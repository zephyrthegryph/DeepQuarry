//! The jobs registry (`rust_core.md` §10): named long-running work
//! (station layout, generation planners, path-search batches) with submit,
//! poll, progress, cancel and results.
//!
//! - Jobs run on their own small pool, never on the frame pool, and yield to
//!   frames: a job calls [`JobCtx::checkpoint`] between steps, which parks
//!   while the owner has flagged a frame as running
//!   ([`JobRegistry::set_frame_busy`]) and reports cancellation.
//! - Every job has a generation tag (its [`JobId`], never reused). A job
//!   submitted with a `key` supersedes (cancels) the previous job with that
//!   key, and a cancelled job's result is dropped when it arrives.
//! - Results are kept until DM takes or finishes them. Completed ids queue
//!   up for [`drain_completed`](JobRegistry::drain_completed), the hook for
//!   the outbox; DM can also just [`poll`](JobRegistry::poll).
//!
//! Core has no statics: the DLL owns one registry (vg-ffi `jobs`).

use std::any::Any;
use std::collections::HashMap;
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::{Arc, Mutex, MutexGuard, PoisonError};
use std::time::{Duration, Instant};

use crate::metrics::{MS_BUCKETS, MetricsRegistry};

/// A job's generation tag. Never reused within a registry.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct JobId(pub u64);

/// What [`JobRegistry::poll`] reports.
#[derive(Clone, Debug, PartialEq)]
pub enum JobStatus {
    /// Queued or running; progress in `0.0..=1.0` as last reported.
    Pending {
        progress: f32,
    },
    Ready,
    Failed(String),
    Cancelled,
    /// Never submitted, or already finished.
    Unknown,
}

/// Returned by [`JobCtx::checkpoint`] once the job is cancelled.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Cancelled;

impl std::fmt::Display for Cancelled {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("job cancelled")
    }
}

impl std::error::Error for Cancelled {}

/// What a running job sees.
pub struct JobCtx {
    id: JobId,
    cancel: Arc<AtomicBool>,
    progress: Arc<AtomicU32>,
    frame_busy: Arc<AtomicBool>,
}

/// Longest a checkpoint parks for a busy frame before letting the job run
/// anyway, so a stuck frame flag cannot starve jobs forever.
const MAX_YIELD: Duration = Duration::from_millis(250);

impl JobCtx {
    #[must_use]
    pub const fn id(&self) -> JobId {
        self.id
    }

    #[must_use]
    pub fn is_cancelled(&self) -> bool {
        self.cancel.load(Ordering::Relaxed)
    }

    /// Reports progress in `0.0..=1.0`.
    pub fn set_progress(&self, p: f32) {
        self.progress
            .store(p.clamp(0.0, 1.0).to_bits(), Ordering::Relaxed);
    }

    /// Call between steps. Parks while a frame is running (jobs sit below
    /// frame tasks in priority), then returns `Err(Cancelled)` if the job
    /// was cancelled or superseded.
    ///
    /// # Errors
    /// If the job was cancelled.
    pub fn checkpoint(&self) -> Result<(), Cancelled> {
        let start = Instant::now();
        while self.frame_busy.load(Ordering::Relaxed)
            && !self.is_cancelled()
            && start.elapsed() < MAX_YIELD
        {
            std::thread::sleep(Duration::from_micros(200));
        }
        if self.is_cancelled() {
            Err(Cancelled)
        } else {
            Ok(())
        }
    }
}

enum State {
    Pending,
    Ready(Box<dyn Any + Send>),
    Failed(String),
    Cancelled,
}

struct Entry {
    name: String,
    key: Option<String>,
    state: State,
    cancel: Arc<AtomicBool>,
    progress: Arc<AtomicU32>,
}

#[derive(Default)]
struct Inner {
    next: u64,
    jobs: HashMap<u64, Entry>,
    by_key: HashMap<String, u64>,
    completed: Vec<JobId>,
}

/// One row of [`JobRegistry::list`].
#[derive(Clone, Debug, PartialEq)]
pub struct JobInfo {
    pub id: JobId,
    pub name: String,
    pub status: JobStatus,
}

/// Submit, poll, cancel and collect long jobs.
pub struct JobRegistry {
    pool: rayon::ThreadPool,
    inner: Arc<Mutex<Inner>>,
    frame_busy: Arc<AtomicBool>,
    metrics: Option<Arc<MetricsRegistry>>,
}

fn lock(inner: &Mutex<Inner>) -> MutexGuard<'_, Inner> {
    inner.lock().unwrap_or_else(PoisonError::into_inner)
}

impl JobRegistry {
    /// A registry with `threads` job threads (named `vg-job-N`).
    ///
    /// # Errors
    /// If the pool cannot be created.
    pub fn new(threads: usize) -> Result<Self, rayon::ThreadPoolBuildError> {
        let pool = rayon::ThreadPoolBuilder::new()
            .num_threads(threads.max(1))
            .thread_name(|i| format!("vg-job-{i}"))
            .build()?;
        Ok(Self {
            pool,
            inner: Arc::new(Mutex::new(Inner {
                next: 1,
                ..Inner::default()
            })),
            frame_busy: Arc::new(AtomicBool::new(false)),
            metrics: None,
        })
    }

    /// Records `jobs.<name>.{submitted,completed,failed,cancelled}` counters
    /// and a `jobs.<name>.ms` histogram into `metrics`.
    #[must_use]
    pub fn with_metrics(mut self, metrics: Arc<MetricsRegistry>) -> Self {
        self.metrics = Some(metrics);
        self
    }

    /// Flags whether a frame is running; checkpoints park while it is.
    pub fn set_frame_busy(&self, busy: bool) {
        self.frame_busy.store(busy, Ordering::Relaxed);
    }

    /// Starts `work` as job `name`. With a `key`, cancels the previous job
    /// submitted under the same key (its result will be dropped).
    pub fn submit<T, F>(&self, name: &str, key: Option<&str>, work: F) -> JobId
    where
        T: Any + Send,
        F: FnOnce(&JobCtx) -> Result<T, String> + Send + 'static,
    {
        let cancel = Arc::new(AtomicBool::new(false));
        let progress = Arc::new(AtomicU32::new(0));
        let id = {
            let mut inner = lock(&self.inner);
            let id = JobId(inner.next);
            inner.next += 1;
            if let Some(key) = key {
                if let Some(old) = inner.by_key.insert(key.to_owned(), id.0) {
                    if let Some(old) = inner.jobs.get(&old) {
                        old.cancel.store(true, Ordering::Relaxed);
                    }
                }
            }
            inner.jobs.insert(
                id.0,
                Entry {
                    name: name.to_owned(),
                    key: key.map(str::to_owned),
                    state: State::Pending,
                    cancel: Arc::clone(&cancel),
                    progress: Arc::clone(&progress),
                },
            );
            id
        };
        let metric = |what: &str| {
            self.metrics
                .as_ref()
                .map(|m| m.counter(&format!("jobs.{name}.{what}")))
        };
        if let Some(c) = metric("submitted") {
            c.inc();
        }
        let done = [metric("completed"), metric("failed"), metric("cancelled")];
        let timing = self
            .metrics
            .as_ref()
            .map(|m| m.histogram(&format!("jobs.{name}.ms"), MS_BUCKETS));
        let ctx = JobCtx {
            id,
            cancel,
            progress,
            frame_busy: Arc::clone(&self.frame_busy),
        };
        let inner = Arc::clone(&self.inner);
        self.pool.spawn(move || {
            let start = Instant::now();
            let state = if ctx.is_cancelled() {
                State::Cancelled
            } else {
                match catch_unwind(AssertUnwindSafe(|| work(&ctx))) {
                    _ if ctx.is_cancelled() => State::Cancelled,
                    Ok(Ok(value)) => State::Ready(Box::new(value)),
                    Ok(Err(error)) => State::Failed(error),
                    Err(payload) => State::Failed(
                        payload
                            .downcast_ref::<&str>()
                            .map(ToString::to_string)
                            .or_else(|| payload.downcast_ref::<String>().cloned())
                            .map_or_else(
                                || "job panicked".to_owned(),
                                |m| format!("job panicked: {m}"),
                            ),
                    ),
                }
            };
            if let Some(h) = &timing {
                h.observe(start.elapsed().as_secs_f64() * 1000.0);
            }
            let slot = match state {
                State::Ready(_) => 0,
                State::Failed(_) => 1,
                _ => 2,
            };
            if let Some(c) = &done[slot] {
                c.inc();
            }
            ctx.set_progress(1.0);
            let mut inner = lock(&inner);
            if let Some(entry) = inner.jobs.get_mut(&ctx.id.0) {
                entry.state = state;
                inner.completed.push(ctx.id);
            }
        });
        id
    }

    /// A job's status. Does not consume anything.
    #[must_use]
    pub fn poll(&self, id: JobId) -> JobStatus {
        let inner = lock(&self.inner);
        inner.jobs.get(&id.0).map_or(JobStatus::Unknown, status_of)
    }

    /// Runs `f` on a ready job's result, if it is ready and of type `T`.
    pub fn with_result<T: Any, R>(&self, id: JobId, f: impl FnOnce(&T) -> R) -> Option<R> {
        let inner = lock(&self.inner);
        match &inner.jobs.get(&id.0)?.state {
            State::Ready(value) => value.downcast_ref::<T>().map(f),
            _ => None,
        }
    }

    /// Removes a ready job and returns its result, if it is of type `T`.
    pub fn take_result<T: Any>(&self, id: JobId) -> Option<T> {
        let mut inner = lock(&self.inner);
        if !matches!(inner.jobs.get(&id.0)?.state, State::Ready(ref v) if v.is::<T>()) {
            return None;
        }
        let entry = remove(&mut inner, id)?;
        match entry.state {
            State::Ready(v) => v.downcast().ok().map(|b| *b),
            _ => None,
        }
    }

    /// Asks a job to stop; its result, if any, is dropped. Returns whether
    /// the job was still pending.
    pub fn cancel(&self, id: JobId) -> bool {
        let mut inner = lock(&self.inner);
        let Some(entry) = inner.jobs.get_mut(&id.0) else {
            return false;
        };
        entry.cancel.store(true, Ordering::Relaxed);
        if matches!(entry.state, State::Pending) {
            true
        } else {
            entry.state = State::Cancelled;
            false
        }
    }

    /// Forgets a job: cancels it if pending and drops its result. Returns
    /// whether it existed.
    pub fn finish(&self, id: JobId) -> bool {
        let mut inner = lock(&self.inner);
        let Some(entry) = remove(&mut inner, id) else {
            return false;
        };
        entry.cancel.store(true, Ordering::Relaxed);
        true
    }

    /// Ids of jobs that finished (ready, failed or cancelled) since the last
    /// call, in completion order.
    pub fn drain_completed(&self) -> Vec<JobId> {
        std::mem::take(&mut lock(&self.inner).completed)
    }

    /// Every known job, by id.
    #[must_use]
    pub fn list(&self) -> Vec<JobInfo> {
        let inner = lock(&self.inner);
        let mut rows: Vec<_> = inner
            .jobs
            .iter()
            .map(|(id, e)| JobInfo {
                id: JobId(*id),
                name: e.name.clone(),
                status: status_of(e),
            })
            .collect();
        rows.sort_by_key(|r| r.id);
        rows
    }

    /// Pending jobs.
    #[must_use]
    pub fn pending(&self) -> usize {
        lock(&self.inner)
            .jobs
            .values()
            .filter(|e| matches!(e.state, State::Pending))
            .count()
    }
}

fn remove(inner: &mut Inner, id: JobId) -> Option<Entry> {
    let entry = inner.jobs.remove(&id.0)?;
    if let Some(key) = &entry.key {
        if inner.by_key.get(key) == Some(&id.0) {
            inner.by_key.remove(key);
        }
    }
    Some(entry)
}

fn status_of(e: &Entry) -> JobStatus {
    match &e.state {
        State::Pending if e.cancel.load(Ordering::Relaxed) => JobStatus::Cancelled,
        State::Pending => JobStatus::Pending {
            progress: f32::from_bits(e.progress.load(Ordering::Relaxed)),
        },
        State::Ready(_) => JobStatus::Ready,
        State::Failed(error) => JobStatus::Failed(error.clone()),
        State::Cancelled => JobStatus::Cancelled,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::mpsc;

    fn wait(reg: &JobRegistry, id: JobId) -> JobStatus {
        let start = Instant::now();
        loop {
            let s = reg.poll(id);
            if !matches!(s, JobStatus::Pending { .. }) || start.elapsed() > Duration::from_secs(10)
            {
                return s;
            }
            std::thread::yield_now();
        }
    }

    #[test]
    fn submit_poll_take() {
        let metrics = Arc::new(MetricsRegistry::new());
        let reg = JobRegistry::new(2)
            .unwrap()
            .with_metrics(Arc::clone(&metrics));
        let id = reg.submit("sum", None, |ctx| {
            ctx.set_progress(0.5);
            ctx.checkpoint().map_err(|e| e.to_string())?;
            Ok((1..=10u32).sum::<u32>())
        });
        assert_eq!(wait(&reg, id), JobStatus::Ready);
        assert_eq!(reg.with_result(id, |v: &u32| *v), Some(55));
        assert_eq!(reg.take_result::<String>(id), None, "wrong type keeps it");
        assert_eq!(reg.take_result::<u32>(id), Some(55));
        assert_eq!(reg.poll(id), JobStatus::Unknown);
        assert_eq!(reg.drain_completed(), vec![id]);
        assert_eq!(metrics.counter("jobs.sum.completed").get(), 1);
    }

    #[test]
    fn failures_and_panics_are_reported() {
        let reg = JobRegistry::new(1).unwrap();
        let a = reg.submit::<(), _>("bad", None, |_| Err("nope".into()));
        let b = reg.submit::<(), _>("boom", None, |_| panic!("kaboom"));
        assert_eq!(wait(&reg, a), JobStatus::Failed("nope".into()));
        assert_eq!(
            wait(&reg, b),
            JobStatus::Failed("job panicked: kaboom".into())
        );
    }

    #[test]
    fn cancel_and_supersede_drop_results() {
        let reg = JobRegistry::new(2).unwrap();
        let (tx, rx) = mpsc::channel::<()>();
        let first = reg.submit("plan", Some("station"), move |ctx| {
            rx.recv().unwrap();
            ctx.checkpoint().map_err(|e| e.to_string())?;
            Ok(1u8)
        });
        let second = reg.submit("plan", Some("station"), |_| Ok(2u8));
        assert_eq!(reg.poll(first), JobStatus::Cancelled);
        tx.send(()).unwrap();
        assert_eq!(wait(&reg, second), JobStatus::Ready);
        let start = Instant::now();
        while !reg.drain_completed().contains(&first) {
            assert!(start.elapsed() < Duration::from_secs(10));
            std::thread::yield_now();
        }
        assert_eq!(reg.poll(first), JobStatus::Cancelled);
        assert_eq!(reg.with_result(first, |v: &u8| *v), None);
        assert!(reg.finish(first));
        assert!(!reg.finish(first));
    }

    #[test]
    fn checkpoint_yields_to_frames() {
        let reg = JobRegistry::new(1).unwrap();
        reg.set_frame_busy(true);
        let id = reg.submit("wait", None, |ctx| {
            let t = Instant::now();
            ctx.checkpoint().map_err(|e| e.to_string())?;
            Ok(t.elapsed())
        });
        std::thread::sleep(Duration::from_millis(20));
        reg.set_frame_busy(false);
        assert_eq!(wait(&reg, id), JobStatus::Ready);
        let parked = reg.take_result::<Duration>(id).unwrap();
        assert!(parked >= Duration::from_millis(10), "{parked:?}");
    }
}

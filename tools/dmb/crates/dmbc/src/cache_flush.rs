//! Background publication of a request's cache batch.
//!
//! The segment a request writes (its new memo records, up to gigabytes after a cold build) used to be published before the
//! request replied, so the client waited for a write nothing in its reply depends on. The daemon now hands the finished spool
//! to a flush thread and replies once the output is installed. Everything that could observe the difference waits for the
//! flush first:
//! * a later request of the same cache root, when it first opens the cache ([`wait`], called by `LazyDisk::writer`);
//! * a later flush of that root (flushes of one root run in order);
//! * the daemon's cache budget pass and its exit (retire, idle exit, supersession: [`wait_all`]).
//!
//! A one-shot compile never defers: it exits when the request ends. A cache that is not published is only a cache miss for the
//! next build (records are content addressed), never a wrong answer, so a crash between reply and flush costs time only.
use std::{
    path::{Path, PathBuf},
    sync::{Arc, Condvar, Mutex},
    time::Instant,
};

/// One flush in flight (or finished): waiters block until it completes, whether it succeeded, failed or panicked.
struct Flight {
    done: Mutex<bool>,
    finished: Condvar,
}
impl Flight {
    fn new() -> Arc<Self> {
        Arc::new(Self { done: Mutex::new(false), finished: Condvar::new() })
    }
    fn wait(&self) {
        let mut done = self.done.lock().unwrap_or_else(|error| error.into_inner());
        while !*done {
            done = self.finished.wait(done).unwrap_or_else(|error| error.into_inner());
        }
    }
    fn complete(&self) {
        *self.done.lock().unwrap_or_else(|error| error.into_inner()) = true;
        self.finished.notify_all();
    }
}
/// Completes its flight when dropped (and forgets it), so a panicking flush still releases everything waiting for it.
struct Completion {
    root: PathBuf,
    flight: Arc<Flight>,
}
impl Drop for Completion {
    fn drop(&mut self) {
        FLIGHTS
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .retain(|(held, current)| !(*held == self.root && Arc::ptr_eq(current, &self.flight)));
        self.flight.complete();
    }
}

/// The newest flight of each cache root.
static FLIGHTS: Mutex<Vec<(PathBuf, Arc<Flight>)>> = Mutex::new(Vec::new());

/// Run `work` (the publication of one batch of `root`) on a background thread, after any earlier flush of the same root.
/// `label` names it in the log. If no thread can be started the work runs here, so a flush is never lost.
pub fn defer(root: PathBuf, label: &'static str, work: impl FnOnce() -> Result<String, String> + Send + 'static) {
    let flight = Flight::new();
    let previous = {
        let mut flights = FLIGHTS.lock().unwrap_or_else(|error| error.into_inner());
        let previous = flights.iter().position(|(held, _)| *held == root).map(|at| flights.remove(at).1);
        flights.push((root.clone(), Arc::clone(&flight)));
        previous
    };
    let job = {
        let flight = Arc::clone(&flight);
        move || {
            let _completion = Completion { root, flight };
            if let Some(previous) = previous {
                previous.wait();
            }
            let started = Instant::now();
            match work() {
                Ok(summary) => crate::daemon_eprintln!(
                    "native cache flush ({label}): {summary} in {:.2}s (background)",
                    started.elapsed().as_secs_f64()
                ),
                Err(error) => crate::daemon_eprintln!("native cache flush ({label}) skipped: {error}"),
            }
        }
    };
    // The closure runs exactly once: on the flush thread when it starts, on this thread otherwise.
    let slot = Arc::new(Mutex::new(Some(job)));
    let for_thread = Arc::clone(&slot);
    let started = std::thread::Builder::new().name("cache-flush".into()).spawn(move || {
        let job = for_thread.lock().unwrap_or_else(|error| error.into_inner()).take();
        if let Some(job) = job {
            job();
        }
    });
    if started.is_err() {
        let job = slot.lock().unwrap_or_else(|error| error.into_inner()).take();
        if let Some(job) = job {
            job();
        }
    }
}
/// Block until the flush in flight for `root`, if any, has finished.
pub fn wait(root: &Path) {
    let flight = FLIGHTS
        .lock()
        .unwrap_or_else(|error| error.into_inner())
        .iter()
        .find(|(held, _)| held == root)
        .map(|(_, flight)| Arc::clone(flight));
    if let Some(flight) = flight {
        flight.wait();
    }
}
/// Block until every flush in flight has finished (the cache budget pass, retire and exit).
pub fn wait_all() {
    let all: Vec<Arc<Flight>> = FLIGHTS
        .lock()
        .unwrap_or_else(|error| error.into_inner())
        .iter()
        .map(|(_, flight)| Arc::clone(flight))
        .collect();
    for flight in all {
        flight.wait();
    }
}
/// Flushes in flight.
pub fn pending() -> usize {
    FLIGHTS.lock().unwrap_or_else(|error| error.into_inner()).len()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{atomic::{AtomicBool, AtomicUsize, Ordering::SeqCst}, mpsc};
    use std::time::Duration;

    fn root(name: &str) -> PathBuf {
        PathBuf::from(format!("cache-flush-test/{name}-{}", std::process::id()))
    }
    /// A flush that stays in flight until the returned sender is used.
    fn gated(root: &Path, finished: &Arc<AtomicBool>) -> mpsc::Sender<()> {
        let (release, gate) = mpsc::channel::<()>();
        let finished = Arc::clone(finished);
        defer(root.to_path_buf(), "test", move || {
            let _ = gate.recv();
            finished.store(true, SeqCst);
            Ok("gated".into())
        });
        release
    }
    /// Runs `waiter` on another thread and reports whether it returned within `grace`.
    fn returns_within(grace: Duration, waiter: impl FnOnce() + Send + 'static) -> bool {
        let (done, returned) = mpsc::channel::<()>();
        std::thread::spawn(move || {
            waiter();
            let _ = done.send(());
        });
        returned.recv_timeout(grace).is_ok()
    }

    #[test]
    fn a_later_request_of_the_same_root_waits_for_the_flush() {
        let root = root("same-root");
        let finished = Arc::new(AtomicBool::new(false));
        let release = gated(&root, &finished);
        let waiting = root.clone();
        let seen_finished = Arc::clone(&finished);
        // The reader does not return while the flush is in flight ...
        assert!(!returns_within(Duration::from_millis(200), move || wait(&waiting)));
        // ... and returns, with the flush finished, once it ends.
        let waiting = root.clone();
        let (done, returned) = mpsc::channel::<bool>();
        std::thread::spawn(move || {
            wait(&waiting);
            let _ = done.send(seen_finished.load(SeqCst));
        });
        release.send(()).unwrap();
        assert!(returned.recv_timeout(Duration::from_secs(10)).unwrap());
    }

    #[test]
    fn another_root_is_not_blocked() {
        let held = root("blocked-root");
        let other = root("free-root");
        let finished = Arc::new(AtomicBool::new(false));
        let release = gated(&held, &finished);
        assert!(returns_within(Duration::from_secs(5), move || wait(&other)));
        release.send(()).unwrap();
        wait(&held);
    }

    #[test]
    fn flushes_of_one_root_run_in_order() {
        let root = root("ordered");
        let order = Arc::new(Mutex::new(Vec::<u8>::new()));
        let first_done = Arc::new(AtomicBool::new(false));
        let release = gated(&root, &first_done);
        let second = Arc::clone(&order);
        let first_seen = Arc::clone(&first_done);
        defer(root.clone(), "second", move || {
            // The second flush starts only after the first has finished.
            second.lock().unwrap().push(u8::from(first_seen.load(SeqCst)));
            Ok("second".into())
        });
        std::thread::sleep(Duration::from_millis(150));
        assert!(order.lock().unwrap().is_empty(), "the second flush ran before the first ended");
        release.send(()).unwrap();
        wait(&root);
        assert_eq!(*order.lock().unwrap(), vec![1]);
    }

    #[test]
    fn retire_and_exit_wait_for_every_flush() {
        let roots = [root("exit-a"), root("exit-b")];
        let finished = [Arc::new(AtomicBool::new(false)), Arc::new(AtomicBool::new(false))];
        let releases = [gated(&roots[0], &finished[0]), gated(&roots[1], &finished[1])];
        assert!(!returns_within(Duration::from_millis(200), wait_all));
        let (done, returned) = mpsc::channel::<(bool, bool)>();
        let seen = [Arc::clone(&finished[0]), Arc::clone(&finished[1])];
        std::thread::spawn(move || {
            wait_all();
            let _ = done.send((seen[0].load(SeqCst), seen[1].load(SeqCst)));
        });
        for release in releases {
            release.send(()).unwrap();
        }
        assert_eq!(returned.recv_timeout(Duration::from_secs(10)).unwrap(), (true, true));
    }

    #[test]
    fn a_failed_or_panicking_flush_still_releases_its_waiters() {
        let failing = root("failing");
        defer(failing.clone(), "failing", || Err("disk full".into()));
        wait(&failing);
        let panicking = root("panicking");
        defer(panicking.clone(), "panicking", || panic!("flush panic (expected by the test)"));
        assert!(returns_within(Duration::from_secs(10), move || wait(&panicking)));
        // And a later flush of that root still runs.
        let ran = Arc::new(AtomicUsize::new(0));
        let counted = Arc::clone(&ran);
        defer(root("panicking"), "after", move || {
            counted.fetch_add(1, SeqCst);
            Ok("after".into())
        });
        wait(&root("panicking"));
        assert_eq!(ran.load(SeqCst), 1);
    }
}

//! Reuse ordinary request-bracketed executors across daemon hosts. This is an
//! ownership inventory, not a scheduler: daemon request permits remain authoritative.
use dm_exec::BuildExecutor;
use std::{
    collections::VecDeque,
    sync::{Arc, Condvar, Mutex},
    time::{Duration, Instant},
};

const MAX_WORKERS: usize = 8;
const IDLE: Duration = Duration::from_secs(30);
struct Idle {
    executor: BuildExecutor,
    since: Instant,
}
#[derive(Default)]
struct State {
    physical: usize,
    idle: VecDeque<Idle>,
}
#[derive(Default)]
pub(crate) struct ExecutorPools {
    state: Mutex<State>,
    changed: Condvar,
}
pub(crate) struct ExecutorLease {
    owner: Arc<ExecutorPools>,
    executor: Option<BuildExecutor>,
}
impl ExecutorLease {
    pub(crate) fn executor(&mut self) -> &mut BuildExecutor {
        self.executor.as_mut().expect("live executor lease")
    }
}
impl Drop for ExecutorLease {
    fn drop(&mut self) {
        if let Some(executor) = self.executor.take() {
            let mut state = self
                .owner
                .state
                .lock()
                .unwrap_or_else(|error| error.into_inner());
            state.idle.push_back(Idle {
                executor,
                since: Instant::now(),
            });
            drop(state);
            self.owner.changed.notify_all();
        }
    }
}
impl ExecutorPools {
    #[cfg(test)]
    pub(crate) fn physical_workers(&self) -> usize {
        self.state.lock().unwrap().physical
    }
    pub(crate) fn checkout(
        self: &Arc<Self>,
        workers: usize,
    ) -> Result<ExecutorLease, Box<dyn std::error::Error>> {
        let normal = Instant::now() + Duration::from_secs(600);
        let deadline = crate::daemon::control::current_deadline()
            .map_or(normal, |deadline| deadline.min(normal));
        self.checkout_until(workers, deadline)
    }
    fn checkout_until(
        self: &Arc<Self>,
        workers: usize,
        deadline: Instant,
    ) -> Result<ExecutorLease, Box<dyn std::error::Error>> {
        let workers = workers.max(1);
        if workers > MAX_WORKERS {
            return Err("daemon executor inventory supports at most eight workers".into());
        }
        loop {
            crate::daemon::control::checkpoint()?;
            let mut state = self.state.lock().unwrap_or_else(|error| error.into_inner());
            if let Some(index) = state
                .idle
                .iter()
                .position(|pool| pool.executor.workers() == workers)
            {
                let pool = state.idle.remove(index).expect("idle index");
                return Ok(ExecutorLease {
                    owner: Arc::clone(self),
                    executor: Some(pool.executor),
                });
            }
            if state.physical + workers <= MAX_WORKERS {
                // Reservations and retiring threads count until spawn or join completes.
                state.physical += workers;
                drop(state);
                match BuildExecutor::new_unbound(workers) {
                    Ok(executor) => {
                        return Ok(ExecutorLease {
                            owner: Arc::clone(self),
                            executor: Some(executor),
                        })
                    }
                    Err(error) => {
                        let mut state =
                            self.state.lock().unwrap_or_else(|error| error.into_inner());
                        state.physical -= workers;
                        drop(state);
                        self.changed.notify_all();
                        return Err(error.into());
                    }
                }
            }
            if let Some(idle) = state.idle.pop_front() {
                drop(state);
                self.release(vec![idle]);
                continue;
            }
            if Instant::now() >= deadline {
                return Err(std::io::Error::new(
                    std::io::ErrorKind::TimedOut,
                    "daemon executor admission deadline expired",
                )
                .into());
            }
            let (state, _) = self
                .changed
                .wait_timeout(state, Duration::from_millis(100))
                .unwrap_or_else(|error| error.into_inner());
            drop(state);
        }
    }
    fn release(&self, idle: Vec<Idle>) {
        let workers = idle
            .iter()
            .map(|pool| pool.executor.workers())
            .sum::<usize>();
        // The reservation remains charged while every old OS worker is joined.
        drop(idle);
        let mut state = self.state.lock().unwrap_or_else(|error| error.into_inner());
        state.physical -= workers;
        drop(state);
        self.changed.notify_all();
    }
    pub(crate) fn trim(&self, now: Instant, pressured: bool) {
        let mut state = self.state.lock().unwrap_or_else(|error| error.into_inner());
        let mut retired = Vec::new();
        while state
            .idle
            .front()
            .is_some_and(|pool| pressured || now.saturating_duration_since(pool.since) >= IDLE)
        {
            retired.push(state.idle.pop_front().expect("idle front"));
        }
        drop(state);
        self.release(retired);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn ids(executor: &mut BuildExecutor) -> std::collections::HashSet<std::thread::ThreadId> {
        let barrier = std::sync::Barrier::new(executor.workers());
        let ids = Mutex::new(std::collections::HashSet::new());
        executor
            .with_request(None, |executor| {
                executor.scope(|scope| {
                    for _ in 0..executor.workers() {
                        let ids = &ids;
                        let barrier = &barrier;
                        scope.spawn(move |_| {
                            ids.lock().unwrap().insert(std::thread::current().id());
                            barrier.wait();
                        });
                    }
                })
            })
            .unwrap();
        ids.into_inner().unwrap()
    }
    #[test]
    fn requests_reuse_physical_workers_and_incompatible_idle_pools_join_before_growth() {
        let owner = Arc::new(ExecutorPools::default());
        let mut first = owner.checkout(2).unwrap();
        let first_ids = ids(first.executor());
        drop(first);
        let mut next = owner.checkout(2).unwrap();
        assert_eq!(first_ids, ids(next.executor()));
        drop(next);
        let eight = owner.checkout(8).unwrap();
        assert_eq!(owner.state.lock().unwrap().physical, 8);
        assert!(owner.state.lock().unwrap().idle.is_empty());
        drop(eight);
        owner.trim(Instant::now() + IDLE, false);
        assert_eq!(owner.state.lock().unwrap().physical, 0);
    }
    #[test]
    fn panic_returns_unbound_pool_and_active_pool_is_never_trimmed() {
        let owner = Arc::new(ExecutorPools::default());
        let mut lease = owner.checkout(2).unwrap();
        owner.trim(Instant::now() + IDLE, true);
        assert_eq!(owner.state.lock().unwrap().physical, 2);
        let outcome = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            lease
                .executor()
                .with_request(None, |_| panic!("scoped request failure"))
                .unwrap();
        }));
        assert!(outcome.is_err());
        drop(lease);
        let mut next = owner.checkout(2).unwrap();
        assert_eq!(ids(next.executor()).len(), 2);
        drop(next);
        owner.trim(Instant::now(), true);
        assert_eq!(owner.state.lock().unwrap().physical, 0);
    }
    #[test]
    fn six_concurrent_requests_complete_with_no_more_than_eight_physical_workers() {
        let owner = Arc::new(ExecutorPools::default());
        let start = Arc::new(std::sync::Barrier::new(7));
        let gate = Arc::new((Mutex::new(false), Condvar::new()));
        let (send, receive) = std::sync::mpsc::channel();
        let deadline = Instant::now() + Duration::from_secs(10);
        let handles = (0..6)
            .map(|_| {
                let owner = Arc::clone(&owner);
                let start = Arc::clone(&start);
                let gate = Arc::clone(&gate);
                let send = send.clone();
                std::thread::spawn(move || {
                    start.wait();
                    let mut lease = match owner.checkout_until(2, deadline) {
                        Ok(lease) => lease,
                        Err(error) => {
                            let _ = send.send((2, error.to_string()));
                            return;
                        }
                    };
                    let _ = send.send((0, owner.physical_workers().to_string()));
                    let (ready, changed) = &*gate;
                    let mut released = ready.lock().unwrap();
                    while !*released && Instant::now() < deadline {
                        released = changed
                            .wait_timeout(released, Duration::from_millis(50))
                            .unwrap()
                            .0;
                    }
                    drop(released);
                    let ids = ids(lease.executor());
                    drop(lease);
                    let _ = send.send((1, ids.len().to_string()));
                })
            })
            .collect::<Vec<_>>();
        drop(send);
        start.wait();
        let mut admissions = 0;
        let mut completed = 0;
        let mut errors = Vec::new();
        while admissions < 4 {
            match receive.recv_timeout(Duration::from_secs(5)) {
                Ok((0, workers)) => {
                    admissions += 1;
                    if workers.parse::<usize>().unwrap() > 8 {
                        errors.push(workers);
                    }
                }
                Ok((kind, message)) => {
                    errors.push(format!("unexpected event {kind}: {message}"));
                    break;
                }
                Err(error) => {
                    errors.push(error.to_string());
                    break;
                }
            }
        }
        // Always release before assertions/join, including a failing fixture.
        *gate.0.lock().unwrap() = true;
        gate.1.notify_all();
        while completed < 6 {
            match receive.recv_timeout(Duration::from_secs(10)) {
                Ok((0, workers)) => {
                    admissions += 1;
                    if workers.parse::<usize>().unwrap() > 8 {
                        errors.push(workers);
                    }
                }
                Ok((1, workers)) => {
                    completed += 1;
                    if workers != "2" {
                        errors.push(workers);
                    }
                }
                Ok((_, message)) => {
                    errors.push(message);
                    completed += 1;
                }
                Err(error) => {
                    errors.push(error.to_string());
                    break;
                }
            }
        }
        for handle in handles {
            if handle.join().is_err() {
                errors.push("request thread panicked".into());
            }
        }
        assert!(errors.is_empty(), "{errors:?}");
        assert_eq!((admissions, completed), (6, 6));
        assert!(owner.physical_workers() <= 8);
        owner.trim(Instant::now(), true);
        assert_eq!(owner.physical_workers(), 0);
    }
}

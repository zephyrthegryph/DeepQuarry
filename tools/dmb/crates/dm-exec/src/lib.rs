//! One bounded execution boundary shared by every parallel stage of a build.
//!
//! Jobs may borrow build data. Scope completion joins all jobs, including on
//! panic; dropping the executor terminates and joins its actual OS workers.
//! There is no global Rayon pool or hardware-dependent worker-count cap.
mod weighted;
pub use weighted::weighted_ranges;

use rayon::{Scope, ThreadPool, ThreadPoolBuildError, ThreadPoolBuilder};
use std::sync::{Arc, Mutex};
use std::thread::JoinHandle;

/// Construction rejects an unsupported exact count instead of silently letting
/// Rayon truncate it, and reports OS thread creation failures separately.
#[derive(Debug)]
pub enum ExecutorError {
    InvalidWorkerCount { requested: usize, maximum: usize },
    ThreadPool(ThreadPoolBuildError),
}

impl std::fmt::Display for ExecutorError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::InvalidWorkerCount { requested, maximum } => {
                write!(formatter,
                "requested {requested} compiler workers exceeds the supported maximum {maximum}")
            }
            Self::ThreadPool(error) => write!(formatter, "compiler worker pool: {error}"),
        }
    }
}

impl std::error::Error for ExecutorError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::InvalidWorkerCount { .. } => None,
            Self::ThreadPool(error) => Some(error),
        }
    }
}

pub struct BuildExecutor {
    pool: Option<ThreadPool>,
    handles: Arc<Mutex<Vec<JoinHandle<()>>>>,
    workers: usize,
}

/// Borrowed Rayon scope whose every explicit job inherits the caller's stages.
pub struct BuildScope<'borrow, 'scope> {
    inner: &'borrow Scope<'scope>,
}
impl<'scope> BuildScope<'_, 'scope> {
    pub fn spawn<F>(&self, operation: F)
    where
        F: FnOnce(&BuildScope<'_, 'scope>) + Send + 'scope,
    {
        let context = dm_profile::StageContext::capture();
        self.inner.spawn(move |inner| {
            let _context = context.enter();
            operation(&BuildScope { inner });
        });
    }
}

impl BuildExecutor {
    /// Zero requests one worker rather than Rayon's implicit hardware count.
    pub fn new(workers: usize) -> Result<Self, ExecutorError> {
        let workers = workers.max(1);
        let maximum = rayon::max_num_threads();
        if workers > maximum {
            return Err(ExecutorError::InvalidWorkerCount {
                requested: workers,
                maximum,
            });
        }
        // Never reserve from a user-controlled count. Successful worker spawns
        // grow this ledger, and ordinary OS failures remain fallible.
        let handles = Arc::new(Mutex::new(Vec::new()));
        let spawned = Arc::clone(&handles);
        let result = ThreadPoolBuilder::new()
            .num_threads(workers)
            .thread_name(|index| format!("dm-build-{index}"))
            .spawn_handler(move |thread| {
                let mut builder = std::thread::Builder::new();
                if let Some(name) = thread.name() {
                    builder = builder.name(name.to_owned());
                }
                if let Some(size) = thread.stack_size() {
                    builder = builder.stack_size(size);
                }
                let handle = builder.spawn(move || {
                    let _lifetime = dm_profile::worker_lifetime("compiler.worker_lifetime");
                    thread.run();
                })?;
                spawned
                    .lock()
                    .unwrap_or_else(|e| e.into_inner())
                    .push(handle);
                Ok(())
            })
            .build();
        match result {
            Ok(pool) => Ok(Self {
                pool: Some(pool),
                handles,
                workers,
            }),
            Err(error) => {
                // Rayon has released its partial registry before returning an
                // error; still join every worker it successfully started.
                join_workers(&handles);
                Err(ExecutorError::ThreadPool(error))
            }
        }
    }

    pub fn workers(&self) -> usize {
        self.workers
    }

    /// Runs the scope body on the calling thread and its spawned jobs on the
    /// build's pool. The body and return value need not be Send.
    pub fn scope<'scope, F, R>(&self, operation: F) -> R
    where
        F: FnOnce(&BuildScope<'_, 'scope>) -> R,
    {
        self.pool
            .as_ref()
            .expect("live build executor")
            .in_place_scope(|inner| operation(&BuildScope { inner }))
    }

    pub fn scope_in_place<'scope, F, R>(&self, operation: F) -> R
    where
        F: FnOnce(&BuildScope<'_, 'scope>) -> R,
    {
        self.scope(operation)
    }

    /// Installs parallel iterator/join operations in this pool, never in the
    /// process-global Rayon registry.
    pub fn install<F, R>(&self, operation: F) -> R
    where
        F: FnOnce() -> R + Send,
        R: Send,
    {
        let context = dm_profile::StageContext::capture();
        self.pool
            .as_ref()
            .expect("live build executor")
            .install(move || {
                let _context = context.enter();
                operation()
            })
    }

    /// Explicit consuming shutdown for callers immediately before a profiler
    /// finish. Normal Drop provides the same guarantee on early returns.
    pub fn shutdown(self) {}
}

impl Drop for BuildExecutor {
    fn drop(&mut self) {
        // A ThreadPool drop signals termination but does not join OS threads.
        // Releasing it before joining ensures lifetime observations have landed
        // before the caller snapshots independent process CPU.
        drop(self.pool.take());
        join_workers(&self.handles);
    }
}

fn join_workers(handles: &Mutex<Vec<JoinHandle<()>>>) {
    let handles = std::mem::take(&mut *handles.lock().unwrap_or_else(|e| e.into_inner()));
    for handle in handles {
        // Scoped job panics have already propagated to their scope caller.
        // Never introduce a second panic while unwinding that caller.
        let _ = handle.join();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashSet;
    use std::sync::atomic::{AtomicUsize, Ordering};

    #[test]
    fn scoped_jobs_borrow_disjoint_output() {
        let executor = BuildExecutor::new(3).unwrap();
        let mut output = [0; 16];
        executor.scope(|scope| {
            for (index, slot) in output.iter_mut().enumerate() {
                scope.spawn(move |_| *slot = index + 1);
            }
        });
        assert_eq!(output.iter().sum::<usize>(), 136);
    }

    #[test]
    fn stages_reuse_bounded_worker_identities() {
        let executor = BuildExecutor::new(3).unwrap();
        let identities = Mutex::new(HashSet::new());
        for _ in 0..8 {
            executor.scope(|scope| {
                for _ in 0..32 {
                    scope.spawn(|_| {
                        identities
                            .lock()
                            .unwrap()
                            .insert(std::thread::current().id());
                    });
                }
            });
        }
        assert!((1..=3).contains(&identities.into_inner().unwrap().len()));
        assert_eq!(executor.workers(), 3);
    }

    #[test]
    fn panic_waits_for_other_borrowed_jobs_and_pool_remains_usable() {
        let executor = BuildExecutor::new(2).unwrap();
        let completed = AtomicUsize::new(0);
        let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            executor.scope(|scope| {
                scope.spawn(|_| panic!("intentional scoped panic"));
                for _ in 0..16 {
                    scope.spawn(|_| {
                        completed.fetch_add(1, Ordering::SeqCst);
                    });
                }
            });
        }));
        assert!(result.is_err());
        assert_eq!(completed.load(Ordering::SeqCst), 16);
        assert_eq!(executor.install(|| 42), 42);
        executor.shutdown();
    }

    #[test]
    fn zero_never_selects_hardware_parallelism() {
        assert_eq!(BuildExecutor::new(0).unwrap().workers(), 1);
    }

    #[test]
    fn unsupported_count_fails_before_allocation_or_spawning() {
        let result = std::panic::catch_unwind(|| BuildExecutor::new(usize::MAX));
        assert!(matches!(
            result,
            Ok(Err(ExecutorError::InvalidWorkerCount {
                requested: usize::MAX,
                ..
            }))
        ));
    }
}

//! A rayon pool whose threads can be joined: the DLL must not unload while
//! one of its threads still runs (BYOND frees the library at shutdown, and a
//! pool thread left winding down then executes unmapped code).
use std::sync::{Arc, Mutex};
use std::thread::JoinHandle;

/// A named rayon pool, joined on [`Pool::shutdown`]. Dropping it only stops it.
pub struct Pool {
    pool: Option<rayon::ThreadPool>,
    threads: Arc<Mutex<Vec<JoinHandle<()>>>>,
}

impl Pool {
    /// `threads` threads named `{name}-N`.
    ///
    /// # Errors
    /// If the pool cannot be created.
    pub fn new(threads: usize, name: &'static str) -> Result<Self, rayon::ThreadPoolBuildError> {
        let handles = Arc::new(Mutex::new(Vec::new()));
        let spawned = Arc::clone(&handles);
        let pool = rayon::ThreadPoolBuilder::new()
            .num_threads(threads.max(1))
            .spawn_handler(move |t| {
                let h = std::thread::Builder::new()
                    .name(format!("{name}-{}", t.index()))
                    .spawn(move || t.run())?;
                spawned
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                    .push(h);
                Ok(())
            })
            .build()?;
        Ok(Self {
            pool: Some(pool),
            threads: handles,
        })
    }

    /// False once [`Pool::shutdown`] has run.
    #[must_use]
    pub fn is_running(&self) -> bool {
        self.pool.is_some()
    }

    /// Runs `f` on the pool; a no-op after [`Pool::shutdown`].
    pub fn spawn(&self, f: impl FnOnce() + Send + 'static) {
        if let Some(p) = &self.pool {
            p.spawn(f);
        }
    }

    /// Runs `f` inside the pool and returns its result.
    ///
    /// # Panics
    /// After [`Pool::shutdown`].
    pub fn install<R: Send>(&self, f: impl FnOnce() -> R + Send) -> R {
        self.pool.as_ref().expect("pool shut down").install(f)
    }

    /// Stops the pool once its queued work is done and joins every thread.
    pub fn shutdown(&mut self) {
        drop(self.pool.take());
        let me = std::thread::current().id();
        let handles = std::mem::take(
            &mut *self
                .threads
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner),
        );
        for h in handles {
            if h.thread().id() != me {
                let _ = h.join();
            }
        }
    }
}

// No `Drop` join: a pool dropped from a thread-local destructor would join
// under the Windows loader lock, which the exiting threads also need.
// Owners that must outlive no thread call [`Pool::shutdown`] explicitly.

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};

    #[test]
    fn shutdown_finishes_queued_work_and_joins() {
        let mut pool = Pool::new(2, "test").unwrap();
        let n = Arc::new(AtomicUsize::new(0));
        for _ in 0..8 {
            let n = Arc::clone(&n);
            pool.spawn(move || {
                n.fetch_add(1, Ordering::SeqCst);
            });
        }
        pool.shutdown();
        assert_eq!(n.load(Ordering::SeqCst), 8);
        assert!(pool.threads.lock().unwrap().is_empty());
    }
}

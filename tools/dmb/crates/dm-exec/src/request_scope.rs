//! Exclusive request brackets over the same persistent physical worker pool.
use super::BuildExecutor;
use dm_profile::{RequestContext, RequestContextGuard, WorkerLifetime};
use std::{
    cell::RefCell,
    sync::atomic::{AtomicU64, Ordering},
};
static NEXT_ID: AtomicU64 = AtomicU64::new(1);
pub(super) fn identity() -> u64 {
    NEXT_ID.fetch_add(1, Ordering::Relaxed)
}
struct WorkerBinding {
    lifetime: Option<WorkerLifetime>,
    context: Option<RequestContextGuard>,
}
impl Drop for WorkerBinding {
    fn drop(&mut self) {
        self.lifetime.take();
        self.context.take();
    }
}
thread_local! {static BINDINGS:RefCell<Vec<(u64,WorkerBinding)>>=const{RefCell::new(Vec::new())};}
#[derive(Debug)]
pub struct RequestError(String);
impl std::fmt::Display for RequestError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}
impl std::error::Error for RequestError {}
struct Bracket<'a> {
    executor: &'a BuildExecutor,
}
impl Drop for Bracket<'_> {
    fn drop(&mut self) {
        self.executor.request_active.store(false, Ordering::Release);
        let id = self.executor.identity;
        self.executor
            .pool
            .as_ref()
            .expect("live executor")
            .broadcast(move |_| {
                BINDINGS.with(|bindings| {
                    let mut bindings = bindings.borrow_mut();
                    if let Some(index) = bindings.iter().position(|(key, _)| *key == id) {
                        drop(bindings.remove(index));
                    }
                });
            });
    }
}
impl BuildExecutor {
    /// Binds all workers for one request; every borrowed job joins before release.
    /// This API is for unbound pools only. It never permits concurrent requests.
    pub fn with_request<F, R>(
        &mut self,
        request: Option<&RequestContext>,
        operation: F,
    ) -> Result<R, RequestError>
    where
        F: FnOnce(&BuildExecutor) -> R,
    {
        if !self.unbound {
            return Err(RequestError(
                "request brackets require an unbound executor".into(),
            ));
        }
        let pool = self.pool.as_ref().expect("live executor");
        if pool.current_thread_index().is_some() {
            return Err(RequestError(
                "request bracket cannot start on its own worker".into(),
            ));
        }
        if request.is_none() && RequestContext::capture().is_some() {
            return Err(RequestError(
                "active profiling request requires an explicit request token".into(),
            ));
        }
        let coordinator = request
            .map(RequestContext::enter)
            .transpose()
            .map_err(RequestError)?;
        let id = self.identity;
        let results = pool.broadcast(|_| -> Result<(), String> {
            BINDINGS.with(|bindings| -> Result<(), String> {
                if !bindings.borrow().is_empty() {
                    return Err("worker already belongs to a request bracket".into());
                }
                let context = request.map(RequestContext::enter).transpose()?;
                let lifetime =
                    request.map(|_| dm_profile::worker_lifetime("compiler.worker_lifetime"));
                bindings
                    .borrow_mut()
                    .push((id, WorkerBinding { lifetime, context }));
                Ok(())
            })
        });
        let bracket = Bracket { executor: self };
        if let Some(error) = results.into_iter().find_map(Result::err) {
            drop(bracket);
            drop(coordinator);
            return Err(RequestError(error));
        }
        self.request_active.store(true, Ordering::Release);
        // The bracket is destroyed during unwinding after every scope's jobs join.
        let result = operation(self);
        drop(bracket);
        drop(coordinator);
        Ok(result)
    }
}
#[cfg(test)]
#[path = "request_scope_tests.rs"]
mod tests;

//! Exact request routing. Concurrent process-counter certification is rejected.
use super::{State, STACK};
use std::{
    cell::RefCell,
    marker::PhantomData,
    rc::Rc,
    sync::{atomic::Ordering, Arc, Mutex, OnceLock, Weak},
};
use tracing_subscriber::prelude::*;
static ACTIVE: Mutex<Option<Weak<State>>> = Mutex::new(None);
static TRACING: OnceLock<Result<(), String>> = OnceLock::new();
thread_local! { static REQUEST: RefCell<Option<RequestContext>> = const { RefCell::new(None) }; }
pub(super) fn initialize_tracing() -> Result<(), String> {
    TRACING
        .get_or_init(|| {
            tracing_subscriber::registry()
                .with(super::names::Names)
                .try_init()
                .map_err(|error| error.to_string())
        })
        .clone()
}
pub(super) fn active_state() -> Option<Arc<State>> {
    REQUEST.with(|request| {
        request
            .borrow()
            .as_ref()
            .filter(|context| !context.state.finished.load(Ordering::Acquire))
            .map(|context| Arc::clone(&context.state))
    })
}

#[derive(Clone)]
pub struct RequestContext {
    state: Arc<State>,
    dispatch: tracing::Dispatch,
}
impl std::fmt::Debug for RequestContext {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("RequestContext")
            .field("finished", &self.state.finished.load(Ordering::Acquire))
            .finish_non_exhaustive()
    }
}
impl PartialEq for RequestContext {
    fn eq(&self, other: &Self) -> bool {
        Arc::ptr_eq(&self.state, &other.state)
    }
}
impl Eq for RequestContext {}
impl RequestContext {
    pub(super) fn from_state(state: &Arc<State>) -> Option<Self> {
        let dispatch = state
            .dispatch
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .clone()?;
        Some(Self {
            state: Arc::clone(state),
            dispatch,
        })
    }
    pub fn capture() -> Option<Self> {
        from_active()
    }
    /// Thread-bound binding; enter before creating request stages, drop after them.
    pub fn enter(&self) -> Result<RequestContextGuard, String> {
        let lifecycle = self
            .state
            .dispatch
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        if self.state.finished.load(Ordering::Acquire) {
            return Err("profiling request has finished".into());
        }
        let prior = REQUEST.with(|request| request.borrow().clone());
        if !STACK.with(|stack| stack.borrow().is_empty())
            && prior.as_ref().is_none_or(|old| old != self)
        {
            return Err("cannot change profiling request across an active stage stack".into());
        }
        self.state.bindings.fetch_add(1, Ordering::AcqRel);
        drop(lifecycle);
        let dispatch = tracing::dispatcher::set_default(&self.dispatch);
        REQUEST.with(|request| *request.borrow_mut() = Some(self.clone()));
        Ok(RequestContextGuard {
            prior,
            state: Arc::clone(&self.state),
            dispatch: Some(dispatch),
            thread_bound: PhantomData,
        })
    }
}
fn from_active() -> Option<RequestContext> {
    RequestContext::from_state(&active_state()?)
}
pub struct RequestContextGuard {
    prior: Option<RequestContext>,
    state: Arc<State>,
    dispatch: Option<tracing::dispatcher::DefaultGuard>,
    thread_bound: PhantomData<Rc<()>>,
}
impl Drop for RequestContextGuard {
    fn drop(&mut self) {
        REQUEST.with(|request| *request.borrow_mut() = self.prior.take());
        self.dispatch.take();
        self.state.bindings.fetch_sub(1, Ordering::AcqRel);
    }
}
pub(super) struct RequestLease {
    state: Arc<State>,
}
impl RequestLease {
    pub(super) fn claim(state: Arc<State>) -> Result<Self, String> {
        if !STACK.with(|stack| stack.borrow().is_empty()) {
            return Err("profiling request starts with an active stage stack".into());
        }
        let mut active = ACTIVE.lock().unwrap_or_else(|e| e.into_inner());
        if active.as_ref().and_then(Weak::upgrade).is_some_and(|old| {
            !old.finished.load(Ordering::Acquire)
                || old.workers.load(Ordering::Acquire) != 0
                || old.bindings.load(Ordering::Acquire) != 0
                || old
                    .entries
                    .lock()
                    .unwrap_or_else(|e| e.into_inner())
                    .values()
                    .any(|e| e.active != 0)
        }) {
            return Err("concurrent profiling requests cannot certify process counters".into());
        }
        *active = Some(Arc::downgrade(&state));
        Ok(Self { state })
    }
    pub(super) fn begin_close(&self) {
        let _lifecycle = self
            .state
            .dispatch
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        self.state.finished.store(true, Ordering::Release);
    }
    pub(super) fn close(&self) {
        self.begin_close();
        self.state
            .dispatch
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .take();
        let mut active = ACTIVE.lock().unwrap_or_else(|e| e.into_inner());
        if active
            .as_ref()
            .and_then(Weak::upgrade)
            .is_some_and(|state| {
                Arc::ptr_eq(&state, &self.state)
                    && state.workers.load(Ordering::Acquire) == 0
                    && state.bindings.load(Ordering::Acquire) == 0
                    && !state
                        .entries
                        .lock()
                        .unwrap_or_else(|e| e.into_inner())
                        .values()
                        .any(|e| e.active != 0)
            })
        {
            *active = None;
        }
    }
}
impl Drop for RequestLease {
    fn drop(&mut self) {
        self.close();
    }
}

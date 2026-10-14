//! Transfer exact request and stage ancestry; clocks remain on executing threads.
use super::{stage, RequestContext, RequestContextGuard, StageGuard, STACK};

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct StageContext {
    names: Vec<&'static str>,
    request: Option<RequestContext>,
}
impl StageContext {
    /// Disabled profiling returns an empty context without allocating stage ancestry.
    pub fn capture() -> Self {
        let request = RequestContext::capture();
        if request.is_none() {
            return Self::default();
        }
        Self {
            request,
            names: STACK.with(|stack| stack.borrow().iter().map(|frame| frame.name).collect()),
        }
    }
    pub fn enter(&self) -> StageContextGuard {
        let request = self.request.as_ref().map(|request| {
            request
                .enter()
                .expect("scoped profiling request must remain live until jobs join")
        });
        if self.names.is_empty() {
            return StageContextGuard {
                guards: Vec::new(),
                request,
            };
        }
        // in_place_scope may execute a job on its caller. Its existing shared
        // ancestry must not be entered twice; nested spawns capture their leaf too.
        let shared = STACK.with(|stack| {
            stack
                .borrow()
                .iter()
                .zip(&self.names)
                .take_while(|(frame, name)| frame.name == **name)
                .count()
        });
        let mut entered = StageContextGuard {
            guards: Vec::new(),
            request,
        };
        for &name in &self.names[shared..] {
            entered.guards.push(stage(name));
        }
        entered
    }
}
pub struct StageContextGuard {
    guards: Vec<StageGuard>,
    request: Option<RequestContextGuard>,
}
impl Drop for StageContextGuard {
    fn drop(&mut self) {
        // Vec's ordinary forward drop would violate the profiler stack discipline.
        while let Some(guard) = self.guards.pop() {
            drop(guard);
        }
        self.request.take();
    }
}

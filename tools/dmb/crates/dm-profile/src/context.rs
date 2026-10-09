//! Transfer only stage names; clocks and guards always belong to executing threads.
use super::{stage, StageGuard, ACTIVE, STACK};

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct StageContext {
    names: Vec<&'static str>,
}
impl StageContext {
    /// Disabled profiling returns an empty vector without allocating or touching TLS.
    pub fn capture() -> Self {
        if ACTIVE.get().is_none() {
            return Self::default();
        }
        Self {
            names: STACK.with(|stack| stack.borrow().iter().map(|frame| frame.name).collect()),
        }
    }
    pub fn enter(&self) -> StageContextGuard {
        if self.names.is_empty() {
            return StageContextGuard { guards: Vec::new() };
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
        let mut entered = StageContextGuard { guards: Vec::new() };
        for &name in &self.names[shared..] {
            entered.guards.push(stage(name));
        }
        entered
    }
}
pub struct StageContextGuard {
    guards: Vec<StageGuard>,
}
impl Drop for StageContextGuard {
    fn drop(&mut self) {
        // Vec's ordinary forward drop would violate the profiler stack discipline.
        while let Some(guard) = self.guards.pop() {
            drop(guard);
        }
    }
}

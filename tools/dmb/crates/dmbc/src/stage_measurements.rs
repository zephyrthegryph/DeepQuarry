//! Request-local stage reporting, including early returns. No global profiler.
use std::time::{Duration, Instant};

#[derive(Clone, Copy, Debug)]
pub struct Measurement<S> {
    pub stage: S,
    pub elapsed: Duration,
    /// None marks entry; Some(false) marks an early failure.
    pub succeeded: Option<bool>,
}
pub type Observer<'a, S> = dyn Fn(Measurement<S>) + 'a;
pub(crate) struct Scope<'a, S: Copy> {
    observer: Option<&'a Observer<'a, S>>,
    stage: S,
    started: Instant,
    succeeded: bool,
}
impl<'a, S: Copy> Scope<'a, S> {
    pub(crate) fn new(observer: Option<&'a Observer<'a, S>>, stage: S) -> Self {
        if let Some(observer) = observer {
            observer(Measurement { stage, elapsed: Duration::ZERO, succeeded: None });
        }
        Self { observer, stage, started: Instant::now(), succeeded: false }
    }
    pub(crate) fn complete(mut self) { self.succeeded = true; }
}
impl<S: Copy> Drop for Scope<'_, S> {
    fn drop(&mut self) {
        if let Some(observer) = self.observer {
            observer(Measurement {
                stage: self.stage, elapsed: self.started.elapsed(), succeeded: Some(self.succeeded),
            });
        }
    }
}

//! Request-local stage reporting and opt-in profile spans, including early returns.
use std::time::{Duration, Instant};

#[derive(Clone, Copy, Debug)]
pub struct Measurement<S> {
    pub stage: S,
    pub elapsed: Duration,
    /// None marks entry; Some(false) marks an early failure.
    pub succeeded: Option<bool>,
}
pub type Observer<'a, S> = dyn Fn(Measurement<S>) + 'a;
pub(crate) trait StageName {
    fn profile_name(self) -> &'static str;
}
pub(crate) struct Scope<'a, S: Copy + StageName> {
    observer: Option<&'a Observer<'a, S>>,
    stage: S,
    started: Instant,
    succeeded: bool,
    _profile: dm_profile::StageGuard,
}
impl<'a, S: Copy + StageName> Scope<'a, S> {
    pub(crate) fn new(observer: Option<&'a Observer<'a, S>>, stage: S) -> Self {
        if let Some(observer) = observer {
            observer(Measurement {
                stage,
                elapsed: Duration::ZERO,
                succeeded: None,
            });
        }
        Self {
            observer,
            stage,
            started: Instant::now(),
            succeeded: false,
            _profile: dm_profile::stage(stage.profile_name()),
        }
    }
    pub(crate) fn complete(mut self) {
        self.succeeded = true;
    }
}
impl<S: Copy + StageName> Drop for Scope<'_, S> {
    fn drop(&mut self) {
        if let Some(observer) = self.observer {
            observer(Measurement {
                stage: self.stage,
                elapsed: self.started.elapsed(),
                succeeded: Some(self.succeeded),
            });
        }
    }
}

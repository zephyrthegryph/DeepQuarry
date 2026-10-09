//! Request-local disk admission after exact engine/configuration admission.
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc,
};

#[derive(Default)]
pub(super) struct WarmupState(Option<(u128, Arc<AtomicBool>)>);
pub(crate) enum DiskAdmission {
    OneShot,
    Retained {
        successful: Arc<AtomicBool>,
        may_read: bool,
    },
}
impl WarmupState {
    pub(super) fn admit(&mut self, retained: bool, policy: u128) -> DiskAdmission {
        if !retained {
            return DiskAdmission::OneShot;
        }
        if self
            .0
            .as_ref()
            .is_none_or(|(previous, _)| *previous != policy)
        {
            self.0 = Some((policy, Arc::new(AtomicBool::new(false))));
        }
        let successful = Arc::clone(&self.0.as_ref().expect("warmup namespace").1);
        let may_read = !successful.load(Ordering::Acquire);
        DiskAdmission::Retained {
            successful,
            may_read,
        }
    }
    pub(super) fn clear(&mut self) {
        self.0 = None;
    }
}
impl DiskAdmission {
    pub(crate) fn allows_reads(&self) -> bool {
        match self {
            Self::OneShot => true,
            Self::Retained { may_read, .. } => *may_read,
        }
    }
    pub(crate) fn allows_writes(&self) -> bool {
        matches!(self, Self::OneShot)
    }
    /// Called only after current inputs and the request's output finish succeed.
    pub(crate) fn complete(&self) {
        if let Self::Retained { successful, .. } = self {
            successful.store(true, Ordering::Release);
        }
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn unsuccessful_requests_retry_and_success_keeps_disk_off_hot_path() {
        let mut state = WarmupState::default();
        let cancelled = state.admit(true, 1);
        assert!(cancelled.allows_reads());
        assert!(!cancelled.allows_writes());
        drop(cancelled);
        let successful = state.admit(true, 1);
        assert!(successful.allows_reads());
        successful.complete();
        assert!(!state.admit(true, 1).allows_reads());
        assert!(state.admit(false, 1).allows_writes());
    }
    #[test]
    fn old_namespace_completion_cannot_warm_new_configuration() {
        let mut state = WarmupState::default();
        let old = state.admit(true, 1);
        let current = state.admit(true, 2);
        old.complete();
        assert!(current.allows_reads());
        assert!(state.admit(true, 2).allows_reads());
        current.complete();
        state.clear();
        assert!(state.admit(true, 2).allows_reads());
    }
}

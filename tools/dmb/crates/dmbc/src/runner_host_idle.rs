//! Explicit idle tiers keep active requests and semantic admission untouched.
use super::*;

impl BuildHost {
    pub(crate) fn release_idle_executor(&mut self) {
        // Called only while the host is exclusively locked without active requests.
        // Joining the request-unbound pool leaves no profiler binding behind.
        drop(self.executor.take());
    }

    pub(crate) fn release_idle_artifacts(&mut self) {
        // Keep authenticated engine and preprocessing/semantic source owners.
        // Cleared consumers recreate their normal current-revision stores through
        // the same pipeline; the next request may hydrate disk read-only again.
        self.disk_warmup.clear();
        self.procedures = None;
        self.symbolic = None;
        self.initializers = None;
        self.startup = None;
        self.abi = None;
        self.initializer_fragments = None;
        self.initializer_assemblies = None;
        self.class_projections = None;
        self.link_bindings = None;
        self.maps = None;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn executor_release_preserves_warmup_but_artifact_release_resets_it() {
        let mut host = BuildHost::default();
        host.executor = Some(dm_exec::BuildExecutor::new_unbound(1).unwrap());
        host.disk_admission(4).complete();
        assert!(!host.disk_admission(4).allows_reads());
        host.release_idle_executor();
        assert!(host.executor.is_none());
        assert!(!host.disk_admission(4).allows_reads());
        host.release_idle_artifacts();
        assert!(host.disk_admission(4).allows_reads());
        assert!(host.memo.is_some());
        assert!(host.semantic.is_some());
    }
    #[test]
    fn idle_cleanup_does_not_activate_one_shot_retention() {
        let mut host = BuildHost::one_shot();
        host.release_idle_executor();
        host.release_idle_artifacts();
        assert!(host.memo.is_none());
        assert!(host.semantic.is_none());
        assert!(host.disk_admission(4).allows_writes());
    }
}

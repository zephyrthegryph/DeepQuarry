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
        // the same pipeline; disk remains a lazy fallback on subsequent misses.
        if self.prepared_sources.is_some() {
            self.prepared_sources = Some(Arc::new(
                crate::input_snapshot::PreparedInputArtifacts::default(),
            ));
        }
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
        self.generation = None;
        self.host_facts = None;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn executor_release_preserves_artifacts_and_rich_release_clears_them() {
        let mut host = BuildHost::default();
        host.executor = Some(dm_exec::BuildExecutor::new_unbound(1).unwrap());
        let prepared = host.prepared_sources().unwrap();
        let first = host.procedure_memo(4, None).unwrap();
        let facts = host.host_facts().unwrap();
        let weak_facts = Arc::downgrade(&facts);
        drop(facts);
        let generation = host.generation(4).unwrap();
        let weak_generation = Arc::downgrade(&generation);
        drop(generation);
        host.release_idle_executor();
        assert!(host.executor.is_none());
        assert!(weak_generation.upgrade().is_some());
        assert!(weak_facts.upgrade().is_some());
        let second = host.procedure_memo(4, None).unwrap();
        assert!(Arc::ptr_eq(&first.values, &second.values));
        host.release_idle_artifacts();
        assert!(weak_generation.upgrade().is_none());
        assert!(weak_facts.upgrade().is_none());
        let next = host.procedure_memo(4, None).unwrap();
        assert!(!Arc::ptr_eq(&first.values, &next.values));
        assert!(!Arc::ptr_eq(&prepared, &host.prepared_sources().unwrap()));
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
    }
}

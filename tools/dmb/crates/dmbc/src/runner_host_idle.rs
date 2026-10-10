//! Explicit idle tiers keep active requests and semantic admission untouched.
use super::*;

impl BuildHost {
    pub(crate) fn release_idle_executor(&mut self) {
        // Called only while the host is exclusively locked without active requests.
        // Joining the request-unbound pool leaves no profiler binding behind.
        drop(self.executor.take());
    }

    pub(crate) fn release_idle_artifacts(&mut self) {
        // First pressure tier releases rich and physical buffers, retaining the
        // symbolic dependency receipts needed by the next incremental request.
        // Housekeeping samples memory again before escalating to whole-session
        // eviction; this does not raise the daemon's private-memory threshold.
        self.rich_generation = self.rich_generation.saturating_add(1);
        if self.prepared_sources.is_some() {
            self.prepared_sources = Some(Arc::new(
                crate::input_snapshot::PreparedInputArtifacts::default(),
            ));
        }
        self.procedures = None;
        if let Some((_, symbolic)) = &self.symbolic {
            symbolic.release_bound_images();
        }
        if let Some((_, initializers)) = &self.initializers {
            initializers.release_runtime_syntax();
        }
        self.initializer_fragments = None;
        self.initializer_assemblies = None;
        self.link_bindings = None;
        self.maps = None;
        if let Some((_, generation)) = &self.generation {
            generation.release_wire_images();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn pressure_release_drops_rich_buffers_and_preserves_symbolic_owners() {
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
        assert!(weak_generation.upgrade().is_some());
        assert!(weak_facts.upgrade().is_some());
        let next = host.procedure_memo(4, None).unwrap();
        assert!(!Arc::ptr_eq(&first.values, &next.values));
        assert!(Arc::ptr_eq(
            first.symbolic.as_ref().unwrap(),
            next.symbolic.as_ref().unwrap()
        ));
        assert!(Arc::ptr_eq(
            first.abi.as_ref().unwrap(),
            next.abi.as_ref().unwrap()
        ));
        assert!(Arc::ptr_eq(
            first.required_types.as_ref().unwrap(),
            next.required_types.as_ref().unwrap()
        ));
        assert!(Arc::ptr_eq(
            first.initializers.as_ref().unwrap(),
            next.initializers.as_ref().unwrap()
        ));
        assert!(Arc::ptr_eq(
            first.startup.as_ref().unwrap(),
            next.startup.as_ref().unwrap()
        ));
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

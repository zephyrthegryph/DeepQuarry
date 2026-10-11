//! Explicit idle tiers keep active requests and semantic admission untouched.
use super::*;

impl BuildHost {
    pub(crate) fn release_idle_executor(&mut self) {
        // Called only while the host is exclusively locked without active requests.
        // Joining the request-unbound pool leaves no profiler binding behind.
        drop(self.executor.take());
    }

    /// Intermediate pressure tier: retain the existing semantic/source issuer,
    /// discard optional downstream owners. Escaped request Arcs may live until
    /// their consumers finish, but cannot repopulate these detached host slots.
    pub(crate) fn release_idle_compiler_artifacts(&mut self) {
        self.emit_idle_census("before-compiler-release");
        self.release_idle_executor();
        self.rich_generation = self.rich_generation.saturating_add(1);
        self.procedures = None;
        // Re-creatable projections must release their backing before pruning
        // retained dependency nodes allocates its small traversal workspace.
        // Escaped request owners remain valid independently of these host slots.
        self.initializer_fragments = None;
        self.class_projections = None;
        self.required_types = None;
        self.link_bindings = None;
        self.generation = None;
        self.host_facts = None;
        self.maps = None;
        if let Some((_, owner)) = &self.symbolic {
            eprintln!("dmbd compact symbolic procedures begin");
            let report = owner.compact_for_pressure(192 * 1024 * 1024);
            eprintln!("dmbd compact symbolic procedures {report:?}");
        }
        // Preserve only fully charged source-neutral initializer nodes. This is
        // a logical retention cap, not a claim about process private memory.
        if let Some((_, owner)) = &self.initializers {
            eprintln!("dmbd compact initializer classification begin");
            let report = owner.compact_for_pressure(96 * 1024 * 1024);
            eprintln!("dmbd compact initializer classification {report:?}");
        }
        if let Some((_, owner)) = &self.startup {
            eprintln!("dmbd compact startup begin");
            let report = owner.compact_for_pressure(32 * 1024 * 1024);
            eprintln!("dmbd compact startup {report:?}");
        }
        if let Some((_, owner)) = &self.abi {
            eprintln!("dmbd compact ABI payloads begin");
            let report = owner.compact_for_pressure(32 * 1024 * 1024);
            eprintln!("dmbd compact ABI payloads (shared engine excluded) {report:?}");
        }
        if let Some((_, owner)) = &self.initializer_assemblies {
            eprintln!("dmbd compact initializer assembly begin");
            let report = owner.compact_for_pressure(64 * 1024 * 1024);
            eprintln!("dmbd compact initializer assembly {report:?}");
        }
        // Payload-free resource/demand proofs remain with the semantic owner.
        if self.memo.is_some() {
            self.memo = Some(Default::default());
        }
        if self.prepared_sources.is_some() {
            self.prepared_sources = Some(Arc::new(Default::default()));
        }
        // Preserve current read-only query availability only for the exact
        // retained semantic owner; no old snapshot can retain another tree.
        let mut query = self
            .query_state
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if let Some(snapshot) = query.snapshot.as_mut() {
            snapshot.release_body_queries();
        }
        if query.snapshot.as_ref().is_some_and(|snapshot| {
            self.semantic
                .as_ref()
                .and_then(|state| state.snapshot_tree())
                .is_none_or(|tree| !snapshot.matches_tree(tree))
        }) {
            *query = Default::default();
        }
        drop(query);
        // Worker heaps have already been joined, and optional artifact owners
        // have been dropped. Reclaim freed pages before private-memory pressure
        // decides whether the surviving semantic owner must also be evicted.
        // This preserves the existing live-data budgets and admission receipts.
        let reclaim_started = std::time::Instant::now();
        dm_profile::reclaim_unused_allocator_pages();
        eprintln!(
            "dmbd allocator page reclamation seconds={:.6}",
            reclaim_started.elapsed().as_secs_f64()
        );
        self.emit_idle_census("after-compiler-release");
    }

    pub(crate) fn release_idle_artifacts(&mut self) {
        self.emit_idle_census("before-rich-release");
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
        if let Some((_, owner)) = &self.initializer_assemblies {
            eprintln!("dmbd compact initializer assembly begin");
            let report = owner.compact_for_pressure(64 * 1024 * 1024);
            eprintln!("dmbd compact initializer assembly {report:?}");
        }
        self.link_bindings = None;
        self.maps = None;
        if let Some((_, generation)) = &self.generation {
            generation.release_wire_images();
        }
        self.emit_idle_census("after-rich-release");
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
        let first = host.procedure_memo(4, None, true).unwrap();
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
        let second = host.procedure_memo(4, None, true).unwrap();
        assert!(Arc::ptr_eq(&first.values, &second.values));
        let symbolic_owner = Arc::clone(&host.symbolic.as_ref().unwrap().1);
        let initializer_owner = Arc::clone(&host.initializers.as_ref().unwrap().1);
        let startup_owner = Arc::clone(&host.startup.as_ref().unwrap().1);
        let required_owner = Arc::clone(&host.required_types.as_ref().unwrap().1);
        host.release_idle_artifacts();
        assert!(weak_generation.upgrade().is_some());
        assert!(weak_facts.upgrade().is_some());
        let next = host.procedure_memo(4, None, true).unwrap();
        assert!(!Arc::ptr_eq(&first.values, &next.values));
        assert!(Arc::ptr_eq(
            &symbolic_owner,
            &host.symbolic.as_ref().unwrap().1
        ));
        assert!(
            !Arc::ptr_eq(
                first.symbolic.as_ref().unwrap(),
                next.symbolic.as_ref().unwrap()
            ),
            "each request owns a distinct pending publication lease"
        );
        assert!(Arc::ptr_eq(
            first.abi.as_ref().unwrap(),
            next.abi.as_ref().unwrap()
        ));
        assert!(Arc::ptr_eq(
            &required_owner,
            &host.required_types.as_ref().unwrap().1
        ));
        assert!(
            !Arc::ptr_eq(
                first.required_types.as_ref().unwrap(),
                next.required_types.as_ref().unwrap()
            ),
            "request facades must not reuse pending publication leases"
        );
        assert!(Arc::ptr_eq(
            &initializer_owner,
            &host.initializers.as_ref().unwrap().1
        ));
        assert!(
            !Arc::ptr_eq(
                first.initializers.as_ref().unwrap(),
                next.initializers.as_ref().unwrap()
            ),
            "request facades must not reuse pending publication leases"
        );
        assert!(Arc::ptr_eq(
            &startup_owner,
            &host.startup.as_ref().unwrap().1
        ));
        assert!(
            !Arc::ptr_eq(
                first.startup.as_ref().unwrap(),
                next.startup.as_ref().unwrap()
            ),
            "request facades must not reuse pending publication leases"
        );
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

#[cfg(test)]
#[path = "runner_host_idle_compiler_tests.rs"]
mod compiler_tests;

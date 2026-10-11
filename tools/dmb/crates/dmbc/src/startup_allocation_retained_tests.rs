use super::*;
use dm_ir::{ResolveQuery, ResolvedMeaning, Resolver};
use std::path::Path;
struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
fn frontend(source: &'static str) -> dm_tree::frontend::ColdFrontend {
    dm_tree::frontend::build(
        Path::new("allocation.dme"),
        &Source(source),
        &Default::default(),
        1,
    )
    .unwrap()
}
#[test]
fn retained_allocation_rebinds_shifted_sources_and_recomputes_changed_order() {
    let store = Arc::new(crate::startup::StartupArtifacts::default());
    let mut previous = None;
    for (index, source) in [
        "/world/proc/prior()\n    return 1\nvar/global/late = 1\n/proc/reset()\n    return 1\n/var/global/first = 2\n",
        "// shift\n/world/proc/prior()\n    return 2\nvar/global/late = 1\n/proc/reset()\n    return 3\n/var/global/first = 2\n",
        "/proc/reset()\n    return 1\n/var/global/first = 2\n/world/proc/prior()\n    return 1\nvar/global/late = 1\n",
    ].into_iter().enumerate() {
        let frontend = frontend(source);
        let declaration = dm_tree::initializers::capture_declaration_plan(&frontend.snapshot, &frontend.emission_order).unwrap();
        let plan = declaration.plan();
        let current = StartupAllocationRoster::issue_current_with_artifacts(plan, &[], &frontend, Some(&store)).unwrap();
        let fresh = StartupAllocationRoster::issue_current(plan, &[], &frontend).unwrap();
        assert_eq!(current.allocation.keys, fresh.allocation.keys);
        assert_eq!(current.allocation.registration_owners, fresh.allocation.registration_owners);
        assert!(current.allocation.bind_current(plan, &frontend));
        if let Some(old) = previous.as_ref() { assert_eq!(Arc::ptr_eq(old, &current.allocation), index == 1); }
        previous = Some(Arc::clone(&current.allocation));
        if index == 0 {
            let compact = store.compact_for_pressure(1024 * 1024);
            assert_eq!(compact.retained_entries, 1);
            assert!(compact.charged_bytes > std::mem::size_of::<AllocationReceipt>());
        }
        let mut malformed = plan.clone();
        Arc::make_mut(&mut malformed.origins)[0].provenance.span.start += 1;
        assert!(!current.allocation.bind_current(&malformed, &frontend));
    }
}
struct Host(bool);
impl Resolver for Host {
    fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
        if self.0 {
            ResolvedMeaning::Unsupported(query)
        } else {
            ResolvedMeaning::Missing
        }
    }
}
#[test]
fn finalized_allocation_replays_negative_resolver_reads_in_same_store() {
    let frontend = frontend("/var/global/value = 1\n");
    let declaration = dm_tree::initializers::capture_declaration_plan(
        &frontend.snapshot,
        &frontend.emission_order,
    )
    .unwrap();
    let store = Arc::new(crate::startup::StartupArtifacts::default());
    let current = StartupAllocationRoster::issue_current_with_artifacts(
        declaration.plan(),
        &[],
        &frontend,
        Some(&store),
    )
    .unwrap();
    let input = || FinalInput {
        allocation: Arc::clone(&current.allocation),
        classifications: Vec::new(),
    };
    let host = Host(false);
    let recording = crate::lowering_memo::RecordingResolver::new(&host);
    assert_eq!(
        recording.resolve(ResolveQuery::GlobalProc(SymbolId::of("absent"))),
        ResolvedMeaning::Missing
    );
    let ordered = Arc::new(OrderedRoster {
        keys: current.allocation.keys.clone(),
        ranks: current.allocation.ranks.clone(),
    });
    let saved = store.remember_final_allocation(
        FinalReceipt {
            input: input(),
            ordered,
        },
        &recording,
    );
    let admitted = store.final_allocation(&input(), &host).unwrap();
    assert!(Arc::ptr_eq(&saved, &admitted.ordered));
    assert!(store.final_allocation(&input(), &Host(true)).is_none());
    let stats = store.retention_census();
    assert!(stats
        .owners
        .iter()
        .any(|owner| owner.owner == "startup.allocation"));
}
#[test]
fn finalized_production_classification_reuses_only_current_admitted_owners() {
    use crate::initializer_policy::{
        CapturedInitializerEvaluator, InitializerArtifacts, InitializerReuse,
    };
    let frontend = frontend("/var/global/value = 1\n");
    let declaration = dm_tree::initializers::capture_declaration_plan(
        &frontend.snapshot,
        &frontend.emission_order,
    )
    .unwrap();
    let plan = declaration.plan();
    let store = Arc::new(crate::startup::StartupArtifacts::default());
    let classifications = InitializerArtifacts::default();
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let host = frontend.snapshot.tree.as_ref();
    let evaluator = crate::driver_facts::DriverEvaluator {
        pure_calls: None,
        resource_search_context: None,
        resolver: host,
        symbols: &plan.symbols,
    };
    let classify = || {
        crate::initializer_policy::classify_with_reuse_on_executor(
            &plan.writes,
            &plan.symbols,
            evaluator.parallel_evaluator().unwrap(),
            false,
            &executor,
            InitializerReuse {
                store: &classifications,
                resolver: host,
                policy: 1,
                resource_search_context: None,
            },
        )
        .unwrap()
    };
    let a =
        StartupAllocationRoster::issue_current_with_artifacts(plan, &[], &frontend, Some(&store))
            .unwrap();
    let classified_a = classify();
    assert!(FinalInput::capture(&a.allocation, plan, &classified_a).is_some());
    a.finalize(plan, &classified_a, host).unwrap();
    let b =
        StartupAllocationRoster::issue_current_with_artifacts(plan, &[], &frontend, Some(&store))
            .unwrap();
    let mut classified_b = classify();
    b.finalize(plan, &classified_b, host).unwrap();
    assert!(Arc::ptr_eq(
        a.finalized.get().unwrap(),
        b.finalized.get().unwrap()
    ));
    classified_b.accepted[0] = None;
    assert!(FinalInput::capture(&b.allocation, plan, &classified_b).is_none());
}

#[test]
fn retained_array_allocation_and_final_receipts_match_fresh_semantic_changes() {
    use crate::initializer_policy::{
        CapturedInitializerEvaluator, InitializerArtifacts, InitializerReuse,
    };
    let base =
        "/var/global/list/values[2]\n/var/global/list/unsized[]\n/var/global/default_value = 1\n";
    for (source, allocation_hit, final_hit) in [
        ("// current source shift\n/var/global/list/values[2]\n/var/global/list/unsized[]\n/var/global/default_value = 1\n", true, true),
        ("/var/global/list/renamed[2]\n/var/global/list/unsized[]\n/var/global/default_value = 1\n", false, false),
        ("/var/global/list/values[3]\n/var/global/list/unsized[]\n/var/global/default_value = 1\n", true, false),
        ("/var/global/list/values[2]\n/var/global/list/unsized[]\n/var/global/default_value = 2\n", true, false),
        ("/var/global/list/values[2]\n/var/global/list/unsized[1]\n/var/global/default_value = 1\n", true, false),
    ] {
        let store = Arc::new(crate::startup::StartupArtifacts::default());
        let classifications = InitializerArtifacts::default();
        let executor = dm_exec::BuildExecutor::new(1).unwrap();
        let mut previous = None;
        for text in [base, source] {
            let frontend = frontend(text);
            let declaration = dm_tree::initializers::capture_declaration_plan(
                &frontend.snapshot, &frontend.emission_order,
            ).unwrap();
            let plan = declaration.plan();
            assert_eq!(plan.writes.len(), 3);
            let host = frontend.snapshot.tree.as_ref();
            let evaluator = crate::driver_facts::DriverEvaluator {
                pure_calls: None, resource_search_context: None, resolver: host, symbols: &plan.symbols,
            };
            let classified = crate::initializer_policy::classify_with_reuse_on_executor(
                &plan.writes, &plan.symbols, evaluator.parallel_evaluator().unwrap(), false, &executor,
                InitializerReuse { store: &classifications, resolver: host, policy: 1, resource_search_context: None },
            ).unwrap();
            let current = StartupAllocationRoster::issue_current_with_artifacts(
                plan, &[], &frontend, Some(&store),
            ).unwrap();
            let fresh = StartupAllocationRoster::issue_current(plan, &[], &frontend).unwrap();
            assert!(current.allocation.bind_current(plan, &frontend));
            current.finalize(plan, &classified, host).unwrap();
            fresh.finalize(plan, &classified, host).unwrap();
            let final_owner = current.finalized.get().unwrap();
            assert_eq!(final_owner.keys, fresh.finalized.get().unwrap().keys);
            assert_eq!(final_owner.ranks, fresh.finalized.get().unwrap().ranks);
            if let Some((allocation, final_roster)) = previous.as_ref() {
                assert_eq!(Arc::ptr_eq(allocation, &current.allocation), allocation_hit, "{source}");
                assert_eq!(Arc::ptr_eq(final_roster, final_owner), final_hit, "{source}");
            }
            previous = Some((Arc::clone(&current.allocation), Arc::clone(final_owner)));
        }
    }
}

#[path = "startup_allocation_fresh_tests.rs"]
mod fresh_publication;

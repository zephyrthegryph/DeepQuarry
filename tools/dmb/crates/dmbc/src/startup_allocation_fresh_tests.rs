use super::*;
fn issue(
    store: &Arc<crate::startup::StartupArtifacts>,
    source: &'static str,
) -> StartupAllocationRoster {
    let frontend = frontend(source);
    let declaration = dm_tree::initializers::capture_declaration_plan(
        &frontend.snapshot,
        &frontend.emission_order,
    )
    .unwrap();
    StartupAllocationRoster::issue_current_with_artifacts(
        declaration.plan(),
        &[],
        &frontend,
        Some(store),
    )
    .unwrap()
}
fn final_input(allocation: &Arc<AllocationReceipt>) -> FinalInput {
    FinalInput {
        allocation: allocation.clone(),
        classifications: Vec::new(),
    }
}
fn finalize(
    store: &crate::startup::StartupArtifacts,
    allocation: &Arc<AllocationReceipt>,
) -> Arc<OrderedRoster> {
    let host = Host(false);
    let recording = crate::lowering_memo::RecordingResolver::new(&host);
    // Both source revisions have exactly the same negative semantic ledger.
    assert_eq!(
        recording.resolve(ResolveQuery::GlobalProc(SymbolId::of("absent"))),
        ResolvedMeaning::Missing
    );
    store.remember_final_allocation(
        FinalReceipt {
            input: final_input(allocation),
            ordered: Arc::new(OrderedRoster {
                keys: allocation.keys.clone(),
                ranks: allocation.ranks.clone(),
            }),
        },
        &recording,
    )
}
#[test]
fn current_allocation_and_final_rosters_replace_rejected_inputs_only_on_success() {
    let owner = Arc::new(crate::startup::StartupArtifacts::default());
    let original_source = "/var/global/first = 1\n";
    let changed_source = "/var/global/first = 1\n/var/global/second = 2\n";
    let initial = owner.for_request(true);
    let old = issue(&initial, original_source);
    let old_ordered = finalize(&initial, &old.allocation);
    assert!(initial.publish_successful());
    // Abort a real changed allocation attempt; published and escaped old owners survive.
    let failed = owner.for_request(true);
    let changed = issue(&failed, changed_source);
    assert_ne!(changed.allocation.keys, old.allocation.keys);
    let changed_ordered = finalize(&failed, &changed.allocation);
    assert_eq!(changed_ordered.keys, changed.allocation.keys);
    assert!(!Arc::ptr_eq(&old_ordered, &changed_ordered));
    drop(changed);
    drop(failed);
    let recovery = owner.for_request(true);
    let recovered = issue(&recovery, original_source);
    assert!(Arc::ptr_eq(&old.allocation, &recovered.allocation));
    let old_hit = recovery
        .final_allocation(&final_input(&recovered.allocation), &Host(false))
        .unwrap();
    assert!(Arc::ptr_eq(&old_ordered, &old_hit.ordered));
    drop(recovery);
    // A successful changed request keeps the newly computed owners on the next hit.
    let successful = owner.for_request(true);
    let current = issue(&successful, changed_source);
    let current_ordered = finalize(&successful, &current.allocation);
    assert!(successful.publish_successful());
    let next = owner.for_request(true);
    let hit = issue(&next, changed_source);
    assert!(Arc::ptr_eq(&current.allocation, &hit.allocation));
    let final_hit = next
        .final_allocation(&final_input(&hit.allocation), &Host(false))
        .unwrap();
    assert!(Arc::ptr_eq(&current_ordered, &final_hit.ordered));
    assert_eq!(current_ordered.keys, current.allocation.keys);
    let fresh = issue(
        &Arc::new(crate::startup::StartupArtifacts::default()),
        changed_source,
    );
    assert_eq!(current.allocation.keys, fresh.allocation.keys);
    assert_eq!(current.allocation.ranks, fresh.allocation.ranks);
    assert_eq!(old_ordered.keys, old.allocation.keys); // old escaped readers unchanged
}

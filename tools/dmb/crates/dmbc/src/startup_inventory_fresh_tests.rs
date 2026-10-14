use super::*;
fn observe(
    front: &dm_tree::frontend::FrontendRevision,
    pool: &dm_exec::BuildExecutor,
    store: Option<&StartupArtifacts>,
) -> Arc<StartupFacts> {
    let arena = dm_tree::frontend::BodyArena::new(front);
    capture(front, pool, &arena, store)
}
#[test]
fn changed_inventory_is_retained_after_success_and_failed_attempt_keeps_old_owner() {
    let owner = StartupArtifacts::default();
    let pool = dm_exec::BuildExecutor::new(1).unwrap();
    let original = revision("/proc/p()\n    var/static/cache = 3\n    return cache\n");
    let changed = revision(
        "/proc/p()\n    var/static/cache = 4\n    return cache\n/proc/new_proc()\n    return 1\n",
    );
    let initial = owner.for_request(true);
    let old = observe(&original, &pool, Some(&initial));
    assert!(initial.publish_successful());
    let failed = owner.for_request(true);
    let discarded = observe(&changed, &pool, Some(&failed));
    assert!(!Arc::ptr_eq(
        &old.static_inventory,
        &discarded.static_inventory
    ));
    drop(discarded);
    drop(failed);
    let recovery = owner.for_request(true);
    let recovered = observe(&original, &pool, Some(&recovery));
    assert!(Arc::ptr_eq(
        &old.static_inventory,
        &recovered.static_inventory
    ));
    drop(recovered);
    drop(recovery);
    let successful = owner.for_request(true);
    let current = observe(&changed, &pool, Some(&successful));
    let fresh = observe(&changed, &pool, None);
    assert_eq!(current.plan.writes, fresh.plan.writes);
    assert_eq!(current.plan.origins, fresh.plan.origins);
    assert!(successful.publish_successful());
    let next = owner.for_request(true);
    let reused = observe(&changed, &pool, Some(&next));
    assert!(
        Arc::ptr_eq(&current.static_inventory, &reused.static_inventory),
        "the changed receipt, not its rejected predecessor, must be retained"
    );
    assert_eq!(next.inventory_hits.load(Ordering::Relaxed), 1);
    assert_eq!(next.inventory_recomputed.load(Ordering::Relaxed), 0);
    let old_oracle = observe(&original, &pool, None);
    assert_eq!(old.plan.writes, old_oracle.plan.writes);
    assert_eq!(old.plan.origins, old_oracle.plan.origins); // escaped old facts unchanged
}

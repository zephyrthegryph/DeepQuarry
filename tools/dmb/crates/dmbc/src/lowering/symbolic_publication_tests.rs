use super::*;
fn identity() -> UnitIdentity {
    UnitIdentity {
        owner: dm_ir::SymbolId::of("/datum/probe"),
        name: dm_ir::SymbolId::of("read"),
        namespace: Namespace::Proc,
        occurrence: 0,
    }
}
fn record(key: &[u8], reads: Vec<ResolverRead>) -> Record {
    Record {
        recipe: None,
        key: Arc::from(key),
        reads: reads.into(),
        versions: Arc::from([]),
        value: RecordValue::Selections {
            facts: Arc::new(Default::default()),
            abi: vec![7],
        },
        relative_debug: Vec::new(),
        required_types: Arc::from([]),
        modified_recipes: Arc::from([]),
    }
}
fn selected(store: &SessionSymbolicMemo, key: &[u8]) -> Option<Arc<Record>> {
    let mut result = None;
    store.visit_records(|value| {
        if value.key.as_ref() == key {
            result = Some(Arc::clone(value));
        }
    });
    result
}
#[test]
fn symbolic_success_failed_and_ephemeral_attempts_keep_exact_recipe_owners() {
    let owner = SessionSymbolicMemo::current_revision();
    let first = owner.for_request(true);
    first.insert_record(identity(), record(b"first body", vec![]));
    let old = selected(&owner, b"first body").unwrap();
    let weak_old = Arc::downgrade(&old);
    drop(old);
    assert!(first.publish_successful());
    drop(first);
    let failed = owner.for_request(true);
    failed.insert_record(identity(), record(b"changed body", vec![]));
    let changed = selected(&owner, b"changed body").unwrap();
    let weak_changed = Arc::downgrade(&changed);
    drop(changed);
    // Same identity and empty ledger MUST NOT deduplicate a changed source key.
    assert!(weak_old.upgrade().is_some());
    drop(failed);
    assert!(weak_changed.upgrade().is_none());
    assert!(weak_old.upgrade().is_some());
    let next = owner.for_request(true);
    let analysis = owner.for_request(false);
    analysis.insert_record(identity(), record(b"analysis body", vec![]));
    assert!(!analysis.publish_successful());
    drop(analysis);
    assert!(next.publish_successful());
    drop(next);
    assert!(weak_old.upgrade().is_none());
    assert_eq!(owner.visit_records(|_| {}), 0);
}
struct Host(bool);
impl Resolver for Host {
    fn resolve(&self, _: dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning {
        dm_ir::ResolvedMeaning::Presence(self.0)
    }
}
#[test]
fn symbolic_claim_requires_exact_negative_read_and_current_consumer_admission() {
    let owner = SessionSymbolicMemo::current_revision();
    let first = owner.for_request(true);
    let query = dm_ir::ResolveQuery::MemberCallableName(dm_ir::SymbolId::of("absent"));
    first.insert_record(
        identity(),
        record(
            b"recipe",
            vec![ResolverRead {
                query,
                domain: query.domain(),
                answer: dm_ir::ResolvedMeaning::Presence(false),
            }],
        ),
    );
    let old = selected(&owner, b"recipe").unwrap();
    let weak = Arc::downgrade(&old);
    assert!(first.publish_successful());
    drop(first);
    drop(old);
    let next = owner.for_request(true);
    let key = locator(identity(), b"recipe");
    let attempt = next.attempt.as_ref().unwrap();
    assert!(attempt
        .with_pending(|leases| leases
            .records
            .visit_explained_accepted(&key, &Host(true), &mut |_| true)
            .0)
        .flatten()
        .is_none());
    assert!(attempt
        .with_pending(|leases| leases
            .records
            .visit_explained_accepted(&key, &Host(false), &mut |_| false)
            .0)
        .flatten()
        .is_none());
    assert!(next.publish_successful());
    assert!(weak.upgrade().is_none());
    drop(next);
}

#[test]
fn request_facades_share_actual_session_counters_and_sealed_insert_declines() {
    let owner = SessionSymbolicMemo::current_revision();
    let first = owner.for_request(true);
    assert!(Arc::ptr_eq(&first.admitted, &owner.admitted));
    assert!(Arc::ptr_eq(&first.reused, &owner.reused));
    assert!(Arc::ptr_eq(&first.pruned, &owner.pruned));
    assert!(Arc::ptr_eq(&first.declines, &owner.declines));
    first.admitted.fetch_add(2, Ordering::Relaxed);
    first.declines.read_changed.fetch_add(1, Ordering::Relaxed);
    assert!(first.publish_successful());
    assert!(!first.insert_record(identity(), record(b"sealed", vec![])));
    drop(first);
    let next = owner.for_request(true);
    assert_eq!(next.admitted.load(Ordering::Relaxed), 2);
    assert_eq!(owner.retention_stats().successful_admissions, 2);
    assert_eq!(owner.decline_stats().read_changed, 1);
}

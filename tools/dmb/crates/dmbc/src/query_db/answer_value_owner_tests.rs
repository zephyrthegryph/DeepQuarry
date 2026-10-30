use super::answer_value_owner::ValueRetentionPermit;
use super::*;
use dm_ir::{ResolveQuery as Q, ResolvedMeaning as M, SymbolId};
fn pool() -> Arc<AnswerValues> {
    Arc::new(AnswerValues::with_source_ledger(SourceLedger::new(4096)))
}
fn query() -> Q {
    Q::Type(SymbolId::of("/datum"))
}
#[test]
fn runtime_aliases_predating_attachment_and_original_weak_both_keep_charge() {
    let pool = pool();
    let value = pool.intern(0, &query(), &M::Missing);
    let old_runtime_alias = value.clone();
    assert_eq!(pool.source_ledger.snapshot().live, 0);
    let permit = ValueRetentionPermit::lifetime_fixture(&value, &pool.source_ledger, 100);
    pool.retain_source_owner(0, &value, permit).unwrap();
    drop(value);
    assert_eq!(pool.source_ledger.snapshot().live, 100);
    drop(old_runtime_alias);
    assert_eq!(
        pool.source_ledger.snapshot().live,
        100,
        "original pooled Weak retains allocation after all strong owners died"
    );
    assert_eq!(
        pool.shards[0]
            .lock()
            .unwrap()
            .get(&0)
            .unwrap()
            .strong_count(),
        0
    );
    pool.prune();
    assert_eq!(pool.source_ledger.snapshot().live, 0);
}
#[test]
fn overwritten_pool_key_cannot_release_a_retained_marked_base() {
    let pool = pool();
    let value = pool.intern(0, &query(), &M::Missing);
    let marked_base = value.clone();
    let permit = ValueRetentionPermit::lifetime_fixture(&value, &pool.source_ledger, 100);
    pool.retain_source_owner(0, &value, permit).unwrap();
    drop(value);
    let replacement = pool.intern(0, &query(), &M::Symbol(SymbolId::of("/datum")));
    assert_eq!(pool.source_ledger.snapshot().live, 100);
    drop(marked_base);
    assert_eq!(pool.source_ledger.snapshot().live, 0);
    drop(replacement);
    pool.prune();
}
#[test]
fn foreign_value_permit_fails_without_attachment_and_releases_reservation() {
    let pool = pool();
    let value = pool.intern(0, &query(), &M::Missing);
    let foreign = pool.intern(1, &query(), &M::Missing);
    let permit = ValueRetentionPermit::lifetime_fixture(&foreign, &pool.source_ledger, 100);
    assert!(pool.retain_source_owner(0, &value, permit).is_err());
    assert!(value.source_retention.get().is_none());
    assert!(foreign.source_retention.get().is_none());
    assert_eq!(pool.source_ledger.snapshot().live, 0);
}
#[test]
fn original_canonical_pointer_and_resource_attachment_are_shared_without_value_copy() {
    let pool = pool();
    let value = pool.intern(0, &query(), &M::Missing);
    let permit = ValueRetentionPermit::lifetime_fixture(&value, &pool.source_ledger, 100);
    pool.retain_source_owner(0, &value, permit).unwrap();
    let warm = pool.intern(0, &query(), &M::Missing);
    assert!(std::ptr::eq::<AnswerValue>(&*value, &*warm));
    let mut c = crate::heap_census::HeapCensus::new("source-owner-lifetime");
    value.census(&mut c);
    warm.census(&mut c);
    drop(value);
    drop(warm);
    pool.shards[0]
        .lock()
        .unwrap()
        .get(&0)
        .unwrap()
        .census(&mut c);
    assert_eq!(pool.source_ledger.snapshot().live, 100);
    pool.prune();
    assert_eq!(pool.source_ledger.snapshot().live, 0);
}
#[test]
fn late_attachment_to_original_base_after_pool_overwrite_needs_no_new_registry() {
    let pool = pool();
    let base = pool.intern(0, &query(), &M::Missing);
    let replacement = pool.intern(0, &query(), &M::Symbol(SymbolId::of("/datum")));
    let permit = ValueRetentionPermit::lifetime_fixture(&base, &pool.source_ledger, 100);
    pool.retain_source_owner(0, &base, permit).unwrap();
    drop(replacement);
    pool.prune();
    assert_eq!(pool.source_ledger.snapshot().live, 100);
    drop(base);
    assert_eq!(pool.source_ledger.snapshot().live, 0);
}

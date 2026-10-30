use super::answer_storage::insert_source_map;
use super::*;
use dm_ir::{ResolveQuery as Q, SymbolId};
fn pool(limit: usize) -> Arc<AnswerValues> {
    Arc::new(AnswerValues::with_source_ledger(SourceLedger::new(limit)))
}
fn value() -> ValueOwner {
    ValueOwner::new_runtime(11, true, Q::Type(SymbolId::of("/datum")))
}
fn slot(value: ValueOwner) -> AnswerSlot {
    AnswerSlot {
        request: 0,
        born: 0,
        changed: 0,
        stamp: 0,
        value,
        base: None,
    }
}

#[test]
fn originals_share_global_budget_and_actual_destruction_releases_backing() {
    let values = pool(1 << 20);
    let ledger = Arc::clone(&values.source_ledger);
    let a = Answers::with_values(Arc::clone(&values));
    let b = Answers::with_values(Arc::clone(&values));
    let held = value();
    insert_source_map(&mut a.shards[0].lock().unwrap(), 0, slot(held.clone())).unwrap();
    let first = ledger.snapshot().live;
    assert!(first > 0);
    insert_source_map(&mut b.shards[0].lock().unwrap(), 0, slot(held.clone())).unwrap();
    assert!(ledger.snapshot().live > first);
    insert_source_map(
        &mut values.shards[0].lock().unwrap(),
        0,
        PooledOwner::from_owner(&held),
    )
    .unwrap();
    let bytes = ledger.snapshot().live;
    a.clear();
    b.clear();
    drop(held);
    values.prune();
    assert!(values.shards[0].lock().unwrap().is_empty());
    assert_eq!(
        ledger.snapshot().live,
        bytes,
        "clear/prune retain actual bucket backing"
    );
    drop(a);
    drop(b);
    assert!(ledger.snapshot().live > 0);
    drop(values);
    assert_eq!(ledger.snapshot().live, 0);
}
#[test]
fn failed_map_growth_mutates_no_entries_and_next_small_insert_recovers() {
    let values = pool(4096);
    let answers = Answers::with_values(Arc::clone(&values));
    let ledger = &values.source_ledger;
    let mut slots = answers.shards[0].lock().unwrap();
    {
        let handle = slots.allocator().clone();
        let mode = handle.source_mode().unwrap();
        assert!(slots.try_reserve(100_000).is_err());
        assert!(mode.denied());
    }
    assert!(slots.is_empty());
    assert_eq!(ledger.snapshot().live, 0);
    insert_source_map(&mut slots, 0, slot(value())).unwrap();
    let snapshot = ledger.snapshot();
    insert_source_map(&mut slots, 0, slot(value())).unwrap();
    assert_eq!(ledger.snapshot(), snapshot);
    assert_eq!(slots.len(), 1);
}
#[test]
fn stamp_reservation_preserves_binding_and_uses_global_lifetime_charge() {
    let values = pool(1 << 20);
    let ledger = Arc::clone(&values.source_ledger);
    let answers = Answers::with_values(Arc::clone(&values));
    {
        let mut current = answers.current.write().unwrap();
        while current.stamps.len() < current.stamps.capacity() {
            let n = current.stamps.len() as u128;
            current.stamps.push((n, 55));
        }
        let before = (
            current.request,
            current.world,
            current.stamp,
            current.stamps.to_vec(),
        );
        let expected = current.reserve_source_stamp((0, 99)).unwrap();
        assert_eq!(
            (
                current.request,
                current.world,
                current.stamp,
                current.stamps.to_vec()
            ),
            before
        );
        assert!(ledger.snapshot().live > 0);
        let reserved = ledger.snapshot().live;
        current.bind(None, 99);
        assert_eq!(current.stamp, expected);
        assert_eq!(ledger.snapshot().live, reserved);
    }
    drop(answers);
    drop(values);
    assert_eq!(ledger.snapshot().live, 0);
}
#[test]
fn ordinary_runtime_storage_is_uncapped_when_source_budget_is_zero() {
    let values = pool(0);
    let answers = Answers::with_values(Arc::clone(&values));
    let query = Q::Type(SymbolId::of("/datum"));
    let held = values.intern(
        55,
        &query,
        &dm_ir::ResolvedMeaning::Symbol(SymbolId::of("/datum")),
    );
    answers.shards[0].lock().unwrap().insert(55, slot(held));
    answers.current.write().unwrap().bind(None, 77);
    assert_eq!(answers.len(), 1);
    assert_eq!(values.source_ledger.snapshot().live, 0);
}

use super::production_tests::{frontend, prepared, same};
use super::*;

#[test]
fn compact_abi_replays_actual_unit_owners_and_current_changed_inputs() {
    let engine = crate::runner_host::EnginePayload::capture(
        include_bytes!("../../../../fixtures/native_template.bin").to_vec(),
        1,
        true,
        0,
    )
    .unwrap();
    let store = AbiArtifacts::with_engine_owner(Arc::clone(&engine)).with_retained_shortcuts();
    let old = frontend(
        "/datum/a/proc/p(x=3)\n    return x\n/datum/b/proc/q()\n    return 2\n",
        &engine.snapshot,
    );
    let first = prepared(&old, &engine.snapshot, Some(&store));
    let compact = store.compact_for_pressure(8 * 1024 * 1024);
    assert_eq!(
        compact.retained_entries, 3,
        "two unit payloads and the same admitted batch"
    );
    assert!(compact.charged_bytes > 3 * std::mem::size_of::<Artifact>());
    let shifted = frontend(
        "// moved\n/datum/a/proc/p(x=3)\n    return x+1\n/datum/b/proc/q()\n    return 4\n",
        &engine.snapshot,
    );
    let retained = prepared(&shifted, &engine.snapshot, Some(&store));
    same(&retained, &prepared(&shifted, &engine.snapshot, None));
    for index in 0..2 {
        assert!(Arc::ptr_eq(
            first.prepared.units_owner().selected(index).unwrap(),
            retained.prepared.units_owner().selected(index).unwrap()
        ));
    }
    assert_eq!(store.batch_reused(), 1);
    let changed = frontend(
        "/datum/a/proc/p(x=9)\n    return x\n/datum/b/proc/q()\n    return 4\n",
        &engine.snapshot,
    );
    let changed = prepared(&changed, &engine.snapshot, Some(&store));
    assert!(!Arc::ptr_eq(
        first.prepared.units_owner().selected(0).unwrap(),
        changed.prepared.units_owner().selected(0).unwrap()
    ));
    assert_eq!(
        store.batch_reused(),
        1,
        "changed default cannot use old batch"
    );
    assert_eq!(store.compact_for_pressure(0).retained_entries, 0);
}

#[test]
fn historical_abi_engine_identity_is_weak_and_dead_or_foreign_declines() {
    let engine = crate::runner_host::EnginePayload::capture(
        include_bytes!("../../../../fixtures/native_template.bin").to_vec(),
        1,
        true,
        0,
    )
    .unwrap();
    let identity = Arc::downgrade(&engine);
    assert_eq!(Arc::strong_count(&engine), 1);
    assert!(observations::same_engine(
        &identity,
        &Arc::downgrade(&engine)
    ));
    let foreign = crate::runner_host::EnginePayload::capture(
        include_bytes!("../../../../fixtures/native_template.bin").to_vec(),
        1,
        true,
        0,
    )
    .unwrap();
    assert!(!observations::same_engine(
        &identity,
        &Arc::downgrade(&foreign)
    ));
    drop(engine);
    assert!(identity.upgrade().is_none());
    assert!(!observations::same_engine(&identity, &identity));
}

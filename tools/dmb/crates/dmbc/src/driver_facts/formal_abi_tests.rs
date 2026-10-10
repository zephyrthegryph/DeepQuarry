//! BYOND 516.1687 compile-only golden: formal-inheritance-receipt.json.
use super::*;
const SOURCE: &str =
    include_str!("../../../../fixtures/native_compiler/formal_abi_inheritance/probe.dme");
fn compare_golden_flags(value: &PreparedPinnedSourceAbi) {
    let oracle = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../fixtures/native_compiler/formal_abi_inheritance/probe.native.bin"
    ))
    .unwrap();
    let current = flags(value);
    assert_eq!(current.len(), 3);
    for (flags, path) in current.into_iter().zip([
        b"/datum/base/proc/check".as_slice(),
        b"/datum/base/check",
        b"/datum/child/check",
    ]) {
        let expected = oracle
            .procs
            .iter()
            .find(|proc| oracle.string(proc.strings[0]) == Some(path))
            .unwrap();
        // Decode the wire extension through its semantic accessors; the 0x80
        // extension marker is not a ProcLayout setting.
        assert_eq!(flags & 1 != 0, expected.is_hidden(), "hidden {:?}", path);
        assert_eq!(
            flags & 4 != 0,
            expected.waits_for_completion(),
            "waitfor {:?}",
            path
        );
        assert_eq!(
            flags & 0x100 != 0,
            expected.runs_in_background(),
            "background {:?}",
            path
        );
    }
}

fn flags(value: &PreparedPinnedSourceAbi) -> Vec<u32> {
    value
        .prepared
        .units
        .iter()
        .map(|(_, unit)| unit.abi.as_ref().unwrap().layout.flags)
        .collect()
}
#[test]
fn child_abi_inherits_original_formal_settings_not_effective_parent_override() {
    let engine_owner = crate::runner_host::EnginePayload::capture(
        include_bytes!("../../../../fixtures/native_template.bin").to_vec(),
        1,
        true,
        0,
    )
    .unwrap();
    let engine = &engine_owner.snapshot;
    let store = AbiArtifacts::with_engine_owner(Arc::clone(&engine_owner));
    let front = frontend(SOURCE, &engine);
    let first = prepared(&front, &engine, Some(&store));
    same(&first, &prepared(&front, &engine, None));
    compare_golden_flags(&first);
    let changed = frontend("/datum/base/proc/check(a)\n    set hidden = 1\n    return 42\n/datum/base/check(a)\n    set waitfor = 0\n    set background = 1\n    return 7\n/datum/child\n    parent_type = /datum/base\n/datum/child/check()\n    return\n", &engine);
    let retained = prepared(&changed, &engine, Some(&store));
    same(&retained, &prepared(&changed, &engine, None));
    compare_golden_flags(&retained);
    assert_eq!(store.totals(), (3, 3));
    let changed_formal = frontend("/datum/base/proc/check(a)\n    set hidden = 0\n    return 42\n/datum/base/check(a)\n    set waitfor = 0\n    set background = 1\n    return 7\n/datum/child\n    parent_type = /datum/base\n/datum/child/check()\n    return\n", &engine);
    let invalidated = prepared(&changed_formal, &engine, Some(&store));
    same(&invalidated, &prepared(&changed_formal, &engine, None));
    assert_eq!(flags(&invalidated), vec![4, 0x100, 4]);
    assert_eq!(store.totals(), (3, 6));
}

#[test]
fn original_formal_waitfor_zero_remains_inherited_and_child_explicit_setting_wins() {
    let engine_owner = crate::runner_host::EnginePayload::capture(
        include_bytes!("../../../../fixtures/native_template.bin").to_vec(),
        1,
        true,
        0,
    )
    .unwrap();
    let engine = &engine_owner.snapshot;
    let front = frontend("/datum/base/proc/check()\n    set waitfor = 0\n    return 1\n/datum/child\n    parent_type = /datum/base\n/datum/child/check()\n    return\n/datum/explicit\n    parent_type = /datum/base\n/datum/explicit/check()\n    set waitfor = 1\n    return\n", &engine);
    let result = prepared(&front, &engine, None);
    assert!(result.prepared.diagnostics.is_empty());
    assert_eq!(flags(&result), vec![0, 0, 4]);
}

//! BYOND 516.1687 compile-only golden: formal-inheritance-receipt.json.
use super::*;
const SOURCE: &str = "/datum/base/proc/check(a)\n    set hidden = 1\n    return 0\n/datum/base/check(a)\n    set waitfor = 0\n    set background = 1\n    return 1\n/datum/child\n    parent_type = /datum/base\n/datum/child/check()\n    return\n";
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
    let engine = EngineSnapshot::from_bytes(
        include_bytes!("../../../../fixtures/native_template.bin"),
        1,
    )
    .unwrap()
    .with_bootstrap_catalog()
    .unwrap();
    let store = AbiArtifacts::default();
    let front = frontend(SOURCE, &engine);
    let first = prepared(&front, &engine, Some(&store));
    same(&first, &prepared(&front, &engine, None));
    assert_eq!(flags(&first), vec![5, 0x101, 5]);
    let changed = frontend("/datum/base/proc/check(a)\n    set hidden = 1\n    return 42\n/datum/base/check(a)\n    set waitfor = 0\n    set background = 1\n    return 7\n/datum/child\n    parent_type = /datum/base\n/datum/child/check()\n    return\n", &engine);
    let retained = prepared(&changed, &engine, Some(&store));
    same(&retained, &prepared(&changed, &engine, None));
    assert_eq!(flags(&retained), vec![5, 0x101, 5]);
    assert_eq!(store.totals(), (3, 3));
    let changed_formal = frontend("/datum/base/proc/check(a)\n    set hidden = 0\n    return 42\n/datum/base/check(a)\n    set waitfor = 0\n    set background = 1\n    return 7\n/datum/child\n    parent_type = /datum/base\n/datum/child/check()\n    return\n", &engine);
    let invalidated = prepared(&changed_formal, &engine, Some(&store));
    same(&invalidated, &prepared(&changed_formal, &engine, None));
    assert_eq!(flags(&invalidated), vec![4, 0x100, 4]);
    assert_eq!(store.totals(), (3, 6));
}

#[test]
fn original_formal_waitfor_zero_remains_inherited_and_child_explicit_setting_wins() {
    let engine = EngineSnapshot::from_bytes(
        include_bytes!("../../../../fixtures/native_template.bin"),
        1,
    )
    .unwrap()
    .with_bootstrap_catalog()
    .unwrap();
    let front = frontend("/datum/base/proc/check()\n    set waitfor = 0\n    return 1\n/datum/child\n    parent_type = /datum/base\n/datum/child/check()\n    return\n/datum/explicit\n    parent_type = /datum/base\n/datum/explicit/check()\n    set waitfor = 1\n    return\n", &engine);
    let result = prepared(&front, &engine, None);
    assert!(result.prepared.diagnostics.is_empty());
    assert_eq!(flags(&result), vec![0, 0, 4]);
}

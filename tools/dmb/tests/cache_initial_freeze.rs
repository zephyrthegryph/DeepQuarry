use byond_dmb::{
    bytecode::{self, Operand},
    compare::{compare_dmbs, compare_proc_code, CompareOptions},
    dmb::Dmb,
    operands::Variable,
    translate::translate_named_debug,
};
mod common;

fn id(dmb: &Dmb, path: &str) -> usize {
    dmb.procs
        .iter()
        .position(|proc| dmb.string(proc.strings[0]) == Some(path.as_bytes()))
        .unwrap()
}
fn switch_initial_arms(dmb: &Dmb) {
    let code = bytecode::decode(
        dmb.proc_code_words(id(dmb, "/proc/initial_switch"))
            .unwrap(),
    )
    .unwrap();
    let dispatch = code
        .iter()
        .find(|instruction| instruction.opcode == 0x78)
        .unwrap();
    let targets = dispatch.branch_targets().unwrap();
    assert_eq!(targets.len(), 2);
    for target in targets {
        let branch: Vec<_> = code
            .iter()
            .filter(|instruction| {
                instruction.offset >= target as usize && !matches!(instruction.opcode, 0x84 | 0x85)
            })
            .take(2)
            .collect();
        assert_eq!(branch[0].opcode, 0x33);
        let operands = branch[0].typed_operands().unwrap();
        let [Operand::Variable(Variable::Initial(field))] = operands.as_slice() else {
            panic!("switch arm must read frozen owner: {operands:?}")
        };
        let Variable::Field(name) = field.as_ref() else {
            panic!("unexpected initial field")
        };
        assert_eq!(dmb.string(*name), Some(b"value".as_slice()));
        assert_eq!(branch[1].opcode, 0x12);
    }
}
#[test]
fn initial_and_saved_preserve_frozen_derived_values_and_safe_fresh_reads() {
    let common::TranslationFixture {
        dir: fixture,
        input,
        baseline,
        template,
        native,
    } = common::translation_fixture("cache_initial_freeze");
    let names = [
        "derived_vars_len",
        "derived_vars_type",
        "derived_initial",
        "derived_double_value",
        "derived_saved",
        "root_initial",
        "root_saved",
        "initial_then_read",
        "saved_then_read",
        "initial_child_written",
        "initial_other_selected",
        "initial_global_call",
        "initial_deep",
        "initial_if",
        "initial_safe",
        "saved_safe",
        "different_default_witness",
        "different_saved_witness",
        "initial_factory",
        "saved_factory",
    ];
    for debug in [false, true] {
        let actual =
            translate_named_debug(&input, &baseline, &template, &fixture, Some("probe"), debug)
                .unwrap();
        for name in names {
            let path = format!("/proc/{name}");
            let diff = compare_proc_code(
                &native,
                id(&native, &path),
                &actual.dmb,
                id(&actual.dmb, &path),
                &path,
                100,
                true,
            );
            assert!(diff.is_empty(), "debug={debug} {path}: {diff:#?}");
        }
        switch_initial_arms(&native);
        switch_initial_arms(&actual.dmb);
        let diff = compare_dmbs(
            &native,
            &actual.dmb,
            &CompareOptions {
                authored_prefixes: vec!["/datum/holder/other".into(), "/datum/temporary".into()],
                compare_bytecode: false,
                max_discrepancies: 100,
            },
        );
        assert!(
            diff.is_empty(),
            "differing default/saved class declarations: {diff:#?}"
        );
    }
}

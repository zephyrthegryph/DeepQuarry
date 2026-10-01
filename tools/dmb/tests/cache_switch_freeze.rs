use byond_dmb::{
    bytecode::{self, Operand},
    dmb::Dmb,
    opendream::OpenDreamProgram,
    operands::Variable,
    translate::translate_named_debug,
};
use std::collections::{BTreeMap, HashMap, HashSet};
use std::path::Path;

fn selected_reference(dmb: &Dmb, value: &Variable) -> String {
    match value {
        Variable::SetCache(owner, next) => format!(
            "select({},{})",
            selected_reference(dmb, owner),
            selected_reference(dmb, next)
        ),
        Variable::Global(id) => format!(
            "global:{}",
            String::from_utf8_lossy(dmb.string(dmb.variables[*id as usize].name).unwrap())
        ),
        Variable::Field(id) => format!(
            "field:{}",
            String::from_utf8_lossy(dmb.string(*id).unwrap())
        ),
        Variable::DynamicProc(id) => format!(
            "method:{}",
            String::from_utf8_lossy(dmb.string(*id).unwrap())
        ),
        other => format!("{other:?}"),
    }
}
fn terminal(value: &Variable) -> &Variable {
    match value {
        Variable::SetCache(_, next) => terminal(next),
        other => other,
    }
}
fn accesses(dmb: &Dmb, path: &str) -> Vec<String> {
    let id = dmb
        .procs
        .iter()
        .position(|proc| dmb.string(proc.strings[0]) == Some(path.as_bytes()))
        .unwrap();
    let mut result = Vec::new();
    for instruction in bytecode::decode(dmb.proc_code_words(id).unwrap()).unwrap() {
        if !matches!(instruction.opcode, 0x29 | 0x2a | 0x33) {
            continue;
        }
        for operand in instruction.typed_operands().unwrap() {
            if let Operand::Variable(value) = operand {
                let relevant = match terminal(&value) {
                    Variable::DynamicProc(id) => dmb.string(*id) == Some(b"read"),
                    Variable::Field(id) => dmb.string(*id) == Some(b"value"),
                    _ => false,
                };
                if relevant {
                    result.push(selected_reference(dmb, &value));
                }
            }
        }
    }
    // Native and OD place the default arm in different positions. Compare the
    // actual receiver operations in every authored arm, retaining multiplicity.
    result.sort();
    result
}
fn dispatch_arms(dmb: &Dmb, path: &str) -> BTreeMap<String, Vec<String>> {
    let id = dmb
        .procs
        .iter()
        .position(|proc| dmb.string(proc.strings[0]) == Some(path.as_bytes()))
        .unwrap();
    let code = bytecode::decode(dmb.proc_code_words(id).unwrap()).unwrap();
    assert!(
        !code.iter().any(|instruction| instruction.name == "Try"),
        "fixture must have no active try cleanup"
    );
    let positions: HashMap<_, _> = code
        .iter()
        .enumerate()
        .map(|(index, instruction)| (instruction.offset, index))
        .collect();
    let key = |value: byond_dmb::operands::Value| match value.tag_word & 255 {
        0 => "null".to_owned(),
        6 => format!(
            "string:{}",
            String::from_utf8_lossy(
                dmb.string(((value.tag_word >> 8) << 16) | value.data_word)
                    .unwrap()
            )
        ),
        42 => format!(
            "number:{:08x}",
            (value.data_word << 16) | value.extra_word.unwrap()
        ),
        other => panic!("unexpected fixture key {other}"),
    };
    let mut entries = Vec::new();
    for instruction in &code {
        for operand in instruction.typed_operands().unwrap() {
            match operand {
                Operand::Switch { cases, default } => {
                    entries.extend(
                        cases
                            .into_iter()
                            .map(|(value, target)| (key(value), target)),
                    );
                    entries.push(("default".into(), default));
                }
                Operand::RangeSwitch {
                    ranges,
                    exact,
                    default,
                } => {
                    entries.extend(ranges.into_iter().map(|(low, high, target)| {
                        (format!("{}..{}", key(low), key(high)), target)
                    }));
                    entries.extend(
                        exact
                            .into_iter()
                            .map(|(value, target)| (key(value), target)),
                    );
                    entries.push(("default".into(), default));
                }
                _ => {}
            }
        }
    }
    let mut result = BTreeMap::new();
    for (key, target) in entries {
        let mut index = positions[&(target as usize)];
        let mut seen = HashSet::new();
        let mut accesses = Vec::new();
        loop {
            assert!(seen.insert(index), "unexpected fixture loop {path}");
            let instruction = &code[index];
            if instruction.opcode == 0xf8 {
                accesses.push("authored-goto:f8".to_owned());
            }
            if !matches!(instruction.opcode, 0xf | 0xf8 | 0x84 | 0x85) {
                let mut operands = Vec::new();
                for operand in instruction.typed_operands().unwrap() {
                    match operand {
                        Operand::Variable(value) => operands.push(selected_reference(dmb, &value)),
                        Operand::Word(word) => operands.push(format!("word:{word}")),
                        Operand::Value(value) => operands.push(key_value(dmb, value)),
                        other => panic!("unexpected nested fixture dispatch {other:?}"),
                    }
                }
                accesses.push(format!("{:x}:{operands:?}", instruction.opcode));
            }
            if matches!(instruction.opcode, 0 | 0x12) {
                break;
            }
            // Layout joins are followed as edges. Authored TryJmp above remains
            // an explicit compared operation, including outside a try frame.
            index = if matches!(instruction.opcode, 0xf | 0xf8) {
                positions[&(instruction.operands[0] as usize)]
            } else {
                index + 1
            };
        }
        assert!(
            result.insert(key, accesses).is_none(),
            "duplicate fixture arm"
        );
    }
    result
}
fn key_value(dmb: &Dmb, value: byond_dmb::operands::Value) -> String {
    match value.tag_word & 255 {
        0 => "null".to_owned(),
        6 => format!(
            "string:{}",
            String::from_utf8_lossy(
                dmb.string(((value.tag_word >> 8) << 16) | value.data_word)
                    .unwrap()
            )
        ),
        42 => format!(
            "number:{:08x}",
            (value.data_word << 16) | value.extra_word.unwrap()
        ),
        other => panic!("unexpected fixture value {other}"),
    }
}
#[test]
fn switch_entries_preserve_frozen_receivers_without_leaking_arm_changes() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let fixture = root.join("fixtures/translation/cache_switch_freeze");
    let input = OpenDreamProgram::from_path(fixture.join("probe.json")).unwrap();
    let baseline =
        OpenDreamProgram::from_path(root.join("fixtures/native_template_savefile_5161687.json"))
            .unwrap();
    let template =
        Dmb::from_bytes(&std::fs::read(root.join("fixtures/native_template.bin")).unwrap())
            .unwrap();
    let native =
        Dmb::from_bytes(&std::fs::read(fixture.join("probe.native.bin")).unwrap()).unwrap();
    let cases = [
        ("after_switch", 2),
        ("after_if", 2),
        ("after_switch_root", 2),
        ("switch_field", 2),
        ("switch_range", 3),
        ("switch_strings", 4),
        ("switch_join", 3),
        ("switch_sideeffect_flag", 2),
        ("switch_field_flag", 3),
        ("switch_foreign_field_flag", 3),
        ("switch_mixed_table", 4),
        ("switch_goto_join", 3),
    ];
    for debug in [false, true] {
        let actual =
            translate_named_debug(&input, &baseline, &template, &fixture, Some("probe"), debug)
                .unwrap();
        for path in ["/proc/after_if", "/proc/flag_mutates_child"] {
            let find = |dmb: &Dmb| {
                dmb.procs
                    .iter()
                    .position(|proc| dmb.string(proc.strings[0]) == Some(path.as_bytes()))
                    .unwrap()
            };
            assert!(
                byond_dmb::compare::compare_proc_code(
                    &native,
                    find(&native),
                    &actual.dmb,
                    find(&actual.dmb),
                    path,
                    100,
                    true
                )
                .is_empty(),
                "full body debug={debug} {path}"
            );
        }
        for (name, count) in cases {
            let path = format!("/proc/{name}");
            let expected = accesses(&native, &path);
            assert_eq!(expected.len(), count, "native coverage {path}");
            assert_eq!(
                accesses(&actual.dmb, &path),
                expected,
                "debug={debug} {path}"
            );
            let expected_arms = dispatch_arms(&native, &path);
            assert_eq!(expected_arms.is_empty(), name == "after_if");
            assert_eq!(
                dispatch_arms(&actual.dmb, &path),
                expected_arms,
                "arm receivers debug={debug} {path}"
            );
        }
    }
}

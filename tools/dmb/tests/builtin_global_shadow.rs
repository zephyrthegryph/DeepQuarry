use byond_dmb::{
    bytecode::{self, Operand},
    compare::compare_proc_code,
    dmb::Dmb,
    opendream::OpenDreamProgram,
    operands::Variable,
    translate::translate_named_debug,
};
use std::{collections::BTreeSet, path::Path};

fn proc_id(dmb: &Dmb, path: &str) -> usize {
    dmb.procs
        .iter()
        .position(|proc| {
            dmb.string(proc.strings[0])
                .is_some_and(|name| String::from_utf8_lossy(name).replace("/proc/", "/") == path)
        })
        .unwrap_or_else(|| panic!("missing {path}"))
}

fn global_ids(dmb: &Dmb, proc: usize) -> BTreeSet<u32> {
    fn visit(variable: &Variable, ids: &mut BTreeSet<u32>) {
        match variable {
            Variable::Global(id) => {
                ids.insert(*id);
            }
            Variable::SetCache(left, right) => {
                visit(left, ids);
                visit(right, ids);
            }
            Variable::Initial(value) | Variable::IsSaved(value) => visit(value, ids),
            _ => {}
        }
    }
    let mut ids = BTreeSet::new();
    for instruction in bytecode::decode(dmb.proc_code_words(proc).unwrap()).unwrap() {
        for operand in instruction.typed_operands().unwrap() {
            if let Operand::Variable(variable) = operand {
                visit(&variable, &mut ids);
            }
        }
    }
    ids
}

#[test]
fn builtin_names_do_not_alias_authored_static_bindings() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let fixtures = root.join("fixtures/translation");
    let input = OpenDreamProgram::from_path(fixtures.join("builtin_global_shadow.json")).unwrap();
    let baseline =
        OpenDreamProgram::from_path(root.join("fixtures/native_template_savefile_5161687.json"))
            .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/builtin_global_shadow.native.bin"
    ))
    .unwrap();
    let mutable = [
        "/datum/shadow_left/bump",
        "/datum/shadow_right/bump",
        "/shadow_static_left",
        "/shadow_static_right",
        "/shadow_true",
        "/shadow_default_equal",
    ];
    for debug in [false, true] {
        let actual = translate_named_debug(
            &input,
            &baseline,
            &template,
            &fixtures,
            Some("builtin_global_shadow"),
            debug,
        )
        .unwrap()
        .dmb;
        let mut native_bindings = BTreeSet::new();
        let mut actual_bindings = BTreeSet::new();
        for path in mutable
            .into_iter()
            .chain(["/datum/shadow_const/read", "/shadow_call_pair"])
        {
            let n = proc_id(&native, path);
            let a = proc_id(&actual, path);
            if path == "/datum/shadow_const/read" {
                // OpenDream folds this immutable read. Check the exact native
                // constant record and complete return sequence independently.
                let native_ids = global_ids(&native, n);
                assert_eq!(native_ids.len(), 1);
                let id = *native_ids.first().unwrap();
                let variable = &native.variables[id as usize];
                assert_eq!((variable.kind, variable.value), (42, 1f32.to_bits()));
                assert!(native.global_variable_flags().unwrap().contains(&(id, 3)));
                let executable = bytecode::decode(actual.proc_code_words(a).unwrap())
                    .unwrap()
                    .into_iter()
                    .filter(|i| !matches!(i.opcode, 0x84 | 0x85))
                    .collect::<Vec<_>>();
                assert_eq!(
                    executable.iter().map(|i| i.opcode).collect::<Vec<_>>(),
                    [0x60, 0x12, 0]
                );
                assert_eq!(executable[0].operands, [42, 1f32.to_bits() >> 16, 0]);
                continue;
            }
            let differences = compare_proc_code(&native, n, &actual, a, path, 64, true);
            assert!(
                differences.is_empty(),
                "{path}, debug={debug}: {differences:#?}"
            );
            if mutable.contains(&path) {
                let ni = global_ids(&native, n);
                let ai = global_ids(&actual, a);
                assert_eq!(ni.len(), 1, "native {path}");
                assert_eq!(ai.len(), 1, "actual {path}");
                assert!(
                    native_bindings.insert(*ni.first().unwrap()),
                    "native aliases {path}"
                );
                assert!(
                    actual_bindings.insert(*ai.first().unwrap()),
                    "actual aliases {path}"
                );
                let flags = actual.global_variable_flags().unwrap();
                assert!(
                    flags.contains(&(*ai.first().unwrap(), 1)),
                    "mutable footer missing: {path}"
                );
                assert!(
                    !flags.contains(&(*ai.first().unwrap(), 3)),
                    "mutable static aliases builtin constant: {path}"
                );
                let variable = &actual.variables[*ai.first().unwrap() as usize];
                assert_eq!(variable.kind, 42);
                assert_eq!(
                    variable.value,
                    if path == "/shadow_true" {
                        2f32.to_bits()
                    } else if path == "/shadow_default_equal" {
                        1f32.to_bits()
                    } else {
                        0
                    }
                );
            }
        }
        for path in [
            "/datum/shadow_left",
            "/datum/shadow_right",
            "/datum/shadow_const",
        ] {
            let class = actual
                .classes
                .iter()
                .position(|class| actual.string(class.path_string_id()) == Some(path.as_bytes()))
                .unwrap();
            assert!(
                actual
                    .class_variable_declarations(class)
                    .unwrap()
                    .iter()
                    .any(|(id, flags)| {
                        actual.string(actual.variables[*id as usize].name)
                            == Some(b"NORTH".as_slice())
                            && flags & 1 != 0
                    }),
                "class binding omitted: {path}"
            );
        }
    }
}

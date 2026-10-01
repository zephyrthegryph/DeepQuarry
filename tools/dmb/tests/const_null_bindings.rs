use byond_dmb::{
    bytecode::{decode, Operand},
    compare::compare_proc_code,
    dmb::Dmb,
    opendream::OpenDreamProgram,
    operands::Variable,
    translate::translate_named_debug,
};
use std::{collections::HashSet, path::Path};

fn proc_id(dmb: &Dmb, path: &str) -> usize {
    dmb.procs
        .iter()
        .position(|proc| dmb.string(proc.strings[0]) == Some(path.as_bytes()))
        .unwrap_or_else(|| panic!("missing authored procedure {path}"))
}

fn globals_read(dmb: &Dmb, path: &str) -> Vec<u32> {
    decode(dmb.proc_code_words(proc_id(dmb, path)).unwrap())
        .unwrap()
        .into_iter()
        .filter(|instruction| instruction.opcode == 0x33)
        .flat_map(|instruction| instruction.typed_operands().unwrap())
        .filter_map(|operand| match operand {
            Operand::Variable(Variable::Global(id)) => Some(id),
            _ => None,
        })
        .collect()
}

fn readonly_footer(dmb: &Dmb) -> HashSet<u32> {
    dmb.lists[dmb.variable_footer as usize]
        .chunks_exact(2)
        .filter_map(|pair| (pair[1] == 3).then_some(pair[0]))
        .collect()
}

fn paths(name: &str) -> Vec<String> {
    let names: &[&str] = match name {
        "probe" | "ambiguous" | "same_null" => &[
            "global_read",
            "local_read",
            "local_other",
            "owner",
            "typed",
            "computed",
            "safe",
            "computed_safe",
            "new_computed",
            "new_safe",
        ],
        "hierarchy" => &["owner", "unknown", "typed", "safe", "colon", "safe_colon"],
        "order_three" => &["computed", "pure", "safe", "owner", "typed", "typed_safe"],
        "order_reverse" | "order_reopen" | "mixed_reverse" => &["computed", "owner"],
        _ => panic!("unlisted fixture {name}"),
    };
    let mut result: Vec<_> = names.iter().map(|name| format!("/proc/{name}")).collect();
    if matches!(name, "probe" | "ambiguous" | "same_null") {
        result.push("/datum/base/proc/read_c".into());
    }
    if name == "probe" {
        result.push("/datum/child/proc/inherited_c".into());
    }
    result
}

#[test]
fn native_const_null_binding_bodies_and_readonly_declarations_match() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let fixtures = root.join("fixtures/translation/const_null_bindings");
    let baseline =
        OpenDreamProgram::from_path(root.join("fixtures/native_template_savefile_5161687.json"))
            .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let mut compared = 0;
    for name in [
        "probe",
        "ambiguous",
        "same_null",
        "hierarchy",
        "order_three",
        "order_reverse",
        "order_reopen",
        "mixed_reverse",
    ] {
        let input = OpenDreamProgram::from_path(fixtures.join(format!("{name}.json"))).unwrap();
        let native =
            Dmb::from_bytes(&std::fs::read(fixtures.join(format!("{name}.native.bin"))).unwrap())
                .unwrap();
        let metadata = input.globals.as_ref().unwrap();
        assert!(
            !metadata.const_field_global_ids.is_empty(),
            "{name} must exercise a class binding"
        );
        for debug in [false, true] {
            let output =
                translate_named_debug(&input, &baseline, &template, &fixtures, Some(name), debug)
                    .unwrap();
            output.dmb.validate_references().unwrap();
            let native_readonly = readonly_footer(&native);
            let actual_readonly = readonly_footer(&output.dmb);
            for path in paths(name) {
                let differences = compare_proc_code(
                    &native,
                    proc_id(&native, &path),
                    &output.dmb,
                    proc_id(&output.dmb, &path),
                    &path,
                    50,
                    true,
                );
                assert!(
                    differences.is_empty(),
                    "{name} debug={debug} {path}: {differences:#?}"
                );
                compared += 1;
                if matches!(
                    path.as_str(),
                    "/proc/computed" | "/proc/unknown" | "/proc/new_computed"
                ) && !globals_read(&native, &path).is_empty()
                {
                    // The native owned receiver destination is FFD8 Cache,
                    // not FFF8 Eval. Decimal 65496 must not be misclassified.
                    for dmb in [&native, &output.dmb] {
                        let instructions =
                            decode(dmb.proc_code_words(proc_id(dmb, &path)).unwrap()).unwrap();
                        assert!(
                            instructions
                                .iter()
                                .any(|instruction| instruction.opcode == 0x34
                                    && instruction
                                        .typed_operands()
                                        .unwrap()
                                        .contains(&Operand::Variable(Variable::Cache))),
                            "{name} {path} must preserve the native frozen receiver Cache"
                        );
                    }
                }
                for (dmb, readonly) in
                    [(&native, &native_readonly), (&output.dmb, &actual_readonly)]
                {
                    for id in globals_read(dmb, &path) {
                        assert!(
                            readonly.contains(&id),
                            "{name} {path} reads non-const Global#{id}"
                        );
                        assert_eq!(
                            dmb.variables[id as usize].kind, 0,
                            "{name} {path} must retain const-null storage"
                        );
                    }
                }
            }
            for &old in &metadata.const_global_ids {
                assert!(
                    actual_readonly.contains(&output.ids.globals[old]),
                    "{name} missing flag3 for global {old}"
                );
            }
            for &old in &metadata.const_field_global_ids {
                let id = output.ids.globals[old];
                assert!(output.dmb.classes.iter().enumerate().any(|(class, _)|
                    output.dmb.class_variable_declarations(class).is_some_and(|declarations|
                        declarations.contains(&(id, 3)))),
                    "{name} class const binding must reuse its existing declaration VariableID {id}");
            }
            if matches!(name, "probe" | "ambiguous" | "same_null") {
                let first = globals_read(&output.dmb, "/proc/local_read");
                let second = globals_read(&output.dmb, "/proc/local_other");
                assert_eq!(first.len(), 1);
                assert_eq!(second.len(), 1);
                assert_ne!(
                    first[0], second[0],
                    "same-name proc-local constants need separate bindings"
                );
                for path in ["/proc/local_read", "/proc/local_other"] {
                    let code = decode(
                        output
                            .dmb
                            .proc_code_words(proc_id(&output.dmb, path))
                            .unwrap(),
                    )
                    .unwrap();
                    assert!(
                        !code
                            .iter()
                            .any(|instruction| matches!(instruction.opcode, 0x34 | 0x3a)),
                        "{name} const-null declaration emitted runtime initialization in {path}"
                    );
                }
            }
            // A competing runtime field declared last keeps unknown lookup dynamic.
            // Reversing those owners makes the last const-null name binding win.
            if name == "ambiguous" {
                assert!(globals_read(&native, "/proc/computed").is_empty());
                assert!(globals_read(&output.dmb, "/proc/computed").is_empty());
            } else if name == "mixed_reverse" {
                assert_eq!(globals_read(&native, "/proc/computed").len(), 1);
                assert_eq!(globals_read(&output.dmb, "/proc/computed").len(), 1);
            }
        }
    }
    // Every authored procedure in all eight fixtures, in both debug modes.
    assert_eq!(compared, 104);
}

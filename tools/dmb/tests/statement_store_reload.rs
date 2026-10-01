use byond_dmb::{
    bytecode::{decode, Instruction, Operand},
    compare::compare_proc_code,
    dmb::Dmb,
    opendream::OpenDreamProgram,
    operands::Variable,
    translate::translate_named_debug,
};
use std::path::Path;
fn find(dmb: &Dmb, path: &str) -> usize {
    dmb.procs
        .iter()
        .position(|proc| dmb.string(proc.strings[0]) == Some(path.as_bytes()))
        .unwrap_or_else(|| panic!("missing {path}"))
}
fn body(dmb: &Dmb, path: &str) -> Vec<Instruction> {
    decode(dmb.proc_code_words(find(dmb, path)).unwrap())
        .unwrap()
        .into_iter()
        .filter(|i| !matches!(i.opcode, 0x84 | 0x85))
        .collect()
}
fn targets(i: &Instruction, opcode: u32, variable: Variable) -> bool {
    i.opcode == opcode && i.typed_operands().unwrap() == vec![Operand::Variable(variable)]
}
#[test]
fn statement_store_reload_preserves_native_assignment_ownership() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let fixture = root.join("fixtures/translation/statement_store_reload");
    let input = OpenDreamProgram::from_path(fixture.join("probe.json")).unwrap();
    let baseline =
        OpenDreamProgram::from_path(root.join("fixtures/native_template_savefile_5161687.json"))
            .unwrap();
    let template =
        Dmb::from_bytes(&std::fs::read(root.join("fixtures/native_template.bin")).unwrap())
            .unwrap();
    let native =
        Dmb::from_bytes(&std::fs::read(fixture.join("probe.native.bin")).unwrap()).unwrap();
    let globals = [
        "assignment_return",
        "assignment_call",
        "assignment_condition",
        "assignment_field",
        "statement_reload",
        "statement_reload_refcount",
        "argument_statement",
        "argument_expression",
        "global_statement",
        "global_expression",
        "field_statement",
        "field_expression",
        "numeric_statement",
        "numeric_expression",
        "world_statement",
        "world_expression",
    ];
    let mut paths: Vec<String> = globals.iter().map(|n| format!("/proc/{n}")).collect();
    paths.extend(
        [
            "/datum/observer/proc/src_statement",
            "/datum/observer/proc/src_expression",
            "/datum/observer/Del",
        ]
        .map(str::to_owned),
    );
    assert_eq!(paths.len(), 19);
    // The old local's synchronous Del reads the shared RHS reference count.
    let del = body(&native, "/datum/observer/Del");
    assert!(del.iter().any(|i| i.opcode == 0x178));
    assert!(del.iter().any(|i| matches!(
        i.typed_operands().unwrap().as_slice(),
        [Operand::Variable(Variable::Global(_))]
    ) && i.opcode == 0x33));
    for (name, var) in [
        ("statement_reload", Variable::Local(0)),
        ("statement_reload_refcount", Variable::Local(0)),
        ("argument_statement", Variable::Arg(0)),
        ("numeric_statement", Variable::Local(0)),
    ] {
        let native_body = body(&native, &format!("/proc/{name}"));
        assert!(
            native_body
                .windows(2)
                .any(|w| targets(&w[0], 0x34, var.clone()) && targets(&w[1], 0x33, var.clone())),
            "native statement witness {name}"
        );
        let proc_ = input.procs.iter().find(|p| p.name == name).unwrap();
        assert_eq!(
            proc_.native_store_reload_offsets.len(),
            1,
            "marked fusion {name}"
        );
        let at = proc_.native_store_reload_offsets[0] as usize;
        assert_eq!(proc_.bytecode.as_ref().unwrap()[at], 0x09);
    }
    for (name, var) in [
        ("assignment_return", Variable::Local(0)),
        ("assignment_call", Variable::Local(0)),
        ("assignment_condition", Variable::Local(0)),
        ("assignment_field", Variable::Local(0)),
        ("argument_expression", Variable::Arg(0)),
        ("numeric_expression", Variable::Local(0)),
    ] {
        assert!(
            body(&native, &format!("/proc/{name}"))
                .iter()
                .any(|i| targets(i, 0x35, var.clone())),
            "native expression witness {name}"
        );
        assert!(
            input
                .procs
                .iter()
                .find(|p| p.name == name)
                .unwrap()
                .native_store_reload_offsets
                .is_empty(),
            "expression must not be marked {name}"
        );
    }
    let mut failures = Vec::new();
    for debug in [false, true] {
        let actual =
            translate_named_debug(&input, &baseline, &template, &fixture, Some("probe"), debug)
                .unwrap();
        for path in &paths {
            let diff = compare_proc_code(
                &native,
                find(&native, path),
                &actual.dmb,
                find(&actual.dmb, path),
                path,
                100,
                true,
            );
            if !diff.is_empty() {
                failures.push(format!("debug={debug} {path}: {diff:#?}"));
            }
        }
    }
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}

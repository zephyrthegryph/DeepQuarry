use byond_dmb::{
    bytecode::decode, compare::compare_proc_code, dmb::Dmb, opendream::OpenDreamProgram,
    operands::Variable, translate::translate_named_debug,
};
use std::path::Path;
fn proc_id(dmb: &Dmb, path: &str) -> usize {
    dmb.procs
        .iter()
        .position(|p| dmb.string(p.strings[0]) == Some(path.as_bytes()))
        .unwrap()
}
fn selector(v: Variable) -> Variable {
    match v {
        Variable::SetCache(_, rhs) => selector(*rhs),
        other => other,
    }
}
#[test]
fn verb_calls_preserve_the_native_namespace_with_colliding_display_names() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let dir = root.join("fixtures/translation/verb_selectors");
    let baseline =
        OpenDreamProgram::from_path(root.join("fixtures/native_template_savefile_5161687.json"))
            .unwrap();
    let template =
        Dmb::from_bytes(&std::fs::read(root.join("fixtures/native_template.dmb")).unwrap())
            .unwrap();
    let input = OpenDreamProgram::from_path(dir.join("probe.json")).unwrap();
    let native = Dmb::from_bytes(&std::fs::read(dir.join("probe.native.bin")).unwrap()).unwrap();
    for debug in [false, true] {
        let output =
            translate_named_debug(&input, &baseline, &template, &dir, Some("probe"), debug)
                .unwrap();
        for path in [
            "/proc/before",
            "/proc/after",
            "/proc/after_arglist",
            "/proc/after_safe",
            "/proc/dynamic",
            "/proc/collision_verb",
            "/proc/collision_proc",
            "/proc/computed",
            "/proc/conditional",
            "/proc/safe_arglist",
            "/proc/statement",
            "/proc/explicit_proc",
            "/datum/dispatch/proc/self_call",
            "/datum/child/proc/inherited_self",
            "/proc/static_verb",
            "/proc/static_verb_safe",
            "/proc/static_verb_arglist",
            "/proc/static_verb_statement",
        ] {
            let n = proc_id(&native, path);
            let a = proc_id(&output.dmb, path);
            let differences = compare_proc_code(&native, n, &output.dmb, a, path, 100, true);
            assert!(
                differences.is_empty(),
                "{path}, debug={debug}: {differences:?}"
            );
        }
        let call_selector = |path| {
            let instructions = decode(
                output
                    .dmb
                    .proc_code_words(proc_id(&output.dmb, path))
                    .unwrap(),
            )
            .unwrap();
            let call = instructions
                .iter()
                .find(|i| matches!(i.opcode, 0x29 | 0x2a))
                .unwrap();
            selector(Variable::decode(&call.operands).unwrap().0)
        };
        let Variable::DynamicVerb(verb_name) = call_selector("/proc/collision_verb") else {
            panic!("verb namespace missing")
        };
        let Variable::DynamicProc(proc_name) = call_selector("/proc/collision_proc") else {
            panic!("proc namespace missing")
        };
        assert_eq!(
            verb_name, proc_name,
            "the legal alias collision must retain the same name and distinct namespaces"
        );
        for path in [
            "/proc/static_verb",
            "/proc/static_verb_safe",
            "/proc/static_verb_arglist",
            "/proc/static_verb_statement",
        ] {
            let body = decode(native.proc_code_words(proc_id(&native, path)).unwrap()).unwrap();
            let call = body
                .iter()
                .find(|i| matches!(i.opcode, 0x29 | 0x2a))
                .unwrap();
            assert!(
                matches!(
                    selector(Variable::decode(&call.operands).unwrap().0),
                    Variable::StaticVerb(_)
                ),
                "native static encoding witness missing: {path}"
            );
            assert!(
                matches!(call_selector(path), Variable::DynamicVerb(_)),
                "translated verb namespace missing: {path}"
            );
        }
    }
}

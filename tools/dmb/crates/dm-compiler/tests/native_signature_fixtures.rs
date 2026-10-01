use byond_dmb::{bytecode, dmb::Dmb};

fn proc_id(dmb: &Dmb, path: &str) -> usize {
    dmb.procs
        .iter()
        .position(|proc| dmb.string(proc.strings[0]) == Some(path.as_bytes()))
        .unwrap_or_else(|| panic!("missing native proc {path}"))
}

#[test]
fn native_parameter_qualifiers_and_expression_sources() {
    let dmb = Dmb::from_bytes(include_bytes!(
        "../../../fixtures/native_compiler/parameter_forms.native.bin"
    ))
    .unwrap();
    for path in ["/proc/probe_const", "/proc/probe_var_const"] {
        let arg = dmb.proc_arguments(proc_id(&dmb, path)).unwrap().remove(0);
        assert_eq!((arg.type_flags, arg.value_source), (0, 0x7d01));
    }
    for (path, source_word, first_opcode) in [
        ("/proc/probe_in", 0x40, "GetVar"),
        ("/proc/probe_in_call", 0x140, "PushInt"),
    ] {
        let arg = dmb.proc_arguments(proc_id(&dmb, path)).unwrap().remove(0);
        assert_eq!((arg.type_flags, arg.value_source), (1, source_word));
        let source = dmb.argument_source_proc_id(&arg).unwrap() as usize;
        let instructions = bytecode::decode(dmb.proc_code_words(source).unwrap()).unwrap();
        assert_eq!(instructions[0].name, first_opcode);
        assert_eq!(instructions[instructions.len() - 2].name, "Ret");
    }
}

#[test]
fn native_iterator_filters_and_database_forms() {
    let dmb = Dmb::from_bytes(include_bytes!(
        "../../../fixtures/native_compiler/remaining_forms.native.bin"
    ))
    .unwrap();
    for (path, filter) in [
        ("/proc/iterator_anything", 4096),
        ("/proc/iterator_union", 3),
        ("/proc/iterator_turf", 32),
    ] {
        let instructions = bytecode::decode(dmb.proc_code_words(proc_id(&dmb, path)).unwrap())
            .unwrap();
        let iter = instructions.iter().find(|i| i.name == "IterLoad").unwrap();
        assert_eq!(iter.operands, [5, filter]);
    }
    for path in ["/proc/sqlite_arg", "/proc/sqlite_arg_query"] {
        let arg = dmb.proc_arguments(proc_id(&dmb, path)).unwrap().remove(0);
        assert_eq!((arg.type_flags, arg.value_source), (0, 0x7d01));
    }
    for path in [
        "/proc/sqlite_local",
        "/proc/sqlite_query_local",
        "/datum/sqlite_probe/proc/assign_db",
    ] {
        let instructions = bytecode::decode(dmb.proc_code_words(proc_id(&dmb, path)).unwrap())
            .unwrap();
        assert_eq!(instructions[0].name, "PushVal");
        assert_eq!(instructions[0].operands[0], 32);
        assert_eq!(instructions[2].name, "New");
        assert_eq!(instructions[2].operands, [1]);
    }
}

#[test]
fn native_context_constants_and_verb_source() {
    let dmb = Dmb::from_bytes(include_bytes!(
        "../../../fixtures/native_compiler/context_constants.native.bin"
    ))
    .unwrap();
    for (path, kind) in [
        ("/proc/global_proc_name", 38),
        ("/proc/global_type_name", 0),
        ("/datum/context_probe/proc/member_proc_name", 38),
        ("/datum/context_probe/proc/member_type_name", 32),
    ] {
        let id = proc_id(&dmb, path);
        let instructions = bytecode::decode(dmb.proc_code_words(id).unwrap()).unwrap();
        assert_eq!(instructions[0].name, "PushVal");
        assert_eq!(instructions[0].operands[0], kind);
        if kind == 38 {
            assert_eq!(instructions[0].operands[1], id as u32);
        }
    }
    for path in [
        "/datum/context_probe/verb/view_source",
        "/datum/context_probe/verb/plain_view_source",
    ] {
        let proc = &dmb.procs[proc_id(&dmb, path)];
        assert_eq!((proc.source_kind, proc.source_parameter), (1, 1));
        assert_eq!(proc.effective_flags(), 4);
    }
}

#[test]
fn native_alert_padding_and_issaved_lvalue_selector() {
    let dmb = Dmb::from_bytes(include_bytes!(
        "../../../fixtures/native_compiler/alert_issaved.native.bin"
    ))
    .unwrap();
    for path in [
        "/proc/alert_one",
        "/proc/alert_two",
        "/proc/alert_four",
        "/proc/alert_six",
        "/proc/alert_omitted",
    ] {
        let instructions = bytecode::decode(dmb.proc_code_words(proc_id(&dmb, path)).unwrap())
            .unwrap();
        let alert = instructions.iter().position(|i| i.name == "Alert").unwrap();
        assert_eq!(alert, 6);
        assert!(instructions[..alert].iter().all(|i| i.name == "PushVal" || i.name == "GetVar"));
        assert!(instructions[alert].operands.is_empty());
    }
    let direct = bytecode::decode(
        dmb.proc_code_words(proc_id(&dmb, "/proc/issaved_member"))
            .unwrap(),
    )
    .unwrap();
    assert_eq!(direct[0].name, "GetVar");
    assert!(direct[0].operands.contains(&0xffe8));
    let indexed = bytecode::decode(
        dmb.proc_code_words(proc_id(&dmb, "/proc/issaved_index"))
            .unwrap(),
    )
    .unwrap();
    assert!(indexed.iter().any(|i| i.name == "GetVar" && i.operands.contains(&0xffe8)));
}

#[test]
fn native_alist_class_has_distinct_value_tag() {
    let dmb = Dmb::from_bytes(include_bytes!(
        "../../../fixtures/native_compiler/class_tags.native.bin"
    ))
    .unwrap();
    for (path, tag) in [
        ("/proc/alist_class", 89),
        ("/proc/generator_class", 32),
        ("/proc/database_class", 32),
        ("/proc/database_query_class", 32),
    ] {
        let code = bytecode::decode(dmb.proc_code_words(proc_id(&dmb, path)).unwrap()).unwrap();
        assert_eq!((code[0].name, code[0].operands[0]), ("PushVal", tag));
    }
}

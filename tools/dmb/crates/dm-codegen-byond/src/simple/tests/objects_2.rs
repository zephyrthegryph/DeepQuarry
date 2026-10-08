//! Objects lowering regression tests.
use super::*;

#[test]
fn inferred_new_uses_declared_member_type() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/member_inferred_new/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/member_inferred_new/probe.native.bin"
    ))
    .unwrap();
    let mut shared = SharedLowerBindings::default();
    shared.member_types.insert(
        "/datum/holder".into(),
        HashMap::from([("entry".into(), "/datum/item".into())]),
    );
    shared
        .parent_types
        .insert("/datum/holder".into(), "/datum".into());
    let bindings = LowerBindings {
        parameters: vec!["H".into()],
        parameter_types: HashMap::from([("H".into(), "/datum/holder".into())]),
        shared: Some(Arc::new(shared)),
        ..LowerBindings::default()
    };
    let compiled = compile_simple_proc_with_bindings(&ast.items[2].children, &bindings).unwrap();
    assert!(compiled.class_paths.contains(&"/datum/item".to_string()));
    let mut ledger = Ledger::default();
    let class_id = native
        .classes
        .iter()
        .position(|class| native.string(class.path_string_id()) == Some(b"/datum/item".as_slice()))
        .unwrap();
    ledger
        .bind(
            crate::Symbol::new(Table::Class, "/datum/item"),
            class_id as u32,
        )
        .unwrap();
    for key in &compiled.strings {
        let string_id = native
            .strings
            .iter()
            .position(|entry| entry.data == compiled.string_bytes(key))
            .unwrap();
        ledger
            .bind(crate::Symbol::new(Table::String, key), string_id as u32)
            .unwrap();
    }
    let linked = link_proc(&compiled.code, &ledger).unwrap();
    let proc_id = native
        .procs
        .iter()
        .position(|proc| native.string(proc.strings[0]) == Some(b"/proc/probe".as_slice()))
        .unwrap();
    assert_eq!(linked.words, native.proc_code_words(proc_id).unwrap());

    let compiled = compile_simple_proc_with_bindings(&ast.items[3].children, &bindings).unwrap();
    let linked = link_proc(&compiled.code, &ledger).unwrap();
    let proc_id = native
        .procs
        .iter()
        .position(|proc| native.string(proc.strings[0]) == Some(b"/proc/probe_type".as_slice()))
        .unwrap();
    assert_eq!(linked.words, native.proc_code_words(proc_id).unwrap());
}

#[test]
fn qualified_global_reads_and_writes_match_native() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/global_qualified/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/global_qualified/probe.native.bin"
    ))
    .unwrap();
    let variable_id = native
        .variables
        .iter()
        .position(|variable| native.string(variable.name) == Some(b"foo".as_slice()))
        .unwrap();
    let bindings = LowerBindings {
        globals: BTreeSet::from(["foo".into()]),
        ..LowerBindings::default()
    };
    for (id, item) in ast.items.iter().enumerate().skip(1) {
        let compiled = compile_simple_proc_with_bindings(&item.children, &bindings).unwrap();
        let mut ledger = Ledger::default();
        ledger
            .bind(
                crate::Symbol::new(Table::Variable, "foo"),
                variable_id as u32,
            )
            .unwrap();
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        assert_eq!(
            linked.words,
            native.proc_code_words(id - 1).unwrap(),
            "proc {id}"
        );
    }
}

#[test]
fn list_bare_associative_keys_match_native() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/list_bare_keys/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let compiled =
        compile_simple_proc_with_params(&ast.items[0].children, &["target".into()]).unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/list_bare_keys/probe.native.bin"
    ))
    .unwrap();
    let mut ledger = Ledger::default();
    for key in &compiled.strings {
        let string_id = native
            .strings
            .iter()
            .position(|entry| entry.data == compiled.string_bytes(key))
            .unwrap();
        ledger
            .bind(crate::Symbol::new(Table::String, key), string_id as u32)
            .unwrap();
    }
    let linked = link_proc(&compiled.code, &ledger).unwrap();
    assert_eq!(linked.words, native.proc_code_words(0).unwrap());
}

#[test]
fn sound_constructor_matches_native() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/sound_ctor/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/sound_ctor/probe.native.bin"
    ))
    .unwrap();
    for id in 0..3 {
        let params = if id == 2 { vec![] } else { vec!["a".into()] };
        let compiled = compile_simple_proc_with_params(&ast.items[id].children, &params).unwrap();
        let mut ledger = Ledger::default();
        for key in &compiled.strings {
            let string_id = native
                .strings
                .iter()
                .position(|entry| entry.data == compiled.string_bytes(key))
                .unwrap();
            ledger
                .bind(crate::Symbol::new(Table::String, key), string_id as u32)
                .unwrap();
        }
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        assert_eq!(
            linked.words,
            native.proc_code_words(id).unwrap(),
            "proc {id}"
        );
    }
}

#[test]
fn untyped_array_new_matches_native() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/inferred_array_new/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/inferred_array_new/probe.native.bin"
    ))
    .unwrap();
    let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
    let mut ledger = Ledger::default();
    ledger
        .bind(crate::Symbol::new(Table::Class, "/list"), 0)
        .unwrap();
    let linked = link_proc(&compiled.code, &ledger).unwrap();
    assert_eq!(linked.words, native.proc_code_words(0).unwrap());
}

#[test]
fn new_chain_matches_native() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/new_chain/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/new_chain/probe.native.bin"
    ))
    .unwrap();
    let compiled = compile_simple_proc(&ast.items[1].children).unwrap();
    let mut ledger = Ledger::default();
    ledger
        .bind(crate::Symbol::new(Table::Class, "/datum/thing"), 0)
        .unwrap();
    let string_id = native
        .strings
        .iter()
        .position(|entry| entry.data == b"InvokeAsync")
        .unwrap();
    ledger
        .bind(
            crate::Symbol::new(Table::String, "InvokeAsync"),
            string_id as u32,
        )
        .unwrap();
    let linked = link_proc(&compiled.code, &ledger).unwrap();
    assert_eq!(linked.words, native.proc_code_words(1).unwrap());
}

#[test]
fn particles_class_literal_and_constructor_match_native() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/particles_class/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/particles_class/probe.native.bin"
    ))
    .unwrap();
    for id in 0..2 {
        let compiled = compile_simple_proc(&ast.items[id].children).unwrap();
        let mut ledger = Ledger::default();
        ledger
            .bind(crate::Symbol::new(Table::Class, "/particles"), 23)
            .unwrap();
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        assert_eq!(
            linked.words,
            native.proc_code_words(id).unwrap(),
            "proc {id}"
        );
    }
}

#[test]
fn dynamic_constructor_type_matches_native_bytecode() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/dynamic_new/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let compiled =
        compile_simple_proc_with_params(&ast.items[0].children, &["typepath".into()]).unwrap();
    let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/dynamic_new/probe.native.bin"
    ))
    .unwrap();
    assert_eq!(linked.words, native.proc_code_words(0).unwrap());
}

#[test]
fn savefile_read_write_statements_preserve_index_context() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/native_compiler/input_special.dm"
    ));
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/native_compiler/input_special.native.bin"
    ))
    .unwrap();
    for (index, item) in ast.items.iter().enumerate() {
        let params = if index == 2 {
            vec!["value".into()]
        } else {
            vec!["source".into(), "value".into()]
        };
        let compiled = compile_simple_proc_with_params(&item.children, &params).unwrap();
        let mut ledger = Ledger::default();
        for key in &compiled.strings {
            let id = native
                .strings
                .iter()
                .position(|s| s.data == compiled.string_bytes(key))
                .unwrap();
            ledger
                .bind(crate::Symbol::new(Table::String, key), id as u32)
                .unwrap();
        }
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        assert_eq!(
            linked.words,
            native.proc_code_words(index).unwrap(),
            "proc {index}"
        );
    }
}

#[test]
fn indexed_augmented_assignment_preserves_native_evaluation_order() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/index_aug/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/index_aug/probe.native.bin"
    ))
    .unwrap();
    for (index, item) in ast.items.iter().enumerate() {
        let compiled =
            compile_simple_proc_with_params(&item.children, &["L".into(), "i".into(), "x".into()])
                .unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        assert_eq!(
            linked.words,
            native.proc_code_words(index).unwrap(),
            "proc {index}"
        );
    }
}

#[test]
fn initial_dynamic_index_and_colon_member_match_native_bytecode() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/initial_dynamic/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/initial_dynamic/probe.native.bin"
    ))
    .unwrap();
    for (index, item) in ast.items.iter().enumerate() {
        let parameters = if index == 0 {
            vec!["D".into(), "name".into()]
        } else {
            vec!["D".into()]
        };
        let compiled = compile_simple_proc_with_params(&item.children, &parameters).unwrap();
        let mut ledger = Ledger::default();
        for key in &compiled.strings {
            let id = native
                .strings
                .iter()
                .position(|entry| entry.data == compiled.string_bytes(key))
                .unwrap();
            ledger
                .bind(crate::Symbol::new(Table::String, key), id as u32)
                .unwrap();
        }
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        assert_eq!(
            linked.words,
            native.proc_code_words(index).unwrap(),
            "proc {index}"
        );
    }
}

#[test]
fn indexed_reads_and_writes_use_native_stack_order() {
    let ast = dm_syntax::parse("/proc/test(items, key)\n  items[key] = 7\n  return items[key]\n");
    let compiled =
        compile_simple_proc_with_params(&ast.items[0].children, &["items".into(), "key".into()])
            .unwrap();
    let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
    let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
    let names: Vec<_> = decoded
        .iter()
        .map(|instruction| instruction.opcode)
        .collect();
    assert!(names.contains(&opcode::LIST_SET));
    assert!(names.contains(&opcode::LIST_GET));
    let set = decoded
        .iter()
        .position(|instruction| instruction.opcode == opcode::LIST_SET)
        .unwrap();
    assert_eq!(decoded[set - 3].opcode, opcode::PUSH_INT);
    assert_eq!(decoded[set - 2].opcode, opcode::GET_VAR);
    assert_eq!(decoded[set - 1].opcode, opcode::GET_VAR);
}

#[test]
fn computed_index_receiver_reads_field_from_cache() {
    let ast = dm_syntax::parse("/proc/test(items, key)\n  return items[key].value\n");
    let compiled =
        compile_simple_proc_with_params(&ast.items[0].children, &["items".into(), "key".into()])
            .unwrap();
    let mut ledger = Ledger::default();
    ledger
        .assign(Table::String, compiled.strings.clone())
        .unwrap();
    let linked = link_proc(&compiled.code, &ledger).unwrap();
    let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
    let sequence: Vec<_> = decoded
        .iter()
        .map(|instruction| instruction.opcode)
        .collect();
    assert!(sequence
        .windows(3)
        .any(|ops| ops == [opcode::LIST_GET, opcode::SET_VAR, opcode::GET_VAR]));
    let get = decoded
        .iter()
        .find(|instruction| {
            instruction.opcode == opcode::GET_VAR && instruction.operands.len() == 1
        })
        .unwrap();
    assert_eq!(get.operands[0], 0);
}

#[test]
fn computed_receiver_assignment_matches_native_order() {
    let source = "/proc/test(a,b)\n  logical_identity(a).value = (a = b)\n  return a\n";
    let ast = dm_syntax::parse(source);
    let mut bindings = LowerBindings {
        parameters: vec!["a".into(), "b".into()],
        ..LowerBindings::default()
    };
    bindings.global_procs.insert("logical_identity".into());
    let compiled = compile_simple_proc_with_bindings(&ast.items[0].children, &bindings).unwrap();
    let mut ledger = Ledger::default();
    ledger
        .bind(crate::Symbol::new(Table::String, "value"), 437)
        .unwrap();
    ledger
        .bind(crate::Symbol::new(Table::Proc, "/proc/logical_identity"), 3)
        .unwrap();
    let linked = link_proc(&compiled.code, &ledger).unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/logical_fields.native.bin"
    ))
    .unwrap();
    let id = native
        .procs
        .iter()
        .position(|proc| {
            native
                .string(proc.strings[0])
                .is_some_and(|path| path.ends_with(b"field_statement_call_mutate"))
        })
        .unwrap();
    assert_eq!(linked.words, native.proc_code_words(id).unwrap());
    let expression =
        dm_syntax::parse("/proc/test(a,b)\n  return logical_identity(a).value = (a = b)\n");
    let compiled_expr =
        compile_simple_proc_with_bindings(&expression.items[0].children, &bindings).unwrap();
    let linked_expr = link_proc(&compiled_expr.code, &ledger).unwrap();
    let expr_id = native
        .procs
        .iter()
        .position(|proc| {
            native
                .string(proc.strings[0])
                .is_some_and(|path| path.ends_with(b"field_expr_call_mutate"))
        })
        .unwrap();
    assert_eq!(linked_expr.words, native.proc_code_words(expr_id).unwrap());
}

#[test]
fn absolute_constructor_matches_native_fixture() {
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/const_null_bindings/same_null.native.bin"
    ))
    .unwrap();
    let class_id = native
        .classes
        .iter()
        .position(|class| native.string(class.path_string_id()) == Some(b"/datum/base".as_slice()))
        .unwrap();
    let proc_id = native
        .procs
        .iter()
        .position(|proc| {
            native
                .string(proc.strings[0])
                .is_some_and(|path| path.ends_with(b"owner"))
        })
        .unwrap();
    let ast = dm_syntax::parse("/proc/owner()\n  return new /datum/base\n");
    let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
    assert_eq!(compiled.class_paths, ["/datum/base"]);
    let mut ledger = Ledger::default();
    ledger
        .bind(
            crate::Symbol::new(Table::Class, "/datum/base"),
            class_id as u32,
        )
        .unwrap();
    let linked = link_proc(&compiled.code, &ledger).unwrap();
    assert_eq!(linked.words, native.proc_code_words(proc_id).unwrap());
}

#[test]
fn absolute_constructor_accepts_arguments() {
    let ast = dm_syntax::parse("/proc/make()\n  return new /datum/base(7, \"seed\")\n");
    let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
    assert_eq!(compiled.class_paths, ["/datum/base"]);
    assert_eq!(compiled.strings, ["seed"]);
    let mut ledger = Ledger::default();
    ledger
        .bind(crate::Symbol::new(Table::Class, "/datum/base"), 23)
        .unwrap();
    ledger
        .bind(crate::Symbol::new(Table::String, "seed"), 42)
        .unwrap();
    let linked = link_proc(&compiled.code, &ledger).unwrap();
    let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
    assert!(decoded
        .iter()
        .any(|instruction| instruction.opcode == opcode::NEW));
}

#[test]
fn file_and_icon_constructors_link_resource_literals() {
    for name in ["file", "icon"] {
        let ast = dm_syntax::parse(&format!("/proc/make()\n  return {name}('asset.txt')\n"));
        let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
        assert_eq!(compiled.resources, ["asset.txt"]);
        let mut ledger = Ledger::default();
        ledger
            .bind(crate::Symbol::new(Table::Resource, "asset.txt"), 7)
            .unwrap();
        if name == "icon" {
            ledger
                .bind(crate::Symbol::new(Table::String, "/icon"), 29)
                .unwrap();
        }
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
        assert!(decoded
            .iter()
            .any(|instruction| instruction.opcode == opcode::NEW));
    }
}

#[test]
fn typed_null_global_member_bypasses_receiver() {
    let ast = dm_syntax::parse("/proc/test()\n    GLOB.shared = 9\n    return GLOB.shared\n");
    let shared = SharedLowerBindings {
        member_globals: HashMap::from([(
            "/datum/base".into(),
            HashMap::from([("shared".into(), "shared_slot".into())]),
        )]),
        parent_types: HashMap::from([("/datum/child".into(), "/datum/base".into())]),
        ..Default::default()
    };
    let bindings = LowerBindings {
        global_types: HashMap::from([("GLOB".into(), "/datum/child".into())]),
        shared: Some(Arc::new(shared)),
        ..Default::default()
    };
    let compiled = compile_simple_proc_with_bindings(&ast.items[0].children, &bindings).unwrap();
    let mut ledger = Ledger::default();
    ledger
        .bind(crate::Symbol::new(Table::Variable, "shared_slot"), 68)
        .unwrap();
    let linked = link_proc(&compiled.code, &ledger).unwrap();
    assert_eq!(
        linked.words,
        [0x50, 9, 0x34, 0xffdb, 68, 0x33, 0xffdb, 68, 0x12, 0]
    );
}
#[test]
fn computed_global_member_rejects_untyped_instance_collision() {
    let ast = dm_syntax::parse("/proc/test()\n    return get_holder().shared\n");
    for collision in [false, true] {
        let mut shared = SharedLowerBindings {
            member_globals: HashMap::from([(
                "/datum/base".into(),
                HashMap::from([("shared".into(), "shared_slot".into())]),
            )]),
            known_member_fields: HashMap::from([(
                "/datum/base".into(),
                BTreeSet::from(["shared".into()]),
            )]),
            ..Default::default()
        };
        if collision {
            shared
                .known_member_fields
                .insert("/datum/other".into(), BTreeSet::from(["shared".into()]));
        }
        let bindings = LowerBindings {
            global_procs: BTreeSet::from(["get_holder".into()]),
            shared: Some(Arc::new(shared)),
            ..Default::default()
        };
        let compiled =
            compile_simple_proc_with_bindings(&ast.items[0].children, &bindings).unwrap();
        let mut ledger = Ledger::default();
        ledger
            .bind(crate::Symbol::new(Table::Proc, "/proc/get_holder"), 1)
            .unwrap();
        ledger
            .bind(crate::Symbol::new(Table::Variable, "shared_slot"), 67)
            .unwrap();
        ledger
            .bind(crate::Symbol::new(Table::String, "shared"), 437)
            .unwrap();
        let words = link_proc(&compiled.code, &ledger).unwrap().words;
        if collision {
            assert_eq!(words, [0x30, 0, 1, 0x34, 0xffd8, 0x33, 437, 0x12, 0]);
        } else {
            assert_eq!(words, [0x30, 0, 1, 0x34, 0xffd8, 0x33, 0xffdb, 67, 0x12, 0]);
        }
    }
}
#[test]
fn negation_wraps_locate_in_clause_only_without_parentheses() {
    let compile = |expression: &str| {
        let ast = dm_syntax::parse(&format!("/proc/test(L)\n    return {expression}\n"));
        let compiled =
            compile_simple_proc_with_params(&ast.items[0].children, &["L".into()]).unwrap();
        let mut ledger = Ledger::default();
        ledger
            .bind(crate::Symbol::new(Table::Class, "/datum/coil"), 0)
            .unwrap();
        link_proc(&compiled.code, &ledger).unwrap().words
    };
    assert_eq!(
        compile("!locate(/datum/coil) in L"),
        [0x60, 32, 0, 0x33, 0xffd9, 0, 0x97, 0x0e, 0x12, 0]
    );
    assert_eq!(
        compile("!!locate(/datum/coil) in L"),
        [0x60, 32, 0, 0x33, 0xffd9, 0, 0x97, 0x0e, 0x0e, 0x12, 0]
    );
    assert_eq!(
        compile("(!locate(/datum/coil)) in L"),
        [0x33, 0xffd9, 0, 0x60, 32, 0, 0x5b, 0x0e, 0xa9, 5, 0x36, 0x12, 0]
    );
    assert!(!compile("!1 in list(2)").contains(&0x97));
}

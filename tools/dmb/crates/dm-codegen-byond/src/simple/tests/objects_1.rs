//! Objects lowering regression tests.
use super::*;

#[test]
fn nameof_fields_and_variables_match_native_without_evaluating_receivers() {
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/native_compiler/nameof_references.native.bin"
    ))
    .unwrap();
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/native_compiler/nameof_references.dm"
    ));
    let body = &ast.items[0]
        .children
        .iter()
        .find(|item| item.header == "proc/reference_names()")
        .unwrap()
        .children;
    let compiled = compile_simple_proc(body).unwrap();
    let mut ledger = Ledger::default();
    for key in &compiled.strings {
        let id = native
            .strings
            .iter()
            .position(|entry| entry.data == compiled.string_bytes(key.id).unwrap())
            .unwrap();
        ledger
            .bind(reference(Table::String, key), id as u32)
            .unwrap();
    }
    let id = native
        .procs
        .iter()
        .position(|proc| {
            native.string(proc.strings[0]) == Some(b"/datum/nameof_member/proc/reference_names")
        })
        .unwrap();
    assert_eq!(
        link_proc(&compiled.code, &ledger).unwrap().words,
        native.proc_code_words(id).unwrap()
    );
    for (source, expected) in [
        ("type::name", "name"),
        ("type::vv_VAS", "vv_VAS"),
        ("(type::name)", "name"),
        ("receiver().name", "name"),
    ] {
        assert_eq!(
            nameof_reference(&parse_expression(source).expr.unwrap()),
            Some(expected)
        );
    }
    let ast = dm_syntax::parse("/proc/test()\n    return nameof(type::vv_VAS)\n");
    let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
    assert_eq!(string_texts(&compiled), ["vv_VAS"]);
    assert!(compiled.class_paths.is_empty());
}

#[test]
fn global_vars_builtin_does_not_alias_ordinary_vars_declarations() {
    let ast = dm_syntax::parse("/proc/test()\n    return vars + length(global.vars)\n");
    let bindings = LowerBindings {
        globals: BTreeSet::from(["vars".into()]),
        ..Default::default()
    };
    let compiled = compile_fixture_proc_with_bindings(&ast.items[0].children, &bindings).unwrap();
    let mut references = Vec::new();
    compiled
        .code
        .for_each_reference(|reference| references.push(reference));
    assert_eq!(
        references,
        [
            reference(Table::Variable, "vars"),
            SymRef::BuiltinGlobalVars
        ]
    );
    let mut ledger = Ledger::default();
    ledger.bind(reference(Table::Variable, "vars"), 10).unwrap();
    ledger.bind(SymRef::BuiltinGlobalVars, 177).unwrap();
    let linked = link_proc(&compiled.code, &ledger).unwrap();
    assert!(linked
        .words
        .windows(3)
        .any(|words| words == [opcode::GET_VAR, 0xffdb, 10]));
    assert!(linked
        .words
        .windows(3)
        .any(|words| words == [opcode::GET_VAR, 0xffdb, 177]));
}

#[test]
fn short_circuit_index_assignments_preserve_receiver_cache_like_native() {
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/native_compiler/short_assignment.native.bin"
    ))
    .unwrap();
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/native_compiler/short_assignment.dm"
    ));
    for id in 0..3 {
        let compiled =
            compile_simple_proc_with_params(&ast.items[id].children, &["a".into(), "b".into()])
                .unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        assert_eq!(
            linked.words,
            native.proc_code_words(id).unwrap(),
            "proc {id}"
        );
    }
    for (name, params) in [
        ("short_assignment_member", vec!["a".into(), "b".into()]),
        (
            "short_assignment_index_effects",
            vec!["a".into(), "b".into(), "count".into()],
        ),
    ] {
        let item = ast
            .items
            .iter()
            .find(|item| item.header.starts_with(&format!("/proc/{name}(")))
            .unwrap();
        let bindings = LowerBindings {
            parameters: params,
            global_procs: HashMap::from([
                (
                    "assignment_receiver".into(),
                    reference(Table::Proc, "/proc/assignment_receiver"),
                ),
                (
                    "assignment_index".into(),
                    reference(Table::Proc, "/proc/assignment_index"),
                ),
            ]),
            ..Default::default()
        };
        let compiled = compile_fixture_proc_with_bindings(&item.children, &bindings).unwrap();
        let mut ledger = Ledger::default();
        for key in &compiled.strings {
            let id = native
                .strings
                .iter()
                .position(|entry| entry.data == compiled.string_bytes(key.id).unwrap())
                .unwrap();
            ledger
                .bind(reference(Table::String, key), id as u32)
                .unwrap();
        }
        for helper in ["assignment_receiver", "assignment_index"] {
            let path = format!("/proc/{helper}");
            let id = native
                .procs
                .iter()
                .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
                .unwrap();
            ledger
                .bind(reference(Table::Proc, path), id as u32)
                .unwrap();
        }
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        let path = format!("/proc/{name}");
        let id = native
            .procs
            .iter()
            .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
            .unwrap();
        assert_eq!(linked.words, native.proc_code_words(id).unwrap(), "{path}");
    }
}

#[test]
fn modified_types_link_as_native_instances_in_literals_and_constructors() {
    let alias = "/datum/example/__dm_modified_123";
    let mut shared = SharedLowerBindings::default();
    shared
        .modified_instances
        .insert(alias.into(), SymbolId::of("/datum/example"));
    let bindings = LowerBindings {
        shared: Some(Arc::new(shared)),
        ..Default::default()
    };
    let ast = dm_syntax::parse(&format!(
        "/proc/example()\n    var/a = {alias}\n    return new {alias}()\n"
    ));
    let compiled = compile_fixture_proc_with_bindings(&ast.items[0].children, &bindings).unwrap();
    assert!(compiled.class_paths.is_empty());
    assert_eq!(compiled.instance_paths, [SymbolId::of(alias)]);
    let mut ledger = Ledger::default();
    ledger
        .bind(reference(Table::Instance, alias), 0x123456)
        .unwrap();
    let linked = link_proc(&compiled.code, &ledger).unwrap();
    assert_eq!(
        linked
            .words
            .windows(2)
            .filter(|words| *words == [41 | (0x12 << 8), 0x3456])
            .count(),
        2
    );
    let mut references = Vec::new();
    compiled
        .code
        .for_each_reference(|reference| references.push(reference));
    assert_eq!(
        references,
        vec![
            SymRef::Instance(SymbolId::of(alias)),
            SymRef::Instance(SymbolId::of(alias))
        ]
    );
}

#[test]
fn mixed_associative_list_matches_native() {
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/assoc_nativekeys.native.bin"
    ))
    .unwrap();
    let ast = dm_syntax::parse("/proc/a_mixed(x)\n    return list(x,\"key\"=2,x+1)\n");
    let compiled = compile_simple_proc_with_params(&ast.items[0].children, &["x".into()]).unwrap();
    let mut ledger = Ledger::default();
    for key in &compiled.strings {
        let id = native
            .strings
            .iter()
            .position(|entry| entry.data == compiled.string_bytes(key.id).unwrap())
            .unwrap();
        ledger
            .bind(reference(Table::String, key), id as u32)
            .unwrap();
    }
    let linked = link_proc(&compiled.code, &ledger).unwrap();
    let proc_id = native
        .procs
        .iter()
        .position(|proc| native.string(proc.strings[0]) == Some(b"/proc/a_mixed".as_slice()))
        .unwrap();
    assert_eq!(linked.words, native.proc_code_words(proc_id).unwrap());
}

#[test]
fn implicit_field_reads_from_src_like_native() {
    let ast = dm_syntax::parse("/datum/cache_binding/proc/read(arg)\n    return value\n");
    let mut bindings = LowerBindings::default();
    bindings.parameters.push("arg".into());
    bindings.fields.insert("value".into());
    let compiled = compile_fixture_proc_with_bindings(&ast.items[0].children, &bindings).unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/cache_binding_freeze/probe.native.bin"
    ))
    .unwrap();
    let field_id = native
        .strings
        .iter()
        .position(|string| string.data == b"value")
        .unwrap();
    let mut ledger = Ledger::default();
    ledger
        .bind(reference(Table::String, "value"), field_id as u32)
        .unwrap();
    let linked = link_proc(&compiled.code, &ledger).unwrap();
    let id = native
        .procs
        .iter()
        .position(|proc| {
            native.string(proc.strings[0]) == Some(b"/datum/cache_binding/proc/read".as_slice())
        })
        .unwrap();
    assert_eq!(linked.words, native.proc_code_words(id).unwrap());
}

#[test]
fn implicit_field_write_matches_native_src_receiver() {
    let ast = dm_syntax::parse(
        "/datum/holder/proc/setter_reads()\n    value = 9\n    return value + other\n",
    );
    let mut bindings = LowerBindings::default();
    bindings.fields.extend(["value".into(), "other".into()]);
    let compiled = compile_fixture_proc_with_bindings(&ast.items[0].children, &bindings).unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/setter_cache_boundaries/probe.native.bin"
    ))
    .unwrap();
    let mut ledger = Ledger::default();
    for name in ["value", "other"] {
        let id = native
            .strings
            .iter()
            .position(|string| string.data == name.as_bytes())
            .unwrap();
        ledger
            .bind(reference(Table::String, name), id as u32)
            .unwrap();
    }
    let linked = link_proc(&compiled.code, &ledger).unwrap();
    let id = native
        .procs
        .iter()
        .position(|proc| {
            native.string(proc.strings[0]) == Some(b"/datum/holder/proc/setter_reads".as_slice())
        })
        .unwrap();
    let native_words = native.proc_code_words(id).unwrap();
    assert_eq!(&linked.words[..6], &native_words[..6]);
    // DreamMaker reuses its cached src binding after this setter. We
    // explicitly bind src again for later field reads.
}

#[test]
fn unsupported_initial_reference_fails_closed() {
    let ast = dm_syntax::parse("/obj/proc/test()\n    return initial(icon)\n");
    let errors = compile_simple_proc(&ast.items[0].children).unwrap_err();
    assert!(errors[0].reason.contains("field reference"));
}

#[test]
fn safe_index_assignment_matches_native_fixture() {
    let ast = dm_syntax::parse("/proc/safe_index_assign(list/a,b,c)\n    a?[b] = c\n");
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let compiled = compile_simple_proc_with_params(
        &ast.items[0].children,
        &["a".into(), "b".into(), "c".into()],
    )
    .unwrap();
    let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/safe_index.native.bin"
    ))
    .unwrap();
    let id = native
        .procs
        .iter()
        .position(|proc| {
            native.string(proc.strings[0]) == Some(b"/proc/safe_index_assign".as_slice())
        })
        .unwrap();
    let native_words = native.proc_code_words(id).unwrap();
    assert_eq!(
        linked.words[..native_words.len() - 1],
        native_words[..native_words.len() - 1]
    );
}

#[test]
fn safe_index_augmented_assignment_matches_native_fixture() {
    let ast = dm_syntax::parse("/proc/safe_index_add(list/a,b,c)\n    a?[b] += c\n");
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let compiled = compile_simple_proc_with_params(
        &ast.items[0].children,
        &["a".into(), "b".into(), "c".into()],
    )
    .unwrap();
    let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/safe_index.native.bin"
    ))
    .unwrap();
    let id = native
        .procs
        .iter()
        .position(|proc| native.string(proc.strings[0]) == Some(b"/proc/safe_index_add".as_slice()))
        .unwrap();
    let native_words = native.proc_code_words(id).unwrap();
    assert_eq!(
        linked.words[..native_words.len() - 1],
        native_words[..native_words.len() - 1]
    );
}

#[test]
fn safe_member_assignment_uses_native_guard_order() {
    let ast = dm_syntax::parse("/proc/test(a, b)\n    a?.value = b\n");
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let compiled =
        compile_simple_proc_with_params(&ast.items[0].children, &["a".into(), "b".into()]).unwrap();
    let mut ledger = Ledger::default();
    ledger
        .assign(
            Table::String,
            compiled
                .strings
                .iter()
                .map(|payload| SymRef::String(payload.id)),
        )
        .unwrap();
    let linked = link_proc(&compiled.code, &ledger).unwrap();
    let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
    let opcodes: Vec<_> = decoded
        .iter()
        .map(|instruction| instruction.opcode)
        .collect();
    assert_eq!(
        &opcodes[..6],
        [
            opcode::GET_VAR,
            318,
            opcode::PUSH_CACHE,
            opcode::GET_VAR,
            opcode::POP_CACHE,
            opcode::SET_VAR
        ]
    );
    assert_eq!(
        decoded[1].branch_targets().unwrap(),
        vec![decoded[6].offset as u32]
    );
}

#[test]
fn static_member_reads_use_native_selector_kind() {
    let ast = dm_syntax::parse("/proc/test(datum/x/path)\n    return path::abstract_type\n");
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let compiled =
        compile_simple_proc_with_params(&ast.items[0].children, &["path".into()]).unwrap();
    let mut ledger = Ledger::default();
    ledger
        .assign(
            Table::String,
            compiled
                .strings
                .iter()
                .map(|payload| SymRef::String(payload.id)),
        )
        .unwrap();
    let linked = link_proc(&compiled.code, &ledger).unwrap();
    assert_eq!(
        linked.words[..8],
        [0x33, 0xffd9, 0, 0x34, 0xffd8, 0x33, 0xffe7, 0]
    );
}

#[test]
fn inherited_class_static_member_uses_runtime_static_selector() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/static_inherited/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/static_inherited/probe.native.bin"
    ))
    .unwrap();
    let proc_id = native
        .procs
        .iter()
        .position(|proc| {
            native.string(proc.strings[0]) == Some(b"/proc/probe_static_inherited".as_slice())
        })
        .unwrap();
    assert_eq!(native.proc_code_words(proc_id).unwrap(), &[80, 5, 18, 0]);
    let compiled = compile_simple_proc(&ast.items[2].children).unwrap();
    let mut ledger = Ledger::default();
    ledger
        .bind(
            reference(Table::Class, "/datum/static_inherited_base/child"),
            0,
        )
        .unwrap();
    for key in &compiled.strings {
        let string_id = native
            .strings
            .iter()
            .position(|entry| entry.data == compiled.string_bytes(key.id).unwrap())
            .unwrap();
        ledger
            .bind(reference(Table::String, key), string_id as u32)
            .unwrap();
    }
    let linked = link_proc(&compiled.code, &ledger).unwrap();
    let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
    assert_eq!(decoded[0].opcode, opcode::PUSH_VAL);
    assert_eq!(decoded[0].operands, vec![32, 0]);
    assert_eq!(decoded[1].opcode, opcode::SET_VAR);
    assert_eq!(decoded[2].opcode, opcode::GET_VAR);
    assert_eq!(decoded[2].operands[0], 0xffe7);
}

#[test]
fn qualified_initial_uses_native_static_reference_selector() {
    for path in ["/datum/base", "/datum/child"] {
        let initial = dm_syntax::parse(&format!(
            "/proc/check()\n    return initial({path}::value)\n"
        ));
        let reference = dm_syntax::parse(&format!("/proc/check()\n    return {path}::value\n"));
        let a = compile_fixture_proc_with_bindings(
            &initial.items[0].children,
            &LowerBindings::default(),
        )
        .unwrap();
        let b = compile_fixture_proc_with_bindings(
            &reference.items[0].children,
            &LowerBindings::default(),
        )
        .unwrap();
        assert_eq!(a.code, b.code);
    }
}
#[test]
fn initial_and_istype_use_native_static_reference_and_type_test() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/initial_istype/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/initial_istype/probe.native.bin"
    ))
    .unwrap();
    for (item, path, parameter, inferred) in [
        (&ast.items[1], "/proc/test", "x", false),
        (&ast.items[2], "/proc/istype_test", "x", false),
        (&ast.items[3], "/proc/istype_implicit", "x", true),
    ] {
        let mut bindings = LowerBindings {
            parameters: vec![parameter.into()],
            ..LowerBindings::default()
        };
        if inferred {
            bindings
                .parameter_types
                .insert(parameter.into(), "/datum/x".into());
        }
        let compiled = compile_fixture_proc_with_bindings(&item.children, &bindings).unwrap();
        let mut ledger = Ledger::default();
        ledger
            .assign(
                Table::String,
                compiled
                    .strings
                    .iter()
                    .map(|payload| SymRef::String(payload.id)),
            )
            .unwrap();
        ledger
            .assign(
                Table::Class,
                compiled.class_paths.iter().copied().map(SymRef::Type),
            )
            .unwrap();
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        let id = native
            .procs
            .iter()
            .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
            .unwrap();
        let expected = byond_dmb::bytecode::decode(native.proc_code_words(id).unwrap()).unwrap();
        let ours = byond_dmb::bytecode::decode(&linked.words).unwrap();
        assert_eq!(
            ours.iter()
                .map(|instruction| instruction.opcode)
                .collect::<Vec<_>>(),
            expected
                .iter()
                .map(|instruction| instruction.opcode)
                .collect::<Vec<_>>(),
            "{path}"
        );
        if path == "/proc/test" {
            assert!(linked.words.contains(&0xffe7));
        }
    }
}

#[test]
fn prefix_postfix_increment_and_index_match_native_bodies() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/incdec/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/incdec/probe.native.bin"
    ))
    .unwrap();
    for (item, path, params) in [
        (&ast.items[0], "/proc/post_statement", vec![]),
        (&ast.items[1], "/proc/pre_statement", vec![]),
        (&ast.items[2], "/proc/post_expr", vec![]),
        (&ast.items[3], "/proc/pre_expr", vec![]),
        (
            &ast.items[4],
            "/proc/post_index",
            vec!["x".into(), "i".into()],
        ),
    ] {
        let compiled = compile_simple_proc_with_params(&item.children, &params).unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        let id = native
            .procs
            .iter()
            .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
            .unwrap();
        assert_eq!(linked.words, native.proc_code_words(id).unwrap(), "{path}");
    }
}

#[test]
fn indexed_logical_assignment_statement_and_expression_match_native() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/logical_index/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/logical_index/probe.native.bin"
    ))
    .unwrap();
    for (item, path, params) in [
        (
            &ast.items[0],
            "/proc/statement",
            vec!["x".into(), "i".into(), "y".into()],
        ),
        (
            &ast.items[1],
            "/proc/expression",
            vec!["x".into(), "i".into(), "y".into()],
        ),
        (
            &ast.items[2],
            "/proc/simple_expression",
            vec!["x".into(), "y".into()],
        ),
    ] {
        let compiled = compile_simple_proc_with_params(&item.children, &params).unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        let id = native
            .procs
            .iter()
            .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
            .unwrap();
        assert_eq!(linked.words, native.proc_code_words(id).unwrap(), "{path}");
    }
}

#[test]
fn builtin_regex_and_icon_classes_use_native_datum_tag() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/builtin_classes/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/builtin_classes/probe.native.bin"
    ))
    .unwrap();
    for (index, item) in ast.items.iter().enumerate() {
        let compiled = compile_simple_proc(&item.children).unwrap();
        let mut ledger = Ledger::default();
        let (class, class_id) = if index == 0 {
            ("/regex", 20)
        } else {
            ("/icon", 15)
        };
        ledger
            .bind(reference(Table::Class, class), class_id)
            .unwrap();
        for key in &compiled.strings {
            let id = native
                .strings
                .iter()
                .position(|entry| entry.data == compiled.string_bytes(key.id).unwrap())
                .unwrap();
            ledger
                .bind(reference(Table::String, key), id as u32)
                .unwrap();
        }
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        assert_eq!(linked.words, native.proc_code_words(index).unwrap());
    }
}

#[test]
fn list_local_new_without_path_infers_list_type() {
    let ast =
        dm_syntax::parse("/proc(test)\n    var/list/sorted_text = new()\n    return sorted_text\n");
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
    assert!(compiled.class_paths.contains(&SymbolId::of("/list")));
}

#[test]
fn conditional_inferred_new_matches_native() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/conditional_new/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let compiled = compile_simple_proc_with_params(&ast.items[0].children, &["a".into()]).unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/conditional_new/probe.native.bin"
    ))
    .unwrap();
    let mut ledger = Ledger::default();
    ledger.bind(reference(Table::Class, "/icon"), 15).unwrap();
    let linked = link_proc(&compiled.code, &ledger).unwrap();
    assert_eq!(linked.words, native.proc_code_words(0).unwrap());
}

#[test]
fn locate_empty_typed_assignment_matches_native() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/locate_empty/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let compiled = compile_simple_proc_with_params(&ast.items[0].children, &["L".into()]).unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/locate_empty/probe.native.bin"
    ))
    .unwrap();
    let mut ledger = Ledger::default();
    ledger.bind(reference(Table::Class, "/obj"), 4).unwrap();
    let linked = link_proc(&compiled.code, &ledger).unwrap();
    assert_eq!(linked.words, native.proc_code_words(0).unwrap());
    let compiled = compile_simple_proc(&ast.items[1].children).unwrap();
    let linked = link_proc(&compiled.code, &ledger).unwrap();
    assert_eq!(linked.words, native.proc_code_words(1).unwrap());
}

#[test]
fn dynamic_colon_member_read_write_match_native() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/colon_member/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/colon_member/probe.native.bin"
    ))
    .unwrap();
    for (id, item) in ast.items.iter().enumerate() {
        let compiled = compile_simple_proc_with_params(&item.children, &["D".into()]).unwrap();
        let mut ledger = Ledger::default();
        for key in &compiled.strings {
            let string_id = native
                .strings
                .iter()
                .position(|entry| entry.data == compiled.string_bytes(key.id).unwrap())
                .unwrap();
            ledger
                .bind(reference(Table::String, key), string_id as u32)
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
fn implicit_args_list_reads_and_writes_match_native() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/args_builtin/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/args_builtin/probe.native.bin"
    ))
    .unwrap();
    for (id, item) in ast.items.iter().enumerate() {
        let compiled =
            compile_simple_proc_with_params(&item.children, &["a".into(), "b".into()]).unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        assert_eq!(
            linked.words,
            native.proc_code_words(id).unwrap(),
            "proc {id}"
        );
    }

    let shadow = dm_syntax::parse("/proc/probe()\n    var/args = 7\n    return args\n");
    let compiled = compile_simple_proc(&shadow.items[0].children).unwrap();
    let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
    assert!(byond_dmb::bytecode::decode(&linked.words)
        .unwrap()
        .iter()
        .any(|instruction| instruction.opcode == opcode::GET_VAR
            && instruction.operands == [0xffda, 0]));
}

#[test]
fn associative_list_constructor_matches_native() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/named_keys/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/named_keys/probe.native.bin"
    ))
    .unwrap();
    for id in 1..4 {
        let params = if id == 3 {
            vec!["a".into(), "b".into()]
        } else {
            vec![]
        };
        let compiled = compile_simple_proc_with_params(&ast.items[id].children, &params).unwrap();
        let mut ledger = Ledger::default();
        for key in &compiled.strings {
            let string_id = native
                .strings
                .iter()
                .position(|entry| entry.data == compiled.string_bytes(key.id).unwrap())
                .unwrap();
            ledger
                .bind(reference(Table::String, key), string_id as u32)
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

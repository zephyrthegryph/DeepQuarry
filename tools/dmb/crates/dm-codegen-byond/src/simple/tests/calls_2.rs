//! Calls lowering regression tests.
use super::*;

#[test]
fn builtin_arglist_matches_native() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/builtin_arglist/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/builtin_arglist/probe.native.bin"
    ))
    .unwrap();
    for id in 0..3 {
        let compiled =
            compile_simple_proc_with_params(&ast.items[id].children, &["L".into()]).unwrap();
        let mut ledger = Ledger::default();
        if id == 1 {
            let string_id = native
                .strings
                .iter()
                .position(|entry| entry.data == b"/generator")
                .unwrap();
            ledger
                .bind(reference(Table::String, "/generator"), string_id as u32)
                .unwrap();
        }
        if id == 2 {
            ledger.bind(reference(Table::Class, "/datum"), 0).unwrap();
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
fn typed_member_call_uses_native_static_proc_reference() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/native_compiler/proc_override_chain.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/native_compiler/proc_override_chain.native.bin"
    ))
    .unwrap();
    let shared = SharedLowerBindings {
        member_procs: HashMap::from([(
            "/datum/override_probe".into(),
            HashMap::from([(
                "under_score".into(),
                reference(Table::Proc, "/datum/override_probe/proc/under_score"),
            )]),
        )]),
        ..SharedLowerBindings::default()
    };
    let bindings = LowerBindings {
        parameters: vec!["D".into()],
        parameter_types: HashMap::from([("D".into(), "/datum/override_probe".into())]),
        shared: Some(Arc::new(shared)),
        ..LowerBindings::default()
    };
    for (name, id, target_id, target_path) in [
        (
            "invoke_source_name",
            6,
            3,
            "/datum/override_probe/proc/under_score",
        ),
        (
            "invoke_plain_typed",
            9,
            4,
            "/datum/override_probe/proc/plain_method",
        ),
    ] {
        let item = ast
            .items
            .iter()
            .find(|item| item.header.contains(&format!("{name}(")))
            .unwrap();
        let compiled = compile_fixture_proc_with_bindings(&item.children, &bindings).unwrap();
        let mut ledger = Ledger::default();
        if id == 6 {
            ledger
                .bind(reference(Table::Proc, target_path), target_id)
                .unwrap();
        } else {
            ledger
                .bind(reference(Table::String, "plain method"), 440)
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
fn callback_constructor_chain_lowers() {
    let ast = dm_syntax::parse("/proc/probe(message)\n    return new /datum/callback/verb_callback(src, (nameof(/mob.proc/say)), message):InvokeAsync()\n");
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let compiled =
        compile_simple_proc_with_params(&ast.items[0].children, &["message".into()]).unwrap();
    assert!(compiled
        .class_paths
        .contains(&SymbolId::of("/datum/callback/verb_callback")));
    assert!(string_texts(&compiled).contains(&"InvokeAsync".into()));
}

#[test]
fn image_and_animate_calls_match_native_bytecode() {
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/native_compiler/builtin_catalog.native.bin"
    ))
    .unwrap();
    for (name, parameters, body) in [
        (
            "image_named",
            "a,b,c",
            "return image(icon=a, loc=b, layer=c)",
        ),
        ("image_mixed", "a,b", "return image(a, loc=b)"),
        ("image_one", "a", "return image(a)"),
        (
            "animate_named",
            "a,b",
            "animate(a, pixel_x=b, time=5)\n    return 1",
        ),
        ("animate_one", "a", "animate(a)\n    return 1"),
        ("animate_two", "a,b", "animate(a,b)\n    return 1"),
    ] {
        let path = format!("/proc/catalog_{name}");
        let source = format!("{path}({parameters})\n    {body}\n");
        let ast = dm_syntax::parse(&source);
        assert!(ast.diagnostics.is_empty(), "{name}: {:?}", ast.diagnostics);
        let params = parameters.split(',').map(str::to_owned).collect::<Vec<_>>();
        let compiled = compile_simple_proc_with_params(&ast.items[0].children, &params).unwrap();
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
        let id = native
            .procs
            .iter()
            .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
            .unwrap();
        assert_eq!(linked.words, native.proc_code_words(id).unwrap(), "{path}");
    }
}

#[test]
fn safe_postfix_guards_cover_indices_members_and_calls_but_stop_at_groups() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/native_compiler/safe_postfix_chain/probe.dm"
    ));
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/native_compiler/safe_postfix_chain/probe.native.bin"
    ))
    .unwrap();
    for name in ["index_chain", "member_chain", "call_chain", "grouped_index"] {
        let path = format!("/proc/{name}");
        let item = ast
            .items
            .iter()
            .find(|item| item.header.starts_with(&format!("{path}(")))
            .unwrap();
        let compiled = compile_fixture_proc_with_bindings(
            &item.children,
            &LowerBindings {
                parameters: vec!["L".into()],
                parameter_types: HashMap::from([("L".into(), "/datum/chain_probe".into())]),
                global_procs: HashMap::from([(
                    "index_key".into(),
                    reference(Table::Proc, "/proc/index_key"),
                )]),
                ..LowerBindings::default()
            },
        )
        .unwrap();
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
            .assign(Table::Proc, [reference(Table::Proc, "/proc/index_key")])
            .unwrap();
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        let id = native
            .procs
            .iter()
            .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
            .unwrap();
        for words in [&linked.words[..], native.proc_code_words(id).unwrap()] {
            let decoded = byond_dmb::bytecode::decode(words).unwrap();
            let guard = decoded
                .iter()
                .find(|instruction| instruction.opcode == 317)
                .unwrap();
            let target = guard.branch_targets().unwrap()[0] as usize;
            if name == "grouped_index" {
                assert!(
                    target
                        <= decoded
                            .iter()
                            .find(|instruction| instruction.opcode == opcode::LIST_GET)
                            .unwrap()
                            .offset
                );
            } else {
                assert_eq!(
                    target,
                    decoded
                        .iter()
                        .find(|instruction| instruction.opcode == opcode::RET)
                        .unwrap()
                        .offset,
                    "{name}"
                );
            }
        }
    }
}

#[test]
fn renamed_verbs_use_native_verb_call_selectors() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/native_compiler/verb_call_selectors/probe.dm"
    ));
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/native_compiler/verb_call_selectors/probe.native.bin"
    ))
    .unwrap();
    let owner = "/mob/selector_probe";
    let verb = "/mob/selector_probe/verb/halt_probe";
    let shared = Arc::new(SharedLowerBindings {
        member_procs: HashMap::from([(
            owner.into(),
            HashMap::from([("halt_probe".into(), reference(Table::Proc, verb))]),
        )]),
        ..SharedLowerBindings::default()
    });
    for (child, parameters) in [(1, vec![]), (2, vec!["M".into()])] {
        let compiled = compile_fixture_proc_with_bindings(
            &ast.items[0].children[child].children,
            &LowerBindings {
                parameters,
                parameter_types: HashMap::from([("M".into(), owner.into())]),
                current_type_path: Some(owner.into()),
                shared: Some(shared.clone()),
                ..LowerBindings::default()
            },
        )
        .unwrap();
        let mut ledger = Ledger::default();
        ledger
            .assign(Table::Proc, [reference(Table::Proc, verb)])
            .unwrap();
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        assert!(linked.words.contains(&0xffe0));
        assert!(!linked.words.contains(&0xffdf));
        let path = format!(
            "{owner}/proc/{}",
            if child == 1 {
                "bare_probe"
            } else {
                "member_probe"
            }
        );
        let id = native
            .procs
            .iter()
            .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
            .unwrap();
        assert!(native
            .proc_code_words(id)
            .unwrap()
            .contains(&if child == 1 { 0xffe0 } else { 0xffde }));
    }
}

#[test]
fn current_and_inherited_members_shadow_global_procedures() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/native_compiler/member_global_shadowing/probe.dm"
    ));
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/native_compiler/member_global_shadowing/probe.native.bin"
    ))
    .unwrap();
    let shared = Arc::new(SharedLowerBindings {
        global_procs: HashMap::from([(
            "collision".into(),
            reference(Table::Proc, "/proc/collision"),
        )]),
        known_member_procs: HashMap::from([(
            "/datum/shadow".into(),
            BTreeSet::from(["collision".into()]),
        )]),
        parent_types: HashMap::from([("/datum/shadow/child".into(), "/datum/shadow".into())]),
        ..SharedLowerBindings::default()
    });
    for (index, owner, path, expected) in [
        (2, "/datum/shadow", "/datum/shadow/proc/probe", opcode::CALL),
        (
            3,
            "/datum/shadow/child",
            "/datum/shadow/child/proc/inherited_probe",
            opcode::CALL,
        ),
        (
            4,
            "/datum/shadow",
            "/datum/shadow/proc/explicit_global",
            opcode::CALL_GLOB,
        ),
    ] {
        let compiled = compile_fixture_proc_with_bindings(
            &ast.items[index].children,
            &LowerBindings {
                current_type_path: Some(owner.into()),
                shared: Some(shared.clone()),
                ..LowerBindings::default()
            },
        )
        .unwrap();
        let calls: Vec<_> = compiled
            .code
            .items
            .iter()
            .filter_map(|item| match item {
                CodeItem::Instruction(instruction)
                    if matches!(instruction.opcode, opcode::CALL | opcode::CALL_GLOB) =>
                {
                    Some(instruction.opcode)
                }
                _ => None,
            })
            .collect();
        let id = native
            .procs
            .iter()
            .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
            .unwrap();
        assert_eq!(native.proc_code_words(id).unwrap()[0], expected, "{path}");
        assert_eq!(calls, vec![expected], "{path}");
    }
}

#[test]
fn bound_project_rejects_unknown_bare_calls_but_allows_dynamic_members() {
    let ast = dm_syntax::parse("/proc/probe(receiver)\n    missing_builtin()\n");
    assert!(compile_simple_proc_with_params(&ast.items[0].children, &["receiver".into()]).is_ok());
    let bindings = LowerBindings {
        parameters: vec!["receiver".into()],
        shared: Some(Arc::new(SharedLowerBindings::default())),
        ..LowerBindings::default()
    };
    let errors = compile_fixture_proc_with_bindings(&ast.items[0].children, &bindings).unwrap_err();
    assert!(errors[0]
        .reason
        .contains("unresolved unqualified procedure: missing_builtin"));
    let dynamic = dm_syntax::parse("/proc/probe(receiver)\n    receiver.dynamic_method()\n");
    assert!(compile_fixture_proc_with_bindings(&dynamic.items[0].children, &bindings).is_ok());
    let inherited = dm_syntax::parse("/datum/child/proc/probe()\n    declared_method()\n");
    let bindings = LowerBindings {
        current_type_path: Some("/datum/child".into()),
        shared: Some(Arc::new(SharedLowerBindings {
            known_member_procs: HashMap::from([(
                "/datum/parent".into(),
                BTreeSet::from(["declared_method".into()]),
            )]),
            parent_types: HashMap::from([("/datum/child".into(), "/datum/parent".into())]),
            ..SharedLowerBindings::default()
        })),
        ..LowerBindings::default()
    };
    let compiled =
        compile_fixture_proc_with_bindings(&inherited.items[0].children, &bindings).unwrap();
    assert!(string_texts(&compiled).contains(&"declared method".into()));
}

#[test]
fn load_ext_and_handle_calls_match_native() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/native_compiler/load_ext.dm"
    ));
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/native_compiler/load_ext.native.bin"
    ))
    .unwrap();
    for (index, parameters) in [
        vec!["library", "function"],
        vec!["function", "value"],
        vec!["function", "values"],
    ]
    .iter()
    .enumerate()
    {
        let params = parameters
            .iter()
            .map(|name| (*name).to_owned())
            .collect::<Vec<_>>();
        let compiled =
            compile_simple_proc_with_params(&ast.items[index].children, &params).unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        assert_eq!(
            linked.words,
            native.proc_code_words(index).unwrap(),
            "proc {index}"
        );
    }
}

#[test]
fn chained_dynamic_and_external_calls_match_native_bytecode() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/chained_call/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/chained_call/probe.native.bin"
    ))
    .unwrap();
    for (index, item) in ast.items.iter().enumerate() {
        let parameter = if index == 0 { "target" } else { "library" };
        let compiled =
            compile_simple_proc_with_params(&item.children, &[parameter.into()]).unwrap();
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
        assert_eq!(
            linked.words,
            native.proc_code_words(index).unwrap(),
            "proc {index}"
        );
    }
}

#[test]
fn named_filter_matches_native_bytecode() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/filter_named/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let item = ast
        .items
        .iter()
        .find(|item| item.header.starts_with("/proc/probe_filter("))
        .unwrap();
    let compiled =
        compile_simple_proc_with_params(&item.children, &["a".into(), "b".into()]).unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/filter_named/probe.native.bin"
    ))
    .unwrap();
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
    let id = native
        .procs
        .iter()
        .position(|proc| native.string(proc.strings[0]) == Some(b"/proc/probe_filter".as_slice()))
        .unwrap();
    assert_eq!(linked.words, native.proc_code_words(id).unwrap());
}

#[test]
fn single_target_chained_calls_match_native_bytecode() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/chained_call_one/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/chained_call_one/probe.native.bin"
    ))
    .unwrap();
    for (index, item) in ast.items.iter().enumerate() {
        let compiled = compile_simple_proc_with_params(&item.children, &["fn".into()]).unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        assert_eq!(linked.words, native.proc_code_words(index).unwrap());
    }
}

#[test]
fn member_reads_writes_and_calls_link_through_receiver() {
    let ast =
        dm_syntax::parse("/proc/test(obj)\n  obj.value = 3\n  obj.update(2)\n  return obj.value\n");
    let compiled =
        compile_simple_proc_with_params(&ast.items[0].children, &["obj".into()]).unwrap();
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
    assert!(decoded
        .iter()
        .any(|instruction| instruction.opcode == opcode::SET_VAR));
    // A discarded call uses native CallStatement (0x2a), whose skipped
    // raw word must be the Pop marker. Expression calls still use CALL.
    let call = decoded
        .iter()
        .find(|instruction| instruction.opcode == 0x2a)
        .unwrap();
    assert_eq!(
        linked.words[call.offset + 1 + call.operands.len()],
        opcode::POP
    );
    assert!(decoded
        .iter()
        .any(|instruction| instruction.opcode == opcode::GET_VAR));
}

#[test]
fn computed_receiver_call_preserves_cache_across_arguments() {
    let ast = dm_syntax::parse("/proc/test(x)\n  return make(x).update(2)\n");
    let compiled = compile_simple_proc_with_params(&ast.items[0].children, &["x".into()]).unwrap();
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
    assert!(decoded
        .iter()
        .any(|instruction| instruction.opcode == opcode::PUSH_CACHE));
    assert!(decoded
        .iter()
        .any(|instruction| instruction.opcode == opcode::POP_CACHE));
    assert!(decoded
        .iter()
        .any(|instruction| instruction.opcode == opcode::CALL));
}

#[test]
fn src_call_uses_native_compound_variable() {
    let ast = dm_syntax::parse("/proc/test()\n  return foo(1)\n");
    let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
    let mut ledger = Ledger::default();
    ledger.bind(reference(Table::String, "foo"), 438).unwrap();
    let linked = link_proc(&compiled.code, &ledger).unwrap();
    assert!(linked
        .words
        .windows(6)
        .any(|w| w == [0x29, 0xffdc, 0xffce, 0xffdd, 438, 1]));
}

#[test]
fn named_icon_matches_native_fixture() {
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/constructor_branch_entries/probe.native.bin"
    ))
    .unwrap();
    let ast = dm_syntax::parse("/proc/icon_named(flag,path)\n  if(!flag)\n    return\n  return icon(icon=path, icon_state=\"x\")\n");
    let compiled =
        compile_simple_proc_with_params(&ast.items[0].children, &["flag".into(), "path".into()])
            .unwrap();
    let mut ledger = Ledger::default();
    for string in &compiled.strings {
        let id = native
            .strings
            .iter()
            .position(|entry| entry.data == string.bytes.as_ref())
            .unwrap();
        ledger
            .bind(reference(Table::String, string), id as u32)
            .unwrap();
    }
    let linked = link_proc(&compiled.code, &ledger).unwrap();
    let proc_id = native
        .procs
        .iter()
        .position(|proc| native.string(proc.strings[0]) == Some(b"/proc/icon_named".as_slice()))
        .unwrap();
    let native_words = native.proc_code_words(proc_id).unwrap();
    assert_eq!(&linked.words[8..], &native_words[8..]);
}

#[test]
fn pick_prob_syntax_uses_numeric_weight_without_probability_call() {
    for (bare, sugar) in [("1", "prob(1)"), ("weight", "prob(weight)")] {
        let compile = |weight: &str| {
            let ast = dm_syntax::parse(&format!(
                "/proc/test(weight)\n    return pick({weight};7, {weight};9)\n"
            ));
            let compiled =
                compile_simple_proc_with_params(&ast.items[0].children, &["weight".into()])
                    .unwrap();
            link_proc(&compiled.code, &Ledger::default()).unwrap().words
        };
        assert_eq!(compile(bare), compile(sugar));
    }
}

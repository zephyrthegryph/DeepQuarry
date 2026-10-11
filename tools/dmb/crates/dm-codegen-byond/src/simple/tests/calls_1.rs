//! Calls lowering regression tests.
use super::*;

#[test]
fn direct_discarded_calls_match_native_ownership_modes_and_pop_markers() {
    fn find<'a>(items: &'a [Item], name: &str) -> Option<&'a Item> {
        for item in items {
            if item.header.split('(').next()?.rsplit('/').next() == Some(name) {
                return Some(item);
            }
            if let Some(found) = find(&item.children, name) {
                return Some(found);
            }
        }
        None
    }
    struct Debug;
    impl DebugSourceProvider for Debug {
        fn entry_ordinal(&self) -> Result<u32, String> {
            Ok(0)
        }
        fn ordinal(&self, offset: usize) -> Result<u32, String> {
            u32::try_from(offset).map_err(|error| error.to_string())
        }
    }
    type Cases<'a> = &'a [(&'a str, &'a [&'a str])];
    let fixtures: [(&str, &[u8], Cases<'_>); 3] = [
        (
            include_str!("../../../../../fixtures/lowering/self_call_ownership.dm"),
            include_bytes!("../../../../../fixtures/lowering/self_call_ownership.bin"),
            &[
                ("discard", &[]),
                ("named", &[]),
                ("with_args", &["L"]),
                ("value", &[]),
                ("choice", &["a"]),
                ("reverse", &["a"]),
                ("multiline", &[]),
            ],
        ),
        (
            include_str!("../../../../../fixtures/lowering/computed_call_ownership.dm"),
            include_bytes!("../../../../../fixtures/lowering/computed_call_ownership.bin"),
            &[
                ("computed_empty", &["O"]),
                ("computed_positional", &["O"]),
                ("computed_named", &["O"]),
                ("computed_arglist", &["O", "L"]),
                ("computed_conditional", &["a", "O", "P"]),
                ("computed_short", &["a", "O"]),
                ("computed_value", &["O"]),
                ("computed_safe", &["O"]),
                ("direct_child", &["O"]),
                ("direct_owner", &["O"]),
                ("direct_multiline", &["O"]),
            ],
        ),
        (
            include_str!("../../../../../fixtures/lowering/grouped_call_ownership.dm"),
            include_bytes!("../../../../../fixtures/lowering/grouped_call_ownership.bin"),
            &[
                ("group_self", &[]),
                ("group_direct", &["O"]),
                ("group_computed", &["O"]),
            ],
        ),
    ];
    for (source, bytes, cases) in fixtures {
        let ast = dm_syntax::parse(source);
        let native = byond_dmb::dmb::Dmb::from_bytes(bytes).unwrap();
        for &(name, parameters) in cases {
            let item = find(&ast.items, name).unwrap();
            let id = native
                .procs
                .iter()
                .position(|proc| {
                    native
                        .string(proc.strings[0])
                        .is_some_and(|path| path.ends_with(format!("/{name}").as_bytes()))
                })
                .unwrap();
            let native_calls = byond_dmb::bytecode::decode(native.proc_code_words(id).unwrap())
                .unwrap()
                .into_iter()
                .filter(|instruction| matches!(instruction.opcode, 0x29 | 0x2a))
                .map(|instruction| instruction.opcode)
                .collect::<Vec<_>>();
            for debug in [false, true] {
                let mut bindings = LowerBindings {
                    parameters: parameters.iter().map(|name| (*name).into()).collect(),
                    ..Default::default()
                };
                bindings
                    .global_procs
                    .insert("getter".into(), reference(Table::Proc, "/proc/getter"));
                for parameter in ["O", "P"] {
                    bindings
                        .parameter_types
                        .insert(parameter.into(), "/datum/ownership".into());
                }
                bindings.parameter_types.insert("L".into(), "/list".into());
                let compiled = compile_with_lookup(
                    &item.children,
                    None,
                    &bindings,
                    None,
                    debug.then_some(&Debug as &dyn DebugSourceProvider),
                )
                .unwrap();
                let frozen = crate::freeze_proc(&compiled.code).unwrap();
                let words = frozen.code().words();
                let decoded = byond_dmb::bytecode::decode(words.as_ref()).unwrap();
                let calls = decoded
                    .iter()
                    .filter(|instruction| matches!(instruction.opcode, 0x29 | 0x2a))
                    .map(|instruction| instruction.opcode)
                    .collect::<Vec<_>>();
                assert_eq!(calls, native_calls, "{name}, debug={debug}");
                for call in decoded
                    .iter()
                    .filter(|instruction| instruction.opcode == 0x2a)
                {
                    let marker = call.offset + 1 + call.operands.len();
                    assert_eq!(words[marker], opcode::POP, "{name}, debug={debug}");
                    assert!(
                        decoded.iter().all(|instruction| !instruction
                            .branch_targets()
                            .unwrap()
                            .contains(&(marker as u32))),
                        "branch enters skipped Pop: {name}"
                    );
                }
            }
        }
    }
}

#[test]
fn procedure_and_verb_constructors_use_native_proc_references() {
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/native_compiler/proc_namespace.native.bin"
    ))
    .unwrap();
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/native_compiler/proc_namespace.dm"
    ));
    let owner = SymbolId::of("/datum/namespace_probe");
    for (name, member, captured, id) in [
        (
            "new_verb",
            "third",
            SymRef::Verb {
                owner,
                name: SymbolId::of("third"),
                occurrence: 0,
            },
            2,
        ),
        (
            "new_proc",
            "first",
            SymRef::Proc {
                owner,
                name: SymbolId::of("first"),
                occurrence: 0,
            },
            0,
        ),
    ] {
        let item = ast
            .items
            .iter()
            .find(|item| item.header == format!("/proc/{name}()"))
            .unwrap();
        let compiled = crate::compile_simple_proc_with_bindings(
            &item.children,
            &LowerBindings {
                shared: Some(Arc::new(SharedLowerBindings {
                    member_procs: HashMap::from([(
                        "/datum/namespace_probe".into(),
                        HashMap::from([(member.into(), captured)]),
                    )]),
                    ..Default::default()
                })),
                ..Default::default()
            },
        )
        .unwrap();
        assert!(compiled.class_paths.is_empty());
        let mut ledger = Ledger::default();
        ledger.bind(captured, id).unwrap();
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        let proc = native
            .procs
            .iter()
            .position(|proc| {
                native.string(proc.strings[0]) == Some(format!("/proc/{name}").as_bytes())
            })
            .unwrap();
        assert_eq!(linked.words, native.proc_code_words(proc).unwrap());
    }
}

#[test]
fn parent_call_matches_native_inherited_proc() {
    let ast = dm_syntax::parse("/datum/child/result()\n    return ..() + 1\n");
    let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
    let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/inheritance.native.bin"
    ))
    .unwrap();
    let id = native
        .procs
        .iter()
        .position(|proc| {
            native
                .string(proc.strings[0])
                .is_some_and(|path| path.ends_with(b"/fixture_child/result"))
        })
        .unwrap();
    assert_eq!(linked.words, native.proc_code_words(id).unwrap());
}

#[test]
fn parent_call_with_explicit_arguments_uses_native_call_parent_args() {
    let ast = dm_syntax::parse(
        "/datum/child/Initialize(mapload, amount)\n    return ..(mapload, amount + 1)\n",
    );
    let compiled = compile_simple_proc_with_params(
        &ast.items[0].children,
        &["mapload".into(), "amount".into()],
    )
    .unwrap();
    let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
    let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
    let call = decoded
        .iter()
        .find(|instruction| instruction.opcode == 0x2d)
        .unwrap();
    assert_eq!(call.operands, vec![2]);
}

#[test]
fn implicit_parent_forwarding_and_explicit_empty_arguments_match_native() {
    let source = include_str!("../../../../../fixtures/native_compiler/parent_forwarding.dm");
    let ast = dm_syntax::parse(source);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/native_compiler/parent_forwarding.native.bin"
    ))
    .unwrap();
    for (owner, method, params) in [
        ("/datum/forwarding/child", "single", vec!["value".into()]),
        (
            "/datum/forwarding/child",
            "multiple",
            vec!["a".into(), "b".into()],
        ),
        ("/datum/forwarding/empty", "single", vec!["value".into()]),
    ] {
        let item = ast.items.iter().find(|item| item.header == owner).unwrap();
        let body = &item
            .children
            .iter()
            .find(|item| item.header.starts_with(&format!("{method}(")))
            .unwrap()
            .children;
        let compiled = compile_simple_proc_with_params(body, &params).unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        let path = format!("{owner}/{method}");
        let proc_id = native
            .procs
            .iter()
            .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
            .unwrap();
        assert_eq!(
            linked.words,
            native.proc_code_words(proc_id).unwrap(),
            "{path}"
        );
    }
}

#[test]
fn parent_arglist_matches_native_fixture() {
    let ast = dm_syntax::parse("/proc/arglist_root_super(list/L)\n    return ..(arglist(L))\n");
    let compiled = compile_simple_proc_with_params(&ast.items[0].children, &["L".into()]).unwrap();
    let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/arglist_builtin_forms.native.bin"
    ))
    .unwrap();
    let id = native
        .procs
        .iter()
        .position(|proc| {
            native.string(proc.strings[0]) == Some(b"/proc/arglist_root_super".as_slice())
        })
        .unwrap();
    assert_eq!(linked.words, native.proc_code_words(id).unwrap());
}

#[test]
fn self_arglist_matches_native_fixture() {
    let ast = dm_syntax::parse("/proc/arglist_self(list/L)\n    return .(arglist(L))\n");
    let compiled = compile_simple_proc_with_params(&ast.items[0].children, &["L".into()]).unwrap();
    let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/arglist_builtin_forms.native.bin"
    ))
    .unwrap();
    let id = native
        .procs
        .iter()
        .position(|proc| native.string(proc.strings[0]) == Some(b"/proc/arglist_self".as_slice()))
        .unwrap();
    assert_eq!(linked.words, native.proc_code_words(id).unwrap());
}

#[test]
fn isnull_call_uses_native_builtin_opcode() {
    let ast = dm_syntax::parse("/proc/test()\n    return isnull(rand(1, 2))\n");
    let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
    let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
    let ours = byond_dmb::bytecode::decode(&linked.words).unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/null_equality_ownership/probe.native.bin"
    ))
    .unwrap();
    let id = native
        .procs
        .iter()
        .position(|proc| native.string(proc.strings[0]) == Some(b"/proc/builtin_null".as_slice()))
        .unwrap();
    let theirs = byond_dmb::bytecode::decode(native.proc_code_words(id).unwrap()).unwrap();
    assert!(ours
        .iter()
        .any(|instruction| instruction.opcode == opcode::IS_NULL));
    assert!(theirs
        .iter()
        .any(|instruction| instruction.opcode == opcode::IS_NULL));
}

#[test]
fn min_max_arglist_match_native_fixture() {
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/builtin_final.native.bin"
    ))
    .unwrap();
    for (name, body) in [
        ("bf_maxlist", "return max(arglist(L))"),
        ("bf_minlist", "return min(arglist(L))"),
    ] {
        let source = format!("/proc/{name}(L)\n    {body}\n");
        let ast = dm_syntax::parse(&source);
        let compiled =
            compile_simple_proc_with_params(&ast.items[0].children, &["L".into()]).unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        let path = format!("/proc/{name}");
        let id = native
            .procs
            .iter()
            .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
            .unwrap();
        assert_eq!(linked.words, native.proc_code_words(id).unwrap(), "{name}");
    }
}

#[test]
fn regex_calls_match_native_fixture() {
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/call_overloads.native.bin"
    ))
    .unwrap();
    for (name, params, body) in [
        ("o_regex", vec!["t", "f"], "return regex(t,f)"),
        ("o_regex_one", vec!["t"], "return regex(t)"),
        ("o_regex_quote", vec!["t"], "return regex(t,1)"),
    ] {
        let source = format!("/proc/{name}()\n    {body}\n");
        let ast = dm_syntax::parse(&source);
        let compiled = compile_simple_proc_with_params(
            &ast.items[0].children,
            &params.into_iter().map(str::to_owned).collect::<Vec<_>>(),
        )
        .unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        let path = format!("/proc/{name}");
        let id = native
            .procs
            .iter()
            .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
            .unwrap();
        assert_eq!(linked.words, native.proc_code_words(id).unwrap(), "{name}");
    }
    let raw = dm_syntax::parse("/proc/test()\n    return regex(@\"^\\w+$\", \"g\")\n");
    let compiled = compile_simple_proc(&raw.items[0].children).unwrap();
    assert!(compiled
        .strings
        .iter()
        .any(|value| value.bytes.as_ref() == b"^\\w+$"));
}

#[test]
fn catalog_calls_match_native_procedure_bodies() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/native_compiler/builtin_catalog.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/native_compiler/builtin_catalog.native.bin"
    ))
    .unwrap();
    for item in &ast.items {
        let path = item.header.split('(').next().unwrap();
        let Some(name) = path.strip_prefix("/proc/catalog_") else {
            continue;
        };
        if crate::builtin_catalog::lookup(name).is_none() {
            continue;
        }
        let params: Vec<String> = item
            .header
            .split_once('(')
            .and_then(|(_, tail)| tail.split_once(')'))
            .unwrap()
            .0
            .split(',')
            .map(|arg| arg.trim().to_owned())
            .collect();
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
fn named_calls_follow_native_argument_list_shapes() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/named_calls/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/named_calls/probe.native.bin"
    ))
    .unwrap();
    for (index, path, params) in [
        (1, "/proc/named", vec![]),
        (3, "/proc/member", vec!["x".into()]),
        (4, "/proc/newthing", vec![]),
    ] {
        let mut bindings = LowerBindings {
            parameters: params,
            ..LowerBindings::default()
        };
        bindings
            .global_procs
            .insert("f".into(), reference(Table::Proc, "/proc/f"));
        let compiled =
            compile_fixture_proc_with_bindings(&ast.items[index].children, &bindings).unwrap();
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
        ledger
            .assign(Table::Proc, vec![reference(Table::Proc, "/proc/f")])
            .unwrap();
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        let ours = byond_dmb::bytecode::decode(&linked.words).unwrap();
        let native_id = native
            .procs
            .iter()
            .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
            .unwrap();
        let expected =
            byond_dmb::bytecode::decode(native.proc_code_words(native_id).unwrap()).unwrap();
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
    }
}

#[test]
fn omitted_middle_call_argument_matches_native_bytecode() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/call_hole/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let mut bindings = LowerBindings::default();
    bindings.global_procs.insert(
        "call_hole_target".into(),
        reference(Table::Proc, "/proc/call_hole_target"),
    );
    let compiled = compile_fixture_proc_with_bindings(&ast.items[1].children, &bindings).unwrap();
    let mut ledger = Ledger::default();
    ledger
        .bind(reference(Table::Proc, "/proc/call_hole_target"), 0)
        .unwrap();
    let linked = link_proc(&compiled.code, &ledger).unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/call_hole/probe.native.bin"
    ))
    .unwrap();
    assert_eq!(linked.words, native.proc_code_words(1).unwrap());
}

#[test]
fn arglist_dynamic_and_filter_match_native() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/arglist_dynamic/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/arglist_dynamic/probe.native.bin"
    ))
    .unwrap();
    for (id, item) in ast.items.iter().enumerate() {
        let params = match id {
            0 | 1 => vec!["fn", "L"],
            2 => vec!["L"],
            _ => vec!["target", "name", "L"],
        }
        .into_iter()
        .map(str::to_owned)
        .collect::<Vec<_>>();
        let compiled = compile_simple_proc_with_params(&item.children, &params).unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        assert_eq!(
            linked.words,
            native.proc_code_words(id).unwrap(),
            "proc {id}"
        );
    }
}

#[test]
fn quoted_named_argument_key_matches_native_image_call() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/named_keys/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/named_keys/probe.native.bin"
    ))
    .unwrap();
    let compiled = compile_simple_proc_with_params(&ast.items[0].children, &["a".into()]).unwrap();
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
    assert_eq!(linked.words, native.proc_code_words(0).unwrap());
}

#[test]
fn member_arglist_and_colon_calls_match_native() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/member_arglist/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/member_arglist/probe.native.bin"
    ))
    .unwrap();
    for id in 1..4 {
        let params = if id == 3 {
            vec!["D".into()]
        } else {
            vec!["D".into(), "L".into()]
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

#[test]
fn icon_mixed_positional_and_named_args_match_native() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/icon_mixed/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let compiled =
        compile_simple_proc_with_params(&ast.items[0].children, &["a".into(), "b".into()]).unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/icon_mixed/probe.native.bin"
    ))
    .unwrap();
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
    assert_eq!(linked.words, native.proc_code_words(0).unwrap());
}

#[test]
fn global_namespace_call_and_vars_match_native() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/global_namespace/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/global_namespace/probe.native.bin"
    ))
    .unwrap();
    let bindings = LowerBindings {
        global_procs: HashMap::from([("foo".into(), reference(Table::Proc, "/proc/foo"))]),
        ..LowerBindings::default()
    };
    for id in 1..3 {
        let compiled =
            compile_fixture_proc_with_bindings(&ast.items[id].children, &bindings).unwrap();
        let mut ledger = Ledger::default();
        if id == 1 {
            ledger.bind(reference(Table::Proc, "/proc/foo"), 0).unwrap();
        } else {
            ledger.bind(SymRef::BuiltinGlobalVars, 177).unwrap();
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
fn named_safe_method_call_matches_native() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/safe_named_call/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/safe_named_call/probe.native.bin"
    ))
    .unwrap();
    let compiled = compile_simple_proc_with_params(&ast.items[1].children, &["D".into()]).unwrap();
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
    assert_eq!(linked.words, native.proc_code_words(1).unwrap());
}

#[test]
fn src_and_global_arglist_calls_match_native() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/src_arglist/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/src_arglist/probe.native.bin"
    ))
    .unwrap();
    let bindings = LowerBindings {
        parameters: vec!["L".into()],
        global_procs: HashMap::from([("baz".into(), reference(Table::Proc, "/proc/baz"))]),
        ..LowerBindings::default()
    };
    for (item, id) in [(1, 1), (3, 3)] {
        let compiled =
            compile_fixture_proc_with_bindings(&ast.items[item].children, &bindings).unwrap();
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
        if item == 3 {
            ledger.bind(reference(Table::Proc, "/proc/baz"), 2).unwrap();
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
fn constructor_arglist_matches_native() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/new_arglist/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/new_arglist/probe.native.bin"
    ))
    .unwrap();
    for id in 0..2 {
        let params = if id == 0 {
            vec!["path".into(), "L".into()]
        } else {
            vec!["L".into()]
        };
        let compiled = compile_simple_proc_with_params(&ast.items[id].children, &params).unwrap();
        let mut ledger = Ledger::default();
        if id == 1 {
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
fn call_member_aug_lowers_without_unsupported_target() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/call_member_aug/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let item = ast
        .items
        .iter()
        .find(|item| item.header.contains("/proc/add("))
        .unwrap();
    let bindings = LowerBindings {
        parameters: vec!["D".into(), "n".into()],
        ..LowerBindings::default()
    };
    let compiled = compile_fixture_proc_with_bindings(&item.children, &bindings).unwrap();
    let opcodes: Vec<_> = compiled
        .code
        .items
        .iter()
        .filter_map(|item| match item {
            CodeItem::Instruction(instruction) => Some(instruction.opcode),
            _ => None,
        })
        .collect();
    assert!(opcodes.contains(&opcode::AUG_ADD));
}

#[test]
fn rgb_named_matches_native() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/rgb_named/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/rgb_named/probe.native.bin"
    ))
    .unwrap();
    for id in 0..2 {
        let compiled = compile_simple_proc_with_params(
            &ast.items[id].children,
            &["a".into(), "b".into(), "c".into(), "d".into()],
        )
        .unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        assert_eq!(
            linked.words,
            native.proc_code_words(id).unwrap(),
            "proc {id}"
        );
    }
}

#[test]
fn parent_named_matches_native() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/parent_named/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/parent_named/probe.native.bin"
    ))
    .unwrap();
    let compiled =
        compile_simple_proc_with_params(&ast.items[1].children, &["a".into(), "infix".into()])
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
    assert_eq!(linked.words, native.proc_code_words(1).unwrap());
}

#[test]
fn global_call_preserves_captured_occurrence_identity() {
    let ast = dm_syntax::parse("/proc/test()\n    return target()\n");
    let captured = SymRef::Proc {
        owner: SymbolId::of("/"),
        name: SymbolId::of("target"),
        occurrence: 37,
    };
    let bindings = LowerBindings {
        global_procs: HashMap::from([("target".into(), captured)]),
        ..Default::default()
    };
    let compiled = compile_fixture_proc_with_bindings(&ast.items[0].children, &bindings).unwrap();
    let mut references = Vec::new();
    compiled
        .code
        .for_each_reference(|reference| references.push(reference));
    assert!(references.contains(&captured));
    let mut ledger = Ledger::default();
    ledger.bind(captured, 91).unwrap();
    let linked = link_proc(&compiled.code, &ledger).unwrap();
    assert!(linked.words.contains(&91));
}

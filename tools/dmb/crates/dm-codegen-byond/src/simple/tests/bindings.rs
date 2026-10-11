//! Bindings lowering regression tests.
use super::*;

#[test]
fn modulo_constant_folding_truncates_operands_like_native() {
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/native_compiler/integer_modulo.native.bin"
    ))
    .unwrap();
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/native_compiler/integer_modulo.dm"
    ));
    for id in 0..3 {
        let compiled = compile_simple_proc(&ast.items[id].children).unwrap();
        assert_eq!(
            link_proc(&compiled.code, &Ledger::default()).unwrap().words,
            native.proc_code_words(id).unwrap()
        );
    }
    for source in [
        "5 % 0.5",
        "-2147483648 % -1",
        "1.#INF % 2",
        "2147483648 % 2",
    ] {
        assert!(
            fold_number(&parse_expression(source).expr.unwrap()).is_none(),
            "{source}"
        );
    }
}

#[test]
fn initial_globals_locals_and_parameters_match_native() {
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/native_compiler/global_initial.native.bin"
    ))
    .unwrap();
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/native_compiler/global_initial.dm"
    ));
    for name in [
        "initial_global",
        "initial_global_qualified",
        "saved_global",
        "initial_local",
    ] {
        let item = ast
            .items
            .iter()
            .find(|item| item.header.starts_with(&format!("/proc/{name}(")))
            .unwrap();
        let bindings = LowerBindings {
            globals: BTreeSet::from(["initial_probe".into()]),
            parameters: if name == "initial_local" {
                vec!["value".into()]
            } else {
                vec![]
            },
            fields: if name == "initial_local" {
                BTreeSet::from(["local".into(), "value".into()])
            } else {
                BTreeSet::new()
            },
            ..Default::default()
        };
        let compiled = compile_fixture_proc_with_bindings(&item.children, &bindings).unwrap();
        let mut ledger = Ledger::default();
        let id = native
            .variables
            .iter()
            .position(|variable| native.string(variable.name) == Some(b"initial_probe"))
            .unwrap();
        ledger
            .bind(reference(Table::Variable, "initial_probe"), id as u32)
            .unwrap();
        let path = format!("/proc/{name}");
        let id = native
            .procs
            .iter()
            .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
            .unwrap();
        assert_eq!(
            link_proc(&compiled.code, &ledger).unwrap().words,
            native.proc_code_words(id).unwrap()
        );
    }
}

#[test]
fn default_arguments_and_mutated_iteration_match_native() {
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/native_compiler/control_runtime.native.bin"
    ))
    .unwrap();
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/native_compiler/control_runtime.dm"
    ));
    for (name, params, defaults) in [
        (
            "control_defaults",
            vec!["a".into(), "b".into(), "c".into()],
            vec![Some("3".into()), Some("4".into()), Some("5".into())],
        ),
        ("control_iteration", vec![], vec![]),
    ] {
        let item = ast
            .items
            .iter()
            .find(|item| item.header.starts_with(&format!("/proc/{name}(")))
            .unwrap();
        let bindings = LowerBindings {
            parameters: params,
            parameter_defaults: defaults,
            global_procs: HashMap::from([(
                "control_defaults".into(),
                reference(Table::Proc, "/proc/control_defaults"),
            )]),
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
        let helper = native
            .procs
            .iter()
            .position(|proc| native.string(proc.strings[0]) == Some(b"/proc/control_defaults"))
            .unwrap();
        ledger
            .bind(
                reference(Table::Proc, "/proc/control_defaults"),
                helper as u32,
            )
            .unwrap();
        let path = format!("/proc/{name}");
        let id = native
            .procs
            .iter()
            .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
            .unwrap();
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        assert_eq!(linked.words, native.proc_code_words(id).unwrap(), "{name}");
    }
}

#[test]
fn untyped_lexical_bindings_do_not_inherit_outer_type_queries() {
    use dm_ir::{ResolveQuery as Q, ResolvedMeaning as M, Resolver, SymbolId, SymbolTable};
    use std::sync::Mutex;
    struct OuterField(Mutex<Vec<Q>>);
    impl Resolver for OuterField {
        fn resolve(&self, query: Q) -> M {
            self.0.lock().unwrap().push(query);
            match query {
                Q::HasMemberVar { .. } => M::Presence(true),
                Q::DeclaredVarType { .. } => M::DeclaredType(Some(SymbolId::of("/datum/outer"))),
                Q::RuntimeType(id) => M::Symbol(id),
                _ => M::Unsupported(query),
            }
        }
    }
    for formal in [false, true] {
        for contextual in [false, true] {
            let source = format!(
                "/datum/owner/proc/test({})\n{}    {}\n",
                if formal { "value" } else { "" },
                if formal { "" } else { "    var/value\n" },
                if contextual {
                    "value = new()"
                } else {
                    "return value.member"
                },
            );
            let ast = dm_syntax::parse(&source);
            assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
            let host = OuterField(Mutex::new(Vec::new()));
            let mut symbols = SymbolTable::default();
            symbols.intern("/datum/owner").unwrap();
            symbols.intern("/datum/outer").unwrap();
            let inputs = crate::lower_resolver::ProcedureInputs {
                current_type_path: Some("/datum/owner".into()),
                parameters: if formal { vec!["value".into()] } else { vec![] },
                ..Default::default()
            };
            let result =
                compile_simple_proc_with_resolver(&ast.items[0].children, &inputs, &symbols, &host);
            if contextual {
                let errors = result.err().expect("untyped new requires a type");
                assert!(
                    errors.iter().any(|error| error
                        .reason
                        .contains("inferred new requires a typed declaration")),
                    "{errors:?}"
                );
            } else {
                assert!(result.is_ok(), "{:?}", result.as_ref().err());
            }
            assert!(
                host.0.lock().unwrap().is_empty(),
                "outer queries for lexical binding"
            );
        }
    }
}

#[test]
fn bare_local_var_declaration_binds_its_name() {
    for source in [
        "/proc/test()\n    var amount = 3\n    return amount\n",
        "/proc/test()\n    var\tamount = 3\n    return amount\n",
    ] {
        let ast = dm_syntax::parse(source);
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
        assert_eq!(compiled.local_names, ["amount"]);
    }
}

#[test]
fn shared_bindings_resolve_names_without_serializing_project_maps() {
    let ast = dm_syntax::parse("/proc/test()\n    return project_value + project_proc()\n");
    let mut shared = SharedLowerBindings::default();
    shared.globals.insert("project_value".into());
    shared.global_variables.insert(
        "project_value".into(),
        reference(Table::Variable, "project_value"),
    );
    shared.global_procs.insert(
        "project_proc".into(),
        reference(Table::Proc, "/proc/project_proc"),
    );
    shared.fingerprint = "project-digest".into();
    let bindings = LowerBindings {
        shared: Some(Arc::new(shared)),
        ..LowerBindings::default()
    };
    let compiled = compile_fixture_proc_with_bindings(&ast.items[0].children, &bindings).unwrap();
    assert!(compiled.code.items.iter().any(|item| matches!(item,
        CodeItem::Instruction(instruction) if instruction.opcode == opcode::CALL_GLOB)));
    let serialized = serde_json::to_string(&bindings).unwrap();
    assert!(!serialized.contains("project_value"));
    assert!(!serialized.contains("project-digest"));
}
#[test]
fn const_formal_guards_binding_writes_without_freezing_payloads() {
    let bindings = LowerBindings {
        parameters: vec!["value".into()],
        readonly_parameters: [0].into(),
        current_type_path: Some("/datum/probe".into()),
        fields: ["value".into()].into(),
        ..LowerBindings::default()
    };
    for body in [
        "value = 3",
        "value += 3",
        "value++",
        "--value",
        "for(value in list(1))\n        return",
        "for(value = 1 to 3)\n        return",
    ] {
        let ast = dm_syntax::parse(&format!("/proc/test(value)\n    {body}\n"));
        let result = compile_fixture_proc_with_bindings(&ast.items[0].children, &bindings);
        let errors = result.expect_err("const binding mutation must fail");
        assert!(
            errors
                .iter()
                .any(|error| error.kind == LowerErrorKind::SourceError
                    && error.reason.contains("constant parameter")),
            "{errors:?}"
        );
    }
    for body in [
        "value[1] = 7",
        "src.value = 3",
        "return value",
        "var/other = 3\n    other = 4",
    ] {
        let ast = dm_syntax::parse(&format!("/proc/test(value)\n    {body}\n"));
        let result = compile_fixture_proc_with_bindings(&ast.items[0].children, &bindings);
        assert!(result.is_ok(), "{:?}", result.err());
    }
}

#[test]
fn shared_numeric_constants_respect_lexical_shadowing() {
    let ast = dm_syntax::parse(
        "/proc/constant()\n    return UNIX\n/proc/shadow(UNIX)\n    return UNIX\n",
    );
    let mut shared = SharedLowerBindings::default();
    shared
        .numeric_constants
        .insert("UNIX".into(), 3.0_f32.to_bits());
    let shared = Arc::new(shared);
    let constant = compile_fixture_proc_with_bindings(
        &ast.items[0].children,
        &LowerBindings {
            shared: Some(shared.clone()),
            ..LowerBindings::default()
        },
    )
    .unwrap();
    let shadow = compile_fixture_proc_with_bindings(
        &ast.items[1].children,
        &LowerBindings {
            parameters: vec!["UNIX".into()],
            shared: Some(shared),
            ..LowerBindings::default()
        },
    )
    .unwrap();
    let constant_words = link_proc(&constant.code, &Ledger::default()).unwrap().words;
    let shadow_words = link_proc(&shadow.code, &Ledger::default()).unwrap().words;
    assert_eq!(constant_words[0..2], [opcode::PUSH_INT, 3]);
    assert_eq!(shadow_words[0..3], [opcode::GET_VAR, 0xffd9, 0]);
}

#[test]
fn sorted_text_list_uses_typed_local_constructor() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/sortedtextlist/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let compiled = compile_simple_proc_with_params(
        &ast.items[0].children,
        &["incoming".into(), "case_sensitive".into()],
    );
    assert!(compiled.is_ok());
}

#[test]
fn compiler_context_constants_match_native() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/native_compiler/context_constants.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/native_compiler/context_constants.native.bin"
    ))
    .unwrap();
    for (id, path, owner) in [
        (0, "/proc/global_proc_name", None),
        (1, "/proc/global_type_name", None),
        (
            2,
            "/datum/context_probe/proc/member_proc_name",
            Some("/datum/context_probe"),
        ),
        (
            3,
            "/datum/context_probe/proc/member_type_name",
            Some("/datum/context_probe"),
        ),
    ] {
        let name = path.rsplit('/').next().unwrap();
        let item = ast
            .items
            .iter()
            .find(|item| item.header.contains(&format!("{name}(")))
            .unwrap();
        let bindings = LowerBindings {
            current_proc_path: Some(path.into()),
            current_type_path: owner.map(str::to_owned),
            ..LowerBindings::default()
        };
        let compiled = compile_fixture_proc_with_bindings(&item.children, &bindings).unwrap();
        let mut ledger = Ledger::default();
        if id == 0 || id == 2 {
            ledger.bind(reference(Table::Proc, path), id).unwrap();
        }
        if id == 3 {
            ledger
                .bind(reference(Table::Class, "/datum/context_probe"), 0)
                .unwrap();
        }
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        assert_eq!(
            linked.words,
            native.proc_code_words(id as usize).unwrap(),
            "proc {id}"
        );
    }
}

#[test]
fn typed_parameter_inferred_new_matches_native() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/return_inferred_new/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/return_inferred_new/probe.native.bin"
    ))
    .unwrap();
    for id in 0..2 {
        let bindings = LowerBindings {
            parameters: vec!["p".into()],
            parameter_types: HashMap::from([("p".into(), "/datum/point".into())]),
            parameter_defaults: vec![Some(if id == 0 { "new" } else { "new(1)" }.into())],
            ..LowerBindings::default()
        };
        let compiled =
            compile_fixture_proc_with_bindings(&ast.items[id].children, &bindings).unwrap();
        let mut ledger = Ledger::default();
        ledger
            .bind(reference(Table::Class, "/datum/point"), 0)
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
fn lexical_local_names_can_recur_in_distinct_branches_and_loops() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/reused_locals/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/reused_locals/probe.native.bin"
    ))
    .unwrap();
    for (index, item) in ast.items.iter().enumerate() {
        let params = if index == 0 {
            vec!["x".into()]
        } else {
            vec!["L".into()]
        };
        let compiled = compile_simple_proc_with_params(&item.children, &params).unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        assert_eq!(
            linked.words,
            native.proc_code_words(index).unwrap(),
            "proc {index}"
        );
    }
}

#[test]
fn typed_local_infers_constructor_path() {
    let ast = dm_syntax::parse(
        "/proc/create()\n    var/datum/expedition_building/B = new(3)\n    return B\n",
    );
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
    assert_eq!(
        compiled.class_paths,
        vec![SymbolId::of("/datum/expedition_building")]
    );
    let mut ledger = Ledger::default();
    ledger
        .bind(reference(Table::Class, "/datum/expedition_building"), 7)
        .unwrap();
    let linked = link_proc(&compiled.code, &ledger).unwrap();
    let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
    assert!(decoded
        .iter()
        .any(|instruction| instruction.opcode == opcode::NEW));
    let bare = dm_syntax::parse(
        "/proc/create()\n    var/datum/expedition_building/B = new\n    return B\n",
    );
    assert!(bare.diagnostics.is_empty(), "{:?}", bare.diagnostics);
    let bare_compiled = compile_simple_proc(&bare.items[0].children).unwrap();
    assert_eq!(
        bare_compiled.class_paths,
        vec![SymbolId::of("/datum/expedition_building")]
    );
    let reassigned = dm_syntax::parse(
        "/proc/create()\n    var/datum/expedition_building/B\n    B = new(3)\n    return B\n",
    );
    let reassigned_compiled = compile_simple_proc(&reassigned.items[0].children).unwrap();
    assert_eq!(
        reassigned_compiled.class_paths,
        vec![SymbolId::of("/datum/expedition_building")]
    );
}

#[test]
fn typed_local_declarations_bind_leaf_names() {
    let ast = dm_syntax::parse(
        "/proc/locals()\n  var/list/items = list(1)\n  var/obj/item/tool = null\n  return items\n",
    );
    let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
    assert_eq!(compiled.local_names, ["items", "tool"]);
    link_proc(&compiled.code, &Ledger::default()).unwrap();
}

#[test]
fn catch_without_binding_matches_native_fixture() {
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/try_empty.native.bin"
    ))
    .unwrap();
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/try_empty.dm"
    ));
    let compiled =
        compile_simple_proc_with_params(&ast.items[0].children, &["value".into()]).unwrap();
    let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
    let id = native
        .procs
        .iter()
        .position(|proc| native.string(proc.strings[0]) == Some(b"/proc/try_empty".as_slice()))
        .unwrap();
    assert_eq!(linked.words, native.proc_code_words(id).unwrap());
}

#[test]
fn literal_parameter_defaults_match_native_prologue() {
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/argument_defaults.native.bin"
    ))
    .unwrap();
    let proc_id = native
        .procs
        .iter()
        .position(|proc| {
            native.string(proc.strings[0]) == Some(b"/proc/default_arg_probe".as_slice())
        })
        .unwrap();
    let class_id = native
        .classes
        .iter()
        .position(|class| native.string(class.path_string_id()) == Some(b"/obj".as_slice()))
        .unwrap();
    let string_id = native
        .strings
        .iter()
        .position(|string| string.data == b"hi")
        .unwrap();
    let ast = dm_syntax::parse("/proc/test(a,b,c,d)\n  return a\n");
    let bindings = LowerBindings {
        parameters: vec!["a".into(), "b".into(), "c".into(), "d".into()],
        parameter_defaults: vec![
            Some("5".into()),
            Some("\"hi\"".into()),
            Some("list(1, 2)".into()),
            Some("/obj".into()),
        ],
        ..LowerBindings::default()
    };
    let compiled = compile_fixture_proc_with_bindings(&ast.items[0].children, &bindings).unwrap();
    let mut ledger = Ledger::default();
    ledger
        .bind(reference(Table::String, "hi"), string_id as u32)
        .unwrap();
    ledger
        .bind(reference(Table::Class, "/obj"), class_id as u32)
        .unwrap();
    let linked = link_proc(&compiled.code, &ledger).unwrap();
    assert_eq!(linked.words, native.proc_code_words(proc_id).unwrap());
}

#[test]
fn numeric_range_binding_matches_native_iteration_state() {
    let source = "/proc/test(low, high)\n    var/i = 99\n    for(i in low to high)\n        i += 10\n    return i\n";
    let ast = dm_syntax::parse(source);
    let compiled =
        compile_simple_proc_with_params(&ast.items[0].children, &["low".into(), "high".into()])
            .unwrap();
    let words = link_proc(&compiled.code, &Ledger::default()).unwrap().words;
    assert_eq!(
        words,
        [
            0x50, 99, 0x34, 0xffda, 0, 0x33, 0xffd9, 0, 0x33, 0xffd9, 1, 0xfc, 0xfd, 23, 0xffda, 0,
            0x50, 10, 0x45, 0xffda, 0, 0xf8, 12, 0xfb, 2, 0x33, 0xffda, 0, 0x12, 0
        ]
    );
}

#[test]
fn implied_type_constructor_uses_target_type_and_preserves_local_shadow() {
    let compile = |body: &str| {
        let ast = dm_syntax::parse(&format!("/proc/probe()\n{body}"));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        compile_fixture_proc_with_bindings(&ast.items[0].children, &LowerBindings::default())
            .unwrap()
    };
    let bare = compile("    var/datum/point/value = new(1)\n    return value\n");
    let implied =
        compile("    var/datum/point/value = new __IMPLIED_TYPE__(1)\n    return value\n");
    assert_eq!(bare.code, implied.code);
    let explicit = compile("    var/__IMPLIED_TYPE__ = /datum/point\n    var/datum/other/value = new __IMPLIED_TYPE__\n    return value\n");
    let renamed = compile(
        "    var/chosen = /datum/point\n    var/datum/other/value = new chosen\n    return value\n",
    );
    assert_eq!(explicit.code, renamed.code);
}

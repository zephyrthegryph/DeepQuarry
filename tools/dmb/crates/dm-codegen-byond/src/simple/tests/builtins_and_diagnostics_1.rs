//! Builtins and diagnostics lowering regression tests.
use super::*;

#[test]
fn lower_error_old_serialization_defaults_to_unsupported_without_span() {
    let error: super::LowerError =
        serde_json::from_str(r#"{"statement":"return x","reason":"unknown meaning"}"#).unwrap();
    assert_eq!(error.kind, super::LowerErrorKind::UnsupportedModel);
    assert_eq!(error.span, None);
    let encoded = serde_json::to_string(&error).unwrap();
    assert!(!encoded.contains("span"));
}
#[test]
fn rand_two_arguments_uses_native_builtin_opcode() {
    let ast = dm_syntax::parse("/proc/test()\n    return rand(1, 2) == null\n");
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
        .position(|proc| {
            native.string(proc.strings[0]) == Some(b"/proc/global_equal_null".as_slice())
        })
        .unwrap();
    let theirs = byond_dmb::bytecode::decode(native.proc_code_words(id).unwrap()).unwrap();
    assert_eq!(ours[2].opcode, 0x23);
    assert!(
        theirs.iter().any(|instruction| instruction.opcode == 0x23),
        "{theirs:?}"
    );
}

#[test]
fn ceil_matches_native_builtin_fixture() {
    let ast = dm_syntax::parse("/proc/b_ceiling(x)\n    return ceil(x)\n");
    let compiled = compile_simple_proc_with_params(&ast.items[0].children, &["x".into()]).unwrap();
    let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/builtin_next.native.bin"
    ))
    .unwrap();
    let id = native
        .procs
        .iter()
        .position(|proc| native.string(proc.strings[0]) == Some(b"/proc/b_ceiling".as_slice()))
        .unwrap();
    assert_eq!(linked.words, native.proc_code_words(id).unwrap());
}

#[test]
fn clamp_emits_builtin_after_three_values() {
    let ast = dm_syntax::parse("/proc/test(x)\n    return clamp(x, 0, 100)\n");
    let compiled = compile_simple_proc_with_params(&ast.items[0].children, &["x".into()]).unwrap();
    let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
    let code = byond_dmb::bytecode::decode(&linked.words).unwrap();
    assert_eq!(code[3].opcode, 0x14a);
}

#[test]
fn min_max_match_native_single_and_pair_fixtures() {
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/min_max_single/min_max_single.native.bin"
    ))
    .unwrap();
    for (name, params, body) in [
        ("min_single", vec!["value"], "return min(value)"),
        ("max_single", vec!["value"], "return max(value)"),
        ("min_pair", vec!["a", "b"], "return min(a,b)"),
        ("max_pair", vec!["a", "b"], "return max(a,b)"),
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
}

#[test]
fn floor_matches_native_builtin_fixture() {
    let ast = dm_syntax::parse("/proc/b_floor(x)\n    return floor(x)\n");
    let compiled = compile_simple_proc_with_params(&ast.items[0].children, &["x".into()]).unwrap();
    let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/builtin_next.native.bin"
    ))
    .unwrap();
    let id = native
        .procs
        .iter()
        .position(|proc| native.string(proc.strings[0]) == Some(b"/proc/b_floor".as_slice()))
        .unwrap();
    assert_eq!(linked.words, native.proc_code_words(id).unwrap());
}

#[test]
fn length_matches_native_fixture() {
    let ast = dm_syntax::parse("/proc/literal_length()\n    return length(\"Ａ２～\")\n");
    let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/literal_format_unicode/probe.native.bin"
    ))
    .unwrap();
    let string_id = native
        .strings
        .iter()
        .position(|string| string.data == "Ａ２～".as_bytes())
        .unwrap();
    let mut ledger = Ledger::default();
    ledger
        .bind(
            crate::Symbol::new(Table::String, "Ａ２～"),
            string_id as u32,
        )
        .unwrap();
    let linked = link_proc(&compiled.code, &ledger).unwrap();
    let id = native
        .procs
        .iter()
        .position(|proc| native.string(proc.strings[0]) == Some(b"/proc/literal_length".as_slice()))
        .unwrap();
    assert_eq!(linked.words, native.proc_code_words(id).unwrap());
}

#[test]
fn copytext_three_arguments_matches_native_fixture() {
    let ast = dm_syntax::parse("/proc/literal_copytext()\n    return copytext(\"Ａ２～\", 1, 4)\n");
    let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/literal_format_unicode/probe.native.bin"
    ))
    .unwrap();
    let string_id = native
        .strings
        .iter()
        .position(|string| string.data == "Ａ２～".as_bytes())
        .unwrap();
    let mut ledger = Ledger::default();
    ledger
        .bind(
            crate::Symbol::new(Table::String, "Ａ２～"),
            string_id as u32,
        )
        .unwrap();
    let linked = link_proc(&compiled.code, &ledger).unwrap();
    let id = native
        .procs
        .iter()
        .position(|proc| {
            native.string(proc.strings[0]) == Some(b"/proc/literal_copytext".as_slice())
        })
        .unwrap();
    assert_eq!(linked.words, native.proc_code_words(id).unwrap());
}

#[test]
fn copytext_two_arguments_pads_native_null_end() {
    let ast = dm_syntax::parse("/proc/test(x)\n    return copytext(x, 2)\n");
    let compiled = compile_simple_proc_with_params(&ast.items[0].children, &["x".into()]).unwrap();
    let code =
        byond_dmb::bytecode::decode(&link_proc(&compiled.code, &Ledger::default()).unwrap().words)
            .unwrap();
    assert_eq!(code[2].opcode, opcode::PUSH_VAL);
    assert_eq!(code[2].operands, vec![0, 0]);
    assert_eq!(code[3].opcode, 0x6e);
}

#[test]
fn text2num_uses_native_builtin_opcode() {
    let ast = dm_syntax::parse("/proc/test(x)\n    return text2num(x)\n");
    let compiled = compile_simple_proc_with_params(&ast.items[0].children, &["x".into()]).unwrap();
    let ours =
        byond_dmb::bytecode::decode(&link_proc(&compiled.code, &Ledger::default()).unwrap().words)
            .unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/cable_numeric_parse/probe.native.bin"
    ))
    .unwrap();
    let id = native
        .procs
        .iter()
        .position(|proc| {
            native.string(proc.strings[0]) == Some(b"/obj/cable/proc/parse".as_slice())
        })
        .unwrap();
    let theirs = byond_dmb::bytecode::decode(native.proc_code_words(id).unwrap()).unwrap();
    assert_eq!(ours[1].opcode, 0x76);
    assert!(theirs.iter().any(|instruction| instruction.opcode == 0x76));
}

#[test]
fn findtext_two_arguments_uses_native_defaults() {
    let ast = dm_syntax::parse("/proc/test(x)\n    return findtext(x, \"-\")\n");
    let compiled = compile_simple_proc_with_params(&ast.items[0].children, &["x".into()]).unwrap();
    let mut ledger = Ledger::default();
    ledger
        .bind(crate::Symbol::new(Table::String, "-"), 1)
        .unwrap();
    let ours =
        byond_dmb::bytecode::decode(&link_proc(&compiled.code, &ledger).unwrap().words).unwrap();
    assert_eq!(ours[2].opcode, opcode::PUSH_INT);
    assert_eq!(ours[2].operands, vec![1]);
    assert_eq!(ours[3].opcode, opcode::PUSH_VAL);
    assert_eq!(ours[3].operands, vec![0, 0]);
    assert_eq!(ours[4].opcode, 0x6f);
}

#[test]
fn del_world_matches_native_fixture() {
    let ast =
        dm_syntax::parse("/obj/proc/delete_intrinsic_world()\n    del(world)\n    return 7\n");
    let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
    let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/delete_readonly_intrinsics/probe.native.bin"
    ))
    .unwrap();
    let id = native
        .procs
        .iter()
        .position(|proc| {
            native.string(proc.strings[0]) == Some(b"/obj/proc/delete_intrinsic_world".as_slice())
        })
        .unwrap();
    assert_eq!(linked.words, native.proc_code_words(id).unwrap());
}

#[test]
fn world_log_output_matches_native_instruction_sequence() {
    let ast = dm_syntax::parse("/world/New()\n    world.log << \"MAPPED cable\"\n");
    let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/cable_numeric_parse/probe.native.bin"
    ))
    .unwrap();
    let mut ledger = Ledger::default();
    let log_id = native
        .strings
        .iter()
        .position(|string| string.data == b"log")
        .unwrap();
    let message_id = native
        .strings
        .iter()
        .position(|string| string.data == b"MAPPED cable")
        .unwrap();
    ledger
        .bind(crate::Symbol::new(Table::String, "log"), log_id as u32)
        .unwrap();
    ledger
        .bind(
            crate::Symbol::new(Table::String, "MAPPED cable"),
            message_id as u32,
        )
        .unwrap();
    let linked = link_proc(&compiled.code, &ledger).unwrap();
    let id = native
        .procs
        .iter()
        .position(|proc| native.string(proc.strings[0]) == Some(b"/world/New".as_slice()))
        .unwrap();
    assert_eq!(
        &linked.words[..8],
        &native.proc_code_words(id).unwrap()[27..35]
    );
}

#[test]
fn round_to_multiple_uses_native_opcode() {
    let ast = dm_syntax::parse("/proc/test(x)\n    return round(x, 0.001)\n");
    let compiled = compile_simple_proc_with_params(&ast.items[0].children, &["x".into()]).unwrap();
    let mut ledger = Ledger::default();
    for value in &compiled.strings {
        ledger
            .bind(crate::Symbol::new(Table::String, value), 1)
            .unwrap();
    }
    let ours =
        byond_dmb::bytecode::decode(&link_proc(&compiled.code, &ledger).unwrap().words).unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/indexed_conditional.native.bin"
    ))
    .unwrap();
    let id = native
        .procs
        .iter()
        .position(|proc| native.string(proc.strings[0]) == Some(b"/proc/ic_round".as_slice()))
        .unwrap();
    let theirs = byond_dmb::bytecode::decode(native.proc_code_words(id).unwrap()).unwrap();
    assert!(ours.iter().any(|instruction| instruction.opcode == 0x44));
    assert!(theirs.iter().any(|instruction| instruction.opcode == 0x44));
}

#[test]
fn invalid_builtin_argument_count_fails_closed() {
    {
        let source = "/proc/test()\n    return alert()\n";
        let expected = "alert() requires one to six arguments";
        let ast = dm_syntax::parse(source);
        let errors = compile_simple_proc(&ast.items[0].children).unwrap_err();
        assert!(errors[0].reason.contains(expected), "{errors:?}");
    }
}

#[test]
fn safe_navigation_uses_native_cache_guards() {
    let ast = dm_syntax::parse(
        "/proc/test(a, key)\n    return a?[key.value]\n/proc/member(a)\n    return a?.value\n/proc/safe_call(a, b)\n    return a?.f(b)\n",
    );
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    for (item, params, expected) in [
        (
            &ast.items[0],
            vec!["a".into(), "key".into()],
            vec![
                opcode::GET_VAR,
                317,
                opcode::PUSH_CACHE,
                opcode::GET_VAR,
                opcode::GET_VAR,
                opcode::LIST_GET,
                opcode::POP_CACHE,
            ],
        ),
        (
            &ast.items[1],
            vec!["a".into()],
            vec![opcode::GET_VAR, 317, opcode::GET_VAR],
        ),
        (
            &ast.items[2],
            vec!["a".into(), "b".into()],
            vec![
                opcode::GET_VAR,
                317,
                opcode::PUSH_CACHE,
                opcode::GET_VAR,
                opcode::POP_CACHE,
                opcode::CALL,
            ],
        ),
    ] {
        let compiled = compile_simple_proc_with_params(&item.children, &params).unwrap();
        let mut ledger = Ledger::default();
        ledger
            .assign(Table::String, compiled.strings.clone())
            .unwrap();
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
        let opcodes: Vec<_> = decoded
            .iter()
            .map(|instruction| instruction.opcode)
            .collect();
        assert_eq!(&opcodes[..expected.len()], expected);
        let guard = &decoded[1];
        assert_eq!(
            guard.branch_targets().unwrap(),
            vec![decoded[expected.len()].offset as u32]
        );
    }
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/safe_index.native.bin"
    ))
    .unwrap();
    for path in [
        b"/proc/safe_computed_index".as_slice(),
        b"/proc/safe_nested_index",
    ] {
        let id = native
            .procs
            .iter()
            .position(|proc| native.string(proc.strings[0]) == Some(path))
            .unwrap();
        let decoded = byond_dmb::bytecode::decode(native.proc_code_words(id).unwrap()).unwrap();
        assert_eq!(decoded[1].opcode, 317);
        assert_eq!(decoded[2].opcode, opcode::PUSH_CACHE);
    }
}

#[test]
fn alternate_builtin_arities_match_native_bodies() {
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/native_compiler/builtin_catalog.native.bin"
    ))
    .unwrap();
    for (name, expression, parameters) in [
        ("arctan2", "arctan(a,b)", vec!["a", "b"]),
        ("log2", "log(a,b)", vec!["a", "b"]),
        ("num2text2", "num2text(a,b)", vec!["a", "b"]),
        ("num2text3", "num2text(a,b,c)", vec!["a", "b", "c"]),
        ("ispath2", "ispath(a,b)", vec!["a", "b"]),
        ("locate3", "locate(a,b,c)", vec!["a", "b", "c"]),
        ("time2text3", "time2text(a,b,c)", vec!["a", "b", "c"]),
        ("rgb4", "rgb(a,b,c,d)", vec!["a", "b", "c", "d"]),
    ] {
        let path = format!("/proc/catalog_{name}");
        let source = format!(
            "{path}({})\n    return {expression}\n",
            parameters.join(",")
        );
        let ast = dm_syntax::parse(&source);
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let params: Vec<String> = parameters.iter().map(|name| (*name).into()).collect();
        let compiled = compile_simple_proc_with_params(&ast.items[0].children, &params).unwrap();
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
fn sized_local_arrays_match_native_bodies() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/local_array/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/local_array/probe.native.bin"
    ))
    .unwrap();
    for (item, params, path) in [
        (&ast.items[0], vec![], "/proc/test"),
        (&ast.items[1], vec!["n".into()], "/proc/test2"),
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
fn multidimensional_local_array_matches_native_body() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/local_array_multi/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let compiled =
        compile_simple_proc_with_params(&ast.items[0].children, &["a".into(), "b".into()]).unwrap();
    let mut ledger = Ledger::default();
    ledger
        .assign(Table::Class, compiled.class_paths.clone())
        .unwrap();
    let linked = link_proc(&compiled.code, &ledger).unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/local_array_multi/probe.native.bin"
    ))
    .unwrap();
    let id = native
        .procs
        .iter()
        .position(|proc| native.string(proc.strings[0]) == Some(b"/proc/test".as_slice()))
        .unwrap();
    assert_eq!(linked.words, native.proc_code_words(id).unwrap());
}

#[test]
fn infinity_literals_match_native_value_words() {
    for (literal, bits) in [
        ("1.#INF", f32::INFINITY.to_bits()),
        ("-1.#INF", f32::NEG_INFINITY.to_bits()),
    ] {
        let ast = dm_syntax::parse(&format!("/proc/test()\n    return {literal}\n"));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        assert_eq!(linked.words, [0x60, 42, bits >> 16, bits & 0xffff, 0x12, 0]);
    }
}

#[test]
fn input_type_filters_and_choices_emit_native_prompt_operands() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/input_default/input_default.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/input_default/input_default.native.bin"
    ))
    .unwrap();
    for (index, path, mask, has_choices) in [
        (0, "/proc/implicit_prompt", 0, false),
        (1, "/proc/text_prompt", 4, false),
        (2, "/proc/implicit_choice", 0, true),
        (3, "/proc/anything_choice", 4096, true),
        (4, "/proc/implicit_short", 0, false),
        (5, "/proc/text_short", 4, false),
    ] {
        let params = if has_choices {
            vec!["choices".into()]
        } else {
            vec![]
        };
        let compiled =
            compile_simple_proc_with_params(&ast.items[index].children, &params).unwrap();
        let mut ledger = Ledger::default();
        ledger
            .assign(Table::String, compiled.strings.clone())
            .unwrap();
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        let ours = byond_dmb::bytecode::decode(&linked.words).unwrap();
        let id = native
            .procs
            .iter()
            .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
            .unwrap();
        let expected = byond_dmb::bytecode::decode(native.proc_code_words(id).unwrap()).unwrap();
        let input = ours
            .iter()
            .find(|instruction| instruction.opcode == 0xc1)
            .unwrap();
        let native_input = expected
            .iter()
            .find(|instruction| instruction.opcode == 0xc1)
            .unwrap();
        assert_eq!(input.operands, native_input.operands, "{path}");
        assert_eq!(input.operands, [mask, 0, if has_choices { 64 } else { 0 }]);
        assert!(ours.iter().any(|instruction| instruction.opcode == 0xba));
    }
}

#[test]
fn color_input_uses_native_prompt_configuration() {
    let ast = dm_syntax::parse("/proc/test()\n    return input() as color\n");
    let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
    let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
    let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
    assert_eq!(decoded[0].operands, [42, 18432, 0]);
    assert!(decoded
        .iter()
        .any(|instruction| instruction.opcode == 0xc6 && instruction.operands == [0, 0, 0]));
    assert!(decoded.iter().any(|instruction| instruction.opcode == 0xba));
}

#[test]
fn raw_single_quote_text_matches_native() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/raw_single_quote/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/raw_single_quote/probe.native.bin"
    ))
    .unwrap();
    assert_eq!(native.string(437), Some(b"a\\n[b]".as_slice()));
    let mut ledger = Ledger::default();
    ledger
        .bind(crate::Symbol::new(Table::String, "a\\n[b]"), 437)
        .unwrap();
    let linked = link_proc(&compiled.code, &ledger).unwrap();
    assert_eq!(linked.words, native.proc_code_words(0).unwrap());
}

#[test]
fn escaped_apostrophe_and_angle_match_native() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/string_escapes/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/string_escapes/probe.native.bin"
    ))
    .unwrap();
    for (id, item) in ast.items.iter().enumerate() {
        let compiled = compile_simple_proc(&item.children).unwrap();
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
fn generator_builtin_matches_native() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/native_compiler/generator_alist.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/native_compiler/generator_alist.native.bin"
    ))
    .unwrap();
    for id in 0..4 {
        let params = if id == 1 {
            vec!["a", "b", "c"]
        } else {
            vec!["a", "b"]
        }
        .into_iter()
        .map(str::to_owned)
        .collect::<Vec<_>>();
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
fn builtin_type_tags_match_native() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/builtin_type_tags/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/builtin_type_tags/probe.native.bin"
    ))
    .unwrap();
    for (id, item) in ast.items.iter().enumerate() {
        let compiled = compile_simple_proc(&item.children).unwrap();
        let mut ledger = Ledger::default();
        let (path, class_id) = if id < 2 {
            ("/mutable_appearance", 6)
        } else {
            ("/particles", 23)
        };
        ledger
            .bind(crate::Symbol::new(Table::Class, path), class_id)
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
fn pair_iteration_matches_native() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/native_compiler/for_pair.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/native_compiler/for_pair.native.bin"
    ))
    .unwrap();
    for (id, item) in ast.items.iter().enumerate() {
        let compiled = compile_simple_proc_with_params(&item.children, &["L".into()]).unwrap();
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
fn json_encode_flags_matches_native() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/json_encode_flags/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/json_encode_flags/probe.native.bin"
    ))
    .unwrap();
    let compiled =
        compile_simple_proc_with_params(&ast.items[0].children, &["value".into(), "flags".into()])
            .unwrap();
    let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
    assert_eq!(linked.words, native.proc_code_words(0).unwrap());
}

#[test]
fn alert_and_issaved_match_native() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/native_compiler/alert_issaved.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/native_compiler/alert_issaved.native.bin"
    ))
    .unwrap();
    for id in [0usize, 1, 2, 3, 5, 6] {
        let item = ast
            .items
            .iter()
            .find(|item| {
                item.header.contains(match id {
                    0 => "alert_one(",
                    1 => "alert_two(",
                    2 => "alert_four(",
                    3 => "alert_six(",
                    5 => "issaved_member(",
                    _ => "issaved_index(",
                })
            })
            .unwrap();
        let param = if id < 5 { "M" } else { "D" };
        let compiled = compile_simple_proc_with_params(&item.children, &[param.into()]).unwrap();
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
fn exception_type_matches_native() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/exception_type/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/exception_type/probe.native.bin"
    ))
    .unwrap();
    for id in 0..2 {
        let bindings = LowerBindings {
            parameters: if id == 0 { vec!["E".into()] } else { vec![] },
            parameter_types: if id == 0 {
                HashMap::from([("E".into(), "/exception".into())])
            } else {
                HashMap::new()
            },
            ..LowerBindings::default()
        };
        let compiled =
            compile_simple_proc_with_bindings(&ast.items[id].children, &bindings).unwrap();
        let mut ledger = Ledger::default();
        ledger
            .bind(crate::Symbol::new(Table::Class, "/exception"), 19)
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
fn inc_length_matches_native() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/inc_length/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/inc_length/probe.native.bin"
    ))
    .unwrap();
    for id in 0..2 {
        let compiled =
            compile_simple_proc_with_params(&ast.items[id].children, &["L".into()]).unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        assert_eq!(
            linked.words,
            native.proc_code_words(id).unwrap(),
            "proc {id}"
        );
    }
}

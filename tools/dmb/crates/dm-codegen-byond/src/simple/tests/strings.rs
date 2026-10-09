//! Strings lowering regression tests.
use super::*;

#[test]
fn procedure_and_verb_namespaces_are_native_strings() {
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/native_compiler/proc_namespace.native.bin"
    ))
    .unwrap();
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/native_compiler/proc_namespace.dm"
    ));
    for (name, namespace) in [
        ("proc_group", "proc"),
        ("verb_group", "verb"),
        ("proc_types", "proc"),
        ("verb_types", "verb"),
    ] {
        let item = ast
            .items
            .iter()
            .find(|item| item.header == format!("/proc/{name}()"))
            .unwrap();
        let compiled = compile_simple_proc(&item.children).unwrap();
        assert!(compiled.class_paths.is_empty());
        let path = format!("/datum/namespace_probe/{namespace}");
        let string = native
            .strings
            .iter()
            .position(|entry| entry.data == path.as_bytes())
            .unwrap();
        let mut ledger = Ledger::default();
        ledger
            .bind(reference(Table::String, path), string as u32)
            .unwrap();
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
fn raw_unicode_string_matches_native_fixture() {
    let ast = dm_syntax::parse("/proc/literal_raw()\n    return @\"Ａ２～\"\n");
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/literal_format_unicode/probe.native.bin"
    ))
    .unwrap();
    let mut ledger = Ledger::default();
    let string_id = native
        .strings
        .iter()
        .position(|string| string.data == "Ａ２～".as_bytes())
        .unwrap();
    ledger
        .bind(reference(Table::String, "Ａ２～"), string_id as u32)
        .unwrap();
    let linked = link_proc(&compiled.code, &ledger).unwrap();
    let id = native
        .procs
        .iter()
        .position(|proc| native.string(proc.strings[0]) == Some(b"/proc/literal_raw".as_slice()))
        .unwrap();
    assert_eq!(linked.words, native.proc_code_words(id).unwrap());
}

#[test]
fn shared_string_constants_respect_lexical_shadowing() {
    let ast = dm_syntax::parse(
        "/proc/constant()\n    return UNIX\n/proc/shadow(UNIX)\n    return UNIX\n",
    );
    let mut shared = SharedLowerBindings::default();
    shared.string_constants.insert("UNIX".into(), "UNIX".into());
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
    let mut ledger = Ledger::default();
    ledger.bind(reference(Table::String, "UNIX"), 7).unwrap();
    let constant_words = link_proc(&constant.code, &ledger).unwrap().words;
    let shadow_words = link_proc(&shadow.code, &ledger).unwrap().words;
    assert_eq!(constant_words[0..3], [opcode::PUSH_VAL, 6, 7]);
    assert_eq!(shadow_words[0..3], [opcode::GET_VAR, 0xffd9, 0]);
}

#[test]
fn nameof_proc_reference_folds_to_native_leaf_string() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/nameof/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/nameof/probe.native.bin"
    ))
    .unwrap();
    for (proc, path) in [
        (&ast.items[1], "/datum/x/proc/get"),
        (&ast.items[2], "/datum/x/proc/get2"),
    ] {
        let compiled = compile_simple_proc(&proc.children).unwrap();
        assert!(string_texts(&compiled).contains(&"foo".into()));
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
        let id = native
            .procs
            .iter()
            .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
            .unwrap();
        let native_code = byond_dmb::bytecode::decode(native.proc_code_words(id).unwrap()).unwrap();
        let native_id = native_code[0].operands[1];
        assert_eq!(native.string(native_id), Some(b"foo".as_slice()));
        assert_eq!(linked.words[0], native.proc_code_words(id).unwrap()[0]);
    }
}

#[test]
fn text_placeholder_templates_match_native() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/text_template/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/text_template/probe.native.bin"
    ))
    .unwrap();
    for (id, item) in ast.items.iter().enumerate() {
        let params = match id {
            0 => vec!["a", "b", "c"],
            1 => vec!["a", "b"],
            2 => vec![],
            3 => vec!["a"],
            _ => vec!["a", "b"],
        }
        .into_iter()
        .map(str::to_owned)
        .collect::<Vec<_>>();
        let compiled = compile_simple_proc_with_params(&item.children, &params).unwrap();
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
fn text_template_and_literal_share_utf8_string_key() {
    let ast = dm_syntax::parse("/proc/test()\n    return list(\"same\", text(\"same\"))\n");
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
    assert_eq!(
        compiled
            .strings
            .iter()
            .filter(|key| compiled.string_bytes(key.id).unwrap() == b"same")
            .count(),
        1
    );
    let mut ledger = Ledger::default();
    ledger.bind(reference(Table::String, "same"), 0).unwrap();
    link_proc(&compiled.code, &ledger).unwrap();
}

#[test]
fn escaped_strings_match_native() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/native_compiler/string_escapes.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/native_compiler/string_escapes.native.bin"
    ))
    .unwrap();
    for id in 0..7 {
        let compiled = compile_simple_proc(&ast.items[id].children).unwrap();
        let mut ledger = Ledger::default();
        for key in &compiled.strings {
            let string_id = native
                .strings
                .iter()
                .position(|entry| entry.data == compiled.string_bytes(key.id).unwrap())
                .unwrap_or_else(|| panic!("native string missing: {key:?}"));
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
fn hex_and_block_string_literals_match_native_bytecode() {
    let hex = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/raw_hex_literals/hex.dm"
    ));
    assert!(hex.diagnostics.is_empty(), "{:?}", hex.diagnostics);
    let native_hex = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/raw_hex_literals/hex.native.bin"
    ))
    .unwrap();
    for (index, item) in hex.items.iter().enumerate() {
        let compiled = compile_simple_proc(&item.children).unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        assert_eq!(linked.words, native_hex.proc_code_words(index).unwrap());
    }

    let raw = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/raw_hex_literals/raw.dm"
    ));
    assert!(raw.diagnostics.is_empty(), "{:?}", raw.diagnostics);
    let native_raw = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/raw_hex_literals/raw.native.bin"
    ))
    .unwrap();
    for (index, item) in raw.items.iter().enumerate() {
        let compiled = compile_simple_proc(&item.children).unwrap();
        let mut ledger = Ledger::default();
        for key in &compiled.strings {
            let id = native_raw
                .strings
                .iter()
                .position(|entry| entry.data == compiled.string_bytes(key.id).unwrap())
                .unwrap_or_else(|| panic!("native string missing: {key:?}"));
            ledger
                .bind(reference(Table::String, key), id as u32)
                .unwrap();
        }
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        assert_eq!(linked.words, native_raw.proc_code_words(index).unwrap());
    }
}

#[test]
fn lone_closing_bracket_is_literal_string_content() {
    let (bytes, interpolations) = parse_interpolated_string("] and \\] and \\[").unwrap();
    assert_eq!(bytes, b"] and ] and [");
    assert!(interpolations.is_empty());
}

#[test]
fn closing_bracket_strings_match_native_bytecode() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/native_compiler/string_bracket_semantics.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/native_compiler/string_bracket_semantics.native.bin"
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
    assert_eq!(linked.words, native.proc_code_words(0).unwrap());
}

#[test]
fn local_assignment_and_string_reference_link() {
    let ast = dm_syntax::parse("/proc/test()\n  var/x = \"hello\"\n  x = 3\n  return x\n");
    let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
    assert_eq!(string_texts(&compiled), ["hello"]);
    assert_eq!(compiled.local_count, 1);
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
    assert!(linked
        .relocations
        .iter()
        .any(|(_, symbol)| *symbol == SymRef::String(SymbolId::of("hello"))));
    assert!(byond_dmb::bytecode::decode(&linked.words).is_ok());
}

#[test]
fn simple_interpolation_matches_native_fixture() {
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/format_context.native.bin"
    ))
    .unwrap();
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/format_context.dm"
    ));
    for name in [
        "format_context_00",
        "format_context_03",
        "format_context_57",
        "format_context_58",
        "format_context_59",
        "format_context_128",
        "format_context_129",
    ] {
        let item = ast
            .items
            .iter()
            .find(|item| item.header.starts_with(&format!("/proc/{name}(")))
            .unwrap();
        let compiled = compile_simple_proc_with_params(&item.children, &["X".into()]).unwrap();
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
            .position(|proc| {
                native
                    .string(proc.strings[0])
                    .is_some_and(|path| path.ends_with(name.as_bytes()))
            })
            .unwrap();
        assert_eq!(linked.words, native.proc_code_words(id).unwrap(), "{name}");
    }
}

#[test]
fn multiple_interpolations_keep_order_and_template_bytes() {
    let ast = dm_syntax::parse("/proc/text(x,y)\n  return \"A [x] B [y]\"\n");
    let compiled =
        compile_simple_proc_with_params(&ast.items[0].children, &["x".into(), "y".into()]).unwrap();
    let key = compiled
        .strings
        .iter()
        .find(|key| std::str::from_utf8(&key.bytes).is_err())
        .unwrap();
    assert_eq!(
        compiled.string_bytes(key.id).unwrap(),
        b"A \xff\x01 B \xff\x01"
    );
    let mut ledger = Ledger::default();
    ledger.bind(reference(Table::String, key), 5).unwrap();
    let linked = link_proc(&compiled.code, &ledger).unwrap();
    let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
    assert!(decoded
        .iter()
        .any(|ins| ins.opcode == 2 && ins.operands == [5, 2]));
}

#[test]
fn control_only_string_preserves_binary_marker() {
    let ast = dm_syntax::parse("/proc/test()\n  return \"\\proper K10\"\n");
    let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
    let key = compiled.strings.first().unwrap();
    assert_eq!(compiled.string_bytes(key.id).unwrap(), b"\xff\x15K10");
}

#[test]
fn binary_templates_are_interned_by_exact_bytes_once() {
    let ast = dm_syntax::parse("/proc/test(x)\n    var/a = \"A [x]\"\n    return \"A [x]\"\n");
    let compiled = compile_simple_proc_with_params(&ast.items[0].children, &["x".into()]).unwrap();
    let template = b"A \xff\x01";
    let payloads = compiled
        .strings
        .iter()
        .filter(|payload| payload.bytes.as_ref() == template)
        .collect::<Vec<_>>();
    assert_eq!(payloads.len(), 1);
    assert_eq!(payloads[0].id, SymbolId::of_bytes(template));
}

#[test]
fn continued_interpolation_expressions_keep_literal_decoder_authority() {
    for value in [
        "[pick(\"first\",\\\n    \"second\")].",
        "[isRepeating ? \\\r\n    \"repeat\" : \"deleted\"]",
        "[pick(\"left\\\n    right\",\\\n    \"second\")]",
    ] {
        let (_, expressions) = parse_interpolated_string(value).unwrap();
        assert_eq!(expressions.len(), 1);
    }
}

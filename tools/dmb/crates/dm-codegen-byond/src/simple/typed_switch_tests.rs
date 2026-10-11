use super::*;
use crate::{link_proc, Ledger};

#[test]
fn constant_string_and_null_tables_preserve_executable_debug_sources() {
    struct Debug;
    impl DebugSourceProvider for Debug {
        fn entry_ordinal(&self) -> Result<u32, String> {
            Ok(0)
        }
        fn ordinal(&self, offset: usize) -> Result<u32, String> {
            u32::try_from(offset).map_err(|error| error.to_string())
        }
    }
    let parsed = dm_syntax::parse(
        "/proc/probe(value)\n  switch(value)\n    if(\"text\")\n      return 1\n    if(null)\n      return 2\n    else\n      return 3\n",
    );
    let bindings = LowerBindings {
        parameters: vec!["value".into()],
        ..Default::default()
    };
    let compiled = compile_with_lookup(
        &parsed.items[0].children,
        None,
        &bindings,
        None,
        Some(&Debug),
    )
    .unwrap();
    assert_eq!(compiled.local_count, 0);
    let frozen = crate::freeze_proc(&compiled.code).unwrap();
    let decoded = byond_dmb::bytecode::decode(frozen.code().words().as_ref()).unwrap();
    assert!(decoded.iter().any(|instruction| instruction.opcode == 0x78));
    assert!(!decoded
        .iter()
        .any(|instruction| instruction.opcode == opcode::TEQ));
    let selector = decoded
        .iter()
        .position(|instruction| instruction.opcode == opcode::GET_VAR)
        .unwrap();
    assert_eq!(decoded[selector - 2].opcode, 0x84);
    assert_eq!(decoded[selector - 1].opcode, 0x85);
    assert!(frozen
        .code()
        .relocations()
        .any(|site| matches!(site.reference, SymRef::SourceLine(_))));
}

#[test]
fn constant_switch_tables_have_no_synthetic_locals_and_valid_case_targets() {
    for (arms, expected) in [
        ("    if(1, 2)\n      return 10\n", 0x78),
        (
            "    if(1, 2)\n      return 10\n    if(3 to 5)\n      return 20\n",
            0x7a,
        ),
    ] {
        let source = format!("/proc/test(x)\n  switch(x)\n{arms}    else\n      return 0\n");
        let ast = dm_syntax::parse(&source);
        let compiled =
            compile_simple_proc_with_params(&ast.items[0].children, &["x".into()]).unwrap();
        assert_eq!(compiled.local_count, 0);
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
        let table = decoded.iter().find(|ins| ins.opcode == expected).unwrap();
        let targets = table.branch_targets().unwrap();
        assert!(targets.len() >= 3);
        for target in targets {
            assert!(decoded.iter().any(|ins| ins.offset == target as usize));
        }
        assert!(!decoded.iter().any(|ins| ins.opcode == opcode::TEQ));
    }
}

#[test]
fn dynamic_switch_alternative_keeps_existing_runtime_fallback() {
    let ast = dm_syntax::parse(
        "/proc/test(x, y)\n  switch(x)\n    if(y)\n      return 1\n    else\n      return 0\n",
    );
    let compiled =
        compile_simple_proc_with_params(&ast.items[0].children, &["x".into(), "y".into()]).unwrap();
    assert_eq!(compiled.local_count, 1);
    let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
    let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
    assert!(decoded.iter().any(|ins| ins.opcode == opcode::TEQ));
    assert!(!decoded.iter().any(|ins| matches!(ins.opcode, 0x78 | 0x7a)));
}

#[test]
fn range_null_string_table_matches_authenticated_native_fixture() {
    let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../fixtures/lowering");
    let native =
        byond_dmb::dmb::Dmb::from_bytes(&std::fs::read(dir.join("switch_range_null.bin")).unwrap())
            .unwrap();
    let source = std::fs::read_to_string(dir.join("switch_range_null.dm")).unwrap();
    let ast = dm_syntax::parse(&source);
    let compiled =
        compile_simple_proc_with_params(&ast.items[0].children, &["value".into()]).unwrap();
    assert_eq!(compiled.local_count, 0);
    let mut ledger = Ledger::default();
    for text in ["negative", "null", "zero", "text", "other"] {
        let id = native
            .strings
            .iter()
            .position(|entry| entry.data == text.as_bytes())
            .unwrap();
        ledger
            .bind(SymRef::String(SymbolId::of(text)), id as u32)
            .unwrap();
    }
    let linked = link_proc(&compiled.code, &ledger).unwrap();
    let actual = byond_dmb::bytecode::decode(&linked.words).unwrap();
    let expected = byond_dmb::bytecode::decode(native.proc_code_words(0).unwrap()).unwrap();
    let a = actual.iter().find(|ins| ins.opcode == 0x7a).unwrap();
    let b = expected.iter().find(|ins| ins.opcode == 0x7a).unwrap();
    let branch_words = a.branch_target_word_offsets().unwrap();
    assert_eq!(a.operands.len(), b.operands.len());
    // Targets differ because debug/prologue layout differs; all value words are exact.
    for (offset, (left, right)) in a.operands.iter().zip(&b.operands).enumerate() {
        if !branch_words.contains(&(a.offset + 1 + offset)) {
            assert_eq!(left, right, "table value word {offset}");
        }
    }
    for (target, text) in a
        .branch_targets()
        .unwrap()
        .into_iter()
        .zip(["negative", "null", "zero", "text", "other"])
    {
        let at = target as usize;
        assert_eq!(linked.words[at], opcode::PUSH_VAL);
        assert_eq!(native.string(linked.words[at + 2]), Some(text.as_bytes()));
    }
}

#[test]
fn overlapping_range_and_exact_case_preserve_authored_fallback() {
    let ast = dm_syntax::parse(
        "/proc/test(x)\n  switch(x)\n    if(2)\n      return 1\n    if(1 to 3)\n      return 2\n",
    );
    let compiled = compile_simple_proc_with_params(&ast.items[0].children, &["x".into()]).unwrap();
    assert_eq!(compiled.local_count, 1);
    let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
    assert!(!byond_dmb::bytecode::decode(&linked.words)
        .unwrap()
        .iter()
        .any(|ins| ins.opcode == 0x7a));
}

#[test]
fn switch_default_targets_preserve_native_authored_transfers() {
    let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../fixtures/translation/switch_default_transfer");
    let native =
        byond_dmb::dmb::Dmb::from_bytes(&std::fs::read(dir.join("probe.native.bin")).unwrap())
            .unwrap();
    let ast = dm_syntax::parse(&std::fs::read_to_string(dir.join("probe.dm")).unwrap());
    for name in [
        "range_continue",
        "exact_continue",
        "string_goto",
        "range_protected_continue",
    ] {
        let item = ast
            .items
            .iter()
            .find(|item| item.header == format!("/proc/{name}(v)"))
            .unwrap();
        let compiled = compile_simple_proc_with_params(&item.children, &["v".into()]).unwrap();
        let mut ledger = Ledger::default();
        if name == "string_goto" {
            let id = native
                .strings
                .iter()
                .position(|entry| entry.data == b"x")
                .unwrap();
            ledger
                .bind(SymRef::String(SymbolId::of("x")), id as u32)
                .unwrap();
        }
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        let id = native
            .procs
            .iter()
            .position(|proc| {
                native.string(proc.strings[0]) == Some(format!("/proc/{name}").as_bytes())
            })
            .unwrap();
        let first_at_default = |words: &[u32]| {
            let body = byond_dmb::bytecode::decode(words).unwrap();
            let table = body
                .iter()
                .find(|ins| matches!(ins.opcode, 0x78 | 0x7a))
                .unwrap();
            let target = *table.branch_targets().unwrap().last().unwrap() as usize;
            body.iter()
                .skip_while(|ins| ins.offset < target)
                .find(|ins| !matches!(ins.opcode, 0x84 | 0x85))
                .unwrap()
                .opcode
        };
        assert_eq!(
            first_at_default(&linked.words),
            first_at_default(native.proc_code_words(id).unwrap()),
            "{name} authored transfer must remain at default entry"
        );
    }
}

#[test]
fn authored_forward_and_backward_gotos_both_check_budget() {
    for (source, expected) in [
        (
            "/proc/test()\n  goto later\n  later:\n    return 0\n",
            opcode::JMP_LOOP,
        ),
        ("/proc/test()\n  again:\n    goto again\n", opcode::JMP_LOOP),
    ] {
        let ast = dm_syntax::parse(source);
        let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        let body = byond_dmb::bytecode::decode(&linked.words).unwrap();
        assert_eq!(body[0].opcode, expected);
    }
}

#[test]
fn authored_goto_dispatch_matches_existing_native_matrix() {
    let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../fixtures/translation/goto_budget");
    let native =
        byond_dmb::dmb::Dmb::from_bytes(&std::fs::read(dir.join("probe.native.bin")).unwrap())
            .unwrap();
    let ast = dm_syntax::parse(&std::fs::read_to_string(dir.join("probe.dm")).unwrap());
    let effect = native
        .procs
        .iter()
        .position(|proc| native.string(proc.strings[0]) == Some(b"/proc/effect".as_slice()))
        .unwrap();
    let branches = |words: &[u32]| {
        let body = byond_dmb::bytecode::decode(words).unwrap();
        body.iter()
            .filter(|ins| matches!(ins.opcode, 0xf8 | 0x12f))
            .map(|ins| {
                let target = ins.operands[0] as usize;
                let destination = body
                    .iter()
                    .find(|next| next.offset >= target && !matches!(next.opcode, 0x84 | 0x85))
                    .unwrap();
                (ins.opcode, target <= ins.offset, destination.opcode)
            })
            .collect::<Vec<_>>()
    };
    for name in [
        "backward",
        "forward",
        "switch_forward",
        "nested",
        "immediate",
        "conditional",
        "ordinary_if",
        "natural_loop",
        "protected_goto",
    ] {
        let item = ast
            .items
            .iter()
            .find(|item| item.header == format!("/proc/{name}(flag)"))
            .unwrap();
        let bindings = LowerBindings {
            parameters: vec!["flag".into()],
            global_procs: HashMap::from([(
                "effect".into(),
                SymRef::Proc {
                    owner: SymbolId::of("/"),
                    name: SymbolId::of("effect"),
                    occurrence: 0,
                },
            )]),
            ..LowerBindings::default()
        };
        let compiled = compile_simple_proc_with_bindings(&item.children, &bindings).unwrap();
        let mut ledger = Ledger::default();
        ledger
            .bind(
                SymRef::Proc {
                    owner: SymbolId::of("/"),
                    name: SymbolId::of("effect"),
                    occurrence: 0,
                },
                effect as u32,
            )
            .unwrap();
        for string in &compiled.strings {
            let id = native
                .strings
                .iter()
                .position(|entry| entry.data == string.bytes.as_ref())
                .unwrap();
            ledger.bind(SymRef::String(string.id), id as u32).unwrap();
        }
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        let id = native
            .procs
            .iter()
            .position(|proc| {
                native.string(proc.strings[0]) == Some(format!("/proc/{name}").as_bytes())
            })
            .unwrap();
        assert_eq!(
            branches(&linked.words),
            branches(native.proc_code_words(id).unwrap()),
            "{name}"
        );
    }
}

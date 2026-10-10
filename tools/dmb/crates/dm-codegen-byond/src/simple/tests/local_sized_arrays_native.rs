//! Complete executable comparisons with pinned compile-only local array captures.
use super::*;

#[test]
fn local_sized_array_initializers_match_native_complete_words() {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../fixtures/native/local_sized_array_initializers");
    for case in [
        "explicit_list",
        "explicit_null",
        "implicit",
        "multidim_list",
        "scalar",
        "nonliteral",
        "multidim_implicit",
    ] {
        let source = std::fs::read_to_string(root.join(format!("{case}.dm"))).unwrap();
        let native = byond_dmb::dmb::Dmb::from_bytes(
            &std::fs::read(root.join(format!("{case}.native.bin"))).unwrap(),
        )
        .unwrap();
        let ast = dm_syntax::parse(&source);
        let bindings = LowerBindings {
            parameters: vec!["n".into()],
            parameter_defaults: vec![Some("3".into())],
            ..LowerBindings::default()
        };
        let compiled = compile_simple_proc_with_bindings(&ast.items[0].children, &bindings)
            .unwrap_or_else(|errors| panic!("{case}: {errors:?}"));
        let proc_id = native
            .procs
            .iter()
            .position(|proc| native.string(proc.strings[0]) == Some(b"/proc/probe".as_slice()))
            .unwrap();
        let native_words = native.proc_code_words(proc_id).unwrap();
        let native_instructions = byond_dmb::bytecode::decode(native_words).unwrap();
        let mut ledger = Ledger::default();
        for path in &compiled.class_paths {
            let id = if *path == SymbolId::of("/list") {
                // This native builtin value is not an ordinary Class-table row.
                let operand = native_instructions
                    .iter()
                    .find(|instruction| {
                        instruction.opcode == opcode::PUSH_VAL
                            && instruction.operands.first() == Some(&40)
                    })
                    .expect("captured builtin list allocation operand");
                assert_eq!(operand.operands.len(), 2);
                assert_eq!(
                    operand.operands[1], 0,
                    "authenticated /list builtin payload"
                );
                operand.operands[1]
            } else {
                native
                    .classes
                    .iter()
                    .position(|class| {
                        native
                            .string(class.path_string_id())
                            .map(SymbolId::of_bytes)
                            == Some(*path)
                    })
                    .expect("current captured class identity") as u32
            };
            ledger.bind(SymRef::Type(*path), id).unwrap();
        }
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        let decode = |words: &[u32]| {
            byond_dmb::bytecode::decode(words)
                .unwrap()
                .into_iter()
                .filter(|instruction| !matches!(instruction.opcode, 0x84 | 0x85))
                .map(|instruction| (instruction.opcode, instruction.operands))
                .collect::<Vec<_>>()
        };
        assert_eq!(
            decode(&linked.words),
            decode(native.proc_code_words(proc_id).unwrap()),
            "{case}"
        );
        if case == "nonliteral" {
            assert_eq!(
                decode(&linked.words)
                    .iter()
                    .filter(|(op, args)| {
                        *op == opcode::GET_VAR && args.as_slice() == [0xffd9, 0]
                    })
                    .count(),
                2,
                "one default guard read plus one dimension read"
            );
        }
    }
}

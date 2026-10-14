//! Direct producer comparisons with the committed native deletion capture.
use super::*;

fn executable(words: &[u32]) -> Vec<(u32, Vec<u32>)> {
    let mut result = Vec::new();
    for instruction in byond_dmb::bytecode::decode(words).unwrap() {
        if matches!(instruction.opcode, 0x84 | 0x85) {
            continue;
        }
        result.push((instruction.opcode, instruction.operands));
        // del(src) terminates its procedure; compare all executable instructions,
        // including End, without comparing unreachable compiler terminal padding.
        if instruction.opcode == opcode::END {
            break;
        }
    }
    result
}

#[test]
fn mutable_local_argument_and_temporary_deletion_match_native() {
    let source = include_str!("../../../../../fixtures/translation/delete_lvalue/delete_lvalue.dm");
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/delete_lvalue/delete_lvalue.native.bin"
    ))
    .unwrap();
    let ast = dm_syntax::parse(source);
    for (path, parameters) in [
        ("/proc/delete_local", vec![]),
        ("/proc/delete_argument", vec!["value".into()]),
        ("/proc/delete_text_storage", vec![]),
        ("/proc/delete_temporary", vec![]),
        ("/datum/holder/proc/delete_src", vec![]),
    ] {
        let item = ast
            .items
            .iter()
            .find(|item| item.header.split('(').next() == Some(path))
            .unwrap();
        let compiled = compile_simple_proc_with_params(&item.children, &parameters).unwrap();
        let mut ledger = Ledger::default();
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
            .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
            .unwrap();
        assert_eq!(
            executable(&linked.words),
            executable(native.proc_code_words(id).unwrap()),
            "{path}"
        );
    }
}

#[test]
fn lexical_src_parameter_is_cleared_and_does_not_terminate_body() {
    let ast = dm_syntax::parse("/proc/delete_shadow(src)\n    del(src)\n    return src\n");
    let compiled =
        compile_simple_proc_with_params(&ast.items[0].children, &["src".into()]).unwrap();
    let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
    let instructions = executable(&linked.words);
    let deletion = instructions
        .iter()
        .position(|(opcode, _)| *opcode == 0x0c)
        .unwrap();
    assert_eq!(instructions[deletion - 2], (opcode::PUSH_VAL, vec![0, 0]));
    assert_eq!(
        instructions[deletion - 1],
        (opcode::SET_VAR, vec![0xffd9, 0])
    );
    assert_eq!(
        instructions[deletion + 1],
        (opcode::GET_VAR, vec![0xffd9, 0])
    );
    assert_eq!(instructions[deletion + 2].0, opcode::RET);
}

#[test]
fn indexed_and_effectful_indexed_deletion_match_native() {
    let source = include_str!("../../../../../fixtures/translation/delete_lvalue/delete_lvalue.dm");
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/delete_lvalue/delete_lvalue.native.bin"
    ))
    .unwrap();
    let ast = dm_syntax::parse(source);
    for (name, parameters, helpers) in [
        ("delete_index", vec!["values".into(), "key".into()], vec![]),
        (
            "delete_effectful_index",
            vec!["L".into()],
            vec!["get_values", "get_key"],
        ),
    ] {
        let path = format!("/proc/{name}");
        let item = ast
            .items
            .iter()
            .find(|item| item.header.split('(').next() == Some(path.as_str()))
            .unwrap();
        let bindings = LowerBindings {
            parameters,
            global_procs: helpers
                .iter()
                .map(|name| {
                    (
                        (*name).to_owned(),
                        reference(Table::Proc, format!("/proc/{name}")),
                    )
                })
                .collect(),
            ..Default::default()
        };
        let compiled = compile_simple_proc_with_bindings(&item.children, &bindings).unwrap();
        let mut ledger = Ledger::default();
        for string in &compiled.strings {
            let id = native
                .strings
                .iter()
                .position(|entry| entry.data == string.bytes.as_ref())
                .unwrap();
            ledger.bind(SymRef::String(string.id), id as u32).unwrap();
        }
        for helper in helpers {
            let helper_path = format!("/proc/{helper}");
            let id = native
                .procs
                .iter()
                .position(|proc| native.string(proc.strings[0]) == Some(helper_path.as_bytes()))
                .unwrap();
            ledger
                .bind(reference(Table::Proc, helper_path), id as u32)
                .unwrap();
        }
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        let id = native
            .procs
            .iter()
            .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
            .unwrap();
        assert_eq!(
            executable(&linked.words),
            executable(native.proc_code_words(id).unwrap()),
            "{path}"
        );
    }
}

#[test]
fn mutable_and_readonly_intrinsic_deletion_match_native() {
    let source =
        include_str!("../../../../../fixtures/translation/delete_readonly_intrinsics/probe.dm");
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/delete_readonly_intrinsics/probe.native.bin"
    ))
    .unwrap();
    let ast = dm_syntax::parse(source);
    for name in [
        "world",
        "caller",
        "callee",
        "src",
        "usr",
        "args",
        "global_vars",
        "src_type",
    ] {
        let path = format!("/obj/proc/delete_intrinsic_{name}");
        let item = ast
            .items
            .iter()
            .find(|item| item.header.split('(').next() == Some(path.as_str()))
            .unwrap();
        let compiled = compile_simple_proc(&item.children).unwrap();
        let id = native
            .procs
            .iter()
            .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
            .unwrap();
        let mut ledger = Ledger::default();
        for string in &compiled.strings {
            let id = native
                .strings
                .iter()
                .position(|entry| entry.data == string.bytes.as_ref())
                .unwrap();
            ledger.bind(SymRef::String(string.id), id as u32).unwrap();
        }
        if name == "global_vars" {
            let instructions =
                byond_dmb::bytecode::decode(native.proc_code_words(id).unwrap()).unwrap();
            let get = instructions
                .iter()
                .find(|ins| ins.opcode == opcode::GET_VAR)
                .unwrap();
            let (byond_dmb::operands::Variable::Global(slot), _) =
                byond_dmb::operands::Variable::decode(&get.operands).unwrap()
            else {
                panic!("native global.vars storage operand");
            };
            assert_eq!(native.variables[slot as usize].kind, 82);
            ledger.bind(SymRef::BuiltinGlobalVars, slot).unwrap();
        }
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        assert_eq!(
            executable(&linked.words),
            executable(native.proc_code_words(id).unwrap()),
            "{path}"
        );
    }
}

#[test]
fn nonlocal_deletion_requires_exact_nonopaque_writable_metadata() {
    use dm_ir::{ResolveQuery as Q, ResolvedMeaning as M, Resolver, SymbolTable};
    struct Host {
        flags: u32,
        complete: bool,
    }
    impl Resolver for Host {
        fn resolve(&self, query: Q) -> M {
            let owner = SymbolId::of("/datum/holder");
            let name = SymbolId::of("value");
            match query {
                Q::HasMemberVar {
                    owner: found,
                    name: selected,
                } if found == owner && selected == name => M::Presence(true),
                Q::VarStorage {
                    owner: found,
                    name: selected,
                } if found == owner && selected == name => M::InstanceField {
                    declaring_owner: owner,
                    name,
                },
                Q::Var {
                    owner: found,
                    name: selected,
                } if found == owner && selected == name => {
                    if !self.complete {
                        return M::Unsupported(query);
                    }
                    let mut data = dm_ir::DeclarationMeaning::default();
                    data.flags = self.flags;
                    M::Member {
                        owner,
                        name,
                        fingerprint: 1,
                        data: std::sync::Arc::new(data),
                    }
                }
                _ => M::Missing,
            }
        }
    }
    let mut symbols = SymbolTable::default();
    symbols.intern("/datum/holder").unwrap();
    symbols.intern("value").unwrap();
    let ast = dm_syntax::parse("/datum/holder/proc/delete_field()\n    del(value)\n");
    let inputs = crate::lower_resolver::ProcedureInputs {
        current_type_path: Some("/datum/holder".into()),
        ..Default::default()
    };
    for flags in [0, 2] {
        let lowered = compile_simple_proc_with_resolver(
            &ast.items[0].children,
            &inputs,
            &symbols,
            &Host {
                flags,
                complete: true,
            },
        )
        .unwrap();
        let setters = lowered
            .procedure
            .code
            .items
            .iter()
            .filter(|item| {
                matches!(
                    item,
                    CodeItem::Instruction(Instruction {
                        opcode: opcode::SET_VAR,
                        ..
                    })
                )
            })
            .count();
        assert_eq!(setters, usize::from(flags == 0));
    }
    assert!(compile_simple_proc_with_resolver(
        &ast.items[0].children,
        &inputs,
        &symbols,
        &Host {
            flags: 0,
            complete: false
        }
    )
    .is_err());
}

#[path = "typed_delete_resolver_native.rs"]
mod resolver_native;

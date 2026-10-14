//! Exact authored declaration metadata, paired with existing native capture.
use super::*;
use dm_ir::{ResolveQuery as Q, ResolvedMeaning as M, Resolver, SymbolTable};
use std::sync::Arc;

struct Declarations;
impl Resolver for Declarations {
    fn resolve(&self, query: Q) -> M {
        let root = SymbolId::of("/");
        let holder = SymbolId::of("/datum/holder");
        let known = |owner, name| {
            (owner == root
                && (name == SymbolId::of("value") || name == SymbolId::of("null_global")))
                || (owner == holder
                    && (name == SymbolId::of("value") || name == SymbolId::of("null_field")))
        };
        let metadata = |owner, name| {
            let mut data = dm_ir::DeclarationMeaning::default();
            if name == SymbolId::of("null_field") || name == SymbolId::of("null_global") {
                data.flags = 2;
                data.resolved_constant = Some(dm_ir::SemanticValue::Null);
            }
            M::Member {
                owner,
                name,
                fingerprint: 1,
                data: Arc::new(data),
            }
        };
        match query {
            Q::RuntimeType(path) => M::Symbol(path),
            Q::HasMemberVar { owner, name } => M::Presence(known(owner, name)),
            Q::GlobalVar(name) if known(root, name) => metadata(root, name),
            Q::Var { owner, name } if known(owner, name) => metadata(owner, name),
            Q::VarStorage { owner, name }
                if owner == holder && name == SymbolId::of("null_field") =>
            {
                M::Slot {
                    symbol: SymbolId::of("/datum/holder::null_field"),
                    owner,
                    name,
                }
            }
            Q::VarStorage { owner, name } if known(owner, name) && owner == holder => {
                M::InstanceField {
                    declaring_owner: owner,
                    name,
                }
            }
            Q::VarStorage { owner, name } if known(owner, name) && owner == root => M::Slot {
                symbol: name,
                owner,
                name,
            },
            Q::DeclaredVarType { owner, name } if known(owner, name) => M::DeclaredType(None),
            Q::Constant { owner, name }
                if known(owner, name)
                    && (name == SymbolId::of("null_field")
                        || name == SymbolId::of("null_global")) =>
            {
                M::Value(dm_ir::SemanticValue::Null)
            }
            _ => M::Missing,
        }
    }
}

fn normalized(words: &[u32]) -> Vec<(u32, Vec<u32>)> {
    let all = byond_dmb::bytecode::decode(words).unwrap();
    let semantic: Vec<_> = all
        .iter()
        .filter(|ins| !matches!(ins.opcode, 0x84 | 0x85))
        .collect();
    semantic
        .iter()
        .map(|ins| {
            let mut operands = ins.operands.clone();
            for offset in ins.branch_target_word_offsets().unwrap() {
                let operand = offset - ins.offset - 1;
                let target = operands[operand] as usize;
                operands[operand] = semantic
                    .iter()
                    .position(|dest| dest.offset >= target)
                    .expect("branch destination in current procedure")
                    as u32;
            }
            (ins.opcode, operands)
        })
        .collect()
}

#[test]
fn typed_safe_const_fields_and_globals_match_authenticated_native() {
    let source = include_str!("../../../../../fixtures/translation/delete_lvalue/delete_lvalue.dm");
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/delete_lvalue/delete_lvalue.native.bin"
    ))
    .unwrap();
    let ast = dm_syntax::parse(source);
    let mut symbols = SymbolTable::default();
    for text in ["/", "/datum/holder", "value", "null_field", "null_global"] {
        symbols.intern(text).unwrap();
    }
    for (path, parameters, parameter_types, current_type_path) in [
        ("/proc/delete_global", vec![], HashMap::new(), "/"),
        ("/proc/delete_const_global", vec![], HashMap::new(), "/"),
        (
            "/datum/holder/proc/delete_field",
            vec![],
            HashMap::new(),
            "/datum/holder",
        ),
        (
            "/proc/delete_safe",
            vec!["H".into()],
            HashMap::from([("H".into(), "/datum/holder".into())]),
            "/",
        ),
        (
            "/proc/delete_const_field",
            vec!["H".into()],
            HashMap::from([("H".into(), "/datum/holder".into())]),
            "/",
        ),
        (
            "/proc/delete_safe_const",
            vec!["H".into()],
            HashMap::from([("H".into(), "/datum/holder".into())]),
            "/",
        ),
    ] {
        let item = ast
            .items
            .iter()
            .find(|item| item.header.split('(').next() == Some(path))
            .unwrap();
        let inputs = crate::lower_resolver::ProcedureInputs {
            parameters,
            parameter_types,
            current_type_path: Some(current_type_path.into()),
            ..Default::default()
        };
        let lowered =
            compile_simple_proc_with_resolver(&item.children, &inputs, &symbols, &Declarations)
                .unwrap();
        let compiled = lowered.procedure;
        let mut ledger = Ledger::default();
        for string in &compiled.strings {
            let id = native
                .strings
                .iter()
                .position(|entry| entry.data == string.bytes.as_ref())
                .unwrap();
            ledger.bind(SymRef::String(string.id), id as u32).unwrap();
        }
        for (reference, slot) in &lowered.slots {
            let text = symbols.text(slot.name).unwrap();
            let id = native
                .global_variable_flags()
                .unwrap()
                .iter()
                .map(|(id, _)| *id)
                .find(|id| {
                    native.string(native.variables[*id as usize].name) == Some(text.as_bytes())
                })
                .unwrap();
            ledger.bind(*reference, id).unwrap();
        }
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        let id = native
            .procs
            .iter()
            .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
            .unwrap();
        assert_eq!(
            normalized(&linked.words),
            normalized(native.proc_code_words(id).unwrap()),
            "{path}"
        );
    }
}

use crate::{compile_simple_proc_with_resolver, lower_resolver::ProcedureInputs};
use dm_ir::{ResolveQuery as Q, ResolvedMeaning as M, Resolver, SymbolTable};
use std::{collections::HashMap, sync::Mutex};

#[derive(Default)]
struct UnknownFields(Mutex<Vec<Q>>);
impl Resolver for UnknownFields {
    fn resolve(&self, query: Q) -> M {
        self.0.lock().unwrap().push(query);
        match query {
            Q::RuntimeType(path) if path == dm_ir::SymbolId::of("/obj/item") => M::Symbol(path),
            _ => M::Unsupported(query),
        }
    }
}

#[test]
fn colon_fields_bypass_static_receiver_facts_while_dot_remains_strict() {
    let mut symbols = SymbolTable::default();
    symbols.intern("/obj/item").unwrap();
    symbols.intern("status").unwrap();
    let inputs = ProcedureInputs {
        parameters: vec!["W".into()],
        parameter_types: HashMap::from([("W".into(), "/obj/item".into())]),
        ..Default::default()
    };
    for body in ["return W:status", "W:status = 1", "W:status += 1", "W:status++"] {
        let source = format!("/proc/probe(W)\n    {body}\n");
        let parsed = dm_syntax::parse(&source);
        let host = UnknownFields::default();
        let code = compile_simple_proc_with_resolver(&parsed.items[0].children,
            &inputs, &symbols, &host).unwrap();
        assert!(code.procedure.strings.iter().any(|name| name == "status"));
        assert!(host.0.lock().unwrap().is_empty(), "{body}");
    }
    let parsed = dm_syntax::parse("/proc/probe(W)\n    return W.status\n");
    let host = UnknownFields::default();
    assert!(compile_simple_proc_with_resolver(&parsed.items[0].children,
        &inputs, &symbols, &host).is_err());
    assert!(host.0.lock().unwrap().iter().any(|query|
        matches!(query, Q::VarStorage { .. })));
}

#[test]
fn frame_references_use_native_words_and_lexical_parameters_shadow_them() {
    // Pinned call_frames.native.bin SHA256:
    // 2dd5108390ca1860dd136cb6c6d0fb123164392a579c32018bade8dc07a8a07e.
    // Its frame_caller/frame_callee procedures use fff0/fff1 respectively.
    let symbols = SymbolTable::default();
    for (name, expected) in [("caller", 0xfff0), ("callee", 0xfff1)] {
        let parsed = dm_syntax::parse(&format!("/proc/probe()\n    return {name}\n"));
        let host = UnknownFields::default();
        let code = compile_simple_proc_with_resolver(&parsed.items[0].children,
            &Default::default(), &symbols, &host).unwrap();
        let frozen = crate::encoder::freeze_proc(&code.procedure.code,
            |_| Err("frame has no table reference".into())).unwrap();
        assert!(frozen.code().words().windows(2).any(|words| words == [0x33, expected]));
        assert!(host.0.lock().unwrap().is_empty());
        let inputs = ProcedureInputs { parameters:vec![name.into()], ..Default::default() };
        let code = compile_simple_proc_with_resolver(&parsed.items[0].children,
            &inputs, &symbols, &host).unwrap();
        assert!(code.procedure.code.items.iter().any(|item|
            matches!(item, crate::Item::Instruction(instruction)
                if instruction.operands.iter().any(|word|
                    matches!(word, crate::Word::Variable(crate::VariableWord::Arg(0)))))));
    }
}

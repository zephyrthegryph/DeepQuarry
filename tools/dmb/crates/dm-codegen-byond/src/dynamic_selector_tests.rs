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

#[test]
fn computed_receiver_with_proven_instance_storage_skips_global_uniqueness() {
    struct InstanceField(Mutex<Vec<Q>>);
    impl Resolver for InstanceField {
        fn resolve(&self, query: Q) -> M {
            self.0.lock().unwrap().push(query);
            match query {
                Q::RuntimeType(path) => M::Symbol(path),
                Q::Ancestry(path) => M::Symbols(vec![path, dm_ir::SymbolId::of("/obj")]),
                Q::VarStorage { owner, name } => M::InstanceField { declaring_owner:owner, name },
                _ => M::Unsupported(query),
            }
        }
    }
    let mut symbols = SymbolTable::default();
    symbols.intern("/obj/item").unwrap();
    symbols.intern("/obj").unwrap();
    symbols.intern("status").unwrap();
    let host = InstanceField(Mutex::new(vec![]));
    let parsed = dm_syntax::parse("/proc/probe()\n    return (/obj/item).status\n");
    let code = compile_simple_proc_with_resolver(&parsed.items[0].children,
        &Default::default(), &symbols, &host).unwrap();
    assert!(code.procedure.strings.iter().any(|name| name == "status"));
    assert!(host.0.lock().unwrap().iter().any(|query| matches!(query, Q::VarStorage { .. })));
    assert!(!host.0.lock().unwrap().iter().any(|query| matches!(query, Q::UniqueStaticVar(_))));
}

#[test]
fn authored_call_return_annotation_types_nested_field_context() {
    use dm_ir::{DeclarationMeaning, ExpressionToken, ProcedureMetadata, ProcedureSignature,
        SymbolId, SymbolicExpression};
    use std::sync::Arc;
    let mut symbols = SymbolTable::default();
    for text in ["/datum/client", "/datum/message", "/datum/file", "/datum", "current_message", "attachment"] {
        symbols.intern(text).unwrap();
    }
    let annotation = SymbolicExpression { tokens: dm_syntax::lex("/datum/message").tokens
        .into_iter().map(|token| ExpressionToken { kind:token.kind,
            text:symbols.intern(&token.text).unwrap(), relative_span:token.span }).collect() };
    struct Host { metadata:Arc<DeclarationMeaning>, reads:Mutex<Vec<Q>> }
    impl Resolver for Host {
        fn resolve(&self, query:Q)->M {
            self.reads.lock().unwrap().push(query);
            match query {
                Q::RuntimeType(path) => M::Symbol(path),
                Q::Ancestry(path) => M::Symbols(vec![path, SymbolId::of("/datum")]),
                Q::HasMemberProc { name, .. } if name==SymbolId::of("current_message") => M::Presence(true),
                Q::Proc { owner, name, verb:false } if name==SymbolId::of("current_message") =>
                    M::Member {owner,name,fingerprint:1,data:self.metadata.clone()},
                Q::VarStorage { owner, name } if name==SymbolId::of("attachment") =>
                    M::InstanceField {declaring_owner:owner,name},
                Q::DeclaredVarType {name,..} if name==SymbolId::of("attachment") =>
                    M::DeclaredType(Some(SymbolId::of("/datum/file"))),
                _ => M::Unsupported(query),
            }
        }
    }
    let host=Host {metadata:Arc::new(DeclarationMeaning { procedure:Some(Arc::new(ProcedureMetadata {
        signature:ProcedureSignature {parameters:Arc::from([]),variadic:false,return_annotation:Some(annotation)},
        settings:Arc::from([]),
    })), ..Default::default() }), reads:Mutex::new(vec![]) };
    let parsed=dm_syntax::parse("/proc/probe()\n    return istype(current_message().attachment)\n");
    let code=compile_simple_proc_with_resolver(&parsed.items[0].children,
        &ProcedureInputs {current_type_path:Some("/datum/client".into()),..Default::default()},
        &symbols,&host).unwrap();
    assert!(code.procedure.class_paths.iter().any(|path| path=="/datum/file"));
    assert!(host.reads.lock().unwrap().iter().any(|query|
        matches!(query,Q::DeclaredVarType {owner,..} if *owner==SymbolId::of("/datum/message"))));
}

#[test]
fn current_proc_builtin_precedes_unrelated_member_queries_and_keeps_relocation() {
    let mut symbols=SymbolTable::default();
    let owner=symbols.intern("/datum/log_entry").unwrap();
    let name=symbols.intern("read").unwrap();
    let host=UnknownFields::default();
    let parsed=dm_syntax::parse("/proc/probe()\n    return __PROC__\n");
    let inputs=ProcedureInputs {current_type_path:Some("/datum/log_entry".into()),
        current_proc_path:Some("/datum/log_entry/proc/read".into()),..Default::default()};
    let code=compile_simple_proc_with_resolver(&parsed.items[0].children,&inputs,&symbols,&host).unwrap();
    assert!(host.0.lock().unwrap().is_empty());
    let frozen=crate::encoder::freeze_proc(&code.procedure.code, |symbol| {
        assert_eq!(symbol.key,"/datum/log_entry/proc/read");
        Ok(dm_ir::SymRef::Proc {owner,name,occurrence:0})
    }).unwrap();
    assert_eq!(frozen.code().relocations().len(),1);
    let linked=frozen.code().link(|_| Some(13)).unwrap();
    assert!(linked.windows(2).any(|words| words==[38,13]));
    let inputs=ProcedureInputs {parameters:vec!["__PROC__".into()],..inputs};
    let code=compile_simple_proc_with_resolver(&parsed.items[0].children,&inputs,&symbols,&host).unwrap();
    assert!(code.procedure.code.items.iter().any(|item|
        matches!(item,crate::Item::Instruction(instruction) if instruction.operands.iter()
            .any(|word| matches!(word,crate::Word::Variable(crate::VariableWord::Arg(0)))))));
}

#[test]
fn authored_global_access_records_exact_root_slot_sidecar() {
    use dm_ir::SymbolId;
    struct Host;
    impl Resolver for Host {
        fn resolve(&self, query:Q)->M {
            let root=SymbolId::of("/"); let name=SymbolId::of("__rust_g");
            match query {
                Q::GlobalVar(actual) if actual==name => M::Member {owner:root,name,
                    fingerprint:1,data:std::sync::Arc::new(Default::default())},
                Q::VarStorage {owner,name:actual} if owner==root && actual==name =>
                    M::Slot {symbol:SymbolId::of("slot/root/__rust_g"),owner,name},
                _=>M::Unsupported(query),
            }
        }
    }
    let mut symbols=SymbolTable::default();
    symbols.intern("/").unwrap(); symbols.intern("__rust_g").unwrap();
    for body in ["return __rust_g", "__rust_g = 1", "return global.__rust_g", "global.__rust_g = 1"] {
        let parsed=dm_syntax::parse(&format!("/proc/probe()\n    {body}\n"));
        let code=compile_simple_proc_with_resolver(&parsed.items[0].children,
            &Default::default(),&symbols,&Host).unwrap();
        assert_eq!(code.slots.len(),1,"{body}");
        let (symbol,slot)=code.slots.iter().next().unwrap();
        assert_eq!(slot.owner,SymbolId::of("/"));
        assert_eq!(slot.name,SymbolId::of("__rust_g"));
        assert_eq!(symbol.key,"var/__rust_g");
        let frozen=crate::encoder::freeze_proc(&code.procedure.code,|actual| {
            assert_eq!(actual,symbol);
            Ok(dm_ir::SymRef::VariableSlot(slot.symbol))
        }).unwrap();
        assert_eq!(frozen.code().relocations().len(),1);
    }
}

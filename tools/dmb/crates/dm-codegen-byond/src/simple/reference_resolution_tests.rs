use super::*;
struct TypedGlobal(u8);
impl dm_ir::Resolver for TypedGlobal {
    fn resolve(&self, query: dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning {
        use dm_ir::{ResolveQuery as Q, ResolvedMeaning as R};
        let name = SymbolId::of("value");
        let owner = SymbolId::of("/");
        let path = SymbolId::of("/datum/declared_alias");
        match query {
            Q::GlobalVar(n) if n == name && self.0 == 3 => R::Missing,
            Q::PredefinedConstant(n) if n == name && self.0 == 3 => {
                R::Value(dm_ir::SemanticValue::NumberBits(7.0f32.to_bits()))
            }
            Q::GlobalVar(n) if n == name => R::Member {
                owner,
                name,
                fingerprint: 0,
                data: std::sync::Arc::new(dm_ir::DeclarationMeaning {
                    declared_type: Some(path),
                    ..Default::default()
                }),
            },
            Q::VarStorage { owner: o, name: n } if o == owner && n == name => R::Slot {
                symbol: name,
                owner,
                name,
            },
            Q::DeclaredVarType { owner: o, name: n } if o == owner && n == name => {
                if self.0 == 5 {
                    R::Unsupported(query)
                } else {
                    R::DeclaredType((!matches!(self.0, 3 | 4)).then_some(path))
                }
            }
            Q::RuntimeType(p) if p == path => match self.0 {
                0 => R::Missing,
                1 => R::Symbol(SymbolId::of("/datum/current_runtime")),
                6 => R::Presence(true),
                7 => R::Unsupported(Q::RuntimeType(SymbolId::of("/different/query"))),
                _ => R::Unsupported(query),
            },
            _ => R::Missing,
        }
    }
}
#[test]
fn body_read_validates_selected_declared_type_with_current_span_and_alias_authority() {
    let source = "// current shifted occurrence\n\n/proc/read()\n    return value\n";
    let ast = dm_syntax::parse(source);
    let mut symbols = dm_ir::SymbolTable::default();
    symbols.intern("/datum/declared_alias").unwrap();
    symbols.intern("/datum/current_runtime").unwrap();
    symbols.intern("/").unwrap();
    symbols.intern("value").unwrap();
    let inputs = crate::ProcedureInputs::default();
    let compile = |host: &TypedGlobal| {
        crate::compile_simple_proc_with_resolver(&ast.items[0].children, &inputs, &symbols, host)
    };
    let errors = compile(&TypedGlobal(0))
        .err()
        .expect("definite missing type");
    let error = errors
        .iter()
        .find(|e| e.kind == LowerErrorKind::SourceError)
        .unwrap();
    assert_eq!(
        error.reason,
        "returnvalue: undefined type: /datum/declared_alias"
    );
    assert_eq!(
        error.span.unwrap().start,
        source.find("return value").unwrap()
    );
    assert!(
        compile(&TypedGlobal(1)).is_ok(),
        "current alias mapping stays valid"
    );
    assert!(
        compile(&TypedGlobal(2)).is_ok(),
        "opaque runtime mapping does not invalidate a value-only read"
    );
    for malformed in [6, 7] {
        assert!(
            compile(&TypedGlobal(malformed)).is_err(),
            "malformed optional runtime answer must decline"
        );
    }
    let scalar = compile(&TypedGlobal(3))
        .ok()
        .expect("scalar globals keep their ordinary constant producer");
    assert!(scalar.procedure.code.items.iter().any(|item| matches!(item,
        CodeItem::Instruction(instruction) if instruction.opcode == opcode::PUSH_INT)));
    assert!(
        !scalar.procedure.code.items.iter().any(|item| matches!(item,
        CodeItem::Instruction(instruction) if instruction.opcode == opcode::GET_VAR))
    );
    assert!(
        compile(&TypedGlobal(4)).is_ok(),
        "known untyped slot must not require RuntimeType authority"
    );
    assert!(
        compile(&TypedGlobal(5)).is_ok(),
        "proven value storage survives opaque optional type metadata"
    );
    let receiver = dm_syntax::parse("/proc/read()\n    return value.member\n");
    let receiver = crate::compile_simple_proc_with_resolver(
        &receiver.items[0].children,
        &inputs,
        &symbols,
        &TypedGlobal(5),
    );
    assert!(
        receiver.is_err(),
        "receiver type operations still require their own authority"
    );
    let receiver = crate::compile_simple_proc_with_resolver(
        &dm_syntax::parse("/proc/read()\n    return value.member\n").items[0].children,
        &inputs,
        &symbols,
        &TypedGlobal(2),
    );
    assert!(
        receiver.is_err(),
        "known typed opaque receiver still needs runtime mapping authority"
    );
}
struct Answers(bool);
impl dm_ir::Resolver for Answers {
    fn resolve(&self, query: dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning {
        if self.0 {
            dm_ir::ResolvedMeaning::Missing
        } else {
            dm_ir::ResolvedMeaning::Unsupported(query)
        }
    }
}
#[test]
fn authoritative_unknown_name_is_source_error_and_opaque_host_is_unsupported() {
    let source = "// shifted source\n/proc/read()\n    return missing.value\n";
    let ast = dm_syntax::parse(source);
    let symbols = dm_ir::SymbolTable::default();
    let inputs = crate::ProcedureInputs::default();
    let errors = crate::compile_simple_proc_with_resolver(
        &ast.items[0].children,
        &inputs,
        &symbols,
        &Answers(true),
    )
    .err()
    .expect("unknown name must fail compilation");
    assert!(errors
        .iter()
        .any(|error| error.kind == LowerErrorKind::SourceError
            && error.reason == "returnmissing.value: undefined var"));
    let error = errors
        .iter()
        .find(|error| error.kind == LowerErrorKind::SourceError)
        .unwrap();
    let span = error
        .span
        .expect("current statement span must survive classification");
    assert!(span.start >= source.find("return missing").unwrap());
    assert!(span.end <= source.len());
    let opaque = crate::compile_simple_proc_with_resolver(
        &ast.items[0].children,
        &inputs,
        &symbols,
        &Answers(false),
    )
    .err()
    .expect("opaque host must decline compilation");
    assert!(opaque
        .iter()
        .all(|error| error.kind == LowerErrorKind::UnsupportedModel));
}

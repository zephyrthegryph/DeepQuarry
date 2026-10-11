use super::*;
struct TypedGlobal(u8);
impl dm_ir::Resolver for TypedGlobal {
    fn resolve(&self, query: dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning {
        use dm_ir::{ResolveQuery as Q, ResolvedMeaning as R};
        let name = SymbolId::of("value");
        let owner = SymbolId::of("/");
        let path = SymbolId::of("/datum/declared_alias");
        match query {
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
                R::DeclaredType(Some(path))
            }
            Q::RuntimeType(p) if p == path => match self.0 {
                0 => R::Missing,
                1 => R::Symbol(SymbolId::of("/datum/current_runtime")),
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
    let opaque = compile(&TypedGlobal(2))
        .err()
        .expect("opaque type declines");
    assert!(opaque
        .iter()
        .all(|e| e.kind == LowerErrorKind::UnsupportedModel));
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

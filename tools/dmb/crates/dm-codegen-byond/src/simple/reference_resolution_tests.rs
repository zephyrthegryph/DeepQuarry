use super::*;
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

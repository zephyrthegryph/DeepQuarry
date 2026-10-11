//! One selection emitter shared by ordinary lowering and current resident queries.
pub(crate) fn compile_selected_view<R: dm_ir::Resolver>(
    view: dm_syntax::StatementView<'_>,
    inputs: &dm_codegen_byond::ProcedureInputs,
    symbols: &dm_ir::SymbolTable,
    resolver: &R,
    debug: Option<&dyn dm_codegen_byond::DebugSourceProvider>,
    span: dm_syntax::Span,
) -> Result<
    (
        dm_codegen_byond::lower_resolver::ResolverProc,
        dm_ir::SelectedReferences,
    ),
    Vec<dm_codegen_byond::LowerError>,
> {
    dm_codegen_byond::compile_statement_view_with_resolver_and_references_at(
        view, inputs, symbols, resolver, debug, span,
    )
}

pub(crate) fn append_selected_grammar<T>(
    result: Result<T, Vec<dm_codegen_byond::LowerError>>,
    body: &dm_tree::frontend::StatementBody,
) -> Result<T, Vec<dm_codegen_byond::LowerError>> {
    super::grammar::append(result, Some(body))
}

pub(crate) fn compile_selected_lossless<R: dm_ir::Resolver>(
    body: &[dm_syntax::Item],
    inputs: &dm_codegen_byond::ProcedureInputs,
    symbols: &dm_ir::SymbolTable,
    resolver: &R,
    debug: Option<&dyn dm_codegen_byond::DebugSourceProvider>,
) -> Result<dm_codegen_byond::lower_resolver::ResolverProc, Vec<dm_codegen_byond::LowerError>> {
    dm_codegen_byond::compile_preparsed_lossless_with_resolver(
        body, inputs, symbols, resolver, debug,
    )
}

#[cfg(test)]
mod tests {
    #[test]
    fn selected_lossless_uses_ordinary_fallback_diagnostics() {
        struct Host;
        impl dm_ir::Resolver for Host {
            fn resolve(&self, query: dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning {
                dm_ir::ResolvedMeaning::Unsupported(query)
            }
        }
        let parsed = dm_syntax::parse("/proc/read()\n    return (1 +)\n");
        let body = &parsed.items[0].children;
        let inputs = dm_codegen_byond::ProcedureInputs::default();
        let symbols = dm_ir::SymbolTable::default();
        let ordinary = dm_codegen_byond::compile_preparsed_lossless_with_resolver(
            body, &inputs, &symbols, &Host, None,
        )
        .err()
        .unwrap();
        let selected = super::compile_selected_lossless(body, &inputs, &symbols, &Host, None)
            .err()
            .unwrap();
        assert_eq!(selected, ordinary);
        assert!(!selected.is_empty());
    }
}

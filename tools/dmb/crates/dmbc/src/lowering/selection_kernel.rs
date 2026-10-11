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

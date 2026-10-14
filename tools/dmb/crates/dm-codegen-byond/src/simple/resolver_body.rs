//! Resolver-backed producer shared by ordinary and reference-capturing requests.
use super::*;

pub(super) fn compile_resolver_body<R: dm_ir::Resolver>(
    body: &[Item],
    typed: Option<TypedInput<'_>>,
    inputs: &crate::lower_resolver::ProcedureInputs,
    symbols: &dm_ir::SymbolTable,
    resolver: &R,
    debug: Option<&dyn DebugSourceProvider>,
) -> Result<crate::lower_resolver::ResolverProc, Vec<LowerError>> {
    compile_resolver_body_captured(body, typed, inputs, symbols, resolver, debug, None)
}
pub(super) fn compile_resolver_body_captured<R: dm_ir::Resolver>(
    body: &[Item],
    typed: Option<TypedInput<'_>>,
    inputs: &crate::lower_resolver::ProcedureInputs,
    symbols: &dm_ir::SymbolTable,
    resolver: &R,
    debug: Option<&dyn DebugSourceProvider>,
    reference_output: Option<reference_facts::ReferenceRequest<'_>>,
) -> Result<crate::lower_resolver::ResolverProc, Vec<LowerError>> {
    let bindings = inputs.lexical_bindings();
    let lookup = crate::lower_resolver::ProjectResolver {
        modified_instances: std::cell::RefCell::new(Default::default()),
        procedure_values: std::cell::RefCell::new(Default::default()),
        procedure_statics: std::cell::RefCell::new(Default::default()),
        resolver,
        symbols,
        slots: std::cell::RefCell::new(Default::default()),
        resources: std::cell::RefCell::new(Default::default()),
        instances: std::cell::RefCell::new(Default::default()),
        runtime_types: std::cell::RefCell::new(Default::default()),
        resource_search_context: inputs.resource_search_context,
    };
    let procedure = compile_with_lookup_mode(
        body,
        typed,
        &bindings,
        Some(&lookup),
        debug,
        true,
        reference_output,
    )?;
    Ok(crate::lower_resolver::ResolverProc {
        modified_instances: lookup.modified_instances.into_inner(),
        procedure_values: lookup.procedure_values.into_inner(),
        procedure_statics: lookup.procedure_statics.into_inner(),
        procedure,
        slots: lookup.slots.into_inner(),
        resources: lookup.resources.into_inner(),
        instances: lookup.instances.into_inner(),
    })
}

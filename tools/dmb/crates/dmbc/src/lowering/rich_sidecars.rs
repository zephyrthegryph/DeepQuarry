//! Rebind rich compatibility sidecars through the existing current recipe issuer.
use super::*;

trait SidecarDemand {
    type Failure;
    fn with_body<'f, T>(
        bodies: &dm_tree::frontend::BodyArena<'f>,
        body: &BodyOccurrence,
        consume: impl FnOnce(&dm_tree::frontend::ParsedBody<'f>) -> Option<T>,
    ) -> Result<Option<T>, Self::Failure>;
}
struct CompatibilitySidecar;
impl SidecarDemand for CompatibilitySidecar {
    type Failure = std::convert::Infallible;
    fn with_body<'f, T>(
        bodies: &dm_tree::frontend::BodyArena<'f>,
        body: &BodyOccurrence,
        consume: impl FnOnce(&dm_tree::frontend::ParsedBody<'f>) -> Option<T>,
    ) -> Result<Option<T>, Self::Failure> {
        Ok(bodies.with_parsed(body, consume).ok().flatten())
    }
}
struct CheckedSidecar;
impl SidecarDemand for CheckedSidecar {
    type Failure = LoweringFailure;
    fn with_body<'f, T>(
        bodies: &dm_tree::frontend::BodyArena<'f>,
        body: &BodyOccurrence,
        consume: impl FnOnce(&dm_tree::frontend::ParsedBody<'f>) -> Option<T>,
    ) -> Result<Option<T>, Self::Failure> {
        match bodies.with_parsed_checked(body, consume) {
            Ok(unit) => Ok(unit),
            Err(dm_tree::frontend::BodySyntaxFailure::Syntax(_)) => Ok(None),
            Err(dm_tree::frontend::BodySyntaxFailure::Operational(e)) => {
                Err(LoweringFailure::Operational(e))
            }
        }
    }
}
pub(super) fn rebind<R: Resolver>(
    previous: &LoweredUnit,
    frontend: &ColdFrontend,
    body: &BodyOccurrence,
    bodies: &dm_tree::frontend::BodyArena<'_>,
    host: &R,
    prepared: &crate::procedure_policy::PreparedUnit,
    debug: crate::debug_sources::DebugOrigins,
) -> Option<LoweredUnit> {
    rebind_with::<CompatibilitySidecar, _>(previous, frontend, body, bodies, host, prepared, debug)
        .unwrap_or_else(|impossible| match impossible {})
}
pub(super) fn rebind_checked<R: Resolver>(
    previous: &LoweredUnit,
    frontend: &ColdFrontend,
    body: &BodyOccurrence,
    bodies: &dm_tree::frontend::BodyArena<'_>,
    host: &R,
    prepared: &crate::procedure_policy::PreparedUnit,
    debug: crate::debug_sources::DebugOrigins,
) -> Result<Option<LoweredUnit>, LoweringFailure> {
    rebind_with::<CheckedSidecar, _>(previous, frontend, body, bodies, host, prepared, debug)
}
fn rebind_with<D: SidecarDemand, R: Resolver>(
    previous: &LoweredUnit,
    frontend: &ColdFrontend,
    body: &BodyOccurrence,
    bodies: &dm_tree::frontend::BodyArena<'_>,
    host: &R,
    prepared: &crate::procedure_policy::PreparedUnit,
    debug: crate::debug_sources::DebugOrigins,
) -> Result<Option<LoweredUnit>, D::Failure> {
    if crate::lowering::source_unit_identity(frontend, body)
        .ok()
        .is_none_or(|source| source.identity != previous.identity)
    {
        return Ok(None);
    }
    if previous.code.modified_instances.is_empty() && previous.source_helpers.is_empty() {
        let mut unit = previous.clone();
        unit.debug_origins = debug;
        return Ok(Some(unit));
    }
    D::with_body(bodies, body, |parsed| {
        let symbols = frontend.snapshot.tree.symbols();
        let metadata = frontend
            .snapshot
            .tree
            .member(body.member)?
            .metadata
            .procedure
            .clone()?;
        let abi = prepared.abi.as_ref()?;
        if previous.abi.as_deref() != Some(abi.as_ref())
            || previous.source_helpers.len() != abi.source_helpers.len()
        {
            return None;
        }
        let mut unit = previous.clone();
        unit.code.modified_instances.clear();
        for (reference, captured) in &previous.code.modified_instances {
            let recipe = crate::modified_initializers::prepare_seed(
                *reference,
                captured,
                &previous.debug_origins,
            )
            .ok()?
            .source_recipe(previous.origin.expanded_span)?;
            let seed = recipe.reissue(parsed, frontend, host, symbols, &debug)?;
            let (issued, current) = seed.into_current_capture();
            if issued != *reference
                || unit
                    .code
                    .modified_instances
                    .insert(issued, current)
                    .is_some()
            {
                return None;
            }
        }
        unit.source_helpers.clear();
        for (stored, issued) in previous.source_helpers.iter().zip(&abi.source_helpers) {
            if stored.owner != previous.identity || stored.argument as usize != issued.argument {
                return None;
            }
            let mut code = stored.code.clone();
            code.modified_instances.clear();
            for (reference, captured) in &stored.code.modified_instances {
                let recipe = crate::modified_initializers::prepare_seed(
                    *reference,
                    captured,
                    &stored.debug_origins,
                )
                .ok()?
                .helper_source_recipe_in(stored.argument, stored.original_root)?;
                let (issued, current) = recipe
                    .reissue(parsed, frontend, host, symbols, &debug)?
                    .into_current_capture();
                if issued != *reference || code.modified_instances.insert(issued, current).is_some()
                {
                    return None;
                }
            }
            let context = crate::argument_sources::HelperInputs {
                frontend,
                parsed: parsed.item().into(),
                metadata: &metadata,
                owner: previous.identity,
                inputs: &prepared.inputs,
                helpers: &abi.source_helpers,
                symbols,
            };
            let current = if stored.original_root.is_some() {
                crate::argument_sources::rebase_cached_helper_original(
                    context,
                    parsed,
                    stored.argument,
                    code,
                )
                .ok()?
            } else {
                crate::argument_sources::rebase_cached_helper(context, stored.argument, code)
                    .ok()?
            };
            unit.source_helpers.push(current);
        }
        unit.debug_origins = debug.clone();
        Some(unit)
    })
}

#[cfg(test)]
#[path = "rich_sidecar_tests.rs"]
mod tests;

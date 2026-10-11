//! Rebind rich compatibility sidecars through the existing current recipe issuer.
use super::*;

#[cfg(test)]
pub(super) fn diagnose_key(
    memo: &crate::lowering_memo::ProcedureMemo,
    current: &[u8],
    identity: dm_ir::ProcedureIdentity,
) {
    memo.values.visit_storage(|view| match view {
        dm_session::ArtifactStorageView::Store { entries, .. } => {
            eprintln!(
                "rich lookup: resident entries={entries}, current key len={}",
                current.len()
            );
        }
        dm_session::ArtifactStorageView::Entry { key, value, .. }
            if value.unit.identity.owner == identity.owner
                && value.unit.identity.name == identity.name =>
        {
            let first_difference = key.iter().zip(current).position(|(a, b)| a != b);
            eprintln!(
                "rich lookup: stored key len={} exact={} first_difference={first_difference:?}",
                key.len(),
                key.as_ref() == current
            );
        }
        _ => {}
    });
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
    if crate::lowering::source_unit_identity(frontend, body)
        .ok()?
        .identity
        != previous.identity
    {
        return None;
    }
    if previous.code.modified_instances.is_empty() && previous.source_helpers.is_empty() {
        let mut unit = previous.clone();
        unit.debug_origins = debug;
        return Some(unit);
    }
    bodies
        .with_parsed(body, |parsed| {
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
                if stored.owner != previous.identity || stored.argument as usize != issued.argument
                {
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
                    .helper_source_recipe(stored.argument)?;
                    let (issued, current) = recipe
                        .reissue(parsed, frontend, host, symbols, &debug)?
                        .into_current_capture();
                    if issued != *reference
                        || code.modified_instances.insert(issued, current).is_some()
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
                unit.source_helpers.push(
                    crate::argument_sources::rebase_cached_helper(context, stored.argument, code)
                        .ok()?,
                );
            }
            unit.debug_origins = debug.clone();
            Some(unit)
        })
        .ok()
        .flatten()
}

#[cfg(test)]
#[path = "rich_sidecar_tests.rs"]
mod tests;

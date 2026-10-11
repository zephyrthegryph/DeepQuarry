//! Compatibility adapter for explicitly constructed memos without typed stores.
//! Production one-shot and retained factories both use shared per-write fragments
//! and assemblies. This wrapper preserves existing standalone callers/tests.
use super::*;
#[allow(clippy::too_many_arguments)]
pub(super) fn lower<'a, R: Resolver>(
    memo: &crate::lowering_memo::ProcedureMemo,
    classified: &ClassifiedInitializers,
    group: &initializer_policy::RuntimeGroup,
    host: &R,
    resource_search_context: Option<u128>,
    debug: &DebugOrigins,
    write_ordinals: &[usize],
    assignment_views: &[dm_codegen_byond::initializer::AssignmentView<'_>],
    value_continuations: Vec<Option<dm_codegen_byond::initializer::ValueContinuation<'_>>>,
    context: impl Fn() -> dm_codegen_byond::initializer::InitializerContext<'a>,
    map_error: &dyn Fn(dm_codegen_byond::initializer::InitializerError) -> InitializerLoweringError,
) -> Result<dm_codegen_byond::lower_resolver::ResolverProc, InitializerLoweringError> {
    let key = key(
        memo.policy,
        classified,
        group,
        resource_search_context,
        debug,
    )?;
    // Stored reads (including mandatory ancestry/override facts) are
    // validated by the lookup. A hit does not build a second recorder.
    let selected = memo.verification.select();
    let replay = memo.lookup_anonymous_verified(&key, host, debug.entries.len(), selected);
    if selected && (replay.code.is_some() || replay.errors.is_some()) {
        verify_hit(memo, &replay, classified, group, context(), host, map_error)?;
    }
    if let Some(errors) = replay.errors {
        if errors.iter().all(|error| {
            error
                .span
                .is_none_or(|span| span.start <= span.end && span.end < write_ordinals.len())
        }) {
            if selected {
                memo.counts
                    .disk_hits
                    .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
            }
            return Err(map_error(
                dm_codegen_byond::initializer::InitializerError::Lowering(errors),
            ));
        }
    }
    if let Some(code) = replay.code {
        if selected {
            memo.counts
                .disk_hits
                .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        }
        Ok(code)
    } else {
        let recorder = crate::lowering_memo::RecordingResolver::new(host);
        for &write_index in &group.writes {
            let write = classified
                .writes
                .get(write_index)
                .ok_or("initializer group write missing")?;
            recorder.resolve(dm_ir::ResolveQuery::Ancestry(write.write.lexical_owner));
            if let Some(identity) = write.write.lexical_procedure {
                recorder.record_occurrence(identity);
            }
        }
        let code = dm_codegen_byond::initializer::lower_with_value_continuations(
            &assignment_views,
            context(),
            &recorder,
            value_continuations.clone(),
        )
        .map_err(|error| {
            if let dm_codegen_byond::initializer::InitializerError::Lowering(errors) = &error {
                if errors.iter().all(|error| {
                    error.span.is_none_or(|span| {
                        span.start <= span.end && span.end < write_ordinals.len()
                    })
                }) {
                    memo.remember_failure(
                        &key,
                        None,
                        &recorder.reads(),
                        errors,
                        &recorder.domain_receipts(),
                    );
                }
            }
            map_error(error)
        })?;
        memo.remember_executable(&key, &recorder.reads(), &code, &recorder.domain_receipts());
        Ok(code)
    }
}

fn verify_hit<R: Resolver>(
    memo: &crate::lowering_memo::ProcedureMemo,
    old: &crate::lowering_memo_wire::AnonymousLookup,
    classified: &ClassifiedInitializers,
    group: &initializer_policy::RuntimeGroup,
    context: dm_codegen_byond::initializer::InitializerContext<'_>,
    host: &R,
    map_error: &dyn Fn(dm_codegen_byond::initializer::InitializerError) -> InitializerLoweringError,
) -> Result<(), InitializerLoweringError> {
    use std::sync::atomic::Ordering;
    memo.verification
        .anonymous_initializer_checked
        .fetch_add(1, Ordering::Relaxed);
    let recorder = crate::lowering_memo::RecordingResolver::new(host);
    for &index in &group.writes {
        let write = &classified.writes[index].write;
        recorder.resolve(dm_ir::ResolveQuery::Ancestry(write.lexical_owner));
        if let Some(identity) = write.lexical_procedure {
            recorder.record_occurrence(identity);
        }
    }
    let fresh = fragments::verify::assembly(classified, group, context, &recorder);
    let actual_reads = recorder.reads();
    let current_ledger = fragments::verify::canonical_ledger(
        actual_reads
            .iter()
            .map(|read| (read.query, read.domain, read.answer.canonical_bytes())),
    );
    let old_ledger = old.verification_reads.as_ref().and_then(|reads| {
        fragments::verify::canonical_ledger(
            reads
                .iter()
                .map(|(query, answer)| (*query, query.domain(), answer.clone())),
        )
    });
    let category = if old_ledger.is_none() || old_ledger != current_ledger {
        Some("complete canonical read ledger")
    } else {
        match (&old.code, &old.errors, fresh) {
            (Some(old), None, Ok(fresh))
                if crate::lowering_memo_wire::verification_code_equal(old, &fresh) =>
            {
                None
            }
            (Some(_), None, Ok(_)) => Some("semantic initializer output"),
            (None, Some(old), Err(fresh)) => {
                // Both rosters project through the SAME exact current source-sidecar mapper.
                let old = map_error(dm_codegen_byond::initializer::InitializerError::Lowering(
                    old.clone(),
                ));
                let fresh = map_error(fresh);
                match (old, fresh) {
                    (
                        InitializerLoweringError::Diagnostics(old),
                        InitializerLoweringError::Diagnostics(fresh),
                    ) if crate::initializer_diagnostics::verification_diagnostics_equal(
                        &old, &fresh,
                    ) =>
                    {
                        None
                    }
                    _ => Some("current-bound initializer diagnostics"),
                }
            }
            (None, Some(_), Ok(_)) => Some("cached failure became current success"),
            (Some(_), None, Err(_)) => Some("cached success became current rejection"),
            _ => Some("anonymous initializer result kind"),
        }
    };
    match category {
        None => Ok(()),
        Some(category) => {
            memo.verification
                .anonymous_initializer_mismatches
                .fetch_add(1, Ordering::Relaxed);
            Err(InitializerLoweringError::Invariant(format!(
                "anonymous initializer verification mismatch: {category}"
            )))
        }
    }
}

fn key(
    policy: u128,
    classified: &ClassifiedInitializers,
    group: &initializer_policy::RuntimeGroup,
    resource_search_context: Option<u128>,
    debug: &DebugOrigins,
) -> Result<Vec<u8>, InitializerLoweringError> {
    let mut key = b"dmbc-anonymous-declaration-v3-sized-continuations\0".to_vec();
    key.extend_from_slice(&policy.to_le_bytes());
    key.extend_from_slice(
        &serde_json::to_vec(&resource_search_context).map_err(|error| error.to_string())?,
    );
    for &write_index in &group.writes {
        let write = classified
            .writes
            .get(write_index)
            .ok_or("initializer group write missing")?;
        let bytes = write.write.canonical_bytes();
        key.extend_from_slice(&(bytes.len() as u64).to_le_bytes());
        key.extend_from_slice(&bytes);
        match write
            .runtime_value
            .as_ref()
            .ok_or("initializer runtime value missing")?
        {
            RuntimeValue::Expression(_) => key.push(0),
            RuntimeValue::SizedArray(dimensions)
            | RuntimeValue::SizedArrayExplicit { dimensions, .. } => {
                key.push(
                    if matches!(
                        write.runtime_value,
                        Some(RuntimeValue::SizedArrayExplicit { .. })
                    ) {
                        2
                    } else {
                        1
                    },
                );
                key.extend_from_slice(&(dimensions.len() as u64).to_le_bytes());
                for dimension in dimensions.iter() {
                    key.extend_from_slice(&dimension.to_le_bytes());
                }
            }
        }
    }
    for origin in &debug.entries {
        key.extend_from_slice(&(origin.semantic_path.len() as u64).to_le_bytes());
        key.extend_from_slice(origin.semantic_path.as_bytes());
    }
    Ok(key)
}

#[cfg(test)]
#[path = "initializer_anonymous_tests.rs"]
mod tests;

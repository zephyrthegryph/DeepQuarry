//! Shared initializer verification comparisons; ordinary exact admission remains mandatory.
use super::*;
use std::collections::BTreeMap;
pub(crate) type Receipt = dm_session::Receipt<receipts::Query, receipts::Answer, receipts::Domain>;
fn ledger(
    reads: impl IntoIterator<
        Item = dm_session::Observation<receipts::Query, receipts::Answer, receipts::Domain>,
    >,
) -> Option<BTreeMap<receipts::Query, (receipts::Domain, Vec<u8>)>> {
    canonical_ledger(reads.into_iter().filter_map(|read| match read.answer {
        receipts::Answer::Input(_) => None,
        receipts::Answer::Semantic(answer) => {
            Some((read.query, read.domain, answer.canonical_bytes()))
        }
    }))
}
/// Exact query/domain/answer comparison shared by typed and anonymous initializer hits.
pub(crate) fn canonical_ledger<Q: Ord, D: Eq + Clone>(
    reads: impl IntoIterator<Item = (Q, D, Vec<u8>)>,
) -> Option<BTreeMap<Q, (D, Vec<u8>)>> {
    let mut result = BTreeMap::new();
    for (query, domain, answer) in reads {
        let answer = (domain, answer);
        if result
            .insert(query, answer.clone())
            .is_some_and(|old| old != answer)
        {
            return None;
        }
    }
    Some(result)
}
pub(in crate::initializer_lowering) fn same_reads(
    key: &receipts::Binding,
    old: &Receipt,
    fresh: Vec<dm_session::Observation<receipts::Query, receipts::Answer, receipts::Domain>>,
) -> bool {
    let mut input = false;
    for read in old.iter() {
        if let receipts::Query::Input = read.query {
            match &read.answer {
                receipts::Answer::Input(answer)
                    if answer.as_ref() == key.inputs.as_ref()
                        && read.domain == receipts::Domain::Input =>
                {
                    input = true
                }
                _ => return false,
            }
        } else if !matches!(read.answer, receipts::Answer::Semantic(_)) {
            return false;
        }
    }
    input
        && match (ledger(old.iter().cloned()), ledger(fresh)) {
            (Some(old), Some(fresh)) => old == fresh,
            _ => false,
        }
}
#[allow(clippy::too_many_arguments)]
pub(super) fn fragment<R: Resolver>(
    key: &receipts::Binding,
    prepared: &PreparedAssignmentGroup<'_>,
    index: usize,
    write: &dm_ir::InitializerWrite,
    host: &R,
    old_reads: &Receipt,
    old: &AssignmentFragment,
) -> Result<(), InitializerError> {
    let recorder = crate::lowering_memo::RecordingResolver::new(host);
    recorder.resolve(dm_ir::ResolveQuery::Ancestry(write.lexical_owner));
    if let Some(identity) = write.lexical_procedure {
        recorder.record_occurrence(identity);
    }
    let fresh = prepared.try_lower_fragment(index, &recorder);
    let reads = receipts::reads(key, recorder.reads());
    let fresh = fresh.and_then(|fragment| {
        fragment
            .map(|value| value.code().clone())
            .ok_or_else(|| InitializerError::Unsupported("fresh fragment unavailable".into()))
    });
    code(
        key,
        old_reads,
        old.code(),
        fresh,
        reads,
        "assignment fragment",
    )
}

pub(crate) fn code(
    key: &receipts::Binding,
    old_reads: &Receipt,
    old: &dm_codegen_byond::lower_resolver::ResolverProc,
    fresh: Result<dm_codegen_byond::lower_resolver::ResolverProc, InitializerError>,
    reads: Vec<dm_session::Observation<receipts::Query, receipts::Answer, receipts::Domain>>,
    stage: &str,
) -> Result<(), InitializerError> {
    let category = if !same_reads(key, old_reads, reads) {
        Some("complete canonical read ledger")
    } else {
        match fresh {
            Ok(fresh) if crate::lowering_memo_wire::verification_code_equal(old, &fresh) => None,
            Ok(_) => Some("semantic fragment output"),
            Err(_) => Some("fresh producer rejected this initializer"),
        }
    };
    match category {
        None => Ok(()),
        Some(category) => Err(InitializerError::Invalid(format!(
            "initializer {stage} verification mismatch: {category}"
        ))),
    }
}

/// Same complete assembly producer, with current views created only for a selected hit.
pub(in crate::initializer_lowering) fn assembly<R: Resolver>(
    classified: &crate::initializer_policy::ClassifiedInitializers,
    group: &crate::initializer_policy::RuntimeGroup,
    context: dm_codegen_byond::initializer::InitializerContext<'_>,
    host: &R,
) -> Result<dm_codegen_byond::lower_resolver::ResolverProc, InitializerError> {
    let values = group
        .writes
        .iter()
        .map(|&index| {
            let write = classified.writes.get(index).ok_or_else(|| {
                InitializerError::Invalid("current assembly write missing".into())
            })?;
            let value = write.runtime_value.as_ref().ok_or_else(|| {
                InitializerError::Invalid("current assembly runtime value missing".into())
            })?;
            Ok(super::super::value_expression(value))
        })
        .collect::<Result<Vec<_>, InitializerError>>()?;
    let views = group
        .writes
        .iter()
        .enumerate()
        .map(|(index, &write_index)| {
            let write = &classified.writes[write_index].write;
            dm_codegen_byond::initializer::AssignmentView {
                source_site: write.source_site,
                target: &write.target,
                lexical_owner: write.lexical_owner,
                value: values[index].as_ref(),
                occurrence: dm_syntax::Span::new(index, index),
            }
        })
        .collect::<Vec<_>>();
    let continuations = group
        .writes
        .iter()
        .map(|&index| {
            super::super::value_continuation(&classified.writes[index], group.receiver.is_none())
        })
        .collect();
    dm_codegen_byond::initializer::lower_with_value_continuations(
        &views,
        context,
        host,
        continuations,
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn omitted_negative_answer_and_changed_answer_are_not_equivalent() {
        let query = receipts::Query::Semantic(dm_ir::ResolveQuery::GlobalProc(
            dm_ir::SymbolId::of("missing"),
        ));
        let read = |answer| dm_session::Observation {
            query: query.clone(),
            answer: receipts::Answer::Semantic(answer),
            domain: receipts::Domain::Semantic(dm_ir::ReadDomain::Tree),
        };
        let negative = ledger([read(dm_ir::ResolvedMeaning::Missing)]).unwrap();
        assert_ne!(negative, ledger([]).unwrap());
        assert_ne!(
            negative,
            ledger([read(dm_ir::ResolvedMeaning::Presence(true))]).unwrap()
        );
        assert!(ledger([
            read(dm_ir::ResolvedMeaning::Missing),
            read(dm_ir::ResolvedMeaning::Presence(true))
        ])
        .is_none());
    }
}

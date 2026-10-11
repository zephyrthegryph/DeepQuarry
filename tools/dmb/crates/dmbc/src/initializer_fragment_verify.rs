//! Fragment-only missing-read verification. Assemblies and modified fragments
//! are not covered here; ordinary exact admission remains mandatory everywhere.
use super::*;
use std::collections::BTreeMap;
type Receipt = dm_session::Receipt<receipts::Query, receipts::Answer, receipts::Domain>;
fn ledger(
    reads: impl IntoIterator<
        Item = dm_session::Observation<receipts::Query, receipts::Answer, receipts::Domain>,
    >,
) -> Option<BTreeMap<receipts::Query, (receipts::Domain, Vec<u8>)>> {
    let mut result = BTreeMap::new();
    for read in reads {
        let answer = match read.answer {
            // Input authority is checked separately with full Eq, never encoded hash identity.
            receipts::Answer::Input(_) => continue,
            receipts::Answer::Semantic(answer) => answer.canonical_bytes(),
        };
        let answer = (read.domain, answer);
        if result
            .insert(read.query, answer.clone())
            .is_some_and(|old| old != answer)
        {
            return None;
        }
    }
    Some(result)
}
fn same_reads(
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
    let category = if !same_reads(key, old_reads, reads) {
        Some("complete canonical read ledger")
    } else {
        match fresh {
            Ok(Some(fresh))
                if old.modified_references() == fresh.modified_references()
                    && crate::lowering_memo_wire::verification_code_equal(
                        old.code(),
                        fresh.code(),
                    ) =>
            {
                None
            }
            Ok(Some(_)) => Some("semantic fragment output"),
            Ok(None) => Some("fresh producer no longer supports this fragment"),
            Err(_) => Some("fresh producer rejected this fragment"),
        }
    };
    match category {
        None => Ok(()),
        Some(category) => Err(InitializerError::Invalid(format!(
            "initializer fragment verification mismatch: {category}; target={:?}",
            write.target
        ))),
    }
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

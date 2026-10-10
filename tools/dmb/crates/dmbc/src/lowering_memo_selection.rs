//! Query-only disk result; no executable IR or process-local source issuer.
use crate::lowering_memo::ResolverRead;
use crate::lowering_memo_compact::BoundedVec;
use crate::lowering_memo_wire::read_wire::ReadWire;
use dm_ir::{ProcedureIdentity, ReadDomain, ResolveQuery, Resolver, SelectedMeaning, SymbolId};
use serde::{Deserialize, Serialize};
use std::borrow::Cow;
pub(crate) const SCHEMA: u32 = 0x0206_0008;
const LIMIT: usize = 8 * 1024 * 1024;
#[derive(Serialize, Deserialize)]
struct Reference {
    path: BoundedVec<(u8, usize)>,
    span: Option<(usize, usize)>,
    name: SymbolId,
    meaning: SelectedMeaning,
}
#[derive(Serialize, Deserialize)]
pub(crate) struct Payload<'a> {
    #[serde(borrow)]
    key: Cow<'a, [u8]>,
    identity: ProcedureIdentity,
    #[serde(borrow)]
    abi: Cow<'a, [u8]>,
    #[serde(borrow)]
    reads: BoundedVec<ReadWire<'a>>,
    versions: BoundedVec<(ReadDomain, u128)>,
    references: BoundedVec<Reference>,
    unbound: usize,
}
pub(crate) fn encode(
    key: &[u8],
    reads: &[ResolverRead],
    versions: &[(ReadDomain, u128)],
    unit: &crate::lowering::LoweredUnit,
) -> Option<Vec<u8>> {
    let facts = unit.selected_references.as_ref()?;
    if facts.complete {
        return None;
    }
    let abi = unit.abi.as_ref()?;
    let identity = unit.identity;
    let value = Payload {
        key: Cow::Borrowed(key),
        identity: ProcedureIdentity {
            owner: identity.owner,
            name: identity.name,
            verb: identity.namespace == crate::lowering::Namespace::Verb,
            occurrence: identity.occurrence,
        },
        abi: Cow::Owned(abi.canonical_bytes()),
        reads: BoundedVec(
            reads
                .iter()
                .map(|r| ReadWire {
                    query: r.query,
                    answer: Cow::Owned(r.answer.canonical_bytes()),
                })
                .collect(),
        ),
        versions: BoundedVec(
            versions
                .iter()
                .copied()
                .filter(|(d, _)| d.persistent_version())
                .collect(),
        ),
        references: BoundedVec(
            facts
                .references
                .iter()
                .map(|r| Reference {
                    path: BoundedVec(
                        r.path
                            .iter()
                            .map(|step| match *step {
                                dm_syntax::NodeStep::Statement(i) => (0, i),
                                dm_syntax::NodeStep::Branch(i) => (1, i),
                                dm_syntax::NodeStep::Expression(i) => (2, i),
                                dm_syntax::NodeStep::Child(i) => (3, i),
                            })
                            .collect(),
                    ),
                    span: r.relative_span,
                    name: r.name,
                    meaning: r.meaning.clone(),
                })
                .collect(),
        ),
        unbound: facts.unbound_selections,
    };
    dm_wire::encode_bounded(SCHEMA, &value, LIMIT).ok()
}
pub(crate) fn decode(bytes: &[u8]) -> Result<Payload<'_>, String> {
    let value: Payload<'_> = dm_wire::decode_borrowed(SCHEMA, bytes, LIMIT)?;
    crate::lowering_memo_wire::validate_versions(&value.versions.0)?;
    if !value.references.0.iter().all(|r| {
        r.path.0.first().is_some_and(|(tag, _)| *tag == 0)
            && r.path.0.iter().all(|(tag, _)| *tag <= 3)
            && r.meaning.structurally_valid()
            && r.span.is_none_or(|(start, end)| start <= end)
    }) {
        return Err("malformed selected coordinate/meaning".into());
    }
    Ok(value)
}
impl Payload<'_> {
    pub(crate) fn promotion(&self) -> crate::lowering_memo_wire::ResidentPromotion {
        crate::lowering_memo_wire::ResidentPromotion {
            queries: self.reads.0.iter().map(|read| read.query).collect(),
            versions: self.versions.0.clone(),
            relative_debug: Vec::new(),
        }
    }
    pub(crate) fn matches(&self, key: &[u8], identity: ProcedureIdentity) -> bool {
        self.key.as_ref() == key && self.identity == identity
    }
    pub(crate) fn changed_read<R: Resolver>(&self, host: &R) -> Option<ResolveQuery> {
        let matching = crate::lowering_memo::matching_domains(&self.versions.0, host);
        self.reads.0.iter().find_map(|r| {
            (!matching.contains(&r.query.domain())
                && host.resolve(r.query).canonical_bytes() != r.answer.as_ref())
            .then_some(r.query)
        })
    }
    pub(crate) fn bind(
        self,
        context: crate::lowering_memo_wire::ProcedureReplayContext<'_>,
        prepared: &crate::procedure_policy::PreparedUnit,
    ) -> Option<std::sync::Arc<dm_ir::SelectedReferences>> {
        if !context.selections_only
            || prepared.require_production_abi().is_err()
            || self.abi.as_ref() != prepared.abi.as_ref()?.canonical_bytes()
        {
            return None;
        }
        let current = crate::lowering::source_unit_identity(context.frontend, context.body)
            .ok()?
            .identity;
        if current.owner != self.identity.owner
            || current.name != self.identity.name
            || current.occurrence != self.identity.occurrence
            || (current.namespace == crate::lowering::Namespace::Verb) != self.identity.verb
        {
            return None;
        }
        let len = context
            .body
            .expanded_span
            .end
            .checked_sub(context.body.expanded_span.start)?;
        let mut references = Vec::with_capacity(self.references.0.len());
        for r in self.references.0 {
            if let Some((start, end)) = r.span {
                if start > end
                    || end > len
                    || context
                        .frontend
                        .location(context.body.expanded_span.start.checked_add(start)?)
                        .is_none()
                {
                    return None;
                }
            }
            references.push(dm_ir::SelectedReference {
                path: r
                    .path
                    .0
                    .into_iter()
                    .map(|(tag, i)| match tag {
                        0 => dm_syntax::NodeStep::Statement(i),
                        1 => dm_syntax::NodeStep::Branch(i),
                        2 => dm_syntax::NodeStep::Expression(i),
                        3 => dm_syntax::NodeStep::Child(i),
                        _ => unreachable!("validated tag"),
                    })
                    .collect(),
                relative_span: r.span,
                name: r.name,
                meaning: r.meaning,
            });
        }
        Some(std::sync::Arc::new(dm_ir::SelectedReferences {
            references,
            complete: false,
            unbound_selections: self.unbound,
        }))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn payload() -> Payload<'static> {
        Payload {
            key: Cow::Borrowed(b"exact"),
            identity: ProcedureIdentity {
                owner: SymbolId::of("/"),
                name: SymbolId::of("p"),
                verb: false,
                occurrence: 0,
            },
            abi: Cow::Borrowed(b"abi"),
            reads: BoundedVec(Vec::new()),
            versions: BoundedVec(Vec::new()),
            references: BoundedVec(vec![Reference {
                path: BoundedVec(vec![(0, 0), (2, 0)]),
                span: Some((0, 1)),
                name: SymbolId::of("x"),
                meaning: SelectedMeaning::Argument(0),
            }]),
            unbound: 0,
        }
    }
    #[test]
    fn selected_wire_is_bounded_and_rejects_corrupt_coordinate_structure() {
        let bytes = dm_wire::encode_bounded(SCHEMA, &payload(), LIMIT).unwrap();
        assert!(decode(&bytes).is_ok());
        let mut bad = payload();
        bad.references.0[0].path.0[0].0 = 4;
        assert!(decode(&dm_wire::encode_bounded(SCHEMA, &bad, LIMIT).unwrap()).is_err());
        let mut bad = payload();
        bad.references.0[0].span = Some((2, 1));
        assert!(decode(&dm_wire::encode_bounded(SCHEMA, &bad, LIMIT).unwrap()).is_err());
        let mut bad = bytes;
        *bad.last_mut().unwrap() ^= 1;
        assert!(decode(&bad).is_err());
    }
    #[test]
    fn selected_wire_replays_exact_negative_read_answers() {
        struct Host(bool);
        impl Resolver for Host {
            fn resolve(&self, _: ResolveQuery) -> dm_ir::ResolvedMeaning {
                if self.0 {
                    dm_ir::ResolvedMeaning::Symbol(SymbolId::of("defined"))
                } else {
                    dm_ir::ResolvedMeaning::Missing
                }
            }
        }
        let query = ResolveQuery::GlobalVar(SymbolId::of("absent"));
        let mut value = payload();
        value.reads = BoundedVec(vec![ReadWire {
            query,
            answer: Cow::Owned(Host(false).resolve(query).canonical_bytes()),
        }]);
        let bytes = dm_wire::encode_bounded(SCHEMA, &value, LIMIT).unwrap();
        let decoded = decode(&bytes).unwrap();
        assert!(decoded.changed_read(&Host(false)).is_none());
        assert_eq!(decoded.changed_read(&Host(true)), Some(query));
    }
}

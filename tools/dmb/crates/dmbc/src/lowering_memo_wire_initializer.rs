//! Initializer payload adapter on the existing CodeWire and canonical read codec.
//! Whole buckets are typed/recertified before any current semantic callback.
use super::{CodeWire, ResolverProc};
use dm_codegen_byond::initializer::AssignmentFragment;
use dm_ir::{ResolveQuery, ResolvedMeaning, Resolver};
use serde::{Deserialize, Serialize};
const SCHEMA: u32 = 0x0206_0018;
pub(crate) const LIMIT: usize = 8 * 1024 * 1024;
#[derive(Serialize, Deserialize)]
struct Payload {
    recipe: Vec<u8>,
    assembly: bool,
    roots: usize,
    mandatory: Vec<ResolveQuery>,
    reads: Vec<(ResolveQuery, Vec<u8>)>,
    code: CodeWire,
}
pub(crate) struct Candidate {
    pub recipe: Vec<u8>,
    pub assembly: bool,
    pub roots: usize,
    pub mandatory: Vec<ResolveQuery>,
    pub reads: Vec<(ResolveQuery, Vec<u8>)>,
    pub code: ResolverProc,
}
struct NoReads;
impl Resolver for NoReads {
    fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
        // Source-neutral hydration has no descriptor factories/semantic callbacks.
        ResolvedMeaning::Unsupported(query)
    }
}
pub(crate) fn portable(value: &ResolvedMeaning) -> bool {
    match value {
        ResolvedMeaning::Unsupported(_) | ResolvedMeaning::RetainedProc { .. } => false,
        ResolvedMeaning::Members(values) => values.iter().all(portable),
        _ => true,
    }
}
fn valid_reads(reads: &[(ResolveQuery, Vec<u8>)], required: &[ResolveQuery]) -> bool {
    let canonical = crate::initializer_lowering::verification::canonical_ledger(
        reads.iter().map(|(q, a)| (*q, q.domain(), a.clone())),
    );
    canonical.is_some()
        && !reads.iter().any(|(q, _)| {
            matches!(
                q,
                ResolveQuery::Resource(_) | ResolveQuery::ResourceIn { .. }
            )
        })
        && required
            .iter()
            .all(|q| reads.iter().any(|(old, a)| old == q && !a.is_empty()))
}
pub(crate) fn encode(
    recipe: Vec<u8>,
    assembly: bool,
    roots: usize,
    mandatory: Vec<ResolveQuery>,
    reads: &[dm_session::ResolverRead],
    code: &ResolverProc,
) -> Option<Vec<u8>> {
    if reads.iter().any(|r| {
        !portable(&r.answer)
            || matches!(
                r.query,
                ResolveQuery::Resource(_) | ResolveQuery::ResourceIn { .. }
            )
    }) {
        return None;
    }
    if assembly {
        AssignmentFragment::validate_assembly_transport(code, roots).ok()?;
    } else {
        AssignmentFragment::from_transport(code.clone()).ok()?;
    }
    let code = CodeWire::capture(code);
    if !code.source_neutral_initializer() {
        return None;
    }
    let reads = reads
        .iter()
        .map(|r| (r.query, r.answer.canonical_bytes()))
        .collect::<Vec<_>>();
    if !valid_reads(&reads, &mandatory) {
        return None;
    }
    dm_wire::encode_bounded(
        SCHEMA,
        &Payload {
            recipe,
            assembly,
            roots,
            mandatory,
            reads,
            code,
        },
        LIMIT,
    )
    .ok()
}
#[cfg(test)]
pub(crate) fn omit_mandatory(bytes: &[u8]) -> Vec<u8> {
    let mut payload: Payload = dm_wire::decode(SCHEMA, bytes, LIMIT).unwrap();
    payload.mandatory.clear();
    payload.reads.clear();
    dm_wire::encode(SCHEMA, &payload).unwrap()
}
pub(crate) fn decode_bucket(bytes: &[u8]) -> Result<Vec<Candidate>, String> {
    let rows = dm_cache::decode_variants(bytes)?;
    let payloads = rows
        .iter()
        .map(|row| dm_wire::decode::<Payload>(SCHEMA, row, LIMIT))
        .collect::<Result<Vec<_>, _>>()?;
    payloads
        .into_iter()
        .map(|p| {
            if p.recipe.is_empty()
                || !valid_reads(&p.reads, &p.mandatory)
                || !p.code.source_neutral_initializer()
                || (!p.assembly && p.roots != 1)
            {
                return Err("invalid initializer payload/receipt".into());
            }
            let code = p
                .code
                .rehydrate(&NoReads, p.roots)
                .ok_or("invalid initializer code descriptors")?;
            if p.assembly {
                AssignmentFragment::validate_assembly_transport(&code, p.roots)
                    .map_err(|e| format!("invalid initializer assembly: {e:?}"))?;
            } else {
                AssignmentFragment::from_transport(code.clone())
                    .map_err(|e| format!("invalid initializer fragment: {e:?}"))?;
            }
            Ok(Candidate {
                recipe: p.recipe,
                assembly: p.assembly,
                roots: p.roots,
                mandatory: p.mandatory,
                reads: p.reads,
                code,
            })
        })
        .collect()
}

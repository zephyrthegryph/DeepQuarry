//! Initializer payload adapter on the existing CodeWire and canonical read codec.
//! Whole buckets are typed/recertified before any current semantic callback.
use super::{CodeWire, ResolverProc};
use dm_codegen_byond::initializer::AssignmentFragment;
use dm_ir::{ResolveQuery, ResolvedMeaning, Resolver};
use serde::{Deserialize, Serialize};
const SCHEMA: u32 = 0x0206_0020;
pub(crate) const LIMIT: usize = 8 * 1024 * 1024;
#[derive(Serialize, Deserialize)]
struct Payload {
    recipe: Vec<u8>,
    assembly: bool,
    modified_only: bool,
    roots: usize,
    mandatory: Vec<ResolveQuery>,
    reads: Vec<(ResolveQuery, Vec<u8>)>,
    code: CodeWire,
    modified: Vec<(usize, crate::modified_initializers::ExpressionEvidence)>,
}
pub(crate) struct Candidate {
    pub recipe: Vec<u8>,
    pub assembly: bool,
    pub modified_only: bool,
    pub roots: usize,
    pub mandatory: Vec<ResolveQuery>,
    pub reads: Vec<(ResolveQuery, Vec<u8>)>,
    pub code: ResolverProc,
    pub modified: Vec<(usize, crate::modified_initializers::ExpressionRecipe)>,
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
        && required.iter().all(|q| {
            reads.iter().any(|(old, a)| {
                old == q
                    && !a.is_empty()
                    && match q {
                        ResolveQuery::RuntimeType(path) => {
                            *a == ResolvedMeaning::Symbol(*path).canonical_bytes()
                        }
                        _ => true,
                    }
            })
        })
}
#[cfg(test)]
pub(crate) fn encode(
    recipe: Vec<u8>,
    assembly: bool,
    roots: usize,
    mandatory: Vec<ResolveQuery>,
    reads: &[dm_session::ResolverRead],
    code: &ResolverProc,
) -> Option<Vec<u8>> {
    encode_with_modified(recipe, assembly, roots, mandatory, reads, code, Vec::new())
}
pub(crate) fn encode_with_modified(
    recipe: Vec<u8>,
    assembly: bool,
    roots: usize,
    mandatory: Vec<ResolveQuery>,
    reads: &[dm_session::ResolverRead],
    code: &ResolverProc,
    modified: Vec<(usize, crate::modified_initializers::ExpressionEvidence)>,
) -> Option<Vec<u8>> {
    encode_current_program(
        recipe, assembly, roots, mandatory, reads, code, modified, false,
    )
}
pub(crate) fn encode_current_program(
    recipe: Vec<u8>,
    assembly: bool,
    roots: usize,
    mandatory: Vec<ResolveQuery>,
    reads: &[dm_session::ResolverRead],
    code: &ResolverProc,
    modified: Vec<(usize, crate::modified_initializers::ExpressionEvidence)>,
    modified_only: bool,
) -> Option<Vec<u8>> {
    if modified_only && (!assembly || roots == 0) {
        return None;
    }
    let debug_count = roots.checked_add(usize::from(modified_only))?;
    if reads.iter().any(|r| {
        !portable(&r.answer)
            || matches!(
                r.query,
                ResolveQuery::Resource(_) | ResolveQuery::ResourceIn { .. }
            )
    }) {
        return None;
    }
    let references = modified
        .iter()
        .map(|(_, r)| r.reference())
        .collect::<Vec<_>>();
    if modified.iter().any(|(index, r)| {
        *index >= roots
            || r.origin() as usize != index.saturating_add(usize::from(modified_only))
            || r.resident_recipe().is_none()
    }) {
        return None;
    }
    if code.instances.iter().any(|(alias, instance)| {
        !modified.iter().any(|(_, r)| {
            r.reference() == dm_ir::SymRef::Instance(*alias)
                && r.runtime_type() == instance.runtime_type
        })
    }) {
        return None;
    }
    if assembly {
        AssignmentFragment::validate_assembly_transport_with_references(
            code,
            debug_count,
            references,
        )
        .ok()?;
    } else {
        AssignmentFragment::from_transport_with_references(code.clone(), references).ok()?;
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
            modified_only,
            roots,
            mandatory,
            reads,
            code,
            modified,
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
#[cfg(test)]
pub(crate) fn corrupt_modified_roster(bytes: &[u8], duplicate: bool) -> Vec<u8> {
    let mut payload: Payload = dm_wire::decode(SCHEMA, bytes, LIMIT).unwrap();
    if duplicate {
        payload.modified.push(payload.modified[0].clone());
    } else {
        payload.modified.clear();
    }
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
            if (p.modified_only && (!p.assembly || p.roots == 0))
                || p.recipe.is_empty()
                || !valid_reads(&p.reads, &p.mandatory)
                || !p.code.source_neutral_initializer()
                || (!p.assembly && p.roots != 1)
            {
                return Err("invalid initializer payload/receipt".into());
            }
            let debug_count = p
                .roots
                .checked_add(usize::from(p.modified_only))
                .ok_or("initializer debug count overflow")?;
            let code = p
                .code
                .rehydrate(&NoReads, debug_count)
                .ok_or("invalid initializer code descriptors")?;
            if code.instances.iter().any(|(alias, instance)| {
                !p.modified.iter().any(|(_, r)| {
                    r.reference() == dm_ir::SymRef::Instance(*alias)
                        && r.runtime_type() == instance.runtime_type
                })
            }) {
                return Err("modified runtime type table differs from recipe evidence".into());
            }
            let modified = p
                .modified
                .into_iter()
                .map(|(index, evidence)| {
                    if index >= p.roots
                        || evidence.origin() as usize
                            != index.saturating_add(usize::from(p.modified_only))
                    {
                        return Err("invalid modified assignment origin".to_string());
                    }
                    evidence
                        .resident_recipe()
                        .map(|recipe| (index, recipe))
                        .ok_or_else(|| "invalid modified expression evidence".to_string())
                })
                .collect::<Result<Vec<_>, _>>()?;
            let references = modified
                .iter()
                .map(|(_, r)| r.reference())
                .collect::<Vec<_>>();
            if p.assembly {
                AssignmentFragment::validate_assembly_transport_with_references(
                    &code,
                    debug_count,
                    references,
                )
                .map_err(|e| format!("invalid initializer assembly: {e:?}"))?;
            } else {
                AssignmentFragment::from_transport_with_references(code.clone(), references)
                    .map_err(|e| format!("invalid initializer fragment: {e:?}"))?;
            }
            Ok(Candidate {
                recipe: p.recipe,
                assembly: p.assembly,
                modified_only: p.modified_only,
                roots: p.roots,
                mandatory: p.mandatory,
                reads: p.reads,
                code,
                modified,
            })
        })
        .collect()
}

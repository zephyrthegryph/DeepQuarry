//! Per-unit programs in the existing map output store. Full canonical inputs,
//! exact current expression bytes and ordinary resolver receipts admit reuse.
use super::*;
use crate::debug_sources::{DebugOriginProvider, DebugOrigins};
use crate::map_initializers::Unit;
use crate::modified_initializers::ExpressionRecipe;
use dm_codegen_byond::lower_resolver::ResolverProc;
use dm_codegen_byond::DebugSourceProvider;
use dm_ir::{SymRef, SymbolTable};

// Unit admission feeds a surrounding bundle recorder. Replaying each accepted
// edge preserves that bundle's complete dependency ledger even with versions.
struct Replay<'a, R>(&'a R);
impl<R: Resolver> Resolver for Replay<'_, R> {
    fn resolve(&self, query: dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning {
        self.0.resolve(query)
    }
}

pub(crate) const PREFIX: &[u8] = b"dmbc-map-unit-resident-v1\0";
#[derive(Clone, Copy)]
pub(crate) enum Site {
    Entry,
    Value { assignment: usize, offset: usize },
}
impl Site {
    pub(crate) fn capture(unit: &Unit, entry: usize, offset: usize) -> Option<Self> {
        if offset == entry {
            return Some(Self::Entry);
        }
        let mut matches = unit
            .origins
            .iter()
            .enumerate()
            .filter_map(|(assignment, origin)| {
                let span = origin.span.value_span;
                (offset >= span.start && offset <= span.end).then_some(Self::Value {
                    assignment,
                    offset: offset.saturating_sub(span.start),
                })
            });
        let site = matches.next()?;
        matches.next().is_none().then_some(site)
    }
    fn bind(self, unit: &Unit, entry: usize) -> Option<usize> {
        match self {
            Self::Entry => Some(entry),
            Self::Value { assignment, offset } => {
                let span = unit.origins.get(assignment)?.span.value_span;
                (offset <= span.end.checked_sub(span.start)?)
                    .then(|| span.start.checked_add(offset))
                    .flatten()
            }
        }
    }
}
pub(in crate::map_memo) struct RetainedUnit {
    code: crate::InitializerCode,
    sites: Vec<Site>,
    recipes: Vec<ExpressionRecipe>,
    root_indexes: Vec<usize>,
    references: Vec<SymRef>,
}

impl MapMemo {
    pub(crate) fn map_unit_key(
        &self,
        unit: &Unit,
        maps: &[MapPlan],
        context: Option<u128>,
    ) -> Option<Arc<[u8]>> {
        let mut key = PREFIX.to_vec();
        key.extend_from_slice(&self.policy.to_le_bytes());
        key.push(u8::from(context.is_some()));
        if let Some(context) = context {
            key.extend_from_slice(&context.to_le_bytes());
        }
        frame(&mut key, &unit.canonical_bytes());
        if unit.assignments.len() != unit.origins.len() {
            return None;
        }
        for origin in unit.origins.iter() {
            let map = maps.get(origin.atom.map)?;
            let text = map.captured.source.get(origin.span.value_span.range())?;
            frame(&mut key, text.as_bytes());
        }
        Some(key.into())
    }
    pub(crate) fn map_unit<R: Resolver>(
        &self,
        key: &Arc<[u8]>,
        unit: &Unit,
        maps: &[MapPlan],
        entry: usize,
        origins: &(impl DebugOriginProvider + DebugSourceProvider),
        symbols: &SymbolTable,
        host: &R,
    ) -> Option<(crate::InitializerCode, Arc<DebugOrigins>)> {
        self.pending_maps.as_ref()?;
        self.current
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .outputs
            .push(key.clone());
        let hit = self
            .with_pending_maps(|leases| {
                leases
                    .outputs
                    .visit_explained(key, &Replay(host), &mut |value| {
                        matches!(value.as_ref(), MapOutputs::Unit(_))
                    })
                    .0
            })
            .flatten()?;
        let MapOutputs::Unit(value) = hit.as_ref() else {
            return None;
        };
        if value.recipes.len() != value.root_indexes.len() {
            return None;
        }
        // Recreate the ordinal sequence through the same current issuer before
        // attaching descriptors, whose field origins reference those ordinals.
        let mut debug = DebugOrigins::default();
        for (ordinal, site) in value.sites.iter().enumerate() {
            let offset = site.bind(unit, entry)?;
            if origins.ordinal(offset).ok()? as usize != ordinal {
                return None;
            }
            debug.entries.push(origins.origin(offset).ok()?);
        }
        let code = if value.recipes.is_empty() {
            value.code.clone()
        } else {
            let roots = crate::map_initializers::prepare_unit_expressions(unit, maps).ok()?;
            let recording = RecordingResolver::new(host);
            let captured = value
                .recipes
                .iter()
                .zip(&value.root_indexes)
                .map(|(recipe, index)| recipe.reissue(&roots.get(*index)?.2, &recording, symbols))
                .collect::<Option<std::collections::BTreeMap<_, _>>>()?;
            if captured
                .keys()
                .copied()
                .ne(value.references.iter().copied())
            {
                return None;
            }
            let mut code = value.code.as_ref().clone();
            code.modified_instances = captured;
            crate::InitializerCode::from_admitted(code, value.code.requests().clone())
        };
        self.counts.unit_hits.fetch_add(1, Ordering::Relaxed);
        Some((code, Arc::new(debug)))
    }
    pub(crate) fn remember_map_unit<R: Resolver>(
        &self,
        key: Arc<[u8]>,
        unit: &Unit,
        maps: &[MapPlan],
        code: &crate::InitializerCode,
        entry: usize,
        offsets: &[usize],
        recording: &RecordingResolver<'_, R>,
    ) {
        let Some(_) = &self.pending_maps else {
            return;
        };
        let Some(sites) = offsets
            .iter()
            .map(|offset| Site::capture(unit, entry, *offset))
            .collect::<Option<Vec<_>>>()
        else {
            return;
        };
        let mut recipes = Vec::new();
        let mut root_indexes = Vec::new();
        if !code.modified_instances.is_empty() {
            let Ok(roots) = crate::map_initializers::prepare_unit_expressions(unit, maps) else {
                return;
            };
            for (reference, captured) in &code.modified_instances {
                let mut matches = roots
                    .iter()
                    .enumerate()
                    .filter_map(|(index, (_, _, root))| {
                        ExpressionRecipe::from_capture(*reference, captured, root)
                            .map(|recipe| (index, recipe))
                    });
                let Some((index, recipe)) = matches.next() else {
                    return;
                };
                if matches.next().is_some() {
                    return;
                }
                root_indexes.push(index);
                recipes.push(recipe);
            }
        }
        let references = code.modified_instances.keys().copied().collect();
        let stripped = if code.modified_instances.is_empty() {
            code.clone()
        } else {
            let mut stripped: ResolverProc = code.as_ref().clone();
            stripped.modified_instances.clear();
            crate::InitializerCode::from_admitted(stripped, code.requests().clone())
        };
        let reads = recording.reads();
        let versions = recording.domain_receipts();
        let Some(weight) = crate::heap_census::resident_map_unit_weight(
            &stripped,
            &key,
            &reads,
            &versions,
            &recipes,
            &references,
            &sites,
            &root_indexes,
        ) else {
            return;
        };
        self.current
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .outputs
            .push(key.clone());
        self.with_pending_maps(|leases| {
            leases
                .outputs
                .insert_with(key, reads, versions, weight, || {
                    MapOutputs::Unit(RetainedUnit {
                        code: stripped,
                        sites,
                        recipes,
                        root_indexes,
                        references,
                    })
                })
        });
    }
}

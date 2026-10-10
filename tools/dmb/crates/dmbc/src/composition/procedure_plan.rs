//! Canonical emission rosters and independent deferred procedure metadata.
use super::*;
use crate::{lowering::UnitIdentity, symbolic::FrozenUnit};
use dm_codegen_byond::procedure_abi::ArgumentSource;
#[path = "metadata_roster.rs"]
mod metadata_roster;

#[derive(Clone, Default, PartialEq, Eq)]
pub(super) struct CompositionPlan {
    pub procedures: Vec<(u32, UnitIdentity)>,
    pub helpers: Vec<(u32, Key)>,
    pub initializers: Vec<(u32, dm_link::InitializerIdentity)>,
}
fn canonical<T>(rows: &mut Vec<(u32, T)>) {
    // Link assignments are visited in Key order. Preserve the old map's last
    // assignment at an aliased index, then traverse numeric table order.
    rows.sort_by_key(|row| row.0);
    rows.reverse();
    rows.dedup_by_key(|row| row.0);
    rows.reverse();
}
impl CompositionPlan {
    pub fn canonicalize(&mut self) {
        canonical(&mut self.procedures);
        canonical(&mut self.helpers);
        canonical(&mut self.initializers);
    }
    pub fn bind(self, batch: &FrozenBatch) -> BoundCompositionPlan {
        BoundCompositionPlan {
            counts: [
                self.procedures.len(),
                self.helpers.len(),
                self.initializers.len(),
            ],
            procedures: bind(
                self.procedures,
                batch
                    .units
                    .iter()
                    .enumerate()
                    .map(|(index, unit)| (unit.lowered.identity, index)),
                "duplicate procedure artifact",
            ),
            helpers: bind(
                self.helpers,
                batch.helpers.iter().enumerate().map(|(index, unit)| {
                    (
                        crate::symbolic::helper_key(unit.owner, unit.argument),
                        index,
                    )
                }),
                "duplicate helper artifact",
            ),
            initializers: bind(
                self.initializers,
                batch
                    .initializers
                    .iter()
                    .enumerate()
                    .map(|(index, unit)| (unit.identity, index)),
                "duplicate initializer artifact",
            ),
        }
    }
}
#[derive(Clone, Copy)]
pub(super) struct Slot<K> {
    pub table_index: u32,
    pub identity: K,
    pub artifact: Option<usize>,
}
pub(super) struct BoundCompositionPlan {
    pub counts: [usize; 3],
    pub procedures: Result<std::sync::Arc<Vec<Slot<UnitIdentity>>>, CompositionError>,
    pub helpers: Result<std::sync::Arc<Vec<Slot<Key>>>, CompositionError>,
    pub initializers:
        Result<std::sync::Arc<Vec<Slot<dm_link::InitializerIdentity>>>, CompositionError>,
}
fn bind<K: Ord + Copy>(
    rows: Vec<(u32, K)>,
    artifacts: impl Iterator<Item = (K, usize)>,
    duplicate: &str,
) -> Result<std::sync::Arc<Vec<Slot<K>>>, CompositionError> {
    let mut artifacts: Vec<_> = artifacts.collect();
    artifacts.sort_by_key(|row| row.0);
    if artifacts.windows(2).any(|pair| pair[0].0 == pair[1].0) {
        return Err(unsupported(duplicate));
    }
    Ok(std::sync::Arc::new(
        rows.into_iter()
            .map(|(table_index, identity)| Slot {
                table_index,
                identity,
                artifact: artifacts
                    .binary_search_by_key(&identity, |row| row.0)
                    .ok()
                    .map(|index| artifacts[index].1),
            })
            .collect(),
    ))
}

/// Private numeric projection, admitted against current shared assignments and
/// complete ordered artifact identities. No body, ABI or source proof is retained.
pub(super) struct CachedPlan {
    bindings: dm_link::BindingTables,
    raw: CompositionPlan,
    units: Vec<UnitIdentity>,
    helpers: Vec<Key>,
    initializers: Vec<dm_link::InitializerIdentity>,
    procedures: std::sync::Arc<Vec<Slot<UnitIdentity>>>,
    helper_rows: std::sync::Arc<Vec<Slot<Key>>>,
    initializer_rows: std::sync::Arc<Vec<Slot<dm_link::InitializerIdentity>>>,
    argument_sources: Option<(usize, std::sync::Arc<dm_link::ArgumentSourceReferences>)>,
    metadata: Option<metadata_roster::MetadataRoster>,
}
impl CachedPlan {
    pub(super) fn argument_sources(
        &mut self,
        tables: &dm_link::LinkTables,
        start: usize,
        order: &[Key],
    ) -> Result<std::sync::Arc<dm_link::ArgumentSourceReferences>, dm_link::LinkError> {
        let current = self.bindings.same_owner(&tables.binding_tables()) && self.helpers == order;
        if current {
            if let Some((previous_start, owner)) = &self.argument_sources {
                if *previous_start == start {
                    return Ok(std::sync::Arc::clone(owner));
                }
            }
        }
        let owner = std::sync::Arc::new(dm_link::ArgumentSourceReferences::assign(
            tables, start, order,
        )?);
        if current {
            self.argument_sources = Some((start, std::sync::Arc::clone(&owner)));
        }
        Ok(owner)
    }
    pub fn admit(
        &self,
        raw: &CompositionPlan,
        batch: &FrozenBatch,
    ) -> Option<BoundCompositionPlan> {
        if !self.bindings.same_owner(&batch.tables.binding_tables())
            || self.raw != *raw
            || !self
                .units
                .iter()
                .copied()
                .eq(batch.units.iter().map(|unit| unit.lowered.identity))
            || !self.helpers.iter().copied().eq(batch
                .helpers
                .iter()
                .map(|unit| crate::symbolic::helper_key(unit.owner, unit.argument)))
            || !self
                .initializers
                .iter()
                .copied()
                .eq(batch.initializers.iter().map(|unit| unit.identity))
        {
            return None;
        }
        Some(BoundCompositionPlan {
            counts: [
                self.procedures.len(),
                self.helper_rows.len(),
                self.initializer_rows.len(),
            ],
            procedures: Ok(std::sync::Arc::clone(&self.procedures)),
            helpers: Ok(std::sync::Arc::clone(&self.helper_rows)),
            initializers: Ok(std::sync::Arc::clone(&self.initializer_rows)),
        })
    }
    pub fn capture(
        raw: CompositionPlan,
        batch: &FrozenBatch,
        bound: &BoundCompositionPlan,
    ) -> Option<Self> {
        Some(Self {
            bindings: batch.tables.binding_tables(),
            raw,
            units: batch
                .units
                .iter()
                .map(|unit| unit.lowered.identity)
                .collect(),
            helpers: batch
                .helpers
                .iter()
                .map(|unit| crate::symbolic::helper_key(unit.owner, unit.argument))
                .collect(),
            initializers: batch
                .initializers
                .iter()
                .map(|unit| unit.identity)
                .collect(),
            procedures: std::sync::Arc::clone(bound.procedures.as_ref().ok()?),
            helper_rows: std::sync::Arc::clone(bound.helpers.as_ref().ok()?),
            initializer_rows: std::sync::Arc::clone(bound.initializers.as_ref().ok()?),
            argument_sources: None,
            metadata: None,
        })
    }
    pub(super) fn prepare_metadata(
        &mut self,
        slots: &[Slot<UnitIdentity>],
        batch: &FrozenBatch,
        projection: Option<&crate::class_projection::ClassProjection>,
        symbols: &SymbolTable,
        references: &std::sync::Arc<dm_link::ArgumentSourceReferences>,
        executor: Option<&dm_exec::BuildExecutor>,
    ) -> Vec<Result<PreparedMetadata, CompositionError>> {
        let admitted = self
            .metadata
            .as_ref()
            .and_then(|owner| owner.admit(slots, batch, projection, symbols, references));
        if let Some(rows) = &admitted {
            if rows.iter().all(Option::is_some) {
                let prepared = rows
                    .iter()
                    .map(|row| {
                        Ok(PreparedMetadata::Retained(std::sync::Arc::clone(
                            row.as_ref().expect("all rows admitted"),
                        )))
                    })
                    .collect::<Vec<_>>();
                if !self
                    .metadata
                    .as_ref()
                    .is_some_and(|owner| owner.is_current_roster(slots, &prepared))
                {
                    self.metadata = metadata_roster::MetadataRoster::capture(
                        slots, batch, projection, references, &prepared,
                    );
                }
                return prepared;
            }
        }
        let prepared = prepare_metadata_with_admitted(
            slots,
            batch,
            projection,
            symbols,
            references,
            executor,
            true,
            admitted.as_deref(),
        );
        self.metadata = metadata_roster::MetadataRoster::capture(
            slots, batch, projection, references, &prepared,
        );
        prepared
    }
    /// Move the one metadata owner into the current plan. Every row must pass
    /// current per-frame admission before reuse; old binding tables are discarded.
    pub(super) fn inherit_metadata(&mut self, previous: &mut Self) {
        self.metadata = previous.metadata.take();
    }
    pub fn census(&self, census: &mut crate::heap_census::HeapCensus) {
        if let Some(owner) = &self.metadata {
            owner.census(census);
        }
        let name = "composition.plan";
        census.vec_payload(name, &self.raw.procedures);
        census.vec_payload(name, &self.raw.helpers);
        census.vec_payload(name, &self.raw.initializers);
        census.vec_payload(name, &self.units);
        census.vec_payload(name, &self.helpers);
        census.vec_payload(name, &self.initializers);
        if census.arc_object(name, &self.procedures) {
            census.vec_payload(name, &self.procedures);
        }
        if census.arc_object(name, &self.helper_rows) {
            census.vec_payload(name, &self.helper_rows);
        }
        if census.arc_object(name, &self.initializer_rows) {
            census.vec_payload(name, &self.initializer_rows);
        }
        if let Some((_, owner)) = &self.argument_sources {
            census.arc_object("composition.argument_sources", owner);
            census.unknown(
                "composition.argument_sources",
                "private BTreeMap backing and Arc control layout are unavailable",
            );
        }
        census.unknown(
            name,
            "binding owner BTreeMap backing, Arc controls and allocator overhead are unavailable",
        );
    }
}

pub(super) enum PreparedMetadata {
    Fresh(ProcedureMetadata),
    Retained(std::sync::Arc<super::frame_contribution::FrameContribution>),
}
impl From<ProcedureMetadata> for PreparedMetadata {
    fn from(value: ProcedureMetadata) -> Self {
        Self::Fresh(value)
    }
}
pub(super) struct ProcedureMetadata {
    pub declared: Option<bool>,
    pub path: Result<std::sync::Arc<str>, CompositionError>,
    pub default_display: Result<std::sync::Arc<str>, CompositionError>,
    pub value_sources: Vec<Result<u32, CompositionError>>,
}
fn metadata(
    unit: &FrozenUnit,
    projection: Option<&crate::class_projection::ClassProjection>,
    symbols: &SymbolTable,
    references: &dm_link::ArgumentSourceReferences,
) -> Result<ProcedureMetadata, CompositionError> {
    let abi = unit
        .lowered
        .abi
        .as_ref()
        .ok_or_else(|| unsupported("procedure ABI was not authoritative"))?;
    let frame = &unit.lowered.frame;
    if frame.argument_names.len() != frame.argument_type_flags.len()
        || frame.argument_names.len() != abi.argument_sources.len()
    {
        return Err(unsupported("argument metadata count mismatch"));
    }
    if frame.local_count as usize != frame.local_names.len() {
        return Err(unsupported("local metadata count mismatch"));
    }
    let identity = unit.lowered.identity;
    let key = crate::symbolic::unit_key(identity);
    let declared = match projection {
        Some(plan) => plan
            .procedure_declarations
            .get(&key)
            .copied()
            .ok_or_else(|| unsupported("missing source procedure declaration provenance")),
        None => Ok(true),
    };
    let declaration = declared.as_ref().ok().copied();
    let path = declared.and_then(|declared| unit.metadata_recipe.path(symbols, declared));
    let default_display = unit.metadata_recipe.display(symbols);
    let value_sources = unit
        .metadata_recipe
        .selectors(&abi.argument_sources)
        .iter()
        .map(|source| match source {
            ArgumentSource::Builtin { kind, parameter } => {
                Ok(u32::from(*kind) | (u32::from(*parameter) << 8))
            }
            ArgumentSource::Helper { argument } => {
                let argument = u32::try_from(*argument)
                    .map_err(|_| unsupported("helper argument overflow"))?;
                let position = references
                    .index(crate::symbolic::helper_key(identity, argument))
                    .ok_or_else(|| unsupported("missing argument source companion"))?;
                Ok(0x40 | (u32::from(position) << 8))
            }
        })
        .collect();
    Ok(ProcedureMetadata {
        declared: declaration,
        path,
        default_display,
        value_sources,
    })
}

pub(super) fn prepare_metadata(
    slots: &[Slot<UnitIdentity>],
    batch: &FrozenBatch,
    projection: Option<&crate::class_projection::ClassProjection>,
    symbols: &SymbolTable,
    references: &dm_link::ArgumentSourceReferences,
    executor: Option<&dm_exec::BuildExecutor>,
    retain_frames: bool,
) -> Vec<Result<PreparedMetadata, CompositionError>> {
    prepare_metadata_with_admitted(
        slots,
        batch,
        projection,
        symbols,
        references,
        executor,
        retain_frames,
        None,
    )
}
fn prepare_metadata_with_admitted(
    slots: &[Slot<UnitIdentity>],
    batch: &FrozenBatch,
    projection: Option<&crate::class_projection::ClassProjection>,
    symbols: &SymbolTable,
    references: &dm_link::ArgumentSourceReferences,
    executor: Option<&dm_exec::BuildExecutor>,
    retain_frames: bool,
    admitted: Option<&[Option<std::sync::Arc<super::frame_contribution::FrameContribution>>]>,
) -> Vec<Result<PreparedMetadata, CompositionError>> {
    let prepare = |index: usize, slot: &Slot<UnitIdentity>| {
        if let Some(hit) = admitted
            .and_then(|rows| rows.get(index))
            .and_then(Option::as_ref)
        {
            return Ok(PreparedMetadata::Retained(std::sync::Arc::clone(hit)));
        }
        prepare_metadata_row(slot, batch, projection, symbols, references, retain_frames)
    };
    let Some(executor) = executor.filter(|executor| executor.workers() > 1 && slots.len() > 1)
    else {
        return slots
            .iter()
            .enumerate()
            .map(|(index, slot)| prepare(index, slot))
            .collect();
    };
    let chunk = slots.len().div_ceil(executor.workers().min(slots.len()));
    let chunk_size = chunk;
    let chunks: Vec<_> = slots.chunks(chunk_size).collect();
    let outputs: Vec<_> = chunks.iter().map(|_| std::sync::Mutex::new(None)).collect();
    executor.scope(|scope| {
        for (index, chunk) in chunks.into_iter().enumerate() {
            let output = &outputs[index];
            let prepare = &prepare;
            scope.spawn(move |_| {
                let _profile = dm_profile::stage("composition.procedure_metadata");
                let rows = chunk
                    .iter()
                    .enumerate()
                    .map(|(local, slot)| {
                        std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                            prepare(index * chunk_size + local, slot)
                        }))
                        .unwrap_or_else(|_| Err(unsupported("procedure metadata worker panicked")))
                    })
                    .collect::<Vec<_>>();
                *output.lock().unwrap_or_else(|error| error.into_inner()) = Some(rows);
            });
        }
    });
    outputs
        .into_iter()
        .flat_map(|output| {
            output
                .into_inner()
                .unwrap_or_else(|error| error.into_inner())
                .expect("metadata worker completed")
        })
        .collect()
}

fn prepare_metadata_row(
    slot: &Slot<UnitIdentity>,
    batch: &FrozenBatch,
    projection: Option<&crate::class_projection::ClassProjection>,
    symbols: &SymbolTable,
    references: &dm_link::ArgumentSourceReferences,
    retain_frames: bool,
) -> Result<PreparedMetadata, CompositionError> {
    match slot.artifact {
        Some(index) => {
            let unit = &batch.units[index];
            if retain_frames {
                let retained = unit
                    .metadata_recipe
                    .frame_owner()
                    .lock()
                    .unwrap_or_else(|e| e.into_inner())
                    .clone();
                if let Some(hit) = retained
                    .filter(|hit| hit.admit_current_metadata(unit, projection, symbols, references))
                {
                    return Ok(PreparedMetadata::Retained(hit));
                }
            }
            metadata(unit, projection, symbols, references).map(PreparedMetadata::Fresh)
        }
        None => Err(unsupported("missing global procedure artifact")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn canonical_roster_preserves_numeric_order_and_last_alias() {
        let mut rows = vec![(9, 1), (2, 2), (9, 3), (3, 4)];
        canonical(&mut rows);
        assert_eq!(rows, [(2, 2), (3, 4), (9, 3)]);
    }
    #[test]
    fn bindings_keep_missing_rows_deferred_in_canonical_order() {
        let slots = bind(vec![(2, 4), (3, 8)], [(4, 7)].into_iter(), "duplicate").unwrap();
        assert_eq!(slots[0].artifact, Some(7));
        assert_eq!(slots[1].artifact, None);
        assert_eq!(slots[1].table_index, 3);
        assert_eq!(slots[1].identity, 8);
    }
    #[test]
    fn duplicate_artifact_remains_a_phase_error() {
        assert!(
            matches!(bind(vec![(2, 4)], [(4, 7), (4, 8)].into_iter(), "duplicate artifact"),
            Err(CompositionError::Unsupported(message)) if message == "duplicate artifact")
        );
    }
}

#[cfg(test)]
#[path = "argument_sources_tests.rs"]
mod argument_sources_tests;

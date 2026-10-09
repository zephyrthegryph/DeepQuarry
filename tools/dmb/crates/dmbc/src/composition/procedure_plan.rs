//! Canonical emission rosters and independent deferred procedure metadata.
use super::*;
use crate::{lowering::UnitIdentity, symbolic::FrozenUnit};
use dm_codegen_byond::procedure_abi::ArgumentSource;

#[derive(Default)]
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
pub(super) struct Slot<K> {
    pub table_index: u32,
    pub identity: K,
    pub artifact: Option<usize>,
}
pub(super) struct BoundCompositionPlan {
    pub procedures: Result<Vec<Slot<UnitIdentity>>, CompositionError>,
    pub helpers: Result<Vec<Slot<Key>>, CompositionError>,
    pub initializers: Result<Vec<Slot<dm_link::InitializerIdentity>>, CompositionError>,
}
fn bind<K: Ord + Copy>(
    rows: Vec<(u32, K)>,
    artifacts: impl Iterator<Item = (K, usize)>,
    duplicate: &str,
) -> Result<Vec<Slot<K>>, CompositionError> {
    let mut artifacts: Vec<_> = artifacts.collect();
    artifacts.sort_by_key(|row| row.0);
    if artifacts.windows(2).any(|pair| pair[0].0 == pair[1].0) {
        return Err(unsupported(duplicate));
    }
    Ok(rows
        .into_iter()
        .map(|(table_index, identity)| Slot {
            table_index,
            identity,
            artifact: artifacts
                .binary_search_by_key(&identity, |row| row.0)
                .ok()
                .map(|index| artifacts[index].1),
        })
        .collect())
}

pub(super) struct ProcedureMetadata {
    pub path: Result<String, CompositionError>,
    pub default_display: Result<String, CompositionError>,
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
    let path = declared.and_then(|declared| {
        proc_path(
            symbols,
            identity.owner,
            identity.name,
            identity.namespace,
            declared,
        )
    });
    let default_display = text(symbols, identity.name).map(|name| name.replace('_', " "));
    let value_sources = abi
        .argument_sources
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
) -> Vec<Result<ProcedureMetadata, CompositionError>> {
    let prepare = |slot: &Slot<UnitIdentity>| match slot.artifact {
        Some(index) => metadata(&batch.units[index], projection, symbols, references),
        None => Err(unsupported("missing global procedure artifact")),
    };
    let Some(executor) = executor.filter(|executor| executor.workers() > 1 && slots.len() > 1)
    else {
        return slots.iter().map(prepare).collect();
    };
    let chunk = slots.len().div_ceil(executor.workers().min(slots.len()));
    let chunks: Vec<_> = slots.chunks(chunk).collect();
    let outputs: Vec<_> = chunks.iter().map(|_| std::sync::Mutex::new(None)).collect();
    executor.scope(|scope| {
        for (index, chunk) in chunks.into_iter().enumerate() {
            let output = &outputs[index];
            let prepare = &prepare;
            scope.spawn(move |_| {
                let _profile = dm_profile::stage("composition.procedure_metadata");
                let rows = chunk
                    .iter()
                    .map(|slot| {
                        std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| prepare(slot)))
                            .unwrap_or_else(|_| {
                                Err(unsupported("procedure metadata worker panicked"))
                            })
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

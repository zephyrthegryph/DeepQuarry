//! Borrow the actual current initializer owners; no parser or token regeneration.
use super::*;
use crate::initializer_policy::{DefaultValue, InitializerArtifacts, SemanticClassification};
use dm_session::ArtifactStorageView;

fn storage<T>(
    c: &mut HeapCensus,
    prefix: &str,
    view: ArtifactStorageView<'_, T>,
    inspect: impl FnOnce(&mut HeapCensus, &Arc<T>),
) {
    match view {
        ArtifactStorageView::Store { entries, buckets } => {
            c.observe_items(prefix, entries);
            if buckets != 0 {
                c.unknown(prefix, "private artifact index nodes/control allocation excluded; exposed payload owners counted separately");
            }
        }
        ArtifactStorageView::Bucket {
            address,
            len,
            capacity,
            element_size,
        } => {
            c.buffer(
                prefix,
                address,
                len.saturating_mul(element_size),
                capacity.saturating_mul(element_size),
            );
        }
        ArtifactStorageView::Entry {
            key,
            reads,
            versions,
            value,
        } => {
            c.slice(prefix, key, true);
            if c.receipt(prefix, reads) {
                for read in reads.iter() {
                    super::resident_weight::answer(c, &read.answer);
                }
            }
            c.slice(prefix, versions, true);
            inspect(c, value);
        }
    }
}
pub(super) fn classification(c: &mut HeapCensus, value: &Arc<SemanticClassification>) {
    if !c.arc_object("initializer_classification.payload", value) {
        return;
    }
    c.arc_object("initializer_classification.identity", &value.identity());
    if let Some(write) = value.input_write() {
        c.shared_initializer_write("initializer_classification.inputs", write);
    }
    value.visit_retained_parts(|default, key, dimensions, expression| {
        match default {
            DefaultValue::Transform(_) => (),
            DefaultValue::Scalar(value) => {
                c.semantic_value("initializer_classification.default", value)
            }
            DefaultValue::InitializerExpression { canonical, .. } => {
                c.slice("initializer_classification.default", canonical, true);
            }
        }
        if let Some(key) = key {
            c.slice("initializer_classification.token_key", key, true);
        }
        if let Some(dimensions) = dimensions {
            c.slice("initializer_classification.dimensions", dimensions, true);
        }
        if let Some((source, syntax)) = expression {
            c.arc_text("initializer_classification.runtime_source", source);
            match syntax {
                Some(syntax) if c.arc_object("initializer_classification.runtime_ast", syntax) => {
                    c.typed_expression("initializer_classification.runtime_ast", syntax)
                }
                _ => (),
            }
        }
    });
}
pub(crate) fn compact_allocations(
    key: &Arc<[u8]>,
    reads: &dm_session::Receipt<dm_ir::ResolveQuery, dm_ir::ResolvedMeaning, dm_ir::ReadDomain>,
    versions: &Arc<[(dm_ir::ReadDomain, u128)]>,
    value: &Arc<SemanticClassification>,
    limit: usize,
) -> Option<Vec<dm_session::PressureAllocation>> {
    let mut census = HeapCensus::compact_pressure_allocations(limit);
    census.slice("compact.key", key, true);
    census.receipt("compact.reads", reads);
    census.slice("compact.versions", versions, true);
    for read in reads.iter() {
        super::resident_weight::answer(&mut census, &read.answer);
    }
    classification(&mut census, value);
    census.finish_compact_pressure_allocations()
}

pub(crate) fn compact_modifier_allocations(
    key: &Arc<[u8]>,
    reads: &dm_session::Receipt<dm_ir::ResolveQuery, dm_ir::ResolvedMeaning, dm_ir::ReadDomain>,
    versions: &Arc<[(dm_ir::ReadDomain, u128)]>,
    value: &Arc<crate::initializer_policy::modifier_facts::ModifierArtifact>,
    limit: usize,
) -> Option<Vec<dm_session::PressureAllocation>> {
    let mut census = HeapCensus::compact_pressure_allocations(limit);
    census.slice("compact.key", key, true);
    census.receipt("compact.reads", reads);
    census.slice("compact.versions", versions, true);
    for read in reads.iter() {
        super::resident_weight::answer(&mut census, &read.answer);
    }
    if census.arc_object("initializer_modifiers.payload", value) {
        census.shared_initializer_write("initializer_modifiers.inputs", &value.input);
    }
    census.finish_compact_pressure_allocations()
}

/// Conservative logical charge; repeated shared owners may be charged again.
/// Store/lease/index charges are supplied once by the shared pressure core.
pub(crate) fn compact_charge(census: HeapCensus, private: usize) -> Option<usize> {
    let encounters = census.buffer_encounters;
    let report = census.finish();
    if report.unknown_capacity_payload_bytes != 0
        || report.owners.iter().any(|owner| !owner.unknown.is_empty())
    {
        return None;
    }
    usize::try_from(report.unique_known_capacity_bytes)
        .ok()?
        .checked_add(encounters.checked_mul(64)?)?
        .checked_add(private)
}
impl HeapCensus {
    pub(crate) fn initializer_artifacts(&mut self, store: &InitializerArtifacts) {
        self.unknown("initializer_classification.publication", "private publication and lease control/index allocations excluded; pending and published payload owners visited together");
        store.visit_roster_storage(|address, bytes| {
            self.buffer(
                "initializer_classification.roster_owner",
                address,
                bytes,
                bytes,
            );
        });
        // Each callback finishes before the next mutex is entered. A roster
        // callback visits payloads only; it never re-enters either store.
        store.visit_storage(|view| {
            storage(
                self,
                "initializer_classification.store",
                view,
                classification,
            )
        });
        store.visit_modifier_storage(|view| {
            storage(self, "initializer_modifiers.store", view, |c, value| {
                if c.arc_object("initializer_modifiers.payload", value) {
                    c.shared_initializer_write("initializer_modifiers.inputs", &value.input);
                }
            })
        });
        store.visit_preparation(|preparation| {
            if !self.arc_object("initializer_preparation.owner", preparation) {
                return;
            }
            self.slice("initializer_preparation.owners", &preparation.owners, true);
            if self.slice(
                "initializer_preparation.buckets",
                &preparation.buckets,
                true,
            ) {
                for bucket in preparation.buckets.iter() {
                    self.slice("initializer_preparation.ordinals", &bucket.ordinals, true);
                }
            }
            preparation.visit_locations(|locations| {
                if !self.arc_object("initializer_preparation.locations", locations) {
                    return;
                }
                if self.slice("initializer_preparation.inputs", &locations.inputs, true) {
                    for input in locations.inputs.iter() {
                        self.shared_initializer_write("initializer_preparation.inputs", input);
                    }
                }
                self.slice("initializer_preparation.modifiers", &locations.facts, true);
                if self.arc_object("initializer_preparation.keys_owner", &locations.keys)
                    && self.vec_payload("initializer_preparation.keys", &locations.keys)
                {
                    for key in locations.keys.iter() {
                        self.slice("initializer_preparation.key_bytes", key, true);
                    }
                }
            });
        });
        store.visit_token_index(|owner| {
            if self.arc_object("initializer_token_roster.index", owner) {
                let index = owner.lock().unwrap_or_else(|error| error.into_inner());
                self.observe_items("initializer_token_roster.index", index.len());
                if index.capacity() != 0 {
                    self.unknown("initializer_token_roster.index", "private HashMap bucket/control backing excluded; logical entry count and exposed canonical owners counted");
                }
                for key in index.keys() {
                    self.slice("initializer_token_roster.canonical", key, true);
                }
            }
        });
        store.visit_token_roster(|accepted, tokens, groups| {
            if self.vec_payload("initializer_token_roster.accepted", accepted) {
                for value in accepted {
                    self.arc_object("initializer_classification.identity", value);
                }
            }
            if self.vec_payload("initializer_token_roster.tokens", tokens) {
                for (_, canonical) in tokens.iter().flatten() {
                    self.slice("initializer_token_roster.canonical", canonical, true);
                }
            }
            if self.vec_payload("initializer_token_roster.groups", groups) {
                for group in groups {
                    self.vec_payload("initializer_token_roster.group_writes", &group.writes);
                }
            }
        });
    }
}
#[cfg(test)]
pub(crate) fn inspect(store: &InitializerArtifacts) -> HeapCensusReport {
    let mut c = HeapCensus::new("retained_initializer_classification");
    c.initializer_artifacts(store);
    c.finish()
}
impl crate::lowering_memo::ProcedureMemo {
    pub fn initializer_retention_census(&self) -> Option<HeapCensusReport> {
        self.initializers.as_ref().map(|store| {
            let mut c = HeapCensus::new("retained_initializer_classification");
            if c.arc_object("initializer_classification.owner", store) {
                c.initializer_artifacts(store);
            }
            c.finish()
        })
    }
}

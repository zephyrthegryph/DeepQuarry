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
            c.vec_payload("initializer_classification.token_key", key);
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
impl HeapCensus {
    pub(crate) fn initializer_artifacts(&mut self, store: &InitializerArtifacts) {
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
        super::initializer_prepared_keys::inspect(self, store);
        store.visit_modifier_storage(|view| {
            storage(self, "initializer_modifiers.store", view, |c, value| {
                c.arc_object("initializer_modifiers.payload", value);
            })
        });
        store.visit_token_roster(|accepted, tokens, groups| {
            if self.vec_payload("initializer_token_roster.accepted", accepted) {
                for value in accepted {
                    classification(self, value);
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

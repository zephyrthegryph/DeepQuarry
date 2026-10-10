//! A single current canonical token/group layout, admitted by the same per-write owners.
//! No current syntax, origins, dense table IDs, or independent dependency cache.
use super::*;
use std::sync::{
    Mutex,
    atomic::{AtomicU64, Ordering},
};
#[derive(Default)]
pub(super) struct CurrentRoster {
    value: Mutex<Option<Roster>>,
    pub(super) hits: AtomicU64,
    pub(super) recomputed: AtomicU64,
}
struct Roster {
    debug_defined: bool,
    accepted: Vec<Arc<artifact::SemanticClassification>>,
    tokens: Vec<Option<(u32, Arc<[u8]>)>>,
    groups: Vec<RuntimeGroup>,
}
impl CurrentRoster {
    pub(super) fn clear(&self) {
        *self.value.lock().unwrap_or_else(|error| error.into_inner()) = None;
    }
    #[allow(clippy::type_complexity)]
    pub(super) fn visit(
        &self,
        visitor: impl FnOnce(
            &Vec<Arc<artifact::SemanticClassification>>,
            &Vec<Option<(u32, Arc<[u8]>)>>,
            &Vec<RuntimeGroup>,
        ),
    ) {
        let guard = self.value.lock().unwrap_or_else(|error| error.into_inner());
        if let Some(value) = guard.as_ref() {
            visitor(&value.accepted, &value.tokens, &value.groups);
        }
    }

    pub(super) fn finish(
        &self,
        pending: Vec<PendingWrite>,
        debug_defined: bool,
        ordinal: &mut usize,
    ) -> Result<ClassifiedInitializers, String> {
        let accepted = pending
            .iter()
            .map(|write| write.accepted.clone())
            .collect::<Option<Vec<_>>>();
        if let Some(accepted) = &accepted {
            let guard = self.value.lock().unwrap_or_else(|error| error.into_inner());
            if let Some(previous) = guard.as_ref().filter(|previous| {
                previous.debug_defined == debug_defined
                    && previous.accepted.len() == accepted.len()
                    && previous
                        .accepted
                        .iter()
                        .zip(accepted)
                        .all(|(a, b)| Arc::ptr_eq(a, b))
            }) {
                let writes = pending
                    .into_iter()
                    .zip(&previous.tokens)
                    .map(|(mut pending, token)| {
                        *ordinal = pending.write.source_ordinal;
                        if let Some((token, canonical)) = token {
                            pending.write.default = DefaultValue::InitializerExpression {
                                token: *token,
                                canonical: Arc::clone(canonical),
                            };
                        }
                        pending.write
                    })
                    .collect();
                self.hits.fetch_add(1, Ordering::Relaxed);
                return Ok(ClassifiedInitializers {
                    accepted: accepted
                        .iter()
                        .cloned()
                        .map(ClassificationOwner::new)
                        .map(Some)
                        .collect(),
                    writes,
                    groups: previous.groups.clone(),
                });
            }
        }
        self.recomputed.fetch_add(1, Ordering::Relaxed);
        let classified = finish_pending(pending.into_iter(), debug_defined, ordinal)?;
        let value = accepted.map(|accepted| Roster {
            debug_defined,
            accepted,
            tokens: classified
                .writes
                .iter()
                .map(|write| match &write.default {
                    DefaultValue::InitializerExpression { token, canonical } => {
                        Some((*token, Arc::clone(canonical)))
                    }
                    _ => None,
                })
                .collect(),
            groups: classified.groups.clone(),
        });
        *self.value.lock().unwrap_or_else(|error| error.into_inner()) = value;
        Ok(classified)
    }
}

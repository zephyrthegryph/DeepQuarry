//! A single current canonical token/group layout, admitted by the same per-write owners.
//! No current syntax, origins, dense table IDs, or independent dependency cache.
use super::*;
#[path = "preparation.rs"]
pub(super) mod preparation;
use std::sync::{
    atomic::{AtomicU64, Ordering},
    Mutex,
};
#[derive(Default)]
pub(super) struct CurrentRoster {
    value: Mutex<Option<Roster>>,
    preparation: Mutex<Option<Arc<preparation::Preparation>>>,
    pub(super) hits: AtomicU64,
    pub(super) recomputed: AtomicU64,
}
#[derive(Clone)]
struct Roster {
    debug_defined: bool,
    canonical: crate::initializer_tokens::CanonicalTokens,
    accepted: Vec<Arc<u8>>,
    tokens: Vec<Option<(u32, Arc<[u8]>)>>,
    groups: Vec<RuntimeGroup>,
}
impl CurrentRoster {
    pub(super) fn fork(&self) -> Self {
        Self {
            value: Mutex::new(
                self.value
                    .lock()
                    .unwrap_or_else(|error| error.into_inner())
                    .clone(),
            ),
            preparation: Mutex::new(
                self.preparation
                    .lock()
                    .unwrap_or_else(|error| error.into_inner())
                    .clone(),
            ),
            hits: AtomicU64::new(0),
            recomputed: AtomicU64::new(0),
        }
    }

    pub(super) fn canonical_owner(&self) -> Option<crate::initializer_tokens::CanonicalTokens> {
        self.value
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .as_ref()
            .map(|value| Arc::clone(&value.canonical))
    }
    pub(super) fn visit_canonical(
        &self,
        visitor: impl FnOnce(&crate::initializer_tokens::CanonicalTokens),
    ) {
        let guard = self.value.lock().unwrap_or_else(|error| error.into_inner());
        if let Some(value) = guard.as_ref() {
            visitor(&value.canonical);
        }
    }
    pub(super) fn clear(&self) {
        *self.value.lock().unwrap_or_else(|error| error.into_inner()) = None;
        self.clear_preparation();
    }
    pub(super) fn clear_preparation(&self) {
        *self
            .preparation
            .lock()
            .unwrap_or_else(|error| error.into_inner()) = None;
    }
    pub(super) fn preparation(&self, writes: &[InitializerWrite]) -> Arc<preparation::Preparation> {
        let previous = self
            .preparation
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .clone();
        if let Some(previous) = previous.filter(|previous| previous.matches(writes)) {
            return previous;
        }
        let current = preparation::Preparation::new(writes);
        *self.preparation.lock().unwrap_or_else(|e| e.into_inner()) = Some(current.clone());
        current
    }
    pub(super) fn visit_preparation(&self, visit: impl FnOnce(&Arc<preparation::Preparation>)) {
        let guard = self.preparation.lock().unwrap_or_else(|e| e.into_inner());
        if let Some(preparation) = guard.as_ref() {
            visit(preparation);
        }
    }
    #[allow(clippy::type_complexity)]
    pub(super) fn visit(
        &self,
        visitor: impl FnOnce(&Vec<Arc<u8>>, &Vec<Option<(u32, Arc<[u8]>)>>, &Vec<RuntimeGroup>),
    ) {
        let guard = self.value.lock().unwrap_or_else(|error| error.into_inner());
        if let Some(value) = guard.as_ref() {
            visitor(&value.accepted, &value.tokens, &value.groups);
        }
    }

    #[cfg(test)]
    pub(super) fn finish(
        &self,
        pending: Vec<PendingWrite>,
        debug_defined: bool,
        ordinal: &mut usize,
    ) -> Result<ClassifiedInitializers, String> {
        let mut tokens = crate::initializer_tokens::Tokens::new(debug_defined);
        self.finish_shared(pending, debug_defined, ordinal, &mut tokens)
    }
    pub(super) fn finish_shared(
        &self,
        pending: Vec<PendingWrite>,
        debug_defined: bool,
        ordinal: &mut usize,
        tokens: &mut crate::initializer_tokens::Tokens,
    ) -> Result<ClassifiedInitializers, String> {
        let accepted = pending
            .iter()
            .map(|write| write.accepted.as_ref().map(|value| value.identity()))
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
                        .map(ClassificationOwner::from_identity)
                        .map(Some)
                        .collect(),
                    writes,
                    groups: previous.groups.clone(),
                });
            }
        }
        self.recomputed.fetch_add(1, Ordering::Relaxed);
        let classified = finish_pending_shared(pending.into_iter(), ordinal, tokens)?;
        let value = accepted.map(|accepted| Roster {
            debug_defined,
            canonical: tokens.canonical_owner(),
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

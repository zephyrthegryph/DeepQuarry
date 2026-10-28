//! Body syntax lives in the SAME graph as compilation inputs, not a sibling
//! analysis cache. Revision-scoped keys are deliberately conservative: no
//! cross-revision reuse of ASTs containing absolute expanded-source positions.
use super::*;
use dm_tree::frontend::{
    BodySyntax, BodySyntaxInput, BodySyntaxQueries, Diagnostic, DiagnosticKind, DiagnosticStage,
};
use std::sync::{
    atomic::{AtomicUsize, Ordering},
    Weak,
};

pub(super) const BODY_SYNTAX: Kind = Kind(4);
const BUDGET: usize = 128 * 1024 * 1024;

#[derive(Debug)]
struct Params {
    input: Weak<BodySyntaxInput>,
    key: Key,
}

pub(super) fn register(db: &Db, charged: Arc<AtomicUsize>) {
    db.define(BODY_SYNTAX, "native-body-syntax", move |_, params| {
        let params = params
            .downcast_ref::<Params>()
            .expect("body query parameter type");
        let input = params
            .input
            .upgrade()
            .ok_or(QueryError::Missing(params.key))?;
        let result = input.parse().map(Arc::new);
        let bytes = result
            .as_ref()
            .map_or(1024, |syntax| syntax.budget_charge());
        // Identity is valid only within this private parser issuance. A fresh
        // issuance has a different key even if all its bytes happen to match.
        charged.fetch_add(bytes, Ordering::Relaxed);
        Ok(Outcome::new(result, params.key.id, bytes))
    });
}

impl std::fmt::Debug for QueryDb {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("QueryDb")
            .field("id", &self.id)
            .finish_non_exhaustive()
    }
}
impl BodySyntaxQueries for QueryDb {
    fn begin_revision(&self) {
        let mut inputs = self.body_inputs.lock().unwrap_or_else(|e| e.into_inner());
        inputs.retain(|key, input| {
            if input.strong_count() > 0 {
                true
            } else {
                let freed = self.db.value_bytes_at(*key);
                self.db.remove(*key);
                let _ =
                    self.body_charge
                        .fetch_update(Ordering::Relaxed, Ordering::Relaxed, |charge| {
                            Some(charge.saturating_sub(freed))
                        });
                false
            }
        });
    }
    fn syntax(&self, input: &Arc<BodySyntaxInput>) -> Result<Arc<BodySyntax>, Diagnostic> {
        let key = Key::new(BODY_SYNTAX, input.key().into());
        self.body_inputs
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .entry(key)
            .or_insert_with(|| Arc::downgrade(input));
        // Charge only computed values; checking the budget is O(1), unlike a
        // full graph census for each body. Conservative charges can evict early.
        if self.body_charge.load(Ordering::Relaxed) > BUDGET {
            let freed = self.db.evict_values(&[BODY_SYNTAX]);
            let _ = self
                .body_charge
                .fetch_update(Ordering::Relaxed, Ordering::Relaxed, |charge| {
                    Some(charge.saturating_sub(freed))
                });
        }
        let result = self
            .db
            .get::<Result<Arc<BodySyntax>, Diagnostic>>(
                key,
                Arc::new(Params {
                    input: Arc::downgrade(input),
                    key,
                }),
            )
            .map_err(|error| Diagnostic {
                kind: DiagnosticKind::Internal,
                stage: DiagnosticStage::Internal,
                location: None,
                message: format!("native body query failed: {error:?}"),
            })?;
        result.as_ref().clone()
    }
}

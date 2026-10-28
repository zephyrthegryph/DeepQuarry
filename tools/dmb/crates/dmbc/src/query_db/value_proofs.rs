//! Whole-program inference is a derived family of the compiler's existing DB.
//! Parameters retain input owners weakly; proof values retain no AST/model.
use super::*;
use dm_analysis::{
    untyped::Unsupported,
    value_query::{ArchiveValueInput, ArchiveValueProof, ArchiveValueQueries},
};
use std::sync::{
    atomic::{AtomicUsize, Ordering},
    Weak,
};

pub(super) const VALUE_PROOFS: Kind = Kind(5);
const BUDGET: usize = 64 * 1024 * 1024;
struct Params {
    input: Weak<ArchiveValueInput>,
    key: Key,
}
pub(super) fn register(db: &Db, charged: Arc<AtomicUsize>) {
    db.define(VALUE_PROOFS, "native-value-proofs", move |ctx, params| {
        let params = params
            .downcast_ref::<Params>()
            .expect("value proof parameter type");
        let input = params
            .input
            .upgrade()
            .ok_or(QueryError::Missing(params.key))?;
        for syntax in input
            .archive()
            .syntax_inputs()
            .ok_or(QueryError::Missing(params.key))?
        {
            body_syntax::observe(ctx, syntax)?;
        }
        let result = input.compute();
        let bytes = result.as_ref().map_or(1024, |proof| proof.budget_charge());
        charged.fetch_add(bytes, Ordering::Relaxed);
        Ok(Outcome::new(result, params.key.id, bytes))
    });
}
impl QueryDb {
    pub(super) fn prune_value_proofs(&self) {
        self.value_inputs
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .retain(|key, input| {
                if input.strong_count() > 0 {
                    return true;
                }
                let freed = self.db.value_bytes_at(*key);
                self.db.remove(*key);
                let _ =
                    self.value_charge
                        .try_update(Ordering::Relaxed, Ordering::Relaxed, |bytes| {
                            Some(bytes.saturating_sub(freed))
                        });
                false
            });
    }
}
impl ArchiveValueQueries for QueryDb {
    fn value_proof(
        &self,
        input: &Arc<ArchiveValueInput>,
    ) -> Result<Arc<ArchiveValueProof>, Unsupported> {
        if !input.archive().uses_body_queries(self) {
            return Err(Unsupported(
                "value proofs require the compiler's existing syntax graph".into(),
            ));
        }
        let syntax_inputs = input
            .archive()
            .syntax_inputs()
            .ok_or_else(|| Unsupported("issued syntax inputs absent".into()))?;
        // Kind5 observes all parser dependencies before inference. Reject an
        // oversized cohort before that loop can populate the syntax family.
        // This migration admission estimate is not a full-host/RSS guarantee.
        admit_syntax_cohort(syntax_inputs.iter().map(|input| input.budget_charge()))?;
        {
            let mut inputs = self.body_inputs.lock().unwrap_or_else(|e| e.into_inner());
            for syntax in syntax_inputs {
                inputs
                    .entry(Key::new(body_syntax::BODY_SYNTAX, syntax.key().into()))
                    .or_insert_with(|| Arc::downgrade(syntax));
            }
        }
        let key = Key::new(VALUE_PROOFS, input.key().into());
        self.value_inputs
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .entry(key)
            .or_insert_with(|| Arc::downgrade(input));
        if self.value_charge.load(Ordering::Relaxed) > BUDGET {
            let freed = self.db.evict_values(&[VALUE_PROOFS]);
            let _ = self
                .value_charge
                .try_update(Ordering::Relaxed, Ordering::Relaxed, |bytes| {
                    Some(bytes.saturating_sub(freed))
                });
        }
        let answer = self
            .db
            .get::<Result<Arc<ArchiveValueProof>, Unsupported>>(
                key,
                Arc::new(Params {
                    input: Arc::downgrade(input),
                    key,
                }),
            )
            .map_err(|e| Unsupported(format!("native value proof query failed: {e:?}")))?;
        let proof = answer
            .as_ref()
            .as_ref()
            .map(Arc::clone)
            .map_err(|error| Unsupported(error.0.clone()))?;
        proof.validate_for(input)?;
        Ok(proof)
    }
}

/// Pure preflight: arithmetic overflow is refusal, never a truncated cohort.
fn admit_syntax_cohort(charges: impl IntoIterator<Item = usize>) -> Result<usize, Unsupported> {
    charges.into_iter().try_fold(0usize, |total, charge| {
        total.checked_add(charge).filter(|&bytes| bytes <= body_syntax::BUDGET)
            .ok_or_else(|| Unsupported(format!(
                "native value proof syntax cohort exceeds {}-byte migration admission budget",
                body_syntax::BUDGET,
            )))
    })
}

#[cfg(test)]
mod budget_tests {
    use super::*;

    #[test]
    fn value_syntax_cohort_accepts_empty_and_exact_budget() {
        assert_eq!(admit_syntax_cohort([]).unwrap(), 0);
        assert_eq!(admit_syntax_cohort([body_syntax::BUDGET]).unwrap(), body_syntax::BUDGET);
        assert_eq!(admit_syntax_cohort([body_syntax::BUDGET - 1, 1]).unwrap(), body_syntax::BUDGET);
    }
    #[test]
    fn value_syntax_cohort_rejects_over_budget_and_overflow_without_parsing() {
        assert!(admit_syntax_cohort([body_syntax::BUDGET, 1]).is_err());
        assert!(admit_syntax_cohort([usize::MAX]).is_err());
        assert!(admit_syntax_cohort([1, usize::MAX]).is_err());
    }
}

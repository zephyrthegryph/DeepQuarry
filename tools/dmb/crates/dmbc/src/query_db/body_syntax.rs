//! Body syntax lives in the SAME graph as compilation inputs, not a sibling
//! analysis cache. Revision-scoped keys are deliberately conservative: no
//! cross-revision reuse of ASTs containing absolute expanded-source positions.
use super::*;
use dm_tree::frontend::{
    BodySyntax, BodySyntaxFailure, BodySyntaxInput, BodySyntaxQueries, Diagnostic, DiagnosticKind,
    DiagnosticStage,
};
use std::sync::{
    atomic::{AtomicUsize, Ordering},
    Weak,
};

pub(super) const BODY_SYNTAX: Kind = Kind(4);
pub(super) const BUDGET: usize = 128 * 1024 * 1024;

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
        #[cfg(test)]
        body_failure_test_checkpoint(params.key)?;
        // Existing Kind4 owns the in-scope permit. Setting leaves never call
        // host.syntax/Db.get or reacquire/reset any family admission here.
        let parsed = setting_syntax::with_setting_admission(&charged, |admission| {
            input.parse_with_setting_admission(admission)
        });
        let result = match parsed {
            Ok(syntax) => Ok(Arc::new(syntax)),
            Err(BodySyntaxFailure::Syntax(error)) => Err(error),
            Err(BodySyntaxFailure::Operational(error)) => {
                return Err(QueryError::operational(params.key, error))
            }
        };
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
        self.prune_value_proofs();
        self.prune_purity();
        self.prune_raw_policy();
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
        self.body_syntax_result(input)
            .map_err(body_query_diagnostic)?
    }
    fn syntax_checked(
        &self,
        input: &Arc<BodySyntaxInput>,
    ) -> Result<Arc<BodySyntax>, BodySyntaxFailure> {
        self.body_syntax_result(input)
            .map_err(|error| match error.into_operational() {
                Ok(actual) => BodySyntaxFailure::Operational(actual.into_io()),
                Err(error) => BodySyntaxFailure::Operational(std::io::Error::other(
                    BodyQueryGraphFailure(error),
                )),
            })?
            .map_err(BodySyntaxFailure::Syntax)
    }
}

// Standalone compatibility and checked native consumers share the SAME query,
// input owner, budget/eviction policy and cached syntax value. Only transport
// differs; an operational QueryError never becomes a syntax Diagnostic in the
// checked path and is never an Outcome.
// Infrastructure failure is not parser meaning. Retain the actual graph
// exception as the IO cause instead of caching an invented syntax Diagnostic.
#[derive(Debug)]
struct BodyQueryGraphFailure(QueryError);
impl std::fmt::Display for BodyQueryGraphFailure {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "native body query failed: {:?}", self.0)
    }
}
impl std::error::Error for BodyQueryGraphFailure {}
fn body_query_diagnostic(error: QueryError) -> Diagnostic {
    Diagnostic {
        kind: DiagnosticKind::Internal,
        stage: DiagnosticStage::Internal,
        location: None,
        message: format!("native body query failed: {error:?}"),
    }
}
impl QueryDb {
    fn body_syntax_result(
        &self,
        input: &Arc<BodySyntaxInput>,
    ) -> Result<Result<Arc<BodySyntax>, Diagnostic>, QueryError> {
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
        let result = self.db.get::<Result<Arc<BodySyntax>, Diagnostic>>(
            key,
            Arc::new(Params {
                input: Arc::downgrade(input),
                key,
            }),
        )?;
        Ok(result.as_ref().clone())
    }
}

/// Record a real syntax dependency of a derived policy query. The archive's
/// later parse request borrows this exact cached value through its host.
pub(super) fn observe(
    ctx: &mut dm_query::Ctx<'_>,
    input: &Arc<BodySyntaxInput>,
) -> Result<(), QueryError> {
    let key = Key::new(BODY_SYNTAX, input.key().into());
    ctx.get::<Result<Arc<BodySyntax>, Diagnostic>>(
        key,
        Arc::new(Params {
            input: Arc::downgrade(input),
            key,
        }),
    )?;
    Ok(())
}

// Explicit per-thread test scheduling at the genuine Kind4 compute boundary.
// No settings admission or production error state is introduced here.
#[cfg(test)]
enum TestBodyFailure {
    Operational(std::io::Error),
    GraphMissing,
}
#[cfg(test)]
thread_local! {static BODY_FAILURE:std::cell::RefCell<Option<(usize,TestBodyFailure)>>=const{std::cell::RefCell::new(None)};}
#[cfg(test)]
pub(crate) struct BodyFailureSchedule;
#[cfg(test)]
impl Drop for BodyFailureSchedule {
    fn drop(&mut self) {
        BODY_FAILURE.with(|s| *s.borrow_mut() = None);
    }
}
#[cfg(test)]
fn body_failure_test_checkpoint(key: Key) -> Result<(), QueryError> {
    BODY_FAILURE.with(|s| {
        let mut scheduled = s.borrow_mut();
        if let Some((remaining, _)) = scheduled.as_mut() {
            if *remaining > 0 {
                *remaining -= 1;
                return Ok(());
            }
            let (_, error) = scheduled.take().expect("scheduled failure");
            return Err(match error {
                TestBodyFailure::Operational(error) => QueryError::operational(key, error),
                TestBodyFailure::GraphMissing => QueryError::Missing(key),
            });
        }
        Ok(())
    })
}
#[cfg(test)]
impl QueryDb {
    pub(crate) fn fail_body_syntax_after_for_test(
        &self,
        completed: usize,
        error: std::io::Error,
    ) -> BodyFailureSchedule {
        BODY_FAILURE.with(|s| {
            assert!(s.borrow().is_none());
            *s.borrow_mut() = Some((completed, TestBodyFailure::Operational(error)));
        });
        BodyFailureSchedule
    }
    pub(crate) fn fail_body_graph_once_for_test(&self) -> BodyFailureSchedule {
        BODY_FAILURE.with(|s| {
            assert!(s.borrow().is_none());
            *s.borrow_mut() = Some((0, TestBodyFailure::GraphMissing));
        });
        BodyFailureSchedule
    }
}

#[cfg(test)]
#[path="body_literal_tests.rs"]mod body_literal_tests;

//! Exact per-query receipts; no source revision or dense arena IDs are retained.
use super::*;
#[derive(Clone, Debug, Eq, PartialEq, Ord, PartialOrd)]
pub enum ScalarReadQuery {
    PurePolicy,
    Member { owner: SymbolId, name: SymbolId },
    Meaning(ResolveQuery),
    Spelling(SymbolId),
    Predefined(SymbolId),
    Dependency(ScalarQuery),
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ScalarReadAnswer {
    PurePolicy(u128, Option<(u128, u128)>),
    Member(Option<(SymbolId, SymbolId, Arc<crate::MemberMetadata>, u128)>),
    Meaning(ResolvedMeaning),
    Spelling(Option<Arc<str>>),
    Predefined(PredefinedOutcome),
    Dependency(ScalarOutcome),
}
/// A single result plus direct dependency graph data. Public construction is
/// inspectable; only current exact read replay in the shared store admits it.
#[derive(Debug)]
pub struct ScalarArtifact {
    certificate: Option<u64>,
    pub outcome: ScalarOutcome,
    pub dependencies: Arc<[ScalarQuery]>,
    pub predefined: Arc<[(SymbolId, PredefinedOutcome)]>,
}
impl ScalarArtifact {
    /// Construct inspectable data without issuing shortcut authority.
    pub fn new(
        outcome: ScalarOutcome,
        dependencies: Arc<[ScalarQuery]>,
        predefined: Arc<[(SymbolId, PredefinedOutcome)]>,
    ) -> Self {
        Self {
            certificate: None,
            outcome,
            dependencies,
            predefined,
        }
    }
    pub(super) fn captured(
        outcome: ScalarOutcome,
        dependencies: Arc<[ScalarQuery]>,
        predefined: Arc<[(SymbolId, PredefinedOutcome)]>,
    ) -> Self {
        static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(1);
        let certificate = matches!(outcome, ScalarOutcome::Value(_))
            .then(|| {
                NEXT.fetch_update(
                    std::sync::atomic::Ordering::Relaxed,
                    std::sync::atomic::Ordering::Relaxed,
                    |next| next.checked_add(1),
                )
                .ok()
            })
            .flatten();
        Self {
            certificate,
            outcome,
            dependencies,
            predefined,
        }
    }
    /// Process-local receipt. It is usable only after current exact store admission.
    pub fn certificate(&self) -> Option<u64> {
        self.certificate
    }
}
pub trait ScalarArtifacts {
    fn accept_policy(
        &self,
        _decode: fn(&str) -> Option<Vec<u8>>,
        _nameof: fn(&Expr) -> Option<String>,
    ) -> bool {
        false
    }
    fn finish(&self, _queries: &[ScalarQuery]) {}
    fn lookup(
        &self,
        query: ScalarQuery,
        answer: &dyn Fn(&ScalarReadQuery) -> ScalarReadAnswer,
    ) -> Option<Arc<ScalarArtifact>>;
    /// Compatibility providers do not issue replay authority implicitly.
    fn remember_certified(
        &self,
        query: ScalarQuery,
        value: ScalarArtifact,
        reads: Vec<(ScalarReadQuery, ScalarReadAnswer)>,
    ) -> Option<Arc<ScalarArtifact>> {
        self.remember(query, value, reads);
        None
    }
    fn remember(
        &self,
        query: ScalarQuery,
        value: ScalarArtifact,
        reads: Vec<(ScalarReadQuery, ScalarReadAnswer)>,
    );
}

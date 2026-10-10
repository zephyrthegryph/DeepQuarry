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
    PurePolicy(Option<(u128, u128)>),
    Member(Option<(SymbolId, SymbolId, Arc<crate::MemberMetadata>)>),
    Meaning(ResolvedMeaning),
    Spelling(Option<Arc<str>>),
    Predefined(PredefinedOutcome),
    Dependency(ScalarOutcome),
}
/// A single result plus direct dependency graph data. Public construction is
/// inspectable; only current exact read replay in the shared store admits it.
pub struct ScalarArtifact {
    pub outcome: ScalarOutcome,
    pub dependencies: Arc<[ScalarQuery]>,
    pub predefined: Arc<[(SymbolId, PredefinedOutcome)]>,
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
    fn remember(
        &self,
        query: ScalarQuery,
        value: ScalarArtifact,
        reads: Vec<(ScalarReadQuery, ScalarReadAnswer)>,
    );
}

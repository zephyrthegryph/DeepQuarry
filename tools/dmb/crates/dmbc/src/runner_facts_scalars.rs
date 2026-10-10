//! Scalar receipts share the existing host artifact store, with exact engine ownership.
use super::*;
use dm_tree::constant_resolution::{
    ScalarArtifact, ScalarArtifacts, ScalarQuery, ScalarReadAnswer, ScalarReadQuery,
};
pub(super) struct CurrentScalars<'a> {
    pub owner: &'a RetainedHostFacts,
    pub engine: &'a Arc<crate::runner_host::RetainedEngine>,
}
struct Replay<'a> {
    engine: &'a Arc<crate::runner_host::RetainedEngine>,
    answer: &'a dyn Fn(&ScalarReadQuery) -> ScalarReadAnswer,
}
impl dm_session::ObservationHost<Query, Answer, Domain> for Replay<'_> {
    fn answer(&self, query: &Query) -> Answer {
        match query {
            Query::Engine => Answer::Engine(Arc::clone(self.engine)),
            Query::Scalar(query) => Answer::Scalar((self.answer)(query)),
            _ => unreachable!("scalar stage contains only engine and evaluator reads"),
        }
    }
}
pub(super) fn key(query: ScalarQuery) -> Vec<u8> {
    let (kind, owner, name) = match query {
        ScalarQuery::Const { owner, name } => (0, owner, name),
        ScalarQuery::DeclaredDefault { owner, name } => (1, owner, name),
        ScalarQuery::EffectiveDefault { owner, name } => (2, owner, name),
    };
    let mut bytes = b"native-pinned-scalar-v1\0".to_vec();
    bytes.push(kind);
    bytes.extend_from_slice(&owner.bits().to_le_bytes());
    bytes.extend_from_slice(&name.bits().to_le_bytes());
    bytes
}
impl ScalarArtifacts for CurrentScalars<'_> {
    fn accept_policy(
        &self,
        decode: fn(&str) -> Option<Vec<u8>>,
        nameof: fn(&dm_syntax::Expr) -> Option<String>,
    ) -> bool {
        std::ptr::fn_addr_eq(
            decode,
            crate::compile_driver::scalar_decode as fn(&str) -> Option<Vec<u8>>,
        ) && std::ptr::fn_addr_eq(
            nameof,
            crate::compile_driver::scalar_nameof as fn(&dm_syntax::Expr) -> Option<String>,
        )
    }
    fn lookup(
        &self,
        query: ScalarQuery,
        answer: &dyn Fn(&ScalarReadQuery) -> ScalarReadAnswer,
    ) -> Option<Arc<ScalarArtifact>> {
        let value = self.owner.values.lookup(
            &key(query),
            &Replay {
                engine: self.engine,
                answer,
            },
        )?;
        match value.as_ref() {
            Artifact::Scalar(value) => {
                self.owner.scalar_hits.fetch_add(1, Ordering::Relaxed);
                Some(Arc::clone(value))
            }
            _ => None,
        }
    }
    fn remember(
        &self,
        query: ScalarQuery,
        value: ScalarArtifact,
        reads: Vec<(ScalarReadQuery, ScalarReadAnswer)>,
    ) {
        let ledger = dm_session::ObservationLedger::default();
        ledger.record(
            Query::Engine,
            Answer::Engine(Arc::clone(self.engine)),
            Domain::ExactOwners,
            None,
        );
        for (query, answer) in reads {
            ledger.record(
                Query::Scalar(query),
                Answer::Scalar(answer),
                Domain::ExactOwners,
                None,
            );
        }
        let key = key(query);
        let charge = std::mem::size_of::<Artifact>().saturating_add(key.len());
        self.owner.values.insert_with(
            Arc::from(key),
            ledger.reads(),
            ledger.domain_receipts(),
            charge,
            || Artifact::Scalar(Arc::new(value)),
        );
    }
    fn finish(&self, queries: &[ScalarQuery]) {
        let keys: Vec<_> = queries.iter().copied().map(key).collect();
        self.owner
            .values
            .retain_current_keys(keys.iter().map(Vec::as_slice).chain([
                KEY,
                catalogs::CONSTANTS_KEY,
                catalogs::RUNTIME_KEY,
                engine_providers::KEY,
            ]));
    }
}

pub(super) fn inspect(value: &Arc<ScalarArtifact>, census: &mut crate::heap_census::HeapCensus) {
    if census.arc_object("host.scalar.artifact", value) {
        inspect_outcome(&value.outcome, census);
        census.slice(
            "host.scalar.artifact.dependencies",
            &value.dependencies,
            true,
        );
        census.slice("host.scalar.artifact.predefined", &value.predefined, true);
        for (_, answer) in value.predefined.iter() {
            if let dm_tree::constant_resolution::PredefinedOutcome::Value(value) = answer {
                census.semantic_value("host.scalar.artifact.predefined", value);
            }
        }
    }
}
fn inspect_outcome(
    value: &dm_tree::constant_resolution::ScalarOutcome,
    census: &mut crate::heap_census::HeapCensus,
) {
    use dm_tree::constant_resolution::ScalarOutcome;
    match value {
        ScalarOutcome::Value(value) => census.semantic_value("host.scalar.artifact.value", value),
        ScalarOutcome::RejectedPureCall(error) => {
            for text in [&error.name, &error.reason] {
                census.exposed_buffer(
                    "host.scalar.artifact.errors",
                    text.as_ptr() as usize,
                    text.len(),
                    text.capacity(),
                );
            }
        }
        ScalarOutcome::Cycle(cycle) => {
            census.slice("host.scalar.artifact.cycles", cycle, true);
        }
        _ => (),
    }
}
pub(super) fn inspect_answer(
    value: &ScalarReadAnswer,
    census: &mut crate::heap_census::HeapCensus,
) {
    match value {
        ScalarReadAnswer::Member(Some((_, _, metadata))) => {
            if census.arc_object("host.scalar.read.metadata", metadata) {
                census.unknown(
                    "host.scalar.read.metadata",
                    "nested immutable declaration metadata backing excluded",
                );
            }
        }
        ScalarReadAnswer::Spelling(Some(text)) => {
            census.arc_text("host.scalar.read.spellings", text);
        }
        ScalarReadAnswer::Dependency(value) => inspect_outcome(value, census),
        ScalarReadAnswer::Predefined(dm_tree::constant_resolution::PredefinedOutcome::Value(
            value,
        )) => census.semantic_value("host.scalar.read.predefined", value),
        ScalarReadAnswer::Meaning(_) => census.unknown(
            "host.scalar.read.meanings",
            "nested resolver meaning backing excluded",
        ),
        _ => (),
    }
}

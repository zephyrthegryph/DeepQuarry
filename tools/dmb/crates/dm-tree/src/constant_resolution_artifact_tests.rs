use super::*;
use std::sync::atomic::{AtomicUsize, Ordering};
struct Store {
    values:
        dm_session::ObservedArtifactStore<ScalarArtifact, ScalarReadQuery, ScalarReadAnswer, ()>,
    hits: AtomicUsize,
}
impl Default for Store {
    fn default() -> Self {
        Self {
            values: dm_session::ObservedArtifactStore::current_revision(),
            hits: AtomicUsize::new(0),
        }
    }
}
struct Replay<'a>(&'a dyn Fn(&ScalarReadQuery) -> ScalarReadAnswer);
impl dm_session::ObservationHost<ScalarReadQuery, ScalarReadAnswer, ()> for Replay<'_> {
    fn answer(&self, query: &ScalarReadQuery) -> ScalarReadAnswer {
        (self.0)(query)
    }
}
fn key(query: ScalarQuery) -> Vec<u8> {
    let mut bytes = Vec::new();
    query.encode(&mut bytes);
    bytes
}
fn decode(raw: &str) -> Option<Vec<u8>> {
    Some(raw.as_bytes().to_vec())
}
fn nameof(_: &Expr) -> Option<String> {
    None
}
impl ScalarArtifacts for Store {
    fn finish(&self, queries: &[ScalarQuery]) {
        let keys: Vec<_> = queries.iter().copied().map(key).collect();
        self.values
            .retain_current_keys(keys.iter().map(Vec::as_slice));
    }
    fn accept_policy(
        &self,
        decoder: fn(&str) -> Option<Vec<u8>>,
        names: fn(&Expr) -> Option<String>,
    ) -> bool {
        std::ptr::fn_addr_eq(decoder, decode as fn(&str) -> Option<Vec<u8>>)
            && std::ptr::fn_addr_eq(names, nameof as fn(&Expr) -> Option<String>)
    }
    fn lookup(
        &self,
        query: ScalarQuery,
        answer: &dyn Fn(&ScalarReadQuery) -> ScalarReadAnswer,
    ) -> Option<Arc<ScalarArtifact>> {
        let value = self.values.lookup(&key(query), &Replay(answer));
        if value.is_some() {
            self.hits.fetch_add(1, Ordering::Relaxed);
        }
        value
    }
    fn remember(
        &self,
        query: ScalarQuery,
        value: ScalarArtifact,
        reads: Vec<(ScalarReadQuery, ScalarReadAnswer)>,
    ) {
        let ledger = dm_session::ObservationLedger::default();
        for (query, answer) in reads {
            ledger.record(query, answer, (), None);
        }
        self.values
            .insert_with(key(query).into(), ledger.reads(), Vec::new(), 0, || value);
    }
}
fn query(name: &str) -> ScalarQuery {
    ScalarQuery::Const {
        owner: SymbolId::of("/datum/probe"),
        name: SymbolId::of(name),
    }
}
fn run(store: &Store, source: &str, requests: &[ScalarQuery]) -> ScalarSnapshot {
    let source = tests::snapshot(source);
    let actual = resolve_pinned_with_artifacts(
        &source,
        requests,
        1,
        decode,
        nameof,
        None,
        None,
        Some(store),
    );
    let fresh = resolve(
        &source,
        requests,
        &ScalarBackend {
            identity: 1,
            decode_string: &decode,
            nameof: &nameof,
        },
    );
    assert_eq!(actual.identity, fresh.identity);
    assert_eq!(actual.outcomes, fresh.outcomes);
    assert_eq!(actual.dependencies, fresh.dependencies);
    assert_eq!(actual.predefined_reads, fresh.predefined_reads);
    assert!(Arc::ptr_eq(&actual.source.occurrences, &source.occurrences));
    actual
}
#[test]
fn scalar_receipts_reuse_unrelated_structural_edits_and_recalculate_dependencies() {
    let store = Store::default();
    let requests = [query("a")];
    run(
        &store,
        "/datum/probe\n    var/const/a = b + 1\n    var/const/b = 3\n",
        &requests,
    );
    let before = store.hits.load(Ordering::Relaxed);
    run(&store,"/datum/probe\n    var/const/a = b + 1\n    var/const/b = 3\n    var/extra = 9\n    proc/unrelated()\n        return 2\n",&requests);
    assert!(store.hits.load(Ordering::Relaxed) >= before + 2);
    let result = run(
        &store,
        "/datum/probe\n    var/const/a = b + 1\n    var/const/b = 7\n",
        &requests,
    );
    assert_eq!(
        result.outcome(query("a")),
        Some(&ScalarOutcome::Value(SemanticValue::NumberBits(
            8f32.to_bits()
        )))
    );
}
#[test]
fn negative_lexical_probes_and_changed_short_circuit_do_not_pollute_current_graph() {
    let store = Store::default();
    let requests = [query("a")];
    run(
        &store,
        "var/const/b = 3\n/datum/probe\n    var/const/a = b + 1\n",
        &requests,
    );
    let result = run(
        &store,
        "var/const/b = 3\n/datum/probe\n    var/b = 9\n    var/const/a = b + 1\n",
        &requests,
    );
    assert_eq!(
        result.outcome(query("a")),
        Some(&ScalarOutcome::Unsupported(UnsupportedReason::NotConst))
    );
    let store = Store::default();
    run(
        &store,
        "/datum/probe\n    var/const/a = b && c\n    var/const/b = 1\n    var/const/c = 4\n",
        &requests,
    );
    let result = run(
        &store,
        "/datum/probe\n    var/const/a = b && c\n    var/const/b = 0\n    var/const/c = 4\n",
        &requests,
    );
    assert!(!result.outcomes.contains_key(&query("c")));
}
#[test]
fn cycle_and_cycle_ancestors_never_enter_retained_store() {
    let store = Store::default();
    run(
        &store,
        "/datum/probe\n    var/const/a = b + 1\n    var/const/b = c\n    var/const/c = 3\n",
        &[query("a")],
    );
    store.values.visit_storage(|view| {
        if let dm_session::ObservedArtifactStorageView::Store { entries, .. } = view {
            assert_eq!(entries, 3)
        }
    });
    run(
        &store,
        "/datum/probe\n    var/const/a = b + 1\n    var/const/b = c\n    var/const/c = b\n",
        &[query("a")],
    );
    store.values.visit_storage(|view| {
        if let dm_session::ObservedArtifactStorageView::Store { entries, .. } = view {
            assert_eq!(entries, 0)
        }
    });
}
#[test]
fn opaque_backend_and_pure_call_policy_decline_retention() {
    let store = Store::default();
    let source = tests::snapshot("/datum/probe\n    var/const/a = 1\n");
    fn custom(_: &str) -> Option<Vec<u8>> {
        None
    }
    resolve_pinned_with_artifacts(
        &source,
        &[query("a")],
        1,
        custom,
        nameof,
        None,
        None,
        Some(&store),
    );
    struct Opaque;
    impl PureCalls for Opaque {
        fn identity(&self) -> u128 {
            1
        }
        fn accepts(&self, _: &str) -> bool {
            true
        }
        fn evaluate(
            &self,
            name: &str,
            _arguments: &[Option<Constant>],
        ) -> Result<Constant, PureCallError> {
            Err(PureCallError {
                name: name.into(),
                reason: "opaque".into(),
            })
        }
    }
    resolve_pinned_with_artifacts(
        &source,
        &[query("a")],
        1,
        decode,
        nameof,
        None,
        Some(&Opaque),
        Some(&store),
    );
    store.values.visit_storage(|view| {
        if let dm_session::ObservedArtifactStorageView::Store { entries, .. } = view {
            assert_eq!(entries, 0)
        }
    });
}

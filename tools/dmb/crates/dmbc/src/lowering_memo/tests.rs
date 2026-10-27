use super::*;
#[test]
fn resident_budget_evicts_before_retaining_new_results() {
    let memo = LoweringMemo::with_limit(10);
    assert!(memo.insert_with(Arc::from(b"a".as_slice()), vec![], vec![], 6, || 1u32));
    assert!(memo.insert_with(Arc::from(b"b".as_slice()), vec![], vec![], 6, || 2u32));
    assert!(memo.lookup(b"a", &Host(false)).is_none());
    assert_eq!(memo.lookup(b"b", &Host(false)).as_deref(), Some(&2));
    assert_eq!(memo.admitted_bytes(), 6);
}

struct Host(bool);
impl Resolver for Host {
    fn resolve(&self, _query: ResolveQuery) -> ResolvedMeaning {
        if self.0 {
            ResolvedMeaning::Symbol(dm_ir::SymbolId::of("/datum/changed"))
        } else {
            ResolvedMeaning::Missing
        }
    }
}
#[test]
fn negative_reads_invalidate_and_exact_keys_never_alias() {
    let memo = LoweringMemo::default();
    let recorder = RecordingResolver::new(&Host(false));
    recorder.resolve(ResolveQuery::GlobalVar(dm_ir::SymbolId::of("absent")));
    memo.insert(
        Arc::from(b"full-header-body".as_slice()),
        recorder.reads(),
        7u32,
    );
    assert_eq!(
        memo.lookup(b"full-header-body", &Host(false)).as_deref(),
        Some(&7)
    );
    assert!(memo.lookup(b"full-header-body", &Host(true)).is_none());
    assert!(memo
        .lookup(b"changed-header-same-body", &Host(false))
        .is_none());
}
#[test]
fn mandatory_reads_include_ancestry_and_structural_declaration_position() {
    let recorder = RecordingResolver::new(&Host(false));
    recorder.record_declaration_occurrence(dm_ir::ProcedureIdentity {
        owner: dm_ir::SymbolId::of("/datum/a"),
        name: dm_ir::SymbolId::of("run"),
        verb: false,
        occurrence: 2,
    });
    let reads = recorder.reads();
    assert_eq!(reads.len(), 2);
    assert!(matches!(reads[0].query, ResolveQuery::Ancestry(_)));
    assert!(matches!(
        reads[1].query,
        ResolveQuery::DeclarationChain { .. }
    ));
    // The explicit legacy recorder remains available to body-sensitive clients.
    let legacy = RecordingResolver::new(&Host(false));
    legacy.record_occurrence(dm_ir::ProcedureIdentity {
        owner: dm_ir::SymbolId::of("/datum/a"),
        name: dm_ir::SymbolId::of("run"),
        verb: false,
        occurrence: 2,
    });
    assert!(matches!(
        legacy.reads()[1].query,
        ResolveQuery::OverrideChain { .. }
    ));
}
struct ReplayHost {
    changed: bool,
    calls: std::sync::atomic::AtomicUsize,
}
impl Resolver for ReplayHost {
    fn resolve(&self, _: ResolveQuery) -> ResolvedMeaning {
        self.calls
            .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        if self.changed {
            ResolvedMeaning::Symbol(dm_ir::SymbolId::of("changed"))
        } else {
            ResolvedMeaning::Missing
        }
    }
}
#[test]
fn stored_reads_are_replayed_and_a_changed_answer_declines() {
    let host = |changed| ReplayHost {
        changed,
        calls: Default::default(),
    };
    let initial = host(false);
    let recorder = RecordingResolver::new(&initial);
    recorder.resolve(ResolveQuery::GlobalVar(dm_ir::SymbolId::of("absent")));
    recorder.resolve(ResolveQuery::Resource(dm_ir::SymbolId::of("missing.asset")));
    assert_eq!(recorder.reads().len(), 2);
    let memo = LoweringMemo::default();
    assert!(memo.insert_with(
        Arc::from(b"domain-key".as_slice()),
        recorder.reads(),
        Vec::new(),
        1,
        || 7u32
    ));
    let same = host(false);
    assert_eq!(memo.lookup(b"domain-key", &same).as_deref(), Some(&7));
    assert_eq!(same.calls.load(std::sync::atomic::Ordering::Relaxed), 2);
    let changed = host(true);
    assert!(memo.lookup(b"domain-key", &changed).is_none());
}

#[path = "disk_candidate_tests.rs"]
mod disk_candidates;

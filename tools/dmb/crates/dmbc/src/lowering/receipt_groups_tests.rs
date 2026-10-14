use super::*;
use dm_ir::Resolver;
use std::sync::{
    atomic::{AtomicUsize, Ordering},
    Arc,
};

struct Host {
    missing_now_present: bool,
    calls: AtomicUsize,
}
impl Resolver for Host {
    fn observes_reads(&self) -> bool {
        false
    }
    fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
        self.calls.fetch_add(1, Ordering::Relaxed);
        match query {
            ResolveQuery::HasMemberVar { name, .. } if name == SymbolId::of("missing") => {
                ResolvedMeaning::Presence(self.missing_now_present)
            }
            ResolveQuery::HasMemberVar { .. } => ResolvedMeaning::Presence(true),
            _ => ResolvedMeaning::Unsupported(query),
        }
    }
}
fn reads(owner: &str, private: &str) -> Vec<ResolverRead> {
    let shared = SymbolId::of(owner);
    let private = SymbolId::of(private);
    let mut reads = vec![
        (shared, "known", true),
        (shared, "missing", false),
        (private, "own", true),
    ]
    .into_iter()
    .map(|(owner, name, present)| {
        let query = ResolveQuery::HasMemberVar {
            owner,
            name: SymbolId::of(name),
        };
        ResolverRead {
            query,
            domain: query.domain(),
            answer: ResolvedMeaning::Presence(present),
        }
    })
    .collect::<Vec<_>>();
    reads.sort_by_key(|read| read.query);
    reads
}
fn leaves(receipt: &ProcedureReceipt) -> Vec<Arc<[ResolverRead]>> {
    let mut result = Vec::new();
    receipt.visit_storage(|view| {
        if let dm_session::ReceiptStorageView::Flat(leaf) = view {
            result.push(Arc::clone(leaf));
        }
    });
    result
}
#[test]
fn grouped_procedure_reads_share_exact_owner_leaves_and_replay_every_edge() {
    let pool = ProcedureGroups::default();
    let first = grouped(&pool, reads("/datum/shared", "/datum/first"));
    let second = grouped(&pool, reads("/datum/shared", "/datum/second"));
    let common = |receipt: &ProcedureReceipt| {
        leaves(receipt)
            .into_iter()
            .find(|leaf| leaf.len() == 2)
            .unwrap()
    };
    assert!(Arc::ptr_eq(&common(&first), &common(&second)));
    let host = Host {
        missing_now_present: false,
        calls: AtomicUsize::new(0),
    };
    let request = RequestAdmission::new(&host);
    let first_observer = crate::lowering_memo::RecordingResolver::new(&host);
    let second_observer = crate::lowering_memo::RecordingResolver::new(&host);
    assert_eq!(
        request.first_changed(&first, |leaf| first_observer.record_admitted(leaf)),
        None
    );
    assert_eq!(
        request.first_changed(&second, |leaf| second_observer.record_admitted(leaf)),
        None
    );
    assert_eq!(
        host.calls.load(Ordering::Relaxed),
        4,
        "shared two-read leaf validated once"
    );
    assert_eq!(
        first_observer.reads(),
        first.iter().cloned().collect::<Vec<_>>()
    );
    assert_eq!(
        second_observer.reads(),
        second.iter().cloned().collect::<Vec<_>>()
    );
    let changed = Host {
        missing_now_present: true,
        calls: AtomicUsize::new(0),
    };
    let next_request = RequestAdmission::new(&changed);
    assert!(
        next_request.first_changed(&first, |_| {}).is_some(),
        "negative answer becoming positive invalidates next request"
    );
}
#[test]
fn conflicting_query_answers_are_not_discarded_and_opaque_observers_resolve() {
    let pool = ProcedureGroups::default();
    let mut original = reads("/datum/shared", "/datum/private");
    let mut conflict = original[0].clone();
    conflict.answer = ResolvedMeaning::Missing;
    original.insert(1, conflict);
    let grouped = grouped(&pool, original.clone());
    assert_eq!(grouped.iter().cloned().collect::<Vec<_>>(), original);
    struct Observer(AtomicUsize);
    impl Resolver for Observer {
        fn resolve(&self, _: ResolveQuery) -> ResolvedMeaning {
            self.0.fetch_add(1, Ordering::Relaxed);
            ResolvedMeaning::Missing
        }
    }
    let opaque = Observer(AtomicUsize::new(0));
    assert!(
        opaque.observes_reads(),
        "external wrappers safely retain resolve instrumentation"
    );
    let recorder = crate::lowering_memo::RecordingResolver::new(&opaque);
    recorder.record_admitted(&original);
    assert_eq!(opaque.0.load(Ordering::Relaxed), original.len());
}

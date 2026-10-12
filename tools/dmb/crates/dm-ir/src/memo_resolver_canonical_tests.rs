use super::*;
use crate::{CanonicalResolvedAnswer, SymbolId};
struct Provider {
    calls: AtomicUsize,
    answer: ResolvedMeaning,
}
impl Resolver for Provider {
    fn resolve(&self, _: ResolveQuery) -> ResolvedMeaning {
        self.calls.fetch_add(1, Ordering::Relaxed);
        self.answer.clone()
    }
}
fn query() -> ResolveQuery {
    ResolveQuery::GlobalProc(SymbolId::of("missing"))
}
#[test]
fn canonical_request_memo_lazily_shares_bounded_bytes() {
    let host = Provider {
        calls: AtomicUsize::new(0),
        answer: ResolvedMeaning::Missing,
    };
    let memo = MemoResolver::new(&host, 4);
    memo.resolve(query());
    assert!(memo.entries.read().unwrap()[&query()].canonical.is_none());
    let a = memo.resolve_with_canonical(query());
    let b = memo.resolve_with_canonical(query());
    assert_eq!(a.answer, b.answer);
    assert_eq!(a.canonical().as_ptr(), b.canonical().as_ptr());
    assert_eq!(host.calls.load(Ordering::Relaxed), 1);
}
#[test]
fn canonical_oversize_bytes_compute_without_retaining_them() {
    let mut answer = super::declaration_tests::declaration();
    if let ResolvedMeaning::Declaration { data, .. } = &mut answer {
        Arc::make_mut(data).canonical = Arc::from(vec![7u8; 5000]);
    }
    let host = Provider {
        calls: AtomicUsize::new(0),
        answer,
    };
    let memo = MemoResolver::new(&host, 4);
    let a = memo.resolve_with_canonical(query());
    let b = memo.resolve_with_canonical(query());
    assert!(a.canonical().len() > 4096);
    assert_eq!(a.canonical(), b.canonical());
    assert!(memo.entries.read().unwrap()[&query()]
        .canonical
        .as_ref()
        .unwrap()
        .get()
        .unwrap()
        .is_none());
    assert_eq!(host.calls.load(Ordering::Relaxed), 1);
}
#[test]
fn canonical_concurrent_cells_share_one_retained_byte_owner() {
    let host = Provider {
        calls: AtomicUsize::new(0),
        answer: ResolvedMeaning::Missing,
    };
    let memo = MemoResolver::new(&host, 4);
    memo.resolve(query());
    let answers: Vec<CanonicalResolvedAnswer> = std::thread::scope(|scope| {
        let handles: Vec<_> = (0..8)
            .map(|_| scope.spawn(|| memo.resolve_with_canonical(query())))
            .collect();
        handles.into_iter().map(|h| h.join().unwrap()).collect()
    });
    assert!(answers
        .iter()
        .all(|a| a.canonical().as_ptr() == answers[0].canonical().as_ptr()));
}
#[test]
fn default_canonical_capability_preserves_every_observed_resolve() {
    let host = Provider {
        calls: AtomicUsize::new(0),
        answer: ResolvedMeaning::Missing,
    };
    let a = host.resolve_with_canonical(query());
    let b = host.resolve_with_canonical(query());
    assert_eq!(a.canonical(), b.canonical());
    assert_eq!(host.calls.load(Ordering::Relaxed), 2);
}

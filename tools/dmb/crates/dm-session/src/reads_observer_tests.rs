use super::*;
use crate::{Observation, Receipt, ReceiptAdmission};
use std::sync::atomic::{AtomicUsize, Ordering};
struct Provider {
    calls: AtomicUsize,
    changed: bool,
}
fn negative() -> ResolveQuery {
    ResolveQuery::GlobalVar(dm_ir::SymbolId::of("missing"))
}
fn opaque() -> ResolveQuery {
    ResolveQuery::GlobalVar(dm_ir::SymbolId::of("opaque"))
}
impl Resolver for Provider {
    fn observes_reads(&self) -> bool {
        false
    }
    fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
        self.calls.fetch_add(1, Ordering::Relaxed);
        if query == negative() {
            if self.changed {
                ResolvedMeaning::Symbol(dm_ir::SymbolId::of("now present"))
            } else {
                ResolvedMeaning::Missing
            }
        } else {
            ResolvedMeaning::Unsupported(query)
        }
    }
}
fn provider(changed: bool) -> Provider {
    Provider {
        calls: AtomicUsize::new(0),
        changed,
    }
}
fn receipt() -> Receipt<ResolveQuery, ResolvedMeaning, ReadDomain> {
    vec![
        Observation {
            query: negative(),
            answer: ResolvedMeaning::Missing,
            domain: negative().domain(),
        },
        Observation {
            query: opaque(),
            answer: ResolvedMeaning::Unsupported(opaque()),
            domain: opaque().domain(),
        },
    ]
    .into()
}
fn assert_reads(
    recording: &RecordingResolver<'_, impl Resolver>,
    receipt: &Receipt<ResolveQuery, ResolvedMeaning, ReadDomain>,
) {
    let mut expected = receipt.iter().cloned().collect::<Vec<_>>();
    expected.sort_by_key(|read| read.query);
    assert_eq!(recording.reads(), expected);
}
#[test]
fn admitted_leaf_delivery_preserves_nested_negative_and_opaque_reads() {
    let host = provider(false);
    let inner = RecordingResolver::new(&host);
    let outer = RecordingResolver::new(&inner);
    let admission = ReceiptAdmission::new(&outer);
    let receipt = receipt();
    assert!(admission.allows_certificate_reuse());
    assert_eq!(admission.first_changed_receipted(&receipt, |_| {}), None);
    assert_reads(&inner, &receipt);
    assert_reads(&outer, &receipt);
    // Each read was replayed once against the provider; the recorders took the admitted answers.
    assert_eq!(host.calls.load(Ordering::Relaxed), 2);
}
#[test]
fn exact_leaf_delivery_and_cached_verdict_do_not_repeat_provider_evaluation() {
    let host = provider(false);
    let recorder = RecordingResolver::new(&host);
    let admission = ReceiptAdmission::new(&recorder);
    let receipt = receipt();
    for _ in 0..2 {
        assert_eq!(admission.first_changed(&receipt, |_| {}), None);
    }
    assert_eq!(host.calls.load(Ordering::Relaxed), 2);
    assert_reads(&recorder, &receipt);
}
#[test]
fn receipts_replay_the_current_provider_and_a_changed_leaf_cannot_import_old_answers() {
    let receipt = receipt();
    let host = provider(false);
    let recorder = RecordingResolver::new(&host);
    let admission = ReceiptAdmission::new(&recorder);
    assert_eq!(admission.first_changed_receipted(&receipt, |_| {}), None);
    assert_eq!(host.calls.load(Ordering::Relaxed), 2);
    let changed = provider(true);
    let new = RecordingResolver::new(&changed);
    let admission = ReceiptAdmission::new(&new);
    assert_eq!(
        admission.first_changed_receipted(&receipt, |_| {}),
        Some(negative())
    );
    assert!(
        new.reads().is_empty(),
        "a private admitted-leaf proof cannot exist for a changed leaf"
    );
}
#[test]
fn differing_duplicate_answers_remain_independent_admission_obligations() {
    let query = negative();
    let receipt: Receipt<_, _, _> = vec![
        Observation {
            query,
            answer: ResolvedMeaning::Missing,
            domain: query.domain(),
        },
        Observation {
            query,
            answer: ResolvedMeaning::Unsupported(query),
            domain: query.domain(),
        },
    ]
    .into();
    let host = provider(false);
    let recorder = RecordingResolver::new(&host);
    let admission = ReceiptAdmission::new(&recorder);
    assert_eq!(admission.first_changed_receipted(&receipt, |_| {}), Some(query));
    assert_eq!(host.calls.load(Ordering::Relaxed), 2);
    assert!(recorder.reads().is_empty());
}
struct Nontransparent<'a> {
    host: &'a Provider,
    observed: AtomicUsize,
}
impl Resolver for Nontransparent<'_> {
    fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
        self.observed.fetch_add(1, Ordering::Relaxed);
        self.host.resolve(query)
    }
}
#[test]
fn nontransparent_custom_observer_keeps_ordinary_resolve_callbacks() {
    let host = provider(false);
    let custom = Nontransparent {
        host: &host,
        observed: AtomicUsize::new(0),
    };
    let recorder = RecordingResolver::new(&custom);
    let admission = ReceiptAdmission::new(&recorder);
    let receipt = receipt();
    assert!(!admission.allows_certificate_reuse());
    assert_eq!(admission.first_changed_receipted(&receipt, |_| {}), None);
    assert_reads(&recorder, &receipt);
    assert_eq!(custom.observed.load(Ordering::Relaxed), 2);
    assert!(dm_ir::TransparentReceiptObserver::new(&custom, &recorder).is_none());
}

#[test]
fn canonical_forwarding_records_every_nested_observation_around_same_memo() {
    struct Current(std::sync::atomic::AtomicUsize);
    impl dm_ir::Resolver for Current {
        fn observes_reads(&self) -> bool {
            false
        }
        fn resolve(&self, _: dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning {
            self.0.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
            dm_ir::ResolvedMeaning::Missing
        }
    }
    let host = Current(std::sync::atomic::AtomicUsize::new(0));
    let memo = dm_ir::MemoResolver::new(&host, 4);
    let inner = super::RecordingResolver::new(&memo);
    let outer = super::RecordingResolver::new(&inner);
    let query = dm_ir::ResolveQuery::GlobalProc(dm_ir::SymbolId::of("canonical_missing"));
    let a = dm_ir::Resolver::resolve_with_canonical(&outer, query);
    let b = dm_ir::Resolver::resolve_with_canonical(&outer, query);
    assert_eq!(a.canonical().as_ptr(), b.canonical().as_ptr());
    assert_eq!(host.0.load(std::sync::atomic::Ordering::Relaxed), 1);
    assert_eq!(inner.reads().len(), 1);
    assert_eq!(outer.reads().len(), 1);
    assert_eq!(outer.reads()[0].answer, dm_ir::ResolvedMeaning::Missing);
}

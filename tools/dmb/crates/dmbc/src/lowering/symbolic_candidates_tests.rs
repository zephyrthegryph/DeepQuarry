use super::*;
use std::sync::atomic::AtomicUsize;
struct Host {
    versions: AtomicUsize,
    answers: AtomicUsize,
    current: u128,
}
impl Resolver for Host {
    fn resolve(&self, _: dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning {
        self.answers.fetch_add(1, Ordering::Relaxed);
        dm_ir::ResolvedMeaning::Presence(false)
    }
    fn domain_version(&self, _: dm_ir::ReadDomain) -> Option<u128> {
        self.versions.fetch_add(1, Ordering::Relaxed);
        Some(self.current)
    }
    fn observes_reads(&self) -> bool {
        false
    }
}
#[test]
fn symbolic_request_dispatch_uses_one_current_certificate_and_preserves_local_guards() {
    let owner = SessionSymbolicMemo::current_revision();
    let first = owner.for_request(true);
    let query = dm_ir::ResolveQuery::MemberCallableName(dm_ir::SymbolId::of("missing"));
    let identity = UnitIdentity {
        owner: dm_ir::SymbolId::of("/datum/a"),
        name: dm_ir::SymbolId::of("p"),
        namespace: Namespace::Proc,
        occurrence: 0,
    };
    for bytes in [b"first".as_slice(), b"second".as_slice()] {
        assert!(first.insert_record(
            identity,
            Record {
                local: None,
                recipe: None,
                key: Arc::from(bytes),
                reads: vec![ResolverRead {
                    query,
                    domain: query.domain(),
                    answer: dm_ir::ResolvedMeaning::Presence(false)
                }]
                .into(),
                versions: Arc::from([(query.domain(), 7)]),
                value: RecordValue::Selections {
                    facts: Arc::new(Default::default()),
                    abi: vec![1]
                },
                relative_debug: vec![],
                required_types: Arc::from([]),
                modified_recipes: Arc::from([]),
            }
        ));
    }
    assert!(first.publish_successful());
    drop(first);
    let next = owner.for_request(false);
    let host = Host {
        versions: AtomicUsize::new(0),
        answers: AtomicUsize::new(0),
        current: 7,
    };
    let admission = RequestAdmission::new(&host);
    let roster = next.candidate_roster(&admission).unwrap();
    assert!(roster.take_identity_if(identity, |_| false).is_empty());
    assert_eq!(host.versions.load(Ordering::Relaxed), 1);
    for (bytes, license) in [(b"first".as_slice(), false), (b"second".as_slice(), true)] {
        let key = symbolic_publication::locator(identity, bytes);
        let mut edges = 0;
        let accepted = next
            .attempt
            .as_ref()
            .unwrap()
            .with_pending(|leases| {
                leases.records.claim_unchanged(
                    roster.take(&key).pop().unwrap(),
                    &key,
                    |record| license && record.key.as_ref() == bytes,
                    |leaf| edges += leaf.len(),
                )
            })
            .flatten();
        assert_eq!(accepted.is_some(), license);
        assert_eq!(edges, usize::from(license));
    }
    assert_eq!(host.versions.load(Ordering::Relaxed), 1);
    assert_eq!(host.answers.load(Ordering::Relaxed), 0);
    let changed = Host {
        current: 8,
        versions: AtomicUsize::new(0),
        answers: AtomicUsize::new(0),
    };
    let changed_admission = RequestAdmission::new(&changed);
    assert!(next
        .candidate_roster(&changed_admission)
        .unwrap()
        .take_identity(identity)
        .is_empty());
}

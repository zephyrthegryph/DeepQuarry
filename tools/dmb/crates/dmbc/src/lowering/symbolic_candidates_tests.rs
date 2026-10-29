use super::*;
use std::sync::atomic::AtomicUsize;
struct AnswerHost {
    present: bool,
    versions: AtomicUsize,
}
impl Resolver for AnswerHost {
    fn resolve(&self, _: dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning {
        dm_ir::ResolvedMeaning::Presence(self.present)
    }
    fn observes_reads(&self) -> bool {
        false
    }
}
#[test]
fn query_database_proves_stored_units_by_their_recorded_answers() {
    let db = Arc::new(crate::query_db::QueryDb::default());
    let owner = SessionSymbolicMemo::current_revision().with_query_db(&db);
    let first = owner.for_request(true);
    let query = dm_ir::ResolveQuery::MemberCallableName(dm_ir::SymbolId::of("present"));
    let identity = UnitIdentity {
        owner: dm_ir::SymbolId::of("/datum/a"),
        name: dm_ir::SymbolId::of("p"),
        namespace: Namespace::Proc,
        occurrence: 0,
    };
    assert!(first.insert_record(
        identity,
        Record {
            local: None,
            recipe: None,
            key: Arc::<[u8]>::from(b"unit".as_slice()).into(),
            reads: vec![ResolverRead {
                query,
                domain: query.domain(),
                answer: dm_ir::ResolvedMeaning::Presence(true)
            }]
            .into(),
            value: RecordValue::Selections {
                facts: Arc::new(Default::default()),
                abi: vec![1]
            },
            relative_debug: vec![].into(),
            required_types: Arc::from([]),
            modified_recipes: Arc::from([]),
        }
    ));
    assert!(first.publish_successful());
    drop(first);
    for (present, proven) in [(true, 1), (false, 0), (true, 1)] {
        db.next_request();
        let next = owner.for_request(false);
        let host = AnswerHost { present, versions: AtomicUsize::new(0) };
        let admission = RequestAdmission::new(&host);
        let roster = next.candidate_roster(&admission).unwrap();
        assert_eq!(roster.take_identity(identity).len(), proven, "present={present}");
        assert_eq!(host.versions.load(Ordering::Relaxed), 0, "no domain versions are issued");
    }
}

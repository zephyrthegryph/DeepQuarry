use super::*;
use dm_codegen_byond::ProcedureInputs;
use dm_ir::{ProcedureMetadata, ResolveQuery, ResolvedMeaning, SymbolId, SymbolTable};
use dm_tree::frontend::SourceLocation;

struct Source;
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &std::path::Path) -> Result<String, String> {
        Ok("/proc/probe()\n    return 7\n".into())
    }
}
struct Host {
    changed: bool,
}
impl Resolver for Host {
    fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
        if query == ResolveQuery::GlobalProc(SymbolId::of("new_dependency")) {
            if self.changed {
                ResolvedMeaning::Symbol(SymbolId::of("/proc/new_dependency"))
            } else {
                ResolvedMeaning::Missing
            }
        } else {
            ResolvedMeaning::Unsupported(query)
        }
    }
}
struct Policy;
impl AbiPolicy for Policy {
    fn inputs(
        &self,
        _: UnitIdentity,
        _: &ProcedureMetadata,
        _: &SymbolTable,
        _: &SourceLocation,
    ) -> Result<ProcedureInputs, String> {
        Ok(ProcedureInputs::default())
    }
}
#[test]
fn rich_promotion_preserves_current_only_negative_reissue_dependency() {
    let front = dm_tree::frontend::build(
        std::path::Path::new("project.dme"),
        &Source,
        &Default::default(),
        1,
    )
    .unwrap();
    let host = Host { changed: false };
    let mut lowered = crate::lowering::lower_frontend(&front, &host, &Policy, Default::default());
    assert!(lowered.diagnostics.is_empty(), "{:?}", lowered.diagnostics);
    let unit = lowered.units.pop().unwrap();
    let mut memo = crate::lowering_memo::ProcedureMemo::new(1);
    memo.symbolic = Some(Arc::new(SessionSymbolicMemo::default()));
    let key: Arc<[u8]> = Arc::from(&b"current-rich-procedure"[..]);
    memo.values.insert(
        Arc::clone(&key),
        Vec::new(),
        crate::lowering_memo::CachedProcedure {
            unit,
            relative_debug: Vec::new(),
        },
    );
    let (accepted, changed) =
        memo.values
            .visit_receipted_with(&key, &mut |_, _| None::<ResolveQuery>, &mut |_| true);
    assert!(changed.is_none());
    let accepted = accepted.unwrap();
    assert_eq!(accepted.reads.iter().count(), 0);
    let current = crate::lowering_memo::RecordingResolver::new(&host);
    let query = ResolveQuery::GlobalProc(SymbolId::of("new_dependency"));
    assert_eq!(current.resolve(query), ResolvedMeaning::Missing);
    accepted.reads.visit_storage(|view| {
        if let dm_session::ReceiptStorageView::Flat(leaf) = view {
            current.record_admitted(leaf);
        }
    });
    let promoted = accepted_admission(&memo, key.to_vec(), &accepted, &current).unwrap();
    assert!(promoted
        .reads
        .iter()
        .any(|read| read.query == query && read.answer == ResolvedMeaning::Missing));
    // Exercise the same shared store admission used by the promoted record.
    let store = dm_session::ArtifactStore::<()>::default();
    assert!(store
        .insert_with_receipt(
            Arc::clone(&key),
            promoted.reads,
            promoted.versions,
            1,
            || ()
        )
        .is_some());
    assert!(store.lookup(&key, &host).is_some());
    assert!(store.lookup(&key, &Host { changed: true }).is_none());
}

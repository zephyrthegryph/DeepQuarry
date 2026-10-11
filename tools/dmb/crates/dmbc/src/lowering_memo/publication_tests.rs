use super::*;
struct Source;
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &std::path::Path) -> Result<String, String> {
        Ok("/proc/read()\n    return 7\n".into())
    }
}
struct Host;
impl Resolver for Host {
    fn resolve(&self, query: ResolveQuery) -> dm_ir::ResolvedMeaning {
        dm_ir::ResolvedMeaning::Unsupported(query)
    }
}
struct Policy;
impl crate::lowering::AbiPolicy for Policy {
    fn inputs(
        &self,
        _: crate::lowering::UnitIdentity,
        _: &dm_ir::ProcedureMetadata,
        _: &dm_ir::SymbolTable,
        _: &dm_tree::frontend::SourceLocation,
    ) -> Result<dm_codegen_byond::ProcedureInputs, String> {
        Ok(Default::default())
    }
}
fn cached(weight: usize) -> CachedProcedure {
    let frontend = dm_tree::frontend::build(
        std::path::Path::new("project.dme"),
        &Source,
        &Default::default(),
        1,
    )
    .unwrap();
    let mut lowered =
        crate::lowering::lower_frontend(&frontend, &Host, &Policy, Default::default());
    assert!(lowered.diagnostics.is_empty());
    CachedProcedure {
        unit: lowered.units.remove(0),
        relative_debug: vec![],
        retained_weight: weight,
    }
}
#[test]
fn rich_published_and_pending_charge_once_and_failed_attempt_keeps_success() {
    let owner = Arc::new(RetainedProcedures::default());
    let first = owner.begin(true);
    let key: Arc<[u8]> = Arc::from(b"exact".as_slice());
    let old = first
        .with_pending(|lease| {
            lease.insert_with_receipt(Arc::clone(&key), Vec::new().into(), RESIDENT_LIMIT, || {
                cached(RESIDENT_LIMIT)
            })
        })
        .flatten()
        .unwrap();
    let weak = Arc::downgrade(&old);
    assert!(first.publish_successful());
    drop(first);
    drop(old);
    assert!(!owner.can_insert(1));
    let next = owner.begin(true);
    let shared = next
        .with_pending(|lease| lease.visit_explained_accepted(&key, &Host, &mut |_| true).0)
        .flatten()
        .unwrap();
    assert!(owner.can_insert(0));
    assert!(!owner.can_insert(1));
    drop(shared);
    drop(next);
    assert!(weak.upgrade().is_some());
    let analysis = owner.begin(false);
    assert!(!analysis.publish_successful());
    drop(analysis);
    let empty = owner.begin(true);
    assert!(empty.publish_successful());
    assert!(weak.upgrade().is_none());
    assert!(owner.can_insert(RESIDENT_LIMIT));
}

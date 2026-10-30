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
fn cached() -> CachedProcedure {
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
                cached()
            })
        })
        .flatten()
        .unwrap();
    let weak = Arc::downgrade(&old);
    assert!(first.publish_successful());
    drop(first);
    drop(old);
    assert_eq!(owner.values.available_bytes(), 0);
    let next = owner.begin(true);
    assert!(next
        .with_pending(|lease| lease.insert_with_receipt(
            Arc::from(b"new".as_slice()),
            Vec::new().into(),
            1,
            || panic!("over-budget value must not be constructed")
        ))
        .flatten()
        .is_none());
    assert!(weak.upgrade().is_some());
    let shared = next
        .with_pending(|lease| lease.visit_explained_accepted(&key, &Host, &mut |_| true).0)
        .flatten()
        .unwrap();
    assert_eq!(owner.values.admitted_bytes(), RESIDENT_LIMIT);
    assert_eq!(owner.values.available_bytes(), 0);
    drop(shared);
    drop(next);
    assert!(weak.upgrade().is_some());
    let analysis = owner.begin(false);
    assert!(!analysis.publish_successful());
    drop(analysis);
    let empty = owner.begin(true);
    assert!(empty.publish_successful());
    assert!(weak.upgrade().is_none());
    assert_eq!(owner.values.available_bytes(), RESIDENT_LIMIT);
}

#[test]
fn rich_fallible_current_rebind_error_keeps_original_publication_and_retry() {
    let owner = Arc::new(RetainedProcedures::default());
    let key: Arc<[u8]> = Arc::from(b"typed-rich-rebind".as_slice());
    let first = owner.begin(true);
    let original = first
        .with_pending(|lease| {
            lease.insert_with_receipt(Arc::clone(&key), Vec::new().into(), 1, cached)
        })
        .flatten()
        .unwrap();
    assert!(first.publish_successful());
    drop(first);
    let memo = ProcedureMemo::with_resident_for_request(17, Arc::clone(&owner), None, true);
    let error = memo
        .try_visit_resident(&key, &Host, &mut |_| {
            Err::<bool, _>(std::io::Error::from_raw_os_error(1450))
        })
        .err()
        .expect("actual current rebind IO");
    assert_eq!(error.raw_os_error(), Some(1450));
    drop(memo);
    assert!(
        Arc::strong_count(&original) > 1,
        "failed request did not drop original publication"
    );
    let retry = ProcedureMemo::with_resident_for_request(17, Arc::clone(&owner), None, true);
    let (accepted, changed) = retry
        .try_visit_resident(&key, &Host, &mut |_| Ok::<_, std::io::Error>(true))
        .unwrap();
    assert!(changed.is_none());
    assert!(Arc::ptr_eq(&accepted.unwrap().value, &original));
}

use super::*;

#[test]
fn symbolic_code_admission_preserves_fresh_sharing_and_shared_or_weak_artifact_owners() {
    struct Source;
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &std::path::Path) -> Result<String, String> {
            Ok("/proc/check()\n    return 7\n".into())
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
            Ok(Default::default())
        }
    }
    let frontend = dm_tree::frontend::build(
        std::path::Path::new("project.dme"),
        &Source,
        &Default::default(),
        1,
    )
    .unwrap();
    let tree = frontend.snapshot.tree.as_ref();
    let fresh = || {
        let mut batch =
            crate::lowering::lower_frontend(&frontend, tree, &Policy, Default::default());
        assert!(batch.diagnostics.is_empty(), "{:?}", batch.diagnostics);
        crate::symbolic::prepare_contribution(
            batch.units.remove(0),
            tree.symbols(),
            &Default::default(),
            &Default::default(),
            false,
        )
        .unwrap()
    };
    let pool = Arc::new(crate::symbolic::shared_procedure_code::SharedProcedureCode::default());
    let owner = SessionSymbolicMemo::with_shared_code(&pool);
    let request = owner.for_request(true);
    let mut first = fresh();
    let mut second = fresh();
    assert!(first.can_share_code());
    assert!(second.can_share_code());
    request.share_current_code(&mut first);
    request.share_current_code(&mut second);
    let first_artifact = first.shared_artifact();
    let second_artifact = second.shared_artifact();
    assert!(
        Arc::ptr_eq(
            &first_artifact.code().shared_code(),
            &second_artifact.code().shared_code()
        ),
        "fresh owners must still enter the existing physical sharing lease"
    );
    assert!(!second.can_share_code());
    let before = second_artifact.code().shared_code();
    let source = second.current_source().clone();
    request.share_current_code(&mut second);
    assert!(Arc::ptr_eq(&before, &second_artifact.code().shared_code()));
    assert_eq!(second.current_source(), &source);

    // A weak observer also forbids mutable sharing, even after its strong
    // sibling drops. The eligibility guard must match Arc::get_mut precisely.
    let weak = Arc::downgrade(&second_artifact);
    drop(second_artifact);
    assert!(!second.can_share_code());
    request.share_current_code(&mut second);
    assert!(weak.upgrade().is_some());
    drop(weak);
    assert!(second.can_share_code());
    request.share_current_code(&mut second);
    assert!(request.publish_successful());
    assert!(Arc::ptr_eq(
        &before,
        &second.shared_artifact().code().shared_code()
    ));
}

use super::*;
use std::{
    path::Path,
    sync::atomic::{AtomicBool, Ordering},
};
struct Source;
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok("/proc/probe()\n    return 7\n".into())
    }
}
struct Policy(AtomicBool);
impl AbiPolicy for Policy {
    fn inputs(
        &self,
        _: UnitIdentity,
        metadata: &ProcedureMetadata,
        _: &SymbolTable,
        _: &SourceLocation,
    ) -> Result<ProcedureInputs, String> {
        assert!(metadata.signature.parameters.is_empty());
        Ok(Default::default())
    }
    fn prepare_issued_checked(
        &self,
        _: &ProcedureMetadata,
        _: &dm_tree::frontend::IssuedBodyInput<'_>,
        _: &AbiContext<'_>,
    ) -> Result<Option<PreparedReplay>, dm_codegen_byond::procedure_abi::AbiError> {
        if self.0.swap(false, Ordering::Relaxed) {
            Err(dm_codegen_byond::procedure_abi::AbiError::operational(
                std::io::Error::from_raw_os_error(1450),
            ))
        } else {
            Ok(None)
        }
    }
}
#[test]
fn checked_memo_issued_and_body_operations_never_become_misses_or_cached_failures() {
    let db = Arc::new(crate::query_db::QueryDb::default());
    let frontend = dm_tree::frontend::build(
        Path::new("memo-operation.dme"),
        &Source,
        &Default::default(),
        1,
    )
    .unwrap()
    .with_body_queries(db.clone());
    let body = &frontend.bodies[0];
    let arena = dm_tree::frontend::BodyArena::new(&frontend);
    let current = PreparedBody::issue(&frontend, body).unwrap();
    let host = frontend.snapshot.tree.as_ref();
    let policy = Policy(AtomicBool::new(true));
    let memo = crate::lowering_memo::ProcedureMemo::new(17);
    let error = admit_one_input_checked(
        &frontend,
        body,
        host,
        None,
        None,
        None,
        &policy,
        None,
        Some(&memo),
        &arena,
        false,
        false,
        false,
        None,
        Some(&current),
    )
    .err()
    .expect("actual issued preparation IO");
    assert!(
        matches!(error,LoweringFailure::Operational(ref error) if error.raw_os_error()==Some(1450))
    );
    assert_eq!(db.db().stats(dm_query::Kind(4)).computed, 0);
    assert!(memo.values.is_empty());
    let scheduled = db.fail_body_syntax_after_for_test(0, std::io::Error::from_raw_os_error(1450));
    let error = admit_one_input_checked(
        &frontend,
        body,
        host,
        None,
        None,
        None,
        &policy,
        None,
        Some(&memo),
        &arena,
        false,
        false,
        false,
        None,
        Some(&current),
    )
    .err()
    .expect("actual original body IO");
    assert!(
        matches!(error,LoweringFailure::Operational(ref error) if error.raw_os_error()==Some(1450))
    );
    drop(scheduled);
    assert!(memo.values.is_empty());
    let completed = admit_one_input_checked(
        &frontend,
        body,
        host,
        None,
        None,
        None,
        &policy,
        None,
        Some(&memo),
        &arena,
        false,
        false,
        false,
        None,
        Some(&current),
    )
    .unwrap()
    .finish()
    .unwrap();
    let actual = completed.into_lowered();
    assert_eq!(db.db().stats(dm_query::Kind(4)).computed, 1);
    let fresh_arena = dm_tree::frontend::BodyArena::new(&frontend);
    let fresh = lower_one(
        &frontend,
        body,
        host,
        &policy,
        None,
        &fresh_arena,
        false,
        Some(current.source()),
    )
    .unwrap();
    assert_eq!(actual.code.procedure, fresh.code.procedure);
    let warm_arena = dm_tree::frontend::BodyArena::new(&frontend);
    let warm = admit_one_input_checked(
        &frontend,
        body,
        host,
        None,
        None,
        None,
        &policy,
        None,
        Some(&memo),
        &warm_arena,
        false,
        false,
        false,
        None,
        Some(&current),
    )
    .unwrap()
    .finish()
    .unwrap()
    .into_lowered();
    assert_eq!(warm.code.procedure, fresh.code.procedure);
    assert_eq!(memo.counts.resident_hits.load(Ordering::Relaxed), 1);
}

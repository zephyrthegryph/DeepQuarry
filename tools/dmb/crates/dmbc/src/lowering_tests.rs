use super::*;
use dm_ir::{ResolveQuery, ResolvedMeaning};
use std::{collections::BTreeMap, path::Path};
struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
struct Host;
impl Resolver for Host {
    fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
        ResolvedMeaning::Unsupported(query)
    }
}
struct NoParameters;
impl AbiPolicy for NoParameters {
    fn inputs(
        &self,
        _: UnitIdentity,
        metadata: &ProcedureMetadata,
        _: &SymbolTable,
        _: &SourceLocation,
    ) -> Result<ProcedureInputs, String> {
        if !metadata.signature.parameters.is_empty() || metadata.signature.variadic {
            return Err("no-parameter policy does not know parameter ABI".into());
        }
        Ok(ProcedureInputs::default())
    }
}
fn frontend(source: &'static str) -> ColdFrontend {
    dm_tree::frontend::build(
        Path::new("project.dme"),
        &Source(source),
        &BTreeMap::new(),
        1,
    )
    .unwrap()
}
#[path = "lowering_tests/memo_replay.rs"]
mod memo_replay;
#[path = "lowering_tests/semantics.rs"]
mod semantics;

#[path = "lowering_tests/body_arena.rs"]
mod body_arena;

#[path = "lowering_tests/inherited_call_capture.rs"]
mod inherited_call_capture;

#[path = "lowering_tests/completion.rs"]
mod completion;

#[path = "lowering_tests/disk_only.rs"]
mod disk_only;

#[path = "lowering_tests/owned_prepare.rs"]
mod owned_prepare;

#[path = "lowering_tests/reference_capture.rs"]
mod reference_capture;

#[path = "lowering_tests/incomplete_expression.rs"]
mod incomplete_expression;

#[path = "lowering_tests/initializer_instance_calls.rs"]
mod initializer_instance_calls;

#[test]
fn checked_lower_leaf_original_body_io_leaves_arena_retryable_and_words_unchanged() {
    let queries = Arc::new(crate::query_db::QueryDb::default());
    let front = frontend("/proc/probe()\n    return 7\n").with_body_queries(queries.clone());
    let body = &front.bodies[0];
    let arena = dm_tree::frontend::BodyArena::new(&front);
    let schedule =
        queries.fail_body_syntax_after_for_test(0, std::io::Error::from_raw_os_error(1450));
    match lower_one_checked(
        &front,
        body,
        &Host,
        &NoParameters,
        None,
        &arena,
        false,
        None,
    )
    .err()
    .expect("actual original body failure")
    {
        LoweringFailure::Operational(error) => assert_eq!(error.raw_os_error(), Some(1450)),
        other => panic!("IO became lowering diagnostics: {other:?}"),
    }
    drop(schedule);
    let checked = lower_one_checked(
        &front,
        body,
        &Host,
        &NoParameters,
        None,
        &arena,
        false,
        None,
    )
    .unwrap();
    let legacy_arena = dm_tree::frontend::BodyArena::new(&front);
    let legacy = lower_one(
        &front,
        body,
        &Host,
        &NoParameters,
        None,
        &legacy_arena,
        false,
        None,
    )
    .unwrap();
    assert_eq!(checked.code.procedure, legacy.code.procedure);
    assert_eq!(queries.db().stats(dm_query::Kind(4)).computed, 1);
}
#[test]
fn checked_lower_leaf_uses_typed_abi_hook_and_preserves_actual_cause() {
    struct ActualAbiOperation;
    impl AbiPolicy for ActualAbiOperation {
        fn inputs(
            &self,
            _: UnitIdentity,
            _: &ProcedureMetadata,
            _: &SymbolTable,
            _: &SourceLocation,
        ) -> Result<ProcedureInputs, String> {
            Ok(ProcedureInputs::default())
        }
        fn prepare_owned_captured(
            &self,
            _: &ProcedureMetadata,
            _: dm_tree::frontend::ParsedBody<'_>,
            _: &AbiContext<'_>,
        ) -> Result<OwnedPreparedBody, String> {
            panic!("checked native path must not call compatibility ABI hook")
        }
        fn prepare_owned_captured_checked(
            &self,
            _: &ProcedureMetadata,
            _: dm_tree::frontend::ParsedBody<'_>,
            _: &AbiContext<'_>,
        ) -> Result<OwnedPreparedBody, dm_codegen_byond::procedure_abi::AbiError> {
            Err(dm_codegen_byond::procedure_abi::AbiError::operational(
                std::io::Error::from_raw_os_error(1450),
            ))
        }
    }
    let front = frontend("/proc/probe()\n    return 7\n");
    let arena = dm_tree::frontend::BodyArena::new(&front);
    match lower_one_checked(
        &front,
        &front.bodies[0],
        &Host,
        &ActualAbiOperation,
        None,
        &arena,
        false,
        None,
    )
    .err()
    .expect("actual ABI failure")
    {
        LoweringFailure::Operational(error) => assert_eq!(error.raw_os_error(), Some(1450)),
        other => panic!("ABI IO became unsupported/source diagnostics: {other:?}"),
    }
}
#[test]
fn checked_leaf_default_preserves_custom_owned_hook_and_genuine_source_class() {
    struct CustomOwned(std::sync::atomic::AtomicBool);
    impl AbiPolicy for CustomOwned {
        fn inputs(
            &self,
            _: UnitIdentity,
            _: &ProcedureMetadata,
            _: &SymbolTable,
            _: &SourceLocation,
        ) -> Result<ProcedureInputs, String> {
            Ok(ProcedureInputs::default())
        }
        fn prepare_owned_captured(
            &self,
            metadata: &ProcedureMetadata,
            parsed: dm_tree::frontend::ParsedBody<'_>,
            context: &AbiContext<'_>,
        ) -> Result<OwnedPreparedBody, String> {
            self.0.store(true, std::sync::atomic::Ordering::Relaxed);
            let prepared = self.prepare(metadata, parsed.item(), context)?;
            let mut header = parsed.into_item();
            header.children.clear();
            Ok((prepared, header, None))
        }
    }
    let front = frontend("/proc/probe()\n    return 7\n");
    let arena = dm_tree::frontend::BodyArena::new(&front);
    let custom = CustomOwned(std::sync::atomic::AtomicBool::new(false));
    lower_one_checked(
        &front,
        &front.bodies[0],
        &Host,
        &custom,
        None,
        &arena,
        false,
        None,
    )
    .unwrap();
    assert!(custom.0.load(std::sync::atomic::Ordering::Relaxed));
    struct SourceFailure;
    impl AbiPolicy for SourceFailure {
        fn inputs(
            &self,
            _: UnitIdentity,
            _: &ProcedureMetadata,
            _: &SymbolTable,
            _: &SourceLocation,
        ) -> Result<ProcedureInputs, String> {
            Ok(ProcedureInputs::default())
        }
        fn prepare_owned_captured_checked(
            &self,
            _: &ProcedureMetadata,
            _: dm_tree::frontend::ParsedBody<'_>,
            _: &AbiContext<'_>,
        ) -> Result<OwnedPreparedBody, dm_codegen_byond::procedure_abi::AbiError> {
            Err(dm_codegen_byond::procedure_abi::AbiError::source(
                "genuine checked source classification",
            ))
        }
    }
    let arena = dm_tree::frontend::BodyArena::new(&front);
    match lower_one_checked(
        &front,
        &front.bodies[0],
        &Host,
        &SourceFailure,
        None,
        &arena,
        false,
        None,
    )
    .err()
    .unwrap()
    {
        LoweringFailure::Diagnostics(rows) => {
            assert_eq!(rows.len(), 1);
            assert_eq!(rows[0].kind, DiagnosticKind::SourceError);
            assert_eq!(rows[0].origin, front.bodies[0].source);
        }
        other => panic!("source error became operational: {other:?}"),
    }
}

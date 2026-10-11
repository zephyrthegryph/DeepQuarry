use super::*;
use crate::lowering::{AbiPolicy, LoweringConfig, LoweringExecution, UnitIdentity};
use dm_ir::{ProcedureMetadata, ResolveQuery, ResolvedMeaning, Resolver, SymbolId, SymbolTable};
use dm_tree::frontend::{ColdFrontend, SourceLocation};
use std::path::Path;
struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
struct MissingCall<'a>(&'a dm_tree::SemanticTree);
impl Resolver for MissingCall<'_> {
    fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
        match query {
            ResolveQuery::GlobalProc(name) | ResolveQuery::Proc { name, .. }
                if name == SymbolId::of("missing_initializer") =>
            {
                ResolvedMeaning::Missing
            }
            ResolveQuery::HasMemberProc { name, .. }
                if name == SymbolId::of("missing_initializer") =>
            {
                ResolvedMeaning::Presence(false)
            }
            _ => self.0.resolve(query),
        }
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
    ) -> Result<dm_codegen_byond::ProcedureInputs, String> {
        if !metadata.signature.parameters.is_empty() || metadata.signature.variadic {
            return Err("fixture requires issued no-argument signature".into());
        }
        Ok(Default::default())
    }
}
fn frontend() -> ColdFrontend {
    dm_tree::frontend::build(Path::new("diagnostics.dme"),
        &Source("var/value = missing_initializer()\n/proc/broken()\n    var/duplicate = 1\n    var/duplicate = 2\n    return duplicate\n/proc/good()\n    return 7\n"),
        &Default::default(), 1).unwrap()
}
#[test]
fn initializer_source_rejection_collects_actual_current_body_errors_without_memo() {
    let frontend = frontend();
    let bodies = dm_tree::frontend::BodyArena::new_typed(
        &frontend,
        dm_codegen_byond::typed_statements_supported_for_capture,
    );
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let startup =
        crate::startup::capture_with_executor_and_bodies(&frontend, &[], &executor, &bodies)
            .unwrap();
    let host = MissingCall(frontend.snapshot.tree.as_ref());
    let evaluator = crate::driver_facts::DriverEvaluator {
        pure_calls: None,
        resource_search_context: None,
        resolver: &host,
        symbols: startup.plan().symbols.as_ref(),
    };
    let error =
        crate::initializer_lowering::lower_captured(&frontend, &startup, &evaluator, &host, None)
            .err()
            .expect("actual initializer producer rejects certified missing call");
    let InitializerLoweringError::Diagnostics(original) = &error else {
        panic!("actual typed initializer source diagnostics expected");
    };
    assert_eq!(original.len(), 1);
    assert_eq!(original[0].kind, DiagnosticKind::SourceError);
    assert_eq!(original[0].origin.line, 1);
    let original_message = original[0].message.clone();
    let combined = collect(error, || {
        crate::lowering::lower_frontend_with_statics_on_executor_and_bodies(
            &frontend,
            &host,
            &NoParameters,
            LoweringConfig::default(),
            &startup,
            LoweringExecution::new(&executor, &bodies),
        )
        .diagnostics
    });
    let ColdError::Lowering(combined) = combined else {
        panic!("typed source diagnostics expected")
    };
    assert_eq!(combined.len(), 2);
    assert_eq!(combined[0].message, original_message);
    assert_eq!(combined[0].origin.line, 1);
    assert_eq!(combined[1].message, "duplicate: duplicate definition");
    assert_eq!(combined[1].origin.line, 4);
    assert_eq!(combined[1].related[0].origin.line, 3);
    assert!(combined
        .iter()
        .all(|diagnostic| diagnostic.kind == DiagnosticKind::SourceError));
}
#[test]
fn non_source_initializer_rejections_never_run_body_continuation() {
    let frontend = frontend();
    let origin = frontend.location(0).unwrap();
    for kind in [DiagnosticKind::UnsupportedModel, DiagnosticKind::Internal] {
        let error = InitializerLoweringError::Diagnostics(vec![LoweringDiagnostic {
            kind,
            identity: None,
            origin: origin.clone(),
            message: "typed guard fixture".into(),
            related: Vec::new(),
        }]);
        let _ = collect(error, || {
            panic!("non-source typed diagnostics cannot continue")
        });
    }
    for error in [
        InitializerLoweringError::Unsupported("unsupported fixture".into()),
        InitializerLoweringError::Invariant("invariant fixture".into()),
        InitializerLoweringError::Diagnostics(Vec::new()),
    ] {
        let _ = collect(error, || panic!("continuation must not run"));
    }
}

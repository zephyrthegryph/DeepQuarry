use super::*;
use std::sync::atomic::{AtomicBool, Ordering};

struct BorrowedPolicy(AtomicBool);
impl AbiPolicy for BorrowedPolicy {
    fn inputs(
        &self,
        _: UnitIdentity,
        _: &ProcedureMetadata,
        _: &SymbolTable,
        _: &SourceLocation,
    ) -> Result<ProcedureInputs, String> {
        Ok(ProcedureInputs::default())
    }
    fn prepare_captured(
        &self,
        metadata: &ProcedureMetadata,
        parsed: &dm_tree::frontend::ParsedBody<'_>,
        context: &AbiContext<'_>,
    ) -> Result<PreparedUnit, String> {
        assert!(!parsed.item().children.is_empty());
        self.0.store(true, Ordering::Relaxed);
        self.prepare(metadata, parsed.item(), context)
    }
}

#[test]
fn owned_preparation_preserves_borrowed_custom_policy_and_exact_header() {
    let frontend = frontend("/proc/p()\n    return 7\n");
    let body = &frontend.bodies[0];
    let identity = crate::lowering::source_unit_identity(&frontend, body)
        .unwrap()
        .identity;
    let tree = frontend.snapshot.tree.as_ref();
    let member = tree.member(body.member).unwrap();
    let metadata = member.metadata.procedure.as_ref().unwrap();
    let parsed = frontend.parse_body(body).unwrap();
    let header = parsed.item().header.clone();
    let span = parsed.item().header_span;
    let policy = BorrowedPolicy(AtomicBool::new(false));
    let context = AbiContext {
        identity,
        symbols: tree.symbols(),
        origin: &body.source,
        resolver: &Host,
    };
    let (prepared, retained_header, statements) = policy
        .prepare_owned_captured(metadata, parsed, &context)
        .unwrap();
    assert!(statements.is_none());
    assert!(policy.0.load(Ordering::Relaxed));
    assert!(!prepared.executable_body.is_empty());
    assert_eq!(retained_header.header, header);
    assert_eq!(retained_header.header_span, span);
    assert!(retained_header.children.is_empty());
}

#[test]
fn production_statement_model_matches_lossless_settings_statics_and_debug() {
    use crate::driver_facts::{prepare_pinned_source_abi, FrozenPreparedPolicy};
    let engine = crate::engine::EngineSnapshot::from_bytes(
        include_bytes!("../../../../fixtures/native_template.bin"),
        1,
    )
    .unwrap();
    let seed = engine.frontend_seed();
    let frontend = dm_tree::frontend::build_with_config(
        Path::new("project.dme"),
        &Source("/proc/p()\n    set name = \"Display\"\n    var/static/count = 2\n    if(count)\n        set waitfor = 0\n        return count\n    return 0\n"),
        &Default::default(),
        dm_tree::frontend::FrontendConfig { workers: 1, engine: Some(&seed), observer: None },
    ).unwrap();
    let startup = crate::startup::capture(&frontend).unwrap();
    let host = startup
        .resolver(&frontend, frontend.snapshot.tree.as_ref())
        .unwrap();
    let abi = prepare_pinned_source_abi(&frontend, &engine, &host, None, 1).unwrap();
    assert!(
        abi.prepared.diagnostics.is_empty(),
        "{:?}",
        abi.prepared.diagnostics
    );
    let policy = FrozenPreparedPolicy::new(&frontend, &abi.prepared).unwrap();
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let raw = dm_tree::frontend::BodyArena::new(&frontend);
    let typed = dm_tree::frontend::BodyArena::new_typed(
        &frontend,
        dm_codegen_byond::typed_statements_supported_for_capture,
    );
    let body = &frontend.bodies[0];
    let statement_ptr = typed
        .with_parsed(body, |parsed| {
            assert!(parsed.item().children.is_empty());
            let facts = dm_tree::procedure_statics::capture_issued_statements(
                startup.procedure(body.declaration).unwrap().procedure,
                parsed.statement_body().unwrap(),
            )
            .unwrap();
            assert_eq!(
                facts.declarations,
                startup.procedure(body.declaration).unwrap().declarations
            );
            parsed
                .statement_body()
                .unwrap()
                .parsed()
                .statements
                .as_ptr()
        })
        .unwrap();
    let authored = typed
        .with_parsed(body, |parsed| parsed.shared_statement_body().unwrap())
        .unwrap();
    let authored_count = authored.parsed().statements.len();
    let authored_header = authored.parsed().statements[0].raw_header.as_ptr();
    assert!(!statement_ptr.is_null());
    let before = lower_frontend_with_statics_on_executor_and_bodies(
        &frontend,
        &host,
        &policy,
        LoweringConfig::default(),
        &startup,
        LoweringExecution::new(&executor, &raw),
    );
    let after = lower_frontend_with_statics_on_executor_and_bodies(
        &frontend,
        &host,
        &policy,
        LoweringConfig::default(),
        &startup,
        LoweringExecution::new(&executor, &typed),
    );
    assert!(before.diagnostics.is_empty(), "{:?}", before.diagnostics);
    assert!(after.diagnostics.is_empty(), "{:?}", after.diagnostics);
    assert_eq!(authored.parsed().statements.len(), authored_count);
    assert_eq!(
        authored.parsed().statements[0].raw_header.as_ptr(),
        authored_header
    );
    assert!(matches!(
        authored.parsed().statements[0].kind,
        dm_syntax::StatementKind::Set { .. }
    ));
    assert!(matches!(
        authored.parsed().statements[1].kind,
        dm_syntax::StatementKind::Var { .. }
    ));
    assert_eq!(std::sync::Arc::strong_count(&authored), 1);
    assert_eq!(before.units.len(), after.units.len());
    for (raw, typed) in before.units.iter().zip(&after.units) {
        assert_eq!(raw.code.procedure, typed.code.procedure);
        assert_eq!(raw.debug_origins, typed.debug_origins);
        assert_eq!(raw.metadata, typed.metadata);
    }
}

use super::*;
use std::path::Path;
struct Source;
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok("/datum/probe\n    var/value = 7\n    proc/read(argument)\n        var/static/shared = 2\n        return value + argument + shared\n".into())
    }
}
#[test]
fn resident_selected_model_uses_same_producer_after_frontend_release() {
    let mut host = crate::runner_host::BuildHost::one_shot();
    let engine = host
        .engine(
            "project.dme".into(),
            Default::default(),
            true,
            include_bytes!("../../../fixtures/native_template.bin").to_vec(),
        )
        .unwrap();
    let frontend = dm_tree::frontend::FrontendRevision::new(
        dm_tree::frontend::build_with_config(
            Path::new("project.dme"),
            &Source,
            &Default::default(),
            dm_tree::frontend::FrontendConfig {
                workers: 1,
                engine: Some(engine.frontend_seed()),
                observer: None,
            },
        )
        .unwrap(),
    );
    let (resolver, _) =
        crate::request_runner::runner_facts::prepare(&frontend, &engine.snapshot).unwrap();
    let links = engine.link_overlay().unwrap();
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let memo = crate::lowering_memo::ProcedureMemo::new(123);
    let mut expected = Vec::new();
    crate::analysis_export::write_resolved_selected(
        &frontend,
        &engine.snapshot,
        &resolver,
        &links.inventory.spellings,
        &executor,
        &memo,
        &mut io::sink(),
        None,
        |row: &crate::selected_query::CurrentProcedureReferences| -> std::io::Result<()> {
            row.write_jsonl(&mut expected)?;
            Ok(())
        },
    )
    .unwrap();
    let bodies = dm_tree::frontend::BodyArena::new_typed(
        &frontend,
        dm_codegen_byond::typed_statements_supported_for_capture,
    );
    let startup = crate::startup::capture_revision_facts_with_executor_and_bodies(
        &frontend,
        &links.inventory.spellings,
        &executor,
        &bodies,
    )
    .unwrap();
    let startup_view = startup.view_revision(&frontend).unwrap();
    let prepared =
        crate::driver_facts::prepare_pinned_source_abi_with_startup_on_executor_with_artifacts(
            &frontend,
            &engine.snapshot,
            &resolver,
            &startup_view,
            None,
            &executor,
            None,
        )
        .unwrap();
    assert!(prepared.prepared.diagnostics.is_empty());
    let archive = frontend.body_archive().unwrap();
    let declaration = frontend.bodies[0].declaration.0;
    let resolver = NativeResourceResolver::from_shared_symbols(
        resolver,
        frontend.snapshot.tree.shared_symbols(),
        Default::default(),
        [],
        [],
    )
    .unwrap();
    let context = ResolvedContext::new(
        resolver,
        Arc::clone(prepared.prepared.units_owner()),
        Arc::clone(&startup),
    );
    assert!(context.resolver.resources().is_none());
    drop(prepared);
    drop(startup_view);
    drop(startup);
    drop(bodies);
    drop(frontend);
    let current = context.query(&archive, declaration).unwrap();
    let mut actual = Vec::new();
    current.write_jsonl(&mut actual).unwrap();
    assert_eq!(actual, expected);
    assert!(context.query(&archive, u32::MAX).is_err());
}

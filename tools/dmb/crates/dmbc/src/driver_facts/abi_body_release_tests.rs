//! ABI-only retention must not replace the current executable-body consumer.
use super::*;
use crate::lowering::AbiPolicy;
use std::path::Path;
struct Source;
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok("/datum/probe/proc/p(x)\n    set waitfor = 0\n    return x + 7\n".into())
    }
}
#[test]
fn abi_roster_releases_bodies_and_current_consumer_matches_artifact_path() {
    let engine_owner = crate::runner_host::EnginePayload::capture(
        include_bytes!("../../../../fixtures/native_template.bin").to_vec(),
        1,
        true,
        0,
    )
    .unwrap();
    let engine = &engine_owner.snapshot;
    let seed = engine.frontend_seed();
    let front = dm_tree::frontend::build_with_config(
        Path::new("abi-body.dme"),
        &Source,
        &Default::default(),
        dm_tree::frontend::FrontendConfig {
            workers: 1,
            engine: Some(&seed),
            observer: None,
        },
    )
    .unwrap();
    let startup = crate::startup::capture(&front).unwrap();
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let store = AbiArtifacts::with_engine_owner(Arc::clone(&engine_owner));
    let prepare = |artifacts| {
        prepare_pinned_source_abi_with_startup_on_executor_with_artifacts(
            &front,
            &engine,
            front.snapshot.tree.as_ref(),
            &startup,
            None,
            &executor,
            artifacts,
        )
        .unwrap()
    };
    let plain = prepare(None);
    let retained = prepare(Some(&store));
    assert!(
        plain.prepared.diagnostics.is_empty(),
        "{:?}",
        plain.prepared.diagnostics
    );
    assert!(retained.prepared.diagnostics.is_empty());
    for (_, unit) in plain
        .prepared
        .units()
        .iter()
        .chain(retained.prepared.units())
    {
        assert!(unit.executable_body.is_empty());
    }
    let body = &front.bodies[0];
    let parsed = front.parse_body(body).unwrap();
    let identity = startup
        .unit_members()
        .iter()
        .find(|(_, member)| **member == body.member)
        .unwrap()
        .0;
    let metadata = front
        .snapshot
        .tree
        .member(body.member)
        .unwrap()
        .metadata
        .procedure
        .as_ref()
        .unwrap();
    let context = AbiContext {
        identity: *identity,
        symbols: front.snapshot.tree.symbols(),
        origin: &body.source,
        resolver: front.snapshot.tree.as_ref(),
    };
    let consume = |prepared: &PreparedSourceAbi| {
        let policy = FrozenPreparedPolicy::new(&front, prepared).unwrap();
        let unit = policy
            .prepare_captured(metadata, &parsed, &context)
            .unwrap();
        assert!(!unit.executable_body.is_empty());
        assert!(unit
            .executable_body
            .iter()
            .all(|item| !item.header.starts_with("set ")));
        let code = dm_codegen_byond::compile_simple_proc_with_resolver(
            &unit.executable_body,
            &unit.inputs,
            context.symbols,
            front.snapshot.tree.as_ref(),
        )
        .unwrap();
        assert!(code.modified_instances.is_empty());
        assert!(code.procedure_values.is_empty());
        assert!(code.procedure_statics.is_empty());
        assert!(code.slots.is_empty());
        assert!(code.resources.is_empty());
        assert!(code.instances.is_empty());
        (unit.abi.unwrap().canonical_bytes(), code.procedure)
    };
    assert_eq!(consume(&plain.prepared), consume(&retained.prepared));
}

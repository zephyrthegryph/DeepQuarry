use super::*;
use std::path::Path;
struct Source;
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok("/proc/probe()\n    return 7\n".into())
    }
}
struct NoSourceTypeDefaults;
impl crate::class_projection::TypeValuePolicy for NoSourceTypeDefaults {
    fn tag(&self, _: dm_ir::SymbolId) -> Result<u8, crate::class_projection::ProjectionError> {
        Err(crate::class_projection::ProjectionError::Unsupported(
            "fixture has no source type defaults".into(),
        ))
    }
}
fn compile(host: &mut BuildHost) -> Vec<u8> {
    let bytes = include_bytes!("../../../fixtures/native_template.bin");
    let engine = host
        .engine(
            PathBuf::from("pressure.dme"),
            Default::default(),
            true,
            bytes.to_vec(),
        )
        .unwrap();
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let frontend = dm_tree::frontend::build_with_executor_and_semantic_state(
        Path::new("pressure.dme"),
        &Source,
        &Default::default(),
        dm_tree::frontend::FrontendConfig {
            workers: 1,
            engine: Some(engine.frontend_seed()),
            observer: None,
        },
        None,
        &executor,
        host.semantic.as_mut(),
    )
    .unwrap();
    let facts = host.host_facts();
    let (resolver, _scalar) =
        crate::request_runner::runner_facts::prepare_retained(&frontend, &engine, facts.as_deref())
            .unwrap();
    let memo = host.procedure_memo(17, None, true);
    crate::compile_driver::compile_observed_with_memo(
        &frontend,
        &resolver,
        &engine.snapshot,
        &engine.bytes,
        engine.link_overlay().unwrap(),
        &NoSourceTypeDefaults,
        None,
        Vec::new(),
        None,
        1,
        None,
        memo.as_ref(),
    )
    .unwrap()
    .dmb
    .bytes()
    .to_vec()
}
#[test]
fn compiler_pressure_tier_preserves_semantic_owner_and_regenerates_fresh_equal_output() {
    let mut host = BuildHost::default();
    let before = compile(&mut host);
    let tree = Arc::clone(host.semantic.as_ref().unwrap().snapshot_tree().unwrap());
    let old = host.procedure_memo(17, None, true).unwrap();
    let old_facts = host.host_facts().unwrap();
    let symbolic_owner = Arc::clone(&host.symbolic.as_ref().unwrap().1);
    host.release_idle_compiler_artifacts();
    assert!(Arc::ptr_eq(
        &tree,
        host.semantic.as_ref().unwrap().snapshot_tree().unwrap()
    ));
    assert!(
        Arc::ptr_eq(&symbolic_owner, &host.symbolic.as_ref().unwrap().1),
        "compiler pressure preserves the bounded published symbolic owner"
    );
    assert!(
        host.abi.is_some(),
        "compact ABI facade retains its explicit engine baseline"
    );
    assert!(
        host.startup.is_some(),
        "compact startup facade remains bounded"
    );
    assert!(host.generation.is_none());
    assert!(host.host_facts.is_none());
    let regenerated = host.procedure_memo(17, None, true).unwrap();
    assert!(!Arc::ptr_eq(&old.values, &regenerated.values));
    assert!(!Arc::ptr_eq(
        old.symbolic.as_ref().unwrap(),
        regenerated.symbolic.as_ref().unwrap()
    ));
    assert!(!Arc::ptr_eq(&old_facts, &host.host_facts().unwrap()));
    // The published owner survives; each request facade has its own lease.
    assert!(Arc::ptr_eq(
        &symbolic_owner,
        &host.symbolic.as_ref().unwrap().1
    ));
    // Escaped rich request handles remain detached from the new rich owner.
    drop(old);
    drop(old_facts);
    let after = compile(&mut host);
    assert!(Arc::ptr_eq(
        &tree,
        host.semantic.as_ref().unwrap().snapshot_tree().unwrap()
    ));
    let fresh = compile(&mut BuildHost::one_shot());
    assert_eq!(before, after);
    assert_eq!(after, fresh);
}

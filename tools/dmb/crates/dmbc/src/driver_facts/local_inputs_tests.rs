use super::*;
use crate::lowering::AbiPolicy;
use dm_ir::SymbolTable;
use std::sync::Arc;
struct Source;
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &std::path::Path) -> Result<String, String> {
        Ok("/datum/a/proc/p(x = 7)\n    return x\n".into())
    }
}
#[test]
fn local_input_license_shares_actual_units_and_declines_foreign_source_and_symbols() {
    let engine = crate::runner_host::EnginePayload::capture(
        include_bytes!("../../../../fixtures/native_template.bin").to_vec(),
        1,
        true,
        0,
    )
    .unwrap();
    let seed = engine.snapshot.frontend_seed();
    let build = || {
        dm_tree::frontend::build_with_config(
            std::path::Path::new("local.dme"),
            &Source,
            &Default::default(),
            dm_tree::frontend::FrontendConfig {
                workers: 1,
                engine: Some(&seed),
                observer: None,
            },
        )
        .unwrap()
    };
    let front = build();
    let foreign = build();
    let startup = crate::startup::capture(&front).unwrap();
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let prepared =
        crate::driver_facts::prepare_pinned_source_abi_with_startup_on_executor_with_artifacts(
            &front,
            &engine.snapshot,
            front.snapshot.tree.as_ref(),
            &startup,
            None,
            &executor,
            None,
        )
        .unwrap();
    assert!(
        prepared.prepared.diagnostics.is_empty(),
        "{:?}",
        prepared.prepared.diagnostics
    );
    let policy =
        crate::driver_facts::FrozenPreparedPolicy::new(&front, &prepared.prepared).unwrap();
    let roster = crate::lowering::PreparedBodyRoster::issue(&front)
        .ok()
        .unwrap();
    let foreign_roster = crate::lowering::PreparedBodyRoster::issue(&foreign)
        .ok()
        .unwrap();
    let license = policy
        .current_local_inputs(&front, front.snapshot.tree.symbols())
        .unwrap();
    let current = license.prepared(roster.ordered().next().unwrap()).unwrap();
    let actual = &prepared.prepared.units()[0].1;
    assert!(Arc::ptr_eq(&current.inputs, &actual.inputs));
    assert!(Arc::ptr_eq(
        current.abi.as_ref().unwrap(),
        actual.abi.as_ref().unwrap()
    ));
    assert!(current.executable_body.is_empty());
    assert!(license
        .prepared(foreign_roster.ordered().next().unwrap())
        .is_none());
    assert!(policy
        .current_local_inputs(&foreign, foreign.snapshot.tree.symbols())
        .is_none());
    assert!(policy
        .current_local_inputs(&front, &SymbolTable::default())
        .is_none());
}

use super::*;
use std::path::Path;
struct Source(String);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.clone())
    }
}
#[test]
fn uncaptured_high_ordinal_demand_uses_current_body_and_rejects_stale_pins() {
    let mut host = crate::runner_host::BuildHost::one_shot();
    let engine = host
        .engine(
            "project.dme".into(),
            Default::default(),
            true,
            include_bytes!("../../../fixtures/native_template.bin").to_vec(),
        )
        .unwrap();
    let build = |prefix: &str, result: u32| {
        let mut source = prefix.to_string();
        for index in 0..270 {
            source.push_str(&format!("/proc/query_{index}()\n    return {result}\n"));
        }
        dm_tree::frontend::FrontendRevision::new(
            dm_tree::frontend::build_with_config(
                Path::new("project.dme"),
                &Source(source),
                &Default::default(),
                dm_tree::frontend::FrontendConfig {
                    workers: 1,
                    engine: Some(engine.frontend_seed()),
                    observer: None,
                },
            )
            .unwrap(),
        )
    };
    let original = build("", 1);
    let request = |frontend: &dm_tree::frontend::FrontendRevision| QueryRequest {
        timeout_seconds: None,
        project: "project.dme".into(),
        defines: Default::default(),
        engine_template: None,
        bootstrap_catalog: true,
        expected_revision: Some(format!("{:032x}", frontend.snapshot.tree.identity())),
        expected_source_revision: Some(format!(
            "{:032x}",
            dm_analysis::tree_export::source_revision(frontend)
        )),
        queries: vec![],
        source_queries: vec![SourceQuery::SelectedReferences {
            ordinal: frontend.bodies.last().unwrap().declaration.0,
        }],
    };
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let memo = crate::lowering_memo::ProcedureMemo::new(123);
    let mut demand = Demand {
        request: request(&original),
        reply: None,
    };
    demand
        .complete(&original, &engine, None, &executor, Some(&memo), 123)
        .unwrap();
    let reply = demand.reply.take().unwrap();
    assert!(reply.jsonl.contains("selected_reference"));
    let row: serde_json::Value = serde_json::from_str(reply.jsonl.trim()).unwrap();
    assert_eq!(
        row["occurrence"],
        original.bodies.last().unwrap().declaration.0
    );
    let shifted = build("// current source shift\n", 2);
    assert!(demand
        .complete(&shifted, &engine, None, &executor, Some(&memo), 123)
        .is_err());
    demand.request = request(&shifted);
    demand
        .complete(&shifted, &engine, None, &executor, Some(&memo), 123)
        .unwrap();
    let shifted_reply = demand.reply.take().unwrap();
    assert_ne!(reply.source_revision, shifted_reply.source_revision);
    assert!(!shifted_reply.complete);
}

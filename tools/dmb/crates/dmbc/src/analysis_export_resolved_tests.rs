//! Real pinned-host/startup/ABI/query fixture; hooked after the active gate closes.
use super::*;
use std::{collections::BTreeMap, path::Path};

struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}

#[test]
fn resolved_export_selects_local_and_binds_shifted_current_coordinates() {
    let mut retained = crate::runner_host::BuildHost::one_shot();
    let engine = retained
        .engine(
            "project.dme".into(),
            BTreeMap::new(),
            true,
            include_bytes!("../../../fixtures/native_template.bin").to_vec(),
        )
        .unwrap();
    let executor = dm_exec::BuildExecutor::new(2).unwrap();
    let memo = crate::lowering_memo::ProcedureMemo::new(123);
    for (source, line) in [
        ("/proc/resolved_probe(x)\n    var/y = x\n    return y\n", 3),
        (
            "\n\n/proc/resolved_probe(x)\n    var/y = x\n    return y\n",
            5,
        ),
    ] {
        let frontend = dm_tree::frontend::FrontendRevision::new(
            dm_tree::frontend::build_with_config(
                Path::new("project.dme"),
                &Source(source),
                &Default::default(),
                dm_tree::frontend::FrontendConfig {
                    workers: 2,
                    engine: Some(engine.frontend_seed()),
                    observer: None,
                },
            )
            .unwrap(),
        );
        let (host, _scalar) = prepare(&frontend, &engine.snapshot).unwrap();
        let links = engine.link_overlay().unwrap();
        let mut bytes = Vec::new();
        assert_eq!(
            crate::analysis_export::write_resolved(
                &frontend,
                &engine.snapshot,
                &host,
                &links.inventory.spellings,
                &executor,
                &memo,
                &mut bytes
            )
            .unwrap(),
            1
        );
        let rows: Vec<serde_json::Value> = std::str::from_utf8(&bytes)
            .unwrap()
            .lines()
            .map(|line| serde_json::from_str(line).unwrap())
            .collect();
        let selected: Vec<_> = rows
            .iter()
            .filter(|row| row["row"] == "selected_reference")
            .collect();
        assert!(!selected.is_empty());
        let local = selected
            .iter()
            .find(|row| row["meaning"]["kind"] == "local")
            .expect("compiler-selected local read");
        assert_eq!(local["source"]["line"], line);
        let start = local["start"].as_u64().unwrap() as usize;
        let end = local["end"].as_u64().unwrap() as usize;
        assert_eq!(&frontend.expanded.text[start..end], "y");
        assert_eq!(
            local["source"]["file"],
            frontend.location(start).unwrap().semantic_path.as_ref()
        );
        assert!(rows
            .iter()
            .any(|row| row["row"] == "selected_reference_summary"
                && row["semantic_resolution_complete"] == false));
        assert!(rows.iter().any(|row| row["row"] == "coverage"
            && row["semantic_resolution_complete"] == false
            && row["diagnostics"] == 0));
    }
}

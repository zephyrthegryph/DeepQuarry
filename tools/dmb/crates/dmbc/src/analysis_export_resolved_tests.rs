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
    check_resolved(false);
}
#[test]
fn selected_completion_preserves_disk_population_and_resident_query_hits() {
    check_resolved(true);
}
fn check_resolved(disk: bool) {
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
    let cache = disk.then(|| {
        let base = if cfg!(windows) {
            std::path::PathBuf::from("E:/dq-cache/dmb-protocol-checks")
        } else {
            std::env::temp_dir()
        };
        let path = base.join(format!(
            "selected-completion-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        dm_cache::Cache::open(path, dm_cache::Limits::default()).unwrap()
    });
    let memo = match &cache {
        Some(cache) => {
            crate::lowering_memo::ProcedureMemo::with_disk(123, cache.snapshot().unwrap())
        }
        None => crate::lowering_memo::ProcedureMemo::new(123),
    };
    let mut last_frontend = None;
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
        last_frontend = Some(frontend);
    }
    if let Some(cache) = cache {
        let records = memo.take_pending();
        assert!(
            !records.is_empty(),
            "query completion preserves ordinary disk population"
        );
        assert!(
            memo.counts
                .resident_hits
                .load(std::sync::atomic::Ordering::Relaxed)
                > 0,
            "shifted query uses admitted resident selections"
        );
        cache.publish(&records).unwrap();
        let frontend = last_frontend.unwrap();
        let (host, _) = prepare(&frontend, &engine.snapshot).unwrap();
        let links = engine.link_overlay().unwrap();
        let mut disk_memo =
            crate::lowering_memo::ProcedureMemo::with_disk_only(123, cache.snapshot().unwrap());
        disk_memo.symbolic = Some(std::sync::Arc::new(Default::default()));
        let mut bytes = Vec::new();
        assert_eq!(
            crate::analysis_export::write_resolved(
                &frontend,
                &engine.snapshot,
                &host,
                &links.inventory.spellings,
                &executor,
                &disk_memo,
                &mut bytes
            )
            .unwrap(),
            1
        );
        assert!(
            disk_memo
                .counts
                .compact_disk_hits
                .load(std::sync::atomic::Ordering::Relaxed)
                > 0,
            "fresh query facade directly admits selected-only disk facts"
        );
        assert_eq!(
            disk_memo
                .counts
                .recomputed
                .load(std::sync::atomic::Ordering::Relaxed),
            0
        );
        let first_disk_hits = disk_memo
            .counts
            .disk_hits
            .load(std::sync::atomic::Ordering::Relaxed);
        let mut repeated = Vec::new();
        crate::analysis_export::write_resolved(
            &frontend,
            &engine.snapshot,
            &host,
            &links.inventory.spellings,
            &executor,
            &disk_memo,
            &mut repeated,
        )
        .unwrap();
        assert_eq!(bytes, repeated);
        assert_eq!(
            disk_memo
                .counts
                .disk_hits
                .load(std::sync::atomic::Ordering::Relaxed),
            first_disk_hits
        );
        assert!(
            disk_memo
                .counts
                .resident_hits
                .load(std::sync::atomic::Ordering::Relaxed)
                > 0
        );
        assert_eq!(
            memo.counts
                .compact_disk_encoded
                .load(std::sync::atomic::Ordering::Relaxed),
            1,
            "query capture publishes bounded selected-only facts"
        );
    }
}

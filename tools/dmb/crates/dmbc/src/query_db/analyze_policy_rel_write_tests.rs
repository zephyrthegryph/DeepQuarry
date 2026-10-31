use super::*;
use crate::{
    input_snapshot::{FolderListing, RecordingInputs, SnapshotProvider, Stamp},
    policy_request::{PolicyInputFile, PolicyInputRequest, PolicyInputRole},
};
#[path = "../../../dm-analysis/examples/support/reference_hierarchy.rs"]
mod reference_hierarchy;
#[derive(Clone)]
struct Source;
impl Source {
    fn bytes(path: &Path) -> io::Result<&'static [u8]> {
        match path.file_name().and_then(|s| s.to_str()) {
            Some("deepquarry.dme") => Ok(b"#include \"code/probe.dm\"\n"),
            Some("probe.dm") => {
                Ok(b"/datum/probe\n    var/link\n    var/datum/persistent\n    proc/save(datum/probe/P)\n        rel_clear(P, nameof(link))\n")
            }
            _ => Err(io::ErrorKind::NotFound.into()),
        }
    }
}
impl SnapshotProvider for Source {
    fn stamp(&self, path: &Path) -> io::Result<Stamp> {
        Ok(Stamp {
            size: Self::bytes(path)?.len() as u64,
            modified_ns: 1,
            file_id: Some(1),
        })
    }
    fn read(&self, path: &Path) -> io::Result<(Stamp, Vec<u8>)> {
        Ok((self.stamp(path)?, Self::bytes(path)?.to_vec()))
    }
    fn list(&self, path: &Path) -> io::Result<FolderListing> {
        Ok(FolderListing::Present(if path.ends_with("code") {
            vec!["probe.dm".into()]
        } else {
            vec!["code".into(), "deepquarry.dme".into()]
        }))
    }
}
fn cohort(db: &Arc<QueryDb>) -> Arc<Cohort> {
    let root = std::env::current_dir()
        .unwrap()
        .join("rel-write-host-query");
    let inputs = RecordingInputs::new(Source, 1);
    let seed = reference_hierarchy::seed();
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let frontend = dm_tree::frontend::build_with_executor_and_semantic_state_for_policy(
        &root.join("deepquarry.dme"),
        &inputs,
        &Default::default(),
        dm_tree::frontend::FrontendConfig {
            workers: 1,
            engine: Some(&seed),
            observer: None,
        },
        None,
        &executor,
        None,
        true,
    )
    .unwrap()
    .with_body_queries(db.clone());
    let intent = PolicyInputRequest {workspace_generators:Vec::new(),
        workspace: None,
        files: vec![PolicyInputFile {
            path: root.join("scopes.toml"),
            role: PolicyInputRole::Configuration,
            required: false,
        }],
        search_folders: vec![],
    }
    .admit()
    .unwrap();
    let capture = Arc::new(
        crate::runner_host::policy_capture::capture(
            &frontend,
            &inputs,
            &intent.capture_files(),
            &[],
        )
        .unwrap()
        .bind_request(&intent)
        .unwrap(),
    );
    db.raw_cohort(capture, &root, &root.join("scopes.toml"))
        .unwrap()
}

#[test]
fn admitted_rel_write_uses_existing_kind10_and_reuses_exact_current_cohort() {
    let db = Arc::new(QueryDb::default());
    let cohort = cohort(&db);
    let first = db
        .analyze_fixture_findings(&cohort, &["rel_write_undeclared".into()])
        .unwrap();
    assert_eq!(first.runs.len(), 1);
    assert_eq!(first.runs[0].name, "rel_write_undeclared");
    assert_eq!(first.runs[0].run.sites.len(), 1);
    assert_eq!(first.runs[0].run.sites[0].rule, "undeclared");
    let computed = db.db.stats(ANALYZE_FINDINGS).computed;
    let second = db
        .analyze_fixture_findings(&cohort, &["rel_write_undeclared".into()])
        .unwrap();
    assert_eq!(first.runs[0].run.sites, second.runs[0].run.sites);
    assert_eq!(db.db.stats(ANALYZE_FINDINGS).computed, computed);
}

#[test]
fn admitted_stored_reference_uses_same_kind10_and_current_original_cohort() {
    let db = Arc::new(QueryDb::default());
    let cohort = cohort(&db);
    let first = db
        .analyze_fixture_findings(&cohort, &["stored_refs".into()])
        .unwrap();
    assert_eq!(first.runs.len(), 1);
    assert_eq!(first.runs[0].name, "stored_refs");
    assert_eq!(first.runs[0].run.sites.len(), 1);
    assert_eq!(first.runs[0].run.sites[0].rule, "var");
    assert_eq!(first.runs[0].run.sites[0].ident, "/datum/probe::persistent");
    let computed = db.db.stats(ANALYZE_FINDINGS).computed;
    let second = db
        .analyze_fixture_findings(&cohort, &["stored_refs".into()])
        .unwrap();
    assert_eq!(first.runs[0].run.sites, second.runs[0].run.sites);
    assert_eq!(db.db.stats(ANALYZE_FINDINGS).computed, computed);
}

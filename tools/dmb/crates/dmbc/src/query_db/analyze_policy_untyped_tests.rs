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
                Ok(b"/datum/probe\n    var/link\n    proc/save(datum/probe/P)\n        link = P\n")
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
    let root = std::env::current_dir().unwrap().join("untyped-host-query");
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
    let intent = PolicyInputRequest {
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
fn admitted_complete_untyped_reuses_kind5_and_records_real_kind10_dependency() {
    let db = Arc::new(QueryDb::default());
    let cohort = cohort(&db);
    let result = db
        .analyze_fixture_findings(&cohort, &["untyped".into()])
        .unwrap();
    assert_eq!(result.runs.len(), 1);
    assert_eq!(result.runs[0].name, "untyped");
    assert!(result.runs[0].run.sites.iter().any(|s| s.rule == "typed"));
    let input = cohort.capture.untyped_input(&[]).unwrap();
    let proof_key = Key::new(
        super::super::super::value_proofs::VALUE_PROOFS,
        input.key().into(),
    );
    assert!(db
        .db
        .dependants(&[proof_key])
        .iter()
        .any(|k| k.kind == ANALYZE_FINDINGS));
    let inferred = db
        .db
        .stats(super::super::super::value_proofs::VALUE_PROOFS)
        .computed;
    let scans = db.db.stats(ANALYZE_FINDINGS).computed;
    let second = db
        .analyze_fixture_findings(&cohort, &["untyped".into()])
        .unwrap();
    assert_eq!(result.runs[0].run.sites, second.runs[0].run.sites);
    assert_eq!(
        db.db
            .stats(super::super::super::value_proofs::VALUE_PROOFS)
            .computed,
        inferred
    );
    assert_eq!(db.db.stats(ANALYZE_FINDINGS).computed, scans);
    assert!(inferred > 0);
}

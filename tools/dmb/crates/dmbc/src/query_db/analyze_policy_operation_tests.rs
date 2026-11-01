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
                Ok(b"#define CAPABILITIES(T) T/proc/capabilities()\n#define TRUE 1\n/datum/probe\n    var/datum/link\nCAPABILITIES(/datum/probe)\n    ref_one(nameof(link), weak = TRUE)\n/datum/probe/proc/save(datum/probe/P)\n    link = P\n")
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
        .join("checked-policy-host-query");
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
    let intent = PolicyInputRequest {workspace_auxiliary:Vec::new(),workspace_generators:Vec::new(),
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
fn checked_source_policies_actual_kind4_io_never_publish_findings_and_same_input_recovers() {
    for policy in [
        "requirement_bool",
        "untyped_member",
        "stored_refs",
        "rel_write_undeclared",
        "weak_raw_read",
    ] {
        for successful_bodies in [0, 1] {
            let db = Arc::new(QueryDb::default());
            let cohort = cohort(&db);
            let schedule = db.fail_body_syntax_after_for_test(
                successful_bodies,
                io::Error::from_raw_os_error(1450),
            );
            let error = db.analyze_fixture_findings(&cohort, &[policy.into()])
                .err().unwrap_or_else(||panic!("{policy} must reach actual Kind4 fault after {successful_bodies} completed body reads"));
            assert_eq!(
                error.raw_os_error(),
                Some(1450),
                "{policy} must preserve original OS failure"
            );
            assert_eq!(
                db.db.stats(ANALYZE_FINDINGS).computed,
                0,
                "no partial/semantic error Outcome: {policy}"
            );
            drop(schedule);
            let first = db
                .analyze_fixture_findings(&cohort, &[policy.into()])
                .unwrap();
            assert_eq!(first.runs.len(), 1);
            assert_eq!(first.runs[0].name, policy);
            let bodies = db.db.stats(Kind(4)).computed;
            let second = db
                .analyze_fixture_findings(&cohort, &[policy.into()])
                .unwrap();
            assert_eq!(first.runs[0].run.sites, second.runs[0].run.sites);
            assert_eq!(db.db.stats(ANALYZE_FINDINGS).computed, 1);
            assert_eq!(
                db.db.stats(Kind(4)).computed,
                bodies,
                "unchanged warm retry shares original body owner"
            );
        }
    }
}

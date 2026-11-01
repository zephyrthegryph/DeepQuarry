//! Real filesystem alias acquisition, no public facts mint source identity.
#![cfg(windows)]
use super::*;
use crate::input_snapshot::{
    FileSystemInputs, FolderListing, SnapshotProvider, SourceAliasChallenge, SourceAliasProof,
    Stamp,
};
use std::sync::atomic::{AtomicUsize, Ordering};
struct Io {
    reads: Arc<AtomicUsize>,
    decline: bool,
}
impl SnapshotProvider for Io {
    fn read(&self, path: &Path) -> io::Result<(Stamp, Vec<u8>)> {
        self.reads.fetch_add(1, Ordering::Relaxed);
        if self.decline
            && path.file_name() == Some(std::ffi::OsStr::new("compiled.dm"))
            && !path.to_string_lossy().starts_with(r"\\?\")
        {
            let bytes = b"/atom\n    var/foreign_dos_key\n".to_vec();
            let mut stamp = FileSystemInputs.stamp(path)?;
            stamp.size = bytes.len() as u64;
            return Ok((stamp, bytes));
        }
        FileSystemInputs.read(path)
    }
    fn stamp(&self, path: &Path) -> io::Result<Stamp> {
        FileSystemInputs.stamp(path)
    }
    fn list(&self, path: &Path) -> io::Result<FolderListing> {
        FileSystemInputs.list(path)
    }
    fn source_alias(
        &self,
        path: &Path,
        challenge: &SourceAliasChallenge,
    ) -> io::Result<Option<SourceAliasProof>> {
        if self.decline {
            Ok(None)
        } else {
            FileSystemInputs.source_alias(path, challenge)
        }
    }
}
fn setup(
    label: &str,
    decline: bool,
) -> (
    PathBuf,
    PathBuf,
    PathBuf,
    Arc<AtomicUsize>,
    RecordingInputs<Io>,
    ColdFrontend,
    Arc<crate::query_db::QueryDb>,
) {
    let root = crate::test_scratch::dir(label);
    std::fs::create_dir_all(root.join("code")).unwrap();
    let source = root.join("code/compiled.dm");
    let config = root.join("scopes.toml");
    std::fs::write(
        &source,
        b"/atom\n    var/native_alias_value\n/proc/alias_fixture_tail()\n    return\n",
    )
    .unwrap();
    std::fs::write(root.join("project.dme"), b"#include \"code/compiled.dm\"\n").unwrap();
    std::fs::write(&config, b"# captured config\n").unwrap();
    let reads = Arc::new(AtomicUsize::new(0));
    let inputs = RecordingInputs::new(
        Io {
            reads: reads.clone(),
            decline,
        },
        4_000_000_000,
    );
    let db = Arc::new(crate::query_db::QueryDb::default());
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let frontend = dm_tree::frontend::build_with_executor_and_semantic_state_for_policy(
        &std::fs::canonicalize(root.join("project.dme")).unwrap(),
        &inputs,
        &Default::default(),
        dm_tree::frontend::FrontendConfig {
            workers: 1,
            engine: None,
            observer: None,
        },
        None,
        &executor,
        None,
        true,
    )
    .unwrap()
    .with_body_queries(db.clone());
    (root, source, config, reads, inputs, frontend, db)
}
fn intent(source: &Path, config: &Path) -> crate::policy_request::AdmittedPolicyRequest {
    use crate::policy_request::*;
    PolicyInputRequest {workspace_auxiliary:Vec::new(),workspace_generators:Vec::new(),
        workspace: None,
        files: vec![
            PolicyInputFile {
                path: source.into(),
                role: PolicyInputRole::DmSource,
                required: true,
            },
            PolicyInputFile {
                path: config.into(),
                role: PolicyInputRole::Configuration,
                required: true,
            },
        ],
        search_folders: vec![],
    }
    .admit()
    .unwrap()
}
#[test]
fn dos_request_reuses_verbatim_acquired_source_once_and_warm_typed_findings_keep_authority() {
    let (root, source, config, reads, inputs, frontend, db) =
        setup("acquired-alias-warm-typed", false);
    let before = reads.load(Ordering::Relaxed);
    let request = intent(&source, &config);
    let captured = Arc::new(
        capture(&frontend, &inputs, &request.capture_files(), &[])
            .unwrap()
            .bind_request(&request)
            .unwrap(),
    );
    assert_eq!(
        reads.load(Ordering::Relaxed),
        before + 1,
        "only configuration bytes read, never alias payload"
    );
    let primary = frontend
        .files
        .iter()
        .find(|file| file.path.file_name() == Some(std::ffi::OsStr::new("compiled.dm")))
        .unwrap();
    assert_ne!(primary.path.as_path(), source.as_path());
    assert!(captured.policy().file(primary.path.as_ref()).is_some());
    assert!(
        captured.policy().file(&source).is_none(),
        "provider key is not rewritten or duplicated"
    );
    assert!(
        std::ptr::eq(
            captured.compiled_source_file(&source).unwrap(),
            captured
                .compiled_source_file(primary.path.as_ref())
                .unwrap()
        ),
        "issued alias returns the SAME original compiled policy file"
    );
    assert!(captured.compiled_source_file(&config).is_none());
    assert!(captured
        .compiled_source_file(&root.join("foreign.dm"))
        .is_none());
    let implicit = capture(&frontend, &inputs, &[], &[]).unwrap();
    assert!(
        implicit.compiled_source_file(&source).is_none(),
        "equivalent prefix alone cannot mint an unrequested alias"
    );
    assert_eq!(
        reads.load(Ordering::Relaxed),
        before + 1,
        "membership queries and an implicit compiled capture perform no IO"
    );
    let mut aliases = 0;
    captured.visit_source_aliases(|path, alias| {
        assert_eq!(path, &source);
        assert_eq!(alias.primary_path(), primary.path.as_path());
        aliases += 1;
    });
    assert_eq!(aliases, 1);
    assert_eq!(
        captured
            .policy()
            .files()
            .filter(
                |file| dm_preprocess::regions::relative_filesystem_path(file.path(), &root)
                    .is_some_and(|p| p == Path::new("code/compiled.dm"))
            )
            .count(),
        1
    );
    let cohort = db.raw_cohort(captured, &root, &config).unwrap();
    let first = db
        .analyze_fixture_findings(&cohort, &["base_vars".into()])
        .unwrap();
    let computed = db.db().stats(dm_query::Kind(10)).computed;
    let second = db
        .analyze_fixture_findings(&cohort, &["base_vars".into()])
        .unwrap();
    assert_eq!(db.db().stats(dm_query::Kind(10)).computed, computed);
    assert_eq!(
        serde_json::to_value(&first.runs[0].run.sites).unwrap(),
        serde_json::to_value(&second.runs[0].run.sites).unwrap()
    );
    assert_eq!(
        first.runs[0].run.sites.len(),
        1,
        "no duplicate report-relative rows"
    );
    assert_eq!(reads.load(Ordering::Relaxed), before + 1);
}
#[test]
fn custom_decline_refuses_same_relative_alias_without_reread_or_silent_dedup() {
    let (_, source, config, reads, inputs, frontend, _) =
        setup("acquired-alias-custom-decline", true);
    let before = reads.load(Ordering::Relaxed);
    let request = intent(&source, &config);
    let error = capture(&frontend, &inputs, &request.capture_files(), &[])
        .err()
        .unwrap();
    assert!(error
        .to_string()
        .contains("provider cannot certify requested alias"));
    assert_eq!(
        reads.load(Ordering::Relaxed),
        before,
        "refuses alias atomically before foreign payload can be read"
    );
}
#[test]
fn changed_alias_file_stamp_does_not_rebind_old_acquisition() {
    let (_, source, config, _, inputs, frontend, _) = setup("acquired-alias-changed", false);
    std::fs::write(
        &source,
        b"/atom\n    var/changed_larger_value_with_new_stamp\n",
    )
    .unwrap();
    let request = intent(&source, &config);
    assert!(capture(&frontend, &inputs, &request.capture_files(), &[]).is_err());
}

#[test]
fn acquired_alias_capture_cannot_be_relabelled_as_another_request_scope() {
    let (_, source, config, _, inputs, frontend, _) = setup("acquired-alias-intent", false);
    let requested = intent(&source, &config);
    let capture = capture(&frontend, &inputs, &requested.capture_files(), &[]).unwrap();
    let foreign = intent(&std::fs::canonicalize(&source).unwrap(), &config);
    assert!(
        capture.bind_request(&foreign).is_err(),
        "compiler member implicit scope does not license an unrequested alias"
    );
}

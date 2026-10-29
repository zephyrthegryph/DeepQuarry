use super::*;
use crate::{
    input_snapshot::{FolderListing, RecordingInputs, SnapshotProvider, Stamp},
    policy_request::{PolicyInputFile, PolicyInputRequest, PolicyInputRole},
};
#[derive(Clone)]
struct Files {
    a: &'static [u8],
    config: Option<&'static [u8]>,
}
impl Files {
    fn bytes(&self, path: &Path) -> io::Result<&'static [u8]> {
        match path.file_name().and_then(|p| p.to_str()) {
            Some("p.dme") => Ok(b"#include \"code/a.dm\"\n#include \"code/b.dm\"\n"),
            Some("a.dm") => Ok(self.a),
            Some("b.dm") => Ok(b"/proc/b()\n    sleep(2)\n"),
            Some("scopes.toml") => self.config.ok_or(io::ErrorKind::NotFound.into()),
            _ => Err(io::ErrorKind::NotFound.into()),
        }
    }
}
impl SnapshotProvider for Files {
    fn stamp(&self, path: &Path) -> io::Result<Stamp> {
        Ok(Stamp {
            size: self.bytes(path)?.len() as u64,
            modified_ns: 1,
            file_id: Some(1),
        })
    }
    fn read(&self, path: &Path) -> io::Result<(Stamp, Vec<u8>)> {
        Ok((self.stamp(path)?, self.bytes(path)?.to_vec()))
    }
    fn list(&self, path: &Path) -> io::Result<FolderListing> {
        Ok(FolderListing::Present(if path.ends_with("code") {
            vec!["a.dm".into(), "b.dm".into()]
        } else {
            let mut v = vec!["code".into(), "p.dme".into()];
            if self.config.is_some() {
                v.push("scopes.toml".into());
            }
            v
        }))
    }
}
fn root() -> PathBuf {
    dm_preprocess::regions::canonical_path(
        &std::env::current_dir().unwrap().join("raw-query-fixture"),
    )
}
fn capture(
    db: &Arc<QueryDb>,
    a: &'static [u8],
    config: Option<&'static [u8]>,
) -> Arc<CapturedPolicyInputs> {
    capture_project(db, a, config, &root().join("p.dme"))
}
fn capture_project(
    db: &Arc<QueryDb>,
    a: &'static [u8],
    config: Option<&'static [u8]>,
    project: &Path,
) -> Arc<CapturedPolicyInputs> {
    let inputs = RecordingInputs::new(Files { a, config }, 1);
    let frontend = dm_tree::frontend::build(project, &inputs, &Default::default(), 1)
        .unwrap()
        .with_body_queries(db.clone());
    let intent = PolicyInputRequest {
        files: vec![PolicyInputFile {
            path: root().join("scopes.toml"),
            role: PolicyInputRole::Configuration,
            required: false,
        }],
        search_folders: vec![],
    }
    .admit()
    .unwrap();
    Arc::new(
        crate::runner_host::policy_capture::capture(
            &frontend,
            &inputs,
            &intent.capture_files(),
            &[],
        )
        .unwrap()
        .bind_request(&intent)
        .unwrap(),
    )
}
const BEFORE: &[u8] = b"/proc/a()\n    sleep(1)\n";
fn cohort(db: &Arc<QueryDb>, a: &'static [u8], config: Option<&'static [u8]>) -> Arc<Cohort> {
    db.raw_cohort(capture(db, a, config), &root(), &root().join("scopes.toml"))
        .unwrap()
}
fn names() -> Vec<String> {
    vec!["scheduler".into()]
}
#[test]
fn warm_queries_reuse_one_computation_and_source_view_owner() {
    let db = Arc::new(QueryDb::default());
    let input = cohort(&db, BEFORE, None);
    let first = db.raw_findings(&input, &names()).unwrap();
    first.validate_for(&input).unwrap();
    assert_eq!(first.runs[0].run.sites.len(), 2);
    let count = db.db.stats(RAW_FINDINGS).computed;
    let census = db.raw_policy_cache_stats();
    assert!(census.input_and_param_estimate > 0);
    assert!(census.derived_estimate > 0);
    assert!(census.input_and_param_estimate <= INPUT_BUDGET);
    assert!(census.derived_estimate <= RESULT_BUDGET);
    let issued_path = input.files.iter().find(|path| {
        dm_preprocess::regions::relative_filesystem_path(path, &input.root)
            .is_some_and(|relative| relative == Path::new("code/a.dm"))
    }).unwrap();
    let file_key = key(RAW_FILE, &(&input.root, issued_path));
    let held = db.db.input::<FileData>(file_key).unwrap();
    assert!(db
        .db
        .dependants(&[file_key])
        .iter()
        .any(|key| key.kind == RAW_FINDINGS));
    let config_key = key(RAW_CONFIG, &(&input.root, &input.configuration));
    let dependent = db.db.dependants(&[config_key]);
    assert!(dependent.iter().any(|key| key.kind == RAW_SCOPE));
    assert!(dependent.iter().any(|key| key.kind == RAW_FINDINGS));
    let second = db.raw_findings(&input, &names()).unwrap();
    assert_eq!(second.runs[0].run.sites, first.runs[0].run.sites);
    assert_eq!(db.db.stats(RAW_FINDINGS).computed, count);
    let warm_census = db.raw_policy_cache_stats();
    assert_eq!(warm_census.nodes, census.nodes);
    assert_eq!(
        warm_census.input_and_param_estimate,
        census.input_and_param_estimate
    );
    assert_eq!(warm_census.derived_estimate, census.derived_estimate);
    assert!(Arc::ptr_eq(
        &held.file,
        &db.db.input::<FileData>(file_key).unwrap().file
    ));
    let new_input = db
        .raw_cohort(
            Arc::clone(&input.capture),
            &root(),
            &root().join("scopes.toml"),
        )
        .unwrap();
    assert!(first.validate_for(&new_input).is_err());
    db.raw_findings(&new_input, &names()).unwrap();
    assert_eq!(db.db.stats(RAW_FINDINGS).computed, count);
    assert_eq!(
        db.db.stats(super::super::body_syntax::BODY_SYNTAX).computed,
        0
    );
}
#[test]
fn one_file_edit_retracts_only_that_file_and_unrelated_config_is_early_cutoff() {
    let db = Arc::new(QueryDb::default());
    let first = cohort(&db, BEFORE, None);
    db.raw_findings(&first, &names()).unwrap();
    let count = db.db.stats(RAW_FINDINGS).computed;
    let edited = cohort(&db, b"/proc/a()\n    return 1\n", None);
    let rows = db.raw_findings(&edited, &names()).unwrap();
    assert_eq!(rows.runs[0].run.sites.len(), 1);
    assert!(rows.runs[0].run.sites[0].rel.ends_with("b.dm"));
    assert_eq!(db.db.stats(RAW_FINDINGS).computed, count + 1);
    let count = db.db.stats(RAW_FINDINGS).computed;
    let unrelated = cohort(
        &db,
        b"/proc/a()\n    return 1\n",
        Some(b"[lint.breakpoint]\nexempt_files=['code/b.dm']\n"),
    );
    db.raw_findings(&unrelated, &names()).unwrap();
    assert_eq!(db.db.stats(RAW_FINDINGS).computed, count);
    let affected = cohort(
        &db,
        b"/proc/a()\n    return 1\n",
        Some(b"[lint.scheduler]\nexempt_files=['code/b.dm']\n"),
    );
    assert!(db.raw_findings(&affected, &names()).unwrap().runs[0]
        .run
        .sites
        .is_empty());
    assert!(db.db.stats(RAW_FINDINGS).computed > count);
}
#[test]
fn eviction_recomputes_without_frontend_or_body_parse_and_preserves_exact_findings() {
    let db = Arc::new(QueryDb::default());
    let input = cohort(&db, BEFORE, None);
    let first = db.raw_findings(&input, &names()).unwrap();
    let count = db.db.stats(RAW_FINDINGS).computed;
    db.db.evict_values(&[RAW_FINDINGS, RAW_SCOPE]);
    let second = db.raw_findings(&input, &names()).unwrap();
    assert_eq!(second.runs[0].run.sites, first.runs[0].run.sites);
    assert_eq!(second.runs[0].allow_used, first.runs[0].allow_used);
    assert_eq!(second.runs[0].run.notes, first.runs[0].run.notes);
    assert!(db.db.stats(RAW_FINDINGS).computed > count);
    assert_eq!(
        db.db.stats(super::super::body_syntax::BODY_SYNTAX).computed,
        0
    );
    {
        let _guard = db.raw_policy.gate.lock().unwrap();
        db.raw_prune_locked(Instant::now() + MAX_AGE + Duration::from_secs(1));
    }
    assert!(db.raw_policy.leases.lock().unwrap().is_empty());
    assert_eq!(
        db.raw_findings(&input, &names()).unwrap().runs[0].run.sites,
        first.runs[0].run.sites
    );
}
#[test]
fn foreign_graph_receipts_roots_and_uncaptured_configuration_are_refused() {
    let db = Arc::new(QueryDb::default());
    let other = Arc::new(QueryDb::default());
    let capture = capture(&db, BEFORE, None);
    assert!(other
        .raw_cohort(Arc::clone(&capture), &root(), &root().join("scopes.toml"))
        .is_err());
    assert!(db
        .raw_cohort(
            Arc::clone(&capture),
            &root().join("narrow"),
            &root().join("scopes.toml")
        )
        .is_err());
    assert!(db
        .raw_cohort(Arc::clone(&capture), &root(), &root().join("unknown.toml"))
        .is_err());
    let input = db
        .raw_cohort(Arc::clone(&capture), &root(), &root().join("scopes.toml"))
        .unwrap();
    assert!(other.raw_findings(&input, &names()).is_err());
    let rows = db.raw_findings(&input, &names()).unwrap();
    let different_root = db
        .raw_cohort(
            capture,
            root().parent().unwrap(),
            &root().join("scopes.toml"),
        )
        .unwrap();
    assert!(rows.validate_for(&different_root).is_err());
    assert!(db.raw_findings(&different_root, &names()).unwrap().runs[0]
        .run
        .sites
        .is_empty());
}

#[test]
fn aggregate_file_order_matches_legacy_slash_spelling_on_windows() {
    let mut files = vec![root().join("code0.dm"), root().join("code/z.dm")];
    sort_files(&root(), &mut files);
    assert!(files[0].ends_with("code/z.dm"));
}

#[test]
fn cache_admission_refuses_oversized_cohort_before_installing_any_nodes() {
    let db = Arc::new(QueryDb::default());
    let input = cohort(&db, BEFORE, None);
    let planned = BTreeMap::from([(key(RAW_FILE, &"too-large"), INPUT_BUDGET + 1)]);
    {
        let _gate = db.raw_policy.gate.lock().unwrap();
        assert!(db
            .raw_admit_locked(&input, &planned, Instant::now())
            .is_err());
    }
    assert_eq!(db.raw_policy_cache_stats().nodes, 0);
    let planned = (0..=MAX_NODES).map(|i| (key(RAW_FILE, &i), 1)).collect();
    {
        let _gate = db.raw_policy.gate.lock().unwrap();
        assert!(db
            .raw_admit_locked(&input, &planned, Instant::now())
            .is_err());
    }
    assert_eq!(db.raw_policy_cache_stats().nodes, 0);
}

#[test]
fn explicit_idle_release_drops_raw_cache_values_without_destroying_caller_findings() {
    let db = Arc::new(QueryDb::default());
    let input = cohort(&db, BEFORE, None);
    let rows = db.raw_findings(&input, &names()).unwrap();
    assert!(db.raw_policy_cache_stats().nodes > 0);
    db.release_raw_policy_cache();
    let stats = db.raw_policy_cache_stats();
    assert_eq!(stats.nodes, 0);
    assert_eq!(stats.derived_estimate, 0);
    assert_eq!(stats.input_and_param_estimate, 0);
    rows.validate_for(&input).unwrap();
    assert_eq!(rows.runs[0].run.sites.len(), 2);
}

#[cfg(windows)]
#[test]
fn verbatim_compiler_sources_keep_keys_and_report_with_ordinary_root() {
    let db = Arc::new(QueryDb::default());
    let ordinary = root();
    // This fixture root is an ordinary absolute drive path on Windows.
    let verbatim = PathBuf::from(format!(r"\\?\{}", ordinary.display()));
    let capture = capture_project(&db, BEFORE, None, &verbatim.join("p.dme"));
    let input = db
        .raw_cohort(capture, &ordinary, &ordinary.join("scopes.toml"))
        .unwrap();
    assert!(input.files.iter().all(|p| p.starts_with(&verbatim)));
    let rows = db.raw_findings(&input, &names()).unwrap();
    assert_eq!(
        rows.runs[0]
            .run
            .sites
            .iter()
            .map(|s| s.rel.as_str())
            .collect::<Vec<_>>(),
        ["code/a.dm", "code/b.dm"]
    );
    let file = input
        .files
        .iter()
        .find(|p| p.ends_with("code/a.dm"))
        .unwrap();
    let stored = db
        .db
        .input::<FileData>(key(RAW_FILE, &(&ordinary, file)))
        .unwrap();
    assert_eq!(stored.file.path(), file);
    let mut ordered = vec![verbatim.join("code0.dm"), verbatim.join("code/z.dm")];
    sort_files(&ordinary, &mut ordered);
    assert!(ordered[0].ends_with("code/z.dm"));
}

#[test]
fn missing_to_present_configuration_retracts_and_back_without_losing_allow_rows() {
    const ANNOTATED: &[u8] = b"/proc/a()\n    sleep(1) // ALLOW(scheduler): retained annotation tests cached consumption parity\n";
    let db = Arc::new(QueryDb::default());
    let missing = cohort(&db, ANNOTATED, None);
    let first = db.raw_findings(&missing, &names()).unwrap();
    assert_eq!(first.runs[0].run.sites.len(), 1);
    assert_eq!(first.runs[0].allow_used.len(), 1);
    let initial = db.db.stats(RAW_FINDINGS).computed;
    assert_eq!(initial as usize, missing.files.len());
    let warm = db.raw_findings(&missing, &names()).unwrap();
    assert_eq!(db.db.stats(RAW_FINDINGS).computed, initial);
    assert_eq!(warm.runs[0].allow_used, first.runs[0].allow_used);
    let present = cohort(
        &db,
        ANNOTATED,
        Some(b"[lint.scheduler]\nexempt_files=['code/b.dm']\n"),
    );
    let removed = db.raw_findings(&present, &names()).unwrap();
    assert!(removed.runs[0].run.sites.is_empty());
    assert_eq!(removed.runs[0].allow_used, first.runs[0].allow_used);
    assert_eq!(db.db.stats(RAW_FINDINGS).computed, initial + missing.files.len() as u64);
    let restored = db.raw_findings(&missing, &names()).unwrap();
    assert_eq!(restored.runs[0].run.sites, first.runs[0].run.sites);
    assert_eq!(restored.runs[0].allow_used, first.runs[0].allow_used);
    assert_eq!(db.db.stats(RAW_FINDINGS).computed, initial + 2 * missing.files.len() as u64);
}

#[test]
fn raw_graph_revisions_never_hide_a_compiler_source_edit() {
    use dm_preprocess::regions::prepared_source::{PreparedSource, PreparedSources};
    use dm_preprocess::SourceChanges;
    let prepared = |text: &str| {
        PreparedSources::from_prepared([(
            PathBuf::from("compiler.dm"),
            Arc::new(PreparedSource::new(Arc::from(text))),
        )])
        .unwrap()
    };
    let db = Arc::new(QueryDb::default());
    db.revise(&prepared("old"), 1).unwrap();
    let before = SourceChanges::revision(db.as_ref());
    let raw = cohort(&db, BEFORE, None);
    db.raw_findings(&raw, &names()).unwrap();
    let during = SourceChanges::revision(db.as_ref());
    // A raw-only gap may conservatively require a full source comparison.
    assert!(db
        .changes_since(before)
        .is_none_or(|paths| paths.is_empty()));
    db.revise(&prepared("edited"), 1).unwrap();
    let revised = SourceChanges::revision(db.as_ref());
    for token in [before, during] {
        if let Some(paths) = db.changes_since(token) {
            assert!(paths.contains(Path::new("compiler.dm")));
        }
    }
    db.release_raw_policy_cache();
    if let Some(paths) = db.changes_since(before) {
        assert!(paths.contains(Path::new("compiler.dm")));
    }
    assert!(db
        .changes_since(revised)
        .is_none_or(|paths| paths.is_empty()));
}

#[test]
fn concurrent_pinned_cohorts_are_serialized_without_cross_config_answers() {
    let db = Arc::new(QueryDb::default());
    let old = cohort(&db, BEFORE, None);
    let changed = cohort(
        &db,
        b"/proc/a()\n    return 1\n",
        Some(b"[lint.scheduler]\nexempt_files=['code/b.dm']\n"),
    );
    let barrier = Arc::new(std::sync::Barrier::new(2));
    std::thread::scope(|scope| {
        let spawn = |input: Arc<Cohort>, expected: usize| {
            let db = Arc::clone(&db);
            let barrier = Arc::clone(&barrier);
            scope.spawn(move || {
                barrier.wait();
                let result = db.raw_findings(&input, &names()).unwrap();
                result.validate_for(&input).unwrap();
                assert_eq!(result.runs[0].run.sites.len(), expected);
            })
        };
        let a = spawn(old, 2);
        let b = spawn(changed, 0);
        a.join().unwrap();
        b.join().unwrap();
    });
}
#[test]
fn idle_raw_cache_release_drops_last_source_owner_after_capture_is_gone() {
    let db = Arc::new(QueryDb::default());
    let input = cohort(&db, BEFORE, None);
    let issued_path = input.files.iter().find(|path| {
        dm_preprocess::regions::relative_filesystem_path(path, &input.root)
            .is_some_and(|relative| relative == Path::new("code/a.dm"))
    }).unwrap();
    let weak = input
        .capture
        .policy()
        .file(issued_path)
        .unwrap()
        .view(TextView::AnalyzeRaw)
        .unwrap()
        .downgrade();
    let rows = db.raw_findings(&input, &names()).unwrap();
    drop(input);
    assert!(
        weak.upgrade().is_some(),
        "graph File retains issued source storage"
    );
    db.release_raw_policy_cache();
    assert!(
        weak.upgrade().is_none(),
        "release drops graph's last immutable source owner"
    );
    assert_eq!(
        rows.runs[0].run.sites.len(),
        2,
        "caller findings remain independently valid"
    );
}

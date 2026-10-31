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
        workspace: None,
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
    let issued_path = input
        .files
        .iter()
        .find(|path| {
            dm_preprocess::regions::relative_filesystem_path(path, &input.root)
                .is_some_and(|relative| relative == Path::new("code/a.dm"))
        })
        .unwrap();
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
    assert_eq!(
        db.db.stats(RAW_FINDINGS).computed,
        initial + missing.files.len() as u64
    );
    let restored = db.raw_findings(&missing, &names()).unwrap();
    assert_eq!(restored.runs[0].run.sites, first.runs[0].run.sites);
    assert_eq!(restored.runs[0].allow_used, first.runs[0].allow_used);
    assert_eq!(
        db.db.stats(RAW_FINDINGS).computed,
        initial + 2 * missing.files.len() as u64
    );
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
    // shared_prepared intentionally shares exact text process-wide across live
    // sessions. This lifetime test needs a unique source so unrelated parallel
    // tests cannot be legitimate last owners of the same immutable arena.
    const UNIQUE: &[u8] = b"/proc/a()\n    sleep(1) // idle raw release owner fixture\n";
    let input = cohort(&db, UNIQUE, None);
    let issued_path = input
        .files
        .iter()
        .find(|path| {
            dm_preprocess::regions::relative_filesystem_path(path, &input.root)
                .is_some_and(|relative| relative == Path::new("code/a.dm"))
        })
        .unwrap();
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

#[test]
fn forced_equal_config_hash_cannot_reuse_stale_parsed_scope_on_public_raw_path() {
    let db = Arc::new(QueryDb::default());
    let input = cohort(&db, BEFORE, Some(b"# actual current config\n"));
    db.raw_findings(&input, &names()).unwrap();
    let config_key = key(RAW_CONFIG, &(&input.root, &input.configuration));
    let valid_hash = db.db.input::<ConfigData>(config_key).unwrap().hash;
    db.db.remove(config_key);
    db.db.set_input(
        config_key,
        ConfigData {
            config: Arc::new(
                Config::capture(Configuration::Captured(b"# foreign stale config\n")).unwrap(),
            ),
            hash: valid_hash,
            original: Some(dm_resources::SharedBytes::from(
                b"# foreign stale config\n".to_vec(),
            )),
        },
        valid_hash,
    );
    let computations = db.db.stats(RAW_FINDINGS).computed;
    let error = db
        .raw_findings(&input, &names())
        .err()
        .expect("equal hash must not grant byte authority");
    assert!(error
        .to_string()
        .contains("configuration bytes/absence contradict"));
    assert_eq!(db.db.stats(RAW_FINDINGS).computed, computations);
}

#[test]
fn forced_equal_source_hash_cannot_reuse_foreign_raw_findings() {
    let db = Arc::new(QueryDb::default());
    let input = cohort(&db, BEFORE, None);
    db.raw_findings(&input, &names()).unwrap();
    let path = input
        .files
        .iter()
        .find(|path| {
            dm_preprocess::regions::relative_filesystem_path(path, &input.root)
                .is_some_and(|rel| rel == Path::new("code/a.dm"))
        })
        .unwrap();
    let file_key = key(RAW_FILE, &(&input.root, path));
    let valid_hash = db.db.input::<FileData>(file_key).unwrap().hash;
    db.db.remove(file_key);
    db.db.set_input(
        file_key,
        FileData {
            file: Arc::new(
                File::capture(
                    &input.root,
                    path,
                    "/proc/foreign()\n    return\n".to_string().into(),
                )
                .unwrap(),
            ),
            hash: valid_hash,
        },
        valid_hash,
    );
    let computed = db.db.stats(RAW_FINDINGS).computed;
    let error = db
        .raw_findings(&input, &names())
        .err()
        .expect("hash alone must not authorize cached raw bytes");
    assert!(error
        .to_string()
        .contains("cached raw source path/bytes contradict"));
    assert_eq!(db.db.stats(RAW_FINDINGS).computed, computed);
}

#[test]
fn cached_error_charge_uses_capacity_and_atomic_admission_never_publishes_over_limit() {
    let mut error = String::with_capacity(64 * 1024);
    error.push('x');
    let expected = error.capacity()
        + std::mem::size_of::<Result<Arc<Findings>, String>>()
        + 2 * std::mem::size_of::<usize>();
    assert_eq!(result_error_charge::<Arc<Findings>>(&error), expected);
    assert_eq!(
        result_error_charge::<Vec<RawRun>>(&error),
        error.capacity()
            + std::mem::size_of::<Result<Vec<RawRun>, String>>()
            + 2 * std::mem::size_of::<usize>()
    );
    let charge = AtomicUsize::new(7);
    let key = Key::new(RAW_FINDINGS, 991);
    let admission = Admission::default();
    admission.limit.store(expected + 7, Ordering::Relaxed);
    retain_derived(&charge, expected, &admission, key).unwrap();
    assert_eq!(charge.load(Ordering::Relaxed), expected + 7);
    assert!(retain_derived(&charge, 1, &admission, key).is_err());
    assert_eq!(charge.load(Ordering::Relaxed), expected + 7);
    let mut old = b"native-raw-policy-error-v1\0".to_vec();
    old.extend_from_slice(error.as_bytes());
    assert_eq!(error_hash(&error), dm_query::hash_bytes(&old));
}

#[test]
fn raw_scope_cached_error_retains_actual_bytes_or_is_refused_without_a_value() {
    let q = QueryDb::default();
    let config = Key::new(RAW_CONFIG, 992);
    q.db.set_input(
        config,
        ConfigData {
            config: Arc::new(Config::capture(Configuration::ProvenMissing).unwrap()),
            hash: 1,
            original: None,
        },
        1,
    );
    let denied = Key::new(RAW_SCOPE, 993);
    q.raw_policy.admission.limit.store(0, Ordering::Relaxed);
    assert!(q
        .db
        .get::<Result<Arc<Scope>, String>>(
            denied,
            Arc::new(ScopeParams {
                config,
                name: "not-admitted",
            })
        )
        .is_err());
    assert!(q
        .db
        .retained_value::<Result<Arc<Scope>, String>>(denied)
        .is_none());
    assert_eq!(q.raw_policy.charge.load(Ordering::Relaxed), 0);
    let admitted = denied; // same params/node must observe current mutable headroom
    q.raw_policy
        .admission
        .limit
        .store(RESULT_BUDGET, Ordering::Relaxed);
    q.raw_policy
        .admission
        .denied
        .store(false, Ordering::Relaxed);
    let result =
        q.db.get::<Result<Arc<Scope>, String>>(
            admitted,
            Arc::new(ScopeParams {
                config,
                name: "not-admitted",
            }),
        )
        .unwrap();
    let error = result.as_ref().as_ref().err().unwrap();
    let expected = result_error_charge::<Arc<Scope>>(error);
    assert_eq!(q.db.value_bytes_at(admitted), expected);
    assert_eq!(q.raw_policy.charge.load(Ordering::Relaxed), expected);
    assert_eq!(
        q.workspace_result_charge_locked().unwrap(),
        0,
        "raw global charge must not be counted again as workspace payload"
    );
}

#[test]
fn request_boundary_reconciles_global_reservations_to_live_derived_values_only() {
    let q = Arc::new(QueryDb::default());
    let input = cohort(&q, BEFORE, None);
    let rows = q.raw_findings(&input, &names()).unwrap();
    assert_eq!(rows.runs[0].run.sites.len(), 2);
    let expected = q
        .raw_policy
        .leases
        .lock()
        .unwrap()
        .keys()
        .filter(|key| {
            matches!(
                key.kind,
                RAW_FINDINGS | RAW_SCOPE | analyze_policy::ANALYZE_FINDINGS
            )
        })
        .map(|key| q.db.value_bytes_at(*key))
        .sum::<usize>();
    // A generic Db early cutoff may retain the previous value after a fresh
    // Outcome reserved its bytes. Model that conservative reservation, without
    // forging any input, policy result or compiler/source authority.
    q.raw_policy.charge.fetch_add(128, Ordering::Relaxed);
    let _gate = q.raw_policy.gate.lock().unwrap();
    q.raw_prune_locked(Instant::now());
    assert_eq!(q.raw_policy.charge.load(Ordering::Relaxed), expected);
}
#[test]
fn raw_mid_compute_cancellation_is_not_a_cached_semantic_refusal() {
    let db = Arc::new(QueryDb::default());
    let input = cohort(&db, BEFORE, None);
    let expected = db.raw_findings(&input, &names()).unwrap();
    db.db.evict_values(&[RAW_FINDINGS]);
    let revision = db.db.revision();
    let token = crate::daemon::control::Cancellation::default();
    db.raw_policy
        .admission
        .abort
        .cancel_on_poll(3, token.clone());
    let binding = crate::daemon::control::bind_with_deadline(
        token,
        std::time::Instant::now() + std::time::Duration::from_secs(60),
    );
    let error = db
        .raw_findings(&input, &names())
        .err()
        .expect("actual cancellation after raw scanning");
    assert_eq!(error.kind(), io::ErrorKind::Interrupted);
    assert_eq!(crate::request_failure::exit_code(&error), 75);
    assert_eq!(db.raw_policy.admission.abort.poll_count(), 3);
    let leases = db.raw_policy.leases.lock().unwrap();
    assert!(leases.keys().filter(|k| k.kind == RAW_FINDINGS).all(|k| db
        .db
        .retained_value::<Result<Arc<Findings>, String>>(*k)
        .is_none()));
    drop(leases);
    assert!(
        db.raw_policy.admission.abort.is_aborted(),
        "taking original error must not unlatch publication denial"
    );
    drop(binding);
    db.raw_policy.admission.abort.disarm();
    let again = db.raw_findings(&input, &names()).unwrap();
    assert_eq!(
        revision,
        db.db.revision(),
        "retry uses SAME source/capture/input revision"
    );
    assert_eq!(
        serde_json::to_value(&again.runs[0].run.sites).unwrap(),
        serde_json::to_value(&expected.runs[0].run.sites).unwrap()
    );
}
#[test]
fn typed_scanner_mid_compute_cancellation_retries_same_captured_input() {
    let db = Arc::new(QueryDb::default());
    let input = cohort(&db, b"/datum/probe/Initialize()\n    return 1\n", None);
    let names = vec!["init".to_string()];
    let expected = db.analyze_fixture_findings(&input, &names).unwrap();
    db.db.evict_values(&[analyze_policy::ANALYZE_FINDINGS]);
    let revision = db.db.revision();
    let token = crate::daemon::control::Cancellation::default();
    db.raw_policy
        .admission
        .abort
        .cancel_on_poll(4, token.clone());
    let binding = crate::daemon::control::bind_with_deadline(
        token,
        std::time::Instant::now() + std::time::Duration::from_secs(60),
    );
    let error = db
        .analyze_fixture_findings(&input, &names)
        .err()
        .expect("actual scanner callback cancellation");
    assert_eq!(error.kind(), io::ErrorKind::Interrupted);
    assert_eq!(crate::request_failure::exit_code(&error), 75);
    assert_eq!(db.raw_policy.admission.abort.poll_count(), 4);
    let leases = db.raw_policy.leases.lock().unwrap();
    assert!(leases
        .keys()
        .filter(|k| k.kind == analyze_policy::ANALYZE_FINDINGS)
        .all(|k| db
            .db
            .retained_value::<Result<Vec<RawRun>, String>>(*k)
            .is_none()));
    drop(leases);
    drop(binding);
    db.raw_policy.admission.abort.disarm();
    let again = db.analyze_fixture_findings(&input, &names).unwrap();
    assert_eq!(revision, db.db.revision());
    assert_eq!(
        serde_json::to_value(&again.runs[0].run.sites).unwrap(),
        serde_json::to_value(&expected.runs[0].run.sites).unwrap()
    );
}

#[test]
fn report_source_headroom_and_sink_denials_never_cache_and_same_query_recovers() {
    let q=QueryDb::default();
    let config=Key::new(RAW_CONFIG,1992);
    q.db.set_input(config,ConfigData{config:Arc::new(Config::capture(Configuration::ProvenMissing).unwrap()),hash:1,original:None},1);
    let scope_key=Key::new(RAW_SCOPE,1993);
    let scope_params=ScopeParams{config,name:"scheduler"};
    let scope=q.db.get::<Result<Arc<Scope>,String>>(scope_key,Arc::new(scope_params.clone())).unwrap();
    let scope=scope.as_ref().as_ref().unwrap();
    let source=format!("/proc/p()\n    sleep(1) // {}\n","x".repeat(32768));
    let file=Arc::new(File::capture(&root(),&root().join("code/a.dm"),source.into()).unwrap());
    assert!(matches!(file.scan_budgeted_checked(scope,MAX_FIXTURE_SITES,16384),
        Err(captured_raw_file::ScanFailure::Admission(error)) if error.contains("report evidence")),
        "fixture specifically reaches new source-evidence denial after the ordinary finding fits");
    let file_key=Key::new(RAW_FILE,1994);
    q.db.set_input(file_key,FileData{file:file.clone(),hash:2},2);
    let result_key=Key::new(RAW_FINDINGS,1995);
    let params=Arc::new(FileParams{file:file_key,scope:scope_key,scope_params});
    let prior=q.raw_policy.charge.load(Ordering::Relaxed);
    // The same query first hits the old Sink admission and then the report evidence admission.
    for available in [64,16384] {
        q.raw_policy.admission.limit.store(prior+available+512,Ordering::Relaxed);
        q.raw_policy.admission.denied.store(false,Ordering::Relaxed);
        assert!(q.db.get::<Result<Arc<Findings>,String>>(result_key,params.clone()).is_err());
        assert!(q.raw_policy.admission.denied.load(Ordering::Relaxed));
        assert!(q.db.retained_value::<Result<Arc<Findings>,String>>(result_key).is_none());
        assert_eq!(q.raw_policy.charge.load(Ordering::Relaxed),prior);
    }
    q.raw_policy.admission.limit.store(RESULT_BUDGET,Ordering::Relaxed);
    q.raw_policy.admission.denied.store(false,Ordering::Relaxed);
    let result=q.db.get::<Result<Arc<Findings>,String>>(result_key,params.clone()).unwrap();
    let rows=result.as_ref().as_ref().unwrap();
    assert_eq!(rows.run.sites.len(),1);
    assert!(rows.site_text(0).unwrap().starts_with("sleep(1) // xxx"));
    assert_eq!(rows.site_text(0).unwrap().len(),32768+12);
    let warm=q.db.get::<Result<Arc<Findings>,String>>(result_key,params).unwrap();
    assert!(Arc::ptr_eq(&result,&warm));
}

use super::*;
use dm_analysis::policy_inputs::HostCapture;
use dm_tree::frontend::ColdFrontend;
use std::sync::Arc;
struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
fn fixture(source: &'static str) -> (std::path::PathBuf, ColdFrontend, PolicyInputs) {
    let root = std::env::current_dir().unwrap().join("raw-policy-fixture");
    let frontend = dm_tree::frontend::build(
        &root.join("code/sample.dm"),
        &Source(source),
        &Default::default(),
        1,
    )
    .unwrap();
    let captures = frontend
        .files
        .iter()
        .filter(|file| file.captured)
        .map(|file| {
            HostCapture::analyze_raw(
                Arc::clone(&file.path),
                PolicyRole::DmSource,
                file.text.clone(),
            )
        })
        .collect::<Vec<_>>();
    let inputs = PolicyInputs::capture(&frontend, captures).unwrap();
    (root, frontend, inputs)
}
fn selected(name: &str) -> Vec<String> {
    vec![name.into()]
}
#[test]
fn raw_adapter_shares_issued_text_and_preserves_exact_file_policy_and_allow_rows() {
    let source="/datum/probe/proc/run()\n    sleep(1)\n    sleep(2) // ALLOW(scheduler): this is an intentional annotation fixture\n";
    let (root, frontend, inputs) = fixture(source);
    let captured =
        CapturedRawPolicy::capture(&root, &inputs, Configuration::ProvenMissing).unwrap();
    let source_owner = &frontend
        .files
        .iter()
        .find(|file| file.captured)
        .unwrap()
        .text;
    assert!(captured
        .tree
        .get("code/sample.dm")
        .unwrap()
        .raw()
        .text
        .same_view(source_owner));
    let actual = captured
        .scan(&selected("scheduler"), || Ok(()))
        .unwrap()
        .pop()
        .unwrap();
    let old_tree = Tree::from_files(vec![SourceFile::from_text("code/sample.dm", source)]);
    let registry = registry();
    let lint = registry.find("scheduler").unwrap();
    let scope = Scopes::default().for_lint("scheduler", "");
    let cx = Cx { fixture:None,
        tree: &old_tree,
        meta: lint.meta(),
        scope: &scope,
    };
    let mut expected = Sink::new();
    expected.cur = "code/sample.dm".into();
    lint.scan_file(&cx, old_tree.get("code/sample.dm").unwrap(), &mut expected);
    assert_eq!(actual.run.sites, expected.sites);
    assert_eq!(actual.allow_used, expected.allow_used);
    assert_eq!(actual.run.notes, expected.notes);
    assert_eq!(actual.run.sites.len(), 1);
    assert_eq!(actual.run.sites[0].line, 2);
    assert_eq!(actual.allow_used.len(), 1);
}
#[test]
fn scope_filters_and_hidden_files_reuse_existing_selection_rules() {
    let (root, frontend, _) = fixture("/datum/probe/proc/run()\n    sleep(1)\n");
    let mut captures = frontend
        .files
        .iter()
        .filter(|file| file.captured)
        .map(|file| {
            HostCapture::analyze_raw(
                Arc::clone(&file.path),
                PolicyRole::DmSource,
                file.text.clone(),
            )
        })
        .collect::<Vec<_>>();
    captures.push(HostCapture::analyze_raw(
        Arc::new(root.join("code/.hidden/ignored.dm")),
        PolicyRole::DmSource,
        "sleep(1)\n".into(),
    ));
    let inputs = PolicyInputs::capture(&frontend, captures).unwrap();
    let config = b"[lint.scheduler]\nexempt_files=[\"code/sample.dm\"]\n";
    let captured =
        CapturedRawPolicy::capture(&root, &inputs, Configuration::Captured(config)).unwrap();
    assert!(captured.scan(&selected("scheduler"), || Ok(())).unwrap()[0]
        .run
        .sites
        .is_empty());
}
#[test]
#[cfg(feature="legacy-sem")]
fn legacy_semantic_access_is_latched_and_cannot_return_a_clean_run() {
    let (root, _, inputs) = fixture("/datum/probe\n");
    let captured =
        CapturedRawPolicy::capture(&root, &inputs, Configuration::ProvenMissing).unwrap();
    assert!(crate::sem::sem_for(&captured.tree).is_none());
    assert!(captured
        .tree
        .captured_violation()
        .unwrap()
        .contains("semantic model"));
    assert!(captured.scan(&selected("scheduler"), || Ok(())).is_err());
    assert!(crate::sem::Sem::build(&root, &captured.tree).is_err());
}
#[test]
fn extra_reads_and_memoized_indexes_are_rejected_before_io_or_initialization() {
    let (root, _, inputs) = fixture("/datum/probe\n");
    let captured =
        CapturedRawPolicy::capture(&root, &inputs, Configuration::ProvenMissing).unwrap();
    assert!(captured.tree.read_extra("not-captured.dm").is_none());
    assert!(captured.scan(&selected("scheduler"), || Ok(())).is_err());
    let called = std::sync::atomic::AtomicBool::new(false);
    let denied = catch_unwind(AssertUnwindSafe(|| {
        captured.tree.memo("sem/model", || {
            called.store(true, std::sync::atomic::Ordering::SeqCst);
            1usize
        })
    }));
    assert!(denied.is_err());
    assert!(!called.load(std::sync::atomic::Ordering::SeqCst));
}
#[test]
fn nonwhitelisted_semantic_lints_and_interrupted_scans_discard_all_results() {
    let (root, _, inputs) = fixture("/datum/probe\n");
    let captured =
        CapturedRawPolicy::capture(&root, &inputs, Configuration::ProvenMissing).unwrap();
    assert!(captured.scan(&selected("tracked"), || Ok(())).is_err());
    assert!(captured.scan(&[], || Ok(())).is_err());
    assert!(captured
        .scan(&selected("scheduler"), || Err("cancelled".into()))
        .is_err());
    assert_eq!(RAW_FILE_LINTS.len(), 43);
    for &name in RAW_FILE_LINTS {
        let lint = registry().find(name).expect("every raw-file policy is registered");
        assert!(lint.meta().scan == ScanKind::File, "{name} must remain file-only");
    }
    // The same registry also stores the separately admitted bounded cohort.
    // Only the audited entry_slots File policy moved; Tree/Both remain separate.
    for &name in crate::captured_raw_cohort::LINTS {
        if name == "entry_slots" {
            assert!(captured.scan(&selected(name), || Ok(())).is_ok(),
                "unchanged File policy has independent public-file and private-fixture roles");
        } else {
            assert!(captured.scan(&selected(name), || Ok(())).is_err(),
                "bounded Tree/Both cohort {name} must not receive raw-file admission");
        }
    }
    assert!(registry().lints.iter().all(|lint|
        RAW_FILE_LINTS.contains(&lint.meta().name)
            || crate::captured_raw_cohort::LINTS.contains(&lint.meta().name)));
}
#[test]
fn missing_analyze_raw_view_is_an_error_not_compiler_decoded_fallback() {
    let (root, frontend, _) = fixture("/datum/probe\n");
    let inputs = PolicyInputs::capture(&frontend, []).unwrap();
    assert!(CapturedRawPolicy::capture(&root, &inputs, Configuration::ProvenMissing).is_err());
}

fn with_policy_sources(
    frontend: &ColdFrontend,
    extras: Vec<(String, dm_preprocess::SourceText)>,
) -> PolicyInputs {
    let mut captures = frontend
        .files
        .iter()
        .filter(|file| file.captured)
        .map(|file| {
            HostCapture::analyze_raw(
                Arc::clone(&file.path),
                PolicyRole::DmSource,
                file.text.clone(),
            )
        })
        .collect::<Vec<_>>();
    let root = frontend
        .files
        .iter()
        .find(|file| file.captured)
        .unwrap()
        .path
        .parent()
        .unwrap()
        .parent()
        .unwrap();
    captures.extend(extras.into_iter().map(|(name, text)| {
        HostCapture::analyze_raw(Arc::new(root.join(name)), PolicyRole::DmSource, text)
    }));
    PolicyInputs::capture(frontend, captures).unwrap()
}
#[test]
fn fixture_admission_rejects_oversized_single_sources_and_configuration() {
    let (root, frontend, _) = fixture("/datum/probe\n");
    let text: dm_preprocess::SourceText = " ".repeat(MAX_FIXTURE_FILE_BYTES + 1).into();
    let inputs = with_policy_sources(&frontend, vec![("code/large.dm".into(), text)]);
    assert!(CapturedRawPolicy::capture(&root, &inputs, Configuration::ProvenMissing).is_err());
    let inputs = with_policy_sources(&frontend, vec![]);
    let config = vec![b' '; MAX_FIXTURE_FILE_BYTES + 1];
    assert!(CapturedRawPolicy::capture(&root, &inputs, Configuration::Captured(&config)).is_err());
}
#[test]
fn fixture_total_admission_counts_paths_even_when_source_payload_is_shared() {
    let (root, frontend, _) = fixture("/datum/probe\n");
    let shared: dm_preprocess::SourceText = " ".repeat(MAX_FIXTURE_FILE_BYTES).into();
    let extras = (0..32)
        .map(|index| (format!("code/{index}.dm"), shared.clone()))
        .collect();
    let inputs = with_policy_sources(&frontend, extras);
    assert!(CapturedRawPolicy::capture(&root, &inputs, Configuration::ProvenMissing).is_err());
}
#[test]
fn exceeding_site_admission_discards_every_result_without_truncation() {
    let (root, frontend, _) = fixture("/datum/probe\n");
    let dense: dm_preprocess::SourceText = "sleep(1)\n".repeat(MAX_FIXTURE_SITES + 1).into();
    let inputs = with_policy_sources(&frontend, vec![("code/dense.dm".into(), dense)]);
    let runner = CapturedRawPolicy::capture(&root, &inputs, Configuration::ProvenMissing).unwrap();
    let error = runner
        .scan(&selected("scheduler"), || Ok(()))
        .err()
        .expect("overflow must refuse, not truncate");
    assert!(error.contains("finding admission"));
}

#[cfg(windows)]
#[test]
fn raw_capture_compares_verbatim_drive_root_without_changing_provider_key() {
    let root = Path::new(r"E:\raw-policy-fixture");
    let authored = Path::new(r"\\?\E:\raw-policy-fixture\code\sample.dm");
    let frontend = dm_tree::frontend::build(authored,
        &Source("/proc/run()\n    sleep(1)\n"), &Default::default(), 1).unwrap();
    let captures: Vec<_> = frontend.files.iter().filter(|f|f.captured).map(|f|
        HostCapture::analyze_raw(Arc::clone(&f.path), PolicyRole::DmSource, f.text.clone())).collect();
    let inputs = PolicyInputs::capture(&frontend, captures).unwrap();
    let policy = CapturedRawPolicy::capture(root, &inputs, Configuration::ProvenMissing).unwrap();
    let captured = policy.tree.get("code/sample.dm").unwrap();
    assert_eq!(captured.abs.as_path(), authored);
    let rows = policy.scan(&selected("scheduler"), ||Ok(())).unwrap();
    assert_eq!(rows[0].run.sites.len(), 1);
    assert_eq!(rows[0].run.sites[0].rel, "code/sample.dm");
    assert!(CapturedRawPolicy::capture(Path::new(r"E:\raw-policy-fixture-other"),
        &inputs, Configuration::ProvenMissing).is_err());
}

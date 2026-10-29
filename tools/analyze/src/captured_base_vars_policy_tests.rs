use super::*;
use dm_analysis::policy_inputs::{HostCapture, PolicyRole};
use std::{collections::BTreeSet, path::PathBuf, sync::Arc};
struct Source(
    &'static str,
    std::cell::RefCell<std::collections::BTreeMap<PathBuf, dm_preprocess::AcquiredSource>>,
);
impl Source {
    fn new(text: &'static str) -> Self {
        Self(text, Default::default())
    }
}
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Err("actual primary bytes required".into())
    }
    fn acquired_source(
        &self,
        path: &Path,
    ) -> Result<Option<dm_preprocess::AcquiredSource>, String> {
        if !self.1.borrow().contains_key(path) {
            self.1.borrow_mut().insert(
                path.into(),
                dm_preprocess::AcquiredSource::from_original_bytes(self.0.as_bytes().to_vec(), ()),
            );
        }
        Ok(self.1.borrow().get(path).cloned())
    }
    fn source_acquisition(
        &self,
        path: &Path,
        text: &dm_preprocess::SourceText,
    ) -> Option<dm_preprocess::AcquiredSource> {
        self.1
            .borrow()
            .get(path)
            .filter(|source| source.lease().source_text().same_view(text))
            .cloned()
    }
}
fn fixture() -> (PathBuf, PolicyInputs) {
    let root = std::env::current_dir()
        .unwrap()
        .join("base-vars-composition-unit");
    let source="/atom\n    var/plain\n    var/list/items = list()\n    var/kept // ALLOW(base_vars): fixture keeps this base field deliberately for its owner\n    var/list/list_kept = list() // ALLOW(instance_list): fixture keeps this list allocation deliberately for its owner\n/datum/record/probe/proc/business()\n    return\n/datum/record/probe/proc/set_value()\n    return\n";
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let frontend = dm_tree::frontend::build_with_executor_and_semantic_state_for_policy(
        &root.join("code/probe.dm"),
        &Source::new(source),
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
    .unwrap();
    let extra = frontend
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
    (root, PolicyInputs::capture(&frontend, extra).unwrap())
}
const CONFIG:&[u8]=b"[lint.base_vars.lists]\nrecord_accessor_prefixes=['set_','get_']\n[lint.base_vars.tables.base_var_home_hot]\n'/atom/plain'='short'\n";
#[test]
fn all_four_rules_compose_in_legacy_order_with_one_annotation_phase() {
    let (root, inputs) = fixture();
    let policy =
        CapturedBaseVarsPolicy::capture(&root, &inputs, Configuration::Captured(CONFIG)).unwrap();
    let candidates = BorrowedBaseVarCandidates::capture(&policy.raw, &inputs)
        .unwrap()
        .scan(|| Ok(()))
        .unwrap();
    let full = policy.scan(|| Ok(())).unwrap();
    assert_eq!(
        full.run
            .sites
            .iter()
            .map(|site| site.rule.as_str())
            .collect::<BTreeSet<_>>(),
        BTreeSet::from(["base_var", "list_init", "hot_home", "records_data_only"])
    );
    assert_eq!(full.allow_used, candidates.allow_used);
    assert_eq!(full.allow_used.len(), 2);
    assert_eq!(full.run.notes, candidates.run.notes);
    assert_eq!(full.run.notes.len(), 1);
    assert_eq!(full.run.sites.last().unwrap().rule, "records_data_only");
    let hot = full
        .run
        .sites
        .iter()
        .position(|site| site.rule == "hot_home")
        .unwrap();
    assert!(full.run.sites[..hot]
        .iter()
        .all(|site| matches!(site.rule.as_str(), "base_var" | "list_init")));
    assert_eq!(
        full.run
            .sites
            .iter()
            .filter(|site| site.rule == "records_data_only")
            .count(),
        1
    );
}
#[test]
fn borrowed_composition_reuses_the_raw_source_owner() {
    let (root, inputs) = fixture();
    let raw = CapturedRawPolicy::capture(&root, &inputs, Configuration::Captured(CONFIG)).unwrap();
    let borrowed = BorrowedBaseVarsPolicy::capture(&raw, &inputs).unwrap();
    let first = borrowed.scan(|| Ok(())).unwrap();
    let marker = raw.tree.get("code/probe.dm").unwrap().marker().clone();
    let second = borrowed.scan(|| Ok(())).unwrap();
    assert_eq!(first.run.sites, second.run.sites);
    assert_eq!(first.allow_used, second.allow_used);
    assert!(marker.same_view(raw.tree.get("code/probe.dm").unwrap().marker()));
}
#[test]
fn missing_analyze_raw_is_an_error_before_any_findings() {
    let root = std::env::current_dir()
        .unwrap()
        .join("base-vars-no-raw-unit");
    let frontend = dm_tree::frontend::build(
        &root.join("code/probe.dm"),
        &Source::new("/atom\n    var/one\n"),
        &Default::default(),
        1,
    )
    .unwrap();
    let inputs = PolicyInputs::capture(&frontend, Vec::new()).unwrap();
    assert!(CapturedBaseVarsPolicy::capture(&root, &inputs, Configuration::ProvenMissing).is_err());
}
#[test]
fn cancellation_after_candidate_work_does_not_issue_partial_results() {
    let (root, inputs) = fixture();
    let policy =
        CapturedBaseVarsPolicy::capture(&root, &inputs, Configuration::Captured(CONFIG)).unwrap();
    let mut candidate_checks = 0usize;
    BorrowedBaseVarCandidates::capture(&policy.raw, &inputs)
        .unwrap()
        .scan(|| {
            candidate_checks += 1;
            Ok(())
        })
        .unwrap();
    let mut checks = 0usize;
    let result = policy.scan(|| {
        checks += 1;
        if checks > candidate_checks {
            Err("after candidates".into())
        } else {
            Ok(())
        }
    });
    assert_eq!(result.err().as_deref(), Some("after candidates"));
    assert!(crate::dm::sys::take_recorded().is_empty());
}

#[test]
fn include_eof_policy_cursor_does_not_rewrite_base_var_provenance_or_create_a_code_site() {
    struct Files {
        source: String,
        acquired:
            std::cell::RefCell<std::collections::BTreeMap<PathBuf, dm_preprocess::AcquiredSource>>,
    }
    impl dm_preprocess::SourceProvider for Files {
        fn acquired_source(
            &self,
            path: &Path,
        ) -> Result<Option<dm_preprocess::AcquiredSource>, String> {
            if !self.acquired.borrow().contains_key(path) {
                let original = self.read(path)?;
                self.acquired.borrow_mut().insert(
                    path.into(),
                    dm_preprocess::AcquiredSource::from_original_bytes(original.into_bytes(), ()),
                );
            }
            Ok(self.acquired.borrow().get(path).cloned())
        }
        fn source_acquisition(
            &self,
            path: &Path,
            text: &dm_preprocess::SourceText,
        ) -> Option<dm_preprocess::AcquiredSource> {
            self.acquired
                .borrow()
                .get(path)
                .filter(|source| source.lease().source_text().same_view(text))
                .cloned()
        }
        fn read(&self, path: &Path) -> Result<String, String> {
            Ok(if path.extension().is_some_and(|e| e == "dme") {
                "#include \"code/probe.dm\"\n".into()
            } else {
                self.source.clone()
            })
        }
    }
    let root = std::env::current_dir()
        .unwrap()
        .join("base-var-eof-policy-unit");
    for source in [
        "/atom\n    var/eof_value",
        "/atom\n    var/eof_value[3]",
        "#define FINAL var/eof_value\n/atom\n    FINAL\n",
    ] {
        let executor = dm_exec::BuildExecutor::new(1).unwrap();
        let frontend = dm_tree::frontend::build_with_executor_and_semantic_state_for_policy(
            &root.join("deepquarry.dme"),
            &Files {
                source: source.into(),
                acquired: Default::default(),
            },
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
        .unwrap();
        for capture_manifest in [false, true] {
            let extra = frontend
                .files
                .iter()
                .filter(|f| {
                    f.captured
                        && (capture_manifest || !f.path.extension().is_some_and(|e| e == "dme"))
                })
                .map(|f| {
                    HostCapture::analyze_raw(
                        Arc::clone(&f.path),
                        PolicyRole::DmSource,
                        f.text.clone(),
                    )
                })
                .collect::<Vec<_>>();
            let inputs = PolicyInputs::capture(&frontend, extra).unwrap();
            // Match the real host's RAW_FILE owner assembly: only files
            // explicitly captured as raw enter the shared roster. In the
            // targetless branch the compiled DME has no fabricated raw view.
            if !capture_manifest {
                assert!(
                    CapturedRawPolicy::capture(&root, &inputs, Configuration::ProvenMissing)
                        .is_err(),
                    "standalone all-source capture must remain strict"
                );
            }
            let shared = inputs
                .files()
                .filter(|file| {
                    file.role() == PolicyRole::DmSource
                        && (capture_manifest
                            || file.path().as_path() != root.join("deepquarry.dme").as_path())
                })
                .map(|file| {
                    Arc::new(
                        crate::captured_raw_file::File::capture(
                            &root,
                            file.path(),
                            file.view(dm_analysis::policy_inputs::TextView::AnalyzeRaw)
                                .unwrap()
                                .clone(),
                        )
                        .unwrap(),
                    )
                })
                .collect::<Vec<_>>();
            let make_raw = |configuration| {
                let config = crate::captured_raw_file::Config::capture(configuration).unwrap();
                CapturedRawPolicy::from_shared_files(&root, &inputs, &config, &shared)
            };
            if !capture_manifest {
                let error = make_raw(Configuration::ProvenMissing)
                    .err()
                    .expect("an incomplete shared roster must not issue a raw owner");
                assert!(error.contains("shared source roster is incomplete"));
                continue;
            }
            let raw = make_raw(Configuration::ProvenMissing).unwrap();
            let facts =
                crate::captured_base_var_hot_policy::NativeBaseVarFacts::capture(&raw, &inputs)
                    .unwrap();
            let rows = facts
                .declarations(crate::base_var_hot_policy::BASE_TYPES)
                .unwrap();
            assert_eq!(rows.len(), 1);
            assert!(
                rows[0].native.source.path.ends_with("code/probe.dm"),
                "native source must remain original"
            );
            assert_eq!(
                (rows[0].relative.as_ref(), rows[0].line),
                ("deepquarry.dme", 2)
            );
            assert_eq!(
                rows[0].name, "eof_value",
                "the hot-home declared set must retain the row"
            );
            let result = BorrowedBaseVarsPolicy::capture(&raw, &inputs)
                .unwrap()
                .scan(|| Ok(()))
                .unwrap();
            assert!(
                result.run.sites.is_empty(),
                "original code-file selection omits a DME cursor"
            );
            assert!(result.allow_used.is_empty());
            let hot=b"[lint.base_vars.tables.base_var_home_hot]\n'/atom/eof_value'='code/reader.dm /atom/proc/read reads this field on every frame'\n";
            let raw_hot = make_raw(Configuration::Captured(hot)).unwrap();
            let with_hot = BorrowedBaseVarsPolicy::capture(&raw_hot, &inputs)
                .unwrap()
                .scan(|| Ok(()))
                .unwrap();
            assert!(with_hot.run.sites.is_empty(),"the original typed_vars declared set includes this DME cursor; hot_home must not call it stale");
        }
    }
}
#[test]
fn base_var_policy_does_not_fallback_to_headers_without_compatibility_issuance() {
    let root = std::env::current_dir()
        .unwrap()
        .join("base-var-unissued-policy-unit");
    let frontend = dm_tree::frontend::build(
        &root.join("code/probe.dm"),
        &Source::new("/atom\n    var/one\n"),
        &Default::default(),
        1,
    )
    .unwrap();
    let extra = frontend
        .files
        .iter()
        .filter(|f| f.captured)
        .map(|f| {
            HostCapture::analyze_raw(Arc::clone(&f.path), PolicyRole::DmSource, f.text.clone())
        })
        .collect::<Vec<_>>();
    let inputs = PolicyInputs::capture(&frontend, extra).unwrap();
    let result = CapturedBaseVarsPolicy::capture(&root, &inputs, Configuration::ProvenMissing)
        .unwrap()
        .scan(|| Ok(()));
    assert!(result.err().unwrap().contains("producer was not requested"));
}

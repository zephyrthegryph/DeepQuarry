use super::*;
use crate::{
    input_snapshot::{FileSystemInputs, FolderListing, RecordingInputs, SnapshotProvider, Stamp},
    policy_request::{PolicyInputFile, PolicyInputRequest, PolicyInputRole},
};
use std::sync::atomic::{AtomicUsize, Ordering};
#[derive(Clone)]
struct Counted(Arc<AtomicUsize>);
impl SnapshotProvider for Counted {
    fn stamp(&self, p: &Path) -> io::Result<Stamp> {
        self.0.fetch_add(1, Ordering::Relaxed);
        FileSystemInputs.stamp(p)
    }
    fn read(&self, p: &Path) -> io::Result<(Stamp, Vec<u8>)> {
        self.0.fetch_add(1, Ordering::Relaxed);
        FileSystemInputs.read(p)
    }
    fn list(&self, p: &Path) -> io::Result<FolderListing> {
        self.0.fetch_add(1, Ordering::Relaxed);
        FileSystemInputs.list(p)
    }
}
const MANIFEST: &str =
    "#if 0\n#include \"code/probe.dm\"\n#include \"code/extra.dm\"\n#endif\n/datum\n";
const PROBE:&str="/datum/system/power\n    var/own\nSYSTEM_DEF(power)\nSYSTEM_ACCESSOR(power, power_own, nameof(own))\nsparse(/obj/probe, a, type = num)\n";
fn capture(db: &Arc<QueryDb>, root: &Path, reads: Arc<AtomicUsize>) -> Arc<Cohort> {
    let provider = Counted(reads);
    let inputs = RecordingInputs::new(provider, 123);
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let front = dm_tree::frontend::build_with_executor_and_semantic_state_for_policy(
        &root.join("deepquarry.dme"),
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
    let intent = PolicyInputRequest {workspace_auxiliary:Vec::new(),workspace_generators:Vec::new(),
        workspace: None,
        files: vec![
            PolicyInputFile {
                path: root.join("deepquarry.dme"),
                role: PolicyInputRole::DmSource,
                required: true,
            },
            PolicyInputFile {
                path: root.join("code/probe.dm"),
                role: PolicyInputRole::DmSource,
                required: true,
            },
            PolicyInputFile {
                path: root.join("code/extra.dm"),
                role: PolicyInputRole::DmSource,
                required: true,
            },
            PolicyInputFile {
                path: root.join("scopes.toml"),
                role: PolicyInputRole::Configuration,
                required: false,
            },
        ],
        search_folders: vec![],
    }
    .admit()
    .unwrap();
    let captured = Arc::new(
        crate::runner_host::policy_capture::capture(&front, &inputs, &intent.capture_files(), &[])
            .unwrap()
            .bind_request(&intent)
            .unwrap(),
    );
    db.raw_cohort(captured, root, &root.join("scopes.toml"))
        .unwrap()
}
fn fixture() -> (Arc<QueryDb>, PathBuf, Arc<AtomicUsize>, Arc<Cohort>) {
    let root = crate::test_scratch::dir("native-generator-graph");
    std::fs::create_dir_all(root.join("code")).unwrap();
    std::fs::write(root.join("deepquarry.dme"), MANIFEST).unwrap();
    std::fs::write(root.join("code/probe.dm"), PROBE).unwrap();
    std::fs::write(
        root.join("code/extra.dm"),
        "sparse(/obj/probe, a, type = text)\nSYSTEM_ACCESSOR(power, missing, nameof(absent))\n",
    )
    .unwrap();
    let db = Arc::new(QueryDb::default());
    let reads = Arc::new(AtomicUsize::new(0));
    let cohort = capture(&db, &root, reads.clone());
    (db, root, reads, cohort)
}
#[test]
fn same_db_generators_reuse_exact_outcome_and_existing_raw_lazies_without_reads() {
    let (db, root, reads, c) = fixture();
    let expected_sparse = dq_analyze::captured_sparse_slots::CapturedSparseSlots::capture(
        &root,
        c.capture.policy().archive(),
        c.capture.policy(),
    )
    .unwrap()
    .generate(|| Ok(()))
    .unwrap();
    let expected_system = dq_analyze::captured_system_accessors::CapturedSystemAccessors::capture(
        &root,
        c.capture.policy().archive(),
        c.capture.policy(),
    )
    .unwrap()
    .generate(|| Ok(()))
    .unwrap();
    let before = reads.load(Ordering::Relaxed);
    let one = db
        .with_generator_fixture(&c, GeneratorName::SparseSlots, |a| {
            assert_eq!(a.text(), expected_sparse.file_text());
            assert_eq!(a.diagnostics(), expected_sparse.diags);
            assert_eq!(a.path(), "code/engine/_generated/sparse_slots.dm");
            Ok(a.text.as_ptr() as usize)
        })
        .unwrap();
    let (file_key, file) = {
        let _gate = db.raw_policy.gate.lock().unwrap();
        let prepared = db.raw_prepare_locked(&c, &[], Instant::now()).unwrap();
        let (file_key, _, _) = prepared
            .sources
            .iter()
            .find(|(_, _, file)| file.path().ends_with("probe.dm"))
            .expect("actual prepared probe source");
        (*file_key, db.db.input::<FileData>(*file_key).unwrap())
    };
    let computed = db.db.stats(GENERATOR_RESULT).computed;
    let two = db
        .with_generator_fixture(&c, GeneratorName::SparseSlots, |a| {
            Ok(a.text.as_ptr() as usize)
        })
        .unwrap();
    assert_eq!(one, two);
    assert_eq!(db.db.stats(GENERATOR_RESULT).computed, computed);
    db.with_generator_fixture(&c, GeneratorName::SystemAccessors, |a| {
        assert_eq!(a.text(), expected_system.file_text());
        assert_eq!(a.diagnostics(), expected_system.diags);
        Ok(())
    })
    .unwrap();
    assert_eq!(
        reads.load(Ordering::Relaxed),
        before,
        "queries cannot touch provider or filesystem"
    );
    db.raw_findings(
        &c,
        &[dq_analyze::captured_raw_policy::RAW_FILE_LINTS[0].into()],
    )
    .unwrap();
    assert!(Arc::ptr_eq(
        &file.file,
        &db.db.input::<FileData>(file_key).unwrap().file
    ));
    assert!(db.raw_policy_cache_stats().retained_shared_view_capacity > 0);
    let foreign = QueryDb::default();
    let before = foreign.db.stats(GENERATOR_RESULT).computed;
    assert!(foreign
        .with_generator_fixture(&c, GeneratorName::SparseSlots, |_| Ok(()))
        .is_err());
    assert_eq!(foreign.db.stats(GENERATOR_RESULT).computed, before);
}
#[test]
fn new_original_source_manifest_and_configuration_captures_invalidate_same_graph() {
    let (db, root, reads, old) = fixture();
    let first = db
        .with_generator_fixture(&old, GeneratorName::SparseSlots, |a| Ok(a.fingerprint()))
        .unwrap();
    let n = db.db.stats(GENERATOR_RESULT).computed;
    std::fs::write(root.join("scopes.toml"), "# newly appeared\n").unwrap();
    let configured = capture(&db, &root, reads.clone());
    assert_ne!(
        old.capture.policy_revision(),
        configured.capture.policy_revision()
    );
    assert_eq!(
        db.with_generator_fixture(&configured, GeneratorName::SparseSlots, |a| Ok(
            a.fingerprint()
        ))
        .unwrap(),
        first
    );
    assert!(db.db.stats(GENERATOR_RESULT).computed > n);
    std::fs::write(root.join("code/probe.dm"), PROBE.replace(", a,", ", z,")).unwrap();
    let changed = capture(&db, &root, reads.clone());
    assert_ne!(
        db.with_generator_fixture(
            &changed,
            GeneratorName::SparseSlots,
            |a| Ok(a.fingerprint())
        )
        .unwrap(),
        first
    );
    std::fs::write(
        root.join("deepquarry.dme"),
        MANIFEST.replace(
            "#include \"code/probe.dm\"\n#include \"code/extra.dm\"",
            "#include \"code/extra.dm\"\n#include \"code/probe.dm\"",
        ),
    )
    .unwrap();
    let reordered = capture(&db, &root, reads);
    db.with_generator_fixture(&reordered, GeneratorName::SparseSlots, |a| {
        assert!(!a.text().is_empty());
        Ok(())
    })
    .unwrap();
}
#[test]
fn bounded_output_denial_and_cancellation_publish_no_clean_result_then_recover() {
    let (db, _, _, c) = fixture();
    // A directly budgeted producer proves denial BEFORE retaining a single row.
    let raw = dq_analyze::captured_raw_policy::CapturedRawPolicy::capture(
        &c.root,
        c.capture.policy(),
        Configuration::ProvenMissing,
    )
    .unwrap();
    assert!(Budget::new(0).is_err());
    let b = Budget::new(64).unwrap();
    assert!(BorrowedSparseSlots::capture(&raw, c.capture.policy(), b.clone()).is_err());
    assert!(b.denied());
    let token = crate::daemon::control::Cancellation::default();
    let binding = crate::daemon::control::bind_with_deadline(
        token.clone(),
        Instant::now() + Duration::from_secs(60),
    );
    token.cancel();
    assert_eq!(
        db.with_generator_fixture(&c, GeneratorName::SparseSlots, |_| Ok(()))
            .unwrap_err()
            .kind(),
        io::ErrorKind::Interrupted
    );
    drop(binding);
    db.with_generator_fixture(&c, GeneratorName::SparseSlots, |a| {
        assert!(!a.text().is_empty());
        Ok(())
    })
    .unwrap();
}

#[test]
fn old_cached_artifact_plus_one_byte_headroom_denies_new_rows_and_recovers() {
    let (db, _, _, c) = fixture();
    let old = db
        .with_generator_fixture(&c, GeneratorName::SparseSlots, |a| Ok(a.fingerprint()))
        .unwrap();
    let used = db.raw_policy.charge.load(Ordering::Relaxed);
    let consumed = std::cell::Cell::new(false);
    let error = db
        .with_generator_fixture_limit(&c, GeneratorName::SystemAccessors, Some(used + 1), |_| {
            consumed.set(true);
            Ok(())
        })
        .unwrap_err();
    assert!(
        !consumed.get(),
        "denied output must never reach its consumer"
    );
    // The earliest admission boundary may reject before a lazy source view is
    // requested. Both are operational quota failures, never clean artifacts.
    assert!(
        error
            .to_string()
            .contains("captured source view allocation")
            || error
                .to_string()
                .contains("shared native policy result budget exhausted"),
        "{error}"
    );
    assert_eq!(
        db.with_generator_fixture(&c, GeneratorName::SparseSlots, |a| Ok(a.fingerprint()))
            .unwrap(),
        old,
        "denied different generator cannot evict current warm artifact"
    );
    db.with_generator_fixture(&c, GeneratorName::SystemAccessors, |a| {
        assert!(a.text().contains("power_own"));
        Ok(())
    })
    .unwrap();
}

#[test]
fn preexisting_shared_file_lazy_denial_is_not_cached_and_only_poisoned_input_is_evicted() {
    let (db, _, _, c) = fixture();
    let (file_key, old) = {
        let _gate = db.raw_policy.gate.lock().unwrap();
        let prepared = db.raw_prepare_locked(&c, &[], Instant::now()).unwrap();
        let key = prepared
            .sources
            .iter()
            .find(|(_, _, f)| f.path().ends_with("probe.dm"))
            .unwrap()
            .0;
        (key, db.db.input::<FileData>(key).unwrap())
    };
    let path = old.file.path();
    let raw = c
        .capture
        .policy()
        .file(path)
        .unwrap()
        .view(TextView::AnalyzeRaw)
        .unwrap();
    let full = File::capture_budgeted(&c.root, path, raw.clone(), usize::MAX).unwrap();
    // Construction has only recorded raw text/index owners. Complete the actual
    // initial Record/DerivedViews census before using its retained charge as a
    // limit: otherwise require_view_budget itself detects those uncounted owners,
    // rather than the test exercising a later demanded marker allocation.
    full.require_view_budget().unwrap();
    let tiny =
        Arc::new(File::capture_budgeted(&c.root, path, raw.clone(), full.budget_charge()).unwrap());
    assert!(
        tiny.require_view_budget().is_ok(),
        "original raw capture is initially valid"
    );
    // A finite scoped File is deliberately not eligible for content rebind.
    // Demand a real existing raw-policy view BEFORE installation, rather than
    // mistaking that earlier rebind refusal for an in-generator lazy denial.
    let config = Config::capture(Configuration::ProvenMissing).unwrap();
    let scope = config.scope("containment").unwrap();
    let lazy_error = tiny.scan(&scope).unwrap_err();
    assert!(
        lazy_error.contains("captured source view allocation"),
        "{lazy_error}"
    );
    assert!(
        tiny.require_view_budget().is_err(),
        "real demanded code view must latch denial"
    );
    let (valid_key, valid_owner) = {
        let _gate = db.raw_policy.gate.lock().unwrap();
        let prepared = db.raw_prepare_locked(&c, &[], Instant::now()).unwrap();
        let key = prepared
            .sources
            .iter()
            .find(|(key, _, _)| *key != file_key)
            .unwrap()
            .0;
        (key, db.db.input::<FileData>(key).unwrap())
    };
    db.db.remove(file_key);
    db.db.set_input(
        file_key,
        FileData {
            file: tiny.clone(),
            hash: old.hash,
        },
        old.hash,
    );
    let calls = std::cell::Cell::new(0);
    let error = db
        .with_generator_fixture(&c, GeneratorName::SparseSlots, |_| {
            calls.set(calls.get() + 1);
            Ok(())
        })
        .unwrap_err();
    assert!(error.to_string().contains("budget"), "{error}");
    assert_eq!(
        calls.get(),
        0,
        "no empty/partial generated artifact can escape"
    );
    assert!(
        tiny.require_view_budget().is_err(),
        "the generator must preserve the real preexisting lazy-denial latch"
    );
    assert!(
        db.db.input::<FileData>(file_key).is_none(),
        "only actually poisoned source input is removed"
    );
    assert!(
        Arc::ptr_eq(
            &valid_owner.file,
            &db.db.input::<FileData>(valid_key).unwrap().file
        ),
        "unpoisoned shared source owner survives rejection"
    );
    drop(tiny);
    drop(full);
    drop(old);
    db.with_generator_fixture(&c, GeneratorName::SparseSlots, |a| {
        assert!(a.text().contains("sparse_slot_rows"));
        Ok(())
    })
    .unwrap();
}

#[test]
fn stats_same_db_exact_warm_owner_shared_raw_inputs_and_real_capture_changes() {
    let (db, root, reads, original) = fixture();
    std::fs::write(root.join("code/probe.dm"), "/obj/base\n    var/existing\nSTAT(/obj/base/child, existing, ALL)\nSTAT(/obj/a, energy, SUM, base = 7)\n").unwrap();
    std::fs::write(
        root.join("code/extra.dm"),
        "STAT(/obj/a, bad, SUM, broken)\n",
    )
    .unwrap();
    let c = capture(&db, &root, reads.clone());
    let before = reads.load(Ordering::Relaxed);
    let first = db
        .with_generator_fixture(&c, GeneratorName::Stats, |a| {
            assert_eq!(a.name(), "stats");
            assert_eq!(a.path(), "code/engine/_generated/stats.dm");
            assert!(a.text().contains("/obj/a/var/energy = 7"));
            assert!(!a.text().contains("/obj/base/child/var/existing"));
            assert_eq!(a.diagnostics().len(), 1);
            Ok((a.text.as_ptr() as usize, a.fingerprint()))
        })
        .unwrap();
    let computed = db.db.stats(GENERATOR_RESULT).computed;
    let second = db
        .with_generator_fixture(&c, GeneratorName::Stats, |a| {
            Ok((a.text.as_ptr() as usize, a.fingerprint()))
        })
        .unwrap();
    assert_eq!(first, second);
    assert_eq!(db.db.stats(GENERATOR_RESULT).computed, computed);
    assert_eq!(
        reads.load(Ordering::Relaxed),
        before,
        "warm stats cannot reacquire source"
    );
    let foreign = QueryDb::default();
    assert!(foreign
        .with_generator_fixture(&c, GeneratorName::Stats, |_| Ok(()))
        .is_err());
    std::fs::write(root.join("code/extra.dm"), "STAT(/obj/a, later, PRODUCT)\n").unwrap();
    let changed = capture(&db, &root, reads.clone());
    db.with_generator_fixture(&changed, GeneratorName::Stats, |a| {
        assert_ne!(a.fingerprint(), first.1);
        assert!(a.text().contains("/obj/a/var/later = 1"));
        assert!(a.diagnostics().is_empty());
        Ok(())
    })
    .unwrap();
    std::fs::write(root.join("scopes.toml"), "[lint.init]\n").unwrap();
    let configured = capture(&db, &root, reads.clone());
    let count = db.db.stats(GENERATOR_RESULT).computed;
    db.with_generator_fixture(&configured, GeneratorName::Stats, |a| {
        assert!(a.text().contains("/obj/a/var/later = 1"));
        Ok(())
    })
    .unwrap();
    assert!(
        db.db.stats(GENERATOR_RESULT).computed > count,
        "exact changed configuration is a real dependency even when stats semantics ignore it"
    );
    std::fs::write(
        root.join("deepquarry.dme"),
        "#if 0\n#include \"code/extra.dm\"\n#include \"code/probe.dm\"\n#endif\n/datum\n",
    )
    .unwrap();
    let reordered = capture(&db, &root, reads.clone());
    let count = db.db.stats(GENERATOR_RESULT).computed;
    db.with_generator_fixture(&reordered, GeneratorName::Stats, |a| {
        assert!(a.text().contains("/obj/a/var/later = 1"));
        Ok(())
    })
    .unwrap();
    assert!(db.db.stats(GENERATOR_RESULT).computed>count,"original manifest order is also captured even when distinct sorted rows emit the same text");
    drop(original);
}
#[test]
fn stats_cancellation_and_remaining_family_headroom_never_publish_partial_output() {
    let (db, root, reads, _) = fixture();
    std::fs::write(root.join("code/probe.dm"), "STAT(/obj/a, value, SUM)\n").unwrap();
    let c = capture(&db, &root, reads);
    let called = std::cell::Cell::new(false);
    assert!(db
        .with_generator_fixture_limit(&c, GeneratorName::Stats, Some(1), |_| {
            called.set(true);
            Ok(())
        })
        .is_err());
    assert!(!called.get());
    db.with_generator_fixture(&c, GeneratorName::Stats, |a| {
        assert!(a.text().contains("/obj/a/var/value = 0"));
        Ok(())
    })
    .unwrap();
    let cancellation = crate::daemon::control::Cancellation::default();
    cancellation.cancel();
    let _bound = crate::daemon::control::bind_with_deadline(
        cancellation,
        Instant::now() + Duration::from_secs(60),
    );
    assert!(db
        .with_generator_fixture(&c, GeneratorName::Stats, |_| {
            called.set(true);
            Ok(())
        })
        .is_err());
    assert!(
        !called.get(),
        "even cached stats cannot publish after cancellation"
    );
}

#[test]
fn actions_same_db_exact_warm_owner_raw_fields_and_source_config_manifest_dependencies() {
    let (db, root, reads, _) = fixture();
    std::fs::write(
        root.join("code/probe.dm"),
        "ACTION(fall, turf/landing)\n/datum/notice/fell\n    var/landing\n",
    )
    .unwrap();
    std::fs::write(
        root.join("code/extra.dm"),
        "ACTION(fall, num/duplicate)\nACTION(check, QUERY, mob/wearer)\n",
    )
    .unwrap();
    let c = capture(&db, &root, reads.clone());
    let before = reads.load(Ordering::Relaxed);
    let one = db
        .with_generator_fixture(&c, GeneratorName::Actions, |a| {
            assert_eq!(a.name(), "actions");
            assert_eq!(a.path(), "code/engine/_generated/actions.dm");
            assert!(a
                .text()
                .contains("/proc/act_fall(datum/holder, turf/landing, act_answer = FALSE)"));
            assert!(a.text().contains("/proc/query_check("));
            assert_eq!(a.diagnostics().len(), 1);
            Ok((a.text.as_ptr() as usize, a.fingerprint()))
        })
        .unwrap();
    let count = db.db.stats(GENERATOR_RESULT).computed;
    let two = db
        .with_generator_fixture(&c, GeneratorName::Actions, |a| {
            Ok((a.text.as_ptr() as usize, a.fingerprint()))
        })
        .unwrap();
    assert_eq!(one, two);
    assert_eq!(db.db.stats(GENERATOR_RESULT).computed, count);
    assert_eq!(
        reads.load(Ordering::Relaxed),
        before,
        "warm actions may not reacquire original sources"
    );
    assert!(QueryDb::default()
        .with_generator_fixture(&c, GeneratorName::Actions, |_| Ok(()))
        .is_err());
    std::fs::write(root.join("scopes.toml"), "[lint.init]\n").unwrap();
    let configured = capture(&db, &root, reads.clone());
    db.with_generator_fixture(&configured, GeneratorName::Actions, |a| {
        assert_eq!(a.fingerprint(), one.1);
        Ok(())
    })
    .unwrap();
    assert!(
        db.db.stats(GENERATOR_RESULT).computed > count,
        "real unchanged-result configuration dependency must still compute a new frame node"
    );
    std::fs::write(
        root.join("deepquarry.dme"),
        "#if 0\n#include \"code/extra.dm\"\n#include \"code/probe.dm\"\n#endif\n/datum\n",
    )
    .unwrap();
    let reordered = capture(&db, &root, reads.clone());
    db.with_generator_fixture(&reordered, GeneratorName::Actions, |a| {
        assert_ne!(a.fingerprint(), one.1);
        assert!(a
            .text()
            .contains("/proc/act_fall(datum/holder, num/duplicate, act_answer = FALSE)"));
        Ok(())
    })
    .unwrap();
    std::fs::write(root.join("code/extra.dm"), "ACTION(speak, num/volume)\n").unwrap();
    let changed = capture(&db, &root, reads.clone());
    db.with_generator_fixture(&changed, GeneratorName::Actions, |a| {
        assert!(a.text().contains("/datum/notice/spoke"));
        assert!(a.diagnostics().is_empty());
        Ok(())
    })
    .unwrap();
}
#[test]
fn actions_remaining_budget_and_cancelled_cached_read_publish_no_partial_generator() {
    let (db, root, reads, _) = fixture();
    std::fs::write(
        root.join("code/probe.dm"),
        "ACTION(move, turf/origin, turf/destination)\n",
    )
    .unwrap();
    let c = capture(&db, &root, reads);
    let called = std::cell::Cell::new(false);
    assert!(db
        .with_generator_fixture_limit(&c, GeneratorName::Actions, Some(1), |_| {
            called.set(true);
            Ok(())
        })
        .is_err());
    assert!(!called.get());
    db.with_generator_fixture(&c, GeneratorName::Actions, |a| {
        assert!(a.text().contains("origin_turf"));
        Ok(())
    })
    .unwrap();
    let cancellation = crate::daemon::control::Cancellation::default();
    let _bound = crate::daemon::control::bind_with_deadline(
        cancellation.clone(),
        Instant::now() + Duration::from_secs(60),
    );
    cancellation.cancel();
    assert_eq!(
        db.with_generator_fixture(&c, GeneratorName::Actions, |_| {
            called.set(true);
            Ok(())
        })
        .unwrap_err()
        .kind(),
        io::ErrorKind::Interrupted
    );
    assert!(!called.get());
}

#[test]
fn declare_ids_same_db_warm_original_owner_and_exact_config_source_manifest_dependencies() {
    let (db, root, reads, _) = fixture();
    std::fs::write(
        root.join("code/probe.dm"),
        "CAPABILITY_DEF(first, CAP_ONE)\nSTAT(/datum/x, value, SUM)\n",
    )
    .unwrap();
    std::fs::write(
        root.join("code/extra.dm"),
        "CAPABILITY_DEF(last, CAP_ONE)\ncap_keys(CAP_ONE, ON = TRUE)\n",
    )
    .unwrap();
    let c = capture(&db, &root, reads.clone());
    let before = reads.load(Ordering::Relaxed);
    let one = db
        .with_generator_fixture(&c, GeneratorName::DeclareIds, |a| {
            assert_eq!(a.name(), "declare_ids");
            assert_eq!(a.path(), "code/engine/_generated/ids.dm");
            assert!(a.text().contains("#define STAT_VALUE 100001"));
            assert!(a.text().contains("#define LAST_ON CAPKEY_ID(CAP_ONE, 1)"));
            assert!(a.diagnostics().is_empty());
            Ok((a.text.as_ptr() as usize, a.fingerprint()))
        })
        .unwrap();
    let computed = db.db.stats(GENERATOR_RESULT).computed;
    let two = db
        .with_generator_fixture(&c, GeneratorName::DeclareIds, |a| {
            Ok((a.text.as_ptr() as usize, a.fingerprint()))
        })
        .unwrap();
    assert_eq!(one, two);
    assert_eq!(computed, db.db.stats(GENERATOR_RESULT).computed);
    assert_eq!(before, reads.load(Ordering::Relaxed));
    assert!(QueryDb::default()
        .with_generator_fixture(&c, GeneratorName::DeclareIds, |_| Ok(()))
        .is_err());
    std::fs::write(
        root.join("scopes.toml"),
        "# configuration still participates in exact query dependency\n",
    )
    .unwrap();
    let configured = capture(&db, &root, reads.clone());
    db.with_generator_fixture(&configured, GeneratorName::DeclareIds, |a| {
        assert_eq!(a.fingerprint(), one.1);
        Ok(())
    })
    .unwrap();
    assert!(db.db.stats(GENERATOR_RESULT).computed > computed);
    std::fs::write(
        root.join("code/extra.dm"),
        "#define STAT_VALUE 99\nCAPABILITY_DEF(last, CAP_ONE)\ncap_keys(CAP_ONE, ON = TRUE)\n",
    )
    .unwrap();
    let changed = capture(&db, &root, reads.clone());
    db.with_generator_fixture(&changed, GeneratorName::DeclareIds, |a| {
        assert!(!a.text().contains("#define STAT_VALUE"));
        assert_ne!(a.fingerprint(), one.1);
        Ok(())
    })
    .unwrap();
    // Reordering the same two source receipts changes the last-wins cap-name map
    // only when equal sort names preserve encounter order. Equal names but distinct
    // IDs are a separate policy branch; inspect diagnostics/bytes, not guessed AST.
    std::fs::write(
        root.join("deepquarry.dme"),
        "#if 0\n#include \"code/extra.dm\"\n#include \"code/probe.dm\"\n#endif\n/datum\n",
    )
    .unwrap();
    let reordered = capture(&db, &root, reads);
    let count = db.db.stats(GENERATOR_RESULT).computed;
    db.with_generator_fixture(&reordered, GeneratorName::DeclareIds, |a| {
        assert!(!a.text().contains("#define STAT_VALUE"));
        Ok(())
    })
    .unwrap();
    assert!(
        db.db.stats(GENERATOR_RESULT).computed > count,
        "manifest changes are actual dependencies even when sorted ID bytes agree"
    );
}
#[test]
fn declare_ids_quota_and_cached_cancellation_refuse_without_callback_and_recover() {
    let (db, root, reads, _) = fixture();
    std::fs::write(root.join("code/probe.dm"), "STAT(/datum/x, value, SUM)\n").unwrap();
    let c = capture(&db, &root, reads);
    let called = std::cell::Cell::new(false);
    assert!(db
        .with_generator_fixture_limit(&c, GeneratorName::DeclareIds, Some(1), |_| {
            called.set(true);
            Ok(())
        })
        .is_err());
    assert!(!called.get());
    db.with_generator_fixture(&c, GeneratorName::DeclareIds, |a| {
        assert!(a.text().contains("STAT_VALUE"));
        Ok(())
    })
    .unwrap();
    let cancellation = crate::daemon::control::Cancellation::default();
    let bound = crate::daemon::control::bind_with_deadline(
        cancellation.clone(),
        Instant::now() + Duration::from_secs(60),
    );
    cancellation.cancel();
    assert_eq!(
        db.with_generator_fixture(&c, GeneratorName::DeclareIds, |_| {
            called.set(true);
            Ok(())
        })
        .unwrap_err()
        .kind(),
        io::ErrorKind::Interrupted
    );
    assert!(!called.get());
    drop(bound);
    db.with_generator_fixture(&c, GeneratorName::DeclareIds, |a| {
        assert!(a.diagnostics().is_empty());
        Ok(())
    })
    .unwrap();
}

#[test]
fn declare_same_db_warm_original_owner_and_exact_config_source_manifest_dependencies() {
    let (db, root, reads, _) = fixture();
    std::fs::write(
        root.join("code/probe.dm"),
        "CAPABILITY_DEF(first, CAP_ONE)\nSTAT(/datum/x, value, SUM)\n",
    )
    .unwrap();
    std::fs::write(
        root.join("code/extra.dm"),
        "CAPABILITY_DEF(last, CAP_ONE)\ncap_keys(CAP_ONE, ON = TRUE)\n",
    )
    .unwrap();
    let c = capture(&db, &root, reads.clone());
    let before = reads.load(Ordering::Relaxed);
    let one = db
        .with_generator_fixture(&c, GeneratorName::Declare, |a| {
            assert_eq!(a.name(), "declare");
            assert_eq!(a.path(), "code/engine/_generated/declare.dm");
            assert!(a.text().contains("/proc/first("));
            assert!(a.text().contains("/proc/last("));
            assert!(a.diagnostics().is_empty());
            Ok((a.text.as_ptr() as usize, a.fingerprint()))
        })
        .unwrap();
    let computed = db.db.stats(GENERATOR_RESULT).computed;
    let two = db
        .with_generator_fixture(&c, GeneratorName::Declare, |a| {
            Ok((a.text.as_ptr() as usize, a.fingerprint()))
        })
        .unwrap();
    assert_eq!(one, two);
    assert_eq!(computed, db.db.stats(GENERATOR_RESULT).computed);
    assert_eq!(before, reads.load(Ordering::Relaxed));
    assert!(QueryDb::default()
        .with_generator_fixture(&c, GeneratorName::Declare, |_| Ok(()))
        .is_err());
    std::fs::write(
        root.join("scopes.toml"),
        "# configuration still participates in exact query dependency\n",
    )
    .unwrap();
    let configured = capture(&db, &root, reads.clone());
    db.with_generator_fixture(&configured, GeneratorName::Declare, |a| {
        assert_eq!(a.fingerprint(), one.1);
        Ok(())
    })
    .unwrap();
    assert!(db.db.stats(GENERATOR_RESULT).computed > computed);
    std::fs::write(
        root.join("code/extra.dm"),
        "CAPABILITY_DEF(changed, CAP_ONE)\ncap_keys(CAP_ONE, ON = TRUE)\n",
    )
    .unwrap();
    let changed = capture(&db, &root, reads.clone());
    db.with_generator_fixture(&changed, GeneratorName::Declare, |a| {
        assert!(a.text().contains("/proc/changed("));
        assert_ne!(a.fingerprint(), one.1);
        Ok(())
    })
    .unwrap();
    // Reordering the same two source receipts changes the last-wins cap-name map
    // only when equal sort names preserve encounter order. Equal names but distinct
    // IDs are a separate policy branch; inspect diagnostics/bytes, not guessed AST.
    std::fs::write(
        root.join("deepquarry.dme"),
        "#if 0\n#include \"code/extra.dm\"\n#include \"code/probe.dm\"\n#endif\n/datum\n",
    )
    .unwrap();
    let reordered = capture(&db, &root, reads);
    let count = db.db.stats(GENERATOR_RESULT).computed;
    db.with_generator_fixture(&reordered, GeneratorName::Declare, |a| {
        assert!(a.text().contains("/proc/changed("));
        Ok(())
    })
    .unwrap();
    assert!(
        db.db.stats(GENERATOR_RESULT).computed > count,
        "manifest changes are actual dependencies even when sorted ID bytes agree"
    );
}
#[test]
fn declare_quota_and_cached_cancellation_refuse_without_callback_and_recover() {
    let (db, root, reads, _) = fixture();
    std::fs::write(
        root.join("code/probe.dm"),
        "CAPABILITY_DEF(quota, CAP_QUOTA)\n",
    )
    .unwrap();
    let c = capture(&db, &root, reads);
    let called = std::cell::Cell::new(false);
    assert!(db
        .with_generator_fixture_limit(&c, GeneratorName::Declare, Some(1), |_| {
            called.set(true);
            Ok(())
        })
        .is_err());
    assert!(!called.get());
    db.with_generator_fixture(&c, GeneratorName::Declare, |a| {
        assert!(a.text().contains("/proc/quota("));
        Ok(())
    })
    .unwrap();
    let cancellation = crate::daemon::control::Cancellation::default();
    let bound = crate::daemon::control::bind_with_deadline(
        cancellation.clone(),
        Instant::now() + Duration::from_secs(60),
    );
    cancellation.cancel();
    assert_eq!(
        db.with_generator_fixture(&c, GeneratorName::Declare, |_| {
            called.set(true);
            Ok(())
        })
        .unwrap_err()
        .kind(),
        io::ErrorKind::Interrupted
    );
    assert!(!called.get());
    drop(bound);
    db.with_generator_fixture(&c, GeneratorName::Declare, |a| {
        assert!(a.diagnostics().is_empty());
        Ok(())
    })
    .unwrap();
}

#[test]
fn ui_types_multifile_same_db_warm_owner_and_config_source_manifest_dependencies() {
    let (db, root, reads, _) = fixture();
    std::fs::write(root.join("code/probe.dm"),"SCHEMA(/datum/x, value, int(0,3))\nCAPABILITIES(/datum/x, interface(\"One\"), ui_shape(value))\n").unwrap();
    std::fs::write(
        root.join("code/extra.dm"),
        "CAPABILITIES(/datum/y, interface(\"Two\"), ui_shape(label = schema_text(8)))\n",
    )
    .unwrap();
    let c = capture(&db, &root, reads.clone());
    let before = reads.load(Ordering::Relaxed);
    let one = db
        .with_generator_files_fixture(&c, GeneratorName::UiTypes, |a| {
            assert_eq!(a.name(), "ui_types");
            assert_eq!(a.files().len(), 2);
            assert!(a.files()[0].0.ends_with("One.d.ts"));
            assert!(a.files()[1].0.ends_with("Two.d.ts"));
            assert!(a.files()[0].1.contains("value: number"));
            assert!(a.diagnostics().is_empty());
            assert!(
                a.retained_charge()
                    >= a.files()
                        .iter()
                        .map(|(p, t)| p.capacity() + t.capacity())
                        .sum::<usize>()
            );
            Ok((
                a.files().as_ptr() as usize,
                a.files()[0].1.as_ptr() as usize,
                a.fingerprint(),
            ))
        })
        .unwrap();
    let computed = db.db.stats(GENERATOR_RESULT).computed;
    let two = db
        .with_generator_files_fixture(&c, GeneratorName::UiTypes, |a| {
            Ok((
                a.files().as_ptr() as usize,
                a.files()[0].1.as_ptr() as usize,
                a.fingerprint(),
            ))
        })
        .unwrap();
    assert_eq!(one, two);
    assert_eq!(computed, db.db.stats(GENERATOR_RESULT).computed);
    assert_eq!(before, reads.load(Ordering::Relaxed));
    assert!(db
        .with_generator_fixture::<()>(&c, GeneratorName::UiTypes, |_| panic!(
            "multifile payload cannot enter single API"
        ))
        .is_err());
    assert!(db
        .with_generator_files_fixture::<()>(&c, GeneratorName::SparseSlots, |_| panic!(
            "single payload cannot enter multi API"
        ))
        .is_err());
    assert!(QueryDb::default()
        .with_generator_files_fixture(&c, GeneratorName::UiTypes, |_| Ok(()))
        .is_err());
    std::fs::write(
        root.join("scopes.toml"),
        "# exact config still invalidates\n",
    )
    .unwrap();
    let configured = capture(&db, &root, reads.clone());
    db.with_generator_files_fixture(&configured, GeneratorName::UiTypes, |a| {
        assert_eq!(a.fingerprint(), one.2);
        Ok(())
    })
    .unwrap();
    assert!(db.db.stats(GENERATOR_RESULT).computed > computed);
    std::fs::write(
        root.join("code/extra.dm"),
        "CAPABILITIES(/datum/y, interface(\"Three\"), ui_shape(label = bool()))\n",
    )
    .unwrap();
    let changed = capture(&db, &root, reads.clone());
    db.with_generator_files_fixture(&changed, GeneratorName::UiTypes, |a| {
        assert_ne!(a.fingerprint(), one.2);
        assert!(a
            .files()
            .iter()
            .any(|(p, t)| p.ends_with("Three.d.ts") && t.contains("label: boolean")));
        Ok(())
    })
    .unwrap();
    std::fs::write(
        root.join("deepquarry.dme"),
        "#if 0\n#include \"code/extra.dm\"\n#include \"code/probe.dm\"\n#endif\n/datum\n",
    )
    .unwrap();
    let reordered = capture(&db, &root, reads);
    let prior = db.db.stats(GENERATOR_RESULT).computed;
    db.with_generator_files_fixture(&reordered, GeneratorName::UiTypes, |a| {
        assert_eq!(a.files().len(), 2);
        Ok(())
    })
    .unwrap();
    assert!(db.db.stats(GENERATOR_RESULT).computed > prior);
}
#[test]
fn ui_types_allocation_cancel_path_refusal_never_publish_and_same_input_recovers() {
    let (db, root, reads, _) = fixture();
    std::fs::write(
        root.join("code/probe.dm"),
        "CAPABILITIES(/datum/x, interface(\"Probe\"), ui_shape(value = bool()))\n",
    )
    .unwrap();
    let c = capture(&db, &root, reads.clone());
    let called = std::cell::Cell::new(false);
    assert!(db
        .with_generator_fixture_limit(&c, GeneratorName::UiTypes, Some(1), |_| {
            called.set(true);
            Ok(())
        })
        .is_err());
    assert!(!called.get());
    db.with_generator_files_fixture(&c, GeneratorName::UiTypes, |a| {
        assert_eq!(a.files().len(), 1);
        Ok(())
    })
    .unwrap();
    let token = crate::daemon::control::Cancellation::default();
    let bound = crate::daemon::control::bind_with_deadline(
        token.clone(),
        Instant::now() + Duration::from_secs(60),
    );
    token.cancel();
    assert_eq!(
        db.with_generator_files_fixture(&c, GeneratorName::UiTypes, |_| {
            called.set(true);
            Ok(())
        })
        .unwrap_err()
        .kind(),
        io::ErrorKind::Interrupted
    );
    assert!(!called.get());
    drop(bound);
    db.with_generator_files_fixture(&c, GeneratorName::UiTypes, |a| {
        assert_eq!(a.files().len(), 1);
        Ok(())
    })
    .unwrap();
    assert!(validate_ui_output_path(
        &root,
        "tgui/packages/tgui/interfaces/generated/../escape.d.ts"
    )
    .is_err());
    assert!(validate_ui_output_path(&root, "code/escape.d.ts").is_err());
    std::fs::write(
        root.join("code/probe.dm"),
        "CAPABILITIES(/datum/x, interface(\"../Escape\"), ui_shape(value = bool()))\n",
    )
    .unwrap();
    let unsafe_c = capture(&db, &root, reads);
    assert!(db
        .with_generator_files_fixture::<()>(&unsafe_c, GeneratorName::UiTypes, |_| panic!(
            "invalid declared output must not publish"
        ))
        .is_err());
}
#[test]
fn multifile_artifact_counts_actual_capacity_and_checked_single_mode_refuses() {
    let mut files = Vec::with_capacity(7);
    let mut path = String::with_capacity(99);
    path.push_str("tgui/packages/tgui/interfaces/generated/X.d.ts");
    let mut text = String::with_capacity(333);
    text.push_str("original bytes");
    files.push((path, text));
    let a = Artifact {
        name: GeneratorName::UiTypes,
        text: String::new(),
        files,
        diags: Vec::new(),
    };
    assert!(a.single().is_err());
    assert!(a.charge() >= 7 * std::mem::size_of::<(String, String)>() + 99 + 333);
    let first = a.fingerprint();
    let mut b = Artifact {
        name: GeneratorName::UiTypes,
        text: String::new(),
        files: vec![(a.files[0].0.clone(), a.files[0].1.clone())],
        diags: Vec::new(),
    };
    assert_eq!(first, b.fingerprint());
    b.files[0].0.push('x');
    assert_ne!(first, b.fingerprint());
    let bad = Artifact {
        name: GeneratorName::SparseSlots,
        text: String::new(),
        files: vec![("bad".into(), "bad".into())],
        diags: Vec::new(),
    };
    assert!(bad.single().is_err());
}

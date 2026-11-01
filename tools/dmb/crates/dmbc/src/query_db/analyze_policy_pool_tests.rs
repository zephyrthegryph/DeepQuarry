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
pub(super) fn capture(db: &Arc<QueryDb>, root: &Path, reads: Arc<AtomicUsize>) -> Arc<Cohort> {
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

fn pool_fixture() -> (Arc<QueryDb>, PathBuf, Arc<AtomicUsize>, Arc<Cohort>) {
    let (db, root, reads, _) = fixture();
    std::fs::write(
        root.join("code/probe.dm"),
        "/datum/packet\n\tparent_type = /datum/pooled\n",
    )
    .unwrap();
    std::fs::write(
        root.join("code/extra.dm"),
        "/proc/use()\n\tvar/a = new /datum/packet\n\treturn take(/datum/packet)\n",
    )
    .unwrap();
    let c = capture(&db, &root, reads.clone());
    (db, root, reads, c)
}
#[test]
fn pool_same_db_borrowed_warm_original_owners_and_both_scope_exemptions() {
    let (db, root, reads, c) = pool_fixture();
    let before = reads.load(Ordering::Relaxed);
    let one = db
        .with_analyze_fixture_findings(&c, &["pool".into()], |rows| {
            assert_eq!(rows.len(), 1);
            assert_eq!(rows[0].run.sites.len(), 2);
            assert_eq!(rows[0].run.notes, ["pool_lint: 2 problem(s)"]);
            Ok(rows[0].run.sites.as_ptr() as usize)
        })
        .unwrap();
    let computed = db.db.stats(ANALYZE_FINDINGS).computed;
    let two = db
        .with_analyze_fixture_findings(&c, &["pool".into()], |rows| {
            Ok(rows[0].run.sites.as_ptr() as usize)
        })
        .unwrap();
    assert_eq!(one, two);
    assert_eq!(computed, db.db.stats(ANALYZE_FINDINGS).computed);
    assert_eq!(reads.load(Ordering::Relaxed), before);
    assert!(QueryDb::default()
        .with_analyze_fixture_findings(&c, &["pool".into()], |_| Ok(()))
        .is_err());
    assert!(db
        .analyze_fixture_findings(&c, &["pool".into()])
        .err()
        .unwrap()
        .to_string()
        .contains("borrowed"));
    std::fs::write(
        root.join("scopes.toml"),
        "[lint.pool.lists]\nexempt_prefixes=[\"code/probe.dm\"]\n",
    )
    .unwrap();
    let named = capture(&db, &root, reads.clone());
    db.with_analyze_fixture_findings(&named, &["pool".into()], |rows| {
        assert_eq!(
            rows[0].run.sites.len(),
            2,
            "named exemption keeps pooled facts"
        );
        Ok(())
    })
    .unwrap();
    std::fs::write(
        root.join("scopes.toml"),
        "[lint.pool]\nexempt_files=[\"code/probe.dm\"]\n",
    )
    .unwrap();
    let generic = capture(&db, &root, reads.clone());
    db.with_analyze_fixture_findings(&generic, &["pool".into()], |rows| {
        assert_eq!(
            rows[0].run.sites.len(),
            1,
            "generic exemption removes pooled facts but file take still leaks"
        );
        assert_eq!(rows[0].run.sites[0].rule, "take_leak");
        Ok(())
    })
    .unwrap();
    std::fs::write(
        root.join("code/extra.dm"),
        "/proc/use()\n\treturn take(/datum/packet)\n\tpacket.release()\n",
    )
    .unwrap();
    let changed = capture(&db, &root, reads);
    db.with_analyze_fixture_findings(&changed, &["pool".into()], |rows| {
        assert!(rows[0].run.sites.is_empty());
        Ok(())
    })
    .unwrap();
}
#[test]
fn pool_joint_headroom_failure_no_callback_and_cancelled_cached_read_recover() {
    let (db, root, reads, c) = pool_fixture();
    db.with_analyze_fixture_findings(&c, &["pool".into()], |rows| {
        assert_eq!(rows[0].run.sites.len(), 2);
        Ok(())
    })
    .unwrap();
    let used = db.raw_policy.charge.load(Ordering::Relaxed);
    std::fs::write(
        root.join("scopes.toml"),
        "# same policy, a different exact configuration\n",
    )
    .unwrap();
    let next = capture(&db, &root, reads);
    let called = std::cell::Cell::new(false);
    assert!(db
        .with_analyze_fixture_findings_limit(&next, &["pool".into()], Some(used + 1), |_| {
            called.set(true);
            Ok(())
        })
        .is_err());
    assert!(!called.get());
    db.with_analyze_fixture_findings(&next, &["pool".into()], |rows| {
        assert_eq!(rows[0].run.sites.len(), 2);
        Ok(())
    })
    .unwrap();
    db.with_analyze_fixture_findings(&c, &["pool".into()], |rows| {
        assert_eq!(
            rows[0].run.sites.len(),
            2,
            "old captured policy still computes correctly after unrelated denial"
        );
        Ok(())
    })
    .unwrap();
    let token = crate::daemon::control::Cancellation::default();
    let _binding = crate::daemon::control::bind_with_deadline(
        token.clone(),
        Instant::now() + Duration::from_secs(60),
    );
    token.cancel();
    assert_eq!(
        db.with_analyze_fixture_findings(&c, &["pool".into()], |_| {
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
fn borrowed_output_reservation_includes_warm_result_and_denial_recovers() {
    let (db, root, _, cohort) = fixture();
    let names = vec!["pool".into()];
    let mut ptr = 0usize;
    db.with_analyze_fixture_findings(&cohort, &names, |runs| {
        ptr = runs.as_ptr() as usize;
        Ok(())
    })
    .unwrap();
    let old = db.raw_policy.charge.load(Ordering::Relaxed);
    assert!(old > 0);
    let mut called = false;
    let denied = db.with_analyze_fixture_output(&cohort, &names, RESULT_BUDGET - old + 1, |_| {
        called = true;
        Ok(())
    });
    assert!(denied.is_err());
    assert!(!called);
    db.with_analyze_fixture_output(&cohort, &names, 4096, |runs| {
        assert_eq!(ptr, runs.as_ptr() as usize);
        Ok(())
    })
    .unwrap();
    drop(root);
}

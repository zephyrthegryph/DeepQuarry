use super::*;
use std::sync::atomic::AtomicUsize;
fn fixture(name: &str) -> (Arc<QueryDb>, PathBuf, Arc<AtomicUsize>, Arc<Cohort>) {
    let root = crate::test_scratch::dir("native-raw-cohort9");
    std::fs::create_dir_all(root.join("code")).unwrap();
    std::fs::write(root.join("deepquarry.dme"),
        "#if 0\n#include \"code/probe.dm\"\n#include \"code/extra.dm\"\n#endif\n/datum\n").unwrap();
    let (a,b,config) = match name {
        "cooldown" => (include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../analyze/fixtures/native-raw-cohort9/cooldown/code/a.dm")), include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../analyze/fixtures/native-raw-cohort9/cooldown/code/b.dm")), include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../analyze/fixtures/native-raw-cohort9/cooldown/scopes.toml"))),
        "declaration_block" => (include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../analyze/fixtures/native-raw-cohort9/declaration_block/code/a.dm")), include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../analyze/fixtures/native-raw-cohort9/declaration_block/code/b.dm")), include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../analyze/fixtures/native-raw-cohort9/declaration_block/scopes.toml"))),
        "duplicate_input_key" => (include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../analyze/fixtures/native-raw-cohort9/duplicate_input_key/code/a.dm")), include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../analyze/fixtures/native-raw-cohort9/duplicate_input_key/code/b.dm")), include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../analyze/fixtures/native-raw-cohort9/duplicate_input_key/scopes.toml"))),
        "entry_slots" => (include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../analyze/fixtures/native-raw-cohort9/entry_slots/code/a.dm")), include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../analyze/fixtures/native-raw-cohort9/entry_slots/code/b.dm")), include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../analyze/fixtures/native-raw-cohort9/entry_slots/scopes.toml"))),
        "interactions" => (include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../analyze/fixtures/native-raw-cohort9/interactions/code/a.dm")), include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../analyze/fixtures/native-raw-cohort9/interactions/code/b.dm")), include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../analyze/fixtures/native-raw-cohort9/interactions/scopes.toml"))),
        "latent" => (include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../analyze/fixtures/native-raw-cohort9/latent/code/a.dm")), include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../analyze/fixtures/native-raw-cohort9/latent/code/b.dm")), include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../analyze/fixtures/native-raw-cohort9/latent/scopes.toml"))),
        "pollers" => (include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../analyze/fixtures/native-raw-cohort9/pollers/code/a.dm")), include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../analyze/fixtures/native-raw-cohort9/pollers/code/b.dm")), include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../analyze/fixtures/native-raw-cohort9/pollers/scopes.toml"))),
        "read_back" => (include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../analyze/fixtures/native-raw-cohort9/read_back/code/a.dm")), include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../analyze/fixtures/native-raw-cohort9/read_back/code/b.dm")), include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../analyze/fixtures/native-raw-cohort9/read_back/scopes.toml"))),
        "cap_bits" => (include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../analyze/fixtures/native-raw-cohort9/cap_bits/code/a.dm")), include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../analyze/fixtures/native-raw-cohort9/cap_bits/code/b.dm")), include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../analyze/fixtures/native-raw-cohort9/cap_bits/scopes.toml"))),
        _ => panic!("unissued fixture"),
    };
    std::fs::write(root.join("code/probe.dm"), a).unwrap();
    std::fs::write(root.join("code/extra.dm"), b).unwrap();
    let config = config.replace("code/a.dm", "code/probe.dm").replace("code/b.dm", "code/extra.dm");
    std::fs::write(root.join("scopes.toml"), config).unwrap();
    let db = Arc::new(QueryDb::default()); let reads = Arc::new(AtomicUsize::new(0));
    let c = super::pool_tests::capture(&db, &root, reads.clone()); (db,root,reads,c)
}
#[test]
fn raw_cohort_nine_actual_owners_warm_no_io_foreign_db_and_borrowed_only() {
    for &name in dq_analyze::captured_raw_cohort::LINTS {
        let (db,_root,reads,c) = fixture(name); let before=reads.load(Ordering::Relaxed);
        let names=[name.into()];
        let pointer=db.with_analyze_fixture_findings(&c,&names,|rows| {
            assert_eq!(rows.len(),1); assert_eq!(rows[0].name,name);
            assert!(!rows[0].run.sites.is_empty(),"real positive coverage: {name}");
            Ok(rows[0].run.sites.as_ptr() as usize)
        }).unwrap();
        let computed=db.db.stats(ANALYZE_FINDINGS).computed;
        db.with_analyze_fixture_findings(&c,&names,|rows| {
            assert_eq!(rows[0].run.sites.as_ptr() as usize,pointer); Ok(())
        }).unwrap();
        assert_eq!(db.db.stats(ANALYZE_FINDINGS).computed,computed);
        assert_eq!(db.db.stats(dm_query::Kind(4)).computed,0,"raw whole-cohort never demands executable grammar");
        assert_eq!(reads.load(Ordering::Relaxed),before,"cold and warm query no input IO");
        assert!(QueryDb::default().with_analyze_fixture_findings(&c,&names,|_|Ok(())).is_err());
        assert!(db.analyze_fixture_findings(&c,&names).err().unwrap().to_string().contains("borrowed"));
    }
}
#[test]
fn raw_cohort_config_and_source_changes_recompute_same_db_without_query_io() {
    let (db,root,reads,c)=fixture("cooldown"); let names=["cooldown".into()];
    db.with_analyze_fixture_findings(&c,&names,|rows| {assert_eq!(rows[0].run.sites.len(),1);Ok(())}).unwrap();
    let computed=db.db.stats(ANALYZE_FINDINGS).computed;
    std::fs::write(root.join("scopes.toml"),"[lint.cooldown]\nexempt_files=[\"code/probe.dm\"]\n").unwrap();
    let configured=super::pool_tests::capture(&db,&root,reads.clone()); let before=reads.load(Ordering::Relaxed);
    db.with_analyze_fixture_findings(&configured,&names,|rows| {assert!(rows[0].run.sites.is_empty());Ok(())}).unwrap();
    assert!(db.db.stats(ANALYZE_FINDINGS).computed>computed);assert_eq!(reads.load(Ordering::Relaxed),before);
    std::fs::write(root.join("scopes.toml"),"").unwrap();
    std::fs::write(root.join("code/probe.dm"),"/proc/run()\n\tif(world.time > a)\n\t\treturn\n\tif(world.time < b)\n\t\treturn\n").unwrap();
    let changed=super::pool_tests::capture(&db,&root,reads.clone());let before=reads.load(Ordering::Relaxed);
    db.with_analyze_fixture_findings(&changed,&names,|rows| {assert_eq!(rows[0].run.sites.len(),2);Ok(())}).unwrap();
    assert_eq!(reads.load(Ordering::Relaxed),before);
}
#[test]
fn raw_cohort_joint_quota_cancel_and_deep_fanout_never_publish_and_recover() {
    let (db,root,reads,c)=fixture("interactions"); let names=["interactions".into()];
    let called=std::cell::Cell::new(false);
    assert!(db.with_analyze_fixture_findings_limit(&c,&names,Some(1),|_|{called.set(true);Ok(())}).is_err());
    assert!(!called.get());
    db.with_analyze_fixture_findings(&c,&names,|rows|{assert!(!rows[0].run.sites.is_empty());Ok(())}).unwrap();
    let old_charge=db.raw_policy.charge.load(Ordering::Relaxed);
    std::fs::write(root.join("scopes.toml"),"# same semantics, new exact config
").unwrap();
    let next=super::pool_tests::capture(&db,&root,reads.clone());
    assert!(db.with_analyze_fixture_findings_limit(&next,&names,Some(old_charge+1024),|_|{called.set(true);Ok(())}).is_err());
    assert!(!called.get());
    db.with_analyze_fixture_findings(&next,&names,|rows|{assert!(!rows[0].run.sites.is_empty());Ok(())}).unwrap();
    {
        let token=crate::daemon::control::Cancellation::default();
        let _binding=crate::daemon::control::bind_with_deadline(token.clone(),Instant::now()+Duration::from_secs(60));token.cancel();
        assert_eq!(db.with_analyze_fixture_findings(&c,&names,|_|{called.set(true);Ok(())}).unwrap_err().kind(),io::ErrorKind::Interrupted);
    }
    assert!(!called.get());db.with_analyze_fixture_findings(&c,&names,|_|Ok(())).unwrap();
    // Real retained input is below existing per-file admission, but short-name
    // depth and repeated cross-file owner fanout must fail BEFORE legacy maps.
    let parent=format!("/obj/{}root","a/".repeat(128));
    let mut source=String::new();for i in 0..128 {source.push_str(&format!("DECLARE_INTERACTIONS({parent}/c{i})\n"));}
    assert!(source.len()<dq_analyze::captured_raw_policy::MAX_FIXTURE_FILE_BYTES);
    std::fs::write(root.join("code/probe.dm"),source).unwrap();
    let deep=super::pool_tests::capture(&db,&root,reads.clone());
    assert!(db.with_analyze_fixture_findings(&deep,&names,|_|{called.set(true);Ok(())}).is_err());assert!(!called.get());
    std::fs::write(root.join("code/probe.dm"),"DECLARE_INTERACTIONS(/obj/p)\nDECLARE_INTERACTIONS(/obj/p/c)\n").unwrap();
    let retry=super::pool_tests::capture(&db,&root,reads);
    db.with_analyze_fixture_findings(&retry,&names,|rows|{assert_eq!(rows[0].run.sites.len(),1);Ok(())}).unwrap();
}

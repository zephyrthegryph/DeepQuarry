use super::*;
use std::sync::atomic::AtomicUsize;
fn fixture()->(Arc<QueryDb>,PathBuf,Arc<AtomicUsize>,Arc<Cohort>){
 let root=crate::test_scratch::dir("native-whole-keys");std::fs::create_dir_all(root.join("code")).unwrap();
 std::fs::write(root.join("deepquarry.dme"),"#if 0\n#include \"code/probe.dm\"\n#include \"code/extra.dm\"\n#endif\n/datum\n").unwrap();
 std::fs::write(root.join("code/probe.dm"),"STAT(/datum/probe, energy)\nCAPABILITIES(/datum/probe, op(\"real\"), extend(\"missing\"))\n").unwrap();
 std::fs::write(root.join("code/extra.dm"),"STAT(/datum/probe, energy)\n").unwrap();
 let db=Arc::new(QueryDb::default());let reads=Arc::new(AtomicUsize::new(0));let c=super::pool_tests::capture(&db,&root,reads.clone());(db,root,reads,c)
}
#[test]
fn keys_actual_native_query_is_borrowed_zero_body_no_io_and_tracks_original_manifest_order(){
 let(db,root,reads,c)=fixture();let names=vec!["sem/keys".to_string()];let before=reads.load(Ordering::Relaxed);
 assert!(db.analyze_fixture_findings(&c,&names).is_err(),"bounded keys never clones payload outside its family gate");
 db.with_analyze_fixture_findings(&c,&names,|runs|{let duplicate=runs[0].run.sites.iter().find(|r|r.rule=="duplicate_declaration").unwrap();assert_eq!(duplicate.rel,"code/extra.dm");assert_eq!(runs[0].run.sites.len(),2);Ok(())}).unwrap();
 let computed=db.db.stats(ANALYZE_FINDINGS).computed;
 db.with_analyze_fixture_findings(&c,&names,|runs|{assert_eq!(runs[0].run.sites.len(),2);Ok(())}).unwrap();
 assert_eq!(db.db.stats(ANALYZE_FINDINGS).computed,computed);assert_eq!(db.db.stats(Kind(4)).computed,0);assert_eq!(reads.load(Ordering::Relaxed),before);
 std::fs::write(root.join("deepquarry.dme"),"#if 0\n#include \"code/extra.dm\"\n#include \"code/probe.dm\"\n#endif\n/datum\n").unwrap();
 let next=super::pool_tests::capture(&db,&root,reads.clone());let before=reads.load(Ordering::Relaxed);
 db.with_analyze_fixture_findings(&next,&names,|runs|{let duplicate=runs[0].run.sites.iter().find(|r|r.rule=="duplicate_declaration").unwrap();assert_eq!(duplicate.rel,"code/probe.dm");Ok(())}).unwrap();
 assert_eq!(reads.load(Ordering::Relaxed),before);assert_eq!(db.db.stats(Kind(4)).computed,0);
}
#[test]
fn keys_actual_mid_query_cancellation_and_resource_refusal_never_publish_then_same_source_recovers(){
 let(db,_root,_reads,c)=fixture();let names=vec!["sem/keys".to_string()];let called=std::cell::Cell::new(false);
 {let token=crate::daemon::control::Cancellation::default();let _binding=crate::daemon::control::bind_with_deadline(token.clone(),Instant::now()+Duration::from_secs(60));db.raw_policy.admission.abort.cancel_on_poll(15,token);
 let error=db.with_analyze_fixture_findings(&c,&names,|_|{called.set(true);Ok(())}).unwrap_err();assert_eq!(error.kind(),io::ErrorKind::Interrupted);db.raw_policy.admission.abort.disarm();}
 assert!(!called.get());
 assert!(db.with_analyze_fixture_findings_limit(&c,&names,Some(1024),|_|{called.set(true);Ok(())}).is_err());assert!(!called.get());
 db.with_analyze_fixture_findings(&c,&names,|runs|{assert_eq!(runs[0].run.sites.len(),2);Ok(())}).unwrap();
}

use super::*;
use crate::{input_snapshot::{FolderListing,RecordingInputs,SnapshotProvider,Stamp},
    policy_request::{PolicyInputFile,PolicyInputRequest,PolicyInputRole}};
use std::sync::atomic::AtomicUsize;
#[path="../../../dm-analysis/examples/support/reference_hierarchy.rs"]mod reference_hierarchy;
#[derive(Clone)]struct Source{reads:Arc<AtomicUsize>,list:bool,config:bool,collision:bool}
impl Source{
 fn bytes(&self,path:&Path)->io::Result<&'static [u8]>{match path.file_name().and_then(|s|s.to_str()){
 Some("deepquarry.dme")=>Ok(b"#include \"code/sub/../probe.dm\"\n"),
 Some("probe.dm") if self.list&&self.collision=>Ok(b"#define TRACKED(T,v)\n/datum/owner\n    var/list/items=list()\nTRACKED(/datum/owner,items)\n/datum/owner\n    proc/add_items(x)\n        return x\n/proc/tail()\n    return\n"),
 Some("probe.dm") if self.list=>Ok(b"#define TRACKED(T,v)\n/datum/owner\n    var/list/items=list()\nTRACKED(/datum/owner,items)\n/proc/tail()\n    return\n"),
 Some("probe.dm")=>Ok(b"#define TRACKED(T,v)\n/datum/owner\n    var/items=list()\nTRACKED(/datum/owner,items)\n/proc/tail()\n    return\n"),
 Some("scopes.toml") if self.config=>Ok(b"# current captured configuration\n"),
 _=>Err(io::ErrorKind::NotFound.into())}}
}
impl SnapshotProvider for Source{
 fn stamp(&self,p:&Path)->io::Result<Stamp>{self.reads.fetch_add(1,Ordering::Relaxed);Ok(Stamp{size:self.bytes(p)?.len() as u64,modified_ns:1,file_id:Some(1)})}
 fn read(&self,p:&Path)->io::Result<(Stamp,Vec<u8>)>{self.reads.fetch_add(1,Ordering::Relaxed);Ok((self.stamp(p)?,self.bytes(p)?.to_vec()))}
 fn list(&self,path:&Path)->io::Result<FolderListing>{
  self.reads.fetch_add(1,Ordering::Relaxed);
  let path=dm_preprocess::regions::canonical_path(path);
  Ok(if path.ends_with("tracked-generator-provider"){
    let mut names=vec!["code".into(),"deepquarry.dme".into()];
    if self.config{names.push("scopes.toml".into());}FolderListing::Present(names)
  }else if path.ends_with("tracked-generator-provider/code"){
    FolderListing::Present(vec!["probe.dm".into(),"sub".into()])
  }else if path.ends_with("tracked-generator-provider/code/sub"){
    FolderListing::Present(vec![])
  }else{FolderListing::Missing})
 }
}
fn cohort(db:&Arc<QueryDb>,reads:Arc<AtomicUsize>,list:bool,config:bool)->Arc<Cohort>{cohort_with_collision(db,reads,list,config,false)}
fn cohort_with_collision(db:&Arc<QueryDb>,reads:Arc<AtomicUsize>,list:bool,config:bool,collision:bool)->Arc<Cohort>{
 let root=std::env::current_dir().unwrap().join("tracked-generator-provider");
 let inputs=RecordingInputs::new(Source{reads,list,config,collision},1);
 let seed=reference_hierarchy::seed();let executor=dm_exec::BuildExecutor::new(1).unwrap();
 let front=dm_tree::frontend::build_with_executor_and_semantic_state_for_policy(
 &root.join("deepquarry.dme"),&inputs,&Default::default(),dm_tree::frontend::FrontendConfig{workers:1,engine:Some(&seed),observer:None},None,&executor,None,true)
 .unwrap().with_body_queries(db.clone());
 let intent=PolicyInputRequest{analysis_context:None,workspace_auxiliary:Vec::new(),workspace_generators:Vec::new(),workspace:None,files:vec![PolicyInputFile{path:root.join("scopes.toml"),role:PolicyInputRole::Configuration,required:false}],search_folders:vec![]}.admit().unwrap();
 let captured=Arc::new(crate::runner_host::policy_capture::capture(&front,&inputs,&intent.capture_files(),&[]).unwrap().bind_request(&intent).unwrap());
 db.raw_cohort(captured,&root,&root.join("scopes.toml")).unwrap()
}
#[test]
fn tracked_lists_original_native_type_owner_warm_config_source_and_no_io(){
 let db=Arc::new(QueryDb::default());let reads=Arc::new(AtomicUsize::new(0));
 let c=cohort(&db,reads.clone(),true,false);let before=reads.load(Ordering::Relaxed);
 let (pointer,text)=db.with_generator_fixture(&c,GeneratorName::TrackedLists,|a|{
    assert_eq!(a.name(),"tracked_lists");assert!(a.diagnostics().is_empty());
    assert_eq!(a.text().matches("/// TRACKED(").count(),1);
    assert!(a.text().contains("/datum/owner/proc/add_items(x)"));
    assert_eq!(a.path(),"code/engine/_generated/tracked_lists.dm");Ok((a.text().as_ptr() as usize,a.text().to_owned()))}).unwrap();
 let computed=db.db.stats(GENERATOR_RESULT).computed;
 db.with_generator_fixture(&c,GeneratorName::TrackedLists,|a|{assert_eq!(a.text().as_ptr() as usize,pointer);assert_eq!(a.text(),text);Ok(())}).unwrap();
 assert_eq!(db.db.stats(GENERATOR_RESULT).computed,computed);assert_eq!(reads.load(Ordering::Relaxed),before,"warm and cold queries use captures only");
 let configured=cohort(&db,reads.clone(),true,true);let before=reads.load(Ordering::Relaxed);
 db.with_generator_fixture(&configured,GeneratorName::TrackedLists,|a|{assert_eq!(a.text(),text);Ok(())}).unwrap();
 assert_eq!(reads.load(Ordering::Relaxed),before);
 let untyped=cohort(&db,reads.clone(),false,true);let before=reads.load(Ordering::Relaxed);
 db.with_generator_fixture(&untyped,GeneratorName::TrackedLists,|a|{assert_eq!(a.text().matches("/// TRACKED(").count(),0);assert!(!a.text().contains("/proc/add_items"));Ok(())}).unwrap();
 assert_eq!(reads.load(Ordering::Relaxed),before,"list initializer cannot replace declared list type");
}
#[test]
fn tracked_lists_real_quota_and_cancellation_never_deliver_and_same_input_recovers(){
 let db=Arc::new(QueryDb::default());let c=cohort(&db,Arc::new(AtomicUsize::new(0)),true,false);
 let delivered=AtomicUsize::new(0);
 assert!(db.with_generator_fixture_limit(&c,GeneratorName::TrackedLists,Some(64),|_|{delivered.fetch_add(1,Ordering::Relaxed);Ok(())}).is_err());
 assert_eq!(delivered.load(Ordering::Relaxed),0);
 let token=crate::daemon::control::Cancellation::default();let binding=crate::daemon::control::bind_with_deadline(token.clone(),Instant::now()+Duration::from_secs(30));token.cancel();
 let error=db.with_generator_fixture(&c,GeneratorName::TrackedLists,|_|{delivered.fetch_add(1,Ordering::Relaxed);Ok(())}).unwrap_err();
 assert_eq!(error.kind(),io::ErrorKind::Interrupted);assert_eq!(delivered.load(Ordering::Relaxed),0);drop(binding);
 db.with_generator_fixture(&c,GeneratorName::TrackedLists,|a|{assert!(a.text().contains("/proc/add_items(x)"));delivered.fetch_add(1,Ordering::Relaxed);Ok(())}).unwrap();
 assert_eq!(delivered.load(Ordering::Relaxed),1);
}

#[test]
fn tracked_lists_equivalent_captured_provider_keys_do_not_omit_original_nearest_owner_collision(){
 let db=Arc::new(QueryDb::default());let c=cohort_with_collision(&db,Arc::new(AtomicUsize::new(0)),true,false,true);
 let inputs=c.capture.policy();let root=&c.root;
 let mut shared=Vec::new();let mut different=false;
 for file in inputs.files().filter(|f|f.role()==dm_analysis::policy_inputs::PolicyRole::DmSource){
    let path=if file.path().ends_with("probe.dm"){root.join("code/alternate/../probe.dm")}else{file.path().as_ref().clone()};
    if file.path().ends_with("probe.dm"){assert_ne!(&path,file.path().as_ref());different=true;}
    shared.push(Arc::new(dq_analyze::captured_raw_file::File::capture(root,&path,
        file.view(dm_analysis::policy_inputs::TextView::AnalyzeRaw).unwrap().clone()).unwrap()));
 }
 assert!(different);
 let config=dq_analyze::captured_raw_file::Config::capture(dq_analyze::captured_raw_policy::Configuration::ProvenMissing).unwrap();
 let raw=dq_analyze::captured_raw_policy::CapturedRawPolicy::from_shared_files(root,inputs,&config,&shared).unwrap();
 let budget=dq_analyze::captured_generator_budget::Budget::new(64*1024*1024).unwrap();
 let actual=dq_analyze::captured_tracked_lists::BorrowedTrackedLists::capture(&raw,inputs,budget).unwrap().generate(||Ok(())).unwrap();
 assert_eq!(actual.diags.len(),1,"actual nested proc collision cannot disappear under equivalent raw key");
 assert!(actual.diags[0].msg.contains("add_items"));assert!(!actual.body.contains("/proc/add_items"));
 assert_eq!(db.db.stats(dm_query::Kind(4)).computed,0,"declaration collision scan must not demand executable body grammar");
}

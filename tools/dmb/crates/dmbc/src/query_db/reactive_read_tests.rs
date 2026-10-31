use super::*;
use crate::{input_snapshot::{FolderListing,RecordingInputs,SnapshotProvider,Stamp},policy_request::{PolicyInputFile,PolicyInputRequest,PolicyInputRole}};
use std::sync::atomic::AtomicUsize;
#[path="../../../dm-analysis/examples/support/reference_hierarchy.rs"]mod reference_hierarchy;
#[derive(Clone)]struct Source{reads:Arc<AtomicUsize>,body:&'static str,configured:bool}
impl Source{fn bytes(&self,path:&Path)->io::Result<&'static [u8]>{match path.file_name().and_then(|s|s.to_str()){
 Some("deepquarry.dme")=>Ok(b"#include \"code/probe.dm\"\n"),Some("probe.dm")=>Ok(self.body.as_bytes()),Some("scopes.toml")if self.configured=>Ok(b"# exact configuration changed\n"),_=>Err(io::ErrorKind::NotFound.into())}}}
impl SnapshotProvider for Source{
 fn stamp(&self,p:&Path)->io::Result<Stamp>{self.reads.fetch_add(1,Ordering::Relaxed);Ok(Stamp{size:self.bytes(p)?.len() as u64,modified_ns:1,file_id:Some(1)})}
 fn read(&self,p:&Path)->io::Result<(Stamp,Vec<u8>)>{self.reads.fetch_add(1,Ordering::Relaxed);Ok((self.stamp(p)?,self.bytes(p)?.to_vec()))}
 fn list(&self,p:&Path)->io::Result<FolderListing>{self.reads.fetch_add(1,Ordering::Relaxed);let p=dm_preprocess::regions::canonical_path(p);Ok(if p.ends_with("reactive-original-provider"){let mut v=vec!["code".into(),"deepquarry.dme".into()];if self.configured{v.push("scopes.toml".into())}FolderListing::Present(v)}else if p.ends_with("reactive-original-provider/code"){FolderListing::Present(vec!["probe.dm".into()])}else{FolderListing::Missing})}
}
const BODY:&str="#define TRACKED(T,v)\nvar/global_counter=1\n/datum/probe\n    var/value\n    proc/leaf()\n        return value\n    proc/global_read()\n        return global_counter\n    proc/unrelated()\n        return 99\n    proc/write_global()\n        global_counter=2\nTRACKED(/datum/probe,value)\n";
struct Fixture{db:Arc<QueryDb>,reads:Arc<AtomicUsize>,root:PathBuf,inputs:RecordingInputs<Source>,front:dm_tree::frontend::FrontendRevision,state:std::cell::RefCell<dm_tree::frontend::RetainedSemanticTree>}
impl Fixture{
 fn new(body:&'static str,configured:bool)->Self{Self::new_with_db(Arc::new(QueryDb::default()),body,configured)}
 fn new_with_db(db:Arc<QueryDb>,body:&'static str,configured:bool)->Self{let root=std::env::current_dir().unwrap().join("reactive-original-provider");let reads=Arc::new(AtomicUsize::new(0));let inputs=RecordingInputs::new(Source{reads:Arc::clone(&reads),body,configured},1).with_prepared_sources(Some(Arc::new(crate::input_snapshot::PreparedInputArtifacts::default())));let seed=reference_hierarchy::seed();let executor=dm_exec::BuildExecutor::new(1).unwrap();let mut state=dm_tree::frontend::RetainedSemanticTree::one_shot();let front=dm_tree::frontend::build_with_executor_and_semantic_state_for_policy(&root.join("deepquarry.dme"),&inputs,&Default::default(),dm_tree::frontend::FrontendConfig{workers:1,engine:Some(&seed),observer:None},None,&executor,Some(&mut state),true).unwrap().with_body_queries(db.clone());let front=dm_tree::frontend::FrontendRevision::new(front);state.remember_frontend(&root.join("deepquarry.dme"),&Default::default(),front.clone());Self{db,reads,root,inputs,front,state:std::cell::RefCell::new(state)}}
 fn capture(&self)->Arc<Cohort>{self.capture_front(&self.front)}
 fn capture_front(&self,front:&dm_tree::frontend::ColdFrontend)->Arc<Cohort>{let intent=PolicyInputRequest{workspace:None,files:vec![PolicyInputFile{path:self.root.join("scopes.toml"),role:PolicyInputRole::Configuration,required:false}],search_folders:vec![]}.admit().unwrap();let capture=Arc::new(crate::runner_host::policy_capture::capture(front,&self.inputs,&intent.capture_files(),&[]).unwrap().bind_request(&intent).unwrap());self.db.raw_cohort(capture,&self.root,&self.root.join("scopes.toml")).unwrap()}
 fn reissue(&self)->dm_tree::frontend::ColdFrontend{let seed=reference_hierarchy::seed();let executor=dm_exec::BuildExecutor::new(1).unwrap();dm_tree::frontend::build_with_executor_and_semantic_state_for_policy(&self.root.join("deepquarry.dme"),&self.inputs,&Default::default(),dm_tree::frontend::FrontendConfig{workers:1,engine:Some(&seed),observer:None},None,&executor,Some(&mut self.state.borrow_mut()),true).unwrap().with_body_queries(self.db.clone())}
}
fn request(name:&str)->Request{Request::Read{receiver:"/datum/probe".into(),procedure:name.into(),context:None,flavor:Flavor::Closed}}
#[test]
fn actual_read_leaf_is_lazy_and_fresh_capture_same_frontend_reuses_complete_original_value(){
 let fixture=Fixture::new(BODY,false);let first=fixture.capture();assert_eq!(fixture.db.db.stats(crate::query_db::body_syntax::BODY_SYNTAX).computed,0);let before=fixture.reads.load(Ordering::Relaxed);
 let pointer=fixture.db.with_reactive_fixture(&first,request("leaf"),|value|{let Value::Reads(value)=value else{panic!("actual read role")};assert_eq!(value.facts().reads().len(),1);assert_eq!(value.facts().reads()[0].var,"value");Ok(value.facts().reads().as_ptr() as usize)}).unwrap();
 assert_eq!(fixture.reads.load(Ordering::Relaxed),before);assert_eq!(fixture.db.db.stats(crate::query_db::body_syntax::BODY_SYNTAX).computed,1,"unrelated bodies and globals remain undemanded");assert_eq!(fixture.db.db.stats(REACTIVE_RESULT).computed,1,"no eager Globals node");
 let second=fixture.capture();assert!(!Arc::ptr_eq(first.capture.policy().archive(),second.capture.policy().archive()));assert_ne!(first.capture.semantic_source_evidence().key(),second.capture.semantic_source_evidence().key());assert_eq!(source_locator(&first.capture).unwrap(),source_locator(&second.capture).unwrap());let before=fixture.reads.load(Ordering::Relaxed);
 fixture.db.with_reactive_fixture(&second,request("leaf"),|value|{let Value::Reads(value)=value else{panic!("actual read role")};assert_eq!(value.facts().reads().as_ptr() as usize,pointer);Ok(())}).unwrap();assert_eq!(fixture.db.db.stats(REACTIVE_RESULT).computed,1);assert_eq!(fixture.db.db.stats(crate::query_db::body_syntax::BODY_SYNTAX).computed,1);assert_eq!(fixture.reads.load(Ordering::Relaxed),before);
 let foreign=QueryDb::default();assert!(foreign.with_reactive_fixture(&first,request("leaf"),|_|Ok(())).is_err());
}
#[test]
fn actual_global_question_lazily_computes_one_shared_global_result_and_tracks_real_body_edges(){
 let fixture=Fixture::new(BODY,false);let capture=fixture.capture();fixture.db.with_reactive_fixture(&capture,request("leaf"),|_|Ok(())).unwrap();
 fixture.db.with_reactive_fixture(&capture,request("global_read"),|value|{let Value::Reads(value)=value else{panic!("actual read role")};assert!(value.facts().diagnostics().iter().any(|d|d.rule=="untracked_global"));Ok(())}).unwrap();
 let n=fixture.db.db.stats(REACTIVE_RESULT).computed;assert_eq!(n,3,"leaf + global read + one global classifier");let bodies=fixture.db.db.stats(crate::query_db::body_syntax::BODY_SYNTAX).computed;
 fixture.db.with_reactive_fixture(&capture,request("global_read"),|_|Ok(())).unwrap();assert_eq!(fixture.db.db.stats(REACTIVE_RESULT).computed,n);assert_eq!(fixture.db.db.stats(crate::query_db::body_syntax::BODY_SYNTAX).computed,bodies);
 let gate=fixture.db.raw_policy.gate.lock().unwrap();let leases=fixture.db.raw_policy.admission.leases.lock().unwrap();let derived=leases.keys().filter(|k|k.kind==REACTIVE_RESULT).copied().collect::<Vec<_>>();drop(leases);drop(gate);
 assert_eq!(derived.len(),3);let body_key=Key::new(crate::query_db::body_syntax::BODY_SYNTAX,capture.capture.policy().archive().syntax_inputs().unwrap()[0].key().into());let dependants=fixture.db.db.dependants(&[body_key]);assert!(derived.iter().any(|key|dependants.contains(key)),"real Kind12 -> Kind4 edge, not same-host identity");
}
#[test]
fn actual_read_cancel_returns_no_payload_and_same_original_capture_recovers(){
 let fixture=Fixture::new(BODY,false);let capture=fixture.capture();let delivered=AtomicUsize::new(0);let token=crate::daemon::control::Cancellation::default();let binding=crate::daemon::control::bind_with_deadline(token.clone(),Instant::now()+Duration::from_secs(30));token.cancel();
 let error=fixture.db.with_reactive_fixture(&capture,request("leaf"),|_|{delivered.fetch_add(1,Ordering::Relaxed);Ok(())}).unwrap_err();assert_eq!(error.kind(),io::ErrorKind::Interrupted);assert_eq!(delivered.load(Ordering::Relaxed),0);drop(binding);
 fixture.db.with_reactive_fixture(&capture,request("leaf"),|_|{delivered.fetch_add(1,Ordering::Relaxed);Ok(())}).unwrap();assert_eq!(delivered.load(Ordering::Relaxed),1);
}

#[test]
fn genuine_mapping_reissue_recomputes_under_current_evidence_without_reparsing_shared_body(){
 let fixture=Fixture::new(BODY,false);let old=fixture.capture();let old_pointer=fixture.db.with_reactive_fixture(&old,request("leaf"),|value|{let Value::Reads(v)=value else{panic!("actual read role")};Ok(v.facts().reads().as_ptr() as usize)}).unwrap();let bodies=fixture.db.db.stats(crate::query_db::body_syntax::BODY_SYNTAX).computed;
 let current=fixture.reissue();assert_eq!(current.timings.declaration_parsing,Duration::ZERO,"genuine retained whole-program path");
 assert!(Arc::ptr_eq(&fixture.front.syntax,&current.syntax),"actual unchanged declaration owner, not only semantic equality");
 let current_archive=current.body_archive().unwrap();let original=old.capture.policy().archive();
 for ordinal in 0..fixture.front.plan.occurrences.len(){assert!(original.source_acquisition(ordinal).unwrap().same_original_acquisition(current_archive.source_acquisition(ordinal).unwrap()),"real prepared original acquisition must survive request refresh");}
 let captured=fixture.capture_front(&current);
 assert_eq!(source_locator(&old.capture).unwrap(),source_locator(&captured.capture).unwrap(),"SAME original parser input roster");assert!(!Arc::ptr_eq(old.capture.policy().mapping(),captured.capture.policy().mapping()),"actual current mapping reissued");
 let computed=fixture.db.db.stats(REACTIVE_RESULT).computed;fixture.db.with_reactive_fixture(&captured,request("leaf"),|value|{let Value::Reads(v)=value else{panic!("actual read role")};assert_ne!(v.facts().reads().as_ptr() as usize,old_pointer);assert!(v.matches(captured.capture.policy()));assert_eq!(v.facts().reads()[0].var,"value");Ok(())}).unwrap();assert_eq!(fixture.db.db.stats(REACTIVE_RESULT).computed,computed+1,"source-foreign cached value declined then fresh-evidence computation");assert_eq!(fixture.db.db.stats(crate::query_db::body_syntax::BODY_SYNTAX).computed,bodies,"current source wrapper reuses SAME original canonical body query");
}

#[test]
fn actual_kind12_quota_has_no_outcome_and_warm_current_headroom_does_not_poison_recovery(){
 let fixture=Fixture::new(BODY,false);let capture=fixture.capture();let delivered=AtomicUsize::new(0);
 assert!(fixture.db.with_reactive_fixture_limit(&capture,request("leaf"),Some(64),|_|{delivered.fetch_add(1,Ordering::Relaxed);Ok(())}).is_err());assert_eq!(delivered.load(Ordering::Relaxed),0);assert_eq!(fixture.db.db.stats(REACTIVE_RESULT).computed,0);
 let pointer=fixture.db.with_reactive_fixture(&capture,request("leaf"),|v|{let Value::Reads(v)=v else{panic!("actual role")};Ok(v.facts().reads().as_ptr() as usize)}).unwrap();let computed=fixture.db.db.stats(REACTIVE_RESULT).computed;
 assert!(fixture.db.with_reactive_fixture_limit(&capture,request("leaf"),Some(64),|_|{delivered.fetch_add(1,Ordering::Relaxed);Ok(())}).is_err());assert_eq!(delivered.load(Ordering::Relaxed),0);
 fixture.db.with_reactive_fixture(&capture,request("leaf"),|v|{let Value::Reads(v)=v else{panic!("actual role")};assert_eq!(v.facts().reads().as_ptr() as usize,pointer);Ok(())}).unwrap();assert_eq!(fixture.db.db.stats(REACTIVE_RESULT).computed,computed);
}
#[test]
fn equal_text_foreign_and_real_later_body_or_header_edit_never_reuse_source_owners(){
 let first=Fixture::new(BODY,false);let old=first.capture();first.db.with_reactive_fixture(&old,request("leaf"),|_|Ok(())).unwrap();
 let foreign=Fixture::new_with_db(Arc::clone(&first.db),BODY,false);let c=foreign.capture();assert_ne!(source_locator(&old.capture).unwrap(),source_locator(&c.capture).unwrap());let before=first.db.db.stats(REACTIVE_RESULT).computed;
 first.db.with_reactive_fixture(&c,request("leaf"),|value|{let Value::Reads(value)=value else{panic!("actual role")};assert!(value.matches(c.capture.policy()));assert!(!value.matches(old.capture.policy()));Ok(())}).unwrap();assert_eq!(first.db.db.stats(REACTIVE_RESULT).computed,before+1);
 for text in [BODY.replace("return 99","return 98"),BODY.replace("proc/unrelated()","proc/unrelated(x)")] {
  let current=Fixture::new_with_db(Arc::clone(&first.db),Box::leak(text.into_boxed_str()),false);let c=current.capture();assert_ne!(source_locator(&old.capture).unwrap(),source_locator(&c.capture).unwrap());first.db.with_reactive_fixture(&c,request("leaf"),|value|{let Value::Reads(value)=value else{panic!("actual role")};assert!(value.matches(c.capture.policy()));assert!(!value.matches(old.capture.policy()));Ok(())}).unwrap();
 }
}

#[test]
fn actual_full_original_global_fixture_emits_complete_admitted_comparison_payload(){
 #[derive(Clone)]struct Files(Arc<AtomicUsize>);
 impl SnapshotProvider for Files{
  fn stamp(&self,p:&Path)->io::Result<Stamp>{self.0.fetch_add(1,Ordering::Relaxed);crate::input_snapshot::FileSystemInputs.stamp(p)}
  fn read(&self,p:&Path)->io::Result<(Stamp,Vec<u8>)>{self.0.fetch_add(1,Ordering::Relaxed);crate::input_snapshot::FileSystemInputs.read(p)}
  fn list(&self,p:&Path)->io::Result<FolderListing>{self.0.fetch_add(1,Ordering::Relaxed);crate::input_snapshot::FileSystemInputs.list(p)}
 }
 let root=Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../analyze/fixtures/native-global-classifier");let reads=Arc::new(AtomicUsize::new(0));let inputs=RecordingInputs::new(Files(Arc::clone(&reads)),1);let db=Arc::new(QueryDb::default());let seed=reference_hierarchy::seed();let executor=dm_exec::BuildExecutor::new(1).unwrap();
 let front=dm_tree::frontend::build_with_executor_and_semantic_state_for_policy(&root.join("deepquarry.dme"),&inputs,&Default::default(),dm_tree::frontend::FrontendConfig{workers:1,engine:Some(&seed),observer:None},None,&executor,None,true).unwrap().with_body_queries(db.clone());
 let intent=PolicyInputRequest{workspace:None,files:vec![PolicyInputFile{path:root.join("scopes.toml"),role:PolicyInputRole::Configuration,required:false}],search_folders:vec![]}.admit().unwrap();let capture=Arc::new(crate::runner_host::policy_capture::capture(&front,&inputs,&intent.capture_files(),&[]).unwrap().bind_request(&intent).unwrap());
 for relative in ["code/globals.dm","code/types.dm","code/calls.dm","code/tests/ignored.dm"]{assert!(capture.policy().file(&root.join(relative)).is_some(),"entire original fixture must be captured: {relative}");}
 let cohort=db.raw_cohort(capture,&root,&root.join("scopes.toml")).unwrap();assert_eq!(db.db.stats(crate::query_db::body_syntax::BODY_SYNTAX).computed,0);let before=reads.load(Ordering::Relaxed);
 db.with_reactive_fixture(&cohort,Request::Globals,|value|{
  let Value::Globals(value)=value else{panic!("actual complete global result")};
  struct Output{bytes:Vec<u8>,budget:Arc<Budget>,first:Option<io::Error>}
  impl io::Write for Output{
   fn write(&mut self,bytes:&[u8])->io::Result<usize>{
    if self.first.is_some(){return Err(io::Error::other("test admitted output stopped"))}
    let operation=(||{crate::daemon::control::checkpoint()?;let need=self.bytes.len().checked_add(bytes.len()).ok_or_else(||io::Error::new(io::ErrorKind::OutOfMemory,"test output size overflow"))?;
     if need>self.bytes.capacity(){let requested=need.max(self.bytes.capacity().saturating_mul(2)).max(256);let reservation=requested.checked_mul(4).and_then(|n|n.checked_add(64)).ok_or_else(||io::Error::new(io::ErrorKind::OutOfMemory,"test output capacity overflow"))?;self.budget.charge(reservation).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;self.bytes.try_reserve_exact(requested-self.bytes.len()).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;if self.bytes.capacity().checked_mul(1).is_none_or(|n|n>reservation){return Err(io::Error::new(io::ErrorKind::OutOfMemory,"test output exposed capacity exceeds reservation"))}}
     self.bytes.extend_from_slice(bytes);Ok(bytes.len())})();
    match operation{Ok(n)=>Ok(n),Err(actual)=>{self.first=Some(actual);Err(io::Error::other("test admitted output stopped"))}}
   }
   fn flush(&mut self)->io::Result<()>{Ok(())}
  }
  let available=RESULT_BUDGET.checked_sub(db.raw_policy.charge.load(Ordering::Acquire)).ok_or_else(||io::Error::new(io::ErrorKind::OutOfMemory,"global comparison output headroom"))?;let budget=Budget::new(available).map_err(io::Error::other)?;
  let mut output=Output{bytes:Vec::new(),budget,first:None};let serialized=value.serialize_facts(&mut serde_json::Serializer::new(&mut output));if let Some(actual)=output.first.take(){return Err(actual)}serialized.map_err(io::Error::other)?;crate::daemon::control::checkpoint()?;
  let json=String::from_utf8(output.bytes).map_err(io::Error::other)?;println!("NATIVE_GLOBAL_FULL={json}");Ok(())
 }).unwrap();assert_eq!(reads.load(Ordering::Relaxed),before,"native query/output must not reread fixture source");
}

#[test]
fn reactive_key_schema_borrows_namespaced_ids_identically_from_prepared_rows_and_slices(){
 let keys=[Key::new(Kind(7),1),Key::new(Kind(8),u128::MAX)];let prepared=[(keys[0],42u128,()),(keys[1],99u128,())];
 let expected=serde_json::to_vec(&[(7u16,1u128),(8u16,u128::MAX)]).unwrap();
 let from_keys=serde_json::to_vec(&KeyRows(keys.iter())).unwrap();let from_prepared=serde_json::to_vec(&KeyRows(prepared.iter().map(|(key,_,_)|key))).unwrap();assert_eq!(from_keys,expected);assert_eq!(from_prepared,expected);
 let streamed=metadata_key(&KeyRows(keys.iter())).unwrap();assert_eq!(streamed.kind,REACTIVE_RESULT);assert_eq!(streamed.id,dm_query::hash_bytes(&expected));assert_eq!(metadata_key(&KeyRows(prepared.iter().map(|(key,_,_)|key))).unwrap(),streamed);
 let different=[Key::new(Kind(8),1),keys[1]];assert_ne!(metadata_key(&KeyRows(different.iter())).unwrap(),streamed,"key namespace participates, not only numeric id");
}

#[test]
fn actual_full_original_read_fixture_emits_all_ordered_result_fields(){
 #[derive(Clone)]struct Files(Arc<AtomicUsize>);
 impl SnapshotProvider for Files{
  fn stamp(&self,p:&Path)->io::Result<Stamp>{self.0.fetch_add(1,Ordering::Relaxed);crate::input_snapshot::FileSystemInputs.stamp(p)}
  fn read(&self,p:&Path)->io::Result<(Stamp,Vec<u8>)>{self.0.fetch_add(1,Ordering::Relaxed);crate::input_snapshot::FileSystemInputs.read(p)}
  fn list(&self,p:&Path)->io::Result<FolderListing>{self.0.fetch_add(1,Ordering::Relaxed);crate::input_snapshot::FileSystemInputs.list(p)}
 }
 let root=Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../analyze/fixtures/native-reactive-reads");let reads=Arc::new(AtomicUsize::new(0));let inputs=RecordingInputs::new(Files(Arc::clone(&reads)),1);let db=Arc::new(QueryDb::default());let seed=reference_hierarchy::seed();let executor=dm_exec::BuildExecutor::new(1).unwrap();
 let front=dm_tree::frontend::build_with_executor_and_semantic_state_for_policy(&root.join("deepquarry.dme"),&inputs,&Default::default(),dm_tree::frontend::FrontendConfig{workers:1,engine:Some(&seed),observer:None},None,&executor,None,true).unwrap().with_body_queries(db.clone());
 let intent=PolicyInputRequest{workspace:None,files:vec![PolicyInputFile{path:root.join("scopes.toml"),role:PolicyInputRole::Configuration,required:false}],search_folders:vec![]}.admit().unwrap();let capture=Arc::new(crate::runner_host::policy_capture::capture(&front,&inputs,&intent.capture_files(),&[]).unwrap().bind_request(&intent).unwrap());
 for relative in ["code/probe.dm"]{assert!(capture.policy().file(&root.join(relative)).is_some(),"entire original fixture must be captured: {relative}");}
 let cohort=db.raw_cohort(capture,&root,&root.join("scopes.toml")).unwrap();assert_eq!(db.db.stats(crate::query_db::body_syntax::BODY_SYNTAX).computed,0);let before=reads.load(Ordering::Relaxed);
 for(name,context,closed)in [("leaf",None,true),("method_call",None,true),("global_wrapper",None,true),("global_wrapper",None,false),("contextual",Some("/datum/act/eval"),true),("virtual_probe",None,true)]{
 db.with_reactive_fixture(&cohort,Request::Read{receiver:"/datum/probe".into(),procedure:name.into(),context:context.map(str::to_owned),flavor:if closed{Flavor::Closed}else{Flavor::Targeted}},|value|{
  let Value::Reads(value)=value else{panic!("actual complete read result")};
  #[derive(serde::Serialize)]struct Row<'a>{procedure:&'a str,context:Option<&'a str>,closed:bool,facts:&'a dq_analyze::captured_reactive_reads::FrozenReadSet}
  let row=Row{procedure:name,context,closed,facts:value.facts()};
  struct Output{bytes:Vec<u8>,budget:Arc<Budget>,first:Option<io::Error>}
  impl io::Write for Output{
   fn write(&mut self,bytes:&[u8])->io::Result<usize>{
    if self.first.is_some(){return Err(io::Error::other("test admitted output stopped"))}
    let operation=(||{crate::daemon::control::checkpoint()?;let need=self.bytes.len().checked_add(bytes.len()).ok_or_else(||io::Error::new(io::ErrorKind::OutOfMemory,"test output size overflow"))?;
     if need>self.bytes.capacity(){let requested=need.max(self.bytes.capacity().saturating_mul(2)).max(256);let reservation=requested.checked_mul(4).and_then(|n|n.checked_add(64)).ok_or_else(||io::Error::new(io::ErrorKind::OutOfMemory,"test output capacity overflow"))?;self.budget.charge(reservation).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;self.bytes.try_reserve_exact(requested-self.bytes.len()).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;if self.bytes.capacity().checked_mul(1).is_none_or(|n|n>reservation){return Err(io::Error::new(io::ErrorKind::OutOfMemory,"test output exposed capacity exceeds reservation"))}}
     self.bytes.extend_from_slice(bytes);Ok(bytes.len())})();
    match operation{Ok(n)=>Ok(n),Err(actual)=>{self.first=Some(actual);Err(io::Error::other("test admitted output stopped"))}}
   }
   fn flush(&mut self)->io::Result<()>{Ok(())}
  }
  let available=RESULT_BUDGET.checked_sub(db.raw_policy.charge.load(Ordering::Acquire)).ok_or_else(||io::Error::new(io::ErrorKind::OutOfMemory,"global comparison output headroom"))?;let budget=Budget::new(available).map_err(io::Error::other)?;
  let mut output=Output{bytes:Vec::new(),budget,first:None};let serialized=serde::Serialize::serialize(&row,&mut serde_json::Serializer::new(&mut output));if let Some(actual)=output.first.take(){return Err(actual)}serialized.map_err(io::Error::other)?;crate::daemon::control::checkpoint()?;
  let json=String::from_utf8(output.bytes).map_err(io::Error::other)?;println!("NATIVE_READ_FULL={json}");Ok(())
 }).unwrap();}assert_eq!(reads.load(Ordering::Relaxed),before,"native query/output must not reread fixture source");
}


#[test]
fn actual_native_only_globals_over_large_original_roster_uses_context_body_edges_without_raw_or_io(){
 const SOURCE:Kind=Kind(247);const GLOBALS:Kind=Kind(248);
 #[derive(Clone)]struct Files{rows:Arc<std::collections::BTreeMap<PathBuf,String>>,reads:Arc<AtomicUsize>}
 impl SnapshotProvider for Files{
  fn stamp(&self,p:&Path)->io::Result<Stamp>{self.reads.fetch_add(1,Ordering::Relaxed);let text=self.rows.get(&dm_preprocess::regions::canonical_path(p)).ok_or(io::ErrorKind::NotFound)?;Ok(Stamp{size:text.len() as u64,modified_ns:1,file_id:Some(1)})}
  fn read(&self,p:&Path)->io::Result<(Stamp,Vec<u8>)>{self.reads.fetch_add(1,Ordering::Relaxed);let stamp=self.stamp(p)?;Ok((stamp,self.rows[&dm_preprocess::regions::canonical_path(p)].as_bytes().to_vec()))}
  fn list(&self,p:&Path)->io::Result<FolderListing>{self.reads.fetch_add(1,Ordering::Relaxed);let p=dm_preprocess::regions::canonical_path(p);let mut names=std::collections::BTreeSet::new();for path in self.rows.keys(){if let Ok(rest)=path.strip_prefix(&p){if let Some(component)=rest.components().next(){names.insert(component.as_os_str().to_string_lossy().into_owned());}}}Ok(if names.is_empty(){FolderListing::Missing}else{FolderListing::Present(names.into_iter().collect())})}
 }
 let root=std::env::current_dir().unwrap().join("native-only-globals-large-roster");let mut rows=std::collections::BTreeMap::new();let mut manifest=String::new();
 const CODE:&str="var/global/boot_only_control=0\nvar/global/runtime_only_control=0\n/world/New()\n    initialize_boot_control()\n/proc/initialize_boot_control()\n    boot_only_control=1\n/proc/runtime_control()\n    runtime_only_control=1\n";
 for i in 0..129{let relative=format!("code/p_{i:03}.dm");manifest.push_str(&format!("#include \"{relative}\"\n"));rows.insert(dm_preprocess::regions::canonical_path(&root.join(relative)),if i==0{CODE.to_owned()}else{"// genuine acquired unused include\n".into()});}
 rows.insert(dm_preprocess::regions::canonical_path(&root.join("deepquarry.dme")),manifest);let reads=Arc::new(AtomicUsize::new(0));let inputs=RecordingInputs::new(Files{rows:Arc::new(rows),reads:Arc::clone(&reads)},1);let db=Arc::new(QueryDb::default());let seed=reference_hierarchy::seed();let executor=dm_exec::BuildExecutor::new(1).unwrap();
 let front=dm_tree::frontend::build_with_executor_and_semantic_state_for_policy(&root.join("deepquarry.dme"),&inputs,&Default::default(),dm_tree::frontend::FrontendConfig{workers:1,engine:Some(&seed),observer:None},None,&executor,None,true).unwrap().with_body_queries(db.clone());
 let policy=Arc::new(dm_analysis::policy_inputs::PolicyInputs::capture(&front,std::iter::empty()).unwrap());assert!(policy.files().filter(|f|f.is_compiled()).count()>128);assert!(policy.files().all(|f|f.view(dm_analysis::policy_inputs::TextView::AnalyzeRaw).is_err()));assert_eq!(db.db.stats(crate::query_db::body_syntax::BODY_SYNTAX).computed,0);
 let source_key=Key::new(SOURCE,1);let result_key=Key::new(GLOBALS,1);db.db.define_input(SOURCE,"test-native-only-original-policy");let loans=Arc::new(AtomicUsize::new(0));let queried=Arc::clone(&loans);let native_root=root.clone();
 db.db.define(GLOBALS,"test-native-only-globals-original-context",move|ctx,_|{
  let captured=ctx.input::<(Arc<dm_analysis::policy_inputs::PolicyInputs>,usize)>(source_key)?;let budget=Budget::new(captured.1).map_err(|e|QueryError::operational(result_key,io::Error::new(io::ErrorKind::OutOfMemory,e)))?;let active=std::cell::RefCell::new(ctx);
  let body=|input:&Arc<dm_tree::frontend::BodySyntaxInput>|{queried.fetch_add(1,Ordering::Relaxed);crate::query_db::body_syntax::obtain(&mut active.borrow_mut(),input)};
  let value=dq_analyze::captured_reactive_reads::globals_native(&captured.0,&native_root,&budget,&crate::daemon::control::checkpoint,&body).map_err(|e|match e{Failure::Operational(actual)=>QueryError::operational(result_key,actual),Failure::Unsupported(message)=>QueryError::operational(result_key,io::Error::new(io::ErrorKind::Unsupported,message))})?;
  let charge=value.retained_charge().ok_or_else(||QueryError::operational(result_key,io::ErrorKind::OutOfMemory.into()))?;
  Ok(dm_query::Outcome::new(value,captured.0.revision().compiler_source,charge))
 });
 let fixed=std::mem::size_of::<Budget>()+2*std::mem::size_of::<usize>();db.db.set_input(source_key,(Arc::clone(&policy),fixed),fixed as u128);let before=reads.load(Ordering::Relaxed);
 let failed=db.db.get::<GlobalResult>(result_key,Arc::new(())).err().expect("actual cold quota refusal").into_operational().unwrap().into_io();assert_eq!(failed.kind(),io::ErrorKind::OutOfMemory);assert_eq!(loans.load(Ordering::Relaxed),0,"refuse before actual body demand");assert_eq!(db.db.stats(GLOBALS).computed,0);
 db.db.set_input(source_key,(Arc::clone(&policy),64*1024*1024usize),(64*1024*1024)as u128);let schedule=db.fail_body_syntax_after_for_test(1,io::Error::from_raw_os_error(1450));let failed=db.db.get::<GlobalResult>(result_key,Arc::new(())).err().expect("actual body IO").into_operational().unwrap().into_io();assert_eq!(failed.raw_os_error(),Some(1450));drop(schedule);
 let value=db.db.get::<GlobalResult>(result_key,Arc::new(())).unwrap();assert!(value.matches(&policy));assert_eq!(db.db.stats(crate::query_db::body_syntax::BODY_SYNTAX).computed,3,"only three real bodies in a129-file original source roster");
 let mut bytes=[0u8;4096];let mut output=io::Cursor::new(&mut bytes[..]);value.serialize_facts(&mut serde_json::Serializer::new(&mut output)).unwrap();let length=output.position() as usize;drop(output);let actual:serde_json::Value=serde_json::from_slice(&bytes[..length]).unwrap();
 let expected=serde_json::json!({"globals":{"runtime_written":["runtime_only_control"],"written":["boot_only_control","runtime_only_control"],"runtime_field_written":["runtime_only_control"],"boot_procs":2},"writes":{"written":["boot_only_control","runtime_only_control"],"typed":{"boot_only_control":["/"],"runtime_only_control":["/"]},"untyped":[]}});assert_eq!(actual,expected,"complete tiny original policy result, not selected booleans");
 let warm=db.db.get::<GlobalResult>(result_key,Arc::new(())).unwrap();assert!(Arc::ptr_eq(&value,&warm));assert_eq!(db.db.stats(GLOBALS).computed,1);assert_eq!(reads.load(Ordering::Relaxed),before,"native source/Globals/serialization do not reacquire original inputs");assert_eq!(db.db.stats(RAW_FILE).computed,0,"no raw-file policy node was manufactured");assert!(db.raw_policy.admission.leases.lock().unwrap().is_empty(),"producer test does not manufacture raw-family inputs or result leases");
 let actual_body=policy.archive().syntax_inputs().unwrap().first().unwrap();let body_key=Key::new(crate::query_db::body_syntax::BODY_SYNTAX,actual_body.key().into());assert!(db.db.dependants(&[body_key]).contains(&result_key),"actual original Kind4 dynamic edge under parent context");
}

//! Explicit missing-output generation over genuine native bootstrap originals.
//! Staging only: no filesystem writer, SourceSnapshot, compiled-source receipt,
//! sibling semantic model/cache or default request route is introduced here.
use super::*;
use crate::input_snapshot::{GenerationBootstrap,GenerationSourceReader,RecordingInputs,SnapshotProvider};
use crate::runner_host::workspace_discovery::DiscoveryReceipt;
use super::super::generator_policy::{Artifact,GeneratorName};
use dq_analyze::{captured_generator_budget::Budget,captured_reactive_reads::Failure,generator_test_scope::TestTypeCollector,key_policy_control::Control};
fn oom(budget:&Budget,message:impl Into<String>)->Failure{budget.deny();Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message.into()))}
struct Check<'a>{budget:&'a Budget}
impl Control for Check<'_>{type Error=Failure;const CHECKED:bool=true;fn checkpoint(&mut self)->Result<(),Failure>{self.budget.require().map_err(|message|oom(self.budget,message))?;crate::daemon::control::checkpoint()?;self.budget.require().map_err(|message|oom(self.budget,message))}fn reserve(&mut self,bytes:usize)->Result<(),Failure>{self.budget.charge(bytes).map_err(|message|oom(self.budget,message))}fn overflow(&mut self)->Failure{oom(self.budget,"generation policy allocation overflow")}fn allocation_failed(&mut self)->Failure{oom(self.budget,"generation policy allocation refused")}}
fn source_only(name:GeneratorName)->bool{matches!(name,GeneratorName::SparseSlots|GeneratorName::DeclareIds|GeneratorName::Declare|GeneratorName::UiTypes|GeneratorName::Stats|GeneratorName::Actions|GeneratorName::SystemAccessors)}
fn named(name:GeneratorName,mut output:dq_analyze::sparse_slots_policy::Output,budget:&Arc<Budget>)->Result<Artifact,Failure>{
 let filename=match name{GeneratorName::SparseSlots=>"sparse_slots.dm",GeneratorName::DeclareIds=>"ids.dm",GeneratorName::Declare=>"declare.dm",GeneratorName::Stats=>"stats.dm",GeneratorName::Actions=>"actions.dm",_=>return Err("generation named source-only role differs".into())};
 let text=output.captured_named_file_text(name.name(),filename,budget).map_err(|message|oom(budget,message))?;
 budget.charge(std::mem::size_of::<Artifact>()).map_err(|message|oom(budget,message))?;
 Ok(Artifact{name,text,files:Vec::new(),diags:std::mem::take(&mut output.diags)})
}
impl QueryDb{
 /// Borrow outputs only while their actual generation/source scope is live.
 /// consume stages/funds owned bytes; it must not install files or cache Budget.
 /// Commit occurs only AFTER this call ends and all original loans are dropped.
 pub(crate) fn with_generation_source_generators<P:SnapshotProvider>(
  &self,frame:&GenerationBootstrap,inputs:&RecordingInputs<P>,discovery:&Arc<DiscoveryReceipt>,
  intent:&crate::policy_request::AdmittedPolicyRequest,names:&[GeneratorName],
  mut consume:impl FnMut(&Artifact,&Arc<Budget>,&std::collections::BTreeSet<String>)->io::Result<()>,
 )->io::Result<()>{self.with_generation_source_generators_limit(frame,inputs,discovery,intent,names,None,&mut consume)}
 fn with_generation_source_generators_limit<P:SnapshotProvider>(
  &self,frame:&GenerationBootstrap,inputs:&RecordingInputs<P>,discovery:&Arc<DiscoveryReceipt>,intent:&crate::policy_request::AdmittedPolicyRequest,names:&[GeneratorName],limit:Option<usize>,
  consume:&mut dyn FnMut(&Artifact,&Arc<Budget>,&std::collections::BTreeSet<String>)->io::Result<()>,
 )->io::Result<()>{
  if names.is_empty()||names.len()>13||names.iter().any(|name|!source_only(*name)||!intent.workspace_generators().contains(name)){return Err(io::Error::new(io::ErrorKind::Unsupported,"generation requires requested source-only output roles"))}
  for(index,name)in names.iter().enumerate(){if names[..index].contains(name){return Err(io::Error::new(io::ErrorKind::InvalidInput,"generation output role repeats"))}}
  let request=intent.workspace().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"generation needs actual admitted workspace intent"))?;
  if request.root!=discovery.contract().root||request.recursive_roots!=discovery.contract().recursive_roots{return Err(io::Error::new(io::ErrorKind::InvalidData,"generation discovery differs from admitted workspace request"))}
  crate::daemon::control::checkpoint()?;frame.require_recording(inputs)?;discovery.validate_recording(inputs)?;
  let _gate=self.raw_policy.gate.lock().unwrap_or_else(|error|error.into_inner());self.raw_prune_locked(std::time::Instant::now());self.begin_result_admission_locked()?;
  let inventory=self.workspace_resource_inventory_locked()?;
  let fixed=inventory.coordination_charge(0)?.checked_add(8192).ok_or_else(||io::Error::new(io::ErrorKind::OutOfMemory,"generation coordination overflow"))?;
  let available=self.workspace_input_headroom_locked(fixed)?.min(RESULT_BOUND.checked_sub(self.raw_policy.charge.load(Ordering::Relaxed)).and_then(|n|n.checked_sub(inventory.bytes())).and_then(|n|n.checked_sub(aggregate::REPORT_RESERVE)).ok_or_else(||io::Error::new(io::ErrorKind::OutOfMemory,"generation result-family headroom exhausted"))?).min(limit.unwrap_or(usize::MAX));
  let budget=Budget::new(available).map_err(|message|io::Error::new(io::ErrorKind::OutOfMemory,message))?;
  let run=(||{
   // Exactly ONE original-source reader owns all acquired bytes for this phase.
   // Every selected generator below reuses it; do not invoke this API per name.
   let reader=GenerationSourceReader::capture(frame,inputs,discovery,&budget)?;
   let manifest=frame.declarations().root_source().ok_or("generation root source absent")?;
   let lease=frame.declarations().original_sources().find_map(|(path,lease)|(path==manifest).then_some(lease).flatten()).ok_or("generation manifest acquisition absent")?;
   let bom=match lease.encoding(){dm_preprocess::SourceEncoding::Utf8=>false,dm_preprocess::SourceEncoding::Utf8Bom=>true,_=>return Err(Failure::from("generation manifest requires original strict UTF8"))};
   budget.charge(lease.source_text().len().checked_mul(64).and_then(|n|n.checked_add(4096)).ok_or_else(||oom(&budget,"generation manifest metadata overflow"))?).map_err(|message|oom(&budget,message))?;
   let order=dq_analyze::raw_marker_policy::dme_include_order_view(lease.source_text().as_str(),bom);
   let mut collector=TestTypeCollector::default();let mut control=Check{budget:&budget};
   if !reader.for_each_tests(&mut|relative,views|{collector.observe(relative,views.raw()?,&mut control)?;Ok(true)})?{return Err("generation CLI test-source traversal stopped".into())}
   let tests=collector.finish();
   for name in names{reader.checkpoint()?;
    let artifact=match name{
     GeneratorName::SparseSlots|GeneratorName::DeclareIds=>{let role=if *name==GeneratorName::SparseSlots{dq_analyze::captured_declaration_pages::Generator::SparseSlots}else{dq_analyze::captured_declaration_pages::Generator::DeclareIds};named(*name,dq_analyze::captured_declaration_pages::generate_from_pages(role,&reader,&order,&budget,&||crate::daemon::control::checkpoint())?,&budget)?},
     GeneratorName::Declare=>named(*name,dq_analyze::captured_declare_pages::generate_from_pages(&reader,&order,&budget,&||crate::daemon::control::checkpoint())?,&budget)?,
     GeneratorName::Stats=>named(*name,dq_analyze::captured_stats_pages::generate_from_pages(&reader,&order,&budget,&||crate::daemon::control::checkpoint())?,&budget)?,
     GeneratorName::Actions=>named(*name,dq_analyze::captured_actions_pages::generate_from_pages(&reader,&order,&budget,&||crate::daemon::control::checkpoint())?,&budget)?,
     GeneratorName::SystemAccessors=>{let mut output=dq_analyze::captured_system_accessors_pages::generate_from_pages(&reader,&order,&budget,&||crate::daemon::control::checkpoint())?;let text=output.captured_file_text(&budget).map_err(|message|if budget.denied(){oom(&budget,message)}else{Failure::Unsupported(message)})?;let diags=std::mem::take(&mut output.diags);drop(output);budget.charge(std::mem::size_of::<Artifact>()).map_err(|message|oom(&budget,message))?;Artifact{name:*name,text,files:Vec::new(),diags}},
     GeneratorName::UiTypes=>{let generated=dq_analyze::captured_ui_pages::generate_from_pages(&reader,&order,&budget,&||crate::daemon::control::checkpoint())?;budget.charge(std::mem::size_of::<Artifact>()).map_err(|message|oom(&budget,message))?;Artifact{name:*name,text:String::new(),files:generated.files,diags:generated.diags}},
     _=>unreachable!("source-only roles validated before capture"),
    };
    reader.require_completed()?;consume(&artifact,&budget,&tests)?;reader.checkpoint()?;
   }
   reader.require_completed()?;Ok::<_,Failure>(())
  })();
  match run{Err(Failure::Operational(actual))=>Err(actual),other=>{
   frame.require_recording(inputs)?;crate::daemon::control::checkpoint()?;budget.require().map_err(|message|io::Error::new(io::ErrorKind::OutOfMemory,message))?;
   other.map_err(|failure|match failure{Failure::Operational(actual)=>actual,Failure::Unsupported(message)=>io::Error::new(io::ErrorKind::Unsupported,message)})
  }}
 }
}

#[cfg(test)]mod tests{
 use super::*;use crate::input_snapshot::{FileSystemInputs,GenerationBootstrapPreparation,GenerationBootstrapFailure,Stamp,FolderListing,CapturedInputRead,PolicyDirectoryListing,SourceAliasChallenge,SourceAliasProof};
 use crate::runner_host::workspace_discovery::{self,DiscoveryContract};
 use std::{collections::BTreeMap,path::{Path,PathBuf},sync::{Arc,Mutex,atomic::{AtomicBool,AtomicUsize}}};
 #[derive(Clone)]struct Physical{fail:Arc<AtomicBool>,raw:PathBuf,reads:Arc<Mutex<BTreeMap<PathBuf,usize>>>}
 impl Physical{fn record(&self,path:&Path){*self.reads.lock().unwrap().entry(path.to_owned()).or_default()+=1;}fn count(&self,path:&Path)->usize{self.reads.lock().unwrap().get(path).copied().unwrap_or(0)}}
 impl SnapshotProvider for Physical{
  fn stamp(&self,path:&Path)->io::Result<Stamp>{if self.fail.load(Ordering::Relaxed)&&path==self.raw{return Err(io::Error::from_raw_os_error(1450))}SnapshotProvider::stamp(&FileSystemInputs,path)}
  fn read(&self,path:&Path)->io::Result<(Stamp,Vec<u8>)>{self.record(path);SnapshotProvider::read(&FileSystemInputs,path)}
  fn read_verified(&self,path:&Path)->io::Result<CapturedInputRead>{self.record(path);SnapshotProvider::read_verified(&FileSystemInputs,path)}
  fn list(&self,path:&Path)->io::Result<FolderListing>{SnapshotProvider::list(&FileSystemInputs,path)}
  fn read_policy_bounded(&self,path:&Path,limit:usize)->io::Result<Option<CapturedInputRead>>{self.record(path);if self.fail.load(Ordering::Relaxed)&&path==self.raw{return Err(io::Error::from_raw_os_error(1450))}SnapshotProvider::read_policy_bounded(&FileSystemInputs,path,limit)}
  fn policy_directory(&self,path:&Path,follow:bool,limit:usize)->io::Result<Option<PolicyDirectoryListing>>{SnapshotProvider::policy_directory(&FileSystemInputs,path,follow,limit)}
  fn source_alias(&self,path:&Path,proof:&SourceAliasChallenge)->io::Result<Option<SourceAliasProof>>{SnapshotProvider::source_alias(&FileSystemInputs,path,proof)}
 }
 struct Fixture{root:PathBuf,project:PathBuf,backend:Physical,inputs:RecordingInputs<Physical>,frame:GenerationBootstrap,discovery:Arc<DiscoveryReceipt>,intent:crate::policy_request::AdmittedPolicyRequest,queries:Arc<QueryDb>}
 const ROLES:[GeneratorName;7]=[GeneratorName::SparseSlots,GeneratorName::SystemAccessors,GeneratorName::Stats,GeneratorName::Actions,GeneratorName::DeclareIds,GeneratorName::Declare,GeneratorName::UiTypes];
 fn prepare(inputs:&RecordingInputs<Physical>,project:&Path,queries:&Arc<QueryDb>)->GenerationBootstrap{
  let host=queries.clone()as Arc<dyn dm_tree::frontend::SettingExpressionQueries>;let executor=dm_exec::BuildExecutor::new(1).unwrap();
  match inputs.prepare_generation_bootstrap(project,&BTreeMap::new(),dm_tree::frontend::FrontendConfig{workers:1,engine:None,observer:None},&executor,&host,&mut |_|Ok(())).unwrap(){GenerationBootstrapPreparation::MissingOutputs(frame)=>frame,GenerationBootstrapPreparation::NotNeeded=>panic!("real registered files are absent")}
 }
 fn fixture()->Fixture{
  let root=crate::test_scratch::dir("generation-original-source-pages");std::fs::create_dir_all(root.join("code/engine")).unwrap();std::fs::create_dir_all(root.join("code/tests")).unwrap();
  let project=root.join("deepquarry.dme");let mut manifest=String::new();for relative in QueryDb::generation_dm_outputs(){manifest.push_str(&format!("#include \"{relative}\"\n"));}manifest.push_str("#include \"code/compiled.dm\"\n");std::fs::write(&project,manifest).unwrap();
  std::fs::write(root.join("code/compiled.dm"),"/datum/probe\n    var/value=7\n/proc/wall(a,b)\n    return null\n").unwrap();
  let raw=root.join("code/markers.dm");std::fs::write(&raw,"sparse(/datum/probe, stash, type = /datum)\nCAPABILITY_TYPE(probe, CAP_PROBE, /datum/probe)\nCAPABILITIES(/datum/probe)\n    wall(1, 2)\nSTAT(/datum/probe, charge, SUM)\nACTION(hit, num/power)\nSYSTEM_DEF(clock)\nSYSTEM_ACCESSOR(clock, get_value, nameof(value))\n/datum/system/clock\n    var/value\n").unwrap();std::fs::write(root.join("code/tests/only.dm"),"/datum/generation_test_only\n").unwrap();
  let backend=Physical{fail:Arc::new(AtomicBool::new(false)),raw,reads:Arc::new(Mutex::new(BTreeMap::new()))};let inputs=RecordingInputs::new(backend.clone(),0);let queries=Arc::new(QueryDb::default());let frame=prepare(&inputs,&project,&queries);
  let discovery=Arc::new(workspace_discovery::discover(&inputs,DiscoveryContract{root:root.clone(),recursive_roots:vec![root.join("code")]}).unwrap());
  let mut intent=crate::policy_request::PolicyInputRequest::default();intent.workspace=Some(crate::policy_request::WorkspacePolicyRequest{root:root.clone(),recursive_roots:vec![root.join("code")],configuration:root.join("missing.toml")});intent.workspace_generators=ROLES.to_vec();let intent=intent.admit().unwrap();Fixture{root,project,backend,inputs,frame,discovery,intent,queries}
 }
 #[test]fn real_missing_output_bootstrap_runs_all_seven_source_generators_from_original_loans_without_cold_or_body_role(){
  let f=fixture();
  let originals=f.frame.declarations().original_sources().collect::<Vec<_>>();assert_eq!(originals.len(),2,"only actual manifest and compiled DM are original source loans");assert!(originals.iter().all(|(_,lease)|lease.is_some()),"every actual source has its real acquisition");assert!(originals.iter().any(|(path,_)|*path==f.project));assert!(originals.iter().any(|(path,_)|*path==f.root.join("code/compiled.dm")));f.frame.require_recording(&f.inputs).unwrap();
  let compiled=f.root.join("code/compiled.dm");let compiled_reads=f.backend.count(&compiled);let raw_reads=f.backend.count(&f.backend.raw);let mut observed=Vec::new();
  f.queries.with_generation_source_generators(&f.frame,&f.inputs,&f.discovery,&f.intent,&ROLES,|artifact,_,tests|{
   observed.push(artifact.name);assert!(tests.contains("/datum/generation_test_only"));
   let expected=match artifact.name{GeneratorName::SparseSlots=>Some("list(/datum/probe, \"stash\", \"/datum\")"),GeneratorName::DeclareIds=>Some("#define CAP_PROBE 300"),GeneratorName::Declare=>Some("/datum/probe/declared_entries"),GeneratorName::Stats=>Some("__stat_charge"),GeneratorName::Actions=>Some("/datum/act/hit"),GeneratorName::SystemAccessors=>Some("return SSclock?.value"),GeneratorName::UiTypes=>None,_=>unreachable!()};
   if let Some(expected)=expected{assert!(artifact.text.contains(expected),"{} actual output lacks {expected}",artifact.name.name());assert!(artifact.files.is_empty())}else{assert!(artifact.text.is_empty());assert!(artifact.files.is_empty())}assert!(artifact.diags.is_empty());Ok(())
  }).unwrap();assert_eq!(observed,ROLES);assert_eq!(f.backend.count(&compiled),compiled_reads,"compiled original lease must be borrowed, never reread");assert_eq!(f.backend.count(&f.backend.raw),raw_reads+1,"one bounded original read despite multiple policy traversals");assert_eq!(f.queries.db.stats(crate::query_db::body_syntax::BODY_SYNTAX).computed,0);assert!(!f.root.join("code/engine/_generated/declare.dm").exists(),"staging consumer never installs files");
 }
 #[test]fn generation_source_roles_reject_foreign_recorder_subset_and_auto_before_delivery(){
  let f=fixture();let foreign=RecordingInputs::new(f.backend.clone(),0);let mut visits=0;
  assert!(f.queries.with_generation_source_generators(&f.frame,&foreign,&f.discovery,&f.intent,&[GeneratorName::Declare],|_,_,_|{visits+=1;Ok(())}).is_err());assert_eq!(visits,0);
  let subset_inputs=RecordingInputs::new(f.backend.clone(),0);let subset_frame=prepare(&subset_inputs,&f.project,&f.queries);let subset=Arc::new(workspace_discovery::discover(&subset_inputs,DiscoveryContract{root:f.root.clone(),recursive_roots:vec![f.root.join("code/tests")]}).unwrap());let mut subset_intent=crate::policy_request::PolicyInputRequest::default();subset_intent.workspace=Some(crate::policy_request::WorkspacePolicyRequest{root:f.root.clone(),recursive_roots:vec![f.root.join("code/tests")],configuration:f.root.join("missing.toml")});subset_intent.workspace_generators=vec![GeneratorName::Declare];let subset_intent=subset_intent.admit().unwrap();assert!(f.queries.with_generation_source_generators(&subset_frame,&subset_inputs,&subset,&subset_intent,&[GeneratorName::Declare],|_,_,_|{visits+=1;Ok(())}).is_err());assert_eq!(visits,0);
  let mut intent=crate::policy_request::PolicyInputRequest::default();intent.workspace=f.intent.workspace().cloned();intent.workspace_generators=vec![GeneratorName::AutoTracked];let intent=intent.admit().unwrap();let error=f.queries.with_generation_source_generators(&f.frame,&f.inputs,&f.discovery,&intent,&[GeneratorName::AutoTracked],|_,_,_|{visits+=1;Ok(())}).unwrap_err();assert_eq!(error.kind(),io::ErrorKind::Unsupported);assert_eq!(visits,0,"no invented body/read role for AutoTracked");
 }
 #[test]fn generation_source_actual_io_quota_cancel_and_staged_callback_failure_recover_on_same_frame(){
  let f=fixture();f.backend.fail.store(true,Ordering::Relaxed);let error=f.queries.with_generation_source_generators(&f.frame,&f.inputs,&f.discovery,&f.intent,&[GeneratorName::Declare],|_,_,_|panic!("no artifact on actual read IO")).unwrap_err();assert_eq!(error.raw_os_error(),Some(1450));f.backend.fail.store(false,Ordering::Relaxed);
  let error=f.queries.with_generation_source_generators_limit(&f.frame,&f.inputs,&f.discovery,&f.intent,&[GeneratorName::Declare],Some(64),&mut|_,_,_|panic!("no artifact on quota")).unwrap_err();assert_eq!(error.kind(),io::ErrorKind::OutOfMemory);
  let cancellation=crate::daemon::control::Cancellation::default();let binding=crate::daemon::control::bind_with_deadline(cancellation.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));cancellation.cancel();assert_eq!(f.queries.with_generation_source_generators(&f.frame,&f.inputs,&f.discovery,&f.intent,&[GeneratorName::Declare],|_,_,_|panic!("no cancelled artifact")).unwrap_err().kind(),io::ErrorKind::Interrupted);drop(binding);
  assert_eq!(f.queries.with_generation_source_generators(&f.frame,&f.inputs,&f.discovery,&f.intent,&[GeneratorName::Declare],|_,_,_|Err(io::Error::from_raw_os_error(112))).unwrap_err().raw_os_error(),Some(112));
  f.queries.with_generation_source_generators(&f.frame,&f.inputs,&f.discovery,&f.intent,&[GeneratorName::Declare],|artifact,_,_|{assert!(artifact.text.contains("/proc/probe("));Ok(())}).unwrap();
 }
 #[test]fn actual_output_write_retires_old_bootstrap_and_all_present_declines_before_any_second_parse(){
  let f=fixture();f.queries.with_generation_source_generators(&f.frame,&f.inputs,&f.discovery,&f.intent,&[GeneratorName::Declare],|_,_,_|Ok(())).unwrap();
  let output=f.root.join("code/engine/_generated/declare.dm");std::fs::create_dir_all(output.parent().unwrap()).unwrap();std::fs::write(&output,"/datum/real_generated_output\n    var/new_value=1\n").unwrap();let before=f.backend.count(&f.backend.raw);let error=f.queries.with_generation_source_generators(&f.frame,&f.inputs,&f.discovery,&f.intent,&[GeneratorName::Declare],|_,_,_|panic!("old negative cannot deliver")).unwrap_err();assert_eq!(error.kind(),io::ErrorKind::InvalidData);assert_eq!(f.backend.count(&f.backend.raw),before);
  let next=RecordingInputs::new(f.backend.clone(),0);let host=f.queries.clone()as Arc<dyn dm_tree::frontend::SettingExpressionQueries>;let executor=dm_exec::BuildExecutor::new(1).unwrap();let parses=AtomicUsize::new(0);let observe=|event:dm_tree::frontend::FrontendProgress|{if event.stage==dm_tree::frontend::FrontendStage::DeclarationParsing{parses.fetch_add(1,Ordering::Relaxed);}};let config=dm_tree::frontend::FrontendConfig{workers:1,engine:None,observer:Some(&observe)};
  let next_frame=match next.prepare_generation_bootstrap(&f.project,&BTreeMap::new(),config,&executor,&host,&mut |_|Ok(())).unwrap(){GenerationBootstrapPreparation::MissingOutputs(frame)=>frame,GenerationBootstrapPreparation::NotNeeded=>panic!("other registered outputs remain missing")};assert!(parses.load(Ordering::Relaxed)>0,"observer must measure the genuine native declaration parser");assert!(next_frame.declarations().declarations().count()>f.frame.declarations().declarations().count());assert!(!next_frame.declarations().omissions().any(|path|path==output));
  for relative in QueryDb::generation_dm_outputs(){let path=f.root.join(relative);if !path.exists(){std::fs::create_dir_all(path.parent().unwrap()).unwrap();std::fs::write(path,"// actual generated output exists\n").unwrap();}}
  let current=RecordingInputs::new(f.backend.clone(),0);let before_parses=parses.load(Ordering::Relaxed);
  let config=dm_tree::frontend::FrontendConfig{workers:1,engine:None,observer:Some(&observe)};assert!(matches!(current.prepare_generation_bootstrap(&f.project,&BTreeMap::new(),config,&executor,&host,&mut |_|Ok(())).unwrap(),GenerationBootstrapPreparation::NotNeeded));assert_eq!(parses.load(Ordering::Relaxed),before_parses,"normal retained full-frontend path must be selected before generation declaration parsing");
 }
}

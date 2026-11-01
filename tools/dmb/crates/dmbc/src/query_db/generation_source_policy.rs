//! Explicit missing-output generation over genuine native bootstrap originals.
//! Staging only: no filesystem writer, SourceSnapshot, compiled-source receipt,
//! sibling semantic model/cache or default request route is introduced here.
use super::*;
use crate::input_snapshot::{GenerationBootstrap,GenerationQuestionBootstrap,GenerationSourceFrame,GenerationSourceReader,RecordingInputs,SnapshotProvider};
use crate::runner_host::workspace_discovery::DiscoveryReceipt;
use super::super::generator_policy::{Artifact,GeneratorName};
use dq_analyze::{captured_generator_budget::Budget,captured_reactive_reads::Failure,generator_test_scope::TestTypeCollector,key_policy_control::Control};
fn oom(budget:&Budget,message:impl Into<String>)->Failure{budget.deny();Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message.into()))}
struct Check<'a>{budget:&'a Budget}
impl Control for Check<'_>{type Error=Failure;const CHECKED:bool=true;fn checkpoint(&mut self)->Result<(),Failure>{self.budget.require().map_err(|message|oom(self.budget,message))?;crate::daemon::control::checkpoint()?;self.budget.require().map_err(|message|oom(self.budget,message))}fn reserve(&mut self,bytes:usize)->Result<(),Failure>{self.budget.charge(bytes).map_err(|message|oom(self.budget,message))}fn overflow(&mut self)->Failure{oom(self.budget,"generation policy allocation overflow")}fn allocation_failed(&mut self)->Failure{oom(self.budget,"generation policy allocation refused")}}
fn source_only(name:GeneratorName)->bool{matches!(name,GeneratorName::SparseSlots|GeneratorName::DeclareIds|GeneratorName::Declare|GeneratorName::UiTypes|GeneratorName::Stats|GeneratorName::Actions|GeneratorName::SystemAccessors)}
fn named(name:GeneratorName,mut output:dq_analyze::sparse_slots_policy::Output,budget:&Arc<Budget>)->Result<Artifact,Failure>{
 let filename=match name{GeneratorName::SparseSlots=>"sparse_slots.dm",GeneratorName::DeclareIds=>"ids.dm",GeneratorName::Declare=>"declare.dm",GeneratorName::Stats=>"stats.dm",GeneratorName::Actions=>"actions.dm",GeneratorName::AutoTracked=>"auto_tracked.dm",GeneratorName::Deps=>"deps.dm",GeneratorName::Reads=>"reads.dm",GeneratorName::Plans=>"plans.dm",_=>return Err("generation named source-only role differs".into())};
 let text=output.captured_named_file_text(name.name(),filename,budget).map_err(|message|oom(budget,message))?;
 budget.charge(std::mem::size_of::<Artifact>()).map_err(|message|oom(budget,message))?;
 Ok(Artifact{name,text,files:Vec::new(),diags:std::mem::take(&mut output.diags)})
}
fn source_artifact<P:SnapshotProvider>(name:GeneratorName,reader:&GenerationSourceReader<'_,P>,budget:&Arc<Budget>,order:&std::collections::HashMap<String,usize>)->Result<Artifact,Failure>{
 let _order=order;let name=&name;Ok(match name{
     GeneratorName::SparseSlots|GeneratorName::DeclareIds=>{let role=if *name==GeneratorName::SparseSlots{dq_analyze::captured_declaration_pages::Generator::SparseSlots}else{dq_analyze::captured_declaration_pages::Generator::DeclareIds};named(*name,dq_analyze::captured_declaration_pages::generate_from_pages(role,reader,_order,budget,&||crate::daemon::control::checkpoint())?,budget)?},
     GeneratorName::Declare=>named(*name,dq_analyze::captured_declare_pages::generate_from_pages(reader,_order,budget,&||crate::daemon::control::checkpoint())?,budget)?,
     GeneratorName::Stats=>named(*name,dq_analyze::captured_stats_pages::generate_from_pages(reader,_order,budget,&||crate::daemon::control::checkpoint())?,budget)?,
     GeneratorName::Actions=>named(*name,dq_analyze::captured_actions_pages::generate_from_pages(reader,_order,budget,&||crate::daemon::control::checkpoint())?,budget)?,
     GeneratorName::SystemAccessors=>{let mut output=dq_analyze::captured_system_accessors_pages::generate_from_pages(reader,_order,budget,&||crate::daemon::control::checkpoint())?;let text=output.captured_file_text(budget).map_err(|message|if budget.denied(){oom(budget,message)}else{Failure::Unsupported(message)})?;let diags=std::mem::take(&mut output.diags);drop(output);budget.charge(std::mem::size_of::<Artifact>()).map_err(|message|oom(budget,message))?;Artifact{name:*name,text,files:Vec::new(),diags}},
     GeneratorName::UiTypes=>{let generated=dq_analyze::captured_ui_pages::generate_from_pages(reader,_order,budget,&||crate::daemon::control::checkpoint())?;budget.charge(std::mem::size_of::<Artifact>()).map_err(|message|oom(budget,message))?;Artifact{name:*name,text:String::new(),files:generated.files,diags:generated.diags}},
     _=>unreachable!("source-only roles validated before capture"),
    })
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
  self.with_generation_phase(GenerationSourceFrame::Declarations(frame),inputs,discovery,intent,names,limit,|reader,budget,_order,tests|{
   for name in names{reader.checkpoint()?;
    let artifact=source_artifact(*name,reader,budget,_order)?;
    reader.require_completed()?;consume(&artifact,budget,tests)?;reader.checkpoint()?;
   }
   Ok(())
  })
 }

 fn with_generation_phase<P:SnapshotProvider>(
  &self,frame:GenerationSourceFrame<'_>,inputs:&RecordingInputs<P>,discovery:&Arc<DiscoveryReceipt>,intent:&crate::policy_request::AdmittedPolicyRequest,names:&[GeneratorName],limit:Option<usize>,
  operation:impl for<'phase>FnOnce(&GenerationSourceReader<'phase,P>,&Arc<Budget>,&std::collections::HashMap<String,usize>,&std::collections::BTreeSet<String>)->Result<(),Failure>,
 )->io::Result<()>{
  if names.is_empty()||names.len()>13||names.iter().any(|name|!(if frame.questions().is_some(){true}else{source_only(*name)})||!intent.workspace_generators().contains(name)){return Err(io::Error::new(io::ErrorKind::Unsupported,"generation requires requested supported phase output roles"))}
  for(index,name)in names.iter().enumerate(){if names[..index].contains(name){return Err(io::Error::new(io::ErrorKind::InvalidInput,"generation output role repeats"))}}
  let request=intent.workspace().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"generation needs actual admitted workspace intent"))?;
  if request.root!=discovery.contract().root||request.recursive_roots!=discovery.contract().recursive_roots{return Err(io::Error::new(io::ErrorKind::InvalidData,"generation discovery differs from admitted workspace request"))}
  crate::daemon::control::checkpoint()?;frame.require_recording(inputs)?;discovery.validate_recording(inputs)?;
  if names.iter().any(|name|matches!(name,GeneratorName::AutoTracked|GeneratorName::Deps|GeneratorName::Reads|GeneratorName::Plans)){let questions=frame.questions().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"Auto requires its actual native question frame"))?;questions.prepare_original_member_groups().map_err(|failure|match failure{dm_tree::frontend::BodySyntaxFailure::Operational(actual)=>actual,dm_tree::frontend::BodySyntaxFailure::Syntax(error)=>io::Error::new(io::ErrorKind::InvalidInput,error.message)})?;}
  let _gate=self.raw_policy.gate.lock().unwrap_or_else(|error|error.into_inner());self.raw_prune_locked(std::time::Instant::now());self.begin_result_admission_locked()?;
  let inventory=self.workspace_resource_inventory_locked()?;
  // These NEW retained generation spans are already charged to the native
  // declaration counter. They still overlap this distinct phase envelope:
  // subtract their live reservation before minting ONE operation Budget.
  let generation_metadata=if let Some(questions)=frame.questions(){
   let mut actual=Some(0usize);questions.visit_generation_metadata(|_,bytes|{actual=actual.and_then(|n|n.checked_add(bytes))});
   let actual=actual.ok_or_else(||io::Error::new(io::ErrorKind::OutOfMemory,"generation metadata census overflow"))?;
   let reserved=questions.generation_retained_question_charge().ok_or_else(||io::Error::new(io::ErrorKind::OutOfMemory,"generation retained question charge overflow"))?;if actual>reserved{return Err(io::Error::new(io::ErrorKind::OutOfMemory,"generation metadata exceeds native reservation"))}reserved
  }else{0};
  let fixed=inventory.coordination_charge(0)?.checked_add(8192).and_then(|n|n.checked_add(generation_metadata)).ok_or_else(||io::Error::new(io::ErrorKind::OutOfMemory,"generation coordination overflow"))?;
  let available=self.workspace_input_headroom_locked(fixed)?.min(RESULT_BOUND.checked_sub(self.raw_policy.charge.load(Ordering::Relaxed)).and_then(|n|n.checked_sub(inventory.bytes())).and_then(|n|n.checked_sub(aggregate::REPORT_RESERVE)).and_then(|n|n.checked_sub(generation_metadata)).ok_or_else(||io::Error::new(io::ErrorKind::OutOfMemory,"generation result-family headroom exhausted"))?).min(limit.unwrap_or(usize::MAX));
  let budget=Budget::new(available).map_err(|message|io::Error::new(io::ErrorKind::OutOfMemory,message))?;
  let run=(||{
   // Exactly ONE original-source reader owns all acquired bytes for this phase.
   // Every selected generator below reuses it; do not invoke this API per name.
   let reader=GenerationSourceReader::capture_frame(frame,inputs,discovery,&budget)?;
   let manifest=frame.root_source().ok_or("generation root source absent")?;
   let lease=frame.originals().find_map(|(path,lease)|(path==manifest).then_some(lease).flatten()).ok_or("generation manifest acquisition absent")?;
   let bom=match lease.encoding(){dm_preprocess::SourceEncoding::Utf8=>false,dm_preprocess::SourceEncoding::Utf8Bom=>true,_=>return Err(Failure::from("generation manifest requires original strict UTF8"))};
   budget.charge(lease.source_text().len().checked_mul(64).and_then(|n|n.checked_add(4096)).ok_or_else(||oom(&budget,"generation manifest metadata overflow"))?).map_err(|message|oom(&budget,message))?;
   let order=dq_analyze::raw_marker_policy::dme_include_order_view(lease.source_text().as_str(),bom);
   let mut collector=TestTypeCollector::default();let mut control=Check{budget:&budget};
   if !reader.for_each_tests(&mut|relative,views|{collector.observe(relative,views.raw()?,&mut control)?;Ok(true)})?{return Err("generation CLI test-source traversal stopped".into())}
   let tests=collector.finish();
   operation(&reader,&budget,&order,&tests)?;
   reader.require_completed()?;Ok::<_,Failure>(())
  })();
  match run{Err(Failure::Operational(actual))=>Err(actual),other=>{
   frame.require_recording(inputs)?;crate::daemon::control::checkpoint()?;budget.require().map_err(|message|io::Error::new(io::ErrorKind::OutOfMemory,message))?;
   other.map_err(|failure|match failure{Failure::Operational(actual)=>actual,Failure::Unsupported(message)=>io::Error::new(io::ErrorKind::Unsupported,message)})
  }}
 }

 /// Purpose-specific generation questions. No compiled source snapshot or
 /// ordinary FullArtifact is minted; outputs are borrowed only for staging.
 pub(crate) fn with_generation_question_generators<P:SnapshotProvider>(
  &self,frame:&GenerationQuestionBootstrap,inputs:&RecordingInputs<P>,discovery:&Arc<DiscoveryReceipt>,intent:&crate::policy_request::AdmittedPolicyRequest,names:&[GeneratorName],
  mut consume:impl FnMut(&Artifact,&Arc<Budget>,&std::collections::BTreeSet<String>)->io::Result<()>,
 )->io::Result<()>{self.with_generation_question_generators_limit(frame,inputs,discovery,intent,names,None,&mut consume)}
 fn with_generation_question_generators_limit<P:SnapshotProvider>(
  &self,frame:&GenerationQuestionBootstrap,inputs:&RecordingInputs<P>,discovery:&Arc<DiscoveryReceipt>,intent:&crate::policy_request::AdmittedPolicyRequest,names:&[GeneratorName],limit:Option<usize>,consume:&mut dyn FnMut(&Artifact,&Arc<Budget>,&std::collections::BTreeSet<String>)->io::Result<()>,
 )->io::Result<()>{
  use dq_analyze::captured_generation_questions::{self as purpose,Generator as Role,Generated};
  fn role(name:GeneratorName)->Option<Role>{Some(match name{GeneratorName::Deps=>Role::Deps,GeneratorName::AutoTracked=>Role::AutoTracked,GeneratorName::Reads=>Role::Reads,GeneratorName::DerivedReads=>Role::DerivedReads,GeneratorName::Plans=>Role::Plans,_=>return None})}
  frame.with_questions(inputs,|questions|{
   if !questions.body_host_is(self){return Err(io::Error::new(io::ErrorKind::InvalidInput,"generation question host belongs to another actual QueryDb"))}
   // Only actual skipped stage-zero DM includes block semantic questions.
   // Missing registry outputs never encountered by this plan are irrelevant.
   if names.iter().any(|name|!source_only(*name))&&questions.encountered_omissions().any(|path|[GeneratorName::SparseSlots,GeneratorName::SystemAccessors,GeneratorName::Stats,GeneratorName::Actions,GeneratorName::DeclareIds,GeneratorName::Declare].iter().any(|name|discovery.contract().root.join(name.path())==path)){
    return Err(io::Error::new(io::ErrorKind::Unsupported,"generation questions require reissue after encountered stage-zero outputs are installed"))
   }
   self.with_generation_phase(GenerationSourceFrame::Questions(frame),inputs,discovery,intent,names,limit,|reader,budget,order,tests|{
    let mut selected=[Role::Deps;5];let mut count=0;for name in names{if let Some(value)=role(*name){selected[count]=value;count+=1;}}
    let mut cursor=0usize;
    fn emit_other<P:SnapshotProvider>(name:GeneratorName,questions:&dm_tree::frontend::GenerationNativeQuestions,reader:&GenerationSourceReader<'_,P>,budget:&Arc<Budget>,order:&std::collections::HashMap<String,usize>,tests:&std::collections::BTreeSet<String>,consume:&mut dyn FnMut(&Artifact,&Arc<Budget>,&std::collections::BTreeSet<String>)->io::Result<()>)->Result<(),Failure>{
     reader.checkpoint()?;let artifact=if source_only(name){source_artifact(name,reader,budget,order)?}else if name==GeneratorName::TrackedLists{
      let mut output=dq_analyze::captured_tracked_lists_pages::generate_from_generation(questions,reader.root(),reader,tests,budget,&||crate::daemon::control::checkpoint())?;
      let text=output.captured_named_file_text("tracked_lists","tracked_lists.dm",budget).map_err(|m|oom(budget,m))?;let diags=std::mem::take(&mut output.diags);drop(output);budget.charge(std::mem::size_of::<Artifact>()).map_err(|m|oom(budget,m))?;Artifact{name,text,files:Vec::new(),diags}
     }else{return Err("generation non-question role differs".into())};
     reader.require_completed()?;consume(&artifact,budget,tests)?;reader.checkpoint()
    }
    let mut run=|configuration:Option<&dq_analyze::captured_raw_file::Config>|->Result<(),Failure>{
     if count>0{purpose::with_generators(questions,reader.root(),reader,order,configuration,tests,&selected[..count],budget,&||crate::daemon::control::checkpoint(),&mut|value,generated|{
      while cursor<names.len()&&role(names[cursor]).is_none(){emit_other(names[cursor],questions,reader,budget,order,tests,consume)?;cursor+=1;}
      let name=*names.get(cursor).ok_or("generation question callback exceeds requested phase")?;if role(name)!=Some(value){return Err("generation question callback order differs".into())}cursor+=1;
      let artifact=match generated{Generated::Single(output)=>named(name,output,budget)?,Generated::Derived(text)=>{
       if name!=GeneratorName::DerivedReads{return Err("generation multifile role differs".into())}
       let path="code/_generated/reads.dm";budget.charge(std::mem::size_of::<Artifact>()+4*std::mem::size_of::<(String,String)>()+path.len()).map_err(|m|oom(budget,m))?;
       let mut files=Vec::new();files.try_reserve_exact(1).map_err(|_|oom(budget,"generation derived file allocation refused"))?;if files.capacity()>4{return Err(oom(budget,"generation derived file capacity exceeded reservation"))}files.push((path.to_owned(),text));Artifact{name,text:String::new(),files,diags:Vec::new()}
      }};
      reader.require_completed()?;consume(&artifact,budget,tests)?;reader.checkpoint()
     })?;}
     while cursor<names.len(){emit_other(names[cursor],questions,reader,budget,order,tests,consume)?;cursor+=1;}Ok(())
    };
    if names.contains(&GeneratorName::AutoTracked){let configuration=&intent.workspace().ok_or("generation Auto workspace configuration intent absent")?.configuration;reader.with_auto_configuration(configuration,|config|run(Some(config)))?;}else{run(None)?;}
    Ok(())
   })?;Ok(Ok::<_,()>(()))
  })?.map_err(|_|io::Error::other("generation question phase declined"))
 }

}

#[cfg(test)]
#[path="../../../dm-analysis/examples/support/reference_hierarchy.rs"]mod generation_reference_hierarchy;

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
  let project=root.join("deepquarry.dme");let mut manifest=String::new();for relative in QueryDb::generation_dm_outputs(){manifest.push_str(&format!("#include \"{relative}\"\n"));}manifest.push_str("#include \"code/compiled.dm\"\n#include \"fixture_map.dmm\"\n#include \"fixture_skin.dmf\"\n");std::fs::write(&project,manifest).unwrap();
  std::fs::write(root.join("code/compiled.dm"),"/datum/probe\n    var/value=7\n/proc/wall(a,b)\n    return null\n").unwrap();
  std::fs::write(root.join("fixture_map.dmm"),"\"a\" = (/turf)\n(1,1,1) = {\"\na\n\"}\n").unwrap();std::fs::write(root.join("fixture_skin.dmf"),"window \"probe\"\n").unwrap();
  let raw=root.join("code/markers.dm");std::fs::write(&raw,"sparse(/datum/probe, stash, type = /datum)\nCAPABILITY_TYPE(probe, CAP_PROBE, /datum/probe)\nCAPABILITIES(/datum/probe)\n    wall(1, 2)\nSTAT(/datum/probe, charge, SUM)\nACTION(hit, num/power)\nSYSTEM_DEF(clock)\nSYSTEM_ACCESSOR(clock, get_value, nameof(value))\n/datum/system/clock\n    var/value\n").unwrap();std::fs::write(root.join("code/tests/only.dm"),"/datum/generation_test_only\n").unwrap();
  let backend=Physical{fail:Arc::new(AtomicBool::new(false)),raw,reads:Arc::new(Mutex::new(BTreeMap::new()))};let inputs=RecordingInputs::new(backend.clone(),0);let queries=Arc::new(QueryDb::default());let frame=prepare(&inputs,&project,&queries);
  let discovery=Arc::new(workspace_discovery::discover(&inputs,DiscoveryContract{root:root.clone(),recursive_roots:vec![root.join("code")]}).unwrap());
  let mut intent=crate::policy_request::PolicyInputRequest::default();intent.workspace=Some(crate::policy_request::WorkspacePolicyRequest{root:root.clone(),recursive_roots:vec![root.join("code")],configuration:root.join("missing.toml")});intent.workspace_generators=ROLES.to_vec();let intent=intent.admit().unwrap();Fixture{root,project,backend,inputs,frame,discovery,intent,queries}
 }
 #[test]fn real_missing_output_bootstrap_runs_all_seven_source_generators_from_original_loans_without_cold_or_body_role(){
  let f=fixture();
  let originals=f.frame.declarations().original_sources().collect::<Vec<_>>();assert_eq!(originals.len(),2,"only actual manifest and compiled DM are original source loans");assert!(originals.iter().all(|(_,lease)|lease.is_some()),"every actual source has its real acquisition");assert!(originals.iter().any(|(path,_)|*path==f.project));assert!(originals.iter().any(|(path,_)|*path==f.root.join("code/compiled.dm")));f.frame.require_recording(&f.inputs).unwrap();assert_eq!(f.backend.count(&f.root.join("fixture_map.dmm")),0,"typed map dependency is not a code-source acquisition");assert_eq!(f.backend.count(&f.root.join("fixture_skin.dmf")),0,"typed skin dependency is not a code-source acquisition");
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
 // Same original hierarchy fixture used by the independent whole legacy oracle;
 // hierarchy only, never a production default or an invented complete engine.
 fn tracked_fixture()->(PathBuf,Physical,RecordingInputs<Physical>,GenerationBootstrap,Arc<DiscoveryReceipt>,crate::policy_request::AdmittedPolicyRequest,Arc<QueryDb>){
  let root=crate::test_scratch::dir("generation-tracked-purpose");std::fs::create_dir_all(root.join("code/tests")).unwrap();std::fs::create_dir_all(root.join("code/sub")).unwrap();
  for(relative,text)in [
   ("deepquarry.dme",include_str!("../../../../../analyze/fixtures/generation_tracked_bootstrap/deepquarry.dme")),
   ("code/probe.dm",include_str!("../../../../../analyze/fixtures/generation_tracked_bootstrap/code/probe.dm")),
   ("code/tests/tracked.dm",include_str!("../../../../../analyze/fixtures/generation_tracked_bootstrap/code/tests/tracked.dm")),
   ("code/extra.dm",include_str!("../../../../../analyze/fixtures/generation_tracked_bootstrap/code/extra.dm")),
  ]{std::fs::write(root.join(relative),text).unwrap();}
  let backend=Physical{fail:Arc::new(AtomicBool::new(false)),raw:root.join("code/extra.dm"),reads:Arc::new(Mutex::new(BTreeMap::new()))};let inputs=RecordingInputs::new(backend.clone(),0);let queries=Arc::new(QueryDb::default());let frame=prepare(&inputs,&root.join("deepquarry.dme"),&queries);
  let discovery=Arc::new(workspace_discovery::discover(&inputs,DiscoveryContract{root:root.clone(),recursive_roots:vec![root.join("code")]}).unwrap());let mut intent=crate::policy_request::PolicyInputRequest::default();intent.workspace=Some(crate::policy_request::WorkspacePolicyRequest{root:root.clone(),recursive_roots:vec![root.join("code")],configuration:root.join("missing.toml")});intent.workspace_generators=ROLES.into_iter().chain([GeneratorName::TrackedLists]).collect();let intent=intent.admit().unwrap();(root,backend,inputs,frame,discovery,intent,queries)
 }
 fn question_after_source_seven()->(PathBuf,Physical,RecordingInputs<Physical>,GenerationQuestionBootstrap,Arc<DiscoveryReceipt>,crate::policy_request::AdmittedPolicyRequest,Arc<QueryDb>){
  use std::io::Write;
  let(root,backend,inputs,frame,discovery,intent,queries)=tracked_fixture();
  assert!(QueryDb::generation_dm_outputs().all(|relative|!root.join(relative).exists()));
  let scratch=crate::test_scratch::dir("generation-purpose-journal");let mut staged=crate::generation_journal::StagedJournal::new(crate::generation_staging::temporary_output(&scratch).unwrap()).unwrap();let mut ordinal=0;
  queries.with_generation_source_generators(&frame,&inputs,&discovery,&intent,&ROLES,|artifact,budget,_|{let bound=artifact.charge().checked_mul(8).and_then(|n|n.checked_add(8192)).unwrap();budget.charge(bound).map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))?;let observed=serde_json::to_string(&artifact.output_wire()).unwrap();assert!(observed.capacity()<=bound);println!("NATIVE_GENERATION_SOURCE_FILE={observed}");staged.append_generator(ordinal,artifact.name.name())?;ordinal+=1;assert!(artifact.diags.is_empty());if artifact.name==GeneratorName::UiTypes{for(path,text)in&artifact.files{QueryDb::validate_generation_output(&root,artifact.name,path).map_err(|m|io::Error::new(io::ErrorKind::InvalidData,m))?;staged.append_file(path,text)?;}}else{let(path,text)=artifact.single()?;QueryDb::validate_generation_output(&root,artifact.name,path).map_err(|m|io::Error::new(io::ErrorKind::InvalidData,m))?;staged.append_file(path,text)?;}Ok(())}).unwrap();
  let mut staged=staged.seal().unwrap();drop(frame);drop(discovery);let closure=inputs.into_snapshot().unwrap();assert!(closure.restat(&backend).unwrap().unchanged());
  staged.visit(&mut |_|Ok(()),&mut|kind,_,relative,_,bytes|{if kind==1{let target=root.join(relative);std::fs::create_dir_all(target.parent().unwrap())?;let mut file=std::fs::File::create(target)?;std::io::copy(bytes,&mut file)?;file.flush()?;}else{std::io::copy(bytes,&mut std::io::sink())?;}Ok(())}).unwrap();
  assert!(!closure.restat(&backend).unwrap().unchanged(),"real phase writes retire the old issued negative closure");
  let inputs=RecordingInputs::new(backend.clone(),0);let host=queries.clone()as Arc<dyn dm_tree::frontend::SettingExpressionQueries>;let executor=dm_exec::BuildExecutor::new(1).unwrap();let seed=super::generation_reference_hierarchy::seed();let config=dm_tree::frontend::FrontendConfig{workers:1,engine:Some(&seed),observer:None};
  let raw=match inputs.prepare_generation_question_bootstrap(&root.join("deepquarry.dme"),&Default::default(),config,&executor,&host,&mut |_|Ok(())).unwrap(){GenerationBootstrapPreparation::MissingOutputs(frame)=>frame,_=>panic!("actual stage1 outputs remain absent")};let frame=raw.into_native_questions(&inputs,config,&executor,&queries).unwrap();
  let discovery=Arc::new(workspace_discovery::discover(&inputs,DiscoveryContract{root:root.clone(),recursive_roots:vec![root.join("code")]}).unwrap());(root,backend,inputs,frame,discovery,intent,queries)
 }
 #[test]fn actual_all_missing_source_seven_then_native_question_tracked_preserves_original_whole_output_and_no_body_demand(){
  let(root,backend,inputs,frame,discovery,intent,queries)=question_after_source_seven();let compiled=backend.count(&root.join("code/probe.dm"));let mut visits=0;
  queries.with_generation_question_generators(&frame,&inputs,&discovery,&intent,&[GeneratorName::TrackedLists],|artifact,budget,tests|{visits+=1;assert!(tests.contains("/datum/test_box"));assert_eq!(artifact.text.matches("/// TRACKED(").count(),6);assert_eq!(artifact.diags.len(),3);assert!(artifact.text.contains("#if defined(UNIT_TESTS)"));
   // Observation is test-only, but its exposed serialization backing is still
   // funded while the actual phase Budget and artifact loan are live.
   let bound=artifact.charge().checked_mul(8).and_then(|n|n.checked_add(8192)).unwrap();budget.charge(bound).map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))?;let json=serde_json::to_string(&artifact.output_wire()).unwrap();assert!(json.capacity()<=bound);println!("NATIVE_GENERATION_TRACKED_FULL={json}");Ok(())
  }).unwrap();assert_eq!(visits,1);assert_eq!(backend.count(&root.join("code/probe.dm")),compiled);assert_eq!(queries.db.stats(crate::query_db::body_syntax::BODY_SYNTAX).computed,0);assert!(!root.join(GeneratorName::TrackedLists.path()).exists(),"phase consumer only stages data; ordered errors prevent installation");
 }
 #[test]fn generation_tracked_actual_io_quota_cancel_foreign_db_and_callback_unwind_refuse_then_same_frame_recovers(){
  let(root,backend,inputs,frame,discovery,intent,queries)=question_after_source_seven();let names=[GeneratorName::TrackedLists];let mut visits=0;backend.fail.store(true,Ordering::Relaxed);let error=queries.with_generation_question_generators(&frame,&inputs,&discovery,&intent,&names,|_,_,_|{visits+=1;Ok(())}).unwrap_err();assert_eq!(error.raw_os_error(),Some(1450));assert_eq!(visits,0);backend.fail.store(false,Ordering::Relaxed);
  let error=queries.with_generation_question_generators_limit(&frame,&inputs,&discovery,&intent,&names,Some(1),&mut|_,_,_|{visits+=1;Ok(())}).unwrap_err();assert_eq!(error.kind(),io::ErrorKind::OutOfMemory);assert_eq!(visits,0);
  let foreign=QueryDb::default();assert_eq!(foreign.with_generation_question_generators(&frame,&inputs,&discovery,&intent,&names,|_,_,_|{visits+=1;Ok(())}).unwrap_err().kind(),io::ErrorKind::InvalidInput);assert_eq!(visits,0);
  let token=crate::daemon::control::Cancellation::default();let binding=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));token.cancel();assert_eq!(queries.with_generation_question_generators(&frame,&inputs,&discovery,&intent,&names,|_,_,_|{visits+=1;Ok(())}).unwrap_err().kind(),io::ErrorKind::Interrupted);drop(binding);assert_eq!(visits,0);
  let failure=queries.with_generation_question_generators(&frame,&inputs,&discovery,&intent,&names,|_,_,_|Err(io::Error::from_raw_os_error(1450))).unwrap_err();assert_eq!(failure.raw_os_error(),Some(1450));
  let panic=std::panic::catch_unwind(std::panic::AssertUnwindSafe(||{let _=queries.with_generation_question_generators(&frame,&inputs,&discovery,&intent,&names,|_,_,_|->io::Result<()>{panic!("actual generation staged callback")});}));assert!(panic.is_err());queries.with_generation_question_generators(&frame,&inputs,&discovery,&intent,&names,|_,_,_|{visits+=1;Ok(())}).unwrap();assert_eq!(visits,1);assert_eq!(queries.db.stats(crate::query_db::body_syntax::BODY_SYNTAX).computed,0);assert!(!root.join(GeneratorName::TrackedLists.path()).exists());
 }

 fn auto_question_after_source_seven(configured:bool,outside:bool)->(PathBuf,Physical,RecordingInputs<Physical>,GenerationQuestionBootstrap,Arc<DiscoveryReceipt>,crate::policy_request::AdmittedPolicyRequest,Arc<QueryDb>){
  use std::io::Write;let root=crate::test_scratch::dir("generation-auto-purpose");std::fs::create_dir_all(root.join("code/tests")).unwrap();std::fs::create_dir_all(root.join("tools/ci")).unwrap();
  std::fs::write(root.join("code/probe.dm"),include_str!("../../../../../analyze/fixtures/native-auto-generator/basic/code/probe.dm")).unwrap();std::fs::write(root.join("code/tests/only.dm"),include_str!("../../../../../analyze/fixtures/native-auto-generator/basic/code/tests/only.dm")).unwrap();std::fs::write(root.join("code/extra.dm"),"// actual uncompiled source, borrowed only by raw policy\n").unwrap();
  if configured{std::fs::write(root.join("tools/ci/lint_scopes.toml"),include_str!("../../../../../analyze/fixtures/native-auto-generator/configured/tools/ci/lint_scopes.toml")).unwrap();}
  let mut manifest=String::new();for relative in QueryDb::generation_dm_outputs(){manifest.push_str(&format!("#include \"{}\"\n",relative.replace('\\',"/")));}manifest.push_str(include_str!("../../../../../analyze/fixtures/native-auto-generator/basic/deepquarry.dme"));if outside{std::fs::create_dir_all(root.join("outside")).unwrap();std::fs::write(root.join("outside/explicit.dm"),"// genuine required original outside CODE\r\n/datum/probe/proc/set_charge(value)\r\n    charge = value\r\n").unwrap();manifest.push_str("#include \"outside/explicit.dm\"\n");}std::fs::write(root.join("deepquarry.dme"),manifest).unwrap();
  let backend=Physical{fail:Arc::new(AtomicBool::new(false)),raw:root.join("code/extra.dm"),reads:Arc::new(Mutex::new(BTreeMap::new()))};let inputs=RecordingInputs::new(backend.clone(),0);let queries=Arc::new(QueryDb::default());let frame=prepare(&inputs,&root.join("deepquarry.dme"),&queries);let discovery=Arc::new(workspace_discovery::discover(&inputs,DiscoveryContract{root:root.clone(),recursive_roots:vec![root.join("code")]}).unwrap());let mut intent=crate::policy_request::PolicyInputRequest::default();intent.workspace=Some(crate::policy_request::WorkspacePolicyRequest{root:root.clone(),recursive_roots:vec![root.join("code")],configuration:root.join("tools/ci/lint_scopes.toml")});intent.workspace_generators=ROLES.into_iter().chain([GeneratorName::AutoTracked,GeneratorName::TrackedLists,GeneratorName::Deps,GeneratorName::Reads,GeneratorName::DerivedReads,GeneratorName::Plans]).collect();let intent=intent.admit().unwrap();
  let mut journal=crate::generation_journal::StagedJournal::new(crate::generation_staging::temporary_output(&crate::test_scratch::dir("generation-auto-seven-journal")).unwrap()).unwrap();let mut ordinal=0;queries.with_generation_source_generators(&frame,&inputs,&discovery,&intent,&ROLES,|artifact,_,_|{assert!(artifact.diags.is_empty());journal.append_generator(ordinal,artifact.name.name())?;ordinal+=1;if artifact.name==GeneratorName::UiTypes{for(path,text)in&artifact.files{journal.append_file(path,text)?;}}else{let(path,text)=artifact.single()?;journal.append_file(path,text)?;}Ok(())}).unwrap();let mut journal=journal.seal().unwrap();drop(frame);drop(discovery);let closure=inputs.into_snapshot().unwrap();assert!(closure.restat(&backend).unwrap().unchanged());journal.visit(&mut |_|Ok(()),&mut|kind,_,relative,_,bytes|{if kind==1{let target=root.join(relative);std::fs::create_dir_all(target.parent().unwrap())?;let mut file=std::fs::File::create(target)?;std::io::copy(bytes,&mut file)?;file.flush()?;}else{std::io::copy(bytes,&mut std::io::sink())?;}Ok(())}).unwrap();assert!(!closure.restat(&backend).unwrap().unchanged());
  let inputs=RecordingInputs::new(backend.clone(),0);let host=queries.clone()as Arc<dyn dm_tree::frontend::SettingExpressionQueries>;let executor=dm_exec::BuildExecutor::new(1).unwrap();let seed=super::generation_reference_hierarchy::seed();let config=dm_tree::frontend::FrontendConfig{workers:1,engine:Some(&seed),observer:None};let raw=match inputs.prepare_generation_question_bootstrap(&root.join("deepquarry.dme"),&Default::default(),config,&executor,&host,&mut |_|Ok(())).unwrap(){GenerationBootstrapPreparation::MissingOutputs(frame)=>frame,_=>panic!("genuine Auto output remains missing after source seven")};let frame=raw.into_native_questions(&inputs,config,&executor,&queries).unwrap();let discovery=Arc::new(workspace_discovery::discover(&inputs,DiscoveryContract{root:root.clone(),recursive_roots:vec![root.join("code")]}).unwrap());(root,backend,inputs,frame,discovery,intent,queries)
 }
 #[test]fn actual_all_missing_source_seven_then_auto_uses_real_reads_writes_config_and_warm_kind4(){
  use sha2::Digest;for configured in [false,true]{let(root,backend,inputs,frame,discovery,intent,queries)=auto_question_after_source_seven(configured,false);let before=backend.count(&root.join("code/probe.dm"));assert_eq!(queries.db.stats(crate::query_db::body_syntax::BODY_SYNTAX).computed,0);let mut first=None;let mut visits=0;
   queries.with_generation_question_generators(&frame,&inputs,&discovery,&intent,&[GeneratorName::AutoTracked],|artifact,budget,tests|{assert!(tests.contains("/datum/test_only"));assert!(artifact.diags.is_empty());assert!(artifact.text.contains("TRACKED(/datum/probe, charge)"));assert!(artifact.text.contains("TRACKED(/datum/test_only, energy)"));assert!(artifact.text.contains("#if defined(UNIT_TESTS)"));assert_eq!(artifact.text.contains("TRACKED(/datum/probe, excluded)"),!configured);assert_eq!(artifact.text.contains("TRACKED(/datum/manual, spare)"),configured);assert!(!artifact.text.contains("TRACKED(/datum/manual, value)"),"actual reserved-name decision remains blocked");let bound=artifact.charge().checked_mul(8).and_then(|n|n.checked_add(8192)).unwrap();budget.charge(bound).map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))?;let json=serde_json::to_string(&artifact.output_wire()).unwrap();assert!(json.capacity()<=bound);first=Some(<[u8;32]>::from(sha2::Sha256::digest(json.as_bytes())));println!("NATIVE_GENERATION_AUTO_{}={json}",if configured{"CONFIGURED"}else{"BASIC"});visits+=1;Ok(())}).unwrap();let computed=queries.db.stats(crate::query_db::body_syntax::BODY_SYNTAX).computed;assert!(computed>0);
   queries.with_generation_question_generators(&frame,&inputs,&discovery,&intent,&[GeneratorName::AutoTracked],|artifact,budget,_|{let bound=artifact.charge()*8+8192;budget.charge(bound).map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))?;let json=serde_json::to_string(&artifact.output_wire()).unwrap();assert!(json.capacity()<=bound);assert_eq!(first,Some(<[u8;32]>::from(sha2::Sha256::digest(json.as_bytes()))));visits+=1;Ok(())}).unwrap();assert_eq!(visits,2);assert_eq!(queries.db.stats(crate::query_db::body_syntax::BODY_SYNTAX).computed,computed);assert_eq!(backend.count(&root.join("code/probe.dm")),before,"actual compiled original reused");assert!(!root.join(GeneratorName::AutoTracked.path()).exists(),"phase only stages actual output data");
  }
 }
 #[test]fn generation_auto_actual_body_io_quota_cancel_foreign_host_and_unwind_refuse_then_recover(){
  let(root,_backend,inputs,frame,discovery,intent,queries)=auto_question_after_source_seven(false,false);let names=[GeneratorName::AutoTracked];let mut visits=0;let fail=queries.fail_body_syntax_after_for_test(0,io::Error::from_raw_os_error(1450));assert_eq!(queries.with_generation_question_generators(&frame,&inputs,&discovery,&intent,&names,|_,_,_|{visits+=1;Ok(())}).unwrap_err().raw_os_error(),Some(1450));drop(fail);assert_eq!(visits,0);
  assert_eq!(queries.with_generation_question_generators_limit(&frame,&inputs,&discovery,&intent,&names,Some(1),&mut|_,_,_|{visits+=1;Ok(())}).unwrap_err().kind(),io::ErrorKind::OutOfMemory);let foreign=QueryDb::default();assert_eq!(foreign.with_generation_question_generators(&frame,&inputs,&discovery,&intent,&names,|_,_,_|{visits+=1;Ok(())}).unwrap_err().kind(),io::ErrorKind::InvalidInput);
  let token=crate::daemon::control::Cancellation::default();let bound=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));token.cancel();assert_eq!(queries.with_generation_question_generators(&frame,&inputs,&discovery,&intent,&names,|_,_,_|{visits+=1;Ok(())}).unwrap_err().kind(),io::ErrorKind::Interrupted);drop(bound);assert_eq!(visits,0);
  assert_eq!(queries.with_generation_question_generators(&frame,&inputs,&discovery,&intent,&names,|_,_,_|Err(io::Error::from_raw_os_error(1450))).unwrap_err().raw_os_error(),Some(1450));let panic=std::panic::catch_unwind(std::panic::AssertUnwindSafe(||{let _=queries.with_generation_question_generators(&frame,&inputs,&discovery,&intent,&names,|_,_,_|->io::Result<()>{panic!("actual Auto phase consumer")});}));assert!(panic.is_err());queries.with_generation_question_generators(&frame,&inputs,&discovery,&intent,&names,|artifact,_,_|{assert!(artifact.text.contains("TRACKED(/datum/probe, charge)"));visits+=1;Ok(())}).unwrap();assert_eq!(visits,1);assert!(!root.join(GeneratorName::AutoTracked.path()).exists());
 }
 #[test]fn generation_auto_uses_genuine_required_outside_code_callable_header_without_original_reread(){
  let(root,backend,inputs,frame,discovery,intent,queries)=auto_question_after_source_seven(false,true);let outside=root.join("outside/explicit.dm");let before=backend.count(&outside);queries.with_generation_question_generators(&frame,&inputs,&discovery,&intent,&[GeneratorName::AutoTracked],|artifact,_,_|{assert!(!artifact.text.contains("TRACKED(/datum/probe, charge)"),"actual handwritten setter is a collision");assert!(artifact.text.contains("TRACKED(/datum/probe, excluded)"));assert!(artifact.text.contains("TRACKED(/datum/test_only, energy)"));Ok(())}).unwrap();assert_eq!(backend.count(&outside),before,"required compiled original loan uses actual captured acquisition");
 }
 #[test]fn generation_auto_existing_target_group_is_preadmitted_before_phase_budget_and_reused(){
  let(_root,_backend,inputs,frame,discovery,intent,queries)=auto_question_after_source_seven(false,false);let _:Result<(),()>=frame.with_questions(&inputs,|q|{let formal=q.tree().source_formal_variable_member(dm_ir::SymbolId::of("/datum/probe"),dm_ir::SymbolId::of("charge")).unwrap().unwrap();assert!(q.member_first_original_occurrence(formal).is_err(),"read-only lookup must never trigger legacy unadmitted construction");let counter=crate::query_db::body_syntax_counter_for_test(&queries);let poll=||Ok(());let admission=dm_syntax::SettingAdmission::new(counter,crate::query_db::body_syntax_budget_for_test(),&poll);let used=counter.load(Ordering::Acquire);let held=admission.reserve(crate::query_db::body_syntax_budget_for_test()-used).unwrap();let error=q.prepare_original_member_groups().unwrap_err();assert!(matches!(error,dm_tree::frontend::BodySyntaxFailure::Operational(ref actual)if actual.kind()==io::ErrorKind::OutOfMemory));assert!(q.member_first_original_occurrence(formal).is_err());drop(held);drop(admission);q.prepare_original_member_groups().unwrap();assert!(q.member_first_original_occurrence(formal).unwrap().is_some());let reserved=q.generation_retained_question_charge().unwrap();assert!(reserved>q.generation_metadata_charge());let mut actual=0usize;q.visit_generation_metadata(|_,bytes|actual=actual.checked_add(bytes).unwrap());assert!(reserved>=actual);Ok(Ok(()))}).unwrap();assert_eq!(queries.db.stats(crate::query_db::body_syntax::BODY_SYNTAX).computed,0);queries.with_generation_question_generators(&frame,&inputs,&discovery,&intent,&[GeneratorName::AutoTracked],|_,_,_|Ok(())).unwrap();
 }

 #[test]fn actual_generation_question_purposes_share_one_reader_and_match_warm_whole_outputs(){
  use sha2::Digest;let(root,backend,inputs,frame,discovery,intent,queries)=auto_question_after_source_seven(false,false);
  let names=[GeneratorName::Deps,GeneratorName::SparseSlots,GeneratorName::Reads,GeneratorName::DerivedReads,GeneratorName::TrackedLists,GeneratorName::Plans,GeneratorName::AutoTracked];
  let compiled=backend.count(&root.join("code/probe.dm"));let uncompiled=backend.count(&root.join("code/extra.dm"));let mut first=Vec::new();
  queries.with_generation_question_generators(&frame,&inputs,&discovery,&intent,&names,|artifact,budget,_|{
   assert_eq!(artifact.name,names[first.len()]);let bound=artifact.charge().checked_mul(8).and_then(|n|n.checked_add(8192)).unwrap();budget.charge(bound).map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))?;
   let json=serde_json::to_string(&artifact.output_wire()).unwrap();assert!(json.capacity()<=bound);if !source_only(artifact.name){println!("NATIVE_GENERATION_PURPOSE_FULL={json}");}first.push(<[u8;32]>::from(sha2::Sha256::digest(json.as_bytes())));Ok(())
  }).unwrap();assert_eq!(first.len(),names.len());assert_eq!(backend.count(&root.join("code/probe.dm")),compiled);assert_eq!(backend.count(&root.join("code/extra.dm")),uncompiled+1,"ONE reader owns the uncompiled original for all selected policies");let computed=queries.db.stats(crate::query_db::body_syntax::BODY_SYNTAX).computed;assert!(computed>0);
  let mut cursor=0;queries.with_generation_question_generators(&frame,&inputs,&discovery,&intent,&names,|artifact,budget,_|{let bound=artifact.charge()*8+8192;budget.charge(bound).map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))?;let json=serde_json::to_string(&artifact.output_wire()).unwrap();assert_eq!(<[u8;32]>::from(sha2::Sha256::digest(json.as_bytes())),first[cursor]);cursor+=1;Ok(())}).unwrap();assert_eq!(cursor,names.len());assert_eq!(queries.db.stats(crate::query_db::body_syntax::BODY_SYNTAX).computed,computed);assert_eq!(backend.count(&root.join("code/probe.dm")),compiled);
 }
 #[test]fn actual_derived_only_generation_uses_raw_policy_without_body_demand(){
  let(root,_backend,inputs,frame,discovery,intent,queries)=auto_question_after_source_seven(false,false);let mut calls=0;
  queries.with_generation_question_generators(&frame,&inputs,&discovery,&intent,&[GeneratorName::DerivedReads],|artifact,_,_|{assert_eq!(artifact.name,GeneratorName::DerivedReads);assert_eq!(artifact.files.len(),1);assert_eq!(artifact.files[0].0,"code/_generated/reads.dm");calls+=1;Ok(())}).unwrap();assert_eq!(calls,1);assert_eq!(queries.db.stats(crate::query_db::body_syntax::BODY_SYNTAX).computed,0);assert!(!root.join("code/_generated/reads.dm").exists());
 }
 #[test]fn consumed_bootstrap_stages_then_retires_real_complete_input_closure(){
  let f=fixture();let Fixture{root,project:_,backend,inputs,frame,discovery,intent,queries}=f;
  let spool=crate::generation_staging::temporary_output(&crate::test_scratch::dir("generation-retired-bootstrap")).unwrap();let mut closed=queries.stage_generation_bootstrap(crate::input_snapshot::OwnedGenerationFrame::Declarations(frame),inputs,discovery,&intent,&ROLES,spool).unwrap();
  closed.inputs.require_current(&backend).unwrap();assert_eq!(closed.inputs.root(),root);let mut generators=0;closed.journal.visit(&mut |_|Ok(()),&mut|kind,_,_,_,bytes|{if kind==3{generators+=1;}std::io::copy(bytes,&mut std::io::sink())?;Ok(())}).unwrap();assert_eq!(generators,ROLES.len());
  std::fs::write(root.join("code/compiled.dm"),"/datum/changed\n").unwrap();assert!(closed.inputs.require_current(&backend).is_err());
 }

 #[test]fn remaining_generation_purposes_preserve_io_quota_foreign_eof_and_unwind(){
  let(root,_backend,inputs,frame,discovery,intent,queries)=auto_question_after_source_seven(false,true);let names=[GeneratorName::Deps,GeneratorName::Reads,GeneratorName::DerivedReads,GeneratorName::Plans];let mut visits=0;
  let fail=queries.fail_body_syntax_after_for_test(0,io::Error::from_raw_os_error(1450));assert_eq!(queries.with_generation_question_generators(&frame,&inputs,&discovery,&intent,&names,|_,_,_|{visits+=1;Ok(())}).unwrap_err().raw_os_error(),Some(1450));drop(fail);assert_eq!(visits,0);
  assert_eq!(queries.with_generation_question_generators_limit(&frame,&inputs,&discovery,&intent,&names,Some(1),&mut|_,_,_|{visits+=1;Ok(())}).unwrap_err().kind(),io::ErrorKind::OutOfMemory);assert_eq!(QueryDb::default().with_generation_question_generators(&frame,&inputs,&discovery,&intent,&names,|_,_,_|{visits+=1;Ok(())}).unwrap_err().kind(),io::ErrorKind::InvalidInput);assert_eq!(visits,0);
  assert_eq!(queries.with_generation_question_generators(&frame,&inputs,&discovery,&intent,&names,|_,_,_|Err(io::Error::from_raw_os_error(1450))).unwrap_err().raw_os_error(),Some(1450));
  let unwind=std::panic::catch_unwind(std::panic::AssertUnwindSafe(||{let _=queries.with_generation_question_generators(&frame,&inputs,&discovery,&intent,&names,|_,_,_|->io::Result<()>{panic!("remaining purpose staging unwind")});}));assert!(unwind.is_err());
  queries.with_generation_question_generators(&frame,&inputs,&discovery,&intent,&names,|_,_,_|{visits+=1;Ok(())}).unwrap();assert_eq!(visits,names.len());assert!(!root.join(GeneratorName::Plans.path()).exists());
  std::fs::write(root.join("code/extra.dm"),"// changed uncompiled original after actual discovery\n").unwrap();assert!(queries.with_generation_question_generators(&frame,&inputs,&discovery,&intent,&names,|_,_,_|{visits+=1;Ok(())}).is_err());assert_eq!(visits,names.len());
 }

 #[test]fn consumed_question_purposes_seal_only_after_actual_phase_and_keep_negative_freshness(){
  let(root,backend,inputs,frame,discovery,intent,queries)=auto_question_after_source_seven(false,false);let names=[GeneratorName::Deps,GeneratorName::Reads,GeneratorName::DerivedReads,GeneratorName::Plans,GeneratorName::AutoTracked];
  let spool=crate::generation_staging::temporary_output(&crate::test_scratch::dir("generation-retired-questions")).unwrap();let closed=queries.stage_generation_bootstrap(crate::input_snapshot::OwnedGenerationFrame::Questions(frame),inputs,discovery,&intent,&names,spool).unwrap();closed.inputs.require_current(&backend).unwrap();assert_eq!(closed.inputs.names().collect::<Vec<_>>(),names);assert!(!root.join(GeneratorName::AutoTracked.path()).exists());
  std::fs::create_dir_all(root.join("code/engine/_generated")).unwrap();std::fs::write(root.join(GeneratorName::AutoTracked.path()),"// appeared after all actual question/source guards retired\n").unwrap();assert!(closed.inputs.require_current(&backend).is_err(),"actual registered negative survives complete final recorder move");
 }

 #[test]fn restricted_generation_presentation_uses_fixed_manifest_not_alternate_compile_environment(){
  for fixed in [None,Some("#include \"code/unrelated.dm\"\n")]{
   let Fixture{root,project,backend,inputs,frame,discovery,intent,queries}=fixture();drop(frame);drop(discovery);drop(inputs);let alternate=root.join("main.dme");std::fs::rename(project,&alternate).unwrap();if let Some(text)=fixed{std::fs::write(root.join("deepquarry.dme"),text).unwrap();}
   let inputs=RecordingInputs::new(backend.clone(),0);let frame=prepare(&inputs,&alternate,&queries);let discovery=Arc::new(workspace_discovery::discover(&inputs,DiscoveryContract{root:root.clone(),recursive_roots:vec![root.join("code")]}).unwrap());let spool=crate::generation_staging::temporary_output(&crate::test_scratch::dir("generation-fixed-presentation")).unwrap();
   let closed=queries.stage_generation_bootstrap(crate::input_snapshot::OwnedGenerationFrame::Declarations(frame),inputs,discovery,&intent,&[GeneratorName::SparseSlots],spool).unwrap();assert_eq!(closed.included()[0],fixed.is_none(),"fixed deepquarry observation controls presentation, never main.dme");closed.inputs.require_current(&backend).unwrap();std::fs::write(root.join("deepquarry.dme"),"// changed or appeared fixed presentation\n").unwrap();assert!(closed.inputs.require_current(&backend).is_err(),"actual fixed read/negative remains in moved complete closure");
  }
 }

}

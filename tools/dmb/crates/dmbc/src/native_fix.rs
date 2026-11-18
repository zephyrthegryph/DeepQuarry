//! Opt-in single-file tracked list macro fix on the current retained native host.
//! No legacy Engine/Cx, second parser/model, default CLI activation or fallback.
use crate::{request::{BuildCommand,BuildOutcome,BuildRequest},runner_host::BuildHost};
use dm_preprocess::source_arena_credit::SourceArenaCredit;
use dq_analyze::captured_tracked_fix::ListMacroFixData;
use serde::{Deserialize,Serialize};
use std::{error::Error,fmt,io::{self,Write},path::{Component,Path}};
pub use dq_analyze::native_fix_wire::Mode as Codemod;
#[derive(Clone,Debug,Serialize,Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Request {pub build:BuildRequest,pub codemod:Codemod,pub relative:String,#[serde(default)]pub apply:bool}
impl Request {
 fn validate(&self,host:&BuildHost)->io::Result<()>{self.qualify()?;if !host.retains_artifacts(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"native fix requires actual retained host"))}Ok(())}
 pub(crate) fn qualify(&self)->io::Result<()> {qualify_build(&self.build,self.codemod)?;
  let relative=Path::new(&self.relative);
  if self.relative.is_empty()||self.relative.len()>4096||self.relative.contains(['\\',':'])||relative.is_absolute()
   ||relative.components().any(|part|!matches!(part,Component::Normal(_)))||relative.extension()!=Some(std::ffi::OsStr::new("dm"))
   ||!(self.relative.starts_with("code/")||self.relative.starts_with("maps/"))
   ||self.relative.starts_with("code/engine/_generated/")||self.relative.starts_with("code/_generated/"){
   return Err(io::Error::new(io::ErrorKind::InvalidInput,"native fix accepts exactly one ordinary authored code/maps DM path"))
  }
  Ok(())
 }
 fn metadata_charge(&self,work:&dyn dm_preprocess::source_arena_credit::SourceArenaWork)->io::Result<usize>{
  let mut size=std::mem::size_of::<Self>().checked_mul(8).and_then(|n|n.checked_add(65536)).ok_or(io::ErrorKind::OutOfMemory)?;
  let policy=self.build.policy_inputs.as_ref().expect("cheap shape validated policy");let workspace=policy.workspace.as_ref().expect("cheap shape validated workspace");
  let roots=workspace.recursive_roots.len().checked_mul(4*std::mem::size_of::<std::path::PathBuf>()).and_then(|n|n.checked_add(policy.workspace_auxiliary.len().checked_mul(4*std::mem::size_of::<crate::policy_request::WorkspaceAuxiliaryQuestion>())?)).ok_or(io::ErrorKind::OutOfMemory)?;
  size=size.checked_add(roots).ok_or(io::ErrorKind::OutOfMemory)?;
  for path in std::iter::once(self.build.project.as_path()).chain(self.build.cache_root.as_deref()).chain(std::iter::once(workspace.root.as_path())).chain(std::iter::once(workspace.configuration.as_path())).chain(workspace.recursive_roots.iter().map(|path|path.as_path())).chain(std::iter::once(Path::new(&self.relative))){
   work.checkpoint()?;size=size.checked_add(path.as_os_str().len().checked_mul(64).and_then(|n|n.checked_add(2048)).ok_or(io::ErrorKind::OutOfMemory)?).ok_or(io::ErrorKind::OutOfMemory)?;
  }Ok(size)
 }
}
fn qualify_build(build:&BuildRequest,codemod:Codemod)->io::Result<()>{
  use crate::policy_request::{AnalysisContext,WorkspaceAuxiliaryQuestion as Q};
  if build.command!=BuildCommand::PrepareQuery||!build.exact_inputs||!build.no_cache||build.no_daemon
   ||!build.defines.is_empty()||build.engine_template.is_some()||build.bootstrap_catalog||build.timeout_seconds.is_none()
   ||build.record_inputs.is_some()||build.replay_inputs.is_some()||build.trace_path.is_some()||build.artifact_directory.is_some()
   ||build.output_store.is_some()||build.source_questions.is_some()||build.diagnostic_declarations
   ||build.warnings!=crate::diagnostics::WarningPolicy::default(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"native fix requires live exact no-cache retained Original preparation"))}
  let policy=build.policy_inputs.as_ref().ok_or_else(||io::Error::other("native fix needs its actual workspace intent"))?;
  let workspace=policy.workspace.as_ref().ok_or_else(||io::Error::other("native fix workspace absent"))?;
  if policy.analysis_context!=Some(AnalysisContext::OriginalAnalyze0290)||policy.workspace_auxiliary.as_slice()!=match codemod{Codemod::TrackedTests=>&[Q::TrackedTests][..],Codemod::TrackedDropDeclared=>&[Q::SemReads,Q::Tracked][..],_=>&[Q::Tracked][..]}||!policy.workspace_generators.is_empty()
   ||!policy.files.is_empty()||!policy.search_folders.is_empty()||!workspace.root.is_absolute()||!build.project.is_absolute()
   ||build.project.strip_prefix(&workspace.root).ok()!=Some(Path::new("deepquarry.dme"))||workspace.configuration.strip_prefix(&workspace.root).ok()!=Some(Path::new("tools/ci/lint_scopes.toml")){
   return Err(io::Error::new(io::ErrorKind::InvalidInput,"native fix needs the exact actual tracked source purpose and fixed manifest/configuration"))
  }
  let cache=build.cache_root.as_ref().filter(|path|path.is_absolute()).ok_or_else(||io::Error::other("native fix needs its explicit external cache root"))?;
  if cache.starts_with(&workspace.root)||workspace.root.starts_with(cache){return Err(io::Error::new(io::ErrorKind::InvalidInput,"native fix cache must be disjoint from authored source"))}
  crate::request::validate_timeout_seconds(build.timeout_seconds)?;Ok(())
 }
struct Plan {data:ListMacroFixData,text:String,_credit:SourceArenaCredit}
#[derive(Debug)]pub struct CommittedFailure {primary:Box<dyn Error>,pub replacement:crate::input_snapshot::Stamp}
impl fmt::Display for CommittedFailure {fn fmt(&self,out:&mut fmt::Formatter<'_>)->fmt::Result{write!(out,"authored in-place fix committed=true; reprepare/report failed: {}",self.primary)}}
impl Error for CommittedFailure {fn source(&self)->Option<&(dyn Error+'static)>{Some(self.primary.as_ref())}}
#[derive(Serialize)]struct Report<'a>{schema:&'static str,codemod:Codemod,complete:bool,applied:bool,committed:bool,
 normalized_preimage_bytes:usize,physical_preimage_bytes:usize,physical_preimage_hash:String,preparation:&'a BuildOutcome,reprepared:Option<&'a BuildOutcome>,plan:&'a ListMacroFixData,text:&'a str}
/// Explicit typed transport shim for the same resident host. Existing command
/// defaults are unchanged. The daemon/admin adapter may call this only under
/// its normal single-host request ownership; DATA cannot supply an edit plan.
#[derive(Debug)]pub struct FailedMutation{primary:Box<dyn Error>,pub may_have_changed:bool,pub recovered:bool,recovery:Option<Box<dyn Error>>}
impl fmt::Display for FailedMutation{fn fmt(&self,f:&mut fmt::Formatter<'_>)->fmt::Result{write!(f,"authored in-place fix may_have_changed={} recovered={}: {}",self.may_have_changed,self.recovered,self.primary)?;if let Some(error)=&self.recovery{write!(f,"; recovery failed: {error}")?}Ok(())}}
impl Error for FailedMutation{fn source(&self)->Option<&(dyn Error+'static)>{Some(self.primary.as_ref())}}
pub fn run(request:Request,host:&mut BuildHost,diagnostics:&mut impl Write,output:&mut impl Write)->Result<(),Box<dyn Error>>{run_completed(request,host,diagnostics,output,false).map(|_|())}
pub(crate) struct Completed{pub(crate) inputs:crate::request_runner::author_fix_capture::Inputs,pub(crate) frame:dq_analyze::selected_exclusions_wire::Frame,pub(crate) rewrites:usize,pub(crate) committed:bool,residue:usize,has_schema:bool,declarations:(usize,usize,usize,usize,usize)}
pub(crate) fn run_completed(request:Request,host:&mut BuildHost,diagnostics:&mut impl Write,output:&mut impl Write,plain:bool)->Result<Completed,Box<dyn Error>>{run_anchored(request,host,diagnostics,output,plain,true,None)}
fn run_anchored(request:Request,host:&mut BuildHost,diagnostics:&mut impl Write,output:&mut impl Write,plain:bool,summary:bool,anchor:Option<&crate::request_runner::author_fix_capture::Inputs>)->Result<Completed,Box<dyn Error>> {
 use crate::daemon::{control,prepare_deadline};
 request.validate(host)?;
 let source_root=&request.build.policy_inputs.as_ref().expect("validated policy").workspace.as_ref().expect("validated workspace").root;
 let requested=prepare_deadline::capture(request.build.command,request.build.timeout_seconds,std::time::Instant::now())?.ok_or_else(||io::Error::other("native fix deadline absent"))?;
 let _binding=if control::WorkerContext::capture_for_checkpoints().is_none(){
  if control::current_deadline().is_some(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"native fix cannot start inside publication").into())}
  Some(control::bind_with_deadline(control::Cancellation::default(),requested))
 }else{if control::current_deadline().is_none_or(|deadline|deadline>requested){return Err(io::Error::new(io::ErrorKind::InvalidInput,"native fix cannot extend inherited deadline").into())}None};
 control::checkpoint()?;
 // Borrowed cheap checks precede binding. Clone/admission storage is funded
 // only under the actual original request cancellation/deadline context.
 let _request_metadata=host.source_arena_work().reserve(request.metadata_charge(host.source_arena_work())?)?;
 request.build.policy_inputs.as_ref().expect("validated policy").clone().admit()?;
 let cache_root=request.build.cache_root.as_ref().expect("validated cache");
 let path_width=source_root.as_os_str().len().checked_add(cache_root.as_os_str().len()).and_then(|n|n.checked_add(request.relative.len())).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;
 let _request_paths=host.source_arena_work().reserve(path_width.checked_mul(32).and_then(|n|n.checked_add(65536)).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?)?;
 let actual_root=std::fs::canonicalize(source_root)?;let actual_cache=std::fs::canonicalize(cache_root)?;
 if actual_root.starts_with(&actual_cache)||actual_cache.starts_with(&actual_root){return Err(io::Error::new(io::ErrorKind::InvalidInput,"native fix physical cache overlaps authored source").into())}
 let(prepared,inputs)=crate::request_runner::prepare_native_author_fix(request.build.clone(),host,diagnostics)?;
 if !matches!(prepared,BuildOutcome::QueryPrepared{retained:true,..}){return Err(io::Error::other("native fix did not prepare actual retained source").into())}
 inputs.require_current()?;if let Some(previous)=anchor{previous.require_authored_step(&inputs,None,host.source_arena_work())?;}let state=host.query_state();
 let plan={let state=state.try_lock().map_err(|_|io::Error::new(io::ErrorKind::WouldBlock,"native fix current state borrowed"))?;
  let snapshot=state.snapshot.as_ref().ok_or_else(||io::Error::other("native fix source absent"))?;
  snapshot.require_analysis_context(Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290))?;
  snapshot.with_original_list_macro_fix(&inputs,&request.relative,request.codemod!=Codemod::TrackedListMacros,request.codemod==Codemod::TrackedTests,request.codemod==Codemod::TrackedDropDeclared,|data,budget,work|{
   let text=if summary{data.text(request.apply,budget,&control::checkpoint)}else{data.body_text(request.apply,budget,&control::checkpoint)}.map_err(failure)?;
   let size=data.retained_charge().and_then(|n|n.checked_add(text.capacity())).and_then(|n|n.checked_add(std::mem::size_of::<Plan>()+65536)).ok_or(io::ErrorKind::OutOfMemory)?;
   let credit=work.reserve(size)?;Ok(Plan{data,text,_credit:credit})
  })?};
 inputs.require_current()?;
 if request.codemod==Codemod::TrackedListMacros&&!plan.data.residue().is_empty(){return Err(io::Error::new(io::ErrorKind::Unsupported,format!("native tracked-list-macros: {} unfixable contexts; no source changed",plan.data.residue().len())).into())}
 let path_width=source_root.as_os_str().len().checked_add(request.relative.len()).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;
 let _physical_paths=host.source_arena_work().reserve(path_width.checked_mul(16).and_then(|n|n.checked_add(8192)).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?)?;
 let stamp=inputs.recorded_stamp(&request.relative)?;
 let physical=crate::native_fix_physical::read(&source_root.join(&request.relative),&stamp,host.source_arena_work())?;
 if inputs.target_stamp(&request.relative,&physical.bytes)?!=stamp{return Err(io::Error::other("physical bytes do not match original recorded native payload").into())}
 let mapped=crate::native_fix_physical::map(&physical.bytes,&plan.data,host.source_arena_work())?;
 inputs.require_current()?;
 let mut committed=None;let mut reparsed=None;let mut recovery_inputs=None;
 if request.apply&&!plan.data.edits().is_empty(){
  // Existing host-wide invalidation drops query/handler/raw publications,
  // callable indices, semantic fronts and session memo before mutation.
  host.clear_regions();dm_profile::request_mark("authored.fix.source_retired");
  let mutation=crate::native_author_fix_transaction::commit(&actual_root,&request.relative,&stamp,&physical.bytes,&mapped.bytes,host.source_arena_work(),&mut||inputs.require_current());
  // Attempt recovery even on pre-truncate failure because the old host was
  // retired; after truncate/write failure it is mandatory. Preserve first IO.
  let recovery=crate::request_runner::prepare_native_author_fix(request.build.clone(),host,diagnostics).and_then(|(outcome,current)|if matches!(outcome,BuildOutcome::QueryPrepared{retained:true,..}){current.require_current()?;Ok((outcome,current))}else{Err(io::Error::other("authored fix reprepare did not publish actual current source").into())});
  match mutation{
   Err(error)=>{let(recovered,recovery)=match recovery{Ok(_)=>(true,None),Err(actual)=>(false,Some(actual))};if !recovered{host.clear_regions()};return Err(Box::new(FailedMutation{primary:error.primary,may_have_changed:error.may_have_changed,recovered,recovery}))}
   Ok(installed)=>{let(stamp,transition)=installed.into_parts();committed=Some(stamp);match recovery{Ok((outcome,current))=>{
      if let Err(primary)=inputs.require_authored_step(&current,Some(&transition),host.source_arena_work()){host.clear_regions();return Err(Box::new(CommittedFailure{primary:Box::new(primary),replacement:committed.take().unwrap()}))}
      dm_profile::request_mark("authored.fix.recovered");reparsed=Some(outcome);recovery_inputs=Some(current)},Err(primary)=>{host.clear_regions();return Err(Box::new(CommittedFailure{primary,replacement:committed.take().unwrap()}))}}}
  }
 }else{inputs.require_current()?;}
 control::checkpoint().map_err(|primary|match committed.as_ref(){Some(replacement)=>Box::new(CommittedFailure{primary:Box::new(primary),replacement:replacement.clone()})as Box<dyn Error>,None=>Box::new(primary)})?;
 let final_inputs=recovery_inputs.as_ref().unwrap_or(&inputs);
 if let Err(primary)=final_inputs.require_current(){host.clear_regions();if let Some(replacement)=committed{return Err(Box::new(CommittedFailure{primary,replacement}))}return Err(primary)}
 let mut checked=CheckpointOutput(output);
 let result=if plain{checked.write_all(plan.text.as_bytes()).and_then(|()|checked.flush())}else{serde_json::to_writer(&mut checked,&Report{schema:"native-authored-fix-v1",codemod:request.codemod,complete:true,applied:request.apply,committed:committed.is_some(),normalized_preimage_bytes:plan.data.preimage().len(),physical_preimage_bytes:physical.bytes.len(),physical_preimage_hash:format!("{:032x}",xxhash_rust::xxh3::xxh3_128(&physical.bytes)),preparation:&prepared,reprepared:reparsed.as_ref(),plan:&plan.data,text:&plan.text}).map_err(io::Error::from).and_then(|()|checked.write_all(b"\n")).and_then(|()|checked.flush())};
 if let Err(primary)=result{host.clear_regions();if let Some(replacement)=committed{return Err(Box::new(CommittedFailure{primary:Box::new(primary),replacement}))}return Err(primary.into())}
 if let Err(primary)=final_inputs.require_current(){host.clear_regions();if let Some(replacement)=committed{return Err(Box::new(CommittedFailure{primary,replacement}))}return Err(primary)}
 let frame=crate::daemon::selected_report_wire::Frame::from_prepared(reparsed.as_ref().unwrap_or(&prepared)).map_err(|primary|match committed.as_ref(){Some(replacement)=>Box::new(CommittedFailure{primary:Box::new(primary),replacement:replacement.clone()})as Box<dyn Error>,None=>Box::new(primary)})?.observation_data();let rewrites=plan.data.rewrite_count();let residue=plan.data.residue().len();let has_schema=plan.data.has_schema();let declarations=plan.data.declaration_counts();let committed=committed.is_some();let inputs=recovery_inputs.unwrap_or(inputs);Ok(Completed{inputs,frame,rewrites,committed,residue,has_schema,declarations})
}
// Keep the original bound request live during streaming; preserve a real
// writer error before any later checkpoint can replace it.
struct CheckpointOutput<'a,W:Write>(&'a mut W);
impl<W:Write>Write for CheckpointOutput<'_,W>{
 fn write(&mut self,bytes:&[u8])->io::Result<usize>{crate::daemon::control::checkpoint()?;let count=self.0.write(bytes)?;crate::daemon::control::checkpoint()?;Ok(count)}
 fn flush(&mut self)->io::Result<()>{crate::daemon::control::checkpoint()?;self.0.flush()?;crate::daemon::control::checkpoint()}
}
fn failure(error:dq_analyze::captured_reactive_reads::Failure)->io::Error {match error{dq_analyze::captured_reactive_reads::Failure::Operational(actual)=>actual,dq_analyze::captured_reactive_reads::Failure::Unsupported(reason)=>io::Error::new(io::ErrorKind::Unsupported,reason)}}

#[cfg(test)]mod request_controls {
 use super::*;
 #[test]fn typed_native_fix_request_refuses_other_codemods_options_and_caller_supplied_edits(){
  let(_,build,_,_)=crate::generation_test_fixture::fixture();
  let request=Request{build,codemod:Codemod::TrackedListMacros,relative:"code/probe.dm".into(),apply:false};
  let good=serde_json::to_value(&request).unwrap();
  let mut other=good.clone();other["codemod"]=serde_json::json!("own_set");
  assert!(serde_json::from_value::<Request>(other).unwrap_err().to_string().contains("unknown variant"));
  for name in ["tests","drop_declared","propose_schema","edits","preimage","expected_stamp"]{
   let mut other=good.clone();other[name]=serde_json::json!(true);
   assert!(serde_json::from_value::<Request>(other).unwrap_err().to_string().contains("unknown field"),"{name}");
  }
 }
}


/// Sizing DATA only: never delivered and grants no successful completion.
/// Use the same wire type with maximal fixed widths and actual borrowed JSON
/// path/array widths. Keep the existing 1024-byte header and trailing newline.
fn qualify_terminal_header(root:&Path,prefixes:&[String],mode:Codemod)->io::Result<()> {
 use dq_analyze::{native_fix_wire::{Terminal,Schema,Scope},selected_exclusions_wire::{Frame,Seal,Hex128,MAX_HEADER}};
 struct Count(usize);
 impl Write for Count {
  fn write(&mut self,bytes:&[u8])->io::Result<usize>{crate::daemon::control::checkpoint()?;self.0=self.0.checked_add(bytes.len()).ok_or(io::ErrorKind::OutOfMemory)?;if self.0>MAX_HEADER{return Err(io::Error::new(io::ErrorKind::InvalidInput,"native FIX prefix/root binding exceeds existing terminal header bound before mutation"))}Ok(bytes.len())}
  fn flush(&mut self)->io::Result<()>{Ok(())}
 }
 fn width(value:&impl Serialize)->io::Result<usize>{let mut count=Count(0);serde_json::to_writer(&mut count,value).map_err(io::Error::from)?;Ok(count.0)}
 // Empty path/vector allocate no buffers. False is the longer JSON boolean;
 // Some(maximum seal) is longer than absent diagnostics. This is only a bound.
 let maximum=Terminal{schema:Schema::V1,complete:false,full_policy_parity:false,root:std::path::PathBuf::new(),scope:if prefixes.is_empty(){Scope::AllTrackedSources}else{Scope::PathPrefixes},prefixes:Vec::new(),mode,apply:false,frame:Frame{semantic_revision:Hex128(u128::MAX),source_revision:Hex128(u128::MAX),policy_revision:Hex128(u128::MAX)},selected:u64::MAX,visited:u64::MAX,rewrites:u64::MAX,residue:u64::MAX,committed_files:u64::MAX,diagnostics:Some(Seal{length:u64::MAX,hash:Hex128(u128::MAX)}),report:Seal{length:u64::MAX,hash:Hex128(u128::MAX)}};
 let fixed=width(&maximum)?;let root_width=width(&root)?;let prefix_width=width(&prefixes)?;
 // Empty Path JSON and empty array each occupy two bytes; include real newline.
 let size=fixed.checked_sub(4).and_then(|n|n.checked_add(root_width)).and_then(|n|n.checked_add(prefix_width)).and_then(|n|n.checked_add(1)).ok_or(io::ErrorKind::OutOfMemory)?;
 if size>MAX_HEADER{return Err(io::Error::new(io::ErrorKind::InvalidInput,"native FIX prefix/root binding exceeds existing terminal header bound before mutation"))}Ok(())
}

fn drain(reader:&mut dyn io::Read)->io::Result<()>{let mut bytes=[0u8;8192];loop{crate::daemon::control::checkpoint()?;match reader.read(&mut bytes){Ok(0)=>return Ok(()),Ok(_)=>{},Err(actual)=>return Err(actual)}}}
pub(crate) fn mode_questions(mode:Codemod)->&'static[crate::policy_request::WorkspaceAuxiliaryQuestion]{use crate::policy_request::WorkspaceAuxiliaryQuestion as Q;match mode{Codemod::TrackedTests=>&[Q::TrackedTests],Codemod::TrackedDropDeclared=>&[Q::SemReads,Q::Tracked],_=>&[Q::Tracked]}}
#[derive(Clone,Debug,Serialize,Deserialize)]#[serde(deny_unknown_fields)]pub struct BatchRequest{pub build:BuildRequest,pub codemod:Codemod,pub prefixes:Vec<String>,#[serde(default)]pub apply:bool}
impl BatchRequest{
 pub(crate) fn qualify(&self)->io::Result<()>{qualify_build(&self.build,self.codemod)?;let root=&self.build.policy_inputs.as_ref().unwrap().workspace.as_ref().unwrap().root;qualify_terminal_header(root,&self.prefixes,self.codemod)}
 fn metadata_charge(&self,work:&dyn dm_preprocess::source_arena_credit::SourceArenaWork)->io::Result<usize>{
  let policy=self.build.policy_inputs.as_ref().ok_or_else(||io::Error::other("FIX batch policy absent"))?;let workspace=policy.workspace.as_ref().ok_or_else(||io::Error::other("FIX batch workspace absent"))?;let mut bytes=std::mem::size_of::<Self>().checked_mul(16).and_then(|n|n.checked_add(131072)).ok_or(io::ErrorKind::OutOfMemory)?;
  bytes=bytes.checked_add(self.prefixes.len().checked_mul(8*std::mem::size_of::<String>()).ok_or(io::ErrorKind::OutOfMemory)?).and_then(|n|n.checked_add(workspace.recursive_roots.len().checked_mul(8*std::mem::size_of::<std::path::PathBuf>())?)).ok_or(io::ErrorKind::OutOfMemory)?;
  for path in std::iter::once(self.build.project.as_path()).chain(self.build.cache_root.as_deref()).chain(std::iter::once(workspace.root.as_path())).chain(std::iter::once(workspace.configuration.as_path())).chain(workspace.recursive_roots.iter().map(|p|p.as_path())){work.checkpoint()?;bytes=bytes.checked_add(path.as_os_str().len().checked_mul(128).and_then(|n|n.checked_add(4096)).ok_or(io::ErrorKind::OutOfMemory)?).ok_or(io::ErrorKind::OutOfMemory)?;}
  for prefix in &self.prefixes{work.checkpoint()?;bytes=bytes.checked_add(prefix.len().checked_mul(8).and_then(|n|n.checked_add(128)).ok_or(io::ErrorKind::OutOfMemory)?).ok_or(io::ErrorKind::OutOfMemory)?;}Ok(bytes)
 }
}

struct Targets{paths:Vec<String>,schema_count:usize,_credit:SourceArenaCredit}
#[derive(Debug)]pub struct BatchFailure{pub committed_files:usize,primary:Box<dyn Error>}
impl fmt::Display for BatchFailure{fn fmt(&self,f:&mut fmt::Formatter<'_>)->fmt::Result{write!(f,"native authored FIX incomplete; {} earlier file(s) committed; current attempt: {}",self.committed_files,self.primary)}}impl Error for BatchFailure{fn source(&self)->Option<&(dyn Error+'static)>{Some(self.primary.as_ref())}}
/// Issued only after actual target EOF, each selected operation, every genuine
/// post-write reprepare/transition check and a final actual input barrier.
pub struct BatchOutcome{pub selected:usize,pub visited:usize,pub rewrites:usize,pub residue:usize,pub committed_files:usize,pub(crate) frame:dq_analyze::selected_exclusions_wire::Frame,pub(crate) inputs:crate::request_runner::author_fix_capture::Inputs,_issued:()}
pub fn run_batch(request:BatchRequest,host:&mut BuildHost,diagnostics:&mut impl Write,output:&mut impl Write)->Result<BatchOutcome,Box<dyn Error>>{
 use crate::daemon::{control,prepare_deadline};request.qualify()?;if !host.retains_artifacts(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"native FIX batch requires actual retained host").into())}
 let requested=prepare_deadline::capture(request.build.command,request.build.timeout_seconds,std::time::Instant::now())?.ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"native FIX batch deadline absent"))?;
 let _binding=if control::WorkerContext::capture_for_checkpoints().is_none(){if control::current_deadline().is_some(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"native FIX batch cannot start in publication").into())}Some(control::bind_with_deadline(control::Cancellation::default(),requested))}else{if control::current_deadline().is_none_or(|deadline|deadline>requested){return Err(io::Error::new(io::ErrorKind::InvalidInput,"native FIX batch cannot extend inherited deadline").into())}None};control::checkpoint()?;
 let _metadata=host.source_arena_work().reserve(request.metadata_charge(host.source_arena_work())?)?;request.build.policy_inputs.as_ref().unwrap().clone().admit()?;
 let(prepared,mut previous)=crate::request_runner::prepare_native_author_fix(request.build.clone(),host,diagnostics)?;if !matches!(&prepared,BuildOutcome::QueryPrepared{retained:true,..}){return Err(io::Error::other("native FIX batch did not obtain actual retained source").into())}previous.require_current()?;
 let targets={let state=host.query_state();let state=state.try_lock().map_err(|_|io::Error::new(io::ErrorKind::WouldBlock,"native FIX batch source borrowed"))?;let snapshot=state.snapshot.as_ref().ok_or_else(||io::Error::other("native FIX batch source missing"))?;snapshot.with_original_fix_targets(&previous,request.codemod,&request.prefixes,|data,_,work|{let schema_count=data.schema_count;let paths=data.paths;let initial=paths.capacity().checked_mul(std::mem::size_of::<String>()).and_then(|n|n.checked_add(std::mem::size_of::<Targets>()+65536)).ok_or(io::ErrorKind::OutOfMemory)?;let bytes=paths.iter().try_fold(initial,|n,path|n.checked_add(path.capacity())).ok_or(io::ErrorKind::OutOfMemory)?;let credit=work.reserve(bytes)?;Ok(Targets{paths,schema_count,_credit:credit})})?};previous.require_current()?;
 let mut max_path=0;for path in &targets.paths{control::checkpoint()?;max_path=max_path.max(path.len());}let _one_path=host.source_arena_work().reserve(max_path.checked_mul(4).and_then(|n|n.checked_add(4096)).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?)?;
 let selected=targets.paths.len();let(mut visited,mut rewrites,mut committed_files)=(0usize,0usize,0usize);let mut residue=0usize;let mut declarations=[0usize;5];let mut has_schema=targets.schema_count!=0;let mut frame=crate::daemon::selected_report_wire::Frame::from_prepared(&prepared)?.observation_data();
 for relative in &targets.paths{
  let result=(||->Result<Completed,Box<dyn Error>>{control::checkpoint()?;previous.require_current()?;let one=Request{build:request.build.clone(),codemod:request.codemod,relative:relative.clone(),apply:request.apply};run_anchored(one,host,diagnostics,output,true,false,Some(&previous))})();
  let completed=match result{Ok(completed)=>completed,Err(primary)=>return Err(Box::new(BatchFailure{committed_files,primary}))};if completed.committed{committed_files=committed_files.checked_add(1).ok_or_else(||Box::new(BatchFailure{committed_files,primary:io::Error::from(io::ErrorKind::OutOfMemory).into()})as Box<dyn Error>)?;}visited=visited.checked_add(1).ok_or_else(||Box::new(BatchFailure{committed_files,primary:io::Error::from(io::ErrorKind::OutOfMemory).into()})as Box<dyn Error>)?;rewrites=rewrites.checked_add(completed.rewrites).ok_or_else(||Box::new(BatchFailure{committed_files,primary:io::Error::from(io::ErrorKind::OutOfMemory).into()})as Box<dyn Error>)?;residue=residue.checked_add(completed.residue).ok_or_else(||Box::new(BatchFailure{committed_files,primary:io::Error::from(io::ErrorKind::OutOfMemory).into()})as Box<dyn Error>)?;for (out,value)in declarations.iter_mut().zip([completed.declarations.0,completed.declarations.1,completed.declarations.2,completed.declarations.3,completed.declarations.4]){*out=out.checked_add(value).ok_or_else(||Box::new(BatchFailure{committed_files,primary:io::Error::from(io::ErrorKind::OutOfMemory).into()})as Box<dyn Error>)?;}has_schema|=completed.has_schema;frame=completed.frame;previous=completed.inputs;
 }
 if visited!=selected{return Err(Box::new(BatchFailure{committed_files,primary:io::Error::new(io::ErrorKind::InvalidData,"native FIX stopped before actual selected-roster exhaustion").into()}))}let written=(||->io::Result<()>{let mut checked=CheckpointOutput(output);if request.codemod==Codemod::TrackedDropDeclared{writeln!(&mut checked,"{} TRACKED declaration(s) {} ({} read, {} called only, {} never written), {} kept",declarations[0],if request.apply{"dropped"}else{"droppable (dry run; --apply writes them)"},declarations[2],declarations[3],declarations[4],declarations[1])?;}else if !has_schema{checked.write_all(b"no tracked vars\n")?;}else{writeln!(&mut checked,"{} rewrite(s){}, {} for hand conversion",rewrites,if request.apply{" applied"}else{" (dry run; --apply writes them)"},residue)?;}checked.flush()})();written.map_err(|primary|Box::new(BatchFailure{committed_files,primary:Box::new(primary)})as Box<dyn Error>)?;previous.require_current().map_err(|primary|Box::new(BatchFailure{committed_files,primary})as Box<dyn Error>)?;Ok(BatchOutcome{selected,visited,rewrites,residue,committed_files,frame,inputs:previous,_issued:()})
}

pub(crate) struct StagedBatch{pub(crate) root:std::path::PathBuf,pub(crate) prefixes:Vec<String>,pub(crate) mode:Codemod,pub(crate) apply:bool,pub(crate) completed:BatchOutcome,pub(crate) diagnostics:Option<crate::selected_report_spool::Verified>,pub(crate) report:crate::selected_report_spool::Verified,pub(crate) _credit:SourceArenaCredit}
pub(crate) fn stage_batch(request:BatchRequest,host:&mut BuildHost)->Result<StagedBatch,Box<dyn Error>>{
 use crate::daemon::control;control::checkpoint()?;if control::WorkerContext::capture_for_checkpoints().is_none()||control::current_deadline().is_none(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"native FIX batch staging requires active original daemon request").into())}request.qualify()?;let credit=host.source_arena_work().reserve(request.metadata_charge(host.source_arena_work())?)?;
 let workspace=request.build.policy_inputs.as_ref().unwrap().workspace.as_ref().unwrap();let cache=request.build.cache_root.as_ref().unwrap();let root=workspace.root.clone();let prefixes=request.prefixes.clone();let mode=request.codemod;let apply=request.apply;let mut diagnostics=crate::selected_report_spool::Stage::new(cache)?;let mut report=crate::selected_report_spool::Stage::new(cache)?;
 let completed=run_batch(request,host,&mut diagnostics,&mut report)?;
 let result=(||->Result<_,Box<dyn Error>>{let diagnostics=if diagnostics.length()==0{None}else{Some(diagnostics.seal()?.validate(drain)?.0)};let report=report.seal()?.validate(drain)?.0;completed.inputs.require_current()?;Ok((diagnostics,report))})();let(diagnostics,report)=result.map_err(|primary|Box::new(BatchFailure{committed_files:completed.committed_files,primary})as Box<dyn Error>)?;Ok(StagedBatch{root,prefixes,mode,apply,completed,diagnostics,report,_credit:credit})
}

// Reused authored-transaction status wrappers for the baseline coordinator.
impl BatchFailure{pub(crate) fn from_operation(committed_files:usize,primary:Box<dyn Error>)->Box<dyn Error>{Box::new(Self{committed_files,primary})}}
impl FailedMutation{pub(crate) fn from_attempt(primary:Box<dyn Error>,may_have_changed:bool,recovered:bool,recovery:Option<Box<dyn Error>>)->Box<dyn Error>{Box::new(Self{primary,may_have_changed,recovered,recovery})}}

impl CommittedFailure{
 /// Only an actual writer-minted opaque transition supplies committed truth.
 pub(crate) fn from_verified_transition(primary:Box<dyn Error>,transition:&crate::native_author_fix_transaction::Transition)->Box<dyn Error>{Box::new(Self{primary,replacement:transition.verified_replacement().clone()})}
}

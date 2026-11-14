//! Opt-in single-file tracked list macro fix on the current retained native host.
//! No legacy Engine/Cx, second parser/model, default CLI activation or fallback.
use crate::{request::{BuildCommand,BuildOutcome,BuildRequest},runner_host::BuildHost};
use dm_preprocess::source_arena_credit::SourceArenaCredit;
use dq_analyze::captured_tracked_fix::ListMacroFixData;
use serde::{Deserialize,Serialize};
use std::{error::Error,fmt,io::{self,Write},path::{Component,Path}};
#[derive(Clone,Copy,Debug,Serialize,Deserialize,Eq,PartialEq)]
pub enum Codemod {#[serde(rename="tracked-list-macros")]TrackedListMacros}
#[derive(Clone,Debug,Serialize,Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Request {pub build:BuildRequest,pub codemod:Codemod,pub relative:String,#[serde(default)]pub apply:bool}
impl Request {
 fn validate(&self,host:&BuildHost)->io::Result<()> {
  use crate::policy_request::{AnalysisContext,WorkspaceAuxiliaryQuestion as Q};
  let build=&self.build;
  if build.command!=BuildCommand::PrepareQuery||!build.exact_inputs||!build.no_cache||build.no_daemon||!host.retains_artifacts()
   ||!build.defines.is_empty()||build.engine_template.is_some()||build.bootstrap_catalog||build.timeout_seconds.is_none()
   ||build.record_inputs.is_some()||build.replay_inputs.is_some()||build.trace_path.is_some()||build.artifact_directory.is_some()
   ||build.output_store.is_some()||build.source_questions.is_some()||build.diagnostic_declarations
   ||build.warnings!=crate::diagnostics::WarningPolicy::default(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"native fix requires live exact no-cache retained Original preparation"))}
  let policy=build.policy_inputs.as_ref().ok_or_else(||io::Error::other("native fix needs its actual workspace intent"))?;
  let workspace=policy.workspace.as_ref().ok_or_else(||io::Error::other("native fix workspace absent"))?;
  if policy.analysis_context!=Some(AnalysisContext::OriginalAnalyze0290)||policy.workspace_auxiliary!=[Q::Tracked]||!policy.workspace_generators.is_empty()
   ||!policy.files.is_empty()||!policy.search_folders.is_empty()||!workspace.root.is_absolute()||!build.project.is_absolute()
   ||build.project.strip_prefix(&workspace.root).ok()!=Some(Path::new("deepquarry.dme"))||workspace.configuration.strip_prefix(&workspace.root).ok()!=Some(Path::new("tools/ci/lint_scopes.toml")){
   return Err(io::Error::new(io::ErrorKind::InvalidInput,"native fix needs the exact actual tracked source purpose and fixed manifest/configuration"))
  }
  let relative=Path::new(&self.relative);
  if self.relative.is_empty()||self.relative.len()>4096||self.relative.contains(['\\',':'])||relative.is_absolute()
   ||relative.components().any(|part|!matches!(part,Component::Normal(_)))||relative.extension()!=Some(std::ffi::OsStr::new("dm"))
   ||!(self.relative.starts_with("code/")||self.relative.starts_with("maps/"))
   ||self.relative.starts_with("code/engine/_generated/")||self.relative.starts_with("code/_generated/"){
   return Err(io::Error::new(io::ErrorKind::InvalidInput,"native fix accepts exactly one ordinary authored code/maps DM path"))
  }
  let cache=build.cache_root.as_ref().filter(|path|path.is_absolute()).ok_or_else(||io::Error::other("native fix needs its explicit external cache root"))?;
  if cache.starts_with(&workspace.root)||workspace.root.starts_with(cache){return Err(io::Error::new(io::ErrorKind::InvalidInput,"native fix cache must be disjoint from authored source"))}
  crate::request::validate_timeout_seconds(build.timeout_seconds)?;Ok(())
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
pub fn run(request:Request,host:&mut BuildHost,diagnostics:&mut impl Write,output:&mut impl Write)->Result<(),Box<dyn Error>> {
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
 inputs.require_current()?;let state=host.query_state();
 let plan={let state=state.try_lock().map_err(|_|io::Error::new(io::ErrorKind::WouldBlock,"native fix current state borrowed"))?;
  let snapshot=state.snapshot.as_ref().ok_or_else(||io::Error::other("native fix source absent"))?;
  snapshot.require_analysis_context(Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290))?;
  snapshot.with_original_list_macro_fix(&inputs,&request.relative,|data,budget,work|{
   let text=data.text(request.apply,budget,&control::checkpoint).map_err(failure)?;
   let size=data.retained_charge().and_then(|n|n.checked_add(text.capacity())).and_then(|n|n.checked_add(std::mem::size_of::<Plan>()+65536)).ok_or(io::ErrorKind::OutOfMemory)?;
   let credit=work.reserve(size)?;Ok(Plan{data,text,_credit:credit})
  })?};
 inputs.require_current()?;
 if !plan.data.residue().is_empty(){return Err(io::Error::new(io::ErrorKind::Unsupported,format!("native tracked-list-macros: {} unfixable contexts; no source changed",plan.data.residue().len())).into())}
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
  let mutation=crate::native_author_fix_transaction::commit(source_root,&request.relative,&stamp,&physical.bytes,&mapped.bytes,host.source_arena_work(),&mut||inputs.require_current());
  // Attempt recovery even on pre-truncate failure because the old host was
  // retired; after truncate/write failure it is mandatory. Preserve first IO.
  let recovery=crate::request_runner::prepare_native_author_fix(request.build.clone(),host,diagnostics).and_then(|(outcome,current)|if matches!(outcome,BuildOutcome::QueryPrepared{retained:true,..}){current.require_current()?;Ok((outcome,current))}else{Err(io::Error::other("authored fix reprepare did not publish actual current source").into())});
  match mutation{
   Err(error)=>{let(recovered,recovery)=match recovery{Ok(_)=>(true,None),Err(actual)=>(false,Some(actual))};if !recovered{host.clear_regions()};return Err(Box::new(FailedMutation{primary:error.primary,may_have_changed:error.may_have_changed,recovered,recovery}))}
   Ok(installed)=>{committed=Some(installed.stamp);match recovery{Ok((outcome,current))=>{dm_profile::request_mark("authored.fix.recovered");reparsed=Some(outcome);recovery_inputs=Some(current)},Err(primary)=>{host.clear_regions();return Err(Box::new(CommittedFailure{primary,replacement:committed.take().unwrap()}))}}}
  }
 }else{inputs.require_current()?;}
 control::checkpoint().map_err(|primary|match committed.as_ref(){Some(replacement)=>Box::new(CommittedFailure{primary:Box::new(primary),replacement:replacement.clone()})as Box<dyn Error>,None=>Box::new(primary)})?;
 let final_inputs=recovery_inputs.as_ref().unwrap_or(&inputs);
 if let Err(primary)=final_inputs.require_current(){host.clear_regions();if let Some(replacement)=committed{return Err(Box::new(CommittedFailure{primary,replacement}))}return Err(primary)}
 let mut checked=CheckpointOutput(output);
 let result=serde_json::to_writer(&mut checked,&Report{schema:"native-authored-fix-v1",codemod:request.codemod,complete:true,applied:request.apply,committed:committed.is_some(),normalized_preimage_bytes:plan.data.preimage().len(),physical_preimage_bytes:physical.bytes.len(),physical_preimage_hash:format!("{:032x}",xxhash_rust::xxh3::xxh3_128(&physical.bytes)),preparation:&prepared,reprepared:reparsed.as_ref(),plan:&plan.data,text:&plan.text}).map_err(io::Error::from).and_then(|()|checked.write_all(b"\n")).and_then(|()|checked.flush());
 if let Err(primary)=result{host.clear_regions();if let Some(replacement)=committed{return Err(Box::new(CommittedFailure{primary:Box::new(primary),replacement}))}return Err(primary.into())}
 if let Err(primary)=final_inputs.require_current(){host.clear_regions();if let Some(replacement)=committed{return Err(Box::new(CommittedFailure{primary,replacement}))}return Err(primary)}Ok(())
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

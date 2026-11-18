//! Actual original codemod operation over the retained host and one recorder.
//! All writes reuse the authored in-place kernel; every attempted mutation
//! retires and reprepares before any later plan row or completed delivery.
use super::*;
use std::{error::Error,fmt,io::{self,Write},path::{Path,Component}};
use crate::request::{BuildRequest,BuildCommand};
use crate::request_runner::{codemod_capture::{Captured,Mode as CaptureMode},native_codemod_fixture::{SemanticPrepared,prepare_semantic_only}};
use super::codemod_targets::{Targets,Output,Mode};
use dq_analyze::{codemod::Codemod,captured_codemod_plan::{Plan,Reports,DeliveryMode},native_codemod_fixture_wire::{Binding,Question},captured_reactive_reads::Failure};
type BoxError=Box<dyn Error>;
pub(crate)struct Completed{pub(crate)prepared:SemanticPrepared,pub(crate)exit:i32,pub(crate)committed:usize}
impl Completed{
 pub(crate)fn require_current(&self)->Result<(),BoxError>{self.prepared.inputs.require_current()?;let view=self.prepared.frontend.source_view().map_err(io::Error::other)?;self.prepared.inputs.require_binding(view.mapping(),view.tree().identity(),view.source_revision())?;Ok(())}
 pub(crate)fn frame(&self)->Result<dq_analyze::native_codemod_fixture_wire::SourceFrame,BoxError>{
  self.require_current()?;let view=self.prepared.frontend.source_view().map_err(io::Error::other)?;
  let completeness=match self.prepared.frontend.original_analysis_completeness(){Some(dm_tree::frontend::OriginalAnalysisCompleteness::Complete)=>dq_analyze::native_codemod_fixture_wire::OriginalCompleteness::Complete,Some(dm_tree::frontend::OriginalAnalysisCompleteness::PrimaryPrefix)=>dq_analyze::native_codemod_fixture_wire::OriginalCompleteness::PrimaryPrefix,None=>return Err(invalid("codemod frame has no actual original producer").into())};
  Ok(dq_analyze::native_codemod_fixture_wire::SourceFrame::Semantic{semantic:view.tree().identity(),source:view.source_revision(),completeness})
 }
}

struct State<'a>{prepared:SemanticPrepared,captured:Captured<'a>,targets:Targets<'a>}
#[derive(Debug)]struct AttemptFailure{primary:BoxError,may_have_changed:bool,recovered:bool,recovery:Option<BoxError>}
impl fmt::Display for AttemptFailure{fn fmt(&self,out:&mut fmt::Formatter<'_>)->fmt::Result{write!(out,"codemod mutation may_have_changed={} recovered={}: {}",self.may_have_changed,self.recovered,self.primary)?;if let Some(recovery)=&self.recovery{write!(out,"; recovery failed: {recovery}")?}Ok(())}}
impl Error for AttemptFailure{fn source(&self)->Option<&(dyn Error+'static)>{Some(self.primary.as_ref())}}
fn invalid(message:&'static str)->io::Error{io::Error::new(io::ErrorKind::InvalidInput,message)}
/// Fallible owned copy of the strict request, no text multiplier
/// or serialization-based claim. The caller keeps the source request alive.
pub(crate)fn request_copy(request:&BuildRequest,work:&dyn dm_preprocess::source_arena_credit::SourceArenaWork)->io::Result<(BuildRequest,dm_preprocess::source_arena_credit::SourceArenaCredit)>{
 if request.command!=BuildCommand::PrepareQuery||request.source_questions.is_some()||request.diagnostic_declarations||!request.defines.is_empty()||request.engine_template.is_some()||request.bootstrap_catalog||request.output_store.is_some()||request.record_inputs.is_some()||request.replay_inputs.is_some()||request.artifact_directory.is_some()||request.no_daemon||request.trace_path.is_some(){return Err(invalid("codemod request clone requires the actual strict Original utility shape"))}
 let policy=request.policy_inputs.as_ref().ok_or_else(||invalid("codemod actual policy request absent"))?;let workspace=policy.workspace.as_ref().ok_or_else(||invalid("codemod actual workspace absent"))?;
 if !policy.files.is_empty()||!policy.search_folders.is_empty()||!policy.workspace_generators.is_empty(){return Err(invalid("codemod cannot clone another policy purpose"))}
 let mut credit=work.reserve(std::mem::size_of::<BuildRequest>())?;
 fn path(input:&std::path::PathBuf,work:&dyn dm_preprocess::source_arena_credit::SourceArenaWork,credit:&mut dm_preprocess::source_arena_credit::SourceArenaCredit)->io::Result<std::path::PathBuf>{work.checkpoint()?;let capacity=input.as_os_str().len();work.grow(credit,capacity)?;let mut out=std::path::PathBuf::new();out.try_reserve_exact(capacity).map_err(|_|io::ErrorKind::OutOfMemory)?;if out.capacity()>capacity{return Err(io::ErrorKind::OutOfMemory.into())}out.push(input);Ok(out)}
 let mut roots=Vec::new();work.grow(&mut credit,workspace.recursive_roots.len().checked_mul(std::mem::size_of::<std::path::PathBuf>()).ok_or(io::ErrorKind::OutOfMemory)?)?;roots.try_reserve_exact(workspace.recursive_roots.len()).map_err(|_|io::ErrorKind::OutOfMemory)?;if roots.capacity()>workspace.recursive_roots.len(){return Err(io::ErrorKind::OutOfMemory.into())}for root in &workspace.recursive_roots{roots.push(path(root,work,&mut credit)?);}
 let mut auxiliary=Vec::new();work.grow(&mut credit,policy.workspace_auxiliary.len().checked_mul(std::mem::size_of::<crate::policy_request::WorkspaceAuxiliaryQuestion>()).ok_or(io::ErrorKind::OutOfMemory)?)?;auxiliary.try_reserve_exact(policy.workspace_auxiliary.len()).map_err(|_|io::ErrorKind::OutOfMemory)?;if auxiliary.capacity()>policy.workspace_auxiliary.len(){return Err(io::ErrorKind::OutOfMemory.into())}auxiliary.extend_from_slice(&policy.workspace_auxiliary);
 let mut ignored=Vec::new();work.grow(&mut credit,request.warnings.ignored.len().checked_mul(std::mem::size_of::<String>()).ok_or(io::ErrorKind::OutOfMemory)?)?;ignored.try_reserve_exact(request.warnings.ignored.len()).map_err(|_|io::ErrorKind::OutOfMemory)?;if ignored.capacity()>request.warnings.ignored.len(){return Err(io::ErrorKind::OutOfMemory.into())}for source in &request.warnings.ignored{work.checkpoint()?;work.grow(&mut credit,source.len())?;let mut text=String::new();text.try_reserve_exact(source.len()).map_err(|_|io::ErrorKind::OutOfMemory)?;if text.capacity()>source.len(){return Err(io::ErrorKind::OutOfMemory.into())}text.push_str(source);ignored.push(text);}
 let actual=BuildRequest{command:request.command.clone(),source_questions:None,diagnostic_declarations:false,timeout_seconds:request.timeout_seconds,
  policy_inputs:Some(crate::policy_request::PolicyInputRequest{analysis_context:policy.analysis_context,files:Vec::new(),search_folders:Vec::new(),workspace:Some(crate::policy_request::WorkspacePolicyRequest{root:path(&workspace.root,work,&mut credit)?,recursive_roots:roots,configuration:path(&workspace.configuration,work,&mut credit)?}),workspace_generators:Vec::new(),workspace_auxiliary:auxiliary}),
  project:path(&request.project,work,&mut credit)?,defines:std::collections::BTreeMap::new(),workers:request.workers,engine_template:None,bootstrap_catalog:false,progress_enabled:request.progress_enabled,output_store:None,exact_inputs:request.exact_inputs,no_cache:request.no_cache,cache_root:request.cache_root.as_ref().map(|source|path(source,work,&mut credit)).transpose()?,record_inputs:None,replay_inputs:None,artifact_directory:None,no_daemon:false,trace_path:None,warnings:crate::diagnostics::WarningPolicy{as_errors:request.warnings.as_errors,ignored}};
 work.checkpoint()?;Ok((actual,credit))
}
fn prepare<'a>(request:&BuildRequest,root:&'a Path,cm:&'a dyn Codemod,mode:Mode,host:&mut BuildHost)->Result<State<'a>,BoxError>{
 let(copied,_copy_credit)=request_copy(request,host.source_arena_work())?;
 let capture_mode=match mode{Mode::Check=>CaptureMode::Check,Mode::Apply=>CaptureMode::Apply,Mode::WriteResidue=>CaptureMode::WriteResidue,Mode::Revert=>CaptureMode::Revert};
 let mut captured=Captured::new(root,cm,capture_mode);let mut targets=Targets::new(root,cm.name(),mode)?;
 let prepared={let mut pair=super::codemod_targets::Pair{first:&mut captured,second:&mut targets};prepare_semantic_only(copied,root,host,&mut pair)?};
 Ok(State{prepared,captured,targets})
}
fn recovery<'a>(prior:&State<'a>,request:&BuildRequest,root:&'a Path,cm:&'a dyn Codemod,mode:Mode,host:&mut BuildHost,mutation:Result<crate::native_author_fix_transaction::Committed,crate::native_author_fix_transaction::MutationFailure>,output:Option<Output>)->Result<State<'a>,BoxError>{
 let next=prepare(request,root,cm,mode,host);
 match mutation{
  Err(first)=>{let(recovered,recovery)=match next{Ok(_)=>(true,None),Err(error)=>(false,Some(error))};if !recovered{host.clear_regions()};Err(Box::new(AttemptFailure{primary:first.primary,may_have_changed:first.may_have_changed,recovered,recovery}))},
  Ok(committed)=>{let(_,transition)=committed.into_parts();let next=next.map_err(|primary|{host.clear_regions();Box::new(AttemptFailure{primary,may_have_changed:true,recovered:false,recovery:None})as BoxError})?;let step=match output{Some(kind)=>prior.prepared.inputs.require_codemod_output_step(&next.prepared.inputs,prior.targets.target(kind),&transition,host.source_arena_work()),None=>prior.prepared.inputs.require_codemod_authored_step(&next.prepared.inputs,&transition,host.source_arena_work())};if let Err(primary)=step{host.clear_regions();return Err(Box::new(AttemptFailure{primary:primary.into(),may_have_changed:true,recovered:true,recovery:None}))}Ok(next)},
 }
}
fn write_source<'a>(state:State<'a>,request:&BuildRequest,root:&'a Path,cm:&'a dyn Codemod,mode:Mode,host:&mut BuildHost,relative:&str,before:&[u8],after:&[u8])->Result<State<'a>,BoxError>{
 let actual=state.captured.actual_file(relative).or_else(||state.targets.revert_source(relative)).ok_or_else(||invalid("codemod authored output omitted actual physical capture"))?;if actual.bytes()!=before{return Err(io::Error::new(io::ErrorKind::Interrupted,"codemod authored plan differs from current captured preimage").into())}
 state.prepared.inputs.require_current()?;host.clear_regions();
 let mutation=crate::native_author_fix_transaction::commit(root,relative,actual.stamp(),actual.bytes(),after,host.source_arena_work(),&mut||state.prepared.inputs.require_current());
 recovery(&state,request,root,cm,mode,host,mutation,None)
}
fn write_output<'a>(mut state:State<'a>,request:&BuildRequest,root:&'a Path,cm:&'a dyn Codemod,mode:Mode,host:&mut BuildHost,kind:Output,bytes:&[u8],committed:&mut usize)->Result<State<'a>,BoxError>{
 loop{
  let target=state.targets.target(kind);let Some(parent)=target.next_directory()?else{break};
  if target.stamp()?.is_some(){return Err(invalid("existing codemod output unexpectedly has a missing parent").into())}
  state.prepared.inputs.require_current()?;host.clear_regions();let mutation=crate::native_author_fix_transaction::commit_directory(parent,host.source_arena_work(),&mut||state.prepared.inputs.require_current());
  let next=prepare(request,root,cm,mode,host);
  match mutation{
   Err(first)=>{let(recovered,recovery)=match next{Ok(_)=>(true,None),Err(error)=>(false,Some(error))};if !recovered{host.clear_regions()};return Err(Box::new(AttemptFailure{primary:first.primary,may_have_changed:first.may_have_changed,recovered,recovery}))},
   Ok(actual)=>{let transition=actual.into_transition();let next=next.map_err(|primary|{host.clear_regions();Box::new(AttemptFailure{primary,may_have_changed:true,recovered:false,recovery:None})as BoxError})?;if let Err(primary)=state.prepared.inputs.require_codemod_directory_step(&next.prepared.inputs,&transition,host.source_arena_work()){host.clear_regions();return Err(Box::new(AttemptFailure{primary:primary.into(),may_have_changed:true,recovered:true,recovery:None}))}state=next;*committed=committed.checked_add(1).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;},
  }
 }
 let target=state.targets.target(kind);state.prepared.inputs.require_current()?;host.clear_regions();let mutation=crate::native_author_fix_transaction::commit_codemod(target,bytes,host.source_arena_work(),&mut||state.prepared.inputs.require_current());
 let next=recovery(&state,request,root,cm,mode,host,mutation,Some(kind))?;*committed=committed.checked_add(1).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;Ok(next)
}
/// stdout/stderr must be caller-owned staging sinks. The caller delivers their
/// checked seals only after Completed::require_current succeeds again.
fn run_inner(request:&BuildRequest,binding:&Binding,host:&mut BuildHost,stdout:&mut dyn Write,stderr:&mut dyn Write,progress:&mut Progress)->Result<Completed,BoxError>{
 binding.validate()?;crate::daemon::control::checkpoint()?;
 if crate::daemon::control::WorkerContext::capture_for_checkpoints().is_none()||crate::daemon::control::current_deadline().is_none(){return Err(invalid("codemod requires actual request context and deadline").into())}
 let Question::Codemod{name,apply,revert,write_residue,sites,paths}=&binding.question else{return Err(invalid("codemod coordinator received another utility question").into())};
 let cm=dq_analyze::codemod::native_find(name).ok_or_else(||invalid("codemod registry member absent"))?;let root=binding.root.as_path();
 let mode=if *revert{Mode::Revert}else if *apply{Mode::Apply}else if *write_residue{Mode::WriteResidue}else{Mode::Check};
 if !*revert&&*write_residue&&!paths.is_empty(){return Err(invalid("--write-residue describes the whole tree; drop --path").into())}
 let began=std::time::Instant::now();let mut state=prepare(request,root,cm,mode,host)?;
 if mode==Mode::Revert{return run_revert(state,request,root,cm,host,stdout,stderr,progress)}
 let committed=&mut progress.committed;
 let plan=state.prepared.with_model(root,host,|snapshot|snapshot.with_semantic_only_utility_patterns(root,|inputs,root,budget,work,body,patterns|dq_analyze::captured_codemod_plan::run(inputs,root,budget,work,patterns,body,&crate::daemon::control::checkpoint,cm,*apply,paths,state.captured.calls().map_err(Failure::Operational)?.rows(),&state.captured,state.captured.manifest().and_then(|bytes|std::str::from_utf8(bytes).ok())).map_err(Failure::Operational)))?;
 let delivery=match mode{Mode::Apply=>DeliveryMode::Apply,Mode::WriteResidue=>DeliveryMode::Residue,_=>DeliveryMode::Check};
 let reports=state.prepared.with_model(root,host,|snapshot|snapshot.with_semantic_only_utility_patterns(root,|_,_,budget,work,_,patterns|plan.reports(cm,delivery,*sites,state.captured.committed_residue(),began.elapsed(),budget,work,patterns).map_err(Failure::Operational)))?;
 writeln!(stdout,"{}",reports.data().summary)?;stdout.write_all(reports.data().sites.as_bytes())?;
 match mode{
  Mode::Apply=>{
   if state.targets.target(Output::RevertRecord).stamp()?.is_some(){writeln!(stderr,"analyze codemod: data/codemod/{}/revert.json exists: an earlier --apply is not reverted; run --revert (or delete it) first",cm.name())?;return Ok(Completed{prepared:state.prepared,exit:2,committed:0})}
   // Preserve legacy all-plan-before-first-write. Actual captured before bytes
   // are authenticated again by the SAME writer after each reprepare.
   for change in &plan.result().changes{state=write_source(state,request,root,cm,mode,host,&change.rel,change.before.as_bytes(),change.after.as_bytes())?;*committed=committed.checked_add(1).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;}
   state=write_output(state,request,root,cm,mode,host,Output::RevertRecord,reports.data().record.as_ref().ok_or_else(||invalid("codemod apply omitted exact revert report"))?.as_bytes(),committed)?;
   writeln!(stdout,"{}",reports.data().recipe.as_ref().ok_or_else(||invalid("codemod apply omitted recipe"))?)?;
  },Mode::WriteResidue=>{
   state=write_output(state,request,root,cm,mode,host,Output::Residue,reports.data().residue.as_ref().ok_or_else(||invalid("codemod residue report absent"))?.as_bytes(),committed)?;
   if let Some(keys)=&reports.data().keys{state=write_output(state,request,root,cm,mode,host,Output::Keys,keys.as_bytes(),committed)?;}
   writeln!(stdout,"wrote {}",root.join(state.targets.target(Output::Residue).relative()).display())?;
  },Mode::Check=>stderr.write_all(reports.data().errors.as_bytes())?,Mode::Revert=>unreachable!(),
 }
 state.prepared.inputs.require_current()?;crate::daemon::control::checkpoint()?;Ok(Completed{prepared:state.prepared,exit:reports.data().exit,committed:*committed})
}
struct RevertedCapture<'a>{root:&'a Path,record:&'a str,files:&'a[dq_analyze::codemod::report::RevertFile]}
impl crate::request_runner::utility_capture::Capture for RevertedCapture<'_>{
 fn begin_attempt(&mut self){}
 fn workspace_roster(&mut self,_:&crate::runner_host::workspace_discovery::DiscoveryReceipt,_:&dyn dm_preprocess::source_arena_credit::SourceArenaWork)->io::Result<()>{Ok(())}
 fn prepare_current(&mut self,_:&dm_tree::frontend::DiagnosticSourceView<'_>,_:&crate::runner_host::query_snapshot::SourceSnapshot,_:&dyn dm_preprocess::source_arena_credit::SourceArenaWork)->Result<(),BoxError>{Ok(())}
 fn capture(&mut self,physical:&mut dyn crate::input_snapshot::utility_capture::UtilityPhysicalInputs)->io::Result<()>{
  for(relative,record)in std::iter::once((self.record,true)).chain(self.files.iter().map(|file|(file.file.as_str(),false))){
   let mut path=None;physical.with_work(&mut|work|{path=Some(super::codemod_targets::paid_path(self.root,relative,work)?);Ok(())})?;let(path,_credit)=path.ok_or_else(||io::Error::other("post-revert path work omitted"))?;let actual=physical.read(&path,dq_analyze::selected_exclusions_wire::MAX_STREAM as usize)?;
   if record&&actual.is_some(){return Err(io::Error::new(io::ErrorKind::Interrupted,"removed codemod record was recreated"))}if !record&&actual.is_none(){return Err(io::Error::new(io::ErrorKind::Interrupted,"reverted authored file disappeared"))}
  }Ok(())
 }
}
fn run_revert<'a>(mut state:State<'a>,request:&BuildRequest,root:&'a Path,cm:&'a dyn Codemod,host:&mut BuildHost,stdout:&mut dyn Write,_stderr:&mut dyn Write,progress:&mut Progress)->Result<Completed,BoxError>{
 let plan=state.prepared.with_model(root,host,|snapshot|snapshot.with_semantic_only_utility_patterns(root,|_,_,budget,work,_,patterns|dq_analyze::captured_codemod_plan::revert(state.targets.revert_files().map_err(Failure::Operational)?,&state.targets,budget,work,patterns).map_err(Failure::Operational)))?;
 let committed=&mut progress.committed;for change in &plan.result().changes{state=write_source(state,request,root,cm,Mode::Revert,host,&change.rel,change.before.as_bytes(),change.after.as_bytes())?;*committed=committed.checked_add(1).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;}
 // Original revert removes the record only after every source write. The
 // native path authenticates that ordinary deletion and its exact recorder
 // delta; a real removal/recovery IO is never converted into a success seal.
 let target=state.targets.target(Output::RevertRecord);state.prepared.inputs.require_current()?;host.clear_regions();let mutation=crate::native_author_fix_transaction::remove_codemod(target,host.source_arena_work(),&mut||state.prepared.inputs.require_current());
 let recover=(||->Result<SemanticPrepared,BoxError>{let(copy,_copy_credit)=request_copy(request,host.source_arena_work())?;let mut capture=RevertedCapture{root,record:target.relative(),files:state.targets.revert_files()?};prepare_semantic_only(copy,root,host,&mut capture)})();
 let prepared=match mutation{
  Err(first)=>{let(recovered,recovery)=match recover{Ok(_)=>(true,None),Err(error)=>(false,Some(error))};if !recovered{host.clear_regions()};return Err(Box::new(AttemptFailure{primary:first.primary,may_have_changed:first.may_have_changed,recovered,recovery}))},
  Ok(removal)=>{let next=recover.map_err(|primary|{host.clear_regions();Box::new(AttemptFailure{primary,may_have_changed:true,recovered:false,recovery:None})as BoxError})?;if let Err(primary)=state.prepared.inputs.require_codemod_removal_step(&next.inputs,target,&removal,host.source_arena_work()){host.clear_regions();return Err(Box::new(AttemptFailure{primary:primary.into(),may_have_changed:true,recovered:true,recovery:None}))}next},
 };
 *committed=committed.checked_add(1).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;prepared.inputs.require_current()?;writeln!(stdout,"reverted {} files",plan.result().changes.len())?;crate::daemon::control::checkpoint()?;Ok(Completed{prepared,exit:0,committed:*committed})
}

#[derive(Default)]struct Progress{committed:usize}
struct ObservedOutput<'a>{actual:&'a mut dyn Write,failed:&'a std::cell::Cell<bool>}
impl Write for ObservedOutput<'_>{fn write(&mut self,bytes:&[u8])->io::Result<usize>{let result=self.actual.write(bytes);if result.is_err(){self.failed.set(true)}result}fn flush(&mut self)->io::Result<()>{let result=self.actual.flush();if result.is_err(){self.failed.set(true)}result}}
/// Output after a verified mutation cannot lose the known mutation/recovery
/// truth merely because the staging sink refused its next bytes. The original
/// first typed IO remains Error::source, and no completed value is returned.
pub(crate)fn run(request:&BuildRequest,binding:&Binding,host:&mut BuildHost,stdout:&mut dyn Write,stderr:&mut dyn Write)->Result<Completed,BoxError>{
 let mut progress=Progress::default();let failed=std::cell::Cell::new(false);
 let result=run_inner(request,binding,host,&mut ObservedOutput{actual:stdout,failed:&failed},&mut ObservedOutput{actual:stderr,failed:&failed},&mut progress);
 match result{Err(primary)if progress.committed>0&&primary.downcast_ref::<AttemptFailure>().is_none()=>{if !failed.get(){host.clear_regions()};Err(Box::new(AttemptFailure{primary,may_have_changed:true,recovered:failed.get(),recovery:None}))},other=>other}
}

#[cfg(test)]mod output_controls{use super::*;
 struct Denied;impl Write for Denied{fn write(&mut self,_:&[u8])->io::Result<usize>{Err(io::Error::from_raw_os_error(1450))}fn flush(&mut self)->io::Result<()>{Err(io::Error::from_raw_os_error(1450))}}
 #[test]fn output_observation_retains_first_os_error_and_known_recovered_mutation(){let failed=std::cell::Cell::new(false);let first=ObservedOutput{actual:&mut Denied,failed:&failed}.write_all(b"after verified committed file").unwrap_err();assert!(failed.get());let error=AttemptFailure{primary:first.into(),may_have_changed:true,recovered:true,recovery:None};assert!(error.may_have_changed&&error.recovered);assert_eq!(error.source().unwrap().downcast_ref::<io::Error>().unwrap().raw_os_error(),Some(1450));}
}

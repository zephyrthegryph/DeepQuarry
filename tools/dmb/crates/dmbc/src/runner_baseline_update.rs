//! Explicit full native baseline update on the SAME retained host/recorder.
//! Plans remain operation-local; no alternate parser, cache or source grant.
use super::{BuildHost,workspace_capture::{WorkspaceCapture,BaselineTarget},query_snapshot::{BaselineProjectionRows,workspace_native_guard::NativeReadGuard}};
use dq_analyze::{captured_generator_budget::Budget,lint::{Meta,Run,Policy},scopes::LintScope};
use dm_preprocess::source_arena_credit::SourceArenaCredit;
use std::{error::Error,io::{self,Write},path::Path,sync::Arc};
/// SAME existing full report grant. Last field drops only after every copied
/// target/preimage/output owner and its admission budget have been retired.
pub(super) struct Allocation{budget:Arc<Budget>,_credit:std::sync::Mutex<SourceArenaCredit>}
impl Allocation{
 pub(super) fn budget(&self)->&Arc<Budget>{&self.budget}
 fn settle_retained(&self,work:&dyn dm_preprocess::source_arena_credit::SourceArenaWork)->io::Result<()>{
  work.checkpoint()?;let mut credit=self._credit.lock().map_err(|_|io::Error::other("baseline allocation credit poisoned"))?;
  let retain=self.budget.used();let release=credit.reserved_bytes().checked_sub(retain).ok_or_else(oom)?;
  work.shrink(&mut credit,release)
 }
}
type TargetLoan<'a>=dyn FnMut(Option<&Meta>)->io::Result<BaselineTarget>+'a;
struct Edit{desired:String,target:BaselineTarget}
pub(super) struct Builder{mode:dq_analyze::native_baseline_update_wire::Mode,edits:Vec<Edit>,notes:String,config:Option<Edit>,observed:usize,_allocation:Arc<Allocation>}
fn oom()->io::Error{io::ErrorKind::OutOfMemory.into()}
fn charge(b:&Budget,n:Option<usize>)->io::Result<()>{b.charge(n.ok_or_else(oom)?).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))}
fn row<T>(budget:&Budget,rows:&mut Vec<T>)->io::Result<()>{if rows.len()==rows.capacity(){let cap=rows.capacity().max(1).checked_mul(2).ok_or_else(oom)?;charge(budget,cap.checked_mul(4*std::mem::size_of::<T>()))?;rows.try_reserve_exact(cap-rows.len()).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;if rows.capacity()>cap.saturating_mul(4){return Err(oom())}}Ok(())}
impl Builder{
 pub(super) fn new(credit:SourceArenaCredit,budget:Arc<Budget>,mode:dq_analyze::native_baseline_update_wire::Mode)->Result<Self,Box<dyn Error>>{
  let(layout,_)=std::alloc::Layout::new::<[std::sync::atomic::AtomicUsize;2]>().extend(std::alloc::Layout::new::<Allocation>()).map_err(|_|oom())?;
  charge(&budget,std::mem::size_of::<Self>().checked_add(layout.pad_to_align().size()))?;
  Ok(Self{mode,edits:Vec::new(),notes:String::new(),config:None,observed:0,_allocation:Arc::new(Allocation{budget,_credit:std::sync::Mutex::new(credit)})})
 }
 fn budget(&self)->&Arc<Budget>{self._allocation.budget()}
 fn kernel_mode(&self)->dq_analyze::baseline::Mode{match self.mode{dq_analyze::native_baseline_update_wire::Mode::Update=>dq_analyze::baseline::Mode::Update,dq_analyze::native_baseline_update_wire::Mode::Seed=>dq_analyze::baseline::Mode::Seed,dq_analyze::native_baseline_update_wire::Mode::Migrate=>dq_analyze::baseline::Mode::Migrate}}
 fn note(&mut self,note:&str)->io::Result<()>{if note.is_empty(){return Ok(())}charge(self.budget(),note.len().checked_add(1).and_then(|n|n.checked_mul(4)))?;self.notes.try_reserve_exact(note.len()+1).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;self.notes.push_str(note);self.notes.push('\n');Ok(())}
 fn config(&mut self,target:&mut TargetLoan<'_>)->io::Result<&mut Edit>{
  if self.config.is_none(){let target=target(None)?;charge(self.budget(),target.preimage().len().checked_mul(4))?;let desired=std::str::from_utf8(target.preimage()).unwrap_or_default().to_owned();self.config=Some(Edit{target,desired});}
  Ok(self.config.as_mut().unwrap())
 }
 fn ceiling(&mut self,target:&mut TargetLoan<'_>,lint:&str,rule:&str,n:i64)->io::Result<()>{
  self.config(target)?;let current=self.config.as_ref().unwrap().desired.len();
  let scratch=Budget::scoped_temporaries(self.budget()).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;
  charge(&scratch,current.checked_add(lint.len()).and_then(|n|n.checked_add(rule.len())).and_then(|n|n.checked_add(256)).and_then(|n|n.checked_mul(64)))?;
  let desired=dq_analyze::scopes::render_ceiling(&self.config.as_ref().unwrap().desired,lint,rule,n);
  charge(self.budget(),Some(desired.capacity()))?;self.config.as_mut().unwrap().desired=desired;drop(scratch);Ok(())
 }
 pub(super) fn observe(&mut self,meta:&Meta,scope:&LintScope,rows:BaselineProjectionRows<'_>,_child:&Arc<Budget>,capture:&Arc<WorkspaceCapture>,guard:&NativeReadGuard<'_>)->io::Result<()>{
  if !capture.has_baseline_update_capture(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"baseline planner lost its actual private capture"))}
  let allocation=Arc::clone(&self._allocation);self.observe_using_target(meta,scope,rows,&mut|meta|capture.owned_baseline_update_target(guard,meta,&allocation))
 }
 fn observe_using_target(&mut self,meta:&Meta,scope:&LintScope,rows:BaselineProjectionRows<'_>,target:&mut TargetLoan<'_>)->io::Result<()>{
  crate::daemon::control::checkpoint()?;
  self.observed=self.observed.checked_add(1).ok_or_else(oom)?;
  if let BaselineProjectionRows::CheckGrep(data)=rows{
   let mut changes=Vec::new();let budget=Arc::clone(self.budget());
   let scratch=Budget::scoped_temporaries(self.budget()).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;
   let message=dq_analyze::lints::check_grep::native::plan_baseline_mode(scope,&data.run,self.kernel_mode(),&scratch,&||crate::daemon::control::checkpoint(),&mut|rule,n|{charge(&budget,rule.len().checked_mul(4))?;row(&budget,&mut changes)?;changes.push((rule.to_owned(),n));Ok(())})?;
   for(rule,n)in changes{self.ceiling(target,"check_grep",&rule,n)?;}return self.note(&message)
  }
  let BaselineProjectionRows::Generic{run,text,lines}=rows else{unreachable!()};
  if std::ptr::eq(meta,dq_analyze::captured_system_boundary_pages::metadata()){
   let target=target(Some(meta))?;let(_,header)=dq_analyze::captured_system_boundary_pages::baseline_update_target();
   self.count_target(meta,run,target,header,true)?;return Ok(())
  }
  let mut ceiling_note=String::new();
  if matches!(meta.policy,Policy::Sites{..}|Policy::Hard){
   let notes=meta.rules.iter().try_fold(0usize,|n,r|n.checked_add(r.name.len()).and_then(|n|n.checked_add(64))).and_then(|n|n.checked_mul(4));charge(self.budget(),notes)?;
   let grouping=Budget::scoped_temporaries(self.budget()).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;
   let unknown=run.sites.iter().filter(|site|!meta.rules.iter().any(|rule|rule.name==site.rule)).count();
   charge(&grouping,run.sites.len().checked_mul(4*std::mem::size_of::<&dq_analyze::lint::Site>()).and_then(|n|n.checked_add(meta.rules.len().checked_add(unknown)?.checked_mul(512)?)))?;
   for(rule,found)in run.by_rule(meta){if let Some(&old)=scope.ceilings.get(rule){let count=i64::try_from(found.len()).map_err(|_|oom())?;let new=match self.mode{dq_analyze::native_baseline_update_wire::Mode::Update=>old.min(count),dq_analyze::native_baseline_update_wire::Mode::Seed=>count,dq_analyze::native_baseline_update_wire::Mode::Migrate=>old};if new!=old{self.ceiling(target,meta.name,rule,new)?;use std::fmt::Write as _;write!(&mut ceiling_note," ceiling {} {} -> {};",rule,old,new).unwrap();}}}
  }
  match meta.policy{
   Policy::Sites{baseline,..}=>{
    if lines.len()!=run.sites.len(){return Err(io::Error::new(io::ErrorKind::InvalidData,"baseline actual Sites finding/text shape differs"))}
    let target=target(Some(meta))?;
    let width=lines.iter().try_fold(target.preimage().len(),|n,line|n.checked_add(line.len())).and_then(|n|run.sites.iter().try_fold(n,|n,s|n.checked_add(s.rel.len()).and_then(|n|n.checked_add(s.ident.len())).and_then(|n|n.checked_add(s.rule.len())).and_then(|n|n.checked_add(s.key.len())))).ok_or_else(oom)?;
    let scratch=Budget::scoped_temporaries(self.budget()).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;
    charge(&scratch,width.checked_add(1).and_then(|n|n.checked_mul(128)).and_then(|n|n.checked_add(run.sites.len().checked_add(meta.rules.len())?.checked_add(1)?.checked_mul(8192)?)))?;
    let(desired,count,counts)=dq_analyze::policy_finish::admitted::render_captured_sites_mode(meta,scope,text,run,target.preimage(),self.kernel_mode())?;
    self.add(Edit{target,desired})?;self.note(&format!("{}: baseline {} ({} rows; {});{}",meta.name,baseline,count,counts,ceiling_note))
   },
   Policy::Ceilings{header,..}=>{let target=target(Some(meta))?;self.count_target(meta,run,target,header,false)},
   Policy::Hard=>self.note(&format!("{}: no baseline (hard ban);{}",meta.name,ceiling_note)),
   Policy::Custom if meta.name=="deadline_polling"=>self.note(&dq_analyze::lints::deadline_polling::observed_baseline_report()),
   Policy::Custom=>Err(io::Error::new(io::ErrorKind::Unsupported,"unregistered custom baseline update behavior")),
  }
 }
 fn count_target(&mut self,meta:&Meta,run:&Run,target:BaselineTarget,header:&[&str],custom:bool)->io::Result<()>{
  let width=run.sites.iter().try_fold(target.preimage().len(),|n,site|n.checked_add(site.key.len())).ok_or_else(oom)?;
  let scratch=Budget::scoped_temporaries(self.budget()).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;
  charge(&scratch,width.checked_add(1).and_then(|n|n.checked_mul(64)).and_then(|n|n.checked_add(run.sites.len().checked_add(1)?.checked_mul(4096)?)))?;
  if custom&&matches!(self.mode,dq_analyze::native_baseline_update_wire::Mode::Migrate){return self.note("system_boundary: count ceilings have no rows to migrate")}
  let(desired,count)=dq_analyze::policy_finish::admitted::render_captured_count_mode(target.preimage(),header,run,self.kernel_mode());
  let relative=target.relative();if let Some(desired)=desired{self.add(Edit{target,desired})?;}
  if custom{self.note(&format!("system_boundary: {} {} entries",if matches!(self.mode,dq_analyze::native_baseline_update_wire::Mode::Seed){"wrote"}else{"baseline lowered to"},count))}else{self.note(&format!("{}: baseline {} ({} entries)",meta.name,relative,count))}
 }
 fn add(&mut self,edit:Edit)->io::Result<()>{charge(self.budget(),Some(edit.desired.capacity()))?;if self.edits.iter().any(|old|old.target.relative()==edit.target.relative()){return Err(io::Error::new(io::ErrorKind::InvalidData,"registered baseline targets overlap; require ordered shared-target renderer"))}let budget=Arc::clone(self.budget());row(&budget,&mut self.edits)?;self.edits.push(edit);Ok(())}
}

#[derive(Clone,Debug,serde::Serialize,serde::Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Request{pub build:crate::request::BuildRequest,#[serde(default)]pub mode:dq_analyze::native_baseline_update_wire::Mode,#[serde(default)]pub no_gen:bool,#[serde(default,skip_serializing_if="Vec::is_empty")]pub selectors:Vec<String>}
#[derive(Debug,serde::Serialize)]
pub struct Outcome{pub complete:bool,pub registered:usize,pub committed_files:usize,pub generation_committed:bool}
impl Request{
 pub(crate) fn qualify(&self)->io::Result<()>{
  let b=&self.build;
  if b.command!=crate::request::BuildCommand::PrepareQuery||!b.exact_inputs||!b.no_cache||b.no_daemon||b.timeout_seconds.is_none()||!b.defines.is_empty()||b.record_inputs.is_some()||b.replay_inputs.is_some()||b.trace_path.is_some()||b.artifact_directory.is_some()||b.output_store.is_some()||b.source_questions.is_some()||b.diagnostic_declarations||b.warnings!=crate::diagnostics::WarningPolicy::default(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"baseline update requires live exact no-cache retained Original preparation"))}
  let p=b.policy_inputs.as_ref().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"baseline update policy intent absent"))?;
  if p.analysis_context!=Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290)||!p.files.is_empty()||!p.search_folders.is_empty()||!p.workspace_generators.is_empty()||(!p.workspace_auxiliary.is_empty()&&p.workspace_auxiliary!=crate::policy_request::WorkspaceAuxiliaryQuestion::PRIVATE_FULL_REGISTRY){return Err(io::Error::new(io::ErrorKind::InvalidInput,"baseline update requires the actual full registered Analyze intent"))}
  crate::request::validate_timeout_seconds(b.timeout_seconds)?;Ok(())
 }
}
fn failed(primary:Box<dyn Error>,committed:usize,gen:bool)->Box<dyn Error>{
 let primary=crate::native_fix::BatchFailure::from_operation(committed,primary);
 if gen{Box::new(crate::generation_coordinator::CoordinatorFailure{primary,cleanup:Vec::new(),pending_cleanup:Vec::new(),committed:true})}else{primary}
}
impl Builder{
 pub(super) fn observed_count(&self)->usize{self.observed}
 fn close_plan(&mut self,work:&dyn dm_preprocess::source_arena_credit::SourceArenaWork)->io::Result<()>{
  if self.observed==0{return Err(io::Error::new(io::ErrorKind::InvalidData,"baseline plan has no completed actual producers"))}
  if let Some(config)=self.config.take(){self.add(config)?;}
  self.edits.retain(|edit|edit.desired.as_bytes()!=edit.target.preimage());
  self._allocation.settle_retained(work)
 }
}
fn baseline_selection(host:&BuildHost,selectors:&[String],mode:dq_analyze::native_baseline_update_wire::Mode)->io::Result<Arc<super::NativeCheckSelection>>{
 let mut selection=super::prepare_native_registered_check_selection(selectors,super::FullRegistryCheckOptions{raw:false,ci:false,unused:false,no_cache:true,rehash:true},host.source_arena_work())?;
 Arc::get_mut(&mut selection).ok_or_else(||io::Error::new(io::ErrorKind::InvalidData,"fresh baseline selection already aliased"))?.require_baseline_update(mode)?;Ok(selection)
}
struct Prepared{inputs:super::full_registry_check::FullRegistryCheckInputs,frame:dq_analyze::full_registry_check_wire::CheckFrame,plan:Builder}
fn prepare(host:&mut BuildHost,build:crate::request::BuildRequest,project:&Path,generation_domain:Option<&crate::request_runner::runner_freshness::GenerationInputClosure>,selection:Arc<super::NativeCheckSelection>)->Result<Prepared,Box<dyn Error>>{
 let(inputs,frame,mut plan)=host.stage_registered_baseline_plan(build,selection,generation_domain)?;
 // Actual producer spools retire before reducing their one report grant.
 // The genuine moved input variant remains live through every delivery check.
 inputs.require_report_current(project)?;plan.close_plan(host.source_arena_work())?;Ok(Prepared{inputs,frame,plan})
}

impl BuildHost{
 /// Explicit full native baseline mode; ordinary/default routing unchanged.
 /// A write/error never returns a completed Outcome; previous commits survive.
 pub fn update_native_baselines(&mut self,request:Request,diagnostics:&mut impl Write,output:&mut impl Write)->Result<Outcome,Box<dyn Error>>{
  request.qualify()?;
  super::full_registry_check::with_full_registry_check_context(request.build.command,request.build.timeout_seconds,||run_bound(self,request,diagnostics,output).map(|completed|completed.outcome))
 }
}
pub(crate) struct Completed{pub(crate) root:std::path::PathBuf,pub(crate) project:std::path::PathBuf,pub(crate) mode:dq_analyze::native_baseline_update_wire::Mode,pub(crate) no_gen:bool,pub(crate) outcome:Outcome,pub(crate) inputs:super::full_registry_check::FullRegistryCheckInputs,pub(crate) frame:dq_analyze::full_registry_check_wire::CheckFrame,pub(crate) selection:dq_analyze::full_registry_check_selection_wire::SelectionBinding,pub(crate) selected:usize,_plan:Builder,_metadata:SourceArenaCredit}
pub(crate) const SEND_SCRATCH:usize=8192*18+4096;
pub(crate) struct Staged{pub(crate) completed:Completed,pub(crate) diagnostics:Option<crate::selected_report_spool::Verified>,pub(crate) report:crate::selected_report_spool::Verified,pub(crate) _spool_credit:SourceArenaCredit}
fn drain(reader:&mut dyn std::io::Read)->io::Result<()>{let mut bytes=[0u8;8192];loop{crate::daemon::control::checkpoint()?;if reader.read(&mut bytes)?==0{return Ok(())}}}
pub(crate) fn stage(request:Request,host:&mut BuildHost)->Result<Staged,Box<dyn Error>>{
 use crate::daemon::control;control::checkpoint()?;if control::WorkerContext::capture_for_checkpoints().is_none()||control::current_deadline().is_none(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"baseline staging requires the active original daemon request").into())}request.qualify()?;
 let cache=request.build.cache_root.as_deref().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"baseline staging cache absent"))?;
 let width=cache.as_os_str().len().checked_mul(64).and_then(|n|n.checked_add(65536)).and_then(|n|n.checked_add(SEND_SCRATCH)).ok_or_else(oom)?;let spool_credit=host.source_arena_work().reserve(width)?;
 let mut diagnostics=crate::selected_report_spool::Stage::new(cache)?;let mut report=crate::selected_report_spool::Stage::new(cache)?;
 let completed=run_bound(host,request,&mut diagnostics,&mut report)?;
 let result=(||->Result<_,Box<dyn Error>>{let diagnostics=if diagnostics.length()==0{None}else{Some(diagnostics.seal()?.validate(drain)?.0)};let report=report.seal()?.validate(drain)?.0;completed.inputs.require_report_current(&completed.project)?;Ok((diagnostics,report))})();
 let(diagnostics,report)=result.map_err(|primary|failed(primary,completed.outcome.committed_files,completed.outcome.generation_committed))?;Ok(Staged{completed,diagnostics,report,_spool_credit:spool_credit})
}
#[derive(Clone,Copy)]enum Event<'a>{AfterGeneration,BeforeAttempt(&'a str),Physical(crate::native_author_fix_transaction::Event),BeforeDelivery}
fn run_bound(host:&mut BuildHost,request:Request,diagnostics:&mut impl Write,output:&mut impl Write)->Result<Completed,Box<dyn Error>>{run_bound_using(host,request,diagnostics,output,&mut |_|Ok(()))}
fn run_bound_using(host:&mut BuildHost,request:Request,diagnostics:&mut impl Write,output:&mut impl Write,hook:&mut impl FnMut(Event<'_>)->io::Result<()>)->Result<Completed,Box<dyn Error>>{
 use crate::daemon::control;
 control::checkpoint()?;if !host.retains_artifacts(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"baseline update requires the retained native host").into())}
 let p=request.build.policy_inputs.as_ref().unwrap();let w=p.workspace.as_ref().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"baseline update workspace absent"))?;
 let width=w.recursive_roots.len().checked_add(8).and_then(|n|w.root.as_os_str().len().checked_mul(n)).and_then(|n|n.checked_add(w.configuration.as_os_str().len())).and_then(|n|n.checked_add(request.build.cache_root.as_ref().map_or(0,|p|p.as_os_str().len()))).and_then(|n|n.checked_mul(64)).and_then(|n|n.checked_add(131072)).ok_or_else(oom)?;
 let width=request.selectors.iter().try_fold(width.checked_add(request.selectors.capacity().checked_mul(std::mem::size_of::<String>()).ok_or_else(oom)?).ok_or_else(oom)?,|n,selector|n.checked_add(selector.capacity()).ok_or_else(oom))?;
 let _metadata=host.source_arena_work().reserve(width)?;
 let(root,cache)=BuildHost::native_registry_check_paths(&request.build)?;
 let project=crate::policy_request::canonical_analysis_project(&request.build.project,Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290))?;
 let selection=baseline_selection(host,&request.selectors,request.mode)?;
 dq_analyze::native_baseline_update_wire::require_header_room(&root,selection.binding(),u64::try_from(selection.names().len()).map_err(|_|oom())?,u64::try_from(selection.registered_count()?).map_err(|_|oom())?)?;
 let mut generation_committed=false;let mut generation_inputs=None;
 if !request.no_gen{
  let mut build=request.build.clone();let policy=build.policy_inputs.as_mut().unwrap();policy.workspace_auxiliary.clear();policy.workspace_generators=crate::generation_coordinator::OBSERVED_NAMES.to_vec();
  let report=crate::generation_coordinator::run(host,&build,&crate::generation_coordinator::OBSERVED_NAMES,crate::generation_transaction::Mode::Write,&cache)?;
  generation_committed=report.committed;
  for row in &report.diagnostics{control::checkpoint().map_err(|e|failed(e.into(),0,generation_committed))?;writeln!(diagnostics,"{}:{}: [gen/{}] {}",row.relative,row.line,row.name.name(),row.message).map_err(|e|failed(e.into(),0,generation_committed))?;}
  for row in &report.cleanup{writeln!(diagnostics,"committed cleanup warning for {}: {}",row.path.display(),row.error).map_err(|e|failed(e.into(),0,generation_committed))?;}
  let clean=!report.rows.is_empty()&&report.diagnostics.is_empty()&&report.cleanup.is_empty()&&report.rows.iter().all(|row|matches!(row.state,crate::generation_transaction::State::Fresh|crate::generation_transaction::State::Written));
  if !clean{return Err(failed(crate::request_failure::RequestFailure::source("analyze baseline: native GEN did not finish cleanly; no baseline was attempted").into(),0,generation_committed))}
  let inputs=(||->Result<crate::request_runner::runner_freshness::GenerationInputClosure,Box<dyn Error>>{
   let snapshot={let state=host.query_state();let mut state=state.try_lock().map_err(|_|io::Error::new(io::ErrorKind::WouldBlock,"final GEN frame borrowed"))?;state.snapshot.take().ok_or_else(||io::Error::other("actual final GEN source absent"))?};
  let inputs=snapshot.retire_for_generation()?;inputs.require_current_exact()?;Ok(inputs)
  })().map_err(|e|failed(e,0,generation_committed))?;
  generation_inputs=Some(inputs);
  hook(Event::AfterGeneration).map_err(|e|failed(e.into(),0,generation_committed))?;
  host.clear_regions();dm_tree::frontend::BodySyntaxQueries::begin_revision(host.query_db().as_ref());
 }
 // The first baseline snapshot is genuinely prepared AFTER the GEN operation.
 let mut current=prepare(host,request.build.clone(),&project,generation_inputs.as_ref(),Arc::clone(&selection)).map_err(|e|failed(e,0,generation_committed))?;
 if let Some(inputs)=&generation_inputs{inputs.require_current_exact().map_err(|e|failed(e,0,generation_committed))?;}
 let selected=current.plan.observed;let registered=selection.registered_count()?;let mut committed=0usize;
 // Keep the initial completed render in registry order; subsequent captures
 // exist solely to authenticate each exact step and current final source.
 let mut edits=std::mem::take(&mut current.plan.edits).into_iter();
 while let Some(edit)=edits.next(){
  control::checkpoint().map_err(|e|failed(e.into(),committed,generation_committed))?;
  current.inputs.require_report_current(&project).map_err(|e|failed(e,committed,generation_committed))?;
  hook(Event::BeforeAttempt(edit.target.relative())).map_err(|e|failed(e.into(),committed,generation_committed))?;
  host.clear_regions();
  let attempted=crate::native_author_fix_transaction::commit_baseline_target_using(&edit.target,edit.desired.as_bytes(),host.source_arena_work(),&mut||current.inputs.require_report_current(&project),&mut|event|hook(Event::Physical(event)));
  // Every attempted OS mutation, successful or not, uses the SAME actual host
  // preparation path under the still-bound original cancellation/deadline.
  let recovery=prepare(host,request.build.clone(),&project,generation_inputs.as_ref(),Arc::clone(&selection));
  match attempted{
   Err(actual)=>{
    let(recovered,recovery)=match recovery{Ok(value)=>{drop(value);(true,None)},Err(error)=>{host.clear_regions();(false,Some(error))}};
    return Err(failed(crate::native_fix::FailedMutation::from_attempt(actual.primary,actual.may_have_changed,recovered,recovery),committed,generation_committed))
   },
   Ok(installed)=>{
    committed=committed.checked_add(1).ok_or_else(||failed(oom().into(),committed,generation_committed))?;
    let(_,transition)=installed.into_parts();
    let next=match recovery{Ok(value)=>value,Err(primary)=>{host.clear_regions();return Err(failed(primary,committed,generation_committed))}};
    if let Err(primary)=current.inputs.require_baseline_step(&next.inputs,&project,&transition,host.source_arena_work()){
     host.clear_regions();return Err(failed(primary.into(),committed,generation_committed))
    }
    let Prepared{inputs,frame,plan}=next;drop(plan);current.inputs=inputs;current.frame=frame;
   }
  }
 }
 hook(Event::BeforeDelivery).map_err(|e|failed(e.into(),committed,generation_committed))?;
 current.inputs.require_report_current(&project).map_err(|e|failed(e,committed,generation_committed))?;
 let mut stage=crate::selected_report_spool::Stage::new(&cache).map_err(|e|failed(e.into(),committed,generation_committed))?;
 stage.write_all(current.plan.notes.as_bytes()).map_err(|e|failed(e.into(),committed,generation_committed))?;
 let stage=super::query_snapshot::checked_selected_report_stage(stage).map_err(|e|failed(e.into(),committed,generation_committed))?;
 current.inputs.require_report_current(&project).map_err(|e|failed(e,committed,generation_committed))?;
 stage.publish(output).map_err(|e|failed(e.into(),committed,generation_committed))?;
 current.inputs.require_report_current(&project).map_err(|e|failed(e,committed,generation_committed))?;control::checkpoint().map_err(|e|failed(e.into(),committed,generation_committed))?;
 let Prepared{inputs,frame,plan}=current;Ok(Completed{root,project,mode:request.mode,no_gen:request.no_gen,selection:selection.binding(),selected,outcome:Outcome{complete:true,registered,committed_files:committed,generation_committed},inputs,frame,_plan:plan,_metadata})
}

#[cfg(test)]#[path="../../../../analyze/fixtures/report_configuration.rs"]mod fixture_configuration;
#[cfg(test)]mod controls{use super::*;use std::{fs,path::PathBuf};
 fn put(root:&Path,relative:&str,bytes:impl AsRef<[u8]>){let p=root.join(relative);fs::create_dir_all(p.parent().unwrap()).unwrap();fs::write(p,bytes).unwrap();}
 fn fixture(label:&str)->(BuildHost,Request,PathBuf,String,Vec<u8>){
  let root=fs::canonicalize(crate::test_scratch::dir(label)).unwrap();let cache=fs::canonicalize(crate::test_scratch::dir(&format!("{label}-cache"))).unwrap();
  use crate::policy_request::{WorkspaceAuxiliaryQuestion as Q,WorkspacePolicyRequest,PolicyInputRequest,AnalysisContext};let roots=Q::authored_doc_ui_roots(Q::PRIVATE_FULL_REGISTRY).unwrap();for dir in roots{fs::create_dir_all(root.join(dir)).unwrap();}fs::create_dir_all(root.join(dq_analyze::ui_actions_policy::INTERFACES)).unwrap();
  put(&root,"deepquarry.dme","#include \"code/probe.dm\"\n");put(&root,"code/probe.dm","/proc/probe()\n    return 0\n");put(&root,"tools/ci/lint_scopes.toml",fixture_configuration::with_overlay(""));
  let crate::request::Command::Build(build)=crate::cli::parse(&["prepare-query".into(),root.join("deepquarry.dme").to_string_lossy().into_owned()]).unwrap()else{panic!("actual preparation")};let mut build=*build;build.no_cache=true;build.exact_inputs=true;build.progress_enabled=false;build.workers=1;build.timeout_seconds=Some(60);build.engine_template=None;build.bootstrap_catalog=false;build.cache_root=Some(cache);build.policy_inputs=Some(PolicyInputRequest{analysis_context:Some(AnalysisContext::OriginalAnalyze0290),workspace:Some(WorkspacePolicyRequest{root:root.clone(),recursive_roots:roots.iter().map(|p|root.join(p)).collect(),configuration:root.join("tools/ci/lint_scopes.toml")}),..Default::default()});
  let mut host=BuildHost::default();let selection=super::super::prepare_native_registered_check_selection(&[],super::super::FullRegistryCheckOptions::default(),host.source_arena_work()).unwrap();let meta=selection.metadata().find(|m|match m.policy{Policy::Sites{banned,..}=>m.rules.iter().any(|r|!banned.contains(&r.name)),_=>false}).unwrap();let Policy::Sites{baseline,banned,..}=meta.policy else{unreachable!()};let rule=meta.rules.iter().find(|r|!banned.contains(&r.name)).unwrap().name;let target=baseline.to_owned();let row=format!("{rule}\tcode/gone.dm\tremoved fixture source\n");drop(selection);
  // Fixture setup uses the actual native planner to seed its canonical empty
  // outputs. The exercised update below starts on a fresh genuine host.
  let project=build.project.clone();let prepared=super::super::full_registry_check::with_full_registry_check_context(build.command,build.timeout_seconds,||{let selection=baseline_selection(&host,&[],dq_analyze::native_baseline_update_wire::Mode::Update)?;prepare(&mut host,build.clone(),&project,None,selection)}).unwrap();
  for edit in &prepared.plan.edits{put(&root,edit.target.relative(),edit.desired.as_bytes());}drop(prepared);drop(host);
  let clean=fs::read(root.join(&target)).unwrap();let mut old=clean.clone();old.extend_from_slice(row.as_bytes());fs::write(root.join(&target),&old).unwrap();(BuildHost::default(),Request{build,mode:dq_analyze::native_baseline_update_wire::Mode::Update,no_gen:true,selectors:Vec::new()},root,target,clean)
 }
 fn actual_io(mut error:&(dyn Error+'static))->Option<i32>{loop{if let Some(io)=error.downcast_ref::<io::Error>(){if let Some(raw)=io.raw_os_error(){return Some(raw)}}error=error.source()?;}}
 fn using(host:&mut BuildHost,request:Request,out:&mut impl Write,hook:&mut impl FnMut(Event<'_>)->io::Result<()>)->Result<Completed,Box<dyn Error>>{super::super::full_registry_check::with_full_registry_check_context(request.build.command,request.build.timeout_seconds,||run_bound_using(host,request,&mut io::sink(),out,hook))}
 #[test]fn actual_native_baseline_update_shrinks_captured_rows_then_reprepares_and_delivers_current(){let(mut host,request,root,target,clean)=fixture("baseline-current-shrink");let(mut diagnostics,mut report)=(Vec::new(),Vec::new());let result=host.update_native_baselines(request.clone(),&mut diagnostics,&mut report).unwrap();assert!(result.complete);assert_eq!(result.committed_files,1);assert!(!result.generation_committed);assert_eq!(fs::read(root.join(&target)).unwrap(),clean);assert!(!report.is_empty());let again=host.update_native_baselines(request,&mut diagnostics,&mut Vec::new()).unwrap();assert_eq!(again.committed_files,0);}
 #[test]fn actual_native_baseline_first_io_before_write_preserves_bytes_and_same_host_recovers(){let(mut host,request,root,target,clean)=fixture("baseline-before-write-io");let before=fs::read(root.join(&target)).unwrap();let mut calls=0;let error=using(&mut host,request.clone(),&mut Vec::new(),&mut|e|{if matches!(e,Event::BeforeAttempt(_)){calls+=1;return Err(io::Error::from_raw_os_error(1450))}Ok(())}).err().unwrap();assert_eq!(actual_io(error.as_ref()),Some(1450));assert_eq!(calls,1);assert_eq!(fs::read(root.join(&target)).unwrap(),before);let result=host.update_native_baselines(request,&mut Vec::new(),&mut Vec::new()).unwrap();assert_eq!(result.committed_files,1);assert_eq!(fs::read(root.join(target)).unwrap(),clean);}
 #[test]fn actual_native_baseline_after_truncate_io_is_first_and_same_host_reprepares_before_retry(){let(mut host,request,root,target,_)=fixture("baseline-after-truncate-io");let error=using(&mut host,request.clone(),&mut Vec::new(),&mut|e|if matches!(e,Event::Physical(crate::native_author_fix_transaction::Event::AfterTruncate)){Err(io::Error::from_raw_os_error(1450))}else{Ok(())}).err().unwrap();assert_eq!(actual_io(error.as_ref()),Some(1450));let mutation=error.source().unwrap().downcast_ref::<crate::native_fix::FailedMutation>().expect("actual attempted-writer failure");assert!(mutation.may_have_changed);assert!(mutation.recovered,"same-host genuine reprepare must complete before returning the original IO");assert!(fs::read(root.join(&target)).unwrap().is_empty());let result=host.update_native_baselines(request,&mut Vec::new(),&mut Vec::new()).unwrap();assert!(result.complete);assert!(!fs::read(root.join(target)).unwrap().is_empty());}
 #[test]fn actual_native_baseline_config_change_before_mutation_is_not_overwritten(){let(mut host,request,root,target,_)=fixture("baseline-config-external");let before=fs::read(root.join(&target)).unwrap();let config=root.join("tools/ci/lint_scopes.toml");let mut text=fs::read(&config).unwrap();text.extend_from_slice(b"\n# external writer\n");let mut changed=false;let error=using(&mut host,request,&mut Vec::new(),&mut|e|{if matches!(e,Event::BeforeAttempt(_))&&!changed{fs::write(&config,&text)?;changed=true;}Ok(())}).err().unwrap();assert!(changed);assert!(error.to_string().contains("changed")||error.to_string().contains("current"),"{error}");assert_eq!(fs::read(root.join(target)).unwrap(),before);assert_eq!(fs::read(config).unwrap(),text);}
 #[test]fn actual_native_baseline_final_delivery_io_retains_committed_count_and_original_os_error(){let(mut host,request,root,target,clean)=fixture("baseline-output-io");struct Stop;impl Write for Stop{fn write(&mut self,_:&[u8])->io::Result<usize>{Err(io::Error::from_raw_os_error(1450))}fn flush(&mut self)->io::Result<()>{Ok(())}}let error=host.update_native_baselines(request,&mut Vec::new(),&mut Stop).unwrap_err();assert_eq!(actual_io(error.as_ref()),Some(1450));assert_eq!(error.downcast_ref::<crate::native_fix::BatchFailure>().expect("real committed operation wrapper").committed_files,1);assert_eq!(fs::read(root.join(target)).unwrap(),clean);}
 #[test]fn actual_native_baseline_absent_target_is_created_then_exact_next_recorder_accepts_only_writer_step(){let(mut host,request,root,target,clean)=fixture("baseline-absent-created");fs::remove_file(root.join(&target)).unwrap();let result=host.update_native_baselines(request,&mut Vec::new(),&mut Vec::new()).unwrap();assert_eq!(result.committed_files,1);assert_eq!(fs::read(root.join(&target)).unwrap(),clean);}
 #[test]fn actual_native_baseline_external_creation_after_negative_capture_is_preserved(){let(mut host,request,root,target,_)=fixture("baseline-absent-foreign");fs::remove_file(root.join(&target)).unwrap();let mut created=false;let error=using(&mut host,request,&mut Vec::new(),&mut|e|{if let Event::BeforeAttempt(relative)=e{if relative==target&&!created{fs::write(root.join(&target),b"# independently created target\n")?;created=true;}}Ok(())}).err().unwrap();assert!(created);let mutation=error.source().unwrap().downcast_ref::<crate::native_fix::FailedMutation>().unwrap();assert!(!mutation.may_have_changed);assert!(mutation.recovered);assert_eq!(fs::read(root.join(target)).unwrap(),b"# independently created target\n");}
 #[test]fn actual_native_baseline_resource_denial_precedes_mutation_then_released_same_host_recovers(){let(mut host,request,root,target,clean)=fixture("baseline-pressure-recovery");let before=fs::read(root.join(&target)).unwrap();let pressure=host.source_arena_work().reserve(128*1024*1024-512*1024).unwrap();let error=host.update_native_baselines(request.clone(),&mut Vec::new(),&mut Vec::new()).unwrap_err();let mut at=error.as_ref();let mut oom=false;loop{if at.downcast_ref::<io::Error>().is_some_and(|e|e.kind()==io::ErrorKind::OutOfMemory){oom=true;break}match at.source(){Some(next)=>at=next,None=>break}}assert!(oom,"{error}");assert_eq!(fs::read(root.join(&target)).unwrap(),before);drop(pressure);let result=host.update_native_baselines(request,&mut Vec::new(),&mut Vec::new()).unwrap();assert_eq!(result.committed_files,1);assert_eq!(fs::read(root.join(target)).unwrap(),clean);}

 #[test]fn actual_native_baseline_real_all_generator_operation_precedes_first_update_capture(){let(mut host,mut request,root,target,clean)=fixture("baseline-real-gen-order");request.no_gen=false;let mut generated=0;let mut attempts=0;let completed=using(&mut host,request,&mut Vec::new(),&mut|e|{match e{Event::AfterGeneration=>generated+=1,Event::BeforeAttempt(_)=>{assert_eq!(generated,1,"actual clean closed GEN must precede any baseline attempt");attempts+=1},_=>{}}Ok(())}).unwrap();assert_eq!(generated,1);assert!(attempts>0);assert!(completed.outcome.complete);assert!(completed.outcome.generation_committed,"fresh fixture starts with no generated target roster");assert_eq!(fs::read(root.join(target)).unwrap(),clean);}
 #[test]fn actual_native_baseline_real_gen_error_before_capture_keeps_original_io_and_never_writes_baseline(){let(mut host,mut request,root,target,_)=fixture("baseline-real-gen-first-io");request.no_gen=false;let before=fs::read(root.join(&target)).unwrap();let mut called=0;let error=using(&mut host,request,&mut Vec::new(),&mut|e|{if matches!(e,Event::AfterGeneration){called+=1;return Err(io::Error::from_raw_os_error(1450))}if matches!(e,Event::BeforeAttempt(_)){panic!("baseline cannot be attempted after GEN handoff IO")}Ok(())}).err().unwrap();assert_eq!(called,1);assert_eq!(actual_io(error.as_ref()),Some(1450));assert_eq!(fs::read(root.join(target)).unwrap(),before);}

 #[test]fn actual_native_baseline_seed_adds_real_library_dependency_while_update_never_adds_it(){let(mut host,mut request,root,_,_)=fixture("baseline-mode-real-seed");put(&root,"code/content/baseline_target.dm","/datum/content_target\n");put(&root,"code/library/baseline_use.dm","/datum/library_probe\n    var/datum/content_target/target\n");put(&root,"deepquarry.dme","#include \"code/probe.dm\"\n#include \"code/content/baseline_target.dm\"\n#include \"code/library/baseline_use.dm\"\n");let path=root.join("tools/ci/library_layering_baseline.txt");host.update_native_baselines(request.clone(),&mut Vec::new(),&mut Vec::new()).unwrap();let old=fs::read_to_string(&path).unwrap();assert!(!old.contains("code/library/baseline_use.dm"),"Update cannot add the actual new finding");request.mode=dq_analyze::native_baseline_update_wire::Mode::Seed;let seeded=host.update_native_baselines(request.clone(),&mut Vec::new(),&mut Vec::new()).unwrap();assert!(seeded.committed_files>0);let seed=fs::read_to_string(&path).unwrap();assert!(seed.contains("external_dependency\tcode/library/baseline_use.dm\t"),"same real native declaration/type provenance must produce a row: {seed}");request.mode=dq_analyze::native_baseline_update_wire::Mode::Update;host.update_native_baselines(request,&mut Vec::new(),&mut Vec::new()).unwrap();assert_eq!(fs::read_to_string(path).unwrap(),seed);}
 #[test]fn actual_native_baseline_migrate_keeps_unclaimed_sites_and_count_file_bytes_without_writing(){let(mut host,mut request,root,target,_)=fixture("baseline-mode-real-migrate");request.mode=dq_analyze::native_baseline_update_wire::Mode::Migrate;let selection=super::super::prepare_native_registered_check_selection(&[],super::super::FullRegistryCheckOptions::default(),host.source_arena_work()).unwrap();let count=selection.metadata().find_map(|m|match m.policy{Policy::Ceilings{baseline,..}=>Some(baseline),_=>None}).expect("actual registered count policy");let bytes=b"# preserved noncanonical comment\r\nold-count 7\r\n\r\n";put(&root,count,bytes);put(&root,"tools/ci/system_boundary_baseline.txt",bytes);let sites=fs::read(root.join(&target)).unwrap();let config=fs::read(root.join("tools/ci/lint_scopes.toml")).unwrap();drop(selection);let mut report=Vec::new();let result=using(&mut host,request,&mut report,&mut|event|{if matches!(event,Event::BeforeAttempt(_)){panic!("Migrate count/unchanged Sites must not reach any physical attempt")}Ok(())}).unwrap();assert_eq!(result.outcome.committed_files,0);assert_eq!(fs::read(root.join(target)).unwrap(),sites,"Migrate retains the unclaimed old Sites row");assert_eq!(fs::read(root.join(count)).unwrap(),bytes);assert_eq!(fs::read(root.join("tools/ci/system_boundary_baseline.txt")).unwrap(),bytes);assert_eq!(fs::read(root.join("tools/ci/lint_scopes.toml")).unwrap(),config);assert!(String::from_utf8(report).unwrap().contains("system_boundary: count ceilings have no rows to migrate"));}

 fn selected_fixture(label:&str,names:&[&str],overlay:&str,manifest:bool)->(BuildHost,Request,PathBuf){
  let root=fs::canonicalize(crate::test_scratch::dir(label)).unwrap();let cache=fs::canonicalize(crate::test_scratch::dir(&format!("{label}-cache"))).unwrap();
  put(&root,"code/probe.dm","/proc/probe()\n    return 0\n");put(&root,"tools/ci/lint_scopes.toml",fixture_configuration::with_overlay(overlay));
  if manifest{put(&root,"deepquarry.dme","#include \"code/probe.dm\"\n");}
  use crate::policy_request::{WorkspaceAuxiliaryQuestion as Q,WorkspacePolicyRequest,PolicyInputRequest,AnalysisContext};let roots=Q::authored_doc_ui_roots(Q::PRIVATE_FULL_REGISTRY).unwrap();
  let crate::request::Command::Build(build)=crate::cli::parse(&["prepare-query".into(),root.join("deepquarry.dme").to_string_lossy().into_owned()]).unwrap()else{panic!("actual preparation")};let mut build=*build;build.no_cache=true;build.exact_inputs=true;build.progress_enabled=false;build.workers=1;build.timeout_seconds=Some(60);build.engine_template=None;build.bootstrap_catalog=false;build.cache_root=Some(cache);build.policy_inputs=Some(PolicyInputRequest{analysis_context:Some(AnalysisContext::OriginalAnalyze0290),workspace:Some(WorkspacePolicyRequest{root:root.clone(),recursive_roots:roots.iter().map(|p|root.join(p)).collect(),configuration:root.join("tools/ci/lint_scopes.toml")}),..Default::default()});
  (BuildHost::default(),Request{build,mode:dq_analyze::native_baseline_update_wire::Mode::Update,no_gen:true,selectors:names.iter().map(|name|(*name).to_owned()).collect()},root)
 }
 #[test]fn actual_selected_source_baseline_without_dme_updates_only_captured_config_and_keeps_source_frame(){
  let(mut host,request,root)=selected_fixture("baseline-selected-dmless-source",&["scheduler"],"[lint.scheduler.ceilings]\nsleep = 7\n",false);put(&root,"tools/ci/library_layering_baseline.txt",[0xff,0,0x8e]);let mut report=Vec::new();
  let completed=using(&mut host,request,&mut report,&mut|event|{if let Event::BeforeAttempt(path)=event{assert_eq!(path,"tools/ci/lint_scopes.toml")}Ok(())}).unwrap();
  assert!(matches!(completed.frame,dq_analyze::full_registry_check_wire::CheckFrame::Source{..}));assert_eq!(completed.selected,1);assert!(completed.outcome.registered>completed.selected);assert_eq!(completed.outcome.committed_files,1);assert!(!root.join("deepquarry.dme").exists());assert!(fs::read_to_string(root.join("tools/ci/lint_scopes.toml")).unwrap().contains("sleep = 0"));assert_eq!(fs::read(root.join("tools/ci/library_layering_baseline.txt")).unwrap(),[0xff,0,0x8e]);let state=host.query_state.try_lock().unwrap();assert!(state.snapshot.is_none());assert!(state.handlers_snapshot.is_none());assert!(state.raw_snapshot.is_some());
 }
 #[test]fn actual_selected_handler_baseline_without_dme_uses_current_handler_ledger_and_config_target(){
  let(mut host,request,root)=selected_fixture("baseline-selected-dmless-handler",&["sem/handlers"],"[lint.\"sem/handlers\".ceilings]\ncontext_escape = 7\n",false);
  let completed=using(&mut host,request,&mut Vec::new(),&mut|_|Ok(())).unwrap();assert!(matches!(completed.frame,dq_analyze::full_registry_check_wire::CheckFrame::Handlers{full_source_revision:None,..}));assert_eq!(completed.selected,1);assert_eq!(completed.outcome.committed_files,1);assert!(!root.join("deepquarry.dme").exists());assert!(fs::read_to_string(root.join("tools/ci/lint_scopes.toml")).unwrap().contains("context_escape = 0"));let state=host.query_state.try_lock().unwrap();assert!(state.snapshot.is_none());assert!(state.handlers_snapshot.is_some());
 }
 #[test]fn actual_selected_source_handler_baseline_keeps_real_no_model_union_and_one_config_edit(){
  let(mut host,request,root)=selected_fixture("baseline-selected-dmless-union",&["scheduler","sem/handlers"],"[lint.scheduler.ceilings]\nsleep = 7\n[lint.\"sem/handlers\".ceilings]\ncontext_escape = 7\n",false);
  let completed=using(&mut host,request,&mut Vec::new(),&mut|_|Ok(())).unwrap();assert!(matches!(completed.frame,dq_analyze::full_registry_check_wire::CheckFrame::SourceHandlers{full_source_revision:None,full_semantic_revision:None,full_policy_revision:None,..}));assert_eq!(completed.selected,2);assert_eq!(completed.outcome.committed_files,1);let text=fs::read_to_string(root.join("tools/ci/lint_scopes.toml")).unwrap();assert!(text.contains("sleep = 0")&&text.contains("context_escape = 0"));assert!(!root.join("deepquarry.dme").exists());let state=host.query_state.try_lock().unwrap();assert!(state.snapshot.is_none());assert!(state.raw_snapshot.is_some()&&state.handlers_snapshot.is_some());
 }
 #[test]fn actual_selected_model_baseline_seeds_real_library_site_and_creates_only_registered_absent_target(){
  let(mut host,mut request,root)=selected_fixture("baseline-selected-model-seed",&["library_layering"],"",true);request.mode=dq_analyze::native_baseline_update_wire::Mode::Seed;
  put(&root,"code/content/baseline_target.dm","/datum/content_target\n");put(&root,"code/library/baseline_use.dm","/datum/library_probe\n    var/datum/content_target/target\n");put(&root,"deepquarry.dme","#include \"code/probe.dm\"\n#include \"code/content/baseline_target.dm\"\n#include \"code/library/baseline_use.dm\"\n");assert!(!root.join("tools/ci/library_layering_baseline.txt").exists());
  let completed=using(&mut host,request,&mut Vec::new(),&mut|event|{if let Event::BeforeAttempt(path)=event{assert_eq!(path,"tools/ci/library_layering_baseline.txt")}Ok(())}).unwrap();assert!(matches!(completed.frame,dq_analyze::full_registry_check_wire::CheckFrame::Model{..}));assert_eq!(completed.selected,1);assert_eq!(completed.outcome.committed_files,1);assert!(fs::read_to_string(root.join("tools/ci/library_layering_baseline.txt")).unwrap().contains("external_dependency\tcode/library/baseline_use.dm\t"));let state=host.query_state.try_lock().unwrap();assert!(state.snapshot.is_some());assert!(state.handlers_snapshot.is_none());
 }
 #[test]fn actual_selected_engine_baseline_preserves_conditional_source_or_model_frame(){
  for model in[false,true]{let(mut host,request,root)=selected_fixture(if model{"baseline-selected-engine-model"}else{"baseline-selected-engine-empty"},&["engine_layering"],"[lint.engine_layering.ceilings]\nexternal_dependency = 7\n",model);if model{put(&root,"code/engine/owned.dm","/datum/engine_probe\n    var/value = 1\n");put(&root,"deepquarry.dme","#include \"code/probe.dm\"\n#include \"code/engine/owned.dm\"\n");}let completed=using(&mut host,request,&mut Vec::new(),&mut|_|Ok(())).unwrap();assert_eq!(matches!(completed.frame,dq_analyze::full_registry_check_wire::CheckFrame::Model{..}),model);assert_eq!(matches!(completed.frame,dq_analyze::full_registry_check_wire::CheckFrame::Source{..}),!model);assert_eq!(completed.outcome.committed_files,1);assert!(fs::read_to_string(root.join("tools/ci/lint_scopes.toml")).unwrap().contains("external_dependency = 0"));}
 }
 #[test]fn actual_selected_baseline_first_io_and_real_pressure_preserve_config_then_same_host_recovers(){
  let(mut host,request,root)=selected_fixture("baseline-selected-first-io-pressure",&["scheduler"],"[lint.scheduler.ceilings]\nsleep = 7\n",false);let before=fs::read(root.join("tools/ci/lint_scopes.toml")).unwrap();let error=using(&mut host,request.clone(),&mut Vec::new(),&mut|event|if matches!(event,Event::Physical(crate::native_author_fix_transaction::Event::AfterTruncate)){Err(io::Error::from_raw_os_error(1450))}else{Ok(())}).err().unwrap();assert_eq!(actual_io(error.as_ref()),Some(1450));let mutation=error.source().unwrap().downcast_ref::<crate::native_fix::FailedMutation>().expect("actual attempted-writer failure");assert!(mutation.may_have_changed);assert!(mutation.recovered,"actual same-host selected source reprepare must finish before first IO escapes");put(&root,"tools/ci/lint_scopes.toml",&before);host.clear_regions();let pressure=host.source_arena_work().reserve(128*1024*1024-512*1024).unwrap();let error=host.update_native_baselines(request.clone(),&mut Vec::new(),&mut Vec::new()).unwrap_err();let mut at=error.as_ref();let mut oom=false;loop{if at.downcast_ref::<io::Error>().is_some_and(|e|e.kind()==io::ErrorKind::OutOfMemory){oom=true;break}match at.source(){Some(next)=>at=next,None=>break}}assert!(oom,"{error}");assert_eq!(fs::read(root.join("tools/ci/lint_scopes.toml")).unwrap(),before);drop(pressure);let result=host.update_native_baselines(request,&mut Vec::new(),&mut Vec::new()).unwrap();assert_eq!(result.committed_files,1);
 }
 #[test]fn actual_selected_baseline_rechecks_real_gen_physical_domain_before_any_baseline_write(){
  let(mut host,mut request,root,_,_)=fixture("baseline-selected-real-gen-domain");request.selectors=vec!["scheduler".into()];request.no_gen=false;put(&root,"tools/ci/lint_scopes.toml",fixture_configuration::with_overlay("[lint.scheduler.ceilings]\nsleep = 7\n"));let before=fs::read(root.join("tools/ci/lint_scopes.toml")).unwrap();let mut after_gen=0;
  let error=using(&mut host,request.clone(),&mut Vec::new(),&mut|event|{match event{Event::AfterGeneration=>{after_gen+=1;put(&root,"code/probe.dm","/proc/probe()\n    return 1\n");},Event::BeforeAttempt(_)=>panic!("changed GEN input cannot reach baseline writer"),_=>{}}Ok(())}).err().unwrap();assert_eq!(after_gen,1);assert_eq!(fs::read(root.join("tools/ci/lint_scopes.toml")).unwrap(),before);assert!(error.to_string().contains("input")||error.to_string().contains("changed"),"{error}");let completed=using(&mut host,request,&mut Vec::new(),&mut|_|Ok(())).unwrap();assert!(matches!(completed.frame,dq_analyze::full_registry_check_wire::CheckFrame::Source{..}));assert_eq!(completed.outcome.committed_files,1);
 }

}

impl Builder{
 pub(super) fn observe_handler(&mut self,meta:&Meta,scope:&LintScope,rows:BaselineProjectionRows<'_>,loan:&crate::request_runner::native_check_handlers::BaselineConfiguration<'_>)->io::Result<()>{
  if meta.name!="sem/handlers"||!matches!(meta.policy,Policy::Hard)||!super::query_snapshot::SourceSnapshot::is_registered_baseline_metadata(meta){return Err(io::Error::new(io::ErrorKind::InvalidInput,"Handler baseline callback has another canonical producer policy"))}
  let allocation=Arc::clone(&self._allocation);self.observe_using_target(meta,scope,rows,&mut|meta|{if meta.is_some(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"Handler hard policy has no baseline target"))}super::workspace_capture::owned_handler_baseline_configuration(loan,&allocation)})
 }
 pub(super) fn observe_engine(&mut self,meta:&Meta,scope:&LintScope,rows:BaselineProjectionRows<'_>,plan:&Arc<super::NativeCheckSelection>,capture:&Arc<WorkspaceCapture>,guard:&NativeReadGuard<'_>)->io::Result<()>{
  if !std::ptr::eq(meta,dq_analyze::engine_layering_policy::Layer::Engine.metadata())||!matches!(meta.policy,Policy::Hard){return Err(io::Error::new(io::ErrorKind::InvalidInput,"Engine baseline callback has another canonical producer policy"))}
  let allocation=Arc::clone(&self._allocation);self.observe_using_target(meta,scope,rows,&mut|meta|{if meta.is_some(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"Engine hard policy has no baseline target"))}capture.owned_engine_baseline_configuration(guard,plan,&allocation)})
 }
}

/// Output DATA preview of the ordinary registered baseline planner. This does
/// not commit a baseline or run a second lint/policy implementation.
pub(crate) struct ParityPreview{pub(crate) project:std::path::PathBuf,pub(crate) inputs:super::full_registry_check::FullRegistryCheckInputs,pub(crate) frame:dq_analyze::full_registry_check_wire::CheckFrame,plan:Builder}
impl ParityPreview{
 pub(crate) fn require_current(&self)->Result<(),Box<dyn Error>>{self.inputs.require_report_current(&self.project)}
 /// Borrow only already-admitted exact target and desired bytes. Source reads
 /// remain owned by the authentic selected ledger; output paths grant no I/O.
 pub(crate) fn visit_edits(&self,visit:&mut dyn FnMut(&str,&[u8],&[u8])->io::Result<()>)->io::Result<()>{
  for edit in &self.plan.edits{crate::daemon::control::checkpoint()?;visit(edit.target.relative(),edit.target.preimage(),edit.desired.as_bytes())?;}Ok(())
 }
 /// Fixed output proof is borrowed only from this SAME genuine planner.
 pub(crate) fn visit_targets(&self,visit:&mut dyn FnMut(&BaselineTarget,&[u8])->io::Result<()>)->io::Result<()>{for edit in &self.plan.edits{crate::daemon::control::checkpoint()?;visit(&edit.target,edit.desired.as_bytes())?;}Ok(())}
 pub(crate) fn into_inputs(self)->(std::path::PathBuf,super::full_registry_check::FullRegistryCheckInputs,dq_analyze::full_registry_check_wire::CheckFrame){let Self{project,inputs,frame,plan}=self;drop(plan);(project,inputs,frame)}
 pub(crate) fn write_notes(&self,out:&mut dyn Write)->io::Result<()>{out.write_all(self.plan.notes.as_bytes())}
}
pub(crate) fn parity_preview(mut build:crate::request::BuildRequest,selectors:&[String],mode:dq_analyze::native_baseline_update_wire::Mode,host:&mut BuildHost)->Result<ParityPreview,Box<dyn Error>>{
 // No GEN and no original-project mutation. The reference sees an owned source
 // clone with these SAME captured inputs; real authoring stays untouched.
 // Utility envelope authenticates its SemReads entry shape first. The real
 // baseline selection derives its own complete registered question profile.
 if let Some(policy)=build.policy_inputs.as_mut(){policy.workspace_auxiliary.clear();}
 let request=Request{build,mode,no_gen:true,selectors:Vec::new()};request.qualify()?;
 super::full_registry_check::with_full_registry_check_context(request.build.command,request.build.timeout_seconds,||{
  let selection=baseline_selection(host,selectors,mode)?;
  let project=crate::policy_request::canonical_analysis_project(&request.build.project,Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290))?;
  let(inputs,frame,mut plan)=host.stage_registered_baseline_plan(request.build,selection,None)?;
  inputs.require_report_current(&project)?;
  // Unlike authoring, parity retains no-op targets too: the independent old
  // implementation may legitimately rewrite identical bytes on these files.
  if plan.observed==0{return Err(io::Error::new(io::ErrorKind::InvalidData,"parity baseline plan has no completed producer").into())}
  if let Some(config)=plan.config.take(){plan.add(config)?;}plan._allocation.settle_retained(host.source_arena_work())?;
  let result=ParityPreview{project,inputs,frame,plan};result.require_current()?;Ok(result)
 })
}

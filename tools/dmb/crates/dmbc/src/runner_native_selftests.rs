//! Actual callback dispatch on the existing selected-producer catalog.
//! No fixture result grants source/model/report completion or a reusable cache.
use super::{BuildHost,NativeCheckSelection,full_registry_check::{NativeSelftestWork,NativeFixtureMessage}};
use std::{io,error::Error,path::Path,sync::Arc};
use dq_analyze::{derived_selftest_policy::{Failure,NativeAssertions},captured_generator_budget::Budget,lint::{Lint,Meta}};
use dm_preprocess::source_arena_credit::{SourceArenaCredit,SourceArenaWork};

#[derive(Clone,Copy)]enum Callback{Registered,Derived,Ui,Tracked,Sys(dq_analyze::sys_selftest_policy::Kind),Reactive,CheckGrep,Pool,Inherited}
fn descriptor(meta:&'static Meta)->io::Result<Callback>{
 if let Some(actual)=dq_analyze::captured_raw_policy::metadata(meta.name){
  if !std::ptr::eq(actual,meta){return Err(io::Error::new(io::ErrorKind::InvalidData,"selftest native registration metadata differs from its selected producer"))}
  return Ok(Callback::Registered)
 }
 Ok(match meta.name{
  "derived_reads"=>Callback::Derived,"ui_actions"=>Callback::Ui,"tracked"|"tracked_tests"=>Callback::Tracked,"sys/dx_reactive"=>Callback::Reactive,"check_grep"=>Callback::CheckGrep,"pool"=>Callback::Pool,
  "sys/dx_constructor_shadow"=>Callback::Sys(dq_analyze::sys_selftest_policy::Kind::Constructor),"sys/dx_look_side_effects"=>Callback::Sys(dq_analyze::sys_selftest_policy::Kind::Look),"sys/dx_manual_fingerprint_log"=>Callback::Sys(dq_analyze::sys_selftest_policy::Kind::ManualLog),"sys/dx_string_names"=>Callback::Sys(dq_analyze::sys_selftest_policy::Kind::StringNames),
  // These actual legacy classes do not override Lint::selftest (Sys entries
  // have module.selftest=None). Invoke the existing inherited method below;
  // unknown/new producers refuse until their callback has been source-audited.
  "allow_annotations"|"map_edits"|"image_dir_after_build"|"silicon_entry"|"sem/keys"|"sys/hygiene"|"sys/resolvers"|"sys/tables"|"system_boundary"|"sem/handlers"|"sem/reads"|"untracked_inputs"|"setter_publishes"|"decl"|"init"|"base_vars"|"requirement_bool"|"player_link"|"untyped_member"|"weak_raw_read"|"rel_write_undeclared"|"untyped"|"stored_refs"|"engine_layering"|"library_layering"|"lifeforms"|"op_order"|"ownership"|"notice_publisher"|"report_in_catch"|"sys/sfx"|"sys/requirements"|"sys/expiry"|"doc_snippets"|"sys/ui"|"state_schema"|"lifecycle"|"sys/loot"|"instance_list"|"cache"|"sys/dx_ownership_forms"|"api"|"sys/fields"|"sys/appearance"=>Callback::Inherited,
  _=>return Err(io::Error::new(io::ErrorKind::Unsupported,"selected native producer has no reviewed ordinary selftest callback")),
 })
}
struct Inherited(&'static Meta);
impl Lint for Inherited{fn meta(&self)->&Meta{self.0}}
fn operational(actual:Box<dyn Error>)->Failure{Failure::Operational(match actual.downcast::<io::Error>(){Ok(actual)=>*actual,Err(other)=>io::Error::other(other.to_string())})}
fn outcome(message:NativeFixtureMessage,work:&NativeSelftestWork<'_>)->Result<String,Failure>{message.take_for_catalog(work).map_err(Failure::Operational)?.map_err(Failure::Assertion)}

impl BuildHost{
 pub(super) fn run_native_selected_selftests(
  &mut self,plan:&NativeCheckSelection,cache:&Path,live:crate::input_snapshot::NativeSelftestInputs<'_>,credit:&SourceArenaCredit,budget:&Arc<Budget>,patterns_db:&crate::query_db::QueryDb,
 )->Result<dq_analyze::captured_raw_policy::RawSelftestResult,Box<dyn Error>>{
  self.run_native_selected_selftests_mode(plan,cache,live,credit,budget,false,patterns_db)
 }
 pub(super) fn run_native_selected_selftests_mode(
  &mut self,plan:&NativeCheckSelection,cache:&Path,live:crate::input_snapshot::NativeSelftestInputs<'_>,credit:&SourceArenaCredit,budget:&Arc<Budget>,retain_successes:bool,patterns_db:&crate::query_db::QueryDb,
 )->Result<dq_analyze::captured_raw_policy::RawSelftestResult,Box<dyn Error>>{
  crate::daemon::control::checkpoint()?;
  if crate::daemon::control::WorkerContext::capture_for_checkpoints().is_none(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"native callbacks require the original active request context").into())}
  let count=plan.names().len();
  let upper=count.checked_mul(4).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;
  budget.charge(upper.checked_mul(std::mem::size_of::<&'static Meta>()).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?).map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))?;
  let mut metas=Vec::new();metas.try_reserve_exact(count).map_err(|_|io::Error::from(io::ErrorKind::OutOfMemory))?;
  if metas.capacity()>upper{return Err(io::Error::new(io::ErrorKind::OutOfMemory,"native callback roster exceeds its admitted physical capacity").into())}
  for meta in plan.metadata(){crate::daemon::control::checkpoint()?;descriptor(meta)?;metas.push(meta)}
  let result=dq_analyze::captured_raw_policy::run_native_selftest_catalog_mode(&metas,budget,&crate::daemon::control::checkpoint,retain_successes,|meta,local|{
   let work=NativeSelftestWork::new(credit,local).map_err(Failure::Operational)?;
   let mut keep=NativeAssertions{budget:local,poll:&crate::daemon::control::checkpoint};
   let mut temp=NativeAssertions{budget:local,poll:&crate::daemon::control::checkpoint};
   match descriptor(meta).map_err(Failure::Operational)?{
    Callback::Registered=>dq_analyze::captured_raw_policy::registered_selftest_funded_with_patterns(meta.name,local,&crate::daemon::control::checkpoint,&crate::query_db::PatternProvider::new(patterns_db,patterns_db)).ok_or_else(||Failure::Operational(io::Error::new(io::ErrorKind::InvalidData,"actual native callback registration disappeared")))?,
    Callback::Derived=>outcome(self.run_native_derived_fixture_selftest_using(cache,&work).map_err(operational)?,&work),
    Callback::Ui=>outcome(self.run_native_ui_fixture_selftest_using(cache,live.dispatcher(),&work).map_err(operational)?,&work),
    Callback::Reactive=>outcome(self.run_native_sys_reactive_fixture_selftest_using(cache,&work).map_err(operational)?,&work),
    Callback::Tracked=>dq_analyze::tracked_selftest_policy::run(&mut keep,&mut temp),
    Callback::Sys(kind)=>dq_analyze::sys_selftest_policy::run(kind,&mut keep,&mut temp),
    Callback::Pool=>dq_analyze::pool_selftest_policy::run(local,&crate::daemon::control::checkpoint),
    Callback::CheckGrep=>dq_analyze::lints::check_grep::selftest_policy::run_native(live.ignore(),local,&crate::daemon::control::checkpoint),
    Callback::Inherited=>Lint::selftest(&Inherited(meta)).map_err(Failure::Assertion),
   }
  }).map_err(|failure|match failure{Failure::Operational(actual)=>actual,Failure::Assertion(message)=>io::Error::other(message)})?;
  if !result.matches_names(plan.names())||result.completed()!=count{return Err(io::Error::new(io::ErrorKind::InvalidData,"native callback result differs from the actual selected producer order").into())}
  Ok(result)
 }
}

#[cfg(test)]mod controls{
 use super::*;
 #[test]fn every_actual_registered_producer_has_an_explicit_native_callback_before_execution(){let host=BuildHost::default();let plan=super::super::prepare_native_registered_check_selection(&[],super::super::FullRegistryCheckOptions::default(),host.source_arena_work()).unwrap();assert!(plan.names().len()<=999,"actual catalog count exceeds the separately tested three-digit callback terminal width");for meta in plan.metadata(){descriptor(meta).unwrap();}}
 #[test]fn native_catalog_keeps_exact_assertion_names_and_first_operational_failure(){let a=dq_analyze::captured_raw_policy::metadata("scheduler").unwrap();let b=dq_analyze::captured_raw_policy::metadata("entry_slots").unwrap();let budget=Budget::new(dq_analyze::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES).unwrap();let calls=std::cell::Cell::new(0);let actual=dq_analyze::captured_raw_policy::run_native_selftest_catalog(&[a,b],&budget,&||Ok(()),|meta,_|{calls.set(calls.get()+1);Err(Failure::Assertion(meta.name.to_owned()))}).unwrap();assert_eq!(calls.get(),2);assert_eq!(actual.failures().collect::<Vec<_>>(),[(a.name,a.name),(b.name,b.name)]);let budget=Budget::new(dq_analyze::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES).unwrap();let error=dq_analyze::captured_raw_policy::run_native_selftest_catalog(&[a,b],&budget,&||Ok(()),|_,_|Err(Failure::Operational(io::Error::from_raw_os_error(1450)))).err().unwrap();assert!(matches!(error,Failure::Operational(actual)if actual.raw_os_error()==Some(1450)));}
}

/// Request DATA only. The parent recorder, not this path, issues input facts.
pub(crate) struct NativeSelftestRequest{caller:Option<std::path::PathBuf>}
impl NativeSelftestRequest{pub(crate) fn new(caller:Option<std::path::PathBuf>)->Self{Self{caller}}pub(crate) fn caller(&self)->Option<&Path>{self.caller.as_deref()}}
/// Per-attempt actual result; drops on retry and cannot mint a completed wire
/// receipt until the SAME final recorder issuer has been authenticated.
pub(crate) struct NativeSelftestPending{
 actual:dq_analyze::captured_raw_policy::RawSelftestResult,
 budget:Arc<Budget>,epoch:Option<crate::input_snapshot::JoinedReportEpoch>,
 lender:Arc<crate::query_db::QueryDb>,credit:SourceArenaCredit,
}
impl NativeSelftestPending{
 pub(crate) fn finish(self,plan:&NativeCheckSelection,final_epoch:&crate::input_snapshot::JoinedReportEpoch)->io::Result<()>{
  if self.epoch.as_ref().is_some_and(|epoch|!epoch.same_recorder(final_epoch)){return Err(io::Error::new(io::ErrorKind::InvalidInput,"native selftest inputs belong to another preparation recorder"))}
  plan.install_native_selftests(self.actual,self.credit,&self.budget,self.lender.as_ref())
 }
}
impl BuildHost{
 pub(crate) fn prepare_native_selftests<P:crate::input_snapshot::SnapshotProvider>(
  &mut self,plan:&NativeCheckSelection,recording:&crate::input_snapshot::RecordingInputs<P>,cache:&Path,workspace_root:&Path,
 )->Result<NativeSelftestPending,Box<dyn Error>>{
  self.prepare_native_selftests_mode(plan,recording,cache,workspace_root,false)
 }
 pub(crate) fn prepare_native_selftests_mode<P:crate::input_snapshot::SnapshotProvider>(
  &mut self,plan:&NativeCheckSelection,recording:&crate::input_snapshot::RecordingInputs<P>,cache:&Path,workspace_root:&Path,retain_successes:bool,
 )->Result<NativeSelftestPending,Box<dyn Error>>{
  let request=plan.selftest_request().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"native callback preparation was not requested"))?;
  if crate::daemon::control::WorkerContext::capture_for_checkpoints().is_none(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"native callback capture requires the original active request context").into())}
  crate::daemon::control::checkpoint()?;
  let lender=Arc::clone(self.query_db());
  let credit=lender.reserve(dq_analyze::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES)?;
  let budget=Budget::new(dq_analyze::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES).map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))?;
  let candidates=lender.with_native_selftest_input_resources(&budget,|resources|recording.capture_native_selftest_candidates(plan,request.caller(),workspace_root,&budget,lender.as_ref(),resources))?;
  // The input-family gate and temporary lender have BOTH ended before nested
  // fixture preparations switch the host's genuine engine/query variant.
  let(actual,epoch)=recording.with_native_selftest_inputs(&candidates,|live|self.run_native_selected_selftests_mode(plan,cache,live,&credit,&budget,retain_successes,lender.as_ref()))?;
  drop(candidates);
  if request.caller().is_some()&&epoch.is_none(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"selected live callback inputs did not issue an actual parent-recorder epoch").into())}
  Ok(NativeSelftestPending{actual,budget,epoch,lender,credit})
 }
}

#[cfg(test)]mod funded_raw_fixture_credit_controls{
 use super::*;
 #[test]fn actual_query_db_callback_grant_funds_checked_raw_sources_then_refunds(){
  let host=BuildHost::default();
  let before=host.query_db().source_input_admission_bytes().unwrap();
  let credit=host.source_arena_work().reserve(dq_analyze::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES).unwrap();
  let during=host.query_db().source_input_admission_bytes().unwrap();
  assert!(during>=before+dq_analyze::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES);
  let budget=Budget::new(dq_analyze::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES).unwrap();
  let work=NativeSelftestWork::new(&credit,&budget).unwrap();
  let actual=dq_analyze::captured_raw_policy::registered_selftest_funded("dcs",work.budget(),&||Ok(())).unwrap().unwrap();
  assert!(budget.used()<=credit.reserved_bytes());
  drop(actual);drop(work);drop(budget);drop(credit);
  let after=host.query_db().source_input_admission_bytes().unwrap();
  assert!(after+dq_analyze::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES<=during,"actual released source grant must not remain retained by fixture DATA");
 }
}

impl NativeSelftestPending{
 pub(super) fn finish_standalone<P:crate::input_snapshot::SnapshotProvider>(self,plan:&NativeCheckSelection,recording:crate::input_snapshot::RecordingInputs<P>)->Result<crate::input_snapshot::InputSnapshot,Box<dyn Error>>{
  let require=crate::request_runner::runner_freshness::require_native_callback_inputs_current;
  let inputs=if self.epoch.is_some(){let(_,final_epoch)=recording.with_joined_report_snapshot(require)?;if self.epoch.as_ref().is_some_and(|prior|!prior.same_recorder(&final_epoch)){return Err(io::Error::new(io::ErrorKind::InvalidInput,"standalone callback final issuer differs").into())}recording.into_joined_report_snapshot(&final_epoch)?}else{recording.into_snapshot()?};
  require(&inputs)?;crate::daemon::control::checkpoint()?;
  plan.install_native_selftests(self.actual,self.credit,&self.budget,self.lender.as_ref())?;
  Ok(inputs)
 }
}

//! Actual scratch ownership; immutable image payloads are written by borrow.
//! Parsed configuration/source facts retain their existing preparation ledger.
use super::*;
use std::{path::{Path,PathBuf,Component},sync::{Arc,atomic::{AtomicUsize,Ordering}}};
use dq_analyze::captured_generator_budget::Budget;

pub(super) struct Resources{
 budget:Arc<Budget>,guard_peak:AtomicUsize,
 // Last: paths/guards and the child Budget disappear before the physical loan.
 _credit:dm_preprocess::source_arena_credit::SourceArenaControlCredit,
}

#[cfg(test)]mod controls{
 use super::*;
 use dm_preprocess::source_arena_credit::SourceArenaWork;
 #[test]fn actual_static_configuration_write_uses_real_scratch_rows_and_refunds_the_same_scoped_budget(){
  let cache=crate::test_scratch::dir("native-static-fixture-admission");let host=BuildHost::default();
  let credit=host.source_arena_work().reserve(dq_analyze::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES).unwrap();
  let budget=Budget::new(dq_analyze::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES).unwrap();let work=NativeSelftestWork::new(&credit,&budget).unwrap();
  with_full_registry_check_context(crate::request::BuildCommand::PrepareQuery,Some(120),||{
   let before=budget.used();{
    let mut scratch=NativeFixtureSources::new_using(&cache,&work)?;
    let bytes=include_bytes!("../../../../ci/lint_scopes.toml");
    assert!(bytes.len().checked_mul(64).unwrap()>dq_analyze::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES,"the actual original false-denial witness must remain real");
    scratch.put("tools/ci/lint_scopes.toml",bytes)?;
    assert_eq!(std::fs::metadata(scratch.root().join("tools/ci/lint_scopes.toml"))?.len(),bytes.len()as u64);
    let request=scratch.query_request_using(&cache)?;
    assert_eq!(request.command,crate::request::BuildCommand::PrepareQuery);assert_eq!(request.workers,1);
    assert_eq!(request.policy_inputs.as_ref().unwrap().workspace.as_ref().unwrap().configuration,scratch.root().join("tools/ci/lint_scopes.toml"));
    assert!(budget.used()<dq_analyze::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES);
    drop(request);scratch.remove()?;
   }
   assert_eq!(budget.used(),before+std::mem::size_of::<Budget>()+2*std::mem::size_of::<usize>(),"scratch payload refunds; the existing child-Budget policy retains fixed metadata");Ok(())
  }).unwrap();
 }
 #[test]fn actual_scratch_admission_denies_before_creation_and_a_fresh_same_host_loan_recovers(){
  let cache=crate::test_scratch::dir("native-static-fixture-denial");let host=BuildHost::default();
  with_full_registry_check_context(crate::request::BuildCommand::PrepareQuery,Some(120),||{
   let before=std::fs::read_dir(&cache)?.count();
   let credit=host.source_arena_work().reserve(1024)?;let budget=Budget::new(1024).map_err(io::Error::other)?;let work=NativeSelftestWork::new(&credit,&budget)?;
   let charged=budget.used();let error=NativeFixtureSources::new_using(&cache,&work).err().expect("real guard backing must exceed the actual small grant");
   assert_eq!(error.kind(),io::ErrorKind::OutOfMemory);assert_eq!(std::fs::read_dir(&cache)?.count(),before);assert_eq!(budget.used(),charged+std::mem::size_of::<Budget>()+2*std::mem::size_of::<usize>());drop(credit);drop(budget);
   let credit=host.source_arena_work().reserve(dq_analyze::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES)?;
   let budget=Budget::new(dq_analyze::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES).map_err(io::Error::other)?;let work=NativeSelftestWork::new(&credit,&budget)?;
   let mut scratch=NativeFixtureSources::new_using(&cache,&work)?;scratch.put("code/fixture.dm",b"/datum/native_fixture\n")?;scratch.remove()?;drop(scratch);
   assert_eq!(std::fs::read_dir(&cache)?.count(),before);Ok(())
  }).unwrap();
 }
}
fn oom(message:String)->io::Error{io::Error::new(io::ErrorKind::OutOfMemory,message)}
impl Resources{
 fn new(work:&NativeSelftestWork<'_>)->io::Result<Self>{
  let budget=Budget::scoped_temporaries(work.budget()).map_err(oom)?;
  budget.charge(std::mem::size_of::<Resources>()+std::mem::size_of::<NativeFixtureSources>()).map_err(oom)?;
  Ok(Self{budget,guard_peak:AtomicUsize::new(0),_credit:work._credit.control()})
 }
 fn charge(&self,bytes:Option<usize>)->io::Result<()>{self.budget.charge(bytes.ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?).map_err(oom)}
 fn guard(&self,path:&Path,root:&Path)->io::Result<()>{
  let need=crate::frozen_inputs::generation_publication_guard_charge(path,root)?;
  let before=self.guard_peak.load(Ordering::Acquire);
  if need>before{self.budget.charge(need-before).map_err(oom)?;self.guard_peak.store(need,Ordering::Release)}Ok(())
 }
 fn guard_paid(&self,path:&Path,root:&Path)->io::Result<()>{
  if crate::frozen_inputs::generation_publication_guard_charge(path,root)?>self.guard_peak.load(Ordering::Acquire){return Err(io::Error::new(io::ErrorKind::InvalidData,"fixture cleanup guard exceeds its actual already-paid source paths"))}Ok(())
 }
 fn owned(&self,path:&Path)->io::Result<PathBuf>{self.charge(path.as_os_str().len().checked_add(64))?;Ok(path.to_path_buf())}
 fn joined(&self,parent:&Path,relative:&Path)->io::Result<PathBuf>{
  let need=parent.as_os_str().len().checked_add(relative.as_os_str().len()).and_then(|n|n.checked_add(1)).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;
  self.charge(need.checked_add(64))?;let mut path=PathBuf::with_capacity(need);path.push(parent);path.push(relative);
  if path.capacity()>need{return Err(io::Error::new(io::ErrorKind::OutOfMemory,"fixture path backing exceeds its admitted exact capacity"))}Ok(path)
 }
 fn rows<T>(&self,rows:&mut Vec<T>,additional:usize)->io::Result<()>{
  let need=rows.len().checked_add(additional).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;
  if need<=rows.capacity(){return Ok(())}
  let next=need.max(rows.capacity().checked_mul(2).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?).max(4);
  self.charge(next.checked_mul(std::mem::size_of::<T>()).and_then(|n|n.checked_add(64)))?;
  rows.try_reserve_exact(next-rows.len()).map_err(|_|io::Error::from(io::ErrorKind::OutOfMemory))?;
  if rows.capacity()>next{return Err(io::Error::new(io::ErrorKind::OutOfMemory,"fixture row backing exceeds its actual admitted capacity"))}Ok(())
 }
}

impl NativeFixtureSources{
 /// Caller supplies the existing admitted absolute cache namespace, rather
 /// than asking the fixture command parser to perform a second ambient lookup.
 pub(in crate::runner_host) fn new_using(cache:&Path,work:&NativeSelftestWork<'_>)->io::Result<Self>{
  if crate::daemon::control::WorkerContext::capture_for_checkpoints().is_none(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"fixture scratch requires its original active request context"))}
  if !cache.is_absolute(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"native fixture cache must be the actual admitted absolute cache"))}
  let resources=Resources::new(work)?;
  // Existing source-free guard preflight covers the real held ancestor
  // roster/path conversions. This persistent guard is distinct from the
  // two-owner temporary high-water slot below.
  resources.budget.charge(crate::frozen_inputs::generation_publication_guard_charge(cache,cache)?).map_err(oom)?;
  let parent=resources.owned(cache)?;
  let guard=crate::frozen_inputs::generation_ancestor_guard(&parent,&parent)?;
  for _ in 0..16{
   crate::daemon::control::checkpoint()?;
   let mut control=dq_analyze::derived_selftest_policy::NativeAssertions{budget:&resources.budget,poll:&crate::daemon::control::checkpoint};
   let name=dq_analyze::key_policy_control::format(&mut control,format_args!("native-selftest-{}-{}",std::process::id(),native_fixture_next_id())).map_err(|failure|match failure{dq_analyze::derived_selftest_policy::Failure::Operational(actual)=>actual,dq_analyze::derived_selftest_policy::Failure::Assertion(message)=>io::Error::other(message)})?;
   let root=resources.joined(&parent,Path::new(&name))?;resources.guard(&root,&parent)?;
   match std::fs::create_dir(&root){
    Ok(())=>{let identity=crate::frozen_inputs::generation_directory_identity(&root,&parent)?;return Ok(Self{root,parent,identity,files:Vec::new(),directories:Vec::new(),_parent:guard,_resource:Some(resources)})},
    Err(actual)if actual.kind()==io::ErrorKind::AlreadyExists=>continue,Err(actual)=>return Err(actual),
   }
  }
  Err(io::Error::new(io::ErrorKind::AlreadyExists,"native fixture source namespace exhausted"))
 }
 pub(super) fn current_admitted(&self)->io::Result<()>{
  let resources=self._resource.as_ref().expect("actual scratch resource owner");
  resources.guard(&self.root,&self.parent)?;self.current_unadmitted()
 }
 pub(super) fn put_admitted(&mut self,relative:&str,bytes:&[u8])->io::Result<()>{
  self.current_admitted()?;crate::daemon::control::checkpoint()?;
  let relative=Path::new(relative);
  if relative.as_os_str().is_empty()||relative.components().any(|part|!matches!(part,Component::Normal(_))){return Err(io::Error::new(io::ErrorKind::InvalidInput,"native fixture path must be a normal owned relative path"))}
  let resources=self._resource.as_ref().expect("actual scratch resource owner");resources.budget.require().map_err(oom)?;
  let full=resources.joined(&self.root,relative)?;resources.guard(&full,&self.root)?;
  let components=relative.components().count();
  // The unchanged writer collects borrowed Components and grows one mutable
  // directory path. Geometric Vec/OsString growth has total new backing at
  // most four times its real final row/byte extent (including old+new overlap).
  resources.charge(components.max(4).checked_mul(4).and_then(|n|n.checked_mul(std::mem::size_of::<Component<'_>>())).and_then(|n|n.checked_add(64)))?;
  resources.charge(self.root.as_os_str().len().checked_add(64))?;
  resources.charge(full.as_os_str().len().checked_mul(4).and_then(|n|n.checked_add(128)))?;
  resources.charge(full.as_os_str().len().checked_add(64))?;
  let mut width=self.root.as_os_str().len();
  for part in relative.parent().unwrap_or_else(||Path::new("")).components(){width=width.checked_add(part.as_os_str().len()).and_then(|n|n.checked_add(1)).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;resources.charge(width.checked_add(64))?;}
  resources.rows(&mut self.directories,components.saturating_sub(1))?;
  resources.rows(&mut self.files,1)?;
  // Payload is a borrow. No source/config bytes are cloned by write_all.
  self.put_unadmitted(relative.to_str().expect("fixture relative path came from str"),bytes)
 }
 pub(super) fn remove_admitted(&mut self)->io::Result<()>{
  let resources=self._resource.as_ref().expect("actual scratch resource owner");
  resources.guard_paid(&self.root,&self.parent)?;
  for(path,_)in &self.files{resources.guard_paid(path.parent().unwrap(),&self.root)?;}
  for(path,_)in &self.directories{resources.guard_paid(path,&self.root)?;}
  // No new reservation or checkpoint after a prior allocation/IO failure:
  // all cleanup guards reuse the actual already-paid high-water backing.
  self.remove_unadmitted()
 }
 pub(in crate::runner_host) fn query_request_using(&self,cache:&Path)->io::Result<crate::request::BuildRequest>{
  use crate::policy_request::{PolicyInputRequest,WorkspacePolicyRequest,WorkspaceAuxiliaryQuestion as Q,AnalysisContext};
  let resource=self._resource.as_ref().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"fixture request needs its actual scratch resource owner"))?;
  resource.budget.require().map_err(oom)?;crate::daemon::control::checkpoint()?;
  let directories=Q::authored_doc_ui_roots(Q::PRIVATE_FULL_REGISTRY).ok_or_else(||io::Error::other("actual native registry fixture roots absent"))?;
  let root=resource.owned(self.root())?;let project=resource.joined(&root,Path::new("deepquarry.dme"))?;
  let configuration=resource.joined(&root,Path::new("tools/ci/lint_scopes.toml"))?;
  let mut recursive_roots=Vec::new();resource.rows(&mut recursive_roots,directories.len())?;
  for directory in directories{recursive_roots.push(resource.joined(&root,Path::new(directory))?);}
  Ok(crate::request::BuildRequest{
   command:crate::request::BuildCommand::PrepareQuery,source_questions:None,diagnostic_declarations:false,timeout_seconds:None,
   policy_inputs:Some(PolicyInputRequest{analysis_context:Some(AnalysisContext::OriginalAnalyze0290),workspace:Some(WorkspacePolicyRequest{root,recursive_roots,configuration}),..Default::default()}),
   project,defines:std::collections::BTreeMap::new(),workers:1,engine_template:None,bootstrap_catalog:false,progress_enabled:false,output_store:None,exact_inputs:false,no_cache:false,
   cache_root:Some(resource.owned(cache)?),record_inputs:None,replay_inputs:None,artifact_directory:None,no_daemon:false,trace_path:None,warnings:crate::diagnostics::WarningPolicy::default(),
  })
 }
}

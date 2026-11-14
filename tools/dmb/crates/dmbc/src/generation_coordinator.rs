//! Serialized full-frontend generation fixed point. The caller already owns
//! the resident BuildHost lock and worker/deadline context. No client installs.
use crate::{GeneratorName,request::{BuildRequest,BuildCommand,BuildOutcome},runner_host::BuildHost,generation_transaction::{self as transaction,Mode,Report,State}};
use std::{error::Error,io,path::{Path,PathBuf},collections::BTreeSet};
type Failure=Box<dyn Error>;
#[derive(Debug)]pub(crate) struct CoordinatorFailure{pub primary:Failure,pub cleanup:Vec<transaction::RollbackFailure>,pub pending_cleanup:Vec<transaction::RollbackFailure>,pub committed:bool}
impl std::fmt::Display for CoordinatorFailure{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{write!(f,"native generation failed: {}",self.primary)?;if self.committed{write!(f,"; earlier generation phases have committed outputs")?;}for warning in self.cleanup.iter().chain(&self.pending_cleanup){write!(f,"; committed cleanup warning for {}: {}",warning.path.display(),warning.error)?;}Ok(())}}
impl Error for CoordinatorFailure{fn source(&self)->Option<&(dyn Error+'static)>{Some(self.primary.as_ref())}}
// SAME existing journal/output envelope, applied to actual simultaneous owned
// coordinator rows. It is neither source authority nor a cached budget.
const RETAINED:usize=64*1024*1024;
fn sum(a:usize,b:usize)->io::Result<usize>{a.checked_add(b).ok_or_else(||io::Error::new(io::ErrorKind::OutOfMemory,"generation coordinator ownership overflow"))}
fn bounded(bytes:usize)->io::Result<()>{if bytes>RETAINED{Err(io::Error::new(io::ErrorKind::OutOfMemory,"generation coordinator retained output exceeds existing envelope"))}else{Ok(())}}
fn vec_bytes<T>(rows:&Vec<T>)->io::Result<usize>{rows.capacity().checked_mul(std::mem::size_of::<T>()).and_then(|n|n.checked_add(std::mem::size_of::<Vec<T>>())).ok_or_else(||io::Error::new(io::ErrorKind::OutOfMemory,"generation coordinator vector overflow"))}
fn warnings_bytes(rows:&Vec<transaction::RollbackFailure>)->io::Result<usize>{rows.iter().try_fold(vec_bytes(rows)?,|n,row|sum(n,row.path.capacity()))}
pub(crate) fn report_bytes(report:&Report)->io::Result<usize>{let mut bytes=sum(vec_bytes(&report.rows)?,vec_bytes(&report.diagnostics)?)?;bytes=sum(bytes,vec_bytes(&report.changed)?)?;bytes=sum(bytes,warnings_bytes(&report.cleanup)?)?;for row in &report.rows{bytes=sum(bytes,row.path.capacity())?;}for row in &report.diagnostics{bytes=sum(bytes,sum(row.relative.capacity(),row.message.capacity())?)?;}for path in &report.changed{bytes=sum(bytes,path.capacity())?;}Ok(bytes)}
fn written_bytes(written:&BTreeSet<PathBuf>)->io::Result<usize>{written.iter().try_fold(std::mem::size_of::<BTreeSet<PathBuf>>(),|n,path|sum(n,sum(1024+std::mem::size_of::<PathBuf>(),path.capacity())?))}
fn append<T>(to:&mut Vec<T>,from:&mut Vec<T>,live:usize)->io::Result<()>{let required=to.len().checked_add(from.len()).ok_or(io::ErrorKind::OutOfMemory)?;if required>to.capacity(){let overlap=required.checked_mul(4).and_then(|n|n.checked_mul(std::mem::size_of::<T>())).ok_or(io::ErrorKind::OutOfMemory)?;bounded(sum(live,overlap)?)?;to.try_reserve_exact(required-to.len()).map_err(|error|io::Error::new(io::ErrorKind::OutOfMemory,error))?;if to.capacity()>required.saturating_mul(4){return Err(io::ErrorKind::OutOfMemory.into())}}to.append(from);Ok(())}
fn phase(name:GeneratorName)->u8{u8::from(matches!(name,GeneratorName::Deps|GeneratorName::DerivedReads|GeneratorName::Plans|GeneratorName::Reads|GeneratorName::TrackedLists))}
fn prepare(host:&mut BuildHost,context:&BuildRequest,names:&[GeneratorName])->Result<(),Failure>{
 crate::daemon::control::checkpoint()?;let mut request=context.clone();request.command=BuildCommand::PrepareQuery;
 if request.source_questions.is_some()||request.diagnostic_declarations{return Err(io::Error::new(io::ErrorKind::InvalidInput,"generation requires the strict existing frontend role").into())}
 let policy=request.policy_inputs.as_mut().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"generation requires actual workspace input intent"))?;if policy.workspace.is_none(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"generation requires issued workspace scope").into())}policy.workspace_generators=names.to_vec();policy.clone().admit()?;
 match crate::request_runner::run_build_with_host(request,host)?{BuildOutcome::QueryPrepared{..}=>Ok(()),_=>Err(io::Error::other("generation preparation did not publish the actual query frame").into())}
}
fn full_stage(host:&mut BuildHost,context:&BuildRequest,names:&[GeneratorName],cache:&Path,mode:Mode,existing:usize)->Result<Report,Failure>{
 if names.is_empty(){return Ok(Report{rows:Vec::new(),diagnostics:Vec::new(),changed:Vec::new(),cleanup:Vec::new(),committed:false})}prepare(host,context,names)?;
 let snapshot={let state=host.query_state();let mut state=state.lock().unwrap_or_else(|error|error.into_inner());state.snapshot.take().ok_or_else(||io::Error::other("prepared generation snapshot unavailable"))?};
 let closed=snapshot.stage_generation(crate::generation_staging::temporary_output(cache)?)?;transaction::commit_with_existing(closed,cache,mode,existing).map_err(|error|Box::new(error)as Failure)
}
struct PhaseReport { report:Report, restricted:bool }
fn source_only(name:GeneratorName)->bool{matches!(name,GeneratorName::Actions|GeneratorName::Declare|GeneratorName::DeclareIds|GeneratorName::Stats|GeneratorName::SystemAccessors|GeneratorName::UiTypes)}
fn restricted_stage(host:&mut BuildHost,context:&BuildRequest,names:&[GeneratorName],requested:&[GeneratorName],cache:&Path,mode:Mode,existing:usize,questions:bool)->Result<Option<Report>,Failure>{
 if names.is_empty(){return Ok(None)}
 match crate::request_runner::generation_cold::stage(host,context,names,requested,questions,cache)?{
  crate::request_runner::generation_cold::Preparation::NotNeeded=>Ok(None),
  crate::request_runner::generation_cold::Preparation::Closed(closed)=>{
   // Successful restricted preparation cannot retain an old published complete
   // frame across mutation. Keep compiler caches, retire only that publication.
   let old={let state=host.query_state();let mut state=state.lock().unwrap_or_else(|error|error.into_inner());state.snapshot.take()};drop(old);
   transaction::commit_with_existing(closed,cache,mode,existing).map(Some).map_err(|error|Box::new(error)as Failure)
  },
 }
}
fn stage(host:&mut BuildHost,context:&BuildRequest,names:&[GeneratorName],requested:&[GeneratorName],cache:&Path,mode:Mode,existing:usize)->Result<PhaseReport,Failure>{
 if let Some(report)=restricted_stage(host,context,names,requested,cache,mode,existing,true)?{return Ok(PhaseReport{report,restricted:true})}
 Ok(PhaseReport{report:full_stage(host,context,names,cache,mode,existing)?,restricted:false})
}
fn merge(mut zero:Report,mut one:Report,other:usize)->io::Result<Report>{zero.committed|=one.committed;let live=sum(sum(report_bytes(&zero)?,report_bytes(&one)?)?,other)?;append(&mut zero.rows,&mut one.rows,live)?;let live=sum(sum(report_bytes(&zero)?,report_bytes(&one)?)?,other)?;append(&mut zero.diagnostics,&mut one.diagnostics,live)?;let live=sum(sum(report_bytes(&zero)?,report_bytes(&one)?)?,other)?;append(&mut zero.changed,&mut one.changed,live)?;let live=sum(sum(report_bytes(&zero)?,report_bytes(&one)?)?,other)?;append(&mut zero.cleanup,&mut one.cleanup,live)?;let sorting=zero.rows.len().checked_mul(2*std::mem::size_of::<transaction::OutputRow>()).and_then(|n|n.checked_add(zero.diagnostics.len().checked_mul(2*std::mem::size_of::<transaction::Diagnostic>())?)).ok_or(io::ErrorKind::OutOfMemory)?;bounded(sum(sum(report_bytes(&zero)?,other)?,sorting)?)?;zero.rows.sort_by(|a,b|a.name.name().cmp(b.name.name()));zero.diagnostics.sort_by(|a,b|a.name.name().cmp(b.name.name()));Ok(zero)}
fn wrote(report:&Report)->bool{report.rows.iter().any(|row|row.state==State::Written)}
fn remember(report:&Report,written:&mut BTreeSet<PathBuf>,other:usize)->io::Result<()>{for path in &report.changed{if !written.contains(path){let next=path.as_os_str().len().checked_mul(4).and_then(|n|n.checked_add(1024+std::mem::size_of::<PathBuf>()+64)).ok_or(io::ErrorKind::OutOfMemory)?;bounded(sum(sum(sum(report_bytes(report)?,written_bytes(written)?)?,other)?,next)?)?;written.insert(path.clone());}}Ok(())}
fn complete_changed(report:&mut Report,written:&mut BTreeSet<PathBuf>,other:usize)->io::Result<()>{
 let count=written.len();let backing=count.checked_mul(4).and_then(|n|n.checked_mul(std::mem::size_of::<PathBuf>())).and_then(|n|n.checked_add(std::mem::size_of::<Vec<PathBuf>>())).ok_or(io::ErrorKind::OutOfMemory)?;
 bounded(sum(sum(sum(report_bytes(report)?,written_bytes(written)?)?,other)?,backing)?)?;
 let mut changed=Vec::new();changed.try_reserve_exact(count).map_err(|error|io::Error::new(io::ErrorKind::OutOfMemory,error))?;if changed.capacity()>count.saturating_mul(4){return Err(io::ErrorKind::OutOfMemory.into())}
 // BTree order is deterministic; no path backing is cloned. Both the old report
 // vector and all set nodes/paths were funded until each physical owner drops.
 for path in std::mem::take(written){changed.push(path)}
 report.changed=changed;Ok(())
}
/// Explicit Declare-only transaction; deliberately not selected by the
/// default coordinator. Its two private question owners have retired before
/// the ordinary journal transaction starts.
pub(crate) fn run_declare_overlay(
    host: &mut BuildHost,
    context: &BuildRequest,
    mode: Mode,
    cache: &Path,
    hook: &mut impl FnMut(transaction::Event) -> io::Result<()>,
) -> Result<Report, Failure> {
    let closed = match crate::request_runner::generation_cold::stage_declare_overlay(host, context, cache)? {
        crate::request_runner::generation_cold::Preparation::Closed(value) => value,
        crate::request_runner::generation_cold::Preparation::NotNeeded =>
            return Err(io::Error::new(io::ErrorKind::Unsupported, "Declare overlay requires an actual missing Declare include").into()),
    };
    let old = host.query_state().lock().unwrap_or_else(|error| error.into_inner()).snapshot.take();
    drop(old);
    let mut report = transaction::commit_using(closed, cache, mode, hook)?;
    // The staged Check result is already complete. A full PrepareQuery here
    // would open the deliberately still-absent file and fail the check.
    if mode == Mode::Check {
        return Ok(report);
    }
    let names = &[GeneratorName::Declare];
    if let Err(primary) = prepare(host, context, names) {
        return Err(Box::new(CoordinatorFailure {
            primary, cleanup: std::mem::take(&mut report.cleanup), pending_cleanup: Vec::new(),
            committed: report.committed,
        }));
    }
    Ok(report)
}

/// Restricted bootstrap precedes the existing native fixed point when needed.
/// Only genuine ordinary preparation publishes the final complete source frame.
pub(crate) fn run(host:&mut BuildHost,context:&BuildRequest,names:&[GeneratorName],mode:Mode,cache:&Path)->Result<Report,Failure>{run_using(host,context,names,mode,cache,&mut|_,_|Ok(()))}
fn run_using(host:&mut BuildHost,context:&BuildRequest,names:&[GeneratorName],mode:Mode,cache:&Path,after_commit:&mut impl FnMut(&Report,&mut BuildHost)->Result<(),Failure>)->Result<Report,Failure>{
 if names.is_empty()||names.len()>crate::GeneratorName::REGISTERED_COUNT{return Err(io::Error::new(io::ErrorKind::InvalidInput,"generation requires a bounded set of actual generator questions").into())}let mut names=names.to_vec();names.sort();if names.windows(2).any(|pair|pair[0]==pair[1]){return Err(io::Error::new(io::ErrorKind::InvalidInput,"duplicate generator question").into())}
 // Auto's existing policy consumes the fixed CLI lint_scopes observation.
 // Reject a predictable incompatible intent before any source-seven commit;
 // the actual reader still authenticates/reads that same path later.
 if names.contains(&GeneratorName::AutoTracked){
  let workspace=context.policy_inputs.as_ref().and_then(|intent|intent.workspace.as_ref()).ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"generation Auto requires actual workspace configuration intent"))?;
  let width=workspace.root.as_os_str().len().checked_add(workspace.configuration.as_os_str().len()).and_then(|n|n.checked_add("/tools/ci/lint_scopes.toml".len())).and_then(|n|n.checked_mul(8)).and_then(|n|n.checked_add(4096)).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;bounded(width)?;
  let expected=dm_preprocess::regions::canonical_path(&workspace.root.join("tools/ci/lint_scopes.toml"));
  if dm_preprocess::regions::canonical_path(&workspace.configuration)!=expected{return Err(io::Error::new(io::ErrorKind::InvalidInput,"generation Auto requires the actual fixed lint_scopes configuration request before output mutation").into())}
 }
 let zero:Vec<_>=names.iter().copied().filter(|name|phase(*name)==0).collect();let one:Vec<_>=names.iter().copied().filter(|name|phase(*name)==1).collect();let mut saved:Option<Report>=None;let mut written=BTreeSet::new();let mut cleanup=Vec::new();let mut pending_cleanup=Vec::new();let mut committed=false;
 let pending=(||->Result<Report,Failure>{
 // Bootstrap only the requested seven source-only roles before the original
 // eight/five fixed point. No missing declarations are faked and no unrequested
 // prerequisite is written. Questions are reissued from actual installed bytes.
 let source_names:Vec<_>=zero.iter().copied().filter(|name|source_only(*name)).collect();
 if let Some(mut bootstrap)=restricted_stage(host,context,&source_names,&names,cache,mode,4096,false)?{
  committed|=bootstrap.committed;pending_cleanup=std::mem::take(&mut bootstrap.cleanup);
  // Commit state and cleanup are owned before any fallible metadata work.
  let live=sum(sum(report_bytes(&bootstrap)?,warnings_bytes(&pending_cleanup)?)?,4096)?;
  append(&mut cleanup,&mut pending_cleanup,live)?;
  remember(&bootstrap,&mut written,sum(warnings_bytes(&cleanup)?,4096)?)?;
  if bootstrap.committed{after_commit(&bootstrap,host)?;}
 }
 for _ in 0..5{
  let saved_bytes=saved.as_ref().map(report_bytes).transpose()?.unwrap_or(0);let existing=sum(sum(sum(sum(saved_bytes,written_bytes(&written)?)?,warnings_bytes(&cleanup)?)?,warnings_bytes(&pending_cleanup)?)?,4096)?;
  let first_phase=stage(host,context,&zero,&names,cache,mode,existing)?;let first_restricted=first_phase.restricted;let mut first=first_phase.report;committed|=first.committed;pending_cleanup=std::mem::take(&mut first.cleanup);if first.committed{if !first_restricted{prepare(host,context,&names)?;}after_commit(&first,host)?;}let live=sum(sum(sum(sum(sum(saved_bytes,written_bytes(&written)?)?,warnings_bytes(&cleanup)?)?,warnings_bytes(&pending_cleanup)?)?,report_bytes(&first)?)?,4096)?;append(&mut cleanup,&mut pending_cleanup,live)?;let other=sum(sum(sum(saved_bytes,warnings_bytes(&cleanup)?)?,warnings_bytes(&pending_cleanup)?)?,4096)?;remember(&first,&mut written,other)?;
  // Every committed mutation advances the SAME real retained source frame.

  if mode==Mode::Write&&wrote(&first){saved=None;continue}
  let mut result=if let Some(second)=saved.take(){let other=sum(sum(sum(written_bytes(&written)?,warnings_bytes(&cleanup)?)?,warnings_bytes(&pending_cleanup)?)?,4096)?;merge(first,second,other)?}else{
   let existing=sum(sum(sum(sum(report_bytes(&first)?,written_bytes(&written)?)?,warnings_bytes(&cleanup)?)?,warnings_bytes(&pending_cleanup)?)?,4096)?;let second_phase=stage(host,context,&one,&names,cache,mode,existing)?;let second_restricted=second_phase.restricted;let mut second=second_phase.report;committed|=second.committed;pending_cleanup=std::mem::take(&mut second.cleanup);if second.committed{if !second_restricted{prepare(host,context,&names)?;}after_commit(&second,host)?;}let live=sum(sum(sum(sum(sum(report_bytes(&first)?,written_bytes(&written)?)?,warnings_bytes(&cleanup)?)?,warnings_bytes(&pending_cleanup)?)?,report_bytes(&second)?)?,4096)?;append(&mut cleanup,&mut pending_cleanup,live)?;let other=sum(sum(sum(report_bytes(&first)?,warnings_bytes(&cleanup)?)?,warnings_bytes(&pending_cleanup)?)?,4096)?;remember(&second,&mut written,other)?;if mode==Mode::Write&&wrote(&second){saved=Some(second);continue}let other=sum(sum(written_bytes(&written)?,warnings_bytes(&cleanup)?)?,4096)?;merge(first,second,other)?};
  // Leave the final unchanged actual native frame on THIS same host for the
  // following compile/check. No source/snapshot is synthesized from journal.
  prepare(host,context,&names)?;if result.rows.is_empty(){return Err(Box::new(crate::request_failure::RequestFailure::source(format!("analyze gen: no generator named {:?}",names.iter().map(|name|name.name()).collect::<Vec<_>>()))))}for row in &mut result.rows{if row.state==State::Fresh&&written.contains(&row.path){row.state=State::Written}}complete_changed(&mut result,&mut written,sum(sum(warnings_bytes(&cleanup)?,warnings_bytes(&pending_cleanup)?)?,4096)?)?;result.cleanup=std::mem::take(&mut cleanup);result.committed=committed;return Ok(result)
 }Err(io::Error::other("native generation did not reach the existing five-pass fixed point").into())})();
 match pending{Ok(report)=>Ok(report),Err(primary)=>Err(Box::new(CoordinatorFailure{primary,cleanup,pending_cleanup,committed}))}
}

#[cfg(test)]mod tests{use super::*;use std::sync::Arc;
 use crate::generation_test_fixture::fixture;
 #[test]fn actual_same_build_host_coordinator_checks_writes_reprepares_and_keeps_final_frame_for_warm_generation(){let(mut host,request,cache,root)=fixture();let target=root.join("code/engine/_generated/deps.dm");let initial=std::fs::read(&target).unwrap();let check=run(&mut host,&request,&[GeneratorName::Deps],Mode::Check,&cache).unwrap();assert_eq!(check.rows.len(),1);assert_eq!(check.rows[0].state,State::Stale);assert_eq!(std::fs::read(&target).unwrap(),initial);let written=run(&mut host,&request,&[GeneratorName::Deps],Mode::Write,&cache).unwrap();assert_eq!(written.rows[0].state,State::Written);assert!(written.cleanup.is_empty());assert_ne!(std::fs::read(&target).unwrap(),initial);let tree=Arc::clone(host.query_tree().unwrap());{let state=host.query_state();let state=state.lock().unwrap();let snapshot=state.snapshot.as_ref().expect("final unchanged frame retained on the actual resident host");snapshot.workspace_native_read().unwrap();snapshot.workspace_generator_inputs(GeneratorName::Deps).unwrap();}let body=std::fs::read(&target).unwrap();let warm=run(&mut host,&request,&[GeneratorName::Deps],Mode::Write,&cache).unwrap();assert_eq!(warm.rows[0].state,State::Fresh);assert!(warm.changed.is_empty());assert_eq!(std::fs::read(&target).unwrap(),body);assert!(Arc::ptr_eq(&tree,host.query_tree().unwrap()),"same actual retained semantic owner, no second native declaration model");}
 #[test]fn actual_same_host_missing_deps_uses_recorded_restricted_questions_then_keeps_real_full_frame(){let(mut host,request,cache,root)=fixture();let target=root.join("code/engine/_generated/deps.dm");std::fs::remove_file(&target).unwrap();let report=run(&mut host,&request,&[GeneratorName::Deps],Mode::Write,&cache).unwrap();assert!(report.committed);assert_eq!(report.rows.len(),1);assert_eq!(report.rows[0].state,State::Written);assert!(target.is_file());let state=host.query_state();let state=state.lock().unwrap();let snapshot=state.snapshot.as_ref().expect("actual installed bytes followed by the ordinary retained pipeline");snapshot.workspace_native_read().unwrap();snapshot.workspace_generator_inputs(GeneratorName::Deps).unwrap();}
 #[test]fn coordinator_stage_partition_is_the_exact_existing_seven_then_five_generator_order(){let zero=[GeneratorName::Actions,GeneratorName::AutoTracked,GeneratorName::Declare,GeneratorName::DeclareIds,GeneratorName::Stats,GeneratorName::SystemAccessors,GeneratorName::UiTypes];let one=[GeneratorName::Deps,GeneratorName::DerivedReads,GeneratorName::Plans,GeneratorName::Reads,GeneratorName::TrackedLists];assert!(zero.into_iter().all(|name|phase(name)==0));assert!(one.into_iter().all(|name|phase(name)==1));}
 #[test]fn actual_postcommit_metadata_allocation_failure_preserves_committed_status_and_current_host_frame(){let(mut host,request,cache,root)=fixture();let target=root.join("code/engine/_generated/deps.dm");let initial=std::fs::read(&target).unwrap();let error=run_using(&mut host,&request,&[GeneratorName::Deps],Mode::Write,&cache,&mut|_,_|{let mut impossible=Vec::<u8>::new();let cause=impossible.try_reserve_exact(usize::MAX).expect_err("actual metadata capacity overflow");Err(Box::new(io::Error::new(io::ErrorKind::OutOfMemory,cause)))}).err().unwrap();let error=error.downcast_ref::<CoordinatorFailure>().unwrap();assert!(error.committed,"real output commit precedes the actual metadata allocation failure");assert_eq!(error.primary.downcast_ref::<io::Error>().unwrap().kind(),io::ErrorKind::OutOfMemory);assert_ne!(std::fs::read(&target).unwrap(),initial);let state=host.query_state();let state=state.lock().unwrap();state.snapshot.as_ref().expect("actual reprepare precedes metadata work").workspace_native_read().unwrap();}

}

#[cfg(test)]
#[path="generation_cold_tests.rs"]
mod cold_tests;
#[cfg(test)]#[path="generation_original_tests.rs"]mod original_tests;

// The explicit all-twelve CHECK observer never accepts a mutation mode.
pub(crate) const OBSERVED_NAMES:[GeneratorName;12]=[GeneratorName::Actions,GeneratorName::AutoTracked,GeneratorName::Declare,GeneratorName::DeclareIds,GeneratorName::Deps,GeneratorName::DerivedReads,GeneratorName::Plans,GeneratorName::Reads,GeneratorName::Stats,GeneratorName::SystemAccessors,GeneratorName::TrackedLists,GeneratorName::UiTypes];
pub(crate) struct ObservedCheck{
 pub(crate) report:Report,
 pub(crate) phases:[Option<transaction::CheckEvidence>;3],
 pub(crate) observation_error:Option<io::Error>,
 _report_credit:dm_preprocess::source_arena_credit::SourceArenaCredit,
 _credit:dm_preprocess::source_arena_credit::SourceArenaCredit,
}
impl ObservedCheck{
 pub(crate) fn require_current(&mut self)->Result<(),Failure>{let mut spools=0u64;for phase in self.phases.iter_mut().flatten(){phase.require_current()?;spools=spools.checked_add(phase.retained_spool_bytes()?).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;if spools>RETAINED as u64{return Err(io::Error::new(io::ErrorKind::OutOfMemory,"observed Check retained journals/backups exceed existing output bound").into())}}crate::daemon::control::checkpoint()?;Ok(())}
}
fn capture_check_phase(host:&mut BuildHost,context:&BuildRequest,names:&[GeneratorName],requested:&[GeneratorName],cache:&Path,existing:usize,questions:bool,fallback:bool)->Result<Option<(Report,transaction::CheckEvidence)>,Failure>{
 if names.is_empty(){return Ok(None)}let closed=match crate::request_runner::generation_cold::stage(host,context,names,requested,questions,cache)?{
  crate::request_runner::generation_cold::Preparation::Closed(closed)=>{let old=host.query_state().lock().unwrap_or_else(|error|error.into_inner()).snapshot.take();drop(old);Some(closed)},
  crate::request_runner::generation_cold::Preparation::NotNeeded if !fallback=>None,
  crate::request_runner::generation_cold::Preparation::NotNeeded=>{prepare(host,context,names)?;let snapshot=host.query_state().lock().unwrap_or_else(|error|error.into_inner()).snapshot.take().ok_or_else(||io::Error::other("observed Check actual phase source absent"))?;Some(snapshot.stage_generation(crate::generation_staging::temporary_output(cache)?)?)},
 };
 match closed{None=>Ok(None),Some(closed)=>{let(report,evidence)=transaction::capture_check(closed,cache,existing,host.source_arena_work())?;if !evidence.matches_names(names){return Err(io::Error::new(io::ErrorKind::InvalidData,"observed Check closure names differ from actual phase").into())}if report.committed||!report.changed.is_empty(){return Err(io::Error::new(io::ErrorKind::InvalidData,"CHECK phase unexpectedly mutated generated outputs").into())}Ok(Some((report,evidence)))}}
}
pub(crate) fn capture_all_check(host:&mut BuildHost,context:&BuildRequest,cache:&Path)->Result<ObservedCheck,Failure>{
 crate::daemon::control::checkpoint()?;let mut names=OBSERVED_NAMES;names.sort();let actual=context.policy_inputs.as_ref().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"observed Check actual generator intent absent"))?;
 if actual.workspace_generators.len()!=names.len()||names.iter().any(|name|actual.workspace_generators.iter().filter(|candidate|*candidate==name).count()!=1){return Err(io::Error::new(io::ErrorKind::InvalidInput,"observed Check requires each canonical production generator exactly once").into())}
 let workspace=actual.workspace.as_ref().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"observed Check workspace absent"))?;let expected=dm_preprocess::regions::canonical_path(&workspace.root.join("tools/ci/lint_scopes.toml"));if dm_preprocess::regions::canonical_path(&workspace.configuration)!=expected{return Err(io::Error::new(io::ErrorKind::InvalidInput,"observed Check Auto needs actual fixed lint_scopes configuration").into())}
 let control=host.source_arena_work().reserve(std::mem::size_of::<ObservedCheck>()+65536)?;
 let zero:Vec<_>=names.iter().copied().filter(|name|phase(*name)==0).collect();let one:Vec<_>=names.iter().copied().filter(|name|phase(*name)==1).collect();let source:Vec<_>=zero.iter().copied().filter(|name|source_only(*name)).collect();let mut phases:[Option<transaction::CheckEvidence>;3]=std::array::from_fn(|_|None);let mut live=4096usize;
 if let Some((report,evidence))=capture_check_phase(host,context,&source,&names,cache,live,false,false)?{live=sum(live,evidence.retained_bytes())?;bounded(sum(live,report_bytes(&report)?)?)?;phases[0]=Some(evidence);drop(report);}
 let(first,first_evidence)=capture_check_phase(host,context,&zero,&names,cache,live,true,true)?.ok_or_else(||io::Error::other("observed Check stage0 was not actually completed"))?;live=sum(live,first_evidence.retained_bytes())?;phases[1]=Some(first_evidence);bounded(sum(live,report_bytes(&first)?)?)?;
 let(second,second_evidence)=capture_check_phase(host,context,&one,&names,cache,sum(live,report_bytes(&first)?)?,true,true)?.ok_or_else(||io::Error::other("observed Check stage1 was not actually completed"))?;live=sum(live,second_evidence.retained_bytes())?;phases[2]=Some(second_evidence);let merge_bytes=first.rows.len().checked_add(second.rows.len()).and_then(|n|n.checked_mul(6*std::mem::size_of::<transaction::OutputRow>())).and_then(|n|first.diagnostics.len().checked_add(second.diagnostics.len()).and_then(|d|d.checked_mul(6*std::mem::size_of::<transaction::Diagnostic>())).and_then(|d|n.checked_add(d))).and_then(|n|n.checked_add(65536)).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;bounded(sum(live,merge_bytes)?)?;let report_credit=host.source_arena_work().reserve(merge_bytes)?;let report=merge(first,second,live)?;
 if report.rows.is_empty()||report.committed||!report.changed.is_empty()||!report.cleanup.is_empty()||report.rows.iter().any(|row|!names.contains(&row.name)){return Err(io::Error::new(io::ErrorKind::InvalidData,"observed Check final report is incomplete or contains mutation/foreign rows").into())}
 bounded(sum(live,report_bytes(&report)?)?)?;prepare(host,context,&names)?;let mut completed=ObservedCheck{report,phases,observation_error:None,_report_credit:report_credit,_credit:control};completed.require_current()?;Ok(completed)
}

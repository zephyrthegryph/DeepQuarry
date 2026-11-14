//! CHECK-only qualification over actual retained phase/source/target owners.
//! No new compiler, source lookup, semantic representation or write callback.
use super::{GenerationRequest,validate_cache};
use crate::{generation_coordinator::{self,ObservedCheck,OBSERVED_NAMES},runner_host::BuildHost,request::BuildRequest};
use std::{error::Error,io::{self,Write}};
use serde::Serialize;
use dm_preprocess::source_arena_credit::SourceArenaWork;
const STREAM:u64=dq_analyze::selected_exclusions_wire::MAX_STREAM;
struct CheckedWriter<'a,W>{inner:&'a mut W,context:&'a crate::daemon::control::WorkerContext,remaining:u64}
impl<W:Write>Write for CheckedWriter<'_,W>{fn write(&mut self,bytes:&[u8])->io::Result<usize>{self.context.checkpoint()?;if bytes.len()as u64>self.remaining{return Err(io::ErrorKind::OutOfMemory.into())}let n=self.inner.write(bytes)?;self.remaining-=n as u64;Ok(n)}fn flush(&mut self)->io::Result<()>{self.context.checkpoint()?;self.inner.flush()}}
#[derive(Serialize)]struct PhaseHeader<'a>{slot:usize,role:&'static str,root:&'a std::path::Path,names:[Option<&'static str>;12],journal_length:u64,journal_records:u64,journal_records_hash:dq_analyze::selected_exclusions_wire::Hex128}
#[derive(Serialize)]struct Header<'a>{schema:&'static str,kind:&'static str,full_policy_parity:bool,full_generation_parity:bool,check_only:bool,source_scope:&'static str,requested_names:[&'static str;12],phases:[Option<PhaseHeader<'a>>;3]}
fn channel<W:Write>(context:&crate::daemon::control::WorkerContext,remaining:&mut u64,output:&mut W,run:impl FnOnce(&mut CheckedWriter<'_,W>)->io::Result<()>)->io::Result<()>{let mut writer=CheckedWriter{inner:output,context,remaining:*remaining};let result=run(&mut writer);*remaining=writer.remaining;result?;writer.flush()}
/// Borrowed actual phase owners. Archive data and independent CHECK oracle
/// here; every stream is provisional until successful outer postvalidation.
pub struct GenerationCheckObservation<'a>{state:&'a mut ObservedCheck,context:crate::daemon::control::WorkerContext,pub deadline:std::time::Instant,remaining:u64}
impl GenerationCheckObservation<'_>{
 fn step(&mut self,run:impl FnOnce(&mut ObservedCheck,&crate::daemon::control::WorkerContext,&mut u64)->io::Result<()>)->io::Result<()>{
  if let Some(error)=&self.state.observation_error{return Err(io::Error::new(error.kind(),"Check observation stopped after its retained first error"))}
  let result=self.context.checkpoint().and_then(|()|run(self.state,&self.context,&mut self.remaining));if let Err(actual)=result{let kind=actual.kind();self.state.observation_error=Some(actual);return Err(io::Error::new(kind,"Check observation failed; the operation retains its first actual error"))}Ok(())
 }
 pub fn phase_slots(&self)->[bool;3]{std::array::from_fn(|slot|self.state.phases[slot].is_some())}
 pub fn write_header(&mut self,output:&mut impl Write)->io::Result<()>{self.step(|state,context,remaining|{
  let phases=std::array::from_fn(|slot|state.phases[slot].as_ref().map(|phase|{let mut names=[None;12];for(out,name)in names.iter_mut().zip(phase.names()){*out=Some(name.name());}let(length,count,hash)=phase.journal_identity();PhaseHeader{slot,role:["bootstrap_provenance_only","final_stage0","final_stage1"][slot],root:phase.root(),names,journal_length:length,journal_records:count,journal_records_hash:dq_analyze::selected_exclusions_wire::Hex128(hash)}}));
  let header=Header{schema:"native-generation-check-observation-v1",kind:"actual_retained_phase_and_target_data",full_policy_parity:false,full_generation_parity:false,check_only:true,source_scope:"actual per-phase inputs and output preimages; no no-intervening-change proof",requested_names:OBSERVED_NAMES.map(|name|name.name()),phases};channel(context,remaining,output,|out|serde_json::to_writer(out,&header).map_err(io::Error::from))
 })}
 /// Same moved input facts, actual target stamp/digest/absence and exact sealed
 /// desired binary journal. No output is reconstructed or queried again.
 pub fn write_phase(&mut self,slot:usize,inputs:&mut impl Write,targets:&mut impl Write,journal:&mut impl Write)->io::Result<()>{self.step(|state,context,remaining|{
  let phase=state.phases.get_mut(slot).and_then(Option::as_mut).ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"actual observed Check phase absent"))?;channel(context,remaining,inputs,|out|phase.write_inputs(out))?;channel(context,remaining,targets,|out|phase.write_targets(out))?;channel(context,remaining,journal,|out|phase.write_journal(out))
 })}
 pub fn write_report(&mut self,output:&mut impl Write)->io::Result<()>{self.step(|state,context,remaining|channel(context,remaining,output,|out|super::write_observed_report(&state.report,out)))}
}
/// Explicit all-twelve CHECK request. It has no mutationmode/bootstrap mode.
/// Caller buffers/discards every observation if callback/postvalidation fails.
pub fn with_all_generation_check_input_observation<F>(host:&mut BuildHost,request:BuildRequest,observe:F)->Result<bool,Box<dyn Error>>
where F:for<'a>FnOnce(GenerationCheckObservation<'a>)->io::Result<()>{
 use crate::daemon::{control,prepare_deadline};
 let requested=prepare_deadline::capture(request.command,request.timeout_seconds,std::time::Instant::now())?.ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"observed generation Check requires original explicit deadline"))?;
 let _binding=if control::WorkerContext::capture_for_checkpoints().is_none(){if control::current_deadline().is_some(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"observed generation Check cannot begin in publication").into())}Some(control::bind_with_deadline(control::Cancellation::default(),requested))}else{if control::current_deadline().is_none_or(|deadline|deadline>requested){return Err(io::Error::new(io::ErrorKind::InvalidInput,"observed generation Check cannot extend inherited request").into())}None};control::checkpoint()?;
 let context=control::WorkerContext::capture().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"observed generation Check lost original context"))?;let deadline=control::current_deadline().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"observed generation Check lost original deadline"))?;
 let generation=GenerationRequest{build:request,check:true,bootstrap:None};let policy=generation.build.policy_inputs.as_ref().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"observed generation Check actual policy absent"))?;
 if !generation.build.no_cache||!generation.build.exact_inputs||policy.analysis_context!=Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290)||!policy.files.is_empty()||!policy.search_folders.is_empty()||!policy.workspace_auxiliary.is_empty(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"observed generation Check requires exact default Original generator-only intent").into())}
 let workspace=policy.workspace.as_ref().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"observed generation Check workspace absent"))?;let cache=generation.build.cache_root.as_ref().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"observed generation Check external cache absent"))?;
 let paths=workspace.recursive_roots.iter().try_fold(generation.build.project.as_os_str().len().checked_add(cache.as_os_str().len()).and_then(|n|n.checked_add(workspace.root.as_os_str().len())).and_then(|n|n.checked_add(workspace.configuration.as_os_str().len())).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?,|n,p|n.checked_add(p.as_os_str().len()).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory)))?;
 let bytes=paths.checked_mul(64).and_then(|n|n.checked_add(65536+std::mem::size_of::<F>())).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;let _metadata=host.source_arena_work().reserve(bytes)?;generation.validate()?;validate_cache(&generation.build)?;
 let mut completed=generation_coordinator::capture_all_check(host,&generation.build,cache)?;completed.require_current()?;
 let observed=observe(GenerationCheckObservation{state:&mut completed,context,deadline,remaining:STREAM});if let Some(first)=completed.observation_error.take(){return Err(first.into())}observed?;completed.require_current()?;control::checkpoint()?;Ok(super::observation_clean(&completed.report))
}

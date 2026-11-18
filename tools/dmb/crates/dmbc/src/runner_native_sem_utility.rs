//! Ordinary utilities over the SAME current Original model and moved recorder.
use super::*;
use dq_analyze::native_sem_utility_wire::{Binding,Question,Frame,OriginalCompleteness};
use dm_preprocess::source_arena_credit::SourceArenaCredit;
use std::{io::{self,Write},sync::Arc};
type BoxError=Box<dyn std::error::Error>;
fn invalid(message:&'static str)->io::Error{io::Error::new(io::ErrorKind::InvalidInput,message)}
pub(crate) struct NativeSemReport{
 pub(crate) binding:Binding,pub(crate) frame:Frame,pub(crate) exit:u8,pub(crate) committed:bool,
 pub(crate) inputs:crate::request_runner::schema_capture::Inputs,
 pub(crate) frontend:Arc<dm_tree::frontend::DiagnosticFrontend>,
 pub(crate) stdout:crate::selected_report_spool::Verified,pub(crate) stderr:crate::selected_report_spool::Verified,
 pub(crate) _prepare_credit:SourceArenaCredit,pub(crate) _credit:SourceArenaCredit,
}
impl NativeSemReport{
 pub(crate)fn publish(self,stdout:&mut impl Write,stderr:&mut impl Write)->Result<u8,BoxError>{self.require_current()?;self.stderr.publish(stderr)?;self.stdout.publish(stdout)?;require_current(&self.frontend,&self.inputs,&self.frame)?;Ok(self.exit)}
 pub(crate) fn require_current(&self)->Result<(),BoxError>{require_current(&self.frontend,&self.inputs,&self.frame)}
}
fn failed<E>(pending:&mut Option<BoxError>,actual:BoxError)->Result<E,dq_analyze::captured_reactive_reads::Failure>{*pending=Some(actual);Err(dq_analyze::captured_reactive_reads::Failure::Unsupported("utility callback failed; original typed error retained".into()))}
impl BuildHost{
 pub(crate)fn stage_native_sem_utility(&mut self,request:crate::request::BuildRequest,binding:&Binding)->Result<NativeSemReport,BoxError>{self.stage_native_sem_utility_using(request,binding,&mut |_|Ok(()))}
 pub(crate)fn stage_native_sem_utility_using(&mut self,request:crate::request::BuildRequest,binding:&Binding,hook:&mut dyn FnMut(crate::native_author_fix_transaction::Event)->io::Result<()>)->Result<NativeSemReport,BoxError>{
  binding.validate()?;crate::daemon::control::checkpoint()?;
  if crate::daemon::control::WorkerContext::capture_for_checkpoints().is_none()||crate::daemon::control::current_deadline().is_none(){return Err(invalid("utility requires its actual request context/deadline").into())}
  let cache=request.cache_root.as_ref().ok_or_else(||invalid("utility cache absent"))?;
  let extra=match &binding.question{Question::Reads{owner,procedure}=>owner.len().checked_add(procedure.len()).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?,_=>0};
  let mut request_size=RequestSize{bytes:0,first:None};let counted=serde_json::to_writer(&mut request_size,&request);if let Some(first)=request_size.first{return Err(first.into())}counted.map_err(io::Error::other)?;
  let bytes=std::mem::size_of::<NativeSemReport>().checked_add(std::mem::size_of::<crate::selected_report_spool::Stage>()*2).and_then(|n|n.checked_add(binding.root.as_os_str().len().checked_mul(8)?)).and_then(|n|n.checked_add(cache.as_os_str().len().checked_mul(8)?)).and_then(|n|n.checked_add(extra.checked_mul(4)?)).and_then(|n|n.checked_add(request_size.bytes.checked_mul(4)?)).and_then(|n|n.checked_add(std::mem::size_of::<crate::request::BuildRequest>())).and_then(|n|n.checked_add(16384)).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;
  let credit=self.source_arena_work().reserve(bytes)?;let recovery_request=request.clone();let recovery_cache=cache.clone();
  let mut stdout=crate::selected_report_spool::Stage::new(cache)?;let mut stderr=crate::selected_report_spool::Stage::new(cache)?;
  let mut base=match binding.question{Question::BaseVarsDead{tsv,few}=>Some(super::base_vars_capture::BaseVarsCapture::new(binding.root.clone(),cache.clone(),tsv,few)),_=>None};
  let mut closure=if matches!(binding.question,Question::Closure{write:true}){Some(super::sem_closure_capture::CapturedClosureTarget::new(binding.root.clone()))}else{None};
  let physical=match (&mut base,&mut closure){(Some(base),_)=>Some(base as &mut dyn crate::request_runner::utility_capture::Capture),(_,Some(closure))=>Some(closure as &mut dyn crate::request_runner::utility_capture::Capture),_=>None};
  let started=std::time::Instant::now();
  let(_,mut inputs,mut frontend,mut prepare_credit)=crate::request_runner::prepare_native_sem_utility(request,binding,self,physical)?;
  inputs.require_current()?;
  let state=self.query_state.try_lock().map_err(|_|invalid("utility current query snapshot already borrowed or poisoned"))?;
  let snapshot=state.snapshot.as_ref().ok_or_else(||invalid("utility current snapshot absent"))?;
  let mut frame=snapshot.native_sem_utility_frame(&inputs)?;
  let mut exit=0;
  if base.is_none(){
   let question=match binding.question{Question::ClothingDump=>crate::policy_request::WorkspaceAuxiliaryQuestion::BaseVars,_=>crate::policy_request::WorkspaceAuxiliaryQuestion::SemReads};
   let mut first=None;
   let result=inputs.with_context(||snapshot.with_original_utility_model(question,true,|policy,root,budget,_work,body,markers|{
    match super::native_sem_prelude::with_values(&frontend,policy,self.query_db(),body,root,budget,markers,started,&mut stderr,|values,_a,stderr|{
     match &binding.question{
      Question::ClothingDump=>values.visit_types(&mut|owner,path|{if !dq_analyze::native_sem_utility_render::clothing_type(path){return Ok(())}let mut values_owned=std::array::from_fn::<_,8,_>(|_|None);for(index,name)in dq_analyze::native_sem_utility_render::CLOTHING_VARS.iter().enumerate(){values_owned[index]=values.debug_value(owner,name)?;}let borrowed=std::array::from_fn(|index|values_owned[index].as_ref().map(|value|value.as_str()));dq_analyze::native_sem_utility_render::clothing_borrowed_row(&mut stdout,path,&borrowed)})?,
      Question::ReadsUsage=>{writeln!(stderr,"usage: analyze sem reads /type proc")?;exit=2;},
      Question::Help=>writeln!(stdout,"analyze sem reads /type proc | analyze sem oracle [--all] | analyze sem closure [--write] | analyze sem clothing-dump")?,
      Question::Reads{..}|Question::Closure{..}=>{},
      Question::BaseVarsDead{..}=>return Err(invalid("base-vars entered Sem prelude").into()),
     }Ok(())
    }){Ok(())=>Ok(()),Err(actual)=>failed(&mut first,actual)}
   }));if let Some(actual)=first{return Err(actual)}result?;
   match &binding.question{
    Question::Reads{owner,procedure}=>{let analysis=std::time::Instant::now();inputs.with_context(||snapshot.with_original_sem_utility_read(owner,procedure,|data,budget,_work|{let poll=||{budget.require().map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))?;crate::daemon::control::checkpoint()};data.utility_procedure().ok_or_else(||invalid("utility omitted its actual procedure descriptor"))?.write(owner,procedure,&mut stderr)?;writeln!(stderr,"analysis: {:.2?}",analysis.elapsed())?;dq_analyze::native_sem_utility_render::frozen_reads(&mut stdout,data.facts(),&poll)?;poll()}))?;},
    Question::Closure{..}=>inputs.with_context(||snapshot.with_original_utility_pages(|policy,root,pages,order,budget,body,patterns|dq_analyze::captured_sem_utility_closure::render(policy,root,pages,order,budget,&||crate::daemon::control::checkpoint(),body,patterns,&mut|text|stdout.write_all(text.as_bytes()))))?,
    _=>{},
   }
  }
  drop(state);
  let(mut stdout,stderr)=if let Some(base)=&mut base{base.take()?}else{(stdout.seal_allow_empty()?.validate(crate::request_runner::schema_capture::drain)?.0,stderr.seal_allow_empty()?.validate(crate::request_runner::schema_capture::drain)?.0)};
  let mut committed=false;
  if let Some(target)=&mut closure{
   require_current(&frontend,&inputs,&frame)?;let desired=ReportBytes::capture(stdout,self.source_arena_work())?;self.clear_regions();
   let attempted=crate::native_author_fix_transaction::commit_closure_using(target,&desired.bytes,self.source_arena_work(),&mut||require_current(&frontend,&inputs,&frame),&mut|event|hook(event));
   let recovered=crate::request_runner::prepare_native_sem_utility(recovery_request,binding,self,Some(target));
   let transition=match attempted{Err(actual)=>{let(recovered,recovery)=match recovered{Ok(value)=>{drop(value);(true,None)},Err(error)=>{self.clear_regions();(false,Some(error))}};return Err(crate::native_fix::FailedMutation::from_attempt(actual.primary,actual.may_have_changed,recovered,recovery))},Ok(actual)=>actual.into_parts().1};
   let(_,next_inputs,next_frontend,next_credit)=match recovered{Ok(value)=>value,Err(first)=>{self.clear_regions();return Err(first)}};
   inputs.require_closure_report_step(&next_inputs,&binding.root,&transition,self.source_arena_work())?;
   let current=self.query_state.try_lock().map_err(|_|invalid("utility reprepare snapshot already borrowed"))?;let next_frame=current.snapshot.as_ref().ok_or_else(||invalid("utility reprepare omitted actual snapshot"))?.native_sem_utility_frame(&next_inputs)?;drop(current);
   inputs=next_inputs;frontend=next_frontend;prepare_credit=next_credit;frame=next_frame;require_current(&frontend,&inputs,&frame)?;
   let mut summary=crate::selected_report_spool::Stage::new(&recovery_cache)?;writeln!(summary,"wrote {}",binding.root.join(super::sem_closure_capture::RELATIVE).display())?;stdout=summary.seal()?.validate(crate::request_runner::schema_capture::drain)?.0;committed=true;drop(desired);
  }
  let report=NativeSemReport{binding:binding.clone(),frame,exit,committed,inputs,frontend,stdout,stderr,_prepare_credit:prepare_credit,_credit:credit};report.require_current()?;Ok(report)
 }
}

pub(crate) fn require_current(frontend:&dm_tree::frontend::DiagnosticFrontend,inputs:&crate::request_runner::schema_capture::Inputs,frame:&Frame)->Result<(),BoxError>{frontend.require_original_utility_owner()?;let actual=match frontend.original_analysis_completeness(){Some(dm_tree::frontend::OriginalAnalysisCompleteness::Complete)=>OriginalCompleteness::Complete,Some(dm_tree::frontend::OriginalAnalysisCompleteness::PrimaryPrefix)=>OriginalCompleteness::PrimaryPrefix,None=>return Err(invalid("utility actual Original completeness absent").into())};if actual!=frame.original{return Err(invalid("utility terminal completeness differs from actual owner").into())}let view=frontend.source_view().map_err(io::Error::other)?;inputs.require_binding(view.mapping(),view.tree().identity(),view.source_revision())?;inputs.require_current()?;crate::daemon::control::checkpoint()?;Ok(())}

struct RequestSize{bytes:usize,first:Option<io::Error>}
impl Write for RequestSize{fn write(&mut self,bytes:&[u8])->io::Result<usize>{let Some(next)=self.bytes.checked_add(bytes.len())else{self.first=Some(io::ErrorKind::OutOfMemory.into());return Err(io::ErrorKind::Other.into())};self.bytes=next;Ok(bytes.len())}fn flush(&mut self)->io::Result<()>{Ok(())}}
pub(super) struct ReportBytes{pub(super) bytes:Vec<u8>,_credit:SourceArenaCredit}
impl ReportBytes{pub(super) fn capture(report:crate::selected_report_spool::Verified,work:&dyn dm_preprocess::source_arena_credit::SourceArenaWork)->io::Result<Self>{let length=usize::try_from(report.length()).map_err(|_|io::ErrorKind::OutOfMemory)?;let credit=work.reserve(length.checked_mul(4).and_then(|n|n.checked_add(std::mem::size_of::<Self>())).ok_or(io::ErrorKind::OutOfMemory)?)?;let mut bytes=Vec::new();bytes.try_reserve_exact(length).map_err(|_|io::ErrorKind::OutOfMemory)?;if bytes.capacity()>length.checked_mul(4).ok_or(io::ErrorKind::OutOfMemory)?{return Err(io::ErrorKind::OutOfMemory.into())}struct Sink<'a>{bytes:&'a mut Vec<u8>,expected:usize}impl Write for Sink<'_>{fn write(&mut self,part:&[u8])->io::Result<usize>{if self.bytes.len().checked_add(part.len()).is_none_or(|n|n>self.expected){return Err(invalid("closure report exceeds its verified extent"))}self.bytes.extend_from_slice(part);Ok(part.len())}fn flush(&mut self)->io::Result<()>{Ok(())}}report.publish(&mut Sink{bytes:&mut bytes,expected:length})?;if bytes.len()!=length{return Err(invalid("closure report is shorter than verified extent"))}Ok(Self{bytes,_credit:credit})}}

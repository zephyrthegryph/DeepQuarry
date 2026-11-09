//! Real host ports for the private handler partial-purpose producer.
//! SAME QueryDb/current Kind4 children; no raw reparse or second model cache.
use super::*;
use std::{cell::RefCell,io};
use dq_analyze::{captured_reactive_reads::Failure,captured_generator_budget::Budget};
use dm_tree::frontend::{BodySyntaxFailure,CurrentArchivedBody};
use crate::input_snapshot::HandlerPreparedCapture;
use crate::request_runner::runner_freshness::HandlerPolicyAdmission;
fn body_failure(error:BodySyntaxFailure)->Failure{match error{BodySyntaxFailure::Operational(actual)=>Failure::Operational(actual),BodySyntaxFailure::Syntax(actual)=>Failure::Unsupported(actual.message)}}
fn actual(message:&str)->Failure{Failure::Operational(io::Error::new(io::ErrorKind::InvalidData,message))}
struct Source<'a,'ctx>{queries:&'a QueryDb,capture:&'a Arc<HandlerPreparedCapture>,inputs:&'a dm_analysis::policy_inputs::HandlersStructuralInputs,recipe:&'a dq_analyze::sem_handlers_partial_recipe::Recipe,ctx:RefCell<&'a mut dm_query::Ctx<'ctx>>,budget:&'a Arc<Budget>}
impl dq_analyze::sem_handlers_structural_native::Source for Source<'_,'_>{
 fn inputs(&self)->&dm_analysis::policy_inputs::HandlersStructuralInputs{self.inputs}
 fn require(&self)->Result<(),Failure>{self.capture.require_bound()?;if !self.capture.uses_queries(self.queries)||!self.inputs.archive().uses_body_queries(self.queries){return Err(actual("handlers current source/query owner differs"))}self.budget.require().map_err(|m|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,m)))}
 fn checkpoint(&self)->io::Result<()>{crate::daemon::control::checkpoint()}
 fn budget(&self)->&Arc<Budget>{self.budget}
 fn definition_relative(&self,ordinal:usize,scratch:&Budget)->Result<String,Failure>{
  dq_analyze::sem_handlers_structural_native::Source::require(self)?;crate::daemon::control::checkpoint()?;
  let occurrence=self.inputs.archive().occurrences().get(ordinal).ok_or("handler source value ordinal absent")?;let point=self.inputs.archive().callable_header_policy_line(occurrence.member)?;let root=self.capture.root();let size=point.path.as_os_str().len().checked_add(root.as_os_str().len()).and_then(|n|n.checked_mul(128)).and_then(|n|n.checked_add(4096)).ok_or_else(||{scratch.deny();Failure::Operational(io::ErrorKind::OutOfMemory.into())})?;scratch.charge(size).map_err(|m|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,m)))?;
  let relative=dm_preprocess::regions::relative_filesystem_path(&point.path,root);Ok(match relative{Some(relative)=>dq_analyze::util::rel_slash(&relative,std::path::Path::new("")),None=>dq_analyze::util::rel_slash(&point.path,root)})
 }
 fn candidate(&self,relative:&str)->Result<bool,Failure>{dq_analyze::sem_handlers_structural_native::Source::require(self)?;Ok(self.recipe.candidates.binary_search_by(|row|row.relative.as_str().cmp(relative)).is_ok())}
 fn line_at(&self,current:dm_syntax::Span)->Result<u32,Failure>{dq_analyze::sem_handlers_structural_native::Source::require(self)?;let point=self.inputs.mapping().original_policy_line(current.start)?;u32::try_from(point.line).map_err(|_|"handler current report line overflow".into())}
 fn with_current_body<'a>(&'a self,ordinal:usize,consume:&mut dyn for<'p>FnMut(CurrentArchivedBody<'a,'p>,&dm_syntax::SettingAdmission<'_>)->Result<(),Failure>)->Result<(),Failure>{
  dq_analyze::sem_handlers_structural_native::Source::require(self)?;let mut first=None;
  let result=self.queries.with_handlers_current_body_in(&mut self.ctx.borrow_mut(),self.inputs.archive(),ordinal,|_,availability,a|{
   let body=match availability{super::handlers_current_body::HandlerBodyAvailability::Available(body)|super::handlers_current_body::HandlerBodyAvailability::Skipped(body)=>body};
   match consume(body,a){Ok(())=>Ok(()),Err(actual)=>{first=Some(actual);Err(BodySyntaxFailure::Operational(io::Error::new(io::ErrorKind::Interrupted,"actual handler current-body consumer stopped")))}}
  });if let Some(actual)=first{return Err(actual)}result.map_err(body_failure)
 }
}
/// Called only by the actual registered handler result query after its own
/// genuine partial admission. Returns unsealed findings; no full report grant.
pub(super) fn collect_structural_in(queries:&QueryDb,ctx:&mut dm_query::Ctx<'_>,capture:&Arc<HandlerPreparedCapture>,proof:&HandlerPolicyAdmission,budget:&Arc<Budget>,emit:impl FnMut(&'static str,&str,u32,String)->Result<(),Failure>)->Result<(),Failure>{
 crate::daemon::control::checkpoint()?;if !Arc::ptr_eq(capture,proof.capture()){return Err(actual("handler result has another actual admitted capture"))}capture.require_bound()?;
 if !capture.uses_queries(queries){return Err(actual("handler result belongs to another current QueryDb"))}
 if capture.prepared().frontend().is_none(){if capture.prepared().subject().has_candidates(){return Err(actual("handler selected candidates lost their real partial model"))}return Ok(())}
 capture.prepared().subject().with_recipe(|recipe|{
 let width=recipe.try_calls.len().checked_mul(std::mem::size_of::<&str>()*4).and_then(|n|n.checked_add(128)).ok_or_else(||{budget.deny();Failure::Operational(io::ErrorKind::OutOfMemory.into())})?;budget.charge(width).map_err(|m|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,m)))?;let calls=recipe.try_calls.iter().map(String::as_str).collect::<Vec<_>>();
 let source=Source{queries,capture,inputs:capture.structural_inputs()?,recipe,ctx:RefCell::new(ctx),budget};dq_analyze::sem_handlers_structural_native::collect(&source,&calls,emit)
 })?
}

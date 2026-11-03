//! The SAME evaluated walker over actual current source/model + canonical BODY.
//! This first consumer lends expression events for selected variable policy;
//! it does not claim full original-union/prefix migration or invent old None.
use super::*;
use crate::{policy_body_demand::PolicyFailure as Failure,checker_effects::output::ReportBudget};
use std::{cell::RefCell,io};
#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub(crate) enum CurrentEvaluation{Evaluated,SkippedOriginal}
struct State<'a>{budget:&'a ReportBudget,reserve:&'a dyn Fn(usize)->io::Result<()>,checkpoint:&'a dyn Fn()->io::Result<()>,first:RefCell<Option<io::Error>>}
impl State<'_>{
 fn fail(&self,actual:io::Error)->Failure{let kind=actual.kind();if self.first.borrow().is_none(){*self.first.borrow_mut()=Some(actual);}Failure::Operational(kind.into())}
 fn checkpoint(&self)->Result<(),Failure>{if let Some(first)=self.first.borrow().as_ref(){return Err(Failure::Operational(first.kind().into()))}(self.checkpoint)().map_err(|actual|self.fail(actual))?;self.budget.charge(0).map_err(|_|self.fail(io::Error::new(io::ErrorKind::OutOfMemory,"current evaluator execution admission exhausted")))}
 fn storage(&self,bytes:usize)->Result<(),Failure>{self.checkpoint()?;self.budget.charge(bytes).map_err(|_|self.fail(io::Error::new(io::ErrorKind::OutOfMemory,"current evaluator storage admission exhausted")))?;(self.reserve)(bytes).map_err(|actual|self.fail(actual))}
}
struct CurrentDemand<'s,'a,'operation>{state:&'s State<'a>,archive:&'s BodyArchive,admission:&'s dm_syntax::SettingAdmission<'operation>,loan:Option<&'s crate::checks_undefined_variable::CurrentCanonicalBodyLoan<'s>>}
impl PrefixDemand for CurrentDemand<'_,'_,'_>{
 type Error=Failure;
 fn source_checkpoint(&self)->Option<&dyn Fn()->io::Result<()>>{Some(self.state.checkpoint)}
 fn checkpoint(&self)->Result<(),Failure>{self.state.checkpoint()}
 fn storage(&self,bytes:usize)->Result<(),Failure>{self.state.storage(bytes)}
 fn policy_failure(&self,failure:Failure)->Failure{failure}
 fn resource(&self,message:&'static str)->Failure{self.state.fail(io::Error::new(io::ErrorKind::OutOfMemory,message))}
 fn owns_directive_binding(&self)->bool{self.loan.is_some()}
 fn owns_return_expression_binding(&self)->bool{self.loan.is_some()}
 fn prefix_with_budget<T>(&self,archive:&BodyArchive,identity:dm_ir::ProcedureIdentity,_:Option<&ReportBudget>,consume:impl FnOnce(dm_tree::frontend::InitialSettingPrefix<'_>)->T)->Result<T,Failure>{
  self.state.checkpoint()?;if !std::ptr::eq(archive,self.archive){return Err("current canonical prefix archive is foreign".into())}let loan=self.loan.ok_or("current canonical callee-prefix/return-expression binding needs actual query-context loan; old absolute BODY fallback is forbidden")?;
  let ordinal=archive.callables().ordinal_for_identity_using(identity,&mut||self.state.checkpoint())?.ok_or("current canonical source callable occurrence absent")?;
  archive.with_current_body_checked_in(ordinal,self.admission,&mut(),|_,input|loan(input),|_,body|body.with_initial_setting_prefix(identity,self.admission,consume)).map_err(transport)
 }
}
struct Sink<'s,'a,F>{state:&'s State<'a>,consume:F}
impl<'ast,F:FnMut(Event<'ast>)->Result<(),Failure>> OriginalEvents<'ast,Failure> for Sink<'_,'_,F>{
 fn expression_event(&mut self,event:Event<'ast>)->Result<(),Failure>{self.state.checkpoint()?;(self.consume)(event)}
 // The selected variable policy requests expression events, not control rows.
 // SAME pinned control walk still decides which expressions actually execute.
 fn flow_event(&mut self,_:crate::checker_reachable::Event<'ast>)->Result<(),Failure>{self.state.checkpoint()}
 fn access_row(&mut self,_:crate::checks_proc_visibility::Row<'ast>)->Result<(),Failure>{Err("current variable event consumer did not request procedure-access rows".into())}
 fn immediate_row(&mut self,_:crate::checks::Diagnostic)->Result<(),Failure>{Err("current variable event consumer did not request immediate effect rows".into())}
}
fn transport(failure:dm_tree::frontend::BodySyntaxFailure)->Failure{match failure{dm_tree::frontend::BodySyntaxFailure::Operational(actual)=>Failure::Operational(actual),dm_tree::frontend::BodySyntaxFailure::Syntax(actual)=>actual.message.into()}}
pub(crate) fn events_using<'ast>(body:&'ast dm_tree::frontend::CurrentArchivedBody<'_,'_>,resolver:&(impl Resolver+?Sized),profile:PackedU128,syntax_admission:&dm_syntax::SettingAdmission<'_>,budget:&ReportBudget,reserve:&dyn Fn(usize)->io::Result<()>,checkpoint:&dyn Fn()->io::Result<()>,prefix_loan:Option<&crate::checks_undefined_variable::CurrentCanonicalBodyLoan<'_>>,consume:impl FnMut(Event<'ast>)->Result<(),Failure>)->Result<CurrentEvaluation,Failure>{
 checkpoint().map_err(Failure::Operational)?;
 if resolver.source_owner()!=Some(std::ptr::from_ref(body.tree()).cast()){return Err("current semantic resolver belongs to another native model".into())}
 body.tree().validate_checker_builtin_profile(profile).map_err(|actual|format!("current semantic builtin profile: {actual:?}"))?;
 match body.syntax().original_code_disposition().map_err(transport)?{dm_tree::frontend::OriginalBodyDisposition::Skipped(_)=>return Ok(CurrentEvaluation::SkippedOriginal),dm_tree::frontend::OriginalBodyDisposition::Available(_)=>{}}
 let state=State{budget,reserve,checkpoint,first:RefCell::new(None)};let mut sink=Sink{state:&state,consume};
 let result=(||{let parameters=body.source_parameters(syntax_admission).map_err(transport)?;let mut walker=Walker::new_current_using(body,parameters,resolver,profile,CurrentDemand{state:&state,archive:body.archive_owner(),admission:syntax_admission,loan:prefix_loan})?;walker.original_events=Some(&mut sink);walker.original_values=prefix_loan.is_some();crate::checker_reachable::current_original_syntax_with_observer_using(body,&mut walker)?;walker.check_effect_admission()?;Ok(CurrentEvaluation::Evaluated)})();
 if let Some(actual)=state.first.borrow_mut().take(){return Err(Failure::Operational(actual))}if matches!(&result,Err(Failure::Operational(_))){return result}checkpoint().map_err(Failure::Operational)?;result
}

//! Typed body transport for the SAME original prefix/return policy.
use dm_tree::frontend::{BodyArchive,BodySyntax,BodySyntaxInput,BodySyntaxFailure,InitialSettingPrefix};
use crate::checker_effects::{ExecutionAdmission,output::ReportBudget};
use std::sync::Arc;
pub(crate) type BodyLoan<'a>=dyn Fn(&Arc<BodySyntaxInput>,&ExecutionAdmission)->Result<Arc<BodySyntax>,BodySyntaxFailure>+'a;
pub(crate) trait Demand{
 type Error:From<String>+for<'a>From<&'a str>;
 fn source_checkpoint(&self)->Option<&dyn Fn()->std::io::Result<()>>{None}
 fn policy_failure(&self,failure:crate::policy_body_demand::PolicyFailure)->Self::Error{failure.to_string().into()}
 fn checkpoint(&self)->Result<(),Self::Error>{Ok(())}
 fn storage(&self,_bytes:usize)->Result<(),Self::Error>{Ok(())}
 fn owns_directive_binding(&self)->bool{false}
 fn owns_return_expression_binding(&self)->bool{false}
 fn profile(&self)->Option<dm_tree::checker_builtins::ValidatedCheckerProfile<'_>>{None}
 fn validate_profile(&self,tree:&dm_tree::SemanticTree,profile:dm_ir::PackedU128)->Result<(),dm_tree::checker_builtins::CheckerBuiltinError>{match self.profile(){Some(checked)=>checked.require(tree,profile),None=>tree.validate_checker_builtin_profile(profile)}}
 fn resource(&self,message:&'static str)->Self::Error;
 fn prefix_with_budget<T>(&self,archive:&BodyArchive,identity:dm_ir::ProcedureIdentity,budget:Option<&ReportBudget>,consume:impl FnOnce(InitialSettingPrefix<'_>)->T)->Result<T,Self::Error>;
 fn prefix<T>(&self,archive:&BodyArchive,identity:dm_ir::ProcedureIdentity,consume:impl FnOnce(InitialSettingPrefix<'_>)->T)->Result<T,Self::Error>{self.prefix_with_budget(archive,identity,None,consume)}
 fn with_budget<'b>(&'b self,budget:Option<&'b ReportBudget>)->Bounded<'b,Self> where Self:Sized{Bounded{demand:self,budget}}
}
pub(crate) struct Bounded<'a,D>{demand:&'a D,budget:Option<&'a ReportBudget>}
impl<D:Demand> Demand for Bounded<'_,D>{type Error=D::Error;fn source_checkpoint(&self)->Option<&dyn Fn()->std::io::Result<()>>{self.demand.source_checkpoint()}fn policy_failure(&self,failure:crate::policy_body_demand::PolicyFailure)->Self::Error{self.demand.policy_failure(failure)}fn checkpoint(&self)->Result<(),Self::Error>{self.demand.checkpoint()}fn storage(&self,bytes:usize)->Result<(),Self::Error>{self.demand.storage(bytes)}fn owns_directive_binding(&self)->bool{self.demand.owns_directive_binding()}fn owns_return_expression_binding(&self)->bool{self.demand.owns_return_expression_binding()}fn profile(&self)->Option<dm_tree::checker_builtins::ValidatedCheckerProfile<'_>>{self.demand.profile()}fn resource(&self,message:&'static str)->Self::Error{self.demand.resource(message)}fn prefix_with_budget<T>(&self,archive:&BodyArchive,identity:dm_ir::ProcedureIdentity,budget:Option<&ReportBudget>,consume:impl FnOnce(InitialSettingPrefix<'_>)->T)->Result<T,Self::Error>{self.demand.prefix_with_budget(archive,identity,budget.or(self.budget),consume)}}
pub(crate) struct Compatibility<E=String>(std::marker::PhantomData<fn()->E>);
impl<E> Compatibility<E>{pub(crate) fn new()->Self{Self(std::marker::PhantomData)}}
impl<E:From<String>+for<'a>From<&'a str>> Demand for Compatibility<E>{type Error=E;fn resource(&self,message:&'static str)->E{message.into()}fn prefix_with_budget<T>(&self,archive:&BodyArchive,identity:dm_ir::ProcedureIdentity,_budget:Option<&ReportBudget>,consume:impl FnOnce(InitialSettingPrefix<'_>)->T)->Result<T,E>{archive.with_initial_setting_prefix(identity,consume).map_err(E::from)}}
pub(crate) struct Checked<'a>{pub(crate) checkpoint:&'a dyn Fn()->std::io::Result<()>,pub(crate) body:&'a BodyLoan<'a>,pub(crate) admission:&'a ExecutionAdmission,pub(crate) profile:dm_tree::checker_builtins::ValidatedCheckerProfile<'a>,pub(crate) original_syntax:bool}
impl Demand for Checked<'_>{type Error=crate::policy_body_demand::PolicyFailure;fn source_checkpoint(&self)->Option<&dyn Fn()->std::io::Result<()>>{Some(self.checkpoint)}fn policy_failure(&self,failure:crate::policy_body_demand::PolicyFailure)->Self::Error{failure}fn checkpoint(&self)->Result<(),Self::Error>{(self.checkpoint)().map_err(Self::Error::Operational)}fn profile(&self)->Option<dm_tree::checker_builtins::ValidatedCheckerProfile<'_>>{Some(self.profile)}fn resource(&self,message:&'static str)->Self::Error{Self::Error::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,message))}fn prefix_with_budget<T>(&self,archive:&BodyArchive,identity:dm_ir::ProcedureIdentity,budget:Option<&ReportBudget>,consume:impl FnOnce(InitialSettingPrefix<'_>)->T)->Result<T,Self::Error>{
 let view=budget.map_or_else(||self.admission.current_view(),ReportBudget::admission_view);
 if !self.admission.same_control(&view){return Err(Self::Error::Operational(std::io::Error::new(std::io::ErrorKind::InvalidInput,"effect prefix scratch view has another admission")))}
 let parse = |_: &BodyArchive, ordinal| {
  archive.parse_checked_using(ordinal, &|input: &Arc<BodySyntaxInput>| (self.body)(input, &view)).map_err(|error| match error {
   BodySyntaxFailure::Syntax(error) => Self::Error::from(error.message),
   BodySyntaxFailure::Operational(actual) => Self::Error::Operational(actual),
  })
 };
 if self.original_syntax {
  archive.with_initial_setting_prefix_original_syntax_using(identity, parse, consume)
 } else {
  archive.with_initial_setting_prefix_using(identity, parse, consume)
 }
}}
impl<D:Demand+?Sized> Demand for &D{type Error=D::Error;fn source_checkpoint(&self)->Option<&dyn Fn()->std::io::Result<()>>{(**self).source_checkpoint()}fn policy_failure(&self,failure:crate::policy_body_demand::PolicyFailure)->Self::Error{(**self).policy_failure(failure)}fn checkpoint(&self)->Result<(),Self::Error>{(**self).checkpoint()}fn storage(&self,bytes:usize)->Result<(),Self::Error>{(**self).storage(bytes)}fn owns_directive_binding(&self)->bool{(**self).owns_directive_binding()}fn owns_return_expression_binding(&self)->bool{(**self).owns_return_expression_binding()}fn profile(&self)->Option<dm_tree::checker_builtins::ValidatedCheckerProfile<'_>>{(**self).profile()}fn resource(&self,message:&'static str)->Self::Error{(**self).resource(message)}fn prefix_with_budget<T>(&self,archive:&BodyArchive,identity:dm_ir::ProcedureIdentity,budget:Option<&ReportBudget>,consume:impl FnOnce(InitialSettingPrefix<'_>)->T)->Result<T,Self::Error>{(**self).prefix_with_budget(archive,identity,budget,consume)}}

/// Typed checked demand for configured semantic checker policies. It borrows
/// the archive's actual host; it does not mint an effects admission or new Db.
pub(crate) struct Policy<'a>{pub(crate) checkpoint:&'a dyn Fn()->std::io::Result<()>}
impl Demand for Policy<'_>{
 type Error=crate::policy_body_demand::PolicyFailure;
 fn source_checkpoint(&self)->Option<&dyn Fn()->std::io::Result<()>>{Some(self.checkpoint)}
 fn policy_failure(&self,failure:crate::policy_body_demand::PolicyFailure)->Self::Error{failure}
 fn checkpoint(&self)->Result<(),Self::Error>{(self.checkpoint)().map_err(Self::Error::Operational)}
 fn owns_directive_binding(&self)->bool{true}
 fn resource(&self,message:&'static str)->Self::Error{Self::Error::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,message))}
 fn prefix_with_budget<T>(&self,archive:&BodyArchive,identity:dm_ir::ProcedureIdentity,_budget:Option<&ReportBudget>,consume:impl FnOnce(InitialSettingPrefix<'_>)->T)->Result<T,Self::Error>{
  self.checkpoint()?;let pending=archive.with_initial_setting_prefix_original_syntax_using(identity,|archive,ordinal|archive.parse_checked(ordinal).map_err(|error|match error{BodySyntaxFailure::Operational(actual)=>Self::Error::Operational(actual),BodySyntaxFailure::Syntax(error)=>error.message.into()}),consume);
  // T is opaque and may itself carry the first operational failure. Do not
  // poll between that callback and the typed family boundary, which performs
  // its final guard only after inspecting actual Operational first.
  pending
 }
}

/// Borrow the existing checked demand only after EffectInput authenticated its
/// Original checker receipt. The same body contribution owns all insertion
/// diagnostics; ordinary effects keep their strict partial-prefix contract.
pub(crate) struct Original<D>(pub(crate) D);
impl<D:Demand> Demand for Original<D>{type Error=D::Error;fn source_checkpoint(&self)->Option<&dyn Fn()->std::io::Result<()>>{self.0.source_checkpoint()}fn policy_failure(&self,failure:crate::policy_body_demand::PolicyFailure)->Self::Error{self.0.policy_failure(failure)}fn checkpoint(&self)->Result<(),Self::Error>{self.0.checkpoint()}fn storage(&self,bytes:usize)->Result<(),Self::Error>{self.0.storage(bytes)}fn owns_directive_binding(&self)->bool{true}fn owns_return_expression_binding(&self)->bool{true}fn profile(&self)->Option<dm_tree::checker_builtins::ValidatedCheckerProfile<'_>>{self.0.profile()}fn resource(&self,message:&'static str)->Self::Error{self.0.resource(message)}fn prefix_with_budget<T>(&self,archive:&BodyArchive,identity:dm_ir::ProcedureIdentity,budget:Option<&ReportBudget>,consume:impl FnOnce(InitialSettingPrefix<'_>)->T)->Result<T,Self::Error>{self.0.prefix_with_budget(archive,identity,budget,consume)}}

/// Opt-in direct canonical transport. The existing archive's retained BODY
/// query owns every callee loan. This adapter never asks for absolute syntax.
pub(crate) struct Current<'a,'op>{
 pub(crate) archive:&'a BodyArchive,
 pub(crate) admission:&'a dm_syntax::SettingAdmission<'op>,
 pub(crate) checkpoint:&'a dyn Fn()->std::io::Result<()>,
 pub(crate) obtain:Option<&'a crate::checker_effects::CanonicalOriginalBodyLoan<'a>>,
}
impl Demand for Current<'_,'_>{
 type Error=crate::policy_body_demand::PolicyFailure;
 fn source_checkpoint(&self)->Option<&dyn Fn()->std::io::Result<()>>{Some(self.checkpoint)}
 fn checkpoint(&self)->Result<(),Self::Error>{(self.checkpoint)().map_err(Self::Error::Operational)}
 fn policy_failure(&self,failure:Self::Error)->Self::Error{failure}
 fn resource(&self,message:&'static str)->Self::Error{Self::Error::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,message))}
 fn prefix_with_budget<T>(&self,archive:&BodyArchive,identity:dm_ir::ProcedureIdentity,_:Option<&ReportBudget>,consume:impl FnOnce(InitialSettingPrefix<'_>)->T)->Result<T,Self::Error>{
  self.checkpoint()?;
  if !std::ptr::eq(self.archive,archive){return Err("current Original callee archive differs".into())}
  let ordinal=archive.callables().ordinal_for_identity_using(identity,&mut||self.checkpoint())?.ok_or("current Original callee occurrence absent")?;
  let pending=match self.obtain{
   Some(obtain)=>archive.with_current_body_checked_in(ordinal,self.admission,&mut(),|_,input|obtain(input),|_,body|body.with_initial_setting_prefix(identity,self.admission,consume)),
   None=>archive.with_current_body_checked(ordinal,self.admission,|body|body.with_initial_setting_prefix(identity,self.admission,consume)),
  };
  pending.map_err(|actual|match actual{
   BodySyntaxFailure::Operational(actual)=>Self::Error::Operational(actual),
   BodySyntaxFailure::Syntax(actual)=>actual.message.into(),
  })
 }
}

#[cfg(test)]mod return_binding_ownership_tests{
 use super::*;
 #[test]fn complete_return_binding_ownership_is_not_the_selected_directive_flag(){
  let legacy=Compatibility::<String>::new();assert!(!legacy.owns_return_expression_binding());assert!(!legacy.owns_directive_binding());let poll=||Ok(());let selected=Policy{checkpoint:&poll};assert!(selected.owns_directive_binding());assert!(!selected.owns_return_expression_binding());let complete=Original(selected);assert!(complete.owns_return_expression_binding());assert!(complete.with_budget(None).owns_return_expression_binding());assert!((&complete).owns_return_expression_binding());
 }
}

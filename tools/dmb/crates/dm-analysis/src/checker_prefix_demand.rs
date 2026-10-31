//! Typed body transport for the SAME original prefix/return policy.
use dm_tree::frontend::{BodyArchive,BodySyntax,BodySyntaxInput,BodySyntaxFailure,InitialSettingPrefix};
use crate::checker_effects::{ExecutionAdmission,output::ReportBudget};
use std::sync::Arc;
pub(crate) type BodyLoan<'a>=dyn Fn(&Arc<BodySyntaxInput>,&ExecutionAdmission)->Result<Arc<BodySyntax>,BodySyntaxFailure>+'a;
pub(crate) trait Demand{
 type Error:From<String>+for<'a>From<&'a str>;
 fn profile(&self)->Option<dm_tree::checker_builtins::ValidatedCheckerProfile<'_>>{None}
 fn validate_profile(&self,tree:&dm_tree::SemanticTree,profile:dm_ir::PackedU128)->Result<(),dm_tree::checker_builtins::CheckerBuiltinError>{match self.profile(){Some(checked)=>checked.require(tree,profile),None=>tree.validate_checker_builtin_profile(profile)}}
 fn resource(&self,message:&'static str)->Self::Error;
 fn prefix_with_budget<T>(&self,archive:&BodyArchive,identity:dm_ir::ProcedureIdentity,budget:Option<&ReportBudget>,consume:impl FnOnce(InitialSettingPrefix<'_>)->T)->Result<T,Self::Error>;
 fn prefix<T>(&self,archive:&BodyArchive,identity:dm_ir::ProcedureIdentity,consume:impl FnOnce(InitialSettingPrefix<'_>)->T)->Result<T,Self::Error>{self.prefix_with_budget(archive,identity,None,consume)}
 fn with_budget<'b>(&'b self,budget:Option<&'b ReportBudget>)->Bounded<'b,Self> where Self:Sized{Bounded{demand:self,budget}}
}
pub(crate) struct Bounded<'a,D>{demand:&'a D,budget:Option<&'a ReportBudget>}
impl<D:Demand> Demand for Bounded<'_,D>{type Error=D::Error;fn profile(&self)->Option<dm_tree::checker_builtins::ValidatedCheckerProfile<'_>>{self.demand.profile()}fn resource(&self,message:&'static str)->Self::Error{self.demand.resource(message)}fn prefix_with_budget<T>(&self,archive:&BodyArchive,identity:dm_ir::ProcedureIdentity,budget:Option<&ReportBudget>,consume:impl FnOnce(InitialSettingPrefix<'_>)->T)->Result<T,Self::Error>{self.demand.prefix_with_budget(archive,identity,budget.or(self.budget),consume)}}
pub(crate) struct Compatibility<E=String>(std::marker::PhantomData<fn()->E>);
impl<E> Compatibility<E>{pub(crate) fn new()->Self{Self(std::marker::PhantomData)}}
impl<E:From<String>+for<'a>From<&'a str>> Demand for Compatibility<E>{type Error=E;fn resource(&self,message:&'static str)->E{message.into()}fn prefix_with_budget<T>(&self,archive:&BodyArchive,identity:dm_ir::ProcedureIdentity,_budget:Option<&ReportBudget>,consume:impl FnOnce(InitialSettingPrefix<'_>)->T)->Result<T,E>{archive.with_initial_setting_prefix(identity,consume).map_err(E::from)}}
pub(crate) struct Checked<'a>{pub(crate) body:&'a BodyLoan<'a>,pub(crate) admission:&'a ExecutionAdmission,pub(crate) profile:dm_tree::checker_builtins::ValidatedCheckerProfile<'a>}
impl Demand for Checked<'_>{type Error=crate::policy_body_demand::PolicyFailure;fn profile(&self)->Option<dm_tree::checker_builtins::ValidatedCheckerProfile<'_>>{Some(self.profile)}fn resource(&self,message:&'static str)->Self::Error{Self::Error::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,message))}fn prefix_with_budget<T>(&self,archive:&BodyArchive,identity:dm_ir::ProcedureIdentity,budget:Option<&ReportBudget>,consume:impl FnOnce(InitialSettingPrefix<'_>)->T)->Result<T,Self::Error>{
 let view=budget.map_or_else(||self.admission.current_view(),ReportBudget::admission_view);
 if !self.admission.same_control(&view){return Err(Self::Error::Operational(std::io::Error::new(std::io::ErrorKind::InvalidInput,"effect prefix scratch view has another admission")))}
 archive.with_initial_setting_prefix_using(identity,|archive,ordinal|archive.parse_checked_using(ordinal,&|input:&std::sync::Arc<dm_tree::frontend::BodySyntaxInput>|(self.body)(input,&view)).map_err(|error|match error{BodySyntaxFailure::Syntax(error)=>Self::Error::from(error.message),BodySyntaxFailure::Operational(actual)=>Self::Error::Operational(actual)}),consume)
}}
impl<D:Demand+?Sized> Demand for &D{type Error=D::Error;fn profile(&self)->Option<dm_tree::checker_builtins::ValidatedCheckerProfile<'_>>{(**self).profile()}fn resource(&self,message:&'static str)->Self::Error{(**self).resource(message)}fn prefix_with_budget<T>(&self,archive:&BodyArchive,identity:dm_ir::ProcedureIdentity,budget:Option<&ReportBudget>,consume:impl FnOnce(InitialSettingPrefix<'_>)->T)->Result<T,Self::Error>{(**self).prefix_with_budget(archive,identity,budget,consume)}}

//! Operation-local produced source-root questions; not semantic answers.
use super::*;
use crate::initializer_policy::InitializerFailure;
use dm_tree::frontend::{OriginalInitializerExpression,OriginalInitializerRootProvenance,OriginalAbiExpressionProvenance,OriginalAbiExpressionKind,OriginalAbiSourceInput};
#[derive(Clone,Copy)]
pub(in crate::driver_facts) enum RootSubject{Declaration{owner:dm_ir::SymbolId,name:dm_ir::SymbolId},ProcedureStatic(dm_ir::ProcedureStaticIdentity)}
pub(in crate::driver_facts) trait RootObserver:Sync{fn record(&self,subject:RootSubject,root:&OriginalInitializerExpression<'_>,a:&dm_syntax::SettingAdmission<'_>)->Result<(),InitializerFailure>;}
enum RootRecord{Top(OriginalAbiExpressionProvenance),Selected{subject:RootSubject,root:OriginalInitializerRootProvenance}}
struct RootRows{rows:Vec<RootRecord>,lease:dm_syntax::SettingRootLease}
#[derive(Default)]
pub(in crate::driver_facts) struct RootCapture{rows:std::sync::Mutex<Option<RootRows>>}
pub(crate) struct SourceUnitWitness{roots:RootRows}
fn body_failure(error:dm_tree::frontend::BodySyntaxFailure)->InitializerFailure{match error{dm_tree::frontend::BodySyntaxFailure::Operational(actual)=>InitializerFailure::Operational(actual),dm_tree::frontend::BodySyntaxFailure::Syntax(source)=>InitializerFailure::Unsupported(source.message)}}
fn abi_failure(error:InitializerFailure)->AbiError{match error{InitializerFailure::Operational(actual)=>AbiError::operational(actual),InitializerFailure::Unsupported(reason)=>AbiError::unsupported(reason)}}
fn checked(a:&dm_syntax::SettingAdmission<'_>)->Result<(),InitializerFailure>{let result=a.checkpoint();if let Some(actual)=a.take_operational_error(){return Err(InitializerFailure::Operational(actual))}result.map_err(InitializerFailure::Operational)}
impl RootRows{
 fn empty(a:&dm_syntax::SettingAdmission<'_>)->Result<Self,InitializerFailure>{let lease=a.reserve(0).map_err(|proxy|InitializerFailure::Operational(a.take_operational_error().unwrap_or(proxy)))?;Ok(Self{rows:Vec::new(),lease})}
 fn admit(&mut self,weak:usize,a:&dm_syntax::SettingAdmission<'_>)->Result<(),InitializerFailure>{
  checked(a)?;let next=if self.rows.len()==self.rows.capacity(){Some(self.rows.capacity().max(4).checked_mul(2).ok_or_else(||InitializerFailure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,"ABI root roster capacity overflow")))?)}else{None};
  let growth=next.unwrap_or(0).checked_mul(std::mem::size_of::<RootRecord>()).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(weak)).ok_or_else(||InitializerFailure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,"ABI root roster charge overflow")))?;
  a.grow(&mut self.lease,growth).map_err(|proxy|InitializerFailure::Operational(a.take_operational_error().unwrap_or(proxy)))?;
  if let Some(next)=next{let mut rows=Vec::new();rows.try_reserve_exact(next).map_err(|error|InitializerFailure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,error)))?;if rows.capacity()>next*4{return Err(InitializerFailure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,"ABI root roster allocator exceeds preadmitted capacity")))}rows.append(&mut self.rows);self.rows=rows;}Ok(())
 }
}
impl RootCapture{
 fn append(&self,weak:usize,a:&dm_syntax::SettingAdmission<'_>,make:impl FnOnce()->Result<RootRecord,InitializerFailure>)->Result<(),InitializerFailure>{let mut rows=self.rows.lock().unwrap_or_else(|e|e.into_inner());if rows.is_none(){*rows=Some(RootRows::empty(a)?)}let rows=rows.as_mut().expect("initialized");rows.admit(weak,a)?;let record=make()?;checked(a)?;rows.rows.push(record);Ok(())}
 pub(in crate::driver_facts) fn top(&self,input:&OriginalAbiSourceInput<'_>,kind:OriginalAbiExpressionKind,expression:&dm_ir::SymbolicExpression,root:&dm_syntax::SettingExpression,a:&dm_syntax::SettingAdmission<'_>)->Result<(),InitializerFailure>{self.append(OriginalAbiExpressionProvenance::weak_backing_charge(),a,||input.expression_provenance(kind,expression,root).map(RootRecord::Top).map_err(body_failure))}
 // Only the successful policy return reaches this consuming completion boundary.
 pub(super) fn complete(self,source:&OriginalAbiSources<'_>)->Result<SourceUnitWitness,AbiError>{let mut roots=self.rows.into_inner().unwrap_or_else(|e|e.into_inner());source.context.with_admission(&mut |a|{checked(a).map_err(|error|match error{InitializerFailure::Operational(actual)=>dm_tree::frontend::BodySyntaxFailure::Operational(actual),InitializerFailure::Unsupported(reason)=>dm_tree::frontend::BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidData,reason))})?;if roots.as_ref().is_some_and(|rows|!a.matches_lease_domain(&rows.lease)){return Err(dm_tree::frontend::BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidInput,"ABI produced roots use a foreign budget")))}if roots.is_none(){roots=Some(RootRows::empty(a).map_err(|e|match e{InitializerFailure::Operational(actual)=>dm_tree::frontend::BodySyntaxFailure::Operational(actual),InitializerFailure::Unsupported(reason)=>dm_tree::frontend::BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidData,reason))})?)}Ok(())}).map_err(|e|abi_failure(body_failure(e)))?;Ok(SourceUnitWitness{roots:roots.expect("completed admission")})}
}
impl RootObserver for RootCapture{fn record(&self,subject:RootSubject,root:&OriginalInitializerExpression<'_>,a:&dm_syntax::SettingAdmission<'_>)->Result<(),InitializerFailure>{self.append(root.provenance_weak_backing_charge(),a,||Ok(RootRecord::Selected{subject,root:root.provenance()}))}}
impl SourceUnitWitness{
 pub(super) fn accepts(&self,source:&OriginalAbiSources<'_>,body:&dm_tree::frontend::BodyOccurrence,metadata:&dm_ir::ProcedureMetadata,evaluator:&DriverEvaluator<'_>)->Result<bool,AbiError>{
  let input=source.context.abi_source_input(body,metadata).map_err(|e|abi_failure(body_failure(e)))?;let mut accepted=false;
  source.context.with_admission(&mut|a|{
   let attempt=(||->Result<bool,InitializerFailure>{checked(a)?;if !a.matches_lease_domain(&self.roots.lease){return Ok(false)}
    for record in &self.roots.rows{checked(a)?;let matches=match record{
     RootRecord::Top(root)=>root.matches(&input,a).map_err(body_failure)?,
     RootRecord::Selected{subject,root}=>match subject{
      RootSubject::Declaration{owner,name}=>{let dm_ir::ResolvedMeaning::Member{owner:actual,name:actual_name,data,..}=evaluator.resolver.resolve(dm_ir::ResolveQuery::Var{owner:*owner,name:*name})else{return Ok(false)};if actual!=*owner||actual_name!=*name{return Ok(false)}let selected=source.context.selected_admitted(*owner,*name,&data,a).map_err(body_failure)?;root.matches_declaration(&selected,a).map_err(body_failure)?},
      RootSubject::ProcedureStatic(identity)=>{let Some(receipt)=source.startup.source_static_receipt(body.declaration)else{return Ok(false)};let dm_ir::ResolvedMeaning::ProcedureStatic(data)=evaluator.resolver.resolve(dm_ir::ResolveQuery::ProcedureStatic{procedure:identity.procedure,name:identity.name})else{return Ok(false)};if data.identity!=*identity{return Ok(false)}let selected=source.context.selected_static_admitted(receipt,*identity,&data,a).map_err(body_failure)?;root.matches_declaration(&selected,a).map_err(body_failure)?}
     }
    };if !matches{return Ok(false)}}checked(a)?;Ok(true)})();
   match attempt{Err(InitializerFailure::Operational(actual))=>Err(dm_tree::frontend::BodySyntaxFailure::Operational(actual)),Err(InitializerFailure::Unsupported(_))=>{accepted=false;Ok(())},Ok(result)=>{accepted=result;Ok(())}}
  }).map_err(|e|abi_failure(body_failure(e)))?;Ok(accepted)
 }
 pub(crate) fn visit_storage(&self,mut visit:impl FnMut(usize,usize)){visit(self.roots.rows.as_ptr() as usize,self.roots.rows.capacity()*std::mem::size_of::<RootRecord>());for row in &self.roots.rows{match row{RootRecord::Top(root)=>root.visit_storage(&mut visit),RootRecord::Selected{root,..}=>root.visit_storage(&mut visit)}}self.roots.lease.visit_counter_storage(visit)}
}

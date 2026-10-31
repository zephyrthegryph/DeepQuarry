//! Resource/source admission for existing initializer stage and incremental hits.
//! Semantic keys/answer versions remain separately mandatory. No scalar values,
//! parsed source, semantic rows or independent cache/model live in this receipt.
use dm_tree::frontend::{BodySyntaxFailure,ColdFrontend,OriginalInitializerRootProvenance,OriginalInitializerExpressionInput,OriginalInitializerDimensionInput};
#[derive(Clone,Copy,PartialEq,Eq)]enum Question{Rhs(usize),Dimension{ordinal:usize,suffix:usize}}
struct Record{question:Question,root:OriginalInitializerRootProvenance}
struct Rows{records:Vec<Record>,lease:dm_syntax::SettingRootLease}
pub(crate) struct SourceStageWitness{rows:Rows}
enum Input<'source>{Rhs(OriginalInitializerExpressionInput<'source>),Dimension(OriginalInitializerDimensionInput<'source>)}
impl Input<'_>{fn prepare(&self,a:&dm_syntax::SettingAdmission<'_>)->Result<dm_tree::frontend::OriginalInitializerExpression<'_>,BodySyntaxFailure>{match self{Self::Rhs(input)=>input.prepare(a),Self::Dimension(input)=>input.prepare(a)}}fn matches(&self,root:&OriginalInitializerRootProvenance,a:&dm_syntax::SettingAdmission<'_>)->Result<bool,BodySyntaxFailure>{match self{Self::Rhs(input)=>root.matches_initializer(input,a),Self::Dimension(input)=>root.matches_dimension(input,a)}}}
fn checkpoint(a:&dm_syntax::SettingAdmission<'_>)->Result<(),BodySyntaxFailure>{let result=a.checkpoint();if let Some(actual)=a.take_operational_error(){return Err(BodySyntaxFailure::Operational(actual))}result.map_err(BodySyntaxFailure::Operational)}
fn oom(message:&'static str)->BodySyntaxFailure{BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,message))}
fn questions<'source>(front:&'source ColdFrontend,startup:&'source crate::startup::OriginalStartup<'source>,a:&dm_syntax::SettingAdmission<'_>,mut visit:impl FnMut(Question,Input<'source>)->Result<bool,BodySyntaxFailure>)->Result<bool,BodySyntaxFailure>{
 let context=front.original_issued_initializer_context(startup.issued_initializer_plan())?;
 for(ordinal,write)in startup.plan().writes.iter().enumerate(){checkpoint(a)?;
  if matches!(&write.value,dm_ir::InitializerValue::Expression(_)){if !visit(Question::Rhs(ordinal),Input::Rhs(context.input(ordinal)?))?{return Ok(false)}}
  if write.declared_array.is_some(){for row in context.dimensions(ordinal)?{checkpoint(a)?;let(suffix,input)=row?;if let Some(input)=input{if !visit(Question::Dimension{ordinal,suffix},Input::Dimension(input))?{return Ok(false)}}}}
 }checkpoint(a)?;Ok(true)
}
impl Rows{
 fn new(a:&dm_syntax::SettingAdmission<'_>)->Result<Self,BodySyntaxFailure>{let lease=a.reserve(0).map_err(|proxy|BodySyntaxFailure::Operational(a.take_operational_error().unwrap_or(proxy)))?;Ok(Self{records:Vec::new(),lease})}
 fn push(&mut self,question:Question,root:&dm_tree::frontend::OriginalInitializerExpression<'_>,a:&dm_syntax::SettingAdmission<'_>)->Result<(),BodySyntaxFailure>{
  checkpoint(a)?;let capacity=if self.records.len()==self.records.capacity(){Some(self.records.capacity().max(4).checked_mul(2).ok_or_else(||oom("source stage question capacity overflow"))?)}else{None};
  let charge=capacity.unwrap_or(0).checked_mul(std::mem::size_of::<Record>()).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(root.provenance_weak_backing_charge())).ok_or_else(||oom("source stage question charge overflow"))?;
  a.grow(&mut self.lease,charge).map_err(|proxy|BodySyntaxFailure::Operational(a.take_operational_error().unwrap_or(proxy)))?;
  if let Some(capacity)=capacity{let mut next=Vec::new();next.try_reserve_exact(capacity).map_err(|error|BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,error)))?;if next.capacity()>capacity*4{return Err(oom("source stage allocator exceeds preadmitted capacity"))}next.append(&mut self.records);self.records=next;}
  self.records.push(Record{question,root:root.provenance()});Ok(())
 }
}
impl SourceStageWitness{
 // Called only after the original initializer producer completed successfully.
 // Its RHS/dimension roots are already prepared; this makes one existing-plan
 // traversal to retain QUESTIONS, never cloned plan rows or a second model.
 pub(super) fn capture(front:&ColdFrontend,startup:&crate::startup::OriginalStartup<'_>)->Result<Self,BodySyntaxFailure>{
  let context=front.original_declaration_expression_context()?;let mut rows=None;
  context.with_admission(&mut|a|{let mut captured=Rows::new(a)?;questions(front,startup,a,|question,input|{let root=input.prepare(a)?;captured.push(question,&root,a)?;Ok(true)})?;checkpoint(a)?;rows=Some(captured);Ok(())})?;
  rows.map(|rows|Self{rows}).ok_or_else(||BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidData,"source stage admission omitted operation")))
 }
 pub(crate) fn accepts(&self,front:&ColdFrontend,startup:&crate::startup::OriginalStartup<'_>)->Result<bool,BodySyntaxFailure>{
  let context=front.original_declaration_expression_context()?;let mut accepted=false;
  context.with_admission(&mut|a|{checkpoint(a)?;if !a.matches_lease_domain(&self.rows.lease){return Ok(())}let mut at=0;
   let result=questions(front,startup,a,|question,input|{let Some(record)=self.rows.records.get(at)else{return Ok(false)};if record.question!=question{return Ok(false)}if !input.matches(&record.root,a)?{return Ok(false)}at+=1;Ok(true)});
   match result{Err(BodySyntaxFailure::Operational(actual))=>Err(BodySyntaxFailure::Operational(actual)),Err(BodySyntaxFailure::Syntax(_))=>{checkpoint(a)?;Ok(())},Ok(matched)=>{checkpoint(a)?;accepted=matched&&at==self.rows.records.len();Ok(())}}
  })?;Ok(accepted)
 }
 pub(crate) fn visit_storage(&self,mut visit:impl FnMut(usize,usize)){visit(self.rows.records.as_ptr() as usize,self.rows.records.capacity()*std::mem::size_of::<Record>());for record in &self.rows.records{record.root.visit_storage(&mut visit)}self.rows.lease.visit_counter_storage(visit)}
}

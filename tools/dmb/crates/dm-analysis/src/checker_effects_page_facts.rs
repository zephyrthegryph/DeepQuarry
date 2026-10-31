//! Retained unique effect facts of ONE actual original contribution window.
//! No AST, source bytes, BodyEffects/Input owner or independent proc model.
use super::*;
use crate::policy_body_demand::PolicyFailure;
use dm_tree::frontend::{BodySyntax,BodySyntaxInput,BodySyntaxFailure,OriginalArchiveOwner};
use std::{io,mem::size_of};
struct Row{ordinal:usize,id:ProcedureIdentity,parent:Option<EffectTarget>,direct:bool,builtin:bool,start:usize,end:usize}
pub struct EffectPageFacts{owner:OriginalArchiveOwner,profile:PackedU128,start:usize,total:usize,rows:Vec<Row>,calls:Vec<ProcedureIdentity>}
impl EffectPageFacts{
 pub fn start(&self)->usize{self.start}
 pub fn len(&self)->usize{self.rows.len()}
 pub fn total(&self)->usize{self.total}
 pub fn ordinal(&self,index:usize)->Option<usize>{Some(self.rows.get(index)?.ordinal)}
 pub fn procedure(&self,index:usize)->Option<ProcedureIdentity>{Some(self.rows.get(index)?.id)}
 pub fn has_effect_seed(&self,index:usize)->Option<bool>{let row=self.rows.get(index)?;Some(row.direct||row.builtin)}
 pub fn has_direct_effect(&self,index:usize)->Option<bool>{Some(self.rows.get(index)?.direct)}
 pub fn source_calls(&self,index:usize)->Option<&[ProcedureIdentity]>{let row=self.rows.get(index)?;self.calls.get(row.start..row.end)}
 pub fn source_parent(&self,index:usize)->Option<ProcedureIdentity>{match self.rows.get(index)?.parent{Some(EffectTarget::Source(id))=>Some(id),_=>None}}
 pub fn validate(&self,source:&EffectSource<'_>)->Result<(),PolicyFailure>{
  if !self.owner.matches(source.archive)||self.profile!=source.profile||self.total!=source.len()||self.start.checked_add(self.len()).is_none_or(|end|end>source.len()){return Err("effect page facts are not current original source/profile/range".into())}
  for(index,row)in self.rows.iter().enumerate(){if source.original_ordinal(self.start+index)!=Some(row.ordinal){return Err("effect page ordinal roster differs".into())}}Ok(())
 }
 pub fn retained_charge(&self)->Option<usize>{size_of::<Self>().checked_add(self.rows.capacity().checked_mul(size_of::<Row>())?)?.checked_add(self.calls.capacity().checked_mul(size_of::<ProcedureIdentity>())?)?.checked_add(self.owner.fixed_retention_capacity()?)}
 pub fn visit_storage(&self,mut visit:impl FnMut(Storage)){
  visit(Storage::Buffer{owner:"purity.page_rows",address:self.rows.as_ptr() as usize,logical:self.rows.len()*size_of::<Row>(),capacity:self.rows.capacity()*size_of::<Row>()});
  visit(Storage::Buffer{owner:"purity.page_calls",address:self.calls.as_ptr() as usize,logical:self.calls.len()*size_of::<ProcedureIdentity>(),capacity:self.calls.capacity()*size_of::<ProcedureIdentity>()});
  self.owner.visit_storage(|owner,address,logical,capacity|visit(Storage::Buffer{owner,address,logical,capacity}));
 }
 pub fn compute_checked(source:&EffectSource<'_>,start:usize,width:usize,resolver:&(impl Resolver+?Sized),admission:&ExecutionAdmission,checkpoint:&mut impl FnMut()->io::Result<()>,body:&dyn Fn(&Arc<BodySyntaxInput>,&ExecutionAdmission)->Result<Arc<BodySyntax>,BodySyntaxFailure>)->Result<Self,PolicyFailure>{
  let mut built=None;
  source.with_page_checked(start,width,resolver,admission,checkpoint,body,|page|{
   let budget=ReportBudget::for_operation(admission);budget.charge(page.live_charge()).map_err(|_|resource(&budget,"effect page retained overlap exhausted"))?;
   let owner=source.archive.original_owner_witness();let fixed=owner.fixed_retention_capacity().and_then(|n|n.checked_add(size_of::<Self>())).ok_or_else(||resource(&budget,"effect page witness capacity overflow"))?;budget.charge(fixed).map_err(|_|resource(&budget,"effect page witness admission exhausted"))?;
   let count=(0..page.len()).try_fold(0usize,|count,index|{let row=page.contribution(index)?.ok_or("effect page contribution missing")?;count.checked_add(row.source_call_count()).ok_or_else(||resource(&budget,"effect page calls overflow"))})?;
   let mut rows=allocate(page.len(),&budget)?;let mut calls=allocate(count,&budget)?;
   for index in 0..page.len(){let row=page.contribution(index)?.ok_or("effect page contribution missing")?;let begin=calls.len();row.try_source_calls(|id|{calls.push(id);Ok::<_,PolicyFailure>(())})?;rows.push(Row{ordinal:row.ordinal(),id:row.procedure(),parent:row.parent(),direct:row.has_direct_effect(),builtin:row.has_builtin_effect_call(),start:begin,end:calls.len()});}
   built=Some(Self{owner,profile:source.profile,start:page.start(),total:page.total(),rows,calls});Ok(())
  })?;
  built.ok_or_else(||"effect page factory omitted original contribution".into())
 }
}
fn resource(b:&ReportBudget,message:&'static str)->PolicyFailure{b.deny();PolicyFailure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message))}
fn allocate<T>(count:usize,b:&ReportBudget)->Result<Vec<T>,PolicyFailure>{let bound=count.checked_mul(size_of::<T>()).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(size_of::<Vec<T>>()));b.charge(bound.ok_or_else(||resource(b,"effect page retained array overflow"))?).map_err(|_|resource(b,"effect page retained array admission exhausted"))?;let mut rows=Vec::new();rows.try_reserve_exact(count).map_err(|actual|{b.deny();PolicyFailure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,actual))})?;if rows.capacity()>count.saturating_mul(4){return Err(resource(b,"effect page retained array exposed excess"))}Ok(rows)}

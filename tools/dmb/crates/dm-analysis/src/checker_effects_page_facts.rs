//! Retained unique effect facts of ONE actual original contribution window.
//! No AST, source bytes, strong Input/archive owner or independent proc model.
//! Original scalar BodyEffects metadata is retained for the shared report judge.
use super::*;
use crate::policy_body_demand::PolicyFailure;
use dm_tree::frontend::{BodySyntax,BodySyntaxInput,BodySyntaxFailure,OriginalArchiveOwner};
use std::{io,mem::size_of};
struct Row{original:Arc<BodyEffects>,ordinal:usize,id:ProcedureIdentity,parent:Option<EffectTarget>,direct:bool,builtin:bool,start:usize,end:usize}
pub struct EffectPageFacts{owner:OriginalArchiveOwner,profile:PackedU128,start:usize,total:usize,rows:Vec<Row>,calls:Vec<ProcedureIdentity>}
impl EffectPageFacts{
 pub fn start(&self)->usize{self.start}
 pub fn len(&self)->usize{self.rows.len()}
 pub fn total(&self)->usize{self.total}
 pub fn ordinal(&self,index:usize)->Option<usize>{Some(self.rows.get(index)?.ordinal)}
 pub fn procedure(&self,index:usize)->Option<ProcedureIdentity>{Some(self.rows.get(index)?.id)}
 pub fn parent(&self,index:usize)->Option<Option<EffectTarget>>{Some(self.rows.get(index)?.parent)}
 pub fn has_builtin_effect_call(&self,index:usize)->Option<bool>{Some(self.rows.get(index)?.builtin)}
 pub fn has_effect_seed(&self,index:usize)->Option<bool>{let row=self.rows.get(index)?;Some(row.direct||row.builtin)}
 pub fn has_direct_effect(&self,index:usize)->Option<bool>{Some(self.rows.get(index)?.direct)}
 pub fn source_calls(&self,index:usize)->Option<&[ProcedureIdentity]>{let row=self.rows.get(index)?;self.calls.get(row.start..row.end)}
 pub fn source_parent(&self,index:usize)->Option<ProcedureIdentity>{match self.rows.get(index)?.parent{Some(EffectTarget::Source(id))=>Some(id),_=>None}}
 pub fn validate(&self,source:&EffectSource<'_>)->Result<(),PolicyFailure>{
  if !self.owner.matches(source.archive)||self.profile!=source.profile||self.total!=source.len()||self.start.checked_add(self.len()).is_none_or(|end|end>source.len()){return Err("effect page facts are not current original source/profile/range".into())}
  for(index,row)in self.rows.iter().enumerate(){if source.original_ordinal(self.start+index)!=Some(row.ordinal){return Err("effect page ordinal roster differs".into())}}Ok(())
 }
 pub(super) fn current<'view,'source>(&'view self,source:&'view EffectSource<'source>)->Result<CurrentEffectPage<'view,'source>,PolicyFailure>{self.validate(source)?;Ok(CurrentEffectPage{facts:self,_source:source})}
 pub fn report_fingerprint(&self)->u128{let mut hash=fingerprint::Fingerprint::new(b"original-effect-page-report-fields-v1");hash.u128(self.profile.get());hash.usize(self.start);hash.usize(self.total);hash.usize(self.rows.len());for row in &self.rows{hash.usize(row.ordinal);hash.id(row.id);hash.parent(row.parent);hash.byte(u8::from(row.direct));hash.byte(u8::from(row.builtin));hash.usize(row.start);hash.usize(row.end);hash.body(&row.original);}hash.usize(self.calls.len());for id in &self.calls{hash.id(*id)}hash.finish()}
 pub fn retained_charge(&self)->Option<usize>{let originals=self.rows.iter().try_fold(size_of::<EffectInput>(),|n,row|n.checked_add(row.original.charge()))?;size_of::<Self>().checked_add(originals)?.checked_add(self.rows.capacity().checked_mul(size_of::<Row>())?)?.checked_add(self.calls.capacity().checked_mul(size_of::<ProcedureIdentity>())?)?.checked_add(self.owner.fixed_retention_capacity()?)}
 pub fn visit_storage(&self,mut visit:impl FnMut(Storage)){
  visit(Storage::Buffer{owner:"purity.page_rows",address:self.rows.as_ptr() as usize,logical:self.rows.len()*size_of::<Row>(),capacity:self.rows.capacity()*size_of::<Row>()});
  visit(Storage::Buffer{owner:"purity.page_calls",address:self.calls.as_ptr() as usize,logical:self.calls.len()*size_of::<ProcedureIdentity>(),capacity:self.calls.capacity()*size_of::<ProcedureIdentity>()});
  for row in &self.rows{row.original.visit_storage(&mut visit)}
  // Every retained original body refers weakly to the SAME page input. Its
  // payload/order/archive have dropped; only this fixed allocation remains.
  if let Some(row)=self.rows.first(){visit(Storage::Buffer{owner:"purity.page_original_input_weak",address:row.original.input.as_ptr() as usize,logical:size_of::<EffectInput>(),capacity:size_of::<EffectInput>()});}
  self.owner.visit_storage(|owner,address,logical,capacity|visit(Storage::Buffer{owner,address,logical,capacity}));
 }
 pub fn compute_checked(source:&EffectSource<'_>,start:usize,width:usize,resolver:&(impl Resolver+?Sized),admission:&ExecutionAdmission,checkpoint:&mut impl FnMut()->io::Result<()>,body:&dyn Fn(&Arc<BodySyntaxInput>,&ExecutionAdmission)->Result<Arc<BodySyntax>,BodySyntaxFailure>)->Result<Self,PolicyFailure>{
  let mut built=None;
  source.with_page_checked(start,width,resolver,admission,checkpoint,body,|page|{
   built=Some(Self::from_original_page(source,admission,&page)?);Ok(())
  })?;
  built.ok_or_else(||"effect page factory omitted original contribution".into())
 }
 fn from_original_page(source:&EffectSource<'_>,admission:&ExecutionAdmission,page:&EffectSourcePage<'_>)->Result<Self,PolicyFailure>{
   let budget=ReportBudget::for_operation(admission);budget.charge(page.live_charge()).map_err(|_|resource(&budget,"effect page retained overlap exhausted"))?;
   let owner=source.archive.original_owner_witness();let fixed=owner.fixed_retention_capacity().and_then(|n|n.checked_add(size_of::<Self>())).ok_or_else(||resource(&budget,"effect page witness capacity overflow"))?;budget.charge(fixed).map_err(|_|resource(&budget,"effect page witness admission exhausted"))?;
   let count=(0..page.len()).try_fold(0usize,|count,index|{let row=page.contribution(index)?.ok_or("effect page contribution missing")?;count.checked_add(row.source_call_count()).ok_or_else(||resource(&budget,"effect page calls overflow"))})?;
   let mut rows=allocate(page.len(),&budget)?;let mut calls=allocate(count,&budget)?;
   for index in 0..page.len(){let row=page.contribution(index)?.ok_or("effect page contribution missing")?;let begin=calls.len();row.try_source_calls(|id|{calls.push(id);Ok::<_,PolicyFailure>(())})?;let original=page.retain_contribution(index)?.ok_or("effect page original contribution missing")?;rows.push(Row{original,ordinal:row.ordinal(),id:row.procedure(),parent:row.parent(),direct:row.has_direct_effect(),builtin:row.has_builtin_effect_call(),start:begin,end:calls.len()});}
   Ok(Self{owner,profile:source.profile,start:page.start(),total:page.total(),rows,calls})
 }

 pub fn compute_from_original_bodies<E>(source:&EffectSource<'_>,input:&Arc<EffectInput>,start:usize,width:usize,admission:&ExecutionAdmission,checkpoint:&mut impl FnMut()->io::Result<()>,obtain:&mut impl FnMut(usize,&ExecutionAdmission)->Result<Arc<BodyEffects>,E>)->Result<Self,source_pages::OriginalBodyReadFailure<E>>{
  let mut built=None;source.with_original_body_page_checked(input,start,width,admission,checkpoint,obtain,|page|{built=Some(Self::from_original_page(source,admission,&page)?);Ok(())})?;built.ok_or_else(||source_pages::OriginalBodyReadFailure::Policy("cached original page omitted its real contribution".into()))
 }
 pub fn with_original_body<T>(&self,index:usize,input:&Arc<EffectInput>,consume:impl FnOnce(&BodyEffects)->T)->Result<T,PolicyFailure>{if !input.is_original_checker_source(){return Err("ordinary page input cannot issue original checker body observations".into())}let body=&self.rows.get(index).ok_or("original page body index absent")?.original;body.validate(input)?;if body.original_evaluations!=1{return Err("original page body was not evaluated exactly once".into())}Ok(consume(body))}

}
fn resource(b:&ReportBudget,message:&'static str)->PolicyFailure{b.deny();PolicyFailure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message))}
fn allocate<T>(count:usize,b:&ReportBudget)->Result<Vec<T>,PolicyFailure>{let bound=count.checked_mul(size_of::<T>()).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(size_of::<Vec<T>>()));b.charge(bound.ok_or_else(||resource(b,"effect page retained array overflow"))?).map_err(|_|resource(b,"effect page retained array admission exhausted"))?;let mut rows=Vec::new();rows.try_reserve_exact(count).map_err(|actual|{b.deny();PolicyFailure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,actual))})?;if rows.capacity()>count.saturating_mul(4){return Err(resource(b,"effect page retained array exposed excess"))}Ok(rows)}

/// A borrowed loan to actual privately produced page facts. This grants no
/// source identity; consumers still validate the private current-source witness.
pub trait EffectPageRead{fn effect_page(&self)->&EffectPageFacts;}
impl EffectPageRead for EffectPageFacts{fn effect_page(&self)->&EffectPageFacts{self}}

/// One validated current source loan; metadata reads do not revalidate the
/// entire window per body and cannot outlive either the page or source borrow.
pub(super) struct CurrentEffectPage<'view,'source>{facts:&'view EffectPageFacts,_source:&'view EffectSource<'source>}
impl CurrentEffectPage<'_,'_>{pub(super) fn contribution(&self,index:usize)->Option<&BodyEffects>{self.facts.rows.get(index).map(|row|row.original.as_ref())}}

/// One original scalar contribution plus its ACTUAL retained page owner. The
/// body Arc is private and physically drops before the page's lease-bearing
/// loan. It contains no AST/raw-source/strong archive or semantic model owner.
pub(super) struct SourceBodyLoan<'view,'source,P>{body:Option<Arc<BodyEffects>>,page:Option<P>,_source:&'view EffectSource<'source>}
impl<P> std::ops::Deref for SourceBodyLoan<'_,'_,P>{type Target=BodyEffects;fn deref(&self)->&BodyEffects{self.body.as_deref().expect("sealed original contribution loan")}}
impl<P> Drop for SourceBodyLoan<'_,'_,P>{fn drop(&mut self){drop(self.body.take());drop(self.page.take());}}
impl<'view,'source,P:std::ops::Deref> SourceBodyLoan<'view,'source,P> where P::Target:EffectPageRead{
 pub(super) fn issue(source:&'view EffectSource<'source>,page:P,node:usize)->Result<Self,PolicyFailure>{let facts=page.effect_page();facts.validate(source)?;let local=node.checked_sub(facts.start).filter(|local|*local<facts.rows.len()).ok_or("report body outside current original page loan")?;let original=Arc::clone(&facts.rows[local].original);if source.original_ordinal(node)!=Some(original.ordinal)||facts.rows[local].id!=original.procedure{return Err("report body metadata differs from original page identity".into())}Ok(Self{body:Some(original),page:Some(page),_source:source})}
}

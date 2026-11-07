//! Current PAGE-backed access to the unique checker report judgement.
//! This is operation-local data access; the actual query caller still joins
//! the current summary/graph and retains the SAME family ledger.
use super::*;
use super::report_core::{ReportAccess,ReportBodyLoan,ReportBodyView,ReportSource};
use crate::policy_body_demand::PolicyFailure;
use std::{cell::RefCell,io,ops::Deref};


/// Resource operations on the caller's EXISTING family escrow. A scope may be
/// retired only after its temporary owners physically drop; errors/unwinds keep
/// the full reservation. These methods grant no source/semantic authority.
pub trait EffectReportWork{type Mark;fn reserve(&mut self,bytes:usize)->io::Result<()>;fn mark(&mut self)->io::Result<Self::Mark>;fn reconcile(&mut self,marker:Self::Mark,retained_delta:usize)->io::Result<()>;}
impl<T:EffectReportWork+?Sized> EffectReportWork for &mut T{type Mark=T::Mark;fn reserve(&mut self,bytes:usize)->io::Result<()>{(**self).reserve(bytes)}fn mark(&mut self)->io::Result<Self::Mark>{(**self).mark()}fn reconcile(&mut self,marker:Self::Mark,retained:usize)->io::Result<()>{(**self).reconcile(marker,retained)}}

pub(super) struct NativeReportAccess<'view,'source,B,F,R:?Sized,C,W>{
 pub(super) source:&'view EffectSource<'source>,
 pub(super) graph:&'view CurrentEffectGraph<'view,'source>,
 pub(super) summary:&'view OwnedCompactEffectSummary,
 pub(super) order:&'view crate::checker_order::ArchivedOrder<'source>,
 pub(super) rank:&'view [u32],pub(super) range:std::ops::Range<usize>,
 pub(super) read:F,pub(super) resolver:&'view R,pub(super) checkpoint:&'view RefCell<C>,pub(super) work:&'view RefCell<W>,pub(super) body:std::marker::PhantomData<B>,
}
impl<B,F,R:?Sized,C,W> NativeReportAccess<'_,'_,B,F,R,C,W> where R:Resolver,C:FnMut()->io::Result<()>,W:EffectReportWork{
 fn poll(&self)->Result<(),PolicyFailure>{(self.checkpoint.borrow_mut())().map_err(PolicyFailure::Operational)}
 fn parent(&self,target:EffectTarget)->Result<Option<EffectTarget>,PolicyFailure>{self.poll()?;match target{EffectTarget::Source(id)=>self.graph.parent(self.graph.node_for(id).ok_or("effect report source predecessor absent")?).ok_or_else(||"effect report source parent row absent".into()),EffectTarget::Builtin(_)=>Ok(original_target_parent_using(self.source.archive,self.source.profile,self.resolver,target,&mut||self.poll())?)}}
 fn is_override(&self,child:usize,target:EffectTarget)->Result<bool,PolicyFailure>{let catalog=dm_tree::checker_builtins::pinned_catalog().map_err(|e|PolicyFailure::from(format!("effect report original catalog: {e:?}")))?;if catalog.profile!=self.source.profile{return Err("effect report catalog profile differs".into())}let bound=self.graph.len().checked_add(catalog.declarations.len()).and_then(|n|n.checked_add(1)).ok_or_else(||PolicyFailure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"effect report predecessor coordinate overflow")))?;let mut at=self.graph.parent(child).ok_or("effect report child parent row absent")?;for _ in 0..bound{self.poll()?;let Some(parent)=at else{return Ok(false)};if parent==target{return Ok(true)}at=self.parent(parent)?;}Err("effect report predecessor cycle".into())}
}
impl<P> ReportBodyLoan for page_facts::SourceBodyLoan<'_, '_, P> {
 fn view(&self)->ReportBodyView<'_>{ReportBodyView::from(&**self)}
}
impl<'view,'source,B,F,R:?Sized,C,W> ReportAccess for NativeReportAccess<'view,'source,B,F,R,C,W> where B:ReportBodyLoan,F:Fn(usize,&ExecutionAdmission)->Result<B,PolicyFailure>,R:Resolver,C:FnMut()->io::Result<()>,W:EffectReportWork{
 type Error=PolicyFailure;type Scope=W::Mark;type Body<'a>=B where Self:'a;type Overrides<'a>=Vec<usize> where Self:'a;
 fn checkpoint(&self)->Result<(),PolicyFailure>{self.poll()}
 fn source(&self)->ReportSource<'_>{ReportSource{archive:self.source.archive,profile:self.source.profile}}
 fn group_mark(&self)->Result<Self::Scope,PolicyFailure>{self.work.borrow_mut().mark().map_err(PolicyFailure::Operational)}
 fn group_finished(&self,marker:Self::Scope,retained_delta:usize)->Result<(),PolicyFailure>{self.work.borrow_mut().reconcile(marker,retained_delta).map_err(PolicyFailure::Operational)}
 fn observes_allocations(&self)->bool{true}
 fn reserve(&self,bytes:usize)->Result<(),PolicyFailure>{self.poll()?;self.work.borrow_mut().reserve(bytes).map_err(PolicyFailure::Operational)}
 fn target_range(&self)->std::ops::Range<usize>{self.range.clone()}
 fn len(&self)->usize{self.graph.len()}
 fn ordered_node(&self,rank:usize)->Result<usize,PolicyFailure>{self.poll()?;let ordinal=self.order.ordinal(rank).ok_or("effect report ordered ordinal absent")?;let id=self.source.archive.callables().identity(ordinal).ok_or("effect report ordered identity absent")?;self.index(id)}
 fn body(&self,node:usize,live:&ExecutionAdmission)->Result<Self::Body<'_>,PolicyFailure>{self.poll()?;(self.read)(node,live)}
 fn index(&self,id:ProcedureIdentity)->Result<usize,PolicyFailure>{self.graph.node_for(id).ok_or_else(||"effect report current identity absent".into())}
 fn source_parent(&self,id:ProcedureIdentity,_:&ExecutionAdmission)->Result<Option<EffectTarget>,PolicyFailure>{self.poll()?;self.graph.parent(self.index(id)?).ok_or_else(||"effect report original predecessor absent".into())}
 fn has_effect(&self,node:usize)->Result<bool,PolicyFailure>{self.summary.node_has_effect(node).ok_or_else(||"effect report current summary row absent".into())}
 fn override_children(&self,node:usize,budget:&output::ReportBudgetWith<'_,PolicyFailure>)->Result<Vec<usize>,PolicyFailure>{
  self.poll()?;let target=EffectTarget::Source(self.graph.identity(node).ok_or("effect report override target absent")?);let mut count=0usize;while self.graph.successor(node,count)?.is_some(){self.poll()?;count=count.checked_add(1).ok_or_else(||PolicyFailure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"effect report successor count overflow")))?;}let bytes=count.checked_mul(std::mem::size_of::<usize>()).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(std::mem::size_of::<Vec<usize>>()+64)).ok_or("effect report override projection overflow")?;budget.charge(bytes)?;let mut children=Vec::new();children.try_reserve_exact(count).map_err(|e|PolicyFailure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,e)))?;if children.capacity()>count.saturating_mul(4){budget.deny();return Err(PolicyFailure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"effect report override projection exposed excess")))}
  let mut previous=None;for next in 0..count{self.poll()?;let child=self.graph.successor(node,next)?.ok_or("effect report current adjacency changed")?;if previous==Some(child){continue}previous=Some(child);let id=self.graph.identity(child).ok_or("effect report override identity absent")?;if self.graph.own_direct(child)!=Some(true)||id.name==SymbolId::of("New")||!self.is_override(child,target)?{continue}children.push(child);}
  // The graph's original-node successor order is not report order. This one
  // bounded scalar row uses the actual checker-order rank, never source names.
  crate::checker_order::sort_report_projection(&mut children,&self.rank, &mut||{self.poll()})?;Ok(children)
 }
 fn callable_point(&self,body:&ReportBodyView<'_>,missing:&'static str,budget:&output::ReportBudgetWith<'_,PolicyFailure>)->Result<(SourceNoteOrigin,Span),PolicyFailure>{self.poll()?;let origin=body.callable_origin.as_ref().map_err(|e|PolicyFailure::from(e.message()))?;let bytes=std::mem::size_of::<SourceNoteOrigin>().checked_add(std::mem::size_of::<std::path::PathBuf>()).and_then(|n|n.checked_add(origin.path.capacity())).and_then(|n|n.checked_add(128+2*std::mem::size_of::<usize>())).ok_or("effect report note capacity overflow")?;budget.charge(bytes)?;let header=body.opening_parenthesis.ok_or(missing)?;Ok((origin.clone(),header))}
}

/// Select the established report family; whole-checker phase composition is a
/// caller policy (body-immediate, sleep, then purity), not query request order.
#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub enum EffectReportPhase{Purity,Sleep}
/// One admitted projection for all windows of the same current graph.
pub struct EffectReportOrder<'graph,'source>{
 graph:&'graph RetainedEffectGraph,
 order:crate::checker_order::ArchivedOrder<'source>,
 rank:Vec<u32>,
}
impl EffectReportOrder<'_,'_>{
 pub fn retained_charge(&self)->Option<usize>{
  self.order.retained_charge()?.checked_add(std::mem::size_of::<Vec<u32>>())?
      .checked_add(self.rank.capacity().checked_mul(std::mem::size_of::<u32>())?)
 }
}

impl<'source> EffectSource<'source>{
 /// Borrow actual original PAGE contributions under the caller's SAME current
 /// graph/summary and family escrow. This returns data only: the query boundary
 /// must authenticate its summary receipt and recheck current source before any
 /// retained Outcome/writer publication. The observer reserves BEFORE each
 /// allocation and must remain alive while returned rows remain alive.
 pub fn report_pages_checked<P:std::ops::Deref+Clone,C:FnMut()->io::Result<()>,R:Resolver+?Sized,W:EffectReportWork>(&self,graph:&RetainedEffectGraph,summary:&OwnedCompactEffectSummary,phase:EffectReportPhase,resolver:&R,policy:&CheckerPolicy,admission:&ExecutionAdmission,checkpoint:&mut C,read:impl Fn(usize,usize,&ExecutionAdmission)->Result<P,PolicyFailure>,work:&mut W)->Result<Vec<Produced>,PolicyFailure> where P::Target:EffectPageRead{self.report_pages_window_checked(graph,summary,0,self.len(),phase,resolver,policy,admission,checkpoint,read,work)}
pub fn report_pages_window_checked<P:std::ops::Deref+Clone,C:FnMut()->io::Result<()>,R:Resolver+?Sized,W:EffectReportWork>(&self,graph:&RetainedEffectGraph,summary:&OwnedCompactEffectSummary,start:usize,count:usize,phase:EffectReportPhase,resolver:&R,policy:&CheckerPolicy,admission:&ExecutionAdmission,checkpoint:&mut C,read:impl Fn(usize,usize,&ExecutionAdmission)->Result<P,PolicyFailure>,work:&mut W)->Result<Vec<Produced>,PolicyFailure> where P::Target:EffectPageRead{
  let current = graph.current(self)?;
  let last_page = RefCell::new(None::<P>);
  let loan = |node:usize,live:&ExecutionAdmission| {
   let start=current.page_start(node).ok_or("effect report original page coordinate absent")?;
   let mut last=last_page.borrow_mut();
   let reuse=last.as_ref().is_some_and(|page|page.effect_page().start()==start&&node>=start&&node<start.saturating_add(page.effect_page().len()));
   let page=if reuse{last.as_ref().expect("current bounded page loan").clone()}else{
    let page=read(start,current.page_width(),live)?;page.effect_page().validate(self)?;*last=Some(page.clone());page
   };
   drop(last);
   page_facts::SourceBodyLoan::issue(self,page,node)
  };
  self.report_body_loans_window_checked(graph,summary,start,count,phase,resolver,policy,admission,checkpoint,loan,None,work)
 }

 pub fn report_replay_window_checked<C:FnMut()->io::Result<()>,R:Resolver+?Sized,W:EffectReportWork>(
  &self,graph:&RetainedEffectGraph,summary:&OwnedCompactEffectSummary,start:usize,count:usize,
  phase:EffectReportPhase,resolver:&R,policy:&CheckerPolicy,admission:&ExecutionAdmission,
  checkpoint:&mut C,replay:&CompactGraphReplay<'_>,work:&mut W,
 )->Result<Vec<Produced>,PolicyFailure>{
  if !Arc::ptr_eq(self.archive,replay.input().archive()) || self.profile!=replay.input().profile(){
   return Err("compact effect report replay belongs to another source".into())
  }
  let loan=|node:usize,_:&ExecutionAdmission|replay.body(self.original_ordinal(node).ok_or("compact report source ordinal absent")?);
  self.report_body_loans_window_checked(graph,summary,start,count,phase,resolver,policy,admission,checkpoint,loan,None,work)
 }

 pub fn report_order_checked<'graph,C:FnMut()->io::Result<()>,W:EffectReportWork>(
  &self,graph:&'graph RetainedEffectGraph,admission:&ExecutionAdmission,checkpoint:&mut C,work:&mut W,
 )->Result<EffectReportOrder<'graph,'source>,PolicyFailure>{
  let current=graph.current(self)?;
  let order=crate::checker_order::ArchivedOrder::build(self.archive,admission,checkpoint,&mut|bytes|work.reserve(bytes))?;if order.len()!=current.len(){return Err("effect report original order omits source contribution".into())}
   let budget=ReportBudget::for_operation(admission);budget.charge(order.retained_charge().ok_or("effect report retained order capacity overflow")?).map_err(|_|PolicyFailure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"effect report live order overlap denied")))?;let bytes=current.len().checked_mul(std::mem::size_of::<u32>()).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(std::mem::size_of::<Vec<u32>>()+64)).ok_or("effect report rank projection overflow")?;budget.charge(bytes).map_err(|_|PolicyFailure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"effect report rank projection denied")))?;work.reserve(bytes).map_err(PolicyFailure::Operational)?;let mut rank=Vec::new();rank.try_reserve_exact(current.len()).map_err(|e|PolicyFailure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,e)))?;if rank.capacity()>current.len().saturating_mul(4){budget.deny();return Err(PolicyFailure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"effect report rank projection exposed excess")))}rank.resize(current.len(),u32::MAX);
   for at in 0..order.len(){checkpoint().map_err(PolicyFailure::Operational)?;let ordinal=order.ordinal(at).ok_or("effect report rank original ordinal absent")?;let id=self.archive.callables().identity(ordinal).ok_or("effect report rank original identity absent")?;let node=current.node_for(id).ok_or("effect report rank original node absent")?;if rank[node]!=u32::MAX{return Err("effect report rank duplicates original contribution".into())}rank[node]=u32::try_from(at).map_err(|_|PolicyFailure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"effect report rank coordinate exceeds original scalar storage")))?;}
  checkpoint().map_err(PolicyFailure::Operational)?;
  admission.reserve_external(0).map_err(PolicyFailure::Operational)?;
  Ok(EffectReportOrder{graph,order,rank})
 }

 pub fn report_replay_window_using_order_checked<C:FnMut()->io::Result<()>,R:Resolver+?Sized,W:EffectReportWork>(
  &self,order:&EffectReportOrder<'_,'source>,summary:&OwnedCompactEffectSummary,start:usize,count:usize,
  phase:EffectReportPhase,resolver:&R,policy:&CheckerPolicy,admission:&ExecutionAdmission,
  checkpoint:&mut C,replay:&CompactGraphReplay<'_>,work:&mut W,
 )->Result<Vec<Produced>,PolicyFailure>{
  if !Arc::ptr_eq(self.archive,replay.input().archive()) || self.profile!=replay.input().profile(){
   return Err("compact effect report replay belongs to another source".into())
  }
  let loan=|node:usize,_:&ExecutionAdmission|replay.body(self.original_ordinal(node).ok_or("compact report source ordinal absent")?);
  self.report_body_loans_window_checked(order.graph,summary,start,count,phase,resolver,policy,admission,checkpoint,loan,Some(order),work)
 }

 fn report_body_loans_window_checked<B:ReportBodyLoan,C:FnMut()->io::Result<()>,R:Resolver+?Sized,W:EffectReportWork>(
  &self,graph:&RetainedEffectGraph,summary:&OwnedCompactEffectSummary,start:usize,count:usize,
  phase:EffectReportPhase,resolver:&R,policy:&CheckerPolicy,admission:&ExecutionAdmission,
  checkpoint:&mut C,read:impl Fn(usize,&ExecutionAdmission)->Result<B,PolicyFailure>,projection:Option<&EffectReportOrder<'_,'source>>,work:&mut W,
 )->Result<Vec<Produced>,PolicyFailure>{
  checkpoint().map_err(PolicyFailure::Operational)?;admission.reserve_external(0).map_err(PolicyFailure::Operational)?;
  let checkpoint=RefCell::new(checkpoint);let work=RefCell::new(work);let pending=(||{
   let current=graph.current(self)?;let end=start.checked_add(count).ok_or("effect report target window overflow")?.min(current.len());if start>current.len(){return Err("effect report target window outside original order".into())}let range=start..end;if summary.len()!=current.len(){return Err("effect report summary has another current graph extent".into())}
   let owned;
   let order=match projection{
    Some(order)=>{if !std::ptr::eq(order.graph,graph){return Err("effect report order belongs to another current graph".into())}order}
    None=>{owned=self.report_order_checked(graph,admission,&mut||(checkpoint.borrow_mut())(),&mut **work.borrow_mut())?;&owned}
   };
   let budget=ReportBudget::for_operation(admission);
   budget.charge(order.retained_charge().ok_or("effect report retained order/rank capacity overflow")?)
       .map_err(|_|PolicyFailure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"effect report live order/rank overlap denied")))?;
   let access=NativeReportAccess{source:self,graph:&current,summary,order:&order.order,rank:&order.rank,range,read,resolver,checkpoint:&checkpoint,work:&work,body:std::marker::PhantomData};let live=budget.admission_view();match phase{EffectReportPhase::Purity=>report_core::purity(&access,resolver,policy,&live,||access.poll()),EffectReportPhase::Sleep=>report_core::sleep(&access,resolver,policy,&live,||access.poll())}
  })();if matches!(&pending,Err(PolicyFailure::Operational(_))){return pending}(checkpoint.borrow_mut())().map_err(PolicyFailure::Operational)?;admission.reserve_external(0).map_err(PolicyFailure::Operational)?;pending
 }
}

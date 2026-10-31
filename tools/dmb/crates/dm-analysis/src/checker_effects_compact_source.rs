//! Compact unique effect adjacency from SAME original source contributions.
//! This is graph work over original IDs, never a Type/Proc model or source proof.
use super::*;
use crate::policy_body_demand::PolicyFailure;
use dm_tree::frontend::{BodySyntax,BodySyntaxInput,BodySyntaxFailure};
use std::{io,mem::size_of};
#[derive(Clone,Copy)]struct Row{parent:Option<EffectTarget>,direct:bool,builtin:bool}
/// Borrowed source identity plus flat global source-call/override adjacency.
/// Internal edge order is irrelevant to SCC; checker report/BFS order must still
/// come from original contributions and the existing checker_order policy.
pub struct CompactEffectGraph<'view,'source>{source:&'view EffectSource<'source>,index:Vec<(ProcedureIdentity,u32)>,offsets:Vec<usize>,edges:Vec<u32>,seed:Vec<bool>}
impl<'view,'source> CompactEffectGraph<'view,'source>{
 pub fn len(&self)->usize{self.seed.len()}
 pub fn original_ordinal(&self,node:usize)->Option<usize>{self.source.original_ordinal(node)}
 pub fn direct_effect(&self,node:usize)->Option<bool>{self.seed.get(node).copied()}
 pub fn successor(&self,node:usize,next:usize)->Result<Option<usize>,PolicyFailure>{
  let start=*self.offsets.get(node).ok_or("effect graph node outside original roster")?;let end=*self.offsets.get(node+1).ok_or("effect graph row incomplete")?;
  Ok(start.checked_add(next).filter(|at|*at<end).and_then(|at|self.edges.get(at)).map(|to|*to as usize))
 }
 pub fn retained_charge(&self)->Option<usize>{size_of::<Self>().checked_add(self.index.capacity().checked_mul(size_of::<(ProcedureIdentity,u32)>())?)?.checked_add(self.offsets.capacity().checked_mul(size_of::<usize>())?)?.checked_add(self.edges.capacity().checked_mul(size_of::<u32>())?)?.checked_add(self.seed.capacity())}
 pub fn compute_scc_checked(&self,admission:&ExecutionAdmission,checkpoint:&mut impl FnMut()->io::Result<()>)->Result<CompactEffectScc,PolicyFailure>{
  checkpoint().map_err(PolicyFailure::Operational)?;
  let budget=ReportBudget::for_operation(admission);budget.charge(self.retained_charge().ok_or_else(||resource(&budget,"effect graph retained capacity overflow"))?).map_err(|_|resource(&budget,"effect graph retained overlap refused"))?;
  CompactEffectScc::compute_checked(self.len(),&admission.restricted(budget.remaining()),|node,next,_|self.successor(node,next),checkpoint)
 }
 /// Graph retention and SCC retention overlap the same family allowance.
 pub fn summarize_checked<'scc>(&self,scc:&'scc CompactEffectScc,admission:&ExecutionAdmission,checkpoint:&mut impl FnMut()->io::Result<()>)->Result<CompactEffectSummary<'scc>,PolicyFailure>{
  checkpoint().map_err(PolicyFailure::Operational)?;
  let budget=ReportBudget::for_operation(admission);budget.charge(self.retained_charge().ok_or_else(||resource(&budget,"effect graph retained capacity overflow"))?).map_err(|_|resource(&budget,"effect graph retained overlap refused"))?;
  scc.summarize_checked(&admission.restricted(budget.remaining()),|node,_|Ok(self.direct_effect(node).ok_or("effect graph summary node outside roster")?),|node,next,_|self.successor(node,next),checkpoint)
 }

 /// Move only existing scalar buffers; no source bytes/AST/body owners escape.
 /// Source remains strongly borrowed until its fixed Weak coordination is
 /// admitted, so an unsuccessful reservation cannot extend uncharged liveness.
 pub fn into_retained_checked(self,checkpoint:&mut impl FnMut()->io::Result<()>,work:&mut impl FnMut(usize)->io::Result<()>)->Result<RetainedEffectGraph,PolicyFailure>{
  checkpoint().map_err(PolicyFailure::Operational)?;
  let owner=self.source.archive.original_owner_witness();let fixed=owner.fixed_retention_capacity().and_then(|n|n.checked_add(size_of::<RetainedEffectGraph>())).ok_or_else(||PolicyFailure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"effect retained graph witness overflow")))?;
  work(fixed).map_err(PolicyFailure::Operational)?;
  Ok(RetainedEffectGraph{owner,profile:self.source.profile,index:self.index,offsets:self.offsets,edges:self.edges,seed:self.seed})
 }
pub fn build_original_checked(source:&'view EffectSource<'source>,width:usize,admission:&ExecutionAdmission,checkpoint:&mut impl FnMut()->io::Result<()>,body:&dyn Fn(&Arc<BodySyntaxInput>,&ExecutionAdmission)->Result<Arc<BodySyntax>,BodySyntaxFailure>)->Result<Self,PolicyFailure>{let validated=source.archive.tree().validated_checker_profile(source.profile).map_err(|e|PolicyFailure::from(format!("effect original profile: {e:?}")))?;Self::build_checked(source,width,&validated,admission,checkpoint,body)}
 pub fn build_checked(source:&'view EffectSource<'source>,width:usize,resolver:&(impl Resolver+?Sized),admission:&ExecutionAdmission,checkpoint:&mut impl FnMut()->io::Result<()>,body:&dyn Fn(&Arc<BodySyntaxInput>,&ExecutionAdmission)->Result<Arc<BodySyntax>,BodySyntaxFailure>)->Result<Self,PolicyFailure>{
  Self::build_pages_checked(source,width,resolver,admission,checkpoint,&mut|start,width,child,checkpoint|EffectPageFacts::compute_checked(source,start,width,resolver,child,checkpoint,body).map(Arc::new))
 }
 /// A reader must return a privately produced current page. Its witness is
 /// checked again here before any scalar adjacency is counted or written.
 /// Only the graph escapes; borrowed page owners remain inside each iteration.
 pub fn build_pages_checked<C:FnMut()->io::Result<()>,P:std::ops::Deref>(source:&'view EffectSource<'source>,width:usize,resolver:&(impl Resolver+?Sized),admission:&ExecutionAdmission,checkpoint:&mut C,read:&mut impl FnMut(usize,usize,&ExecutionAdmission,&mut C)->Result<P,PolicyFailure>)->Result<Self,PolicyFailure> where P::Target:EffectPageRead{
  Self::build_pages_reserved_checked(source,width,resolver,admission,checkpoint,read,&mut|_|Ok(()))
 }
 /// Actual query callers reserve each allocation in the SAME family ledger
 /// before it occurs. The observer grants resources only, never source proof.
 pub fn build_pages_reserved_checked<C:FnMut()->io::Result<()>,P:std::ops::Deref>(source:&'view EffectSource<'source>,width:usize,resolver:&(impl Resolver+?Sized),admission:&ExecutionAdmission,checkpoint:&mut C,read:&mut impl FnMut(usize,usize,&ExecutionAdmission,&mut C)->Result<P,PolicyFailure>,work:&mut impl FnMut(usize)->io::Result<()>)->Result<Self,PolicyFailure> where P::Target:EffectPageRead{
  checkpoint().map_err(PolicyFailure::Operational)?;
  let pending=(||{
   let budget=ReportBudget::for_operation(admission);let n=source.len();if n>=u32::MAX as usize{return Err(resource(&budget,"effect source dense coordinates exceed scalar storage"))}
   if width==0||width>MAX_EVENTS{return Err("effect graph source page width outside event allowance".into())}
   if resolver.source_owner()!=Resolver::source_owner(source.archive.tree()){return Err("effect graph resolver foreign".into())}
   let mut index=allocate::<(ProcedureIdentity,u32)>(n,&budget,0,work)?;let mut rows=allocate::<Row>(n,&budget,0,work)?;
   for node in 0..n{checkpoint().map_err(PolicyFailure::Operational)?;index.push((identity(source.archive,source.original_ordinal(node).ok_or("effect source row missing")?)?,node as u32));rows.push(Row{parent:None,direct:false,builtin:false});}
   index.sort_unstable_by_key(|row|row.0);if index.windows(2).any(|pair|pair[0].0==pair[1].0){return Err("effect source identity has multiple original body occurrences".into())}
   let find=|id:ProcedureIdentity|->Result<u32,PolicyFailure>{index.binary_search_by_key(&id,|row|row.0).map(|at|index[at].1).map_err(|_|"effect graph target has no original source contribution".into())};
   // Count first, then allocate adjacency exactly once. This removes geometric
   // pair-buffer replacements and their overlap with the final CSR arrays.
   let mut degree=allocate::<u32>(n,&budget,0,work)?;degree.resize(n,0);
   let mut start=0usize;
   while start<n{
    checkpoint().map_err(PolicyFailure::Operational)?;
    let child=admission.restricted(budget.remaining());let page_owner=read(start,width,&child,checkpoint)?;let page=page_owner.effect_page();
    page.validate(source)?;require_window(&page,start,width,n)?;
    for local in 0..page.len(){let node=start+local;let id=page.procedure(local).ok_or("effect source page identity missing")?;
     if source.original_ordinal(node)!=page.ordinal(local)||find(id)? as usize!=node{return Err("effect source page order changed".into())}
     rows[node]=Row{parent:page.parent(local).ok_or("effect source parent missing")?,direct:page.has_direct_effect(local).ok_or("effect source direct row missing")?,builtin:page.has_builtin_effect_call(local).ok_or("effect source builtin row missing")?};
     for &id in page.source_calls(local).ok_or("effect source calls missing")?{find(id)?;degree[node]=degree[node].checked_add(1).ok_or_else(||resource(&budget,"effect source row degree overflow"))?;}
    }
    start=start.checked_add(page.len()).ok_or_else(||resource(&budget,"effect page source cursor overflow"))?;
   }
   visit_overrides(source,resolver,&index,&rows,&find,checkpoint,|from,_|{degree[from as usize]=degree[from as usize].checked_add(1).ok_or_else(||resource(&budget,"effect override degree overflow"))?;Ok(())})?;
   let mut offsets=allocate::<usize>(n.checked_add(1).ok_or_else(||resource(&budget,"effect graph offsets overflow"))?,&budget,0,work)?;
   let mut total=0usize;for &count in &degree{checkpoint().map_err(PolicyFailure::Operational)?;offsets.push(total);total=total.checked_add(count as usize).ok_or_else(||resource(&budget,"effect graph edge count overflow"))?;}offsets.push(total);
   let mut edges=allocate::<u32>(total,&budget,0,work)?;edges.resize(total,0);
   let mut seed=allocate::<bool>(n,&budget,0,work)?;seed.extend(rows.iter().map(|row|row.direct||row.builtin));
   // Offsets themselves serve as write cursors. Degree is remaining capacity;
   // no second cursor array/pair list or copied reverse graph is needed.
   let mut start=0usize;
   while start<n{
    checkpoint().map_err(PolicyFailure::Operational)?;
    let child=admission.restricted(budget.remaining());let page_owner=read(start,width,&child,checkpoint)?;let page=page_owner.effect_page();
    page.validate(source)?;require_window(&page,start,width,n)?;
    for local in 0..page.len(){let node=start+local;let old=&rows[node];let id=page.procedure(local).ok_or("effect source second-pass identity missing")?;
     if source.original_ordinal(node)!=page.ordinal(local)||find(id)? as usize!=node||Some(old.parent)!=page.parent(local)||Some(old.direct)!=page.has_direct_effect(local)||Some(old.builtin)!=page.has_builtin_effect_call(local){return Err("effect source changed between adjacency passes".into())}
     for &id in page.source_calls(local).ok_or("effect source second-pass calls missing")?{insert_edge(node,find(id)?,&mut offsets,&mut degree,&mut edges)?;}
    }
    start=start.checked_add(page.len()).ok_or_else(||resource(&budget,"effect page second-pass cursor overflow"))?;
   }
   visit_overrides(source,resolver,&index,&rows,&find,checkpoint,|from,to|insert_edge(from as usize,to,&mut offsets,&mut degree,&mut edges))?;
   if degree.iter().any(|remaining|*remaining!=0){return Err("effect source second-pass degree incomplete".into())}
   for node in (1..=n).rev(){offsets[node]=offsets[node-1];}offsets[0]=0;
   for node in 0..n{checkpoint().map_err(PolicyFailure::Operational)?;edges[offsets[node]..offsets[node+1]].sort_unstable();}
   // Parents/degrees drop at exit. Move the SAME funded sorted ID array
   // into the result for original encounter-order report/BFS lookups; no
   // second name/index allocation or per-edge roster scan is introduced.
   Ok(Self{source,index,offsets,edges,seed})
  })();
  if matches!(&pending,Err(PolicyFailure::Operational(_))){return pending}checkpoint().map_err(PolicyFailure::Operational)?;if admission.is_denied(){return Err(PolicyFailure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"effect graph operation denied")))}pending
 }
}
fn resource(b:&ReportBudget,message:&'static str)->PolicyFailure{b.deny();PolicyFailure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message))}
fn reserve(b:&ReportBudget,bytes:usize,page:usize)->Result<(),PolicyFailure>{b.charge(bytes).map_err(|_|resource(b,"effect compact graph capacity admission exhausted"))?;if b.remaining()<page{return Err(resource(b,"effect compact graph and live page overlap exhausted"))}Ok(())}
fn allocate<T>(count:usize,b:&ReportBudget,page:usize,work:&mut impl FnMut(usize)->io::Result<()>)->Result<Vec<T>,PolicyFailure>{let bytes=count.checked_mul(size_of::<T>()).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(size_of::<Vec<T>>()+64)).ok_or_else(||resource(b,"effect compact graph capacity overflow"))?;reserve(b,bytes,page)?;work(bytes).map_err(PolicyFailure::Operational)?;let mut out=Vec::new();out.try_reserve_exact(count).map_err(|actual|{b.deny();PolicyFailure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,actual))})?;if out.capacity()>count.saturating_mul(4){return Err(resource(b,"effect compact graph exposed capacity exceeds reservation"))}Ok(out)}
fn insert_edge(node:usize,to:u32,offsets:&mut[usize],remaining:&mut[u32],edges:&mut[u32])->Result<(),PolicyFailure>{
 let left=remaining.get_mut(node).ok_or("effect edge node outside original roster")?;
 if *left==0{return Err("effect source second-pass row exceeds original degree".into())}
 let at=offsets.get_mut(node).ok_or("effect adjacency cursor unavailable")?;
 *edges.get_mut(*at).ok_or("effect adjacency cursor outside admitted buffer")?=to;
 *at=at.checked_add(1).ok_or("effect adjacency cursor overflow")?;*left-=1;Ok(())
}
fn visit_overrides(source:&EffectSource<'_>,resolver:&(impl Resolver+?Sized),index:&[(ProcedureIdentity,u32)],rows:&[Row],find:&impl Fn(ProcedureIdentity)->Result<u32,PolicyFailure>,checkpoint:&mut impl FnMut()->io::Result<()>,mut edge:impl FnMut(u32,u32)->Result<(),PolicyFailure>)->Result<(),PolicyFailure>{
 let catalog=dm_tree::checker_builtins::pinned_catalog().map_err(|error|PolicyFailure::from(format!("effect graph original builtin catalog: {error:?}")))?;
 if catalog.profile!=source.profile{return Err("effect graph builtin profile differs".into())}
 let steps=rows.len().checked_add(catalog.declarations.len()).and_then(|n|n.checked_add(1)).ok_or_else(||PolicyFailure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"effect predecessor bound overflow")))?;
 for &(id,child) in index{
  checkpoint().map_err(PolicyFailure::Operational)?;if !rows[child as usize].direct||id.name==SymbolId::of("New"){continue}
  let mut parent=rows[child as usize].parent;let mut visited=0;
  while let Some(target)=parent{checkpoint().map_err(PolicyFailure::Operational)?;visited+=1;if visited>steps{return Err("purity original predecessor cycle".into())}
   parent=match target{EffectTarget::Source(id)=>{let at=find(id)?;edge(at,child)?;rows[at as usize].parent},EffectTarget::Builtin(_)=>original_target_parent(source.archive,source.profile,resolver,target)?};
  }
 }
 Ok(())
}
fn require_window(page:&EffectPageFacts,start:usize,width:usize,total:usize)->Result<(),PolicyFailure>{
 if page.start()!=start||page.total()!=total||page.len()==0||page.len()>width.min(total.saturating_sub(start)){return Err("effect page reader returned another original window".into())}Ok(())
}

/// Source-free retained scalar adjacency; this is not a current-source lease.
pub struct RetainedEffectGraph{owner:dm_tree::frontend::OriginalArchiveOwner,profile:PackedU128,index:Vec<(ProcedureIdentity,u32)>,offsets:Vec<usize>,edges:Vec<u32>,seed:Vec<bool>}
pub struct CurrentEffectGraph<'view,'source>{graph:&'view RetainedEffectGraph,source:&'view EffectSource<'source>}
impl RetainedEffectGraph{
 pub fn retained_charge(&self)->Option<usize>{size_of::<Self>().checked_add(self.index.capacity().checked_mul(size_of::<(ProcedureIdentity,u32)>())?)?.checked_add(self.offsets.capacity().checked_mul(size_of::<usize>())?)?.checked_add(self.edges.capacity().checked_mul(size_of::<u32>())?)?.checked_add(self.seed.capacity())?.checked_add(self.owner.fixed_retention_capacity()?)}
 pub fn current<'view,'source>(&'view self,source:&'view EffectSource<'source>)->Result<CurrentEffectGraph<'view,'source>,PolicyFailure>{if !self.owner.matches(source.archive)||self.profile!=source.profile||self.seed.len()!=source.len(){return Err("effect retained graph has another original source/profile".into())}Ok(CurrentEffectGraph{graph:self,source})}
 pub fn visit_storage(&self,mut visit:impl FnMut(Storage)){
  visit(Storage::Buffer{owner:"purity.global_original_ids",address:self.index.as_ptr() as usize,logical:self.index.len()*size_of::<(ProcedureIdentity,u32)>(),capacity:self.index.capacity()*size_of::<(ProcedureIdentity,u32)>()});
  visit(Storage::Buffer{owner:"purity.global_offsets",address:self.offsets.as_ptr() as usize,logical:self.offsets.len()*size_of::<usize>(),capacity:self.offsets.capacity()*size_of::<usize>()});
  visit(Storage::Buffer{owner:"purity.global_edges",address:self.edges.as_ptr() as usize,logical:self.edges.len()*size_of::<u32>(),capacity:self.edges.capacity()*size_of::<u32>()});
  visit(Storage::Buffer{owner:"purity.global_seed",address:self.seed.as_ptr() as usize,logical:self.seed.len(),capacity:self.seed.capacity()});
  self.owner.visit_storage(|owner,address,logical,capacity|visit(Storage::Buffer{owner,address,logical,capacity}));
 }
}
impl CurrentEffectGraph<'_,'_>{
 pub fn node_for(&self,id:ProcedureIdentity)->Option<usize>{self.graph.index.binary_search_by_key(&id,|row|row.0).ok().map(|at|self.graph.index[at].1 as usize)}
 pub fn len(&self)->usize{self.graph.seed.len()}
 pub fn original_ordinal(&self,node:usize)->Option<usize>{self.source.original_ordinal(node)}
 pub fn direct_effect(&self,node:usize)->Option<bool>{self.graph.seed.get(node).copied()}
 pub fn successor(&self,node:usize,next:usize)->Result<Option<usize>,PolicyFailure>{let start=*self.graph.offsets.get(node).ok_or("effect current graph node outside roster")?;let end=*self.graph.offsets.get(node+1).ok_or("effect current graph row incomplete")?;Ok(start.checked_add(next).filter(|at|*at<end).and_then(|at|self.graph.edges.get(at)).map(|to|*to as usize))}
 pub fn compute_scc_checked(&self,admission:&ExecutionAdmission,checkpoint:&mut impl FnMut()->io::Result<()>)->Result<CompactEffectScc,PolicyFailure>{checkpoint().map_err(PolicyFailure::Operational)?;let budget=ReportBudget::for_operation(admission);budget.charge(self.graph.retained_charge().ok_or_else(||resource(&budget,"effect current graph capacity overflow"))?).map_err(|_|resource(&budget,"effect current graph SCC overlap refused"))?;CompactEffectScc::compute_checked(self.len(),&admission.restricted(budget.remaining()),|node,next,_|self.successor(node,next),checkpoint)}
}

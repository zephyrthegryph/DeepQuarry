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
pub struct CompactEffectGraph<'view,'source>{source:&'view EffectSource<'source>,offsets:Vec<usize>,edges:Vec<u32>,seed:Vec<bool>}
impl<'view,'source> CompactEffectGraph<'view,'source>{
 pub fn len(&self)->usize{self.seed.len()}
 pub fn original_ordinal(&self,node:usize)->Option<usize>{self.source.original_ordinal(node)}
 pub fn direct_effect(&self,node:usize)->Option<bool>{self.seed.get(node).copied()}
 pub fn successor(&self,node:usize,next:usize)->Result<Option<usize>,PolicyFailure>{
  let start=*self.offsets.get(node).ok_or("effect graph node outside original roster")?;let end=*self.offsets.get(node+1).ok_or("effect graph row incomplete")?;
  Ok(start.checked_add(next).filter(|at|*at<end).and_then(|at|self.edges.get(at)).map(|to|*to as usize))
 }
 pub fn retained_charge(&self)->Option<usize>{size_of::<Self>().checked_add(self.offsets.capacity().checked_mul(size_of::<usize>())?)?.checked_add(self.edges.capacity().checked_mul(size_of::<u32>())?)?.checked_add(self.seed.capacity())}
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
 pub fn build_checked(source:&'view EffectSource<'source>,width:usize,resolver:&(impl Resolver+?Sized),admission:&ExecutionAdmission,checkpoint:&mut impl FnMut()->io::Result<()>,body:&dyn Fn(&Arc<BodySyntaxInput>,&ExecutionAdmission)->Result<Arc<BodySyntax>,BodySyntaxFailure>)->Result<Self,PolicyFailure>{
  checkpoint().map_err(PolicyFailure::Operational)?;
  let pending=(||{
   let budget=ReportBudget::for_operation(admission);let n=source.len();if n>=u32::MAX as usize{return Err(resource(&budget,"effect source dense coordinates exceed scalar storage"))}
   if width==0||width>MAX_EVENTS{return Err("effect graph source page width outside event allowance".into())}
   if resolver.source_owner()!=Resolver::source_owner(source.archive.tree()){return Err("effect graph resolver foreign".into())}
   let mut index=allocate::<(ProcedureIdentity,u32)>(n,&budget,0)?;let mut rows=allocate::<Row>(n,&budget,0)?;
   for node in 0..n{checkpoint().map_err(PolicyFailure::Operational)?;index.push((identity(source.archive,source.original_ordinal(node).ok_or("effect source row missing")?)?,node as u32));rows.push(Row{parent:None,direct:false,builtin:false});}
   index.sort_unstable_by_key(|row|row.0);if index.windows(2).any(|pair|pair[0].0==pair[1].0){return Err("effect source identity has multiple original body occurrences".into())}
   let find=|id:ProcedureIdentity|->Result<u32,PolicyFailure>{index.binary_search_by_key(&id,|row|row.0).map(|at|index[at].1).map_err(|_|"effect graph target has no original source contribution".into())};
   // Count first, then allocate adjacency exactly once. This removes geometric
   // pair-buffer replacements and their overlap with the final CSR arrays.
   let mut degree=allocate::<u32>(n,&budget,0)?;degree.resize(n,0);
   let mut start=0usize;
   while start<n{
    let mut consumed=0usize;
    let child=admission.restricted(budget.remaining());
    source.with_page_checked(start,width,resolver,&child,checkpoint,body,|page|{
     consumed=page.len();
     for local in 0..page.len(){let contribution=page.contribution(local)?.ok_or("effect source page row missing")?;let node=start+local;
      if source.original_ordinal(node)!=Some(contribution.ordinal())||find(contribution.procedure())? as usize!=node{return Err("effect source page order changed".into())}
      rows[node]=Row{parent:contribution.parent(),direct:contribution.has_direct_effect(),builtin:contribution.has_builtin_effect_call()};
      contribution.try_source_calls(|id|{find(id)?;degree[node]=degree[node].checked_add(1).ok_or_else(||resource(&budget,"effect source row degree overflow"))?;Ok::<_,PolicyFailure>(())})?;
     }Ok(())
    })?;
    if consumed==0{return Err("effect graph source window omitted rows".into())}start=start.checked_add(consumed).ok_or_else(||resource(&budget,"effect graph source cursor overflow"))?;
   }
   visit_overrides(source,resolver,&index,&rows,&find,checkpoint,|from,_|{degree[from as usize]=degree[from as usize].checked_add(1).ok_or_else(||resource(&budget,"effect override degree overflow"))?;Ok(())})?;
   let mut offsets=allocate::<usize>(n.checked_add(1).ok_or_else(||resource(&budget,"effect graph offsets overflow"))?,&budget,0)?;
   let mut total=0usize;for &count in &degree{checkpoint().map_err(PolicyFailure::Operational)?;offsets.push(total);total=total.checked_add(count as usize).ok_or_else(||resource(&budget,"effect graph edge count overflow"))?;}offsets.push(total);
   let mut edges=allocate::<u32>(total,&budget,0)?;edges.resize(total,0);
   let mut seed=allocate::<bool>(n,&budget,0)?;seed.extend(rows.iter().map(|row|row.direct||row.builtin));
   // Offsets themselves serve as write cursors. Degree is remaining capacity;
   // no second cursor array/pair list or copied reverse graph is needed.
   let mut start=0usize;
   while start<n{
    let mut consumed=0usize;
    let child=admission.restricted(budget.remaining());
    source.with_page_checked(start,width,resolver,&child,checkpoint,body,|page|{
     consumed=page.len();
     for local in 0..page.len(){let contribution=page.contribution(local)?.ok_or("effect source second-pass row missing")?;let node=start+local;let old=&rows[node];
      if source.original_ordinal(node)!=Some(contribution.ordinal())||find(contribution.procedure())? as usize!=node||old.parent!=contribution.parent()||old.direct!=contribution.has_direct_effect()||old.builtin!=contribution.has_builtin_effect_call(){return Err("effect source changed between adjacency passes".into())}
      contribution.try_source_calls(|id|insert_edge(node,find(id)?,&mut offsets,&mut degree,&mut edges))?;
     }Ok(())
    })?;
    if consumed==0{return Err("effect graph source window omitted rows".into())}start=start.checked_add(consumed).ok_or_else(||resource(&budget,"effect graph source cursor overflow"))?;
   }
   visit_overrides(source,resolver,&index,&rows,&find,checkpoint,|from,to|insert_edge(from as usize,to,&mut offsets,&mut degree,&mut edges))?;
   if degree.iter().any(|remaining|*remaining!=0){return Err("effect source second-pass degree incomplete".into())}
   for node in (1..=n).rev(){offsets[node]=offsets[node-1];}offsets[0]=0;
   // Preserve the prior pairs.sort_unstable successor order in place.
   for node in 0..n{checkpoint().map_err(PolicyFailure::Operational)?;edges[offsets[node]..offsets[node+1]].sort_unstable();}
   // All temporary IDs/parents/degrees are physically freed at function exit;
   // final graph owns only scalar adjacency and an actual borrowed source view.
   Ok(Self{source,offsets,edges,seed})
  })();
  if matches!(&pending,Err(PolicyFailure::Operational(_))){return pending}checkpoint().map_err(PolicyFailure::Operational)?;if admission.is_denied(){return Err(PolicyFailure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"effect graph operation denied")))}pending
 }
}
fn resource(b:&ReportBudget,message:&'static str)->PolicyFailure{b.deny();PolicyFailure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message))}
fn reserve(b:&ReportBudget,bytes:usize,page:usize)->Result<(),PolicyFailure>{b.charge(bytes).map_err(|_|resource(b,"effect compact graph capacity admission exhausted"))?;if b.remaining()<page{return Err(resource(b,"effect compact graph and live page overlap exhausted"))}Ok(())}
fn allocate<T>(count:usize,b:&ReportBudget,page:usize)->Result<Vec<T>,PolicyFailure>{let bytes=count.checked_mul(size_of::<T>()).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(size_of::<Vec<T>>()+64)).ok_or_else(||resource(b,"effect compact graph capacity overflow"))?;reserve(b,bytes,page)?;let mut out=Vec::new();out.try_reserve_exact(count).map_err(|actual|{b.deny();PolicyFailure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,actual))})?;if out.capacity()>count.saturating_mul(4){return Err(resource(b,"effect compact graph exposed capacity exceeds reservation"))}Ok(out)}
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

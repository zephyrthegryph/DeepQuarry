//! ONE global iterative SCC over a finite original-ID adjacency reader.
//! No page SCC, reverse-edge copy, procedure model or parser is stored here.
//! A source producer still owns current archive/profile/edge proof; these scalar
//! component numbers alone never admit a source query or executable cache hit.
use super::{ExecutionAdmission,ReportBudget};
use crate::policy_body_demand::PolicyFailure;
use std::{io,mem::size_of};
const NONE:u32=u32::MAX;
#[derive(Clone,Copy)]struct Frame{node:u32,next:usize}
/// Unique checker work only. Node indices are the caller's original dense body
/// ordinals, not a copied name/owner roster. Component labels are internal; only
/// their partition matters, matching the existing whole-graph policy.
pub struct CompactEffectScc{component:Vec<u32>,count:u32}
impl CompactEffectScc{
    /// SAME six-array envelope used by compute_checked, for an outer existing
    /// family ledger to fund this work before entering the primitive.
    pub fn work_charge(nodes:usize)->Option<usize>{let item=size_of::<u32>().checked_mul(4)?.checked_add(size_of::<bool>())?.checked_add(size_of::<Frame>())?;nodes.checked_mul(item)?.checked_mul(4)?.checked_add(size_of::<Self>()+6*size_of::<Vec<u32>>()+256)}
    /// Maximum of the SAME summary arrays when every node is its own SCC;
    /// retained component capacity is bounded by compute_checked's4x reserve.
    pub fn summary_work_charge_bound(nodes:usize)->Option<usize>{nodes.checked_mul(size_of::<u32>()+size_of::<u32>()+size_of::<bool>())?.checked_mul(4)?.checked_add(nodes.checked_mul(size_of::<u32>())?.checked_mul(4)?)?.checked_add(size_of::<Self>()+3*size_of::<Vec<u32>>()+size_of::<CompactEffectSummary<'_>>()+128)}
    pub fn summary_work_charge(&self)->Option<usize>{self.component.len().checked_mul(size_of::<u32>())?.checked_add((self.count as usize).checked_mul(size_of::<u32>()+size_of::<bool>())?)?.checked_mul(4)?.checked_add(self.retained_charge()?)?.checked_add(3*size_of::<Vec<u32>>()+size_of::<CompactEffectSummary<'_>>()+128)}
    /// Consume the actual existing SCC/summary buffers; no node projection or
    /// copied component roster is introduced for retained query publication.
    pub fn into_summary_checked(self,admission:&ExecutionAdmission,direct:impl FnMut(usize,&ExecutionAdmission)->Result<bool,PolicyFailure>,successor:impl FnMut(usize,usize,&ExecutionAdmission)->Result<Option<usize>,PolicyFailure>,checkpoint:&mut impl FnMut()->io::Result<()>)->Result<OwnedCompactEffectSummary,PolicyFailure>{let CompactEffectSummary{effect,..}=self.summarize_checked(admission,direct,successor,checkpoint)?;Ok(OwnedCompactEffectSummary{component:self.component,effect})}

    pub fn components(&self)->&[u32]{&self.component}
    pub fn component_count(&self)->usize{self.count as usize}
    pub fn same_component(&self,a:usize,b:usize)->Option<bool>{Some(self.component.get(a)?==self.component.get(b)?)}
    pub fn retained_charge(&self)->Option<usize>{size_of::<Self>().checked_add(self.component.capacity().checked_mul(size_of::<u32>())?)}
    /// Propagate the original direct/builtin effect seed over the SAME global
    /// SCC partition. Tarjan labels complete sink components first, so a flat
    /// component-member linkage permits one pass without a copied DAG/reverse
    /// edge model. Callers must supply the same immutable source edge reader.
    pub fn summarize_checked<'scc>(
        &'scc self,admission:&ExecutionAdmission,
        mut direct:impl FnMut(usize,&ExecutionAdmission)->Result<bool,PolicyFailure>,
        mut successor:impl FnMut(usize,usize,&ExecutionAdmission)->Result<Option<usize>,PolicyFailure>,
        checkpoint:&mut impl FnMut()->io::Result<()>,
    )->Result<CompactEffectSummary<'scc>,PolicyFailure>{
        checkpoint().map_err(PolicyFailure::Operational)?;
        let pending=(||{
            let budget=ReportBudget::for_operation(admission);let nodes=self.component.len();let count=self.count as usize;
            let bytes=self.summary_work_charge().ok_or_else(||resource(&budget,"effect summary capacity overflow"))?;
            budget.charge(bytes).map_err(|_|resource(&budget,"effect summary admission exhausted"))?;
            let read_admission=admission.restricted(budget.remaining());
            let mut first=vector(count,NONE,&budget)?;let mut next=vector(nodes,NONE,&budget)?;let mut effect=vector(count,false,&budget)?;
            for(node,&component)in self.component.iter().enumerate(){checkpoint().map_err(PolicyFailure::Operational)?;let c=component as usize;if c>=count{return Err("effect SCC component is outside original partition".into())}next[node]=first[c];first[c]=node as u32;}
            for c in 0..count{let mut node=first[c];while node!=NONE{checkpoint().map_err(PolicyFailure::Operational)?;let at=node as usize;effect[c]|=direct(at,&read_admission)?;let mut edge=0;while let Some(to)=successor(at,edge,&read_admission)?{checkpoint().map_err(PolicyFailure::Operational)?;let target=*self.component.get(to).ok_or("effect summary endpoint outside original roster")? as usize;if target>c{return Err("effect adjacency changed after global SCC partition".into())}if target!=c{let inherited=effect[target];effect[c]|=inherited;}edge=edge.checked_add(1).ok_or_else(||resource(&budget,"effect summary edge cursor overflow"))?;}node=next[at];}}
            if admission.is_denied(){return Err(resource(&budget,"effect summary reader admission was denied"))}
            Ok(CompactEffectSummary{scc:self,effect})
        })();
        if matches!(&pending,Err(PolicyFailure::Operational(_))){return pending}checkpoint().map_err(PolicyFailure::Operational)?;pending
    }
    /// A reader yields the indexed outgoing edge, then None at the immutable
    /// row's end. It may borrow original contribution pages under its EXISTING
    /// graph permit. It must include override edges exactly as EffectInput.plan
    /// does. Callee recursion is handled here, never by recursively getting body
    /// queries. Actual reader IO remains uncached and unchanged.
    pub fn compute_checked(
        nodes:usize,admission:&ExecutionAdmission,
        mut successor:impl FnMut(usize,usize,&ExecutionAdmission)->Result<Option<usize>,PolicyFailure>,
        checkpoint:&mut impl FnMut()->io::Result<()>,
    )->Result<Self,PolicyFailure>{
        checkpoint().map_err(PolicyFailure::Operational)?;
        let pending=(||{
            if nodes>=NONE as usize{return Err(PolicyFailure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"effect SCC node coordinates exceed bounded scalar storage")))}
            let budget=ReportBudget::for_operation(admission);
            // Reserve all six maximum-length work arrays BEFORE allocating any.
            // No edge-count or whole-source MAX_EVENTS limit is raised: edges
            // are borrowed one at a time from independently admitted pages.
            let bound=Self::work_charge(nodes).ok_or_else(||resource(&budget,"effect SCC work capacity overflow"))?;
            budget.charge(bound).map_err(|_|resource(&budget,"effect SCC work admission exhausted"))?;
            let read_admission=admission.restricted(budget.remaining());
            let mut index=vector(nodes,NONE,&budget)?;let mut low=vector(nodes,NONE,&budget)?;let mut active=vector(nodes,false,&budget)?;
            let mut component=vector(nodes,NONE,&budget)?;let mut stack:Vec<u32>=empty(nodes,&budget)?;let mut frames:Vec<Frame>=empty(nodes,&budget)?;
            let(mut entered,mut count)=(0u32,0u32);
            for start in 0..nodes{
                checkpoint().map_err(PolicyFailure::Operational)?;if index[start]!=NONE{continue}
                index[start]=entered;low[start]=entered;entered+=1;active[start]=true;stack.push(start as u32);frames.push(Frame{node:start as u32,next:0});
                while let Some(frame)=frames.last().copied(){
                    checkpoint().map_err(PolicyFailure::Operational)?;let node=frame.node as usize;
                    if let Some(child)=successor(node,frame.next,&read_admission)?{
                        if child>=nodes{return Err("effect SCC reader endpoint outside actual original roster".into())}
                        frames.last_mut().expect("current original DFS frame").next=frame.next.checked_add(1).ok_or_else(||resource(&budget,"effect SCC edge cursor overflow"))?;
                        if index[child]==NONE{index[child]=entered;low[child]=entered;entered+=1;active[child]=true;stack.push(child as u32);frames.push(Frame{node:child as u32,next:0});}
                        else if active[child]{low[node]=low[node].min(index[child]);}
                    }else{
                        frames.pop();if low[node]==index[node]{loop{checkpoint().map_err(PolicyFailure::Operational)?;let at=stack.pop().ok_or("effect SCC active stack incomplete")? as usize;active[at]=false;component[at]=count;if at==node{break}}count+=1;}
                        if let Some(parent)=frames.last(){let parent=parent.node as usize;low[parent]=low[parent].min(low[node]);}
                    }
                }
            }
            if admission.is_denied(){return Err(resource(&budget,"effect SCC reader admission was denied"))}
            checkpoint().map_err(PolicyFailure::Operational)?;Ok(Self{component,count})
        })();
        if matches!(&pending,Err(PolicyFailure::Operational(_))){return pending}
        checkpoint().map_err(PolicyFailure::Operational)?;pending
    }
}
/// A borrowed partition plus its unique boolean effect summary; no source
/// receipt or names/ASTs are created from component equality.
pub struct CompactEffectSummary<'scc>{scc:&'scc CompactEffectScc,effect:Vec<bool>}
impl CompactEffectSummary<'_>{
    pub fn node_has_effect(&self,node:usize)->Option<bool>{self.effect.get(*self.scc.component.get(node)? as usize).copied()}
    pub fn retained_charge(&self)->Option<usize>{size_of::<Self>().checked_add(self.effect.capacity().checked_mul(size_of::<bool>())?)}
}

/// Source-free scalar output only. Query callers must keep the actual original
/// graph/current witness alongside this moved result before exposing reports.
pub struct OwnedCompactEffectSummary{component:Vec<u32>,effect:Vec<bool>}
impl OwnedCompactEffectSummary{
 pub fn node_has_effect(&self,node:usize)->Option<bool>{self.effect.get(*self.component.get(node)? as usize).copied()}
 pub fn len(&self)->usize{self.component.len()}
 pub fn retained_charge(&self)->Option<usize>{size_of::<Self>().checked_add(self.component.capacity().checked_mul(size_of::<u32>())?)?.checked_add(self.effect.capacity())}
 pub fn visit_storage(&self,mut visitor:impl FnMut(&'static str,usize,usize,usize)){visitor("purity.global_components",self.component.as_ptr() as usize,self.component.len()*size_of::<u32>(),self.component.capacity()*size_of::<u32>());visitor("purity.global_component_effects",self.effect.as_ptr() as usize,self.effect.len(),self.effect.capacity());}
}
fn resource(b:&ReportBudget,message:&'static str)->PolicyFailure{b.deny();PolicyFailure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message))}
fn empty<T>(n:usize,b:&ReportBudget)->Result<Vec<T>,PolicyFailure>{let mut rows=Vec::new();rows.try_reserve_exact(n).map_err(|actual|{b.deny();PolicyFailure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,actual))})?;if rows.capacity()>n.saturating_mul(4){return Err(resource(b,"effect SCC exposed capacity exceeds reserved envelope"))}Ok(rows)}
fn vector<T:Clone>(n:usize,value:T,b:&ReportBudget)->Result<Vec<T>,PolicyFailure>{let mut rows=empty(n,b)?;rows.resize(n,value);Ok(rows)}

#[cfg(test)]mod tests{
    use super::*;
    #[test]fn global_reader_preserves_cross_window_cycles_and_matches_original_partition(){
        let edges=vec![vec![1],vec![2],vec![0,3],vec![4],vec![3],vec![]];let old=super::super::scc(&edges).unwrap();
        let actual=CompactEffectScc::compute_checked(edges.len(),&ExecutionAdmission::default(),|node,next,_|Ok(edges[node].get(next).copied()),&mut||Ok(())).unwrap();
        for a in 0..edges.len(){for b in 0..edges.len(){assert_eq!(actual.same_component(a,b),Some(old[a]==old[b]));}}assert_eq!(actual.component_count(),3);
    }
    #[test]fn global_reader_has_bounded_stack_and_actual_io_is_retryable_without_partial_summary(){
        let n=20000;let admission=ExecutionAdmission::default();let mut polls=0;let error=CompactEffectScc::compute_checked(n,&admission,|node,next,_|Ok((next==0).then_some((node+1)%n)),&mut||{polls+=1;if polls==100{Err(io::Error::from_raw_os_error(1450))}else{Ok(())}}).err().unwrap();assert!(matches!(error,PolicyFailure::Operational(ref actual)if actual.raw_os_error()==Some(1450)));
        let recovered=CompactEffectScc::compute_checked(n,&admission,|node,next,_|Ok((next==0).then_some((node+1)%n)),&mut||Ok(())).unwrap();assert_eq!(recovered.component_count(),1);assert_eq!(recovered.same_component(0,n-1),Some(true));
        let tiny=ExecutionAdmission::with_limit(1);assert!(matches!(CompactEffectScc::compute_checked(n,&tiny,|_,_,_|panic!("refuse before reader work"),&mut||Ok(())),Err(PolicyFailure::Operational(ref e))if e.kind()==io::ErrorKind::OutOfMemory));assert!(tiny.is_denied());
    }

    #[test]fn original_reader_receives_only_parent_work_headroom_and_preserves_first_actual_io(){
        let limit=ExecutionAdmission::with_limit(1024);
        let error=CompactEffectScc::compute_checked(1,&limit,|_,_,child|{let budget=ReportBudget::for_operation(child);assert!(budget.charge(1024).is_err(),"global work arrays remain live during reader demand");Err(PolicyFailure::Operational(io::Error::from_raw_os_error(1450)))},&mut||Ok(())).err().unwrap();
        assert!(matches!(error,PolicyFailure::Operational(ref actual)if actual.raw_os_error()==Some(1450)),"reader actual cause outranks its shared denial state");assert!(limit.is_denied());
        let fresh=CompactEffectScc::compute_checked(1,&ExecutionAdmission::default(),|_,_,_|Ok(None),&mut||Ok(())).unwrap();let summary=fresh.summarize_checked(&ExecutionAdmission::default(),|_,_|Ok(true),|_,_,_|Ok(None),&mut||Ok(())).unwrap();assert_eq!(summary.node_has_effect(0),Some(true));
    }
}

#[cfg(test)]mod retained_tests{use super::*;
 #[test]fn retained_summary_moves_actual_component_buffer_and_preserves_global_cycle_effects(){let edges=[vec![1],vec![0,2],vec![],vec![]];let a=ExecutionAdmission::default();let scc=CompactEffectScc::compute_checked(edges.len(),&a,|i,n,_|Ok(edges[i].get(n).copied()),&mut||Ok(())).unwrap();let pointer=scc.component.as_ptr();let old=scc.summarize_checked(&a,|i,_|Ok(i==2),|i,n,_|Ok(edges[i].get(n).copied()),&mut||Ok(())).unwrap();let expected=(0..edges.len()).map(|i|old.node_has_effect(i)).collect::<Vec<_>>();drop(old);let actual=scc.into_summary_checked(&a,|i,_|Ok(i==2),|i,n,_|Ok(edges[i].get(n).copied()),&mut||Ok(())).unwrap();assert_eq!(actual.component.as_ptr(),pointer);assert_eq!((0..actual.len()).map(|i|actual.node_has_effect(i)).collect::<Vec<_>>(),expected);assert_eq!(expected,[Some(true),Some(true),Some(true),Some(false)]);}
}

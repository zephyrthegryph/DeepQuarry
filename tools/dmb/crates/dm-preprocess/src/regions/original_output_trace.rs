//! Immutable lineage captured on actual output entries, not reconstructed
//! from the mutable current macro stack after a delayed consumer drains it.
use crate::macro_expansion::{OriginalMacroText as Text,OriginalMacroOrigin as Origin};
use super::macro_trace_view::OriginalMacroAuthor;
use dm_syntax::{SettingAdmission,SettingRootLease};use std::{io,sync::{Arc,Weak},mem};
struct Node{parent:OriginalOutputTrace,name:Text,origin:Origin,definition:Option<Origin>,projected:Option<Arc<OriginalMacroAuthor>>,depth:usize,credit:SettingRootLease}
#[derive(Clone,Default)]pub(super) struct OriginalOutputTrace(Option<Arc<Node>>);
/// A one-entry projection cache can identify the same trace without keeping
/// the node, its name or its ancestor chain alive. The weak allocation can
/// outlive the node's own lease, so retain its exact fixed backing separately.
pub(super) struct OriginalTraceProjectionKey {
    owner: Weak<Node>,
    credit: SettingRootLease,
}
impl OriginalTraceProjectionKey {
    pub(super) fn matches(&self, trace: &OriginalOutputTrace, a: &SettingAdmission<'_>) -> bool {
        a.matches_lease_domain(&self.credit)
            && trace.0.as_ref().is_some_and(|node| self.owner.as_ptr() == Arc::as_ptr(node))
    }
}
pub(super) struct OriginalOutputTraceView<'a>{pub(super) name:&'a str,pub(super) origin:Origin,pub(super) definition:Option<Origin>,pub(super) projected:Option<&'a Arc<OriginalMacroAuthor>>,pub(super) depth:usize}
impl Drop for OriginalOutputTrace{fn drop(&mut self){let mut next=self.0.take();while let Some(owner)=next{let Some(mut payload)=Arc::into_inner(owner)else{break};next=payload.parent.0.take();drop(payload);}}}
fn poll(a:&SettingAdmission<'_>)->io::Result<()>{a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))}
impl OriginalOutputTrace{
    pub(super) fn projection_key_using(&self, a: &SettingAdmission<'_>) -> io::Result<OriginalTraceProjectionKey> {
        self.check(a)?;
        let node = self.0.as_ref().ok_or(io::ErrorKind::InvalidInput)?;
        let credit = a.reserve(mem::size_of::<Node>() + 2 * mem::size_of::<usize>())
            .map_err(|error| a.take_operational_error().unwrap_or(error))?;
        Ok(OriginalTraceProjectionKey { owner: Arc::downgrade(node), credit })
    }
 pub(super) fn depth(&self)->usize{self.0.as_deref().map_or(0,|node|node.depth)}
 fn check(&self,a:&SettingAdmission<'_>)->io::Result<()>{poll(a)?;if self.0.as_deref().is_some_and(|node|!a.matches_lease_domain(&node.credit)){return Err(io::ErrorKind::InvalidInput.into())}Ok(())}
 #[cfg(test)]
 pub(super) fn pushed_using(&self,name:&str,origin:Origin,depth:usize,definition:Option<Origin>,a:&SettingAdmission<'_>)->io::Result<Self>{
  self.pushed_with_definition_using(name,origin,depth,definition,None,a)
 }
 pub(super) fn pushed_with_definition_using(&self,name:&str,origin:Origin,depth:usize,definition:Option<Origin>,projected:Option<&Arc<OriginalMacroAuthor>>,a:&SettingAdmission<'_>)->io::Result<Self>{
  self.check(a)?;if depth!=self.depth().checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?||!origin.invocation{return Err(io::ErrorKind::InvalidInput.into())}
  let mut actual=Text::new(a)?;actual.push_str(name,a)?;let credit=a.reserve(mem::size_of::<Node>()+2*mem::size_of::<usize>()).map_err(|e|a.take_operational_error().unwrap_or(e))?;Ok(Self(Some(Arc::new(Node{parent:self.clone(),name:actual,origin,definition,projected:projected.cloned(),depth,credit}))))
 }
 pub(super) fn popped_using(&self,depth:usize,a:&SettingAdmission<'_>)->io::Result<Self>{self.check(a)?;let node=self.0.as_deref().ok_or(io::ErrorKind::InvalidInput)?;if node.depth!=depth.checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?{return Err(io::ErrorKind::InvalidInput.into())}Ok(node.parent.clone())}
 /// Exact actual allocations only. Caller deduplicates repeated parent/node
 /// aliases by address; conservative quota reservation is never a heap row.
 pub(super) fn visit_storage(&self,mut visit:impl FnMut(usize,usize,usize)){let mut node=self.0.as_ref();while let Some(actual)=node{visit(Arc::as_ptr(actual)as usize,1,mem::size_of::<Node>()+2*mem::size_of::<usize>());actual.name.visit_allocation(|p,n|visit(p,n,n));if let Some(definition)=&actual.projected{definition.visit_storage(&mut visit)}actual.credit.visit_counter_storage(|p,n|visit(p,1,n));node=actual.parent.0.as_ref();}}
 /// Borrow current-to-outer lineage without a copied Vec/dictionary or source
 /// authority. Caller may reverse its already-funded retained output recipe.
 pub(super) fn visit_inner_to_outer_using(&self,a:&SettingAdmission<'_>,mut visit:impl FnMut(OriginalOutputTraceView<'_>)->io::Result<()>)->io::Result<()>{
  self.check(a)?;let mut node=self.0.as_deref();while let Some(actual)=node{poll(a)?;if !a.matches_lease_domain(&actual.credit){return Err(io::ErrorKind::InvalidInput.into())}visit(OriginalOutputTraceView{name:actual.name.as_str(),origin:actual.origin,definition:actual.definition,projected:actual.projected.as_ref(),depth:actual.depth})?;node=actual.parent.0.as_deref();}Ok(())
 }
}

#[cfg(test)]mod tests{
 use super::*;use std::sync::atomic::{AtomicUsize,Ordering};
 #[test]fn last_alias_reclaims_long_parent_chain_iteratively_without_refunding_live_middle_alias(){
  let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,8<<20,&||Ok(()));let origin=Origin{physical:dm_syntax::Span::new(0,1),line:1,byte_column:Some(1),occurrence:0,invocation:true};let mut current=OriginalOutputTrace::default();let mut middle=None;for depth in 1..=4096{current=current.pushed_using("m",origin,depth,None,&a).unwrap();if depth==2048{middle=Some(current.clone())}}drop(current);assert!(used.load(Ordering::Acquire)>0);assert_eq!(middle.as_ref().unwrap().depth(),2048);drop(middle);assert_eq!(used.load(Ordering::Acquire),0);
 }
}

//! Immutable lineage captured on actual output entries, not reconstructed
//! from the mutable current macro stack after a delayed consumer drains it.
use crate::macro_expansion::{OriginalMacroText as Text,OriginalMacroOrigin as Origin};
use super::macro_trace_view::OriginalMacroAuthor;
use dm_syntax::{SettingAdmission,SettingRootLease};use std::{io,sync::{Arc,Weak},mem};
struct Node{parent:OriginalOutputTrace,name:Option<Text>,origin:Origin,definition:Option<Origin>,projected:Option<Arc<OriginalMacroAuthor>>,depth:usize,credit:SettingRootLease}
impl Node{
 fn name(&self)->&str{
  self.name.as_ref().map_or_else(||self.projected.as_ref().expect("issued authored invocation name").name(),Text::as_str)
 }
}
#[derive(Clone,Default)]pub(super) struct OriginalOutputTrace(Option<Arc<Node>>);
/// A projection cache can identify the same trace without keeping
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
    /// Compare to the exact direct parent already retained by this node.
    /// No lookup by span, macro spelling or structurally equal lineage.
    pub(super) fn matches_direct_parent(
        &self, trace: &OriginalOutputTrace, a: &SettingAdmission<'_>,
    ) -> bool {
        trace.0.as_deref().is_some_and(|node| self.matches(&node.parent, a))
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
 /// Bounded layout choice only. The actual visit still checks the admission,
 /// lends the provider, and authenticates every author in the same order.
 pub(super) fn supports_narrow_projection(&self)->bool{
  const MAX_PROBE_DEPTH:usize=64;
  if self.depth()>MAX_PROBE_DEPTH{return false}
  let mut node=self.0.as_deref();
  for _ in 0..self.depth(){
   let Some(actual)=node else{return false};
   let span=actual.origin.physical;
   if u32::try_from(span.start).is_err()||u32::try_from(span.end).is_err(){return false}
   node=actual.parent.0.as_deref();
  }
  node.is_none()
 }
 fn check(&self,a:&SettingAdmission<'_>)->io::Result<()>{poll(a)?;if self.0.as_deref().is_some_and(|node|!a.matches_lease_domain(&node.credit)){return Err(io::ErrorKind::InvalidInput.into())}Ok(())}
 #[cfg(test)]
 pub(super) fn pushed_using(&self,name:&str,origin:Origin,depth:usize,definition:Option<Origin>,a:&SettingAdmission<'_>)->io::Result<Self>{
  self.pushed_with_definition_using(name,origin,depth,definition,None,a)
 }
 pub(super) fn pushed_with_definition_using(&self,name:&str,origin:Origin,depth:usize,definition:Option<Origin>,projected:Option<&Arc<OriginalMacroAuthor>>,a:&SettingAdmission<'_>)->io::Result<Self>{
  self.check(a)?;if depth!=self.depth().checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?||!origin.invocation{return Err(io::ErrorKind::InvalidInput.into())}
  let actual=if definition.is_some() && projected.is_some_and(|author|
   author.origin().is_some() && author.is_admitted_by(a) && author.name()==name)
  {
   // The node already retains this exact authored epoch. Keep the former
   // zero-admission check and storage checkpoints, but do not fund or
   // allocate a second copy of immutable spelling. Definition coordinates
   // are still authenticated later by the actual provider.
   let _domain=a.reserve(0).map_err(|e|a.take_operational_error().unwrap_or(e))?;
   poll(a)?;
   if !name.is_empty(){poll(a)?;poll(a)?;}
   None
  }else{
   let mut actual=Text::new(a)?;
   actual.push_str(name,a)?;
   Some(actual)
  };
  let credit=a.reserve(mem::size_of::<Node>()+2*mem::size_of::<usize>()).map_err(|e|a.take_operational_error().unwrap_or(e))?;
  Ok(Self(Some(Arc::new(Node{parent:self.clone(),name:actual,origin,definition,projected:projected.cloned(),depth,credit}))))
 }
 pub(super) fn popped_using(&self,depth:usize,a:&SettingAdmission<'_>)->io::Result<Self>{self.check(a)?;let node=self.0.as_deref().ok_or(io::ErrorKind::InvalidInput)?;if node.depth!=depth.checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?{return Err(io::ErrorKind::InvalidInput.into())}Ok(node.parent.clone())}
 /// Exact actual allocations only. Caller deduplicates repeated parent/node
 /// aliases by address; conservative quota reservation is never a heap row.
 pub(super) fn visit_storage(&self,mut visit:impl FnMut(usize,usize,usize)){let mut node=self.0.as_ref();while let Some(actual)=node{visit(Arc::as_ptr(actual)as usize,1,mem::size_of::<Node>()+2*mem::size_of::<usize>());if let Some(name)=&actual.name{name.visit_allocation(|p,n|visit(p,n,n));}if let Some(definition)=&actual.projected{definition.visit_storage(&mut visit)}actual.credit.visit_counter_storage(|p,n|visit(p,1,n));node=actual.parent.0.as_ref();}}
 /// Borrow current-to-outer lineage without a copied Vec/dictionary or source
 /// authority. Caller may reverse its already-funded retained output recipe.
 pub(super) fn visit_inner_to_outer_using(&self,a:&SettingAdmission<'_>,mut visit:impl FnMut(OriginalOutputTraceView<'_>)->io::Result<()>)->io::Result<()>{
  self.check(a)?;let mut node=self.0.as_deref();while let Some(actual)=node{poll(a)?;if !a.matches_lease_domain(&actual.credit){return Err(io::ErrorKind::InvalidInput.into())}visit(OriginalOutputTraceView{name:actual.name(),origin:actual.origin,definition:actual.definition,projected:actual.projected.as_ref(),depth:actual.depth})?;node=actual.parent.0.as_deref();}Ok(())
 }
}

#[cfg(test)]mod tests{
 use super::*;use std::sync::atomic::{Ordering};
 #[test]
 fn authored_trace_name_reuses_only_exact_admitted_epoch_and_preserves_first_error(){
  use std::{cell::Cell,path::PathBuf};
  let fixed=dm_syntax::SettingChargeCounter::root_allocation_bytes();
  let used=dm_syntax::SettingChargeCounter::try_new(fixed).unwrap();
  let a=SettingAdmission::new(&used,1<<20,&||Ok(()));
  let other=dm_syntax::SettingChargeCounter::try_new(fixed).unwrap();
  let foreign=SettingAdmission::new(&other,1<<20,&||Ok(()));
  let authored=super::super::DefinitionOrigin{
   path:Arc::new(PathBuf::from("E:/actual.dm")),source_span:dm_syntax::Span::new(5,12),source_line:2,
  };
  let name="ACTUAL_MACRO";
  let owner=OriginalMacroAuthor::new_using(name,Some(authored.clone()),&a).unwrap();
  let foreign_owner=OriginalMacroAuthor::new_using(name,Some(authored),&foreign).unwrap();
  let definition=Origin{physical:dm_syntax::Span::new(5,12),line:2,byte_column:Some(1),occurrence:0,invocation:false};
  let invocation=Origin{physical:dm_syntax::Span::new(15,27),line:3,invocation:true,..definition};
  let trace=OriginalOutputTrace::default();
  let node_bytes=mem::size_of::<Node>()+2*mem::size_of::<usize>();
  let before=used.load(Ordering::Acquire);
  let one_short=SettingAdmission::new(&used,before+node_bytes-1,&||Ok(()));
  assert_eq!(trace.pushed_with_definition_using(name,invocation,1,Some(definition),Some(&owner),&one_short).err().unwrap().kind(),io::ErrorKind::OutOfMemory);
  assert_eq!(used.load(Ordering::Acquire),before);
  let poll_count=Cell::new(0);
  let fault=||{poll_count.set(poll_count.get()+1);if poll_count.get()==4{Err(io::Error::from_raw_os_error(1450))}else{Ok(())}};
  let interrupted=SettingAdmission::new(&used,1<<20,&fault);
  assert_eq!(trace.pushed_with_definition_using(name,invocation,1,Some(definition),Some(&owner),&interrupted).err().unwrap().raw_os_error(),Some(1450));
  assert_eq!(used.load(Ordering::Acquire),before);
  let exact=SettingAdmission::new(&used,before+node_bytes,&||Ok(()));
  let retained=trace.pushed_with_definition_using(name,invocation,1,Some(definition),Some(&owner),&exact).unwrap();
  assert_eq!(used.load(Ordering::Acquire),before+node_bytes,"only the actual trace node is newly allocated");
  let address=owner.name().as_ptr();
  let mut matched=false;
  retained.visit_inner_to_outer_using(&a,|row|{
   assert_eq!(row.name.as_ptr(),address);
   assert!(Arc::ptr_eq(row.projected.unwrap(),&owner));
   matched=true;
   Ok(())
  }).unwrap();
  assert!(matched);
  drop(retained);
  assert_eq!(used.load(Ordering::Acquire),before);
  for (spelling,author) in [("OTHER_MACRO",&owner),(name,&foreign_owner)]{
   let fallback=trace.pushed_with_definition_using(spelling,invocation,1,Some(definition),Some(author),&a).unwrap();
   assert!(used.load(Ordering::Acquire)>before+node_bytes);
   fallback.visit_inner_to_outer_using(&a,|row|{
    assert_eq!(row.name,spelling);
    assert_ne!(row.name.as_ptr(),author.name().as_ptr());
    Ok(())
   }).unwrap();
   drop(fallback);
   assert_eq!(used.load(Ordering::Acquire),before);
  }
  let detached=trace.pushed_with_definition_using(name,invocation,1,Some(definition),Some(&owner),&a).unwrap();
  drop(owner);
  detached.visit_inner_to_outer_using(&a,|row|{assert_eq!(row.name.as_ptr(),address);Ok(())}).unwrap();
  drop((detached,foreign_owner,trace));
  assert_eq!(used.load(Ordering::Acquire),fixed);
  assert_eq!(other.load(Ordering::Acquire),fixed);
 }

 #[test]fn last_alias_reclaims_long_parent_chain_iteratively_without_refunding_live_middle_alias(){
  let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,8<<20,&||Ok(()));let origin=Origin{physical:dm_syntax::Span::new(0,1),line:1,byte_column:Some(1),occurrence:0,invocation:true};let mut current=OriginalOutputTrace::default();let mut middle=None;for depth in 1..=4096{current=current.pushed_using("m",origin,depth,None,&a).unwrap();if depth==2048{middle=Some(current.clone())}}drop(current);assert!(used.load(Ordering::Acquire)>dm_syntax::SettingChargeCounter::root_allocation_bytes());assert_eq!(middle.as_ref().unwrap().depth(),2048);drop(middle);assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
 }
}

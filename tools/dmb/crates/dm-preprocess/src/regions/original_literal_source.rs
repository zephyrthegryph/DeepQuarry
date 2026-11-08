//! Actual final-primary fact/source association. The genuine demand driver is
//! the only issuer. No strong whole-TU SourceText, parser/model/cache is pinned.
//! Header installation still checks its actual primary context and source view;
//! equal text/backing alone cannot substitute an old producer's typed facts.
use crate::{SourceText,WeakSourceText};
use dm_syntax::{OriginalPrimaryLiteralFacts,OriginalLiteralFactsView,SettingAdmission,SettingRootLease,Span};
use std::{io,sync::Arc};
struct Binding{source:WeakSourceText,facts:OriginalPrimaryLiteralFacts,credit:SettingRootLease}
/// Opaque SAME actual final-primary owner. Private Arc has no Weak/Arc escape;
/// its last control allocation dies before the payload/credit destructor.
pub struct OriginalLiteralSourceBinding(Option<Arc<Binding>>);
impl Clone for OriginalLiteralSourceBinding{fn clone(&self)->Self{Self(Some(self.0.as_ref().expect("live source binding").clone()))}}
impl Drop for OriginalLiteralSourceBinding{fn drop(&mut self){if let Some(owner)=self.0.take(){if let Some(binding)=Arc::into_inner(owner){drop(binding)}}}}
/// Cheap bounded view of that SAME owner, not another fact roster/source store.
#[derive(Clone)]pub struct OriginalLiteralSourceView{binding:OriginalLiteralSourceBinding,window:Span}
fn poll(a:&SettingAdmission<'_>)->io::Result<()>{a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))}
fn require_source_view(source:&WeakSourceText,actual:&SourceText,window:Span)->io::Result<()>{
 let source=source.upgrade().ok_or_else(||io::Error::new(io::ErrorKind::NotConnected,"actual primary source backing expired"))?;let expected=source.checked_view(window.range()).ok_or(io::ErrorKind::InvalidInput)?;if !expected.same_view(actual){return Err(io::Error::new(io::ErrorKind::InvalidInput,"header does not lend the actual primary source view"))}Ok(())
}
impl OriginalLiteralSourceBinding{
 fn payload(&self)->&Binding{self.0.as_deref().expect("live source binding")}
 /// Only finalization of the SAME actual driver invokes this after moving the
 /// original fact owner and the one sealed output arena. No external Vec/data
 /// constructor is exposed, and a numeric window is not source authorization.
 pub(in crate::regions) fn issue_actual(source:&SourceText,mut facts:OriginalPrimaryLiteralFacts,output:&super::original_prepared_output::OriginalOutputIdentity,actual_eof:bool,a:&SettingAdmission<'_>)->io::Result<Self>{
  poll(a)?;if !facts.is_admitted_by(a)||facts.consumed_extent()!=Some(source.as_str().len()){return Err(io::Error::new(io::ErrorKind::InvalidInput,"actual source/fact frontier or resource owner differs"))}
  if facts.projection_owner().is_some_and(|owner|!output.matches_projection_data(owner)){return Err(io::Error::new(io::ErrorKind::InvalidInput,"projected spelling belongs to another actual output"))}
  facts.checked_data_window(Span::new(0,source.as_str().len()))?;
  if actual_eof {
   let _released = facts.settle_delivered_body_singletons(source.as_str(),a)?;
   #[cfg(debug_assertions)]
   if std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some() {
    eprintln!("ORIGINAL_DELIVERED_SINGLETON_RECONCILIATION released_bytes={_released}");
   }
  }
  let credit=a.reserve(std::mem::size_of::<Binding>()+2*std::mem::size_of::<usize>()).map_err(|e|a.take_operational_error().unwrap_or(e))?;
  Ok(Self(Some(Arc::new(Binding{source:source.downgrade(),facts,credit}))))
 }
 pub fn same_producer(&self,other:&Self)->bool{Arc::ptr_eq(self.0.as_ref().expect("live source binding"),other.0.as_ref().expect("live source binding"))}
 /// The caller supplies its independently retained actual primary outcome
 /// owner. A previous owner's equal spelling/backing cannot pass this check.
 pub fn checked_view(&self,actual_source:&SourceText,window:Span,actual_primary:&Self,a:&SettingAdmission<'_>)->io::Result<OriginalLiteralSourceView>{
  poll(a)?;if !self.same_producer(actual_primary)||!a.matches_lease_domain(&self.payload().credit)||!self.payload().facts.is_admitted_by(a){return Err(io::Error::new(io::ErrorKind::InvalidInput,"foreign current primary literal owner"))}
  require_source_view(&self.payload().source,actual_source,window)?;
  self.payload().facts.checked_data_window(window)?;
  Ok(OriginalLiteralSourceView{binding:self.clone(),window})
 }
 pub fn visit_storage(&self,mut visit:impl FnMut(usize,usize,usize)){
  let owner=self.0.as_ref().expect("live source binding");let fixed=std::mem::size_of::<Binding>()+2*std::mem::size_of::<usize>();visit(Arc::as_ptr(owner)as usize,fixed,fixed);owner.credit.visit_counter_storage(|p,n|visit(p,n,n));owner.facts.visit_storage(&mut visit);owner.source.visit_backing_storage(&mut visit);owner.source.visit_derived_resource_storage(|p,n|visit(p,n,n));
 }
}
impl OriginalLiteralSourceView{
 pub fn same_producer(&self,actual_primary:&OriginalLiteralSourceBinding)->bool{self.binding.same_producer(actual_primary)}
 /// Actual current HeaderInput supplies its immutable source on every getter;
 /// geometry/backing failure stays Err, never a false None/unavailable model.
 pub fn checked_facts<'a>(&'a self,actual_source:&'a SourceText)->io::Result<OriginalLiteralFactsView<'a>>{
  require_source_view(&self.binding.payload().source,actual_source,self.window)?;self.binding.payload().facts.checked_data_window(self.window)?.with_source_data(actual_source.as_str())
 }
 pub fn visit_storage(&self,visit:impl FnMut(usize,usize,usize)){self.binding.visit_storage(visit)}
}

#[cfg(test)]mod tests{
 use super::*;
 #[test]fn actual_weak_source_view_keeps_geometry_and_rejects_equal_text_foreign_backing(){
  let parent:SourceText="prefix123tail".to_owned().into();let weak=parent.downgrade();let view=parent.checked_view(6..9).unwrap();assert!(require_source_view(&weak,&view,Span::new(6,9)).is_ok());let foreign:SourceText="123".to_owned().into();assert_eq!(require_source_view(&weak,&foreign,Span::new(6,9)).unwrap_err().kind(),io::ErrorKind::InvalidInput);assert!(require_source_view(&weak,&view,Span::new(5,8)).is_err());assert!(require_source_view(&weak,&view,Span::new(6,99)).is_err());
 }
 #[test]fn expired_actual_weak_source_cannot_be_replaced_by_later_equal_spelling_or_address(){
  let parent:SourceText="same".to_owned().into();let weak=parent.downgrade();drop(parent);let later:SourceText="same".to_owned().into();assert_eq!(require_source_view(&weak,&later,Span::new(0,4)).unwrap_err().kind(),io::ErrorKind::NotConnected);
 }
}

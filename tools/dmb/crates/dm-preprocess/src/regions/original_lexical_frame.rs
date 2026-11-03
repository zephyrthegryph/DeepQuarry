//! Actual opened lexer-instance DATA identity. The SAME raw owner validates
//! provider currentness BEFORE issuing it. Neither equality nor this metadata
//! tag authorizes CODE/EOF/model roles or fresh quote advancement.
use crate::SourceAcquisitionLease;use dm_syntax::{SettingAdmission,SettingRootLease};use std::{io,sync::Arc};
struct Owner{acquisition:SourceAcquisitionLease,credit:SettingRootLease}
pub struct OriginalLexicalFrameIdentity(Option<Arc<Owner>>);
impl Clone for OriginalLexicalFrameIdentity{fn clone(&self)->Self{Self(Some(self.0.as_ref().expect("live actual lexical frame").clone()))}}
impl Drop for OriginalLexicalFrameIdentity{fn drop(&mut self){if let Some(owner)=self.0.take(){if let Some(owner)=Arc::into_inner(owner){drop(owner)}}}}
impl OriginalLexicalFrameIdentity{
 pub(in crate::regions) fn issue(acquisition:SourceAcquisitionLease,a:&SettingAdmission<'_>)->io::Result<Self>{let credit=a.reserve(std::mem::size_of::<Owner>()+2*std::mem::size_of::<usize>()).map_err(|e|a.take_operational_error().unwrap_or(e))?;Ok(Self(Some(Arc::new(Owner{acquisition,credit}))))}
 pub fn same_frame(&self,other:&Self)->bool{Arc::ptr_eq(self.0.as_ref().expect("live actual lexical frame"),other.0.as_ref().expect("live actual lexical frame"))}
 pub(in crate::regions) fn acquisition(&self)->&SourceAcquisitionLease{&self.0.as_deref().expect("live actual lexical frame").acquisition}
 pub(in crate::regions) fn admitted_by(&self,a:&SettingAdmission<'_>)->bool{a.matches_lease_domain(&self.0.as_deref().expect("live actual lexical frame").credit)}
 pub fn visit_metadata_storage(&self,mut visit:impl FnMut(usize,usize,usize)){let owner=self.0.as_ref().expect("live actual lexical frame");let fixed=std::mem::size_of::<Owner>()+2*std::mem::size_of::<usize>();visit(Arc::as_ptr(owner)as usize,fixed,fixed);owner.credit.visit_counter_storage(|p,n|visit(p,n,n));}
 pub fn visit_acquisition_storage(&self,visit:impl FnMut(crate::source_acquisition::AcquisitionStorage<'_>)){self.0.as_deref().expect("live actual lexical frame").acquisition.visit_storage(visit)}
}
impl std::fmt::Debug for OriginalLexicalFrameIdentity{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.debug_struct("OriginalLexicalFrameIdentity").finish_non_exhaustive()}}

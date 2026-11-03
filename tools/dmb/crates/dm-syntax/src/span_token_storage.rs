//! Immutable token DATA ownership, no parser/cache/source/completeness grant.
use crate::{SpanToken,SettingAdmission,SettingRootLease};
use std::{io,fmt,ops::Deref,sync::Arc};
struct SharedPayload{tokens:Vec<SpanToken>,credit:SettingRootLease}
/// The actual token Vec moves once; aliases retain its resource root. No Arc or
/// Weak escape exists, and control allocation dies before payload/credit.
pub struct SharedSpanTokens(Option<Arc<SharedPayload>>);
impl Clone for SharedSpanTokens{fn clone(&self)->Self{Self(Some(self.0.as_ref().expect("live shared tokens").clone()))}}
impl Drop for SharedSpanTokens{fn drop(&mut self){if let Some(owner)=self.0.take(){if let Some(payload)=Arc::into_inner(owner){drop(payload)}}}}
impl fmt::Debug for SharedSpanTokens{fn fmt(&self,f:&mut fmt::Formatter<'_>)->fmt::Result{f.debug_struct("SharedSpanTokens").field("len",&self.as_slice().len()).finish_non_exhaustive()}}
fn poll(a:&SettingAdmission<'_>)->io::Result<()>{a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))}
impl SharedSpanTokens{
 /// Resource-only move, not token/source authorization. The actual producer
 /// remains responsible for real grammar/ordering/current acquisition proof.
 pub fn from_admitted_using(tokens:Vec<SpanToken>,credit:SettingRootLease,a:&SettingAdmission<'_>)->io::Result<Self>{
  let mut pending=SharedPayload{tokens,credit};poll(a)?;
  let bytes=pending.tokens.capacity().checked_mul(std::mem::size_of::<SpanToken>()).ok_or(io::ErrorKind::OutOfMemory)?;
  if !a.matches_lease_domain(&pending.credit)||pending.credit.bytes()<bytes{return Err(io::Error::new(io::ErrorKind::InvalidInput,"shared tokens lack actual same-domain buffer admission"))}
  let fixed=std::mem::size_of::<SharedPayload>().checked_add(2*std::mem::size_of::<usize>()).ok_or(io::ErrorKind::OutOfMemory)?;
  a.grow(&mut pending.credit,fixed).map_err(|e|a.take_operational_error().unwrap_or(e))?;poll(a)?;
  Ok(Self(Some(Arc::new(pending))))
 }
 pub fn as_slice(&self)->&[SpanToken]{&self.0.as_ref().expect("live shared tokens").tokens}
 pub fn capacity(&self)->usize{self.0.as_ref().expect("live shared tokens").tokens.capacity()}
 pub fn same_owner(&self,other:&Self)->bool{Arc::ptr_eq(self.0.as_ref().unwrap(),other.0.as_ref().unwrap())}
 pub fn admitted_by(&self,a:&SettingAdmission<'_>)->bool{a.matches_lease_domain(&self.0.as_ref().unwrap().credit)}
 /// Allocation identity only, not semantic/source authority. Actual collector
 /// deduplicates across expanded/primary/header aliases at the same addresses.
 pub fn visit_storage(&self,mut visit:impl FnMut(usize,usize,usize)){
  let owner=self.0.as_ref().unwrap();let fixed=std::mem::size_of::<SharedPayload>()+2*std::mem::size_of::<usize>();visit(Arc::as_ptr(owner)as usize,fixed,fixed);
  if owner.tokens.capacity()!=0{visit(owner.tokens.as_ptr()as usize,owner.tokens.len()*std::mem::size_of::<SpanToken>(),owner.tokens.capacity()*std::mem::size_of::<SpanToken>())}
  owner.credit.visit_counter_storage(|p,n|{let n=n+2*std::mem::size_of::<usize>();visit(p,n,n)});
 }
}
/// Ordinary Native keeps its original owned Vec algorithms/clone behavior;
/// genuine final Original handoff shares one immutable actual allocation.
#[derive(Clone,Debug)]pub enum SpanTokenStorage{Owned(Vec<SpanToken>),Shared(SharedSpanTokens)}
impl Default for SpanTokenStorage{fn default()->Self{Self::Owned(Vec::new())}}
impl From<Vec<SpanToken>> for SpanTokenStorage{fn from(tokens:Vec<SpanToken>)->Self{Self::Owned(tokens)}}
impl From<SharedSpanTokens> for SpanTokenStorage{fn from(tokens:SharedSpanTokens)->Self{Self::Shared(tokens)}}
impl Deref for SpanTokenStorage{type Target=[SpanToken];fn deref(&self)->&Self::Target{match self{Self::Owned(tokens)=>tokens,Self::Shared(tokens)=>tokens.as_slice()}}}
impl AsRef<[SpanToken]> for SpanTokenStorage{fn as_ref(&self)->&[SpanToken]{self}}
impl PartialEq for SpanTokenStorage{fn eq(&self,other:&Self)->bool{self.as_ref()==other.as_ref()}}impl Eq for SpanTokenStorage{}
impl<'a>IntoIterator for &'a SpanTokenStorage{type Item=&'a SpanToken;type IntoIter=std::slice::Iter<'a,SpanToken>;fn into_iter(self)->Self::IntoIter{self.iter()}}
impl SpanTokenStorage{
 pub fn as_slice(&self)->&[SpanToken]{self}
 pub fn capacity(&self)->usize{match self{Self::Owned(tokens)=>tokens.capacity(),Self::Shared(tokens)=>tokens.capacity()}}
 pub fn shared(&self)->Option<&SharedSpanTokens>{match self{Self::Shared(tokens)=>Some(tokens),_=>None}}
 pub fn visit_storage(&self,mut visit:impl FnMut(usize,usize,usize)){match self{Self::Shared(tokens)=>tokens.visit_storage(visit),Self::Owned(tokens)=>{if tokens.capacity()!=0{visit(tokens.as_ptr()as usize,tokens.len()*std::mem::size_of::<SpanToken>(),tokens.capacity()*std::mem::size_of::<SpanToken>())}}}}
}
#[cfg(test)]mod tests{
 use super::*;use std::sync::atomic::{AtomicUsize,Ordering};
 #[test]fn actual_vec_moves_once_and_last_alias_keeps_same_buffer_credit_without_source_or_ast_owner(){let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let tokens=crate::lex_spans("a+2").tokens;let ptr=tokens.as_ptr();let credit=a.reserve(tokens.capacity()*std::mem::size_of::<SpanToken>()).unwrap();let shared=SharedSpanTokens::from_admitted_using(tokens,credit,&a).unwrap();let primary:SpanTokenStorage=shared.clone().into();let expanded:SpanTokenStorage=shared.clone().into();let header:SpanTokenStorage=shared.clone().into();assert_eq!(primary.as_ptr(),ptr);assert_eq!(expanded.as_ptr(),ptr);assert_eq!(header.as_ptr(),ptr);assert!(primary.shared().unwrap().same_owner(header.shared().unwrap()));let charge=used.load(Ordering::Acquire);drop((shared,primary,expanded));assert_eq!(used.load(Ordering::Acquire),charge);drop(header);assert_eq!(used.load(Ordering::Acquire),0);}
 #[test]fn foreign_short_and_first_io_refuse_without_losing_actual_storage_credit_and_fresh_handoff_recovers(){let used=Arc::new(AtomicUsize::new(0));let other=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let b=SettingAdmission::new(&other,1<<20,&||Ok(()));let tokens=crate::lex_spans("x").tokens;let n=tokens.capacity()*std::mem::size_of::<SpanToken>();assert_eq!(SharedSpanTokens::from_admitted_using(tokens,b.reserve(n).unwrap(),&a).unwrap_err().kind(),io::ErrorKind::InvalidInput);assert_eq!(other.load(Ordering::Acquire),0);let tokens=crate::lex_spans("x").tokens;assert_eq!(SharedSpanTokens::from_admitted_using(tokens,a.reserve(0).unwrap(),&a).unwrap_err().kind(),io::ErrorKind::InvalidInput);let fault=||Err(io::Error::from_raw_os_error(1450));let fail=SettingAdmission::new(&used,1<<20,&fault);let tokens=crate::lex_spans("x").tokens;let n=tokens.capacity()*std::mem::size_of::<SpanToken>();assert_eq!(SharedSpanTokens::from_admitted_using(tokens,a.reserve(n).unwrap(),&fail).unwrap_err().raw_os_error(),Some(1450));assert_eq!(used.load(Ordering::Acquire),0);let tokens=crate::lex_spans("x").tokens;let n=tokens.capacity()*std::mem::size_of::<SpanToken>();drop(SharedSpanTokens::from_admitted_using(tokens,a.reserve(n).unwrap(),&a).unwrap());assert_eq!(used.load(Ordering::Acquire),0);}
}

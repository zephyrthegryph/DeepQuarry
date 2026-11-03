//! Resource-only credit for the native transformed source arena. No source,
//! token, EOF, declaration or semantic authorization is carried by this value.
use std::{any::Any,io,sync::Arc};
/// Host-private issuer implements this for one actual allocation reservation.
/// The native host verifies its own concrete owner and existing resource domain.
pub trait SourceArenaCreditOwner:Send+Sync{
 fn as_any(&self)->&dyn Any;
 fn reserved_bytes(&self)->usize;
 fn visit_storage(&self,visit:&mut dyn FnMut(usize,usize));
}
/// Move-only. SourceText retains this with its last physical backing owner;
/// cloning a SourceText aliases that backing, never duplicates this reservation.
pub struct SourceArenaCredit{owner:Arc<dyn SourceArenaCreditOwner>}
/// Immutable control-block credit. Clones pay no allocation and cannot be grown
/// or converted back into a mutable payload reservation.
#[derive(Clone)]pub struct SourceArenaControlCredit{owner:Arc<dyn SourceArenaCreditOwner>}
impl SourceArenaControlCredit{
 pub fn reserved_bytes(&self)->usize{self.owner.reserved_bytes()}
 pub fn owner(&self)->&dyn SourceArenaCreditOwner{self.owner.as_ref()}
 pub fn visit_storage(&self,visit:&mut dyn FnMut(usize,usize)){self.owner.visit_storage(visit)}
}
impl SourceArenaCredit{
 pub fn into_control(self)->SourceArenaControlCredit{SourceArenaControlCredit{owner:self.owner}}
 pub fn from_resource_owner(owner:Arc<dyn SourceArenaCreditOwner>)->Self{Self{owner}}
 pub fn reserved_bytes(&self)->usize{self.owner.reserved_bytes()}
 pub fn owner(&self)->&dyn SourceArenaCreditOwner{self.owner.as_ref()}
 pub fn visit_storage(&self,visit:&mut dyn FnMut(usize,usize)){self.owner.visit_storage(visit)}
}
/// Borrowed operation lender. Retained credits must not retain this lender,
/// QueryDb, the source census, a source model or an independent budget manager.
/// Reserve the complete new allocation while old storage is still live. Shrink
/// only AFTER physical release. A failed allocation keeps its peak reservation
/// until credit drop, so cleanup cannot replace the original operational error.
pub trait SourceArenaWork:Send+Sync{
 /// Existing family bookkeeping pregrant for the actual maximum source/object
 /// observation count. No semantic authority or second budget is issued.
 fn original_read_bookkeeping_bytes(&self)->io::Result<usize>{Err(io::Error::new(io::ErrorKind::NotConnected,"host cannot fund Original read observations"))}
 /// Settle actual read allocations before the provider may return/fail after
 /// exceptional publication. Cleanup operation: do not checkpoint mid-commit.
 fn adopt_original_read(&self,_credit:&mut SourceArenaCredit,_source:&crate::SourceAcquisitionLease)->io::Result<()>{Err(io::Error::new(io::ErrorKind::NotConnected,"host cannot adopt Original read observations"))}
 fn checkpoint(&self)->io::Result<()>;
 fn reserve(&self,bytes:usize)->io::Result<SourceArenaCredit>;
 fn grow(&self,credit:&mut SourceArenaCredit,extra:usize)->io::Result<()>;
 fn shrink(&self,credit:&mut SourceArenaCredit,bytes:usize)->io::Result<()>;
}

/// One operation-local read owner in the SAME existing input-family. No family
/// gate spans provider IO, decoding, source-stack or parser callbacks. Its peak
/// reservation disappears only after acquired() registers actual weak owners.
pub fn read_original_source_using(provider:&dyn crate::SourceProvider,path:&std::path::Path,max_bytes:usize,work:&dyn SourceArenaWork)->io::Result<Option<crate::SourceAcquisitionLease>>{
 struct Funding{credit:SourceArenaCredit,raw:Option<usize>,planned:bool,new_source:bool,delivered:bool}
 let bookkeeping=work.original_read_bookkeeping_bytes()?;
 let funding=std::cell::RefCell::new(Funding{credit:work.reserve(bookkeeping)?,raw:None,planned:false,new_source:false,delivered:false});
 let pending=provider.original_raw_source_admitted(path,max_bytes,&mut |capacity|{
  let mut state=funding.borrow_mut();if state.raw.is_some()||capacity>max_bytes{return Err(io::Error::new(io::ErrorKind::InvalidInput,"Original raw provider repeated/exceeded actual preallocation"))}work.grow(&mut state.credit,capacity)?;state.raw=Some(capacity);Ok(())
 },&mut |plan|{
  let mut state=funding.borrow_mut();if state.planned{return Err(io::Error::new(io::ErrorKind::InvalidInput,"Original raw provider repeated decode allocation plan"))}
  if plan.needs_decode(){
   if state.raw!=Some(plan.capacity())||plan.original().len()>plan.capacity(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"Original decode plan differs from SAME admitted raw buffer"))}
   // Exact count is issued by SAME actual decoder's before_allocate(size),
   // not another whole-file decoder walk in this resource-only wrapper.
   if !plan.exceptional()&&plan.decoded_bytes()!=0{return Err(io::Error::new(io::ErrorKind::InvalidInput,"UTF8 move plan claims a second decoded buffer"))}
   let bytes=plan.constructor_bytes().checked_add(plan.decoded_bytes()).ok_or(io::ErrorKind::OutOfMemory)?;work.grow(&mut state.credit,bytes)?;
  }else if state.raw.is_some()||plan.capacity()!=0||plan.constructor_bytes()!=0||plan.decoded_bytes()!=0{return Err(io::Error::new(io::ErrorKind::InvalidInput,"prepaid Original subject plan attempts new backing allocation"))}
  state.planned=true;state.new_source=plan.needs_decode();Ok(())
 },&mut |source|{
  let mut state=funding.borrow_mut();if !state.planned||state.delivered{return Err(io::Error::new(io::ErrorKind::InvalidInput,"Original provider delivered outside its actual allocation plan"))}
  if state.new_source{work.adopt_original_read(&mut state.credit,source)?;}
  state.delivered=true;Ok(())
 });
 // Provider errors, including acquired callback errors, are returned unchanged.
 // Existing native provider publishes exceptional bytes only immediately before
 // acquired(); native adoption registers every actual weak owner before denial.
 let result=pending?;
 if result.is_some()&&!funding.borrow().delivered{return Err(io::Error::new(io::ErrorKind::InvalidInput,"Original provider bypassed acquired ownership settlement"))}
 Ok(result)
}

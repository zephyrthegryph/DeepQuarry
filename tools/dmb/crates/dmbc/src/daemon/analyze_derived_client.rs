//! Existing process-local delivery allowance with actual allocation peaks.
//! No resident counter/model is fabricated across IPC. Large text remains a
//! serde-issued raw JSON loan; neither an owned report nor ALLOW set is decoded.
use super::{AnalyzeRequest,Admission,LIMIT,invalid,AttemptKind};
use super::super::{protocol,transport};
use dq_analyze::policy_finish::{admitted::Work,derived_wire};
use std::{cell::RefCell,error::Error,io::{self,Write}};
const FRAME_PEAK:usize=4*protocol::MAX_FRAME+4096;
struct DeliveryWork{admission:RefCell<Admission>,slots:RefCell<[usize;4]>}
impl DeliveryWork{fn new()->Self{Self{admission:RefCell::new(Admission::default()),slots:RefCell::new([0;4])}}}
impl Work for DeliveryWork{
 fn checkpoint(&self)->io::Result<()>{if self.admission.borrow().denied{Err(io::ErrorKind::OutOfMemory.into())}else{Ok(())}}
 fn reserve(&self,n:usize)->io::Result<()>{self.admission.borrow_mut().add(n)}
 fn temporary(&self,slot:usize,n:usize)->io::Result<()>{self.checkpoint()?;let mut slots=self.slots.borrow_mut();let old=*slots.get(slot).ok_or_else(||self.overflow())?;if n>old{self.reserve(n-old)?;slots[slot]=n}Ok(())}
 fn overflow(&self)->io::Error{self.admission.borrow_mut().denied=true;io::ErrorKind::OutOfMemory.into()}
}
/// Bytes drop before their actual operation allowance. All decoded strings are
/// borrowed from this buffer, and parser scratch dies before it is returned.
pub(super) struct Delivered{bytes:Vec<u8>,work:DeliveryWork,clean:bool,complete:bool,kind:AttemptKind}
impl Delivered{
 pub(super) fn bytes(&self)->&[u8]{&self.bytes}pub(super) fn clean(&self)->bool{self.clean}pub(super) fn complete(&self)->bool{self.complete}
 fn append(&mut self,part:&[u8])->io::Result<()>{let needed=self.bytes.len().checked_add(part.len()).filter(|n|*n<=LIMIT).ok_or_else(||self.work.overflow())?;if needed>self.bytes.capacity(){let cap=needed.max(self.bytes.capacity().saturating_mul(2)).max(65_536);let new=cap.checked_mul(4).and_then(|n|n.checked_add(self.bytes.capacity())).and_then(|n|n.checked_add(64)).ok_or_else(||self.work.overflow())?;self.work.temporary(1,new)?;self.bytes.try_reserve_exact(cap-self.bytes.len()).map_err(|_|self.work.overflow())?;if self.bytes.capacity()>cap.saturating_mul(4){return Err(self.work.overflow())}}self.bytes.extend_from_slice(part);Ok(())}
 pub(super) fn write_allow_usage_best_effort(&self){if !self.complete{return}
 let write=|file:&mut std::fs::File|match self.kind{
  AttemptKind::Derived=>derived_wire::validate(&self.bytes,self.clean,&self.work)?.write_allow_usage(file),
  AttemptKind::Handlers=>derived_wire::validate_handlers(&self.bytes,self.clean,&self.work)?.write_allow_usage(file),
 };
if let Some(path)=std::env::var_os("DQ_ALLOW_USAGE").filter(|v|!v.is_empty()){if let Ok(mut file)=std::fs::OpenOptions::new().create(true).append(true).open(path){let _=write(&mut file);}}}
}
#[derive(Debug)]struct DeliveryFailure{first:Box<dyn Error>,_work:DeliveryWork}
impl std::fmt::Debug for DeliveryWork{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.debug_struct("DeliveryWork").finish_non_exhaustive()}}
impl std::fmt::Display for DeliveryFailure{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{std::fmt::Display::fmt(self.first.as_ref(),f)}}
impl Error for DeliveryFailure{fn source(&self)->Option<&(dyn Error+'static)>{Some(self.first.as_ref())}}
pub(super) fn receive(request:AnalyzeRequest,kind:AttemptKind,diagnostics:&mut impl Write)->Result<Delivered,Box<dyn Error>>{
 let mut delivered=Delivered{bytes:Vec::new(),work:DeliveryWork::new(),clean:false,complete:false,kind};
 let result=(||->Result<(bool,bool),Box<dyn Error>>{delivered.work.temporary(0,FRAME_PEAK)?;let mut stream=super::super::connect_generation()?;transport::set_timeout(&mut stream,transport::BUILD_DEADLINE)?;let wire=match kind{AttemptKind::Derived=>protocol::Request::Derived(request),AttemptKind::Handlers=>protocol::Request::Handlers(request)};protocol::send(&mut stream,&wire)?;let mut sequence=0u32;let mut accepted=false;let mut diagnostic_bytes=0usize;
 loop{match protocol::receive::<protocol::Reply>(&mut stream)?{
  protocol::Reply::Accepted=>{if accepted{return Err(invalid("duplicate Derived acceptance").into())}accepted=true},
  protocol::Reply::Diagnostic{bytes,..}=>{if !accepted{return Err(invalid("Derived diagnostic precedes acceptance").into())}super::preparation_diagnostic(&bytes,&mut diagnostic_bytes,diagnostics)?},
  protocol::Reply::DerivedFragment{sequence:actual,offset,bytes}=>{if !accepted||actual!=sequence||offset!=delivered.bytes.len()as u64||bytes.is_empty()||bytes.len()>65_536{return Err(invalid("foreign/reordered Derived report fragment").into())}delivered.append(&bytes)?;sequence=sequence.checked_add(1).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?},
  protocol::Reply::DerivedFinished{clean,total,hash}=>{if !accepted||sequence==0||total!=delivered.bytes.len()as u64||hash!=xxhash_rust::xxh3::xxh3_128(&delivered.bytes){return Err(invalid("incomplete Derived report transport").into())}
   // Raw frame/fragment owners are now gone; slot0 may fund the later parser
   // scratch peak. Neither phase coexists, and high water never refunds early.
   let complete=match kind{
    AttemptKind::Derived=>derived_wire::validate(&delivered.bytes,clean,&delivered.work)?.complete(),
    AttemptKind::Handlers=>derived_wire::validate_handlers(&delivered.bytes,clean,&delivered.work)?.complete(),
   };
   return Ok((clean,complete))},
  protocol::Reply::Rejected(error)=>return Err(error.into()),_=>return Err(invalid("unexpected Derived report reply").into()),
 }}
 })();match result{Ok((clean,complete))=>{delivered.clean=clean;delivered.complete=complete;Ok(delivered)},Err(first)=>{let Delivered{bytes,work,..}=delivered;drop(bytes);Err(Box::new(DeliveryFailure{first,_work:work}))}}
}

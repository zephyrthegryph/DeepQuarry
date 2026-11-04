//! Recorded real reader-open outcomes. Replay never opens the original path;
//! duplicate suppression happens before even loading a journal payload file.
use super::*;
use crate::input_snapshot::{OriginalOpenedRead as Read,OriginalReadOpenStatus as Status,OriginalPayloadDigest,ImmutablePathFacts};
use dm_preprocess::{OriginalRawOpenDecision as Decision,source_arena_credit::SourceArenaWork};
impl Inputs{
 pub(super) fn original_open_with_journal(&self,path:&Path,limit:usize,work:&dyn SourceArenaWork,after_open:&mut dyn FnMut()->io::Result<Decision>,before_allocate:&mut dyn FnMut(usize)->io::Result<()>)->io::Result<Read>{
  if !path.is_absolute(){return Err(invalid("Original journal requires exact absolute lookup path"))}work.checkpoint()?;
  if let Self::Replay(journal)=self{
   let(status,payload)={let index=journal.index.lock().map_err(|_|invalid("verification mutex poisoned"))?;(index.original_open_v1.get(path).ok_or_else(||Journal::unknown(path))?,index.original_payload_v1.get(path))};
   if !status.is_readable(){return Ok(Read::SourceOpenFailed(status.error_using(work)?))}
   if after_open()?==Decision::Suppress{return Ok(Read::Suppressed)}
   let payload=payload.ok_or_else(||invalid("captured opened reader was suppressed: no payload authority for replay Read"))?;
   if payload.stamp.size>limit as u64{return Err(invalid("journal Original exceeds payload admission"))}
   // This is journal storage, not another source open. Its allocation still
   // goes through SAME actual read callback and bounded verified read kernel.
   let read=FileSystemInputs.read_policy_bounded_admitted(&journal.payload(payload.content),limit,before_allocate)?.ok_or_else(||invalid("journal cannot issue bounded payload read"))?;
   let(_,bytes,content)=read.into_parts();if content!=payload.content||bytes.len()as u64!=payload.stamp.size{return Err(invalid("journal Original payload checksum mismatch"))}
   return Ok(Read::Read(CapturedInputRead::from_verified(payload.stamp,bytes,content)))
  }
  let Self::Recording(journal)=self else{return FileSystemInputs.read_original_open_admitted(path,limit,work,after_open,before_allocate)};
  let(before,payload_before)={let index=journal.index.lock().map_err(|_|invalid("verification mutex poisoned"))?;(index.original_open_v1.clone(),index.original_payload_v1.clone())};
  let mut prepaid=Some(work.reserve(before.probe_pregrant(path)?)?);let payload_prepaid=work.reserve(payload_before.probe_pregrant(path)?)?;
  let called=std::cell::Cell::new(false);let decision=std::cell::Cell::new(None);let first=std::cell::RefCell::new(None);
  let result=FileSystemInputs.read_original_open_admitted(path,limit,work,&mut ||{
   let result=(||{if called.replace(true){return Err(invalid("physical provider repeated reader-open callback"))}let next=before.recorded_using(path,Status::Readable,prepaid.take().ok_or_else(||invalid("journal open pregrant consumed"))?,work)?;{
    let mut index=journal.index.lock().map_err(|_|invalid("verification mutex poisoned"))?;if !index.original_open_v1.same_owner(&before){return Err(io::Error::new(io::ErrorKind::Interrupted,"journal opened-reader capture raced before commit"))}index.original_open_v1=next;
   }let selected=after_open()?;decision.set(Some(selected));Ok(selected)})();match result{Ok(v)=>Ok(v),Err(error)=>{if first.borrow().is_none(){*first.borrow_mut()=Some(error)}Err(io::ErrorKind::Other.into())}}
  },&mut |size|{let result=if decision.get()!=Some(Decision::Read){Err(invalid("journal payload allocation before opened Read decision"))}else{before_allocate(size)};match result{Ok(())=>Ok(()),Err(error)=>{if first.borrow().is_none(){*first.borrow_mut()=Some(error)}Err(io::ErrorKind::Other.into())}}});
  if let Some(error)=first.into_inner(){return Err(error)}
  let result=result?;
  match &result{
   Read::SourceOpenFailed(error)=>{if called.get(){return Err(invalid("physical post-open failure mislabeled as source-open failure"))}if !crate::input_snapshot::original_source_open_failure(error){return Err(invalid("operational IO mislabeled as journal source-open failure"))}let status=Status::capture_using(error,work)?;let next=before.recorded_using(path,status,prepaid.take().ok_or_else(||invalid("failed-open journal pregrant consumed"))?,work)?;let mut index=journal.index.lock().map_err(|_|invalid("verification mutex poisoned"))?;if !index.original_open_v1.same_owner(&before){return Err(io::Error::new(io::ErrorKind::Interrupted,"journal failed-open capture raced"))}index.original_open_v1=next;},
   Read::Suppressed=>{if decision.get()!=Some(Decision::Suppress){return Err(invalid("journal suppression lacks actual opened decision"))}},
   Read::Read(read)=>{if decision.get()!=Some(Decision::Read){return Err(invalid("journal payload lacks actual opened read decision"))}let fact=OriginalPayloadDigest{stamp:read.stamp().clone(),content:read.content()};let next=payload_before.recorded_using(path,fact,payload_prepaid,work)?;
    // No index guard is held during payload IO or host callbacks.
    let payload=journal.payload(read.content());if !payload.exists(){fs::write(&payload,read.bytes())?;}
    let mut index=journal.index.lock().map_err(|_|invalid("verification mutex poisoned"))?;if !index.original_payload_v1.same_owner(&payload_before){return Err(io::Error::new(io::ErrorKind::Interrupted,"journal payload capture raced"))}index.original_payload_v1=next;
   }
  }Ok(result)
 }
}

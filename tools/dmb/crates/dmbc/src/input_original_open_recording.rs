//! SAME recorder's exact Original reader boundary. No parent enumeration,
//! normalized-path substitute, payload reread, or synthetic missing FileInput.
use super::*;
use dm_preprocess::{OriginalRawOpenDecision as Decision,OriginalRawReadOutcome as Outcome};
use dm_preprocess::source_arena_credit::SourceArenaWork;
#[derive(Clone,Debug,Eq,PartialEq,Serialize,Deserialize)]
pub(crate) struct OriginalPayloadDigest{pub(crate) stamp:Stamp,pub(crate) content:u128}
impl super::path_presence::ImmutableFactValue for OriginalPayloadDigest{}
impl<P:SnapshotProvider> RecordingInputs<P>{
 pub(super) fn capture_original_open_admitted(&self,path:&Path,limit:usize,work:&dyn SourceArenaWork,after_open:&mut dyn FnMut()->io::Result<Decision>,before_read:&mut dyn FnMut(usize)->io::Result<()>,before_decode:&mut dyn FnMut(dm_preprocess::OriginalRawAllocationPlan<'_>)->io::Result<()>,fund_text:Option<&dm_preprocess::source_arena_credit::OriginalReadTextFunding<'_>>,acquired:&mut dyn FnMut(&dm_preprocess::SourceAcquisitionLease)->io::Result<()>)->io::Result<Outcome>{
  if self.initial_environment!=dm_preprocess::InitialEnvironment::OriginalChecker0290{return Err(invalid("actual Original pipeline context required before reader open"))}
  if !path.is_absolute(){return Err(invalid("Original reader requires absolute actual lookup path"))}work.checkpoint()?;
  if let Some(source)=self.analysis_subject.as_ref().and_then(|subject|subject.source_for(path)){
   // The private captured subject is the genuine non-filesystem issuer. It
   // still decides suppression BEFORE lending prepaid bytes/decode/acquisition.
   if after_open()?==Decision::Suppress{return Ok(Outcome::Suppressed)}
   before_decode(dm_preprocess::OriginalRawAllocationPlan::new(&[],0,0,0,matches!(source.encoding(),dm_preprocess::SourceEncoding::Utf8Bom|dm_preprocess::SourceEncoding::IncompatibleOriginal),false))?;acquired(source.lease())?;return Ok(Outcome::Acquired(source.lease().clone()))
  }
  // Both persistent spines are prepaid before the provider's real OS open.
  let(before,payload_before)={let snapshot=self.snapshot.lock().map_err(|_|invalid("input capture mutex poisoned"))?;(snapshot.opened_reads.clone(),snapshot.original_payloads.clone())};
  let mut prepaid=Some(work.reserve(before.probe_pregrant(path)?)?);
  let payload_prepaid=work.reserve(payload_before.probe_pregrant(path)?)?;
  let called=std::cell::Cell::new(false);let decision=std::cell::Cell::new(None);let first=std::cell::RefCell::new(None);
  let result=self.provider.read_original_open_admitted(path,limit,work,&mut ||{
   let result=(||{if called.replace(true){return Err(invalid("provider repeated actual opened-reader decision"))}let next=before.recorded_original_using(path,OriginalReadOpenStatus::Readable,prepaid.take().ok_or_else(||invalid("opened-reader pregrant already consumed"))?,work,Some(&self.original_path_bank))?;{
    let mut snapshot=self.snapshot.lock().map_err(|_|invalid("input capture mutex poisoned"))?;if !snapshot.opened_reads.same_owner(&before){return Err(io::Error::new(io::ErrorKind::Interrupted,"concurrent opened-reader capture changed before commit"))}snapshot.opened_reads=next;
   }let actual=after_open()?;decision.set(Some(actual));Ok(actual)})();
   match result{Ok(value)=>Ok(value),Err(error)=>{if first.borrow().is_none(){*first.borrow_mut()=Some(error)}Err(io::ErrorKind::Other.into())}}
  },&mut |size|{
   let result=if decision.get()!=Some(Decision::Read){Err(invalid("provider requested payload allocation before genuine read decision"))}else{before_read(size)};
   match result{Ok(())=>Ok(()),Err(error)=>{if first.borrow().is_none(){*first.borrow_mut()=Some(error)}Err(io::ErrorKind::Other.into())}}
  });
  if let Some(error)=first.into_inner(){return Err(error)}
  match result?{
   OriginalOpenedRead::Suppressed=>{if !called.get()||decision.get()!=Some(Decision::Suppress){return Err(invalid("provider suppressed without actual opened-reader suppression"))}Ok(Outcome::Suppressed)},
   OriginalOpenedRead::SourceOpenFailed(error)=>{if called.get(){return Err(invalid("provider converted a post-open failure into source absence"))}if !original_source_open_failure(&error){return Err(error)}let status=OriginalReadOpenStatus::capture_using(&error,work)?;let next=before.recorded_original_using(path,status,prepaid.take().ok_or_else(||invalid("missing failed-open pregrant"))?,work,Some(&self.original_path_bank))?;let mut snapshot=self.snapshot.lock().map_err(|_|invalid("input capture mutex poisoned"))?;if !snapshot.opened_reads.same_owner(&before){return Err(io::Error::new(io::ErrorKind::Interrupted,"concurrent failed-open capture changed before commit"))}snapshot.opened_reads=next;self.root_failure_capture.note_recorded_failure(path,&before,&snapshot.opened_reads);Ok(Outcome::SourceOpenFailed(error))},
   OriginalOpenedRead::Read(read)=>{if decision.get()!=Some(Decision::Read){return Err(invalid("provider returned payload without actual opened-reader read decision"))}let(stamp,bytes,content)=read.into_parts();if stamp.size!=bytes.len()as u64||bytes.capacity()>limit{return Err(invalid("Original provider exceeded admitted payload size/capacity"))}let digest=OriginalPayloadDigest{stamp,content};let next=payload_before.recorded_original_using(path,digest,payload_prepaid,work,Some(&self.original_path_bank))?;{let mut snapshot=self.snapshot.lock().map_err(|_|invalid("input capture mutex poisoned"))?;if !snapshot.original_payloads.same_owner(&payload_before){return Err(io::Error::new(io::ErrorKind::Interrupted,"concurrent Original payload capture changed before commit"))}snapshot.original_payloads=next;}let lease=self.finish_exact_original_read_admitted(path,bytes,before_decode,fund_text,acquired)?;if let Some(subject)=&self.analysis_subject{subject.bind_actual_physical_root(path,&lease)?;}Ok(Outcome::Acquired(lease))}
  }
 }
}

#[cfg(test)]#[path="input_original_open_recording_tests.rs"]mod tests;

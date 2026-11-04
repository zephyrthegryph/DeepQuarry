//! Fixture-only actual raw source provider. Both Native source and Analyze
//! policy DATA are derived from ONE admitted physical byte read/acquisition.
use std::{collections::BTreeMap,path::{Path,PathBuf},sync::{Arc,Mutex},io::{self,Read}};
struct Receipt{issuer:Arc<()>,original:Option<Arc<Vec<u8>>>}
struct Captured{source:dm_preprocess::SourceAcquisitionLease,raw:dm_preprocess::SourceText}
pub struct Provider{rows:Mutex<BTreeMap<PathBuf,Captured>>,issuer:Arc<()>}
impl Provider{
 pub fn new()->Self{Self{rows:Mutex::new(BTreeMap::new()),issuer:Arc::new(())}}
 pub fn analyze_raw(&self,path:&Path,decoded:&dm_preprocess::SourceText)->dm_preprocess::SourceText{let rows=self.rows.lock().unwrap();let actual=rows.get(path).expect("compiled file must retain its actual original acquisition");assert!(actual.source.source_text().same_view(decoded),"raw policy view must come from the SAME original captured file");actual.raw.clone()}
}
impl dm_preprocess::SourceProvider for Provider{
 fn path_presence_admitted(&self,path:&Path,work:&dyn dm_preprocess::source_arena_credit::SourceArenaWork)->io::Result<bool>{
  work.checkpoint()?;
  // Metadata-only OS scratch is lent by the SAME caller before the actual
  // probe. No payload, map/path clone, source acquisition or cached guess.
  let bytes=path.as_os_str().len().checked_mul(4).and_then(|n|n.checked_add(std::mem::size_of::<std::fs::Metadata>()*4+1024)).ok_or(io::ErrorKind::OutOfMemory)?;let _scratch=work.reserve(bytes)?;
  let present=match std::fs::metadata(path){Ok(_)=>true,Err(actual)if matches!(actual.kind(),io::ErrorKind::NotFound|io::ErrorKind::NotADirectory)=>false,Err(actual)=>return Err(actual)};
  work.checkpoint()?;Ok(present)
 }
 fn initial_environment(&self)->dm_preprocess::InitialEnvironment{dm_preprocess::InitialEnvironment::OriginalChecker0290}
 fn original_batch_source(&self)->io::Result<Option<&(dyn dm_preprocess::SourceProvider+Sync)>>{Ok(Some(self))}
 fn read(&self,_:&Path)->Result<String,String>{Err("actual admitted Original raw acquisition required".into())}
 fn original_raw_source_admitted(&self,path:&Path,max:usize,before_read:&mut dyn FnMut(usize)->io::Result<()>,before_decode:&mut dyn FnMut(dm_preprocess::OriginalRawAllocationPlan<'_>)->io::Result<()>,acquired:&mut dyn FnMut(&dm_preprocess::SourceAcquisitionLease)->io::Result<()>)->io::Result<Option<dm_preprocess::SourceAcquisitionLease>>{let file=match std::fs::File::open(path){Ok(file)=>file,Err(actual)if actual.kind()==io::ErrorKind::NotFound=>return Ok(None),Err(actual)=>return Err(actual)};self.read_opened_source_admitted(path,file,max,before_read,before_decode,acquired)}
 fn original_raw_source_open_admitted(&self,path:&Path,max:usize,work:&dyn dm_preprocess::source_arena_credit::SourceArenaWork,after_open:&mut dyn FnMut()->io::Result<dm_preprocess::OriginalRawOpenDecision>,before_read:&mut dyn FnMut(usize)->io::Result<()>,before_decode:&mut dyn FnMut(dm_preprocess::OriginalRawAllocationPlan<'_>)->io::Result<()>,acquired:&mut dyn FnMut(&dm_preprocess::SourceAcquisitionLease)->io::Result<()>)->io::Result<dm_preprocess::OriginalRawReadOutcome>{
  work.checkpoint()?;let file=match std::fs::File::open(path){Ok(file)=>file,Err(actual)=>return match actual.kind(){io::ErrorKind::NotFound|io::ErrorKind::NotADirectory|io::ErrorKind::PermissionDenied|io::ErrorKind::InvalidInput=>Ok(dm_preprocess::OriginalRawReadOutcome::SourceOpenFailed(actual)),_=>Err(actual)}};
  if after_open()?==dm_preprocess::OriginalRawOpenDecision::Suppress{return Ok(dm_preprocess::OriginalRawReadOutcome::Suppressed)}
  self.read_opened_source_admitted(path,file,max,before_read,before_decode,acquired)?.map(dm_preprocess::OriginalRawReadOutcome::Acquired).ok_or_else(||io::Error::new(io::ErrorKind::InvalidData,"actual opened fixture source lost its read outcome"))
 }
 fn original_source_bytes<'a>(&'a self,lease:&'a dm_preprocess::SourceAcquisitionLease)->io::Result<Option<&'a[u8]>>{let receipt=lease.receipt::<Receipt>().ok_or(io::ErrorKind::InvalidInput)?;if !Arc::ptr_eq(&receipt.issuer,&self.issuer){return Err(io::ErrorKind::InvalidInput.into())}Ok(Some(receipt.original.as_ref().map_or_else(||lease.source_text().as_bytes(),|raw|raw.as_slice())))}
}

impl Provider{
 fn read_opened_source_admitted(&self,path:&Path,mut file:std::fs::File,max:usize,before_read:&mut dyn FnMut(usize)->io::Result<()>,before_decode:&mut dyn FnMut(dm_preprocess::OriginalRawAllocationPlan<'_>)->io::Result<()>,acquired:&mut dyn FnMut(&dm_preprocess::SourceAcquisitionLease)->io::Result<()>)->io::Result<Option<dm_preprocess::SourceAcquisitionLease>>{
  let mut rows=self.rows.lock().unwrap();
  if let Some(actual)=rows.get(path){let exceptional=actual.source.encoding()!=dm_preprocess::SourceEncoding::Utf8;before_decode(dm_preprocess::OriginalRawAllocationPlan::new(&[],0,0,0,exceptional,false))?;acquired(&actual.source)?;return Ok(Some(actual.source.clone()))}
  let before=file.metadata()?;let len=usize::try_from(before.len()).map_err(|_|io::ErrorKind::OutOfMemory)?;if len>max{return Err(io::ErrorKind::OutOfMemory.into())}
  before_read(len)?;let mut bytes=Vec::new();bytes.try_reserve_exact(len).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;if bytes.capacity()>len{return Err(io::Error::new(io::ErrorKind::OutOfMemory,"fixture raw allocator exceeded exact pregrant"))}bytes.resize(len,0);file.read_exact(&mut bytes)?;let mut extra=[0u8;1];if file.read(&mut extra)?!=0{return Err(io::Error::new(io::ErrorKind::Interrupted,"fixture source grew during actual read"))}let after=file.metadata()?;if after.len()!=before.len()||after.modified()?!=before.modified()?{return Err(io::ErrorKind::Interrupted.into())}
  let encoding=if std::str::from_utf8(&bytes).is_err(){dm_preprocess::SourceEncoding::IncompatibleOriginal}else if bytes.starts_with(b"\xef\xbb\xbf"){dm_preprocess::SourceEncoding::Utf8Bom}else{dm_preprocess::SourceEncoding::Utf8};let exceptional=encoding!=dm_preprocess::SourceEncoding::Utf8;let capacity=bytes.capacity();
  // Native input constructor, fixture raw-policy projection and map receipt
  // are all preadmitted before decoding or allocating those retained values.
  let constructor=dm_preprocess::SourceAcquisitionLease::raw_constructor_storage_bytes::<Receipt>()?.checked_add(capacity.checked_mul(8).ok_or(io::ErrorKind::OutOfMemory)?).and_then(|n|n.checked_add(path.as_os_str().len().checked_mul(8)?)).and_then(|n|n.checked_add(8192)).ok_or(io::ErrorKind::OutOfMemory)?;
  let mut bytes=Some(bytes);let decoded=if exceptional{dm_preprocess::decode_source_bytes_admitted(bytes.as_ref().unwrap(),&mut|n|before_decode(dm_preprocess::OriginalRawAllocationPlan::new(bytes.as_ref().unwrap(),capacity,constructor,n,true,true)),&mut||Ok(()))?}else{before_decode(dm_preprocess::OriginalRawAllocationPlan::new(bytes.as_ref().unwrap(),capacity,constructor,0,false,true))?;String::new()};
  let raw:dm_preprocess::SourceText=crate::util::universal_newlines(String::from_utf8_lossy(bytes.as_ref().unwrap()).into_owned()).into();
  let (decoded,original)=if exceptional{(decoded,Some(Arc::new(bytes.take().unwrap())))}else{(String::from_utf8(bytes.take().unwrap()).map_err(|_|io::ErrorKind::InvalidData)?,None)};
  let source=dm_preprocess::SourceAcquisitionLease::from_raw_original_decoded(decoded,encoding,Receipt{issuer:self.issuer.clone(),original});acquired(&source)?;rows.insert(path.to_path_buf(),Captured{source:source.clone(),raw});Ok(Some(source))

 }
}

#[cfg(test)]#[path="../../dmb/shared/test_scratch.rs"]mod open_fixture_scratch;
#[cfg(test)]mod opened_reader_controls{
 use super::open_fixture_scratch as scratch;
 use super::*;use dm_preprocess::SourceProvider;use std::cell::Cell;

 struct Work;impl dm_preprocess::source_arena_credit::SourceArenaWork for Work{fn checkpoint(&self)->io::Result<()>{Ok(())}fn reserve(&self,_:usize)->io::Result<dm_preprocess::source_arena_credit::SourceArenaCredit>{panic!("the real outer producer owns its resource reservation")}fn grow(&self,_:&mut dm_preprocess::source_arena_credit::SourceArenaCredit,_:usize)->io::Result<()>{panic!("outer producer")}fn shrink(&self,_:&mut dm_preprocess::source_arena_credit::SourceArenaCredit,_:usize)->io::Result<()>{panic!("outer producer")}}
 #[test]fn real_open_precedes_suppression_and_no_payload_hook_runs_for_suppressed_reader(){let root=scratch::dir("handler-fixture-open-before-suppress");let path=root.join("source.dm");std::fs::write(&path,b"#error suppression must avoid this payload\n").unwrap();let source=Provider::new();let opened=Cell::new(0);let result=source.original_raw_source_open_admitted(&path,0,&Work,&mut||{opened.set(opened.get()+1);Ok(dm_preprocess::OriginalRawOpenDecision::Suppress)},&mut|_|panic!("suppressed source must not ask for payload admission"),&mut|_|panic!("suppressed source must not decode"),&mut|_|panic!("suppressed source must not issue a source acquisition")).unwrap();assert!(matches!(result,dm_preprocess::OriginalRawReadOutcome::Suppressed));assert_eq!(opened.get(),1);assert!(source.rows.lock().unwrap().is_empty());}
 #[test]fn missing_real_file_is_source_open_failure_before_duplicate_decision_not_absence_or_suppression(){let root=scratch::dir("handler-fixture-missing-open");let source=Provider::new();let result=source.original_raw_source_open_admitted(&root.join("missing.dm"),0,&Work,&mut||panic!("no actual opened reader exists"),&mut|_|panic!("no payload"),&mut|_|panic!("no decode"),&mut|_|panic!("no acquisition")).unwrap();assert!(matches!(result,dm_preprocess::OriginalRawReadOutcome::SourceOpenFailed(actual)if actual.kind()==io::ErrorKind::NotFound));}
}

#[cfg(test)]mod presence_controls{
 use super::*;use dm_preprocess::{SourceProvider,source_arena_credit::{SourceArenaWork,SourceArenaCredit,SourceArenaCreditOwner}};use std::{any::Any,sync::atomic::{AtomicUsize,Ordering}};
 struct Credit{n:usize,used:Arc<AtomicUsize>}
 impl Drop for Credit{fn drop(&mut self){self.used.fetch_sub(self.n,Ordering::AcqRel);}}
 impl SourceArenaCreditOwner for Credit{fn as_any(&self)->&dyn Any{self}fn reserved_bytes(&self)->usize{self.n}fn visit_storage(&self,visit:&mut dyn FnMut(usize,usize)){visit(self as*const Self as usize,std::mem::size_of::<Self>()+2*std::mem::size_of::<usize>())}}
 struct Work{used:Arc<AtomicUsize>,entries:AtomicUsize,limit:usize,fail:bool}
 impl Work{fn new(limit:usize)->Self{Self{used:Arc::new(AtomicUsize::new(0)),entries:AtomicUsize::new(0),limit,fail:false}}}
 impl SourceArenaWork for Work{
  fn checkpoint(&self)->io::Result<()>{if self.fail{Err(io::Error::from_raw_os_error(1450))}else{Ok(())}}
  fn reserve(&self,n:usize)->io::Result<SourceArenaCredit>{self.checkpoint()?;let next=self.used.load(Ordering::Acquire).checked_add(n).ok_or(io::ErrorKind::OutOfMemory)?;if next>self.limit{return Err(io::ErrorKind::OutOfMemory.into())}self.used.store(next,Ordering::Release);self.entries.fetch_add(1,Ordering::AcqRel);Ok(SourceArenaCredit::from_resource_owner(Arc::new(Credit{n,used:Arc::clone(&self.used)})))}
  fn grow(&self,_:&mut SourceArenaCredit,_:usize)->io::Result<()>{panic!("presence scratch uses one exact existing caller loan")}
  fn shrink(&self,_:&mut SourceArenaCredit,_:usize)->io::Result<()>{panic!("presence scratch drops its exact actual owner")}
 }
 #[test]fn actual_admitted_presence_probes_same_provider_file_directory_and_missing_without_payload_or_cached_guess(){
  let root=super::open_fixture_scratch::dir("actual-provider-presence");let file=root.join("source.dm");std::fs::write(&file,b"do not read as source").unwrap();let provider=Provider::new();let work=Work::new(1<<20);
  assert!(provider.path_presence_admitted(&file,&work).unwrap());assert!(provider.path_presence_admitted(&root,&work).unwrap());assert!(!provider.path_presence_admitted(&file.join("nested"),&work).unwrap());std::fs::remove_file(&file).unwrap();assert!(!provider.path_presence_admitted(&file,&work).unwrap(),"a repeated actual probe cannot reuse prior presence");assert!(provider.rows.lock().unwrap().is_empty(),"metadata must not issue/read/decode any source payload");assert_eq!(work.used.load(Ordering::Acquire),0);assert_eq!(work.entries.load(Ordering::Acquire),4);
 }
 #[test]fn actual_admitted_presence_preserves_first_1450_and_quota_before_invalid_os_probe(){
  let provider=Provider::new();let invalid=Path::new("invalid\0path");let mut failed=Work::new(1<<20);failed.fail=true;let error=provider.path_presence_admitted(invalid,&failed).unwrap_err();assert_eq!(error.raw_os_error(),Some(1450));assert_eq!(failed.entries.load(Ordering::Acquire),0);let denied=Work::new(0);let error=provider.path_presence_admitted(invalid,&denied).unwrap_err();assert_eq!(error.kind(),io::ErrorKind::OutOfMemory,"quota refuses before malformed OS path can produce InvalidInput");assert_eq!(denied.used.load(Ordering::Acquire),0);assert!(provider.rows.lock().unwrap().is_empty());
 }
}

//! Small public-boundary proof target. Does not compile the monolithic unit-test
//! registry, run a game world, or substitute a source/model fixture authority.
#[path = "../../../shared/test_scratch.rs"]
mod test_scratch;
use dmbc::input_snapshot::{FileSystemInputs,SnapshotProvider,GeneratedOutputInputs,CapturedInputRead,Stamp,FolderListing};
use dm_preprocess::{SourceText,source_arena_credit::SourceArenaWork};
use std::{io,path::Path,sync::Arc};

#[test]
fn actual_single_handle_read_admits_before_payload_read() {
    let root=test_scratch::dir("actual-read-preallocation");let path=root.join("source.dm");std::fs::write(&path,b"1234").unwrap();
    let mut calls=0;
    let error=FileSystemInputs.read_policy_bounded_admitted(&path,4,&mut |size|{
        calls+=1;assert_eq!(size,4);std::fs::write(&path,b"")?;Ok(())
    }).unwrap_err();
    assert_eq!(calls,1);assert_eq!(error.kind(),io::ErrorKind::Interrupted);
}
#[test]
fn actual_exact_allocation_and_admission_error_keep_physical_bytes_and_io() {
    let root=test_scratch::dir("actual-read-preallocation-error");let path=root.join("source.dm");std::fs::write(&path,b"actual").unwrap();
    let error=FileSystemInputs.read_policy_bounded_admitted(&path,6,&mut |_|Err(io::Error::from_raw_os_error(1450))).unwrap_err();assert_eq!(error.raw_os_error(),Some(1450));
    let mut calls=0;let read=FileSystemInputs.read_policy_bounded_admitted(&path,6,&mut |size|{calls+=1;assert_eq!(size,6);Ok(())}).unwrap().unwrap();
    let(_,bytes,_)=read.into_parts();assert_eq!(calls,1);assert_eq!(bytes,b"actual");assert_eq!(bytes.capacity(),6);
}
#[test]
fn absent_or_oversized_physical_input_never_issues_an_allocation() {
    let root=test_scratch::dir("actual-read-preallocation-noallocation");let missing=root.join("missing.dm");
    assert_eq!(FileSystemInputs.read_policy_bounded_admitted(&missing,10,&mut |_|panic!("no opened source" )).unwrap_err().kind(),io::ErrorKind::NotFound);
    let path=root.join("large.dm");std::fs::write(&path,b"1234").unwrap();assert!(FileSystemInputs.read_policy_bounded_admitted(&path,3,&mut |_|panic!("size refused before allocation")).is_err());
}
#[test]
fn a_bounded_only_provider_cannot_synthesize_a_funded_read() {
    struct BoundedOnly;
    impl SnapshotProvider for BoundedOnly {
        fn stamp(&self,_:&Path)->io::Result<Stamp>{unreachable!()}
        fn read(&self,_:&Path)->io::Result<(Stamp,Vec<u8>)>{panic!("no unbounded fallback")}
        fn list(&self,_:&Path)->io::Result<FolderListing>{unreachable!()}
        fn read_policy_bounded(&self,_:&Path,_:usize)->io::Result<Option<CapturedInputRead>>{panic!("no read-then-fund fallback")}
    }
    assert!(BoundedOnly.read_policy_bounded_admitted(Path::new("unissued.dm"),100,&mut |_|panic!("no actual issuer")).unwrap().is_none());
}
#[test]
fn generated_output_filter_forwards_the_same_physical_admission_boundary() {
    let root=test_scratch::dir("actual-read-preallocation-generated");let path=root.join("source.dm");std::fs::write(&path,b"same").unwrap();
    let provider=GeneratedOutputInputs::new(FileSystemInputs,[path.clone()]);let mut calls=0;
    let read=provider.read_policy_bounded_admitted(&path,4,&mut |size|{calls+=1;assert_eq!(size,4);Ok(())}).unwrap().unwrap();assert_eq!(calls,1);assert_eq!(read.bytes(),b"same");
}
#[test]
fn real_native_input_lender_rejects_foreign_credit_and_preserves_denied_reservation() {
    let own=dmbc::query_db::QueryDb::default();let other=dmbc::query_db::QueryDb::default();let mut credit=SourceArenaWork::reserve(&own,32).unwrap();
    assert_eq!(SourceArenaWork::grow(&other,&mut credit,1).unwrap_err().kind(),io::ErrorKind::InvalidInput);assert_eq!(SourceArenaWork::shrink(&other,&mut credit,1).unwrap_err().kind(),io::ErrorKind::InvalidInput);assert_eq!(credit.reserved_bytes(),32);
    SourceArenaWork::grow(&own,&mut credit,7).unwrap();assert_eq!(credit.reserved_bytes(),39);assert_eq!(SourceArenaWork::grow(&own,&mut credit,usize::MAX).unwrap_err().kind(),io::ErrorKind::OutOfMemory);assert_eq!(credit.reserved_bytes(),39);SourceArenaWork::shrink(&own,&mut credit,7).unwrap();assert_eq!(credit.reserved_bytes(),32);
    assert_eq!(SourceArenaWork::reserve(&own,256*1024*1024).err().unwrap().kind(),io::ErrorKind::OutOfMemory);
}
#[test]
fn real_native_source_credit_does_not_retain_query_db_or_dead_payload() {
    let db=Arc::new(dmbc::query_db::QueryDb::default());let db_weak=Arc::downgrade(&db);let text=String::from("escaped actual native allocation");let pointer=text.as_ptr();let capacity=text.capacity();
    let payload=SourceArenaWork::reserve(db.as_ref(),capacity).unwrap();let control=SourceArenaWork::reserve(db.as_ref(),SourceText::source_arena_control_bytes().unwrap()).unwrap().into_control();let source=SourceText::from_source_arena(text,payload,control).unwrap();assert_eq!(source.as_str().as_ptr(),pointer);let weak=source.downgrade();drop(db);assert!(db_weak.upgrade().is_none());assert_eq!(source.source_arena_payload_credit().unwrap().reserved_bytes(),capacity);drop(source);assert!(weak.upgrade().is_none());let mut metadata=0;weak.visit_derived_resource_storage(|_,bytes|metadata+=bytes);assert!(metadata>0);drop(weak);
}

#[test]
fn admitted_journal_roundtrip_preserves_exact_invalid_bytes_and_original_file_stamp(){
    let root=test_scratch::dir("admitted-read-journal");let path=root.join("source.dm");let journal=root.join("journal");std::fs::write(&path,[0x80]).unwrap();
    let provider=dmbc::frozen_inputs::Inputs::record(&journal).unwrap();let mut calls=0;let original=provider.read_policy_bounded_admitted(&path,1,&mut |size|{calls+=1;assert_eq!(size,1);Ok(())}).unwrap().unwrap();assert_eq!(calls,1);assert_eq!(original.bytes(),[0x80]);provider.finish().unwrap();std::fs::remove_file(&path).unwrap();
    let replay=dmbc::frozen_inputs::Inputs::replay(&journal).unwrap();let mut replay_calls=0;let read=replay.read_policy_bounded_admitted(&path,1,&mut |size|{replay_calls+=1;assert_eq!(size,1);Ok(())}).unwrap().unwrap();assert_eq!(replay_calls,1);assert_eq!(read.bytes(),original.bytes());assert_eq!(read.stamp(),original.stamp());assert_eq!(read.content(),original.content());
}
#[test]
fn journal_resource_notfound_is_not_persisted_as_captured_source_absence(){
    let root=test_scratch::dir("admitted-read-journal-notfound");let path=root.join("source.dm");let journal=root.join("journal");std::fs::write(&path,b"present").unwrap();
    let provider=dmbc::frozen_inputs::Inputs::record(&journal).unwrap();let error=provider.read_policy_bounded_admitted(&path,7,&mut |_|Err(io::ErrorKind::NotFound.into())).unwrap_err();assert_eq!(error.kind(),io::ErrorKind::NotFound);provider.finish().unwrap();
    let replay=dmbc::frozen_inputs::Inputs::replay(&journal).unwrap();let error=replay.read_policy_bounded_admitted(&path,7,&mut |_|panic!("unknown source cannot allocate")).unwrap_err();assert_eq!(error.kind(),io::ErrorKind::InvalidData,"unknown input stayed unknown; not a captured missing input");
}

// Actual public Original opener boundary, not the monolithic native unit registry.
fn original_open(path:&Path,limit:usize,after:&mut dyn FnMut()->io::Result<dm_preprocess::OriginalRawOpenDecision>,before:&mut dyn FnMut(usize)->io::Result<()>)->io::Result<dmbc::input_snapshot::OriginalOpenedRead>{
    FileSystemInputs.read_original_open_admitted(path,limit,&dmbc::query_db::QueryDb::default(),after,before)
}
#[test]fn original_open_suppresses_before_zero_budget_payload_or_decode(){
    let root=test_scratch::dir("original-public-suppress");let path=root.join("actual.dm");std::fs::write(&path,b"invalid source \xff, larger than zero allowance").unwrap();let mut opens=0;
    let result=original_open(&path,0,&mut||{opens+=1;Ok(dm_preprocess::OriginalRawOpenDecision::Suppress)},&mut |_|panic!("no payload admission after suppression")).unwrap();assert!(matches!(result,dmbc::input_snapshot::OriginalOpenedRead::Suppressed));assert_eq!(opens,1);
}
#[test]fn original_open_failure_precedes_duplicate_decision_for_missing_and_not_directory(){
    let root=test_scratch::dir("original-public-missing");let file=root.join("not-directory");std::fs::write(&file,b"").unwrap();for path in [root.join("missing.dm"),file.join("child.dm")]{let result=original_open(&path,0,&mut||panic!("failed open cannot suppress"),&mut |_|panic!("failed open cannot admit payload")).unwrap();assert!(matches!(result,dmbc::input_snapshot::OriginalOpenedRead::SourceOpenFailed(_)));}
}
#[test]fn original_open_callback_preserves_first_resource_error_without_payload(){
    let root=test_scratch::dir("original-public-error");let path=root.join("actual.dm");std::fs::write(&path,b"source").unwrap();let result=original_open(&path,0,&mut||Err(io::Error::from_raw_os_error(1450)),&mut |_|panic!("no read after callback IO"));assert_eq!(result.err().unwrap().raw_os_error(),Some(1450));
}
#[test]fn original_open_reads_same_handle_and_admits_exact_existing_size(){
    let root=test_scratch::dir("original-public-read");let path=root.join("actual.dm");std::fs::write(&path,b"source").unwrap();let mut opens=0;let mut admits=0;let result=original_open(&path,6,&mut||{opens+=1;Ok(dm_preprocess::OriginalRawOpenDecision::Read)},&mut |n|{assert_eq!(n,6);admits+=1;Ok(())}).unwrap();let dmbc::input_snapshot::OriginalOpenedRead::Read(read)=result else{panic!("actual payload")};assert_eq!(read.bytes(),b"source");assert_eq!((opens,admits),(1,1));
}
#[cfg(windows)]#[test]fn original_open_real_sharing_denial_precedes_suppression(){
    use std::os::windows::fs::OpenOptionsExt;let root=test_scratch::dir("original-public-denied");let path=root.join("actual.dm");std::fs::write(&path,b"source").unwrap();let held=std::fs::OpenOptions::new().read(true).share_mode(0).open(&path).unwrap();let result=original_open(&path,0,&mut||panic!("denied open cannot suppress"),&mut |_|panic!("denied open cannot admit")).unwrap();let dmbc::input_snapshot::OriginalOpenedRead::SourceOpenFailed(error)=result else{panic!("actual source failure")};assert!(matches!(error.raw_os_error(),Some(32|33)),"real Windows sharing/lock denial is retained: {error:?}");drop(held);
}
#[test]fn original_open_path_replacement_never_reopens_different_payload(){
    let root=test_scratch::dir("original-public-replace");let path=root.join("actual.dm");let moved=root.join("opened.dm");std::fs::write(&path,b"source").unwrap();let result=original_open(&path,128,&mut||{std::fs::rename(&path,&moved)?;std::fs::write(&path,b"replacement")?;Ok(dm_preprocess::OriginalRawOpenDecision::Read)},&mut |n|{assert_eq!(n,6,"already-open descriptor size");Ok(())});assert_eq!(result.err().unwrap().kind(),io::ErrorKind::Interrupted);
}
#[test]fn original_open_unissued_provider_never_falls_back_to_ordinary_reads(){
    struct Unissued;impl SnapshotProvider for Unissued{fn stamp(&self,_:&Path)->io::Result<Stamp>{panic!("no ordinary fallback")}fn read(&self,_:&Path)->io::Result<(Stamp,Vec<u8>)>{panic!("no ordinary fallback")}fn list(&self,_:&Path)->io::Result<FolderListing>{panic!("no directory fallback")}}
    let result=Unissued.read_original_open_admitted(Path::new("unissued.dm"),100,&dmbc::query_db::QueryDb::default(),&mut||panic!("unissued source cannot open"),&mut |_|panic!("unissued source cannot admit"));assert_eq!(result.err().unwrap().kind(),io::ErrorKind::NotConnected);
}

mod recorded_open_controls {
//! Real same-recorder open, payload and frozen-replay controls; no parser or model.
use dmbc::input_snapshot::{RecordingInputs,SnapshotProvider,FileSystemInputs,OriginalOpenedRead,Stamp,FolderListing};
use dm_preprocess::{OriginalRawOpenDecision as Decision,OriginalRawReadOutcome as Outcome};
use std::{io,path::Path};
use super::test_scratch;
use dm_preprocess::SourceProvider;
use dm_preprocess::source_arena_credit::{SourceArenaCredit,SourceArenaCreditOwner,SourceArenaWork};
use std::{any::Any,sync::{Arc,atomic::{AtomicUsize,Ordering}},cell::Cell};
struct Credit{bytes:AtomicUsize,live:Arc<AtomicUsize>}
impl Drop for Credit{fn drop(&mut self){self.live.fetch_sub(self.bytes.load(Ordering::Acquire),Ordering::AcqRel);}}
impl SourceArenaCreditOwner for Credit{fn as_any(&self)->&dyn Any{self}fn reserved_bytes(&self)->usize{self.bytes.load(Ordering::Acquire)}fn visit_storage(&self,_:&mut dyn FnMut(usize,usize)){}}
struct Work{live:Arc<AtomicUsize>,limit:usize}
impl Work{fn new(limit:usize)->Self{Self{live:Arc::new(AtomicUsize::new(0)),limit}}fn charge(&self,n:usize)->io::Result<()>{self.live.fetch_update(Ordering::AcqRel,Ordering::Acquire,|old|old.checked_add(n).filter(|total|*total<=self.limit)).map(|_|()).map_err(|_|io::ErrorKind::OutOfMemory.into())}fn own<'a>(&self,c:&'a SourceArenaCredit)->io::Result<&'a Credit>{let owner=c.owner().as_any().downcast_ref::<Credit>().ok_or(io::ErrorKind::InvalidInput)?;if !Arc::ptr_eq(&owner.live,&self.live){return Err(io::ErrorKind::InvalidInput.into())}Ok(owner)}}
impl SourceArenaWork for Work{
 fn checkpoint(&self)->io::Result<()>{Ok(())}
 fn reserve(&self,n:usize)->io::Result<SourceArenaCredit>{self.charge(n)?;Ok(SourceArenaCredit::from_resource_owner(Arc::new(Credit{bytes:AtomicUsize::new(n),live:self.live.clone()})))}
 fn grow(&self,c:&mut SourceArenaCredit,n:usize)->io::Result<()>{let owner=self.own(c)?;self.charge(n)?;owner.bytes.fetch_add(n,Ordering::AcqRel);Ok(())}
 fn shrink(&self,c:&mut SourceArenaCredit,n:usize)->io::Result<()>{let owner=self.own(c)?;owner.bytes.fetch_update(Ordering::AcqRel,Ordering::Acquire,|old|old.checked_sub(n)).map_err(|_|io::ErrorKind::InvalidInput)?;self.live.fetch_sub(n,Ordering::AcqRel);Ok(())}
}

fn inputs<P:SnapshotProvider>(p:P)->RecordingInputs<P>{RecordingInputs::new(p,0).with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290)}
fn raw<P:SnapshotProvider>(input:&RecordingInputs<P>,path:&Path,work:&Work,decision:Decision,counts:&[Cell<usize>;4])->io::Result<Outcome>{input.original_raw_source_open_admitted(path,1<<20,work,&mut||{counts[0].set(counts[0].get()+1);Ok(decision)},&mut|_|{counts[1].set(counts[1].get()+1);Ok(())},&mut|_|{counts[2].set(counts[2].get()+1);Ok(())},&mut|_|{counts[3].set(counts[3].get()+1);Ok(())})}
#[test]fn actual_suppression_records_only_real_open_no_payload_decode_or_source_and_alias_retains_credit(){
 let root=test_scratch::dir("original-open-recorded-suppression");std::fs::create_dir_all(&root).unwrap();let path=root.join("bad.dm");std::fs::write(&path,b"\xff\0").unwrap();let work=Work::new(4<<20);let input=inputs(FileSystemInputs);let counts=std::array::from_fn(|_|Cell::new(0));assert!(matches!(raw(&input,&path,&work,Decision::Suppress,&counts).unwrap(),Outcome::Suppressed));assert_eq!(counts.map(Cell::into_inner),[1,0,0,0]);let snapshot=input.snapshot().unwrap();let json=serde_json::to_value(&snapshot).unwrap();assert!(json["files"].as_object().unwrap().is_empty());assert!(json.get("original_payloads").is_none());assert_eq!(json["opened_reads"][path.to_string_lossy().as_ref()],"Readable");assert_eq!(snapshot.restat(&FileSystemInputs).unwrap().rehashed,0);let alias=snapshot.clone();drop((snapshot,input));assert!(work.live.load(Ordering::Acquire)>0);drop(alias);assert_eq!(work.live.load(Ordering::Acquire),0);
}
#[test]fn deleted_before_suppression_records_actual_source_failure_and_warm_creation_invalidates(){
 let root=test_scratch::dir("original-open-recorded-missing");std::fs::create_dir_all(&root).unwrap();let path=root.join("missing.dm");let work=Work::new(4<<20);let input=inputs(FileSystemInputs);let counts=std::array::from_fn(|_|Cell::new(0));let Outcome::SourceOpenFailed(error)=raw(&input,&path,&work,Decision::Suppress,&counts).unwrap()else{panic!("actual open must fail before duplicate callback")};assert_eq!(error.kind(),io::ErrorKind::NotFound);assert_eq!(counts.map(Cell::into_inner),[0,0,0,0]);let snapshot=input.snapshot().unwrap();assert!(snapshot.restat(&FileSystemInputs).unwrap().unchanged());std::fs::write(&path,b"/datum/new\n").unwrap();assert!(!snapshot.restat(&FileSystemInputs).unwrap().unchanged());assert!(snapshot.files().next().is_none());drop((snapshot,input));assert_eq!(work.live.load(Ordering::Acquire),0);
}
#[test]fn exact_dotdot_lookup_payload_has_its_own_digest_receipt_and_no_canonical_file_alias(){
 let root=test_scratch::dir("original-open-exact-payload");std::fs::create_dir_all(root.join("child")).unwrap();std::fs::write(root.join("actual.dm"),b"/datum/actual\n").unwrap();let path=root.join("child").join("..").join("actual.dm");let work=Work::new(4<<20);let input=inputs(FileSystemInputs);let counts=std::array::from_fn(|_|Cell::new(0));let Outcome::Acquired(lease)=raw(&input,&path,&work,Decision::Read,&counts).unwrap()else{panic!("real opened payload must issue actual acquisition")};assert_eq!(input.original_source_bytes(&lease).unwrap().unwrap(),b"/datum/actual\n");assert_eq!(counts.map(Cell::into_inner),[1,1,1,1]);let snapshot=input.snapshot().unwrap();
 // Exercise the real typed codec: a u128 digest must not go through Value's u64 projection.
 let encoded=serde_json::to_vec(&snapshot).unwrap();
 let decoded:dmbc::input_snapshot::InputSnapshot=serde_json::from_slice(&encoded).unwrap();
 assert_eq!(decoded,snapshot);
 #[derive(serde::Deserialize)]
 struct PayloadKeys{original_payloads:std::collections::BTreeMap<std::path::PathBuf,serde::de::IgnoredAny>}
 let keys:PayloadKeys=serde_json::from_slice(&encoded).unwrap();
 assert!(keys.original_payloads.contains_key(&path));assert!(snapshot.files().next().is_none());assert!(snapshot.restat(&FileSystemInputs).unwrap().unchanged());std::fs::write(root.join("actual.dm"),b"/datum/changed\n").unwrap();assert!(!snapshot.restat(&FileSystemInputs).unwrap().unchanged());drop((snapshot,input,lease));assert_eq!(work.live.load(Ordering::Acquire),0);
}
#[test]fn frozen_suppression_replays_real_open_after_file_deleted_without_payload_or_live_probe(){
 let root=test_scratch::dir("original-open-journal-suppressed");std::fs::create_dir_all(&root).unwrap();let path=root.join("duplicate.dm");std::fs::write(&path,b"invalid source").unwrap();let directory=root.join("journal");let work=Work::new(4<<20);let journal=dmbc::frozen_inputs::Inputs::record(&directory).unwrap();let input=inputs(&journal);let counts=std::array::from_fn(|_|Cell::new(0));assert!(matches!(raw(&input,&path,&work,Decision::Suppress,&counts).unwrap(),Outcome::Suppressed));drop(input);journal.finish().unwrap();drop(journal);assert_eq!(std::fs::read_dir(directory.join("payloads")).unwrap().count(),0);std::fs::remove_file(&path).unwrap();let replay=dmbc::frozen_inputs::Inputs::replay(&directory).unwrap();let input=inputs(&replay);let counts=std::array::from_fn(|_|Cell::new(0));assert!(matches!(raw(&input,&path,&work,Decision::Suppress,&counts).unwrap(),Outcome::Suppressed));assert_eq!(counts.map(Cell::into_inner),[1,0,0,0]);let counts=std::array::from_fn(|_|Cell::new(0));assert!(raw(&input,&path,&work,Decision::Read,&counts).is_err(),"a recorded suppression never grants uncaptured payload");drop(input);drop(replay);assert_eq!(work.live.load(Ordering::Acquire),0);
}
#[test]fn failed_open_journal_replays_exact_cause_even_after_live_path_appears(){
 let root=test_scratch::dir("original-open-journal-failed");std::fs::create_dir_all(&root).unwrap();let path=root.join("missing.dm");let directory=root.join("journal");let work=Work::new(4<<20);let journal=dmbc::frozen_inputs::Inputs::record(&directory).unwrap();let input=inputs(&journal);let counts=std::array::from_fn(|_|Cell::new(0));let Outcome::SourceOpenFailed(old)=raw(&input,&path,&work,Decision::Read,&counts).unwrap()else{panic!("real missing file")};drop(input);journal.finish().unwrap();drop(journal);std::fs::write(&path,b"now exists").unwrap();let replay=dmbc::frozen_inputs::Inputs::replay(&directory).unwrap();let input=inputs(&replay);let counts=std::array::from_fn(|_|Cell::new(0));let Outcome::SourceOpenFailed(actual)=raw(&input,&path,&work,Decision::Suppress,&counts).unwrap()else{panic!("recorded source failure remains failure")};assert_eq!((actual.kind(),actual.raw_os_error(),actual.to_string()),(old.kind(),old.raw_os_error(),old.to_string()));assert_eq!(counts.map(Cell::into_inner),[0,0,0,0]);drop(input);drop(replay);assert_eq!(work.live.load(Ordering::Acquire),0);
}
#[test]fn callback_operational_error_1450_cannot_become_source_failure_or_missing_fact(){
 let root=test_scratch::dir("original-open-recorder-first-io");std::fs::create_dir_all(&root).unwrap();let path=root.join("actual.dm");std::fs::write(&path,b"contents").unwrap();let work=Work::new(4<<20);let input=inputs(FileSystemInputs);let error=input.original_raw_source_open_admitted(&path,1<<20,&work,&mut||Err(io::Error::from_raw_os_error(1450)),&mut|_|panic!("no payload after callback failure"),&mut|_|panic!("no decode"),&mut|_|panic!("no source")).err().unwrap();assert_eq!(error.raw_os_error(),Some(1450));let snapshot=input.snapshot().unwrap();assert!(snapshot.files().next().is_none());assert!(serde_json::to_value(&snapshot).unwrap()["negative_files"].as_array().unwrap().is_empty());assert!(serde_json::to_value(&snapshot).unwrap()["opened_reads"][path.to_string_lossy().as_ref()]=="Readable");
}
#[test]fn denied_open_pregrant_performs_no_provider_operation(){
 struct Never;impl SnapshotProvider for Never{fn stamp(&self,_:&Path)->io::Result<Stamp>{panic!("no stamp")}fn read(&self,_:&Path)->io::Result<(Stamp,Vec<u8>)>{panic!("no read")}fn list(&self,_:&Path)->io::Result<FolderListing>{panic!("no folder")}fn read_original_open_admitted(&self,_:&Path,_:usize,_:&dyn SourceArenaWork,_:&mut dyn FnMut()->io::Result<Decision>,_:&mut dyn FnMut(usize)->io::Result<()>)->io::Result<OriginalOpenedRead>{panic!("resource refusal must precede even actual reader open")}}
 let work=Work::new(0);let input=inputs(Never);let counts=std::array::from_fn(|_|Cell::new(0));assert!(raw(&input,Path::new("E:/dq-cache/test-scratch/denied.dm"),&work,Decision::Read,&counts).is_err());assert_eq!(counts.map(Cell::into_inner),[0,0,0,0]);
}

}

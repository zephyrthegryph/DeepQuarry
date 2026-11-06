//! Real same-recorder open, payload and frozen-replay controls; no parser or model.
use super::*;
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
 let root=crate::test_scratch::dir("original-open-recorded-suppression");std::fs::create_dir_all(&root).unwrap();let path=root.join("bad.dm");std::fs::write(&path,b"\xff\0").unwrap();let work=Work::new(4<<20);let input=inputs(FileSystemInputs);let counts=std::array::from_fn(|_|Cell::new(0));assert!(matches!(raw(&input,&path,&work,Decision::Suppress,&counts).unwrap(),Outcome::Suppressed));assert_eq!(counts.map(Cell::into_inner),[1,0,0,0]);let snapshot=input.snapshot().unwrap();let json=serde_json::to_value(&snapshot).unwrap();assert!(json["files"].as_object().unwrap().is_empty());assert!(json.get("original_payloads").is_none());assert_eq!(json["opened_reads"][path.to_string_lossy().as_ref()],"Readable");assert_eq!(snapshot.restat(&FileSystemInputs).unwrap().rehashed,0);let alias=snapshot.clone();drop((snapshot,input));assert!(work.live.load(Ordering::Acquire)>0);drop(alias);assert_eq!(work.live.load(Ordering::Acquire),0);
}
#[test]fn deleted_before_suppression_records_actual_source_failure_and_warm_creation_invalidates(){
 let root=crate::test_scratch::dir("original-open-recorded-missing");std::fs::create_dir_all(&root).unwrap();let path=root.join("missing.dm");let work=Work::new(4<<20);let input=inputs(FileSystemInputs);let counts=std::array::from_fn(|_|Cell::new(0));let Outcome::SourceOpenFailed(error)=raw(&input,&path,&work,Decision::Suppress,&counts).unwrap()else{panic!("actual open must fail before duplicate callback")};assert_eq!(error.kind(),io::ErrorKind::NotFound);assert_eq!(counts.map(Cell::into_inner),[0,0,0,0]);let snapshot=input.snapshot().unwrap();assert!(snapshot.restat(&FileSystemInputs).unwrap().unchanged());std::fs::write(&path,b"/datum/new\n").unwrap();assert!(!snapshot.restat(&FileSystemInputs).unwrap().unchanged());assert!(snapshot.files().next().is_none());drop((snapshot,input));assert_eq!(work.live.load(Ordering::Acquire),0);
}
#[test]fn exact_dotdot_lookup_payload_has_its_own_digest_receipt_and_no_canonical_file_alias(){
 let root=crate::test_scratch::dir("original-open-exact-payload");std::fs::create_dir_all(root.join("child")).unwrap();std::fs::write(root.join("actual.dm"),b"/datum/actual\n").unwrap();let path=root.join("child").join("..").join("actual.dm");let work=Work::new(4<<20);let input=inputs(FileSystemInputs);let counts=std::array::from_fn(|_|Cell::new(0));let Outcome::Acquired(lease)=raw(&input,&path,&work,Decision::Read,&counts).unwrap()else{panic!("real opened payload must issue actual acquisition")};assert_eq!(input.original_source_bytes(&lease).unwrap().unwrap(),b"/datum/actual\n");assert_eq!(counts.map(Cell::into_inner),[1,1,1,1]);let snapshot=input.snapshot().unwrap();
 // Exercise the real typed codec: a u128 digest must not go through Value's u64 projection.
 let encoded=serde_json::to_vec(&snapshot).unwrap();
 let decoded:crate::input_snapshot::InputSnapshot=serde_json::from_slice(&encoded).unwrap();
 assert_eq!(decoded,snapshot);
 #[derive(serde::Deserialize)]
 struct PayloadKeys{original_payloads:std::collections::BTreeMap<std::path::PathBuf,serde::de::IgnoredAny>}
 let keys:PayloadKeys=serde_json::from_slice(&encoded).unwrap();
 assert!(keys.original_payloads.contains_key(&path));assert!(snapshot.files().next().is_none());assert!(snapshot.restat(&FileSystemInputs).unwrap().unchanged());std::fs::write(root.join("actual.dm"),b"/datum/changed\n").unwrap();assert!(!snapshot.restat(&FileSystemInputs).unwrap().unchanged());drop((snapshot,input,lease));assert_eq!(work.live.load(Ordering::Acquire),0);
}
#[test]
fn exact_original_loan_requires_the_current_positive_facts_and_unpoisoned_recorder() {
    let root=crate::test_scratch::dir("original-exact-loan-current-facts");
    let path=root.join("actual.dm");
    let bytes=b"\xef\xbb\xbf/datum/actual\n";
    std::fs::write(&path,bytes).unwrap();
    let work=Work::new(4<<20);
    let input=inputs(FileSystemInputs);
    let counts=std::array::from_fn(|_|Cell::new(0));
    let Outcome::Acquired(lease)=raw(&input,&path,&work,Decision::Read,&counts).unwrap()else{panic!("actual source")};
    assert_eq!(input.original_source_bytes(&lease).unwrap().unwrap(),bytes);
    assert_eq!(counts.map(Cell::into_inner),[1,1,1,1]);
    let first_serial=input.snapshot.lock().unwrap().cached_exact_loan().expect("warm exact proof");
    let reissued=lease.reissued(());
    assert!(reissued.same_original_acquisition(&lease));
    assert!(input.original_source_bytes(&reissued).is_err(),"original text owner cannot reissue the private serial");
    let counts=std::array::from_fn(|_|Cell::new(0));
    let Outcome::Acquired(later)=raw(&input,&path,&work,Decision::Read,&counts).unwrap()else{panic!("reopened actual source")};
    assert!(input.snapshot.lock().unwrap().cached_exact_loan().is_none(),"mutable capture projection retires the prior proof");
    assert_eq!(input.original_source_bytes(&later).unwrap().unwrap(),bytes);
    assert_ne!(input.snapshot.lock().unwrap().cached_exact_loan(),Some(first_serial),"equal facts do not reuse a serial");
    assert_eq!(input.original_source_bytes(&lease).unwrap().unwrap(),bytes);
    assert_eq!(input.snapshot.lock().unwrap().cached_exact_loan(),Some(first_serial),"the one-entry memo can refill from live facts");

    let other=inputs(FileSystemInputs);
    let counts=std::array::from_fn(|_|Cell::new(0));
    let Outcome::Acquired(other_lease)=raw(&other,&path,&work,Decision::Read,&counts).unwrap()else{panic!("second actual source")};
    assert_eq!(other.original_source_bytes(&other_lease).unwrap().unwrap(),bytes);
    assert!(other.original_source_bytes(&lease).is_err(),"equal current facts from another recorder grant nothing");

    let observed=std::mem::take(&mut input.snapshot.lock().unwrap().opened_reads);
    assert!(input.snapshot.lock().unwrap().cached_exact_loan().is_none());
    assert!(input.original_source_bytes(&lease).is_err(),"current opened-reader proof is required");
    input.snapshot.lock().unwrap().opened_reads=observed;
    assert_eq!(input.original_source_bytes(&lease).unwrap().unwrap(),bytes);
    assert_eq!(input.snapshot.lock().unwrap().cached_exact_loan(),Some(first_serial));
    let payload=std::mem::take(&mut input.snapshot.lock().unwrap().original_payloads);
    assert!(input.snapshot.lock().unwrap().cached_exact_loan().is_none());
    assert!(input.original_source_bytes(&lease).is_err(),"current exact payload is required");
    input.snapshot.lock().unwrap().original_payloads=payload;
    assert_eq!(input.original_source_bytes(&lease).unwrap().unwrap(),bytes);

    let poisoned=std::panic::catch_unwind(std::panic::AssertUnwindSafe(||{
        let _locked=input.snapshot.lock().unwrap();
        panic!("deliberately poison the recorder for a loan control");
    }));
    assert!(poisoned.is_err());
    assert!(input.original_source_bytes(&lease).is_err());
}

#[test]fn frozen_suppression_replays_real_open_after_file_deleted_without_payload_or_live_probe(){
 let root=crate::test_scratch::dir("original-open-journal-suppressed");std::fs::create_dir_all(&root).unwrap();let path=root.join("duplicate.dm");std::fs::write(&path,b"invalid source").unwrap();let directory=root.join("journal");let work=Work::new(4<<20);let journal=crate::frozen_inputs::Inputs::record(&directory).unwrap();let input=inputs(&journal);let counts=std::array::from_fn(|_|Cell::new(0));assert!(matches!(raw(&input,&path,&work,Decision::Suppress,&counts).unwrap(),Outcome::Suppressed));drop(input);journal.finish().unwrap();drop(journal);assert_eq!(std::fs::read_dir(directory.join("payloads")).unwrap().count(),0);std::fs::remove_file(&path).unwrap();let replay=crate::frozen_inputs::Inputs::replay(&directory).unwrap();let input=inputs(&replay);let counts=std::array::from_fn(|_|Cell::new(0));assert!(matches!(raw(&input,&path,&work,Decision::Suppress,&counts).unwrap(),Outcome::Suppressed));assert_eq!(counts.map(Cell::into_inner),[1,0,0,0]);let counts=std::array::from_fn(|_|Cell::new(0));assert!(raw(&input,&path,&work,Decision::Read,&counts).is_err(),"a recorded suppression never grants uncaptured payload");drop(input);drop(replay);assert_eq!(work.live.load(Ordering::Acquire),0);
}
#[test]fn failed_open_journal_replays_exact_cause_even_after_live_path_appears(){
 let root=crate::test_scratch::dir("original-open-journal-failed");std::fs::create_dir_all(&root).unwrap();let path=root.join("missing.dm");let directory=root.join("journal");let work=Work::new(4<<20);let journal=crate::frozen_inputs::Inputs::record(&directory).unwrap();let input=inputs(&journal);let counts=std::array::from_fn(|_|Cell::new(0));let Outcome::SourceOpenFailed(old)=raw(&input,&path,&work,Decision::Read,&counts).unwrap()else{panic!("real missing file")};drop(input);journal.finish().unwrap();drop(journal);std::fs::write(&path,b"now exists").unwrap();let replay=crate::frozen_inputs::Inputs::replay(&directory).unwrap();let input=inputs(&replay);let counts=std::array::from_fn(|_|Cell::new(0));let Outcome::SourceOpenFailed(actual)=raw(&input,&path,&work,Decision::Suppress,&counts).unwrap()else{panic!("recorded source failure remains failure")};assert_eq!((actual.kind(),actual.raw_os_error(),actual.to_string()),(old.kind(),old.raw_os_error(),old.to_string()));assert_eq!(counts.map(Cell::into_inner),[0,0,0,0]);drop(input);drop(replay);assert_eq!(work.live.load(Ordering::Acquire),0);
}
#[test]fn callback_operational_error_1450_cannot_become_source_failure_or_missing_fact(){
 let root=crate::test_scratch::dir("original-open-recorder-first-io");std::fs::create_dir_all(&root).unwrap();let path=root.join("actual.dm");std::fs::write(&path,b"contents").unwrap();let work=Work::new(4<<20);let input=inputs(FileSystemInputs);let error=input.original_raw_source_open_admitted(&path,1<<20,&work,&mut||Err(io::Error::from_raw_os_error(1450)),&mut|_|panic!("no payload after callback failure"),&mut|_|panic!("no decode"),&mut|_|panic!("no source")).err().unwrap();assert_eq!(error.raw_os_error(),Some(1450));let snapshot=input.snapshot().unwrap();assert!(snapshot.files().next().is_none());assert!(snapshot.negative_files.is_empty());assert!(snapshot.opened_reads.get(&path).unwrap().is_readable());
}
#[test]fn denied_open_pregrant_performs_no_provider_operation(){
 struct Never;impl SnapshotProvider for Never{fn stamp(&self,_:&Path)->io::Result<Stamp>{panic!("no stamp")}fn read(&self,_:&Path)->io::Result<(Stamp,Vec<u8>)>{panic!("no read")}fn list(&self,_:&Path)->io::Result<FolderListing>{panic!("no folder")}fn read_original_open_admitted(&self,_:&Path,_:usize,_:&dyn SourceArenaWork,_:&mut dyn FnMut()->io::Result<Decision>,_:&mut dyn FnMut(usize)->io::Result<()>)->io::Result<OriginalOpenedRead>{panic!("resource refusal must precede even actual reader open")}}
 let work=Work::new(0);let input=inputs(Never);let counts=std::array::from_fn(|_|Cell::new(0));assert!(raw(&input,Path::new("E:/dq-cache/test-scratch/denied.dm"),&work,Decision::Read,&counts).is_err());assert_eq!(counts.map(Cell::into_inner),[0,0,0,0]);
}

#[test]
fn real_open_and_payload_fact_families_settle_pregrant_and_preserve_snapshot_aliases(){
 let root=crate::test_scratch::dir("original-open-avl-grant-settlement");
 std::fs::create_dir_all(&root).unwrap();
 let work=Work::new(4<<20);
 let input=inputs(FileSystemInputs);
 fn bytes<V: super::super::path_presence::ImmutableFactValue>(
  rows:&super::super::path_presence::ImmutablePathFacts<V>,
 )->std::collections::BTreeMap<usize,usize>{
  let mut sizes=std::collections::BTreeMap::new();
  rows.visit_storage(|address,_,capacity|{sizes.insert(address,capacity);});
  sizes
 }
 let mut prefix=None;
 let mut unused_open=0usize;
 let mut unused_payload=0usize;
 for at in 0..64 {
  let permuted=at*19%64;
  let path=root.join(format!("actual-{permuted:03}.dm"));
  std::fs::write(&path,b"/datum/actual\n").unwrap();
  let prior=input.snapshot().unwrap();
  let open_grant=prior.opened_reads.probe_pregrant(&path).unwrap();
  let payload_grant=prior.original_payloads.probe_pregrant(&path).unwrap();
  let prior_open=bytes(&prior.opened_reads);
  let prior_payload=bytes(&prior.original_payloads);
  let before=work.live.load(Ordering::Acquire);
  let counts=std::array::from_fn(|_|Cell::new(0));
  let Outcome::Acquired(lease)=raw(&input,&path,&work,Decision::Read,&counts).unwrap() else { panic!("actual payload") };
  assert_eq!(counts.map(Cell::into_inner),[1,1,1,1]);
  assert_eq!(input.original_source_bytes(&lease).unwrap().unwrap(),b"/datum/actual\n");
  let next=input.snapshot().unwrap();
  let next_open=bytes(&next.opened_reads);
  let next_payload=bytes(&next.original_payloads);
  // The prior alias is deliberately alive, making address difference an
  // independent exact census of the actual newly retained node/key buffers.
  // Work's credit-control allocation has no entries in this visitor.
  let new_bytes=|next:&std::collections::BTreeMap<usize,usize>,old:&std::collections::BTreeMap<usize,usize>|
   next.iter().filter(|(address,_)|!old.contains_key(*address)).map(|(_,bytes)|*bytes).sum::<usize>();
  let added_open=new_bytes(&next_open,&prior_open);
  let added_payload=new_bytes(&next_payload,&prior_payload);
  assert_eq!(work.live.load(Ordering::Acquire)-before,added_open+added_payload);
  assert!(added_open<open_grant);
  assert!(added_payload<payload_grant);
  unused_open+=open_grant-added_open;
  unused_payload+=payload_grant-added_payload;
  if at==15 {prefix=Some(next);}
 }
 let last=input.snapshot().unwrap();
 let prefix=prefix.unwrap();
 assert_eq!(prefix.opened_reads.len(),16);
 assert_eq!(prefix.original_payloads.len(),16);
 assert_eq!(last.opened_reads.len(),64);
 assert_eq!(last.original_payloads.len(),64);
 assert!(unused_open>64*1024 && unused_payload>64*1024);
 drop((input,last));
 assert!(work.live.load(Ordering::Acquire)>0);
 assert!(prefix.restat(&FileSystemInputs).unwrap().unchanged());
 drop(prefix);
 assert_eq!(work.live.load(Ordering::Acquire),0);
}

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

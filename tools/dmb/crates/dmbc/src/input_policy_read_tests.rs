use super::*;

#[cfg(windows)]
#[test]
fn fixed_library_open_fact_restats_real_denial_and_never_records_admission_errors() {
    use dm_preprocess::source_arena_credit::{SourceArenaCredit, SourceArenaWork};
    use std::{os::windows::fs::OpenOptionsExt, sync::atomic::{AtomicUsize, Ordering}};
    let root = crate::test_scratch::dir("fixed-library-open-fact");
    let path = root.join(crate::runner_host::workspace_capture::LIBRARY_SITES_BASELINE);
    std::fs::create_dir_all(path.parent().unwrap()).unwrap();
    std::fs::write(&path, b"actual baseline").unwrap();
    let work = crate::query_db::QueryDb::default();
    let held = std::fs::OpenOptions::new().read(true).share_mode(0).open(&path).unwrap();
    let inputs = RecordingInputs::new(FileSystemInputs, 1);
    assert!(matches!(inputs.read_fixed_library_baseline(&root, &path, 64, &work).unwrap(),
        FixedLibraryBaseline::OpenUnreadable));
    let facts = inputs.snapshot().unwrap();
    assert!(!facts.contains_file(&path));
    assert!(!facts.negative_files.contains(&path));
    assert!(!facts.opened_reads.get(&path).unwrap().is_readable());
    assert!(facts.restat(&FileSystemInputs).unwrap().changed.is_empty());
    drop(held);
    assert!(facts.restat(&FileSystemInputs).unwrap().changed.contains(&path));

    struct Fault(AtomicUsize, i32);
    impl SourceArenaWork for Fault {
        fn checkpoint(&self) -> io::Result<()> {
            if self.0.fetch_add(1, Ordering::Relaxed) == 2 {
                return Err(io::Error::from_raw_os_error(self.1));
            }
            Ok(())
        }
        fn reserve(&self, _: usize) -> io::Result<SourceArenaCredit> {
            panic!("operation fault cannot reserve an open-status fact")
        }
        fn grow(&self, _: &mut SourceArenaCredit, _: usize) -> io::Result<()> { unreachable!() }
        fn shrink(&self, _: &mut SourceArenaCredit, _: usize) -> io::Result<()> { unreachable!() }
    }
    for raw in [2, 32, 1450] {
        let inputs = RecordingInputs::new(FileSystemInputs, 1);
        let fault = Fault(AtomicUsize::new(0), raw);
        let actual = inputs.read_fixed_library_baseline(&root, &path, 64, &fault)
            .err().expect("actual pre-payload operational refusal");
        assert_eq!(actual.raw_os_error(), Some(raw));
        let facts = inputs.snapshot().unwrap();
        assert!(!facts.contains_file(&path));
        assert!(!facts.negative_files.contains(&path));
        assert!(facts.opened_reads.get(&path).is_none());
    }
}

#[test]
fn oversized_actual_file_is_refused_without_a_recorded_payload() {
    let root = crate::test_scratch::dir("bounded-policy-large");
    let path = root.join("large.dm");
    std::fs::write(&path, b"1234").unwrap();
    let inputs = RecordingInputs::new(FileSystemInputs, 1);
    assert!(inputs.read_policy_candidate(&path, 3).is_err());
    assert!(!inputs.snapshot().unwrap().contains_file(&path));
}
#[test]
fn exact_actual_bound_records_same_bytes_once() {
    let root = crate::test_scratch::dir("bounded-policy-exact");
    let path = root.join("exact.dm");
    std::fs::write(&path, b"1234").unwrap();
    let inputs = RecordingInputs::new(FileSystemInputs, 1);
    let bytes = inputs.read_policy_candidate(&path, 4).unwrap().unwrap();
    assert_eq!(bytes.as_slice(), b"1234");
    assert!(bytes.capacity() <= 4);
    let snapshot = inputs.snapshot().unwrap();
    let fact = snapshot.files().find(|f| f.path == path).unwrap();
    assert_eq!(fact.content, xxhash_rust::xxh3::xxh3_128(b"1234"));
}
#[test]
fn missing_bounded_original_records_exact_negative() {
    let root = crate::test_scratch::dir("bounded-policy-missing");
    let path = root.join("missing.dm");
    let inputs = RecordingInputs::new(FileSystemInputs, 1);
    assert!(inputs.read_policy_candidate(&path, 4).unwrap().is_none());
    assert!(inputs.snapshot().unwrap().negative_files.contains(&path));
}
#[test]
fn unknown_provider_cannot_fall_back_to_unbounded_read() {
    struct Unknown;
    impl SnapshotProvider for Unknown {
        fn stamp(&self, _: &Path) -> io::Result<Stamp> {
            unreachable!()
        }
        fn read(&self, _: &Path) -> io::Result<(Stamp, Vec<u8>)> {
            panic!("bounded admission must not invoke unbounded source read")
        }
        fn list(&self, _: &Path) -> io::Result<FolderListing> {
            Ok(FolderListing::Present(vec![]))
        }
    }
    let path = std::env::current_dir().unwrap().join("unknown.dm");
    let inputs = RecordingInputs::new(Unknown, 1);
    assert!(inputs
        .read_policy_candidate(&path, 4)
        .unwrap_err()
        .to_string()
        .contains("provider cannot prove bounded"));
    assert!(!inputs.snapshot().unwrap().contains_file(&path));
}
#[test]
fn bounded_journal_record_replay_preserves_original_invalid_bytes() {
    let root = crate::test_scratch::dir("bounded-policy-journal");
    let path = root.join("original.dm");
    std::fs::write(&path, b"\x80").unwrap();
    let journal = root.join("journal");
    let inputs = RecordingInputs::new(crate::frozen_inputs::Inputs::record(&journal).unwrap(), 1);
    let original = inputs.read_policy_candidate(&path, 1).unwrap().unwrap();
    assert_eq!(original.as_slice(), b"\x80");
    inputs.provider.finish().unwrap();
    let replay = RecordingInputs::new(crate::frozen_inputs::Inputs::replay(&journal).unwrap(), 1);
    let historical = replay.read_policy_candidate(&path, 1).unwrap().unwrap();
    assert_eq!(historical.as_slice(), b"\x80");
    assert!(replay.read_policy_candidate(&path, 0).is_err());
}

#[test]
fn actual_admission_runs_after_same_handle_stamp_but_before_any_payload_read() {
    let root=crate::test_scratch::dir("bounded-admission-before-read");
    let path=root.join("source.dm");std::fs::write(&path,b"1234").unwrap();
    let inputs=RecordingInputs::new(FileSystemInputs,1);
    let mut calls=0;
    let error=inputs.read_policy_vec_admitted(&path,4,&mut |size|{
        calls+=1;assert_eq!(size,4);
        // A callback after the read would succeed with the old bytes. The real
        // single-handle kernel must instead observe this truncation and refuse.
        std::fs::write(&path,b"")?;Ok(())
    }).unwrap_err();
    assert_eq!(calls,1);assert_eq!(error.kind(),io::ErrorKind::Interrupted);
    assert!(!inputs.snapshot().unwrap().contains_file(&path));
}
#[test]
fn actual_admission_refusal_keeps_exact_io_and_does_not_record_payload() {
    let root=crate::test_scratch::dir("bounded-admission-io");let path=root.join("source.dm");std::fs::write(&path,b"actual").unwrap();
    let inputs=RecordingInputs::new(FileSystemInputs,1);
    let error=inputs.read_policy_vec_admitted(&path,6,&mut |_|Err(io::Error::from_raw_os_error(1450))).unwrap_err();
    assert_eq!(error.raw_os_error(),Some(1450));assert!(!inputs.snapshot().unwrap().contains_file(&path));
    let mut calls=0;let bytes=inputs.read_policy_vec_admitted(&path,6,&mut |size|{calls+=1;assert_eq!(size,6);Ok(())}).unwrap().unwrap();
    assert_eq!(calls,1);assert_eq!(bytes,b"actual");assert!(inputs.snapshot().unwrap().contains_file(&path));
}
#[test]
fn bounded_only_provider_cannot_forge_preallocation_admission() {
    struct BoundedOnly;
    impl SnapshotProvider for BoundedOnly {
        fn stamp(&self,_:&Path)->io::Result<Stamp>{unreachable!()}
        fn read(&self,_:&Path)->io::Result<(Stamp,Vec<u8>)>{panic!("unbounded read forbidden")}
        fn list(&self,_:&Path)->io::Result<FolderListing>{Ok(FolderListing::Present(vec![]))}
        fn read_policy_bounded(&self,_:&Path,_:usize)->io::Result<Option<CapturedInputRead>>{panic!("read-then-fund fallback forbidden")}
    }
    let path=std::env::current_dir().unwrap().join("unissued.dm");let inputs=RecordingInputs::new(BoundedOnly,1);
    let error=inputs.read_policy_vec_admitted(&path,4096,&mut |_|panic!("no real allocation issued")).unwrap_err();
    assert!(error.to_string().contains("provider cannot prove bounded"));assert!(!inputs.snapshot().unwrap().contains_file(&path));
}

#[test]
fn not_found_from_resource_lender_is_never_an_absent_source_fact() {
    let root=crate::test_scratch::dir("bounded-admission-notfound");let path=root.join("actual.dm");std::fs::write(&path,b"present").unwrap();
    let inputs=RecordingInputs::new(FileSystemInputs,1);
    let error=inputs.read_policy_vec_admitted(&path,7,&mut |_|Err(io::Error::from(io::ErrorKind::NotFound))).unwrap_err();
    assert_eq!(error.kind(),io::ErrorKind::NotFound);
    let snapshot=inputs.snapshot().unwrap();assert!(!snapshot.contains_file(&path));assert!(!snapshot.negative_files.contains(&path));
}

#[test]fn original_successful_open_suppresses_before_size_admission_payload_or_decode(){
 let root=crate::test_scratch::dir("original-open-suppress");let path=root.join("duplicate.dm");std::fs::write(&path,b"payload is larger than zero-byte allowance and invalid source \xff").unwrap();let mut opens=0;let result=filesystem_original_open_read_admitted(&path,0,&mut||{opens+=1;Ok(dm_preprocess::OriginalRawOpenDecision::Suppress)},&mut |_|panic!("suppressed actual handle must not request payload admission")).unwrap();assert!(matches!(result,OriginalOpenedRead::Suppressed));assert_eq!(opens,1);
}
#[test]fn original_deleted_and_not_directory_fail_before_any_suppression_decision(){
 let root=crate::test_scratch::dir("original-open-source-fail");let file=root.join("not-directory");std::fs::write(&file,b"").unwrap();for path in [root.join("deleted.dm"),file.join("child.dm")]{let result=filesystem_original_open_read_admitted(&path,0,&mut||panic!("failed open must not become successful suppression"),&mut |_|panic!("failed open cannot admit payload")).unwrap();assert!(matches!(result,OriginalOpenedRead::SourceOpenFailed(_)));}
}
#[test]fn original_after_open_callback_first_io_cannot_become_source_failure_suppression_or_payload(){
 let root=crate::test_scratch::dir("original-open-first-io");let path=root.join("actual.dm");std::fs::write(&path,b"/datum/x\n").unwrap();let result=filesystem_original_open_read_admitted(&path,0,&mut||Err(io::Error::from_raw_os_error(1450)),&mut |_|panic!("first callback error must retire the actual handle before payload"));assert_eq!(result.err().unwrap().raw_os_error(),Some(1450));
}
#[test]fn original_continue_reads_actual_same_handle_with_existing_bounded_kernel(){
 let root=crate::test_scratch::dir("original-open-continue");let path=root.join("actual.dm");std::fs::write(&path,b"/datum/x\n").unwrap();let mut opens=0;let mut admitted=0;let result=filesystem_original_open_read_admitted(&path,32,&mut||{opens+=1;Ok(dm_preprocess::OriginalRawOpenDecision::Read)},&mut |size|{assert_eq!(size,9);admitted+=1;Ok(())}).unwrap();let OriginalOpenedRead::Read(read)=result else{panic!("genuine bounded payload expected")};let(_,bytes,_)=read.into_parts();assert_eq!(bytes,b"/datum/x\n");assert_eq!((opens,admitted),(1,1));
}

#[cfg(windows)]
#[test]fn original_read_denied_by_actual_handle_sharing_fails_before_suppression(){
 use std::os::windows::fs::OpenOptionsExt;let root=crate::test_scratch::dir("original-open-denied");let path=root.join("actual.dm");std::fs::write(&path,b"source").unwrap();let held=std::fs::OpenOptions::new().read(true).share_mode(0).open(&path).unwrap();let result=filesystem_original_open_read_admitted(&path,0,&mut||panic!("denied real open cannot enter duplicate suppression"),&mut |_|panic!("no admitted payload after denied open")).unwrap();let OriginalOpenedRead::SourceOpenFailed(actual)=result else{panic!("source open failure required")};assert!(matches!(actual.raw_os_error(),Some(32|33)),"actual sharing/lock denial code is retained: {actual:?}");drop(held);
}
#[test]fn original_callback_path_replacement_cannot_make_payload_reopen_a_different_file(){
 let root=crate::test_scratch::dir("original-open-single-handle");let path=root.join("actual.dm");let moved=root.join("opened-old.dm");std::fs::write(&path,b"/datum/x\n").unwrap();let result=filesystem_original_open_read_admitted(&path,128,&mut||{std::fs::rename(&path,&moved)?;std::fs::write(&path,b"replacement payload").unwrap();Ok(dm_preprocess::OriginalRawOpenDecision::Read)},&mut |size|{assert_eq!(size,9,"size belongs to already opened descriptor, not replaced pathname");Ok(())});assert_eq!(result.err().unwrap().kind(),io::ErrorKind::Interrupted,"same descriptor sees old bytes and detects changed path; a second open would incorrectly accept replacement");
}

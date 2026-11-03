use super::*;
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

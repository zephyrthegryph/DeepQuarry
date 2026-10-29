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

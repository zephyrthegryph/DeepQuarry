use super::*;
use dm_preprocess::SourceProvider;
#[derive(Clone)]
struct P {
    bytes: Arc<Vec<u8>>,
    reads: Arc<std::sync::atomic::AtomicUsize>,
}
impl P {
    fn new(bytes: &[u8]) -> Self {
        Self {
            bytes: Arc::new(bytes.to_vec()),
            reads: Arc::new(Default::default()),
        }
    }
}
impl SnapshotProvider for P {
    fn stamp(&self, _: &Path) -> io::Result<Stamp> {
        Ok(Stamp {
            size: self.bytes.len() as u64,
            modified_ns: 1,
            file_id: Some(1),
        })
    }
    fn read(&self, p: &Path) -> io::Result<(Stamp, Vec<u8>)> {
        self.reads.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
        Ok((self.stamp(p)?, self.bytes.as_ref().clone()))
    }
    fn list(&self, _: &Path) -> io::Result<FolderListing> {
        Ok(FolderListing::Present(vec!["x.dm".into()]))
    }
}
#[test]
fn warm_prepared_reissues_actual_original_lease_without_a_read() {
    let p = P::new(b"/datum/acquired_source_warm\n");
    let store = Arc::new(PreparedInputArtifacts::default());
    let path = Path::new("x.dm");
    let first =
        RecordingInputs::new(p.clone(), 4_000_000_000).with_prepared_sources(Some(store.clone()));
    let old = SourceProvider::acquired_source(&first, path)
        .unwrap()
        .unwrap();
    let before = p.reads.load(std::sync::atomic::Ordering::SeqCst);
    let next = RecordingInputs::new(p.clone(), 5_000_000_000).with_prepared_sources(Some(store));
    let new = SourceProvider::acquired_source(&next, path)
        .unwrap()
        .unwrap();
    assert_eq!(p.reads.load(std::sync::atomic::Ordering::SeqCst), before);
    assert!(old.same_original_acquisition(&new));
    assert!(!old.same_binding(&new));
    assert!(next.validate_source_acquisition(path, &new));
    assert!(!next.validate_source_acquisition(path, &old));
}
#[test]
fn foreign_normal_lease_rejects_even_with_equal_interned_source() {
    let a = RecordingInputs::new(P::new(b"/datum/foreign_normal_lease\n"), 1);
    let b = RecordingInputs::new(P::new(b"/datum/foreign_normal_lease\n"), 1);
    let p = Path::new("x.dm");
    let x = SourceProvider::acquired_source(&a, p).unwrap().unwrap();
    let y = SourceProvider::acquired_source(&b, p).unwrap().unwrap();
    assert!(Arc::ptr_eq(x.prepared(), y.prepared()));
    assert!(!b.validate_source_acquisition(p, &x));
    assert!(b.validate_source_acquisition(p, &y));
}

#[test]
fn racy_timestamp_rechecks_original_and_reissues_only_authenticated_lease() {
    let p = P::new(b"/datum/acquired_source_racy\n");
    let store = Arc::new(PreparedInputArtifacts::default());
    let path = Path::new("x.dm");
    let first = RecordingInputs::new(p.clone(), 1).with_prepared_sources(Some(store.clone()));
    let old = SourceProvider::acquired_source(&first, path)
        .unwrap()
        .unwrap();
    let before = p.reads.load(std::sync::atomic::Ordering::SeqCst);
    let next = RecordingInputs::new(p.clone(), 2).with_prepared_sources(Some(store));
    let current = SourceProvider::acquired_source(&next, path)
        .unwrap()
        .unwrap();
    assert!(
        p.reads.load(std::sync::atomic::Ordering::SeqCst) > before,
        "racy source metadata cannot suppress original-byte validation"
    );
    assert!(old.same_original_acquisition(&current));
    assert!(!old.same_binding(&current));
    assert!(next.validate_source_acquisition(path, &current));
    assert!(!next.validate_source_acquisition(path, &old));
}

#[test]
fn normal_original_view_has_no_second_raw_buffer() {
    let inputs = RecordingInputs::new(P::new(b"/datum/workspace_normal_original\n"), 4_000_000_000);
    let acquired = SourceProvider::acquired_source(&inputs, Path::new("x.dm"))
        .unwrap()
        .unwrap();
    match recorded_source_original(acquired.lease()).unwrap() {
        RecordedSourceOriginal::Utf8(text) => {
            assert!(text.same_view(acquired.prepared().original()))
        }
        RecordedSourceOriginal::Bytes(_) => {
            panic!("ordinary UTF8 must not retain another original buffer")
        }
    }
}
#[test]
fn exceptional_original_survives_recorder_drop_without_prepared_owner_or_buffer_copy() {
    let bytes = b"// \x80\n/datum/workspace_exceptional_original\n";
    let inputs = RecordingInputs::new(P::new(bytes), 4_000_000_000);
    let acquired = SourceProvider::acquired_source(&inputs, Path::new("x.dm"))
        .unwrap()
        .unwrap();
    let lexical = Arc::downgrade(acquired.prepared());
    let lease = acquired.lease().clone();
    let original = inputs
        .exceptional_source_bytes(Path::new("x.dm"))
        .unwrap()
        .unwrap();
    let owner = original.downgrade();
    match recorded_source_original(&lease).unwrap() {
        RecordedSourceOriginal::Bytes(value) => assert!(value.ptr_eq(&original)),
        _ => panic!("invalid original cannot be reconstructed from decoded text"),
    }
    drop(original);
    drop(acquired);
    drop(inputs);
    assert!(lexical.upgrade().is_none());
    assert!(owner.upgrade().is_some());
    match recorded_source_original(&lease).unwrap() {
        RecordedSourceOriginal::Bytes(value) => assert_eq!(value.as_slice(), bytes),
        _ => panic!("original bytes lost"),
    }
    drop(lease);
    assert!(owner.upgrade().is_none());
}
#[test]
fn warm_exceptional_original_reissues_same_acquired_byte_owner_without_read() {
    let provider = P::new(b"// \x80\n/datum/workspace_warm_original\n");
    let store = Arc::new(PreparedInputArtifacts::default());
    let first = RecordingInputs::new(provider.clone(), 4_000_000_000)
        .with_prepared_sources(Some(store.clone()));
    let old = SourceProvider::acquired_source(&first, Path::new("x.dm"))
        .unwrap()
        .unwrap();
    let before = provider.reads.load(std::sync::atomic::Ordering::SeqCst);
    let next =
        RecordingInputs::new(provider.clone(), 5_000_000_000).with_prepared_sources(Some(store));
    let current = SourceProvider::acquired_source(&next, Path::new("x.dm"))
        .unwrap()
        .unwrap();
    assert_eq!(
        provider.reads.load(std::sync::atomic::Ordering::SeqCst),
        before
    );
    match (
        recorded_source_original(old.lease()).unwrap(),
        recorded_source_original(current.lease()).unwrap(),
    ) {
        (RecordedSourceOriginal::Bytes(a), RecordedSourceOriginal::Bytes(b)) => {
            assert!(a.ptr_eq(b))
        }
        _ => panic!("warm exceptional owner changed"),
    }
}
#[test]
fn public_synthetic_lease_cannot_fabricate_recorded_original_view() {
    let fake = dm_preprocess::AcquiredSource::synthetic_utf8("/datum/fake_original\n".into(), ());
    assert!(recorded_source_original(fake.lease()).is_err());
}

#[test]
fn actual_exceptional_open_donates_raw_capacity_and_control_through_reissue() {
    use dm_preprocess::{InitialEnvironment, OriginalRawOpenDecision, OriginalRawReadOutcome};
    use dm_preprocess::source_arena_credit::read_original_source_open_using;

    for (fixture, raw) in [
        ("owned-bom", b"\xef\xbb\xbf/datum/actual\n".as_slice()),
        ("owned-legacy", b"// latin1 \xe9\n/datum/actual\n".as_slice()),
    ] {
        let root = crate::test_scratch::dir(fixture);
        let path = root.join("source.dm");
        std::fs::write(&path, raw).unwrap();
        let db = crate::query_db::QueryDb::default();
        let baseline = db.source_input_admission_bytes().unwrap();
        let input = RecordingInputs::new(FileSystemInputs, 0)
            .with_initial_environment(InitialEnvironment::OriginalChecker0290);
        let outcome = read_original_source_open_using(
            &input, &path, 4096, &db, &mut || Ok(OriginalRawOpenDecision::Read),
        ).unwrap();
        let OriginalRawReadOutcome::Acquired(first) = outcome else {
            panic!("expected actual exceptional open");
        };
        let RecordedSourceOriginal::Bytes(original) = recorded_source_original(&first).unwrap() else {
            panic!("exceptional source must keep raw bytes");
        };
        assert_eq!(original.as_slice(), raw);
        let payload = original.source_arena_payload_credit().unwrap().reserved_bytes();
        let control = original.source_arena_control_credit().unwrap().reserved_bytes();
        assert_eq!(payload, original.capacity());
        assert_eq!(control, dm_resources::SharedBytes::owner_allocation_bytes());
        let weak = original.downgrade();

        let second = RecordingInputs::new(FileSystemInputs, 0)
            .with_initial_environment(InitialEnvironment::OriginalChecker0290);
        let reissued = second.read_raw_source(&path, 4096, Some(&first), |_, _, new| {
            assert!(!new);
            Ok(())
        }).unwrap().unwrap();
        assert!(reissued.same_original_acquisition(&first));
        let RecordedSourceOriginal::Bytes(alias) = recorded_source_original(&reissued).unwrap() else {
            panic!("reissue must retain actual raw bytes");
        };
        assert!(original.ptr_eq(alias));
        assert!(weak.ptr_eq(&alias.downgrade()));
        drop(first);
        drop(input);
        assert!(weak.upgrade().is_some());

        drop(reissued);
        drop(second);
        assert!(weak.upgrade().is_none());
        assert_eq!(weak.source_arena_control_credit().unwrap().reserved_bytes(), control);
        let only_control = db.source_input_admission_bytes().unwrap();
        assert!(only_control >= baseline + control);
        drop(weak);
        assert_eq!(db.source_input_admission_bytes().unwrap(), baseline);
    }
}

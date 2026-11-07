use super::*;
use dm_preprocess::SourceProvider;
use std::sync::{
    atomic::{AtomicUsize, Ordering},
    Arc,
};
#[derive(Clone)]
struct Source {
    bytes: Arc<Mutex<Vec<u8>>>,
    reads: Arc<AtomicUsize>,
    pointer: Arc<AtomicUsize>,
}
impl Source {
    fn new(bytes: &[u8]) -> Self {
        Self {
            bytes: Arc::new(Mutex::new(bytes.to_vec())),
            reads: Arc::new(AtomicUsize::new(0)),
            pointer: Arc::new(AtomicUsize::new(0)),
        }
    }
}
impl SnapshotProvider for Source {
    fn stamp(&self, _: &Path) -> io::Result<Stamp> {
        Ok(Stamp {
            size: self.bytes.lock().unwrap().len() as u64,
            modified_ns: 1,
            file_id: Some(7),
        })
    }
    fn read(&self, path: &Path) -> io::Result<(Stamp, Vec<u8>)> {
        self.reads.fetch_add(1, Ordering::SeqCst);
        let source = self.bytes.lock().unwrap();
        let mut bytes = Vec::with_capacity(source.len() + 31);
        bytes.extend_from_slice(&source);
        drop(source);
        self.pointer
            .store(bytes.as_ptr() as usize, Ordering::SeqCst);
        Ok((self.stamp(path)?, bytes))
    }
    fn list(&self, _: &Path) -> io::Result<FolderListing> {
        Ok(FolderListing::Present(vec!["child.dm".into()]))
    }
}
#[test]
fn normal_utf8_keeps_no_original_byte_buffer_and_consumes_its_allocation() {
    let source = Source::new(b"/datum/ordinary\r\n");
    let ledger = RecordingInputs::new(source.clone(), 1);
    let path = Path::new("ordinary.dm");
    let decoded = SourceProvider::read(&ledger, path).unwrap();
    assert_eq!(decoded.as_bytes(), b"/datum/ordinary\r\n");
    assert_eq!(
        decoded.as_ptr() as usize,
        source.pointer.load(Ordering::SeqCst)
    );
    assert!(ledger.exceptional_source_bytes(path).unwrap().is_none());
    assert_eq!(source.reads.load(Ordering::SeqCst), 1);
}
#[test]
fn bom_and_legacy_bytes_retain_only_the_original_acquisition_allocation() {
    for original in [
        b"\xef\xbb\xbf/datum/bom\n".as_slice(),
        b"// legacy \x80\n/datum/legacy\n".as_slice(),
    ] {
        let source = Source::new(original);
        let ledger = RecordingInputs::new(source.clone(), 1);
        let path = Path::new("exceptional.dm");
        let decoded = SourceProvider::read(&ledger, path).unwrap();
        let bytes = ledger.exceptional_source_bytes(path).unwrap().unwrap();
        assert_eq!(decoded, dm_preprocess::decode_source_bytes(original));
        assert_eq!(bytes.as_slice(), original);
        assert_eq!(
            bytes.as_ptr() as usize,
            source.pointer.load(Ordering::SeqCst)
        );
        assert_eq!(source.reads.load(Ordering::SeqCst), 1);
    }
}
#[test]
fn generated_source_policy_capture_uses_historical_originals_without_rereading() {
    use crate::input_snapshot::GeneratedOutputInputs;
    use dm_analysis::policy_inputs::TextView;
    for original in [
        b"\xef\xbb\xbf/datum/bom\n".as_slice(),
        b"// legacy \x80\n/datum/legacy\n".as_slice(),
    ] {
        let source = Source::new(original);
        let root = std::env::current_dir()
            .unwrap()
            .join("exceptional-generated");
        let path = root.join("code/_generated/child.dm");
        let provider = GeneratedOutputInputs::new(source.clone(), [root.join("code/_generated")]);
        let ledger = RecordingInputs::new(provider, 1);
        let frontend = dm_tree::frontend::build(&path, &ledger, &Default::default(), 1).unwrap();
        let count = source.reads.load(Ordering::SeqCst);
        *source.bytes.lock().unwrap() = b"/datum/replaced\n".to_vec();
        let captured =
            crate::runner_host::policy_capture::capture(&frontend, &ledger, &[], &[]).unwrap();
        assert_eq!(
            source.reads.load(Ordering::SeqCst),
            count,
            "policy must not reread a compiled source"
        );
        let expected = String::from_utf8_lossy(original)
            .replace("\r\n", "\n")
            .replace('\r', "\n");
        assert_eq!(
            captured
                .policy()
                .file(&path)
                .unwrap()
                .view(TextView::AnalyzeRaw)
                .unwrap()
                .as_str(),
            expected
        );
        assert!(captured.policy().file(&path).unwrap().is_compiled());
        assert!(!captured
            .facts()
            .validate(&source, true, 2)
            .unwrap()
            .0
            .unchanged());
    }
}
#[test]
fn warm_preparation_reissues_original_receipt_and_pruning_releases_it() {
    let source = Source::new(b"\xef\xbb\xbf/datum/bom\n");
    let owner = Arc::new(PreparedInputArtifacts::default());
    let path = Path::new("source.dm");
    let first = RecordingInputs::new(source.clone(), 10_000_000_000)
        .with_prepared_sources(Some(owner.clone()));
    let prepared = first.prepared_source(path).unwrap();
    first.finish_prepared().unwrap();
    let original = first.exceptional_source_bytes(path).unwrap().unwrap();
    let weak = original.downgrade();
    drop(first);
    let second = RecordingInputs::new(source.clone(), 20_000_000_000)
        .with_prepared_sources(Some(owner.clone()));
    let reused = second.prepared_source(path).unwrap();
    assert!(Arc::ptr_eq(&prepared, &reused));
    assert!(original.ptr_eq(&second.exceptional_source_bytes(path).unwrap().unwrap()));
    second.finish_prepared().unwrap();
    let census = crate::heap_census::prepared_input_census(&owner);
    assert!(census
        .owners
        .iter()
        .any(|row| row.owner == "prepared_inputs.exceptional_original_bytes"));
    drop(second);
    drop(original);
    assert!(weak.upgrade().is_some());
    let prune = RecordingInputs::new(source, 30_000_000_000).with_prepared_sources(Some(owner));
    prune.finish_prepared().unwrap();
    assert!(weak.upgrade().is_none());
}
#[test]
fn contradicted_original_receipts_cannot_be_returned_or_rebound() {
    let source = Source::new(b"\xef\xbb\xbf/datum/bom\n");
    let ledger = RecordingInputs::new(source, 1);
    let path = Path::new("source.dm");
    SourceProvider::read(&ledger, path).unwrap();
    assert!(ledger
        .remember_exceptional_source(
            path,
            dm_resources::SharedBytes::from(b"\xef\xbb\xbfdifferent".as_slice())
        )
        .is_err());
    let canonical = canonical_path(path);
    ledger
        .exceptional_originals
        .lock()
        .unwrap()
        .get_mut(&canonical)
        .unwrap()
        .bytes = dm_resources::SharedBytes::from(b"forged".as_slice());
    assert!(ledger.exceptional_source_bytes(path).is_err());
}
struct Count<P> {
    provider: P,
    reads: AtomicUsize,
}
impl<P: SnapshotProvider> SnapshotProvider for Count<P> {
    fn stamp(&self, path: &Path) -> io::Result<Stamp> {
        self.provider.stamp(path)
    }
    fn read(&self, path: &Path) -> io::Result<(Stamp, Vec<u8>)> {
        self.reads.fetch_add(1, Ordering::SeqCst);
        self.provider.read(path)
    }
    fn list(&self, path: &Path) -> io::Result<FolderListing> {
        self.provider.list(path)
    }
}
#[test]
fn frozen_replay_preserves_original_encoding_with_one_payload_acquisition() {
    use dm_analysis::policy_inputs::TextView;
    let root = crate::test_scratch::dir("exceptional-source-replay");
    let path = root.join("child.dm");
    let journal = root.join("journal");
    let original = b"\xef\xbb\xbf/datum/bom\n";
    std::fs::write(&path, original).unwrap();
    {
        let recording = crate::frozen_inputs::Inputs::record(&journal).unwrap();
        let counter = Count {
            provider: &recording,
            reads: AtomicUsize::new(0),
        };
        let ledger = RecordingInputs::new(&counter, 1);
        let frontend = dm_tree::frontend::build(&path, &ledger, &Default::default(), 1).unwrap();
        assert_eq!(counter.reads.load(Ordering::SeqCst), 1);
        crate::runner_host::policy_capture::capture(&frontend, &ledger, &[], &[]).unwrap();
        assert_eq!(counter.reads.load(Ordering::SeqCst), 1);
        recording.finish().unwrap();
    }
    std::fs::write(&path, b"/datum/live_changed\n").unwrap();
    let replay = crate::frozen_inputs::Inputs::replay(&journal).unwrap();
    let counter = Count {
        provider: &replay,
        reads: AtomicUsize::new(0),
    };
    let ledger = RecordingInputs::new(&counter, 2);
    let frontend = dm_tree::frontend::build(&path, &ledger, &Default::default(), 1).unwrap();
    let captured =
        crate::runner_host::policy_capture::capture(&frontend, &ledger, &[], &[]).unwrap();
    assert_eq!(counter.reads.load(Ordering::SeqCst), 1);
    assert_eq!(
        captured
            .policy()
            .file(&path)
            .unwrap()
            .view(TextView::AnalyzeRaw)
            .unwrap()
            .as_str(),
        "\u{feff}/datum/bom\n"
    );
}

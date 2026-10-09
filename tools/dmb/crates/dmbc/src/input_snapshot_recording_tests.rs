use super::*;
use std::sync::{
    atomic::{AtomicUsize, Ordering},
    Barrier,
};

#[test]
fn exact_and_authored_alias_reads_keep_one_canonical_fact_and_conflict_checks() {
    let mut snapshot = InputSnapshot::new(1);
    let path = Path::new("folder/source.dm");
    let alias = Path::new("folder/./source.dm");
    let stamp = Stamp {
        size: 3,
        modified_ns: 1,
        file_id: Some(1),
    };
    snapshot.record_file(path, stamp.clone(), b"one").unwrap();
    snapshot.record_file(path, stamp.clone(), b"one").unwrap();
    snapshot.record_file(alias, stamp.clone(), b"one").unwrap();
    assert!(snapshot.contains_file(path));
    assert!(snapshot.contains_file(alias));
    assert_eq!(snapshot.files().count(), 1);
    assert_eq!(snapshot.files().next().unwrap().path, canonical_path(path));
    for candidate in [path, alias] {
        assert_eq!(
            snapshot
                .record_file(candidate, stamp.clone(), b"two")
                .unwrap_err()
                .kind(),
            io::ErrorKind::InvalidData
        );
    }
    let listing = FolderListing::Present(vec!["source.dm".into()]);
    snapshot
        .record_folder(Path::new("folder"), listing.clone())
        .unwrap();
    snapshot
        .record_folder(Path::new("folder"), listing.clone())
        .unwrap();
    snapshot
        .record_folder(Path::new("folder/."), listing)
        .unwrap();
    assert_eq!(snapshot.folders().len(), 1);
    assert!(snapshot
        .record_folder(Path::new("folder"), FolderListing::Missing)
        .is_err());
    snapshot.check_structure().unwrap();
}

struct ConcurrentReads {
    readers: Barrier,
    sequence: AtomicUsize,
}
impl SnapshotProvider for ConcurrentReads {
    fn stamp(&self, _: &Path) -> io::Result<Stamp> {
        Ok(Stamp {
            size: 3,
            modified_ns: 1,
            file_id: Some(1),
        })
    }
    fn read(&self, path: &Path) -> io::Result<(Stamp, Vec<u8>)> {
        let first = self.sequence.fetch_add(1, Ordering::Relaxed) == 0;
        self.readers.wait();
        Ok((
            self.stamp(path)?,
            if first {
                b"one".to_vec()
            } else {
                b"two".to_vec()
            },
        ))
    }
    fn list(&self, _: &Path) -> io::Result<FolderListing> {
        unreachable!("source reads do not enumerate directories")
    }
}

#[test]
fn concurrent_changed_reads_admit_one_exact_payload_and_reject_the_other() {
    let inputs = RecordingInputs::new(
        ConcurrentReads {
            readers: Barrier::new(2),
            sequence: AtomicUsize::new(0),
        },
        1,
    );
    let path = Path::new("same.dm");
    let results = std::thread::scope(|scope| {
        let first = scope.spawn(|| inputs.read_recorded(path));
        let second = scope.spawn(|| inputs.read_recorded(path));
        [first.join().unwrap(), second.join().unwrap()]
    });
    assert_eq!(results.iter().filter(|result| result.is_ok()).count(), 1);
    let accepted = results
        .iter()
        .find_map(|result| result.as_ref().ok())
        .unwrap();
    let rejected = results
        .iter()
        .find_map(|result| result.as_ref().err())
        .unwrap();
    assert_eq!(rejected.kind(), io::ErrorKind::InvalidData);
    assert_eq!(
        rejected.to_string(),
        "input changed during repeated capture"
    );
    let snapshot = inputs.snapshot().unwrap();
    assert_eq!(snapshot.files.len(), 1);
    let captured = snapshot.files.get(&canonical_path(path)).unwrap();
    assert_eq!(captured.content, xxhash_rust::xxh3::xxh3_128(accepted));
    assert_eq!(captured.stamp.size, accepted.len() as u64);
}

struct EnvelopeProvider {
    verified_reads: AtomicUsize,
}
impl SnapshotProvider for EnvelopeProvider {
    fn stamp(&self, _: &Path) -> io::Result<Stamp> {
        Ok(Stamp {
            size: 7,
            modified_ns: 1,
            file_id: Some(3),
        })
    }
    fn read(&self, _: &Path) -> io::Result<(Stamp, Vec<u8>)> {
        panic!("verified-read consumers must preserve the provider override")
    }
    fn read_verified(&self, path: &Path) -> io::Result<CapturedInputRead> {
        self.verified_reads.fetch_add(1, Ordering::Relaxed);
        Ok(CapturedInputRead::new(
            self.stamp(path)?,
            b"payload".to_vec(),
        ))
    }
    fn list(&self, _: &Path) -> io::Result<FolderListing> {
        unreachable!()
    }
}
#[test]
fn recording_and_default_digest_forward_the_authenticated_provider_read() {
    let provider = EnvelopeProvider {
        verified_reads: AtomicUsize::new(0),
    };
    let path = Path::new("verified.dm");
    let recording = RecordingInputs::new(&provider, 1);
    assert_eq!(
        recording.read_recorded(path).unwrap().as_slice(),
        b"payload"
    );
    assert_eq!(provider.verified_reads.load(Ordering::Relaxed), 1);
    let expected = xxhash_rust::xxh3::xxh3_128(b"payload");
    assert_eq!(
        recording.snapshot().unwrap().files[&canonical_path(path)].content,
        expected
    );
    // Select the reference provider implementation explicitly; method-call
    // autoderef would instead exercise EnvelopeProvider directly.
    assert_eq!(
        <&EnvelopeProvider as SnapshotProvider>::digest(&&provider, path)
            .unwrap()
            .1,
        expected
    );
    assert_eq!(provider.verified_reads.load(Ordering::Relaxed), 2);
}

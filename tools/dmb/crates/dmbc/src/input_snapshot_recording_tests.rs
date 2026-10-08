use super::*;
use std::sync::{
    atomic::{AtomicUsize, Ordering},
    Barrier,
};

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

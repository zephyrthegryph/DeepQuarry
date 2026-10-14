use super::*;
use crate::input_snapshot::{FileInput, FolderListing};
use std::cell::Cell;
struct Provider {
    stamp: Stamp,
    bytes: Vec<u8>,
    reads: Cell<usize>,
}
impl SnapshotProvider for Provider {
    fn stamp(&self, _: &Path) -> io::Result<Stamp> {
        Ok(self.stamp.clone())
    }
    fn read(&self, _: &Path) -> io::Result<(Stamp, Vec<u8>)> {
        self.reads.set(self.reads.get() + 1);
        Ok((self.stamp.clone(), self.bytes.clone()))
    }
    fn list(&self, _: &Path) -> io::Result<FolderListing> {
        Ok(FolderListing::Missing)
    }
}
fn proof(provider: &Provider, scanned: u128) -> InputSnapshot {
    let mut snapshot = InputSnapshot::new(scanned);
    snapshot
        .record_file(
            Path::new("output.rsc"),
            provider.stamp.clone(),
            &provider.bytes,
        )
        .unwrap();
    snapshot
}
#[test]
fn stable_authenticated_hint_skips_read_but_exact_racy_and_unknown_identity_hash() {
    let mut provider = Provider {
        stamp: Stamp {
            size: 6,
            modified_ns: 1,
            file_id: Some(7),
        },
        bytes: b"assets".to_vec(),
        reads: Cell::new(0),
    };
    let snapshot = proof(&provider, 10_000_000_000);
    let expected = (6, xxh3_128(b"assets"));
    assert!(
        validate(&snapshot, &provider, expected, false, 20_000_000_000)
            .unwrap()
            .is_some()
    );
    assert_eq!(provider.reads.get(), 0);
    assert!(
        validate(&snapshot, &provider, expected, true, 20_000_000_000)
            .unwrap()
            .is_some()
    );
    assert_eq!(provider.reads.get(), 1);
    let racy = proof(&provider, 1);
    assert!(validate(&racy, &provider, expected, false, 20_000_000_000)
        .unwrap()
        .is_some());
    assert_eq!(provider.reads.get(), 2);
    provider.stamp.file_id = None;
    let no_id = proof(&provider, 10_000_000_000);
    assert!(validate(&no_id, &provider, expected, false, 20_000_000_000)
        .unwrap()
        .is_some());
    assert_eq!(provider.reads.get(), 3);
}
#[test]
fn expected_identity_and_exact_same_stamp_tampering_cannot_reuse_hint() {
    let mut provider = Provider {
        stamp: Stamp {
            size: 6,
            modified_ns: 1,
            file_id: Some(7),
        },
        bytes: b"assets".to_vec(),
        reads: Cell::new(0),
    };
    let snapshot = proof(&provider, 10_000_000_000);
    assert!(validate(
        &snapshot,
        &provider,
        (6, xxh3_128(b"newres")),
        false,
        20_000_000_000
    )
    .unwrap()
    .is_none());
    assert_eq!(provider.reads.get(), 0);
    provider.bytes = b"edited".to_vec();
    assert!(validate(
        &snapshot,
        &provider,
        (6, xxh3_128(b"assets")),
        true,
        20_000_000_000
    )
    .unwrap()
    .is_none());
    assert_eq!(provider.reads.get(), 1);
    provider.stamp.modified_ns = 2;
    assert!(validate(
        &snapshot,
        &provider,
        (6, xxh3_128(b"assets")),
        false,
        20_000_000_000
    )
    .unwrap()
    .is_none());
    assert_eq!(provider.reads.get(), 2);
}
fn output_snapshot(path: &Path) -> InputSnapshot {
    let (stamp, hash) = FileSystemInputs.digest(path).unwrap();
    let mut snapshot = InputSnapshot::new(0);
    snapshot.record_verified_digest(path, stamp, hash).unwrap();
    snapshot
}
#[test]
fn prior_receipt_restats_and_final_capture_rejects_later_edit() {
    let store = super::super::super::tests::store();
    let destination = store.root.join("output.rsc");
    fs::write(&destination, b"assets").unwrap();
    let snapshot = output_snapshot(&destination);
    let receipt = PriorResourceProof::new(&snapshot, 1)
        .authenticate(&destination, (6, xxh3_128(b"assets")), false)
        .unwrap()
        .expect("authenticated isolated destination");
    let installed = receipt::InstallationReceipt {
        files: vec![receipt],
        exact: false,
    };
    installed
        .record_outputs(&mut InputSnapshot::new(1))
        .unwrap();
    fs::write(&destination, b"tampered output").unwrap();
    assert!(installed
        .record_outputs(&mut InputSnapshot::new(2))
        .is_err());
}
#[test]
fn shared_hardlink_is_replaced_and_resource_identity_mismatch_repairs_output() {
    let store = super::super::super::tests::store();
    let source = store.root.join("source.rsc");
    let destination = store.root.join("output.rsc");
    fs::write(&source, b"assets").unwrap();
    fs::hard_link(&source, &destination).unwrap();
    let snapshot = output_snapshot(&destination);
    assert!(PriorResourceProof::new(&snapshot, 1)
        .authenticate(&destination, (6, xxh3_128(b"assets")), false)
        .unwrap()
        .is_none());
    resource_receipt_with_prior(
        &source,
        &destination,
        (6, xxh3_128(b"assets")),
        Some(PriorResourceProof::new(&snapshot, 1)),
        false,
    )
    .unwrap();
    fs::write(&destination, b"edited").unwrap();
    assert_eq!(fs::read(&source).unwrap(), b"assets");
    let stale = output_snapshot(&destination);
    resource_receipt_with_prior(
        &source,
        &destination,
        (6, xxh3_128(b"assets")),
        Some(PriorResourceProof::new(&stale, 1)),
        true,
    )
    .unwrap();
    assert_eq!(fs::read(&destination).unwrap(), b"assets");
}
#[test]
fn selecting_one_output_does_not_require_old_program_identity() {
    let provider = Provider {
        stamp: Stamp {
            size: 6,
            modified_ns: 1,
            file_id: Some(7),
        },
        bytes: b"assets".to_vec(),
        reads: Cell::new(0),
    };
    let mut snapshot = proof(&provider, 10_000_000_000);
    snapshot
        .record_verified_digest(
            Path::new("output.dmb"),
            Stamp {
                size: 3,
                modified_ns: 2,
                file_id: Some(8),
            },
            xxh3_128(b"old"),
        )
        .unwrap();
    let selected = snapshot
        .select_files(&[PathBuf::from("output.rsc")].into_iter().collect())
        .unwrap();
    let files: Vec<&FileInput> = selected.files().collect();
    assert_eq!(files.len(), 1);
    assert!(validate(
        &selected,
        &provider,
        (6, xxh3_128(b"assets")),
        false,
        20_000_000_000
    )
    .unwrap()
    .is_some());
    assert_eq!(provider.reads.get(), 0);
}

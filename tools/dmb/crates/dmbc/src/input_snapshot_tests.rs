use super::*;
use std::cell::Cell;
#[test]
fn owned_source_preserves_decoder_and_utf8_allocation() {
    let bytes = b"ordinary source".to_vec();
    let allocation = bytes.as_ptr();
    let decoded = decode_owned_source(bytes);
    assert_eq!(decoded.as_ptr(), allocation);
    for bytes in [
        b"\xef\xbb\xbfhello".as_slice(),
        b"\xef\xbb\xbf\xef\xbb\xbf\x80",
        b"valid \xc3\xa9 then \x80\xff\xc3",
        b"",
    ] {
        assert_eq!(
            decode_owned_source(bytes.to_vec()),
            dm_preprocess::decode_source_bytes(bytes)
        );
    }
}
struct Host {
    bytes: Vec<u8>,
    stamp: Stamp,
    listing: FolderListing,
    reads: Cell<usize>,
    listings: Cell<usize>,
}
impl SnapshotProvider for Host {
    fn stamp(&self, _: &Path) -> io::Result<Stamp> {
        Ok(self.stamp.clone())
    }
    fn read(&self, _: &Path) -> io::Result<(Stamp, Vec<u8>)> {
        self.reads.set(self.reads.get() + 1);
        Ok((self.stamp.clone(), self.bytes.clone()))
    }
    fn list(&self, _: &Path) -> io::Result<FolderListing> {
        self.listings.set(self.listings.get() + 1);
        Ok(self.listing.clone())
    }
}
#[test]
fn compound_exact_positive_observes_each_canonical_file_once_and_keeps_role_order() {
    use std::cell::RefCell;

    struct Counting {
        stamp: Stamp,
        seen: RefCell<Vec<String>>,
        failing: Cell<Option<(&'static str, Option<i32>)>>,
    }
    impl SnapshotProvider for Counting {
        fn stamp(&self, _: &Path) -> io::Result<Stamp> { panic!("exact phase requests digest evidence") }
        fn read(&self, _: &Path) -> io::Result<(Stamp, Vec<u8>)> { panic!("no payload copies in this phase") }
        fn list(&self, _: &Path) -> io::Result<FolderListing> { panic!("separate role admission checks directories") }
        fn digest(&self, path: &Path) -> io::Result<(Stamp, u128)> {
            let name = path.file_name().unwrap().to_str().unwrap();
            self.seen.borrow_mut().push(name.to_owned());
            if let Some((target, error)) = self.failing.get() {
                if target == name {
                    return Err(error.map_or_else(|| io::ErrorKind::NotFound.into(), io::Error::from_raw_os_error));
                }
            }
            Ok((self.stamp.clone(), xxhash_rust::xxh3::xxh3_128(b"x")))
        }
    }
    let root = std::env::temp_dir().join("compound-exact-positive-counting");
    let shared = root.join("b-shared.dm");
    let native_only = root.join("a-native.dm");
    let report_only = root.join("0-report.dm");
    let stamp = Stamp { size: 1, modified_ns: 4, file_id: Some(8) };
    let source = Counting { stamp: stamp.clone(), seen: RefCell::new(Vec::new()), failing: Cell::new(None) };
    let mut native = InputSnapshot::new(1);
    native.record_file(&native_only, stamp.clone(), b"x").unwrap();
    native.record_file(&shared, stamp.clone(), b"x").unwrap();
    let mut report = InputSnapshot::new(1);
    report.record_file(&root.join(".").join("b-shared.dm"), stamp.clone(), b"x").unwrap();
    report.record_file(&report_only, stamp.clone(), b"x").unwrap();
    report.require_shared_native_files(&native).unwrap();
    assert!(native.exact_positive_contents_match_pair(&report, &source).unwrap());
    assert_eq!(source.seen.take(), ["a-native.dm", "b-shared.dm", "0-report.dm"]);

    let mut wrong = InputSnapshot::new(1);
    wrong.record_file(&shared, Stamp { modified_ns: 5, ..stamp.clone() }, b"x").unwrap();
    assert!(!native.exact_positive_contents_match_pair(&wrong, &source).unwrap());
    assert_eq!(source.seen.take(), ["a-native.dm", "b-shared.dm"]);
    let mut mismatch = InputSnapshot::new(1);
    mismatch.record_file(&shared, stamp, b"y").unwrap();
    assert_eq!(mismatch.require_shared_native_files(&native).unwrap_err().kind(), io::ErrorKind::Interrupted);
    assert!(source.seen.borrow().is_empty(), "conflicting capture facts never reach the live exact phase");
    let mut negative = InputSnapshot::new(1);
    negative.record_negative(&shared).unwrap();
    assert_eq!(negative.require_shared_native_files(&native).unwrap_err().kind(), io::ErrorKind::Interrupted);

    source.failing.set(Some(("a-native.dm", Some(1450))));
    assert_eq!(native.exact_positive_contents_match_pair(&report, &source).unwrap_err().raw_os_error(), Some(1450));
    assert_eq!(source.seen.take(), ["a-native.dm"]);
    source.failing.set(Some(("b-shared.dm", None)));
    assert!(!native.exact_positive_contents_match_pair(&report, &source).unwrap());
    assert_eq!(source.seen.take(), ["a-native.dm", "b-shared.dm"]);
    source.failing.set(Some(("0-report.dm", Some(1451))));
    assert_eq!(native.exact_positive_contents_match_pair(&report, &source).unwrap_err().raw_os_error(), Some(1451));
    assert_eq!(source.seen.take(), ["a-native.dm", "b-shared.dm", "0-report.dm"]);
}

#[test]
fn exact_and_racy_inputs_rehash_and_negative_folders_invalidate() {
    let mut host = Host {
        bytes: b"old".to_vec(),
        stamp: Stamp {
            size: 3,
            modified_ns: 1,
            file_id: Some(9),
        },
        listing: FolderListing::Missing,
        reads: Cell::new(0),
        listings: Cell::new(0),
    };
    let mut snapshot = InputSnapshot::new(10_000_000_000);
    snapshot
        .record_file(Path::new("project.dm"), host.stamp.clone(), &host.bytes)
        .unwrap();
    snapshot
        .record_folder(Path::new("assets"), FolderListing::Missing)
        .unwrap();
    assert!(snapshot
        .validate(&host, false, 20_000_000_000)
        .unwrap()
        .0
        .unchanged());
    assert_eq!(host.reads.get(), 0);
    host.bytes = b"new".to_vec();
    assert!(!snapshot
        .validate(&host, true, 20_000_000_000)
        .unwrap()
        .0
        .unchanged());
    snapshot.scanned_ns = 1;
    assert!(!snapshot
        .validate(&host, false, 20_000_000_000)
        .unwrap()
        .0
        .unchanged());
    host.bytes = b"old".to_vec();
    host.listing = FolderListing::Present(vec!["new.png".into()]);
    assert_eq!(
        snapshot
            .validate(&host, false, 20_000_000_000)
            .unwrap()
            .0
            .changed,
        vec![PathBuf::from("assets")]
    );
}
#[test]
fn captured_bytes_and_repeated_reads_are_exact() {
    let mut snapshot = InputSnapshot::new(0);
    let stamp = Stamp {
        size: 3,
        modified_ns: 1,
        file_id: None,
    };
    snapshot
        .record_file(Path::new("a.dm"), stamp.clone(), b"one")
        .unwrap();
    assert!(snapshot
        .record_file(Path::new("a.dm"), stamp, b"two")
        .is_err());
    assert!(snapshot
        .record_folder(
            Path::new("assets"),
            FolderListing::Present(vec!["b".into(), "a".into()])
        )
        .is_err());
}
#[test]
fn recording_lists_each_resource_parent_once_then_restats() {
    let host = Host {
        bytes: b"asset".to_vec(),
        stamp: Stamp {
            size: 5,
            modified_ns: 1,
            file_id: Some(1),
        },
        listing: FolderListing::Present(vec!["a.png".into(), "b.png".into()]),
        reads: Cell::new(0),
        listings: Cell::new(0),
    };
    let recording = RecordingInputs::new(host, 10_000_000_000);
    dm_resources::capture::CaptureProvider::read_candidate(&recording, Path::new("assets/a.png"))
        .unwrap();
    dm_resources::capture::CaptureProvider::read_candidate(&recording, Path::new("assets/b.png"))
        .unwrap();
    assert_eq!(recording.provider.listings.get(), 1);
    let snapshot = recording.snapshot().unwrap();
    assert!(snapshot.restat(&recording.provider).unwrap().unchanged());
    assert_eq!(recording.provider.listings.get(), 2);
}
#[test]
fn structural_receipt_is_private_nonsemantic_and_never_deserialized() {
    let mut snapshot = InputSnapshot::new(0);
    let stamp = Stamp {
        size: 3,
        modified_ns: 1,
        file_id: None,
    };
    snapshot
        .record_file(Path::new("a.dm"), stamp, b"one")
        .unwrap();
    let bytes = dm_wire::encode(0x5350_0001, &snapshot).unwrap();
    let restored: InputSnapshot = dm_wire::decode(0x5350_0001, &bytes, dm_wire::MAX_BYTES).unwrap();
    assert!(restored.structure_proof.0.get().is_none());
    assert_eq!(snapshot, restored);
    restored.check_structure().unwrap();
    assert!(restored.structure_proof.0.get().is_some());
    assert_eq!(bytes, dm_wire::encode(0x5350_0001, &restored).unwrap());
    assert!(restored.clone().structure_proof.0.get().is_some());
    snapshot
        .record_folder(
            Path::new("assets"),
            FolderListing::Present(vec!["a".into()]),
        )
        .unwrap();
    assert!(snapshot
        .record_folder(
            Path::new("bad"),
            FolderListing::Present(vec!["z".into(), "a".into()])
        )
        .is_err());
    assert!(snapshot.record_negative(Path::new("a.dm")).is_err());
    snapshot.check_structure().unwrap();

    // Simulate a malformed untrusted wire record; admission must not inherit
    // the valid in-memory issuer receipt from this deliberately forged copy.
    let mut malformed = snapshot.clone();
    malformed.folders.insert(
        PathBuf::from("bad"),
        FolderListing::Present(vec!["z".into(), "a".into()]),
    );
    let bytes = dm_wire::encode(0x5350_0001, &malformed).unwrap();
    let malformed: InputSnapshot =
        dm_wire::decode(0x5350_0001, &bytes, dm_wire::MAX_BYTES).unwrap();
    assert!(malformed.check_structure().is_err());
    assert!(malformed.structure_proof.0.get().is_none());
}
#[test]
fn reuse_validation_stops_on_changes_but_success_refreshes_every_file() {
    let mut host = Host {
        bytes: b"old".to_vec(),
        stamp: Stamp {
            size: 3,
            modified_ns: 1,
            file_id: Some(9),
        },
        listing: FolderListing::Missing,
        reads: Cell::new(0),
        listings: Cell::new(0),
    };
    let mut snapshot = InputSnapshot::new(10_000_000_000);
    for name in ["a.dm", "b.dm", "c.dm", "d.dm"] {
        snapshot
            .record_file(Path::new(name), host.stamp.clone(), &host.bytes)
            .unwrap();
    }
    snapshot
        .record_folder(Path::new("assets"), FolderListing::Missing)
        .unwrap();
    host.bytes = b"new".to_vec();
    assert!(snapshot
        .validate_for_reuse(&host, true, 20_000_000_000)
        .unwrap()
        .is_none());
    assert_eq!(host.reads.get(), 1);
    assert_eq!(host.listings.get(), 0);
    let full = snapshot.validate(&host, true, 20_000_000_000).unwrap();
    assert_eq!(
        full.0.changed.len(),
        4,
        "public API still reports all changes"
    );
    host.bytes = b"old".to_vec();
    host.stamp.modified_ns = 3;
    host.reads.set(0);
    let (report, refreshed) = snapshot
        .validate_for_reuse(&host, false, 20_000_000_000)
        .unwrap()
        .unwrap();
    assert!(report.unchanged());
    assert_eq!(report.rehashed, 4);
    assert_eq!(host.reads.get(), 4);
    assert!(refreshed.files().all(|file| file.stamp.modified_ns == 3));
    assert_eq!(refreshed.scanned_ns, 20_000_000_000);
    host.listing = FolderListing::Present(vec!["new.asset".into()]);
    assert!(refreshed
        .validate_for_reuse(&host, false, 30_000_000_000)
        .unwrap()
        .is_none());
}
#[test]
fn reuse_validation_missing_negative_and_io_boundaries_fail_closed() {
    struct Probe {
        result: io::ErrorKind,
        present: bool,
        calls: Cell<usize>,
    }
    impl SnapshotProvider for Probe {
        fn stamp(&self, _: &Path) -> io::Result<Stamp> {
            self.calls.set(self.calls.get() + 1);
            if self.present {
                Ok(Stamp {
                    size: 1,
                    modified_ns: 1,
                    file_id: Some(1),
                })
            } else {
                Err(io::Error::from(self.result))
            }
        }
        fn read(&self, _: &Path) -> io::Result<(Stamp, Vec<u8>)> {
            panic!("early rejection must not read payload")
        }
        fn list(&self, _: &Path) -> io::Result<FolderListing> {
            panic!("early rejection must not list folders")
        }
    }
    let mut files = InputSnapshot::new(10_000_000_000);
    for path in ["a.dm", "b.dm"] {
        files
            .record_file(
                Path::new(path),
                Stamp {
                    size: 1,
                    modified_ns: 1,
                    file_id: Some(1),
                },
                b"x",
            )
            .unwrap();
    }
    let missing = Probe {
        result: io::ErrorKind::NotFound,
        present: false,
        calls: Cell::new(0),
    };
    assert!(files
        .validate_for_reuse(&missing, false, 20_000_000_000)
        .unwrap()
        .is_none());
    assert_eq!(missing.calls.get(), 1);
    let denied = Probe {
        result: io::ErrorKind::PermissionDenied,
        present: false,
        calls: Cell::new(0),
    };
    assert_eq!(
        files
            .validate_for_reuse(&denied, false, 20_000_000_000)
            .unwrap_err()
            .kind(),
        io::ErrorKind::PermissionDenied
    );
    let mut absent = InputSnapshot::new(10_000_000_000);
    for path in ["a.dm", "b.dm"] {
        absent.record_negative(Path::new(path)).unwrap();
    }
    let found = Probe {
        result: io::ErrorKind::NotFound,
        present: true,
        calls: Cell::new(0),
    };
    assert!(absent
        .validate_for_reuse(&found, false, 20_000_000_000)
        .unwrap()
        .is_none());
    assert_eq!(found.calls.get(), 1);
    assert_eq!(
        absent
            .validate(&found, false, 20_000_000_000)
            .unwrap()
            .0
            .changed
            .len(),
        2
    );
}

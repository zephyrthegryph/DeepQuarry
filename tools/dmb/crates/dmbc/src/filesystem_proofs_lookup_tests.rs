//! Both exact borrowed keys and authored aliases retain the same proof semantics.
use super::*;
fn proofs() -> (BulkFileSystemProofs, PathBuf) {
    let parent = canonical_path(Path::new("proofs/folder"));
    let mut proof = BulkFileSystemProofs::capture([], []);
    proof.directories.insert(
        parent.clone(),
        DirectoryProof {
            entries: BTreeMap::from([(
                "item.dm".into(),
                Some(Stamp {
                    size: 9,
                    modified_ns: 7,
                    file_id: Some(3),
                }),
            )]),
            aliases: BTreeSet::from(["item.dm".into()]),
            ascii: true,
            charged: 0,
        },
    );
    proof.missing_directories.insert(parent.join("missing"));
    (proof, parent)
}
#[test]
fn exact_and_dot_alias_queries_have_identical_positive_folder_and_absence_proofs() {
    let (proof, parent) = proofs();
    let alias = parent.join("../folder");
    assert_eq!(proof.list(&parent).unwrap(), proof.list(&alias).unwrap());
    assert_eq!(
        proof.stamp(&parent.join("item.dm")).unwrap(),
        proof.stamp(&alias.join("item.dm")).unwrap()
    );
    for file in [
        parent.join("absent.dm"),
        alias.join("absent.dm"),
        parent.join("missing/absent.dm"),
    ] {
        assert_eq!(
            proof.stamp(&file).unwrap_err().kind(),
            io::ErrorKind::NotFound
        );
    }
    assert_eq!(
        proof.list(&parent.join("missing")).unwrap(),
        FolderListing::Missing
    );
    assert_eq!(proof.counts().live_stamp_fallbacks, 0);
}
#[test]
fn alternate_case_and_reserved_names_still_require_live_fallback() {
    let (proof, parent) = proofs();
    // Either success or a platform-specific error is legitimate; the synthetic
    // membership proof must not itself authorize these alternate namespaces.
    let _ = proof.stamp(&parent.join("ITEM.dm"));
    let _ = proof.stamp(&parent.join("NUL"));
    assert_eq!(proof.counts().live_stamp_fallbacks, 2);
    assert_eq!(proof.counts().negative_proofs, 0);
}
#[test]
fn snapshot_and_compatibility_capture_preserve_roster_answers_and_counts() {
    let mut snapshot = crate::input_snapshot::InputSnapshot::new(10_000_000_000);
    let folder = canonical_path(Path::new("dmb-proof-absent-fixture-parent"));
    let file = folder.join("source.dm");
    snapshot
        .record_file(
            &file,
            Stamp {
                size: 3,
                modified_ns: 1,
                file_id: Some(7),
            },
            b"one",
        )
        .unwrap();
    snapshot
        .record_folder(&folder, FolderListing::Missing)
        .unwrap();
    snapshot.record_negative(&folder.join("absent.dm")).unwrap();
    let old = BulkFileSystemProofs::capture(snapshot.proof_paths(), snapshot.proof_folders());
    let next = BulkFileSystemProofs::capture_snapshot(&snapshot).unwrap();
    for path in snapshot.proof_paths() {
        let old_answer = old.stamp(&path);
        let next_answer = next.stamp(&path);
        match (old_answer, next_answer) {
            (Ok(old), Ok(next)) => assert_eq!(old, next),
            (Err(old), Err(next)) => assert_eq!(old.kind(), next.kind()),
            _ => panic!("proof capture changed answer"),
        }
    }
    assert_eq!(old.list(&folder).unwrap(), next.list(&folder).unwrap());
    assert_eq!(old.counts(), next.counts());
}
#[test]
fn malformed_snapshot_roster_rejects_before_directory_capture() {
    let snapshot = crate::input_snapshot::InputSnapshot::new(1);
    let mut value = serde_json::to_value(snapshot).unwrap();
    value["negative_files"] = serde_json::json!(["folder/../noncanonical.dm"]);
    let malformed = serde_json::from_value(value).unwrap();
    let result = BulkFileSystemProofs::capture_snapshot(&malformed);
    assert!(matches!(result,Err(error) if error.kind()==io::ErrorKind::InvalidData));
}

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

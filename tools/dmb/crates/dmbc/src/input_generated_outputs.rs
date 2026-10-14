//! Caller-owned output names affect membership proofs, never source reads.
use super::*;
pub struct GeneratedOutputInputs<P> {
    provider: P,
    paths: BTreeSet<PathBuf>,
}
impl<P> GeneratedOutputInputs<P> {
    pub fn new(provider: P, paths: impl IntoIterator<Item = PathBuf>) -> Self {
        Self {
            provider,
            paths: paths.into_iter().map(|p| canonical_path(&p)).collect(),
        }
    }
}
impl<P: SnapshotProvider> SnapshotProvider for GeneratedOutputInputs<P> {
    fn generated_outputs(&self) -> Option<&BTreeSet<PathBuf>> {
        Some(&self.paths)
    }
    fn stamp(&self, path: &Path) -> io::Result<Stamp> {
        self.provider.stamp(path)
    }
    fn read(&self, path: &Path) -> io::Result<(Stamp, Vec<u8>)> {
        self.provider.read(path)
    }
    fn read_verified(&self, path: &Path) -> io::Result<CapturedInputRead> {
        self.provider.read_verified(path)
    }
    fn digest(&self, path: &Path) -> io::Result<(Stamp, u128)> {
        self.provider.digest(path)
    }
    fn list(&self, path: &Path) -> io::Result<FolderListing> {
        self.provider.list(path)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;
    struct Files(RefCell<Vec<String>>, RefCell<bool>);
    impl SnapshotProvider for Files {
        fn list(&self, _: &Path) -> io::Result<FolderListing> {
            let mut names = self.0.borrow().clone();
            names.sort();
            Ok(FolderListing::Present(names))
        }
        fn stamp(&self, _: &Path) -> io::Result<Stamp> {
            if *self.1.borrow() {
                Ok(Stamp {
                    size: 1,
                    modified_ns: 2,
                    file_id: Some(1),
                })
            } else {
                Err(io::ErrorKind::NotFound.into())
            }
        }
        fn read(&self, _: &Path) -> io::Result<(Stamp, Vec<u8>)> {
            unreachable!()
        }
    }
    #[test]
    fn exact_output_membership_exclusions_preserve_negative_and_current_policy_proofs() {
        let files = Files(RefCell::new(vec!["source.dm".into()]), RefCell::new(false));
        let generated = GeneratedOutputInputs::new(&files, [PathBuf::from("project/output.rsc")]);
        let capture = RecordingInputs::new(&generated, 0);
        capture.record_search_folder(Path::new("project")).unwrap();
        let snapshot = capture.into_snapshot().unwrap();
        files.0.borrow_mut().push("output.rsc".into());
        assert!(snapshot.restat(&generated).unwrap().unchanged());
        assert!(!snapshot.restat(&files).unwrap().unchanged());
        files.0.borrow_mut().push("new-resource.png".into());
        assert!(!snapshot.restat(&generated).unwrap().unchanged());
        files.0.borrow_mut().pop();
        let mut negative = snapshot.clone();
        negative
            .record_negative(Path::new("project/output.rsc"))
            .unwrap();
        *files.1.borrow_mut() = true;
        assert!(!negative.restat(&generated).unwrap().unchanged());
        let wire = dm_wire::encode(0x5350_0002, &snapshot).unwrap();
        let restored: InputSnapshot =
            dm_wire::decode(0x5350_0002, &wire, dm_wire::MAX_BYTES).unwrap();
        assert_eq!(snapshot, restored);
        assert!(restored.restat(&generated).unwrap().unchanged());
    }
}

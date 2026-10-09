//! Provider-issued nontext receipts use the existing file-input validation authority.
use super::*;
impl<P: SnapshotProvider> RecordingInputs<P> {
    pub(super) fn retained_nontext_impl(
        &self,
        path: &Path,
        previous: Option<&dm_preprocess::RetainedText>,
    ) -> Result<Option<dm_preprocess::RetainedText>, String> {
        #[derive(Clone)]
        struct Receipt {
            path: PathBuf,
            inputs: InputSnapshot,
        }
        let path = canonical_path(path);
        let now = self
            .snapshot
            .lock()
            .map_err(|_| "input capture mutex poisoned")?
            .scanned_ns;
        if let Some(previous) = previous {
            if let Some(receipt) = previous.receipt::<Receipt>().filter(|r| r.path == path) {
                if let Some((_, refreshed)) = receipt
                    .inputs
                    .validate_for_reuse(&self.provider, self.exact_reuse, now)
                    .map_err(|e| e.to_string())?
                {
                    self.snapshot
                        .lock()
                        .map_err(|_| "input capture mutex poisoned")?
                        .merge(&refreshed)
                        .map_err(|e| e.to_string())?;
                    return Ok(Some(previous.reissued(Receipt {
                        path,
                        inputs: refreshed,
                    })));
                }
            }
        }
        let source = self.read_recorded(&path).map_err(|e| e.to_string())?;
        let mut inputs = InputSnapshot::new(now);
        let fact = self
            .snapshot
            .lock()
            .map_err(|_| "input capture mutex poisoned")?
            .files
            .get(&path)
            .cloned()
            .ok_or("nontext input capture missing")?;
        inputs.files.insert(path.clone(), fact);
        Ok(Some(dm_preprocess::RetainedText::issued(
            std::sync::Arc::from(decode_owned_source(source)),
            Receipt { path, inputs },
        )))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use dm_preprocess::SourceProvider;
    use std::cell::Cell;
    use std::sync::Arc;
    struct Files {
        bytes: Vec<u8>,
        stamp: Stamp,
        reads: Cell<usize>,
    }
    impl SnapshotProvider for Files {
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
    #[test]
    fn authenticated_nontext_reuse_refreshes_ledger_and_exact_mode_checks_content() {
        let mut files = Files {
            bytes: b"old".to_vec(),
            stamp: Stamp {
                size: 3,
                modified_ns: 1,
                file_id: Some(9),
            },
            reads: Cell::new(0),
        };
        let path = Path::new("map.dmm");
        let first = RecordingInputs::new(&files, 10_000_000_000)
            .retained_nontext(path, None)
            .unwrap()
            .unwrap();
        assert_eq!(files.reads.get(), 1);
        let second_owner = RecordingInputs::new(&files, 20_000_000_000);
        let second = second_owner
            .retained_nontext(path, Some(&first))
            .unwrap()
            .unwrap();
        assert!(Arc::ptr_eq(first.text(), second.text()));
        assert_eq!(files.reads.get(), 1);
        assert!(second_owner.snapshot().unwrap().contains_file(path));
        drop(second_owner);
        files.bytes = b"new".to_vec(); // Same metadata: exact mode must reject the old receipt.
        let exact = RecordingInputs::new(&files, 30_000_000_000).with_exact_reuse(true);
        let changed = exact
            .retained_nontext(path, Some(&second))
            .unwrap()
            .unwrap();
        assert_eq!(changed.text().as_ref(), "new");
        assert!(!Arc::ptr_eq(first.text(), changed.text()));
        assert_eq!(files.reads.get(), 3); // Digest proof then fresh capture, preserving existing policy.
    }
    #[test]
    fn receipt_cannot_reuse_a_different_path_or_unknown_provider_token() {
        let files = Files {
            bytes: b"text".to_vec(),
            stamp: Stamp {
                size: 4,
                modified_ns: 1,
                file_id: Some(9),
            },
            reads: Cell::new(0),
        };
        let owner = RecordingInputs::new(&files, 10_000_000_000);
        let first = owner
            .retained_nontext(Path::new("one.dmm"), None)
            .unwrap()
            .unwrap();
        owner
            .retained_nontext(Path::new("two.dmm"), Some(&first))
            .unwrap();
        let unknown = dm_preprocess::RetainedText::issued(Arc::from("bad"), ());
        let actual = owner
            .retained_nontext(Path::new("one.dmm"), Some(&unknown))
            .unwrap()
            .unwrap();
        assert_eq!(actual.text().as_ref(), "text");
        assert_eq!(files.reads.get(), 3);
    }
}

//! Source-local lexical owners; every hit revalidates its provider-issued file proof.
use super::*;
use dm_preprocess::regions::prepared_source::PreparedSource;
use std::sync::Arc;
pub struct PreparedInputPayload {
    source: Arc<PreparedSource>,
    inputs: InputSnapshot,
}
struct NoSemanticReads;
impl dm_ir::Resolver for NoSemanticReads {
    fn resolve(&self, query: dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning {
        dm_ir::ResolvedMeaning::Unsupported(query)
    }
}
/// Current source roster only. Store charges are not decoded heap estimates.
pub struct PreparedInputArtifacts {
    values: dm_session::ArtifactStore<PreparedInputPayload>,
}
impl PreparedInputArtifacts {
    pub fn visit_storage(
        &self,
        visit: impl FnMut(dm_session::ArtifactStorageView<'_, PreparedInputPayload>),
    ) {
        self.values.visit_storage(visit);
    }
}
impl PreparedInputPayload {
    pub fn source(&self) -> &Arc<PreparedSource> {
        &self.source
    }
    pub fn inputs(&self) -> &InputSnapshot {
        &self.inputs
    }
}
impl Default for PreparedInputArtifacts {
    fn default() -> Self {
        Self {
            values: dm_session::ArtifactStore::current_revision(),
        }
    }
}
impl<P: SnapshotProvider> RecordingInputs<P> {
    pub fn with_prepared_sources(mut self, owner: Option<Arc<PreparedInputArtifacts>>) -> Self {
        self.prepared = owner;
        self
    }
    /// Paths prepared by the previous request on this retained owner (its
    /// current roster). Offered to the parallel input pass as speculative
    /// candidates so includes nested below the manifest are not prepared one at
    /// a time by the ordered directive pass. Non-UTF-8 keys are skipped; a
    /// missing or changed file is handled exactly like any other candidate.
    pub fn previous_prepared_paths(&self) -> Vec<std::path::PathBuf> {
        let Some(owner) = &self.prepared else {
            return Vec::new();
        };
        let mut paths = Vec::new();
        owner.values.visit_storage(|view| {
            if let dm_session::ArtifactStorageView::Entry { key, .. } = view {
                if let Ok(text) = std::str::from_utf8(key) {
                    paths.push(std::path::PathBuf::from(text));
                }
            }
        });
        paths
    }
    /// Prune only after the caller has completed successful input capture.
    pub fn finish_prepared(&self) -> io::Result<()> {
        if let Some(owner) = &self.prepared {
            let keys = self
                .prepared_keys
                .lock()
                .map_err(|_| invalid("prepared input roster poisoned"))?;
            owner
                .values
                .retain_current_keys(keys.iter().map(AsRef::as_ref));
        }
        Ok(())
    }
    pub(super) fn prepared_impl(&self, path: &Path) -> io::Result<Option<Arc<PreparedSource>>> {
        let Some(owner) = &self.prepared else {
            return Ok(None);
        };
        let path = canonical_path(path);
        let key: Arc<[u8]> = path.as_os_str().as_encoded_bytes().into();
        self.prepared_keys
            .lock()
            .map_err(|_| invalid("prepared input roster poisoned"))?
            .push(Arc::clone(&key));
        let now = self
            .snapshot
            .lock()
            .map_err(|_| invalid("input capture mutex poisoned"))?
            .scanned_ns;
        let mut proof = None;
        let mut error = None;
        let (hit, _) = owner
            .values
            .visit_explained(&key, &NoSemanticReads, &mut |payload| match payload
                .inputs
                .validate_for_reuse(&self.provider, self.exact_reuse, now)
            {
                Ok(Some((_, refreshed))) => {
                    proof = Some(refreshed);
                    true
                }
                Ok(None) => false,
                Err(e) => {
                    error = Some(e);
                    false
                }
            });
        if let Some(error) = error {
            return Err(error);
        }
        if let Some(hit) = hit {
            let refreshed = proof.expect("admitted prepared input proof");
            self.snapshot
                .lock()
                .map_err(|_| invalid("input capture mutex poisoned"))?
                .merge(&refreshed)?;
            let source = Arc::clone(&hit.source);
            owner
                .values
                .insert_with(key, Vec::new(), Vec::new(), 0, || PreparedInputPayload {
                    source: Arc::clone(&source),
                    inputs: refreshed,
                });
            return Ok(Some(source));
        }
        let bytes = {
            let _stage = dm_profile::stage("input_scan.source_read");
            self.read_recorded(&path)?
        };
        let source = {
            let _stage = dm_profile::stage("input_scan.lexical_prepare");
            Arc::new(PreparedSource::from_text(decode_owned_source(bytes).into()))
        };
        let fact = self
            .snapshot
            .lock()
            .map_err(|_| invalid("input capture mutex poisoned"))?
            .files
            .get(&path)
            .cloned()
            .ok_or_else(|| invalid("prepared input capture missing"))?;
        let mut inputs = InputSnapshot::new(now);
        inputs.files.insert(path, fact);
        owner
            .values
            .insert_with(key, Vec::new(), Vec::new(), 0, || PreparedInputPayload {
                source: Arc::clone(&source),
                inputs,
            });
        Ok(Some(source))
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    use dm_preprocess::SourceProvider;
    use std::cell::Cell;
    struct Files {
        bytes: Vec<u8>,
        reads: Cell<usize>,
    }
    impl SnapshotProvider for Files {
        fn stamp(&self, _: &Path) -> io::Result<Stamp> {
            Ok(Stamp {
                size: self.bytes.len() as u64,
                modified_ns: 1,
                file_id: Some(7),
            })
        }
        fn read(&self, path: &Path) -> io::Result<(Stamp, Vec<u8>)> {
            self.reads.set(self.reads.get() + 1);
            Ok((self.stamp(path)?, self.bytes.clone()))
        }
        fn list(&self, _: &Path) -> io::Result<FolderListing> {
            Ok(FolderListing::Missing)
        }
    }
    #[test]
    fn shares_lexical_owner_only_after_current_proof_and_exact_changes_reprepare() {
        let owner = Arc::new(PreparedInputArtifacts::default());
        let mut files = Files {
            bytes: b"/proc/a()\n\treturn 1\n".to_vec(),
            reads: Cell::new(0),
        };
        let path = Path::new("source.dm");
        let first_capture =
            RecordingInputs::new(&files, 10_000_000_000).with_prepared_sources(Some(owner.clone()));
        let first = first_capture.prepared_source(path).unwrap();
        first_capture.finish_prepared().unwrap();
        let report = crate::heap_census::prepared_input_census(&owner);
        assert!(report.unique_known_capacity_bytes > 0);
        assert!(report.owners.iter().any(|owner| owner
            .unknown
            .iter()
            .any(|reason| reason.contains("PreparedLine"))));
        drop(first_capture);
        let second_capture =
            RecordingInputs::new(&files, 20_000_000_000).with_prepared_sources(Some(owner.clone()));
        let second = second_capture.prepared_source(path).unwrap();
        assert!(Arc::ptr_eq(&first, &second));
        assert_eq!(files.reads.get(), 1);
        assert!(second_capture.snapshot().unwrap().contains_file(path));
        drop(second_capture);
        files.bytes = b"/proc/a()\n\treturn 2\n".to_vec();
        let changed = RecordingInputs::new(&files, 30_000_000_000)
            .with_exact_reuse(true)
            .with_prepared_sources(Some(owner));
        assert!(!Arc::ptr_eq(
            &first,
            &changed.prepared_source(path).unwrap()
        ));
        assert_eq!(files.reads.get(), 3);
    }
    #[test]
    fn one_shot_has_no_preparation_owner() {
        let files = Files {
            bytes: b"x".to_vec(),
            reads: Cell::new(0),
        };
        let capture = RecordingInputs::new(&files, 10_000_000_000);
        assert!(capture.prepared_source(Path::new("x.dm")).is_none());
        assert_eq!(files.reads.get(), 0);
    }
}

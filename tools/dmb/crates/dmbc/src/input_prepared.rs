//! Source-local lexical owners; every hit revalidates its provider-issued file proof.
use super::*;
use dm_preprocess::regions::prepared_source::PreparedSource;
use std::sync::Arc;
/// Per-process prepared-input counters (hits, misses and nanoseconds spent validating, reading
/// and preparing), reported on the `native input preparation` progress line.
pub mod counters {
    use std::sync::atomic::{AtomicU64, Ordering};
    pub static HITS: AtomicU64 = AtomicU64::new(0);
    pub static MISSES: AtomicU64 = AtomicU64::new(0);
    pub static CALLED: AtomicU64 = AtomicU64::new(0);
    pub static UNCHANGED_NO: AtomicU64 = AtomicU64::new(0);
    pub static ERRORS: AtomicU64 = AtomicU64::new(0);
    pub static VALIDATE_NS: AtomicU64 = AtomicU64::new(0);
    pub static READ_NS: AtomicU64 = AtomicU64::new(0);
    pub static PREPARE_NS: AtomicU64 = AtomicU64::new(0);
    pub fn take() -> String {
        let n = |c: &AtomicU64| c.swap(0, Ordering::Relaxed);
        format!(
            "prepared inputs: hits={} misses={} called={} unchanged_no={} errors={} validate_cpu={:.3}s read_cpu={:.3}s lexical_cpu={:.3}s",
            n(&HITS),
            n(&MISSES),
            n(&CALLED),
            n(&UNCHANGED_NO),
            n(&ERRORS),
            n(&VALIDATE_NS) as f64 / 1e9,
            n(&READ_NS) as f64 / 1e9,
            n(&PREPARE_NS) as f64 / 1e9
        )
    }
}
pub struct PreparedInputPayload {
    // None means an old/unproven payload, never inferred UTF8 from text.
    acquisition: Option<dm_preprocess::AcquiredSource>,
    source: Arc<PreparedSource>,
    inputs: InputSnapshot,
    original_bytes: Option<dm_resources::SharedBytes>,
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
    pub(crate) fn source_acquisition(&self) -> Option<&dm_preprocess::AcquiredSource> {
        self.acquisition.as_ref()
    }
    pub fn source(&self) -> &Arc<PreparedSource> {
        &self.source
    }
    pub fn exceptional_original_bytes(&self) -> Option<&dm_resources::SharedBytes> {
        self.original_bytes.as_ref()
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
        static NOW: dm_profile::Accumulator = dm_profile::Accumulator::new("prepared.snapshot_now");
        static VISIT: dm_profile::Accumulator =
            dm_profile::Accumulator::new("prepared.visit_validate");
        static MERGE: dm_profile::Accumulator = dm_profile::Accumulator::new("prepared.merge");
        static INSERT: dm_profile::Accumulator = dm_profile::Accumulator::new("prepared.insert");
        let now_timer = NOW.time();
        let now = self
            .snapshot
            .lock()
            .map_err(|_| invalid("input capture mutex poisoned"))?
            .scanned_ns;
        drop(now_timer);
        let mut proof = None;
        let mut error = None;
        let visit_timer = VISIT.time();
        let validate_started = std::time::Instant::now();
        let (hit, _) = owner
            .values
            .visit_explained(&key, &NoSemanticReads, &mut |payload| {
                counters::CALLED.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                match payload
                    .inputs
                    .validate_for_reuse(&self.provider, self.exact_reuse, now)
                {
                    Ok(Some((_, refreshed))) => {
                        proof = Some(refreshed);
                        true
                    }
                    Ok(None) => {
                        counters::UNCHANGED_NO.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                        false
                    }
                    Err(e) => {
                        counters::ERRORS.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                        error = Some(e);
                        false
                    }
                }
            });
        counters::VALIDATE_NS.fetch_add(
            validate_started.elapsed().as_nanos() as u64,
            std::sync::atomic::Ordering::Relaxed,
        );
        drop(visit_timer);
        if let Some(error) = error {
            return Err(error);
        }
        if let Some(hit) = hit {
            counters::HITS.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
            let refreshed = proof.expect("admitted prepared input proof");
            // The structure check is memoized on the proof; doing it here keeps it out of the
            // shared snapshot lock, which every prepared input of the request takes.
            refreshed.check_structure()?;
            let merge_timer = MERGE.time();
            self.snapshot
                .lock()
                .map_err(|_| invalid("input capture mutex poisoned"))?
                .merge(&refreshed)?;
            drop(merge_timer);
            let _insert_timer = INSERT.time();
            let source = Arc::clone(&hit.source);
            let acquisition =
                self.refresh_source_acquisition(&path, &source, hit.acquisition.as_ref())?;
            let original_bytes = hit.original_bytes.clone();
            if let Some(bytes) = &original_bytes {
                self.remember_exceptional_source(&path, bytes.clone())?;
            }
            owner
                .values
                .insert_with(key, Vec::new(), 0, || PreparedInputPayload {
                    source: Arc::clone(&source),
                    acquisition,
                    inputs: refreshed,
                    original_bytes,
                });
            return Ok(Some(source));
        }
        counters::MISSES.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        let read_started = std::time::Instant::now();
        let bytes = {
            let _stage = dm_profile::stage("input_scan.source_read");
            self.read_recorded(&path)?
        };
        counters::READ_NS.fetch_add(
            read_started.elapsed().as_nanos() as u64,
            std::sync::atomic::Ordering::Relaxed,
        );
        let prepare_started = std::time::Instant::now();
        let acquisition = self.acquire_recorded_source(&path, bytes)?;
        let source = {
            let _stage = dm_profile::stage("input_scan.lexical_prepare");
            Arc::clone(acquisition.prepared())
        };
        counters::PREPARE_NS.fetch_add(
            prepare_started.elapsed().as_nanos() as u64,
            std::sync::atomic::Ordering::Relaxed,
        );
        let fact = self
            .snapshot
            .lock()
            .map_err(|_| invalid("input capture mutex poisoned"))?
            .files
            .get(&path)
            .cloned()
            .ok_or_else(|| invalid("prepared input capture missing"))?;
        let original_bytes = self.exceptional_source_bytes(&path)?;
        let mut inputs = InputSnapshot::new(now);
        inputs.files.insert(path, fact);
        owner
            .values
            .insert_with(key, Vec::new(), 0, || PreparedInputPayload {
                source: Arc::clone(&source),
                acquisition: Some(acquisition),
                inputs,
                original_bytes,
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
            .any(|reason| reason.contains("line and directive array"))));
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

impl<P:SnapshotProvider> RecordingInputs<P>{
 pub(super) fn prepare_subject_header<T:std::any::Any+Send+Sync>(&self,root:&Path,text:dm_preprocess::SourceText,receipt:T)->io::Result<dm_preprocess::AcquiredSource>{
  let Some(owner)=&self.prepared else{return Ok(dm_preprocess::AcquiredSource::synthetic_utf8(text,receipt))};
  let mut key=Vec::new();key.try_reserve_exact(64+root.as_os_str().len()).map_err(|_|io::Error::new(io::ErrorKind::OutOfMemory,"analysis header key refused"))?;key.extend_from_slice(b"\xfforiginal-analyze-full-subject-v1\0");key.extend_from_slice(root.as_os_str().as_encoded_bytes());let key:Arc<[u8]>=key.into();
  // Lexical byte cache only: no physical source fact or discovery proof is
  // retained here. The newly issued subject authenticates its current header.
  let inputs=InputSnapshot::new(0);let mut previous=None;
  owner.values.visit_explained(&key,&NoSemanticReads,&mut|payload|{if payload.source.original().as_str()==text.as_str(){previous=payload.acquisition.clone();previous.is_some()}else{false}});
  self.prepared_keys.lock().map_err(|_|invalid("analysis header keys poisoned"))?.push(Arc::clone(&key));
  if let Some(previous)=previous{return Ok(previous.reissued(receipt))}
  let acquisition=dm_preprocess::AcquiredSource::synthetic_utf8(text,receipt);let source=Arc::clone(acquisition.prepared());let retained=acquisition.clone();owner.values.insert_with(key,Vec::new(),0,||PreparedInputPayload{source,acquisition:Some(retained),inputs,original_bytes:None});Ok(acquisition)
 }
}

impl<P:SnapshotProvider> RecordingInputs<P>{
 /// Reuse only lexical bytes proven equal to this newly recorded bounded read.
 /// The current recorder reissues the physical receipt; the old proof is not authority.
 pub(super) fn reuse_current_prepared_original(&self,path:&Path,original:&[u8])->io::Result<Option<dm_preprocess::AcquiredSource>>{
  let Some(owner)=&self.prepared else{return Ok(None)};let key:Arc<[u8]>=canonical_path(path).as_os_str().as_encoded_bytes().into();let mut old=None;
  owner.values.visit_explained(&key,&NoSemanticReads,&mut|payload|{let Some(acquired)=payload.acquisition.as_ref()else{return false};let Ok(raw)=super::recorded_source_original(acquired.lease())else{return false};let bytes=match raw{super::RecordedSourceOriginal::Utf8(text)=>text.as_bytes(),super::RecordedSourceOriginal::Bytes(bytes)=>bytes.as_slice()};if bytes!=original{return false}old=Some(acquired.clone());true});
  let Some(old)=old else{return Ok(None)};self.refresh_source_acquisition(path,old.prepared(),Some(&old))
 }
 pub(super) fn retain_current_prepared_original(&self,path:&Path,acquisition:&dm_preprocess::AcquiredSource)->io::Result<()>{
  let Some(owner)=&self.prepared else{return Ok(())};let path=canonical_path(path);let key:Arc<[u8]>=path.as_os_str().as_encoded_bytes().into();self.prepared_keys.lock().map_err(|_|invalid("prepared original roster poisoned"))?.push(Arc::clone(&key));
  let fact=self.recorded_file_fact(&path)?;let original_bytes=self.exceptional_source_bytes(&path)?;let mut inputs=InputSnapshot::new(0);inputs.files.insert(path,fact);let source=Arc::clone(acquisition.prepared());let acquisition=acquisition.clone();owner.values.insert_with(key,Vec::new(),0,||PreparedInputPayload{source,acquisition:Some(acquisition),inputs,original_bytes});Ok(())
 }
}

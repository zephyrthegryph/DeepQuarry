use crate::input_proof::InputProof;
use crate::prepared_project::{PreparationStats, PreparedProject, PreparedSource};
use dm_host::file_stamp::{capture, FileStamp};
use dm_preprocess::{PreprocessCache, PreprocessedProject, SourceProvider};
use sha2::{Digest, Sha256};
use std::cell::RefCell;
use std::collections::{BTreeMap, BTreeSet};
use std::io;
use std::path::{Path, PathBuf};
use std::sync::Arc;

/// Keep the exact bytes consumed during a pass. The consistency check must
/// compare those bytes, rather than independently re-reading sources that may
/// already have changed while preprocessing was in progress.
fn trace_preparation_stage(stage: &str, started: std::time::Instant) {
    if std::env::var_os("DM_BUILD_TRACE").is_some() {
        eprintln!("DM_BUILD_TRACE preparation {stage}: {:.3}s", started.elapsed().as_secs_f64());
    }
}

#[derive(Default)]
struct RecordingFileSystem<'a> {
    retained: Option<&'a BTreeMap<PathBuf, RetainedSource>>,
    prefetched: Option<&'a BTreeMap<PathBuf, Result<PreparedSource, String>>>,
    unchanged: Option<&'a BTreeSet<PathBuf>>,
    digests: RefCell<BTreeMap<PathBuf, [u8; 32]>>,
    texts: RefCell<BTreeMap<PathBuf, Arc<str>>>,
    stamps: RefCell<BTreeMap<PathBuf, FileStamp>>,
    files_read: std::cell::Cell<usize>,
    bytes_read: std::cell::Cell<usize>,
    reused: std::cell::Cell<usize>,
}

impl SourceProvider for RecordingFileSystem<'_> {
    fn read(&self, path: &Path) -> Result<String, String> {
        self.read_shared(path).map(|text| text.to_string())
    }

    fn read_shared(&self, path: &Path) -> Result<Arc<str>, String> {
        if let Some(text) = self.texts.borrow().get(path) {
            return Ok(Arc::clone(text));
        }
        if let Some(source) = self.prefetched.and_then(|sources| sources.get(path)) {
            let source = source.as_ref().map_err(Clone::clone)?;
            self.texts
                .borrow_mut()
                .insert(path.to_owned(), Arc::clone(&source.text));
            self.digests
                .borrow_mut()
                .insert(path.to_owned(), source.digest);
            if let Some(stamp) = &source.stamp {
                self.stamps
                    .borrow_mut()
                    .insert(path.to_owned(), stamp.clone());
            }
            return Ok(Arc::clone(&source.text));
        }
        if !crate::input_proof::exact_inputs()
            && self.unchanged.is_some_and(|paths| paths.contains(path))
        {
            if let Some(previous) = self.retained.and_then(|sources| sources.get(path)) {
                if let Ok(text) = previous.content() {
                    self.texts
                        .borrow_mut()
                        .insert(path.to_path_buf(), Arc::clone(&text));
                    self.digests
                        .borrow_mut()
                        .insert(path.to_path_buf(), previous.digest);
                    if let Some(stamp) = &previous.stamp {
                        self.stamps
                            .borrow_mut()
                            .insert(path.to_path_buf(), stamp.clone());
                    }
                    self.reused.set(self.reused.get() + 1);
                    return Ok(text);
                }
            }
        }
        // Retain the stamp taken before these exact source bytes were read.
        // Repeated provider reads use the original text and original stamp.
        let source = read_prepared_source(path, dm_work::WorkLimits::configured())?;
        let text = source.text;
        self.files_read.set(self.files_read.get() + 1);
        self.bytes_read.set(self.bytes_read.get() + text.len());
        self.digests
            .borrow_mut()
            .insert(path.to_path_buf(), source.digest);
        self.texts
            .borrow_mut()
            .insert(path.to_path_buf(), text.clone());
        if let Some(stamp) = source.stamp {
            self.stamps.borrow_mut().insert(path.to_path_buf(), stamp);
        }
        Ok(text)
    }

    fn fingerprint_read(&self, path: &Path, source: &str) -> [u8; 32] {
        self.digests
            .borrow()
            .get(path)
            .copied()
            .unwrap_or_else(|| Sha256::digest(source.as_bytes()).into())
    }

    fn fingerprint(&self, path: &Path) -> Result<[u8; 32], String> {
        if let Some(digest) = self.digests.borrow().get(path) {
            return Ok(*digest);
        }
        self.read_shared(path)?;
        Ok(self.digests.borrow()[path])
    }
}

type RetainedSource = PreparedSource;

pub(crate) fn read_prepared_source(
    path: &Path,
    limits: dm_work::WorkLimits,
) -> Result<PreparedSource, String> {
    use std::io::Read;
    let stamp = (!crate::input_proof::exact_inputs())
        .then(|| capture(path))
        .flatten();
    let source = (|| -> io::Result<PreparedSource> {
        let file = std::fs::File::open(path)?;
        let bound = limits.max_active_bytes.saturating_sub(16 * 1024) / 8;
        let mut bytes = Vec::new();
        file.take(bound as u64 + 1).read_to_end(&mut bytes)?;
        if bytes.len() > bound {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "source exceeds work allocation budget",
            ));
        }
        let text: Arc<str> = dm_preprocess::decode_source_bytes(&bytes).into();
        let digest = Sha256::digest(text.as_bytes()).into();
        Ok(PreparedSource {
            content_len: text.len(),
            blob: None,
            blob_offset: 0,
            blob_packed: false,
            blob_published: false,
            inventory_bucket:crate::prepared_persistence::source_bucket(path) as u8,
            text,
            digest,
            stamp,
        })
    })();
    source.map_err(|error| error.to_string())
}

/// One session's bounded expansion cache and exact source snapshot. The caller
/// supplies only paths proven unchanged against the last successful discovery.
/// Unknown journal status must use an empty set or exact strong stamp checks.
pub struct DiscoveryCache {
    path: PathBuf,
    expansions: PreprocessCache,
    sources: BTreeMap<PathBuf, RetainedSource>,
    prepared: Option<Arc<PreparedProject>>,
    prepared_bytes: usize,
    released_context: Option<String>,
    released_proof: Option<InputProof>,
    store: Option<crate::ContentStore>,
    resources: dm_resources::ResourceFingerprintCache,
}

#[derive(Clone, Copy, Debug, Default)]
pub(crate) struct DiscoveryRetentionFootprint {
    pub prepared: usize,
    pub source_index: usize,
    pub expansions: usize,
    pub resources: usize,
    pub released_proof: usize,
    pub cas_proofs: usize,
}

impl DiscoveryCache {
    pub fn load(root: &Path) -> Self {
        Self::load_with_cache_root(root, crate::default_cache_root(root))
    }

    pub fn load_with_cache_root(root: &Path, cache_root: PathBuf) -> Self {
        let path = dm_compiler::preprocess_cache_path(root);
        Self {
            expansions: PreprocessCache::load_incremental(&path),
            path,
            sources: BTreeMap::new(),
            prepared: None,
            prepared_bytes: 0,
            released_context: None,
            released_proof: None,
            resources: dm_resources::ResourceFingerprintCache::open(&cache_root),
            store: crate::ContentStore::new(cache_root).ok(),
        }
    }

    pub fn resident_bytes(&self) -> usize {
        let footprint = self.retention_footprint();
        footprint
            .prepared
            .saturating_add(footprint.source_index)
            .saturating_add(footprint.expansions)
            .saturating_add(footprint.resources)
            .saturating_add(footprint.released_proof)
            .saturating_add(footprint.cas_proofs)
    }

    pub(crate) fn retention_footprint(&self) -> DiscoveryRetentionFootprint {
        DiscoveryRetentionFootprint {
            prepared: self.prepared_bytes,
            source_index: self
                .sources
                .iter()
                .map(|(path, source)| {
                    path.as_os_str().len() * 2
                        + 192
                        + if self.prepared.is_none() {
                            source.text.len()
                        } else {
                            0
                        }
                })
                .sum(),
            expansions: self.expansions.resident_bytes(),
            resources: self.resources.resident_bytes(),
            cas_proofs: self
                .store
                .as_ref()
                .map_or(0, crate::ContentStore::proof_resident_bytes),
            released_proof: self
                .released_proof
                .as_ref()
                .map_or(0, InputProof::resident_bytes)
                + self.released_context.as_ref().map_or(0, String::capacity),
        }
    }

    pub(crate) fn trim_expansions_to(&mut self, limit: usize) -> usize {
        let before = self.expansions.resident_bytes();
        self.expansions.trim_to(limit);
        before.saturating_sub(self.expansions.resident_bytes())
    }

    /// Keep the expansion and dependency index while evicting authored payloads.
    /// A later requested file reads its verified CAS node; missing nodes fall
    /// back to the actual source provider rather than invalidating the graph.
    pub(crate) fn trim_authored_payloads(&mut self) -> usize {
        let before = self.resident_bytes();
        for source in self.sources.values_mut() {
            if source.blob.is_some() {
                source.text = Arc::from("");
            }
        }
        if let Some(prepared) = self.prepared.as_mut() {
            let prepared = Arc::make_mut(prepared);
            for source in Arc::make_mut(&mut prepared.sources).values_mut() {
                if source.blob.is_some() {
                    source.text = Arc::from("");
                }
            }
            self.prepared_bytes = prepared.resident_bytes();
        }
        before.saturating_sub(self.resident_bytes())
    }

    /// Evict decoded expanded text while retaining origins, unit layout,
    /// dependency proofs and disk handles needed for direct body-edit splices.
    pub(crate) fn release_prepared_snapshot(&mut self) -> usize {
        let before=self.resident_bytes();
        if let Some(prepared)=self.prepared.as_mut() {
            let prepared=Arc::make_mut(prepared);Arc::make_mut(&mut prepared.expansion).evict_payloads();
            prepared.compact_metadata();
            prepared.trace_resident_components();
            self.prepared_bytes=prepared.resident_bytes();
        }
        before.saturating_sub(self.resident_bytes())
    }

    /// Detached inputs and expansion frames can be restored from the same CAS
    /// after pool pressure. Resource proof records have their own small bound.
    pub(crate) fn source_resident_bytes(&self) -> usize {
        self.expansions
            .resident_bytes()
            .saturating_add(self.prepared_bytes)
            .saturating_add(
                self.sources
                    .iter()
                    .map(|(path, source)| {
                        // The second map owns its keys/nodes but shares decoded text
                        // with PreparedProject while that snapshot is retained.
                        path.as_os_str().len() * 2
                            + 192
                            + if self.prepared.is_none() {
                                source.text.len()
                            } else {
                                0
                            }
                    })
                    .sum::<usize>(),
            )
            .saturating_add(
                self.released_proof
                    .as_ref()
                    .map_or(0, InputProof::resident_bytes),
            )
            .saturating_add(self.released_context.as_ref().map_or(0, String::capacity))
    }

    pub(crate) fn release_source_frames(&mut self) {
        self.release_prepared_snapshot();
        // Evict decoded payloads, retaining the source dependency index and CAS
        // handles. Memory pressure must not become a whole-project invalidation.
        for source in self.sources.values_mut() {
            if source.blob.as_ref().is_some_and(|path| path.is_file()) {
                source.text = Arc::from("");
            }
        }
        self.expansions.trim_to(0);
    }

    /// One preparation path for CLI builds, retained daemon builds and tools.
    /// Input proofs may avoid reads; content/context identities gate replay.
    pub fn prepare(
        &mut self,
        root: &Path,
        defines: &BTreeMap<String, String>,
    ) -> io::Result<Arc<PreparedProject>> {
        self.prepare_with_previous(root, defines, &BTreeSet::new(), None)
    }

    /// A lazy expanded CAS failure is a rebuildable cache miss. The caller
    /// retries once, then reports infrastructure failure if repair also fails.
    pub fn rebuild_expansion(&mut self,root:&Path,defines:&BTreeMap<String,String>) -> io::Result<Arc<PreparedProject>> {
        let mut damaged=BTreeSet::new();
        if let Some(previous)=self.prepared.take() {
            self.released_context=Some(previous.context.clone());self.released_proof=previous.proof.clone();
            for piece in &previous.expansion.segments {
                if piece.blob.is_some() && piece.content().is_err() {
                    let blob=piece.blob.as_ref().unwrap();
                    match std::fs::remove_file(blob.as_ref()) {Ok(())=>{},Err(error) if error.kind()==io::ErrorKind::NotFound=>{},Err(error)=>return Err(error)}
                    damaged.insert(piece.digest);
                }
            }
        }
        self.prepared_bytes=0;
        let snapshot=self.prepare(root,defines)?;
        if let Some(store)=&self.store {
            for piece in &snapshot.expansion.segments {
                if damaged.contains(&piece.digest) {store.put_rebuildable("prepared-input-chunk-v2",piece.content()?.as_bytes())?;}
            }
        }
        Ok(snapshot)
    }

    pub(crate) fn resource_archive_inputs(&self,requests:&[dm_resources::ResourceRequest])->Option<Arc<dm_resources::ResourceArchiveInputs>> {
        self.resources.archive_snapshot(requests)
    }

    pub(crate) fn fingerprint_resources(
        &mut self,
        requests: &[dm_resources::ResourceRequest],
    ) -> io::Result<([u8; 32], Option<InputProof>)> {
        let fingerprint = self
            .resources
            .fingerprint_requests(requests.iter().cloned())?;
        let proof = self
            .resources
            .verified_stamps(requests)
            .map(InputProof::from_stamps);
        if std::env::var_os("DM_BUILD_TRACE").is_some() {
            let stats = self.resources.stats();
            eprintln!("DM_BUILD_TRACE resource inputs: {} hashes, {} proof hits, {} hashed bytes, {} disk records", stats.files_hashed, stats.proof_hits, stats.bytes_hashed, stats.disk_records);
        }
        Ok((fingerprint, proof))
    }

    pub(crate) fn prepare_with_previous(
        &mut self,
        root: &Path,
        defines: &BTreeMap<String, String>,
        supplied_unchanged: &BTreeSet<PathBuf>,
        previous: Option<&InputProof>,
    ) -> io::Result<Arc<PreparedProject>> {
        let root_path = root.canonicalize()?;
        let root = root_path.as_path();
        let context = format!(
            "{:x}",
            Sha256::digest(
                serde_json::to_vec(&(
                    "prepared-project-v1",
                    crate::BUILD_FINGERPRINT,
                    root,
                    defines
                ))
                .map_err(io::Error::other)?
            )
        );
        let mut disk_restored = false;
        if self.released_context.as_deref() != Some(context.as_str())
            && self
                .prepared
                .as_ref()
                .is_none_or(|snapshot| snapshot.context != context)
        {
            if let Some(restored) = self.store.as_ref().and_then(|store| {
                crate::prepared_persistence::load(store, &context)
                    .ok()
                    .flatten()
            }) {
                disk_restored = true;
                self.sources = (*restored.sources).clone();
                self.prepared_bytes = restored.resident_bytes();
                self.prepared = Some(Arc::new(restored));
                self.released_context = None;
                self.released_proof = None;
            }
        }
        // Observe source stamps once. A failed whole-snapshot check followed
        // by unchanged_paths used to open the entire source set twice per edit
        // on filesystems where the journal is unavailable.
        let observed_unchanged = (!supplied_unchanged.is_empty())
            .then(|| supplied_unchanged.clone())
            .or_else(|| {
                self.prepared
                    .as_ref()
                    .filter(|snapshot| snapshot.context == context)
                    .and_then(|snapshot| snapshot.proof.as_ref())
                    .filter(|_| !crate::input_proof::exact_inputs())
                    .map(InputProof::unchanged_paths)
            });
        if let Some(snapshot) = self.prepared.as_ref().filter(|snapshot| {
            snapshot.context == context
                && observed_unchanged.as_ref().map_or_else(
                    || snapshot.current(),
                    |unchanged| {
                        snapshot.sources.keys().all(|path| unchanged.contains(path))
                            && snapshot
                                .project
                                .dependencies
                                .iter()
                                .filter(|path| !snapshot.sources.contains_key(*path))
                                .all(|path| !path.exists())
                    },
                )
        }) {
            let snapshot = Arc::new(PreparedProject {
                stats: PreparationStats {
                    retained_hit: !disk_restored,
                    disk_restored,
                    ..Default::default()
                },
                changes: Default::default(),
                ..snapshot.as_ref().clone()
            });
            self.prepared = Some(Arc::clone(&snapshot));
            return Ok(snapshot);
        }
        let old = self.prepared.clone();
        let released_proof = self.released_proof.clone();
        let previous = previous
            .or_else(|| old.as_ref().and_then(|snapshot| snapshot.proof.as_ref()))
            .or(released_proof.as_ref());
        let mut unchanged = observed_unchanged.unwrap_or_else(|| {
            previous
                .map(InputProof::unchanged_paths)
                .unwrap_or_default()
        });
        unchanged.extend(supplied_unchanged.iter().cloned());
        let misses = self.expansions.misses;
        let splice_started = std::time::Instant::now();
        let spliced = old
            .as_ref()
            .filter(|snapshot| snapshot.context == context)
            .and_then(|snapshot| try_splice_sources(snapshot, &unchanged).ok().flatten());
        trace_preparation_stage("source splice", splice_started);
        let discovery_started = std::time::Instant::now();
        let (discovered, expansion) = if let Some((discovered, expansion)) = spliced {
            (discovered, Some(expansion))
        } else {
            let (project, sources, proof, digests, stamps, stats, pieces) = discover_with_retained(
                root,
                defines,
                &mut self.expansions,
                &self.sources,
                &unchanged,
                previous,
            )?;
            (
                (project, sources, proof, digests, stamps, stats),
                Some(crate::prepared_project::SegmentedExpansion::from_pieces(
                    pieces,
                )),
            )
        };
        trace_preparation_stage("discovery and expansion pieces", discovery_started);
        let metadata_started = std::time::Instant::now();
        let (mut project, sources, proof, digests, stamps, mut stats) = discovered;
        project.compact_origins();
        let expansion = Arc::new(expansion.unwrap_or_else(|| {
            crate::prepared_project::SegmentedExpansion::from_text(&project.text)
        }));
        let sources: BTreeMap<_, _> = sources
            .into_iter()
            .map(|(path, text)| {
                let source = old
                    .as_ref()
                    .and_then(|old| old.sources.get(&path))
                    .filter(|source| source.digest == digests[&path])
                    .cloned()
                    .unwrap_or_else(|| PreparedSource {
                        content_len: text.len(),
                        blob: None,
                        blob_offset: 0,
                        blob_packed: false,
                        blob_published: false,
                        inventory_bucket:crate::prepared_persistence::source_bucket(&path) as u8,
                        text,
                        digest: digests[&path],
                        stamp: stamps.get(&path).cloned(),
                    });
                let mut source = source;
                source.stamp = stamps.get(&path).cloned();
                if source.blob.is_none() {
                    if let Some(store) = &self.store {
                        let digest = source
                            .digest
                            .iter()
                            .map(|byte| format!("{byte:02x}"))
                            .collect::<String>();
                        source.blob = Some(
                            store
                                .root
                                .join("prepared-source-v3")
                                .join(&digest[..2])
                                .join(digest),
                        );
                    }
                }
                (path, source)
            })
            .collect();
        let mut changes =
            crate::prepared_project::changes(old.as_deref(), &project, &sources, &context);
        if old.is_none() && self.released_context.is_some() {
            changes.configuration_changed = self.released_context.as_ref() != Some(&context);
            changes.added_sources.clear();
            changes.changed_sources.clear();
            for (path, source) in &sources {
                match self.sources.get(path) {
                    None => {
                        changes.added_sources.insert(path.clone());
                    }
                    Some(previous) if previous.digest != source.digest => {
                        changes.changed_sources.insert(path.clone());
                    }
                    _ => {}
                }
            }
            changes.removed_sources.extend(
                self.sources
                    .keys()
                    .filter(|path| !sources.contains_key(*path))
                    .cloned(),
            );
            // Expanded units conservatively remain changed: their old origins
            // and span/digest summary were intentionally evicted with the pack.
        }
        let project_digest = crate::prepared_project::project_digest(root, &sources);
        let mut expanded_hash = Sha256::new();
        for piece in &expansion.segments {
            expanded_hash.update((piece.content_len as u64).to_le_bytes());
            expanded_hash.update(piece.digest);
        }
        let expanded_digest = project.semantic_identity.as_ref().map_or_else(
            ||format!("{:x}",expanded_hash.finalize()),
            |identity|identity.root.iter().map(|byte|format!("{byte:02x}")).collect());
        let revision = format!(
            "{:x}",
            Sha256::digest(format!("{context}:{project_digest}"))
        );
        stats.disk_restored = disk_restored;
        trace_preparation_stage("origins sources changes identity", metadata_started);
        let macros_started = std::time::Instant::now();
        let mut macro_names = if let Some(old) = &old {
            // The namespace is deliberately conservative across generations.
            // Previously scanned unchanged files contribute through old names;
            // inspect only added/changed authored content for new definitions.
            crate::prepared_project::macro_namespace_sources(&project, sources.iter()
                .filter(|(path, source)| old.sources.get(*path).is_none_or(|before| before.digest != source.digest))
                .map(|(_, source)| source))
        } else {
            crate::prepared_project::macro_namespace(&project, &sources)
        };
        if let Some(old) = &old {
            macro_names.extend(old.macro_names.iter().cloned());
        }
        macro_names.extend(defines.keys().cloned());
        let macro_names = Arc::new(macro_names);
        trace_preparation_stage("macro namespace", macros_started);
        let source_inventory=old.as_ref().and_then(|old|old.source_inventory.as_ref().map(|inventory|Arc::new(inventory.updated(&old.sources,&sources))));
        let mut snapshot = Arc::new(PreparedProject {
            source_inventory,
            project: Arc::new(project),
            macro_names,
            expansion,
            sources: Arc::new(sources),
            project_digest,
            expanded_digest,
            revision,
            changes,
            stats,
            context,
            proof,
        });
        let persistence_started = std::time::Instant::now();
        if self.expansions.misses != misses {
            let _ = self.expansions.save_incremental(&self.path);
        }
        if let Some(store) = &self.store {
            match crate::prepared_persistence::save(store,&snapshot) {
                Ok(published)=>{
                    let snapshot=Arc::make_mut(&mut snapshot);
                    snapshot.source_inventory=Some(Arc::new(published.inventory));
                    let backings=published.backings;
                    Arc::make_mut(&mut snapshot.expansion).attach_backings(&store.root);
                    for source in Arc::make_mut(&mut snapshot.sources).values_mut() {
                        if let Some(backing)=backings.get(&source.digest) {
                            source.blob=Some(store.packed_blob_path("prepared-source-v3",backing));
                            source.blob_offset=backing.start;
                            source.blob_packed=backing.pack.is_some();
                            source.blob_published=true;
                        }
                    }
                },
                Err(error)=>if std::env::var_os("DM_BUILD_TRACE").is_some() {eprintln!("DM_BUILD_TRACE prepared persistence skipped: {error}");},
            }
        }
        trace_preparation_stage("prepared and preprocess persistence", persistence_started);
        self.sources = (*snapshot.sources).clone();
        self.released_context = None;
        self.released_proof = None;
        // Account shared source texts once, then budget expansions alongside
        // the detached current snapshot rather than keeping three source copies.
        let prepared_bytes = snapshot.resident_bytes();
        self.expansions.trim_to(
            (224usize * 1024 * 1024)
                .saturating_sub(prepared_bytes)
                .saturating_sub(self.resources.resident_bytes()),
        );
        self.prepared = Some(Arc::clone(&snapshot));
        if prepared_bytes>224*1024*1024 {self.release_prepared_snapshot();}
        self.prepared_bytes = if self.prepared.is_some() {
            self.prepared.as_ref().map_or(prepared_bytes,|prepared|prepared.resident_bytes())
        } else {
            0
        };
        if self.prepared.is_none() {
            self.released_context = Some(snapshot.context.clone());
            self.released_proof = snapshot.proof.clone();
        }
        Ok(snapshot)
    }

    #[cfg(test)]
    pub(crate) fn discover(
        &mut self,
        root: &Path,
        defines: &BTreeMap<String, String>,
        unchanged: &BTreeSet<PathBuf>,
    ) -> io::Result<(
        PreprocessedProject,
        BTreeMap<PathBuf, String>,
        Option<InputProof>,
    )> {
        self.discover_with_previous(root, defines, unchanged, None)
    }

    #[cfg(test)]
    pub(crate) fn discover_with_previous(
        &mut self,
        root: &Path,
        defines: &BTreeMap<String, String>,
        unchanged: &BTreeSet<PathBuf>,
        previous: Option<&InputProof>,
    ) -> io::Result<(
        PreprocessedProject,
        BTreeMap<PathBuf, String>,
        Option<InputProof>,
    )> {
        let snapshot = self.prepare_with_previous(root, defines, unchanged, previous)?;
        Ok((
            (*snapshot.project).clone(),
            snapshot
                .sources
                .iter()
                .map(|(path, source)| (path.clone(), source.text.to_string()))
                .collect(),
            snapshot.proof.clone(),
        ))
    }
}

#[cfg(test)]
pub(crate) fn discover_consistent_project(
    root: &Path,
    defines: &BTreeMap<String, String>,
) -> io::Result<(PreprocessedProject, BTreeMap<PathBuf, String>)> {
    discover_consistent_project_with_proof(root, defines)
        .map(|(project, sources, _)| (project, sources))
}

#[cfg(test)]
pub(crate) fn discover_consistent_project_with_proof(
    root: &Path,
    defines: &BTreeMap<String, String>,
) -> io::Result<(
    PreprocessedProject,
    BTreeMap<PathBuf, String>,
    Option<InputProof>,
)> {
    let cache_path = dm_compiler::preprocess_cache_path(root);
    let tracing = std::env::var_os("DM_BUILD_TRACE").is_some();
    let start = std::time::Instant::now();
    let mut cache = PreprocessCache::load_incremental(&cache_path);
    if tracing {
        eprintln!(
            "DM_BUILD_TRACE preprocess cache load {:.3}s: {} bytes resident",
            start.elapsed().as_secs_f64(),
            cache.resident_bytes()
        );
    }
    let replay_start = std::time::Instant::now();
    let result = discover_with_cache_with_proof(root, defines, &mut cache)?;
    if tracing {
        eprintln!(
            "DM_BUILD_TRACE preprocess replay/verify {:.3}s: {} hits, {} misses, {} bytes resident",
            replay_start.elapsed().as_secs_f64(),
            cache.hits,
            cache.misses,
            cache.resident_bytes()
        );
    }
    if cache.misses > 0 {
        // The source snapshot is already verified. Saved entries are keyed by
        // exact source text and incoming macro state, so concurrent writers
        // can safely publish either valid generation of this bounded cache.
        let save_start = std::time::Instant::now();
        let result = cache.save_incremental(&cache_path);
        if tracing {
            eprintln!(
                "DM_BUILD_TRACE preprocess cache save {:.3}s: {}",
                save_start.elapsed().as_secs_f64(),
                if result.is_ok() { "saved" } else { "failed" }
            );
        }
    }
    Ok(result)
}

#[cfg(test)]
fn discover_with_cache(
    root: &Path,
    defines: &BTreeMap<String, String>,
    cache: &mut PreprocessCache,
) -> io::Result<(PreprocessedProject, BTreeMap<PathBuf, String>)> {
    discover_with_cache_with_proof(root, defines, cache)
        .map(|(project, sources, _)| (project, sources))
}

#[cfg(test)]
fn discover_with_cache_with_proof(
    root: &Path,
    defines: &BTreeMap<String, String>,
    cache: &mut PreprocessCache,
) -> io::Result<(
    PreprocessedProject,
    BTreeMap<PathBuf, String>,
    Option<InputProof>,
)> {
    discover_with_retained(
        root,
        defines,
        cache,
        &BTreeMap::new(),
        &BTreeSet::new(),
        None,
    )
    .and_then(|(mut project, sources, proof, _, _, _, pieces)| {
        project.text = dm_syntax::SegmentedSource::new(pieces).try_materialize().map_err(io::Error::other)?;
        Ok((
            project,
            sources
                .into_iter()
                .map(|(path, text)| (path, text.to_string()))
                .collect(),
            proof,
        ))
    })
}

type DiscoveredSources = (
    PreprocessedProject,
    BTreeMap<PathBuf, Arc<str>>,
    Option<InputProof>,
    BTreeMap<PathBuf, [u8; 32]>,
    BTreeMap<PathBuf, FileStamp>,
    PreparationStats,
);

/// Source deltas enter the same detached revision contract as full preprocessing.
/// The splice path never blesses a caller's unchanged claim: a final strong
/// proof must validate every source and the missing-include namespace.
fn try_splice_sources(
    previous: &PreparedProject,
    unchanged: &BTreeSet<PathBuf>,
) -> io::Result<
    Option<(
        DiscoveredSources,
        crate::prepared_project::SegmentedExpansion,
    )>,
> {
    if crate::input_proof::exact_inputs() || previous.proof.is_none() {
        return Ok(None);
    }
    let dirty: Vec<_> = previous
        .sources
        .keys()
        .filter(|path| !unchanged.contains(*path))
        .cloned()
        .collect();
    if dirty.is_empty() || dirty.len() > 32 {
        return Ok(None);
    }
    let limits = dm_work::WorkLimits::configured();
    let previous_sources = previous.sources.as_ref();
    let read = dm_work::map_ordered(
        &dirty,
        limits,
        |path| {
            previous_sources.get(path).map_or(16 * 1024, |source| {
                source
                    .text
                    .len()
                    .saturating_mul(8)
                    .saturating_add(16 * 1024)
            })
        },
        |path| read_prepared_source(path, limits),
    )
    .map_err(|error| io::Error::other(format!("source splice work limits: {error:?}")))?;
    let mut sources = previous.sources.as_ref().clone();
    let mut changed = BTreeMap::new();
    let mut bytes = 0;
    for (path, source) in dirty.iter().zip(read) {
        let Ok(source) = source else {
            return Ok(None);
        };
        bytes += source.text.len();
        let before = &sources[path];
        if before.digest != source.digest {
            changed.insert(
                path.clone(),
                (
                    match before.content() {
                        Ok(text) => text,
                        Err(_) => return Ok(None),
                    },
                    Arc::clone(&source.text),
                ),
            );
        }
        sources.insert(path.clone(), source);
    }
    let Some((project, pieces)) = crate::prepared_project::splice_source_edits(
        &previous.project,
        &previous.expansion,
        &changed,
        &previous.macro_names,
    ) else {
        return Ok(None);
    };
    let Some(stamps) = sources
        .iter()
        .map(|(path, source)| source.stamp.clone().map(|stamp| (path.clone(), stamp)))
        .collect::<Option<BTreeMap<_, _>>>()
    else {
        return Ok(None);
    };
    let mut proof = InputProof::from_stamps(stamps.clone());
    proof.inherit_unchanged(previous.proof.as_ref().unwrap());
    let missing: Vec<_> = project
        .dependencies
        .iter()
        .filter(|path| !sources.contains_key(*path))
        .cloned()
        .collect();
    proof.enable_namespace_journal(&missing);
    if !proof.current() || missing.iter().any(|path| path.exists()) {
        return Ok(None);
    }
    let digests = sources
        .iter()
        .map(|(path, source)| (path.clone(), source.digest))
        .collect();
    let texts = sources
        .into_iter()
        .map(|(path, source)| (path, source.text))
        .collect();
    let stats = PreparationStats {
        source_files_read: dirty.len(),
        source_bytes_read: bytes,
        sources_reused: previous.sources.len().saturating_sub(dirty.len()),
        ..Default::default()
    };
    Ok(Some((
        (project, texts, Some(proof), digests, stamps, stats),
        pieces,
    )))
}

fn discover_with_retained(
    root: &Path,
    defines: &BTreeMap<String, String>,
    cache: &mut PreprocessCache,
    retained: &BTreeMap<PathBuf, RetainedSource>,
    unchanged: &BTreeSet<PathBuf>,
    previous: Option<&InputProof>,
) -> io::Result<(
    PreprocessedProject,
    BTreeMap<PathBuf, Arc<str>>,
    Option<InputProof>,
    BTreeMap<PathBuf, [u8; 32]>,
    BTreeMap<PathBuf, FileStamp>,
    PreparationStats,
    Vec<Arc<str>>,
)> {
    for attempt in 0..3 {
        let mut paths: BTreeSet<_> = retained
            .keys()
            .filter(|path| attempt != 0 || !unchanged.contains(*path))
            .cloned()
            .collect();
        paths.insert(root.to_owned());
        if attempt == 0 && unchanged.contains(root) {
            paths.remove(root);
        }
        let limits = dm_work::WorkLimits::configured();
        let jobs: Vec<_> = paths
            .into_iter()
            .map(|path| {
                let bytes = std::fs::metadata(&path).ok().map_or(16 * 1024, |metadata| {
                    usize::try_from(metadata.len())
                        .unwrap_or(usize::MAX)
                        .saturating_mul(8)
                        .saturating_add(16 * 1024)
                });
                (path, bytes)
            })
            .collect();
        let read_started = std::time::Instant::now();
        let prefetched = dm_work::map_ordered(
            &jobs,
            limits,
            |(_, bytes)| *bytes,
            |(path, _)| read_prepared_source(path, limits),
        )
        .map_err(|error| match error {
            dm_work::WorkError::Panic { job, message } => panic!("source worker {job}: {message}"),
            other => io::Error::new(
                io::ErrorKind::InvalidData,
                format!("source work limits: {other:?}"),
            ),
        })?;
        let prefetched: BTreeMap<_, _> = jobs
            .into_iter()
            .map(|(path, _)| path)
            .zip(prefetched)
            .collect();
        let prefetched_files = prefetched.values().filter(|result| result.is_ok()).count();
        let prefetched_bytes = prefetched
            .values()
            .filter_map(|result| result.as_ref().ok())
            .map(|source| source.text.len())
            .sum();
        // On a consistency retry reread everything; supplied unchanged paths
        // describe the caller's initial observation, not later concurrent edits.
        let provider = RecordingFileSystem {
            retained: (attempt == 0).then_some(retained),
            prefetched: Some(&prefetched),
            unchanged: (attempt == 0).then_some(unchanged),
            files_read: std::cell::Cell::new(prefetched_files),
            bytes_read: std::cell::Cell::new(prefetched_bytes),
            ..Default::default()
        };
        trace_preparation_stage("authored prefetch", read_started);
        let preprocess_started = std::time::Instant::now();
        let (discovery, pieces) =
            dm_preprocess::preprocess_project_cached_segmented(root, &provider, defines, cache);
        trace_preparation_stage("ordered preprocessing", preprocess_started);
        let proof_started = std::time::Instant::now();
        let stats = PreparationStats {
            preprocessed: true,
            source_files_read: provider.files_read.get(),
            source_bytes_read: provider.bytes_read.get(),
            sources_reused: provider.reused.get(),
            ..Default::default()
        };
        let sources = provider.texts.into_inner();
        let stamps = provider.stamps.into_inner();
        let digests = provider.digests.into_inner();
        let mut proof =
            (stamps.len() == sources.len()).then(|| InputProof::from_stamps(stamps.clone()));
        if attempt == 0 {
            if let (Some(proof), Some(previous)) = (&mut proof, previous) {
                proof.inherit_unchanged(previous);
            }
        }
        let unchanged = if let Some(proof) = &proof {
            proof.current()
        } else {
            dm_work::map_ordered(
                &sources.iter().collect::<Vec<_>>(),
                limits,
                |(_, text)| text.len().saturating_mul(8).saturating_add(16 * 1024),
                |(path, _)| {
                    read_prepared_source(path, limits)
                        .is_ok_and(|source| source.digest == digests[*path])
                },
            )
            .is_ok_and(|results| results.into_iter().all(|current| current))
        };
        let missing_still_missing = discovery
            .dependencies
            .iter()
            .filter(|path| !sources.contains_key(*path))
            .all(|path| !path.exists());
        if unchanged && missing_still_missing {
            if let Some(proof) = &mut proof {
                let missing: Vec<_> = discovery
                    .dependencies
                    .iter()
                    .filter(|path| !sources.contains_key(*path))
                    .cloned()
                    .collect();
                proof.enable_namespace_journal(&missing);
                if !proof.current() || missing.iter().any(|path| path.exists()) {
                    continue;
                }
            }
            trace_preparation_stage("input proof establishment", proof_started);
            return Ok((discovery, sources, proof, digests, stamps, stats, pieces));
        }
    }
    Err(io::Error::other(
        "project sources changed during discovery; retry check",
    ))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::sync::atomic::{AtomicU64, Ordering};

    static TEST_SEQUENCE: AtomicU64 = AtomicU64::new(0);

    struct Fixture(PathBuf);

    impl Fixture {
        fn new() -> Self {
            let path = std::env::temp_dir().join(format!(
                "dm-discovery-{}-{}",
                std::process::id(),
                TEST_SEQUENCE.fetch_add(1, Ordering::Relaxed)
            ));
            fs::create_dir_all(&path).unwrap();
            Self(path.canonicalize().unwrap())
        }

        fn write(&self, path: &str, text: &str) {
            let path = self.0.join(path);
            if let Some(parent) = path.parent() {
                fs::create_dir_all(parent).unwrap();
            }
            fs::write(path, text).unwrap();
        }

        fn project(&self) -> PathBuf {
            self.0.join("project.dme")
        }
    }

    impl Drop for Fixture {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    #[test]
    fn prepared_snapshot_reuses_exact_sources_and_restores_origins_on_restart() {
        let fixture = Fixture::new();
        fixture.write("project.dme", "#include \"a.dm\"\n#include \"b.dm\"\n");
        fixture.write("a.dm", "/proc/a()\n    return 1\n");
        fixture.write("b.dm", "/proc/b()\n    return 2\n");
        let root = fixture.project();
        let cache_root = fixture.0.join("cache");
        let mut cache = DiscoveryCache::load_with_cache_root(&root, cache_root.clone());
        let first = cache.prepare(&root, &BTreeMap::new()).unwrap();
        let unchanged = cache.prepare(&root, &BTreeMap::new()).unwrap();
        assert!(unchanged.stats.retained_hit);
        assert!(!unchanged.stats.preprocessed);
        assert!(Arc::ptr_eq(&first.project, &unchanged.project));
        assert!(Arc::ptr_eq(&first.sources, &unchanged.sources));
        let mut restarted = DiscoveryCache::load_with_cache_root(&root, cache_root);
        let restored = restarted.prepare(&root, &BTreeMap::new()).unwrap();
        assert!(restored.stats.disk_restored);
        assert!(!restored.stats.preprocessed);
        assert_eq!(restored.project.as_ref(), first.project.as_ref());
        assert_eq!(restored.project_digest, first.project_digest);
        assert_eq!(restored.revision, first.revision);
        assert_eq!(restored.project.origin_get(1).unwrap().source_line, 2);
        assert_eq!(
            restored.project.origin_get(1).unwrap().path.as_ref(),
            &fixture.0.join("a.dm")
        );
    }

    #[test]
    fn expanded_snapshot_eviction_keeps_raw_source_proofs_for_one_file_edits() {
        let fixture = Fixture::new();
        fixture.write("project.dme", "#include \"a.dm\"\n#include \"b.dm\"\n");
        fixture.write("a.dm", "/proc/a()\n    return 1\n");
        fixture.write("b.dm", "/proc/b()\n    return 2\n");
        let mut cache =
            DiscoveryCache::load_with_cache_root(&fixture.project(), fixture.0.join("cache"));
        let original = cache.prepare(&fixture.project(), &BTreeMap::new()).unwrap();
        assert!(cache.release_prepared_snapshot() > 0);
        fixture.write("a.dm", "/proc/a()\n    return 30\n");
        let changed = cache.prepare(&fixture.project(), &BTreeMap::new()).unwrap();
        assert!(!changed.stats.disk_restored);
        assert_eq!(changed.stats.source_files_read, 1);
        assert!(changed.changes.added_sources.is_empty());
        assert_eq!(
            changed.changes.changed_sources,
            [fixture.0.join("a.dm")].into()
        );
        assert!(Arc::ptr_eq(
            &original.sources[&fixture.0.join("b.dm")].text,
            &changed.sources[&fixture.0.join("b.dm")].text
        ));
        let fresh = dm_preprocess::preprocess_project(
            &fixture.project(),
            &dm_preprocess::FileSystem,
            &BTreeMap::new(),
        );
        assert_eq!(changed.project.as_ref(), &fresh);
    }

    #[test]
    fn prepared_body_edit_reads_one_source_and_signature_uses_shared_frontend() {
        let fixture = Fixture::new();
        fixture.write("project.dme", "#include \"a.dm\"\n#include \"b.dm\"\n");
        fixture.write("a.dm", "/proc/a()\n    return 1\n");
        fixture.write("b.dm", "/proc/b()\n    return 2\n");
        let root = fixture.project();
        let mut cache = DiscoveryCache::load_with_cache_root(&root, fixture.0.join("cache"));
        let first = cache.prepare(&root, &BTreeMap::new()).unwrap();
        let mut frontend = dm_compiler::frontend::OutlineSession::default();
        let old_abi = frontend.update(&first.project).unwrap().abi_digest;
        fixture.write("a.dm", "/proc/a()\n    return 30\n");
        let edited = cache.prepare(&root, &BTreeMap::new()).unwrap();
        assert_eq!(edited.stats.source_files_read, 1);
        assert_eq!(
            edited.changes.changed_sources,
            [fixture.0.join("a.dm")].into()
        );
        assert!(Arc::ptr_eq(
            &first.sources[&fixture.0.join("b.dm")].text,
            &edited.sources[&fixture.0.join("b.dm")].text
        ));
        assert_eq!(
            frontend.update(&edited.project).unwrap().abi_digest,
            old_abi
        );
        let cold =
            dm_preprocess::preprocess_project(&root, &dm_preprocess::FileSystem, &BTreeMap::new());
        assert_eq!(edited.project.as_ref(), &cold);
        fixture.write("a.dm", "/proc/a(argument = 7)\n    return argument\n");
        let signature = cache.prepare(&root, &BTreeMap::new()).unwrap();
        assert_ne!(
            frontend.update(&signature.project).unwrap().abi_digest,
            old_abi
        );
    }

    #[test]
    fn prepared_missing_include_and_configuration_changes_invalidate_snapshot() {
        let fixture = Fixture::new();
        fixture.write("project.dme", "#include \"missing.dm\"\n");
        let root = fixture.project();
        let mut cache = DiscoveryCache::load_with_cache_root(&root, fixture.0.join("cache"));
        let missing = cache.prepare(&root, &BTreeMap::new()).unwrap();
        assert!(!missing.project.diagnostics.is_empty());
        fixture.write("missing.dm", "/proc/value()\n    return ANSWER\n");
        assert!(!missing.current());
        let defines = [("ANSWER".into(), "17".into())].into();
        let arrived = cache.prepare(&root, &defines).unwrap();
        assert!(arrived.project.diagnostics.is_empty());
        assert!(arrived.expansion.materialize().unwrap().contains("return 17"));
        assert!(arrived.changes.configuration_changed);
        assert!(arrived
            .changes
            .added_sources
            .contains(&fixture.0.join("missing.dm")));
        let changed = cache
            .prepare(&root, &[("ANSWER".into(), "18".into())].into())
            .unwrap();
        assert!(changed.expansion.materialize().unwrap().contains("return 18"));
        assert!(changed.changes.configuration_changed);
        assert_ne!(changed.revision, arrived.revision);
    }

    #[test]
    fn corrupted_prepared_pack_is_a_miss_and_source_proof_survives_preserved_mtime() {
        let fixture = Fixture::new();
        fixture.write("project.dme", "#include \"a.dm\"\n");
        fixture.write("a.dm", "/proc/a()\n    return 1\n");
        let root = fixture.project();
        let cache_root = fixture.0.join("cache");
        let mut cache = DiscoveryCache::load_with_cache_root(&root, cache_root.clone());
        cache.prepare(&root, &BTreeMap::new()).unwrap();
        let namespace = cache_root.join("prepared-input-pack-v1");
        let directory = fs::read_dir(namespace)
            .unwrap()
            .next()
            .unwrap()
            .unwrap()
            .path();
        let pack = fs::read_dir(directory)
            .unwrap()
            .next()
            .unwrap()
            .unwrap()
            .path();
        fs::write(pack, "damaged").unwrap();
        let time = fs::metadata(fixture.0.join("a.dm"))
            .unwrap()
            .modified()
            .unwrap();
        fixture.write("a.dm", "/proc/a()\n    return 2\n");
        fs::File::options()
            .write(true)
            .open(fixture.0.join("a.dm"))
            .unwrap()
            .set_times(fs::FileTimes::new().set_modified(time))
            .unwrap();
        let mut restarted = DiscoveryCache::load_with_cache_root(&root, cache_root);
        let restored = restarted.prepare(&root, &BTreeMap::new()).unwrap();
        assert!(!restored.stats.disk_restored);
        assert!(restored.stats.preprocessed);
        assert!(restored.expansion.materialize().unwrap().contains("return 2"));
    }

    #[test]
    fn recording_provider_keeps_stamp_for_original_bytes() {
        let fixture = Fixture::new();
        fixture.write("leaf.dm", "/proc/value() return 1\n");
        let path = fixture.0.join("leaf.dm");
        let provider = RecordingFileSystem::default();
        let original = provider.read(&path).unwrap();
        let time = fs::metadata(&path).unwrap().modified().unwrap();
        fixture.write("leaf.dm", "/proc/value() return 2\n");
        fs::File::options()
            .write(true)
            .open(&path)
            .unwrap()
            .set_times(fs::FileTimes::new().set_modified(time))
            .unwrap();
        assert_eq!(provider.read(&path).unwrap(), original);
        let proof = InputProof::from_stamps(provider.stamps.into_inner());
        assert!(
            !proof.current(),
            "a cached provider read must not bless newer file metadata"
        );
    }

    #[test]
    fn restart_reuses_leaf_cache_and_macro_edits_invalidate_it() {
        let fixture = Fixture::new();
        fixture.write("project.dme", "#define ANSWER 17\n#include \"leaf.dm\"\n");
        fixture.write("leaf.dm", "/proc/answer()\n    return ANSWER\n");
        let root = fixture.project();
        let defines = BTreeMap::new();
        let (first, sources) = discover_consistent_project(&root, &defines).unwrap();
        assert!(first.text.contains("return 17"));
        assert_eq!(sources.len(), 2);
        let path = dm_compiler::preprocess_cache_path(&root);
        assert!(path.with_extension("index.json").is_file());

        let mut restarted = PreprocessCache::load_incremental(&path);
        let (second, _) = discover_with_cache(&root, &defines, &mut restarted).unwrap();
        assert_eq!(second.text, first.text);
        assert!(restarted.hits > 0);
        assert_eq!(restarted.misses, 0);

        fixture.write("project.dme", "#define ANSWER 18\n#include \"leaf.dm\"\n");
        let (third, _) = discover_with_cache(&root, &defines, &mut restarted).unwrap();
        assert!(third.text.contains("return 18"));
        assert!(restarted.misses > 0);
    }

    #[test]
    fn retained_discovery_reuses_original_sources_and_retries_stale_seed() {
        let fixture = Fixture::new();
        fixture.write("project.dme", "#include \"a.dm\"\n#include \"b.dm\"\n");
        fixture.write("a.dm", "/proc/a()\n return 1\n");
        fixture.write("b.dm", "/proc/b()\n return 2\n");
        let root = fixture.project();
        let mut cache = DiscoveryCache::load(&root);
        let (_, first_sources, _) = cache
            .discover(&root, &BTreeMap::new(), &BTreeSet::new())
            .unwrap();
        let unchanged = first_sources.keys().cloned().collect();
        fixture.write("a.dm", "/proc/a()\n return 3\n");
        // Deliberately stale unchanged set must fail final proof and retry exact reads.
        let (changed, _, _) = cache.discover(&root, &BTreeMap::new(), &unchanged).unwrap();
        let cold =
            dm_preprocess::preprocess_project(&root, &dm_preprocess::FileSystem, &BTreeMap::new());
        assert_eq!(changed, cold);
        assert!(changed.text.contains("return 3"));
        assert!(cache.resident_bytes() < 224 * 1024 * 1024);
    }

    #[test]
    fn missing_include_and_skin_file_join_exact_dependency_snapshot() {
        let fixture = Fixture::new();
        fixture.write(
            "project.dme",
            "#include \"missing.dm\"\n#include \"interface/skin.dmf\"\n",
        );
        fixture.write("interface/skin.dmf", "// skin dependency\n");
        let root = fixture.project();
        let (first, sources) = discover_consistent_project(&root, &BTreeMap::new()).unwrap();
        assert!(first.dependencies.contains(&fixture.0.join("missing.dm")));
        assert!(!sources.contains_key(&fixture.0.join("missing.dm")));
        assert!(sources.contains_key(&fixture.0.join("interface/skin.dmf")));

        fixture.write("missing.dm", "/proc/arrived()\n    return 1\n");
        let (second, sources) = discover_consistent_project(&root, &BTreeMap::new()).unwrap();
        assert!(second.text.contains("/proc/arrived"));
        assert!(sources.contains_key(&fixture.0.join("missing.dm")));
    }

    #[test]
    fn relative_cache_keys_recheck_source_across_project_roots() {
        let first = Fixture::new();
        let second = Fixture::new();
        for fixture in [&first, &second] {
            fixture.write("project.dme", "#include \"leaf.dm\"\n");
        }
        first.write("leaf.dm", "/proc/value()\n    return 1\n");
        second.write("leaf.dm", "/proc/value()\n    return 2\n");
        let mut cache = PreprocessCache::default();
        let (a, _) = discover_with_cache(&first.project(), &BTreeMap::new(), &mut cache).unwrap();
        let (b, sources) =
            discover_with_cache(&second.project(), &BTreeMap::new(), &mut cache).unwrap();
        assert!(a.text.contains("return 1"));
        assert!(b.text.contains("return 2"));
        assert!(sources.contains_key(&second.0.join("leaf.dm")));
        assert!(cache.misses >= 2);
    }
}

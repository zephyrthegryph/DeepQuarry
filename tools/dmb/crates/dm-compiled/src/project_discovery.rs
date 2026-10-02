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
                self.texts
                    .borrow_mut()
                    .insert(path.to_path_buf(), previous.text.clone());
                self.digests
                    .borrow_mut()
                    .insert(path.to_path_buf(), previous.digest);
                if let Some(stamp) = &previous.stamp {
                    self.stamps
                        .borrow_mut()
                        .insert(path.to_path_buf(), stamp.clone());
                }
                self.reused.set(self.reused.get() + 1);
                return Ok(Arc::clone(&previous.text));
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
    store: Option<crate::ContentStore>,
    resources: dm_resources::ResourceFingerprintCache,
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
            resources: dm_resources::ResourceFingerprintCache::open(&cache_root),
            store: crate::ContentStore::new(cache_root).ok(),
        }
    }

    pub fn resident_bytes(&self) -> usize {
        self.source_resident_bytes()
            .saturating_add(self.resources.resident_bytes())
    }

    /// Detached inputs and expansion frames can be restored from the same CAS
    /// after pool pressure. Resource proof records have their own small bound.
    pub(crate) fn source_resident_bytes(&self) -> usize {
        self.expansions
            .resident_bytes()
            .saturating_add(
                self.prepared
                    .as_ref()
                    .map_or(0, |value| value.resident_bytes()),
            )
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
    }

    pub(crate) fn release_source_frames(&mut self) {
        self.prepared = None;
        self.sources.clear();
        self.expansions.clear();
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
        if self
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
                self.prepared = Some(Arc::new(restored));
            }
        }
        if let Some(snapshot) = self
            .prepared
            .as_ref()
            .filter(|snapshot| snapshot.context == context && snapshot.current())
        {
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
        let previous =
            previous.or_else(|| old.as_ref().and_then(|snapshot| snapshot.proof.as_ref()));
        let mut unchanged = previous
            .map(InputProof::unchanged_paths)
            .unwrap_or_default();
        unchanged.extend(supplied_unchanged.iter().cloned());
        let misses = self.expansions.misses;
        let (project, sources, proof, digests, stamps, mut stats) = discover_with_retained(
            root,
            defines,
            &mut self.expansions,
            &self.sources,
            &unchanged,
            previous,
        )?;
        let sources: BTreeMap<_, _> = sources
            .into_iter()
            .map(|(path, text)| {
                let source = PreparedSource {
                    text,
                    digest: digests[&path],
                    stamp: stamps.get(&path).cloned(),
                };
                (path, source)
            })
            .collect();
        let changes =
            crate::prepared_project::changes(old.as_deref(), &project, &sources, &context);
        let project_digest = crate::prepared_project::project_digest(root, &sources);
        let expanded_digest = format!("{:x}", Sha256::digest(project.text.as_bytes()));
        let revision = format!(
            "{:x}",
            Sha256::digest(format!("{context}:{project_digest}"))
        );
        stats.disk_restored = disk_restored;
        let snapshot = Arc::new(PreparedProject {
            project: Arc::new(project),
            sources: Arc::new(sources),
            project_digest,
            expanded_digest,
            revision,
            changes,
            stats,
            context,
            proof,
        });
        if self.expansions.misses != misses {
            let _ = self.expansions.save_incremental(&self.path);
        }
        if let Some(store) = &self.store {
            let _ = crate::prepared_persistence::save(store, &snapshot);
        }
        self.sources = (*snapshot.sources).clone();
        // Account shared source texts once, then budget expansions alongside
        // the detached current snapshot rather than keeping three source copies.
        self.expansions.trim_to(
            (224usize * 1024 * 1024)
                .saturating_sub(snapshot.resident_bytes())
                .saturating_sub(self.resources.resident_bytes()),
        );
        self.prepared =
            (snapshot.resident_bytes() <= 224 * 1024 * 1024).then(|| Arc::clone(&snapshot));
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
    .map(|(project, sources, proof, _, _, _)| {
        (
            project,
            sources
                .into_iter()
                .map(|(path, text)| (path, text.to_string()))
                .collect(),
            proof,
        )
    })
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
        let discovery = dm_preprocess::preprocess_project_cached(root, &provider, defines, cache);
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
            return Ok((discovery, sources, proof, digests, stamps, stats));
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
        assert_eq!(restored.project.origins[1].source_line, 2);
        assert_eq!(
            restored.project.origins[1].path.as_ref(),
            &fixture.0.join("a.dm")
        );
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
        assert!(arrived.project.text.contains("return 17"));
        assert!(arrived.changes.configuration_changed);
        assert!(arrived
            .changes
            .added_sources
            .contains(&fixture.0.join("missing.dm")));
        let changed = cache
            .prepare(&root, &[("ANSWER".into(), "18".into())].into())
            .unwrap();
        assert!(changed.project.text.contains("return 18"));
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
        assert!(restored.project.text.contains("return 2"));
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

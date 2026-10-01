use crate::input_proof::InputProof;
use dm_host::file_stamp::{capture, FileStamp};
use dm_preprocess::{PreprocessCache, PreprocessedProject, SourceProvider};
use sha2::{Digest, Sha256};
use std::cell::RefCell;
use std::collections::{BTreeMap, BTreeSet};
use std::io;
use std::path::{Path, PathBuf};

/// Keep the exact bytes consumed during a pass. The consistency check must
/// compare those bytes, rather than independently re-reading sources that may
/// already have changed while preprocessing was in progress.
#[derive(Default)]
struct RecordingFileSystem<'a> {
    retained: Option<&'a BTreeMap<PathBuf, RetainedSource>>,
    unchanged: Option<&'a BTreeSet<PathBuf>>,
    digests: RefCell<BTreeMap<PathBuf, [u8; 32]>>,
    texts: RefCell<BTreeMap<PathBuf, String>>,
    stamps: RefCell<BTreeMap<PathBuf, FileStamp>>,
}

impl SourceProvider for RecordingFileSystem<'_> {
    fn read(&self, path: &Path) -> Result<String, String> {
        if let Some(text) = self.texts.borrow().get(path) {
            return Ok(text.clone());
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
                return Ok(previous.text.clone());
            }
        }
        // Retain the stamp taken before these exact source bytes were read.
        // Repeated provider reads use the original text and original stamp.
        let before = if crate::input_proof::exact_inputs() {
            None
        } else {
            capture(path)
        };
        let text = dm_preprocess::read_source_file(path).map_err(|error| error.to_string())?;
        self.digests
            .borrow_mut()
            .insert(path.to_path_buf(), Sha256::digest(text.as_bytes()).into());
        self.texts
            .borrow_mut()
            .insert(path.to_path_buf(), text.clone());
        if let Some(stamp) = before {
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
        self.read(path)?;
        Ok(self.digests.borrow()[path])
    }
}

struct RetainedSource {
    text: String,
    digest: [u8; 32],
    stamp: Option<FileStamp>,
}

/// One session's bounded expansion cache and exact source snapshot. The caller
/// supplies only paths proven unchanged against the last successful discovery.
/// Unknown journal status must use an empty set or exact strong stamp checks.
pub(crate) struct DiscoveryCache {
    path: PathBuf,
    expansions: PreprocessCache,
    sources: BTreeMap<PathBuf, RetainedSource>,
}

impl DiscoveryCache {
    pub(crate) fn load(root: &Path) -> Self {
        let path = dm_compiler::preprocess_cache_path(root);
        Self {
            expansions: PreprocessCache::load_incremental(&path),
            path,
            sources: BTreeMap::new(),
        }
    }

    pub(crate) fn resident_bytes(&self) -> usize {
        self.expansions.resident_bytes()
            + self
                .sources
                .iter()
                .map(|(path, source)| path.as_os_str().len() + source.text.len() + 192)
                .sum::<usize>()
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
        let previous_misses = self.expansions.misses;
        let previous_hits = self.expansions.hits;
        let start = std::time::Instant::now();
        let result = discover_with_retained(
            root,
            defines,
            &mut self.expansions,
            &self.sources,
            unchanged,
            previous,
        )?;
        let (project, sources, proof, digests, stamps) = result;
        if std::env::var_os("DM_BUILD_TRACE").is_some() {
            eprintln!("DM_BUILD_TRACE retained preprocess {:.3}s: {} expansion hits, {} misses, {} requested reusable sources, {} bytes resident",
                start.elapsed().as_secs_f64(), self.expansions.hits - previous_hits,
                self.expansions.misses - previous_misses,
                sources.keys().filter(|path| unchanged.contains(*path) && self.sources.contains_key(*path)).count(),
                self.resident_bytes());
        }
        self.sources.clear();
        let mut bytes = 0usize;
        for (path, text) in &sources {
            bytes += path.as_os_str().len() + text.len() + 192;
            if bytes > 64 * 1024 * 1024 {
                break;
            }
            self.sources.insert(
                path.clone(),
                RetainedSource {
                    text: text.clone(),
                    digest: digests[path],
                    stamp: stamps.get(path).cloned(),
                },
            );
        }
        if self.expansions.misses != previous_misses {
            let _ = self.expansions.save_incremental(&self.path);
        }
        Ok((project, sources, proof))
    }
}

pub(crate) fn discover_consistent_project(
    root: &Path,
    defines: &BTreeMap<String, String>,
) -> io::Result<(PreprocessedProject, BTreeMap<PathBuf, String>)> {
    discover_consistent_project_with_proof(root, defines)
        .map(|(project, sources, _)| (project, sources))
}

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
    .map(|(project, sources, proof, _, _)| (project, sources, proof))
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
    BTreeMap<PathBuf, String>,
    Option<InputProof>,
    BTreeMap<PathBuf, [u8; 32]>,
    BTreeMap<PathBuf, FileStamp>,
)> {
    for attempt in 0..3 {
        // On a consistency retry reread everything; supplied unchanged paths
        // describe the caller's initial observation, not later concurrent edits.
        let provider = RecordingFileSystem {
            retained: (attempt == 0).then_some(retained),
            unchanged: (attempt == 0).then_some(unchanged),
            ..Default::default()
        };
        let discovery = dm_preprocess::preprocess_project_cached(root, &provider, defines, cache);
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
            sources.iter().all(|(path, text)| {
                dm_preprocess::read_source_file(path).is_ok_and(|current| current == *text)
            })
        };
        let missing_still_missing = discovery
            .dependencies
            .iter()
            .filter(|path| !sources.contains_key(*path))
            .all(|path| !path.exists());
        if unchanged && missing_still_missing {
            return Ok((discovery, sources, proof, digests, stamps));
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
            Self(path)
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

use dm_preprocess::{PreprocessCache, PreprocessedProject, SourceProvider};
use std::cell::RefCell;
use std::collections::BTreeMap;
use std::io;
use std::path::{Path, PathBuf};

/// Keep the exact bytes consumed during a pass. The consistency check must
/// compare those bytes, rather than independently re-reading sources that may
/// already have changed while preprocessing was in progress.
#[derive(Default)]
struct RecordingFileSystem(RefCell<BTreeMap<PathBuf, String>>);

impl SourceProvider for RecordingFileSystem {
    fn read(&self, path: &Path) -> Result<String, String> {
        if let Some(text) = self.0.borrow().get(path) {
            return Ok(text.clone());
        }
        let text = dm_preprocess::read_source_file(path).map_err(|error| error.to_string())?;
        self.0.borrow_mut().insert(path.to_path_buf(), text.clone());
        Ok(text)
    }
}

pub(crate) fn discover_consistent_project(
    root: &Path,
    defines: &BTreeMap<String, String>,
) -> io::Result<(PreprocessedProject, BTreeMap<PathBuf, String>)> {
    let cache_path = dm_compiler::preprocess_cache_path(root);
    let tracing = std::env::var_os("DM_BUILD_TRACE").is_some();
    let start = std::time::Instant::now();
    let mut cache = PreprocessCache::load(&cache_path);
    if tracing {
        eprintln!(
            "DM_BUILD_TRACE preprocess cache load {:.3}s: {} bytes resident",
            start.elapsed().as_secs_f64(),
            cache.resident_bytes()
        );
    }
    let replay_start = std::time::Instant::now();
    let result = discover_with_cache(root, defines, &mut cache)?;
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
        let result = cache.save(&cache_path);
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

fn discover_with_cache(
    root: &Path,
    defines: &BTreeMap<String, String>,
    cache: &mut PreprocessCache,
) -> io::Result<(PreprocessedProject, BTreeMap<PathBuf, String>)> {
    for _ in 0..3 {
        let provider = RecordingFileSystem::default();
        let discovery = dm_preprocess::preprocess_project_cached(root, &provider, defines, cache);
        let sources = provider.0.into_inner();
        let unchanged = sources.iter().all(|(path, text)| {
            dm_preprocess::read_source_file(path).is_ok_and(|current| current == *text)
        });
        let missing_still_missing = discovery
            .dependencies
            .iter()
            .filter(|path| !sources.contains_key(*path))
            .all(|path| !path.exists());
        if unchanged && missing_still_missing {
            return Ok((discovery, sources));
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
        assert!(path.is_file());

        let mut restarted = PreprocessCache::load(&path);
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

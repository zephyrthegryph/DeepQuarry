//! The on-disk content-hash cache (`data/analyze-cache/`, gitignored).
//!
//! * `meta.bin`: `rel -> (size, mtime, hash)` so an unchanged file is never read or hashed.
//! * `lint-<name>.bin`: per lint, the per-file scan results keyed by `(rel, file hash)` and the
//!   whole-tree memo keyed by the combined hash of every in-scope file.
//!
//! Every file is stamped with `ENGINE_HASH` (a hash of the engine's own sources, set by build.rs)
//! plus the hash of `lint_scopes.toml`; a different stamp discards the file, so a rebuilt engine
//! or an edited scope list can never serve a stale result. Cache errors are never fatal: a
//! missing or corrupt file is simply a miss.

use std::collections::HashMap;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::lint::Sink;
use crate::tree::{FileMeta, Hash};

pub const ENGINE_HASH: &str = env!("DQ_ENGINE_HASH");

/// Per-lint versions (build.rs): the core hash and the own hash of every leaf lint module.
mod lint_versions {
    include!(concat!(env!("OUT_DIR"), "/lint_versions_gen.rs"));
}

/// The version of one lint's results on the hosted path: the core version plus the lint's own files when its module is a leaf
/// (no other source names it), else the whole engine hash. Editing one leaf lint then invalidates only that lint.
pub fn lint_version(name: &str) -> String {
    let module: String = name.chars().map(|c| if c.is_ascii_alphanumeric() { c.to_ascii_lowercase() } else { '_' }).collect();
    match lint_versions::LEAF_HASHES.iter().find(|(m, _)| *m == module) {
        Some((_, own)) => format!("core={}|lint={}", lint_versions::CORE_HASH, own),
        None => format!("engine={}", ENGINE_HASH),
    }
}

#[derive(Serialize, Deserialize, Default)]
pub struct LintCache {
    pub stamp: String,
    /// `SourceFile::fkey` -> result, for files that produced something.
    pub per_file: HashMap<Hash, Sink>,
    /// `fkey`s of files that were scanned and produced nothing.
    pub clean: std::collections::HashSet<Hash>,
    /// (combined input hash, result)
    pub tree: Option<(Hash, Sink)>,
    #[serde(skip)]
    pub dirty: bool,
}

pub struct Cache {
    dir: PathBuf,
    stamp: String,
    pub enabled: bool,
    scopes_hash: String,
    dmbc_model: bool,
}

#[derive(Serialize, Deserialize, Default)]
struct MetaFile {
    stamp: String,
    files: HashMap<String, FileMeta>,
}

impl Cache {
    pub fn open(root: &Path, scopes_hash: &str, enabled: bool) -> Cache {
        // `DQ_ANALYZE_CACHE` moves the cache (several engine builds, or worktrees, on one tree).
        // A model from dmbc's front end (`DQ_ANALYZE_PARSE=dmbc`) keeps its own cache: every cached fact derives from the model.
        let dmbc_model = crate::sem::provided_parse_selected();
        let default_dir = if dmbc_model { "analyze-cache-dmbc" } else { "analyze-cache" };
        let dir = dq_hostio::var_os("DQ_ANALYZE_CACHE").map(PathBuf::from).unwrap_or_else(|| root.join("data").join(default_dir));
        let stamp = if dmbc_model { format!("{}|{}|parse=dmbc", ENGINE_HASH, scopes_hash) } else { format!("{}|{}", ENGINE_HASH, scopes_hash) };
        // Hosted in a resident process, the results live there (incr::Provider): the machine-wide disk copy is not seeded.
        if enabled && !crate::incr::provider_registered() {
            crate::shared::seed(root, &dir, &stamp);
        }
        crate::incr::configure(dir.clone(), stamp.clone(), enabled);
        Cache { dir, stamp, enabled, scopes_hash: scopes_hash.to_string(), dmbc_model }
    }

    /// The stamp of one lint's hosted entry: its own version (see [`lint_version`]), the scope list and the parse flavor.
    fn hosted_lint_stamp(&self, name: &str) -> String {
        format!("{}|{}{}", lint_version(name), self.scopes_hash, if self.dmbc_model { "|parse=dmbc" } else { "" })
    }

    pub fn stamp(&self) -> &str {
        &self.stamp
    }

    pub fn load_meta(&self) -> HashMap<String, FileMeta> {
        if !self.enabled {
            return HashMap::new();
        }
        match std::fs::read(self.dir.join("meta.bin")).ok().and_then(|b| crate::incr::de::<MetaFile>(&b).ok()) {
            // File metadata does not depend on the engine build, only on the files, so the stamp
            // is not compared here: a hash of unchanged bytes stays valid across engine builds.
            Some(m) => m.files,
            None => HashMap::new(),
        }
    }

    pub fn save_meta(&self, files: &HashMap<String, FileMeta>) {
        if !self.enabled {
            return;
        }
        let _ = std::fs::create_dir_all(&self.dir);
        let m = MetaFile { stamp: self.stamp.clone(), files: files.clone() };
        if let Ok(bytes) = crate::incr::ser(&m) {
            atomic_write(&self.dir.join("meta.bin"), &bytes);
        }
    }

    /// How long each lint took the last time it really scanned (scheduling hint only).
    pub fn load_durations(&self) -> HashMap<String, u64> {
        let mut m = HashMap::new();
        if let Ok(t) = std::fs::read_to_string(self.dir.join("durations.txt")) {
            for l in t.lines() {
                if let Some((n, us)) = l.split_once('\t') {
                    if let Ok(us) = us.parse() {
                        m.insert(n.to_string(), us);
                    }
                }
            }
        }
        m
    }

    pub fn save_durations(&self, d: &HashMap<String, u64>) {
        if !self.enabled {
            return;
        }
        let mut rows: Vec<(&String, &u64)> = d.iter().collect();
        rows.sort();
        let text: String = rows.iter().map(|(n, us)| format!("{}\t{}\n", n, us)).collect();
        let _ = std::fs::create_dir_all(&self.dir);
        atomic_write(&self.dir.join("durations.txt"), text.as_bytes());
    }

    fn lint_path(&self, name: &str) -> PathBuf {
        let safe: String = name.chars().map(|c| if c.is_ascii_alphanumeric() || c == '_' || c == '-' { c } else { '_' }).collect();
        self.dir.join(format!("lint-{}.bin", safe))
    }

    pub fn load_lint(&self, name: &str) -> LintCache {
        if !self.enabled {
            return LintCache { stamp: self.stamp.clone(), ..Default::default() };
        }
        if crate::incr::provider_registered() {
            let stamp = self.hosted_lint_stamp(name);
            let loaded = crate::incr::hosted_get_bytes(&format!("lint:{}", name), &stamp).and_then(|b| crate::incr::de::<LintCache>(&b).ok());
            return match loaded {
                Some(mut c) => {
                    c.stamp = self.stamp.clone();
                    c
                }
                None => LintCache { stamp: self.stamp.clone(), ..Default::default() },
            };
        }
        let loaded = std::fs::read(self.lint_path(name)).ok().and_then(|b| crate::incr::de::<LintCache>(&b).ok());
        match loaded {
            Some(c) if c.stamp == self.stamp => c,
            _ => LintCache { stamp: self.stamp.clone(), ..Default::default() },
        }
    }

    pub fn save_lint(&self, name: &str, cache: &LintCache) {
        if !self.enabled || !cache.dirty {
            return;
        }
        if crate::incr::provider_registered() {
            if let Ok(bytes) = crate::incr::ser(cache) {
                crate::incr::hosted_put_bytes(&format!("lint:{}", name), &self.hosted_lint_stamp(name), bytes);
            }
            return;
        }
        let _ = std::fs::create_dir_all(&self.dir);
        if let Ok(bytes) = crate::incr::ser(cache) {
            atomic_write(&self.lint_path(name), &bytes);
        }
    }
}

fn atomic_write(path: &Path, bytes: &[u8]) {
    let tmp = path.with_extension(format!("tmp{}", std::process::id()));
    if std::fs::write(&tmp, bytes).is_ok() {
        let _ = std::fs::rename(&tmp, path);
    } else {
        let _ = std::fs::remove_file(&tmp);
    }
}

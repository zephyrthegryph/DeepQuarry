//! The on-disk content-hash cache (`data/analyze-cache/`, gitignored).
//!
//! * `meta.bin`: `rel -> (size, mtime, hash)` so an unchanged file is never read or hashed.
//! * A lint's results are entries of the run's query stores (`crate::incr`): per file, keyed by `(rel, file hash)`, under the store
//!   `lint:<name>|<version>`, and its whole-tree memo under `lint-tree:<name>|<version>`, keyed by the combined hash of every
//!   in-scope file.
//!
//! Everything is stamped with `ENGINE_HASH` (a hash of the engine's own sources, set by build.rs) plus the hash of
//! `lint_scopes.toml`; a different stamp is a different store, so a rebuilt engine or an edited scope list can never serve a stale
//! result. Cache errors are never fatal: a missing or corrupt file is simply a miss.

use std::collections::HashMap;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::tree::FileMeta;

pub const ENGINE_HASH: &str = env!("DQ_ENGINE_HASH");

/// Per-lint versions (build.rs): the core hash and the own hash of every leaf lint module.
mod lint_versions {
    include!(concat!(env!("OUT_DIR"), "/lint_versions_gen.rs"));
}

/// The version of one lint's results (part of its store's name): the core version plus the lint's own files when its module is a
/// leaf (no other source names it), else the whole engine hash.
pub fn lint_version(name: &str) -> String {
    let module: String = name.chars().map(|c| if c.is_ascii_alphanumeric() { c.to_ascii_lowercase() } else { '_' }).collect();
    match lint_versions::LEAF_HASHES.iter().find(|(m, _)| *m == module) {
        Some((_, own)) => format!("core={}|lint={}", lint_versions::CORE_HASH, own),
        None => format!("engine={}", ENGINE_HASH),
    }
}

pub struct Cache {
    dir: PathBuf,
    stamp: String,
    pub enabled: bool,
}

#[derive(Serialize, Deserialize, Default)]
struct MetaFile {
    stamp: String,
    files: HashMap<String, FileMeta>,
}

impl Cache {
    pub fn open(root: &Path, scopes_hash: &str, enabled: bool) -> Cache {
        // `DQ_ANALYZE_CACHE` moves the cache (several engine builds, or worktrees, on one tree).
        let dir = dq_hostio::var_os("DQ_ANALYZE_CACHE").map(PathBuf::from).unwrap_or_else(|| root.join("data").join("analyze-cache"));
        let stamp = format!("{}|{}", ENGINE_HASH, scopes_hash);
        // Hosted in a resident process, the stores live there (`incr::set_persist_dir`): the machine-wide disk copy is not seeded.
        if enabled && !crate::incr::hosted() {
            crate::shared::seed(root, &dir, &stamp);
        }
        crate::incr::configure(dir.clone(), stamp.clone(), enabled);
        Cache { dir, stamp, enabled }
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
}

fn atomic_write(path: &Path, bytes: &[u8]) {
    let tmp = path.with_extension(format!("tmp{}", std::process::id()));
    if std::fs::write(&tmp, bytes).is_ok() {
        let _ = std::fs::rename(&tmp, path);
    } else {
        let _ = std::fs::remove_file(&tmp);
    }
}

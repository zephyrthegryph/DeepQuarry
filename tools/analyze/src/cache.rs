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
}

#[derive(Serialize, Deserialize, Default)]
struct MetaFile {
    stamp: String,
    files: HashMap<String, FileMeta>,
}

impl Cache {
    pub fn open(root: &Path, scopes_hash: &str, enabled: bool) -> Cache {
        Cache { dir: root.join("data").join("analyze-cache"), stamp: format!("{}|{}", ENGINE_HASH, scopes_hash), enabled }
    }

    pub fn stamp(&self) -> &str {
        &self.stamp
    }

    pub fn load_meta(&self) -> HashMap<String, FileMeta> {
        if !self.enabled {
            return HashMap::new();
        }
        match std::fs::read(self.dir.join("meta.bin")).ok().and_then(|b| bincode::deserialize::<MetaFile>(&b).ok()) {
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
        if let Ok(bytes) = bincode::serialize(&m) {
            atomic_write(&self.dir.join("meta.bin"), &bytes);
        }
    }

    fn lint_path(&self, name: &str) -> PathBuf {
        let safe: String = name.chars().map(|c| if c.is_ascii_alphanumeric() || c == '_' || c == '-' { c } else { '_' }).collect();
        self.dir.join(format!("lint-{}.bin", safe))
    }

    pub fn load_lint(&self, name: &str) -> LintCache {
        if !self.enabled {
            return LintCache { stamp: self.stamp.clone(), ..Default::default() };
        }
        let loaded = std::fs::read(self.lint_path(name)).ok().and_then(|b| bincode::deserialize::<LintCache>(&b).ok());
        match loaded {
            Some(c) if c.stamp == self.stamp => c,
            _ => LintCache { stamp: self.stamp.clone(), ..Default::default() },
        }
    }

    pub fn save_lint(&self, name: &str, cache: &LintCache) {
        if !self.enabled || !cache.dirty {
            return;
        }
        let _ = std::fs::create_dir_all(&self.dir);
        if let Ok(bytes) = bincode::serialize(cache) {
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

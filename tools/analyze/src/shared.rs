//! The machine-wide cache shared by every worktree (`E:/dq-cache/analyze-cache`, or `$DQ_ANALYZE_SHARED_CACHE`).
//!
//! A worktree's own cache (`data/analyze-cache/`, see [`crate::cache`]) holds per-file results keyed by `(path, content hash)`,
//! stamped with the analyzer build and the scope list. Those keys name content, not a checkout, so a result one worktree computed
//! is exactly right for any other worktree holding the same file bytes. This module moves the files between the two:
//!
//! * **Seed.** The first run of a worktree whose cache was last stamped for something else (a fresh checkout, a pool worktree
//!   switched to a new branch, an analyzer rebuild another worktree already ran) copies the shared files for the current stamp
//!   into its own cache directory. Entries for files that differ simply miss; the rest are warm on the first run.
//! * **Publish.** On exit a run copies the cache files it rewrote into the shared directory for its stamp.
//! * **Safety.** Every copy goes to a scratch name and is renamed into place (a reader sees the old file or the new one, never half
//!   of either, and a decode failure is just a miss). A file in the shared directory is never edited in place.
//! * **Cap.** The shared root keeps at most [`DEFAULT_KEEP`] stamp directories and [`DEFAULT_MAX_MB`] MB, least recently used first
//!   (each seed and publish touches the directory's `.used` file). `tools/dq_cache_prune.sh` applies the same rule by hand.
//!
//! Only files whose content is a pure function of file content, the analyzer build and the scope list are shared (see [`shareable`]):
//! the file table (`meta.bin`: sizes and mtimes), the generator memo (`gen-state.bin`: absolute output paths) and the look-key plan stay
//! local. Sharing is off for tests and fixtures (a root without `deepquarry.dme`), when the local cache directory was moved by
//! `DQ_ANALYZE_CACHE`, and in CI, unless `DQ_ANALYZE_SHARED_CACHE` names a directory explicitly (`off` disables it everywhere).

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Mutex;
use std::time::SystemTime;

/// Stamp directories kept (`DQ_ANALYZE_SHARED_KEEP`).
pub const DEFAULT_KEEP: usize = 4;
/// Total size cap of the shared root in MB (`DQ_ANALYZE_SHARED_MAX_MB`).
pub const DEFAULT_MAX_MB: u64 = 4096;
const MARKER: &str = "shared-stamp";
const USED: &str = ".used";

struct Active {
    local: PathBuf,
    shared: PathBuf,
    root: PathBuf,
    key: String,
    /// Files of the local cache modified at or after this instant were written by this run.
    cutoff: SystemTime,
}

static ACTIVE: Mutex<Option<Active>> = Mutex::new(None);
static SEQ: AtomicUsize = AtomicUsize::new(0);

fn trace() -> bool {
    std::env::var_os("DQ_ANALYZE_TRACE").is_some()
}

/// The shared root, when sharing is on for a run rooted at `repo` with its cache in `local`.
fn shared_root(repo: &Path, local: &Path) -> Option<PathBuf> {
    let explicit = std::env::var("DQ_ANALYZE_SHARED_CACHE").ok();
    match explicit.as_deref() {
        Some("off") | Some("0") | Some("") => return None,
        _ => {}
    }
    if !repo.join("deepquarry.dme").exists() {
        return None;
    }
    if let Some(p) = explicit {
        return Some(PathBuf::from(p));
    }
    // A moved local cache (tests, one-off experiments) must not leak into the shared one; CI machines start empty.
    if std::env::var_os("DQ_ANALYZE_CACHE").is_some() || std::env::var_os("CI").is_some() {
        return None;
    }
    if local != repo.join("data").join("analyze-cache") {
        return None;
    }
    if cfg!(windows) && Path::new("E:/").exists() {
        return Some(PathBuf::from("E:/dq-cache/analyze-cache"));
    }
    let home = std::env::var_os("HOME").or_else(|| std::env::var_os("USERPROFILE"))?;
    Some(PathBuf::from(home).join(".cache").join("dq").join("analyze-cache"))
}

/// A file of the cache directory that may be shared between worktrees.
pub fn shareable(name: &str) -> bool {
    if name.contains(".tmp") {
        return false;
    }
    name == "sem-cache.bin" || name == "sem-types.bin" || name == "linetext.bin" || name == "selftest.ok" || (name.ends_with(".bin") && (name.starts_with("lint-") || name.starts_with("incr-")))
}

fn key_of(stamp: &str) -> String {
    blake3::hash(stamp.as_bytes()).to_hex().as_str()[..32].to_string()
}

fn scratch(dir: &Path, name: &str) -> PathBuf {
    dir.join(format!("{}.tmp{}-{}", name, std::process::id(), SEQ.fetch_add(1, Ordering::Relaxed)))
}

/// Copies `from` to `to` through a scratch file and a rename, so `to` is replaced whole or not at all.
fn copy_atomic(from: &Path, to: &Path) -> bool {
    let (Some(dir), Some(name)) = (to.parent(), to.file_name().and_then(|n| n.to_str())) else { return false };
    let tmp = scratch(dir, name);
    if std::fs::copy(from, &tmp).is_ok() && std::fs::rename(&tmp, to).is_ok() {
        return true;
    }
    let _ = std::fs::remove_file(&tmp);
    false
}

fn touch(shared: &Path) {
    let _ = std::fs::create_dir_all(shared);
    let tmp = scratch(shared, USED);
    if std::fs::write(&tmp, b"x").is_ok() && std::fs::rename(&tmp, shared.join(USED)).is_err() {
        let _ = std::fs::remove_file(&tmp);
    }
}

/// Called when a cache directory is opened for `stamp` (analyzer build + scope list). Idempotent within a process.
pub fn seed(repo: &Path, local: &Path, stamp: &str) {
    let mut guard = ACTIVE.lock().unwrap();
    if guard.is_some() {
        return;
    }
    let Some(root) = shared_root(repo, local) else { return };
    let key = key_of(stamp);
    let shared = root.join(&key);
    let marker = local.join(MARKER);
    let mut copied = 0usize;
    let mut bytes = 0u64;
    if std::fs::read_to_string(&marker).ok().as_deref() != Some(key.as_str()) {
        let _ = std::fs::create_dir_all(local);
        if let Ok(rd) = std::fs::read_dir(&shared) {
            for e in rd.filter_map(|e| e.ok()) {
                let name = e.file_name().to_string_lossy().to_string();
                if !shareable(&name) {
                    continue;
                }
                if copy_atomic(&e.path(), &local.join(&name)) {
                    copied += 1;
                    bytes += e.metadata().map(|m| m.len()).unwrap_or(0);
                }
            }
        }
        let tmp = scratch(local, MARKER);
        if std::fs::write(&tmp, &key).is_ok() && std::fs::rename(&tmp, &marker).is_err() {
            let _ = std::fs::remove_file(&tmp);
        }
        if copied > 0 {
            touch(&shared);
        }
    }
    if trace() {
        eprintln!("analyze: shared cache {} ({}): seeded {} file(s), {} KB", shared.display(), key, copied, bytes / 1024);
    }
    // Everything copied in above is older than this instant; what a run writes later is not.
    *guard = Some(Active { local: local.to_path_buf(), shared, root, key, cutoff: SystemTime::now() });
}

/// Called once when the process ends: copies the cache files this run wrote into the shared directory, then applies the caps.
pub fn publish() {
    let Some(a) = ACTIVE.lock().unwrap().take() else { return };
    let Ok(rd) = std::fs::read_dir(&a.local) else { return };
    let mut published = 0usize;
    let mut bytes = 0u64;
    let _ = std::fs::create_dir_all(&a.shared);
    for e in rd.filter_map(|e| e.ok()) {
        let name = e.file_name().to_string_lossy().to_string();
        if !shareable(&name) {
            continue;
        }
        let Ok(meta) = e.metadata() else { continue };
        if meta.modified().map(|m| m < a.cutoff).unwrap_or(true) {
            continue;
        }
        if copy_atomic(&e.path(), &a.shared.join(&name)) {
            published += 1;
            bytes += meta.len();
        }
    }
    if published > 0 {
        touch(&a.shared);
        prune(&a.root, Some(&a.key));
    }
    if trace() {
        eprintln!("analyze: shared cache: published {} file(s), {} KB", published, bytes / 1024);
    }
}

fn dir_bytes(dir: &Path) -> u64 {
    std::fs::read_dir(dir).map(|rd| rd.filter_map(|e| e.ok()).filter_map(|e| e.metadata().ok()).filter(|m| m.is_file()).map(|m| m.len()).sum()).unwrap_or(0)
}

/// Removes the least recently used stamp directories beyond the caps (never `keep`) and scratch files left by a crashed copy.
pub fn prune(root: &Path, keep: Option<&str>) {
    let max_dirs: usize = std::env::var("DQ_ANALYZE_SHARED_KEEP").ok().and_then(|v| v.parse().ok()).unwrap_or(DEFAULT_KEEP);
    let max_bytes: u64 = std::env::var("DQ_ANALYZE_SHARED_MAX_MB").ok().and_then(|v| v.parse::<u64>().ok()).unwrap_or(DEFAULT_MAX_MB) * 1024 * 1024;
    let Ok(rd) = std::fs::read_dir(root) else { return };
    let mut dirs: Vec<(SystemTime, PathBuf, String, u64)> = Vec::new();
    for e in rd.filter_map(|e| e.ok()) {
        let p = e.path();
        let name = e.file_name().to_string_lossy().to_string();
        if !p.is_dir() || name.len() != 32 || !name.bytes().all(|b| b.is_ascii_hexdigit()) {
            continue;
        }
        // Scratch files an interrupted copy left behind (a live copy is seconds old).
        if let Ok(files) = std::fs::read_dir(&p) {
            for f in files.filter_map(|f| f.ok()) {
                let fname = f.file_name().to_string_lossy().to_string();
                let stale = f.metadata().and_then(|m| m.modified()).ok().and_then(|m| m.elapsed().ok()).map(|d| d.as_secs() > 3600).unwrap_or(false);
                if fname.contains(".tmp") && stale {
                    let _ = std::fs::remove_file(f.path());
                }
            }
        }
        let used = std::fs::metadata(p.join(USED)).or_else(|_| std::fs::metadata(&p)).and_then(|m| m.modified()).unwrap_or(SystemTime::UNIX_EPOCH);
        let size = dir_bytes(&p);
        dirs.push((used, p, name, size));
    }
    // Newest first.
    dirs.sort_by(|a, b| b.0.cmp(&a.0));
    let mut total = 0u64;
    for (i, (_, p, name, size)) in dirs.iter().enumerate() {
        let protected = keep == Some(name.as_str());
        total += size;
        if !protected && (i >= max_dirs || total > max_bytes) {
            let _ = std::fs::remove_dir_all(p);
            total -= size;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_content_pure_files_are_shared() {
        for n in ["lint-api.bin", "incr-dx-file-facts.bin", "sem-cache.bin", "sem-types.bin", "linetext.bin", "selftest.ok"] {
            assert!(shareable(n), "{}", n);
        }
        for n in ["meta.bin", "gen-state.bin", "durations.txt", "shared-stamp", "lint-api.bin.tmp12-3", ".used"] {
            assert!(!shareable(n), "{}", n);
        }
    }

    #[test]
    fn prune_keeps_the_newest_and_the_protected() {
        let t = tempfile::tempdir().unwrap();
        let names: Vec<String> = (0..6).map(|i| format!("{:032x}", i)).collect();
        for (i, n) in names.iter().enumerate() {
            let d = t.path().join(n);
            std::fs::create_dir_all(&d).unwrap();
            std::fs::write(d.join("lint-x.bin"), vec![0u8; 10]).unwrap();
            std::fs::write(d.join(USED), b"x").unwrap();
            // Distinct use times, oldest first.
            let when = SystemTime::now() - std::time::Duration::from_secs(1000 - i as u64 * 100);
            std::fs::File::options().write(true).open(d.join(USED)).unwrap().set_modified(when).unwrap();
        }
        // Dir 0 is the oldest but protected; of the rest the four newest (2 to 5) stay, so only 1 goes.
        std::env::set_var("DQ_ANALYZE_SHARED_KEEP", "4");
        prune(t.path(), Some(&names[0]));
        std::env::remove_var("DQ_ANALYZE_SHARED_KEEP");
        let left: Vec<bool> = names.iter().map(|n| t.path().join(n).exists()).collect();
        assert_eq!(left, vec![true, false, true, true, true, true]);
    }
}

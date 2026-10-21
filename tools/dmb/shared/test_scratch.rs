//! Per-process scratch root for unit tests, shared by the dmb crates with `#[cfg(test)] #[path = ".../shared/test_scratch.rs"] mod test_scratch;`.
//!
//! Every test that needs a store or scratch directory builds it under `root()`, a `run-<pid>-<millis>` directory that this process deletes when it
//! exits (pass or fail; `atexit` runs for the test harness's `process::exit`). A process that dies hard leaves the directory behind; the sweep in
//! `tools/dq_cache_prune.sh` removes run directories older than a day whose pid is gone. Set `DQ_TEST_SCRATCH_KEEP=1` to keep a run for debugging.
use std::{
    path::{Path, PathBuf},
    sync::OnceLock,
};

static RUN: OnceLock<PathBuf> = OnceLock::new();

extern "C" {
    fn atexit(callback: extern "C" fn()) -> i32;
}

extern "C" fn remove_run() {
    if std::env::var_os("DQ_TEST_SCRATCH_KEEP").is_some() {
        return;
    }
    if let Some(run) = RUN.get() {
        remove_tree(run);
    }
}

fn remove_tree(path: &Path) {
    if std::fs::remove_dir_all(path).is_ok() {
        return;
    }
    // Published pair files can be read-only; clear that and retry once.
    fn writable(path: &Path) {
        if let Ok(entries) = std::fs::read_dir(path) {
            for entry in entries.flatten() {
                let child = entry.path();
                if let Ok(meta) = std::fs::symlink_metadata(&child) {
                    if meta.is_dir() {
                        writable(&child);
                    } else if !meta.file_type().is_symlink() {
                        let mut permissions = meta.permissions();
                        #[allow(clippy::permissions_set_readonly_false)]
                        permissions.set_readonly(false);
                        let _ = std::fs::set_permissions(&child, permissions);
                    }
                }
            }
        }
    }
    writable(path);
    let _ = std::fs::remove_dir_all(path);
}

fn base() -> PathBuf {
    if let Some(explicit) = std::env::var_os("DQ_TEST_SCRATCH") {
        return PathBuf::from(explicit);
    }
    if cfg!(windows) && Path::new("E:/dq-cache").is_dir() {
        PathBuf::from("E:/dq-cache/test-scratch")
    } else {
        std::env::temp_dir().join("dq-test-scratch")
    }
}

/// This process's scratch root; created on first use and removed at process exit.
pub fn root() -> PathBuf {
    RUN.get_or_init(|| {
        let stamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|elapsed| elapsed.as_millis())
            .unwrap_or_default();
        let run = base().join(format!("run-{}-{stamp}", std::process::id()));
        std::fs::create_dir_all(&run).expect("create test scratch run directory");
        // SAFETY: registers a plain function with the C runtime; it only touches the static above.
        unsafe {
            atexit(remove_run);
        }
        run
    })
    .clone()
}

/// A fresh, empty, uniquely named directory under `root()` (unique across threads of this process).
pub fn dir(label: &str) -> PathBuf {
    static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
    let path = root().join(format!("{label}-{}", NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed)));
    std::fs::create_dir_all(&path).expect("create test scratch directory");
    path
}

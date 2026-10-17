//! Persistent directory watcher for the resident daemon (doc/retained_frontend.md, watcher).
//!
//! The per-request directory sweep (`filesystem_proofs::capture_canonical`) lists every recorded
//! input directory (about 1,400 on the production tree, 0.6 s). With a healthy watcher a directory's
//! proof stays valid until a change event names it, so a request recaptures only the directories
//! that changed.
//!
//! Soundness rests on three rules:
//! * a request first runs a sync cookie (`sync`): a file is created under the watched root and the
//!   request waits for the watcher thread to see it. Events on one directory handle are ordered, so
//!   every event for a write that preceded the request has been applied to the cache by then;
//! * a proof is cached only when no event of any kind arrived while it was being captured;
//! * a lost event (buffer overflow, read error, sync timeout) clears the cache and bumps the epoch.
//!
//! * a directory reached through a reparse point (junction or symlink) is never cached: change
//!   events are delivered for the watched tree itself, not for the target of a link inside it, so
//!   an edit below such a link would leave a stale proof. Compile roots made of junctions into
//!   worktrees (tools/build/lib/compile_root.ts) depend on this.
//!
//! Publication still restats every captured input live (`runner_freshness::admit_live`), so a missed
//! event can at worst make that admission refuse and rebuild; it cannot publish a stale build.
//! `DMB_WATCH=0` disables the watcher; `DMB_WATCH_VERIFY=1` recaptures every cached directory and
//! logs any difference from the cached proof.
use crate::filesystem_proofs::DirectoryProof;
use std::collections::BTreeMap;
use std::path::Path;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Condvar, Mutex, OnceLock};

static ENABLED: AtomicBool = AtomicBool::new(false);
/// Every event or loss bumps this; a capture that straddles a bump is not cached.
static EVENTS: AtomicU64 = AtomicU64::new(0);
/// A directory's cached answer: its proof, or that it does not exist (a failed open is cached too:
/// the 1,100 or so absent search directories of the production tree cost a failing open each).
#[derive(Clone)]
enum Cached {
    Present(Arc<DirectoryProof>),
    Missing,
}
static CACHE: OnceLock<Mutex<BTreeMap<String, Cached>>> = OnceLock::new();
/// Directories whose proof was served from the cache or captured, for the request log.
static HITS: AtomicU64 = AtomicU64::new(0);
static MISSES: AtomicU64 = AtomicU64::new(0);

fn cache() -> &'static Mutex<BTreeMap<String, Cached>> {
    CACHE.get_or_init(Default::default)
}

/// Whether a directory key is itself a reparse point or lies below one, memoized per directory.
/// An event for a directory entry (created, removed, renamed) drops the memo of that entry and its subtree.
static BEHIND_LINK: OnceLock<Mutex<BTreeMap<String, bool>>> = OnceLock::new();
fn behind_link_memo() -> &'static Mutex<BTreeMap<String, bool>> {
    BEHIND_LINK.get_or_init(Default::default)
}

#[cfg(windows)]
fn is_reparse_point(path: &str) -> bool {
    use std::os::windows::fs::MetadataExt;
    const FILE_ATTRIBUTE_REPARSE_POINT: u32 = 0x400;
    std::fs::symlink_metadata(path).is_ok_and(|meta| meta.file_attributes() & FILE_ATTRIBUTE_REPARSE_POINT != 0)
}
#[cfg(not(windows))]
fn is_reparse_point(path: &str) -> bool {
    std::fs::symlink_metadata(path).is_ok_and(|meta| meta.file_type().is_symlink())
}

/// True when `key` (a comparison key from [`key`]) is a link or below one. A key that cannot be inspected counts as not
/// behind a link only if it does not exist (absence is still reported through its parent's events).
fn behind_link(key: &str) -> bool {
    if let Some(known) = behind_link_memo().lock().unwrap_or_else(|e| e.into_inner()).get(key).copied() {
        return known;
    }
    let parent = key.rsplit_once('\\').map(|(parent, _)| parent).filter(|parent| parent.len() >= 3);
    let result = is_reparse_point(key) || parent.is_some_and(behind_link);
    behind_link_memo().lock().unwrap_or_else(|e| e.into_inner()).insert(key.to_string(), result);
    result
}

fn forget_links(path: &str, subtree: bool) {
    let mut memo = behind_link_memo().lock().unwrap_or_else(|e| e.into_inner());
    memo.remove(path);
    if !subtree {
        return;
    }
    let prefix = format!("{path}\\");
    let doomed: Vec<String> = memo
        .range(prefix.clone()..)
        .take_while(|(key, _)| key.starts_with(&prefix))
        .map(|(key, _)| key.clone())
        .collect();
    for key in doomed {
        memo.remove(&key);
    }
}

/// The daemon turns the watcher on once at start; one-shot processes never do.
pub fn enable() {
    if std::env::var_os("DMB_WATCH").is_none_or(|value| value != "0") {
        ENABLED.store(true, Ordering::Release);
    }
}
pub fn enabled() -> bool {
    ENABLED.load(Ordering::Acquire)
}

/// Comparison key of a directory: ASCII only, no short names, `\\?\` and case folded away.
fn key(path: &Path) -> Option<String> {
    let text = path.to_str()?;
    if !text.is_ascii() || text.contains('~') {
        return None;
    }
    let mut text = text.replace('/', "\\");
    if let Some(stripped) = text.strip_prefix("\\\\?\\") {
        text = stripped.to_string();
    }
    while text.len() > 3 && text.ends_with('\\') {
        text.pop();
    }
    Some(text.to_ascii_lowercase())
}

fn clear_all() {
    EVENTS.fetch_add(1, Ordering::AcqRel);
    cache().lock().unwrap_or_else(|e| e.into_inner()).clear();
    behind_link_memo().lock().unwrap_or_else(|e| e.into_inner()).clear();
}

/// Drop the proofs of the directory holding `path` and of `path` itself; with `subtree` also of
/// everything below it (a removed or renamed directory takes its subtree with it).
fn invalidate(path: &str, subtree: bool) {
    EVENTS.fetch_add(1, Ordering::AcqRel);
    forget_links(path, subtree);
    let mut cache = cache().lock().unwrap_or_else(|e| e.into_inner());
    if let Some(parent) = path.rsplit_once('\\').map(|(parent, _)| parent) {
        cache.remove(parent);
    }
    cache.remove(path);
    if !subtree {
        return;
    }
    let prefix = format!("{path}\\");
    let doomed: Vec<String> = cache
        .range(prefix.clone()..)
        .take_while(|(key, _)| key.starts_with(&prefix))
        .map(|(key, _)| key.clone())
        .collect();
    for key in doomed {
        cache.remove(&key);
    }
}

/// The cached proof of `path`, or a fresh capture that is cached when no event interfered.
pub(crate) fn shared_proof(
    path: &Path,
    capture: impl FnOnce(&Path) -> std::io::Result<DirectoryProof>,
) -> std::io::Result<Arc<DirectoryProof>> {
    let Some(key) = key(path).filter(|key| enabled() && covered(path) && !behind_link(key)) else {
        return capture(path).map(Arc::new);
    };
    if let Some(hit) = cache().lock().unwrap_or_else(|e| e.into_inner()).get(&key).cloned() {
        HITS.fetch_add(1, Ordering::Relaxed);
        if verify_enabled() {
            match (capture(path), &hit) {
                (Ok(fresh), Cached::Present(cached)) if same(&fresh, cached) => {}
                (Err(error), Cached::Missing) if error.kind() == std::io::ErrorKind::NotFound => {}
                _ => crate::daemon_eprintln!("native fs watch VERIFY MISMATCH: {key}"),
            }
        }
        return match hit {
            Cached::Present(proof) => Ok(proof),
            Cached::Missing => Err(std::io::Error::new(std::io::ErrorKind::NotFound, "directory absent (watched)")),
        };
    }
    MISSES.fetch_add(1, Ordering::Relaxed);
    let before = EVENTS.load(Ordering::Acquire);
    let captured = capture(path).map(Arc::new);
    let entry = match &captured {
        Ok(proof) => Some(Cached::Present(Arc::clone(proof))),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Some(Cached::Missing),
        Err(_) => None,
    };
    if let Some(entry) = entry {
        if EVENTS.load(Ordering::Acquire) == before {
            let mut cache = cache().lock().unwrap_or_else(|e| e.into_inner());
            // Re-check under the lock: an event applies its removal under this same lock.
            if EVENTS.load(Ordering::Acquire) == before {
                cache.insert(key, entry);
            }
        }
    }
    captured
}
fn same(a: &DirectoryProof, b: &DirectoryProof) -> bool {
    a.entries == b.entries
}
fn verify_enabled() -> bool {
    static VERIFY: OnceLock<bool> = OnceLock::new();
    *VERIFY.get_or_init(|| std::env::var_os("DMB_WATCH_VERIFY").is_some_and(|value| value == "1"))
}

pub fn counters() -> (u64, u64) {
    (HITS.swap(0, Ordering::Relaxed), MISSES.swap(0, Ordering::Relaxed))
}

#[cfg(windows)]
pub use windows::{arm, covered, sync};
#[cfg(not(windows))]
pub fn arm(_root: &Path) {}
#[cfg(not(windows))]
pub fn sync(_root: &Path) {}
#[cfg(not(windows))]
pub fn covered(_path: &Path) -> bool {
    false
}

#[cfg(windows)]
mod windows {
    use super::*;
    use std::ffi::c_void;
    use std::os::windows::ffi::OsStrExt;

    #[link(name = "kernel32")]
    extern "system" {
        fn CreateFileW(
            name: *const u16,
            access: u32,
            share: u32,
            security: *mut c_void,
            disposition: u32,
            flags: u32,
            template: *mut c_void,
        ) -> *mut c_void;
        fn ReadDirectoryChangesW(
            handle: *mut c_void,
            buffer: *mut c_void,
            length: u32,
            subtree: i32,
            filter: u32,
            returned: *mut u32,
            overlapped: *mut c_void,
            completion: *mut c_void,
        ) -> i32;
    }
    const INVALID: isize = -1;
    const BUFFER_BYTES: usize = 4 * 1024 * 1024;

    struct Root {
        /// Comparison key of the watched directory.
        key: String,
        /// Cookie names seen by the watcher thread, with a wake-up for waiters.
        seen: Mutex<Vec<String>>,
        wake: Condvar,
        healthy: AtomicBool,
        counter: AtomicU64,
    }
    static ROOTS: OnceLock<Mutex<Vec<Arc<Root>>>> = OnceLock::new();
    fn roots() -> &'static Mutex<Vec<Arc<Root>>> {
        ROOTS.get_or_init(Default::default)
    }

    /// True when `path` lies under a watched root whose watcher is healthy.
    pub fn covered(path: &Path) -> bool {
        let Some(key) = key(path) else {
            return false;
        };
        roots().lock().unwrap_or_else(|e| e.into_inner()).iter().any(|root| {
            root.healthy.load(Ordering::Acquire)
                && (key == root.key || key.starts_with(&format!("{}\\", root.key)))
        })
    }

    /// Start watching `root` (idempotent). The first call arms and proves the watcher with a cookie.
    pub fn arm(root: &Path) {
        if !enabled() {
            return;
        }
        let Some(root_key) = key(root) else {
            return;
        };
        {
            let roots = roots().lock().unwrap_or_else(|e| e.into_inner());
            if roots.iter().any(|existing| existing.key == root_key && existing.healthy.load(Ordering::Acquire)) {
                return;
            }
        }
        let wide: Vec<u16> = root.as_os_str().encode_wide().chain(Some(0)).collect();
        // SAFETY: NUL-terminated wide path; no security attributes or template.
        let handle = unsafe {
            CreateFileW(
                wide.as_ptr(),
                0x1,        // FILE_LIST_DIRECTORY
                0x7,        // share read, write, delete
                std::ptr::null_mut(),
                3,          // OPEN_EXISTING
                0x02000000, // FILE_FLAG_BACKUP_SEMANTICS
                std::ptr::null_mut(),
            )
        };
        if handle as isize == INVALID {
            crate::daemon_eprintln!("native fs watch: cannot open {}: {}", root.display(), std::io::Error::last_os_error());
            return;
        }
        let state = Arc::new(Root {
            key: root_key,
            seen: Mutex::new(Vec::new()),
            wake: Condvar::new(),
            healthy: AtomicBool::new(false),
            counter: AtomicU64::new(0),
        });
        {
            let mut all = roots().lock().unwrap_or_else(|e| e.into_inner());
            all.retain(|existing| existing.key != state.key);
            all.push(Arc::clone(&state));
        }
        let handle_value = handle as usize;
        let thread_state = Arc::clone(&state);
        let spawned = std::thread::Builder::new()
            .name("dmbc-fs-watch".into())
            .spawn(move || run(handle_value as *mut c_void, &thread_state));
        if spawned.is_err() {
            state.healthy.store(false, Ordering::Release);
            return;
        }
        // Prove it: nothing may be cached from this root before a cookie round trip succeeds.
        state.healthy.store(false, Ordering::Release);
        // Changes are buffered per handle only from the first read call on, so a cookie written
        // before the thread reaches it is lost; a later one proves the watcher.
        if (0..3).any(|_| cookie(root, &state, 1)) {
            state.healthy.store(true, Ordering::Release);
            crate::daemon_eprintln!("native fs watch: armed {}", root.display());
        } else {
            crate::daemon_eprintln!("native fs watch: sync cookie timed out for {}", root.display());
        }
    }

    /// Order a request after every earlier write under `root`. On timeout the watcher is distrusted
    /// and its cache dropped, so the request sweeps as before.
    pub fn sync(root: &Path) {
        if !enabled() {
            return;
        }
        let Some(root_key) = key(root) else {
            return;
        };
        let state = roots()
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .iter()
            .find(|existing| existing.key == root_key)
            .cloned();
        let Some(state) = state else {
            return;
        };
        if !cookie(root, &state, 3) {
            state.healthy.store(false, Ordering::Release);
            clear_all();
            crate::daemon_eprintln!("native fs watch: sync cookie timed out; cache dropped");
        }
    }

    fn cookie(root: &Path, state: &Root, seconds: u64) -> bool {
        let directory = root.join(".dmbc");
        let _ = std::fs::create_dir_all(&directory);
        let id = state.counter.fetch_add(1, Ordering::Relaxed);
        let name = format!("watch-cookie-{}-{id}", std::process::id());
        let path = directory.join(&name);
        if std::fs::write(&path, b"x").is_err() {
            return false;
        }
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(seconds);
        let mut seen = state.seen.lock().unwrap_or_else(|e| e.into_inner());
        let found = loop {
            if let Some(at) = seen.iter().position(|seen| *seen == name) {
                seen.remove(at);
                break true;
            }
            let now = std::time::Instant::now();
            if now >= deadline {
                break false;
            }
            seen = state
                .wake
                .wait_timeout(seen, deadline - now)
                .unwrap_or_else(|e| e.into_inner())
                .0;
        };
        drop(seen);
        let _ = std::fs::remove_file(&path);
        found
    }

    fn run(handle: *mut c_void, state: &Root) {
        let mut buffer = vec![0u32; BUFFER_BYTES / 4];
        loop {
            let mut returned = 0u32;
            // SAFETY: the buffer is DWORD aligned and owns BUFFER_BYTES; the call is synchronous.
            let ok = unsafe {
                ReadDirectoryChangesW(
                    handle,
                    buffer.as_mut_ptr().cast(),
                    BUFFER_BYTES as u32,
                    1,
                    0x5F, // file name, dir name, attributes, size, last write, creation
                    &mut returned,
                    std::ptr::null_mut(),
                    std::ptr::null_mut(),
                )
            };
            if ok == 0 {
                state.healthy.store(false, Ordering::Release);
                clear_all();
                crate::daemon_eprintln!("native fs watch: read failed: {}", std::io::Error::last_os_error());
                return;
            }
            if returned == 0 {
                // Overflow: events were dropped.
                clear_all();
                continue;
            }
            // SAFETY: the kernel wrote `returned` bytes of FILE_NOTIFY_INFORMATION records.
            let bytes = unsafe { std::slice::from_raw_parts(buffer.as_ptr().cast::<u8>(), returned as usize) };
            let mut offset = 0usize;
            let mut cookies = Vec::new();
            loop {
                let Some(head) = bytes.get(offset..offset + 12) else {
                    clear_all();
                    break;
                };
                let next = u32::from_le_bytes(head[0..4].try_into().unwrap()) as usize;
                let action = u32::from_le_bytes(head[4..8].try_into().unwrap());
                let length = u32::from_le_bytes(head[8..12].try_into().unwrap()) as usize;
                let Some(name) = bytes.get(offset + 12..offset + 12 + length) else {
                    clear_all();
                    break;
                };
                let units: Vec<u16> = name.chunks_exact(2).map(|pair| u16::from_le_bytes([pair[0], pair[1]])).collect();
                match String::from_utf16(&units) {
                    Ok(relative) => {
                        let relative = relative.replace('/', "\\");
                        if let Some(cookie) = relative.rsplit('\\').next().filter(|name| name.starts_with("watch-cookie-")) {
                            cookies.push(cookie.to_string());
                        }
                        let full = if relative.is_empty() {
                            state.key.clone()
                        } else {
                            format!("{}\\{}", state.key, relative.to_ascii_lowercase())
                        };
                        if relative.is_ascii() {
                            // Everything but a plain modification can add or remove a directory, and with it the
                            // cached answers (proofs and absences) of its whole subtree.
                            invalidate(&full, action != 3);
                        } else {
                            clear_all();
                        }
                    }
                    Err(_) => clear_all(),
                }
                if next == 0 {
                    break;
                }
                offset += next;
            }
            if !cookies.is_empty() {
                state.seen.lock().unwrap_or_else(|e| e.into_inner()).extend(cookies);
                state.wake.notify_all();
            }
        }
    }
}

#[cfg(all(test, windows))]
mod link_tests {
    use super::*;

    #[test]
    fn directories_behind_a_junction_are_never_cached() {
        let base = std::env::temp_dir().join(format!("dmbc-link-test-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&base);
        let target = base.join("target");
        let root = base.join("root");
        std::fs::create_dir_all(target.join("child")).unwrap();
        std::fs::create_dir_all(root.join("plain")).unwrap();
        let junction = root.join("link");
        let status = std::process::Command::new("cmd")
            .args(["/C", "mklink", "/J"])
            .arg(&junction)
            .arg(&target)
            .output()
            .unwrap();
        assert!(status.status.success(), "mklink failed: {}", String::from_utf8_lossy(&status.stdout));
        let key_of = |path: &Path| key(path).unwrap();
        assert!(behind_link(&key_of(&junction)));
        assert!(behind_link(&key_of(&junction.join("child"))));
        assert!(!behind_link(&key_of(&root.join("plain"))));
        // Removing the junction (not its target) and recreating the entry as a plain directory is seen after the
        // watcher's event for the entry drops the memo.
        std::fs::remove_dir(&junction).unwrap();
        assert!(target.join("child").is_dir(), "removing a junction must not touch its target");
        invalidate(&key_of(&junction), true);
        std::fs::create_dir(&junction).unwrap();
        assert!(!behind_link(&key_of(&junction)));
        let _ = std::fs::remove_dir_all(&base);
    }
}

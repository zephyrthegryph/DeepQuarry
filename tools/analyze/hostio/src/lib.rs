//! The process boundary of the analysis engine, made per request.
//!
//! Standalone (`analyze`, `dmbc analyze` without a daemon) nothing is installed: output goes to the process's stdout and stderr
//! and variables come from the process environment, exactly as `println!` and `std::env::var` would.
//! Inside the dmbc daemon one request runs at a time; the daemon installs a [`Scope`] for it, so the request's output is captured
//! for its client and its variables are the client's, without touching the daemon's own streams or environment (which a compile
//! running beside it reads).
//!
//! analyze, dreamchecker and dreammaker shadow `print!`, `println!`, `eprint!` and `eprintln!` at their crate roots with macros
//! that call [`out`], and read variables through [`var`] / [`var_os`].

use std::collections::HashMap;
use std::ffi::OsString;
use std::fmt;
use std::io::Write;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, RwLock};

/// Receives a request's output: `(stdout, bytes)`.
pub type Sink = dyn Fn(bool, &[u8]) + Send + Sync;

/// What one request runs inside: its environment and where its output goes.
pub struct Scope {
    /// The complete environment the request sees (the client's).
    pub env: HashMap<String, String>,
    /// The client's working directory.
    pub cwd: std::path::PathBuf,
    pub sink: Arc<Sink>,
}

static SCOPE: RwLock<Option<Arc<Scope>>> = RwLock::new(None);
/// Set by the first request scope and never cleared: this process hosts requests and lives on after each one.
static HOST_PROCESS: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);
/// Variables the request set for itself (`set_var`, `remove_var`), on top of its environment.
static LOCAL: Mutex<Option<HashMap<String, Option<String>>>> = Mutex::new(None);
/// Bumped whenever the environment a read would see may change, so values cached from it are computed again.
static GENERATION: AtomicU64 = AtomicU64::new(0);
/// Every variable a request read from its environment (not one it set for itself), with the value it saw: what a remembered
/// answer to the same request depends on ([`env_reads`]).
static READS: Mutex<Option<std::collections::BTreeMap<String, Option<String>>>> = Mutex::new(None);

/// Runs `f` inside `scope`. One scope at a time: the caller serializes requests.
pub fn with_scope<R>(scope: Scope, f: impl FnOnce() -> R) -> R {
    struct Reset;
    impl Drop for Reset {
        fn drop(&mut self) {
            *SCOPE.write().unwrap_or_else(|e| e.into_inner()) = None;
            *READS.lock().unwrap_or_else(|e| e.into_inner()) = None;
            *LOCAL.lock().unwrap_or_else(|e| e.into_inner()) = None;
            GENERATION.fetch_add(1, Ordering::SeqCst);
        }
    }
    HOST_PROCESS.store(true, Ordering::SeqCst);
    *SCOPE.write().unwrap_or_else(|e| e.into_inner()) = Some(Arc::new(scope));
    *LOCAL.lock().unwrap_or_else(|e| e.into_inner()) = Some(HashMap::new());
    *READS.lock().unwrap_or_else(|e| e.into_inner()) = Some(Default::default());
    SPAWNED.store(false, Ordering::SeqCst);
    GENERATION.fetch_add(1, Ordering::SeqCst);
    let _reset = Reset;
    f()
}

/// Whether a request scope is installed (the code runs inside the daemon).
pub fn hosted() -> bool {
    SCOPE.read().unwrap_or_else(|e| e.into_inner()).is_some()
}

/// Whether this process has ever run a request scope: it is a host that outlives its requests, also between two of them and on
/// the threads a request leaves to finish. A one-shot run never sets it.
pub fn host_process() -> bool {
    HOST_PROCESS.load(Ordering::SeqCst)
}

/// Gives up `value` at the end of a run. A one-shot process is about to exit, so the value is forgotten: the OS reclaims it at
/// once, where freeing a whole-tree model one allocation at a time takes seconds. A host lives on, so there the value is dropped;
/// forgetting it would leak it on every request.
pub fn discard<T>(value: T) {
    if host_process() {
        drop(value);
    } else {
        std::mem::forget(value);
    }
}

/// Changes whenever the environment a read would see may have changed.
pub fn generation() -> u64 {
    GENERATION.load(Ordering::SeqCst)
}

fn scope() -> Option<Arc<Scope>> {
    SCOPE.read().unwrap_or_else(|e| e.into_inner()).clone()
}

/// `print!` / `println!` (`stdout`) and `eprint!` / `eprintln!`: to the request's sink, else the process's stream.
pub fn out(stdout: bool, args: fmt::Arguments, newline: bool) {
    match scope() {
        Some(s) => {
            let mut b = Vec::with_capacity(80);
            let _ = b.write_fmt(args);
            if newline {
                b.push(b'\n');
            }
            (s.sink)(stdout, &b);
        }
        None if stdout => {
            let mut o = std::io::stdout().lock();
            let _ = o.write_fmt(args);
            if newline {
                let _ = o.write_all(b"\n");
            }
        }
        None => {
            let mut o = std::io::stderr().lock();
            let _ = o.write_fmt(args);
            if newline {
                let _ = o.write_all(b"\n");
            }
        }
    }
}

/// Raw bytes to stdout or stderr.
pub fn write_bytes(stdout: bool, bytes: &[u8]) {
    match scope() {
        Some(s) => (s.sink)(stdout, bytes),
        None if stdout => {
            let _ = std::io::stdout().write_all(bytes);
        }
        None => {
            let _ = std::io::stderr().write_all(bytes);
        }
    }
}

/// Flushes the process streams (a request's sink needs none).
pub fn flush() {
    if !hosted() {
        let _ = std::io::stdout().flush();
        let _ = std::io::stderr().flush();
    }
}

/// `std::env::current_dir`: the client's when a request is installed.
pub fn current_dir() -> std::io::Result<std::path::PathBuf> {
    match scope() {
        Some(s) => Ok(s.cwd.clone()),
        None => std::env::current_dir(),
    }
}

/// `std::env::var_os`, of the request's environment when one is installed.
pub fn var_os(name: impl AsRef<std::ffi::OsStr>) -> Option<OsString> {
    let name = name.as_ref();
    let Some(s) = scope() else { return std::env::var_os(name) };
    let key = name.to_string_lossy();
    if let Some(local) = LOCAL.lock().unwrap_or_else(|e| e.into_inner()).as_ref() {
        if let Some((_, v)) = local.iter().find(|(k, _)| same_name(k, &key)) {
            return v.clone().map(OsString::from);
        }
    }
    let value = s.env.iter().find(|(k, _)| same_name(k, &key)).map(|(_, v)| v.clone());
    if let Some(reads) = READS.lock().unwrap_or_else(|e| e.into_inner()).as_mut() {
        reads.entry(canonical_name(&key)).or_insert_with(|| value.clone());
    }
    value.map(OsString::from)
}

/// The variables this request has read from its environment so far, by canonical name (upper case on Windows), with the value
/// each read saw (`None`: absent). Reads of a variable the request set or removed itself are not listed: they do not depend on the
/// environment. Empty outside a request.
pub fn env_reads() -> Vec<(String, Option<String>)> {
    READS.lock().unwrap_or_else(|e| e.into_inner()).as_ref().map(|r| r.iter().map(|(k, v)| (k.clone(), v.clone())).collect()).unwrap_or_default()
}

/// Whether this request made a child command ([`command`]): its answer then depends on the child's whole environment, its other
/// inputs and the time it ran, not only on what the request itself read.
pub fn spawned_child() -> bool {
    SPAWNED.load(Ordering::SeqCst)
}

static SPAWNED: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

/// The name a variable is compared by: as written, upper-cased where names ignore case (Windows).
pub fn canonical_name(name: &str) -> String {
    if cfg!(windows) {
        name.to_ascii_uppercase()
    } else {
        name.to_string()
    }
}

/// The value `name` has in `env` the way a read inside a request with that environment would see it (case-insensitive on Windows).
pub fn lookup<'a>(env: &'a HashMap<String, String>, name: &str) -> Option<&'a String> {
    env.iter().find(|(k, _)| same_name(k, name)).map(|(_, v)| v)
}

/// `std::env::var`, of the request's environment when one is installed.
pub fn var(name: impl AsRef<std::ffi::OsStr>) -> Result<String, std::env::VarError> {
    match var_os(name) {
        Some(v) => v.into_string().map_err(std::env::VarError::NotUnicode),
        None => Err(std::env::VarError::NotPresent),
    }
}

/// `std::env::set_var`, for the request only when one is installed.
pub fn set_var(name: &str, value: impl AsRef<std::ffi::OsStr>) {
    let mut local = LOCAL.lock().unwrap_or_else(|e| e.into_inner());
    match local.as_mut() {
        Some(l) => {
            l.retain(|k, _| !same_name(k, name));
            l.insert(name.to_string(), Some(value.as_ref().to_string_lossy().into_owned()));
        }
        None => std::env::set_var(name, value),
    }
    drop(local);
    GENERATION.fetch_add(1, Ordering::SeqCst);
}

/// `std::env::remove_var`, for the request only when one is installed.
pub fn remove_var(name: &str) {
    let mut local = LOCAL.lock().unwrap_or_else(|e| e.into_inner());
    match local.as_mut() {
        Some(l) => {
            l.retain(|k, _| !same_name(k, name));
            l.insert(name.to_string(), None);
        }
        None => std::env::remove_var(name),
    }
    drop(local);
    GENERATION.fetch_add(1, Ordering::SeqCst);
}

/// The environment a child process of the request gets: the request's with its own changes; `None` when standalone (a child
/// inherits the process environment).
pub fn child_env() -> Option<Vec<(String, String)>> {
    let s = scope()?;
    let mut env: Vec<(String, String)> = s.env.iter().map(|(k, v)| (k.clone(), v.clone())).collect();
    if let Some(local) = LOCAL.lock().unwrap_or_else(|e| e.into_inner()).as_ref() {
        for (k, v) in local {
            env.retain(|(e, _)| !same_name(e, k));
            if let Some(v) = v {
                env.push((k.clone(), v.clone()));
            }
        }
    }
    Some(env)
}

/// A child command with the request's environment (inherits the process's when standalone). A child reads what it likes, so the
/// request now depends on more than [`env_reads`] lists ([`spawned_child`]).
pub fn command(program: impl AsRef<std::ffi::OsStr>) -> std::process::Command {
    SPAWNED.store(true, Ordering::SeqCst);
    let mut cmd = std::process::Command::new(program);
    if let Some(env) = child_env() {
        cmd.env_clear().envs(env);
    }
    cmd
}

/// Variable names compare case-insensitively on Windows.
fn same_name(a: &str, b: &str) -> bool {
    if cfg!(windows) {
        a.eq_ignore_ascii_case(b)
    } else {
        a == b
    }
}

/// A value computed from the environment and kept until the environment may have changed (what a `static ON: OnceLock<bool>`
/// was in a one-run process; a daemon request must compute it again from its own environment).
pub struct EnvCached<T: Copy> {
    cell: Mutex<Option<(u64, T)>>,
}

impl<T: Copy> EnvCached<T> {
    pub const fn new() -> Self {
        EnvCached { cell: Mutex::new(None) }
    }

    pub fn get(&self, f: impl FnOnce() -> T) -> T {
        let g = generation();
        let mut c = self.cell.lock().unwrap_or_else(|e| e.into_inner());
        if let Some((gen, v)) = *c {
            if gen == g {
                return v;
            }
        }
        let v = f();
        *c = Some((g, v));
        v
    }
}

impl<T: Copy> Default for EnvCached<T> {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A host outlives its requests, so what a run gives up there must be freed: forgetting it grew the daemon on every request.
    #[test]
    fn a_host_process_frees_what_a_run_discards() {
        struct Counted(Arc<AtomicU64>);
        impl Drop for Counted {
            fn drop(&mut self) {
                self.0.fetch_add(1, Ordering::SeqCst);
            }
        }
        let dropped = Arc::new(AtomicU64::new(0));
        // What the first request scope sets (set here directly: the other tests own the one scope slot).
        HOST_PROCESS.store(true, Ordering::SeqCst);
        assert!(host_process());
        discard(Counted(dropped.clone()));
        assert_eq!(dropped.load(Ordering::SeqCst), 1, "a host frees what a run discards, inside a request or between two");
    }

    #[test]
    fn scope_captures_output_and_environment() {
        let got: Arc<Mutex<Vec<(bool, Vec<u8>)>>> = Arc::default();
        let g = got.clone();
        let mut env = HashMap::new();
        env.insert("DQ_HOSTIO_TEST".to_string(), "inside".to_string());
        let before = generation();
        with_scope(Scope { env, cwd: std::path::PathBuf::from("."), sink: Arc::new(move |o, b| g.lock().unwrap().push((o, b.to_vec()))) }, || {
            assert!(hosted());
            assert_eq!(var("DQ_HOSTIO_TEST").as_deref(), Ok("inside"));
            set_var("DQ_HOSTIO_TEST", "changed");
            assert_eq!(var("DQ_HOSTIO_TEST").as_deref(), Ok("changed"));
            remove_var("DQ_HOSTIO_TEST");
            assert!(var_os("DQ_HOSTIO_TEST").is_none());
            assert!(var("DQ_HOSTIO_ABSENT").is_err());
            let reads = env_reads();
            assert!(reads.iter().any(|(k, v)| k.eq_ignore_ascii_case("DQ_HOSTIO_TEST") && v.as_deref() == Some("inside")));
            assert!(reads.iter().any(|(k, v)| k.eq_ignore_ascii_case("DQ_HOSTIO_ABSENT") && v.is_none()));
            out(true, format_args!("a{}", 1), true);
            out(false, format_args!("b"), false);
        });
        assert!(!hosted());
        assert!(generation() > before);
        assert!(std::env::var_os("DQ_HOSTIO_TEST").is_none(), "a request never writes the process environment");
        assert_eq!(*got.lock().unwrap(), vec![(true, b"a1\n".to_vec()), (false, b"b".to_vec())]);
    }

    #[test]
    fn env_cached_recomputes_after_a_scope_change() {
        static C: EnvCached<u32> = EnvCached::new();
        let mut n = 0;
        assert_eq!(C.get(|| { n += 1; n }), 1);
        assert_eq!(C.get(|| { n += 1; n }), 1);
        with_scope(Scope { env: HashMap::new(), cwd: std::path::PathBuf::from("."), sink: Arc::new(|_, _| {}) }, || {});
        assert_eq!(C.get(|| { n += 1; n }), 2);
    }
}

//! A warm worker per worktree: an `analyze` process that has already read the caches a run needs (the stored model, every proc body
//! decoded, the walk store) and waits for one request. `analyze check` (and `timing`, `baseline`, `gen`) hands its command line to it
//! instead of starting cold, so a run after an edit pays for the edit and not for reading and decoding the caches.
//!
//! The worker runs exactly one request, as an ordinary run of this binary would (same code, same process-wide state from a clean
//! start: nothing is reused across requests but what it read before the request came), writes the answer, then starts its successor
//! and exits. Output, files written and the exit code are the standalone run's: the worker's stdout and stderr are files the client
//! prints once the run is over (each stream byte for byte; the two are not interleaved).
//!
//! Everything lives in `<cache>/warm/` (`data/analyze-cache/warm`):
//!
//! * `starting.json`: a worker is reading its caches (heartbeat: the file's mtime);
//! * `ready.json`: a worker waits (pid, binary identity, environment digest, its output files; heartbeat: mtime);
//! * `claim`: one client holds the worker (created with `create_new`: a second client runs standalone);
//! * `request.json` / `done.json`: the command line, working directory and environment; the exit code;
//! * `retire`: a client found the waiting worker built or started differently and asks it to exit.
//!
//! Memory: the worker holds about 2-3 GB while it waits. It does not start with less than [`MIN_FREE_START_GB`] of RAM free, and it exits
//! after [`DEFAULT_IDLE_MIN`] minutes without a request (`DQ_ANALYZE_WARM_IDLE_MIN`) or as soon as free RAM falls under
//! [`MIN_FREE_IDLE_GB`] while it waits; the next request then runs standalone and starts a new one. `DQ_ANALYZE_WARM=0` (and `CI`) turns
//! it off. Any doubt (no worker, a different binary or environment, a busy or silent worker) runs standalone; nothing is killed.

use std::path::{Path, PathBuf};
use std::time::{Duration, Instant, SystemTime};

/// Commands a warm worker serves.
const SERVED: &[&str] = &["check", "timing", "baseline", "gen"];
const DEFAULT_IDLE_MIN: u64 = 10;
const MIN_FREE_START_GB: u64 = 12;
const MIN_FREE_IDLE_GB: u64 = 6;
/// A heartbeat older than this is a dead worker.
const STALE: Duration = Duration::from_secs(10);
/// How long a client waits for a worker that is still reading its caches.
const WAIT_STARTING: Duration = Duration::from_secs(20);
const CHILD_ENV: &str = "DQ_ANALYZE_WARM_CHILD";

#[derive(serde::Serialize, serde::Deserialize)]
struct Ready {
    pid: u32,
    exe: String,
    env: String,
    out: PathBuf,
    err: PathBuf,
}

#[derive(serde::Serialize, serde::Deserialize)]
struct Request {
    argv: Vec<String>,
    cwd: PathBuf,
    env: Vec<(String, String)>,
}

fn trace() -> bool {
    std::env::var_os("DQ_ANALYZE_WARM_TRACE").is_some()
}

/// The cache directory a run of this worktree uses (as `Cache::open` picks it).
fn cache_dir(root: &Path) -> PathBuf {
    std::env::var_os("DQ_ANALYZE_CACHE").map(PathBuf::from).unwrap_or_else(|| root.join("data").join("analyze-cache"))
}

fn warm_dir(root: &Path) -> PathBuf {
    cache_dir(root).join("warm")
}

/// Whether this command line may go to a warm worker.
fn wanted(argv: &[String]) -> bool {
    if std::env::var_os(CHILD_ENV).is_some() || std::env::var_os("DQ_ANALYZE_UNUSED_RECHECK").is_some() {
        return false;
    }
    if matches!(std::env::var("DQ_ANALYZE_WARM").as_deref(), Ok("0") | Ok("off")) {
        return false;
    }
    if std::env::var("CI").is_ok_and(|v| !v.is_empty() && v != "0" && v != "false") {
        return false;
    }
    let Some(cmd) = argv.get(1) else { return false };
    SERVED.contains(&cmd.as_str()) && !argv.iter().any(|a| a == "--no-cache")
}

/// The binary's identity: a worker of another build never serves. A worker runs from a copy (so the build can replace the binary while
/// it waits) and is told the identity of the binary it was copied from.
fn exe_id() -> String {
    if let Ok(id) = std::env::var("DQ_ANALYZE_WARM_EXE") {
        return id;
    }
    let Ok(exe) = std::env::current_exe() else { return String::new() };
    let meta = std::fs::metadata(&exe).ok();
    let len = meta.as_ref().map(|m| m.len()).unwrap_or(0);
    let modified = meta.and_then(|m| m.modified().ok()).and_then(|t| t.duration_since(SystemTime::UNIX_EPOCH).ok()).map(|d| d.as_nanos()).unwrap_or(0);
    format!("{}|{}|{}", exe.display(), len, modified)
}

/// The environment a run can read (`DQ_*`, `CI`, `RAYON_*`), as a digest: a worker started under another one never serves.
fn env_digest() -> String {
    let mut v: Vec<(String, String)> = std::env::vars()
        .filter(|(k, _)| (k.starts_with("DQ_") || k == "CI" || k.starts_with("RAYON_")) && !k.starts_with("DQ_ANALYZE_WARM"))
        .collect();
    v.sort();
    let mut h = blake3::Hasher::new();
    for (k, val) in v {
        h.update(k.as_bytes());
        h.update(b"=");
        h.update(val.as_bytes());
        h.update(b"\n");
    }
    h.finalize().to_hex().to_string()
}

fn fresh(path: &Path) -> bool {
    std::fs::metadata(path).ok().and_then(|m| m.modified().ok()).and_then(|t| t.elapsed().ok()).is_some_and(|age| age < STALE)
}

fn touch(path: &Path) {
    if let Ok(f) = std::fs::OpenOptions::new().append(true).open(path) {
        let _ = f.set_modified(SystemTime::now());
    }
}

fn write_atomic(path: &Path, bytes: &[u8]) -> bool {
    let tmp = path.with_extension(format!("tmp{}", std::process::id()));
    std::fs::write(&tmp, bytes).is_ok() && std::fs::rename(&tmp, path).is_ok()
}

/// Free physical memory in GB (Windows; elsewhere unknown, taken as plenty).
fn free_gb() -> u64 {
    #[cfg(windows)]
    {
        #[repr(C)]
        struct MemoryStatusEx {
            length: u32,
            memory_load: u32,
            total_phys: u64,
            avail_phys: u64,
            total_page_file: u64,
            avail_page_file: u64,
            total_virtual: u64,
            avail_virtual: u64,
            avail_extended_virtual: u64,
        }
        #[link(name = "kernel32")]
        extern "system" {
            fn GlobalMemoryStatusEx(buffer: *mut MemoryStatusEx) -> i32;
        }
        let mut m = MemoryStatusEx { length: std::mem::size_of::<MemoryStatusEx>() as u32, memory_load: 0, total_phys: 0, avail_phys: 0, total_page_file: 0, avail_page_file: 0, total_virtual: 0, avail_virtual: 0, avail_extended_virtual: 0 };
        // SAFETY: the buffer is a correctly sized MEMORYSTATUSEX with its length set, as the call requires.
        if unsafe { GlobalMemoryStatusEx(&mut m) } != 0 {
            return m.avail_phys >> 30;
        }
        u64::MAX
    }
    #[cfg(not(windows))]
    {
        u64::MAX
    }
}

// ------------------------------------------------------------------------------------------------------------------------------------
// Client

/// Runs `argv` on the warm worker of `root` when one can serve it; `None` means run it here. Starts a worker for the next run when none
/// is waiting or starting.
pub fn client(root: &Path, argv: &[String]) -> Option<u8> {
    if !wanted(argv) {
        return None;
    }
    let dir = warm_dir(root);
    let _ = std::fs::create_dir_all(&dir);
    let ready_path = dir.join("ready.json");
    let started = Instant::now();
    // A worker still reading its caches is worth a short wait: a standalone run costs more than its remaining start.
    while !fresh(&ready_path) && fresh(&dir.join("starting.json")) && started.elapsed() < WAIT_STARTING {
        std::thread::sleep(Duration::from_millis(50));
    }
    let Some(ready) = std::fs::read(&ready_path).ok().and_then(|b| serde_json::from_slice::<Ready>(&b).ok()).filter(|_| fresh(&ready_path)) else {
        spawn(root);
        return None;
    };
    if ready.exe != exe_id() || ready.env != env_digest() {
        // A worker of another build or environment would hold its memory until it idles out: ask it to go now.
        let _ = std::fs::write(dir.join("retire"), b"");
        if trace() {
            eprintln!("analyze: warm: the waiting worker is another build or environment; retired it, running here");
        }
        return None;
    }
    let claim = dir.join("claim");
    if let Ok(m) = std::fs::metadata(&claim) {
        // A claim left by a client that died (no worker holds a request this long).
        if m.modified().ok().and_then(|t| t.elapsed().ok()).is_some_and(|a| a > Duration::from_secs(30 * 60)) {
            let _ = std::fs::remove_file(&claim);
        }
    }
    if std::fs::OpenOptions::new().write(true).create_new(true).open(&claim).is_err() {
        return None;
    }
    let req = Request {
        argv: argv.to_vec(),
        cwd: std::env::current_dir().unwrap_or_else(|_| root.to_path_buf()),
        env: std::env::vars().collect(),
    };
    let done_path = dir.join("done.json");
    let _ = std::fs::remove_file(&done_path);
    if !write_atomic(&dir.join("request.json"), &serde_json::to_vec(&req).unwrap_or_default()) {
        let _ = std::fs::remove_file(&claim);
        return None;
    }
    let busy = dir.join("busy.json");
    let t_sent = Instant::now();
    let code: Option<u8> = loop {
        if let Some(code) = std::fs::read(&done_path).ok().and_then(|b| serde_json::from_slice::<i32>(&b).ok()) {
            break Some(code as u8);
        }
        // The worker takes the request within a heartbeat, then beats on busy.json while it runs.
        let alive = fresh(&busy) || (t_sent.elapsed() < STALE && fresh(&ready_path));
        if !alive {
            break None;
        }
        std::thread::sleep(Duration::from_millis(20));
    };
    if trace() {
        eprintln!("analyze: warm: client: sent after {:.1?}, answer after {:.1?}", t_sent.duration_since(started), started.elapsed());
    }
    let result = code.map(|code| {
        use std::io::Write;
        let out = std::fs::read(&ready.out).unwrap_or_default();
        let err = std::fs::read(&ready.err).unwrap_or_default();
        let _ = std::io::stdout().write_all(&out);
        let _ = std::io::stdout().flush();
        let _ = std::io::stderr().write_all(&err);
        let _ = std::io::stderr().flush();
        code
    });
    for p in [&ready.out, &ready.err, &done_path, &dir.join("request.json")] {
        let _ = std::fs::remove_file(p);
    }
    let _ = std::fs::remove_file(&claim);
    if result.is_none() && trace() {
        eprintln!("analyze: warm: the worker stopped answering; running here");
    }
    result
}

/// Starts a worker for `root` unless one is waiting or starting, or there is too little memory for one.
pub fn spawn(root: &Path) {
    if std::env::var_os(CHILD_ENV).is_some() && std::env::var_os("DQ_ANALYZE_WARM_SUCCESSOR").is_none() {
        return;
    }
    if matches!(std::env::var("DQ_ANALYZE_WARM").as_deref(), Ok("0") | Ok("off")) {
        return;
    }
    let dir = warm_dir(root);
    let _ = std::fs::create_dir_all(&dir);
    if fresh(&dir.join("ready.json")) || fresh(&dir.join("starting.json")) {
        return;
    }
    // No worker is alive, so a `retire` left here was meant for one that already went: it must not stop the new one.
    let _ = std::fs::remove_file(dir.join("retire"));
    if free_gb() < MIN_FREE_START_GB {
        if trace() {
            eprintln!("analyze: warm: under {} GB of RAM free; no worker started", MIN_FREE_START_GB);
        }
        return;
    }
    let Ok(exe) = std::env::current_exe() else { return };
    let id = exe_id();
    // The worker runs a copy, named by the binary's identity: the build replaces the binary while a worker waits, and a worker of the old
    // build then never serves (its identity no longer matches) and is retired by the next client.
    let copy = dir.join(format!("analyze-{}.exe", &blake3::hash(id.as_bytes()).to_hex()[..16]));
    if !copy.exists() {
        let tmp = copy.with_extension(format!("tmp{}", std::process::id()));
        if std::fs::copy(&exe, &tmp).is_err() || std::fs::rename(&tmp, &copy).is_err() {
            let _ = std::fs::remove_file(&tmp);
            return;
        }
    }
    // Copies of other builds, once no worker runs them (a running one cannot be removed and is left for later).
    if let Ok(rd) = std::fs::read_dir(&dir) {
        for e in rd.flatten() {
            let n = e.file_name().to_string_lossy().to_string();
            if n.starts_with("analyze-") && n.ends_with(".exe") && e.path() != copy {
                let _ = std::fs::remove_file(e.path());
            }
        }
    }
    let tag = format!("{}-{}", std::process::id(), SystemTime::now().duration_since(SystemTime::UNIX_EPOCH).map(|d| d.as_millis()).unwrap_or(0));
    let out = dir.join(format!("out-{tag}.txt"));
    let err = dir.join(format!("err-{tag}.txt"));
    let (Ok(o), Ok(e)) = (std::fs::File::create(&out), std::fs::File::create(&err)) else { return };
    // Mark it starting at once, so a second client does not start another.
    let _ = std::fs::write(dir.join("starting.json"), format!("{}", std::process::id()));
    let mut cmd = std::process::Command::new(&copy);
    cmd.env("DQ_ANALYZE_WARM_EXE", &id);
    cmd.arg("warm-serve").arg("--root").arg(root).arg("--out").arg(&out).arg("--err").arg(&err);
    cmd.env(CHILD_ENV, "1").env_remove("DQ_ANALYZE_WARM_SUCCESSOR");
    cmd.stdin(std::process::Stdio::null()).stdout(o).stderr(e);
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        const DETACHED_PROCESS: u32 = 0x0000_0008;
        const CREATE_NEW_PROCESS_GROUP: u32 = 0x0000_0200;
        const CREATE_NO_WINDOW: u32 = 0x0800_0000;
        const BELOW_NORMAL_PRIORITY_CLASS: u32 = 0x0000_4000;
        cmd.creation_flags(DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP | CREATE_NO_WINDOW | BELOW_NORMAL_PRIORITY_CLASS);
    }
    if cmd.spawn().is_err() {
        let _ = std::fs::remove_file(dir.join("starting.json"));
    }
}

// ------------------------------------------------------------------------------------------------------------------------------------
// Worker

/// `analyze warm-serve --root R --out O --err E`: read the caches, wait for one request, run it with `run` (the ordinary entry point),
/// answer, start a successor, return the exit code.
pub fn serve(argv: &[String], run: impl FnOnce(Vec<String>) -> u8) -> u8 {
    let arg = |name: &str| argv.iter().position(|a| a == name).and_then(|i| argv.get(i + 1)).map(PathBuf::from);
    let (Some(root), Some(out), Some(err)) = (arg("--root"), arg("--out"), arg("--err")) else { return 2 };
    let dir = warm_dir(&root);
    let starting = dir.join("starting.json");
    let ready_path = dir.join("ready.json");
    let stop = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false));
    let beat = |path: PathBuf, stop: std::sync::Arc<std::sync::atomic::AtomicBool>| {
        std::thread::spawn(move || {
            while !stop.load(std::sync::atomic::Ordering::Relaxed) {
                touch(&path);
                // Beat every 2 s, but notice `stop` within 20 ms: the worker joins this thread before it runs a request.
                for _ in 0..100 {
                    if stop.load(std::sync::atomic::Ordering::Relaxed) {
                        break;
                    }
                    std::thread::sleep(Duration::from_millis(20));
                }
            }
        })
    };
    let starting_beat = beat(starting.clone(), stop.clone());
    let t0 = Instant::now();
    crate::prewarm(&root);
    stop.store(true, std::sync::atomic::Ordering::Relaxed);
    let _ = starting_beat.join();
    // Reported with the request (below): anything printed now would land in the stderr the client replays.
    let prewarm_took = t0.elapsed();
    let ready = Ready { pid: std::process::id(), exe: exe_id(), env: env_digest(), out: out.clone(), err: err.clone() };
    let ok = write_atomic(&ready_path, &serde_json::to_vec(&ready).unwrap_or_default());
    let _ = std::fs::remove_file(&starting);
    if !ok {
        return 2;
    }
    let stop = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false));
    let ready_beat = beat(ready_path.clone(), stop.clone());
    let idle = Duration::from_secs(60 * std::env::var("DQ_ANALYZE_WARM_IDLE_MIN").ok().and_then(|v| v.parse().ok()).unwrap_or(DEFAULT_IDLE_MIN));
    let waited = Instant::now();
    let request_path = dir.join("request.json");
    let mut last_memory_check = Instant::now();
    let req: Option<Request> = loop {
        if let Some(r) = std::fs::read(&request_path).ok().and_then(|b| serde_json::from_slice::<Request>(&b).ok()) {
            break Some(r);
        }
        if waited.elapsed() > idle {
            break None;
        }
        if dir.join("retire").exists() {
            let _ = std::fs::remove_file(dir.join("retire"));
            break None;
        }
        if last_memory_check.elapsed() > Duration::from_secs(5) {
            last_memory_check = Instant::now();
            if free_gb() < MIN_FREE_IDLE_GB {
                break None;
            }
        }
        std::thread::sleep(Duration::from_millis(25));
    };
    stop.store(true, std::sync::atomic::Ordering::Relaxed);
    let _ = ready_beat.join();
    let _ = std::fs::remove_file(&ready_path);
    let Some(req) = req else {
        // Idle or short of memory: give the memory back. The next request runs standalone and starts a new worker.
        for p in [&out, &err] {
            let _ = std::fs::remove_file(p);
        }
        return 0;
    };
    let busy = dir.join("busy.json");
    let _ = std::fs::write(&busy, format!("{}", std::process::id()));
    let stop = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false));
    let busy_beat = beat(busy.clone(), stop.clone());
    let _ = std::env::set_current_dir(&req.cwd);
    // The request's environment, exactly: the digest matched, so only variables no run reads can differ.
    let exe = exe_id();
    let keep: std::collections::HashSet<String> = req.env.iter().map(|(k, _)| k.clone()).collect();
    for (k, _) in std::env::vars() {
        if !keep.contains(&k) {
            std::env::remove_var(&k);
        }
    }
    for (k, v) in &req.env {
        std::env::set_var(k, v);
    }
    std::env::set_var(CHILD_ENV, "1");
    std::env::set_var("DQ_ANALYZE_WARM_EXE", exe);
    let t_run = Instant::now();
    let code = run(req.argv);
    if trace() {
        eprintln!("analyze: warm: request served in {:.1?} (caches read in {:.1?}, then waited {:.1?})", t_run.elapsed(), prewarm_took, waited.elapsed());
    }
    {
        use std::io::Write;
        let _ = std::io::stdout().flush();
        let _ = std::io::stderr().flush();
    }
    let _ = write_atomic(&dir.join("done.json"), format!("{}", code).as_bytes());
    stop.store(true, std::sync::atomic::Ordering::Relaxed);
    let _ = busy_beat.join();
    let _ = std::fs::remove_file(&busy);
    // The next request's worker reads the caches this run just wrote.
    std::env::set_var("DQ_ANALYZE_WARM_SUCCESSOR", "1");
    spawn(&root);
    code
}

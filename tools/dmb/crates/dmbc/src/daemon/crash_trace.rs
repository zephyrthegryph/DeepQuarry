//! A daemon that dies leaves a trace of its own: a capped per-namespace `stderr.log` under the daemon state directory.
//!
//! `lifecycle.log` is the shared stderr of every daemon, rotated by size and long since overwritten when someone asks why
//! one namespace's daemon vanished mid-build. This module adds, per namespace (`<state>/<namespace or "default">/`):
//! - `stderr.log`: one line per start, every panic with its thread, location, message and a forced backtrace, and on
//!   Windows the code and address of an unhandled fatal exception (stack overflow, access violation). Capped at 1 MiB
//!   (rotated once to `stderr.log.1`); a namespace directory untouched for 14 days is removed by the next daemon start.
//! - `running.json`: written at start, removed on a clean exit. A start that finds one whose process is gone records
//!   "previous daemon pid N died without a clean shutdown" with its start time and last request, so even a death with no
//!   panic (a kill, an abort, an out-of-memory exit) is visible next time.
//! - `last_request.txt`: the project and variant of the request in flight, overwritten at each request start.
use std::{
    fs,
    io::Write,
    path::{Path, PathBuf},
    sync::{Mutex, OnceLock},
    time::{Duration, SystemTime},
};

const LOG_CAP_BYTES: u64 = 1 << 20;
const NAMESPACE_MAX_AGE: Duration = Duration::from_secs(14 * 24 * 3600);

static DIR: OnceLock<PathBuf> = OnceLock::new();
static WRITE: Mutex<()> = Mutex::new(());

fn namespace_label() -> String {
    std::env::var("DMB_DAEMON_NAMESPACE")
        .ok()
        .filter(|name| {
            !name.is_empty()
                && name.len() <= 64
                && name.bytes().all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || byte == b'-')
        })
        .unwrap_or_else(|| "default".to_owned())
}
fn stamp() -> String {
    format!("[{}ms pid={}]", super::resident::now_ms(), std::process::id())
}
/// Append one entry, rotating at the cap. Never fails the caller: this is a diagnostic.
fn append(dir: &Path, text: &str) {
    let _guard = WRITE.lock().unwrap_or_else(|poison| poison.into_inner());
    let log = dir.join("stderr.log");
    if fs::metadata(&log).is_ok_and(|meta| meta.len() > LOG_CAP_BYTES) {
        let _ = fs::remove_file(dir.join("stderr.log.1"));
        let _ = fs::rename(&log, dir.join("stderr.log.1"));
    }
    if let Ok(mut file) = fs::OpenOptions::new().create(true).append(true).open(&log) {
        let _ = file.write_all(text.as_bytes());
        let _ = file.write_all(b"\n");
    }
}
/// Remove other namespaces' directories that nothing has touched for the age cap.
fn prune_old_namespaces(state: &Path, own: &str, gone: &dyn Fn(u32) -> bool, now: SystemTime) {
    let Ok(entries) = fs::read_dir(state) else { return };
    for entry in entries.flatten() {
        let name = entry.file_name().to_string_lossy().into_owned();
        let path = entry.path();
        if name == own || name == "live" || !path.is_dir() || !path.join("stderr.log").exists() {
            continue;
        }
        let modified = [path.join("stderr.log"), path.join("running.json")]
            .iter()
            .filter_map(|file| fs::metadata(file).and_then(|meta| meta.modified()).ok())
            .max();
        let old = modified.is_some_and(|time| now.duration_since(time).is_ok_and(|age| age > NAMESPACE_MAX_AGE));
        let running = fs::read_to_string(path.join("running.json"))
            .ok()
            .and_then(|text| marker_pid(&text))
            .is_some_and(|pid| !gone(pid));
        if old && !running {
            let _ = fs::remove_dir_all(&path);
        }
    }
}
fn marker_pid(text: &str) -> Option<u32> {
    text.split("\"pid\":").nth(1)?.split(|c: char| !c.is_ascii_digit()).find(|part| !part.is_empty())?.parse().ok()
}
/// Record a predecessor that died without removing its marker, then write this daemon's marker.
fn start_in(dir: &Path, gone: &dyn Fn(u32) -> bool) {
    let _ = fs::create_dir_all(dir);
    let marker = dir.join("running.json");
    if let Ok(previous) = fs::read_to_string(&marker) {
        if let Some(pid) = marker_pid(&previous).filter(|pid| *pid != std::process::id() && gone(*pid)) {
            let last = fs::read_to_string(dir.join("last_request.txt")).unwrap_or_default();
            append(
                dir,
                &format!(
                    "{} previous daemon pid={pid} died without a clean shutdown; marker={}; last request: {}",
                    stamp(),
                    previous.trim(),
                    last.trim()
                ),
            );
        }
    }
    let exe = std::env::current_exe().map(|path| path.display().to_string()).unwrap_or_default();
    let _ = fs::write(
        &marker,
        format!(
            "{{\"pid\":{},\"started_ms\":{},\"exe\":{:?}}}",
            std::process::id(),
            super::resident::now_ms(),
            exe
        ),
    );
    append(dir, &format!("{} daemon start exe={exe}", stamp()));
}
fn panic_text(info: &std::panic::PanicHookInfo<'_>) -> String {
    let payload = info
        .payload()
        .downcast_ref::<&str>()
        .map(|text| (*text).to_owned())
        .or_else(|| info.payload().downcast_ref::<String>().cloned())
        .unwrap_or_else(|| "<non-string payload>".to_owned());
    let location = info.location().map_or_else(|| "<unknown>".to_owned(), ToString::to_string);
    let thread = std::thread::current();
    format!(
        "{} PANIC thread={:?} at {location}: {payload}\n{}",
        stamp(),
        thread.name().unwrap_or("<unnamed>"),
        std::backtrace::Backtrace::force_capture()
    )
}
/// Keeps the marker for the daemon's lifetime; a clean return from `serve` removes it.
pub(super) struct Guard(PathBuf);
impl Drop for Guard {
    fn drop(&mut self) {
        append(&self.0, &format!("{} daemon clean exit", stamp()));
        let _ = fs::remove_file(self.0.join("running.json"));
    }
}
/// Install the per-namespace log, the panic hook and (Windows) the fatal-exception filter.
pub(super) fn install() -> Guard {
    let state = super::resident::state_dir();
    let label = namespace_label();
    let dir = state.join(&label);
    prune_old_namespaces(&state, &label, &|pid| super::resident::process_gone(pid), SystemTime::now());
    start_in(&dir, &|pid| super::resident::process_gone(pid));
    let _ = DIR.set(dir.clone());
    let previous = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        if let Some(dir) = DIR.get() {
            append(dir, &panic_text(info));
        }
        previous(info);
    }));
    #[cfg(windows)]
    fatal::install(&dir);
    Guard(dir)
}
/// The request now in flight, for the next start to quote if this daemon dies during it.
pub(super) fn note_request(description: &str) {
    if let Some(dir) = DIR.get() {
        let _ = fs::write(dir.join("last_request.txt"), format!("{} {description}", stamp()));
    }
}

#[cfg(windows)]
mod fatal {
    use std::{ffi::c_void, io::Write, path::Path, sync::OnceLock};
    static LOG: OnceLock<std::path::PathBuf> = OnceLock::new();
    #[repr(C)]
    struct ExceptionRecord {
        code: u32,
        flags: u32,
        chained: *mut ExceptionRecord,
        address: *mut c_void,
    }
    #[repr(C)]
    struct ExceptionPointers {
        record: *mut ExceptionRecord,
        context: *mut c_void,
    }
    #[link(name = "kernel32")]
    unsafe extern "system" {
        fn SetUnhandledExceptionFilter(
            filter: Option<unsafe extern "system" fn(*mut ExceptionPointers) -> i32>,
        ) -> *mut c_void;
    }
    unsafe extern "system" fn filter(pointers: *mut ExceptionPointers) -> i32 {
        // Best effort on a possibly exhausted stack: no formatting machinery beyond one short line.
        if let (Some(dir), false) = (LOG.get(), pointers.is_null()) {
            let record = unsafe { (*pointers).record };
            if !record.is_null() {
                let (code, address) = unsafe { ((*record).code, (*record).address as usize) };
                if let Ok(mut file) = std::fs::OpenOptions::new().append(true).open(dir) {
                    let _ = writeln!(file, "FATAL EXCEPTION code={code:#010x} address={address:#x} pid={}", std::process::id());
                }
            }
        }
        0 // EXCEPTION_CONTINUE_SEARCH: the process still dies exactly as it did before.
    }
    pub(super) fn install(dir: &Path) {
        let _ = LOG.set(dir.join("stderr.log"));
        unsafe {
            SetUnhandledExceptionFilter(Some(filter));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn scratch(label: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("dmbc-crash-trace-{label}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }
    #[test]
    fn a_predecessor_marker_without_a_live_process_is_reported_once_with_its_last_request() {
        let dir = scratch("marker");
        fs::write(dir.join("running.json"), "{\"pid\":4242,\"started_ms\":1}").unwrap();
        fs::write(dir.join("last_request.txt"), "compile deepquarry.dme").unwrap();
        start_in(&dir, &|pid| pid == 4242);
        let log = fs::read_to_string(dir.join("stderr.log")).unwrap();
        assert!(log.contains("previous daemon pid=4242 died without a clean shutdown"), "{log}");
        assert!(log.contains("compile deepquarry.dme"), "{log}");
        // The new marker replaced the old one, so the next start has nothing to report.
        start_in(&dir, &|_| false);
        let again = fs::read_to_string(dir.join("stderr.log")).unwrap();
        assert_eq!(again.matches("died without a clean shutdown").count(), 1, "{again}");
    }
    #[test]
    fn a_live_predecessor_is_not_reported_dead() {
        let dir = scratch("live");
        fs::write(dir.join("running.json"), "{\"pid\":4242}").unwrap();
        start_in(&dir, &|_| false);
        let log = fs::read_to_string(dir.join("stderr.log")).unwrap();
        assert!(!log.contains("died without"), "{log}");
    }
    #[test]
    fn the_log_rotates_once_over_its_cap() {
        let dir = scratch("cap");
        fs::write(dir.join("stderr.log"), vec![b'x'; (LOG_CAP_BYTES + 1) as usize]).unwrap();
        append(&dir, "fresh entry");
        assert!(dir.join("stderr.log.1").exists());
        assert_eq!(fs::read_to_string(dir.join("stderr.log")).unwrap(), "fresh entry\n");
    }
    #[test]
    fn a_panic_is_written_with_location_message_and_backtrace() {
        let dir = scratch("panic");
        let (sender, receiver) = std::sync::mpsc::channel();
        let hook_sender = Mutex::new(sender);
        let previous = std::panic::take_hook();
        std::panic::set_hook(Box::new(move |info| {
            let _ = hook_sender.lock().unwrap().send(panic_text(info));
        }));
        let _ = std::panic::catch_unwind(|| panic!("boom for the trace"));
        std::panic::set_hook(previous);
        append(&dir, &receiver.recv().unwrap());
        let log = fs::read_to_string(dir.join("stderr.log")).unwrap();
        assert!(log.contains("PANIC") && log.contains("boom for the trace") && log.contains("crash_trace.rs"), "{log}");
    }
    #[test]
    fn only_old_idle_namespaces_are_pruned() {
        let state = scratch("prune");
        for name in ["old", "fresh", "own"] {
            fs::create_dir_all(state.join(name)).unwrap();
            fs::write(state.join(name).join("stderr.log"), "x").unwrap();
        }
        let later = SystemTime::now() + NAMESPACE_MAX_AGE + Duration::from_secs(3600);
        // "now" is far ahead of every file, so all are old; only the own namespace is kept.
        prune_old_namespaces(&state, "own", &|_| true, later);
        assert!(!state.join("old").exists() && !state.join("fresh").exists());
        assert!(state.join("own").exists());
    }
}

//! Machine-wide resident-daemon registry owned by the daemon itself: idle exit, superseded-version exit, provenance of the
//! running executable, and the lifecycle log. Daemons never replace each other: a client talks only to the daemon of its own
//! compiler version (the endpoint is keyed by image identity), a development build runs in a private namespace, and a daemon
//! leaves only for idleness, for being a superseded version nobody uses, or on an explicit retire request.
//!
//! State lives under `DMB_DAEMON_DIR` (default `E:/dq-cache/dmb-daemon`, else `~/.cache/dq/dmb-daemon`):
//! - `lifecycle.log`: stderr of every daemon; rotated to `lifecycle.log.1` when a daemon starts and it is over 1 MiB.
//! - `live/<pid>.json`: one record per daemon (heartbeat, busy flag, last activity).
//! - `live/<pid>.retire`: a request, from outside the process, that the daemon drain and exit.
use serde::{Deserialize, Serialize};
use std::{
    fs, io,
    path::{Path, PathBuf},
    sync::atomic::{AtomicU64, Ordering},
    time::{Duration, SystemTime, UNIX_EPOCH},
};

const DEFAULT_IDLE_EXIT_SECS: u64 = 3600;
const LOG_ROTATE_BYTES: u64 = 1 << 20;
/// A record whose heartbeat is older than this describes a wedged or dead daemon, not a busy one.
const BEAT_FRESH: Duration = Duration::from_secs(30);

static ACTIVITY_MS: AtomicU64 = AtomicU64::new(0);

pub(super) fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |elapsed| elapsed.as_millis() as u64)
}
/// Called when a connection arrives or a build ends: the LRU key other daemons rank this one by.
pub(super) fn touch() {
    ACTIVITY_MS.store(now_ms(), Ordering::Release);
}

pub fn state_dir() -> PathBuf {
    if let Some(dir) = std::env::var_os("DMB_DAEMON_DIR").filter(|dir| !dir.is_empty()) {
        return PathBuf::from(dir);
    }
    if cfg!(windows) && Path::new("E:/dq-cache").is_dir() {
        return PathBuf::from("E:/dq-cache/dmb-daemon");
    }
    let home = std::env::var_os("USERPROFILE")
        .or_else(|| std::env::var_os("HOME"))
        .map_or_else(std::env::temp_dir, PathBuf::from);
    home.join(".cache").join("dq").join("dmb-daemon")
}

fn parse_idle(value: Option<&str>) -> io::Result<Option<Duration>> {
    match value {
        None => Ok(Some(Duration::from_secs(DEFAULT_IDLE_EXIT_SECS))),
        Some(text) => match text.parse::<u64>() {
            Ok(0) => Ok(None),
            Ok(seconds) => Ok(Some(Duration::from_secs(seconds))),
            Err(_) => Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "DMB_DAEMON_IDLE_EXIT_SECS must be a non-negative integer (0 disables idle exit)",
            )),
        },
    }
}
/// `DMB_DAEMON_IDLE_EXIT_SECS`: seconds without a connection or build before the daemon exits. 0 turns it off.
pub(super) fn idle_exit() -> Option<Duration> {
    parse_idle(std::env::var("DMB_DAEMON_IDLE_EXIT_SECS").ok().as_deref())
        .unwrap_or(Some(Duration::from_secs(DEFAULT_IDLE_EXIT_SECS)))
}

#[derive(Clone, Debug, Serialize, Deserialize)]
struct Record {
    pid: u32,
    exe: String,
    namespace: Option<String>,
    started_ms: u64,
    active_ms: u64,
    beat_ms: u64,
    busy: bool,
    /// True once this daemon drains for exit: new clients wait for it instead of starting a second daemon.
    #[serde(default)]
    retiring: bool,
}

fn live_dir(dir: &Path) -> PathBuf {
    dir.join("live")
}
fn record_path(dir: &Path, pid: u32) -> PathBuf {
    live_dir(dir).join(format!("{pid}.json"))
}
fn retire_flag(dir: &Path, pid: u32) -> PathBuf {
    live_dir(dir).join(format!("{pid}.retire"))
}

/// This daemon's registry record; removed on drop.
pub(super) struct Registration {
    dir: PathBuf,
    record: Record,
}
impl Registration {
    fn write(&self) {
        let path = record_path(&self.dir, self.record.pid);
        let temporary = path.with_extension("tmp");
        let written = serde_json::to_vec(&self.record)
            .map_err(io::Error::other)
            .and_then(|bytes| fs::write(&temporary, bytes))
            .and_then(|()| fs::rename(&temporary, &path));
        if let Err(error) = written {
            super::emit_stderr(format_args!("dmbd registry write failed: {error}"));
        }
    }
    /// Refresh the heartbeat; true when a newer daemon asked this one to retire.
    pub(super) fn beat(&mut self, busy: bool, retiring: bool) -> bool {
        let now = now_ms();
        if busy {
            touch();
        }
        self.record.beat_ms = now;
        self.record.busy = busy;
        self.record.retiring = retiring;
        self.record.active_ms = ACTIVITY_MS.load(Ordering::Acquire).max(self.record.started_ms);
        self.write();
        retire_flag(&self.dir, self.record.pid).exists()
    }
}
impl Drop for Registration {
    fn drop(&mut self) {
        let _ = fs::remove_file(record_path(&self.dir, self.record.pid));
        let _ = fs::remove_file(retire_flag(&self.dir, self.record.pid));
    }
}

/// Register this daemon in the machine registry (heartbeat, busy flag, retire flag). Registration never retires or counts other
/// daemons: a daemon leaves only for idleness (`idle_exit`), for being a superseded version nobody uses (`superseded_idle_due`),
/// or on an explicit `--daemon-retire`. A newcomer never replaces an incumbent; each compiler version has its own daemon and
/// its own sessions, and a development build runs in a private namespace (`isolate_development_build`).
/// Failure to register is logged and never prevents the daemon from serving.
pub(super) fn register() -> Option<Registration> {
    touch();
    let dir = state_dir();
    if let Err(error) = fs::create_dir_all(live_dir(&dir)) {
        super::emit_stderr(format_args!("dmbd registry unavailable ({error}); not registered"));
        return None;
    }
    let started = now_ms();
    let registration = Registration {
        dir: dir.clone(),
        record: Record {
            pid: std::process::id(),
            exe: std::env::current_exe().map_or_else(|_| String::new(), |path| path.display().to_string()),
            namespace: std::env::var("DMB_DAEMON_NAMESPACE").ok(),
            started_ms: started,
            active_ms: started,
            beat_ms: started,
            busy: false,
            retiring: false,
        },
    };
    registration.write();
    super::emit_stderr(format_args!(
        "dmbd registered pid={} provenance={:?} namespace={:?} exe={}",
        registration.record.pid,
        provenance_of_self(),
        registration.record.namespace,
        registration.record.exe
    ));
    Some(registration)
}

/// Where a compiler executable comes from. The shared published layout is `<bin>/v/<id>/dmbc` with `<bin>/current` naming the id
/// every compile uses (tools/build/lib/dmbc_cache.ts).
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Provenance {
    /// The version `<bin>/current` names right now.
    Current,
    /// The version `<bin>/next` names: published and being prewarmed (its session is built for the tree while the current
    /// daemon still serves); it becomes `current` once warm.
    Candidate,
    /// A published version that is neither current nor the candidate: a newer compiler is current.
    Superseded,
    /// Anything else: a worktree build, a cargo output, an explicit `DQ_DMBC_BIN`, a test fixture.
    Development,
}

fn provenance_of(exe: &Path, read_pointer: impl Fn(&Path, &str) -> Option<String>) -> Provenance {
    let (Some(version), Some(versions)) = (exe.parent(), exe.parent().and_then(Path::parent)) else {
        return Provenance::Development;
    };
    let id = version.file_name().and_then(|name| name.to_str()).unwrap_or("");
    let published = versions.file_name().is_some_and(|name| name == "v") && id.len() == 16 && id.bytes().all(|byte| byte.is_ascii_hexdigit());
    let Some(bin) = versions.parent().filter(|_| published) else {
        return Provenance::Development;
    };
    let is = |pointer: &str| read_pointer(bin, pointer).is_some_and(|value| value.eq_ignore_ascii_case(id));
    match read_pointer(bin, "current") {
        Some(_) if is("current") => Provenance::Current,
        Some(_) if is("next") => Provenance::Candidate,
        Some(_) => Provenance::Superseded,
        None => Provenance::Development,
    }
}

pub fn provenance_of_self() -> Provenance {
    std::env::current_exe().map_or(Provenance::Development, |exe| {
        provenance_of(&exe, |bin, pointer| fs::read_to_string(bin.join(pointer)).ok().map(|text| text.trim().to_owned()))
    })
}

/// A development build never touches the daemon of the published compiler: with no caller namespace it gets a private one
/// named after its own image identity, so its daemon, discovery endpoint, sessions and retirement are all its own. Called
/// first thing by `dmbc`, before any endpoint is computed.
pub fn isolate_development_build(identity: u128) {
    if std::env::var_os("DMB_DAEMON_NAMESPACE").is_some() || provenance_of_self() != Provenance::Development {
        return;
    }
    let name = format!("dev-{identity:032x}");
    // Single-threaded at process start; the transport layer reads the namespace back through the environment.
    std::env::set_var("DMB_DAEMON_NAMESPACE", &name[..20]);
}

/// A published version that is not `<bin>/current` is superseded: one latest compiler serves everyone, so the daemon finishes its
/// in-flight builds, refuses new ones and exits as soon as nothing is running; clients resolve `current` per compile and reach the
/// new daemon (an old executable that still gets invoked forwards to it, see `forward_target`).
pub(super) fn superseded(provenance: Provenance) -> bool {
    provenance == Provenance::Superseded
}

/// The latest published compiler, when this executable is a superseded published version: where an old client forwards a request.
pub fn forward_target() -> Option<PathBuf> {
    let exe = std::env::current_exe().ok()?;
    if provenance_of_self() != Provenance::Superseded {
        return None;
    }
    let bin = exe.parent()?.parent()?.parent()?;
    let id = fs::read_to_string(bin.join("current")).ok()?.trim().to_owned();
    let target = bin.join("v").join(&id).join(exe.file_name()?);
    target.is_file().then_some(target)
}

/// A draining daemon of this very executable is still alive and recently heartbeating. A client that finds the endpoint
/// absent must wait for it to exit rather than start a second daemon beside it.
pub fn same_binary_draining() -> bool {
    let Ok(own) = std::env::current_exe() else { return false };
    let own = own.display().to_string();
    let now = now_ms();
    read_records(&state_dir()).iter().any(|record| {
        record.retiring
            && record.pid != std::process::id()
            && same_exe(&record.exe, &own)
            && now.saturating_sub(record.beat_ms) < BEAT_FRESH.as_millis() as u64
            && !wait_exit(record.pid, Duration::ZERO)
    })
}

/// A retiring daemon with no running build for this long exits even if clients still hold connections (queued or hung
/// ones get an error and start again). Without a running build there is nothing to drain.
pub(super) const RETIRE_GRACE: Duration = Duration::from_secs(30);
pub(super) fn retire_exit_due(retiring_for: Duration, running: usize) -> bool {
    running == 0 && retiring_for >= RETIRE_GRACE
}

fn read_records(dir: &Path) -> Vec<Record> {
    let mut records = Vec::new();
    let Ok(entries) = fs::read_dir(live_dir(dir)) else {
        return records;
    };
    for entry in entries.flatten() {
        if entry.path().extension().is_some_and(|extension| extension == "json") {
            if let Some(record) = fs::read(entry.path()).ok().and_then(|bytes| serde_json::from_slice::<Record>(&bytes).ok()) {
                records.push(record);
            }
        }
    }
    records
}

fn same_exe(a: &str, b: &str) -> bool {
    !a.is_empty() && a.replace('\\', "/").eq_ignore_ascii_case(&b.replace('\\', "/"))
}

/// Rotate `lifecycle.log` when a daemon is about to inherit it as stderr.
pub(super) fn rotate_lifecycle_log(dir: &Path) {
    let log = dir.join("lifecycle.log");
    if fs::metadata(&log).is_ok_and(|meta| meta.len() > LOG_ROTATE_BYTES) {
        let _ = fs::remove_file(dir.join("lifecycle.log.1"));
        let _ = fs::rename(&log, dir.join("lifecycle.log.1"));
    }
}

#[cfg(windows)]
mod os {
    use std::{ffi::c_void, time::Duration};
    type Handle = *mut c_void;
    const SYNCHRONIZE: u32 = 0x0010_0000;
    #[link(name = "kernel32")]
    unsafe extern "system" {
        fn OpenProcess(access: u32, inherit: i32, pid: u32) -> Handle;
        fn WaitForSingleObject(handle: Handle, millis: u32) -> u32;
        fn CloseHandle(handle: Handle) -> i32;
    }
    /// True when the process is gone (or never openable) within `timeout`.
    pub fn wait_exit(pid: u32, timeout: Duration) -> bool {
        unsafe {
            let handle = OpenProcess(SYNCHRONIZE, 0, pid);
            if handle.is_null() {
                return true;
            }
            let done = WaitForSingleObject(handle, timeout.as_millis().min(u32::MAX as u128 - 1) as u32) == 0;
            CloseHandle(handle);
            done
        }
    }
}

#[cfg(unix)]
mod os {
    use std::time::Duration;
    pub fn wait_exit(pid: u32, timeout: Duration) -> bool {
        let deadline = std::time::Instant::now() + timeout;
        while std::path::Path::new(&format!("/proc/{pid}")).exists() {
            if std::time::Instant::now() >= deadline {
                return false;
            }
            std::thread::sleep(Duration::from_millis(100));
        }
        true
    }
}

use os::wait_exit;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn idle_exit_default_zero_and_garbage() {
        assert_eq!(parse_idle(None).unwrap(), Some(Duration::from_secs(3600)));
        assert_eq!(parse_idle(Some("0")).unwrap(), None);
        assert_eq!(parse_idle(Some("90")).unwrap(), Some(Duration::from_secs(90)));
        assert!(parse_idle(Some("soon")).is_err());
        assert!(parse_idle(Some("-1")).is_err());
    }

    #[test]
    fn provenance_separates_current_candidate_superseded_and_development_builds() {
        let pointers = |_: &Path, name: &str| match name {
            "current" => Some("ebfc6fb0e7c801a8".to_owned()),
            "next" => Some("aaaaaaaaaaaaaaaa".to_owned()),
            _ => None,
        };
        let exe = |id: &str| PathBuf::from(format!("E:/dq-cache/dmb-bin/v/{id}/dmbc.exe"));
        assert_eq!(provenance_of(&exe("ebfc6fb0e7c801a8"), pointers), Provenance::Current);
        assert_eq!(provenance_of(&exe("aaaaaaaaaaaaaaaa"), pointers), Provenance::Candidate);
        assert_eq!(provenance_of(&exe("3ac37341c288ea49"), pointers), Provenance::Superseded);
        assert_eq!(provenance_of(&PathBuf::from("E:/dq-cache/dmb-bin/dmbc.exe"), pointers), Provenance::Development);
        assert_eq!(provenance_of(&PathBuf::from("E:/projects/dq-wt/x/tools/dmb/target/release/dmbc.exe"), pointers), Provenance::Development);
        assert_eq!(provenance_of(&exe("not-a-version-id!"), pointers), Provenance::Development);
        assert_eq!(provenance_of(&exe("ebfc6fb0e7c801a8"), |_: &Path, _: &str| None), Provenance::Development);
    }

    #[test]
    fn only_a_published_version_that_is_not_current_is_superseded() {
        assert!(superseded(Provenance::Superseded));
        assert!(!superseded(Provenance::Current));
        assert!(!superseded(Provenance::Candidate));
        assert!(!superseded(Provenance::Development));
    }

    #[test]
    fn retiring_daemon_without_builds_exits_after_the_grace_never_during_a_build() {
        assert!(!retire_exit_due(RETIRE_GRACE - Duration::from_secs(1), 0));
        assert!(retire_exit_due(RETIRE_GRACE, 0));
        assert!(!retire_exit_due(Duration::from_secs(3600), 1));
    }

    #[test]
    fn log_rotation_keeps_one_generation_over_the_limit() {
        let dir = std::env::temp_dir().join(format!("dmbd-rotate-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        fs::write(dir.join("lifecycle.log"), vec![b'x'; 10]).unwrap();
        rotate_lifecycle_log(&dir);
        assert!(dir.join("lifecycle.log").exists() && !dir.join("lifecycle.log.1").exists());
        fs::write(dir.join("lifecycle.log"), vec![b'x'; (LOG_ROTATE_BYTES + 1) as usize]).unwrap();
        rotate_lifecycle_log(&dir);
        assert!(!dir.join("lifecycle.log").exists() && dir.join("lifecycle.log.1").exists());
        let _ = fs::remove_dir_all(&dir);
    }
}

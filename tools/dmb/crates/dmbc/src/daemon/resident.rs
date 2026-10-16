//! Machine-wide resident-daemon policy owned by the daemon itself: idle exit, the cap on how many
//! `dmbc --serve-daemon` processes may be resident, and the lifecycle log. None of it depends on a
//! caller-side registry, so daemons spawned by worktree-local binaries, older builds or direct
//! invocations are bounded too.
//!
//! State lives under `DMB_DAEMON_DIR` (default `E:/dq-cache/dmb-daemon`, else `~/.cache/dq/dmb-daemon`):
//! - `lifecycle.log`: stderr of every daemon; rotated to `lifecycle.log.1` when a daemon starts and it is over 1 MiB.
//! - `live/<pid>.json`: one record per daemon of this build or newer (heartbeat, busy flag, last activity).
//! - `live/<pid>.retire`: written by a newer daemon to ask that daemon to drain and exit.
//! - `daemons.lock`: held while a starting daemon counts its peers and retires the surplus.
use fs2::FileExt;
use serde::{Deserialize, Serialize};
use std::{
    fs, io,
    path::{Path, PathBuf},
    sync::atomic::{AtomicU64, Ordering},
    time::{Duration, SystemTime, UNIX_EPOCH},
};

const DEFAULT_IDLE_EXIT_SECS: u64 = 600;
const DEFAULT_MAX_DAEMONS: usize = 2;
const LOG_ROTATE_BYTES: u64 = 1 << 20;
/// A record whose heartbeat is older than this describes a wedged or dead daemon, not a busy one.
const BEAT_FRESH: Duration = Duration::from_secs(30);
const RETIRE_WAIT: Duration = Duration::from_secs(10);

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

fn max_daemons() -> usize {
    std::env::var("DQ_DMBC_MAX_DAEMONS")
        .ok()
        .and_then(|text| text.parse().ok())
        .unwrap_or(DEFAULT_MAX_DAEMONS)
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
    pub(super) fn beat(&mut self, busy: bool) -> bool {
        let now = now_ms();
        if busy {
            touch();
        }
        self.record.beat_ms = now;
        self.record.busy = busy;
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

/// Register this daemon, then bring the machine down to `DQ_DMBC_MAX_DAEMONS` by retiring the least recently used idle peers.
/// Failure to do either is logged and never prevents the daemon from serving.
pub(super) fn register_and_enforce() -> Option<Registration> {
    touch();
    let dir = state_dir();
    if let Err(error) = fs::create_dir_all(live_dir(&dir)) {
        super::emit_stderr(format_args!("dmbd registry unavailable ({error}); resident cap not enforced"));
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
        },
    };
    // Registered before counting so a daemon starting concurrently sees this one as young, never as unknown.
    registration.write();
    if let Err(error) = enforce_cap(&dir, std::process::id(), max_daemons()) {
        super::emit_stderr(format_args!("dmbd resident cap not enforced: {error}"));
    }
    Some(registration)
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

#[derive(Debug, Eq, PartialEq)]
enum Action {
    Keep(u32),
    /// Registered and idle: ask it to drain and exit.
    Retire(u32),
    /// Unregistered (older build or foreign launch) or wedged: its state is unknown, end it.
    Terminate(u32),
}

/// Pure policy: which of `others` to remove so that `others.len() + 1 <= cap`. Least recently used first; a daemon whose
/// fresh heartbeat reports a build is never chosen.
fn choose(others: &[u32], records: &[Record], cap: usize, now: u64) -> Vec<Action> {
    let mut ranked: Vec<(u64, u32, Option<&Record>)> = others
        .iter()
        .map(|&pid| {
            let record = records.iter().find(|record| record.pid == pid);
            (record.map_or(0, |record| record.active_ms), pid, record)
        })
        .collect();
    ranked.sort_by_key(|(active, pid, _)| (*active, *pid));
    let mut resident = others.len() + 1;
    let mut actions = Vec::new();
    for (_, pid, record) in ranked {
        if resident <= cap {
            break;
        }
        match record {
            Some(record) if record.busy && now.saturating_sub(record.beat_ms) < BEAT_FRESH.as_millis() as u64 => {
                actions.push(Action::Keep(pid));
            }
            Some(record) if now.saturating_sub(record.beat_ms) < BEAT_FRESH.as_millis() as u64 => {
                actions.push(Action::Retire(pid));
                resident -= 1;
            }
            _ => {
                actions.push(Action::Terminate(pid));
                resident -= 1;
            }
        }
    }
    actions
}

fn enforce_cap(dir: &Path, own: u32, cap: usize) -> io::Result<()> {
    if cap == 0 {
        return Ok(());
    }
    let lock = fs::OpenOptions::new()
        .create(true)
        .truncate(false)
        .write(true)
        .open(dir.join("daemons.lock"))?;
    let deadline = std::time::Instant::now() + Duration::from_secs(60);
    while lock.try_lock_exclusive().is_err() {
        if std::time::Instant::now() >= deadline {
            return Err(io::Error::other("timed out waiting for daemons.lock"));
        }
        std::thread::sleep(Duration::from_millis(100));
    }
    let outcome = (|| {
        let others: Vec<(u32, String)> = list_daemon_processes()?.into_iter().filter(|(pid, _)| *pid != own).collect();
        let records = read_records(dir);
        // A record whose process is gone is garbage from a daemon that crashed.
        for record in &records {
            if record.pid != own && !others.iter().any(|(pid, _)| *pid == record.pid) {
                let _ = fs::remove_file(record_path(dir, record.pid));
            }
        }
        let pids: Vec<u32> = others.iter().map(|(pid, _)| *pid).collect();
        let actions = choose(&pids, &records, cap, now_ms());
        super::emit_stderr(format_args!(
            "dmbd resident cap pid={own} cap={cap} peers={} actions={}",
            pids.len(),
            actions.len()
        ));
        for action in actions {
            let describe = |pid: u32| {
                let exe = others.iter().find(|(other, _)| *other == pid).map_or("?", |(_, exe)| exe.as_str());
                format!("pid={pid} exe={exe}")
            };
            match action {
                Action::Keep(pid) => super::emit_stderr(format_args!("dmbd resident cap keeping busy daemon {}", describe(pid))),
                Action::Retire(pid) => {
                    let _ = fs::write(retire_flag(dir, pid), b"retire");
                    let gone = wait_exit(pid, RETIRE_WAIT);
                    super::emit_stderr(format_args!(
                        "dmbd resident cap retired idle least-recently-used daemon {} exited={gone}",
                        describe(pid)
                    ));
                }
                Action::Terminate(pid) => {
                    let ended = terminate(pid);
                    super::emit_stderr(format_args!(
                        "dmbd resident cap terminated unregistered daemon {} ended={ended}",
                        describe(pid)
                    ));
                    let _ = fs::remove_file(record_path(dir, pid));
                }
            }
        }
        Ok(())
    })();
    let _ = fs2::FileExt::unlock(&lock);
    outcome
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
    use std::{ffi::c_void, io, process::Command, time::Duration};
    type Handle = *mut c_void;
    const TERMINATE: u32 = 0x0001;
    const SYNCHRONIZE: u32 = 0x0010_0000;
    #[link(name = "kernel32")]
    unsafe extern "system" {
        fn OpenProcess(access: u32, inherit: i32, pid: u32) -> Handle;
        fn WaitForSingleObject(handle: Handle, millis: u32) -> u32;
        fn TerminateProcess(handle: Handle, code: u32) -> i32;
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
    pub fn terminate(pid: u32) -> bool {
        unsafe {
            let handle = OpenProcess(TERMINATE | SYNCHRONIZE, 0, pid);
            if handle.is_null() {
                return true;
            }
            let ok = TerminateProcess(handle, 1) != 0;
            CloseHandle(handle);
            ok
        }
    }
    pub fn list_daemon_processes() -> io::Result<Vec<(u32, String)>> {
        use std::os::windows::process::CommandExt;
        let script = "Get-CimInstance Win32_Process -Filter \"Name LIKE 'dmbc%'\" | Where-Object { $_.CommandLine -like '*--serve-daemon*' } | ForEach-Object { \"$($_.ProcessId)|$($_.ExecutablePath)\" }";
        let output = Command::new("powershell.exe")
            .args(["-NoProfile", "-NonInteractive", "-Command", script])
            .creation_flags(0x0800_0000)
            .output()?;
        if !output.status.success() {
            return Err(io::Error::other(format!("process listing failed: {}", String::from_utf8_lossy(&output.stderr).trim())));
        }
        Ok(parse_listing(&String::from_utf8_lossy(&output.stdout)))
    }
    pub fn parse_listing(text: &str) -> Vec<(u32, String)> {
        text.lines()
            .filter_map(|line| {
                let (pid, exe) = line.trim().split_once('|')?;
                Some((pid.trim().parse().ok()?, exe.to_owned()))
            })
            .collect()
    }
}

#[cfg(unix)]
mod os {
    use std::{io, process::Command, time::Duration};
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
    pub fn terminate(pid: u32) -> bool {
        Command::new("kill").args(["-9", &pid.to_string()]).status().is_ok_and(|status| status.success())
    }
    pub fn list_daemon_processes() -> io::Result<Vec<(u32, String)>> {
        let mut found = Vec::new();
        for entry in std::fs::read_dir("/proc")?.flatten() {
            let Some(pid) = entry.file_name().to_str().and_then(|name| name.parse::<u32>().ok()) else {
                continue;
            };
            let Ok(bytes) = std::fs::read(entry.path().join("cmdline")) else {
                continue;
            };
            let mut arguments = bytes.split(|byte| *byte == 0).map(|part| String::from_utf8_lossy(part).into_owned());
            let program = arguments.next().unwrap_or_default();
            let name = program.rsplit('/').next().unwrap_or("");
            if name.starts_with("dmbc") && arguments.any(|argument| argument == "--serve-daemon") {
                found.push((pid, program));
            }
        }
        Ok(found)
    }
}

use os::{list_daemon_processes, terminate, wait_exit};

#[cfg(test)]
mod tests {
    use super::*;

    fn record(pid: u32, active: u64, beat: u64, busy: bool) -> Record {
        Record { pid, exe: String::new(), namespace: None, started_ms: 0, active_ms: active, beat_ms: beat, busy }
    }

    #[test]
    fn idle_exit_default_zero_and_garbage() {
        assert_eq!(parse_idle(None).unwrap(), Some(Duration::from_secs(600)));
        assert_eq!(parse_idle(Some("0")).unwrap(), None);
        assert_eq!(parse_idle(Some("90")).unwrap(), Some(Duration::from_secs(90)));
        assert!(parse_idle(Some("soon")).is_err());
        assert!(parse_idle(Some("-1")).is_err());
    }

    #[test]
    fn within_cap_removes_nothing() {
        assert!(choose(&[10], &[], 2, 1_000).is_empty());
        assert!(choose(&[], &[], 2, 1_000).is_empty());
    }

    #[test]
    fn surplus_goes_least_recently_used_first_and_unregistered_first_of_all() {
        let records = [record(1, 500, 1_000, false), record(2, 900, 1_000, false), record(3, 100, 1_000, false)];
        // cap 2 with one new daemon: only one peer may stay -> two go, unregistered 4 before LRU 3.
        let actions = choose(&[1, 2, 3, 4], &records, 2, 1_000);
        assert_eq!(actions, vec![Action::Terminate(4), Action::Retire(3), Action::Retire(1)]);
    }

    #[test]
    fn busy_daemon_is_never_chosen_and_stale_heartbeat_is_not_busy() {
        let records = [record(1, 0, 1_000, true), record(2, 10, 1_000, false), record(3, 5, 0, true)];
        let now = 1_000 + BEAT_FRESH.as_millis() as u64 + 5;
        // 3's heartbeat is stale (wedged): terminated, not protected. 1 is stale too at this time.
        let actions = choose(&[1, 2, 3], &records, 1, now);
        assert!(actions.iter().all(|action| !matches!(action, Action::Keep(_))));
        let fresh = choose(&[1, 2], &[record(1, 0, 1_000, true), record(2, 10, 1_000, false)], 1, 1_000);
        assert_eq!(fresh, vec![Action::Keep(1), Action::Retire(2)]);
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

    #[cfg(windows)]
    #[test]
    fn listing_parser_reads_pid_and_path() {
        let parsed = os::parse_listing("123|E:\\x\\dmbc.exe\r\n\r\nbad\r\n456|\r\n");
        assert_eq!(parsed, vec![(123, "E:\\x\\dmbc.exe".to_owned()), (456, String::new())]);
    }
}

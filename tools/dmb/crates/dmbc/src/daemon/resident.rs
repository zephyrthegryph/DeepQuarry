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

const DEFAULT_IDLE_EXIT_SECS: u64 = 3600;
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
            retiring: false,
        },
    };
    // Registered before counting so a daemon starting concurrently sees this one as young, never as unknown.
    registration.write();
    if let Err(error) = enforce_cap(&dir, std::process::id(), max_daemons()) {
        super::emit_stderr(format_args!("dmbd resident cap not enforced: {error}"));
    }
    Some(registration)
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

#[derive(Debug, Eq, PartialEq)]
enum Action {
    Keep(u32),
    /// Registered and idle: ask it to drain and exit (flag file).
    Retire(u32),
    /// Unregistered daemon of this very binary: ask it to drain through its endpoint. Never cuts a running build.
    Drain(u32),
    /// Foreign or older binary with no CPU activity for `CPU_IDLE`: the only case that is ended by force.
    Terminate(u32),
}

/// A daemon this machine has seen burn no CPU for this long is not building.
const CPU_IDLE: Duration = Duration::from_secs(5 * 60);

struct Peer {
    pid: u32,
    exe: String,
    cpu_idle: bool,
}

/// Pure policy: which of `others` to remove so that `others.len() + 1 <= cap`. Least recently used first. A daemon whose fresh
/// heartbeat reports a build is never chosen. A daemon with no live record is asked to drain when it runs `own_exe`, and is
/// killed only when it is a different binary that has shown no CPU activity for `CPU_IDLE`; otherwise it is kept (the cap is soft).
fn choose(others: &[Peer], own_exe: &str, records: &[Record], cap: usize, now: u64) -> Vec<Action> {
    let fresh_ms = BEAT_FRESH.as_millis() as u64;
    let mut ranked: Vec<(u64, &Peer, Option<&Record>)> = others
        .iter()
        .map(|peer| {
            let record = records.iter().find(|record| record.pid == peer.pid);
            (record.map_or(0, |record| record.active_ms), peer, record)
        })
        .collect();
    ranked.sort_by_key(|(active, peer, _)| (*active, peer.pid));
    let mut resident = others.len() + 1;
    let mut actions = Vec::new();
    for (_, peer, record) in ranked {
        if resident <= cap {
            break;
        }
        let pid = peer.pid;
        match record.filter(|record| now.saturating_sub(record.beat_ms) < fresh_ms) {
            Some(record) if record.busy => actions.push(Action::Keep(pid)),
            Some(_) => {
                actions.push(Action::Retire(pid));
                resident -= 1;
            }
            None if same_exe(&peer.exe, own_exe) => {
                actions.push(Action::Drain(pid));
                resident -= 1;
            }
            None if peer.cpu_idle => {
                actions.push(Action::Terminate(pid));
                resident -= 1;
            }
            None => actions.push(Action::Keep(pid)),
        }
    }
    actions
}

fn same_exe(a: &str, b: &str) -> bool {
    !a.is_empty() && a.replace('\\', "/").eq_ignore_ascii_case(&b.replace('\\', "/"))
}

#[derive(Default, Serialize, Deserialize)]
struct CpuSeen(std::collections::BTreeMap<u32, (u64, u64)>);

/// Update the per-pid CPU observations and report which pids have been flat for `CPU_IDLE`.
fn observe_cpu(dir: &Path, pids: &[u32], now: u64) -> std::collections::BTreeSet<u32> {
    let path = dir.join("cpu_seen.json");
    let previous: CpuSeen = fs::read(&path).ok().and_then(|bytes| serde_json::from_slice(&bytes).ok()).unwrap_or_default();
    let mut next = CpuSeen::default();
    let mut idle = std::collections::BTreeSet::new();
    for &pid in pids {
        let Some(cpu) = os::cpu_time(pid) else { continue };
        let changed = match previous.0.get(&pid) {
            Some(&(seen_cpu, changed)) if seen_cpu == cpu => changed,
            _ => now,
        };
        if now.saturating_sub(changed) >= CPU_IDLE.as_millis() as u64 {
            idle.insert(pid);
        }
        next.0.insert(pid, (cpu, changed));
    }
    let _ = serde_json::to_vec(&next).map(|bytes| fs::write(&path, bytes));
    idle
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
        let idle = observe_cpu(dir, &pids, now_ms());
        let peers: Vec<Peer> = others
            .iter()
            .map(|(pid, exe)| Peer { pid: *pid, exe: exe.clone(), cpu_idle: idle.contains(pid) })
            .collect();
        let own_exe = std::env::current_exe().map_or_else(|_| String::new(), |path| path.display().to_string());
        let actions = choose(&peers, &own_exe, &records, cap, now_ms());
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
                Action::Keep(pid) => super::emit_stderr(format_args!("dmbd resident cap keeping daemon (busy, or no CPU-idle proof) {}", describe(pid))),
                Action::Retire(pid) => {
                    let _ = fs::write(retire_flag(dir, pid), b"retire");
                    let gone = wait_exit(pid, RETIRE_WAIT);
                    super::emit_stderr(format_args!(
                        "dmbd resident cap retired idle least-recently-used daemon {} exited={gone}",
                        describe(pid)
                    ));
                }
                Action::Drain(pid) => {
                    let asked = super::retire_namespace();
                    let gone = matches!(asked, Ok(true)) && wait_exit(pid, RETIRE_WAIT);
                    super::emit_stderr(format_args!(
                        "dmbd resident cap asked unregistered same-binary daemon {} to drain (endpoint reply {asked:?}) exited={gone}",
                        describe(pid)
                    ));
                }
                Action::Terminate(pid) => {
                    let ended = terminate(pid);
                    super::emit_stderr(format_args!(
                        "dmbd resident cap terminated foreign-binary daemon {} after {}s without CPU activity ended={ended}",
                        describe(pid),
                        CPU_IDLE.as_secs()
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
    #[repr(C)]
    #[derive(Default)]
    struct FileTime {
        low: u32,
        high: u32,
    }
    #[link(name = "kernel32")]
    unsafe extern "system" {
        fn GetProcessTimes(handle: Handle, create: *mut FileTime, exit: *mut FileTime, kernel: *mut FileTime, user: *mut FileTime) -> i32;
    }
    /// Kernel plus user CPU time in 100 ns units, None when the process cannot be opened.
    pub fn cpu_time(pid: u32) -> Option<u64> {
        unsafe {
            let handle = OpenProcess(0x1000, 0, pid); // PROCESS_QUERY_LIMITED_INFORMATION
            if handle.is_null() {
                return None;
            }
            let (mut c, mut e, mut k, mut u) = (FileTime::default(), FileTime::default(), FileTime::default(), FileTime::default());
            let ok = GetProcessTimes(handle, &mut c, &mut e, &mut k, &mut u) != 0;
            CloseHandle(handle);
            let whole = |t: &FileTime| (u64::from(t.high) << 32) | u64::from(t.low);
            ok.then(|| whole(&k) + whole(&u))
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
    pub fn cpu_time(pid: u32) -> Option<u64> {
        let stat = std::fs::read_to_string(format!("/proc/{pid}/stat")).ok()?;
        let fields: Vec<&str> = stat.rsplit_once(')')?.1.split_whitespace().collect();
        Some(fields.get(11)?.parse::<u64>().ok()? + fields.get(12)?.parse::<u64>().ok()?)
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
        Record { pid, exe: String::new(), namespace: None, started_ms: 0, active_ms: active, beat_ms: beat, busy, retiring: false }
    }

    #[test]
    fn idle_exit_default_zero_and_garbage() {
        assert_eq!(parse_idle(None).unwrap(), Some(Duration::from_secs(3600)));
        assert_eq!(parse_idle(Some("0")).unwrap(), None);
        assert_eq!(parse_idle(Some("90")).unwrap(), Some(Duration::from_secs(90)));
        assert!(parse_idle(Some("soon")).is_err());
        assert!(parse_idle(Some("-1")).is_err());
    }

    fn peer(pid: u32, exe: &str, cpu_idle: bool) -> Peer {
        Peer { pid, exe: exe.to_owned(), cpu_idle }
    }
    const OWN: &str = "E:/dq-cache/dmb-bin/dmbc.exe";

    #[test]
    fn within_cap_removes_nothing() {
        assert!(choose(&[peer(10, OWN, true)], OWN, &[], 2, 1_000).is_empty());
        assert!(choose(&[], OWN, &[], 2, 1_000).is_empty());
    }

    #[test]
    fn registered_idle_retire_lru_first_and_busy_is_never_chosen() {
        let records = [record(1, 500, 1_000, false), record(2, 900, 1_000, false), record(3, 100, 1_000, true)];
        let peers = [peer(1, OWN, false), peer(2, OWN, false), peer(3, OWN, false)];
        assert_eq!(choose(&peers, OWN, &records, 1, 1_000), vec![Action::Keep(3), Action::Retire(1), Action::Retire(2)]);
    }

    #[test]
    fn unregistered_same_binary_drains_and_is_never_killed() {
        let actions = choose(&[peer(4, "e:\\dq-cache\\dmb-bin\\dmbc.exe", true), peer(5, OWN, true)], OWN, &[], 1, 1_000);
        assert_eq!(actions, vec![Action::Drain(4), Action::Drain(5)]);
    }

    #[test]
    fn foreign_binary_is_killed_only_after_cpu_idle_proof() {
        let foreign = "E:/projects/dq-wt/x/tools/dmb/target/release/dmbc.exe";
        assert_eq!(choose(&[peer(6, foreign, false)], OWN, &[], 1, 1_000), vec![Action::Keep(6)]);
        assert_eq!(choose(&[peer(6, foreign, true)], OWN, &[], 1, 1_000), vec![Action::Terminate(6)]);
    }

    #[test]
    fn stale_heartbeat_is_not_trusted_as_busy_but_is_not_killed_either() {
        let now = 1_000 + BEAT_FRESH.as_millis() as u64 + 5;
        let records = [record(1, 0, 1_000, true)];
        assert_eq!(choose(&[peer(1, OWN, false)], OWN, &records, 1, now), vec![Action::Drain(1)]);
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

    #[cfg(windows)]
    #[test]
    fn listing_parser_reads_pid_and_path() {
        let parsed = os::parse_listing("123|E:\\x\\dmbc.exe\r\n\r\nbad\r\n456|\r\n");
        assert_eq!(parsed, vec![(123, "E:\\x\\dmbc.exe".to_owned()), (456, String::new())]);
    }
}

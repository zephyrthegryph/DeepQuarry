use super::{
    control,
    protocol::{self, Reply, Request},
    transport,
};
use std::{
    collections::{BTreeMap, VecDeque},
    io,
    path::PathBuf,
    sync::{
        atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering},
        Arc, Condvar, Mutex,
    },
    time::{Duration, Instant},
};
#[path = "admission_deadline.rs"]
mod admission_deadline;
#[path = "admission_limits.rs"]
mod admission_limits;
#[path = "service_generation_admission.rs"]
mod generation_admission;
#[path = "service_request_threads.rs"]
mod request_threads;
#[path = "service_housekeeping.rs"]
mod housekeeping;
#[cfg(test)]
#[path = "service_queue_tests.rs"]
mod queue_tests;
#[path = "soft_memory.rs"]
mod soft_memory;
/// Hosts are retained per manifest and semantic configuration. Supersession also
/// requires the same logical destination. Different defines targeting one file
/// serialize through the existing output lease but do not cancel each other.
#[derive(Clone, Copy, Debug, Eq, PartialEq, Ord, PartialOrd)]
enum RequestCommand {
    Analyze,
    AnalyzeBodies,
    AnalyzeResolved,
    PrepareQuery,
    Compile,
}
impl From<crate::request::BuildCommand> for RequestCommand {
    fn from(command: crate::request::BuildCommand) -> Self {
        use crate::request::BuildCommand;
        match command {
            BuildCommand::Analyze => Self::Analyze,
            BuildCommand::AnalyzeBodies => Self::AnalyzeBodies,
            BuildCommand::AnalyzeResolved => Self::AnalyzeResolved,
            BuildCommand::PrepareQuery => Self::PrepareQuery,
            BuildCommand::Compile => Self::Compile,
        }
    }
}
/// What an engine template is, for keying sessions and requests: its bytes, not where a checkout keeps it. Every worktree has its
/// own copy of `native_template.bin`, and keying by path gave each worktree its own ~10 GB session of the same variant (reported
/// as `variant-mismatch` misses and, with two of them resident, `hard-memory-limit` evictions). An unreadable file falls back to
/// its path so a bad request still gets a session of its own and fails the same way it always did.
#[derive(Clone, Debug, Eq, PartialEq, Ord, PartialOrd)]
enum EngineIdentity {
    Content(u128),
    Path(PathBuf),
}
impl EngineIdentity {
    fn of(path: &std::path::Path) -> Self {
        match std::fs::read(path) {
            Ok(bytes) => Self::Content(xxhash_rust::xxh3::xxh3_128(&bytes)),
            Err(_) => Self::Path(path.to_path_buf()),
        }
    }
}
#[derive(Clone, Debug, Eq, PartialEq, Ord, PartialOrd)]
struct RequestKey {
    command: RequestCommand,
    defines: BTreeMap<String, String>,
    engine: Option<EngineIdentity>,
    bootstrap: bool,
    destination: PathBuf,
    output_store: Option<PathBuf>,
    replay: Option<PathBuf>,
    record_inputs: Option<PathBuf>,
}
impl RequestKey {
    fn of(request: &crate::request::BuildRequest, manifest: &std::path::Path) -> Self {
        Self {
            command: request.command.into(),
            defines: request.defines.clone(),
            engine: request.engine_template.as_deref().map(EngineIdentity::of),
            bootstrap: request.bootstrap_catalog,
            destination: request.artifact_directory.as_ref().map_or_else(
                || manifest.to_path_buf(),
                |directory| {
                    manifest
                        .file_name()
                        .map_or_else(|| manifest.to_path_buf(), |name| directory.join(name))
                },
            ),
            output_store: request.output_store.clone(),
            replay: request.replay_inputs.clone(),
            record_inputs: request.record_inputs.clone(),
        }
    }
}
struct LatestRequest {
    slot: Arc<Slot>,
    key: RequestKey,
    token: control::Cancellation,
}
impl LatestRequest {
    fn register(slot: &Arc<Slot>, key: RequestKey, token: control::Cancellation) -> Self {
        if let Some(previous) = slot
            .newest
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .insert(key.clone(), token.clone())
        {
            previous.cancel();
        }
        Self {
            slot: Arc::clone(slot),
            key,
            token,
        }
    }
}
impl Drop for LatestRequest {
    fn drop(&mut self) {
        let mut newest = self.slot.newest.lock().unwrap_or_else(|e| e.into_inner());
        if newest
            .get(&self.key)
            .is_some_and(|token| token.same_request(&self.token))
        {
            newest.remove(&self.key);
        }
    }
}
struct Slot {
    request_serial: Mutex<()>,
    host: Mutex<crate::runner_host::BuildHost>,
    newest: Mutex<BTreeMap<RequestKey, control::Cancellation>>,
    last: Mutex<Instant>,
    idle_tier: AtomicUsize,
}
/// A session is a project directory under one compiler (engine bytes, bootstrap): not a manifest file and not a define set.
/// Production, test and bench builds of one tree, and a worktree switch, are different inputs of the same session; the host keeps
/// each (project, defines) variant's own state (`BuildHost::engine`, `switch_variant`) and shares everything define-independent.
#[derive(Clone, Debug, Eq, PartialEq, Ord, PartialOrd)]
struct SessionKey {
    /// The project directory (the compile root); a manifest path is reduced to its directory.
    manifest: PathBuf,
    engine: Option<EngineIdentity>,
    bootstrap: bool,
}
impl SessionKey {
    fn of(
        manifest: PathBuf,
        config: Option<&crate::request::BuildRequest>,
    ) -> Self {
        Self {
            manifest: session_root(manifest),
            engine: config.and_then(|request| request.engine_template.as_deref()).map(EngineIdentity::of),
            bootstrap: config.is_some_and(|request| request.bootstrap_catalog),
        }
    }
}
/// The directory a manifest belongs to; anything that is not a `.dme` file path is already a directory.
fn session_root(manifest: PathBuf) -> PathBuf {
    let is_manifest = manifest
        .extension()
        .is_some_and(|extension| extension.eq_ignore_ascii_case("dme"));
    match manifest.parent() {
        Some(parent) if is_manifest && !parent.as_os_str().is_empty() => parent.to_path_buf(),
        _ => manifest,
    }
}
/// Why recent sessions disappeared (bounded, newest last), so the next compile of that session can say why it missed.
static EVICTIONS: Mutex<VecDeque<(SessionKey, String)>> = Mutex::new(VecDeque::new());
const EVICTION_LEDGER: usize = 64;
fn note_eviction(key: &SessionKey, why: &str) {
    let mut ledger = EVICTIONS.lock().unwrap_or_else(|e| e.into_inner());
    ledger.retain(|(old, _)| old != key);
    ledger.push_back((key.clone(), why.to_string()));
    while ledger.len() > EVICTION_LEDGER {
        ledger.pop_front();
    }
}
fn take_eviction(key: &SessionKey) -> Option<String> {
    let mut ledger = EVICTIONS.lock().unwrap_or_else(|e| e.into_inner());
    let at = ledger.iter().position(|(old, _)| old == key)?;
    ledger.remove(at).map(|(_, why)| why)
}
/// How long a build waits for memory before it is admitted anyway.
const MEMORY_WAIT: Duration = Duration::from_secs(300);
const HOT_GROWTH_DEFAULT: u64 = 2_000_000_000;
const COLD_GROWTH_DEFAULT: u64 = 12_000_000_000;
/// What the last build of each (project, hot or cold) grew the process by, so admission asks for what a build really needs.
static GROWTH: Mutex<BTreeMap<(PathBuf, bool), u64>> = Mutex::new(BTreeMap::new());
fn expected_growth(key: &SessionKey, hot: bool) -> u64 {
    let learned = GROWTH.lock().unwrap_or_else(|e| e.into_inner()).get(&(key.manifest.clone(), hot)).copied();
    // 15% over the last observation: growth varies a little build to build.
    learned.map_or(if hot { HOT_GROWTH_DEFAULT } else { COLD_GROWTH_DEFAULT }, |bytes| bytes + bytes / 7)
}
fn note_growth(key: &SessionKey, hot: bool, growth: u64) {
    GROWTH.lock().unwrap_or_else(|e| e.into_inner()).insert((key.manifest.clone(), hot), growth);
}
/// Samples the process's private bytes every 100 ms while a request runs and keeps the maximum.
struct PeakSampler {
    peak: Arc<AtomicU64>,
    stop: Arc<AtomicBool>,
    thread: Option<std::thread::JoinHandle<()>>,
}
impl PeakSampler {
    fn start() -> Self {
        let peak = Arc::new(AtomicU64::new(0));
        let stop = Arc::new(AtomicBool::new(false));
        let (peak_in, stop_in) = (Arc::clone(&peak), Arc::clone(&stop));
        let thread = std::thread::Builder::new()
            .name("dmbd-peak-sampler".into())
            .spawn(move || {
                while !stop_in.load(Ordering::Acquire) {
                    if let Some(bytes) = transport::private_bytes() {
                        peak_in.fetch_max(bytes, Ordering::AcqRel);
                    }
                    std::thread::sleep(Duration::from_millis(100));
                }
            })
            .ok();
        Self { peak, stop, thread }
    }
    fn finish(mut self) -> Option<u64> {
        self.stop.store(true, Ordering::Release);
        if let Some(thread) = self.thread.take() {
            let _ = thread.join();
        }
        Some(self.peak.load(Ordering::Acquire)).filter(|bytes| *bytes > 0)
    }
}
impl Slot {
    fn lock_request_until(
        &self,
        deadline: &admission_deadline::AdmissionDeadline,
    ) -> io::Result<std::sync::MutexGuard<'_, ()>> {
        loop {
            control::checkpoint()?;
            let remaining = deadline.remaining(Instant::now())?;
            match self.request_serial.try_lock() {
                Ok(guard) => return Ok(guard),
                Err(std::sync::TryLockError::Poisoned(error)) => return Ok(error.into_inner()),
                Err(std::sync::TryLockError::WouldBlock) => {}
            }
            std::thread::sleep(Duration::from_millis(20).min(remaining));
        }
    }
    #[cfg(test)]
    fn lock_host(&self) -> io::Result<std::sync::MutexGuard<'_, crate::runner_host::BuildHost>> {
        self.lock_host_until(&admission_deadline::AdmissionDeadline::new(Instant::now()))
    }
    fn lock_host_until(
        &self,
        deadline: &admission_deadline::AdmissionDeadline,
    ) -> io::Result<std::sync::MutexGuard<'_, crate::runner_host::BuildHost>> {
        loop {
            control::checkpoint()?;
            let remaining = deadline.remaining(Instant::now())?;
            match self.host.try_lock() {
                Ok(host) => return Ok(host),
                Err(std::sync::TryLockError::Poisoned(error)) => return Ok(error.into_inner()),
                Err(std::sync::TryLockError::WouldBlock) => {}
            }
            std::thread::sleep(Duration::from_millis(20).min(remaining));
        }
    }
}
struct Shared {
    engines: Arc<crate::runner_host::EnginePayloads>,
    executors: Arc<crate::runner_host::ExecutorPools>,
    procedures: Arc<crate::symbolic::shared_procedure_code::SharedProcedureCode>,
    store: Arc<crate::shared_store::SharedStore>,
    compiler: u128,
    retiring: AtomicBool,
    slots: Mutex<BTreeMap<SessionKey, Arc<Slot>>>,
    running: Mutex<usize>,
    workers: Mutex<usize>,
    max_workers: usize,
    soft_private_bytes: u64,
    capacity: Condvar,
    connections: AtomicUsize,
}
impl Shared {
    /// Soft pressure: the machine is running short of available memory (adaptive budget), or this process passed its fixed soft limit.
    fn under_memory_pressure(&self, bytes: u64) -> bool {
        soft_memory::adaptive_pressure(bytes).map_or(bytes >= self.soft_private_bytes, |pressure| pressure.soft)
    }
    fn over_hard_ceiling(&self, bytes: u64) -> bool {
        soft_memory::adaptive_pressure(bytes)
            .map_or_else(|| bytes >= soft_memory::hard(self.soft_private_bytes).unwrap_or(u64::MAX), |pressure| pressure.hard)
    }
    /// True when available physical memory is below half the reserve: even the newest session may be degraded.
    fn memory_emergency(&self) -> bool {
        soft_memory::adaptive_pressure(transport::private_bytes().unwrap_or(0)).is_some_and(|pressure| pressure.emergency)
    }
    /// Admission by memory (adaptive budget only). A compile is expected to grow the process by `expected_growth` (what this
    /// session's last build of the same kind grew it, else a conservative default); it starts only while the machine would still
    /// have the reserve free afterwards. When it would not: idle sessions of other projects are released least recently used
    /// first, then the request waits for running builds to finish. Progress guarantee: with nothing left to release or wait for,
    /// or after `MEMORY_WAIT`, the build is admitted anyway and the shortfall is logged, so a machine that is simply too small
    /// slows down instead of refusing every build.
    fn await_memory(&self, key: &SessionKey, hot: bool) -> io::Result<()> {
        // The daemon-wide budget applies to every mode: a build is admitted against what it is expected to add.
        self.enforce_retained_budget(Some(key), expected_growth(key, hot).min(soft_memory::retained_budget() / 2));
        let Some(reserve) = soft_memory::adaptive_reserve() else { return Ok(()) };
        let need = expected_growth(key, hot);
        let started = Instant::now();
        loop {
            let Some(available) = soft_memory::available() else { return Ok(()) };
            if available >= reserve.saturating_add(need) {
                return Ok(());
            }
            control::checkpoint()?;
            let private = transport::private_bytes().unwrap_or(0);
            if soft_memory::admission_may_shed(available, need, reserve, private, soft_memory::retained_budget())
                && self.shed_one_idle(key, available, need, reserve)
            {
                continue;
            }
            let running = *self.running.lock().unwrap_or_else(|e| e.into_inner());
            if running == 0 || started.elapsed() >= MEMORY_WAIT {
                super::emit_stderr(format_args!(
                    "dmbd memory admission: admitting {} {} build with {:.1} GB available, needs {:.1} GB above a {:.1} GB reserve (nothing left to release, running builds={running}, waited {:.0}s)",
                    key.manifest.display(),
                    if hot { "hot" } else { "cold" },
                    available as f64 / 1e9,
                    need as f64 / 1e9,
                    reserve as f64 / 1e9,
                    started.elapsed().as_secs_f64()
                ));
                return Ok(());
            }
            std::thread::sleep(Duration::from_millis(200));
        }
    }
    /// Release the least recently used idle session of another project. False when there is none to release.
    fn shed_one_idle(&self, keep: &SessionKey, available: u64, need: u64, reserve: u64) -> bool {
        let victim = {
            let mut slots = self.slots.lock().unwrap_or_else(|e| e.into_inner());
            let key = slots
                .iter()
                .filter(|(other, slot)| *other != keep && Arc::strong_count(slot) == 1 && slot.host.try_lock().is_ok())
                .min_by_key(|(_, slot)| *slot.last.lock().unwrap_or_else(|e| e.into_inner()))
                .map(|(other, _)| other.clone());
            key.and_then(|key| slots.remove(&key).map(|slot| (key, slot)))
        };
        let Some((key, slot)) = victim else { return false };
        note_eviction(&key, "memory-pressure");
        let before = transport::private_bytes();
        drop(slot);
        let after = self.reclaim_allocator(transport::private_bytes());
        super::emit_stderr(format_args!(
            "dmbd memory admission: released idle session {} for {} (available {:.1} GB, build needs {:.1} GB above a {:.1} GB reserve) private-before={before:?} private-after={after:?}",
            key.manifest.display(),
            keep.manifest.display(),
            available as f64 / 1e9,
            need as f64 / 1e9,
            reserve as f64 / 1e9
        ));
        true
    }
    /// The daemon-wide retained-memory budget (`soft_memory::retained_budget`, default 20 GB): while the process holds more private
    /// memory than that and another idle session exists, release the least recently used idle session whole. The most recently used
    /// session and any session that is building are never released for the budget, so a lone session larger than the budget stays
    /// resident. `reserve` is memory a build about to be admitted will add. True when anything was released.
    fn enforce_retained_budget(&self, keep: Option<&SessionKey>, reserve: u64) -> bool {
        let budget = soft_memory::retained_budget();
        let mut released = false;
        loop {
            let Some(private) = transport::private_bytes() else { return released };
            if private.saturating_add(reserve) <= budget {
                return released;
            }
            let victim = {
                let mut slots = self.slots.lock().unwrap_or_else(|e| e.into_inner());
                let sessions: Vec<(SessionKey, Instant, bool)> = slots
                    .iter()
                    .map(|(key, slot)| {
                        let idle = Arc::strong_count(slot) == 1 && slot.host.try_lock().is_ok();
                        // The session being admitted counts as the newest even before its use is recorded.
                        let last = if keep == Some(key) { Instant::now() } else { *slot.last.lock().unwrap_or_else(|e| e.into_inner()) };
                        (key.clone(), last, idle)
                    })
                    .collect();
                soft_memory::budget_victim(&sessions).and_then(|key| slots.remove(&key).map(|slot| (key, slot)))
            };
            let Some((key, slot)) = victim else { return released };
            note_eviction(&key, "memory-budget");
            drop(slot);
            let after = self.reclaim_allocator(transport::private_bytes());
            released = true;
            super::emit_stderr(format_args!(
                "dmbd memory budget: released least recently used idle session {} (budget {:.1} GB, private-before={private} private-after={after:?}, reserved for admission {:.1} GB)",
                key.manifest.display(),
                budget as f64 / 1e9,
                reserve as f64 / 1e9
            ));
            if after.is_none_or(|bytes| bytes >= private) {
                // The release returned nothing (allocator slack): do not walk every remaining session on one sample.
                return released;
            }
        }
    }
    /// Return freed pages to the OS before any pressure decision. Freed-but-
    /// committed allocator pages (transient composition/encode peaks, exited
    /// worker heaps) count as private bytes yet hold no retained data, and an
    /// idle process never runs the allocator's delayed purge by itself.
    fn reclaim_allocator(&self, before: Option<u64>) -> Option<u64> {
        let started = Instant::now();
        let commit_before = dm_profile::allocator_commit_bytes();
        dm_profile::reclaim_unused_allocator_pages();
        let mut after = transport::private_bytes();
        let mut joined_workers = false;
        if after.is_some_and(|bytes| self.over_hard_ceiling(bytes)) {
            // Only above the hard ceiling: idle pool workers own thread heaps
            // that later builds reuse, so joining them abandons those pages.
            self.executors.trim(Instant::now(), true);
            dm_profile::reclaim_unused_allocator_pages();
            after = transport::private_bytes();
            joined_workers = true;
        }
        // A reclaim that freed nothing is the common case after every build and under pressure; logging each one
        // grew lifecycle.log to megabytes of identical lines. Log only reclaims that returned memory or joined workers.
        let freed = match (before, after) {
            (Some(before), Some(after)) => before.saturating_sub(after),
            _ => 0,
        };
        if joined_workers || freed >= RECLAIM_LOG_MIN_BYTES {
            super::emit_stderr(format_args!(
                "dmbd allocator reclaim private-before={before:?} private-after={after:?} freed={freed} mimalloc-commit-before={commit_before:?} mimalloc-commit-after={:?} joined-idle-workers={joined_workers} rust-requested-live={} seconds={:.6}",
                dm_profile::allocator_commit_bytes(),
                housekeeping::allocations::requested_live(),
                started.elapsed().as_secs_f64()
            ));
        }
        if std::env::var_os("DMB_DAEMON_ALLOCATOR_STATS").is_some() {
            dm_profile::print_allocator_stats();
        }
        if std::env::var_os("DMB_MEM_MARKS").is_some_and(|value| value != "0") {
            super::emit_stderr(format_args!("{}", self.store.report()));
        }
        housekeeping::allocations::dump_sites(&format!("after_request private={after:?}"));
        after
    }
    fn reset_host(&self, host: &mut crate::runner_host::BuildHost) {
        *host = crate::runner_host::BuildHost::with_daemon_owners(
            Arc::clone(&self.engines),
            Arc::clone(&self.executors),
            Arc::clone(&self.procedures),
            Arc::clone(&self.store),
        );
        // The replacement holds one handle; with no other session the released session's records have no user left.
        self.store.records.clear_if_held_by_at_most(1);
    }
    /// What the daemon holds for `key` right now: a usable retained session (hot) or the reason there is none.
    fn probe(&self, key: &SessionKey) -> crate::compile_stats::SessionState {
        let slots = self.slots.lock().unwrap_or_else(|e| e.into_inner());
        let sessions = slots.len();
        let miss = match slots.get(key) {
            Some(slot) => {
                let tier = slot.idle_tier.load(Ordering::Acquire);
                // A host busy with another request will have built by the time this one runs: count it as retained.
                let retained = match slot.host.try_lock() {
                    Ok(host) => host.retains_patch_base(),
                    Err(std::sync::TryLockError::Poisoned(_)) => false,
                    Err(std::sync::TryLockError::WouldBlock) => true,
                };
                if tier >= 3 {
                    Some(format!("degraded-tier-{tier}"))
                } else if !retained {
                    Some(take_eviction(key).map_or_else(|| "no-patch-base".to_string(), |why| format!("evicted:{why}")))
                } else {
                    None
                }
            }
            None => Some(match take_eviction(key) {
                Some(why) => format!("evicted:{why}"),
                None if slots.keys().any(|other| other.manifest == key.manifest) => "variant-mismatch".to_string(),
                None => "no-session".to_string(),
            }),
        };
        crate::compile_stats::SessionState { hot: miss.is_none(), miss, sessions }
    }
    fn slot(
        &self,
        path: PathBuf,
        config: Option<&crate::request::BuildRequest>,
    ) -> Arc<Slot> {
        let mut slots = self.slots.lock().unwrap_or_else(|e| e.into_inner());
        let slot = slots
            .entry(SessionKey::of(path, config))
            .or_insert_with(|| {
                Arc::new(Slot {
                    request_serial: Mutex::new(()),
                    host: Mutex::new(crate::runner_host::BuildHost::with_daemon_owners(
                        Arc::clone(&self.engines),
                        Arc::clone(&self.executors),
                        Arc::clone(&self.procedures),
                        Arc::clone(&self.store),
                    )),
                    newest: Mutex::new(BTreeMap::new()),
                    last: Mutex::new(Instant::now()),
                    idle_tier: AtomicUsize::new(0),
                })
            })
            .clone();
        slot.idle_tier.store(0, Ordering::Release);
        slot
    }
    #[cfg(test)]
    fn acquire(self: &Arc<Self>, workers: usize) -> io::Result<Permit> {
        self.acquire_until(
            workers,
            &admission_deadline::AdmissionDeadline::new(Instant::now()),
        )
    }
    fn acquire_until(
        self: &Arc<Self>,
        workers: usize,
        deadline: &admission_deadline::AdmissionDeadline,
    ) -> io::Result<Permit> {
        self.acquire_until_observing(workers, deadline, transport::private_bytes)
    }
    fn acquire_until_observing(
        self: &Arc<Self>,
        workers: usize,
        deadline: &admission_deadline::AdmissionDeadline,
        private_bytes: impl Fn() -> Option<u64>,
    ) -> io::Result<Permit> {
        self.acquire_with_admission_until_observing(workers, deadline, false, private_bytes)
    }
    fn acquire_with_admission_until_observing(
        self: &Arc<Self>,
        workers: usize,
        deadline: &admission_deadline::AdmissionDeadline,
        accepted_before_retirement: bool,
        private_bytes: impl Fn() -> Option<u64>,
    ) -> io::Result<Permit> {
        let workers = workers.max(1);
        if workers > self.max_workers {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, format!(
                "request needs {workers} workers but daemon DMB_DAEMON_MAX_WORKERS limit is {}; use --no-daemon for a larger pool", self.max_workers)));
        }
        let mut active = self.running.lock().unwrap_or_else(|e| e.into_inner());
        let initial_private = private_bytes();
        if initial_private.is_none() {
            super::emit_stderr(format_args!(
                "dmbd memory admission probe unavailable; count-only admission"
            ));
        }
        // Soft throttle, not a hard private-memory ceiling: one admitted build
        // can grow past the limit. Preserve a single-build progress lane.
        while (*active >= 3
            || *self.workers.lock().unwrap_or_else(|e| e.into_inner()) + workers > self.max_workers
            || *active > 0
                && private_bytes().is_some_and(|bytes| self.under_memory_pressure(bytes)))
            && (accepted_before_retirement || !self.retiring.load(Ordering::Acquire))
        {
            control::checkpoint()?;
            let remaining = deadline.remaining(Instant::now())?;
            active = self
                .capacity
                .wait_timeout(active, Duration::from_millis(100).min(remaining))
                .unwrap_or_else(|e| e.into_inner())
                .0;
        }
        control::checkpoint()?;
        deadline.remaining(Instant::now())?;
        if self.retiring.load(Ordering::Acquire) && !accepted_before_retirement {
            return Err(io::Error::other("daemon retiring"));
        }
        *active += 1;
        *self.workers.lock().unwrap_or_else(|e| e.into_inner()) += workers;
        Ok(Permit(Arc::clone(self), workers))
    }
    fn trim(&self) {
        let running = *self.running.lock().unwrap_or_else(|e| e.into_inner());
        let mut bytes = transport::private_bytes();
        let finished = BUILDS_FINISHED.load(Ordering::Acquire);
        let stale = finished != BUILDS_RECLAIMED.load(Ordering::Acquire);
        // Reclaim off the request path, only between builds; resample after.
        // Pressure alone re-collects at most every 30 s: retained memory that a
        // collect cannot return would otherwise be re-collected every second.
        let pressured_due = bytes.is_some_and(|bytes| self.under_memory_pressure(bytes))
            && PRESSURE_RECLAIMED
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .is_none_or(|at| at.elapsed() >= Duration::from_secs(30));
        if running == 0 && (stale || pressured_due) {
            *PRESSURE_RECLAIMED.lock().unwrap_or_else(|e| e.into_inner()) = Some(Instant::now());
            BUILDS_RECLAIMED.store(finished, Ordering::Release);
            bytes = self.reclaim_allocator(bytes);
        }
        // A retiring daemon holds session memory for nobody: free every idle session now, then return the pages.
        if self.retiring.load(Ordering::Acquire) && self.release_for_retire() {
            bytes = self.reclaim_allocator(transport::private_bytes());
        }
        // Diagnostic (feature `allocation-sites` only): 20 s after a build, release the idle session and dump what the
        // daemon still holds with no session, to attribute that residual.
        #[cfg(feature = "allocation-sites")]
        if running == 0
            && std::env::var_os("DMB_ALLOC_SITES_RELEASE").is_some()
            && BUILDS_FINISHED.load(Ordering::Acquire) > 0
            && !DIAG_RELEASED.swap(true, Ordering::AcqRel)
        {
            std::thread::sleep(Duration::from_secs(20));
            let upto = std::env::var("DMB_ALLOC_SITES_RELEASE").ok().and_then(|text| text.parse::<usize>().ok());
            if match upto {
                Some(tier) if (2..housekeeping::SESSION_RELEASE).contains(&tier) => self.diag_release_tiers(tier),
                Some(0) => false,
                _ => self.release_for_retire(),
            } {
                bytes = self.reclaim_allocator(transport::private_bytes());
            }
        }
        if self.enforce_retained_budget(None, 0) {
            bytes = transport::private_bytes();
        }
        let hard = bytes.is_some_and(|bytes| self.over_hard_ceiling(bytes));
        // A running build's transient peak is not retained state: only the
        // hard ceiling may act during one.
        let soft = hard
            || running == 0 && bytes.is_some_and(|bytes| self.under_memory_pressure(bytes));
        self.housekeep(Instant::now(), soft, hard);
        // Host releases above have finished; no slot/host lock is held here.
        self.engines.prune_idle();
        self.executors.trim(Instant::now(), hard);
    }
}
const RECLAIM_LOG_MIN_BYTES: u64 = 64 << 20;
static PRESSURE_RECLAIMED: Mutex<Option<Instant>> = Mutex::new(None);
#[cfg(feature = "allocation-sites")]
static DIAG_RELEASED: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);
static BUILDS_FINISHED: AtomicU64 = AtomicU64::new(0);
static BUILDS_RECLAIMED: AtomicU64 = AtomicU64::new(0);
struct Permit(Arc<Shared>, usize);
impl Drop for Permit {
    fn drop(&mut self) {
        let mut running = self.0.running.lock().unwrap_or_else(|e| e.into_inner());
        *running -= 1;
        BUILDS_FINISHED.fetch_add(1, Ordering::AcqRel);
        super::resident::touch();
        *self.0.workers.lock().unwrap_or_else(|e| e.into_inner()) -= self.1;
        drop(running);
        self.0.capacity.notify_all();
    }
}
struct Connection(Arc<Shared>);
impl Drop for Connection {
    fn drop(&mut self) {
        self.0.connections.fetch_sub(1, Ordering::AcqRel);
    }
}
pub(super) fn serve() -> io::Result<()> {
    // Registers this daemon. Registration never retires another daemon: each compiler version has its own.
    let mut registration = super::resident::register();
    let max_workers = admission_limits::max_workers()?;
    let soft_private_bytes = soft_memory::startup()?;
    match soft_memory::enable_adaptive()? {
        Some(reserve) => super::emit_stderr(format_args!(
            "dmbd adaptive memory budget: reserve={reserve} soft-margin={} ceiling={} (explicit limits and DMB_DAEMON_ADAPTIVE=0 turn it off)",
            soft_memory::SOFT_MARGIN,
            soft_memory::ADAPTIVE_CEILING
        )),
        None => super::emit_stderr(format_args!("dmbd fixed memory budget (adaptive budget off or unavailable)")),
    }
    super::emit_stderr(format_args!(
        "dmbd start pid={} max-builds=3 max-workers={} soft-private-limit={soft_private_bytes} hard-private-limit={}",
        std::process::id(),
        max_workers,
        soft_memory::hard(soft_private_bytes)?
    ));
    crate::fs_watch::enable();
    if let Err(error) = super::cache_gc::spawn() {
        eprintln!("dmbd cache budget: could not start: {error}");
    }
    let compiler = super::compiler_identity()?;
    let mut listeners = super::generation_listeners::Listeners::new(compiler)?;
    let store: Arc<crate::shared_store::SharedStore> = Arc::new(Default::default());
    // Every artifact owner created from here on shares its core with the other sessions (`shared_store.rs`).
    crate::shared_store::activate(&store);
    let shared = Arc::new(Shared {
        engines: Arc::new(Default::default()),
        executors: Arc::new(Default::default()),
        procedures: Arc::new(Default::default()),
        store,
        compiler,
        retiring: AtomicBool::new(false),
        slots: Mutex::new(BTreeMap::new()),
        running: Mutex::new(0),
        workers: Mutex::new(0),
        max_workers,
        soft_private_bytes,
        capacity: Condvar::new(),
        connections: AtomicUsize::new(0),
    });
    let mut activity = Instant::now();
    // Housekeeping (allocator reclaim, tier releases that can take tens of
    // seconds) runs on its own thread so it can never stall request acceptance.
    {
        let owner = Arc::clone(&shared);
        std::thread::Builder::new()
            .name("dmbd-housekeeping".into())
            .stack_size(dm_exec::COMPILER_STACK_BYTES)
            .spawn(move || {
                let mut housekeeping = housekeeping::Deadline::new(Instant::now());
                loop {
                    if housekeeping.due(Instant::now()) {
                        owner.trim();
                    }
                    std::thread::sleep(Duration::from_millis(50));
                }
            })?;
    }
    let mut beat = Instant::now();
    let mut peers_checked = Instant::now();
    let mut retiring_since: Option<Instant> = None;
    let mut beat_retiring = false;
    let mut superseded_exit = false;
    let mut check_superseded = Instant::now();
    loop {
        let retiring = shared.retiring.load(Ordering::Acquire);
        let incoming = listeners.poll(retiring, Instant::now())?;
        if retiring && retiring_since.is_none() {
            retiring_since = Some(Instant::now());
        }
        // One latest compiler: when `current` moves past this version the daemon drains and exits (checked every second).
        if !superseded_exit && check_superseded.elapsed() >= Duration::from_secs(1) {
            check_superseded = Instant::now();
            if super::resident::superseded(super::resident::provenance_of_self()) {
                superseded_exit = true;
                super::emit_stderr(format_args!(
                    "dmbd retiring: a newer compiler version is current; finishing in-flight builds, refusing new ones, then exiting"
                ));
                shared.retire();
            }
        }
        if superseded_exit
            && incoming.is_none()
            && *shared.running.lock().unwrap_or_else(|e| e.into_inner()) == 0
            && shared.connections.load(Ordering::Acquire) == 0
        {
            super::emit_stderr(format_args!("dmbd exiting pid={}: superseded and idle", std::process::id()));
            return Ok(());
        }
        if beat.elapsed() >= Duration::from_secs(5) || retiring != beat_retiring {
            beat_retiring = retiring;
            beat = Instant::now();
            let busy = *shared.running.lock().unwrap_or_else(|e| e.into_inner()) > 0
                || shared.connections.load(Ordering::Acquire) > 0;
            // A current daemon also reaps idle superseded daemons of older builds that lack the immediate self-exit above.
            if !retiring && peers_checked.elapsed() >= Duration::from_secs(30) {
                peers_checked = Instant::now();
                let _ = super::resident::retire_superseded_peers();
            }
            if let Some(registration) = registration.as_mut() {
                if registration.beat(busy, retiring) && !retiring {
                    super::emit_stderr(format_args!(
                        "dmbd retiring: a newer daemon asked for it (machine-wide resident cap); draining running builds"
                    ));
                    shared.retire();
                }
            }
        }
        if shared.root_gone_exit_ready(incoming.is_some()) {
            super::emit_stderr(format_args!(
                "dmbd exiting: every retained project root no longer exists pid={}",
                std::process::id()
            ));
            return Ok(());
        }
        if incoming.is_none()
            && retiring_since.is_some_and(|since| {
                super::resident::retire_exit_due(
                    since.elapsed(),
                    *shared.running.lock().unwrap_or_else(|e| e.into_inner()),
                )
            })
        {
            super::emit_stderr(format_args!(
                "dmbd exiting pid={}: retiring with no running build for {}s (open connections: {})",
                std::process::id(),
                super::resident::RETIRE_GRACE.as_secs(),
                shared.connections.load(Ordering::Acquire)
            ));
            return Ok(());
        }
        if shared.exit_ready(incoming.is_some(), activity.elapsed()) {
            super::emit_stderr(format_args!(
                "dmbd exiting pid={} retiring={} idle-seconds={}",
                std::process::id(),
                shared.retiring.load(Ordering::Acquire),
                activity.elapsed().as_secs()
            ));
            return Ok(());
        }
        match incoming {
            Some(incoming) => {
                let stream = incoming.stream;
                let discovery = incoming.discovery;
                activity = Instant::now();
                super::resident::touch();
                if shared.connections.fetch_add(1, Ordering::AcqRel) >= 16 {
                    shared.connections.fetch_sub(1, Ordering::AcqRel);
                    let mut stream = stream;
                    let _ = protocol::send(
                        &mut stream,
                        &Reply::Rejected(crate::request_failure::RequestFailure::infrastructure(
                            "daemon connection queue is full",
                        )),
                    );
                    continue;
                }
                let shared = Arc::clone(&shared);
                request_threads::run(move || {
                    let _connection = Connection(Arc::clone(&shared));
                    if let Err(error) = handle(stream, &shared, discovery) {
                        super::emit_stderr(format_args!("daemon request: {error}"));
                    }
                })?;
            }
            None => std::thread::sleep(Duration::from_millis(5)),
        }
    }
}
fn handle(mut stream: transport::Stream, shared: &Arc<Shared>, discovery: bool) -> io::Result<()> {
    transport::set_timeout(&mut stream, Duration::from_secs(20))?;
    let Request::Hello { version, compiler } = protocol::receive(&mut stream)? else {
        return Err(io::Error::other("daemon handshake required"));
    };
    protocol::send(
        &mut stream,
        &Reply::Hello {
            version: protocol::VERSION,
            compiler: shared.compiler,
            retiring: shared.retiring.load(Ordering::Acquire),
        },
    )?;
    match protocol::receive(&mut stream)? {
        Request::Retire => {
            super::emit_stderr(format_args!("dmbd retiring: draining running builds"));
            shared.retire();
            protocol::send(&mut stream, &Reply::Retiring)
        }
        Request::Query(request) => {
            if discovery {
                return protocol::send(
                    &mut stream,
                    &Reply::Rejected(crate::request_failure::RequestFailure::invalid_request(
                        "queries require the compiler-generation endpoint",
                    )),
                );
            }
            if version != protocol::VERSION
                || compiler != shared.compiler
                || shared.retiring.load(Ordering::Acquire)
            {
                return protocol::send(
                    &mut stream,
                    &Reply::Rejected(crate::request_failure::RequestFailure::infrastructure(
                        "daemon query generation differs or is retiring",
                    )),
                );
            }
            let result = (|| -> io::Result<super::query::QueryReply> {
                request.validate()?;
                let deadline = Instant::now() + request.timeout()?;
                let admission = admission_deadline::AdmissionDeadline::at(deadline);
                transport::set_timeout(&mut stream, admission.remaining(Instant::now())?)?;
                let _binding =
                    control::bind_with_deadline(control::Cancellation::default(), deadline);
                control::checkpoint()?;
                if !request.project.is_absolute()
                    || request
                        .engine_template
                        .as_ref()
                        .is_some_and(|path| !path.is_absolute())
                {
                    return Err(io::Error::new(
                        io::ErrorKind::InvalidInput,
                        "daemon query paths must be caller-resolved absolute paths",
                    ));
                }
                let key = SessionKey {
                    manifest: session_root(std::fs::canonicalize(&request.project)?),
                    engine: request.engine_template.as_deref().map(EngineIdentity::of),
                    bootstrap: request.bootstrap_catalog,
                };
                let slot = shared
                    .slots
                    .lock()
                    .unwrap_or_else(|error| error.into_inner())
                    .get(&key)
                    .cloned()
                    .ok_or_else(|| {
                        io::Error::new(io::ErrorKind::NotFound, "query session has not been built")
                    })?;
                // Lazy executable/body queries obey the same global worker budget.
                // Acquire before the host lock, matching ordinary build admission.
                let executable = request.source_queries.iter().any(|query| {
                    matches!(
                        query,
                        super::query::SourceQuery::SelectedReferences { .. }
                            | super::query::SourceQuery::BodyModel { .. }
                    )
                });
                let _permit = if executable {
                    Some(shared.acquire_until(1, &admission)?)
                } else {
                    None
                };
                let host = slot.host.try_lock().map_err(|_| {
                    io::Error::new(
                        io::ErrorKind::WouldBlock,
                        "query session is building; retry after completion",
                    )
                })?;
                if !host.serves_variant(&request.project, &request.defines) {
                    return Err(io::Error::new(
                        io::ErrorKind::NotFound,
                        "query session holds another define set or manifest as its active variant; build this one first",
                    ));
                }
                let tree = host.query_tree().ok_or_else(|| {
                    io::Error::new(
                        io::ErrorKind::NotFound,
                        "query semantic snapshot unavailable or evicted",
                    )
                })?;
                let state = host.query_state();
                let state = state.lock().unwrap_or_else(|error| error.into_inner());
                let reply = super::query::evaluate_snapshot(&request, tree, &state)?;
                control::checkpoint()?;
                Ok(reply)
            })();
            match result {
                Ok(reply) => protocol::send(&mut stream, &Reply::Query(reply)),
                Err(error) => protocol::send(
                    &mut stream,
                    &Reply::Rejected(if error.kind() == io::ErrorKind::InvalidInput {
                        crate::request_failure::RequestFailure::invalid_request(error.to_string())
                    } else {
                        crate::request_failure::RequestFailure::from_error(&error)
                    }),
                ),
            }
        }
        Request::Build(request) => {
            dm_profile::request_marks_begin();
            if discovery {
                return protocol::send(
                    &mut stream,
                    &Reply::Rejected(crate::request_failure::RequestFailure::invalid_request(
                        "builds require the compiler-generation endpoint",
                    )),
                );
            }
            if version != protocol::VERSION
                || compiler != shared.compiler
                || shared.retiring.load(Ordering::Acquire)
            {
                return protocol::send(
                    &mut stream,
                    &Reply::Rejected(crate::request_failure::RequestFailure::infrastructure(
                        "daemon version differs or is retiring",
                    )),
                );
            }
            if let Err(error) = super::build_admission::validate(&request) {
                return protocol::send(&mut stream, &Reply::Rejected(error));
            }
            if request.trace_path.is_some() {
                return protocol::send(
                    &mut stream,
                    &Reply::Rejected(crate::request_failure::RequestFailure::infrastructure(
                        "profiled requests require local process certification",
                    )),
                );
            }
            transport::set_timeout(&mut stream, transport::BUILD_DEADLINE)?;
            let path = std::fs::canonicalize(&request.project)?;
            let accepted = match shared.accept_request() {
                Ok(accepted) => accepted,
                Err(error) => {
                    return protocol::send(
                        &mut stream,
                        &Reply::Rejected(crate::request_failure::RequestFailure::from_error(&error)),
                    );
                }
            };
            let key = RequestKey::of(&request, &path);
            let session_key = SessionKey::of(path.clone(), Some(&request));
            let session_state = shared.probe(&session_key);
            let session_state_hot = session_state.hot;
            let stats_context = (
                request.command == crate::request::BuildCommand::Compile,
                path.clone(),
                path.file_name().map_or_else(String::new, |name| name.to_string_lossy().into_owned()),
                request.workers,
            );
            let slot = shared.slot(path, Some(&request));
            let token = control::Cancellation::default();
            let _latest = LatestRequest::register(&slot, key, token.clone());
            protocol::send(&mut stream, &Reply::Accepted)?;
            let stream = Arc::new(Mutex::new(stream));
            let _output = super::output_binding(Arc::clone(&stream));
            let _binding = control::bind(token);
            let admission = admission_deadline::AdmissionDeadline::new(Instant::now());
            let _serial = match slot.lock_request_until(&admission) {
                Ok(serial) => serial,
                Err(error) => {
                    return protocol::send(
                        &mut *stream.lock().unwrap_or_else(|e| e.into_inner()),
                        &Reply::Rejected(crate::request_failure::RequestFailure::from_error(
                            &error,
                        )),
                    )
                }
            };
            if let Err(error) = shared.await_memory(&session_key, session_state_hot) {
                return protocol::send(
                    &mut *stream.lock().unwrap_or_else(|e| e.into_inner()),
                    &Reply::Rejected(crate::request_failure::RequestFailure::from_error(&error)),
                );
            }
            let _permit = match shared.acquire_accepted_until(&accepted, request.workers, &admission) {
                Ok(permit) => permit,
                Err(error) => {
                    return protocol::send(
                        &mut *stream.lock().unwrap_or_else(|e| e.into_inner()),
                        &Reply::Rejected(crate::request_failure::RequestFailure::from_error(
                            &error,
                        )),
                    )
                }
            };
            let mut host = match slot.lock_host_until(&admission) {
                Ok(host) => host,
                Err(error) => {
                    return protocol::send(
                        &mut *stream.lock().unwrap_or_else(|e| e.into_inner()),
                        &Reply::Rejected(crate::request_failure::RequestFailure::from_error(
                            &error,
                        )),
                    )
                }
            };
            slot.idle_tier.store(0, Ordering::Release);
            dm_profile::request_mark("daemon.admitted");
            crate::compile_stats::begin();
            let private_before = transport::private_bytes();
            let build_started = Instant::now();
            let sampler = PeakSampler::start();
            let outcome = std::panic::catch_unwind(std::panic::AssertUnwindSafe(
                || -> Result<crate::request::BuildOutcome, Box<dyn std::error::Error>> {
                    control::checkpoint()?;
                    crate::request_runner::run_build_with_host(request, &mut host)
                },
            ));
            *slot.last.lock().unwrap_or_else(|e| e.into_inner()) = Instant::now();
            let private_after = transport::private_bytes();
            let peak = sampler.finish().max(private_before).max(private_after);
            if let (Some(before), Some(peak)) = (private_before, peak) {
                note_growth(&session_key, session_state_hot, peak.saturating_sub(before));
            }
            if stats_context.0 {
                let error = match &outcome {
                    Ok(Ok(_)) => None,
                    Ok(Err(error)) => Some(error.to_string()),
                    Err(_) => Some("internal compiler panic".to_string()),
                };
                let record = crate::compile_stats::finish(
                    &stats_context.1,
                    stats_context.2,
                    stats_context.3,
                    session_state,
                    build_started.elapsed().as_secs_f64(),
                    (private_before, private_after, peak),
                    error,
                );
                crate::compile_stats::append(&super::resident::state_dir(), &record);
                // The daemon's own stderr is the lifecycle log; the client sees the same line in its build output.
                eprintln!("dmbd {}", record.line());
                crate::daemon_eprintln!("{}", record.line());
            }
            let reply = match outcome {
                Ok(Ok(outcome)) => Reply::Completed(outcome),
                Ok(Err(error)) => Reply::Rejected(
                    crate::request_failure::RequestFailure::from_error(error.as_ref()),
                ),
                Err(_) => {
                    shared.reset_host(&mut host);
                    Reply::Rejected(crate::request_failure::RequestFailure::internal(
                        "internal compiler panic; retained session cleared",
                    ))
                }
            };
            dm_profile::request_mark("daemon.build_returned");
            let result = protocol::send(
                &mut *stream.lock().unwrap_or_else(|e| e.into_inner()),
                &reply,
            );
            dm_profile::request_marks_end("daemon.replied");
            result
        }
        _ => Err(io::Error::other(
            "build or retirement required after handshake",
        )),
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[path = "panic_reset_tests.rs"]
    mod panic_reset;
    #[path = "pressure_tests.rs"]
    mod pressure;
    #[path = "six_session_contract_tests.rs"]
    mod six_session_contract;
    fn shared() -> Arc<Shared> {
        Arc::new(Shared {
            engines: Arc::new(Default::default()),
            executors: Arc::new(Default::default()),
            procedures: Arc::new(Default::default()),
            store: Arc::new(Default::default()),
            compiler: 1,
            retiring: AtomicBool::new(false),
            slots: Mutex::new(BTreeMap::new()),
            running: Mutex::new(0),
            workers: Mutex::new(0),
            max_workers: 8,
            soft_private_bytes: soft_memory::DEFAULT,
            capacity: Condvar::new(),
            connections: AtomicUsize::new(0),
        })
    }
    #[test]
    fn discovery_cannot_admit_a_build_or_capture_its_missing_project() {
        let identity = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let endpoint = transport::Endpoint::generation(identity).unwrap();
        let listener = transport::listener(&endpoint).unwrap();
        let owner = shared();
        let server = std::thread::spawn(move || handle(listener.accept().unwrap(), &owner, true));
        let mut client = transport::connect(&endpoint).unwrap();
        transport::set_timeout(&mut client, Duration::from_secs(2)).unwrap();
        protocol::send(
            &mut client,
            &Request::Hello {
                version: protocol::VERSION,
                compiler: 1,
            },
        )
        .unwrap();
        assert!(matches!(
            protocol::receive::<Reply>(&mut client).unwrap(),
            Reply::Hello { compiler: 1, .. }
        ));
        let arguments = [
            "compile",
            "missing-discovery-fixture.dme",
            "--no-cache",
            "--workers",
            "1",
        ]
        .map(String::from);
        let crate::request::Command::Build(request) = crate::cli::parse(&arguments).unwrap() else {
            panic!("fixture compile request missing");
        };
        protocol::send(&mut client, &Request::Build(*request)).unwrap();
        let Reply::Rejected(failure) = protocol::receive::<Reply>(&mut client).unwrap() else {
            panic!("discovery must reject build before production");
        };
        assert_eq!(
            failure.kind,
            crate::request_failure::FailureKind::InvalidRequest
        );
        assert_eq!(
            failure.message,
            "builds require the compiler-generation endpoint"
        );
        server.join().unwrap().unwrap();
    }
    #[test]
    fn custom_memory_policy_is_shared_by_admission_and_trim() {
        let mut owner = shared();
        Arc::get_mut(&mut owner).unwrap().soft_private_bytes = 2_000_000_000;
        assert!(!owner.under_memory_pressure(1_999_999_999));
        assert!(owner.under_memory_pressure(2_000_000_000));
        assert!(owner.under_memory_pressure(2_000_000_001));
    }
    #[test]
    fn retiring_refuses_admission_and_permit_drops_exactly_once() {
        let shared = shared();
        let first = shared.acquire(2).unwrap();
        let second = shared.acquire(2).unwrap();
        let third = shared.acquire(2).unwrap();
        assert_eq!(*shared.running.lock().unwrap(), 3);
        shared.retiring.store(true, Ordering::Release);
        assert!(shared.acquire(2).is_err());
        drop((first, second, third));
        assert_eq!(*shared.running.lock().unwrap(), 0);
    }
    #[test]
    fn each_manifest_retains_one_host_and_idle_owner_can_be_evicted() {
        let shared = shared();
        let path = PathBuf::from("E:/fixture/one.dme");
        let first = shared.slot(path.clone(), None);
        let second = shared.slot(path.clone(), None);
        assert!(Arc::ptr_eq(&first, &second));
        *first.last.lock().unwrap() = Instant::now() - housekeeping::SESSION_IDLE - Duration::from_secs(1);
        shared.trim();
        assert_eq!(shared.slots.lock().unwrap().len(), 1);
        drop((first, second));
        shared.trim();
        assert!(shared.slots.lock().unwrap().is_empty());
    }
    #[test]
    fn worker_admission_is_exact_and_rejects_unsupported_request() {
        let shared = shared();
        assert!(shared.acquire(9).is_err());
        let permit = shared.acquire(8).unwrap();
        assert_eq!(*shared.workers.lock().unwrap(), 8);
        drop(permit);
        assert_eq!(*shared.workers.lock().unwrap(), 0);
        let zero = shared.acquire(0).unwrap();
        assert_eq!(*shared.workers.lock().unwrap(), 1);
        drop(zero);
    }
    #[test]
    fn configured_worker_limit_rejects_large_requests_and_bounds_combined_permits() {
        let mut shared = shared();
        Arc::get_mut(&mut shared).unwrap().max_workers = 2;
        let error = shared.acquire(3).err().unwrap();
        assert_eq!(error.kind(), io::ErrorKind::InvalidInput);
        assert!(error.to_string().contains("limit is 2"));
        let occupied = shared.acquire(2).unwrap();
        let deadline = admission_deadline::AdmissionDeadline::new(
            Instant::now() - Duration::from_millis(599_950),
        );
        let error = shared
            .acquire_until_observing(1, &deadline, || Some(0))
            .err()
            .unwrap();
        assert_eq!(error.kind(), io::ErrorKind::Interrupted);
        assert_eq!(*shared.workers.lock().unwrap(), 2);
        assert_eq!(*shared.running.lock().unwrap(), 1);
        drop(occupied);
        let first = shared.acquire(1).unwrap();
        let second = shared.acquire(1).unwrap();
        assert_eq!(*shared.workers.lock().unwrap(), 2);
        drop((first, second));
        assert_eq!(*shared.workers.lock().unwrap(), 0);
    }
    #[test]
    fn superseded_admission_does_not_wait_for_worker_capacity() {
        let shared = shared();
        let permit = shared.acquire(8).unwrap();
        let token = control::Cancellation::default();
        token.cancel();
        let _binding = control::bind(token);
        assert_eq!(
            shared.acquire(1).err().unwrap().kind(),
            io::ErrorKind::Interrupted
        );
        drop(permit);
    }
    #[test]
    fn supersession_is_configuration_scoped_and_old_completion_preserves_newest() {
        let shared = shared();
        let slot = shared.slot(PathBuf::from("E:/fixture/project.dme"), None);
        let key = RequestKey {
            command: RequestCommand::Compile,
            defines: BTreeMap::new(),
            engine: None,
            bootstrap: true,
            destination: PathBuf::from("E:/fixture/project.dme"),
            output_store: None,
            replay: None,
            record_inputs: None,
        };
        let first = control::Cancellation::default();
        let old = LatestRequest::register(&slot, key.clone(), first.clone());
        let mut different = key.clone();
        different.defines.insert("MODE".into(), "1".into());
        let other = control::Cancellation::default();
        let independent = LatestRequest::register(&slot, different, other.clone());
        assert!(!first.is_cancelled());
        let second = control::Cancellation::default();
        let latest = LatestRequest::register(&slot, key.clone(), second.clone());
        assert!(first.is_cancelled());
        assert!(!other.is_cancelled());
        drop(old);
        assert!(slot
            .newest
            .lock()
            .unwrap()
            .get(&key)
            .unwrap()
            .same_request(&second));
        drop((latest, independent));
        assert!(slot.newest.lock().unwrap().is_empty());
    }
    #[test]
    fn logical_key_ignores_execution_flags_but_preserves_destinations() {
        let args = vec!["compile".into(), "E:/fixture/project.dme".into()];
        let crate::request::Command::Build(request) = crate::cli::parse(&args).unwrap() else {
            panic!("build expected")
        };
        let mut changed = (*request).clone();
        let manifest = std::path::Path::new("E:/fixture/project.dme");
        let key = RequestKey::of(&request, manifest);
        changed.workers = 8;
        changed.progress_enabled = true;
        changed.no_cache = true;
        changed.exact_inputs = true;
        changed.trace_path = Some("trace.json".into());
        assert_eq!(key, RequestKey::of(&changed, manifest));
        changed.record_inputs = Some("E:/fixture/records".into());
        assert_ne!(key, RequestKey::of(&changed, manifest));
        changed.record_inputs = None;
        changed.artifact_directory = Some("E:/fixture/other".into());
        assert_ne!(key, RequestKey::of(&changed, manifest));
        changed.artifact_directory = None;
        changed.output_store = Some("E:/fixture/store".into());
        assert_ne!(key, RequestKey::of(&changed, manifest));
    }
    #[test]
    fn executable_and_declaration_exports_do_not_supersede_each_other() {
        let args = vec!["analyze".into(), "E:/fixture/project.dme".into()];
        let crate::request::Command::Build(request) = crate::cli::parse(&args).unwrap() else {
            panic!("build expected")
        };
        let manifest = std::path::Path::new("E:/fixture/project.dme");
        let key = RequestKey::of(&request, manifest);
        let mut executable = *request;
        executable.command = crate::request::BuildCommand::AnalyzeBodies;
        assert_ne!(key, RequestKey::of(&executable, manifest));
    }
    #[test]
    fn captured_input_destinations_preserve_independent_requests() {
        let shared = shared();
        let manifest = PathBuf::from("E:/fixture/project.dme");
        let slot = shared.slot(manifest.clone(), None);
        let args = vec!["compile".into(), manifest.to_string_lossy().into_owned()];
        let crate::request::Command::Build(mut request) = crate::cli::parse(&args).unwrap() else {
            panic!("build expected")
        };
        request.record_inputs = Some("E:/fixture/capture-a".into());
        let first = control::Cancellation::default();
        let old =
            LatestRequest::register(&slot, RequestKey::of(&request, &manifest), first.clone());
        request.record_inputs = Some("E:/fixture/capture-b".into());
        let second = control::Cancellation::default();
        let independent =
            LatestRequest::register(&slot, RequestKey::of(&request, &manifest), second.clone());
        assert!(!first.is_cancelled());
        let replacement = LatestRequest::register(
            &slot,
            RequestKey::of(&request, &manifest),
            control::Cancellation::default(),
        );
        assert!(second.is_cancelled());
        assert!(!first.is_cancelled());
        drop((old, independent, replacement));
        assert!(slot.newest.lock().unwrap().is_empty());
    }
    #[test]
    fn define_sets_retain_independent_hosts_and_cancelled_waiter_exits_immediately() {
        let shared = shared();
        let path = PathBuf::from("E:/fixture/project.dme");
        // Define sets are inputs of one session, not separate sessions: the manifest file name does not key it either.
        let plain = shared.slot(path.clone(), None);
        let alternate = shared.slot(path.with_file_name("project.test.dme"), None);
        assert!(Arc::ptr_eq(&plain, &alternate));
        let _busy = plain.host.lock().unwrap();
        let token = control::Cancellation::default();
        token.cancel();
        let _binding = control::bind(token);
        assert_eq!(
            plain.lock_host().err().unwrap().kind(),
            io::ErrorKind::Interrupted
        );
    }
    #[test]
    fn session_keys_use_the_project_directory_and_exact_engine_configuration() {
        let shared = shared();
        let path = PathBuf::from("E:/fixture/project.dme");
        let first = shared.slot(path.clone(), None);
        assert!(Arc::ptr_eq(&first, &shared.slot(PathBuf::from("E:/fixture"), None)));
        assert!(!Arc::ptr_eq(&first, &shared.slot(PathBuf::from("E:/other/project.dme"), None)));
        let args = vec!["compile".into(), path.to_string_lossy().into_owned()];
        let crate::request::Command::Build(mut request) = crate::cli::parse(&args).unwrap() else {
            panic!("build expected")
        };
        request.engine_template = Some("E:/fixture/engine.bin".into());
        let engine = shared.slot(path.clone(), Some(&request));
        assert!(!Arc::ptr_eq(&first, &engine));
        request.bootstrap_catalog = true;
        assert!(!Arc::ptr_eq(
            &engine,
            &shared.slot(path, Some(&request))
        ));
    }
    #[test]
    fn engine_templates_are_keyed_by_content_not_by_checkout_path() {
        let shared = shared();
        let directory = std::env::temp_dir().join(format!("dmbd-engine-key-{}", std::process::id()));
        std::fs::create_dir_all(directory.join("a")).unwrap();
        std::fs::create_dir_all(directory.join("b")).unwrap();
        let (a, b, other) = (directory.join("a/t.bin"), directory.join("b/t.bin"), directory.join("b/other.bin"));
        std::fs::write(&a, b"template").unwrap();
        std::fs::write(&b, b"template").unwrap();
        std::fs::write(&other, b"different").unwrap();
        let path = PathBuf::from("E:/fixture/project.dme");
        let args = vec!["compile".into(), path.to_string_lossy().into_owned()];
        let crate::request::Command::Build(mut request) = crate::cli::parse(&args).unwrap() else {
            panic!("build expected")
        };
        request.engine_template = Some(a);
        let first = shared.slot(path.clone(), Some(&request));
        request.engine_template = Some(b);
        assert!(Arc::ptr_eq(&first, &shared.slot(path.clone(), Some(&request))));
        request.engine_template = Some(other);
        assert!(!Arc::ptr_eq(&first, &shared.slot(path, Some(&request))));
        let _ = std::fs::remove_dir_all(&directory);
    }
}

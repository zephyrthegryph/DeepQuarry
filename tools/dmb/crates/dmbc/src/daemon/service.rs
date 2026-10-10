use super::{
    control,
    protocol::{self, Reply, Request},
    transport,
};
use std::{
    collections::BTreeMap,
    io,
    path::PathBuf,
    sync::{
        atomic::{AtomicBool, AtomicUsize, Ordering},
        Arc, Condvar, Mutex,
    },
    time::{Duration, Instant},
};
#[path = "admission_deadline.rs"]
mod admission_deadline;
#[path = "admission_limits.rs"]
mod admission_limits;
#[path = "service_housekeeping.rs"]
mod housekeeping;
#[cfg(test)]
#[path = "service_queue_tests.rs"]
mod queue_tests;
/// Hosts are retained per manifest and semantic configuration. Supersession also
/// requires the same logical destination. Different defines targeting one file
/// serialize through the existing output lease but do not cancel each other.
#[derive(Clone, Copy, Debug, Eq, PartialEq, Ord, PartialOrd)]
enum RequestCommand {
    Analyze,
    AnalyzeBodies,
    AnalyzeResolved,
    Compile,
}
impl From<crate::request::BuildCommand> for RequestCommand {
    fn from(command: crate::request::BuildCommand) -> Self {
        use crate::request::BuildCommand;
        match command {
            BuildCommand::Analyze => Self::Analyze,
            BuildCommand::AnalyzeBodies => Self::AnalyzeBodies,
            BuildCommand::AnalyzeResolved => Self::AnalyzeResolved,
            BuildCommand::Compile => Self::Compile,
        }
    }
}
#[derive(Clone, Debug, Eq, PartialEq, Ord, PartialOrd)]
struct RequestKey {
    command: RequestCommand,
    defines: BTreeMap<String, String>,
    engine: Option<PathBuf>,
    bootstrap: bool,
    destination: PathBuf,
    output_store: Option<PathBuf>,
    replay: Option<PathBuf>,
}
impl RequestKey {
    fn of(request: &crate::request::BuildRequest, manifest: &std::path::Path) -> Self {
        Self {
            command: request.command.into(),
            defines: request.defines.clone(),
            engine: request.engine_template.clone(),
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
#[derive(Clone, Debug, Eq, PartialEq, Ord, PartialOrd)]
struct SessionKey {
    manifest: PathBuf,
    defines: BTreeMap<String, String>,
    engine: Option<PathBuf>,
    bootstrap: bool,
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
    compiler: u128,
    retiring: AtomicBool,
    slots: Mutex<BTreeMap<SessionKey, Arc<Slot>>>,
    running: Mutex<usize>,
    workers: Mutex<usize>,
    max_workers: usize,
    capacity: Condvar,
    connections: AtomicUsize,
}
impl Shared {
    fn reset_host(&self, host: &mut crate::runner_host::BuildHost) {
        *host = crate::runner_host::BuildHost::with_daemon_owners(
            Arc::clone(&self.engines),
            Arc::clone(&self.executors),
            Arc::clone(&self.procedures),
        );
    }
    fn slot(
        &self,
        path: PathBuf,
        defines: &BTreeMap<String, String>,
        config: Option<&crate::request::BuildRequest>,
    ) -> Arc<Slot> {
        let mut slots = self.slots.lock().unwrap_or_else(|e| e.into_inner());
        let slot = slots
            .entry(SessionKey {
                manifest: path,
                defines: defines.clone(),
                engine: config.and_then(|request| request.engine_template.clone()),
                bootstrap: config.is_some_and(|request| request.bootstrap_catalog),
            })
            .or_insert_with(|| {
                Arc::new(Slot {
                    request_serial: Mutex::new(()),
                    host: Mutex::new(crate::runner_host::BuildHost::with_daemon_owners(
                        Arc::clone(&self.engines),
                        Arc::clone(&self.executors),
                        Arc::clone(&self.procedures),
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
            || *active > 0 && private_bytes().is_some_and(|bytes| bytes >= 4_000_000_000))
            && !self.retiring.load(Ordering::Acquire)
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
        if self.retiring.load(Ordering::Acquire) {
            return Err(io::Error::other("daemon retiring"));
        }
        *active += 1;
        *self.workers.lock().unwrap_or_else(|e| e.into_inner()) += workers;
        Ok(Permit(Arc::clone(self), workers))
    }
    fn trim(&self) {
        let pressured = transport::private_bytes().is_some_and(|bytes| bytes > 4_000_000_000);
        self.housekeep(Instant::now(), pressured);
        // Host releases above have finished; no slot/host lock is held here.
        self.engines.prune_idle();
        self.executors.trim(Instant::now(), pressured);
    }
}
struct Permit(Arc<Shared>, usize);
impl Drop for Permit {
    fn drop(&mut self) {
        let mut running = self.0.running.lock().unwrap_or_else(|e| e.into_inner());
        *running -= 1;
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
    let max_workers = admission_limits::max_workers()?;
    super::emit_stderr(format_args!(
        "dmbd start pid={} max-builds=3 max-workers={} soft-private-limit=4000000000",
        std::process::id(),
        max_workers
    ));
    let endpoint = transport::Endpoint::current()?;
    let listener: transport::Listener = transport::listener(&endpoint)?;
    let shared = Arc::new(Shared {
        engines: Arc::new(Default::default()),
        executors: Arc::new(Default::default()),
        procedures: Arc::new(Default::default()),
        compiler: super::compiler_identity()?,
        retiring: AtomicBool::new(false),
        slots: Mutex::new(BTreeMap::new()),
        running: Mutex::new(0),
        workers: Mutex::new(0),
        max_workers,
        capacity: Condvar::new(),
        connections: AtomicUsize::new(0),
    });
    let (send, receive) = std::sync::mpsc::sync_channel(16);
    std::thread::Builder::new()
        .name("dmbd-accept".into())
        .spawn(move || loop {
            let result = listener.accept();
            let failed = result.is_err();
            if send.send(result).is_err() || failed {
                break;
            }
        })?;
    let mut activity = Instant::now();
    let mut housekeeping = housekeeping::Deadline::new(activity);
    loop {
        if housekeeping.due(Instant::now()) {
            shared.trim();
        }
        if shared.retiring.load(Ordering::Acquire)
            && *shared.running.lock().unwrap_or_else(|e| e.into_inner()) == 0
        {
            return Ok(());
        }
        if activity.elapsed() >= Duration::from_secs(7200)
            && *shared.running.lock().unwrap_or_else(|e| e.into_inner()) == 0
        {
            return Ok(());
        }
        match receive.recv_timeout(Duration::from_secs(1)) {
            Ok(Ok(stream)) => {
                activity = Instant::now();
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
                std::thread::Builder::new()
                    .name("dmbd-request".into())
                    .stack_size(dm_exec::COMPILER_STACK_BYTES)
                    .spawn(move || {
                        let _connection = Connection(Arc::clone(&shared));
                        if let Err(error) = handle(stream, &shared) {
                            super::emit_stderr(format_args!("daemon request: {error}"));
                        }
                    })?;
            }
            Ok(Err(error)) => return Err(error),
            Err(std::sync::mpsc::RecvTimeoutError::Timeout) => {}
            Err(_) => return Err(io::Error::other("daemon listener stopped")),
        }
    }
}
fn handle(mut stream: transport::Stream, shared: &Arc<Shared>) -> io::Result<()> {
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
            shared.retiring.store(true, Ordering::Release);
            shared.capacity.notify_all();
            protocol::send(&mut stream, &Reply::Retiring)
        }
        Request::Query(request) => {
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
                    manifest: std::fs::canonicalize(&request.project)?,
                    defines: request.defines.clone(),
                    engine: request.engine_template.clone(),
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
                let host = slot.host.try_lock().map_err(|_| {
                    io::Error::new(
                        io::ErrorKind::WouldBlock,
                        "query session is building; retry after completion",
                    )
                })?;
                let tree = host.query_tree().ok_or_else(|| {
                    io::Error::new(
                        io::ErrorKind::NotFound,
                        "query semantic snapshot unavailable or evicted",
                    )
                })?;
                let state = host.query_state();
                let state = state.lock().unwrap_or_else(|error| error.into_inner());
                super::query::evaluate_snapshot(&request, tree, &state)
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
            transport::set_timeout(&mut stream, Duration::from_secs(600))?;
            let path = std::fs::canonicalize(&request.project)?;
            let key = RequestKey::of(&request, &path);
            let slot = shared.slot(path, &request.defines, Some(&request));
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
            let _permit = match shared.acquire_until(request.workers, &admission) {
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
            let outcome = std::panic::catch_unwind(std::panic::AssertUnwindSafe(
                || -> Result<crate::request::BuildOutcome, Box<dyn std::error::Error>> {
                    control::checkpoint()?;
                    crate::request_runner::run_build_with_host(request, &mut host)
                },
            ));
            *slot.last.lock().unwrap_or_else(|e| e.into_inner()) = Instant::now();
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
            let result = protocol::send(
                &mut *stream.lock().unwrap_or_else(|e| e.into_inner()),
                &reply,
            );
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
    fn shared() -> Arc<Shared> {
        Arc::new(Shared {
            engines: Arc::new(Default::default()),
            executors: Arc::new(Default::default()),
            procedures: Arc::new(Default::default()),
            compiler: 1,
            retiring: AtomicBool::new(false),
            slots: Mutex::new(BTreeMap::new()),
            running: Mutex::new(0),
            workers: Mutex::new(0),
            max_workers: 8,
            capacity: Condvar::new(),
            connections: AtomicUsize::new(0),
        })
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
        let first = shared.slot(path.clone(), &BTreeMap::new(), None);
        let second = shared.slot(path.clone(), &BTreeMap::new(), None);
        assert!(Arc::ptr_eq(&first, &second));
        *first.last.lock().unwrap() = Instant::now() - Duration::from_secs(601);
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
        let slot = shared.slot(
            PathBuf::from("E:/fixture/project.dme"),
            &BTreeMap::new(),
            None,
        );
        let key = RequestKey {
            command: RequestCommand::Compile,
            defines: BTreeMap::new(),
            engine: None,
            bootstrap: true,
            destination: PathBuf::from("E:/fixture/project.dme"),
            output_store: None,
            replay: None,
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
        changed.record_inputs = Some("records".into());
        assert_eq!(key, RequestKey::of(&changed, manifest));
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
    fn define_sets_retain_independent_hosts_and_cancelled_waiter_exits_immediately() {
        let shared = shared();
        let path = PathBuf::from("E:/fixture/project.dme");
        let plain = shared.slot(path.clone(), &BTreeMap::new(), None);
        let defines = BTreeMap::from([("MODE".into(), "1".into())]);
        let alternate = shared.slot(path.clone(), &defines, None);
        assert!(!Arc::ptr_eq(&plain, &alternate));
        assert!(Arc::ptr_eq(&alternate, &shared.slot(path, &defines, None)));
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
    fn session_keys_use_structural_define_order_and_exact_engine_configuration() {
        let shared = shared();
        let path = PathBuf::from("E:/fixture/project.dme");
        let one = BTreeMap::from([("A".into(), "1".into()), ("B".into(), "2".into())]);
        let reversed = BTreeMap::from([("B".into(), "2".into()), ("A".into(), "1".into())]);
        let first = shared.slot(path.clone(), &one, None);
        assert!(Arc::ptr_eq(
            &first,
            &shared.slot(path.clone(), &reversed, None)
        ));
        let different = BTreeMap::from([("A".into(), "1B2".into())]);
        assert!(!Arc::ptr_eq(
            &first,
            &shared.slot(path.clone(), &different, None)
        ));
        let args = vec!["compile".into(), path.to_string_lossy().into_owned()];
        let crate::request::Command::Build(mut request) = crate::cli::parse(&args).unwrap() else {
            panic!("build expected")
        };
        request.engine_template = Some("E:/fixture/engine.bin".into());
        let engine = shared.slot(path.clone(), &one, Some(&request));
        assert!(!Arc::ptr_eq(&first, &engine));
        request.bootstrap_catalog = true;
        assert!(!Arc::ptr_eq(
            &engine,
            &shared.slot(path, &one, Some(&request))
        ));
    }
}

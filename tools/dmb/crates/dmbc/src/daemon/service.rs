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
struct Slot {
    host: Mutex<crate::runner_host::BuildHost>,
    newest: Mutex<Option<control::Cancellation>>,
    last: Mutex<Instant>,
}
struct Shared {
    compiler: u128,
    retiring: AtomicBool,
    slots: Mutex<BTreeMap<PathBuf, Arc<Slot>>>,
    running: Mutex<usize>,
    workers: Mutex<usize>,
    capacity: Condvar,
    connections: AtomicUsize,
}
impl Shared {
    fn slot(&self, path: PathBuf) -> Arc<Slot> {
        let mut slots = self.slots.lock().unwrap_or_else(|e| e.into_inner());
        slots
            .entry(path)
            .or_insert_with(|| {
                Arc::new(Slot {
                    host: Mutex::new(crate::runner_host::BuildHost::default()),
                    newest: Mutex::new(None),
                    last: Mutex::new(Instant::now()),
                })
            })
            .clone()
    }
    fn acquire(self: &Arc<Self>, workers: usize) -> io::Result<Permit> {
        let workers = workers.max(1);
        if workers > 8 {
            return Err(io::Error::other("daemon supports at most eight workers per request; use --no-daemon for a larger pool"));
        }
        let mut active = self.running.lock().unwrap_or_else(|e| e.into_inner());
        while (*active >= 3
            || *self.workers.lock().unwrap_or_else(|e| e.into_inner()) + workers > 8)
            && !self.retiring.load(Ordering::Acquire)
        {
            control::checkpoint()?;
            active = self
                .capacity
                .wait_timeout(active, Duration::from_millis(100))
                .unwrap_or_else(|e| e.into_inner())
                .0;
        }
        control::checkpoint()?;
        if self.retiring.load(Ordering::Acquire) {
            return Err(io::Error::other("daemon retiring"));
        }
        *active += 1;
        *self.workers.lock().unwrap_or_else(|e| e.into_inner()) += workers;
        Ok(Permit(Arc::clone(self), workers))
    }
    fn trim(&self) {
        let pressured = transport::private_bytes().is_some_and(|bytes| bytes > 4_000_000_000);
        self.slots
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .retain(|_, slot| {
                Arc::strong_count(slot) > 1
                    || !pressured
                        && slot
                            .last
                            .lock()
                            .unwrap_or_else(|e| e.into_inner())
                            .elapsed()
                            < Duration::from_secs(600)
            });
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
    super::emit_stderr(format_args!(
        "dmbd start pid={} max-builds=3 max-workers=8 soft-private-limit=4000000000",
        std::process::id()
    ));
    let endpoint = transport::Endpoint::current()?;
    let listener: transport::Listener = transport::listener(&endpoint)?;
    let shared = Arc::new(Shared {
        compiler: super::compiler_identity()?,
        retiring: AtomicBool::new(false),
        slots: Mutex::new(BTreeMap::new()),
        running: Mutex::new(0),
        workers: Mutex::new(0),
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
    loop {
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
                    .spawn(move || {
                        let _connection = Connection(Arc::clone(&shared));
                        if let Err(error) = handle(stream, &shared) {
                            super::emit_stderr(format_args!("daemon request: {error}"));
                        }
                    })?;
            }
            Ok(Err(error)) => return Err(error),
            Err(std::sync::mpsc::RecvTimeoutError::Timeout) => shared.trim(),
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
            let slot = shared.slot(path);
            let token = control::Cancellation::default();
            {
                let mut newest = slot.newest.lock().unwrap_or_else(|e| e.into_inner());
                if let Some(previous) = newest.replace(token.clone()) {
                    previous.cancel();
                }
            }
            protocol::send(&mut stream, &Reply::Accepted)?;
            let stream = Arc::new(Mutex::new(stream));
            let _output = super::output_binding(Arc::clone(&stream));
            let _binding = control::bind(token);
            let mut host = slot.host.lock().unwrap_or_else(|e| e.into_inner());
            let _permit = match shared.acquire(request.workers) {
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
                    *host = crate::runner_host::BuildHost::default();
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
    fn shared() -> Arc<Shared> {
        Arc::new(Shared {
            compiler: 1,
            retiring: AtomicBool::new(false),
            slots: Mutex::new(BTreeMap::new()),
            running: Mutex::new(0),
            workers: Mutex::new(0),
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
        let first = shared.slot(path.clone());
        let second = shared.slot(path.clone());
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
}

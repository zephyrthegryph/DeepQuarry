//! Bounded transport scheduling. Each compiler database stays on its owner thread.
use dm_compiled::{Coordinator, Request, Response};
use std::collections::HashMap;
use std::io::{self, Write};
use std::net::TcpStream;
use std::path::PathBuf;
use std::sync::mpsc::{self, SyncSender, TrySendError};
use std::thread::JoinHandle;

const QUEUED_PER_WORKER: usize = 2;
const MAX_WORKTREES: usize = 1024;

pub(super) fn worker_count(value: Option<&str>) -> io::Result<usize> {
    let count = value.unwrap_or("2").parse::<usize>().map_err(|_| {
        io::Error::new(
            io::ErrorKind::InvalidInput,
            "DM_DAEMON_WORKERS must be 1..4",
        )
    })?;
    if !(1..=4).contains(&count) {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "DM_DAEMON_WORKERS must be 1..4",
        ));
    }
    Ok(count)
}

pub(super) fn response(error: Option<String>) -> Response {
    Response {
        ok: error.is_none(),
        item_count: 0,
        diagnostics: vec![],
        source_digest: None,
        shared_syntax_hit: false,
        error,
        build: None,
    }
}

pub(super) fn write_response(stream: &mut TcpStream, value: &Response) {
    if let Err(error) = serde_json::to_writer(&mut *stream, value)
        .map_err(io::Error::other)
        .and_then(|()| stream.write_all(b"\n"))
    {
        eprintln!("dm-compiled response error: {error}");
    }
}

pub(super) struct Job {
    pub stream: TcpStream,
    pub request: Request,
}

pub(super) struct WorkerPool {
    senders: Vec<SyncSender<Job>>,
    threads: Vec<JoinHandle<()>>,
    routes: HashMap<PathBuf, usize>,
    next: usize,
}

impl WorkerPool {
    pub fn new(cache: PathBuf, count: usize) -> io::Result<Self> {
        Self::spawn(count, move || {
            let mut coordinator =
                Coordinator::new(cache.clone()).map_err(|error| error.to_string())?;
            Ok(move |request| coordinator.handle(request))
        })
    }

    fn spawn<F, H>(count: usize, factory: F) -> io::Result<Self>
    where
        F: Fn() -> Result<H, String> + Clone + Send + 'static,
        H: FnMut(Request) -> Response + 'static,
    {
        if !(1..=4).contains(&count) {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "compiler worker count must be 1..4",
            ));
        }
        let mut pool = Self {
            senders: vec![],
            threads: vec![],
            routes: HashMap::new(),
            next: 0,
        };
        for index in 0..count {
            let (sender, receiver) = mpsc::sync_channel::<Job>(QUEUED_PER_WORKER);
            let (ready_sender, ready_receiver) = mpsc::sync_channel(1);
            let create = factory.clone();
            let thread = std::thread::Builder::new()
                .name(format!("dm-compiler-{index}"))
                .stack_size(16 * 1024 * 1024)
                .spawn(move || {
                    let mut handler = match create() {
                        Ok(handler) => {
                            let _ = ready_sender.send(Ok(()));
                            handler
                        }
                        Err(error) => {
                            let _ = ready_sender.send(Err(error));
                            return;
                        }
                    };
                    for mut job in receiver {
                        let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                            handler(job.request)
                        }));
                        match result {
                            Ok(value) => write_response(&mut job.stream, &value),
                            Err(_) => {
                                write_response(
                                    &mut job.stream,
                                    &response(Some(
                                        "compiler worker panicked; session state reset".into(),
                                    )),
                                );
                                // A panic may leave Salsa/session state inconsistent. Recreate
                                // local state; immutable disk caches remain available.
                                match create() {
                                    Ok(next) => handler = next,
                                    Err(_) => break,
                                }
                            }
                        }
                    }
                })?;
            pool.senders.push(sender);
            pool.threads.push(thread);
            ready_receiver
                .recv()
                .map_err(io::Error::other)?
                .map_err(io::Error::other)?;
        }
        Ok(pool)
    }

    pub fn submit(&mut self, job: Job) -> Result<(), (Job, String)> {
        let worktree = match &job.request {
            Request::Ping => PathBuf::new(),
            Request::Check { key, .. }
            | Request::CheckProject { key }
            | Request::BuildProject { key, .. }
            | Request::BuildProjectPatch { key, .. } => {
                // Existing paths use canonical identity even when a wire client spells
                // the same worktree through a symlink or with relative components.
                key.worktree
                    .canonicalize()
                    .unwrap_or_else(|_| key.worktree.clone())
            }
        };
        let existing = self.routes.get(&worktree).copied();
        if existing.is_none() && self.routes.len() == MAX_WORKTREES {
            return Err((
                job,
                "daemon worktree routing limit reached; restart to admit more worktrees".into(),
            ));
        }
        let index = existing.unwrap_or(self.next);
        match self.senders[index].try_send(job) {
            Ok(()) => {
                if existing.is_none() {
                    self.routes.insert(worktree, index);
                    self.next = (index + 1) % self.senders.len();
                }
                Ok(())
            }
            Err(TrySendError::Full(job)) => {
                Err((job, "compiler queue is full; retry later".into()))
            }
            Err(TrySendError::Disconnected(job)) => {
                Err((job, "compiler worker unavailable; restart daemon".into()))
            }
        }
    }
}

impl Drop for WorkerPool {
    fn drop(&mut self) {
        self.senders.clear();
        for thread in self.threads.drain(..) {
            let _ = thread.join();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use dm_compiled::SessionKey;
    use std::io::{BufRead, BufReader};
    use std::net::TcpListener;
    use std::sync::{
        atomic::{AtomicBool, AtomicU64, Ordering},
        Arc,
    };
    use std::time::{Duration, Instant};

    fn connection(request: Request) -> (Job, TcpStream) {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let client = TcpStream::connect(listener.local_addr().unwrap()).unwrap();
        client
            .set_read_timeout(Some(Duration::from_secs(5)))
            .unwrap();
        let (stream, _) = listener.accept().unwrap();
        (Job { stream, request }, client)
    }
    fn read_response(stream: TcpStream) -> Response {
        let mut line = String::new();
        BufReader::new(stream).read_line(&mut line).unwrap();
        serde_json::from_str(&line).unwrap()
    }
    fn request(worktree: &str) -> Request {
        Request::Check {
            key: SessionKey {
                worktree: worktree.into(),
                project: "probe.dm".into(),
                target: "byond".into(),
                defines: vec![],
                build_mode: "test".into(),
                compiler_version: "test".into(),
            },
            source: "probe.dm".into(),
            text: "/datum/probe\n    var/value=7\n".into(),
        }
    }

    #[test]
    fn independent_worktrees_overlap_and_keep_affinity() {
        let (started, events) = mpsc::channel();
        let release = Arc::new(AtomicBool::new(false));
        let control = release.clone();
        let mut pool = WorkerPool::spawn(2, move || {
            let started = started.clone();
            let release = control.clone();
            Ok(move |_| {
                started.send(()).unwrap();
                let deadline = Instant::now() + Duration::from_secs(2);
                while !release.load(Ordering::Acquire) && Instant::now() < deadline {
                    std::thread::sleep(Duration::from_millis(1));
                }
                response(None)
            })
        })
        .unwrap();
        let (first, first_client) = connection(request("worktree-a"));
        let (second, second_client) = connection(request("worktree-b"));
        assert!(pool.submit(first).is_ok());
        assert!(pool.submit(second).is_ok());
        let a = events.recv_timeout(Duration::from_secs(1));
        let b = events.recv_timeout(Duration::from_secs(1));
        release.store(true, Ordering::Release);
        assert!(
            a.is_ok() && b.is_ok(),
            "both compiler workers must run before either completes"
        );
        assert!(read_response(first_client).ok);
        assert!(read_response(second_client).ok);
        assert_eq!(pool.routes[&PathBuf::from("worktree-a")], 0);
        assert_eq!(pool.routes[&PathBuf::from("worktree-b")], 1);
        let (again, client) = connection(request("worktree-a"));
        assert!(pool.submit(again).is_ok());
        assert!(read_response(client).ok);
        assert_eq!(pool.routes[&PathBuf::from("worktree-a")], 0);
    }

    #[test]
    fn overload_is_rejected_without_unbounded_pending_requests() {
        let (started, events) = mpsc::channel();
        let release = Arc::new(AtomicBool::new(false));
        let control = release.clone();
        let mut pool = WorkerPool::spawn(1, move || {
            let started = started.clone();
            let release = control.clone();
            Ok(move |_| {
                let _ = started.send(());
                let deadline = Instant::now() + Duration::from_secs(2);
                while !release.load(Ordering::Acquire) && Instant::now() < deadline {
                    std::thread::sleep(Duration::from_millis(1));
                }
                response(None)
            })
        })
        .unwrap();
        let (first, client) = connection(request("same"));
        assert!(pool.submit(first).is_ok());
        events.recv_timeout(Duration::from_secs(1)).unwrap();
        let mut clients = vec![client];
        for _ in 0..QUEUED_PER_WORKER {
            let (job, client) = connection(request("same"));
            assert!(pool.submit(job).is_ok());
            clients.push(client);
        }
        let (job, _) = connection(request("same"));
        let rejected = pool.submit(job);
        release.store(true, Ordering::Release);
        assert!(matches!(rejected, Err((_, error)) if error.contains("queue is full")));
        for client in clients {
            assert!(read_response(client).ok);
        }
    }

    #[test]
    fn actual_compilers_check_two_worktrees_and_reuse_warm_state() {
        static SEQUENCE: AtomicU64 = AtomicU64::new(0);
        let root = std::env::temp_dir().join(format!(
            "dm-daemon-workers-{}-{}",
            std::process::id(),
            SEQUENCE.fetch_add(1, Ordering::Relaxed)
        ));
        std::fs::create_dir_all(&root).unwrap();
        let mut pool = WorkerPool::new(root.join("cache"), 2).unwrap();
        let mut sources = vec![];
        for name in ["first", "second"] {
            let worktree = root.join(name);
            std::fs::create_dir(&worktree).unwrap();
            let source = worktree.join("probe.dm");
            std::fs::write(&source, "").unwrap();
            let key = SessionKey::new(&worktree, &source, "byond", vec![], "test").unwrap();
            sources.push((key, source));
        }
        for attempt in 0..2 {
            let mut clients = vec![];
            for (key, source) in &sources {
                let (job, client) = connection(Request::Check {
                    key: key.clone(),
                    source: source.clone(),
                    text: "/datum/probe\n    var/value=7\n".into(),
                });
                assert!(pool.submit(job).is_ok());
                clients.push(client);
            }
            for client in clients {
                let result = read_response(client);
                assert!(result.ok, "{:?}", result.error);
                assert!(result.item_count > 0);
                if attempt == 1 {
                    assert!(
                        result.shared_syntax_hit,
                        "repeated worktree check should retain warm syntax"
                    );
                }
            }
        }
        assert_eq!(pool.routes.len(), 2);
        drop(pool);
        assert_eq!(root.parent(), Some(std::env::temp_dir().as_path()));
        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn worker_setting_is_bounded() {
        assert_eq!(worker_count(None).unwrap(), 2);
        for bad in ["0", "5", "-1", "lots"] {
            assert!(worker_count(Some(bad)).is_err());
        }
    }

    #[test]
    fn panicked_worker_resets_and_handles_next_request() {
        let generation = Arc::new(AtomicU64::new(0));
        let mut pool = WorkerPool::spawn(1, move || {
            let current = generation.fetch_add(1, Ordering::Relaxed);
            Ok(move |_| {
                assert_ne!(current, 0, "simulated compiler failure");
                response(None)
            })
        })
        .unwrap();
        let (job, client) = connection(request("same"));
        assert!(pool.submit(job).is_ok());
        assert!(!read_response(client).ok);
        let (job, client) = connection(request("same"));
        assert!(pool.submit(job).is_ok());
        assert!(read_response(client).ok);
    }
}

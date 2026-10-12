use super::*;
use std::sync::mpsc;

fn shared(compiler: u128) -> Arc<Shared> {
    Arc::new(Shared {
        engines: Arc::new(Default::default()),
        executors: Arc::new(Default::default()),
        procedures: Arc::new(Default::default()),
        compiler,
        retiring: AtomicBool::new(false),
        slots: Mutex::new(BTreeMap::new()),
        running: Mutex::new(0),
        workers: Mutex::new(0),
        max_workers: 1,
        soft_private_bytes: soft_memory::DEFAULT,
        capacity: Condvar::new(),
        connections: AtomicUsize::new(0),
    })
}
fn connection(shared: &Arc<Shared>) -> Connection {
    shared.connections.fetch_add(1, Ordering::AcqRel);
    Connection(Arc::clone(shared))
}

#[test]
fn accepted_queued_request_drains_after_retirement_without_worker_oversubscription_or_early_exit() {
    let shared = shared(91);
    let active_connection = connection(&shared);
    let occupied = shared
        .acquire_until_observing(
            1,
            &admission_deadline::AdmissionDeadline::new(Instant::now()),
            || Some(0),
        )
        .unwrap();
    let accepted = shared.accept_request().unwrap();
    let queued_connection = connection(&shared);
    let worker_shared = Arc::clone(&shared);
    let (ready_send, ready_receive) = mpsc::channel();
    let (finished_send, finished_receive) = mpsc::channel();
    let (reply_send, reply_receive) = mpsc::channel();
    let worker = std::thread::spawn(move || {
        let _connection = queued_connection;
        let deadline =
            admission_deadline::AdmissionDeadline::at(Instant::now() + Duration::from_secs(5));
        ready_send.send(()).unwrap();
        let permit = worker_shared
            .acquire_accepted_until_observing(&accepted, 1, &deadline, || Some(0))
            .unwrap();
        assert_eq!(*worker_shared.running.lock().unwrap(), 1);
        assert_eq!(*worker_shared.workers.lock().unwrap(), 1);
        drop(permit);
        finished_send.send(()).unwrap();
        // Model the connection's terminal reply delivery after work has ended.
        reply_receive.recv_timeout(Duration::from_secs(2)).unwrap();
    });
    ready_receive.recv_timeout(Duration::from_secs(2)).unwrap();
    shared.retire();
    assert!(
        shared.accept_request().is_err(),
        "retirement must reject new builds"
    );
    assert!(shared
        .acquire_until_observing(
            1,
            &admission_deadline::AdmissionDeadline::new(Instant::now()),
            || Some(0),
        )
        .is_err());
    assert!(
        matches!(
            finished_receive.recv_timeout(Duration::from_millis(50)),
            Err(mpsc::RecvTimeoutError::Timeout)
        ),
        "retirement must neither reject nor oversubscribe accepted queued work"
    );
    assert!(!shared.exit_ready(false, Duration::ZERO));
    assert_eq!(*shared.running.lock().unwrap(), 1);
    assert_eq!(*shared.workers.lock().unwrap(), 1);
    drop((occupied, active_connection));
    finished_receive
        .recv_timeout(Duration::from_secs(2))
        .unwrap();
    assert_eq!(*shared.running.lock().unwrap(), 0);
    assert_eq!(*shared.workers.lock().unwrap(), 0);
    assert_eq!(shared.connections.load(Ordering::Acquire), 1);
    assert!(
        !shared.exit_ready(false, Duration::ZERO),
        "terminal reply must finish before process exit"
    );
    reply_send.send(()).unwrap();
    worker.join().unwrap();
    assert_eq!(shared.connections.load(Ordering::Acquire), 0);
    assert!(shared.exit_ready(false, Duration::ZERO));
}

#[test]
fn accepted_request_rejects_foreign_generation_and_current_cancellation_or_deadline() {
    let old = shared(91);
    let new = shared(92);
    let accepted = old.accept_request().unwrap();
    let deadline = admission_deadline::AdmissionDeadline::new(Instant::now());
    assert_eq!(
        new.acquire_accepted_until_observing(&accepted, 1, &deadline, || Some(0))
            .err()
            .unwrap()
            .kind(),
        io::ErrorKind::InvalidInput
    );
    old.retire();
    let expired =
        admission_deadline::AdmissionDeadline::at(Instant::now() - Duration::from_millis(1));
    assert_eq!(
        old.acquire_accepted_until_observing(&accepted, 1, &expired, || Some(0))
            .err()
            .unwrap()
            .kind(),
        io::ErrorKind::Interrupted
    );
    let token = control::Cancellation::default();
    token.cancel();
    let _binding = control::bind(token);
    assert_eq!(
        old.acquire_accepted_until_observing(&accepted, 1, &deadline, || Some(0))
            .err()
            .unwrap()
            .kind(),
        io::ErrorKind::Interrupted
    );
    assert_eq!(*old.running.lock().unwrap(), 0);
    assert_eq!(*old.workers.lock().unwrap(), 0);
    assert_eq!(*new.running.lock().unwrap(), 0);
}

#[test]
fn accepted_listener_result_and_handshake_connection_prevent_idle_exit() {
    let shared = shared(91);
    let idle = Duration::from_secs(7200);
    assert!(!shared.exit_ready(false, idle - Duration::from_secs(1)));
    assert!(shared.exit_ready(false, idle));
    assert!(!shared.exit_ready(true, idle));
    let connection = connection(&shared);
    assert!(!shared.exit_ready(false, idle));
    shared.retire();
    assert!(!shared.exit_ready(false, Duration::ZERO));
    drop(connection);
    assert!(shared.exit_ready(false, Duration::ZERO));
}

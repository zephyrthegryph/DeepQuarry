//! Scheduling fixtures, not a real six-worktree daemon acceptance gate.
use super::*;
use std::sync::mpsc;

fn shared() -> Arc<Shared> {
    Arc::new(Shared {
        engines: Arc::new(Default::default()),
        executors: Arc::new(Default::default()),
        compiler: 1,
        retiring: AtomicBool::new(false),
        slots: Mutex::new(BTreeMap::new()),
        running: Mutex::new(0),
        workers: Mutex::new(0),
        capacity: Condvar::new(),
        connections: AtomicUsize::new(0),
    })
}
fn key(destination: &str) -> RequestKey {
    RequestKey {
        compile: true,
        executable_analysis: false,
        defines: BTreeMap::new(),
        engine: None,
        bootstrap: true,
        destination: destination.into(),
        output_store: None,
        replay: None,
    }
}
#[test]
fn newer_request_cancels_a_real_capacity_waiter_without_taking_a_permit() {
    let shared = shared();
    let occupied = shared.acquire(8).unwrap();
    let slot = shared.slot(
        PathBuf::from("E:/fixture/queue.dme"),
        &BTreeMap::new(),
        None,
    );
    let request_key = key("E:/fixture/queue.dme");
    let old_token = control::Cancellation::default();
    let old = LatestRequest::register(&slot, request_key.clone(), old_token.clone());
    let worker_shared = Arc::clone(&shared);
    let (ready_send, ready_receive) = mpsc::channel();
    let (result_send, result_receive) = mpsc::channel();
    let worker = std::thread::spawn(move || {
        let _binding = control::bind(old_token);
        ready_send.send(()).unwrap();
        let result = worker_shared.acquire(1).map(|permit| drop(permit));
        result_send
            .send(result.map_err(|error| error.kind()))
            .unwrap();
    });
    ready_receive.recv_timeout(Duration::from_secs(2)).unwrap();
    assert!(matches!(
        result_receive.recv_timeout(Duration::from_millis(100)),
        Err(mpsc::RecvTimeoutError::Timeout)
    ));
    let new_token = control::Cancellation::default();
    let latest = LatestRequest::register(&slot, request_key.clone(), new_token.clone());
    assert_eq!(
        result_receive.recv_timeout(Duration::from_secs(2)).unwrap(),
        Err(io::ErrorKind::Interrupted)
    );
    worker.join().unwrap();
    assert_eq!(*shared.running.lock().unwrap(), 1);
    assert_eq!(*shared.workers.lock().unwrap(), 8);
    drop(old);
    assert!(slot
        .newest
        .lock()
        .unwrap()
        .get(&request_key)
        .unwrap()
        .same_request(&new_token));
    drop((latest, occupied));
    assert!(slot.newest.lock().unwrap().is_empty());
    assert_eq!(*shared.running.lock().unwrap(), 0);
    assert_eq!(*shared.workers.lock().unwrap(), 0);
}
#[test]
fn independent_output_destinations_do_not_cancel_each_other() {
    let shared = shared();
    let slot = shared.slot(
        PathBuf::from("E:/fixture/project.dme"),
        &BTreeMap::new(),
        None,
    );
    let a = control::Cancellation::default();
    let b = control::Cancellation::default();
    let first = LatestRequest::register(&slot, key("E:/fixture/a/world.dme"), a.clone());
    let second = LatestRequest::register(&slot, key("E:/fixture/b/world.dme"), b.clone());
    assert!(!a.is_cancelled());
    assert!(!b.is_cancelled());
    a.cancel();
    assert!(!b.is_cancelled());
    drop((first, second));
    assert!(slot.newest.lock().unwrap().is_empty());
}

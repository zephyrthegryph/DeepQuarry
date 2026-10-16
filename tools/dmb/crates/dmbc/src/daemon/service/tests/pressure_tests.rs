use super::*;
use std::sync::mpsc;

#[test]
fn queued_host_can_release_all_tiers_without_losing_slot_or_daemon_owners() {
    let shared = shared();
    let path = PathBuf::from("E:/fixture/queued.dme");
    let slot = shared.slot(path.clone(), &BTreeMap::new(), None);
    let deadline = admission_deadline::AdmissionDeadline::new(Instant::now());
    let _serial = slot.lock_request_until(&deadline).unwrap();
    for tier in [2, 3, 4] {
        shared.housekeep(Instant::now(), true, true);
        assert_eq!(slot.idle_tier.load(Ordering::Acquire), tier);
    }
    let roster = shared.slots.lock().unwrap();
    assert_eq!(roster.len(), 1);
    assert!(Arc::ptr_eq(&slot, roster.values().next().unwrap()));
    assert_eq!(Arc::strong_count(&shared.engines), 2);
}

#[test]
fn pressure_never_releases_a_currently_borrowed_host() {
    let shared = shared();
    let slot = shared.slot("E:/fixture/active.dme".into(), &BTreeMap::new(), None);
    let _host = slot.host.lock().unwrap();
    for _ in 0..4 { shared.housekeep(Instant::now(), true, true); }
    assert_eq!(slot.idle_tier.load(Ordering::Acquire), 0);
    assert_eq!(shared.slots.lock().unwrap().len(), 1);
}

#[test]
fn soft_pressure_defers_another_build_but_preserves_single_build_progress() {
    let shared = shared();
    // Observed memory sits at the soft limit, whatever the production default is.
    let pressured = shared.soft_private_bytes;
    let deadline = admission_deadline::AdmissionDeadline::new(Instant::now());
    let first = shared.acquire_until_observing(2, &deadline, move || Some(pressured)).unwrap();
    let worker_shared = Arc::clone(&shared);
    let (ready_send, ready_receive) = mpsc::channel();
    let (done_send, done_receive) = mpsc::channel();
    let worker = std::thread::spawn(move || {
        ready_send.send(()).unwrap();
        let permit = worker_shared.acquire_until_observing(2, &deadline, move || Some(pressured)).unwrap();
        done_send.send(()).unwrap();
        drop(permit);
    });
    ready_receive.recv_timeout(Duration::from_secs(2)).unwrap();
    assert!(matches!(done_receive.recv_timeout(Duration::from_millis(100)), Err(mpsc::RecvTimeoutError::Timeout)));
    assert_eq!(*shared.running.lock().unwrap(), 1);
    drop(first);
    done_receive.recv_timeout(Duration::from_secs(2)).unwrap();
    worker.join().unwrap();
    assert_eq!(*shared.running.lock().unwrap(), 0);
}

#[test]
fn same_slot_follower_waits_without_consuming_global_permit_and_can_cancel() {
    let shared = shared();
    let slot = shared.slot("E:/fixture/serial.dme".into(), &BTreeMap::new(), None);
    let deadline = admission_deadline::AdmissionDeadline::new(Instant::now());
    let _head = slot.lock_request_until(&deadline).unwrap();
    let token = control::Cancellation::default();
    let worker_token = token.clone();
    let worker_slot = Arc::clone(&slot);
    let (ready_send, ready_receive) = mpsc::channel();
    let (done_send, done_receive) = mpsc::channel();
    let worker = std::thread::spawn(move || {
        let _binding = control::bind(worker_token);
        let deadline = admission_deadline::AdmissionDeadline::new(Instant::now());
        ready_send.send(()).unwrap();
        let result = worker_slot.lock_request_until(&deadline).map(|guard| drop(guard));
        done_send.send(result.map_err(|error| error.kind())).unwrap();
    });
    ready_receive.recv_timeout(Duration::from_secs(2)).unwrap();
    assert!(matches!(done_receive.recv_timeout(Duration::from_millis(100)), Err(mpsc::RecvTimeoutError::Timeout)));
    assert_eq!(*shared.running.lock().unwrap(), 0);
    let unrelated = shared.acquire_until_observing(2, &deadline, || None).unwrap();
    token.cancel();
    assert_eq!(done_receive.recv_timeout(Duration::from_secs(2)).unwrap(), Err(io::ErrorKind::Interrupted));
    worker.join().unwrap();
    drop(unrelated);
}

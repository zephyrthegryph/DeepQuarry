//! Sequential requests share process tracing registration, never process certificates.
#[test]
fn requests_route_exact_state_dispatch_and_close_every_lifecycle() {
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let directory = std::path::PathBuf::from("E:/dq-cache/dmb-protocol-checks")
        .join(format!("request-context-{}-{stamp}", std::process::id()));
    std::fs::create_dir_all(&directory).unwrap();
    let obstruction = directory.join("file");
    std::fs::write(&obstruction, b"not a directory").unwrap();
    assert!(dm_profile::initialize(&obstruction.join("invalid.trace.json")).is_err());
    let first = dm_profile::initialize(&directory.join("first.trace.json")).unwrap();
    assert!(dm_profile::initialize(&directory.join("overlap.trace.json")).is_err());
    let exact = first.request_context();
    let captured;
    {
        let _parent = dm_profile::stage("first");
        captured = dm_profile::StageContext::capture();
        let worker_context = captured.clone();
        std::thread::spawn(move || {
            let _context = worker_context.enter();
            let _lifetime = dm_profile::worker_lifetime("compiler.worker_lifetime");
            let _leaf = dm_profile::stage("first.worker");
            dm_profile::tracing::info!(marker = "first-only", "request event");
        })
        .join()
        .unwrap();
    }
    let first_report = first.finish(&["first"]).unwrap();
    assert!(first_report
        .stages
        .iter()
        .any(|stage| stage.name == "first.worker"));
    assert!(first_report
        .stages
        .iter()
        .any(|stage| stage.name == "compiler.worker_lifetime"));
    assert!(dm_profile::RequestContext::capture().is_none());
    assert!(exact.enter().is_err());
    let second = dm_profile::initialize(&directory.join("second.trace.json")).unwrap();
    assert_ne!(exact, second.request_context());
    assert!(std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| captured.enter())).is_err());
    {
        let _stage = dm_profile::stage("second");
        dm_profile::tracing::info!(marker = "second-only", "request event");
    }
    let second_report = second.finish(&["second"]).unwrap();
    assert!(second_report
        .stages
        .iter()
        .all(|stage| !stage.name.starts_with("first")));
    let first_trace = std::fs::read_to_string(directory.join("first.trace.json")).unwrap();
    let second_trace = std::fs::read_to_string(directory.join("second.trace.json")).unwrap();
    assert!(first_trace.contains("first-only"));
    assert!(!first_trace.contains("second-only"));
    assert!(second_trace.contains("second-only"));
    assert!(!second_trace.contains("first-only"));
    // Certification refuses outstanding pool lifetime coverage; cleanup closes
    // the failed request and leaves the next sequential request usable.
    let unjoined = dm_profile::initialize(&directory.join("unjoined.trace.json")).unwrap();
    let lifetime = dm_profile::worker_lifetime("compiler.worker_lifetime");
    assert!(unjoined
        .finish(&[])
        .unwrap_err()
        .contains("worker lifetimes joined"));
    drop(lifetime);
    assert!(dm_profile::RequestContext::capture().is_none());
    let bound_request = dm_profile::initialize(&directory.join("bound.trace.json")).unwrap();
    let token = bound_request.request_context();
    let (ready_send, ready_recv) = std::sync::mpsc::channel();
    let (release_send, release_recv) = std::sync::mpsc::channel();
    let external = std::thread::spawn(move || {
        // Merely running on another thread cannot inherit the active request.
        assert!(dm_profile::RequestContext::capture().is_none());
        let _binding = token.enter().unwrap();
        ready_send.send(()).unwrap();
        release_recv.recv().unwrap();
        // Finishing sealed context admission before taking the snapshot.
        assert!(token.enter().is_err());
        assert!(dm_profile::RequestContext::capture().is_none());
    });
    ready_recv.recv().unwrap();
    assert!(bound_request.finish(&[]).is_err());
    assert!(dm_profile::initialize(&directory.join("still-bound.trace.json")).is_err());
    release_send.send(()).unwrap();
    external.join().unwrap();
    let dropped = dm_profile::initialize(&directory.join("dropped.trace.json")).unwrap();
    drop(dropped);
    assert!(dm_profile::RequestContext::capture().is_none());
    let final_request = dm_profile::initialize(&directory.join("final.trace.json")).unwrap();
    {
        let _stage = dm_profile::stage("final");
    }
    final_request.finish(&["final"]).unwrap();
    std::fs::remove_dir_all(directory).unwrap();
}

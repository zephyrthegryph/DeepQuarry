//! Actual protocol/production publication over the existing tiny fixture core.
use super::*;

fn accept_until(listener: &transport::Listener) -> io::Result<transport::Stream> {
    let deadline = Instant::now() + Duration::from_secs(2);
    loop {
        if let Some(stream) = listener.try_accept()? {
            return Ok(stream);
        }
        if Instant::now() >= deadline {
            return Err(io::Error::new(
                io::ErrorKind::TimedOut,
                "fixture pipe acceptance expired",
            ));
        }
        std::thread::sleep(Duration::from_millis(2));
    }
}
pub(super) fn serve_once(listener: &transport::Listener, shared: &Arc<Shared>) -> io::Result<()> {
    let stream = accept_until(listener)?;
    shared.connections.fetch_add(1, Ordering::AcqRel);
    let _connection = Connection(Arc::clone(shared));
    // Actual service handler: ticket issuance, per-session ordering, worker
    // admission, the retained host/executor core and terminal reply are shared.
    handle(stream, shared, false)
}
pub(super) fn hello(endpoint: &transport::Endpoint, compiler: u128, retiring: bool) -> transport::Stream {
    let mut stream = transport::connect(endpoint).unwrap();
    transport::set_timeout(&mut stream, Duration::from_secs(5)).unwrap();
    protocol::send(
        &mut stream,
        &Request::Hello {
            version: protocol::VERSION,
            compiler,
        },
    )
    .unwrap();
    assert!(
        matches!(protocol::receive::<Reply>(&mut stream).unwrap(), Reply::Hello {
        version: protocol::VERSION, compiler: actual, retiring: actual_retiring,
    } if actual == compiler && actual_retiring == retiring)
    );
    stream
}
fn complete(stream: &mut transport::Stream) -> BuildOutcome {
    let deadline = Instant::now() + Duration::from_secs(30);
    loop {
        let remaining = deadline
            .checked_duration_since(Instant::now())
            .unwrap_or(Duration::ZERO);
        assert!(
            !remaining.is_zero(),
            "tiny fixture build completion expired"
        );
        transport::set_timeout(stream, remaining).unwrap();
        match protocol::receive::<Reply>(stream).unwrap() {
            Reply::Diagnostic { .. } => {}
            Reply::Completed(outcome) => return outcome,
            Reply::Rejected(error) => panic!("accepted fixture build rejected: {error}"),
            _ => panic!("unexpected reply after Accepted"),
        }
    }
}

#[test]
fn accepted_queued_pipe_build_completes_after_retirement_while_new_generation_publishes() {
    let roots = Roots::new();
    let nonce = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let old_id = nonce ^ (u128::from(std::process::id()) << 64);
    let new_id = old_id ^ (1 << 127);
    let old_endpoint = transport::Endpoint::generation(old_id).unwrap();
    let new_endpoint = transport::Endpoint::generation(new_id).unwrap();
    let old_listener = transport::listener(&old_endpoint).unwrap();
    let new_listener = transport::listener(&new_endpoint).unwrap();
    let mut old = shared();
    let old_mut = Arc::get_mut(&mut old).unwrap();
    old_mut.compiler = old_id;
    old_mut.max_workers = 1;
    let mut new = shared();
    let new_mut = Arc::get_mut(&mut new).unwrap();
    new_mut.compiler = new_id;
    new_mut.max_workers = 1;
    let old_request = request(&roots, 0, false);
    let old_destination = old_request.artifact_directory.clone().unwrap();
    let new_request = request(&roots, 1, false);
    let new_destination = new_request.artifact_directory.clone().unwrap();

    std::thread::scope(|scope| {
        // Keep the permit inside the scope body so failure unwinding releases
        // capacity before scope waits for the production request thread.
        let mut occupied = Some(
            old.acquire_until_observing(
                1,
                &admission_deadline::AdmissionDeadline::new(Instant::now()),
                || Some(0),
            )
            .unwrap(),
        );
        let old_server = scope.spawn(|| serve_once(&old_listener, &old));
        let mut old_client = hello(&old_endpoint, old_id, false);
        protocol::send(&mut old_client, &Request::Build(old_request)).unwrap();
        assert!(matches!(
            protocol::receive::<Reply>(&mut old_client).unwrap(),
            Reply::Accepted
        ));
        assert_eq!(*old.running.lock().unwrap(), 1);
        assert!(
            !old_destination.join("probe.dmb").exists(),
            "accepted work must still be capacity-queued"
        );

        let retire_server = scope.spawn(|| serve_once(&old_listener, &old));
        let mut retirement = hello(&old_endpoint, old_id, false);
        protocol::send(&mut retirement, &Request::Retire).unwrap();
        assert!(matches!(
            protocol::receive::<Reply>(&mut retirement).unwrap(),
            Reply::Retiring
        ));
        drop(retirement);
        retire_server.join().unwrap().unwrap();
        assert!(old.retiring.load(Ordering::Acquire));
        assert!(!old.exit_ready(false, Duration::ZERO));

        // The new compiler generation serves a real independent worktree
        // request while the old accepted build remains queued and drainable.
        let new_server = scope.spawn(|| serve_once(&new_listener, &new));
        let mut new_client = hello(&new_endpoint, new_id, false);
        protocol::send(&mut new_client, &Request::Build(new_request)).unwrap();
        assert!(matches!(
            protocol::receive::<Reply>(&mut new_client).unwrap(),
            Reply::Accepted
        ));
        let new_pair = published(complete(&mut new_client), &new_destination);
        drop(new_client);
        new_server.join().unwrap().unwrap();
        assert!(!old_destination.join("probe.dmb").exists());

        // A request arriving after the retirement barrier is rejected before
        // Accepted; it neither cancels nor replaces the old queued request.
        let rejected_server = scope.spawn(|| serve_once(&old_listener, &old));
        let mut rejected = hello(&old_endpoint, old_id, true);
        protocol::send(&mut rejected, &Request::Build(request(&roots, 2, false))).unwrap();
        let Reply::Rejected(error) = protocol::receive::<Reply>(&mut rejected).unwrap() else {
            panic!("retired generation must not accept another build");
        };
        assert_eq!(
            error.kind,
            crate::request_failure::FailureKind::Infrastructure
        );
        drop(rejected);
        rejected_server.join().unwrap().unwrap();

        drop(occupied.take());
        let old_pair = published(complete(&mut old_client), &old_destination);
        drop(old_client);
        old_server.join().unwrap().unwrap();
        assert_eq!(
            old_pair.1, new_pair.1,
            "the same tiny source must publish the same DMB through both generations"
        );
        assert_eq!(old_pair.2, new_pair.2);
        assert_eq!(*old.running.lock().unwrap(), 0);
        assert_eq!(*old.workers.lock().unwrap(), 0);
        assert_eq!(old.connections.load(Ordering::Acquire), 0);
        assert!(old.exit_ready(false, Duration::ZERO));
    });
}

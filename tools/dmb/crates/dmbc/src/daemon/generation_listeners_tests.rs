use super::*;
use std::io::{Read, Write};

fn identities() -> (u128, u128, u128) {
    static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
    let value = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos()
        ^ (u128::from(std::process::id()) << 64)
        ^ u128::from(NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed));
    (value, value ^ (1 << 127), value ^ (1 << 126))
}
fn accepted(listeners: &mut Listeners) -> Incoming {
    let deadline = Instant::now() + Duration::from_secs(2);
    loop {
        if let Some(incoming) = listeners.poll(false, Instant::now()).unwrap() {
            return incoming;
        }
        assert!(
            Instant::now() < deadline,
            "local generation did not accept its connected client"
        );
        std::thread::sleep(Duration::from_millis(2));
    }
}

#[test]
fn new_generation_accepts_while_old_stream_drains_and_discovery_transfers() {
    let (old_id, new_id, discovery_id) = identities();
    let old_endpoint = transport::Endpoint::generation(old_id).unwrap();
    let new_endpoint = transport::Endpoint::generation(new_id).unwrap();
    // Test-owned namespace; never claim the real user discovery endpoint.
    let discovery_endpoint = transport::Endpoint::generation(discovery_id).unwrap();
    let mut old = Listeners::bind(old_endpoint.clone(), discovery_endpoint.clone()).unwrap();
    let mut old_client = transport::connect(&old_endpoint).unwrap();
    let old_incoming = accepted(&mut old);
    assert!(!old_incoming.discovery);
    let mut old_stream = old_incoming.stream;
    let mut new = Listeners::bind(new_endpoint.clone(), discovery_endpoint.clone()).unwrap();
    assert!(
        new.discovery.is_none(),
        "old owns discovery while new already owns its generation"
    );
    let mut new_client = transport::connect(&new_endpoint).unwrap();
    let new_incoming = accepted(&mut new);
    assert!(!new_incoming.discovery);
    let mut new_stream = new_incoming.stream;
    new_stream.write_all(b"new").unwrap();
    let mut bytes = [0; 3];
    new_client.read_exact(&mut bytes).unwrap();
    assert_eq!(&bytes, b"new");

    assert!(old.poll(true, Instant::now()).unwrap().is_none());
    assert!(old.generation.is_none() && old.discovery.is_none());
    // Retirement drops listening handles only. This already accepted request
    // keeps its original stream and finishes after the replacement is serving.
    old_stream.write_all(b"old").unwrap();
    old_client.read_exact(&mut bytes).unwrap();
    assert_eq!(&bytes, b"old");
    new.poll(false, Instant::now() + Duration::from_secs(2))
        .unwrap();
    assert!(new.discovery.is_some());
    let mut discovery_client = transport::connect(&discovery_endpoint).unwrap();
    let incoming = accepted(&mut new);
    assert!(
        incoming.discovery,
        "discovery role cannot become a build connection"
    );
    let mut discovery_stream = incoming.stream;
    discovery_stream.write_all(b"new").unwrap();
    discovery_client.read_exact(&mut bytes).unwrap();
    assert_eq!(&bytes, b"new");
}

#[test]
fn same_generation_cannot_steal_live_listener_or_discovery() {
    let (generation_id, other_id, discovery_id) = identities();
    let generation = transport::Endpoint::generation(generation_id).unwrap();
    let discovery = transport::Endpoint::generation(discovery_id).unwrap();
    let first = Listeners::bind(generation.clone(), discovery.clone()).unwrap();
    assert_eq!(
        Listeners::bind(generation, discovery.clone())
            .err()
            .unwrap()
            .kind(),
        io::ErrorKind::AddrInUse
    );
    let second = Listeners::bind(
        transport::Endpoint::generation(other_id).unwrap(),
        discovery,
    )
    .unwrap();
    assert!(first.discovery.is_some());
    assert!(second.discovery.is_none());
}

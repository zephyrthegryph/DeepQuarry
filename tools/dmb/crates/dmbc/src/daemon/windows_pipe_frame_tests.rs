use super::*;
use crate::daemon::protocol;
use std::{sync::mpsc, time::Duration};

fn endpoint() -> Endpoint {
    let mut endpoint = Endpoint::current().unwrap();
    static NEXT: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);
    endpoint.name = wide(&format!(
        r"\\.\pipe\dmbd-frame-test-{}-{}-{}",
        endpoint.sid,
        std::process::id(),
        NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed)
    ));
    endpoint
}
fn client(endpoint: &Endpoint) -> Stream {
    (0..200)
        .find_map(|_| {
            let stream = connect(endpoint).ok();
            if stream.is_none() {
                std::thread::sleep(Duration::from_millis(5));
            }
            stream
        })
        .expect("private current-user frame test pipe connects")
}

#[test]
fn large_frames_cross_pipe_quota_in_both_directions_and_preserve_following_frame() {
    let endpoint = endpoint();
    let listener = listener(&endpoint).unwrap();
    // Match the actual 128-row page shape, with enough per-row data to exceed
    // the 64KiB kernel quota. Do not shrink the logical request or reply.
    let value = serde_json::json!({"items": (0..128).map(|ordinal| serde_json::json!({
        "ordinal": ordinal, "provenance": "source\\nested\\current.dm".repeat(80),
    })).collect::<Vec<_>>()});
    assert!(serde_json::to_vec(&value).unwrap().len() > 65536);
    let expected = value.clone();
    let (ack_send, ack_receive) = mpsc::channel();
    let worker = std::thread::spawn(move || {
        let mut stream = listener.accept().unwrap();
        set_timeout(&mut stream, Duration::from_secs(5)).unwrap();
        let received: serde_json::Value = protocol::receive(&mut stream).unwrap();
        assert_eq!(received, expected);
        protocol::send(&mut stream, &received).unwrap();
        protocol::send(&mut stream, &serde_json::json!({"following": true})).unwrap();
        ack_receive.recv_timeout(Duration::from_secs(5)).unwrap();
    });
    let mut stream = client(&endpoint);
    set_timeout(&mut stream, Duration::from_secs(5)).unwrap();
    protocol::send(&mut stream, &value).unwrap();
    let received: serde_json::Value = protocol::receive(&mut stream).unwrap();
    assert_eq!(received, value);
    let following: serde_json::Value = protocol::receive(&mut stream).unwrap();
    assert_eq!(following, serde_json::json!({"following": true}));
    ack_send.send(()).unwrap();
    worker.join().unwrap();
}

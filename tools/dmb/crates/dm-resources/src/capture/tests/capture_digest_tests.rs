use super::*;

#[test]
fn repeated_capture_uses_one_snapshot_and_preserves_digest_observations() {
    let provider = memory(&[("game/a.txt", b"payload")]);
    let policy = policy();
    let additional = [ResourceRequest {
        archive_name: "a.txt".into(),
        disk_path: PathBuf::from("game/a.txt"),
    }];
    let captured = capture_expanded(
        &plan(),
        &expanded("/proc/p()\n    return 'a.txt'\n"),
        CaptureConfig {
            policy: &policy,
            encoded: &[],
            additional: &additional,
        },
        &provider,
    )
    .unwrap();
    let digest: [u8; 32] = Sha256::digest(b"payload").into();
    assert_eq!(
        provider.reads.borrow().as_slice(),
        &[PathBuf::from("game/a.txt")]
    );
    assert_eq!(captured.observations.len(), 2);
    assert!(
        captured
            .observations
            .iter()
            .all(|observation| observation.outcome
                == CandidateOutcome::Captured { digest, length: 7 })
    );
    assert_eq!(captured.resources.inputs.len(), 1);
    assert_eq!(captured.resources.inputs[0].content_digest, digest);
    assert_eq!(
        captured.resources.inputs[0].named.asset_bytes().unwrap(),
        b"payload"
    );
}

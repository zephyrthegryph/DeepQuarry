//! Bounded rebuilds belong to the shared runner, before publication is sealed.
use crate::input_snapshot::{InputSnapshot, SnapshotProvider};
use crate::request::{BuildOutcome, BuildRequest};
use std::{error::Error, fmt};

#[derive(Debug)]
struct InputsMoved(std::io::Error);
impl Default for InputsMoved {
    fn default() -> Self {
        Self(std::io::Error::new(
            std::io::ErrorKind::Interrupted,
            "captured inputs moved",
        ))
    }
}
impl fmt::Display for InputsMoved {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("inputs changed before publication")
    }
}
impl Error for InputsMoved {
    fn source(&self) -> Option<&(dyn Error + 'static)> {
        Some(&self.0)
    }
}

pub(super) fn run(
    request: BuildRequest,
    mut attempt: impl FnMut(BuildRequest, bool) -> Result<BuildOutcome, Box<dyn Error>>,
) -> Result<BuildOutcome, Box<dyn Error>> {
    // A recording journal is immutable and cannot be overwritten by a retry.
    // Reject moving inputs there; the verification caller captures a new journal.
    let journal = request.record_inputs.is_some() || request.replay_inputs.is_some();
    retry(!journal, |allow_moving| {
        attempt(request.clone(), allow_moving)
    })
}

fn retry<T>(
    enabled: bool,
    mut attempt: impl FnMut(bool) -> Result<T, Box<dyn Error>>,
) -> Result<T, Box<dyn Error>> {
    for index in 0..3 {
        crate::daemon::control::checkpoint()?;
        match attempt(enabled && index == 2) {
            Err(error) if error.is::<InputsMoved>() && enabled && index < 2 => {
                crate::daemon_eprintln!(
                    "native inputs changed before publication; rebuilding ({}/2)",
                    index + 1
                );
            }
            result => return result,
        }
    }
    unreachable!("last attempt always returns")
}

pub(super) fn admit(
    inputs: &InputSnapshot,
    provider: &impl SnapshotProvider,
    allow_moving_snapshot: bool,
) -> Result<(), Box<dyn Error>> {
    crate::daemon::control::checkpoint()?;
    if inputs.restat(provider)?.unchanged() {
        return Ok(());
    }
    if allow_moving_snapshot {
        crate::daemon_eprintln!("native inputs are still changing after two rebuilds; publishing the latest captured snapshot");
        Ok(())
    } else {
        Err(Box::new(InputsMoved::default()))
    }
}

pub(super) fn admit_live(inputs: &InputSnapshot, allow_moving: bool) -> Result<(), Box<dyn Error>> {
    let current = crate::filesystem_proofs::BulkFileSystemProofs::capture_snapshot(inputs)?;
    admit(inputs, &current, allow_moving)
}

pub(super) fn admit_captured(
    capture: &crate::input_snapshot::RecordingInputs<&crate::frozen_inputs::Inputs>,
    retained: Option<&InputSnapshot>,
    provider: &crate::frozen_inputs::Inputs,
    allow_moving: bool,
) -> Result<InputSnapshot, Box<dyn Error>> {
    let mut inputs = capture.snapshot()?;
    if let Some(retained) = retained {
        inputs.merge(retained)?;
    }
    if matches!(provider, crate::frozen_inputs::Inputs::Replay(_)) {
        admit(&inputs, provider, false)?;
    } else {
        admit_live(&inputs, allow_moving)?;
    }
    Ok(inputs)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn changed_capture_rebuilds_before_publication_and_final_snapshot_is_explicit() {
        use crate::input_snapshot::{FolderListing, Stamp};
        struct Current;
        impl SnapshotProvider for Current {
            fn stamp(&self, _: &std::path::Path) -> std::io::Result<Stamp> {
                Ok(Stamp {
                    size: 1,
                    modified_ns: 2,
                    file_id: Some(1),
                })
            }
            fn read(&self, _: &std::path::Path) -> std::io::Result<(Stamp, Vec<u8>)> {
                panic!("freshness admission must not reread payloads")
            }
            fn list(&self, _: &std::path::Path) -> std::io::Result<FolderListing> {
                panic!("no search folders captured")
            }
        }
        let mut inputs = InputSnapshot::new(1);
        inputs
            .record_file(
                std::path::Path::new("source.dm"),
                Stamp {
                    size: 1,
                    modified_ns: 1,
                    file_id: Some(1),
                },
                b"x",
            )
            .unwrap();
        let error = admit(&inputs, &Current, false).unwrap_err();
        assert!(error.is::<InputsMoved>());
        assert_eq!(
            crate::request_failure::classify(error.as_ref()),
            crate::request_failure::FailureKind::Cancelled
        );
        admit(&inputs, &Current, true).unwrap();
    }
    #[test]
    fn rebuild_policy_stops_at_three_and_does_not_retry_unrelated_failures() {
        let mut visits = Vec::new();
        let outcome = retry(true, |allow| {
            visits.push(allow);
            if allow {
                Ok(7)
            } else {
                Err(Box::new(InputsMoved::default()))
            }
        })
        .unwrap();
        assert_eq!(outcome, 7);
        assert_eq!(visits, [false, false, true]);
        let mut failures = 0;
        assert!(retry::<()>(true, |_| {
            failures += 1;
            Err(std::io::Error::other("publication failure").into())
        })
        .is_err());
        assert_eq!(failures, 1);
        let mut journals = 0;
        assert!(retry::<()>(false, |_| {
            journals += 1;
            Err(Box::new(InputsMoved::default()))
        })
        .is_err());
        assert_eq!(journals, 1);
    }
}

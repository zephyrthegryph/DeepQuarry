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
    mut attempt: impl FnMut(BuildRequest) -> Result<BuildOutcome, Box<dyn Error>>,
) -> Result<BuildOutcome, Box<dyn Error>> {
    // A recording journal is immutable and cannot be overwritten by a retry.
    // Reject moving inputs there; the verification caller captures a new journal.
    let journal = request.record_inputs.is_some() || request.replay_inputs.is_some();
    retry(!journal, || attempt(request.clone()))
}

fn retry<T>(
    enabled: bool,
    mut attempt: impl FnMut() -> Result<T, Box<dyn Error>>,
) -> Result<T, Box<dyn Error>> {
    for index in 0..3 {
        crate::daemon::control::checkpoint()?;
        match attempt() {
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
) -> Result<(), Box<dyn Error>> {
    crate::daemon::control::checkpoint()?;
    let validation = inputs.restat(provider)?;
    if validation.unchanged() {
        return Ok(());
    }
    // Publication is never allowed to bypass captured-input freshness, including
    // the final bounded retry. Show a bounded sample to diagnose self-invalidation.
    crate::daemon_eprintln!(
        "native publication rejected: {} changed inputs; first paths: {:?}",
        validation.changed.len(),
        validation.changed.iter().take(8).collect::<Vec<_>>()
    );
    Err(Box::new(InputsMoved::default()))
}

pub(super) fn admit_live(
    inputs: &InputSnapshot,
    generated_outputs: &std::collections::BTreeSet<std::path::PathBuf>,
) -> Result<(), Box<dyn Error>> {
    let current = crate::filesystem_proofs::BulkFileSystemProofs::capture_snapshot(inputs)?;
    let current = crate::input_snapshot::GeneratedOutputInputs::new(
        &current,
        generated_outputs.iter().cloned(),
    );
    admit(inputs, &current)
}

pub(super) fn admit_captured<P: SnapshotProvider>(
    capture: &crate::input_snapshot::RecordingInputs<P>,
    retained: Option<&InputSnapshot>,
    provider: &crate::frozen_inputs::Inputs,
    generated_outputs: &std::collections::BTreeSet<std::path::PathBuf>,
) -> Result<InputSnapshot, Box<dyn Error>> {
    let mut inputs = capture.snapshot()?;
    if let Some(retained) = retained {
        inputs.merge(retained)?;
    }
    if matches!(provider, crate::frozen_inputs::Inputs::Replay(_)) {
        let current = crate::input_snapshot::GeneratedOutputInputs::new(
            provider,
            generated_outputs.iter().cloned(),
        );
        admit(&inputs, &current)?;
    } else {
        admit_live(&inputs, generated_outputs)?;
    }
    Ok(inputs)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn changed_capture_never_publishes_even_on_final_attempt() {
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
        let error = admit(&inputs, &Current).unwrap_err();
        assert!(error.is::<InputsMoved>());
        assert_eq!(
            crate::request_failure::classify(error.as_ref()),
            crate::request_failure::FailureKind::Cancelled
        );
    }
    #[test]
    fn rebuild_policy_stops_at_three_and_does_not_retry_unrelated_failures() {
        let mut visits = 0;
        let outcome = retry::<()>(true, || {
            visits += 1;
            Err(Box::new(InputsMoved::default()))
        });
        assert!(outcome.unwrap_err().is::<InputsMoved>());
        assert_eq!(visits, 3);
        let mut successful_visits = 0;
        assert_eq!(
            retry(true, || {
                successful_visits += 1;
                if successful_visits < 3 {
                    Err(Box::new(InputsMoved::default()))
                } else {
                    Ok(7)
                }
            })
            .unwrap(),
            7
        );
        let mut failures = 0;
        assert!(retry::<()>(true, || {
            failures += 1;
            Err(std::io::Error::other("publication failure").into())
        })
        .is_err());
        assert_eq!(failures, 1);
        let mut journals = 0;
        assert!(retry::<()>(false, || {
            journals += 1;
            Err(Box::new(InputsMoved::default()))
        })
        .is_err());
        assert_eq!(journals, 1);
    }
}

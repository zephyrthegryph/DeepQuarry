//! Conventional destinations are request-local even when the immutable pair is reused.
use super::*;
use crate::input_snapshot::{FolderListing, Stamp};
use std::cell::Cell;

struct Outputs {
    calls: Cell<usize>,
}
impl SnapshotProvider for Outputs {
    fn stamp(&self, _: &Path) -> io::Result<Stamp> {
        self.calls.set(self.calls.get() + 1);
        Ok(stamp())
    }
    fn read(&self, path: &Path) -> io::Result<(Stamp, Vec<u8>)> {
        Ok((self.stamp(path)?, b"output".to_vec()))
    }
    fn list(&self, _: &Path) -> io::Result<FolderListing> {
        panic!("output validation must not inspect folders")
    }
}
fn stamp() -> Stamp {
    Stamp {
        size: 6,
        modified_ns: 1,
        file_id: Some(9),
    }
}
fn captured(project: &Path) -> InputSnapshot {
    let mut outputs = InputSnapshot::new(10_000_000_000);
    for extension in ["dmb", "rsc", "dmb-pair.json"] {
        outputs
            .record_file(&project.with_extension(extension), stamp(), b"output")
            .unwrap();
    }
    outputs
}
fn validated(outputs: InputSnapshot) -> ValidatedRecord {
    ValidatedRecord {
        record: Record {
            inputs: InputSnapshot::new(0),
            pair: 7,
            outputs: Some(outputs),
            resource_manifest: None,
        },
        validation: Validation::default(),
        timings: ValidationTimings::default(),
    }
}

#[test]
fn changed_destination_requires_install_without_scanning_previous_files() {
    let old = Path::new("E:/dq-cache/session-output-fixture/old/project.dme");
    let current = Path::new("E:/dq-cache/session-output-fixture/current/project.dme");
    let provider = Outputs {
        calls: Cell::new(0),
    };
    let mut record = validated(captured(old));
    assert_eq!(
        record
            .refresh_outputs_at(current, &provider, true, 20_000_000_000)
            .unwrap(),
        (false, 0)
    );
    assert_eq!(provider.calls.get(), 0);
    assert_eq!(
        record
            .refresh_outputs_at(old, &provider, true, 20_000_000_000)
            .unwrap(),
        (true, 3)
    );
    // Exact validation checks the stamp and then authenticates the bytes of
    // each file; this fixture's read also obtains its own stamp.
    assert_eq!(provider.calls.get(), 6);
}

#[test]
fn nonexact_output_fact_rosters_require_install_without_provider_calls() {
    let project = Path::new("E:/dq-cache/session-output-fixture/project.dme");
    let provider = Outputs {
        calls: Cell::new(0),
    };
    let mut extra = captured(project);
    extra
        .record_file(
            Path::new("E:/dq-cache/session-output-fixture/extra"),
            stamp(),
            b"output",
        )
        .unwrap();
    let mut negative = captured(project);
    negative
        .record_negative(Path::new("E:/dq-cache/session-output-fixture/missing"))
        .unwrap();
    let mut folder = captured(project);
    folder
        .record_folder(
            Path::new("E:/dq-cache/session-output-fixture/folder"),
            FolderListing::Missing,
        )
        .unwrap();
    let mut missing = InputSnapshot::new(10_000_000_000);
    missing
        .record_file(&project.with_extension("dmb"), stamp(), b"output")
        .unwrap();
    for outputs in [extra, negative, folder, missing] {
        assert_eq!(
            validated(outputs)
                .refresh_outputs_at(project, &provider, true, 20_000_000_000)
                .unwrap(),
            (false, 0)
        );
    }
    assert_eq!(provider.calls.get(), 0);
}

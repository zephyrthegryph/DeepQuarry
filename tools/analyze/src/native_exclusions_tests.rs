use super::*;
use crate::selected_exclusions_wire::{Frame, Schema};
#[path = "../../dmb/shared/test_scratch.rs"]
mod scratch;

fn seal(bytes: &[u8]) -> Seal {
    Seal { length: bytes.len() as u64, hash: Hex128(xxhash_rust::xxh3::xxh3_128(bytes)) }
}

fn terminal(report: &[u8], diagnostics: Option<&[u8]>, clean: bool) -> Terminal {
    Terminal {
        schema: Schema::V1, roster: Roster::WithSilicon,
        frame: Frame { semantic_revision: Hex128(1), source_revision: Hex128(2), policy_revision: Hex128(3) },
        clean, report: seal(report), diagnostics: diagnostics.map(seal),
    }
}

fn envelope(header: &impl serde::Serialize, report: &[u8]) -> Vec<u8> {
    let mut bytes = serde_json::to_vec(header).unwrap();
    bytes.push(b'\n');
    bytes.extend_from_slice(report);
    bytes
}

fn run(
    status: i32, stdout: &[u8], stderr: &[u8], root: &Path, expected: Roster,
    output: &mut Vec<u8>, diagnostics: &mut Vec<u8>,
) -> io::Result<u8> {
    let stdout = capture_stdout(stdout, root, expected)?;
    let stderr = Captured::read(&mut &*stderr, root, MAX_STREAM)?;
    deliver(Some(status), stdout, stderr, output, diagnostics)
}

#[test]
fn native_exclusions_publishes_exact_machine_and_diagnostic_bytes_after_both_validate() {
    let root = scratch::dir("analyze-exclusions-client-complete");
    let report = [b'R'; BLOCK + 7];
    let stderr = b"actual original diagnostic \xce\xbb \xff\n";
    for (status, diagnostics) in [(0, None), (1, Some(stderr.as_slice()))] {
        let header = terminal(&report, diagnostics, status == 0);
        let wire = envelope(&header, &report);
        let mut output = Vec::new();
        let mut actual_diagnostics = Vec::new();
        assert_eq!(run(status, &wire, diagnostics.unwrap_or_default(), &root, header.roster,
            &mut output, &mut actual_diagnostics).unwrap(), status as u8);
        assert_eq!(output, wire);
        assert_eq!(actual_diagnostics, diagnostics.unwrap_or_default());
    }
    assert_eq!(fs::read_dir(root).unwrap().count(), 0);
}

#[test]
fn native_exclusions_malformed_batches_leave_both_writers_untouched() {
    let root = scratch::dir("analyze-exclusions-client-malformed");
    let report = b"actual report\n";
    let stderr = b"actual notice\n";
    let terminal = terminal(report, Some(stderr), true);
    let valid = envelope(&terminal, report);
    let mut trailer = valid.clone();
    trailer.push(b'x');
    let mut missing = serde_json::to_value(terminal).unwrap();
    missing.as_object_mut().unwrap().remove("diagnostics");
    let mut wrong_pin = serde_json::to_value(terminal).unwrap();
    wrong_pin["frame"]["policy_revision"] = serde_json::json!("NOT_VALID");
    let oversized = [b'x'; MAX_HEADER + 1];
    for (status, stdout, diagnostics, expected) in [
        (1, valid.clone(), stderr.as_slice(), terminal.roster),
        (2, valid.clone(), stderr.as_slice(), terminal.roster),
        (0, valid.clone(), stderr.as_slice(), Roster::Base),
        (0, valid.clone(), b"different notice\n", terminal.roster),
        (0, valid.clone(), b"", terminal.roster),
        (0, envelope(&terminal, &report[..report.len() - 1]), stderr.as_slice(), terminal.roster),
        (0, envelope(&terminal, b"foreign bytes\n"), stderr.as_slice(), terminal.roster),
        (0, envelope(&missing, report), stderr.as_slice(), terminal.roster),
        (0, envelope(&wrong_pin, report), stderr.as_slice(), terminal.roster),
        (0, trailer, stderr.as_slice(), terminal.roster),
        (0, oversized.to_vec(), stderr.as_slice(), terminal.roster),
        (0, Vec::new(), stderr.as_slice(), terminal.roster),
    ] {
        let mut output = Vec::new();
        let mut diagnostics_output = Vec::new();
        assert!(run(status, &stdout, diagnostics, &root, expected, &mut output, &mut diagnostics_output).is_err());
        assert!(output.is_empty() && diagnostics_output.is_empty());
    }
    assert!(Captured::read(&mut &b"oversized"[..], &root, 3).is_err());
    assert_eq!(fs::read_dir(root).unwrap().count(), 0);
}

#[test]
fn native_exclusions_refusal_has_no_batch_and_preserves_cancellation() {
    let root = scratch::dir("analyze-exclusions-client-cancelled");
    let mut stdout = Vec::new();
    let mut stderr = Vec::new();
    assert_eq!(run(75, b"", b"superseded\n", &root, Roster::Base, &mut stdout, &mut stderr).unwrap(), 75);
    assert!(stdout.is_empty());
    assert_eq!(stderr, b"superseded\n");
}

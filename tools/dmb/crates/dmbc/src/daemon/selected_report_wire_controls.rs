use super::*;
use dm_preprocess::source_arena_credit::{SourceArenaCredit, SourceArenaCreditOwner};
use serde_json::{json, Value};
use std::sync::Arc;

struct Credit(usize);
impl SourceArenaCreditOwner for Credit {
    fn as_any(&self) -> &dyn std::any::Any { self }
    fn reserved_bytes(&self) -> usize { self.0 }
    fn visit_storage(&self, _: &mut dyn FnMut(usize, usize)) {}
}
struct Work { allow: bool }
impl SourceArenaWork for Work {
    fn checkpoint(&self) -> io::Result<()> { control::checkpoint() }
    fn reserve(&self, bytes: usize) -> io::Result<SourceArenaCredit> {
        assert_eq!(bytes, SEND_SCRATCH);
        if !self.allow { return Err(io::ErrorKind::OutOfMemory.into()); }
        Ok(SourceArenaCredit::from_resource_owner(Arc::new(Credit(bytes))))
    }
    fn grow(&self, _: &mut SourceArenaCredit, _: usize) -> io::Result<()> { panic!("only one framing reserve") }
    fn shrink(&self, _: &mut SourceArenaCredit, _: usize) -> io::Result<()> { panic!("framing credit lives through terminal") }
}

fn frame() -> Frame {
    Frame::from_prepared(&BuildOutcome::QueryPrepared {
        semantic_revision: format!("{:032x}", 1), source_revision: format!("{:032x}", 2),
        policy_revision: Some(format!("{:032x}", 3)), retained: true,
    }).unwrap()
}

fn verified(cache: &Path, text: &[u8]) -> Verified {
    let mut stage = Stage::new(cache).unwrap();
    stage.write_all(text).unwrap();
    let (file, length) = stage.seal().unwrap().validate(|read| io::copy(read, &mut io::sink())).unwrap();
    assert_eq!(length, text.len() as u64);
    file
}
fn seal(text: &[u8]) -> Seal {
    Seal { length: text.len() as u64, hash: Hex128(xxhash_rust::xxh3::xxh3_128(text)) }
}

#[test]
fn two_streams_are_fragmented_and_published_only_after_matching_terminal() {
    let cache = crate::test_scratch::dir("selected-report-wire-both");
    let report = [b'x'; FRAGMENT + 17];
    let warning = b"original warning \xce\xbb \xff\n";
    let mut wire = Vec::new();
    protocol::send(&mut wire, &protocol::Reply::Accepted).unwrap();
    send(&mut wire, Roster::WithSilicon, frame(), false, Some(verified(&cache, warning)), verified(&cache, &report), &Work { allow: true }).unwrap();
    let mut input = wire.as_slice();
    let delivered = receive(&mut input, &cache, Roster::WithSilicon).unwrap();
    assert!(input.is_empty());
    assert_eq!(delivered.terminal, Terminal {
        schema: Schema::V1, roster: Roster::WithSilicon, frame: frame().0, clean: false,
        diagnostics: Some(seal(warning)), report: seal(&report),
    });
    let mut stderr = Vec::new();
    let mut stdout = Vec::new();
    assert!(!delivered.publish(&mut stderr, &mut stdout).unwrap());
    let mut parts = stdout.splitn(2, |b| *b == b'\n');
    let header: Terminal = serde_json::from_slice(parts.next().unwrap()).unwrap();
    assert_eq!(header.report, seal(&report));
    assert_eq!(header.diagnostics, Some(seal(warning)));
    assert_eq!(parts.next(), Some(report.as_slice()));
    assert_eq!(stderr, warning);
    assert_eq!(std::fs::read_dir(cache).unwrap().count(), 0);
}

fn fragment(channel: Channel, sequence: u32, offset: u64, bytes: &[u8]) -> Value {
    json!({"SelectedReportFragment": {"channel": channel, "sequence": sequence, "offset": offset, "bytes": bytes}})
}
fn fixture() -> (Vec<Value>, Terminal) {
    let diagnostics = b"notice\n";
    let report = b"result\n";
    (vec![json!("Accepted"), fragment(Channel::Diagnostics, 0, 0, diagnostics), fragment(Channel::Report, 0, 0, report)],
        Terminal { schema: Schema::V1, roster: Roster::Base, frame: frame().0, clean: true,
            diagnostics: Some(seal(diagnostics)), report: seal(report) })
}
fn encode(rows: &[Value]) -> Vec<u8> {
    let mut wire = Vec::new();
    for row in rows { protocol::send(&mut wire, row).unwrap(); }
    wire
}
fn reject(cache: &Path, rows: &[Value], tail: &[u8]) {
    let mut wire = encode(rows);
    wire.extend_from_slice(tail);
    let mut diagnostics = Vec::new();
    let mut report = Vec::new();
    let result: Result<bool, Box<dyn Error>> = receive(&mut wire.as_slice(), cache, Roster::Base)
        .and_then(|delivered| Ok(delivered.publish(&mut diagnostics, &mut report)?));
    assert!(result.is_err() && diagnostics.is_empty() && report.is_empty());
    assert_eq!(std::fs::read_dir(cache).unwrap().count(), 0);
}

#[test]
fn malformed_metadata_and_stream_order_never_publish_to_either_writer() {
    let cache = crate::test_scratch::dir("selected-report-wire-malformed");
    let (prefix, terminal) = fixture();
    reject(&cache, &prefix, &[]); // EOF before terminal
    reject(&cache, &prefix[1..], &[]); // no acceptance
    for bad in [
        json!("Accepted"),
        fragment(Channel::Diagnostics, 1, 7, b"late"),
        fragment(Channel::Report, 2, 7, b"out of order"),
        fragment(Channel::Report, 1, 9, b"wrong offset"),
        fragment(Channel::Report, 1, 7, b""),
        fragment(Channel::Report, 1, 7, &[0; FRAGMENT + 1]),
        json!({"Diagnostic":{"stdout":true,"bytes":[8]}}),
        json!({"Rejected":{"kind":"Source","message":"contradicts already emitted data"}}),
    ] {
        let mut rows = prefix.clone();
        rows.push(bad);
        rows.push(json!({"SelectedReportFinished": terminal}));
        reject(&cache, &rows, &[]);
    }
    let mut valid = prefix.clone();
    valid.push(json!({"SelectedReportFinished": terminal}));
    reject(&cache, &valid, &[1]); // any bytes after terminal
    let mut missing = json!({"SelectedReportFinished": terminal});
    missing["SelectedReportFinished"].as_object_mut().unwrap().remove("diagnostics");
    let mut rows = prefix.clone();
    rows.push(missing);
    reject(&cache, &rows, &[]);
    for bad in [
        Terminal { roster: Roster::WithSilicon, ..terminal },
        Terminal { report: Seal { hash: Hex128(0), ..terminal.report }, ..terminal },
        Terminal { report: Seal { length: 0, ..terminal.report }, ..terminal },
        Terminal { diagnostics: None, ..terminal },
        Terminal { diagnostics: Some(Seal { length: 8, ..terminal.diagnostics.unwrap() }), ..terminal },
    ] {
        let mut rows = prefix.clone();
        rows.push(json!({"SelectedReportFinished": bad}));
        reject(&cache, &rows, &[]);
    }
    reject(&cache, &[], &((protocol::MAX_FRAME as u32) + 1).to_le_bytes());
}

#[test]
fn sender_preserves_denial_cancellation_and_first_actual_output_io() {
    let cache = crate::test_scratch::dir("selected-report-wire-first-error");
    let report = b"report\n";
    let mut output = Vec::new();
    let Err(SendFailure::BeforePublication(error)) =
        send(&mut output, Roster::Base, frame(), true, None, verified(&cache, report), &Work { allow: false })
    else { panic!("framing quota must be refused before publication") };
    assert_eq!(error.kind(), io::ErrorKind::OutOfMemory);
    assert!(output.is_empty());

    let staged = verified(&cache, report);
    let token = control::Cancellation::default();
    let binding = control::bind(token.clone());
    token.cancel();
    let Err(SendFailure::BeforePublication(error)) =
        send(&mut output, Roster::Base, frame(), true, None, staged, &Work { allow: true })
    else { panic!("cancellation must be refused before publication") };
    assert_eq!(crate::request_failure::exit_code(&error), 75);
    assert!(output.is_empty());
    drop(binding);

    struct Broken;
    impl Write for Broken {
        fn write(&mut self, _: &[u8]) -> io::Result<usize> { Err(io::Error::from_raw_os_error(1450)) }
        fn flush(&mut self) -> io::Result<()> { panic!("must not replace the first actual write error") }
    }
    let Err(SendFailure::AfterPublication(error)) =
        send(&mut Broken, Roster::Base, frame(), true, None, verified(&cache, report), &Work { allow: true })
    else { panic!("a writer may have accepted bytes before reporting an error") };
    assert_eq!(error.raw_os_error(), Some(1450));
    assert_eq!(std::fs::read_dir(cache).unwrap().count(), 0);
}

#[test]
fn existing_typed_rejection_still_preserves_cancellation_status() {
    let cache = crate::test_scratch::dir("selected-report-wire-rejected");
    let mut wire = Vec::new();
    protocol::send(&mut wire, &protocol::Reply::Accepted).unwrap();
    protocol::send_rejected_text(&mut wire, crate::request_failure::FailureKind::Cancelled, "superseded").unwrap();
    let Err(error) = receive(&mut wire.as_slice(), &cache, Roster::Base) else { panic!("rejection cannot issue a report") };
    assert_eq!(crate::request_failure::exit_code(error.as_ref()), 75);
    assert_eq!(error.to_string(), "superseded");
}

#[cfg(windows)]
#[test]
fn closed_named_pipe_is_eof_only_after_a_valid_terminal() {
    struct WindowsClose<'a>(&'a [u8]);
    impl Read for WindowsClose<'_> {
        fn read(&mut self, output: &mut [u8]) -> io::Result<usize> {
            if self.0.is_empty() { return Err(io::Error::from_raw_os_error(109)); }
            self.0.read(output)
        }
    }
    let cache = crate::test_scratch::dir("selected-report-wire-windows-eof");
    let (mut rows, terminal) = fixture();
    assert!(receive(&mut WindowsClose(&encode(&rows)), &cache, Roster::Base).is_err());
    rows.push(json!({"SelectedReportFinished": terminal}));
    assert!(receive(&mut WindowsClose(&encode(&rows)), &cache, Roster::Base).is_ok());
}

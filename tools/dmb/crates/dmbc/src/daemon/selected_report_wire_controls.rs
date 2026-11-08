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

#[test]
fn selected_v2_names_exact_canonical_policies_and_rejects_v1_or_foreign_set() {
    let cache = crate::test_scratch::dir("selected-report-wire-v2");
    let report = b"exact report\n";
    let warning = b"exact warning\n";
    let mut wire = Vec::new();
    protocol::send(&mut wire, &protocol::Reply::Accepted).unwrap();
    send_v2(&mut wire, Roster::WithEngineInternal, frame(), false,
        Some(verified(&cache, warning)), verified(&cache, report), &Work { allow: true }, JudgmentV2::Raw).unwrap();
    assert!(receive(&mut wire.as_slice(), &cache, Roster::WithEngineInternal).is_err());
    assert!(receive_v2(&mut wire.as_slice(), &cache, Roster::Base, JudgmentV2::Raw).is_err());
    assert!(receive_v2(&mut wire.as_slice(), &cache, Roster::WithEngineInternal, JudgmentV2::CiCeilings).is_err());
    let delivered = receive_v2(&mut wire.as_slice(), &cache, Roster::WithEngineInternal, JudgmentV2::Raw).unwrap();
    let mut diagnostics = Vec::new();
    let mut output = Vec::new();
    assert!(!delivered.publish(&mut diagnostics, &mut output).unwrap());
    let mut parts = output.splitn(2, |byte| *byte == b'\n');
    let header: Value = serde_json::from_slice(parts.next().unwrap()).unwrap();
    assert_eq!(header["policies"], json!(Roster::WithEngineInternal.names()));
    assert_eq!(parts.next().unwrap(), report);
    assert_eq!(diagnostics, warning);
    let (mut rows, terminal) = fixture();
    rows.push(json!({"SelectedReportFinished": terminal}));
    assert!(receive_v2(&mut encode(&rows).as_slice(), &cache, Roster::Base, JudgmentV2::Raw).is_err());
    for policies in [
        json!(["allow_annotations", "scheduler", "notice_publisher", "report_in_catch"]),
        json!(["allow_annotations", "cooldown", "engine_internal", "notice_publisher", "report_in_catch", "scheduler", "silicon_entry"]),
        json!(["allow_annotations", "allow_annotations", "notice_publisher", "report_in_catch", "scheduler"]),
    ] {
        assert!(serde_json::from_value::<SelectedPoliciesV2>(policies).is_err());
    }
    let mixed = Roster::WithCooldownAndEngineInternal;
    assert!(serde_json::to_value(mixed).is_err(), "v2-only plan cannot encode a v1 alias");
    assert!(serde_json::from_value::<Roster>(json!("with_cooldown_and_engine_internal")).is_err());
    let names = json!(mixed.names());
    assert_eq!(serde_json::from_value::<SelectedPoliciesV2>(names).unwrap().names(), mixed.names());
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

#[test]
fn combined_streams_share_one_source_frame_and_keep_v1_isolated() {
    let cache = crate::test_scratch::dir("combined-selected-report-wire");
    let diagnostics = b"one actual warning\n";
    let checker = [b'c'; FRAGMENT + 5];
    let report = [b'r'; FRAGMENT + 11];
    let checker_frame = WireFrame { policy_revision: Hex128(4), ..frame().0 };
    let mut wire = Vec::new();
    protocol::send(&mut wire, &protocol::Reply::Accepted).unwrap();
    send_combined(
        &mut wire, Roster::WithSemanticReads, frame(), false, Some(verified(&cache, diagnostics)),
        (checker_frame, verified(&cache, &checker)), verified(&cache, &report), &Work { allow: true },
    ).unwrap();

    assert!(receive(&mut wire.as_slice(), &cache, Roster::WithSemanticReads).is_err());
    assert!(receive_combined(&mut wire.as_slice(), &cache, Roster::WithReactivePolicies).is_err());
    let complete = receive_combined(&mut wire.as_slice(), &cache, Roster::WithSemanticReads).unwrap();
    assert_eq!(complete.terminal.frame, frame().0);
    assert_eq!(complete.terminal.checker_policy_revision, checker_frame.policy_revision);
    assert_eq!(complete.terminal.checker, seal(&checker));
    let mut stderr = Vec::new();
    let mut stdout = Vec::new();
    assert!(!complete.publish(&mut stderr, &mut stdout).unwrap());
    let newline = stdout.iter().position(|byte| *byte == b'\n').unwrap();
    let header: CombinedTerminal = serde_json::from_slice(&stdout[..newline]).unwrap();
    assert_eq!(header.report, seal(&report));
    let (actual_checker, actual_report) = stdout[newline + 1..].split_at(checker.len());
    assert_eq!(actual_checker, checker.as_slice());
    assert_eq!(actual_report, report.as_slice());
    assert_eq!(stderr, diagnostics);

    let foreign = WireFrame { source_revision: Hex128(5), ..checker_frame };
    let mut empty = Vec::new();
    let error = send_combined(
        &mut empty, Roster::WithSemanticReads, frame(), true, None, (foreign, verified(&cache, &checker)),
        verified(&cache, &report), &Work { allow: true },
    ).unwrap_err();
    assert!(matches!(error, SendFailure::BeforePublication(_)));
    assert!(empty.is_empty());
    assert_eq!(std::fs::read_dir(cache).unwrap().count(), 0);
}

#[test]
fn combined_rejects_partial_wrong_order_or_foreign_terminal_before_writers() {
    let cache = crate::test_scratch::dir("combined-selected-report-wire-rejected");
    let checker = b"checker\n";
    let analyze = b"analyze\n";
    let terminal = CombinedTerminal {
        schema: CombinedSchema::V1, roster: Roster::WithSemanticReads, frame: frame().0,
        checker_policy_revision: Hex128(4), clean: true, diagnostics: None,
        checker: seal(checker), report: seal(analyze),
    };
    let accept = json!("Accepted");
    let check = fragment(Channel::Checker, 0, 0, checker);
    let report = fragment(Channel::Report, 0, 0, analyze);
    let finish = json!({"SelectedCombinedReportFinished": terminal});
    let bad_digest = json!({"SelectedCombinedReportFinished": CombinedTerminal {
        checker: Seal { hash: Hex128(0), ..terminal.checker }, ..terminal
    }});
    let foreign_roster = json!({"SelectedCombinedReportFinished": CombinedTerminal {
        roster: Roster::WithReactivePolicies, ..terminal
    }});
    let oversized = json!({"SelectedCombinedReportFinished": CombinedTerminal {
        report: Seal { length: MAX_STREAM, ..terminal.report }, ..terminal
    }});
    for rows in [
        vec![accept.clone(), check.clone()],
        vec![accept.clone(), report.clone(), check.clone(), finish.clone()],
        vec![accept.clone(), check.clone(), report.clone(), bad_digest],
        vec![accept.clone(), check.clone(), report.clone(), oversized],
        vec![accept.clone(), check.clone(), report.clone(), foreign_roster],
        vec![accept.clone(), check.clone(), report.clone(), finish, json!("Accepted")],
        vec![accept, report, json!({"SelectedReportFinished": fixture().1})],
    ] {
        let wire = encode(&rows);
        let mut stderr = Vec::new();
        let mut stdout = Vec::new();
        let result = receive_combined(&mut wire.as_slice(), &cache, Roster::WithSemanticReads)
            .and_then(|complete| Ok(complete.publish(&mut stderr, &mut stdout)?));
        assert!(result.is_err() && stderr.is_empty() && stdout.is_empty());
        assert_eq!(std::fs::read_dir(&cache).unwrap().count(), 0);
    }
}

#[test]
fn named_image_dir_reuses_sealed_report_and_refuses_other_protocol_roles(){
    use dq_analyze::selected_exclusions_wire::NamedImageDirSchema;
    let cache=crate::test_scratch::dir("named-image-dir-wire");
    let report=b"image_dir_after_build: example report\n";
    let terminal=NamedImageDirTerminal{schema:NamedImageDirSchema::V1,frame:frame().0,clean:false,report:seal(report)};
    let publication=std::cell::Cell::new(false);
    let mut wire=Vec::new();
    protocol::send(&mut wire,&protocol::Reply::Accepted).unwrap();
    send_named_image_dir(&mut wire,terminal,verified(&cache,report),&Work{allow:true},&publication).unwrap();
    assert!(publication.get());
    assert!(receive(&mut wire.as_slice(),&cache,Roster::Base).is_err());
    assert!(receive_combined(&mut wire.as_slice(),&cache,Roster::WithSemanticReads).is_err());
    let named=receive_named_image_dir(&mut wire.as_slice(),&cache).unwrap();
    let mut published=Vec::new();
    assert!(!named.publish(&mut published).unwrap());
    let mut parts=published.splitn(2,|byte|*byte==b'\n');
    assert_eq!(serde_json::from_slice::<NamedImageDirTerminal>(parts.next().unwrap()).unwrap(),terminal);
    assert_eq!(parts.next().unwrap(),report);

    let report_fragment=fragment(Channel::Report,0,0,report);
    let invalid=[
        vec![json!("Accepted"),report_fragment.clone(),json!({"SelectedReportFinished":fixture().1})],
        vec![json!("Accepted"),fragment(Channel::Diagnostics,0,0,b"unadmitted notice"),json!({"NamedImageDirReportFinished":terminal})],
        vec![json!("Accepted"),report_fragment.clone(),json!({"NamedImageDirReportFinished":NamedImageDirTerminal{report:Seal{hash:Hex128(0),..terminal.report},..terminal}})],
        vec![json!("Accepted"),report_fragment,json!({"NamedImageDirReportFinished":terminal}),json!("Accepted")],
    ];
    for rows in invalid{assert!(receive_named_image_dir(&mut encode(&rows).as_slice(),&cache).is_err());}
    let publication=std::cell::Cell::new(false);
    let mut wire=Vec::new();
    let foreign=NamedImageDirTerminal{report:seal(b"other report"),..terminal};
    assert!(matches!(send_named_image_dir(&mut wire,foreign,verified(&cache,report),&Work{allow:true},&publication),Err(SendFailure::BeforePublication(_))));
    assert!(wire.is_empty()&&!publication.get());

    protocol::send(&mut wire,&protocol::Reply::Accepted).unwrap();
    send_named_image_dir_rejection(&mut wire,&io::Error::from_raw_os_error(1450)).unwrap();
    let rejected=receive_named_image_dir(&mut wire.as_slice(),&cache).err().unwrap();
    assert_eq!(rejected.downcast_ref::<io::Error>().unwrap().raw_os_error(),Some(1450));
    assert_eq!(std::fs::read_dir(&cache).unwrap().count(),0);
}

#[test]
fn compound_terminal_gates_both_reports_on_the_actual_native_pair() {
    exercise_compound_terminal(CompoundRoster::Selected(Roster::WithSemanticReads));
}

#[test]
fn full_registry_compound_terminal_is_distinct_and_checks_native_installation() {
    exercise_compound_terminal(CompoundRoster::FullRegistry);
}

fn exercise_compound_terminal(roster: CompoundRoster) {
    let other = match roster {
        CompoundRoster::Selected(_) => CompoundRoster::FullRegistry,
        CompoundRoster::FullRegistry => CompoundRoster::Selected(Roster::WithSemanticReads),
    };
    let cache = crate::test_scratch::dir("compound-selected-wire");
    let store = crate::publish::PairStore::open(cache.join("native-store")).unwrap();
    let pair = store.publish_exact(1, b"fixture dmb", b"fixture rsc", true).unwrap();
    let checker_frame = WireFrame { policy_revision: Hex128(4), ..frame().0 };
    let mut wire = Vec::new();
    protocol::send(&mut wire, &protocol::Reply::Accepted).unwrap();
    let work = Work { allow: true };
    CompiledSelectedReports {
        compiled: BuildOutcome::Published {
            publication_proof: None, pair: pair.clone(), store: store.root_path().to_owned(),
            output_project: cache.join("deepquarry.dme"), session_hit: false, seconds: 0.0,
        },
        roster, frame: frame(), clean: false,
        diagnostics: Some(verified(&cache, b"preparation\n")),
        checker: (checker_frame, verified(&cache, b"checker\n")),
        report: verified(&cache, b"analyze\n"),
        _credit: work.reserve(SEND_SCRATCH).unwrap(),
    }.send(&mut wire, roster, &work).unwrap();

    let verify = |actual: &crate::publish::OutputPair| {
        if store.verify(actual.id, true)? != *actual || *actual != pair {
            return Err(invalid("native receipt differs"));
        }
        Ok(())
    };
    assert!(receive_combined(&mut wire.as_slice(), &cache, Roster::WithSemanticReads).is_err());
    assert!(receive_compilation(&mut wire.as_slice(), &cache, other, verify).is_err());
    let mut bad_tail = wire.clone();
    bad_tail.push(0);
    assert!(receive_compilation(&mut bad_tail.as_slice(), &cache, roster, verify).is_err());
    assert!(receive_compilation(&mut wire.as_slice(), &cache, roster,
        |_| Err(invalid("destination receipt changed"))).is_err());
    let delivered = receive_compilation(&mut wire.as_slice(), &cache, roster, verify).unwrap();
    let mut stderr = Vec::new();
    let mut stdout = Vec::new();
    assert!(!delivered.publish(&mut stderr, &mut stdout).unwrap());
    let newline = stdout.iter().position(|&byte| byte == b'\n').unwrap();
    let terminal: CompoundTerminal = serde_json::from_slice(&stdout[..newline]).unwrap();
    assert_eq!(terminal.native_pair, pair);
    let (source, policy) = match terminal.selected {
        CompoundReports::Selected(report) => {
            assert_eq!(terminal.schema, CompoundSchema::V1);
            (report.frame, report.checker_policy_revision)
        }
        CompoundReports::FullRegistry(report) => {
            assert_eq!(terminal.schema, CompoundSchema::FullRegistryV1);
            (report.frame, report.checker_policy_revision)
        }
    };
    assert_eq!(source, frame().0);
    assert_eq!(policy, checker_frame.policy_revision);
    assert_eq!(&stdout[newline+1..], b"checker\nanalyze\n");
    assert_eq!(stderr, b"preparation\n");
}

#[test]
fn source_only_selected_wire_refuses_semantic_terminals_and_foreign_channels() {
    let cache = crate::test_scratch::dir("selected-raw-file-wire");
    let text = b"exact source-only report\n";
    let prepared = BuildOutcome::RawQueryPrepared {
        query_revision: format!("{:032x}", 1), source_revision: format!("{:032x}", 2),
        policy_revision: format!("{:032x}", 3), retained: true,
    };
    assert!(Frame::from_prepared(&prepared).is_err());
    let mut wire = Vec::new();
    protocol::send(&mut wire, &protocol::Reply::Accepted).unwrap();
    send_raw_selected(&mut wire, Roster::AllRawFilePolicies, RawFrame::from_prepared(&prepared).unwrap(), false,
        verified(&cache, text), &Work { allow: true }).unwrap();
    assert!(receive(&mut wire.as_slice(), &cache, Roster::AllRawFilePolicies).is_err());
    let delivered = receive_raw_selected(&mut wire.as_slice(), &cache, Roster::AllRawFilePolicies).unwrap();
    assert_eq!(delivered.terminal.frame.query_revision, Hex128(1));
    assert_eq!(delivered.terminal.report, seal(text));
    assert!(!delivered.terminal.clean);
    let mut docs = Vec::new();
    protocol::send(&mut docs, &protocol::Reply::Accepted).unwrap();
    send_raw_selected(&mut docs, Roster::WithDocSnippets, RawFrame::from_prepared(&prepared).unwrap(),
        false, verified(&cache, text), &Work { allow: true }).unwrap();
    assert!(receive_raw_selected(&mut docs.as_slice(), &cache, Roster::AllRawFilePolicies).is_err());
    let docs = receive_raw_selected(&mut docs.as_slice(), &cache, Roster::WithDocSnippets).unwrap();
    assert_eq!(docs.terminal.report, seal(text));

    let mut semantic = Vec::new();
    protocol::send(&mut semantic, &protocol::Reply::Accepted).unwrap();
    send(&mut semantic, Roster::Base, frame(), false, None,
        verified(&cache, text), &Work { allow: true }).unwrap();
    assert!(receive_raw_selected(&mut semantic.as_slice(), &cache, Roster::AllRawFilePolicies).is_err());

    let mut foreign = Vec::new();
    protocol::send(&mut foreign, &protocol::Reply::Accepted).unwrap();
    protocol::send(&mut foreign, &SendReply::SelectedReportFragment {
        channel: Channel::Diagnostics, sequence: 0, offset: 0, bytes: b"foreign diagnostics",
    }).unwrap();
    assert!(receive_raw_selected(&mut foreign.as_slice(), &cache, Roster::AllRawFilePolicies).is_err());
}

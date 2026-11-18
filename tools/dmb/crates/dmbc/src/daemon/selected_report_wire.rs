//! Transport for a completed, exact exclusions-only report.
//! Frames carry result data. Only the retained BuildHost can issue a report.
use crate::{
    request::BuildOutcome,
    request_failure::RequestFailure,
    selected_report_spool::{Stage, Verified},
};
use dm_preprocess::source_arena_credit::SourceArenaWork;
use serde::{Deserialize, Serialize};
use std::{
    error::Error,
    io::{self, Cursor, Read, Write},
    path::Path,
};

use super::{control, protocol, selected_exclusions::Mode};
use dq_analyze::selected_exclusions_wire::{
    CombinedSchema, CombinedTerminal, Frame as WireFrame, Hex128, NamedImageDirTerminal, JudgmentV2, RawSelectedFrame, RawSelectedSchema, RawSelectedTerminal, Seal, Schema, SchemaV2, SelectedPoliciesV2, Terminal, TerminalV2, MAX_HEADER, MAX_STREAM,
};
pub(crate) use dq_analyze::selected_exclusions_wire::Roster;

#[path="schema_report_wire.rs"]mod schema_report;
#[path="native_fix_report_wire.rs"]mod fix_report;
#[path="baseline_update_report_wire.rs"]mod baseline_update_report;
pub(crate) use baseline_update_report::{send_baseline_update,receive_baseline_update};
pub(crate) use fix_report::{send_fix,receive_fix};
pub(crate) use schema_report::{send_schema,receive_schema};
const FRAGMENT: usize = 8192;
// At most one frame and fixed-sized decoded fragment live. Numeric-byte JSON
// can expand a single u8 to four bytes before the enclosing record is counted.
const SEND_SCRATCH: usize = FRAGMENT * 18 + 4096;
/// An actual transport grant from the same host, obtained before any
/// optional cold report retention can consume its headroom.
pub(crate) struct CompoundSendScratch(dm_preprocess::source_arena_credit::SourceArenaCredit);

impl CompoundSendScratch {
    pub(crate) fn reserve(work: &dyn SourceArenaWork) -> io::Result<Self> {
        work.reserve(SEND_SCRATCH).map(Self)
    }
}


fn invalid(message: &'static str) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, message)
}

// Actual service-issued coordinates. The shared wire data alone cannot be
// supplied to the sender in place of a retained BuildOutcome.
#[derive(Clone, Copy)]
pub(crate) struct Frame(WireFrame);
impl Frame {
    pub(crate) fn observation_data(self)->WireFrame {self.0}
    pub(crate) fn from_prepared(prepared: &BuildOutcome) -> io::Result<Self> {
        let BuildOutcome::QueryPrepared { semantic_revision, source_revision, policy_revision: Some(policy_revision), retained: true } = prepared else {
            return Err(invalid("selected report requires actual retained Original preparation"));
        };
        let pin = |value: &str| Hex128::parse(value).ok_or_else(|| invalid("selected preparation has an invalid revision"));
        Ok(Self(WireFrame {
            semantic_revision: pin(semantic_revision)?,
            source_revision: pin(source_revision)?,
            policy_revision: pin(policy_revision)?,
        }))
    }

    pub(crate) fn require_checker_frame(&self, checker: WireFrame) -> io::Result<()> {
        if self.0.semantic_revision != checker.semantic_revision || self.0.source_revision != checker.source_revision {
            return Err(invalid("combined checker and Analyze do not share the same source preparation"));
        }
        Ok(())
    }
}

/// Retains the actual ordinary publication outcome and Original report spools
/// together. The host invokes the consumer under the same compound deadline.
pub(crate) struct CompiledSelectedReports {
    pub(crate) compiled: BuildOutcome,
    pub(crate) roster: CompoundRoster,
    pub(crate) frame: Frame,
    pub(crate) clean: bool,
    pub(crate) diagnostics: Option<Verified>,
    pub(crate) checker: (WireFrame, Verified),
    pub(crate) report: Verified,
    pub(crate) _credit: dm_preprocess::source_arena_credit::SourceArenaControlCredit,
    pub(crate) send_scratch: Option<CompoundSendScratch>,
}

impl CompiledSelectedReports {
    pub(crate) fn publish(
        self, diagnostics: &mut impl Write, checker: &mut impl Write, analyze: &mut impl Write,
    ) -> io::Result<(BuildOutcome, bool)> {
        if let Some(notices) = self.diagnostics { notices.publish(diagnostics)?; }
        self.checker.1.publish(checker)?;
        self.report.publish(analyze)?;
        Ok((self.compiled, self.clean))
    }

    pub(crate) fn send(
        self, stream: &mut impl Write, expected: CompoundRoster, work: &dyn SourceArenaWork,
    ) -> Result<(), SendFailure> {
        let Self { compiled, roster, frame, clean, diagnostics, checker, report, _credit, send_scratch } = self;
        if roster != expected {
            return Err(SendFailure::BeforePublication(invalid("compound selected roster differs")));
        }
        let BuildOutcome::Published { pair, session_hit: false, .. } = compiled else {
            return Err(SendFailure::BeforePublication(invalid("compound result requires actual exact native publication")));
        };
        let (checker_frame, checker_report) = &checker;
        frame.require_checker_frame(*checker_frame).map_err(SendFailure::BeforePublication)?;
        let diagnostics_seal = diagnostics.as_ref().map(seal_of);
        let checker_seal = seal_of(checker_report);
        let report_seal = seal_of(&report);
        let (schema, selected) = match roster {
            CompoundRoster::Selected(roster) => (CompoundSchema::V1, CompoundReports::Selected(CombinedTerminal {
                schema: CombinedSchema::V1, roster, frame: frame.0,
                checker_policy_revision: checker_frame.policy_revision, clean,
                diagnostics: diagnostics_seal, checker: checker_seal, report: report_seal,
            })),
            CompoundRoster::FullRegistry | CompoundRoster::FullRegistryCi | CompoundRoster::FullRegistryCiCbt => {
                let (schema, report_schema) = match roster {
                    CompoundRoster::FullRegistry => (CompoundSchema::FullRegistryV1, FullRegistrySchema::V1),
                    CompoundRoster::FullRegistryCi => (CompoundSchema::FullRegistryCiV1, FullRegistrySchema::CiV1),
                    CompoundRoster::FullRegistryCiCbt => (CompoundSchema::FullRegistryCiCbtV1, FullRegistrySchema::CiCbtV1),
                    CompoundRoster::Selected(_) => unreachable!("full registry terminal selection"),
                };
                (schema, CompoundReports::FullRegistry(FullRegistryReports {
                    schema: report_schema, frame: frame.0,
                    checker_policy_revision: checker_frame.policy_revision, clean,
                    diagnostics: diagnostics_seal, checker: checker_seal, report: report_seal,
                }))
            }
        };
        let terminal = CompoundTerminal { schema, native_pair: pair, selected };
        terminal.require(roster).map_err(SendFailure::BeforePublication)?;
        encode_header(&terminal).map_err(SendFailure::BeforePublication)?;
        send_channels(stream, diagnostics, Some(checker), report, work, send_scratch, SendReply::SelectedCompilationFinished(terminal))
    }
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
enum CompoundSchema {
    #[serde(rename = "native-compiled-selected-v1")]
    V1,
    #[serde(rename = "native-compiled-full-registry-v1")]
    FullRegistryV1,
    #[serde(rename = "native-compiled-full-registry-ci-v1")]
    FullRegistryCiV1,
    #[serde(rename = "native-compiled-full-registry-ci-cbt-v1")]
    FullRegistryCiCbtV1,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Ord, PartialOrd)]
pub(crate) enum CompoundRoster { Selected(Roster), FullRegistry, FullRegistryCi, FullRegistryCiCbt }

impl CompoundRoster {
    pub(crate) fn strict_profile(self) -> crate::request::CompoundStrictProfile {
        match self {
            Self::FullRegistryCiCbt => crate::request::CompoundStrictProfile::Cbt,
            _ => crate::request::CompoundStrictProfile::Default,
        }
    }

    pub(crate) fn is_full(self) -> bool { !matches!(self, Self::Selected(_)) }
    pub(crate) fn is_ci(self) -> bool { matches!(self, Self::FullRegistryCi | Self::FullRegistryCiCbt) }
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(untagged)]
enum CompoundReports { Selected(CombinedTerminal), FullRegistry(FullRegistryReports) }

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
enum FullRegistrySchema {
    #[serde(rename = "native-checker-analyze-full-registry-v1")]
    V1,
    #[serde(rename = "native-checker-analyze-full-registry-ci-v1")]
    CiV1,
    #[serde(rename = "native-checker-analyze-full-registry-ci-cbt-v1")]
    CiCbtV1,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct FullRegistryReports {
    schema: FullRegistrySchema,
    frame: WireFrame,
    checker_policy_revision: Hex128,
    clean: bool,
    #[serde(deserialize_with = "require_diagnostics_option")]
    diagnostics: Option<Seal>,
    checker: Seal,
    report: Seal,
}

fn require_diagnostics_option<'de, D: serde::Deserializer<'de>>(deserializer: D) -> Result<Option<Seal>, D::Error> {
    Option::deserialize(deserializer)
}

/// Native output and Original reports have different authority. The actual
/// native pair receipt carries no Original semantic or policy revision.
#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct CompoundTerminal {
    schema: CompoundSchema,
    native_pair: crate::publish::OutputPair,
    selected: CompoundReports,
}
impl CompoundTerminal {
    fn require(&self, expected: CompoundRoster) -> io::Result<()> {
        match (&self.selected, self.schema, expected) {
            (CompoundReports::Selected(terminal), CompoundSchema::V1, CompoundRoster::Selected(roster))
                if terminal.roster == roster => terminal.require()?,
            (CompoundReports::FullRegistry(terminal), CompoundSchema::FullRegistryV1, CompoundRoster::FullRegistry)
                if terminal.schema == FullRegistrySchema::V1 => validate_full_registry_streams(terminal)?,
            (CompoundReports::FullRegistry(terminal), CompoundSchema::FullRegistryCiV1, CompoundRoster::FullRegistryCi)
                if terminal.schema == FullRegistrySchema::CiV1 => validate_full_registry_streams(terminal)?,
            (CompoundReports::FullRegistry(terminal), CompoundSchema::FullRegistryCiCbtV1, CompoundRoster::FullRegistryCiCbt)
                if terminal.schema == FullRegistrySchema::CiCbtV1 => validate_full_registry_streams(terminal)?,
            _ => return Err(invalid("compound terminal names a foreign report selection")),
        }
        if self.native_pair.version != 1 || self.native_pair.dmb_bytes == 0 {
            return Err(invalid("compound terminal names a foreign roster or native pair"));
        }
        Ok(())
    }
}

fn validate_full_registry_streams(terminal: &FullRegistryReports) -> io::Result<()> {
    if [Some(terminal.checker),Some(terminal.report),terminal.diagnostics].into_iter().flatten()
        .any(|seal| !(1..=MAX_STREAM).contains(&seal.length)) {
        return Err(invalid("full registry terminal declares an empty or oversized stream"));
    }
    let total=terminal.checker.length.checked_add(terminal.report.length)
        .and_then(|n|n.checked_add(terminal.diagnostics.map_or(0,|seal|seal.length)));
    if total.is_none_or(|n|n>MAX_STREAM){return Err(invalid("full registry reports exceed the aggregate stream bound"))}
    Ok(())
}

/// Only an actual retained raw-query outcome can issue a source-only frame.
pub(crate) struct RawFrame(RawSelectedFrame);
impl RawFrame {
    pub(crate) fn from_prepared(prepared: &BuildOutcome) -> io::Result<Self> {
        let BuildOutcome::RawQueryPrepared { query_revision, source_revision, policy_revision, retained: true } = prepared else {
            return Err(invalid("raw selected report requires actual retained raw preparation"));
        };
        let pin = |value: &str| Hex128::parse(value).ok_or_else(|| invalid("raw selected preparation has an invalid revision"));
        Ok(Self(RawSelectedFrame {
            query_revision: pin(query_revision)?,
            source_revision: pin(source_revision)?,
            policy_revision: pin(policy_revision)?,
        }))
    }
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
enum Channel {
    Diagnostics,
    Checker,
    Report,
    Usage,
}

fn seal_of(file: &Verified) -> Seal {
    Seal { length: file.length(), hash: Hex128(file.hash()) }
}

#[derive(Serialize)]
enum SendReply<'a> {
    NativeCodemodFixtureFinished(dq_analyze::native_codemod_fixture_wire::Terminal),
    NativeSemUtilityFinished(dq_analyze::native_sem_utility_wire::Terminal),
    SelectedReportFragment { channel: Channel, sequence: u32, offset: u64, bytes: &'a [u8] },
    SelectedReportFinished(Terminal),
    RawSelectedReportFinished(RawSelectedTerminal),
    SelectedReportV2Finished(TerminalV2),
    SelectedCombinedReportFinished(CombinedTerminal),
    SelectedCompilationFinished(CompoundTerminal),
    NamedImageDirReportFinished(NamedImageDirTerminal),
    NamedImageDirRejected(NamedRejection),
    FullRegistryCheckFinished(dq_analyze::full_registry_check_wire::Terminal),
    NativeSelftestsFinished(dq_analyze::native_selftest_wire::Terminal),
    FullRegistryCheckCliFinished(dq_analyze::native_check_cli_wire::Terminal),
    SchemaProposalsFinished(dq_analyze::schema_proposals_wire::Terminal),
    NativeFixFinished(dq_analyze::native_fix_wire::Terminal),
    BaselineUpdateFinished(dq_analyze::native_baseline_update_wire::Terminal),
    CheckerTextFinished(dq_analyze::native_checker_wire::Terminal),
}

struct FragmentWriter<'a, W> {
    stream: &'a mut W,
    channel: Channel,
    sequence: u32,
    offset: u64,
}
impl<W: Write> Write for FragmentWriter<'_, W> {
    fn write(&mut self, input: &[u8]) -> io::Result<usize> {
        for bytes in input.chunks(FRAGMENT) {
            let next_sequence = self.sequence.checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?;
            let next_offset = self.offset.checked_add(bytes.len() as u64).ok_or(io::ErrorKind::OutOfMemory)?;
            protocol::send(&mut *self.stream, &SendReply::SelectedReportFragment {
                channel: self.channel,
                sequence: self.sequence,
                offset: self.offset,
                bytes,
            })?;
            self.sequence = next_sequence;
            self.offset = next_offset;
        }
        Ok(input.len())
    }

    fn flush(&mut self) -> io::Result<()> {
        self.stream.flush()
    }
}

/// Only a prepublication failure can be sent as an ordinary typed rejection.
/// An actual delivery error may follow a partially written fragment.
#[derive(Debug)]
pub(crate) enum SendFailure {
    BeforePublication(io::Error),
    AfterPublication(io::Error),
}

/// Send after Accepted, under the service's existing request and deadline.
/// The caller retains the selected-result funding while these files are live.
pub(crate) fn send(
    stream: &mut impl Write, roster: Roster, frame: Frame, clean: bool,
    diagnostics: Option<Verified>, report: Verified, work: &dyn SourceArenaWork,
) -> Result<(), SendFailure> {
    send_with_checker(stream, roster, frame, clean, diagnostics, None, report, work, None)
}

pub(crate) fn send_raw_selected(
    stream: &mut impl Write, roster: Roster, frame: RawFrame, clean: bool,
    report: Verified, work: &dyn SourceArenaWork,
) -> Result<(), SendFailure> {
    let terminal = RawSelectedTerminal {
        schema: RawSelectedSchema::V1, roster,
        frame: frame.0, clean, report: seal_of(&report),
    };
    terminal.require(roster).map_err(SendFailure::BeforePublication)?;
    encode_header(&terminal).map_err(SendFailure::BeforePublication)?;
    let _frame = work.reserve(SEND_SCRATCH).map_err(SendFailure::BeforePublication)?;
    control::begin_publication().map_err(SendFailure::BeforePublication)?;
    report.publish(&mut FragmentWriter { stream, channel: Channel::Report, sequence: 0, offset: 0 })
        .map_err(SendFailure::AfterPublication)?;
    protocol::send(stream, &SendReply::RawSelectedReportFinished(terminal))
        .map_err(SendFailure::AfterPublication)
}

pub(crate) fn send_combined(
    stream: &mut impl Write, roster: Roster, frame: Frame, clean: bool, diagnostics: Option<Verified>,
    checker: (WireFrame, Verified), report: Verified, work: &dyn SourceArenaWork,
) -> Result<(), SendFailure> {
    send_with_checker(stream, roster, frame, clean, diagnostics, Some(checker), report, work, None)
}

pub(crate) fn send_v2(
    stream: &mut impl Write, roster: Roster, frame: Frame, clean: bool,
    diagnostics: Option<Verified>, report: Verified, work: &dyn SourceArenaWork, judgment: JudgmentV2,
) -> Result<(), SendFailure> {
    send_with_checker(stream, roster, frame, clean, diagnostics, None, report, work, Some(judgment))
}

fn send_with_checker(
    stream: &mut impl Write, roster: Roster, frame: Frame, clean: bool,
    diagnostics: Option<Verified>, checker: Option<(WireFrame, Verified)>, report: Verified,
    work: &dyn SourceArenaWork, generic_v2: Option<JudgmentV2>,
) -> Result<(), SendFailure> {
    let diagnostics_seal = diagnostics.as_ref().map(seal_of);
    let report_seal = seal_of(&report);
    let terminal = if let Some(judgment) = generic_v2 {
        if checker.is_some() {
            return Err(SendFailure::BeforePublication(invalid("selected v2 cannot carry checker output")));
        }
        let terminal = TerminalV2 {
            schema: SchemaV2::V2,
            judgment,
            policies: SelectedPoliciesV2::for_roster(roster).map_err(SendFailure::BeforePublication)?,
            frame: frame.0, clean, diagnostics: diagnostics_seal, report: report_seal,
        };
        terminal.require_using(roster, judgment).map_err(SendFailure::BeforePublication)?;
        SendReply::SelectedReportV2Finished(terminal)
    } else if let Some((checker_frame, checker)) = &checker {
        frame.require_checker_frame(*checker_frame).map_err(SendFailure::BeforePublication)?;
        let terminal = CombinedTerminal {
            schema: CombinedSchema::V1, roster, frame: frame.0, checker_policy_revision: checker_frame.policy_revision,
            clean, diagnostics: diagnostics_seal, checker: seal_of(checker), report: report_seal,
        };
        terminal.require().map_err(SendFailure::BeforePublication)?;
        SendReply::SelectedCombinedReportFinished(terminal)
    } else {
        let terminal = Terminal {
            schema: Schema::V1, roster, frame: frame.0, clean,
            diagnostics: diagnostics_seal, report: report_seal,
        };
        terminal.require(roster).map_err(SendFailure::BeforePublication)?;
        SendReply::SelectedReportFinished(terminal)
    };
    send_channels(stream, diagnostics, checker, report, work, None, terminal)
}

fn send_channels(
    stream: &mut impl Write, diagnostics: Option<Verified>, checker: Option<(WireFrame, Verified)>,
    report: Verified, work: &dyn SourceArenaWork, prepaid: Option<CompoundSendScratch>, terminal: SendReply<'_>,
) -> Result<(), SendFailure> {
    let _frame = match prepaid {
        Some(CompoundSendScratch(credit)) => {
            control::checkpoint().map_err(SendFailure::BeforePublication)?;
            credit
        }
        None => work.reserve(SEND_SCRATCH).map_err(SendFailure::BeforePublication)?,
    };
    control::begin_publication().map_err(SendFailure::BeforePublication)?;
    let sent = (|| {
        if let Some(diagnostics) = diagnostics {
            diagnostics.publish(&mut FragmentWriter { stream: &mut *stream, channel: Channel::Diagnostics, sequence: 0, offset: 0 })?;
        }
        if let Some((_, checker)) = checker {
            checker.publish(&mut FragmentWriter { stream: &mut *stream, channel: Channel::Checker, sequence: 0, offset: 0 })?;
        }
        report.publish(&mut FragmentWriter { stream: &mut *stream, channel: Channel::Report, sequence: 0, offset: 0 })?;
        protocol::send(stream, &terminal)
    })();
    sent.map_err(SendFailure::AfterPublication)
}

/// Only the inline authorized BuildHost callback may use this sender.
pub(crate) fn send_named_image_dir(
    stream:&mut impl Write, terminal:NamedImageDirTerminal, report:Verified,
    work:&dyn SourceArenaWork, publication:&std::cell::Cell<bool>,
)->Result<(),SendFailure>{
    terminal.require().map_err(SendFailure::BeforePublication)?;
    if terminal.report!=seal_of(&report){
        return Err(SendFailure::BeforePublication(invalid("named ImageDir terminal seal differs from the actual staged report")));
    }
    let _frame=work.reserve(SEND_SCRATCH).map_err(SendFailure::BeforePublication)?;
    control::begin_publication().map_err(SendFailure::BeforePublication)?;
    publication.set(true);
    report.publish(&mut FragmentWriter{stream,channel:Channel::Report,sequence:0,offset:0})
        .map_err(SendFailure::AfterPublication)?;
    protocol::send(stream,&SendReply::NamedImageDirReportFinished(terminal))
        .map_err(SendFailure::AfterPublication)
}

#[derive(Serialize,Deserialize)]
#[serde(deny_unknown_fields)]
struct NamedRejection{
    failure:RequestFailure,
    os_code:Option<i32>,
}
pub(crate) fn send_named_image_dir_rejection(stream:&mut impl Write,error:&(dyn Error+'static))->io::Result<()>{
    let os_code=error.downcast_ref::<io::Error>().and_then(io::Error::raw_os_error);
    protocol::send(stream,&SendReply::NamedImageDirRejected(NamedRejection{
        failure:super::generation::bounded_request_failure(error)?,os_code,
    }))
}

/// The decoder cannot allocate based on an untrusted JSON sequence length.
/// The outer 4 MiB frame cap still admits the existing typed rejection text.
struct Bytes {
    data: [u8; FRAGMENT],
    length: usize,
}
impl<'de> Deserialize<'de> for Bytes {
    fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        struct ByteVisitor;
        impl<'de> serde::de::Visitor<'de> for ByteVisitor {
            type Value = Bytes;
            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("one bounded nonempty selected report fragment")
            }
            fn visit_seq<A: serde::de::SeqAccess<'de>>(self, mut sequence: A) -> Result<Bytes, A::Error> {
                let mut bytes = Bytes { data: [0; FRAGMENT], length: 0 };
                while bytes.length < FRAGMENT {
                    let Some(value) = sequence.next_element::<u8>()? else { break };
                    bytes.data[bytes.length] = value;
                    bytes.length += 1;
                }
                if bytes.length == 0
                    || (bytes.length == FRAGMENT && sequence.next_element::<u8>()?.is_some()) {
                    return Err(serde::de::Error::custom("empty or oversized selected report fragment"));
                }
                Ok(bytes)
            }
        }
        deserializer.deserialize_seq(ByteVisitor)
    }
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Fragment {
    channel: Channel,
    sequence: u32,
    offset: u64,
    bytes: Bytes,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Rejection {
    kind: crate::request_failure::FailureKind,
    message: String,
}

#[derive(Deserialize)]
enum ReceiveReply {
    NativeCodemodFixtureFinished(dq_analyze::native_codemod_fixture_wire::Terminal),
    NativeSemUtilityFinished(dq_analyze::native_sem_utility_wire::Terminal),
    Accepted,
    Rejected(Rejection),
    SelectedReportFragment(Fragment),
    SelectedReportFinished(Terminal),
    RawSelectedReportFinished(RawSelectedTerminal),
    SelectedReportV2Finished(TerminalV2),
    SelectedCombinedReportFinished(CombinedTerminal),
    SelectedCompilationFinished(CompoundTerminal),
    NamedImageDirReportFinished(NamedImageDirTerminal),
    NamedImageDirRejected(NamedRejection),
    FullRegistryCheckFinished(dq_analyze::full_registry_check_wire::Terminal),
    NativeSelftestsFinished(dq_analyze::native_selftest_wire::Terminal),
    FullRegistryCheckCliFinished(dq_analyze::native_check_cli_wire::Terminal),
    SchemaProposalsFinished(dq_analyze::schema_proposals_wire::Terminal),
    NativeFixFinished(dq_analyze::native_fix_wire::Terminal),
    BaselineUpdateFinished(dq_analyze::native_baseline_update_wire::Terminal),
    CheckerTextFinished(dq_analyze::native_checker_wire::Terminal),
}

#[derive(Default)]
struct Collector {
    stage: Option<Stage>,
    next: u32,
}
impl Collector {
    fn push(&mut self, cache: &Path, fragment: &Fragment) -> io::Result<()> {
        if fragment.sequence != self.next || fragment.offset != self.stage.as_ref().map_or(0, Stage::length) {
            return Err(invalid("selected report fragment is reordered or noncontiguous"));
        }
        let next = self.next.checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?;
        let stage = match &mut self.stage {
            Some(stage) => stage,
            slot @ None => slot.insert(Stage::new(cache)?),
        };
        stage.write_all(&fragment.bytes.data[..fragment.bytes.length])?;
        self.next = next;
        Ok(())
    }

    fn finish(self, expected: Option<Seal>) -> io::Result<Option<Verified>> {
        match (self.stage, expected) {
            (None, None) => Ok(None),
            (Some(stage), Some(expected)) if stage.length() == expected.length => {
                let (file, count) = stage.seal()?.validate(|read| io::copy(read, &mut io::sink()))?;
                if count != expected.length || seal_of(&file) != expected {
                    return Err(invalid("selected report length or digest differs"));
                }
                Ok(Some(file))
            }
            _ => Err(invalid("selected report terminal differs from its received streams")),
        }
    }
}

/// Held until terminal, frame boundaries, EOF and both private files pass.
/// Neither a partial success nor a remote rejection can reach a caller writer.
pub(crate) struct Delivered<T = Terminal> {
    terminal: T,
    diagnostics: Option<Verified>,
    report: Verified,
}

impl Delivered {
    /// A bounded metadata line precedes the exact report body. Actual Original
    /// diagnostics are separate and become visible only for a verified batch.
    pub(crate) fn publish(self, diagnostics: &mut impl Write, output: &mut impl Write) -> io::Result<bool> {
        let clean = self.terminal.clean;
        self.publish_analyze(diagnostics, output)?;
        Ok(clean)
    }
}
impl Delivered<TerminalV2> {
    pub(crate) fn publish(self, diagnostics: &mut impl Write, output: &mut impl Write) -> io::Result<bool> {
        let clean = self.terminal.clean;
        self.publish_analyze(diagnostics, output)?;
        Ok(clean)
    }
}
impl Delivered<RawSelectedTerminal> {
    pub(crate) fn publish(self, diagnostics: &mut impl Write, output: &mut impl Write) -> io::Result<bool> {
        let clean = self.terminal.clean;
        self.publish_analyze(diagnostics, output)?;
        Ok(clean)
    }
}
impl<T: Serialize> Delivered<T> {
    fn publish_analyze(self, diagnostics: &mut impl Write, output: &mut impl Write) -> io::Result<()> {
        let (header, size) = encode_header(&self.terminal)?;
        control::begin_publication()?;
        if let Some(file) = self.diagnostics {
            file.publish(diagnostics)?;
        }
        output.write_all(&header[..size])?;
        self.report.publish(output)
    }
}

pub(crate) struct DeliveredCombined {
    terminal: CombinedTerminal,
    diagnostics: Option<Verified>,
    checker: Verified,
    report: Verified,
}

impl DeliveredCombined {
    /// CLI representation: bounded terminal line, exact checker bytes, then
    /// exact Analyze bytes on stdout. Preparation diagnostics remain stderr.
    pub(crate) fn publish(self, diagnostics: &mut impl Write, output: &mut impl Write) -> io::Result<bool> {
        let (header, size) = encode_header(&self.terminal)?;
        self.publish_with_header(&header[..size], diagnostics, output)
    }

    fn publish_with_header(self, header: &[u8], diagnostics: &mut impl Write, output: &mut impl Write) -> io::Result<bool> {
        control::begin_publication()?;
        if let Some(file) = self.diagnostics {
            file.publish(diagnostics)?;
        }
        output.write_all(header)?;
        self.checker.publish(output)?;
        self.report.publish(output)?;
        Ok(self.terminal.clean)
    }
}

fn encode_header(value: &impl Serialize) -> io::Result<([u8; MAX_HEADER], usize)> {
    let mut header = [0u8; MAX_HEADER];
    let size = {
        let mut writer = Cursor::new(header.as_mut_slice());
        serde_json::to_writer(&mut writer, value).map_err(io::Error::other)?;
        writer.write_all(b"\n")?;
        writer.position() as usize
    };
    Ok((header, size))
}

fn require_end(stream: &mut impl Read) -> io::Result<()> {
    match stream.read(&mut [0u8]) {
        Ok(0) => Ok(()),
        Ok(_) => Err(invalid("selected report has data after its terminal")),
        // The real Windows pipe uses PeekNamedPipe, which reports a closed
        // peer as an OS error. A close is success only AFTER a valid terminal.
        #[cfg(windows)]
        Err(error) if matches!(error.raw_os_error(), Some(109 | 233)) => Ok(()),
        Err(error) => Err(error),
    }
}

pub(crate) fn receive(stream: &mut impl Read, cache: &Path, expected: Roster) -> Result<Delivered, Box<dyn Error>> {
    match receive_mode(stream, cache, Some(expected), Mode::Ordinary, None)? {
        Received::Ordinary(delivered) => Ok(delivered),
        _ => Err(invalid("unexpected selected report terminal version").into()),
    }
}

pub(crate) fn receive_raw_selected(
    stream: &mut impl Read, cache: &Path, expected: Roster,
) -> Result<Delivered<RawSelectedTerminal>, Box<dyn Error>> {
    let mut report = Collector::default();
    let mut accepted = false;
    loop {
        control::checkpoint()?;
        match protocol::receive_bounded::<ReceiveReply>(stream, protocol::MAX_FRAME)? {
            ReceiveReply::Accepted if !accepted => accepted = true,
            ReceiveReply::Rejected(error) if report.next == 0 =>
                return Err(RequestFailure { kind: error.kind, message: error.message }.into()),
            ReceiveReply::SelectedReportFragment(fragment) if accepted && fragment.channel == Channel::Report =>
                report.push(cache, &fragment)?,
            ReceiveReply::RawSelectedReportFinished(terminal) if accepted => {
                terminal.require(expected)?;
                require_end(stream)?;
                let report = report.finish(Some(terminal.report))?.ok_or_else(|| invalid("raw selected report has no body"))?;
                return Ok(Delivered { terminal, diagnostics: None, report });
            }
            _ => return Err(invalid("unexpected raw selected report response or channel").into()),
        }
    }
}

pub(crate) fn receive_combined(stream: &mut impl Read, cache: &Path, expected: Roster) -> Result<DeliveredCombined, Box<dyn Error>> {
    match receive_mode(stream, cache, Some(expected), Mode::Combined, None)? {
        Received::Combined(delivered) => Ok(delivered),
        _ => Err(invalid("unexpected combined selected report terminal version").into()),
    }
}

pub(crate) fn receive_v2(stream: &mut impl Read, cache: &Path, expected: Roster, judgment: JudgmentV2) -> Result<Delivered<TerminalV2>, Box<dyn Error>> {
    if !Roster::v2_for(judgment).contains(&expected) {
        return Err(invalid("selected v2 receive requires its admitted roster and judgment").into());
    }
    SelectedPoliciesV2::for_roster(expected)?;
    match receive_mode(stream, cache, Some(expected), Mode::GenericV2(judgment), None)? {
        Received::GenericV2(delivered) => Ok(delivered),
        _ => Err(invalid("unexpected selected v2 report terminal version").into()),
    }
}

pub(crate) struct DeliveredNamedImageDir {
    terminal:NamedImageDirTerminal,
    report:Verified,
}
impl DeliveredNamedImageDir {
    pub(crate) fn publish(self,output:&mut impl Write)->io::Result<bool>{
        let(header,size)=encode_header(&self.terminal)?;
        control::begin_publication()?;
        output.write_all(&header[..size])?;
        self.report.publish(output)?;
        Ok(self.terminal.clean)
    }
}

pub(crate) fn receive_named_image_dir(stream:&mut impl Read,cache:&Path)->Result<DeliveredNamedImageDir,Box<dyn Error>>{
    let mut report=Collector::default();
    let mut accepted=false;
    loop {
        control::checkpoint()?;
        match protocol::receive_bounded::<ReceiveReply>(stream,protocol::MAX_FRAME)? {
            ReceiveReply::Accepted if !accepted=>accepted=true,
            ReceiveReply::Rejected(error) if report.next==0=>
                return Err(RequestFailure{kind:error.kind,message:error.message}.into()),
            ReceiveReply::NamedImageDirRejected(error) if report.next==0=>{
                if let Some(code)=error.os_code{return Err(io::Error::from_raw_os_error(code).into())}
                return Err(error.failure.into());
            }
            ReceiveReply::SelectedReportFragment(fragment) if accepted&&matches!(fragment.channel,Channel::Report)=>
                report.push(cache,&fragment)?,
            ReceiveReply::NamedImageDirReportFinished(terminal) if accepted=>{
                terminal.require()?;
                require_end(stream)?;
                let report=report.finish(Some(terminal.report))?.ok_or_else(||invalid("named ImageDir has no report body"))?;
                return Ok(DeliveredNamedImageDir{terminal,report});
            }
            _=>return Err(invalid("unexpected named ImageDir response or channel").into()),
        }
    }
}

pub(crate) struct DeliveredCompilation {
    terminal: CompoundTerminal,
    diagnostics: Option<Verified>,
    checker: Verified,
    report: Verified,
    clean: bool,
}
impl DeliveredCompilation {
    pub(crate) fn publish(self, diagnostics: &mut impl Write, output: &mut impl Write) -> io::Result<bool> {
        let (header, size) = encode_header(&self.terminal)?;
        control::begin_publication()?;
        if let Some(file)=self.diagnostics { file.publish(diagnostics)?; }
        output.write_all(&header[..size])?;
        self.checker.publish(output)?;
        self.report.publish(output)?;
        Ok(self.clean)
    }
}

/// Verification belongs to the exact native destination admitted by the
/// client request. Never publish report bytes from a remote pair claim alone.
pub(crate) fn receive_compilation(
    stream: &mut impl Read, cache: &Path, expected: CompoundRoster,
    verify_installed: impl FnOnce(&crate::publish::OutputPair) -> io::Result<()>,
) -> Result<DeliveredCompilation, Box<dyn Error>> {
    match receive_mode(stream, cache, None, Mode::Combined, Some(expected))? {
        Received::Compilation(delivered) => {
            verify_installed(&delivered.terminal.native_pair)?;
            Ok(delivered)
        }
        _ => Err(invalid("unexpected compound selected report terminal version").into()),
    }
}

enum Received { Ordinary(Delivered), Combined(DeliveredCombined), GenericV2(Delivered<TerminalV2>), Compilation(DeliveredCompilation) }

// Each mode demands its own terminal and exact channels before publication.
fn receive_mode(stream: &mut impl Read, cache: &Path, expected: Option<Roster>, mode: Mode, compound: Option<CompoundRoster>) -> Result<Received, Box<dyn Error>> {
    let combined = mode == Mode::Combined;
    let mut diagnostics = Collector::default();
    let mut checker = Collector::default();
    let mut report = Collector::default();
    let mut accepted = false;
    let mut total = 0u64;
    loop {
        control::checkpoint()?;
        match protocol::receive_bounded::<ReceiveReply>(stream, protocol::MAX_FRAME)? {
            ReceiveReply::Accepted if !accepted => accepted = true,
            ReceiveReply::Rejected(error) if diagnostics.next == 0 && checker.next == 0 && report.next == 0 => {
                return Err(RequestFailure { kind: error.kind, message: error.message }.into());
            }
            ReceiveReply::SelectedReportFragment(fragment) if accepted => {
                if mode != Mode::Ordinary {
                    total = total.checked_add(fragment.bytes.length as u64).filter(|sum| *sum <= MAX_STREAM)
                        .ok_or_else(|| invalid(if combined { "combined selected report exceeds the aggregate stream bound" }
                            else { "selected v2 report exceeds the aggregate stream bound" }))?;
                }
                match fragment.channel {
                    Channel::Diagnostics if checker.next == 0 && report.next == 0 => diagnostics.push(cache, &fragment)?,
                    Channel::Checker if combined && report.next == 0 => checker.push(cache, &fragment)?,
                    Channel::Report if !combined || checker.next != 0 => report.push(cache, &fragment)?,
                    _ => return Err(invalid("selected report has an unexpected or out-of-order channel").into()),
                }
            }
            ReceiveReply::SelectedReportFinished(terminal) if accepted && mode == Mode::Ordinary => {
                terminal.require(expected.ok_or_else(||invalid("selected report request absent"))?)?;
                // One request per connection. An extra frame invalidates all streams.
                require_end(stream)?;
                let diagnostics = diagnostics.finish(terminal.diagnostics)?;
                let report = report.finish(Some(terminal.report))?.ok_or_else(|| invalid("selected report has no body"))?;
                return Ok(Received::Ordinary(Delivered { terminal, diagnostics, report }));
            }
            ReceiveReply::SelectedReportV2Finished(terminal) if accepted && matches!(mode, Mode::GenericV2(_)) => {
                let Mode::GenericV2(judgment) = mode else { unreachable!("checked v2 report mode") };
                terminal.require_using(expected.ok_or_else(||invalid("selected v2 request absent"))?, judgment)?;
                require_end(stream)?;
                let diagnostics = diagnostics.finish(terminal.diagnostics)?;
                let report = report.finish(Some(terminal.report))?.ok_or_else(|| invalid("selected v2 report has no body"))?;
                return Ok(Received::GenericV2(Delivered { terminal, diagnostics, report }));
            }
            ReceiveReply::SelectedCompilationFinished(terminal) if accepted && combined && compound.is_some() => {
                terminal.require(compound.expect("compound route"))?;
                require_end(stream)?;
                let (d, c, r, clean) = match &terminal.selected {
                    CompoundReports::Selected(t)=>(t.diagnostics,t.checker,t.report,t.clean),
                    CompoundReports::FullRegistry(t)=>(t.diagnostics,t.checker,t.report,t.clean),
                };
                let diagnostics = diagnostics.finish(d)?;
                let checker = checker.finish(Some(c))?.ok_or_else(||invalid("compound Checker body missing"))?;
                let report = report.finish(Some(r))?.ok_or_else(||invalid("compound Analyze body missing"))?;
                return Ok(Received::Compilation(DeliveredCompilation { terminal, diagnostics, checker, report, clean }));
            }
            ReceiveReply::SelectedCombinedReportFinished(terminal) if accepted && combined && compound.is_none() => {
                terminal.require()?;
                if Some(terminal.roster) != expected {
                    return Err(invalid("combined selected report terminal names a foreign roster").into());
                }
                require_end(stream)?;
                return Ok(Received::Combined(finish_combined(terminal, diagnostics, checker, report)?));
            }
            _ => return Err(invalid("unexpected selected report response").into()),
        }
    }
}

fn finish_combined(terminal: CombinedTerminal, diagnostics: Collector, checker: Collector, report: Collector) -> io::Result<DeliveredCombined> {
    let diagnostics = diagnostics.finish(terminal.diagnostics)?;
    let checker = checker.finish(Some(terminal.checker))?.ok_or_else(|| invalid("combined selected report has no checker body"))?;
    let report = report.finish(Some(terminal.report))?.ok_or_else(|| invalid("combined selected report has no Analyze body"))?;
    Ok(DeliveredCombined { terminal, diagnostics, checker, report })
}

#[cfg(test)]
#[path = "selected_report_wire_controls.rs"]
mod wire_controls;


/// Report-only full-registry delivery retains the actual preparation ledger.
/// It has no irreversible source/output mutation, so keep cancellation and the
/// SAME request deadline active throughout fragments AND final freshness.
pub(crate) fn send_full_check(stream:&mut impl Write,completed:crate::runner_host::FullRegistryCheckReport,work:&dyn SourceArenaWork)->Result<crate::runner_host::FullRegistryCheckInputs,SendFailure>{
 use dq_analyze::full_registry_check_wire::{Terminal,Schema,Scope};
 let crate::runner_host::FullRegistryCheckReport{project,inputs,frame,selection,selected,registered,format,clean,selftests,cli,diagnostics,report,_credit,..}=completed;
 let convert=|error:Box<dyn Error>|match error.downcast::<io::Error>(){Ok(actual)=>*actual,Err(other)=>io::Error::other(other.to_string())};
 inputs.require_report_current(&project).map_err(convert).map_err(SendFailure::BeforePublication)?;
 let terminal=Terminal{schema:if selftests.is_some(){Schema::V3}else{Schema::V2},complete:true,full_policy_parity:false,scope:if selected==registered{Scope::FullRegistry}else{Scope::RegistrySelection},options:format,selection,selected,registered,frame,clean,selftests,diagnostics:diagnostics.as_ref().map(seal_of),report:seal_of(&report)};
 terminal.require_selftests(format,selection,selftests.is_some()).map_err(SendFailure::BeforePublication)?;
 let usage_seal=cli.as_ref().filter(|cli|cli.usage_requested).map(|cli|cli.usage.as_ref().map(seal_of).unwrap_or(Seal{length:0,hash:Hex128(xxhash_rust::xxh3::xxh3_128(b""))}));
 let total=terminal.report.length.checked_add(terminal.diagnostics.as_ref().map_or(0,|seal|seal.length)).and_then(|n|n.checked_add(usage_seal.as_ref().map_or(0,|seal|seal.length)));
 if total.is_none_or(|n|n>MAX_STREAM){return Err(SendFailure::BeforePublication(invalid("CHECK CLI streams exceed the existing aggregate report bound")))}
 let outer=cli.as_ref().map(|cli|dq_analyze::native_check_cli_wire::Terminal{schema:dq_analyze::native_check_cli_wire::Schema::V1,requested:cli.binding,terminal:terminal.clone(),usage:usage_seal});
 if let Some(outer)=&outer{encode_header(outer).map_err(SendFailure::BeforePublication)?;}else{encode_header(&terminal).map_err(SendFailure::BeforePublication)?;}
 let _scratch=work.reserve(SEND_SCRATCH).map_err(SendFailure::BeforePublication)?;
 let sent=(||{
  control::checkpoint()?;
  if let Some(stage)=diagnostics{stage.publish(&mut FragmentWriter{stream:&mut *stream,channel:Channel::Diagnostics,sequence:0,offset:0})?;}
  report.publish(&mut FragmentWriter{stream:&mut *stream,channel:Channel::Report,sequence:0,offset:0})?;
  // Consume only the genuine producer-owned usage stream; retain its resource
  // owner, final input ledger and all other output grants through the terminal.
  if let Some(mut cli)=cli{if let Some(stage)=cli.usage.take(){stage.publish(&mut FragmentWriter{stream:&mut *stream,channel:Channel::Usage,sequence:0,offset:0})?;}inputs.require_report_current(&project).map_err(convert)?;control::checkpoint()?;protocol::send(stream,&SendReply::FullRegistryCheckCliFinished(outer.ok_or_else(||invalid("CHECK CLI owner omitted its terminal"))?))}
  else{inputs.require_report_current(&project).map_err(convert)?;control::checkpoint()?;protocol::send(stream,&SendReply::FullRegistryCheckFinished(terminal))}
  ?;control::checkpoint()
 })();sent.map_err(SendFailure::AfterPublication)?;Ok(inputs)
}
pub(crate) struct DeliveredFullCheck{terminal:dq_analyze::full_registry_check_wire::Terminal,cli:Option<dq_analyze::native_check_cli_wire::Terminal>,timing_only:bool,diagnostics:Option<Verified>,report:Verified,usage:Option<Verified>}
impl DeliveredFullCheck{
 pub(crate) fn publish(self,output:&mut impl Write)->io::Result<bool>{
  let(header,length)=if let Some(cli)=&self.cli{encode_header(cli)?}else{encode_header(&self.terminal)?};
  output.write_all(&header[..length])?;if let Some(stage)=self.diagnostics{stage.publish(output)?;}self.report.publish(output)?;if let Some(stage)=self.usage{stage.publish(output)?;}Ok(self.terminal.clean||self.timing_only)
 }
}
pub(crate) fn receive_full_check(stream:&mut impl Read,cache:&Path,expected:crate::runner_host::FullRegistryCheckOptions,selection:dq_analyze::full_registry_check_selection_wire::SelectionBinding)->Result<DeliveredFullCheck,Box<dyn Error>>{ receive_full_check_selftests(stream,cache,expected,selection,false) }
pub(crate) fn receive_full_check_selftests(stream:&mut impl Read,cache:&Path,expected:crate::runner_host::FullRegistryCheckOptions,selection:dq_analyze::full_registry_check_selection_wire::SelectionBinding,selftests:bool)->Result<DeliveredFullCheck,Box<dyn Error>>{receive_full_check_cli(stream,cache,expected,selection,selftests,None)}
pub(crate) fn receive_full_check_cli(stream:&mut impl Read,cache:&Path,expected:crate::runner_host::FullRegistryCheckOptions,selection:dq_analyze::full_registry_check_selection_wire::SelectionBinding,selftests:bool,cli:Option<&dq_analyze::native_check_cli_wire::Request>)->Result<DeliveredFullCheck,Box<dyn Error>>{
 if let Some(cli)=cli{cli.qualify(expected,selftests)?;}
 let(mut accepted,mut diagnostics,mut report,mut usage)=(false,Collector::default(),Collector::default(),Collector::default());let mut total=0u64;
 loop{control::checkpoint()?;match protocol::receive_bounded::<ReceiveReply>(stream,protocol::MAX_FRAME)?{
  ReceiveReply::Accepted if !accepted=>accepted=true,
  ReceiveReply::Rejected(error) if diagnostics.next==0&&report.next==0&&usage.next==0=>return Err(RequestFailure{kind:error.kind,message:error.message}.into()),
  ReceiveReply::SelectedReportFragment(fragment) if accepted=>{total=total.checked_add(fragment.bytes.length as u64).filter(|n|*n<=MAX_STREAM).ok_or_else(||invalid("CHECK received streams exceed the existing aggregate report bound"))?;match fragment.channel{Channel::Diagnostics if report.next==0&&usage.next==0=>diagnostics.push(cache,&fragment)?,Channel::Report if usage.next==0=>report.push(cache,&fragment)?,Channel::Usage if cli.is_some_and(|cli|cli.allow_usage)&&report.next!=0=>usage.push(cache,&fragment)?,_=>return Err(invalid("report-only CHECK received an unexpected or out-of-order channel").into())}},
  ReceiveReply::FullRegistryCheckFinished(terminal) if accepted&&cli.is_none()=>{
   terminal.require_selftests(expected,selection,selftests)?;require_end(stream)?;
   let diagnostics=diagnostics.finish(terminal.diagnostics)?;let report=report.finish(Some(terminal.report))?.ok_or_else(||invalid("full CHECK terminal has no actual report body"))?;
   return Ok(DeliveredFullCheck{terminal,cli:None,timing_only:false,diagnostics,report,usage:None})
  },
  ReceiveReply::FullRegistryCheckCliFinished(outer) if accepted&&cli.is_some()=>{
   let requested=cli.ok_or_else(||invalid("CHECK CLI terminal has no request"))?;outer.require(expected,selection,selftests,requested)?;require_end(stream)?;
   let diagnostics=diagnostics.finish(outer.terminal.diagnostics)?;let report=report.finish(Some(outer.terminal.report))?.ok_or_else(||invalid("CHECK CLI terminal has no actual report body"))?;
   let usage=match outer.usage{Some(seal)if seal.length==0=>{if usage.next!=0||seal.hash.0!=xxhash_rust::xxh3::xxh3_128(b""){return Err(invalid("empty CHECK usage terminal differs from its actual bytes").into())}usage.finish(None)?},seal=>usage.finish(seal)?};
   return Ok(DeliveredFullCheck{terminal:outer.terminal.clone(),cli:Some(outer),timing_only:requested.timing_only,diagnostics,report,usage})
  },
  _=>return Err(invalid("unexpected full native CHECK report-only frame").into()),
 }}
}

#[path="checker_text_wire.rs"]mod checker_text_wire;
pub(crate) use checker_text_wire::{send_checker_text,receive_checker_text};

/// Callback-only stream: no CHECK frame or policy/model claims.
pub(crate) fn send_standalone_selftests(stream:&mut impl Write,completed:crate::runner_host::StandaloneSelftestReport,work:&dyn SourceArenaWork)->Result<(),SendFailure>{
 let convert=|e:Box<dyn Error>|match e.downcast::<io::Error>(){Ok(e)=>*e,Err(e)=>io::Error::other(e.to_string())};
 completed.require_current().map_err(convert).map_err(SendFailure::BeforePublication)?;
 let crate::runner_host::StandaloneSelftestReport{inputs,report,plan,queries,_credit}=completed;
 let actual=plan.native_selftest_result().map_err(SendFailure::BeforePublication)?.ok_or_else(||SendFailure::BeforePublication(invalid("standalone callbacks missing actual result")))?;
 let terminal=dq_analyze::native_selftest_wire::Terminal{schema:dq_analyze::native_selftest_wire::Schema::V1,complete:true,selection:plan.binding(),selected:plan.names().len()as u64,completed:actual.completed()as u64,failed:actual.failed()as u64,report:seal_of(&report)};
 terminal.require(plan.binding()).map_err(SendFailure::BeforePublication)?;encode_header(&terminal).map_err(SendFailure::BeforePublication)?;
 let scratch=work.reserve(SEND_SCRATCH).map_err(SendFailure::BeforePublication)?;
 let result=(||{control::checkpoint()?;report.publish(&mut FragmentWriter{stream:&mut *stream,channel:Channel::Report,sequence:0,offset:0})?;crate::request_runner::runner_freshness::require_native_callback_inputs_current(&inputs).map_err(convert)?;control::checkpoint()?;protocol::send(stream,&SendReply::NativeSelftestsFinished(terminal))?;control::checkpoint()})();
 drop(inputs);drop(plan);drop(queries);drop(scratch);drop(_credit);result.map_err(SendFailure::AfterPublication)
}
pub(crate) struct DeliveredStandaloneSelftests{terminal:dq_analyze::native_selftest_wire::Terminal,report:Verified}
impl DeliveredStandaloneSelftests{pub(crate)fn publish(self,output:&mut impl Write)->io::Result<bool>{let(header,n)=encode_header(&self.terminal)?;output.write_all(&header[..n])?;self.report.publish(output)?;Ok(self.terminal.failed==0)}}
pub(crate) fn receive_standalone_selftests(stream:&mut impl Read,cache:&Path,selection:dq_analyze::full_registry_check_selection_wire::SelectionBinding)->Result<DeliveredStandaloneSelftests,Box<dyn Error>>{
 let(mut accepted,mut report,mut total)=(false,Collector::default(),0u64);
 loop{control::checkpoint()?;match protocol::receive_bounded::<ReceiveReply>(stream,protocol::MAX_FRAME)?{
  ReceiveReply::Accepted if !accepted=>accepted=true,
  ReceiveReply::Rejected(error)if report.next==0=>return Err(RequestFailure{kind:error.kind,message:error.message}.into()),
  ReceiveReply::SelectedReportFragment(fragment)if accepted&&matches!(fragment.channel,Channel::Report)=>{total=total.checked_add(fragment.bytes.length as u64).filter(|n|*n<=MAX_STREAM).ok_or_else(||invalid("standalone callback stream exceeds report bound"))?;report.push(cache,&fragment)?;},
  ReceiveReply::NativeSelftestsFinished(terminal)if accepted=>{terminal.require(selection)?;require_end(stream)?;let report=report.finish(Some(terminal.report))?.ok_or_else(||invalid("standalone terminal has no transcript"))?;return Ok(DeliveredStandaloneSelftests{terminal,report})},
  _=>return Err(invalid("unexpected standalone callback frame").into()),
 }}
}

#[path="native_utility_streams.rs"]pub(super) mod utility_streams;
#[path="native_sem_utility_wire.rs"]mod sem_utility;
pub(crate) use sem_utility::{send_native_sem_utility,receive_native_sem_utility};

#[path="native_codemod_fixture_wire.rs"]mod codemod_fixture_utility;
pub(crate)use codemod_fixture_utility::{send_native_codemod_fixture,receive_native_codemod_fixture};

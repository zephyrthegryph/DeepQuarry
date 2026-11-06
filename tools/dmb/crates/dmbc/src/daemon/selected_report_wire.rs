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

use super::{control, generation::MAX_REPORT_BYTES, protocol};

const FRAGMENT: usize = 8192;
const HEADER: usize = 1024;
// At most one frame and fixed-sized decoded fragment live. Numeric-byte JSON
// can expand a single u8 to four bytes before the enclosing record is counted.
const SEND_SCRATCH: usize = FRAGMENT * 18 + 4096;

#[derive(Clone, Copy, Debug, Deserialize, Eq, Ord, PartialEq, PartialOrd, Serialize)]
#[serde(rename_all = "snake_case")]
pub(crate) enum Roster {
    Base,
    WithCooldown,
    WithSilicon,
}

impl Roster {
    pub(crate) const MAX_POLICIES: usize = 6;
    pub(crate) const ALL: [Self; 3] = [Self::Base, Self::WithCooldown, Self::WithSilicon];

    pub(crate) fn names(self) -> &'static [&'static str] {
        match self {
            Self::Base => &["allow_annotations", "notice_publisher", "report_in_catch", "scheduler"],
            Self::WithCooldown => &["allow_annotations", "cooldown", "notice_publisher", "report_in_catch", "scheduler"],
            Self::WithSilicon => &["allow_annotations", "cooldown", "notice_publisher", "report_in_catch", "scheduler", "silicon_entry"],
        }
    }
}

fn invalid(message: &'static str) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, message)
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct Hex128(u128);

impl Hex128 {
    fn parse(value: &str) -> Option<Self> {
        if value.len() != 32 || !value.bytes().all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b)) {
            return None;
        }
        u128::from_str_radix(value, 16).ok().map(Self)
    }
}
impl Serialize for Hex128 {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        serializer.collect_str(&format_args!("{:032x}", self.0))
    }
}
impl<'de> Deserialize<'de> for Hex128 {
    fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        struct HexVisitor;
        impl serde::de::Visitor<'_> for HexVisitor {
            type Value = Hex128;
            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("32 lowercase hexadecimal digits")
            }
            fn visit_str<E: serde::de::Error>(self, value: &str) -> Result<Self::Value, E> {
                Hex128::parse(value).ok_or_else(|| E::custom("invalid selected report digest or revision"))
            }
        }
        deserializer.deserialize_str(HexVisitor)
    }
}

/// Transport coordinates from the actual admitted preparation. Decoding these
/// values on the client does not create a source frame or a reusable query pin.
#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct Frame {
    semantic_revision: Hex128,
    source_revision: Hex128,
    policy_revision: Hex128,
}
impl Frame {
    pub(crate) fn from_prepared(prepared: &BuildOutcome) -> io::Result<Self> {
        let BuildOutcome::QueryPrepared { semantic_revision, source_revision, policy_revision: Some(policy_revision), retained: true } = prepared else {
            return Err(invalid("selected report requires actual retained Original preparation"));
        };
        let pin = |value: &str| Hex128::parse(value).ok_or_else(|| invalid("selected preparation has an invalid revision"));
        Ok(Self {
            semantic_revision: pin(semantic_revision)?,
            source_revision: pin(source_revision)?,
            policy_revision: pin(policy_revision)?,
        })
    }
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
enum Channel {
    Diagnostics,
    Report,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
enum Schema {
    #[serde(rename = "native-analyze-exclusions-batch-v1")]
    V1,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
struct Seal {
    length: u64,
    hash: Hex128,
}
impl Seal {
    fn of(file: &Verified) -> Self {
        Self { length: file.length(), hash: Hex128(file.hash()) }
    }

    fn require_bound(self) -> io::Result<()> {
        if self.length == 0 || self.length > MAX_REPORT_BYTES as u64 {
            return Err(invalid("selected report terminal declares an empty or oversized stream"));
        }
        Ok(())
    }
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
struct Terminal {
    schema: Schema,
    roster: Roster,
    frame: Frame,
    clean: bool,
    #[serde(deserialize_with = "explicit_option")]
    diagnostics: Option<Seal>,
    report: Seal,
}
fn explicit_option<'de, D: serde::Deserializer<'de>, T: Deserialize<'de>>(deserializer: D) -> Result<Option<T>, D::Error> {
    Option::deserialize(deserializer)
}

impl Terminal {
    fn require(self, expected: Roster) -> io::Result<()> {
        if self.roster != expected {
            return Err(invalid("selected report terminal names a foreign roster"));
        }
        self.report.require_bound()?;
        if let Some(diagnostics) = self.diagnostics {
            diagnostics.require_bound()?;
        }
        Ok(())
    }
}

#[derive(Serialize)]
enum SendReply<'a> {
    SelectedReportFragment { channel: Channel, sequence: u32, offset: u64, bytes: &'a [u8] },
    SelectedReportFinished(Terminal),
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
    let terminal = Terminal {
        schema: Schema::V1, roster, frame, clean,
        diagnostics: diagnostics.as_ref().map(Seal::of), report: Seal::of(&report),
    };
    terminal.require(roster).map_err(SendFailure::BeforePublication)?;
    let _frame = work.reserve(SEND_SCRATCH).map_err(SendFailure::BeforePublication)?;
    control::begin_publication().map_err(SendFailure::BeforePublication)?;
    let sent = (|| {
        if let Some(diagnostics) = diagnostics {
            diagnostics.publish(&mut FragmentWriter { stream: &mut *stream, channel: Channel::Diagnostics, sequence: 0, offset: 0 })?;
        }
        report.publish(&mut FragmentWriter { stream: &mut *stream, channel: Channel::Report, sequence: 0, offset: 0 })?;
        protocol::send(stream, &SendReply::SelectedReportFinished(terminal))
    })();
    sent.map_err(SendFailure::AfterPublication)
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
    Accepted,
    Rejected(Rejection),
    SelectedReportFragment(Fragment),
    SelectedReportFinished(Terminal),
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
                if count != expected.length || Seal::of(&file) != expected {
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
pub(crate) struct Delivered {
    terminal: Terminal,
    diagnostics: Option<Verified>,
    report: Verified,
}

impl Delivered {
    /// A bounded metadata line precedes the exact report body. Actual Original
    /// diagnostics are separate and become visible only for a verified batch.
    pub(crate) fn publish(self, diagnostics: &mut impl Write, output: &mut impl Write) -> io::Result<bool> {
        let mut header = [0u8; HEADER];
        let size = {
            let mut writer = Cursor::new(header.as_mut_slice());
            serde_json::to_writer(&mut writer, &self.terminal).map_err(io::Error::other)?;
            writer.write_all(b"\n")?;
            writer.position() as usize
        };
        control::begin_publication()?;
        if let Some(file) = self.diagnostics {
            file.publish(diagnostics)?;
        }
        output.write_all(&header[..size])?;
        self.report.publish(output)?;
        Ok(self.terminal.clean)
    }
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
    let mut diagnostics = Collector::default();
    let mut report = Collector::default();
    let mut accepted = false;
    loop {
        control::checkpoint()?;
        match protocol::receive_bounded::<ReceiveReply>(stream, protocol::MAX_FRAME)? {
            ReceiveReply::Accepted if !accepted => accepted = true,
            ReceiveReply::Rejected(error) if diagnostics.next == 0 && report.next == 0 => {
                return Err(RequestFailure { kind: error.kind, message: error.message }.into());
            }
            ReceiveReply::SelectedReportFragment(fragment) if accepted => match fragment.channel {
                Channel::Diagnostics if report.next == 0 => diagnostics.push(cache, &fragment)?,
                Channel::Report => report.push(cache, &fragment)?,
                Channel::Diagnostics => return Err(invalid("selected diagnostics follow report bytes").into()),
            },
            ReceiveReply::SelectedReportFinished(terminal) if accepted => {
                terminal.require(expected)?;
                // This service uses one request per connection. An extra frame
                // after the terminal invalidates the whole machine transcript.
                require_end(stream)?;
                let diagnostics = diagnostics.finish(terminal.diagnostics)?;
                let report = report.finish(Some(terminal.report))?.ok_or_else(|| invalid("selected report has no body"))?;
                return Ok(Delivered { terminal, diagnostics, report });
            }
            _ => return Err(invalid("unexpected selected report response").into()),
        }
    }
}

#[cfg(test)]
#[path = "selected_report_wire_controls.rs"]
mod wire_controls;

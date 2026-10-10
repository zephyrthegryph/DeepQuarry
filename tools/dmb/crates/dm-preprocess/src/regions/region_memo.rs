//! Expansion reuse after a fresh, ordered directive plan. Conditional/include
//! interpretation and effects remain authoritative in that plan; this memo never
//! speculates a different directive state or parses a region as a standalone AST.
pub(super) mod retained_size;
#[cfg(test)]
mod retained_size_tests;
mod source_wire;
#[path = "expansion_storage.rs"]
pub(super) mod storage;
use super::{DirectivePlan, MacroEnvironment, MacroExpansion};
use crate::{Diagnostic, DiagnosticKind, Macro, MacroLookup};
use dm_syntax::Span;
use retained_size::{record, shared_macro, slice, vector};
use serde::{Deserialize, Serialize};
use std::{
    cell::RefCell,
    collections::{BTreeMap, BTreeSet},
    sync::Arc,
};
use xxhash_rust::xxh3::Xxh3;
pub const EXPANSION_VERSION: u32 = 3;
pub const FRAGMENT_VERSION: u32 = 1;
#[cfg(test)]
mod fragment_tests {
    use super::*;
    #[test]
    fn independent_fragment_requires_exact_source_and_schema() {
        let record = FragmentRecord::new(3, "/datum/probe\n", Arc::from([1u8, 2, 3])).unwrap();
        let restored = FragmentRecord::from_bytes(&record.to_bytes().unwrap()).unwrap();
        assert_eq!(restored, record);
        assert!(restored.matches(3, "/datum/probe\n"));
        assert!(!restored.matches(4, "/datum/probe\n"));
        assert!(!restored.matches(3, "/datum/other\n"));
        assert_ne!(
            record.key(),
            FragmentRecord::lookup_key(3, "/datum/other\n")
        );
        assert!(FragmentRecord::from_bytes(&[0; 8]).is_err());
        assert!(FragmentRecord::new(3, "x", vec![0; 4 * 1024 * 1024 + 1].into()).is_some());
    }
}
/// Root-context grammar chunks are looked up independently of region offsets.
/// The parser must still validate its payload and freshly bind all provenance.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct FragmentRecord {
    schema: u32,
    source: Arc<str>,
    payload: Arc<[u8]>,
}
impl FragmentRecord {
    /// Conservative retained allocation bytes including this record's Arc;
    /// shared backing storage is charged for each occurrence, never deduplicated.
    pub fn retained_size_bytes(&self) -> usize {
        record::<Self>()
            .saturating_add(slice::<u8>(self.source.len()))
            .saturating_add(slice::<u8>(self.payload.len()))
    }

    pub fn lookup_key(schema: u32, source: &str) -> u128 {
        let mut hash = Xxh3::new();
        hash.update(b"root-grammar-fragment-v1\0");
        hash.update(&schema.to_le_bytes());
        hash.update(&(source.len() as u64).to_le_bytes());
        hash.update(source.as_bytes());
        hash.digest128()
    }
    pub fn new(schema: u32, source: &str, payload: Arc<[u8]>) -> Option<Self> {
        Some(Self {
            schema,
            source: source.into(),
            payload,
        })
    }
    pub fn key(&self) -> u128 {
        Self::lookup_key(self.schema, &self.source)
    }
    pub fn matches(&self, schema: u32, source: &str) -> bool {
        self.schema == schema && self.source.as_ref() == source
    }
    pub fn payload(&self) -> &[u8] {
        &self.payload
    }
    pub fn to_bytes(&self) -> Result<Vec<u8>, String> {
        dm_wire::encode(FRAGMENT_VERSION, self)
    }
    pub fn from_bytes(bytes: &[u8]) -> Result<Self, String> {
        let record: Self = dm_wire::decode(FRAGMENT_VERSION, bytes, bytes.len())?;
        Ok(record)
    }
}
/// A caller-owned memo, optionally backed by validated disk records. No hidden
/// process cache or filesystem access exists in the preprocessor.
pub trait ExpansionMemo: Sync {
    fn input_admissions(&self) -> Option<&super::ExpansionInputs> {
        None
    }
    fn candidates(&self, key: u128) -> Vec<Arc<ExpansionRecord>>;
    fn insert(&self, record: Arc<ExpansionRecord>);
    /// Acceptance is determined by the consumer's complete current-context validation.
    fn visit_candidates(
        &self,
        key: u128,
        accept: &mut dyn FnMut(&Arc<ExpansionRecord>) -> bool,
    ) -> bool {
        self.candidates(key).iter().rev().any(accept)
    }
    fn visit_directive_candidates(
        &self,
        key: u128,
        accept: &mut dyn FnMut(&Arc<super::DirectiveRecord>) -> bool,
    ) -> bool {
        self.directive_candidates(key).iter().rev().any(accept)
    }
    fn visit_fragment_candidates(
        &self,
        key: u128,
        accept: &mut dyn FnMut(&Arc<FragmentRecord>) -> bool,
    ) -> bool {
        self.fragment_candidates(key).iter().rev().any(accept)
    }

    fn directive_candidates(&self, _key: u128) -> Vec<Arc<super::DirectiveRecord>> {
        Vec::new()
    }
    fn insert_directive(&self, _record: Arc<super::DirectiveRecord>) {}
    fn fragment_candidates(&self, _key: u128) -> Vec<Arc<FragmentRecord>> {
        Vec::new()
    }
    fn insert_fragment(&self, _record: Arc<FragmentRecord>) {}
}
/// Neutral, versioned compact parser payload. The parser owns validation.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct ParseFragment {
    schema: u32,
    #[serde(with = "span_wire")]
    span: Span,
    payload: Arc<[u8]>,
}
impl ParseFragment {
    pub fn schema(&self) -> u32 {
        self.schema
    }
    pub fn span(&self) -> Span {
        self.span
    }
    pub fn payload(&self) -> &[u8] {
        &self.payload
    }
}
/// Receipt issued by this expansion, with current joined-arena coordinates.
#[derive(Clone, Debug)]
pub struct RegionReceipt {
    pub(super) region: usize,
    pub(super) output: Span,
    pub(super) record: Arc<ExpansionRecord>,
}
impl RegionReceipt {
    pub fn region(&self) -> usize {
        self.region
    }
    pub fn output_span(&self) -> Span {
        self.output
    }
    pub fn record(&self) -> &Arc<ExpansionRecord> {
        &self.record
    }
}
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct MacroRead {
    pub segment: usize,
    pub name: Arc<str>,
    pub definition: Option<Arc<Macro>>,
}
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
struct Trace {
    name: String,
    #[serde(with = "span_wire")]
    invocation_span: Span,
    replacement_chain: Vec<String>,
}
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
struct Line {
    #[serde(with = "span_wire")]
    output: Span,
    input: usize,
    traces: Vec<Trace>,
}
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
struct Error {
    input: usize,
    kind: DiagnosticKind,
    message: String,
}
/// Private fields keep records issued from actual expansion; accessors support
/// analysis and storage adapters without exposing mutable reusable output.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct ExpansionRecord {
    key: u128,
    #[serde(with = "source_wire")]
    source: crate::SourceText,
    control: Arc<[u8]>,
    #[serde(with = "source_wire")]
    text: crate::SourceText,
    reads: Vec<MacroRead>,
    locations: Vec<(usize, bool, String)>,
    lines: Vec<Line>,
    diagnostics: Vec<Error>,
    #[serde(default)]
    fragments: Vec<ParseFragment>,
}
impl ExpansionRecord {
    /// Includes record Arc, owned capacities and all nested Arc backing storage.
    /// Duplicate shared allocations are conservatively charged per occurrence.
    pub fn retained_size_bytes(&self) -> usize {
        record::<Self>()
            .saturating_add(source_wire::retained_size(&self.source))
            .saturating_add(slice::<u8>(self.control.len()))
            .saturating_add(source_wire::retained_size(&self.text))
            .saturating_add(vector(&self.reads, |read| {
                slice::<u8>(read.name.len()).saturating_add(
                    read.definition
                        .as_ref()
                        .map_or(0, |value| shared_macro(value)),
                )
            }))
            .saturating_add(vector(&self.locations, |(_, _, name)| name.capacity()))
            .saturating_add(vector(&self.lines, |line| {
                vector(&line.traces, |trace| {
                    trace
                        .name
                        .capacity()
                        .saturating_add(vector(&trace.replacement_chain, String::capacity))
                })
            }))
            .saturating_add(vector(&self.diagnostics, |error| error.message.capacity()))
            .saturating_add(vector(&self.fragments, |fragment| {
                slice::<u8>(fragment.payload.len())
            }))
    }

    /// Same expansion authority; parser enrichment is not another macro variant.
    pub fn same_expansion(&self, other: &Self) -> bool {
        self.key == other.key
            && self.source == other.source
            && self.control == other.control
            && self.text == other.text
            && self.reads == other.reads
            && self.locations == other.locations
            && self.lines == other.lines
            && self.diagnostics == other.diagnostics
    }

    /// Parser sidecars are optional hints, independently validated by their consumer.
    pub fn fragment_count(&self) -> usize {
        self.fragments.len()
    }

    pub fn fragment(&self, schema: u32, span: Span) -> Option<&[u8]> {
        self.fragments
            .iter()
            .rev()
            .find(|fragment| fragment.schema == schema && fragment.span == span)
            .map(|fragment| fragment.payload())
    }
    pub fn with_fragment(&self, schema: u32, span: Span, payload: Arc<[u8]>) -> Option<Self> {
        self.text.get(span.range())?;
        let mut result = self.clone();
        result.append_fragment(schema, span, payload)?;
        Some(result)
    }
    /// Enrich an exclusively owned draft without cloning its expansion receipt.
    pub fn append_fragment(&mut self, schema: u32, span: Span, payload: Arc<[u8]>) -> Option<()> {
        self.text.get(span.range())?;
        self.fragments
            .retain(|fragment| fragment.schema != schema || fragment.span != span);
        self.fragments.push(ParseFragment {
            schema,
            span,
            payload,
        });
        Some(())
    }
    pub fn to_bytes(&self) -> Result<Vec<u8>, String> {
        dm_wire::encode(EXPANSION_VERSION, self)
    }
    pub fn from_bytes(bytes: &[u8]) -> Result<Self, String> {
        let record: Self = dm_wire::decode(EXPANSION_VERSION, bytes, bytes.len())?;
        if record.control.get(..4) != Some(EXPANSION_VERSION.to_le_bytes().as_slice()) {
            return Err("expansion record version mismatch".into());
        }
        if framed_key(&record.source, &record.control) != record.key {
            return Err("expansion record key mismatch".into());
        }
        if record.lines.iter().any(|line| {
            line.output.start > line.output.end
                || line.output.end > record.text.len()
                || !record.text.is_char_boundary(line.output.start)
                || !record.text.is_char_boundary(line.output.end)
        }) {
            return Err("expansion record output span invalid".into());
        }
        if record
            .fragments
            .iter()
            .any(|fragment| record.text.get(fragment.span.range()).is_none())
        {
            return Err("invalid parser fragment span".into());
        }
        Ok(record)
    }
    pub fn key(&self) -> u128 {
        self.key
    }
    pub fn version(&self) -> u32 {
        EXPANSION_VERSION
    }
    pub(super) fn location_reads(&self) -> &[(usize, bool, String)] {
        &self.locations
    }
    pub fn reads(&self) -> &[MacroRead] {
        &self.reads
    }
    pub fn text(&self) -> &str {
        &self.text
    }
}
type RecordedMacroReads = BTreeMap<(usize, String), Option<Arc<Macro>>>;
#[derive(Default)]
pub(super) struct Recorder {
    reads: RefCell<RecordedMacroReads>,
    locations: RefCell<BTreeSet<(usize, bool)>>,
}
pub(super) struct RecordingLookup<'a> {
    pub env: &'a MacroEnvironment,
    pub recorder: &'a Recorder,
    pub segment: usize,
    pub input: usize,
}
impl MacroLookup for RecordingLookup<'_> {
    fn get_key_value(&self, name: &str) -> Option<(&str, &Macro)> {
        self.recorder
            .reads
            .borrow_mut()
            .entry((self.segment, name.to_owned()))
            .or_insert_with(|| self.env.shared_definition(name));
        self.env.get_key_value(name)
    }
    fn location_read(&self, file: bool) {
        self.recorder
            .locations
            .borrow_mut()
            .insert((self.input, file));
    }
}
fn inputs(plan: &DirectivePlan, index: usize) -> Vec<(usize, &super::RegionLine)> {
    plan.regions[index]
        .segments
        .iter()
        .enumerate()
        .flat_map(|(segment, value)| value.lines.iter().map(move |line| (segment, line)))
        .collect()
}
fn framed_key(source: &str, control: &[u8]) -> u128 {
    let mut hash = Xxh3::new();
    hash.update(&(source.len() as u64).to_le_bytes());
    hash.update(source.as_bytes());
    hash.update(control);
    hash.digest128()
}
fn context(plan: &DirectivePlan, index: usize) -> Option<(crate::SourceText, Arc<[u8]>, u128)> {
    let region = &plan.regions[index];
    let path = &plan.occurrences[region.occurrence].path;
    let owner = plan.source_texts.get(path.as_ref())?;
    owner.get(region.source_span.range())?;
    let source = owner.view(region.source_span.range());
    let mut control = EXPANSION_VERSION.to_le_bytes().to_vec();
    for (segment, line) in plan.regions[index]
        .segments
        .iter()
        .enumerate()
        .flat_map(|(segment, value)| value.lines.iter().map(move |line| (segment, line)))
    {
        control.extend_from_slice(&(segment as u64).to_le_bytes());
        control.extend_from_slice(
            &(line
                .source_span
                .start
                .checked_sub(region.source_span.start)? as u64)
                .to_le_bytes(),
        );
        control.extend_from_slice(&(line.text.len() as u64).to_le_bytes());
        control.extend_from_slice(line.text.as_bytes());
    }
    let identity = framed_key(&source, &control);
    Some((source, control.into(), identity))
}
pub(super) fn expand(
    plan: &DirectivePlan,
    index: usize,
    memo: &dyn ExpansionMemo,
) -> super::expansion::RegionOutput {
    if let Some(record) = memo
        .input_admissions()
        .and_then(|inputs| inputs.lookup(plan, index))
    {
        return hydrate(plan, index, &inputs(plan, index), &record);
    }
    let Some((source, control, key)) = context(plan, index) else {
        return super::expansion::expand_region(plan, index, None);
    };
    let input = inputs(plan, index);
    let mut accepted = None;
    memo.visit_candidates(key, &mut |record| {
        if record.key != key || record.source != source || record.control != control {
            return false;
        }
        if record.reads.iter().any(|read| {
            plan.regions[index]
                .segments
                .get(read.segment)
                .is_none_or(|segment| {
                    segment.macros.shared_definition(&read.name) != read.definition
                })
        }) {
            return false;
        }
        if record.locations.iter().any(|(ordinal, file, expected)| {
            input.get(*ordinal).is_none_or(|(_, line)| {
                if *file {
                    plan.semantic_path(plan.regions[index].occurrence) != *expected
                } else {
                    line.source_line.to_string() != *expected
                }
            })
        }) {
            return false;
        }
        if record.lines.iter().any(|line| line.input >= input.len())
            || record
                .diagnostics
                .iter()
                .any(|error| error.input >= input.len())
        {
            return false;
        }
        if let Some(admissions) = memo.input_admissions() {
            admissions.insert(plan, index, Arc::clone(record));
        }
        accepted = Some(hydrate(plan, index, &input, record));
        true
    });
    if let Some(output) = accepted {
        return output;
    }
    let recorder = Recorder::default();
    let output = super::expansion::expand_region(plan, index, Some(&recorder));
    let ordinals: BTreeMap<_, _> = input
        .iter()
        .enumerate()
        .map(|(ordinal, (_, line))| {
            (
                (
                    line.source_line,
                    line.source_span.start,
                    line.source_span.end,
                ),
                ordinal,
            )
        })
        .collect();
    let lines = output
        .lines
        .iter()
        .map(|(span, line, source_span, traces)| {
            let ordinal = ordinals
                .get(&(line, source_span.start, source_span.end))
                .copied()?;
            Some(Line {
                output: span,
                input: ordinal,
                traces: traces
                    .iter()
                    .map(|trace| Trace {
                        name: trace.name.to_string(),
                        invocation_span: trace.invocation_span,
                        replacement_chain: trace
                            .replacement_chain
                            .iter()
                            .map(|name| name.to_string())
                            .collect(),
                    })
                    .collect(),
            })
        })
        .collect::<Option<Vec<_>>>();
    let Some(lines) = lines else {
        return output;
    };
    let mut diagnostics = Vec::new();
    for error in &output.diagnostics {
        let Some(ordinal) = input
            .iter()
            .position(|(_, line)| line.source_line == error.line)
        else {
            return output;
        };
        diagnostics.push(Error {
            input: ordinal,
            kind: error.kind,
            message: error.message.clone(),
        });
    }
    let locations = recorder
        .locations
        .into_inner()
        .into_iter()
        .map(|(ordinal, file)| {
            (
                ordinal,
                file,
                if file {
                    plan.semantic_path(plan.regions[index].occurrence)
                } else {
                    input[ordinal].1.source_line.to_string()
                },
            )
        })
        .collect();
    let reads = recorder
        .reads
        .into_inner()
        .into_iter()
        .map(|((segment, name), definition)| MacroRead {
            segment,
            name: Arc::from(name),
            definition,
        })
        .collect();
    let record = Arc::new(ExpansionRecord {
        key,
        source,
        control,
        text: output.text.clone(),
        reads,
        locations,
        lines,
        diagnostics,
        fragments: Vec::new(),
    });
    if let Some(admissions) = memo.input_admissions() {
        admissions.insert(plan, index, Arc::clone(&record));
    }
    memo.insert(Arc::clone(&record));
    let mut output = output;
    output.text = record.text.clone();
    output.receipt = Some(record);
    output
}
fn hydrate(
    plan: &DirectivePlan,
    index: usize,
    input: &[(usize, &super::RegionLine)],
    record: &Arc<ExpansionRecord>,
) -> super::expansion::RegionOutput {
    let region = &plan.regions[index];
    let path = plan.occurrences[region.occurrence].path.as_ref();
    let mut output = super::expansion::RegionOutput {
        text: record.text.clone(),
        receipt: Some(Arc::clone(record)),
        lines: Default::default(),
        diagnostics: Vec::new(),
    };
    let mut trace_arena = super::trace_arena::TraceArena::default();
    let mut lines =
        super::expansion::output_lines::OutputLineBuilder::with_capacity(record.lines.len());
    for line in &record.lines {
        let (segment, current) = input[line.input];
        let traces = line
            .traces
            .iter()
            .map(|trace| MacroExpansion {
                name: trace_arena.name(&trace.name),
                invocation_span: trace.invocation_span,
                replacement_chain: trace_arena.chain_strings(&trace.replacement_chain),
                definition: region.segments[segment]
                    .macros
                    .definition_origin(&trace.name)
                    .cloned(),
            })
            .collect();
        lines.push((
            line.output,
            current.source_line,
            current.source_span,
            trace_arena.freeze_expansions(traces),
        ));
    }
    output.lines = lines.finish();
    for error in &record.diagnostics {
        output.diagnostics.push(Diagnostic {
            path: path.clone(),
            line: input[error.input].1.source_line,
            kind: error.kind,
            message: error.message.clone(),
        });
    }
    output
}

mod span_wire {
    use dm_syntax::Span;
    use serde::{Deserialize, Deserializer, Serialize, Serializer};
    pub fn serialize<S: Serializer>(value: &Span, s: S) -> Result<S::Ok, S::Error> {
        [value.start, value.end].serialize(s)
    }
    pub fn deserialize<'de, D: Deserializer<'de>>(d: D) -> Result<Span, D::Error> {
        let [start, end] = <[usize; 2]>::deserialize(d)?;
        if start > end {
            return Err(serde::de::Error::custom("reversed span"));
        }
        Ok(Span::new(start, end))
    }
}

#[cfg(test)]
mod tests {
    use super::super::{
        expand_regions_text, expand_regions_text_with_memo, plan_regions, SourceProvider,
    };
    use super::*;
    #[test]
    fn streamed_region_memo_key_preserves_exact_previous_framing() {
        for length in [0, 1, 16, 127, 128, 239, 240, 241, 1024, 32768] {
            let source = "x".repeat(length);
            let control = "line\n\u{b5}\0".repeat(length / 7 + 1).into_bytes();
            let mut previous = (source.len() as u64).to_le_bytes().to_vec();
            previous.extend_from_slice(source.as_bytes());
            previous.extend_from_slice(&control);
            assert_eq!(
                framed_key(&source, &control),
                xxhash_rust::xxh3::xxh3_128(&previous)
            );
        }
    }

    use std::{
        path::{Path, PathBuf},
        sync::{
            atomic::{AtomicUsize, Ordering},
            Mutex,
        },
    };
    struct Memory(BTreeMap<PathBuf, String>);
    impl SourceProvider for Memory {
        fn read(&self, path: &Path) -> Result<String, String> {
            self.0.get(path).cloned().ok_or_else(|| "missing".into())
        }
    }
    #[derive(Default)]
    struct Memo {
        records: Mutex<BTreeMap<u128, Vec<Arc<ExpansionRecord>>>>,
        inserts: AtomicUsize,
    }
    impl ExpansionMemo for Memo {
        fn candidates(&self, key: u128) -> Vec<Arc<ExpansionRecord>> {
            self.records
                .lock()
                .unwrap()
                .get(&key)
                .cloned()
                .unwrap_or_default()
        }
        fn insert(&self, r: Arc<ExpansionRecord>) {
            self.inserts.fetch_add(1, Ordering::Relaxed);
            self.records
                .lock()
                .unwrap()
                .entry(r.key())
                .or_default()
                .push(r);
        }
    }
    #[test]
    fn fresh_and_retained_region_outputs_share_the_certified_text_backing() {
        let plan = plan("/proc/probe()\n    return 7\n", &[]);
        let memo = Memo::default();
        let fresh = expand(&plan, 0, &memo);
        let record = Arc::clone(fresh.receipt.as_ref().unwrap());
        let region = &plan.regions[0];
        let path = &plan.occurrences[region.occurrence].path;
        let source = plan.source_texts[path.as_ref()].view(region.source_span.range());
        assert!(record.source.same_view(&source));
        let decoded = ExpansionRecord::from_bytes(&record.to_bytes().unwrap()).unwrap();
        assert_eq!(decoded, *record);
        assert!(!decoded.source.same_view(&record.source));
        assert!(!decoded.text.same_view(&record.text));
        let disk_memo = Memo::default();
        disk_memo.insert(Arc::new(decoded));
        let disk_output = expand(&plan, 0, &disk_memo);
        assert_eq!(disk_output.text, fresh.text);
        assert_eq!(disk_memo.inserts.load(Ordering::Relaxed), 1);
        let reused = expand(&plan, 0, &memo);
        for output in [&fresh, &reused] {
            assert_eq!(output.text.as_str(), record.text());
            assert!(output.text.same_view(&record.text));
        }
        assert_eq!(fresh.lines.len(), reused.lines.len());
        for ((span, line, input, traces), (other_span, other_line, other_input, other_traces)) in
            fresh.lines.iter().zip(reused.lines.iter())
        {
            assert_eq!((span, line, input), (other_span, other_line, other_input));
            assert_eq!(traces.len(), other_traces.len());
            for (trace, other) in traces.iter().zip(other_traces.iter()) {
                assert_eq!(trace.name, other.name);
                assert_eq!(trace.invocation_span, other.invocation_span);
                assert_eq!(trace.replacement_chain, other.replacement_chain);
                let definition = |origin: &Option<super::super::DefinitionOrigin>| {
                    origin
                        .as_ref()
                        .map(|origin| (origin.path.clone(), origin.source_span, origin.source_line))
                };
                assert_eq!(definition(&trace.definition), definition(&other.definition));
            }
        }
        assert_eq!(fresh.diagnostics, reused.diagnostics);
    }
    fn plan(body: &str, defines: &[(&str, &str)]) -> DirectivePlan {
        let source = Memory(BTreeMap::from([(
            PathBuf::from("project.dme"),
            body.into(),
        )]));
        plan_regions(
            Path::new("project.dme"),
            &source,
            &defines
                .iter()
                .map(|(name, value)| (name.to_string(), value.to_string()))
                .collect(),
        )
    }
    #[test]
    fn empty_trace_sharing_preserves_each_authored_origin() {
        let memo = Memo::default();
        let plan = plan("var/a = 1\nvar/b = 2\n", &[]);
        let fresh = expand_regions_text(&plan, 1);
        let recorded = expand_regions_text_with_memo(&plan, 1, &memo);
        let hydrated = expand_regions_text_with_memo(&plan, 1, &memo);
        assert_eq!(
            format!("{:?}", fresh.origins),
            format!("{:?}", recorded.origins)
        );
        assert_eq!(
            format!("{:?}", fresh.origins),
            format!("{:?}", hydrated.origins)
        );
        for output in [&fresh, &hydrated] {
            assert_eq!(output.origins.len(), 2);
            let first = output.origins.get(0).unwrap();
            let second = output.origins.get(1).unwrap();
            assert!(first.macro_expansions.is_empty());
            assert!(Arc::ptr_eq(first.macro_expansions, second.macro_expansions));
            assert_ne!(first.source_span, second.source_span);
            assert_ne!(first.output_span, second.output_span);
            assert_ne!(first.origin.source_line, second.origin.source_line);
        }
    }
    #[test]
    fn fresh_and_hydrated_trace_text_matches_and_shares_per_region() {
        let memo = Memo::default();
        let plan = plan(
            "var/a = OUTER + OUTER\nvar/b = OUTER\n",
            &[("OUTER", "INNER"), ("INNER", "1")],
        );
        let fresh = expand_regions_text(&plan, 1);
        let recorded = expand_regions_text_with_memo(&plan, 1, &memo);
        let hydrated = expand_regions_text_with_memo(&plan, 1, &memo);
        assert_eq!(
            format!("{:?}", fresh.origins),
            format!("{:?}", recorded.origins)
        );
        assert_eq!(
            format!("{:?}", fresh.origins),
            format!("{:?}", hydrated.origins)
        );
        for output in [&fresh, &hydrated] {
            let traces = output.origins.get(0).unwrap().macro_expansions;
            assert_eq!(traces.len(), 4);
            assert!(Arc::ptr_eq(&traces[0].name, &traces[2].name));
            assert!(Arc::ptr_eq(
                &traces[1].replacement_chain,
                &traces[3].replacement_chain
            ));
            assert_ne!(traces[0].invocation_span, traces[2].invocation_span);
            assert!(Arc::ptr_eq(
                &traces[0].name,
                &output.origins.get(1).unwrap().macro_expansions[0].name
            ));
        }
    }
    #[test]
    fn expansion_memo_validates_positive_negative_and_unused_macro_reads() {
        let memo = Memo::default();
        let first = plan("var/a = USED + ABSENT\n", &[("USED", "1"), ("UNUSED", "2")]);
        let cold = expand_regions_text(&first, 1);
        let one = expand_regions_text_with_memo(&first, 2, &memo);
        assert_eq!(one.text, cold.text);
        assert_eq!(format!("{:?}", one.origins), format!("{:?}", cold.origins));
        let n = memo.inserts.load(Ordering::Relaxed);
        let unused = plan("var/a = USED + ABSENT\n", &[("USED", "1"), ("UNUSED", "3")]);
        assert_eq!(
            expand_regions_text_with_memo(&unused, 1, &memo).text,
            cold.text
        );
        assert_eq!(memo.inserts.load(Ordering::Relaxed), n);
        let negative = plan("var/a = USED + ABSENT\n", &[("USED", "1"), ("ABSENT", "4")]);
        assert_eq!(
            expand_regions_text_with_memo(&negative, 2, &memo).text,
            expand_regions_text(&negative, 1).text
        );
        assert!(memo.inserts.load(Ordering::Relaxed) > n);
        let changed = plan("var/a = USED + ABSENT\n", &[("USED", "9")]);
        assert_eq!(
            expand_regions_text_with_memo(&changed, 2, &memo).text,
            expand_regions_text(&changed, 1).text
        );
    }
    #[test]
    fn expansion_memo_replays_current_origins_and_serialized_records() {
        let memo = Memo::default();
        let first = plan("#define VALUE 7\nvar/a = VALUE\n", &[]);
        let cold = expand_regions_text(&first, 1);
        expand_regions_text_with_memo(&first, 1, &memo);
        {
            let mut records = memo.records.lock().unwrap();
            for bucket in records.values_mut() {
                for record in bucket {
                    *record =
                        Arc::new(ExpansionRecord::from_bytes(&record.to_bytes().unwrap()).unwrap());
                }
            }
        }
        let hit = expand_regions_text_with_memo(&first, 2, &memo);
        assert_eq!(hit.text, cold.text);
        assert_eq!(format!("{:?}", hit.origins), format!("{:?}", cold.origins));
        let moved = plan("\n#define VALUE 7\nvar/a = VALUE\n", &[]);
        let moved_cold = expand_regions_text(&moved, 1);
        let hit = expand_regions_text_with_memo(&moved, 2, &memo);
        assert_eq!(hit.text, moved_cold.text);
        assert_eq!(
            format!("{:?}", hit.origins),
            format!("{:?}", moved_cold.origins)
        );
        let mut records = memo.records.lock().unwrap();
        let record = records.values_mut().next().unwrap().first().unwrap();
        assert!(
            record.to_bytes().unwrap().len() < serde_json::to_vec(record.as_ref()).unwrap().len()
        );
        let mut wrong_key = record.as_ref().clone();
        wrong_key.key = 0;
        assert!(ExpansionRecord::from_bytes(&wrong_key.to_bytes().unwrap()).is_err());
        let mut corrupt = record.to_bytes().unwrap();
        let end = corrupt.len() - 1;
        corrupt[end] ^= 1;
        assert!(ExpansionRecord::from_bytes(&corrupt).is_err());
    }
    #[test]
    fn expansion_memo_preserves_directive_effects_and_executed_location_reads() {
        let memo = Memo::default();
        for body in [
            "#if ENABLED\n#define VALUE 8\n#else\n#define VALUE 9\n#endif\nvar/a = VALUE\n",
            "var/a = __LINE__\nvar/b = __FILE__\n",
        ] {
            for defines in [vec![("ENABLED", "1")], vec![("ENABLED", "0")]] {
                let plan = plan(body, &defines);
                let cold = expand_regions_text(&plan, 1);
                let hit = expand_regions_text_with_memo(&plan, 2, &memo);
                assert_eq!(hit.text, cold.text);
                assert_eq!(format!("{:?}", hit.origins), format!("{:?}", cold.origins));
                assert_eq!(hit.diagnostics, cold.diagnostics);
            }
        }
    }
}

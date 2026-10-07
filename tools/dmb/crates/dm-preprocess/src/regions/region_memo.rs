//! Expansion reuse after a fresh, ordered directive plan. Conditional/include
//! interpretation and effects remain authoritative in that plan; this memo never
//! speculates a different directive state or parses a region as a standalone AST.
use super::{DirectivePlan, MacroEnvironment, MacroExpansion};
use crate::{Diagnostic, DiagnosticKind, Macro, MacroLookup};
use dm_syntax::Span;
use serde::{Deserialize, Serialize};
use std::{
    cell::RefCell,
    collections::{BTreeMap, BTreeSet},
    sync::Arc,
};
use xxhash_rust::xxh3::Xxh3;
pub const EXPANSION_VERSION: u32 = 3;
/// A caller-owned memo, optionally backed by validated disk records. No hidden
/// process cache or filesystem access exists in the preprocessor.
pub trait ExpansionMemo: Sync {
    fn candidates(&self, key: u128) -> Vec<Arc<ExpansionRecord>>;
    fn insert(&self, record: Arc<ExpansionRecord>);
    fn directive_candidates(&self, _key: u128) -> Vec<Arc<super::DirectiveRecord>> {
        Vec::new()
    }
    fn insert_directive(&self, _record: Arc<super::DirectiveRecord>) {}
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
    source: Arc<str>,
    control: Arc<[u8]>,
    text: Arc<str>,
    reads: Vec<MacroRead>,
    locations: Vec<(usize, bool, String)>,
    lines: Vec<Line>,
    diagnostics: Vec<Error>,
    #[serde(default)]
    fragments: Vec<ParseFragment>,
}
impl ExpansionRecord {
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

    pub fn fragment(&self, schema: u32, span: Span) -> Option<&[u8]> {
        self.fragments
            .iter()
            .rev()
            .find(|fragment| fragment.schema == schema && fragment.span == span)
            .map(|fragment| fragment.payload())
    }
    pub fn with_fragment(&self, schema: u32, span: Span, payload: Arc<[u8]>) -> Option<Self> {
        self.text.get(span.range())?;
        let total = self
            .fragments
            .iter()
            .filter(|fragment| fragment.schema != schema || fragment.span != span)
            .try_fold(payload.len(), |total, fragment| {
                total.checked_add(fragment.payload.len())
            })?;
        if payload.len() > 4 * 1024 * 1024 || self.fragments.len() >= 256 || total > 8 * 1024 * 1024
        {
            return None;
        }
        let mut result = self.clone();
        result
            .fragments
            .retain(|fragment| fragment.schema != schema || fragment.span != span);
        result.fragments.push(ParseFragment {
            schema,
            span,
            payload,
        });
        Some(result)
    }
    pub fn to_bytes(&self) -> Result<Vec<u8>, String> {
        dm_wire::encode(EXPANSION_VERSION, self)
    }
    pub fn from_bytes(bytes: &[u8]) -> Result<Self, String> {
        let record: Self = dm_wire::decode(EXPANSION_VERSION, bytes, 16 * 1024 * 1024)?;
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
        if record.fragments.len() > 256
            || record
                .fragments
                .iter()
                .try_fold(0usize, |total, fragment| {
                    total.checked_add(fragment.payload.len())
                })
                .is_none_or(|total| total > 8 * 1024 * 1024)
            || record.fragments.iter().any(|fragment| {
                fragment.payload.len() > 4 * 1024 * 1024
                    || record.text.get(fragment.span.range()).is_none()
            })
        {
            return Err("invalid parser fragment bounds".into());
        }
        Ok(record)
    }
    pub fn key(&self) -> u128 {
        self.key
    }
    pub fn version(&self) -> u32 {
        EXPANSION_VERSION
    }
    pub fn reads(&self) -> &[MacroRead] {
        &self.reads
    }
    pub fn text(&self) -> &str {
        &self.text
    }
}
#[derive(Default)]
pub(super) struct Recorder {
    reads: RefCell<BTreeMap<(usize, String), Option<Arc<Macro>>>>,
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
fn context(plan: &DirectivePlan, index: usize) -> Option<(&str, Arc<[u8]>, u128)> {
    let region = &plan.regions[index];
    let path = &plan.occurrences[region.occurrence].path;
    let source = plan
        .source_texts
        .get(path.as_ref())?
        .get(region.source_span.start..region.source_span.end)?;
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
    let identity = framed_key(source, &control);
    Some((source, control.into(), identity))
}
pub(super) fn expand(
    plan: &DirectivePlan,
    index: usize,
    memo: &dyn ExpansionMemo,
) -> super::expansion::RegionOutput {
    let Some((source, control, key)) = context(plan, index) else {
        return super::expansion::expand_region(plan, index, None);
    };
    let input = inputs(plan, index);
    for record in memo.candidates(key).into_iter().rev() {
        if record.key != key || record.source.as_ref() != source || record.control != control {
            continue;
        }
        if record.reads.iter().any(|read| {
            plan.regions[index]
                .segments
                .get(read.segment)
                .is_none_or(|segment| {
                    segment.macros.shared_definition(&read.name) != read.definition
                })
        }) {
            continue;
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
            continue;
        }
        if record.lines.iter().any(|line| line.input >= input.len())
            || record
                .diagnostics
                .iter()
                .any(|error| error.input >= input.len())
        {
            continue;
        }
        return hydrate(plan, index, &input, &record);
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
    let mut lines = Vec::new();
    for (span, line, source_span, traces) in &output.lines {
        let Some(ordinal) = ordinals
            .get(&(*line, source_span.start, source_span.end))
            .copied()
        else {
            return output;
        };
        lines.push(Line {
            output: *span,
            input: ordinal,
            traces: traces
                .iter()
                .map(|trace| Trace {
                    name: trace.name.clone(),
                    invocation_span: trace.invocation_span,
                    replacement_chain: trace.replacement_chain.clone(),
                })
                .collect(),
        });
    }
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
        source: Arc::from(source),
        control,
        text: Arc::from(output.text.as_str()),
        reads,
        locations,
        lines,
        diagnostics,
        fragments: Vec::new(),
    });
    memo.insert(Arc::clone(&record));
    let mut output = output;
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
        text: record.text.to_string(),
        receipt: Some(Arc::clone(record)),
        ..Default::default()
    };
    for line in &record.lines {
        let (segment, current) = input[line.input];
        let traces = line
            .traces
            .iter()
            .map(|trace| MacroExpansion {
                name: trace.name.clone(),
                invocation_span: trace.invocation_span,
                replacement_chain: trace.replacement_chain.clone(),
                definition: region.segments[segment]
                    .macros
                    .definition_origin(&trace.name)
                    .cloned(),
            })
            .collect();
        output.lines.push((
            line.output,
            current.source_line,
            current.source_span,
            Arc::new(traces),
        ));
    }
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

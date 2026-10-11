//! Ordered directive interval receipts. Includes remain fresh recursion barriers.
use super::region_memo::retained_size::{macro_heap, record, shared_macro, slice, vector};
use super::{prepared_source::PreparedLines, MacroEnvironment};
use crate::{Conditional, DiagnosticKind, Macro, MacroLookup};
use serde::{Deserialize, Serialize};
use std::{
    cell::RefCell,
    collections::{BTreeMap, BTreeSet},
    sync::Arc,
};
use xxhash_rust::xxh3::Xxh3;
pub const DIRECTIVE_VERSION: u32 = 5;
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub(super) enum Action {
    Text(usize),
    Freeze,
    Define {
        input: usize,
        name: String,
        definition: Macro,
    },
    Undef {
        input: usize,
        name: String,
    },
    Error {
        input: usize,
        kind: DiagnosticKind,
        message: String,
    },
    Multiple,
    RecoveryDirective {
        input: usize,
    },
}
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
struct Read {
    name: String,
    present: bool,
    meaning: bool,
    definition: Option<Arc<Macro>>,
}
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct DirectiveRecord {
    key: u128,
    source: Arc<str>,
    control: Arc<[u8]>,
    incoming: Vec<Conditional>,
    outgoing: Vec<Conditional>,
    reads: Vec<Read>,
    file_dirs: Option<(Vec<std::path::PathBuf>, Vec<Macro>)>,
    actions: Vec<Action>,
    inputs: usize,
}
impl DirectiveRecord {
    /// Includes record Arc, owned capacities and every nested shared allocation;
    /// duplicate Arc identities are conservatively charged per occurrence.
    pub fn retained_size_bytes(&self) -> usize {
        record::<Self>()
            .saturating_add(slice::<u8>(self.source.len()))
            .saturating_add(slice::<u8>(self.control.len()))
            .saturating_add(vector(&self.incoming, |_| 0))
            .saturating_add(vector(&self.outgoing, |_| 0))
            .saturating_add(vector(&self.reads, |read| {
                read.name.capacity().saturating_add(
                    read.definition
                        .as_ref()
                        .map_or(0, |value| shared_macro(value)),
                )
            }))
            .saturating_add(self.file_dirs.as_ref().map_or(0, |(paths, values)| {
                vector(paths, std::path::PathBuf::capacity)
                    .saturating_add(vector(values, macro_heap))
            }))
            .saturating_add(vector(&self.actions, |action| match action {
                Action::Define {
                    name, definition, ..
                } => name.capacity().saturating_add(macro_heap(definition)),
                Action::Undef { name, .. } => name.capacity(),
                Action::Error { message, .. } => message.capacity(),
                Action::Text(_)
                | Action::Freeze
                | Action::Multiple
                | Action::RecoveryDirective { .. } => 0,
            }))
    }

    pub fn key(&self) -> u128 {
        self.key
    }
    pub fn version(&self) -> u32 {
        DIRECTIVE_VERSION
    }
    pub fn same_plan(&self, other: &Self) -> bool {
        self == other
    }
    pub fn to_bytes(&self) -> Result<Vec<u8>, String> {
        dm_wire::encode(DIRECTIVE_VERSION, self)
    }
    pub fn from_bytes(bytes: &[u8]) -> Result<Self, String> {
        let value: Self = dm_wire::decode(DIRECTIVE_VERSION, bytes, bytes.len())?;
        if value.control.get(..4) != Some(DIRECTIVE_VERSION.to_le_bytes().as_slice())
            || key(&value.source, &value.control) != value.key
            || value.actions.iter().any(|action| match action {
                Action::Text(input)
                | Action::Define { input, .. }
                | Action::Undef { input, .. }
                | Action::Error { input, .. }
                | Action::RecoveryDirective { input } => *input >= value.inputs,
                Action::Freeze | Action::Multiple => false,
            })
        {
            return Err("invalid directive interval receipt".into());
        }
        Ok(value)
    }
    pub(super) fn matches(
        &self,
        source: &str,
        control: &[u8],
        inputs: usize,
        environment: &MacroEnvironment,
        conditionals: &[Conditional],
        file_dirs: (&[std::path::PathBuf], &[Macro]),
    ) -> bool {
        self.inputs == inputs
            && self.source.as_ref() == source
            && self.control.as_ref() == control
            && self.incoming == conditionals
            && self.reads.iter().all(|read| {
                let current = environment.shared_definition(&read.name);
                if read.meaning {
                    current == read.definition
                } else {
                    current.is_some() == read.present
                }
            })
            && self
                .file_dirs
                .as_ref()
                .is_none_or(|(paths, values)| paths == file_dirs.0 && values == file_dirs.1)
    }
    pub(super) fn actions(&self) -> &[Action] {
        &self.actions
    }
    pub(super) fn outgoing(&self) -> &[Conditional] {
        &self.outgoing
    }
}
fn key(source: &str, control: &[u8]) -> u128 {
    let mut hash = Xxh3::new();
    hash.update(&(source.len() as u64).to_le_bytes());
    hash.update(source.as_bytes());
    hash.update(control);
    hash.digest128()
}
pub(super) fn context<'a>(
    original: &'a str,
    lines: PreparedLines<'_>,
) -> Option<(&'a str, Arc<[u8]>, u128)> {
    let first = lines.first()?;
    let end = lines.last()?.source_span.end;
    let source = original.get(first.source_span.start..end)?;
    let mut control = DIRECTIVE_VERSION.to_le_bytes().to_vec();
    for line in lines.iter() {
        for number in [
            line.source_span.start - first.source_span.start,
            line.source_span.end - first.source_span.start,
            line.source_line - first.source_line,
            line.source_lines,
            line.text.len(),
        ] {
            control.extend_from_slice(&(number as u64).to_le_bytes());
        }
        control.extend_from_slice(line.text.as_bytes());
    }
    let identity = key(source, &control);
    Some((source, control.into(), identity))
}
pub(super) struct Recording {
    pub start: usize,
    pub end: usize,
    pub current: usize,
    pub actions: Vec<Action>,
    pub local: BTreeSet<String>,
    reads: RefCell<BTreeMap<String, Read>>,
    source: Arc<str>,
    control: Arc<[u8]>,
    key: u128,
    incoming: Vec<Conditional>,
    file_dirs: Option<(Vec<std::path::PathBuf>, Vec<Macro>)>,
    entry_dirs: (Vec<std::path::PathBuf>, Vec<Macro>),
}
impl Recording {
    pub fn new(
        start: usize,
        end: usize,
        context: (&str, Arc<[u8]>, u128),
        conditionals: &[Conditional],
        dirs: &[std::path::PathBuf],
        definitions: &[Macro],
    ) -> Self {
        Self {
            start,
            end,
            current: 0,
            actions: Vec::new(),
            local: BTreeSet::new(),
            reads: RefCell::new(BTreeMap::new()),
            source: Arc::from(context.0),
            control: context.1,
            key: context.2,
            incoming: conditionals.to_vec(),
            file_dirs: None,
            entry_dirs: (dirs.to_vec(), definitions.to_vec()),
        }
    }
    pub fn directory_read(&mut self) {
        self.file_dirs = Some(self.entry_dirs.clone());
    }
    pub fn finish(self, outgoing: &[Conditional]) -> DirectiveRecord {
        DirectiveRecord {
            key: self.key,
            source: self.source,
            control: self.control,
            incoming: self.incoming,
            outgoing: outgoing.to_vec(),
            reads: self.reads.into_inner().into_values().collect(),
            file_dirs: self.file_dirs,
            actions: self.actions,
            inputs: self.end - self.start,
        }
    }
}
pub(super) struct Lookup<'a> {
    pub environment: &'a MacroEnvironment,
    pub recording: &'a Recording,
}
impl Lookup<'_> {
    fn record(&self, name: &str, meaning: bool) {
        if self.recording.local.contains(name) {
            return;
        }
        let definition = self.environment.shared_definition(name);
        let mut reads = self.recording.reads.borrow_mut();
        let old = reads.get(name);
        if old.is_some_and(|old| old.meaning || !meaning) {
            return;
        }
        reads.insert(
            name.into(),
            Read {
                name: name.into(),
                present: definition.is_some(),
                meaning,
                definition: meaning.then_some(definition).flatten(),
            },
        );
    }
}
impl MacroLookup for Lookup<'_> {
    fn get_key_value(&self, name: &str) -> Option<(&str, &Macro)> {
        self.record(name, true);
        self.environment.get_key_value(name)
    }
    fn contains_key(&self, name: &str) -> bool {
        self.record(name, false);
        self.environment.get(name).is_some()
    }
}

#[cfg(test)]
mod tests {
    use super::super::{
        expand_regions_text, plan_regions, plan_regions_with_memo, DirectivePlan, ExpansionMemo,
        ExpansionRecord, SourceProvider,
    };
    use super::*;
    #[test]
    fn retained_directive_records_charge_reserved_nested_capacities() {
        let mut value = DirectiveRecord {
            key: 0,
            source: Arc::from(""),
            control: Arc::from([]),
            incoming: Vec::new(),
            outgoing: Vec::new(),
            reads: Vec::new(),
            file_dirs: None,
            actions: Vec::new(),
            inputs: 0,
        };
        let before = value.retained_size_bytes();
        value.actions.reserve_exact(3);
        assert_eq!(
            value.retained_size_bytes() - before,
            value.actions.capacity() * std::mem::size_of::<Action>()
        );
        let name = String::with_capacity(101);
        let definition = Macro {
            parameters: Some(Vec::with_capacity(11)),
            replacement: String::with_capacity(201),
            variadic: false,
        };
        let extra = name.capacity() + macro_heap(&definition);
        let before = value.retained_size_bytes();
        value.actions.push(Action::Define {
            input: 0,
            name,
            definition,
        });
        assert_eq!(value.retained_size_bytes() - before, extra);
    }

    #[test]
    fn streamed_directive_memo_key_preserves_exact_previous_framing() {
        for length in [0, 1, 16, 127, 128, 239, 240, 241, 1024, 32768] {
            let source = "x".repeat(length);
            let control = "line\n\u{b5}\0".repeat(length / 7 + 1).into_bytes();
            let mut previous = (source.len() as u64).to_le_bytes().to_vec();
            previous.extend_from_slice(source.as_bytes());
            previous.extend_from_slice(&control);
            assert_eq!(
                key(&source, &control),
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
        records: Mutex<BTreeMap<u128, Vec<Arc<DirectiveRecord>>>>,
        inserts: AtomicUsize,
    }
    impl ExpansionMemo for Memo {
        fn candidates(&self, _: u128) -> Vec<Arc<ExpansionRecord>> {
            Vec::new()
        }
        fn insert(&self, _: Arc<ExpansionRecord>) {}
        fn directive_candidates(&self, key: u128) -> Vec<Arc<DirectiveRecord>> {
            self.records
                .lock()
                .unwrap()
                .get(&key)
                .cloned()
                .unwrap_or_default()
        }
        fn insert_directive(&self, value: Arc<DirectiveRecord>) {
            self.inserts.fetch_add(1, Ordering::Relaxed);
            self.records
                .lock()
                .unwrap()
                .entry(value.key())
                .or_default()
                .push(value);
        }
    }
    fn source(files: &[(&str, &str)]) -> Memory {
        Memory(
            files
                .iter()
                .map(|(path, text)| (PathBuf::from(path), text.to_string()))
                .collect(),
        )
    }
    fn equivalent(cold: &DirectivePlan, reused: &DirectivePlan) {
        assert_eq!(cold.final_macros, reused.final_macros);
        assert_eq!(cold.file_dirs, reused.file_dirs);
        assert_eq!(cold.diagnostics, reused.diagnostics);
        assert_eq!(cold.diagnostic_ordinals, reused.diagnostic_ordinals);
        assert_eq!(
            format!("{:?}", cold.occurrences),
            format!("{:?}", reused.occurrences)
        );
        assert_eq!(
            format!("{:?}", cold.regions),
            format!("{:?}", reused.regions)
        );
        let first = expand_regions_text(cold, 1);
        let second = expand_regions_text(reused, 2);
        assert_eq!(first.text, second.text);
        assert_eq!(
            format!("{:?}", first.origins),
            format!("{:?}", second.origins)
        );
        assert_eq!(first.diagnostics, second.diagnostics);
    }
    #[test]
    fn completed_include_recovery_events_replay_exact_current_occurrences() {
        for manifest in [
            "#include \"body.dm\"\n#define AFTER 1\n",
            "#include \"body.dm\"\n#if 0\n/datum/skipped\n#endif\n",
            "#include \"body.dm\"\n#include \"body.dm\"\n",
            "#include \"body.dm\"",
        ] {
            let files = source(&[("project.dme", manifest), ("body.dm", "/datum/probe\n")]);
            let memo = Memo::default();
            let cold =
                plan_regions_with_memo(Path::new("project.dme"), &files, &BTreeMap::new(), &memo);
            let count = memo.inserts.load(Ordering::Relaxed);
            let reused =
                plan_regions_with_memo(Path::new("project.dme"), &files, &BTreeMap::new(), &memo);
            equivalent(&cold, &reused);
            assert_eq!(memo.inserts.load(Ordering::Relaxed), count);
            for (a, b) in cold.occurrences.iter().zip(&reused.occurrences) {
                assert_eq!(a.eof_cursor_line(), b.eof_cursor_line());
                assert_eq!(a.eof_cursor_encounter(), b.eof_cursor_encounter());
                assert_eq!(
                    a.return_cursor().map(|c| (
                        c.parent_occurrence(),
                        c.decoded_offset(),
                        c.directive_anchor_line(),
                        c.encounter_ordinal()
                    )),
                    b.return_cursor().map(|c| (
                        c.parent_occurrence(),
                        c.decoded_offset(),
                        c.directive_anchor_line(),
                        c.encounter_ordinal()
                    ))
                );
            }
            assert_eq!(
                cold.occurrences[0].eof_cursor_encounter(),
                Some(cold.items.len())
            );
            for included in cold.occurrences.iter().skip(1) {
                let returned = included.return_cursor().unwrap();
                assert!(returned
                    .encounter_ordinal()
                    .is_some_and(|ordinal| ordinal <= cold.items.len()));
            }
            assert_eq!(
                cold.occurrences[0].eof_cursor_line(),
                Some(manifest.lines().count() + 1)
            );
            let record = memo
                .records
                .lock()
                .unwrap()
                .values()
                .flatten()
                .next()
                .unwrap()
                .clone();
            let bytes = record.to_bytes().unwrap();
            assert!(DirectiveRecord::from_bytes(&bytes).is_ok());
            // Prior receipts did not issue ordered return/EOF cursor events.
            let old = dm_wire::encode(4, record.as_ref()).unwrap();
            assert!(DirectiveRecord::from_bytes(&old).is_err());
        }
    }

    #[test]
    fn multiple_pragma_branch_toggle_replays_only_exact_current_conditions() {
        let files = source(&[
            (
                "project.dme",
                "#include \"body.dm\"\n#include \"body.dm\"\n",
            ),
            (
                "body.dm",
                "#if ENABLE_MULTIPLE\n#pragma multiple\n#endif\n/datum/repeated\n",
            ),
        ]);
        let memo = Memo::default();
        for (enabled, repeats) in [("0", false), ("1", true), ("0", false), ("1", true)] {
            let defines = BTreeMap::from([("ENABLE_MULTIPLE".into(), enabled.into())]);
            let fresh = plan_regions(Path::new("project.dme"), &files, &defines);
            let reused = plan_regions_with_memo(Path::new("project.dme"), &files, &defines, &memo);
            equivalent(&fresh, &reused);
            assert_eq!(reused.occurrences[2].suppressed, !repeats);
            assert_eq!(
                expand_regions_text(&reused, 1).text.as_ref(),
                if repeats {
                    "/datum/repeated\n/datum/repeated\n"
                } else {
                    "/datum/repeated\n"
                }
            );
        }
    }
    #[test]
    fn multiple_pragma_is_replayed_from_disk_receipt_before_repeated_include() {
        let files = source(&[
            ("project.dme", "#define PACK station\n#include \"body.dm\"\n#undef PACK\n#define PACK sif\n#include \"body.dm\"\n"),
            ("body.dm", "#pragma multiple\n/datum/turfpack/PACK\n"),
        ]);
        let memo = Memo::default();
        let defines = BTreeMap::new();
        let cold = plan_regions(Path::new("project.dme"), &files, &defines);
        plan_regions_with_memo(Path::new("project.dme"), &files, &defines, &memo);
        for records in memo.records.lock().unwrap().values_mut() {
            for record in records {
                *record =
                    Arc::new(DirectiveRecord::from_bytes(&record.to_bytes().unwrap()).unwrap());
            }
        }
        let count = memo.inserts.load(Ordering::Relaxed);
        let reused = plan_regions_with_memo(Path::new("project.dme"), &files, &defines, &memo);
        equivalent(&cold, &reused);
        assert!(!reused.occurrences[2].suppressed);
        assert_eq!(
            expand_regions_text(&reused, 1).text.as_ref(),
            "/datum/turfpack/station\n/datum/turfpack/sif\n"
        );
        assert_eq!(memo.inserts.load(Ordering::Relaxed), count);
    }
    #[test]
    fn directive_interval_replay_preserves_include_effects_cross_file_stack_and_diagnostics() {
        let files=source(&[("project.dme","#if ENABLED\n#define LOCAL 7\n#include \"child.dm\"\nvar/after = LOCAL + CHILD\n#error authored message\n#include \"child.dm\"\n"),("child.dm","#endif\n#define CHILD 8\nvar/child = LOCAL\n")]);
        let memo = Memo::default();
        let defines = BTreeMap::from([("ENABLED".into(), "1".into())]);
        let cold = plan_regions(Path::new("project.dme"), &files, &defines);
        let first = plan_regions_with_memo(Path::new("project.dme"), &files, &defines, &memo);
        equivalent(&cold, &first);
        let n = memo.inserts.load(Ordering::Relaxed);
        let hit = plan_regions_with_memo(Path::new("project.dme"), &files, &defines, &memo);
        equivalent(&cold, &hit);
        assert_eq!(memo.inserts.load(Ordering::Relaxed), n);
        let changed = BTreeMap::from([("ENABLED".into(), "0".into())]);
        equivalent(
            &plan_regions(Path::new("project.dme"), &files, &changed),
            &plan_regions_with_memo(Path::new("project.dme"), &files, &changed, &memo),
        );
    }
    #[test]
    fn directive_reads_distinguish_presence_meaning_local_effects_and_negative_absence() {
        let files=source(&[("project.dme","#ifdef PRESENT\n#define LOCAL 5\n#endif\n#if defined(ABSENT)\n#error negative changed\n#endif\n#if VALUE == 3\nvar/yes = LOCAL\n#endif\n#undef VALUE\n#define VALUE 4\n#if VALUE == 4\nvar/local = VALUE\n#endif\n")]);
        let memo = Memo::default();
        let defines = BTreeMap::from([
            ("PRESENT".into(), "1".into()),
            ("VALUE".into(), "3".into()),
            ("UNREAD".into(), "1".into()),
        ]);
        plan_regions_with_memo(Path::new("project.dme"), &files, &defines, &memo);
        let n = memo.inserts.load(Ordering::Relaxed);
        let mut unread = defines.clone();
        unread.insert("PRESENT".into(), "9".into());
        unread.insert("UNREAD".into(), "2".into());
        let hit = plan_regions_with_memo(Path::new("project.dme"), &files, &unread, &memo);
        equivalent(
            &plan_regions(Path::new("project.dme"), &files, &unread),
            &hit,
        );
        assert_eq!(memo.inserts.load(Ordering::Relaxed), n);
        unread.insert("ABSENT".into(), "1".into());
        let changed = plan_regions_with_memo(Path::new("project.dme"), &files, &unread, &memo);
        equivalent(
            &plan_regions(Path::new("project.dme"), &files, &unread),
            &changed,
        );
        assert!(memo.inserts.load(Ordering::Relaxed) > n);
    }
    #[test]
    fn directive_disk_roundtrip_rebinds_origins_and_validates_file_dir_stack() {
        let files=source(&[("project.dme","#define FILE_DIR \"local\"\n#undef FILE_DIR\n#if defined(FILE_DIR)\nvar/dir = FILE_DIR\n#endif\n#define LOCAL 3\nvar/a = LOCAL\n")]);
        let memo = Memo::default();
        let defines = BTreeMap::from([("FILE_DIR".into(), "\"entry\"".into())]);
        let first = plan_regions_with_memo(Path::new("project.dme"), &files, &defines, &memo);
        {
            let mut records = memo.records.lock().unwrap();
            for bucket in records.values_mut() {
                for value in bucket {
                    *value =
                        Arc::new(DirectiveRecord::from_bytes(&value.to_bytes().unwrap()).unwrap());
                }
            }
        }
        let hit = plan_regions_with_memo(Path::new("project.dme"), &files, &defines, &memo);
        equivalent(&first, &hit);
        let changed = BTreeMap::from([("FILE_DIR".into(), "\"changed\"".into())]);
        equivalent(
            &plan_regions(Path::new("project.dme"), &files, &changed),
            &plan_regions_with_memo(Path::new("project.dme"), &files, &changed, &memo),
        );
    }
}

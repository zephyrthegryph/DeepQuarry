//! Incremental link and composition on the general path (doc/incremental_core.md, step 6).
//!
//! The link and composition stages are one query over the program's link inputs. When the
//! declaration side of those inputs is unchanged, the retained output image is the answer for
//! every unit whose code is unchanged, and only the units whose code changed are relinked against
//! the retained link tables and their code rows rewritten in the retained image; the image is
//! re-encoded section by section (`ListRowImage::splice`), never recomposed. The general path
//! (`crate::cold`) asks this module after startup and ABI preparation, before the initializer
//! stage: a request whose declaration inputs differ, or whose changed units change their link
//! footprint, composes the whole program.
//!
//! The declaration side is unchanged when, against the retained output's own build:
//! 1. every answer is the same: the answer table has the version it had when that build
//!    published (`QueryDb::answers_version`: tree, answer world, resource searches);
//! 2. the program text outside procedure bodies is the same, blank lines aside (`text_key`);
//! 3. no non-text input and not the resource archive changed;
//! 4. the bodies are the same roster (same count, same file per position).
//!
//! Positions are inputs of their own: the source line of every expanded line outside the bodies,
//! and inside bodies whose text is unchanged, is paired between the two builds (`LineMap`), and
//! the retained initializer code and declaration warnings are moved to the new lines. Bodies whose
//! text or position changed are relowered; each must keep its link footprint (frame, ABI,
//! features, inventory, strings aside, debug paths, instances, helpers, required types, no
//! modified instances), and none may be the first root procedure (its literals register strings
//! with the declarations). New string literals are appended to the retained string table.
use crate::initializer_policy::warnings::InitializerWarning;
use crate::lowering::UnitIdentity;
use std::collections::{BTreeMap, HashMap};
use std::sync::Arc;
use xxhash_rust::xxh3::Xxh3;

/// At most this many relowered bodies are spliced; more compose the whole program.
const SPLICE_LIMIT: usize = 4096;

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct BodyShape {
    /// Text, file and position of the body (positions included: a moved body
    /// relinks with new debug lines).
    pub(crate) digest: u128,
    /// Expanded text only: a body whose text is unchanged merely moved.
    pub(crate) text: u128,
    /// Declares a proc-static or global var: startup facts depend on it.
    pub(crate) guarded: bool,
    pub(crate) path: Arc<str>,
    /// The file the body's source lives in.
    pub(crate) file: Arc<std::path::PathBuf>,
    pub(crate) line: usize,
    /// Newlines inside the body's expanded text.
    pub(crate) lines: usize,
}

/// What `LineMap` pairs: the expanded rows of one build (one per output line), its body spans in
/// expanded order and the semantic path of every region.
struct Layout {
    origins: dm_preprocess::regions::ExpandedOriginArena,
    text: dm_preprocess::SourceText,
    /// Body spans sorted by start, with the body's index in `SourceShape::bodies`.
    spans: Vec<(usize, usize, usize)>,
    region_paths: Arc<[Arc<str>]>,
}

/// The source inputs of one build that the incremental output compares.
pub struct SourceShape {
    /// The expanded text outside bodies, blank lines aside, with a marker per body.
    text_key: u128,
    /// Every expanded row's region and source line, in order.
    positions: u128,
    pub(crate) bodies: Vec<BodyShape>,
    layout: Layout,
    /// Semantic tree identity of the build this shape describes.
    pub(crate) tree_identity: u128,
}

/// Whether `initial(` ... `)` anywhere names `name` as a whole word.
fn reads_initial(text: &[u8], name: &[u8]) -> bool {
    let needle = b"initial";
    let mut at = 0;
    while let Some(found) = text[at..].windows(needle.len()).position(|window| window == needle) {
        let start = at + found;
        at = start + needle.len();
        if !word_at(text, start, needle) {
            continue;
        }
        let rest = &text[at..];
        let Some(open) = rest.iter().position(|byte| !byte.is_ascii_whitespace()) else {
            break;
        };
        if rest[open] != b'(' {
            continue;
        }
        let mut depth = 0usize;
        let argument_start = at + open + 1;
        let mut end = argument_start;
        for (offset, &byte) in text[argument_start..].iter().enumerate().take(4096) {
            match byte {
                b'(' => depth += 1,
                b')' if depth == 0 => {
                    end = argument_start + offset;
                    break;
                }
                b')' => depth -= 1,
                _ => {}
            }
            end = argument_start + offset + 1;
        }
        let argument = &text[argument_start..end];
        if argument
            .windows(name.len())
            .enumerate()
            .any(|(offset, window)| window == name && word_at(argument, offset, name))
        {
            return true;
        }
    }
    false
}

pub(crate) fn word_at(text: &[u8], at: usize, word: &[u8]) -> bool {
    let before = at == 0 || !(text[at - 1].is_ascii_alphanumeric() || text[at - 1] == b'_');
    let end = at + word.len();
    let after = end >= text.len() || !(text[end].is_ascii_alphanumeric() || text[end] == b'_');
    before && after
}

/// Conservative: any `static` word, or a `global` word not used as `global.x`.
fn declares_static(text: &[u8]) -> bool {
    let mut at = 0;
    while at < text.len() {
        let byte = text[at];
        if byte == b's' || byte == b'g' {
            let (word, member_access_ok): (&[u8], bool) = if byte == b's' {
                (b"static", false)
            } else {
                (b"global", true)
            };
            if text[at..].starts_with(word) && word_at(text, at, word) {
                let next = text[at + word.len()..]
                    .iter()
                    .find(|byte| !byte.is_ascii_whitespace());
                if !(member_access_ok && next == Some(&b'.')) {
                    return true;
                }
            }
        }
        at += 1;
    }
    false
}

fn body_span(body: &dm_tree::frontend::BodyOccurrence, text: &[u8]) -> std::ops::Range<usize> {
    let span = body.expanded_span.range();
    let start = span.start.min(text.len());
    start..span.end.min(text.len()).max(start)
}

fn body_shape(body: &dm_tree::frontend::BodyOccurrence, text: &[u8]) -> BodyShape {
    let body_text = &text[body_span(body, text)];
    let source = &body.source;
    let mut hash = Xxh3::new();
    hash.update(&(body_text.len() as u64).to_le_bytes());
    hash.update(body_text);
    hash.update(source.path.as_os_str().as_encoded_bytes());
    hash.update(b"\0");
    hash.update(source.semantic_path.as_bytes());
    hash.update(b"\0");
    for value in [
        source.line,
        source.encounter_ordinal,
        source.include_occurrence,
        body.declaration.0 as usize,
        body.member.0 as usize,
        source.include_chain.len(),
    ] {
        hash.update(&(value as u64).to_le_bytes());
    }
    for &include in source.include_chain.iter() {
        hash.update(&(include as u64).to_le_bytes());
    }
    for expansion in source.macro_expansions.iter() {
        hash.update(expansion.name.as_bytes());
        for name in expansion.replacement_chain.iter() {
            hash.update(b"/");
            hash.update(name.as_bytes());
        }
        hash.update(b";");
    }
    for origin in body.setting_context_origins.iter() {
        hash.update(origin.semantic_path.as_bytes());
        hash.update(&(origin.line as u64).to_le_bytes());
    }
    BodyShape {
        digest: hash.digest128(),
        text: xxhash_rust::xxh3::xxh3_128(body_text),
        guarded: declares_static(body_text),
        path: Arc::clone(&source.semantic_path),
        file: Arc::clone(&source.path),
        line: source.line,
        lines: body_text.iter().filter(|&&byte| byte == b'\n').count(),
    }
}

/// How one expanded row takes part in line pairing.
#[derive(Clone, Copy, PartialEq, Eq)]
enum Row {
    /// Has text outside every body: paired in order with the other build's.
    Skeleton,
    /// Inside the body with this index (no text outside bodies).
    Body(usize),
    /// Whitespace only, outside bodies.
    Blank,
}

/// Classify every row of `layout`, calling `visit(index, row, outside_text)` in order. A row's
/// outside text is its bytes outside every body span, without the line break.
fn sweep_rows(layout: &Layout, mut visit: impl FnMut(usize, Row, &[&[u8]])) {
    let text = layout.text.as_str().as_bytes();
    let mut body = 0usize;
    let mut parts: Vec<&[u8]> = Vec::with_capacity(2);
    for index in 0..layout.origins.len() {
        let Some(origin) = layout.origins.get(index) else {
            break;
        };
        let (start, end) = (
            origin.output_span.start.min(text.len()),
            origin.output_span.end.min(text.len()),
        );
        while body < layout.spans.len() && layout.spans[body].1 <= start {
            body += 1;
        }
        parts.clear();
        let mut cursor = start;
        let mut inside = None;
        let mut next = body;
        while cursor < end {
            match layout.spans.get(next) {
                Some(&(span_start, span_end, which)) if span_start < end => {
                    if span_start > cursor {
                        parts.push(&text[cursor..span_start]);
                    }
                    inside.get_or_insert(which);
                    cursor = cursor.max(span_end);
                    next += 1;
                }
                _ => {
                    parts.push(&text[cursor..end]);
                    cursor = end;
                }
            }
        }
        let significant = parts
            .iter()
            .any(|part| part.iter().any(|byte| !byte.is_ascii_whitespace()));
        let row = match (significant, inside) {
            (true, _) => Row::Skeleton,
            (false, Some(which)) => Row::Body(which),
            (false, None) => Row::Blank,
        };
        visit(index, row, &parts);
    }
}

impl SourceShape {
    pub fn capture(
        frontend: &dm_tree::frontend::ColdFrontend,
        executor: &dm_exec::BuildExecutor,
    ) -> Self {
        let _profile = dm_profile::stage("retained_output.source_shape");
        let text = frontend.expanded.text.as_str().as_bytes();
        let bodies = &frontend.bodies;
        let shapes: Vec<BodyShape> = executor.install(|| {
            use rayon::prelude::*;
            bodies
                .par_iter()
                .with_min_len(256)
                .map(|body| body_shape(body, text))
                .collect()
        });
        let mut spans: Vec<(usize, usize, usize)> = bodies
            .iter()
            .enumerate()
            .map(|(index, body)| {
                let span = body_span(body, text);
                (span.start, span.end, index)
            })
            .collect();
        spans.sort_unstable();
        let region_paths: Arc<[Arc<str>]> = frontend
            .plan
            .regions
            .iter()
            .map(|region| Arc::clone(&frontend.plan.occurrences[region.occurrence].semantic_path))
            .collect();
        let layout = Layout {
            origins: frontend.expanded.origins.clone(),
            text: frontend.expanded.text.clone(),
            spans,
            region_paths,
        };
        let mut key = Xxh3::new();
        key.update(b"dmb-retained-output-text-v1\0");
        for file in frontend.files.iter() {
            key.update(file.path.as_os_str().as_encoded_bytes());
            key.update(&[0, u8::from(file.captured)]);
        }
        let mut positions = Xxh3::new();
        positions.update(b"dmb-retained-output-positions-v1\0");
        let mut last_body = None;
        sweep_rows(&layout, |index, row, parts| {
            if let Some(origin) = layout.origins.get(index) {
                positions.update(&(origin.region as u64).to_le_bytes());
                positions.update(&(origin.origin.source_line as u64).to_le_bytes());
            }
            if let Row::Body(which) = row {
                if last_body != Some(which) {
                    key.update(b"\0body\0");
                    key.update(shapes[which].path.as_bytes());
                    last_body = Some(which);
                }
            }
            if row == Row::Skeleton {
                for part in parts {
                    let part = match part.iter().rposition(|byte| !byte.is_ascii_whitespace()) {
                        Some(last) => &part[..=last],
                        None => &part[..0],
                    };
                    key.update(&(part.len() as u64).to_le_bytes());
                    key.update(part);
                }
                key.update(b"\n");
            }
        });
        dm_profile::request_mark("retained_output.text_key");
        Self {
            text_key: key.digest128(),
            positions: positions.digest128(),
            bodies: shapes,
            layout,
            tree_identity: frontend.snapshot.tree.identity(),
        }
    }
    /// The program text outside procedure bodies (blank lines aside) and the body roster.
    pub(crate) fn text_key(&self) -> (u128, usize) {
        (self.text_key, self.bodies.len())
    }
}

/// The new source line of an old one, per semantic path. Paired rows that kept their line are
/// not stored; rows inside a body whose text changed cannot be paired and are recorded as
/// unknown, and a lookup there fails.
pub(crate) struct LineMap {
    identity: bool,
    moved: HashMap<Arc<str>, HashMap<usize, usize>>,
    unknown: HashMap<Arc<str>, std::collections::HashSet<usize>>,
}
impl LineMap {
    fn identity() -> Self {
        Self {
            identity: true,
            moved: HashMap::new(),
            unknown: HashMap::new(),
        }
    }
    /// Pair the rows of two builds with equal `text_key`s.
    fn between(old: &SourceShape, new: &SourceShape) -> Result<Self, String> {
        if old.positions == new.positions {
            return Ok(Self::identity());
        }
        let _timer = dm_profile::detail_timer("retained_output.line_map");
        type Rows = (Vec<(Arc<str>, usize)>, HashMap<usize, Vec<(Arc<str>, usize)>>);
        let collect = |shape: &SourceShape| -> Rows {
            let layout = &shape.layout;
            let mut skeleton = Vec::new();
            let mut bodies: HashMap<usize, Vec<(Arc<str>, usize)>> = HashMap::new();
            sweep_rows(layout, |index, row, _| {
                let Some(origin) = layout.origins.get(index) else {
                    return;
                };
                let Some(path) = layout.region_paths.get(origin.region) else {
                    return;
                };
                let at = (Arc::clone(path), origin.origin.source_line);
                match row {
                    Row::Skeleton => skeleton.push(at),
                    Row::Body(which) => bodies.entry(which).or_default().push(at),
                    // Nothing points at a blank line.
                    Row::Blank => {}
                }
            });
            (skeleton, bodies)
        };
        let (old_skeleton, old_bodies) = collect(old);
        let (new_skeleton, new_bodies) = collect(new);
        if old_skeleton.len() != new_skeleton.len() {
            return Err(format!(
                "{} declaration lines became {}",
                old_skeleton.len(),
                new_skeleton.len()
            ));
        }
        let mut map = Self {
            identity: false,
            moved: HashMap::new(),
            unknown: HashMap::new(),
        };
        let mut pair = |map: &mut Self, (old_path, old_line): &(Arc<str>, usize), (new_path, new_line): &(Arc<str>, usize)| {
            if old_path != new_path {
                return Err(format!("{old_path}:{old_line} moved to {new_path}:{new_line}"));
            }
            if old_line != new_line {
                if let Some(previous) = map
                    .moved
                    .entry(Arc::clone(old_path))
                    .or_default()
                    .insert(*old_line, *new_line)
                {
                    if previous != *new_line {
                        return Err(format!("{old_path}:{old_line} maps to two lines"));
                    }
                }
            }
            Ok(())
        };
        for (old, new) in old_skeleton.iter().zip(&new_skeleton) {
            pair(&mut map, old, new)?;
        }
        for (which, rows) in &old_bodies {
            let same_text = old.bodies[*which].text == new.bodies[*which].text;
            match new_bodies.get(which) {
                Some(new_rows) if same_text && new_rows.len() == rows.len() => {
                    for (old, new) in rows.iter().zip(new_rows) {
                        pair(&mut map, old, new)?;
                    }
                }
                _ => {
                    for (path, line) in rows {
                        map.unknown.entry(Arc::clone(path)).or_default().insert(*line);
                    }
                }
            }
        }
        // A line that is both paired (moved) and unknown keeps its pairing.
        for (path, lines) in &mut map.unknown {
            if let Some(moved) = map.moved.get(path) {
                lines.retain(|line| !moved.contains_key(line));
            }
        }
        Ok(map)
    }
    pub(crate) fn is_identity(&self) -> bool {
        self.identity || self.moved.values().all(HashMap::is_empty)
    }
    /// New line of an old line, when the two builds pair it.
    pub(crate) fn map(&self, path: &str, line: usize) -> Option<usize> {
        if self.identity || line == 0 {
            return Some(line);
        }
        if let Some(new) = self.moved.get(path).and_then(|moved| moved.get(&line)) {
            return Some(*new);
        }
        if self.unknown.get(path).is_some_and(|lines| lines.contains(&line)) {
            return None;
        }
        Some(line)
    }
}

/// Warnings of a full build split by where an incremental output gets them from.
#[derive(Clone)]
pub struct OutputWarnings {
    /// Initializer and callable warnings (declaration level; moved with their lines).
    pub(crate) prefix: Vec<InitializerWarning>,
    /// Per-unit warnings in contribution order.
    pub(crate) units: Vec<(UnitIdentity, Vec<InitializerWarning>)>,
}
impl OutputWarnings {
    pub(crate) fn new(
        prefix: Vec<InitializerWarning>,
        units: Vec<(UnitIdentity, Vec<InitializerWarning>)>,
    ) -> Self {
        Self { prefix, units }
    }
    pub(crate) fn render(&self, local: Vec<InitializerWarning>) -> Vec<InitializerWarning> {
        let mut all = self.prefix.clone();
        all.extend(local);
        for (_, warnings) in &self.units {
            all.extend(warnings.iter().cloned());
        }
        all
    }
}

/// Source half of a retained output (the link half and the image are held by the generation
/// itself; see `composition::RetainedGeneration`).
pub struct OutputBase {
    pub(crate) shape: Arc<SourceShape>,
    pub(crate) units: Arc<BTreeMap<UnitIdentity, crate::symbolic::PreparedPatchRecord>>,
    pub(crate) inputs: Arc<crate::input_snapshot::InputSnapshot>,
    pub(crate) archive: crate::publish::ResourceIdentity,
    pub(crate) warnings: Arc<OutputWarnings>,
    /// The answer table's version when this build published (see `QueryDb::answers_version`).
    pub(crate) answers: Option<u128>,
    /// The part of `answers` besides the tree (`QueryDb::answers_context`).
    pub(crate) answers_context: Option<u128>,
    /// The marking of the answer table made for this output (`QueryDb::mark_published`); None
    /// for an output whose answers were not marked (declaration patches).
    pub(crate) marks: Option<u64>,
    pub(crate) dmb_hash: u128,
}
impl OutputBase {
    /// Base of a completed full build.
    pub(crate) fn of_full_build(
        shape: Arc<SourceShape>,
        records: Vec<crate::symbolic::PreparedPatchRecord>,
        inputs: crate::input_snapshot::InputSnapshot,
        archive: crate::publish::ResourceIdentity,
        warnings: OutputWarnings,
        answers: Option<u128>,
        answers_context: Option<u128>,
        marks: Option<u64>,
        dmb_hash: u128,
    ) -> Option<Self> {
        let mut units = BTreeMap::new();
        for record in records {
            // Duplicate identities never splice; the linker rejects them anyway.
            if units.insert(record.record.identity(), record).is_some() {
                return None;
            }
        }
        Some(Self {
            shape,
            units: Arc::new(units),
            inputs: Arc::new(inputs),
            archive,
            warnings: Arc::new(warnings),
            answers,
            answers_context,
            marks,
            dmb_hash,
        })
    }
    /// Program text key and body count of the build this base describes.
    pub(crate) fn text_key(&self) -> (u128, usize) {
        self.shape.text_key()
    }
    pub(crate) fn dmb_hash(&self) -> u128 {
        self.dmb_hash
    }
    pub(crate) fn with_output_hash(mut self, hash: u128) -> Self {
        self.dmb_hash = hash;
        self
    }
}

/// An incrementally linked output, ready for the ordinary publication path.
pub(crate) struct Patched {
    pub dmb: byond_dmb::dmb::EncodedDmb,
    pub warnings: Vec<InitializerWarning>,
    pub query: (
        Arc<crate::driver_facts::PreparedAbiUnits>,
        Arc<crate::startup::StartupFacts>,
    ),
    pub changed_bodies: usize,
    pub shifted_initializers: usize,
    pub patched_rows: usize,
}

/// The retained output a request may build on, from the request runner.
pub struct RetainedOutput<'a> {
    pub generation: &'a crate::composition::RetainedGeneration,
    pub shape: &'a Arc<SourceShape>,
    pub inputs: crate::input_snapshot::InputSnapshot,
    pub archive: crate::publish::ResourceIdentity,
}

pub(crate) fn first_root_body(frontend: &dm_tree::frontend::ColdFrontend) -> Option<usize> {
    use dm_tree::allocation_ledger::AllocationKind;
    let root = dm_ir::SymbolId::of("/");
    let span = frontend.allocation_ledger.events.iter().find_map(|event| match event.kind {
        AllocationKind::Procedure {
            owner,
            verb: false,
            body,
            ..
        } if owner == root => Some(body),
        _ => None,
    })?;
    frontend
        .bodies
        .iter()
        .position(|occurrence| occurrence.expanded_span == span)
}

pub(crate) fn code_row(
    image: &crate::composition::PatchImage,
    tables: &dm_link::LinkTables,
    key: dm_link::Key,
) -> Result<usize, String> {
    let index = tables
        .index(key)
        .ok_or_else(|| format!("{key:?} has no procedure index"))?;
    image
        .proc_code
        .get(index as usize)
        .map(|&code| code as usize)
        .filter(|&code| code < image.rows.len())
        .ok_or_else(|| format!("{key:?} has no retained code list"))
}

/// The bodies to relower against the retained output, and how lines moved; `Err` says why the
/// declaration side differs (the whole program is composed).
pub(crate) struct Admitted {
    /// The answer facts the patched output is retained with.
    pub answered: Answered,
    pub base: Arc<OutputBase>,
    pub link: Arc<crate::composition::PatchLink>,
    pub image: Arc<crate::composition::PatchImage>,
    pub changed: Vec<usize>,
    pub lines: LineMap,
    /// Variables-table records `(record, kind, value)` whose numeric default this request edited.
    pub variable_values: Vec<(u32, u8, u32)>,
}
/// The answer table's facts at the point an output is retained (see `OutputBase`).
#[derive(Clone, Copy, Debug, Default)]
pub(crate) struct Answered {
    pub version: Option<u128>,
    pub context: Option<u128>,
    pub marks: Option<u64>,
}

/// This request's answers: the table, the request's view of it and the worker count its proof
/// may use.
pub(crate) struct AnswerProof<'a> {
    pub db: &'a crate::query_db::QueryDb,
    pub request: &'a crate::query_db::RequestAnswers<'a>,
    pub workers: usize,
}

/// Admit the request to be built on the retained output.
///
/// The answers gate is decided on the answers themselves, last (it is the only expensive
/// check): when the table's version is the one the retained output published with, every
/// answer is equal. Otherwise the version differs only in the tree identity (the answer world
/// and the resource searches must be equal), and every answer the retained output was built
/// from is asked again under this request's tree and compared with the value it had at
/// publication (`QueryDb::prove_against_base`). That proof asks the whole marked table, not
/// the answers some stage happened to ask, so it does not depend on what is unasked. A unit
/// that reads an answer with no published value is a new unit: only bodies whose text or
/// position changed are lowered here, with this request's answers, and the body roster is the
/// same as the retained output's, so none is new.
pub(crate) fn admit(
    retained: &RetainedOutput<'_>,
    frontend: &dm_tree::frontend::ColdFrontend,
    answers: Option<u128>,
    context: Option<u128>,
    proof: Option<AnswerProof<'_>>,
) -> Result<Admitted, String> {
    let shape = retained.shape;
    // Prefer a retained output of this build's program text (another lane's tree may be current).
    if retained
        .generation
        .select_patch_base(|base| base.text_key() == shape.text_key())
    {
        crate::daemon_eprintln!("native incremental output: switched to the retained output with this program text");
    }
    let (base, link, image) = retained
        .generation
        .patch_base()
        .ok_or("no retained output")?;
    if base.dmb_hash != image.rows.image().content_hash() {
        return Err("retained image differs from its output".into());
    }
    let Some(answers) = answers else {
        return Err("answers are not versioned".into());
    };
    // A pure numeric default edit (proved by the frontend relative to this very base) moves the
    // text of the default's own row and nothing else: its Variables record is rewritten and no
    // text can read the default at compile time.
    let default_edits = frontend
        .snapshot
        .tree
        .default_edits()
        .filter(|edits| edits.from_identity == base.shape.tree_identity);
    let mut variable_values = Vec::new();
    if let Some(edits) = default_edits.filter(|_| base.shape.text_key() != shape.text_key()) {
        if base.shape.bodies.len() != shape.bodies.len() {
            return Err("body roster changed with the defaults".into());
        }
        variable_values = default_edit_records(retained, frontend, &image, edits, &base.shape, shape)?;
    } else if base.shape.text_key() != shape.text_key() {
        return Err("program text outside bodies changed".into());
    }
    if base.shape.bodies.iter().zip(&shape.bodies).any(|(old, new)| old.path != new.path) {
        return Err("a body moved between files".into());
    }
    if let Some(difference) = retained
        .inputs
        .non_text_difference_with(&base.inputs, retained.archive != base.archive)
    {
        return Err(format!("non-text input changed: {difference}"));
    }
    if retained.archive != base.archive {
        return Err("resource archive changed".into());
    }
    let lines = LineMap::between(&base.shape, shape)?;
    let changed: Vec<usize> = shape
        .bodies
        .iter()
        .zip(&base.shape.bodies)
        .enumerate()
        .filter(|(_, (new, old))| new.digest != old.digest)
        .map(|(index, _)| index)
        .collect();
    if changed.len() > SPLICE_LIMIT {
        return Err(format!("{} bodies changed (limit {SPLICE_LIMIT})", changed.len()));
    }
    if first_root_body(frontend).is_some_and(|root| changed.contains(&root)) {
        return Err("changed body is the first root procedure (its literals register strings)".into());
    }
    let mut answered = Answered { version: Some(answers), context, marks: None };
    if !variable_values.is_empty() {
        // The answer world differs with the declarations by exactly the edited defaults, and no
        // text can read one (`reads_initial` found no `initial()` naming it), so no answer a
        // retained unit read has moved.
        crate::daemon_eprintln!(
            "native incremental output: {} numeric defaults edited, answers not compared",
            variable_values.len()
        );
    } else if base.answers != Some(answers) {
        let detail = proof.as_ref().map_or_else(String::new, |proof| {
            format!(" ({})", proof.db.answer_diff().summary())
        });
        if context.is_none() || base.answers_context != context {
            return Err(format!("answer world or resource searches changed{detail}"));
        }
        let (Some(proof), Some(marks)) = (proof.as_ref(), base.marks) else {
            return Err(format!("answers changed, none marked for the retained output{detail}"));
        };
        let held = proof
            .db
            .prove_against_base(proof.request, marks, proof.workers)
            .map_err(|reason| format!("answers changed: {reason}{detail}"))?;
        crate::daemon_eprintln!(
            "native incremental output: {held} published answers asked again, none differ (tree identity only)"
        );
    }
    if let Some(proof) = &proof {
        answered.marks = Some(proof.db.mark_published());
    }
    Ok(Admitted {
        answered,
        base,
        link,
        image,
        changed,
        lines,
        variable_values,
    })
}

/// The Variables records of a pure numeric default edit, after proving the program text outside
/// bodies differs from the retained build's only in those defaults' own rows and that no text
/// reads one at compile time.
fn default_edit_records(
    retained: &RetainedOutput<'_>,
    frontend: &dm_tree::frontend::ColdFrontend,
    image: &crate::composition::PatchImage,
    edits: &dm_tree::DefaultEdits,
    old: &SourceShape,
    new: &SourceShape,
) -> Result<Vec<(u32, u8, u32)>, String> {
    let text = frontend.expanded.text.as_str().as_bytes();
    let symbols = frontend.snapshot.tree.symbols();
    let mut names: Vec<Vec<u8>> = Vec::with_capacity(edits.edits.len());
    let mut values = Vec::with_capacity(edits.edits.len());
    for edit in &edits.edits {
        let name = symbols.text(edit.name).ok_or("edited var has no spelling")?;
        if reads_initial(text, name.as_bytes()) {
            return Err(format!("initial({name}) is read at compile time"));
        }
        let record = retained
            .generation
            .field_record(edit.owner, edit.name)
            .ok_or("edited var has no retained field record")?;
        let (kind, value, _) = image
            .rows
            .variable_record(record)
            .map_err(|error| format!("variable record: {error}"))?;
        if kind != 42 || value != edit.old_bits {
            return Err("retained record does not hold the old numeric default".into());
        }
        names.push(name.as_bytes().to_vec());
        values.push((record, 42u8, edit.value_bits));
    }
    let (old_hashes, _) = skeleton_rows(&old.layout, None);
    let (new_hashes, _) = skeleton_rows(&new.layout, None);
    if old_hashes.len() != new_hashes.len() {
        return Err("declaration line count changed with the defaults".into());
    }
    let differing: std::collections::HashSet<usize> = old_hashes
        .iter()
        .zip(&new_hashes)
        .enumerate()
        .filter(|(_, (a, b))| a != b)
        .map(|(index, _)| index)
        .collect();
    if differing.len() > edits.edits.len() {
        return Err(format!(
            "{} declaration lines changed for {} default edits",
            differing.len(),
            edits.edits.len()
        ));
    }
    let (_, old_text) = skeleton_rows(&old.layout, Some(&differing));
    let (_, new_text) = skeleton_rows(&new.layout, Some(&differing));
    for index in &differing {
        let (Some(before), Some(after)) = (old_text.get(index), new_text.get(index)) else {
            return Err("changed declaration line is not retained".into());
        };
        if !is_default_row_edit(before, after, &names) {
            return Err("a declaration line changed other than a numeric default".into());
        }
    }
    Ok(values)
}

/// `var/name = <number>` rows that differ only in the number, naming an edited var.
fn is_default_row_edit(before: &[u8], after: &[u8], names: &[Vec<u8>]) -> bool {
    let split = |row: &[u8]| -> Option<(Vec<u8>, Vec<u8>)> {
        let at = row.iter().position(|&byte| byte == b'=')?;
        Some((row[..at].trim_ascii().to_vec(), row[at + 1..].trim_ascii().to_vec()))
    };
    let (Some((head, old_value)), Some((new_head, new_value))) = (split(before), split(after)) else {
        return false;
    };
    let numeric = |value: &[u8]| {
        !value.is_empty()
            && value
                .iter()
                .all(|byte| byte.is_ascii_hexdigit() || matches!(byte, b'x' | b'X' | b'.' | b'+' | b'-'))
    };
    if head != new_head || !numeric(&old_value) || !numeric(&new_value) {
        return false;
    }
    if head.iter().any(|byte| matches!(byte, b'(' | b')' | b',' | b'=' | b'"')) {
        return false;
    }
    names.iter().any(|name| {
        head.ends_with(name)
            && head.len().checked_sub(name.len()).is_some_and(|start| {
                start == 0 || !(head[start - 1].is_ascii_alphanumeric() || head[start - 1] == b'_')
            })
    })
}

/// The hash of every row with text outside bodies (trailing blanks aside), in order, and the text
/// of the rows whose ordinal is in `wanted`.
fn skeleton_rows(
    layout: &Layout,
    wanted: Option<&std::collections::HashSet<usize>>,
) -> (Vec<u128>, HashMap<usize, Vec<u8>>) {
    let mut hashes = Vec::new();
    let mut texts = HashMap::new();
    sweep_rows(layout, |_, row, parts| {
        if row != Row::Skeleton {
            return;
        }
        let mut hash = Xxh3::new();
        let mut joined = Vec::new();
        for part in parts {
            let part = match part.iter().rposition(|byte| !byte.is_ascii_whitespace()) {
                Some(last) => &part[..=last],
                None => &part[..0],
            };
            hash.update(&(part.len() as u64).to_le_bytes());
            hash.update(part);
            if wanted.is_some() {
                joined.extend_from_slice(part);
            }
        }
        if wanted.is_some_and(|wanted| wanted.contains(&hashes.len())) {
            texts.insert(hashes.len(), joined);
        }
        hashes.push(hash.digest128());
    });
    (hashes, texts)
}

/// Relink the relowered units against the retained tables and splice their rows (and those of
/// initializers whose lines moved) into the retained image.
pub(crate) fn splice(
    retained: RetainedOutput<'_>,
    admitted: Admitted,
    frontend: &dm_tree::frontend::ColdFrontend,
    contributions: &[crate::symbolic::PreparedContribution],
    query: (
        Arc<crate::driver_facts::PreparedAbiUnits>,
        Arc<crate::startup::StartupFacts>,
    ),
    executor: &dm_exec::BuildExecutor,
) -> Result<Patched, String> {
    let Admitted {
        answered,
        base,
        link,
        image,
        changed,
        lines,
        variable_values,
    } = admitted;
    let shape = retained.shape;
    let symbols = frontend.snapshot.tree.symbols();
    // Bodies whose text is unchanged and merely moved, by current position.
    let moved: std::collections::HashSet<(Arc<str>, usize)> = changed
        .iter()
        .filter(|&&index| shape.bodies[index].text == base.shape.bodies[index].text)
        .map(|&index| (Arc::clone(&shape.bodies[index].path), shape.bodies[index].line))
        .collect();
    let mut rows = Vec::new();
    let mut unit_warnings = BTreeMap::new();
    // Units whose footprint differs only in the string literals they own: their new strings are
    // appended to the string table, the old ones stay unreferenced (stable numbering).
    let mut string_units: Vec<(UnitIdentity, crate::symbolic::PreparedPatchRecord)> = Vec::new();
    let mut new_entries: Vec<(dm_link::Key, dm_link::EntryContent)> = Vec::new();
    for contribution in contributions {
        let record = contribution.patch_record();
        let identity = record.record.identity();
        let old = base
            .units
            .get(&identity)
            .ok_or_else(|| format!("unit {identity:?} absent from the retained output"))?;
        let source = contribution.current_source();
        let moved_only = moved.contains(&(Arc::clone(&source.semantic_path), source.line));
        // A moved body's modified-instance descriptors keep their aliases (the footprint
        // compares them); their initializer code is moved with its lines.
        if (record.modified || old.modified) && !moved_only {
            return Err(format!("unit {identity:?} has modified instances"));
        }
        let (new_parts, old_parts) = (record.footprint(), old.footprint());
        let mut differing = new_parts
            .iter()
            .zip(&old_parts)
            .filter(|((_, new), (_, old))| new != old)
            .map(|((name, _), _)| *name);
        if let Some(first) = differing.next() {
            let strings_only = std::iter::once(first)
                .chain(differing)
                .all(|name| matches!(name, "strings" | "value_strings"));
            if !strings_only {
                return Err(format!("unit {identity:?} link footprint changed: {first}"));
            }
            new_entries.extend(record.record.string_entries());
            string_units.push((identity, record));
        }
    }
    // With new strings the units link against tables extended append-only; every existing
    // assignment stays, so the other units' words are unchanged.
    let mut extended = None;
    let mut new_strings = Vec::new();
    if !string_units.is_empty() {
        let starts = retained
            .generation
            .model_table_starts(base.dmb_hash)
            .ok_or("retained model released or differs from the retained output")?;
        let (tables, added) = link
            .tables
            .extended(new_entries, &starts)
            .map_err(|error| format!("string append link: {error:?}"))?;
        for &(key, index) in &added {
            match key {
                dm_link::Key::String(_) => new_strings.push((
                    index,
                    tables.content(key).ok_or("appended string content")?.to_vec(),
                )),
                other => return Err(format!("string append would add {other:?}")),
            }
        }
        dm_profile::request_mark("splice.strings_extended");
        extended = Some(tables);
    }
    let tables = extended.as_ref().unwrap_or(&link.tables);
    let mut push_row = |rows: &mut Vec<(usize, Arc<Vec<u32>>)>, key, words: Arc<Vec<u32>>| {
        byond_dmb::bytecode::visit_instructions(&words, |_| {}, |_| {})
            .map_err(|error| format!("{key:?} bytecode: {error:?}"))?;
        let code = code_row(&image, tables, key)?;
        if !image.rows.row_equals(code, &words) {
            rows.push((code, words));
        }
        Ok::<_, String>(())
    };
    for contribution in contributions {
        let record = contribution.patch_record();
        let identity = record.record.identity();
        let words = record
            .record
            .link_words(tables, &link.mobs)
            .map_err(|error| format!("unit {identity:?} link: {error:?}"))?;
        push_row(&mut rows, crate::symbolic::unit_key(identity), words)?;
        for (key, words) in record
            .record
            .helper_words(tables, &link.mobs)
            .map_err(|error| format!("unit {identity:?} helper link: {error:?}"))?
        {
            push_row(&mut rows, key, words)?;
        }
        unit_warnings.insert(
            identity,
            contribution
                .current_warnings(symbols)
                .map_err(|error| format!("unit {identity:?} warnings: {error}"))?,
        );
    }
    let mut shifted_initializers = 0;
    let mut next_initializers = None;
    if !lines.is_identity() {
        // Every retained debug line must be paired with a current one.
        for code in &link.initializers {
            if let Some((path, line)) = code
                .origin_lines()
                .find(|(path, line)| lines.map(path, *line as usize).is_none())
            {
                return Err(format!("initializer line {path}:{line} has no current line"));
            }
        }
        let shift = |path: &str, line: u32| {
            lines.map(path, line as usize).map_or(line, |line| line as u32)
        };
        let mut current = Vec::with_capacity(link.initializers.len());
        for code in &link.initializers {
            match code
                .relink_shifted(tables, &link.mobs, &shift)
                .map_err(|error| format!("{:?} relink: {error:?}", code.key))?
            {
                Some((words, moved)) => {
                    shifted_initializers += 1;
                    push_row(&mut rows, code.key, words)?;
                    current.push(moved);
                }
                None => current.push(code.clone()),
            }
        }
        next_initializers = Some(current);
    }
    dm_profile::request_mark("splice.linked");
    // Warnings exactly as a full build reports them: moved declaration warnings, current local
    // warnings, then unit warnings in unit order.
    let mut warnings = (*base.warnings).clone();
    for warning in &mut warnings.prefix {
        if let Some(line) = warning.location.line.as_mut() {
            *line = lines
                .map(&warning.location.semantic_path, *line)
                .ok_or_else(|| {
                    format!(
                        "warning line {}:{line} has no current line",
                        warning.location.semantic_path
                    )
                })?;
        }
    }
    for (identity, current) in &mut warnings.units {
        if let Some(rebound) = unit_warnings.remove(identity) {
            *current = rebound;
        }
    }
    let local = crate::local_warnings::capture(frontend)
        .map_err(|error| format!("local warnings: {error:?}"))?;
    let output_warnings = warnings.render(local);
    let patched_rows = rows.len() + variable_values.len();
    let appended_strings = new_strings.len();
    let units = if string_units.is_empty() {
        Arc::clone(&base.units)
    } else {
        let mut units = (*base.units).clone();
        for (identity, record) in string_units {
            units.insert(identity, record);
        }
        Arc::new(units)
    };
    let next = OutputBase {
        shape: Arc::clone(shape),
        units,
        inputs: Arc::new(retained.inputs),
        archive: retained.archive,
        warnings: Arc::new(warnings),
        answers: answered.version,
        answers_context: answered.context,
        marks: answered.marks,
        dmb_hash: 0,
    };
    let dmb = if let Some(tables) = extended {
        // The model path re-encodes with list-row reuse and installs the extended tables;
        // `patch_rows` would leave the new strings out of the image.
        let initializers = next_initializers.unwrap_or_else(|| link.initializers.clone());
        retained.generation.patch_model(
            base.dmb_hash,
            |model| crate::composition::append::append_table_strings(model, &new_strings),
            |model, _strings| {
                for (row, words) in &rows {
                    *model.lists.get_mut(*row).ok_or_else(|| {
                        crate::composition::CompositionError::NonContiguous("code row".into())
                    })? = words.as_ref().clone();
                }
                for &(record, _, value) in &variable_values {
                    model
                        .variables
                        .get_mut(record as usize)
                        .ok_or_else(|| {
                            crate::composition::CompositionError::NonContiguous("variable record".into())
                        })?
                        .value = value;
                }
                Ok(())
            },
            crate::composition::PatchLink {
                tables,
                mobs: link.mobs.clone(),
                initializers,
            },
            next,
            executor,
        )?
    } else {
        // `patch_rows` stamps the new output hash before installing the base.
        retained
            .generation
            .patch_rows(&image, &rows, &variable_values, next, next_initializers)?
    };
    if appended_strings > 0 {
        crate::daemon_eprintln!("native incremental output: {appended_strings} strings appended");
    }
    Ok(Patched {
        dmb,
        warnings: output_warnings,
        query,
        changed_bodies: changed.len(),
        shifted_initializers,
        patched_rows,
    })
}

/// Incremental outputs per project (test and diagnostic observation only).
static APPLIED: std::sync::Mutex<BTreeMap<std::path::PathBuf, u64>> =
    std::sync::Mutex::new(BTreeMap::new());
pub(crate) fn note_applied(project: &std::path::Path) {
    *APPLIED
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .entry(project.to_path_buf())
        .or_default() += 1;
}
#[cfg(test)]
pub(crate) fn applied(project: &std::path::Path) -> u64 {
    APPLIED
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .get(project)
        .copied()
        .unwrap_or(0)
}

/// Incremental outputs plus declaration patches of a project (tests).
#[cfg(test)]
pub(crate) fn applied_with_declaration_patches(project: &std::path::Path) -> u64 {
    applied(project) + crate::declaration_patch::applied(project)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn static_and_global_declarations_are_guarded_but_global_access_is_not() {
        assert!(declares_static(b"var/static/x = 1"));
        assert!(declares_static(b"var/global/list/x"));
        assert!(!declares_static(b"return global.x"));
        assert!(!declares_static(b"var/globalish = 1; staticky()"));
    }
}

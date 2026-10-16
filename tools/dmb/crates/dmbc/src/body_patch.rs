//! Body-edit fast path for retained (daemon) builds.
//!
//! When an edit changes only procedure bodies, the declaration skeleton, every
//! non-text input and every table assignment of the previous build stay valid.
//! The fast path then lowers only the changed bodies, links each one against
//! the retained link tables, and splices the new code lists into the retained
//! output image. Everything else (initializers, class projection,
//! required-type admission, whole-program linking, composition and encoding)
//! is skipped. The result must equal a fresh full build byte for byte; every
//! condition that cannot be proven declines the patch with a logged reason,
//! and the ordinary full path runs.
//!
//! Positions are kept out of the skeleton. A body edit that adds or removes
//! lines shifts every later line of its file: the bodies below it then have new
//! start lines (their digests change, so they are relowered and patched like
//! edited bodies), and initializer procedures whose debug lines lie below it
//! are relinked with shifted lines and patched too. Initializer and callable
//! warnings are line-shifted, local warnings recomputed and unit warnings
//! rebound, so reported warnings match a full build.
//!
//! Admission, in order:
//! 1. A patch base exists: the previous successful build of this session left
//!    its source shape, per-unit footprints, link tables, inputs and the hash
//!    of the image it describes.
//! 2. The declaration skeleton is unchanged: the expanded text outside bodies,
//!    each body's file, and the file roster (no positions).
//! 3. The line map derived from body line counts explains every body's new
//!    start line.
//! 4. No input other than `.dm`/`.dme` text changed (content), no resource
//!    search folder changed, and the resource archive identity is unchanged.
//! 5. Changed bodies (by expanded text and source position) are at most
//!    `PATCH_LIMIT`, none of them (before or after) declares a proc-static or
//!    global var, and none is the first root procedure (whose literals
//!    register strings early).
//! 6. Each relowered unit has the same link footprint as before (frame, ABI,
//!    features, inventory entry/slots/strings, value strings, debug paths,
//!    instances, helper link inputs, required types, no modified instances).
use crate::initializer_policy::warnings::InitializerWarning;
use crate::lowering::UnitIdentity;
use std::collections::{BTreeMap, HashMap};
use std::sync::Arc;
use xxhash_rust::xxh3::Xxh3;

#[path = "body_patch_append.rs"]
mod append;
#[path = "body_patch_lines.rs"]
mod align;

/// At most this many relowered bodies are patched; more fall back.
const PATCH_LIMIT: usize = 4096;

#[derive(Clone, Debug, PartialEq, Eq)]
struct BodyShape {
    /// Text, file and position of the body (positions included: a moved body
    /// relinks with new debug lines).
    digest: u128,
    /// Expanded text only: a body whose text is unchanged merely moved.
    text: u128,
    /// Declares a proc-static or global var: startup facts depend on it.
    guarded: bool,
    path: Arc<str>,
    /// The file the body's source lives in (its text is retained beside the shape).
    file: Arc<std::path::PathBuf>,
    line: usize,
    /// Newlines inside the body's expanded text.
    lines: usize,
}

/// Declaration skeleton plus one shape per body, in `frontend.bodies` order.
pub struct SourceShape {
    skeleton: u128,
    /// The file roster and include structure, without any text.
    roster: u128,
    /// The text of every captured file as this build read it. Shared with the frontend's owners
    /// (no copy), it lets a later edit that only moves code be aligned against the old text.
    texts: HashMap<Arc<std::path::PathBuf>, dm_preprocess::SourceText>,
    bodies: Vec<BodyShape>,
    /// Semantic tree identity of the build this shape describes; default
    /// edits are admitted only from exactly this tree.
    tree_identity: u128,
}

fn word_at(text: &[u8], at: usize, word: &[u8]) -> bool {
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
    // Diagnostic: DMB_BODY_PATCH_DUMP=<semantic path>:<line> appends that
    // body's expanded text to DMB_BODY_PATCH_DUMP_FILE on every capture.
    if let (Ok(target), Ok(file)) = (
        std::env::var("DMB_BODY_PATCH_DUMP"),
        std::env::var("DMB_BODY_PATCH_DUMP_FILE"),
    ) {
        if target == format!("{}:{}", source.semantic_path, source.line) {
            use std::io::Write;
            if let Ok(mut out) = std::fs::OpenOptions::new().create(true).append(true).open(file) {
                let _ = writeln!(out, "=== {target} {} bytes", body_text.len());
                let _ = out.write_all(body_text);
                let _ = writeln!(out);
            }
        }
    }
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

impl SourceShape {
    pub fn capture(
        frontend: &dm_tree::frontend::ColdFrontend,
        executor: &dm_exec::BuildExecutor,
    ) -> Self {
        let _profile = dm_profile::stage("body_patch.source_shape");
        let text = frontend.expanded.text.as_str().as_bytes();
        let bodies = &frontend.bodies;
        let mut order: Vec<usize> = (0..bodies.len()).collect();
        order.sort_by_key(|&index| {
            let span = bodies[index].expanded_span;
            (span.start, span.end)
        });
        let mut skeleton = Xxh3::new();
        skeleton.update(b"dmb-body-patch-skeleton-v2\0");
        for file in frontend.files.iter() {
            skeleton.update(file.path.to_string_lossy().as_bytes());
            skeleton.update(&[0, u8::from(file.captured)]);
        }
        let mut through = 0usize;
        for &index in &order {
            let body = &bodies[index];
            let span = body_span(body, text);
            if span.start >= through {
                skeleton.update(&((span.start - through) as u64).to_le_bytes());
                skeleton.update(&text[through..span.start]);
            }
            // The body's file, never its position: positions live in the
            // per-body side table and are reconciled by the line map.
            skeleton.update(body.source.semantic_path.as_bytes());
            skeleton.update(b"\0");
            through = through.max(span.end);
        }
        skeleton.update(&text[through.min(text.len())..]);
        dm_profile::request_mark("patch.skeleton_hashed");
        let shapes = executor.install(|| {
            use rayon::prelude::*;
            bodies
                .par_iter()
                .with_min_len(256)
                .map(|body| body_shape(body, text))
                .collect()
        });
        let mut roster = Xxh3::new();
        roster.update(b"dmb-body-patch-roster-v1\0");
        for file in frontend.files.iter() {
            roster.update(file.path.to_string_lossy().as_bytes());
            roster.update(&[0, u8::from(file.captured)]);
        }
        for occurrence in frontend.plan.occurrences.iter() {
            roster.update(occurrence.path.to_string_lossy().as_bytes());
            roster.update(b"\0");
            roster.update(occurrence.semantic_path.as_bytes());
            roster.update(&occurrence.parent.map_or(u64::MAX, |parent| parent as u64).to_le_bytes());
        }
        Self {
            skeleton: skeleton.digest128(),
            roster: roster.digest128(),
            texts: frontend
                .files
                .iter()
                .filter(|file| file.captured)
                .map(|file| (Arc::clone(&file.path), file.text.clone()))
                .collect(),
            bodies: shapes,
            tree_identity: frontend.snapshot.tree.identity(),
        }
    }
}

/// Line shifts of one build relative to the base: per file, the old end line
/// of each body whose line count changed, with the cumulative delta after it.
struct LineMap {
    files: HashMap<Arc<str>, Vec<(usize, isize)>>,
}
impl LineMap {
    fn between(old: &[BodyShape], new: &[BodyShape]) -> Self {
        let mut deltas: HashMap<Arc<str>, Vec<(usize, isize)>> = HashMap::new();
        for (old, new) in old.iter().zip(new) {
            if old.lines != new.lines {
                deltas
                    .entry(Arc::clone(&old.path))
                    .or_default()
                    .push((old.line + old.lines, new.lines as isize - old.lines as isize));
            }
        }
        for steps in deltas.values_mut() {
            steps.sort_by_key(|(end, _)| *end);
            let mut total = 0;
            for step in steps.iter_mut() {
                total += step.1;
                step.1 = total;
            }
        }
        Self { files: deltas }
    }
    /// The map of an edit that only moved code: for every file whose text changed, the old and new
    /// text must agree on every token outside the bodies (see `body_patch_lines`), and the bodies
    /// pair up in order. Files whose text is unchanged do not move.
    fn aligned(
        frontend: &dm_tree::frontend::ColdFrontend,
        old: &SourceShape,
        new: &SourceShape,
        directives: align::Directives,
    ) -> Result<Self, String> {
        let mut semantic: HashMap<&std::path::Path, Vec<Arc<str>>> = HashMap::new();
        for occurrence in frontend.plan.occurrences.iter() {
            let paths = semantic.entry(occurrence.path.as_path()).or_default();
            if !paths.iter().any(|path| *path == occurrence.semantic_path) {
                paths.push(Arc::clone(&occurrence.semantic_path));
            }
        }
        let mut files: HashMap<Arc<str>, Vec<(usize, isize)>> = HashMap::new();
        for file in frontend.files.iter().filter(|file| file.captured) {
            let Some(before) = old.texts.get(&file.path) else {
                return Err(format!("{} is new", file.path.display()));
            };
            let (before, after) = (before.as_str(), file.text.as_str());
            if std::ptr::eq(before.as_ptr(), after.as_ptr()) && before.len() == after.len()
                || before == after
            {
                continue;
            }
            let mut old_ranges = Vec::new();
            let mut new_ranges = Vec::new();
            let mut pairs = Vec::new();
            for (before, after) in old.bodies.iter().zip(&new.bodies) {
                if *after.file != *file.path && *before.file != *file.path {
                    continue;
                }
                if before.file != after.file {
                    return Err("a body moved between files".into());
                }
                old_ranges.push((before.line as u32, (before.line + before.lines) as u32));
                new_ranges.push((after.line as u32, (after.line + after.lines) as u32));
                pairs.push((before.line as u32, after.line as u32));
            }
            old_ranges.sort();
            new_ranges.sort();
            pairs.extend(
                align::gap_pairs(before, &old_ranges, after, &new_ranges, directives)
                    .map_err(|reason| format!("{}: {reason}", file.path.display()))?,
            );
            let steps = align::steps(pairs)
                .ok_or_else(|| format!("{}: lines do not move in order", file.path.display()))?;
            if steps.is_empty() {
                continue;
            }
            for path in semantic.get(file.path.as_path()).into_iter().flatten() {
                files.insert(Arc::clone(path), steps.clone());
            }
        }
        Ok(Self { files })
    }
    fn is_identity(&self) -> bool {
        self.files.is_empty()
    }
    /// New line of an old line outside every changed body.
    fn map(&self, path: &str, line: usize) -> usize {
        let Some(steps) = self.files.get(path) else {
            return line;
        };
        let applied = steps.partition_point(|(end, _)| *end < line);
        match applied {
            0 => line,
            count => (line as isize + steps[count - 1].1).max(0) as usize,
        }
    }
}

/// Warnings of a full build split by where a patch gets them from.
#[derive(Clone)]
pub struct PatchWarnings {
    /// Initializer and callable warnings (declaration level; line-shifted).
    prefix: Vec<InitializerWarning>,
    /// Per-unit warnings in contribution order.
    units: Vec<(UnitIdentity, Vec<InitializerWarning>)>,
}
impl PatchWarnings {
    pub(crate) fn new(
        prefix: Vec<InitializerWarning>,
        units: Vec<(UnitIdentity, Vec<InitializerWarning>)>,
    ) -> Self {
        Self { prefix, units }
    }
    fn render(&self, local: Vec<InitializerWarning>) -> Vec<InitializerWarning> {
        let mut all = self.prefix.clone();
        all.extend(local);
        for (_, warnings) in &self.units {
            all.extend(warnings.iter().cloned());
        }
        all
    }
}

/// Source half of a retained generation's patch base (the link half and the
/// image are held by the generation itself; see `composition::RetainedGeneration`).
pub struct BodyPatchBase {
    shape: Arc<SourceShape>,
    units: Arc<BTreeMap<UnitIdentity, crate::symbolic::PreparedPatchRecord>>,
    inputs: Arc<crate::input_snapshot::InputSnapshot>,
    archive: crate::publish::ResourceIdentity,
    warnings: Arc<PatchWarnings>,
    dmb_hash: u128,
}
impl BodyPatchBase {
    /// Base of a completed full build.
    pub(crate) fn of_full_build(
        shape: Arc<SourceShape>,
        records: Vec<crate::symbolic::PreparedPatchRecord>,
        inputs: crate::input_snapshot::InputSnapshot,
        archive: crate::publish::ResourceIdentity,
        warnings: PatchWarnings,
        dmb_hash: u128,
    ) -> Option<Self> {
        let mut units = BTreeMap::new();
        for record in records {
            // Duplicate identities never patch; the linker rejects them anyway.
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
            dmb_hash,
        })
    }
    pub(crate) fn with_output_hash(mut self, hash: u128) -> Self {
        self.dmb_hash = hash;
        self
    }
}

/// A patched output, ready for the ordinary publication path.
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

/// Inputs of one patch attempt, borrowed from the request runner.
pub(crate) struct PatchRequest<'a, R: dm_ir::Resolver> {
    pub generation: &'a crate::composition::RetainedGeneration,
    pub shape: &'a Arc<SourceShape>,
    pub frontend: &'a dm_tree::frontend::FrontendRevision,
    pub resolver: &'a R,
    pub engine: &'a crate::engine::EngineSnapshot,
    pub engine_bytes: &'a [u8],
    pub references: &'a crate::symbolic::ReferenceBindings,
    pub spellings: &'a Vec<(dm_ir::SymbolId, Arc<[u8]>)>,
    pub resource_search_context: Option<u128>,
    pub inputs: crate::input_snapshot::InputSnapshot,
    pub archive: crate::publish::ResourceIdentity,
    pub executor: &'a dm_exec::BuildExecutor,
    pub memo: Option<&'a crate::lowering_memo::ProcedureMemo>,
    pub workers: usize,
}

fn first_root_body(frontend: &dm_tree::frontend::ColdFrontend) -> Option<usize> {
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

fn code_row(
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

/// Try the fast path. `Err` carries the reason it declined; the caller logs it
/// and runs the full path. No state is changed unless `Ok` is returned.
pub(crate) fn try_patch<R: dm_ir::Resolver>(request: PatchRequest<'_, R>) -> Result<Patched, String> {
    let (base, link, image) = request
        .generation
        .patch_base()
        .ok_or("no patch base retained")?;
    if base.dmb_hash != image.rows.image().content_hash() {
        return Err("retained output differs from the patch base".into());
    }
    let shape = request.shape;
    let frontend: &dm_tree::frontend::ColdFrontend = request.frontend;
    // An edit that only moves code (comment and blank lines, a new directive) leaves the tree and
    // the file roster alone; its line map comes from the changed files' old and new text.
    let same_structure =
        base.shape.tree_identity == shape.tree_identity && base.shape.roster == shape.roster;
    let mut moved = None;
    if shape.bodies.len() != base.shape.bodies.len() || shape.skeleton != base.shape.skeleton {
        let tree = &frontend.snapshot.tree;
        if tree.appended_callables().is_some() {
            return append::try_append_patch(request, &base, &link, &image)
                .map_err(|reason| format!("declaration skeleton changed; append patch: {reason}"));
        }
        if shape.bodies.len() != base.shape.bodies.len() {
            return Err(format!(
                "declaration skeleton changed (bodies {} -> {})",
                base.shape.bodies.len(),
                shape.bodies.len()
            ));
        }
        let motion = if same_structure {
            LineMap::aligned(frontend, &base.shape, shape, align::Directives::Compared)
        } else {
            Err("the tree or the file roster changed".to_string())
        };
        match motion {
            Ok(map) => moved = Some(map),
            Err(motion) => {
                let (old_hash, new_hash) = (base.shape.skeleton, shape.skeleton);
                return try_default_patch(request, &base, &image).map_err(|reason| {
                    format!(
                        "declaration skeleton changed (hash {old_hash:032x} -> {new_hash:032x}, tree identity {}); default patch: {reason}; code motion: {motion}",
                        if same_structure { "same" } else { "changed" }
                    )
                });
            }
        }
    }
    let mut lines = moved.unwrap_or_else(|| LineMap::between(&base.shape.bodies, &shape.bodies));
    let unexplained = |lines: &LineMap| {
        base.shape
            .bodies
            .iter()
            .zip(&shape.bodies)
            .find(|(old, new)| old.path != new.path || lines.map(&old.path, old.line) != new.line)
            .map(|(old, new)| (Arc::clone(&old.path), old.line, Arc::clone(&new.path), new.line))
    };
    if let Some((old_path, old_line, new_path, new_line)) = unexplained(&lines) {
        // Directive lines add no expanded text, so when that text is unchanged they only move code.
        let inert = (same_structure && shape.skeleton == base.shape.skeleton)
            .then(|| LineMap::aligned(frontend, &base.shape, shape, align::Directives::Inert))
            .and_then(Result::ok)
            .filter(|map| unexplained(map).is_none());
        match inert {
            Some(map) => lines = map,
            None => {
                return Err(format!(
                    "line map does not explain {old_path}:{old_line} -> {new_path}:{new_line}"
                ))
            }
        }
    }
    if let Some(difference) = request.inputs.non_text_difference(&base.inputs) {
        return Err(format!("non-text input changed: {difference}"));
    }
    if request.archive != base.archive {
        return Err("resource archive changed".into());
    }
    let changed: Vec<usize> = shape
        .bodies
        .iter()
        .zip(&base.shape.bodies)
        .enumerate()
        .filter(|(_, (new, old))| new.digest != old.digest)
        .map(|(index, _)| index)
        .collect();
    if changed.is_empty() {
        return Err("no body changed".into());
    }
    {
        let sample: Vec<String> = changed
            .iter()
            .take(4)
            .map(|&index| {
                let (old, new) = (&base.shape.bodies[index], &shape.bodies[index]);
                format!("{}:{}->{} lines {}->{}", new.path, old.line, new.line, old.lines, new.lines)
            })
            .collect();
        crate::daemon_eprintln!(
            "native body patch: {} changed bodies, line map {}, first: {}",
            changed.len(),
            if lines.is_identity() { "identity" } else { "shifting" },
            sample.join(", ")
        );
    }
    if changed.len() > PATCH_LIMIT {
        return Err(format!("{} bodies changed (limit {PATCH_LIMIT})", changed.len()));
    }
    for &index in &changed {
        // A moved body keeps its statics; their initializer code is relinked
        // with shifted lines like every other initializer below.
        let moved_only = shape.bodies[index].text == base.shape.bodies[index].text;
        if !moved_only && (shape.bodies[index].guarded || base.shape.bodies[index].guarded) {
            let source = &frontend.bodies[index].source;
            return Err(format!(
                "changed body declares a static or global var ({}:{})",
                source.semantic_path, source.line
            ));
        }
    }
    if first_root_body(frontend).is_some_and(|root| changed.contains(&root)) {
        return Err("changed body is the first root procedure".into());
    }
    let selected: Vec<_> = changed.iter().map(|&index| &frontend.bodies[index]).collect();
    let lowered = crate::cold::body_patch::lower_selected(
        frontend,
        request.resolver,
        crate::cold::body_patch::LinkFacts {
            engine_bytes: request.engine_bytes,
            engine: request.engine,
            references: request.references,
            spellings: request.spellings,
        },
        request.resource_search_context,
        crate::lowering::LoweringConfig {
            workers: request.workers,
            ..Default::default()
        },
        request.memo,
        Some(request.frontend),
        request.executor,
        &selected,
    )?;
    let symbols = frontend.snapshot.tree.symbols();
    // Bodies whose text is unchanged and merely moved, by current position.
    let moved: std::collections::HashSet<(Arc<str>, usize)> = changed
        .iter()
        .filter(|&&index| shape.bodies[index].text == base.shape.bodies[index].text)
        .map(|&index| (Arc::clone(&shape.bodies[index].path), shape.bodies[index].line))
        .collect();
    let mut rows = Vec::new();
    let mut unit_warnings = BTreeMap::new();
    let mut push_row = |rows: &mut Vec<(usize, Arc<Vec<u32>>)>, key, words: Arc<Vec<u32>>| {
        byond_dmb::bytecode::visit_instructions(&words, |_| {}, |_| {})
            .map_err(|error| format!("{key:?} bytecode: {error:?}"))?;
        let code = code_row(&image, &link.tables, key)?;
        if !image.rows.row_equals(code, &words) {
            rows.push((code, words));
        }
        Ok::<_, String>(())
    };
    for contribution in &lowered.contributions {
        let record = contribution.patch_record();
        let identity = record.record.identity();
        let old = base
            .units
            .get(&identity)
            .ok_or_else(|| format!("unit {identity:?} absent from the patch base"))?;
        let source = contribution.current_source();
        let moved_only = moved.contains(&(Arc::clone(&source.semantic_path), source.line));
        // A moved body's modified-instance descriptors keep their aliases (the
        // footprint compares them); their initializer code is line-shifted.
        if (record.modified || old.modified) && !moved_only {
            return Err(format!("unit {identity:?} has modified instances"));
        }
        let (new_parts, old_parts) = (record.footprint(), old.footprint());
        if let Some(((name, _), _)) = new_parts
            .iter()
            .zip(&old_parts)
            .find(|((_, new), (_, old))| new != old)
        {
            return Err(format!("unit {identity:?} link footprint changed: {name}"));
        }
        let words = record
            .record
            .link_words(&link.tables, &link.mobs)
            .map_err(|error| format!("unit {identity:?} link: {error:?}"))?;
        push_row(&mut rows, crate::symbolic::unit_key(identity), words)?;
        for (key, words) in record
            .record
            .helper_words(&link.tables, &link.mobs)
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
        let shift = |path: &str, line: u32| lines.map(path, line as usize) as u32;
        let mut current = Vec::with_capacity(link.initializers.len());
        for code in &link.initializers {
            match code
                .relink_shifted(&link.tables, &link.mobs, &shift)
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
    dm_profile::request_mark("patch.linked");
    // Warnings exactly as a full build reports them: shifted declaration
    // warnings, current local warnings, then unit warnings in unit order.
    let mut warnings = (*base.warnings).clone();
    for warning in &mut warnings.prefix {
        if let Some(line) = warning.location.line.as_mut() {
            *line = lines.map(&warning.location.semantic_path, *line);
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
    let patched_rows = rows.len();
    let next = BodyPatchBase {
        shape: Arc::clone(shape),
        units: Arc::clone(&base.units),
        inputs: Arc::new(request.inputs),
        archive: request.archive,
        warnings: Arc::new(warnings),
        dmb_hash: 0,
    };
    // `patch_rows` stamps the new output hash before installing the base.
    let dmb = request
        .generation
        .patch_rows(&image, &rows, next, next_initializers)?;
    Ok(Patched {
        dmb,
        warnings: output_warnings,
        query: lowered.query,
        changed_bodies: changed.len(),
        shifted_initializers,
        patched_rows,
    })
}

/// Default-edit fast path (doc/structural_change_set.md, link/encode). The
/// frontend's in-place update proved every declaration change is a formal
/// var's default moving between numeric literals, from exactly the tree of
/// the patch base. Such an edit changes only those Variables-table values:
/// they are rewritten in the retained image, and every other stage is
/// skipped. Declines when any body or declaration names the var inside
/// `initial(...)` (a compile-time read of the default), when bodies, inputs
/// or the archive changed, or when the image record does not hold the old
/// numeric value.
fn try_default_patch<R: dm_ir::Resolver>(
    request: PatchRequest<'_, R>,
    base: &BodyPatchBase,
    image: &crate::composition::PatchImage,
) -> Result<Patched, String> {
    let frontend: &dm_tree::frontend::ColdFrontend = request.frontend;
    let edits = frontend
        .snapshot
        .tree
        .default_edits()
        .ok_or("not a pure numeric default edit")?;
    if edits.from_identity != base.shape.tree_identity {
        return Err("default edits are not relative to the patch base".into());
    }
    let shape = request.shape;
    if shape.bodies != base.shape.bodies {
        return Err("bodies changed with the defaults".into());
    }
    if let Some(difference) = request.inputs.non_text_difference(&base.inputs) {
        return Err(format!("non-text input changed: {difference}"));
    }
    if request.archive != base.archive {
        return Err("resource archive changed".into());
    }
    let text = frontend.expanded.text.as_str().as_bytes();
    let symbols = frontend.snapshot.tree.symbols();
    let mut values = Vec::with_capacity(edits.edits.len());
    for edit in &edits.edits {
        let name = symbols.text(edit.name).ok_or("edited var has no spelling")?;
        if reads_initial(text, name.as_bytes()) {
            return Err(format!("initial({name}) is read at compile time"));
        }
        let record = request
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
        values.push((record, 42u8, edit.value_bits));
    }
    // The query host (ABI and startup facts) of the current revision.
    let lowered = crate::cold::body_patch::lower_selected(
        frontend,
        request.resolver,
        crate::cold::body_patch::LinkFacts {
            engine_bytes: request.engine_bytes,
            engine: request.engine,
            references: request.references,
            spellings: request.spellings,
        },
        request.resource_search_context,
        crate::lowering::LoweringConfig {
            workers: request.workers,
            ..Default::default()
        },
        request.memo,
        Some(request.frontend),
        request.executor,
        &[],
    )?;
    let local = crate::local_warnings::capture(frontend)
        .map_err(|error| format!("local warnings: {error:?}"))?;
    let output_warnings = base.warnings.render(local);
    let next = BodyPatchBase {
        shape: Arc::clone(shape),
        units: Arc::clone(&base.units),
        inputs: Arc::new(request.inputs),
        archive: request.archive,
        warnings: Arc::clone(&base.warnings),
        dmb_hash: 0,
    };
    let dmb = request.generation.patch_variable_values(image, &values, next)?;
    crate::daemon_eprintln!("native default patch: {} variable records", values.len());
    Ok(Patched {
        dmb,
        warnings: output_warnings,
        query: lowered.query,
        changed_bodies: 0,
        shifted_initializers: 0,
        patched_rows: values.len(),
    })
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

#[cfg(test)]
mod tests {
    use super::*;
    fn body(path: &str, line: usize, lines: usize) -> BodyShape {
        BodyShape {
            digest: 0,
            text: 0,
            guarded: false,
            path: Arc::from(path),
            file: Arc::new(std::path::PathBuf::from(path)),
            line,
            lines,
        }
    }
    #[test]
    fn line_map_shifts_only_lines_below_resized_bodies_of_the_same_file() {
        let old = [body("a.dm", 10, 3), body("a.dm", 20, 2), body("b.dm", 5, 1)];
        let new = [body("a.dm", 10, 5), body("a.dm", 22, 1), body("b.dm", 5, 1)];
        let map = LineMap::between(&old, &new);
        assert_eq!(map.map("a.dm", 9), 9);
        assert_eq!(map.map("a.dm", 13), 13, "the resized body's own last line");
        assert_eq!(map.map("a.dm", 14), 16);
        assert_eq!(map.map("a.dm", 20), 22);
        assert_eq!(map.map("a.dm", 23), 24, "both deltas accumulate");
        assert_eq!(map.map("b.dm", 30), 30);
        assert!(LineMap::between(&old, &old).is_identity());
    }
    #[test]
    fn static_and_global_declarations_are_guarded_but_global_access_is_not() {
        assert!(declares_static(b"var/static/x = 1"));
        assert!(declares_static(b"var/global/list/x"));
        assert!(!declares_static(b"return global.x"));
        assert!(!declares_static(b"var/globalish = 1; staticky()"));
    }
}

/// Applied patches per project (test and diagnostic observation only).
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

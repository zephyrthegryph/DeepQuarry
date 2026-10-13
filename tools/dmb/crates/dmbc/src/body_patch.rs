//! Body-edit fast path for retained (daemon) builds.
//!
//! When an edit changes only procedure bodies, the declaration skeleton, every
//! non-text input and every table assignment of the previous build stay valid.
//! The fast path then lowers only the changed bodies, links each one against
//! the retained link tables, and splices the new code lists into the retained
//! output model and its certified image. Everything else (initializers, class
//! projection, required-type admission, whole-program linking, composition and
//! encoding) is skipped. The result must equal a fresh full build byte for
//! byte; every condition below that cannot be proven declines the patch with a
//! logged reason, and the ordinary full path runs.
//!
//! Admission, in order:
//! 1. A patch base exists: the previous successful build of this session left
//!    its source shape, per-unit footprints, link tables, inputs and the hash
//!    of the generation it describes.
//! 2. The declaration skeleton is unchanged: the expanded text outside bodies,
//!    each body's file, start line and line count, and the file roster.
//! 3. No input other than `.dm`/`.dme` text changed (content), no resource
//!    search folder changed, and the resource archive identity is unchanged.
//! 4. Changed bodies (by expanded text and source position) are few, none of
//!    them (before or after) declares a proc-static or global var, and none is
//!    the first root procedure (whose literals register strings early).
//! 5. Each relowered unit has the same link footprint as before (frame, ABI,
//!    features, warnings, inventory entry/slots/strings, value strings, debug
//!    paths, instances, helpers, required types, no modified instances) and
//!    neither version carries warnings.
use crate::lowering::UnitIdentity;
use std::collections::BTreeMap;
use std::sync::Arc;
use xxhash_rust::xxh3::Xxh3;

/// At most this many relowered bodies are patched; more fall back.
const PATCH_LIMIT: usize = 512;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct BodyShape {
    digest: u128,
    /// Declares a proc-static or global var: startup facts depend on it.
    guarded: bool,
}

/// Declaration skeleton plus one digest per body, in `frontend.bodies` order.
pub struct SourceShape {
    skeleton: u128,
    bodies: Vec<BodyShape>,
}

fn word_at(text: &[u8], at: usize, word: &[u8]) -> bool {
    let before = at == 0 || !(text[at - 1].is_ascii_alphanumeric() || text[at - 1] == b'_');
    let end = at + word.len();
    let after = end >= text.len() || !(text[end].is_ascii_alphanumeric() || text[end] == b'_');
    before && after
}

/// Conservative: any `static` word, or a `global` word not used as `global.x`.
fn declares_static(text: &[u8]) -> bool {
    for (word, member_access_ok) in [(&b"static"[..], false), (&b"global"[..], true)] {
        let mut from = 0;
        while let Some(found) = text[from..]
            .windows(word.len())
            .position(|window| window == word)
        {
            let at = from + found;
            if word_at(text, at, word) {
                let next = text[at + word.len()..]
                    .iter()
                    .find(|byte| !byte.is_ascii_whitespace());
                if !(member_access_ok && next == Some(&b'.')) {
                    return true;
                }
            }
            from = at + word.len();
        }
    }
    false
}

impl SourceShape {
    pub fn capture(frontend: &dm_tree::frontend::ColdFrontend) -> Self {
        let _profile = dm_profile::stage("body_patch.source_shape");
        let text = frontend.expanded.text.as_str().as_bytes();
        let bodies = &frontend.bodies;
        let mut order: Vec<usize> = (0..bodies.len()).collect();
        order.sort_by_key(|&index| {
            let span = bodies[index].expanded_span;
            (span.start, span.end)
        });
        let mut skeleton = Xxh3::new();
        skeleton.update(b"dmb-body-patch-skeleton-v1\0");
        for file in frontend.files.iter() {
            skeleton.update(file.path.to_string_lossy().as_bytes());
            skeleton.update(&[0, u8::from(file.captured)]);
        }
        let mut through = 0usize;
        for &index in &order {
            let body = &bodies[index];
            let span = body.expanded_span.range();
            let start = span.start.min(text.len());
            let end = span.end.min(text.len());
            if start >= through {
                skeleton.update(&((start - through) as u64).to_le_bytes());
                skeleton.update(&text[through..start]);
            }
            let lines = text[start..end].iter().filter(|&&byte| byte == b'\n').count();
            skeleton.update(body.source.semantic_path.as_bytes());
            skeleton.update(&(body.source.line as u64).to_le_bytes());
            skeleton.update(&(lines as u64).to_le_bytes());
            through = through.max(end);
        }
        skeleton.update(&text[through.min(text.len())..]);
        let shapes = bodies
            .iter()
            .map(|body| {
                let span = body.expanded_span.range();
                let start = span.start.min(text.len());
                let end = span.end.min(text.len()).max(start);
                let body_text = &text[start..end];
                let source = &body.source;
                let mut hash = Xxh3::new();
                hash.update(&(body_text.len() as u64).to_le_bytes());
                hash.update(body_text);
                hash.update(source.path.to_string_lossy().as_bytes());
                hash.update(b"\0");
                hash.update(source.semantic_path.as_bytes());
                hash.update(b"\0");
                for value in [
                    source.line,
                    source.encounter_ordinal,
                    source.include_occurrence,
                    body.declaration.0 as usize,
                ] {
                    hash.update(&(value as u64).to_le_bytes());
                }
                hash.update(format!("{:?}{:?}", source.include_chain, body.member).as_bytes());
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
                    guarded: declares_static(body_text),
                }
            })
            .collect();
        Self {
            skeleton: skeleton.digest128(),
            bodies: shapes,
        }
    }
}

/// Source half of a retained generation's patch base (the link half is held
/// by the generation itself; see `composition::RetainedGeneration`).
pub struct BodyPatchBase {
    shape: Arc<SourceShape>,
    units: Arc<BTreeMap<UnitIdentity, crate::symbolic::PreparedPatchRecord>>,
    inputs: Arc<crate::input_snapshot::InputSnapshot>,
    archive: crate::publish::ResourceIdentity,
    warnings: Arc<Vec<crate::initializer_policy::warnings::InitializerWarning>>,
    dmb_hash: u128,
}
impl BodyPatchBase {
    /// Base of a completed full build.
    pub(crate) fn of_full_build(
        shape: Arc<SourceShape>,
        records: Vec<crate::symbolic::PreparedPatchRecord>,
        inputs: crate::input_snapshot::InputSnapshot,
        archive: crate::publish::ResourceIdentity,
        warnings: Vec<crate::initializer_policy::warnings::InitializerWarning>,
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
}

impl BodyPatchBase {
    pub(crate) fn with_output_hash(mut self, hash: u128) -> Self {
        self.dmb_hash = hash;
        self
    }
}

/// A patched output, ready for the ordinary publication path.
pub(crate) struct Patched {
    pub dmb: byond_dmb::dmb::EncodedDmb,
    pub warnings: Vec<crate::initializer_policy::warnings::InitializerWarning>,
    pub query: (
        Arc<crate::driver_facts::PreparedAbiUnits>,
        Arc<crate::startup::StartupFacts>,
    ),
    pub changed_bodies: usize,
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
    if shape.skeleton != base.shape.skeleton || shape.bodies.len() != base.shape.bodies.len() {
        return Err("declaration skeleton changed".into());
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
    if changed.len() > PATCH_LIMIT {
        return Err(format!("{} bodies changed (limit {PATCH_LIMIT})", changed.len()));
    }
    let frontend: &dm_tree::frontend::ColdFrontend = request.frontend;
    for &index in &changed {
        if shape.bodies[index].guarded || base.shape.bodies[index].guarded {
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
    let mut rows = Vec::with_capacity(lowered.contributions.len());
    for contribution in &lowered.contributions {
        let record = contribution.patch_record();
        let identity = record.record.identity();
        let old = base
            .units
            .get(&identity)
            .ok_or_else(|| format!("unit {identity:?} absent from the patch base"))?;
        if record.record.has_warnings() || old.record.has_warnings() {
            return Err(format!("unit {identity:?} carries warnings"));
        }
        if record.modified || old.modified {
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
        byond_dmb::bytecode::visit_instructions(&words, |_| {}, |_| {})
            .map_err(|error| format!("unit {identity:?} bytecode: {error:?}"))?;
        let index = link
            .tables
            .index(crate::symbolic::unit_key(identity))
            .ok_or_else(|| format!("unit {identity:?} has no procedure index"))?;
        let code = image
            .proc_code
            .get(index as usize)
            .map(|&code| code as usize)
            .filter(|&code| code < image.rows.len())
            .ok_or_else(|| format!("unit {identity:?} has no retained code list"))?;
        if !image.rows.row_equals(code, &words) {
            rows.push((code, words));
        }
    }
    dm_profile::request_mark("patch.linked");
    let patched_rows = rows.len();
    let next = BodyPatchBase {
        shape: Arc::clone(shape),
        units: Arc::clone(&base.units),
        inputs: Arc::new(request.inputs),
        archive: request.archive,
        warnings: Arc::clone(&base.warnings),
        dmb_hash: 0,
    };
    // `patch_rows` stamps the new output hash before installing the base.
    let dmb = request.generation.patch_rows(&image, &rows, next)?;
    Ok(Patched {
        dmb,
        warnings: (*base.warnings).clone(),
        query: lowered.query,
        changed_bodies: changed.len(),
        patched_rows,
    })
}

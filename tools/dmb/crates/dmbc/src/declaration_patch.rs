//! Declaration patches for retained (daemon) builds: an edit that only added procs or verbs
//! (`declaration_patch_append.rs`) or only moved a formal var's default between numeric literals
//! (`try_default_patch`) is applied to the retained output image without compiling the whole
//! program. These are special cases the general path (`crate::cold`, `crate::retained_output`)
//! has not absorbed yet; each is deleted once the general path matches it. Every condition that
//! cannot be proven declines with a logged reason, and the general path runs.
use crate::retained_output::{first_root_body, word_at, OutputBase, Patched, SourceShape};
use std::collections::HashMap;
use std::sync::Arc;

#[path = "declaration_patch_append.rs"]
mod append;

/// At most this many relowered bodies are patched; more fall back.
const PATCH_LIMIT: usize = 4096;

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

/// Try a declaration patch. `Err` carries the reason it declined; the caller logs it and runs
/// the general path. No state is changed unless `Ok` is returned.
pub(crate) fn try_patch<R: dm_ir::Resolver>(request: PatchRequest<'_, R>) -> Result<Patched, String> {
    let tree = &request.frontend.snapshot.tree;
    if tree.appended_callables().is_none() && tree.default_edits().is_none() {
        return Err("not a declaration patch".into());
    }
    let (base, link, image) = request
        .generation
        .patch_base()
        .ok_or("no patch base retained")?;
    if base.dmb_hash != image.rows.image().content_hash() {
        return Err("retained output differs from the patch base".into());
    }
    if tree.appended_callables().is_some() {
        return append::try_append_patch(request, &base, &link, &image)
            .map_err(|reason| format!("append patch: {reason}"));
    }
    try_default_patch(request, &base, &image).map_err(|reason| format!("default patch: {reason}"))
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
    base: &OutputBase,
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
    if let Some(difference) = request.inputs.non_text_difference_with(&base.inputs, request.archive != base.archive) {
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
    let lowered = crate::cold::selected_lowering::lower_selected(
        frontend,
        request.resolver,
        crate::cold::selected_lowering::LinkFacts {
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
    let next = OutputBase {
        shape: Arc::clone(shape),
        units: Arc::clone(&base.units),
        inputs: Arc::new(request.inputs),
        archive: request.archive,
        warnings: Arc::clone(&base.warnings),
        answers: lowered.answers,
        answers_context: None,
        marks: None,
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

/// Applied declaration patches per project (test and diagnostic observation only).
static APPLIED: std::sync::Mutex<std::collections::BTreeMap<std::path::PathBuf, u64>> =
    std::sync::Mutex::new(std::collections::BTreeMap::new());
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

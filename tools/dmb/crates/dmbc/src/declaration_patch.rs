//! The appended-callable patch for retained (daemon) builds: an edit that only added procs or verbs
//! (`declaration_patch_append.rs`) is applied to the retained output image without compiling the
//! whole program. It is a special case the general path (`crate::cold`, `crate::retained_output`)
//! has not absorbed yet; it is deleted once the general path matches it. (Numeric default edits
//! are no longer special: `retained_output::admit` takes them.) Every condition that
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
    pub project: &'a std::path::Path,
}

/// Try a declaration patch. `Err` carries the reason it declined; the caller logs it and runs
/// the general path. No state is changed unless `Ok` is returned.
pub(crate) fn try_patch<R: dm_ir::Resolver>(request: PatchRequest<'_, R>) -> Result<Patched, String> {
    let tree = &request.frontend.snapshot.tree;
    if tree.appended_callables().is_none() {
        return Err("not an appended-callable patch".into());
    }
    let (base, link, image) = request
        .generation
        .patch_base()
        .ok_or("no patch base retained")?;
    if base.dmb_hash != image.rows.image().content_hash() {
        return Err("retained output differs from the patch base".into());
    }
    append::try_append_patch(request, &base, &link, &image)
        .map_err(|reason| format!("append patch: {reason}"))
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

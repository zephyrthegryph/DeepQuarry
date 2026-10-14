//! Opt-in quiescent retained semantic ownership; never an admission input.
use std::io::{self, Write};
pub(crate) fn emit_frontend(
    frontend: &dm_tree::frontend::FrontendRevision,
    state: Option<&dm_tree::frontend::RetainedSemanticTree>,
    memo: Option<&dyn dm_preprocess::regions::ExpansionMemo>,
    prepared: Option<&crate::input_snapshot::PreparedInputArtifacts>,
) -> io::Result<()> {
    crate::heap_census::emit_if_enabled("frontend.ready", |census| {
        census.frontend(frontend);
        census.retained_frontend_owners(state, memo.and_then(|memo| memo.input_admissions()), prepared);
    })
}
pub(crate) fn emit(state: Option<&dm_tree::frontend::RetainedSemanticTree>) -> io::Result<()> {
    let Some(path) = std::env::var_os("DMB_HEAP_CENSUS_PATH").filter(|path| !path.is_empty()) else {
        return Ok(());
    };
    let Some(state) = state else { return Ok(()) };
    let report = crate::heap_census::retained_declaration_census(state);
    let mut file = std::fs::OpenOptions::new().create(true).append(true).open(path)?;
    serde_json::to_writer(&mut file, &report).map_err(io::Error::other)?;
    file.write_all(b"\n")
}

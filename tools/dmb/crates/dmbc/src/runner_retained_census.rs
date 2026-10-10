//! Opt-in quiescent retained semantic ownership; never an admission input.
use std::io::{self, Write};
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

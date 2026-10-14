//! Explicit caller-owned output names; source reads remain fully authenticated.
use crate::request::BuildCommand;
use std::path::{Path, PathBuf};

pub(super) fn paths(
    project: &Path,
    output_project: &Path,
    command: BuildCommand,
    output_store: Option<&Path>,
    artifacts: Option<&Path>,
    recording: Option<&Path>,
    cache: Option<&Path>,
    trace: Option<&Path>,
) -> std::io::Result<Vec<PathBuf>> {
    let mut result = Vec::new();
    // This directory is the compiler's session and telemetry namespace.
    result.push(
        project
            .parent()
            .ok_or_else(|| std::io::Error::other("manifest parent missing"))?
            .join(".dmbc"),
    );
    if command == BuildCommand::Compile {
        // Prepared RSC installation lives in a reserved namespace beside the
        // destination, including externally routed artifact directories.
        if let Some(parent) = output_project.parent() {
            result.push(parent.join(".dmbc"));
        }
        for extension in ["dmb", "rsc", "dmb-pair.json"] {
            result.push(output_project.with_extension(extension));
        }
        result.push(match output_store {
            Some(path) => path.to_path_buf(),
            None => crate::publish::default_store_path(project)?,
        });
    }
    result.extend(
        [artifacts, recording, cache, trace]
            .into_iter()
            .flatten()
            .map(Path::to_path_buf),
    );
    Ok(result)
}

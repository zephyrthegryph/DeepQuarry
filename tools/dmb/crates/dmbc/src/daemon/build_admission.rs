//! A wire request has no caller working directory. Never resolve it against
//! the daemon's launch directory (which may belong to a different worktree).
use crate::{request::BuildRequest, request_failure::RequestFailure};
use std::path::Path;

pub(super) fn validate(request: &BuildRequest) -> Result<(), RequestFailure> {
    fn absolute(name: &str, path: &Path) -> Result<(), RequestFailure> {
        if path.is_absolute() {
            return Ok(());
        }
        Err(RequestFailure::invalid_request(format!(
            "daemon build {name} must be an absolute caller-resolved path"
        )))
    }
    absolute("project", &request.project)?;
    for (name, path) in [
        ("engine_template", &request.engine_template),
        ("output_store", &request.output_store),
        ("cache_root", &request.cache_root),
        ("record_inputs", &request.record_inputs),
        ("replay_inputs", &request.replay_inputs),
        ("artifact_directory", &request.artifact_directory),
        ("trace_path", &request.trace_path),
    ] {
        if let Some(path) = path {
            absolute(name, path)?;
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::request::BuildCommand;
    use std::collections::BTreeMap;
    use std::path::PathBuf;
    fn absolute_path(name: &str) -> PathBuf {
        std::env::temp_dir()
            .join("dmb-admission-fixture")
            .join(name)
    }
    fn request() -> BuildRequest {
        BuildRequest {
            command: BuildCommand::Compile,
            project: absolute_path("world.dme"),
            defines: BTreeMap::new(),
            workers: 2,
            engine_template: None,
            bootstrap_catalog: false,
            progress_enabled: false,
            output_store: None,
            exact_inputs: false,
            no_cache: false,
            cache_root: None,
            record_inputs: None,
            replay_inputs: None,
            artifact_directory: None,
            no_daemon: false,
            trace_path: None,
            warnings: Default::default(),
        }
    }
    #[test]
    fn supplied_paths_must_be_caller_absolute_before_build_admission() {
        let base = request();
        assert!(validate(&base).is_ok());
        for field in 0..8 {
            let mut current = base.clone();
            let relative = PathBuf::from("other-worktree/input");
            match field {
                0 => current.project = relative,
                1 => current.engine_template = Some(relative),
                2 => current.output_store = Some(relative),
                3 => current.cache_root = Some(relative),
                4 => current.record_inputs = Some(relative),
                5 => current.replay_inputs = Some(relative),
                6 => current.artifact_directory = Some(relative),
                _ => current.trace_path = Some(relative),
            }
            assert_eq!(validate(&current).unwrap_err().kind.exit_code(), 64);
        }
    }
    #[test]
    fn absolute_optional_paths_preserve_exact_request_configuration() {
        let mut current = request();
        current.engine_template = Some(absolute_path("engine.dmb"));
        current.output_store = Some(absolute_path("store"));
        current.cache_root = Some(absolute_path("cache"));
        current.record_inputs = Some(absolute_path("record"));
        current.replay_inputs = Some(absolute_path("replay"));
        current.artifact_directory = Some(absolute_path("outputs"));
        current.trace_path = Some(absolute_path("trace.json"));
        let before = current.clone();
        validate(&current).unwrap();
        assert_eq!(current, before);
    }
    #[cfg(windows)]
    #[test]
    fn windows_drive_absolute_and_unc_paths_are_accepted_without_io() {
        for path in [r"E:\worktree\world.dme", r"\\server\share\world.dme"] {
            let mut current = request();
            current.project = PathBuf::from(path);
            validate(&current).unwrap();
        }
    }
    #[cfg(windows)]
    #[test]
    fn windows_drive_relative_and_root_relative_paths_are_not_absolute() {
        for path in ["E:world.dme", "\\world.dme"] {
            let mut current = request();
            current.project = PathBuf::from(path);
            assert!(validate(&current).is_err());
        }
    }
}

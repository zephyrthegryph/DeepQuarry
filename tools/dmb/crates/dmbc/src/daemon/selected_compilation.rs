//! Explicit compound request. Only the existing selected Original roster and
//! the same manifest's ordinary live no-cache compile can serve it.
use super::{protocol, selected_exclusions::{Mode, Request as SelectedRequest}, selected_report_wire as wire, transport};
use crate::{input_snapshot::{FileSystemInputs, SnapshotProvider}, publish::OutputPair, request::{BuildCommand, BuildRequest}, runner_host::BuildHost};
use serde::{Deserialize, Serialize};
use std::{error::Error, fs::{self, File}, io::{self, Read}, path::{Path, PathBuf}};

const MAX_REQUEST: u64 = 64 * 1024;
const MAX_PAIR_MARKER: u64 = 1024;

#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(super) struct Request {
    pub(super) selected: SelectedRequest,
    pub(super) output_name: String,
}

pub(super) struct Destination {
    cache: PathBuf,
    root: PathBuf,
    store: PathBuf,
    artifacts: PathBuf,
}
fn invalid(message: &'static str) -> io::Error { io::Error::new(io::ErrorKind::InvalidInput, message) }

impl Destination {
    pub(super) fn admit(prepare: &BuildRequest, output_name: &str) -> io::Result<Self> {
        let suffix = output_name.strip_prefix("compound-").unwrap_or("");
        if suffix.is_empty() || suffix.len() > 48 || !suffix.bytes().all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-') {
            return Err(invalid("compound output requires a fresh compound- name under the external cache"));
        }
        if !prepare.no_cache || prepare.warnings != crate::diagnostics::WarningPolicy::default() {
            return Err(invalid("compound request requires explicit no-cache and default warning settings"));
        }
        let (workspace, cache) = BuildHost::original_exclusions_paths(prepare)?;
        let workspace = fs::canonicalize(workspace)?;
        if workspace.starts_with(&cache) {
            return Err(invalid("compound cache must be disjoint from the workspace"));
        }
        let root = cache.join(output_name);
        match fs::symlink_metadata(&root) {
            Err(error) if error.kind() == io::ErrorKind::NotFound => {}
            Ok(_) => return Err(io::Error::new(io::ErrorKind::AlreadyExists, "compound output directory already exists")),
            Err(error) => return Err(error),
        }
        Ok(Self { cache, store: root.join("store"), artifacts: root.join("artifacts"), root })
    }

    pub(super) fn compile(&self, prepare: &BuildRequest) -> BuildRequest {
        let mut native = prepare.clone();
        native.command = BuildCommand::Compile;
        native.policy_inputs = None;
        native.output_store = Some(self.store.clone());
        native.artifact_directory = Some(self.artifacts.clone());
        native
    }

    /// Claim exactly this new destination after Accepted, before either phase.
    /// Keep the ordinary publication directory guards alive across the build.
    pub(super) fn claim(&self) -> io::Result<[crate::frozen_inputs::GenerationAncestorGuard; 3]> {
        let cache = crate::frozen_inputs::generation_publication_guard(&self.cache, &self.cache)?;
        fs::create_dir(&self.root)?;
        fs::create_dir(&self.store)?;
        fs::create_dir(&self.artifacts)?;
        let store = crate::frozen_inputs::generation_publication_guard(&self.store, &self.cache)?;
        let artifacts = crate::frozen_inputs::generation_publication_guard(&self.artifacts, &self.cache)?;
        Ok([cache, store, artifacts])
    }

    pub(super) fn require_published(&self, outcome: &crate::request::BuildOutcome) -> io::Result<()> {
        let crate::request::BuildOutcome::Published { output_project, store, session_hit: false, .. } = outcome else {
            return Err(invalid("compound native result did not publish an exact pair"));
        };
        if output_project != &self.artifacts.join("deepquarry.dme") || store != &self.store {
            return Err(invalid("compound native publication destination differs"));
        }
        Ok(())
    }

    fn verify_installed(&self, pair: &OutputPair) -> io::Result<()> {
        let _store = crate::frozen_inputs::generation_ancestor_guard(&self.store, &self.cache)?;
        let _artifacts = crate::frozen_inputs::generation_ancestor_guard(&self.artifacts, &self.cache)?;
        if crate::publish::PairStore::open(&self.store)?.verify(pair.id, true)? != *pair {
            return Err(invalid("compound native store pair differs from the terminal"));
        }
        let marker = self.artifacts.join("deepquarry.dmb-pair.json");
        let mut bytes = Vec::new();
        require_regular_file(&marker)?;
        File::open(marker)?.take(MAX_PAIR_MARKER + 1).read_to_end(&mut bytes)?;
        if bytes.len() as u64 > MAX_PAIR_MARKER || serde_json::from_slice::<OutputPair>(&bytes).map_err(io::Error::other)? != *pair {
            return Err(invalid("compound native installation marker differs from the terminal"));
        }
        for (name, len, hash) in [("deepquarry.dmb", pair.dmb_bytes, pair.dmb_hash), ("deepquarry.rsc", pair.rsc_bytes, pair.rsc_hash)] {
            let path = self.artifacts.join(name);
            require_regular_file(&path)?;
            let (stamp, content) = FileSystemInputs.digest(&path)?;
            if stamp.size != len || content != hash {
                return Err(invalid("compound installed artifact differs from the terminal"));
            }
        }
        Ok(())
    }
}

fn require_regular_file(path: &Path) -> io::Result<()> {
    let metadata = fs::symlink_metadata(path)?;
    if !metadata.is_file() || metadata.file_type().is_symlink() {
        return Err(invalid("compound destination is not an installed regular file"));
    }
    #[cfg(windows)]
    {
        use std::os::windows::fs::MetadataExt;
        if metadata.file_attributes() & 0x400 != 0 {
            return Err(invalid("compound destination is a reparse point"));
        }
    }
    Ok(())
}

pub fn run_file(path: &Path) -> Result<bool, Box<dyn Error>> {
    let mut bytes = Vec::new();
    File::open(path)?.take(MAX_REQUEST + 1).read_to_end(&mut bytes)?;
    if bytes.len() as u64 > MAX_REQUEST { return Err(invalid("compound request exceeds its control bound").into()); }
    let request: Request = serde_json::from_slice(&bytes)?;
    drop(bytes);
    let roster = request.selected.qualify(Mode::Combined)?;
    super::build_admission::validate(&request.selected.build)?;
    let destination = Destination::admit(&request.selected.build, &request.output_name)?;
    let mut stream = super::connect_generation()?;
    transport::set_timeout(&mut stream, transport::BUILD_DEADLINE)?;
    protocol::send(&mut stream, &protocol::Request::CompileSelectedReports(request))?;
    let delivered = wire::receive_compilation(&mut stream, &destination.cache, roster, |pair| destination.verify_installed(pair))
        .map_err(|error| {
            if error.is::<crate::request_failure::RequestFailure>() { return error; }
            io::Error::other(format!("compound delivery failed; native installation may have completed: {error}")).into()
        })?;
    Ok(delivered.publish(&mut io::stderr().lock(), &mut io::stdout().lock())?)
}

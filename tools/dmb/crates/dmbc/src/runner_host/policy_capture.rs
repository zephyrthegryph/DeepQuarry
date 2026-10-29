//! Explicit raw-policy capture through the compiler request's existing ledger.
//! Unwired integration helper: this does not crawl or certify a workspace. Its
//! directory/absence facts cover only requested paths and search folders.
use crate::input_snapshot::{InputSnapshot, RecordingInputs, SnapshotProvider};
use dm_analysis::policy_inputs::{HostCapture, PolicyInputs, PolicyRole};
use dm_preprocess::{regions::canonical_path, SourceText};
use dm_resources::capture::CaptureProvider;
use dm_tree::frontend::ColdFrontend;
use std::{
    collections::BTreeMap,
    io,
    path::{Path, PathBuf},
    sync::Arc,
};

#[derive(Clone)]
pub(crate) struct RequestedPolicyFile {
    pub path: PathBuf,
    pub role: PolicyRole,
    /// Missing optional files still become negative facts in the same ledger.
    pub required: bool,
}

/// Retains content views beside their recorded file/directory/absence proof.
/// `PolicyInputs::revision()` fingerprints text only; consumers must bind these
/// complete captured facts as well when caching decisions about missing files.
pub(crate) struct CapturedPolicyInputs {
    policy: PolicyInputs,
    facts: InputSnapshot,
    missing: Vec<PathBuf>,
    explicit_search_folders: Vec<PathBuf>,
    policy_revision: Option<u128>,
    configuration_bytes: BTreeMap<PathBuf, Option<dm_resources::SharedBytes>>,
}
/// Retention admission for this bounded migration capture, not a process-RSS
/// or peak-read-allocation guarantee. SourceText owners can be shared, so the
/// conservative view charge deliberately may count one owner more than once.
pub(crate) const MAX_POLICY_CAPTURE_CHARGE: usize = 64 * 1024 * 1024;
impl CapturedPolicyInputs {
    pub(crate) fn bind_request(
        mut self,
        request: &crate::policy_request::AdmittedPolicyRequest,
    ) -> io::Result<Self> {
        if request.search_folders() != self.explicit_search_folders.as_slice() {
            return Err(io::Error::other(
                "captured explicit search scope differs from policy request",
            ));
        }
        // Existing present bytes prove either optional or required admission.
        // Missing paths remain optional-only and retain their exact role below.
        for file in request.files() {
            let role = match file.role {
                crate::policy_request::PolicyInputRole::DmSource => PolicyRole::DmSource,
                crate::policy_request::PolicyInputRole::Configuration => PolicyRole::Configuration,
            };
            match self.policy.file(&file.path) {
                Some(captured) if captured.role() == role => (),
                None if !file.required
                    && self.missing.contains(&file.path)
                    && match role {
                        PolicyRole::Configuration => self
                            .configuration_bytes
                            .get(&file.path)
                            .is_some_and(|bytes| bytes.is_none()),
                        PolicyRole::DmSource => !self.configuration_bytes.contains_key(&file.path),
                    } =>
                {
                    ()
                }
                _ => {
                    return Err(io::Error::other(
                        "policy request is not proven by captured inputs",
                    ))
                }
            }
        }
        // The request must explain the entire explicit scope, not merely a
        // subset of a more permissive capture. Compiler members are implicit;
        // noncompiled files and missing paths need exact admitted intent.
        for file in self.policy.files().filter(|file| !file.is_compiled()) {
            if !request.files().iter().any(|wanted| {
                wanted.path.as_path() == file.path().as_path()
                    && match wanted.role {
                        crate::policy_request::PolicyInputRole::DmSource => {
                            file.role() == PolicyRole::DmSource
                        }
                        crate::policy_request::PolicyInputRole::Configuration => {
                            file.role() == PolicyRole::Configuration
                        }
                    }
            }) {
                return Err(io::Error::other(
                    "captured noncompiled policy file is not requested",
                ));
            }
        }
        for path in &self.missing {
            if !request
                .files()
                .iter()
                .any(|wanted| wanted.path == *path && !wanted.required)
            {
                return Err(io::Error::other(
                    "captured missing policy path is not requested",
                ));
            }
        }
        if request
            .search_folders()
            .iter()
            .any(|folder| !self.facts.folders().contains_key(folder))
        {
            return Err(io::Error::other("policy search folder is not recorded"));
        }
        self.policy_revision = Some(crate::policy_request::captured_revision(
            self.policy.revision().policy_inputs,
            &self.facts,
            request,
        )?);
        Ok(self)
    }
    pub(crate) fn policy_revision(&self) -> Option<u128> {
        self.policy_revision
    }

    pub fn policy(&self) -> &PolicyInputs {
        &self.policy
    }
    pub fn facts(&self) -> &InputSnapshot {
        &self.facts
    }
    pub(crate) fn explicit_search_folders(&self) -> &[PathBuf] {
        &self.explicit_search_folders
    }
    pub fn missing_paths(&self) -> &[PathBuf] {
        &self.missing
    }
    /// Exact authenticated configuration payload. Missing is returned ONLY for
    /// a requested optional Configuration path whose absence was recorded.
    /// Unrequested/wrong-role paths are errors, never permission to default.
    pub fn configuration_bytes(&self, path: &Path) -> io::Result<Option<&[u8]>> {
        let path = canonical_path(path);
        match self.configuration_bytes.get(&path) {
            Some(Some(bytes))
                if self
                    .policy
                    .file(&path)
                    .is_some_and(|file| file.role() == PolicyRole::Configuration) =>
            {
                Ok(Some(bytes.as_slice()))
            }
            Some(None) if self.missing.contains(&path) => Ok(None),
            _ => Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "configuration path is not admitted with a captured configuration role/absence",
            )),
        }
    }
    pub(crate) fn visit_configuration_bytes(
        &self,
        mut visit: impl FnMut(&PathBuf, Option<&dm_resources::SharedBytes>),
    ) {
        for (path, bytes) in &self.configuration_bytes {
            visit(path, bytes.as_ref());
        }
    }
    /// Later resource reads can extend the same request ledger. Replay admits
    /// only a full ledger that already contains every captured policy fact.
    pub fn is_recorded_in(&self, complete: &InputSnapshot) -> bool {
        let mut combined = complete.clone();
        combined.merge(&self.facts).is_ok() && combined.same_recorded_facts(complete)
    }
    pub fn budget_charge(&self) -> usize {
        let mut charge = 4096usize;
        charge = charge.saturating_add(
            self.explicit_search_folders
                .capacity()
                .saturating_mul(std::mem::size_of::<PathBuf>()),
        );
        for folder in &self.explicit_search_folders {
            charge = charge.saturating_add(folder.as_os_str().as_encoded_bytes().len());
        }
        for file in self.policy.files() {
            charge = charge
                .saturating_add(256)
                .saturating_add(file.path().as_os_str().as_encoded_bytes().len());
            for (_, text) in file.views() {
                charge = charge.saturating_add(64).saturating_add(text.len());
            }
        }
        for (path, bytes) in &self.configuration_bytes {
            charge = charge
                .saturating_add(128)
                .saturating_add(path.as_os_str().as_encoded_bytes().len())
                .saturating_add(
                    bytes
                        .as_ref()
                        .map_or(0, dm_resources::SharedBytes::capacity),
                );
        }
        self.facts
            .visit_recorded_storage(|files, folders, negative, generated| {
                for file in files.values() {
                    charge = charge.saturating_add(192).saturating_add(
                        file.path
                            .as_os_str()
                            .as_encoded_bytes()
                            .len()
                            .saturating_mul(2),
                    );
                }
                for (path, listing) in folders {
                    charge = charge
                        .saturating_add(128)
                        .saturating_add(path.as_os_str().as_encoded_bytes().len());
                    if let crate::input_snapshot::FolderListing::Present(names) = listing {
                        for name in names {
                            charge = charge.saturating_add(32).saturating_add(name.len());
                        }
                    }
                }
                for path in negative.iter().chain(generated.iter()) {
                    charge = charge
                        .saturating_add(96)
                        .saturating_add(path.as_os_str().as_encoded_bytes().len());
                }
            });
        for path in &self.missing {
            charge = charge
                .saturating_add(32)
                .saturating_add(path.as_os_str().as_encoded_bytes().len());
        }
        charge
    }
}

/// Call before completing the request's InputSnapshot, using the SAME
/// RecordingInputs that supplied the compiler frontend. This reads bytes but
/// never parses more DM or manufactures compiled membership. Callers explicitly
/// request policy-only DM/config and search folders; no recursive coverage claim.
pub(crate) fn capture<P: SnapshotProvider>(
    frontend: &ColdFrontend,
    inputs: &RecordingInputs<P>,
    requested: &[RequestedPolicyFile],
    search_folders: &[PathBuf],
) -> io::Result<CapturedPolicyInputs> {
    let initial = inputs.snapshot()?;
    let raw_digests: BTreeMap<_, _> = initial
        .files()
        .map(|file| (file.path.as_path(), file.content))
        .collect();
    let mut sources = BTreeMap::new();
    let mut requests = BTreeMap::new();
    for file in frontend.files.iter().filter(|file| file.captured) {
        let path = canonical_path(file.path.as_ref());
        let content = raw_digests.get(path.as_path()).copied().ok_or_else(|| {
            io::Error::other("policy capture lacks compiler's recorded source fact")
        })?;
        sources.insert(path.clone(), (&file.text, content));
        requests.insert(
            path.clone(),
            RequestedPolicyFile {
                path,
                role: PolicyRole::DmSource,
                required: true,
            },
        );
    }
    for request in requested {
        let path = canonical_path(&request.path);
        if let Some(previous) = requests.get_mut(&path) {
            if previous.role != request.role {
                return Err(io::Error::other("policy path has contradictory roles"));
            }
            previous.required |= request.required;
        } else {
            requests.insert(
                path.clone(),
                RequestedPolicyFile {
                    path,
                    ..request.clone()
                },
            );
        }
    }
    let explicit_search_folders = search_folders
        .iter()
        .map(|folder| canonical_path(folder))
        .collect::<std::collections::BTreeSet<_>>()
        .into_iter()
        .collect::<Vec<_>>();
    for folder in &explicit_search_folders {
        inputs.record_search_folder(folder)?;
    }
    let mut extra = Vec::new();
    let mut missing = Vec::new();
    let mut configuration_bytes = BTreeMap::new();
    for (path, request) in requests {
        if let Some((compiled, raw_content)) = sources.get(&path) {
            let raw = if compiled.span_fingerprint(0..compiled.len())==Some(*raw_content) {
                if compiled.as_bytes().contains(&b'\r'){analyze_raw(compiled.as_bytes())}else{SourceText::clone(compiled)}
            } else {
                let original=inputs.exceptional_source_bytes(&path)?.ok_or_else(||io::Error::other(
                    "compiled source original byte view was not retained at acquisition"))?;
                if xxhash_rust::xxh3::xxh3_128(original.as_slice())!=*raw_content
                    ||dm_preprocess::decode_source_bytes(original.as_slice())!=compiled.as_str() {
                    return Err(io::Error::other("exceptional original source contradicts compiler capture"));
                }
                analyze_raw(original.as_slice())
            };
            let parent=path.parent().ok_or_else(||io::Error::other("compiled policy source has no parent"))?;
            inputs.record_search_folder(parent)?;
            let path=Arc::new(path);
            extra.push(HostCapture::compiler_decoded(Arc::clone(&path),SourceText::clone(compiled)));
            extra.push(HostCapture::analyze_raw(path,PolicyRole::DmSource,raw));
            continue;
        }
        // Existing resource capture already records the parent listing AND a
        // negative lookup on NotFound, including for optional configuration.
        let Some(bytes) = inputs.read_candidate(&path)? else {
            if request.required {
                return Err(io::Error::new(
                    io::ErrorKind::NotFound,
                    format!("required policy input missing: {}", path.display()),
                ));
            }
            if request.role == PolicyRole::Configuration {
                configuration_bytes.insert(path.clone(), None);
            }
            missing.push(path);
            continue;
        };
        let path = Arc::new(path);
        let native = if request.role == PolicyRole::DmSource {
            let text = SourceText::from(dm_preprocess::decode_source_bytes(bytes.as_slice()));
            extra.push(HostCapture::compiler_decoded(
                Arc::clone(&path),
                text.clone(),
            ));
            Some(text)
        } else {
            None
        };
        // Analyze reads UTF-8-lossy and universal newlines. In particular, its
        // raw view retains a UTF-8 BOM, unlike the compiler's decoded original.
        let raw = if let Some(native) = native.filter(|native| {
            native.as_str().as_bytes() == bytes.as_slice() && !bytes.as_slice().contains(&b'\r')
        }) {
            native
        } else {
            analyze_raw(bytes.as_slice())
        };
        if request.role == PolicyRole::Configuration {
            configuration_bytes.insert(path.as_ref().clone(), Some(bytes));
        }
        extra.push(HostCapture::analyze_raw(path, request.role, raw));
    }
    let policy = PolicyInputs::capture(frontend, extra).map_err(io::Error::other)?;
    let facts = inputs.snapshot()?;
    let captured = CapturedPolicyInputs {
        policy,
        facts,
        missing,
        explicit_search_folders,
        policy_revision: None,
        configuration_bytes,
    };
    admit_capture_charge(captured.budget_charge())?;
    Ok(captured)
}
fn admit_capture_charge(charge: usize) -> io::Result<()> {
    if charge > MAX_POLICY_CAPTURE_CHARGE {
        Err(io::Error::other(
            "raw policy capture exceeds bounded migration retention admission",
        ))
    } else {
        Ok(())
    }
}
fn analyze_raw(bytes: &[u8]) -> SourceText {
    String::from_utf8_lossy(bytes)
        .replace("\r\n", "\n")
        .replace('\r', "\n")
        .into()
}

#[cfg(test)]
#[path = "policy_capture_tests.rs"]
mod tests;

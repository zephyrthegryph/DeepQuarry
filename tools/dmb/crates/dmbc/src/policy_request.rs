//! Explicit, bounded-in-scope policy input intent; never workspace coverage.
//! Wire values are untrusted until admitted. Admission performs no filesystem IO.
use dm_preprocess::regions::canonical_path;
use serde::{Deserialize, Serialize};
use std::{
    collections::{BTreeMap, BTreeSet},
    io,
    path::PathBuf,
};

#[derive(Clone, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
pub struct PolicyInputRequest {
    #[serde(default)]
    pub files: Vec<PolicyInputFile>,
    #[serde(default)]
    pub search_folders: Vec<PathBuf>,
}
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct PolicyInputFile {
    pub path: PathBuf,
    pub role: PolicyInputRole,
    pub required: bool,
}
#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PolicyInputRole {
    DmSource,
    Configuration,
}

/// Private normalized authority. Deserialization validates, never bypasses admission.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(try_from = "PolicyInputRequest", into = "PolicyInputRequest")]
pub struct AdmittedPolicyRequest {
    files: Vec<PolicyInputFile>,
    search_folders: Vec<PathBuf>,
}
impl PolicyInputRequest {
    pub fn admit(self) -> io::Result<AdmittedPolicyRequest> {
        fn absolute(path: PathBuf) -> io::Result<PathBuf> {
            if !path.is_absolute() {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidInput,
                    "policy input paths must be absolute caller-resolved paths",
                ));
            }
            Ok(canonical_path(&path))
        }
        let mut files: BTreeMap<PathBuf, PolicyInputFile> = BTreeMap::new();
        for mut file in self.files {
            file.path = absolute(file.path)?;
            match files.get_mut(&file.path) {
                Some(previous) if previous.role != file.role => {
                    return Err(io::Error::new(
                        io::ErrorKind::InvalidInput,
                        "policy path has contradictory roles",
                    ))
                }
                Some(previous) => previous.required |= file.required,
                None => {
                    files.insert(file.path.clone(), file);
                }
            }
        }
        let folders = self
            .search_folders
            .into_iter()
            .map(absolute)
            .collect::<io::Result<BTreeSet<_>>>()?;
        Ok(AdmittedPolicyRequest {
            files: files.into_values().collect(),
            search_folders: folders.into_iter().collect(),
        })
    }
}
impl TryFrom<PolicyInputRequest> for AdmittedPolicyRequest {
    type Error = io::Error;
    fn try_from(value: PolicyInputRequest) -> io::Result<Self> {
        value.admit()
    }
}
impl From<AdmittedPolicyRequest> for PolicyInputRequest {
    fn from(value: AdmittedPolicyRequest) -> Self {
        Self {
            files: value.files,
            search_folders: value.search_folders,
        }
    }
}
impl AdmittedPolicyRequest {
    pub fn files(&self) -> &[PolicyInputFile] {
        &self.files
    }
    pub fn search_folders(&self) -> &[PathBuf] {
        &self.search_folders
    }
    pub(crate) fn capture_files(
        &self,
    ) -> Vec<crate::runner_host::policy_capture::RequestedPolicyFile> {
        self.files
            .iter()
            .map(
                |file| crate::runner_host::policy_capture::RequestedPolicyFile {
                    path: file.path.clone(),
                    required: file.required,
                    role: match file.role {
                        PolicyInputRole::DmSource => {
                            dm_analysis::policy_inputs::PolicyRole::DmSource
                        }
                        PolicyInputRole::Configuration => {
                            dm_analysis::policy_inputs::PolicyRole::Configuration
                        }
                    },
                },
            )
            .collect()
    }
}
/// Absent requests preserve existing identities byte-for-byte. Presence,
/// including Some(empty), is domain-separated and bound to the complete contract.
pub(crate) fn append_identity(
    bytes: &mut Vec<u8>,
    request: Option<&AdmittedPolicyRequest>,
) -> io::Result<()> {
    if let Some(request) = request {
        let encoded = serde_json::to_vec(request).map_err(io::Error::other)?;
        bytes.extend_from_slice(b"native-policy-inputs-v1\0");
        bytes.extend_from_slice(&(encoded.len() as u64).to_le_bytes());
        bytes.extend_from_slice(&encoded);
    }
    Ok(())
}
/// Policy-only content changes must not masquerade as the same external pin.
/// The input ledger includes requested directory and negative facts; this is
/// neither a semantic-tree copy nor a claim about unrequested workspace files.
pub(crate) fn captured_revision(
    content: u128,
    facts: &crate::input_snapshot::InputSnapshot,
    request: &AdmittedPolicyRequest,
) -> io::Result<u128> {
    let mut bytes = b"native-captured-policy-v1\0".to_vec();
    bytes.extend_from_slice(&content.to_le_bytes());
    append_identity(&mut bytes, Some(request))?;
    let mut encoded = Ok(Vec::new());
    facts.visit_recorded_storage(|files, folders, negative, generated| {
        encoded = serde_json::to_vec(&(files, folders, negative, generated));
    });
    let facts = encoded.map_err(io::Error::other)?;
    bytes.extend_from_slice(&(facts.len() as u64).to_le_bytes());
    bytes.extend_from_slice(&facts);
    Ok(xxhash_rust::xxh3::xxh3_128(&bytes))
}
#[cfg(test)]
#[path = "policy_request_tests.rs"]
mod tests;

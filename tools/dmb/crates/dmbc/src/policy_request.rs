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
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub workspace: Option<WorkspacePolicyRequest>,
    #[serde(default,skip_serializing_if="Vec::is_empty",with="generator_names")]
    pub workspace_generators: Vec<crate::GeneratorName>,
}
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WorkspacePolicyRequest {
    pub root: PathBuf,
    pub recursive_roots: Vec<PathBuf>,
    pub configuration: PathBuf,
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
    workspace: Option<WorkspacePolicyRequest>,
    workspace_generators: Vec<crate::GeneratorName>,
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
        if self.workspace.is_some() && (!self.files.is_empty() || !self.search_folders.is_empty()) {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "workspace policy intent cannot mix explicit files or search_folders",
            ));
        }
        if !self.workspace_generators.is_empty() && self.workspace.is_none(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"generator questions require an actual workspace intent"));}
        if self.workspace_generators.len()>13{return Err(io::Error::new(io::ErrorKind::InvalidInput,"generator questions exceed the registered set"));}
        let mut workspace_generators=self.workspace_generators;workspace_generators.sort_unstable();
        if workspace_generators.windows(2).any(|pair|pair[0]==pair[1]){return Err(io::Error::new(io::ErrorKind::InvalidInput,"duplicate generator question"));}
        let workspace = self
            .workspace
            .map(|wanted| -> io::Result<WorkspacePolicyRequest> {
                let root = absolute(wanted.root)?;
                let recursive_roots = wanted
                    .recursive_roots
                    .into_iter()
                    .map(absolute)
                    .collect::<io::Result<BTreeSet<_>>>()?
                    .into_iter()
                    .collect::<Vec<_>>();
                if recursive_roots.is_empty()
                    || recursive_roots.iter().any(|p| !p.starts_with(&root))
                {
                    return Err(io::Error::new(
                        io::ErrorKind::InvalidInput,
                        "workspace needs nonempty recursive roots within its root",
                    ));
                }
                Ok(WorkspacePolicyRequest {
                    root,
                    recursive_roots,
                    configuration: absolute(wanted.configuration)?,
                })
            })
            .transpose()?;
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
            workspace,
            workspace_generators,
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
            workspace: value.workspace,
            workspace_generators: value.workspace_generators,
        }
    }
}
impl AdmittedPolicyRequest {
    pub fn workspace_generators(&self)->&[crate::GeneratorName]{&self.workspace_generators}
    pub fn workspace(&self) -> Option<&WorkspacePolicyRequest> {
        self.workspace.as_ref()
    }
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
    if !facts.policy_directories().is_empty() {
        let typed = serde_json::to_vec(facts.policy_directories()).map_err(io::Error::other)?;
        bytes.extend_from_slice(b"typed-policy-directory-observations-v1\0");
        bytes.extend_from_slice(&(typed.len() as u64).to_le_bytes());
        bytes.extend_from_slice(&typed);
    }
    let facts = encoded.map_err(io::Error::other)?;
    bytes.extend_from_slice(&(facts.len() as u64).to_le_bytes());
    bytes.extend_from_slice(&facts);
    Ok(xxhash_rust::xxh3::xxh3_128(&bytes))
}
#[cfg(test)]
#[path = "policy_request_tests.rs"]
mod tests;

/// Stream the exact typed discovery/config/source closure into the existing
/// external policy pin. No full roster serialization buffer or model is built.
pub(crate) fn workspace_revision(
    source: u128,
    facts: &crate::input_snapshot::InputSnapshot,
    root: &std::path::Path,
    recursive_roots: &[PathBuf],
    configuration: &std::path::Path,
) -> io::Result<u128> {
    struct HashWriter(xxhash_rust::xxh3::Xxh3);
    impl io::Write for HashWriter {
        fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
            self.0.update(bytes);
            Ok(bytes.len())
        }
        fn flush(&mut self) -> io::Result<()> {
            Ok(())
        }
    }
    let mut hash = HashWriter(xxhash_rust::xxh3::Xxh3::new());
    use io::Write;
    hash.write_all(b"native-workspace-policy-v1\0")?;
    serde_json::to_writer(&mut hash, &(source, root, recursive_roots, configuration))
        .map_err(io::Error::other)?;
    let mut encoded = Ok(());
    facts.visit_recorded_storage(|files, folders, negative, generated| {
        encoded = serde_json::to_writer(
            &mut hash,
            &(
                files,
                folders,
                negative,
                generated,
                facts.policy_directories(),
            ),
        )
        .map_err(io::Error::other);
    });
    encoded?;
    Ok(hash.0.digest128())
}

mod generator_names{
 use super::*;
 pub fn serialize<S:serde::Serializer>(names:&[crate::GeneratorName],serializer:S)->Result<S::Ok,S::Error>{use serde::ser::SerializeSeq;let mut seq=serializer.serialize_seq(Some(names.len()))?;for name in names{seq.serialize_element(name.name())?;}seq.end()}
 pub fn deserialize<'de,D:serde::Deserializer<'de>>(decoder:D)->Result<Vec<crate::GeneratorName>,D::Error>{struct Names;impl<'de>serde::de::Visitor<'de>for Names{type Value=Vec<crate::GeneratorName>;fn expecting(&self,out:&mut std::fmt::Formatter)->std::fmt::Result{out.write_str("at most thirteen canonical generator questions")}fn visit_seq<A:serde::de::SeqAccess<'de>>(self,mut sequence:A)->Result<Self::Value,A::Error>{if sequence.size_hint().is_some_and(|n|n>13){return Err(serde::de::Error::custom("generator question list exceeds registered set"))}let mut names=Vec::new();names.try_reserve_exact(13).map_err(serde::de::Error::custom)?;while let Some(name)=sequence.next_element::<crate::GeneratorName>()?{if names.len()==13{return Err(serde::de::Error::custom("generator question list exceeds registered set"))}names.push(name);}Ok(names)}}decoder.deserialize_seq(Names)}
}

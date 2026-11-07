//! Explicit, bounded-in-scope policy input intent; never workspace coverage.
//! Wire values are untrusted until admitted. Admission performs no filesystem IO.
use dm_preprocess::regions::canonical_path;
use serde::{Deserialize, Serialize};
use std::{
    collections::{BTreeMap, BTreeSet},
    io,
    path::{Path, PathBuf},
};

pub(crate) fn canonical_analysis_project(project:&std::path::Path,context:Option<AnalysisContext>)->io::Result<PathBuf>{
 if context==Some(AnalysisContext::OriginalAnalyze0290){if project.file_name()!=Some(std::ffi::OsStr::new("deepquarry.dme")){return Err(io::Error::new(io::ErrorKind::InvalidInput,"whole Analyze purpose requires fixed deepquarry project name"))}let root=project.parent().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"Analyze root absent"))?;return Ok(std::fs::canonicalize(root)?.join("deepquarry.dme"))}std::fs::canonicalize(project)
}

/// Explicit analysis preprocessing purpose. This is configuration; the actual
/// native frontend and source mapping must issue its current context separately.
#[derive(Clone,Copy,Debug,Eq,PartialEq,Ord,PartialOrd,Serialize,Deserialize)]
#[serde(rename_all="snake_case")]
pub enum AnalysisContext { OriginalChecker0290,OriginalAnalyze0290 }
impl AnalysisContext { pub(crate) fn frontend_context(self)->Self{Self::OriginalChecker0290} pub(crate) fn initial_environment(self)->dm_preprocess::InitialEnvironment { match self { Self::OriginalChecker0290|Self::OriginalAnalyze0290=>dm_preprocess::InitialEnvironment::OriginalChecker0290 } } }

#[derive(Clone, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
pub struct PolicyInputRequest {
    #[serde(default,skip_serializing_if="Option::is_none")]
    pub analysis_context: Option<AnalysisContext>,
    #[serde(default)]
    pub files: Vec<PolicyInputFile>,
    #[serde(default)]
    pub search_folders: Vec<PathBuf>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub workspace: Option<WorkspacePolicyRequest>,
    #[serde(default,skip_serializing_if="Vec::is_empty",with="generator_names")]
    pub workspace_generators: Vec<crate::GeneratorName>,
    #[serde(default,skip_serializing_if="Vec::is_empty",with="auxiliary_questions")]
    pub workspace_auxiliary: Vec<WorkspaceAuxiliaryQuestion>,
}
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WorkspacePolicyRequest {
    pub root: PathBuf,
    pub recursive_roots: Vec<PathBuf>,
    pub configuration: PathBuf,
}
pub(crate) fn exact_code_maps_roots(root: &Path, roots: &[PathBuf]) -> bool {
    roots.len() == 2 && ["code", "maps"].into_iter().all(|name| {
        roots.iter().any(|candidate| candidate.strip_prefix(root).ok() == Some(Path::new(name)))
    })
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


/// Explicit fixed auxiliary questions, independent of generator/source roles.
#[derive(Clone,Copy,Debug,Eq,PartialEq,Ord,PartialOrd,Serialize,Deserialize)]
#[serde(rename_all="snake_case")]
pub enum WorkspaceAuxiliaryQuestion{DeadlinePollingAllowlist,CheckGrep,Keys,SemReads,UntrackedInputs,Tracked,TrackedTests,CheckGrepBaseline,Decl,Init,BaseVars,RequirementBool,PlayerLink,UntypedMember,WeakRawRead,RelWriteUndeclared,Untyped,DocSnippets,StoredRefs,Ownership,EngineLayering,LibraryLayering,UiActions,SetterPublishes,OpOrder,SysReactive,Lifeforms,DerivedReads,SemHandlers,NoticePublisher,SiliconEntry,LibraryLayeringFullAllow,SemHandlersFullAllow,MapEdits,AllRawFilePolicies,ImageDir,EngineLayeringFullAllow,DocSnippetsFullAllow,UiActionsFullAllow,DocUiFullAllow}
impl WorkspaceAuxiliaryQuestion {
    // Both original Tree policies use the same exact CODE_DM subset.
    pub(crate) const SELECTED_ORDER_AND_OWNERSHIP: &'static [Self] =
        &[Self::Ownership, Self::OpOrder];
    pub(crate) const SELECTED_MAP_AND_LAYERING: &'static [Self] =
        &[Self::LibraryLayeringFullAllow, Self::MapEdits, Self::EngineLayeringFullAllow];

    pub(crate) fn admits_map_edits_capture(questions: &[Self]) -> bool {
        questions == [Self::MapEdits] || questions == Self::SELECTED_MAP_AND_LAYERING
    }

    pub(crate) const SELECTED_READS: &'static [Self] = &[Self::SemReads, Self::UntrackedInputs];
    pub(crate) const SELECTED_SETTER: &'static [Self] = &[Self::SetterPublishes];
    pub(crate) const SELECTED_LIFEFORMS_PLAYER_LINK: &'static [Self] =
        &[Self::PlayerLink, Self::Lifeforms];
    pub(crate) const SELECTED_REFERENCE_POLICIES: &'static [Self] =
        &[Self::UntypedMember, Self::WeakRawRead, Self::RelWriteUndeclared];
    pub(crate) const SELECTED_STORED_AND_TRACKED: &'static [Self] =
        &[Self::Tracked, Self::TrackedTests, Self::StoredRefs];
    pub(crate) const SELECTED_DECLARATION_POLICIES: &'static [Self] =
        &[Self::Decl, Self::Init, Self::BaseVars];
    pub(crate) const SELECTED_REACTIVE: &'static [Self] =
        &[Self::SemReads, Self::UntrackedInputs, Self::SetterPublishes];

    pub(crate) fn admits_selected_reads(questions: &[Self]) -> bool {
        questions == Self::SELECTED_READS || questions == Self::SELECTED_REACTIVE
    }

    pub(crate) fn admits_combined_reports(questions: &[Self]) -> bool {
        Self::admits_selected_reads(questions) || questions == [Self::Untyped]
            || questions == Self::SELECTED_STORED_AND_TRACKED
    }

    pub(crate) fn admits_selected_setter(questions: &[Self]) -> bool {
        questions == Self::SELECTED_SETTER || questions == Self::SELECTED_REACTIVE
    }
}

impl WorkspaceAuxiliaryQuestion { pub(crate) const ALL:&'static[Self]=&[Self::DeadlinePollingAllowlist,Self::CheckGrep,Self::Keys,Self::SemReads,Self::UntrackedInputs,Self::Tracked,Self::TrackedTests,Self::CheckGrepBaseline,Self::Decl,Self::Init,Self::BaseVars,Self::RequirementBool,Self::PlayerLink,Self::UntypedMember,Self::WeakRawRead,Self::RelWriteUndeclared,Self::Untyped,Self::DocSnippets,Self::StoredRefs,Self::Ownership,Self::EngineLayering,Self::LibraryLayering,Self::UiActions,Self::SetterPublishes,Self::OpOrder,Self::SysReactive,Self::Lifeforms,Self::DerivedReads,Self::SemHandlers,Self::NoticePublisher,Self::SiliconEntry,Self::LibraryLayeringFullAllow,Self::SemHandlersFullAllow,Self::MapEdits,Self::AllRawFilePolicies,Self::ImageDir,Self::EngineLayeringFullAllow,Self::DocSnippetsFullAllow,Self::UiActionsFullAllow,Self::DocUiFullAllow]; pub(crate) const SEMANTIC:&'static[Self]=&[Self::SemReads,Self::UntrackedInputs,Self::SetterPublishes,Self::SysReactive,Self::Lifeforms,Self::DerivedReads,Self::Tracked,Self::TrackedTests,Self::Decl,Self::Init,Self::BaseVars,Self::RequirementBool,Self::PlayerLink,Self::UntypedMember,Self::WeakRawRead,Self::RelWriteUndeclared,Self::Untyped,Self::StoredRefs,Self::EngineLayering,Self::LibraryLayering,Self::SiliconEntry,Self::LibraryLayeringFullAllow,Self::SemHandlersFullAllow,Self::MapEdits,Self::ImageDir,Self::EngineLayeringFullAllow]; pub(crate) fn is_semantic(self)->bool {Self::SEMANTIC.contains(&self)} }

impl WorkspaceAuxiliaryQuestion {
    pub(crate) fn layering(self) -> Option<dq_analyze::engine_layering_policy::Layer> {
        use dq_analyze::engine_layering_policy::Layer;
        match self {
            Self::EngineLayering => Some(Layer::Engine),
            Self::LibraryLayering => Some(Layer::Library),
            _ => None,
        }
    }

    pub(crate) fn selected_layering(self) -> Option<dq_analyze::engine_layering_policy::Layer> {
        use dq_analyze::engine_layering_policy::Layer;
        match self {
            Self::EngineLayeringFullAllow => Some(Layer::Engine),
            Self::LibraryLayeringFullAllow => Some(Layer::Library),
            _ => None,
        }
    }

    pub(crate) fn exclusive_layering(questions: &[Self]) -> Option<Self> {
        match questions {
            [question] if question.layering().is_some() => Some(*question),
            _ => None,
        }
    }
}

/// Private normalized authority. Deserialization validates, never bypasses admission.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(try_from = "PolicyInputRequest", into = "PolicyInputRequest")]
pub struct AdmittedPolicyRequest {
    analysis_context: Option<AnalysisContext>,
    files: Vec<PolicyInputFile>,
    search_folders: Vec<PathBuf>,
    workspace: Option<WorkspacePolicyRequest>,
    workspace_generators: Vec<crate::GeneratorName>,
    workspace_auxiliary: Vec<WorkspaceAuxiliaryQuestion>,
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
        if self.analysis_context==Some(AnalysisContext::OriginalAnalyze0290)&&self.workspace.is_none(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"full Analyze subject requires actual workspace intent"))}
        if self.workspace.is_some() && (!self.files.is_empty() || !self.search_folders.is_empty()) {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "workspace policy intent cannot mix explicit files or search_folders",
            ));
        }
        if !self.workspace_generators.is_empty() && self.workspace.is_none(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"generator questions require an actual workspace intent"));}
        if self.workspace_generators.len()>crate::GeneratorName::REGISTERED_COUNT{return Err(io::Error::new(io::ErrorKind::InvalidInput,"generator questions exceed the registered set"));}
        if self.analysis_context.is_some() && !self.workspace_generators.is_empty() && (self.analysis_context!=Some(AnalysisContext::OriginalAnalyze0290)||!self.workspace_auxiliary.is_empty()) {return Err(io::Error::new(io::ErrorKind::InvalidInput,"Original generation requires its actual full Analyze purpose without mixed auxiliary roles"));}
        let mut workspace_generators=self.workspace_generators;workspace_generators.sort_unstable();
        if workspace_generators.windows(2).any(|pair|pair[0]==pair[1]){return Err(io::Error::new(io::ErrorKind::InvalidInput,"duplicate generator question"));}
        if !self.workspace_auxiliary.is_empty() && self.workspace.is_none(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"auxiliary questions require actual workspace intent"))}
        if self.workspace_auxiliary.len()>WorkspaceAuxiliaryQuestion::ALL.len(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"auxiliary questions exceed fixed registered set"))}
        let mut workspace_auxiliary=self.workspace_auxiliary;workspace_auxiliary.sort_unstable();if workspace_auxiliary.contains(&WorkspaceAuxiliaryQuestion::CheckGrep)&&workspace_auxiliary.contains(&WorkspaceAuxiliaryQuestion::CheckGrepBaseline){return Err(io::Error::new(io::ErrorKind::InvalidInput,"CheckGrep check and baseline purposes are mutually exclusive"))}if workspace_auxiliary.windows(2).any(|pair|pair[0]==pair[1]){return Err(io::Error::new(io::ErrorKind::InvalidInput,"duplicate auxiliary question"))}
        if workspace_auxiliary.contains(&WorkspaceAuxiliaryQuestion::PlayerLink)&&self.analysis_context!=Some(AnalysisContext::OriginalAnalyze0290){return Err(io::Error::new(io::ErrorKind::InvalidInput,"player-link requires its actual full Original Analyze subject"))}
        if workspace_auxiliary.contains(&WorkspaceAuxiliaryQuestion::AllRawFilePolicies)
            && (self.analysis_context != Some(AnalysisContext::OriginalAnalyze0290)
                || workspace_auxiliary.as_slice() != [WorkspaceAuxiliaryQuestion::AllRawFilePolicies]
                || !workspace_generators.is_empty() || !self.files.is_empty()
                || !self.search_folders.is_empty())
        {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "raw file roster requires its exclusive Original workspace purpose"));
        }
        if workspace_auxiliary.contains(&WorkspaceAuxiliaryQuestion::DocSnippetsFullAllow)
            && (self.analysis_context != Some(AnalysisContext::OriginalAnalyze0290)
                || workspace_auxiliary.as_slice() != [WorkspaceAuxiliaryQuestion::DocSnippetsFullAllow]
                || !workspace_generators.is_empty() || !self.files.is_empty() || !self.search_folders.is_empty())
        {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "joined Docs requires its exact Original workspace purpose"));
        }
        if workspace_auxiliary.contains(&WorkspaceAuxiliaryQuestion::UiActionsFullAllow)
            && (self.analysis_context != Some(AnalysisContext::OriginalAnalyze0290)
                || workspace_auxiliary.as_slice() != [WorkspaceAuxiliaryQuestion::UiActionsFullAllow]
                || !workspace_generators.is_empty() || !self.files.is_empty() || !self.search_folders.is_empty())
        {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "joined UI Actions requires its exact Original workspace purpose"));
        }
        if workspace_auxiliary.contains(&WorkspaceAuxiliaryQuestion::DocUiFullAllow)
            && (self.analysis_context != Some(AnalysisContext::OriginalAnalyze0290)
                || workspace_auxiliary.as_slice() != [WorkspaceAuxiliaryQuestion::DocUiFullAllow]
                || !workspace_generators.is_empty() || !self.files.is_empty() || !self.search_folders.is_empty())
        {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "joined Docs and UI Actions requires its exact Original workspace purpose"));
        }
        if workspace_auxiliary.contains(&WorkspaceAuxiliaryQuestion::ImageDir)
            && (self.analysis_context != Some(AnalysisContext::OriginalAnalyze0290)
                || workspace_auxiliary.as_slice() != [WorkspaceAuxiliaryQuestion::ImageDir]
                || !workspace_generators.is_empty() || !self.files.is_empty()
                || !self.search_folders.is_empty())
        {
            return Err(io::Error::new(io::ErrorKind::InvalidInput,
                "image_dir_after_build requires its exact clean Original selected purpose"));
        }
        if workspace_auxiliary.contains(&WorkspaceAuxiliaryQuestion::MapEdits)
            && (self.analysis_context != Some(AnalysisContext::OriginalAnalyze0290)
                || !WorkspaceAuxiliaryQuestion::admits_map_edits_capture(&workspace_auxiliary)
                || self.workspace.as_ref().is_none_or(|w| {
                    w.recursive_roots.as_slice() != [w.root.join("code"), w.root.join("maps")]
                        && (workspace_auxiliary.as_slice() != [WorkspaceAuxiliaryQuestion::MapEdits]
                            || w.recursive_roots.as_slice() != [w.root.join("code")])
                }))
        {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "map_edits requires exclusive Original Analyze with fixed CODE discovery"));
        }
        if workspace_auxiliary.contains(&WorkspaceAuxiliaryQuestion::SiliconEntry)
            && (self.analysis_context != Some(AnalysisContext::OriginalAnalyze0290)
                || workspace_auxiliary.as_slice() != [WorkspaceAuxiliaryQuestion::SiliconEntry])
        {
            return Err(io::Error::new(io::ErrorKind::InvalidInput,"silicon_entry requires its exclusive full Original Analyze subject"));
        }
        if workspace_auxiliary.contains(&WorkspaceAuxiliaryQuestion::UntypedMember)&&self.analysis_context!=Some(AnalysisContext::OriginalAnalyze0290){return Err(io::Error::new(io::ErrorKind::InvalidInput,"untyped-member requires its actual full Original Analyze subject"))}
        if workspace_auxiliary.contains(&WorkspaceAuxiliaryQuestion::WeakRawRead)&&self.analysis_context!=Some(AnalysisContext::OriginalAnalyze0290){return Err(io::Error::new(io::ErrorKind::InvalidInput,"weak-raw-read requires its actual full Original Analyze subject"))}
        if workspace_auxiliary.contains(&WorkspaceAuxiliaryQuestion::RelWriteUndeclared)&&self.analysis_context!=Some(AnalysisContext::OriginalAnalyze0290){return Err(io::Error::new(io::ErrorKind::InvalidInput,"rel-write requires its actual full Original Analyze subject"))}
        if workspace_auxiliary.contains(&WorkspaceAuxiliaryQuestion::Untyped)&&self.analysis_context!=Some(AnalysisContext::OriginalAnalyze0290){return Err(io::Error::new(io::ErrorKind::InvalidInput,"untyped requires its actual full Original Analyze subject"))}
        if workspace_auxiliary.contains(&WorkspaceAuxiliaryQuestion::StoredRefs)&&self.analysis_context!=Some(AnalysisContext::OriginalAnalyze0290){return Err(io::Error::new(io::ErrorKind::InvalidInput,"stored_refs requires its actual full Original Analyze subject"))}
        if workspace_auxiliary.contains(&WorkspaceAuxiliaryQuestion::OpOrder)&&self.analysis_context!=Some(AnalysisContext::OriginalAnalyze0290){return Err(io::Error::new(io::ErrorKind::InvalidInput,"op_order requires its exact Original Analyze source purpose"))}
        if workspace_auxiliary.contains(&WorkspaceAuxiliaryQuestion::UiActions)&&self.analysis_context!=Some(AnalysisContext::OriginalAnalyze0290){return Err(io::Error::new(io::ErrorKind::InvalidInput,"ui_actions requires its exact Original Analyze source purpose"))}
        if workspace_auxiliary.iter().any(|q| q.layering().is_some())
            && (WorkspaceAuxiliaryQuestion::exclusive_layering(&workspace_auxiliary).is_none()
                || self.analysis_context != Some(AnalysisContext::OriginalAnalyze0290)
                || !workspace_generators.is_empty())
        {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "layering requires its exclusive full Original Analyze subject"));
        }
        if workspace_auxiliary.iter().any(|question| question.selected_layering().is_some())
            && (self.analysis_context != Some(AnalysisContext::OriginalAnalyze0290)
                || (workspace_auxiliary.len() != 1
                    && workspace_auxiliary.as_slice() != WorkspaceAuxiliaryQuestion::SELECTED_MAP_AND_LAYERING)
                || !workspace_generators.is_empty() || !self.files.is_empty() || !self.search_folders.is_empty())
        {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "layering selected report requires its exact Original Analyze role"));
        }
        if workspace_auxiliary.contains(&WorkspaceAuxiliaryQuestion::SemHandlersFullAllow)
            && (self.analysis_context != Some(AnalysisContext::OriginalAnalyze0290)
                || workspace_auxiliary.as_slice() != [WorkspaceAuxiliaryQuestion::SemHandlersFullAllow]
                || !workspace_generators.is_empty() || !self.files.is_empty() || !self.search_folders.is_empty())
        {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "selected handlers requires its exact full Original Analyze role"));
        }
        if workspace_auxiliary.contains(&WorkspaceAuxiliaryQuestion::SemHandlers)&&(self.analysis_context!=Some(AnalysisContext::OriginalAnalyze0290)||workspace_auxiliary.as_slice()!=[WorkspaceAuxiliaryQuestion::SemHandlers]||!self.files.is_empty()||!self.search_folders.is_empty()||!workspace_generators.is_empty()){return Err(io::Error::new(io::ErrorKind::InvalidInput,"sem/handlers requires its exclusive actual Original Analyze partial-policy purpose"))}
        if workspace_auxiliary.contains(&WorkspaceAuxiliaryQuestion::NoticePublisher)
            && (self.analysis_context != Some(AnalysisContext::OriginalAnalyze0290)
                || workspace_auxiliary.as_slice() != [WorkspaceAuxiliaryQuestion::NoticePublisher]
                || !self.files.is_empty()
                || !self.search_folders.is_empty()
                || !workspace_generators.is_empty())
        {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "notice_publisher requires its exclusive Original Analyze source purpose"));
        }
        if workspace_auxiliary.iter().any(|question|question.is_semantic()) && self.analysis_context.is_none() {return Err(io::Error::new(io::ErrorKind::InvalidInput,"semantic analysis questions require the explicit original context"))}
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
            analysis_context:self.analysis_context,
            files: files.into_values().collect(),
            search_folders: folders.into_iter().collect(),
            workspace,
            workspace_generators,
            workspace_auxiliary,
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
            analysis_context:value.analysis_context,
            files: value.files,
            search_folders: value.search_folders,
            workspace: value.workspace,
            workspace_generators: value.workspace_generators,
            workspace_auxiliary: value.workspace_auxiliary,
        }
    }
}
impl AdmittedPolicyRequest {
    pub fn analysis_context(&self)->Option<AnalysisContext>{self.analysis_context}
    pub fn workspace_auxiliary(&self)->&[WorkspaceAuxiliaryQuestion]{&self.workspace_auxiliary}
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
    facts.write_original_workspace_observations(&mut hash)?;
    Ok(hash.0.digest128())
}

mod generator_names{
 use super::*;
 pub fn serialize<S:serde::Serializer>(names:&[crate::GeneratorName],serializer:S)->Result<S::Ok,S::Error>{use serde::ser::SerializeSeq;let mut seq=serializer.serialize_seq(Some(names.len()))?;for name in names{seq.serialize_element(name.name())?;}seq.end()}
 pub fn deserialize<'de,D:serde::Deserializer<'de>>(decoder:D)->Result<Vec<crate::GeneratorName>,D::Error>{struct Names;impl<'de>serde::de::Visitor<'de>for Names{type Value=Vec<crate::GeneratorName>;fn expecting(&self,out:&mut std::fmt::Formatter)->std::fmt::Result{out.write_str("at most twelve canonical generator questions")}fn visit_seq<A:serde::de::SeqAccess<'de>>(self,mut sequence:A)->Result<Self::Value,A::Error>{if sequence.size_hint().is_some_and(|n|n>crate::GeneratorName::REGISTERED_COUNT){return Err(serde::de::Error::custom("generator question list exceeds registered set"))}let mut names=Vec::new();names.try_reserve_exact(crate::GeneratorName::REGISTERED_COUNT).map_err(serde::de::Error::custom)?;while let Some(name)=sequence.next_element::<crate::GeneratorName>()?{if names.len()==crate::GeneratorName::REGISTERED_COUNT{return Err(serde::de::Error::custom("generator question list exceeds registered set"))}names.push(name);}Ok(names)}}decoder.deserialize_seq(Names)}
}

mod auxiliary_questions{
 use super::*;
 pub fn serialize<S:serde::Serializer>(values:&[WorkspaceAuxiliaryQuestion],serializer:S)->Result<S::Ok,S::Error>{values.serialize(serializer)}
 pub fn deserialize<'de,D:serde::Deserializer<'de>>(decoder:D)->Result<Vec<WorkspaceAuxiliaryQuestion>,D::Error>{struct Questions;impl<'de>serde::de::Visitor<'de>for Questions{type Value=Vec<WorkspaceAuxiliaryQuestion>;fn expecting(&self,f:&mut std::fmt::Formatter)->std::fmt::Result{f.write_str("at most the registered fixed workspace auxiliary questions")}fn visit_seq<A:serde::de::SeqAccess<'de>>(self,mut seq:A)->Result<Self::Value,A::Error>{if seq.size_hint().is_some_and(|n|n>WorkspaceAuxiliaryQuestion::ALL.len()){return Err(serde::de::Error::custom("too many auxiliary questions"))}let mut values=Vec::new();values.try_reserve_exact(WorkspaceAuxiliaryQuestion::ALL.len()).map_err(serde::de::Error::custom)?;while let Some(value)=seq.next_element()?{if values.len()==WorkspaceAuxiliaryQuestion::ALL.len(){return Err(serde::de::Error::custom("too many auxiliary questions"))}values.push(value)}Ok(values)}}decoder.deserialize_seq(Questions)}
}

#[cfg(test)]mod analysis_context_tests{
 use super::*;
 #[test]fn explicit_analysis_context_is_canonical_and_native_absence_keeps_existing_wire_identity(){
  let ordinary=PolicyInputRequest::default();assert_eq!(serde_json::to_string(&ordinary).unwrap(),"{\"files\":[],\"search_folders\":[]}");
  let mut actual=ordinary.clone();actual.analysis_context=Some(AnalysisContext::OriginalChecker0290);let admitted=actual.clone().admit().unwrap();assert_eq!(admitted.analysis_context(),actual.analysis_context);assert_eq!(PolicyInputRequest::from(admitted.clone()),actual);let mut native=Vec::new();append_identity(&mut native,Some(&ordinary.admit().unwrap())).unwrap();let mut original=Vec::new();append_identity(&mut original,Some(&admitted)).unwrap();assert_ne!(native,original);
  let mut impossible=actual;impossible.workspace_generators=vec![crate::GeneratorName::AutoTracked];assert!(impossible.admit().is_err());
  assert!(serde_json::from_str::<PolicyInputRequest>(r#"{"analysis_context":"unissued_checker","files":[],"search_folders":[]}"#).is_err());
 }
}

#[cfg(test)]mod check_grep_purpose_tests{
 use super::*;
 #[test]fn check_and_baseline_auxiliary_questions_are_canonical_distinct_and_mutually_exclusive(){
  let root=crate::test_scratch::dir("grep-purpose-request");let mut request=PolicyInputRequest::default();request.workspace=Some(WorkspacePolicyRequest{root:root.clone(),recursive_roots:vec![root.join("code")],configuration:root.join("tools/ci/lint_scopes.toml")});
  request.workspace_auxiliary=vec![WorkspaceAuxiliaryQuestion::CheckGrepBaseline];let baseline=request.clone().admit().unwrap();assert_eq!(baseline.workspace_auxiliary(),[WorkspaceAuxiliaryQuestion::CheckGrepBaseline]);let json=serde_json::to_vec(&baseline).unwrap();let restored:AdmittedPolicyRequest=serde_json::from_slice(&json).unwrap();assert_eq!(restored,baseline);
  request.workspace_auxiliary=vec![WorkspaceAuxiliaryQuestion::CheckGrep];let check=request.clone().admit().unwrap();assert_ne!(serde_json::to_vec(&check).unwrap(),json);
  request.workspace_auxiliary=vec![WorkspaceAuxiliaryQuestion::CheckGrepBaseline,WorkspaceAuxiliaryQuestion::CheckGrep];assert!(request.clone().admit().is_err());assert!(serde_json::from_slice::<AdmittedPolicyRequest>(&serde_json::to_vec(&request).unwrap()).is_err());
 }
}

#[cfg(test)]mod full_allow_question_roster_tests{
 use super::*;
 #[test]fn exact_registered_question_capacities_cover_union_and_preserve_duplicate_unknown_and_wrong_context_rejection(){
  let mut all=WorkspaceAuxiliaryQuestion::ALL.to_vec();all.sort_unstable();all.dedup();assert_eq!(all.len(),WorkspaceAuxiliaryQuestion::ALL.len());for question in WorkspaceAuxiliaryQuestion::ALL{assert_eq!(question.is_semantic(),WorkspaceAuxiliaryQuestion::SEMANTIC.contains(question));}
  let root=crate::test_scratch::dir("full-allow-question-union");let mut request=PolicyInputRequest::default();request.analysis_context=Some(AnalysisContext::OriginalAnalyze0290);request.workspace=Some(WorkspacePolicyRequest{root:root.clone(),recursive_roots:vec![root.join("code"),root.join("maps")],configuration:root.join("tools/ci/lint_scopes.toml")});request.workspace_auxiliary=WorkspaceAuxiliaryQuestion::ALL.iter().copied().filter(|question|!matches!(question,WorkspaceAuxiliaryQuestion::CheckGrepBaseline|WorkspaceAuxiliaryQuestion::SemHandlers|WorkspaceAuxiliaryQuestion::NoticePublisher|WorkspaceAuxiliaryQuestion::SiliconEntry|WorkspaceAuxiliaryQuestion::EngineLayering|WorkspaceAuxiliaryQuestion::LibraryLayering|WorkspaceAuxiliaryQuestion::LibraryLayeringFullAllow|WorkspaceAuxiliaryQuestion::SemHandlersFullAllow|WorkspaceAuxiliaryQuestion::MapEdits|WorkspaceAuxiliaryQuestion::ImageDir|WorkspaceAuxiliaryQuestion::EngineLayeringFullAllow|WorkspaceAuxiliaryQuestion::DocSnippetsFullAllow|WorkspaceAuxiliaryQuestion::UiActionsFullAllow|WorkspaceAuxiliaryQuestion::DocUiFullAllow)).collect();let admitted=request.clone().admit().unwrap();assert_eq!(admitted.workspace_auxiliary().len(),WorkspaceAuxiliaryQuestion::ALL.len()-14);let json=serde_json::to_vec(&request).unwrap();let decoded:PolicyInputRequest=serde_json::from_slice(&json).unwrap();assert_eq!(decoded,request);
  let mut handlers=request.clone();
  handlers.workspace_auxiliary=vec![WorkspaceAuxiliaryQuestion::SemHandlers];
  assert_eq!(handlers.clone().admit().unwrap().workspace_auxiliary(),[WorkspaceAuxiliaryQuestion::SemHandlers]);
  handlers.workspace_auxiliary.push(WorkspaceAuxiliaryQuestion::SemReads);
  assert!(handlers.admit().is_err(),"the partial Handler subject must not join a full semantic request");
  request.workspace_auxiliary.push(WorkspaceAuxiliaryQuestion::SemReads);assert!(request.clone().admit().is_err());request.workspace_auxiliary=vec![WorkspaceAuxiliaryQuestion::SemReads];request.analysis_context=None;assert!(request.admit().is_err());assert!(serde_json::from_str::<PolicyInputRequest>(r#"{"workspace_auxiliary":["unissued_auxiliary_question"]}"#).is_err());
 }
}

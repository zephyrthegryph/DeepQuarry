//! Production raw producer, distinct from bounded fixture CapturedPolicyInputs.
//! Native entries retain compare-only weak acquisition IDs, never all text views.
use crate::input_snapshot::{
    FileInput, FixedLibraryBaseline, InputSnapshot, RecordedSourceOriginal, RecordingInputs, SnapshotProvider,
    WorkspaceRawSpool, WorkspaceRawSpoolBuilder,
};
use crate::runner_host::workspace_discovery::DiscoveryReceipt;
use crate::query_db::{CurrentWorkspaceRawFile as CurrentFile,WorkspaceRawSourceProof as SourceProof};
use dm_preprocess::{
    regions::{canonical_path, relative_filesystem_path},
};
use dm_resources::SharedBytes;
use dm_tree::frontend::{ColdFrontend, SourceExportMapping};
use std::{
    collections::BTreeMap,
    io,
    path::{Path, PathBuf},
    sync::{Arc, Weak},
};
const EXTRA_BUDGET: usize = 64 * 1024 * 1024;
pub(crate) const LIBRARY_SITES_BASELINE: &str = "tools/ci/library_layering_baseline.txt";
#[path = "workspace_alias_index.rs"]
mod alias_index;
pub(crate) use alias_index::AliasIndex as WorkspaceAliasIndex;
// The capture's exact immutable mapping owns these acquisition slots.
struct Native {
    occurrence: usize,
}
enum Original {
    Native(Native),
    Owned(SharedBytes),
    RawInput(dm_preprocess::SourceAcquisitionLease),
    PairedDmm(usize),
    Spool(usize),
}
struct CapturedOriginal{original:Original,fact:FileInput}
impl CapturedOriginal {
    fn borrow_original<'a>(&'a self, mapping: &'a SourceExportMapping) -> io::Result<RecordedSourceOriginal<'a>> {
        match &self.original {
            Original::Native(native) => {
                let lease = mapping.source_acquisition(native.occurrence)
                    .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "dispatcher Original acquisition differs"))?;
                crate::input_snapshot::recorded_source_original(lease)
            }
            Original::Owned(bytes) => Ok(RecordedSourceOriginal::Bytes(bytes)),
            Original::RawInput(_) | Original::PairedDmm(_) | Original::Spool(_) => Err(io::Error::new(io::ErrorKind::InvalidInput, "dispatcher requires its authored capture owner")),
        }
    }
}

enum FilePath {
    Discovered(usize),
    Fixed(Box<PathBuf>),
}

struct File {
    path: FilePath,
    original: Original,
}

impl File {
    fn path<'a>(&'a self, discovery: &'a DiscoveryReceipt) -> &'a PathBuf {
        match &self.path {
            FilePath::Discovered(index) => &discovery.files()[*index],
            FilePath::Fixed(path) => path,
        }
    }
}
/// Data from the actual visible dispatcher acquisition, never a source witness.
struct MapEditsFile {
    relative: String,
    rows: dq_analyze::map_edits_policy::ParsedMap,
}

struct FullCiBaselines {
    rows: Vec<(&'static str, PathBuf, FixedLibraryBaseline)>,
    preflight_charge: usize,
}

impl FullCiBaselines {
    fn observe<P: SnapshotProvider>(
        inputs: &RecordingInputs<P>, root: &Path, budget: &dq_analyze::captured_generator_budget::Budget,
        work: &dyn dm_preprocess::source_arena_credit::SourceArenaWork,
    ) -> io::Result<Self> {
        Self::observe_using(inputs, root, budget, work, None)
    }

    fn observe_using<P: SnapshotProvider>(
        inputs: &RecordingInputs<P>, root: &Path, budget: &dq_analyze::captured_generator_budget::Budget,
        work: &dyn dm_preprocess::source_arena_credit::SourceArenaWork,
        funded: Option<&dq_analyze::captured_generator_budget::Budget>,
    ) -> io::Result<Self> {
        use dq_analyze::captured_allow_annotations::Operation;
        let mut control = Operation { budget: funded.unwrap_or(budget), poll: &crate::daemon::control::checkpoint };
        let roster = crate::runner_host::query_snapshot::SourceSnapshot::registered_full_baselines(&mut control).map_err(map_edits_failure)?;
        if roster.is_empty() || !root.is_absolute() {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "full CI requires a registered baseline roster and absolute workspace"));
        }
        let mut charge = std::mem::size_of::<Self>() + 64;
        if let Some(funded) = funded { funded.charge(charge).map_err(map_edits_quota)?; }
        let mut rows = Vec::new();
        for relative in roster {
            work.checkpoint()?;
            // Retain canonical path, owner metadata, and enough scratch for the
            // path to enter the selected workspace closure under the same cap.
            let width = root.as_os_str().len().checked_add(relative.len())
                .and_then(|n| n.checked_mul(8)).and_then(|n| n.checked_add(2176))
                .ok_or(io::ErrorKind::OutOfMemory)?;
            charge = charge.checked_add(width).filter(|n| *n <= EXTRA_BUDGET)
                .ok_or(io::ErrorKind::OutOfMemory)?;
            if let Some(funded) = funded { funded.charge(width).map_err(map_edits_quota)?; }
            rows.try_reserve_exact(1).map_err(|error| io::Error::new(io::ErrorKind::OutOfMemory, error))?;
            let path = canonical_path(&root.join(relative));
            if rows.iter().any(|(_, observed, _)| *observed == path) {
                return Err(io::Error::new(io::ErrorKind::InvalidData, "registered baselines alias in the workspace"));
            }
            let baseline = match funded {
                Some(funded) => inputs.read_registered_baseline_using(
                    &path, (EXTRA_BUDGET - charge).min(budget.remaining()), work,
                    Some(&mut |bytes| funded.charge(bytes).map_err(map_edits_quota)),
                )?,
                None => inputs.read_registered_baseline(&path, EXTRA_BUDGET - charge, work)?,
            };
            charge = charge.checked_add(baseline.bytes().map_or(0, SharedBytes::capacity))
                .filter(|n| *n <= EXTRA_BUDGET).ok_or(io::ErrorKind::OutOfMemory)?;
            rows.push((relative, path, baseline));
        }
        Ok(Self { rows, preflight_charge: charge })
    }

    fn files(&self) -> impl Iterator<Item = (&PathBuf, &FixedLibraryBaseline)> {
        self.rows.iter().map(|(_, path, baseline)| (path, baseline))
    }
}

struct UiDispatcherCapture{index:Option<usize>,prepared:dq_analyze::ui_actions_policy::PreparedDispatcher}
pub(crate) struct WorkspaceCapture {
    source: Weak<SourceExportMapping>,
    raw_source:Option<Weak<RawSourceIdentity>>,
    engine_no_model:Option<crate::runner_host::workspace_discovery::EngineNoModelProof>,
    ui_dispatcher:Option<UiDispatcherCapture>,
    source_revision: u128,
    policy_revision: u128,
    issuance: u64,
    discovery: Arc<DiscoveryReceipt>,
    shared_derived: Option<Arc<crate::input_snapshot::DerivedPreflight>>,
    files: Box<[File]>,
    configuration: PathBuf,
    config: Option<SharedBytes>,
    auxiliary: Vec<crate::policy_request::WorkspaceAuxiliaryQuestion>,
    deadline: Option<(PathBuf,Option<SharedBytes>)>,
    library_baseline: Option<(PathBuf, FixedLibraryBaseline)>,
    full_ci_baselines: Option<Box<FullCiBaselines>>,
    check_grep:Option<[Option<usize>;6]>,
    keys_manifest:Option<Option<usize>>,
    base_vars_configuration:Option<Option<usize>>,
    map_edits: Option<Vec<MapEditsFile>>,
    paired_dmm: Option<Arc<crate::query_db::FundedPairedDmm>>,
    raw_spool: Option<Arc<WorkspaceRawSpool>>,
    facts: InputSnapshot,
}
/// Actor rows use the exact legacy selected Tree, including hidden DM.
#[derive(Clone, Copy)]
pub(crate) enum SiliconActorDomain<'a> {
    CodeOnly,
    SelectedCodeMaps(&'a dq_analyze::captured_allow_annotations::full_unused::SelectedTreePlanData),
    SelectedAuthored(&'a dq_analyze::captured_allow_annotations::full_unused::SelectedTreePlanData),
}
impl SiliconActorDomain<'_> {
    fn includes(self, relative: &str) -> bool {
        if let Self::SelectedAuthored(plan) = self { return plan.matches_loaded_dm(relative); }
        relative.ends_with(".dm")
            && (relative.starts_with("code/")
                || (matches!(self, Self::SelectedCodeMaps(_)) && relative.starts_with("maps/")))
    }
}

impl WorkspaceCapture {
    pub(crate) fn ui_dispatcher_index(&self)->io::Result<Option<usize>>{
     self.ui_dispatcher.as_ref().map(|value|value.index).ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"UI dispatcher was not requested"))
    }
    pub(crate) fn prepared_ui_dispatcher(&self)->io::Result<&dq_analyze::ui_actions_policy::PreparedDispatcher>{
     self.ui_dispatcher.as_ref().map(|value|&value.prepared).ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"actual prepared UI dispatcher absent"))
    }
    pub(crate) fn require_analysis_subject(&self,subject:&crate::input_snapshot::OriginalAnalysisSubject)->io::Result<()>{if !subject.same_discovery(&self.discovery)||!subject.matches_workspace_root(&self.discovery.contract().root){return Err(io::Error::new(io::ErrorKind::InvalidInput,"Analyze subject belongs to another actual workspace discovery"))}Ok(())}
    pub(crate) fn semantic_order_question(&self)->Option<crate::policy_request::WorkspaceAuxiliaryQuestion>{use crate::policy_request::WorkspaceAuxiliaryQuestion as Q;[Q::SemReads,Q::UntrackedInputs,Q::SetterPublishes,Q::SysReactive,Q::Lifeforms,Q::DerivedReads].into_iter().find(|question|self.auxiliary.contains(question))}
    pub(crate) fn has_map_edits_capture(&self) -> bool {
        crate::policy_request::WorkspaceAuxiliaryQuestion::admits_map_edits_capture(&self.auxiliary)
    }

    pub(crate) fn has_authored_doc_ui_capture(&self) -> bool {
        use crate::policy_request::WorkspaceAuxiliaryQuestion as Q;

        self.raw_source.is_none()
            && Q::authored_doc_ui_roots(&self.auxiliary)
                .is_some_and(|roots| self.discovery.matches_authored_doc_ui_profile(roots))
            && self.ui_dispatcher.is_some()
            && (self.map_edits.is_some() || self.paired_dmm.is_some())
    }

    pub(crate) fn has_extended_authored_doc_ui_capture(&self) -> bool {
        use crate::policy_request::WorkspaceAuxiliaryQuestion as Q;
        Q::is_extended_authored_doc_ui(self.auxiliary()) && self.has_authored_doc_ui_capture()
    }

    pub(crate) fn for_each_map_edit_file(
        &self, scope: &crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,
        mut visit: impl FnMut(&str, &dq_analyze::map_edits_policy::ParsedMap) -> io::Result<()>,
    ) -> io::Result<()> {
        self.require_scope(scope)?;
        if !self.has_map_edits_capture() {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "map_edits current capture role differs"));
        }
        let maps = self.map_edits.as_ref()
            .ok_or_else(|| io::Error::other("map_edits has no complete observed input owner"))?;
        for map in maps {
            crate::daemon::control::checkpoint()?;
            visit(&map.relative, &map.rows)?;
        }
        self.require_scope(scope)?;
        crate::daemon::control::checkpoint()
    }

    pub(crate) fn has_paired_dmm(&self) -> bool { self.paired_dmm.is_some() }

    pub(crate) fn with_paired_map_rows(
        &self, scope: &crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,
        budget: &Arc<dq_analyze::captured_generator_budget::Budget>,
        mut visit: impl FnMut(&str, &str, &str, usize) -> io::Result<()>,
    ) -> io::Result<()> {
        self.require_scope(scope)?;
        let stage = self.paired_dmm.as_ref().ok_or_else(|| io::Error::other("paired maps absent"))?;
        let stage_facts = stage.facts();
        let mut stage = stage.stage.lock().map_err(|_| io::Error::other("paired maps poisoned"))?;
        for index in 0..stage.map_order().len() {
            crate::daemon::control::checkpoint()?;
            let ordinal = stage.map_order()[index];
            let path = stage_facts.path(ordinal)?;
            let scratch = dq_analyze::captured_generator_budget::Budget::scoped_temporaries(budget).map_err(map_edits_quota)?;
            scratch.charge(path.as_os_str().len().checked_mul(8).and_then(|n| n.checked_add(512))
                .ok_or(io::ErrorKind::OutOfMemory)?).map_err(map_edits_quota)?;
            let relative = dq_analyze::util::rel_slash(path, self.root());
            stage.take_map(ordinal, &scratch, |ty, var, line| visit(&relative, ty, var, line))?;
        }
        self.require_scope(scope)
    }

    pub(crate) fn paired_grep_fragment(
        &self, scope: &crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,
        ordinal: usize, relative: &str, budget: &dq_analyze::captured_generator_budget::Budget,
    ) -> Result<dq_analyze::lints::check_grep::native::StaticFileData, dq_analyze::captured_reactive_reads::Failure> {
        self.require_scope(scope)?;
        let stage = self.paired_dmm.as_ref().ok_or_else(|| io::Error::other("paired grep absent"))?;
        stage.stage.lock().map_err(|_| io::Error::other("paired grep poisoned"))?
            .take_grep(ordinal, relative, budget)
    }

    pub(crate) fn has_semantic_question(&self,question:crate::policy_request::WorkspaceAuxiliaryQuestion)->bool{question.is_semantic()&&self.auxiliary.contains(&question)}

    pub(crate) fn has_auxiliary_question(&self,question:crate::policy_request::WorkspaceAuxiliaryQuestion)->bool{self.auxiliary.contains(&question)}
    pub(crate) fn matches_auxiliary_questions(&self,questions:&[crate::policy_request::WorkspaceAuxiliaryQuestion])->bool{self.auxiliary.as_slice()==questions}

    /// Exact fixed original manifest used by the unique declaration order policy.
    /// Missing is an actual recorded negative; unselected is a refusal.
    pub(crate) fn with_keys_manifest<R>(&self,scope:&crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,visit:impl FnOnce(Option<&[u8]>)->Result<R,dq_analyze::captured_reactive_reads::Failure>)->Result<R,dq_analyze::captured_reactive_reads::Failure>{
     use dq_analyze::captured_reactive_reads::Failure;self.require_scope(scope)?;
     if !self.auxiliary.contains(&crate::policy_request::WorkspaceAuxiliaryQuestion::Keys){return Err("keys original manifest question was not selected".into())}
     self.with_order_manifest(scope,visit)
    }
    pub(crate) fn with_op_order_manifest<R>(&self,scope:&crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,visit:impl FnOnce(Option<&[u8]>)->Result<R,dq_analyze::captured_reactive_reads::Failure>)->Result<R,dq_analyze::captured_reactive_reads::Failure>{
     use crate::policy_request::WorkspaceAuxiliaryQuestion as Q;
     self.require_scope(scope)?;
     let questions=self.auxiliary.as_slice();
     if questions != [Q::OpOrder] && questions != Q::SELECTED_ORDER_AND_OWNERSHIP
          && !((questions == Q::PRIVATE_EXTENDED_AUTHORED_ORDINARY_SEMANTIC || Q::is_private_authored_checker(questions)) && self.has_extended_authored_doc_ui_capture()) {
      return Err("actual op_order fixed manifest purpose absent".into());
     }
     self.with_order_manifest(scope,visit)
    }
    pub(crate) fn with_semantic_manifest<R>(&self,scope:&crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,question:crate::policy_request::WorkspaceAuxiliaryQuestion,visit:impl FnOnce(Option<&[u8]>)->Result<R,dq_analyze::captured_reactive_reads::Failure>)->Result<R,dq_analyze::captured_reactive_reads::Failure>{
     use crate::policy_request::WorkspaceAuxiliaryQuestion as Q;
     if !matches!(question,Q::SemReads|Q::UntrackedInputs|Q::SetterPublishes|Q::SysReactive|Q::Lifeforms|Q::DerivedReads)||!self.auxiliary.contains(&question){return Err("semantic fixed manifest question was not selected".into())}
     self.with_order_manifest(scope,visit)
    }
    fn with_order_manifest<R>(&self,scope:&crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,visit:impl FnOnce(Option<&[u8]>)->Result<R,dq_analyze::captured_reactive_reads::Failure>)->Result<R,dq_analyze::captured_reactive_reads::Failure>{
     use dq_analyze::captured_reactive_reads::Failure;self.require_scope(scope)?;
     let pending=match self.keys_manifest.ok_or("keys original manifest observation unavailable")?{None=>visit(None),Some(index)=>{let file=self.files.get(index).ok_or("keys original manifest file absent")?;if file.path(&self.discovery).parent()!=Some(self.root())||file.path(&self.discovery).file_name()!=Some(std::ffi::OsStr::new("deepquarry.dme")){return Err("keys original fixed manifest role differs".into())}let original=self.original(index,scope)?;visit(Some(match &original{RecordedSourceOriginal::Utf8(text)=>text.as_bytes(),RecordedSourceOriginal::Bytes(bytes)=>bytes.as_slice()}))}};
     if matches!(&pending,Err(Failure::Operational(_))){return pending}self.require_scope(scope)?;crate::daemon::control::checkpoint()?;pending
    }
    pub(crate) fn require_check_grep_archive(&self,scope:&crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,archive:&dm_tree::frontend::BodyArchive)->io::Result<()>{
     self.check_grep_names(scope)?;if !Weak::ptr_eq(&self.source,&Arc::downgrade(archive.source_mapping())){return Err(io::Error::new(io::ErrorKind::InvalidInput,"check_grep body archive belongs to another actual source mapping"))}Ok(())
    }
    pub(crate) fn check_grep_names<'a>(&'a self,scope:&crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>)->io::Result<(&'a[PathBuf],&'a[PathBuf])>{
     self.require_scope(scope)?;if self.check_grep.is_none()||(!self.auxiliary.contains(&crate::policy_request::WorkspaceAuxiliaryQuestion::CheckGrep)&&!self.auxiliary.contains(&crate::policy_request::WorkspaceAuxiliaryQuestion::CheckGrepBaseline)){return Err(io::Error::new(io::ErrorKind::Unsupported,"check_grep auxiliary observations were not selected"))}self.discovery.check_grep_names()
    }
    pub(crate) fn check_grep_purpose(&self,scope:&crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>)->io::Result<dq_analyze::lints::check_grep::native::Purpose>{
     self.check_grep_names(scope)?;use crate::policy_request::WorkspaceAuxiliaryQuestion as Q;use dq_analyze::lints::check_grep::native::Purpose;
     match(self.auxiliary.contains(&Q::CheckGrep),self.auxiliary.contains(&Q::CheckGrepBaseline)){(true,false)=>Ok(Purpose::Check),(false,true)=>Ok(Purpose::Baseline),_=>Err(io::Error::new(io::ErrorKind::InvalidInput,"exact actual CheckGrep purpose unavailable"))}
    }
    pub(crate) fn with_check_grep_fixed<R>(&self,scope:&crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,which:dq_analyze::lints::check_grep::native::Fixed,visit:impl FnOnce(Option<&[u8]>)->Result<R,dq_analyze::captured_reactive_reads::Failure>)->Result<R,dq_analyze::captured_reactive_reads::Failure>{
     use dq_analyze::captured_reactive_reads::Failure;let purpose=self.check_grep_purpose(scope)?;if !dq_analyze::lints::check_grep::native::Fixed::for_purpose(purpose).contains(&which){return Err("fixed observation was not requested by the actual CheckGrep baseline purpose".into())}
     let indices=self.check_grep.as_ref().ok_or("check_grep fixed observations unavailable")?;
     let pending=match indices[which.index()]{None=>visit(None),Some(index)=>{
      let file=self.files.get(index).ok_or("check_grep fixed source index absent")?;
      if file.path(&self.discovery).strip_prefix(self.root()).ok()!=Some(Path::new(which.relative())){return Err("check_grep fixed source role differs".into())}
      let original=self.original(index,scope)?;visit(Some(match &original{RecordedSourceOriginal::Utf8(text)=>text.as_bytes(),RecordedSourceOriginal::Bytes(bytes)=>bytes.as_slice()}))
     }};
     if matches!(&pending,Err(Failure::Operational(_))){return pending}self.require_scope(scope)?;crate::daemon::control::checkpoint()?;pending
    }
    pub(crate) fn for_each_check_grep_dme(&self,scope:&crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,visit:&mut dyn FnMut(&str,&[u8])->Result<(),dq_analyze::captured_reactive_reads::Failure>)->Result<(),dq_analyze::captured_reactive_reads::Failure>{
     use dq_analyze::captured_reactive_reads::Failure;let(names,_)=self.check_grep_names(scope)?;let mut count=0;
     for(index,file)in self.files.iter().enumerate(){
      if file.path(&self.discovery).parent()!=Some(self.root()){continue}let Some(name)=file.path(&self.discovery).file_name().and_then(|name|name.to_str())else{continue};
      if !dq_analyze::lints::check_grep::native::is_root_dme(name){continue}
      if names.binary_search(file.path(&self.discovery)).is_err(){return Err("check_grep root manifest is outside its typed discovery".into())}
      crate::daemon::control::checkpoint()?;self.require_scope(scope)?;
      let original=self.original(index,scope)?;let pending=visit(name,match &original{RecordedSourceOriginal::Utf8(text)=>text.as_bytes(),RecordedSourceOriginal::Bytes(bytes)=>bytes.as_slice()});
      if matches!(&pending,Err(Failure::Operational(_))){return pending}self.require_scope(scope)?;crate::daemon::control::checkpoint()?;pending?;count+=1;
     }
     if count!=names.len(){return Err("check_grep root manifest traversal omitted an observed file".into())}self.require_scope(scope)?;Ok(())
    }
    pub(crate) fn check_grep_page(&self,scope:&crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,start:usize,count:usize,budget:usize,configuration:&dq_analyze::captured_raw_file::Config,include_exempt:bool)->io::Result<(Vec<crate::query_db::CurrentWorkspaceRawFile>,usize)>{
     self.check_grep_names(scope)?;
     self.page_needed(scope,start,count,budget,|relative|Ok(
         !(self.has_paired_dmm() && paired_dmm_relative(relative))
         && dq_analyze::lints::check_grep::native::selects_source(relative)
         && (include_exempt || !configuration.policy_path_exempt("check_grep","",relative))))
    }

    pub(crate) fn census(self: &Arc<Self>, census: &mut crate::heap_census::HeapCensus) {
        let owner = "query_snapshot.workspace.capture";
        if !census.arc_object(owner, self) {
            return;
        }
        census.slice(owner, self.files.as_ref(), true);
        census.path(owner, &self.configuration);
        if let Some(spool) = &self.raw_spool {
            spool.visit_storage(|pointer, payload, capacity| { census.exposed_buffer(owner, pointer, payload, capacity); });
        }
        if let Some(ui)=&self.ui_dispatcher{
            ui.prepared.visit_exposed_storage(|pointer,payload,capacity|{census.exposed_buffer(owner,pointer,payload,capacity);});
            if ui.prepared.has_opaque_storage(){census.unknown(owner,"UI prepared normalizer regex/hash buckets are covered by its conservative admission envelope");}
        }

        if let Some(raw)=&self.raw_source{let bytes=std::mem::size_of::<RawSourceIdentity>()+2*std::mem::size_of::<usize>();census.exposed_buffer("query_snapshot.workspace.raw_identity",raw.as_ptr()as usize,bytes,bytes);}
        for file in &self.files {
            if let FilePath::Fixed(path) = &file.path {
                let bytes = std::mem::size_of::<PathBuf>();
                census.exposed_buffer(owner, path.as_ref() as *const PathBuf as usize, bytes, bytes);
                census.path(owner, path);
            }
            match &file.original {
                Original::Native(_) | Original::PairedDmm(_) | Original::Spool(_) => {}
                Original::RawInput(lease) => {census.source_acquisition(lease);}
                Original::Owned(bytes) => {
                    if census.shared_bytes_owner(owner, bytes) {
                        census.vec_payload(owner, bytes.shared_owner().bytes());
                    }
                }
            }
        }
        if let Some(bytes) = &self.config {
            if census.shared_bytes_owner(owner, bytes) {
                census.vec_payload(owner, bytes.shared_owner().bytes());
            }
        }
        if let Some(maps) = &self.map_edits {
            let owner = "query_snapshot.workspace.map_edits";
            census.vec_payload(owner, maps);
            for map in maps {
                census.string(owner, &map.relative);
                map.rows.visit_storage(|pointer, payload, capacity| {
                    if capacity != 0 { census.exposed_buffer(owner, pointer, payload, capacity); }
                });
            }
        }
        census.vec_payload(owner,&self.auxiliary);
        for (path, bytes) in self.deadline.iter().map(|(path, bytes)| (path, bytes.as_ref()))
            .chain(self.library_baseline.iter().map(|(path, baseline)| (path, baseline.bytes())))
            .chain(self.full_ci_baselines.iter().flat_map(|capture| capture.files())
                .map(|(path, baseline)| (path, baseline.bytes()))) {
            census.path(owner,path);
            if let Some(bytes)=bytes{if census.shared_bytes_owner(owner, bytes){census.vec_payload(owner,bytes.shared_owner().bytes());}}
        }
        if let Some(capture) = &self.full_ci_baselines {
            let bytes = std::mem::size_of::<FullCiBaselines>();
            census.exposed_buffer(owner, capture.as_ref() as *const FullCiBaselines as usize, bytes, bytes);
            census.vec_payload(owner, &capture.rows);
        }
        self.discovery.census(census);
        census.workspace_policy_facts(&self.facts);
    }

    pub(crate) fn auxiliary(&self)->&[crate::policy_request::WorkspaceAuxiliaryQuestion]{&self.auxiliary}
    pub(crate) fn library_sites_baseline<'a>(
        &'a self, scope: &crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,
    ) -> io::Result<Option<&'a [u8]>> {
        self.require_scope(scope)?;
        let (path, bytes) = self.library_baseline.as_ref().ok_or_else(|| io::Error::new(
            io::ErrorKind::Unsupported, "actual fixed library baseline role was not captured",
        ))?;
        if self.auxiliary.as_slice() != [crate::policy_request::WorkspaceAuxiliaryQuestion::LibraryLayeringFullAllow]
            || path.strip_prefix(self.root()).ok() != Some(Path::new(LIBRARY_SITES_BASELINE))
        {
            return Err(io::Error::new(io::ErrorKind::InvalidData, "actual fixed library baseline scope differs"));
        }
        crate::daemon::control::checkpoint()?;
        Ok(bytes.bytes().map(SharedBytes::as_slice))
    }
    pub(crate) fn full_ci_baseline<'a>(
        &'a self, scope: &crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,
        meta: &dq_analyze::lint::Meta,
    ) -> io::Result<Option<&'a [u8]>> {
        use crate::policy_request::WorkspaceAuxiliaryQuestion as Q;
        use dq_analyze::lint::Policy;
        self.require_scope(scope)?;
        if self.auxiliary != Q::PRIVATE_FULL_REGISTRY {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "full CI baseline requires its private registry frame"));
        }
        let path = match meta.policy {
            Policy::Sites { baseline, .. } | Policy::Ceilings { baseline, .. } => baseline,
            _ => return Err(io::Error::new(io::ErrorKind::InvalidInput, "policy does not use an observed baseline")),
        };
        let capture = self.full_ci_baselines.as_ref()
            .ok_or_else(|| io::Error::other("workspace has no full CI baseline observations"))?;
        let (_, _, baseline) = capture.rows.iter().find(|(relative, _, _)| *relative == path)
            .ok_or_else(|| io::Error::other("full CI baseline observation is missing from the registered roster"))?;
        crate::daemon::control::checkpoint()?;
        Ok(baseline.bytes().map(SharedBytes::as_slice))
    }

    pub(crate) fn deadline_observation(&self)->io::Result<(&Path,Option<&[u8]>)>{self.deadline.as_ref().map(|(path,bytes)|(path.as_path(),bytes.as_ref().map(SharedBytes::as_slice))).ok_or_else(||io::Error::other("DeadlinePolling auxiliary was not admitted and observed"))}
    pub(crate) fn issuance(&self) -> u64 {
        self.issuance
    }
    pub(crate) fn policy_revision(&self) -> u128 {
        self.policy_revision
    }
    pub(crate) fn recursive_roots(&self) -> &[PathBuf] {
        &self.discovery.contract().recursive_roots
    }
    pub(crate) fn matches_source(
        &self,
        mapping: &Arc<SourceExportMapping>,
        revision: u128,
    ) -> bool {
        Weak::ptr_eq(&self.source, &Arc::downgrade(mapping)) && self.source_revision == revision
    }
    pub(crate) fn matches_frontend(&self, frontend: &ColdFrontend) -> bool {
        frontend
            .source_export_mapping()
            .is_some_and(|mapping| Weak::ptr_eq(&self.source, &Arc::downgrade(mapping)))
            && self.source_revision == frontend.source_export_revision()
    }
    pub(crate) fn matches_request(
        &self,
        request: &crate::policy_request::WorkspacePolicyRequest,
    ) -> bool {
        self.root() == request.root
            && self.configuration == request.configuration
            && self.discovery.contract().recursive_roots == request.recursive_roots
    }
    pub(crate) fn is_recorded_in(&self, complete: &InputSnapshot) -> bool {
        let mut same = false;
        complete.visit_recorded_storage(|all_files, all_folders, all_negative, all_generated| {
            self.facts
                .visit_recorded_storage(|files, folders, negative, generated| {
                    same = files.iter().all(|(p, f)| all_files.get(p) == Some(f))
                        && folders.iter().all(|(p, f)| all_folders.get(p) == Some(f))
                        && negative.is_subset(all_negative)
                        && generated.is_subset(all_generated);
                });
        });
        same && self.shared_derived.as_ref().is_none_or(|donor| donor.workspace_files_in(complete))
            && self.raw_spool.as_ref().is_none_or(|spool| spool.facts_in(complete))
            && self.paired_dmm.as_ref().is_none_or(|owner| owner.facts().facts_in(complete))
            && self.facts.original_observations_subset_of(complete) && self
            .policy_directories()
            .iter()
            .all(|(p, f)| complete.policy_directories().get(p) == Some(f))
    }

    pub(crate) fn covers_extended_reactive_raw_domains(
        &self, admit: &mut dyn FnMut(usize) -> io::Result<()>,
    ) -> io::Result<bool> {
        use crate::policy_request::WorkspaceAuxiliaryQuestion as Q;
        use dq_analyze::selected_exclusions_wire::Roster;

        let expected = Roster::AllRawFilePolicies.workspace_roots();
        let actual = self.recursive_roots();
        if self.raw_source.is_some() || !self.matches_auxiliary_questions(Q::SELECTED_REACTIVE)
            || actual.len() != expected.len()
            || actual.iter().zip(expected).any(|(path, name)| path.strip_prefix(self.root()).ok() != Some(Path::new(name)))
        {
            return Ok(false);
        }
        // Observe both extra roots under this capture's real recorder. Their
        // genuine absence is permitted for the policies that select them.
        Ok(self.discovery.covers_dm_roots(dq_analyze::tree::CODE_MAPS_DM.roots, false, admit)?
            && self.discovery.covers_dm_roots(&[("interface", "dm"), ("modular_chomp", "dm")], true, admit)?)
    }

    pub(crate) fn covers_selected_raw_policies(&self,names:&[String],admit:&mut dyn FnMut(usize)->io::Result<()>)->io::Result<bool>{
     if names.is_empty(){return Ok(false)}
     for name in names{let Some(meta)=dq_analyze::captured_raw_policy::metadata(name)else{return Ok(false)};if !dq_analyze::captured_raw_policy::RAW_FILE_LINTS.contains(&name.as_str())||!self.discovery.covers_dm_roots(meta.select.roots,true,admit)?{return Ok(false)}}Ok(true)
    }
    /// The actual unfiltered recursive DM receipt also covers dot paths.
    /// This method does not reuse the hidden-excluding CODE policy page.
    pub(crate) fn covers_instance_list(&self,admit:&mut dyn FnMut(usize)->io::Result<()>)->io::Result<bool>{self.discovery.covers_dm_roots(dq_analyze::instance_list_policy::META.select.roots,false,admit)}
    pub(crate) fn instance_list_page(&self,scope:&crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,start:usize,count:usize,budget:usize,config:Option<&dq_analyze::captured_raw_file::Config>)->io::Result<(Vec<crate::query_db::CurrentWorkspaceRawFile>,usize)>{self.page_needed(scope,start,count,budget,|relative|Ok(dq_analyze::instance_list_policy::selects_path(relative)&&!config.is_some_and(|config|config.policy_path_exempt("instance_list","",relative))))}
    pub(crate) fn covers_code_dm(&self,admit:&mut dyn FnMut(usize)->io::Result<()>)->io::Result<bool>{if self.engine_no_model.is_some(){return Ok(false)}self.discovery.covers_code_dm(admit)}
    pub(crate) fn covers_generator_cli_tests(&self,admit:&mut dyn FnMut(usize)->io::Result<()>)->io::Result<bool>{self.discovery.covers_generator_cli_tests(admit)}
    pub(crate) fn root(&self) -> &Path {
        &self.discovery.contract().root
    }
    pub(crate) fn require_scope(
        &self,
        scope: &crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,
    ) -> io::Result<()> {
        if !scope.matches_capture(
            self,
            &self.source,
            self.raw_source.as_ref(),
            self.source_revision,
            self.policy_revision,
        ) {
            return Err(io::Error::other("workspace source scope is stale/foreign"));
        }
        Ok(())
    }
    pub(crate) fn page(
        &self,
        scope: &crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,
        start: usize,
        count: usize,
        budget: usize,
        scopes: &[Arc<dq_analyze::captured_raw_file::Scope>],
    ) -> io::Result<(Vec<crate::query_db::CurrentWorkspaceRawFile>, usize)> {
        self.page_needed_using(scope,start,count,budget,scopes.len()==1,|relative|{
            let mut excluded=true;for scope in scopes{excluded &= scope.excludes_path(relative).map_err(io::Error::other)?;}Ok(!excluded)
        })
    }
    /// Policy-only CODE_DM input loan. No lint scope may suppress semantic
    /// marker/lexical work, and no raw tuple becomes a compiled source receipt.
    pub(crate) fn code_page(&self,scope:&crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,start:usize,count:usize,budget:usize)->io::Result<(Vec<crate::query_db::CurrentWorkspaceRawFile>,usize)>{
        self.page_needed(scope,start,count,budget,|relative|Ok(dq_analyze::captured_raw_file::is_code_dm(relative)))
    }
    pub(crate) fn code_policy_page(&self,scope:&crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,start:usize,count:usize,budget:usize,configuration:&dq_analyze::captured_raw_file::Config,policy:&'static str,group:&'static str)->io::Result<(Vec<crate::query_db::CurrentWorkspaceRawFile>,usize)>{self.page_needed(scope,start,count,budget,|relative|Ok(dq_analyze::captured_raw_file::is_code_dm(relative)&&!configuration.policy_path_exempt(policy,group,relative)))}
    // Legacy Tree::load keeps hidden DM even when a selected file scan
    // excludes it. Silicon's actor phase can name those same captured files.
    pub(crate) fn covers_joined_silicon_actors(
        &self, plan: &dq_analyze::captured_allow_annotations::full_unused::SelectedTreePlanData,
        admit: &mut dyn FnMut(usize) -> io::Result<()>,
    ) -> io::Result<bool> {
        use crate::policy_request::WorkspaceAuxiliaryQuestion as Q;
        if !(Q::is_private_authored_actor_domain(self.auxiliary()) || Q::is_private_grep_domain(self.auxiliary()))
            || !self.has_extended_authored_doc_ui_capture() {
            return Ok(false);
        }
        for directory in plan.loaded_dm_roots() {
            if directory.is_empty() || !self.discovery.covers_dm_roots(&[(directory, "dm")], true, admit)? {
                return Ok(false);
            }
        }
        Ok(true)
    }
    pub(crate) fn silicon_page(&self,scope:&crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,start:usize,count:usize,budget:usize,domain:SiliconActorDomain<'_>)->io::Result<(Vec<crate::query_db::CurrentWorkspaceRawFile>,usize)>{
        self.page_needed(scope,start,count,budget,|relative|Ok(domain.includes(relative)))
    }
    pub(crate) fn silicon_file_index(&self,scope:&crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,relative:&str,domain:SiliconActorDomain<'_>)->io::Result<Option<usize>>{
        self.require_scope(scope)?;
        if !domain.includes(relative)||relative.split('/').any(|part|matches!(part,""|"."|".."))||relative.contains('\\'){return Ok(None)}
        let path=self.root().join(relative);
        // Discovery orders by relative slash path, rather than platform
        // PathBuf comparison. Compare the original names without sorting again.
        for(index,source)in self.discovery.files().iter().enumerate(){
            crate::daemon::control::checkpoint()?;
            if *source==path{
                if self.files.get(index).is_none_or(|file|file.path(&self.discovery)!=&path){return Err(io::Error::new(io::ErrorKind::InvalidData,"silicon source does not match its actual discovery index"))}
                return Ok(Some(index));
            }
        }
        Ok(None)
    }
    pub(crate) fn generator_test_page(&self,scope:&crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,start:usize,count:usize,budget:usize)->io::Result<(Vec<crate::query_db::CurrentWorkspaceRawFile>,usize)>{
        self.page_needed(scope,start,count,budget,|relative|Ok(dq_analyze::captured_raw_file::is_generator_cli_test_source(relative)))
    }
    pub(crate) fn covers_hygiene(&self,admit:&mut dyn FnMut(usize)->io::Result<()>)->io::Result<bool>{self.discovery.covers_dm_roots(dq_analyze::captured_sys_hygiene_pages::selected_roots(),true,admit)}
    pub(crate) fn hygiene_page(&self,scope:&crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,start:usize,count:usize,budget:usize,configuration:&dq_analyze::captured_raw_file::Config,policy:&'static str,group:&'static str)->io::Result<(Vec<crate::query_db::CurrentWorkspaceRawFile>,usize)>{self.page_needed(scope,start,count,budget,|relative|Ok(dq_analyze::captured_sys_hygiene_pages::selects_path(relative)&&!configuration.policy_path_exempt(policy,group,relative)))}
    /// Exact tracked declaration/index domain; selected pass applies its own original policy exclusions before any original file loan.
    pub(crate) fn tracked_page(&self,scope:&crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,start:usize,count:usize,budget:usize,configuration:Option<(&dq_analyze::captured_raw_file::Config,bool)>)->io::Result<(Vec<crate::query_db::CurrentWorkspaceRawFile>,usize)>{self.page_needed(scope,start,count,budget,|relative|Ok(dq_analyze::captured_sys_hygiene_pages::selects_path(relative)&&configuration.is_none_or(|(config,tests)|if tests{dq_analyze::tracked_policy::TEST_PREFIXES.iter().any(|prefix|relative.starts_with(prefix))}else{!config.policy_path_exempt("tracked","",relative)})))}
    fn page_needed(&self,scope:&crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,start:usize,count:usize,budget:usize,needed:impl FnMut(&str)->io::Result<bool>)->io::Result<(Vec<crate::query_db::CurrentWorkspaceRawFile>,usize)>{
        self.page_needed_using(scope,start,count,budget,false,needed)
    }
    fn page_needed_using(&self,scope:&crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,start:usize,count:usize,budget:usize,retain_raw_selection:bool,mut needed:impl FnMut(&str)->io::Result<bool>)->io::Result<(Vec<crate::query_db::CurrentWorkspaceRawFile>,usize)>{
        if self.engine_no_model.is_some(){return Err(io::Error::new(io::ErrorKind::Unsupported,"engine metadata-only completion grants no source payload traversal"))}
        self.require_scope(scope)?;
        if count == 0 || count > 128 {
            return Err(io::Error::other(
                "workspace page needs one to128 file slots",
            ));
        }
        let mut result = Vec::with_capacity(count.min(self.files.len().saturating_sub(start)));
        let mut owners = BTreeMap::new();
        let mut path_bytes = 0usize;
        let mut total = 0usize;
        let mut end = start;
        for (index, file) in self.files.iter().enumerate().skip(start).take(count) {
            crate::daemon::control::checkpoint()?;
            let rel = relative_filesystem_path(file.path(&self.discovery), self.root())
                .ok_or_else(|| io::Error::other("workspace page path escapes root"))?
                .to_string_lossy()
                .replace('\\', "/");
            let excluded = !needed(&rel)?;
            let path_charge = file.path(&self.discovery).capacity().checked_add(
                if retain_raw_selection { rel.capacity() } else { 0 },
            ).ok_or_else(|| io::Error::other("workspace path accounting overflow"))?;
            let spool_frame = if let Original::Spool(ordinal) = &file.original {
                let spool = self.raw_spool.as_ref()
                    .ok_or_else(|| io::Error::other("actual workspace raw spool is absent"))?;
                if !matches!(&file.path, FilePath::Discovered(index) if index == ordinal) {
                    return Err(io::Error::other("raw spool discovery slot differs"));
                }
                Some((spool, *ordinal))
            } else {
                None
            };
            let proof = match &file.original {
                Original::Native(native) => SourceProof::Native(
                    scope.captured_acquisition(self, native.occurrence)?.original_identity(),
                ),
                Original::RawInput(lease)=>SourceProof::Native(lease.original_identity()),
                Original::Owned(bytes) => SourceProof::Owned(bytes.downgrade()),
                Original::PairedDmm(ordinal) => SourceProof::PairedDmm(*ordinal),
                Original::Spool(_) => {
                    let (spool, ordinal) = spool_frame
                        .ok_or_else(|| io::Error::other("raw spool page has no exact frame"))?;
                    SourceProof::Spool(spool.identity_for_slot(ordinal)?)
                }
            };
            let mut own = BTreeMap::new();
            let mut funded=std::collections::BTreeSet::new();
            if let Original::RawInput(lease)=&file.original{dq_analyze::captured_raw_file::visit_source_storage(lease.source_text(),|key,_|{funded.insert(key);});}

            let observe = |own: &mut BTreeMap<_, _>, text: &dm_preprocess::SourceText| {
                dq_analyze::captured_raw_file::visit_source_storage(text, |key, bytes| {
                    if funded.contains(&key) { return; }
                    own.entry(key)
                        .and_modify(|old: &mut usize| *old = (*old).max(bytes))
                        .or_insert(bytes);
                });
            };
            let text = if excluded {
                None
            } else if let Some((spool, ordinal)) = spool_frame {
                let available = budget.saturating_sub(total).saturating_sub(path_charge);
                let Some(text) = spool.normalized_slot(ordinal, available)? else {
                    if result.is_empty() {
                        return Err(io::Error::new(io::ErrorKind::OutOfMemory,
                            "whole spooled source normalization exceeds remaining input budget"));
                    }
                    break;
                };
                observe(&mut own, &text);
                Some(text)
            } else {
                let original = self.original(index, scope)?;
                let clean = match &original {
                    RecordedSourceOriginal::Utf8(text) if !text.as_bytes().contains(&b'\r') => Some(text),
                    _ => None,
                };
                let peak = if let Some(text) = clean {
                    observe(&mut own, text);
                    own.iter()
                        .filter(|(key, _)| !owners.contains_key(*key))
                        .try_fold(0usize, |n, (_, b)| n.checked_add(*b))
                        .ok_or_else(|| io::Error::other("workspace source capacity overflow"))?
                } else {
                    let raw = match &original {
                        RecordedSourceOriginal::Utf8(text) => text.as_bytes(),
                        RecordedSourceOriginal::Bytes(bytes) => bytes.as_slice(),
                    };
                    dq_analyze::captured_raw_file::analyze_raw_len(raw)
                        .map_err(io::Error::other)?
                        .checked_mul(4)
                        .and_then(|n| n.checked_add(8192))
                        .ok_or_else(|| io::Error::other("workspace normalization peak overflow"))?
                };
                if total
                    .checked_add(path_charge)
                    .and_then(|n| n.checked_add(peak))
                    .is_none_or(|n| n > budget)
                {
                    if result.is_empty() {
                        return Err(io::Error::other(
                            "whole source normalization exceeds remaining input budget",
                        ));
                    }
                    break;
                }
                let text = if let Some(text) = clean {
                    dm_preprocess::SourceText::clone(text)
                } else {
                    let text = crate::input_snapshot::normalize_recorded_policy_original(&original);
                    observe(&mut own, &text);
                    text
                };
                Some(text)
            };
            let charge = own
                .values()
                .try_fold(0usize, |n, b| n.checked_add(*b))
                .ok_or_else(|| io::Error::other("workspace source accounting overflow"))?;
            for (key, bytes) in own {
                owners
                    .entry(key)
                    .and_modify(|old: &mut usize| *old = (*old).max(bytes))
                    .or_insert(bytes);
            }
            path_bytes = path_bytes
                .checked_add(path_charge)
                .ok_or_else(|| io::Error::other("workspace path accounting overflow"))?;
            total = owners
                .values()
                .try_fold(path_bytes, |n, b| n.checked_add(*b))
                .ok_or_else(|| io::Error::other("workspace page accounting overflow"))?;
            if total > budget {
                return Err(io::Error::other(
                    "workspace actual source capacity exceeds page input budget",
                ));
            }
            result.push(CurrentFile {
                path: file.path(&self.discovery).clone(),
                text,
                proof,
                charge,
                raw_selection: retain_raw_selection.then_some((rel, excluded)),
            });
            end = index + 1;
        }
        Ok((result, end))
    }
    #[cfg(test)]
    pub(crate) fn facts(&self) -> &InputSnapshot {
        assert!(self.shared_derived.is_none(), "joined workspace facts use the borrowed directory view");
        &self.facts
    }
    pub(crate) fn file_facts(&self) -> &InputSnapshot { &self.facts }
    pub(crate) fn borrows_file_facts(&self, donor: &crate::input_snapshot::DerivedPreflight) -> bool {
        self.shared_derived.as_deref().is_some_and(|actual| std::ptr::eq(actual, donor))
    }

    pub(crate) fn policy_directories(&self) -> &BTreeMap<PathBuf, crate::input_snapshot::PolicyDirectoryObservation> {
        if self.shared_derived.is_some() { self.discovery.policy_directories() }
        else { self.facts.policy_directories() }
    }
    pub(crate) fn file_count(&self) -> usize {
        self.files.len()
    }
    pub(crate) fn path(&self, index: usize) -> io::Result<&Path> {
        self.files
            .get(index)
            .map(|file| file.path(&self.discovery).as_path())
            .ok_or_else(|| io::Error::other("workspace file index unavailable"))
    }
    pub(crate) fn productive_ui_configuration(&self)->io::Result<Option<&dq_analyze::captured_raw_file::Config>>{self.discovery.productive_ui_configuration(&self.configuration)}
    pub(crate) fn productive_doc_configuration(&self)->io::Result<Option<&dq_analyze::captured_raw_file::Config>>{self.discovery.productive_doc_configuration(&self.configuration)}
    pub(crate) fn configuration(&self) -> (&Path, Option<&[u8]>) {
        (
            &self.configuration,
            self.config.as_ref().map(|bytes| bytes.as_slice()),
        )
    }
    pub(crate) fn original<'a>(
        &'a self,
        index: usize,
        scope: &'a crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,
    ) -> io::Result<RecordedSourceOriginal<'a>> {
        if !scope.matches_capture(
            self,
            &self.source,
            self.raw_source.as_ref(),
            self.source_revision,
            self.policy_revision,
        ) {
            return Err(io::Error::other(
                "workspace native source scope is stale or foreign",
            ));
        }
        match &self
            .files
            .get(index)
            .ok_or_else(|| io::Error::other("workspace file index unavailable"))?
            .original
        {
            Original::Native(native) => crate::input_snapshot::recorded_source_original(scope.captured_acquisition(self, native.occurrence)?),
            Original::RawInput(lease)=>crate::input_snapshot::recorded_source_original(lease),
            Original::Owned(bytes) => Ok(RecordedSourceOriginal::Bytes(bytes)),
            Original::PairedDmm(_) => Err(io::Error::new(io::ErrorKind::Unsupported, "paired DMM has no raw materialization")),
            Original::Spool(_) => Err(io::Error::new(io::ErrorKind::Unsupported, "raw spool requires bounded workspace page materialization")),
        }
    }
    // Exact borrowed owner accounting: metadata and extra owned originals count;
    // native bytes are NOT credited by hashes/equality but remain borrowed under
    // the active current SourceSnapshot guard and are not retained by this input.
    pub(crate) fn retained_charge(&self) -> io::Result<usize> {
        let mut count = std::mem::size_of_val(self)
            .checked_add(std::mem::size_of_val(self.files.as_ref()))
            .ok_or_else(|| io::Error::other("workspace metadata overflow"))?;
        let mut seen = std::collections::BTreeSet::new();
        if let Some(owner)=&self.shared_derived{owner.account_shared_capture_aliases(&mut seen)?;}
        let mut add = |bytes: usize| -> io::Result<()> {
            count = count
                .checked_add(bytes)
                .ok_or_else(|| io::Error::other("workspace capture overflow"))?;
            Ok(())
        };
        add(self.configuration.capacity())?;
        if let Some(spool) = &self.raw_spool { add(spool.retained_bytes())?; }
        if let Some(maps) = &self.map_edits {
            add(maps.capacity().checked_mul(std::mem::size_of::<MapEditsFile>())
                .ok_or_else(|| io::Error::from(io::ErrorKind::OutOfMemory))?)?;
            for map in maps {
                add(map.relative.capacity())?;
                let mut bytes = Some(0usize);
                map.rows.visit_storage(|_, _, capacity| bytes = bytes.and_then(|n| n.checked_add(capacity)));
                add(bytes.ok_or_else(|| io::Error::from(io::ErrorKind::OutOfMemory))?)?;
            }
        }
        if let Some(proof)=&self.engine_no_model{add(proof.preflight().charge())?;}
        if let Some(ui)=&self.ui_dispatcher{add(ui.prepared.budget_charge())?;}
        if self.raw_source.is_some(){add(std::mem::size_of::<RawSourceIdentity>()+std::mem::size_of::<crate::query_db::QueryDb>()+4*std::mem::size_of::<usize>())?;}
        for file in &self.files {
            if let FilePath::Fixed(path) = &file.path {
                add(std::mem::size_of::<PathBuf>() + path.capacity())?;
            }
            match &file.original {
                Original::Native(_) | Original::PairedDmm(_) | Original::Spool(_) => {}
                Original::RawInput(lease)=>{
                    let mut metadata=0usize;
                    lease.visit_storage(|storage|match storage{
                        dm_preprocess::source_acquisition::AcquisitionStorage::Object{address,bytes}=>{if seen.insert(address){metadata=metadata.saturating_add(bytes+2*std::mem::size_of::<usize>());}},
                        dm_preprocess::source_acquisition::AcquisitionStorage::Receipt{address,bytes,value}=>{if seen.insert(address){metadata=metadata.saturating_add(bytes+2*std::mem::size_of::<usize>());if let Some((path,fact_path,issuer))=crate::input_snapshot::recorded_source_receipt_storage(value){metadata=metadata.saturating_add(path.capacity()).saturating_add(if std::ptr::eq(path,fact_path){0}else{fact_path.capacity()});if seen.insert(Arc::as_ptr(issuer)as usize){metadata=metadata.saturating_add(2*std::mem::size_of::<usize>());}}}},
                        dm_preprocess::source_acquisition::AcquisitionStorage::Source(_)=>{}
                    });add(metadata)?;
                }
                Original::Owned(bytes) => {
                    let owner = bytes.shared_owner();
                    if seen.insert(owner as *const dm_resources::SharedBytesOwner as usize) {
                        add(std::mem::size_of_val(owner)
                            + 2 * std::mem::size_of::<usize>())?;
                        add(owner.bytes().capacity())?;
                    }
                }
            }
        }
        if let Some(bytes) = &self.config {
            let owner = bytes.shared_owner();
            if seen.insert(owner as *const dm_resources::SharedBytesOwner as usize) {
                add(std::mem::size_of_val(owner) + 2 * std::mem::size_of::<usize>())?;
                add(owner.bytes().capacity())?;
            }
        }
        add(self.auxiliary.capacity()*std::mem::size_of::<crate::policy_request::WorkspaceAuxiliaryQuestion>())?;
        for (path, bytes) in self.deadline.iter().map(|(path, bytes)| (path, bytes.as_ref()))
            .chain(self.library_baseline.iter().map(|(path, baseline)| (path, baseline.bytes())))
            .chain(self.full_ci_baselines.iter().flat_map(|capture| capture.files())
                .map(|(path, baseline)| (path, baseline.bytes()))) {
            add(path.capacity())?;
            if let Some(bytes)=bytes{let owner=bytes.shared_owner();if seen.insert(bytes.owner_address()){add(std::mem::size_of_val(owner)+2*std::mem::size_of::<usize>())?;add(owner.bytes().capacity())?;}}
        }
        if let Some(capture) = &self.full_ci_baselines {
            add(std::mem::size_of::<FullCiBaselines>())?;
            add(capture.rows.capacity().checked_mul(std::mem::size_of::<(&'static str, PathBuf, FixedLibraryBaseline)>())
                .ok_or(io::ErrorKind::OutOfMemory)?)?;
        }
        // Shared directory arrays are charged by actual retained ownership, with
        // PathBuf capacities and conservative map-node allowance exposed below.
        if self.shared_derived.is_none(){add(self.discovery.retained_charge_with(&mut seen)?)?;}
        add(self.facts.policy_closure_charge_with(&mut seen)?)?;
        Ok(count)
    }
}
pub(crate) fn capture<P: SnapshotProvider>(
    frontend: &ColdFrontend,
    inputs: &RecordingInputs<P>,
    discovery: Arc<DiscoveryReceipt>,
    configuration: &Path,
) -> io::Result<Arc<WorkspaceCapture>> {
    capture_with_auxiliary(frontend,inputs,discovery,configuration,&[])
}
struct OriginalWorkspaceSource<'a>{mapping:&'a Arc<SourceExportMapping>,plan:&'a dm_tree::frontend::FrontendDirectivePlan,revision:u128}
pub(crate) fn capture_analysis_with_auxiliary<P:SnapshotProvider>(frontend:&dm_tree::frontend::DiagnosticSourceView<'_>,inputs:&RecordingInputs<P>,discovery:Arc<DiscoveryReceipt>,configuration:&Path,questions:&[crate::policy_request::WorkspaceAuxiliaryQuestion])->io::Result<Arc<WorkspaceCapture>>{
    if frontend.original_analysis_completeness().is_none(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"workspace full source capture refuses partial diagnostic purpose"))}
    if frontend.mapping().initial_environment()!=dm_preprocess::InitialEnvironment::OriginalChecker0290 {return Err(io::Error::new(io::ErrorKind::InvalidInput,"analysis workspace requires its actual original context"))}
    capture_original(OriginalWorkspaceSource{mapping:frontend.mapping(),plan:frontend.original_plan(),revision:frontend.source_revision()},inputs,discovery,configuration,questions,None,None,None,None,None,EXTRA_BUDGET)
}
pub(crate) fn capture_with_auxiliary<P:SnapshotProvider>(frontend:&ColdFrontend,inputs:&RecordingInputs<P>,discovery:Arc<DiscoveryReceipt>,configuration:&Path,questions:&[crate::policy_request::WorkspaceAuxiliaryQuestion])->io::Result<Arc<WorkspaceCapture>>{
    let mapping=frontend.source_export_mapping().ok_or_else(||io::Error::other("workspace compiler mapping unproven"))?;
    capture_original(OriginalWorkspaceSource{mapping,plan:&frontend.plan,revision:frontend.source_export_revision()},inputs,discovery,configuration,questions,None,None,None,None,None,EXTRA_BUDGET)
}
/// Same Original workspace and same library semantic child. Only this private
/// selected attempt adds the fixed read-only baseline to the captured closure.
pub(crate) fn capture_analysis_with_library_baseline<P: SnapshotProvider>(
    frontend: &dm_tree::frontend::DiagnosticSourceView<'_>, inputs: &RecordingInputs<P>,
    discovery: Arc<DiscoveryReceipt>, configuration: &Path,
    questions: &[crate::policy_request::WorkspaceAuxiliaryQuestion],
    work: &dyn dm_preprocess::source_arena_credit::SourceArenaWork,
) -> io::Result<Arc<WorkspaceCapture>> {
    use crate::policy_request::WorkspaceAuxiliaryQuestion as Q;
    if frontend.original_analysis_completeness().is_none()
        || frontend.mapping().initial_environment() != dm_preprocess::InitialEnvironment::OriginalChecker0290
        || questions != [Q::LibraryLayeringFullAllow]
        || discovery.contract().recursive_roots.as_slice() !=
            [discovery.contract().root.join("code"), discovery.contract().root.join("maps")]
        || configuration != discovery.contract().root.join("tools/ci/lint_scopes.toml")
    {
        return Err(io::Error::new(io::ErrorKind::InvalidInput, "fixed library baseline requires its exact selected workspace"));
    }
    capture_original(OriginalWorkspaceSource {
        mapping: frontend.mapping(), plan: frontend.original_plan(),
        revision: frontend.source_revision(),
    }, inputs, discovery, configuration, questions, None, Some(work), None, None, None, EXTRA_BUDGET)
}
/// Exclusive authored MapEdits capture. Keep the existing workspace
/// capture allowance funded while the map provider owns its scratch and parsed
/// rows, then register the one immutable joined owner in the existing ledger.
pub(crate) fn capture_analysis_map_edits<P: SnapshotProvider>(
    frontend: &dm_tree::frontend::DiagnosticSourceView<'_>,
    inputs: &RecordingInputs<P>,
    discovery: Arc<DiscoveryReceipt>,
    configuration: &Path,
    questions: &[crate::policy_request::WorkspaceAuxiliaryQuestion],
    queries: &crate::query_db::QueryDb,
) -> io::Result<Arc<WorkspaceCapture>> {
    capture_analysis_map_edits_using(frontend, inputs, discovery, configuration, questions, queries, false, None, None)
}

pub(crate) fn capture_analysis_full_ci<P: SnapshotProvider>(
    frontend: &dm_tree::frontend::DiagnosticSourceView<'_>, inputs: &RecordingInputs<P>,
    discovery: Arc<DiscoveryReceipt>, configuration: &Path,
    questions: &[crate::policy_request::WorkspaceAuxiliaryQuestion], queries: &crate::query_db::QueryDb,
    paired_dmm: Option<Arc<crate::query_db::FundedPairedDmm>>,
    raw_spool_cache: Option<&Path>,
) -> io::Result<Arc<WorkspaceCapture>> {
    capture_analysis_map_edits_using(frontend, inputs, discovery, configuration, questions, queries, true, paired_dmm, raw_spool_cache)
}

fn capture_analysis_map_edits_using<P: SnapshotProvider>(
    frontend: &dm_tree::frontend::DiagnosticSourceView<'_>, inputs: &RecordingInputs<P>,
    discovery: Arc<DiscoveryReceipt>, configuration: &Path,
    questions: &[crate::policy_request::WorkspaceAuxiliaryQuestion], queries: &crate::query_db::QueryDb,
    full_ci: bool,
    paired_dmm: Option<Arc<crate::query_db::FundedPairedDmm>>,
    raw_spool_cache: Option<&Path>,
) -> io::Result<Arc<WorkspaceCapture>> {
    use crate::policy_request::WorkspaceAuxiliaryQuestion as Q;
    use dq_analyze::captured_generator_budget::Budget;
    use dm_tree::frontend::DiagnosticPreparationPurpose::OriginalSharedComplete;
    let subject = inputs.original_analysis_subject()
        .ok_or_else(|| io::Error::other("map_edits actual Original subject absent"))?;
    subject.require_bound_mapping(frontend.mapping())?;
    if (full_ci && (questions != Q::PRIVATE_FULL_REGISTRY
        || configuration != discovery.contract().root.join("tools/ci/lint_scopes.toml")))
        || !Q::admits_map_edits_capture(questions)
        || subject.synthetic() || !subject.same_discovery(&discovery)
        || frontend.preparation_purpose() != OriginalSharedComplete
        || frontend.original_analysis_completeness().is_none()
        || frontend.mapping().initial_environment() != dm_preprocess::InitialEnvironment::OriginalChecker0290
        || !((questions == [Q::MapEdits] && discovery.contract().recursive_roots.as_slice() == [discovery.contract().root.join("code")])
            || discovery.contract().recursive_roots.as_slice()
                == [discovery.contract().root.join("code"), discovery.contract().root.join("maps")]
            || Q::authored_doc_ui_roots(questions).is_some_and(|roots| discovery.matches_authored_doc_ui_profile(roots)))
    {
        return Err(io::Error::new(io::ErrorKind::InvalidInput, "map_edits requires its fixed authored model and CODE discovery"));
    }
    if raw_spool_cache.is_some() && (!full_ci || paired_dmm.is_none()) {
        return Err(io::Error::new(io::ErrorKind::InvalidInput, "raw workspace spool requires paired private Full CI"));
    }
    if let Some(owner) = &paired_dmm {
        if !full_ci || questions != Q::PRIVATE_FULL_REGISTRY {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "paired DMM requires exact private Full CI"));
        }
        owner.stage.lock().map_err(|_| io::Error::other("paired DMM stage poisoned"))?
            .require_recording(inputs, &discovery, queries)?;
    }
    queries.with_semantic_workspace_capture_inputs(|budget, credits| {
        let variable = raw_spool_cache.is_some();
        let recorder_before = if variable {
            Some((inputs.late_workspace_recorder_owner()?, inputs.late_workspace_recorder_charge()?))
        } else { None };
        let baseline_funding = if variable {
            Some(Budget::scoped_temporaries(budget).map_err(map_edits_quota)?)
        } else {
            None
        };
        // Keep the old fixed window and failure ordering on all other paths.
        // The staged path leaves real room for held baseline source work.
        let fixed_window = if variable {
            None
        } else {
            let ordinary = Budget::reserve_window(budget, EXTRA_BUDGET).map_err(map_edits_quota)?;
            if ordinary.capacity() != EXTRA_BUDGET {
                return Err(io::Error::new(io::ErrorKind::OutOfMemory, format!(
                    "workspace capture needs {EXTRA_BUDGET} bytes of source-family headroom; {} bytes are available",
                    ordinary.capacity(),
                )));
            }
            Some(ordinary)
        };
        let full_ci_baselines = if full_ci {
            Some(Box::new(credits.with_held_source_work(queries, |work| {
                FullCiBaselines::observe_using(
                    inputs, &discovery.contract().root, budget, work, baseline_funding.as_deref(),
                )
            })?))
        } else {
            None
        };
        let baseline_paid = if variable {
            full_ci_baselines.as_ref().expect("actual staged Full CI").preflight_charge
        } else { 0 };
        let ordinary = match fixed_window {
            Some(ordinary) => ordinary,
            None => Budget::reserve_window(budget, EXTRA_BUDGET - baseline_paid).map_err(map_edits_quota)?,
        };
        let capture_limit = ordinary.capacity() + baseline_paid;
        let pending = capture_original(
            OriginalWorkspaceSource { mapping: frontend.mapping(), plan: frontend.original_plan(),
                revision: frontend.source_revision() },
            inputs, discovery, configuration, questions, Some((budget, credits)), None, full_ci_baselines, paired_dmm, raw_spool_cache.map(|cache| (queries, cache)), capture_limit,
        );
        // Recorder facts can outlive either a successful capture or a failed
        // provider read. Publish their growth before releasing the window.
        let recorder_growth = if let Some((owner, before)) = recorder_before {
            match inputs.late_workspace_recorder_charge().and_then(|after| {
                let growth = after.saturating_sub(before);
                credits.retain_late_recorder_growth(&owner, growth)?;
                Ok(growth)
            }) {
                Ok(growth) => growth,
                Err(error) => {
                    ordinary.keep();
                    return match pending { Err(first) => Err(first), Ok(_) => Err(error) };
                }
            }
        } else { 0 };
        let capture = match pending {
            Ok(capture) => capture,
            Err(first) => {
                let _ = ordinary.settle_registered(budget, recorder_growth);
                return Err(first);
            }
        };
        let retained = capture.retained_charge()?.checked_add(2*std::mem::size_of::<usize>())
            .ok_or_else(|| io::Error::from(io::ErrorKind::OutOfMemory))?;
        if variable && std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some() {
            eprintln!("ORIGINAL_WORKSPACE_SETTLEMENT retained={retained} recorder_growth={recorder_growth} admitted={capture_limit}");
        }
        if let Some(baseline_funding) = baseline_funding {
            if retained > capture_limit {
                return Err(io::Error::new(io::ErrorKind::OutOfMemory,
                    "staged workspace retained storage exceeds its admitted grant"));
            }
            // The raw family gate stays held. Settle both already-funded
            // pieces without allocating or running an observer between them.
            let ordinary_retained = retained.saturating_sub(baseline_paid)
                .checked_add(recorder_growth).ok_or(io::ErrorKind::OutOfMemory)?;
            ordinary.settle(ordinary_retained).map_err(map_edits_quota)?;
            drop(baseline_funding);
            budget.charge(retained.min(baseline_paid)).map_err(map_edits_quota)?;
        } else {
            ordinary.settle(retained).map_err(map_edits_quota)?;
        }
        credits.retain_capture_metadata(&capture, retained)?;
        Ok(capture)
    })
}

fn map_edits_quota(message: String) -> io::Error {
    io::Error::new(io::ErrorKind::OutOfMemory, message)
}

fn map_edits_failure(failure: dq_analyze::captured_reactive_reads::Failure) -> io::Error {
    match failure {
        dq_analyze::captured_reactive_reads::Failure::Operational(error) => error,
        dq_analyze::captured_reactive_reads::Failure::Unsupported(message) =>
            io::Error::new(io::ErrorKind::Unsupported, message),
    }
}

pub(crate) fn paired_dmm_relative(relative: &str) -> bool {
    relative.starts_with("maps/") && relative.ends_with(".dmm")
}

/// One sorted borrowed path and the first actual authored occurrence.
struct KnownSources<'a>(Vec<(&'a Path, usize)>);

impl<'a> KnownSources<'a> {
    fn get(&self, path: &Path) -> Option<&usize> {
        let index = self.0.binary_search_by(|row| row.0.cmp(path)).ok()?;
        Some(&self.0[index].1)
    }

    fn contains_key(&self, path: &Path) -> bool {
        self.get(path).is_some()
    }

    fn keys(&self) -> impl ExactSizeIterator<Item = &'a Path> + '_ {
        self.0.iter().map(|row| row.0)
    }
}

fn capture_original<P:SnapshotProvider>(frontend:OriginalWorkspaceSource<'_>,inputs:&RecordingInputs<P>,discovery:Arc<DiscoveryReceipt>,configuration:&Path,questions:&[crate::policy_request::WorkspaceAuxiliaryQuestion],map_work:Option<(&Arc<dq_analyze::captured_generator_budget::Budget>,&mut dyn crate::input_snapshot::RecordedPolicySourceLender)>,library_sites:Option<&dyn dm_preprocess::source_arena_credit::SourceArenaWork>,full_ci_baselines:Option<Box<FullCiBaselines>>,paired_dmm:Option<Arc<crate::query_db::FundedPairedDmm>>,raw_spool_context:Option<(&crate::query_db::QueryDb,&Path)>,capture_limit:usize)->io::Result<Arc<WorkspaceCapture>>{
    if questions.contains(&crate::policy_request::WorkspaceAuxiliaryQuestion::MapEdits) != map_work.is_some() {
        return Err(io::Error::new(io::ErrorKind::InvalidInput, "map_edits requires its actual capture producer"));
    }
    use crate::policy_request::WorkspaceAuxiliaryQuestion as Q;
    // The larger private roster is closed. Keep the generic bound and require
    // the same strict ordering for every capture.
    if (questions.len() > 12 && !Q::is_extended_authored_doc_ui(questions))
        || questions.windows(2).any(|pair| pair[0] >= pair[1]) {
        return Err(io::Error::new(io::ErrorKind::InvalidInput, "actual canonical auxiliary questions required"));
    }
    if questions.contains(&crate::policy_request::WorkspaceAuxiliaryQuestion::CheckGrep)&&questions.contains(&crate::policy_request::WorkspaceAuxiliaryQuestion::CheckGrepBaseline){return Err(io::Error::new(io::ErrorKind::InvalidInput,"CheckGrep check and baseline purposes are mutually exclusive"))}
    discovery.validate_recording(inputs)?;
    if let Some(subject)=inputs.original_analysis_subject(){subject.validate_mapping(frontend.mapping)?;if !subject.same_discovery(&discovery){return Err(io::Error::other("Analyze subject and workspace discovery differ"))}}
    if !configuration.is_absolute() {
        return Err(io::Error::other(
            "workspace configuration must be caller absolute",
        ));
    }
    let mapping = frontend.mapping;
    let occurrences = frontend.plan.occurrences();
    let known_bytes = occurrences.len().checked_mul(std::mem::size_of::<(&Path, usize)>())
        .ok_or(io::ErrorKind::OutOfMemory)?;
    if known_bytes > capture_limit {
        return Err(io::Error::new(io::ErrorKind::OutOfMemory, "compiled occurrence index exceeds workspace admission"));
    }
    let mut rows = Vec::new();
    rows.try_reserve_exact(occurrences.len()).map_err(|actual| io::Error::new(io::ErrorKind::OutOfMemory, actual))?;
    if rows.capacity() != occurrences.len() {
        return Err(io::Error::new(io::ErrorKind::OutOfMemory, "compiled occurrence index capacity exceeds workspace admission"));
    }
    for (index, occurrence) in occurrences.iter().enumerate() {
        crate::daemon::control::checkpoint()?;
        rows.push((occurrence.path.as_path(), index));
    }
    rows.sort_unstable();
    rows.dedup_by(|left, right| left.0 == right.0);
    let known = KnownSources(rows);
    // Reserve the COMPLETE metadata cohort before any extra original payload
    // read. A late final census must not hide an unbounded capture high-water.
    // This is conservative admission (not claimed allocator/RSS measurement).
    let shared_derived = if questions == Q::PRIVATE_FULL_REGISTRY {
        let subject = inputs.original_analysis_subject().ok_or_else(|| io::Error::other("full registry Derived subject absent"))?;
        let owner = subject.derived_preflight_owner()?;
        if !owner.is_joined_registry() || !Arc::ptr_eq(owner.discovery(), &discovery) {
            return Err(io::Error::other("full registry Derived discovery differs from capture"));
        }
        owner.require_recording(inputs)?;
        Some(Arc::clone(owner))
    } else { None };
    let discovery_bytes = if shared_derived.is_some() { 0 } else { discovery.retained_charge()? };
    let mut used = known_bytes.checked_add(discovery_bytes)
        .and_then(|bytes| bytes.checked_add(
            std::mem::size_of::<WorkspaceCapture>() + 2048 + configuration.as_os_str().len() * 4,
        ))
        .ok_or_else(|| io::Error::other("workspace metadata overflow"))?;
    if let Some(capture) = &full_ci_baselines {
        used = used.checked_add(capture.preflight_charge).ok_or(io::ErrorKind::OutOfMemory)?;
        if capture.files().any(|(path, _)| known.contains_key(path.as_path())) {
            return Err(io::Error::new(io::ErrorKind::InvalidData, "registered baseline also participates in the authored source plan"));
        }
    }
    if let Some(subject)=inputs.original_analysis_subject(){used=used.checked_add(subject.charge()).ok_or_else(||io::Error::new(io::ErrorKind::OutOfMemory,"Analyze subject/capture charge overflow"))?;}
    let staged = raw_spool_context.is_some();
    // CheckGrep has at most six fixed paths, Keys and BaseVars one each.
    let staged_file_slots = discovery.files().len().checked_add(if staged { 8 } else { 0 })
        .ok_or(io::ErrorKind::OutOfMemory)?;
    if staged {
        // Discovered File paths borrow their existing discovery ordinal.
        // Their File vector is the only durable per-discovery-row allocation
        // here; fixed rows are separately admitted at their insertion sites.
        let bytes = staged_file_slots.checked_mul(std::mem::size_of::<File>())
            .ok_or(io::ErrorKind::OutOfMemory)?;
        used = used.checked_add(bytes).ok_or(io::ErrorKind::OutOfMemory)?;
    }
    // The alias index is discovery scratch, not source authority. Build it
    // under the same admission before classifying the per-file reserve.
    let alias_reserve = alias_index::AliasIndex::reserve_charge(known.keys())?;
    used = used.checked_add(alias_reserve).filter(|&bytes| bytes <= capture_limit)
        .ok_or_else(|| io::Error::new(io::ErrorKind::OutOfMemory, "workspace alias index exceeds capture allowance"))?;
    let joined_maps = map_work.is_some() && Q::is_private_grep_domain(questions);
    let is_joined_map = |path: &Path| joined_maps
        && path.extension().is_some_and(|ext| ext == "dmm")
        && path.strip_prefix(&discovery.contract().root)
            .is_ok_and(|relative| relative.starts_with("maps"));
    let mut mapped_scratch = 0;
    let mut donor_rows = 0usize;
    let mut spool_rows = 0usize;
    let mut fallback_rows = 0usize;
    let mut fallback_bytes = 0usize;
    for path in discovery.files() {
        crate::daemon::control::checkpoint()?;
        let width = path.capacity().checked_mul(8).and_then(|n| n.checked_add(2048))
            .ok_or(io::ErrorKind::OutOfMemory)?;
        let exact = known.get(path.as_path());
        let donor_row = staged
            && shared_derived.as_ref().is_some_and(|owner| owner.workspace_file(path).is_some())
            && inputs.has_policy_file_and_parent(path)?;
        donor_rows += usize::from(donor_row);
        if staged && (exact.is_some_and(|&index| mapping.source_acquisition(index).is_some())
            || donor_row || paired_dmm.is_some() && is_joined_map(path))
        {
            // The donor's requested file and ordinary parent already exist.
            // Capture still authenticates the alias or reread, if needed.
            // Any local closure clone is admitted separately below.
            mapped_scratch = mapped_scratch.max(width);
        } else if staged && exact.is_none() && spools_private_full_page_source(path, &discovery.contract().root)
        {
            // Typed discovery already owns the parent listing. A spooled
            // payload can add one ordinary fact (key and fact path buffers).
            // Its durable spool entry is funded by the builder below.
            spool_rows += 1;
            let fact = path.capacity().checked_mul(8)
                .and_then(|n| n.checked_add(128 + std::mem::size_of::<FileInput>()))
                .ok_or(io::ErrorKind::OutOfMemory)?;
            used = used.checked_add(fact).ok_or(io::ErrorKind::OutOfMemory)?;
            mapped_scratch = mapped_scratch.max(width);
        } else {
            // Uncompiled/fallback reads may still add ordinary recorder
            // metadata. Retain their prior allowance before the provider.
            fallback_rows += 1;
            fallback_bytes = fallback_bytes.checked_add(width).ok_or(io::ErrorKind::OutOfMemory)?;
            used = used.checked_add(width).ok_or(io::ErrorKind::OutOfMemory)?;
        }
    }
    let mut primary_scratch = 0usize;
    for path in known.keys() {
        let spelling = path.as_os_str().len().checked_mul(2).ok_or(io::ErrorKind::OutOfMemory)?;
        if staged {
            // The primary spelling is borrowed by the index and selection.
            // Only one authenticated challenge owns a temporary copy.
            primary_scratch = primary_scratch.max(spelling);
        } else {
            used = used.checked_add(spelling).ok_or(io::ErrorKind::OutOfMemory)?;
        }
    }
    used = used.checked_add(mapped_scratch).and_then(|n| n.checked_add(primary_scratch))
        .ok_or(io::ErrorKind::OutOfMemory)?;
    if staged && std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some() {
            let baseline_bytes = full_ci_baselines.as_ref().map_or(0, |rows| rows.preflight_charge);
            let subject_bytes = inputs.original_analysis_subject().map_or(0, |subject| subject.charge());
            eprintln!("ORIGINAL_WORKSPACE_METADATA bytes={used} admitted={capture_limit} known_bytes={known_bytes} alias_bytes={alias_reserve} file_slots={staged_file_slots} donor_rows={donor_rows} spool_rows={spool_rows} fallback_rows={fallback_rows} fallback_bytes={fallback_bytes} baseline_bytes={baseline_bytes} subject_bytes={subject_bytes}");
    }
    if used > capture_limit {
        return Err(io::Error::new(io::ErrorKind::OutOfMemory,
            format!("workspace metadata needs {used} bytes before payload read, with {capture_limit} admitted"),
        ));
    }
    let aliases = alias_index::AliasIndex::new(known.keys(), alias_reserve)?;
    let mut ui = if questions.contains(&Q::DocUiFullAllow) {
        // The funded MapEdits caller holds an ordinary capture window covering
        // all capture_limit bytes. The dispatcher uses only the remainder of that
        // window, and its surviving owner is settled once with the capture.
        if map_work.is_none() || !Q::authored_doc_ui_roots(questions).is_some_and(|roots| discovery.matches_authored_doc_ui_profile(roots)) {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "authored UI requires its actual joined discovery and capture funding"));
        }
        let root = &discovery.contract().root;
        let mut admit = |bytes: usize| -> io::Result<()> {
            used = used.checked_add(bytes).filter(|&used| used <= capture_limit).ok_or(io::ErrorKind::OutOfMemory)?;
            Ok(())
        };
        if !discovery.covers_doc_snippets(&mut admit)?
            || !discovery.covers_ui_actions(&mut admit)?
            || !discovery.covers_dm_roots(dq_analyze::tree::CODE_MAPS_DM.roots, false, &mut admit)?
            || Q::is_extended_authored_doc_ui(questions)
                && !discovery.covers_dm_roots(&[("interface", "dm"), ("modular_chomp", "dm")], true, &mut admit)?
        {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "authored UI joined domains were not completely observed"));
        }
        discovery.productive_ui_configuration(configuration)?
            .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "authored UI lacks its actual discovery configuration"))?;
        const DISPATCHER: &str = dq_analyze::ui_actions_policy::DISPATCHER;
        let width = root.as_os_str().len().checked_add(DISPATCHER.len())
            .and_then(|n| n.checked_mul(8)).and_then(|n| n.checked_add(1024))
            .ok_or(io::ErrorKind::OutOfMemory)?;
        admit(width)?;
        let path = root.join(DISPATCHER);
        let mut captured = None;
        if discovery.files().contains(&path) {
            crate::daemon::control::checkpoint()?;
            captured = Some(capture_optional_original(
                inputs, mapping, frontend.plan, &discovery, &known, &aliases, &path, &mut used, capture_limit, 0,
            )?.ok_or_else(|| io::Error::other("discovered UI dispatcher disappeared before capture"))?);
        }
        let original = captured.as_ref().map(|file| file.borrow_original(mapping)).transpose()?;
        let room = capture_limit.checked_sub(used).ok_or(io::ErrorKind::OutOfMemory)?;
        let budget = dq_analyze::captured_generator_budget::Budget::new(room).map_err(map_edits_quota)?;
        let prepared = prepare_captured_ui_dispatcher(original.as_ref(), &budget)?;
        used = used.checked_add(prepared.budget_charge()).filter(|&used| used <= capture_limit).ok_or(io::ErrorKind::OutOfMemory)?;
        Some((path, captured, UiDispatcherCapture { index: None, prepared }))
    } else {
        None
    };
    let map_fact_count = if paired_dmm.is_some() { 0 } else { discovery.files().iter().filter(|path| is_joined_map(path)).count() };
    let map_fact_storage = map_fact_count.checked_mul(std::mem::size_of::<(usize, FileInput)>())
        .ok_or(io::ErrorKind::OutOfMemory)?;
    used = used.checked_add(map_fact_storage).filter(|&n| n <= capture_limit)
        .ok_or_else(|| io::Error::new(io::ErrorKind::OutOfMemory, "joined MapEdits fact index exceeds capture allowance"))?;
    let mut map_facts = Vec::new();
    map_facts.try_reserve_exact(map_fact_count)
        .map_err(|error| io::Error::new(io::ErrorKind::OutOfMemory, error))?;
    if map_facts.capacity() > map_fact_count {
        return Err(io::Error::new(io::ErrorKind::OutOfMemory, "joined MapEdits fact index capacity exceeds admission"));
    }
    let mut raw_builder = if let Some((queries, cache)) = raw_spool_context {
        let mut rows = 0usize;
        for path in discovery.files() {
            crate::daemon::control::checkpoint()?;
            if spools_private_full_page_source(path, discovery.contract().root.as_path()) {
                rows = rows.checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?;
            }
        }
        if rows == 0 {
            None
        } else {
            // The admitted ordinary window is already held by the caller. This
            // bounded subledger never obtains another daemon grant.
            let admission = dq_analyze::captured_generator_budget::Budget::new(capture_limit - used)
                .map_err(map_edits_quota)?;
            let builder = WorkspaceRawSpoolBuilder::new(inputs, Arc::clone(&discovery), queries,
                rows, &admission, cache)?;
            used = used.checked_add(builder.live_capture_bytes()).ok_or(io::ErrorKind::OutOfMemory)?;
            Some(builder)
        }
    } else { None };
    let mut files = if staged {
        let count = staged_file_slots;
        let mut files = Vec::new();
        files.try_reserve_exact(count).map_err(|actual| io::Error::new(io::ErrorKind::OutOfMemory, actual))?;
        if files.capacity() != count { return Err(io::ErrorKind::OutOfMemory.into()); }
        files
    } else {
        Vec::with_capacity(discovery.files().len())
    };
    for (source_index, path) in discovery.files().iter().enumerate() {
        crate::daemon::control::checkpoint()?;
        if let Some(owner) = &paired_dmm {
            if is_joined_map(path) {
                if let Some(&index) = known.get(path.as_path()) {
                    let actual = frontend.plan.occurrences().get(index)
                        .filter(|row| row.path.as_path() == path.as_path())
                        .ok_or_else(|| io::Error::other("paired DMM occurrence differs"))?;
                    if actual.non_text_kind() != Some(dm_preprocess::regions::NonTextKind::Map) {
                        return Err(io::Error::new(io::ErrorKind::Unsupported, "paired DMM cannot replace a compiled acquisition"));
                    }
                } else if aliases.candidate(path)?.is_some() {
                    return Err(io::Error::new(io::ErrorKind::Unsupported, "paired DMM cannot replace a compiled alias"));
                }
                let mut stage = owner.stage.lock().map_err(|_| io::Error::other("paired DMM stage poisoned"))?;
                stage.replay_capture_error(source_index)?;
                stage.require_capture_slot(source_index, Some(&inputs.recorded_file_fact(path)?))?;
                files.push(File { path: FilePath::Discovered(source_index), original: Original::PairedDmm(source_index) });
                continue;
            }
        }
        let mut capture_discovered = || {
            let spool = raw_builder.as_mut()
                .filter(|_| spools_private_full_page_source(path, discovery.contract().root.as_path()))
                .map(|builder| (builder, source_index));
            capture_optional_original_using(inputs,mapping,frontend.plan,&discovery,&known,&aliases,
                path,&mut used,capture_limit,0,spool).inspect_err(|error| {
                    if staged && std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some() {
                        eprintln!("ORIGINAL_WORKSPACE_SOURCE {}: {error}", path.display());
                    }
                })?
                .ok_or_else(||io::Error::other("discovered source disappeared before capture"))
        };
        let captured = if let Some((dispatcher, acquired, status)) = &mut ui {
            if dispatcher.as_path() == path.as_path() {
                status.index = Some(files.len());
                acquired.take().ok_or_else(|| io::Error::other("actual authored dispatcher acquisition missing"))?
            } else {
                let relative = path.strip_prefix(&discovery.contract().root)
                    .map_err(|_| io::Error::new(io::ErrorKind::InvalidInput, "authored UI source escapes actual root"))?;
                let grep_payload = questions.contains(&Q::CheckGrep)
                    && dq_analyze::lints::check_grep::native::selects_filesystem_source(relative);
                if !grep_payload && relative.starts_with("tgui/packages/tgui/interfaces") &&
                    !keeps_discovered_ui_path(relative, true, true, status.prepared.needs_sources(), |relative| {
                        Ok(discovery.productive_ui_configuration(configuration)?
                            .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "authored UI lacks its actual discovery configuration"))?
                            .policy_path_exempt("ui_actions", dq_analyze::ui_actions_policy::metadata().group, relative))
                    })?
                {
                    continue;
                }
                capture_discovered()?
            }
        } else {
            capture_discovered()?
        };
        if is_joined_map(path) && matches!(&captured.original, Original::Owned(_)) {
            map_facts.push((files.len(), captured.fact));
        }
        files.push(File { path: FilePath::Discovered(source_index), original: captured.original });
    }
    let remaining = capture_limit
        .checked_sub(used)
        .ok_or_else(|| io::Error::other("workspace metadata leaves no config budget"))?;
    if discovery.files().iter().any(|path| path == configuration) {
        return Err(io::Error::other(
            "workspace configuration cannot also be a DM source",
        ));
    }
    let config = if let Some(owner)=&shared_derived{owner.configuration_bytes().cloned()}
        else{inputs.read_policy_candidate(configuration, remaining)?};
    let mut auxiliary=Vec::new();let mut deadline=None;let mut check_grep=None;let mut check_grep_paths:Option<[Option<PathBuf>;6]>=None;let mut keys_manifest=None;let mut keys_manifest_path=None;let mut base_vars_configuration=None;let mut base_vars_configuration_path=None;
    if !questions.is_empty(){
     used=used.checked_add(config.as_ref().map_or(0,SharedBytes::capacity)).and_then(|n|n.checked_add(4*questions.len()*std::mem::size_of::<crate::policy_request::WorkspaceAuxiliaryQuestion>())).and_then(|n|n.checked_add(128)).filter(|n|*n<=capture_limit).ok_or_else(||io::Error::new(io::ErrorKind::OutOfMemory,"auxiliary metadata overflow"))?;
     auxiliary.try_reserve_exact(questions.len()).map_err(|actual|io::Error::new(io::ErrorKind::OutOfMemory,actual))?;if auxiliary.capacity()>4*questions.len(){return Err(io::ErrorKind::OutOfMemory.into())}auxiliary.extend_from_slice(questions);
     if questions.contains(&crate::policy_request::WorkspaceAuxiliaryQuestion::DeadlinePollingAllowlist){
      let width=discovery.contract().root.as_os_str().len().checked_add("/tools/ci/deadline_polling_allowlist.txt".len()).and_then(|n|n.checked_mul(8)).and_then(|n|n.checked_add(2048)).ok_or(io::ErrorKind::OutOfMemory)?;
      used=used.checked_add(width).filter(|n|*n<=capture_limit).ok_or(io::ErrorKind::OutOfMemory)?;
      let path=discovery.contract().root.join("tools/ci/deadline_polling_allowlist.txt");
      let bytes=inputs.read_policy_candidate(&path,capture_limit-used)?;used=used.checked_add(bytes.as_ref().map_or(0,SharedBytes::capacity)).and_then(|n|n.checked_add(128)).filter(|n|*n<=capture_limit).ok_or(io::ErrorKind::OutOfMemory)?;deadline=Some((path,bytes));
     }
    }
    if questions.contains(&crate::policy_request::WorkspaceAuxiliaryQuestion::CheckGrep)||questions.contains(&crate::policy_request::WorkspaceAuxiliaryQuestion::CheckGrepBaseline){
     use dq_analyze::lints::check_grep::native::{Fixed,Purpose};discovery.check_grep_names()?;
     let purpose=if questions.contains(&crate::policy_request::WorkspaceAuxiliaryQuestion::CheckGrep){Purpose::Check}else{Purpose::Baseline};let requested=Fixed::for_purpose(purpose);
     let path_width=discovery.contract().root.as_os_str().len().checked_add(128).and_then(|n|n.checked_mul(8)).and_then(|n|n.checked_add(2048)).and_then(|n|n.checked_mul(requested.len())).ok_or(io::ErrorKind::OutOfMemory)?;
     let wanted=files.len().checked_add(requested.len()).ok_or(io::ErrorKind::OutOfMemory)?;let capacity=wanted.checked_mul(4).ok_or(io::ErrorKind::OutOfMemory)?;
     used=used.checked_add(path_width).and_then(|n|if files.capacity()<wanted{n.checked_add(capacity.checked_mul(std::mem::size_of::<File>())?)}else{Some(n)}).filter(|n|*n<=capture_limit).ok_or(io::ErrorKind::OutOfMemory)?;
     let paths=std::array::from_fn(|index|{let fixed=Fixed::all()[index];requested.contains(&fixed).then(||discovery.contract().root.join(fixed.relative()))});
     if files.capacity()<wanted{files.try_reserve_exact(requested.len()).map_err(|error|io::Error::new(io::ErrorKind::OutOfMemory,error))?;if files.capacity()>capacity{return Err(io::Error::new(io::ErrorKind::OutOfMemory,"check_grep actual fixed-file capacity exceeds admission"))}}
     let mut indices=[None;6];for(index,path)in paths.iter().enumerate(){let Some(path)=path else{continue};crate::daemon::control::checkpoint()?;
      if let Some(existing)=files.iter().position(|file|file.path(&discovery)==path){indices[index]=Some(existing);continue}
      if path==configuration{if let Some(bytes)=&config{indices[index]=Some(files.len());inputs.recorded_file_fact(path)?;files.push(File{path:FilePath::Fixed(Box::new(path.clone())),original:Original::Owned(bytes.clone())});}continue}
      if let Some(CapturedOriginal{original,..})=capture_optional_original(inputs,mapping,frontend.plan,&discovery,&known,&aliases,path,&mut used,capture_limit,128)?{indices[index]=Some(files.len());files.push(File{path:FilePath::Fixed(Box::new(path.clone())),original});}
     }
     check_grep=Some(indices);check_grep_paths=Some(paths);
    }
    if questions == crate::policy_request::WorkspaceAuxiliaryQuestion::SELECTED_ORDER_AND_OWNERSHIP
        || questions.iter().any(|question|matches!(question,crate::policy_request::WorkspaceAuxiliaryQuestion::Keys|crate::policy_request::WorkspaceAuxiliaryQuestion::SemReads|crate::policy_request::WorkspaceAuxiliaryQuestion::UntrackedInputs|crate::policy_request::WorkspaceAuxiliaryQuestion::SetterPublishes|crate::policy_request::WorkspaceAuxiliaryQuestion::SysReactive|crate::policy_request::WorkspaceAuxiliaryQuestion::Lifeforms)){
     let width=discovery.contract().root.as_os_str().len().checked_add("/deepquarry.dme".len()).and_then(|n|n.checked_mul(8)).and_then(|n|n.checked_add(2048)).ok_or(io::ErrorKind::OutOfMemory)?;
     let wanted=files.len().checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?;let capacity=wanted.checked_mul(4).ok_or(io::ErrorKind::OutOfMemory)?;
     used=used.checked_add(width).and_then(|n|if files.capacity()<wanted{n.checked_add(capacity.checked_mul(std::mem::size_of::<File>())?)}else{Some(n)}).filter(|n|*n<=capture_limit).ok_or(io::ErrorKind::OutOfMemory)?;
     let path=discovery.contract().root.join("deepquarry.dme");
     if files.capacity()<wanted{files.try_reserve_exact(1).map_err(|error|io::Error::new(io::ErrorKind::OutOfMemory,error))?;if files.capacity()>capacity{return Err(io::Error::new(io::ErrorKind::OutOfMemory,"keys manifest actual capacity exceeds admission"))}}
     let index=if let Some(existing)=files.iter().position(|file|file.path(&discovery)==&path){Some(existing)}else{
      let original=if path==configuration{config.as_ref().map(|bytes|inputs.recorded_file_fact(&path).map(|fact|CapturedOriginal{original:Original::Owned(bytes.clone()),fact})).transpose()?}else{capture_optional_original(inputs,mapping,frontend.plan,&discovery,&known,&aliases,&path,&mut used,capture_limit,128)?};
      if let Some(CapturedOriginal{original,..})=original{let index=files.len();files.push(File{path:FilePath::Fixed(Box::new(path.clone())),original});Some(index)}else{None}
     };keys_manifest=Some(index);keys_manifest_path=Some(path);
    }

    if questions.contains(&crate::policy_request::WorkspaceAuxiliaryQuestion::BaseVars){
     let width=discovery.contract().root.as_os_str().len().checked_add("/tools/ci/lint_scopes.toml".len()).and_then(|n|n.checked_mul(8)).and_then(|n|n.checked_add(2048)).ok_or(io::ErrorKind::OutOfMemory)?;let wanted=files.len().checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?;let capacity=wanted.checked_mul(4).ok_or(io::ErrorKind::OutOfMemory)?;
     used=used.checked_add(width).and_then(|n|if files.capacity()<wanted{n.checked_add(capacity.checked_mul(std::mem::size_of::<File>())?)}else{Some(n)}).filter(|n|*n<=capture_limit).ok_or(io::ErrorKind::OutOfMemory)?;let path=discovery.contract().root.join("tools/ci/lint_scopes.toml");if files.capacity()<wanted{files.try_reserve_exact(1).map_err(|error|io::Error::new(io::ErrorKind::OutOfMemory,error))?;if files.capacity()>capacity{return Err(io::Error::new(io::ErrorKind::OutOfMemory,"base-vars fixed configuration capacity exceeds admission"))}}
     let mut existing=None;for(index,file)in files.iter().enumerate(){crate::daemon::control::checkpoint()?;if file.path(&discovery)==&path{existing=Some(index);break}}let index=if let Some(existing)=existing{Some(existing)}else{let original=if path==configuration{config.as_ref().map(|bytes|inputs.recorded_file_fact(&path).map(|fact|CapturedOriginal{original:Original::Owned(bytes.clone()),fact})).transpose()?}else{capture_optional_original(inputs,mapping,frontend.plan,&discovery,&known,&aliases,&path,&mut used,capture_limit,128)?};if let Some(CapturedOriginal{original,..})=original{let index=files.len();files.push(File{path:FilePath::Fixed(Box::new(path.clone())),original});Some(index)}else{None}};base_vars_configuration=Some(index);base_vars_configuration_path=Some(path);
    }

    let library_baseline = if let Some(work) = library_sites {
        let width=discovery.contract().root.as_os_str().len().checked_add(LIBRARY_SITES_BASELINE.len())
            .and_then(|n|n.checked_mul(8)).and_then(|n|n.checked_add(2176)).ok_or(io::ErrorKind::OutOfMemory)?;
        used=used.checked_add(width).filter(|n|*n<=capture_limit).ok_or(io::ErrorKind::OutOfMemory)?;
        let path=discovery.contract().root.join(LIBRARY_SITES_BASELINE);
        if known.contains_key(path.as_path()) {
            return Err(io::Error::new(io::ErrorKind::InvalidData, "fixed library baseline also participates in the authored source plan"));
        }
        let bytes=inputs.read_fixed_library_baseline(discovery.contract().root.as_path(), &path, capture_limit-used, work)?;
        Some((path,bytes))
    } else { None };

    let fixed_path_inputs = || std::iter::once(configuration)
        .chain(deadline.iter().map(|(path, _)| path.as_path()))
        .chain(library_baseline.iter().filter(|(_, fact)| fact.selects_file_fact()).map(|(path, _)| path.as_path()))
        .chain(full_ci_baselines.iter().flat_map(|capture| capture.files())
            .filter(|(_, fact)| fact.selects_file_fact()).map(|(path, _)| path.as_path()))
        .chain(keys_manifest_path.iter().map(PathBuf::as_path))
        .chain(base_vars_configuration_path.iter().map(PathBuf::as_path))
        .chain(check_grep_paths.iter().flat_map(|paths| paths.iter().flatten().map(PathBuf::as_path)));
    // The emitted rows carry occurrence indices or sealed frame slots.
    // Neither temporary lookup table is needed by the fact closure.
    drop(aliases);
    drop(known);
    if staged {
        used = used.checked_sub(known_bytes).and_then(|bytes| bytes.checked_sub(alias_reserve))
            .ok_or_else(|| io::Error::other("workspace lookup scratch was not admitted"))?;
    }
    let fixed_paths: Vec<_> = if staged {
        let mut count = 0usize;
        for path in fixed_path_inputs() {
            count = count.checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?;
            // Preserve a conservative allowance for canonical path ownership.
            let width = path.as_os_str().len().checked_mul(8)
                .and_then(|n| n.checked_add(2048 + std::mem::size_of::<PathBuf>()))
                .ok_or(io::ErrorKind::OutOfMemory)?;
            used = used.checked_add(width).filter(|n| *n <= capture_limit)
                .ok_or(io::ErrorKind::OutOfMemory)?;
        }
        let mut paths = Vec::new();
        paths.try_reserve_exact(count).map_err(|actual| io::Error::new(io::ErrorKind::OutOfMemory, actual))?;
        if paths.capacity() != count { return Err(io::ErrorKind::OutOfMemory.into()); }
        paths.extend(fixed_path_inputs().map(canonical_path));
        paths
    } else {
        fixed_path_inputs().map(canonical_path).collect()
    };
    let mut standalone_map_paths = std::collections::BTreeSet::new();
    let mut selected = std::collections::BTreeSet::new();
    let mut compact_selected = Vec::<(&Path, usize)>::new();
    if staged {
        // Each capture row can select its own path and at most one primary.
        let rows = files.len().checked_mul(2).and_then(|n| n.checked_add(fixed_paths.len()))
            .ok_or(io::ErrorKind::OutOfMemory)?;
        let bytes = rows.checked_mul(std::mem::size_of::<(&Path, usize)>()).ok_or(io::ErrorKind::OutOfMemory)?;
        used = used.checked_add(bytes).filter(|n| *n <= capture_limit).ok_or(io::ErrorKind::OutOfMemory)?;
        compact_selected.try_reserve_exact(rows).map_err(|actual| io::Error::new(io::ErrorKind::OutOfMemory, actual))?;
        if compact_selected.capacity() != rows { return Err(io::ErrorKind::OutOfMemory.into()); }
    }
    let mut select = |path, ordinal| {
        if staged { compact_selected.push((path, ordinal)); }
        else { selected.insert(path); }
    };
    for (index, file) in files.iter().enumerate() {
        select(file.path(&discovery).as_path(), index * 2);
        if let Original::Native(native) = &file.original {
            // The recorded capture above already checked this immutable
            // occurrence against its exact primary receipt and binding. Only
            // the selected closure needs a copy of its physical path.
            let primary = frontend.plan.occurrences().get(native.occurrence)
                .ok_or_else(|| io::Error::other("workspace native primary occurrence absent"))?;
            select(primary.path.as_path(), index * 2 + 1);
        }
    }
    for (index, path) in fixed_paths.iter().enumerate() {
        select(path.as_path(), files.len() * 2 + index);
    }
    if staged {
        // Match BTreeSet::insert: equivalent paths keep the first raw
        // spelling encountered in the existing capture traversal.
        compact_selected.sort_unstable();
        compact_selected.dedup_by(|left, right| left.0 == right.0);
    }
    if staged && files.capacity() != files.len() {
        let overlap = files.len().checked_mul(std::mem::size_of::<File>())
            .ok_or(io::ErrorKind::OutOfMemory)?;
        used = used.checked_add(overlap).filter(|n| *n <= capture_limit)
            .ok_or(io::ErrorKind::OutOfMemory)?;
    }
    let mut map_edits = None;
    let map_directories = if let Some(owner) = &paired_dmm {
        let mut stage = owner.stage.lock().map_err(|_| io::Error::other("paired MapEdits stage poisoned"))?;
        for index in 0..stage.map_order().len() {
            crate::daemon::control::checkpoint()?;
            let ordinal = stage.map_order()[index];
            let path = discovery.files().get(ordinal).ok_or_else(|| io::Error::other("paired MapEdits ordinal absent"))?;
            stage.require_map_outcome(ordinal, &inputs.recorded_file_fact(path)?)?;
        }
        Vec::new()
    } else if let Some((budget, lender)) = map_work {
        use dq_analyze::{captured_allow_annotations::Operation, key_policy_control as kc, map_edits_policy::ParsedMap};
        let poll = &crate::daemon::control::checkpoint;
        let mut control = Operation { budget, poll };
        let mut maps = Vec::new();
        let joined = Q::is_private_grep_domain(questions);
        let mut parse = |path: &Path, relative: &str, bytes: &[u8]| {
            let rows = ParsedMap::parse(bytes, budget, poll).map_err(map_edits_failure)?;
            kc::row(&mut control, &mut maps).map_err(map_edits_failure)?;
            let relative = kc::own(&mut control, relative).map_err(map_edits_failure)?;
            // Both the selected path index and the copied InputSnapshot file
            // fact are part of the map phase's funding before insertion.
            let width = path.as_os_str().len().checked_mul(32).and_then(|n| n.checked_add(8192))
                .ok_or_else(|| io::Error::from(io::ErrorKind::OutOfMemory))?;
            budget.charge(width).map_err(map_edits_quota)?;
            if !joined && (selected.contains(path) || !standalone_map_paths.insert(path.to_owned())) {
                return Err(io::Error::new(io::ErrorKind::InvalidInput, "map_edits source path has a second selected role"));
            }
            maps.push(MapEditsFile { relative, rows });
            Ok(())
        };
        let directories = if joined {
            inputs.fold_observed_map_edits_inputs(&discovery, budget, lender, |path, relative| {
                let (index, file) = files.iter().enumerate().find(|(_, file)| file.path(&discovery) == path)
                    .ok_or_else(|| io::Error::other("joined MapEdits has no exact captured CheckGrep payload"))?;
                let Original::Owned(bytes) = &file.original else {
                    return Err(io::Error::other("joined MapEdits requires the actual raw DMM payload owner"));
                };
                let fact = map_facts.binary_search_by_key(&index, |row| row.0)
                    .ok().map(|at| &map_facts[at].1)
                    .ok_or_else(|| io::Error::other("joined MapEdits has no actual captured file fact"))?;
                if *fact != inputs.recorded_file_fact(path)? {
                    return Err(io::Error::other("joined MapEdits original DMM observation changed"));
                }
                parse(path, relative, bytes.as_slice())
            })?;
            Vec::new()
        } else {
            inputs.fold_regular_map_edits_inputs(&discovery.contract().root, budget, lender, parse)?
        };
        // The original directory backing is shared with the recorded facts.
        // Budget the closure's second key/index allocation before it is made.
        for directory in &directories {
            let width = directory.capacity().checked_mul(8).and_then(|n| n.checked_add(4096))
                .ok_or_else(|| io::Error::from(io::ErrorKind::OutOfMemory))?;
            budget.charge(width).map_err(map_edits_quota)?;
        }
        map_edits = Some(maps);
        directories
    } else {
        Vec::new()
    };
    drop(map_facts);
    selected.extend(standalone_map_paths.iter().map(PathBuf::as_path));
    let canonical_configuration = canonical_path(configuration);
    let (facts, policy_revision) = if staged {
        if !map_directories.is_empty() {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "joined workspace has directories outside actual discovery"));
        }
        inputs.policy_workspace_joined_files_hashed(
            &compact_selected, &discovery, shared_derived.as_deref()
                .ok_or_else(|| io::Error::other("staged workspace has no actual Derived donor"))?,
            capture_limit.checked_sub(used).ok_or(io::ErrorKind::OutOfMemory)?,
            frontend.revision, &canonical_configuration,
            |path, fact| {
                let index = compact_selected.binary_search_by(|(selected, _)| selected.cmp(&path))
                    .map_err(|_| io::Error::other("raw workspace selected key disappeared"))?;
                let insertion = compact_selected[index].1;
                let Some(file) = files.get(insertion / 2).filter(|_| insertion % 2 == 0) else { return Ok(false); };
                match (&file.path, &file.original) {
                    (FilePath::Discovered(discovered), Original::Spool(ordinal))
                        if discovered == ordinal && file.path(&discovery).as_path() == path
                            && spools_private_full_page_source(path, &discovery.contract().root) =>
                    {
                        raw_builder.as_ref().ok_or_else(|| io::Error::other("raw spool builder absent"))?
                            .require_fact(*ordinal, fact)?;
                        Ok(true)
                    }
                    (FilePath::Discovered(discovered), Original::PairedDmm(ordinal))
                        if discovered == ordinal && file.path(&discovery).as_path() == path =>
                    {
                        paired_dmm.as_ref().ok_or_else(|| io::Error::other("paired DMM owner absent"))?
                            .facts().require(*ordinal, fact)?;
                        Ok(true)
                    }
                    _ => Ok(false),
                }
            },
        )?
    } else {
        let (facts, borrowed_directories) = if shared_derived.is_some() {
            if !map_directories.is_empty() {
                return Err(io::Error::new(io::ErrorKind::InvalidInput, "joined workspace has directories outside actual discovery"));
            }
            (inputs.policy_workspace_joined_files_using(selected.into_iter(), &discovery, shared_derived.as_deref())?,
                Some(discovery.policy_directories()))
        } else {
            (inputs.policy_workspace_closure_paths(
                selected.into_iter(), discovery.directory_paths().chain(&map_directories),
            )?, None)
        };
        let revision = crate::policy_request::workspace_revision_with_file_donor(
            frontend.revision, &facts,
            borrowed_directories.unwrap_or_else(|| facts.policy_directories()),
            shared_derived.as_deref(), &discovery.contract().root,
            &discovery.contract().recursive_roots, &canonical_configuration,
        )?;
        (facts, revision)
    };
    let policy_revision=if auxiliary.is_empty(){policy_revision}else{let flags=[auxiliary.contains(&crate::policy_request::WorkspaceAuxiliaryQuestion::DeadlinePollingAllowlist),auxiliary.contains(&crate::policy_request::WorkspaceAuxiliaryQuestion::CheckGrep)];let mut hash=xxhash_rust::xxh3::Xxh3::new();hash.update(b"native-workspace-auxiliary-v1");hash.update(&policy_revision.to_le_bytes());hash.update(&[u8::from(flags[0]),u8::from(flags[1])]);hash.digest128()};
    let policy_revision=if auxiliary.contains(&crate::policy_request::WorkspaceAuxiliaryQuestion::DocSnippets){let mut hash=xxhash_rust::xxh3::Xxh3::new();hash.update(b"native-workspace-doc-snippets-source-purpose-v1");hash.update(&policy_revision.to_le_bytes());hash.digest128()}else{policy_revision};
    let policy_revision=if auxiliary.contains(&crate::policy_request::WorkspaceAuxiliaryQuestion::CheckGrepBaseline){let mut hash=xxhash_rust::xxh3::Xxh3::new();hash.update(b"native-workspace-check-grep-baseline-intent-v1");hash.update(&policy_revision.to_le_bytes());hash.digest128()}else{policy_revision};
    let policy_revision=if auxiliary.contains(&crate::policy_request::WorkspaceAuxiliaryQuestion::Keys){let mut hash=xxhash_rust::xxh3::Xxh3::new();hash.update(b"native-workspace-keys-intent-v1");hash.update(&policy_revision.to_le_bytes());hash.digest128()}else{policy_revision};
    let policy_revision=if auxiliary.iter().any(|question|question.is_semantic()){use crate::policy_request::WorkspaceAuxiliaryQuestion as Q;let mut hash=xxhash_rust::xxh3::Xxh3::new();hash.update(b"native-workspace-semantic-intent-v1");hash.update(&policy_revision.to_le_bytes());for question in[Q::SemReads,Q::UntrackedInputs,Q::SetterPublishes,Q::Tracked,Q::TrackedTests,Q::SysReactive,Q::Lifeforms,Q::DerivedReads]{hash.update(&[u8::from(auxiliary.contains(&question))]);}hash.digest128()}else{policy_revision};
    let policy_revision=if auxiliary.contains(&crate::policy_request::WorkspaceAuxiliaryQuestion::Decl){let mut hash=xxhash_rust::xxh3::Xxh3::new();hash.update(b"native-workspace-decl-intent-v1");hash.update(&policy_revision.to_le_bytes());hash.digest128()}else{policy_revision};
    let policy_revision=if auxiliary.contains(&crate::policy_request::WorkspaceAuxiliaryQuestion::Init){let mut hash=xxhash_rust::xxh3::Xxh3::new();hash.update(b"native-workspace-init-intent-v1");hash.update(&policy_revision.to_le_bytes());hash.digest128()}else{policy_revision};
    let policy_revision=if auxiliary.contains(&crate::policy_request::WorkspaceAuxiliaryQuestion::BaseVars){let mut hash=xxhash_rust::xxh3::Xxh3::new();hash.update(b"native-workspace-base-vars-intent-v1");hash.update(&policy_revision.to_le_bytes());hash.digest128()}else{policy_revision};
    let policy_revision=if auxiliary.contains(&crate::policy_request::WorkspaceAuxiliaryQuestion::RequirementBool){let mut hash=xxhash_rust::xxh3::Xxh3::new();hash.update(b"native-workspace-requirement-bool-intent-v1");hash.update(&policy_revision.to_le_bytes());hash.digest128()}else{policy_revision};
    let policy_revision=if auxiliary.contains(&crate::policy_request::WorkspaceAuxiliaryQuestion::PlayerLink){let mut hash=xxhash_rust::xxh3::Xxh3::new();hash.update(b"native-workspace-player-link-intent-v1");hash.update(&policy_revision.to_le_bytes());hash.digest128()}else{policy_revision};
    let policy_revision=if auxiliary.contains(&crate::policy_request::WorkspaceAuxiliaryQuestion::SiliconEntry){let mut hash=xxhash_rust::xxh3::Xxh3::new();hash.update(b"native-workspace-silicon-entry-intent-v1");hash.update(&policy_revision.to_le_bytes());hash.digest128()}else{policy_revision};
    let policy_revision=if auxiliary.contains(&crate::policy_request::WorkspaceAuxiliaryQuestion::UntypedMember){let mut hash=xxhash_rust::xxh3::Xxh3::new();hash.update(b"native-workspace-untyped-member-intent-v1");hash.update(&policy_revision.to_le_bytes());hash.digest128()}else{policy_revision};
    let policy_revision=if auxiliary.contains(&crate::policy_request::WorkspaceAuxiliaryQuestion::WeakRawRead){let mut hash=xxhash_rust::xxh3::Xxh3::new();hash.update(b"native-workspace-weak-raw-read-intent-v1");hash.update(&policy_revision.to_le_bytes());hash.digest128()}else{policy_revision};
    let policy_revision=if auxiliary.contains(&crate::policy_request::WorkspaceAuxiliaryQuestion::RelWriteUndeclared){let mut hash=xxhash_rust::xxh3::Xxh3::new();hash.update(b"native-workspace-rel-write-intent-v1");hash.update(&policy_revision.to_le_bytes());hash.digest128()}else{policy_revision};
    let policy_revision=if auxiliary.contains(&crate::policy_request::WorkspaceAuxiliaryQuestion::Untyped){let mut hash=xxhash_rust::xxh3::Xxh3::new();hash.update(b"native-workspace-untyped-intent-v1");hash.update(&policy_revision.to_le_bytes());hash.digest128()}else{policy_revision};
    let policy_revision=if auxiliary.contains(&crate::policy_request::WorkspaceAuxiliaryQuestion::StoredRefs){let mut hash=xxhash_rust::xxh3::Xxh3::new();hash.update(b"native-workspace-stored_refs-intent-v1");hash.update(&policy_revision.to_le_bytes());hash.digest128()}else{policy_revision};
    let policy_revision=if auxiliary.contains(&crate::policy_request::WorkspaceAuxiliaryQuestion::LibraryLayeringFullAllow){let mut hash=xxhash_rust::xxh3::Xxh3::new();hash.update(b"native-workspace-library-layering-selected-union-v1");hash.update(&policy_revision.to_le_bytes());hash.digest128()}else{policy_revision};
    let policy_revision=if auxiliary.contains(&crate::policy_request::WorkspaceAuxiliaryQuestion::EngineLayeringFullAllow){let mut hash=xxhash_rust::xxh3::Xxh3::new();hash.update(b"native-workspace-engine-layering-selected-union-v1");hash.update(&policy_revision.to_le_bytes());hash.digest128()}else{policy_revision};
    let policy_revision=if auxiliary.contains(&crate::policy_request::WorkspaceAuxiliaryQuestion::SemHandlersFullAllow){
        let mut hash=xxhash_rust::xxh3::Xxh3::new();hash.update(b"native-workspace-sem-handlers-selected-full-v1");hash.update(&policy_revision.to_le_bytes());hash.digest128()
    }else{policy_revision};
    let policy_revision=if auxiliary.contains(&crate::policy_request::WorkspaceAuxiliaryQuestion::ImageDir){
        let mut hash=xxhash_rust::xxh3::Xxh3::new();
        hash.update(b"native-workspace-clean-image-dir-intent-v1");
        hash.update(&policy_revision.to_le_bytes());hash.digest128()
    }else{policy_revision};
    let policy_revision=if let Some(question)=crate::policy_request::WorkspaceAuxiliaryQuestion::exclusive_layering(&auxiliary){let mut hash=xxhash_rust::xxh3::Xxh3::new();match question.layering().expect("exact layering role"){dq_analyze::engine_layering_policy::Layer::Engine=>hash.update(b"native-workspace-engine_layering-intent-v1"),dq_analyze::engine_layering_policy::Layer::Library=>hash.update(b"native-workspace-library_layering-intent-v1")};hash.update(&policy_revision.to_le_bytes());hash.digest128()}else{policy_revision};
    let policy_revision = if map_edits.is_some() || paired_dmm.is_some() {
        let mut hash = xxhash_rust::xxh3::Xxh3::new();
        hash.update(b"native-workspace-map-edits-regular-v1");
        hash.update(&policy_revision.to_le_bytes());
        hash.digest128()
    } else { policy_revision };
    let policy_revision = if library_baseline.is_some() {
        let mut hash = xxhash_rust::xxh3::Xxh3::new();
        hash.update(b"native-workspace-library-sites-baseline-v1");
        hash.update(&policy_revision.to_le_bytes());
        hash.digest128()
    } else { policy_revision };
    let policy_revision = if full_ci_baselines.is_some() {
        let mut hash = xxhash_rust::xxh3::Xxh3::new();
        hash.update(b"native-workspace-full-registry-ci-baselines-v1");
        hash.update(&policy_revision.to_le_bytes());
        hash.digest128()
    } else { policy_revision };
    let ui_dispatcher = ui.map(|(_, _, status)| status);
    let policy_revision = if ui_dispatcher.is_some() {
        let mut hash = xxhash_rust::xxh3::Xxh3::new();
        hash.update(b"native-workspace-authored-doc-ui-v1");
        hash.update(&policy_revision.to_le_bytes());
        hash.digest128()
    } else {
        policy_revision
    };
    let raw_spool = raw_builder.map(WorkspaceRawSpoolBuilder::seal).transpose()?;
    if let (Some(spool), Some((queries, _))) = (&raw_spool, raw_spool_context) {
        spool.require_recording(inputs, &discovery, queries)?;
    }
    let issuance=next_issuance()?;
    let result = Arc::new(WorkspaceCapture {
        source: Arc::downgrade(mapping),raw_source:None,engine_no_model:None,ui_dispatcher,
        source_revision: frontend.revision,
        policy_revision,
        issuance,
        discovery,
        shared_derived,
        files: files.into_boxed_slice(),
        configuration: canonical_configuration,
        config,
        auxiliary,
        deadline,
        library_baseline,
        full_ci_baselines,
        check_grep,
        keys_manifest,
        base_vars_configuration,
        map_edits,
        paired_dmm,
        raw_spool,
        facts,
    });
    if result.retained_charge()? > capture_limit {
        return Err(io::Error::other(
            "workspace capture exceeds existing64MiB extra-owner bound",
        ));
    }
    Ok(result)
}

/// Payloads whose Full Registry consumers take bounded pages. The discovery
/// receipt and ordinary acquisition selector still decide actual membership
/// and native/fixed/alias precedence before this storage choice can apply.
fn spools_private_full_page_source(path: &Path, root: &Path) -> bool {
    let Ok(relative) = path.strip_prefix(root) else { return false; };
    let Some(name) = relative.file_name().map(|name| name.as_encoded_bytes()) else {
        return false;
    };
    if relative.parent() == Some(Path::new("doc/rewrite"))
        && !name.starts_with(b".") && !name.contains(&b'\\') && name.ends_with(b".md")
    {
        return true;
    }
    let typescript = name.ends_with(b".ts") || name.ends_with(b".tsx");
    typescript && (relative.starts_with("tgui/packages/tgui/interfaces")
        || dq_analyze::lints::check_grep::native::selects_filesystem_source(relative))
}

#[cfg(test)]
#[test]
fn private_full_spool_selects_only_bounded_page_source_roles() {
    let root = Path::new("workspace");
    for name in ["doc/rewrite/guide.md", "tgui/packages/tgui/interfaces/Probe.tsx",
        "code/Probe.ts", "code/.ts"] {
        assert!(spools_private_full_page_source(&root.join(name), root), "{name}");
    }
    for name in ["doc/rewrite/.hidden.md", "doc/rewrite/child/guide.md", "doc/guide.md",
        "code/library/capabilities/ui_actions.dm", "code/__defines/verdigris/_bindings.dm",
        "tools/ci/lint_scopes.toml", "deepquarry.dme", "tgui/Probe.tsx", "external/Probe.tsx"] {
        assert!(!spools_private_full_page_source(&root.join(name), root), "{name}");
    }
    assert!(!spools_private_full_page_source(Path::new("other/doc/rewrite/guide.md"), root));
}

/// SAME authenticated original selector for discovered files and explicitly
/// selected optional fixed questions; a missing result never supplies bytes.
fn capture_optional_original<P:SnapshotProvider>(inputs:&RecordingInputs<P>,mapping:&SourceExportMapping,plan:&dm_tree::frontend::FrontendDirectivePlan,discovery:&DiscoveryReceipt,known:&KnownSources<'_>,aliases:&alias_index::AliasIndex<'_>,path:&Path,used:&mut usize,capture_limit:usize,backing_room:usize)->io::Result<Option<CapturedOriginal>>{
    capture_optional_original_using(inputs,mapping,plan,discovery,known,aliases,path,used,capture_limit,backing_room,None)
}
fn capture_optional_original_using<P:SnapshotProvider>(inputs:&RecordingInputs<P>,mapping:&SourceExportMapping,plan:&dm_tree::frontend::FrontendDirectivePlan,discovery:&DiscoveryReceipt,known:&KnownSources<'_>,aliases:&alias_index::AliasIndex<'_>,path:&Path,used:&mut usize,capture_limit:usize,backing_room:usize,spool:Option<(&mut WorkspaceRawSpoolBuilder,usize)>)->io::Result<Option<CapturedOriginal>>{
        let mut primary = path;let mut alias_fact=None;
        if !known.contains_key(primary) {
            if let Some(candidate) = aliases.candidate(path)? {
                let occurrence=*known.get(candidate).ok_or_else(||io::Error::other("alias candidate has no actual mapped occurrence"))?;
                let proof=inputs.acquire_mapped_source_alias(path,candidate,mapping,occurrence)?.ok_or_else(||io::Error::other("workspace source alias contract unsupported"))?;
                if proof.primary_path()!=candidate{return Err(io::Error::other("foreign workspace source alias proof"))}
                alias_fact=Some(proof.requested_fact().clone());
                primary = candidate;
            }
        }
        let native_index=if let Some(index)=known.get(primary){
            let occurrence=plan.occurrences().get(*index).filter(|occurrence|occurrence.path.as_path()==primary).ok_or_else(||io::Error::other("workspace native occurrence join differs"))?;
            if occurrence.non_text_kind()==Some(dm_preprocess::regions::NonTextKind::Map)&&discovery.check_grep_names().is_ok(){None}else{Some(index)}
        }else{None};
        // Actual typed NonText maps have no text acquisition. The selected raw
        // role obtains their bytes through the SAME recorder candidate path;
        // every unexpected text None still takes the strict native lease guard.
        let original = if let Some(index) = native_index {
            let lease = mapping
                .source_acquisition(*index)
                .ok_or_else(|| io::Error::other("native original acquisition unavailable"))?;
            let primary_fact=inputs.mapped_recorded_source_fact(mapping,*index,primary)?;
            crate::input_snapshot::recorded_source_original(lease)?; // prove original-byte representation now
            CapturedOriginal{fact:alias_fact.unwrap_or_else(||primary_fact.clone()),original:Original::Native(Native {
                occurrence: *index,
            })}
        } else {
            let remaining = capture_limit
                .checked_sub(*used).and_then(|remaining|remaining.checked_sub(backing_room))
                .ok_or_else(|| io::Error::other("workspace extra-owner capture budget exceeded"))?;
            let observed=inputs.original_analysis_subject().and_then(|subject|subject.fixed_candidate(path));
            if alias_fact.is_none() && observed.is_none() {
                if let Some((builder, ordinal)) = spool {
                    let scratch = dq_analyze::captured_generator_budget::Budget::new(remaining)
                        .map_err(map_edits_quota)?;
                    let Some(fact) = builder.append_actual(inputs, ordinal, &scratch)? else {
                        return Ok(None);
                    };
                    return Ok(Some(CapturedOriginal { fact, original: Original::Spool(ordinal) }));
                }
            }
            let bytes=match observed{Some(Some(bytes))=>Some(bytes.clone()),Some(None)=>None,None=>inputs.read_policy_candidate(path,remaining)?};
            let Some(bytes)=bytes else{return Ok(None)};
            // A subject-observed SharedBytes clone shares its already admitted payload;
            // this row still owes its own fixed metadata allowance.
            let payload=if observed.is_some(){0}else{bytes.capacity()};
            if payload>remaining{return Err(io::Error::new(io::ErrorKind::OutOfMemory,"Analyze fixed candidate exceeds remaining capture charge"))}
            *used = used
                .checked_add(payload)
                .and_then(|n| n.checked_add(128))
                .ok_or_else(|| io::Error::other("workspace retained owner overflow"))?;
            CapturedOriginal{fact:inputs.recorded_file_fact(path)?,original:Original::Owned(bytes)}
        };
    Ok(Some(original))
}

impl WorkspaceCapture{
 pub(crate) fn lifecycle_page(&self,scope:&crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,start:usize,count:usize,budget:usize,configuration:&dq_analyze::captured_raw_file::Config)->io::Result<(Vec<crate::query_db::CurrentWorkspaceRawFile>,usize)>{self.page_needed(scope,start,count,budget,|relative|Ok(dq_analyze::lifecycle_policy::selects_path(relative)&&!configuration.policy_path_exempt("lifecycle","",relative)))}
}

impl WorkspaceCapture{
 pub(crate) fn covers_raw_tree_policy(
     &self,
     policy: dq_analyze::captured_raw_tree_pages::Policy,
     admit: &mut dyn FnMut(usize) -> io::Result<()>,
 ) -> io::Result<bool> {
     use crate::policy_request::WorkspaceAuxiliaryQuestion as Q;
     use dq_analyze::captured_raw_tree_pages::Policy;

     match policy {
         Policy::NoticePublisher | Policy::ReportInCatch => self.covers_code_dm(admit),
         Policy::UiActions => {
             if !self.has_authored_doc_ui_capture()
                 && !matches!(self.auxiliary.as_slice(), [Q::UiActions | Q::UiActionsFullAllow | Q::DocUiFullAllow])
             {
                 return Ok(false);
             }
             self.discovery.covers_ui_actions(admit)
         }
         Policy::DocSnippets => {
             if !self.has_authored_doc_ui_capture()
                 && !matches!(self.auxiliary.as_slice(), [Q::DocSnippets | Q::DocSnippetsFullAllow | Q::DocUiFullAllow])
             {
                 return Ok(false);
             }
             self.discovery.covers_doc_snippets(admit)
         }
         _ => self.discovery.covers_dm_roots(policy.metadata().select.roots, true, admit),
     }
 }
 pub(crate) fn raw_tree_policy_page(&self,scope:&crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,start:usize,count:usize,budget:usize,config:&dq_analyze::captured_raw_file::Config,policy:dq_analyze::captured_raw_tree_pages::Policy,selected:bool)->io::Result<(Vec<crate::query_db::CurrentWorkspaceRawFile>,usize)>{self.page_needed(scope,start,count,budget,|relative|Ok(policy.selects_path(relative)&&(!selected||!config.policy_path_exempt(policy.name(),policy.metadata().group,relative))))}
 pub(crate) fn covers_decl(&self,admit:&mut dyn FnMut(usize)->io::Result<()>)->io::Result<bool>{self.discovery.covers_dm_roots(dq_analyze::captured_decl_pages::metadata().select.roots,false,admit)}
 pub(crate) fn decl_page(&self,scope:&crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,start:usize,count:usize,budget:usize,config:Option<&dq_analyze::captured_raw_file::Config>)->io::Result<(Vec<crate::query_db::CurrentWorkspaceRawFile>,usize)>{self.page_needed(scope,start,count,budget,|relative|Ok(dq_analyze::captured_decl_pages::selects_path(relative)&&!config.is_some_and(|config|config.policy_path_exempt("decl","",relative))))}
}

impl WorkspaceCapture{
 pub(crate) fn covers_init(&self,admit:&mut dyn FnMut(usize)->io::Result<()>)->io::Result<bool>{self.discovery.covers_dm_roots(dq_analyze::captured_init_pages::metadata().select.roots,false,admit)}
 pub(crate) fn init_page(&self,scope:&crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,start:usize,count:usize,budget:usize,config:Option<&dq_analyze::captured_raw_file::Config>)->io::Result<(Vec<crate::query_db::CurrentWorkspaceRawFile>,usize)>{self.page_needed(scope,start,count,budget,|relative|Ok(dq_analyze::captured_init_pages::selects_path(relative)&&!config.is_some_and(|config|config.policy_path_exempt("init","",relative))))}
}

impl WorkspaceCapture{
 pub(crate) fn with_base_vars_configuration<R>(&self,scope:&crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,visit:impl FnOnce(Option<&[u8]>)->Result<R,dq_analyze::captured_reactive_reads::Failure>)->Result<R,dq_analyze::captured_reactive_reads::Failure>{use dq_analyze::captured_reactive_reads::Failure;self.require_scope(scope)?;if !self.auxiliary.contains(&crate::policy_request::WorkspaceAuxiliaryQuestion::BaseVars){return Err("base-vars fixed configuration was not selected".into())}let pending=match self.base_vars_configuration.ok_or("base-vars fixed configuration observation absent")?{None=>visit(None),Some(index)=>{let file=self.files.get(index).ok_or("base-vars fixed configuration file absent")?;if file.path(&self.discovery).strip_prefix(self.root()).ok()!=Some(Path::new("tools/ci/lint_scopes.toml")){return Err("base-vars fixed configuration role differs".into())}let original=self.original(index,scope)?;visit(Some(match &original{RecordedSourceOriginal::Utf8(text)=>text.as_bytes(),RecordedSourceOriginal::Bytes(bytes)=>bytes.as_slice()}))}};if matches!(&pending,Err(Failure::Operational(_))){return pending}self.require_scope(scope)?;crate::daemon::control::checkpoint()?;pending}
 pub(crate) fn covers_base_vars(&self,admit:&mut dyn FnMut(usize)->io::Result<()>)->io::Result<bool>{self.discovery.covers_dm_roots(&[("code","dm")],false,admit)}
 pub(crate) fn base_vars_page(&self,scope:&crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,start:usize,count:usize,budget:usize)->io::Result<(Vec<crate::query_db::CurrentWorkspaceRawFile>,usize)>{self.page_needed(scope,start,count,budget,|relative|Ok(relative.starts_with("code/")&&relative.ends_with(".dm")))}
 pub(crate) fn covers_requirement_bool(&self,admit:&mut dyn FnMut(usize)->io::Result<()>)->io::Result<bool>{self.discovery.covers_dm_roots(&[("code","dm")],true,admit)}
 pub(crate) fn requirement_bool_page(&self,scope:&crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,start:usize,count:usize,budget:usize)->io::Result<(Vec<crate::query_db::CurrentWorkspaceRawFile>,usize)>{self.page_needed(scope,start,count,budget,|relative|Ok(dq_analyze::captured_requirement_bool_pages::selects_path(relative)))}
}

fn next_issuance()->io::Result<u64>{
    static NEXT_ISSUANCE: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(1);
    let issuance = NEXT_ISSUANCE
        .fetch_update(
            std::sync::atomic::Ordering::Relaxed,
            std::sync::atomic::Ordering::Relaxed,
            |value| value.checked_add(1),
        )
        .map_err(|_| io::Error::other("workspace capture issuance exhausted"))?;
Ok(issuance)
}

/// Private identity issued only after actual complete source acquisition.
/// It is neither a successful semantic graph nor a semantic-unavailable result.
#[derive(Clone,Copy,PartialEq,Eq)]pub(crate) enum RawSourcePurpose{DocSnippets,DocSnippetsFullAllow,Ownership,EngineNoModel,LibraryNoModel,UiActions,OpOrder,NoticePublisher,AllRawFilePolicies,UiActionsFullAllow,DocUiFullAllow}
impl RawSourcePurpose{pub(crate) fn name(self)->&'static str{match self{Self::AllRawFilePolicies=>"all_raw_file_policies",Self::OpOrder=>"op_order",Self::DocSnippets=>"doc_snippets",Self::DocSnippetsFullAllow=>"doc_snippets_full_allow",Self::Ownership=>"ownership",Self::NoticePublisher=>"notice_publisher",Self::EngineNoModel=>"engine_layering",Self::LibraryNoModel=>"library_layering",Self::UiActions=>"ui_actions",Self::UiActionsFullAllow=>"ui_actions_full_allow",Self::DocUiFullAllow=>"doc_ui_full_allow"}}pub(crate) fn question(self)->crate::policy_request::WorkspaceAuxiliaryQuestion{use crate::policy_request::WorkspaceAuxiliaryQuestion as Q;match self{Self::AllRawFilePolicies=>Q::AllRawFilePolicies,Self::OpOrder=>Q::OpOrder,Self::DocSnippets=>Q::DocSnippets,Self::DocSnippetsFullAllow=>Q::DocSnippetsFullAllow,Self::Ownership=>Q::Ownership,Self::NoticePublisher=>Q::NoticePublisher,Self::EngineNoModel=>Q::EngineLayering,Self::LibraryNoModel=>Q::LibraryLayering,Self::UiActions=>Q::UiActions,Self::UiActionsFullAllow=>Q::UiActionsFullAllow,Self::DocUiFullAllow=>Q::DocUiFullAllow}}}
impl RawSourcePurpose {
 pub(crate) fn is_ui(self)->bool{matches!(self,Self::UiActions|Self::UiActionsFullAllow|Self::DocUiFullAllow)}
 pub(crate) fn layering_no_model(self)->bool{matches!(self,Self::EngineNoModel|Self::LibraryNoModel)}}
pub(crate) struct RawSourceIdentity{revision:u128,queries:Weak<crate::query_db::QueryDb>,purpose:RawSourcePurpose}
impl RawSourceIdentity{pub(crate) fn revision(&self)->u128{self.revision}pub(crate) fn purpose(&self)->RawSourcePurpose{self.purpose}pub(crate) fn uses_queries(&self,db:&crate::query_db::QueryDb)->bool{self.queries.upgrade().is_some_and(|held|std::ptr::eq(held.as_ref(),db))}}
impl WorkspaceCapture{
 /// Compare two already-issued raw captures. Physical Original identity
 /// can survive reissuance only after the genuine reread compares exact
 /// bytes; bindings and revision pins themselves are never reused here.
 pub(crate) fn same_bulk_report_inputs(&self, prior: &Self) -> io::Result<bool> {
    if !self.is_sealed_raw_file_capture() || !prior.is_sealed_raw_file_capture()
        || self.root() != prior.root() || self.recursive_roots() != prior.recursive_roots()
        || self.configuration() != prior.configuration()
        || self.facts.policy_directories() != prior.facts.policy_directories()
        || self.discovery.files() != prior.discovery.files()
        || self.files.len() != prior.files.len()
    { return Ok(false); }
    for (current, old) in self.files.iter().zip(&prior.files) {
        crate::daemon::control::checkpoint()?;
        if current.path(&self.discovery) != old.path(&prior.discovery) { return Ok(false); }
        let (Original::RawInput(current), Original::RawInput(old)) = (&current.original, &old.original)
            else { return Ok(false); };
        if !current.original_identity().same_live_original(&old.original_identity()) {
            return Ok(false);
        }
    }
    Ok(true)
 }
 pub(crate) fn is_sealed_raw_file_capture(&self) -> bool {
    self.raw_source.is_some() && self.matches_auxiliary_questions(
        &[crate::policy_request::WorkspaceAuxiliaryQuestion::AllRawFilePolicies])
 }
 pub(crate) fn raw_input_files(&self)->impl Iterator<Item=&dm_preprocess::SourceAcquisitionLease>{self.files.iter().filter_map(|file|match &file.original{Original::RawInput(lease)=>Some(lease),_=>None})}
 pub(crate) fn visit_raw_input_storage(&self,mut visit:impl FnMut((u8,usize),usize)){for lease in self.raw_input_files(){crate::input_snapshot::visit_raw_source_backing(lease,&mut visit);}}
 fn prior_raw_input(&self, path: &Path, purpose: RawSourcePurpose) -> Option<&dm_preprocess::SourceAcquisitionLease> {
    let file = if purpose == RawSourcePurpose::AllRawFilePolicies {
        // This capture keeps the complete discovery order. It has no extra
        // manifest or dispatcher row. Compare the same canonical display key
        // as discovery, whose order differs from Path::Ord on Windows.
        let key = |path: &Path| relative_filesystem_path(path, self.root())
            .map(|relative| relative.to_string_lossy().replace('\\', "/"));
        let sought = key(path)?;
        let index = self.files.binary_search_by(|file| key(file.path(&self.discovery)).as_ref().cmp(&Some(&sought))).ok()?;
        self.files.get(index).filter(|file| file.path(&self.discovery) == path)?
    } else {
        self.files.iter().find(|file| file.path(&self.discovery) == path)?
    };
    match &file.original {
        Original::RawInput(lease) => Some(lease),
        _ => None,
    }
 }
 pub(crate) fn matches_raw_source(&self,owner:&Arc<RawSourceIdentity>,revision:u128)->bool{self.raw_source.as_ref().is_some_and(|held|Weak::ptr_eq(held,&Arc::downgrade(owner)))&&self.source_revision==revision&&owner.revision==revision}
}
/// The Doc producer never asks for Sem. Its source witness is issued before any
/// frontend attempt and does not inspect or parse the unrelated physical DME.
pub(crate) fn capture_raw_only<P:SnapshotProvider>(inputs:&RecordingInputs<P>,intent:&crate::policy_request::AdmittedPolicyRequest,queries:&Arc<crate::query_db::QueryDb>)->io::Result<(Arc<WorkspaceCapture>,Arc<RawSourceIdentity>)>{capture_raw_only_with_prior(inputs,intent,queries,None)}
pub(crate) fn capture_raw_only_with_prior<P:SnapshotProvider>(inputs:&RecordingInputs<P>,intent:&crate::policy_request::AdmittedPolicyRequest,queries:&Arc<crate::query_db::QueryDb>,prior:Option<&Arc<WorkspaceCapture>>)->io::Result<(Arc<WorkspaceCapture>,Arc<RawSourceIdentity>)>{
 queries.with_raw_source_capture_inputs(|budget,credits|capture_raw_only_funded(inputs,intent,queries,prior,None,budget,credits))
}
pub(crate) fn capture_engine_unselected<P:SnapshotProvider>(inputs:&RecordingInputs<P>,intent:&crate::policy_request::AdmittedPolicyRequest,queries:&Arc<crate::query_db::QueryDb>,proof:crate::runner_host::workspace_discovery::EngineNoModelProof)->io::Result<(Arc<WorkspaceCapture>,Arc<RawSourceIdentity>)>{if intent.workspace_auxiliary()!=[proof.preflight().question()]{return Err(io::Error::new(io::ErrorKind::InvalidInput,"engine no-model proof cannot grant another producer purpose"))}proof.require(inputs)?;queries.with_raw_source_capture_inputs(|budget,credits|capture_raw_only_funded(inputs,intent,queries,None,Some(proof),budget,credits))}
// Both workspace capture modes must feed the selected recorder's actual
// original bytes here. This function does not acquire or authenticate files.
fn prepare_captured_ui_dispatcher(
    original: Option<&RecordedSourceOriginal<'_>>,
    budget: &Arc<dq_analyze::captured_generator_budget::Budget>,
) -> io::Result<dq_analyze::ui_actions_policy::PreparedDispatcher> {
    let quota = |message| io::Error::new(io::ErrorKind::OutOfMemory, message);
    // The old raw facade is lossy UTF-8 with universal newlines and preserves
    // BOM bytes. Native compiler decoding is a distinct view, not UI source text.
    let normalization=dq_analyze::captured_generator_budget::Budget::scoped_temporaries(budget).map_err(quota)?;
    let text=if let Some(original)=original{
     let mut backing=Some(0usize);
     let raw=match original{
      crate::input_snapshot::RecordedSourceOriginal::Utf8(text)=>{dq_analyze::captured_raw_file::visit_source_storage(text,|_,bytes|backing=backing.and_then(|n|n.checked_add(bytes)));text.as_bytes()},
      crate::input_snapshot::RecordedSourceOriginal::Bytes(bytes)=>{backing=bytes.capacity().checked_add(128);bytes.as_slice()},
     };
     let transform=if matches!(original,crate::input_snapshot::RecordedSourceOriginal::Utf8(text)if !text.as_bytes().contains(&b'\r')){Some(0)}else{dq_analyze::captured_raw_file::analyze_raw_len(raw).map_err(quota)?.checked_mul(4).and_then(|n|n.checked_add(8192))};
     normalization.charge(backing.and_then(|n|n.checked_add(transform?)).ok_or(io::ErrorKind::OutOfMemory)?).map_err(quota)?;
     Some(crate::input_snapshot::normalize_recorded_policy_original(original))
    }else{None};
    let prepared=dq_analyze::ui_actions_policy::prepare_dispatcher(text.as_ref().map(|text|text.as_str()),budget,&crate::daemon::control::checkpoint).map_err(|actual|match actual{
     dq_analyze::captured_reactive_reads::Failure::Operational(error)=>error,
     dq_analyze::captured_reactive_reads::Failure::Unsupported(message)=>io::Error::new(io::ErrorKind::Unsupported,message),
    })?;
    drop(text);
    drop(normalization);
    Ok(prepared)
}

// File selection is independent of how the actual file will be acquired. The
// caller supplies independent roles proved by its own discovery receipt.
fn keeps_discovered_ui_path(
    relative: &Path,
    aggregate_dm: bool,
    productive_docs: bool,
    dispatcher_needs_sources: bool,
    ui_path_exempt: impl FnOnce(&str) -> io::Result<bool>,
) -> io::Result<bool> {
    if aggregate_dm
        && (relative.starts_with("code") || relative.starts_with("maps"))
        && relative.extension().is_some_and(|extension| extension == "dm")
    {
        return Ok(true);
    }
    if !dispatcher_needs_sources && !productive_docs {
        return Ok(false);
    }
    let relative = relative.to_string_lossy().replace('\\', "/");
    if productive_docs && dq_analyze::doc_snippets_policy::is_doc_path(&relative) {
        return Ok(true);
    }
    if !dispatcher_needs_sources || relative.ends_with(".d.ts") {
        return Ok(false);
    }
    Ok(!ui_path_exempt(&relative)?)
}

#[cfg(test)]
#[test]
fn ui_path_selection_keeps_independent_roles_after_dispatcher_refusal() {
    fn unused(_: &str) -> io::Result<bool> { panic!("this path must not consult UI config") }
    assert!(keeps_discovered_ui_path(Path::new("maps/hidden.dm"), true, true, false, unused).unwrap());
    assert!(keeps_discovered_ui_path(Path::new("doc/rewrite/guide.md"), true, true, false, unused).unwrap());
    assert!(!keeps_discovered_ui_path(Path::new("tgui/Other.tsx"), true, true, false, unused).unwrap());
    assert!(!keeps_discovered_ui_path(Path::new("tgui/Other.d.ts"), true, true, true, unused).unwrap());
    assert!(!keeps_discovered_ui_path(Path::new("tgui/Other.tsx"), true, true, true, |name| {
        assert_eq!(name, "tgui/Other.tsx");
        Ok(true)
    }).unwrap());
    assert!(keeps_discovered_ui_path(Path::new("tgui/Other.tsx"), true, true, true, |_| Ok(false)).unwrap());
}

fn capture_raw_only_funded<P:SnapshotProvider>(inputs:&RecordingInputs<P>,intent:&crate::policy_request::AdmittedPolicyRequest,queries:&Arc<crate::query_db::QueryDb>,prior:Option<&Arc<WorkspaceCapture>>,engine:Option<crate::runner_host::workspace_discovery::EngineNoModelProof>,budget:&Arc<dq_analyze::captured_generator_budget::Budget>,credits:&mut crate::query_db::RawInputCredits<'_>)->io::Result<(Arc<WorkspaceCapture>,Arc<RawSourceIdentity>)>{
 let capture_started = std::time::Instant::now();
 use crate::policy_request::{AnalysisContext,WorkspaceAuxiliaryQuestion as Q};
 let purpose=match intent.workspace_auxiliary(){[Q::AllRawFilePolicies]=>RawSourcePurpose::AllRawFilePolicies,[Q::OpOrder]=>RawSourcePurpose::OpOrder,[Q::DocSnippets]=>RawSourcePurpose::DocSnippets,[Q::DocSnippetsFullAllow]=>RawSourcePurpose::DocSnippetsFullAllow,[Q::Ownership]=>RawSourcePurpose::Ownership,[Q::NoticePublisher]=>RawSourcePurpose::NoticePublisher,[Q::UiActions]=>RawSourcePurpose::UiActions,[Q::UiActionsFullAllow]=>RawSourcePurpose::UiActionsFullAllow,[Q::DocUiFullAllow]=>RawSourcePurpose::DocUiFullAllow,[Q::EngineLayering]if engine.as_ref().is_some_and(|p|p.preflight().question()==Q::EngineLayering)=>RawSourcePurpose::EngineNoModel,[Q::LibraryLayering]if engine.as_ref().is_some_and(|p|p.preflight().question()==Q::LibraryLayering)=>RawSourcePurpose::LibraryNoModel,_=>return Err(io::Error::new(io::ErrorKind::InvalidInput,"actual exclusive raw source purpose required"))};
 if intent.analysis_context()!=Some(AnalysisContext::OriginalAnalyze0290)||dm_preprocess::SourceProvider::initial_environment(inputs)!=dm_preprocess::InitialEnvironment::OriginalChecker0290||!intent.workspace_generators().is_empty()||!intent.files().is_empty()||!intent.search_folders().is_empty(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"raw source requires its exact admitted original purpose"))}
 let workspace=intent.workspace().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"raw Doc workspace intent absent"))?;
 let prior = prior.and_then(|capture| {
     let owner = capture.raw_source.as_ref().and_then(Weak::upgrade)?;
     (owner.uses_queries(queries.as_ref()) && owner.purpose() == purpose
         && capture.matches_request(workspace)).then_some((capture, owner))
 });
 let contract=crate::runner_host::workspace_discovery::DiscoveryContract{root:workspace.root.clone(),recursive_roots:workspace.recursive_roots.clone()};
 let quota=|message|io::Error::new(io::ErrorKind::OutOfMemory,message);
 let metadata_peak=dq_analyze::captured_generator_budget::Budget::scoped_temporaries(budget).map_err(quota)?;metadata_peak.charge(EXTRA_BUDGET).map_err(quota)?;
 let mut doc_config=None;let discovery=match &engine{Some(proof)=>{proof.require(inputs)?;Arc::clone(proof.preflight().discovery())},None=>Arc::new(match purpose{
  RawSourcePurpose::AllRawFilePolicies=>{
   use dq_analyze::selected_exclusions_wire::Roster;
   let expected=Roster::AllRawFilePolicies.workspace_roots();
   if workspace.recursive_roots.len()!=expected.len()||workspace.recursive_roots.iter().zip(expected).any(|(path,name)|*path!=workspace.root.join(name))
    ||workspace.configuration!=workspace.root.join("tools/ci/lint_scopes.toml"){return Err(io::Error::new(io::ErrorKind::InvalidInput,"raw file roster needs its actual closed roots and configuration"))}
   crate::runner_host::workspace_discovery::discover(inputs,contract)?
  },
  RawSourcePurpose::DocUiFullAllow=>{let(discovery,config)=crate::runner_host::workspace_discovery::discover_doc_ui_joined(inputs,contract,&workspace.configuration)?;doc_config=Some(config);discovery},
  RawSourcePurpose::DocSnippetsFullAllow=>{let(discovery,config)=crate::runner_host::workspace_discovery::discover_doc_snippets_joined(inputs,contract,&workspace.configuration)?;doc_config=Some(config);discovery},
  RawSourcePurpose::DocSnippets=>{let(discovery,config)=crate::runner_host::workspace_discovery::discover_doc_snippets_productive(inputs,contract,&workspace.configuration)?;doc_config=Some(config);discovery},RawSourcePurpose::Ownership|RawSourcePurpose::OpOrder|RawSourcePurpose::NoticePublisher=>{if workspace.recursive_roots.as_slice()!=[workspace.root.join("code")]{return Err(io::Error::new(io::ErrorKind::InvalidInput,"raw source purpose requires exactly actual CODE_DM"))}crate::runner_host::workspace_discovery::discover_ownership_code(inputs,contract)?},RawSourcePurpose::UiActionsFullAllow=>{let(discovery,config)=crate::runner_host::workspace_discovery::discover_ui_actions_joined(inputs,contract,&workspace.configuration)?;doc_config=Some(config);discovery},RawSourcePurpose::UiActions=>{let(discovery,config)=crate::runner_host::workspace_discovery::discover_ui_actions_productive(inputs,contract,&workspace.configuration)?;doc_config=Some(config);discovery},RawSourcePurpose::EngineNoModel|RawSourcePurpose::LibraryNoModel=>return Err(io::Error::new(io::ErrorKind::InvalidInput,"engine no-model capture requires authentic selection proof"))})};discovery.validate_recording(inputs)?;
 dm_profile::detail_mark("raw_capture.discovery", capture_started);
 let mut used=discovery.retained_charge()?.checked_add(std::mem::size_of::<WorkspaceCapture>()+std::mem::size_of::<RawSourceIdentity>()+std::mem::size_of::<crate::query_db::QueryDb>()+512).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;
 let mut admit=|bytes:usize|->io::Result<()>{used=used.checked_add(bytes).filter(|n|*n<=EXTRA_BUDGET).ok_or_else(||io::Error::new(io::ErrorKind::OutOfMemory,"raw Doc source exceeds existing capture allowance"))?;Ok(())};
 let covered=match purpose{
  RawSourcePurpose::AllRawFilePolicies=>{
   let mut covered=true;
   for &name in dq_analyze::selected_exclusions_wire::Roster::AllRawFilePolicies.names(){
    let select=match name{
     "allow_annotations"=>dq_analyze::allow_annotation_policy::metadata().select,
     "notice_publisher"=>dq_analyze::captured_raw_tree_pages::Policy::NoticePublisher.metadata().select,
     "report_in_catch"=>dq_analyze::captured_raw_tree_pages::Policy::ReportInCatch.metadata().select,
     _=>dq_analyze::captured_raw_policy::metadata(name).ok_or_else(||io::Error::other("closed raw roster policy metadata absent"))?.select,
    };
    if !discovery.covers_dm_roots(select.roots,true,&mut admit)?{covered=false;break}
   }
   covered&&discovery.covers_dm_roots(dq_analyze::tree::CODE_MAPS_DM.roots,false,&mut admit)?
  },
  RawSourcePurpose::DocUiFullAllow=>discovery.covers_doc_snippets(&mut admit)?&&discovery.covers_ui_actions(&mut admit)?&&discovery.covers_code_dm(&mut admit)?&&discovery.covers_dm_roots(&[("maps","dm")],false,&mut admit)?,
  RawSourcePurpose::DocSnippetsFullAllow=>discovery.covers_doc_snippets(&mut admit)?&&discovery.covers_code_dm(&mut admit)?&&discovery.covers_dm_roots(&[("maps","dm")],false,&mut admit)?,RawSourcePurpose::DocSnippets=>discovery.covers_doc_snippets(&mut admit)?,RawSourcePurpose::UiActionsFullAllow=>discovery.covers_ui_actions(&mut admit)?&&discovery.covers_code_dm(&mut admit)?&&discovery.covers_dm_roots(&[("maps","dm")],false,&mut admit)?,RawSourcePurpose::UiActions=>discovery.covers_ui_actions(&mut admit)?,RawSourcePurpose::OpOrder|RawSourcePurpose::Ownership|RawSourcePurpose::NoticePublisher|RawSourcePurpose::EngineNoModel|RawSourcePurpose::LibraryNoModel=>discovery.covers_code_dm(&mut admit)?};if !covered{return Err(io::Error::new(io::ErrorKind::InvalidInput,"raw source lacks its actual purpose-specific discovery"))}drop(admit);
 // Capture the actual dispatcher first. Missing/bad source never opens any
 // other selected body. A visible path is selected by discovery, not reopened
 // as a guessed filesystem path outside the original UI namespace.
 let ui_joined=matches!(purpose,RawSourcePurpose::UiActionsFullAllow|RawSourcePurpose::DocUiFullAllow);
 let ui_purpose=purpose.is_ui();
 let ui_dispatcher_path=if ui_purpose{
  Some(workspace.root.join(dq_analyze::ui_actions_policy::DISPATCHER))
 }else{None};
 let mut acquire=|path:&Path|->io::Result<dm_preprocess::SourceAcquisitionLease>{
  crate::daemon::control::checkpoint()?;
  let width=path.as_os_str().len().checked_mul(16).and_then(|n|n.checked_add(4096)).ok_or(io::ErrorKind::OutOfMemory)?;
  used=used.checked_add(width).filter(|n|*n<=EXTRA_BUDGET).ok_or(io::ErrorKind::OutOfMemory)?;
  let scratch=dq_analyze::captured_generator_budget::Budget::scoped_temporaries(budget).map_err(quota)?;
  let allowance=budget.remaining().saturating_sub(8192)/8;if allowance==0{return Err(quota("raw source read has no remaining actual input allowance".into()))}
  scratch.charge(allowance+8192).map_err(quota)?;
  let old=prior.as_ref().and_then(|(capture, _)| capture.prior_raw_input(path, purpose));
  credits.prepare_source()?;
  let lease=inputs.read_raw_source(path,allowance,old,|capacity,exceptional,needs_decode|scratch.charge(capacity.checked_mul(if !needs_decode{0}else if exceptional{13}else{5}).and_then(|n|n.checked_add(8192)).ok_or(io::ErrorKind::OutOfMemory)?).map_err(quota))?.ok_or_else(||io::Error::new(io::ErrorKind::Interrupted,"discovered raw source disappeared"))?;
  credits.retain(&lease)?;drop(scratch);Ok(lease)
 };
 let mut ui_original=match &ui_dispatcher_path{
  Some(path)if discovery.files().contains(path)=>Some(acquire(path)?),_=>None,
 };
 let prepared_ui=if ui_purpose{
  let original=ui_original.as_ref().map(crate::input_snapshot::recorded_source_original).transpose()?;
  Some(prepare_captured_ui_dispatcher(original.as_ref(),budget)?)
 }else{None};
 let ui_needs_sources=prepared_ui.as_ref().is_some_and(|value|value.needs_sources());
 let source_count=if engine.is_some(){0}else if !ui_joined&&prepared_ui.is_some()&&!ui_needs_sources{usize::from(ui_original.is_some())}else{discovery.files().len()};
 let slots=source_count.checked_add(1+usize::from(purpose==RawSourcePurpose::OpOrder)).ok_or(io::ErrorKind::OutOfMemory)?;let max_slots=slots.checked_mul(4).ok_or(io::ErrorKind::OutOfMemory)?;
 let capacity=max_slots.checked_mul(std::mem::size_of::<File>()+std::mem::size_of::<PathBuf>()).and_then(|n|n.checked_add(128)).ok_or(io::ErrorKind::OutOfMemory)?;
 drop(acquire);
 used=used.checked_add(capacity).filter(|n|*n<=EXTRA_BUDGET).ok_or(io::ErrorKind::OutOfMemory)?;
 let mut files=Vec::new();files.try_reserve_exact(source_count+usize::from(purpose==RawSourcePurpose::OpOrder)).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;if files.capacity()>max_slots{return Err(io::ErrorKind::OutOfMemory.into())}
 let mut selected=Vec::new();selected.try_reserve_exact(slots).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;if selected.capacity()>max_slots{return Err(io::ErrorKind::OutOfMemory.into())}
 let mut ui_dispatcher_index=None;
 for (source_index, path) in discovery.files().iter().enumerate(){
  if engine.is_some(){break}
  if prepared_ui.is_some()&&ui_dispatcher_path.as_ref()!=Some(path){
   let relative=path.strip_prefix(&workspace.root).map_err(|_|io::Error::new(io::ErrorKind::InvalidInput,"UI selected source escapes actual root"))?;
   if !keeps_discovered_ui_path(relative,ui_joined,purpose==RawSourcePurpose::DocUiFullAllow,ui_needs_sources,|relative|{
    Ok(discovery.productive_ui_configuration(&workspace.configuration)?.ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"UI source selection lacks actual configuration"))?.policy_path_exempt("ui_actions",dq_analyze::ui_actions_policy::metadata().group,relative))
   })?{continue}
  }

  crate::daemon::control::checkpoint()?;
  let lease=if ui_dispatcher_path.as_ref()==Some(path){ui_dispatcher_index=Some(files.len());ui_original.take().ok_or_else(||io::Error::new(io::ErrorKind::InvalidData,"actual UI dispatcher acquisition missing"))?}else{
   let width=path.capacity().checked_mul(16).and_then(|n|n.checked_add(4096)).ok_or(io::ErrorKind::OutOfMemory)?;used=used.checked_add(width).filter(|n|*n<=EXTRA_BUDGET).ok_or(io::ErrorKind::OutOfMemory)?;
   let scratch=dq_analyze::captured_generator_budget::Budget::scoped_temporaries(budget).map_err(quota)?;let allowance=budget.remaining().saturating_sub(8192)/8;if allowance==0{return Err(quota("raw source read has no remaining actual input allowance".into()))}scratch.charge(allowance+8192).map_err(quota)?;
   let old=prior.as_ref().and_then(|(capture, _)| capture.prior_raw_input(path, purpose));
   credits.prepare_source()?;let lease=inputs.read_raw_source(path,allowance,old,|capacity,exceptional,needs_decode|scratch.charge(capacity.checked_mul(if !needs_decode{0}else if exceptional{13}else{5}).and_then(|n|n.checked_add(8192)).ok_or(io::ErrorKind::OutOfMemory)?).map_err(quota))?.ok_or_else(||io::Error::new(io::ErrorKind::Interrupted,"discovered raw source disappeared"))?;
   if purpose == RawSourcePurpose::AllRawFilePolicies {
      credits.retain_sealed(&lease)?;
   } else {
      credits.retain(&lease)?;
   }
   drop(scratch);
   lease
  };
  inputs.recorded_file_fact(path)?;files.push(File{path:FilePath::Discovered(source_index),original:Original::RawInput(lease)});selected.push(path.clone());
 }
 dm_profile::detail_mark("raw_capture.sources", capture_started);
 let mut op_order_manifest=None;
 if purpose==RawSourcePurpose::OpOrder{
  let path=workspace.root.join("deepquarry.dme");crate::daemon::control::checkpoint()?;
  let width=path.as_os_str().len().checked_mul(16).and_then(|n|n.checked_add(4096)).ok_or(io::ErrorKind::OutOfMemory)?;used=used.checked_add(width).filter(|n|*n<=EXTRA_BUDGET).ok_or(io::ErrorKind::OutOfMemory)?;
  let scratch=dq_analyze::captured_generator_budget::Budget::scoped_temporaries(budget).map_err(quota)?;let allowance=budget.remaining().saturating_sub(8192)/8;if allowance==0{return Err(quota("op_order fixed manifest has no actual input allowance".into()))}scratch.charge(allowance+8192).map_err(quota)?;
  let old=prior.as_ref().and_then(|(capture, _)| capture.prior_raw_input(&path, purpose));
  credits.prepare_source()?;let lease=inputs.read_raw_source(&path,allowance,old,|capacity,exceptional,needs_decode|scratch.charge(capacity.checked_mul(if !needs_decode{0}else if exceptional{13}else{5}).and_then(|n|n.checked_add(8192)).ok_or(io::ErrorKind::OutOfMemory)?).map_err(quota))?;
  let index=if let Some(lease)=lease{credits.retain(&lease)?;let index=files.len();inputs.recorded_file_fact(&path)?;files.push(File{path:FilePath::Fixed(Box::new(path.clone())),original:Original::RawInput(lease)});Some(index)}else{None};
  op_order_manifest=Some(index);selected.push(path);drop(scratch);
 }
 let ui_dispatcher=prepared_ui.map(|prepared|UiDispatcherCapture{index:ui_dispatcher_index,prepared});
 let config_width=workspace.configuration.as_os_str().len().checked_mul(8).and_then(|n|n.checked_add(1024)).ok_or(io::ErrorKind::OutOfMemory)?;used=used.checked_add(config_width).filter(|n|*n<=EXTRA_BUDGET).ok_or(io::ErrorKind::OutOfMemory)?;let configuration=canonical_path(&workspace.configuration);if discovery.files().contains(&configuration){return Err(io::Error::new(io::ErrorKind::InvalidInput,"raw configuration cannot also be selected source"))}let config=match &engine{Some(proof)=>{if configuration!=proof.preflight().configuration().0{return Err(io::Error::new(io::ErrorKind::InvalidInput,"engine configuration path differs"))}proof.preflight().configuration_bytes().cloned()},None=>match doc_config{Some(bytes)=>bytes,None=>inputs.read_policy_candidate(&configuration,EXTRA_BUDGET-used)?}};used=used.checked_add(config.as_ref().map_or(0,SharedBytes::capacity)).filter(|n|*n<=EXTRA_BUDGET).ok_or(io::ErrorKind::OutOfMemory)?;selected.push(configuration.clone());
 let selected=selected.into_iter().collect::<std::collections::BTreeSet<_>>();let facts=inputs.policy_workspace_closure(&selected,discovery.directory_paths())?;let revision=crate::policy_request::workspace_revision(0,&facts,&workspace.root,&workspace.recursive_roots,&configuration)?;let owner=Arc::new(RawSourceIdentity{revision,queries:Arc::downgrade(queries),purpose});let mut hash=xxhash_rust::xxh3::Xxh3::new();hash.update(b"original-source-only-not-semantic-v1");hash.update(purpose.name().as_bytes());hash.update(&revision.to_le_bytes());let policy_revision=hash.digest128();
 let capture=Arc::new(WorkspaceCapture{source:Weak::new(),raw_source:Some(Arc::downgrade(&owner)),engine_no_model:engine,ui_dispatcher,source_revision:revision,policy_revision,issuance:next_issuance()?,discovery,shared_derived:None,files:files.into_boxed_slice(),configuration,config,auxiliary:vec![purpose.question()],deadline:None,library_baseline:None,full_ci_baselines:None,check_grep:None,keys_manifest:op_order_manifest,base_vars_configuration:None,map_edits:None,paired_dmm:None,raw_spool:None,facts});
 if used>EXTRA_BUDGET||capture.retained_charge()?>EXTRA_BUDGET{return Err(io::Error::new(io::ErrorKind::OutOfMemory,"raw Doc retained source exceeds existing capture allowance"))}capture.discovery.validate_recording(inputs)?;let metadata=capture.retained_charge()?;budget.charge(metadata).map_err(quota)?;credits.retain_capture_metadata(&capture,metadata)?;drop(metadata_peak);dm_profile::detail_mark("raw_capture.settled", capture_started);Ok((capture,owner))
}

impl WorkspaceCapture{
 /// Borrow metadata from this exact issued discovery; no source view/body is opened.
 pub(crate) fn for_each_engine_path(&self,scope:&crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,admit:&mut dyn FnMut(usize)->io::Result<()>,visit:&mut dyn FnMut(&str)->io::Result<()>)->io::Result<()>{
  self.require_scope(scope)?;if !self.covers_code_dm(admit)?{return Err(io::Error::new(io::ErrorKind::InvalidInput,"engine metadata requires actual full visible CODE_DM discovery"))}
  for path in self.discovery.files(){crate::daemon::control::checkpoint()?;let relative=path.strip_prefix(self.root()).map_err(|_|io::Error::new(io::ErrorKind::InvalidInput,"engine discovery escapes current root"))?;admit(relative.as_os_str().len().checked_mul(8).and_then(|n|n.checked_add(512)).ok_or(io::ErrorKind::OutOfMemory)?)?;let relative=relative.to_string_lossy().replace('\\',"/");if dq_analyze::captured_raw_file::is_code_dm(&relative){visit(&relative)?}}
  self.require_scope(scope)?;Ok(())
 }
 pub(crate) fn engine_marker_page(&self,scope:&crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,start:usize,count:usize,budget:usize,config:&dq_analyze::captured_raw_file::Config,layer:dq_analyze::engine_layering_policy::Layer)->io::Result<(Vec<crate::query_db::CurrentWorkspaceRawFile>,usize)>{self.page_needed(scope,start,count,budget,|relative|Ok(dq_analyze::captured_raw_file::is_code_dm(relative)&&layer.selects(relative)&&!config.policy_path_exempt(layer.name(),"",relative)))}
}

impl WorkspaceCapture{pub(crate) fn require_engine_preflight(&self,engine:&crate::runner_host::workspace_discovery::EnginePreflight)->io::Result<()>{if self.auxiliary.as_slice()!=[engine.question()]||!Arc::ptr_eq(engine.discovery(),&self.discovery)||engine.configuration()!=self.configuration(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"engine actual discovery/configuration owner differs from current capture"))}Ok(())}}

impl WorkspaceCapture{pub(crate) fn engine_no_model(&self)->io::Result<&crate::runner_host::workspace_discovery::EngineNoModelProof>{let proof=self.engine_no_model.as_ref().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"actual engine no-model selection absent"))?;self.require_engine_preflight(proof.preflight())?;if !proof.preflight().is_empty(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"engine no-model capture contains selected sources"))}Ok(proof)}}

// Closed fixed AUTO observation for the actual Sys reactive semantic question.
// A full CODE discovery negative is different from an acquisition/read failure.
impl WorkspaceCapture {
 pub(crate) fn sys_reactive_auto_index(&self,scope:&crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,admit:&mut dyn FnMut(usize)->io::Result<()>)->io::Result<Option<usize>>{
  self.require_scope(scope)?;
  if !self.auxiliary.contains(&crate::policy_request::WorkspaceAuxiliaryQuestion::SysReactive){return Err(io::Error::new(io::ErrorKind::InvalidInput,"Sys reactive fixed source question was not selected"))}
  if !self.discovery.covers_code_dm(admit)?{return Err(io::Error::new(io::ErrorKind::InvalidInput,"Sys reactive AUTO observation requires actual CODE discovery"))}
  let relative=Path::new(dq_analyze::auto_setter_calls_policy::AUTO_REL);
  let mut observed=None;
  for path in self.discovery.files(){crate::daemon::control::checkpoint()?;if path.strip_prefix(self.root()).is_ok_and(|path|path==relative){if observed.replace(path).is_some(){return Err(io::Error::new(io::ErrorKind::InvalidData,"Sys reactive fixed source discovery repeated"))}}}
  let Some(path)=observed else{return Ok(None)};
  let mut selected=None;
  for(index,file)in self.files.iter().enumerate(){crate::daemon::control::checkpoint()?;if file.path(&self.discovery)==path{if selected.replace(index).is_some(){return Err(io::Error::new(io::ErrorKind::InvalidData,"Sys reactive fixed source acquisition repeated"))}}}
  selected.map(Some).ok_or_else(||io::Error::new(io::ErrorKind::InvalidData,"discovered Sys reactive AUTO lacks actual acquisition"))
 }
 pub(crate) fn sys_reactive_auto_page(&self,scope:&crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,index:usize,budget:usize)->io::Result<(Vec<crate::query_db::CurrentWorkspaceRawFile>,usize)>{
  let file=self.files.get(index).ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"Sys reactive fixed source index absent"))?;
  if !file.path(&self.discovery).strip_prefix(self.root()).is_ok_and(|p|p==Path::new(dq_analyze::auto_setter_calls_policy::AUTO_REL)){return Err(io::Error::new(io::ErrorKind::InvalidInput,"Sys reactive fixed source index changed role"))}
  self.page_needed(scope,index,1,budget,|relative|Ok(relative==dq_analyze::auto_setter_calls_policy::AUTO_REL))
 }
}

impl WorkspaceCapture{
 pub(crate) fn covers_allow_unused(&self,plan:&dq_analyze::captured_allow_annotations::full_unused::SelectedTreePlanData,admit:&mut dyn FnMut(usize)->io::Result<()>)->io::Result<bool>{for root in plan.roots(){if !self.discovery.covers_dm_roots(&[(*root,"dm")],false,admit)?{return Ok(false)}}Ok(true)}
 pub(crate) fn allow_unused_page(&self,scope:&crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,start:usize,count:usize,budget:usize,plan:&dq_analyze::captured_allow_annotations::full_unused::SelectedTreePlanData)->io::Result<(Vec<crate::query_db::CurrentWorkspaceRawFile>,usize)>{self.page_needed(scope,start,count,budget,|relative|Ok(plan.matches_path(relative)))}
}

#[cfg(test)]
mod full_ci_baseline_observation_tests {
    use super::*;
    use crate::input_snapshot::FileSystemInputs;

    #[test]
    fn joined_workspace_revision_borrows_the_same_actual_directory_facts() {
        use crate::runner_host::workspace_discovery::{discover, DiscoveryContract};
        let root = crate::test_scratch::dir("joined-workspace-directory-loan");
        let code = root.join("code");
        std::fs::create_dir_all(code.join("nested")).unwrap();
        std::fs::write(code.join("nested/probe.dm"), b"/datum/probe\n").unwrap();
        let inputs = RecordingInputs::new(FileSystemInputs, 1);
        let discovery = discover(&inputs, DiscoveryContract {
            root: root.clone(), recursive_roots: vec![code],
        }).unwrap();
        assert!(!discovery.policy_directories().is_empty());
        let old = inputs.policy_workspace_closure_paths(std::iter::empty(), discovery.directory_paths()).unwrap();
        let compact = inputs.policy_workspace_joined_files(std::iter::empty(), &discovery).unwrap();
        assert!(compact.policy_directories().is_empty());
        let roots = &discovery.contract().recursive_roots;
        let config = root.join("tools/ci/lint_scopes.toml");
        assert_eq!(
            crate::policy_request::workspace_revision(12, &old, &root, roots, &config).unwrap(),
            crate::policy_request::workspace_revision_with_directories(
                12, &compact, discovery.policy_directories(), &root, roots, &config,
            ).unwrap(),
        );
        let foreign = RecordingInputs::new(FileSystemInputs, 1);
        assert!(foreign.policy_workspace_joined_files(std::iter::empty(), &discovery).is_err());
    }

    #[test]
    fn registered_ci_baseline_only_changes_invalidate_the_actual_workspace_closure() {
        let root = crate::test_scratch::dir("full-ci-baseline-inputs");
        let readable = root.join(LIBRARY_SITES_BASELINE);
        std::fs::create_dir_all(readable.parent().unwrap()).unwrap();
        let capture = |expected: Option<&[u8]>| {
            let inputs = RecordingInputs::new(FileSystemInputs, 1);
            let queries = crate::query_db::QueryDb::default();
            let budget = dq_analyze::captured_generator_budget::Budget::new(1 << 20).unwrap();
            let baselines = FullCiBaselines::observe(&inputs, &root, &budget, &queries).unwrap();
            let (_, _, seen) = baselines.rows.iter()
                .find(|(name, _, _)| *name == LIBRARY_SITES_BASELINE).unwrap();
            assert_eq!(seen.bytes().map(|bytes| bytes.as_slice()), expected);
            if expected.is_none() {
                assert!(matches!(seen, FixedLibraryBaseline::Missing));
            }
            let selected = baselines.files().filter(|(_, fact)| fact.selects_file_fact())
                .map(|(path, _)| path.clone()).collect();
            let closure = inputs.policy_workspace_closure(&selected, std::iter::empty()).unwrap();
            assert!(closure.restat(&FileSystemInputs).unwrap().changed.is_empty());
            closure
        };
        let missing = capture(None);
        std::fs::write(&readable, [0xff]).unwrap();
        assert!(missing.restat(&FileSystemInputs).unwrap().changed.contains(&canonical_path(&readable)));
        let present = capture(Some(&[0xff]));
        std::fs::write(&readable, b"now a real baseline").unwrap();
        assert!(present.restat(&FileSystemInputs).unwrap().changed.contains(&canonical_path(&readable)));
    }
}

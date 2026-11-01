//! Production raw producer, distinct from bounded fixture CapturedPolicyInputs.
//! Native entries retain compare-only weak acquisition IDs, never all text views.
use crate::input_snapshot::{
    FileInput, InputSnapshot, RecordedSourceOriginal, RecordingInputs, SnapshotProvider,
};
use crate::runner_host::workspace_discovery::DiscoveryReceipt;
use crate::query_db::{CurrentWorkspaceRawFile as CurrentFile,WorkspaceRawSourceProof as SourceProof};
use dm_preprocess::{
    regions::{canonical_path, relative_filesystem_path},
    SourceAcquisitionIdentity,
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
#[path = "workspace_alias_index.rs"]
mod alias_index;
pub(crate) use alias_index::AliasIndex as WorkspaceAliasIndex;
struct Native {
    occurrence: usize,
    identity: SourceAcquisitionIdentity,
    primary: FileInput,
}
enum Original {
    Native(Native),
    Owned(SharedBytes),
}
struct File {
    path: PathBuf,
    fact: FileInput,
    original: Original,
}
pub(crate) struct WorkspaceCapture {
    source: Weak<SourceExportMapping>,
    source_revision: u128,
    policy_revision: u128,
    issuance: u64,
    discovery: Arc<DiscoveryReceipt>,
    files: Box<[File]>,
    configuration: PathBuf,
    config: Option<SharedBytes>,
    auxiliary: Vec<crate::policy_request::WorkspaceAuxiliaryQuestion>,
    deadline: Option<(PathBuf,Option<SharedBytes>)>,
    check_grep:Option<[Option<usize>;6]>,
    facts: InputSnapshot,
}
impl WorkspaceCapture {
    pub(crate) fn require_check_grep_archive(&self,scope:&crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,archive:&dm_tree::frontend::BodyArchive)->io::Result<()>{
     self.check_grep_names(scope)?;if !Weak::ptr_eq(&self.source,&Arc::downgrade(archive.source_mapping())){return Err(io::Error::new(io::ErrorKind::InvalidInput,"check_grep body archive belongs to another actual source mapping"))}Ok(())
    }
    pub(crate) fn check_grep_names<'a>(&'a self,scope:&crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>)->io::Result<(&'a[PathBuf],&'a[PathBuf])>{
     self.require_scope(scope)?;if self.check_grep.is_none()||!self.auxiliary.contains(&crate::policy_request::WorkspaceAuxiliaryQuestion::CheckGrep){return Err(io::Error::new(io::ErrorKind::Unsupported,"check_grep auxiliary observations were not selected"))}self.discovery.check_grep_names()
    }
    pub(crate) fn with_check_grep_fixed<R>(&self,scope:&crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,which:dq_analyze::lints::check_grep::native::Fixed,visit:impl FnOnce(Option<&[u8]>)->Result<R,dq_analyze::captured_reactive_reads::Failure>)->Result<R,dq_analyze::captured_reactive_reads::Failure>{
     use dq_analyze::captured_reactive_reads::Failure;self.check_grep_names(scope)?;
     let indices=self.check_grep.as_ref().ok_or("check_grep fixed observations unavailable")?;
     let pending=match indices[which.index()]{None=>visit(None),Some(index)=>{
      let file=self.files.get(index).ok_or("check_grep fixed source index absent")?;
      if file.path.strip_prefix(self.root()).ok()!=Some(Path::new(which.relative())){return Err("check_grep fixed source role differs".into())}
      let original=self.original(index,scope)?;visit(Some(match &original{RecordedSourceOriginal::Utf8(text)=>text.as_bytes(),RecordedSourceOriginal::Bytes(bytes)=>bytes.as_slice()}))
     }};
     if matches!(&pending,Err(Failure::Operational(_))){return pending}self.require_scope(scope)?;crate::daemon::control::checkpoint()?;pending
    }
    pub(crate) fn for_each_check_grep_dme(&self,scope:&crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,visit:&mut dyn FnMut(&str,&[u8])->Result<(),dq_analyze::captured_reactive_reads::Failure>)->Result<(),dq_analyze::captured_reactive_reads::Failure>{
     use dq_analyze::captured_reactive_reads::Failure;let(names,_)=self.check_grep_names(scope)?;let mut count=0;
     for(index,file)in self.files.iter().enumerate(){
      if file.path.parent()!=Some(self.root()){continue}let Some(name)=file.path.file_name().and_then(|name|name.to_str())else{continue};
      if !dq_analyze::lints::check_grep::native::is_root_dme(name){continue}
      if names.binary_search(&file.path).is_err(){return Err("check_grep root manifest is outside its typed discovery".into())}
      crate::daemon::control::checkpoint()?;self.require_scope(scope)?;
      let original=self.original(index,scope)?;let pending=visit(name,match &original{RecordedSourceOriginal::Utf8(text)=>text.as_bytes(),RecordedSourceOriginal::Bytes(bytes)=>bytes.as_slice()});
      if matches!(&pending,Err(Failure::Operational(_))){return pending}self.require_scope(scope)?;crate::daemon::control::checkpoint()?;pending?;count+=1;
     }
     if count!=names.len(){return Err("check_grep root manifest traversal omitted an observed file".into())}self.require_scope(scope)?;Ok(())
    }
    pub(crate) fn check_grep_page(&self,scope:&crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,start:usize,count:usize,budget:usize,configuration:&dq_analyze::captured_raw_file::Config,include_exempt:bool)->io::Result<(Vec<crate::query_db::CurrentWorkspaceRawFile>,usize)>{
     self.check_grep_names(scope)?;
     self.page_needed(scope,start,count,budget,|relative|Ok(dq_analyze::lints::check_grep::native::selects_source(relative)&&(include_exempt||!configuration.policy_path_exempt("check_grep","",relative))))
    }

    pub(crate) fn census(self: &Arc<Self>, census: &mut crate::heap_census::HeapCensus) {
        let owner = "query_snapshot.workspace.capture";
        if !census.arc_object(owner, self) {
            return;
        }
        census.slice(owner, self.files.as_ref(), true);
        census.path(owner, &self.configuration);
        for file in &self.files {
            census.path(owner, &file.path);
            census.path(owner, &file.fact.path);
            match &file.original {
                Original::Native(native) => {
                    census.path(owner, &native.primary.path);
                    native.identity.visit_storage(|storage| {
                        if let dm_preprocess::source_acquisition::AcquisitionStorage::Object {
                            address,
                            bytes,
                        } = storage
                        {
                            census.exposed_buffer(owner, address, bytes, bytes);
                        }
                    });
                }
                Original::Owned(bytes) => {
                    if census.arc_object(owner, bytes.shared_owner()) {
                        census.vec_payload(owner, bytes.shared_owner().bytes());
                    }
                }
            }
        }
        if let Some(bytes) = &self.config {
            if census.arc_object(owner, bytes.shared_owner()) {
                census.vec_payload(owner, bytes.shared_owner().bytes());
            }
        }
        census.vec_payload(owner,&self.auxiliary);
        if let Some((path,bytes))=&self.deadline{census.path(owner,path);if let Some(bytes)=bytes{if census.arc_object(owner,bytes.shared_owner()){census.vec_payload(owner,bytes.shared_owner().bytes());}}}
        self.discovery.census(census);
        census.workspace_policy_facts(&self.facts);
    }

    pub(crate) fn auxiliary(&self)->&[crate::policy_request::WorkspaceAuxiliaryQuestion]{&self.auxiliary}
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
        same && self
            .facts
            .policy_directories()
            .iter()
            .all(|(p, f)| complete.policy_directories().get(p) == Some(f))
    }

    pub(crate) fn covers_selected_raw_policies(&self,names:&[String],admit:&mut dyn FnMut(usize)->io::Result<()>)->io::Result<bool>{
     if names.is_empty(){return Ok(false)}
     for name in names{let Some(meta)=dq_analyze::captured_raw_policy::metadata(name)else{return Ok(false)};if !dq_analyze::captured_raw_policy::RAW_FILE_LINTS.contains(&name.as_str())||!self.discovery.covers_dm_roots(meta.select.roots,true,admit)?{return Ok(false)}}Ok(true)
    }
    pub(crate) fn covers_code_dm(&self,admit:&mut dyn FnMut(usize)->io::Result<()>)->io::Result<bool>{self.discovery.covers_code_dm(admit)}
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
        self.page_needed(scope,start,count,budget,|relative|{
            let mut excluded=true;for scope in scopes{excluded &= scope.excludes_path(relative).map_err(io::Error::other)?;}Ok(!excluded)
        })
    }
    /// Policy-only CODE_DM input loan. No lint scope may suppress semantic
    /// marker/lexical work, and no raw tuple becomes a compiled source receipt.
    pub(crate) fn code_page(&self,scope:&crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,start:usize,count:usize,budget:usize)->io::Result<(Vec<crate::query_db::CurrentWorkspaceRawFile>,usize)>{
        self.page_needed(scope,start,count,budget,|relative|Ok(dq_analyze::captured_raw_file::is_code_dm(relative)))
    }
    pub(crate) fn generator_test_page(&self,scope:&crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,start:usize,count:usize,budget:usize)->io::Result<(Vec<crate::query_db::CurrentWorkspaceRawFile>,usize)>{
        self.page_needed(scope,start,count,budget,|relative|Ok(dq_analyze::captured_raw_file::is_generator_cli_test_source(relative)))
    }
    pub(crate) fn covers_hygiene(&self,admit:&mut dyn FnMut(usize)->io::Result<()>)->io::Result<bool>{self.discovery.covers_dm_roots(dq_analyze::captured_sys_hygiene_pages::selected_roots(),true,admit)}
    pub(crate) fn hygiene_page(&self,scope:&crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,start:usize,count:usize,budget:usize,configuration:&dq_analyze::captured_raw_file::Config,policy:&'static str,group:&'static str)->io::Result<(Vec<crate::query_db::CurrentWorkspaceRawFile>,usize)>{self.page_needed(scope,start,count,budget,|relative|Ok(dq_analyze::captured_sys_hygiene_pages::selects_path(relative)&&!configuration.policy_path_exempt(policy,group,relative)))}
    fn page_needed(&self,scope:&crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,start:usize,count:usize,budget:usize,mut needed:impl FnMut(&str)->io::Result<bool>)->io::Result<(Vec<crate::query_db::CurrentWorkspaceRawFile>,usize)>{
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
            let rel = relative_filesystem_path(&file.path, self.root())
                .ok_or_else(|| io::Error::other("workspace page path escapes root"))?
                .to_string_lossy()
                .replace('\\', "/");
            let excluded = !needed(&rel)?;
            let proof = match &file.original {
                Original::Native(native) => SourceProof::Native(
                    scope.original_identity(native.occurrence, &native.identity)?,
                ),
                Original::Owned(bytes) => SourceProof::Owned(Arc::downgrade(bytes.shared_owner())),
            };
            let mut own = BTreeMap::new();
            let text = if excluded {
                None
            } else {
                let original = self.original(index, scope)?;
                let raw = match &original {
                    RecordedSourceOriginal::Utf8(text) => text.as_bytes(),
                    RecordedSourceOriginal::Bytes(bytes) => bytes.as_slice(),
                };
                let length = dq_analyze::captured_raw_file::analyze_raw_len(raw)
                    .map_err(io::Error::other)?;
                let peak = if matches!(&original,RecordedSourceOriginal::Utf8(text) if !text.as_bytes().contains(&b'\r'))
                {
                    if let RecordedSourceOriginal::Utf8(text) = &original {
                        dq_analyze::captured_raw_file::visit_source_storage(text, |key, bytes| {
                            own.entry(key)
                                .and_modify(|old: &mut usize| *old = (*old).max(bytes))
                                .or_insert(bytes);
                        });
                    }
                    own.iter()
                        .filter(|(key, _)| !owners.contains_key(*key))
                        .try_fold(0usize, |n, (_, b)| n.checked_add(*b))
                        .ok_or_else(|| io::Error::other("workspace source capacity overflow"))?
                } else {
                    length
                        .checked_mul(4)
                        .and_then(|n| n.checked_add(8192))
                        .ok_or_else(|| io::Error::other("workspace normalization peak overflow"))?
                };
                if total
                    .checked_add(file.path.capacity())
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
                let text = crate::input_snapshot::normalize_recorded_policy_original(&original);
                own.clear();
                dq_analyze::captured_raw_file::visit_source_storage(&text, |key, bytes| {
                    own.entry(key)
                        .and_modify(|old: &mut usize| *old = (*old).max(bytes))
                        .or_insert(bytes);
                });
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
                .checked_add(file.path.capacity())
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
                path: file.path.clone(),
                text,
                proof,
                charge,
            });
            end = index + 1;
        }
        Ok((result, end))
    }
    pub(crate) fn facts(&self) -> &InputSnapshot {
        &self.facts
    }
    pub(crate) fn file_count(&self) -> usize {
        self.files.len()
    }
    pub(crate) fn path(&self, index: usize) -> io::Result<&Path> {
        self.files
            .get(index)
            .map(|file| file.path.as_path())
            .ok_or_else(|| io::Error::other("workspace file index unavailable"))
    }
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
            Original::Native(native) => scope.original(native.occurrence, &native.identity),
            Original::Owned(bytes) => Ok(RecordedSourceOriginal::Bytes(bytes)),
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
        let mut add = |bytes: usize| -> io::Result<()> {
            count = count
                .checked_add(bytes)
                .ok_or_else(|| io::Error::other("workspace capture overflow"))?;
            Ok(())
        };
        add(self.configuration.capacity())?;
        for file in &self.files {
            add(file.path.capacity())?;
            add(file.fact.path.capacity())?;
            match &file.original {
                Original::Native(native) => {
                    add(native.primary.path.capacity())?;
                    let mut metadata = 0;
                    native.identity.visit_storage(|v| {
                        if let dm_preprocess::source_acquisition::AcquisitionStorage::Object {
                            bytes,
                            ..
                        } = v
                        {
                            metadata = bytes.saturating_add(2 * std::mem::size_of::<usize>());
                        }
                    });
                    add(metadata)?;
                }
                Original::Owned(bytes) => {
                    let owner = bytes.shared_owner();
                    if seen.insert(Arc::as_ptr(owner) as usize) {
                        add(std::mem::size_of_val(owner.as_ref())
                            + 2 * std::mem::size_of::<usize>())?;
                        add(owner.bytes().capacity())?;
                    }
                }
            }
        }
        if let Some(bytes) = &self.config {
            let owner = bytes.shared_owner();
            if seen.insert(Arc::as_ptr(owner) as usize) {
                add(std::mem::size_of_val(owner.as_ref()) + 2 * std::mem::size_of::<usize>())?;
                add(owner.bytes().capacity())?;
            }
        }
        add(self.auxiliary.capacity()*std::mem::size_of::<crate::policy_request::WorkspaceAuxiliaryQuestion>())?;
        if let Some((path,bytes))=&self.deadline{add(path.capacity())?;if let Some(bytes)=bytes{let owner=bytes.shared_owner();if seen.insert(Arc::as_ptr(owner)as usize){add(std::mem::size_of_val(owner.as_ref())+2*std::mem::size_of::<usize>())?;add(owner.bytes().capacity())?;}}}
        // Shared directory arrays are charged by actual retained ownership, with
        // PathBuf capacities and conservative map-node allowance exposed below.
        add(self.discovery.retained_charge_with(&mut seen)?)?;
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
pub(crate) fn capture_with_auxiliary<P:SnapshotProvider>(frontend:&ColdFrontend,inputs:&RecordingInputs<P>,discovery:Arc<DiscoveryReceipt>,configuration:&Path,questions:&[crate::policy_request::WorkspaceAuxiliaryQuestion])->io::Result<Arc<WorkspaceCapture>>{
    if questions.len()>2||questions.windows(2).any(|pair|pair[0]>=pair[1]){return Err(io::Error::new(io::ErrorKind::InvalidInput,"actual canonical auxiliary questions required"))}
    discovery.validate_recording(inputs)?;
    if !configuration.is_absolute() {
        return Err(io::Error::other(
            "workspace configuration must be caller absolute",
        ));
    }
    let mapping = frontend
        .source_export_mapping()
        .ok_or_else(|| io::Error::other("workspace compiler mapping unproven"))?;
    let mut known = BTreeMap::new();
    for (index, occurrence) in frontend.plan.occurrences.iter().enumerate() {
        known.entry(occurrence.path.as_path()).or_insert(index);
    }
    let texts = frontend
        .files
        .iter()
        .filter(|file| file.captured)
        .map(|file| (file.path.as_path(), &file.text))
        .collect::<BTreeMap<_, _>>();
    // Reserve the COMPLETE metadata cohort before any extra original payload
    // read. A late final census must not hide an unbounded capture high-water.
    // This is conservative admission (not claimed allocator/RSS measurement).
    let mut used = discovery
        .retained_charge()?
        .checked_add(
            std::mem::size_of::<WorkspaceCapture>() + 2048 + configuration.as_os_str().len() * 4,
        )
        .ok_or_else(|| io::Error::other("workspace metadata overflow"))?;
    for path in discovery.files() {
        used = used
            .checked_add(2048 + path.capacity() * 8)
            .ok_or_else(|| io::Error::other("workspace metadata overflow"))?;
    }
    for path in known.keys() {
        // Include primary alias spelling capacity even if every source needs an
        // alias. This temporary conservative reserve is not retained storage.
        used = used
            .checked_add(path.as_os_str().len() * 2)
            .ok_or_else(|| io::Error::other("workspace primary metadata overflow"))?;
    }
    let alias_reserve = alias_index::AliasIndex::reserve_charge(known.keys().copied())?;
    used = used
        .checked_add(alias_reserve)
        .ok_or_else(|| io::Error::other("workspace alias metadata overflow"))?;
    if used > EXTRA_BUDGET {
        return Err(io::Error::other(
            "workspace metadata exceeds extra-owner bound before payload read",
        ));
    }
    let aliases = alias_index::AliasIndex::new(known.keys().copied(), alias_reserve)?;
    let mut files = Vec::with_capacity(discovery.files().len());
    for path in discovery.files() {
        crate::daemon::control::checkpoint()?;
        let original=capture_optional_original(inputs,mapping,&frontend.plan,&discovery,&known,&texts,&aliases,path,&mut used,0)?.ok_or_else(||io::Error::other("discovered source disappeared before capture"))?;
        files.push(File {
            path: path.clone(),
            fact: inputs.recorded_file_fact(path)?,
            original,
        });
    }
    let remaining = EXTRA_BUDGET
        .checked_sub(used)
        .ok_or_else(|| io::Error::other("workspace metadata leaves no config budget"))?;
    if discovery.files().iter().any(|path| path == configuration) {
        return Err(io::Error::other(
            "workspace configuration cannot also be a DM source",
        ));
    }
    let config = inputs.read_policy_candidate(configuration, remaining)?;
    let mut auxiliary=Vec::new();let mut deadline=None;let mut check_grep=None;let mut check_grep_paths:Option<[PathBuf;6]>=None;
    if !questions.is_empty(){
     used=used.checked_add(config.as_ref().map_or(0,SharedBytes::capacity)).and_then(|n|n.checked_add(4*questions.len()*std::mem::size_of::<crate::policy_request::WorkspaceAuxiliaryQuestion>())).and_then(|n|n.checked_add(128)).filter(|n|*n<=EXTRA_BUDGET).ok_or_else(||io::Error::new(io::ErrorKind::OutOfMemory,"auxiliary metadata overflow"))?;
     auxiliary.try_reserve_exact(questions.len()).map_err(|actual|io::Error::new(io::ErrorKind::OutOfMemory,actual))?;if auxiliary.capacity()>4*questions.len(){return Err(io::ErrorKind::OutOfMemory.into())}auxiliary.extend_from_slice(questions);
     if questions.contains(&crate::policy_request::WorkspaceAuxiliaryQuestion::DeadlinePollingAllowlist){
      let width=discovery.contract().root.as_os_str().len().checked_add("/tools/ci/deadline_polling_allowlist.txt".len()).and_then(|n|n.checked_mul(8)).and_then(|n|n.checked_add(2048)).ok_or(io::ErrorKind::OutOfMemory)?;
      used=used.checked_add(width).filter(|n|*n<=EXTRA_BUDGET).ok_or(io::ErrorKind::OutOfMemory)?;
      let path=discovery.contract().root.join("tools/ci/deadline_polling_allowlist.txt");
      let bytes=inputs.read_policy_candidate(&path,EXTRA_BUDGET-used)?;used=used.checked_add(bytes.as_ref().map_or(0,SharedBytes::capacity)).and_then(|n|n.checked_add(128)).filter(|n|*n<=EXTRA_BUDGET).ok_or(io::ErrorKind::OutOfMemory)?;deadline=Some((path,bytes));
     }
    }
    if questions.contains(&crate::policy_request::WorkspaceAuxiliaryQuestion::CheckGrep){
     discovery.check_grep_names()?;
     let path_width=discovery.contract().root.as_os_str().len().checked_add(128).and_then(|n|n.checked_mul(8)).and_then(|n|n.checked_add(2048)).and_then(|n|n.checked_mul(6)).ok_or(io::ErrorKind::OutOfMemory)?;
     let wanted=files.len().checked_add(6).ok_or(io::ErrorKind::OutOfMemory)?;let capacity=wanted.checked_mul(4).ok_or(io::ErrorKind::OutOfMemory)?;
     used=used.checked_add(path_width).and_then(|n|n.checked_add(capacity.checked_mul(std::mem::size_of::<File>())?)).filter(|n|*n<=EXTRA_BUDGET).ok_or(io::ErrorKind::OutOfMemory)?;
     let paths=std::array::from_fn(|index|discovery.contract().root.join(dq_analyze::lints::check_grep::native::Fixed::all()[index].relative()));
     files.try_reserve_exact(6).map_err(|error|io::Error::new(io::ErrorKind::OutOfMemory,error))?;if files.capacity()>capacity{return Err(io::Error::new(io::ErrorKind::OutOfMemory,"check_grep actual fixed-file capacity exceeds admission"))}
     let mut indices=[None;6];
     for(index,path)in paths.iter().enumerate(){crate::daemon::control::checkpoint()?;
      if let Some(existing)=files.iter().position(|file|file.path==*path){indices[index]=Some(existing);continue}
      if path==configuration{if let Some(bytes)=&config{indices[index]=Some(files.len());files.push(File{path:path.clone(),fact:inputs.recorded_file_fact(path)?,original:Original::Owned(bytes.clone())});}continue}
      if let Some(original)=capture_optional_original(inputs,mapping,&frontend.plan,&discovery,&known,&texts,&aliases,path,&mut used,128)?{indices[index]=Some(files.len());files.push(File{path:path.clone(),fact:inputs.recorded_file_fact(path)?,original});}
     }
     check_grep=Some(indices);check_grep_paths=Some(paths);
    }
    let selected = files
        .iter()
        .flat_map(|file| {
            let mut paths = vec![file.path.clone()];
            if let Original::Native(native) = &file.original {
                paths.push(native.primary.path.clone());
            }
            paths
        })
        .chain(std::iter::once(canonical_path(configuration)))
        .chain(deadline.iter().map(|(path,_)|canonical_path(path)))
        .chain(check_grep_paths.iter().flat_map(|paths|paths.iter().map(|path|canonical_path(path))))
        .collect();
    let facts = inputs.policy_workspace_closure(&selected, discovery.directory_paths())?;
    let policy_revision = crate::policy_request::workspace_revision(
        frontend.source_export_revision(),
        &facts,
        &discovery.contract().root,
        &discovery.contract().recursive_roots,
        &canonical_path(configuration),
    )?;
    let policy_revision=if auxiliary.is_empty(){policy_revision}else{let flags=[auxiliary.contains(&crate::policy_request::WorkspaceAuxiliaryQuestion::DeadlinePollingAllowlist),auxiliary.contains(&crate::policy_request::WorkspaceAuxiliaryQuestion::CheckGrep)];let mut hash=xxhash_rust::xxh3::Xxh3::new();hash.update(b"native-workspace-auxiliary-v1");hash.update(&policy_revision.to_le_bytes());hash.update(&[u8::from(flags[0]),u8::from(flags[1])]);hash.digest128()};
    static NEXT_ISSUANCE: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(1);
    let issuance = NEXT_ISSUANCE
        .fetch_update(
            std::sync::atomic::Ordering::Relaxed,
            std::sync::atomic::Ordering::Relaxed,
            |value| value.checked_add(1),
        )
        .map_err(|_| io::Error::other("workspace capture issuance exhausted"))?;
    let result = Arc::new(WorkspaceCapture {
        source: Arc::downgrade(mapping),
        source_revision: frontend.source_export_revision(),
        policy_revision,
        issuance,
        discovery,
        files: files.into_boxed_slice(),
        configuration: canonical_path(configuration),
        config,
        auxiliary,
        deadline,
        check_grep,
        facts,
    });
    if result.retained_charge()? > EXTRA_BUDGET {
        return Err(io::Error::other(
            "workspace capture exceeds existing64MiB extra-owner bound",
        ));
    }
    Ok(result)
}

/// SAME authenticated original selector for discovered files and explicitly
/// selected optional fixed questions; a missing result never supplies bytes.
fn capture_optional_original<P:SnapshotProvider>(inputs:&RecordingInputs<P>,mapping:&SourceExportMapping,plan:&dm_preprocess::regions::DirectivePlan,discovery:&DiscoveryReceipt,known:&BTreeMap<&Path,usize>,texts:&BTreeMap<&Path,&dm_preprocess::SourceText>,aliases:&alias_index::AliasIndex<'_>,path:&Path,used:&mut usize,backing_room:usize)->io::Result<Option<Original>>{
        let mut primary = path;
        if !known.contains_key(primary) {
            if let Some(candidate) = aliases.candidate(path)? {
                let text = texts
                    .get(candidate)
                    .ok_or_else(|| io::Error::other("native source text absent"))?;
                let proof = inputs
                    .acquire_source_alias(path, candidate, text)?
                    .ok_or_else(|| {
                        io::Error::other("workspace source alias contract unsupported")
                    })?;
                if proof.primary_path() != candidate {
                    return Err(io::Error::other("foreign workspace source alias proof"));
                }
                primary = candidate;
            }
        }
        let native_index=if let Some(index)=known.get(primary){
            let occurrence=plan.occurrences.get(*index).filter(|occurrence|occurrence.path.as_path()==primary).ok_or_else(||io::Error::other("workspace native occurrence join differs"))?;
            if occurrence.non_text_kind()==Some(dm_preprocess::regions::NonTextKind::Map)&&discovery.check_grep_names().is_ok(){None}else{Some(index)}
        }else{None};
        // Actual typed NonText maps have no text acquisition. The selected raw
        // role obtains their bytes through the SAME recorder candidate path;
        // every unexpected text None still takes the strict native lease guard.
        let original = if let Some(index) = native_index {
            let lease = mapping
                .source_acquisition(*index)
                .ok_or_else(|| io::Error::other("native original acquisition unavailable"))?;
            if !inputs.validate_source_lease(primary, lease) {
                return Err(io::Error::other(
                    "native original belongs to another recorder",
                ));
            }
            crate::input_snapshot::recorded_source_original(lease)?; // prove original-byte representation now
            Original::Native(Native {
                occurrence: *index,
                identity: lease.identity(),
                primary: inputs.recorded_file_fact(primary)?,
            })
        } else {
            let remaining = EXTRA_BUDGET
                .checked_sub(*used).and_then(|remaining|remaining.checked_sub(backing_room))
                .ok_or_else(|| io::Error::other("workspace extra-owner capture budget exceeded"))?;
            let Some(bytes)=inputs.read_policy_candidate(path,remaining)?else{return Ok(None)};
            *used = used
                .checked_add(bytes.capacity())
                .and_then(|n| n.checked_add(128))
                .ok_or_else(|| io::Error::other("workspace retained owner overflow"))?;
            Original::Owned(bytes)
        };
    Ok(Some(original))
}

//! Private recorder-issued Derived raw preflight. No hash/None source grants.
use super::*;
use std::sync::{Arc,Mutex,OnceLock};
use dq_analyze::{captured_generator_budget::Budget,captured_raw_file::{Config,RawPolicyViews},captured_raw_policy::Configuration,captured_reactive_reads::Failure,captured_derived_reads::UnsealedDerivedIndexData};
use dq_analyze::sem_handlers_partial_recipe::HandlerCodeFacts;
use crate::runner_host::workspace_discovery::{DiscoveryReceipt,DiscoveryContract};
fn operational(f:Failure)->io::Error{match f{Failure::Operational(e)=>e,Failure::Unsupported(m)=>io::Error::new(io::ErrorKind::Unsupported,m)}}
// Derived owns only CODE_DM. A selected report can also carry a separate
// parent inventory for map policies, without broadening this preflight.
fn derived_code_root(workspace: &crate::policy_request::WorkspacePolicyRequest) -> io::Result<PathBuf> {
    let code = workspace.root.join("code");
    let roots = workspace.recursive_roots.as_slice();
    if roots.first() != Some(&code)
        || !(roots.len() == 1 || (roots.len() == 2 && roots[1] == workspace.root.join("maps")))
    {
        return Err(invalid("Derived requires an exact CODE or CODE plus maps workspace"));
    }
    Ok(code)
}
fn pay(b:&Budget,bytes:Option<usize>)->io::Result<()>{let n=bytes.ok_or(io::ErrorKind::OutOfMemory)?;b.charge(n).map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))}
pub(crate) struct DerivedPreflight{
 // Payload precedes its actual operation funding. The host binds this owner,
 // never the unsealed DATA or a vector/hash supplied by a caller.
 index:Mutex<Option<UnsealedDerivedIndexData>>,facts:DerivedClosure,discovery:Arc<DiscoveryReceipt>,config:Arc<Config>,configuration:PathBuf,configuration_bytes:Option<dm_resources::SharedBytes>,issuer:Arc<()>,queries:crate::query_db::NativeQueryOwnerIdentity,subject_issuer:OnceLock<Arc<()>>,joined_registry:bool,handler_code:Vec<Option<HandlerCodeFacts>>,charge:usize,budget:Arc<Budget>,
}
enum DerivedClosure {
 Standalone(InputSnapshot),
 Joined(JoinedClosure),
}

struct JoinedClosure {
 files: Vec<JoinedFileFact>,
 configuration_missing: bool,
}

struct JoinedFileFact {
 ordinal: usize,
 stamp: Stamp,
 content: u128,
}

impl JoinedFileFact {
 const CONFIGURATION: usize = usize::MAX;

 fn path<'a>(&self, discovery: &'a DiscoveryReceipt, configuration: &'a Path) -> &'a Path {
  if self.ordinal == Self::CONFIGURATION { configuration }
  else { discovery.files()[self.ordinal].as_path() }
 }

 fn capture(ordinal: usize, path: &Path, file: &FileInput) -> io::Result<Self> {
  // The ordinary reader records this exact canonical key in both places.
  // Omit the redundant FileInput path only after checking it.
  if path.as_os_str() != file.path.as_os_str() {
   return Err(invalid("Derived ordinary file path differs from its discovery key"));
  }
  Ok(Self { ordinal, stamp: file.stamp.clone(), content: file.content })
 }

 fn matches(&self, path: &Path, file: &FileInput) -> bool {
  path.as_os_str() == file.path.as_os_str() && self.stamp == file.stamp && self.content == file.content
 }
}

impl JoinedClosure {
 fn capture(
  current: &InputSnapshot, discovery: &DiscoveryReceipt, configuration: &Path,
  selected: &[(usize, &Path)], budget: &Budget,
 ) -> io::Result<Self> {
  let config = current.files.get(configuration);
  let config_selected = selected.iter().any(|(_, path)| *path == configuration);
  let capacity = selected.len().checked_add(usize::from(config.is_some() && !config_selected))
   .ok_or(io::ErrorKind::OutOfMemory)?;
  pay(budget, capacity.checked_mul(std::mem::size_of::<JoinedFileFact>()))?;
  let mut files = Vec::new();
  files.try_reserve_exact(capacity).map_err(|error| io::Error::new(io::ErrorKind::OutOfMemory, error))?;
  if files.capacity() != capacity { return Err(io::ErrorKind::OutOfMemory.into()); }
  for &(ordinal, path) in selected {
   crate::daemon::control::checkpoint()?;
   if discovery.files().get(ordinal).is_none_or(|file| file.as_os_str() != path.as_os_str()) {
    return Err(invalid("Derived selected file lost its actual discovery ordinal"));
   }
   let file = current.files.get(path).ok_or_else(|| invalid("Derived selected CODE file lacks its recorded ordinary read"))?;
   files.push(JoinedFileFact::capture(ordinal, path, file)?);
  }
  if let Some(config) = config.filter(|_| !config_selected) {
   files.push(JoinedFileFact::capture(JoinedFileFact::CONFIGURATION, configuration, config)?);
  }
  let configuration_missing = config.is_none();
  if configuration_missing && !current.negative_files.contains(configuration) {
   return Err(invalid("Derived configuration has no recorded file or absence"));
  }
  // Preserve the old snapshot's ordinary path ordering at proof checks.
  files.sort_unstable_by(|left, right| left.path(discovery, configuration).cmp(right.path(discovery, configuration)));
  if files.windows(2).any(|row| row[0].path(discovery, configuration) == row[1].path(discovery, configuration)) {
   return Err(invalid("Derived selected CODE file repeats its canonical discovery path"));
  }
  Ok(Self { files, configuration_missing })
 }

 fn require_subset(&self, current: &InputSnapshot, discovery: &DiscoveryReceipt, configuration: &Path, directories: &BTreeMap<PathBuf, PolicyDirectoryObservation>) -> io::Result<()> {
  for row in &self.files {
   crate::daemon::control::checkpoint()?;
   let path = row.path(discovery, configuration);
   if !current.files.get(path).is_some_and(|file| row.matches(path, file)) {
    return Err(invalid("Derived actual preflight file fact changed"));
   }
  }
  if self.configuration_missing {
   crate::daemon::control::checkpoint()?;
   if current.files.contains_key(configuration) || !current.negative_files.contains(configuration) {
    return Err(invalid("Derived actual preflight negative changed"));
   }
  }
  for (path, fact) in discovery.policy_directories() {
   crate::daemon::control::checkpoint()?;
   if directories.get(path) != Some(fact) {
    return Err(invalid("Derived actual preflight typed directory changed"));
   }
  }
  Ok(())
 }

 fn retained_charge(&self) -> Option<usize> {
  self.files.capacity().checked_mul(std::mem::size_of::<JoinedFileFact>())
 }
}

impl DerivedPreflight{
 pub(crate) fn workspace_file_count(&self) -> usize {
  match &self.facts { DerivedClosure::Joined(facts) if self.joined_registry => facts.files.len(), _ => 0 }
 }
 pub(crate) fn workspace_files(&self) -> impl Iterator<Item = (&Path, &Stamp, u128)> {
  let files = match &self.facts { DerivedClosure::Joined(facts) if self.joined_registry => facts.files.as_slice(), _ => &[] };
  files.iter().map(move |row| (row.path(&self.discovery, &self.configuration), &row.stamp, row.content))
 }
 pub(crate) fn workspace_file(&self, path: &Path) -> Option<(&Path, &Stamp, u128)> {
  let DerivedClosure::Joined(facts) = &self.facts else { return None };
  if !self.joined_registry { return None; }
  let index = facts.files.binary_search_by(|row| row.path(&self.discovery, &self.configuration).cmp(path)).ok()?;
  let row = &facts.files[index];
  Some((row.path(&self.discovery, &self.configuration), &row.stamp, row.content))
 }
 pub(crate) fn workspace_missing_configuration(&self) -> Option<&Path> {
  let DerivedClosure::Joined(facts) = &self.facts else { return None };
  (self.joined_registry && facts.configuration_missing).then_some(self.configuration.as_path())
 }
 pub(crate) fn workspace_files_in(&self, current: &InputSnapshot) -> bool {
  self.workspace_files().all(|(path, stamp, content)| current.files.get(path).is_some_and(|file|
   file.path.as_os_str() == path.as_os_str() && &file.stamp == stamp && file.content == content))
 }
 // These two ordinary rosters may replace a copied Handler prefix only
 // after exact same-recorder, same-query and same-value checks by its issuer.
 pub(super) fn handler_prefix_donor<P:SnapshotProvider>(
  &self,inputs:&RecordingInputs<P>,queries:&crate::query_db::QueryDb,current:&InputSnapshot,
 )->bool{
  Arc::ptr_eq(&self.issuer,&inputs.source_issuer)&&self.queries.matches(queries)&&self.handler_prefix_matches(current)
 }
 pub(super) fn handler_prefix_matches(&self,current:&InputSnapshot)->bool{
  let DerivedClosure::Joined(facts)=&self.facts else{return false};
  self.joined_registry&&self.discovery.directories_in(current)
   && facts.files.iter().all(|row|{
    let path=row.path(&self.discovery,&self.configuration);
    current.files.get(path).is_some_and(|file|row.matches(path,file))
   })
 }
 pub(super) fn handler_prefix_contains_file(&self,path:&PathBuf,fact:&FileInput)->bool{
  let DerivedClosure::Joined(facts)=&self.facts else{return false};
  facts.files.binary_search_by(|row|row.path(&self.discovery,&self.configuration).cmp(path.as_path()))
   .is_ok_and(|index|facts.files[index].matches(path,fact))
 }
 pub(crate) fn require_bound_current(&self,subject:&OriginalAnalysisSubject,workspace:&Arc<crate::runner_host::workspace_capture::WorkspaceCapture>,scope:&crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,inputs:&dm_analysis::policy_inputs::PolicyInputs)->io::Result<()>{self.require_bound_frame(subject,workspace,scope,inputs)}
 pub(crate) fn take_bound_current(&self,subject:&OriginalAnalysisSubject,workspace:&Arc<crate::runner_host::workspace_capture::WorkspaceCapture>,scope:&crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,inputs:&dm_analysis::policy_inputs::PolicyInputs)->io::Result<Option<UnsealedDerivedIndexData>>{self.require_bound_current(subject,workspace,scope,inputs)?;Ok(self.index.lock().map_err(|_|invalid("Derived current index poisoned"))?.take())}
 pub(crate) fn require_configuration(&self,path:&Path,bytes:Option<&[u8]>)->io::Result<()>{if path!=self.configuration||bytes!=self.configuration_bytes.as_ref().map(|b|b.as_slice()){return Err(invalid("Derived actual current configuration differs from raw preflight"))}Ok(())}
 pub(crate) fn discovery(&self)->&Arc<DiscoveryReceipt>{&self.discovery}
 pub(crate) fn is_joined_registry(&self)->bool{self.joined_registry}
 pub(crate) fn configuration_bytes(&self)->Option<&dm_resources::SharedBytes>{self.configuration_bytes.as_ref()}
 pub(super) fn joined_configuration<P: SnapshotProvider>(
  &self, inputs: &RecordingInputs<P>, queries: &crate::query_db::QueryDb,
 ) -> io::Result<&Config> {
  if !self.joined_registry || !self.queries.matches(queries) {
   return Err(invalid("joined configuration requires its actual query owner"));
  }
  self.require_recording(inputs)?;
  Ok(&self.config)
 }

 pub(super) fn lend_handler_configuration<P: SnapshotProvider>(
  &self, inputs: &RecordingInputs<P>, queries: &crate::query_db::QueryDb,
  path: &Path, current: Option<&[u8]>,
 ) -> io::Result<(Option<dm_resources::SharedBytes>, Arc<Config>)> {
  if !self.joined_registry || !self.queries.matches(queries) {
   return Err(invalid("handler configuration requires the joined Derived query owner"));
  }
  self.require_recording(inputs)?;
  self.require_configuration(path, current)?;
  Ok((self.configuration_bytes.clone(), Arc::clone(&self.config)))
 }
 /// Borrow the actual roster and its per-file DATA together. Handler still
 /// performs its own exact bounded read before making a result visible.
 pub(super) fn handler_code_roster<'a,P:SnapshotProvider>(&'a self,inputs:&RecordingInputs<P>,queries:&crate::query_db::QueryDb,root:&Path)->io::Result<impl Iterator<Item=(&'a Path,Option<HandlerCodeFacts>)>+'a>{
  if !self.joined_registry||!self.queries.matches(queries)||root!=self.discovery.contract().root||self.handler_code.len()!=self.discovery.files().len(){
   return Err(invalid("handler CODE facts require their actual joined roster"));
  }
  self.require_recording(inputs)?;
  Ok(self.discovery.files().iter().map(PathBuf::as_path).zip(self.handler_code.iter().copied()))
 }
 pub(crate) fn account_shared_capture_aliases(&self, seen: &mut BTreeSet<usize>) -> io::Result<()> {
  self.discovery.retained_charge_with(seen)?;
  if let DerivedClosure::Standalone(facts)=&self.facts{facts.policy_closure_charge_with(seen)?;}
  if let Some(bytes)=&self.configuration_bytes{seen.insert(bytes.owner_address());}
  Ok(())
 }
 /// Dynamic resource bound only. The proof remains the sealed recorder owner.
 pub(crate) fn input_retained_charge(&self)->io::Result<usize>{let index=self.index.lock().map_err(|_|invalid("Derived preflight index poisoned during resource census"))?;self.charge.checked_add(match index.as_ref(){Some(data)=>data.retained_charge().ok_or(io::ErrorKind::OutOfMemory)?,None=>0}).ok_or_else(||io::ErrorKind::OutOfMemory.into())}
 fn require_subset(&self,current:&InputSnapshot)->io::Result<()> {
  self.require_subset_with_directories(current,current.policy_directories())
 }
 fn require_subset_with_directories(&self,current:&InputSnapshot,directories:&BTreeMap<PathBuf, PolicyDirectoryObservation>)->io::Result<()>{
  let facts=match &self.facts {
   DerivedClosure::Standalone(facts)=>facts,
   DerivedClosure::Joined(facts)=>return facts.require_subset(current,&self.discovery,&self.configuration,directories),
  };
  for(p,v)in &facts.files{crate::daemon::control::checkpoint()?;if current.files.get(p)!=Some(v){return Err(invalid("Derived actual preflight file fact changed"))}}
  for p in &facts.negative_files{crate::daemon::control::checkpoint()?;if !current.negative_files.contains(p){return Err(invalid("Derived actual preflight negative changed"))}}
  for(p,v)in &facts.policy_directories{crate::daemon::control::checkpoint()?;if directories.get(p)!=Some(v){return Err(invalid("Derived actual preflight typed directory changed"))}}Ok(())
 }
 pub(crate) fn require_recording<P:SnapshotProvider>(&self,inputs:&RecordingInputs<P>)->io::Result<()>{crate::daemon::control::checkpoint()?;if !Arc::ptr_eq(&self.issuer,&inputs.source_issuer){return Err(invalid("Derived preflight belongs to another actual recorder"))}self.discovery.validate_recording(inputs)?;let current=inputs.snapshot.lock().map_err(|_|invalid("Derived current recording poisoned"))?;self.require_subset(&current)}
 fn bind_subject<P:SnapshotProvider>(&self,inputs:&RecordingInputs<P>,subject:&Arc<OriginalAnalysisSubject>)->io::Result<()>{self.require_recording(inputs)?;if inputs.original_analysis_subject().is_none_or(|current|!Arc::ptr_eq(current,subject))||!subject.matches_workspace_root(&self.discovery.contract().root){return Err(invalid("Derived bind is not this recorder's actual full subject"))}pay(&self.budget,Some(2*std::mem::size_of::<usize>()))?;if self.subject_issuer.set(Arc::clone(subject.actual_subject_issuer())).is_err(){return Err(invalid("Derived preflight full subject was already bound"))}Ok(())}
 /// Validate the EXISTING parent binding. Retain no new mapping alias;
 /// actual source ownership and expiry remain with its original producer.
 pub(super) fn bind_mapping(&self,subject:&OriginalAnalysisSubject,mapping:&Arc<dm_tree::frontend::SourceExportMapping>)->io::Result<()>{self.require_subject(subject)?;subject.require_bound_mapping(mapping)}
 fn require_subject(&self,subject:&OriginalAnalysisSubject)->io::Result<()>{if self.subject_issuer.get().is_none_or(|owner|!Arc::ptr_eq(owner,subject.actual_subject_issuer()))||!subject.derived_preflight().is_ok_and(|p|std::ptr::eq(p,self)){return Err(invalid("Derived preflight has no actual issued full subject"))}Ok(())}
 fn require_bound_frame(&self,subject:&OriginalAnalysisSubject,workspace:&Arc<crate::runner_host::workspace_capture::WorkspaceCapture>,scope:&crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,inputs:&dm_analysis::policy_inputs::PolicyInputs)->io::Result<()>{crate::daemon::control::checkpoint()?;workspace.require_scope(scope)?;self.require_subject(subject)?;subject.require_bound_mapping(inputs.mapping())?;workspace.require_analysis_subject(subject)?;if !scope.uses_query_owner(&self.queries)||workspace.root()!=self.discovery.contract().root||!workspace.matches_auxiliary_questions(if self.joined_registry {
  crate::policy_request::WorkspaceAuxiliaryQuestion::PRIVATE_FULL_REGISTRY
 } else { &[crate::policy_request::WorkspaceAuxiliaryQuestion::DerivedReads] }){return Err(invalid("Derived bound mapping/current QueryDb/role/workspace differs"))}if !workspace.borrows_file_facts(self) {
  self.require_subset_with_directories(workspace.file_facts(),workspace.policy_directories())?;
 }self.budget.require().map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))}
 pub(crate) fn require_current(&self,subject:&OriginalAnalysisSubject,workspace:&Arc<crate::runner_host::workspace_capture::WorkspaceCapture>,scope:&crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,inputs:&dm_analysis::policy_inputs::PolicyInputs,queries:&crate::query_db::QueryDb)->io::Result<()>{self.require_subject(subject)?;subject.require_bound_mapping(inputs.mapping())?;workspace.require_analysis_subject(subject)?;if !scope.uses_queries(queries)||!self.queries.matches(queries){return Err(invalid("Derived actual current QueryDb owner differs"))}self.require_bound_frame(subject,workspace,scope,inputs)}
 pub(crate) fn take_current(&self,subject:&OriginalAnalysisSubject,workspace:&Arc<crate::runner_host::workspace_capture::WorkspaceCapture>,scope:&crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,inputs:&dm_analysis::policy_inputs::PolicyInputs,queries:&crate::query_db::QueryDb)->io::Result<Option<UnsealedDerivedIndexData>>{self.require_current(subject,workspace,scope,inputs,queries)?;Ok(self.index.lock().map_err(|_|invalid("Derived preflight index poisoned"))?.take())}
 pub(crate) fn census(self:&Arc<Self>,census:&mut crate::heap_census::HeapCensus){let owner="query_snapshot.derived_preflight";if !census.arc_object(owner,self){return}self.discovery.census(census);match &self.facts{DerivedClosure::Standalone(facts)=>census.workspace_policy_facts(facts),DerivedClosure::Joined(facts)=>{census.vec_payload(owner,&facts.files);},}census.path(owner,&self.configuration);census.arc_object(owner,&self.issuer);census.arc_object(owner,&self.config);if let Some(issuer)=self.subject_issuer.get(){census.arc_object(owner,issuer);}self.queries.visit_storage(|pointer,logical,capacity|{census.exposed_buffer("query_snapshot.derived_query_counter",pointer,logical,capacity);});if let Some(bytes)=&self.configuration_bytes{if census.shared_bytes_owner(owner, bytes){census.vec_payload(owner,bytes.shared_owner().bytes());}}census.unknown(owner,"private raw identifier index BTree nodes, retained source Budget parent chain and interpreted Config backing are not exposed; admission bounds are not reported as heap bytes");}
}
impl<P:SnapshotProvider> RecordingInputs<P>{
 fn read_derived_configuration(&self, path: &Path, budget: &Arc<Budget>, joined: bool)
  -> io::Result<(Option<dm_resources::SharedBytes>, Arc<Config>)>
 {
  // The raw read and full TOML parse still need the old peak envelope.
  let scratch=Budget::scoped_temporaries(budget).map_err(io::Error::other)?;
  let bytes=self.read_policy_vec_admitted(path,budget.remaining(),&mut|length|
   pay(&scratch,length.checked_mul(64).and_then(|size|size.checked_add(8192))))?;
  let config=Config::capture(bytes.as_ref().map_or(Configuration::ProvenMissing,|bytes|
   Configuration::Captured(bytes.as_slice()))).map_err(io::Error::other)?;
  let scope_bound=if joined {config.retained_scope_bound()} else {None}
   .unwrap_or_else(||config.budget_charge());
  let backing=bytes.as_ref().map_or(0,Vec::capacity);
  pay(budget,scope_bound.checked_add(backing).and_then(|size|size.checked_add(8192)))?;
  Ok((bytes.map(dm_resources::SharedBytes::from),Arc::new(config)))
 }

 /// Closed cold purpose. This performs selected raw schema before manifest,
 /// native frontend, Globals or BODY. Later full subject binding is separate.
 pub(crate) fn issue_derived_preflight_using(&self,intent:&crate::policy_request::AdmittedPolicyRequest,queries:&Arc<crate::query_db::QueryDb>,budget:&Arc<Budget>,lender:&mut dyn super::RecordedPolicySourceLender)->io::Result<Arc<DerivedPreflight>>{
  use crate::policy_request::{AnalysisContext,WorkspaceAuxiliaryQuestion as Q};let joined_registry=intent.workspace_auxiliary()==Q::PRIVATE_FULL_REGISTRY;if self.analysis_subject.is_some()||self.initial_environment!=dm_preprocess::InitialEnvironment::OriginalChecker0290||intent.analysis_context()!=Some(AnalysisContext::OriginalAnalyze0290)||(!joined_registry&&intent.workspace_auxiliary()!=[Q::DerivedReads])||!intent.workspace_generators().is_empty()||!intent.files().is_empty()||!intent.search_folders().is_empty(){return Err(invalid("Derived cold preflight requires its exact unissued Original purpose"))}let workspace=intent.workspace().ok_or_else(||invalid("Derived workspace absent"))?;let code=if joined_registry{workspace.root.join("code")}else{derived_code_root(workspace)?};
  let trace = cfg!(debug_assertions) && std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some();
  let mark = |stage, files| {
   if trace {
    eprintln!("original derived preflight stage={stage} files={files} used={} remaining={}", budget.used(), budget.remaining());
   }
  };
  let configuration = canonical_path(&workspace.configuration);
  let (bytes, config)=self.read_derived_configuration(&configuration,budget,joined_registry)?;
  mark("configuration", 0);
  let discovery=Arc::new(if joined_registry {
   crate::runner_host::workspace_discovery::discover_full_registry_from_derived(self,
    DiscoveryContract{root:workspace.root.clone(),recursive_roots:workspace.recursive_roots.clone()},
    &configuration,&config,budget,lender)?
  } else {
   crate::runner_host::workspace_discovery::discover_ownership_code_admitted(self,
    DiscoveryContract{root:workspace.root.clone(),recursive_roots:vec![code]},budget,lender)?
  });discovery.validate_recording(self)?;if !discovery.covers_code_dm(&mut|n|pay(budget,Some(n)))?{return Err(invalid("Derived preflight lacks actual complete CODE discovery"))}
  mark("discovery", discovery.files().len());
  let selected = {
   // Discovery already sorts by the normalized relative spelling. Retain
   // only path references, while reusing one admitted conversion envelope.
   let scratch = Budget::scoped_temporaries(budget).map_err(io::Error::other)?;
   let width = discovery.files().iter().map(|path| path.as_os_str().len()).max().unwrap_or(0);
   pay(&scratch, width.checked_mul(8).and_then(|size| size.checked_add(512)))?;
   let capacity = discovery.files().len();
   pay(budget, capacity.checked_mul(std::mem::size_of::<(usize,&Path)>()))?;
   let mut selected = Vec::new();
   selected.try_reserve_exact(capacity).map_err(|error| io::Error::new(io::ErrorKind::OutOfMemory, error))?;
   if selected.capacity() != capacity { return Err(io::ErrorKind::OutOfMemory.into()); }
   for (ordinal,path) in discovery.files().iter().enumerate() {
    crate::daemon::control::checkpoint()?;
    let relative = path.strip_prefix(&workspace.root).map_err(|_| invalid("Derived preflight path escapes actual root"))?;
    let rel = relative.to_string_lossy().replace('\\', "/");
    if dq_analyze::captured_raw_file::is_code_dm(&rel)
     && !config.policy_path_exempt("derived_reads", dq_analyze::captured_derived_reads::metadata().group, &rel) {
     selected.push((ordinal,path.as_path()));
    }
   }
   selected
  };
  struct Pages<'a,P>{inputs:&'a RecordingInputs<P>,root:&'a Path,selected:&'a[(usize,&'a Path)],current:std::cell::Cell<usize>,budget:&'a Arc<Budget>,lender:std::cell::RefCell<&'a mut dyn super::RecordedPolicySourceLender>,ended:std::cell::Cell<bool>}
  impl<P:SnapshotProvider> dq_analyze::reactive_raw_policy_pages::RawPolicyPages for Pages<'_,P>{fn for_each(&self,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{if self.ended.get(){return Err("Derived cold raw model phase repeated".into())}for &(ordinal,path) in self.selected{crate::daemon::control::checkpoint()?;self.current.set(ordinal);if !self.inputs.with_recorded_policy_file_code_using(self.root,path,self.budget,&mut **self.lender.borrow_mut(),visit)?{return Ok(false)}}self.ended.set(true);Ok(true)}}
  mark("selection", selected.len());
  let mut handler_code=Vec::new();
  if joined_registry{
   let count=discovery.files().len();
   pay(budget,count.checked_mul(std::mem::size_of::<Option<HandlerCodeFacts>>()))?;
   handler_code.try_reserve_exact(count).map_err(|error|io::Error::new(io::ErrorKind::OutOfMemory,error))?;
   if handler_code.capacity()!=count{return Err(io::ErrorKind::OutOfMemory.into())}
   handler_code.resize(count,None);
  }
  let pages=Pages{inputs:self,root:&workspace.root,selected:&selected,current:std::cell::Cell::new(usize::MAX),budget,lender:std::cell::RefCell::new(lender),ended:false.into()};
  let index=if joined_registry{
   dq_analyze::captured_derived_reads::prepare_selected_pages_with_code(&pages,budget,&crate::daemon::control::checkpoint,&mut|relative,code|{
    let slot=handler_code.get_mut(pages.current.get()).ok_or_else(||Failure::from("Derived file has no actual handler ordinal"))?;
    if let Some(code)=code{
     if !config.policy_path_exempt("sem/handlers",dq_analyze::sem_handlers_policy::metadata().group,relative){
      *slot=Some(HandlerCodeFacts::classify(relative,code.text.as_str()));
     }
    }
    Ok(())
   })
  }else{dq_analyze::captured_derived_reads::prepare_selected_pages(&pages,budget,&crate::daemon::control::checkpoint)}.map_err(operational)?;
  if !pages.ended.get(){return Err(invalid("Derived preflight did not exhaust actual selected source"))}discovery.validate_recording(self)?;
  mark("schema", selected.len());
  // Preadmit exact path capacities and a conservative SAME-recording closure
  // bound before cloning any file/directory metadata, not selected_count*1024.
  let facts = if joined_registry {
   let current=self.snapshot.lock().map_err(|_|invalid("Derived recording mutex poisoned"))?;
   DerivedClosure::Joined(JoinedClosure::capture(&current,&discovery,&configuration,&selected,budget)?)
  }else{
   let mut paths=BTreeSet::new();pay(budget,Some(128))?;
   for &(_,path) in &selected{pay(budget,path.as_os_str().len().checked_mul(4).and_then(|n|n.checked_add(128)))?;}
   pay(budget,configuration.capacity().checked_add(128))?;
   {let current=self.snapshot.lock().map_err(|_|invalid("Derived recording mutex poisoned"))?;pay(budget,Some(current.policy_closure_charge()?))?;}
   for &(_,path) in &selected{paths.insert(path.to_path_buf());}paths.insert(configuration.clone());
   DerivedClosure::Standalone(self.policy_workspace_closure(&paths,discovery.directory_paths())?)
  };
  mark("closure", selected.len());
  let mut seen=BTreeSet::new();
  let charge=Some(std::mem::size_of::<DerivedPreflight>()+std::mem::size_of::<Budget>()+4*std::mem::size_of::<usize>()+crate::query_db::NativeQueryOwnerIdentity::retained_charge()).and_then(|n|n.checked_add(if joined_registry{0}else{config.budget_charge()})).and_then(|n|n.checked_add(bytes.as_ref().map_or(0,|bytes|bytes.capacity()+std::mem::size_of::<dm_resources::SharedBytesOwner>()+2*std::mem::size_of::<usize>()))).and_then(|n|n.checked_add(handler_code.capacity().checked_mul(std::mem::size_of::<Option<HandlerCodeFacts>>())?)).and_then(|n|n.checked_add(configuration.capacity())).and_then(|n|n.checked_add(discovery.retained_charge_with(&mut seen).ok()?)).and_then(|n|n.checked_add(match &facts{DerivedClosure::Standalone(facts)=>facts.policy_closure_charge_with(&mut seen).ok()?,DerivedClosure::Joined(facts)=>facts.retained_charge()?,})).ok_or(io::ErrorKind::OutOfMemory)?;
  pay(budget,Some(crate::query_db::NativeQueryOwnerIdentity::retained_charge()+std::mem::size_of::<DerivedPreflight>()+2*std::mem::size_of::<usize>()))?;let owner=Arc::new(DerivedPreflight{index:Mutex::new(Some(index)),facts,discovery,config,configuration,configuration_bytes:bytes,issuer:Arc::clone(&self.source_issuer),queries:queries.native_query_owner_identity(),subject_issuer:OnceLock::new(),joined_registry,handler_code,charge,budget:Arc::clone(budget)});owner.require_recording(self)?;Ok(owner)
 }
 pub(crate) fn issue_original_analysis_subject_derived(&mut self,intent:&crate::policy_request::AdmittedPolicyRequest,preflight:Arc<DerivedPreflight>)->io::Result<Arc<OriginalAnalysisSubject>>{if preflight.is_joined_registry(){
  let subject=self.issue_original_analysis_subject_full_registry(intent,&preflight)?;
  preflight.bind_subject(self,&subject)?;subject.install_derived_preflight(preflight)?;return Ok(subject)
 }if intent.workspace_auxiliary()!=[crate::policy_request::WorkspaceAuxiliaryQuestion::DerivedReads]{return Err(invalid("Derived raw preflight cannot bind another selected purpose"))}preflight.require_recording(self)?;let workspace=intent.workspace().ok_or_else(||invalid("Derived subject workspace absent"))?;let code=derived_code_root(workspace)?;if workspace.root!=preflight.discovery.contract().root||preflight.discovery.contract().recursive_roots.as_slice()!=[code]||canonical_path(&workspace.configuration)!=preflight.configuration{return Err(invalid("Derived subject intent differs from actual raw preflight namespace"))}let subject=self.issue_original_analysis_subject(intent)?;preflight.bind_subject(self,&subject)?;subject.install_derived_preflight(preflight)?;Ok(subject)}
}

#[cfg(test)]mod controls{
 use super::*;
 pub(super) fn intent(root:&Path)->crate::policy_request::AdmittedPolicyRequest{crate::policy_request::PolicyInputRequest{analysis_context:Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290),workspace:Some(crate::policy_request::WorkspacePolicyRequest{root:root.to_path_buf(),recursive_roots:vec![root.join("code")],configuration:root.join("tools/ci/lint_scopes.toml")}),workspace_auxiliary:vec![crate::policy_request::WorkspaceAuxiliaryQuestion::DerivedReads],..Default::default()}.admit().unwrap()}
 #[test]fn actual_derived_preflight_finishes_raw_before_hostile_manifest_and_has_no_model_or_public_binding(){let root=crate::test_scratch::dir("derived-real-cold-preflight");std::fs::create_dir_all(root.join("code")).unwrap();std::fs::write(root.join("deepquarry.dme"),"#include \"unterminated\n").unwrap();let code=root.join("code/a.dm");std::fs::write(&code,"/datum/probe\n    var/value\n/datum/probe/derived()\n    return list(drawn_from(nameof(value)))\n/datum/probe/broken()\n    ) : \"bad body\n").unwrap();let mut inputs=RecordingInputs::new(FileSystemInputs,0).with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);let queries=Arc::new(crate::query_db::QueryDb::default());let budget=Budget::new(32*1024*1024).unwrap();let selected=intent(&root);let owner=queries.prepare_derived_preflight(&inputs,&selected).unwrap();assert!(owner.index.lock().unwrap().is_some());assert!(inputs.original_analysis_subject().is_none());assert!(inputs.source_acquisitions.lock().unwrap().is_empty(),"raw index cannot invoke native PreparedSource or parse bad BODY");assert!(inputs.recorded_file_fact(&code).is_ok());let wrong=RecordingInputs::new(FileSystemInputs,0).with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);assert!(owner.require_recording(&wrong).is_err(),"equal root/text cannot replace actual recorder");assert!(inputs.recorded_file_fact(&root.join("deepquarry.dme")).is_err(),"raw model phase must precede even opening the actual project");let subject=inputs.issue_original_analysis_subject_derived(&selected,Arc::clone(&owner)).unwrap();assert!(std::ptr::eq(subject.derived_preflight().unwrap(),owner.as_ref()));assert!(inputs.source_acquisitions.lock().unwrap().is_empty(),"metadata issuance alone prepares no semantic source");}

 #[cfg(windows)]
 #[test]
 fn actual_original_verbatim_primary_needs_a_receipt_donor_under_low_local_limit() {
  use crate::policy_request::{AnalysisContext,PolicyInputRequest,WorkspaceAuxiliaryQuestion as Q,WorkspacePolicyRequest};
  use dm_tree::frontend::{self,FrontendConfig,SettingExpressionQueries};
  let root=crate::test_scratch::dir("actual-native-primary-closure-spellings");
  std::fs::create_dir_all(root.join("code")).unwrap();
  let discovered=root.join("code/a.dm");
  std::fs::write(&discovered,br##"/datum/probe
    var/value=1
"##).unwrap();
  let project=root.join("deepquarry.dme");
  std::fs::write(&project,br##"#include "code/a.dm"
"##).unwrap();
  let request=PolicyInputRequest{
   analysis_context:Some(AnalysisContext::OriginalAnalyze0290),
   workspace:Some(WorkspacePolicyRequest{
    root:root.clone(),configuration:root.join("tools/ci/lint_scopes.toml"),
    recursive_roots:Q::authored_doc_ui_roots(Q::PRIVATE_FULL_REGISTRY).unwrap().iter().map(|name|root.join(name)).collect(),
   }),workspace_auxiliary:Q::PRIVATE_FULL_REGISTRY.to_vec(),..Default::default()
  }.admit_private_authored_doc_ui().unwrap();
  let inputs=RecordingInputs::new(FileSystemInputs,0)
   .with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);
  let queries=Arc::new(crate::query_db::QueryDb::default());
  let donor=queries.prepare_derived_preflight(&inputs,&request).unwrap();
  let primary=std::fs::canonicalize(&discovered).unwrap();
  assert_ne!(primary,discovered,"fixture requires distinct DOS and verbatim Path keys");
  assert!(dm_preprocess::regions::relative_filesystem_path(&primary,&discovered)
   .is_some_and(|path|path.as_os_str().is_empty()));
  // This is a separate real bounded read, as performed by the native
  // prescan. No forged ordinary fact or opened-source receipt is inserted.
  inputs.read_policy_candidate(&primary,1<<20).unwrap().unwrap();
  let executor=dm_exec::BuildExecutor::new(1).unwrap();
  let seed=dm_tree::checker_builtins::original_analysis_seed().unwrap();
  let host=Arc::clone(&queries) as Arc<dyn SettingExpressionQueries>;
  let provider=inputs.original_batch_view(None);
  let front=frontend::build_for_original_analysis_with_state_checked(
   &std::fs::canonicalize(&project).unwrap(),&provider,&BTreeMap::new(),
   FrontendConfig{workers:1,engine:Some(seed.frontend_seed()),observer:None},
   None,&executor,None,&host,
  ).unwrap();
  let view=front.source_view().unwrap();
  let (occurrence,actual)=view.semantic_includes().find(|(_,path)|path.as_path()==primary).unwrap();
  assert_eq!(actual.as_os_str(),primary.as_os_str());
  let fact=inputs.mapped_recorded_source_fact(view.mapping(),occurrence,&primary).unwrap();
  let ordinary=inputs.recorded_file_fact(&primary).unwrap();
  assert_eq!(fact.stamp,ordinary.stamp);
  assert_eq!(fact.content,ordinary.content);
  assert!(donor.workspace_file(&discovered).is_some());
  assert!(donor.workspace_file(&primary).is_none());
  let mut selected=[(discovered.as_path(),0),(primary.as_path(),1),(donor.configuration.as_path(),2)];
  selected.sort_unstable();
  let local_limit=2048+8*donor.configuration.as_os_str().len();
  let failure=inputs.policy_workspace_joined_files_hashed(
   &selected,&donor.discovery,&donor,local_limit,7,&donor.configuration,|_,_|Ok(false),
  ).unwrap_err();
  assert_eq!(failure.kind(),io::ErrorKind::OutOfMemory);
  let (copied,hash)=inputs.policy_workspace_joined_files_hashed(
   &selected,&donor.discovery,&donor,1<<20,7,&donor.configuration,|_,_|Ok(false),
  ).unwrap();
  assert_eq!(copied.files.len(),1,"only the verbatim primary is duplicated");
  let legacy=inputs.policy_workspace_joined_files(
   selected.iter().map(|&(path,_)|path),&donor.discovery,
  ).unwrap();
  assert_eq!(hash,crate::policy_request::workspace_revision_with_directories(
   7,&legacy,donor.discovery.policy_directories(),&root,
   &donor.discovery.contract().recursive_roots,&donor.configuration,
  ).unwrap());
  let borrowed = |path:&Path, fact:&FileInput, current:&InputSnapshot| {
   if path != primary { return Ok(false); }
   let issued = inputs.mapped_original_source_fact_in(view.mapping(),occurrence,path,current)?;
   Ok(issued == fact)
  };
  let (loaned,loaned_hash)=inputs.policy_workspace_joined_files_hashed_current(
   &selected,&donor.discovery,&donor,local_limit,7,&donor.configuration,borrowed,
  ).unwrap();
  assert!(loaned.files.is_empty(),"both source facts already have authenticated owners");
  assert_eq!(loaned_hash,hash,"borrowed serialization keeps the selected keys and actual recorder values");
  let current=inputs.snapshot().unwrap();
  assert_eq!(inputs.mapped_original_source_fact_in(view.mapping(),occurrence,&primary,&current).unwrap(),&ordinary);
  let mut changed=current.clone();
  changed.files.get_mut(&primary).unwrap().content ^= 1;
  assert!(inputs.mapped_original_source_fact_in(view.mapping(),occurrence,&primary,&changed).is_err());
  let mut missing_current=current.clone();
  missing_current.files.remove(&primary);
  assert!(crate::input_snapshot::recorded_original_source_fact_in(
   view.mapping(),occurrence,&missing_current,
  ).is_err(),"final freshness needs the same actual ordinary fact");
  let mut missing=[(primary.as_path(),1),(donor.configuration.as_path(),2)];
  missing.sort_unstable();
  let omitted=inputs.policy_workspace_joined_files_hashed_current(
   &missing,&donor.discovery,&donor,local_limit,7,&donor.configuration,borrowed,
  ).unwrap_err();
  assert!(omitted.to_string().contains("every donated file fact"),
   "the native donor cannot replace the missing discovered donor obligation: {omitted}");
  let foreign=RecordingInputs::new(FileSystemInputs,0)
   .with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);
  foreign.read_policy_candidate(&primary,1<<20).unwrap().unwrap();
  assert!(foreign.mapped_original_source_fact_in(view.mapping(),occurrence,&primary,&current).is_err(),
   "an equal ordinary file fact cannot transfer the recorder's private opened receipt");
  let foreign_provider=foreign.original_batch_view(None);
  let foreign_front=frontend::build_for_original_analysis_with_state_checked(
   &std::fs::canonicalize(&project).unwrap(),&foreign_provider,&BTreeMap::new(),
   FrontendConfig{workers:1,engine:Some(seed.frontend_seed()),observer:None},
   None,&executor,None,&host,
  ).unwrap();
  let foreign_view=foreign_front.source_view().unwrap();
  let (foreign_occurrence,_)=foreign_view.semantic_includes()
   .find(|(_,path)|path.as_path()==primary).unwrap();
  let foreign_current=foreign.snapshot().unwrap();
  assert_eq!(foreign.mapped_original_source_fact_in(
   foreign_view.mapping(),foreign_occurrence,&primary,&foreign_current,
  ).unwrap(),foreign_current.files.get(&primary).unwrap(),
   "the foreign control must first authenticate its own actual opened receipt");
  assert!(inputs.mapped_original_source_fact_in(
   foreign_view.mapping(),foreign_occurrence,&primary,&foreign_current,
  ).is_err(),"a valid same-config native mapping still belongs to its actual recorder");
  assert!(inputs.mapped_original_source_fact_in(view.mapping(),usize::MAX,&primary,&current).is_err());
  let (root_ordinal,_)=view.semantic_includes().find(|(_,path)|path.file_name()==project.file_name()).unwrap();
  assert!(inputs.mapped_original_source_fact_in(view.mapping(),root_ordinal,&primary,&current).is_err());
  drop(foreign_view);drop(foreign_front);drop(foreign_provider);drop(foreign);
  let alias= view.mapping().source_acquisition(occurrence).unwrap().clone();  let mapping=Arc::downgrade(view.mapping());
  // No retained semantic state or body query was issued in this fixture.
  // The view and fact loans are borrowed; front owns both ColdFrontend's
  // mapping and BodyArchive's mapping. The detached receipt owns neither.
  drop(view);drop(front);drop(provider);
  assert!(mapping.upgrade().is_none(),"the receipt alias does not keep the mapping alive");
  assert_eq!(dm_preprocess::SourceProvider::original_source_bytes(&inputs,&alias).unwrap().unwrap(),
   b"/datum/probe
    var/value=1
");
 }

 #[test]fn joined_derived_ordinal_proof_preserves_actual_file_config_and_directory_facts(){
  use crate::policy_request::WorkspaceAuxiliaryQuestion as Q;
  let root=crate::test_scratch::dir("derived-real-joined-ordinals");
  std::fs::create_dir_all(root.join("code")).unwrap();
  let source=root.join("code/a.dm");
  std::fs::write(&source,"/datum/probe\n    var/value\n").unwrap();
  let request=crate::policy_request::PolicyInputRequest{
   analysis_context:Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290),
   workspace:Some(crate::policy_request::WorkspacePolicyRequest{
    root:root.clone(),
    recursive_roots:Q::authored_doc_ui_roots(Q::PRIVATE_FULL_REGISTRY).unwrap().iter().map(|name|root.join(name)).collect(),
    configuration:root.join("tools/ci/lint_scopes.toml"),
   }),
   workspace_auxiliary:Q::PRIVATE_FULL_REGISTRY.to_vec(), ..Default::default()
  };
  let request=request.admit_private_authored_doc_ui().unwrap();
  let inputs=RecordingInputs::new(FileSystemInputs,0).with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);
  let queries=Arc::new(crate::query_db::QueryDb::default());
  let owner=queries.prepare_derived_preflight(&inputs,&request).unwrap();
  let DerivedClosure::Joined(closure)=&owner.facts else {panic!("actual joined capture must seal ordinal rows")};
  assert!(closure.configuration_missing);
  assert_eq!(closure.files.len(),1);
  let fixed = root.join("fixed.txt");
  std::fs::write(&fixed, b"actual fixed workspace file").unwrap();
  inputs.read_policy_candidate(&fixed, 4096).unwrap();
  let mut chosen = [canonical_path(&source), canonical_path(&fixed), owner.configuration.clone()];
  chosen.sort();
  let full = inputs.policy_workspace_joined_files(chosen.iter().map(PathBuf::as_path), &owner.discovery).unwrap();
  let compact = inputs.policy_workspace_joined_files_using(
   chosen.iter().map(PathBuf::as_path), &owner.discovery, Some(&owner),
  ).unwrap();
  // Equivalent Path ordering with byte-distinct input spelling. The first
  // selected key is serialized verbatim, but its value is the recorder's.
  let alternative = root.join("code").join(".").join(source.file_name().unwrap());
  let canonical_source = canonical_path(&source);
  assert_eq!(alternative, canonical_source);
  assert_ne!(alternative.as_os_str(), canonical_source.as_os_str());
  let mut selected: Vec<_> = [&alternative, &canonical_source, &owner.configuration]
   .into_iter().enumerate().map(|(ordinal, path)| (path.as_path(), ordinal)).collect();
  selected.sort_unstable();
  selected.dedup_by(|later, earlier| later.0 == earlier.0);
  assert!(selected.iter().any(|(path, _)| path.as_os_str()==alternative.as_os_str()));
  // Raw's current nonhashed donor mode rejects an otherwise unchanged
  // recorder fact when only the selected key has an equivalent spelling.
  // Assert each comparison independently: this is not a stale-state or
  // different-content control, and no donor label is rewritten to pass.
  let selected_source=selected.iter().find(|(path,_)|*path==canonical_source).unwrap().0;
  let (donated_path,donated_stamp,donated_content)=owner.workspace_file(selected_source).unwrap();
  let recorded=inputs.recorded_file_fact(selected_source).unwrap();
  assert_ne!(selected_source.as_os_str(),donated_path.as_os_str());
  assert_eq!(recorded.path.as_os_str(),donated_path.as_os_str());
  assert_eq!(&recorded.stamp,donated_stamp);
  assert_eq!(recorded.content,donated_content);
  let raw_key_refusal=inputs.policy_workspace_joined_files_using(
   selected.iter().map(|&(path,_)|path),&owner.discovery,Some(&owner),
  ).unwrap_err();
  assert_eq!(raw_key_refusal.kind(),io::ErrorKind::InvalidData);
  assert_eq!(raw_key_refusal.to_string(),"workspace file donor differs from the recorded selected fact");
  let legacy = inputs.policy_workspace_joined_files(
   selected.iter().map(|&(path, _)| path), &owner.discovery,
  ).unwrap();
  let (_, actual_hash) = inputs.policy_workspace_joined_files_hashed(
   &selected, &owner.discovery, &owner, 1 << 20, 7, &owner.configuration, |_, _| Ok(false),
  ).unwrap();
  assert_eq!(actual_hash, crate::policy_request::workspace_revision_with_directories(
   7, &legacy, owner.discovery.policy_directories(), &root,
   &owner.discovery.contract().recursive_roots, &owner.configuration,
  ).unwrap());
  assert_eq!(full.files().count(), 2);
  assert_eq!(compact.files().count(), 1);
  let local = compact.recorded_canonical_file(&canonical_path(&fixed)).unwrap();
  let positive = 2048 + 8 * local.path.capacity().max(local.path.as_os_str().len());
  let negative = 2048 + 8 * owner.configuration.as_os_str().len();
  // A zero allowance cannot copy local facts. A window for exactly the
  // local positive and missing configuration needs no room for the donor.
  let select = || chosen.iter().map(PathBuf::as_path);
  let failure = inputs.policy_workspace_joined_files_with_limit(
   select(), &owner.discovery, Some(&owner), Some(0),
  ).unwrap_err();
  assert_eq!(failure.kind(), io::ErrorKind::OutOfMemory);
  let exact = inputs.policy_workspace_joined_files_with_limit(
   select(), &owner.discovery, Some(&owner), Some(positive + negative),
  ).unwrap();
  assert_eq!(exact.files().count(), 1);
  assert!(compact.recorded_canonical_file(&canonical_path(&fixed)).is_some());
  let roots = &owner.discovery.contract().recursive_roots;
  let dirs = owner.discovery.policy_directories();
  assert_eq!(
   crate::policy_request::workspace_revision_with_directories(7, &full, dirs, &root, roots, &owner.configuration).unwrap(),
   crate::policy_request::workspace_revision_with_file_donor(7, &compact, dirs, Some(&owner), &root, roots, &owner.configuration).unwrap(),
  );
  assert!(inputs.policy_workspace_joined_files_using(
   std::iter::once(owner.configuration.as_path()), &owner.discovery, Some(&owner),
  ).is_err());
  let current=inputs.snapshot.lock().unwrap();
  let mut changed=current.clone();
  drop(current);
  assert!(owner.require_subset(&changed).is_ok());
  changed.files.get_mut(&canonical_path(&source)).unwrap().content^=1;
  assert!(owner.require_subset(&changed).unwrap_err().to_string().contains("file fact changed"));
  changed=inputs.snapshot.lock().unwrap().clone();
  changed.negative_files.remove(&owner.configuration);
  assert!(owner.require_subset(&changed).unwrap_err().to_string().contains("negative changed"));
  changed=inputs.snapshot.lock().unwrap().clone();
  let mut config=changed.files.get(&canonical_path(&source)).unwrap().clone();
  config.path=owner.configuration.clone();
  changed.files.insert(config.path.clone(),config);
  assert!(owner.require_subset(&changed).unwrap_err().to_string().contains("negative changed"));
  changed=inputs.snapshot.lock().unwrap().clone();
  let directory=owner.discovery.directory_paths().next().unwrap();
  changed.policy_directories.get_mut(directory).unwrap().follow_root^=true;
  assert!(owner.require_subset(&changed).unwrap_err().to_string().contains("typed directory changed"));

  // A new operation with an authored config must retain its actual stamp and
  // digest in the same ordinal proof alongside the selected CODE file.
  std::fs::create_dir_all(root.join("tools/ci")).unwrap();
  std::fs::write(root.join("tools/ci/lint_scopes.toml"),"").unwrap();
  let inputs=RecordingInputs::new(FileSystemInputs,0).with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);
  let owner=queries.prepare_derived_preflight(&inputs,&request).unwrap();
  let DerivedClosure::Joined(closure)=&owner.facts else {panic!("actual joined capture must seal ordinal rows")};
  assert!(!closure.configuration_missing);
  assert!(closure.files.iter().any(|row|row.ordinal==JoinedFileFact::CONFIGURATION));
  let mut changed=inputs.snapshot.lock().unwrap().clone();
  changed.files.get_mut(&owner.configuration).unwrap().stamp.size^=1;
  assert!(owner.require_subset(&changed).unwrap_err().to_string().contains("file fact changed"));
 }
 #[test]fn joined_derived_config_keeps_full_preparse_admission_and_settles_surviving_scope(){
  let root=crate::test_scratch::dir("derived-config-scope-settlement");
  let path=root.join("lint_scopes.toml");
  let text=format!("# {}\n[lint.derived_reads]\nexempt_prefixes = [\"code/skip/\"]\n","comment ".repeat(8192));
  std::fs::write(&path,&text).unwrap();
  let inputs=RecordingInputs::new(FileSystemInputs,0).with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);
  let low=Budget::new(256*1024).unwrap();
  let error=inputs.read_derived_configuration(&path,&low,true).err().expect("small retained scope cannot bypass full preparse reservation");
  assert_eq!(error.kind(),io::ErrorKind::OutOfMemory);
  assert!(inputs.recorded_policy_file_observation(&path).is_err(),"denied read cannot publish a positive configuration fact");
  let high=Budget::new(16*1024*1024).unwrap();
  let (bytes,config)=inputs.read_derived_configuration(&path,&high,true).unwrap();
  assert_eq!(bytes.as_ref().unwrap().as_slice(),text.as_bytes());
  assert!(config.policy_path_exempt("derived_reads","","code/skip/actual.dm"));
  assert!(!config.policy_path_exempt("derived_reads","","code/actual.dm"));
  let bound=config.retained_scope_bound().unwrap_or_else(||config.budget_charge());
  if config.retained_scope_bound().is_some(){
   assert!(bound<128*1024);
   assert!(high.used()<config.budget_charge());
  }
  assert!(high.used()>=bound+bytes.unwrap().capacity());
 }
 #[test]fn derived_configuration_failure_precedes_any_typed_code_discovery(){let root=crate::test_scratch::dir("derived-real-config-first");std::fs::create_dir_all(root.join("code")).unwrap();std::fs::create_dir_all(root.join("tools/ci")).unwrap();std::fs::write(root.join("tools/ci/lint_scopes.toml"),"[not valid TOML").unwrap();std::fs::write(root.join("code/a.dm"),"/obj/a\n").unwrap();let inputs=RecordingInputs::new(FileSystemInputs,0).with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);let queries=Arc::new(crate::query_db::QueryDb::default());let budget=Budget::new(32*1024*1024).unwrap();assert!(queries.prepare_derived_preflight(&inputs,&intent(&root)).is_err());assert!(inputs.snapshot.lock().unwrap().policy_directories.is_empty(),"config interpretation precedes recursive source discovery");}
}

#[cfg(test)]mod dynamic_resource_control{
 use super::*;
 #[test]fn actual_index_consumption_releases_only_its_dynamic_input_bound(){
  let root=crate::test_scratch::dir("derived-preflight-index-resource");std::fs::create_dir_all(root.join("code")).unwrap();std::fs::write(root.join("code/a.dm"),format!("/datum/probe\n    var/value\n// {}\n", "real raw payload ".repeat(1024))).unwrap();
  let inputs=RecordingInputs::new(FileSystemInputs,0).with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);let queries=Arc::new(crate::query_db::QueryDb::default());let selected=super::controls::intent(&root);let owner=queries.prepare_derived_preflight(&inputs,&selected).unwrap();let before=owner.input_retained_charge().unwrap();
  let data=owner.index.lock().unwrap().take().unwrap();let backing=data.retained_charge().unwrap();assert!(backing>0);assert_eq!(before-owner.input_retained_charge().unwrap(),backing,"same live owner keeps its funded metadata while consumed identifier data leaves it");drop(data);assert!(owner.input_retained_charge().unwrap()>std::mem::size_of::<DerivedPreflight>());
 }
}

impl<P:SnapshotProvider> RecordingInputs<P>{
 /// One SAME-attempt raw report only. This deliberately does not construct a
 /// WorkspaceCapture, current source guard, SourceSnapshot or cache witness.
 pub(crate) fn with_failed_original_derived_using<T>(&self,failed:OriginalRootOpenFailure,queries:&crate::query_db::QueryDb,budget:&Arc<Budget>,lender:&mut dyn super::RecordedPolicySourceLender,consume:impl FnOnce(&dq_analyze::captured_derived_reads::DerivedReadData,&Config)->io::Result<T>)->io::Result<T>{
  failed.require_recording(self,queries)?;
  let subject=self.original_analysis_subject().ok_or_else(||invalid("failed Derived report has no actual issued subject namespace"))?;
  if subject.project()!=failed.root(){return Err(invalid("failed Derived report root differs from its exact preparation attempt"))}
  let preflight=subject.derived_preflight_owner()?;preflight.require_subject(subject)?;preflight.require_recording(self)?;
  if !preflight.queries.matches(queries){return Err(invalid("failed Derived report belongs to another actual query owner"))}
  struct Pages<'a,'l,P>{inputs:&'a RecordingInputs<P>,preflight:&'a DerivedPreflight,selected:bool,budget:&'a Arc<Budget>,lender:&'a std::cell::RefCell<&'l mut dyn super::RecordedPolicySourceLender>,completed:std::cell::Cell<usize>}
  impl<P:SnapshotProvider> dq_analyze::reactive_raw_policy_pages::RawPolicyPages for Pages<'_,'_,P>{
   fn for_each(&self,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{
    self.preflight.require_recording(self.inputs)?;
    for path in self.preflight.discovery.files(){
     crate::daemon::control::checkpoint()?;let relative=path.strip_prefix(&self.preflight.discovery.contract().root).map_err(|_|invalid("failed Derived raw source escaped actual discovery"))?;
     let width=relative.as_os_str().len().checked_mul(8).and_then(|n|n.checked_add(512)).ok_or_else(||{self.budget.deny();io::Error::from(io::ErrorKind::OutOfMemory)})?;pay(self.budget,Some(width))?;let rel=relative.to_string_lossy().replace('\\',"/");
     if !dq_analyze::captured_raw_file::is_code_dm(&rel){return Err("failed Derived actual discovery contains non-CODE source".into())}
     if self.selected&&self.preflight.config.policy_path_exempt("derived_reads",dq_analyze::captured_derived_reads::metadata().group,&rel){continue}
     if !self.inputs.with_recorded_policy_file_using(&self.preflight.discovery.contract().root,path,self.budget,&mut **self.lender.borrow_mut(),visit)?{self.preflight.require_recording(self.inputs)?;return Ok(false)}
    }
    self.preflight.require_recording(self.inputs)?;self.completed.set(self.completed.get().checked_add(1).ok_or_else(||{self.budget.deny();io::Error::from(io::ErrorKind::OutOfMemory)})?);Ok(true)
   }
  }
  let lender=std::cell::RefCell::new(lender);let selected=Pages{inputs:self,preflight:&preflight,selected:true,budget,lender:&lender,completed:0.into()};let all=Pages{inputs:self,preflight:&preflight,selected:false,budget,lender:&lender,completed:0.into()};
  struct C<'a>(&'a Budget);impl dq_analyze::key_policy_control::Control for C<'_>{type Error=Failure;const CHECKED:bool=true;fn checkpoint(&mut self)->Result<(),Failure>{crate::daemon::control::checkpoint()?;self.0.require().map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))?;Ok(())}fn reserve(&mut self,n:usize)->Result<(),Failure>{pay(self.0,Some(n))?;Ok(())}fn overflow(&mut self)->Failure{self.0.deny();Failure::Operational(io::ErrorKind::OutOfMemory.into())}fn allocation_failed(&mut self)->Failure{self.overflow()}}
  let mut collector=dq_analyze::generator_test_scope::TestTypeCollector::default();let mut c=C(budget);
  use dq_analyze::reactive_raw_policy_pages::RawPolicyPages;
  if !all.for_each(&mut|relative,views|{collector.observe(relative,views.raw()?,&mut c)?;Ok(true)}).map_err(operational)?{return Err(invalid("failed Derived test classification stopped before actual all-CODE EOF"))}
  let tests=collector.finish();let index=preflight.index.lock().map_err(|_|invalid("failed Derived index poisoned"))?.take().ok_or_else(||invalid("failed Derived same-attempt index was already consumed"))?;
  let data=dq_analyze::captured_derived_reads::derived_reads_data_without_semantic_from_preflight_pages(index,&selected,&all,&tests,budget,&crate::daemon::control::checkpoint).map_err(operational)?;
  if selected.completed.get()<2||all.completed.get()<2{return Err(invalid("failed Derived report omitted selected/all-CODE whole judgment EOF"))}
  failed.require_recording(self,queries)?;preflight.require_recording(self)?;
  // All owned report data physically drops before this operation's funding.
  // The callback receives DATA only; no mixed transcript becomes clean/current.
  let result=consume(&data,&preflight.config);drop(data);drop(tests);drop(all);drop(selected);drop(lender);drop(failed);result
 }
}


#[cfg(test)]
#[test]
fn actual_joined_derived_schema_and_discovery_precede_manifest_bytes() {
 use crate::policy_request::{AnalysisContext,PolicyInputRequest,WorkspacePolicyRequest,WorkspaceAuxiliaryQuestion as Q};
 let root=crate::test_scratch::dir("joined-derived-before-physical-root");
 for directory in ["code","maps","interface","modular_chomp","doc/rewrite","tgui","tools/ci"] {
  std::fs::create_dir_all(root.join(directory)).unwrap();
 }
 let manifest=root.join("deepquarry.dme");
 let code=root.join("code/probe.dm");
 let config=root.join("tools/ci/lint_scopes.toml");
 std::fs::write(&manifest, "#include \"unterminated\n").unwrap();
 std::fs::write(&code, "/datum/probe\n    var/value\n/datum/probe/derived()\n    return list(drawn_from(nameof(value)))\n").unwrap();
 std::fs::write(&config, "[malformed").unwrap();
 let mut intent=PolicyInputRequest::default();
 intent.analysis_context=Some(AnalysisContext::OriginalAnalyze0290);
 intent.workspace_auxiliary=Q::PRIVATE_FULL_REGISTRY.to_vec();
 intent.workspace=Some(WorkspacePolicyRequest{
  root:root.clone(),configuration:config.clone(),
  recursive_roots:Q::authored_doc_ui_roots(Q::PRIVATE_FULL_REGISTRY).unwrap().iter().map(|name|root.join(name)).collect(),
 });
 assert!(intent.clone().admit().is_err());
 let intent=intent.admit_private_authored_doc_ui().unwrap();
 let mut inputs=RecordingInputs::new(FileSystemInputs,0).with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);
 let queries=Arc::new(crate::query_db::QueryDb::default());
 assert!(queries.prepare_derived_preflight(&inputs,&intent).is_err());
 assert!(inputs.snapshot.lock().unwrap().policy_directories.is_empty());
 assert!(inputs.recorded_file_fact(&manifest).is_err());
 std::fs::write(&config, "").unwrap();
 let mut inputs=RecordingInputs::new(FileSystemInputs,0).with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);
 let preflight=queries.prepare_derived_preflight(&inputs,&intent).unwrap();
 assert!(preflight.is_joined_registry());
 assert!(preflight.discovery().check_grep_names().unwrap().0.contains(&manifest));
 assert!(preflight.index.lock().unwrap().is_some());
 assert!(inputs.recorded_file_fact(&code).is_ok());
 assert!(inputs.recorded_file_fact(&manifest).is_err());
 assert!(inputs.source_acquisitions.lock().unwrap().is_empty());
 let config = canonical_path(&config);
 let current = inputs.read_policy_vec_admitted(&config, 4096, &mut |_| Ok(())).unwrap();
 let (_, shared) = preflight.lend_handler_configuration(&inputs,&queries,&config,current.as_deref()).unwrap();
 assert!(Arc::ptr_eq(&shared,&preflight.config));
 assert!(preflight.lend_handler_configuration(&inputs,&queries,&config,Some(b"different")).is_err());
 let subject=inputs.issue_original_analysis_subject_derived(&intent,Arc::clone(&preflight)).unwrap();
 assert!(Arc::ptr_eq(subject.discovery(),preflight.discovery()));
 assert!(Arc::ptr_eq(subject.derived_preflight_owner().unwrap(),&preflight));
}

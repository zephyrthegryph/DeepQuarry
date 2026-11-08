//! Private recorder-issued Derived raw preflight. No hash/None source grants.
use super::*;
use std::sync::{Arc,Mutex,OnceLock};
use dq_analyze::{captured_generator_budget::Budget,captured_raw_file::{Config,RawPolicyViews},captured_raw_policy::Configuration,captured_reactive_reads::Failure,captured_derived_reads::UnsealedDerivedIndexData};
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
 index:Mutex<Option<UnsealedDerivedIndexData>>,facts:InputSnapshot,discovery:Arc<DiscoveryReceipt>,config:Arc<Config>,configuration:PathBuf,configuration_bytes:Option<dm_resources::SharedBytes>,issuer:Arc<()>,queries:crate::query_db::NativeQueryOwnerIdentity,subject_issuer:OnceLock<Arc<()>>,joined_registry:bool,charge:usize,budget:Arc<Budget>,
}
impl DerivedPreflight{
 pub(crate) fn require_bound_current(&self,subject:&OriginalAnalysisSubject,workspace:&Arc<crate::runner_host::workspace_capture::WorkspaceCapture>,scope:&crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,inputs:&dm_analysis::policy_inputs::PolicyInputs)->io::Result<()>{self.require_bound_frame(subject,workspace,scope,inputs)}
 pub(crate) fn take_bound_current(&self,subject:&OriginalAnalysisSubject,workspace:&Arc<crate::runner_host::workspace_capture::WorkspaceCapture>,scope:&crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,inputs:&dm_analysis::policy_inputs::PolicyInputs)->io::Result<Option<UnsealedDerivedIndexData>>{self.require_bound_current(subject,workspace,scope,inputs)?;Ok(self.index.lock().map_err(|_|invalid("Derived current index poisoned"))?.take())}
 pub(crate) fn require_configuration(&self,path:&Path,bytes:Option<&[u8]>)->io::Result<()>{if path!=self.configuration||bytes!=self.configuration_bytes.as_ref().map(|b|b.as_slice()){return Err(invalid("Derived actual current configuration differs from raw preflight"))}Ok(())}
 pub(crate) fn discovery(&self)->&Arc<DiscoveryReceipt>{&self.discovery}
 pub(crate) fn is_joined_registry(&self)->bool{self.joined_registry}
 pub(crate) fn configuration_bytes(&self)->Option<&dm_resources::SharedBytes>{self.configuration_bytes.as_ref()}
 pub(crate) fn account_shared_capture_aliases(&self, seen: &mut BTreeSet<usize>) -> io::Result<()> {
  self.discovery.retained_charge_with(seen)?;
  self.facts.policy_closure_charge_with(seen)?;
  if let Some(bytes)=&self.configuration_bytes{seen.insert(bytes.owner_address());}
  Ok(())
 }
 /// Dynamic resource bound only. The proof remains the sealed recorder owner.
 pub(crate) fn input_retained_charge(&self)->io::Result<usize>{let index=self.index.lock().map_err(|_|invalid("Derived preflight index poisoned during resource census"))?;self.charge.checked_add(match index.as_ref(){Some(data)=>data.retained_charge().ok_or(io::ErrorKind::OutOfMemory)?,None=>0}).ok_or_else(||io::ErrorKind::OutOfMemory.into())}
 fn require_subset(&self,current:&InputSnapshot)->io::Result<()>{
  for(p,v)in &self.facts.files{crate::daemon::control::checkpoint()?;if current.files.get(p)!=Some(v){return Err(invalid("Derived actual preflight file fact changed"))}}
  for p in &self.facts.negative_files{crate::daemon::control::checkpoint()?;if !current.negative_files.contains(p){return Err(invalid("Derived actual preflight negative changed"))}}
  for(p,v)in &self.facts.policy_directories{crate::daemon::control::checkpoint()?;if current.policy_directories.get(p)!=Some(v){return Err(invalid("Derived actual preflight typed directory changed"))}}Ok(())
 }
 pub(crate) fn require_recording<P:SnapshotProvider>(&self,inputs:&RecordingInputs<P>)->io::Result<()>{crate::daemon::control::checkpoint()?;if !Arc::ptr_eq(&self.issuer,&inputs.source_issuer){return Err(invalid("Derived preflight belongs to another actual recorder"))}self.discovery.validate_recording(inputs)?;let current=inputs.snapshot.lock().map_err(|_|invalid("Derived current recording poisoned"))?;self.require_subset(&current)}
 fn bind_subject<P:SnapshotProvider>(&self,inputs:&RecordingInputs<P>,subject:&Arc<OriginalAnalysisSubject>)->io::Result<()>{self.require_recording(inputs)?;if inputs.original_analysis_subject().is_none_or(|current|!Arc::ptr_eq(current,subject))||!subject.matches_workspace_root(&self.discovery.contract().root){return Err(invalid("Derived bind is not this recorder's actual full subject"))}pay(&self.budget,Some(2*std::mem::size_of::<usize>()))?;if self.subject_issuer.set(Arc::clone(subject.actual_subject_issuer())).is_err(){return Err(invalid("Derived preflight full subject was already bound"))}Ok(())}
 /// Validate the EXISTING parent binding. Retain no new mapping alias;
 /// actual source ownership and expiry remain with its original producer.
 pub(super) fn bind_mapping(&self,subject:&OriginalAnalysisSubject,mapping:&Arc<dm_tree::frontend::SourceExportMapping>)->io::Result<()>{self.require_subject(subject)?;subject.require_bound_mapping(mapping)}
 fn require_subject(&self,subject:&OriginalAnalysisSubject)->io::Result<()>{if self.subject_issuer.get().is_none_or(|owner|!Arc::ptr_eq(owner,subject.actual_subject_issuer()))||!subject.derived_preflight().is_ok_and(|p|std::ptr::eq(p,self)){return Err(invalid("Derived preflight has no actual issued full subject"))}Ok(())}
 fn require_bound_frame(&self,subject:&OriginalAnalysisSubject,workspace:&Arc<crate::runner_host::workspace_capture::WorkspaceCapture>,scope:&crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,inputs:&dm_analysis::policy_inputs::PolicyInputs)->io::Result<()>{crate::daemon::control::checkpoint()?;workspace.require_scope(scope)?;self.require_subject(subject)?;subject.require_bound_mapping(inputs.mapping())?;workspace.require_analysis_subject(subject)?;if !scope.uses_query_owner(&self.queries)||workspace.root()!=self.discovery.contract().root||!workspace.matches_auxiliary_questions(if self.joined_registry {
  crate::policy_request::WorkspaceAuxiliaryQuestion::PRIVATE_FULL_REGISTRY
 } else { &[crate::policy_request::WorkspaceAuxiliaryQuestion::DerivedReads] }){return Err(invalid("Derived bound mapping/current QueryDb/role/workspace differs"))}self.require_subset(workspace.facts())?;self.budget.require().map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))}
 pub(crate) fn require_current(&self,subject:&OriginalAnalysisSubject,workspace:&Arc<crate::runner_host::workspace_capture::WorkspaceCapture>,scope:&crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,inputs:&dm_analysis::policy_inputs::PolicyInputs,queries:&crate::query_db::QueryDb)->io::Result<()>{self.require_subject(subject)?;subject.require_bound_mapping(inputs.mapping())?;workspace.require_analysis_subject(subject)?;if !scope.uses_queries(queries)||!self.queries.matches(queries){return Err(invalid("Derived actual current QueryDb owner differs"))}self.require_bound_frame(subject,workspace,scope,inputs)}
 pub(crate) fn take_current(&self,subject:&OriginalAnalysisSubject,workspace:&Arc<crate::runner_host::workspace_capture::WorkspaceCapture>,scope:&crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,inputs:&dm_analysis::policy_inputs::PolicyInputs,queries:&crate::query_db::QueryDb)->io::Result<Option<UnsealedDerivedIndexData>>{self.require_current(subject,workspace,scope,inputs,queries)?;Ok(self.index.lock().map_err(|_|invalid("Derived preflight index poisoned"))?.take())}
 pub(crate) fn census(self:&Arc<Self>,census:&mut crate::heap_census::HeapCensus){let owner="query_snapshot.derived_preflight";if !census.arc_object(owner,self){return}self.discovery.census(census);census.workspace_policy_facts(&self.facts);census.path(owner,&self.configuration);census.arc_object(owner,&self.issuer);census.arc_object(owner,&self.config);if let Some(issuer)=self.subject_issuer.get(){census.arc_object(owner,issuer);}self.queries.visit_storage(|pointer,logical,capacity|{census.exposed_buffer("query_snapshot.derived_query_counter",pointer,logical,capacity);});if let Some(bytes)=&self.configuration_bytes{if census.shared_bytes_owner(owner, bytes){census.vec_payload(owner,bytes.shared_owner().bytes());}}census.unknown(owner,"private raw identifier index BTree nodes, retained source Budget parent chain and interpreted Config backing are not exposed; admission bounds are not reported as heap bytes");}
}
impl<P:SnapshotProvider> RecordingInputs<P>{
 /// Closed cold purpose. This performs selected raw schema before manifest,
 /// native frontend, Globals or BODY. Later full subject binding is separate.
 pub(crate) fn issue_derived_preflight_using(&self,intent:&crate::policy_request::AdmittedPolicyRequest,queries:&Arc<crate::query_db::QueryDb>,budget:&Arc<Budget>,lender:&mut dyn super::RecordedPolicySourceLender)->io::Result<Arc<DerivedPreflight>>{
  use crate::policy_request::{AnalysisContext,WorkspaceAuxiliaryQuestion as Q};let joined_registry=intent.workspace_auxiliary()==Q::PRIVATE_FULL_REGISTRY;if self.analysis_subject.is_some()||self.initial_environment!=dm_preprocess::InitialEnvironment::OriginalChecker0290||intent.analysis_context()!=Some(AnalysisContext::OriginalAnalyze0290)||(!joined_registry&&intent.workspace_auxiliary()!=[Q::DerivedReads])||!intent.workspace_generators().is_empty()||!intent.files().is_empty()||!intent.search_folders().is_empty(){return Err(invalid("Derived cold preflight requires its exact unissued Original purpose"))}let workspace=intent.workspace().ok_or_else(||invalid("Derived workspace absent"))?;let code=if joined_registry{workspace.root.join("code")}else{derived_code_root(workspace)?};
  let configuration=canonical_path(&workspace.configuration);let bytes=self.read_policy_vec_admitted(&configuration,budget.remaining(),&mut|n|pay(budget,n.checked_mul(64).and_then(|n|n.checked_add(8192))))?.map(dm_resources::SharedBytes::from);let config=Arc::new(Config::capture(bytes.as_ref().map_or(Configuration::ProvenMissing,|b|Configuration::Captured(b.as_slice()))).map_err(io::Error::other)?);pay(budget,Some(config.budget_charge()))?;
  let discovery=Arc::new(if joined_registry {
   crate::runner_host::workspace_discovery::discover_full_registry_from_derived(self,
    DiscoveryContract{root:workspace.root.clone(),recursive_roots:workspace.recursive_roots.clone()},
    &configuration,&config,budget,lender)?
  } else {
   crate::runner_host::workspace_discovery::discover_ownership_code_admitted(self,
    DiscoveryContract{root:workspace.root.clone(),recursive_roots:vec![code]},budget,lender)?
  });discovery.validate_recording(self)?;if !discovery.covers_code_dm(&mut|n|pay(budget,Some(n)))?{return Err(invalid("Derived preflight lacks actual complete CODE discovery"))}
  pay(budget,discovery.files().len().checked_mul(std::mem::size_of::<(String,&Path)>()*4))?;let mut selected=Vec::new();
  for path in discovery.files(){crate::daemon::control::checkpoint()?;let relative=path.strip_prefix(&workspace.root).map_err(|_|invalid("Derived preflight path escapes actual root"))?;pay(budget,relative.as_os_str().len().checked_mul(8).and_then(|n|n.checked_add(512)))?;let rel=relative.to_string_lossy().replace('\\',"/");if dq_analyze::captured_raw_file::is_code_dm(&rel)&&!config.policy_path_exempt("derived_reads",dq_analyze::captured_derived_reads::metadata().group,&rel){selected.push((rel,path.as_path()));}}
  selected.sort_unstable_by(|a,b|a.0.cmp(&b.0));
  struct Pages<'a,P>{inputs:&'a RecordingInputs<P>,root:&'a Path,selected:&'a[(String,&'a Path)],budget:&'a Arc<Budget>,lender:std::cell::RefCell<&'a mut dyn super::RecordedPolicySourceLender>,ended:std::cell::Cell<bool>}
  impl<P:SnapshotProvider> dq_analyze::reactive_raw_policy_pages::RawPolicyPages for Pages<'_,P>{fn for_each(&self,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{if self.ended.get(){return Err("Derived cold raw model phase repeated".into())}for(_,path)in self.selected{crate::daemon::control::checkpoint()?;if !self.inputs.with_recorded_policy_file_using(self.root,path,self.budget,&mut **self.lender.borrow_mut(),visit)?{return Ok(false)}}self.ended.set(true);Ok(true)}}
  let pages=Pages{inputs:self,root:&workspace.root,selected:&selected,budget,lender:std::cell::RefCell::new(lender),ended:false.into()};let index=dq_analyze::captured_derived_reads::prepare_selected_pages(&pages,budget,&crate::daemon::control::checkpoint).map_err(operational)?;if !pages.ended.get(){return Err(invalid("Derived preflight did not exhaust actual selected source"))}discovery.validate_recording(self)?;
  // Preadmit exact path capacities and a conservative SAME-recording closure
  // bound before cloning any file/directory metadata, not selected_count*1024.
  let mut paths=BTreeSet::new();pay(budget,Some(128))?;
  for(_,path)in &selected{pay(budget,path.as_os_str().len().checked_mul(4).and_then(|n|n.checked_add(128)))?;}
  pay(budget,configuration.capacity().checked_add(128))?;
  {let current=self.snapshot.lock().map_err(|_|invalid("Derived recording mutex poisoned"))?;pay(budget,Some(current.policy_closure_charge()?))?;}
  for(_,path)in &selected{paths.insert(path.to_path_buf());}paths.insert(configuration.clone());let facts=self.policy_workspace_closure(&paths,discovery.directory_paths())?;
  let mut seen=BTreeSet::new();
  let charge=Some(std::mem::size_of::<DerivedPreflight>()+std::mem::size_of::<Budget>()+4*std::mem::size_of::<usize>()+crate::query_db::NativeQueryOwnerIdentity::retained_charge()).and_then(|n|n.checked_add(if joined_registry{0}else{config.budget_charge()})).and_then(|n|n.checked_add(bytes.as_ref().map_or(0,|bytes|bytes.capacity()+std::mem::size_of::<dm_resources::SharedBytesOwner>()+2*std::mem::size_of::<usize>()))).and_then(|n|n.checked_add(configuration.capacity())).and_then(|n|n.checked_add(discovery.retained_charge_with(&mut seen).ok()?)).and_then(|n|n.checked_add(facts.policy_closure_charge_with(&mut seen).ok()?)).ok_or(io::ErrorKind::OutOfMemory)?;
  pay(budget,Some(crate::query_db::NativeQueryOwnerIdentity::retained_charge()+std::mem::size_of::<DerivedPreflight>()+2*std::mem::size_of::<usize>()))?;let owner=Arc::new(DerivedPreflight{index:Mutex::new(Some(index)),facts,discovery,config,configuration,configuration_bytes:bytes,issuer:Arc::clone(&self.source_issuer),queries:queries.native_query_owner_identity(),subject_issuer:OnceLock::new(),joined_registry,charge,budget:Arc::clone(budget)});owner.require_recording(self)?;Ok(owner)
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
 std::fs::write(config, "").unwrap();
 let mut inputs=RecordingInputs::new(FileSystemInputs,0).with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);
 let preflight=queries.prepare_derived_preflight(&inputs,&intent).unwrap();
 assert!(preflight.is_joined_registry());
 assert!(preflight.discovery().check_grep_names().unwrap().0.contains(&manifest));
 assert!(preflight.index.lock().unwrap().is_some());
 assert!(inputs.recorded_file_fact(&code).is_ok());
 assert!(inputs.recorded_file_fact(&manifest).is_err());
 assert!(inputs.source_acquisitions.lock().unwrap().is_empty());
 let subject=inputs.issue_original_analysis_subject_derived(&intent,Arc::clone(&preflight)).unwrap();
 assert!(Arc::ptr_eq(subject.discovery(),preflight.discovery()));
 assert!(Arc::ptr_eq(subject.derived_preflight_owner().unwrap(),&preflight));
}

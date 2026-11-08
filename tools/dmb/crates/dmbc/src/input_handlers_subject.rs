//! Actual recorded source recipe for sem/handlers' private partial TU.
//! No alternate model/cache, full-project role or physical synthetic EOF.
use super::*;
use crate::runner_host::workspace_discovery::{DiscoveryContract,DiscoveryReceipt};
use dq_analyze::{captured_generator_budget::Budget,captured_reactive_reads::Failure,key_policy_control::{self as kc,Control},sem_handlers_partial_recipe::Recipe};
use std::sync::Arc;
fn fail(message:&str)->io::Error{io::Error::new(io::ErrorKind::InvalidInput,message)}
fn quota(budget:&Budget,message:&str)->io::Error{budget.deny();io::Error::new(io::ErrorKind::OutOfMemory,message)}
fn actual(failure:Failure)->io::Error{match failure{Failure::Operational(error)=>error,Failure::Unsupported(message)=>io::Error::new(io::ErrorKind::Unsupported,message)}}
fn read_funded<P:SnapshotProvider>(inputs:&RecordingInputs<P>,path:&Path,budget:&Budget)->io::Result<Option<dm_resources::SharedBytes>>{inputs.read_policy_vec_admitted(path,budget.remaining(),&mut|n|{let n=n.checked_add(128).ok_or_else(||quota(budget,"handlers raw payload overflow"))?;budget.charge(n).map_err(|_|quota(budget,"handlers raw payload refused before read"))}).map(|bytes|bytes.map(Into::into))}
struct Native<'a>{budget:&'a Budget}
impl Control for Native<'_>{type Error=io::Error;const CHECKED:bool=true;fn checkpoint(&mut self)->io::Result<()>{self.budget.require().map_err(|_|quota(self.budget,"handlers subject budget denied"))?;crate::daemon::control::checkpoint()}fn reserve(&mut self,n:usize)->io::Result<()>{self.budget.charge(n).map_err(|_|quota(self.budget,"handlers subject allocation denied"))}fn overflow(&mut self)->io::Error{quota(self.budget,"handlers subject allocation overflow")}fn allocation_failed(&mut self)->io::Error{quota(self.budget,"handlers subject allocation refused")}}
struct HeaderReceipt{issuer:Arc<()>,path:PathBuf}
struct CapturedHandlerRoot{project:PathBuf,namespace:PathBuf,header:dm_preprocess::AcquiredSource}
pub(crate) struct HandlerStructuralSubject{
 root:PathBuf,canonical_root:PathBuf,captured:Option<CapturedHandlerRoot>,discovery:Arc<DiscoveryReceipt>,recipe:Recipe,requires_full:bool,selected_full:bool,
 configuration:PathBuf,configuration_bytes:Option<dm_resources::SharedBytes>,config:Arc<dq_analyze::captured_raw_file::Config>,
 selection_facts:InputSnapshot,issuer:Arc<()>,recorder:Arc<()>,
 bound:std::sync::OnceLock<std::sync::Weak<dm_tree::frontend::SourceExportMapping>>,
 _configuration_owner: Option<Arc<super::DerivedPreflight>>,
 // Last: source/recipe allocations are gone before their producer funding.
 budget:Arc<Budget>,
}
impl HandlerStructuralSubject{
 pub(crate) fn root_path(&self)->&Path{&self.root}
 pub(crate) fn canonical_root_path(&self)->&Path{&self.canonical_root}
 pub(crate) fn project(&self)->io::Result<&Path>{Ok(&self.captured()?.project)}
 fn captured(&self)->io::Result<&CapturedHandlerRoot>{self.captured.as_ref().ok_or_else(||fail("no structural source root exists when no old candidates were selected"))}
 pub(crate) fn requires_full_model(&self)->bool{self.requires_full}
 pub(crate) fn is_selected_full(&self)->bool{self.selected_full}
 pub(crate) fn recipe(&self)->&Recipe{&self.recipe}
 pub(crate) fn config(&self)->&dq_analyze::captured_raw_file::Config{&self.config}
 /// Actual old CODE-tree membership, not physical-path inference or authority.
 /// Preserve exact slash registration spelling; do not collapse ParentDir or
 /// turn a compiled include outside the selected tree into an ALLOW source.
 pub(crate) fn old_tree_contains(&self,relative:&str)->bool{self.discovery.files().iter().any(|path|path.strip_prefix(&self.root).ok().and_then(|path|path.to_str()).is_some_and(|path|path.chars().map(|c|if c=='\\'{'/'}else{c}).eq(relative.chars())))}

 pub(crate) fn require_configuration(&self,path:&Path,bytes:Option<&[u8]>)->io::Result<()>{if path!=self.configuration||bytes!=self.configuration_bytes.as_ref().map(|b|b.as_slice()){return Err(fail("handlers actual interpreted configuration differs from selected raw preflight"))}Ok(())}
 pub(crate) fn input_retained_charge(&self)->io::Result<usize>{self.budget.require().map_err(|m|quota(&self.budget,&m))?;Ok(self.budget.used())}
 pub(crate) fn census(self:&Arc<Self>,c:&mut crate::heap_census::HeapCensus){let owner="query_snapshot.handlers_preflight";if !c.arc_object(owner,self){return}c.path(owner,&self.root);c.path(owner,&self.canonical_root);c.path(owner,&self.configuration);c.arc_object(owner,&self.config);c.arc_object(owner,&self.issuer);c.arc_object(owner,&self.recorder);self.discovery.census(c);c.workspace_policy_facts(&self.selection_facts);if let Some(bytes)=&self.configuration_bytes{if c.shared_bytes_owner(owner, bytes){c.vec_payload(owner,bytes.shared_owner().bytes());}}if let Some(mapping)=self.bound.get().and_then(std::sync::Weak::upgrade){c.source_export_mapping(&mapping);}if let Some(root)=&self.captured{c.path(owner,&root.project);c.path(owner,&root.namespace);}c.unknown(owner,"private Recipe and Config collection nodes and source Budget parent chain lack allocator geometry; admission totals are not heap bytes");}
 fn require_operation<P:SnapshotProvider>(&self,inputs:&RecordingInputs<P>)->io::Result<()>{crate::daemon::control::checkpoint()?;self.budget.require().map_err(|_|quota(&self.budget,"handlers current operation budget denied"))?;if !Arc::ptr_eq(&self.recorder,&inputs.source_issuer){return Err(fail("handlers partial subject belongs to another actual input recorder"))}Ok(())}
 pub(crate) fn require_recording<P:SnapshotProvider>(&self,inputs:&RecordingInputs<P>)->io::Result<()>{
  self.require_operation(inputs)?;self.discovery.validate_recording(inputs)?;
  // Borrow the SAME ledger: do not clone all selected facts per physical read.
  let current=inputs.snapshot.lock().map_err(|_|fail("handlers current input ledger poisoned"))?;
  if !self.selection_facts.original_observations_subset_of(&current)||!self.selection_facts.files.iter().all(|(path,fact)|current.files.get(path)==Some(fact))||!self.selection_facts.negative_files.iter().all(|path|current.negative_files.contains(path)&&!current.files.contains_key(path))||!self.selection_facts.policy_directories.iter().all(|(path,fact)|current.policy_directories.get(path)==Some(fact)){return Err(fail("handlers selection/negative dependencies changed; reissue the child recipe"))}Ok(())
 }
 pub(crate) fn require_current<P:SnapshotProvider>(&self,inputs:&RecordingInputs<P>)->io::Result<()>{self.require_recording(inputs)?;let current=inputs.snapshot.lock().map_err(|_|fail("handlers current input ledger poisoned"))?;if !current.restat(&inputs.provider)?.unchanged(){return Err(fail("handlers actual input closure changed before publication"))}Ok(())}
 pub(crate) fn provider<'a,P:SnapshotProvider+Sync>(&'a self,inputs:&'a RecordingInputs<P>)->io::Result<HandlerStructuralProvider<'a,P>>{self.require_current(inputs)?;self.captured()?;Ok(HandlerStructuralProvider{subject:self,inputs})}
 pub(crate) fn bind_frontend<P:SnapshotProvider>(&self,frontend:&dm_tree::frontend::DiagnosticFrontend,inputs:&RecordingInputs<P>)->io::Result<()>{
  self.require_current(inputs)?;let root=self.captured()?;let structural=frontend.handlers_structural_source().map_err(|m|fail(&m))?;let view=structural.view();
  if !view.original_plan().defines().is_empty()||view.mapping().initial_environment()!=dm_preprocess::InitialEnvironment::OriginalChecker0290{return Err(fail("handlers structural frontend has another caller macro context"))}
  enum Stop{Source(&'static str),Operational(io::Error)}impl From<&'static str>for Stop{fn from(m:&'static str)->Self{Self::Source(m)}}
  let (root_occurrence,entry,path,lease)=view.mapping().original_root_acquisition_using(&mut||crate::daemon::control::checkpoint().map_err(Stop::Operational)).map_err(|f|match f{Stop::Operational(e)=>e,Stop::Source(m)=>fail(m)})?;
  let receipt=lease.receipt::<HeaderReceipt>().ok_or_else(||fail("handlers root lacks its private captured recipe receipt"))?;
  if entry!=root.project||path!=root.project||receipt.path!=root.project||!Arc::ptr_eq(&receipt.issuer,&self.issuer)||!lease.same_binding(root.header.lease()){return Err(fail("handlers root/path/acquisition belongs to another partial recipe"))}
  for(index,(path,acquired))in view.mapping().source_acquisitions().enumerate(){crate::daemon::control::checkpoint()?;if index==root_occurrence{continue}let physical=acquired.ok_or_else(||fail("handlers included source has no actual acquisition"))?;if physical.same_binding(lease){return Err(fail("handlers partial child cannot use private synthetic root acquisition"))}inputs.mapped_recorded_source_fact(view.mapping(),index,path)?;}
  if self.bound.get().is_some_and(|old|!std::sync::Weak::ptr_eq(old,&Arc::downgrade(view.mapping()))){return Err(fail("handlers partial subject is already bound to another actual native graph"))}
  let _=self.bound.set(Arc::downgrade(view.mapping()));Ok(())
 }
}
/// A borrowed purpose wrapper over the SAME actual recorder. Only the generated
/// root is intercepted; children retain their genuine physical acquisitions.
pub(crate) struct HandlerStructuralProvider<'a,P:SnapshotProvider+Sync>{subject:&'a HandlerStructuralSubject,inputs:&'a RecordingInputs<P>}
impl<P:SnapshotProvider+Sync> dm_preprocess::SourceProvider for HandlerStructuralProvider<'_,P>{
 fn path_presence_admitted(&self,path:&Path,work:&dyn dm_preprocess::source_arena_credit::SourceArenaWork)->io::Result<bool>{self.subject.require_operation(self.inputs)?;dm_preprocess::SourceProvider::path_presence_admitted(self.inputs,path,work)}
 fn original_batch_source(&self)->io::Result<Option<&(dyn dm_preprocess::SourceProvider+Sync)>>{self.subject.require_operation(self.inputs)?;Ok(Some(self))}
 fn initial_environment(&self)->dm_preprocess::InitialEnvironment{dm_preprocess::InitialEnvironment::OriginalChecker0290}
 fn read(&self,_:&Path)->Result<String,String>{Err("handlers partial input requires its actual admitted original acquisition".into())}
 fn original_raw_source_open_admitted(&self,path:&Path,max:usize,work:&dyn dm_preprocess::source_arena_credit::SourceArenaWork,after_open:&mut dyn FnMut()->io::Result<dm_preprocess::OriginalRawOpenDecision>,before_read:&mut dyn FnMut(usize)->io::Result<()>,before_decode:&mut dyn FnMut(dm_preprocess::OriginalRawAllocationPlan<'_>)->io::Result<()>,acquired:&mut dyn FnMut(&dm_preprocess::SourceAcquisitionLease)->io::Result<()>)->io::Result<dm_preprocess::OriginalRawReadOutcome>{
  self.subject.require_operation(self.inputs)?;let root=self.subject.captured()?;
  if canonical_path(path)==root.project{if after_open()?==dm_preprocess::OriginalRawOpenDecision::Suppress{return Ok(dm_preprocess::OriginalRawReadOutcome::Suppressed)}before_decode(dm_preprocess::OriginalRawAllocationPlan::new(&[],0,0,0,false,false))?;acquired(root.header.lease())?;return Ok(dm_preprocess::OriginalRawReadOutcome::Acquired(root.header.lease().clone()))}
  dm_preprocess::SourceProvider::original_raw_source_open_admitted(self.inputs,path,max,work,after_open,before_read,before_decode,acquired)
 }
 fn original_raw_source_open_owned_admitted(&self,path:&Path,max:usize,work:&dyn dm_preprocess::source_arena_credit::SourceArenaWork,after_open:&mut dyn FnMut()->io::Result<dm_preprocess::OriginalRawOpenDecision>,before_read:&mut dyn FnMut(usize)->io::Result<()>,before_decode:&mut dyn FnMut(dm_preprocess::OriginalRawAllocationPlan<'_>)->io::Result<()>,fund_text:&dm_preprocess::source_arena_credit::OriginalReadTextFunding<'_>,acquired:&mut dyn FnMut(&dm_preprocess::SourceAcquisitionLease)->io::Result<()>)->io::Result<dm_preprocess::OriginalRawReadOutcome>{
  self.subject.require_operation(self.inputs)?;let root=self.subject.captured()?;
  if canonical_path(path)==root.project{if after_open()?==dm_preprocess::OriginalRawOpenDecision::Suppress{return Ok(dm_preprocess::OriginalRawReadOutcome::Suppressed)}before_decode(dm_preprocess::OriginalRawAllocationPlan::new(&[],0,0,0,false,false))?;acquired(root.header.lease())?;return Ok(dm_preprocess::OriginalRawReadOutcome::Acquired(root.header.lease().clone()))}
  dm_preprocess::SourceProvider::original_raw_source_open_owned_admitted(self.inputs,path,max,work,after_open,before_read,before_decode,fund_text,acquired)
 }
 fn original_raw_source_admitted(&self,path:&Path,max:usize,before_read:&mut dyn FnMut(usize)->io::Result<()>,before_decode:&mut dyn FnMut(dm_preprocess::OriginalRawAllocationPlan<'_>)->io::Result<()>,acquired:&mut dyn FnMut(&dm_preprocess::SourceAcquisitionLease)->io::Result<()>)->io::Result<Option<dm_preprocess::SourceAcquisitionLease>>{
  self.subject.require_operation(self.inputs)?;if canonical_path(path)==self.subject.captured()?.project{before_decode(dm_preprocess::OriginalRawAllocationPlan::new(&[],0,0,0,false,false))?;acquired(self.subject.captured()?.header.lease())?;return Ok(Some(self.subject.captured()?.header.lease().clone()))}
  dm_preprocess::SourceProvider::original_raw_source_admitted(self.inputs,path,max,before_read,before_decode,acquired)
 }
 fn original_source_bytes<'a>(&'a self,lease:&'a dm_preprocess::SourceAcquisitionLease)->io::Result<Option<&'a[u8]>>{self.subject.require_operation(self.inputs)?;if lease.same_binding(self.subject.captured()?.header.lease()){return Ok(Some(self.subject.captured()?.header.prepared().original().as_bytes()))}dm_preprocess::SourceProvider::original_source_bytes(self.inputs,lease)}
 fn acquired_source(&self,path:&Path)->Result<Option<dm_preprocess::AcquiredSource>,String>{self.subject.require_operation(self.inputs).map_err(|e|e.to_string())?;let root=self.subject.captured().map_err(|e|e.to_string())?;if canonical_path(path)==root.project{return Ok(Some(root.header.clone()))}dm_preprocess::SourceProvider::acquired_source(self.inputs,path)}
 fn source_acquisition(&self,path:&Path,text:&dm_preprocess::SourceText)->Option<dm_preprocess::AcquiredSource>{if self.subject.require_operation(self.inputs).is_err(){return None}if canonical_path(path)==self.subject.captured.as_ref()?.project{return self.subject.captured.as_ref()?.header.prepared().original().same_view(text).then(||self.subject.captured.as_ref().unwrap().header.clone())}dm_preprocess::SourceProvider::source_acquisition(self.inputs,path,text)}
 fn prepared_source(&self,path:&Path)->Option<Arc<dm_preprocess::regions::prepared_source::PreparedSource>>{if self.subject.require_operation(self.inputs).is_err(){return None}if canonical_path(path)==self.subject.captured.as_ref()?.project{return Some(Arc::clone(self.subject.captured.as_ref()?.header.prepared()))}dm_preprocess::SourceProvider::prepared_source(self.inputs,path)}
}
use dq_analyze::sem_handlers_partial_recipe::HandlerCodeFacts;
fn handler_relative_order<'a>(root:&Path,path:&'a Path)->Option<impl Iterator<Item=u8>+Clone+'a>{
 Some(path.strip_prefix(root).ok()?.to_str()?.bytes().map(|b|if b==b'\\'{b'/'}else{b}))
}
fn handler_code_at<'a>(
 root:&Path,path:&Path,roster:&mut std::iter::Peekable<impl Iterator<Item=(&'a Path,Option<HandlerCodeFacts>)>>,
)->Option<HandlerCodeFacts>{
 let current=handler_relative_order(root,path)?;
 while let Some(&(candidate,_))=roster.peek(){
  match handler_relative_order(root,candidate)?.cmp(current.clone()){
   std::cmp::Ordering::Less=>{roster.next();},
   std::cmp::Ordering::Equal if candidate.as_os_str()==path.as_os_str()=>return roster.next().and_then(|(_,facts)|facts),
   _=>return None,
  }
 }
 None
}
struct Pages<'a,'l,'provider,P:SnapshotProvider,I:Iterator>{inputs:&'a RecordingInputs<P>,root:&'a Path,files:&'a [PathBuf],budget:&'a Arc<Budget>,lender:&'a std::cell::RefCell<&'l mut (dyn super::RecordedPolicySourceLender+'provider)>,trace:bool,code_roster:std::cell::RefCell<Option<std::iter::Peekable<I>>>,code_facts:std::cell::Cell<Option<HandlerCodeFacts>>}
impl<'a,P:SnapshotProvider,I:Iterator<Item=(&'a Path,Option<HandlerCodeFacts>)>> dq_analyze::reactive_raw_policy_pages::RawPolicyPages for Pages<'a,'_,'_,P,I>{
 fn handler_code_facts(&self)->Option<HandlerCodeFacts>{self.code_facts.get()}
 fn for_each(&self,visit:&mut dyn FnMut(&str,dq_analyze::captured_raw_file::RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{
  let mut reused_code = 0;
  for (index, path) in self.files.iter().enumerate() {
   crate::daemon::control::checkpoint()?;
   let code=self.code_roster.borrow_mut().as_mut().and_then(|roster|handler_code_at(self.root,path,roster));
   let mut consume=|relative:&str,views:dq_analyze::captured_raw_file::RawPolicyViews<'_>|{
    self.code_facts.set(code);
    let pending=visit(relative,views);
    self.code_facts.set(None);
    pending
   };
   let result = if code.is_some(){
    self.inputs.with_recorded_policy_file_marker_using(self.root,path,self.budget,&mut **self.lender.borrow_mut(),&mut consume)
   }else{
    self.inputs.with_recorded_policy_file_using(self.root,path,self.budget,&mut **self.lender.borrow_mut(),&mut consume)
   };
   if self.trace && (result.is_err() || index % 1024 == 0) {
    let relative = path.strip_prefix(self.root).unwrap_or(path).display();
    eprintln!("original handler preflight file={index} path={relative} used={} remaining={}", self.budget.used(), self.budget.remaining());
   }
   if !result? { return Ok(false); }
   reused_code += usize::from(code.is_some());
  }
  if self.trace {
   eprintln!("original handler CODE views reused={reused_code} of {}", self.files.len());
  }
  Ok(true)
 }
}
impl<P:SnapshotProvider> RecordingInputs<P>{
 /// Internal child of the already admitted OriginalAnalyze parent. This reads
 /// the actual selected files and config through its existing input ledger.
 pub(crate) fn issue_handlers_structural_subject_using(&self,intent:&crate::policy_request::AdmittedPolicyRequest,selected:Option<&dq_analyze::captured_allow_annotations::full_unused::SelectedTreePlanData>,budget:&Arc<Budget>,lender:&mut dyn super::RecordedPolicySourceLender,queries:&crate::query_db::QueryDb,derived:Option<&Arc<super::DerivedPreflight>>)->io::Result<HandlerStructuralSubject>{
  use crate::policy_request::{AnalysisContext,WorkspaceAuxiliaryQuestion as Q};
  let auxiliary=if selected.is_some(){Q::admits_selected_handlers(intent.workspace_auxiliary())}else{intent.workspace_auxiliary()==[Q::SemHandlers]};
  if intent.analysis_context()!=Some(AnalysisContext::OriginalAnalyze0290)||!auxiliary||!intent.files().is_empty()||!intent.search_folders().is_empty()||!intent.workspace_generators().is_empty()||self.initial_environment!=dm_preprocess::InitialEnvironment::OriginalChecker0290{return Err(fail("handlers partial child requires its actual Original Analyze purpose"))}
  let workspace=intent.workspace().ok_or_else(||fail("handlers child has no admitted workspace"))?;let mut control=Native{budget};control.checkpoint()?;
  let trace = cfg!(debug_assertions) && std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some();
  let mark = |stage| {
   if trace {
    eprintln!("original handler preflight stage={stage} used={} remaining={}", budget.used(), budget.remaining());
   }
  };
  if let Some(plan)=selected{
   let roots=&workspace.recursive_roots;
   let exact=roots.len()==2&&roots.iter().zip(["code","maps"]).all(|(path,relative)|
    path.strip_prefix(&workspace.root).ok()==Some(Path::new(relative)));
   let joined=Q::is_private_handlers_domain(intent.workspace_auxiliary())
    && Q::authored_doc_ui_roots(intent.workspace_auxiliary()).is_some_and(|expected|
      roots.len()==expected.len() && roots.iter().zip(expected).all(|(path,relative)|
        path.strip_prefix(&workspace.root).ok()==Some(Path::new(relative))));
   if (!exact&&!joined)||plan.roots()!=["code","maps"]||workspace.configuration.strip_prefix(&workspace.root).ok()!=Some(Path::new("tools/ci/lint_scopes.toml")){
    return Err(fail("selected handlers requires its exact admitted CODE+MAPS workspace and plan"));
   }
   kc::reserve(&mut control,||workspace.root.as_os_str().len().checked_mul(8)?.checked_add(1024))?;
  }
  mark("start");
  let (config_bytes, config) = if let Some(derived) = derived {
   if intent.workspace_auxiliary() != Q::PRIVATE_FULL_REGISTRY {
    return Err(fail("shared handler configuration requires the full registry request"));
   }
   // Reread the genuine current bytes. The parsed owner is shared only
   // once this recorder and the prior capture agree on exact content.
   let scratch = Budget::scoped_temporaries(budget).map_err(io::Error::other)?;
   let bytes = self.read_policy_vec_admitted(&workspace.configuration, budget.remaining(), &mut |length| {
    let size = length.checked_add(128).ok_or_else(|| quota(budget, "handler configuration read overflow"))?;
    scratch.charge(size).map_err(io::Error::other)
   })?;
   derived.lend_handler_configuration(self, queries, &canonical_path(&workspace.configuration), bytes.as_deref())?
  } else {
   let bytes = read_funded(self,&workspace.configuration,budget)?;
   kc::reserve(&mut control,||bytes.as_ref().map_or(Some(1024),|b|b.capacity().checked_mul(64)?.checked_add(8192)))?;
   let config=dq_analyze::captured_raw_file::Config::capture(bytes.as_ref().map_or(dq_analyze::captured_raw_policy::Configuration::ProvenMissing,|b|dq_analyze::captured_raw_policy::Configuration::Captured(b.as_slice()))).map_err(|m|fail(&m))?;
   kc::reserve(&mut control,||config.budget_charge().checked_add(2*std::mem::size_of::<usize>()))?;
   (bytes, Arc::new(config))
  };
  // The combined plan determines the legacy tree for final ALLOW lookups,
  // not the structural selector. Legacy candidates, declarations and try-call
  // inputs still come exclusively from visible CODE, on this same recorder.
  let recursive_roots=if selected.is_some(){vec![workspace.root.join("code")]}else{workspace.recursive_roots.clone()};
  mark("configuration");
  let discovery_scratch=Budget::scoped_temporaries(budget).map_err(|message|quota(budget,&message))?;
  let discovery=Arc::new(crate::runner_host::workspace_discovery::discover_handlers_code_admitted(self,DiscoveryContract{root:workspace.root.clone(),recursive_roots},budget,&discovery_scratch,lender)?);
  discovery.validate_recording(self)?;
  let retained_discovery=discovery.retained_charge()?;kc::reserve(&mut control,||retained_discovery.checked_add(1024))?;
  drop(discovery_scratch);
  mark("discovery");
  let manifest=workspace.root.join("deepquarry.dme");
  // Old Decl::dme_include_order observes optional marker DATA only. The
  // actual source-open result distinguishes genuine unavailability from a
  // provider/work/1450/cancellation error; no error-kind inference here.
  let mut marker=None;let mut calls=0usize;
  lender.with_held_source_work(queries,&mut|work|{calls+=1;if calls!=1{return Err(fail("handler marker resource loan repeated"))}marker=Some(dm_preprocess::source_arena_credit::read_original_source_open_using(self,&manifest,budget.remaining(),work,&mut||Ok(dm_preprocess::OriginalRawOpenDecision::Read))?);Ok(())})?;
  if calls!=1{return Err(fail("handler marker resource loan omitted"))}let marker=marker.ok_or_else(||fail("handler marker resource loan returned no actual read outcome"))?;
  let marker_lease=match marker{dm_preprocess::OriginalRawReadOutcome::Acquired(lease)=>Some(lease),dm_preprocess::OriginalRawReadOutcome::SourceOpenFailed(_)=>None,dm_preprocess::OriginalRawReadOutcome::Absent|dm_preprocess::OriginalRawReadOutcome::Suppressed=>return Err(fail("optional handler marker has no genuine actual open observation"))};
  let original_manifest=marker_lease.as_ref().map(super::recorded_source_original).transpose()?;
  let manifest_text=original_manifest.as_ref().and_then(|source|match source{super::RecordedSourceOriginal::Utf8(text)=>std::str::from_utf8(text.as_bytes()).ok(),super::RecordedSourceOriginal::Bytes(bytes)=>std::str::from_utf8(bytes.as_slice()).ok()});
  let order_budget=Budget::scoped_temporaries(budget).map_err(|message|quota(budget,&message))?;
  let mut order_control=Native{budget:&order_budget};
  kc::reserve(&mut order_control,||manifest_text.map_or(Some(1024),|text|text.len().checked_mul(32)?.checked_add(8192)))?;
  // A fixed manifest observation is never this partial TU's root or EOF.
  let order=match manifest_text{Some(text)=>dq_analyze::raw_marker_policy::dme_include_order_controlled(text,false,&mut order_control)?,None=>Default::default()};
  let handler_scope=config.borrowed_report_scope("sem/handlers",dq_analyze::sem_handlers_policy::metadata().group);let extra=handler_scope.map_or(&[][..],|scope|scope.list("try_calls"));
  mark("marker");
  // Discovery already owns the exact legacy slash-string ordering.
  let recipe_plan={let source_lender=std::cell::RefCell::new(&mut *lender);let pages=Pages{inputs:self,root:&workspace.root,files:discovery.files(),budget,lender:&source_lender,trace,
   code_roster:std::cell::RefCell::new(derived.map(|owner|owner.handler_code_roster(self,queries,&workspace.root)).transpose()?.map(Iterator::peekable)),
   code_facts:std::cell::Cell::new(None)};dq_analyze::captured_sem_handlers_recipe::select_scoped_from_pages(&pages,&order,extra,handler_scope,manifest_text,budget,&crate::daemon::control::checkpoint).map_err(actual)?};
  drop(order);
  drop(order_budget);
  mark("recipe");
  let recipe=recipe_plan.recipe;let requires_full=recipe_plan.requires_full;
  if trace {
   eprintln!("original handler source recipe includes={} candidates={}", recipe.includes.len(), recipe.candidates.len());
  }
  if selected.is_some()&&!requires_full&&!Q::is_private_handlers_domain(intent.workspace_auxiliary()){
   return Err(io::Error::new(io::ErrorKind::Unsupported,"selected handlers requires genuine full-model demand"));
  }
  let selection_scratch=Budget::scoped_temporaries(budget).map_err(|message|quota(budget,&message))?;
  let mut selection_control=Native{budget:&selection_scratch};
  let mut selection_files=BTreeSet::new();
  for path in discovery.files(){
   kc::reserve(&mut selection_control,||path.as_os_str().len().checked_mul(4)?.checked_add(256))?;
   selection_files.insert(path.clone());
  }
  kc::reserve(&mut selection_control,||workspace.configuration.as_os_str().len().checked_mul(4)?.checked_add(256))?;
  selection_files.insert(workspace.configuration.clone());
  if marker_lease.is_some(){
   kc::reserve(&mut selection_control,||manifest.capacity().checked_add(256))?;
   selection_files.insert(manifest);
  }
  let canonical_root=std::fs::canonicalize(&workspace.root)?;
  // The old algorithm does not even create/compile synth.dme without a
  // candidate. A selected READS_AS/output-base may still demand the distinct
  // full source, but it cannot manufacture a structural root or witness.
  let directory = if recipe.candidates.is_empty() {
   None
  } else {
   let directory = canonical_root.join("__dmb_original_handlers_structural__");
   // This is a single typed directory probe with no traversal metadata.
   // Recipe and source bytes already occupy the separate live input budget.
   if !matches!(self.capture_policy_directory_lent(&directory,false,0,budget,lender)?,PolicyDirectoryListing::Missing) {
    return Err(fail("private handlers synthetic namespace already has a physical entry"));
   }
   Some(directory)
  };
  let closure_scratch=Budget::scoped_temporaries(budget).map_err(|message|quota(budget,&message))?;
  let mut closure_control=Native{budget:&closure_scratch};
  let metadata={let current=self.snapshot.lock().map_err(|_|fail("handlers metadata ledger poisoned"))?;kc::reserve(&mut closure_control,||current.policy_directories.len().checked_mul(1024)?.checked_add(4096))?;current.policy_closure_charge()?};
  kc::reserve(&mut closure_control,||metadata.checked_mul(2)?.checked_add(4096))?;
  let selection_facts=self.policy_workspace_closure(&selection_files,discovery.directory_paths().chain(directory.iter()))?;
  drop(selection_files);
  drop(selection_scratch);
  let retained_facts=selection_facts.policy_closure_charge_with(&mut BTreeSet::new())?;kc::reserve(&mut control,||retained_facts.checked_add(4096))?;
  drop(closure_scratch);
  mark("closure");
  let issuer=Arc::new(());let captured=if let Some(directory)=directory{let project=directory.join("synth.dme");kc::reserve(&mut control,||canonical_root.as_os_str().len().checked_mul(128)?.checked_add(8192))?;let rendered_root=dm_preprocess::regions::filesystem_comparison_key(&canonical_root);let rendered=recipe.render(&rendered_root,&mut control)?;let lexical=dm_preprocess::regions::prepared_source::PreparedSource::include_header_retained_bound(rendered.len(),recipe.includes.len()).ok_or_else(||quota(budget,"handlers synthetic root lexical pregrant overflow"))?;kc::reserve(&mut control,||Some(lexical))?;kc::reserve(&mut control,||rendered.capacity().checked_add(2048)?.checked_add(project.as_os_str().len().checked_mul(8)?))?;let header=self.prepare_subject_header_for(super::prepared::SubjectHeaderPurpose::HandlersStructural,&canonical_root,rendered.into(),HeaderReceipt{issuer:Arc::clone(&issuer),path:project.clone()})?;Some(CapturedHandlerRoot{project,namespace:directory,header})}else{None};
  kc::reserve(&mut control,||Some(std::mem::size_of::<HandlerStructuralSubject>()+2*std::mem::size_of::<usize>()))?;
  kc::reserve(&mut control,||workspace.root.as_os_str().len().checked_add(canonical_root.as_os_str().len())?.checked_mul(4))?;
  let subject=HandlerStructuralSubject{root:workspace.root.clone(),canonical_root,captured,discovery,recipe,requires_full,selected_full:selected.is_some(),configuration:workspace.configuration.clone(),configuration_bytes:config_bytes,config,selection_facts,issuer,recorder:Arc::clone(&self.source_issuer),bound:Default::default(),_configuration_owner:derived.cloned(),budget:Arc::clone(budget)};subject.require_current(self)?;Ok(subject)
 }
}

pub(super) fn handler_receipt_storage(value:&(dyn std::any::Any+Send+Sync))->Option<(&PathBuf,&PathBuf,&Arc<()>)>{let receipt=value.downcast_ref::<HeaderReceipt>()?;Some((&receipt.path,&receipt.path,&receipt.issuer))}

/// Preserve the actual native diagnostic vector as an inspectable frontier.
/// No generic Unsupported/native grammar gap becomes old modelNone/bodyNone.
#[derive(Debug)]pub(crate) struct HandlerNativeFrontier(pub(crate) dm_tree::frontend::FrontendDiagnostics);
impl std::fmt::Display for HandlerNativeFrontier{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{write!(f,"actual native partial preparation remains unavailable: {:?}",self.0)}}
impl std::error::Error for HandlerNativeFrontier{}
/// Current native partial preparation, retained by the existing host snapshot
/// when its structural query is issued. This is a source owner, not a cache.
pub(crate) struct PreparedHandlersStructural{subject:Arc<HandlerStructuralSubject>,frontend:Option<Arc<dm_tree::frontend::DiagnosticFrontend>>}
impl PreparedHandlersStructural{
 pub(crate) fn subject(&self)->&Arc<HandlerStructuralSubject>{&self.subject}
 pub(crate) fn frontend(&self)->Option<&Arc<dm_tree::frontend::DiagnosticFrontend>>{self.frontend.as_ref()}
}
impl<P:SnapshotProvider+Sync> RecordingInputs<P>{
 /// Uses the current borrowed executor and SAME QueryDb resource/BODY host.
 /// No private executor, parser, RetainedSemanticTree or model cache is created.
 pub(crate) fn prepare_handlers_structural(&self,subject:Arc<HandlerStructuralSubject>,executor:&dm_exec::BuildExecutor,queries:&Arc<crate::query_db::QueryDb>)->io::Result<PreparedHandlersStructural>{
  if subject.recipe.candidates.is_empty() {
   subject.require_current(self)?;
   return Ok(PreparedHandlersStructural{subject,frontend:None});
  }
  let provider=subject.provider(self)?;
  let seed=dm_tree::checker_builtins::original_analysis_seed().map_err(|error|io::Error::new(io::ErrorKind::InvalidData,format!("invalid Original builtin catalog: {error:?}")))?;
  let host=Arc::clone(queries)as Arc<dyn dm_tree::frontend::SettingExpressionQueries>;
  let frontend=dm_tree::frontend::build_for_original_handlers_structural_checked(subject.project()?,&provider,dm_tree::frontend::FrontendConfig{workers:executor.workers(),engine:Some(seed.frontend_seed()),observer:None},None,executor,&host).map_err(|failure|match failure{dm_tree::frontend::FrontendBuildFailure::Operational(actual)=>actual,dm_tree::frontend::FrontendBuildFailure::Diagnostics(errors)=>io::Error::new(io::ErrorKind::Unsupported,HandlerNativeFrontier(errors))})?;
  dm_profile::request_mark("handlers.partial_frontend_done");
  let frontend=Arc::new(frontend.with_body_queries(Arc::clone(queries)as Arc<dyn dm_tree::frontend::BodySyntaxQueries>).map_err(io::Error::other)?);subject.bind_frontend(&frontend,self)?;
  dm_profile::request_mark("handlers.partial_source_bound");
  Ok(PreparedHandlersStructural{subject,frontend:Some(frontend)})
 }
}
#[cfg(test)]mod partial_subject_tests{
 use super::*;
 #[test]
 fn handler_code_cursor_matches_exact_provider_path_and_skips_missing_rows(){
  let root=Path::new("root");
  let skipped=root.join("code/0.dm");
  let slash=root.join("code/a.dm");
  let backslash=root.join("code\\a.dm");
  let missing=root.join("code/b.dm");
  let present=root.join("code/c.dm");
  let mut rows=[
   (skipped.as_path(),None),
   (slash.as_path(),Some(HandlerCodeFacts::Candidate)),
   (missing.as_path(),None),
   (present.as_path(),Some(HandlerCodeFacts::Both)),
  ].into_iter().peekable();
  assert_eq!(handler_code_at(root,&backslash,&mut rows),None);
  assert_eq!(handler_code_at(root,&slash,&mut rows),Some(HandlerCodeFacts::Candidate));
  assert_eq!(handler_code_at(root,&missing,&mut rows),None);
  assert_eq!(handler_code_at(root,&present,&mut rows),Some(HandlerCodeFacts::Both));
 }
 fn fixture(label:&str)->(PathBuf,crate::policy_request::AdmittedPolicyRequest,RecordingInputs){
  let root=crate::test_scratch::dir(label);for(rel,text)in[("code/__defines/context.dm","/datum/act\n"),("code/candidate.dm","/proc/probe(datum/act/A)\n    START_ACTION()\n"),("code/ordinary_macros.dm","#define START_ACTION ACT_ATTEMPT\n"),("deepquarry.dme","#include \"code/__defines/context.dm\"\n#include \"code/ordinary_macros.dm\"\n#include \"code/candidate.dm\"\n")]{let path=root.join(rel);std::fs::create_dir_all(path.parent().unwrap()).unwrap();std::fs::write(path,text).unwrap();}
  let intent=crate::policy_request::PolicyInputRequest{analysis_context:Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290),workspace_auxiliary:vec![crate::policy_request::WorkspaceAuxiliaryQuestion::SemHandlers],workspace:Some(crate::policy_request::WorkspacePolicyRequest{root:root.clone(),recursive_roots:vec![root.join("code")],configuration:root.join("tools/ci/lint_scopes.toml")}),..Default::default()}.admit().unwrap();let inputs=RecordingInputs::new(FileSystemInputs,0).with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);(root,intent,inputs)
 }
 #[test]
 fn real_handler_budget_growth_is_observed_before_cached_admission(){
  let(_,intent,inputs)=fixture("handlers-upper-reobserves-live-charge");
  let queries=Arc::new(crate::query_db::QueryDb::default());
  let subject=queries.prepare_handlers_preflight(&inputs,&intent).unwrap();
  let exact=queries.raw_source_input_charge_locked().unwrap();
  assert_eq!(queries.raw_source_upper_for_test().unwrap(),(exact,true));

  // This is the same budget later used to retain the prepared Handler capture.
  // Growth must be visible even though no source-ledger row was replaced.
  let growth=4096;
  subject.budget.charge(growth).unwrap();
  assert_eq!(queries.raw_source_upper_for_test().unwrap(),(exact+growth,true));
  assert_eq!(queries.raw_source_input_charge_locked().unwrap(),exact+growth);

  subject.budget.deny();
  assert_eq!(queries.raw_source_upper_for_test().unwrap_err().kind(),io::ErrorKind::OutOfMemory);
 }

 #[test]fn captured_partial_subject_rejects_other_recorder_revision_and_physical_namespace(){
  let(root,intent,inputs)=fixture("handlers-partial-current");let budget=Budget::new(64*1024*1024).unwrap();let subject=Arc::new(crate::query_db::QueryDb::default()).prepare_handlers_preflight(&inputs,&intent).unwrap();assert_eq!(subject.recipe.includes.iter().map(|row|row.relative.as_str()).collect::<Vec<_>>(),["code/__defines/context.dm","code/candidate.dm"]);assert_eq!(subject.captured().unwrap().header.encoding(),dm_preprocess::SourceEncoding::SyntheticUtf8);assert!(!subject.project().unwrap().exists());
  let other=RecordingInputs::new(FileSystemInputs,0).with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);assert!(subject.require_current(&other).is_err());std::fs::write(root.join("code/candidate.dm"),"/proc/probe(datum/act/A)\n    return 1\n").unwrap();assert!(subject.require_current(&inputs).is_err());
  let(_,intent,inputs)=fixture("handlers-partial-negative-namespace");let subject=Arc::new(crate::query_db::QueryDb::default()).prepare_handlers_preflight(&inputs,&intent).unwrap();std::fs::create_dir_all(&subject.captured().unwrap().namespace).unwrap();assert!(subject.require_current(&inputs).is_err());
 }
 fn selected_intent(root:&Path)->crate::policy_request::AdmittedPolicyRequest{
  crate::policy_request::PolicyInputRequest{
   analysis_context:Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290),
   workspace_auxiliary:vec![crate::policy_request::WorkspaceAuxiliaryQuestion::SemHandlersFullAllow],
   workspace:Some(crate::policy_request::WorkspacePolicyRequest{
    root:root.to_path_buf(),recursive_roots:vec![root.join("code"),root.join("maps")],
    configuration:root.join("tools/ci/lint_scopes.toml"),
   }),..Default::default()
  }.admit().unwrap()
 }

 #[test]fn selected_handlers_projects_only_code_and_refuses_map_only_full_demand(){
  use dq_analyze::{captured_allow_annotations::{Operation,full_unused::SelectedTreePlanData},tree::CODE_MAPS_DM};
  let(root,_,inputs)=fixture("selected-handlers-structural-projection");
  std::fs::create_dir(root.join("maps")).unwrap();
  std::fs::write(root.join("maps/handler.dm"),"READS_AS(/datum/only_map, value)\nACTION(map_marker)\n/proc/map_handler(datum/act/A)\n    return list(A)\n").unwrap();
  let intent=selected_intent(&root);
  let queries=Arc::new(crate::query_db::QueryDb::default());
  let budget=Budget::new(1<<20).unwrap();let mut work=Operation{budget:&budget,poll:&||Ok(())};
  let plan=SelectedTreePlanData::new([CODE_MAPS_DM],&mut work).unwrap();
  let error=queries.prepare_selected_handlers_preflight(&inputs,&intent,&plan,None).err().unwrap();
  assert_eq!(error.kind(),io::ErrorKind::Unsupported);
  assert!(!inputs.snapshot.lock().unwrap().policy_directories.contains_key(&root.join("maps")));

  // Use a new actual recorder after changing authored input.
  std::fs::write(root.join("code/demand.dm"),"READS_AS(/datum/ordinary, value)\nACTION(code_marker)\n").unwrap();
  let current=RecordingInputs::new(FileSystemInputs,0).with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);
  let subject=queries.prepare_selected_handlers_preflight(&current,&intent,&plan,None).unwrap();
  assert!(subject.is_selected_full()&&subject.requires_full_model());
  assert_eq!(subject.recipe.candidates.iter().map(|row|row.relative.as_str()).collect::<Vec<_>>(),["code/__defines/context.dm","code/candidate.dm"]);
  assert!(subject.recipe.try_calls.iter().any(|name|name=="act_code_marker"));
  assert!(!subject.recipe.try_calls.iter().any(|name|name=="act_map_marker"));
  assert!(!subject.old_tree_contains("maps/handler.dm"));
  subject.require_current(&current).unwrap();
  assert!(subject.require_current(&inputs).is_err());
  assert!(current.original_analysis_subject().is_none(),"the structural projection cannot issue a full graph");
 }

 #[test]fn actual_native_partial_prepare_is_not_filtered_full_graph_or_full_purpose(){
  let(_,intent,inputs)=fixture("handlers-partial-native-purpose");let queries=Arc::new(crate::query_db::QueryDb::default());let executor=dm_exec::BuildExecutor::new(1).unwrap();let subject=queries.prepare_handlers_preflight(&inputs,&intent).unwrap();let prepared=inputs.prepare_handlers_structural(subject,&executor,&queries).unwrap();
  let partial=prepared.frontend.as_ref().unwrap().handlers_structural_source().unwrap();let view=partial.view();assert_eq!(prepared.frontend.as_ref().unwrap().preparation_purpose(),dm_tree::frontend::DiagnosticPreparationPurpose::OriginalHandlersStructuralComplete);assert!(view.original_analysis_completeness().is_none());assert!(prepared.frontend.as_ref().unwrap().checker_source_view().is_err());assert!(view.expanded_text().contains("START_ACTION"));assert!(!view.original_plan().occurrences().iter().any(|row|row.path.ends_with("ordinary_macros.dm")),"ordinary macro file must never be compiled into this actual partial TU");
  let other=Arc::new(crate::query_db::QueryDb::default()).prepare_handlers_preflight(&inputs,&intent).unwrap();assert!(other.bind_frontend(prepared.frontend.as_ref().unwrap(),&inputs).is_err(),"equal recipe bytes cannot impersonate another current captured root acquisition");
 }
 #[test]fn no_candidates_issues_no_synthetic_root_or_structural_model_even_with_physical_namespace(){
  let(root,intent,inputs)=fixture("handlers-no-candidates-native");std::fs::write(root.join("code/__defines/context.dm"),"#define ORDINARY 1\n").unwrap();std::fs::write(root.join("code/candidate.dm"),"/datum/ordinary\n").unwrap();std::fs::create_dir_all(root.join("__dmb_original_handlers_structural__")).unwrap();
  let budget=Budget::new(64*1024*1024).unwrap();let subject=Arc::new(crate::query_db::QueryDb::default()).prepare_handlers_preflight(&inputs,&intent).unwrap();assert!(subject.recipe.candidates.is_empty());assert!(!subject.requires_full_model());assert!(subject.captured.is_none());assert!(subject.project().is_err());assert!(subject.provider(&inputs).is_err());
  let queries=Arc::new(crate::query_db::QueryDb::default());let executor=dm_exec::BuildExecutor::new(1).unwrap();let subject=queries.prepare_handlers_preflight(&inputs,&intent).unwrap();let prepared=inputs.prepare_handlers_structural(subject,&executor,&queries).unwrap();assert!(prepared.frontend().is_none(),"no ordinary parser diagnostics/model outcome is manufactured when old code never requested a model");
 }
 #[test]fn reads_as_only_still_demands_distinct_full_model_without_structural_model(){
  let(root,intent,inputs)=fixture("handlers-reads-as-only-full-demand");std::fs::write(root.join("code/__defines/context.dm"),"#define ORDINARY 1\n").unwrap();std::fs::write(root.join("code/candidate.dm"),"READS_AS(/datum/ordinary, value)\n").unwrap();
  let subject=Arc::new(crate::query_db::QueryDb::default()).prepare_handlers_preflight(&inputs,&intent).unwrap();assert!(subject.recipe.candidates.is_empty());assert!(subject.requires_full_model(),"actual old full-model demand includes READS_AS even with no handlers or structural candidate");assert!(subject.captured.is_none());
 }

 #[test]fn actual_handler_preflight_interprets_config_before_any_code_discovery_or_manifest(){
  let(root,intent,inputs)=fixture("handlers-cold-config-before-code");let configuration=root.join("tools/ci/lint_scopes.toml");std::fs::create_dir_all(configuration.parent().unwrap()).unwrap();std::fs::write(configuration,"[not valid TOML").unwrap();std::fs::remove_file(root.join("deepquarry.dme")).unwrap();
  let queries=Arc::new(crate::query_db::QueryDb::default());assert!(queries.prepare_handlers_preflight(&inputs,&intent).is_err());assert!(inputs.snapshot.lock().unwrap().policy_directories.is_empty(),"config failure must precede CODE discovery and synthetic namespace creation");assert!(inputs.recorded_file_fact(&root.join("code/candidate.dm")).is_err());assert!(inputs.original_analysis_subject().is_none());
 }
 #[test]fn actual_handler_preflight_retains_same_config_and_refuses_other_purpose(){
  let(root,intent,inputs)=fixture("handlers-config-retention-and-purpose");let queries=Arc::new(crate::query_db::QueryDb::default());let subject=queries.prepare_handlers_preflight(&inputs,&intent).unwrap();assert!(subject.require_configuration(&root.join("tools/ci/lint_scopes.toml"),None).is_ok());assert!(subject.require_configuration(&root.join("other.toml"),None).is_err());assert!(subject.require_configuration(&root.join("tools/ci/lint_scopes.toml"),Some(b"changed")).is_err());assert!(inputs.original_analysis_subject().is_none(),"private partial selection cannot issue a full subject even with valid candidates");
  let wrong=crate::policy_request::PolicyInputRequest{analysis_context:Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290),workspace:Some(crate::policy_request::WorkspacePolicyRequest{root:root.clone(),recursive_roots:vec![root.join("code")],configuration:root.join("tools/ci/lint_scopes.toml")}),..Default::default()}.admit().unwrap();assert!(queries.prepare_handlers_preflight(&inputs,&wrong).is_err());
 }

 #[test]fn actual_partial_provider_delegates_admitted_physical_presence_without_spoofing_synthetic_file(){
  let(root,intent,inputs)=fixture("handlers-real-presence-delegation");let queries=Arc::new(crate::query_db::QueryDb::default());let subject=queries.prepare_handlers_preflight(&inputs,&intent).unwrap();let provider=subject.provider(&inputs).unwrap();assert!(dm_preprocess::SourceProvider::path_presence_admitted(&provider,&root.join("code/candidate.dm"),queries.as_ref()).unwrap());assert!(!dm_preprocess::SourceProvider::path_presence_admitted(&provider,subject.project().unwrap(),queries.as_ref()).unwrap(),"captured synthetic source is not a fabricated physical file");assert!(inputs.snapshot.lock().unwrap().path_presence.get(&root.join("code/candidate.dm")).is_some());
 }

}

/// Retained current partial producer result, not a cache or a full SourceSnapshot.
/// The actual host QueryState owns this; no source-valued Weak is minted here.
pub(crate) struct HandlerPreparedCapture{
 prepared:PreparedHandlersStructural,
 inputs:Option<dm_analysis::policy_inputs::HandlersStructuralInputs>,
 facts:InputSnapshot,queries:crate::query_db::NativeQueryOwnerIdentity,issuance:u64,
 staged:Option<DetachedStructural>,
 // Metadata/recipe payload drops before its actual producer funding.
 budget:Arc<Budget>,
}
struct DetachedStructural{
 revision:Option<u128>,
 rows:std::sync::Mutex<Option<Result<crate::query_db::StagedHandlerStructuralRows,Failure>>>,
}
impl HandlerPreparedCapture{
 pub(crate) fn require_staging_recording<P:SnapshotProvider>(&self,recording:&RecordingInputs<P>,queries:&crate::query_db::QueryDb)->io::Result<()>{
  self.require_bound()?;
  if self.has_staged_rows()||!self.prepared.subject.is_selected_full()||!self.uses_queries(queries){
   return Err(fail("handler stage requires actual live selected partial inputs"));
  }
  self.prepared.subject.require_recording(recording)?;
  let current=recording.snapshot.lock().map_err(|_|fail("handler staging recorder poisoned"))?;
  if !self.is_recorded_in(&current){return Err(fail("handler staging recorder lost actual partial facts"))}
  Ok(())
 }
 pub(crate) fn partial_revision(&self)->io::Result<Option<u128>>{
  if let Some(staged)=&self.staged{return Ok(staged.revision)}
  self.prepared.frontend.as_ref().map(|_|self.structural_inputs().map(|inputs|inputs.source_revision())).transpose()
 }
 pub(crate) fn has_staged_rows(&self)->bool{self.staged.is_some()}
 pub(crate) fn take_staged_rows(&self)->Result<Option<crate::query_db::StagedHandlerStructuralRows>,Failure>{
  let Some(staged)=&self.staged else{return Ok(None)};
  let mut rows=staged.rows.lock().map_err(|_|fail("handler staged result mutex poisoned"))?;
  rows.take().ok_or_else(||Failure::from(fail("handler staged result already consumed")))?.map(Some)
 }
 pub(crate) fn detach_staged(
  capture:Arc<Self>,rows:Result<crate::query_db::StagedHandlerStructuralRows,Failure>,
 )->io::Result<Arc<Self>>{
  capture.require_bound()?;
  if capture.has_staged_rows()||!capture.prepared.subject.is_selected_full(){return Err(fail("only a live selected partial owner can detach"))}
  let mut capture=Arc::try_unwrap(capture).map_err(|_|fail("handler staged producer still has a live owning alias"))?;
  let revision=capture.partial_revision()?;
  // The replacement Arc is funded separately: the old query Weak may
  // still retain its control block. No archive owner crosses the handoff.
  let archive=capture.inputs.as_ref().map(|inputs|Arc::downgrade(inputs.archive()));
  drop(capture.inputs.take());
  drop(capture.prepared.frontend.take());
  if cfg!(debug_assertions)&&std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some(){
   eprintln!("original handler partial detached archive_live={}",archive.as_ref().is_some_and(|archive|archive.strong_count()!=0));
  }
  capture.staged=Some(DetachedStructural{revision,rows:std::sync::Mutex::new(Some(rows))});
  capture.budget.charge(std::mem::size_of::<Self>()+2*std::mem::size_of::<usize>()).map_err(|m|quota(&capture.budget,&m))?;
  Ok(Arc::new(capture))
 }
 pub(crate) fn prepared(&self)->&PreparedHandlersStructural{&self.prepared}
 pub(crate) fn structural_inputs(&self)->io::Result<&dm_analysis::policy_inputs::HandlersStructuralInputs>{self.inputs.as_ref().ok_or_else(||fail("no structural model exists for genuinely empty candidate selection"))}
 pub(crate) fn uses_queries(&self,queries:&crate::query_db::QueryDb)->bool{self.queries.matches(queries)}
 pub(crate) fn budget(&self)->&Arc<Budget>{&self.budget}
 pub(crate) fn issuance(&self)->u64{self.issuance}
 pub(crate) fn root(&self)->&Path{&self.prepared.subject.root}
 pub(crate) fn candidate(&self,relative:&str)->bool{
  // Captured recipe selection validates strict relative-name order and
  // preserves it when adding candidates.
  self.prepared.subject.recipe.candidates.binary_search_by(|row|row.relative.as_str().cmp(relative)).is_ok()
 }
 pub(crate) fn try_calls(&self)->&[String]{&self.prepared.subject.recipe.try_calls}
 pub(crate) fn is_recorded_in(&self,complete:&InputSnapshot)->bool{
  let facts=&self.facts;facts.files.iter().all(|(p,v)|complete.files.get(p)==Some(v))&&facts.folders.iter().all(|(p,v)|complete.folders.get(p)==Some(v))&&facts.policy_directories.iter().all(|(p,v)|complete.policy_directories.get(p)==Some(v))&&facts.negative_files.is_subset(&complete.negative_files)&&facts.generated_outputs.is_subset(&complete.generated_outputs)&&facts.original_observations_subset_of(complete)
 }
 pub(crate) fn require_bound(&self)->io::Result<()>{
  crate::daemon::control::checkpoint()?;self.budget.require().map_err(|m|quota(&self.budget,&m))?;
  if let Some(staged)=&self.staged{
   if !self.prepared.subject.is_selected_full()||self.prepared.frontend.is_some()||self.inputs.is_some()
    ||staged.revision.is_none()!=self.prepared.subject.recipe.candidates.is_empty(){
    return Err(fail("handler detached disposition differs from actual partial preparation"));
   }
   return Ok(())
  }
  match(&self.prepared.frontend,&self.inputs){
   (None,None)if self.prepared.subject.recipe.candidates.is_empty()=>Ok(()),
   (Some(frontend),Some(inputs))=>{let source=frontend.handlers_structural_source().map_err(|m|fail(&m))?;if !inputs.matches(&source)||!self.prepared.subject.bound.get().and_then(std::sync::Weak::upgrade).is_some_and(|mapping|Arc::ptr_eq(&mapping,inputs.mapping())){return Err(fail("handlers capture current partial purpose/source binding differs"))}Ok(())},
   _=>Err(fail("handlers capture model/selection availability differs")),
  }
 }
}
impl<P:SnapshotProvider+Sync> RecordingInputs<P>{
 pub(crate) fn capture_handlers_prepared(&self,prepared:PreparedHandlersStructural,queries:&Arc<crate::query_db::QueryDb>)->io::Result<Arc<HandlerPreparedCapture>>{
  let budget=Arc::clone(&prepared.subject.budget);let budget=&budget;prepared.subject.require_current(self)?;let mut c=Native{budget};
  let inputs=match &prepared.frontend{Some(frontend)=>{let source=frontend.handlers_structural_source().map_err(|m|fail(&m))?;Some(dm_analysis::policy_inputs::HandlersStructuralInputs::capture(&source).map_err(io::Error::other)?)},None=>None};
  dm_profile::request_mark("handlers.partial_revision_done");
  // Same InputSnapshot clone-admission contract as current policy captures.
  let facts={let current=self.snapshot.lock().map_err(|_|fail("handler final input ledger poisoned"))?;let bytes=current.policy_closure_charge()?;kc::reserve(&mut c,||bytes.checked_mul(2)?.checked_add(std::mem::size_of::<HandlerPreparedCapture>()+crate::query_db::NativeQueryOwnerIdentity::retained_charge()+4096))?;
   // Immutable path/open/payload facts clone only their funded shared roots;
   // the old folder Vec<String> and generated-path maps deep-copy separately.
   for(path,listing)in &current.folders{kc::reserve(&mut c,||path.capacity().checked_mul(4)?.checked_add(256))?;if let FolderListing::Present(names)=listing{kc::reserve(&mut c,||names.len().checked_mul(std::mem::size_of::<String>()*4)?.checked_add(128))?;for name in names{kc::reserve(&mut c,||name.len().checked_mul(4)?.checked_add(64))?;}}}
   for path in &current.generated_outputs{kc::reserve(&mut c,||path.capacity().checked_mul(4)?.checked_add(256))?;}current.clone()};
  static NEXT:std::sync::atomic::AtomicU64=std::sync::atomic::AtomicU64::new(1);let issuance=NEXT.fetch_add(1,std::sync::atomic::Ordering::Relaxed);if issuance==u64::MAX{return Err(fail("handlers capture issuance exhausted"))}
  let result=Arc::new(HandlerPreparedCapture{prepared,inputs,facts,staged:None,queries:queries.native_query_owner_identity(),issuance,budget:Arc::clone(budget)});result.require_bound()?;Ok(result)
 }
}

impl HandlerPreparedCapture{
 pub(crate) fn require_failed_full_prefix<P:SnapshotProvider>(&self,inputs:&RecordingInputs<P>,queries:&crate::query_db::QueryDb,failed:&super::OriginalRootOpenFailure)->io::Result<()>{
  self.require_bound()?;self.prepared.subject.require_operation(inputs)?;if !self.uses_queries(queries){return Err(fail("handler failed prefix has another actual query owner"))}
  let full=inputs.original_analysis_subject().ok_or_else(||fail("handler failed prefix lacks its actual independently requested full subject"))?;
  if !self.prepared.subject.requires_full_model()||failed.root()!=full.project()||!full.matches_workspace_root(self.root()){return Err(fail("handler failed prefix has another actual full root or unrequested partition"))}
  failed.require_handler_prefix(inputs,queries,&self.prepared.subject.selection_facts)?;failed.require_handler_prefix(inputs,queries,&self.facts)
 }
}

//! Genuine full Analyze semantic subject, issued from the same recorded inputs.
//! A generated root is a private header, never a recorded physical file.
use super::*;
use crate::runner_host::workspace_discovery::{DiscoveryReceipt,DiscoveryContract};
use std::sync::Arc;
const LIMIT:usize=64*1024*1024;
fn slash_bytes(path:&Path)->impl Iterator<Item=u8>+'_ {path.as_os_str().as_encoded_bytes().iter().map(|byte|if *byte==b'\\'{b'/'}else{*byte})}
struct HeaderReceipt{issuer:Arc<()>,path:PathBuf}
pub(crate) struct OriginalAnalysisSubject{derived_preflight:std::sync::OnceLock<Arc<super::DerivedPreflight>>,engine_preflight:Option<Arc<crate::runner_host::workspace_discovery::EnginePreflight>>,
 root:PathBuf,canonical_root:PathBuf, project:PathBuf, discovery:Arc<DiscoveryReceipt>,bound_mapping:std::sync::OnceLock<std::sync::Weak<dm_tree::frontend::SourceExportMapping>>,
 fixed_original:Option<dm_resources::SharedBytes>,header:Option<dm_preprocess::AcquiredSource>,actual_root:std::sync::OnceLock<dm_preprocess::SourceAcquisitionLease>,recorder_issuer:Arc<()>,issuer:Arc<()>,charge:usize,
}
fn oom()->io::Error{io::Error::new(io::ErrorKind::OutOfMemory,"original Analyze subject exceeds existing source-capture bound")}
impl OriginalAnalysisSubject{
 pub(super) fn actual_subject_issuer(&self)->&Arc<()>{&self.issuer}
 pub(super) fn install_derived_preflight(&self,preflight:Arc<super::DerivedPreflight>)->io::Result<()>{self.derived_preflight.set(preflight).map_err(|_|invalid("Derived full subject preflight repeated"))}
 pub(crate) fn derived_preflight_owner(&self)->io::Result<&Arc<super::DerivedPreflight>>{self.derived_preflight.get().ok_or_else(||invalid("actual recorded Derived preflight owner absent"))}
 pub(crate) fn derived_preflight(&self)->io::Result<&super::DerivedPreflight>{self.derived_preflight.get().map(Arc::as_ref).ok_or_else(||invalid("actual recorded Derived preflight absent"))}

 pub(crate) fn engine_preflight(&self)->io::Result<&crate::runner_host::workspace_discovery::EnginePreflight>{let engine=self.engine_preflight.as_deref().ok_or_else(||invalid("actual conditional engine preflight absent"))?;if engine.is_empty()||!Arc::ptr_eq(engine.discovery(),&self.discovery){return Err(invalid("engine model purpose differs from actual selected discovery"))}Ok(engine)}
 pub(crate) fn bind_frontend(&self,view:&dm_tree::frontend::DiagnosticSourceView<'_>)->io::Result<()>{
  if view.original_analysis_completeness().is_none(){return Err(invalid("Analyze subject lacks authentic original primary outcome"))}
  view.require_original_analysis_seed().map_err(|message|invalid(&message))?;if !view.original_plan().defines().is_empty(){return Err(invalid("Analyze subject contains unadmitted caller defines"))}self.validate_mapping(view.mapping())?;let _=self.bound_mapping.set(Arc::downgrade(view.mapping()));self.require_bound_mapping(view.mapping())?;if let Some(preflight)=self.derived_preflight.get(){preflight.bind_mapping(self,view.mapping())?}Ok(())
 }
 pub(crate) fn require_bound_mapping(&self,mapping:&dm_tree::frontend::SourceExportMapping)->io::Result<()>{if self.bound_mapping.get().is_none(){return Err(invalid("full Analyze subject has not bound actual default-context frontend"))}self.validate_mapping(mapping)}
 /// Issued namespace DATA only, before source traversal. This cannot validate
 /// a root acquisition, mapping, source role, EOF or semantic product.
 pub(crate) fn declared_entry_root(&self,project:&Path)->io::Result<&Path>{if project!=self.project{return Err(invalid("issued generation namespace differs from subject entry"))}Ok(&self.canonical_root)}
 pub(crate) fn generation_root(&self,project:&Path,lease:&dm_preprocess::SourceAcquisitionLease)->io::Result<&Path>{
  self.declared_entry_root(project)?;
  if let Some(header)=&self.header{if !header.lease().same_binding(lease){return Err(invalid("generation synthetic root acquisition differs"))}}
  else if !super::source_acquisition::recorded_root_lease_matches(lease,&self.recorder_issuer,project,false){return Err(invalid("generation root lacks its actual recorded acquisition"))}
  Ok(&self.canonical_root)
 }
 pub(crate) fn generation_workspace_root(&self,project:&Path,lease:&dm_preprocess::SourceAcquisitionLease)->io::Result<&Path>{self.generation_root(project,lease)?;Ok(&self.root)}
 pub(crate) fn generation_manifest<'a>(&'a self,root:&Path,project:&Path,lease:&'a dm_preprocess::SourceAcquisitionLease)->io::Result<dq_analyze::captured_untyped::ManifestRead<'a>>{if self.generation_workspace_root(project,lease)?!=root{return Err(invalid("generation subject manifest root differs"))}if self.synthetic(){self.manifest_payload()}else{original_manifest(lease)}}
 fn manifest_payload(&self)->io::Result<dq_analyze::captured_untyped::ManifestRead<'_>>{use dq_analyze::captured_untyped::ManifestRead;if let Some(source)=self.actual_root.get(){return original_manifest(source)}Ok(match &self.fixed_original{Some(bytes)=>ManifestRead::OriginalBytes(bytes.as_slice()),None=>ManifestRead::ProvenUnavailable})}
 pub(crate) fn manifest_originals<'a>(&'a self,root:&Path,mapping:&dm_tree::frontend::SourceExportMapping)->io::Result<dq_analyze::captured_untyped::ManifestRead<'a>>{
  self.require_bound_mapping(mapping)?;if !self.matches_workspace_root(root){return Err(invalid("generation manifest loan belongs to another actual workspace"))}self.manifest_payload()
 }
 pub(crate) fn project(&self)->&Path{&self.project}
 pub(crate) fn matches_request_project(&self,path:&Path)->bool{path.file_name()==Some(std::ffi::OsStr::new("deepquarry.dme"))&&path.parent().is_some_and(|parent|parent==self.root||parent==self.canonical_root)}
 pub(crate) fn census(self:&Arc<Self>,census:&mut crate::heap_census::HeapCensus){if !census.arc_object("query_snapshot.original_analysis_subject",self){return}if let Some(preflight)=self.derived_preflight.get(){preflight.census(census);}census.path("query_snapshot.original_analysis_subject",&self.root);census.path("query_snapshot.original_analysis_subject",&self.canonical_root);census.path("query_snapshot.original_analysis_subject",&self.project);census.arc_object("query_snapshot.original_analysis_subject.issuer",&self.issuer);self.discovery.census(census);if let Some(bound)=self.bound_mapping.get(){if let Some(mapping)=bound.upgrade(){census.source_export_mapping(&mapping);}else{let bytes=std::mem::size_of::<dm_tree::frontend::SourceExportMapping>();census.exposed_buffer("query_snapshot.original_analysis_subject.expired_mapping",bound.as_ptr()as usize,bytes,bytes);}}if let Some(bytes)=&self.fixed_original{if census.shared_bytes_owner("query_snapshot.original_analysis_subject.fixed", bytes){census.vec_payload("query_snapshot.original_analysis_subject.fixed",bytes.shared_owner().bytes());}}for source in self.header.iter(){census.source_acquisition(source.lease());census.prepared_source(source.prepared());}if let Some(source)=self.actual_root.get(){census.source_acquisition(source);}census.arc_object("query_snapshot.original_analysis_subject.recorder",&self.recorder_issuer);}
 pub(crate) fn discovery(&self)->&Arc<DiscoveryReceipt>{&self.discovery}
 pub(crate) fn fixed_candidate(&self,path:&Path)->Option<Option<&dm_resources::SharedBytes>>{if !self.synthetic()||path.strip_prefix(&self.root).ok()!=Some(Path::new("deepquarry.dme")){return None}Some(self.fixed_original.as_ref())}
 pub(crate) fn matches_workspace_root(&self,root:&Path)->bool{self.root==root}
 pub(crate) fn same_discovery(&self,discovery:&Arc<DiscoveryReceipt>)->bool{Arc::ptr_eq(&self.discovery,discovery)}
 pub(crate) fn synthetic(&self)->bool{self.header.is_some()}
 pub(crate) fn charge(&self)->usize{self.charge}
 pub(crate) fn source_for(&self,path:&Path)->Option<&dm_preprocess::AcquiredSource>{(canonical_path(path)==self.project).then_some(self.header.as_ref()).flatten()}
 pub(crate) fn header_for(&self,path:&Path)->Option<&dm_preprocess::AcquiredSource>{(canonical_path(path)==self.project).then_some(self.header.as_ref()).flatten()}
 pub(crate) fn authenticates_header(&self,path:&Path,lease:&dm_preprocess::SourceAcquisitionLease)->bool{
  // Ordinary source loans have a different receipt type. Reject them
  // before rebuilding the synthetic header's canonical path.
  let Some(receipt)=lease.receipt::<HeaderReceipt>()else{return false};
  let Some(header)=self.header_for(path)else{return false};
  receipt.path==self.project&&Arc::ptr_eq(&receipt.issuer,&self.issuer)&&header.lease().same_binding(lease)
 }
 pub(crate) fn validate_mapping(&self,mapping:&dm_tree::frontend::SourceExportMapping)->io::Result<()>{
  if self.bound_mapping.get().is_some_and(|bound|bound.as_ptr()!=std::ptr::from_ref(mapping)){return Err(invalid("Analyze subject belongs to another actual source mapping"))}
  if mapping.initial_environment()!=dm_preprocess::InitialEnvironment::OriginalChecker0290{return Err(invalid("Analyze subject requires actual Original preprocessing"))}
  enum Stop{Source(&'static str),Operational(io::Error)}impl From<&'static str>for Stop{fn from(value:&'static str)->Self{Self::Source(value)}}
  let(root,entry,path,lease)=mapping.original_root_acquisition_using(&mut||crate::daemon::control::checkpoint().map_err(Stop::Operational)).map_err(|failure|match failure{Stop::Operational(actual)=>actual,Stop::Source(message)=>invalid(message)})?;
  let expected=self.header.as_ref().map(|source|source.lease()).or_else(||self.actual_root.get()).ok_or_else(||invalid("Analyze actual delivered root acquisition absent"))?;
  if entry!=self.project||path!=self.project||!lease.same_binding(expected){return Err(invalid("Analyze subject actual entry/path/acquisition differs"))}
  if self.synthetic(){for(index,(_,acquired))in mapping.source_acquisitions().enumerate(){crate::daemon::control::checkpoint()?;if index!=root&&acquired.is_some_and(|value|value.same_binding(lease)){return Err(invalid("generated Analyze header cannot substitute for an included physical source"))}}}Ok(())

 }
}
impl<P:SnapshotProvider> RecordingInputs<P>{
 pub(crate) fn issue_original_analysis_subject(&mut self,intent:&crate::policy_request::AdmittedPolicyRequest)->io::Result<Arc<OriginalAnalysisSubject>>{self.issue_original_analysis_subject_with_engine(intent,None,None)}
 pub(crate) fn issue_original_analysis_subject_engine(&mut self,intent:&crate::policy_request::AdmittedPolicyRequest,preflight:crate::runner_host::workspace_discovery::EnginePreflight)->io::Result<Arc<OriginalAnalysisSubject>>{if intent.workspace_auxiliary()!=[preflight.question()]||intent.workspace().is_none_or(|workspace|workspace.root!=preflight.discovery().contract().root||workspace.recursive_roots!=preflight.discovery().contract().recursive_roots||workspace.configuration!=preflight.configuration().0){return Err(invalid("engine preflight cannot grant another actual subject namespace/purpose"))}preflight.require(self)?;if preflight.is_empty(){return Err(invalid("empty engine selection must finish before manifest/model acquisition"))}self.issue_original_analysis_subject_with_engine(intent,Some(Arc::new(preflight)),None)}
 pub(super) fn issue_original_analysis_subject_full_registry(
  &mut self, intent: &crate::policy_request::AdmittedPolicyRequest, preflight: &super::DerivedPreflight,
 )->io::Result<Arc<OriginalAnalysisSubject>> {
  preflight.require_recording(self)?;
  if intent.workspace_auxiliary() != crate::policy_request::WorkspaceAuxiliaryQuestion::PRIVATE_FULL_REGISTRY
   || !preflight.is_joined_registry() {
   return Err(invalid("full registry subject requires its exact Derived discovery"));
  }
  self.issue_original_analysis_subject_with_engine(intent,None,Some(preflight.discovery()))
 }
 fn issue_original_analysis_subject_with_engine(&mut self,intent:&crate::policy_request::AdmittedPolicyRequest,engine_preflight:Option<Arc<crate::runner_host::workspace_discovery::EnginePreflight>>,derived_discovery:Option<&Arc<DiscoveryReceipt>>)->io::Result<Arc<OriginalAnalysisSubject>>{
  use crate::policy_request::AnalysisContext;
  if intent.analysis_context()!=Some(AnalysisContext::OriginalAnalyze0290)||self.initial_environment!=dm_preprocess::InitialEnvironment::OriginalChecker0290{return Err(invalid("full Analyze subject requires its actual admitted purpose"))}
  if self.analysis_subject.is_some(){return Err(invalid("Analyze subject already issued"))}
  let workspace=intent.workspace().ok_or_else(||invalid("Analyze subject requires actual workspace selection"))?;
  let contract=DiscoveryContract{root:workspace.root.clone(),recursive_roots:workspace.recursive_roots.clone()};
  let grep=intent.workspace_auxiliary().iter().any(|question|matches!(question,crate::policy_request::WorkspaceAuxiliaryQuestion::CheckGrep|crate::policy_request::WorkspaceAuxiliaryQuestion::CheckGrepBaseline));
  let docs=intent.workspace_auxiliary().contains(&crate::policy_request::WorkspaceAuxiliaryQuestion::DocSnippets);if docs&&grep{return Err(io::Error::new(io::ErrorKind::InvalidInput,"doc snippets and CheckGrep source roles cannot be mixed"))}
  let joined_map_edits=crate::policy_request::WorkspaceAuxiliaryQuestion::admits_map_edits_capture(intent.workspace_auxiliary())
   && workspace.recursive_roots.as_slice()==[workspace.root.join("code"),workspace.root.join("maps")];
  let discovery=if let Some(discovery)=derived_discovery{Arc::clone(discovery)}else if let Some(engine)=&engine_preflight{engine.require(self)?;Arc::clone(engine.discovery())}else{Arc::new(if crate::policy_request::WorkspaceAuxiliaryQuestion::authored_doc_ui_roots(intent.workspace_auxiliary()).is_some(){
   crate::runner_host::workspace_discovery::discover_authored_doc_ui(self,contract,&workspace.configuration,intent.workspace_auxiliary())?
  }else if docs{crate::runner_host::workspace_discovery::discover_doc_snippets(self,contract)?}else if grep{crate::runner_host::workspace_discovery::discover_check_grep(self,contract)?}else if joined_map_edits{crate::runner_host::workspace_discovery::discover_joined_map_edits(self,contract)?}else{crate::runner_host::workspace_discovery::discover(self,contract)?})};
  discovery.validate_recording(self)?;let mut charge=match &engine_preflight{Some(engine)=>engine.charge(),None=>discovery.retained_charge()?};
  let mut admit=|bytes:usize|->io::Result<()>{charge=charge.checked_add(bytes).ok_or_else(oom)?;if charge>LIMIT{return Err(oom())}Ok(())};
  if docs{if !discovery.covers_doc_snippets(&mut admit)?{return Err(invalid("doc subject lacks its complete actual mixed-source discovery"))}}else if !discovery.covers_code_dm(&mut admit)?{return Err(invalid("Analyze subject lacks complete actual CODE_DM discovery"))}
  let root=&workspace.root;admit(root.as_os_str().len().checked_mul(64).and_then(|n|n.checked_add(4096)).ok_or_else(oom)?)?;
  let canonical_root=std::fs::canonicalize(root)?;let fixed=canonical_root.join("deepquarry.dme");
  let original=self.read_policy_candidate(&fixed,LIMIT.checked_sub(charge).ok_or_else(oom)?)?;
  charge=charge.checked_add(original.as_ref().map_or(0,|bytes|bytes.capacity().saturating_add(128))).ok_or_else(oom)?;if charge>LIMIT{return Err(oom())}
  let real=original.as_ref().and_then(|bytes|std::str::from_utf8(bytes.as_slice()).ok()).is_some_and(|text|text.contains("#include"));
  if !real{
   let requested=root.join("deepquarry.dme");if requested!=fixed{
    if original.is_some(){self.record_observed_file_alias(&requested,&fixed)?;}else{
     // An absent canonical key never invents absence for another spelling.
     // Observe this exact requested leaf through the SAME typed provider.
     if !matches!(self.capture_policy_directory_bounded(&requested,false,charge)?,PolicyDirectoryListing::Missing){return Err(invalid("Analyze fixed manifest absence differs at requested spelling"))}
     self.snapshot.lock().map_err(|_|invalid("input mutex poisoned"))?.record_negative(&requested)?;
    }
   }
  }
  let issuer=Arc::new(());
  // The first marker read is raw DATA only. A real root must be physically
  // opened/read again by the Original producer; never preparse or serve it here.
  let (project,header)=if real{(fixed,None)
  }else{
   // Match Tree::load's relative slash-string ordering, not PathBuf component order.
   // Sorting references retains no duplicate path/String roster.
   let count=discovery.files().len();let rows=count.checked_mul(std::mem::size_of::<&Path>()).and_then(|n|n.checked_mul(4)).ok_or_else(oom)?;
   charge=charge.checked_add(rows).ok_or_else(oom)?;if charge>LIMIT{return Err(oom())}
   let mut paths=Vec::new();paths.try_reserve_exact(count).map_err(|_|oom())?;if paths.capacity().checked_mul(std::mem::size_of::<&Path>()).is_none_or(|n|n>rows){return Err(oom())}
   for path in discovery.files(){crate::daemon::control::checkpoint()?;let relative=path.strip_prefix(root).map_err(|_|invalid("Analyze discovery escapes root"))?;
    if !relative.starts_with("code")||path.extension()!=Some(std::ffi::OsStr::new("dm"))||relative.components().any(|part|part.as_os_str().as_encoded_bytes().first()==Some(&b'.')){continue}paths.push(path.as_path());}
   paths.sort_unstable_by(|a,b|slash_bytes(a).cmp(slash_bytes(b)));
   // Only render already discovered source paths. Normalize ordinary Windows
   // drive spelling BEFORE converting separators: //?/E:/... is a UNC spelling,
   // not the verbatim-disk spelling that the provider actually authenticated.
   // The temporary projection is funded once at its maximum live size.
   let projection_peak=paths.iter().try_fold(0usize,|peak,path|{crate::daemon::control::checkpoint()?;let bytes=path.as_os_str().len().checked_mul(128).and_then(|n|n.checked_add(8192)).ok_or_else(oom)?;Ok::<_,io::Error>(peak.max(bytes))})?;
   charge=charge.checked_add(projection_peak).ok_or_else(oom)?;if charge>LIMIT{return Err(oom())}
   let width=paths.iter().try_fold(0usize,|n,path|n.checked_add(path.as_os_str().len().checked_mul(4)?.checked_add(13)?)).ok_or_else(oom)?;
   let lexical=dm_preprocess::regions::prepared_source::PreparedSource::include_header_retained_bound(width,paths.len()).ok_or_else(oom)?;
   charge=charge.checked_add(lexical).ok_or_else(oom)?;if charge>LIMIT{return Err(oom())}
   let mut text=String::new();text.try_reserve_exact(width).map_err(|_|oom())?;if text.capacity()>4*width{return Err(oom())}
   for path in paths{crate::daemon::control::checkpoint()?;if path.as_os_str().as_encoded_bytes().iter().any(|byte|matches!(*byte,b'\n'|b'\r'|b'"')){return Err(invalid("generated literal include path has unsupported line/quote characters"))}text.push_str("#include \"");for ch in dm_preprocess::regions::filesystem_comparison_key(path).to_str().ok_or_else(||invalid("original Analyze include path is not UTF8"))?.chars(){text.push(if ch=='\\'{'/'}else{ch})}text.push_str("\"\n");}
   charge=charge.checked_sub(projection_peak).ok_or_else(oom)?;
   let directory=canonical_root.join("__dmb_original_analysis_subject__");
   if !matches!(self.capture_policy_directory_bounded(&directory,false,charge)?,PolicyDirectoryListing::Missing){return Err(invalid("generated Analyze root namespace is not genuinely absent"))}
   let project=directory.join("synth.dme");
   let header=self.prepare_subject_header(root,text.into(),HeaderReceipt{issuer:Arc::clone(&issuer),path:project.clone()})?;(project,Some(header))
  };
  let fixed_original=if real{None}else{original};
  // The issue-phase reserve includes temporary sorting/decoding and the
  // discovery already shared by WorkspaceCapture. Carry only the additional
  // subject owner into the later capture phase; do not charge that shared
  // discovery twice or keep a temporary peak as a retained real-DME payload.
  let charge=if header.is_some(){charge.checked_sub(discovery.retained_charge()?).ok_or_else(oom)?}else{std::mem::size_of::<OriginalAnalysisSubject>().checked_add(root.capacity()).and_then(|n|n.checked_add(canonical_root.capacity())).and_then(|n|n.checked_add(project.capacity())).and_then(|n|n.checked_add(512+std::mem::size_of::<dm_tree::frontend::SourceExportMapping>()+4*std::mem::size_of::<usize>())).and_then(|n|n.checked_add(fixed_original.as_ref().map_or(0,|bytes|bytes.capacity()+std::mem::size_of::<dm_resources::SharedBytesOwner>()+2*std::mem::size_of::<usize>()))).ok_or_else(oom)?};
  let charge=charge.checked_add(engine_preflight.as_ref().map_or(0,|engine|engine.charge())).ok_or_else(oom)?;if charge>LIMIT{return Err(oom())}
  let subject=Arc::new(OriginalAnalysisSubject{derived_preflight:std::sync::OnceLock::new(),engine_preflight,root:root.clone(),canonical_root,project,discovery,bound_mapping:std::sync::OnceLock::new(),fixed_original,header,actual_root:std::sync::OnceLock::new(),recorder_issuer:Arc::clone(&self.source_issuer),issuer,charge});self.analysis_subject=Some(Arc::clone(&subject));Ok(subject)
 }
 pub(crate) fn original_analysis_subject(&self)->Option<&Arc<OriginalAnalysisSubject>>{self.analysis_subject.as_ref()}
 pub(crate) fn is_generated_analysis_header(&self,path:&Path,text:&dm_preprocess::SourceText)->bool{self.analysis_subject.as_ref().and_then(|subject|subject.header_for(path)).is_some_and(|header|header.prepared().original().same_view(text))}
 pub(crate) fn validate_analysis_subject_lease(&self,path:&Path,lease:&dm_preprocess::SourceAcquisitionLease)->bool{self.analysis_subject.as_ref().is_some_and(|subject|subject.authenticates_header(path,lease))}
}
pub(crate) fn subject_receipt_storage(value:&(dyn std::any::Any+Send+Sync))->Option<(&PathBuf,&PathBuf,&Arc<()>)>{let value=value.downcast_ref::<HeaderReceipt>()?;Some((&value.path,&value.path,&value.issuer))}

fn original_manifest(lease:&dm_preprocess::SourceAcquisitionLease)->io::Result<dq_analyze::captured_untyped::ManifestRead<'_>>{use dq_analyze::captured_untyped::ManifestRead;match super::recorded_source_original(lease)?{super::RecordedSourceOriginal::Utf8(text)=>Ok(ManifestRead::CompiledOriginalBytes(text.as_bytes())),super::RecordedSourceOriginal::Bytes(bytes)=>Ok(ManifestRead::CompiledOriginalBytes(bytes.as_slice()))}}
impl OriginalAnalysisSubject{
 /// Called only by SAME recorder after the actual exact-open/read acquisition
 /// and its existing acquired resource callback both succeeded.
 pub(super) fn bind_actual_physical_root(&self,path:&Path,lease:&dm_preprocess::SourceAcquisitionLease)->io::Result<()>{
  if self.synthetic()||path!=self.project{return Ok(())}
  if !super::source_acquisition::recorded_root_lease_matches(lease,&self.recorder_issuer,path,true){return Err(invalid("actual physical root lacks its genuine exact-open recorder receipt"))}
  if let Some(prior)=self.actual_root.get(){return if prior.same_binding(lease){Ok(())}else{Err(invalid("actual physical root attempt was already bound"))}}
  self.actual_root.set(lease.clone()).map_err(|_|invalid("actual physical root binding raced"))
 }
}

impl<P:SnapshotProvider> RecordingInputs<P>{
 /// Prepare only the actual selected entry metadata, using the existing private
 /// issuer. Return project DATA, never a subject/source/EOF/completeness grant.
 /// The actual SourceProvider must still open/read a physical root afterward.
 pub fn prepare_original_analysis_entry(&mut self,request:crate::policy_request::PolicyInputRequest)->io::Result<PathBuf>{
  use crate::policy_request::{AnalysisContext,WorkspaceAuxiliaryQuestion as Q};
  let intent=request.admit().map_err(io::Error::other)?;
  if intent.analysis_context()!=Some(AnalysisContext::OriginalAnalyze0290)||intent.workspace_auxiliary()!=[Q::DerivedReads]||!intent.workspace_generators().is_empty()||!intent.files().is_empty()||!intent.search_folders().is_empty()||intent.workspace().is_none_or(|workspace|!workspace.root.is_absolute()||workspace.recursive_roots.as_slice()!=[workspace.root.join("code")]){return Err(invalid("metadata-only entry requires its exact selected Original CODE request"))}
  let subject=self.issue_original_analysis_subject(&intent)?;Ok(subject.project().to_path_buf())
 }
}

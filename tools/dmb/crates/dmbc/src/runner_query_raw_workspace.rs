//! Current source-only workspace frame, not a semantic or compiler snapshot.
//! It shares the actual capture/acquisitions, QueryAttempt and the host's QueryDb.
use std::{io,path::Path,sync::Arc};
use crate::{policy_request::{AnalysisContext,AdmittedPolicyRequest,WorkspaceAuxiliaryQuestion as Q},query_db::QueryDb,runner_host::workspace_capture::{WorkspaceCapture,RawSourceIdentity}};
#[derive(Clone)]
pub(crate) struct RawWorkspaceSnapshot{pub(super) capture:Arc<WorkspaceCapture>,pub(super) source:Arc<RawSourceIdentity>,pub(super) queries:Arc<QueryDb>,revision:u128}
impl RawWorkspaceSnapshot{
 fn issued(intent:&AdmittedPolicyRequest,capture:Arc<WorkspaceCapture>,source:Arc<RawSourceIdentity>,queries:Arc<QueryDb>)->io::Result<Self>{
  if intent.analysis_context()!=Some(AnalysisContext::OriginalAnalyze0290)||!source.purpose().question().is_some_and(|question|intent.workspace_auxiliary()==[question])||!intent.workspace_generators().is_empty()||!intent.files().is_empty()||!intent.search_folders().is_empty()||intent.workspace().is_none_or(|request|!capture.matches_request(request)){return Err(io::Error::new(io::ErrorKind::InvalidInput,"raw source frame requires its actual exclusive producer purpose"))}
  super::workspace_native_guard::NativeReadGuard::raw_owned(&capture,&source,&queries)?;
  let mut hash=xxhash_rust::xxh3::Xxh3::new();hash.update(b"raw-query-frame-not-semantic-tree-v1");hash.update(&source.revision().to_le_bytes());hash.update(&capture.policy_revision().to_le_bytes());hash.update(&capture.issuance().to_le_bytes());let revision=hash.digest128();Ok(Self{capture,source,queries,revision})
 }
 pub(crate) fn issued_registered(intent:&AdmittedPolicyRequest,capture:Arc<WorkspaceCapture>,source:Arc<RawSourceIdentity>,queries:Arc<QueryDb>,plan:&Arc<crate::runner_host::NativeCheckSelection>)->io::Result<Self>{
  if !plan.source_only()||intent.analysis_context()!=Some(AnalysisContext::OriginalAnalyze0290)||!intent.workspace_auxiliary().is_empty()||!intent.workspace_generators().is_empty()||!intent.files().is_empty()||!intent.search_folders().is_empty()||intent.workspace().is_none_or(|request|!capture.matches_request(request)){
   return Err(io::Error::new(io::ErrorKind::InvalidInput,"registered source frame requires its actual source request"))
  }
  source.require_registered_plan(plan)?;
  capture.require_registered_plan(plan)?;
  super::workspace_native_guard::NativeReadGuard::raw_owned(&capture,&source,&queries)?;
  let mut hash=xxhash_rust::xxh3::Xxh3::new();hash.update(b"registered-source-check-frame-not-semantic-v1");hash.update(&source.revision().to_le_bytes());hash.update(&capture.policy_revision().to_le_bytes());hash.update(&capture.issuance().to_le_bytes());
  Ok(Self{capture,source,queries,revision:hash.digest128()})
 }
 pub(crate) fn require_registered_source_plan(&self,plan:&Arc<crate::runner_host::NativeCheckSelection>)->io::Result<()>{
  crate::daemon::control::checkpoint()?;
  self.source.require_registered_plan(plan)?;
  self.capture.require_registered_plan(plan)?;
  super::workspace_native_guard::NativeReadGuard::raw_owned(&self.capture,&self.source,&self.queries)?;
  Ok(())
 }
 pub(crate) fn require_same_registered_frame(&self,other:&Self,plan:&Arc<crate::runner_host::NativeCheckSelection>)->io::Result<()>{
  self.require_registered_source_plan(plan)?;other.require_registered_source_plan(plan)?;
  if !Arc::ptr_eq(&self.capture,&other.capture)||!Arc::ptr_eq(&self.source,&other.source)||!Arc::ptr_eq(&self.queries,&other.queries)||self.revision!=other.revision{
   return Err(io::Error::new(io::ErrorKind::InvalidInput,"source CHECK inputs belong to another actual raw frame"))
  }Ok(())
 }
 pub(in crate::runner_host) fn bulk_prior_capture(&self)->Option<Arc<WorkspaceCapture>>{self.capture.is_sealed_raw_file_capture().then(||Arc::clone(&self.capture))}
 pub(crate) fn revision(&self)->u128{self.revision}
 pub(crate) fn source_revision(&self)->u128{self.source.revision()}
 pub(crate) fn policy_revision(&self)->u128{self.capture.policy_revision()}
 pub(crate) fn with_native_raw_tree<R>(&self,policy:dq_analyze::captured_raw_tree_pages::Policy,consume:impl FnOnce(&dq_analyze::captured_raw_tree_pages::Data,&dq_analyze::captured_raw_file::Config,&Arc<dq_analyze::captured_generator_budget::Budget>)->io::Result<R>)->Result<R,dq_analyze::captured_reactive_reads::Failure>{if policy.name()!=self.source.purpose().name(){return Err("raw source producer differs from its actual closed purpose".into())}let guard=super::workspace_native_guard::NativeReadGuard::raw_owned(&self.capture,&self.source,&self.queries)?;self.queries.with_workspace_raw_tree(&self.capture,&guard,policy,consume)}
 pub(crate) fn matches_context(&self,project:&Path,defines:&std::collections::BTreeMap<String,String>,context:Option<AnalysisContext>)->bool{context==Some(AnalysisContext::OriginalAnalyze0290)&&defines.is_empty()&&dm_preprocess::regions::canonical_path(project)==dm_preprocess::regions::canonical_path(&self.capture.root().join("deepquarry.dme"))}
 pub(crate) fn require_request(&self,request:&crate::daemon::query::QueryRequest)->io::Result<()>{
  use crate::daemon::query::SourceQuery;
  if !self.matches_context(&request.project,&request.defines,request.analysis_context)||!request.queries.is_empty()||request.engine_template.is_some()||request.bootstrap_catalog{return Err(io::Error::new(io::ErrorKind::InvalidInput,"raw source frame grants no model, checker or compiler question"))}
  let exact=|observed:&Option<String>,pin:u128|observed.as_deref().is_some_and(|value|value.eq_ignore_ascii_case(&format!("{pin:032x}")));
  if !exact(&request.expected_revision,self.revision())||!exact(&request.expected_source_revision,self.source_revision())||!exact(&request.expected_policy_revision,self.policy_revision()){return Err(io::Error::new(io::ErrorKind::InvalidInput,"raw source request revision differs from this current actual owner"))}
  if matches!(self.source.purpose(),crate::runner_host::workspace_capture::RawSourcePurpose::RegisteredSourceCheck|crate::runner_host::workspace_capture::RawSourcePurpose::AllRawFilePolicies|crate::runner_host::workspace_capture::RawSourcePurpose::DocSnippetsFullAllow|crate::runner_host::workspace_capture::RawSourcePurpose::UiActionsFullAllow|crate::runner_host::workspace_capture::RawSourcePurpose::DocUiFullAllow){return Err(io::Error::new(io::ErrorKind::InvalidInput,"raw file roster can only issue its exact selected report"))}
  if self.source.purpose().layering_no_model(){
   match request.source_queries.as_slice(){[SourceQuery::NativeWorkspaceSemanticReportPage{root,configuration,lints,limit,..}]if root==self.capture.root()&&configuration==self.capture.configuration().0&&lints.as_slice()==[self.source.purpose().name()]&&(1..=128).contains(limit)=>{self.capture.engine_no_model()?;},_=>return Err(io::Error::new(io::ErrorKind::InvalidInput,"engine no-model frame requires exactly its semantic report"))}
  }else{  match request.source_queries.as_slice(){[SourceQuery::NativeWorkspaceRawTreeReportPage{root,configuration,lints,limit,..}]if root==self.capture.root()&&configuration==self.capture.configuration().0&&lints.as_slice()==[self.source.purpose().name()]&&(1..=128).contains(limit)=>(),_=>return Err(io::Error::new(io::ErrorKind::InvalidInput,"raw producer frame requires its exact source-only report question"))}}
  super::workspace_native_guard::NativeReadGuard::raw_owned(&self.capture,&self.source,&self.queries)?;Ok(())
 }
 pub(crate) fn census(&self,census:&mut crate::heap_census::HeapCensus){self.capture.census(census);census.arc_object("query_snapshot.raw_source_identity",&self.source);census.arc_object("query_snapshot.raw_source_queries",&self.queries);self.queries.purity_census(census);self.queries.value_rejection_census(census);self.queries.answer_storage_census(census);}
}
impl super::QueryAttempt{
 pub(crate) fn current_raw_capture(&self)->Option<Arc<WorkspaceCapture>>{self.state.lock().ok().and_then(|state|state.raw_snapshot.as_ref().map(|raw|Arc::clone(&raw.capture)))}
 pub(crate) fn admit_raw_source(&mut self,intent:&AdmittedPolicyRequest,capture:Arc<WorkspaceCapture>,source:Arc<RawSourceIdentity>,queries:Arc<QueryDb>,admission:crate::request_runner::runner_freshness::WorkspacePolicyAdmission)->io::Result<(u128,u128,u128)>{
  if self.finished||self.captured||self.pending_source.is_some()||self.pending_workspace.is_some()||self.pending_diagnostic.is_some()||!Arc::ptr_eq(&capture,admission.capture()){return Err(io::Error::new(io::ErrorKind::InvalidInput,"raw source admission differs from the actual uncommitted query attempt"))}
  if admission.take_generation_inputs().is_some(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"raw source admission cannot carry a generation grant"))}
  let snapshot=RawWorkspaceSnapshot::issued(intent,capture,source,queries)?;let pins=(snapshot.revision(),snapshot.source_revision(),snapshot.policy_revision());crate::daemon::control::checkpoint()?;
  if self.enabled{let mut state=self.state.lock().unwrap_or_else(|error|error.into_inner());state.snapshot=None;state.handlers_snapshot=None;state.raw_snapshot=Some(snapshot);state.publication_pair=None;self.captured=true;}Ok(pins)
 }
 pub(crate) fn admit_registered_source_snapshot(&mut self,snapshot:RawWorkspaceSnapshot,admission:crate::request_runner::runner_freshness::WorkspacePolicyAdmission)->io::Result<(u128,u128,u128)>{
  if self.finished||self.captured||self.pending_source.is_some()||self.pending_workspace.is_some()||self.pending_diagnostic.is_some()||!Arc::ptr_eq(&snapshot.capture,admission.capture())||admission.take_generation_inputs().is_some(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"registered source admission differs from its actual uncommitted query attempt"))}
  let pins=(snapshot.revision(),snapshot.source_revision(),snapshot.policy_revision());crate::daemon::control::checkpoint()?;
  if self.enabled{let mut state=self.state.lock().unwrap_or_else(|error|error.into_inner());state.snapshot=None;state.handlers_snapshot=None;state.raw_snapshot=Some(snapshot);state.publication_pair=None;self.captured=true;}Ok(pins)
 }
 pub(crate) fn finish_raw_source(&mut self){let mut state=self.state.lock().unwrap_or_else(|error|error.into_inner());state.publication_pair=None;state.last_request_outcome="raw_source_prepared";self.finished=true;}
}

impl RawWorkspaceSnapshot{
 pub(crate) fn issued_engine_unselected(intent:&AdmittedPolicyRequest,capture:Arc<WorkspaceCapture>,source:Arc<RawSourceIdentity>,queries:Arc<QueryDb>,plan:&Arc<crate::runner_host::NativeCheckSelection>)->io::Result<Self>{
  if !plan.exclusive_engine_layering()||source.purpose()!=crate::runner_host::workspace_capture::RawSourcePurpose::EngineNoModel{return Err(io::Error::new(io::ErrorKind::InvalidInput,"actual exclusive empty Engine raw purpose required"))}
  let actual=Self::issued(intent,capture,source,queries)?;actual.require_engine_unselected_plan(plan)?;Ok(actual)
 }
 pub(crate) fn require_engine_unselected_plan(&self,plan:&Arc<crate::runner_host::NativeCheckSelection>)->io::Result<()>{
  if !plan.exclusive_engine_layering()||plan.roots()!=dq_analyze::tree::CODE_DM.roots||self.source.purpose()!=crate::runner_host::workspace_capture::RawSourcePurpose::EngineNoModel||self.capture.recursive_roots()!=[self.capture.root().join("code")]||self.capture.configuration().0!=self.capture.root().join("tools/ci/lint_scopes.toml"){return Err(io::Error::new(io::ErrorKind::InvalidInput,"actual empty Engine source frame differs from exact registered selection"))}
  let proof=self.capture.engine_no_model()?;if proof.preflight().question()!=Q::EngineLayering{return Err(io::Error::new(io::ErrorKind::InvalidInput,"empty Engine proof has another producer role"))}super::workspace_native_guard::NativeReadGuard::raw_owned(&self.capture,&self.source,&self.queries)?;Ok(())
 }
 pub(crate) fn require_same_engine_unselected_frame(&self,other:&Self,plan:&Arc<crate::runner_host::NativeCheckSelection>)->io::Result<()>{
  self.require_engine_unselected_plan(plan)?;other.require_engine_unselected_plan(plan)?;
  if !Arc::ptr_eq(&self.capture,&other.capture)||!Arc::ptr_eq(&self.source,&other.source)||!Arc::ptr_eq(&self.queries,&other.queries)||self.revision()!=other.revision()||self.source_revision()!=other.source_revision()||self.policy_revision()!=other.policy_revision(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"empty Engine ledger/frame belongs to another actual source owner"))}Ok(())
 }
}
impl super::QueryAttempt{
 pub(crate) fn admit_engine_unselected_snapshot(&mut self,snapshot:RawWorkspaceSnapshot,admission:crate::request_runner::runner_freshness::WorkspacePolicyAdmission)->io::Result<(u128,u128,u128)>{
  if self.finished||self.captured||self.pending_source.is_some()||self.pending_workspace.is_some()||self.pending_diagnostic.is_some()||snapshot.source.purpose()!=crate::runner_host::workspace_capture::RawSourcePurpose::EngineNoModel||!Arc::ptr_eq(&snapshot.capture,admission.capture())||admission.take_generation_inputs().is_some(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"empty Engine admission differs from actual uncommitted raw frame"))}snapshot.capture.engine_no_model()?;
  let pins=(snapshot.revision(),snapshot.source_revision(),snapshot.policy_revision());crate::daemon::control::checkpoint()?;
  if self.enabled{let mut state=self.state.lock().unwrap_or_else(|error|error.into_inner());state.snapshot=None;state.handlers_snapshot=None;state.raw_snapshot=Some(snapshot);state.publication_pair=None;self.captured=true;}Ok(pins)
 }
}

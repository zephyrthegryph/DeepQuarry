//! Current source-only workspace frame, not a semantic or compiler snapshot.
//! It shares the actual capture/acquisitions, QueryAttempt and the host's QueryDb.
use std::{io,path::Path,sync::Arc};
use crate::{policy_request::{AnalysisContext,AdmittedPolicyRequest,WorkspaceAuxiliaryQuestion as Q},query_db::QueryDb,runner_host::workspace_capture::{WorkspaceCapture,RawSourceIdentity}};
pub(crate) struct RawWorkspaceSnapshot{pub(super) capture:Arc<WorkspaceCapture>,pub(super) source:Arc<RawSourceIdentity>,pub(super) queries:Arc<QueryDb>,revision:u128}
impl RawWorkspaceSnapshot{
 fn issued(intent:&AdmittedPolicyRequest,capture:Arc<WorkspaceCapture>,source:Arc<RawSourceIdentity>,queries:Arc<QueryDb>)->io::Result<Self>{
  if intent.analysis_context()!=Some(AnalysisContext::OriginalAnalyze0290)||intent.workspace_auxiliary()!=[source.purpose().question()]||!intent.workspace_generators().is_empty()||!intent.files().is_empty()||!intent.search_folders().is_empty()||intent.workspace().is_none_or(|request|!capture.matches_request(request)){return Err(io::Error::new(io::ErrorKind::InvalidInput,"raw source frame requires its actual exclusive producer purpose"))}
  super::workspace_native_guard::NativeReadGuard::raw_owned(&capture,&source,&queries)?;
  let mut hash=xxhash_rust::xxh3::Xxh3::new();hash.update(b"raw-query-frame-not-semantic-tree-v1");hash.update(&source.revision().to_le_bytes());hash.update(&capture.policy_revision().to_le_bytes());hash.update(&capture.issuance().to_le_bytes());let revision=hash.digest128();Ok(Self{capture,source,queries,revision})
 }
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
 pub(crate) fn finish_raw_source(&mut self){let mut state=self.state.lock().unwrap_or_else(|error|error.into_inner());state.publication_pair=None;state.last_request_outcome="raw_source_prepared";self.finished=true;}
}

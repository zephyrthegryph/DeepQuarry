//! Current private handler-purpose host owner. This is neither SourceSnapshot
//! nor RawWorkspaceSnapshot: it grants no full model, checker or compiler role.
use std::{io,path::Path,sync::Arc};
use crate::{input_snapshot::HandlerPreparedCapture,policy_request::{AdmittedPolicyRequest,AnalysisContext,WorkspaceAuxiliaryQuestion as Q},query_db::QueryDb,request_runner::runner_freshness::HandlerPolicyAdmission};
fn invalid(message:&str)->io::Error{io::Error::new(io::ErrorKind::InvalidInput,message)}
pub(crate) struct HandlerWorkspaceSnapshot{capture:Arc<HandlerPreparedCapture>,proof:Arc<HandlerPolicyAdmission>,queries:Arc<QueryDb>,revision:u128,full_subject:Option<Arc<crate::input_snapshot::OriginalAnalysisSubject>>,full_revision:Option<u128>}
impl HandlerWorkspaceSnapshot{
 /// Issuance is possible only after the real normal input barrier issued the
 /// distinct partial admission for this exact retained current producer.
 pub(crate) fn issued(intent:&AdmittedPolicyRequest,capture:Arc<HandlerPreparedCapture>,proof:Arc<HandlerPolicyAdmission>,queries:Arc<QueryDb>)->io::Result<Self>{
  crate::daemon::control::checkpoint()?;
  if intent.analysis_context()!=Some(AnalysisContext::OriginalAnalyze0290)||intent.workspace_auxiliary()!=[Q::SemHandlers]||!intent.files().is_empty()||!intent.search_folders().is_empty()||!intent.workspace_generators().is_empty()||intent.workspace().is_none_or(|workspace|workspace.root!=capture.root())||!proof.is_current()||!Arc::ptr_eq(&capture,proof.capture())||!capture.uses_queries(&queries){return Err(invalid("handler snapshot differs from its actual exclusive current partial-purpose admission"))}
  capture.require_bound()?;
  // The key is a private current-owner query namespace, not evidence of source
  // equality or EOF. A real source revision stays separately optional below.
  let mut hash=xxhash_rust::xxh3::Xxh3::new();hash.update(b"handler-private-partial-current-query-owner-v1");hash.update(&capture.issuance().to_le_bytes());match capture.prepared().frontend(){Some(_)=>{hash.update(&[1]);hash.update(&capture.structural_inputs()?.source_revision().to_le_bytes());},None=>{hash.update(&[0]);}}
  let revision=hash.digest128();Ok(Self{capture,proof,queries,revision,full_subject:None,full_revision:None})
 }
 pub(crate) fn requires_full(&self)->bool{self.capture.prepared().subject().requires_full_model()}
 pub(super) fn bind_full_snapshot(&mut self,full:Option<&super::SourceSnapshot>)->io::Result<()>{
  if let Some(full)=full{if !self.requires_full(){return Err(invalid("unrequested full handler source cannot be bound"))}full.require_analysis_context(Some(AnalysisContext::OriginalAnalyze0290))?;self.full_subject=Some(Arc::clone(full.analysis_subject.as_ref().ok_or_else(||invalid("handler full source subject absent"))?));self.full_revision=Some(full.source_revision);}self.require_full_snapshot(full)
 }
 pub(super) fn require_full_snapshot(&self,full:Option<&super::SourceSnapshot>)->io::Result<()>{
  self.require_current()?;match(full,self.requires_full()){
   (None,false)=>Ok(()),
   (Some(full),true)=>{full.require_analysis_context(Some(AnalysisContext::OriginalAnalyze0290))?;if self.full_revision!=Some(full.source_revision)||full.analysis_subject.as_ref().zip(self.full_subject.as_ref()).is_none_or(|(actual,bound)|!Arc::ptr_eq(actual,bound))||!full.matches_original_analysis_subject(&self.capture.root().join("deepquarry.dme"))||full.native_raw_queries.as_ref().is_none_or(|queries|!Arc::ptr_eq(queries,&self.queries)){return Err(invalid("handler demanded full partition lacks its separately issued actual source/query owner"))}Ok(())},
   (None,true)=>Err(io::Error::new(io::ErrorKind::NotConnected,"handler demanded full partition remains genuinely unprepared")),
   (Some(_),false)=>Err(invalid("handler structural-only selection cannot inherit an unrequested full source frame")),
  }
 }
 pub(crate) fn require_current(&self)->io::Result<()>{crate::daemon::control::checkpoint()?;if !self.proof.is_current()||!Arc::ptr_eq(&self.capture,self.proof.capture())||!self.capture.uses_queries(&self.queries){return Err(invalid("handler current host/query/admission owner changed"))}self.capture.require_bound()}
 pub(crate) fn revision(&self)->u128{self.revision}
 pub(crate) fn source_revision(&self)->io::Result<Option<u128>>{self.require_current()?;match self.capture.prepared().frontend(){Some(_)=>Ok(Some(self.capture.structural_inputs()?.source_revision())),None=>Ok(None)}}
 pub(crate) fn capture(&self)->&Arc<HandlerPreparedCapture>{&self.capture}
 pub(crate) fn admission(&self)->&Arc<HandlerPolicyAdmission>{&self.proof}
 pub(crate) fn queries(&self)->&Arc<QueryDb>{&self.queries}
 pub(crate) fn matches_context(&self,project:&Path,defines:&std::collections::BTreeMap<String,String>,context:Option<AnalysisContext>)->bool{context==Some(AnalysisContext::OriginalAnalyze0290)&&defines.is_empty()&&dm_preprocess::regions::canonical_path(project)==dm_preprocess::regions::canonical_path(&self.capture.root().join("deepquarry.dme"))}
 pub(crate) fn census(&self,c:&mut crate::heap_census::HeapCensus){c.arc_object("query_snapshot.handlers_capture",&self.capture);c.arc_object("query_snapshot.handlers_admission",&self.proof);c.arc_object("query_snapshot.handlers_queries",&self.queries);self.capture.prepared().subject().census(c);if let Some(subject)=&self.full_subject{subject.census(c);}c.unknown("query_snapshot.handlers_capture","private partial archive/mapping owner payload is retained by the same native source host; structural facts metadata lacks complete allocator geometry");}
}

impl super::QueryAttempt{
 /// Called after the real partial freshness barrier, and after the separate
 /// full source barrier exactly when selection demanded the full partition.
 pub(crate) fn admit_handlers_source(&mut self,intent:&AdmittedPolicyRequest,capture:Arc<HandlerPreparedCapture>,proof:Arc<HandlerPolicyAdmission>,queries:Arc<QueryDb>)->io::Result<u128>{
  if self.finished||self.pending_source.is_some()||self.pending_workspace.is_some()||self.pending_diagnostic.is_some(){return Err(invalid("handler source cannot publish over unfinished source admission"))}
  let mut snapshot=HandlerWorkspaceSnapshot::issued(intent,capture,proof,queries)?;let revision=snapshot.revision();let mut state=self.state.lock().unwrap_or_else(|e|e.into_inner());
  if snapshot.requires_full(){if !self.captured{return Err(invalid("handler full partition was not actually admitted by this current query attempt"))}snapshot.bind_full_snapshot(state.snapshot.as_ref())?;}else{snapshot.bind_full_snapshot(None)?;}crate::daemon::control::checkpoint()?;
  if self.enabled{if !snapshot.requires_full(){state.snapshot=None;}state.raw_snapshot=None;state.handlers_snapshot=Some(snapshot);state.publication_pair=None;self.captured=true;}Ok(revision)
 }
 pub(crate) fn finish_handlers_source(&mut self){let mut state=self.state.lock().unwrap_or_else(|e|e.into_inner());state.publication_pair=None;state.last_request_outcome="handler_source_prepared";self.finished=true;}
}

impl HandlerWorkspaceSnapshot{
 pub(crate) fn with_prepared_report<T>(&self,request:&crate::request::BuildRequest,prepared:&crate::request::BuildOutcome,full:Option<&super::SourceSnapshot>,diagnostics:&mut impl std::io::Write,consume:impl FnOnce(&dq_analyze::captured_sem_handlers::Data,&dq_analyze::captured_raw_file::Config)->io::Result<T>)->io::Result<T>{
  use crate::request::{BuildCommand,BuildOutcome};
  let bad=||invalid("prepared handlers report differs from its actual current request/source");
  if request.command!=BuildCommand::PrepareQuery||!request.project.is_absolute()||!request.defines.is_empty()||request.engine_template.is_some()||request.bootstrap_catalog||!self.matches_context(&request.project,&request.defines,Some(AnalysisContext::OriginalAnalyze0290)){return Err(bad())}
  let intent=request.policy_inputs.as_ref().ok_or_else(bad)?.clone().admit().map_err(io::Error::other)?;
  if intent.analysis_context()!=Some(AnalysisContext::OriginalAnalyze0290)||intent.workspace_auxiliary()!=[Q::SemHandlers]||!intent.files().is_empty()||!intent.search_folders().is_empty()||!intent.workspace_generators().is_empty()||intent.workspace().is_none_or(|workspace|workspace.root!=self.capture.root()){return Err(bad())}
  let BuildOutcome::HandlersQueryPrepared{query_revision,partial_source_revision,full_source_revision,retained:true}=prepared else{return Err(bad())};
  let decode=|s:&str|u128::from_str_radix(s,16).map_err(|_|bad());
  if decode(query_revision)?!=self.revision||partial_source_revision.as_ref().map(|s|decode(s)).transpose()?!=self.source_revision()?||full_source_revision.as_ref().map(|s|decode(s)).transpose()?!=self.full_revision{return Err(bad())}
  self.require_full_snapshot(full)?;
  // Receipt, owner and current guards remain authoritative; the wire revisions
  // above only reject stale input. The partial purpose cannot become full.
  if let Some(frontend)=self.capture.prepared().frontend(){let partial=frontend.handlers_structural_source().map_err(io::Error::other)?;if let Some(notices)=partial.view().original_preprocess_notices(){crate::diagnostics::write_original_preprocess_notices(diagnostics,&notices)?;}}
  let answer=match full{
   None=>self.queries.with_handlers_structural_report(&self.capture,&self.proof,|data,configuration,_budget|consume(data,configuration)),
   Some(full)=>{let guard=full.workspace_native_read()?;let workspace=full.native_workspace.as_ref().ok_or_else(bad)?;let capture=full.native_policy_inputs.as_ref().ok_or_else(||invalid("handler full partition lacks its independently admitted declaration inputs"))?;full.replay_original_preprocess_notices(diagnostics)?;self.queries.with_handlers_full_report(&self.capture,&self.proof,workspace,&guard,capture,|data,configuration,_budget|consume(data,configuration))}
  };if answer.is_err(){return answer}self.require_full_snapshot(full)?;answer
 }
}

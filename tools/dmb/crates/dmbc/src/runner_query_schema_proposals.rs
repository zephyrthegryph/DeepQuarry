use super::*;
impl SourceSnapshot {
 pub(crate) fn require_schema_capture_binding(&self,inputs:&crate::request_runner::schema_capture::Inputs)->std::io::Result<()>{
  let mapping=self.source_mapping.as_ref().ok_or_else(||std::io::Error::other("schema proposal actual source mapping absent"))?;inputs.require_binding(mapping,self.tree.identity(),self.source_revision)
 }

 pub(crate) fn with_original_schema_proposals_report_to<T>(&self,_diagnostics:&mut impl std::io::Write,consume:impl FnOnce(&dq_analyze::captured_untyped_pages::schema_proposals::Data,&dq_analyze::captured_raw_file::Config,&Arc<dq_analyze::captured_generator_budget::Budget>)->std::io::Result<T>)->std::io::Result<T>{
  let question=crate::policy_request::WorkspaceAuxiliaryQuestion::Untyped;let capture=self.workspace_semantic_inputs(question)?;let guard=self.workspace_native_read()?;let workspace=self.native_workspace.as_ref().ok_or_else(||std::io::Error::other("schema proposals actual workspace unavailable"))?;let subject=self.analysis_subject.as_ref().ok_or_else(||std::io::Error::other("schema proposals actual full Original Analyze subject absent"))?;let queries=self.native_raw_queries.as_ref().ok_or_else(||std::io::Error::other("schema proposals actual QueryDb unavailable"))?;
  queries.with_original_workspace_schema_proposals_guard(workspace,&guard,capture,subject,None,consume)
 }
}

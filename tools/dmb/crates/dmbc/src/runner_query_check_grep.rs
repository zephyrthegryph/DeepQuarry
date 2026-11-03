//! Actual published snapshot check_grep entry. Explicit selected auxiliary
//! observations and semantic encoding evidence are required before any output.
use super::SourceSnapshot;
use std::{io,sync::Arc};
use dq_analyze::{captured_generator_budget::Budget,captured_reactive_reads::Failure};
impl SourceSnapshot{
 pub(crate) fn with_native_check_grep<R>(&self,tree:&dm_tree::SemanticTree,consume:impl FnOnce(&dq_analyze::lints::check_grep::native::Output,&Arc<Budget>)->Result<R,Failure>)->Result<R,Failure>{self.with_native_check_grep_source(tree,|queries,capture,guard,archive,evidence|queries.with_workspace_check_grep(capture,guard,archive,evidence,consume))}
 pub(crate) fn with_native_check_grep_report<R>(&self,tree:&dm_tree::SemanticTree,consume:impl FnOnce(&dq_analyze::lints::check_grep::native::Output,&dq_analyze::captured_raw_file::Scope,&Arc<Budget>)->Result<R,Failure>)->Result<R,Failure>{self.with_native_check_grep_source(tree,|queries,capture,guard,archive,evidence|queries.with_workspace_check_grep_report(capture,guard,archive,evidence,consume))}
 pub(crate) fn with_native_check_grep_baseline_report<R>(&self,tree:&dm_tree::SemanticTree,consume:impl FnOnce(&dq_analyze::lints::check_grep::native::BaselineData,&dq_analyze::captured_raw_file::Scope,&Arc<Budget>)->Result<R,Failure>)->Result<R,Failure>{self.with_native_check_grep_source(tree,|queries,capture,guard,archive,evidence|queries.with_workspace_check_grep_baseline_report(capture,guard,archive,evidence,consume))}
 fn with_native_check_grep_source<R>(&self,tree:&dm_tree::SemanticTree,consume:impl FnOnce(&crate::query_db::QueryDb,&Arc<crate::runner_host::workspace_capture::WorkspaceCapture>,&super::workspace_native_guard::NativeReadGuard<'_>,&dm_tree::frontend::BodyArchive,&crate::input_snapshot::SemanticSourceEvidence)->Result<R,Failure>)->Result<R,Failure>{
  crate::daemon::control::checkpoint()?;
  if !self.matches_tree(tree){return Err(Failure::Operational(io::Error::new(io::ErrorKind::InvalidInput,"check_grep current tree differs")))}
  self.require_semantic_source_encoding()?;
  let evidence=self.semantic_sources.as_deref().ok_or("check_grep semantic encoding evidence unavailable")?;
  let archive=self.body_archive.as_deref().filter(|archive|archive.matches_tree(tree)).ok_or("check_grep actual current body archive unavailable")?;
  let capture=self.native_workspace.as_ref().ok_or("check_grep actual workspace capture unavailable")?;
  let queries=self.native_raw_queries.as_ref().ok_or("check_grep actual compiler QueryDb unavailable")?;
  let guard=self.workspace_native_read()?;capture.check_grep_names(&guard)?;
  consume(queries,capture,&guard,archive,evidence)
 }
}

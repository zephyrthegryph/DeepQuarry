//! Selected sem/keys over the actual current workspace source frame.
use super::SourceSnapshot;
use dq_analyze::{captured_keys_pages::KeyData,captured_raw_file::Config,captured_generator_budget::Budget,captured_reactive_reads::Failure};
use std::{io,sync::Arc};
impl SourceSnapshot{
 pub(crate) fn with_native_keys<R>(&self,tree:&dm_tree::SemanticTree,consume:impl FnOnce(&KeyData,&Config,&Arc<Budget>)->io::Result<R>)->Result<R,Failure>{
  crate::daemon::control::checkpoint()?;if !self.matches_tree(tree){return Err(Failure::Operational(io::Error::new(io::ErrorKind::InvalidInput,"keys actual source tree differs")))}let capture=self.native_workspace.as_ref().ok_or("keys actual workspace source capture absent")?;let db=self.native_raw_queries.as_ref().ok_or("keys actual current QueryDb absent")?;let guard=self.workspace_native_read()?;db.with_workspace_keys(capture,&guard,consume)
 }
}

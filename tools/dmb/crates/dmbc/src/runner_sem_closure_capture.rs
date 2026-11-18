//! One private fixed authored report target, captured before the recorder epoch.
use super::*;
use std::{io,path::{Path,PathBuf}};
use crate::{request_runner::utility_capture::Capture,input_snapshot::utility_capture::{UtilityPhysicalInputs,UtilityBytes}};
pub(crate)const RELATIVE:&str="doc/rewrite/reads_closure_newly_visible.md";
pub(crate)struct CapturedClosureTarget{root:PathBuf,bytes:Option<UtilityBytes>,ready:bool}
impl CapturedClosureTarget{
 pub(crate)fn new(root:PathBuf)->Self{Self{root,bytes:None,ready:false}}
 pub(crate)fn root(&self)->&Path{&self.root}
 pub(crate)fn stamp(&self)->io::Result<Option<&crate::input_snapshot::Stamp>>{if !self.ready{return Err(io::Error::new(io::ErrorKind::InvalidInput,"closure target was not actually captured"))}Ok(self.bytes.as_ref().map(|bytes|bytes.stamp()))}
 pub(crate)fn preimage(&self)->io::Result<&[u8]>{self.stamp()?;Ok(self.bytes.as_ref().map_or(&[],|bytes|bytes.bytes()))}
}
impl Capture for CapturedClosureTarget{
 fn begin_attempt(&mut self){self.ready=false;self.bytes=None;}
 fn workspace_roster(&mut self,_:&crate::runner_host::workspace_discovery::DiscoveryReceipt,_:&dyn dm_preprocess::source_arena_credit::SourceArenaWork)->io::Result<()>{Ok(())}
 fn prepare_current(&mut self,_:&dm_tree::frontend::DiagnosticSourceView<'_>,_:&crate::runner_host::query_snapshot::SourceSnapshot,_:&dyn dm_preprocess::source_arena_credit::SourceArenaWork)->Result<(),Box<dyn std::error::Error>>{Ok(())}
 fn capture(&mut self,physical:&mut dyn UtilityPhysicalInputs)->io::Result<()>{self.ready=false;self.bytes=None;let actual=physical.read(&self.root.join(RELATIVE),dq_analyze::selected_exclusions_wire::MAX_STREAM as usize)?;self.bytes=actual;self.ready=true;Ok(())}
}

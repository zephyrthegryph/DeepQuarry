//! Pre-final required physical-byte loan on the SAME utility preparation.
//! No source/model issuer and no independent cache or resource allowance.
use crate::{input_snapshot::{RecordingInputs,SnapshotProvider,utility_capture::{UtilityPhysicalInputs,UtilityPhysicalLoan}},query_db::QueryDb};
use std::io;

pub(crate) trait Capture{
 /// Plan exact demanded files against the SAME already-admitted current
 /// snapshot outside the raw gate. No borrowed reader may escape this call.
 fn prepare_current(&mut self,view:&dm_tree::frontend::DiagnosticSourceView<'_>,snapshot:&crate::runner_host::query_snapshot::SourceSnapshot,work:&dyn dm_preprocess::source_arena_credit::SourceArenaWork)->Result<(),Box<dyn std::error::Error>>;
 /// SAME actual private discovery producer, in its immutable files() order.
 /// This is a borrow only; retaining/copying output needs its own paid keeper.
 /// No Source/Model authority is created by the roster DATA.
 fn workspace_roster(&mut self,actual:&crate::runner_host::workspace_discovery::DiscoveryReceipt,work:&dyn dm_preprocess::source_arena_credit::SourceArenaWork)->io::Result<()>;
 /// Fresh attempts must retire prior output BEFORE touching another recorder.
 fn begin_attempt(&mut self);
 /// Any retained output must own UtilityBytes and separately paid row/path
 /// storage. The real recorder moves only after this callback returns Ok.
 fn capture(&mut self,physical:&mut dyn UtilityPhysicalInputs)->io::Result<()>;
}
pub(crate) fn run<P:SnapshotProvider>(capture:&mut dyn Capture,recording:&RecordingInputs<P>,queries:&QueryDb)->io::Result<()>{
 // This existing gate supplies actual remaining raw-family headroom; its
 // Budget is a window onto that family, never a new independent allowance.
 // Its held-work loan avoids re-entering the raw gate during byte admission.
 queries.with_baseline_input_refresh(|budget,lender|{
  // Exactly the existing selected-refresh accounting contract: legacy folder
  // rows survive intermediate core-only directory publication, and the final
  // SAME recorder row receives an absolute actual census on every error path.
  let(owner,before,legacy)=recording.baseline_refresh_recorder_metadata(budget)?;
  crate::input_snapshot::RecordedPolicySourceLender::prepare_directory_metadata(lender,&owner,before)?;
  let ceiling=lender.recorder_metadata_operation_ceiling(&owner)?;
  let pending=lender.with_baseline_legacy_metadata(&owner,legacy,|lender|{
   let mut loan=UtilityPhysicalLoan{recording,queries,budget,lender};
   capture.capture(&mut loan)
  });
  let settled=match recording.late_workspace_recorder_charge().and_then(|n|n.checked_add(2*std::mem::size_of::<usize>()).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))){
   Ok(actual)=>{lender.retain_recorder_metadata_absolute(&owner,actual);if actual>ceiling{budget.deny();Err(io::ErrorKind::OutOfMemory.into())}else{Ok(())}},
   Err(later)=>{lender.retain_recorder_metadata_absolute(&owner,ceiling);budget.deny();Err(later)},
  };
  match pending{Err(first)=>Err(first),Ok(())=>settled}
 })
}

/// An owned COPY of only the actual producer's ordered path roster. No borrowed
/// Discovery Arc can outlive its containing capture grant on an error path.
/// Vector/path buffers precede the SAME actual operation resource credit.
pub(crate) struct Roster{paths:Vec<std::path::PathBuf>,_credit:dm_preprocess::source_arena_credit::SourceArenaCredit}
impl Roster{
 pub(crate) fn paths(&self)->&[std::path::PathBuf]{&self.paths}
 pub(crate) fn capture(actual:&crate::runner_host::workspace_discovery::DiscoveryReceipt,work:&dyn dm_preprocess::source_arena_credit::SourceArenaWork)->io::Result<Self>{
  work.checkpoint()?;let files=actual.files();
  let rows_upper=files.len().checked_mul(4).ok_or(io::ErrorKind::OutOfMemory)?;
  let mut bytes=rows_upper.checked_mul(std::mem::size_of::<std::path::PathBuf>()).ok_or(io::ErrorKind::OutOfMemory)?;
  let mut credit=work.reserve(bytes)?;let mut paths=Vec::new();
  paths.try_reserve_exact(files.len()).map_err(|_|io::Error::from(io::ErrorKind::OutOfMemory))?;
  if paths.capacity()>rows_upper{return Err(io::ErrorKind::OutOfMemory.into())}
  work.shrink(&mut credit,bytes.checked_sub(paths.capacity().checked_mul(std::mem::size_of::<std::path::PathBuf>()).ok_or(io::ErrorKind::OutOfMemory)?).ok_or(io::ErrorKind::OutOfMemory)?)?;
  for path in files{
   let copy=dm_preprocess::regions::copy_path_into_credit(path,work,&mut credit)?;
   paths.push(copy);
  }
  work.checkpoint()?;Ok(Self{paths,_credit:credit})
 }
}

//! Distinct handler partial-purpose admission through the normal input barrier.
//! No full Workspace/SourceFrame/Diagnostic admission is reinterpreted here.
use super::*;
use std::sync::Arc;
use crate::input_snapshot::HandlerPreparedCapture;
enum Disposition{Current,PreparationOnly,FailedFull(crate::input_snapshot::OriginalRootOpenFailure)}
pub(crate) struct HandlerPolicyAdmission{capture:Arc<HandlerPreparedCapture>,disposition:Disposition}
impl HandlerPolicyAdmission{pub(crate) fn is_current(&self)->bool{matches!(&self.disposition,Disposition::Current)}
 pub(crate) fn failed_root(&self)->Option<&crate::input_snapshot::OriginalRootOpenFailure>{match &self.disposition{Disposition::Current|Disposition::PreparationOnly=>None,Disposition::FailedFull(failed)=>Some(failed)}}
pub(crate) fn capture(&self)->&Arc<HandlerPreparedCapture>{&self.capture}
 pub(crate) fn into_shared(self)->std::io::Result<Arc<Self>>{self.capture.require_bound()?;self.capture.budget().charge(std::mem::size_of::<Self>()+2*std::mem::size_of::<usize>()).map_err(|m|std::io::Error::new(std::io::ErrorKind::OutOfMemory,m))?;Ok(Arc::new(self))}
}
impl HandlerPolicyAdmission{
 pub(crate) fn is_structural_staging(&self)->bool{matches!(&self.disposition,Disposition::PreparationOnly)}
}
pub(crate) fn admit_handlers_structural_staging<P:SnapshotProvider>(
 recording:&crate::input_snapshot::RecordingInputs<P>,capture:Arc<HandlerPreparedCapture>,queries:&crate::query_db::QueryDb,
)->std::io::Result<Arc<HandlerPolicyAdmission>>{
 capture.require_staging_recording(recording,queries)?;
 HandlerPolicyAdmission{capture,disposition:Disposition::PreparationOnly}.into_shared()
}

pub(crate) fn admit_handlers_captured_using<P:SnapshotProvider>(
 recording:&crate::input_snapshot::RecordingInputs<P>,retained:Option<&InputSnapshot>,
 provider:&crate::frozen_inputs::Inputs,generated_outputs:&std::collections::BTreeSet<std::path::PathBuf>,
 capture:Arc<HandlerPreparedCapture>,source_work:&dyn dm_preprocess::source_arena_credit::SourceArenaWork,
)->Result<(InputSnapshot,HandlerPolicyAdmission),Box<dyn Error>>{
 capture.require_bound()?;
 let inputs=admit_captured_using(recording,retained,provider,generated_outputs,source_work)?;
 if !capture.is_recorded_in(&inputs){return Err(std::io::Error::new(std::io::ErrorKind::InvalidData,"normal admitted closure omits actual handler partial producer facts").into())}
 capture.require_bound()?;Ok((inputs,HandlerPolicyAdmission{capture,disposition:Disposition::Current}))
}

/// This never calls the normal current-source freshness barrier and cannot
/// publish a warm source. The private actual failed-reader receipt authenticates
/// the same-attempt partial prefix and is strongly retained until delivery ends.
pub(crate) fn admit_handlers_actual_failed_full<P:SnapshotProvider>(inputs:&crate::input_snapshot::RecordingInputs<P>,capture:Arc<HandlerPreparedCapture>,queries:&crate::query_db::QueryDb,failed:crate::input_snapshot::OriginalRootOpenFailure)->std::io::Result<Arc<HandlerPolicyAdmission>>{
 capture.require_failed_full_prefix(inputs,queries,&failed)?;HandlerPolicyAdmission{capture,disposition:Disposition::FailedFull(failed)}.into_shared()
}

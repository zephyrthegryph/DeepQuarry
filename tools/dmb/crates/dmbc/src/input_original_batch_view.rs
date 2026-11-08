//! Statically safe borrowed view of the SAME real recorder. No new capture,
//! source issuer, resource counter, preparation or snapshot is manufactured.
use super::{RecordingInputs,SnapshotProvider};
use dm_preprocess::{SourceProvider,SourceChanges,SourceText};
use std::{io,path::{Path,PathBuf},sync::Arc,collections::BTreeSet};
pub(crate) struct OriginalBatchRecordingView<'a,P:SnapshotProvider+Sync>{
    inputs:&'a RecordingInputs<P>,
    changes:Option<&'a(dyn SourceChanges+Sync)>,
}
impl<P:SnapshotProvider+Sync> RecordingInputs<P>{
    pub(crate) fn original_batch_view<'a>(&'a self,changes:Option<&'a(dyn SourceChanges+Sync)>)->OriginalBatchRecordingView<'a,P>{OriginalBatchRecordingView{inputs:self,changes}}
}
impl<'a,P:SnapshotProvider+Sync> OriginalBatchRecordingView<'a,P>{
    pub(super) fn inputs(&self)->&'a RecordingInputs<P>{self.inputs}
}
impl<P:SnapshotProvider+Sync> dm_preprocess::regions::OriginalRootOpenObserver for OriginalBatchRecordingView<'_,P>{
    fn before_root_read_using(&self,provider:&dyn SourceProvider,path:&Path,work:&dyn dm_preprocess::source_arena_credit::SourceArenaWork,a:&dm_syntax::SettingAdmission<'_>)->io::Result<()>{self.inputs.root_failure_capture.before_recording_view(self,provider,path,work,a)}
    fn actual_root_open_failed_using(&self,failed:dm_preprocess::regions::OriginalRootOpenFailureLoan<'_,'_>){self.inputs.root_failure_capture.failed_recording_view(self,failed)}
}
impl<P:SnapshotProvider+Sync> SourceProvider for OriginalBatchRecordingView<'_,P>{
    fn original_batch_source(&self)->io::Result<Option<&(dyn SourceProvider+Sync)>>{Ok(Some(self))}
    fn original_root_open_observer(&self)->Option<&dyn dm_preprocess::regions::OriginalRootOpenObserver>{self.inputs.root_failure_capture.is_armed().then_some(self)}
    fn initial_environment(&self)->dm_preprocess::InitialEnvironment{self.inputs.initial_environment()}
    fn path_presence_admitted(&self,path:&Path,work:&dyn dm_preprocess::source_arena_credit::SourceArenaWork)->io::Result<bool>{self.inputs.path_presence_admitted(path,work)}
    fn read(&self,path:&Path)->Result<String,String>{SourceProvider::read(self.inputs,path)}
    fn original_raw_source_checked(&self,path:&Path,max:usize,before:&mut dyn FnMut(usize,bool,bool)->io::Result<()>)->io::Result<Option<dm_preprocess::SourceAcquisitionLease>>{self.inputs.original_raw_source_checked(path,max,before)}
    fn original_raw_source_admitted(&self,path:&Path,max:usize,before_read:&mut dyn FnMut(usize)->io::Result<()>,before_decode:&mut dyn FnMut(dm_preprocess::OriginalRawAllocationPlan<'_>)->io::Result<()>,acquired:&mut dyn FnMut(&dm_preprocess::SourceAcquisitionLease)->io::Result<()>)->io::Result<Option<dm_preprocess::SourceAcquisitionLease>>{self.inputs.original_raw_source_admitted(path,max,before_read,before_decode,acquired)}
    fn original_raw_source_open_admitted(&self,path:&Path,max:usize,work:&dyn dm_preprocess::source_arena_credit::SourceArenaWork,after_open:&mut dyn FnMut()->io::Result<dm_preprocess::OriginalRawOpenDecision>,before_read:&mut dyn FnMut(usize)->io::Result<()>,before_decode:&mut dyn FnMut(dm_preprocess::OriginalRawAllocationPlan<'_>)->io::Result<()>,acquired:&mut dyn FnMut(&dm_preprocess::SourceAcquisitionLease)->io::Result<()>)->io::Result<dm_preprocess::OriginalRawReadOutcome>{self.inputs.original_raw_source_open_admitted(path,max,work,after_open,before_read,before_decode,acquired)}
 fn original_raw_source_open_owned_admitted(&self,path:&Path,max:usize,work:&dyn dm_preprocess::source_arena_credit::SourceArenaWork,after_open:&mut dyn FnMut()->io::Result<dm_preprocess::OriginalRawOpenDecision>,before_read:&mut dyn FnMut(usize)->io::Result<()>,before_decode:&mut dyn FnMut(dm_preprocess::OriginalRawAllocationPlan<'_>)->io::Result<()>,fund_text:&dm_preprocess::source_arena_credit::OriginalReadTextFunding<'_>,acquired:&mut dyn FnMut(&dm_preprocess::SourceAcquisitionLease)->io::Result<()>)->io::Result<dm_preprocess::OriginalRawReadOutcome>{self.inputs.original_raw_source_open_owned_admitted(path,max,work,after_open,before_read,before_decode,fund_text,acquired)}
    fn original_source_bytes<'a>(&'a self,lease:&'a dm_preprocess::SourceAcquisitionLease)->io::Result<Option<&'a[u8]>>{self.inputs.original_source_bytes(lease)}
    fn original_geometry_byte_loan<'a>(&'a self, lease: &'a dm_preprocess::SourceAcquisitionLease)
        -> io::Result<Option<dm_preprocess::OriginalGeometryByteLoan<'a>>> {
        self.inputs.original_geometry_byte_loan(lease).map(Some)
    }
    fn acquired_source(&self,path:&Path)->Result<Option<dm_preprocess::AcquiredSource>,String>{self.inputs.acquired_source(path)}
    fn source_acquisition(&self,path:&Path,text:&SourceText)->Option<dm_preprocess::AcquiredSource>{self.inputs.source_acquisition(path,text)}
    fn retained_nontext(&self,path:&Path,prior:Option<&dm_preprocess::RetainedText>)->Result<Option<dm_preprocess::RetainedText>,String>{self.inputs.retained_nontext(path,prior)}
    fn prepared_source(&self,path:&Path)->Option<Arc<dm_preprocess::regions::prepared_source::PreparedSource>>{self.inputs.prepared_source(path)}
    fn revision(&self)->Option<u64>{self.changes.map(SourceChanges::revision)}
    fn changes_since(&self,revision:u64)->Option<Arc<BTreeSet<PathBuf>>>{self.changes?.changes_since(revision)}
    fn fingerprint_read(&self,path:&Path,text:&str)->[u8;32]{self.inputs.fingerprint_read(path,text)}
    fn fingerprint(&self,path:&Path)->Result<[u8;32],String>{self.inputs.fingerprint(path)}
}

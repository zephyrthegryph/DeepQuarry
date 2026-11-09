//! Armed actual-recorder root-open attempt. Not generic Sem=None or a graph.
use super::*;use std::sync::{Arc,Mutex,OnceLock};
use dm_preprocess::{SourceProvider,source_arena_credit::SourceArenaWork,regions::{OriginalRootOpenObserver,OriginalRootOpenFailureLoan}};
struct Attempt{
 root:PathBuf,issuer:Arc<()>,started:OnceLock<()>,pending:OnceLock<(OriginalOpenFacts,OriginalOpenFacts)>,failed:OnceLock<OriginalOpenFacts>,queries:crate::query_db::NativeQueryOwnerIdentity,work_address:usize,provider_address:usize,
 // Actual facts/status/path drop before the SAME admitted storage credit.
 credit:dm_syntax::SettingRootLease,
}
#[derive(Default)]pub(super) struct RootFailureCapture{state:Mutex<Option<Arc<Attempt>>>}
impl RootFailureCapture{
 pub(super) fn is_armed(&self)->bool{self.state.lock().ok().is_some_and(|state|state.is_some())}
 /// Private SAME-recorder failure transaction. This alone grants nothing: the
 /// subsequent opaque root-only producer loan must also seal it.
 pub(super) fn note_recorded_failure(&self,path:&Path,before:&OriginalOpenFacts,current:&OriginalOpenFacts){let Ok(state)=self.state.lock()else{return};let Some(attempt)=state.as_ref()else{return};if path!=attempt.root||attempt.started.get().is_none(){return}let _=attempt.pending.set((before.clone(),current.clone()));}
}
/// Private producer evidence, not CODE EOF, a semantic model or report grant.
/// No from_error/from_None/from_hash constructor exists.
pub(crate) struct OriginalRootOpenFailure{attempt:Arc<Attempt>}
impl OriginalRootOpenFailure{
 pub(crate) fn root(&self)->&Path{&self.attempt.root}
 pub(crate) fn require_recording<P:SnapshotProvider>(&self,inputs:&RecordingInputs<P>,queries:&crate::query_db::QueryDb)->io::Result<()>{
  if !Arc::ptr_eq(&self.attempt.issuer,&inputs.source_issuer)||!self.attempt.queries.matches(queries){return Err(invalid("actual root failure belongs to another recorder/resource owner"))}
  let actual=self.attempt.failed.get().ok_or_else(||invalid("root attempt has no opaque actual failed-reader loan"))?;let snapshot=inputs.snapshot.lock().map_err(|_|invalid("root failure recording poisoned"))?;
  if !snapshot.opened_reads.same_owner(actual)||actual.get(&self.attempt.root).is_none_or(|status|status.is_readable()){return Err(invalid("actual failed-root reader facts changed"))}Ok(())
 }
 pub(crate) fn visit_storage(&self,mut visit:impl FnMut(usize,usize,usize)){
  let fixed=std::mem::size_of::<Attempt>()+2*std::mem::size_of::<usize>();visit(Arc::as_ptr(&self.attempt)as usize,fixed,fixed);visit(self.attempt.root.as_os_str().as_encoded_bytes().as_ptr()as usize,self.attempt.root.as_os_str().as_encoded_bytes().len(),self.attempt.root.capacity());if let Some((before,current))=self.attempt.pending.get(){before.visit_storage(&mut visit);current.visit_storage(&mut visit)}if let Some(failed)=self.attempt.failed.get(){failed.visit_storage(&mut visit)}self.attempt.credit.visit_counter_storage(|p,n|visit(p,n,n));self.attempt.queries.visit_storage(visit);
 }
}
impl<P:SnapshotProvider> RecordingInputs<P>{
 pub(crate) fn arm_original_root_attempt(&self,root:&Path,queries:&crate::query_db::QueryDb,a:&dm_syntax::SettingAdmission<'_>)->io::Result<()>{
  if !root.is_absolute()||self.initial_environment!=dm_preprocess::InitialEnvironment::OriginalChecker0290{return Err(invalid("root attempt requires exact absolute Original root/context"))}
  let mut state=self.root_failure_capture.state.lock().map_err(|_|invalid("root attempt state poisoned"))?;if state.is_some(){return Err(invalid("root attempt is already armed"))}
  let identity=queries.native_query_owner_identity();if !identity.matches_admission(a){return Err(invalid("root attempt uses another actual syntax admission owner"))}
  let path_bound=root.as_os_str().len().checked_mul(4).ok_or(io::ErrorKind::OutOfMemory)?;let bound=path_bound.checked_add(std::mem::size_of::<Attempt>()+4*std::mem::size_of::<usize>()+crate::query_db::NativeQueryOwnerIdentity::retained_charge()).ok_or(io::ErrorKind::OutOfMemory)?;
  let credit=a.reserve(bound).map_err(|e|a.take_operational_error().unwrap_or(e))?;let mut path=PathBuf::new();path.try_reserve_exact(root.as_os_str().len()).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;path.push(root);if path.capacity()>path_bound{return Err(io::ErrorKind::OutOfMemory.into())}
  let work:&dyn SourceArenaWork=queries;
  *state=Some(Arc::new(Attempt{root:path,issuer:Arc::clone(&self.source_issuer),started:OnceLock::new(),pending:OnceLock::new(),failed:OnceLock::new(),queries:identity,work_address:work as*const dyn SourceArenaWork as*const ()as usize,provider_address:self as*const Self as usize,credit}));Ok(())
 }
 pub(crate) fn take_actual_root_open_failure(&self)->Option<OriginalRootOpenFailure>{let mut state=self.root_failure_capture.state.lock().ok()?;if !state.as_ref().is_some_and(|attempt|attempt.failed.get().is_some()){return None}Some(OriginalRootOpenFailure{attempt:state.take()?})}
}
impl RootFailureCapture{
 fn before_exact(&self,provider:&dyn SourceProvider,path:&Path,work:&dyn SourceArenaWork,a:&dm_syntax::SettingAdmission<'_>,recorder_address:usize,provider_address:usize)->io::Result<()>{
  let state=self.state.lock().map_err(|_|invalid("root attempt state poisoned"))?;let attempt=state.as_ref().ok_or_else(||invalid("root observer was not actually armed"))?;
  if recorder_address!=attempt.provider_address||provider as*const dyn SourceProvider as*const ()as usize!=provider_address||path!=attempt.root||!attempt.queries.matches_admission(a)||!a.matches_lease_domain(&attempt.credit)||work as*const dyn SourceArenaWork as*const ()as usize!=attempt.work_address{return Err(invalid("root observer recorder/view/resource owner/path differs from real armed attempt"))}
  attempt.started.set(()).map_err(|_|invalid("actual root observer was already consumed"))
 }
 fn failed_exact(&self,failed:OriginalRootOpenFailureLoan<'_,'_>,recorder_address:usize,provider_address:usize){
  // No allocation, cancellation checkpoint or replaceable error after the real
  // failed-open IO. The private recorder note plus opaque loan are both needed.
  let Ok(state)=self.state.lock()else{return};let Some(attempt)=state.as_ref()else{return};
  if recorder_address!=attempt.provider_address||attempt.started.get().is_none()||failed.provider()as*const dyn SourceProvider as*const ()as usize!=provider_address||failed.path()!=attempt.root||!attempt.queries.matches_admission(failed.admission())||!failed.admission().matches_lease_domain(&attempt.credit)||failed.source_work()as*const dyn SourceArenaWork as*const ()as usize!=attempt.work_address{return}
  let Some((_,current))=attempt.pending.get()else{return};if current.get(failed.path()).is_none_or(|status|status.is_readable()){return}
  let _=attempt.failed.set(current.clone());
 }
 pub(super) fn before_recording_view<P:SnapshotProvider+Sync>(&self,view:&super::original_batch_view::OriginalBatchRecordingView<'_,P>,provider:&dyn SourceProvider,path:&Path,work:&dyn SourceArenaWork,a:&dm_syntax::SettingAdmission<'_>)->io::Result<()>{
  // Only this closed statically safe adapter can authenticate its borrowed
  // recorder. An arbitrary forwarding SourceProvider gets no alias grant.
  if !std::ptr::eq(self,&view.inputs().root_failure_capture){return Err(invalid("root observer view belongs to another recorder slot"))}
  self.before_exact(provider,path,work,a,view.inputs()as*const RecordingInputs<P>as usize,view as*const super::original_batch_view::OriginalBatchRecordingView<'_,P>as usize)
 }
 pub(super) fn failed_recording_view<P:SnapshotProvider+Sync>(&self,view:&super::original_batch_view::OriginalBatchRecordingView<'_,P>,failed:OriginalRootOpenFailureLoan<'_,'_>){
  if !std::ptr::eq(self,&view.inputs().root_failure_capture){return}
  self.failed_exact(failed,view.inputs()as*const RecordingInputs<P>as usize,view as*const super::original_batch_view::OriginalBatchRecordingView<'_,P>as usize)
 }
}
impl OriginalRootOpenObserver for RootFailureCapture{
 fn before_root_read_using(&self,provider:&dyn SourceProvider,path:&Path,work:&dyn SourceArenaWork,a:&dm_syntax::SettingAdmission<'_>)->io::Result<()>{let address=provider as*const dyn SourceProvider as*const ()as usize;self.before_exact(provider,path,work,a,address,address)}
 fn actual_root_open_failed_using(&self,failed:OriginalRootOpenFailureLoan<'_,'_>){let address=failed.provider()as*const dyn SourceProvider as*const ()as usize;self.failed_exact(failed,address,address)}
}

impl OriginalRootOpenFailure{
 /// Same-attempt prefix inspection only; this cannot issue current freshness.
 /// Only the exact failed root may differ between captured prefix and current
 /// open ledger, and its earlier value must belong to the opaque attempt's
 /// genuine before-open owner. All other observations remain exact subsets.
 pub(super) fn require_handler_prefix<P:SnapshotProvider>(&self,inputs:&RecordingInputs<P>,queries:&crate::query_db::QueryDb,prefix:&InputSnapshot,extra_ordinary:impl FnOnce(&InputSnapshot)->bool)->io::Result<()>{
  self.require_recording(inputs,queries)?;
  let before=&self.attempt.pending.get().ok_or_else(||invalid("failed root has no actual observation transaction"))?.0;
  let current=inputs.snapshot.lock().map_err(|_|invalid("handler failed-prefix ledger poisoned"))?;
  let ordinary=prefix.files.iter().all(|(p,v)|current.files.get(p)==Some(v))&&prefix.folders.iter().all(|(p,v)|current.folders.get(p)==Some(v))&&prefix.policy_directories.iter().all(|(p,v)|current.policy_directories.get(p)==Some(v))&&prefix.negative_files.is_subset(&current.negative_files)&&prefix.generated_outputs.is_subset(&current.generated_outputs);
  let opened=prefix.opened_reads.iter().all(|(p,v)|if p==&self.attempt.root{before.get(p).as_ref()==Some(v)}else{current.opened_reads.get(p).as_ref()==Some(v)});
  if !ordinary||!extra_ordinary(&current)||!opened||!prefix.path_presence.iter().all(|(p,v)|current.path_presence.get(p).as_ref()==Some(v))||!prefix.original_payloads.iter().all(|(p,v)|current.original_payloads.get(p).as_ref()==Some(v)){return Err(invalid("failed handler prefix differs from its exact before/current recorded observations"))}Ok(())
 }
}

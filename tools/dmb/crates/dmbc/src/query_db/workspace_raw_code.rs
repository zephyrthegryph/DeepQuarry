//! Borrowed original CODE_DM production over the existing workspace capture.
//! No captured raw Tree/model, acquisition, per-file query or retained text view.
use super::*;
use dq_analyze::{captured_generator_budget::Budget,captured_reactive_reads::Failure};
use dq_analyze::captured_raw_file::RawPolicyViews;

/// Request-local reader; only an actual admitted workspace guard constructs it.
/// A false visitor result stops a search and does not assert complete coverage.
pub(crate) struct WorkspaceCodeReader<'a,'scope>{
 db:&'a QueryDb,capture:&'a Arc<WorkspaceCapture>,scope:&'a NativeReadGuard<'scope>,
 inventory:&'a ResourceInventory,budget:Arc<Budget>,fixed:usize,
}

/// Only the exhausted original loop can construct this proof. A stopped
/// name-search cannot be mistaken for complete raw input coverage.
pub(crate) enum WorkspaceCodeTraversal<'reader,'capture,'scope>{Stopped,Completed(WorkspaceCodeCompletion<'reader,'capture,'scope>)}
pub(crate) struct WorkspaceCodeCompletion<'reader,'capture,'scope>{reader:&'reader WorkspaceCodeReader<'capture,'scope>,inputs:&'reader dm_analysis::policy_inputs::PolicyInputs}
/// Compare-only original workspace/discovery/config owner for retained facts.
/// No original bytes, source views or discovery payloads are retained strongly.
pub(crate) struct WorkspaceCodeWitness{capture:Weak<WorkspaceCapture>}
impl WorkspaceCodeWitness{
 pub(crate) fn matches(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,inputs:&dm_analysis::policy_inputs::PolicyInputs)->Result<bool,Failure>{
  crate::daemon::control::checkpoint()?;capture.require_scope(scope)?;
  if !capture.matches_source(inputs.mapping(),inputs.revision().compiler_source){return Err(Failure::Operational(invalid("workspace witness/current semantic source frame differs")))}
  let same=self.capture.strong_count()!=0&&Weak::ptr_eq(&self.capture,&Arc::downgrade(capture));
  crate::daemon::control::checkpoint()?;Ok(same)
 }
 pub(crate) fn visit_storage(&self,mut visit:impl FnMut(usize,usize)){if !self.capture.as_ptr().is_null(){visit(self.capture.as_ptr()as usize,std::mem::size_of::<WorkspaceCapture>()+2*std::mem::size_of::<usize>())}}
}
impl WorkspaceCodeTraversal<'_,'_,'_>{
 pub(crate) fn into_witness(self)->Result<Option<WorkspaceCodeWitness>,Failure>{match self{Self::Stopped=>Ok(None),Self::Completed(completed)=>completed.into_witness().map(Some)}}
}
impl WorkspaceCodeCompletion<'_,'_,'_>{
 pub(crate) fn into_witness(self)->Result<WorkspaceCodeWitness,Failure>{
  self.reader.require_policy_inputs(self.inputs)?;self.reader.require_full_code_discovery()?;
  self.reader.budget.charge(std::mem::size_of::<WorkspaceCodeWitness>()+std::mem::size_of::<WorkspaceCapture>()+2*std::mem::size_of::<usize>()).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;
  let witness=WorkspaceCodeWitness{capture:Arc::downgrade(self.reader.capture)};
  self.reader.checkpoint()?;Ok(witness)
 }
}

impl<'capture,'scope> WorkspaceCodeReader<'capture,'scope>{
 pub(crate) fn for_each_code_file_completed<'reader>(&'reader self,inputs:&'reader dm_analysis::policy_inputs::PolicyInputs,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<WorkspaceCodeTraversal<'reader,'capture,'scope>,Failure>{
  self.require_policy_inputs(inputs)?;self.require_full_code_discovery()?;
  if !self.for_each_code_file(visit)?{return Ok(WorkspaceCodeTraversal::Stopped)}
  self.require_policy_inputs(inputs)?;self.require_full_code_discovery()?;Ok(WorkspaceCodeTraversal::Completed(WorkspaceCodeCompletion{reader:self,inputs}))
 }

 fn require_full_code_discovery(&self)->Result<(),Failure>{
  self.checkpoint()?;
  let full=self.capture.covers_code_dm(&mut|bytes|self.budget.charge(bytes).map_err(|message|io::Error::new(io::ErrorKind::OutOfMemory,message)))?;
  if !full{return Err(Failure::from("complete original recursive CODE_DM discovery is required"))}self.checkpoint()?;Ok(())
 }
 pub(crate) fn require_policy_inputs(&self,inputs:&dm_analysis::policy_inputs::PolicyInputs)->Result<(),Failure>{
  self.checkpoint()?;if !self.capture.matches_source(inputs.mapping(),inputs.revision().compiler_source){return Err(Failure::Operational(invalid("workspace raw/semantic inputs have different original source frames")))}Ok(())
 }
 pub(crate) fn budget(&self)->&Arc<Budget>{&self.budget}
 pub(crate) fn root(&self)->&std::path::Path{self.capture.root()}
 pub(crate) fn configuration(&self)->(&std::path::Path,Option<&[u8]>){self.capture.configuration()}
 fn checkpoint(&self)->Result<(),Failure>{let _=self.inventory.bytes();crate::daemon::control::checkpoint()?;self.capture.require_scope(self.scope)?;self.budget.require().map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))}
 pub(crate) fn for_each_code_file(&self,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{
  self.checkpoint()?;let mut start=0;
  while start<self.capture.file_count(){
   self.checkpoint()?;
   let fixed=self.fixed.checked_add(self.budget.used()).ok_or_else(||Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"workspace code fold accounting overflow")))?;
   let available=self.db.workspace_input_headroom_locked(fixed)?;
   let(files,end)=self.capture.code_page(self.scope,start,PAGE_FILES,available)?;
   if end<=start{return Err(Failure::Operational(invalid("original code page made no progress")))}
   // Sum is deliberately conservative for aliased sources; the existing page
   // constructor independently admits its exact union before normalization.
   let live=files.iter().try_fold(files.capacity().checked_mul(std::mem::size_of::<CurrentFile>()).ok_or_else(||invalid("code page metadata overflow"))?,|n,file|n.checked_add(file.charge).and_then(|n|n.checked_add(file.path.capacity())).ok_or_else(||invalid("code page live ownership overflow")))?;
   for file in &files{
    self.checkpoint()?;
    let Some(text)=&file.text else{continue};
    let pending=dq_analyze::captured_raw_file::with_original_policy_file(self.capture.root(),&file.path,text.clone(),live,&self.budget,visit);
    if matches!(&pending,Err(Failure::Operational(_))){return pending}
    self.checkpoint()?;if !pending?{return Ok(false)}
   }
   drop(files);start=end;
  }
  self.checkpoint()?;Ok(true)
 }
}
impl QueryDb{
 /// Execute policy-only folds over actual discovered original files. Complete
 /// discovery/config/source evidence remains on the existing WorkspaceCapture.
 /// The operation budget is funded from this SAME raw-family inventory and
 /// limits. No result or source authority is cached by this entry.
 pub(crate) fn with_workspace_code_pages<R>(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,visit:impl FnOnce(&WorkspaceCodeReader<'_,'_>)->Result<R,Failure>)->Result<R,Failure>{
  crate::daemon::control::checkpoint()?;capture.require_scope(scope)?;
  if !scope.uses_queries(self){return Err(Failure::Operational(invalid("original code pages need the current compiler QueryDb")))}
  let _gate=self.raw_policy.gate.lock().unwrap_or_else(|e|e.into_inner());
  self.raw_prune_locked(std::time::Instant::now());
  let inventory=self.workspace_resource_inventory_locked()?;
  let fixed=capture.retained_charge()?.checked_add(inventory.coordination_charge(0)?).and_then(|n|n.checked_add(std::mem::size_of::<WorkspaceCodeReader<'_,'_>>()+PAGE_FILES*std::mem::size_of::<CurrentFile>()+4096)).ok_or_else(||Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"workspace code fixed accounting overflow")))?;
  let input=self.workspace_input_headroom_locked(fixed)?;
  let results=RESULT_BOUND.checked_sub(self.raw_policy.charge.load(Ordering::Relaxed)).and_then(|n|n.checked_sub(inventory.bytes())).and_then(|n|n.checked_sub(aggregate::REPORT_RESERVE)).ok_or_else(||Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"workspace code result-family headroom exhausted")))?;
  let budget=Budget::new(input.min(results)).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;
  let reader=WorkspaceCodeReader{db:self,capture,scope,inventory:&inventory,budget,fixed};
  let pending=visit(&reader);
  if matches!(&pending,Err(Failure::Operational(_))){return pending}
  reader.checkpoint()?;pending
 }
}

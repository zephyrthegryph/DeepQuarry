//! One resource-only allocation role in the EXISTING raw input-family ledger.
//! No query kind, semantic cache, cap or independent domain counter is added.
use super::*;
use dm_preprocess::source_arena_credit::{SourceArenaCredit,SourceArenaCreditOwner,SourceArenaWork};
use std::sync::atomic::{AtomicUsize,Ordering};
/// Only actual reservation size and a WEAK identity of the existing Admission.
/// No QueryDb, ledger or source/model owner is retained by an escaped SourceText.
pub(super) struct Allocation{bytes:AtomicUsize,domain:Weak<crate::query_db::raw_policy::Admission>}
impl Allocation{
 pub(super) fn metadata_bytes()->usize{std::mem::size_of::<Self>()+2*std::mem::size_of::<usize>()}
 pub(super) fn retained_bytes(&self)->io::Result<usize>{Self::metadata_bytes().checked_add(self.bytes.load(Ordering::Acquire)).ok_or_else(oom)}
 pub(super) fn store_reserved_bytes(&self,bytes:usize){self.bytes.store(bytes,Ordering::Release);}
 fn same_domain(&self,domain:&Weak<crate::query_db::raw_policy::Admission>)->bool{Weak::ptr_eq(&self.domain,domain)}
}
/// Concrete strong handles cover temporary ledger upgrades and registration
/// failure before an owner enters the public, erased credit handles.
pub(super) struct AllocationHandle(Option<Arc<Allocation>>);
impl AllocationHandle {
    pub(super) fn new(owner: Arc<Allocation>) -> Self {
        Self(Some(owner))
    }
    pub(super) fn arc(&self) -> &Arc<Allocation> {
        self.0.as_ref().expect("live native allocation handle")
    }
    fn register(mut self, ledger: &mut super::raw_input_credits::Ledger) -> io::Result<SourceArenaCredit> {
        ledger.register_source_arena(self.arc())?;
        Ok(SourceArenaCredit::from_resource_owner(self.0.take().expect("registered native allocation")))
    }
}
impl Drop for AllocationHandle {
    fn drop(&mut self) {
        if let Some(owner) = self.0.take() {
            owner.release();
        }
    }
}
impl SourceArenaCreditOwner for Allocation{
 fn as_any(&self)->&dyn std::any::Any{self}
 fn release(self: Arc<Self>) {
    // Every strong handle uses this path. Extraction relinquishes the Arc's
    // implicit Weak before payload drop. Explicit ledger Weak references
    // retain their control allocation independently.
    drop(Arc::into_inner(self));
 }

 fn reserved_bytes(&self)->usize{self.bytes.load(Ordering::Acquire)}
 fn visit_storage(&self,visit:&mut dyn FnMut(usize,usize)){visit(std::ptr::from_ref(self)as usize,Self::metadata_bytes())}
}
fn oom()->io::Error{io::Error::new(io::ErrorKind::OutOfMemory,"native source arena exceeds existing shared input-family allowance")}
fn no_source_room(_requested:usize,_ledger_live:usize,_remaining:Option<usize>)->io::Error{
 #[cfg(debug_assertions)]
 if std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some(){
  eprintln!("ORIGINAL_SOURCE_INPUT_LIMIT requested={_requested} source_ledger_reserved={_ledger_live} shared_input_headroom={_remaining:?}");
 }
 oom()
}
fn wrong()->io::Error{io::Error::new(io::ErrorKind::InvalidInput,"source arena credit was not issued in this native input family")}
fn allocation<'a>(db:&QueryDb,credit:&'a SourceArenaCredit)->io::Result<&'a Allocation>{
 let actual=credit.owner().as_any().downcast_ref::<Allocation>().ok_or_else(wrong)?;
 if !actual.same_domain(&Arc::downgrade(&db.raw_policy.admission)){return Err(wrong())}Ok(actual)
}
pub(super) fn funded_parts(text:&SourceText,domain:Option<&Weak<crate::query_db::raw_policy::Admission>>)->(bool,bool){
 let Some(expected)=domain else{return(false,false)};
 let control=text.source_arena_control_credit().and_then(|credit|credit.owner().as_any().downcast_ref::<Allocation>()).is_some_and(|actual|actual.same_domain(expected));
 let payload=text.source_arena_payload_credit().and_then(|credit|credit.owner().as_any().downcast_ref::<Allocation>()).is_some_and(|actual|actual.same_domain(expected));
 (control,payload)
}
impl QueryDb{
 /// Convert ONE actual same-family read reservation into the actual acquired
 /// source backing observations, atomically under the existing family gate.
 /// No gate is held across caller IO/decode/driver work. This is resource
 /// accounting only: the lease still requires its actual source issuer proof.
 pub(crate) fn adopt_original_raw_read(&self,credit:&mut SourceArenaCredit,source:&dm_preprocess::SourceAcquisitionLease)->io::Result<()>{
  let actual=allocation(self,credit)?;
  let _gate=self.raw_policy.gate.lock().unwrap_or_else(|e|e.into_inner());
  let mut ledger=self.raw_policy.workspace.raw_sources.lock().unwrap_or_else(|e|e.into_inner());
  if !ledger.has_source_arena(actual){return Err(wrong())}
  let reserved=actual.reserved_bytes();
  // Commit must not poll: actual exceptional bytes may already have escaped
  // into RecordingInputs. On an unexpected quota failure the ledger still
  // records all payloads and the reservation remains unchanged until cleanup.
  let _actual_delta=ledger.adopt_original_read(source,reserved)?;
  ledger.resize_arena(actual,0)?;
  // At success new row delta <= old reservation; total family charge cannot
  // increase, so neither new headroom admission nor post-commit IO is needed.
  Ok(())
 }
 fn admit_source_arena(&self,ledger:&mut super::raw_input_credits::Ledger,need:usize)->io::Result<()>{
  if self.raw_policy.admission.source_arena_needs_census.swap(false,Ordering::AcqRel){ledger.invalidate_upper();}
  let (mut live,was_cached)=ledger.admission_charge()?;
  let mut available=self.workspace_input_base_headroom_locked(live);
  if was_cached && available.as_ref().map_or(true,|room|need>*room){
   live=ledger.refresh_after_pressure()?;
   available=self.workspace_input_base_headroom_locked(live);
  }
  let available=available.map_err(|_|no_source_room(need,live,None))?;
  if need>available{return Err(no_source_room(need,live,Some(available)))}
  Ok(())
 }
}
impl SourceArenaWork for QueryDb{
 fn transformed_source_address_limit(&self)->Option<usize>{
  cfg!(all(target_pointer_width="64",any(windows,unix))).then_some(super::raw_policy::INPUT_BUDGET)
 }
 fn original_read_bookkeeping_bytes(&self)->io::Result<usize>{6usize.checked_mul(raw_input_credits::NODE).ok_or_else(oom)}
 fn adopt_original_read(&self,credit:&mut SourceArenaCredit,source:&dm_preprocess::SourceAcquisitionLease)->io::Result<()>{self.adopt_original_raw_read(credit,source)}
 fn checkpoint(&self)->io::Result<()>{crate::daemon::control::checkpoint()}
 fn reserve(&self,bytes:usize)->io::Result<SourceArenaCredit>{
  self.checkpoint()?;let _gate=self.raw_policy.gate.lock().unwrap_or_else(|e|e.into_inner());
  let mut ledger=self.raw_policy.workspace.raw_sources.lock().unwrap_or_else(|e|e.into_inner());
  ledger.bind_source_arena(&self.raw_policy.admission)?;
  crate::daemon::control::checkpoint()?;
  let need=bytes.checked_add(Allocation::metadata_bytes()).and_then(|n|n.checked_add(raw_input_credits::NODE)).ok_or_else(oom)?;
  self.admit_source_arena(&mut ledger,need)?;
  // Both Arc metadata and the existing weak map row were admitted BEFORE growth.
  let actual=Arc::new(Allocation{bytes:AtomicUsize::new(bytes),domain:Arc::downgrade(&self.raw_policy.admission)});
  AllocationHandle::new(actual).register(&mut ledger)
 }
 fn grow(&self,credit:&mut SourceArenaCredit,extra:usize)->io::Result<()>{
  self.checkpoint()?;let actual=allocation(self,credit)?;
  let _gate=self.raw_policy.gate.lock().unwrap_or_else(|e|e.into_inner());let mut ledger=self.raw_policy.workspace.raw_sources.lock().unwrap_or_else(|e|e.into_inner());
  if !ledger.has_source_arena(actual){return Err(wrong())}if extra==0{return Ok(())}
  crate::daemon::control::checkpoint()?;
  let next=actual.reserved_bytes().checked_add(extra).ok_or_else(oom)?;
  self.admit_source_arena(&mut ledger,extra)?;
  ledger.resize_arena(actual,next)
 }
 fn shrink(&self,credit:&mut SourceArenaCredit,bytes:usize)->io::Result<()>{
  // Releasing known freed storage never polls a new cancellation/error over the
  // first allocation failure. It still verifies the SAME private issuer/row.
  let actual=allocation(self,credit)?;let _gate=self.raw_policy.gate.lock().unwrap_or_else(|e|e.into_inner());let mut ledger=self.raw_policy.workspace.raw_sources.lock().unwrap_or_else(|e|e.into_inner());
  let next=actual.reserved_bytes().checked_sub(bytes).ok_or_else(wrong)?;ledger.resize_arena(actual,next)
 }
}

#[cfg(test)]mod actual_native_arena_resource_tests{
 use super::*;
 fn live(db:&QueryDb)->usize{db.raw_source_input_charge_locked().unwrap()}
 #[test]fn actual_existing_input_family_rejects_foreign_growth_and_denial_preserves_credit(){
  let own=QueryDb::default();let other=QueryDb::default();let baseline=live(&own);let mut credit=SourceArenaWork::reserve(&own,32).unwrap();let held=live(&own);
  assert!(held>=baseline+32);assert_eq!(SourceArenaWork::grow(&other,&mut credit,1).unwrap_err().kind(),io::ErrorKind::InvalidInput);assert_eq!(SourceArenaWork::shrink(&other,&mut credit,1).unwrap_err().kind(),io::ErrorKind::InvalidInput);assert_eq!(live(&own),held);
  SourceArenaWork::grow(&own,&mut credit,7).unwrap();assert_eq!(credit.reserved_bytes(),39);assert_eq!(live(&own),held+7);
  assert_eq!(SourceArenaWork::grow(&own,&mut credit,usize::MAX).unwrap_err().kind(),io::ErrorKind::OutOfMemory);assert_eq!(credit.reserved_bytes(),39);assert_eq!(live(&own),held+7);
  SourceArenaWork::shrink(&own,&mut credit,7).unwrap();assert_eq!(live(&own),held);drop(credit);assert_eq!(live(&own),baseline);
  assert_eq!(SourceArenaWork::reserve(&own,256*1024*1024).err().unwrap().kind(),io::ErrorKind::OutOfMemory);assert_eq!(live(&own),baseline,"denial did not publish a partial reservation or raise the actual family cap");
 }
 #[test]fn actual_source_text_payload_and_last_weak_control_are_counted_by_same_native_family(){
  let db=QueryDb::default();let baseline=live(&db);let text=String::from("native arena owner");let pointer=text.as_ptr();let capacity=text.capacity();let metadata=SourceText::source_arena_control_bytes().unwrap();let payload=SourceArenaWork::reserve(&db,capacity).unwrap();let control=SourceArenaWork::reserve(&db,metadata).unwrap().into_control();
  let source=SourceText::from_source_arena(text,payload,control).unwrap();assert_eq!(source.as_str().as_ptr(),pointer);let view=source.checked_view(1..source.len()).unwrap();let weak=source.downgrade();let full=live(&db);drop(source);assert_eq!(live(&db),full);drop(view);assert!(weak.upgrade().is_none());
  assert_eq!(live(&db),baseline+raw_input_credits::NODE+Allocation::metadata_bytes()+metadata,"physical String reservation ended, real weak-control reservation survived");drop(weak);assert_eq!(live(&db),baseline);
 }
 #[test]fn escaped_source_and_weak_alias_do_not_keep_the_query_db_or_source_payload_alive(){let db=Arc::new(QueryDb::default());let db_weak=Arc::downgrade(&db);let text=String::from("escaped actual arena");let capacity=text.capacity();let source=SourceText::from_source_arena(text,SourceArenaWork::reserve(db.as_ref(),capacity).unwrap(),SourceArenaWork::reserve(db.as_ref(),SourceText::source_arena_control_bytes().unwrap()).unwrap().into_control()).unwrap();let weak=source.downgrade();drop(db);assert!(db_weak.upgrade().is_none(),"resource credit must not retain QueryDb/ledger/model");assert_eq!(source.as_str(),"escaped actual arena");drop(source);assert!(weak.upgrade().is_none());let mut controls=0;weak.visit_derived_resource_storage(|_,bytes|controls+=bytes);assert!(controls>0,"last weak still owns its actual fixed resource metadata, without source content");drop(weak);}
}

#[cfg(test)]mod actual_original_raw_read_adoption_tests{
 use super::*;use crate::input_snapshot::{RecordingInputs,FileSystemInputs};
 fn live(db:&QueryDb)->usize{db.raw_source_input_charge_locked().unwrap()}

 #[test]
 fn actual_shared_family_holds_only_settled_fact_grants_across_real_snapshot_aliases() {
  let db=QueryDb::default();
  let baseline=live(&db);
  let root=crate::test_scratch::dir("native-original-avl-settled-family");
  let inputs=RecordingInputs::new(FileSystemInputs,0)
   .with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);
  let mut prefix=None;
  for index in 0..24 {
   let path=root.join(format!("actual-{index:02}.dm"));
   std::fs::write(&path,b"/datum/probe\n").unwrap();
   let result=dm_preprocess::source_arena_credit::read_original_source_open_using(
    &inputs,&path,1024,&db,&mut || Ok(dm_preprocess::OriginalRawOpenDecision::Read),
   ).unwrap();
   let dm_preprocess::OriginalRawReadOutcome::Acquired(source)=result else { panic!("actual acquired file") };
   drop(source);
   let snapshot=inputs.snapshot().unwrap();
   if index==0 {
    let mut storage=std::collections::BTreeMap::new();
    snapshot.visit_original_open_storage(|address,_,capacity| { storage.insert(address,capacity); });
    assert_eq!(live(&db)-baseline,storage.values().sum::<usize>()+2*raw_input_credits::NODE,
     "one open and one payload fact own exact key/node buffers and a real ledger row per grant");
   }
   if index==7 { prefix=Some((snapshot,live(&db))); }
  }
  let (prefix,prefix_charge)=prefix.unwrap();
  assert!(live(&db)>prefix_charge);
  drop(inputs);
  assert_eq!(live(&db),prefix_charge,"later disjoint fact grants die with the final snapshot");
  assert!(prefix.restat(&FileSystemInputs).unwrap().unchanged());
  drop(prefix);
  assert_eq!(live(&db),baseline);
 }

 #[test]fn actual_bom_bytes_remain_weakly_funded_after_frame_failure_and_drop_only_with_recording_inputs(){
  let db=QueryDb::default();let baseline=live(&db);let root=crate::test_scratch::dir("native-raw-read-adoption-bom");let path=root.join("original.dm");let raw=b"\xef\xbb\xbfactual original\x80";std::fs::write(&path,raw).unwrap();let inputs=RecordingInputs::new(FileSystemInputs,0).with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);
  let lease=dm_preprocess::source_arena_credit::read_original_source_using(&inputs,&path,1024,&db).unwrap().unwrap();let full=live(&db);assert!(full>baseline+raw.len());drop(lease);let exceptional_only=live(&db);assert!(exceptional_only<full);assert!(exceptional_only>=baseline+raw.len(),"actual RecordingInputs still retains exceptional SharedBytes after frame/result failure");drop(inputs);assert_eq!(live(&db),baseline);
 }
 #[test]fn actual_foreign_domain_denial_keeps_credit_and_same_db_atomic_adoption_recovers(){
  let db=QueryDb::default();let other=QueryDb::default();let baseline=live(&db);let root=crate::test_scratch::dir("native-raw-read-adoption-foreign");let path=root.join("actual.dm");std::fs::write(&path,b"/datum/probe\n").unwrap();let inputs=RecordingInputs::new(FileSystemInputs,0).with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);let mut temporary=SourceArenaWork::reserve(&db,16*1024).unwrap();let lease=inputs.read_raw_source(&path,1024,None,|_,_,_|Ok(())).unwrap().unwrap();assert_eq!(other.adopt_original_raw_read(&mut temporary,&lease).unwrap_err().kind(),io::ErrorKind::InvalidInput);assert_eq!(temporary.reserved_bytes(),16*1024);db.adopt_original_raw_read(&mut temporary,&lease).unwrap();assert_eq!(temporary.reserved_bytes(),0);drop(temporary);assert!(live(&db)>baseline);drop(lease);drop(inputs);assert_eq!(live(&db),baseline);
 }
 #[test]fn actual_surprise_payload_denial_still_records_exceptional_original_and_preserves_temporary_credit(){
  let db=QueryDb::default();let baseline=live(&db);let root=crate::test_scratch::dir("native-raw-read-adoption-underfunded");let path=root.join("actual.dm");let mut bytes=vec![0xef,0xbb,0xbf];bytes.extend(std::iter::repeat(b'x').take(8192));std::fs::write(&path,&bytes).unwrap();let inputs=RecordingInputs::new(FileSystemInputs,0).with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);let mut temporary=SourceArenaWork::reserve(&db,6*raw_input_credits::NODE).unwrap();let lease=inputs.read_raw_source(&path,16*1024,None,|_,_,_|Ok(())).unwrap().unwrap();assert_eq!(db.adopt_original_raw_read(&mut temporary,&lease).unwrap_err().kind(),io::ErrorKind::OutOfMemory);assert_eq!(temporary.reserved_bytes(),6*raw_input_credits::NODE);drop(temporary);drop(lease);assert!(live(&db)>=baseline+bytes.len(),"denial cannot refund actual escaped exceptional backing");drop(inputs);assert_eq!(live(&db),baseline);
 }
}

#[cfg(test)]mod actual_original_constructor_resource_tests{
 use super::*;use crate::input_snapshot::{RecordingInputs,FileSystemInputs};
 #[test]fn actual_reissued_bindings_dedup_shared_original_but_keep_distinct_receipt_and_path_lifetimes(){
  let db=QueryDb::default();let baseline=db.raw_source_input_charge_locked().unwrap();let root=crate::test_scratch::dir("native-raw-reissue-metadata");let path=root.join("actual.dm");std::fs::write(&path,b"/datum/original\n").unwrap();let first=RecordingInputs::new(FileSystemInputs,0).with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);let lease=dm_preprocess::source_arena_credit::read_original_source_using(&first,&path,1024,&db).unwrap().unwrap();let first_charge=db.raw_source_input_charge_locked().unwrap();
  let second=RecordingInputs::new(FileSystemInputs,0).with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);let reissued=second.read_raw_source(&path,1024,Some(&lease),|_,_,new|{assert!(!new);Ok(())}).unwrap().unwrap();assert!(reissued.same_original_acquisition(&lease));let mut credit=SourceArenaWork::reserve(&db,16*1024).unwrap();db.adopt_original_raw_read(&mut credit,&reissued).unwrap();drop(credit);let both=db.raw_source_input_charge_locked().unwrap();assert!(both>first_charge);drop(lease);drop(first);let only_reissued=db.raw_source_input_charge_locked().unwrap();assert!(only_reissued<both);assert!(only_reissued>baseline);drop(reissued);drop(second);assert_eq!(db.raw_source_input_charge_locked().unwrap(),baseline);
 }
}

/// A resource-only synchronous loan from the ACTUAL held family gate/ledger.
/// The Mutex coordinates this borrowed ledger; it is not a new budget/counter.
struct HeldSourceState<'a>{ledger:&'a mut super::raw_input_credits::Ledger,domain:&'a Arc<crate::query_db::raw_policy::Admission>,budget:&'a dq_analyze::captured_generator_budget::Budget}
struct HeldSourceWork<'a>{state:std::sync::Mutex<HeldSourceState<'a>>}
impl<'a> HeldSourceWork<'a>{
 fn lock<'s>(&'s self)->io::Result<std::sync::MutexGuard<'s,HeldSourceState<'a>>>{self.state.lock().map_err(|_|io::Error::new(io::ErrorKind::InvalidData,"held source resource loan poisoned"))}
 fn actual<'credit>(state:&HeldSourceState<'_>,credit:&'credit SourceArenaCredit)->io::Result<&'credit Allocation>{let actual=credit.owner().as_any().downcast_ref::<Allocation>().ok_or_else(wrong)?;if !actual.same_domain(&Arc::downgrade(state.domain))||!state.ledger.has_source_arena(actual){return Err(wrong())}Ok(actual)}
}
impl SourceArenaWork for HeldSourceWork<'_>{
 fn original_read_bookkeeping_bytes(&self)->io::Result<usize>{6usize.checked_mul(raw_input_credits::NODE).ok_or_else(oom)}
 fn checkpoint(&self)->io::Result<()>{let state=self.lock()?;if state.budget.denied(){return Err(oom())}drop(state);crate::daemon::control::checkpoint()}
 fn reserve(&self,bytes:usize)->io::Result<SourceArenaCredit>{self.checkpoint()?;let mut state=self.lock()?;let needed=bytes.checked_add(Allocation::metadata_bytes()).and_then(|n|n.checked_add(raw_input_credits::NODE)).ok_or_else(||{state.budget.deny();oom()})?;state.budget.charge(needed).map_err(|_|oom())?;let actual=Arc::new(Allocation{bytes:AtomicUsize::new(bytes),domain:Arc::downgrade(state.domain)});AllocationHandle::new(actual).register(state.ledger)}
 fn grow(&self,credit:&mut SourceArenaCredit,extra:usize)->io::Result<()>{self.checkpoint()?;let mut state=self.lock()?;let actual=Self::actual(&state,credit)?;let next=charge_allocation_growth(actual,state.budget,extra)?;state.ledger.resize_arena(actual,next)}
 fn shrink(&self,credit:&mut SourceArenaCredit,bytes:usize)->io::Result<()>{let mut state=self.lock()?;let actual=Self::actual(&state,credit)?;let next=actual.reserved_bytes().checked_sub(bytes).ok_or_else(wrong)?;state.ledger.resize_arena(actual,next)}
 fn adopt_original_read(&self,credit:&mut SourceArenaCredit,source:&dm_preprocess::SourceAcquisitionLease)->io::Result<()>{let mut state=self.lock()?;let actual=Self::actual(&state,credit)?;let reserved=actual.reserved_bytes();state.ledger.adopt_original_read(source,reserved)?;state.ledger.resize_arena(actual,0)}
}
/// Only RawInputCredits can lend its own actual mutable ledger and operation
/// budget. Bind verifies the existing native domain before any provider IO.
pub(super) fn with_held_source_work<R>(db:&QueryDb,ledger:&mut super::raw_input_credits::Ledger,budget:&dq_analyze::captured_generator_budget::Budget,consume:impl FnOnce(&dyn SourceArenaWork)->io::Result<R>)->io::Result<R>{ledger.bind_source_arena(&db.raw_policy.admission)?;let work=HeldSourceWork{state:std::sync::Mutex::new(HeldSourceState{ledger,domain:&db.raw_policy.admission,budget})};consume(&work)}

/// Resource-only loan issued INSIDE the genuine report's already-held family
/// gate. No reserve/grow call reenters that gate and no new counter is minted.
struct ReportOutputWork<'a>{allocation:&'a Allocation,budget:&'a dq_analyze::captured_generator_budget::Budget}
impl dq_analyze::policy_finish::admitted::Work for ReportOutputWork<'_>{
 fn checkpoint(&self)->io::Result<()>{if self.budget.denied(){return Err(oom())}crate::daemon::control::checkpoint()}
 fn reserve(&self,bytes:usize)->io::Result<()>{self.checkpoint()?;let next=charge_allocation_growth(self.allocation,self.budget,bytes)?;self.allocation.store_reserved_bytes(next);Ok(())}
 fn overflow(&self)->io::Error{self.budget.deny();oom()}
}
impl QueryDb{
 /// Called only from the actual current/failed report callback while that
 /// producer holds raw_policy.gate. The private native allocation downcast and
 /// SAME admission identity reject unrelated/custom/foreign resource owners.
 pub(crate) fn with_report_output_work_locked<R>(&self,credit:&dm_preprocess::source_arena_credit::SourceArenaControlCredit,budget:&dq_analyze::captured_generator_budget::Budget,consume:impl FnOnce(&dyn dq_analyze::policy_finish::admitted::Work)->io::Result<R>)->io::Result<R>{
  let actual=credit.owner().as_any().downcast_ref::<Allocation>().ok_or_else(wrong)?;if !actual.same_domain(&Arc::downgrade(&self.raw_policy.admission)){return Err(wrong())}
  self.raw_policy.admission.source_arena_needs_census.store(true,Ordering::Release);
  let work=ReportOutputWork{allocation:actual,budget};let value=consume(&work);match value{Err(first)=>Err(first),Ok(value)=>{dq_analyze::policy_finish::admitted::Work::checkpoint(&work)?;Ok(value)}}
 }
}

impl QueryDb{pub(crate) fn source_input_admission_bytes(&self)->io::Result<usize>{let _gate=self.raw_policy.gate.try_lock().map_err(|_|io::Error::new(io::ErrorKind::WouldBlock,"input family is already borrowed"))?;self.raw_source_input_charge_locked()}}

fn charge_allocation_growth(actual:&Allocation,budget:&dq_analyze::captured_generator_budget::Budget,extra:usize)->io::Result<usize>{let next=actual.reserved_bytes().checked_add(extra).ok_or_else(||{budget.deny();oom()})?;budget.charge(extra).map_err(|_|oom())?;Ok(next)}

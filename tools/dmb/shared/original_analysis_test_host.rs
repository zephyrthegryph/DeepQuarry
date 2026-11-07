// Shared TEST-ONLY extraction of the existing dm-tree checked fixture host.
// It owns resource admission/census only, never a parser/model/cache/daemon.
use super::*;
use std::sync::{Arc,atomic::{AtomicBool,AtomicUsize,Ordering}};
#[derive(Debug)]
pub(crate) struct Host {
    pub(crate) counter:Arc<dm_syntax::SettingChargeCounter>,
    pub(crate) limit:AtomicUsize,
    pub(crate) fail:AtomicBool,
    pub(crate) entries:AtomicUsize,
    pub(crate) aliases:std::sync::Mutex<OriginalSignatureAliasCensus>,
    source_reads:std::sync::Mutex<SourceReadLedger>,
}
impl Host {
    pub(crate) fn new()->Arc<Self>{Arc::new(Self{counter:dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap(),limit:AtomicUsize::new(128*1024*1024),fail:AtomicBool::new(false),entries:AtomicUsize::new(0),aliases:Default::default(),source_reads:Default::default()})}
    fn checkpoint(&self)->std::io::Result<()>{if self.fail.load(Ordering::Acquire){Err(std::io::Error::from_raw_os_error(1450))}else{Ok(())}}
}
impl SettingExpressionQueries for Host {
    fn original_source_work(&self)->Result<&dyn dm_preprocess::source_arena_credit::SourceArenaWork,BodySyntaxFailure>{Ok(self)}
    fn retain_original_signature_aliases(&self,row:Arc<OriginalSignatureAliasGroup>,a:&dm_syntax::SettingAdmission<'_>)->Result<(),BodySyntaxFailure>{self.aliases.lock().unwrap().retain(row,a).map_err(BodySyntaxFailure::Operational)}
    fn expression(&self,input:&SettingExpressionInput<'_>)->Result<dm_syntax::SettingExpression,BodySyntaxFailure>{
        let checkpoint=||self.checkpoint();
        input.prepare(&dm_syntax::SettingAdmission::new(&self.counter,self.limit.load(Ordering::Acquire),&checkpoint))
    }
    fn initializer<'source>(&self,input:&OriginalInitializerExpressionInput<'source>)->Result<OriginalInitializerExpression<'source>,BodySyntaxFailure>{
        let checkpoint=||self.checkpoint();
        input.prepare(&dm_syntax::SettingAdmission::new(&self.counter,self.limit.load(Ordering::Acquire),&checkpoint))
    }
    fn with_declaration_admission(&self,operation:&mut dyn FnMut(&dm_syntax::SettingAdmission<'_>)->Result<(),BodySyntaxFailure>)->Result<(),BodySyntaxFailure>{
        self.prune_source_reads();
        self.entries.fetch_add(1,Ordering::Relaxed);
        let checkpoint=||self.checkpoint();
        let a=dm_syntax::SettingAdmission::new(&self.counter,self.limit.load(Ordering::Acquire),&checkpoint);
        self.aliases.lock().unwrap().prune(&a).map_err(BodySyntaxFailure::Operational)?;
        let before=a.checkpoint();
        if let Some(actual)=a.take_operational_error(){return Err(BodySyntaxFailure::Operational(actual))}
        before.map_err(BodySyntaxFailure::Operational)?;
        let result=operation(&a);
        if matches!(&result,Err(BodySyntaxFailure::Operational(_))){return result}
        let after=a.checkpoint();
        if let Some(actual)=a.take_operational_error(){return Err(BodySyntaxFailure::Operational(actual))}
        after.map_err(BodySyntaxFailure::Operational)?;result
    }
}

// TEST-only accounting in the SAME fixture counter. The weak ledger retains
// resource reservations, never a source/model/parser/cache or strong QueryDb.
#[derive(Default)]struct SourceReadLedger{rows:Vec<SourceReadReservation>,storage:Option<dm_syntax::SettingRootLease>}
impl std::fmt::Debug for SourceReadLedger{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.debug_struct("SourceReadLedger").field("rows",&self.rows.len()).field("capacity",&self.rows.capacity()).field("funded",&self.storage.as_ref().map(|credit|credit.bytes())).finish()}}
struct SourceReadReservation{source:dm_preprocess::WeakSourceText,objects:Vec<dm_preprocess::source_acquisition::WeakAcquisitionObject>,_credit:dm_syntax::SettingRootLease}
impl std::fmt::Debug for SourceReadReservation{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.write_str("SourceReadReservation")}}
struct SourceCredit{payload:AtomicUsize,lease:std::sync::Mutex<Option<dm_syntax::SettingRootLease>>}
impl dm_preprocess::source_arena_credit::SourceArenaCreditOwner for SourceCredit{fn as_any(&self)->&dyn std::any::Any{self}fn reserved_bytes(&self)->usize{self.payload.load(Ordering::Acquire)}fn visit_storage(&self,visit:&mut dyn FnMut(usize,usize)){visit(self as*const Self as usize,std::mem::size_of::<Self>()+2*std::mem::size_of::<usize>())}}
impl Host{
 fn prune_source_reads(&self){let mut ledger=self.source_reads.lock().unwrap();ledger.rows.retain(|row|row.source.upgrade().is_some()||row.objects.iter().any(|object|object.is_alive()));if ledger.rows.is_empty(){let old=std::mem::take(&mut ledger.rows);drop(old);let storage=ledger.storage.take();drop(storage);}}
 #[cfg(test)]pub(crate) fn source_resource_rows(&self)->(usize,usize,usize){let ledger=self.source_reads.lock().unwrap();(ledger.rows.len(),ledger.rows.capacity(),ledger.storage.as_ref().map_or(0,|credit|credit.bytes()))}
 #[cfg(test)]fn source_resource_control_capacity(&self)->usize{let ledger=self.source_reads.lock().unwrap();let mut bytes=ledger.rows.capacity()*std::mem::size_of::<SourceReadReservation>();for row in &ledger.rows{row.source.visit_backing_storage(|_,_,capacity|bytes+=capacity);for object in &row.objects{object.visit_control_storage(|_,_,capacity|bytes+=capacity)}}bytes}

 fn source_credit<'a>(&self,credit:&'a dm_preprocess::source_arena_credit::SourceArenaCredit)->std::io::Result<&'a SourceCredit>{let row=credit.owner().as_any().downcast_ref::<SourceCredit>().ok_or(std::io::ErrorKind::InvalidInput)?;let lock=row.lease.lock().unwrap();let lease=lock.as_ref().ok_or(std::io::ErrorKind::InvalidInput)?;let a=dm_syntax::SettingAdmission::new(&self.counter,self.limit.load(Ordering::Acquire),&||Ok(()));if !a.matches_lease_domain(lease){return Err(std::io::ErrorKind::InvalidInput.into())}drop(lock);Ok(row)}
}
impl dm_preprocess::source_arena_credit::SourceArenaWork for Host{
 fn checkpoint(&self)->std::io::Result<()>{Host::checkpoint(self)}
 fn original_read_bookkeeping_bytes(&self)->std::io::Result<usize>{self.prune_source_reads();let ledger=self.source_reads.lock().unwrap();ledger.rows.capacity().max(4).checked_mul(8).and_then(|n|n.checked_mul(std::mem::size_of::<SourceReadReservation>())).and_then(|n|n.checked_add(4096)).ok_or_else(||std::io::ErrorKind::OutOfMemory.into())}
 fn reserve(&self,n:usize)->std::io::Result<dm_preprocess::source_arena_credit::SourceArenaCredit>{self.checkpoint()?;let poll=||self.checkpoint();let a=dm_syntax::SettingAdmission::new(&self.counter,self.limit.load(Ordering::Acquire),&poll);let bytes=n.checked_add(std::mem::size_of::<SourceCredit>()+2*std::mem::size_of::<usize>()).ok_or(std::io::ErrorKind::OutOfMemory)?;let lease=a.reserve(bytes);if let Some(actual)=a.take_operational_error(){return Err(actual)}let lease=lease?;Ok(dm_preprocess::source_arena_credit::SourceArenaCredit::from_resource_owner(Arc::new(SourceCredit{payload:AtomicUsize::new(n),lease:std::sync::Mutex::new(Some(lease))})))}
 fn grow(&self,credit:&mut dm_preprocess::source_arena_credit::SourceArenaCredit,n:usize)->std::io::Result<()>{self.checkpoint()?;let row=self.source_credit(credit)?;let next=row.payload.load(Ordering::Acquire).checked_add(n).ok_or(std::io::ErrorKind::OutOfMemory)?;let poll=||self.checkpoint();let a=dm_syntax::SettingAdmission::new(&self.counter,self.limit.load(Ordering::Acquire),&poll);let mut lease=row.lease.lock().unwrap();let result=a.grow(lease.as_mut().ok_or(std::io::ErrorKind::InvalidInput)?,n);if let Some(actual)=a.take_operational_error(){return Err(actual)}result?;row.payload.store(next,Ordering::Release);Ok(())}
 fn shrink(&self,credit:&mut dm_preprocess::source_arena_credit::SourceArenaCredit,n:usize)->std::io::Result<()>{let row=self.source_credit(credit)?;let next=row.payload.load(Ordering::Acquire).checked_sub(n).ok_or(std::io::ErrorKind::InvalidInput)?;let a=dm_syntax::SettingAdmission::new(&self.counter,self.limit.load(Ordering::Acquire),&||Ok(()));let mut lease=row.lease.lock().unwrap();a.shrink(lease.as_mut().ok_or(std::io::ErrorKind::InvalidInput)?,n)?;row.payload.store(next,Ordering::Release);Ok(())}
 fn adopt_original_read(&self,credit:&mut dm_preprocess::source_arena_credit::SourceArenaCredit,source:&dm_preprocess::SourceAcquisitionLease)->std::io::Result<()>{
  let row=self.source_credit(credit)?;let mut ledger=self.source_reads.lock().unwrap();
  // Weak controls and Vec replacement peak are prepaid before the source read.
  // A separate same-counter storage lease survives whenever spare Vec capacity
  // survives; row payload credit is NEVER the only owner of that capacity.
  let mut credit=row.lease.lock().unwrap();let current=credit.as_mut().ok_or(std::io::ErrorKind::InvalidInput)?;
  if ledger.rows.len()==ledger.rows.capacity(){
   let capacity=ledger.rows.capacity().max(4).checked_mul(2).ok_or(std::io::ErrorKind::OutOfMemory)?;let max=capacity.checked_mul(4).ok_or(std::io::ErrorKind::OutOfMemory)?;let bytes=max.checked_mul(std::mem::size_of::<SourceReadReservation>()).ok_or(std::io::ErrorKind::OutOfMemory)?;
   let a=dm_syntax::SettingAdmission::new(&self.counter,self.limit.load(Ordering::Acquire),&||Ok(()));let mut allocation=a.split(current,bytes)?;
   match &mut ledger.storage{Some(storage)=>a.absorb(storage,&mut allocation)?,None=>ledger.storage=Some(allocation)}
   let additional=capacity-ledger.rows.len();ledger.rows.try_reserve_exact(additional).map_err(|e|std::io::Error::new(std::io::ErrorKind::OutOfMemory,e))?;if ledger.rows.capacity()>max{return Err(std::io::ErrorKind::OutOfMemory.into())}
  }
  let mut objects=Vec::new();objects.try_reserve_exact(3).map_err(|e|std::io::Error::new(std::io::ErrorKind::OutOfMemory,e))?;if objects.capacity()>12{return Err(std::io::ErrorKind::OutOfMemory.into())}source.visit_weak_resource_objects(|object|objects.push(object));if objects.len()!=3{return Err(std::io::ErrorKind::InvalidData.into())}
  let reservation=credit.take().ok_or(std::io::ErrorKind::InvalidInput)?;ledger.rows.push(SourceReadReservation{source:source.source_text().downgrade(),objects,_credit:reservation});row.payload.store(0,Ordering::Release);Ok(())
 }
}

#[cfg(test)]mod actual_source_resource_tests{
 use super::*;use dm_preprocess::source_arena_credit::SourceArenaWork;
 #[test]fn weak_source_controls_and_spare_ledger_capacity_remain_funded_until_physical_release(){
  let host=Host::new();let before=host.counter.load(Ordering::Acquire);let source=dm_preprocess::SourceAcquisitionLease::from_raw_original_bytes(b"/proc/p()\n".to_vec(),());let alias=source.source_text().clone();
  let bookkeeping=host.original_read_bookkeeping_bytes().unwrap();let mut credit=host.reserve(bookkeeping+8192).unwrap();host.adopt_original_read(&mut credit,&source).unwrap();drop(credit);
  let(rows,capacity,storage)=host.source_resource_rows();assert_eq!(rows,1);assert!(capacity>=rows&&storage>=capacity*std::mem::size_of::<SourceReadReservation>());let live=host.counter.load(Ordering::Acquire);assert!(live>before);
  drop(source);host.prune_source_reads();assert_eq!(host.source_resource_rows().0,1,"detached actual SourceText alias still owns raw payload");assert_eq!(host.counter.load(Ordering::Acquire),live,"neither dead Binding controls nor live backing can become free budget while Weak rows retain them");
  drop(alias);assert!(host.source_resource_control_capacity()>0,"dead owners still leave physical Weak control allocations until prune");assert_eq!(host.counter.load(Ordering::Acquire),live,"no refund while those control allocations remain");host.prune_source_reads();assert_eq!(host.source_resource_rows(),(0,0,0),"drop actual Vec before refunding its storage credit");assert_eq!(host.counter.load(Ordering::Acquire),before);
 }
 #[test]fn pruning_one_source_keeps_shared_row_buffer_funded_and_rejects_foreign_credit(){
  let host=Host::new();let mut sources=Vec::new();for _ in 0..9{let source=dm_preprocess::SourceAcquisitionLease::from_raw_original_bytes(b"/datum/a\n".to_vec(),());let mut credit=host.reserve(host.original_read_bookkeeping_bytes().unwrap()+8192).unwrap();host.adopt_original_read(&mut credit,&source).unwrap();sources.push(source)}
  sources.pop();host.prune_source_reads();let(rows,capacity,storage)=host.source_resource_rows();assert_eq!(rows,8);assert!(storage>=capacity*std::mem::size_of::<SourceReadReservation>());
  let foreign=Host::new();let mut wrong=foreign.reserve(8192).unwrap();assert_eq!(host.grow(&mut wrong,1).unwrap_err().kind(),std::io::ErrorKind::InvalidInput);drop(wrong);assert_eq!(foreign.counter.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());drop(sources);host.prune_source_reads();assert_eq!(host.source_resource_rows(),(0,0,0));assert_eq!(host.counter.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
 }
}

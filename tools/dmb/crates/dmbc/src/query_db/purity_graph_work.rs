//! Allocation escrow in the SAME purity ledger; not another counter/store.
use super::*;
pub(super) struct GraphLease{
 pub(super) ledger:Arc<Mutex<Ledger>>,
 pub(super) completion:Arc<std::sync::atomic::AtomicBool>,
 dirty:Arc<std::sync::atomic::AtomicBool>,
}
impl GraphLease{
 pub(super) fn new(ledger:Arc<Mutex<Ledger>>,completion:Arc<std::sync::atomic::AtomicBool>)->Self{
  let dirty=Arc::clone(&ledger.lock().unwrap_or_else(|e|e.into_inner()).completion_dirty);
  Self{ledger,completion,dirty}
 }
}
impl Drop for GraphLease{
 fn drop(&mut self){
  self.completion.store(true,Ordering::Release);
  self.dirty.store(true,Ordering::Release);
 }
}
pub(super) struct GraphWork{ledger:Arc<Mutex<Ledger>>,key:Key,bytes:usize,issuance:Option<std::num::NonZeroU64>,#[cfg(test)]report_peak:usize,#[cfg(test)]report_total:usize,#[cfg(test)]report_retired:usize}
impl GraphWork{
 #[cfg(test)]pub(super) fn charged_bytes_for_chunk(&self)->usize{self.bytes}
 #[cfg(test)]pub(super) fn report_scope_counts(&self)->(usize,usize,usize){(self.report_peak,self.report_total,self.report_retired)}
 pub(super) fn new(ledger:Arc<Mutex<Ledger>>,key:Key)->Self{static NEXT:std::sync::atomic::AtomicU64=std::sync::atomic::AtomicU64::new(1);Self::new_using_counter(ledger,key,&NEXT)}
 fn new_using_counter(ledger:Arc<Mutex<Ledger>>,key:Key,counter:&std::sync::atomic::AtomicU64)->Self{Self{ledger,key,bytes:0,issuance:next_work_issuance(counter),#[cfg(test)]report_peak:0,#[cfg(test)]report_total:0,#[cfg(test)]report_retired:0}}
 pub(super) fn reserve(&mut self,bytes:usize)->std::io::Result<()>{
  crate::daemon::control::checkpoint()?;if self.issuance.is_none(){return Err(std::io::Error::new(std::io::ErrorKind::OutOfMemory,"effect resource-work issuance exhausted before allocation"))}let mut ledger=self.ledger.lock().unwrap_or_else(|e|e.into_inner());
  let total=self.bytes.checked_add(bytes).ok_or_else(||std::io::Error::new(std::io::ErrorKind::OutOfMemory,"effect graph escrow overflow"))?;
  ledger.admit(bytes).map_err(|_|std::io::Error::new(std::io::ErrorKind::OutOfMemory,"effect graph live-family escrow refused"))?;
  ledger.active_graph_work=ledger.active_graph_work.checked_add(bytes).ok_or_else(||std::io::Error::new(std::io::ErrorKind::OutOfMemory,"effect graph family escrow overflow"))?;self.bytes=total;#[cfg(test)]{self.report_peak=self.report_peak.max(total);self.report_total=self.report_total.saturating_add(bytes);}Ok(())
 }
 /// Called only after graph-builder scratch has physically dropped. Transfer
 /// its escrow into the actual escaped immutable graph while holding one lock.
 pub(super) fn publish(self,graph:dm_analysis::checker_effects::RetainedEffectGraph)->Result<Outcome,QueryError>{self.publish_data::<global_graph::NativeEffectGraph>(graph)}
 pub(super) fn publish_data<T:RetainedHandle>(mut self,data:T::Data)->Result<Outcome,QueryError>{
  self.reserve(T::coordination_charge()+std::mem::size_of::<std::sync::atomic::AtomicBool>()).map_err(|actual|QueryError::operational(self.key,actual))?;
  let completion=Arc::new(std::sync::atomic::AtomicBool::new(false));
  let value=T::issue(data,Arc::clone(&self.ledger),Arc::clone(&completion));
  let bytes=value.retained_charge().ok_or(QueryError::Missing(self.key))?;
  crate::daemon::control::checkpoint().map_err(|actual|QueryError::operational(self.key,actual))?;
  let owner:Value=value.clone();let fingerprint=value.fingerprint(self.key);crate::daemon::control::checkpoint().map_err(|actual|QueryError::operational(self.key,actual))?;let outcome=Outcome::new(Ok::<Arc<T>,String>(value),fingerprint,bytes);
  let mut ledger=self.ledger.lock().unwrap_or_else(|e|e.into_inner());
  if ledger.denied||ledger.aborted.is_some(){return Err(QueryError::Missing(self.key))}
  ledger.live_bytes();
  let exposed_bound=if ledger.live.len()==ledger.live.capacity(){ledger.live.len().checked_add(1).and_then(|n|n.checked_mul(4)).ok_or(QueryError::Missing(self.key))?}else{ledger.live.capacity()};
  let growth=exposed_bound.saturating_sub(ledger.live.capacity()).checked_mul(std::mem::size_of::<Live>()).ok_or(QueryError::Missing(self.key))?;
  ledger.admit(bytes.saturating_add(growth).saturating_add(std::mem::size_of::<std::sync::atomic::AtomicBool>()).saturating_sub(self.bytes)).map_err(|_|QueryError::Missing(self.key))?;
  if let Err(actual)=ledger.live.try_reserve_exact(1){ledger.denied=true;return Err(QueryError::operational(self.key,std::io::Error::new(std::io::ErrorKind::OutOfMemory,actual)))}
  if ledger.live.capacity()>exposed_bound{ledger.denied=true;return Err(QueryError::operational(self.key,std::io::Error::new(std::io::ErrorKind::OutOfMemory,"effect graph retained-owner directory exposed excess capacity")))}
  ledger.active_graph_work=ledger.active_graph_work.checked_sub(self.bytes).expect("same owned graph escrow");self.bytes=0;
  ledger.push_live(Live{owner:Arc::downgrade(&owner),completion:Some(completion),bytes,kind:self.key.kind,error:false});Ok(outcome)
 }
}
impl Drop for GraphWork{fn drop(&mut self){if self.bytes!=0{let mut ledger=self.ledger.lock().unwrap_or_else(|e|e.into_inner());ledger.active_graph_work=ledger.active_graph_work.checked_sub(self.bytes).expect("same owned graph escrow drop");}}}

pub(super) trait RetainedHandle:Send+Sync+'static{fn fingerprint(&self,key:Key)->u128{key.id}type Data;fn coordination_charge()->usize;fn issue(data:Self::Data,ledger:Arc<Mutex<Ledger>>,completion:Arc<std::sync::atomic::AtomicBool>)->Arc<Self>;fn retained_charge(&self)->Option<usize>;}

// Resource coordination only: never a semantic/source fingerprint or proof.
fn next_work_issuance(counter:&std::sync::atomic::AtomicU64)->Option<std::num::NonZeroU64>{counter.fetch_update(Ordering::Relaxed,Ordering::Relaxed,|value|value.checked_add(1)).ok().and_then(std::num::NonZeroU64::new)}
pub(super) struct ReportScopeMark{issuance:std::num::NonZeroU64,key:Key,bytes:usize}
impl dm_analysis::checker_effects::EffectReportWork for GraphWork{
 type Mark=ReportScopeMark;
 fn reserve(&mut self,bytes:usize)->std::io::Result<()>{GraphWork::reserve(self,bytes)}
 fn mark(&mut self)->std::io::Result<Self::Mark>{crate::daemon::control::checkpoint()?;Ok(ReportScopeMark{issuance:self.issuance.ok_or_else(||std::io::Error::new(std::io::ErrorKind::OutOfMemory,"effect report resource issuance exhausted"))?,key:self.key,bytes:self.bytes})}
 fn reconcile(&mut self,marker:Self::Mark,retained_delta:usize)->std::io::Result<()>{crate::daemon::control::checkpoint()?;if Some(marker.issuance)!=self.issuance||marker.key!=self.key{return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"effect report scope belongs to another actual escrow"))}let desired=marker.bytes.checked_add(retained_delta).filter(|desired|marker.bytes<=self.bytes&&*desired<=self.bytes).ok_or_else(||std::io::Error::new(std::io::ErrorKind::OutOfMemory,"effect report retained scope exceeds actual owned escrow"))?;let mut ledger=self.ledger.lock().unwrap_or_else(|e|e.into_inner());if ledger.denied{return Err(std::io::Error::new(std::io::ErrorKind::OutOfMemory,"effect report family was already denied"))}let credit=self.bytes-desired;ledger.active_graph_work=ledger.active_graph_work.checked_sub(credit).expect("same owned report scope reservation");self.bytes=desired;#[cfg(test)]{self.report_retired=self.report_retired.saturating_add(credit);}Ok(())}
}

#[cfg(test)]mod report_scope_tests{use super::*;use dm_analysis::checker_effects::EffectReportWork;use std::sync::atomic::{AtomicBool,Ordering};
 #[test]fn scope_markers_refuse_another_actual_same_key_escrow_without_credit(){let ledger=Arc::new(Mutex::new(Ledger::default()));let key=Key::new(Kind(26),11);let mut a=GraphWork::new(ledger.clone(),key);let mut b=GraphWork::new(ledger.clone(),key);a.reserve(1024).unwrap();b.reserve(1024).unwrap();let mark=EffectReportWork::mark(&mut a).unwrap();assert_eq!(EffectReportWork::reconcile(&mut b,mark,0).unwrap_err().kind(),std::io::ErrorKind::InvalidInput);assert_eq!(ledger.lock().unwrap().active_graph_work,2048);drop(a);drop(b);assert_eq!(ledger.lock().unwrap().active_graph_work,0);}
 #[test]fn failed_checkpoint_keeps_full_scope_and_unwind_frees_buffers_before_escrow_credit(){let ledger=Arc::new(Mutex::new(Ledger::default()));let mut work=GraphWork::new(ledger.clone(),Key::new(Kind(26),12));work.reserve(1024).unwrap();let marker=EffectReportWork::mark(&mut work).unwrap();work.reserve(4096).unwrap();let buffer=vec![0u8;4096];let error=Err::<(),Vec<u8>>(buffer);assert_eq!(ledger.lock().unwrap().active_graph_work,5120,"error payload is still physically owned; no scope reconciliation");drop(error);let token=crate::daemon::control::Cancellation::default();let binding=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));token.cancel();assert_eq!(EffectReportWork::reconcile(&mut work,marker,0).unwrap_err().kind(),std::io::ErrorKind::Interrupted);assert_eq!(ledger.lock().unwrap().active_graph_work,5120,"actual failed checkpoint grants no early credit");drop(binding);drop(work);assert_eq!(ledger.lock().unwrap().active_graph_work,0);
 struct PhysicalBuffer{bytes:Vec<u8>,ledger:Arc<Mutex<Ledger>>,funded:Arc<AtomicBool>}impl Drop for PhysicalBuffer{fn drop(&mut self){self.funded.store(self.ledger.lock().unwrap().active_graph_work>=self.bytes.capacity(),Ordering::Release);}}let funded=Arc::new(AtomicBool::new(false));let result=std::panic::catch_unwind(std::panic::AssertUnwindSafe({let ledger=ledger.clone();let funded=funded.clone();move||{let mut work=GraphWork::new(ledger.clone(),Key::new(Kind(26),13));work.reserve(4096).unwrap();let _marker=EffectReportWork::mark(&mut work).unwrap();let _buffer=PhysicalBuffer{bytes:vec![0u8;4096],ledger,funded};panic!("actual scope unwind before reconciliation");}}));assert!(result.is_err());assert!(funded.load(Ordering::Acquire));assert_eq!(ledger.lock().unwrap().active_graph_work,0);}
}

#[cfg(test)]mod post_hash_tests{use super::*;struct HashWork{bytes:Vec<u8>,token:crate::daemon::control::Cancellation,cancel:bool,lease:GraphLease}
 impl RetainedHandle for HashWork{type Data=(Vec<u8>,crate::daemon::control::Cancellation,bool);fn fingerprint(&self,_:Key)->u128{if self.cancel{self.token.cancel()}7}fn coordination_charge()->usize{std::mem::size_of::<Self>()-std::mem::size_of::<Vec<u8>>()}fn issue((bytes,token,cancel):Self::Data,ledger:Arc<Mutex<Ledger>>,completion:Arc<std::sync::atomic::AtomicBool>)->Arc<Self>{Arc::new(Self{bytes,token,cancel,lease:GraphLease::new(ledger,completion)})}fn retained_charge(&self)->Option<usize>{self.bytes.capacity().checked_add(std::mem::size_of::<Self>())}}
 #[test]fn actual_cancellation_during_retained_value_fingerprint_precedes_outcome_and_same_key_recovers(){let ledger=Arc::new(Mutex::new(Ledger::default()));let key=Key::new(Kind(23),17);let token=crate::daemon::control::Cancellation::default();let binding=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));let mut work=GraphWork::new(ledger.clone(),key);work.reserve(4096).unwrap();let error=work.publish_data::<HashWork>((vec![0u8;1024],token.clone(),true)).err().unwrap();assert!(token.is_cancelled(),"actual successful fingerprint hook cancelled the real coordinator token");let actual=error.into_operational().expect("post-hash actual control failure").into_io();assert_eq!(actual.kind(),std::io::ErrorKind::Interrupted);assert_eq!(ledger.lock().unwrap().active_graph_work,0);assert!(ledger.lock().unwrap().live.is_empty(),"no retained owner/outcome is claimed after hashing is interrupted");drop(binding);let healthy=crate::daemon::control::Cancellation::default();let _binding=crate::daemon::control::bind_with_deadline(healthy.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));let mut retry=GraphWork::new(ledger.clone(),key);retry.reserve(4096).unwrap();let outcome=retry.publish_data::<HashWork>((vec![0u8;1024],healthy,false)).unwrap();assert_eq!(ledger.lock().unwrap().active_graph_work,0);assert_eq!(ledger.lock().unwrap().live.len(),1);drop(outcome);assert_eq!(ledger.lock().unwrap().live_bytes(),0);}
}

#[cfg(test)]mod issuance_tests{use super::*;use dm_analysis::checker_effects::EffectReportWork;
 #[test]fn recycled_same_box_address_and_same_key_refuse_old_scope_mark_without_credit(){let ledger=Arc::new(Mutex::new(Ledger::default()));let key=Key::new(Kind(26),19);let mut slot=Box::new(GraphWork::new(ledger.clone(),key));slot.reserve(1024).unwrap();let address=slot.as_ref()as*const GraphWork as usize;let marker=EffectReportWork::mark(slot.as_mut()).unwrap();*slot=GraphWork::new(ledger.clone(),key);assert_eq!(slot.as_ref()as*const GraphWork as usize,address);assert_eq!(ledger.lock().unwrap().active_graph_work,0);slot.reserve(4096).unwrap();assert_eq!(EffectReportWork::reconcile(slot.as_mut(),marker,0).unwrap_err().kind(),std::io::ErrorKind::InvalidInput);assert_eq!(ledger.lock().unwrap().active_graph_work,4096);drop(slot);assert_eq!(ledger.lock().unwrap().active_graph_work,0);}
 #[test]fn same_owned_work_may_move_without_becoming_another_scope(){let ledger=Arc::new(Mutex::new(Ledger::default()));let mut work=GraphWork::new(ledger.clone(),Key::new(Kind(26),20));work.reserve(1024).unwrap();let marker=EffectReportWork::mark(&mut work).unwrap();let mut moved=Box::new(work);moved.reserve(4096).unwrap();EffectReportWork::reconcile(moved.as_mut(),marker,0).unwrap();assert_eq!(ledger.lock().unwrap().active_graph_work,1024);drop(moved);assert_eq!(ledger.lock().unwrap().active_graph_work,0);}
 struct NeverIssued;impl RetainedHandle for NeverIssued{type Data=();fn coordination_charge()->usize{0}fn issue(_:(),_:Arc<Mutex<Ledger>>,_:Arc<std::sync::atomic::AtomicBool>)->Arc<Self>{panic!("exhausted work cannot allocate or issue a retained owner")}fn retained_charge(&self)->Option<usize>{Some(0)}}
 #[test]fn resource_issuance_overflow_never_wraps_or_allocates_and_does_not_reset_shared_counter(){let counter=std::sync::atomic::AtomicU64::new(u64::MAX-1);assert_eq!(next_work_issuance(&counter).unwrap().get(),u64::MAX-1);assert!(next_work_issuance(&counter).is_none());assert!(next_work_issuance(&counter).is_none());assert_eq!(counter.load(Ordering::Relaxed),u64::MAX);let ledger=Arc::new(Mutex::new(Ledger::default()));let key=Key::new(Kind(26),21);let mut work=GraphWork::new_using_counter(ledger.clone(),key,&counter);assert_eq!(work.reserve(1).unwrap_err().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(EffectReportWork::mark(&mut work).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);let error=work.publish_data::<NeverIssued>(()).err().unwrap().into_operational().unwrap().into_io();assert_eq!(error.kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(ledger.lock().unwrap().active_graph_work,0);assert!(ledger.lock().unwrap().live.is_empty());}
}

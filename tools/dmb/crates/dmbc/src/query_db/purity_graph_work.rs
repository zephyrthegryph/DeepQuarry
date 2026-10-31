//! Allocation escrow in the SAME purity ledger; not another counter/store.
use super::*;
pub(super) struct GraphLease{pub(super) ledger:Arc<Mutex<Ledger>>,pub(super) completion:Arc<std::sync::atomic::AtomicBool>}
impl Drop for GraphLease{fn drop(&mut self){self.completion.store(true,Ordering::Release);}}
pub(super) struct GraphWork{ledger:Arc<Mutex<Ledger>>,key:Key,bytes:usize}
impl GraphWork{
 pub(super) fn new(ledger:Arc<Mutex<Ledger>>,key:Key)->Self{Self{ledger,key,bytes:0}}
 pub(super) fn reserve(&mut self,bytes:usize)->std::io::Result<()>{
  crate::daemon::control::checkpoint()?;let mut ledger=self.ledger.lock().unwrap_or_else(|e|e.into_inner());
  let total=self.bytes.checked_add(bytes).ok_or_else(||std::io::Error::new(std::io::ErrorKind::OutOfMemory,"effect graph escrow overflow"))?;
  ledger.admit(bytes).map_err(|_|std::io::Error::new(std::io::ErrorKind::OutOfMemory,"effect graph live-family escrow refused"))?;
  ledger.active_graph_work=ledger.active_graph_work.checked_add(bytes).ok_or_else(||std::io::Error::new(std::io::ErrorKind::OutOfMemory,"effect graph family escrow overflow"))?;self.bytes=total;Ok(())
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
  let exposed_bound=if ledger.live.len()==ledger.live.capacity(){ledger.live.len().checked_add(1).and_then(|n|n.checked_mul(4)).ok_or(QueryError::Missing(self.key))?}else{ledger.live.capacity()};
  let growth=exposed_bound.saturating_sub(ledger.live.capacity()).checked_mul(std::mem::size_of::<Live>()).ok_or(QueryError::Missing(self.key))?;
  ledger.admit(bytes.saturating_add(growth).saturating_add(std::mem::size_of::<std::sync::atomic::AtomicBool>()).saturating_sub(self.bytes)).map_err(|_|QueryError::Missing(self.key))?;
  if let Err(actual)=ledger.live.try_reserve_exact(1){ledger.denied=true;return Err(QueryError::operational(self.key,std::io::Error::new(std::io::ErrorKind::OutOfMemory,actual)))}
  if ledger.live.capacity()>exposed_bound{ledger.denied=true;return Err(QueryError::operational(self.key,std::io::Error::new(std::io::ErrorKind::OutOfMemory,"effect graph retained-owner directory exposed excess capacity")))}
  ledger.active_graph_work=ledger.active_graph_work.checked_sub(self.bytes).expect("same owned graph escrow");self.bytes=0;
  ledger.live.push(Live{owner:Arc::downgrade(&owner),completion:Some(completion),bytes,kind:self.key.kind,error:false});Ok(outcome)
 }
}
impl Drop for GraphWork{fn drop(&mut self){if self.bytes!=0{let mut ledger=self.ledger.lock().unwrap_or_else(|e|e.into_inner());ledger.active_graph_work=ledger.active_graph_work.checked_sub(self.bytes).expect("same owned graph escrow drop");}}}

pub(super) trait RetainedHandle:Send+Sync+'static{fn fingerprint(&self,key:Key)->u128{key.id}type Data;fn coordination_charge()->usize;fn issue(data:Self::Data,ledger:Arc<Mutex<Ledger>>,completion:Arc<std::sync::atomic::AtomicBool>)->Arc<Self>;fn retained_charge(&self)->Option<usize>;}

#[cfg(test)]mod post_hash_tests{use super::*;struct HashWork{bytes:Vec<u8>,token:crate::daemon::control::Cancellation,cancel:bool,lease:GraphLease}
 impl RetainedHandle for HashWork{type Data=(Vec<u8>,crate::daemon::control::Cancellation,bool);fn fingerprint(&self,_:Key)->u128{if self.cancel{self.token.cancel()}7}fn coordination_charge()->usize{std::mem::size_of::<Self>()-std::mem::size_of::<Vec<u8>>()}fn issue((bytes,token,cancel):Self::Data,ledger:Arc<Mutex<Ledger>>,completion:Arc<std::sync::atomic::AtomicBool>)->Arc<Self>{Arc::new(Self{bytes,token,cancel,lease:GraphLease{ledger,completion}})}fn retained_charge(&self)->Option<usize>{self.bytes.capacity().checked_add(std::mem::size_of::<Self>())}}
 #[test]fn actual_cancellation_during_retained_value_fingerprint_precedes_outcome_and_same_key_recovers(){let ledger=Arc::new(Mutex::new(Ledger::default()));let key=Key::new(Kind(23),17);let token=crate::daemon::control::Cancellation::default();let binding=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));let mut work=GraphWork::new(ledger.clone(),key);work.reserve(4096).unwrap();let error=work.publish_data::<HashWork>((vec![0u8;1024],token.clone(),true)).err().unwrap();assert!(token.is_cancelled(),"actual successful fingerprint hook cancelled the real coordinator token");let actual=error.into_operational().expect("post-hash actual control failure").into_io();assert_eq!(actual.kind(),std::io::ErrorKind::Interrupted);assert_eq!(ledger.lock().unwrap().active_graph_work,0);assert!(ledger.lock().unwrap().live.is_empty(),"no retained owner/outcome is claimed after hashing is interrupted");drop(binding);let healthy=crate::daemon::control::Cancellation::default();let _binding=crate::daemon::control::bind_with_deadline(healthy.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));let mut retry=GraphWork::new(ledger.clone(),key);retry.reserve(4096).unwrap();let outcome=retry.publish_data::<HashWork>((vec![0u8;1024],healthy,false)).unwrap();assert_eq!(ledger.lock().unwrap().active_graph_work,0);assert_eq!(ledger.lock().unwrap().live.len(),1);drop(outcome);assert_eq!(ledger.lock().unwrap().live_bytes(),0);}
}

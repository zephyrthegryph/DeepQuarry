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
  let owner:Value=value.clone();let outcome=Outcome::new(Ok::<Arc<T>,String>(value),self.key.id,bytes);
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

pub(super) trait RetainedHandle:Send+Sync+'static{type Data;fn coordination_charge()->usize;fn issue(data:Self::Data,ledger:Arc<Mutex<Ledger>>,completion:Arc<std::sync::atomic::AtomicBool>)->Arc<Self>;fn retained_charge(&self)->Option<usize>;}

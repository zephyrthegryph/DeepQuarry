//! Resource observation owned by the EXISTING native OS-worker entry.
//! Not a transferable allocation/source/model token. No pool, job or cache.
use std::{cell::Cell,marker::PhantomData,rc::Rc,thread::ThreadId};
#[derive(Clone,Copy)]struct Active{generation:ThreadId,bytes:usize}
thread_local!{static ACTIVE:Cell<Option<Active>>=const{Cell::new(None)};}
/// A non-Send/non-Sync borrow scoped to one actual worker observation.
/// No public constructor or raw stack-size accessor exists.
pub struct CurrentCompilerWorkerStack<'worker>{generation:ThreadId,_borrow:PhantomData<&'worker Rc<()>>}
pub(crate) struct Entry{prior:Option<Active>}
impl Entry{
 /// Only the actual BuildExecutor OS spawn handler calls this, once per worker.
 /// Rust ThreadId is the private entry generation; it is never an OS PID/name.
 pub(crate) fn enter(configured:Option<usize>)->Self{let next=configured.map(|bytes|Active{generation:std::thread::current().id(),bytes});let prior=ACTIVE.with(|slot|slot.replace(next));Self{prior}}
}
impl Drop for Entry{fn drop(&mut self){ACTIVE.with(|slot|slot.set(self.prior))}}
/// The higher-ranked borrow cannot escape this observation or move to a foreign
/// thread. Production consumers revalidate again at the actual admission use.
pub fn with_current_compiler_worker_stack<R>(operation:impl for<'worker>FnOnce(Option<CurrentCompilerWorkerStack<'worker>>)->R)->R{
 ACTIVE.with(|slot|operation(slot.get().map(|active|CurrentCompilerWorkerStack{generation:active.generation,_borrow:PhantomData})))
}
impl CurrentCompilerWorkerStack<'_>{
 /// Reserve a conservative quarter of THIS actual native worker's explicit
 /// stack for primary parse/inventory frames. Raw integers are never accepted
 /// as worker provenance by this path; no token is cached or transferable.
 pub fn with_primary_allowance<R>(&self,operation:impl FnOnce(usize)->R)->std::io::Result<R>{
  if self.generation!=std::thread::current().id(){return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"native stack observation belongs to another worker"))}
  ACTIVE.with(|slot|match slot.get(){Some(active)if active.generation==self.generation=>Ok(operation(active.bytes/4)),_=>Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"native stack observation is no longer current"))})
 }
}
#[cfg(test)]mod tests{
 use super::*;
 #[test]fn actual_worker_stack_observation_is_absent_outside_executor_and_issued_only_on_its_worker(){
  with_current_compiler_worker_stack(|scope|assert!(scope.is_none()));let executor=crate::BuildExecutor::new(1).unwrap();let thread=std::thread::current().id();executor.install(||with_current_compiler_worker_stack(|scope|{let scope=scope.expect("actual native worker stack entry");assert_ne!(std::thread::current().id(),thread);let observed=scope.with_primary_allowance(|bytes|bytes).unwrap();assert_eq!(observed,crate::COMPILER_STACK_BYTES/4)}));with_current_compiler_worker_stack(|scope|assert!(scope.is_none()));
 }
}

//! Stack-only child admission on the existing policy family. The family gate
//! is already held by the caller; this never resets it or enters another gate.
use super::*;
use dq_analyze::captured_generator_budget::Budget;

struct Limit<'a>{admission:&'a Admission,previous:usize,parent:&'a Budget,charge:&'a AtomicUsize,before:usize,_local:std::marker::PhantomData<std::rc::Rc<()>>}
impl Drop for Limit<'_>{fn drop(&mut self){
 self.admission.limit.store(self.previous,Ordering::Release);
 let delta=self.charge.load(Ordering::Acquire).saturating_sub(self.before);
 if self.parent.retain_nested(delta).is_err(){self.admission.denied.store(true,Ordering::Release);}
}}
impl Admission{
    /// Coordination only: the actual source/evidence factory remains mandatory.
    /// Dynamic children join the SAME original lease map, without eviction or a
    /// second store. Exhaustion refuses before the child's params are allocated.
    pub(super) fn admit_child(&self,owner:Weak<CapturedPolicyInputs>,key:Key,bytes:usize)->Result<(),QueryError>{
        let mut leases=self.leases.lock().unwrap_or_else(|e|e.into_inner());
        let total=leases.iter().filter(|(k,_)|**k!=key).try_fold(bytes,|n,(_,lease)|n.checked_add(lease.bytes));
        let count=leases.len().checked_add(usize::from(!leases.contains_key(&key))).and_then(|n|n.checked_add(self.workspace_nodes.load(Ordering::Acquire)));
        if total.is_none_or(|n|n>INPUT_BUDGET)||count.is_none_or(|n|n>MAX_NODES){self.denied.store(true,Ordering::Release);return Err(QueryError::Missing(key));}
        leases.insert(key,Lease{owner:LeaseOwner::Semantic(owner),bytes,touched:Instant::now()});Ok(())
    }
    pub(super) fn admit_ui(&self,owner:Weak<crate::runner_host::workspace_capture::WorkspaceCapture>,key:Key,bytes:usize)->Result<(),QueryError>{
        let bytes=bytes.checked_add(std::mem::size_of::<Lease>()).and_then(|n|n.checked_add(std::mem::size_of::<crate::runner_host::workspace_capture::WorkspaceCapture>())).and_then(|n|n.checked_add(2*std::mem::size_of::<usize>()+128)).ok_or_else(||QueryError::operational(key,io::Error::new(io::ErrorKind::OutOfMemory,"UI lease metadata overflow")))?;
        let mut leases=self.leases.lock().unwrap_or_else(|e|e.into_inner());
        let total=leases.iter().filter(|(k,_)|**k!=key).try_fold(bytes,|n,(_,lease)|n.checked_add(lease.bytes));
        let count=leases.len().checked_add(usize::from(!leases.contains_key(&key))).and_then(|n|n.checked_add(self.workspace_nodes.load(Ordering::Acquire)));
        if total.is_none_or(|n|n>INPUT_BUDGET)||count.is_none_or(|n|n>MAX_NODES){self.denied.store(true,Ordering::Release);return Err(QueryError::operational(key,io::Error::new(io::ErrorKind::OutOfMemory,"UI raw input/result admission exceeds existing family")))}
        leases.insert(key,Lease{owner:LeaseOwner::UiRaw(owner),bytes,touched:Instant::now()});Ok(())
    }
    /// Reserve the live parent's temporary envelope BEFORE ctx.get. Child
    /// retained bytes already enter the family charge; only its actual positive
    /// delta is transferred into the parent's operation budget. A warm child
    /// therefore transfers zero. Completed descendants survive a parent error.
    pub(super) fn with_child<T>(&self,parent:&Budget,charge:&AtomicUsize,key:Key,operation:impl FnOnce()->Result<T,QueryError>)->Result<T,QueryError>{
        parent.require().map_err(|_|{self.denied.store(true,Ordering::Release);QueryError::Missing(key)})?;
        let previous=self.limit.load(Ordering::Acquire);
        let Some(limit)=previous.checked_sub(parent.temporary_charge())else{self.denied.store(true,Ordering::Release);return Err(QueryError::Missing(key));};
        self.limit.store(limit,Ordering::Release);
        let before=charge.load(Ordering::Acquire);
        let result={let _restore=Limit{admission:self,previous,parent,charge,before,_local:std::marker::PhantomData};operation()};
        if parent.denied()&&!matches!(&result,Err(QueryError::Operational{..})){self.denied.store(true,Ordering::Release);return Err(QueryError::Missing(key));}
        result
    }
}
#[cfg(test)]
mod tests{
 use super::*;
 #[test]
 fn nested_child_cold_peak_denial_restores_limit_and_warm_transfers_no_bytes(){
  let db=Db::default();let admission=Arc::new(Admission::default());let charge=Arc::new(AtomicUsize::new(0));let kind=Kind(249);let key=Key::new(kind,1);
  let a=Arc::clone(&admission);let c=Arc::clone(&charge);
  db.define(kind,"test-real-nested-retained-child",move|_,_|{retain_derived(&c,384,&a,key)?;Ok(Outcome::new(7usize,7,384))});
  admission.limit.store(512,Ordering::Release);let parent=Budget::new(512).unwrap();parent.charge(192).unwrap();
  assert!(admission.with_child(&parent,&charge,key,||db.get::<usize>(key,Arc::new(()))).is_err());assert_eq!(admission.limit.load(Ordering::Acquire),512);assert_eq!(charge.load(Ordering::Acquire),0);assert_eq!(db.value_bytes_at(key),0);
  admission.denied.store(false,Ordering::Release);admission.limit.store(2048,Ordering::Release);let parent=Budget::new(2048).unwrap();let before=parent.used();
  assert_eq!(*admission.with_child(&parent,&charge,key,||db.get::<usize>(key,Arc::new(()))).unwrap(),7);assert_eq!(parent.used()-before,384);assert_eq!(charge.load(Ordering::Acquire),384);
  let computed=db.stats(kind).computed;let before=parent.used();assert_eq!(*admission.with_child(&parent,&charge,key,||db.get::<usize>(key,Arc::new(()))).unwrap(),7);assert_eq!(parent.used(),before);assert_eq!(db.stats(kind).computed,computed);
  drop(parent);assert_eq!(charge.load(Ordering::Acquire),384,"child remains an original Db value after parent budget drops");
 }
 #[test]
 fn nested_child_parent_error_and_unwind_restore_outer_limit(){
  let admission=Admission::default();admission.limit.store(4096,Ordering::Release);let charge=AtomicUsize::new(0);let parent=Budget::new(4096).unwrap();let key=Key::new(Kind(249),2);
  assert!(admission.with_child::<()>(&parent,&charge,key,||{charge.store(128,Ordering::Release);Err(QueryError::Missing(key))}).is_err());assert_eq!(parent.used(),std::mem::size_of::<Budget>()+2*std::mem::size_of::<usize>()+128);assert_eq!(admission.limit.load(Ordering::Acquire),4096);assert_eq!(charge.load(Ordering::Acquire),128);
  let before=parent.used();let panic=std::panic::catch_unwind(std::panic::AssertUnwindSafe(||{let _=admission.with_child::<()>(&parent,&charge,key,||{charge.fetch_add(64,Ordering::AcqRel);panic!("real child unwinds")});}));assert!(panic.is_err());assert_eq!(admission.limit.load(Ordering::Acquire),4096);assert_eq!(parent.used()-before,64,"valid child retention transfers even during unwinding");
 }
}

#[cfg(test)]mod sibling_tests{
 use super::*;
 #[test]fn two_cold_siblings_and_grandchild_fit_once_each_and_warm_loans_are_free(){
  let db=Db::default();let admission=Arc::new(Admission::default());admission.limit.store(1024,Ordering::Release);let charge=Arc::new(AtomicUsize::new(0));let kind=Kind(248);let left=Key::new(kind,1);let right=Key::new(kind,2);let grand=Key::new(kind,3);
  let a=Arc::clone(&admission);let c=Arc::clone(&charge);db.define(kind,"real nested sibling peak",move|ctx,params|{
   let value=*params.downcast_ref::<u128>().unwrap();let key=Key::new(kind,value);
   if value==1{let budget=Budget::new(a.limit.load(Ordering::Acquire).saturating_sub(c.load(Ordering::Acquire))).unwrap();budget.charge(32).unwrap();a.with_child(&budget,&c,grand,||ctx.get::<usize>(grand,Arc::new(3u128)))?;retain_derived(&c,256,&a,key)?;}else{retain_derived(&c,if value==2{300}else{256},&a,key)?;}
   Ok(Outcome::new(value as usize,value,if value==2{300}else{256}))
  });
  let parent=Budget::new(1024).unwrap();parent.charge(96).unwrap();let temporary=parent.temporary_charge();assert!(temporary+812<=1024);
  assert_eq!(*admission.with_child(&parent,&charge,left,||db.get::<usize>(left,Arc::new(1u128))).unwrap(),1);assert_eq!(charge.load(Ordering::Acquire),512);assert_eq!(parent.temporary_charge(),temporary);
  assert_eq!(*admission.with_child(&parent,&charge,right,||db.get::<usize>(right,Arc::new(2u128))).unwrap(),2);assert_eq!(charge.load(Ordering::Acquire),812);assert_eq!(parent.temporary_charge(),temporary);
  let used=parent.used();let computed=db.stats(kind).computed;for(key,id)in[(left,1u128),(right,2),(grand,3)]{admission.with_child(&parent,&charge,key,||db.get::<usize>(key,Arc::new(id))).unwrap();}assert_eq!(parent.used(),used);assert_eq!(db.stats(kind).computed,computed);assert_eq!(admission.limit.load(Ordering::Acquire),1024);
 }
}

impl Admission{
 pub(super) fn admit_handlers(&self,owner:Weak<crate::input_snapshot::HandlerPreparedCapture>,key:Key,bytes:usize)->Result<(),QueryError>{
  let bytes=bytes.checked_add(std::mem::size_of::<Lease>()).and_then(|n|n.checked_add(std::mem::size_of::<crate::input_snapshot::HandlerPreparedCapture>())).and_then(|n|n.checked_add(2*std::mem::size_of::<usize>()+128)).ok_or_else(||QueryError::operational(key,io::Error::new(io::ErrorKind::OutOfMemory,"handler result metadata overflow")))?;
  let mut leases=self.leases.lock().unwrap_or_else(|e|e.into_inner());let total=leases.iter().filter(|(k,_)|**k!=key).try_fold(bytes,|n,(_,lease)|n.checked_add(lease.bytes));let count=leases.len().checked_add(usize::from(!leases.contains_key(&key))).and_then(|n|n.checked_add(self.workspace_nodes.load(Ordering::Acquire)));
  if total.is_none_or(|n|n>INPUT_BUDGET)||count.is_none_or(|n|n>MAX_NODES){self.denied.store(true,Ordering::Release);return Err(QueryError::operational(key,io::Error::new(io::ErrorKind::OutOfMemory,"handler partial result admission exceeds existing family")))}
  leases.insert(key,Lease{owner:LeaseOwner::Handlers(owner),bytes,touched:Instant::now()});Ok(())
 }
}

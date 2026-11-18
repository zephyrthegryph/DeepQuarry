//! Native pattern compilation is ONE typed value in the existing Db.
//! Full pattern source/mode parameters are owned query DATA, never source/currentness proof.
use super::*;
use dm_preprocess::source_arena_credit::{SourceArenaCredit,SourceArenaWork};
use dq_analyze::native_pattern::{self,Spec,Program,CompileFailure};
use dq_analyze::native_pattern::admission::{Admission,Hook,Refused};
use std::{error::Error,fmt,io,sync::{Arc,Mutex}};
// Diagnostics cannot replace the actual operational error or panic in Drop.
fn native_frontier_trace(args:core::fmt::Arguments<'_>){let _=std::io::Write::write_fmt(&mut std::io::stderr().lock(),format_args!("{}\n",args));}

pub(super) const NATIVE_PATTERN:Kind=Kind(33);
struct Params{pattern:String,mode:native_pattern::Mode,_metadata:SourceArenaCredit}
impl Params{fn spec(&self)->Spec<'_>{Spec{pattern:&self.pattern,mode:self.mode}}}
// Field order is custody: actual program then source credit retire before its
// SAME parent-budget payload charge. Params remain independently node-owned.
struct OwnedProgram{params:Arc<Params>,program:Program,_credit:SourceArenaCredit,_budget_retention:std::sync::OnceLock<dq_analyze::captured_generator_budget::RetainedPayloadCharge>}
/// This borrow is used only during the scoped computation. Neither the lender,
/// hook nor query owner is retained by the resulting compiled program.
struct Compilation<'a>{work:&'a dyn SourceArenaWork,context:crate::daemon::control::WorkerContext,first:Mutex<Option<io::Error>>,credit:Mutex<Option<SourceArenaCredit>>,phase:Mutex<RetainedPhaseState>}
#[derive(Default)]struct RetainedPhaseState{next:u64,active:Option<(u64,usize,u8)>,composite:Option<(u64,usize)>}
fn invalid(message:&'static str)->io::Error{io::Error::new(io::ErrorKind::InvalidData,message)}
impl Compilation<'_>{
 fn refuse(&self,actual:io::Error)->Refused{self.first.lock().unwrap_or_else(|e|e.into_inner()).get_or_insert(actual);Refused}
 fn prior(&self)->bool{self.first.lock().unwrap_or_else(|e|e.into_inner()).is_some()}
 fn take_first(&mut self)->Option<io::Error>{self.first.get_mut().unwrap_or_else(|e|e.into_inner()).take()}
 fn take_credit(&mut self)->io::Result<SourceArenaCredit>{self.credit.get_mut().unwrap_or_else(|e|e.into_inner()).take().ok_or_else(||invalid("native pattern compilation credit was already moved"))}
 fn settle_phase(&self,serial:u64,retained:usize,finish:bool,builder_checkpoint:bool)->Result<(),Refused>{
  self.checkpoint()?;let mut phase=self.phase.lock().unwrap_or_else(|e|e.into_inner());
  let (issued,start,checkpointed)=phase.active.ok_or_else(||self.refuse(invalid("native retained phase absent or already consumed")))?;
  if issued!=serial||(!finish&&checkpointed!=u8::from(builder_checkpoint)){return Err(self.refuse(invalid("native retained phase out of order, repeated or foreign")))}
  let keep=start.checked_add(retained).ok_or_else(||self.refuse(io::ErrorKind::OutOfMemory.into()))?;
  let mut credit=self.credit.lock().unwrap_or_else(|e|e.into_inner());let credit=credit.as_mut().ok_or_else(||self.refuse(invalid("native phase credit already moved")))?;
  let released=credit.reserved_bytes().checked_sub(keep).ok_or_else(||self.refuse(invalid("native retained phase exceeded its preadmission")))?;
  if std::env::var_os("DMB_ORIGINAL_TRACE_PATTERN_FRONTIER").is_some(){native_frontier_trace(format_args!("NATIVE_PATTERN_PHASE serial={} finish={} prior_checkpoint={} start={} kept={} credit={} release={}",serial,finish,checkpointed!=0,start,retained,credit.reserved_bytes(),released))}
  self.work.shrink(credit,released).map_err(|actual|self.refuse(actual))?;if finish{phase.active=None;}else{phase.active=Some((serial,start,1+u8::from(builder_checkpoint)));}Ok(())
 }

}
impl Admission for Compilation<'_>{
 fn checkpoint(&self)->Result<(),Refused>{if self.prior(){return Err(Refused)}self.context.checkpoint().and_then(|()|self.work.checkpoint()).map_err(|actual|self.refuse(actual))}
 fn reserve(&self,bytes:usize)->Result<(),Refused>{self.checkpoint()?;let mut credit=self.credit.lock().unwrap_or_else(|e|e.into_inner());let actual=credit.as_mut().ok_or_else(||self.refuse(invalid("native pattern work has no actual retained credit")))?;self.work.grow(actual,bytes).map_err(|error|{if std::env::var_os("DMB_ORIGINAL_TRACE_PATTERN_FRONTIER").is_some(){native_frontier_trace(format_args!("NATIVE_PATTERN_GROW_REFUSED requested={} credit={} error={}",bytes,actual.reserved_bytes(),error))}self.refuse(error)})}
 fn begin_retained_phase(&self)->Result<Option<u64>,Refused>{
  self.checkpoint()?;let mut phase=self.phase.lock().unwrap_or_else(|e|e.into_inner());
  if phase.active.is_some(){return Err(self.refuse(invalid("native retained compiler phases cannot overlap")))}
  let serial=phase.next.checked_add(1).ok_or_else(||self.refuse(io::ErrorKind::OutOfMemory.into()))?;
  let credit=self.credit.lock().unwrap_or_else(|e|e.into_inner());let start=credit.as_ref().ok_or_else(||self.refuse(invalid("native phase credit already moved")))?.reserved_bytes();
  phase.next=serial;phase.active=Some((serial,start,0));Ok(Some(serial))
 }
 fn settle_retained_phase(&self,serial:u64,retained:usize)->Result<(),Refused>{self.settle_phase(serial,retained,true,false)}
 fn checkpoint_retained_phase(&self,serial:u64,retained:usize)->Result<(),Refused>{self.settle_phase(serial,retained,false,false)}
 fn checkpoint_retained_builder_phase(&self,serial:u64,retained:usize)->Result<(),Refused>{self.settle_phase(serial,retained,false,true)}

 fn abandon_retained_phase(&self,serial:u64){
  let mut phase=self.phase.lock().unwrap_or_else(|e|e.into_inner());
  if phase.active.is_some_and(|(issued,_,_)|issued==serial){phase.active=None}else{self.refuse(invalid("native retained phase abandoned out of order"));}
 }
 fn begin_retained_composite_phase(&self)->Result<Option<u64>,Refused>{
  self.checkpoint()?;let mut phase=self.phase.lock().unwrap_or_else(|e|e.into_inner());
  if phase.active.is_some()||phase.composite.is_some(){return Err(self.refuse(invalid("native composite phase overlaps an active producer")))}
  let serial=phase.next.checked_add(1).ok_or_else(||self.refuse(io::ErrorKind::OutOfMemory.into()))?;
  let credit=self.credit.lock().unwrap_or_else(|e|e.into_inner());let start=credit.as_ref().ok_or_else(||self.refuse(invalid("native composite credit already moved")))?.reserved_bytes();
  phase.next=serial;phase.composite=Some((serial,start));Ok(Some(serial))
 }
 fn settle_retained_composite_phase(&self,serial:u64,retained:usize)->Result<(),Refused>{
  self.checkpoint()?;let mut phase=self.phase.lock().unwrap_or_else(|e|e.into_inner());
  let (issued,start)=phase.composite.ok_or_else(||self.refuse(invalid("native composite phase absent or consumed")))?;
  if issued!=serial||phase.active.is_some(){return Err(self.refuse(invalid("native composite phase is foreign or still has a live child")))}
  let keep=start.checked_add(retained).ok_or_else(||self.refuse(io::ErrorKind::OutOfMemory.into()))?;
  let mut credit=self.credit.lock().unwrap_or_else(|e|e.into_inner());let credit=credit.as_mut().ok_or_else(||self.refuse(invalid("native composite credit already moved")))?;
  let released=credit.reserved_bytes().checked_sub(keep).ok_or_else(||self.refuse(invalid("native composite exceeds actual preadmission")))?;
  if std::env::var_os("DMB_ORIGINAL_TRACE_PATTERN_FRONTIER").is_some(){native_frontier_trace(format_args!("NATIVE_PATTERN_COMPOSITE serial={} start={} kept={} credit={} release={}",serial,start,retained,credit.reserved_bytes(),released))}
  self.work.shrink(credit,released).map_err(|actual|self.refuse(actual))?;phase.composite=None;Ok(())
 }
 fn abandon_retained_composite_phase(&self,serial:u64){
  let mut phase=self.phase.lock().unwrap_or_else(|e|e.into_inner());
  if phase.composite.is_some_and(|(issued,_)|issued==serial)&&phase.active.is_none(){phase.composite=None}else{self.refuse(invalid("native composite abandoned out of order or with live child"));}
 }
 fn overflow(&self)->Refused{self.refuse(io::ErrorKind::OutOfMemory.into())}
 fn allocation_failed(&self)->Refused{self.refuse(io::ErrorKind::OutOfMemory.into())}
}
struct FundedCompileError{message:String,_credit:SourceArenaCredit}
impl fmt::Debug for FundedCompileError{fn fmt(&self,f:&mut fmt::Formatter<'_>)->fmt::Result{f.debug_struct("FundedCompileError").field("message",&self.message).finish()}}
impl fmt::Display for FundedCompileError{fn fmt(&self,f:&mut fmt::Formatter<'_>)->fmt::Result{f.write_str(&self.message)}}
impl Error for FundedCompileError{}
fn key(spec:Spec)->Key{Key::new(NATIVE_PATTERN,spec.fingerprint())}
pub(super)fn register(db:&Db){
 db.define(NATIVE_PATTERN,"native-admitted-compiled-pattern",|_,params|{
  let params=params.downcast_ref::<Params>().ok_or(QueryError::Missing(Key::new(NATIVE_PATTERN,0)))?;
  // A payload eviction is not permission to invoke an unadmitted constructor.
  // The public host path re-enters this SAME node with its scoped real lender.
  Err(QueryError::operational(key(params.spec()),invalid("native pattern recomputation requires its actual scoped allocation lender")))
 });
}
impl QueryDb{
 /// No gate, ledger, SourceArenaWork or callback is retained in owned Params.
 /// A caller already under the raw-family gate must pass its real held lender.
 pub(crate)fn with_native_pattern<R>(&self,spec:Spec,work:&dyn SourceArenaWork,consume:impl FnOnce(&Program)->io::Result<R>)->io::Result<R>{self.with_native_pattern_using(spec,work,None,consume)}
 fn with_native_pattern_using<R>(&self,spec:Spec,work:&dyn SourceArenaWork,scope:Option<&dyn PatternWorkLender>,consume:impl FnOnce(&Program)->io::Result<R>)->io::Result<R>{
  crate::daemon::control::checkpoint()?;
  if crate::daemon::control::current_deadline().is_none(){return Err(invalid("native pattern lookup requires the original active request deadline"))}
  let context=crate::daemon::control::WorkerContext::capture_for_checkpoints().ok_or_else(||invalid("native pattern requires its actual prepublication context"))?;
  context.checkpoint()?;
  let actual_key=key(spec);
  // Immutable programs have no source inputs. Reuse the actual retained owner
  // only after exact source/mode + real domain validation; no Params copy or
  // optional pre-work grant is needed on this pure compiled-value hit.
  if let Some(owner)=self.db.retained_value::<OwnedProgram>(actual_key){
   if owner.params.spec()!=spec||owner.program.signature()!=spec.fingerprint(){return Err(invalid("native compiled pattern belongs to different exact Params"))}
   self.require_native_pattern_credit(&owner._credit)?;
   self.require_native_pattern_credit(&owner.params._metadata)?;
   work.checkpoint()?;let result=consume(&owner.program);if result.is_err(){return result}work.checkpoint()?;return result;
  }

  // An exact hit above retains warm reuse. On a miss the actual family may
  // retire only unborrowed completed programs BEFORE any new admission fails.
  // This is pressure handling, never a retry of a lost first operational IO.
  if let Some(scope)=scope{scope.prepare_miss(self)?;}
  // This owns the actual Params Arc only. Existing Db graph bookkeeping has
  // its existing framework admission/census contract; this is not a claim
  // that a Params credit owns shared shard HashMap/BTree backing.
  let metadata_bytes=spec.pattern.len().checked_add(std::mem::size_of::<Params>()).and_then(|n|n.checked_add(2*std::mem::size_of::<usize>())).ok_or(io::ErrorKind::OutOfMemory)?;
  let metadata=work.reserve(metadata_bytes)?;
  self.require_native_pattern_credit(&metadata)?;
  let mut pattern=String::new();pattern.try_reserve_exact(spec.pattern.len()).map_err(|_|io::Error::from(io::ErrorKind::OutOfMemory))?;
  if pattern.capacity()>spec.pattern.len(){return Err(io::ErrorKind::OutOfMemory.into())}pattern.push_str(spec.pattern);
  let params=Arc::new(Params{pattern,mode:spec.mode,_metadata:metadata});
  let actual_params=Arc::clone(&params);
  let owner=self.db.get_with_scoped_computation::<OwnedProgram>(actual_key,params,|_,params|{
   let params=params.downcast_ref::<Params>().ok_or_else(||QueryError::operational(actual_key,invalid("native pattern Params have the wrong actual type")))?;
   if params.spec()!=spec||key(params.spec())!=actual_key||actual_params.spec()!=params.spec(){return Err(QueryError::operational(actual_key,invalid("native pattern exact Params/key differ")))}
   let compute=move |work:&dyn SourceArenaWork|->Result<(Outcome,usize),QueryError>{
   let credit=work.reserve(std::mem::size_of::<Compilation<'_>>()+std::mem::size_of::<OwnedProgram>()+std::mem::size_of::<FundedCompileError>()+8*std::mem::size_of::<usize>()).map_err(|actual|QueryError::operational(actual_key,actual))?;
   self.require_native_pattern_credit(&credit).map_err(|actual|QueryError::operational(actual_key,actual))?;
   let compilation=Arc::new(Compilation{work,context:context.clone(),first:Mutex::new(None),credit:Mutex::new(Some(credit)),phase:Mutex::new(RetainedPhaseState::default())});
   let hook=Hook(Some(compilation.clone()));
   // Program only seals after exact actual-hook issuance is rechecked. The
   // produced program contains no lender, compiled-registry cache or fixture.
   if std::env::var_os("DMB_ORIGINAL_TRACE_PATTERN_FRONTIER").is_some(){let spec=actual_params.spec();if spec.pattern.len()<=512{native_frontier_trace(format_args!("NATIVE_PATTERN_COMPILE_BEGIN fingerprint={:032x} mode={:?} bytes={} source={:?}",spec.fingerprint(),spec.mode,spec.pattern.len(),spec.pattern))}else{native_frontier_trace(format_args!("NATIVE_PATTERN_COMPILE_BEGIN fingerprint={:032x} mode={:?} bytes={} source=omitted_over512",spec.fingerprint(),spec.mode,spec.pattern.len()))}}
   let result=native_pattern::compile(actual_params.spec(),&hook);
   if std::env::var_os("DMB_ORIGINAL_TRACE_PATTERN_FRONTIER").is_some(){native_frontier_trace(format_args!("NATIVE_PATTERN_COMPILE_RETURN fingerprint={:032x} success={}",actual_params.spec().fingerprint(),result.is_ok()))}
   drop(hook);
   if let Some(first)=compilation.first.lock().unwrap_or_else(|e|e.into_inner()).take(){return Err(QueryError::operational(actual_key,first))}
   let mut compilation=Arc::try_unwrap(compilation).map_err(|_|QueryError::operational(actual_key,invalid("native compiler retained a borrowed allocation hook")))?;
   if let Some(first)=compilation.take_first(){return Err(QueryError::operational(actual_key,first))}
   let mut credit=compilation.take_credit().map_err(|actual|QueryError::operational(actual_key,actual))?;
   let program=match result{
    Ok(program)=>program,
    Err(CompileFailure::Refused)=>return Err(QueryError::operational(actual_key,invalid("native compiler refused without its actual first operational error"))),
    Err(CompileFailure::Invalid(message))=>return Err(QueryError::operational(actual_key,io::Error::new(io::ErrorKind::InvalidData,FundedCompileError{message,_credit:credit}))),
   };
   // All parser/compiler temporaries and borrowed hooks have dropped. This
   // census can only REFUND a reservation already admitted before allocation.
   let retained=program.retained_bytes().and_then(|n|n.checked_add(std::mem::size_of::<OwnedProgram>()))
    .and_then(|n|n.checked_add(2*std::mem::size_of::<usize>()))
    .ok_or_else(||QueryError::operational(actual_key,io::Error::from(io::ErrorKind::OutOfMemory)))?;
   let release=credit.reserved_bytes().checked_sub(retained)
    .ok_or_else(||QueryError::operational(actual_key,invalid("native program exceeded its actual preadmitted retained extent")))?;
   work.shrink(&mut credit,release).map_err(|actual|QueryError::operational(actual_key,actual))?;
   let bytes=credit.reserved_bytes();
   Ok((Outcome::new(OwnedProgram{params:actual_params,program,_credit:credit,_budget_retention:std::sync::OnceLock::new()},spec.fingerprint(),bytes),bytes))
   };
   if let Some(scope)=scope{
    let mut compute=Some(compute);
    scope.with_compile(actual_key,&mut|work|{let compute=compute.take().ok_or_else(||QueryError::operational(actual_key,invalid("native compile scope repeated")))?;compute(work)})
   }else{compute(work).map(|(actual,_)|actual)}

  }).map_err(|error|match error.into_operational(){Ok(actual)=>actual.into_io(),Err(_)=>invalid("native compiled pattern query did not produce its actual admitted value")})?;
  // A fingerprint locates a node; it does not establish exact pattern equality.
  if owner.params.spec()!=spec||owner.program.signature()!=spec.fingerprint(){return Err(invalid("native compiled pattern belongs to a different exact pattern/mode"))}
  work.checkpoint()?;let result=consume(&owner.program);if result.is_err(){return result}work.checkpoint()?;result
 }
 /// A fresh operation-local scratch loan on the SAME source-family lender.
 /// The immutable compiled value is the existing query node above; scratch is
 /// neither cached nor retained by that node, and its actual first IO wins.
 fn with_native_pattern_execution<R:ExecutionResult>(&self,spec:Spec,work:&dyn SourceArenaWork,consume:impl FnOnce(&Program,&Hook<'_>)->io::Result<R>)->io::Result<R>{
  self.with_native_pattern(spec,work,|program|{
   let credit=work.reserve(std::mem::size_of::<Compilation<'_>>()+2*std::mem::size_of::<usize>())?;
   let (actual,credit)=self.execute_native_program_credit(program,work,credit,consume)?;drop(credit);Ok(actual)
  })
 }
 fn execute_native_program_credit<R:ExecutionResult>(&self,program:&Program,work:&dyn SourceArenaWork,mut credit:SourceArenaCredit,consume:impl FnOnce(&Program,&Hook<'_>)->io::Result<R>)->io::Result<(R,SourceArenaCredit)>{
  let context=crate::daemon::control::WorkerContext::capture_for_checkpoints().ok_or_else(||invalid("native search requires original request context"))?;context.checkpoint()?;
  self.require_native_pattern_credit(&credit)?;
  let minimum=std::mem::size_of::<Compilation<'_>>()+2*std::mem::size_of::<usize>();
  if credit.reserved_bytes()<minimum{let extra=minimum-credit.reserved_bytes();work.grow(&mut credit,extra)?;}
   let compilation=Arc::new(Compilation{work,context:context.clone(),first:Mutex::new(None),credit:Mutex::new(Some(credit)),phase:Mutex::new(RetainedPhaseState::default())});
   let hook=Hook(Some(compilation.clone()));let result=consume(program,&hook);drop(hook);
   if let Some(first)=compilation.first.lock().unwrap_or_else(|e|e.into_inner()).take(){return Err(first)}
   // An already returned visitor IO precedes any later ownership check. The
   // failed result is never published or retained as a compiled completion.
   let actual=match result{Ok(actual)=>actual,Err(first)=>return Err(first)};
   let mut compilation=Arc::try_unwrap(compilation).map_err(|_|invalid("native search retained its borrowed resource hook"))?;
   if let Some(first)=compilation.take_first(){return Err(first)}
   // Only sealed heap-free results leave this private executor. Actual
   // provider visitors receive borrowed rows and copy under their own existing
   // output owner before these real execution buffers retire.
   let credit=compilation.take_credit()?;drop(compilation);Ok((actual,credit))
 }

}

mod scalar_result{pub trait Sealed{}impl Sealed for (){}impl Sealed for bool{}impl Sealed for usize{}}
trait ExecutionResult:scalar_result::Sealed{}impl ExecutionResult for (){}impl ExecutionResult for bool{}impl ExecutionResult for usize{}
/// Install retirement only on this actual not-yet-published compiled outcome.
/// No caller-supplied estimated bytes may credit another source/budget owner.
pub(super)fn retain_program_payload(outcome:Outcome,retained:usize,child:&dq_analyze::captured_generator_budget::Budget,parent:&Arc<dq_analyze::captured_generator_budget::Budget>)->io::Result<Outcome>{
 let owner=outcome.value.downcast_ref::<OwnedProgram>().ok_or_else(||invalid("retained native program has another actual value type"))?;
 let fixed=std::mem::size_of::<OwnedProgram>().checked_add(2*std::mem::size_of::<usize>()).ok_or(io::ErrorKind::OutOfMemory)?;
 let payload=owner.program.retained_bytes().ok_or(io::ErrorKind::OutOfMemory)?;
 if owner._credit.reserved_bytes()!=retained||outcome.bytes!=retained||payload.checked_add(fixed)!=Some(retained)||owner._budget_retention.get().is_some(){return Err(invalid("native retained payload differs from its actual compiled credit"))}
 let charge=child.transfer_scoped_retained_payload(parent,retained,payload).map_err(|message|io::Error::new(io::ErrorKind::InvalidData,message))?;
 match owner._budget_retention.set(charge){Ok(())=>Ok(outcome),Err(charge)=>{drop(outcome);charge.keep_failed();Err(invalid("native program retained budget was already issued"))}}
}

/// One operation-local mutable reservation, not a program/fact cache. The
/// issuer returns it only after actual execution buffers and hooks have dropped.
pub(crate) trait PatternWorkLender:Sync{
 fn prepare_miss(&self,db:&QueryDb)->io::Result<()>;
 fn with_compile(&self,key:Key,compute:&mut dyn FnMut(&dyn SourceArenaWork)->Result<(Outcome,usize),QueryError>)->Result<Outcome,QueryError>;
 fn with_scratch(&self,visit:&mut dyn FnMut(&dyn SourceArenaWork,SourceArenaCredit)->io::Result<SourceArenaCredit>)->io::Result<()>;
}
/// Borrowed facade over the SAME session Db and the actual active family loan.
/// No pattern cache, source observation, TLS or persistent callback is created.
pub(crate) struct PatternProvider<'a>{db:&'a QueryDb,work:&'a dyn SourceArenaWork,scratch:Option<&'a dyn PatternWorkLender>}
impl<'a> PatternProvider<'a>{
 pub(crate)fn new(db:&'a QueryDb,work:&'a dyn SourceArenaWork)->Self{Self{db,work,scratch:None}}
 pub(crate)fn scoped(db:&'a QueryDb,work:&'a dyn SourceArenaWork,scratch:&'a dyn PatternWorkLender)->Self{Self{db,work,scratch:Some(scratch)}}
 fn execution(&self,spec:Spec,consume:impl FnOnce(&Program,&Hook<'_>)->io::Result<bool>)->io::Result<bool>{
  self.db.with_native_pattern_using(spec,self.work,self.scratch,|program|{
   let Some(scratch)=self.scratch else{let credit=self.work.reserve(std::mem::size_of::<Compilation<'_>>()+2*std::mem::size_of::<usize>())?;let(actual,credit)=self.db.execute_native_program_credit(program,self.work,credit,consume)?;drop(credit);return Ok(actual)};
   let mut consume=Some(consume);let mut result=None;
   scratch.with_scratch(&mut|work,credit|{
    let consume=consume.take().ok_or_else(||invalid("native scratch callback repeated"))?;
    let(actual,credit)=self.db.execute_native_program_credit(program,work,credit,consume)?;result=Some(actual);Ok(credit)
   })?;
   result.ok_or_else(||invalid("native scratch loan did not execute actual operation"))
  })
 }
}
impl native_pattern::Provider for PatternProvider<'_>{
 fn validate(&self,spec:Spec)->io::Result<native_pattern::Validation>{
  match self.db.with_native_pattern_using(spec,self.work,self.scratch,|_|Ok(())){
   Ok(())=>Ok(native_pattern::Validation::Valid),
   Err(actual)if actual.get_ref().is_some_and(|inner|inner.is::<FundedCompileError>())=>Ok(native_pattern::Validation::Invalid(actual)),
   Err(actual)=>Err(actual),
  }
 }

 fn capture_len(&self,spec:Spec)->io::Result<usize>{self.db.with_native_pattern_using(spec,self.work,self.scratch,|program|Ok(program.capture_len()))}
 fn find(&self,spec:Spec,text:&str,start:usize,visit:&mut dyn FnMut((usize,usize))->io::Result<()>)->io::Result<bool>{
  self.execution(spec,|program,hook|{
   match program.find_at(text,start,hook){Ok(Some(bounds))=>{visit(bounds)?;Ok(true)},Ok(None)=>Ok(false),Err(_)=>Err(invalid("native find refused; actual owner retains first IO"))}
  })
 }
 fn capture(&self,spec:Spec,text:&str,start:usize,visit:&mut dyn FnMut(&[Option<(usize,usize)>])->io::Result<()>)->io::Result<bool>{
  self.execution(spec,|program,hook|{
   let result=program.captures_at(text,start,hook);
   match result{
    Ok(Some(actual))=>{visit(&actual)?;Ok(true)},
    Ok(None)=>Ok(false),
    Err(_)=>Err(invalid("native search refused; operation owner must return its latched actual error")),
   }
  })
 }
}

#[cfg(test)]mod controls{
 use super::*;
 use dq_analyze::native_pattern::Mode;
 use std::{sync::atomic::{AtomicUsize,Ordering},time::{Duration,Instant}};
 // Every issued credit is still minted by the actual QueryDb. This adapter
 // injects only an operational boundary; it cannot manufacture a grant.
 struct StopGrow<'a>{actual:&'a QueryDb,calls:AtomicUsize,kind:io::ErrorKind}
 impl SourceArenaWork for StopGrow<'_>{
  fn checkpoint(&self)->io::Result<()>{SourceArenaWork::checkpoint(self.actual)}
  fn reserve(&self,n:usize)->io::Result<SourceArenaCredit>{SourceArenaWork::reserve(self.actual,n)}
  fn grow(&self,_:&mut SourceArenaCredit,_:usize)->io::Result<()>{self.calls.fetch_add(1,Ordering::SeqCst);if self.kind==io::ErrorKind::Other{Err(io::Error::from_raw_os_error(1450))}else{Err(self.kind.into())}}
  fn shrink(&self,c:&mut SourceArenaCredit,n:usize)->io::Result<()>{SourceArenaWork::shrink(self.actual,c,n)}
 }
 fn binding()->crate::daemon::control::Binding{crate::daemon::control::bind_with_deadline(Default::default(),Instant::now()+Duration::from_secs(120))}
 #[test]fn actual_native_program_uses_same_query_node_exact_mode_and_refunds_retired_program(){
  let _bound=binding();let db=QueryDb::default();
  let spec=Spec{pattern:r"(?<![\w/])(?:SEND_SIGNAL|SEND_GLOBAL_SIGNAL)\s*\(|\bSIGNAL_HANDLER\b",mode:Mode::Search};
  let mut address=0usize;
  db.with_native_pattern_execution(spec,&db,|program,hook|{
   address=program as *const Program as usize;
   let found=program.captures_at("x.SEND_SIGNAL(src)",0,hook).map_err(|_|invalid("actual admission unexpectedly failed"))?.unwrap();assert_eq!(found[0],Some((2,14)));Ok(())
  }).unwrap();
  db.with_native_pattern(spec,&db,|program|{assert_eq!(program as *const Program as usize,address);Ok(())}).unwrap();
  assert_eq!(db.db.stats(NATIVE_PATTERN).computed,1);
  let before=db.source_input_admission_bytes().unwrap();let bytes=db.db.evict_values(&[NATIVE_PATTERN]);assert!(bytes>0);
  assert!(db.source_input_admission_bytes().unwrap()<before,"real program buffers release with their actual query owner");
  db.with_native_pattern(spec,&db,|_|Ok(())).unwrap();assert_eq!(db.db.stats(NATIVE_PATTERN).computed,2);
  assert_ne!(spec.fingerprint(),Spec{mode:Mode::Full,..spec}.fingerprint());
 }
 #[test]fn actual_compile_growth_first_io_cancel_and_pressure_do_not_publish_then_same_db_recovers(){
  let _bound=binding();let db=QueryDb::default();let spec=Spec{pattern:r"\w+(?=!)",mode:Mode::Search};
  for kind in [io::ErrorKind::Other,io::ErrorKind::Interrupted,io::ErrorKind::OutOfMemory]{
   let stop=StopGrow{actual:&db,calls:AtomicUsize::new(0),kind};
   let error=db.with_native_pattern(spec,&stop,|_|Err::<(),_>(invalid("later visitor must not run"))).unwrap_err();
   if kind==io::ErrorKind::Other{assert_eq!(error.raw_os_error(),Some(1450))}else{assert_eq!(error.kind(),kind)}
   assert_eq!(stop.calls.load(Ordering::SeqCst),1);assert_eq!(db.db.value_bytes_at(key(spec)),0);assert_eq!(db.db.stats(NATIVE_PATTERN).computed,0);
  }
  db.with_native_pattern_execution(spec,&db,|program,hook|{assert!(program.captures_at("yes!",0,hook).map_err(|_|invalid("actual search failed"))?.is_some());Ok(())}).unwrap();
  assert_eq!(db.db.stats(NATIVE_PATTERN).computed,1);
 }
 #[test]fn foreign_real_source_credit_is_not_a_native_program_resource_owner(){
  let _bound=binding();let db=QueryDb::default();let other=QueryDb::default();let credit=SourceArenaWork::reserve(&other,1024).unwrap();
  assert_eq!(db.require_native_pattern_credit(&credit).unwrap_err().kind(),io::ErrorKind::InvalidInput);
  assert!(other.require_native_pattern_credit(&credit).is_ok());
 }
 #[test]fn admitted_existing_engines_preserve_legacy_modes_groups_unicode_lookarounds_and_backrefs(){
  let _bound=binding();let db=QueryDb::default();
  for(source,hay)in [
   (r"(?<![\w.])spawn\s*\(","x.spawn(0) spawn (1)"),
   (r"(?<![\w/])SEND\s*\(|\bHANDLER\b","x/HANDLER SEND("),
   (r"([a-z])\1(?=x)","aax bbx cx"),
   (r"(?P<word>\w+)(?:\s+(\d+))?","Ã©clair 12"),
   (r"(?=.)","Ã©ðŸ˜€"),
   (r"[Ã©](?=x)","Ã©x"),
   (r"a|ab","ab"),
  ]{
   for mode in [Mode::Search,Mode::Match,Mode::Full]{
    let spec=Spec{pattern:source,mode};
    // Reference is the unchanged Pat constructor, never a second DM frontend.
    // Its unrelated process-owned test allocations are not a resource proof.
    let old=match mode{Mode::Search=>dq_analyze::pat::Pat::new(source),Mode::Match=>dq_analyze::pat::Pat::new_match(source),Mode::Full=>dq_analyze::pat::Pat::new_full(source)};
    let expected=old.captures(hay).map(|row|row.groups);
    db.with_native_pattern_execution(spec,&db,|program,hook|{
     let actual=program.captures_at(hay,0,hook).map_err(|_|invalid("actual admitted engine refused"))?;
     assert_eq!(actual,expected,"source={source:?} mode={mode:?}");
     let found=program.find_at(hay,0,hook).map_err(|_|invalid("actual admitted find refused"))?;
     assert_eq!(found,old.find(hay).map(|row|(row.start,row.end)),"actual separate find contract source={source:?} mode={mode:?}");
     assert_eq!(program.capture_len(),old.capture_group_count());Ok(())
    }).unwrap();
   }
  }
 }
 #[test]fn actual_ten_registered_callbacks_use_real_session_program_loans_and_preserve_shared_assertion_text(){
  let _bound=binding();let db=QueryDb::default();
  let _fixture_credit=SourceArenaWork::reserve(&db,dq_analyze::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES).unwrap();
  let provider=PatternProvider::new(&db,&db);
  for name in ["cap_bits","dcs","entry_slots","reactions_table_proc","sys/dx_manual_transfer","sys/dx_raw_delay","sys/dx_raw_overlays","sys/dx_review","sys/sync_sql","sys/usr_use"]{
   // The reference path is solely an assertion/text oracle. Its legacy regex
   // allocations are explicitly not included in an RSS/resource-fit claim.
   let expected=dq_analyze::captured_raw_policy::registered_selftest(name).unwrap();
   let budget=dq_analyze::captured_generator_budget::Budget::new(dq_analyze::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES).unwrap();
   let actual=dq_analyze::captured_raw_policy::registered_selftest_funded_with_patterns(name,&budget,&crate::daemon::control::checkpoint,&provider).unwrap();
   match(expected,actual){
    (Ok(old),Ok(actual))=>assert_eq!(old,actual,"{name}"),
    (Err(old),Err(dq_analyze::derived_selftest_policy::Failure::Assertion(actual)))=>assert_eq!(old,actual,"{name}"),
    other=>panic!("actual native callback disagreed for {name}: {other:?}"),
   }
  }
  assert!(db.db.stats(NATIVE_PATTERN).computed>0);
 }
}

#[cfg(test)]mod borrowed_pattern_parameter_controls{
 use super::*;
 #[test]fn actual_owned_params_survive_borrowed_source_drop_and_compare_exact_mode(){
  let _binding=crate::daemon::control::bind_with_deadline(Default::default(),std::time::Instant::now()+std::time::Duration::from_secs(120));
  let db=QueryDb::default();let mut address=0;
  {let source=String::from("config_(?:alpha|beta)");db.with_native_pattern(Spec{pattern:&source,mode:native_pattern::Mode::Search},&db,|program|{address=program as *const _ as usize;Ok(())}).unwrap();}
  let source=String::from("config_(?:alpha|beta)");
  db.with_native_pattern(Spec{pattern:&source,mode:native_pattern::Mode::Search},&db,|program|{assert_eq!(program as *const _ as usize,address);Ok(())}).unwrap();
  db.with_native_pattern(Spec{pattern:&source,mode:native_pattern::Mode::Full},&db,|program|{assert_ne!(program as *const _ as usize,address);Ok(())}).unwrap();
 }
}

#[cfg(test)]mod validation_disposition_controls{
 use super::*;
 #[test]fn actual_invalid_pattern_validation_retains_typed_compile_owner_but_never_classifies_real_1450_as_syntax(){
  use std::sync::atomic::{AtomicUsize,Ordering};
  struct Stop<'a>{db:&'a QueryDb,calls:AtomicUsize}
  impl SourceArenaWork for Stop<'_>{
   fn checkpoint(&self)->io::Result<()>{SourceArenaWork::checkpoint(self.db)}
   fn reserve(&self,n:usize)->io::Result<SourceArenaCredit>{SourceArenaWork::reserve(self.db,n)}
   fn grow(&self,_:&mut SourceArenaCredit,_:usize)->io::Result<()>{self.calls.fetch_add(1,Ordering::SeqCst);Err(io::Error::from_raw_os_error(1450))}
   fn shrink(&self,c:&mut SourceArenaCredit,n:usize)->io::Result<()>{SourceArenaWork::shrink(self.db,c,n)}
  }
  let _binding=crate::daemon::control::bind_with_deadline(Default::default(),std::time::Instant::now()+std::time::Duration::from_secs(120));
  let db=QueryDb::default();let bad=Spec{pattern:"(",mode:native_pattern::Mode::Search};let provider=PatternProvider::new(&db,&db);
  let invalid=native_pattern::Provider::validate(&provider,bad).unwrap();let native_pattern::Validation::Invalid(actual)=invalid else{panic!("actual invalid syntax must retain its typed funded diagnostic")};assert!(actual.get_ref().is_some_and(|inner|inner.is::<FundedCompileError>()));assert_eq!(db.db.stats(NATIVE_PATTERN).computed,0);drop(actual);
  let stop=Stop{db:&db,calls:AtomicUsize::new(0)};let denied=PatternProvider::new(&db,&stop);let actual=native_pattern::Provider::validate(&denied,bad).unwrap_err();assert_eq!(actual.raw_os_error(),Some(1450));assert!(stop.calls.load(Ordering::SeqCst)>0);assert_eq!(db.db.stats(NATIVE_PATTERN).computed,0);
  let good=Spec{pattern:"(good)",mode:native_pattern::Mode::Search};assert!(matches!(native_pattern::Provider::validate(&provider,good).unwrap(),native_pattern::Validation::Valid));assert_eq!(native_pattern::Provider::capture_len(&provider,good).unwrap(),2);assert_eq!(db.db.stats(NATIVE_PATTERN).computed,1);
 }
}

#[cfg(test)]mod specialized_policy_controls{
 use super::*;use dq_analyze::{captured_generator_budget::Budget,captured_raw_file::{File,RawPolicyViews,Config},captured_raw_policy::Configuration,captured_reactive_reads::Failure,reactive_raw_policy_pages::RawPolicyPages};
 struct Pages{files:Vec<File>}
 impl RawPolicyPages for Pages{fn for_each(&self,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{for file in &self.files{if !file.with_policy_views(visit)?{return Ok(false)}}Ok(true)}}
 fn pages()->Pages{
  // Authored lexical DATA only. These pages cannot issue Original or source EOF authority.
  let root=std::env::current_dir().unwrap();let rows=[
   ("code/alpha/model.dm","SYSTEM_DEF(alpha)\nGLOBAL_LIST_INIT(shared, list(1,2))\n/datum/system/alpha\n    needs = list(/datum/system/missing)\n/obj/a\n    var/cached_value\n/obj/a/process()\n    cached_value = world.time + 10\n    if(world.time > cached_value)\n        return\n/obj/a/values()\n    return GLOB.shared\n/obj/a/constant()\n    return list(1,2)\n/obj/a/Initialize()\n\treturn INITIALIZE_HINT_QDEL\n/obj/a/call()\n    om_prompt(src)\n    om_task_start(1,2,3,list(1))\n    SSalpha.hidden\n"),
   ("code/alpha/api.dm","/datum/system/alpha/proc/allowed()\n    return 1\n"),
   ("maps/case.dm","CAPABILITIES(/obj/a)\n\tmap_resolver(PROC_REF(build))\n/obj/b/Initialize()\n\tqdel(src)\n")];
  Pages{files:rows.into_iter().map(|(rel,text)|File::capture(&root,&root.join(rel),text.to_owned().into()).unwrap()).collect()}
 }
 #[test]fn actual_specialized_policy_readers_match_all_rows_text_usage_and_reuse_same_db_programs(){
  let _binding=crate::daemon::control::bind_with_deadline(Default::default(),std::time::Instant::now()+std::time::Duration::from_secs(120));let db=QueryDb::default();let pages=pages();let config=Config::capture(Configuration::ProvenMissing).unwrap();
  let execute=||{let budget=Budget::new(64*1024*1024).unwrap();db.with_native_fixture_patterns(&budget,|provider|{
   macro_rules! compare{($module:ident)=>{{
    let expected=dq_analyze::$module::collect(&pages,&config,&budget,&||Ok(())).map_err(|actual|match actual{Failure::Operational(actual)=>actual,Failure::Unsupported(message)=>io::Error::other(message)})?;
    let actual=dq_analyze::$module::collect_with_patterns(&pages,&config,&budget,&||Ok(()),provider).map_err(|actual|match actual{Failure::Operational(actual)=>actual,Failure::Unsupported(message)=>io::Error::other(message)})?;
    assert_eq!(actual.sites(),expected.sites(),stringify!($module));assert_eq!(actual.source_text(),expected.source_text(),stringify!($module));assert_eq!(actual.allow_used(),expected.allow_used(),stringify!($module));
   }}}
   compare!(captured_sys_hygiene_pages);compare!(captured_sys_resolvers_pages);compare!(captured_sys_tables_pages);compare!(captured_system_boundary_pages);compare!(captured_api_pages);compare!(captured_sys_fields_pages);compare!(captured_sys_appearance_pages);Ok(())
  })};execute().unwrap();let computed=db.db.stats(NATIVE_PATTERN).computed;assert!(computed>0,"actual same-Db producer compiled the requested programs");execute().unwrap();assert_eq!(db.db.stats(NATIVE_PATTERN).computed,computed,"second admitted operation reuses exact same pattern/key equality");
 }
}


#[cfg(test)]mod retained_plain_phase_controls{
 use super::*;use dq_analyze::native_pattern::Mode;
 fn bound()->crate::daemon::control::Binding{crate::daemon::control::bind_with_deadline(Default::default(),std::time::Instant::now()+std::time::Duration::from_secs(120))}
 fn owner<'a>(work:&'a dyn SourceArenaWork)->Arc<Compilation<'a>>{Arc::new(Compilation{work,context:crate::daemon::control::WorkerContext::capture_for_checkpoints().unwrap(),first:Mutex::new(None),credit:Mutex::new(Some(work.reserve(std::mem::size_of::<Compilation<'_>>()).unwrap())),phase:Mutex::new(RetainedPhaseState::default())})}
 #[test]fn retained_plain_phase_tokens_reject_foreign_overlapping_out_of_order_and_reused_settlement(){
  let _bound=bound();let db=QueryDb::default();let a=owner(&db);let b=owner(&db);let ah=Hook(Some(a.clone()));let bh=Hook(Some(b.clone()));
  let phase=ah.retained_phase().unwrap();assert!(phase.settle(&bh,0).is_err());assert!(a.phase.lock().unwrap().active.is_none());assert!(b.prior());
  let a=owner(&db);let ah=Hook(Some(a.clone()));let phase=ah.retained_phase().unwrap();assert!(ah.retained_phase().is_err());drop(phase);assert!(a.prior());
  let a=owner(&db);let serial=a.begin_retained_phase().unwrap().unwrap();a.reserve(200).unwrap();a.settle_retained_phase(serial,80).unwrap();assert!(a.settle_retained_phase(serial,0).is_err());
  let a=owner(&db);let serial=a.begin_retained_phase().unwrap().unwrap();assert!(a.settle_retained_phase(serial+1,0).is_err());
 }
 #[test]fn actual_phase_compile_first_1450_is_not_replaced_by_abandonment_or_settlement(){
  use std::sync::atomic::{AtomicUsize,Ordering};
  struct Stop<'a>{db:&'a QueryDb,calls:AtomicUsize}
  impl SourceArenaWork for Stop<'_>{fn checkpoint(&self)->io::Result<()>{SourceArenaWork::checkpoint(self.db)}fn reserve(&self,n:usize)->io::Result<SourceArenaCredit>{SourceArenaWork::reserve(self.db,n)}fn grow(&self,_:&mut SourceArenaCredit,_:usize)->io::Result<()>{self.calls.fetch_add(1,Ordering::SeqCst);Err(io::Error::from_raw_os_error(1450))}fn shrink(&self,c:&mut SourceArenaCredit,n:usize)->io::Result<()>{SourceArenaWork::shrink(self.db,c,n)}}
  let _bound=bound();let db=QueryDb::default();let stop=Stop{db:&db,calls:AtomicUsize::new(0)};let spec=Spec{pattern:r"(?<![\w.])spawn\s*\(",mode:Mode::Search};let e=db.with_native_pattern(spec,&stop,|_|Ok(())).unwrap_err();assert_eq!(e.raw_os_error(),Some(1450));assert_eq!(stop.calls.load(Ordering::SeqCst),1);assert_eq!(db.db.value_bytes_at(key(spec)),0);
 }
}

#[cfg(test)]mod retained_parser_checkpoint_controls{
 use super::*;
 #[test]fn actual_same_phase_parser_checkpoint_retires_dead_backing_and_keeps_active_identity_and_live_product(){
  let _bound=crate::daemon::control::bind_with_deadline(Default::default(),std::time::Instant::now()+std::time::Duration::from_secs(120));let db=QueryDb::default();
  let owner=Arc::new(Compilation{work:&db,context:crate::daemon::control::WorkerContext::capture_for_checkpoints().unwrap(),first:Mutex::new(None),credit:Mutex::new(Some(SourceArenaWork::reserve(&db,256).unwrap())),phase:Mutex::new(RetainedPhaseState::default())});let hook=Hook(Some(owner.clone()));let mut phase=hook.retained_phase().unwrap();
  owner.reserve(65536).unwrap();let dead=vec![7u8;65536];owner.reserve(128).unwrap();let live=vec![9u8;128];drop(dead);
  phase.checkpoint(&hook,live.capacity()).unwrap();assert_eq!(owner.credit.lock().unwrap().as_ref().unwrap().reserved_bytes(),256+live.capacity());assert!(owner.phase.lock().unwrap().active.is_some());assert_eq!(live[127],9);
  owner.reserve(64).unwrap();let next=vec![3u8;64];drop(live);drop(next);phase.settle(&hook,0).unwrap();assert_eq!(owner.credit.lock().unwrap().as_ref().unwrap().reserved_bytes(),256);assert!(owner.phase.lock().unwrap().active.is_none());
  let serial=owner.begin_retained_phase().unwrap().unwrap();assert!(owner.checkpoint_retained_phase(serial+1,0).is_err());assert!(owner.prior(),"foreign or stale serial cannot retire active allocations");
  let another=Arc::new(Compilation{work:&db,context:crate::daemon::control::WorkerContext::capture_for_checkpoints().unwrap(),first:Mutex::new(None),credit:Mutex::new(Some(SourceArenaWork::reserve(&db,256).unwrap())),phase:Mutex::new(RetainedPhaseState::default())});let serial=another.begin_retained_phase().unwrap().unwrap();another.reserve(64).unwrap();let live=vec![1u8;64];another.checkpoint_retained_phase(serial,live.capacity()).unwrap();let funded=another.credit.lock().unwrap().as_ref().unwrap().reserved_bytes();assert!(another.checkpoint_retained_phase(serial,0).is_err());assert_eq!(another.credit.lock().unwrap().as_ref().unwrap().reserved_bytes(),funded,"a reused checkpoint cannot refund a still-live product");drop(live);
 }
 #[test]fn actual_parser_checkpoint_then_native_compiler_io_keeps_first_1450_and_no_published_program(){
  use std::sync::atomic::{AtomicBool,Ordering};
  struct StopAfterRetirement<'a>{db:&'a QueryDb,retired:AtomicBool}
  impl SourceArenaWork for StopAfterRetirement<'_>{
   fn checkpoint(&self)->io::Result<()>{SourceArenaWork::checkpoint(self.db)}
   fn reserve(&self,n:usize)->io::Result<SourceArenaCredit>{SourceArenaWork::reserve(self.db,n)}
   fn grow(&self,c:&mut SourceArenaCredit,n:usize)->io::Result<()>{if self.retired.load(Ordering::Acquire){Err(io::Error::from_raw_os_error(1450))}else{SourceArenaWork::grow(self.db,c,n)}}
   fn shrink(&self,c:&mut SourceArenaCredit,n:usize)->io::Result<()>{SourceArenaWork::shrink(self.db,c,n)?;self.retired.store(true,Ordering::Release);Ok(())}
  }
  let _bound=crate::daemon::control::bind_with_deadline(Default::default(),std::time::Instant::now()+std::time::Duration::from_secs(120));let db=QueryDb::default();let work=StopAfterRetirement{db:&db,retired:AtomicBool::new(false)};let spec=Spec{pattern:r"(?m)^(/\w[\w/ ]*?)/(attackby|attack_hand|attack_self|click_alt)\(",mode:native_pattern::Mode::Search};
  let error=db.with_native_pattern(spec,&work,|_|Ok(())).unwrap_err();assert!(work.retired.load(Ordering::Acquire),"actual successful parser checkpoint preceded injected compiler failure");assert_eq!(error.raw_os_error(),Some(1450));assert_eq!(db.db.value_bytes_at(key(spec)),0);
 }

}

#[cfg(test)]mod program_pressure_retirement_controls{
 use super::*;use dq_analyze::{captured_generator_budget::Budget,native_pattern::Mode};
 fn bound()->crate::daemon::control::Binding{crate::daemon::control::bind_with_deadline(Default::default(),std::time::Instant::now()+std::time::Duration::from_secs(120))}
 #[test]fn actual_native_pattern_misses_reclaim_cold_programs_under_same_one_mib_parent_and_keep_exact_hits(){
  let _bound=bound();let db=QueryDb::default();let budget=Budget::new(1<<20).unwrap();
  db.with_native_fixture_patterns(&budget,|provider|{
   for n in 0..48{let pattern=format!(r"(?m)^(/\w[\w/ ]*?)/(attackby|attack_hand|attack_self|click_alt)\(suffix{n}");assert_eq!(provider.capture_len(Spec{pattern:&pattern,mode:Mode::Search})?,3);}
   let compiled=db.db.stats(NATIVE_PATTERN).computed;assert_eq!(compiled,48);assert!(db.db.stats(NATIVE_PATTERN).evicted>0,"real cold compiled owners retired before later misses");
   let last=r"(?m)^(/\w[\w/ ]*?)/(attackby|attack_hand|attack_self|click_alt)\(suffix47";assert_eq!(provider.capture_len(Spec{pattern:last,mode:Mode::Search})?,3);assert_eq!(db.db.stats(NATIVE_PATTERN).computed,compiled,"same exact hit keeps warm program reuse");Ok(())
  }).unwrap();assert!(!budget.denied());assert!(budget.used()<=1<<20);
 }
 #[test]fn actual_escaped_program_strong_and_weak_aliases_keep_payload_charge_until_last_real_payload_drop(){
  let _bound=bound();let db=QueryDb::default();let budget=Budget::new(1<<20).unwrap();let spec=Spec{pattern:r"(\w+)escaped_owner",mode:Mode::Search};
  db.with_native_fixture_patterns(&budget,|provider|{
   provider.capture_len(spec)?;let escaped=db.db.retained_value::<OwnedProgram>(key(spec)).unwrap();let weak=Arc::downgrade(&escaped);let payload=escaped.program.retained_bytes().unwrap();let before=budget.used();
   assert_eq!(db.db.evict_unborrowed_values(&[NATIVE_PATTERN]),0,"escaped strong or weak owner is not a cold cache-only value");assert_eq!(budget.used(),before);
   assert!(db.db.evict_value_at(key(spec))>0);assert_eq!(budget.used(),before,"cache removal alone cannot refund a live escaped program");assert_eq!(escaped.program.capture_len(),2);
   drop(escaped);assert!(weak.upgrade().is_none());assert_eq!(budget.used(),before-payload,"actual NFA teardown refunds its exact original payload only");assert!(budget.used()>=std::mem::size_of::<OwnedProgram>()+2*std::mem::size_of::<usize>(),"fixed wrapper/control funding stays conservative while weak lives");drop(weak);Ok(())
  }).unwrap();
 }
 #[test]fn actual_retained_program_budget_lease_never_refunds_a_later_or_foreign_scope(){
  let _bound=bound();let db=QueryDb::default();let old=Budget::new(1<<20).unwrap();let spec=Spec{pattern:r"(\w+)old_scope",mode:Mode::Search};db.with_native_fixture_patterns(&old,|provider|provider.capture_len(spec)).unwrap();let expired=Arc::downgrade(&old);drop(old);assert!(expired.upgrade().is_none(),"program lease retains no budget/Work/Db strong cycle");let fresh=Budget::new(1<<20).unwrap();let before=fresh.used();assert!(db.db.evict_unborrowed_values(&[NATIVE_PATTERN])>0);assert_eq!(fresh.used(),before,"expired original scope has no authority over a new budget");
 }
}

#[cfg(test)]mod quarter_cache_headroom_controls{
 use super::*;use dq_analyze::{captured_generator_budget::Budget,native_pattern::Mode};
 #[test]fn actual_quarter_occupied_family_retires_cold_values_before_real_registry_peak_and_reuses_exact_hit(){
  let _bound=crate::daemon::control::bind_with_deadline(Default::default(),std::time::Instant::now()+std::time::Duration::from_secs(120));let db=QueryDb::default();let budget=Budget::new(1<<20).unwrap();
  db.with_native_fixture_patterns(&budget,|provider|{
   let mut crossed=false;
   for n in 0..256{let pattern=format!(r"(\w+)quarter_cache_{n}");assert_eq!(provider.capture_len(Spec{pattern:&pattern,mode:Mode::Search})?,2);if budget.used()>budget.allocation_limit()/4{crossed=true;break}}
   assert!(crossed,"real compiled programs, not fake charged bytes, establish cache pressure");assert!(budget.used()<budget.allocation_limit()/2,"old half-full policy would not evict at this actual pre-miss state");let before=db.db.stats(NATIVE_PATTERN).evicted;
   const REGISTRY:&str=r"\bGLOB\.(\w+)\s*(?:\+=|\|=)\s*src\b|\bGLOB\.(\w+)\.(?:Add|Insert)\((?:[^()]*,\s*)?src\)|\bGLOB\.(\w+)\[[^\]]*\]\s*=\s*src\b";
   assert!(include_str!("../../../../../analyze/src/lints/registry.rs").contains(REGISTRY),"exercise the actual authored registry signature");let spec=Spec{pattern:REGISTRY,mode:Mode::Search};assert_eq!(provider.capture_len(spec)?,4);assert!(db.db.stats(NATIVE_PATTERN).evicted>before,"proactive retirement precedes this larger cold compile, without retrying a denial");let compiled=db.db.stats(NATIVE_PATTERN).computed;assert_eq!(provider.capture_len(spec)?,4);assert_eq!(db.db.stats(NATIVE_PATTERN).computed,compiled,"exact current hit bypasses pressure eviction");Ok(())
  }).unwrap();assert!(!budget.denied());assert!(budget.used()<=budget.allocation_limit());
 }
}

#[cfg(test)]mod inline_utf8_grants_controls{
 use super::*;use dq_analyze::{captured_generator_budget::Budget,native_pattern::Mode};
 #[test]fn actual_grants_unicode_signature_and_mixed_classes_preserve_legacy_captures_under_same_parent(){
  let _bound=crate::daemon::control::bind_with_deadline(Default::default(),std::time::Instant::now()+std::time::Duration::from_secs(120));let db=QueryDb::default();let budget=Budget::new(1<<20).unwrap();
  const GRANTS:&str=r"\badd_verb\s*\(|\bremove_verb\s*\(|\bverbs\s*(\+|-|\||&|\^)=|\bverbs\s*=(?!=)|\bverbs\s*\.\s*(Add|Remove|Cut|Insert|Swap|Splice)\s*\(|\bverbs\s*\[[^\]]*\]\s*=(?!=)|\bnew\s*/[\w/]*/(proc|verb)/\w+\s*\(";
  assert!(include_str!("../../../../../analyze/src/lints/sys_grants.rs").contains(GRANTS));
  db.with_native_fixture_patterns(&budget,|provider|{
   for pattern in[GRANTS,r"(\w+)[\s\p{Greek}]+(\w+)",r"(?:[\p{Greek}\p{Cyrillic}]+|\w{2,4})+(\s*)"]{
    let spec=Spec{pattern,mode:Mode::Search};let old=dq_analyze::pat::Pat::new(pattern);assert_eq!(provider.capture_len(spec)?,old.capture_group_count());
    for hay in["new /datum/verb/show(","new /Î”Î¿ÎºÎ¹Î¼Î®/verb/Î´ÎµÎ¯Î¾Îµ(","verbs |=","Î±Î² Ð–Ð–","abc Î´ Î´Îµ",""]{
     let mut actual=None;let matched=provider.capture(spec,hay,0,&mut|rows|{actual=Some(rows.to_vec());Ok(())})?;let expected=old.captures(hay).map(|row|row.groups);assert_eq!(matched,expected.is_some());assert_eq!(actual,expected,"actual Unicode captures pattern={pattern} hay={hay}");
    }
    let owner=db.db.retained_value::<OwnedProgram>(key(spec)).unwrap();let retained=owner.program.retained_bytes().unwrap();assert_eq!(owner._credit.reserved_bytes(),retained+std::mem::size_of::<OwnedProgram>()+2*std::mem::size_of::<usize>());drop(owner);
   }Ok(())
  }).unwrap();assert!(!budget.denied());
 }
}

#[cfg(test)]mod expected_plain_syntax_retirement_controls{
 use super::*;use dq_analyze::{captured_generator_budget::Budget,native_pattern::Mode};
 #[test]fn actual_expected_plain_syntax_failure_retires_dead_scratch_then_preserves_first_fallback_io(){
  use std::sync::atomic::{AtomicBool,AtomicUsize,Ordering};
  struct Observed<'a>{db:&'a QueryDb,released:AtomicUsize,stop:AtomicBool}
  impl SourceArenaWork for Observed<'_>{
   fn checkpoint(&self)->io::Result<()>{SourceArenaWork::checkpoint(self.db)}
   fn reserve(&self,n:usize)->io::Result<SourceArenaCredit>{SourceArenaWork::reserve(self.db,n)}
   fn grow(&self,c:&mut SourceArenaCredit,n:usize)->io::Result<()>{if self.stop.load(Ordering::Acquire)&&self.released.load(Ordering::Acquire)!=0{return Err(io::Error::from_raw_os_error(1450))}SourceArenaWork::grow(self.db,c,n)}
   fn shrink(&self,c:&mut SourceArenaCredit,n:usize)->io::Result<()>{SourceArenaWork::shrink(self.db,c,n)?;self.released.fetch_add(n,Ordering::AcqRel);Ok(())}
  }
  let _bound=crate::daemon::control::bind_with_deadline(Default::default(),std::time::Instant::now()+std::time::Duration::from_secs(120));let db=QueryDb::default();
  // Build real alternating literal AST owners before the unclosed class.
  // Both ordinary parsers reject; no successful delegate can masquerade as
  // retirement. A bare "[" need not create any dead backing beyond its error.
  let work=Observed{db:&db,released:AtomicUsize::new(0),stop:AtomicBool::new(false)};let invalid=Spec{pattern:"ab|cd|ef|gh|ij|kl|mn|op|qr|st|uv|wx|yz[",mode:Mode::Search};let error=db.with_native_pattern(invalid,&work,|_|Ok(())).unwrap_err();assert_eq!(error.kind(),io::ErrorKind::InvalidData);assert!(work.released.load(Ordering::Acquire)>0,"a genuine returned syntax error settles dead parser owners before fallback");assert_eq!(db.db.value_bytes_at(key(invalid)),0);
  let work=Observed{db:&db,released:AtomicUsize::new(0),stop:AtomicBool::new(true)};let spec=Spec{pattern:r"\w+(?=x)",mode:Mode::Search};let error=db.with_native_pattern(spec,&work,|_|Ok(())).unwrap_err();assert!(work.released.load(Ordering::Acquire)>0);assert_eq!(error.raw_os_error(),Some(1450));assert_eq!(db.db.value_bytes_at(key(spec)),0,"actual operational fallback failure publishes no program");
 }
 #[test]fn actual_grants_fancy_fallback_and_prefilter_keep_captures_with_live_native_owners_under_same_one_mib(){
  let _bound=crate::daemon::control::bind_with_deadline(Default::default(),std::time::Instant::now()+std::time::Duration::from_secs(120));let db=QueryDb::default();let budget=Budget::new(1<<20).unwrap();let mut aliases=Vec::new();
  db.with_native_fixture_patterns(&budget,|provider|{
   for n in 0..64{let source=format!(r"(\w+)held_native_{n}");let spec=Spec{pattern:&source,mode:Mode::Search};assert_eq!(provider.capture_len(spec)?,2);aliases.push(db.db.retained_value::<OwnedProgram>(key(spec)).unwrap());if budget.used()>budget.allocation_limit()/3{break}}
   assert!(budget.used()>budget.allocation_limit()/3&&budget.used()<budget.allocation_limit()/2,"genuine escaped programs create concurrent family occupancy; no artificial filler charge");
   const GRANTS:&str=r"\badd_verb\s*\(|\bremove_verb\s*\(|\bverbs\s*(\+|-|\||&|\^)=|\bverbs\s*=(?!=)|\bverbs\s*\.\s*(Add|Remove|Cut|Insert|Swap|Splice)\s*\(|\bverbs\s*\[[^\]]*\]\s*=(?!=)|\bnew\s*/[\w/]*/(proc|verb)/\w+\s*\(";
   assert!(include_str!("../../../../../analyze/src/lints/sys_grants.rs").contains(GRANTS));let spec=Spec{pattern:GRANTS,mode:Mode::Search};let old=dq_analyze::pat::Pat::new(GRANTS);
   for text in["new /datum/verb/show(","new /Δοκιμή/verb/δείξε(","verbs |=","verbs ==",""]{
    let expected=old.captures(text).map(|r|r.groups);let mut actual=None;provider.capture(spec,text,0,&mut|r|{actual=Some(r.to_vec());Ok(())})?;assert_eq!(actual,expected);
    let mut actual_find=None;provider.find(spec,text,0,&mut|r|{actual_find=Some(r);Ok(())})?;assert_eq!(actual_find,old.find(text).map(|r|(r.start,r.end)),"the optional prefilter remains semantically active");
   }
   let owner=db.db.retained_value::<OwnedProgram>(key(spec)).unwrap();assert_eq!(owner._credit.reserved_bytes(),owner.program.retained_bytes().unwrap()+std::mem::size_of::<OwnedProgram>()+2*std::mem::size_of::<usize>());assert!(!budget.denied());Ok(())
  }).unwrap();drop(aliases);assert!(!budget.denied());
 }
}

#[cfg(test)]mod fancy_composite_retirement_controls{
 use super::*;use std::sync::atomic::{AtomicBool,Ordering};
 fn owner(db:&QueryDb)->Arc<Compilation<'_>>{Arc::new(Compilation{work:db,context:crate::daemon::control::WorkerContext::capture_for_checkpoints().unwrap(),first:Mutex::new(None),credit:Mutex::new(Some(SourceArenaWork::reserve(db,std::mem::size_of::<Compilation<'_>>()).unwrap())),phase:Mutex::new(RetainedPhaseState::default())})}
 fn bytes(owner:&Compilation<'_>)->usize{owner.credit.lock().unwrap().as_ref().unwrap().reserved_bytes()}
 fn bound()->crate::daemon::control::Binding{crate::daemon::control::bind_with_deadline(Default::default(),std::time::Instant::now()+std::time::Duration::from_secs(120))}
 #[test]fn actual_composite_phase_keeps_child_baseline_and_retires_only_after_last_child_and_temporary_drop(){
  let _bound=bound();let db=QueryDb::default();let owner=owner(&db);let hook=Hook(Some(owner.clone()));let before=bytes(&owner);let parent=hook.retained_composite_phase().unwrap();
  owner.reserve(100).unwrap();let temporary=vec![1u8;100];let child=hook.retained_phase().unwrap();owner.reserve(200).unwrap();let product=vec![2u8;200];child.settle(&hook,product.capacity()).unwrap();assert_eq!(bytes(&owner),before+300,"child baseline preserves its composite's still-live temporary");drop(temporary);parent.settle(&hook,product.capacity()).unwrap();assert_eq!(bytes(&owner),before+200);assert!(owner.phase.lock().unwrap().active.is_none());assert!(owner.phase.lock().unwrap().composite.is_none());assert!(owner.first.lock().unwrap().is_none());assert_eq!(product[0],2);drop(product);
 }
 #[test]fn actual_composite_phase_rejects_foreign_nested_live_child_and_stale_coordinates_without_refund(){
  let _bound=bound();let db=QueryDb::default();
  let a=owner(&db);let b=owner(&db);let ah=Hook(Some(a.clone()));let bh=Hook(Some(b.clone()));let parent=ah.retained_composite_phase().unwrap();a.reserve(32).unwrap();let before=bytes(&a);assert!(parent.settle(&bh,0).is_err());assert_eq!(bytes(&a),before);
  let a=owner(&db);let h=Hook(Some(a.clone()));let _parent=h.retained_composite_phase().unwrap();let before=bytes(&a);assert!(h.retained_composite_phase().is_err());assert_eq!(bytes(&a),before);
  let a=owner(&db);let h=Hook(Some(a.clone()));let child=h.retained_phase().unwrap();let before=bytes(&a);assert!(h.retained_composite_phase().is_err());assert_eq!(bytes(&a),before);drop(child);
  let a=owner(&db);let h=Hook(Some(a.clone()));let parent=h.retained_composite_phase().unwrap();a.reserve(64).unwrap();let child=h.retained_phase().unwrap();let before=bytes(&a);assert!(parent.settle(&h,0).is_err());assert_eq!(bytes(&a),before);assert!(a.phase.lock().unwrap().composite.is_some());drop(child);
  let a=owner(&db);let serial=a.begin_retained_composite_phase().unwrap().unwrap();a.reserve(64).unwrap();a.settle_retained_composite_phase(serial,0).unwrap();let before=bytes(&a);assert!(a.settle_retained_composite_phase(serial,0).is_err());assert_eq!(bytes(&a),before);
 }
 #[test]fn actual_composite_failed_child_abandon_preserves_first_1450_and_keeps_funded_payload(){
  struct Fail<'a>{db:&'a QueryDb,fail:AtomicBool}
  impl SourceArenaWork for Fail<'_>{fn checkpoint(&self)->io::Result<()>{SourceArenaWork::checkpoint(self.db)}fn reserve(&self,n:usize)->io::Result<SourceArenaCredit>{SourceArenaWork::reserve(self.db,n)}fn grow(&self,c:&mut SourceArenaCredit,n:usize)->io::Result<()>{if self.fail.load(Ordering::Acquire){return Err(io::Error::from_raw_os_error(1450))}SourceArenaWork::grow(self.db,c,n)}fn shrink(&self,c:&mut SourceArenaCredit,n:usize)->io::Result<()>{SourceArenaWork::shrink(self.db,c,n)}}
  let _bound=bound();let db=QueryDb::default();let work=Fail{db:&db,fail:AtomicBool::new(false)};let a=Arc::new(Compilation{work:&work,context:crate::daemon::control::WorkerContext::capture_for_checkpoints().unwrap(),first:Mutex::new(None),credit:Mutex::new(Some(work.reserve(std::mem::size_of::<Compilation<'_>>()).unwrap())),phase:Mutex::new(RetainedPhaseState::default())});let h=Hook(Some(a.clone()));let parent=h.retained_composite_phase().unwrap();a.reserve(64).unwrap();let live=vec![9u8;64];let child=h.retained_phase().unwrap();let before=bytes(&a);work.fail.store(true,Ordering::Release);assert!(a.reserve(1).is_err());drop(parent);assert!(child.settle(&h,0).is_err());assert_eq!(bytes(&a),before);assert_eq!(a.first.lock().unwrap().as_ref().unwrap().raw_os_error(),Some(1450));assert_eq!(live[0],9);drop(live);
 }
}

#[cfg(test)]mod frozen_builder_checkpoint_controls{
 use super::*;use std::sync::atomic::{AtomicBool,Ordering};
 fn owner(db:&QueryDb)->Arc<Compilation<'_>>{Arc::new(Compilation{work:db,context:crate::daemon::control::WorkerContext::capture_for_checkpoints().unwrap(),first:Mutex::new(None),credit:Mutex::new(Some(SourceArenaWork::reserve(db,std::mem::size_of::<Compilation<'_>>()).unwrap())),phase:Mutex::new(RetainedPhaseState::default())})}
 fn bytes(owner:&Compilation<'_>)->usize{owner.credit.lock().unwrap().as_ref().unwrap().reserved_bytes()}
 #[test]fn actual_frozen_builder_checkpoint_requires_same_owner_hir_order_and_one_use_without_losing_live_product(){
  let _bound=crate::daemon::control::bind_with_deadline(Default::default(),std::time::Instant::now()+std::time::Duration::from_secs(120));let db=QueryDb::default();
  let a=owner(&db);let h=Hook(Some(a.clone()));let mut phase=h.retained_phase().unwrap();let before=bytes(&a);assert!(phase.checkpoint_builder(&h,0).is_err());assert_eq!(bytes(&a),before);
  let a=owner(&db);let h=Hook(Some(a.clone()));let mut phase=h.retained_phase().unwrap();a.reserve(128).unwrap();let product=vec![3u8;128];phase.checkpoint(&h,product.capacity()).unwrap();a.reserve(64).unwrap();let dead=vec![1u8;64];let funded=bytes(&a);drop(dead);phase.checkpoint_builder(&h,product.capacity()).unwrap();assert_eq!(bytes(&a),funded-64);assert_eq!(a.phase.lock().unwrap().active.unwrap().2,2);let before=bytes(&a);assert!(phase.checkpoint_builder(&h,0).is_err());assert_eq!(bytes(&a),before);assert_eq!(product[0],3);drop(product);
  let a=owner(&db);let b=owner(&db);let ah=Hook(Some(a.clone()));let bh=Hook(Some(b.clone()));let mut phase=ah.retained_phase().unwrap();a.reserve(64).unwrap();phase.checkpoint(&ah,64).unwrap();let before=bytes(&a);assert!(phase.checkpoint_builder(&bh,0).is_err());assert_eq!(bytes(&a),before);
  let a=owner(&db);let serial=a.begin_retained_phase().unwrap().unwrap();let before=bytes(&a);assert!(a.checkpoint_retained_builder_phase(serial,0).is_err());assert_eq!(bytes(&a),before,"owner rejects bypass of the named HIR stage too");
 }
 #[test]fn actual_frozen_builder_retirement_keeps_first_1450_and_credit_if_physical_shrink_refuses(){
  struct Stop<'a>{db:&'a QueryDb,stop:AtomicBool}
  impl SourceArenaWork for Stop<'_>{fn checkpoint(&self)->io::Result<()>{SourceArenaWork::checkpoint(self.db)}fn reserve(&self,n:usize)->io::Result<SourceArenaCredit>{SourceArenaWork::reserve(self.db,n)}fn grow(&self,c:&mut SourceArenaCredit,n:usize)->io::Result<()>{SourceArenaWork::grow(self.db,c,n)}fn shrink(&self,c:&mut SourceArenaCredit,n:usize)->io::Result<()>{if self.stop.load(Ordering::Acquire){return Err(io::Error::from_raw_os_error(1450))}SourceArenaWork::shrink(self.db,c,n)}}
  let _bound=crate::daemon::control::bind_with_deadline(Default::default(),std::time::Instant::now()+std::time::Duration::from_secs(120));let db=QueryDb::default();let work=Stop{db:&db,stop:AtomicBool::new(false)};let a=Arc::new(Compilation{work:&work,context:crate::daemon::control::WorkerContext::capture_for_checkpoints().unwrap(),first:Mutex::new(None),credit:Mutex::new(Some(work.reserve(std::mem::size_of::<Compilation<'_>>()).unwrap())),phase:Mutex::new(RetainedPhaseState::default())});let h=Hook(Some(a.clone()));let mut phase=h.retained_phase().unwrap();a.reserve(128).unwrap();let product=vec![2u8;128];phase.checkpoint(&h,product.capacity()).unwrap();a.reserve(64).unwrap();let dead=vec![1u8;64];drop(dead);let before=bytes(&a);work.stop.store(true,Ordering::Release);assert!(phase.checkpoint_builder(&h,product.capacity()).is_err());assert_eq!(bytes(&a),before);assert_eq!(a.phase.lock().unwrap().active.unwrap().2,1);assert!(phase.settle(&h,0).is_err());assert_eq!(a.first.lock().unwrap().as_ref().unwrap().raw_os_error(),Some(1450));assert_eq!(product[0],2);drop(product);
 }
}

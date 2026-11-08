//! Distinct typed partial-policy child in the existing Kind12 result family.
//! No full semantic guard, second model store or raw/body parser is introduced.
use super::*;
use dq_analyze::{captured_generator_budget::Budget,captured_reactive_reads::Failure};
#[path="handler_structural_staging.rs"]
pub(crate) mod handler_structural_staging;
#[derive(serde::Serialize)]pub(crate) struct StructuralFinding{pub rule:&'static str,pub relative:String,pub line:u32,pub message:String}
#[derive(serde::Serialize)]pub(crate) struct StructuralData{issuance:u64,rows:Vec<StructuralFinding>}
impl StructuralData{pub(crate) fn rows(&self)->&[StructuralFinding]{&self.rows}fn charge(&self)->Option<usize>{let fixed=std::mem::size_of::<Result<Self,String>>().checked_add(2*std::mem::size_of::<usize>())?.checked_add(self.rows.capacity().checked_mul(std::mem::size_of::<StructuralFinding>())?)?;self.rows.iter().try_fold(fixed,|n,row|n.checked_add(row.relative.capacity())?.checked_add(row.message.capacity()))}}
pub(super) struct Params{key:Key,issuance:u64}
fn actual(f:Failure)->io::Error{match f{Failure::Operational(error)=>error,Failure::Unsupported(message)=>io::Error::new(io::ErrorKind::Unsupported,message)}}
fn checkpoint(b:&Budget)->Result<(),Failure>{crate::daemon::control::checkpoint()?;b.require().map_err(|m|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,m)))}
fn reserve(b:&Budget,n:Option<usize>)->Result<(),Failure>{let n=n.ok_or_else(||{b.deny();Failure::Operational(io::ErrorKind::OutOfMemory.into())})?;b.charge(n).map_err(|m|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,m)))}
pub(super) fn compute(ctx:&mut dm_query::Ctx<'_>,p:&Params,charge:&AtomicUsize,admission:&Admission)->Result<Outcome,QueryError>{
 admission.abort.before_outcome(p.key)?;let loan=admission.current_handlers_operation(p.issuance).map_err(|error|QueryError::operational(p.key,error))?;let b=&loan.budget;let mut rows:Vec<StructuralFinding>=Vec::new();
 let produced=super::super::handlers_source_adapter::collect_structural_in(&loan.queries,ctx,&loan.capture,&loan.proof,b,|rule,relative,line,message|{
  checkpoint(b)?;if rows.len()==rows.capacity(){let capacity=rows.capacity().checked_mul(2).map(|n|n.max(4)).ok_or_else(||{b.deny();Failure::Operational(io::ErrorKind::OutOfMemory.into())})?;reserve(b,capacity.checked_mul(std::mem::size_of::<StructuralFinding>()*4).and_then(|n|n.checked_add(128)))?;rows.try_reserve_exact(capacity-rows.len()).map_err(|_|Failure::Operational(io::ErrorKind::OutOfMemory.into()))?;if rows.capacity()>capacity.checked_mul(4).ok_or_else(||{b.deny();Failure::Operational(io::ErrorKind::OutOfMemory.into())})?{b.deny();return Err(Failure::Operational(io::ErrorKind::OutOfMemory.into()))}}
  reserve(b,relative.len().checked_add(64))?;let mut copied=String::new();copied.try_reserve_exact(relative.len()).map_err(|_|Failure::Operational(io::ErrorKind::OutOfMemory.into()))?;copied.push_str(relative);
  // The body scratch releases its charge on success. The same String now
  // belongs to this result, so admit its actual capacity before publication.
  reserve(b,Some(message.capacity()))?;rows.push(StructuralFinding{rule,relative:copied,line,message});Ok(())
 });
 let value:Result<StructuralData,String>=match produced{Ok(())=>Ok(StructuralData{issuance:p.issuance,rows}),Err(Failure::Operational(error))=>return Err(QueryError::operational(p.key,error)),Err(Failure::Unsupported(message))=>Err(message)};
 let(bytes,hash)=match &value{Ok(data)=>(data.charge().ok_or_else(||QueryError::operational(p.key,io::Error::from(io::ErrorKind::OutOfMemory)))?,super::reactive_read_policy::metadata_key(data).map_err(|e|QueryError::operational(p.key,e))?.id),Err(message)=>(result_error_charge::<StructuralData>(message),error_hash(message))};
 retain_derived(charge,bytes,admission,p.key)?;admission.abort.before_outcome(p.key)?;checkpoint(b).map_err(|f|QueryError::operational(p.key,actual(f)))?;Ok(Outcome::new(value,hash,bytes))
}
struct Phase{budget:Arc<Budget>,done:bool}impl Drop for Phase{fn drop(&mut self){if !self.done{self.budget.keep_failed_scratch()}}}
impl QueryDb{
 /// Read-only actual graph child. The caller owns the typed current partial
 /// snapshot and its normal freshness proof; every cache delivery rechecks it.
 pub(crate) fn with_handlers_structural<R>(self:&Arc<Self>,capture:&Arc<crate::input_snapshot::HandlerPreparedCapture>,proof:&Arc<crate::request_runner::runner_freshness::HandlerPolicyAdmission>,consume:impl FnOnce(&StructuralData,&Arc<Budget>)->io::Result<R>)->Result<R,Failure>{
  crate::daemon::control::checkpoint()?;capture.require_bound()?;if !Arc::ptr_eq(capture,proof.capture())||!capture.uses_queries(self){return Err("handler result current capture/admission/query owner differs".into())}
  let _gate=self.raw_policy.gate.lock().unwrap_or_else(|e|e.into_inner());self.raw_prune_locked(Instant::now());self.raw_policy.admission.abort.begin();self.raw_policy.admission.denied.store(false,Ordering::Release);
  let source=self.raw_source_input_charge_locked()?;let input=self.workspace_input_base_headroom_locked(source)?;let available=input.min(RESULT_BUDGET.saturating_sub(self.raw_policy.charge.load(Ordering::Acquire)));let mut phase=Phase{budget:Budget::new(available).map_err(|m|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,m)))?,done:false};
  let pending=self.with_handlers_structural_budget_locked(capture,proof,&phase.budget,consume);if pending.is_ok(){phase.done=true;}pending
 }
 /// Seal only the existing authenticated Kind12 result. No ALLOW lookup,
 /// full-scope authority or partial archive handle crosses this boundary.
 pub(crate) fn stage_handler_structural_rows(
  self:&Arc<Self>,capture:&Arc<crate::input_snapshot::HandlerPreparedCapture>,
  proof:&Arc<crate::request_runner::runner_freshness::HandlerPolicyAdmission>,cache:&std::path::Path,
 )->Result<handler_structural_staging::StagedRows,Failure>{
  if !proof.is_structural_staging()||capture.has_staged_rows(){return Err("handler stage requires its actual live partial owner and staging-only admission".into())}
  let revision=capture.prepared().frontend().map(|_|capture.structural_inputs().map(|inputs|inputs.source_revision())).transpose()?;
  self.with_handlers_structural(capture,proof,|data,_|
   handler_structural_staging::StagedRows::write(cache,self.native_query_owner_identity(),capture.issuance(),revision,data)
  )
 }
 /// Internal sibling of the full reader: caller already holds the raw-family
 /// gate and lends its SAME unscoped endpoint Budget. No nested operation
 /// counter, extra headroom domain, or relock is created for this child.
 pub(super) fn with_handlers_structural_budget_locked<R>(self:&Arc<Self>,capture:&Arc<crate::input_snapshot::HandlerPreparedCapture>,proof:&Arc<crate::request_runner::runner_freshness::HandlerPolicyAdmission>,b:&Arc<Budget>,consume:impl FnOnce(&StructuralData,&Arc<Budget>)->io::Result<R>)->Result<R,Failure>{
  checkpoint(b)?;capture.require_bound()?;if capture.has_staged_rows(){return Err("detached handler rows cannot answer live Kind12".into())}if !Arc::ptr_eq(capture,proof.capture())||!capture.uses_queries(self){return Err("handler result current capture/admission/query owner differs".into())}
  let key=super::reactive_read_policy::metadata_key(&("original-handlers-partial-structural-v1",capture.issuance()))?;reserve(b,Some(std::mem::size_of::<Params>()+2*std::mem::size_of::<usize>()+128))?;self.raw_policy.admission.admit_handlers(Arc::downgrade(capture),key,std::mem::size_of::<Params>()+128).map_err(super::reactive_read_policy::graph_failure)?;
  let guard=self.raw_policy.admission.bind_handlers_operation(b,capture,proof,self)?;let value=self.db.get::<Result<StructuralData,String>>(key,Arc::new(Params{key,issuance:capture.issuance()})).map_err(super::reactive_read_policy::graph_failure)?;capture.require_bound()?;
  let data=match value.as_ref(){Ok(data)=>data,Err(message)=>{reserve(b,message.len().checked_add(64))?;let mut copy=String::new();copy.try_reserve_exact(message.len()).map_err(|_|Failure::Operational(io::ErrorKind::OutOfMemory.into()))?;copy.push_str(message);return Err(Failure::Unsupported(copy))}};if data.issuance!=capture.issuance(){return Err("handler result cached current owner differs".into())}checkpoint(b)?;let answer=consume(data,b)?;checkpoint(b)?;drop(guard);Ok(answer)
 }
}

#[cfg(test)]mod actual_owner_refusal_controls{
 use super::*;
 #[test]fn actual_handler_kind12_payload_without_partial_operation_refuses_before_dependency_read(){let queries=QueryDb::default();let key=super::super::reactive_read_policy::metadata_key(&("original-handlers-partial-structural-v1",77u64)).unwrap();let params=Params{key,issuance:77};let error=match queries.db.get::<Result<StructuralData,String>>(key,Arc::new(params)){Err(error)=>error,Ok(_)=>panic!("caller scalar metadata cannot issue a current partial source")};let QueryError::Operational{key:actual,error}=error else{panic!("actual Kind12 must dispatch to typed partial owner gate")};assert_eq!(actual,key);let error=error.into_io();assert_eq!(error.kind(),io::ErrorKind::InvalidInput);assert!(error.to_string().contains("handler child has no current sealed partial operation"));assert!(queries.db.retained_value::<Result<StructuralData,String>>(key).is_none());assert!(queries.raw_policy.admission.current_handlers_operation(77).is_err());}
 #[test]fn partial_answer_weak_resource_control_never_grants_source_and_lives_until_real_ttl_prune(){let queries=QueryDb::default();let key=super::super::reactive_read_policy::metadata_key(&("handler-empty-weak-resource-control",9u64)).unwrap();queries.raw_policy.admission.admit_handlers(Weak::new(),key,128).unwrap();assert!(!queries.raw_policy.admission.leases.lock().unwrap().get(&key).unwrap().owner.expires_without_owner());assert!(queries.raw_policy.admission.current_handlers_operation(9).is_err());queries.raw_prune_locked(Instant::now()+MAX_AGE+Duration::from_secs(1));assert!(!queries.raw_policy.admission.leases.lock().unwrap().contains_key(&key));}
}

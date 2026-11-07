//! Buffered borrowed report encoding under the SAME effect-family ledger.
use super::*;use std::io::{self,Write};use dm_analysis::checker_effects::EffectReportPhase;
struct Count{bytes:usize,limit:usize}impl Write for Count{fn write(&mut self,bytes:&[u8])->io::Result<usize>{crate::daemon::control::checkpoint()?;self.bytes=self.bytes.checked_add(bytes.len()).filter(|bytes|*bytes<=self.limit).ok_or_else(||io::Error::new(io::ErrorKind::OutOfMemory,"effect report wire byte allowance exhausted"))?;Ok(bytes.len())}fn flush(&mut self)->io::Result<()>{crate::daemon::control::checkpoint()}}
struct Fixed<'a>{bytes:&'a mut Vec<u8>,length:usize}impl Write for Fixed<'_>{fn write(&mut self,bytes:&[u8])->io::Result<usize>{crate::daemon::control::checkpoint()?;let next=self.bytes.len().checked_add(bytes.len()).filter(|n|*n<=self.length&&*n<=self.bytes.capacity()).ok_or_else(||io::Error::new(io::ErrorKind::InvalidData,"effect report serialization changed after admission"))?;self.bytes.extend_from_slice(bytes);debug_assert_eq!(self.bytes.len(),next);Ok(bytes.len())}fn flush(&mut self)->io::Result<()>{crate::daemon::control::checkpoint()}}
// Own the allocated bytes and their one physical-parent charge together.
struct FixedCheckerWireBytes {
    // Fields drop in this order, including on unwind.
    bytes: Vec<u8>,
    _parent: CheckerWireCharge,
}

struct CheckerWireCharge {
    parent: Arc<dm_syntax::SharedNativeReservation>,
    capacity: usize,
}

impl Drop for CheckerWireCharge {
    fn drop(&mut self) {
        self.parent.release(self.capacity);
    }
}

impl FixedCheckerWireBytes {
    fn allocate(
        parent: &Arc<dm_syntax::SharedNativeReservation>,
        requested: usize,
        capacity_error: &'static str,
    ) -> io::Result<Self> {
        let bound = requested.checked_mul(4)
            .ok_or_else(|| io::Error::new(io::ErrorKind::OutOfMemory, capacity_error))?;
        let provisional = parent.provisional(bound)
            .map_err(|message| io::Error::new(io::ErrorKind::OutOfMemory, message))?;
        // On error, the bytes drop before the provisional grant.
        let mut bytes = Vec::new();
        bytes.try_reserve_exact(requested)
            .map_err(|actual| io::Error::new(io::ErrorKind::OutOfMemory, actual))?;
        let capacity = bytes.capacity();
        if capacity > bound {
            return Err(io::Error::new(io::ErrorKind::OutOfMemory, capacity_error));
        }
        let parent_owner = Arc::clone(parent);
        provisional.commit();
        parent.release(bound - capacity);
        Ok(Self { bytes, _parent: CheckerWireCharge { parent: parent_owner, capacity } })
    }

    fn writer(&mut self, length: usize) -> Fixed<'_> {
        Fixed { bytes: &mut self.bytes, length }
    }

    fn write_to(&self, output: &mut impl Write) -> io::Result<()> {
        output.write_all(&self.bytes)
    }
}

impl QueryDb{
 pub(crate) fn write_effect_report_buffer(&self,input:&Arc<EffectInput>,scope:&crate::runner_host::query_snapshot::PurityScope<'_>,width:usize,pure:&global_report::NativeEffectReport,sleep:&global_report::NativeEffectReport,encode:impl Fn(&mut dyn Write)->io::Result<()>,output:&mut impl Write)->io::Result<()>{
  crate::daemon::control::checkpoint()?;scope.validate(self,input).map_err(io::Error::other)?;self.prune_purity();let _gate=self.purity.gate.lock().unwrap_or_else(|e|e.into_inner());scope.validate(self,input).map_err(io::Error::other)?;pure.validate(input,EffectReportPhase::Purity,width,0,input.archive().callables().source_order().len(),input.archive().callables().source_order().len(),scope.policy_key()).map_err(io::Error::other)?;sleep.validate(input,EffectReportPhase::Sleep,width,0,input.archive().callables().source_order().len(),input.archive().callables().source_order().len(),scope.policy_key()).map_err(io::Error::other)?;let sources=self.purity_sources_using::<ReadFailure>(input,|keys|checked_sources_using::<ReadFailure>(input,keys,&self.sources,||crate::daemon::control::checkpoint().map_err(|actual|ReadFailure::Query(QueryError::operational(global_report::report_key(input,width,EffectReportPhase::Purity,scope.policy_key(),0,input.archive().callables().source_order().len()),actual)))),|actual|ReadFailure::Query(QueryError::operational(global_report::report_key(input,width,EffectReportPhase::Purity,scope.policy_key(),0,input.archive().callables().source_order().len()),io::Error::new(io::ErrorKind::OutOfMemory,actual)))).map_err(|error|match error{ReadFailure::Query(actual)=>pages::restore_graph_error(&self.purity.ledger,actual),ReadFailure::Semantic(message)=>io::Error::other(message)})?;
  let headroom=pages::page_execution_admission(&self.purity.ledger).map_err(|message|io::Error::new(io::ErrorKind::OutOfMemory,message))?;let mut counter=Count{bytes:0,limit:headroom.available()};encode(&mut counter)?;let bound=counter.bytes.checked_mul(4).and_then(|n|n.checked_add(std::mem::size_of::<Vec<u8>>()+64)).ok_or_else(||io::Error::new(io::ErrorKind::OutOfMemory,"effect report wire capacity overflow"))?;let key=global_report::report_key(input,width,EffectReportPhase::Purity,scope.policy_key(),0,input.archive().callables().source_order().len());headroom.reserve_external(bound)?;let mut work=graph_work::GraphWork::new(self.purity.ledger.clone(),key);work.reserve(bound)?;let mut bytes=self.fixed_checker_wire_bytes(counter.bytes,"effect report wire exposed excess capacity")?;encode(&mut bytes.writer(counter.bytes))?;if bytes.bytes.len()!=counter.bytes{return Err(io::Error::new(io::ErrorKind::InvalidData,"effect report serialization length changed after admission"))}
  crate::daemon::control::checkpoint()?;scope.validate(self,input).map_err(io::Error::other)?;checked_sources_using::<ReadFailure>(input,&sources,&self.sources,||crate::daemon::control::checkpoint().map_err(|actual|ReadFailure::Query(QueryError::operational(key,actual)))).map_err(|error|match error{ReadFailure::Query(actual)=>pages::restore_graph_error(&self.purity.ledger,actual),ReadFailure::Semantic(message)=>io::Error::other(message)})?;pure.validate(input,EffectReportPhase::Purity,width,0,input.archive().callables().source_order().len(),input.archive().callables().source_order().len(),scope.policy_key()).map_err(io::Error::other)?;sleep.validate(input,EffectReportPhase::Sleep,width,0,input.archive().callables().source_order().len(),input.archive().callables().source_order().len(),scope.policy_key()).map_err(io::Error::other)?;let result=bytes.write_to(output);drop(bytes);drop(work);result
 }
}

/// Loan valid only while the actual full writer holds the SAME ledger gate.
/// No source tuple, cache answer, or completion flag can construct this type.
pub(crate) struct ExhaustiveReports<'a,'scope>{db:&'a QueryDb,input:&'a Arc<EffectInput>,scope:&'a crate::runner_host::query_snapshot::PurityScope<'scope>,width:usize,window:usize}
impl ExhaustiveReports<'_,'_>{
 pub(crate) fn for_each_diagnostic(&self,mut consume:impl FnMut(&'static str,&Produced)->io::Result<()>)->io::Result<()>{
  let total=self.input.archive().callables().source_order().len();
  for(phase,label,immediate)in[(EffectReportPhase::Purity,"body_immediate",true),(EffectReportPhase::Sleep,"must_not_sleep",false),(EffectReportPhase::Purity,"must_be_pure",false)]{
   #[cfg(test)]self.db.trace_effect_phase_for_test(label,0,total);
   let mut start=0;while start<total{crate::daemon::control::checkpoint()?;let count=self.window.min(total-start);let rows=self.db.native_effect_source_report_window_locked(self.input,self.scope,self.width,phase,start,count,true)?;
    for row in rows.iter(){crate::daemon::control::checkpoint()?;if row.phase()==if phase==EffectReportPhase::Sleep{dm_analysis::checker_effects::ProducedPhase::SleepGraph}else if immediate{dm_analysis::checker_effects::ProducedPhase::BodyImmediate}else{dm_analysis::checker_effects::ProducedPhase::PurityGraph}{consume(label,row)?;}}
    // The exact cached Outcome was evicted before this loan. Its physical
    // messages/notes free here before the next bounded target window begins.
    drop(rows);start=start.checked_add(count).ok_or_else(||io::Error::new(io::ErrorKind::OutOfMemory,"effect target progress overflow"))?;
    #[cfg(test)]self.db.trace_effect_phase_for_test(label,start,total);
   }
   if start!=total{return Err(io::Error::new(io::ErrorKind::InvalidData,"effect target traversal incomplete"))}
  }
  crate::daemon::control::checkpoint()?;self.scope.validate(self.db,self.input).map_err(io::Error::other)
 }
}
impl QueryDb{
 pub(crate) fn write_exhausted_effect_report_buffer(&self,input:&Arc<EffectInput>,scope:&crate::runner_host::query_snapshot::PurityScope<'_>,width:usize,window:usize,encode:impl Fn(&mut dyn Write,&ExhaustiveReports<'_,'_>)->io::Result<()>,output:&mut impl Write)->io::Result<()>{
  crate::daemon::control::checkpoint()?;scope.validate(self,input).map_err(io::Error::other)?;if !input.is_source_page_context()||width==0||width>dm_analysis::checker_effects::MAX_EVENTS||window==0||window>dm_analysis::checker_effects::MAX_EVENTS{return Err(io::Error::new(io::ErrorKind::InvalidInput,"effect full writer requires bounded original source windows"))}
  self.prune_purity();let _gate=self.purity.gate.lock().unwrap_or_else(|e|e.into_inner());scope.validate(self,input).map_err(io::Error::other)?;{let mut ledger=self.purity.ledger.lock().unwrap_or_else(|e|e.into_inner());ledger.denied=false;ledger.aborted=None;}
  let key=global_report::report_key(input,width,EffectReportPhase::Purity,scope.policy_key(),0,0);let sources=self.purity_sources_using::<ReadFailure>(input,|keys|checked_sources_using::<ReadFailure>(input,keys,&self.sources,||crate::daemon::control::checkpoint().map_err(|actual|ReadFailure::Query(QueryError::operational(key,actual)))),|actual|ReadFailure::Query(QueryError::operational(key,io::Error::new(io::ErrorKind::OutOfMemory,actual)))).map_err(|error|match error{ReadFailure::Query(actual)=>pages::restore_graph_error(&self.purity.ledger,actual),ReadFailure::Semantic(message)=>io::Error::other(message)})?;
  let operation=ExhaustiveReports{db:self,input,scope,width,window};let mut count=Count{bytes:0,limit:BUDGET};
  #[cfg(test)]self.trace_effect_phase_for_test("count-begin",0,0);
  encode(&mut count,&operation)?;
  #[cfg(test)]self.trace_effect_phase_for_test("count-end",count.bytes,count.bytes);
  // Counting retained no output buffers. Recompute actual available family
  // headroom after all scalar graph/summary/dependency metadata is admitted.
  let headroom=pages::page_execution_admission(&self.purity.ledger).map_err(|message|io::Error::new(io::ErrorKind::OutOfMemory,message))?;let bound=count.bytes.checked_mul(4).and_then(|n|n.checked_add(std::mem::size_of::<Vec<u8>>()+64)).ok_or_else(||io::Error::new(io::ErrorKind::OutOfMemory,"full effect wire capacity overflow"))?;#[cfg(test)]self.trace_effect_wire_capacity_for_test("wire-precharge",bound,0);
  headroom.reserve_external(bound)?;let mut work=graph_work::GraphWork::new(self.purity.ledger.clone(),key);let marker=dm_analysis::checker_effects::EffectReportWork::mark(&mut work)?;work.reserve(bound)?;
  let mut bytes=self.fixed_checker_wire_bytes(count.bytes,"full effect wire allocator exceeds preadmission")?;
  #[cfg(test)]self.trace_effect_wire_capacity_for_test("wire-allocated",bound,bytes.bytes.capacity());
  settle_fixed_wire_capacity(&mut work,marker,bytes.bytes.capacity())?;
  #[cfg(test)]self.trace_effect_wire_capacity_for_test("wire-settled",bound,bytes.bytes.capacity());#[cfg(test)]self.trace_effect_phase_for_test("encode-begin",0,count.bytes);
  encode(&mut bytes.writer(count.bytes),&operation)?;
  #[cfg(test)]self.trace_effect_phase_for_test("encode-end",bytes.bytes.len(),count.bytes);if bytes.bytes.len()!=count.bytes{return Err(io::Error::new(io::ErrorKind::InvalidData,"exhausted effect wire differs from counted immutable source"))}
  crate::daemon::control::checkpoint()?;scope.validate(self,input).map_err(io::Error::other)?;checked_sources_using::<ReadFailure>(input,&sources,&self.sources,||crate::daemon::control::checkpoint().map_err(|actual|ReadFailure::Query(QueryError::operational(key,actual)))).map_err(|error|match error{ReadFailure::Query(actual)=>pages::restore_graph_error(&self.purity.ledger,actual),ReadFailure::Semantic(message)=>io::Error::other(message)})?;if self.purity.ledger.lock().unwrap_or_else(|e|e.into_inner()).denied{return Err(io::Error::new(io::ErrorKind::OutOfMemory,"full effect wire family admission exhausted"))}
  let result=bytes.write_to(output);drop(bytes);drop(work);result
 }
}

/// Fixed issued-input owner credit in the SAME family ledger. The writer-only
/// snapshot owner frees its input before this noncloneable lease is released.
pub(crate) struct EffectRequestInputLease{ledger:Arc<Mutex<Ledger>>,bytes:usize}
impl Drop for EffectRequestInputLease{fn drop(&mut self){let mut ledger=self.ledger.lock().unwrap_or_else(|e|e.into_inner());ledger.fixed_request_inputs=ledger.fixed_request_inputs.checked_sub(self.bytes).expect("same retained effect input reservation");}}
impl QueryDb{pub(crate) fn reserve_effect_request_input(&self,bytes:usize)->io::Result<EffectRequestInputLease>{crate::daemon::control::checkpoint()?;self.prune_purity();let _gate=self.purity.gate.lock().unwrap_or_else(|e|e.into_inner());let admission=pages::page_execution_admission(&self.purity.ledger).map_err(|message|io::Error::new(io::ErrorKind::OutOfMemory,message))?;admission.reserve_external(bytes)?;let mut ledger=self.purity.ledger.lock().unwrap_or_else(|e|e.into_inner());ledger.admit(bytes).map_err(|message|io::Error::new(io::ErrorKind::OutOfMemory,message))?;ledger.fixed_request_inputs=ledger.fixed_request_inputs.checked_add(bytes).ok_or_else(||io::Error::new(io::ErrorKind::OutOfMemory,"retained effect input credit overflow"))?;Ok(EffectRequestInputLease{ledger:self.purity.ledger.clone(),bytes})}}
#[cfg(test)]impl QueryDb{pub(crate) fn effect_request_input_charge_for_test(&self)->usize{self.purity.ledger.lock().unwrap_or_else(|e|e.into_inner()).fixed_request_inputs}}

/// The fragment is physical output scratch, held across the final encoder and
/// dropped before its SAME-family work credit. No output cache or raw Arc loan.
pub(crate) struct EffectByteBuffer{bytes:FixedCheckerWireBytes,limit:usize,_work:graph_work::GraphWork}
impl crate::daemon::query::encoded_bytes::Buffer for EffectByteBuffer{fn append(&mut self,bytes:&[u8])->io::Result<()>{let value=&mut self.bytes.bytes;if value.len().checked_add(bytes.len()).is_none_or(|n|n>self.limit||n>value.capacity()){return Err(io::Error::new(io::ErrorKind::OutOfMemory,"byte fragment fixed buffer exhausted"))}value.extend_from_slice(bytes);Ok(())}fn bytes(&self)->&[u8]{&self.bytes.bytes}}
impl QueryDb{
 fn fixed_checker_wire_bytes(&self,requested:usize,capacity_error:&'static str)->io::Result<FixedCheckerWireBytes>{
  let parent=self.body_charge.shared_reservation().expect("production syntax parent");
  FixedCheckerWireBytes::allocate(parent,requested,capacity_error)
 }
 pub(crate) fn effect_byte_buffer(&self,input:&Arc<EffectInput>,scope:&crate::runner_host::query_snapshot::PurityScope<'_>,width:usize,limit:usize)->io::Result<EffectByteBuffer>{crate::daemon::control::checkpoint()?;scope.validate(self,input).map_err(io::Error::other)?;if limit==0||limit>crate::daemon::query::encoded_bytes::MAX_FRAGMENT{return Err(io::Error::new(io::ErrorKind::InvalidInput,"byte fragment limit"))}let _gate=self.purity.gate.lock().unwrap_or_else(|e|e.into_inner());let bound=limit.checked_mul(4).and_then(|n|n.checked_add(std::mem::size_of::<Vec<u8>>()+64)).ok_or_else(||io::Error::new(io::ErrorKind::OutOfMemory,"fragment capacity overflow"))?;let headroom=pages::page_execution_admission(&self.purity.ledger).map_err(|message|io::Error::new(io::ErrorKind::OutOfMemory,message))?;headroom.reserve_external(bound)?;let key=global_report::report_key(input,width,EffectReportPhase::Purity,scope.policy_key(),0,0);let mut work=graph_work::GraphWork::new(self.purity.ledger.clone(),key);work.reserve(bound)?;let bytes=self.fixed_checker_wire_bytes(limit,"fragment allocator exceeds reservation")?;Ok(EffectByteBuffer{bytes,limit,_work:work})}}

/// The4x envelope covers allocator exposure BEFORE allocation. Once the actual
/// capacity is known and the original upper-bound check passed, Fixed forbids
/// further growth. Keep every physical byte funded; retire only unused escrow.
fn settle_fixed_wire_capacity(work:&mut graph_work::GraphWork,marker:graph_work::ReportScopeMark,capacity:usize)->io::Result<()>{let retained=capacity.checked_add(std::mem::size_of::<Vec<u8>>()+64).ok_or_else(||io::Error::new(io::ErrorKind::OutOfMemory,"full wire retained capacity overflow"))?;dm_analysis::checker_effects::EffectReportWork::reconcile(work,marker,retained)}
#[cfg(test)]impl QueryDb{fn trace_effect_wire_capacity_for_test(&self,label:&str,pending:usize,capacity:usize){if !self.effect_pressure_trace_enabled_for_test(){return}let mut l=self.purity.ledger.lock().unwrap_or_else(|e|e.into_inner());let live=l.live_bytes();let metadata=l.metadata();eprintln!("effect-10001 phase={label} live={live} metadata={metadata} active_work={} pending_envelope={pending} actual_capacity={capacity} available={} limit={BUDGET}",l.active_graph_work,BUDGET.saturating_sub(live.saturating_add(metadata)));}}
#[cfg(test)]mod fixed_wire_capacity_tests{use super::*;use dm_analysis::checker_effects::EffectReportWork;
 fn allocation(ledger:&Arc<Mutex<Ledger>>)->(graph_work::GraphWork,graph_work::ReportScopeMark,Vec<u8>,usize){let mut work=graph_work::GraphWork::new(ledger.clone(),Key::new(global_report::PURE,809));let marker=work.mark().unwrap();let requested=1024*1024;let bound=requested*4+std::mem::size_of::<Vec<u8>>()+64;work.reserve(bound).unwrap();let mut bytes=Vec::new();bytes.try_reserve_exact(requested).unwrap();assert!(bytes.capacity()<=requested*4);(work,marker,bytes,bound)}
 #[test]fn fixed_wire_settles_unused_envelope_and_keeps_every_exposed_byte_funded_until_drop(){let ledger=Arc::new(Mutex::new(Ledger::default()));let(mut work,marker,mut bytes,bound)=allocation(&ledger);assert_eq!(ledger.lock().unwrap().active_graph_work,bound);let retained=bytes.capacity()+std::mem::size_of::<Vec<u8>>()+64;settle_fixed_wire_capacity(&mut work,marker,bytes.capacity()).unwrap();assert_eq!(ledger.lock().unwrap().active_graph_work,retained);let length=bytes.capacity();Fixed{bytes:&mut bytes,length}.write_all(b"funded final encoded output").unwrap();assert_eq!(ledger.lock().unwrap().active_graph_work,retained);drop(bytes);drop(work);assert_eq!(ledger.lock().unwrap().active_graph_work,0);}
 #[test]fn fixed_wire_cancel_before_settlement_keeps_full_escrow_and_error_unwind_free_bytes_before_credit(){let ledger=Arc::new(Mutex::new(Ledger::default()));let(mut work,marker,bytes,bound)=allocation(&ledger);let token=crate::daemon::control::Cancellation::default();let guard=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));token.cancel();assert_eq!(settle_fixed_wire_capacity(&mut work,marker,bytes.capacity()).unwrap_err().kind(),io::ErrorKind::Interrupted);assert_eq!(ledger.lock().unwrap().active_graph_work,bound);drop(guard);drop(bytes);drop(work);assert_eq!(ledger.lock().unwrap().active_graph_work,0);struct Physical{bytes:Vec<u8>,ledger:Arc<Mutex<Ledger>>}impl Drop for Physical{fn drop(&mut self){assert!(self.ledger.lock().unwrap().active_graph_work>=self.bytes.capacity()+std::mem::size_of::<Vec<u8>>());}}let caught=std::panic::catch_unwind(std::panic::AssertUnwindSafe(||{let(mut work,marker,bytes,_)=allocation(&ledger);settle_fixed_wire_capacity(&mut work,marker,bytes.capacity()).unwrap();let _physical=Physical{bytes,ledger:ledger.clone()};panic!("actual settled-wire unwind");}));assert!(caught.is_err());assert_eq!(ledger.lock().unwrap().active_graph_work,0);}
}

#[cfg(test)]
mod checker_wire_parent_tests {
    use super::*;

    #[test]
    fn checker_wire_parent_settles_capacity_and_keeps_bytes_funded_through_sink_failure() {
        struct Sink<'a> {
            parent: &'a dm_syntax::SharedNativeReservation,
            expected: usize,
        }
        impl Write for Sink<'_> {
            fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
                assert_eq!(bytes, b"exact bytes");
                assert_eq!(self.parent.reserved_bytes(), self.expected);
                Err(io::Error::from_raw_os_error(1450))
            }
            fn flush(&mut self) -> io::Result<()> { Ok(()) }
        }

        let db = QueryDb::default();
        let parent = db.body_charge.shared_reservation().unwrap();
        let baseline = parent.reserved_bytes();
        let mut bytes = db.fixed_checker_wire_bytes(11, "test capacity").unwrap();
        let funded = baseline + bytes.bytes.capacity();
        assert_eq!(parent.reserved_bytes(), funded);
        bytes.writer(11).write_all(b"exact bytes").unwrap();
        assert_eq!(bytes.writer(11).write(b"!").unwrap_err().kind(), io::ErrorKind::InvalidData);
        assert_eq!(parent.reserved_bytes(), funded);
        assert_eq!(bytes.write_to(&mut Sink { parent, expected: funded }).unwrap_err().raw_os_error(), Some(1450));
        drop(bytes);
        assert_eq!(parent.reserved_bytes(), baseline);
        let empty = db.fixed_checker_wire_bytes(0, "test capacity").unwrap();
        assert_eq!(empty.bytes.capacity(), 0);
        assert_eq!(parent.reserved_bytes(), baseline);
    }

    #[test]
    fn checker_wire_parent_competes_with_real_syntax_lease_and_retry_recovers() {
        let limit = 8192;
        let parent = dm_syntax::SharedNativeReservation::try_new(limit).unwrap();
        let syntax = dm_syntax::SettingChargeCounter::try_new_with_parent(limit, Some(parent.clone())).unwrap();
        let baseline = parent.reserved_bytes();
        let admission = dm_syntax::SettingAdmission::new(&syntax, limit, &|| Ok(()));
        let held = admission.reserve(limit - baseline - 4095).unwrap();
        let occupied = parent.reserved_bytes();
        let refused = FixedCheckerWireBytes::allocate(&parent, 1024, "test capacity");
        assert_eq!(refused.err().unwrap().kind(), io::ErrorKind::OutOfMemory);
        assert_eq!(parent.reserved_bytes(), occupied);
        drop(held);
        assert_eq!(parent.reserved_bytes(), baseline);
        let retry = FixedCheckerWireBytes::allocate(&parent, 1024, "test capacity").unwrap();
        assert_eq!(parent.reserved_bytes(), baseline + retry.bytes.capacity());
        drop(retry);
        assert_eq!(parent.reserved_bytes(), baseline);
    }
}

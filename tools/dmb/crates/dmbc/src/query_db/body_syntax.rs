//! Body syntax lives in the SAME graph as compilation inputs, not a sibling
//! analysis cache. Revision-scoped keys are deliberately conservative: no
//! cross-revision reuse of ASTs containing absolute expanded-source positions.
use super::*;
use dm_tree::frontend::{
    BodySyntax, BodySyntaxFailure, BodySyntaxInput, BodySyntaxQueries, Diagnostic, DiagnosticKind,
    DiagnosticStage,
};
use std::sync::{
    atomic::{AtomicUsize, Ordering},
    Weak,
};

pub(super) const BODY_SYNTAX: Kind = Kind(4);
pub(super) const BUDGET: usize = 128 * 1024 * 1024;

#[derive(Debug)]
struct Params {
    input: Weak<BodySyntaxInput>,
    key: Key,
}

pub(super) fn register(db: &Db, charged: Arc<AtomicUsize>) {
    db.define(BODY_SYNTAX, "native-body-syntax", move |_, params| {
        let params = params
            .downcast_ref::<Params>()
            .expect("body query parameter type");
        let input = params
            .input
            .upgrade()
            .ok_or(QueryError::Missing(params.key))?;
        #[cfg(test)]
        body_failure_test_checkpoint(params.key)?;
        // Existing Kind4 owns the in-scope permit. Setting leaves never call
        // host.syntax/Db.get or reacquire/reset any family admission here.
        let parsed = setting_syntax::with_setting_admission(&charged, |admission| {
            input.parse_with_setting_admission(admission)
        });
        let result = match parsed {
            Ok(syntax) => Ok(Arc::new(syntax)),
            Err(BodySyntaxFailure::Syntax(error)) => Err(error),
            Err(BodySyntaxFailure::Operational(error)) => {
                return Err(QueryError::operational(params.key, error))
            }
        };
        let bytes = result
            .as_ref()
            .map_or(1024, |syntax| syntax.budget_charge());
        // Identity is valid only within this private parser issuance. A fresh
        // issuance has a different key even if all its bytes happen to match.
        charged.fetch_add(bytes, Ordering::Relaxed);
        Ok(Outcome::new(result, params.key.id, bytes))
    });
}

impl std::fmt::Debug for QueryDb {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("QueryDb")
            .field("id", &self.id)
            .finish_non_exhaustive()
    }
}
impl BodySyntaxQueries for QueryDb {
    fn begin_revision(&self) {
        self.prune_value_proofs();
        self.prune_purity();
        self.prune_raw_policy();
        let mut inputs = self.body_inputs.lock().unwrap_or_else(|e| e.into_inner());
        inputs.retain(|key, input| {
            if input.strong_count() > 0 {
                true
            } else {
                let freed = self.db.value_bytes_at(*key);
                self.db.remove(*key);
                let _ =
                    self.body_charge
                        .fetch_update(Ordering::Relaxed, Ordering::Relaxed, |charge| {
                            Some(charge.saturating_sub(freed))
                        });
                false
            }
        });
    }
    fn prepare_checked_input(&self,input:&Arc<BodySyntaxInput>)->Result<(),BodySyntaxFailure>{self.prepare_body_input(input).map_err(checked_query_failure)}
    fn syntax(&self, input: &Arc<BodySyntaxInput>) -> Result<Arc<BodySyntax>, Diagnostic> {
        self.body_syntax_result(input)
            .map_err(body_query_diagnostic)?
    }
    fn syntax_checked(
        &self,
        input: &Arc<BodySyntaxInput>,
    ) -> Result<Arc<BodySyntax>, BodySyntaxFailure> {
        self.body_syntax_result(input)
            .map_err(checked_query_failure)?
            .map_err(BodySyntaxFailure::Syntax)
    }
}

// Standalone compatibility and checked native consumers share the SAME query,
// input owner, budget/eviction policy and cached syntax value. Only transport
// differs; an operational QueryError never becomes a syntax Diagnostic in the
// checked path and is never an Outcome.
// Infrastructure failure is not parser meaning. Retain the actual graph
// exception as the IO cause instead of caching an invented syntax Diagnostic.
#[derive(Debug)]
struct BodyQueryGraphFailure(QueryError);
impl std::fmt::Display for BodyQueryGraphFailure {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "native body query failed: {:?}", self.0)
    }
}
impl std::error::Error for BodyQueryGraphFailure {}
fn body_query_diagnostic(error: QueryError) -> Diagnostic {
    Diagnostic {
        kind: DiagnosticKind::Internal,
        stage: DiagnosticStage::Internal,
        location: None,
        message: format!("native body query failed: {error:?}"),
    }
}
impl QueryDb {
    fn prepare_body_input(&self,input:&Arc<BodySyntaxInput>)->Result<(),QueryError>{
        let key=Key::new(BODY_SYNTAX,input.key().into());
        #[cfg(test)]self.record_pressure_trace_for_test(0,0);
        crate::daemon::control::checkpoint().map_err(|actual|QueryError::operational(key,actual))?;
        let mut inputs=self.body_inputs.lock().unwrap_or_else(|e|e.into_inner());
        inputs.entry(key).or_insert_with(||Arc::downgrade(input));
        // Both actual retained setting/literal leases and the existing SOFT
        // syntax estimate share body_charge. Waiting for used>BUDGET is too
        // late: the next real parse needs its cleanup/parser work first.
        // This is a cache-pressure estimate, never a syntax/refusal threshold.
        // 8x the existing64x source estimate covers the existing512x cleanup
        // envelope, plus the host's unchanged complete parser stack allowance.
        if self.body_charge.load(Ordering::Acquire)>BUDGET{
            // Preserve the original over-budget soft-cache fallback. The new
            // pressure path below normally retires consumed values earlier.
            let freed=self.db.evict_values(&[BODY_SYNTAX]);
            let _=self.body_charge.fetch_update(Ordering::AcqRel,Ordering::Acquire,|charge|Some(charge.saturating_sub(freed)));
        }
        let headroom=input.budget_charge().saturating_mul(8).saturating_add(dm_exec::COMPILER_STACK_BYTES/16);
        if self.body_charge.load(Ordering::Acquire).saturating_add(headroom)<=BUDGET{return Ok(())}
        let mut cursor=self.body_eviction_cursor.lock().unwrap_or_else(|e|e.into_inner());
        let after=*cursor;
        use std::ops::Bound::{Excluded,Included,Unbounded};
        let tail=inputs.range((after.map_or(Unbounded,Excluded),Unbounded));
        let wrap=inputs.range((Unbounded,after.map_or(Unbounded,Included))).take(if after.is_some(){usize::MAX}else{0});
        for(&candidate,_)in tail.chain(wrap){
            #[cfg(test)]self.record_pressure_trace_for_test(1,0);
            crate::daemon::control::checkpoint().map_err(|actual|QueryError::operational(key,actual))?;
            if self.body_charge.load(Ordering::Acquire).saturating_add(headroom)<=BUDGET{break}
            *cursor=Some(candidate);
            // Keep this warm target and any actively loaned syntax. Only the
            // exact currently cached Result/BodySyntax owner may be retired.
            if candidate==key{continue}
            let Some(value)=self.db.retained_value::<Result<Arc<BodySyntax>,Diagnostic>>(candidate)else{continue};
            let consumed=Arc::strong_count(&value)==2&&value.as_ref().as_ref().map_or(true,|syntax|Arc::strong_count(syntax)==1);
            if !consumed{continue}
            let freed=self.db.evict_value_if_current(candidate,&value);
            // Free the actual body/retention guards before crediting its soft
            // estimate. Escaped children keep their own real leases alive.
            drop(value);
            #[cfg(test)]if freed!=0{self.record_pressure_trace_for_test(2,freed);}
            if freed!=0{let _=self.body_charge.fetch_update(Ordering::AcqRel,Ordering::Acquire,|charge|Some(charge.saturating_sub(freed)));}
        }
        // No retry after a real parser IO/refusal, and no cap change: after
        // retiring available cache owners the SAME actual admission decides.
        Ok(())
    }
    fn body_syntax_result(
        &self,
        input: &Arc<BodySyntaxInput>,
    ) -> Result<Result<Arc<BodySyntax>, Diagnostic>, QueryError> {
        self.prepare_body_input(input)?;
        let key = Key::new(BODY_SYNTAX, input.key().into());
        let result = self.db.get::<Result<Arc<BodySyntax>, Diagnostic>>(
            key,
            Arc::new(Params {
                input: Arc::downgrade(input),
                key,
            }),
        )?;
        Ok(result.as_ref().clone())
    }
}

fn checked_query_failure(error:QueryError)->BodySyntaxFailure{
 match error.into_operational(){Ok(actual)=>BodySyntaxFailure::Operational(actual.into_io()),Err(error)=>BodySyntaxFailure::Operational(std::io::Error::other(BodyQueryGraphFailure(error)))}
}
/// Record a REAL dynamic body dependency and retain its SAME returned owner.
/// Callers lend this value to BodyArchive::parse_checked_using; no second get.
pub(super) fn obtain(
 ctx:&mut dm_query::Ctx<'_>,input:&Arc<BodySyntaxInput>,
)->Result<Arc<BodySyntax>,BodySyntaxFailure>{
 let key=Key::new(BODY_SYNTAX,input.key().into());
 let result=ctx.get::<Result<Arc<BodySyntax>,Diagnostic>>(key,Arc::new(Params{input:Arc::downgrade(input),key})).map_err(checked_query_failure)?;
 result.as_ref().clone().map_err(BodySyntaxFailure::Syntax)
}

/// Record a real syntax dependency of a derived policy query. The archive's
/// later parse request borrows this exact cached value through its host.
pub(super) fn observe(
    ctx: &mut dm_query::Ctx<'_>,
    input: &Arc<BodySyntaxInput>,
) -> Result<(), QueryError> {
    let key = Key::new(BODY_SYNTAX, input.key().into());
    ctx.get::<Result<Arc<BodySyntax>, Diagnostic>>(
        key,
        Arc::new(Params {
            input: Arc::downgrade(input),
            key,
        }),
    )?;
    Ok(())
}

// Explicit per-thread test scheduling at the genuine Kind4 compute boundary.
// No settings admission or production error state is introduced here.
#[cfg(test)]
enum TestBodyFailure {
    Operational(std::io::Error),
    GraphMissing,
}
#[cfg(test)]
thread_local! {static BODY_FAILURE:std::cell::RefCell<Option<(usize,TestBodyFailure)>>=const{std::cell::RefCell::new(None)};}
#[cfg(test)]
pub(crate) struct BodyFailureSchedule;
#[cfg(test)]
impl Drop for BodyFailureSchedule {
    fn drop(&mut self) {
        BODY_FAILURE.with(|s| *s.borrow_mut() = None);
    }
}
#[cfg(test)]
fn body_failure_test_checkpoint(key: Key) -> Result<(), QueryError> {
    BODY_FAILURE.with(|s| {
        let mut scheduled = s.borrow_mut();
        if let Some((remaining, _)) = scheduled.as_mut() {
            if *remaining > 0 {
                *remaining -= 1;
                return Ok(());
            }
            let (_, error) = scheduled.take().expect("scheduled failure");
            return Err(match error {
                TestBodyFailure::Operational(error) => QueryError::operational(key, error),
                TestBodyFailure::GraphMissing => QueryError::Missing(key),
            });
        }
        Ok(())
    })
}
#[cfg(test)]
impl QueryDb {
    pub(crate) fn fail_body_syntax_after_for_test(
        &self,
        completed: usize,
        error: std::io::Error,
    ) -> BodyFailureSchedule {
        BODY_FAILURE.with(|s| {
            assert!(s.borrow().is_none());
            *s.borrow_mut() = Some((completed, TestBodyFailure::Operational(error)));
        });
        BodyFailureSchedule
    }
    pub(crate) fn fail_body_graph_once_for_test(&self) -> BodyFailureSchedule {
        BODY_FAILURE.with(|s| {
            assert!(s.borrow().is_none());
            *s.borrow_mut() = Some((0, TestBodyFailure::GraphMissing));
        });
        BodyFailureSchedule
    }
}

#[cfg(test)]
#[path="body_literal_tests.rs"]mod body_literal_tests;

#[cfg(test)]#[path="body_syntax_pressure_tests.rs"]mod pressure_tests;

// Bounded, opt-in diagnostics for the actual large source-report test only.
// Coordination is thread-local and cfg(test); no production owner/budget/cache.
#[cfg(test)]#[derive(Clone,Copy)]struct PressureTrace{started:std::time::Instant,prepares:usize,scanned:usize,retired:usize,soft_freed:usize}
#[cfg(test)]thread_local!{static PRESSURE_TRACE:std::cell::Cell<Option<PressureTrace>>=const{std::cell::Cell::new(None)};}
#[cfg(test)]pub(crate) struct PressureTraceGuard{_thread:std::marker::PhantomData<*mut()>}
#[cfg(test)]impl Drop for PressureTraceGuard{fn drop(&mut self){PRESSURE_TRACE.with(|slot|slot.set(None));}}
#[cfg(test)]impl QueryDb{
 pub(crate) fn trace_effect_pressure_for_test(&self)->PressureTraceGuard{PRESSURE_TRACE.with(|slot|{assert!(slot.get().is_none());slot.set(Some(PressureTrace{started:std::time::Instant::now(),prepares:0,scanned:0,retired:0,soft_freed:0}));});PressureTraceGuard{_thread:std::marker::PhantomData}}
 fn record_pressure_trace_for_test(&self,event:u8,bytes:usize){let log=PRESSURE_TRACE.with(|slot|{let Some(mut trace)=slot.get()else{return false};let log=match event{0=>{trace.prepares=trace.prepares.saturating_add(1);trace.prepares%1024==0},1=>{trace.scanned=trace.scanned.saturating_add(1);trace.scanned>=1024&&trace.scanned.is_power_of_two()},_=>{trace.retired=trace.retired.saturating_add(1);trace.soft_freed=trace.soft_freed.saturating_add(bytes);false}};slot.set(Some(trace));log});if log{self.trace_effect_phase_for_test("body-pressure-progress",0,0);}}
 pub(crate) fn effect_pressure_trace_enabled_for_test(&self)->bool{PRESSURE_TRACE.with(|slot|slot.get().is_some())}
 pub(crate) fn trace_effect_phase_for_test(&self,label:&str,at:usize,total:usize){let trace=PRESSURE_TRACE.with(|slot|slot.get());if let Some(trace)=trace{eprintln!("effect-10001 phase={label} progress={at}/{total} elapsed_ms={} prepares={} scanned={} retired={} soft_freed={} body_charge={} k4={} k23={} k24={} k25={} k26={} k27={}",trace.started.elapsed().as_millis(),trace.prepares,trace.scanned,trace.retired,trace.soft_freed,self.body_charge.load(Ordering::Acquire),self.db.stats(Kind(4)).computed,self.db.stats(Kind(23)).computed,self.db.stats(Kind(24)).computed,self.db.stats(Kind(25)).computed,self.db.stats(Kind(26)).computed,self.db.stats(Kind(27)).computed);}}
}

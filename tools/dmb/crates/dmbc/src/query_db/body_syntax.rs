//! Body syntax lives in the SAME graph as compilation inputs, not a sibling
//! analysis cache. Revision-scoped keys are deliberately conservative: no
//! cross-revision reuse of ASTs containing absolute expanded-source positions.
use super::*;
use dm_tree::frontend::{
    BodySyntax, BodySyntaxFailure, BodySyntaxInput, BodySyntaxQueries, Diagnostic, DiagnosticKind,
    DiagnosticStage,OriginalBodySyntaxProduct,BodyCodeIdentity,
};
use std::sync::{
    atomic::Ordering,
    Weak,
};

pub(super) const BODY_SYNTAX: Kind = Kind(4);
pub(super) const BUDGET: usize = 128 * 1024 * 1024;

#[derive(Debug)]
struct Params {
    input: Weak<BodySyntaxInput>,
    key: Key,
    // Tiny code owner prevents pointer-locator ABA while graph metadata lives.
    // No source/input/tree/model is retained strongly through Params.
    code:Option<Arc<BodyCodeIdentity>>,
}
const CANONICAL_DOMAIN:u128=1u128<<127;
pub(super) fn code_key(input:&BodySyntaxInput)->Result<Key,BodySyntaxFailure>{
 let code=input.original_code_owner().ok_or_else(||BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::NotConnected,"actual canonical BODY code owner absent")))?;
 Ok(Key::new(BODY_SYNTAX,CANONICAL_DOMAIN|Arc::as_ptr(code)as usize as u128))
}
enum BodyQueryValue{
 Issued(Result<Arc<BodySyntax>,Diagnostic>),
 Canonical(Result<Arc<OriginalBodySyntaxProduct>,Diagnostic>),
}
impl BodyQueryValue{
 fn issued(&self)->Result<Arc<BodySyntax>,Diagnostic>{match self{Self::Issued(result)=>result.clone(),Self::Canonical(_)=>Err(Diagnostic{kind:DiagnosticKind::Internal,stage:DiagnosticStage::Internal,message:"canonical BODY product cannot masquerade as an absolute parser issuance".into(),location:None})}}
 fn consumed(&self)->bool{match self{
  Self::Issued(result)=>result.as_ref().map_or(true,|syntax|Arc::strong_count(syntax)==1),
  Self::Canonical(result)=>result.as_ref().map_or(true,|product|Arc::strong_count(product)==1&&product.parsed().map_or(true,|syntax|Arc::strong_count(syntax)==1)),
 }}
}
#[derive(Debug)]struct CanonicalBodyContractDiagnostic(Diagnostic);
impl std::fmt::Display for CanonicalBodyContractDiagnostic{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{write!(f,"native canonical BODY producer emitted a source-bound error without its raw native receipt: {:?}",self.0)}}
impl std::error::Error for CanonicalBodyContractDiagnostic{}


pub(super) fn register(db: &Db, charged: Arc<dm_syntax::SettingChargeCounter>) {
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
        if let Some(code)=&params.code{
            if !input.original_code_owner().is_some_and(|actual|Arc::ptr_eq(actual,code)){return Err(QueryError::operational(params.key,std::io::Error::new(std::io::ErrorKind::InvalidData,"actual canonical BODY Params code/input differ")))}
            let parsed=setting_syntax::with_setting_admission(&charged,|a|input.parse_original_product_with_setting_admission(a));
            let result=match parsed{
                Ok(product)=>Ok(Arc::new(product)),
                Err(BodySyntaxFailure::Operational(error))=>return Err(QueryError::operational(params.key,error)),
                Err(BodySyntaxFailure::Syntax(error))=>{
                    // All authored native grammar errors were retained BEFORE
                    // location translation. An unlocated Internal contract fault
                    // is invariant code DATA; a bound error without that actual
                    // issuer is an infrastructure failure, never stale source.
                    if error.location.is_some()||error.kind!=DiagnosticKind::Internal{return Err(QueryError::operational(params.key,std::io::Error::other(CanonicalBodyContractDiagnostic(error))))}
                    Err(error)
                }
            };
            let bytes=result.as_ref().map_or(1024,|product|product.budget_charge());charged.add_soft_estimate(bytes);
            return Ok(Outcome::new(BodyQueryValue::Canonical(result),params.key.id,bytes))
        }
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
        charged.add_soft_estimate(bytes);
        Ok(Outcome::new(BodyQueryValue::Issued(result), params.key.id, bytes))
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
    fn prepare_syntax_product_input(&self,input:&Arc<BodySyntaxInput>)->Result<(),BodySyntaxFailure>{let key=code_key(input)?;self.prepare_body_input_key(input,key).map_err(checked_query_failure)}
    fn begin_revision_inputs(&self,current:&[Arc<BodySyntaxInput>]){
        {let mut inputs=self.body_inputs.lock().unwrap_or_else(|error|error.into_inner());for input in current{if let Ok(key)=code_key(input){if let Some(slot)=inputs.get_mut(&key){*slot=Arc::downgrade(input);}}}}
        self.begin_revision();
    }
    fn syntax_product_checked(&self,input:&Arc<BodySyntaxInput>)->Result<Arc<OriginalBodySyntaxProduct>,BodySyntaxFailure>{
        let key=code_key(input)?;self.prepare_body_input_key(input,key).map_err(checked_query_failure)?;
        let code=Arc::clone(input.original_code_owner().expect("actual code locator checked"));
        let value=self.db.get::<BodyQueryValue>(key,Arc::new(Params{input:Arc::downgrade(input),key,code:Some(code)})).map_err(checked_query_failure)?;
        match value.as_ref(){BodyQueryValue::Canonical(result)=>result.clone().map_err(BodySyntaxFailure::Syntax),BodyQueryValue::Issued(_)=>Err(BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidData,"issued BODY parser result cannot masquerade as a canonical product")))}
    }
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
                self.body_charge.release_soft_estimate(freed);
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
        self.prepare_body_input_key(input,Key::new(BODY_SYNTAX,input.key().into()))
    }
    fn prepare_body_input_key(&self,input:&Arc<BodySyntaxInput>,key:Key)->Result<(),QueryError>{
        #[cfg(test)]self.record_pressure_trace_for_test(0,0);
        crate::daemon::control::checkpoint().map_err(|actual|QueryError::operational(key,actual))?;
        let mut inputs=self.body_inputs.lock().unwrap_or_else(|e|e.into_inner());
        inputs.insert(key,Arc::downgrade(input));
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
            self.body_charge.release_soft_estimate(freed);
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
            let Some(value)=self.db.retained_value::<BodyQueryValue>(candidate)else{continue};
            let consumed=Arc::strong_count(&value)==2&&value.consumed();
            if !consumed{continue}
            let freed=self.db.evict_value_if_current(candidate,&value);
            // Free the actual body/retention guards before crediting its soft
            // estimate. Escaped children keep their own real leases alive.
            drop(value);
            #[cfg(test)]if freed!=0{self.record_pressure_trace_for_test(2,freed);}
            if freed!=0{self.body_charge.release_soft_estimate(freed);}
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
        let result = self.db.get::<BodyQueryValue>(
            key,
            Arc::new(Params {
                input: Arc::downgrade(input),
                key,code:None,
            }),
        )?;
        Ok(result.issued())
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
 obtain_issued(ctx,input).map_err(checked_query_failure)?.map_err(BodySyntaxFailure::Syntax)
}

/// Loan the exact issued child to a policy that must preserve the distinction
/// between an operational query failure and the child's authored syntax result.
pub(super) fn obtain_issued(
 ctx:&mut dm_query::Ctx<'_>,input:&Arc<BodySyntaxInput>,
)->Result<Result<Arc<BodySyntax>,Diagnostic>,QueryError>{
 let key=Key::new(BODY_SYNTAX,input.key().into());
 Ok(ctx.get::<BodyQueryValue>(key,Arc::new(Params{input:Arc::downgrade(input),key,code:None}))?.issued())
}

/// Record a real syntax dependency of a derived policy query. The archive's
/// later parse request borrows this exact cached value through its host.
pub(super) fn observe(
    ctx: &mut dm_query::Ctx<'_>,
    input: &Arc<BodySyntaxInput>,
) -> Result<(), QueryError> {
    let key = Key::new(BODY_SYNTAX, input.key().into());
    ctx.get::<BodyQueryValue>(
        key,
        Arc::new(Params {
            input: Arc::downgrade(input),
            key,code:None,
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

#[cfg(test)]
#[path = "body_syntax_census_tests.rs"]
mod body_syntax_census_tests;

#[cfg(test)]mod actual_canonical_product_tests{
 #[test]fn actual_current_original_body_disposition_binds_only_same_product_and_preserves_unissued(){
  use dm_tree::frontend::OriginalBodyDisposition as D;
  for (body,kind)in[("return 1",0),("return argument.field",0),("return argument +",1),("return\targument +",1),("return   argument +",1),("return (1 +)",2)]{
   let db=Arc::new(QueryDb::default());let mut state=RetainedSemanticTree::new();let front=original_frontend(&mut state,&db,&format!("/proc/p(argument)\n    {body}\n"));let archive=Arc::clone(front.source_view().unwrap().archive());
   setting_syntax::with_setting_admission(&db.body_charge,|a|archive.with_current_body_checked(0,a,|current|{
    match(kind,current.syntax().original_code_disposition()){(0,Ok(D::Available(grant)))|(1,Ok(D::Skipped(grant)))=>{assert!(grant.belongs_to(current.syntax()));assert!(grant.statement_span()?.is_some());},(2,Err(BodySyntaxFailure::Operational(error)))=>assert_eq!(error.kind(),std::io::ErrorKind::Unsupported),_=>panic!("actual current disposition differs for {body}")};Ok(())
   })).unwrap();assert_eq!(db.db.stats(BODY_SYNTAX).computed,1);
  }
 }
 #[test]
 fn actual_original_plain_assignment_return_owns_its_body_disposition() {
    use dm_tree::frontend::OriginalBodyDisposition as D;
    for (body, available) in [
        ("return argument = value", true),
        ("return argument = (value ? 1 : 2)", true),
        ("if(value)\n        return argument = value\n    return argument", true),
        ("return argument.field = value", false),
        ("return argument += value", false),
        ("return (argument = value)", false),
        ("return argument = value = other", false),
        ("if(argument = value)\n        return value", false),
    ] {
        let db = Arc::new(QueryDb::default());
        let front = issued_original_fixture(&db, &format!("/proc/p(argument, value, other)\n    {body}\n"));
        let input = original_input(&front, "p");
        let product = db.syntax_product_checked(&input).unwrap();
        setting_syntax::with_setting_admission(&db.body_charge, |admission| {
            let bound = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
            match (available, bound.original_code_disposition()) {
                (true, Ok(D::Available(grant))) => assert!(grant.belongs_to(&bound)),
                (false, Err(BodySyntaxFailure::Operational(error))) => assert_eq!(error.kind(), std::io::ErrorKind::Unsupported),
                _ => panic!("actual current disposition differs for {body}"),
            }
            Ok::<(), BodySyntaxFailure>(())
        }).unwrap();
    }
 }
 #[test]fn actual_current_original_disposition_never_lends_a_foreign_grant_or_swallows_native_io(){
  let db=Arc::new(QueryDb::default());let text="/proc/p(argument)\n    return argument.field\n";let own=original_frontend(&mut RetainedSemanticTree::new(),&db,text);let other=original_frontend(&mut RetainedSemanticTree::new(),&db,text);let original=original_input(&own,"p");let foreign=original_input(&other,"p");let product=db.syntax_product_checked(&original).unwrap();
  setting_syntax::with_setting_admission(&db.body_charge,|a|{let bound=original.bind_original_product_checked(product.parsed().unwrap(),a)?;assert!(matches!(bound.original_code_disposition()?,dm_tree::frontend::OriginalBodyDisposition::Available(_)));assert!(foreign.bind_original_product_checked(product.parsed().unwrap(),a).is_err());Ok::<(),BodySyntaxFailure>(())}).unwrap();
  let archive=Arc::clone(own.source_view().unwrap().archive());let called=std::cell::Cell::new(false);let fault=||Err(std::io::Error::from_raw_os_error(1450));let a=dm_syntax::SettingAdmission::new(&db.body_charge,BUDGET,&fault);let Err(BodySyntaxFailure::Operational(error))=archive.with_current_body_checked(0,&a,|_|{called.set(true);Ok(())})else{panic!("actual operational error must survive before disposition")};assert_eq!(error.raw_os_error(),Some(1450));assert!(!called.get());
 }

 use super::*;
 use dm_tree::frontend::{RetainedSemanticTree,SettingExpressionQueries,FrontendConfig};
 struct Source(dm_preprocess::AcquiredSource);
 impl dm_preprocess::SourceProvider for Source{
  fn read(&self,_:&std::path::Path)->Result<String,String>{Err("actual original acquisition required".into())}
  fn acquired_source(&self,_:&std::path::Path)->Result<Option<dm_preprocess::AcquiredSource>,String>{Ok(Some(self.0.clone()))}
  fn source_acquisition(&self,_:&std::path::Path,text:&dm_preprocess::SourceText)->Option<dm_preprocess::AcquiredSource>{self.0.lease().source_text().same_view(text).then(||self.0.clone())}
 }
 fn frontend(state:&mut RetainedSemanticTree,db:&Arc<QueryDb>,text:&str)->dm_tree::frontend::ColdFrontend{
  let source=Source(dm_preprocess::AcquiredSource::from_original_bytes(text.as_bytes().to_vec(),()));let executor=dm_exec::BuildExecutor::new(1).unwrap();let host=Arc::clone(db)as Arc<dyn SettingExpressionQueries>;
  dm_tree::frontend::build_with_executor_and_semantic_state_for_policy_checked(std::path::Path::new("canonical-body.dme"),&source,&Default::default(),FrontendConfig{workers:1,engine:None,observer:None},None,&executor,Some(state),true,&host).unwrap().with_body_queries(Arc::clone(db)as Arc<dyn BodySyntaxQueries>)
 }
 struct OriginalSource(Source);
 impl dm_preprocess::SourceProvider for OriginalSource{
  fn initial_environment(&self)->dm_preprocess::InitialEnvironment{dm_preprocess::InitialEnvironment::OriginalChecker0290}
  fn read(&self,path:&std::path::Path)->Result<String,String>{dm_preprocess::SourceProvider::read(&self.0,path)}
  fn acquired_source(&self,path:&std::path::Path)->Result<Option<dm_preprocess::AcquiredSource>,String>{dm_preprocess::SourceProvider::acquired_source(&self.0,path)}
  fn source_acquisition(&self,path:&std::path::Path,text:&dm_preprocess::SourceText)->Option<dm_preprocess::AcquiredSource>{dm_preprocess::SourceProvider::source_acquisition(&self.0,path,text)}
 }
 fn original_frontend(state:&mut RetainedSemanticTree,db:&Arc<QueryDb>,text:&str)->dm_tree::frontend::DiagnosticFrontend{
  let seed=dm_tree::checker_builtins::original_analysis_seed().expect("actual fixed Original declaration seed");let source=OriginalSource(Source(dm_preprocess::AcquiredSource::from_original_bytes(text.as_bytes().to_vec(),())));let executor=dm_exec::BuildExecutor::new(1).unwrap();let host=Arc::clone(db)as Arc<dyn SettingExpressionQueries>;
  let frontend=dm_tree::frontend::build_for_original_analysis_with_state_checked(std::path::Path::new("canonical-original-body.dme"),&source,&Default::default(),FrontendConfig{workers:1,engine:Some(seed.frontend_seed()),observer:None},None,&executor,Some(state),&host).unwrap().with_body_queries(Arc::clone(db)as Arc<dyn BodySyntaxQueries>).unwrap();assert!(frontend.original_analysis_completeness().is_some());frontend
 }
 fn original_input(front:&dm_tree::frontend::DiagnosticFrontend,name:&str)->Arc<BodySyntaxInput>{let view=front.source_view().unwrap();let archive=view.archive();let ordinal=archive.occurrences().iter().enumerate().find(|(_,row)|view.tree().member(row.member).unwrap().name==dm_ir::SymbolId::of(name)).unwrap().0;Arc::clone(&archive.syntax_inputs().unwrap()[ordinal])}
 fn input(front:&dm_tree::frontend::ColdFrontend,name:&str)->Arc<BodySyntaxInput>{
  let archive=front.body_archive().unwrap();let ordinal=archive.occurrences().iter().enumerate().find(|(_,row)|front.snapshot.tree.member(row.member).unwrap().name==dm_ir::SymbolId::of(name)).unwrap().0;Arc::clone(&archive.syntax_inputs().unwrap()[ordinal])
 }
 #[test]fn actual_same_graph_kind4_reuses_one_canonical_product_after_same_chunk_length_change_and_current_offset_shift(){
  let db=Arc::new(QueryDb::default());let mut state=RetainedSemanticTree::new();let p="/proc/p(value=list(1,2))\n    set name = \"p\"\n    var/local[2]=list(1,2)\n    return \"a[value]z\"\n";
  let old=frontend(&mut state,&db,&format!("/proc/q()\n    return 22222222\n{p}"));let old_input=input(&old,"p");let before=db.db.stats(BODY_SYNTAX).computed;
  let product=db.syntax_product_checked(&old_input).unwrap();let parsed=Arc::clone(product.parsed().unwrap());assert_eq!(db.db.stats(BODY_SYNTAX).computed,before+1);
  let after=frontend(&mut state,&db,&format!("/proc/q()\n    return 1\n    // genuine added line before unchanged p\n{p}"));let current=input(&after,"p");assert_ne!(old_input.key(),current.key());assert_eq!(code_key(&old_input).unwrap(),code_key(&current).unwrap());
  let warm=db.syntax_product_checked(&current).unwrap();assert!(Arc::ptr_eq(&product,&warm));assert!(Arc::ptr_eq(&parsed,warm.parsed().unwrap()));assert_eq!(db.db.stats(BODY_SYNTAX).computed,before+1,"actual Q4 provider did not reparse unchanged BODY");
  setting_syntax::with_setting_admission(&db.body_charge,|a|{
   let bound=current.bind_original_product_checked(&parsed,a)?;let parameter=bound.parameters()?.entries().unwrap().next().unwrap();assert_eq!(parameter.original().ordinal(),0);assert!(bound.current_diagnostics().next().is_none());Ok::<(),BodySyntaxFailure>(())
  }).unwrap();
  drop(old_input);drop(old);db.begin_revision();let again=db.syntax_product_checked(&current).unwrap();assert!(Arc::ptr_eq(&warm,&again));assert_eq!(db.db.stats(BODY_SYNTAX).computed,before+1,"latest weak current input refreshed before old issuance pruning");
  let fresh=frontend(&mut RetainedSemanticTree::new(),&db,&format!("/proc/q()\n    return 1\n    // genuine added line before unchanged p\n{p}"));let unissued=input(&fresh,"p");assert_ne!(code_key(&current).unwrap(),code_key(&unissued).unwrap(),"equal bytes without predecessor capture do not create code authority");let fresh_product=db.syntax_product_checked(&unissued).unwrap();assert!(!Arc::ptr_eq(&product,&fresh_product));assert_eq!(db.db.stats(BODY_SYNTAX).computed,before+2);
 }

 #[test]fn actual_current_archive_entry_records_same_kind4_dependency_and_rebinds_after_changed_current_source_input(){
  let db=Arc::new(QueryDb::default());let mut state=RetainedSemanticTree::new();let p="/proc/p(value=1)\n    return value\n";let old=frontend(&mut state,&db,&format!("/proc/q()\n    return 222222\n{p}"));let old_archive=old.body_archive().unwrap();let old_input=input(&old,"p");let old_key=code_key(&old_input).unwrap();let p_ordinal=old_archive.occurrences().iter().position(|row|old.snapshot.tree.member(row.member).unwrap().name==dm_ir::SymbolId::of("p")).unwrap();
  let driver=Key::new(Kind(246),1);db.db.define_input(driver.kind,"actual current original archive");db.db.set_input(driver,Arc::clone(&old_archive),old_input.key().into());
  let parent=Key::new(Kind(247),1);let charged=Arc::clone(&db.body_charge);
  db.db.define(parent.kind,"actual current canonical body consumer",move|ctx,_|{
   let archive=ctx.get::<Arc<dm_tree::frontend::BodyArchive>>(driver,Arc::new(()))?;
   let line=setting_syntax::with_setting_admission(&charged,|a|archive.with_current_body_checked_in(p_ordinal,a,ctx,|ctx,input|obtain_product(ctx,input),|_,body|{
    assert!(body.belongs_to(&archive));let parameter=body.syntax().parameters()?.entries().unwrap().next().unwrap();assert_eq!(body.current_source(parameter.name().unwrap())?,"value");
    Ok(body.occurrence().source.line)
   })).map_err(|failure|match failure{BodySyntaxFailure::Operational(actual)=>QueryError::operational(parent,actual),BodySyntaxFailure::Syntax(actual)=>QueryError::operational(parent,std::io::Error::other(format!("unexpected real source refusal in valid native control: {actual:?}")))})?;
   Ok(Outcome::new(line,line as u128,std::mem::size_of::<usize>()))
  });
  let before=db.db.stats(BODY_SYNTAX).computed;let first=db.db.get::<usize>(parent,Arc::new(())).unwrap();assert!(db.db.dependants(&[old_key]).contains(&parent));assert_eq!(db.db.stats(BODY_SYNTAX).computed,before+1);
  let new=frontend(&mut state,&db,&format!("/proc/q()\n    return 1\n    // actual added source line\n{p}"));let archive=new.body_archive().unwrap();let current=input(&new,"p");assert_eq!(code_key(&current).unwrap(),old_key);db.db.set_input(driver,archive,current.key().into());let second=db.db.get::<usize>(parent,Arc::new(())).unwrap();assert_eq!(*second,*first+1);assert_eq!(db.db.stats(BODY_SYNTAX).computed,before+1,"changed current-source parent reuses exact canonical syntax child");assert!(db.db.dependants(&[old_key]).contains(&parent));
 }

 #[test]fn actual_current_bitwise_producer_reuses_native_algorithm_and_code_product_after_same_chunk_source_edit(){
  let db=Arc::new(QueryDb::default());let mut state=RetainedSemanticTree::new();let p="/proc/p(a,b)\n    return !a & b\n";let old=frontend(&mut state,&db,&format!("/proc/q()\n    return 222222\n{p}"));let archive=old.body_archive().unwrap();let p_ordinal=archive.occurrences().iter().position(|row|old.snapshot.tree.member(row.member).unwrap().name==dm_ir::SymbolId::of("p")).unwrap();
  let before=db.db.stats(BODY_SYNTAX).computed;
  let run=|archive:&dm_tree::frontend::BodyArchive|setting_syntax::with_setting_admission(&db.body_charge,|a|archive.with_current_body_checked(p_ordinal,a,|body|{
   dm_analysis::checks::current_ambiguous_not_bitwise(&body,dm_analysis::checks::Severity::Warning,&||Ok(())).map_err(|failure|match failure{dm_analysis::policy_body_demand::PolicyFailure::Operational(actual)=>BodySyntaxFailure::Operational(actual),other=>BodySyntaxFailure::Operational(std::io::Error::other(other.to_string()))})
  })).unwrap();
  let first=run(&archive);assert_eq!(first.len(),1);assert_eq!(first[0].message,"Ambiguous `!` on left side of bitwise `&` operator");assert_eq!(first[0].notes.iter().map(|note|note.legacy_text()).collect::<Vec<_>>(),["Did you mean `!(x & y)`?","Did you mean `!x && y`?","Did you mean `~x & y`?"]);
  let current=frontend(&mut state,&db,&format!("/proc/q()\n    return 1\n    // actual added source line\n{p}"));let archive=current.body_archive().unwrap();let next=run(&archive);assert_eq!(next.len(),1);assert_eq!(first[0].message,next[0].message);assert_eq!(first[0].notes,next[0].notes);
  let first_archive=old.body_archive().unwrap();let old_line=first_archive.source_note_point(first[0].span.start).unwrap().line;let line=archive.source_note_point(next[0].span.start).unwrap().line;assert_eq!(line,old_line+1);assert_eq!(db.db.stats(BODY_SYNTAX).computed,before+1,"pure consumer uses SAME existing canonical Q4 product");
  let fail=||Err(std::io::Error::from_raw_os_error(1450));setting_syntax::with_setting_admission(&db.body_charge,|a|archive.with_current_body_checked(p_ordinal,a,|body|{
   let Err(dm_analysis::policy_body_demand::PolicyFailure::Operational(actual))=dm_analysis::checks::current_ambiguous_not_bitwise(&body,dm_analysis::checks::Severity::Warning,&fail)else{panic!("real current consumer failure must not publish partial rows")};assert_eq!(actual.raw_os_error(),Some(1450));Ok(())
  })).unwrap();assert_eq!(db.db.stats(BODY_SYNTAX).computed,before+1);
 }
 #[test]fn actual_current_parameter_source_view_reuses_one_ledger_and_native_validator_after_source_shift(){
  let db=Arc::new(QueryDb::default());let mut state=RetainedSemanticTree::new();let p="/proc/p(obj/value[]=list(1,2),other=3)\n    return value\n";
  let old=frontend(&mut state,&db,&format!("/proc/q()\n    return 22222222\n{p}"));let old_input=input(&old,"p");let before=db.db.stats(BODY_SYNTAX).computed;let product=db.syntax_product_checked(&old_input).unwrap();let old_a=dm_syntax::SettingAdmission::new(&db.body_charge,BUDGET,&||Ok(()));let old_binding=old_input.bind_original_product_checked(product.parsed().unwrap(),&old_a).unwrap();let original_signature=old_binding.parameters().unwrap().original();
  let new=frontend(&mut state,&db,&format!("/proc/q()\n    return 1\n    // actual current line before unchanged p\n{p}"));let archive=new.body_archive().unwrap();let ordinal=archive.occurrences().iter().position(|row|new.snapshot.tree.member(row.member).unwrap().name==dm_ir::SymbolId::of("p")).unwrap();
  setting_syntax::with_setting_admission(&db.body_charge,|a|archive.with_current_body_checked(ordinal,a,|body|{
   let view=body.source_parameters(a)?;view.require_for(body.tree(),body.occurrence()).unwrap();let entries=view.entries().unwrap();assert!(std::ptr::eq(entries,original_signature.entries().unwrap()),"same canonical ledger, no copied current signature");assert_eq!(view.header_span().unwrap(),body.syntax().header_span());assert_eq!(view.name(&entries[0]).unwrap(),"value");assert_eq!(view.type_path(&entries[0]).unwrap().as_deref(),Some("/list/obj"));assert_eq!(view.name(&entries[1]).unwrap(),"other");assert_eq!(view.type_path(&entries[1]).unwrap(),None);let cursor=view.declaration_cursor(&entries[0]).unwrap();assert_eq!(body.current_source(cursor)?,"[");
   let calls=std::cell::Cell::new(0usize);let fail=||{let n=calls.get()+1;calls.set(n);if n==3{Err(std::io::Error::from_raw_os_error(1450))}else{Ok(())}};let fault=dm_syntax::SettingAdmission::new(&db.body_charge,BUDGET,&fail);let Err(BodySyntaxFailure::Operational(actual))=body.source_parameters(&fault)else{panic!("real per-formal checkpoint must retain first typed failure")};assert_eq!(actual.raw_os_error(),Some(1450));assert_eq!(calls.get(),3);
   let old_archive=old.body_archive().unwrap();assert!(view.require_for(old_archive.tree(),&old_archive.occurrences()[ordinal]).is_err(),"current source view never certifies the old semantic tree/occurrence");Ok(())
  })).unwrap();assert_eq!(db.db.stats(BODY_SYNTAX).computed,before+1,"source/parameter consumers share unchanged canonical product");
 }
 #[test]fn actual_current_local_source_view_preserves_native_ledger_and_scope_after_earlier_shift(){
  let db=Arc::new(QueryDb::default());let mut state=RetainedSemanticTree::new();let p="/proc/p()\n    var/obj/owned[2]\n    var/plain=1\n    return plain\n";let old=frontend(&mut state,&db,&format!("/proc/q()\n    return 22222222\n{p}"));let old_input=input(&old,"p");let before=db.db.stats(BODY_SYNTAX).computed;let product=db.syntax_product_checked(&old_input).unwrap();let parsed=product.parsed().unwrap();let original=parsed.statement_storage().parsed().local_variables.entries().unwrap();assert_eq!(original.len(),2);
  let new=frontend(&mut state,&db,&format!("/proc/q()\n    return 1\n{p}"));let archive=new.body_archive().unwrap();let ordinal=archive.occurrences().iter().position(|row|new.snapshot.tree.member(row.member).unwrap().name==dm_ir::SymbolId::of("p")).unwrap();
  setting_syntax::with_setting_admission(&db.body_charge,|a|archive.with_current_body_checked(ordinal,a,|body|{
   let view=body.source_locals(a)?;view.require_for(body.tree(),body.occurrence(),body.syntax().canonical_statement_storage()).unwrap();let entries=view.entries().unwrap();assert!(std::ptr::eq(entries,original));assert_eq!(view.name(&entries[0]).unwrap(),"owned");assert_eq!(view.type_path(&entries[0]).unwrap().as_deref(),Some("/list/obj"));assert_eq!(view.type_path_width(&entries[0]).unwrap(),9);assert_eq!(view.name(&entries[1]).unwrap(),"plain");assert_eq!(view.type_path(&entries[1]).unwrap(),None);assert!(view.scope_admission().unwrap()>4096);assert!(std::ptr::eq(view.in_current_span(body.syntax().body_span()).unwrap(),entries));
   let calls=std::cell::Cell::new(0usize);let fail=||{let n=calls.get()+1;calls.set(n);if n==3{Err(std::io::Error::from_raw_os_error(1450))}else{Ok(())}};let fault=dm_syntax::SettingAdmission::new(&db.body_charge,BUDGET,&fail);let Err(BodySyntaxFailure::Operational(actual))=body.source_locals(&fault)else{panic!("real local component traversal checkpoint must preserve typed fault")};assert_eq!(actual.raw_os_error(),Some(1450));assert_eq!(calls.get(),3);Ok(())
  })).unwrap();assert_eq!(db.db.stats(BODY_SYNTAX).computed,before+1);
 }
 #[test]fn current_archive_entry_rejects_real_foreign_product_and_counter_before_consumer_without_fallback(){
  let db=Arc::new(QueryDb::default());let mut state=RetainedSemanticTree::new();let text="/proc/p()\n    return 1\n";let front=frontend(&mut state,&db,text);let archive=front.body_archive().unwrap();let foreign=frontend(&mut RetainedSemanticTree::new(),&db,text);let foreign_input=input(&foreign,"p");let product=db.syntax_product_checked(&foreign_input).unwrap();let called=std::cell::Cell::new(false);
  setting_syntax::with_setting_admission(&db.body_charge,|a|{
   let result=archive.with_current_body_checked_in(0,a,&mut(),|_,_|Ok(Arc::clone(&product)),|_,_|{called.set(true);Ok(())});assert!(result.is_err());assert!(!called.get());Ok::<(),BodySyntaxFailure>(())
  }).unwrap();
  let foreign_counter=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=dm_syntax::SettingAdmission::new(&foreign_counter,BUDGET,&||Ok(()));assert!(archive.with_current_body_checked(0,&a,|_|{called.set(true);Ok(())}).is_err());assert!(!called.get());
  let provider=Source(dm_preprocess::AcquiredSource::from_original_bytes(text.as_bytes().to_vec(),()));let no_host=dm_tree::frontend::build(std::path::Path::new("no-current-host.dme"),&provider,&Default::default(),1).unwrap().body_archive().unwrap();let Err(BodySyntaxFailure::Operational(error))=no_host.with_current_body_checked(0,&a,|_|{called.set(true);Ok(())})else{panic!("missing real native current host")};assert_eq!(error.kind(),std::io::ErrorKind::NotConnected);assert!(!called.get(),"missing canonical host never invokes a standalone parser/consumer");
 }
 #[test]fn actual_canonical_kind4_retirement_uses_existing_family_budget_and_preserves_escaped_roots(){
  let db=Arc::new(QueryDb::default());let mut state=RetainedSemanticTree::new();let front=frontend(&mut state,&db,"/proc/p()\n    return \"kept [1]\"\n");let current=input(&front,"p");let key=code_key(&current).unwrap();let product=db.syntax_product_checked(&current).unwrap();let root=Arc::clone(product.parsed().unwrap());let before=db.db.stats(BODY_SYNTAX).computed;
  let value=db.db.retained_value::<BodyQueryValue>(key).unwrap();assert!(!value.consumed(),"active canonical product/root cannot be retired by consumed-value pressure");drop(value);
  let weak=Arc::downgrade(&current);drop(current);drop(front);assert_eq!(weak.strong_count(),0,"graph Params retain only tiny code owner, never original input");
  db.begin_revision();assert!(!db.body_inputs.lock().unwrap().contains_key(&key));assert_eq!(db.db.value_bytes_at(key),0);assert!(root.statement_storage().has_native_literal_syntax());assert_eq!(db.db.stats(BODY_SYNTAX).computed,before,"retirement does not reparse escaped original roots");
 }
 #[test]fn actual_canonical_kind4_preserves_first_typed_parser_operational_failure_and_retries_same_code(){
  let db=Arc::new(QueryDb::default());let mut state=RetainedSemanticTree::new();let front=frontend(&mut state,&db,"/proc/p()\n    return \"[1]\"\n");let input=input(&front,"p");let before=db.db.stats(BODY_SYNTAX).computed;
  let injected=db.fail_body_syntax_after_for_test(0,std::io::Error::from_raw_os_error(1450));let Err(BodySyntaxFailure::Operational(error))=db.syntax_product_checked(&input)else{panic!("actual native Kind4 injected operation must fail")};assert_eq!(error.raw_os_error(),Some(1450));assert_eq!(db.db.stats(BODY_SYNTAX).computed,before);drop(injected);
  let result=db.syntax_product_checked(&input).unwrap();assert!(result.parsed().is_some());assert_eq!(db.db.stats(BODY_SYNTAX).computed,before+1);let again=db.syntax_product_checked(&input).unwrap();assert!(Arc::ptr_eq(&result,&again));assert_eq!(db.db.stats(BODY_SYNTAX).computed,before+1);
 }
 fn issued_original_fixture(db: &Arc<QueryDb>, text: &str) -> dm_tree::frontend::DiagnosticFrontend {
     let project = crate::test_scratch::dir("admin-coordinate-original-body").join("project.dme");
     std::fs::write(&project, text).unwrap();
     let inputs = crate::input_snapshot::RecordingInputs::new(crate::input_snapshot::FileSystemInputs, 0)
         .with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);
     let provider = inputs.original_batch_view(None);
     let seed = dm_tree::checker_builtins::original_analysis_seed().unwrap();
     let executor = dm_exec::BuildExecutor::new(1).unwrap();
     let host = Arc::clone(db) as Arc<dyn SettingExpressionQueries>;
     dm_tree::frontend::build_for_original_compound_with_callable_anchors_checked(
         &project, &provider, &Default::default(),
         FrontendConfig { workers: 1, engine: Some(seed.frontend_seed()), observer: None },
         None, &executor, None, &host, None,
     ).unwrap().with_body_queries(Arc::clone(db) as Arc<dyn BodySyntaxQueries>).unwrap()
 }

 #[test]
 fn actual_current_nested_admin_coordinate_template_has_complete_original_body() {
     let text = r#"
#define ADMIN_JMP(point) "<a href='byond://?X=[point.x];Y=[point.y]'>JMP</a>"
/proc/Admin_Coordinates_Readable(atom/source, area_name, admin_jump_ref)
    var/turf/turf_at_coords = Safe_COORD_Location(source)
    return turf_at_coords ? "[area_name ? "[get_area_name(turf_at_coords, 1)] " : " "]([turf_at_coords.x],[turf_at_coords.y],[turf_at_coords.z])[admin_jump_ref ? " [ADMIN_JMP(turf_at_coords)]" : ""]" : "nonexistent location"
"#;
     let db = Arc::new(QueryDb::default());
     let front = issued_original_fixture(&db, text);
     let input = original_input(&front, "Admin_Coordinates_Readable");
     let product = db.syntax_product_checked(&input).unwrap();
     setting_syntax::with_setting_admission(&db.body_charge, |admission| {
         let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
         assert!(body.canonical_statement_storage().has_native_literal_syntax());
         let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = body.original_code_disposition()? else {
             panic!("the consumed local and return productions are available");
         };
         assert!(proof.belongs_to(&body));
         assert_eq!(proof.statement_span()?, None);
         Ok::<(), BodySyntaxFailure>(())
     }).unwrap();
 }


 #[test]
 fn actual_safe_coordinate_lookup_body_witness_keeps_control_and_assignment_shapes() {
     let fixture = r#"
/proc/Safe_COORD_Location(atom/source)
    if(isturf(source))
        return source
    var/atom/drop_atom = source.drop_location()
    if(!drop_atom)
        return
    var/turf/drop_turf = get_step(drop_atom, 0)
    if(!drop_turf)
        var/atom/last_try = drop_atom.loc?.drop_location()
        if(last_try)
            drop_turf = get_step(last_try, 0)
    return drop_turf
"#;
     for (text, expected) in [
         (fixture.to_owned(), true),
         (fixture.replace("if(isturf(source))", "if(isturf(source)) ;"), false),
         (fixture.replace("get_step(last_try, 0)", "get_step(last_try, distance = 0)"), false),
         (fixture.replace("drop_atom.loc?.drop_location()", "drop_atom.loc?:drop_location()"), false),
     ] {
         let db = Arc::new(QueryDb::default());
         let front = issued_original_fixture(&db, &text);
         let input = original_input(&front, "Safe_COORD_Location");
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let product = product.parsed().expect("native grammar produces the control body");
             let body = input.bind_original_product_checked(product, admission)?;
             let disposition = body.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = disposition? else {
                     panic!("the control body must be available");
                 };
                 assert!(proof.belongs_to(&body));
             } else {
                 assert!(matches!(disposition, Err(BodySyntaxFailure::Operational(error)) if error.kind() == std::io::ErrorKind::Unsupported), "{text}");
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]
 fn actual_original_repeated_safe_dot_fields_consume_each_authored_follow() {
     let fixture = r#"
/proc/admin_seed_spawn_advanced_call(mob/actor)
    return (GLOB.AdminProcCaller && GLOB.AdminProcCaller == actor?.client?.ckey) || (GLOB.AdminProcCallHandler && actor == GLOB.AdminProcCallHandler)
/proc/safe_field(mob/actor)
    return actor?.client?.ckey
/proc/mixed_field(mob/actor)
    return actor?.client.ckey
/proc/safe_colon(mob/actor)
    return actor?.client?:ckey
/proc/colon_receiver(mob/actor)
    return actor?:client?.ckey
/proc/index_receiver(mob/actor, index)
    return actor?.client?[index]?.ckey
"#;
     let db = Arc::new(QueryDb::default());
     let front = issued_original_fixture(&db, fixture);
     for (name, expected) in [
         ("admin_seed_spawn_advanced_call", true), ("safe_field", true), ("mixed_field", true),
         ("safe_colon", false), ("colon_receiver", false), ("index_receiver", false),
     ] {
         let input = original_input(&front, name);
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let disposition = body.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = disposition? else {
                     panic!("actual Original SafeDot field chain is available: {name}");
                 };
                 assert!(proof.belongs_to(&body));
             } else {
                 assert!(matches!(disposition, Err(BodySyntaxFailure::Operational(error))
                     if error.kind() == std::io::ErrorKind::Unsupported), "{name}");
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]
 fn actual_original_indexed_writes_require_exact_target_and_indexed_value() {
     let fixture = r#"
/proc/probe(rlist, keys, values, altlist, i)
    rlist[1] += keys[i]
    rlist[(i % 2) + 1] += altlist[i]
    rlist[2][keys[i]] = values[i]
    return rlist
"#;
     for (text, expected) in [
         (fixture.to_owned(), true),
         (fixture.replace("rlist[(i % 2) + 1] +=", "rlist[(i % 2) + 1] -="), false),
         (fixture.replace("rlist[(i % 2) + 1] +=", "rlist?[(i % 2) + 1] +="), false),
         (fixture.replace("rlist[(i % 2) + 1] +=", "get_list()[(i % 2) + 1] +="), false),
         (fixture.replace("+= altlist[i]", "+= 1"), false),
         (fixture.replace("rlist[2][keys[i]] =", "return rlist[2][keys[i]] ="), false),
         (fixture.replace("rlist[2][keys[i]] =", "rlist[2][keys[i]][1] ="), false),
     ] {
         let db = Arc::new(QueryDb::default());
         let front = issued_original_fixture(&db, &text);
         let input = original_input(&front, "probe");
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let disposition = body.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = disposition? else {
                     panic!("actual Original indexed writes are available");
                 };
                 assert!(proof.belongs_to(&body));
             } else {
                 assert!(matches!(disposition, Err(BodySyntaxFailure::Operational(error))
                     if error.kind() == std::io::ErrorKind::Unsupported), "{text}");
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]
 fn actual_original_comparison_and_boolean_controls_compose_in_one_body() {
     let fixture = r#"
/proc/probe(interval, edge)
    if(!(istext(interval) && length(interval)) && (!isnum(interval) || interval <= 0))
        return null
    while(change_is_published(interval) && edge != ANY)
        return interval
    return edge
"#;
     let db = Arc::new(QueryDb::default());
     let front = issued_original_fixture(&db, fixture);
     let input = original_input(&front, "probe");
     let product = db.syntax_product_checked(&input).unwrap();
     setting_syntax::with_setting_admission(&db.body_charge, |admission| {
         let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
         let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = body.original_code_disposition()? else {
             panic!("the real nested control predicates must be available");
         };
         assert!(proof.belongs_to(&body));
         Ok::<(), BodySyntaxFailure>(())
     }).unwrap();
 }

 #[test]
 fn actual_admin_notice_consumes_grouped_for_index_and_bare_loop_continue() {
     let fixture = r#"
#define REGISTRY_MEMBERS(ID) (GLOB.registry_members[ID])
#define REGISTRY_MOBS "mob_list"
/proc/admin_notice(message, rights)
    for(var/mob/M in REGISTRY_MEMBERS(REGISTRY_MOBS))
        var/C = M.client
        if(!C)
            continue
        if(!(istype(C, /client)))
            continue
        if(check_rights_for(C, rights))
            to_chat(C, message)
"#;
     for (text, expected) in [
         (fixture.to_owned(), true),
         (fixture.replace("continue", "continue named"), false),
         (fixture.replace("            to_chat(C, message)", "            to_chat(C, message)\n    continue"), false),
         (fixture.replace("(GLOB.registry_members[ID])", "(GLOB.registry_members?[ID])"), false),
     ] {
         let db = Arc::new(QueryDb::default());
         let front = issued_original_fixture(&db, &text);
         let input = original_input(&front, "admin_notice");
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let disposition = body.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = disposition? else {
                     panic!("actual Original grouped index and ForList continue are available");
                 };
                 assert!(proof.belongs_to(&body));
             } else {
                 assert!(matches!(disposition, Err(BodySyntaxFailure::Operational(error)) if error.kind() == std::io::ErrorKind::Unsupported), "{text}");
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]
 fn actual_assertion_message_body_witness_keeps_typed_template_values_and_children() {
     let fixture = r#"
/proc/assertion_message(file, line, condition, message)
    if (!isnull(message))
        message = " - [message]"
    return "[file]:[line]:Assertion failed: [condition][message]"
"#;
     for (text, expected) in [
         (fixture.to_owned(), true),
         (fixture.replace("message = ", "message += "), false),
         (fixture.replace("[condition][message]", "[condition:member][message]"), false),
     ] {
         let db = Arc::new(QueryDb::default());
         let front = issued_original_fixture(&db, &text);
         let input = original_input(&front, "assertion_message");
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let disposition = body.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = disposition? else {
                     panic!("actual plain assignment and return template are available");
                 };
                 assert!(proof.belongs_to(&body));
             } else {
                 assert!(matches!(disposition, Err(BodySyntaxFailure::Operational(error)) if error.kind() == std::io::ErrorKind::Unsupported), "{text}");
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]
 fn actual_message_admins_body_witness_composes_macro_rights_and_keyed_statement() {
     let fixture = r#"
#define R_ADMIN (1<<1)
#define R_SERVER (1<<4)
#define R_MOD (1<<13)
#define PREFIX(text) ("<prefix>" + text + "</prefix>")
#define FILTER(text) ("<filter>" + text + "</filter>")
/proc/message_admins(msg)
    msg = FILTER(PREFIX("ADMIN LOG:") + "[msg]")
    for(var/client/C in GLOB.admins)
        if(check_rights_for(C, (R_ADMIN|R_MOD|R_SERVER)))
            to_chat(C,
                    type = "adminlog",
                    html = msg,
                    confidential = TRUE)
"#;
     for (text, expected) in [
         (fixture.to_owned(), true),
         (fixture.replace("GLOB.admins", "GLOB:admins"), false),
         (fixture.replace("html = msg", "html = (msg = TRUE)"), false),
     ] {
         let db = Arc::new(QueryDb::default());
         let front = issued_original_fixture(&db, &text);
         let input = original_input(&front, "message_admins");
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let disposition = body.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = disposition? else {
                     panic!("actual Original macro controls are available");
                 };
                 assert!(proof.belongs_to(&body));
             } else {
                 assert!(matches!(disposition, Err(BodySyntaxFailure::Operational(error)) if error.kind() == std::io::ErrorKind::Unsupported), "{text}");
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]
 fn actual_original_gaussian_else_and_do_while_keep_exact_block_links() {
     let fixture = r#"
/proc/gaussian(mean, stddev)
    var/static/gaussian_next
    var/R1;var/R2;var/working
    if(gaussian_next != null)
        R1 = gaussian_next
        gaussian_next = null
    else
        do
            R1 = rand(-10000,10000)/10000
            R2 = rand(-10000,10000)/10000
            working = R1*R1 + R2*R2
        while(working >= 1 || working==0)
        working = sqrt(-2 * log(working) / working)
        R1 *= working
        gaussian_next = R2 * working
    return (mean + stddev * R1)
"#;
     for (text, expected) in [
         (fixture.to_owned(), true),
         (fixture.replace("        do\n", "        do ;\n"), false),
         (fixture.replace("if(gaussian_next != null)", "if(gaussian_next != null) ;"), false),
     ] {
         let db = Arc::new(QueryDb::default());
         let front = issued_original_fixture(&db, &text);
         let input = original_input(&front, "gaussian");
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let disposition = body.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = disposition? else {
                     panic!("actual Original else and do-while are available");
                 };
                 assert!(proof.belongs_to(&body));
             } else {
                 assert!(matches!(disposition, Err(BodySyntaxFailure::Operational(error)) if error.kind() == std::io::ErrorKind::Unsupported), "{text}");
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]
 fn actual_original_else_if_attaches_only_after_the_consumed_then_block() {
     let fixture = r#"
/proc/probe(character)
    var/datum/mind/M
    if(ismob(character))
        var/mob/C = character
        M = C.mind
    else if(istype(character, /datum/mind))
        M = character
    return M
"#;
     for (text, expected) in [
         (fixture.to_owned(), true),
         (fixture.replace("else if(istype(character, /datum/mind))\n        M = character",
             "else if(istype(character, /datum/mind)) M = character"), false),
         (fixture.replace("if(ismob(character))", "if(ismob(character)) ;"), false),
     ] {
         let db = Arc::new(QueryDb::default());
         let front = issued_original_fixture(&db, &text);
         let input = original_input(&front, "probe");
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let disposition = body.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = disposition? else {
                     panic!("actual Original else-if attaches to the completed block");
                 };
                 assert!(proof.belongs_to(&body));
             } else {
                 assert!(matches!(disposition, Err(BodySyntaxFailure::Operational(error)) if error.kind() == std::io::ErrorKind::Unsupported), "{text}");
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]
 fn actual_admin_attack_safe_call_consumes_only_absolute_unmodified_path_argument() {
     let fixture = r#"
#define R_ADMIN (1<<1)
#define R_MOD (1<<13)
#define ATTACK_PREFIX(text) ("<attack>" + text + "</attack>")
/proc/msg_admin_attack(text)
    var/rendered = ATTACK_PREFIX("[text]")
    for(var/client/C in GLOB.admins)
        if(check_rights_for(C, (R_ADMIN|R_MOD)))
            if(C.prefs?.read_preference(/datum/preference/toggle/show_attack_logs))
                var/msg = rendered
                to_chat(C,
                        type = "attacklog",
                        html = msg,
                        confidential = TRUE)
"#;
     for (text, expected) in [
         (fixture.to_owned(), true),
         (fixture.replace("/datum/preference/toggle/show_attack_logs", ".preference/toggle/show_attack_logs"), false),
         (fixture.replace("/datum/preference/toggle/show_attack_logs", "/datum/preference/toggle/show_attack_logs{enabled=1}"), false),
     ] {
         let db = Arc::new(QueryDb::default());
         let front = issued_original_fixture(&db, &text);
         let input = original_input(&front, "msg_admin_attack");
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let disposition = body.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = disposition? else {
                     panic!("actual safe call with absolute prefab path is available");
                 };
                 assert!(proof.belongs_to(&body));
             } else {
                 assert!(matches!(disposition, Err(BodySyntaxFailure::Operational(error)) if error.kind() == std::io::ErrorKind::Unsupported), "{text}");
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]
 fn actual_original_bare_typed_static_local_uses_issued_path() {
     use dm_tree::frontend::OriginalBodyDisposition as D;
     for (local, available) in [
         ("var/static/list/sound_cache", true),
         ("var/static/datum/list_owner/sound_cache", true),
         ("var/static/list/sound_cache[3]", false),
         ("var/static/list/sound_cache = list()", false),
     ] {
         let db = Arc::new(QueryDb::default());
         let front = issued_original_fixture(&db, &format!("/datum/list_owner\n/proc/probe()\n    {local}\n    return sound_cache\n"));
         let view = front.source_view().unwrap();
         let archive = view.archive();
         setting_syntax::with_setting_admission(&db.body_charge, |a| archive.with_current_body_checked(0, a, |current| {
             match (available, current.syntax().original_code_disposition()) {
                 (true, Ok(D::Available(grant))) => assert!(grant.belongs_to(current.syntax())),
                 (false, Err(BodySyntaxFailure::Operational(error))) => assert_eq!(error.kind(), std::io::ErrorKind::Unsupported),
                 _ => panic!("actual static local disposition differs for {local}"),
             }
             Ok(())
         })).unwrap();
     }
 }

 #[test]
 fn actual_original_static_local_and_standalone_increment_use_issued_tokens() {
     let fixture = r#"
/proc/wrapper(next)
    var/static/__f
    if(!__f)
        __f = choose(next)
    next++
    return __f
#define VERDIGRIS (__verdigris || __detect_verdigris())
#define VG_COUNT_FFI_CALL __verdigris_ffi_calls++
/proc/vg_adjust_multi_hook(...)
    var/static/__f
    if(!__f)
        __f = load_ext(VERDIGRIS, "byond:adjust_multi_hook_ffi")
    VG_COUNT_FFI_CALL
    return call_ext(__f)(arglist(args))
/proc/vg_air_watch_changed(watch, revisions)
    var/static/__f
    if(!__f)
        __f = load_ext(VERDIGRIS, "byond:air_watch_changed_ffi")
    VG_COUNT_FFI_CALL
    return call_ext(__f)(watch, revisions)
/proc/local_row()
    var/R1;var/R2;var/working
    return R1
/proc/static_initializer()
    var/static/__f = 1
    return __f
/proc/member_increment(target)
    target.next++
    return target
/proc/prefix_increment(next)
    ++next
    return next
"#;
     let db = Arc::new(QueryDb::default());
     let front = issued_original_fixture(&db, fixture);
     for (name, expected) in [("wrapper", true), ("vg_adjust_multi_hook", true), ("vg_air_watch_changed", true), ("local_row", true), ("static_initializer", false),
         ("member_increment", false), ("prefix_increment", false)]
     {
         let input = original_input(&front, name);
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let disposition = body.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = disposition? else {
                     panic!("actual Original static/increment grammar is available: {name}");
                 };
                 assert!(proof.belongs_to(&body));
             } else {
                 assert!(matches!(disposition, Err(BodySyntaxFailure::Operational(error)) if error.kind() == std::io::ErrorKind::Unsupported), "{name}");
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]
 fn actual_fast_split_stack_witness_consumes_return_slot_and_dynamic_constructor() {
     let fixture = r#"
/proc/fast_split_stack(obj/item/stack/target, amount)
    if(!target.use(amount))
        return null
    . = new target.type(target.drop_location(), amount)
"#;
     for (text, expected) in [
         (fixture.to_owned(), true),
         (fixture.replace(". = new", ". += new"), false),
         (fixture.replace("new target.type", "new target?.type"), false),
         (fixture.replace("target.drop_location(), amount", "target.drop_location(), quantity = amount"), false),
     ] {
         let db = Arc::new(QueryDb::default());
         let front = issued_original_fixture(&db, &text);
         let input = original_input(&front, "fast_split_stack");
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let disposition = body.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = disposition? else {
                     panic!("actual return-slot dynamic constructor is available");
                 };
                 assert!(proof.belongs_to(&body));
             } else {
                 assert!(matches!(disposition, Err(BodySyntaxFailure::Operational(error)) if error.kind() == std::io::ErrorKind::Unsupported), "{text}");
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]
 fn actual_original_gcd_and_mean_use_exact_arithmetic_body_witnesses() {
     let fixture = r#"
/proc/GCD(a, b)
    return b ? GCD(b, (a) % (b)) : a
/proc/Mean(...)
    var/sum = 0
    for(var/val in args)
        sum += val
    return sum / args.len
/proc/scaled(amount)
    return -(amount * 0.125)
"#;
     let db = Arc::new(QueryDb::default());
     let front = issued_original_fixture(&db, fixture);
     for name in ["GCD", "Mean", "scaled"] {
         let input = original_input(&front, name);
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = body.original_code_disposition()? else {
                 panic!("actual Original arithmetic body is available: {name}");
             };
             assert!(proof.belongs_to(&body));
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]
 fn actual_admin_intercom_dotted_statement_call_keeps_keyed_argument_scope() {
     let fixture = r#"
/proc/admin_intercom_line(message, sender, channel, speech_verb)
    GLOB.global_announcer.autosay(message, sender, channel, states = speech_verb)
"#;
     for (text, expected) in [
         (fixture.to_owned(), true),
         (fixture.replace("announcer.autosay", "announcer?.autosay"), false),
         (fixture.replace("states = speech_verb", "states = choose(state = speech_verb)"), false),
     ] {
         let db = Arc::new(QueryDb::default());
         let front = issued_original_fixture(&db, &text);
         let input = original_input(&front, "admin_intercom_line");
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let disposition = body.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = disposition? else {
                     panic!("actual dotted statement call is available");
                 };
                 assert!(proof.belongs_to(&body));
             } else {
                 assert!(matches!(disposition, Err(BodySyntaxFailure::Operational(error)) if error.kind() == std::io::ErrorKind::Unsupported), "{text}");
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]
 fn actual_original_static_returns_keep_issued_values_and_absolute_paths() {
     let fixture = r#"
/datum/choice
/proc/static_text()
    return "static value"
/proc/static_resource()
    return 'icons/probe.dmi'
/proc/static_type()
    return /datum/choice
/proc/mixed_static(choice)
    if(choice)
        return ""
    return /datum/choice
/proc/relative_type()
    return .choice
"#;
     let db = Arc::new(QueryDb::default());
     let front = issued_original_fixture(&db, fixture);
     for (name, expected) in [
         ("static_text", true), ("static_resource", true), ("static_type", true),
         ("mixed_static", true), ("relative_type", false),
     ] {
         let input = original_input(&front, name);
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let disposition = body.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = disposition? else {
                     panic!("actual static return grammar is available: {name}");
                 };
                 assert!(proof.belongs_to(&body));
             } else {
                 assert!(matches!(disposition, Err(BodySyntaxFailure::Operational(error)) if error.kind() == std::io::ErrorKind::Unsupported), "{name}");
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
     for source in [r#""static value""#, "'icons/probe.dmi'", "/datum/choice"] {
         let parsed = dm_syntax::parse_expression(source);
         assert!(parsed.diagnostics.is_empty(), "{source}: {:?}", parsed.diagnostics);
         let syntax = dm_syntax::parse(&format!("/proc/compat()\n    return {source}\n"));
         assert!(dm_syntax::parse_proc_body(&syntax.items[0]).original_grammar.is_none(), "{source}");
     }
 }

 #[test]
 fn actual_original_local_initializers_and_plain_return_slot_compose_exact_values() {
     let fixture = r#"
/proc/solve(a, b, c)
    . = list()
    var/d = b*b - 4*a*c
    var/bottom = 2*a
    if(d < 0)
        return
    var/root = sqrt(d)
    . = (-b + root) / bottom
/proc/angle(inc, dec)
    if(inc < 0)
        inc += 360
    . = inc > dec ? -dec : inc
/proc/unsupported_local(a)
    var/value = sqrt(number = a)
    return value
"#;
     let db = Arc::new(QueryDb::default());
     let front = issued_original_fixture(&db, fixture);
     for (name, expected) in [("solve", true), ("angle", true), ("unsupported_local", false)] {
         let input = original_input(&front, name);
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let disposition = body.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = disposition? else {
                     panic!("actual local and return-slot grammar is available: {name}");
                 };
                 assert!(proof.belongs_to(&body));
             } else {
                 assert!(matches!(disposition, Err(BodySyntaxFailure::Operational(error)) if error.kind() == std::io::ErrorKind::Unsupported), "{name}");
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]
 fn actual_original_for_each_subtracts_one_index_from_the_same_member() {
     let fixture = "/proc/probe(regex/admin_ranks_regex)\n    for(var/i in admin_ranks_regex.group - admin_ranks_regex.group[1])\n        return i\n    return 0\n";
     for (text, expected) in [
         (fixture.to_owned(), true),
         (fixture.replace("group - ", "group + "), false),
         (fixture.replace("group[1]", "other[1]"), false),
         (fixture.replace("group[1]", "group[2 + 1]"), false),
         (fixture.replace("var/i in", "i in"), false),
     ] {
         let db = Arc::new(QueryDb::default());
         let front = issued_original_fixture(&db, &text);
         let input = original_input(&front, "probe");
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let disposition = body.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = disposition? else {
                     panic!("actual Original ForEach member subtraction is available");
                 };
                 assert!(proof.belongs_to(&body));
             } else {
                 assert!(matches!(disposition, Err(BodySyntaxFailure::Operational(error))
                     if error.kind() == std::io::ErrorKind::Unsupported), "{text}");
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]
 fn actual_original_for_list_owns_zero_argument_call_and_member_iterable() {
     let fixture = r#"
/proc/probe(M)
    if(ticker_mode().antag_templates && ticker_mode().antag_templates.len)
        for(var/datum/antagonist/antag in ticker_mode().antag_templates)
            if(antag.is_antagonist(M))
                return 2
    return 0
"#;
     for (text, expected) in [
         (fixture.to_owned(), true),
         (fixture.replace("in ticker_mode().", "in ticker_mode(M)."), false),
         (fixture.replace("in ticker_mode().", "in ticker_mode()?."), false),
     ] {
         let db = Arc::new(QueryDb::default());
         let front = issued_original_fixture(&db, &text);
         let input = original_input(&front, "probe");
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let disposition = body.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = disposition? else {
                     panic!("actual Original ForList call-member iterable is available");
                 };
                 assert!(proof.belongs_to(&body));
             } else {
                 assert!(matches!(disposition, Err(BodySyntaxFailure::Operational(error)) if error.kind() == std::io::ErrorKind::Unsupported), "{text}");
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]
 fn actual_original_braced_assert_and_dot_accumulation_have_exact_statement_proofs() {
     let fixture = r#"
#undef ASSERT
#define ASSERT(condition, message...) \
    if (!(condition)) { \
        CRASH(assertion_message(__FILE__, __LINE__, #condition, ##message)) \
    }
/proc/solve(a, b, c)
    ASSERT(a)
    . = list()
    var/d = b*b - 4*a*c
    var/bottom = 2*a
    if(d < 0)
        return
    var/root = sqrt(d)
    . += (-b + root) / bottom
    if(!d)
        return
    . += (-b - root) / bottom
/proc/ret()
    return .
/proc/call_with_trailing_comma(a)
    return choose(a,)
/proc/call_with_interior_hole(a)
    return choose(a,,a)
/proc/two_crash_args(a)
    CRASH(a, a)
/proc/crash_as_return(a)
    return CRASH(a)
/proc/crash_as_local(a)
    var/invalid = CRASH(a)
    return invalid
"#;
     let db = Arc::new(QueryDb::default());
     let front = issued_original_fixture(&db, fixture);
     for (name, expected) in [("solve", true), ("ret", true), ("call_with_trailing_comma", true),
         ("call_with_interior_hole", false), ("two_crash_args", false),
         ("crash_as_return", false), ("crash_as_local", false)]
     {
         let input = original_input(&front, name);
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let disposition = body.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = disposition? else {
                     panic!("actual Original crash/dot grammar is available: {name}");
                 };
                 assert!(proof.belongs_to(&body));
             } else {
                 assert!(matches!(disposition, Err(BodySyntaxFailure::Operational(error)) if error.kind() == std::io::ErrorKind::Unsupported), "{name}");
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]
 fn actual_original_nested_if_tail_proves_each_close_before_outer_else() {
     let fixture = r#"
/proc/probe(a, b, c)
    if(!a)
        if(!b)
            return 1
        else if(!c)
            return 2
        else
            if(!a)
                return 3
    else
        return 4
"#;
     for (text, expected) in [
         (fixture.to_owned(), true),
         (fixture.replace("        else\n            if(!a)\n                return 3", ""), true),
         (fixture.replace("    else\n        return 4", "    else return 4"), false),
         (fixture.replace("            if(!a)\n                return 3", "            while(!a)\n                return 3"), false),
     ] {
         let db = Arc::new(QueryDb::default());
         let front = issued_original_fixture(&db, &text);
         let input = original_input(&front, "probe");
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let disposition = body.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = disposition? else {
                     panic!("actual Original nested tail links to the outer else: {text}");
                 };
                 assert!(proof.belongs_to(&body));
             } else {
                 assert!(matches!(disposition, Err(BodySyntaxFailure::Operational(error))
                     if error.kind() == std::io::ErrorKind::Unsupported), "{text}");
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]
 fn actual_original_inline_if_consumes_one_return_without_an_else() {
     let fixture = concat!(
         "#define INVESTIGATE_DIR \"data/investigate/\"\n",
         "/proc/investigate_reset()\n",
         "    if(fdel(INVESTIGATE_DIR))\treturn 1\n",
         "    return 0\n",
     );
     for (text, expected) in [
         (fixture.to_owned(), true),
         (fixture.replace("\treturn 1", "\treturn"), true),
         (fixture.replace("\treturn 1", "\tfdel(INVESTIGATE_DIR)"), false),
         (fixture.replace("\treturn 1\n", "\treturn 1\n    else\n        return 2\n"), false),
     ] {
         let db = Arc::new(QueryDb::default());
         let front = issued_original_fixture(&db, &text);
         let input = original_input(&front, "investigate_reset");
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let disposition = body.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = disposition? else {
                     panic!("actual Original inline return is available: {text}");
                 };
                 assert!(proof.belongs_to(&body));
             } else {
                 assert!(matches!(disposition, Err(BodySyntaxFailure::Operational(error))
                     if error.kind() == std::io::ErrorKind::Unsupported), "{text}");
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]
 fn actual_original_control_clause_does_not_cut_a_matching_keyword_prefix() {
     let fixture = "/proc/probe(i, f)\n    if(i)\n        return f\n    if(f)\n        return i\n    return 0\n";
     let db = Arc::new(QueryDb::default());
     let front = issued_original_fixture(&db, fixture);
     let input = original_input(&front, "probe");
     let product = db.syntax_product_checked(&input).unwrap();
     setting_syntax::with_setting_admission(&db.body_charge, |admission| {
         let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
         let dm_tree::frontend::OriginalBodyDisposition::Available(proof) =
             body.original_code_disposition()?
         else {
             panic!("both controls must use the actual clause occurrences");
         };
         assert!(proof.belongs_to(&body));
         Ok::<(), BodySyntaxFailure>(())
     }).unwrap();
 }

 #[test]
 fn actual_original_plain_index_reads_and_writes_keep_exact_root_roles() {
     use dm_tree::frontend::OriginalBodyDisposition as D;
     for (body, available) in [
         // Root return, interpolation, and local initializer.
         ("return target_list[list_length]", true),
         (r#"return "[input[1]]""#, true),
         ("var/result = listfrom[listfrom.len]\n    return result", true),
         ("var/result = sound_cache[file_path]\n    return result", true),
         // Plain indexed stores, including a distinct indexed RHS.
         ("L[key] = temp[key]\n    return L", true),
         ("Q[x.name] = x\n    return Q", true),
         // Keep unqualified bracket kinds, call receivers, and evaluated keys out.
         ("return target_list?[list_length]", false),
         ("return get_list()[list_length]", false),
         ("return target_list[object:key]", false),
         ("return target_list[object?.key]", false),
         ("return target_list[list_length + 1]", false),
         ("L[key][list_length] = x\n    return L", false),
         ("Q[x.name] += x\n    return Q", false),
     ] {
         let db = Arc::new(QueryDb::default());
         let front = issued_original_fixture(&db, &format!("/proc/probe(target_list, list_length, input, listfrom, sound_cache, file_path, L, key, temp, Q, x, object)\n    {body}\n"));
         let view = front.source_view().unwrap();
         let archive = view.archive();
         setting_syntax::with_setting_admission(&db.body_charge, |a| archive.with_current_body_checked(0, a, |current| {
             match (available, current.syntax().original_code_disposition()) {
                 (true, Ok(D::Available(grant))) => assert!(grant.belongs_to(current.syntax())),
                 (false, Err(BodySyntaxFailure::Operational(error))) => assert_eq!(error.kind(), std::io::ErrorKind::Unsupported),
                 _ => panic!("actual index disposition differs for {body}"),
             }
             Ok(())
         })).unwrap();
     }
 }

 #[test]
 fn actual_original_positional_dotted_statement_owns_the_same_call_proof() {
     let fixture = "/proc/probe(i, txt_rank, count, previous_rank)\n    if(i)\n        txt_rank.process_keyword(i, count, previous_rank)\n";
     for (text, expected) in [
         (fixture.to_owned(), true),
         (fixture.replace("txt_rank.process_keyword", "txt_rank.child.process_keyword"), true),
         (fixture.replace("txt_rank.process_keyword", "txt_rank?.process_keyword"), false),
         (fixture.replace("txt_rank.process_keyword", "txt_rank:process_keyword"), false),
         (fixture.replace("txt_rank.process_keyword", "get_rank().process_keyword"), false),
     ] {
         let db = Arc::new(QueryDb::default());
         let front = issued_original_fixture(&db, &text);
         let input = original_input(&front, "probe");
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let disposition = body.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = disposition? else {
                     panic!("actual Original positional dot call is available: {text}");
                 };
                 assert!(proof.belongs_to(&body));
             } else {
                 assert!(matches!(disposition, Err(BodySyntaxFailure::Operational(error))
                     if error.kind() == std::io::ErrorKind::Unsupported), "{text}");
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 fn actual_original_backup_rank_new_reads_exact_nested_string_indices() {
     let fixture = r#"
/proc/probe(list/json, J)
    var/datum/admin_rank/json_rank = new("[J]", "rank_backup", json["ranks"]["[J]"]["include rights"], json["ranks"]["[J]"]["exclude rights"], json["ranks"]["[J]"]["can edit rights"])
    return json_rank
"#;
     for (text, expected) in [
         (fixture.to_owned(), true),
         (fixture.replace(r#"["include rights"]"#, r#"["include rights"]["extra"]"#), false),
         (fixture.replace(r#"["[J]"]["include rights"]"#, r#"["[J + 1]"]["include rights"]"#), false),
         (fixture.replace(r#"["include rights"]"#, "[1]"), false),
         (fixture.replace(r#"json["ranks"]"#, r#"get_json()["ranks"]"#), false),
         (fixture.replace(r#"["include rights"]"#, r#"?["include rights"]"#), false),
     ] {
         let db = Arc::new(QueryDb::default());
         let front = issued_original_fixture(&db, &text);
         let input = original_input(&front, "probe");
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let disposition = body.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = disposition? else {
                     panic!("actual Original backup rank reads are available");
                 };
                 assert!(proof.belongs_to(&body));
             } else {
                 assert!(matches!(disposition, Err(BodySyntaxFailure::Operational(error))
                     if error.kind() == std::io::ErrorKind::Unsupported), "{text}");
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]
 fn actual_original_bare_input_and_unweighted_pick_keep_distinct_primitive_syntax() {
     let fixture = r#"
/proc/input_value(list/input)
    return length(input) + input.len
/proc/pick_list(list/list)
    return pick(list)
/proc/pick_listfrom(list/listfrom)
    var/picked = pick(listfrom)
    return picked
/proc/pick_weighted(list/list)
    return pick(2;list)
/proc/pick_multiple(list/list)
    return pick(list, 1)
/proc/pick_trailing(list/list)
    return pick(list,)
/proc/pick_keyword(list/list)
    return pick(choice = list)
/proc/input_primitive()
    return input() as text
"#;
     let db = Arc::new(QueryDb::default());
     let front = issued_original_fixture(&db, fixture);
     for (name, expected) in [
         ("input_value", true), ("pick_list", true), ("pick_listfrom", true),
         ("pick_weighted", false), ("pick_multiple", false), ("pick_trailing", false),
         ("pick_keyword", false), ("input_primitive", false),
     ] {
         let input = original_input(&front, name);
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let disposition = body.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = disposition? else {
                     panic!("actual Original input/pick proof is available: {name}");
                 };
                 assert!(proof.belongs_to(&body));
             } else {
                 assert!(matches!(disposition, Err(BodySyntaxFailure::Operational(error))
                     if error.kind() == std::io::ErrorKind::Unsupported), "{name}");
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]
 fn actual_original_implicit_constructor_consumes_exact_positional_children() {
     let fixture = r#"
/proc/probe()
    var/regex/admin_ranks_regex = new(@"^Name\s*=\s*(.+?)\s*\n+Include\s*=\s*([\l @]*?)\s*\n+Exclude\s*=\s*([\l @]*?)\s*\n+Edit\s*=\s*([\l @]*?)\s*\n*$", "gm")
    var/datum/admin_rank/txt_rank = new(admin_ranks_regex.group[1], "rank_txt")
    return txt_rank
"#;
     for (text, expected) in [
         (fixture.to_owned(), true),
         (fixture.replace(", \"gm\")", ", 2)"), true),
         (fixture.replace("admin_ranks_regex.group[1], \"rank_txt\"", ""), true),
         (fixture.replace(", \"rank_txt\")", ", \"rank_txt\",)"), false),
         (fixture.replace(", \"rank_txt\")", ", name = \"rank_txt\")"), false),
         (fixture.replace("admin_ranks_regex.group[1], \"rank_txt\"", &vec!["1"; 17].join(", ")), false),
         (fixture.replace(", \"gm\")", ", , \"gm\")"), false),
         (fixture.replace("= new(", "= new /regex("), false),
     ] {
         let db = Arc::new(QueryDb::default());
         let front = issued_original_fixture(&db, &text);
         let input = original_input(&front, "probe");
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let disposition = body.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = disposition? else {
                     panic!("actual Original implicit positional construction is available");
                 };
                 assert!(proof.belongs_to(&body));
             } else {
                 assert!(matches!(disposition, Err(BodySyntaxFailure::Operational(error))
                     if error.kind() == std::io::ErrorKind::Unsupported), "{text}");
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]
 fn actual_original_initialized_for_range_uses_the_authored_equals_separator() {
     let fixture = "/proc/probe(uses_charge)\n    for(var/i = 1 to uses_charge)\n        return i\n    return 0\n";
     for (text, expected) in [
         (fixture.to_owned(), true),
         (fixture.replace("var/i = 1", "i=1"), false),
         (fixture.replace("var/i = 1", "var/num/i=1"), false),
         (fixture.replace("1 to uses_charge)", "1 to uses_charge step 2)"), false),
         (fixture.replace("1 to uses_charge)", "1; uses_charge; i++)"), false),
     ] {
         let db = Arc::new(QueryDb::default());
         let front = issued_original_fixture(&db, &text);
         let input = original_input(&front, "probe");
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let disposition = body.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = disposition? else {
                     panic!("actual Original initialized range is available");
                 };
                 assert!(proof.belongs_to(&body));
             } else {
                 assert!(matches!(disposition, Err(BodySyntaxFailure::Operational(error))
                     if error.kind() == std::io::ErrorKind::Unsupported), "{text}");
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]
 fn actual_original_for_range_authenticates_declared_binding_and_both_bounds() {
     let fixture = r#"
/proc/probe(x1, x2, increments)
    for(var/i in 1 to increments)
        return i
    for(var/j in min(x1, x2) to max(x1, x2))
        return j
    return 0
"#;
     for (text, expected) in [
         (fixture.to_owned(), true),
         (fixture.replace("var/i in 1", "i in 1"), false),
         (fixture.replace("var/i in 1", "var/num/i in 1"), false),
         (fixture.replace("to increments)", "to increments step 2)"), false),
         (fixture.replace("    for(var/i in 1 to increments)\n        return i", "    for(var/i in 1 to increments) return i"), false),
     ] {
         let db = Arc::new(QueryDb::default());
         let front = issued_original_fixture(&db, &text);
         let input = original_input(&front, "probe");
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let disposition = body.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = disposition? else {
                     panic!("actual Original declared ForRange is available");
                 };
                 assert!(proof.belongs_to(&body));
             } else {
                 assert!(matches!(disposition, Err(BodySyntaxFailure::Operational(error))
                     if error.kind() == std::io::ErrorKind::Unsupported), "{text}");
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]
 fn actual_original_classic_for_uses_matching_separators_and_authored_parts() {
     let fixture = r#"
#define LAZYLEN(L) length(L)
/proc/probe(keys, i)
    for(i = 1, i <= LAZYLEN(keys), i++)
        return i
    return 0
"#;
     for (text, expected) in [
         (fixture.to_owned(), true),
         (fixture.replace("1, i <= LAZYLEN(keys),", "1; i <= LAZYLEN(keys);"), true),
         (fixture.replace("1, i <=", "1; i <="), false),
         (fixture.replace(", i++)", ", i = i + 1)"), false),
         (fixture.replace("for(i = 1", "for(var/i = 1"), true),
         (fixture.replace("for(i = 1", "for(var/num/i = 1"), false),
         (fixture.replace("i++)", "++i)"), true),
         (fixture.replace("i++)", "--i)"), false),
         (fixture.replace("i++)", "++i.field)"), false),
         ("/proc/probe(list/L)
    for(var/i=1; i<L.len; i++)
        L.Swap(i, rand(i,L.len))
    return L
".to_owned(), true),
         ("/proc/probe(list/L)
    for(var/i=1, i<L.len, ++i)
        L.Swap(i,rand(i,L.len))
".to_owned(), true),
         (fixture.replace("i++)\n        return i", "i++) return i"), false),
     ] {
         let db = Arc::new(QueryDb::default());
         let front = issued_original_fixture(&db, &text);
         let input = original_input(&front, "probe");
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let disposition = body.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = disposition? else {
                     panic!("actual Original classic ForLoop is available: {text}");
                 };
                 assert!(proof.belongs_to(&body));
             } else {
                 assert!(matches!(disposition, Err(BodySyntaxFailure::Operational(error))
                     if error.kind() == std::io::ErrorKind::Unsupported), "{text}");
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]
 fn actual_original_plain_additive_and_postfix_update_statements_stay_statement_only() {
     let fixture = r#"
/proc/probe(angle, pixel_x, pixel_y, new_x, new_y)
    pixel_x += sin(angle)+16*sin(angle)*2
    pixel_y -= cos(angle)+16*cos(angle)*2
    new_x++
    new_y--
    return 0
"#;
     for (text, expected) in [
         (fixture.to_owned(), true),
         (fixture.replace("pixel_x +=", "pixel_x *="), false),
         (fixture.replace("pixel_x +=", "return pixel_x +="), false),
         (fixture.replace("new_y--", "return new_y--"), false),
         (fixture.replace("new_y--", "--new_y"), false),
         (fixture.replace("new_y--", "new_y.field--"), false),
     ] {
         let db = Arc::new(QueryDb::default());
         let front = issued_original_fixture(&db, &text);
         let input = original_input(&front, "probe");
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let disposition = body.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = disposition? else {
                     panic!("actual Original updates have a statement witness");
                 };
                 assert!(proof.belongs_to(&body));
             } else {
                 assert!(matches!(disposition, Err(BodySyntaxFailure::Operational(error))
                     if error.kind() == std::io::ErrorKind::Unsupported), "{text}");
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]
 fn actual_original_coordinate_locate_requires_three_positional_arguments() {
     let fixture = "/proc/probe(x, y, turf/starting)\n    return locate(x, y, starting.z)\n";
     for (text, expected) in [
         (fixture.to_owned(), true),
         (fixture.replace("y, starting.z", "y"), false),
         (fixture.replace("y, starting.z", "y, starting.z, x"), false),
         (fixture.replace("y, starting.z", ", starting.z"), false),
         (fixture.replace("y, starting.z", "y, z = starting.z"), false),
         (fixture.replace("starting.z)", "starting.z,)"), false),
     ] {
         let db = Arc::new(QueryDb::default());
         let front = issued_original_fixture(&db, &text);
         let input = original_input(&front, "probe");
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let disposition = body.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = disposition? else {
                     panic!("actual Original coordinate locate is available");
                 };
                 assert!(proof.belongs_to(&body));
             } else {
                 assert!(matches!(disposition, Err(BodySyntaxFailure::Operational(error))
                     if error.kind() == std::io::ErrorKind::Unsupported), "{text}");
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]
 fn actual_original_continue_uses_the_innermost_authenticated_loop() {
     let fixture = r#"
#define QDELETED(X) (isnull(X) || X.gc_destroyed)
/proc/probe(txt_rank)
    while(txt_rank)
        if(QDELETED(txt_rank))
            continue
        if(QDELETED(txt_rank)) continue
        return 1
    return 0
"#;
     for (text, expected) in [
         (fixture.to_owned(), true),
         (fixture.replace("if(QDELETED(txt_rank)) continue", "if(QDELETED(txt_rank)) continue target"), false),
         (fixture.replace("if(QDELETED(txt_rank)) continue", "if(QDELETED(txt_rank)); continue"), false),
         (fixture.replace("if(QDELETED(txt_rank)) continue", "do\n            continue\n        while(txt_rank)"), false),
         (fixture.replace("if(QDELETED(txt_rank)) continue", "for(var/i in 1 to 2)\n            continue"), false),
     ] {
         let db = Arc::new(QueryDb::default());
         let front = issued_original_fixture(&db, &text);
         let input = original_input(&front, "probe");
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let disposition = body.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = disposition? else {
                     panic!("actual Original continue in while is available");
                 };
                 assert!(proof.belongs_to(&body));
             } else {
                 assert!(matches!(disposition, Err(BodySyntaxFailure::Operational(error))
                     if error.kind() == std::io::ErrorKind::Unsupported), "{text}");
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]
 fn actual_original_negated_positional_stack_call_already_has_a_witness() {
     let fixture = r#"
/obj/item/stack/proc/use(used)
    if(!can_use(used))
        return 0
    return 1
/obj/item/stack/proc/can_use(used)
    return used
"#;
     let db = Arc::new(QueryDb::default());
     let front = issued_original_fixture(&db, fixture);
     let input = original_input(&front, "use");
     let product = db.syntax_product_checked(&input).unwrap();
     setting_syntax::with_setting_admission(&db.body_charge, |admission| {
         let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
         let dm_tree::frontend::OriginalBodyDisposition::Available(proof) =
             body.original_code_disposition()?
         else {
             panic!("the exact stack condition must use the existing Original witness");
         };
         assert!(proof.belongs_to(&body));
         Ok::<(), BodySyntaxFailure>(())
     }).unwrap();
 }

 #[test]
 fn actual_original_offset_indices_preserve_all_seven_dispatch_arguments() {
     let fixture = r#"
/proc/probe(obj/machinery/power/apc/target, list/flat, p)
    target.on_apc_report(flat[p + 0], flat[p + 1], flat[p + 2], flat[p + 3], flat[p + 4], flat[p + 5], flat[p + 6])
    return 1
"#;
     for (text, expected) in [
         (fixture.to_owned(), true),
         (fixture.replace("p + 6", "p - 6"), false),
         (fixture.replace("p + 6", "p + offset"), false),
         (fixture.replace("p + 6", "get_offset() + 6"), false),
         (fixture.replace("flat[p + 6]", "flat?[p + 6]"), false),
     ] {
         let db = Arc::new(QueryDb::default());
         let front = issued_original_fixture(&db, &text);
         let input = original_input(&front, "probe");
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let disposition = body.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = disposition? else {
                     panic!("actual Original dispatch argument index proof is available");
                 };
                 assert!(proof.belongs_to(&body));
             } else {
                 assert!(matches!(disposition, Err(BodySyntaxFailure::Operational(error))
                     if error.kind() == std::io::ErrorKind::Unsupported), "{text}");
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]
 fn actual_original_typecache_exclusion_not_consumes_one_plain_index_operand() {
     let fixture = r#"
/proc/probe(list/atoms, list/typecache_include, list/typecache_exclude)
    . = list()
    for(var/atom/A as anything in atoms)
        if(typecache_include[A.type] && !typecache_exclude[A.type])
            . += A
"#;
     for (text, expected) in [
         (fixture.to_owned(), true),
         (fixture.replace("!typecache_exclude[A.type]", "!typecache_exclude[A]"), true),
         (fixture.replace("!typecache_exclude[A.type]", "-typecache_exclude[A.type]"), false),
         (fixture.replace("!typecache_exclude[A.type]", "!typecache_exclude[A:type]"), false),
         (fixture.replace("!typecache_exclude[A.type]", "!typecache_exclude[lookup(A)]"), false),
         (fixture.replace("!typecache_exclude[A.type]", "!typecache_exclude[A.type][A]"), false),
         (fixture.replace("!typecache_exclude[A.type]", "!typecache_exclude[++A]"), false),
     ] {
         let db = Arc::new(QueryDb::default());
         let front = issued_original_fixture(&db, &text);
         let input = original_input(&front, "probe");
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let disposition = body.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = disposition? else {
                     panic!("actual Original typecache exclusion must be available");
                 };
                 assert!(proof.belongs_to(&body));
                 let parsed = product.parsed().unwrap().statement_storage().parsed();
                 let dm_syntax::StatementKind::For { body, .. } = &parsed.statements[1].kind
                     else { panic!("actual authored atom loop"); };
                 let dm_syntax::StatementKind::If { condition, .. } = &body[0].kind
                     else { panic!("actual authored filter condition"); };
                 assert!(matches!(&condition.kind, dm_syntax::ExprKind::Binary { op, lhs, rhs }
                     if op == "&&" && matches!(&lhs.kind, dm_syntax::ExprKind::Index { .. })
                         && matches!(&rhs.kind, dm_syntax::ExprKind::Unary { op, value }
                             if op == "!" && matches!(&value.kind, dm_syntax::ExprKind::Index { .. }))));
             } else {
                 assert!(matches!(disposition, Err(BodySyntaxFailure::Operational(error))
                     if error.kind() == std::io::ErrorKind::Unsupported), "{text}");
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]
 fn actual_original_as_anything_keeps_the_authored_atom_or_list_binding() {
     let fixture = r#"
/proc/probe(list/atoms, list/typecache)
    . = list()
    for(var/atom/A as anything in atoms)
        if(typecache[A.type])
            . += A
    for(var/list/row as anything in atoms)
        if(row)
            . += row
"#;
     for (text, expected) in [
         (fixture.to_owned(), true),
         (fixture.replace("var/atom/A", "var/datum/A"), true),
         (fixture.replace("var/atom/A", "var/atom/movable/A"), true),
         (fixture.replace("A as anything", "A as obj"), false),
         (fixture.replace("anything in atoms", "anything in atoms.values"), true),
     ] {
         let db = Arc::new(QueryDb::default());
         let front = issued_original_fixture(&db, &text);
         let input = original_input(&front, "probe");
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let disposition = body.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = disposition? else {
                     panic!("actual Original atom and list bindings are available");
                 };
                 assert!(proof.belongs_to(&body));
                 let parsed = product.parsed().unwrap().statement_storage().parsed();
                 let entries = parsed.local_variables.entries().unwrap();
                 assert_eq!(entries.iter().filter(|entry|
                     entry.source_kind == dm_syntax::LocalSourceKind::ForBinding).count(), 2);
             } else {
                 assert!(matches!(disposition, Err(BodySyntaxFailure::Operational(error))
                     if error.kind() == std::io::ErrorKind::Unsupported), "{text}");
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }


 #[test]
 fn actual_original_typed_anything_for_keeps_real_local_type_and_name_spans() {
     let fixture = "\
/var/datum/controller/global_vars/GLOB\n\
/datum/controller/global_vars/var/list/admin_ranks\n\
/datum/admin_rank/var/name\n\
/proc/probe(list/ranks)\n\
    for(var/datum/admin_rank/rank as anything in GLOB.admin_ranks)\n\
        ranks += rank\n\
    return ranks\n";
     for (text, expected) in [
         (fixture.to_owned(), true),
         (fixture.replace("datum/admin_rank/rank", "atom/movable/rank"), true),
         (fixture.replace("datum/admin_rank/rank", "datum/rank"), true),
         (fixture.replace("GLOB.admin_ranks", "ranks"), true),
         (fixture.replace("var/datum/admin_rank/rank", "var/static/datum/admin_rank/rank"), false),
         (fixture.replace("var/datum/admin_rank/rank", "var/tmp/datum/admin_rank/rank"), false),
         (fixture.replace("var/datum/admin_rank/rank", "var/SpacemanDMM_private/datum/admin_rank/rank"), false),
         (fixture.replace("rank as anything", "rank[] as anything"), false),
         (fixture.replace("rank as anything", "rank as obj"), false),
         (fixture.replace("GLOB.admin_ranks)", "GLOB?.admin_ranks)"), false),
         (fixture.replace("GLOB.admin_ranks)", "GLOB:admin_ranks)"), false),
         (fixture.replace("GLOB.admin_ranks)", "GLOB.admin_ranks.extra)"), false),
         (fixture.replace("GLOB.admin_ranks)", "get_ranks())"), false),
     ] {
         let db = Arc::new(QueryDb::default());
         let front = issued_original_fixture(&db, &text);
         let input = original_input(&front, "probe");
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = body.original_code_disposition()? else {
                     panic!("typed Original as-anything binding must be available");
                 };
                 assert!(proof.belongs_to(&body));
                 let storage = product.parsed().unwrap().statement_storage();
                 let entry = storage.parsed().local_variables.entries().unwrap().iter().find(|entry|
                     entry.source_kind == dm_syntax::LocalSourceKind::ForBinding).unwrap();
                 let view = front.source_view().unwrap();
                 let source = view.expanded_text();
                 let name = body.projection().span(entry.name).unwrap();
                 assert_eq!(&source[name.range()], "rank");
                 let types = entry.type_components.iter().map(|span| {
                     let span = body.projection().span(*span).unwrap();
                     &source[span.range()]
                 }).collect::<Vec<_>>();
                 let expected_path = text.split_once("    for(var/").unwrap().1.split_once("/rank as anything").unwrap().0;
                 assert_eq!(types.join("/"), expected_path);
                 assert_eq!(entry.source_modifiers, 0);
                 assert!(!entry.array_suffix);
             } else {
                 assert!(matches!(body.original_code_disposition(), Err(BodySyntaxFailure::Operational(error))
                     if error.kind() == std::io::ErrorKind::Unsupported), "{text}");
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]
 fn actual_original_admin_ranks_function_has_typed_anything_body_receipt() {
     let authored = include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../../code/content/admin/admin_ranks.dm"));
     let authored = authored.replace("\r\n", "\n");
     let start = authored.find("/proc/ranks_from_rank_name(rank_name)\n").unwrap();
     let tail = &authored[start..];
     let end = tail.find("\n/proc/join_admin_ranks(").unwrap();
     let source = format!("/var/datum/controller/global_vars/GLOB\n/datum/controller/global_vars/var/list/admin_ranks\n/datum/admin_rank/var/name\n{}", &tail[..end]);
     assert!(source.contains("for (var/datum/admin_rank/rank as anything in GLOB.admin_ranks)"));
     let db = Arc::new(QueryDb::default());
     let front = issued_original_fixture(&db, &source);
     let input = original_input(&front, "ranks_from_rank_name");
     let product = db.syntax_product_checked(&input).unwrap();
     setting_syntax::with_setting_admission(&db.body_charge, |admission| {
         let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
         let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = body.original_code_disposition()? else {
             panic!("actual admin-rank function must have complete native body receipt");
         };
         assert!(proof.belongs_to(&body));
         Ok::<(), BodySyntaxFailure>(())
     }).unwrap();
 }

 #[test]
 fn actual_original_list_as_anything_and_nested_bare_break_authenticate_own_loops() {
     let fixture = r#"
/proc/probe(list/rank_rows, list/admin_ranks)
    for(var/list/row as anything in rank_rows)
        var/rank_name = row[1]
        for(var/datum/admin_rank/R in admin_ranks)
            if(R.name == rank_name)
                break
    return 0
"#;
     for (text, expected) in [
         (fixture.to_owned(), true),
         (fixture.replace("as anything", "as text"), false),
         (fixture.replace("in rank_rows", "in rank_rows.list"), false),
         (fixture.replace("var/list/row", "var/row"), false),
         (fixture.replace("                break", "                break target"), false),
         (fixture.replace("        for(var/datum/admin_rank/R in admin_ranks)", "        for(var/R in 1 to 2)"), false),
         ("/proc/probe()\n    break\n".to_owned(), false),
     ] {
         let db = Arc::new(QueryDb::default());
         let front = issued_original_fixture(&db, &text);
         let input = original_input(&front, "probe");
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let disposition = body.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = disposition? else {
                     panic!("actual Original as-anything and break are available");
                 };
                 assert!(proof.belongs_to(&body));
                 let statements = &product.parsed().unwrap().statement_storage().parsed().statements;
                 let dm_syntax::StatementKind::For {
                     control: dm_syntax::ForControl::Each { binding, .. }, ..
                 } = &statements[0].kind else {
                     panic!("actual loop must declare its iteration local");
                 };
                 assert_eq!(binding, "var/list/row");
             } else {
                 assert!(matches!(disposition, Err(BodySyntaxFailure::Operational(error))
                     if error.kind() == std::io::ErrorKind::Unsupported), "{text}");
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]
 fn actual_original_for_each_accepts_only_the_witnessed_bare_string_index() {
     let fixture = r#"
/proc/probe(list/json, key)
    for(var/J in json["ranks"])
        if(J)
            continue
        return J
    return 0
"#;
     for (text, expected) in [
         (fixture.to_owned(), true),
         (fixture.replace(r#"json["ranks"]"#, "json[1]"), false),
         (fixture.replace(r#"json["ranks"]"#, "json[key]"), false),
         (fixture.replace(r#"json["ranks"]"#, r#"json?["ranks"]"#), false),
         (fixture.replace(r#"json["ranks"]"#, r#"json["rank keys"]"#), false),
         (fixture.replace(r#"json["ranks"]"#, r#"json["ranks"]["next"]"#), false),
         (fixture.replace("var/J in", "J in"), false),
     ] {
         let db = Arc::new(QueryDb::default());
         let front = issued_original_fixture(&db, &text);
         let input = original_input(&front, "probe");
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let disposition = body.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = disposition? else {
                     panic!("actual Original bare string-index iterable is available");
                 };
                 assert!(proof.belongs_to(&body));
             } else {
                 assert!(matches!(disposition, Err(BodySyntaxFailure::Operational(error))
                     if error.kind() == std::io::ErrorKind::Unsupported), "{text}");
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]
 fn actual_original_cooldown_macro_group_retains_its_statement_assignment() {
     let fixture = r#"
#define SECONDS *10
#define CLOCK_WORLD 0
#define TIME_NOW(clock, owner...) ((clock) ? own_clock_now(owner) : world.time)
#define COOLDOWN_START(cd_source, cd_index, cd_time) (cd_source.cd_index = TIME_NOW(CLOCK_WORLD) + (cd_time))
#define APC_REPORT_LOG_INTERVAL (30 SECONDS)
/obj/machinery/power/apc/proc/probe()
    COOLDOWN_START(src, report_log_cooldown, APC_REPORT_LOG_INTERVAL)
    return 0
"#;
     for (text, expected) in [
         (fixture.to_owned(), true),
         (fixture.replace("    COOLDOWN_START(", "    return COOLDOWN_START("), false),
         (fixture.replace("cd_source.cd_index =", "cd_source.cd_index +="), false),
         (fixture.replace("cd_source.cd_index =", "cd_source:cd_index ="), false),
         (fixture.replace("cd_source.cd_index =", "cd_source.cd_index[1] ="), false),
     ] {
         let db = Arc::new(QueryDb::default());
         let front = issued_original_fixture(&db, &text);
         let input = original_input(&front, "probe");
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let disposition = body.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = disposition? else {
                     panic!("actual Original cooldown group is available");
                 };
                 assert!(proof.belongs_to(&body));
                 let statements = product.parsed().unwrap().statement_storage().parsed();
                 assert!(matches!(&statements.statements[0].kind,
                     dm_syntax::StatementKind::Expression(value) if matches!(&value.kind, dm_syntax::ExprKind::Group(_))));
             } else {
                 assert!(matches!(disposition, Err(BodySyntaxFailure::Operational(error))
                     if error.kind() == std::io::ErrorKind::Unsupported), "{text}");
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]
 fn actual_original_length_input_switch_authenticates_inline_returns() {
     let fixture = "/proc/probe(list/input)\n    switch(length(input))\n        if(0) return 0\n        if(1) return 1\n        else return 2\n";
     for (text, expected) in [
         (fixture.to_owned(), true),
         (fixture.replace("length(input)", "rand(0, 1)"), false),
         (fixture.replace("if(0)", "if(0, 1)"), false),
         (fixture.replace("return 0", "return"), false),
         (fixture.replace("length(input)", "input"), false),
     ] {
         let db = Arc::new(QueryDb::default());
         let front = issued_original_fixture(&db, &text);
         let input = original_input(&front, "probe");
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let disposition = body.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = disposition? else {
                     panic!("actual Original inline switch is available");
                 };
                 assert!(proof.belongs_to(&body));
                 let parsed = product.parsed().unwrap().statement_storage().parsed();
                 let dm_syntax::StatementKind::Switch { cases, else_branch, .. } =
                     &parsed.statements[0].kind else { panic!("actual inline switch"); };
                 for statement in cases.iter().flat_map(|case| case.body.iter()).chain(else_branch) {
                     assert_eq!(statement.span.start, statement.header_span.start);
                     assert!(statement.raw_header.starts_with("return "));
                 }
             } else {
                 assert!(matches!(disposition, Err(BodySyntaxFailure::Operational(error))
                     if error.kind() == std::io::ErrorKind::Unsupported), "{text}");
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }


 #[test]
 fn actual_original_english_list_keeps_all_interpolation_children_and_primitive_index_key() {
     let file = include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../../code/host/helpers/_lists.dm"));
     let file = file.replace("\r\n", "\n");
     let start = file.find("/proc/english_list(").unwrap();
     let tail = &file[start..];
     let end = tail.find("\n// Determiner constants").unwrap();
     let authored = &tail[..end];
     assert!(authored.contains("[jointext(input, comma_text, 1, -1)][final_comma_text][and_text][input[input.len]]"));
     for (source, expected) in [
         (authored.to_owned(), true),
         (authored.replace("input[input.len]", "input[input?.len]"), false),
         (authored.replace("input[input.len]", "input[input.len.extra]"), false),
         (authored.replace("input[input.len]", "input[length(input)]"), false),
     ] {
         let db = Arc::new(QueryDb::default());
         let front = issued_original_fixture(&db, &source);
         let input = original_input(&front, "english_list");
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let disposition = body.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = disposition? else {
                     panic!("the actual english_list interpolation must be available");
                 };
                 assert!(proof.belongs_to(&body));
                 let storage = product.parsed().unwrap().statement_storage();
                 let dm_syntax::StatementKind::Switch { else_branch, .. } = &storage.parsed().statements[0].kind
                     else { panic!("actual length switch"); };
                 let dm_syntax::StatementKind::Return(Some(expression)) = &else_branch[0].kind
                     else { panic!("actual default return"); };
                 let dm_syntax::ExprKind::Literal(literal) = &expression.kind
                     else { panic!("actual interpolation owner"); };
                 let parts = literal.prepared_syntax_parts().unwrap().unwrap().unwrap();
                 assert_eq!(parts.expressions.len(), 4);
                 let dm_syntax::ExprKind::Index { object, index } = &parts.expressions[3].kind
                     else { panic!("same last interpolation index"); };
                 assert!(matches!(&object.kind, dm_syntax::ExprKind::Ident(name) if name == "input"));
                 assert!(matches!(&index.kind, dm_syntax::ExprKind::Member { object, selector, via_colon: false }
                     if selector == "len" && matches!(&object.kind, dm_syntax::ExprKind::Ident(name) if name == "input")));
             } else {
                 assert!(!matches!(disposition, Ok(dm_tree::frontend::OriginalBodyDisposition::Available(_))), "{source}");
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]
 fn actual_original_else_if_chain_authenticates_every_link() {
     let fixture = r#"
/proc/probe(a, b)
    if(!a)
        return 1
    else if(!b)
        return 2
    else
        return 3
"#;
     for (text, expected) in [
         (fixture.to_owned(), true),
         (fixture.replace("else if(!b)", "else if(b)"), true),
         (fixture.replace("    else\n        return 3", "    else return 3"), false),
         (fixture.replace("else if(!b)", "else if(b)")
             .replace("    else\n        return 3", "    else return 3"), false),
         (fixture.replace("    else if(!b)\n        return 2", "    else if(!b) return 2"), false),
     ] {
         let db = Arc::new(QueryDb::default());
         let front = issued_original_fixture(&db, &text);
         let input = original_input(&front, "probe");
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let disposition = body.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = disposition? else {
                     panic!("actual Original linked else-if chain is available: {text}");
                 };
                 assert!(proof.belongs_to(&body));
             } else {
                 assert!(matches!(disposition, Err(BodySyntaxFailure::Operational(error))
                     if error.kind() == std::io::ErrorKind::Unsupported), "{text}");
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]fn actual_compound_if_disposition_binds_same_primary_product_and_rejects_foreign_and_quota_io(){
  for body in["    if(argument)\n        return 1\n    return 2\n","    if(argument)\n        return 1\n    else\n        return 2\n"]{
   let text=format!("/proc/p(argument)\n{body}");let db=Arc::new(QueryDb::default());
   let own=original_frontend(&mut RetainedSemanticTree::new(),&db,&text);let other=original_frontend(&mut RetainedSemanticTree::new(),&db,&text);
   let input=original_input(&own,"p");let foreign=original_input(&other,"p");
   let denied=db.fail_body_syntax_after_for_test(0,std::io::Error::new(std::io::ErrorKind::OutOfMemory,"actual canonical body operation denied"));
   assert!(matches!(db.syntax_product_checked(&input),Err(BodySyntaxFailure::Operational(error))if error.kind()==std::io::ErrorKind::OutOfMemory));drop(denied);
   let product=db.syntax_product_checked(&input).unwrap();
   setting_syntax::with_setting_admission(&db.body_charge,|a|{
    let bound=input.bind_original_product_checked(product.parsed().unwrap(),a)?;
    let dm_tree::frontend::OriginalBodyDisposition::Available(grant)=bound.original_code_disposition()?else{panic!("genuine complete compound body must be available")};assert!(grant.belongs_to(&bound));assert_eq!(grant.statement_span()?,None);
    assert!(foreign.bind_original_product_checked(product.parsed().unwrap(),a).is_err());Ok::<(),BodySyntaxFailure>(())
   }).unwrap();
   let archive=Arc::clone(own.source_view().unwrap().archive());let calls=std::cell::Cell::new(0);let fault=||Err(std::io::Error::from_raw_os_error(1450));let a=dm_syntax::SettingAdmission::new(&db.body_charge,BUDGET,&fault);
   assert!(matches!(archive.with_current_body_checked(0,&a,|_|{calls.set(calls.get()+1);Ok(())}),Err(BodySyntaxFailure::Operational(error))if error.raw_os_error()==Some(1450)));assert_eq!(calls.get(),0);
  }
 }

}

/// Real canonical Kind4 dependency on this SAME active query context. The
/// archive's checked-in entry performs host preparation, current input/code
/// binding and real current source/error projection AFTER this one get.
pub(super) fn obtain_product(ctx:&mut dm_query::Ctx<'_>,input:&Arc<BodySyntaxInput>)->Result<Arc<OriginalBodySyntaxProduct>,BodySyntaxFailure>{
 let key=code_key(input)?;let code=Arc::clone(input.original_code_owner().expect("actual canonical code locator checked"));
 let result=ctx.get::<BodyQueryValue>(key,Arc::new(Params{input:Arc::downgrade(input),key,code:Some(code)})).map_err(checked_query_failure)?;
 match result.as_ref(){BodyQueryValue::Canonical(result)=>result.clone().map_err(BodySyntaxFailure::Syntax),BodyQueryValue::Issued(_)=>Err(BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidData,"active native context returned issued syntax for canonical key")))}
}

#[cfg(test)]
impl QueryDb{
 pub(crate) fn original_current_body_bytes_for_test(&self,input:&Arc<dm_analysis::checker_effects::EffectInput>,ordinal:usize,encode:impl FnOnce(&[dm_analysis::checker_effects::OriginalBodyDiagnostic])->Vec<u8>)->Result<Vec<u8>,BodySyntaxFailure>{
  self.with_setting_admission(|syntax|input.archive().with_current_body_checked(ordinal,syntax,|body|{
   input.with_current_original_body_rows(&body,syntax,input.archive().tree(),&dm_analysis::checker_effects::ExecutionAdmission::default(),&||crate::daemon::control::checkpoint(),|rows|Ok(encode(rows))).map_err(|actual|match actual{
    dm_analysis::policy_body_demand::PolicyFailure::Operational(actual)=>BodySyntaxFailure::Operational(actual),
    actual=>BodySyntaxFailure::Operational(std::io::Error::other(actual.to_string())),
   })
  }))
 }
}

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

#[path = "body_syntax_census_tests.rs"]
pub(super) mod body_syntax_census_tests;

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
 fn actual_original_terminal_do_while_requires_owned_statement_terminator(){
  let fixture="/proc/probe(x)\n    do\n        x *= 2\n    while(x < 8)\n";
  for(text,expected)in[(fixture.to_owned(),true),(fixture.replace("    while(x < 8)","    while(x < 8);"),true),
   (fixture.replace("    do\n","    do;\n"),false),(fixture.replace("while(x < 8)","while(x < 8) return x"),false)]{
   let db=Arc::new(QueryDb::default());let front=issued_original_fixture(&db,&text);let input=original_input(&front,"probe");let product=db.syntax_product_checked(&input).unwrap();
   setting_syntax::with_setting_admission(&db.body_charge,|admission|{let body=input.bind_original_product_checked(product.parsed().unwrap(),admission)?;let result=body.original_code_disposition();
    if expected{let dm_tree::frontend::OriginalBodyDisposition::Available(proof)=result?else{panic!("actual terminal do-while remains unissued")};assert!(proof.belongs_to(&body));}
    else{assert!(matches!(result,Err(BodySyntaxFailure::Operational(error))if error.kind()==std::io::ErrorKind::Unsupported));}Ok::<(),BodySyntaxFailure>(())
   }).unwrap();
  }
 }
 #[test]
 fn actual_original_stoplag_production_body_uses_exact_macro_definitions_and_terminal_cursor(){
  let root=std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../..");let actual=std::fs::read_to_string(root.join("code/host/helpers/time.dm")).unwrap();
  let start=actual.find("#define DELTA_CALC ").unwrap();let end=start+actual[start..].find("#undef DELTA_CALC").unwrap()+"#undef DELTA_CALC".len();let mut source=String::new();
  for(path,prefix)in[("code/defines/host/math.dm","#define CEILING("),("code/defines/engine/time.dm","#define DS2TICKS("),("code/defines/engine/_tick.dm","#define TICK_USAGE "),("code/defines/engine/_tick.dm","#define TICK_LIMIT_TO_RUN "),("code/defines/engine/kernel_timing.dm","#define INITSTAGE_MAX ")]{
   let text=std::fs::read_to_string(root.join(path)).unwrap();let line=text.lines().find(|line|line.starts_with(prefix)).unwrap();source.push_str(line);source.push('\n');
  }
  source.push_str(&actual[start..end]);source.push('\n');
  let db=Arc::new(QueryDb::default());let front=issued_original_fixture(&db,&source);let input=original_input(&front,"stoplag");let product=db.syntax_product_checked(&input).unwrap();
  setting_syntax::with_setting_admission(&db.body_charge,|admission|{let body=input.bind_original_product_checked(product.parsed().unwrap(),admission)?;let dm_tree::frontend::OriginalBodyDisposition::Available(proof)=body.original_code_disposition()?else{panic!("whole actual production stoplag remains unissued")};assert!(proof.belongs_to(&body));
   assert!(product.parsed().unwrap().statement_storage().parsed().statements.iter().any(|statement|matches!(statement.kind,dm_syntax::StatementKind::DoWhile{..})),"the UNIT_TESTS alternate body was not substituted");Ok::<(),BodySyntaxFailure>(())
  }).unwrap();
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
             "else if(istype(character, /datum/mind)) M = character"), true),
         (fixture.replace("else if(istype(character, /datum/mind))\n        M = character",
             "else if(istype(character, /datum/mind)) M.field = character"), false),
         (fixture.replace("else if(istype(character, /datum/mind))\n        M = character",
             "else if(istype(character, /datum/mind)); M = character"), false),
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
         ("var/static/list/sound_cache = list()", true),
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
/proc/member_increment_nested(target)
    target.nested.next++
    return target
/proc/prefix_increment_return(next)
    return ++next
"#;
     let db = Arc::new(QueryDb::default());
     let front = issued_original_fixture(&db, fixture);
     for (name, expected) in [("wrapper", true), ("vg_adjust_multi_hook", true), ("vg_air_watch_changed", true), ("local_row", true), ("static_initializer", true),
         ("member_increment", true), ("prefix_increment", true), ("member_increment_nested", false), ("prefix_increment_return", false)]
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
 fn actual_original_scalar_membership_and_bare_list_assignment_preserve_the_exact_roles() {
     let fixture = "/proc/probe(list/list)\n    while(null in list)\n        list -= null\n    return\n";
     for (source, expected) in [
         (fixture.to_owned(), true),
         (fixture.replace("list -= null", "list += null"), true),
         (fixture.replace("list -= null", "list = null"), true),
         (fixture.replace("null in list", "0 in list"), true),
         (fixture.replace("null in list", "42 in list"), true),
         (fixture.replace("null in list", "null in entries"), true),
         (fixture.replace("null in list", "null in list()"), false),
         (fixture.replace("null in list", "null in list && flag"), false),
         (fixture.replace("null in list", "null && flag in list"), false),
         (fixture.replace("null in list", "null in first to last"), false),
         (fixture.replace("null in list", "null in list tail"), false),
         (fixture.replace("list -= null", "list() -= null"), false),
         (fixture.replace("list -= null", "list.key -= null"), false),
         (fixture.replace("list -= null", "list[1] -= null"), false),
         (fixture.replace("list -= null", "list:key -= null"), false),
         (fixture.replace("list -= null", "list?.key -= null"), false),
     ] {
         let db = Arc::new(QueryDb::default());
         let front = issued_original_fixture(&db, &source);
         let input = original_input(&front, "probe");
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let disposition = body.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = disposition? else {
                     panic!("issued scalar membership and list target must be available: {source}");
                 };
                 assert!(proof.belongs_to(&body));
                 let parsed = product.parsed().unwrap().statement_storage().parsed();
                 let dm_syntax::StatementKind::While { condition, body } = &parsed.statements[0].kind
                     else { panic!("actual while"); };
                 assert!(matches!(&condition.kind, dm_syntax::ExprKind::Binary { op, lhs, rhs }
                     if op == "in" && matches!(&lhs.kind, dm_syntax::ExprKind::Literal(_))
                         && matches!(&rhs.kind, dm_syntax::ExprKind::Ident(_))));
                 assert_eq!(body.len(), 1);
             } else {
                 assert!(!matches!(disposition, Ok(dm_tree::frontend::OriginalBodyDisposition::Available(_))), "{source}");
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]
 fn actual_original_pop_and_merge_key_postfix_shapes_bind_only_their_issued_roles() {
     let pop = "/proc/probe(list/listfrom)\n    if(listfrom.len > 0)\n        var/picked = listfrom[listfrom.len]\n        listfrom.len--\n        return picked\n    return null\n";
     let merge = "/proc/probe(list/L, Li, list/result)\n    result += L[Li++]\n    return result\n";
     for (source, expected) in [
         (pop.to_owned(), true),
         (merge.to_owned(), true),
         (merge.replace("Li++", "Li--"), true),
         (pop.replace("listfrom.len--", "listfrom:len--"), false),
         (pop.replace("listfrom.len--", "listfrom?.len--"), false),
         (pop.replace("listfrom.len--", "listfrom.inner.len--"), false),
         (merge.replace("Li++", "++Li"), false),
         (merge.replace("Li++", "L.Li++"), false),
         (merge.replace("Li++", "L[Li]++"), false),
         (merge.replace("result += L[Li++]", "L[Li++] = result"), false),
     ] {
         let db = Arc::new(QueryDb::default());
         let front = issued_original_fixture(&db, &source);
         let input = original_input(&front, "probe");
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let disposition = body.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = disposition? else {
                     panic!("actual pop/merge postfix cohort must be available: {source}");
                 };
                 assert!(proof.belongs_to(&body));
             } else {
                 assert!(!matches!(disposition, Ok(dm_tree::frontend::OriginalBodyDisposition::Available(_))), "{source}");
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]
 fn actual_original_for_list_direct_call_reuses_only_its_completed_ordinary_iterable() {
     let fixture = "/proc/probe(path, other)\n    for(var/T in subtypesof(path))\n        return T\n";
     for (source, expected) in [
         (fixture.to_owned(), true),
         (fixture.replace("subtypesof(path)", "typesof(path)"), true),
         (fixture.replace("subtypesof(path)", "lookup()"), true),
         (fixture.replace("subtypesof(path)", "lookup(path, other)"), true),
         (fixture.replace("subtypesof(path)", "lookup(path,)"), true),
         (fixture.replace("subtypesof(path)", "object.lookup(path)"), false),
         (fixture.replace("subtypesof(path)", "object:lookup(path)"), false),
         (fixture.replace("subtypesof(path)", "object?.lookup(path)"), false),
         (fixture.replace("subtypesof(path)", "subtypesof(path).items"), false),
         (fixture.replace("subtypesof(path)", "lookup(choice = path)"), false),
         (fixture.replace("subtypesof(path)", "new /datum/probe(path)"), false),
         (fixture.replace("subtypesof(path)", "pick(path)"), false),
         (fixture.replace("subtypesof(path)", "lookup(path) + other"), false),
         (fixture.replace("subtypesof(path)", "(lookup(path))"), false),
         (fixture.replace("subtypesof(path)", "lookup(path) = other"), false),
         (fixture.replace("subtypesof(path)", "lookup(path) tail"), false),
     ] {
         let db = Arc::new(QueryDb::default());
         let front = issued_original_fixture(&db, &source);
         let input = original_input(&front, "probe");
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let disposition = body.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = disposition? else {
                     panic!("actual direct Call iterable must be available: {source}");
                 };
                 assert!(proof.belongs_to(&body));
                 let parsed = product.parsed().unwrap().statement_storage().parsed();
                 let dm_syntax::StatementKind::For { control, body, .. } =
                     &parsed.statements[0].kind else { panic!("actual for-list"); };
                 let dm_syntax::ForControl::Each { iterable, .. } = control
                     else { panic!("actual list control"); };
                 assert!(matches!(&iterable.kind, dm_syntax::ExprKind::Call { callee, .. }
                     if matches!(&callee.kind, dm_syntax::ExprKind::Ident(_))));
                 assert!(matches!(body[0].kind, dm_syntax::StatementKind::Return(_)));
             } else {
                 assert!(!matches!(disposition, Ok(dm_tree::frontend::OriginalBodyDisposition::Available(_))), "{source}");
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
         (fixture.replace("\treturn 1\n", "\treturn 1\n    else\n        return 2\n"), true),
         (fixture.replace("\treturn 1", "; return 1"), false),
         (fixture.replace("\treturn 1\n", "\treturn 1\n    else return 2\n"), false),
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
 fn actual_original_indexed_rhs_helpers_keep_their_real_source_and_lvalue_shapes() {
     let file = include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../../code/host/helpers/icons.dm")).replace("\r\n", "\n");
     let compat = include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../../code/__byond_version_compat.dm"));
     let actual_clamp = compat.lines().find(|line| line.starts_with("#define CLAMP(")).unwrap();
     for name in ["adjust_brightness", "AverageColor", "build_icon_state_set"] {
         let start = file.find(&format!("/proc/{name}(")).unwrap();
         let end = file[start+1..].find("\n/proc/").map(|at|start+1+at).unwrap();
         let actual = &file[start..end];
         let source = format!("{actual_clamp}\n{actual}");
         let db = Arc::new(QueryDb::default());
         let front = issued_original_fixture(&db,&source);
         let input = original_input(&front,name);
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge,|admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(),admission)?;
             let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = body.original_code_disposition()? else {
                 panic!("whole authored helper indexed RHS: {name}");
             };
             assert!(proof.belongs_to(&body));
             Ok::<(),BodySyntaxFailure>(())
         }).unwrap();
     }
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
         // Exact safe-name and ordinary call-result followers now have read proofs.
         ("return target_list?[list_length]", true),
         ("return get_list()[list_length]", true),
         // Other receiver/key cohorts retain their independent restrictions.
         ("return target_list[object:key]", false),
         ("return target_list[object?.key]", false),
         ("return target_list[list_length + 1]", true),
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
 fn actual_original_guest_key_empty_for_initializer_keeps_absence_and_real_separators() {
     let file = include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../../code/host/helpers/client_lookup.dm")).replace("\r\n", "\n");
     let start = file.find("/proc/IsGuestKey(").unwrap();
     let end = file[start + 1..].find("\n/proc/").map(|at| start + 1 + at).unwrap();
     let actual = &file[start..end];
     let markers = include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../../code/defines/engine/declare/markers.dm"));
     let reads_from = markers.lines().find(|line| line.starts_with("#define READS_FROM(")).unwrap();
     let leaf = "for (, i <= len, ++i)";
     assert!(actual.contains(leaf));
     for (body, expected) in [
         (actual.to_owned(), true),
         (actual.replace(leaf, "for (; i <= len; ++i)"), true),
         (actual.replace(leaf, "for (ignored, i <= len, ++i)"), false),
         (actual.replace(leaf, "for (; i <= len, ++i)"), false),
         (actual.replace(leaf, "for (, , ++i)"), false),
         (actual.replace(leaf, "for (, i <= len, )"), false),
         (actual.replace(leaf, "for (, i <= len, bump(i))"), false),
         (actual.replace(leaf, "for (i <= len, ++i)"), false),
     ] {
         let source = format!("{reads_from}\n{body}");
         let db = Arc::new(QueryDb::default());
         let front = issued_original_fixture(&db, &source);
         let input = original_input(&front, "IsGuestKey");
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let bound = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let disposition = bound.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = disposition? else { panic!("actual empty initializer loop: {source}"); };
                 assert!(proof.belongs_to(&bound));
                 let parsed = product.parsed().unwrap().statement_storage().parsed();
                 let loop_stmt = parsed.statements.iter().find(|statement| matches!(&statement.kind, dm_syntax::StatementKind::For { .. })).unwrap();
                 let dm_syntax::StatementKind::For { control: dm_syntax::ForControl::CStyle { initializer, condition, step }, .. } = &loop_stmt.kind else { panic!("same C style loop"); };
                 assert!(initializer.is_none(), "no invented initializer or new declaration");
                 assert!(condition.is_some() && step.is_some());
                 assert!(!parsed.local_variables.entries().unwrap().iter().any(|row| row.source_kind == dm_syntax::LocalSourceKind::ForInitializer));
             } else {
                 assert!(!matches!(disposition, Ok(dm_tree::frontend::OriginalBodyDisposition::Available(_))), "{source}");
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }


 #[test]
 fn actual_original_range_and_classic_bare_loop_exits_keep_exact_source_authority() {
     // Macro-body loop shape in getFlatIcon: this is a source-backed subtree,
     // not a claim that every other production in the whole helper is issued.
     let icons=std::fs::read_to_string(std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
         .join("../../../../code/host/helpers/icons.dm")).unwrap();
     assert!(icons.contains("for (var/i in 1 to process.len)"));
     assert!(icons.contains("for (var/index_to_compare_to in 1 to layers.len)"));
     let fixture="/proc/probe(process)\n    for(var/i in 1 to process.len)\n        if(!i)\n            continue\n        break\n    return 0\n";
     for (text,expected) in [
         (fixture.to_owned(),true),
         (fixture.replace("for(var/i in 1 to process.len)","for(var/i=1; i<=process.len; i++)"),true),
         (fixture.replace("for(var/i in 1 to process.len)","for(var/i=1, i<=process.len, i++)"),true),
         (fixture.replace("            continue","            continue target"),false),
         (fixture.replace("        break","        break target"),false),
         (fixture.replace("var/i in 1", "i in 1"),false),
         (fixture.replace("to process.len)", "to process.len step 2)"),false),
         (fixture.replace("for(var/i in 1 to process.len)","for(var/i=1; i<=process.len, i++)"),false),
         ("/proc/probe()\n    break\n    return 0\n".to_owned(),false),
         ("/proc/probe()\n    continue\n    return 0\n".to_owned(),false),
     ] {
         let db=Arc::new(QueryDb::default());
         let front=issued_original_fixture(&db,&text);
         let input=original_input(&front,"probe");
         let product=db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge,|admission| {
             let body=input.bind_original_product_checked(product.parsed().unwrap(),admission)?;
             let disposition=body.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof)=disposition? else {
                     panic!("same authenticated loop must issue: {text}");
                 };
                 assert!(proof.belongs_to(&body));
             } else {
                 assert!(matches!(disposition,Err(BodySyntaxFailure::Operational(error))
                     if error.kind()==std::io::ErrorKind::Unsupported),"{text}");
             }
             Ok::<(),BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]
 fn actual_original_classic_additive_steps_require_bare_names_and_matching_separators() {
     // Exact header and first body line from reject_bad_name; other body
     // constructs are intentionally not substituted or claimed as covered.
     let actual=std::fs::read_to_string(std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
         .join("../../../../code/host/helpers/text.dm")).unwrap();
     assert!(actual.contains("for(var/i = 1, i <= t_len, i += length(char))"));
     assert!(actual.contains("char = t_in[i]"));
     let fixture="/proc/probe(t_in,t_len,char)\n    for(var/i = 1, i <= t_len, i += length(char))\n        char = t_in[i]\n    return char\n";
     for (text,expected) in [
         (fixture.to_owned(),true),
         (fixture.replace("i += length(char)","i -= length(char)"),true),
         (fixture.replace("1, i <= t_len,", "1; i <= t_len;"),true),
         (fixture.replace("1, i <= t_len,", "1; i <= t_len,"),false),
         (fixture.replace("i += length(char)","i *= length(char)"),false),
         (fixture.replace("i += length(char)","i.field += length(char)"),false),
         (fixture.replace("i += length(char)","i[1] += length(char)"),false),
         (fixture.replace("i += length(char)","(i) += length(char)"),false),
         (fixture.replace("i += length(char)","null += length(char)"),false),
         (fixture.replace("i += length(char)","__PROC__ += length(char)"),false),
         (fixture.replace("i += length(char)","i += (char += 1)"),false),
     ] {
         let db=Arc::new(QueryDb::default());
         let front=issued_original_fixture(&db,&text);
         let input=original_input(&front,"probe");
         let product=db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge,|admission| {
             let body=input.bind_original_product_checked(product.parsed().unwrap(),admission)?;
             let disposition=body.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof)=disposition? else {
                     panic!("same authored additive classic step must issue: {text}");
                 };
                 assert!(proof.belongs_to(&body));
             } else {
                 assert!(matches!(disposition,Err(BodySyntaxFailure::Operational(error))
                     if error.kind()==std::io::ErrorKind::Unsupported),"{text}");
             }
             Ok::<(),BodySyntaxFailure>(())
         }).unwrap();
     }
 }


 #[test]
 fn actual_original_read_rgb_inline_prefix_uses_own_condition_close_and_statement_receipt(){
  let actual=std::fs::read_to_string(std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../../code/host/helpers/icons.dm")).unwrap();
  let line=actual.lines().find(|line|line.trim_start().starts_with("if(text2ascii(rgb) == 35) ++start")).expect("actual ReadRGB opening-hash skip").trim();
  assert!(line.ends_with("// skip opening #"));
  // Exact actual statement subtree, not a claim that the whole RGB helper's
  // other independent grammar frontiers are all currently witnessed.
  let fixture=format!("/proc/probe(rgb,start)\n    {line}\n    return start\n");
  for(text,expected)in[
   (fixture.clone(),true),(fixture.replace("++start","-- start"),true),
   (fixture.replace("++start","++start.name"),false),(fixture.replace("++start","++L[start]"),false),
   (fixture.replace("++start","++lookup()"),false),(fixture.replace("++start","++(start)"),false),
   (fixture.replace("++start","start++"),false),(fixture.replace("++start","++start + 1"),false),
   (fixture.replace("++start","++null"),false),(fixture.replace("++start","++__TYPE__"),false),
   (fixture.replace(") ++start",") ; ++start"),false),
   (fixture.replace(") ++start",") {;} ++start"),false),
   (fixture.replace("++start","+ +start"),false),
   (fixture.replace("++start","(++start)"),false),
  ]{
   let db=Arc::new(QueryDb::default());let front=issued_original_fixture(&db,&text);let input=original_input(&front,"probe");let product=db.syntax_product_checked(&input).unwrap();
   setting_syntax::with_setting_admission(&db.body_charge,|admission|{
    let body=input.bind_original_product_checked(product.parsed().unwrap(),admission)?;let disposition=body.original_code_disposition();
    if expected{let dm_tree::frontend::OriginalBodyDisposition::Available(proof)=disposition?else{panic!("same actual inline prefix leaf must be witnessed: {text}")};assert!(proof.belongs_to(&body));}
    else{assert!(matches!(disposition,Err(BodySyntaxFailure::Operational(error))if error.kind()==std::io::ErrorKind::Unsupported),"{text}");}
    Ok::<(),BodySyntaxFailure>(())
   }).unwrap();
  }
 }


 #[test]
 fn actual_original_global_local_heads_preserve_static_source_modifiers_and_independent_values(){
  let fixture="/proc/probe()\n    var/global/time_offset=0\n    return time_offset\n";
  for(text,expected)in[(fixture.to_owned(),true),(fixture.replace("global/","static/"),true),
   (fixture.replace("global/","tmp/"),false),(fixture.replace("global/","global/global/"),false),
   (fixture.replace("time_offset=0","time_offset[1]=list()"),false),
   (fixture.replace("time_offset=0","time_offset=(time_offset += 1)"),false)]{
   let db=Arc::new(QueryDb::default());let front=issued_original_fixture(&db,&text);let input=original_input(&front,"probe");let product=db.syntax_product_checked(&input).unwrap();
   setting_syntax::with_setting_admission(&db.body_charge,|admission|{
    let body=input.bind_original_product_checked(product.parsed().unwrap(),admission)?;let disposition=body.original_code_disposition();
    if expected{let dm_tree::frontend::OriginalBodyDisposition::Available(proof)=disposition?else{panic!("same actual storage-local head must be witnessed: {text}")};assert!(proof.belongs_to(&body));
     let entries=product.parsed().unwrap().statement_storage().parsed().local_variables.entries().unwrap();assert_eq!(entries[0].source_modifiers,1);
    }else{assert!(matches!(disposition,Err(BodySyntaxFailure::Operational(error))if error.kind()==std::io::ErrorKind::Unsupported),"{text}");}
    Ok::<(),BodySyntaxFailure>(())
   }).unwrap();
  }
 }
 #[test]
 fn actual_original_single_list_dimension_owns_the_consumed_complete_child(){
  let fixture="/proc/probe(n)\n    var/list/chars_to_add[max(n+1,0)]\n    return chars_to_add\n";
  for(text,expected)in[(fixture.to_owned(),true),(fixture.replace("max(n+1,0)","(n+1)"),true),
   (fixture.replace("var/list/","var/"),false),(fixture.replace("var/list/","var/static/list/"),false),
   (fixture.replace("[max(n+1,0)]","[]"),false),(fixture.replace("[max(n+1,0)]","[n][1]"),false),
   (fixture.replace("[max(n+1,0)]","[n]=list()"),false),(fixture.replace("max(n+1,0)","n++"),false),
   (fixture.replace("max(n+1,0)","(n=1)"),false),(fixture.replace("chars_to_add[","chars_to_add;["),false)]{
   let db=Arc::new(QueryDb::default());let front=issued_original_fixture(&db,&text);let input=original_input(&front,"probe");let product=db.syntax_product_checked(&input).unwrap();
   setting_syntax::with_setting_admission(&db.body_charge,|admission|{
    let body=input.bind_original_product_checked(product.parsed().unwrap(),admission)?;let disposition=body.original_code_disposition();
    if expected{let dm_tree::frontend::OriginalBodyDisposition::Available(proof)=disposition?else{panic!("same exact array shape and actual child must be witnessed: {text}")};assert!(proof.belongs_to(&body));
     let entry=&product.parsed().unwrap().statement_storage().parsed().local_variables.entries().unwrap()[0];let initializer=entry.implicit_list_initializer().unwrap();assert_eq!(initializer.dimension_slots.as_ref(),[Some(0)]);assert_eq!(initializer.dimensions.len(),1);
     if text.contains("max("){let dm_syntax::ExprKind::Call{args,..}=&initializer.dimensions[0].kind else{panic!("actual max dimension")};let dm_syntax::ExprKind::Literal(value)=&args[1].kind else{panic!("actual scalar zero")};assert!(matches!(value.original_value(),Some(dm_syntax::OriginalTokenValue::Int(0))),"the ledger uses actual typed child, not compatibility AST");}
    }else{assert!(matches!(disposition,Err(BodySyntaxFailure::Operational(error))if error.kind()==std::io::ErrorKind::Unsupported),"{text}");}
    Ok::<(),BodySyntaxFailure>(())
   }).unwrap();
  }
 }
 #[test]
 fn actual_original_time_and_padding_helpers_use_authored_storage_and_array_declarations(){
  let root=std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../..");
  let time=std::fs::read_to_string(root.join("code/host/helpers/time.dm")).unwrap();let start=time.find("/proc/get_game_time()").unwrap();let end=time[start..].find("GLOBAL_VAR_INIT(roundstart_hour").unwrap()+start;
  let tick=std::fs::read_to_string(root.join("code/defines/engine/_tick.dm")).unwrap();let define=tick.lines().find(|line|line.starts_with("#define TICK_USAGE ")).unwrap();
  let mut fixtures=vec![("get_game_time".to_owned(),format!("{define}\n{}",&time[start..end]))];
  let text=std::fs::read_to_string(root.join("code/host/helpers/text.dm")).unwrap();
  for name in ["add_leading","add_trailing"]{let start=text.find(&format!("/proc/{name}(")).unwrap();let tail=&text[start..];let end=tail[1..].find("\n/proc/").map_or(tail.len(),|at|at+1);let source=tail[..end].to_owned();assert!(source.contains("var/list/chars_to_add[max(charcount + 1, 0)]"));fixtures.push((name.to_owned(),source));}
  for(name,text)in fixtures{let db=Arc::new(QueryDb::default());let front=issued_original_fixture(&db,&text);let input=original_input(&front,&name);let product=db.syntax_product_checked(&input).unwrap();setting_syntax::with_setting_admission(&db.body_charge,|admission|{
   let body=input.bind_original_product_checked(product.parsed().unwrap(),admission)?;let dm_tree::frontend::OriginalBodyDisposition::Available(proof)=body.original_code_disposition()?else{panic!("whole authored helper remains unissued: {name}")};assert!(proof.belongs_to(&body));Ok::<(),BodySyntaxFailure>(())
  }).unwrap();}
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
         (fixture.replace(", i++)", ", i = i + 1)"), true),
         (fixture.replace("i++)", "i--)"), true),
         (fixture.replace(", i++)", ", i.field = i)"), false),
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
         (fixture.replace("new_y--", "--new_y"), true),
         (fixture.replace("new_y--", "return --new_y"), false),
         (fixture.replace("new_y--", "new_y.field--"), true),
         (fixture.replace("new_y--", "new_y.nested.field--"), false),
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
         (fixture.replace("if(QDELETED(txt_rank)) continue", "for(var/i in 1 to 2)\n            continue"), true),
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
         (fixture.replace("        for(var/datum/admin_rank/R in admin_ranks)", "        for(var/R in 1 to 2)"), true),
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
 fn actual_original_last_inline_switch_return_has_an_actual_forward_terminator(){
  for fixture in [
   "/proc/probe(value)\n    switch(value)\n        if(1) return \"north\"\n/proc/later()\n    return 0\n",
   "/proc/probe(value)\n    switch(uppertext(value))\n        if(\"NORTH\") return 1\n/proc/later()\n    return 0\n",
  ]{for(text,expected)in[(fixture.to_owned(),true),(fixture.replace(") return", "); return"),false),(fixture.replace(r#"return "north""#, "return value=1").replace("return 1", "return value=1"),true)]{
   let db=Arc::new(QueryDb::default());let front=issued_original_fixture(&db,&text);let input=original_input(&front,"probe");let product=db.syntax_product_checked(&input).unwrap();
   setting_syntax::with_setting_admission(&db.body_charge,|admission|{let body=input.bind_original_product_checked(product.parsed().unwrap(),admission)?;let disposition=body.original_code_disposition();
    if expected{let dm_tree::frontend::OriginalBodyDisposition::Available(proof)=disposition?else{panic!("actual final inline switch case remains unissued: {text}")};assert!(proof.belongs_to(&body));
     let parsed=product.parsed().unwrap().statement_storage().parsed();let dm_syntax::StatementKind::Switch{cases,..}=&parsed.statements[0].kind else{panic!("actual switch")};assert!(cases[0].original_site.cursor.is_ok());
    }else{assert!(!matches!(disposition,Ok(dm_tree::frontend::OriginalBodyDisposition::Available(_))),"{text}");}Ok::<(),BodySyntaxFailure>(())
   }).unwrap();
  }}
 }

 #[test]
 fn actual_original_inline_switch_value_returns_have_exact_heads_and_case_cursors(){
  let fixture="/proc/probe(value)\n    switch(value)\n        if(1.0) return 1\n        if(\"NORTH\") return \"north\"\n        else return 0\n";
  for(text,expected)in[(fixture.to_owned(),true),(fixture.replace("switch(value)","switch(uppertext(value))"),true),
   (fixture.replace("if(1.0)","if(1,2)"),true),(fixture.replace("if(1.0)","if(1 to 2)"),true),
   (fixture.replace("return 1","return"),false),(fixture.replace("return 1","return lookup(value)"),true),
   (fixture.replace("return 1","return value=1"),true),(fixture.replace("if(1.0) return","if(1.0); return"),false),
   (fixture.replace("else return","else; return"),false),(fixture.replace("else return 0","else value=0"),false)]{
   let db=Arc::new(QueryDb::default());let front=issued_original_fixture(&db,&text);let input=original_input(&front,"probe");let product=db.syntax_product_checked(&input).unwrap();
   setting_syntax::with_setting_admission(&db.body_charge,|admission|{
    let body=input.bind_original_product_checked(product.parsed().unwrap(),admission)?;let disposition=body.original_code_disposition();
    if expected{let dm_tree::frontend::OriginalBodyDisposition::Available(proof)=disposition?else{panic!("exact inline value return remains unissued: {text}")};assert!(proof.belongs_to(&body));let parsed=product.parsed().unwrap().statement_storage().parsed();let dm_syntax::StatementKind::Switch{cases,..}=&parsed.statements[0].kind else{panic!("actual switch")};assert!(cases.iter().all(|case|case.original_site.cursor.is_ok()));}
    else{assert!(matches!(disposition,Err(BodySyntaxFailure::Operational(error))if error.kind()==std::io::ErrorKind::Unsupported),"{text}");}Ok::<(),BodySyntaxFailure>(())
   }).unwrap();
  }
 }
 #[test]
 fn actual_original_direction_and_blend_helpers_keep_authored_inline_returns(){
  let actual=std::fs::read_to_string(std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../../code/host/helpers/type2type.dm")).unwrap();
  for name in ["num2dir","dir2text","text2dir","blendMode2iconMode"]{
   let start=actual.find(&format!("/proc/{name}(")).unwrap();let tail=&actual[start..];let end=tail[1..].find("\n/proc/").map_or(tail.len(),|at|at+1);let source=&tail[..end];
   let db=Arc::new(QueryDb::default());let front=issued_original_fixture(&db,source);let input=original_input(&front,name);let product=db.syntax_product_checked(&input).unwrap();
   setting_syntax::with_setting_admission(&db.body_charge,|admission|{let body=input.bind_original_product_checked(product.parsed().unwrap(),admission)?;let dm_tree::frontend::OriginalBodyDisposition::Available(proof)=body.original_code_disposition()?else{panic!("whole authored helper remains unissued: {name}")};assert!(proof.belongs_to(&body));Ok::<(),BodySyntaxFailure>(())}).unwrap();
  }
 }

 #[test]
 fn actual_original_length_input_switch_authenticates_inline_returns() {
     let fixture = "/proc/probe(list/input)\n    switch(length(input))\n        if(0) return 0\n        if(1) return 1\n        else return 2\n";
     for (text, expected) in [
         (fixture.to_owned(), true),
         (fixture.replace("length(input)", "rand(0, 1)"), true),
         (fixture.replace("if(0)", "if(0, 1)"), false),
         (fixture.replace("return 0", "return"), false),
         (fixture.replace("length(input)", "input"), true),
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
 fn actual_original_dd_sort_colon_calls_keep_real_helpers_and_reject_follow_expansion() {
     let file=include_str!(concat!(env!("CARGO_MANIFEST_DIR"),"/../../../../code/host/helpers/_lists.dm")).replace("\r\n","\n");
     fn actual_proc<'a>(file:&'a str,head:&str)->&'a str {
         let tail=&file[file.find(head).unwrap()..];
         &tail[..tail.find("\n/proc/").unwrap_or(tail.len())]
     }
     let merge=actual_proc(&file,"/proc/dd_mergeObjectList(");
     let insert=actual_proc(&file,"/proc/dd_insertObjectList(");
     let dependency=actual_proc(&file,"/datum/proc/dd_SortValue(");
     assert!(merge.contains("LLiV = LLi:dd_SortValue()"));
     assert!(insert.contains("var/Oval = O:dd_SortValue()"));
     for (source,name,expected) in [
         (format!("{dependency}\n{merge}\n{insert}"),"dd_mergeObjectList",true),
         (format!("{dependency}\n{merge}\n{insert}"),"dd_insertObjectList",true),
         (merge.replace("LLi:dd_SortValue()","LLi:dd_SortValue(LLi)"),"dd_mergeObjectList",false),
         (insert.replace("O:dd_SortValue()","O.nested:dd_SortValue()"),"dd_insertObjectList",false),
         (insert.replace("O:dd_SortValue()","O():dd_SortValue()"),"dd_insertObjectList",false),
         (insert.replace("O:dd_SortValue()","O:dd_SortValue().field"),"dd_insertObjectList",false),
     ] {
         let db=Arc::new(QueryDb::default());
         let front=issued_original_fixture(&db,&source);
         let input=original_input(&front,name);
         let product=db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge,|admission| {
             let body=input.bind_original_product_checked(product.parsed().unwrap(),admission)?;
             let disposition=body.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof)=disposition? else {panic!("actual dd sort helper requires its parser-issued zeroarg colon call: {name}");};
                 assert!(proof.belongs_to(&body));
                 assert!(product.parsed().unwrap().statement_storage().parsed().diagnostics.is_empty());
             } else {assert!(!matches!(disposition,Ok(dm_tree::frontend::OriginalBodyDisposition::Available(_))),"{source}");}
             Ok::<(),BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]
 fn actual_original_nested_ordinary_index_is_a_read_and_keeps_actual_list_values() {
     let file=include_str!(concat!(env!("CARGO_MANIFEST_DIR"),"/../../../../code/host/helpers/_lists.dm")).replace("\r\n","\n");
     let tail=&file[file.find("/proc/list_values(").unwrap()..];
     let authored=&tail[..tail.find("\n/proc/").unwrap()];
     assert!(authored.contains("V[i] = L[L[i]]"));
     for (source,name,expected) in [
         (authored.to_owned(),"list_values",true),
         ("/proc/probe(L,R,i)\n    return L[R[i]]\n".to_owned(),"probe",true),
         ("/proc/probe(L,R,i)\n    return L[R[1]]\n".to_owned(),"probe",true),
         ("/proc/probe(L,R,i)\n    return L[R[42]]\n".to_owned(),"probe",true),
         ("/proc/probe(L,R,i)\n    return L[R[i+1]]\n".to_owned(),"probe",false),
         ("/proc/probe(L,R,i)\n    return L[R[-1]]\n".to_owned(),"probe",false),
         ("/proc/probe(L,R,i)\n    return L[R[i++]]\n".to_owned(),"probe",false),
         ("/proc/probe(L,R,i)\n    return L[R[lookup(i)]]\n".to_owned(),"probe",false),
         ("/proc/probe(L,R,i)\n    return L[R[S[i]]]\n".to_owned(),"probe",false),
         ("/proc/probe(L,R,i)\n    return L[(R[i])]\n".to_owned(),"probe",false),
         ("/proc/probe(L,R,i)\n    L[R[i]] = i\n".to_owned(),"probe",false),
         (authored.replace("V[i] = L[L[i]]","L[L[i]] = V[i]"),"list_values",false),
     ] {
         let db=Arc::new(QueryDb::default());
         let front=issued_original_fixture(&db,&source);
         let input=original_input(&front,name);
         let product=db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge,|admission| {
             let body=input.bind_original_product_checked(product.parsed().unwrap(),admission)?;
             let disposition=body.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof)=disposition? else {panic!("actual two-level ordinary read must be available: {source}");};
                 assert!(proof.belongs_to(&body));
                 let parsed=product.parsed().unwrap().statement_storage().parsed();
                 if name=="list_values" {
                     let dm_syntax::StatementKind::For{control:dm_syntax::ForControl::Range{..},body}=&parsed.statements[2].kind else {panic!("actual declared range");};
                     let dm_syntax::StatementKind::Assign{target,op,value}=&body[0].kind else {panic!("actual value copy");};
                     assert_eq!(op,"=");
                     assert!(matches!(&target.kind,dm_syntax::ExprKind::Index{object,index}if matches!(&object.kind,dm_syntax::ExprKind::Ident(name)if name=="V")&&matches!(&index.kind,dm_syntax::ExprKind::Ident(name)if name=="i")));
                     assert!(matches!(&value.kind,dm_syntax::ExprKind::Index{object,index}if matches!(&object.kind,dm_syntax::ExprKind::Ident(name)if name=="L")&&matches!(&index.kind,dm_syntax::ExprKind::Index{object,index}if matches!(&object.kind,dm_syntax::ExprKind::Ident(name)if name=="L")&&matches!(&index.kind,dm_syntax::ExprKind::Ident(name)if name=="i"))));
                 }
             } else {assert!(!matches!(disposition,Ok(dm_tree::frontend::OriginalBodyDisposition::Available(_))),"{source}");}
             Ok::<(),BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]
 fn actual_original_list_null_cohort_keeps_null_member_and_bare_list_target() {
     let file=include_str!(concat!(env!("CARGO_MANIFEST_DIR"),"/../../../../code/host/helpers/_lists.dm")).replace("\r\n","\n");
     fn actual_proc<'a>(file:&'a str,name:&str)->&'a str {
         let start=file.find(&format!("/proc/{name}(")).unwrap();
         let tail=&file[start..];
         &tail[..tail.find("\n/proc/").unwrap_or(tail.len())]
     }
     let names=["listclearnulls","difflist","list_clear_nulls"];
     let mut source=String::new();
     for name in names { source.push_str(actual_proc(&file,name)); source.push('\n'); }
     assert!(source.contains("/proc/listclearnulls(list/list)"));
     assert!(source.contains("while(null in list)"));
     assert!(source.contains("list -= null"));
     let db=Arc::new(QueryDb::default());
     let front=issued_original_fixture(&db,&source);
     for name in names {
         let input=original_input(&front,name);
         let product=db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge,|admission| {
             let body=input.bind_original_product_checked(product.parsed().unwrap(),admission)?;
             let dm_tree::frontend::OriginalBodyDisposition::Available(proof)=body.original_code_disposition()? else {
                 panic!("actual authored neighboring helper {name} must have Original grammar");
             };
             assert!(proof.belongs_to(&body));
             let parsed=product.parsed().unwrap().statement_storage().parsed();
             assert!(parsed.diagnostics.is_empty());
             if name=="listclearnulls" {
                 let dm_syntax::StatementKind::If{then_branch,..}=&parsed.statements[0].kind else { panic!("actual istype condition"); };
                 let dm_syntax::StatementKind::While{condition,body}=&then_branch[0].kind else { panic!("actual null-membership while"); };
                 assert!(matches!(&condition.kind,dm_syntax::ExprKind::Binary{op,lhs,rhs}
                     if op=="in" && matches!(&lhs.kind,dm_syntax::ExprKind::Literal(value)if value.as_str()=="null")
                     && matches!(&rhs.kind,dm_syntax::ExprKind::Ident(name)if name=="list")));
                 assert!(matches!(&body[0].kind,dm_syntax::StatementKind::Assign{target,op,value}
                     if op=="-=" && matches!(&target.kind,dm_syntax::ExprKind::Ident(name)if name=="list")
                     && matches!(&value.kind,dm_syntax::ExprKind::Literal(value)if value.as_str()=="null")));
                 assert!(matches!(parsed.statements.last().unwrap().kind,dm_syntax::StatementKind::Return(None)));
             }
             Ok::<(),BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]
 fn actual_original_create_sort_instance_macro_keeps_bare_contextual_new_without_target_reconstruction() {
     let file = include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../../code/host/helpers/sorts/__main.dm")).replace("\r\n", "\n");
     let start = file.find("#define CREATE_SORT_INSTANCE(").unwrap();
     let end = file[start..].find("\n//This is a global instance").map(|at| start + at).unwrap();
     let actual_macro = &file[start..end];
     assert!(actual_macro.contains("sorter = new;"));
     let source = format!("{actual_macro}\n/datum/sort_instance\n/proc/probe(to_sort, cmp, associative, fromIndex, toIndex)\n    CREATE_SORT_INSTANCE(to_sort, cmp, associative, fromIndex, toIndex)\n    return sorter\n");
     let db = Arc::new(QueryDb::default());
     let front = issued_original_fixture(&db, &source);
     let input = original_input(&front, "probe");
     let product = db.syntax_product_checked(&input).unwrap();
     setting_syntax::with_setting_admission(&db.body_charge, |admission| {
         let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
         let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = body.original_code_disposition()? else {
             panic!("actual CREATE_SORT_INSTANCE macro body remains available");
         };
         assert!(proof.belongs_to(&body));
         Ok::<(), BodySyntaxFailure>(())
     }).unwrap();
 }

 #[test]
 fn actual_original_merge_keyed_lists_uses_sequential_reads_in_real_sorttext_arguments() {
     let file = include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../../code/host/helpers/_lists.dm")).replace("\r\n", "\n");
     let start = file.find("/proc/mergeKeyedLists(").unwrap();
     let end = file[start + 1..].find("\n/proc/").map(|at| start + 1 + at).unwrap();
     let actual = &file[start..end];
     assert!(actual.contains("sorttext(L[Li][key], R[Ri][key])"));
     for (source, expected) in [
         (actual.to_owned(), true),
         (actual.replace("L[Li][key]", "L[Li][lookup(key)]"), false),
         (actual.replace("L[Li][key]", "L[Li][key++]"), false),
     ] {
         let db = Arc::new(QueryDb::default());
         let front = issued_original_fixture(&db, &source);
         let input = original_input(&front, "mergeKeyedLists");
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let disposition = body.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = disposition? else {
                     panic!("actual mergeKeyedLists body must be available");
                 };
                 assert!(proof.belongs_to(&body));
             } else {
                 assert!(!matches!(disposition, Ok(dm_tree::frontend::OriginalBodyDisposition::Available(_))), "{source}");
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]
 fn actual_original_dd_sortedtextlist_reuses_its_existing_for_name_without_shadow_locals() {
     let file = include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../../code/host/helpers/_lists.dm")).replace("\r\n", "\n");
     let start = file.find("/proc/dd_sortedtextlist(").unwrap();
     let end = file[start..].find("\n/datum/proc/dd_SortValue()").map(|at| start + at).unwrap();
     let actual = &file[start..end];
     assert!(actual.contains("var/current_sort_text"));
     assert!(actual.contains("for (current_sort_text in incoming)"));
     for (source, expected_for_bindings) in [
         (actual.to_owned(), 0),
         (actual.replace("for (current_sort_text in incoming)", "for (var/current_sort_text in incoming)"), 1),
         (actual.replace("\tvar/current_sort_text\n", ""), 0),
     ] {
         let db = Arc::new(QueryDb::default());
         let front = issued_original_fixture(&db, &source);
         let input = original_input(&front, "dd_sortedtextlist");
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = body.original_code_disposition()? else {
                 panic!("actual dd_sortedtextlist for-list grammar must be available");
             };
             assert!(proof.belongs_to(&body));
             let parsed = product.parsed().unwrap().statement_storage().parsed();
             assert_eq!(parsed.local_variables.entries().unwrap().iter()
                 .filter(|row| row.source_kind == dm_syntax::LocalSourceKind::ForBinding).count(), expected_for_bindings);
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]
 fn actual_original_init_subtypes_keeps_inline_assignment_and_dynamic_constructor_on_one_archive() {
     let file = include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../../code/host/helpers/_lists.dm")).replace("\r\n", "\n");
     let start = file.find("/proc/subtypesof(").unwrap();
     let init = file.find("/proc/init_subtypes(").unwrap();
     let end = file[init + 1..].find("\n/proc/").map(|at| init + 1 + at).unwrap();
     let source = &file[start..end];
     assert!(source.contains("if(!istype(L))\tL = list()"));
     assert!(source.contains("L += new path()"));
     for (text, expected) in [
         (source.to_owned(), true),
         (source.replace("if(!istype(L))\tL = list()", "if(!istype(L))\n        L = list()"), true),
         (source.replace("if(!istype(L))\tL = list()", "if(!istype(L)); L = list()"), false),
         (source.replace("if(!istype(L))\tL = list()", "if(!istype(L)) L.field = list()"), false),
         (source.replace("new path()", "new path(prototype)"), false),
         (source.replace("new path()", "new path.type()"), false),
     ] {
         let db = Arc::new(QueryDb::default());
         let front = issued_original_fixture(&db, &text);
         let input = original_input(&front, "init_subtypes");
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let disposition = body.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = disposition? else {
                     panic!("actual init_subtypes source must be available");
                 };
                 assert!(proof.belongs_to(&body));
             } else {
                 assert!(!matches!(disposition, Ok(dm_tree::frontend::OriginalBodyDisposition::Available(_))), "{text}");
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]
 fn actual_original_list2text_prefix_read_key_and_positional_dot_have_authentic_children(){
  for fixture in [
   r#"/proc/probe(list/L,i)
    return L[++i]
"#,
   r#"/proc/probe(list/L,i)
    . = "[L[++i]]"
"#,
   r#"/proc/probe(list/L,i,sep)
    . = text("[][][]", ., sep, L[++i])
"#,
  ]{for(text,expected)in[(fixture.to_owned(),true),(fixture.replace("++i","++i.field"),false)]{
   let db=Arc::new(QueryDb::default());let front=issued_original_fixture(&db,&text);let input=original_input(&front,"probe");let product=db.syntax_product_checked(&input).unwrap();
   setting_syntax::with_setting_admission(&db.body_charge,|admission|{let body=input.bind_original_product_checked(product.parsed().unwrap(),admission)?;let disposition=body.original_code_disposition();
    if expected{let dm_tree::frontend::OriginalBodyDisposition::Available(proof)=disposition?else{panic!("actual source child remains unissued: {text}")};assert!(proof.belongs_to(&body));}
    else{assert!(!matches!(disposition,Ok(dm_tree::frontend::OriginalBodyDisposition::Available(_))),"{text}");}Ok::<(),BodySyntaxFailure>(())
   }).unwrap();
  }}
 }
 #[test]
 fn actual_original_whole_list2text_keeps_its_real_local_macros_and_both_arms(){
  let file=std::fs::read_to_string(std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../../code/host/helpers/type2type.dm")).unwrap();let start=file.find("/proc/list2text(").unwrap();let end=start+file[start..].find("// Converts a string into a list").unwrap();let source=&file[start..end];
  assert_eq!(source.matches("#define S1  ").count(),2);assert!(source.contains("ls[++i]"));assert!(source.contains(r#"text("[][][]", ., S1)"#));
  let db=Arc::new(QueryDb::default());let front=issued_original_fixture(&db,source);let input=original_input(&front,"list2text");let product=db.syntax_product_checked(&input).unwrap();
  setting_syntax::with_setting_admission(&db.body_charge,|admission|{let body=input.bind_original_product_checked(product.parsed().unwrap(),admission)?;let dm_tree::frontend::OriginalBodyDisposition::Available(proof)=body.original_code_disposition()?else{panic!("whole authored list2text remains unissued")};assert!(proof.belongs_to(&body));Ok::<(),BodySyntaxFailure>(())}).unwrap();
 }

 #[test]
 fn actual_original_move_element_keeps_prefix_update_only_as_its_real_statement() {
     let file = include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../../code/host/helpers/_lists.dm")).replace("\r\n", "\n");
     let start = file.find("/proc/moveElement(").unwrap();
     let end = file[start + 1..].find("\n/proc/").map(|at| start + 1 + at).unwrap();
     let source = &file[start..end];
     assert!(source.contains("++fromIndex"));
     for (text, expected) in [
         (source.to_owned(), true),
         (source.replace("++fromIndex", "--fromIndex"), true),
         (source.replace("++fromIndex", "return ++fromIndex"), false),
         (source.replace("++fromIndex", "fromIndex = ++toIndex"), false),
         (source.replace("++fromIndex", "++fromIndex.field"), false),
         (source.replace("++fromIndex", "L[++fromIndex]"), false),
     ] {
         let db = Arc::new(QueryDb::default());
         let front = issued_original_fixture(&db, &text);
         let input = original_input(&front, "moveElement");
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let disposition = body.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = disposition? else {
                     panic!("actual moveElement prefix statement must be available");
                 };
                 assert!(proof.belongs_to(&body));
             } else {
                 assert!(!matches!(disposition, Ok(dm_tree::frontend::OriginalBodyDisposition::Available(_))), "{text}");
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }


 fn assert_statement_control_source_has_original_body(source:&str,name:&str,expected:bool){
  let db=Arc::new(QueryDb::default());let front=issued_original_fixture(&db,source);let input=original_input(&front,name);let product=db.syntax_product_checked(&input).unwrap();
  setting_syntax::with_setting_admission(&db.body_charge,|admission|{
   let body=input.bind_original_product_checked(product.parsed().unwrap(),admission)?;let disposition=body.original_code_disposition();
   if expected{let dm_tree::frontend::OriginalBodyDisposition::Available(proof)=disposition?else{panic!("actual statement/control source remains unissued: {source}")};assert!(proof.belongs_to(&body));}
   else{assert!(!matches!(disposition,Ok(dm_tree::frontend::OriginalBodyDisposition::Available(_))),"{source}");}
   Ok::<(),BodySyntaxFailure>(())
  }).unwrap();
 }
 #[test]
 fn actual_original_final_else_return_and_empty_array_initializer_keep_independent_children(){
  for(leaf,expected)in[
   ("if(value == 1) return value\n    else if(value == 2) return other\n    else return value",true),
   ("var/line[] = list(locate(px,py,M.z))\n    return line",true),
   ("var/list/line[ ] = list(value)\n    return line",true),
   ("var/line[4] = list(value)\n    return line",false),
   ("var/line[][] = list(value)\n    return line",false),
   ("var/other/line[] = list(value)\n    return line",false),
   ("if(value == 1) return value\n    else ++other",false),
  ]{let source=format!("/proc/probe(value,other,px,py,atom/M)\n    {leaf}\n");assert_statement_control_source_has_original_body(&source,"probe",expected);}
 }
 #[test]
 fn actual_original_range_dynamic_each_and_anything_children_reuse_owned_header_roles(){
  for(leaf,expected)in[
   ("for(x in x to center.x+radius)\n        return x",true),
   ("for(var/item in owner?.items)\n        return item",true),
   ("for(var/item in owner.items[key])\n        return item",true),
   ("for(var/item in owner.items())\n        return item",true),
   ("for(var/datum/item as anything in contents_of(owner))\n        return item",true),
   ("for(var/list/item as anything in metadata[\"states\"])\n        return item",true),
   ("for(var/datum/item as anything in (owner.items[key]))\n        return item",true),
   ("for(owner.x in x to last)\n        return x",false),
   ("for(x in x to last step delta)\n        return x",false),
   ("for(var/item in (x = owner.items))\n        return item",false),
  ]{let source=format!("/proc/probe(x,center,radius,owner,key,metadata,last,delta)\n    {leaf}\n");assert_statement_control_source_has_original_body(&source,"probe",expected);}
 }
 #[test]
 fn actual_original_comma_for_reuses_real_bare_initializer_and_separators(){
  for(leaf,expected)in[
   ("for(A,A && !istype(A,holder_type),A=A.loc);\n    return A",true),
   ("for(A;A && !istype(A,holder_type);A=A.loc);\n    return A",true),
   ("for(A,A && !istype(A,holder_type);A=A.loc);\n    return A",false),
   ("for(A.loc,A,A=A.loc);\n    return A",false),
  ]{let source=format!("/proc/probe(atom/A,holder_type)\n    {leaf}\n");assert_statement_control_source_has_original_body(&source,"probe",expected);}
 }
 #[test]
 fn actual_original_member_output_and_external_dispatch_statements_keep_source_children(){
  for leaf in ["world.log << text","owner.log.stream << text","call_ext((library || loader()),\"log_write\")(destination,text)"]{
   let source=format!("/proc/probe(owner,text,library,destination)\n    {leaf}\n");assert_statement_control_source_has_original_body(&source,"probe",true);
  }
 }
 #[test]
 fn actual_original_whole_zones_keeps_final_else_return_and_real_bodypart_macros(){
  let root=std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../..");
  let zones=std::fs::read_to_string(root.join("code/host/helpers/zones.dm")).unwrap();
  let defines=std::fs::read_to_string(root.join("code/defines/base/mobs.dm")).unwrap();
  let mut zone_source=String::new();for line in defines.lines(){if ["BP_L_FOOT","BP_R_FOOT","BP_L_LEG","BP_R_LEG","BP_L_HAND","BP_R_HAND","BP_L_ARM","BP_R_ARM"].iter().any(|name|line.strip_prefix("#define ").is_some_and(|tail|tail.starts_with(*name)&&tail.as_bytes().get(name.len()).is_some_and(u8::is_ascii_whitespace))){zone_source.push_str(line);zone_source.push('\n');}}
  zone_source.push_str(&zones);assert_statement_control_source_has_original_body(&zone_source,"parse_zone",true);
 }
 #[test]
 fn actual_original_whole_getline_keeps_explicit_unsized_array_and_real_sign_macro(){
  let root=std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../..");
  let geometry=std::fs::read_to_string(root.join("code/host/helpers/geometry.dm")).unwrap();let start=geometry.find("/proc/getline(").unwrap();let end=start+1+geometry[start+1..].find("/proc/").unwrap();
  let math=std::fs::read_to_string(root.join("code/defines/host/math.dm")).unwrap();let sign=math.lines().find(|line|line.starts_with("#define SIGN(")).unwrap();
  assert_statement_control_source_has_original_body(&format!("{sign}\n{}",&geometry[start..end]),"getline",true);
 }
 #[test]
 fn actual_original_whole_spiral_range_keeps_each_rebound_range_and_owned_body(){
  let root=std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../..");
  let range=std::fs::read_to_string(root.join("code/host/helpers/view_range.dm")).unwrap();let start=range.find("/proc/spiral_range(").unwrap();let end=range[start+1..].find("/proc/").map_or(range.len(),|at|start+1+at);
  assert_statement_control_source_has_original_body(&range[start..end],"spiral_range",true);
 }

 #[test]
 fn actual_original_labels_and_named_loop_control_keep_native_blocks_and_unknown_names(){
  for leaf in [
   "outer:\n        for(var/value in values)\n            if(value)\n                continue outer\n    return 0",
   "outer:\n        while(value)\n            inner:\n                while(value)\n                    break inner\n            continue outer\n    return value",
   "outer: { return value; }",
   "continue missing",
   "break missing",
   "if(value) continue missing\n    return value",
  ]{let source=format!("/proc/probe(value,values)\n    {leaf}\n");assert_statement_control_source_has_original_body(&source,"probe",true);}
  for leaf in ["outer.member:\n        return value","outer:{ return value; }","continue outer.member","break outer extra"]{
   let source=format!("/proc/probe(value)\n    {leaf}\n");assert_statement_control_source_has_original_body(&source,"probe",false);
  }
 }
 #[test]
 fn actual_original_label_disposition_never_transfers_to_another_bound_body_owner(){
  let db=Arc::new(QueryDb::default());let source="/proc/probe(value)\n    outer:\n        while(value)\n            continue outer\n    return value\n";
  let first=issued_original_fixture(&db,source);let second=issued_original_fixture(&db,&format!("\n{source}"));
  let first=original_input(&first,"probe");let second=original_input(&second,"probe");
  let p=db.syntax_product_checked(&first).unwrap();let q=db.syntax_product_checked(&second).unwrap();
  setting_syntax::with_setting_admission(&db.body_charge,|a|{let body=first.bind_original_product_checked(p.parsed().unwrap(),a)?;let other=second.bind_original_product_checked(q.parsed().unwrap(),a)?;
   let dm_tree::frontend::OriginalBodyDisposition::Available(proof)=body.original_code_disposition()?else{panic!("actual label source")};
   assert!(proof.belongs_to(&body));assert!(!proof.belongs_to(&other));Ok::<(),BodySyntaxFailure>(())
  }).unwrap();
 }
 #[test]
 fn actual_original_whole_station_area_helper_retains_its_authored_label_and_nested_loops(){
  let file=std::fs::read_to_string(std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../../code/library/helpers/events.dm")).unwrap();
  let start=file.find("/proc/get_station_areas(").unwrap();let end=start+1+file[start+1..].find("/proc/").unwrap();let source=&file[start..end];
  assert!(source.contains("looping_station_areas:"));assert!(source.contains("continue looping_station_areas"));
  assert_statement_control_source_has_original_body(source,"get_station_areas",true);
 }

 #[test]
 fn actual_original_else_after_trailing_while_keeps_each_owned_open_and_close(){
  for(source,expected)in[
   ("/proc/probe(value)\n    if(value)\n        while(value)\n            value -= 1\n    else\n        return value\n    return value\n",true),
   ("/proc/probe(value) { if(value) { while(value) { value -= 1; } } else { return value; } return value; }\n",true),
   ("/proc/probe(value)\n    if(value)\n        while(value);\n            value -= 1\n    else\n        return value\n    return value\n",false),
  ]{assert_statement_control_source_has_original_body(source,"probe",expected);}
 }

 #[test]
 fn actual_original_static_return_slot_key_assignments_route_whole_alpha_filter(){
  let file=std::fs::read_to_string(std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../../code/library/helpers/filters.dm")).unwrap();
  let start=file.find("/proc/alpha_mask_filter(").unwrap();let end=start+1+file[start+1..].find("/proc/").unwrap();let source=&file[start..end];
  assert!(source.contains(".[\"x\"] = x"));
  for(text,expected)in[(source.to_owned(),true),
   (source.replace(".[\"x\"] = x",".[\"[x]\"] = x"),true),
   (source.replace(".[\"x\"] = x",".[\"x\" + \"suffix\"] = x"),true)]{
   assert_statement_control_source_has_original_body(&text,"alpha_mask_filter",expected);
  }
  let source="/proc/probe(value)\n    . = list()\n    .[\"a=b\"] = value\n    return .\n";
  assert_statement_control_source_has_original_body(source,"probe",true);
 }

 #[test]
 fn actual_original_const_local_and_two_clause_for_keep_head_test_and_close_receipts(){
  for(leaf,expected)in[
   ("var/const/GUID_VERSION = \"b\"\n    return GUID_VERSION",true),
   ("for(var/i=0, ++i<=colors.len)\n        values += colors[i]\n    return values",true),
   ("for(var/i=0; ++i<=colors.len)\n        values += colors[i]\n    return values",true),
   ("for(var/i=0, i<colors.len)\n        values += colors[i]\n    return values",true),
   ("while(istype(Ab,/turf/simulated/open) && --above_range>0)\n        above_range -= 1\n    return values",true),
   ("if(++i<=colors.len)\n        return i\n    return 0",true),
   ("return ++i<=colors.len",false),
   ("var/value = ++i<=colors.len\n    return value",false),
   ("for(var/i=0, ++owner.i<=colors.len)\n        return i",false),
  ]{let source=format!("/proc/probe(colors,values,i,owner,Ab,above_range)\n    {leaf}\n");assert_statement_control_source_has_original_body(&source,"probe",expected);}
 }
 #[test]
 fn actual_original_dynamic_dot_index_and_safe_member_statements_keep_root_receipts(){
  for(leaf,expected)in[
   (". = list()\n    .[state_data[\"name\"]] = state_data[\"dirs\"]",true),
   ("remove_from?.images -= image",true),
   ("return remove_from?.images -= image",false),
   (". = list()\n    .[state_data[\"[key]\"]] = values",true),
   (". = list()\n    .[++key] = values",false),
  ]{let source=format!("/proc/probe(state_data,values,remove_from,image,key)\n    {leaf}\n");assert_statement_control_source_has_original_body(&source,"probe",expected);}
 }
 #[test]
 fn actual_original_return_index_assignment_is_a_distinct_value_context_not_nested_permission(){
  for(leaf,expected)in[
   ("return GLOB.string_lists[string_id] = values",true),
   ("return list(string_id = values)",true),
   ("return GLOB.string_lists[string_id] = other = values",false),
   ("return GLOB.string_lists[string_id] += values",false),
   ("consume(GLOB.string_lists[string_id] = values)",false),
  ]{let source=format!("/proc/probe(string_id,values,other)\n    {leaf}\n");assert_statement_control_source_has_original_body(&source,"probe",expected);}
 }
 #[test]
 fn actual_original_inline_switch_effects_ranges_and_call_returns_keep_actual_case_cursors(){
  for(source,expected)in[
   ("/proc/probe(H,G)\n    switch(H.gender)\n        if(\"male\") G.values += H.name\n        if(\"female\") G.values += H.name\n        else\n            G.values += H.name\n",true),
   ("/proc/probe(ascii)\n    switch(ascii)\n        if(48 to 57) . += ascii2text(ascii)\n        if(65 to 70) . += ascii2text(ascii+32)\n        else return text_or_null(default)\n    return .\n",true),
   ("/proc/probe(ascii)\n    switch(ascii)\n        if(48,49) return lookup(ascii)\n    return .\n",true),
   ("/proc/probe(ascii)\n    switch(ascii)\n        if(48 to 57); . += ascii2text(ascii)\n    return .\n",false),
  ]{assert_statement_control_source_has_original_body(source,"probe",expected);}
 }
 #[test]
 fn actual_original_do_while_nested_tail_uses_real_terminal_condition_and_delimiter(){
  for(source,expected)in[
   ("/proc/probe(value)\n    do\n        if(value)\n            value -= 1\n    while(value)\n    return value\n",true),
   ("/proc/probe(value)\n    do\n        if(value)\n            value -= 1\n    while(value)\n/proc/later()\n    return 0\n",true),
   ("/proc/probe(value)\n    do\n        if(value)\n            break\n    while(value)\n    return value\n",true),
   ("/proc/probe(value)\n    do;\n        if(value)\n            value -= 1\n    while(value)\n",false),
  ]{assert_statement_control_source_has_original_body(source,"probe",expected);}
 }
 fn actual_next_whole_helper(path:&str,name:&str){
  let file=std::fs::read_to_string(std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../..").join(path)).unwrap();let needle=format!("/proc/{name}(");let start=file.find(&needle).unwrap();let end=file[start+1..].find("/proc/").map_or(file.len(),|at|start+1+at);
  assert_statement_control_source_has_original_body(&file[start..end],name,true);
 }

 #[test]
 fn actual_original_primary_in_whole_spatial_helpers_use_current_authored_source(){
  for name in ["locate_on","locate_in_area"]{actual_next_whole_helper("code/engine/refs/containment/spatial.dm",name);}
 }
 #[test]
 fn actual_original_primary_in_authored_expression_roles_and_warning_boundaries(){
  for(leaf,expected)in[
   ("return input(user, message, title, default) as null|anything in items",true),
   ("var/area/overmap/map = locate() in world\n    return map",true),
   ("return !!(locate(/obj/item/mecha_parts/mecha_equipment/tool/passenger) in slot_contents())",true),
   ("if(anchored || (locate(/obj/structure/table) in contents_of(loc)))\n        return 1\n    return 0",true),
   ("if(!(locate(integrated_ai()) in ai_card))\n        return 1\n    return 0",true),
   ("return input() in items as text",false),
   ("return locate(type in items)",false),
   ("return locate(1,2,3) in items",false),
   ("return input() in (++index < limit)",false),
  ]{let source=format!("/proc/probe(user,message,title,default,items,anchored,type,ai_card,index,limit)\n    {leaf}\n");assert_statement_control_source_has_original_body(&source,"probe",expected);}
 }

 #[test]fn actual_original_delete_keeps_authored_command_context_and_expression_distinction(){
  let file=std::fs::read_to_string(std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../../code/world/systems/garbage.dm")).unwrap();
  let line=file.lines().find(|line|line.trim_start().starts_with("del(D) // ALLOW(scheduler): GC:")).expect("actual authored GC delete command");
  let source=format!("/proc/probe(D)\n{}\n    return 0\n",line);assert_statement_control_source_has_original_body(&source,"probe",true);
  for(leaf,wanted)in[("del D\n    return 0",true),("del(D)\n    return del(D)",true),("del(D,other)",false),("del",false),("del(++index < limit)",false)]{
   let source=format!("/proc/probe(D,other,index,limit)\n    {leaf}\n");assert_statement_control_source_has_original_body(&source,"probe",wanted);
  }
 }

 #[test]fn actual_original_authored_operator_roots_and_conditions_retain_full_body_loans(){
  for(path,prefix)in[("code/engine/time/scheduler.dm","rec.queued &= ~bit"),("code/engine/time/records.dm","rec.pend_union &= ~rec.att_pend[i]"),("code/library/capabilities/capabilities.dm","caps ||= list()"),("code/library/helpers/gender.dm","temp_gender ||= get_visible_gender()"),("code/content/client/verbs/character_directory.dm","can_set_prefs &&= !!user.client.prefs")]{
   let file=std::fs::read_to_string(std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../..").join(path)).unwrap();let line=file.lines().find(|line|line.trim_start().starts_with(prefix)).expect("actual authored operator statement");
   let source=format!("/proc/probe(rec,bit,i,caps,temp_gender,can_set_prefs,user)\n    {}\n    return 0\n",line.trim_start());assert_statement_control_source_has_original_body(&source,"probe",true);
  }
  for(leaf,wanted)in[("if(between ~= via)\n        return ~mask\n    return 0",true),("return flat_size ~! add_size",true),("return caps ||= values",false),("var/local = caps &&= values",false),("consume(caps ||= values)",false),("caps ||= values = other",false)]{
   let source=format!("/proc/probe(between,via,mask,flat_size,add_size,caps,values,other)\n    {leaf}\n");assert_statement_control_source_has_original_body(&source,"probe",wanted);
  }
 }

 #[test]fn actual_original_dynamic_dispatch_keeps_authored_timer_and_change_statement_roles(){
  for(path,prefix)in[("code/engine/time/timers.dm","return call(proc_ref)(arglist(call_args || list()))"),("code/engine/time/timers.dm","return call(E, proc_ref)(arglist(call_args || list()))"),("code/engine/time/timers.dm","state[2] = call(proc_ref)(arglist(call_args || list()))"),("code/engine/time/timers.dm","call(proc_ref)(arglist(call_args))"),("code/engine/change/state.dm","return !!call(E, R.when)()")]{
   let file=std::fs::read_to_string(std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../..").join(path)).unwrap();let line=file.lines().find(|line|line.trim_start().starts_with(prefix)).expect("actual authored dynamic call source");let source=format!("/proc/probe(proc_ref,call_args,state,E,R)\n    {}\n",line.trim_start());assert_statement_control_source_has_original_body(&source,"probe",true);
  }
  for(leaf,wanted)in[("var/result = call(target,name)(value)\n    return result",true),("if(call(target)(value))\n        return 1\n    return 0",true),("call(target)(value)",true),("call(target)",false),("call(target)(name = value)",false),("call(target)(value = other = third)",false),("call(target)(value;other)",false)]{let source=format!("/proc/probe(target,name,value,other,third)\n    {leaf}\n");assert_statement_control_source_has_original_body(&source,"probe",wanted);}
 }
 #[test]fn actual_original_whole_guid_keeps_const_declarations_and_real_interpolations(){actual_next_whole_helper("code/library/helpers/guid.dm","GUID")}
 #[test]fn actual_original_whole_mixcolors_keeps_two_clause_prefix_test(){actual_next_whole_helper("code/library/helpers/game.dm","MixColors")}
 #[test]fn actual_original_whole_hex_sanitizer_keeps_inline_range_effects(){actual_next_whole_helper("code/library/helpers/sanitize_values.dm","sanitize_hexcolor")}
 #[test]fn actual_original_whole_shell_url_scrub_keeps_nested_do_tail(){actual_next_whole_helper("code/library/helpers/shell.dm","shell_url_scrub")}
 #[test]fn actual_original_whole_string_list_keeps_returned_cache_assignment(){actual_next_whole_helper("code/library/helpers/string_lists.dm","string_list")}
 #[test]fn actual_original_whole_icon_state_counts_keeps_dynamic_dot_key(){actual_next_whole_helper("code/library/helpers/icons/icon_html.dm","build_icon_state_dir_counts")}
 #[test]fn actual_original_whole_remove_image_keeps_safe_member_compound_write(){actual_next_whole_helper("code/library/helpers/game.dm","remove_image_from_client")}
 #[test]
 fn actual_original_reverse_range_keeps_postfix_argument_values_and_refuses_root_value_roles() {
     let file = include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../../code/host/helpers/_lists.dm")).replace("\r\n", "\n");
     let start = file.find("/proc/reverse_range(").unwrap();
     let end = file[start + 1..].find("\n/proc/").map(|at| start + 1 + at).unwrap();
     let source = &file[start..end];
     assert!(source.contains("inserted_list.Swap(start++, end--)"));
     for (text, expected) in [
         (source.to_owned(), true),
         (source.replace("Swap(start++, end--)", "Swap(++start, end--)"), false),
         (source.replace("Swap(start++, end--)", "Swap(start++, --end)"), false),
         (source.replace("Swap(start++, end--)", "Swap(start++, inserted_list.end--)"), false),
         (source.replace("inserted_list.Swap(start++, end--)", "return start++"), false),
         (source.replace("inserted_list.Swap(start++, end--)", "start = end--"), false),
     ] {
         let db = Arc::new(QueryDb::default());
         let front = issued_original_fixture(&db, &text);
         let input = original_input(&front, "reverse_range");
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let disposition = body.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = disposition? else {
                     panic!("actual reverse_range must be available with prefix companion packet");
                 };
                 assert!(proof.belongs_to(&body));
             } else {
                 assert!(!matches!(disposition, Ok(dm_tree::frontend::OriginalBodyDisposition::Available(_))), "{text}");
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]
 fn actual_original_empty_holder_loop_and_decrement_text_loop_keep_real_body_forms() {
     let file = include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../../code/host/helpers/atom_queries.dm")).replace("\r\n", "\n");
     let start = file.find("/proc/get_holder_at_turf_level(").unwrap();
     let end = file[start + 1..].find("\n/atom/proc/").map(|at| start + 1 + at).unwrap();
     let holder = &file[start..end];
     assert!(holder.contains("for(A=O, A && !isturf(A.loc), A=A.loc);"));
     for (source, expected) in [
         (holder.to_owned(), true),
         (holder.replace("A=A.loc);", "A=A.loc)"), false),
         (holder.replace("A=A.loc);", "A=A.loc) /* ; */"), false),
         (holder.replace("A=O, A &&", "A=O; A &&"), false),
     ] {
         let db = Arc::new(QueryDb::default());
         let front = issued_original_fixture(&db, &source);
         let input = original_input(&front, "get_holder_at_turf_level");
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let disposition = body.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = disposition? else { panic!("actual explicitly empty loop"); };
                 assert!(proof.belongs_to(&body));
                 let parsed = product.parsed().unwrap().statement_storage().parsed();
                 let loop_node = parsed.statements.iter().find(|node| matches!(node.kind, dm_syntax::StatementKind::For { .. })).unwrap();
                 assert!(matches!(&loop_node.kind, dm_syntax::StatementKind::For {
                     control: dm_syntax::ForControl::CStyle { initializer: Some(dm_syntax::ForInitializer::Expr(_)), .. }, body,
                 } if body.is_empty()));
                 assert!(parsed.local_variables.entries().unwrap().iter().all(|row|
                     !matches!(row.source_kind, dm_syntax::LocalSourceKind::ForBinding | dm_syntax::LocalSourceKind::ForInitializer)));
             } else {
                 assert!(!matches!(disposition, Ok(dm_tree::frontend::OriginalBodyDisposition::Available(_))), "{source}");
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
     let file = include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../../code/host/helpers/text.dm")).replace("\r\n", "\n");
     let start = file.find("/proc/trim_right(").unwrap();
     let end = file[start + 1..].find("\n/proc/").map(|at| start + 1 + at).unwrap();
     let marker_file = include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../../code/defines/engine/declare/markers.dm"));
     let reads_from = marker_file.lines().find(|line| line.starts_with("#define READS_FROM(")).unwrap();
     let source = format!("{reads_from}\n{}", &file[start..end]);
     assert!(source.contains("for (var/i = length(text), i > 0, i--)"));
     let db = Arc::new(QueryDb::default());
     let front = issued_original_fixture(&db, &source);
     let input = original_input(&front, "trim_right");
     let product = db.syntax_product_checked(&input).unwrap();
     setting_syntax::with_setting_admission(&db.body_charge, |admission| {
         let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
         let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = body.original_code_disposition()? else { panic!("actual decrement classic loop"); };
         assert!(proof.belongs_to(&body));
         Ok::<(), BodySyntaxFailure>(())
     }).unwrap();
 }

 #[test]
 fn actual_original_absolute_new_reuses_area_queries_and_typed_exception_arguments() {
     let file = include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../../code/host/helpers/area_queries.dm")).replace("\r\n", "\n");
     for name in ["get_current_area_turfs", "get_area_all_atoms", "get_current_area_atoms"] {
         let marker = format!("/proc/{name}(");
         let start = file.find(&marker).unwrap();
         let end = file[start + 1..].find("\n/proc/").map_or(file.len(), |at| start + 1 + at);
         let source = &file[start..end];
         assert!(source.contains("new/list()"));
         let db = Arc::new(QueryDb::default());
         let front = issued_original_fixture(&db, source);
         let input = original_input(&front, name);
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = body.original_code_disposition()? else {
                 panic!("actual area query static constructor must be available: {name}");
             };
             assert!(proof.belongs_to(&body));
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
     // Preserve the real typed interpolation, empty text and numeric arguments;
     // do not substitute a guessed literal or target model for /exception.
     let file = include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../../code/host/helpers/stack_trace.dm")).replace("\r\n", "\n");
     let source = &file[file.find("/proc/dq_report_caught(").unwrap()..];
     assert!(source.contains("new /exception(\"non-exception thrown: [E]\", \"\", 0)"));
     let db = Arc::new(QueryDb::default());
     let front = issued_original_fixture(&db, source);
     let input = original_input(&front, "dq_report_caught");
     let product = db.syntax_product_checked(&input).unwrap();
     setting_syntax::with_setting_admission(&db.body_charge, |admission| {
         let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
         let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = body.original_code_disposition()? else {
             panic!("actual typed exception constructor must be available");
         };
         assert!(proof.belongs_to(&body));
         Ok::<(), BodySyntaxFailure>(())
     }).unwrap();
 }

 #[test]
 fn actual_original_md5asfile_power_uses_the_real_wrap_macro_and_whole_body() {
     let icons = include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../../code/host/helpers/icons.dm")).replace("\r\n", "\n");
     let math = include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../../code/defines/host/math.dm"));
     let actual_wrap = math.lines().find(|line|line.starts_with("#define WRAP(")).unwrap();
     let start=icons.find("/proc/md5asfile(").unwrap();
     let end=icons[start+1..].find("\n/proc/").map(|at|start+1+at).unwrap();
     let actual=&icons[start..end];
     assert!(actual.contains("notch = WRAP(notch+1, 0, 2**15)"));
     let source=format!("{actual_wrap}\n{actual}");
     let db=Arc::new(QueryDb::default());
     let front=issued_original_fixture(&db,&source);
     let input=original_input(&front,"md5asfile");
     let product=db.syntax_product_checked(&input).unwrap();
     setting_syntax::with_setting_admission(&db.body_charge,|admission| {
         let body=input.bind_original_product_checked(product.parsed().unwrap(),admission)?;
         let dm_tree::frontend::OriginalBodyDisposition::Available(proof)=body.original_code_disposition()? else {
             panic!("actual md5asfile whole body with real numeric WRAP expansion");
         };
         assert!(proof.belongs_to(&body));
         Ok::<(),BodySyntaxFailure>(())
     }).unwrap();
 }

 #[test]
 fn actual_original_stripped_input_helpers_keep_their_real_questions_and_type_unions() {
     let file=include_str!(concat!(env!("CARGO_MANIFEST_DIR"),"/../../../../code/host/helpers/text.dm")).replace("\r\n","\n");
     let misc=include_str!(concat!(env!("CARGO_MANIFEST_DIR"),"/../../../../code/defines/content/misc.dm"));
     let actual_max=misc.lines().find(|line|line.split_whitespace().nth(1)==Some("MAX_MESSAGE_LEN")).unwrap();
     for(name,wanted)in[("stripped_input","text"),("stripped_multiline_input","message")] {
         let start=file.find(&format!("/proc/{name}(")).unwrap();
         let end=file[start+1..].find("\n/proc/").map(|at|start+1+at).unwrap();
         let actual=&file[start..end];
         assert!(actual.contains(&format!("input(user, message, title, default) as {wanted}|null")));
         let source=format!("{actual_max}\n{actual}");
         let db=Arc::new(QueryDb::default());let front=issued_original_fixture(&db,&source);let input=original_input(&front,name);
         let product=db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge,|admission| {
             let body=input.bind_original_product_checked(product.parsed().unwrap(),admission)?;
             let dm_tree::frontend::OriginalBodyDisposition::Available(proof)=body.original_code_disposition()? else {panic!("whole real input helper: {name}");};
             assert!(proof.belongs_to(&body));
             let storage=product.parsed().unwrap().statement_storage();
             let dm_syntax::StatementKind::Var{value:Some(initializer),..}=&storage.parsed().statements[0].kind else{panic!("actual input local initializer")};
             let form=dm_syntax::native_special_forms::input(initializer).unwrap().unwrap();
             assert_eq!(form.types,[wanted,"null"]);assert!(form.in_list.is_none());assert_eq!(form.args.len(),4);
             for(argument,wanted)in form.args.iter().zip(["user","message","title","default"]) {
                 assert!(matches!(&argument.kind,dm_syntax::ExprKind::Ident(name)if name==wanted));
             }
             Ok::<(),BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]
 fn actual_original_icon_helpers_reuse_typed_float_and_name_addition_read_composition() {
     let file = include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../../code/host/helpers/icons.dm")).replace("\r\n", "\n");
     let appearance = include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../../code/defines/base/appearance.dm"));
     let actual_ui = appearance.lines().find(|line| line.split_whitespace().nth(1) == Some("APPEARANCE_UI")).unwrap();
     for name in ["sort_atoms_by_layer", "gen_hud_image"] {
         let start = file.find(&format!("/proc/{name}(")).unwrap();
         let end = file[start + 1..].find("\n/proc/").map(|at| start + 1 + at).unwrap();
         let actual = &file[start..end];
         let source = format!("{actual_ui}\n{actual}");
         if name == "gen_hud_image" { assert!(source.contains("img.layer = MOB_LAYER-0.2")); }
         else { assert!(source.contains("result[gap+i]")); }
         let db = Arc::new(QueryDb::default());
         let front = issued_original_fixture(&db, &source);
         let input = original_input(&front, name);
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = body.original_code_disposition()? else { panic!("actual icon helper composition: {name}"); };
             assert!(proof.belongs_to(&body));
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]
 fn actual_original_get_area_turfs_inline_each_uses_existing_header_and_actual_assignment_head() {
     let file = include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../../code/host/helpers/area_queries.dm")).replace("\r\n", "\n");
     let start = file.find("/proc/get_area_turfs(").unwrap();
     let end = file[start + 1..].find("\n/proc/").map(|at| start + 1 + at).unwrap();
     let actual = &file[start..end];
     let leaf = "for(var/turf/T in N) turfs += T";
     assert!(actual.contains(leaf));
     for (source, expected) in [
         (actual.to_owned(), true),
         (actual.replace(leaf, "for(var/turf/T in N); turfs += T"), false),
         (actual.replace(leaf, "for(var/turf/T in N) turfs.field += T"), false),
         (actual.replace(leaf, "for(var/turf/T in N) turfs[T] += T"), false),
         (actual.replace(leaf, "for(var/turf/T in N) return T"), false),
         (actual.replace(leaf, "for(var/turf/T in N) turfs += T++"), false),
         (actual.replace(leaf, "for(var/i=0, i<1, i++) turfs += i"), false),
     ] {
         let db = Arc::new(QueryDb::default());
         let front = issued_original_fixture(&db, &source);
         let input = original_input(&front, "get_area_turfs");
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let disposition = body.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = disposition? else {
                     panic!("actual complete get_area_turfs inline ForList must be available");
                 };
                 assert!(proof.belongs_to(&body));
             } else {
                 assert!(!matches!(disposition, Ok(dm_tree::frontend::OriginalBodyDisposition::Available(_))), "{source}");
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]
 fn actual_original_typecache_cohort_keeps_real_for_list_call_children() {
     let file=include_str!(concat!(env!("CARGO_MANIFEST_DIR"),"/../../../../code/host/helpers/_lists.dm")).replace("\r\n","\n");
     fn actual_proc<'a>(file:&'a str,name:&str)->&'a str {
         let head=format!("/proc/{name}(");
         let start=file.find(&head).unwrap();
         let tail=&file[start..];
         let end=tail.find("\n/proc/").unwrap_or(tail.len());
         &tail[..end]
     }
     // These are the three consecutive authored typecache helpers. The one
     // call dependency is also its real implementation, never a test stub.
     let names=["typecache_filter_list","typecache_filter_multi_list_exclusion","typecacheof","subtypesof"];
     let mut source=String::from("#define TRUE 1\n#define FALSE 0\n");
     for name in names { source.push_str(actual_proc(&file,name)); source.push('\n'); }
     assert!(source.contains("types = ignore_root_path ? subtypesof(path) : typesof(path)"));
     assert!(source.contains("for(var/T in subtypesof(P))"));
     assert!(source.contains("for(var/T in typesof(P))"));
     let db=Arc::new(QueryDb::default());
     let front=issued_original_fixture(&db,&source);
     for (name,expected_loops,expected_calls) in [
         ("typecache_filter_list",1,0),
         ("typecache_filter_multi_list_exclusion",1,0),
         ("typecacheof",5,2),
         ("subtypesof",0,0),
     ] {
         let input=original_input(&front,name);
         let product=db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge,|admission| {
             let body=input.bind_original_product_checked(product.parsed().unwrap(),admission)?;
             let dm_tree::frontend::OriginalBodyDisposition::Available(proof)=body.original_code_disposition()? else {
                 panic!("actual authored helper {name} must have Original grammar");
             };
             assert!(proof.belongs_to(&body));
             let parsed=product.parsed().unwrap().statement_storage().parsed();
             assert!(parsed.diagnostics.is_empty());
             let mut pending=parsed.statements.iter().collect::<Vec<_>>();
             let (mut loops,mut calls)=(0,0);
             while let Some(statement)=pending.pop() {
                 match &statement.kind {
                     dm_syntax::StatementKind::If{then_branch,else_branch,..}=>{
                         pending.extend(then_branch); pending.extend(else_branch);
                     },
                     dm_syntax::StatementKind::For{control:dm_syntax::ForControl::Each{source_binding,iterable,..},body}=>{
                         loops+=1;
                         assert!(source_binding.is_some(),"actual for variable declaration remains source-authenticated");
                         if let dm_syntax::ExprKind::Call{callee,args}=&iterable.kind {
                             calls+=1;
                             assert!(matches!(&callee.kind,dm_syntax::ExprKind::Ident(name)if matches!(name.as_str(),"subtypesof"|"typesof")));
                             assert!(matches!(args.as_slice(),[argument]if matches!(&argument.kind,dm_syntax::ExprKind::Ident(name)if name=="P")));
                         }
                         pending.extend(body);
                     },
                     _=>(),
                 }
             }
             assert_eq!(loops,expected_loops,"{name}");
             assert_eq!(calls,expected_calls,"{name}");
             Ok::<(),BodySyntaxFailure>(())
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
 fn actual_original_indented_switch_keeps_typed_cases_ranges_order_and_real_cursor() {
     let fixture = r#"
/datum/tag
/proc/probe(value, datum/holder)
    switch(value)
        if("alpha", /datum/tag)
            return 0
        if(-2 to -1, 4)
            return 1
        if(1 || 2)
            return 2
        else
            return 3
"#;
     for text in [fixture.to_owned(), fixture.replace("switch(value)", "switch(holder.kind)")] {
         let db = Arc::new(QueryDb::default());
         let front = issued_original_fixture(&db, &text);
         let input = original_input(&front, "probe");
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = body.original_code_disposition()? else {
                 panic!("the consumed Original indented switch must be available");
             };
             assert!(proof.belongs_to(&body));
             let storage = product.parsed().unwrap().statement_storage();
             let dm_syntax::StatementKind::Switch { cases, else_branch, default_present, .. } =
                 &storage.parsed().statements[0].kind else { panic!("actual Switch"); };
             assert_eq!(cases.len(), 3);
             assert!(*default_present);
             assert_eq!(else_branch.len(), 1);
             assert!(matches!(&cases[0].alternatives[..], [
                 dm_syntax::SwitchAlternative::Exact(_), dm_syntax::SwitchAlternative::Exact(_),
             ]));
             assert!(matches!(&cases[1].alternatives[..], [
                 dm_syntax::SwitchAlternative::Range(_, _), dm_syntax::SwitchAlternative::Exact(_),
             ]));
             assert!(matches!(&cases[2].alternatives[..], [
                 dm_syntax::SwitchAlternative::Exact(dm_syntax::Expr { kind: dm_syntax::ExprKind::Binary { op, .. }, .. }),
             ] if op == "||"));
             for case in cases {
                 assert!(case.original_site.cursor.is_ok());
                 for alternative in &case.alternatives {
                     let values = match alternative {
                         dm_syntax::SwitchAlternative::Exact(value) => [Some(value), None],
                         dm_syntax::SwitchAlternative::Range(lower, upper) => [Some(lower), Some(upper)],
                     };
                     for value in values.into_iter().flatten() {
                         assert!(case.original_site.header.start <= value.span.start);
                         assert!(value.span.end <= case.original_site.header.end);
                     }
                 }
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]
 fn actual_original_broader_switch_keeps_inline_and_separator_gaps_explicit() {
     let fixture = "/proc/probe(value)\n    switch(value)\n        if(\"alpha\")\n            return 1\n        else\n            return 2\n";
     for (text, expected) in [
         // Exact single-case inline value return is now certified by its own
         // actual head token loan and owned case cursor, not by normalization.
         (fixture.replace("if(\"alpha\")\n            return 1", "if(\"alpha\") return 1"), true),
         (fixture.replace("if(\"alpha\")", "if(\"alpha\",)"), false),
         (fixture.replace("if(\"alpha\")", "if(,\"alpha\")"), false),
         (fixture.replace("if(\"alpha\")", "if(1 to)"), false),
         (fixture.replace("if(\"alpha\")", "if(value = 1)"), false),
     ] {
         let db = Arc::new(QueryDb::default());
         let front = issued_original_fixture(&db, &text);
         let input = original_input(&front, "probe");
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let disposition=body.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof)=disposition? else { panic!("exact supported inline switch return: {text}"); };
                 assert!(proof.belongs_to(&body));
                 let parsed=product.parsed().unwrap().statement_storage().parsed();
                 let dm_syntax::StatementKind::Switch{cases,..}=&parsed.statements[0].kind else{panic!("actual switch")};
                 assert_eq!(cases.len(),1);assert!(cases[0].original_site.cursor.is_ok());
             } else {
                 assert!(!matches!(disposition, Ok(dm_tree::frontend::OriginalBodyDisposition::Available(_))), "{text}");
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }


 #[test]
 fn actual_original_silicon_ash_parent_call_retains_whole_authored_helper_and_literal(){
  let path=std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../../code/content/mob");
  let silicon=std::fs::read_to_string(path.join("living/silicon/death.dm")).unwrap().replace("\r\n","\n");
  let base=std::fs::read_to_string(path.join("death.dm")).unwrap().replace("\r\n","\n");
  fn whole<'a>(source:&'a str,header:&str)->&'a str{
   let start=source.find(header).unwrap();let tail=&source[start..];
   let end=tail[1..].find("\n/").map_or(tail.len(),|at|at+2);&tail[..end]
  }
  let authored=whole(&silicon,"/mob/living/silicon/ash()\n");
  assert_eq!(authored,"/mob/living/silicon/ash()\n\t..(\"dust-r\")\n\n");
  let parent=whole(&base,"/mob/proc/ash(anim=\"dust-m\")\n");
  assert!(parent.contains("\tdisintegrate(anim, null, FALSE)\n"));
  // Both actual methods are retained. Only the child body's syntax is asked
  // here; this is not parent dependency closure or full Checker qualification.
  for(child,wanted)in[(authored.to_owned(),true),
   (authored.replace("..(\"dust-r\")","..(\"dust-r\",)"),true),
   (authored.replace("..(\"dust-r\")",". .(\"dust-r\")"),false),
   (authored.replace("..(\"dust-r\")","..(\"dust-r\")()"),false)]{
   let source=format!("{parent}\n{child}");let db=Arc::new(QueryDb::default());let front=issued_original_fixture(&db,&source);
   let view=front.source_view().unwrap();let archive=view.archive();
   let ordinal=archive.occurrences().iter().enumerate().find(|(_,row)|{
    let member=view.tree().member(row.member).unwrap();
    member.name==dm_ir::SymbolId::of("ash")
     &&view.tree().type_node(member.owner).unwrap().path==dm_ir::SymbolId::of("/mob/living/silicon")
   }).unwrap().0;
   let input=Arc::clone(&archive.syntax_inputs().unwrap()[ordinal]);let product=db.syntax_product_checked(&input).unwrap();
   setting_syntax::with_setting_admission(&db.body_charge,|admission|{
    let body=input.bind_original_product_checked(product.parsed().unwrap(),admission)?;
    let result=body.original_code_disposition();
    if wanted{
     let dm_tree::frontend::OriginalBodyDisposition::Available(proof)=result?else{panic!("whole actual silicon ash helper")};assert!(proof.belongs_to(&body));
     let parsed=product.parsed().unwrap().statement_storage().parsed();
     let [statement]=parsed.statements.as_slice()else{panic!("one authored parent-call statement")};
     let dm_syntax::StatementKind::Call(expression)=&statement.kind else{panic!("same Call statement")};
     let dm_syntax::ExprKind::Call{callee,args}=&expression.kind else{unreachable!()};
     assert!(matches!(&callee.kind,dm_syntax::ExprKind::Ident(name)if name==".."));
     assert!(matches!(args.as_slice(),[argument]if matches!(&argument.kind,dm_syntax::ExprKind::Literal(value)
      if matches!(value.original_value(),Some(dm_syntax::OriginalTokenValue::String(text))if text=="dust-r"))));
    }else{assert!(!matches!(result,Ok(dm_tree::frontend::OriginalBodyDisposition::Available(_))),"{child}");}
    Ok::<(),BodySyntaxFailure>(())
   }).unwrap();
  }
 }

 #[test]
 fn actual_original_deep_copy_uses_the_return_slot_and_exact_current_procedure_call() {
     let file = include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../../code/host/helpers/_lists.dm")).replace("\r\n", "\n");
     let start = file.find("/proc/deepCopyList(").unwrap();
     let tail = &file[start..];
     let end = tail.find("\n/proc/uniqueList(").unwrap();
     let source = &tail[..end];
     assert!(source.contains(".[i] = .(.[i])"));
     for (text, expected) in [
         (source.to_owned(), true),
         (source.replace(".[i] = .(.[i])", "return .(.[i])"), true),
         (source.replace(".[i] = .(.[i])", ".[i] += .(.[i])"), false),
         (source.replace(".[i] = .(.[i])", ".[i] = .(i)"), true),
         (source.replace(".[i] = .(.[i])", ".[i] = .(.[i], i)"), true),
         (source.replace(".[i] = .(.[i])", ".[i] = ..(.[i])"), true),
         (source.replace(".[i] = .(.[i])", ".[i][i] = .(.[i])"), false),
         (source.replace("islist(.[i])", "islist(.?[i])"), false),
     ] {
         let db = Arc::new(QueryDb::default());
         let front = issued_original_fixture(&db, &text);
         let input = original_input(&front, "deepCopyList");
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let disposition = body.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = disposition? else {
                     panic!("actual Original return-slot recursion is available");
                 };
                 assert!(proof.belongs_to(&body));
             } else {
                 assert!(!matches!(disposition, Ok(dm_tree::frontend::OriginalBodyDisposition::Available(_))), "{text}");
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]
 fn actual_original_duplicate_key_update_is_only_an_indexed_statement() {
     let file = include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../../code/host/helpers/_lists.dm")).replace("\r\n", "\n");
     let start = file.find("/proc/avoid_assoc_duplicate_keys(").unwrap();
     let tail = &file[start..];
     let end = tail.find("\n// Generic listoflist").unwrap();
     let source = &tail[..end];
     assert!(source.contains("used_key_list[input_key]++"));
     for (text, expected) in [
         (source.to_owned(), true),
         (source.replace("used_key_list[input_key]++", "used_key_list[input_key]--"), true),
         (source.replace("used_key_list[input_key]++", "return used_key_list[input_key]++"), false),
         (source.replace("used_key_list[input_key]++", "var/value = used_key_list[input_key]++"), false),
         (source.replace("used_key_list[input_key]++", "consume(used_key_list[input_key]++)"), false),
         (source.replace("used_key_list[input_key]++", "++used_key_list[input_key]"), false),
         (source.replace("used_key_list[input_key]++", "used_key_list?[input_key]++"), false),
         (source.replace("used_key_list[input_key]++", "used_key_list[input_key][1]++"), false),
     ] {
         let db = Arc::new(QueryDb::default());
         let front = issued_original_fixture(&db, &text);
         let input = original_input(&front, "avoid_assoc_duplicate_keys");
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let disposition = body.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = disposition? else {
                     panic!("actual indexed postfix statement is available");
                 };
                 assert!(proof.belongs_to(&body));
             } else {
                 assert!(!matches!(disposition, Ok(dm_tree::frontend::OriginalBodyDisposition::Available(_))), "{text}");
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]
 fn actual_original_icon_read_followers_preserve_source_conditions_and_safe_ast() {
     let file = include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../../code/host/helpers/icons.dm")).replace("\r\n", "\n");
     // Exact authored condition and initializer, tested in small declared
     // bodies. This does not claim the remaining icon helper is witnessed.
     let condition = file.lines().find(|line| line.contains("ignoreGreyscale && rgb2num(this_color, COLORSPACE_HSV)[2] == 0")).unwrap().trim();
     let initializer = file.lines().find(|line| line.trim() == "var/dirs = dir_counts?[state]").unwrap().trim();
     let condition_source = format!("/proc/probe(ignoreGreyscale, this_color)\n    {condition}\n        return 1\n    return 0\n");
     let safe_source = format!("/proc/probe(list/dir_counts, state)\n    {initializer}\n    return dirs\n");
     for (text, expected) in [
         (condition_source.clone(), true),
         (safe_source.clone(), true),
         (condition_source.replace("[2]", "[2](this_color)"), false),
         (safe_source.replace("var/dirs = dir_counts?[state]", "dir_counts?[state] = state"), false),
         (safe_source.replace("dir_counts?[state]", "dir_counts? [state]"), false),
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
                     panic!("actual icon read followers must be available: {text}");
                 };
                 assert!(proof.belongs_to(&body));
             } else {
                 assert!(!matches!(disposition, Ok(dm_tree::frontend::OriginalBodyDisposition::Available(_))), "{text}");
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]
 fn actual_original_dummy_savefile_keeps_whole_authored_try_catch_and_throw() {
     // This control requires BOTH the closed Try/Catch packet and the separate
     // Throw packet. It must fail at a remaining real frontier rather than
     // omit or replace a production statement to manufacture whole coverage.
     let file = include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../../code/host/helpers/icons.dm")).replace("\r\n", "\n");
     let start = file.find("/proc/get_dummy_savefile(").unwrap();
     let end = file[start+1..].find("\n/proc/").map(|at|start+1+at).unwrap();
     let source = &file[start..end];
     assert!(source.contains("catch(var/exception/error)"));
     assert!(source.contains("throw EXCEPTION("));
     let db = Arc::new(QueryDb::default());
     // EXCEPTION is the actual issued OriginalChecker0290 default macro from
     // dm-preprocess/original_default_macro_data.rs, not a fixture substitute.
     let front = issued_original_fixture(&db, source);
     let input = original_input(&front, "get_dummy_savefile");
     let product = db.syntax_product_checked(&input).unwrap();
     setting_syntax::with_setting_admission(&db.body_charge, |admission| {
         let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
         let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = body.original_code_disposition()? else { panic!("whole actual get_dummy_savefile must keep every statement"); };
         assert!(proof.belongs_to(&body));
         let parsed = product.parsed().unwrap().statement_storage().parsed();
         let caught = parsed.statements.iter().find_map(|statement| match &statement.kind {
             dm_syntax::StatementKind::Try { catch_parameter_count, catch_body, .. } => {
                 assert_eq!(*catch_parameter_count, 1); Some(catch_body)
             }, _ => None,
         }).unwrap();
         let dm_syntax::StatementKind::If { then_branch, .. } = &caught[0].kind else { panic!("actual conditional rethrow"); };
         assert!(matches!(&then_branch[0].kind, dm_syntax::StatementKind::Throw(_)), "actual throw statement retained");
         Ok::<(), BodySyntaxFailure>(())
     }).unwrap();
 }

 #[test]
 fn actual_original_try_catch_helpers_need_exact_heads_paths_and_block_links() {
     let file = include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../../code/host/helpers/text.dm")).replace("\r\n", "\n");
     let start = file.find("/proc/safe_json_decode(").unwrap();
     let end = file[start+1..].find("\n/proc/").map(|at|start+1+at).unwrap();
     let actual = &file[start..end];
     let catch_line = actual.lines().find(|line|line.trim_start().starts_with("catch")).unwrap();
     let icons = include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../../code/host/helpers/icons.dm")).replace("\r\n", "\n");
     let real_typed_catch = icons.lines().find(|line|line.trim() == "catch(var/exception/error)").unwrap();
     // Whole real bare-catch helper first. Other rows are explicitly authored
     // header-shape variants, not claims about the whole get_dummy_savefile.
     for (text, expected) in [
         (actual.to_owned(), true),
         (actual.replace(catch_line, real_typed_catch), true),
         (actual.replace(catch_line, "\tcatch(var/absent/error)"), true),
         (actual.replace(catch_line, "\tcatch()"), false),
         (actual.replace(catch_line, "\tcatch(var/error)"), false),
         (actual.replace(catch_line, "\tcatch(exception/error)"), false),
         (actual.replace(catch_line, "\tcatch(var/static/error)"), false),
         (actual.replace(catch_line, "\tcatch(var/exception/error, var/exception/other)"), false),
         (actual.replace(catch_line, "\tcatch(var/datum/exception/error)"), false),
         (actual.replace("\ttry\n", "\ttry;\n"), false),
         (actual.replace(catch_line, "\tcatch;"), false),
     ] {
         let db = Arc::new(QueryDb::default());
         let front = issued_original_fixture(&db, &text);
         let input = original_input(&front, "safe_json_decode");
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let disposition = body.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = disposition? else { panic!("actual try/catch source shape: {text}"); };
                 assert!(proof.belongs_to(&body));
                 let parsed = product.parsed().unwrap().statement_storage().parsed();
                 let dm_syntax::StatementKind::Try { catch_parameter_count, .. } = &parsed.statements[0].kind else { panic!("same native Try"); };
                 assert_eq!(*catch_parameter_count, usize::from(text.contains("catch(var/")));
             } else {
                 assert!(!matches!(disposition, Ok(dm_tree::frontend::OriginalBodyDisposition::Available(_))), "{text}");
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]
 fn actual_original_throw_requires_exact_keyword_child_and_keeps_ordinary_names() {
     for(source,wanted)in[
         ("/proc/probe(value)\n    throw value\n",true),
         ("/proc/probe(value)\n    throw(value)\n",true),
         ("/proc/probe(value)\n    throw -value\n",true),
         ("/proc/probe()\n    throw\"message\"\n",true),
         ("/proc/probe(value)\n    throw value = 1\n",true),
         ("/proc/probe(value)\n    thrower(value)\n",true),
         ("/proc/probe(value)\n    throwable = value\n",true),
         ("/proc/probe(value)\n    throw\n",false),
         ("/proc/probe(value)\n    throw value:field\n",false),
         ("/proc/probe(value)\n    throw value\n        value = 1\n",false),
     ] {
         let db=Arc::new(QueryDb::default());let front=issued_original_fixture(&db,source);let input=original_input(&front,"probe");
         let product=db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge,|admission|{
             let body=input.bind_original_product_checked(product.parsed().unwrap(),admission)?;
             let actual=body.original_code_disposition();
             if wanted {let dm_tree::frontend::OriginalBodyDisposition::Available(proof)=actual? else{panic!("actual throw/name scope: {source}");};assert!(proof.belongs_to(&body));}
             else {assert!(!matches!(actual,Ok(dm_tree::frontend::OriginalBodyDisposition::Available(_))),"{source}");}
             Ok::<(),BodySyntaxFailure>(())
         }).unwrap();
     }
 }
 #[test]
 fn actual_original_scratch_throw_line_preserves_builtin_exception_expansion_and_actual_text() {
     let icons=include_str!(concat!(env!("CARGO_MANIFEST_DIR"),"/../../../../code/host/helpers/icons.dm"));
     let line=icons.lines().find(|line|line.trim_start().starts_with("throw EXCEPTION(")&&line.contains("get_dummy_savefile failed")).unwrap().trim();
     // Explicit isolated syntax fixture: the typed error parameter mirrors
     // the real catch binding. No whole helper or runtime behavior is claimed.
     let source=format!("/proc/probe(exception/error)\n    {line}\n");
     let db=Arc::new(QueryDb::default());let front=issued_original_fixture(&db,&source);let input=original_input(&front,"probe");
     let product=db.syntax_product_checked(&input).unwrap();
     setting_syntax::with_setting_admission(&db.body_charge,|admission|{
         let body=input.bind_original_product_checked(product.parsed().unwrap(),admission)?;
         let dm_tree::frontend::OriginalBodyDisposition::Available(proof)=body.original_code_disposition()? else{panic!("actual exception throw expression");};
         assert!(proof.belongs_to(&body));
         let storage=product.parsed().unwrap().statement_storage();
         let dm_syntax::StatementKind::Throw(value)=&storage.parsed().statements[0].kind else{panic!("actual Throw root");};
         assert!(matches!(&value.kind,dm_syntax::ExprKind::Unary{op,value}if op=="new"&&matches!(&value.kind,dm_syntax::ExprKind::Call{callee,args}if matches!(&callee.kind,dm_syntax::ExprKind::TypePath(path)if path=="/exception")&&args.len()==1)));
         Ok::<(),BodySyntaxFailure>(())
     }).unwrap();
 }

 #[test]
 fn actual_original_sanitize_name_inline_else_requires_exact_keyword_and_assignment() {
     let file = include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../../code/host/helpers/text.dm")).replace("\r\n", "\n");
     let mut lines = file.lines();
     let then = lines.find(|line| line.trim_start().starts_with("if(last_char_group<2)")
         && line.contains("output += ascii2text(ascii_char-32)")).unwrap().trim();
     let other = lines.next().unwrap().trim();
     assert!(other.starts_with("else") && other.contains("output += ascii2text(ascii_char)"));
     // Exact two authored lines, isolated from unrelated switch/loop forms.
     let source = format!("/proc/probe(output, last_char_group, ascii_char)\n    {then}\n    {other}\n    return output\n");
     for (text, expected) in [
         (source.clone(), true),
         (source.replace("output += ascii2text(ascii_char)", "output -= ascii2text(ascii_char)"), true),
         (source.replace("else", "elsewhere"), false),
         (source.replace(other, "else; output += ascii2text(ascii_char)"), false),
         (source.replace("output += ascii2text(ascii_char)", "output() += ascii2text(ascii_char)"), false),
         (source.replace("output += ascii2text(ascii_char)", "output += target.field = ascii_char"), false),
         (source.replace("    return output", "    else output += 1\n    return output"), false),
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
                     panic!("actual final inline ELSE assignment must be available: {text}");
                 };
                 assert!(proof.belongs_to(&body));
                 let storage = product.parsed().unwrap().statement_storage();
                 let dm_syntax::StatementKind::If { else_branch, .. } = &storage.parsed().statements[0].kind
                     else { panic!("actual if with inline else"); };
                 let child = &else_branch[0];
                 assert_eq!(child.span.start, child.header_span.start, "else keyword is outside the actual child span");
                 assert_eq!(text.get(child.header_span.range()).unwrap().trim(), other.strip_prefix("else").unwrap().trim().replace("+=", if text.contains("output -= ascii2text(ascii_char)") { "-=" } else { "+=" }));
             } else {
                 assert!(!matches!(disposition, Ok(dm_tree::frontend::OriginalBodyDisposition::Available(_))), "{text}");
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]
 fn actual_original_icon_initializers_preserve_named_argument_value_roles() {
     let file = include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../../code/host/helpers/icons.dm")).replace("\r\n", "\n");
     let north = file.lines().find(|line| line.trim_start().starts_with("var/icon/north = getFlatIcon(")).unwrap();
     let text = format!("/proc/probe(atom/A, I)\n{north}\n    var/mutable_appearance/overlay = mutable_appearance(I.icon, I.icon_state, plane = 8, alpha = I.alpha)\n    return north\n");
     for (text, expected) in [
         (text.clone(), true),
         (text.replace("defdir=NORTH", "A.defdir=NORTH"), false),
         (text.replace("defdir=NORTH", "defdir+=NORTH"), false),
         (text.replace("plane = 8", "plane = layer = 8"), false),
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
                     panic!("actual named value calls must be available");
                 };
                 assert!(proof.belongs_to(&body));
             } else {
                 assert!(!matches!(disposition, Ok(dm_tree::frontend::OriginalBodyDisposition::Available(_))), "{text}");
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 fn actual_original_sanitizer_assignment_keeps_input_as_the_bare_formal() {
     let file = include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../../code/host/helpers/text.dm")).replace("\r\n", "\n");
     let line = file.lines().find(|line| line.trim() == "input = copytext(input,1,max_length)").unwrap();
     let text = format!("/proc/probe(input, max_length)\n    {}\n    return input\n", line.trim());
     let db = Arc::new(QueryDb::default());
     let front = issued_original_fixture(&db, &text);
     let input = original_input(&front, "probe");
     let product = db.syntax_product_checked(&input).unwrap();
     setting_syntax::with_setting_admission(&db.body_charge, |admission| {
         let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
         let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = body.original_code_disposition()? else {
             panic!("actual bare input assignment must be available");
         };
         assert!(proof.belongs_to(&body));
         Ok::<(), BodySyntaxFailure>(())
     }).unwrap();
 }

 #[test]
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

 #[test]
 fn actual_original_inline_color_leaves_use_real_heads_and_zero_close_else_links() {
     let file = include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../../code/host/helpers/icons.dm")).replace("\r\n", "\n");
     let start = file.find("/proc/BlendRGB(").unwrap();
     let end = start + 1 + file[start + 1..].find("\n/proc/").unwrap();
     let caller = &file[start..end];
     assert!(caller.contains("RGB1 += 255"));
     for (text, expected) in [
         (caller.to_owned(), true),
         (caller.replace("RGB1 += 255", "RGB1 = list()"), true),
         (caller.replace("RGB1 += 255", "RGB1.field += 255"), false),
         (caller.replace("RGB1 += 255", "RGB1[1] += 255"), false),
         (caller.replace("else if(RGB2.len < RGB1.len) RGB2 += 255", "else RGB2 += 255"), false),
     ] {
         // This asserts the real complete caller's grammar, not a semantic
         // report on ReadRGB or a substituted dependency implementation.
         let db=Arc::new(QueryDb::default());let front=issued_original_fixture(&db,&text);
         let input=original_input(&front,"BlendRGB");let product=db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge,|admission|{
             let body=input.bind_original_product_checked(product.parsed().unwrap(),admission)?;
             let disposition=body.original_code_disposition();
             if expected { let dm_tree::frontend::OriginalBodyDisposition::Available(proof)=disposition? else {panic!("actual inline leaves")};assert!(proof.belongs_to(&body)); }
             else {assert!(!matches!(disposition,Ok(dm_tree::frontend::OriginalBodyDisposition::Available(_))));}
             Ok::<(),BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]
 fn actual_original_move_range_links_its_real_for_tail_to_outer_else() {
     let file = include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../../code/host/helpers/_lists.dm")).replace("\r\n", "\n");
     let start = file.find("/proc/moveRange(").unwrap();
     let end = file[start + 1..].find("\n/proc/").map(|at| start + 1 + at).unwrap();
     let source = &file[start..end];
     assert!(source.contains("for(var/i=0, i<distance, ++i)"));
     for (text, expected) in [
         (source.to_owned(), true),
         (source.replace("for(var/i=0, i<distance, ++i)", "for(var/i=0, i<distance, ++i);"), false),
         (source.replace("for(var/i=0, i<distance, ++i)", "for(var/i=0, i<distance, ++i) L.Insert(fromIndex, null)"), false),
         (source.replace("\telse\n", "\telse L.Insert(toIndex, null)\n"), false),
     ] {
         let db = Arc::new(QueryDb::default());
         let front = issued_original_fixture(&db, &text);
         let input = original_input(&front, "moveRange");
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let disposition = body.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = disposition? else {
                     panic!("actual moveRange for tail must link to the outer else");
                 };
                 assert!(proof.belongs_to(&body));
             } else {
                 assert!(!matches!(disposition, Ok(dm_tree::frontend::OriginalBodyDisposition::Available(_))), "{text}");
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]
 fn actual_original_unique_and_assoc_keys_keep_root_assignment_roles() {
     let file = include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../../code/host/helpers/_lists.dm")).replace("\r\n", "\n");
     let extract = |name: &str| {
         let start = file.find(&format!("/proc/{name}(")).unwrap();
         let tail = &file[start + 1..];
         let end = [tail.find("\n/proc/"), tail.find("\n#define ")]
             .into_iter().flatten().min().map(|at| start + 1 + at).unwrap_or(file.len());
         &file[start..end]
     };
     let macros = ["LIST_VALUE_WRAP_LISTS", "UNTYPED_LIST_ADD"].into_iter().map(|name| {
         file.lines().find(|line| line.starts_with(&format!("#define {name}("))).unwrap()
     }).collect::<Vec<_>>().join("\n");
     for (name, source, needle, refusal) in [
         ("uniqueList", extract("uniqueList").to_owned(), ". |= i", "return . |= i"),
         ("assoc_to_keys", format!("{macros}\n{}", extract("assoc_to_keys")), "UNTYPED_LIST_ADD(keys, key)", "return UNTYPED_LIST_ADD(keys, key)"),
     ] {
         assert!(source.contains(needle));
         for (text, expected) in [(source.to_owned(), true), (source.replace(needle, refusal), false)] {
             let db = Arc::new(QueryDb::default());
             let front = issued_original_fixture(&db, &text);
             let input = original_input(&front, name);
             let product = db.syntax_product_checked(&input).unwrap();
             setting_syntax::with_setting_admission(&db.body_charge, |admission| {
                 let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
                 let disposition = body.original_code_disposition();
                 if expected {
                     let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = disposition? else {
                         panic!("actual {name} root assignment must be available");
                     };
                     assert!(proof.belongs_to(&body));
                 } else {
                     assert!(!matches!(disposition, Ok(dm_tree::frontend::OriginalBodyDisposition::Available(_))), "{text}");
                 }
                 Ok::<(), BodySyntaxFailure>(())
             }).unwrap();
         }
     }
 }

 #[test]
 fn actual_original_initialized_static_head_preserves_primary_flags_and_rhs_role() {
     for (local, expected) in [
         ("var/static/slot = 0", true),
         ("var/static/icon/template = icon('icons/effects/effects.dmi', \"nothing\")", true),
         ("var/global/slot = 0", true), ("var/const/slot = 0", false),
         ("var/static/slot[2] = list()", false),
         ("var/static/slot = other = 0", false),
         ("var/static/slot = ++other", false),
     ] {
         let text = format!("/proc/probe(other)\n    {local}\n");
         let db = Arc::new(QueryDb::default());
         let front = issued_original_fixture(&db, &text);
         let input = original_input(&front, "probe");
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let disposition = body.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = disposition? else { panic!("actual static head + RHS must be available: {text}"); };
                 assert!(proof.belongs_to(&body));
                 let facts = product.parsed().unwrap().statement_storage().parsed().local_variables.entries().unwrap();
                 assert_eq!(facts.len(), 1);
                 assert_eq!(facts[0].source_modifiers, 1);
             } else {
                 assert!(!matches!(disposition, Ok(dm_tree::frontend::OriginalBodyDisposition::Available(_))), "{text}");
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]
 fn actual_original_plain_comma_locals_keep_fresh_paths_and_ordered_initializers() {
     for (local, expected) in [
         ("var/x,y,rsq", true), ("var/i=7,ch,len=length(key)", true),
         ("var/list/x,y", false), ("var/static/x,y", false),
         ("var/x,/datum/y", false), ("var/x,y[2]", false),
         ("var/x=other=1,y", false), ("var/x=++other,y", false),
     ] {
         let text = format!("/proc/probe(key,other)\n    {local}\n");
         let db = Arc::new(QueryDb::default());
         let front = issued_original_fixture(&db, &text);
         let input = original_input(&front, "probe");
         let product = db.syntax_product_checked(&input).unwrap();
         setting_syntax::with_setting_admission(&db.body_charge, |admission| {
             let body = input.bind_original_product_checked(product.parsed().unwrap(), admission)?;
             let disposition = body.original_code_disposition();
             if expected {
                 let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = disposition? else { panic!("actual plain comma-local group must be available: {text}"); };
                 assert!(proof.belongs_to(&body));
                 let facts = product.parsed().unwrap().statement_storage().parsed().local_variables.entries().unwrap();
                 assert_eq!(facts.len(),3);
                 for fact in facts {
                     assert_eq!(fact.source_modifiers,0);
                     assert!(fact.type_components.is_empty());
                     assert_eq!(fact.checker_statement_anchor(),facts[0].checker_statement_anchor());
                 }
                 assert!(facts.windows(2).all(|pair|pair[0].name.end < pair[1].name.start));
             } else {
                 assert!(!matches!(disposition, Ok(dm_tree::frontend::OriginalBodyDisposition::Available(_))), "{text}");
             }
             Ok::<(), BodySyntaxFailure>(())
         }).unwrap();
     }
 }

 #[test]
 fn actual_original_gaussrand_keeps_whole_authored_comma_declaration() {
     let file = include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../../code/host/helpers/random.dm")).replace("\r\n", "\n");
     let start = file.find("/proc/GaussRand(").unwrap();
     let end = file[start+1..].find("\n/proc/").map(|at|start+1+at).unwrap();
     let text = &file[start..end];
     assert!(text.contains("var/x,y,rsq"));
     let db = Arc::new(QueryDb::default());
     let front = issued_original_fixture(&db,text);
     let input = original_input(&front,"GaussRand");
     let product = db.syntax_product_checked(&input).unwrap();
     setting_syntax::with_setting_admission(&db.body_charge,|admission| {
         let body = input.bind_original_product_checked(product.parsed().unwrap(),admission)?;
         let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = body.original_code_disposition()? else { panic!("actual whole GaussRand must be available"); };
         assert!(proof.belongs_to(&body));
         Ok::<(),BodySyntaxFailure>(())
     }).unwrap();
 }

 #[test]
 fn actual_original_guest_key_keeps_whole_authored_multi_local_group() {
     let file = include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../../code/host/helpers/client_lookup.dm")).replace("\r\n", "\n");
     let markers = include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../../code/defines/engine/declare/markers.dm"));
     let marker = markers.lines().find(|line|line.starts_with("#define READS_FROM(")).unwrap();
     let start = file.find("/proc/IsGuestKey(").unwrap();
     let end = file[start+1..].find("\n/proc/").map(|at|start+1+at).unwrap();
     let text = format!("{marker}\n{}",&file[start..end]);
     assert!(text.contains("var/i = 7, ch, len = length(key)"));
     // Whole-proc coverage also needs the independently reviewed C-for empty
     // initializer witness. Never replace that authentic loop with a stub.
     let db = Arc::new(QueryDb::default());
     let front = issued_original_fixture(&db,&text);
     let input = original_input(&front,"IsGuestKey");
     let product = db.syntax_product_checked(&input).unwrap();
     setting_syntax::with_setting_admission(&db.body_charge,|admission| {
         let body = input.bind_original_product_checked(product.parsed().unwrap(),admission)?;
         let dm_tree::frontend::OriginalBodyDisposition::Available(proof) = body.original_code_disposition()? else { panic!("actual whole IsGuestKey must be available"); };
         assert!(proof.belongs_to(&body));
         Ok::<(),BodySyntaxFailure>(())
     }).unwrap();
 }

 #[test]
 fn actual_original_ionnum_preserves_whole_authored_unweighted_pick_interpolations() {
     let file=include_str!(concat!(env!("CARGO_MANIFEST_DIR"),"/../../../../code/host/helpers/random.dm")).replace("\r\n","\n");
     let start=file.find("/proc/ionnum(").unwrap();
     let end=file[start+1..].find("\n/proc/").map(|at|start+1+at).unwrap();
     let text=&file[start..end];
     assert!(text.contains("pick(\"1\",\"2\",\"3\",\"4\",\"5\",\"6\",\"7\",\"8\",\"9\",\"0\")"));
     let db=Arc::new(QueryDb::default());
     let front=issued_original_fixture(&db,text);
     let input=original_input(&front,"ionnum");
     let product=db.syntax_product_checked(&input).unwrap();
     setting_syntax::with_setting_admission(&db.body_charge,|admission| {
         let body=input.bind_original_product_checked(product.parsed().unwrap(),admission)?;
         let dm_tree::frontend::OriginalBodyDisposition::Available(proof)=body.original_code_disposition()? else { panic!("actual whole ionnum must be available"); };
         assert!(proof.belongs_to(&body));
         let parsed=product.parsed().unwrap().statement_storage().parsed();
         let dm_syntax::StatementKind::Return(Some(expression))=&parsed.statements[0].kind else { panic!("actual return"); };
         let dm_syntax::ExprKind::Literal(literal)=&expression.kind else { panic!("actual interpolated literal"); };
         let parts=literal.prepared_syntax_parts().expect("already prepared actual literal")
             .expect("successful actual literal preparation").expect("actual interpolated template");
         assert_eq!(parts.expressions.len(),4);
         for (expression,count) in parts.expressions.iter().zip([10,8,8,8]) {
             let pick=dm_syntax::native_special_forms::pick(expression).unwrap();
             assert_eq!(pick.choices().count(),count);
             assert!(pick.choices().all(|choice|choice.weight.is_none()));
         }
         Ok::<(),BodySyntaxFailure>(())
     }).unwrap();
 }

 #[test]
 fn actual_original_generate_key_keeps_all_authored_unweighted_arms_beyond_sixteen() {
     let file=include_str!(concat!(env!("CARGO_MANIFEST_DIR"),"/../../../../code/host/helpers/text.dm")).replace("\r\n","\n");
     let start=file.find("/proc/GenerateKey(").unwrap();
     let end=file[start+1..].find("\n/proc/").map(|at|start+1+at).unwrap();
     let text=&file[start..end];
     assert_eq!(text.matches("newKey += pick(").count(),3);
     let db=Arc::new(QueryDb::default());
     let front=issued_original_fixture(&db,text);
     let input=original_input(&front,"GenerateKey");
     let product=db.syntax_product_checked(&input).unwrap();
     setting_syntax::with_setting_admission(&db.body_charge,|admission| {
         let body=input.bind_original_product_checked(product.parsed().unwrap(),admission)?;
         let dm_tree::frontend::OriginalBodyDisposition::Available(proof)=body.original_code_disposition()? else { panic!("actual whole GenerateKey must be available"); };
         assert!(proof.belongs_to(&body));
         let parsed=product.parsed().unwrap().statement_storage().parsed();
         let mut counts=Vec::new();
         for statement in &parsed.statements {
             if let dm_syntax::StatementKind::Assign { value, .. }=&statement.kind {
                 let pick=dm_syntax::native_special_forms::pick(value).unwrap();
                 assert!(pick.choices().all(|choice|choice.weight.is_none()));
                 counts.push(pick.choices().count());
             }
         }
         assert_eq!(counts,[19,18,10]);
         Ok::<(),BodySyntaxFailure>(())
     }).unwrap();
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

 #[test]fn actual_original_call_member_conditions_switch_and_nested_comparison_keep_real_body_owners(){
  let source="/proc/read_condition(check_obj,ignore_show_messages)\n    if(ignore_show_messages || rules_of(check_obj).show_messages)\n        return check_obj\n    return check_obj\n/proc/read_switch(source)\n    switch(combat_of(source).force)\n        if(1) return source\n        else return source\n/proc/read_nested(prey,limit)\n    if(!(cooldowns_view(prey).slip_protect < limit))\n        return prey\n    return prey\n";
  let db=Arc::new(QueryDb::default());let own=original_frontend(&mut RetainedSemanticTree::new(),&db,source);let foreign=original_frontend(&mut RetainedSemanticTree::new(),&db,source);
  for name in["read_condition","read_switch","read_nested"]{let input=original_input(&own,name);let other=original_input(&foreign,name);let product=db.syntax_product_checked(&input).unwrap();setting_syntax::with_setting_admission(&db.body_charge,|a|{let bound=input.bind_original_product_checked(product.parsed().unwrap(),a)?;let dm_tree::frontend::OriginalBodyDisposition::Available(grant)=bound.original_code_disposition()?else{panic!("actual call-member child did not issue complete BODY: {name}")};assert!(grant.belongs_to(&bound));assert!(other.bind_original_product_checked(product.parsed().unwrap(),a).is_err());Ok::<(),BodySyntaxFailure>(())}).unwrap();}
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

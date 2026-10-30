use super::*;
use std::sync::{Barrier,atomic::AtomicBool};
struct Bytes(dm_preprocess::AcquiredSource);
impl dm_preprocess::SourceProvider for Bytes {
    fn read(&self,_:&std::path::Path)->Result<String,String>{Err("actual original byte acquisition required".into())}
    fn acquired_source(&self,_:&std::path::Path)->Result<Option<dm_preprocess::AcquiredSource>,String>{Ok(Some(self.0.clone()))}
    fn source_acquisition(&self,_:&std::path::Path,text:&dm_preprocess::SourceText)->Option<dm_preprocess::AcquiredSource>{self.0.lease().source_text().same_view(text).then(||self.0.clone())}
}
fn front()->dm_tree::frontend::ColdFrontend{
    let input=Bytes(dm_preprocess::AcquiredSource::from_original_bytes(b"/datum/left\n    var/static/value=1\n/datum/right\n    var/static/value=2\n".to_vec(),()));
    dm_tree::frontend::build(std::path::Path::new("parallel-original-initializers.dme"),&input,&Default::default(),2).unwrap()
}
struct Worker{fail:AtomicBool,barrier:Barrier,calls:AtomicUsize}
impl Worker{fn source(owner:SymbolId)->Evaluation{if owner==SymbolId::of("/datum/left"){Evaluation::SourceError("first original source declaration rejected".into())}else{Evaluation::Scalar(SemanticValue::Null)}}}
impl CapturedInitializerEvaluator for Worker{
    fn evaluate(&self,owner:SymbolId,_:&SymbolicExpression)->Result<Evaluation,String>{Ok(Self::source(owner))}
    fn evaluate_prepared_write_checked(&self,w:&InitializerWrite,_:&SymbolicExpression)->Result<(Evaluation,Option<PreparedInitializerExpression>),InitializerFailure>{
        self.calls.fetch_add(1,Ordering::Relaxed);
        let fail=self.fail.load(Ordering::Acquire);if fail{self.barrier.wait();}
        if fail&&w.lexical_owner==SymbolId::of("/datum/right"){return Err(InitializerFailure::Operational(std::io::Error::from_raw_os_error(1450)));}
        Ok((Self::source(w.lexical_owner),None))
    }
}
impl InitializerEvaluatorFactory for Worker{
    fn with_evaluator(&self,_:Option<&crate::engine::EngineSnapshot>,operation:&mut dyn FnMut(&dyn CapturedInitializerEvaluator)){operation(self)}
}
#[test]
fn parallel_original_source_semantic_chunk_cannot_hide_completed_sibling_operational_failure(){
    let front=front();let plan=dm_tree::initializers::capture_declaration_plan(&front.snapshot,&front.emission_order).unwrap();let writes=&plan.plan().writes;assert_eq!(writes.len(),2);assert_ne!(writes[0].lexical_owner,writes[1].lexical_owner);
    let worker=Worker{fail:AtomicBool::new(true),barrier:Barrier::new(2),calls:AtomicUsize::new(0)};let factory=ParallelEvaluator{factory:&worker,engine:None};let executor=dm_exec::BuildExecutor::new(2).unwrap();
    let InitializerClassificationFailure::Operational(actual)=classify_with_token_mode_on_executor_checked(writes,front.snapshot.tree.symbols(),factory,false,&executor).err().expect("both actual source chunks complete")else{panic!("earlier semantic result discarded sibling actual IO")};assert_eq!(actual.raw_os_error(),Some(1450));assert_eq!(worker.calls.load(Ordering::Relaxed),2);
    worker.fail.store(false,Ordering::Release);
    let InitializerClassificationFailure::Semantic(source)=classify_with_token_mode_on_executor_checked(writes,front.snapshot.tree.symbols(),factory,false,&executor).err().unwrap()else{panic!("same-source genuine semantic result restored after actual operation")};
    assert_eq!(source.issues[0].reason,"first original source declaration rejected");assert_eq!(source.issues[0].source_ordinal,0);assert_eq!(source.issues[0].kind,ClassificationIssueKind::SourceError);
}
#[test]
fn checked_parallel_semantic_source_order_matches_original_compatibility(){
    let front=front();let plan=dm_tree::initializers::capture_declaration_plan(&front.snapshot,&front.emission_order).unwrap();let worker=Worker{fail:AtomicBool::new(false),barrier:Barrier::new(2),calls:AtomicUsize::new(0)};let factory=ParallelEvaluator{factory:&worker,engine:None};let executor=dm_exec::BuildExecutor::new(2).unwrap();
    let old=crate::initializer_policy::classify_with_token_mode_on_executor(&plan.plan().writes,front.snapshot.tree.symbols(),factory,false,&executor).err().unwrap();
    let InitializerClassificationFailure::Semantic(checked)=classify_with_token_mode_on_executor_checked(&plan.plan().writes,front.snapshot.tree.symbols(),factory,false,&executor).err().unwrap()else{panic!("source issue remains semantic")};assert_eq!(checked,old);
}
#[test]
fn checked_parallel_cancelled_empty_and_late_factory_callback_never_return_batch(){
    struct Late{token:crate::daemon::control::Cancellation,calls:AtomicUsize}
    impl CapturedInitializerEvaluator for Late{fn evaluate(&self,_:SymbolId,_:&SymbolicExpression)->Result<Evaluation,String>{Ok(Evaluation::Scalar(SemanticValue::Null))}}
    impl InitializerEvaluatorFactory for Late{fn with_evaluator(&self,_:Option<&crate::engine::EngineSnapshot>,operation:&mut dyn FnMut(&dyn CapturedInitializerEvaluator)){self.calls.fetch_add(1,Ordering::Relaxed);operation(self);self.token.cancel();}}
    let executor=dm_exec::BuildExecutor::new(1).unwrap();let symbols=SymbolTable::default();let token=crate::daemon::control::Cancellation::default();let factory=Late{token:token.clone(),calls:AtomicUsize::new(0)};
    let binding=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));token.cancel();assert!(matches!(classify_with_token_mode_on_executor_checked(&[],&symbols,ParallelEvaluator{factory:&factory,engine:None},false,&executor),Err(InitializerClassificationFailure::Operational(ref e))if e.kind()==std::io::ErrorKind::Interrupted));assert_eq!(factory.calls.load(Ordering::Relaxed),0);drop(binding);
    assert!(classify_with_token_mode_on_executor_checked(&[],&symbols,ParallelEvaluator{factory:&factory,engine:None},false,&executor).unwrap().writes.is_empty());
    let front=front();let plan=dm_tree::initializers::capture_declaration_plan(&front.snapshot,&front.emission_order).unwrap();let token=crate::daemon::control::Cancellation::default();let factory=Late{token:token.clone(),calls:AtomicUsize::new(0)};let binding=crate::daemon::control::bind_with_deadline(token,std::time::Instant::now()+std::time::Duration::from_secs(30));
    assert!(matches!(classify_with_token_mode_on_executor_checked(&plan.plan().writes,front.snapshot.tree.symbols(),ParallelEvaluator{factory:&factory,engine:None},false,&executor),Err(InitializerClassificationFailure::Operational(ref e))if e.kind()==std::io::ErrorKind::Interrupted));assert!(factory.calls.load(Ordering::Relaxed)>0);drop(binding);
}

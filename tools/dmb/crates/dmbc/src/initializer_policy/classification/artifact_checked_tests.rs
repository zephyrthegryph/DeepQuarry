use super::*;
use std::sync::atomic::AtomicUsize;
struct Host;
impl Resolver for Host{fn resolve(&self,q:ResolveQuery)->ResolvedMeaning{match q{ResolveQuery::Constant{..}=>ResolvedMeaning::Value(SemanticValue::NumberBits(7f32.to_bits())),_=>ResolvedMeaning::Missing}}}
struct Worker<'a>{resolver:&'a dyn Resolver,calls:&'a AtomicUsize,mode:&'a AtomicUsize,token:&'a crate::daemon::control::Cancellation}
impl CapturedInitializerEvaluator for Worker<'_>{
    fn evaluate(&self,_:SymbolId,_:&SymbolicExpression)->Result<Evaluation,String>{panic!("checked artifact must not select String evaluator")}
    fn evaluate_prepared_write_checked(&self,w:&InitializerWrite,_:&SymbolicExpression)->Result<(Evaluation,Option<PreparedInitializerExpression>),InitializerFailure>{
        self.calls.fetch_add(1,Ordering::Relaxed);
        let ResolvedMeaning::Value(value)=self.resolver.resolve(ResolveQuery::Constant{owner:w.lexical_owner,name:SymbolId::of("dependency")})else{return Err("original constant unavailable".into())};
        match self.mode.load(Ordering::Relaxed){1|3=>return Err(InitializerFailure::Operational(std::io::Error::from_raw_os_error(1450))),2=>self.token.cancel(),_=>()};
        Ok((Evaluation::Scalar(value),None))
    }
}
impl InitializerEvaluatorFactory for Worker<'_>{
    fn recording_policy_identity(&self)->Option<u128>{Some(203)}
    fn with_recording_evaluator(&self,_:Option<&crate::engine::EngineSnapshot>,resolver:&dyn Resolver,operation:&mut dyn FnMut(&dyn CapturedInitializerEvaluator))->bool{
        operation(&Worker{resolver,calls:self.calls,mode:self.mode,token:self.token});self.mode.load(Ordering::Relaxed)!=3
    }
    fn with_evaluator(&self,_:Option<&crate::engine::EngineSnapshot>,operation:&mut dyn FnMut(&dyn CapturedInitializerEvaluator)){operation(self)}
}
fn attempt(mode_value:usize){
    let mut symbols=SymbolTable::default();let owner=symbols.intern("/").unwrap();let name=symbols.intern("output").unwrap();
    let write=InitializerWrite{source_site:dm_ir::InitializerSite::Declaration,target:InitializerTarget::Shared{owner,name,slot:SymbolId::of("output.slot")},lexical_owner:owner,lexical_procedure:None,value:InitializerValue::Expression(crate::initializer_policy::expression("dependency",&mut symbols).unwrap()),declared_array:None,declaration_flags:Some(8)};
    let host=Host;let calls=AtomicUsize::new(0);let mode=AtomicUsize::new(mode_value);let token=crate::daemon::control::Cancellation::default();
    let worker=Worker{resolver:&host,calls:&calls,mode:&mode,token:&token};let factory=ParallelEvaluator{factory:&worker,engine:None};
    let store=InitializerArtifacts::with_limit(1024*1024);let reuse=InitializerReuse{store:&store,resolver:&host,policy:1,resource_search_context:None};
    let key:Arc<[u8]>=key(&write,ModifierFact::Known(8),reuse,203).into();
    let binding=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));
    let error=classify_one_keyed_grouped_checked_in(&write,&symbols,&worker,ModifierFact::Known(8),19,factory,reuse,Some(&key),None,None,None,None).err().expect("actual checked worker refusal");
    let ClassificationReadFailure::Operational(actual)=error else{panic!("actual worker operation cannot be semantic")};
    if mode_value==2{assert_eq!(actual.kind(),std::io::ErrorKind::Interrupted)}else{assert_eq!(actual.raw_os_error(),Some(1450))};drop(binding);
    assert_eq!(calls.load(Ordering::Relaxed),1,"declined recording cannot hide actual IO by fallback");assert_eq!(store.hits.load(Ordering::Relaxed),0);assert_eq!(store.recomputed.load(Ordering::Relaxed),0);
    let mut entries=0;store.visit_storage(|view|if matches!(view,dm_session::ArtifactStorageView::Entry{..}){entries+=1});assert_eq!(entries,0,"failed item publishes neither semantic artifact nor accepted owner");
    mode.store(0,Ordering::Relaxed);
    let fresh=classify_one_keyed_grouped_checked_in(&write,&symbols,&worker,ModifierFact::Known(8),19,factory,reuse,Some(&key),None,None,None,None).unwrap();assert!(fresh.accepted.is_some());assert_eq!(fresh.write.source_ordinal,19);
    let warm=classify_one_keyed_grouped_checked_in(&write,&symbols,&worker,ModifierFact::Known(8),29,factory,reuse,Some(&key),None,None,None,None).unwrap();assert!(warm.accepted.is_some());assert_eq!(warm.write.default,fresh.write.default);assert_eq!(warm.write.source_ordinal,29);assert_eq!(calls.load(Ordering::Relaxed),2);assert_eq!(store.hits.load(Ordering::Relaxed),1);
    let canceled=crate::daemon::control::Cancellation::default();let binding=crate::daemon::control::bind_with_deadline(canceled.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));canceled.cancel();assert!(matches!(classify_one_keyed_grouped_checked_in(&write,&symbols,&worker,ModifierFact::Known(8),29,factory,reuse,Some(&key),None,None,None,None),Err(ClassificationReadFailure::Operational(ref e))if e.kind()==std::io::ErrorKind::Interrupted));drop(binding);assert_eq!(store.hits.load(Ordering::Relaxed),1,"canceled warm query cannot claim accepted hit");
}
#[test]fn checked_value_artifact_actual_io_has_no_admission_then_same_key_fresh_and_warm(){attempt(1)}
#[test]fn checked_value_artifact_success_then_cancel_is_checked_before_admission(){attempt(2)}
#[test]fn checked_value_artifact_declining_factory_cannot_discard_actual_callback_io(){attempt(3)}

#[test]
fn checked_artifact_semantic_early_exit_and_omitted_callback_still_cross_final_operation_guard(){
    struct Source(bool);
    impl CapturedInitializerEvaluator for Source{
        fn evaluate(&self,_:SymbolId,_:&SymbolicExpression)->Result<Evaluation,String>{panic!("checked source hook")}
        fn evaluate_prepared_write_checked(&self,_:&InitializerWrite,_:&SymbolicExpression)->Result<(Evaluation,Option<PreparedInitializerExpression>),InitializerFailure>{Ok((Evaluation::SourceError("genuine early source error".into()),None))}
    }
    impl InitializerEvaluatorFactory for Source{
        fn recording_policy_identity(&self)->Option<u128>{self.0.then_some(991)}
        fn with_recording_evaluator(&self,_:Option<&crate::engine::EngineSnapshot>,_:&dyn Resolver,_:&mut dyn FnMut(&dyn CapturedInitializerEvaluator))->bool{true}
        fn with_evaluator(&self,_:Option<&crate::engine::EngineSnapshot>,operation:&mut dyn FnMut(&dyn CapturedInitializerEvaluator)){operation(self)}
    }
    for omitted in [false,true]{
        let mut symbols=SymbolTable::default();let owner=symbols.intern("/").unwrap();let name=symbols.intern("output").unwrap();let write=InitializerWrite{source_site:dm_ir::InitializerSite::Declaration,target:InitializerTarget::Shared{owner,name,slot:SymbolId::of("slot")},lexical_owner:owner,lexical_procedure:None,value:InitializerValue::Expression(crate::initializer_policy::expression("1",&mut symbols).unwrap()),declared_array:None,declaration_flags:Some(8)};
        let host=Host;let store=InitializerArtifacts::with_limit(1024*1024);let reuse=InitializerReuse{store:&store,resolver:&host,policy:1,resource_search_context:None};let worker=Source(omitted);let factory=ParallelEvaluator{factory:&worker,engine:None};let key:Arc<[u8]>=key(&write,ModifierFact::Known(8),reuse,991).into();
        let token=crate::daemon::control::Cancellation::default();let binding=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));
        AFTER_ITEM_CANCEL.with(|slot|{assert!(slot.borrow().is_none());*slot.borrow_mut()=Some(token);});
        let ClassificationReadFailure::Operational(actual)=classify_one_keyed_grouped_checked_in(&write,&symbols,&worker,ModifierFact::Known(8),0,factory,reuse,Some(&key),None,None,None,None).err().unwrap()else{panic!("semantic result bypassed final guard")};assert_eq!(actual.kind(),std::io::ErrorKind::Interrupted);drop(binding);
        let ClassificationReadFailure::Semantic(source)=classify_one_keyed_grouped_checked_in(&write,&symbols,&worker,ModifierFact::Known(8),0,factory,reuse,Some(&key),None,None,None,None).err().unwrap()else{panic!("genuine semantic result restored on retry")};assert_eq!(source.reason,if omitted{"initializer recording factory omitted operation"}else{"genuine early source error"});
    }
}

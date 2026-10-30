use super::*;
use dm_ir::ResolvedMeaning;
struct Source;
impl Resolver for Source {
    fn resolve(&self,q:ResolveQuery)->ResolvedMeaning {
        match q {ResolveQuery::Constant{..}=>ResolvedMeaning::Value(SemanticValue::NumberBits(0)),_=>ResolvedMeaning::Unsupported(q)}
    }
}
struct Worker<'a>{resolver:&'a dyn Resolver,captures:&'a AtomicU64,cancel:&'a std::sync::Mutex<Option<crate::daemon::control::Cancellation>>,cancel_after:bool}
impl CapturedInitializerEvaluator for Worker<'_>{
    fn evaluate(&self,_:SymbolId,_:&SymbolicExpression)->Result<Evaluation,String>{panic!("modifier has no RHS")}
    fn binding_knowledge(&self,_:&InitializerWrite)->Result<Option<BindingKnowledge>,String>{panic!("checked reuse cannot choose String hook")}
    fn binding_knowledge_checked(&self,write:&InitializerWrite)->Result<Option<BindingKnowledge>,InitializerFailure>{
        self.captures.fetch_add(1,Ordering::Relaxed);
        let pending=self.cancel.lock().unwrap().take();
        if !self.cancel_after {if let Some(token)=pending.as_ref(){token.cancel();}}
        crate::daemon::control::checkpoint().map_err(InitializerFailure::Operational)?;
        let result=match self.resolver.resolve(ResolveQuery::Constant{owner:write.lexical_owner,name:SymbolId::of("flags")}) {
            ResolvedMeaning::Value(SemanticValue::NumberBits(flags))=>Ok(Some(BindingKnowledge::Modifiers(flags))),
            _=>Err("original modifier dependency unavailable".into()),
        };
        if self.cancel_after {if let Some(token)=pending{token.cancel();}}
        result
    }
}
impl InitializerEvaluatorFactory for Worker<'_>{
    fn recording_policy_identity(&self)->Option<u128>{Some(982)}
    fn with_evaluator(&self,_:Option<&crate::engine::EngineSnapshot>,operation:&mut dyn FnMut(&dyn CapturedInitializerEvaluator)){operation(self)}
    fn with_recording_evaluator(&self,_:Option<&crate::engine::EngineSnapshot>,resolver:&dyn Resolver,operation:&mut dyn FnMut(&dyn CapturedInitializerEvaluator))->bool{
        operation(&Worker{resolver,captures:self.captures,cancel:self.cancel,cancel_after:self.cancel_after});true
    }
}
fn failed_attempt_recovers(cancel_after:bool) {
    let mut symbols=SymbolTable::default();let owner=symbols.intern("/").unwrap();let name=symbols.intern("output").unwrap();
    let writes=[InitializerWrite{source_site:dm_ir::InitializerSite::Declaration,target:InitializerTarget::Shared{owner,name,slot:SymbolId::of("slot")},lexical_owner:owner,lexical_procedure:None,value:InitializerValue::NoAuthoredValue,declared_array:None,declaration_flags:None}];
    let source=Source;let captures=AtomicU64::new(0);let cancel=std::sync::Mutex::new(None);let worker=Worker{resolver:&source,captures:&captures,cancel:&cancel,cancel_after};
    let factory=ParallelEvaluator{factory:&worker,engine:None};let store=InitializerArtifacts::default();
    let reuse=InitializerReuse{store:&store,resolver:&source,policy:98,resource_search_context:None};
    let keys=keys(&writes,factory,reuse).unwrap();
    let token=crate::daemon::control::Cancellation::default();let binding=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));*cancel.lock().unwrap()=Some(token);
    let ModifierReadFailure::Operational(actual)=modifier_facts_reused_checked_in(writes.iter(),&symbols,&worker,&[0],factory,reuse,&keys,None).err().expect("real recording-worker IO") else {panic!("operational result not semantic issue")};
    assert_eq!(actual.kind(),std::io::ErrorKind::Interrupted);
    assert!(keys[0].admitted.get().is_none());assert_eq!(store.modifiers.recomputed.load(Ordering::Relaxed),0);
    let mut values=0;store.modifiers.visit_storage(|view|if matches!(view,dm_session::ArtifactStorageView::Entry{..}){values+=1});assert_eq!(values,0,"no modifier artifact published after actual operation");
    drop(binding);
    let fresh=modifier_facts_reused_checked_in(writes.iter(),&symbols,&worker,&[0],factory,reuse,&keys,None).unwrap();assert_eq!(fresh,vec![ModifierFact::Known(0)]);
    assert!(keys[0].admitted.get().is_some());assert_eq!(store.modifiers.recomputed.load(Ordering::Relaxed),1);
    assert_eq!(modifier_facts_reused_checked_in(writes.iter(),&symbols,&worker,&[0],factory,reuse,&keys,None).unwrap(),fresh);
    let token=crate::daemon::control::Cancellation::default();let binding=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));token.cancel();
    assert!(matches!(modifier_facts_reused_checked_in(writes.iter(),&symbols,&worker,&[0],factory,reuse,&keys,None),Err(ModifierReadFailure::Operational(ref actual))if actual.kind()==std::io::ErrorKind::Interrupted));drop(binding);
    assert_eq!(captures.load(Ordering::Relaxed),2,"failed operation plus fresh compute, exact warm reuse never evaluates");assert_eq!(store.modifiers.hits.load(Ordering::Relaxed),1);
}

#[test]
fn actual_modifier_reuse_operation_cannot_admit_key_or_artifact_and_same_key_retries_warm(){failed_attempt_recovers(false)}
#[test]
fn modifier_worker_success_then_actual_cancellation_cannot_publish_fact_or_claim(){failed_attempt_recovers(true)}

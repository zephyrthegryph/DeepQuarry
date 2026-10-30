use super::*;
use std::cell::Cell;
fn write(name:&str)->InitializerWrite {
    let owner=SymbolId::of("/datum/probe");InitializerWrite{
        source_site:dm_ir::InitializerSite::Declaration,target:InitializerTarget::Instance{declaring_owner:owner,receiver_owner:owner,name:SymbolId::of(name)},
        lexical_owner:owner,lexical_procedure:None,value:InitializerValue::NoAuthoredValue,declared_array:None,declaration_flags:Some(0),
    }
}
#[test]
fn checked_modifier_capture_shares_validation_and_exact_semantic_issue_order() {
    struct Source;
    impl CapturedInitializerEvaluator for Source {
        fn evaluate(&self,_:SymbolId,_:&SymbolicExpression)->Result<Evaluation,String>{panic!("modifier never evaluates RHS")}
        fn binding_knowledge(&self,write:&InitializerWrite)->Result<Option<BindingKnowledge>,String>{
            if write.target==super::checked_tests::write("good").target {Ok(Some(BindingKnowledge::Modifiers(0)))} else {Err("exact custom declaration refusal".into())}
        }
    }
    let symbols=SymbolTable::default();let writes=[write("first"),write("good"),write("last")];let ordinals=[8,2,11];
    let old=modifier_facts_indexed(writes.iter(),&symbols,&Source,Some(&ordinals)).err().unwrap();
    let ModifierReadFailure::Semantic(checked)=modifier_facts_indexed_checked(writes.iter(),&symbols,&Source,Some(&ordinals)).err().unwrap() else {panic!("source semantic result")};
    assert_eq!(checked.issues,old.issues);assert_eq!(checked.issues.iter().map(|i|i.source_ordinal).collect::<Vec<_>>(),vec![8,11]);
    let writes=[write("good")];let old=modifier_facts(&writes,&symbols,&Source).unwrap();
    assert_eq!(modifier_facts_indexed_checked(writes.iter(),&symbols,&Source,None).unwrap(),old);
}
#[test]
fn actual_checked_modifier_io_precedes_earlier_semantic_issue_without_string_hook() {
    struct Native{calls:Cell<usize>,cancel:crate::daemon::control::Cancellation}
    impl CapturedInitializerEvaluator for Native {
        fn evaluate(&self,_:SymbolId,_:&SymbolicExpression)->Result<Evaluation,String>{panic!("modifier never evaluates RHS")}
        fn binding_knowledge(&self,_:&InitializerWrite)->Result<Option<BindingKnowledge>,String>{panic!("typed modifier cannot fallback to String")}
        fn binding_knowledge_checked(&self,_:&InitializerWrite)->Result<Option<BindingKnowledge>,InitializerFailure>{
            self.calls.set(self.calls.get()+1);
            crate::daemon::control::checkpoint().map_err(InitializerFailure::Operational)?;
            if self.calls.get()==1 {self.cancel.cancel();Err(InitializerFailure::Unsupported("earlier genuine semantic issue".into()))}
            else {Ok(Some(BindingKnowledge::Modifiers(0)))}
        }
    }
    let token=crate::daemon::control::Cancellation::default();let native=Native{calls:Cell::new(0),cancel:token.clone()};
    let binding=crate::daemon::control::bind_with_deadline(token,std::time::Instant::now()+std::time::Duration::from_secs(30));
    let writes=[write("first"),write("second")];let symbols=SymbolTable::default();
    let ModifierReadFailure::Operational(actual)=modifier_facts_indexed_checked(writes.iter(),&symbols,&native,None).err().unwrap() else {panic!("completed real IO must not be aggregated as semantic")};
    assert_eq!(actual.kind(),std::io::ErrorKind::Interrupted);assert_eq!(native.calls.get(),2);drop(binding);
    let recovered=modifier_facts_indexed_checked(writes.iter(),&symbols,&native,None).unwrap();assert_eq!(recovered,vec![ModifierFact::Known(0);2]);
}
#[test]
fn checked_modifier_preserves_owned_actual_os_failure_cause_before_any_fact() {
    struct Native;
    impl CapturedInitializerEvaluator for Native {
        fn evaluate(&self,_:SymbolId,_:&SymbolicExpression)->Result<Evaluation,String>{panic!("no RHS")}
        fn binding_knowledge_checked(&self,_:&InitializerWrite)->Result<Option<BindingKnowledge>,InitializerFailure>{Err(InitializerFailure::Operational(std::io::Error::from_raw_os_error(1450)))}
    }
    let writes=[write("one")];let symbols=SymbolTable::default();
    let ModifierReadFailure::Operational(actual)=modifier_facts_indexed_checked(writes.iter(),&symbols,&Native,None).err().unwrap() else {panic!("actual owned IO")};
    assert_eq!(actual.raw_os_error(),Some(1450));
}

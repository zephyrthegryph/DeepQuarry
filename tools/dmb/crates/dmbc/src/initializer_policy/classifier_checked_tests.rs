use super::*;
fn write(owner:SymbolId,name:SymbolId,value:InitializerValue)->InitializerWrite{InitializerWrite{source_site:dm_ir::InitializerSite::Declaration,target:InitializerTarget::Shared{owner,name,slot:SymbolId::of("output.slot")},lexical_owner:owner,lexical_procedure:None,value,declared_array:None,declaration_flags:Some(8)}}
struct Values<'a>(&'a SymbolTable);
impl CapturedInitializerEvaluator for Values<'_>{
    fn evaluate(&self,_:SymbolId,value:&SymbolicExpression)->Result<Evaluation,String>{
        let source=value.source_text(self.0).ok_or("genuine token spelling")?;
        Ok(match source.parse::<f32>(){Ok(n)=>Evaluation::Scalar(SemanticValue::NumberBits(n.to_bits())),Err(_)=>Evaluation::Runtime})
    }
}
#[test]
fn checked_classifier_shares_old_scalar_list_runtime_groups_and_canonical_token_order(){
    let mut symbols=SymbolTable::default();let owner=symbols.intern("/").unwrap();let name=symbols.intern("output").unwrap();
    let writes=["17","list(1,2)","rand(1,2)","list(1,2)"].into_iter().map(|source|write(owner,name,InitializerValue::Expression(expression(source,&mut symbols).unwrap()))).collect::<Vec<_>>();
    let old=classify_with_token_mode(&writes,&symbols,&Values(&symbols),false).unwrap();let checked=classify_with_token_mode_checked(&writes,&symbols,&Values(&symbols),false).unwrap();
    assert_eq!(checked.groups.len(),old.groups.len());for(a,b)in checked.groups.iter().zip(&old.groups){assert_eq!(a.receiver,b.receiver);assert_eq!(a.writes,b.writes);assert_eq!(a.declaration_presence,b.declaration_presence);}assert_eq!(checked.writes.len(),old.writes.len());
    for (a,b) in checked.writes.iter().zip(&old.writes){assert_eq!(a.write,b.write);assert_eq!(a.source_ordinal,b.source_ordinal);assert_eq!(a.default,b.default);assert_eq!(a.phase,b.phase);assert_eq!(a.source_features,b.source_features);assert_eq!(a.runtime_value,b.runtime_value);}
}
#[test]
fn checked_classifier_preserves_genuine_source_kind_nameof_notes_and_assignment_ordinal(){
    struct Source(bool);
    impl CapturedInitializerEvaluator for Source{
        fn evaluate(&self,_:SymbolId,_:&SymbolicExpression)->Result<Evaluation,String>{Ok(if self.0{Evaluation::InvalidNameof("same current nameof source error".into(),dm_codegen_byond::NameofDiagnosticRecovery::ReferenceRejected)}else{Evaluation::SourceError("same current source error".into())})}
    }
    let mut symbols=SymbolTable::default();let owner=symbols.intern("/").unwrap();let name=symbols.intern("output").unwrap();let writes=[write(owner,name,InitializerValue::Expression(expression("1",&mut symbols).unwrap()))];
    for detailed in [false,true]{let old=classify_with_token_mode(&writes,&symbols,&Source(detailed),false).err().unwrap();let InitializerClassificationFailure::Semantic(checked)=classify_with_token_mode_checked(&writes,&symbols,&Source(detailed),false).err().unwrap()else{panic!("actual source semantic failure")};assert_eq!(checked,old);assert!(checked.issues.iter().all(|issue|issue.source_ordinal==0&&issue.kind==ClassificationIssueKind::SourceError));}
}
#[test]
fn actual_checked_classifier_operation_returns_no_result_and_same_source_recovers(){
    struct Native;
    impl CapturedInitializerEvaluator for Native{
        fn evaluate(&self,_:SymbolId,_:&SymbolicExpression)->Result<Evaluation,String>{panic!("checked classifier cannot select String evaluator")}
        fn evaluate_prepared_write_checked(&self,_:&InitializerWrite,_:&SymbolicExpression)->Result<(Evaluation,Option<PreparedInitializerExpression>),InitializerFailure>{crate::daemon::control::checkpoint().map_err(InitializerFailure::Operational)?;Ok((Evaluation::Scalar(SemanticValue::Null),None))}
    }
    let mut symbols=SymbolTable::default();let owner=symbols.intern("/").unwrap();let name=symbols.intern("output").unwrap();let writes=[write(owner,name,InitializerValue::Expression(expression("1",&mut symbols).unwrap()))];
    let token=crate::daemon::control::Cancellation::default();let binding=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));token.cancel();
    let InitializerClassificationFailure::Operational(actual)=classify_with_token_mode_checked(&writes,&symbols,&Native,false).err().expect("actual bound cancellation")else{panic!("not semantic")};assert_eq!(actual.kind(),std::io::ErrorKind::Interrupted);drop(binding);
    assert_eq!(classify_with_token_mode_checked(&writes,&symbols,&Native,false).unwrap().writes[0].default,DefaultValue::Scalar(SemanticValue::Null));
}
#[test]
fn checked_classifier_mid_prepared_os_io_and_successful_hook_cancellation_escape_before_finish(){
    enum Mode{Io,Late(crate::daemon::control::Cancellation)}
    struct Native(Mode);
    impl CapturedInitializerEvaluator for Native{
        fn evaluate(&self,_:SymbolId,_:&SymbolicExpression)->Result<Evaluation,String>{panic!("typed prepared hook")}
        fn evaluate_prepared_write_checked(&self,_:&InitializerWrite,_:&SymbolicExpression)->Result<(Evaluation,Option<PreparedInitializerExpression>),InitializerFailure>{match &self.0{Mode::Io=>Err(InitializerFailure::Operational(std::io::Error::from_raw_os_error(1450))),Mode::Late(token)=>{token.cancel();Ok((Evaluation::Runtime,None))}}}
    }
    let mut symbols=SymbolTable::default();let owner=symbols.intern("/").unwrap();let name=symbols.intern("output").unwrap();let writes=[write(owner,name,InitializerValue::Expression(expression("list(1)",&mut symbols).unwrap()))];
    let InitializerClassificationFailure::Operational(actual)=classify_with_token_mode_checked(&writes,&symbols,&Native(Mode::Io),false).err().unwrap()else{panic!("actual IO")};assert_eq!(actual.raw_os_error(),Some(1450));
    let token=crate::daemon::control::Cancellation::default();let binding=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));let InitializerClassificationFailure::Operational(actual)=classify_with_token_mode_checked(&writes,&symbols,&Native(Mode::Late(token)),false).err().unwrap()else{panic!("cancel before text/runtime decomposition")};assert_eq!(actual.kind(),std::io::ErrorKind::Interrupted);drop(binding);
}

#[test]
fn checked_classifier_pending_semantic_failure_still_checks_actual_final_cancellation(){
    struct Source;
    impl CapturedInitializerEvaluator for Source{fn evaluate(&self,_:SymbolId,_:&SymbolicExpression)->Result<Evaluation,String>{Ok(Evaluation::SourceError("genuine semantic failure before final boundary".into()))}}
    let mut symbols=SymbolTable::default();let owner=symbols.intern("/").unwrap();let name=symbols.intern("output").unwrap();let writes=[write(owner,name,InitializerValue::Expression(expression("1",&mut symbols).unwrap()))];
    let token=crate::daemon::control::Cancellation::default();let binding=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));let schedule=classification::cancel_after_pending_for_test(token);
    let InitializerClassificationFailure::Operational(actual)=classify_with_token_mode_checked(&writes,&symbols,&Source,false).err().unwrap()else{panic!("pending semantic result cannot bypass final operation guard")};assert_eq!(actual.kind(),std::io::ErrorKind::Interrupted);drop(schedule);drop(binding);
    let InitializerClassificationFailure::Semantic(source)=classify_with_token_mode_checked(&writes,&symbols,&Source,false).err().unwrap()else{panic!("same genuine source classification after recovery")};assert_eq!(source.issues[0].reason,"genuine semantic failure before final boundary");
}

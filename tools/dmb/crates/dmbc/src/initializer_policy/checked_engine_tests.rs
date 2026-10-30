use super::*;
fn engine()->crate::engine::EngineSnapshot{crate::engine::EngineSnapshot::from_bytes(include_bytes!("../../../../fixtures/native_template.bin"),1).unwrap()}
fn write()->InitializerWrite{
 let owner=SymbolId::of("/datum/test");let name=SymbolId::of("value");
 InitializerWrite{source_site:dm_ir::InitializerSite::Declaration,target:InitializerTarget::Instance{declaring_owner:owner,receiver_owner:owner,name},lexical_owner:owner,lexical_procedure:None,value:InitializerValue::NoAuthoredValue,declared_array:None,declaration_flags:Some(0)}
}
struct Native;
impl CapturedInitializerEvaluator for Native{
 fn evaluate(&self,_:SymbolId,_:&SymbolicExpression)->Result<Evaluation,String>{panic!("checked engine must not select wrapped compatibility String hook")}
 fn evaluate_prepared_write_checked(&self,_:&InitializerWrite,_:&SymbolicExpression)->Result<(Evaluation,Option<PreparedInitializerExpression>),InitializerFailure>{
  crate::daemon::control::checkpoint().map_err(InitializerFailure::Operational)?;Ok((Evaluation::Scalar(SemanticValue::Null),None))
 }
 fn declaration_modifiers(&self,_:&InitializerWrite)->Result<Option<u32>,String>{Ok(Some(8))}
 fn declaration_modifiers_checked(&self,_:&InitializerWrite)->Result<Option<u32>,InitializerFailure>{Err(InitializerFailure::Operational(std::io::Error::from_raw_os_error(1450)))}
}
#[test]
fn checked_engine_initializer_forwards_actual_io_before_legacy_flags_or_engine_fallback(){
 let engine=engine();let wrapper=EngineCapturedEvaluator{engine:&engine,evaluator:&Native};let write=write();
 assert_eq!(wrapper.declaration_modifiers(&write).unwrap(),Some(8));
 assert_eq!(wrapper.binding_knowledge(&write).unwrap(),Some(BindingKnowledge::Modifiers(8)));
 for error in [wrapper.declaration_modifiers_checked(&write).err().unwrap(),wrapper.binding_knowledge_checked(&write).err().unwrap()]{assert_eq!(error.into_operational().unwrap().raw_os_error(),Some(1450));}
}
#[test]
fn checked_engine_original_operation_cancellation_recovers_without_string_hook(){
 let engine=engine();let wrapper=EngineCapturedEvaluator{engine:&engine,evaluator:&Native};let write=write();let expression=SymbolicExpression{tokens:Arc::from([])};
 let token=crate::daemon::control::Cancellation::default();let binding=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));token.cancel();
 let actual=wrapper.evaluate_prepared_write_checked(&write,&expression).err().expect("actual wrapped cancellation").into_operational().unwrap();assert_eq!(actual.kind(),std::io::ErrorKind::Interrupted);drop(binding);
 assert!(matches!(wrapper.evaluate_prepared_write_checked(&write,&expression).unwrap().0,Evaluation::Scalar(SemanticValue::Null)));
}

use super::*;
use std::cell::Cell;
fn write()->InitializerWrite{
 let owner=SymbolId::of("/datum/test");let name=SymbolId::of("value");
 InitializerWrite{source_site:dm_ir::InitializerSite::Declaration,
 target:dm_ir::InitializerTarget::Instance{declaring_owner:owner,receiver_owner:owner,name},
 lexical_owner:owner,lexical_procedure:None,value:dm_ir::InitializerValue::NoAuthoredValue,
 declared_array:None,declaration_flags:Some(0)}
}
#[test]
fn checked_initializer_defaults_preserve_exact_custom_compatibility_hooks(){
 struct Hooks(Cell<usize>);
 impl CapturedInitializerEvaluator for Hooks{
  fn evaluate(&self,_:SymbolId,_:&SymbolicExpression)->Result<Evaluation,String>{panic!("prepared override must not select another evaluator")}
  fn evaluate_prepared_write(&self,_:&InitializerWrite,_:&SymbolicExpression)->Result<(Evaluation,Option<PreparedInitializerExpression>),String>{
   self.0.set(self.0.get()+1);Ok((Evaluation::SourceError("unchanged actual source classification".into()),None))
  }
  fn evaluate_write(&self,_:&InitializerWrite,_:&SymbolicExpression)->Result<Evaluation,String>{Err("custom write domain".into())}
  fn initializer_token_scalar(&self,_:&SemanticValue)->Result<Vec<u8>,String>{Ok(vec![19,37])}
  fn binding_knowledge(&self,_:&InitializerWrite)->Result<Option<BindingKnowledge>,String>{Ok(Some(BindingKnowledge::Modifiers(8)))}
 }
 let hooks=Hooks(Cell::new(0));let write=write();let expression=SymbolicExpression{tokens:std::sync::Arc::from([])};
 let (evaluation,prepared)=hooks.evaluate_prepared_write_checked(&write,&expression).unwrap();
 assert!(matches!(evaluation,Evaluation::SourceError(ref reason) if reason=="unchanged actual source classification"));
 assert!(prepared.is_none());assert_eq!(hooks.0.get(),1);
 let failure=hooks.evaluate_write_checked(&write,&expression).err().expect("actual old override");
 assert!(matches!(failure,InitializerFailure::Unsupported(ref reason) if reason=="custom write domain"));
 assert_eq!(hooks.initializer_token_scalar_checked(&SemanticValue::Null).unwrap(),vec![19,37]);
 assert_eq!(hooks.binding_knowledge_checked(&write).unwrap(),Some(BindingKnowledge::Modifiers(8)));
}
#[test]
fn initializer_operational_transport_keeps_original_io_kind_os_code_and_cause(){
 use std::error::Error;
 #[derive(Debug)]struct Cause;
 impl std::fmt::Display for Cause{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.write_str("actual owned cause")}}
 impl Error for Cause{}
 let failure=InitializerFailure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,Cause));
 assert_eq!(failure.operational().unwrap().kind(),std::io::ErrorKind::OutOfMemory);
 assert!(failure.source().unwrap().downcast_ref::<std::io::Error>().unwrap().get_ref().unwrap().is::<Cause>());
 let actual=failure.into_operational().unwrap();assert!(actual.get_ref().unwrap().is::<Cause>());
 let original=InitializerFailure::Operational(std::io::Error::from_raw_os_error(1450)).into_operational().unwrap();
 assert_eq!(original.raw_os_error(),Some(1450));
 let semantic=InitializerFailure::Unsupported("same semantic refusal".into()).into_operational().err().unwrap();
 assert!(semantic.operational().is_none());assert!(semantic.source().is_none());
}
#[test]
fn checked_initializer_leaf_actual_cancellation_is_not_unsupported_and_same_operation_recovers(){
 struct Native;
 impl CapturedInitializerEvaluator for Native{
  fn evaluate(&self,_:SymbolId,_:&SymbolicExpression)->Result<Evaluation,String>{panic!("native checked operation cannot go through String")}
  fn evaluate_prepared_write_checked(&self,_:&InitializerWrite,_:&SymbolicExpression)->Result<(Evaluation,Option<PreparedInitializerExpression>),InitializerFailure>{
   crate::daemon::control::checkpoint().map_err(InitializerFailure::Operational)?;
   Ok((Evaluation::Scalar(SemanticValue::NumberBits(1f32.to_bits())),None))
  }
 }
 let native=Native;let write=write();let expression=SymbolicExpression{tokens:std::sync::Arc::from([])};
 let token=crate::daemon::control::Cancellation::default();let binding=crate::daemon::control::bind_with_deadline(token.clone(),
 std::time::Instant::now()+std::time::Duration::from_secs(30));token.cancel();
 let error=native.evaluate_prepared_write_checked(&write,&expression).err().expect("actual current cancellation").into_operational().unwrap();
 assert_eq!(error.kind(),std::io::ErrorKind::Interrupted);drop(binding);
 let (evaluation,_) = native.evaluate_prepared_write_checked(&write,&expression).unwrap();
 assert!(matches!(evaluation,Evaluation::Scalar(SemanticValue::NumberBits(bits)) if bits==1f32.to_bits()));
}

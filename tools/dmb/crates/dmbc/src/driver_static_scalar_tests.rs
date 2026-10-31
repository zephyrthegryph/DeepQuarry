use super::*;
use crate::initializer_policy::{CapturedInitializerEvaluator,InitializerFailure};
use std::path::Path;
struct Source;impl dm_preprocess::SourceProvider for Source{fn read(&self,_:&Path)->Result<String,String>{Ok("/proc/p()\n    var/const/base=1+2\n    var/const/value=base+4\n    return value\n".into())}}
#[test]
fn actual_checked_driver_static_hook_reuses_complete_original_roots_and_transitive_canonical_static_without_text_parse(){
 let db=Arc::new(crate::query_db::QueryDb::default());let host=db.clone() as Arc<dyn dm_tree::frontend::SettingExpressionQueries>;let executor=dm_exec::BuildExecutor::new(1).unwrap();
 let front=dm_tree::frontend::build(Path::new("driver-static-original.dme"),&Source,&Default::default(),1).unwrap().with_setting_expression_queries(&host).unwrap();
 let bodies=dm_tree::frontend::BodyArena::new_typed(&front,dm_codegen_byond::typed_statements_supported_for_capture);
 let startup=crate::startup::capture_original_with_executor_and_bodies_checked(&front,&[],&executor,&bodies).unwrap();
 let resolver=startup.resolver(&front,front.snapshot.tree.as_ref()).unwrap();let driver=DriverEvaluator{pure_calls:None,resource_search_context:None,resolver:&resolver,symbols:&startup.plan().symbols};
 let context=front.original_issued_initializer_context(startup.issued_initializer_plan()).unwrap();let ordinal=startup.plan().writes.iter().position(|write|matches!(write.target,dm_ir::InitializerTarget::ProcedureStatic(id)if id.name==SymbolId::of("value"))).unwrap();let input=context.input(ordinal).unwrap();let root=input.expression().unwrap();
 let dm_ir::InitializerValue::Expression(value)=&input.original_write().value else{panic!("actual authored static RHS")};
 let expected=driver.evaluate_prepared_write(input.original_write(),value).unwrap().0;let Evaluation::Scalar(SemanticValue::NumberBits(expected))=expected else{panic!("legacy numeric static")};
 let before=SCALAR_TEXT_PARSES.with(|n|n.get());let(actual,prepared)=driver.evaluate_original_write_checked(&input,input.original_write()).unwrap();
 let Evaluation::Scalar(SemanticValue::NumberBits(actual))=actual else{panic!("original numeric static")};assert_eq!(actual,7.0_f32.to_bits());assert_eq!(actual,expected);assert!(root.same_root(prepared.unwrap().original().unwrap()));assert_eq!(SCALAR_TEXT_PARSES.with(|n|n.get()),before);
 let token=crate::daemon::control::Cancellation::default();let binding=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(300));token.cancel();
 assert!(matches!(driver.evaluate_original_write_checked(&input,input.original_write()),Err(InitializerFailure::Operational(ref e))if e.kind()==std::io::ErrorKind::Interrupted));drop(binding);
 let(recovered,prepared)=driver.evaluate_original_write_checked(&input,input.original_write()).unwrap();assert!(matches!(recovered,Evaluation::Scalar(SemanticValue::NumberBits(bits))if bits==actual));assert!(root.same_root(prepared.unwrap().original().unwrap()));assert_eq!(db.db().stats(dm_query::Kind(4)).computed,0);
}

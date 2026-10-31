use super::*;
use crate::initializer_policy::{CapturedInitializerEvaluator,InitializerFailure};
use dm_tree::frontend::{ColdFrontend,FrontendConfig,RetainedSemanticTree,SettingExpressionQueries};
use std::path::Path;
struct Source(dm_preprocess::AcquiredSource);
impl dm_preprocess::SourceProvider for Source{
 fn read(&self,_:&Path)->Result<String,String>{Err("original byte acquisition required".into())}
 fn acquired_source(&self,_:&Path)->Result<Option<dm_preprocess::AcquiredSource>,String>{Ok(Some(self.0.clone()))}
 fn source_acquisition(&self,_:&Path,text:&dm_preprocess::SourceText)->Option<dm_preprocess::AcquiredSource>{self.0.lease().source_text().same_view(text).then(||self.0.clone())}
}
fn front(text:&str,host:&Arc<dyn SettingExpressionQueries>)->ColdFrontend{
 let source=Source(dm_preprocess::AcquiredSource::from_original_bytes(text.as_bytes().to_vec(),()));
 let executor=dm_exec::BuildExecutor::new(1).unwrap();
 dm_tree::frontend::build_with_executor_and_semantic_state_for_policy_checked(Path::new("native-scalar-original.dme"),&source,&Default::default(),FrontendConfig{workers:1,engine:None,observer:None},None,&executor,Some(&mut RetainedSemanticTree::default()),true,host).unwrap()
}
fn scalar_bits(evaluation:Evaluation)->u32{let Evaluation::Scalar(SemanticValue::NumberBits(bits))=evaluation else{panic!("actual captured numeric scalar")};bits}
#[test]
fn native_original_scalar_top_and_transitive_constants_share_current_roots_without_text_reparse_and_match_legacy(){
 let db=Arc::new(crate::query_db::QueryDb::default());let host=db.clone() as Arc<dyn SettingExpressionQueries>;
 let front=front("var/const/base=7\nvar/const/next=base+1\nvar/static/value=next+1\n",&host);
 let plan=dm_tree::initializers::capture_declaration_plan(&front.snapshot,&front.emission_order).unwrap();
 let input=front.original_initializer_input(&plan,2).unwrap();let root=input.expression().unwrap();let ptr=root.ast() as *const dm_syntax::Expr;
 let context=front.original_declaration_expression_context().unwrap();
 let driver=DriverEvaluator{pure_calls:None,resource_search_context:None,resolver:front.snapshot.tree.as_ref(),symbols:front.snapshot.tree.symbols()};
 let dm_ir::InitializerValue::Expression(value)=&input.original_write().value else{panic!("actual RHS")};
 let expected=scalar_bits(driver.evaluate_prepared_write(input.original_write(),value).unwrap().0);
 let before=SCALAR_TEXT_PARSES.with(|n|n.get());
 let(actual,prepared)=driver.evaluate_original_write_in(&input,input.original_write(),&context).unwrap();
 assert_eq!(scalar_bits(actual),expected);assert_eq!(expected,9.0_f32.to_bits());
 let prepared=prepared.unwrap();assert_eq!(prepared.ast() as *const dm_syntax::Expr,ptr);
 assert_eq!(SCALAR_TEXT_PARSES.with(|n|n.get()),before,"top and recursive original declarations never render/reparse symbolic expressions");
 let tree=&front.snapshot.tree;let next=tree.resolve(tree.lookup_type(SymbolId::of("/")).unwrap(),SymbolId::of("next"),dm_tree::MemberKind::Var).unwrap();
 let nested=context.selected(SymbolId::of("/"),SymbolId::of("next"),&tree.member(next).unwrap().metadata).unwrap().expression().unwrap();
 assert!(nested.same_root(&context.selected(SymbolId::of("/"),SymbolId::of("next"),&tree.member(next).unwrap().metadata).unwrap().expression().unwrap()));
 assert_eq!(db.db().stats(dm_query::Kind(4)).computed,0);
}
#[test]
fn native_actual_constant_chain_stack_denial_is_operational_and_same_original_owner_recovers(){
 let capacity=dm_exec::COMPILER_STACK_BYTES/16/(16*1024);assert!(capacity>=8);
 let length=(capacity/8).max(3).min(32);
 let mut text=String::new();for n in 0..length{text.push_str(&format!("var/const/c{n}=c{}+1\n",n+1));}text.push_str(&format!("var/const/c{length}=1\n"));
 let db=Arc::new(crate::query_db::QueryDb::default());let host=db.clone() as Arc<dyn SettingExpressionQueries>;
 let front=front(&text,&host);let plan=dm_tree::initializers::capture_declaration_plan(&front.snapshot,&front.emission_order).unwrap();
 let input=front.original_initializer_input(&plan,0).unwrap();let root=input.expression().unwrap();
 let context=front.original_declaration_expression_context().unwrap();
 let driver=DriverEvaluator{pure_calls:None,resource_search_context:None,resolver:front.snapshot.tree.as_ref(),symbols:front.snapshot.tree.symbols()};
 let failed=scalar_demand::with_admission(&context,|a|{
  let mut held=Vec::new();for _ in 0..capacity-4{held.push(a.evaluation_frame().map_err(InitializerFailure::Operational)?);}
  driver.evaluate_original_write_admitted(&input,input.original_write(),&context,a)
 });
 assert!(matches!(failed,Err(InitializerFailure::Operational(ref actual))if actual.kind()==std::io::ErrorKind::OutOfMemory));
 let(actual,prepared)=driver.evaluate_original_write_in(&input,input.original_write(),&context).unwrap();
 assert_eq!(scalar_bits(actual),((length+1)as f32).to_bits());
 assert!(root.same_root(prepared.unwrap().original().unwrap()),"no failed scalar operation poisons or replaces the original source root");
 assert_eq!(db.db().stats(dm_query::Kind(4)).computed,0);
}
#[test]
fn original_scalar_rejects_foreign_frame_and_adapted_value_but_preserves_genuine_invalid_rhs_policy(){
 let db=Arc::new(crate::query_db::QueryDb::default());let host=db.clone() as Arc<dyn SettingExpressionQueries>;
 let a=front("var/static/value=1+2\n",&host);let b=front("var/static/value=1+2\n",&host);
 let plan=dm_tree::initializers::capture_declaration_plan(&a.snapshot,&a.emission_order).unwrap();let input=a.original_initializer_input(&plan,0).unwrap();
 let context=a.original_declaration_expression_context().unwrap();let foreign=b.original_declaration_expression_context().unwrap();
 let driver=DriverEvaluator{pure_calls:None,resource_search_context:None,resolver:a.snapshot.tree.as_ref(),symbols:a.snapshot.tree.symbols()};
 assert!(matches!(driver.evaluate_original_write_in(&input,input.original_write(),&foreign),Err(InitializerFailure::Unsupported(_))));
 let mut altered=input.original_write().clone();let dm_ir::InitializerValue::Expression(value)=&mut altered.value else{panic!("actual RHS")};value.tokens=value.tokens.iter().cloned().collect::<Vec<_>>().into();
 assert!(matches!(driver.evaluate_original_write_in(&input,&altered,&context),Err(InitializerFailure::Unsupported(_))),"equal copied tokens cannot replace the original ordinal receipt");
 let invalid=front("var/static/value=1+\n",&host);let plan=dm_tree::initializers::capture_declaration_plan(&invalid.snapshot,&invalid.emission_order).unwrap();let input=invalid.original_initializer_input(&plan,0).unwrap();let context=invalid.original_declaration_expression_context().unwrap();
 let driver=DriverEvaluator{pure_calls:None,resource_search_context:None,resolver:invalid.snapshot.tree.as_ref(),symbols:invalid.snapshot.tree.symbols()};
 let dm_ir::InitializerValue::Expression(value)=&input.original_write().value else{panic!("actual RHS")};
 let old=driver.evaluate_prepared_write(input.original_write(),value).err().unwrap();
 let new=driver.evaluate_original_write_in(&input,input.original_write(),&context).err().unwrap();
 assert!(matches!(new,InitializerFailure::Unsupported(ref reason)if reason==&old),"cached genuine root syntax retains original scalar error policy");
}

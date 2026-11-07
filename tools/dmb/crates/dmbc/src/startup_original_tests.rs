use super::*;
use std::{path::Path,sync::{Arc,atomic::Ordering}};
struct Source;
impl dm_preprocess::SourceProvider for Source{fn read(&self,_:&Path)->Result<String,String>{Ok("/proc/original_scope_counter()\n    var/const/base=1+2\n    var/const/value=base+4\n    return value\n".into())}}
fn front(db:&Arc<crate::query_db::QueryDb>)->ColdFrontend{
 let host=db.clone() as Arc<dyn dm_tree::frontend::SettingExpressionQueries>;
 dm_tree::frontend::build(Path::new("original-startup-counter.dme"),&Source,&Default::default(),1).unwrap().with_setting_expression_queries(&host).unwrap()
}
fn capture<'a>(front:&'a ColdFrontend,executor:&dm_exec::BuildExecutor,artifacts:Option<&StartupArtifacts>)->Result<OriginalStartup<'a>,StartupFailure>{
 let arena=dm_tree::frontend::BodyArena::new_typed(front,dm_codegen_byond::typed_statements_supported_for_capture);
 match artifacts{Some(store)=>capture_original_with_artifacts_checked(front,&[],executor,&arena,store),None=>capture_original_with_executor_and_bodies_checked(front,&[],executor,&arena)}
}
fn receipt<'borrow>(startup:&'borrow CapturedStartup<'_>)->&'borrow Arc<dm_tree::frontend::IssuedStaticPlan>{startup.procedure_captures().iter().find_map(|(_,capture)|match capture{ProcedureCapture::Issued(receipt)=>Some(receipt),_=>None}).unwrap()}
fn key(front:&ColdFrontend)->Vec<u8>{let body=&front.bodies[0];let identity=front.callable_roster().unwrap().identity_for_member(body.member).unwrap();artifacts::key(identity,front.body_input(body).unwrap().source())}
#[test]
fn actual_original_startup_inventory_shares_canonical_static_objects_with_and_without_existing_artifacts(){
 let db=Arc::new(crate::query_db::QueryDb::default());let front=front(&db);let executor=dm_exec::BuildExecutor::new(1).unwrap();
 let store=StartupArtifacts::default();
 for artifacts in [None,Some(&store)]{
  let startup=capture(&front,&executor,artifacts).unwrap();let receipt=receipt(&startup);let canonical=receipt.canonical_declarations().unwrap();
  let inventory=startup.static_inventory();let host=startup.resolver(&front,front.snapshot.tree.as_ref()).unwrap();
  for declaration in canonical.iter(){
   assert!(Arc::ptr_eq(inventory.declaration(declaration.identity).unwrap(),declaration));
   let dm_ir::ResolvedMeaning::ProcedureStatic(actual)=dm_ir::Resolver::resolve(&host,dm_ir::ResolveQuery::ProcedureStatic{procedure:declaration.identity.procedure,name:declaration.identity.name})else{panic!("original static positive")};
   assert!(Arc::ptr_eq(&actual,declaration),"actual static resolver returns SAME original canonical object");
   let ordinal=startup.plan().origins.iter().position(|origin|matches!(origin.kind,dm_tree::initializers::InitializerOriginKind::ProcedureStatic{identity,..}if identity==declaration.identity)).unwrap();
   let context=front.original_issued_initializer_context(startup.issued_initializer_plan()).unwrap();let input=context.input(ordinal).unwrap();let transitive=input.declaration_context();
   transitive.with_admission(&mut|a|{transitive.selected_static_admitted(receipt,declaration.identity,declaration,a)?.prepare(a)?;Ok(())}).unwrap();
  }
  let compatibility=dm_tree::procedure_statics::StaticResolver::from_plans(front.snapshot.tree.as_ref(),startup.procedures().map(|(_,plan)|(plan.procedure,plan))).unwrap();
  assert_eq!(dm_ir::Resolver::answer_world(&host),dm_ir::Resolver::answer_world(&compatibility));
 }
 assert_eq!(db.db().stats(dm_query::Kind(4)).computed,0);
}
#[test]
fn original_startup_replaces_foreign_counter_cached_parent_then_same_input_reuses_current_parent(){
 fn version(db:&Arc<crate::query_db::QueryDb>,executor:&dm_exec::BuildExecutor,state:&mut dm_tree::frontend::RetainedSemanticTree)->ColdFrontend{
  let host=db.clone() as Arc<dyn dm_tree::frontend::SettingExpressionQueries>;
  dm_tree::frontend::build_with_executor_and_semantic_state(Path::new("original-startup-counter.dme"),&Source,&Default::default(),dm_tree::frontend::FrontendConfig{workers:1,engine:None,observer:None},None,executor,Some(state)).unwrap().with_setting_expression_queries(&host).unwrap()
 }
 let first=Arc::new(crate::query_db::QueryDb::default());let executor=dm_exec::BuildExecutor::new(1).unwrap();let mut state=dm_tree::frontend::RetainedSemanticTree::default();let frontend=version(&first,&executor,&mut state);let artifacts=StartupArtifacts::default();
 {let startup=capture(&frontend,&executor,Some(&artifacts)).unwrap();assert!(receipt(&startup).retained_statement_body().is_some());}
 let old=artifacts.lookup(&key(&frontend)).unwrap();let old_parent=Arc::clone(old.retained_statement_body().unwrap());
 assert!(crate::query_db::body_syntax_counter_for_test(&first).load(Ordering::Acquire)>dm_syntax::SettingChargeCounter::root_allocation_bytes());
 let second=Arc::new(crate::query_db::QueryDb::default());
 let current_frontend=version(&second,&executor,&mut state);
 let rebound=old.bind(&current_frontend,&current_frontend.bodies[0]).unwrap();
 assert!(Arc::ptr_eq(rebound.retained_statement_body().expect("same original body-code parent survives ordinary bind"),&old_parent));
 let host=second.clone() as Arc<dyn dm_tree::frontend::SettingExpressionQueries>;let mut admitted=None;
 host.with_declaration_admission(&mut|a|{admitted=Some(rebound.admitted_by(a)?);Ok(())}).unwrap();assert_eq!(admitted,Some(false),"current source/code proof cannot transfer the old budget domain");
 let frontend=current_frontend;let before=artifacts.recomputed.load(Ordering::Relaxed);
 let current=capture(&frontend,&executor,Some(&artifacts)).unwrap();let current_parent=Arc::clone(receipt(&current).retained_statement_body().unwrap());
 assert!(!Arc::ptr_eq(&old_parent,&current_parent),"foreign counter cache is not source admission");
 assert_eq!(artifacts.recomputed.load(Ordering::Relaxed),before+1);
 let charged=crate::query_db::body_syntax_counter_for_test(&second).load(Ordering::Acquire);assert!(charged>dm_syntax::SettingChargeCounter::root_allocation_bytes());
 let before_hit=artifacts.hits.load(Ordering::Relaxed);let warm=capture(&frontend,&executor,Some(&artifacts)).unwrap();
 assert!(Arc::ptr_eq(receipt(&warm).retained_statement_body().unwrap(),&current_parent));
 assert_eq!(artifacts.hits.load(Ordering::Relaxed),before_hit+1);assert_eq!(crate::query_db::body_syntax_counter_for_test(&second).load(Ordering::Acquire),charged);
 assert_eq!(first.db().stats(dm_query::Kind(4)).computed,0);assert_eq!(second.db().stats(dm_query::Kind(4)).computed,0);
}
#[test]
fn original_startup_quota_failure_publishes_no_plan_or_bad_syntax_and_same_input_recovers(){
 let db=Arc::new(crate::query_db::QueryDb::default());let front=dm_tree::frontend::build(Path::new("original-startup-counter.dme"),&Source,&Default::default(),1).unwrap();let executor=dm_exec::BuildExecutor::new(1).unwrap();let artifacts=StartupArtifacts::default();
 let legacy_arena=dm_tree::frontend::BodyArena::new_typed(&front,dm_codegen_byond::typed_statements_supported_for_capture);
 let legacy=capture_facts_with_executor_and_bodies_and_artifacts(&front,&[],&executor,&legacy_arena,Some(&artifacts),None).unwrap();
 let old=artifacts.lookup(&key(&front)).unwrap();assert!(!old.retained_statement_body().is_some_and(|body|body.has_native_literal_syntax()));drop(legacy);drop(legacy_arena);
 assert_eq!(crate::query_db::body_syntax_counter_for_test(&db).load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
 let host=db.clone() as Arc<dyn dm_tree::frontend::SettingExpressionQueries>;let front=front.with_setting_expression_queries(&host).unwrap();
 let healthy=||Ok(());let budget=crate::query_db::body_syntax_budget_for_test();let admission=dm_syntax::SettingAdmission::new(crate::query_db::body_syntax_counter_for_test(&db),budget,&healthy);let held=admission.reserve(budget - crate::query_db::body_syntax_counter_for_test(&db).load(Ordering::Acquire)).unwrap();
 let arena=dm_tree::frontend::BodyArena::new_typed(&front,dm_codegen_byond::typed_statements_supported_for_capture);let before=artifacts.recomputed.load(Ordering::Relaxed);
 let failure=capture_original_with_artifacts_checked(&front,&[],&executor,&arena,&artifacts).err().expect("actual current body quota");
 assert!(matches!(failure,StartupFailure::Operational(ref actual)if actual.kind()==std::io::ErrorKind::OutOfMemory));
 assert_eq!(artifacts.recomputed.load(Ordering::Relaxed),before);assert!(Arc::ptr_eq(&old,&artifacts.lookup(&key(&front)).unwrap()));
 drop(held);drop(admission);assert_eq!(crate::query_db::body_syntax_counter_for_test(&db).load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
 let current=capture_original_with_artifacts_checked(&front,&[],&executor,&arena,&artifacts).unwrap();
 assert!(receipt(&current).retained_statement_body().unwrap().has_native_literal_syntax());assert_eq!(db.db().stats(dm_query::Kind(4)).computed,0);
}
#[test]
fn source_required_cache_actual_io_is_not_a_miss_or_cached_error_and_same_key_recovers(){
 let db=Arc::new(crate::query_db::QueryDb::default());let front=front(&db);let executor=dm_exec::BuildExecutor::new(1).unwrap();let artifacts=StartupArtifacts::default();let startup=capture(&front,&executor,Some(&artifacts)).unwrap();let key=key(&front);
 let before=artifacts.hits.load(Ordering::Relaxed);
 let failure=artifacts.lookup_original::<std::io::Error>(&key,&mut |_|Err(std::io::Error::from_raw_os_error(1450))).err().expect("actual callback IO");
 assert_eq!(failure.raw_os_error(),Some(1450));assert_eq!(artifacts.hits.load(Ordering::Relaxed),before);
 let warm=capture(&front,&executor,Some(&artifacts)).unwrap();assert!(Arc::ptr_eq(receipt(&startup).retained_statement_body().unwrap(),receipt(&warm).retained_statement_body().unwrap()));
}
#[test]
fn original_startup_absent_provider_and_cancelled_empty_inputs_do_not_downgrade_to_ordinary_capture(){
 struct Empty;impl dm_preprocess::SourceProvider for Empty{fn read(&self,_:&Path)->Result<String,String>{Ok(String::new())}}
 let front=dm_tree::frontend::build(Path::new("empty-original-startup.dme"),&Empty,&Default::default(),1).unwrap();let executor=dm_exec::BuildExecutor::new(1).unwrap();let arena=dm_tree::frontend::BodyArena::new_typed(&front,|_|true);
 assert!(capture_with_executor_and_bodies_checked(&front,&[],&executor,&arena).is_ok());
 assert!(matches!(capture_original_with_executor_and_bodies_checked(&front,&[],&executor,&arena),Err(StartupFailure::Operational(ref actual))if actual.kind()==std::io::ErrorKind::NotConnected));
 let token=crate::daemon::control::Cancellation::default();let binding=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(300));token.cancel();
 assert!(matches!(capture_original_with_executor_and_bodies_checked(&front,&[],&executor,&arena),Err(StartupFailure::Operational(ref actual))if actual.kind()==std::io::ErrorKind::Interrupted));drop(binding);
}

struct SourceWithDimensions;
impl dm_preprocess::SourceProvider for SourceWithDimensions{fn read(&self,_:&Path)->Result<String,String>{Ok("var/static/global_value=unknown+1\nvar/static/list/global_items[1+2]=null\n/proc/p()\n    var/const/base=1+2\n    var/const/value=base+4\n    var/static/list/items[base][]\n    return value\n".into())}}
#[derive(Default)]struct OriginalOnlyOrdinary(std::sync::atomic::AtomicUsize);
impl crate::initializer_policy::CapturedInitializerEvaluator for OriginalOnlyOrdinary{
 fn evaluate(&self,_:dm_ir::SymbolId,_:&dm_ir::SymbolicExpression)->Result<crate::initializer_policy::Evaluation,String>{panic!("legacy owned/text evaluator must not be called")}
 fn evaluate_original_write_checked<'source>(&self,_:&dm_tree::frontend::OriginalInitializerExpressionInput<'source>,_:&dm_ir::InitializerWrite)->Result<(crate::initializer_policy::Evaluation,Option<crate::initializer_policy::ScopedPreparedInitializerExpression<'source>>),crate::initializer_policy::InitializerFailure>{self.0.fetch_add(1,Ordering::Relaxed);Err(crate::initializer_policy::InitializerFailure::Operational(std::io::Error::from_raw_os_error(1450)))}
 fn evaluate_original_dimension_checked(&self,_:&dm_tree::frontend::OriginalInitializerDimensionInput<'_>,_:&dm_ir::InitializerWrite)->Result<crate::initializer_policy::Evaluation,crate::initializer_policy::InitializerFailure>{self.0.fetch_add(1,Ordering::Relaxed);Err(crate::initializer_policy::InitializerFailure::Operational(std::io::Error::from_raw_os_error(1450)))}
 fn evaluate_original_ast_write_checked<'source>(&self,_:&dm_tree::frontend::OriginalInitializerExpressionInput<'source>,_:&dm_ir::InitializerWrite,_:&dm_tree::frontend::OriginalInitializerExpression<'source>,_:&dm_syntax::Expr,_:&dm_ir::SymbolTable)->Result<crate::initializer_policy::Evaluation,crate::initializer_policy::InitializerFailure>{self.0.fetch_add(1,Ordering::Relaxed);Err(crate::initializer_policy::InitializerFailure::Operational(std::io::Error::from_raw_os_error(1450)))}
}
#[test]
fn original_prepared_startup_preserves_revision_receipts_and_lexical_source_hooks(){
 use crate::initializer_policy::{CapturedInitializerEvaluator,Evaluation};
 let db=Arc::new(crate::query_db::QueryDb::default());let host=db.clone() as Arc<dyn dm_tree::frontend::SettingExpressionQueries>;let frontend=dm_tree::frontend::build(Path::new("prepared-original-hooks.dme"),&SourceWithDimensions,&Default::default(),1).unwrap().with_setting_expression_queries(&host).unwrap();let revision=dm_tree::frontend::FrontendRevision::new(frontend);let executor=dm_exec::BuildExecutor::new(1).unwrap();let roster=crate::lowering::PreparedBodyRoster::issue(&revision).ok().unwrap();let arena=dm_tree::frontend::BodyArena::new_typed(&revision,dm_codegen_byond::typed_statements_supported_for_capture);let store=StartupArtifacts::default();
 let startup=capture_original_with_prepared_bodies_checked(&revision,Some(&revision),&[],&executor,&arena,Some(&store),&roster).unwrap();startup.validate_for(&revision).unwrap();assert!(startup.issued_initializer_plan().matches_frontend(&revision));
 let resolver=startup.resolver(&revision,revision.snapshot.tree.as_ref()).unwrap();let ordinary=OriginalOnlyOrdinary::default();let evaluator=StartupEvaluator{ordinary:&ordinary,resolver:&resolver,symbols:&startup.plan().symbols,resource_search_context:None};let context=revision.original_issued_initializer_context(startup.issued_initializer_plan()).unwrap();
 let ordinal=startup.plan().writes.iter().position(|write|matches!(write.target,dm_ir::InitializerTarget::ProcedureStatic(identity)if identity.name==dm_ir::SymbolId::of("value"))).unwrap();let input=context.input(ordinal).unwrap();let (value,root)=evaluator.evaluate_original_write_checked(&input,input.original_write()).unwrap();assert!(matches!(value,Evaluation::Scalar(dm_ir::SemanticValue::NumberBits(bits))if bits==7f32.to_bits()));let root=root.unwrap();let original=root.original().unwrap();assert!(matches!(evaluator.evaluate_original_ast_write_checked(&input,input.original_write(),original,root.ast(),&startup.plan().symbols).unwrap(),Evaluation::Scalar(dm_ir::SemanticValue::NumberBits(bits))if bits==7f32.to_bits()));
 let array=startup.plan().writes.iter().position(|write|matches!(write.target,dm_ir::InitializerTarget::ProcedureStatic(identity)if identity.name==dm_ir::SymbolId::of("items"))).unwrap();let dimension=context.dimension_input(array,0).unwrap();assert!(matches!(evaluator.evaluate_original_dimension_checked(&dimension,dimension.original_write()).unwrap(),Evaluation::Scalar(dm_ir::SemanticValue::NumberBits(bits))if bits==3f32.to_bits()));assert_eq!(ordinary.0.load(Ordering::Relaxed),0,"lexical static original hooks use captured startup resolver, not ordinary/custom fallback");
 let fresh=capture_original_with_artifacts_checked(&revision,&[],&executor,&arena,&store).unwrap();assert_eq!(startup.plan().writes,fresh.plan().writes);assert_eq!(startup.plan().origins,fresh.plan().origins);
 let foreign=dm_tree::frontend::FrontendRevision::new(front(&db));assert!(matches!(capture_original_with_prepared_bodies_checked(&revision,Some(&foreign),&[],&executor,&arena,None,&roster),Err(StartupFailure::Semantic(_))));assert_eq!(db.db().stats(dm_query::Kind(4)).computed,0);
}
#[test]
fn original_startup_evaluator_delegates_nonstatic_source_hooks_and_preserves_actual_io(){
 use crate::initializer_policy::{CapturedInitializerEvaluator,InitializerFailure};
 let db=Arc::new(crate::query_db::QueryDb::default());let host=db.clone() as Arc<dyn dm_tree::frontend::SettingExpressionQueries>;let executor=dm_exec::BuildExecutor::new(1).unwrap();let frontend=dm_tree::frontend::build_with_executor_and_semantic_state_for_policy_checked(Path::new("ordinary-original-hooks.dme"),&SourceWithDimensions,&Default::default(),dm_tree::frontend::FrontendConfig{workers:1,engine:None,observer:None},None,&executor,None,true,&host).unwrap();let plan=dm_tree::initializers::capture_declaration_plan(&frontend.snapshot,&frontend.emission_order).unwrap();let context=frontend.original_initializer_context(&plan).unwrap();let ordinary=OriginalOnlyOrdinary::default();let evaluator=StartupEvaluator{ordinary:&ordinary,resolver:frontend.snapshot.tree.as_ref(),symbols:&plan.plan().symbols,resource_search_context:None};let input=context.input(0).unwrap();assert!(input.original_write().lexical_procedure.is_none());let root=input.expression().unwrap();
 assert!(matches!(evaluator.evaluate_original_write_checked(&input,input.original_write()),Err(InitializerFailure::Operational(ref actual))if actual.raw_os_error()==Some(1450)));assert!(matches!(evaluator.evaluate_original_ast_write_checked(&input,input.original_write(),&root,root.ast(),&plan.plan().symbols),Err(InitializerFailure::Operational(ref actual))if actual.raw_os_error()==Some(1450)));let dimension=context.dimension_input(1,0).unwrap();assert!(matches!(evaluator.evaluate_original_dimension_checked(&dimension,dimension.original_write()),Err(InitializerFailure::Operational(ref actual))if actual.raw_os_error()==Some(1450)));assert_eq!(ordinary.0.load(Ordering::Relaxed),3);
}

use super::*;
use dm_preprocess::{SourceProvider,SourceText};
use std::{io,path::Path};
struct Original(dm_preprocess::AcquiredSource);
impl SourceProvider for Original{
 fn read(&self,_:&Path)->Result<String,String>{Err("original acquisition required".into())}
 fn acquired_source(&self,_:&Path)->Result<Option<dm_preprocess::AcquiredSource>,String>{Ok(Some(self.0.clone()))}
 fn source_acquisition(&self,_:&Path,text:&SourceText)->Option<dm_preprocess::AcquiredSource>{self.0.lease().source_text().same_view(text).then(||self.0.clone())}
}
fn frontend(source:&str,db:&Arc<QueryDb>)->dm_tree::frontend::ColdFrontend{
 let provider=Original(dm_preprocess::AcquiredSource::from_original_bytes(source.as_bytes().to_vec(),()));
 dm_tree::frontend::build(Path::new("original-body-literal.dme"),&provider,&Default::default(),1).unwrap().with_body_queries(db.clone())
}
fn literal<'a>(body:&'a dm_tree::frontend::ArchivedBody<'_>)->&'a dm_syntax::LiteralText{
 let dm_syntax::StatementKind::Return(Some(dm_syntax::Expr{kind:dm_syntax::ExprKind::Literal(l),..}))=&body.statement_body().parsed().statements[0].kind else{panic!("actual original literal")};l
}
#[test]
fn original_header_is_body_free_and_real_kind4_consumers_share_literal_children_and_rebuild_owners(){
 let db=Arc::new(QueryDb::default());let frontend=frontend("/proc/p()\n    return \"value [1 + 2]\"\n",&db);let archive=frontend.body_archive().unwrap();
 assert_eq!(db.db().stats(BODY_SYNTAX).computed,0);
 let occurrence=&archive.occurrences()[0];archive.callable_header_policy_origin(occurrence.member).unwrap();
 assert_eq!(db.db().stats(BODY_SYNTAX).computed,0,"original headers never demand unused body syntax");
 let first=archive.parse_checked(0).unwrap();assert!(first.statement_body().has_native_literal_syntax());
 let children=literal(&first).retained_parts().unwrap().unwrap().unwrap().expressions.as_ptr();
 let warm=archive.parse_checked(0).unwrap();assert!(std::ptr::eq(first.statement_body(),warm.statement_body()));
 assert_eq!(literal(&warm).parts().unwrap().unwrap().expressions.as_ptr(),children);assert_eq!(db.db().stats(BODY_SYNTAX).computed,1);
 db.db.evict_values(&[BODY_SYNTAX]);let rebuilt=archive.parse_checked(0).unwrap();
 assert!(!std::ptr::eq(first.statement_body(),rebuilt.statement_body()));assert_ne!(literal(&rebuilt).parts().unwrap().unwrap().expressions.as_ptr(),children);
 assert_eq!(literal(&first).parts().unwrap().unwrap().expressions.as_ptr(),children,"escaped original owner is never grafted/mutated during fresh computation");
 assert_eq!(db.db().stats(BODY_SYNTAX).computed,2);
}
#[test]
fn real_kind4_cancel_has_no_semantic_outcome_and_same_original_input_retries(){
 let db=Arc::new(QueryDb::default());let frontend=frontend("/proc/p()\n    return \"value [1 + 2]\"\n",&db);let archive=frontend.body_archive().unwrap();
 let token=crate::daemon::control::Cancellation::default();let binding=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(300));token.cancel();
 let error=archive.parse_checked(0).err().expect("actual bound cancellation before body publication");
 assert!(matches!(error,BodySyntaxFailure::Operational(ref actual)if actual.kind()==io::ErrorKind::Interrupted));assert_eq!(db.db().stats(BODY_SYNTAX).computed,0);
 drop(binding);let body=archive.parse_checked(0).unwrap();assert!(body.statement_body().has_native_literal_syntax());assert_eq!(literal(&body).parts().unwrap().unwrap().expressions.len(),1);assert_eq!(db.db().stats(BODY_SYNTAX).computed,1);
 let again=archive.parse_checked(0).unwrap();assert!(std::ptr::eq(body.statement_body(),again.statement_body()));assert_eq!(db.db().stats(BODY_SYNTAX).computed,1,"operational status never poisoned the semantic body node");
}

fn one_shot_frontend(source:&str,db:&Arc<QueryDb>)->dm_tree::frontend::ColdFrontend{
 let provider=Original(dm_preprocess::AcquiredSource::from_original_bytes(source.as_bytes().to_vec(),()));
 let host:Arc<dyn dm_tree::frontend::SettingExpressionQueries>=db.clone();
 dm_tree::frontend::build(Path::new("original-one-shot-literal.dme"),&provider,&Default::default(),1).unwrap().with_setting_expression_queries(&host).unwrap()
}
fn static_literal(body:&dm_tree::frontend::StatementBody)->&dm_syntax::LiteralText{
 let dm_syntax::StatementKind::Var{value:Some(dm_syntax::Expr{kind:dm_syntax::ExprKind::Literal(l),..}),..}=&body.parsed().statements[0].kind else{panic!("actual source static literal")};l
}
#[test]
fn actual_one_shot_zero_set_static_body_uses_same_counter_after_demand_without_kind4_or_unused_body(){
 let db=Arc::new(QueryDb::default());
 let source="/proc/p()\n    var/static/value = \"value [1 + 2]\"\n    return value\n/proc/unused()\n    return \"unused [3 + 4]\"\n";
 let front=one_shot_frontend(source,&db);let body=&front.bodies[0];
 assert!(front.procedure_settings(body).unwrap().is_some(),"actual original metadata receipt exists without a body parse");
 assert!(front.snapshot.tree.member(body.member).unwrap().metadata.procedure.as_ref().unwrap().settings.is_empty());
 assert_eq!(db.body_charge.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
 let archive=front.body_archive().unwrap();archive.callable_header_policy_origin(body.member).unwrap();
 let raw=front.files.iter().find(|f|f.captured).expect("original captured compiler source");assert!(raw.text.contains("var/static/value"));
 assert_eq!(db.db().stats(BODY_SYNTAX).computed,0,"raw/header handling never demands a body query");
 assert_eq!(db.body_charge.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes(),"header handling does not prepare ordinary literal children");
 let arena=dm_tree::frontend::BodyArena::new_typed(&front,|_|true);
 let owner=arena.with_parsed_checked(body,|parsed|parsed.shared_statement_body().expect("actual checked one-shot statement owner")).unwrap();
 assert!(owner.has_native_literal_syntax());
 let child=static_literal(&owner).retained_parts().unwrap().unwrap().unwrap().expressions.as_ptr();
 let warm=arena.with_parsed_checked(body,|parsed|parsed.shared_statement_body().unwrap()).unwrap();
 assert!(Arc::ptr_eq(&owner,&warm));assert_eq!(static_literal(&warm).parts().unwrap().unwrap().expressions.as_ptr(),child);
 let mut retained=0;arena.visit_retained(|_,_|retained+=1);assert_eq!(retained,1,"unused second body stays unparsed");
 assert_eq!(db.db().stats(BODY_SYNTAX).computed,0,"one-shot reuses direct provider permit; it does not attach/query Kind4");
 let alias=static_literal(&owner).clone();let charged=db.body_charge.load(Ordering::Acquire);assert!(charged>dm_syntax::SettingChargeCounter::root_allocation_bytes(),"same actual QueryDb counter owns canonical body storage");
 drop(warm);drop(owner);drop(arena);assert_eq!(db.body_charge.load(Ordering::Acquire),charged,"literal alias keeps its original physical-free credit");
 drop(alias);assert_eq!(db.body_charge.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
}
#[test]
fn actual_one_shot_zero_set_body_quota_refuses_atomically_then_same_source_retries(){
 let db=Arc::new(QueryDb::default());let front=one_shot_frontend("/proc/p()\n    var/static/value = \"value [1 + 2]\"\n    return value\n",&db);
 let body=&front.bodies[0];let arena=dm_tree::frontend::BodyArena::new_typed(&front,|_|true);
 let healthy=||Ok(());let permit=dm_syntax::SettingAdmission::new(&db.body_charge,BUDGET,&healthy);
 let held=permit.reserve(BUDGET - dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
 let failure=arena.with_parsed_checked(body,|_|panic!("failed preparation must not expose a body")).unwrap_err();
 assert!(matches!(failure,BodySyntaxFailure::Operational(ref actual)if actual.kind()==io::ErrorKind::OutOfMemory));
 let mut retained=0;arena.visit_retained(|_,_|retained+=1);assert_eq!(retained,0,"actual quota refusal does not cache syntax/error");
 assert_eq!(db.body_charge.load(Ordering::Acquire),BUDGET);drop(held);drop(permit);assert_eq!(db.body_charge.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
 let owner=arena.with_parsed_checked(body,|parsed|parsed.shared_statement_body().unwrap()).unwrap();
 assert!(owner.has_native_literal_syntax());assert_eq!(static_literal(&owner).retained_parts().unwrap().unwrap().unwrap().expressions.len(),1);
 assert_eq!(db.db().stats(BODY_SYNTAX).computed,0);drop(owner);drop(arena);assert_eq!(db.body_charge.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
}
#[test]
fn unattached_compatibility_zero_set_body_keeps_owned_lazy_literal_behavior(){
 let provider=Original(dm_preprocess::AcquiredSource::from_original_bytes(b"/proc/p()\n    var/static/value = \"value [1 + 2]\"\n    return value\n".to_vec(),()));
 let front=dm_tree::frontend::build(Path::new("compatibility-one-shot-literal.dme"),&provider,&Default::default(),1).unwrap();
 let arena=dm_tree::frontend::BodyArena::new_typed(&front,|_|true);
 arena.with_parsed_checked(&front.bodies[0],|parsed|{
  let body=parsed.statement_body().unwrap();assert!(!body.has_native_literal_syntax());assert!(static_literal(body).retained_parts().is_none());
 }).unwrap();
}

#[test]
fn active_context_direct_body_loan_records_dynamic_edges_and_survives_eviction_without_second_get(){
 const CURRENT:Kind=Kind(241);const PARENT:Kind=Kind(242);
 let db=Arc::new(QueryDb::default());db.db.define_input(CURRENT,"test-original-body-source");
 let first_front=frontend("/proc/p()\n    return \"first [1]\"\n",&db);let first=first_front.body_archive().unwrap();
 let first_input=Arc::clone(&first.syntax_inputs().unwrap()[0]);let first_key=Key::new(BODY_SYNTAX,first_input.key().into());let source_key=Key::new(CURRENT,1);let parent_key=Key::new(PARENT,1);
 db.db.set_input(source_key,Arc::clone(&first),first_input.key().into());
 let weak=Arc::downgrade(&db);
 db.db.define(PARENT,"test-observed-original-body",move|ctx,_|{
  let owner=ctx.input::<Arc<dm_tree::frontend::BodyArchive>>(source_key)?;
  let q=weak.upgrade().ok_or(dm_query::QueryError::Missing(parent_key))?;
  let body=owner.parse_checked_using(0,|input|{
   let syntax=obtain(ctx,input)?;
   // Exact returned owner remains live while the actual Db value is removed.
   // A host re-get here would compute another body and fail the count below.
   q.db.evict_values(&[BODY_SYNTAX]);Ok(syntax)
  }).map_err(|error|match error{BodySyntaxFailure::Operational(actual)=>dm_query::QueryError::operational(parent_key,actual),BodySyntaxFailure::Syntax(_)=>dm_query::QueryError::Missing(parent_key)})?;
  let text=literal(&body).as_str().to_owned();let hash=dm_query::hash_bytes(text.as_bytes());Ok(dm_query::Outcome::new(text,hash,1024))
 });
 let first_text=db.db.get::<String>(parent_key,Arc::new(())).unwrap();assert_eq!(first_text.as_str(),"\"first [1]\"");assert_eq!(db.db.stats(BODY_SYNTAX).computed,1);assert!(db.db.dependants(&[first_key]).contains(&parent_key),"actual Kind4 dynamic edge, not merely same Db identity");
 let warm=db.db.get::<String>(parent_key,Arc::new(())).unwrap();assert!(Arc::ptr_eq(&first_text,&warm));assert_eq!(db.db.stats(PARENT).computed,1);assert_eq!(db.db.stats(BODY_SYNTAX).computed,1,"warm parent must not demand an evicted body again");
 let next_front=frontend("/proc/p()\n    return \"second [1]\"\n",&db);let next=next_front.body_archive().unwrap();let next_input=&next.syntax_inputs().unwrap()[0];let next_key=Key::new(BODY_SYNTAX,next_input.key().into());assert_ne!(next_key,first_key);
 db.db.set_input(source_key,Arc::clone(&next),next_input.key().into());
 let changed=db.db.get::<String>(parent_key,Arc::new(())).unwrap();assert_eq!(changed.as_str(),"\"second [1]\"");assert_eq!(db.db.stats(PARENT).computed,2);assert_eq!(db.db.stats(BODY_SYNTAX).computed,2);assert!(db.db.dependants(&[next_key]).contains(&parent_key));assert!(!db.db.dependants(&[first_key]).contains(&parent_key),"source rebind replaces actual syntax dependency");
}
#[test]
fn direct_body_loan_rejects_real_foreign_returned_arc_and_preserves_actual_io_then_same_input_retry(){
 let db=Arc::new(QueryDb::default());let first=frontend("/proc/p()\n    return \"first [1]\"\n",&db).body_archive().unwrap();let other=frontend("/proc/p()\n    return \"other [2]\"\n",&db).body_archive().unwrap();
 let foreign=db.syntax_checked(&other.syntax_inputs().unwrap()[0]).unwrap();let error=first.parse_checked_using(0,|_|Ok(Arc::clone(&foreign))).err().expect("different genuine original input must refuse");assert!(matches!(error,BodySyntaxFailure::Syntax(ref d)if d.message.contains("foreign parser issuance")));
 let before=db.db.stats(BODY_SYNTAX).computed;let error=first.parse_checked_using(0,|_|Err(BodySyntaxFailure::Operational(io::Error::from_raw_os_error(1450)))).err().expect("actual operational refusal");assert!(matches!(error,BodySyntaxFailure::Operational(ref actual)if actual.raw_os_error()==Some(1450)));assert_eq!(db.db.stats(BODY_SYNTAX).computed,before);
 let same=Arc::clone(&first.syntax_inputs().unwrap()[0]);let body=first.parse_checked_using(0,|input|{assert!(Arc::ptr_eq(input,&same));db.syntax_checked(input)}).unwrap();assert_eq!(literal(&body).as_str(),"\"first [1]\"");assert_eq!(db.db.stats(BODY_SYNTAX).computed,before+1);
 let again=first.parse_checked_using(0,|input|db.syntax_checked(input)).unwrap();assert!(std::ptr::eq(body.statement_body(),again.statement_body()));assert_eq!(db.db.stats(BODY_SYNTAX).computed,before+1);
}
#[test]
fn observed_body_api_has_no_standalone_fallback_or_early_parse(){
 let db=Arc::new(QueryDb::default());let provider=Original(dm_preprocess::AcquiredSource::from_original_bytes(b"/proc/p()\n    return 1\n".to_vec(),()));let front=dm_tree::frontend::build(Path::new("no-observed-host.dme"),&provider,&Default::default(),1).unwrap();let archive=front.body_archive().unwrap();
 let called=std::cell::Cell::new(false);let error=archive.parse_checked_using(0,|_|{called.set(true);panic!("no original query input exists")}).err().expect("mandatory native body query owner");assert!(matches!(error,BodySyntaxFailure::Operational(ref actual)if actual.kind()==io::ErrorKind::NotConnected));assert!(!called.get());assert_eq!(db.db.stats(BODY_SYNTAX).computed,0);
}

#[test]
fn direct_body_loan_registers_weak_input_for_actual_revision_pruning(){
 let db=Arc::new(QueryDb::default());let front=frontend("/proc/p()\n    return \"kept [1]\"\n",&db);let archive=front.body_archive().unwrap();let input=Arc::clone(&archive.syntax_inputs().unwrap()[0]);let key=Key::new(BODY_SYNTAX,input.key().into());let weak=Arc::downgrade(&input);
 let body=archive.parse_checked_using(0,|input|db.syntax_checked(input)).unwrap();assert!(db.body_inputs.lock().unwrap().contains_key(&key));assert!(db.db.value_bytes_at(key)>0);
 drop(body);drop(input);drop(archive);drop(front);assert_eq!(weak.strong_count(),0,"bookkeeping must not retain the original body input");
 db.begin_revision();assert!(!db.body_inputs.lock().unwrap().contains_key(&key));assert_eq!(db.db.value_bytes_at(key),0,"existing revision pruning removes actual expired body node");
}
#[test]
fn actual_host_prepare_error_precedes_context_callback_and_keeps_original_cause(){
 #[derive(Debug)]struct StopPrepare(Arc<QueryDb>);
 impl BodySyntaxQueries for StopPrepare{
  fn syntax(&self,input:&Arc<BodySyntaxInput>)->Result<Arc<BodySyntax>,Diagnostic>{self.0.syntax(input)}
  fn syntax_checked(&self,input:&Arc<BodySyntaxInput>)->Result<Arc<BodySyntax>,BodySyntaxFailure>{self.0.syntax_checked(input)}
  fn prepare_checked_input(&self,_:&Arc<BodySyntaxInput>)->Result<(),BodySyntaxFailure>{Err(BodySyntaxFailure::Operational(io::Error::from_raw_os_error(1450)))}
 }
 let db=Arc::new(QueryDb::default());let source=Original(dm_preprocess::AcquiredSource::from_original_bytes(b"/proc/p()\n    return 1\n".to_vec(),()));let front=dm_tree::frontend::build(Path::new("prepare-stop.dme"),&source,&Default::default(),1).unwrap().with_body_queries(Arc::new(StopPrepare(db.clone())));let archive=front.body_archive().unwrap();let called=std::cell::Cell::new(false);
 let error=archive.parse_checked_using(0,|_|{called.set(true);panic!("prepare refusal must precede context get")}).err().unwrap();assert!(matches!(error,BodySyntaxFailure::Operational(ref actual)if actual.raw_os_error()==Some(1450)));assert!(!called.get());assert_eq!(db.db.stats(BODY_SYNTAX).computed,0);
}

#[test]
fn archive_owner_witness_reuses_actual_tuple_across_fresh_policy_captures_and_refuses_foreign_text(){
 let db=Arc::new(QueryDb::default());let text="/proc/p()\n    return 1\n";let front=frontend(text,&db);
 let first=dm_analysis::policy_inputs::PolicyInputs::capture(&front,Vec::<dm_analysis::policy_inputs::HostCapture>::new()).unwrap();
 let second=dm_analysis::policy_inputs::PolicyInputs::capture(&front,Vec::<dm_analysis::policy_inputs::HostCapture>::new()).unwrap();
 assert!(!Arc::ptr_eq(first.archive(),second.archive()),"real capture constructs a new wrapper");let witness=first.archive().original_owner_witness();assert!(witness.matches(second.archive()),"original inner owner tuple is shared without source equality");
 let foreign=frontend(text,&db).body_archive().unwrap();assert!(!witness.matches(&foreign),"equal text is not original owner identity");assert_eq!(db.db.stats(BODY_SYNTAX).computed,0,"headers/capture/witness never demand bodies");
 let capacity=witness.fixed_retention_capacity().unwrap();assert!(capacity>0);let mut counted=0;witness.visit_storage(|_,_,_,n|counted+=n);assert_eq!(counted,capacity);
 drop(first);drop(second);drop(front);assert!(!witness.matches(&foreign));let mut dead=0;witness.visit_storage(|_,_,live,_|if live==0{dead+=1});assert!(dead>0,"at least an actual original fixed owner is now weak-only");
 for _ in 0..8{let fresh=frontend(text,&db).body_archive().unwrap();assert!(!witness.matches(&fresh),"reallocated wrappers/source owners cannot revive expired receipt");}
}
#[test]
fn archive_owner_witness_rejects_genuine_same_width_body_edit_despite_shared_semantic_tree(){
 fn retained(source:&str,state:&mut dm_tree::frontend::RetainedSemanticTree,db:&Arc<QueryDb>)->dm_tree::frontend::ColdFrontend{
  let provider=Original(dm_preprocess::AcquiredSource::from_original_bytes(source.as_bytes().to_vec(),()));let executor=dm_exec::BuildExecutor::new(1).unwrap();
  dm_tree::frontend::build_with_executor_and_semantic_state(Path::new("archive-owner-retained.dme"),&provider,&Default::default(),dm_tree::frontend::FrontendConfig{workers:1,engine:None,observer:None},None,&executor,Some(state)).unwrap().with_body_queries(db.clone())
 }
 let db=Arc::new(QueryDb::default());let mut state=dm_tree::frontend::RetainedSemanticTree::default();let first=retained("/proc/p()\n    return 1\n/proc/q()\n    return 2\n",&mut state,&db);let archive=first.body_archive().unwrap();let witness=archive.original_owner_witness();
 let current=retained("/proc/p()\n    return 9\n/proc/q()\n    return 2\n",&mut state,&db);assert!(Arc::ptr_eq(&first.snapshot.tree,&current.snapshot.tree),"actual body-only semantic reuse control");let fresh=current.body_archive().unwrap();assert_eq!(archive.occurrences()[0].expanded_span,fresh.occurrences()[0].expanded_span);assert!(!witness.matches(&fresh),"same model/span does not authenticate another actual body/source epoch");assert_eq!(db.db.stats(BODY_SYNTAX).computed,0);
}

#[path="../../../dm-analysis/examples/support/reference_hierarchy.rs"]mod archive_owner_reference_hierarchy;
#[test]
fn archive_owner_witness_refuses_a_different_actual_published_builtin_profile(){
 let db=Arc::new(QueryDb::default());let text="/proc/p()\n    return 1\n";let plain=frontend(text,&db);let old=plain.body_archive().unwrap();let witness=old.original_owner_witness();
 let provider=Original(dm_preprocess::AcquiredSource::from_original_bytes(text.as_bytes().to_vec(),()));let seed=archive_owner_reference_hierarchy::seed();let executor=dm_exec::BuildExecutor::new(1).unwrap();
 let certified=dm_tree::frontend::build_with_executor_and_semantic_state_for_policy(Path::new("archive-owner-profile.dme"),&provider,&Default::default(),dm_tree::frontend::FrontendConfig{workers:1,engine:Some(&seed),observer:None},None,&executor,None,true).unwrap().with_body_queries(db.clone());let current=certified.body_archive().unwrap();
 assert!(current.tree().checker_builtin_profile().is_some());assert_ne!(old.tree().checker_builtin_profile(),current.tree().checker_builtin_profile(),"actual profile control, not a manufactured witness");assert!(!witness.matches(&current));assert_eq!(db.db.stats(BODY_SYNTAX).computed,0);
}

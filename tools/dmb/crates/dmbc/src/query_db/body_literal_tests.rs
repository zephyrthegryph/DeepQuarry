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
 assert_eq!(db.body_charge.load(Ordering::Acquire),0);
 let archive=front.body_archive().unwrap();archive.callable_header_policy_origin(body.member).unwrap();
 let raw=front.files.iter().find(|f|f.captured).expect("original captured compiler source");assert!(raw.text.contains("var/static/value"));
 assert_eq!(db.db().stats(BODY_SYNTAX).computed,0,"raw/header handling never demands a body query");
 assert_eq!(db.body_charge.load(Ordering::Acquire),0,"header handling does not prepare ordinary literal children");
 let arena=dm_tree::frontend::BodyArena::new_typed(&front,|_|true);
 let owner=arena.with_parsed_checked(body,|parsed|parsed.shared_statement_body().expect("actual checked one-shot statement owner")).unwrap();
 assert!(owner.has_native_literal_syntax());
 let child=static_literal(&owner).retained_parts().unwrap().unwrap().unwrap().expressions.as_ptr();
 let warm=arena.with_parsed_checked(body,|parsed|parsed.shared_statement_body().unwrap()).unwrap();
 assert!(Arc::ptr_eq(&owner,&warm));assert_eq!(static_literal(&warm).parts().unwrap().unwrap().expressions.as_ptr(),child);
 let mut retained=0;arena.visit_retained(|_,_|retained+=1);assert_eq!(retained,1,"unused second body stays unparsed");
 assert_eq!(db.db().stats(BODY_SYNTAX).computed,0,"one-shot reuses direct provider permit; it does not attach/query Kind4");
 let alias=static_literal(&owner).clone();let charged=db.body_charge.load(Ordering::Acquire);assert!(charged>0,"same actual QueryDb counter owns canonical body storage");
 drop(warm);drop(owner);drop(arena);assert_eq!(db.body_charge.load(Ordering::Acquire),charged,"literal alias keeps its original physical-free credit");
 drop(alias);assert_eq!(db.body_charge.load(Ordering::Acquire),0);
}
#[test]
fn actual_one_shot_zero_set_body_quota_refuses_atomically_then_same_source_retries(){
 let db=Arc::new(QueryDb::default());let front=one_shot_frontend("/proc/p()\n    var/static/value = \"value [1 + 2]\"\n    return value\n",&db);
 let body=&front.bodies[0];let arena=dm_tree::frontend::BodyArena::new_typed(&front,|_|true);
 let healthy=||Ok(());let permit=dm_syntax::SettingAdmission::new(&db.body_charge,BUDGET,&healthy);
 let held=permit.reserve(BUDGET).unwrap();
 let failure=arena.with_parsed_checked(body,|_|panic!("failed preparation must not expose a body")).unwrap_err();
 assert!(matches!(failure,BodySyntaxFailure::Operational(ref actual)if actual.kind()==io::ErrorKind::OutOfMemory));
 let mut retained=0;arena.visit_retained(|_,_|retained+=1);assert_eq!(retained,0,"actual quota refusal does not cache syntax/error");
 assert_eq!(db.body_charge.load(Ordering::Acquire),BUDGET);drop(held);drop(permit);assert_eq!(db.body_charge.load(Ordering::Acquire),0);
 let owner=arena.with_parsed_checked(body,|parsed|parsed.shared_statement_body().unwrap()).unwrap();
 assert!(owner.has_native_literal_syntax());assert_eq!(static_literal(&owner).retained_parts().unwrap().unwrap().unwrap().expressions.len(),1);
 assert_eq!(db.db().stats(BODY_SYNTAX).computed,0);drop(owner);drop(arena);assert_eq!(db.body_charge.load(Ordering::Acquire),0);
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

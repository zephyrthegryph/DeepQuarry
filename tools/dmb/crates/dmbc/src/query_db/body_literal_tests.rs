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

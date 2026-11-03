//! Same real native primary/model pipeline and canonical Kind4 across a
//! receiver-field-only model change. No extra parse/model/hash-only CodeID.
use super::*;
fn canonical(db:&crate::query_db::QueryDb,archive:&dm_tree::frontend::BodyArchive){dm_tree::frontend::SettingExpressionQueries::with_declaration_admission(db,&mut|a|archive.with_current_body_checked(0,a,|_|Ok(()))).unwrap();}use super::analysis_context_tests::{fixture,run,current};use crate::policy_request::{AnalysisContext,WorkspaceAuxiliaryQuestion as Q};
#[test]fn actual_original_primary_field_only_edit_changes_model_and_preserves_body_code_and_canonical_parse(){
 let source="/datum/receiver
/proc/probe(datum/receiver/argument)
    return argument.field
";let(mut host,mut request,root)=fixture(source);let intent=request.policy_inputs.as_mut().unwrap();intent.analysis_context=Some(AnalysisContext::OriginalAnalyze0290);intent.workspace_auxiliary=vec![Q::StoredRefs];intent.workspace.as_mut().unwrap().recursive_roots=vec![root.join("code")];let db=Arc::clone(host.query_db());run(&mut host,&request);
 let(tree,code)=current(&host,|snapshot|{let archive=snapshot.body_archive.as_ref().unwrap();assert_eq!(archive.len(),1);canonical(&db,archive);let input=&archive.syntax_inputs().unwrap()[0];(Arc::clone(&snapshot.tree),Arc::clone(input.original_code_owner().unwrap()))});let computed=db.db().stats(dm_query::Kind(4)).computed;
 std::fs::write(root.join("code/probe.dm"),"/datum/receiver
    var/field
/proc/probe(datum/receiver/argument)
    return argument.field
").unwrap();run(&mut host,&request);current(&host,|snapshot|{assert!(!Arc::ptr_eq(&tree,&snapshot.tree));let archive=snapshot.body_archive.as_ref().unwrap();let input=&archive.syntax_inputs().unwrap()[0];assert!(Arc::ptr_eq(&code,input.original_code_owner().unwrap()),"actual new header/model owner retains only exact same code identity");canonical(&db,archive);});assert_eq!(db.db().stats(dm_query::Kind(4)).computed,computed);assert!(Arc::ptr_eq(&db,host.query_db()));
}

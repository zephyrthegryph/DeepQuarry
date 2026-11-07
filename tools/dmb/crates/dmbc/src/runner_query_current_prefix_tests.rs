//! Actual current canonical prefix guards, never a synthesized ArchivedBody.
use super::*;
use super::super::analysis_context_tests::{checker_fixture as fixture,run,current};
use dm_tree::frontend::{BodySyntaxFailure,SettingExpressionQueries};
const SOURCE:&str="/datum/receiver\n/proc/probe(datum/receiver/argument)\n    return argument.field\n";
#[test]fn current_initial_prefix_lends_same_native_product_and_current_utf8_source_after_shift(){
 let(mut host,request,root)=fixture(SOURCE);let queries=host.query_db().clone();run(&mut host,&request);
 let view=|host:&crate::runner_host::BuildHost|current(host,|snapshot|{let archive=snapshot.body_archive.as_ref().unwrap();let identity=archive.callables().identity(0).unwrap();let mut result=None;SettingExpressionQueries::with_declaration_admission(queries.as_ref(),&mut|admission|archive.with_current_body_checked(0,admission,|body|body.with_initial_setting_prefix(identity,admission,|prefix|{assert!(prefix.belongs_to(archive));assert_eq!(prefix.identity(),identity);assert!(prefix.settings().is_empty());assert_eq!(prefix.statement_body().parsed().statements.len(),1,"prefix is a view, not an empty replacement body");let source=prefix.source_body();assert!(std::ptr::eq(source.tree(),archive.tree()));assert!(std::ptr::eq(source.occurrence(),body.occurrence()));let canonical=prefix.statement_body().parsed().statements[0].header_span;let current=source.source_point(canonical).unwrap();assert_eq!(source.canonical_point(current).unwrap(),canonical);assert_eq!(archive.expanded_source().get(current.range()),Some("return argument.field"));let tokens=source.original_body_tokens().unwrap();let mut actual_dot=None;for(_,point,text)in tokens.tokens(current).unwrap(){if text=="."{assert_eq!(source.source_point(source.canonical_point(point).unwrap()).unwrap(),point);actual_dot=Some(point.start);}}assert_eq!(actual_dot,archive.expanded_source().find(".field"),"follow points come from real current primary tokens, including UTF8 shifts");result=Some((prefix.statement_body()as*const _ as usize,current.start));}))).unwrap();result.unwrap()});
 let first=view(&host);let parses=queries.db().stats(dm_query::Kind(4)).computed;std::fs::write(root.join("code/probe.dm"),format!("// α actual new source\n{SOURCE}// trailing source change\n")).unwrap();run(&mut host,&request);let shifted=view(&host);assert_eq!(first.0,shifted.0,"same canonical parsed owner, not shifted/cloned AST");assert_ne!(first.1,shifted.1);assert_eq!(queries.db().stats(dm_query::Kind(4)).computed,parses);
}
#[test]fn current_initial_prefix_foreign_identity_and_source_io_remain_real_failures(){
 let(mut host,request,_)=fixture(SOURCE);run(&mut host,&request);let queries=host.query_db().clone();current(&host,|snapshot|{let archive=snapshot.body_archive.as_ref().unwrap();let identity=archive.callables().identity(0).unwrap();SettingExpressionQueries::with_declaration_admission(queries.as_ref(),&mut|admission|archive.with_current_body_checked(0,admission,|body|{let mut called=false;let mut foreign=identity;foreign.owner=dm_ir::SymbolId::of("/datum/foreign");let actual=body.with_initial_setting_prefix(foreign,admission,|_|called=true).unwrap_err();assert!(matches!(actual,BodySyntaxFailure::Operational(actual)if actual.kind()==std::io::ErrorKind::InvalidData));assert!(!called);body.with_initial_setting_prefix(identity,admission,|prefix|{let actual=prefix.source_body().with_source_admission(|_|Err::<(),_>(BodySyntaxFailure::Operational(std::io::Error::from_raw_os_error(1450)))).unwrap_err();assert!(matches!(actual,BodySyntaxFailure::Operational(actual)if actual.raw_os_error()==Some(1450)));})?;Ok(())})).unwrap();});
}
#[test]fn current_initial_prefix_genuine_old_skipped_and_unissued_grammar_are_not_conflated(){
 let(mut host,request,root)=fixture("/proc/probe()\n    return 1 +\n");run(&mut host,&request);let queries=host.query_db().clone();current(&host,|snapshot|{let archive=snapshot.body_archive.as_ref().unwrap();let identity=archive.callables().identity(0).unwrap();SettingExpressionQueries::with_declaration_admission(queries.as_ref(),&mut|admission|archive.with_current_body_checked(0,admission,|body|body.with_initial_setting_prefix(identity,admission,|prefix|{assert!(prefix.settings().is_empty());assert!(prefix.first_non_setting().is_none(),"genuine old code None has no gather-settings body");assert_eq!(prefix.statement_body().parsed().statements.len(),1,"actual recovering native body remains, not fabricated empty syntax");}))).unwrap();});
 std::fs::write(root.join("code/probe.dm"),"/proc/probe(value)\n    return value ? 1 : 2\n").unwrap();run(&mut host,&request);current(&host,|snapshot|{let archive=snapshot.body_archive.as_ref().unwrap();let identity=archive.callables().identity(0).unwrap();SettingExpressionQueries::with_declaration_admission(queries.as_ref(),&mut|admission|archive.with_current_body_checked(0,admission,|body|{let mut calls=0;let actual=body.with_initial_setting_prefix(identity,admission,|_|calls+=1).unwrap_err();assert!(matches!(actual,BodySyntaxFailure::Operational(actual)if actual.kind()==std::io::ErrorKind::Unsupported));assert_eq!(calls,0);Ok(())})).unwrap();});
}


#[derive(Default)]struct SettingPresentationWork{used:usize,fail:bool}
impl dm_analysis::checker_effects::EffectReportWork for SettingPresentationWork{
 type Mark=usize;
 fn reserve(&mut self,bytes:usize)->std::io::Result<()>{if self.fail{return Err(std::io::Error::from_raw_os_error(1450))}self.used=self.used.checked_add(bytes).ok_or(std::io::ErrorKind::OutOfMemory)?;Ok(())}
 fn mark(&mut self)->std::io::Result<usize>{self.reserve(0)?;Ok(self.used)}
 fn reconcile(&mut self,mark:usize,retained:usize)->std::io::Result<()>{self.used=mark.checked_add(retained).ok_or(std::io::ErrorKind::OutOfMemory)?;Ok(())}
}
const INVALID_SETTING_SOURCE:&str="/proc/probe()\n    set SpacemanDMM_should_not_sleep = 2\n    return null\n";
#[test]fn current_setting_recipes_preserve_one_canonical_body_but_render_real_current_debug_points(){
 let(mut host,request,root)=fixture(INVALID_SETTING_SOURCE);let queries=host.query_db().clone();run(&mut host,&request);
 let mut work=SettingPresentationWork::default();let recipes=current(&host,|snapshot|{let archive=snapshot.body_archive.as_ref().unwrap();let mut result=None;SettingExpressionQueries::with_declaration_admission(queries.as_ref(),&mut|admission|archive.with_current_body_checked(0,admission,|body|{result=Some(dm_analysis::checks_directive_binding::current_invalid_setting_recipes(&body,archive.tree(),admission,&mut work,&||Ok(())).unwrap());Ok(())})).unwrap();result.unwrap()});
 assert_eq!(recipes.len(),1);assert!(!recipes.is_skipped_original());let parses=queries.db().stats(dm_query::Kind(4)).computed;
 let mut rendered=Vec::new();let mut expected=Vec::new();
 for (source,expected_line) in [(INVALID_SETTING_SOURCE.to_owned(),2u32),(format!("// α actual source shift\n{INVALID_SETTING_SOURCE}"),3u32)]{
  std::fs::write(root.join("code/probe.dm"),source).unwrap();run(&mut host,&request);
  current(&host,|snapshot|{let archive=snapshot.body_archive.as_ref().unwrap();SettingExpressionQueries::with_declaration_admission(queries.as_ref(),&mut|admission|archive.with_current_body_checked(0,admission,|body|{
   let syntax=body.syntax().canonical_statement_storage();let setting=syntax.parsed().statements[0].setting().unwrap();let projected=body.syntax().projection().span(setting.value.current_span()).unwrap();let registry=archive.source_mapping().original_checker_source_registry(admission).unwrap();let point=registry.location(projected.start).unwrap();assert_eq!(point.line,expected_line);let want=format!("invalid value for set Base {{ term: Spanned {{ location: Location {{ file: FileId({}), line: {}, column: {} }}, elem: Int(2) }}, follow: [] }}",point.file,point.line,point.byte_column);
   let before=work.used;recipes.visit_current(&body,admission,&mut work,&||Ok(()),|row|{assert_eq!(row.message,want);assert_eq!(row.span,body.syntax().projection().span(syntax.parsed().statements[0].header_span).unwrap());assert!(row.notes.is_empty());rendered.push(row.message.clone());Ok(())}).unwrap();assert_eq!(work.used,before,"presentation rows released before report credit is reconciled");expected.push(want);Ok(())})).unwrap();});
 }
 assert_eq!(rendered,expected);assert_ne!(rendered[0],rendered[1],"the source-neutral recipe must not cache old Debug locations inside message text");assert_eq!(queries.db().stats(dm_query::Kind(4)).computed,parses,"source-only line shift rebinds the SAME actual canonical BODY");
}
#[test]fn current_setting_recipes_do_not_hide_actual_report_io_or_rebind_foreign_code(){
 let(mut host,request,root)=fixture(INVALID_SETTING_SOURCE);let queries=host.query_db().clone();run(&mut host,&request);let mut work=SettingPresentationWork::default();let recipes=current(&host,|snapshot|{let archive=snapshot.body_archive.as_ref().unwrap();let mut result=None;SettingExpressionQueries::with_declaration_admission(queries.as_ref(),&mut|admission|archive.with_current_body_checked(0,admission,|body|{result=Some(dm_analysis::checks_directive_binding::current_invalid_setting_recipes(&body,archive.tree(),admission,&mut work,&||Ok(())).unwrap());Ok(())})).unwrap();result.unwrap()});
 current(&host,|snapshot|{let archive=snapshot.body_archive.as_ref().unwrap();SettingExpressionQueries::with_declaration_admission(queries.as_ref(),&mut|admission|archive.with_current_body_checked(0,admission,|body|{let before=work.used;let mut emitted=0;let actual=recipes.visit_current(&body,admission,&mut work,&||Ok(()),|_|{emitted+=1;Err(std::io::Error::from_raw_os_error(1450))}).unwrap_err();assert!(matches!(actual,dm_analysis::policy_body_demand::PolicyFailure::Operational(actual)if actual.raw_os_error()==Some(1450)));assert_eq!(emitted,1);assert_eq!(work.used,before);work.fail=true;let actual=dm_analysis::checks_directive_binding::current_invalid_setting_recipes(&body,archive.tree(),admission,&mut work,&||Ok(())).unwrap_err();assert!(matches!(actual,dm_analysis::policy_body_demand::PolicyFailure::Operational(actual)if actual.raw_os_error()==Some(1450)));work.fail=false;Ok(())})).unwrap();});
 std::fs::write(root.join("code/probe.dm"),INVALID_SETTING_SOURCE.replace(" = 2"," = 3")).unwrap();run(&mut host,&request);current(&host,|snapshot|{let archive=snapshot.body_archive.as_ref().unwrap();SettingExpressionQueries::with_declaration_admission(queries.as_ref(),&mut|admission|archive.with_current_body_checked(0,admission,|body|{let mut emitted=0;let actual=recipes.visit_current(&body,admission,&mut work,&||Ok(()),|_|{emitted+=1;Ok(())}).unwrap_err();assert!(matches!(actual,dm_analysis::policy_body_demand::PolicyFailure::Unsupported(_)));assert_eq!(emitted,0);Ok(())})).unwrap();});
}


const COMPLETE_CURRENT_PREFIX:&str="/proc/probe(x)\n    set SpacemanDMM_should_not_sleep = 0\n    set SpacemanDMM_should_not_sleep = 1\n    set SpacemanDMM_should_not_sleep = 1\n    set SpacemanDMM_made_up = 1\n    set SpacemanDMM_return_type = 1 + 2\n    set SpacemanDMM_return_type = missing\n    set SpacemanDMM_return_type = x.other\n    set SpacemanDMM_return_type = /datum/missing\n    return null\n";
fn observe_complete_current_prefix(host:&crate::runner_host::BuildHost,root:&std::path::Path,ordinal:usize,case:&str)->Vec<(String,usize,usize,String,Vec<String>)>{current(host,|snapshot|{let archive=snapshot.body_archive.as_ref().unwrap();let mut rows=Vec::new();snapshot.visit_current_selected_diagnostics(ordinal,&root.join("code/probe.dm"),Some(&root.join("SpacemanDMM.toml")),&snapshot.tree,|row|{if let crate::query_db::CurrentSelectedDiagnostic::Prelude(row)=row{let point=archive.source_note_point(row.span.start).unwrap();assert_eq!(std::fs::canonicalize(point.path.as_path()).unwrap(),std::fs::canonicalize(root.join("code/probe.dm")).unwrap(),"every delivered row must originate from the exact physical fixture, not a basename alias");rows.push((format!("{:?}",row.severity),point.line,point.byte_column,row.message.clone(),row.notes.iter().map(|note|note.legacy_text()).collect()));}Ok(())}).unwrap();println!("CURRENT_COMPLETE_PREFIX={rows:?}");use sha2::Digest;let source=std::fs::read(root.join("code/probe.dm")).unwrap();let source_sha256=format!("{:x}",sha2::Sha256::digest(&source));let observed=rows.iter().map(|row|serde_json::json!({"level":row.0.to_lowercase(),"line":row.1,"column":row.2,"message":row.3,"notes":row.4})).collect::<Vec<_>>();println!("CURRENT_COMPLETE_PREFIX_NATIVE {}",serde_json::json!({"case":case,"source_sha256":source_sha256,"rows":observed}));rows})}
#[test]fn current_complete_initial_prefix_preserves_all_ordered_judges_and_current_duplicate_notes(){
 let(mut host,mut request,root)=fixture(COMPLETE_CURRENT_PREFIX);std::fs::write(root.join("SpacemanDMM.toml"),b"").unwrap();request.policy_inputs.as_mut().unwrap().files.push(crate::policy_request::PolicyInputFile{path:root.join("code/probe.dm"),role:crate::policy_request::PolicyInputRole::DmSource,required:true});let queries=host.query_db().clone();run(&mut host,&request);let first=observe_complete_current_prefix(&host,&root,0,"complete");assert_eq!(first.len(),7);assert_eq!(first.iter().map(|row|row.1).collect::<Vec<_>>(),[2,4,5,6,7,8,9]);assert_eq!(first.iter().map(|row|row.2).collect::<Vec<_>>(),[5,5,5,5,35,36,5]);assert_eq!(first.iter().map(|row|row.0.as_str()).collect::<Vec<_>>(),["Warning","Warning","Warning","Error","Error","Error","Error"]);assert_eq!(first[0].3,"/proc/probe sets SpacemanDMM_should_not_sleep false, but it cannot be disabled.");assert_eq!(first[1].3,"/proc/probe sets SpacemanDMM_should_not_sleep twice");assert_eq!(first[1].4,["3:5: first definition here"]);assert_eq!(first[2].3,"unknown linter setting \"SpacemanDMM_made_up\"");assert_eq!(first[3].3,"type expr: bad expression node");assert_eq!(first[4].3,"type expr: no such parameter \"missing\"");assert_eq!(first[5].3,"type expr: bad follow node Field(Dot, \"other\")");assert_eq!(first[6].3,"undefined type: /datum/missing");let syntax=queries.db().stats(dm_query::Kind(4)).computed;let semantic=queries.db().stats(dm_query::Kind(28)).computed;
 std::fs::write(root.join("code/probe.dm"),format!("// α source-only shift\n{COMPLETE_CURRENT_PREFIX}")).unwrap();run(&mut host,&request);let shifted=observe_complete_current_prefix(&host,&root,0,"utf8_shift");assert_eq!(shifted.len(),7);assert_eq!(shifted[1].4,["4:5: first definition here"]);assert_eq!(shifted.iter().map(|row|row.1).collect::<Vec<_>>(),[3,5,6,7,8,9,10]);assert_eq!(queries.db().stats(dm_query::Kind(4)).computed,syntax);assert_eq!(queries.db().stats(dm_query::Kind(28)).computed,semantic,"complete prelude presentation never recompiles/evaluates on source-only rebinding");
 // The previously missing static type is an actual compile dependency, including
 // its rejected/empty binding. Adding it retracts the real old error.
 std::fs::write(root.join("code/probe.dm"),format!("/datum/missing\n{COMPLETE_CURRENT_PREFIX}")).unwrap();run(&mut host,&request);let present=observe_complete_current_prefix(&host,&root,0,"added_type");assert_eq!(present.len(),6);assert!(!present.iter().any(|row|row.3=="undefined type: /datum/missing"));assert_eq!(queries.db().stats(dm_query::Kind(4)).computed,syntax);assert_eq!(queries.db().stats(dm_query::Kind(28)).computed,semantic+1);
}
#[test]fn current_complete_prefix_retains_definition_gate_and_final_header_without_settings(){
 let gate="/datum/definition_gate/proc/probe()\n    set SpacemanDMM_can_be_redefined = TRUE\n    return 0\n/datum/definition_gate/probe()\n    set SpacemanDMM_private_proc = 2\n    set SpacemanDMM_should_be_pure = FALSE\n    return 0\n";
 let(mut host,request,root)=fixture(gate);std::fs::write(root.join("SpacemanDMM.toml"),b"").unwrap();run(&mut host,&request);let rows=observe_complete_current_prefix(&host,&root,1,"definition_gate");assert_eq!(rows.len(),2);assert_eq!(rows[0].3,"Can't define procs SpacemanDMM_private_proc outside their initial definition");assert_eq!(rows[1].3,"Can't define procs SpacemanDMM_should_be_pure outside their initial definition");
 std::fs::write(root.join("code/probe.dm"),"/proc/final/probe()\n    return 0\n").unwrap();run(&mut host,&request);let rows=observe_complete_current_prefix(&host,&root,0,"global_final");assert_eq!(rows.len(),1);assert_eq!(rows[0].1,1);assert_eq!(rows[0].3,"/proc/probe sets SpacemanDMM_should_not_override, which cannot be set on global procs");
}

#[test]
fn current_original_switch_cursor_reissues_reader_eof_after_unchanged_body_moves(){
 use dm_syntax::StatementKind;
 const PROBE:&str="/proc/probe()\n    switch(rand(1,2))\n        if(1 || 2)\n            return 0\n";
 let(mut host,request,root)=fixture(PROBE);
 let queries=host.query_db().clone();
 run(&mut host,&request);
 let get=|host:&crate::runner_host::BuildHost|current(host,|snapshot|{
  let archive=snapshot.body_archive.as_ref().unwrap();
  let mut observed=None;
  SettingExpressionQueries::with_declaration_admission(queries.as_ref(),&mut|a|archive.with_current_body_checked(0,a,|body|{
   let syntax=body.syntax().canonical_statement_storage();
   let StatementKind::Switch{cases,..}=&syntax.parsed().statements[0].kind else{panic!("actual original switch")};
   let cursor=body.with_original_body_source(a,|source|source.original_switch_case_cursor(cases[0].original_site))??.unwrap();
   observed=Some((cursor,std::sync::Arc::as_ptr(syntax) as usize));
   Ok(())
  })).unwrap();
  observed.unwrap()
 });
 let original_cursor=|host:&crate::runner_host::BuildHost|current(host,|snapshot|{
  let archive=snapshot.body_archive.as_ref().unwrap();
  let body=archive.parse_checked(0).unwrap();
  let StatementKind::Switch{cases,..}=&body.statement_body().parsed().statements[0].kind else{panic!("actual absolute switch")};
  cases[0].original_site.cursor.unwrap()
 });
 let first=get(&host);
 assert_eq!(first.0,original_cursor(&host),"current cursor equals genuine absolute parser issuance");
 let before=queries.db().stats(dm_query::Kind(4)).computed;
 std::fs::write(root.join("code/probe.dm"),format!("/datum/cursor_shift\n{PROBE}/proc/next()\n    return 1\n")).unwrap();
 run(&mut host,&request);
 let moved=get(&host);
 assert_eq!(first.1,moved.1,"unchanged syntax must reuse the actual native product");
 assert_eq!(queries.db().stats(dm_query::Kind(4)).computed,before);
 assert_ne!(first.0,moved.0,"current authored cursor must move with the live source");
 assert_eq!(moved.0,original_cursor(&host),"after source edit the same AST must use the fresh reader cursor");
}

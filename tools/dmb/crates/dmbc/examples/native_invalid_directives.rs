//! Whole-original fixture oracle through one real native QueryDb and issued archive.
//! Selected directive-family oracle; no gate/default change.
use std::{path::Path,sync::Arc,io::Write};
#[path="../../dm-analysis/examples/support/acquired_files.rs"]mod acquired_files;
#[derive(serde::Serialize)]struct Row<'a>{family:&'static str,severity:&'static str,file:&'a Path,line:u64,expanded_column:u64,message:&'a str,notes:[&'static str;0]}
fn body_error(error:dm_tree::frontend::BodySyntaxFailure)->Box<dyn std::error::Error>{match error{dm_tree::frontend::BodySyntaxFailure::Operational(actual)=>Box::new(actual),dm_tree::frontend::BodySyntaxFailure::Syntax(actual)=>actual.message.into()}}
fn main()->Result<(),Box<dyn std::error::Error>>{
 let project=std::env::args().nth(1).ok_or("expected .dme path")?;if std::env::args().nth(2).is_some_and(|family|!matches!(family.as_str(),"invalid_lint_directive_value"|"directive_at_definition")){return Err("unsupported oracle family".into())}
 let files=acquired_files::AcquiredFiles::default();let db=Arc::new(dmbc::query_db::QueryDb::default());let host:Arc<dyn dm_tree::frontend::SettingExpressionQueries>=db.clone();let executor=dm_exec::BuildExecutor::new(1)?;
 let diagnostic=dm_tree::frontend::build_for_checker_diagnostics_with_state_checked(Path::new(&project),&files,&Default::default(),dm_tree::frontend::FrontendConfig{workers:1,engine:None,observer:None},None,&executor,None,&host).map_err(|errors|format!("native diagnostic source failed: {errors:?}"))?.with_body_queries(db.clone())?;
 let family=std::env::args().nth(2).unwrap_or_else(||"invalid_lint_directive_value".into());let source=diagnostic.source_view()?;let mut output=std::io::stdout().lock();
 for(ordinal,_)in dm_analysis::checker_order::archived_bodies(source.archive())?{
  let body=source.archive().parse_checked(ordinal).map_err(body_error)?;
  let ordinary=if family=="directive_at_definition"{Some(dm_analysis::checks_directive_binding::archived_checked(&body,dm_analysis::checks_directive_binding::Family::AtDefinition,dm_analysis::checks::Severity::Warning,&mut||Ok(()))?)}else{None};
  let retained=if ordinary.is_none(){Some(dm_analysis::checks_directive_binding::archived_value_checked(&body,dm_analysis::checks::Severity::Warning,&mut||Ok(()))?)}else{None};
  for row in ordinary.iter().flat_map(|rows|rows.iter()).chain(retained.iter().flat_map(|rows|rows.iter())){let point=source.mapping().source_note_point(row.span.start)?;let observed=Row{family:row.family,severity:"warning",file:point.path.as_ref(),line:u64::try_from(point.line)?,expanded_column:u64::try_from(point.byte_column)?,message:&row.message,notes:[]};serde_json::to_writer(&mut output,&observed)?;output.write_all(b"\n")?;}
 }
 Ok(())
}

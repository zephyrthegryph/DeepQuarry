//! Pinned initial-prefix setting diagnostics over compiler-issued syntax.
//! SpacemanDMM0290db5c752fa292f9824521515b603a2afd11dc,
//! dreamchecker lib.rs602..617,789..852 (GPL-3.0). No RHS interpretation.
use crate::{checks::{BodyView,Diagnostic,Severity},policy_body_demand::PolicyFailure};
use dm_tree::frontend::{ArchivedBody,StatementBody};
pub(crate) const KNOWN:&[&str]=&["SpacemanDMM_should_not_override","SpacemanDMM_should_call_parent","SpacemanDMM_private_proc","SpacemanDMM_protected_proc","SpacemanDMM_should_not_sleep","SpacemanDMM_allowed_to_sleep","SpacemanDMM_should_be_pure","SpacemanDMM_can_be_redefined"];
const KNOWN_ORDINARY:&[&str]=&["name","desc","category","hidden","popup_menu","instant","invisibility","src","background","waitfor"];
#[derive(Clone,Copy)]enum Family{Linter,Ordinary}
pub fn check_ordinary(view:&BodyView<'_>,severity:Severity)->Result<Vec<Diagnostic>,String>{syntax_family_using(view.syntax(),severity,Family::Ordinary,&mut||Ok(()))}
pub fn archived_ordinary_checked(body:&ArchivedBody<'_>,severity:Severity,checkpoint:&mut impl FnMut()->std::io::Result<()>)->Result<Vec<Diagnostic>,PolicyFailure>{archived_family_checked(body,severity,Family::Ordinary,checkpoint)}
pub fn check(view:&BodyView<'_>,severity:Severity)->Result<Vec<Diagnostic>,String>{syntax_using(view.syntax(),severity,&mut||Ok(()))}
pub fn archived(body:&ArchivedBody<'_>,severity:Severity)->Result<Vec<Diagnostic>,String>{syntax_using(body.statement_body(),severity,&mut||Ok(()))}
/// Operation control varies; all callers share the same original prefix loop.
pub fn archived_checked(body:&ArchivedBody<'_>,severity:Severity,checkpoint:&mut impl FnMut()->std::io::Result<()>)->Result<Vec<Diagnostic>,PolicyFailure>{archived_family_checked(body,severity,Family::Linter,checkpoint)}
fn archived_family_checked(body:&ArchivedBody<'_>,severity:Severity,family:Family,checkpoint:&mut impl FnMut()->std::io::Result<()>)->Result<Vec<Diagnostic>,PolicyFailure>{let mut poll=||checkpoint().map_err(PolicyFailure::Operational);let result=syntax_family_using(body.statement_body(),severity,family,&mut poll);if matches!(&result,Err(PolicyFailure::Operational(_))){return result}poll()?;result}
fn syntax_using<E:From<String>>(syntax:&StatementBody,severity:Severity,checkpoint:&mut impl FnMut()->Result<(),E>)->Result<Vec<Diagnostic>,E>{syntax_family_using(syntax,severity,Family::Linter,checkpoint)}
fn syntax_family_using<E:From<String>>(syntax:&StatementBody,severity:Severity,family:Family,checkpoint:&mut impl FnMut()->Result<(),E>)->Result<Vec<Diagnostic>,E>{
 checkpoint()?;if !syntax.syntax_complete(){return Err("body has unsupported or malformed native syntax".to_owned().into())}if severity==Severity::Disabled{return Ok(Vec::new())}let mut rows=Vec::new();
 for statement in &syntax.parsed().statements{checkpoint()?;let Some(setting)=statement.setting()else{break};let name=setting.attribute;if name=="SpacemanDMM_return_type"{continue}
  let (family,message)=match family{
   Family::Linter if name.starts_with("SpacemanDMM_")&&!KNOWN.contains(&name)=>("unknown_linter_setting",format!("unknown linter setting {name:?}")),
   Family::Ordinary if !name.starts_with("SpacemanDMM_")&&!KNOWN_ORDINARY.contains(&name)=>("unknown_setting",format!("unknown setting {name:?}")),
   _=>continue,
  };
  rows.push(Diagnostic{family,severity,span:statement.header_span,expression_span:setting.value.current_span(),message,notes:Vec::new()});
 }checkpoint()?;Ok(rows)
}
#[cfg(test)]#[path="checks_unknown_linter_setting_tests.rs"]mod tests;

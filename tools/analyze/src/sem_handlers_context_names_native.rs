//! Original act/local classification on genuine current header/local loans.
//! No names are recovered from raw header strings or a second parser.
use crate::{reactive_reads_native::Failure,key_policy_control::{self as kc,Control}};
use dm_syntax::{Expr,ExprKind,Statement,StatementKind,ForControl,LocalSourceKind,VisitDecision};
use dm_tree::frontend::{CurrentArchivedBody,SourceLocalView,BodySyntaxFailure,OriginalBodyDisposition};
use std::collections::BTreeSet;
pub(crate) struct Names{pub acts:BTreeSet<String>,pub locals:BTreeSet<String>}
fn failure(e:BodySyntaxFailure)->Failure{match e{BodySyntaxFailure::Operational(actual)=>Failure::Operational(actual),BodySyntaxFailure::Syntax(actual)=>Failure::Unsupported(actual.message)}}
fn plain_call(mut e:&Expr)->Option<&str>{while let ExprKind::Group(inner)=&e.kind{e=inner}if let ExprKind::Call{callee,..}=&e.kind{if let ExprKind::Ident(name)=&callee.kind{if dm_analysis::original_base_terms::ordinary_call_name(name){return Some(name)}}}None}
fn insert<C:Control<Error=Failure>>(rows:&mut BTreeSet<String>,name:&str,c:&mut C)->Result<(),Failure>{c.checkpoint()?;if !rows.contains(name){kc::reserve(c,||Some(256))?;let owned=kc::own(c,name)?;rows.insert(owned);}Ok(())}
struct Visitor<'a,C,F>{project_name:F,locals:SourceLocalView<'a>,try_calls:&'a[&'a str],names:Names,c:&'a mut C,error:Option<Failure>}
impl<'a,C:Control<Error=Failure>,F:Fn(dm_syntax::Span)->Result<&'a str,Failure>> Visitor<'a,C,F>{
 fn entry(&mut self,entry:&dm_syntax::LocalVariableSyntax,value:Option<&Expr>)->Result<(),Failure>{
  self.c.checkpoint()?;let name=self.locals.name(entry)?;insert(&mut self.names.locals,name,self.c)?;
  // The exact local view computed this path's peak BEFORE formatting it.
  let width=self.locals.type_path_width(entry)?;kc::reserve(self.c,||width.checked_mul(4)?.checked_add(128))?;
  let path=self.locals.type_path(entry)?;let act=path.as_deref().is_some_and(|path|path=="/datum/act"||path.starts_with("/datum/act/"));
  if act||value.and_then(plain_call).is_some_and(|name|self.try_calls.contains(&name)){insert(&mut self.names.acts,name,self.c)?;}Ok(())
 }
 fn statement_inner(&mut self,node:&Statement)->Result<(),Failure>{
  self.c.checkpoint()?;match &node.kind{
   StatementKind::Var{value,..}=>{let entries=self.locals.in_span(node.header_span)?;let mut count=0;for entry in entries{if matches!(entry.source_kind,LocalSourceKind::Statement|LocalSourceKind::CommaContinuation){count+=1;self.entry(entry,value.as_ref())?;}}if count!=1{return Err("handler local initializer needs exact native declaration root association".into())}},
   StatementKind::For{control:ForControl::All{source_binding,..}|ForControl::Each{source_binding,..},..}=>{let entries=self.locals.in_span(node.header_span)?;let mut found=false;for entry in entries{if entry.source_kind==LocalSourceKind::ForBinding{found=true;self.entry(entry,None)?;}}if !found{let name=source_binding.ok_or("handler for-list binding lacks an actual native name component")?.name();let name=(self.project_name)(name)?;insert(&mut self.names.locals,name,self.c)?;}},
   // Original act_idents did not add C-style/range/pair/catch bindings.
   _=>(),
  }Ok(())
 }
 fn fail(&mut self,error:Failure)->VisitDecision{if self.error.is_none(){self.error=Some(error)}VisitDecision::Stop}
}
impl<'a,C:Control<Error=Failure>,F:Fn(dm_syntax::Span)->Result<&'a str,Failure>> dm_analysis::policy_body_observation::BaseChainVisitor for Visitor<'a,C,F>{
 fn statement(&mut self,node:&Statement)->VisitDecision{if self.error.is_some(){return VisitDecision::Stop}match self.statement_inner(node){Ok(())=>VisitDecision::Descend,Err(error)=>self.fail(error)}}
 fn expression(&mut self,_:&Expr,_:bool)->VisitDecision{VisitDecision::Skip}
 fn projected_expression(&mut self,_:dm_syntax::ProjectedExprView<'_>,_:bool)->VisitDecision{VisitDecision::Skip}
 fn frame_capacity(&mut self,n:usize)->Result<(),&'static str>{match self.c.reserve(n){Ok(())=>Ok(()),Err(error)=>{self.fail(error);Err("handler names frame admission refused")}}}
 fn frame_overflow(&mut self)->&'static str{let error=self.c.overflow();self.fail(error);"handler names frame overflow"}
 fn frame_allocation_failed(&mut self)->&'static str{let error=self.c.allocation_failed();self.fail(error);"handler names frame allocation failed"}
}
pub(crate) fn collect_using<C:Control<Error=Failure>>(body:&CurrentArchivedBody<'_,'_>,admission:&dm_syntax::SettingAdmission<'_>,try_calls:&[&str],c:&mut C)->Result<Names,Failure>{
 c.checkpoint()?;match body.syntax().original_code_disposition().map_err(failure)?{OriginalBodyDisposition::Available(grant)=>if !grant.belongs_to(body.syntax()){return Err("handler available BODY grant differs".into())},OriginalBodyDisposition::Skipped(_)=>return Err("handler names cannot run on genuine old skipped BODY".into())}
 let mut names=Names{acts:BTreeSet::new(),locals:BTreeSet::new()};let params=body.source_parameters(admission).map_err(failure)?;
 for parameter in params.entries()?{c.checkpoint()?;let name=params.name(parameter)?;insert(&mut names.locals,name,c)?;if parameter.array_brackets().is_empty()&&params.type_component(parameter,0)?==Some("datum")&&params.type_component(parameter,1)?==Some("act"){insert(&mut names.acts,name,c)?;}}
 let locals=body.source_locals(admission).map_err(failure)?;let scope=locals.scope_admission()?;kc::reserve(c,||Some(scope))?;
 let project_name=|canonical|{let current=body.syntax().projection().span(canonical).ok_or("handler native binding name escapes current BODY projection")?;body.current_source(current).map_err(failure)};let mut visitor=Visitor{project_name,locals,try_calls,names,c,error:None};let coverage=dm_analysis::policy_body_observation::observe_base_chains(body.syntax().canonical_statement_storage().view(),&mut visitor);if let Some(actual)=visitor.error{return Err(actual)}coverage.map_err(Failure::from)?;visitor.c.checkpoint()?;Ok(visitor.names)
}

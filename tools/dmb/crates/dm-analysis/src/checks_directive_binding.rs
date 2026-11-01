//! Pinned directive insertion diagnostics, separate from executable effects.
//! SpacemanDMM0290db5c752fa292f9824521515b603a2afd11dc lib.rs406..426,602..639,755..775 (GPL-3.0).
use crate::{checks::{BodyView,Diagnostic,Note,Severity},policy_body_demand::PolicyFailure};
use dm_tree::frontend::{ArchivedBody,StatementBody,CallableHeaderSource,CallableRoster};
use dm_ir::{ProcedureIdentity,ProcedureDefinition,Resolver,ResolveQuery as Q,ResolvedMeaning as M};
use dm_syntax::{Expr,ExprKind,Span,numeric_form::{numeric_form,NumericForm}};
#[derive(Clone,Copy)]pub enum Family{Incompatible,Disabled,Duplicate,InvalidValue,AtDefinition}
impl Family{pub fn name(self)->&'static str{match self{Self::Incompatible=>"incompatible_directive",Self::Disabled=>"disabled_directive",Self::Duplicate=>"sets_directive_twice",Self::InvalidValue=>"invalid_lint_directive_value",Self::AtDefinition=>"directive_at_definition"}}}
const FLAGS:[(bool,bool,bool);8]=[(false,false,false),(true,false,false),(false,true,false),(false,true,false),(false,true,true),(false,true,true),(false,true,true),(false,false,false)];
struct OriginalHeaders<'a>{roster:&'a CallableRoster,current:dm_tree::MemberId,source:CallableHeaderSource<'a>}
pub fn check(view:&BodyView<'_>,family:Family,severity:Severity)->Result<Vec<Diagnostic>,String>{let front=view.frontend();let roster=front.callable_roster()?;let current=view.body().occurrence().member;let identity=roster.identity_for_member(current).ok_or("directive callable issuance absent")?;syntax_using(view.syntax(),&front.snapshot.tree,identity,&OriginalHeaders{roster,current,source:front.callable_header_source()?},family,severity,&mut||Ok(()),&mut|_|Err("original Debug rendering requires checked archived source admission".into()))}
pub fn archived_checked(body:&ArchivedBody<'_>,family:Family,severity:Severity,checkpoint:&mut impl FnMut()->std::io::Result<()>)->Result<Vec<Diagnostic>,PolicyFailure>{let mut poll=||checkpoint().map_err(PolicyFailure::Operational);let result=(||{let archive=body.archive_owner();let roster=archive.callables();let current=body.occurrence().member;let identity=roster.identity_for_member(current).ok_or("directive callable issuance absent")?;syntax_using(body.statement_body(),body.tree(),identity,&OriginalHeaders{roster,current,source:archive.callable_header_source()},family,severity,&mut poll,&mut|_|Err("original Debug rendering requires checked archived source admission".into()))})();if matches!(&result,Err(PolicyFailure::Operational(_))){return result}poll()?;result}
fn truth(value:&Expr)->Result<Option<bool>,String>{Ok(match &value.kind{ExprKind::Ident(name)if name=="TRUE"=>Some(true),ExprKind::Ident(name)if name=="FALSE"=>Some(false),ExprKind::Literal(raw)if raw.as_str().as_bytes().first().is_some_and(u8::is_ascii_digit)=>match numeric_form(raw.as_str())?{NumericForm::Integer(0)=>Some(false),NumericForm::Integer(1)=>Some(true),_=>None},_=>None})}
fn formal<E:From<String>+From<&'static str>>(tree:&dm_tree::SemanticTree,identity:ProcedureIdentity,checkpoint:&mut impl FnMut()->Result<(),E>)->Result<Option<(ProcedureIdentity,u32)>,E>{let M::Members(rows)=Resolver::resolve(tree,Q::SourceDeclarationChain{owner:identity.owner,name:identity.name,verb:identity.verb})else{return Err("directive initial declaration chain unavailable".into())};for row in rows.iter(){checkpoint()?;let M::Declaration{identity:actual,definition,data,..}=row else{return Err("directive source chain malformed".into())};if *definition==ProcedureDefinition::Declare{return Ok(Some((*actual,data.flags)))}}Ok(None)}
fn source_member<E:From<String>+From<&'static str>>(tree:&dm_tree::SemanticTree,roster:&CallableRoster,identity:ProcedureIdentity,checkpoint:&mut impl FnMut()->Result<(),E>)->Result<dm_tree::MemberId,E>{let owner=tree.lookup_type(identity.owner).ok_or("directive formal owner unavailable")?;let members=&tree.type_node(owner).ok_or("directive formal owner absent")?.members;for member in members.iter(){checkpoint()?;if roster.identity_for_member(*member)==Some(identity){return Ok(*member)}}Err("directive formal has no issued original header".into())}

// The original declaration slot may come from the pinned builtin tree even
// when the effective implementation is authored source. A builtin point cannot
// equal a genuine registered source header; no invented source Location needed.
fn initial_is_own<E:From<String>+From<&'static str>>(tree:&dm_tree::SemanticTree,identity:ProcedureIdentity,headers:&OriginalHeaders<'_>,declaration:Option<(ProcedureIdentity,u32)>,checkpoint:&mut impl FnMut()->Result<(),E>)->Result<bool,E>{
 let source=if let Some((decl,_))=declaration{let member=source_member(tree,headers.roster,decl,checkpoint)?;Some((decl,headers.source.reported_point(member)?.same_reported_point(&headers.source.reported_point(headers.current)?)))}else{None};
 if let Some(profile)=tree.checker_builtin_profile(){tree.validate_checker_builtin_profile(profile).map_err(|e|format!("directive builtin declaration profile: {e:?}"))?;let catalog=dm_tree::checker_builtins::pinned_catalog().map_err(|e|format!("directive builtin declaration catalog: {e:?}"))?;if catalog.profile!=profile{return Err("directive builtin declaration catalog differs".into())}let M::Symbols(ancestry)=Resolver::resolve(tree,Q::Ancestry(identity.owner))else{return Err("directive declaration ancestry unavailable".into())};let source_depth=source.map(|(decl,_)|ancestry.iter().position(|owner|*owner==decl.owner).ok_or("source directive formal outside ancestry")).transpose()?;let mut builtin=None;
  for row in catalog.declarations.iter(){checkpoint()?;if row.name!=identity.name||row.definition!=dm_tree::DefinitionMode::Declare||!matches!(row.kind,dm_tree::MemberKind::Proc|dm_tree::MemberKind::Verb){continue}let Some(depth)=ancestry.iter().position(|owner|*owner==row.owner)else{continue};if builtin.is_none_or(|old|depth<old){builtin=Some(depth)}}
  if let Some(depth)=builtin{if source_depth.is_some_and(|source|source==depth){return Err("source and builtin same-owner formal redeclaration needs original duplicate-declaration admission".into())}if source_depth.is_none_or(|source|depth<source){return Ok(false)}}
 }
 Ok(source.map_or(true,|(_,own)|own))
}
#[derive(Clone,Copy)]enum FirstOrigin{Setting(Span),Header(dm_tree::MemberId)}
fn syntax_using<E:From<String>+From<&'static str>>(syntax:&StatementBody,tree:&dm_tree::SemanticTree,identity:ProcedureIdentity,headers:&OriginalHeaders<'_>,family:Family,severity:Severity,checkpoint:&mut impl FnMut()->Result<(),E>,invalid:&mut impl FnMut(usize)->Result<(),E>)->Result<Vec<Diagnostic>,E>{syntax_using_observed(syntax,tree,identity,headers,family,severity,checkpoint,invalid,None)}
fn syntax_using_observed<E:From<String>+From<&'static str>>(syntax:&StatementBody,tree:&dm_tree::SemanticTree,identity:ProcedureIdentity,headers:&OriginalHeaders<'_>,family:Family,severity:Severity,checkpoint:&mut impl FnMut()->Result<(),E>,invalid:&mut impl FnMut(usize)->Result<(),E>,mut accepted:Option<&mut[Option<Accepted>;8]>)->Result<Vec<Diagnostic>,E>{
 let emit=accepted.is_none();
 checkpoint()?;if !(if matches!(family,Family::InvalidValue)||accepted.is_some(){syntax.original_literal_syntax_complete()}else{syntax.syntax_complete()}){return Err("body has unsupported or malformed native syntax".into())}if severity==Severity::Disabled{return Ok(Vec::new())}
 let mut first:[Option<FirstOrigin>;8]=[None;8];let mut rows=Vec::new();let declaration=formal(tree,identity,checkpoint)?;let mut initial=None;
 // The original seeds OUR owner-local final declaration before explicit Set
 // statements, independently for each implementation ProcRef at its own point.
 if declaration.is_some_and(|(decl,flags)|decl.owner==identity.owner&&flags&dm_ir::PROC_FLAG_FINAL!=0){
  if identity.owner==dm_ir::SymbolId::of("/"){
   if emit&&matches!(family,Family::Incompatible){let display=crate::checker_callable_display::original(tree,identity,|_|Ok::<(),E>(()),&mut *checkpoint)?;let span=headers.source.reported_span(headers.current)?;rows.push(Diagnostic{family:family.name(),severity,span,expression_span:span,message:format!("{display} sets SpacemanDMM_should_not_override, which cannot be set on global procs"),notes:Vec::new()});}
  }else{first[0]=Some(FirstOrigin::Header(headers.current));if let Some(out)=accepted.as_deref_mut(){out[0]=Some(Accepted{enabled:true,at:headers.source.reported_span(headers.current)?});}}
 }
 for (ordinal,statement) in syntax.parsed().statements.iter().enumerate(){checkpoint()?;let Some(setting)=statement.setting()else{break};let name=setting.attribute;let Some(index)=crate::checks_unknown_linter_setting::KNOWN.iter().position(|known|*known==name)else{continue};let(can_disable,at_definition,can_global)=FLAGS[index];
  if at_definition{let own=match initial{Some(own)=>own,None=>{let own=initial_is_own(tree,identity,headers,declaration,checkpoint)?;initial=Some(own);own}};if !own{if emit&&matches!(family,Family::AtDefinition){rows.push(Diagnostic{family:family.name(),severity:Severity::Warning,span:statement.header_span,expression_span:setting.value.current_span(),message:format!("Can't define procs {name} outside their initial definition"),notes:Vec::new()});}continue}}
  let Some(enabled)=truth(setting.value.original())?else{
   if matches!(family,Family::InvalidValue){
    invalid(ordinal)?;
   }
   continue
  };
  let actual=if identity.owner==dm_ir::SymbolId::of("/")&&!can_global{Some((Family::Incompatible,"global"))}else if !enabled&&!can_disable{Some((Family::Disabled,"disabled"))}else if first[index].is_some(){Some((Family::Duplicate,"duplicate"))}else{first[index]=Some(FirstOrigin::Setting(statement.header_span));if let Some(out)=accepted.as_deref_mut(){out[index]=Some(Accepted{enabled,at:statement.header_span});}None};
  let Some((rejected,reason))=actual else{continue};if !emit||rejected.name()!=family.name(){continue}
  let display=crate::checker_callable_display::original(tree,identity,|_|Ok::<(),E>(()),&mut *checkpoint)?;
  let message=match reason{"global"=>format!("{display} sets {name}, which cannot be set on global procs"),"disabled"=>format!("{display} sets {name} false, but it cannot be disabled."),_=>format!("{display} sets {name} twice")};
  let mut notes=Vec::new();if matches!(rejected,Family::Duplicate){let source=match first[index].expect("duplicate accepted first directive"){FirstOrigin::Setting(span)=>headers.source.reported_source_point(span.start)?,FirstOrigin::Header(member)=>headers.source.reported_point(member)?};let current=headers.source.reported_source_point(statement.header_span.start)?;notes.push(original_note(source,current));}
  rows.push(Diagnostic{family:family.name(),severity,span:statement.header_span,expression_span:setting.value.current_span(),message,notes});
 }checkpoint()?;Ok(rows)
}
#[cfg(test)]#[path="checks_directive_binding_tests.rs"]mod tests;

// Pinned Context::pretty_print_error: identical point has no coordinate prefix;
// same reported file has line:column; another file uses its original registry key.
fn original_note(source:dm_tree::frontend::BorrowedSourceNoteOrigin<'_>,current:dm_tree::frontend::BorrowedSourceNoteOrigin<'_>)->Note{original_note_message(source,current,"first definition here")}
pub(crate) fn original_note_message(source:dm_tree::frontend::BorrowedSourceNoteOrigin<'_>,current:dm_tree::frontend::BorrowedSourceNoteOrigin<'_>,message:&str)->Note{
 if source.same_reported_point(&current){return Note{message:message.into(),source:None}}
 let(path,line,column)=source.reported_coordinates();if path==current.reported_coordinates().0{Note{message:message.into(),source:Some(source.into_owned())}}else{Note{message:format!("{}:{line}:{column}: {message}",path.display()),source:None}}
}

/// The actual existing host admission is supplied by
/// the source-bound caller; all three existing families keep their old entry.
/// The rendering callback selects only the original statement ordinal already
/// visited by the unique definition/known-name/truth loop above.
fn archived_value_using(body:&ArchivedBody<'_>,severity:Severity,a:&dm_syntax::SettingAdmission<'_>,checkpoint:&mut impl FnMut()->std::io::Result<()>)->Result<crate::checker_original_expression_debug::OriginalDiagnosticRows,PolicyFailure>{
 let mut poll=||checkpoint().map_err(PolicyFailure::Operational);
 let pending=(||{let archive=body.archive_owner();let roster=archive.callables();let current=body.occurrence().member;let identity=roster.identity_for_member(current).ok_or("directive callable issuance absent")?;
 let mut output=crate::checker_original_expression_debug::OriginalDiagnosticRows::new(a)?;
 let ordinary=syntax_using(body.statement_body(),body.tree(),identity,&OriginalHeaders{roster,current,source:archive.callable_header_source()},Family::InvalidValue,severity,&mut poll,&mut|ordinal|output.push_setting(body,ordinal,severity,a))?;
 if !ordinary.is_empty(){return Err("invalid-value projection emitted an unexpected ordinary row".into())}Ok(output)})();
 if matches!(&pending,Err(PolicyFailure::Operational(_))){return pending}poll()?;pending
}

/// Source-bound invalid-value entry. The actual archive upgrades only its
/// existing native expression host; no caller may substitute a new counter.
/// Rows remain sealed and funded while the consumer borrows them to serialize.
pub fn archived_value_checked(body:&ArchivedBody<'_>,severity:Severity,checkpoint:&mut impl FnMut()->std::io::Result<()>)->Result<crate::checker_original_expression_debug::OriginalDiagnosticRows,PolicyFailure>{
 let pending=body.with_original_syntax_admission(|a|{
  match archived_value_using(body,severity,a,checkpoint){
   Err(PolicyFailure::Operational(actual))=>Err(dm_tree::frontend::BodySyntaxFailure::Operational(actual)),
   other=>Ok(other),
  }
 });
 match pending{Ok(result)=>result,Err(dm_tree::frontend::BodySyntaxFailure::Operational(actual))=>Err(PolicyFailure::Operational(actual)),Err(dm_tree::frontend::BodySyntaxFailure::Syntax(error))=>Err(error.message.into())}
}

/// Borrow accepted owner-local directive coordinates from the SAME unique
/// insertion policy, through the actual source prefix loan. No policy map or
/// diagnostic formatting is rebuilt for a call-site query.
#[derive(Clone,Copy)]pub(crate) struct Accepted{pub enabled:bool,pub at:Span}
pub(crate) fn accepted_own_using<D:crate::checker_prefix_demand::Demand>(archive:&dm_tree::frontend::BodyArchive,identity:ProcedureIdentity,demand:&D)->Result<[Option<Accepted>;8],D::Error>{
 let roster=archive.callables();let current=source_member(archive.tree(),roster,identity,&mut||demand.checkpoint())?;
 let headers=OriginalHeaders{roster,current,source:archive.callable_header_source()};let mut accepted=[None;8];
 demand.prefix(archive,identity,|prefix|{let mut checkpoint=||demand.checkpoint();syntax_using_observed(prefix.statement_body(),archive.tree(),identity,&headers,Family::Duplicate,Severity::Error,&mut checkpoint,&mut|_|Ok(()),Some(&mut accepted)).map(|_|())})??;
 Ok(accepted)
}

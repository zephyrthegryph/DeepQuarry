//! One scoped current-source binding of canonical native BODY syntax DATA.
//! No second AST, source table, semantic model, cache or parser is constructed.
use super::*;
use super::body_queries::{CurrentBodySyntax,OriginalBodySyntaxProduct};
pub struct CurrentArchivedBody<'archive,'syntax>{
 archive:&'archive BodyArchive,
 occurrence:&'archive BodyOccurrence,
 current:CurrentBodySyntax<'syntax>,
}
impl<'a,'p> CurrentArchivedBody<'a,'p>{
 pub fn archive_owner(&self)->&'a BodyArchive{self.archive}
 pub fn occurrence(&self)->&'a BodyOccurrence{self.occurrence}
 pub fn tree(&self)->&'a SemanticTree{self.archive.tree()}
 pub fn syntax(&self)->&CurrentBodySyntax<'p>{&self.current}
 pub fn belongs_to(&self,archive:&BodyArchive)->bool{std::ptr::eq(self.archive,archive)}
 pub fn current_source(&self,span:dm_syntax::Span)->Result<&'a str,BodySyntaxFailure>{
  let body=self.occurrence.expanded_span;
  if span.start<body.start||span.end>body.end{return Err(current_error("selected current syntax point escapes actual body"))}
  self.archive.source.get(span.range()).ok_or_else(||current_error("selected current syntax point escapes actual source"))
 }
 /// Reuses the existing source-parameter view and validator over this actual
 /// current tree/occurrence and the SAME canonical parameter ledger. No clone,
 /// reparse, runtime-metadata substitution or shifted source string is made.
 pub fn source_parameters(&self,a:&dm_syntax::SettingAdmission<'_>)->Result<super::body_archive::SourceParameterView<'_>,BodySyntaxFailure>{
  current_checkpoint(a)?;
  let parameters=self.current.parameters()?;
  super::body_archive::checked_source_parameters_projected(self.tree(),self.occurrence,self.current.header_span(),parameters.original(),&self.archive.source,Some(self.current.projection()),&||current_checkpoint(a),&|actual|BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidData,actual)))
 }
 /// SAME local ledger and scope-geometry algorithm, over authenticated current
 /// source coordinates and model. No source scan or second local symbol table.
 pub fn source_locals(&self,a:&dm_syntax::SettingAdmission<'_>)->Result<super::body_archive::SourceLocalView<'_>,BodySyntaxFailure>{
  current_checkpoint(a)?;super::body_archive::checked_source_locals_projected(self.tree(),self.occurrence,self.current.canonical_statement_storage(),&self.archive.source,Some(self.current.projection()),self.archive.source_mapping().initial_environment()==dm_preprocess::InitialEnvironment::OriginalChecker0290,&||current_checkpoint(a),&|actual|BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidData,actual)))
 }
 /// Use an already-bound primary body with the same admission finish as
 /// a newly borrowed canonical body. The prefix still validates its identity.
 pub fn with_reused_initial_setting_prefix<T>(
  &self,identity:dm_ir::ProcedureIdentity,admission:&dm_syntax::SettingAdmission<'_>,
  consume:impl FnOnce(super::InitialSettingPrefix<'_>)->T,
 )->Result<T,BodySyntaxFailure>{
  current_checkpoint(admission)?;
  let pending=self.with_initial_setting_prefix(identity,admission,consume);
  finish_current_body(admission,pending)
 }
 pub fn native_current_tokens(&self)->Result<crate::procedure::header_input::OriginalBodyTokens<'_>,BodySyntaxFailure>{
  let ordinal=*self.archive.body_indices.get(&self.occurrence.declaration).ok_or_else(||current_error("actual current body declaration index absent"))?;
  self.archive.syntax.original_body_tokens_header_only(self.occurrence.expanded_span).map_err(|_|current_error("actual current primary token recipe absent"))
 }
}
fn current_checkpoint(a:&dm_syntax::SettingAdmission<'_>)->Result<(),BodySyntaxFailure>{let status=a.checkpoint();if let Some(actual)=a.take_operational_error(){return Err(BodySyntaxFailure::Operational(actual))}status.map_err(BodySyntaxFailure::Operational)}
fn finish_current_body<T>(
 a:&dm_syntax::SettingAdmission<'_>,result:Result<T,BodySyntaxFailure>,
)->Result<T,BodySyntaxFailure>{
 if matches!(&result,Err(BodySyntaxFailure::Operational(_))){
  return match a.take_operational_error(){Some(actual)=>Err(BodySyntaxFailure::Operational(actual)),None=>result}
 }
 current_checkpoint(a)?;
 result
}
#[derive(Clone,Copy)]enum CurrentBodyContract{Strict,Utility}
fn current_unavailable(message:&'static str)->BodySyntaxFailure{BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::NotConnected,message))}
fn current_error(message:&'static str)->BodySyntaxFailure{BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidData,message))}
impl BodyArchive{
 /// Flat existing-native-host demand. There is no compatibility statement
 /// parse when the canonical product contract is unavailable.
 pub fn with_current_body_checked<'a,T>(&'a self,ordinal:usize,a:&dm_syntax::SettingAdmission<'_>,consume:impl for<'p>FnOnce(CurrentArchivedBody<'a,'p>)->Result<T,BodySyntaxFailure>)->Result<T,BodySyntaxFailure>{
  let queries=self.body_queries.as_ref().ok_or_else(||current_unavailable("current BODY demand requires actual native query owner"))?;
  self.with_current_body_in(ordinal,a,&mut(),false,CurrentBodyContract::Strict,|_,input|queries.host.syntax_product_checked(input),|_,body|consume(body.ok_or_else(||current_error("strict current BODY omitted actual syntax"))?))
 }
 /// Active-context demand: borrow ONE existing context sequentially for the
 /// real syntax child get and the current semantic consumer. The two callbacks
 /// need not capture competing mutable context loans or reacquire a gate.
 pub fn with_current_body_checked_in<'a,C,T>(&'a self,ordinal:usize,a:&dm_syntax::SettingAdmission<'_>,context:&mut C,obtain:impl FnOnce(&mut C,&Arc<BodySyntaxInput>)->Result<Arc<OriginalBodySyntaxProduct>,BodySyntaxFailure>,consume:impl for<'p>FnOnce(&mut C,CurrentArchivedBody<'a,'p>)->Result<T,BodySyntaxFailure>)->Result<T,BodySyntaxFailure>{
  self.with_current_body_in(ordinal,a,context,true,CurrentBodyContract::Strict,obtain,|context,body|consume(context,body.ok_or_else(||current_error("strict current BODY omitted actual syntax"))?))
 }
 fn with_current_body_in<'a,C,T>(&'a self,ordinal:usize,a:&dm_syntax::SettingAdmission<'_>,context:&mut C,prepare:bool,contract:CurrentBodyContract,obtain:impl FnOnce(&mut C,&Arc<BodySyntaxInput>)->Result<Arc<OriginalBodySyntaxProduct>,BodySyntaxFailure>,consume:impl for<'p>FnOnce(&mut C,Option<CurrentArchivedBody<'a,'p>>)->Result<T,BodySyntaxFailure>)->Result<T,BodySyntaxFailure>{
  current_checkpoint(a)?;
  let queries=self.body_queries.as_ref().ok_or_else(||current_unavailable("current BODY demand requires actual native query inputs"))?;
  let occurrence=self.bodies.get(ordinal).ok_or_else(||current_error("actual current BODY ordinal absent"))?;
  let input=super::body_queries::current_input_admitted(&queries.inputs,&self.bodies,ordinal,&self.syntax,&self.source,&self.mapping,a)?;
  if input.captured_span()!=occurrence.expanded_span{return Err(current_error("actual archive occurrence/query input differs"))}let code=input.original_code_owner().ok_or_else(||current_error("actual current input code absent"))?;self.syntax.original_body_recipe_checked(occurrence.expanded_span,code)?;
  if prepare{queries.host.prepare_syntax_product_input(&input)?;}
  let product=obtain(context,&input)?;
  if matches!(contract,CurrentBodyContract::Utility)&&matches!(product.as_ref(),OriginalBodySyntaxProduct::Rejected(_)){
   if !product.rejects_current_input_admitted(&input,a)?{return Err(current_error("utility rejection omitted its actual current binding"))}
   return finish_current_body(a,consume(context,None))
  }
  if let Some(error)=product.bind_error(&input)?{return Err(BodySyntaxFailure::Syntax(error))}
  let syntax=product.parsed().ok_or_else(||current_error("native product emitted no parse or actual source failure"))?;
  // Parsing/publication may add real leases and the existing soft cache estimate
  // after pre-demand pressure preparation. Keep this actual product loan alive
  // while the SAME host prepares room for current-coordinate binding scratch.
  queries.host.prepare_syntax_product_input(&input)?;
  let current=input.bind_original_product_checked(syntax,a)?;
  let result=consume(context,Some(CurrentArchivedBody{archive:self,occurrence,current}));
  finish_current_body(a,result)
 }
}

impl BodyArchive{
 /// Resource-only loan of the SAME archive's existing syntax host. No parser,
 /// gate/reset, source receipt or semantic policy is issued.
 pub fn with_original_syntax_admission<T>(&self,operation:impl FnOnce(&dm_syntax::SettingAdmission<'_>)->Result<T,BodySyntaxFailure>)->Result<T,BodySyntaxFailure>{super::initializer_source::original_admission_using(self.setting_queries.as_ref(),operation)}
 /// Distinct utility consumption over the SAME canonical product/binding
 /// kernel. None only follows an actually bound Rejected native product.
 /// Strict CHECK/Checker/current-body entrypoints never select this contract.
 pub fn with_utility_current_body_checked_in<'a,C,T>(&'a self,ordinal:usize,a:&dm_syntax::SettingAdmission<'_>,context:&mut C,obtain:impl FnOnce(&mut C,&Arc<BodySyntaxInput>)->Result<Arc<OriginalBodySyntaxProduct>,BodySyntaxFailure>,consume:impl for<'p>FnOnce(&mut C,Option<CurrentArchivedBody<'a,'p>>)->Result<T,BodySyntaxFailure>)->Result<T,BodySyntaxFailure>{
  current_checkpoint(a)?;
  let occurrence=self.bodies.get(ordinal).ok_or_else(||current_error("actual utility BODY ordinal absent"))?;
  if self.source_mapping().initial_environment()!=dm_preprocess::InitialEnvironment::OriginalChecker0290||self.syntax.body_has_parser_report_prefix(occurrence.expanded_span){return Err(current_error("utility body cannot use ordinary or report-only prefix source"))}
  self.with_current_body_in(ordinal,a,context,true,CurrentBodyContract::Utility,obtain,consume)
 }
}

impl BodyArchive{
 pub(in crate::frontend) fn require_utility_frontend(&self,front:&ColdFrontend)->Result<(),BodySyntaxFailure>{
  if !Arc::ptr_eq(&self.tree,&front.snapshot.tree)||!Arc::ptr_eq(&self.declarations,&front.snapshot.occurrences)||!Arc::ptr_eq(&self.syntax,&front.issued_syntax)||!Arc::ptr_eq(&self.bodies,&front.issued_bodies)||!self.source.same_view(&front.issued_arena)||front.source_export_mapping().is_none_or(|mapping|!Arc::ptr_eq(&self.mapping,mapping)){return Err(BodySyntaxFailure::Syntax(internal("utility declaration column and archive differ from actual current source")))}
  Ok(())
 }
 pub fn member_original_first_source_order(&self,member:crate::MemberId)->Result<Option<usize>,String>{
  let Some(ordinal)=self.declarations.first_native_target(crate::Target::Member(member)).map_err(str::to_owned)?else{return Ok(None)};
  self.mapping.declaration_encounter_order(ordinal).map(Some)
 }
 /// Actual current source encounter DATA from the already-funded native
 /// target index. This grants no initializer/body/source-role authority.
 pub fn member_original_source_order(&self,member:crate::MemberId)->Result<Option<usize>,String>{
  let Some(ordinal)=self.declarations.last_native_target(crate::Target::Member(member)).map_err(str::to_owned)?else{return Ok(None)};
  self.mapping.declaration_encounter_order(ordinal).map(Some)
 }
}

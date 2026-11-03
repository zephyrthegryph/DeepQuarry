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
  current_checkpoint(a)?;super::body_archive::checked_source_locals_projected(self.tree(),self.occurrence,self.current.canonical_statement_storage(),&self.archive.source,Some(self.current.projection()),&||current_checkpoint(a),&|actual|BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidData,actual)))
 }
 pub fn native_current_tokens(&self)->Result<crate::procedure::header_input::OriginalBodyTokens<'_>,BodySyntaxFailure>{
  let ordinal=*self.archive.body_indices.get(&self.occurrence.declaration).ok_or_else(||current_error("actual current body declaration index absent"))?;
  let code=self.archive.body_codes.get(ordinal).ok_or_else(||current_error("actual current original code absent"))?;
  self.archive.syntax.original_body_tokens(self.occurrence.expanded_span,&code.identity).map_err(|_|current_error("actual current primary token recipe absent"))
 }
}
fn current_checkpoint(a:&dm_syntax::SettingAdmission<'_>)->Result<(),BodySyntaxFailure>{let status=a.checkpoint();if let Some(actual)=a.take_operational_error(){return Err(BodySyntaxFailure::Operational(actual))}status.map_err(BodySyntaxFailure::Operational)}
fn current_unavailable(message:&'static str)->BodySyntaxFailure{BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::NotConnected,message))}
fn current_error(message:&'static str)->BodySyntaxFailure{BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidData,message))}
impl BodyArchive{
 /// Flat existing-native-host demand. There is no compatibility statement
 /// parse when the canonical product contract is unavailable.
 pub fn with_current_body_checked<'a,T>(&'a self,ordinal:usize,a:&dm_syntax::SettingAdmission<'_>,consume:impl for<'p>FnOnce(CurrentArchivedBody<'a,'p>)->Result<T,BodySyntaxFailure>)->Result<T,BodySyntaxFailure>{
  let queries=self.body_queries.as_ref().ok_or_else(||current_unavailable("current BODY demand requires actual native query owner"))?;
  self.with_current_body_in(ordinal,a,&mut(),false,|_,input|queries.host.syntax_product_checked(input),|_,body|consume(body))
 }
 /// Active-context demand: borrow ONE existing context sequentially for the
 /// real syntax child get and the current semantic consumer. The two callbacks
 /// need not capture competing mutable context loans or reacquire a gate.
 pub fn with_current_body_checked_in<'a,C,T>(&'a self,ordinal:usize,a:&dm_syntax::SettingAdmission<'_>,context:&mut C,obtain:impl FnOnce(&mut C,&Arc<BodySyntaxInput>)->Result<Arc<OriginalBodySyntaxProduct>,BodySyntaxFailure>,consume:impl for<'p>FnOnce(&mut C,CurrentArchivedBody<'a,'p>)->Result<T,BodySyntaxFailure>)->Result<T,BodySyntaxFailure>{
  self.with_current_body_in(ordinal,a,context,true,obtain,consume)
 }
 fn with_current_body_in<'a,C,T>(&'a self,ordinal:usize,a:&dm_syntax::SettingAdmission<'_>,context:&mut C,prepare:bool,obtain:impl FnOnce(&mut C,&Arc<BodySyntaxInput>)->Result<Arc<OriginalBodySyntaxProduct>,BodySyntaxFailure>,consume:impl for<'p>FnOnce(&mut C,CurrentArchivedBody<'a,'p>)->Result<T,BodySyntaxFailure>)->Result<T,BodySyntaxFailure>{
  current_checkpoint(a)?;
  let queries=self.body_queries.as_ref().ok_or_else(||current_unavailable("current BODY demand requires actual native query inputs"))?;
  let occurrence=self.bodies.get(ordinal).ok_or_else(||current_error("actual current BODY ordinal absent"))?;
  let input=queries.inputs.get(ordinal).ok_or_else(||current_error("actual current BODY query input absent"))?;
  let code=self.body_codes.get(ordinal).ok_or_else(||current_error("actual current BODY code receipt absent"))?;
  if input.captured_span()!=occurrence.expanded_span||!input.original_code_owner().is_some_and(|actual|Arc::ptr_eq(actual,&code.identity)){return Err(current_error("actual archive occurrence/code/query input differs"))}
  if prepare{queries.host.prepare_syntax_product_input(input)?;}
  let product=obtain(context,input)?;
  if let Some(error)=product.bind_error(input)?{return Err(BodySyntaxFailure::Syntax(error))}
  let syntax=product.parsed().ok_or_else(||current_error("native product emitted no parse or actual source failure"))?;
  let current=input.bind_original_product_checked(syntax,a)?;
  let result=consume(context,CurrentArchivedBody{archive:self,occurrence,current});
  if matches!(&result,Err(BodySyntaxFailure::Operational(_))){return match a.take_operational_error(){Some(actual)=>Err(BodySyntaxFailure::Operational(actual)),None=>result}}
  let status=a.checkpoint();if let Some(actual)=a.take_operational_error(){return Err(BodySyntaxFailure::Operational(actual))}status.map_err(BodySyntaxFailure::Operational)?;result
 }
}

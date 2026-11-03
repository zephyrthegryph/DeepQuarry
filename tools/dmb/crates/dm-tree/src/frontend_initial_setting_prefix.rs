//! A callback-only proof over the compiler's existing issued BodySyntax node.
//! No second body parser, semantic traversal, retained AST or query database.
use super::{BodyArchive, StatementBody};
use crate::{MemberKind, SemanticTree};
use dm_ir::ProcedureIdentity;
use dm_syntax::{Span, Statement, StatementKind};

pub struct InitialSettingPrefix<'a> {
    archive: &'a BodyArchive,
    identity: ProcedureIdentity,
    settings: &'a [Statement],
    syntax: &'a StatementBody,
    first_non_setting: Option<Span>,
    body: &'a dyn InitialSettingSource,
}
impl<'a> InitialSettingPrefix<'a> {
    /// The same live body guard already held for this synchronous prefix loan.
    pub fn source_body(&self)->&dyn InitialSettingSource{self.body}
    pub fn tree(&self) -> &'a SemanticTree {
        self.archive.tree()
    }
    pub fn identity(&self) -> ProcedureIdentity {
        self.identity
    }
    /// Same already-validated primary body, borrowed only inside this loan.
    pub fn statement_body(&self)->&'a StatementBody{self.syntax}
    pub fn settings(&self) -> &'a [Statement] {
        self.settings
    }
    pub fn first_non_setting(&self) -> Option<Span> {
        self.first_non_setting
    }
    pub fn belongs_to(&self, archive: &BodyArchive) -> bool {
        std::ptr::eq(self.archive, archive)
    }
}
fn prefix_len(body:&StatementBody)->usize{match prefix_len_using(body,&||Ok::<(),std::convert::Infallible>(() )){Ok(count)=>count,Err(never)=>match never{}}}
fn prefix_len_using<E>(body:&StatementBody,checkpoint:&dyn Fn()->Result<(),E>)->Result<usize,E>{let mut count=0;for statement in &body.parsed().statements{checkpoint()?;if !matches!(&statement.kind,StatementKind::Set{..}|StatementKind::ProjectedSet{..}){break}count+=1;}Ok(count)}

impl BodyArchive {
    /// Borrow prefix syntax while the existing primary-node guard is held.
    /// `consume` cannot return borrows of its temporary prefix/body guard.
    /// Callee lookup reads only BodySyntax; it never asks for semantic-body
    /// findings, inferred returns, caller state, or another QueryDb.
    pub fn with_initial_setting_prefix<T>(&self,identity:ProcedureIdentity,consume:impl FnOnce(InitialSettingPrefix<'_>)->T)->Result<T,String>{
        self.with_initial_setting_prefix_using(identity,|archive,ordinal|archive.parse(ordinal).map_err(|error|error.message),consume)
    }
    pub fn with_initial_setting_prefix_using<'source,T,E:From<String>+From<&'static str>>(
        &'source self,identity:ProcedureIdentity,
        parse:impl FnOnce(&'source BodyArchive,usize)->Result<super::ArchivedBody<'source>,E>,
        consume:impl FnOnce(InitialSettingPrefix<'_>)->T,
    )->Result<T,E>{self.with_initial_setting_prefix_mode_using(identity,false,parse,consume)}
    pub fn with_initial_setting_prefix_original_syntax_using<'source,T,E:From<String>+From<&'static str>>(
        &'source self,identity:ProcedureIdentity,
        parse:impl FnOnce(&'source BodyArchive,usize)->Result<super::ArchivedBody<'source>,E>,
        consume:impl FnOnce(InitialSettingPrefix<'_>)->T,
    )->Result<T,E>{self.with_initial_setting_prefix_mode_using(identity,true,parse,consume)}
    fn with_initial_setting_prefix_mode_using<'source,T,E:From<String>+From<&'static str>>(
        &'source self,identity:ProcedureIdentity,original_syntax:bool,
        parse:impl FnOnce(&'source BodyArchive,usize)->Result<super::ArchivedBody<'source>,E>,
        consume:impl FnOnce(InitialSettingPrefix<'_>)->T,
    )->Result<T,E>{
        if self.body_query_host().is_none(){return Err("setting prefix needs the original retained compiler BodySyntax query owner".into())}
        let tree=self.tree();let kind=if identity.verb{MemberKind::Verb}else{MemberKind::Proc};
        let owner=tree.lookup_type(identity.owner).ok_or("prefix source owner unavailable")?;
        let mut member=tree.resolve(owner,identity.name,kind);let mut selected=None;let mut steps=0usize;
        while let Some(id)=member{
            steps=steps.checked_add(1).filter(|n|*n<=tree.members().len()).ok_or("prefix source member history is cyclic")?;
            let node=tree.member(id).ok_or("prefix source member unavailable")?;
            if self.callables().identity_for_member(id)==Some(identity){selected=self.callables().ordinal(id);break}
            member=node.previous;
        }
        let ordinal=selected.ok_or("source callable has no issued primary body for prefix proof")?;
        let body=parse(self,ordinal)?;
        if !std::ptr::eq(body.occurrence(),self.occurrences().get(ordinal).ok_or("prefix original occurrence unavailable")?){return Err("prefix parser returned another original callable occurrence".into())}
        if !body.belongs_to(self) || !(if original_syntax{body.statement_body().original_literal_syntax_complete()}else{body.statement_body().syntax_complete()}) {
            return Err("prefix body is foreign or has incomplete primary syntax".into());
        }
        let syntax = body.statement_body();
        let count = prefix_len(syntax);
        let statements = &syntax.parsed().statements;
        Ok(consume(InitialSettingPrefix {
            archive: self,
            body: &body,
            identity,
            settings: &statements[..count],
            syntax,
            first_non_setting: statements.get(count).map(|statement| statement.header_span),
        }))
    }
}

// This is a sealed borrowed source context, not another parsed body or model.
// Only actual private issued/current archive guards can construct an issuer.
mod source_seal{pub trait Sealed{}}
pub trait InitialSettingSource:source_seal::Sealed{
 fn archive_owner(&self)->&BodyArchive;
 fn tree(&self)->&SemanticTree;
 fn occurrence(&self)->&super::BodyOccurrence;
 fn statement_body(&self)->&StatementBody;
 fn original_body_tokens(&self)->Result<crate::procedure::header_input::OriginalBodyTokens<'_>,super::BodySyntaxFailure>;
 fn source_point(&self,canonical:Span)->Result<Span,String>;
 fn canonical_point(&self,current:Span)->Result<Span,String>;
 fn source_admission(&self,consume:&mut dyn FnMut(&dm_syntax::SettingAdmission<'_>)->Result<(),super::BodySyntaxFailure>)->Result<(),super::BodySyntaxFailure>;
}
impl source_seal::Sealed for super::ArchivedBody<'_>{}
impl InitialSettingSource for super::ArchivedBody<'_>{
 fn archive_owner(&self)->&BodyArchive{super::ArchivedBody::archive_owner(self)}
 fn tree(&self)->&SemanticTree{super::ArchivedBody::tree(self)}
 fn occurrence(&self)->&super::BodyOccurrence{super::ArchivedBody::occurrence(self)}
 fn statement_body(&self)->&StatementBody{super::ArchivedBody::statement_body(self)}
 fn original_body_tokens(&self)->Result<crate::procedure::header_input::OriginalBodyTokens<'_>,super::BodySyntaxFailure>{super::ArchivedBody::original_body_tokens(self).map_err(|message|super::BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidData,message)))}
 fn source_point(&self,point:Span)->Result<Span,String>{Ok(point)}
 fn canonical_point(&self,point:Span)->Result<Span,String>{Ok(point)}
 fn source_admission(&self,consume:&mut dyn FnMut(&dm_syntax::SettingAdmission<'_>)->Result<(),super::BodySyntaxFailure>)->Result<(),super::BodySyntaxFailure>{self.with_original_syntax_admission(|admission|consume(admission))}
}
struct CurrentPrefixSource<'guard,'archive,'syntax,'operation>{body:&'guard super::CurrentArchivedBody<'archive,'syntax>,admission:&'guard dm_syntax::SettingAdmission<'operation>}
impl source_seal::Sealed for CurrentPrefixSource<'_,'_,'_,'_>{}
impl InitialSettingSource for CurrentPrefixSource<'_,'_,'_,'_>{
 fn archive_owner(&self)->&BodyArchive{self.body.archive_owner()}
 fn tree(&self)->&SemanticTree{self.body.tree()}
 fn occurrence(&self)->&super::BodyOccurrence{self.body.occurrence()}
 fn statement_body(&self)->&StatementBody{self.body.syntax().canonical_statement_storage()}
 fn original_body_tokens(&self)->Result<crate::procedure::header_input::OriginalBodyTokens<'_>,super::BodySyntaxFailure>{self.body.native_current_tokens()}
 fn source_point(&self,point:Span)->Result<Span,String>{self.body.syntax().projection().span(point).ok_or_else(||"canonical setting point escapes actual current BODY".into())}
 fn canonical_point(&self,point:Span)->Result<Span,String>{self.body.syntax().projection().inverse().span(point).ok_or_else(||"current setting point escapes actual canonical BODY".into())}
 fn source_admission(&self,consume:&mut dyn FnMut(&dm_syntax::SettingAdmission<'_>)->Result<(),super::BodySyntaxFailure>)->Result<(),super::BodySyntaxFailure>{
  let pending=consume(self.admission);if let Some(actual)=self.admission.take_operational_error(){return Err(super::BodySyntaxFailure::Operational(actual))}if matches!(&pending,Err(super::BodySyntaxFailure::Operational(_))){return pending}let status=self.admission.checkpoint();if let Some(actual)=self.admission.take_operational_error(){return Err(super::BodySyntaxFailure::Operational(actual))}status.map_err(super::BodySyntaxFailure::Operational)?;pending
 }
}
impl dyn InitialSettingSource+'_ {
 /// Typed callback errors cross the same actual source guard. In particular,
 /// an actual earlier reader/OOM error is not hidden inside an opaque T.
 pub fn with_source_admission<T>(&self,consume:impl FnOnce(&dm_syntax::SettingAdmission<'_>)->Result<T,super::BodySyntaxFailure>)->Result<T,super::BodySyntaxFailure>{let mut consume=Some(consume);let mut result=None;self.source_admission(&mut|admission|{let operation=consume.take().ok_or_else(||super::BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidData,"initial setting source callback repeated")))?;result=Some(operation(admission)?);Ok(())})?;result.ok_or_else(||super::BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidData,"initial setting source callback omitted")))}
}
impl super::CurrentArchivedBody<'_,'_>{
 /// Same prefix selector over the canonical parsed product, with the current
 /// source/tree/token/admission guard. No ArchivedBody is forged or reparsed.
 pub fn with_initial_setting_prefix<T>(&self,identity:ProcedureIdentity,admission:&dm_syntax::SettingAdmission<'_>,consume:impl FnOnce(InitialSettingPrefix<'_>)->T)->Result<T,super::BodySyntaxFailure>{
  let archive=self.archive_owner();let actual=archive.callables().identity_for_member(self.occurrence().member);if actual!=Some(identity){return Err(super::BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidData,"current setting prefix callable identity differs")))}
  let syntax=self.syntax().canonical_statement_storage();
  // Authentic old code-None is decided by the SAME private native outcome,
  // before a completeness condition that its real recovering syntax cannot
  // satisfy. Available code still requires the full qualified literal owner.
  let skipped=match self.syntax().original_code_disposition()?{super::OriginalBodyDisposition::Available(_)=>false,super::OriginalBodyDisposition::Skipped(_)=>true};if !skipped&&!syntax.original_literal_syntax_complete(){return Err(super::BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::Unsupported,"current prefix lacks complete native literal syntax")))}let count=if skipped{0}else{prefix_len_using(syntax,&||{let status=admission.checkpoint();if let Some(actual)=admission.take_operational_error(){return Err(super::BodySyntaxFailure::Operational(actual))}status.map_err(super::BodySyntaxFailure::Operational)})?};let source=CurrentPrefixSource{body:self,admission};
  Ok(consume(InitialSettingPrefix{archive,identity,settings:if skipped{&[]}else{&syntax.parsed().statements[..count]},syntax,first_non_setting:if skipped{None}else{syntax.parsed().statements.get(count).map(|row|row.header_span)},body:&source}))
 }
}

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
}
impl<'a> InitialSettingPrefix<'a> {
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
fn prefix_len(body: &StatementBody) -> usize {
    body.parsed()
        .statements
        .iter()
        .take_while(|statement| {
            matches!(
                &statement.kind,
                StatementKind::Set { .. } | StatementKind::ProjectedSet { .. }
            )
        })
        .count()
}
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
            identity,
            settings: &statements[..count],
            syntax,
            first_non_setting: statements.get(count).map(|statement| statement.header_span),
        }))
    }
}

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
    first_non_setting: Option<Span>,
}
impl<'a> InitialSettingPrefix<'a> {
    pub fn tree(&self) -> &'a SemanticTree {
        self.archive.tree()
    }
    pub fn identity(&self) -> ProcedureIdentity {
        self.identity
    }
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
    pub fn with_initial_setting_prefix<T>(
        &self,
        identity: ProcedureIdentity,
        consume: impl FnOnce(InitialSettingPrefix<'_>) -> T,
    ) -> Result<T, String> {
        if self.body_query_host().is_none() {
            return Err(
                "setting prefix needs the original retained compiler BodySyntax query owner".into(),
            );
        }
        let tree = self.tree();
        let mut selected = None;
        for (ordinal, occurrence) in self.occurrences().iter().enumerate() {
            let member = tree
                .member(occurrence.member)
                .ok_or("prefix body member unavailable")?;
            if !matches!(member.kind, MemberKind::Proc | MemberKind::Verb) {
                continue;
            }
            let issued = ProcedureIdentity {
                owner: tree
                    .type_node(member.owner)
                    .ok_or("prefix member owner unavailable")?
                    .path,
                name: member.name,
                verb: member.kind == MemberKind::Verb,
                occurrence: tree
                    .member_occurrence(occurrence.member)
                    .ok_or("prefix source occurrence unavailable")?,
            };
            if issued == identity && selected.replace(ordinal).is_some() {
                return Err("prefix callable identity is ambiguous in issued roster".into());
            }
        }
        let body = self
            .parse(selected.ok_or("source callable has no issued primary body for prefix proof")?)
            .map_err(|error| error.message)?;
        if !body.belongs_to(self) || !body.statement_body().syntax_complete() {
            return Err("prefix body is foreign or has incomplete primary syntax".into());
        }
        let syntax = body.statement_body();
        let count = prefix_len(syntax);
        let statements = &syntax.parsed().statements;
        Ok(consume(InitialSettingPrefix {
            archive: self,
            identity,
            settings: &statements[..count],
            first_non_setting: statements.get(count).map(|statement| statement.header_span),
        }))
    }
}

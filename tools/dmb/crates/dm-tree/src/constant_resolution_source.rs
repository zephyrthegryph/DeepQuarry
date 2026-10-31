//! Private receipt from the SAME scalar selector. Source issuers may inspect
//! it, but callers cannot construct a member/expression/scope authority tuple.
use super::*;
#[derive(Clone,Copy)]
pub(crate) struct SelectedScalarExpression<'source>{pub(super) tree:&'source SemanticTree,pub(super) query:ScalarQuery,pub(super) member:MemberId,pub(super) source_member:MemberId,pub(super) expression:&'source dm_ir::SymbolicExpression,pub(super) scope:dm_ir::TypeId}
impl<'source> SelectedScalarExpression<'source>{
 pub(crate) fn tree(&self)->&'source SemanticTree{self.tree}
 pub(crate) fn member(&self)->MemberId{self.member}
 pub(crate) fn source_member(&self)->MemberId{self.source_member}
 pub(crate) fn expression(&self)->&'source dm_ir::SymbolicExpression{self.expression}
 pub(crate) fn scope(&self)->dm_ir::TypeId{self.scope}
 pub(crate) fn query(&self)->ScalarQuery{self.query}
}

#[derive(Clone,Copy)]
pub(super) struct OriginalScalarPass<'a>{pub(super) context:&'a crate::frontend::OriginalDeclarationExpressionContext<'a>,pub(super) admission:&'a dm_syntax::SettingAdmission<'a>}
impl OriginalScalarPass<'_>{
 pub(super) fn checkpoint(&self)->Result<(),crate::frontend::BodySyntaxFailure>{let pending=self.admission.checkpoint();if let Some(actual)=self.admission.take_operational_error(){return Err(crate::frontend::BodySyntaxFailure::Operational(actual))}pending.map_err(crate::frontend::BodySyntaxFailure::Operational)}
}
pub(super) enum Selected<'source>{Outcome(ScalarOutcome),Expression(SelectedScalarExpression<'source>)}
pub(super) enum OriginalOperand<'source>{Unavailable,RejectedSyntax,Root(crate::frontend::OriginalInitializerExpression<'source>)}

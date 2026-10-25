//! A dot read or write on a receiver of known static type must name a variable
//! that type has, as DreamMaker reports `a.b: undefined var`.
use super::*;
impl Compiler<'_> {
    /// Rejects `object.selector` when `object` has a statically known type that
    /// declares no such variable. Colon access, `global.x`, `x.vars`, built-in
    /// variable spellings (the native inventory is partial) and receivers whose
    /// type cannot be inferred stay accepted.
    pub(super) fn validate_member_var(
        &self,
        expr: &Expr,
        statement: &str,
    ) -> Result<(), LowerError> {
        let ExprKind::Member {
            object,
            selector,
            via_colon: false,
        } = &expr.kind
        else {
            return Ok(());
        };
        let Some(lookup) = self.lookup else {
            return Ok(());
        };
        if dm_syntax::is_global_receiver(object)
            || selector == "vars"
            || dm_ir::builtin_names::is_builtin_var(selector)
            || !assignments::is_reference_chain(object)
        {
            return Ok(());
        }
        let Some(owner) = self.inferred_expression_type(object)? else {
            return Ok(());
        };
        if self.member_global(&owner, selector)?.is_some() {
            return Ok(());
        }
        let present = self.semantic(lookup.presence(dm_ir::ResolveQuery::HasMemberVar {
            owner: SymbolId::of(&owner),
            name: SymbolId::of(selector),
        }))?;
        if present {
            return Ok(());
        }
        let mut failure = error(
            statement,
            &crate::lower_diagnostics::undefined_member_message(statement, selector),
        );
        failure.kind = LowerErrorKind::SourceError;
        Err(failure)
    }
}

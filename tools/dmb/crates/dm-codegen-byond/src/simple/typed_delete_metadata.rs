//! Exact current declaration evidence for nonlocal storage clearing.
use super::*;
impl Compiler<'_> {
    pub(super) fn delete_slot_writable(
        &self,
        reference: SymRef,
        statement: &str,
    ) -> Result<bool, LowerError> {
        let lookup = self
            .lookup
            .ok_or_else(|| error(statement, "deletion slot issuer is unavailable"))?;
        // slot() captured this exact current resolver-issued tuple while selecting
        // the operand. Drop the borrow before further semantic replay.
        let slot = lookup
            .slots
            .borrow()
            .get(&reference)
            .cloned()
            .ok_or_else(|| error(statement, "deletion storage tuple was not issued"))?;
        if reference != SymRef::VariableSlot(slot.symbol) {
            return Err(error(
                statement,
                "deletion storage identity differs from issued tuple",
            ));
        }
        self.delete_declared_writable(
            dm_ir::ResolveQuery::Var {
                owner: slot.owner,
                name: slot.name,
            },
            statement,
        )
    }

    pub(super) fn delete_declared_writable(
        &self,
        query: dm_ir::ResolveQuery,
        statement: &str,
    ) -> Result<bool, LowerError> {
        let lookup = self.lookup.ok_or_else(|| {
            error(
                statement,
                "nonlocal deletion requires current declaration metadata",
            )
        })?;
        match self.semantic(lookup.answer(query))? {
            dm_ir::ResolvedMeaning::Member { data, .. } if data.inherited_opaque.is_none() => {
                Ok(data.flags & 2 == 0)
            }
            _ => self.semantic(Err(error(
                statement,
                "nonlocal deletion writable metadata is incomplete",
            ))),
        }
    }
    pub(super) fn delete_member_writable(
        &self,
        object: &Expr,
        selector: &str,
        statement: &str,
    ) -> Result<bool, LowerError> {
        // Native intrinsic property type is readonly even for dynamic receivers;
        // global.type is an ordinary authored mutable global and is distinct.
        let global = dm_syntax::is_global_receiver(object);
        if (!global && selector == "type") || (global && selector == "vars") {
            return Ok(false);
        }
        let owner = if global {
            "/".to_owned()
        } else {
            self.inferred_expression_type(object)?.ok_or_else(|| {
                error(
                    statement,
                    "dynamic deletion receiver lacks writable declaration metadata",
                )
            })?
        };
        self.delete_declared_writable(
            dm_ir::ResolveQuery::Var {
                owner: SymbolId::of(&owner),
                name: SymbolId::of(selector),
            },
            statement,
        )
    }
}

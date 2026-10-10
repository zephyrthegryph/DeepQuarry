//! Static dot and explicit dynamic colon have distinct recorded name authority.
use super::*;
impl Compiler<'_> {
    pub(super) fn member_call_selector(
        &mut self,
        object: &Expr,
        selector: &str,
        via_colon: bool,
        statement: &str,
    ) -> Result<VariableWord, LowerError> {
        if via_colon {
            if let Some(lookup) = self.lookup {
                let available = self.semantic(lookup.presence(
                    dm_ir::ResolveQuery::MemberCallableName(SymbolId::of(selector)),
                ))?;
                if !available {
                    return Err(self.undefined_member_call(object, selector, ":", statement));
                }
            }
            return Ok(VariableWord::DynamicProc(
                self.intern_string(&selector.replace('_', " ")),
            ));
        }
        // The actual current formal frame certifies untyped ordinary-dot calls
        // as invalid, independent of other owners declaring the same name.
        // Standalone compatibility APIs without semantic authority retain their
        // existing contract. Explicit call(receiver,name) remains dynamic.
        if self.lookup.is_some() {
            if let ExprKind::Ident(name) = &object.kind {
                if self.bindings.parameters.iter().any(|formal| formal == name)
                    && !self.bindings.parameter_types.contains_key(name)
                {
                    return Err(self.undefined_member_call(object, selector, ".", statement));
                }
            }
        }
        Ok(self
            .expression_member_proc(object, selector)?
            .map(member_proc_selector)
            .unwrap_or_else(|| {
                VariableWord::DynamicProc(self.intern_string(&selector.replace('_', " ")))
            }))
    }
    pub(super) fn safe_member_call_selector(
        &mut self,
        object: &Expr,
        selector: &str,
        statement: &str,
    ) -> Result<VariableWord, LowerError> {
        if self.inferred_expression_type(object)?.is_none() {
            if let Some(lookup) = self.lookup {
                if !self.semantic(lookup.presence(dm_ir::ResolveQuery::MemberCallableName(
                    SymbolId::of(selector),
                )))? {
                    // Native safe-dot diagnostics use the ordinary dot spelling.
                    return Err(self.undefined_member_call(object, selector, ".", statement));
                }
            }
        }
        Ok(self
            .expression_member_proc(object, selector)?
            .map(member_proc_selector)
            .unwrap_or_else(|| {
                VariableWord::DynamicProc(self.intern_string(&selector.replace('_', " ")))
            }))
    }
    fn undefined_member_call(
        &self,
        object: &Expr,
        selector: &str,
        separator: &str,
        statement: &str,
    ) -> LowerError {
        let reason = match &object.kind {
            ExprKind::Ident(name) => format!("{name}{separator}{selector}: undefined proc"),
            _ => format!("{selector}: undefined proc"),
        };
        let mut failure = error(statement, &reason);
        failure.kind = LowerErrorKind::SourceError;
        failure
    }
}

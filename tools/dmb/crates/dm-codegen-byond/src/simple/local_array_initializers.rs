//! Shared local sized-array continuation, following authenticated native order.
use super::*;

impl Compiler<'_> {
    pub(in crate::simple) fn local_declaration_initializer(
        &mut self,
        value: &Expr,
        declaration: &str,
        statement: &str,
    ) -> Result<(), LowerError> {
        let mut selected = value;
        while let ExprKind::Group(inner) = &selected.kind {
            selected = inner;
        }
        if matches!(&selected.kind, ExprKind::Literal(raw) if raw == "null") {
            self.emit(opcode::GET_VAR, vec![Word::Variable(VariableWord::Null)]);
            Ok(())
        } else {
            self.local_initializer(value, declaration, statement)
        }
    }

    pub(in crate::simple) fn local_array_declaration(
        &mut self,
        dimensions: &[&str],
        slot: u32,
        statement: &str,
        initializer: Option<impl FnOnce(&mut Self) -> Result<(), LowerError>>,
    ) -> Result<(), LowerError> {
        // Sized declarations issue an actual list receiver, whether or not the
        // authored spelling includes /list. Both typed and compatibility paths
        // share this producer; later member validation still checks the resolver.
        let name = self
            .locals
            .get(slot as usize)
            .ok_or_else(|| error(statement, "local array slot is unavailable"))?
            .clone();
        self.local_types.insert(name, "/list".into());
        let explicit = initializer.is_some();
        let source_ordinal = self.debug_current;
        if let Some(initializer) = initializer {
            initializer(self)?;
            self.emit(
                opcode::SET_VAR,
                vec![Word::Variable(VariableWord::Local(slot))],
            );
        }
        self.local_array(dimensions, statement)?;
        if !explicit {
            self.emit(
                opcode::SET_VAR,
                vec![Word::Variable(VariableWord::Local(slot))],
            );
        }
        if explicit {
            let name = self
                .locals
                .get(slot as usize)
                .ok_or_else(|| error(statement, "local warning slot is unavailable"))?;
            self.result.warnings.push(ProcedureWarning {
                code: dm_ir::WarningCode::ListDoubleInit,
                name: Some(SymbolId::of(name)),
                source_ordinal,
            });
        }
        // Native explicit declarations leave the allocation unassigned; no Pop.
        Ok(())
    }
}

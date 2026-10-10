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
        let explicit = initializer.is_some();
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
        // Native explicit declarations leave the allocation unassigned; no Pop.
        Ok(())
    }
}

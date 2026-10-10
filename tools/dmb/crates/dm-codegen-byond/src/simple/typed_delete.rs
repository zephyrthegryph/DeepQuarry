//! Authored deletion retains the loaded value while clearing mutable storage.
use super::*;

impl Compiler<'_> {
    pub(super) fn typed_delete(
        &mut self,
        target: &Expr,
        statement: &str,
    ) -> Result<bool, LowerError> {
        let mut selected = target;
        while let ExprKind::Group(inner) = &selected.kind {
            selected = inner;
        }
        // Resolve lexical storage before recognizing builtin src, so an authored
        // parameter/local shadow retains its ordinary mutable binding semantics.
        let variable = if let ExprKind::Ident(name) = &selected.kind {
            if self.local_slots.contains_key(name)
                || self
                    .bindings
                    .parameters
                    .iter()
                    .any(|parameter| parameter == name)
                || name == "src"
            {
                Some(self.variable_for_node(selected, name, statement)?)
            } else {
                None
            }
        } else {
            None
        };
        self.expression(target, statement)?;
        let ends_body = matches!(variable, Some(VariableWord::Src));
        match variable {
            Some(variable @ (VariableWord::Local(_) | VariableWord::Src)) => {
                self.emit(opcode::PUSH_VAL, vec![Word::Value(ValueWord::Null)]);
                self.emit(opcode::SET_VAR, vec![Word::Variable(variable)]);
            }
            Some(VariableWord::Arg(slot)) if !self.bindings.readonly_parameters.contains(&slot) => {
                self.emit(opcode::PUSH_VAL, vec![Word::Value(ValueWord::Null)]);
                self.emit(
                    opcode::SET_VAR,
                    vec![Word::Variable(VariableWord::Arg(slot))],
                );
            }
            _ => {}
        }
        self.emit(0x0c, vec![]);
        if ends_body {
            self.emit(opcode::END, vec![]);
        }
        Ok(ends_body)
    }
}

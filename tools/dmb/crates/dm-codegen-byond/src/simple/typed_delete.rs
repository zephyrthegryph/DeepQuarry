//! Authored deletion retains the loaded value while clearing mutable storage.
use super::*;
#[path = "typed_delete_metadata.rs"]
mod metadata;

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
            Some(self.variable_for_node(selected, name, statement)?)
        } else {
            None
        };
        let clear_expression = match &selected.kind {
            ExprKind::Index { .. } | ExprKind::SafeIndex { .. } => true,
            ExprKind::Member {
                object, selector, ..
            }
            | ExprKind::SafeMember {
                object, selector, ..
            } => self.delete_member_writable(object, selector, statement)?,
            ExprKind::Ident(name) => match &variable {
                Some(VariableWord::Global(SymRef::Var { owner, name })) => self
                    .delete_declared_writable(
                        dm_ir::ResolveQuery::Var {
                            owner: *owner,
                            name: *name,
                        },
                        statement,
                    )?,
                Some(VariableWord::Global(reference @ SymRef::VariableSlot(_))) => {
                    self.delete_slot_writable(*reference, statement)?
                }
                Some(VariableWord::Global(reference))
                    if !matches!(reference, SymRef::BuiltinGlobalVars) =>
                {
                    return Err(error(
                        statement,
                        "deletion storage lacks exact declaration metadata",
                    ));
                }
                Some(VariableWord::SetCache(_, _)) => self.delete_declared_writable(
                    dm_ir::ResolveQuery::Var {
                        owner: SymbolId::of(
                            self.bindings.current_type_path.as_deref().unwrap_or("/"),
                        ),
                        name: SymbolId::of(name),
                    },
                    statement,
                )?,
                _ => false,
            },
            _ => false,
        };
        self.expression(target, statement)?;
        let ends_body = matches!(variable, Some(VariableWord::Src));
        match variable {
            Some(
                variable @ (VariableWord::Local(_)
                | VariableWord::Src
                | VariableWord::Usr
                | VariableWord::Args),
            ) => {
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
        if clear_expression {
            // The old deletion value remains below the new null. The shared
            // assignment producer repeats receiver/key evaluation and guards.
            let mut null = selected.clone();
            null.kind = ExprKind::Literal("null".into());
            self.assign_expr(selected, "=", &null, statement)?;
        }
        self.emit(0x0c, vec![]);
        if ends_body {
            self.emit(opcode::END, vec![]);
        }
        Ok(ends_body)
    }
}

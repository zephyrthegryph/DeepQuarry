//! Shared local sized-array continuation, following authenticated native order.
use super::*;

impl Compiler<'_> {
    pub(in crate::simple) fn primary_local_name<'s>(
        &self,
        statement: &'s dm_syntax::Statement,
    ) -> Option<&'s str> {
        let fact = self
            .local_variables?
            .in_span(statement.header_span)
            .ok()?
            .first()?;
        if fact.source_modifiers & 1 != 0 {
            return None;
        }
        let start = fact.name.start.checked_sub(statement.header_span.start)?;
        let end = fact.name.end.checked_sub(statement.header_span.start)?;
        statement.raw_header.get(start..end)
    }
    /// Consume every nonempty original dimension root, including mixed empty
    /// suffixes. Only explicit compatibility entry points may parse old text.
    pub(in crate::simple) fn primary_or_legacy_array(
        &mut self,
        header: dm_syntax::Span,
        slot: u32,
        declaration: &str,
        value: Option<&Expr>,
        statement: &str,
    ) -> Result<bool, LowerError> {
        let ledger = self.local_variables;
        if let Some(ledger) = ledger {
            let facts = match ledger.in_span(header) {
                Ok(facts) => facts,
                Err(_) if !declaration.contains('[') => return Ok(false),
                Err(_) => {
                    return Err(error(
                        statement,
                        "native local dimension receipt unavailable",
                    ))
                }
            };
            let fact = facts.first();
            if facts.len() > 1 {
                return Err(error(
                    statement,
                    "native local declaration receipt ambiguous",
                ));
            }
            if let Some(array) = fact
                .and_then(|fact| fact.array_syntax.as_ref())
                .filter(|a| !a.root.dimensions.is_empty())
            {
                self.local_array_declaration_primary(
                    &array.root,
                    slot,
                    statement,
                    value.map(|value| {
                        move |compiler: &mut Self| {
                            compiler.local_declaration_initializer(value, declaration, statement)
                        }
                    }),
                )?;
                return Ok(true);
            }
            if fact.is_none() && declaration.contains('[') {
                return Err(error(
                    statement,
                    "native local array has no original declaration receipt",
                ));
            }
            return Ok(false);
        }
        if let Some(dimensions) = local_array_dimensions(declaration) {
            self.local_array_declaration(
                &dimensions,
                slot,
                statement,
                value.map(|value| {
                    move |compiler: &mut Self| {
                        compiler.local_declaration_initializer(value, declaration, statement)
                    }
                }),
            )?;
            return Ok(true);
        }
        Ok(false)
    }
    pub(in crate::simple) fn register_local_declaration_type(
        &mut self,
        name: &str,
        declaration: &str,
    ) {
        if let Some(path) = dm_syntax::local_type_path(declaration) {
            self.local_types
                .insert(name.into(), runtime_declaration_path(path));
        } else if declaration.trim_end().ends_with("[]") {
            self.local_types.insert(name.into(), "/list".into());
        }
    }

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
        self.local_array_declaration_with(slot, statement, initializer, |compiler| {
            compiler.local_array(dimensions, statement)
        })
    }
    pub(in crate::simple) fn local_array_declaration_primary(
        &mut self,
        dimensions: &dm_syntax::ImplicitListInitializer,
        slot: u32,
        statement: &str,
        initializer: Option<impl FnOnce(&mut Self) -> Result<(), LowerError>>,
    ) -> Result<(), LowerError> {
        self.local_array_declaration_with(slot, statement, initializer, |compiler| {
            compiler.local_array_primary(&dimensions.dimensions, statement)
        })
    }
    fn local_array_declaration_with(
        &mut self,
        slot: u32,
        statement: &str,
        initializer: Option<impl FnOnce(&mut Self) -> Result<(), LowerError>>,
        lower_dimensions: impl FnOnce(&mut Self) -> Result<(), LowerError>,
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
        lower_dimensions(self)?;
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

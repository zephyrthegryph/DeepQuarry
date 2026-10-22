//! `const` variables as compile-time constants. DreamMaker keeps a bare read of `var/const/X` as a variable read, but
//! folds it wherever the surrounding expression is evaluated at compile time (`X + 2`, `X * 2`, a switch case label).
use super::*;
use dm_ir::{ResolveQuery, ResolvedMeaning, SemanticValue};

impl Compiler<'_> {
    /// The declared type of the existing variable `name` names (a typed argument, a typed local, or a field or global of
    /// the current type), or None when it has none or the catalog cannot say. Never records a resolver failure.
    pub(super) fn declared_variable_type(&self, name: &str) -> Option<String> {
        if let Some(path) = self.local_types.get(name) {
            return Some(path.trim_start_matches('/').to_string());
        }
        if let Some(path) = self.bindings.parameter_types.get(name) {
            return Some(path.trim_start_matches('/').to_string());
        }
        if self.local_slots.contains_key(name) || self.bindings.parameters.iter().any(|formal| formal == name) {
            return None;
        }
        let lookup = self.lookup?;
        let meaning = self.variable_meaning(name, "").ok()?;
        let query = match meaning {
            dm_ir::SelectedMeaning::InstanceField {
                owner: Some(owner),
                name,
            } => ResolveQuery::DeclaredVarType { owner, name },
            dm_ir::SelectedMeaning::SharedStorage(symbol) => {
                let slots = lookup.slots.borrow();
                let slot = slots.get(&symbol)?;
                ResolveQuery::DeclaredVarType {
                    owner: slot.owner,
                    name: slot.name,
                }
            }
            _ => return None,
        };
        let declared = match lookup.resolver.resolve(query) {
            ResolvedMeaning::DeclaredType(declared) => declared?,
            ResolvedMeaning::Member { data, .. } => data.declared_type?,
            _ => return None,
        };
        let text = lookup.text(query, declared).ok()?;
        let text = text.trim_start_matches('/');
        (!text.is_empty()).then(|| text.to_string())
    }

    /// Whether the shared-storage variable is a `const` with a scalar value.
    pub(super) fn is_constant_variable(&self, symbol: SymRef) -> bool {
        self.const_literal(symbol, dm_syntax::Span::default()).is_some()
    }

    /// `Type::name` for a variable whose default is a list: DreamMaker builds that list from the default expression where it
    /// is written (`NewList`, `NewAssocList`) instead of reading `initial()`, which answers null for a list variable.
    pub(super) fn static_list_default(&self, path: &str, name: &str) -> Option<Expr> {
        let lookup = self.lookup?;
        let query = ResolveQuery::Var {
            owner: dm_ir::SymbolId::of(path),
            name: dm_ir::SymbolId::of(name),
        };
        let data = match lookup.resolver.resolve(query) {
            ResolvedMeaning::Member { data, .. } => data,
            _ => return None,
        };
        let initializer = data.initializer.as_ref().or(data.declared_initializer.as_ref())?;
        let text = initializer.source_text(lookup.symbols)?;
        let parsed = dm_syntax::parse_expression(&text);
        if !parsed.diagnostics.is_empty() {
            return None;
        }
        let expr = parsed.expr?;
        match &expr.kind {
            ExprKind::Call { callee, .. } if matches!(&callee.kind, ExprKind::Ident(callee) if callee == "list") => Some(expr),
            _ => None,
        }
    }

    /// The value of the `const` variable a shared-storage reference names, as a literal expression. None for anything
    /// that is not a constant with a scalar value (including every local and argument).
    fn const_literal(&self, symbol: SymRef, span: dm_syntax::Span) -> Option<Expr> {
        let lookup = self.lookup?;
        let (owner, name) = {
            let slots = lookup.slots.borrow();
            let slot = slots.get(&symbol)?;
            (slot.owner, slot.name)
        };
        self.constant_literal_of(owner, name, span)
    }

    /// The literal for the scalar constant `owner`'s variable `name` holds, if it is a `const`.
    fn constant_literal_of(&self, owner: dm_ir::SymbolId, name: dm_ir::SymbolId, span: dm_syntax::Span) -> Option<Expr> {
        let lookup = self.lookup?;
        let answer = lookup.resolver.resolve(ResolveQuery::Constant { owner, name });
        let value = match answer {
            ResolvedMeaning::Value(value) => value,
            ResolvedMeaning::Member { data, .. } => data.resolved_constant.clone()?,
            _ => return None,
        };
        let text = match value {
            SemanticValue::NumberBits(bits) => {
                let number = f32::from_bits(bits);
                if !number.is_finite() {
                    return None;
                }
                format!("{number}")
            }
            SemanticValue::Text(bytes) => {
                let text = std::str::from_utf8(&bytes).ok()?;
                let mut quoted = String::with_capacity(text.len() + 2);
                quoted.push('"');
                for c in text.chars() {
                    match c {
                        '\\' | '"' | '[' | ']' => {
                            quoted.push('\\');
                            quoted.push(c);
                        }
                        '\n' => quoted.push_str("\\n"),
                        '\t' => quoted.push_str("\\t"),
                        '\r' => return None,
                        c => quoted.push(c),
                    }
                }
                quoted.push('"');
                quoted
            }
            _ => return None,
        };
        Some(Expr {
            kind: ExprKind::Literal(text),
            span,
        })
    }

    /// The constant a bare identifier or `receiver.name` member stands for, when it names a `const` variable.
    fn const_reference(&self, expr: &Expr) -> Option<Expr> {
        match &expr.kind {
            ExprKind::Ident(name) => {
                // Asked by name, without selecting the variable: a read of a variable that is not a constant must not
                // allocate its storage ahead of the lowering that reads it (global initializers follow that order).
                if self.local_slots.contains_key(name.as_str())
                    || self.bindings.parameters.iter().any(|formal| formal == name)
                {
                    return None;
                }
                let lookup = self.lookup?;
                if matches!(lookup.procedure_static(self.bindings.procedure_identity, name), Ok(Some(_))) {
                    return None;
                }
                let owner = self.bindings.current_type_path.as_deref().unwrap_or("/");
                self.constant_literal_of(dm_ir::SymbolId::of(owner), dm_ir::SymbolId::of(name), expr.span)
            }
            ExprKind::Group(inner) => self.const_reference(inner),
            ExprKind::Member {
                object,
                selector,
                via_colon: false,
            } if matches!(&object.kind, ExprKind::Ident(_) | ExprKind::Member { .. }) => {
                let owner = self.inferred_expression_type(object).ok()??;
                self.constant_literal_of(dm_ir::SymbolId::of(&owner), dm_ir::SymbolId::of(selector), expr.span)
            }
            _ => None,
        }
    }

    /// The literal a bare reference to a `const` variable stands for.
    pub(super) fn const_reference_literal(&self, expr: &Expr) -> Option<Expr> {
        self.const_reference(expr)
    }

    /// The truth value of a bare reference to a `const` variable.
    pub(super) fn const_reference_truth(&self, expr: &Expr) -> Option<bool> {
        let literal = self.const_reference(expr)?;
        super::expression::constant_truth(&literal)
    }

    /// `expr` with the `const` variables inside its operators replaced by their values, or None when there are none.
    /// Only operators are entered: a call's arguments, indexes and members are not constant contexts.
    pub(super) fn substitute_constants(&self, expr: &Expr) -> Option<Expr> {
        match &expr.kind {
            ExprKind::Ident(_) | ExprKind::Member { .. } => self.const_reference(expr),
            ExprKind::Group(inner) => self.substitute_constants(inner).map(|inner| Expr {
                kind: ExprKind::Group(Box::new(inner)),
                span: expr.span,
            }),
            ExprKind::Unary { op, value } if matches!(op.as_str(), "-" | "!" | "~") => {
                self.substitute_constants(value).map(|value| Expr {
                    kind: ExprKind::Unary {
                        op: op.clone(),
                        value: Box::new(value),
                    },
                    span: expr.span,
                })
            }
            ExprKind::Binary { op, lhs, rhs }
                if matches!(
                    op.as_str(),
                    "+" | "-" | "*" | "/" | "%" | "**" | "&" | "|" | "^" | "<<" | ">>" | "&&" | "||"
                ) =>
            {
                let (l, r) = (self.substitute_constants(lhs), self.substitute_constants(rhs));
                if l.is_none() && r.is_none() {
                    return None;
                }
                Some(Expr {
                    kind: ExprKind::Binary {
                        op: op.clone(),
                        lhs: Box::new(l.unwrap_or_else(|| lhs.as_ref().clone())),
                        rhs: Box::new(r.unwrap_or_else(|| rhs.as_ref().clone())),
                    },
                    span: expr.span,
                })
            }
            _ => None,
        }
    }

    /// The compile-time value of a switch case label or other fully constant context: a constant variable itself, or an
    /// operator expression over them.
    pub(super) fn constant_context_expression(&self, expr: &Expr) -> Option<Expr> {
        self.substitute_constants(expr)
    }
}

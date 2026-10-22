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

    /// The value of the `const` variable a shared-storage reference names, as a literal expression. None for anything
    /// that is not a constant with a scalar value (including every local and argument).
    fn const_literal(&self, symbol: SymRef, span: dm_syntax::Span) -> Option<Expr> {
        let lookup = self.lookup?;
        let (owner, name) = {
            let slots = lookup.slots.borrow();
            let slot = slots.get(&symbol)?;
            (slot.owner, slot.name)
        };
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
                let meaning = self.variable_meaning(name, "").ok()?;
                match meaning {
                    dm_ir::SelectedMeaning::SharedStorage(symbol) => self.const_literal(symbol, expr.span),
                    _ => None,
                }
            }
            ExprKind::Group(inner) => self.const_reference(inner),
            ExprKind::Member {
                object,
                selector,
                via_colon: false,
            } if matches!(&object.kind, ExprKind::Ident(_) | ExprKind::Member { .. }) => {
                let owner = self.inferred_expression_type(object).ok()??;
                let symbol = self.member_global(&owner, selector).ok()??;
                self.const_literal(symbol, expr.span)
            }
            _ => None,
        }
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

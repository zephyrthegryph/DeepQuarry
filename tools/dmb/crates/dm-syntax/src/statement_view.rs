//! Immutable executable views over the authored Statement/Expr tree.
use crate::{Diagnostic, Span, Statement, StatementKind};
use std::collections::BTreeMap;

#[derive(Default)]
pub struct StatementMask {
    hidden: BTreeMap<(usize, usize), Span>,
}
impl StatementMask {
    /// Capture exclusions without changing the authored AST. A hidden parent
    /// hides its complete source range and all children.
    pub fn from_predicate(
        statements: &[Statement],
        mut hide: impl FnMut(&Statement) -> bool,
    ) -> Self {
        let mut result = Self::default();
        let mut pending: Vec<_> = statements.iter().rev().collect();
        while let Some(statement) = pending.pop() {
            if hide(statement) {
                result.hidden.insert(
                    (statement.header_span.start, statement.header_span.end),
                    statement.span,
                );
                continue;
            }
            match &statement.kind {
                StatementKind::If {
                    then_branch,
                    else_branch,
                    ..
                } => {
                    pending.extend(else_branch.iter().rev());
                    pending.extend(then_branch.iter().rev());
                }
                StatementKind::While { body, .. }
                | StatementKind::DoWhile { body, .. }
                | StatementKind::Spawn { body, .. }
                | StatementKind::For { body, .. }
                | StatementKind::Label { body, .. } => pending.extend(body.iter().rev()),
                StatementKind::Switch {
                    cases, else_branch, ..
                } => {
                    pending.extend(else_branch.iter().rev());
                    for case in cases.iter().rev() {
                        pending.extend(case.body.iter().rev());
                    }
                }
                StatementKind::Try {
                    body, catch_body, ..
                } => {
                    pending.extend(catch_body.iter().rev());
                    pending.extend(body.iter().rev());
                }
                _ => (),
            }
        }
        result
    }
    pub fn visible(&self, statement: &Statement) -> bool {
        !self
            .hidden
            .contains_key(&(statement.header_span.start, statement.header_span.end))
    }
    pub fn hides_diagnostic(&self, diagnostic: &Diagnostic) -> bool {
        self.hidden
            .values()
            .any(|span| span.start <= diagnostic.span.start && diagnostic.span.end <= span.end)
    }
    pub fn len(&self) -> usize {
        self.hidden.len()
    }
    pub fn is_empty(&self) -> bool {
        self.hidden.is_empty()
    }
}

#[derive(Clone, Copy)]
pub struct StatementView<'a> {
    statements: &'a [Statement],
    mask: Option<&'a StatementMask>,
}
impl<'a> StatementView<'a> {
    pub fn all(statements: &'a [Statement]) -> Self {
        Self {
            statements,
            mask: None,
        }
    }
    pub fn masked(statements: &'a [Statement], mask: &'a StatementMask) -> Self {
        Self {
            statements,
            mask: Some(mask),
        }
    }
    pub fn statements(self) -> &'a [Statement] {
        self.statements
    }
    pub fn mask(self) -> Option<&'a StatementMask> {
        self.mask
    }
    pub fn child(self, statements: &'a [Statement]) -> Self {
        Self {
            statements,
            mask: self.mask,
        }
    }
    pub fn iter(self) -> impl Iterator<Item = &'a Statement> {
        self.statements
            .iter()
            .filter(move |statement| self.mask.is_none_or(|mask| mask.visible(statement)))
    }
    pub fn first(self) -> Option<&'a Statement> {
        self.iter().next()
    }
    pub fn is_empty(self) -> bool {
        self.first().is_none()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn masked_view_preserves_authored_storage_and_probes_visible_children() {
        let source = crate::parse(
            "/proc/p()\n    if(1)\n        set waitfor = 0\n    else\n        return 7\n",
        );
        let body = crate::parse_body_items(&source.items[0].children);
        assert!(body.diagnostics.is_empty());
        let mask = StatementMask::from_predicate(&body.statements, |statement| {
            matches!(statement.kind, StatementKind::Set { .. })
        });
        let view = StatementView::masked(&body.statements, &mask);
        assert!(std::ptr::eq(view.first().unwrap(), &body.statements[0]));
        let StatementKind::If {
            then_branch,
            else_branch,
            ..
        } = &view.first().unwrap().kind
        else {
            unreachable!()
        };
        assert!(view.child(then_branch).is_empty());
        assert!(!then_branch.is_empty());
        assert!(!view.child(else_branch).is_empty());
        assert_eq!(mask.len(), 1);
    }
}

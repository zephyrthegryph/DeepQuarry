//! Explicit current-source coordinates over SAME canonical original setting AST.
use crate::{Expr, SettingExpression, Span};
#[derive(Clone, Copy)]
pub struct ProjectedExprView<'a> {
    expression: &'a Expr,
    root: &'a SettingExpression,
}
impl<'a> ProjectedExprView<'a> {
    pub(crate) fn new(root: &'a SettingExpression, expression: &'a Expr) -> Self {
        Self { expression, root }
    }
    /// Explicitly ORIGINAL coordinates; never a current-source Expr substitute.
    pub fn original(self) -> &'a Expr {
        self.expression
    }
    pub fn current_span(self) -> Span {
        self.root
            .current_span_of(self.expression)
            .expect("issued setting child remains inside checked source projection")
    }
    pub fn current_span_of(self, original: &Expr) -> Option<Span> {
        self.root.current_span_of(original)
    }
    pub fn current_offset(self) -> usize {
        self.root.current_offset()
    }
}

#[derive(Clone, Copy)]
pub enum SettingValueView<'a> {
    Owned(&'a Expr),
    Projected(&'a SettingExpression),
}
impl<'a> SettingValueView<'a> {
    pub fn original(self) -> &'a Expr {
        match self {
            Self::Owned(e) => e,
            Self::Projected(e) => e.original_expression(),
        }
    }
    pub fn current_span(self) -> Span {
        match self {
            Self::Owned(e) => e.span,
            Self::Projected(e) => e.current_span(),
        }
    }
    pub fn is_projected(self) -> bool {
        matches!(self, Self::Projected(_))
    }
}
pub struct SettingView<'a> {
    pub attribute: &'a str,
    pub relation: &'a str,
    pub value: SettingValueView<'a>,
}
impl crate::Statement {
    pub fn setting(&self) -> Option<SettingView<'_>> {
        match &self.kind {
            crate::StatementKind::Set {
                attribute,
                relation,
                value,
            } => Some(SettingView {
                attribute,
                relation,
                value: SettingValueView::Owned(value),
            }),
            crate::StatementKind::ProjectedSet {
                attribute,
                relation,
                value,
            } => Some(SettingView {
                attribute,
                relation,
                value: SettingValueView::Projected(value),
            }),
            _ => None,
        }
    }
}

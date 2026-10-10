//! Retain only exact source-local syntax issued by the common expression parser.
//! An evaluator may supply arbitrary coordinates; those never gain authority here.
use std::sync::Arc;

#[derive(Clone)]
pub(super) struct SharedExpression {
    source: Arc<str>,
    expression: Arc<dm_syntax::Expr>,
}
impl SharedExpression {
    pub(super) fn capture(source: String, supplied: &Arc<dm_syntax::Expr>) -> Option<Self> {
        let parsed = dm_syntax::parse_expression(&source);
        if !parsed.diagnostics.is_empty() {
            return None;
        }
        let expression = parsed.expr?;
        // Full structural comparison includes every nested expression span.
        if expression != **supplied {
            return None;
        }
        Some(Self {
            source: source.into(),
            expression: Arc::clone(supplied),
        })
    }
    pub(super) fn bind(&self, current_source: &str) -> Option<Arc<dm_syntax::Expr>> {
        (self.source.as_ref() == current_source).then(|| Arc::clone(&self.expression))
    }
    pub(super) fn retained_parts(&self) -> (&Arc<str>, &Arc<dm_syntax::Expr>) {
        (&self.source, &self.expression)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn exact_current_spelling_shares_relative_syntax_and_changes_decline() {
        let source = "list(1, list(2, 3))";
        let expression = Arc::new(dm_syntax::parse_expression(source).expr.unwrap());
        let leaf = SharedExpression::capture(source.into(), &expression).unwrap();
        assert!(Arc::ptr_eq(&expression, &leaf.bind(source).unwrap()));
        assert!(leaf.bind("list(1, list(2, 4))").is_none());
        assert!(leaf.bind(" list(1, list(2, 3))").is_none());
    }
    #[test]
    fn changed_nested_coordinate_cannot_be_certified() {
        let source = "list(1, list(2, 3))";
        let mut expression = dm_syntax::parse_expression(source).expr.unwrap();
        if let dm_syntax::ExprKind::Call { args, .. } = &mut expression.kind {
            args[1].span.start += 1;
        } else {
            panic!("call fixture");
        }
        assert!(SharedExpression::capture(source.into(), &Arc::new(expression)).is_none());
    }
}

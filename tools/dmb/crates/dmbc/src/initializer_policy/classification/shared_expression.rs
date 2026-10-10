//! Retain only exact source-local syntax issued by the common expression parser.
//! An evaluator may supply arbitrary coordinates; those never gain authority here.
use std::sync::{Arc, Mutex};

pub(super) struct SharedExpression {
    source: Arc<str>,
    expression: Mutex<Option<Arc<dm_syntax::Expr>>>,
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
            expression: Mutex::new(Some(Arc::clone(supplied))),
        })
    }
    pub(super) fn bind(&self, current_source: &str) -> Option<Arc<dm_syntax::Expr>> {
        if self.source.as_ref() != current_source {
            return None;
        }
        let mut cache = self
            .expression
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if cache.is_none() {
            // Same parser and exact source as capture: all nested coordinates
            // remain source-local, never absolute frontend authority.
            let parsed = dm_syntax::parse_expression(&self.source);
            if !parsed.diagnostics.is_empty() {
                return None;
            }
            *cache = Some(Arc::new(parsed.expr?));
        }
        cache.as_ref().map(Arc::clone)
    }
    pub(super) fn release_syntax(&self) {
        *self
            .expression
            .lock()
            .unwrap_or_else(|error| error.into_inner()) = None;
    }
    pub(super) fn visit_retained<R>(
        &self,
        visitor: impl FnOnce(&Arc<str>, Option<&Arc<dm_syntax::Expr>>) -> R,
    ) -> R {
        let cache = self
            .expression
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        visitor(&self.source, cache.as_ref())
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

#[cfg(test)]
mod pressure_tests {
    use super::*;
    #[test]
    fn released_syntax_rebinds_exact_relative_tree_and_keeps_live_reader_valid() {
        let source = "list(1, list(2, 3))";
        let expected = Arc::new(dm_syntax::parse_expression(source).expr.unwrap());
        let leaf = SharedExpression::capture(source.into(), &expected).unwrap();
        let reader = leaf.bind(source).unwrap();
        leaf.release_syntax();
        leaf.visit_retained(|text, syntax| {
            assert_eq!(text.as_ref(), source);
            assert!(syntax.is_none());
        });
        assert!(leaf.bind("list(1, list(2, 4))").is_none());
        let rebound = leaf.bind(source).unwrap();
        assert_eq!(*rebound, *expected);
        assert!(!Arc::ptr_eq(&reader, &rebound));
        assert!(Arc::ptr_eq(&rebound, &leaf.bind(source).unwrap()));
        assert_eq!(*reader, *expected);
    }
}

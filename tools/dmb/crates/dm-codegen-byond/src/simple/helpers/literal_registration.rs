//! Constant payload leaves through the same interpolation parser as emission.
use super::{Expr, ExprKind};
use dm_syntax::LiteralText;

/// Visit cooked constant string literal payloads in source expression order.
/// A dynamic template is not itself a constant payload; all its interpolation
/// expression leaves are inspected, including folded/unselected branches and
/// recursively interpolated literal expressions. No resolver is consulted.
/// Only the current literal's parsed expressions are temporarily owned.
pub fn visit_constant_string_literals(
    raw: &str,
    mut visitor: impl FnMut(&[u8]),
) -> Result<(), String> {
    visit_literal(&LiteralText::from(raw), &mut visitor)
}

pub fn visit_native_constant_string_literals(
    raw: &LiteralText,
    mut visitor: impl FnMut(&[u8]),
) -> Result<(), String> {
    visit_literal(raw, &mut visitor)
}
fn visit_literal(raw: &LiteralText, visitor: &mut dyn FnMut(&[u8])) -> Result<(), String> {
    if raw.original_value().is_some(){
        if let Some(bytes)=super::decode_native_constant_string_literal(raw)?{visitor(&bytes);}
        return Ok(());
    }
    let Some(parts) = raw.parts().map_err(str::to_owned)? else {
        return Ok(());
    };
    if parts.expressions.is_empty() {
        visitor(&parts.template);
        return Ok(());
    }
    struct Leaves<'a> {
        visitor: &'a mut dyn FnMut(&[u8]),
        error: Option<String>,
    }
    impl dm_syntax::TypedVisitor for Leaves<'_> {
        fn projected_expression(
            &mut self,
            view: dm_syntax::ProjectedExprView<'_>,
            path: &[dm_syntax::NodeStep],
        ) -> dm_syntax::VisitDecision {
            // Explicitly shape/identity-only; no original span is used as current.
            self.expression(view.original(), path)
        }

        fn expression(
            &mut self,
            expression: &Expr,
            _: &[dm_syntax::NodeStep],
        ) -> dm_syntax::VisitDecision {
            if let ExprKind::Literal(raw) = &expression.kind {
                if let Err(error) = visit_literal(raw, self.visitor) {
                    self.error = Some(error);
                    return dm_syntax::VisitDecision::Stop;
                }
            }
            if matches!(expression.kind, ExprKind::Literal(_)) {
                dm_syntax::VisitDecision::Skip
            } else {
                dm_syntax::VisitDecision::Descend
            }
        }
    }
    let mut leaves = Leaves {
        visitor,
        error: None,
    };
    for expression in &parts.expressions {
        dm_syntax::visit_expression(expression, &mut leaves);
        if let Some(error) = leaves.error.take() {
            return Err(error);
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    fn strings(raw: &str) -> Result<Vec<Vec<u8>>, String> {
        let mut strings = Vec::new();
        visit_constant_string_literals(raw, |bytes| strings.push(bytes.to_vec()))?;
        Ok(strings)
    }
    #[test]
    fn string_allocation_nested_interpolation_keeps_both_conditional_literal_branches() {
        let raw = r#""[1 ? "a_second" : "\x74ype_value"][pick("z_first", "a_second")]""#;
        assert_eq!(
            strings(raw).unwrap(),
            [
                b"a_second".to_vec(),
                b"type_value".to_vec(),
                b"z_first".to_vec(),
                b"a_second".to_vec(),
            ]
        );
        assert!(super::super::decode_constant_string_literal(raw)
            .unwrap()
            .is_none());
    }
    #[test]
    fn string_allocation_nested_interpolation_recurses_without_interpreting_raw_brackets() {
        let raw = r#""[pick("[value]", @"[a_second]", "type_value")]""#;
        assert_eq!(
            strings(raw).unwrap(),
            [b"[a_second]".to_vec(), b"type_value".to_vec()]
        );
        assert_eq!(
            strings(r#"@"[a_second]""#).unwrap(),
            [b"[a_second]".to_vec()]
        );
        let recursive = r#""[pick("[condition ? "a_second" : "type_value"]", "z_first")]""#;
        assert_eq!(
            strings(recursive).unwrap(),
            [
                b"a_second".to_vec(),
                b"type_value".to_vec(),
                b"z_first".to_vec(),
            ]
        );
    }
    #[test]
    fn string_allocation_literal_visitor_preserves_decoder_errors_and_cooked_bytes() {
        for raw in [r#""\x74ype_value""#, r#"@"a_second""#, "{\"line\nvalue\"}"] {
            let expected = super::super::decode_constant_string_literal(raw)
                .unwrap()
                .unwrap();
            assert_eq!(strings(raw).unwrap(), [expected]);
        }
        assert!(strings(r#""[pick("\q")]""#).is_err());
        assert!(strings("42").unwrap().is_empty());
        assert!(strings("'resource.txt'").unwrap().is_empty());
    }
}

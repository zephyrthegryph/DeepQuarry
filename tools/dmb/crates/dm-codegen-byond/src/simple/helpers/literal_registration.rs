//! Constant payload leaves through the same interpolation parser as emission.
use super::{string_literal_parts, Expr, ExprKind};

/// Visit cooked constant string literal payloads in source expression order.
/// A dynamic template is not itself a constant payload; all its interpolation
/// expression leaves are inspected, including folded/unselected branches and
/// recursively interpolated literal expressions. No resolver is consulted.
/// Only the current literal's parsed expressions are temporarily owned.
pub fn visit_constant_string_literals(
    raw: &str,
    mut visitor: impl FnMut(&[u8]),
) -> Result<(), String> {
    visit_literal(raw, &mut visitor)
}

fn visit_literal(raw: &str, visitor: &mut dyn FnMut(&[u8])) -> Result<(), String> {
    let Some((bytes, expressions)) = string_literal_parts(raw)? else {
        return Ok(());
    };
    if expressions.is_empty() {
        visitor(&bytes);
        return Ok(());
    }
    struct Leaves<'a> {
        visitor: &'a mut dyn FnMut(&[u8]),
        error: Option<String>,
    }
    impl dm_syntax::TypedVisitor for Leaves<'_> {
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
            dm_syntax::VisitDecision::Descend
        }
    }
    let mut leaves = Leaves {
        visitor,
        error: None,
    };
    for expression in &expressions {
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

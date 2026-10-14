//! Physical continuation splicing for expressions extracted from string templates.
//! Nested literals keep their escapes for the shared literal decoder.
use crate::{lex_spans, TokenKind};
use std::borrow::Cow;

pub fn splice_expression_continuations(source: &str) -> Cow<'_, str> {
    if !source.contains("\\\n") && !source.contains("\\\r\n") {
        return Cow::Borrowed(source);
    }
    let mut output = String::with_capacity(source.len());
    let mut start = 0;
    for token in lex_spans(source).tokens {
        if matches!(token.kind, TokenKind::String | TokenKind::Resource) {
            splice(&source[start..token.span.range().start], &mut output);
            output.push_str(token.text(source));
            start = token.span.range().end;
        }
    }
    splice(&source[start..], &mut output);
    Cow::Owned(output)
}

fn splice(source: &str, output: &mut String) {
    let mut start = 0;
    let bytes = source.as_bytes();
    let mut cursor = 0;
    while cursor < bytes.len() {
        let length = if bytes[cursor..].starts_with(b"\\\r\n") {
            3
        } else if bytes[cursor..].starts_with(b"\\\n") {
            2
        } else {
            cursor += 1;
            continue;
        };
        output.push_str(&source[start..cursor]);
        cursor += length;
        start = cursor;
    }
    output.push_str(&source[start..]);
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn splices_expression_tokens_but_preserves_nested_literal_continuations() {
        let source = "pick(\"left\\\n    right\",\\\r\n    \"second\")";
        let joined = splice_expression_continuations(source);
        assert_eq!(joined, "pick(\"left\\\n    right\",    \"second\")");
        assert!(crate::parse_expression(&joined).diagnostics.is_empty());
        assert_eq!(splice_expression_continuations("na\\\nme"), "name");
        assert!(matches!(
            splice_expression_continuations("name"),
            Cow::Borrowed(_)
        ));
    }
}

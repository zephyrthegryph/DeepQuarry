//! One scalar clause partition shared by native metadata and original roots.
//! No lexer, AST, symbol table, token copy or source authority is created here.
use crate::parameter_syntax::ParameterToken;
use crate::{Span, SpanToken, TokenKind};
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ParameterClauseSpans {
    pub parameter: Span,
    pub assignment: Option<Span>,
    pub annotation: Option<Span>,
    pub source: Option<Span>,
}
impl ParameterClauseSpans {
    pub fn declaration_end(self) -> usize {
        [self.assignment, self.annotation, self.source]
            .into_iter()
            .flatten()
            .map(|s| s.start)
            .min()
            .unwrap_or(self.parameter.end)
    }
    pub fn after(self, marker: Span) -> Span {
        let end = [self.assignment, self.annotation, self.source]
            .into_iter()
            .flatten()
            .map(|s| s.start)
            .filter(|p| *p > marker.start)
            .min()
            .unwrap_or(self.parameter.end);
        Span::new(marker.end, end)
    }
}
pub fn parameter_clause_spans(
    source: &str,
    tokens: &[SpanToken],
    span: Span,
) -> Result<ParameterClauseSpans, &'static str> {
    clause_spans(source, tokens, span)
}
pub(crate) fn clause_spans<T: ParameterToken>(
    source: &str,
    tokens: &[T],
    span: Span,
) -> Result<ParameterClauseSpans, &'static str> {
    source
        .get(span.range())
        .ok_or("parameter clause span outside original source")?;
    let mut out = ParameterClauseSpans {
        parameter: span,
        assignment: None,
        annotation: None,
        source: None,
    };
    let mut top = 0i32;
    let mut assign = 0usize;
    for t in tokens {
        if t.span().start < span.start
            || t.span().end > span.end
            || source.get(t.span().range()).is_none()
        {
            return Err("parameter clause token escaped original range");
        }
        let text = t.text(source);
        match text {
            "(" | "[" | "{" => top += 1,
            ")" | "]" | "}" => top -= 1,
            "as" if top == 0 && out.annotation.is_none() => out.annotation = Some(t.span()),
            "in" if top == 0 && out.source.is_none() => out.source = Some(t.span()),
            _ => (),
        }
        if matches!(t.kind(), TokenKind::Operator | TokenKind::Punctuation) {
            match text {
                "(" | "[" | "{" => assign += 1,
                ")" | "]" | "}" => assign = assign.saturating_sub(1),
                "=" if assign == 0 && out.assignment.is_none() => out.assignment = Some(t.span()),
                _ => (),
            }
        }
    }
    Ok(out)
}

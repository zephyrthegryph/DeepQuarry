//! Borrowed spans over one lexical pass; subviews keep expression-local offsets.
use dm_syntax::{Span, SpanToken, TokenKind};
#[derive(Debug)]
pub(super) struct LexedHeader<'a> {
    source: &'a str,
    tokens: Vec<SpanToken>,
    valid: bool,
}
impl<'a> LexedHeader<'a> {
    pub(super) fn new(source: &'a str) -> Self {
        #[cfg(test)]
        LEXICAL_HEADER_CALLS.with(|n| n.set(n.get() + 1));
        let lexed = dm_syntax::lex_spans(source);
        Self {
            source,
            tokens: lexed.tokens,
            valid: lexed.diagnostics.is_empty(),
        }
    }
    pub(super) fn valid(&self) -> bool {
        self.valid
    }
    pub(super) fn view(&self) -> HeaderView<'_> {
        HeaderView {
            source: self.source,
            tokens: &self.tokens,
            range: Span::new(0, self.source.len()),
        }
    }
}
#[derive(Clone, Copy)]
pub(super) struct HeaderView<'a> {
    source: &'a str,
    tokens: &'a [SpanToken],
    range: Span,
}
impl<'a> HeaderView<'a> {
    // Only the sibling original-input producer calls this constructor. A view
    // never claims filesystem/current-frame authority by itself.
    pub(super) fn original(
        source: &'a str,
        tokens: &'a [SpanToken],
        range: Span,
    ) -> Result<Self, String> {
        source
            .get(range.range())
            .ok_or("original header range unavailable")?;
        if tokens
            .iter()
            .any(|t| t.span.start < range.start || t.span.end > range.end)
        {
            return Err("original header token escaped its issued range".into());
        }
        Ok(Self {
            source,
            tokens,
            range,
        })
    }
    pub(super) fn parameter_markers(
        self,
    ) -> Result<(Option<usize>, Option<Span>, Option<Span>), String> {
        let parts = dm_syntax::parameter_clause_spans(self.source, self.tokens, self.range)
            .map_err(str::to_owned)?;
        let relative =
            |span: Span| Span::new(span.start - self.range.start, span.end - self.range.start);
        Ok((
            parts.assignment.map(|s| s.start - self.range.start),
            parts.annotation.map(relative),
            parts.source.map(relative),
        ))
    }
    pub(super) fn text(self) -> &'a str {
        &self.source[self.range.range()]
    }
    pub(super) fn tokens(self) -> &'a [SpanToken] {
        self.tokens
    }
    pub(super) fn spelling(self, token: &SpanToken) -> &'a str {
        token.text(self.source)
    }
    pub(super) fn relative_span(self, token: &SpanToken) -> Span {
        Span::new(
            token.span.start - self.range.start,
            token.span.end - self.range.start,
        )
    }
    pub(super) fn slice(self, start: usize, end: usize) -> Self {
        let range = Span::new(self.range.start + start, self.range.start + end);
        let first = self
            .tokens
            .partition_point(|token| token.span.start < range.start);
        let last = self
            .tokens
            .partition_point(|token| token.span.start < range.end);
        Self {
            source: self.source,
            tokens: &self.tokens[first..last],
            range,
        }
    }
    pub(super) fn trim(self) -> Self {
        let text = self.text();
        let start = text.len() - text.trim_start().len();
        self.slice(start, start + text.trim().len())
    }
    pub(super) fn top_level(self) -> Vec<(&'a str, Span)> {
        let mut depth = 0i32;
        let mut result = Vec::new();
        for token in self.tokens {
            let text = self.spelling(token);
            match text {
                "(" | "[" | "{" => depth += 1,
                ")" | "]" | "}" => depth -= 1,
                _ if depth == 0 => result.push((text, self.relative_span(token))),
                _ => {}
            }
        }
        result
    }
    pub(super) fn assignment(self) -> Option<usize> {
        let mut depth = 0usize;
        for token in self.tokens {
            if !matches!(token.kind, TokenKind::Operator | TokenKind::Punctuation) {
                continue;
            }
            match self.spelling(token) {
                "(" | "[" | "{" => depth += 1,
                ")" | "]" | "}" => depth = depth.saturating_sub(1),
                "=" if depth == 0 => return Some(self.relative_span(token).start),
                _ => {}
            }
        }
        None
    }
    pub(super) fn ident(self) -> bool {
        self.tokens.len() == 1
            && self.tokens[0].kind == TokenKind::Ident
            && self.tokens[0].span.start == self.range.start
            && self.tokens[0].span.end == self.range.end
    }
}

#[cfg(test)]
thread_local! { static LEXICAL_HEADER_CALLS: std::cell::Cell<usize> = const { std::cell::Cell::new(0) }; }
#[cfg(test)]
pub(super) fn lexical_header_calls() -> usize {
    LEXICAL_HEADER_CALLS.with(std::cell::Cell::get)
}

#[cfg(test)]
mod parameter_clause_tests {
    use super::*;
    #[test]
    fn shared_parameter_markers_match_existing_native_metadata_partition_without_lex() {
        for source in [
            "x = list(1,2) as text in choices(\"é,in\")",
            "x in list(1) as obj|null",
            "datum/x[2] = null",
            "x = world.vars[\"as\"]",
            "x = F(/* as */1) as text",
        ] {
            let input = LexedHeader::new(source);
            assert!(input.valid());
            let view = input.view();
            let before = lexical_header_calls();
            let top = view.top_level();
            let expected = (
                view.assignment(),
                top.iter().find(|(t, _)| *t == "as").map(|(_, s)| *s),
                top.iter().find(|(t, _)| *t == "in").map(|(_, s)| *s),
            );
            assert_eq!(view.parameter_markers().unwrap(), expected, "{source}");
            assert_eq!(
                lexical_header_calls(),
                before,
                "borrow original tokens; no header relex"
            );
        }
    }
}

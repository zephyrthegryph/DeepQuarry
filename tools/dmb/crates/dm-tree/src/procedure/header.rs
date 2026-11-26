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

//! Lossless lexical layer and a recovering structural parser for BYOND DM.
//!
//! This crate intentionally makes no claim to parse every expression yet. A declaration's
//! header and indented body are retained as tokens so later stages can diagnose unsupported
//! syntax without discarding the original source or changing declaration order.

use serde::{Deserialize, Serialize};
use std::ops::Range;

mod audit;
mod segmented;
pub use segmented::{SegmentedSource, SegmentedChunkSession};
mod statements;
pub use audit::{
    audit_source_streaming, for_each_parsed_chunk, for_each_source_chunk,
    for_each_source_chunk_with_limits, parse_proc_at_span, ChunkReport, StreamingAudit,
};
pub use statements::{
    parse_body_items, parse_proc_body, ForControl, ForInitializer, ParsedBody, Statement,
    StatementKind, SwitchAlternative, SwitchCase,
};

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq, Hash, Serialize, Deserialize)]
pub struct Span {
    pub start: usize,
    pub end: usize,
}

impl Span {
    pub fn new(start: usize, end: usize) -> Self {
        Self { start, end }
    }
    pub fn range(self) -> Range<usize> {
        self.start..self.end
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Diagnostic {
    pub span: Span,
    pub kind: DiagnosticKind,
    pub message: String,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Hash)]
pub enum DiagnosticKind {
    Lexical,
    Expression,
    Statement,
    Indentation,
    Unsupported,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Hash)]
pub enum TokenKind {
    Ident,
    Number,
    String,
    Resource,
    Interpolation,
    Operator,
    Punctuation,
    Whitespace,
    Newline,
    Comment,
    Unknown,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Token {
    pub kind: TokenKind,
    pub span: Span,
    pub text: String,
}

/// A token view into the caller's source. Large preprocessing passes can use these spans
/// without allocating a separate `String` for every punctuation or identifier token.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct SpanToken {
    pub kind: TokenKind,
    pub span: Span,
}

impl SpanToken {
    pub fn text<'a>(self, source: &'a str) -> &'a str {
        &source[self.span.range()]
    }
}

#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct SpannedLexed {
    pub tokens: Vec<SpanToken>,
    pub diagnostics: Vec<Diagnostic>,
}

#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct Lexed {
    pub tokens: Vec<Token>,
    pub diagnostics: Vec<Diagnostic>,
}

fn ident_start(c: char) -> bool {
    c == '_' || c.is_alphabetic()
}
fn ident_continue(c: char) -> bool {
    ident_start(c) || c.is_ascii_digit()
}

/// End offset of a DM quoted string, including nested interpolation strings.
pub fn quoted_end(rest: &str, block: bool, raw: bool) -> Option<usize> {
    let mut iter = rest.char_indices().peekable();
    if block {
        iter.next(); // {
    }
    iter.next(); // opening quote
    let mut interpolation_depth = 0usize;
    let mut escaped = false;
    while let Some((at, ch)) = iter.next() {
        if escaped {
            escaped = false;
            continue;
        }
        if ch == '\\' && (!raw || interpolation_depth > 0) {
            escaped = true;
            continue;
        }
        if interpolation_depth > 0 {
            match ch {
                '"' => {
                    // A string inside an interpolation can itself interpolate
                    // another expression. Skip the complete nested literal;
                    // a single quote-state would mistake its inner brackets
                    // and quotes for the enclosing expression's delimiters.
                    let end = quoted_end(&rest[at..], false, rest[..at].ends_with('@'))?;
                    while iter.peek().is_some_and(|(next, _)| *next < at + end) {
                        iter.next();
                    }
                }
                '\'' => {
                    let mut end = None;
                    let mut quote_escape = false;
                    for (offset, current) in rest[at + 1..].char_indices() {
                        if quote_escape {
                            quote_escape = false;
                        } else if current == '\\' && !rest[..at].ends_with('@') {
                            quote_escape = true;
                        } else if current == '\'' {
                            end = Some(at + 1 + offset + 1);
                            break;
                        }
                    }
                    let end = end?;
                    while iter.peek().is_some_and(|(next, _)| *next < end) {
                        iter.next();
                    }
                }
                '[' => interpolation_depth += 1,
                ']' => interpolation_depth -= 1,
                _ => {}
            }
            continue;
        }
        if ch == '[' && !raw {
            interpolation_depth = 1;
        } else if ch == '"' {
            if !block {
                return Some(at + 1);
            }
            if iter.peek().is_some_and(|(_, next)| *next == '}') {
                return Some(at + 2);
            }
        }
    }
    None
}

/// Lex without discarding trivia. Token spans are UTF-8 byte offsets into `source`.
pub fn lex(source: &str) -> Lexed {
    let spanned = lex_spans(source);
    Lexed {
        tokens: spanned
            .tokens
            .into_iter()
            .map(|token| Token {
                kind: token.kind,
                span: token.span,
                text: token.text(source).into(),
            })
            .collect(),
        diagnostics: spanned.diagnostics,
    }
}

/// Lex into source-backed spans. The caller must retain `source` while reading token text.
pub fn lex_spans(source: &str) -> SpannedLexed {
    let mut out = SpannedLexed::default();
    out.diagnostics = visit_tokens(source, |token| out.tokens.push(token));
    out
}

/// Visit source-backed tokens without retaining a whole-source token vector.
/// Asset discovery and other streaming consumers can keep only relevant tokens.
pub fn visit_tokens(source: &str, mut visitor: impl FnMut(SpanToken)) -> Vec<Diagnostic> {
    let mut diagnostics = Vec::new();
    let mut pos = 0;
    while pos < source.len() {
        let rest = &source[pos..];
        let c = rest.chars().next().unwrap();
        let (kind, end, unterminated) = if c == '\n' || c == '\r' {
            let n = if rest.starts_with("\r\n") {
                2
            } else {
                c.len_utf8()
            };
            (TokenKind::Newline, pos + n, false)
        } else if c == ' ' || c == '\t' {
            let n = rest
                .char_indices()
                .take_while(|(_, c)| *c == ' ' || *c == '\t')
                .map(|(_, c)| c.len_utf8())
                .sum::<usize>();
            (TokenKind::Whitespace, pos + n, false)
        } else if rest.starts_with("//") {
            (
                TokenKind::Comment,
                pos + rest.find(['\r', '\n']).unwrap_or(rest.len()),
                false,
            )
        } else if rest.starts_with("/*") {
            let mut depth = 1usize;
            let mut cursor = 2usize;
            while depth > 0 && cursor + 1 < rest.len() {
                if rest[cursor..].starts_with("/*") {
                    depth += 1;
                    cursor += 2;
                } else if rest[cursor..].starts_with("*/") {
                    depth -= 1;
                    cursor += 2;
                } else {
                    cursor += rest[cursor..].chars().next().unwrap().len_utf8();
                }
            }
            if depth == 0 {
                (TokenKind::Comment, pos + cursor, false)
            } else {
                (TokenKind::Comment, source.len(), true)
            }
        } else if rest.starts_with("@'") {
            let close = rest[2..].find('\'').map(|at| at + 3);
            (
                TokenKind::String,
                pos + close.unwrap_or(rest.len()),
                close.is_none(),
            )
        } else if rest.starts_with("@{\"") {
            let close = quoted_end(&rest[1..], true, true);
            (
                TokenKind::String,
                pos + close.map_or(rest.len(), |end| end + 1),
                close.is_none(),
            )
        } else if rest.starts_with("{\"") {
            let close = quoted_end(rest, true, false);
            (
                TokenKind::String,
                pos + close.unwrap_or(rest.len()),
                close.is_none(),
            )
        } else if rest.starts_with("@\"") {
            let close = quoted_end(&rest[1..], false, true);
            (
                TokenKind::String,
                pos + close.map_or(rest.len(), |end| end + 1),
                close.is_none(),
            )
        } else if c == '"' || c == '\'' {
            let mut escape = false;
            let close = if c == '"' {
                quoted_end(rest, false, false)
            } else {
                let mut close = None;
                for (offset, ch) in rest.char_indices().skip(1) {
                    if escape {
                        escape = false;
                        continue;
                    }
                    if ch == '\\' {
                        escape = true;
                        continue;
                    }
                    if ch == c {
                        close = Some(offset + ch.len_utf8());
                        break;
                    }
                }
                close
            };
            let kind = if c == '\'' {
                TokenKind::Resource
            } else {
                TokenKind::String
            };
            (kind, pos + close.unwrap_or(rest.len()), close.is_none())
        } else if ident_start(c) {
            let n = rest
                .char_indices()
                .take_while(|(_, c)| ident_continue(*c))
                .map(|(_, c)| c.len_utf8())
                .sum::<usize>();
            (TokenKind::Ident, pos + n, false)
        } else if c.is_ascii_digit() {
            let mut n = 0;
            for (offset, ch) in rest.char_indices() {
                let exponent_sign = matches!(ch, '+' | '-')
                    && offset > 0
                    && matches!(rest.as_bytes()[offset - 1], b'e' | b'E')
                    && !rest.starts_with("0x")
                    && !rest.starts_with("0X")
                    && rest
                        .as_bytes()
                        .get(offset + 1)
                        .is_some_and(u8::is_ascii_digit);
                if ch.is_ascii_alphanumeric() || matches!(ch, '.' | '_') || exponent_sign {
                    n = offset + ch.len_utf8();
                } else {
                    break;
                }
            }
            if rest[..n].ends_with('.') && rest[n..].starts_with("#INF") {
                n += "#INF".len();
            }
            (TokenKind::Number, pos + n, false)
        } else {
            let kind = if "/()[]{}.,:;#?".contains(c) {
                TokenKind::Punctuation
            } else if "+-*%=!<>|&^~".contains(c) {
                TokenKind::Operator
            } else {
                TokenKind::Unknown
            };
            (kind, pos + c.len_utf8(), false)
        };
        if unterminated {
            diagnostics.push(Diagnostic {
                span: Span::new(pos, end),
                kind: DiagnosticKind::Lexical,
                message: "unterminated string or comment".into(),
            });
        }
        visitor(SpanToken {
            kind,
            span: Span::new(pos, end),
        });
        pos = end;
    }
    diagnostics
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum ItemKind {
    Type,
    Proc,
    Verb,
    Var,
    Statement,
    Unknown,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct Item {
    pub kind: ItemKind,
    /// Source spelling, including whether a path was relative.
    pub header: String,
    pub span: Span,
    pub header_span: Span,
    pub indent: usize,
    pub children: Vec<Item>,
}

#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct AstFile {
    pub items: Vec<Item>,
    pub tokens: Vec<Token>,
    pub diagnostics: Vec<Diagnostic>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ExprKind {
    Ident(String),
    Literal(String),
    TypePath(String),
    Unary {
        op: String,
        value: Box<Expr>,
    },
    Binary {
        op: String,
        lhs: Box<Expr>,
        rhs: Box<Expr>,
    },
    Conditional {
        condition: Box<Expr>,
        then_value: Box<Expr>,
        else_value: Box<Expr>,
    },
    Call {
        callee: Box<Expr>,
        args: Vec<Expr>,
    },
    Member {
        object: Box<Expr>,
        selector: String,
        via_colon: bool,
    },
    StaticMember {
        object: Box<Expr>,
        selector: String,
    },
    TypeFilter {
        value: Box<Expr>,
        types: Vec<String>,
    },
    ObjectInitializer {
        object: Box<Expr>,
        fields: Vec<(String, Expr)>,
    },
    SafeMember {
        object: Box<Expr>,
        selector: String,
    },
    Index {
        object: Box<Expr>,
        index: Box<Expr>,
    },
    SafeIndex {
        object: Box<Expr>,
        index: Box<Expr>,
    },
    Group(Box<Expr>),
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Expr {
    pub kind: ExprKind,
    pub span: Span,
}

#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct ParsedExpr {
    pub expr: Option<Expr>,
    pub diagnostics: Vec<Diagnostic>,
}

/// Parse the expression subset used by declaration defaults and simple procedure bodies.
/// Invalid or unsupported syntax returns a diagnostic instead of a guessed expression.
pub fn parse_expression(source: &str) -> ParsedExpr {
    let lexical = lex(source);
    let mut parser = ExprParser {
        tokens: lexical
            .tokens
            .into_iter()
            .filter(|t| {
                !matches!(
                    t.kind,
                    TokenKind::Whitespace | TokenKind::Newline | TokenKind::Comment
                )
            })
            .collect(),
        index: 0,
        ternary_then_depth: 0,
        diagnostics: lexical.diagnostics,
    };
    let expr = parser.expression(0);
    if let Some(token) = parser.peek() {
        parser.diagnostics.push(Diagnostic {
            span: token.span,
            kind: DiagnosticKind::Expression,
            message: format!("unexpected token in expression: {}", token.text),
        });
    }
    ParsedExpr {
        expr,
        diagnostics: parser.diagnostics,
    }
}

struct ExprParser {
    tokens: Vec<Token>,
    index: usize,
    ternary_then_depth: usize,
    diagnostics: Vec<Diagnostic>,
}

impl ExprParser {
    fn peek(&self) -> Option<&Token> {
        self.tokens.get(self.index)
    }
    fn take(&mut self) -> Option<Token> {
        let token = self.peek()?.clone();
        self.index += 1;
        Some(token)
    }
    fn take_text(&mut self, text: &str) -> Option<Token> {
        if self.peek().is_some_and(|t| t.text == text) {
            self.take()
        } else {
            None
        }
    }
    fn error(&mut self, span: Span, message: impl Into<String>) {
        self.diagnostics.push(Diagnostic {
            span,
            kind: DiagnosticKind::Expression,
            message: message.into(),
        });
    }

    fn expression(&mut self, min_bp: u8) -> Option<Expr> {
        let mut lhs = self.prefix()?;
        loop {
            if self.ternary_then_depth > 0
                && self.peek().is_some_and(|token| token.text == ":")
                && !self
                    .tokens
                    .get(self.index + 1)
                    .is_some_and(|token| token.text == ":")
                && !self.colon_member_before_ternary_separator(&lhs)
            {
                break;
            }
            if min_bp <= 26 {
                if let Some(open) = self.take_text("{") {
                    let mut fields = Vec::new();
                    while self.peek().is_some_and(|next| next.text != "}") {
                        let Some(name) = self.take() else {
                            break;
                        };
                        if name.kind != TokenKind::Ident {
                            self.error(name.span, "expected object initializer field name");
                            break;
                        }
                        if self.take_text("=").is_none() {
                            self.error(name.span, "expected = after object initializer field");
                            break;
                        }
                        let Some(value) = self.expression_nested(0) else {
                            self.error(name.span, "expected object initializer field value");
                            break;
                        };
                        fields.push((name.text, value));
                        if self.take_text(",").is_none() && self.take_text(";").is_none() {
                            break;
                        }
                    }
                    let end = self.take_text("}").map_or_else(
                        || {
                            self.error(open.span, "unclosed object initializer");
                            lhs.span.end
                        },
                        |close| close.span.end,
                    );
                    lhs = Expr {
                        span: Span::new(lhs.span.start, end),
                        kind: ExprKind::ObjectInitializer {
                            object: Box::new(lhs),
                            fields,
                        },
                    };
                    continue;
                }
                if let (Some(first), Some(second)) =
                    (self.tokens.get(self.index), self.tokens.get(self.index + 1))
                {
                    if first.text == second.text
                        && matches!(first.text.as_str(), "+" | "-")
                        && first.span.end == second.span.start
                    {
                        let op = if first.text == "+" {
                            "post++"
                        } else {
                            "post--"
                        };
                        let end = second.span.end;
                        self.index += 2;
                        lhs = Expr {
                            span: Span::new(lhs.span.start, end),
                            kind: ExprKind::Unary {
                                op: op.into(),
                                value: Box::new(lhs),
                            },
                        };
                        continue;
                    }
                }
                if self.peek().is_some_and(|token| token.text == "?")
                    && self.tokens.get(self.index + 1).is_some_and(|token| {
                        (token.text == "." || token.text == "[")
                            && self.tokens[self.index].span.end == token.span.start
                    })
                {
                    self.take();
                    let separator = self.take().unwrap();
                    if separator.text == "." {
                        let Some(selector) = self.take() else {
                            self.error(separator.span, "expected safe member name");
                            break;
                        };
                        if selector.kind != TokenKind::Ident {
                            self.error(selector.span, "expected safe member name");
                            break;
                        }
                        lhs = Expr {
                            span: Span::new(lhs.span.start, selector.span.end),
                            kind: ExprKind::SafeMember {
                                object: Box::new(lhs),
                                selector: selector.text,
                            },
                        };
                    } else {
                        let index = self.expression_nested(0);
                        let end = self.take_text("]").map_or_else(
                            || {
                                self.error(separator.span, "unclosed safe index");
                                lhs.span.end
                            },
                            |token| token.span.end,
                        );
                        if let Some(index) = index {
                            lhs = Expr {
                                span: Span::new(lhs.span.start, end),
                                kind: ExprKind::SafeIndex {
                                    object: Box::new(lhs),
                                    index: Box::new(index),
                                },
                            };
                        }
                    }
                    continue;
                }
                if let Some(open) = self.take_text("(") {
                    let mut args = Vec::new();
                    if self.peek().is_some_and(|t| t.text != ")") {
                        loop {
                            if self.peek().is_some_and(|next| next.text == ",") {
                                let at = self.peek().unwrap().span.start;
                                args.push(Expr {
                                    span: Span::new(at, at),
                                    kind: ExprKind::Literal("null".into()),
                                });
                                self.take();
                                continue;
                            }
                            let Some(mut arg) = self.expression_nested(0) else {
                                self.error(open.span, "missing call argument");
                                break;
                            };
                            if self.take_text(";").is_some() {
                                let Some(value) = self.expression_nested(0) else {
                                    self.error(arg.span, "missing weighted pick value");
                                    break;
                                };
                                arg = Expr {
                                    span: Span::new(arg.span.start, value.span.end),
                                    kind: ExprKind::Binary {
                                        op: ";".into(),
                                        lhs: Box::new(arg),
                                        rhs: Box::new(value),
                                    },
                                };
                            }
                            args.push(arg);
                            if self.take_text(",").is_none() {
                                break;
                            }
                            if self.peek().is_some_and(|next| next.text == ")") {
                                break;
                            }
                        }
                    }
                    let end = self.take_text(")").map_or_else(
                        || {
                            self.error(open.span, "unclosed call");
                            lhs.span.end
                        },
                        |t| t.span.end,
                    );
                    lhs = Expr {
                        span: Span::new(lhs.span.start, end),
                        kind: ExprKind::Call {
                            callee: Box::new(lhs),
                            args,
                        },
                    };
                    // `in` is an optional locate clause, so it belongs inside
                    // an enclosing prefix operator (`!locate(T) in L`).
                    if matches!(&lhs.kind, ExprKind::Call { callee, args }
                        if matches!(&callee.kind, ExprKind::Ident(name) if name == "locate")
                            && args.len() <= 1)
                        && self.take_text("in").is_some()
                    {
                        let container = self.expression(8)?;
                        lhs = Expr {
                            span: Span::new(lhs.span.start, container.span.end),
                            kind: ExprKind::Binary {
                                op: "in".into(),
                                lhs: Box::new(lhs),
                                rhs: Box::new(container),
                            },
                        };
                    }
                    continue;
                }
                if let Some(open) = self.take_text("[") {
                    let index = self.expression_nested(0);
                    let end = self.take_text("]").map_or_else(
                        || {
                            self.error(open.span, "unclosed index");
                            lhs.span.end
                        },
                        |t| t.span.end,
                    );
                    if let Some(index) = index {
                        lhs = Expr {
                            span: Span::new(lhs.span.start, end),
                            kind: ExprKind::Index {
                                object: Box::new(lhs),
                                index: Box::new(index),
                            },
                        };
                    }
                    continue;
                }
                if self.peek().is_some_and(|t| t.text == "." || t.text == ":") {
                    let separator = self.take().unwrap();
                    let is_static = separator.text == ":" && self.take_text(":").is_some();
                    let Some(selector) = self.take() else {
                        self.error(separator.span, "expected member after selector");
                        break;
                    };
                    if selector.kind != TokenKind::Ident {
                        self.error(selector.span, "expected member name");
                        break;
                    }
                    lhs = Expr {
                        span: Span::new(lhs.span.start, selector.span.end),
                        kind: if is_static {
                            ExprKind::StaticMember {
                                object: Box::new(lhs),
                                selector: selector.text,
                            }
                        } else {
                            ExprKind::Member {
                                object: Box::new(lhs),
                                selector: selector.text,
                                via_colon: separator.text == ":",
                            }
                        },
                    };
                    continue;
                }
            }
            if min_bp <= 8 && self.take_text("as").is_some() {
                let mut types = Vec::new();
                let mut end = lhs.span.end;
                loop {
                    let Some(kind) = self.take() else {
                        self.error(lhs.span, "missing input type after as");
                        break;
                    };
                    if kind.kind != TokenKind::Ident {
                        self.error(kind.span, "expected input type after as");
                        break;
                    }
                    end = kind.span.end;
                    types.push(kind.text);
                    if self.take_text("|").is_none() {
                        break;
                    }
                }
                lhs = Expr {
                    span: Span::new(lhs.span.start, end),
                    kind: ExprKind::TypeFilter {
                        value: Box::new(lhs),
                        types,
                    },
                };
                continue;
            }
            if min_bp <= 2 && self.take_text("?").is_some() {
                self.ternary_then_depth += 1;
                let then_value = self.expression(0);
                self.ternary_then_depth -= 1;
                let then_value = then_value?;
                if self.take_text(":").is_none() {
                    self.error(lhs.span, "ternary expression requires :");
                    return Some(lhs);
                }
                let else_value = self.expression(2)?;
                lhs = Expr {
                    span: Span::new(lhs.span.start, else_value.span.end),
                    kind: ExprKind::Conditional {
                        condition: Box::new(lhs),
                        then_value: Box::new(then_value),
                        else_value: Box::new(else_value),
                    },
                };
                continue;
            }
            let Some((op, width, left_bp, right_bp)) = self.operator() else {
                break;
            };
            if left_bp < min_bp {
                break;
            }
            self.index += width;
            let Some(rhs) = self.expression(right_bp) else {
                self.error(lhs.span, format!("missing right operand for {op}"));
                break;
            };
            lhs = Expr {
                span: Span::new(lhs.span.start, rhs.span.end),
                kind: ExprKind::Binary {
                    op,
                    lhs: Box::new(lhs),
                    rhs: Box::new(rhs),
                },
            };
        }
        Some(lhs)
    }

    fn colon_member_before_ternary_separator(&self, lhs: &Expr) -> bool {
        let Some(colon) = self.tokens.get(self.index) else {
            return false;
        };
        let Some(member) = self.tokens.get(self.index + 1) else {
            return false;
        };
        if lhs.span.end != colon.span.start
            || colon.span.end != member.span.start
            || member.kind != TokenKind::Ident
        {
            return false;
        }
        let mut nesting = 0usize;
        for token in self.tokens.iter().skip(self.index + 2) {
            match token.text.as_str() {
                "(" | "[" | "{" => nesting += 1,
                ")" | "]" | "}" if nesting == 0 => break,
                ")" | "]" | "}" => nesting -= 1,
                "," | ";" if nesting == 0 => break,
                ":" if nesting == 0 => return true,
                _ => {}
            }
        }
        false
    }

    fn expression_nested(&mut self, min_bp: u8) -> Option<Expr> {
        let previous = self.ternary_then_depth;
        self.ternary_then_depth = 0;
        let result = self.expression(min_bp);
        self.ternary_then_depth = previous;
        result
    }

    fn prefix(&mut self) -> Option<Expr> {
        let token = self.take()?;
        let span = token.span;
        match token.kind {
            TokenKind::Ident if token.text == "new" => {
                if self.peek().is_none() {
                    return Some(Expr {
                        span,
                        kind: ExprKind::Call {
                            callee: Box::new(Expr {
                                span,
                                kind: ExprKind::Ident("new".into()),
                            }),
                            args: Vec::new(),
                        },
                    });
                }
                if let Some(open) = self.take_text("(") {
                    let mut args = Vec::new();
                    if self.peek().is_some_and(|next| next.text != ")") {
                        loop {
                            if self.peek().is_some_and(|next| next.text == ",") {
                                let at = self.peek().unwrap().span.start;
                                args.push(Expr {
                                    span: Span::new(at, at),
                                    kind: ExprKind::Literal("null".into()),
                                });
                                self.take();
                                continue;
                            }
                            let Some(arg) = self.expression_nested(0) else {
                                self.error(open.span, "missing constructor argument");
                                break;
                            };
                            args.push(arg);
                            if self.take_text(",").is_none() {
                                break;
                            }
                            if self.peek().is_some_and(|next| next.text == ")") {
                                break;
                            }
                        }
                    }
                    let end = self.take_text(")").map_or_else(
                        || {
                            self.error(open.span, "unclosed constructor");
                            open.span.end
                        },
                        |close| close.span.end,
                    );
                    return Some(Expr {
                        span: Span::new(span.start, end),
                        kind: ExprKind::Call {
                            callee: Box::new(Expr {
                                span,
                                kind: ExprKind::Ident("new".into()),
                            }),
                            args,
                        },
                    });
                }
                let value = self.expression(24)?;
                Some(Expr {
                    span: Span::new(span.start, value.span.end),
                    kind: ExprKind::Unary {
                        op: token.text,
                        value: Box::new(value),
                    },
                })
            }
            TokenKind::Ident if token.text == "null" => Some(Expr {
                span,
                kind: ExprKind::Literal(token.text),
            }),
            TokenKind::Ident => Some(Expr {
                span,
                kind: ExprKind::Ident(token.text),
            }),
            TokenKind::Number | TokenKind::String | TokenKind::Resource => Some(Expr {
                span,
                kind: ExprKind::Literal(token.text),
            }),
            TokenKind::Operator if matches!(token.text.as_str(), "-" | "+" | "!" | "~") => {
                if matches!(token.text.as_str(), "-" | "+")
                    && self.peek().is_some_and(|next| {
                        next.text == token.text && next.span.start == token.span.end
                    })
                {
                    self.take();
                    let value = self.expression(24)?;
                    return Some(Expr {
                        span: Span::new(span.start, value.span.end),
                        kind: ExprKind::Unary {
                            op: if token.text == "+" {
                                "pre++".into()
                            } else {
                                "pre--".into()
                            },
                            value: Box::new(value),
                        },
                    });
                }
                let value = self.expression(24)?;
                Some(Expr {
                    span: Span::new(span.start, value.span.end),
                    kind: ExprKind::Unary {
                        op: token.text,
                        value: Box::new(value),
                    },
                })
            }
            TokenKind::Punctuation if token.text == "(" => {
                let value = self.expression_nested(0)?;
                let end = self.take_text(")").map_or_else(
                    || {
                        self.error(span, "unclosed group");
                        value.span.end
                    },
                    |t| t.span.end,
                );
                Some(Expr {
                    span: Span::new(span.start, end),
                    kind: ExprKind::Group(Box::new(value)),
                })
            }
            TokenKind::Punctuation if token.text == "/" => {
                let mut path = String::from("/");
                let mut end = span.end;
                while let Some(next) = self.peek() {
                    if next.span.start != end {
                        break;
                    }
                    if next.kind == TokenKind::Ident || next.text == "/" {
                        path.push_str(&next.text);
                        end = next.span.end;
                        self.index += 1;
                    } else if next.text == "."
                        && self.tokens.get(self.index + 1).is_some_and(|kind| {
                            matches!(kind.text.as_str(), "proc" | "verb" | "var")
                        })
                        && self
                            .tokens
                            .get(self.index + 2)
                            .is_some_and(|slash| slash.text == "/")
                    {
                        path.push('.');
                        path.push_str(&self.tokens[self.index + 1].text);
                        end = self.tokens[self.index + 1].span.end;
                        self.index += 2;
                    } else {
                        break;
                    }
                }
                if path == "/" {
                    self.error(span, "expected type path after /");
                    None
                } else {
                    path.truncate(path.trim_end_matches('/').len());
                    Some(Expr {
                        span: Span::new(span.start, end),
                        kind: ExprKind::TypePath(path),
                    })
                }
            }
            TokenKind::Punctuation if token.text == "." => {
                if let Some(second) = self.take_text(".") {
                    Some(Expr {
                        span: Span::new(span.start, second.span.end),
                        kind: ExprKind::Ident("..".into()),
                    })
                } else if self
                    .peek()
                    .is_some_and(|next| matches!(next.text.as_str(), "proc" | "verb" | "var"))
                    && self
                        .tokens
                        .get(self.index + 1)
                        .is_some_and(|next| next.text == "/")
                {
                    let mut path = String::from(".");
                    let mut end = span.end;
                    while let Some(next) = self.peek() {
                        if next.span.start != end {
                            break;
                        }
                        if next.kind == TokenKind::Ident || next.text == "/" {
                            path.push_str(&next.text);
                            end = next.span.end;
                            self.index += 1;
                        } else {
                            break;
                        }
                    }
                    path.truncate(path.trim_end_matches('/').len());
                    Some(Expr {
                        span: Span::new(span.start, end),
                        kind: ExprKind::TypePath(path),
                    })
                } else {
                    Some(Expr {
                        span,
                        kind: ExprKind::Ident(".".into()),
                    })
                }
            }
            _ => {
                self.error(span, format!("unexpected expression token: {}", token.text));
                None
            }
        }
    }

    fn operator(&self) -> Option<(String, usize, u8, u8)> {
        const OPS: &[(&str, u8, u8)] = &[
            ("=", 1, 1),
            ("+=", 1, 1),
            ("-=", 1, 1),
            ("*=", 1, 1),
            ("/=", 1, 1),
            ("%=", 1, 1),
            ("|=", 1, 1),
            ("&=", 1, 1),
            ("^=", 1, 1),
            ("<<=", 1, 1),
            (">>=", 1, 1),
            ("||=", 1, 1),
            ("&&=", 1, 1),
            ("||", 3, 4),
            ("&&", 5, 6),
            ("in", 7, 8),
            ("to", 8, 9),
            ("==", 7, 8),
            ("!=", 7, 8),
            ("~=", 7, 8),
            ("~!", 7, 8),
            ("<=", 9, 10),
            (">=", 9, 10),
            ("<", 9, 10),
            (">", 9, 10),
            ("|", 11, 12),
            ("^", 13, 14),
            ("&", 15, 16),
            ("<<", 17, 18),
            (">>", 17, 18),
            ("+", 19, 20),
            ("-", 19, 20),
            ("*", 21, 22),
            ("/", 21, 22),
            ("%", 21, 22),
            ("**", 25, 25),
        ];
        let first = self.peek()?;
        if !matches!(
            first.kind,
            TokenKind::Operator | TokenKind::Punctuation | TokenKind::Ident
        ) {
            return None;
        }
        let mut best: Option<(String, usize, u8, u8)> = None;
        for (op, l, r) in OPS {
            let mut width = 0;
            let mut assembled = String::new();
            for token in self.tokens.iter().skip(self.index) {
                if assembled.len() >= op.len()
                    || token.span.start != first.span.start + assembled.len()
                {
                    break;
                }
                assembled.push_str(&token.text);
                width += 1;
                if assembled == *op && best.as_ref().is_none_or(|b| op.len() > b.0.len()) {
                    best = Some(((*op).into(), width, *l, *r));
                }
            }
        }
        best
    }
}

#[derive(Clone)]
struct Line {
    indent: usize,
    header_start: usize,
    header_end: usize,
    end: usize,
}

/// Locate an assignment outside argument lists, indexing, strings, and braces.
pub fn top_level_assignment_index(source: &str) -> Option<usize> {
    let mut depth = 0usize;
    for token in lex_spans(source).tokens {
        if !matches!(token.kind, TokenKind::Operator | TokenKind::Punctuation) {
            continue;
        }
        match token.text(source) {
            "(" | "[" | "{" => depth += 1,
            ")" | "]" | "}" => depth = depth.saturating_sub(1),
            "=" if depth == 0 => return Some(token.span.start),
            _ => {}
        }
    }
    None
}
fn classify(header: &str, has_children: bool) -> ItemKind {
    let h = header.trim();
    let assignment = top_level_assignment_index(h);
    let boundary = lex_spans(h)
        .tokens
        .into_iter()
        .find(|token| {
            matches!(token.kind, TokenKind::Punctuation | TokenKind::Operator)
                && matches!(token.text(h), "(" | "{" | "=")
        })
        .map_or(h.len(), |token| token.span.start);
    let definition_prefix = &h[..boundary];
    if h.starts_with("set ")
        || h.starts_with("return")
        || h.starts_with("if(")
        || h.starts_with("if (")
        || h.starts_with("for(")
        || h.starts_with("for (")
        || h.starts_with("while(")
        || h.starts_with("while (")
        || h.starts_with("switch(")
        || h.starts_with("switch (")
        || h.starts_with("spawn(")
        || h.starts_with("spawn (")
        || h.starts_with("else")
        || h.starts_with("try")
        || h.starts_with("catch")
        || h.starts_with("break")
        || h.starts_with("continue")
        || h.starts_with("throw ")
        || h.starts_with(".")
    {
        return ItemKind::Statement;
    }
    if definition_prefix.starts_with("var/")
        || definition_prefix.starts_with("/var/")
        || definition_prefix.contains("/var/")
    {
        return ItemKind::Var;
    }
    if definition_prefix.starts_with("proc/")
        || definition_prefix.starts_with("/proc/")
        || definition_prefix.contains("/proc/")
    {
        return ItemKind::Proc;
    }
    if definition_prefix.starts_with("verb/")
        || definition_prefix.starts_with("/verb/")
        || definition_prefix.contains("/verb/")
    {
        return ItemKind::Verb;
    }
    if h.find('(')
        .is_some_and(|open| h.find('{').is_none_or(|brace| open < brace))
    {
        if let Some(open) = h.find('(') {
            if assignment.is_none_or(|index| index > open) {
                return ItemKind::Proc;
            }
        }
    }
    if (h.starts_with('/') && assignment.is_none())
        || (has_children && assignment.is_none())
        || (!h.is_empty() && h.chars().all(ident_continue))
    {
        return ItemKind::Type;
    }
    if h.contains('=') || h.ends_with(')') {
        return ItemKind::Statement;
    }
    ItemKind::Unknown
}

/// Parse indentation and declaration nesting, preserving all tokens for later expression parsing.
/// A malformed indentation transition produces a diagnostic and parsing continues.
pub fn parse(source: &str) -> AstFile {
    let lexed = lex(source);
    // Comments remain in `tokens`, but cannot introduce declarations or alter indentation.
    // A byte-for-byte mask keeps the original source spans valid, including UTF-8 offsets.
    let mut visible = source.as_bytes().to_vec();
    for token in &lexed.tokens {
        if token.kind == TokenKind::Comment
            || (token.kind == TokenKind::String && token.text.contains('\n'))
        {
            for byte in &mut visible[token.span.range()] {
                if !matches!(*byte, b'\r' | b'\n') {
                    *byte = b' ';
                }
            }
        }
    }
    let visible = String::from_utf8(visible).expect("comment mask preserves UTF-8");
    let mut delimiters = visible.as_bytes().to_vec();
    for token in &lexed.tokens {
        if matches!(token.kind, TokenKind::String | TokenKind::Resource) {
            for byte in &mut delimiters[token.span.range()] {
                if !matches!(*byte, b'\r' | b'\n') {
                    *byte = b' ';
                }
            }
        }
    }
    let multiline_literals: Vec<Span> = lexed
        .tokens
        .iter()
        .filter(|token| token.kind == TokenKind::String && token.text.contains('\n'))
        .map(|token| token.span)
        .collect();
    let lines = split_inline_blocks(
        source,
        &structural_lines(&visible, &delimiters, &multiline_literals),
        &delimiters,
    );
    let mut diagnostics = lexed.diagnostics;
    let (items, _) = parse_level(source, &lines, 0, 0, false, &mut diagnostics);
    AstFile {
        items,
        tokens: lexed.tokens,
        diagnostics,
    }
}

/// Structural declaration projection. Lexical spans preserve the same masks,
/// boundaries and diagnostics as the lossless parser, but procedure statements
/// are not allocated unless they contain declaration metadata/static storage.
pub fn parse_declarations(source: &str) -> AstFile {
    parse_declarations_with_sensitive_offsets(source).0
}

/// Declaration projection plus tokens that affect procedure patchability.
/// The frontend reuses this lexical pass instead of lexing every body again.
pub fn parse_declarations_with_sensitive_offsets(source:&str) -> (AstFile,Vec<usize>) {
    let mut visible = source.as_bytes().to_vec();
    let mut delimiters = source.as_bytes().to_vec();
    let mut multiline = Vec::new();
    let mut sensitive = Vec::new();
    // Stream source-backed token spans directly into masks; neither owned
    // tokens nor a full procedure-body token vector survives this projection.
    let mut diagnostics = visit_tokens(source, |token| {
        if token.kind==TokenKind::Resource || matches!(token.text(source),"static"|"const"|"set"|"global"|"{") {sensitive.push(token.span.start);}
        let block = token.kind == TokenKind::String && token.text(source).contains('\n');
        if block { multiline.push(token.span); }
        if token.kind == TokenKind::Comment || block {
            for byte in &mut visible[token.span.range()] { if !matches!(*byte,b'\r'|b'\n') { *byte=b' '; } }
        }
        if matches!(token.kind,TokenKind::Comment|TokenKind::String|TokenKind::Resource) {
            for byte in &mut delimiters[token.span.range()] { if !matches!(*byte,b'\r'|b'\n') { *byte=b' '; } }
        }
    });
    let visible = String::from_utf8(visible).expect("lexical mask preserves UTF-8");
    let lines = split_inline_blocks(source, &structural_lines(&visible, &delimiters, &multiline), &delimiters);
    let (items, _, _) = parse_declaration_level(source, &lines, 0, 0, false, &mut diagnostics);
    (AstFile { items, diagnostics, tokens: Vec::new() },sensitive)
}

fn parse_declaration_level(source: &str, lines: &[Line], mut index: usize, indent: usize, in_body: bool, diagnostics: &mut Vec<Diagnostic>) -> (Vec<Item>, usize, usize) {
    let mut items = Vec::new();
    let mut seen = false;
    let mut final_end = 0;
    while index < lines.len() {
        let line = &lines[index];
        if line.indent < indent || (line.indent > indent && seen) { break; }
        if line.indent > indent { diagnostics.push(Diagnostic { span:Span::new(line.header_start,line.header_end),kind:DiagnosticKind::Indentation,message:"unexpected indentation".into() }); }
        seen = true;
        let header = &source[line.header_start..line.header_end];
        let has_children = index+1 < lines.len() && lines[index+1].indent>line.indent;
        let kind = if in_body { ItemKind::Statement } else { classify(header, has_children) };
        let (children, next, child_end) = if has_children {
            parse_declaration_level(source,lines,index+1,lines[index+1].indent,in_body||matches!(kind,ItemKind::Proc|ItemKind::Verb|ItemKind::Statement),diagnostics)
        } else { (Vec::new(),index+1,line.end) };
        let end = line.end.max(child_end);
        final_end = end;
        let retained = !in_body || header.trim_start().starts_with("set ") || ["var/static/","var/global/","var/const/"].iter().any(|prefix|header.trim_start().starts_with(prefix)) || !children.is_empty();
        if retained { items.push(Item { kind,header:header.to_owned(),span:Span::new(line.header_start,end),header_span:Span::new(line.header_start,line.header_end),indent:line.indent,children }); }
        index=next;
    }
    (items,index,final_end)
}

fn structural_lines(visible: &str, delimiters: &[u8], multiline_literals: &[Span]) -> Vec<Line> {
    let mut lines = Vec::new();
    let mut offset = 0;
    let mut pending: Option<Line> = None;
    let mut depth = 0usize;
    let mut literal_cursor = 0usize;
    for raw in visible.split_inclusive('\n') {
        while multiline_literals
            .get(literal_cursor)
            .is_some_and(|literal| literal.end <= offset)
        {
            literal_cursor += 1;
        }
        let leading = raw
            .bytes()
            .take_while(|b| *b == b' ' || *b == b'\t')
            .count();
        let trimmed = raw[leading..].trim_end_matches(['\r', '\n', ' ', '\t']);
        for byte in &delimiters[offset..offset + raw.len()] {
            match byte {
                b'(' | b'[' => depth += 1,
                b')' | b']' => depth = depth.saturating_sub(1),
                _ => {}
            }
        }
        if !trimmed.is_empty() && !trimmed.starts_with("//") {
            if let Some(line) = pending.as_mut() {
                line.header_end = offset + leading + trimmed.len();
                line.end = offset + raw.len();
            } else {
                // An included file's first line can inherit spaces left by
                // the expanded #include directive. Absolute DM paths declare
                // from the root regardless of that textual indentation.
                let indent = if trimmed.starts_with('/') {
                    0
                } else {
                    raw[..leading]
                        .bytes()
                        .map(|b| if b == b'\t' { 4 } else { 1 })
                        .sum()
                };
                pending = Some(Line {
                    indent,
                    header_start: offset + leading,
                    header_end: offset + leading + trimmed.len(),
                    end: offset + raw.len(),
                });
            }
        } else if let Some(line) = pending.as_mut() {
            line.end = offset + raw.len();
        }
        let mut inside_literal = false;
        for literal in multiline_literals[literal_cursor..]
            .iter()
            .take_while(|literal| literal.start < offset + raw.len())
        {
            if let Some(line) = pending.as_mut() {
                line.header_end = line.header_end.max(literal.end.min(offset + raw.len()));
            }
            inside_literal |= literal.end > offset + raw.len();
        }
        if depth == 0 && !inside_literal {
            if let Some(line) = pending.take() {
                lines.push(line);
            }
        }
        offset += raw.len();
    }
    if let Some(line) = pending {
        lines.push(line);
    }
    lines
}

fn split_inline_blocks(source: &str, lines: &[Line], delimiters: &[u8]) -> Vec<Line> {
    let mut result = Vec::new();
    let mut brace_depth = 0usize;
    let mut initializer_depth = 0usize;
    for line in lines {
        let mut segment_start = line.header_start;
        let mut paren_depth = 0usize;
        let mut inline_do_if = false;
        for at in line.header_start..line.header_end {
            match delimiters[at] {
                b'(' | b'[' => paren_depth += 1,
                b')' | b']' => paren_depth = paren_depth.saturating_sub(1),
                b'{' if paren_depth == 0
                    && (initializer_depth > 0
                        || is_object_initializer(&source[segment_start..at])) =>
                {
                    initializer_depth += 1;
                }
                b'}' if paren_depth == 0 && initializer_depth > 0 => {
                    initializer_depth -= 1;
                }
                b'{' | b'}' | b';' if paren_depth == 0 && initializer_depth == 0 => {
                    let segment = &source[segment_start..at];
                    if let Some(do_at) = (delimiters[at] == b'{' && !inline_do_if)
                        .then(|| inline_if_do_suffix(segment))
                        .flatten()
                    {
                        push_inline_segment(
                            &mut result,
                            source,
                            segment_start,
                            segment_start + do_at,
                            line.indent + brace_depth * 4,
                        );
                        push_inline_segment(
                            &mut result,
                            source,
                            segment_start + do_at,
                            at,
                            line.indent + brace_depth * 4 + 4,
                        );
                        inline_do_if = true;
                    } else {
                        push_inline_segment(
                            &mut result,
                            source,
                            segment_start,
                            at,
                            line.indent + brace_depth * 4 + usize::from(inline_do_if) * 4,
                        );
                    }
                    if delimiters[at] == b'{' {
                        brace_depth += 1;
                    } else if delimiters[at] == b'}' {
                        brace_depth = brace_depth.saturating_sub(1);
                    } else if brace_depth == 0
                        && inline_do_if
                        && segment.trim_start().starts_with("while")
                    {
                        inline_do_if = false;
                    }
                    segment_start = at + 1;
                }
                _ => {}
            }
        }
        let indent = line.indent + brace_depth * 4 + usize::from(inline_do_if) * 4;
        if let Some(body_start) =
            inline_proc_body_start(source, delimiters, segment_start, line.header_end)
        {
            push_inline_segment(&mut result, source, segment_start, body_start, indent);
            push_inline_segment(&mut result, source, body_start, line.header_end, indent + 4);
        } else {
            push_inline_segment(&mut result, source, segment_start, line.header_end, indent);
        }
    }
    result
}

fn inline_proc_body_start(
    source: &str,
    delimiters: &[u8],
    start: usize,
    end: usize,
) -> Option<usize> {
    let segment = source[start..end].trim_start();
    let opening = segment.find('(')?;
    let prefix = segment[..opening].trim();
    if !(prefix.starts_with("proc/")
        || prefix.starts_with("verb/")
        || prefix.starts_with("/proc/")
        || prefix.starts_with("/verb/")
        || prefix.contains("/proc/")
        || prefix.contains("/verb/")
        || (prefix.starts_with('/')
            && !prefix.chars().any(char::is_whitespace)
            && top_level_assignment_index(prefix).is_none()))
    {
        return None;
    }
    let absolute_open = start + source[start..end].find('(')?;
    let mut depth = 0usize;
    for at in absolute_open..end {
        match delimiters[at] {
            b'(' => depth += 1,
            b')' => {
                depth = depth.saturating_sub(1);
                if depth == 0 {
                    let body_start =
                        at + 1 + source[at + 1..end].len() - source[at + 1..end].trim_start().len();
                    let body = &source[body_start..end];
                    if !body.is_empty() && !body.starts_with("as ") {
                        return Some(body_start);
                    }
                    return None;
                }
            }
            _ => {}
        }
    }
    None
}

fn inline_if_do_suffix(segment: &str) -> Option<usize> {
    let trimmed = segment.trim();
    if !(trimmed.starts_with("if(") || trimmed.starts_with("if (")) || !trimmed.ends_with("do") {
        return None;
    }
    let at = segment.rfind("do")?;
    segment[..at]
        .chars()
        .next_back()
        .filter(|ch| ch.is_whitespace())
        .map(|_| at)
}

fn is_object_initializer(prefix: &str) -> bool {
    let token = prefix.split_whitespace().next_back().unwrap_or("");
    token.contains('/')
        && !token.ends_with(')')
        && !token.ends_with(']')
        && (prefix.contains('=')
            || lex_spans(prefix)
                .tokens
                .iter()
                .any(|token| token.kind == TokenKind::Ident && token.text(prefix) == "new")
            || prefix.contains('(')
            || prefix.contains(','))
}

fn push_inline_segment(
    lines: &mut Vec<Line>,
    source: &str,
    start: usize,
    end: usize,
    indent: usize,
) {
    let segment = &source[start..end];
    let trimmed_start = segment.len() - segment.trim_start().len();
    let trimmed_end = segment.trim_end().len();
    if trimmed_end <= trimmed_start {
        return;
    }
    lines.push(Line {
        indent,
        header_start: start + trimmed_start,
        header_end: start + trimmed_end,
        end: start + trimmed_end,
    });
}

fn parse_level(
    source: &str,
    lines: &[Line],
    mut index: usize,
    indent: usize,
    in_body: bool,
    diagnostics: &mut Vec<Diagnostic>,
) -> (Vec<Item>, usize) {
    let mut items = Vec::new();
    while index < lines.len() {
        let line = &lines[index];
        if line.indent < indent {
            break;
        }
        if line.indent > indent && !items.is_empty() {
            break;
        }
        if line.indent > indent {
            diagnostics.push(Diagnostic {
                span: Span::new(line.header_start, line.header_end),
                kind: DiagnosticKind::Indentation,
                message: "unexpected indentation".into(),
            });
        }
        let mut end = line.end;
        let mut children = Vec::new();
        let has_children = index + 1 < lines.len() && lines[index + 1].indent > line.indent;
        let header = source[line.header_start..line.header_end].to_owned();
        let kind = if in_body {
            ItemKind::Statement
        } else {
            classify(&header, has_children)
        };
        if has_children {
            let (parsed, next) = parse_level(
                source,
                lines,
                index + 1,
                lines[index + 1].indent,
                in_body || matches!(kind, ItemKind::Proc | ItemKind::Verb | ItemKind::Statement),
                diagnostics,
            );
            children = parsed;
            index = next;
            end = children.last().map_or(end, |child| child.span.end);
        } else {
            index += 1;
        }
        items.push(Item {
            kind,
            header,
            span: Span::new(line.header_start, end),
            header_span: Span::new(line.header_start, line.header_end),
            indent: line.indent,
            children,
        });
    }
    (items, index)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn inline_class_fields_do_not_define_a_procedure() {
        let source = "/datum/admin_verb/player_panel_new { name=\"Panel\"; description=\"Open\"; category=\"Admin\"; permissions=(((1<<18)-1)); verb_path=/client/proc/player_panel; enabled=1; }\n";
        assert_eq!(classify(source.trim(), true), ItemKind::Type);
        let ast = parse(source);
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        assert_eq!(ast.items[0].kind, ItemKind::Type);
        assert_eq!(ast.items[0].header, "/datum/admin_verb/player_panel_new");
        assert_eq!(ast.items[0].children.len(), 6);
    }

    #[test]
    fn implicit_inline_proc_defaults_are_not_absolute_assignments() {
        let ast =
            parse("/turf/floor/update_graphic(list/add = null, text/value = \"a=b\") return 0\n");
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        assert_eq!(ast.items[0].kind, ItemKind::Proc);
        assert_eq!(
            ast.items[0].header,
            "/turf/floor/update_graphic(list/add = null, text/value = \"a=b\")"
        );
        assert_eq!(ast.items[0].children[0].header, "return 0");
        assert_eq!(
            top_level_assignment_index("/datum/name = \"a=b\""),
            Some(12)
        );
        assert_eq!(
            top_level_assignment_index("/datum/proc/run(x = \"a=b\")"),
            None
        );
    }

    #[test]
    fn absolute_assignment_is_not_a_type_declaration() {
        let ast = parse("/datum/language/human/syllables = list(\n    \"one\", \"two\"\n)\n");
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        assert_eq!(ast.items[0].kind, ItemKind::Statement);
    }

    #[test]
    fn inline_proc_body_is_separate_from_signature() {
        let source = "/proc/rustg_get_version() return call_ext((__rust_g || __detect_rust_g()), \"get_version\")()\n/proc/next()\n    return 1\n";
        let ast = parse(source);
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        assert_eq!(ast.items[0].kind, ItemKind::Proc);
        assert_eq!(ast.items[0].header, "/proc/rustg_get_version()");
        assert_eq!(ast.items[0].children.len(), 1);
        assert_eq!(
            ast.items[0].children[0].header,
            "return call_ext((__rust_g || __detect_rust_g()), \"get_version\")()"
        );
        assert_eq!(ast.items[1].header, "/proc/next()");
    }

    #[test]
    fn lex_is_lossless_and_spans_are_bytes() {
        let src = "/obj/é\n  var/icon = 'a.dmi' // test\n";
        let result = lex(src);
        assert_eq!(
            result
                .tokens
                .iter()
                .map(|t| t.text.as_str())
                .collect::<String>(),
            src
        );
        assert!(result.tokens.iter().all(|t| &src[t.span.range()] == t.text));
        assert!(result.tokens.iter().any(|t| t.kind == TokenKind::Resource));
    }

    #[test]
    fn parse_nested_declarations_and_reopening_order() {
        let src = "/obj\n  var/name = \"first\"\n  proc/test(x)\n    return x\n/obj\n  var/name = \"second\"\n";
        let ast = parse(src);
        assert_eq!(ast.items.len(), 2);
        assert_eq!(ast.items[0].kind, ItemKind::Type);
        assert_eq!(ast.items[0].children[0].kind, ItemKind::Var);
        assert_eq!(ast.items[0].children[1].kind, ItemKind::Proc);
        assert_eq!(
            ast.items[0].children[1].children[0].kind,
            ItemKind::Statement
        );
        assert!(ast.diagnostics.is_empty());
    }

    #[test]
    fn multiline_proc_signature_and_list_expression_are_one_header_each() {
        let source = "/proc/send_announcement(\n    text,\n    title = \"A (title)\",\n)\n    var/list/colors = list(\n        1,\n        2,\n    )\n    return colors\n";
        let ast = parse(source);
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        assert_eq!(ast.items.len(), 1);
        assert_eq!(ast.items[0].kind, ItemKind::Proc);
        assert!(ast.items[0].header.contains("title ="));
        assert_eq!(ast.items[0].children.len(), 2);
        assert!(ast.items[0].children[0].header.contains("2,"));
    }

    #[test]
    fn braces_and_semicolons_create_nested_statements() {
        let source = "/proc/test() { var/x = 1; if(x) { foo(); bar(); } return x; }\n";
        let ast = parse(source);
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        assert_eq!(ast.items.len(), 1);
        let proc = &ast.items[0];
        assert_eq!(proc.kind, ItemKind::Proc);
        assert_eq!(proc.children.len(), 3);
        assert_eq!(proc.children[1].header, "if(x)");
        assert_eq!(proc.children[1].children.len(), 2);
        let body = parse_proc_body(proc);
        assert!(body.diagnostics.is_empty(), "{:?}", body.diagnostics);
        assert_eq!(body.statements.len(), 3);
    }

    #[test]
    fn inline_proc_with_multiline_list_keeps_call_together() {
        let source = "/datum/globals/var/list/x; /datum/globals/proc/InitX(){x =list(\n NORTHEAST,\n NORTHWEST\n); order += \"x\";}\n";
        let ast = parse(source);
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        assert_eq!(ast.items.len(), 2, "{:?}", ast.items);
        let proc = &ast.items[1];
        assert_eq!(proc.kind, ItemKind::Proc);
        assert_eq!(proc.children.len(), 2, "{:?}", proc.children);
        assert!(proc.children[0].header.contains("NORTHWEST"));
        let body = parse_proc_body(proc);
        assert!(body.diagnostics.is_empty(), "{:?}", body.diagnostics);
    }

    #[test]
    fn macro_generated_inline_proc_with_tabbed_multiline_list() {
        let source = "/datum/controller/global_vars/var/global/list/gzn_check; /datum/controller/global_vars/proc/InitGlobalgzn_check(){gzn_check =list(\n\tNORTH,\n\tSOUTH\n);\tgvars_datum_init_order += \"gzn_check\";}\n/datum/controller/global_vars/var/global/list/csrfz_check; /datum/controller/global_vars/proc/InitGlobalcsrfz_check(){csrfz_check =list(\n\tNORTHEAST,\n\tNORTHWEST,\n\t(NORTH|UP),\n\t(SOUTH|DOWN)\n);\tgvars_datum_init_order += \"csrfz_check\";}\n";
        let ast = parse(source);
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let proc = &ast.items[3];
        assert_eq!(proc.children.len(), 2, "{:?}", proc.children);
        let body = parse_proc_body(proc);
        assert!(body.diagnostics.is_empty(), "{:?}", body.diagnostics);
    }

    #[test]
    fn include_footprint_before_absolute_path_does_not_attach_to_previous_proc() {
        let source = "/datum/globals/proc/init(){x = list(\nNORTH\n); order += 1;}\n\n                                        /var/__verdigris\n/proc/detect()\n    return 1\n";
        let ast = parse(source);
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        assert_eq!(ast.items.len(), 3, "{:?}", ast.items);
        assert_eq!(ast.items[0].children.len(), 2);
        assert_eq!(ast.items[1].kind, ItemKind::Var);
        assert_eq!(ast.items[1].indent, 0);
    }

    #[test]
    fn object_initializer_braces_do_not_create_statement_blocks() {
        let source = "/proc/planes()\n    . += new /atom/movable/screen/plane_master{plane = 11}\n    . += new /atom/movable/screen/plane_master{plane = 15; name = \"light\"}\n    return .\n";
        let ast = parse(source);
        let proc = &ast.items[0];
        assert_eq!(proc.children.len(), 3, "{:?}", proc.children);
        assert!(proc.children.iter().all(|item| item.children.is_empty()));
        let body = parse_proc_body(proc);
        assert!(body
            .diagnostics
            .iter()
            .all(|d| d.message != "unsupported statement block"));
    }

    #[test]
    fn object_initializer_expression_preserves_field_overrides() {
        let parsed = parse_expression("new /datum/object_probe{value = 11; name = \"probe\"}");
        assert!(parsed.diagnostics.is_empty(), "{:?}", parsed.diagnostics);
        let expr = parsed.expr.unwrap();
        let ExprKind::Unary { op, value } = expr.kind else {
            panic!("expected new expression");
        };
        assert_eq!(op, "new");
        let ExprKind::ObjectInitializer { object, fields } = value.kind else {
            panic!("expected object initializer");
        };
        assert!(
            matches!(object.kind, ExprKind::TypePath(ref path) if path == "/datum/object_probe")
        );
        assert_eq!(fields.len(), 2);
        assert_eq!(fields[0].0, "value");
        assert_eq!(fields[1].0, "name");
    }

    #[test]
    fn dynamic_colon_member_parses_inside_initial_call() {
        let parsed = parse_expression("initial(recipe.result:name)");
        assert!(parsed.diagnostics.is_empty(), "{:?}", parsed.diagnostics);
        let ExprKind::Call { args, .. } = parsed.expr.unwrap().kind else {
            panic!("expected call");
        };
        assert!(
            matches!(&args[0].kind, ExprKind::Member { selector, via_colon: true, .. } if selector == "name")
        );
    }

    #[test]
    fn dynamic_colon_members_parse_in_ternary_branches() {
        for source in [
            "ismob(target) ? target:client : null",
            "recipe ? initial(recipe.result:name) : null",
        ] {
            let parsed = parse_expression(source);
            assert!(
                parsed.diagnostics.is_empty(),
                "{source}: {:?}",
                parsed.diagnostics
            );
            assert!(matches!(
                parsed.expr.unwrap().kind,
                ExprKind::Conditional { .. }
            ));
        }
    }

    #[test]
    fn inline_if_do_macro_braces_preserve_do_while_pairing() {
        let source = "/proc/test()\n    if(length(protected_jobs))\tdo { if(!restricted_jobs) { restricted_jobs = list(); } restricted_jobs |= protected_jobs; } while(0)\n    return 1\n";
        let ast = parse(source);
        let proc = &ast.items[0];
        assert_eq!(proc.children[0].header, "if(length(protected_jobs))");
        assert_eq!(proc.children[0].children[0].header, "do");
        assert_eq!(proc.children[0].children[1].header, "while(0)");
        assert_eq!(proc.children[1].header, "return 1");
        let body = parse_proc_body(proc);
        assert!(body.diagnostics.is_empty(), "{:?}", body.diagnostics);
    }

    #[test]
    fn bare_relative_type_declaration_without_children() {
        let ast = parse("/mob/living/simple_mob/humanoid/clown\n\tclown\n\tname = \"Clown\"\n");
        assert!(ast.diagnostics.is_empty());
        assert_eq!(ast.items[0].children[0].kind, ItemKind::Type);
        assert_eq!(ast.items[0].children[0].header, "clown");
        assert_eq!(ast.items[0].children[1].kind, ItemKind::Statement);
    }

    #[test]
    fn call_valued_override_is_not_implicit_proc() {
        let ast = parse("/datum/example\n    items = list(1, 2)\n    New(value = list())\n        return ..()\n");
        assert!(ast.diagnostics.is_empty());
        assert_eq!(ast.items[0].children[0].kind, ItemKind::Statement);
        assert_eq!(ast.items[0].children[1].kind, ItemKind::Proc);
    }

    #[test]
    fn proc_paths_inside_assignment_values_do_not_declare_procedures() {
        let ast = parse("/datum/interaction/example\n    requires = list(/proc/check, /verb/inspect, /var/flag)\n    /datum/interaction/example/proc/check(value = /proc/fallback)\n        return value\n");
        assert!(ast.diagnostics.is_empty());
        assert_eq!(ast.items[0].children[0].kind, ItemKind::Statement);
        assert_eq!(ast.items[1].kind, ItemKind::Proc);
    }

    #[test]
    fn nameof_dot_proc_path_is_one_type_path_expression() {
        let parsed = parse_expression("nameof(/datum.proc/find_references)");
        assert!(parsed.diagnostics.is_empty(), "{:?}", parsed.diagnostics);
        let Some(Expr {
            kind: ExprKind::Call { args, .. },
            ..
        }) = parsed.expr
        else {
            panic!("expected nameof call");
        };
        assert_eq!(args.len(), 1);
        assert!(
            matches!(&args[0].kind, ExprKind::TypePath(path) if path == "/datum.proc/find_references")
        );
    }

    #[test]
    fn type_path_stops_before_spaced_in_operator() {
        let parsed = parse_expression("pick(/turf in orange(6))");
        assert!(parsed.diagnostics.is_empty(), "{:?}", parsed.diagnostics);
        let Some(Expr {
            kind: ExprKind::Call { args, .. },
            ..
        }) = parsed.expr
        else {
            panic!("expected pick call");
        };
        let [Expr {
            kind: ExprKind::Binary { op, lhs, rhs },
            ..
        }] = args.as_slice()
        else {
            panic!("expected membership argument: {args:?}");
        };
        assert_eq!(op, "in");
        assert!(matches!(&lhs.kind, ExprKind::TypePath(path) if path == "/turf"));
        assert!(
            matches!(&rhs.kind, ExprKind::Call { callee, .. } if matches!(&callee.kind, ExprKind::Ident(name) if name == "orange"))
        );
        let path = parse_expression("/datum.proc/find_references");
        assert!(path.diagnostics.is_empty());
        assert!(
            matches!(path.expr.unwrap().kind, ExprKind::TypePath(path) if path == "/datum.proc/find_references")
        );
    }

    #[test]
    fn trailing_type_slash_is_canonical_in_values_and_constructors() {
        let path = parse_expression("/obj/trailing_probe/");
        assert!(path.diagnostics.is_empty());
        assert!(
            matches!(path.expr.unwrap().kind, ExprKind::TypePath(path) if path == "/obj/trailing_probe")
        );
        let new = parse_expression("new /obj/trailing_probe/()");
        assert!(new.diagnostics.is_empty(), "{:?}", new.diagnostics);
        let Some(Expr {
            kind: ExprKind::Unary { op, value },
            ..
        }) = new.expr
        else {
            panic!("expected new expression");
        };
        assert_eq!(op, "new");
        assert!(
            matches!(&value.kind, ExprKind::Call { callee, args } if args.is_empty() && matches!(&callee.kind, ExprKind::TypePath(path) if path == "/obj/trailing_probe"))
        );
    }

    #[test]
    fn semicolons_inside_for_control_are_not_split() {
        let source = "/proc/test() { for(var/i = 0; i < 3; i++) { tick(); } }\n";
        let ast = parse(source);
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        assert_eq!(ast.items[0].children.len(), 1);
        assert!(ast.items[0].children[0].header.starts_with("for("));
        assert_eq!(ast.items[0].children[0].children.len(), 1);
    }

    #[test]
    fn lexer_reports_unterminated_resource() {
        assert_eq!(lex("'x.dmi").diagnostics.len(), 1);
    }

    #[test]
    fn expressions_preserve_precedence_and_calls() {
        let parsed = parse_expression("foo(2 + 3 * 4, src.name)");
        assert!(parsed.diagnostics.is_empty(), "{:?}", parsed.diagnostics);
        let ExprKind::Call { args, .. } = parsed.expr.unwrap().kind else {
            panic!("expected call")
        };
        assert_eq!(args.len(), 2);
        let ExprKind::Binary { op, rhs, .. } = &args[0].kind else {
            panic!("expected binary")
        };
        assert_eq!(op, "+");
        assert!(matches!(rhs.kind, ExprKind::Binary { ref op, .. } if op == "*"));
        assert!(matches!(args[1].kind, ExprKind::Member { .. }));
    }

    #[test]
    fn expression_parses_nested_ternary() {
        let parsed = parse_expression("foo ? bar : baz");
        assert!(parsed.diagnostics.is_empty());
        assert!(matches!(
            parsed.expr.unwrap().kind,
            ExprKind::Conditional { .. }
        ));
        let nested = parse_expression("foo ? 1 : bar ? 2 : 3");
        assert!(nested.diagnostics.is_empty());
        assert!(matches!(
            nested.expr.unwrap().kind,
            ExprKind::Conditional { .. }
        ));
    }

    #[test]
    fn procedure_body_calls_and_locals_are_statements() {
        let ast = parse("/obj/proc/test()\n    var/x = 1\n    helper()\n    if(x)\n        proc_name()\n/obj/proc/next()\n    return 2\n");
        assert_eq!(ast.items.len(), 2);
        assert_eq!(ast.items[0].kind, ItemKind::Proc);
        assert!(ast.items[0]
            .children
            .iter()
            .all(|item| item.kind == ItemKind::Statement));
        assert_eq!(
            ast.items[0].children[2].children[0].kind,
            ItemKind::Statement
        );
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    }

    #[test]
    fn multiline_comments_do_not_create_declarations() {
        let ast = parse("/*\n/obj/imaginary\n*/\n/obj/real // trailing\n    var/name = \"real\"\n");
        assert_eq!(ast.items.len(), 1);
        assert_eq!(ast.items[0].header, "/obj/real");
        assert_eq!(ast.items[0].children[0].kind, ItemKind::Var);
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    }

    #[test]
    fn inherited_calls_membership_and_assignments() {
        for source in [
            "..()",
            "x in items",
            "x += 2",
            "new /obj/item(1)",
            "new(user, src)",
            "new",
        ] {
            let parsed = parse_expression(source);
            assert!(
                parsed.diagnostics.is_empty(),
                "{source}: {:?}",
                parsed.diagnostics
            );
            assert!(parsed.expr.is_some(), "{source}");
        }
        let inherited = parse_expression("..()").expr.unwrap();
        assert!(
            matches!(inherited.kind, ExprKind::Call { callee, .. } if matches!(callee.kind, ExprKind::Ident(ref name) if name == ".."))
        );
    }

    #[test]
    fn raw_regex_string_is_one_literal_token() {
        let parsed = parse_expression("@\"^\\w+$\"");
        assert!(parsed.diagnostics.is_empty(), "{:?}", parsed.diagnostics);
        assert!(matches!(
            parsed.expr.unwrap().kind,
            ExprKind::Literal(value) if value == "@\"^\\w+$\""
        ));
    }

    #[test]
    fn raw_quote_after_backslash_ends_string() {
        let source = r#"@"\" + 1"#;
        let tokens = lex_spans(source);
        assert!(tokens.diagnostics.is_empty(), "{:?}", tokens.diagnostics);
        let literals = tokens
            .tokens
            .iter()
            .filter(|token| token.kind == TokenKind::String)
            .map(|token| token.text(source))
            .collect::<Vec<_>>();
        assert_eq!(literals, [r#"@"\""#]);
        let parsed = parse_expression(source);
        assert!(parsed.diagnostics.is_empty(), "{:?}", parsed.diagnostics);
    }

    #[test]
    fn nested_block_comments_hide_inner_closer() {
        let source = "/* outer\n  /* inner */\n  /obj/hidden\n*/\n/obj/real\n";
        let ast = parse(source);
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        assert_eq!(ast.items.len(), 1);
        assert_eq!(ast.items[0].header, "/obj/real");
    }

    #[test]
    fn byond_infinity_is_one_numeric_literal() {
        let source = "1.#INF";
        let tokens = lex_spans(source);
        assert!(tokens.diagnostics.is_empty(), "{:?}", tokens.diagnostics);
        assert_eq!(tokens.tokens.len(), 1);
        assert_eq!(tokens.tokens[0].kind, TokenKind::Number);
        let parsed = parse_expression(source);
        assert!(parsed.diagnostics.is_empty(), "{:?}", parsed.diagnostics);
        assert!(matches!(parsed.expr.unwrap().kind, ExprKind::Literal(value) if value == source));
    }

    #[test]
    fn exponent_is_right_associative_and_binds_tighter_than_multiply() {
        let parsed = parse_expression("2 * 3 ** 2 ** 1");
        assert!(parsed.diagnostics.is_empty(), "{:?}", parsed.diagnostics);
        let ExprKind::Binary { op, rhs, .. } = parsed.expr.unwrap().kind else {
            panic!("expected multiplication")
        };
        assert_eq!(op, "*");
        let ExprKind::Binary { op, rhs, .. } = rhs.kind else {
            panic!("expected exponent")
        };
        assert_eq!(op, "**");
        assert!(matches!(rhs.kind, ExprKind::Binary { op, .. } if op == "**"));
    }

    #[test]
    fn safe_navigation_parses_distinctly() {
        let member = parse_expression("item?.name");
        assert!(member.diagnostics.is_empty(), "{:?}", member.diagnostics);
        assert!(matches!(
            member.expr.unwrap().kind,
            ExprKind::SafeMember { .. }
        ));
        let index = parse_expression("items?[1]");
        assert!(index.diagnostics.is_empty(), "{:?}", index.diagnostics);
        assert!(matches!(
            index.expr.unwrap().kind,
            ExprKind::SafeIndex { .. }
        ));
    }

    #[test]
    fn trailing_comma_in_call_and_constructor_is_accepted() {
        for source in ["list(1, 2,)", "new /datum/x(1, 2,)"] {
            let parsed = parse_expression(source);
            assert!(
                parsed.diagnostics.is_empty(),
                "{source}: {:?}",
                parsed.diagnostics
            );
            assert!(parsed.expr.is_some());
        }
    }

    #[test]
    fn prefix_and_postfix_increment_parse_distinctly() {
        for (source, expected) in [
            ("i++", "post++"),
            ("i--", "post--"),
            ("++i", "pre++"),
            ("--i", "pre--"),
            ("items[index]++", "post++"),
        ] {
            let parsed = parse_expression(source);
            assert!(
                parsed.diagnostics.is_empty(),
                "{source}: {:?}",
                parsed.diagnostics
            );
            assert!(
                matches!(parsed.expr.unwrap().kind, ExprKind::Unary { op, .. } if op == expected)
            );
        }
        let separated = parse_expression("i + +j");
        assert!(matches!(
            separated.expr.unwrap().kind,
            ExprKind::Binary { .. }
        ));
    }

    #[test]
    fn proc_ref_nameof_nested_constructor_parses() {
        let parsed = parse_expression("_addtimer(new /datum/callback(src, (nameof(.proc/standard_reboot))), report_delay + extra_delay, file=__FILE__, line=__LINE__)");
        assert!(parsed.diagnostics.is_empty(), "{:?}", parsed.diagnostics);
        assert!(parsed.expr.is_some());
    }

    #[test]
    fn block_string_and_nested_interpolation_are_single_tokens() {
        let source = "var/message = {\"A [time2text(entry[\"time\"], \"MMM DD\")]\n/obj/not_a_declaration\nB\"}\n/obj/real\n";
        let tokens = lex_spans(source);
        assert!(tokens.diagnostics.is_empty(), "{:?}", tokens.diagnostics);
        let literal = tokens
            .tokens
            .iter()
            .find(|token| token.kind == TokenKind::String)
            .unwrap();
        assert!(literal.text(source).contains("/obj/not_a_declaration"));
        assert!(literal.text(source).ends_with("\"}"));
        let ast = parse(source);
        assert_eq!(ast.items.len(), 2);
        assert_eq!(ast.items[1].header, "/obj/real");
    }

    #[test]
    fn nested_string_interpolation_can_contain_quoted_nested_arguments() {
        let source = r#""outer [flag ? " inner [name ? "yes" : "no"]" : ""] tail""#;
        let lexed = lex(source);
        assert!(lexed.diagnostics.is_empty(), "{:?}", lexed.diagnostics);
        assert_eq!(lexed.tokens.len(), 1);
        assert_eq!(lexed.tokens[0].kind, TokenKind::String);
        assert_eq!(lexed.tokens[0].text, source);
    }

    #[test]
    fn span_lexer_matches_owned_tokens() {
        let source = "/obj/proc/test() // comment\n return \"[src.name]\"\n";
        let owned = lex(source);
        let borrowed = lex_spans(source);
        assert_eq!(owned.diagnostics, borrowed.diagnostics);
        assert_eq!(owned.tokens.len(), borrowed.tokens.len());
        for (owned, borrowed) in owned.tokens.iter().zip(borrowed.tokens) {
            assert_eq!(owned.kind, borrowed.kind);
            assert_eq!(owned.span, borrowed.span);
            assert_eq!(owned.text, borrowed.text(source));
        }
    }

    #[test]
    fn signed_decimal_exponents_do_not_consume_hex_subtraction() {
        for source in ["1e-4", "1E+6", "0.125e-3"] {
            let tokens = lex_spans(source);
            assert_eq!(tokens.tokens.len(), 1, "{source}");
            assert_eq!(tokens.tokens[0].kind, TokenKind::Number);
            assert_eq!(tokens.tokens[0].text(source), source);
            assert!(parse_expression(source).diagnostics.is_empty(), "{source}");
        }
        assert_eq!(lex_spans("0x1e-4").tokens.len(), 3);
    }

    #[test]
    fn raw_single_quoted_patterns_are_strings_not_resources() {
        let source = r#"@'^"[A-z]*"[\s]*=[\s]*\([\s]*\n'"#;
        let lexed = lex_spans(source);
        assert!(lexed.diagnostics.is_empty());
        assert_eq!(lexed.tokens.len(), 1);
        assert_eq!(lexed.tokens[0].kind, TokenKind::String);
    }

    #[test]
    fn deepquarry_declaration_shapes_preserve_order_and_paths() {
        let source = "/datum/example\n    var/static/list/cache\n    proc/Initialize(mapload)\n        return ..()\n/datum/example/var/global/count = 1\n/datum/example/proc/Initialize(mapload)\n    return 2\n";
        let ast = parse(source);
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        assert_eq!(ast.items.len(), 3);
        assert_eq!(ast.items[0].kind, ItemKind::Type);
        assert_eq!(ast.items[0].children[0].kind, ItemKind::Var);
        assert_eq!(ast.items[0].children[1].kind, ItemKind::Proc);
        assert_eq!(ast.items[1].kind, ItemKind::Var);
        assert_eq!(ast.items[2].kind, ItemKind::Proc);
        assert_eq!(
            ast.items[2].header,
            "/datum/example/proc/Initialize(mapload)"
        );
    }

    #[test]
    fn unterminated_block_string_has_typed_lexical_diagnostic() {
        let lexed = lex_spans("var/x = {\"unfinished\ntext\n");
        assert_eq!(lexed.diagnostics.len(), 1);
        assert_eq!(lexed.diagnostics[0].kind, DiagnosticKind::Lexical);
    }
}

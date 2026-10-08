use super::*;

fn ident_start(c: char) -> bool {
    c == '_' || c.is_alphabetic()
}
pub(super) fn ident_continue(c: char) -> bool {
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
        // Raw DM strings preserve regex brackets/backslashes as text. They
        // cannot enter interpolation: otherwise an escaped regex closing
        // bracket may leave a fabricated expression open across declarations.
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
        } else if let Some(stripped) = rest.strip_prefix("@'") {
            let close = stripped.find('\'').map(|at| at + 3);
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

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
        // Raw single-line quotes cannot use a backslash to continue a line.
        // Raw block strings retain their multiline grammar.
        if raw && !block && matches!(ch, '\r' | '\n') {
            return None;
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
    visit_tokens_while(source, |token| {
        visitor(token);
        true
    })
}

/// Same lexer with caller-controlled early completion; no token roster allocation.
pub fn visit_tokens_while(
    source: &str,
    mut visitor: impl FnMut(SpanToken) -> bool,
) -> Vec<Diagnostic> {
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
        } else if let Some((kind, length, unterminated)) = literal_or_comment(rest) {
            (kind, pos + length, unterminated)
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
        if !visitor(SpanToken {
            kind,
            span: Span::new(pos, end),
        }) {
            break;
        }
        pos = end;
    }
    diagnostics
}

/// First nontrivia lookahead token after an exact lexer boundary. Lexical errors
/// before that token decline the answer rather than inventing a cursor.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum LexerLookahead {
    Token(SpanToken),
    End,
    Unknown,
}
pub fn next_significant_token(source: &str, after: usize) -> Option<SpanToken> {
    match lookahead_after(source, after) {
        LexerLookahead::Token(token) => Some(token),
        _ => None,
    }
}
pub fn lookahead_after(source: &str, after: usize) -> LexerLookahead {
    let Some(suffix) = source.get(after..) else {
        return LexerLookahead::Unknown;
    };
    let mut found = None;
    let diagnostics = visit_tokens_while(suffix, |mut token| {
        if matches!(
            token.kind,
            TokenKind::Whitespace | TokenKind::Newline | TokenKind::Comment
        ) {
            return true;
        }
        token.span.start += after;
        token.span.end += after;
        found = Some(token);
        false
    });
    if !diagnostics.is_empty() {
        LexerLookahead::Unknown
    } else {
        found.map_or(LexerLookahead::End, LexerLookahead::Token)
    }
}

#[cfg(test)]
mod cursor_tests {
    use super::*;

    #[test]
    fn lookahead_uses_trivia_rules_and_stops_before_later_errors() {
        let source = "input\n // comment\n /* block */ return \"unterminated";
        let token = next_significant_token(source, "input".len()).unwrap();
        assert_eq!(&source[token.span.start..token.span.end], "return");
        assert!(next_significant_token("input /* unfinished", 5).is_none());
        assert!(next_significant_token("input\n // end", 5).is_none());
        assert!(next_significant_token("é", 1).is_none());
    }
}

fn literal_or_comment(rest: &str) -> Option<(TokenKind, usize, bool)> {
    let c = rest.chars().next()?;
    let result = if rest.starts_with("//") {
        (
            TokenKind::Comment,
            rest.find(['\r', '\n']).unwrap_or(rest.len()),
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
            (TokenKind::Comment, cursor, false)
        } else {
            (TokenKind::Comment, rest.len(), true)
        }
    } else if let Some(stripped) = rest.strip_prefix("@'") {
        let close = stripped.find('\'').map(|at| at + 3);
        (
            TokenKind::String,
            close.unwrap_or(rest.len()),
            close.is_none(),
        )
    } else if rest.starts_with("@{\"") {
        let close = quoted_end(&rest[1..], true, true);
        (
            TokenKind::String,
            close.map_or(rest.len(), |end| end + 1),
            close.is_none(),
        )
    } else if rest.starts_with("{\"") {
        let close = quoted_end(rest, true, false);
        (
            TokenKind::String,
            close.unwrap_or(rest.len()),
            close.is_none(),
        )
    } else if rest.starts_with("@\"") {
        let close = quoted_end(&rest[1..], false, true);
        (
            TokenKind::String,
            close.map_or(rest.len(), |end| end + 1),
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
        (kind, close.unwrap_or(rest.len()), close.is_none())
    } else {
        return None;
    };
    Some(result)
}

/// Visit only comments, sharing exact literal boundaries with the full lexer.
/// Full lexical diagnostics remain available through `visit_tokens`.
pub fn visit_comment_spans(source: &str, mut visitor: impl FnMut(Span)) {
    let bytes = source.as_bytes();
    let mut pos = 0;
    while pos < bytes.len() {
        // SIMD search skips ordinary runs. All five candidates are ASCII and
        // therefore safe UTF-8 slice boundaries; literal grammar stays shared.
        let rest = &bytes[pos..];
        let literal = memchr::memchr3(b'/', b'"', b'\'', rest);
        let raw_or_block = memchr::memchr2(b'@', b'{', rest);
        let next = match (literal, raw_or_block) {
            (Some(left), Some(right)) => left.min(right),
            (Some(offset), None) | (None, Some(offset)) => offset,
            (None, None) => break,
        };
        pos += next;
        if let Some((kind, length, _)) = literal_or_comment(&source[pos..]) {
            if kind == TokenKind::Comment {
                visitor(Span::new(pos, pos + length));
            }
            pos += length;
        } else {
            pos += 1;
        }
    }
}
#[cfg(test)]
mod comment_tests {
    use super::*;
    fn selective(source: &str) -> Vec<Span> {
        let mut spans = Vec::new();
        visit_comment_spans(source, |span| spans.push(span));
        spans
    }
    #[test]
    fn comments_exclude_literals_and_preserve_nested_extent() {
        let source = r#"alpha = "// not comment"; '/*resource*/'; @"/*raw*/"; {"//block"} /* outer /* inner */ end */ // tail
beta"#;
        let spans = selective(source);
        let texts: Vec<_> = spans.iter().map(|span| &source[span.range()]).collect();
        assert_eq!(texts, ["/* outer /* inner */ end */", "// tail"]);
    }
    #[test]
    fn boundary_search_handles_long_unicode_runs_and_adjacent_raw_markers() {
        let ordinary = "雪αidentifier123 ".repeat(513);
        let source = format!("{ordinary}@{{\"/* literal */\"}}@'// resource'@@/ /* nested /* inner */ end */\n{ordinary}// tail");
        let spans = selective(&source);
        assert_eq!(
            spans
                .iter()
                .map(|span| &source[span.range()])
                .collect::<Vec<_>>(),
            ["/* nested /* inner */ end */", "// tail"]
        );
        let mut expected = Vec::new();
        visit_tokens(&source, |token| {
            if token.kind == TokenKind::Comment {
                expected.push(token.span);
            }
        });
        assert_eq!(spans, expected);
    }
    #[test]
    fn selective_matches_full_lexer_at_every_utf8_prefix() {
        let fixtures = [
            "\u{3b1} / x // tail\r\n/* outer /* nested */ remaining */ \u{96ea}",
            r#""hello [list("nested ["deep"]", 'resource')] // text" // real"#,
            r#"@"regex [\] /*literal*/" @'raw/*resource*/' @{"raw // block"} /*yes*/"#,
            r#"{"multiline
["inner /* text */"]"} 'escaped\'//resource' // actual"#,
            "/* unterminated nested /* x */",
            "\"unterminated [\"nested\" // x",
            "ordinary identifiers_123 0xABC 1e-4 #INF /*end*/",
        ];
        for source in fixtures {
            for end in (0..=source.len()).filter(|end| source.is_char_boundary(*end)) {
                let prefix = &source[..end];
                let mut expected = Vec::new();
                visit_tokens(prefix, |token| {
                    if token.kind == TokenKind::Comment {
                        expected.push(token.span);
                    }
                });
                assert_eq!(selective(prefix), expected, "prefix {prefix:?}");
                let mut last = None;
                let mut depth = 0isize;
                let diagnostics = visit_tokens(prefix, |token| {
                    match token.text(prefix) {
                        "(" | "[" => depth += 1,
                        ")" | "]" => depth -= 1,
                        _ => {}
                    }
                    last = Some(token);
                });
                let expected_balance = LexicalBalance {
                    expression_depth: depth,
                    open_literal: last.is_some_and(|token| {
                        token.kind == TokenKind::String
                            && diagnostics
                                .iter()
                                .any(|diagnostic| diagnostic.span.start == token.span.start)
                    }),
                    open_block_string: last.is_some_and(|token| {
                        token.kind == TokenKind::String
                            && token.text(prefix).starts_with("{\"")
                            && token.span.end == prefix.len()
                            && !token.text(prefix).ends_with("\"}")
                    }),
                };
                assert_eq!(
                    lexical_balance(prefix),
                    expected_balance,
                    "balance prefix {prefix:?}"
                );
            }
        }
    }
}

/// Continuation facts from literal boundaries and punctuation, without full tokens.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct LexicalBalance {
    pub expression_depth: isize,
    pub open_literal: bool,
    pub open_block_string: bool,
}

pub fn lexical_balance(source: &str) -> LexicalBalance {
    let mut balance = LexicalBalance::default();
    let bytes = source.as_bytes();
    let mut pos = 0;
    while pos < bytes.len() {
        // Every ordinary byte after a literal means it is no longer the last token.
        balance.open_literal = false;
        balance.open_block_string = false;
        if matches!(bytes[pos], b'/' | b'"' | b'\'' | b'@' | b'{') {
            if let Some((kind, length, unterminated)) = literal_or_comment(&source[pos..]) {
                if kind == TokenKind::String && pos + length == source.len() {
                    balance.open_literal = unterminated;
                    let text = &source[pos..];
                    balance.open_block_string = text.starts_with("{\"") && !text.ends_with("\"}");
                }
                pos += length;
                continue;
            }
        }
        match bytes[pos] {
            b'(' | b'[' => balance.expression_depth += 1,
            b')' | b']' => balance.expression_depth -= 1,
            _ => {}
        }
        pos += 1;
    }
    balance
}

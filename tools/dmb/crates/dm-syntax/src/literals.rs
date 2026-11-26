//! Decoding of single DM literal tokens: numbers, strings, raw strings, resources and interpolated strings.
//!
//! The values follow dreammaker's lexer exactly (`tools/analyze/vendor/dreammaker/src/lexer.rs`), so a consumer can map
//! them one to one onto dreammaker's `Term::Int`, `Term::Float`, `Term::String`, `Term::Resource` and
//! `Term::InterpString`:
//!
//! - A number is an `Int` when it has no `.`/`e`/`E` (outside hex) and fits an `i32` in its radix (`0x` hex, a leading
//!   `0` octal, else decimal); a decimal integer out of `i32` range becomes a `Float`; `1.#INF` is infinity and `1.#IND`
//!   NaN; `_` digit separators are skipped.
//! - String escapes are kept as written (`\n`, `\the`, `\improper`, `\"`, `\[` stay a backslash and the following
//!   character): dreammaker resolves them at a later stage. A backslash before a line break is a line continuation: it,
//!   the break and the leading blanks of the next line are dropped.
//! - Raw strings (`@"..."`, `@{"..."}`, `@(END)...END`, `@x...x`) keep every byte between their delimiters.
//! - A resource (`'icons/x.dmi'`) drops the backslash of each escape.
//! - An interpolated string is its leading text and one part per `[expr]`: the expression's source text (with its byte
//!   offset inside the token, for spans) and the literal text after it. `[]` has no expression.

use crate::{visit_tokens_while, TokenKind};

/// A decoded literal token.
#[derive(Clone, Debug, PartialEq)]
pub enum Literal {
    Int(i32),
    Float(f32),
    String(String),
    Resource(String),
    InterpString(InterpString),
}

/// `"a[x]b[y]c"`: `first` is `a`; the parts are `(x, b)` and `(y, c)`.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct InterpString {
    pub first: String,
    pub parts: Vec<InterpPart>,
}

/// One `[expr]text` part of an interpolated string.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct InterpPart {
    /// `None` for `[]` (or a part holding only blanks and comments).
    pub expr: Option<InterpExpr>,
    /// The literal text after the closing bracket, escapes kept as in [`Literal::String`].
    pub text: String,
}

/// The source of an interpolated expression, for `parse_expression`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct InterpExpr {
    /// The text between the brackets, untrimmed.
    pub source: String,
    /// Byte offset of `source` inside the decoded token text (as passed to [`decode_literal`]).
    pub offset: usize,
}

/// A token dreammaker would reject. `fallback` is the value dreammaker's lexer still produces after registering its
/// error (`Int(0)` for a bad integer, the text read so far for an unterminated string); `None` when the text is not
/// one literal token at all.
#[derive(Clone, Debug, PartialEq)]
pub struct LiteralError {
    pub message: String,
    pub fallback: Option<Literal>,
}

impl LiteralError {
    fn new(message: impl Into<String>, fallback: Option<Literal>) -> Self {
        LiteralError { message: message.into(), fallback }
    }
}

/// Decode one literal token's text. Surrounding blanks and line breaks are ignored (dreammaker drops them as
/// whitespace tokens); any other text before or after the literal is an error without a fallback.
pub fn decode_literal(text: &str) -> Result<Literal, LiteralError> {
    let start = text.len() - text.trim_start().len();
    let end = text.trim_end().len();
    if start >= end {
        return Err(LiteralError::new("empty literal", None));
    }
    let bytes = text.as_bytes();
    let mut reader = Reader { text, bytes, pos: start + 1 };
    let first = bytes[start];
    let result = match first {
        b'0'..=b'9' | b'.' => reader.number(first),
        b'\'' => reader.resource(),
        b'"' => reader.string_literal(b"\""),
        b'{' if bytes.get(start + 1) == Some(&b'"') => {
            reader.pos += 1;
            reader.string_literal(b"\"}")
        }
        b'@' => reader.raw_string(),
        _ => return Err(LiteralError::new(format!("not a literal: {:?}", &text[start..end]), None)),
    };
    if reader.pos < end {
        return Err(LiteralError::new(format!("text after the literal: {:?}", &text[reader.pos..end]), None));
    }
    result
}

struct Reader<'t> {
    text: &'t str,
    bytes: &'t [u8],
    pos: usize,
}

/// dreammaker's `from_utf8_or_latin1`.
fn from_utf8_or_latin1(bytes: Vec<u8>) -> String {
    match String::from_utf8(bytes) {
        Ok(s) => s,
        Err(e) => e.into_bytes().into_iter().map(char::from).collect(),
    }
}

impl Reader<'_> {
    fn next(&mut self) -> Option<u8> {
        let ch = self.bytes.get(self.pos).copied();
        if ch.is_some() {
            self.pos += 1;
        }
        ch
    }

    fn put_back(&mut self, ch: Option<u8>) {
        if ch.is_some() {
            self.pos -= 1;
        }
    }

    /// `read_number_inner`: (integer, radix, text for `from_str`).
    fn number_inner(&mut self, first: u8) -> (bool, u32, String) {
        let mut integer = true;
        let mut exponent = false;
        let mut radix = 10;
        let mut buf = String::new();
        buf.push(first as char);
        if first == b'.' {
            integer = false;
        } else if first == b'0' {
            radix = 8;
            match self.next() {
                Some(b'x') => radix = 16,
                ch => self.put_back(ch),
            }
        }
        loop {
            match self.next() {
                Some(b'_') => {}
                Some(ch) if ch == b'.' || ch == b'e' || ch == b'E' => {
                    if radix != 16 {
                        integer = false;
                        exponent |= ch == b'e' || ch == b'E';
                    }
                    buf.push(ch as char);
                }
                Some(ch) if (ch == b'+' || ch == b'-') && exponent => buf.push(ch as char),
                Some(b'#') => {
                    buf.push('#');
                    let start = buf.len();
                    for _ in 0..3 {
                        if let Some(ch) = self.next() {
                            buf.push(ch as char);
                            if ["I", "IN", "INF", "IND"].contains(&&buf[start..]) {
                                continue;
                            }
                        }
                        return (false, 10, buf);
                    }
                    return if &buf[start..] == "INF" { (false, 10, "inf".into()) } else { (false, 10, "NaN".into()) };
                }
                Some(ch) if (ch as char).is_digit(radix.max(10)) => {
                    exponent = false;
                    buf.push(ch as char);
                }
                ch => {
                    self.put_back(ch);
                    return (integer, radix, buf);
                }
            }
        }
    }

    /// `read_number`.
    fn number(&mut self, first: u8) -> Result<Literal, LiteralError> {
        let (integer, radix, buf) = self.number_inner(first);
        if integer {
            let original = match i32::from_str_radix(&buf, radix) {
                Ok(v) => return Ok(Literal::Int(v)),
                Err(e) => e,
            };
            if radix == 10 {
                if let Ok(v) = buf.parse::<f32>() {
                    // dreammaker warns of the precision loss and keeps the float.
                    return Ok(Literal::Float(v));
                }
            }
            Err(LiteralError::new(format!("bad base-{radix} integer {buf:?}: {original}"), Some(Literal::Int(0))))
        } else {
            match buf.parse::<f32>() {
                Ok(v) => Ok(Literal::Float(v)),
                Err(e) => Err(LiteralError::new(format!("bad float {buf:?}: {e}"), Some(Literal::Float(0.0)))),
            }
        }
    }

    /// `read_resource`.
    fn resource(&mut self) -> Result<Literal, LiteralError> {
        let mut buf = Vec::new();
        let mut backslash = false;
        loop {
            match self.next() {
                Some(ch) if backslash => {
                    backslash = false;
                    buf.push(ch);
                }
                Some(b'\\') => backslash = true,
                Some(b'\'') => return Ok(Literal::Resource(from_utf8_or_latin1(buf))),
                Some(ch) => buf.push(ch),
                None => {
                    let value = Literal::Resource(from_utf8_or_latin1(buf));
                    return Err(LiteralError::new("unterminated resource literal", Some(value)));
                }
            }
        }
    }

    /// `skip_ws(true)` after an escaped line break: blanks, at most one line break, blanks.
    fn skip_continuation(&mut self) {
        let mut newline_left = true;
        loop {
            match self.bytes.get(self.pos) {
                Some(b'\r' | b' ' | b'\t') => self.pos += 1,
                Some(b'\n') if newline_left => {
                    newline_left = false;
                    self.pos += 1;
                }
                _ => return,
            }
        }
    }

    /// `read_string`: the text up to `end` or an unescaped `[`; true when it stopped at `[`.
    fn string_segment(&mut self, end: &[u8]) -> Result<(String, bool), (String, &'static str)> {
        let mut buf = Vec::new();
        let mut backslash = false;
        let mut idx = 0;
        loop {
            let Some(ch) = self.next() else {
                return Err((from_utf8_or_latin1(buf), "unterminated string literal"));
            };
            if ch == end[idx] && !backslash {
                idx += 1;
                if idx == end.len() {
                    return Ok((from_utf8_or_latin1(buf), false));
                }
                continue;
            } else if idx > 0 && ch == end[idx - 1] && end[..idx - 1] == end[1..idx] && !backslash {
                // `""}`: hold `idx` and shift the first character of `end` into the text.
                buf.extend_from_slice(&end[..1]);
                continue;
            } else {
                buf.extend_from_slice(&end[..idx]);
                idx = 0;
            }
            match ch {
                b'\r' | b'\n' if backslash => {
                    backslash = false;
                    self.skip_continuation();
                }
                ch if backslash => {
                    backslash = false;
                    buf.push(b'\\');
                    buf.push(ch);
                }
                b'[' => return Ok((from_utf8_or_latin1(buf), true)),
                b'\\' => backslash = true,
                ch => buf.push(ch),
            }
        }
    }

    /// The expression after an interpolation's `[`, through its matching `]` (nested brackets, strings, resources and
    /// comments lexed as dm-syntax lexes them). Leaves `pos` after the `]`.
    fn interp_expr(&mut self) -> Result<Option<InterpExpr>, &'static str> {
        let start = self.pos;
        let rest = &self.text[start..];
        let mut depth = 1usize;
        let mut close = None;
        let mut significant = false;
        let mut lexical_error = false;
        let diagnostics = visit_tokens_while(rest, |token| {
            let t = &rest[token.span.range()];
            match token.kind {
                TokenKind::Whitespace | TokenKind::Newline | TokenKind::Comment => {}
                TokenKind::Punctuation if t == "[" => {
                    depth += 1;
                    significant = true;
                }
                TokenKind::Punctuation if t == "]" => {
                    depth -= 1;
                    if depth == 0 {
                        close = Some(token.span.start);
                        return false;
                    }
                }
                _ => significant = true,
            }
            true
        });
        if close.is_none() && !diagnostics.is_empty() {
            lexical_error = true;
        }
        let Some(close) = close else {
            self.pos = self.bytes.len();
            return Err(if lexical_error {
                "unterminated literal inside an interpolation"
            } else {
                "unterminated interpolation"
            });
        };
        self.pos = start + close + 1;
        Ok(significant.then(|| InterpExpr { source: rest[..close].to_owned(), offset: start }))
    }

    /// A `"..."` or `{"..."}` string, interpolated or not.
    fn string_literal(&mut self, end: &[u8]) -> Result<Literal, LiteralError> {
        let (first, opened) = match self.string_segment(end) {
            Ok(v) => v,
            Err((text, message)) => return Err(LiteralError::new(message, Some(Literal::String(text)))),
        };
        if !opened {
            return Ok(Literal::String(first));
        }
        let mut interp = InterpString { first, parts: Vec::new() };
        loop {
            let expr = self.interp_expr().map_err(|message| LiteralError::new(message, None))?;
            let (text, opened) = self.string_segment(end).map_err(|(_, message)| LiteralError::new(message, None))?;
            interp.parts.push(InterpPart { expr, text });
            if !opened {
                return Ok(Literal::InterpString(interp));
            }
        }
    }

    /// `read_raw_string_inner`.
    fn raw_until(&mut self, terminator: &[u8]) -> Result<Literal, LiteralError> {
        let mut buf = Vec::new();
        loop {
            match self.next() {
                Some(ch) => buf.push(ch),
                None => {
                    let value = Literal::String(from_utf8_or_latin1(buf));
                    return Err(LiteralError::new("unterminated raw string", Some(value)));
                }
            }
            if buf.ends_with(terminator) {
                buf.truncate(buf.len() - terminator.len());
                return Ok(Literal::String(from_utf8_or_latin1(buf)));
            }
        }
    }

    /// `read_raw_string`, after the `@`.
    fn raw_string(&mut self) -> Result<Literal, LiteralError> {
        let empty = || Some(Literal::String(String::new()));
        match self.next() {
            Some(b'\n') | None => Err(LiteralError::new("unterminated raw string", empty())),
            Some(b'(') => {
                let mut terminator = Vec::new();
                loop {
                    match self.next() {
                        Some(b')') => break,
                        Some(ch) => terminator.push(ch),
                        None => return Err(LiteralError::new("unterminated raw string terminator", empty())),
                    }
                }
                if terminator.is_empty() {
                    return Err(LiteralError::new("empty raw string terminator", empty()));
                }
                self.raw_until(&terminator)
            }
            Some(b'{') => match self.next() {
                Some(b'"') => self.raw_until(b"\"}"),
                other => {
                    self.put_back(other);
                    self.raw_until(b"{")
                }
            },
            Some(terminator) => self.raw_until(&[terminator]),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ok(text: &str) -> Literal {
        decode_literal(text).unwrap_or_else(|e| panic!("{text:?}: {e:?}"))
    }
    fn s(text: &str) -> Literal {
        Literal::String(text.into())
    }

    #[test]
    fn integers_and_radixes() {
        assert_eq!(ok("0"), Literal::Int(0));
        assert_eq!(ok("42"), Literal::Int(42));
        assert_eq!(ok("1_000"), Literal::Int(1000));
        assert_eq!(ok("0x1F"), Literal::Int(31));
        assert_eq!(ok("0xff"), Literal::Int(255));
        assert_eq!(ok("0x1e"), Literal::Int(30), "e is a hex digit, not an exponent");
        assert_eq!(ok("0777"), Literal::Int(511), "a leading 0 is octal");
        assert_eq!(ok("2147483647"), Literal::Int(i32::MAX));
        assert_eq!(ok("16777216"), Literal::Int(16777216));
    }

    #[test]
    fn integer_fallbacks() {
        assert_eq!(ok("2147483648"), Literal::Float(2147483648.0), "decimal overflow becomes a float");
        assert_eq!(ok("99999999999"), Literal::Float(99999999999.0));
        let e = decode_literal("09").unwrap_err();
        assert_eq!(e.fallback, Some(Literal::Int(0)), "{e:?}");
        let e = decode_literal("0xFFFFFFFF").unwrap_err();
        assert_eq!(e.fallback, Some(Literal::Int(0)), "{e:?}");
        assert_eq!(decode_literal("0XFF").unwrap_err().fallback, None, "capital X ends the number: two tokens");
        assert_eq!(decode_literal("10px").unwrap_err().fallback, None);
    }

    #[test]
    fn floats_and_exponents() {
        assert_eq!(ok("1.5"), Literal::Float(1.5));
        assert_eq!(ok("0.25"), Literal::Float(0.25));
        assert_eq!(ok("1."), Literal::Float(1.0));
        assert_eq!(ok("1e3"), Literal::Float(1000.0));
        assert_eq!(ok("1E3"), Literal::Float(1000.0));
        assert_eq!(ok("1e+3"), Literal::Float(1000.0));
        assert_eq!(ok("2.5e-2"), Literal::Float(0.025));
        assert_eq!(ok("1.#INF"), Literal::Float(f32::INFINITY));
        let Literal::Float(nan) = ok("1.#IND") else { panic!() };
        assert!(nan.is_nan());
        assert_eq!(decode_literal("1.#INX").unwrap_err().fallback, Some(Literal::Float(0.0)));
        assert_eq!(decode_literal("1e+").unwrap_err().fallback, Some(Literal::Float(0.0)));
    }

    #[test]
    fn plain_strings_keep_escapes() {
        assert_eq!(ok(r#""""#), s(""));
        assert_eq!(ok(r#""abc""#), s("abc"));
        for esc in [
            r"\n", r"\t", r"\\", r#"\""#, r"\[", r"\]", r"\'", r"\<", r"\>", r"\ ", r"\...", r"\icon", r"\ref",
            r"\the", r"\The", r"\a", r"\an", r"\A", r"\An", r"\improper", r"\proper", r"\he", r"\He", r"\she", r"\She",
            r"\his", r"\His", r"\him", r"\himself", r"\hers", r"\herself", r"\s", r"\th", r"\b", r"\red", r"\roman",
            r"\x", r"\xFF", r"ሴ", r"\N", r"\Unicode",
        ] {
            assert_eq!(ok(&format!("\"{esc} x\"")), s(&format!("{esc} x")), "{esc}");
            assert_eq!(ok(&format!("{{\"{esc} x\"}}")), s(&format!("{esc} x")), "block {esc}");
        }
        assert_eq!(ok(r#""\the [] x""#), Literal::InterpString(InterpString {
            first: r"\the ".into(),
            parts: vec![InterpPart { expr: None, text: " x".into() }],
        }));
    }

    #[test]
    fn line_continuations() {
        assert_eq!(ok("\"a\\\n    b\""), s("ab"));
        assert_eq!(ok("\"a\\\r\n\t\tb\""), s("ab"));
        assert_eq!(ok("\"a\\\n\n b\""), s("ab"), "the escaped break and one more are dropped");
        assert_eq!(ok("\"a\\\n\n\n b\""), s("a\n b"), "a third break is kept");
        assert_eq!(ok("{\"a\nb\"}"), s("a\nb"));
    }

    #[test]
    fn block_strings() {
        assert_eq!(ok(r#"{"a "quoted" b"}"#), s(r#"a "quoted" b"#));
        assert_eq!(ok(r#"{"a""}"#), s(r#"a""#), "two quotes before the brace close after one");
        assert_eq!(ok(r#"{"a}b"}"#), s("a}b"));
    }

    #[test]
    fn unterminated_strings_report_dreammakers_fallback() {
        let e = decode_literal(r#""abc"#).unwrap_err();
        assert_eq!(e.fallback, Some(s("abc")));
        let e = decode_literal(r#"{"a\"}"#).unwrap_err();
        assert_eq!(e.fallback, Some(s(r#"a\"}"#)));
        assert_eq!(decode_literal(r#""a" b"#).unwrap_err().fallback, None);
    }

    #[test]
    fn raw_strings() {
        assert_eq!(ok(r#"@"a\n[b]""#), s(r"a\n[b]"));
        assert_eq!(ok("@{\"a\n\\[\"b\"}"), s("a\n\\[\"b"));
        assert_eq!(ok("@'it\\s'"), s("it\\s"));
        assert_eq!(ok("@(END)a\"}END"), s("a\"}"));
        assert_eq!(ok("@{abc{"), s("abc"));
        assert_eq!(ok("@|x|"), s("x"));
        assert!(decode_literal("@()x").is_err());
        assert_eq!(decode_literal("@\"abc").unwrap_err().fallback, Some(s("abc")));
    }

    #[test]
    fn resources() {
        assert_eq!(ok("'icons/obj/x.dmi'"), Literal::Resource("icons/obj/x.dmi".into()));
        assert_eq!(ok(r"'a\'b\\c'"), Literal::Resource(r"a'b\c".into()));
        assert_eq!(decode_literal("'abc").unwrap_err().fallback, Some(Literal::Resource("abc".into())));
    }

    fn expr(source: &str, offset: usize) -> Option<InterpExpr> {
        Some(InterpExpr { source: source.into(), offset })
    }

    #[test]
    fn interpolation_parts() {
        let text = r#""a[x]b[y.z]c""#;
        assert_eq!(ok(text), Literal::InterpString(InterpString {
            first: "a".into(),
            parts: vec![
                InterpPart { expr: expr("x", 3), text: "b".into() },
                InterpPart { expr: expr("y.z", 7), text: "c".into() },
            ],
        }));
        assert_eq!(ok(r#""[a][b]""#), Literal::InterpString(InterpString {
            first: String::new(),
            parts: vec![InterpPart { expr: expr("a", 2), text: String::new() }, InterpPart { expr: expr("b", 5), text: String::new() }],
        }));
    }

    #[test]
    fn interpolation_nesting() {
        let text = r#""[list[1]] [x?[2]] [f("]", "[y]")] ['a]'] [@"]"] [{"]"}] /* */""#;
        let Literal::InterpString(i) = ok(text) else { panic!() };
        let sources: Vec<_> = i.parts.iter().map(|p| p.expr.as_ref().unwrap().source.as_str()).collect();
        assert_eq!(sources, ["list[1]", "x?[2]", r#"f("]", "[y]")"#, "'a]'", r#"@"]""#, r#"{"]"}"#]);
        for part in &i.parts {
            let e = part.expr.as_ref().unwrap();
            assert_eq!(&text[e.offset..e.offset + e.source.len()], e.source);
        }
        assert_eq!(i.parts.last().unwrap().text, " /* */");
        let block = ok("{\"x [a\n + b] \"y\" \"}");
        let Literal::InterpString(i) = block else { panic!() };
        assert_eq!(i.parts[0].expr.as_ref().unwrap().source, "a\n + b");
        assert_eq!(i.parts[0].text, " \"y\" ");
        assert_eq!(ok(r#""[ ]x""#), Literal::InterpString(InterpString {
            first: String::new(),
            parts: vec![InterpPart { expr: None, text: "x".into() }],
        }));
        assert_eq!(decode_literal(r#""[a""#).unwrap_err().fallback, None);
        assert_eq!(decode_literal(r#""[a]"#).unwrap_err().fallback, None);
    }

    #[test]
    fn surrounding_blanks_and_non_literals() {
        assert_eq!(ok("  \"a\"\n"), s("a"));
        assert!(decode_literal("abc").is_err());
        assert!(decode_literal("").is_err());
    }

    /// Every literal token under `code/` decodes, nested literals inside interpolations included.
    #[test]
    fn corpus_literals_decode() {
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../../code");
        if !root.is_dir() {
            eprintln!("no code/ tree at {}", root.display());
            return;
        }
        #[derive(Default, Debug)]
        struct Counts {
            files: usize,
            ints: usize,
            floats: usize,
            strings: usize,
            resources: usize,
            interps: usize,
            parts: usize,
            empty_parts: usize,
            parts_parsed: usize,
            failures: Vec<String>,
        }
        fn walk_literals(source: &str, where_: &str, c: &mut Counts) {
            let lexed = crate::lex_spans(source);
            for token in lexed.tokens {
                if !matches!(token.kind, TokenKind::Number | TokenKind::String | TokenKind::Resource) {
                    continue;
                }
                let text = token.text(source);
                match decode_literal(text) {
                    Ok(Literal::Int(_)) => c.ints += 1,
                    Ok(Literal::Float(_)) => c.floats += 1,
                    Ok(Literal::String(_)) => c.strings += 1,
                    Ok(Literal::Resource(_)) => c.resources += 1,
                    Ok(Literal::InterpString(i)) => {
                        c.interps += 1;
                        for part in i.parts {
                            c.parts += 1;
                            match part.expr {
                                None => c.empty_parts += 1,
                                Some(e) => {
                                    let parsed = crate::parse_expression(&e.source);
                                    if parsed.expr.is_some() && parsed.diagnostics.is_empty() {
                                        c.parts_parsed += 1;
                                    }
                                    walk_literals(&e.source, where_, c);
                                }
                            }
                        }
                    }
                    Err(e) => c.failures.push(format!("{where_}: {text:?}: {}", e.message)),
                }
            }
        }
        let mut c = Counts::default();
        let mut stack = vec![root];
        while let Some(dir) = stack.pop() {
            for entry in std::fs::read_dir(&dir).unwrap() {
                let path = entry.unwrap().path();
                if path.is_dir() {
                    stack.push(path);
                } else if path.extension().is_some_and(|e| e == "dm") {
                    let bytes = std::fs::read(&path).unwrap();
                    // `#error`/`#warn` take the rest of the line as text (dreammaker's stringy directive), not tokens.
                    let source: String = from_utf8_or_latin1(bytes)
                        .split_inclusive('\n')
                        .map(|line| {
                            let head = line.trim_start();
                            if head.starts_with("#error") || head.starts_with("#warn") {
                                "\n".to_owned()
                            } else {
                                line.to_owned()
                            }
                        })
                        .collect();
                    c.files += 1;
                    walk_literals(&source, &path.display().to_string(), &mut c);
                }
            }
        }
        eprintln!(
            "literal corpus: files {} ints {} floats {} strings {} resources {} interpolated {} parts {} (empty {}, parsed {}) failures {}",
            c.files, c.ints, c.floats, c.strings, c.resources, c.interps, c.parts, c.empty_parts, c.parts_parsed, c.failures.len()
        );
        assert!(c.failures.is_empty(), "{} failures, first: {:#?}", c.failures.len(), &c.failures[..c.failures.len().min(20)]);
    }
}

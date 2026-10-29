//! Authoritative DM literal syntax and text-template decoding.
//! Both native emission and analysis borrow the interpolation expressions retained
//! by the issuing literal. No analyzer-specific expression parser is involved.
use crate::{parse_expression, Expr, ExprKind, Span};
use std::{
    fmt,
    ops::Deref,
    sync::{Arc, OnceLock},
};

/// Lexical facts needed by the pinned checker, before runtime text escapes.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct LiteralLexicalShape {
    pub interpolated: bool,
    pub pinned_segment_nonempty: bool,
}
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum LiteralLexicalError {
    /// Removing CR changed an escape/interpolation boundary. The runtime
    /// expression roster cannot certify the pinned lexical structure.
    InterpolationBoundaryNormalization,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LiteralParts {
    pub template: Vec<u8>,
    pub expressions: Vec<Expr>,
    pub lexical: Result<LiteralLexicalShape, LiteralLexicalError>,
}
#[derive(Debug)]
struct LiteralState {
    raw: String,
    origin: usize,
    parts: OnceLock<Result<Option<LiteralParts>, String>>,
}
/// Clones of a string literal in one issued syntax tree share its parsed
/// leaves. Numbers and resource paths do not allocate a parse cache.
#[derive(Clone, Debug)]
pub struct LiteralText(Backing);
#[derive(Clone, Debug)]
enum Backing {
    Plain(String),
    Text(Arc<LiteralState>),
}
impl LiteralText {
    pub fn at(raw: String, origin: usize) -> Self {
        if raw.starts_with('"')
            || raw.starts_with("{\"")
            || raw.starts_with("@\"")
            || raw.starts_with("@'")
            || raw.starts_with("@{\"")
        {
            Self(Backing::Text(Arc::new(LiteralState {
                raw,
                origin,
                parts: OnceLock::new(),
            })))
        } else {
            Self(Backing::Plain(raw))
        }
    }
    pub fn raw_storage(&self) -> &String {
        match &self.0 {
            Backing::Plain(raw) => raw,
            Backing::Text(state) => &state.raw,
        }
    }
    pub fn as_str(&self) -> &str {
        self.raw_storage()
    }
    /// Read-only census; never computes or retains additional syntax.
    pub fn shared_storage(&self) -> Option<(usize, usize)> {
        match &self.0 {
            Backing::Plain(_) => None,
            Backing::Text(state) => Some((
                Arc::as_ptr(state) as usize,
                std::mem::size_of::<LiteralState>() + 2 * std::mem::size_of::<usize>(),
            )),
        }
    }
    pub fn retained_parts(&self) -> Option<Result<Option<&LiteralParts>, &String>> {
        match &self.0 {
            Backing::Plain(_) => None,
            Backing::Text(state) => state.parts.get().map(|p| p.as_ref().map(Option::as_ref)),
        }
    }
    pub fn parts(&self) -> Result<Option<&LiteralParts>, &str> {
        let Backing::Text(state) = &self.0 else {
            return Ok(None);
        };
        state
            .parts
            .get_or_init(|| {
                retained_string_literal_parts(&state.raw).map(|parts| {
                    parts.map(|mut parts| {
                        for expression in &mut parts.expressions {
                            shift_expression(expression, state.origin);
                        }
                        parts
                    })
                })
            })
            .as_ref()
            .map(|parts| parts.as_ref())
            .map_err(String::as_str)
    }
    pub(crate) fn shift(&mut self, offset: usize) {
        if let Backing::Text(state) = &self.0 {
            if offset != 0 {
                *self = Self::at(state.raw.clone(), state.origin + offset);
            }
        }
    }
}
impl Deref for LiteralText {
    type Target = str;
    fn deref(&self) -> &str {
        self.as_str()
    }
}
impl AsRef<str> for LiteralText {
    fn as_ref(&self) -> &str {
        self.as_str()
    }
}
impl From<String> for LiteralText {
    fn from(raw: String) -> Self {
        Self::at(raw, 0)
    }
}
impl From<&str> for LiteralText {
    fn from(raw: &str) -> Self {
        raw.to_owned().into()
    }
}
impl PartialEq for LiteralText {
    fn eq(&self, other: &Self) -> bool {
        self.as_str() == other.as_str()
    }
}
impl Eq for LiteralText {}
impl PartialEq<String> for LiteralText {
    fn eq(&self, other: &String) -> bool {
        self.as_str() == other
    }
}
impl PartialEq<str> for LiteralText {
    fn eq(&self, other: &str) -> bool {
        self.as_str() == other
    }
}
impl PartialEq<&str> for LiteralText {
    fn eq(&self, other: &&str) -> bool {
        self.as_str() == *other
    }
}
impl fmt::Display for LiteralText {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.as_str().fmt(f)
    }
}

pub fn shift_expression(expression: &mut Expr, offset: usize) {
    expression.span.start += offset;
    expression.span.end += offset;
    match &mut expression.kind {
        ExprKind::Literal(text) => text.shift(offset),
        ExprKind::Ident(_) | ExprKind::TypePath(_) => (),
        ExprKind::Unary { value, .. }
        | ExprKind::Group(value)
        | ExprKind::TypeFilter { value, .. } => shift_expression(value, offset),
        ExprKind::Member { object, .. }
        | ExprKind::StaticMember { object, .. }
        | ExprKind::SafeMember { object, .. } => shift_expression(object, offset),
        ExprKind::Binary { lhs, rhs, .. } => {
            shift_expression(lhs, offset);
            shift_expression(rhs, offset);
        }
        ExprKind::Index { object, index } | ExprKind::SafeIndex { object, index } => {
            shift_expression(object, offset);
            shift_expression(index, offset);
        }
        ExprKind::Conditional {
            condition,
            then_value,
            else_value,
        } => {
            shift_expression(condition, offset);
            shift_expression(then_value, offset);
            shift_expression(else_value, offset);
        }
        ExprKind::Call { callee, args } => {
            shift_expression(callee, offset);
            for arg in args {
                shift_expression(arg, offset);
            }
        }
        ExprKind::ObjectInitializer { object, fields } => {
            shift_expression(object, offset);
            for (_, value) in fields {
                shift_expression(value, offset);
            }
        }
    }
}
/// One shared literal parser for emission and source registration. Expression
/// nodes exist only for this literal's interpolation leaves, never a whole body.
fn string_literal_parts_clean(
    raw: &str,
    projection: RawProjection<'_>,
) -> Result<Option<LiteralParts>, String> {
    // Raw literals preserve escapes and brackets exactly, including multiline text.
    let raw_value = if raw.starts_with("@{\"") && raw.ends_with("\"}") && raw.len() >= 5 {
        Some(&raw[3..raw.len() - 2])
    } else if ((raw.starts_with("@\"") && raw.ends_with('"'))
        || (raw.starts_with("@'") && raw.ends_with('\'')))
        && raw.len() >= 3
    {
        Some(&raw[2..raw.len() - 1])
    } else {
        None
    };
    if let Some(value) = raw_value {
        return Ok(Some(LiteralParts {
            template: value.as_bytes().to_vec(),
            expressions: Vec::new(),
            lexical: Ok(LiteralLexicalShape {
                interpolated: false,
                pinned_segment_nonempty: !projection
                    .segment(value.as_ptr() as usize - raw.as_ptr() as usize, value.len())
                    .is_empty(),
            }),
        }));
    }
    let value = if raw.starts_with("{\"") && raw.ends_with("\"}") && raw.len() >= 4 {
        &raw[2..raw.len() - 2]
    } else if raw.starts_with('"') && raw.ends_with('"') && raw.len() >= 2 {
        &raw[1..raw.len() - 1]
    } else {
        return Ok(None);
    };
    let offset = value.as_ptr() as usize - raw.as_ptr() as usize;
    let mut parts = parse_interpolated_string_clean(value, projection.offset(offset))?;
    for expression in &mut parts.expressions {
        shift_expression(expression, offset);
    }
    Ok(Some(parts))
}

/// Projection of ranges issued by the primary interpolation parser onto the
/// original literal. A start includes removed CR bytes after the preceding
/// delimiter; an end includes removed CR bytes before the following delimiter.
#[derive(Clone, Copy)]
struct RawProjection<'a> {
    original: &'a str,
    positions: Option<&'a [usize]>,
    base: usize,
}
impl<'a> RawProjection<'a> {
    fn identity(original: &'a str) -> Self {
        Self {
            original,
            positions: None,
            base: 0,
        }
    }
    fn offset(self, offset: usize) -> Self {
        Self {
            base: self.base + offset,
            ..self
        }
    }
    fn segment(self, start: usize, len: usize) -> &'a [u8] {
        let start = self.base + start;
        let end = start + len;
        let (start, end) = match self.positions {
            Some(positions) => (
                if start == 0 {
                    0
                } else {
                    positions[start - 1] + 1
                },
                positions.get(end).copied().unwrap_or(self.original.len()),
            ),
            None => (start, end),
        };
        &self.original.as_bytes()[start..end]
    }
}
/// This scan never recognizes interpolation grammar. It observes only literal
/// segment ranges already issued by the one primary parser. Pinned read_string
/// retains ordinary escape bytes, but consumes an escaped CR or LF followed by
/// skip_ws(true): all CR/indentation and at most one additional LF.
fn observe_segment(
    raw: &[u8],
    shape: &mut LiteralLexicalShape,
    error: &mut Option<LiteralLexicalError>,
) {
    let mut at = 0;
    while at < raw.len() {
        match raw[at] {
            b'\\' => {
                at += 1;
                match raw.get(at) {
                    Some(b'\r' | b'\n') => {
                        at += 1;
                        let mut additional_lf = false;
                        while at < raw.len() {
                            match raw[at] {
                                b'\r' | b' ' | b'\t' => at += 1,
                                b'\n' if !additional_lf => {
                                    additional_lf = true;
                                    at += 1;
                                }
                                _ => break,
                            }
                        }
                    }
                    Some(_) => {
                        shape.pinned_segment_nonempty = true;
                        at += 1;
                    }
                    None => {
                        *error = Some(LiteralLexicalError::InterpolationBoundaryNormalization);
                    }
                }
            }
            b'[' => {
                *error = Some(LiteralLexicalError::InterpolationBoundaryNormalization);
                at += 1;
            }
            _ => {
                shape.pinned_segment_nonempty = true;
                at += 1;
            }
        }
    }
}

fn parse_interpolated_string_clean(
    value: &str,
    projection: RawProjection<'_>,
) -> Result<LiteralParts, String> {
    let mut template = Vec::new();
    let mut expressions = Vec::new();
    let mut next_marker = None;
    let mut substituted = false;
    let mut lexical = LiteralLexicalShape {
        interpolated: false,
        pinned_segment_nonempty: false,
    };
    let mut segment_start = 0;
    let mut segment_error = None;
    let mut at = 0;
    while at < value.len() {
        let ch = value[at..].chars().next().unwrap();
        if ch == '\\' {
            at += 1;
            let rest = &value[at..];
            if rest.starts_with("\r\n") || rest.starts_with('\n') {
                at += if rest.starts_with("\r\n") { 2 } else { 1 };
                while at < value.len()
                    && matches!(value.as_bytes()[at], b' ' | b'\t' | b'\r' | b'\n')
                {
                    at += 1;
                }
                continue;
            }
            if rest.starts_with(' ') {
                at += 1;
                continue;
            }
            if let Some(consumed) = numeric_escape(rest, &mut template) {
                at += consumed;
                continue;
            }
            if rest.starts_with("...") {
                template.extend([0xff, 0x12]);
                at += 3;
                continue;
            }
            // DreamMaker reads the whole letter run after `\` as a macro name. A run
            // that names no applicable macro falls back to a one-letter escape
            // (`\n`, `\t`) followed by literal text, or is an error: `"\red"` is the
            // red formatting macro and `"\redb"` is invalid, never `\r` + "ed".
            let word_len = rest.bytes().take_while(u8::is_ascii_alphabetic).count();
            if word_len != 0 {
                let word = &rest[..word_len];
                let after = &rest[word_len..];
                if let Some(effect) = text_macro(word, after, &template, substituted)? {
                    at += word_len;
                    match effect {
                        TextMacro::Emit(marker, consume_space) => {
                            // `\font` absorbs one preceding space, not a following one.
                            if marker == 0x1d && template.last() == Some(&b' ') {
                                template.pop();
                            }
                            template.extend([0xff, marker]);
                            if consume_space && value[at..].starts_with(' ') {
                                at += 1;
                            }
                        }
                        TextMacro::Article(marker) => {
                            template.extend([0xff, marker]);
                            next_marker = Some(0x03);
                            at += 1;
                        }
                        TextMacro::NextExpression(marker) => next_marker = Some(marker),
                        TextMacro::Ordinal => {
                            let last = template.len() - 1;
                            template[last] = 0x05;
                        }
                    }
                    continue;
                }
            }
            let escape = value[at..].chars().next().ok_or("trailing string escape")?;
            let escaped = match escape {
                'n' => "\n",
                't' => "\t",
                '\\' => "\\",
                '"' => "\"",
                '\'' => "'",
                '[' => "[",
                ']' => "]",
                '<' => "&lt;",
                '>' => "&gt;",
                '&' => "&amp;",
                _ if word_len != 0 => {
                    return Err(format!(
                        "undefined text macro or escape sequence: \\{}",
                        &rest[..word_len]
                    ))
                }
                _ => return Err(format!("unsupported string escape: \\{escape}")),
            };
            template.extend_from_slice(escaped.as_bytes());
            at += escape.len_utf8();
            continue;
        }
        if ch == '[' {
            observe_segment(
                projection.segment(segment_start, at - segment_start),
                &mut lexical,
                &mut segment_error,
            );
            lexical.interpolated = true;
            let start = at + 1;
            let mut cursor = None;
            let mut depth = 1usize;
            let diagnostics = crate::visit_tokens_while(&value[start..], |token| {
                if token.kind == crate::TokenKind::Punctuation {
                    match token.text(&value[start..]) {
                        "[" => depth += 1,
                        "]" => {
                            depth -= 1;
                            if depth == 0 {
                                cursor = Some(start + token.span.start);
                                return false;
                            }
                        }
                        _ => (),
                    }
                }
                true
            });
            if !diagnostics.is_empty() {
                return Err("invalid string interpolation tokens".into());
            }
            let cursor = cursor.ok_or("unclosed string interpolation")?;
            substituted = true;
            if value[start..cursor].trim().is_empty() {
                template.extend([0xff, next_marker.take().unwrap_or(1)]);
                at = cursor + 1;
                segment_start = at;
                continue;
            }
            let raw_expression = &value[start..cursor];
            let leading = raw_expression.len() - raw_expression.trim_start().len();
            let raw_expression = raw_expression.trim();
            let (source, positions) = splice_with_positions(raw_expression);
            let parsed = parse_expression(&source);
            if !parsed.diagnostics.is_empty() {
                return Err("invalid string interpolation expression".into());
            }
            let mut expression = parsed.expr.ok_or("empty string interpolation")?;
            remap(&mut expression, &positions, raw_expression);
            shift_expression(&mut expression, start + leading);
            expressions.push(expression);
            let marker = next_marker.take().unwrap_or_else(|| {
                if interpolation_starts_sentence(&template) {
                    2
                } else {
                    1
                }
            });
            template.extend([0xff, marker]);
            at = cursor + 1;
            segment_start = at;
            continue;
        }
        let mut bytes = [0; 4];
        template.extend_from_slice(ch.encode_utf8(&mut bytes).as_bytes());
        at += ch.len_utf8();
    }
    observe_segment(
        projection.segment(segment_start, value.len() - segment_start),
        &mut lexical,
        &mut segment_error,
    );
    Ok(LiteralParts {
        template,
        expressions,
        lexical: segment_error.map_or(Ok(lexical), Err),
    })
}

enum TextMacro {
    /// `0xff marker` in place; the flag consumes one following space.
    Emit(u8, bool),
    /// Article (`\the`, `\a`, ...): marker in place, the next substitution is its
    /// noun (marker 3), and the mandatory following space is consumed.
    Article(u8),
    /// The next substitution is emitted with this marker (`\ref`, `\icon`, ...).
    NextExpression(u8),
    /// `\th` rewrites the marker of the substitution it directly follows.
    Ordinal,
}

/// `\xHH` (two hex digits) and `\uHHHH` (four) code points, UTF-8 encoded.
fn numeric_escape(rest: &str, template: &mut Vec<u8>) -> Option<usize> {
    let digits = match rest.as_bytes().first()? {
        b'x' => 2,
        b'u' => 4,
        _ => return None,
    };
    let hex = rest.get(1..1 + digits)?;
    if !hex.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        return None;
    }
    let code = char::from_u32(u32::from_str_radix(hex, 16).ok()?)?;
    let mut encoded = [0; 4];
    template.extend_from_slice(code.encode_utf8(&mut encoded).as_bytes());
    Some(1 + digits)
}

/// DreamMaker 516.1687 text macros by full name (oracle:
/// `fixtures/native_compiler/text_macros`). `Ok(None)` means the word is not an
/// applicable macro here and falls back to a one-letter escape.
fn text_macro(
    word: &str,
    after: &str,
    template: &[u8],
    substituted: bool,
) -> Result<Option<TextMacro>, String> {
    let pronoun = |marker| {
        if substituted {
            Ok(Some(TextMacro::Emit(marker, false)))
        } else {
            Err(format!("macro \\{word} requires preceding expression"))
        }
    };
    let article = |marker| Ok(after.starts_with(' ').then_some(TextMacro::Article(marker)));
    match word {
        "the" => article(0x08),
        "The" => article(0x09),
        "a" | "an" => article(0x06),
        "A" | "An" => article(0x07),
        "he" | "she" => pronoun(0x0a),
        "He" | "She" => pronoun(0x0b),
        "his" => pronoun(0x0c),
        "His" => pronoun(0x0d),
        "hers" => pronoun(0x0e),
        "Hers" => pronoun(0x0f),
        "him" => pronoun(0x10),
        "himself" | "herself" => pronoun(0x11),
        "s" => pronoun(0x14),
        "th" => {
            if substituted && template.len() >= 2 && template[template.len() - 2] == 0xff {
                Ok(Some(TextMacro::Ordinal))
            } else {
                Err("macro \\th must follow a substituted expression (like []\\th)".into())
            }
        }
        "proper" | "improper" => {
            if template.is_empty() {
                let marker = if word == "proper" { 0x15 } else { 0x16 };
                Ok(Some(TextMacro::Emit(marker, true)))
            } else {
                Err(format!("\\{word} must be at beginning of word"))
            }
        }
        "ref" => Ok(Some(TextMacro::NextExpression(0x2a))),
        "icon" => Ok(Some(TextMacro::NextExpression(0x2b))),
        "roman" => Ok(Some(TextMacro::NextExpression(0x2c))),
        "Roman" => Ok(Some(TextMacro::NextExpression(0x2d))),
        "bold" | "b" => Ok(Some(TextMacro::Emit(0x17, true))),
        "italic" | "i" => Ok(Some(TextMacro::Emit(0x18, true))),
        "underline" | "u" => Ok(Some(TextMacro::Emit(0x19, true))),
        "o" => Ok(Some(TextMacro::Emit(0x1a, true))),
        "font" => Ok(Some(TextMacro::Emit(0x1d, false))),
        "red" => Ok(Some(TextMacro::Emit(0x1f, true))),
        "green" => Ok(Some(TextMacro::Emit(0x20, true))),
        "blue" => Ok(Some(TextMacro::Emit(0x21, true))),
        "black" => Ok(Some(TextMacro::Emit(0x22, true))),
        "white" => Ok(Some(TextMacro::Emit(0x23, true))),
        _ => Ok(None),
    }
}

fn interpolation_starts_sentence(mut prefix: &[u8]) -> bool {
    loop {
        while prefix
            .last()
            .is_some_and(|byte| matches!(byte, b' ' | b'\n' | b'\t' | b'\'' | b'"' | 0xff))
        {
            prefix = &prefix[..prefix.len() - 1];
        }
        match prefix.last() {
            None | Some(b'.' | b'!' | b'?') => return true,
            Some(b'>') => {
                if let Some(opening) = prefix.iter().rposition(|byte| *byte == b'<') {
                    prefix = &prefix[..opening];
                } else {
                    return true;
                }
            }
            _ => return false,
        }
    }
}

fn without_cr(source: &str) -> (String, Vec<usize>) {
    let positions: Vec<_> = source
        .bytes()
        .enumerate()
        .filter_map(|(at, byte)| (byte != b'\r').then_some(at))
        .collect();
    let bytes: Vec<_> = positions.iter().map(|&at| source.as_bytes()[at]).collect();
    (
        String::from_utf8(bytes).expect("removing CR preserves UTF-8"),
        positions,
    )
}
fn splice_with_positions(source: &str) -> (String, Vec<usize>) {
    let protected: Vec<_> = crate::lex_spans(source)
        .tokens
        .into_iter()
        .filter(|t| {
            matches!(
                t.kind,
                crate::TokenKind::String | crate::TokenKind::Resource
            )
        })
        .map(|t| t.span.range())
        .collect();
    let mut positions = Vec::new();
    let mut at = 0;
    let mut token = 0;
    while at < source.len() {
        while token < protected.len() && protected[token].end <= at {
            token += 1;
        }
        let in_literal = protected.get(token).is_some_and(|r| r.contains(&at));
        let tail = &source.as_bytes()[at..];
        let skip = if in_literal {
            0
        } else if tail.starts_with(b"\\\r\n") {
            3
        } else if tail.starts_with(b"\\\n") {
            2
        } else {
            0
        };
        if skip != 0 {
            at += skip;
        } else {
            positions.push(at);
            at += 1;
        }
    }
    let bytes = positions.iter().map(|&at| source.as_bytes()[at]).collect();
    (
        String::from_utf8(bytes).expect("splicing preserves UTF-8"),
        positions,
    )
}
fn remap(expression: &mut Expr, positions: &[usize], source: &str) {
    let span = expression.span;
    let start = positions.get(span.start).copied().unwrap_or(source.len());
    let end = if span.end == span.start {
        start
    } else {
        positions
            .get(span.end - 1)
            .map_or(source.len(), |at| at + 1)
    };
    expression.span = Span::new(start, end);
    match &mut expression.kind {
        ExprKind::Literal(text) => *text = LiteralText::at(source[start..end].to_owned(), start),
        ExprKind::Ident(_) | ExprKind::TypePath(_) => (),
        ExprKind::Unary { value, .. }
        | ExprKind::Group(value)
        | ExprKind::TypeFilter { value, .. } => remap(value, positions, source),
        ExprKind::Member { object, .. }
        | ExprKind::StaticMember { object, .. }
        | ExprKind::SafeMember { object, .. } => remap(object, positions, source),
        ExprKind::Binary { lhs, rhs, .. } => {
            remap(lhs, positions, source);
            remap(rhs, positions, source);
        }
        ExprKind::Index { object, index } | ExprKind::SafeIndex { object, index } => {
            remap(object, positions, source);
            remap(index, positions, source);
        }
        ExprKind::Conditional {
            condition,
            then_value,
            else_value,
        } => {
            remap(condition, positions, source);
            remap(then_value, positions, source);
            remap(else_value, positions, source);
        }
        ExprKind::Call { callee, args } => {
            remap(callee, positions, source);
            for arg in args {
                remap(arg, positions, source);
            }
        }
        ExprKind::ObjectInitializer { object, fields } => {
            remap(object, positions, source);
            for (_, value) in fields {
                remap(value, positions, source);
            }
        }
    }
}
fn retained_string_literal_parts(raw: &str) -> Result<Option<LiteralParts>, String> {
    if !raw.contains('\r') {
        return string_literal_parts_clean(raw, RawProjection::identity(raw));
    }
    let (cooked, positions) = without_cr(raw);
    let mut parts = string_literal_parts_clean(
        &cooked,
        RawProjection {
            original: raw,
            positions: Some(&positions),
            base: 0,
        },
    )?;
    if let Some(parts) = &mut parts {
        for expr in &mut parts.expressions {
            remap(expr, &positions, raw);
        }
    }
    Ok(parts)
}
/// Compatibility tuple projection; the single retained parser also issues
/// lexical policy facts, which runtime-only tuple callers need not retain.
pub fn string_literal_parts(raw: &str) -> Result<Option<(Vec<u8>, Vec<Expr>)>, String> {
    retained_string_literal_parts(raw)
        .map(|parts| parts.map(|parts| (parts.template, parts.expressions)))
}
pub fn parse_interpolated_string(value: &str) -> Result<(Vec<u8>, Vec<Expr>), String> {
    let mut parts = if value.contains('\r') {
        let (cooked, positions) = without_cr(value);
        let mut parts = parse_interpolated_string_clean(
            &cooked,
            RawProjection {
                original: value,
                positions: Some(&positions),
                base: 0,
            },
        )?;
        for expr in &mut parts.expressions {
            remap(expr, &positions, value);
        }
        parts
    } else {
        parse_interpolated_string_clean(value, RawProjection::identity(value))?
    };
    Ok((
        std::mem::take(&mut parts.template),
        std::mem::take(&mut parts.expressions),
    ))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{NodeStep, TypedVisitor, VisitDecision};
    #[test]
    fn literal_clones_share_issued_interpolation_nodes() {
        let parsed = parse_expression(r#""before [callee(2)] after""#);
        assert!(parsed.diagnostics.is_empty());
        let expression = parsed.expr.unwrap();
        let ExprKind::Literal(text) = expression.kind else {
            panic!()
        };
        let copy = text.clone();
        let parts = text.parts().unwrap().unwrap();
        assert!(std::ptr::eq(parts, copy.parts().unwrap().unwrap()));
        assert_eq!(parts.expressions.len(), 1);
        assert!(matches!(parts.expressions[0].kind, ExprKind::Call { .. }));
        assert_eq!(parts.expressions[0].span, Span::new(9, 18));
        assert!(LiteralText::from("42").shared_storage().is_none());
    }
    #[test]
    fn interpolation_visits_nested_calls_once_with_physical_spans() {
        let source = "\"prefix\r [outer(\\\r\n    \"[inner()]\")] end\"";
        let parsed = parse_expression(source);
        assert!(parsed.diagnostics.is_empty(), "{:?}", parsed.diagnostics);
        struct Calls<'a> {
            source: &'a str,
            calls: Vec<String>,
        }
        impl TypedVisitor for Calls<'_> {
            fn expression(&mut self, expression: &Expr, _: &[NodeStep]) -> VisitDecision {
                if let ExprKind::Call { callee, .. } = &expression.kind {
                    let ExprKind::Ident(name) = &callee.kind else {
                        panic!()
                    };
                    assert_eq!(&self.source[callee.span.range()], name);
                    self.calls.push(name.clone());
                }
                VisitDecision::Descend
            }
        }
        let mut calls = Calls {
            source,
            calls: Vec::new(),
        };
        crate::visit_expression(&parsed.expr.unwrap(), &mut calls);
        assert_eq!(calls.calls, ["outer", "inner"]);
    }
    #[test]
    fn rebasing_cached_literal_children_preserves_the_original_issuance() {
        let mut expression = parse_expression(r#""[nested()]""#).expr.unwrap();
        let original = expression.clone();
        let ExprKind::Literal(text) = &original.kind else {
            panic!()
        };
        let original_start = text.parts().unwrap().unwrap().expressions[0].span.start;
        shift_expression(&mut expression, 100);
        let ExprKind::Literal(shifted) = &expression.kind else {
            panic!()
        };
        assert_eq!(
            shifted.parts().unwrap().unwrap().expressions[0].span.start,
            original_start + 100
        );
        assert_eq!(
            text.parts().unwrap().unwrap().expressions[0].span.start,
            original_start
        );
    }
    #[test]
    fn nested_escaped_quotes_resources_and_brackets_use_native_lexer_boundaries() {
        let source = r#""[f("a\"b]", 'icons/a]b.dmi', "]")] trailing""#;
        let parsed = parse_expression(source);
        assert!(parsed.diagnostics.is_empty(), "{:?}", parsed.diagnostics);
        let ExprKind::Literal(text) = parsed.expr.unwrap().kind else {
            panic!()
        };
        let parts = text.parts().unwrap().unwrap();
        assert_eq!(parts.expressions.len(), 1);
        let ExprKind::Call { args, .. } = &parts.expressions[0].kind else {
            panic!()
        };
        assert_eq!(args.len(), 3);
        assert_eq!(&source[args[1].span.range()], "'icons/a]b.dmi'");
    }
    #[test]
    fn raw_and_escaped_brackets_have_no_expression_children() {
        for source in [r#"@"[not_a_call()]""#, r#""\[not_a_call()]""#] {
            let parsed = parse_expression(source);
            assert!(parsed.diagnostics.is_empty());
            let ExprKind::Literal(text) = parsed.expr.unwrap().kind else {
                panic!()
            };
            assert!(text.parts().unwrap().unwrap().expressions.is_empty());
        }
    }
    #[test]
    fn malformed_interpolation_remains_an_explicit_failure() {
        let text = LiteralText::from(r#""[broken(]""#);
        assert_eq!(
            text.parts().unwrap_err(),
            "invalid string interpolation expression"
        );
    }
}

#[cfg(test)]
#[path = "literal_lexical_shape_tests.rs"]
mod lexical_shape_tests;

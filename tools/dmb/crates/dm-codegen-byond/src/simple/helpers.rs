//! Helpers lowering over the shared compiler context.
use super::*;

pub(super) fn member_proc_selector(path: SymRef) -> VariableWord {
    if matches!(path, SymRef::Verb { .. }) {
        VariableWord::StaticVerb(path)
    } else {
        VariableWord::StaticProc(path)
    }
}

pub(super) fn class_tag(path: &str) -> Option<u8> {
    let root = path.trim_start_matches('/').split('/').next()?;
    Some(match root {
        "datum" | "regex" | "icon" | "sound" | "matrix" | "particles" | "database"
        | "generator" | "exception" => 32,
        "obj" | "atom" => 9,
        "mob" => 8,
        "turf" => 10,
        "area" => 11,
        "client" => 59,
        "image" | "mutable_appearance" => 63,
        "list" => 40,
        "alist" => 89,
        "savefile" => 36,
        "file" => 39,
        _ => return None,
    })
}

/// Compile-time spelling of a DM reference. Its receiver is not evaluated.
pub fn nameof_reference(expr: &Expr) -> Option<&str> {
    match &expr.kind {
        ExprKind::Ident(name) => Some(name),
        ExprKind::TypePath(path) => path.rsplit('/').next().filter(|name| !name.is_empty()),
        ExprKind::Member { selector, .. } | ExprKind::StaticMember { selector, .. } => {
            Some(selector)
        }
        ExprKind::Group(inner) => nameof_reference(inner),
        _ => None,
    }
}

pub(super) fn error(statement: &str, reason: &str) -> LowerError {
    LowerError {
        primary_anchor: None,
        related: Vec::new(),
        statement: statement.into(),
        reason: reason.into(),
        ..LowerError::default()
    }
}

/// A confirmed error in the author's source, worded as DreamMaker words it.
pub(super) fn source_error(statement: &str, reason: &str) -> LowerError {
    LowerError {
        kind: LowerErrorKind::SourceError,
        ..error(statement, reason)
    }
}

/// Classify an expression the native parser rejected. Only failures that are
/// invalid DM regardless of parser coverage (unbalanced delimiters, an operator
/// with nothing after it, unterminated text) become source errors; anything
/// else may be valid DM the native parser does not cover yet.
pub(super) fn syntax_failure(text: &str, diagnostics: &[dm_syntax::Diagnostic]) -> LowerError {
    use dm_syntax::TokenKind;
    let lexed = dm_syntax::lex_spans(text);
    if let Some(diagnostic) = lexed.diagnostics.first() {
        return source_error(text, &diagnostic.message);
    }
    let tokens: Vec<_> = lexed
        .tokens
        .iter()
        .filter(|token| {
            !matches!(
                token.kind,
                TokenKind::Whitespace | TokenKind::Newline | TokenKind::Comment
            )
        })
        .map(|token| (token.kind, token.text(text)))
        .collect();
    let mut open = Vec::new();
    for (kind, token) in &tokens {
        if *kind != TokenKind::Punctuation {
            continue;
        }
        match *token {
            "(" | "[" | "{" => open.push(*token),
            ")" | "]" | "}" => {
                if open.pop().is_none() {
                    return source_error(
                        text,
                        &format!("{token}: expected }}\nlocation of top-most unmatched {{"),
                    );
                }
            }
            _ => {}
        }
    }
    if !open.is_empty() {
        // DreamMaker keeps reading continuation lines as arguments and fails at
        // the first that starts with a statement keyword.
        let keyword = text.lines().enumerate().skip(1).find_map(|(line, source)| {
            let first = source
                .trim_start()
                .split(|ch: char| !(ch.is_alphanumeric() || ch == '_'))
                .next()?;
            matches!(
                first,
                "return" | "if" | "else" | "for" | "while" | "do" | "switch" | "spawn" | "break"
                    | "continue" | "goto" | "del" | "set" | "try" | "catch" | "throw"
            )
            .then_some((line, first))
        });
        return source_error(
            text,
            &match keyword {
                Some((line, word)) => format!(
                    "{}{word}: missing comma ',' or right-paren ')'\n{word}: expected end of statement",
                    line_shift(line)
                ),
                None if open.last() == Some(&"[") => {
                    format!("{AT_END}}}: missing comma ',' or right-paren ')'\nlist started here")
                }
                None => "missing comma ',' or right-paren ')'".to_owned(),
            },
        );
    }
    // Two adjacent literal operands (`list(1 2)`) are never DM.
    if let Some(pair) = tokens.windows(2).find(|pair| {
        matches!(pair[0].0, TokenKind::Number | TokenKind::String)
            && matches!(pair[1].0, TokenKind::Number | TokenKind::String)
    }) {
        let token = pair[1].1;
        return source_error(
            text,
            &format!("{token}: missing comma ',' or right-paren ')'\n{token}: expected end of statement\nexpected expression"),
        );
    }
    // `L[]`: an index needs exactly one argument.
    if let Some(window) = tokens.windows(3).find(|window| {
        window[0].0 == TokenKind::Ident && window[1].1 == "[" && window[2].1 == "]"
    }) {
        return source_error(text, &format!("{}: expected 1 arg", window[0].1));
    }
    if diagnostics
        .iter()
        .any(|diagnostic| diagnostic.message == "ternary expression requires :")
    {
        return source_error(text, &format!("{AT_END}expected ':'"));
    }
    let dangling_operator = tokens.iter().enumerate().any(|(index, (kind, token))| {
        *kind == TokenKind::Operator
            && !matches!(*token, "++" | "--")
            && (index == 0 || tokens[index - 1].1 != *token)
            && tokens
                .get(index + 1)
                .is_none_or(|(_, next)| matches!(*next, ")" | "]" | ","))
    });
    if dangling_operator {
        return source_error(text, "missing expression");
    }
    let detail = diagnostics
        .first()
        .map_or("unrecognized syntax", |diagnostic| diagnostic.message.as_str());
    error(text, &format!("expression syntax is unsupported ({detail})"))
}

/// Line marker: DreamMaker found this error at the next token; when the
/// statement ends its file, that token is end of file, reported at the
/// line after the including directive.
pub(crate) const AT_END: &str = "\u{2}";

/// Marker moving a diagnostic `lines` lines below its statement; dmbc's
/// diagnostic writer applies it. Used where DreamMaker reports a later
/// continuation line. A message may also hold further same-line diagnostics
/// separated by newlines.
pub(crate) fn line_shift(lines: usize) -> String {
    if lines == 0 {
        String::new()
    } else {
        format!("\u{1}+{lines}\u{1}")
    }
}

pub(super) fn parenthesized(text: &str) -> Option<&str> {
    let open = text.find('(')?;
    text.ends_with(')')
        .then_some(&text[open + 1..text.len() - 1])
}

/// Decode a quoted DM literal using the same escapes as procedure lowering.
/// Interpolated literals require runtime evaluation and return `None`.
pub fn decode_constant_string_literal(raw: &str) -> Result<Option<Vec<u8>>, String> {
    Ok(string_literal_parts(raw)?
        .and_then(|(bytes, expressions)| expressions.is_empty().then_some(bytes)))
}

#[path = "helpers/literal_registration.rs"]
mod literal_registration;
pub use literal_registration::visit_constant_string_literals;

/// Fold only literal string concatenations through the authoritative scalar
/// evaluator. This admits no name, call, allocation, resource or conditional
/// branch; broader folding requires recorded semantic reads and runtime parity.
pub(super) fn fold_literal_string_expression(expr: &Expr) -> Option<Vec<u8>> {
    fn literal_tree(expr: &Expr) -> bool {
        match &expr.kind {
            ExprKind::Literal(_) => true,
            ExprKind::Group(inner) => literal_tree(inner),
            ExprKind::Binary { op, lhs, rhs } if op == "+" => {
                literal_tree(lhs) && literal_tree(rhs)
            }
            _ => false,
        }
    }
    let mut root = expr;
    while let ExprKind::Group(inner) = &root.kind {
        root = inner;
    }
    if !matches!(&root.kind, ExprKind::Binary { op, .. } if op == "+")
        || !literal_tree(root)
    {
        return None;
    }
    match dm_ir::constants::evaluate_expr_with_resources(
        root,
        |_| None,
        |raw| decode_constant_string_literal(raw).ok().flatten(),
        |_| None,
        |_| None,
    )? {
        dm_ir::constants::Constant::Text(text) => Some(text.into_bytes()),
        dm_ir::constants::Constant::EncodedText(bytes) => Some(bytes),
        _ => None,
    }
}

/// One shared literal parser for emission and source registration. Expression
/// nodes exist only for this literal's interpolation leaves, never a whole body.
fn string_literal_parts(raw: &str) -> Result<Option<(Vec<u8>, Vec<Expr>)>, String> {
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
        return Ok(Some((value.as_bytes().to_vec(), Vec::new())));
    }
    let value = if raw.starts_with("{\"") && raw.ends_with("\"}") && raw.len() >= 4 {
        &raw[2..raw.len() - 2]
    } else if raw.starts_with('"') && raw.ends_with('"') && raw.len() >= 2 {
        &raw[1..raw.len() - 1]
    } else {
        return Ok(None);
    };
    let (bytes, expressions) = parse_interpolated_string(value)?;
    Ok(Some((bytes, expressions)))
}

pub(super) fn parse_interpolated_string(value: &str) -> Result<(Vec<u8>, Vec<Expr>), String> {
    let mut template = Vec::new();
    let mut expressions = Vec::new();
    let mut next_marker = None;
    let mut substituted = false;
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
            let start = at + 1;
            let mut cursor = start;
            let mut depth = 1usize;
            let mut quote = false;
            while cursor < value.len() {
                let next = value[cursor..].chars().next().unwrap();
                if next == '"' {
                    quote = !quote;
                }
                if !quote {
                    if next == '[' {
                        depth += 1;
                    }
                    if next == ']' {
                        depth -= 1;
                        if depth == 0 {
                            break;
                        }
                    }
                }
                cursor += next.len_utf8();
            }
            if depth != 0 {
                return Err("unclosed string interpolation".into());
            }
            substituted = true;
            if value[start..cursor].trim().is_empty() {
                template.extend([0xff, next_marker.take().unwrap_or(1)]);
                at = cursor + 1;
                continue;
            }
            let source = dm_syntax::splice_expression_continuations(value[start..cursor].trim());
            let expression = parse_expression(&source);
            if !expression.diagnostics.is_empty() {
                return Err("invalid string interpolation expression".into());
            }
            expressions.push(expression.expr.ok_or("empty string interpolation")?);
            let marker = next_marker.take().unwrap_or_else(|| {
                if interpolation_starts_sentence(&template) {
                    2
                } else {
                    1
                }
            });
            template.extend([0xff, marker]);
            at = cursor + 1;
            continue;
        }
        let mut bytes = [0; 4];
        template.extend_from_slice(ch.encode_utf8(&mut bytes).as_bytes());
        at += ch.len_utf8();
    }
    Ok((template, expressions))
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

pub(super) fn parse_text_template(value: &str) -> Result<(Vec<u8>, Vec<Option<Expr>>), String> {
    let mut expanded = String::with_capacity(value.len());
    let mut slots = 0;
    let mut chars = value.chars().peekable();
    while let Some(ch) = chars.next() {
        if ch == '\\' {
            expanded.push(ch);
            if let Some(escaped) = chars.next() {
                expanded.push(escaped);
            }
            continue;
        }
        if ch == '[' && chars.peek() == Some(&']') {
            chars.next();
            expanded.push_str(&format!("[__dm_text_slot_{slots}__]"));
            slots += 1;
        } else {
            expanded.push(ch);
        }
    }
    let (template, expressions) = parse_interpolated_string(&expanded)?;
    let expressions = expressions
        .into_iter()
        .map(|expression| match &expression.kind {
            ExprKind::Ident(name) if name.starts_with("__dm_text_slot_") => None,
            _ => Some(expression),
        })
        .collect();
    Ok((template, expressions))
}

/// DreamMaker's capitalisation test looks through text-macro marker bytes: the
/// `0xff` lead byte is skipped like whitespace, so `"\green[x]"` (`ff 20`) starts
/// a sentence while `"\red[x]"` (`ff 1f`) does not.
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

pub(super) fn fold_number(expr: &Expr) -> Option<f32> {
    match &expr.kind {
        ExprKind::Literal(value) if value == "1.#INF" => Some(f32::INFINITY),
        ExprKind::Literal(value) if value.starts_with("0x") || value.starts_with("0X") => {
            u64::from_str_radix(&value[2..].replace('_', ""), 16)
                .ok()
                .map(|number| number as f32)
        }
        ExprKind::Literal(value) => value.parse().ok(),
        ExprKind::Unary { op, value } if op == "-" => Some(-fold_number(value)?),
        ExprKind::Group(value) => fold_number(value),
        ExprKind::Binary { op, lhs, rhs } => {
            let a = fold_number(lhs)?;
            let b = fold_number(rhs)?;
            Some(match op.as_str() {
                "+" => a + b,
                "-" => a - b,
                "*" => a * b,
                "/" if b != 0.0 => a / b,
                "%" if a.is_finite()
                    && b.is_finite()
                    && a >= i32::MIN as f32
                    && a < 2_147_483_648.0
                    && b >= i32::MIN as f32
                    && b < 2_147_483_648.0 =>
                {
                    // DM's % truncates both operands; %% is the real-valued
                    // modulo operator. Checked remainder avoids zero/overflow.
                    (a as i32).checked_rem(b as i32)? as f32
                }
                "<<" if a.is_finite()
                    && b.is_finite()
                    && a.fract() == 0.0
                    && b.fract() == 0.0
                    && a >= i32::MIN as f32
                    && a < 2_147_483_648.0
                    && (0.0..32.0).contains(&b) =>
                {
                    ((a.max(0.0) as u32).wrapping_shl(b as u32) & 0x00ff_ffff) as f32
                }
                ">>" if a.is_finite()
                    && b.is_finite()
                    && a.fract() == 0.0
                    && b.fract() == 0.0
                    && a >= i32::MIN as f32
                    && a < 2_147_483_648.0
                    && (0.0..32.0).contains(&b) =>
                {
                    ((a as i32 & 0x00ff_ffff) as u32).wrapping_shr(b as u32) as f32
                }
                _ => return None,
            })
        }
        _ => None,
    }
}

pub(super) fn is_output_target(expr: &Expr) -> bool {
    matches!(&expr.kind, ExprKind::Ident(name) if name == "world")
        || matches!(
            &expr.kind,
            ExprKind::Member { object, selector, via_colon: false }
                if matches!(&object.kind, ExprKind::Ident(name) if name == "world")
                    && selector == "log"
        )
}

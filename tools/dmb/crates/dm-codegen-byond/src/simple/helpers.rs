//! Helpers lowering over the shared compiler context.
use super::*;

pub(super) fn member_proc_selector(path: SymRef) -> VariableWord {
    if matches!(path, SymRef::Verb { .. }) {
        VariableWord::StaticVerb(path)
    } else {
        VariableWord::StaticProc(path)
    }
}

/// Value tag of the type path `/atom` itself. DreamMaker 516.1687 tags it like `/turf`; every other `/atom/...`
/// path is 9 (movable family).
pub(super) const ATOM_ROOT_TAG: u8 = 10;

pub(super) fn class_tag(path: &str) -> Option<u8> {
    if path.trim_start_matches('/') == "atom" {
        return Some(ATOM_ROOT_TAG);
    }
    family_tag(path)
}

/// Tag of the builtin family a path descends from (the first path segment).
pub(super) fn family_tag(path: &str) -> Option<u8> {
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
                "return"
                    | "if"
                    | "else"
                    | "for"
                    | "while"
                    | "do"
                    | "switch"
                    | "spawn"
                    | "break"
                    | "continue"
                    | "goto"
                    | "del"
                    | "set"
                    | "try"
                    | "catch"
                    | "throw"
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
    if let Some(window) = tokens
        .windows(3)
        .find(|window| window[0].0 == TokenKind::Ident && window[1].1 == "[" && window[2].1 == "]")
    {
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
        .map_or("unrecognized syntax", |diagnostic| {
            diagnostic.message.as_str()
        });
    error(
        text,
        &format!("expression syntax is unsupported ({detail})"),
    )
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
    // Raw-source entry points have no issued expression owner yet. Keep this
    // compatibility boundary; AST consumers use the borrowed overload below.
    decode_native_constant_string_literal(&dm_syntax::LiteralText::from(raw))
}

/// Decode an issued literal without re-parsing its interpolation expressions.
/// The byte result is owned by the caller; syntax stays shared with emission.
pub fn decode_native_constant_string_literal(
    literal: &dm_syntax::LiteralText,
) -> Result<Option<Vec<u8>>, String> {
    if literal.original_value().is_some(){return literal.decode_original_static_text()}
    Ok(literal
        .parts()
        .map_err(str::to_owned)?
        .filter(|parts| parts.expressions.is_empty())
        .map(|parts| parts.template.clone()))
}

#[path = "helpers/literal_registration.rs"]
mod literal_registration;
pub use literal_registration::{
    visit_constant_string_literals, visit_native_constant_string_literals,
};

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
    if !matches!(&root.kind, ExprKind::Binary { op, .. } if op == "+") || !literal_tree(root) {
        return None;
    }
    match dm_ir::constants::evaluate_expr_with_resources(
        root,
        |_| None,
        |literal| {
            decode_native_constant_string_literal(literal)
                .ok()
                .flatten()
        },
        |_| None,
        |_| None,
    )? {
        dm_ir::constants::Constant::Text(text) => Some(text.into_bytes()),
        dm_ir::constants::Constant::EncodedText(bytes) => Some(bytes),
        _ => None,
    }
}

pub(super) use dm_syntax::literal::parse_interpolated_string;

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
/// Bits DreamMaker's constant folder sees for a number: positive values saturate at 32 bits, negative ones at `i32::MIN`
/// (pinned 516.1687: `1.#INF | 1` is 16777215, `2147483648 | 1` is 1, `4294967296 | 1` is 16777215).
fn fold_bits(number: f32) -> Option<u32> {
    if number.is_nan() {
        return None;
    }
    Some(if number >= 0.0 {
        (number as u64).min(u64::from(u32::MAX)) as u32
    } else {
        (number as i64).max(i64::from(i32::MIN)) as i32 as u32
    })
}

/// Bitwise results are 24 bits wide.
const FOLD_MASK: u32 = 0x00ff_ffff;

/// A shift count: negative counts act as 0 and the rest is taken modulo 32.
fn fold_shift_count(number: f32) -> Option<u32> {
    if number.is_nan() {
        return None;
    }
    Some(if number < 0.0 {
        0
    } else {
        (number as u64 & 31) as u32
    })
}

/// The value DreamMaker's constant folder gives a numeric expression, or `None` where DreamMaker does not fold (comparisons, strings,
/// non-constant operands) or reports an error (`x % 0.5`, `0 ** -1`, `-1 ** 0.5`). Numbers are 32-bit floats.
pub(super) fn fold_number(expr: &Expr) -> Option<f32> {
    match &expr.kind {
        ExprKind::Literal(value) if value.original_value().is_some() => {
            // Actual Original token VALUE precedes any spelling inference.
            // Recovered Int0 and exact Float bits must not be reparsed as the
            // offending/raw token. String/resource never coerce via raw text.
            match value.original_value().expect("same immutable scalar facts") {
                dm_syntax::OriginalTokenValue::Int(number)=>Some(number as f32),
                dm_syntax::OriginalTokenValue::Float(number)=>Some(number),
                _=>None,
            }
        }
        ExprKind::Literal(value) if value == "1.#INF" => Some(f32::INFINITY),
        ExprKind::Literal(value) if value == "TRUE" => Some(1.0),
        ExprKind::Literal(value) if value == "FALSE" => Some(0.0),
        ExprKind::Literal(value) if value.starts_with("0x") || value.starts_with("0X") => {
            u64::from_str_radix(&value[2..].replace('_', ""), 16)
                .ok()
                .map(|number| number as f32)
        }
        ExprKind::Literal(value) => value.parse().ok(),
        ExprKind::Unary { op, value } if op == "!" && fold_number(value).is_none() => {
            // `!"text"`: DreamMaker folds the negation of a plain text literal.
            let mut inner = value.as_ref();
            while let ExprKind::Group(next) = &inner.kind {
                inner = next;
            }
            let ExprKind::Literal(raw) = &inner.kind else {
                return None;
            };
            if raw.starts_with("@'") {
                return None;
            }
            let text = decode_native_constant_string_literal(raw).ok().flatten()?;
            Some(if text.is_empty() { 1.0 } else { 0.0 })
        }
        ExprKind::Unary { op, value } => {
            let a = fold_number(value)?;
            match op.as_str() {
                "-" => Some(-a),
                "!" => Some(if a == 0.0 { 1.0 } else { 0.0 }),
                // Negative operands count as 0 here, as they do for `<<`.
                "~" => Some((!(if a < 0.0 { 0 } else { fold_bits(a)? }) & FOLD_MASK) as f32),
                _ => None,
            }
        }
        ExprKind::Group(value) => fold_number(value),
        ExprKind::Call { callee, args } => {
            let ExprKind::Ident(name) = &callee.kind else {
                return None;
            };
            // `text2ascii("A")` is the code of the first character; with a position DreamMaker leaves the call.
            if name == "text2ascii" {
                let [text] = args.as_slice() else { return None };
                let bytes = constant_text(text)?;
                return Some(
                    match std::str::from_utf8(&bytes)
                        .ok()
                        .and_then(|text| text.chars().next())
                    {
                        Some(first) => first as u32 as f32,
                        None => f32::from(bytes.first().copied().unwrap_or(0)),
                    },
                );
            }
            let values: Vec<f32> = args.iter().map(fold_number).collect::<Option<_>>()?;
            fold_builtin_call(name, &values)
        }
        ExprKind::Conditional {
            condition,
            then_value,
            else_value,
        } => {
            if fold_number(condition)? != 0.0 {
                fold_number(then_value)
            } else {
                fold_number(else_value)
            }
        }
        ExprKind::Binary { op, lhs, rhs } if op == "&&" || op == "||" => {
            let a = fold_number(lhs)?;
            // The right side is not evaluated when the left decides, so it need not be constant then.
            if (op == "&&") == (a != 0.0) {
                fold_number(rhs)
            } else {
                Some(a)
            }
        }
        ExprKind::Binary { op, lhs, rhs } => {
            let a = fold_number(lhs)?;
            let b = fold_number(rhs)?;
            Some(match op.as_str() {
                "+" => a + b,
                "-" => a - b,
                "*" => a * b,
                "/" if b != 0.0 => a / b,
                "%" => {
                    // DM's % truncates both operands; %% is the real-valued modulo operator. A divisor that truncates to 0 is a
                    // compile error, and DreamMaker's own folder crashes on i32::MIN % -1, so neither is folded.
                    let (x, y) = (fold_bits_signed(a)?, fold_bits_signed(b)?);
                    if y == 0 || (x == i64::from(i32::MIN) && y == -1) {
                        return None;
                    }
                    (x % y) as f32
                }
                "**" => {
                    if (a < 0.0 && b.fract() != 0.0) || (a == 0.0 && b < 0.0) {
                        return None;
                    }
                    (f64::from(a)).powf(f64::from(b)) as f32
                }
                "&" => ((fold_bits(a)? & fold_bits(b)?) & FOLD_MASK) as f32,
                "|" => ((fold_bits(a)? | fold_bits(b)?) & FOLD_MASK) as f32,
                "^" => ((fold_bits(a)? ^ fold_bits(b)?) & FOLD_MASK) as f32,
                "<<" => {
                    // Negative values shift to 0.
                    if a < 0.0 {
                        0.0
                    } else {
                        (fold_bits(a)?.wrapping_shl(fold_shift_count(b)?) & FOLD_MASK) as f32
                    }
                }
                ">>" => ((fold_bits(a)? & FOLD_MASK) >> fold_shift_count(b)?) as f32,
                _ => return None,
            })
        }
        _ => None,
    }
}

/// The bytes of a constant text argument: a plain literal or a concatenation of literals.
pub(super) fn constant_text(expr: &Expr) -> Option<Vec<u8>> {
    let mut root = expr;
    while let ExprKind::Group(inner) = &root.kind {
        root = inner;
    }
    if let ExprKind::Literal(raw) = &root.kind {
        return decode_native_constant_string_literal(raw).ok().flatten();
    }
    fold_literal_string_expression(root)
}

/// The lowercase hex of the digest DreamMaker folds `md5("text")` to.
pub(super) fn md5_hex(bytes: &[u8]) -> String {
    format!("{:x}", md5::compute(bytes))
}

/// The lowercase hex of the digest DreamMaker folds `sha1("text")` to.
pub(super) fn sha1_hex(bytes: &[u8]) -> String {
    let mut state: [u32; 5] = [
        0x6745_2301,
        0xefcd_ab89,
        0x98ba_dcfe,
        0x1032_5476,
        0xc3d2_e1f0,
    ];
    let mut message = bytes.to_vec();
    message.push(0x80);
    while message.len() % 64 != 56 {
        message.push(0);
    }
    message.extend_from_slice(&((bytes.len() as u64) * 8).to_be_bytes());
    for block in message.chunks_exact(64) {
        let mut w = [0u32; 80];
        for (index, word) in block.chunks_exact(4).enumerate() {
            w[index] = u32::from_be_bytes([word[0], word[1], word[2], word[3]]);
        }
        for index in 16..80 {
            w[index] = (w[index - 3] ^ w[index - 8] ^ w[index - 14] ^ w[index - 16]).rotate_left(1);
        }
        let [mut a, mut b, mut c, mut d, mut e] = state;
        for (index, word) in w.iter().enumerate() {
            let (f, k) = match index {
                0..=19 => ((b & c) | (!b & d), 0x5a82_7999),
                20..=39 => (b ^ c ^ d, 0x6ed9_eba1),
                40..=59 => ((b & c) | (b & d) | (c & d), 0x8f1b_bcdc),
                _ => (b ^ c ^ d, 0xca62_c1d6),
            };
            let next = a
                .rotate_left(5)
                .wrapping_add(f)
                .wrapping_add(e)
                .wrapping_add(k)
                .wrapping_add(*word);
            e = d;
            d = c;
            c = b.rotate_left(30);
            b = a;
            a = next;
        }
        for (slot, value) in state.iter_mut().zip([a, b, c, d, e]) {
            *slot = slot.wrapping_add(value);
        }
    }
    state.iter().map(|word| format!("{word:08x}")).collect()
}

/// The builtin math functions DreamMaker evaluates at compile time when every argument is a literal (pinned 516.1687; `min` and
/// `max` are not folded). Angles are in degrees; arguments outside a function's domain are compile errors there, not folded.
/// `round(x)` is a floor (`round(0.5)` is 0, `round(-2.5)` is -3) and `round(x, step)` is `floor(x / step + 0.5) * step`.
pub(super) fn fold_builtin_call(name: &str, values: &[f32]) -> Option<f32> {
    // The angle is reduced to a turn first (it changes the last digit of `tan(-2147483648)`).
    let radians = |degrees: f32| (f64::from(degrees) % 360.0).to_radians();
    let x = |index: usize| f64::from(values[index]);
    let result: f64 = match (name, values.len()) {
        ("abs", 1) => x(0).abs(),
        ("floor", 1) | ("round", 1) => x(0).floor(),
        ("ceil", 1) => x(0).ceil(),
        ("sqrt", 1) if values[0] >= 0.0 => x(0).sqrt(),
        ("sin", 1) => radians(values[0]).sin(),
        ("cos", 1) => radians(values[0]).cos(),
        // Differs from DreamMaker in the last digit only for angles beyond 2^30 degrees.
        ("tan", 1) => radians(values[0]).tan(),
        ("arcsin", 1) if values[0].abs() <= 1.0 => x(0).asin().to_degrees(),
        ("arccos", 1) if values[0].abs() <= 1.0 => x(0).acos().to_degrees(),
        ("arctan", 1) => x(0).atan().to_degrees(),
        ("arctan", 2) => x(1).atan2(x(0)).to_degrees(),
        ("log", 1) if values[0] > 0.0 => x(0).ln(),
        ("log", 2) if values[0] > 0.0 && values[0] != 1.0 && values[1] > 0.0 => {
            x(1).ln() / x(0).ln()
        }
        // 32-bit arithmetic, as DreamMaker does it (`round(16777215, 1)` is 16777216).
        ("round", 2) if values[1] != 0.0 => {
            return Some((values[0] / values[1] + 0.5).floor() * values[1])
        }
        // A reversed range is swapped first.
        ("clamp", 3) => {
            let (low, high) = if values[1] > values[2] {
                (values[2], values[1])
            } else {
                (values[1], values[2])
            };
            return Some(values[0].max(low).min(high));
        }
        _ => return None,
    };
    Some(result as f32)
}

/// `%` operands: positive values saturate at 32 bits unsigned, negative ones at `i32::MIN`, as 64-bit integers.
fn fold_bits_signed(number: f32) -> Option<i64> {
    if number.is_nan() {
        return None;
    }
    Some(if number >= 0.0 {
        (number as u64).min(u64::from(u32::MAX)) as i64
    } else {
        (number as i64).max(i64::from(i32::MIN))
    })
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

#[cfg(test)]
mod native_literal_decode_tests {
    use super::*;
    #[test]
    fn native_decoder_reuses_literal_parts_and_matches_raw_boundary_bytes() {
        for raw in [
            r#""line\n""#,
            r#"@"[literal]""#,
            r#""[dynamic()]""#,
            r#""\red text""#,
        ] {
            let expression = parse_expression(raw).expr.unwrap();
            let ExprKind::Literal(issued) = &expression.kind else {
                panic!()
            };
            let before = issued.parts().unwrap().unwrap();
            let result = decode_native_constant_string_literal(issued).unwrap();
            assert_eq!(result, decode_constant_string_literal(raw).unwrap());
            assert!(std::ptr::eq(before, issued.parts().unwrap().unwrap()));
            assert_eq!(
                decode_native_constant_string_literal(issued).unwrap(),
                result
            );
        }
    }
}

#[cfg(test)]mod original_numeric_fact_fold_tests{
 use super::*;use dm_syntax::{LiteralText,OriginalTokenValue as V,SettingAdmission};use std::sync::{atomic::{Ordering}};
 fn literal(raw:&str,value:V<&str>,a:&SettingAdmission<'_>)->Expr{Expr{span:dm_syntax::Span::new(0,raw.len()),kind:ExprKind::Literal(LiteralText::from_original_value_data(raw.to_owned(),0,value,a).unwrap())}}
 #[test]fn actual_original_numeric_facts_precede_raw_overflow_hex_boolean_and_exponent_inference(){
  let counter=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let poll=||Ok(());let a=SettingAdmission::new(&counter,1<<20,&poll);
  for(raw,value,bits)in[("2147483648",V::Int(0),0f32.to_bits()),("0xFFFFFFFF",V::Int(-1),(-1f32).to_bits()),("TRUE",V::Int(0),0f32.to_bits()),("1e3",V::Float(1000.0),1000f32.to_bits()),("0",V::Float(-0.0),(-0f32).to_bits()),("1.#IND",V::Float(f32::from_bits(0x7fc00111)),0x7fc00111)]{let expr=literal(raw,value,&a);assert_eq!(fold_number(&expr).unwrap().to_bits(),bits);}
  assert_eq!(counter.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]fn static_string_and_resource_that_look_numeric_are_not_coerced_or_raw_parsed(){
  let counter=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let poll=||Ok(());let a=SettingAdmission::new(&counter,1<<20,&poll);for value in [V::String("1"),V::Resource("1")]{let expr=literal("1",value,&a);assert!(fold_number(&expr).is_none());}assert_eq!(counter.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]fn typed_numeric_recursion_keeps_existing_short_circuit_and_native_paths(){
  let counter=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let poll=||Ok(());let a=SettingAdmission::new(&counter,1<<20,&poll);let left=literal("overflow text",V::Int(0),&a);let rhs=Expr{span:dm_syntax::Span::new(20,30),kind:ExprKind::Ident("dynamic".into())};let expr=Expr{span:dm_syntax::Span::new(0,30),kind:ExprKind::Binary{op:"&&".into(),lhs:Box::new(left),rhs:Box::new(rhs)}};assert_eq!(fold_number(&expr),Some(0.0));for(raw,expected)in[("1.#INF",f32::INFINITY),("0x10",16.0),("2+3",5.0)]{assert_eq!(fold_number(&parse_expression(raw).expr.unwrap()),Some(expected));}for(raw,expected)in[("TRUE",1.0),("FALSE",0.0)]{let native=Expr{span:dm_syntax::Span::new(0,raw.len()),kind:ExprKind::Literal(raw.into())};assert_eq!(fold_number(&native),Some(expected));}
 }
}

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
        statement: statement.into(),
        reason: reason.into(),
        ..LowerError::default()
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
        return Ok(Some(value.as_bytes().to_vec()));
    }
    let value = if raw.starts_with("{\"") && raw.ends_with("\"}") && raw.len() >= 4 {
        &raw[2..raw.len() - 2]
    } else if raw.starts_with('"') && raw.ends_with('"') && raw.len() >= 2 {
        &raw[1..raw.len() - 1]
    } else {
        return Ok(None);
    };
    let (bytes, expressions) = parse_interpolated_string(value)?;
    Ok(expressions.is_empty().then_some(bytes))
}

pub(super) fn parse_interpolated_string(value: &str) -> Result<(Vec<u8>, Vec<Expr>), String> {
    let mut template = Vec::new();
    let mut expressions = Vec::new();
    let mut next_marker = None;
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
            if rest.starts_with('x') && rest.len() >= 3 {
                let hex = &rest[1..3];
                if let Ok(byte) = u8::from_str_radix(hex, 16) {
                    let mut encoded = [0; 4];
                    template
                        .extend_from_slice(char::from(byte).encode_utf8(&mut encoded).as_bytes());
                    at += 3;
                    continue;
                }
            }
            let control = [
                ("improper", 0x16, false, true),
                ("proper", 0x15, false, true),
                ("himself", 0x11, false, false),
                ("hers", 0x0e, false, false),
                ("The", 0x09, true, true),
                ("the", 0x08, true, true),
                ("his", 0x0c, false, false),
                ("he", 0x0a, false, false),
                ("A", 0x07, true, true),
                ("a", 0x06, true, true),
                ("ref", 0x2a, true, false),
                ("roman", 0x2c, true, false),
                ("Roman", 0x2d, true, false),
                ("th", 0x05, false, false),
                ("s", 0x14, false, false),
            ]
            .into_iter()
            .find(|(name, ..)| rest.starts_with(name));
            if let Some((name, marker, modifies_next, consumes_space)) = control {
                if modifies_next && !consumes_space {
                    next_marker = Some(marker);
                } else {
                    template.extend([0xff, marker]);
                    if modifies_next {
                        next_marker = Some(0x03);
                    }
                }
                at += name.len();
                if consumes_space && value[at..].starts_with(' ') {
                    at += 1;
                }
                continue;
            }
            let escape = value[at..].chars().next().ok_or("trailing string escape")?;
            let escaped = match escape {
                'n' => "\n",
                'r' => "\r",
                't' => "\t",
                '\\' => "\\",
                '"' => "\"",
                '\'' => "'",
                '[' => "[",
                ']' => "]",
                '<' => "&lt;",
                '>' => "&gt;",
                '&' => "&amp;",
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

fn interpolation_starts_sentence(mut prefix: &[u8]) -> bool {
    loop {
        while prefix
            .last()
            .is_some_and(|byte| matches!(byte, b' ' | b'\n' | b'\t' | b'\'' | b'"'))
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

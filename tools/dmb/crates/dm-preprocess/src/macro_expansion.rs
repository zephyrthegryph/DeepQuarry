use super::*;

pub(super) fn strip_macro_comments(replacement: &str) -> String {
    let lexed = lex_spans(replacement);
    let mut out = String::with_capacity(replacement.len());
    for token in lexed.tokens {
        if token.kind == TokenKind::Comment {
            out.push(' ');
        } else {
            out.push_str(token.text(replacement));
        }
    }
    out.trim().to_owned()
}

pub(super) fn expand(
    source: &str,
    macros: &dyn MacroLookup,
    depth: usize,
    location: ExpandLocation<'_>,
) -> Result<String, String> {
    expand_mode(source, macros, depth, location, false)
}

fn expand_mode(
    source: &str,
    macros: &dyn MacroLookup,
    depth: usize,
    location: ExpandLocation<'_>,
    substitute_only: bool,
) -> Result<String, String> {
    expand_mode_disabled(
        source,
        macros,
        depth,
        location,
        substitute_only,
        &mut Vec::new(),
    )
}

type MacroTrace<'a> = dyn FnMut(&str, Span, &[&str]) + 'a;

/// The diagnostic for a macro call whose closing parenthesis is not on the logical line.
/// A preprocessor directive can sit inside the argument list (valid DM), so callers hold
/// such a line and join it with the active lines that follow.
pub(crate) const MISSING_CALL_CLOSE: &str = "missing ) in macro call";
/// Bound on the lines joined into one open macro call before it is reported as unclosed.
pub(crate) const MAX_OPEN_CALL_LINES: usize = 256;

pub(crate) fn expand_traced(
    source: &str,
    macros: &dyn MacroLookup,
    location: ExpandLocation<'_>,
    trace: &mut MacroTrace<'_>,
) -> Result<String, String> {
    expand_mode_disabled_traced(
        source,
        macros,
        0,
        location,
        false,
        &mut Vec::new(),
        &mut Some(trace),
    )
}

fn expand_mode_disabled<'a>(
    source: &str,
    macros: &'a dyn MacroLookup,
    depth: usize,
    location: ExpandLocation<'_>,
    substitute_only: bool,
    disabled: &mut Vec<&'a str>,
) -> Result<String, String> {
    expand_mode_disabled_traced(
        source,
        macros,
        depth,
        location,
        substitute_only,
        disabled,
        &mut None,
    )
}

// Preserve original UTF-8 boundary checks in the shared expansion implementation.
#[allow(clippy::sliced_string_as_bytes)]
fn expand_mode_disabled_traced<'a>(
    source: &str,
    macros: &'a dyn MacroLookup,
    depth: usize,
    location: ExpandLocation<'_>,
    substitute_only: bool,
    disabled: &mut Vec<&'a str>,
    trace: &mut Option<&mut MacroTrace<'_>>,
) -> Result<String, String> {
    if depth > 32 {
        return Err("macro expansion exceeded depth 32".into());
    }
    let lexed = lex_spans(source);
    if let Some(diagnostic) = lexed.diagnostics.first() {
        // The logical line already locates the failure; a byte offset into
        // the expanded line is not a user-facing position.
        return Err(diagnostic.message.clone());
    }
    let tokens = lexed.tokens;
    let mut out = String::new();
    let mut i = 0;
    while i < tokens.len() {
        let token = &tokens[i];
        let token_text = token.text(source);
        if token.kind == TokenKind::String {
            if token_text.starts_with("@\"") {
                out.push_str(token_text);
                i += 1;
                continue;
            }
            out.push_str(&expand_interpolations(
                token_text,
                macros,
                depth + 1,
                location,
                substitute_only,
                disabled,
                trace,
            )?);
            i += 1;
            continue;
        }
        if token.kind == TokenKind::Ident {
            // `defined` consumes a macro *name*. Function-like macros may
            // introduce it only after parameter substitution, so protect its
            // operand during the later ordinary expansion pass as well.
            if token_text == "defined" && !substitute_only {
                let mut operand = i + 1;
                while tokens.get(operand).is_some_and(|next| {
                    matches!(next.kind, TokenKind::Whitespace | TokenKind::Newline)
                }) {
                    operand += 1;
                }
                if tokens
                    .get(operand)
                    .is_some_and(|next| next.text(source) == "(")
                {
                    operand += 1;
                    while tokens.get(operand).is_some_and(|next| {
                        matches!(next.kind, TokenKind::Whitespace | TokenKind::Newline)
                    }) {
                        operand += 1;
                    }
                }
                if let Some(name) = tokens
                    .get(operand)
                    .filter(|next| next.kind == TokenKind::Ident)
                {
                    out.push_str(&source[token.span.start..name.span.end]);
                    i = operand + 1;
                    continue;
                }
            }
            if let Some((name, def)) = macros
                .get_key_value(token_text)
                .filter(|_| !disabled.contains(&token_text))
            {
                if let Some(params) = &def.parameters {
                    let Some(open) = tokens.get(i + 1).filter(|t| t.text(source) == "(") else {
                        out.push_str(token_text);
                        i += 1;
                        continue;
                    };
                    let _ = open;
                    let (mut args, after) = parse_arguments(&tokens, source, i + 1)?;
                    if args.is_empty() && params.len() == 1 && !def.variadic {
                        args.push(String::new());
                    }
                    let required = params.len() - usize::from(def.variadic);
                    if args.len() < required || (!def.variadic && args.len() != required) {
                        // DreamMaker's wording; the count detail is not part of it.
                        let _ = (token_text, required);
                        return Err("incorrect number of macro arguments".into());
                    }
                    let args = if def.variadic {
                        let mut packed = args[..required].to_vec();
                        packed.push(args[required..].join(","));
                        packed
                    } else {
                        args
                    };
                    if !substitute_only {
                        if let Some(callback) = trace.as_deref_mut() {
                            callback(name, token.span, disabled);
                        }
                    }
                    // Expand arguments before disabling this invocation. A
                    // nested F(F(x)) is valid; only F inside F's replacement
                    // is recursive. Paste/stringification consume raw spelling.
                    let raw_parameters = raw_macro_parameters(def, macros, &mut BTreeSet::new());
                    let args = params
                        .iter()
                        .zip(args)
                        .map(|(parameter, argument)| {
                            if substitute_only || raw_parameters.contains(parameter.as_str()) {
                                Ok(argument)
                            } else {
                                expand_mode_disabled_traced(
                                    &argument,
                                    macros,
                                    depth + 1,
                                    location,
                                    false,
                                    disabled,
                                    trace,
                                )
                            }
                        })
                        .collect::<Result<Vec<_>, String>>()?;
                    let replacements = params
                        .iter()
                        .cloned()
                        .zip(args)
                        .map(|(name, replacement)| {
                            (
                                name,
                                Macro {
                                    parameters: None,
                                    variadic: false,
                                    replacement,
                                },
                            )
                        })
                        .collect::<BTreeMap<_, _>>();
                    let substituted =
                        expand_mode(&def.replacement, &replacements, depth + 1, location, true)?;
                    disabled.push(name);
                    let expanded = expand_mode_disabled_traced(
                        &substituted,
                        macros,
                        depth + 1,
                        location,
                        false,
                        disabled,
                        trace,
                    );
                    disabled.pop();
                    out.push_str(&expanded?);
                    i = after;
                    continue;
                }
                if !substitute_only {
                    if let Some(callback) = trace.as_deref_mut() {
                        callback(name, token.span, disabled);
                    }
                }
                if substitute_only {
                    out.push_str(&def.replacement);
                } else {
                    // Rescan an object alias together with its following call
                    // arguments, so ALIAS(x) -> FUNCTION(x) actually invokes
                    // the function macro rather than leaving its name behind.
                    let mut target = def.replacement.trim();
                    let mut seen = BTreeSet::new();
                    while seen.insert(target) {
                        let Some(alias) = macros.get(target) else {
                            break;
                        };
                        if alias.parameters.is_some() {
                            break;
                        }
                        target = alias.replacement.trim();
                    }
                    if macros
                        .get(target)
                        .is_some_and(|definition| definition.parameters.is_some())
                        && tokens
                            .get(i + 1)
                            .is_some_and(|token| token.text(source) == "(")
                    {
                        let (_, after) = parse_arguments(&tokens, source, i + 1)?;
                        let call = format!(
                            "{}{}",
                            def.replacement,
                            &source[tokens[i + 1].span.start..tokens[after - 1].span.end]
                        );
                        disabled.push(name);
                        let expanded = expand_mode_disabled_traced(
                            &call,
                            macros,
                            depth + 1,
                            location,
                            false,
                            disabled,
                            trace,
                        );
                        disabled.pop();
                        out.push_str(&expanded?);
                        i = after;
                        continue;
                    }
                    disabled.push(name);
                    let expanded = expand_mode_disabled_traced(
                        &def.replacement,
                        macros,
                        depth + 1,
                        location,
                        false,
                        disabled,
                        trace,
                    );
                    disabled.pop();
                    out.push_str(&expanded?);
                }
                i += 1;
                continue;
            }
            if token_text == "__LINE__" {
                macros.location_read(false);
                out.push_str(&location.line.to_string());
                i += 1;
                continue;
            }
            if token_text == "__FILE__" {
                macros.location_read(true);
                out.push('"');
                for ch in location.file_name.chars() {
                    if matches!(ch, '\\' | '"') {
                        out.push('\\');
                    }
                    out.push(ch);
                }
                out.push('"');
                i += 1;
                continue;
            }
        }
        if token_text == "#"
            && tokens
                .get(i + 1)
                .is_some_and(|next| next.text(source) == "#")
        {
            if let Some(next) = tokens.get(i + 2) {
                if next.kind == TokenKind::Ident
                    && macros.get(next.text(source)).is_some_and(|definition| {
                        definition.parameters.is_none() && definition.replacement.is_empty()
                    })
                {
                    while out.ends_with(char::is_whitespace) {
                        out.pop();
                    }
                    if out.ends_with(',') {
                        out.pop();
                    }
                    i += 3;
                    continue;
                }
            }
            while out.ends_with(char::is_whitespace) {
                out.pop();
            }
            i += 2;
            while tokens
                .get(i)
                .is_some_and(|next| next.kind == TokenKind::Whitespace)
            {
                i += 1;
            }
            continue;
        }
        if token_text == "#" {
            if let Some(next) = tokens.get(i + 1) {
                if next.text(source) == "INF"
                    && out.as_bytes().last() == Some(&b'.')
                    && out[..out.len() - 1]
                        .as_bytes()
                        .last()
                        .is_some_and(u8::is_ascii_digit)
                {
                    out.push_str("#INF");
                    i += 2;
                    continue;
                }
                if next.kind == TokenKind::Ident {
                    if let Some(argument) = macros
                        .get(next.text(source))
                        .filter(|definition| definition.parameters.is_none())
                    {
                        out.push('"');
                        for ch in argument.replacement.chars() {
                            if matches!(ch, '\\' | '"') {
                                out.push('\\');
                            }
                            out.push(ch);
                        }
                        out.push('"');
                        i += 2;
                        continue;
                    }
                }
            }
            return Err("unsupported # token outside macro stringification".into());
        }
        out.push_str(token_text);
        i += 1;
    }
    Ok(out)
}

fn expand_interpolations<'a>(
    literal: &str,
    macros: &'a dyn MacroLookup,
    depth: usize,
    location: ExpandLocation<'_>,
    substitute_only: bool,
    disabled: &mut Vec<&'a str>,
    trace: &mut Option<&mut MacroTrace<'_>>,
) -> Result<String, String> {
    let mut result = String::with_capacity(literal.len());
    let mut cursor = 0;
    let mut chars = literal.char_indices().peekable();
    let mut escaped = false;
    while let Some((at, ch)) = chars.next() {
        if escaped {
            escaped = false;
            continue;
        }
        if ch == '\\' {
            escaped = true;
            continue;
        }
        if ch != '[' {
            continue;
        }
        let start = at + 1;
        let mut nesting = 1usize;
        let mut expression_escaped = false;
        let mut end = None;
        while let Some((offset, current)) = chars.next() {
            if expression_escaped {
                expression_escaped = false;
                continue;
            }
            if current == '\\' {
                expression_escaped = true;
                continue;
            }
            match current {
                '"' => {
                    let Some(length) =
                        quoted_end(&literal[offset..], false, literal[..offset].ends_with('@'))
                    else {
                        return Err("unclosed string interpolation".into());
                    };
                    while chars
                        .peek()
                        .is_some_and(|(next, _)| *next < offset + length)
                    {
                        chars.next();
                    }
                }
                '\'' => {
                    let mut escaped_quote = false;
                    let Some((close, _)) = literal[offset + 1..].char_indices().find(|(_, ch)| {
                        if escaped_quote {
                            escaped_quote = false;
                            false
                        } else if *ch == '\\' && !literal[..offset].ends_with('@') {
                            escaped_quote = true;
                            false
                        } else {
                            *ch == '\''
                        }
                    }) else {
                        return Err("unclosed string interpolation".into());
                    };
                    let close = offset + 1 + close + 1;
                    while chars.peek().is_some_and(|(next, _)| *next < close) {
                        chars.next();
                    }
                }
                '[' => nesting += 1,
                ']' => {
                    nesting -= 1;
                    if nesting == 0 {
                        end = Some(offset);
                        break;
                    }
                }
                _ => {}
            }
        }
        let Some(end) = end else {
            return Err("unclosed string interpolation".into());
        };
        result.push_str(&literal[cursor..start]);
        result.push_str(&expand_mode_disabled_traced(
            &literal[start..end],
            macros,
            depth + 1,
            location,
            substitute_only,
            disabled,
            trace,
        )?);
        cursor = end;
    }
    result.push_str(&literal[cursor..]);
    Ok(result)
}

/// Parameters feeding token-sensitive operators stay raw, including through
/// forwarding macros such as WRAP(x) -> STRINGIFY(x) or CHECK(x) -> defined(x).
fn raw_macro_parameters(
    definition: &Macro,
    macros: &dyn MacroLookup,
    visiting: &mut BTreeSet<String>,
) -> BTreeSet<String> {
    let scanned = lex_spans(&definition.replacement);
    let tokens: Vec<_> = scanned
        .tokens
        .into_iter()
        .filter(|token| {
            !matches!(
                token.kind,
                TokenKind::Whitespace | TokenKind::Newline | TokenKind::Comment
            )
        })
        .collect();
    let text = |index: usize| {
        tokens
            .get(index)
            .map(|token| token.text(&definition.replacement))
    };
    let mut raw = BTreeSet::new();
    for (index, token) in tokens.iter().enumerate() {
        if token.kind != TokenKind::Ident {
            continue;
        }
        let prior = index.checked_sub(1).and_then(&text);
        let before_prior = index.checked_sub(2).and_then(&text);
        if prior == Some("#")
            || text(index + 1) == Some("#")
            || prior == Some("defined")
            || (prior == Some("(") && before_prior == Some("defined"))
        {
            raw.insert(token.text(&definition.replacement).to_owned());
        }
        let callee = token.text(&definition.replacement);
        if text(index + 1) != Some("(")
            || visiting.len() >= 64
            || !visiting.insert(callee.to_owned())
        {
            continue;
        }
        if let Some(nested) = macros
            .get(callee)
            .filter(|nested| nested.parameters.is_some())
        {
            if let Ok((arguments, _)) = parse_arguments(&tokens, &definition.replacement, index + 1)
            {
                let nested_raw = raw_macro_parameters(nested, macros, visiting);
                for (parameter, argument) in
                    nested.parameters.as_ref().unwrap().iter().zip(arguments)
                {
                    if nested_raw.contains(parameter) {
                        // Only exact forwarding propagates a raw name. Expressions
                        // remain expressions and are diagnosed by defined if invalid.
                        if definition
                            .parameters
                            .as_ref()
                            .is_some_and(|params| params.contains(&argument))
                        {
                            raw.insert(argument);
                        }
                    }
                }
            }
        }
        visiting.remove(callee);
    }
    raw
}

fn parse_arguments(
    tokens: &[SpanToken],
    source: &str,
    open: usize,
) -> Result<(Vec<String>, usize), String> {
    let mut args = Vec::new();
    let mut value = String::new();
    let mut depth = 0;
    for (i, token) in tokens.iter().enumerate().skip(open) {
        match token.text(source) {
            "(" => {
                if depth > 0 {
                    value.push('(');
                }
                depth += 1;
            }
            ")" => {
                depth -= 1;
                if depth == 0 {
                    if !value.trim().is_empty() || !args.is_empty() {
                        args.push(value.trim().to_owned());
                    }
                    return Ok((args, i + 1));
                }
                value.push(')');
            }
            "," if depth == 1 => {
                args.push(value.trim().to_owned());
                value.clear();
            }
            _ => value.push_str(token.text(source)),
        }
    }
    Err(MISSING_CALL_CLOSE.into())
}

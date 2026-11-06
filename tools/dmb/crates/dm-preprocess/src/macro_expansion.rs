use super::*;
#[path="macro_storage.rs"]mod funded_storage;
#[path="original_macro_substitution.rs"]mod original_substitution;
#[path="original_macro_values.rs"]mod original_values;
#[path="original_macro_demand.rs"]mod original_demand;
#[path="original_macro_numbers.rs"]mod original_numbers;
#[path="original_macro_define.rs"]mod original_define;
#[path="original_macro_lexical_values.rs"]mod original_lexical_values;
pub(crate) use funded_storage::{empty_exact, FundedMacroOutput};
pub(crate) use funded_storage::formatted as original_format_using;
pub(crate) use original_numbers::IssuedNumber as OriginalMacroNumber;
pub(crate) use original_lexical_values::{quoted_value_using as original_quoted_value_using,comment_value_using as original_comment_value_using,resource_value_using as original_resource_value_using,QuotedValue as OriginalMacroQuotedValue};
pub(crate) use original_define::{Builder as OriginalDefineBuilder,Input as OriginalDefineInput,Progress as OriginalDefineProgress,Defined as OriginalDefinedMacro,Doc as OriginalMacroDoc};
// Parser DATA facade only; actual current source/EOF/model grants remain with
// SAME DirectivePass/QueryAttempt owner, never this transient macro state.
pub(crate) use funded_storage::{MacroRows as OriginalMacroRows,MacroText as OriginalMacroText,MacroTokenRows as OriginalPagedMacroRows};
pub(crate) use original_values::{Token as OriginalMacroToken,Value as OriginalMacroValue,Text as OriginalMacroTextValue,Origin as OriginalMacroOrigin};
pub(crate) use original_demand::{Cursor as OriginalMacroCursor,Source as OriginalMacroSource,Definition as OriginalMacroDefinition,RawStep as OriginalMacroRawStep,Step as OriginalMacroStep,OuterStep as OriginalMacroOuterStep,Notice as OriginalMacroNotice,NoticeKind as OriginalMacroNoticeKind};

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

/// Native expansion-issued source point, relative to one direct physical line.
/// Invocation output is a constant point; unchanged source is affine. These
/// values are deliberately absent from memo wire formats.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) struct MacroBytePoint {
    pub(crate) output: Span,
    pub(crate) source_start: usize,
    pub(crate) invocation: bool,
}
fn push_byte_point(points: &mut Vec<MacroBytePoint>, point: MacroBytePoint) {
    if point.output.start == point.output.end {
        return;
    }
    if let Some(previous) = points.last_mut() {
        if !previous.invocation
            && !point.invocation
            && previous.output.end == point.output.start
            && previous.source_start + previous.output.end - previous.output.start
                == point.source_start
        {
            previous.output.end = point.output.end;
            return;
        }
    }
    points.push(point);
}
pub(crate) fn expand_traced_points(
    source: &str,
    macros: &dyn MacroLookup,
    location: ExpandLocation<'_>,
    trace: &mut MacroTrace<'_>,
) -> Result<(String, Option<Vec<MacroBytePoint>>), String> {
    let mut points = Some(Vec::new());
    let text = expand_mode_disabled_traced_points(
        source,
        macros,
        0,
        location,
        false,
        &mut Vec::new(),
        &mut Some(trace),
        &mut points,
        depth_zero_physical_lines(macros),
    )?;
    Ok((text, points))
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
    expand_mode_disabled_traced_points(
        source,
        macros,
        depth,
        location,
        substitute_only,
        disabled,
        trace,
        &mut None,
        depth == 0 && depth_zero_physical_lines(macros),
    )
}

fn depth_zero_physical_lines(macros:&dyn MacroLookup)->bool{macros.initial_environment()==crate::InitialEnvironment::OriginalChecker0290}

#[allow(clippy::sliced_string_as_bytes)]
fn expand_mode_disabled_traced_points<'a>(
    source: &str,
    macros: &'a dyn MacroLookup,
    depth: usize,
    location: ExpandLocation<'_>,
    substitute_only: bool,
    disabled: &mut Vec<&'a str>,
    trace: &mut Option<&mut MacroTrace<'_>>,
    points: &mut Option<Vec<MacroBytePoint>>,
    physical_lines:bool,
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
    let mut actual_line=location.line;let mut actual_at=0;
    while i < tokens.len() {
        if physical_lines{let start=tokens[i].span.start;actual_line+=source[actual_at..start].bytes().filter(|byte|*byte==b'\n').count();actual_at=start;}
        let location=ExpandLocation{line:actual_line,file_name:location.file_name};
        let first = i;
        let output_start = out.len();
        let mut invocation = false;
        let mut unsupported = false;
        let next = (|| -> Result<usize, String> {
            let token = &tokens[i];
            let token_text = token.text(source);
            if token.kind == TokenKind::String {
                if token_text.starts_with("@\"") {
                    out.push_str(token_text);
                    return Ok(i + 1);
                }
                let expanded = expand_interpolations(
                    token_text,
                    macros,
                    depth + 1,
                    location,
                    substitute_only,
                    disabled,
                    trace,
                    physical_lines,
                )?;
                unsupported = expanded != token_text;
                out.push_str(&expanded);
                return Ok(i + 1);
            }
            if token.kind == TokenKind::Ident {
                if macros.initial_environment()==crate::InitialEnvironment::OriginalChecker0290
                    && !(substitute_only && macros.contains_key(token_text)) {
                    // Pinned real_next substitutes these before ANY define-table
                    // lookup, including source definitions shadowing their names.
                    if token_text=="__LINE__"{unsupported=true;macros.location_read(false);out.push_str(&location.line.to_string());return Ok(i+1)}
                    if token_text=="__FILE__"{unsupported=true;macros.location_read(true);original_quote(&mut out,location.file_name);return Ok(i+1)}
                }

                // `defined` consumes a macro *name*. Function-like macros may
                // introduce it only after parameter substitution, so protect its
                // operand during the later ordinary expansion pass as well.
                if token_text == "defined" && !substitute_only
                    && (macros.initial_environment()!=crate::InitialEnvironment::OriginalChecker0290 || macros.condition_expansion())
                    && !(macros.initial_environment()==crate::InitialEnvironment::OriginalChecker0290 && macros.contains_key("defined")) {
                    let mut operand = i + 1;
                    while tokens.get(operand).is_some_and(|next| {
                        matches!(next.kind, TokenKind::Whitespace | TokenKind::Newline)
                    }) {
                        operand += 1;
                    }
                    let parenthesized=tokens.get(operand).is_some_and(|next|next.text(source)=="(");
                    if parenthesized {
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
                        .filter(|_|macros.initial_environment()!=crate::InitialEnvironment::OriginalChecker0290||parenthesized)
                        .filter(|next| macros.initial_environment()!=crate::InitialEnvironment::OriginalChecker0290 || !matches!(next.text(source),"__FILE__"|"__LINE__"))
                    {
                        out.push_str(&source[token.span.start..name.span.end]);
                        return Ok(operand + 1);
                    }
                }
                if let Some((name, def)) = macros
                    .get_key_value(token_text)
                    .filter(|_| !disabled.contains(&token_text))
                {
                    if let Some(params) = &def.parameters {
                        let Some(open) = tokens.get(i + 1).filter(|t| t.text(source) == "(") else {
                            out.push_str(token_text);
                            return Ok(i + 1);
                        };
                        let _ = open;
                        invocation = true;
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
                        let raw_parameters =
                            raw_macro_parameters(def, macros, &mut BTreeSet::new());
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
                        let context=SubstitutionLookup{replacements:&replacements,parent:macros};
                        let lookup:&dyn MacroLookup=if macros.initial_environment()==crate::InitialEnvironment::OriginalChecker0290{&context}else{&replacements};
                        let substituted = expand_mode(
                            &def.replacement,
                            lookup,
                            depth + 1,
                            location,
                            true,
                        )?;
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
                        return Ok(after);
                    }
                    if !substitute_only {
                        if let Some(callback) = trace.as_deref_mut() {
                            callback(name, token.span, disabled);
                        }
                    }
                    invocation = true;
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
                            return Ok(after);
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
                    return Ok(i + 1);
                }
                if token_text == "__LINE__" {
                    unsupported = true;
                    macros.location_read(false);
                    out.push_str(&location.line.to_string());
                    return Ok(i + 1);
                }
                if token_text == "__FILE__" {
                    unsupported = true;
                    macros.location_read(true);
                    out.push('"');
                    for ch in location.file_name.chars() {
                        if matches!(ch, '\\' | '"') {
                            out.push('\\');
                        }
                        out.push(ch);
                    }
                    out.push('"');
                    return Ok(i + 1);
                }
            }
            if token_text == "#"
                && tokens
                    .get(i + 1)
                    .is_some_and(|next| next.text(source) == "#")
            {
                unsupported = true;
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
                        unsupported = true;
                        return Ok(i + 3);
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
                return Ok(i);
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
                        return Ok(i + 2);
                    }
                    if next.kind == TokenKind::Ident {
                        if let Some(argument) = macros
                            .get(next.text(source))
                            .filter(|definition| definition.parameters.is_none())
                        {
                            unsupported = true;
                            out.push('"');
                            for ch in argument.replacement.chars() {
                                if matches!(ch, '\\' | '"') {
                                    out.push('\\');
                                }
                                out.push(ch);
                            }
                            out.push('"');
                            return Ok(i + 2);
                        }
                    }
                }
                return Err("unsupported # token outside macro stringification".into());
            }
            out.push_str(token_text);
            Ok(i + 1)
        })()?;
        if unsupported || out.len() < output_start {
            *points = None;
        } else if let Some(points) = points {
            push_byte_point(
                points,
                MacroBytePoint {
                    output: Span::new(output_start, out.len()),
                    source_start: tokens[first].span.start,
                    invocation,
                },
            );
        }
        i = next;
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
    physical_lines:bool,
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
        let expression_location=ExpandLocation{file_name:location.file_name,line:location.line+if physical_lines{literal[..start].bytes().filter(|byte|*byte==b'\n').count()}else{0}};
        result.push_str(&expand_mode_disabled_traced_points(
            &literal[start..end],
            macros,
            depth + 1,
            expression_location,
            substitute_only,
            disabled,
            trace,
            &mut None,
            physical_lines,
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

/// Exact pinned lexer::Quote transport, whose input escapes are unparsed.
pub(crate) fn original_quote_delimiters(text:&str)->(&'static str,&'static str){dm_syntax::original_token_value::original_quote_delimiters(text)}
fn original_quote(output:&mut String,text:&str){let(open,close)=original_quote_delimiters(text);output.push_str(open);output.push_str(text);output.push_str(close);}

#[cfg(test)]mod original_dynamic_transport_tests{
 use super::*;
 #[test]fn original_dynamic_tokens_precede_shadow_bindings_and_quote_unparsed_backslashes(){
  let macros=BTreeMap::from([("__LINE__".to_owned(),Macro{parameters:None,variadic:false,replacement:"99".into()}),("__FILE__".to_owned(),Macro{parameters:None,variadic:false,replacement:"\"shadow_file\"".into()})]);let original=crate::initial_environment::ContextLookup{inner:&macros,environment:crate::InitialEnvironment::OriginalChecker0290};let mut trace=|_:&str,_:Span,_:&[&str]|{};
  let text=expand_traced("__FILE__ __LINE__",&original,ExpandLocation{file_name:r"E:\folder\file.dm",line:7},&mut trace).unwrap();assert_eq!(text,r#""E:\folder\file.dm" 7"#);
  let native=expand_traced("__FILE__ __LINE__",&macros,ExpandLocation{file_name:r"E:\folder\file.dm",line:7},&mut trace).unwrap();assert_eq!(native,"\"shadow_file\" 99");
  for(input,wanted)in[("ordinary", "\"ordinary\""),("a\"b","{\"a\"b\"}"),("a\"}b","@@a\"}b@"),("a\nb","{\"a\nb\"}")]{let mut actual=String::new();original_quote(&mut actual,input);assert_eq!(actual,wanted);}
 }
}

/// Parameter substitution owns no macro environment. It borrows the real
/// Original context and forwards actual dynamic-location dependency reads.
struct SubstitutionLookup<'a>{replacements:&'a BTreeMap<String,Macro>,parent:&'a dyn MacroLookup}
impl MacroLookup for SubstitutionLookup<'_>{fn initial_environment(&self)->crate::InitialEnvironment{self.parent.initial_environment()}fn condition_expansion(&self)->bool{self.parent.condition_expansion()}fn get_key_value(&self,name:&str)->Option<(&str,&Macro)>{self.replacements.get_key_value(name).map(|(name,value)|(name.as_str(),value))}fn location_read(&self,file:bool){self.parent.location_read(file)}}

#[cfg(test)]mod original_substitution_context_tests{
 use super::*;
 use std::cell::Cell;
 struct Observed<'a>{inner:&'a BTreeMap<String,Macro>,file:Cell<bool>,line:Cell<bool>,environment:crate::InitialEnvironment}
 impl MacroLookup for Observed<'_>{fn initial_environment(&self)->crate::InitialEnvironment{self.environment}fn get_key_value(&self,name:&str)->Option<(&str,&Macro)>{self.inner.get_key_value(name).map(|(name,value)|(name.as_str(),value))}fn location_read(&self,file:bool){if file{self.file.set(true)}else{self.line.set(true)}}}
 #[test]fn original_function_interpolation_keeps_context_and_records_actual_location_dependencies(){
  let macros=BTreeMap::from([("WHERE".to_owned(),Macro{parameters:Some(vec!["value".into()]),variadic:false,replacement:r#""[__FILE__]:[__LINE__]:[value]""#.into()})]);
  let original=Observed{inner:&macros,file:Cell::new(false),line:Cell::new(false),environment:crate::InitialEnvironment::OriginalChecker0290};
  let actual=expand("WHERE(7)",&original,0,ExpandLocation{file_name:r"E:\folder\source.dm",line:23}).unwrap();
  assert_eq!(actual,r#""["E:\folder\source.dm"]:[23]:[7]""#);
  assert!(original.file.get());assert!(original.line.get());
  let native=Observed{inner:&macros,file:Cell::new(false),line:Cell::new(false),environment:crate::InitialEnvironment::Native5161687};
  let actual=expand("WHERE(7)",&native,0,ExpandLocation{file_name:r"E:\folder\source.dm",line:23}).unwrap();
  assert_eq!(actual,r#""["E:\\folder\\source.dm"]:[23]:[7]""#);
 }
}

#[cfg(test)]mod original_dynamic_formal_tests{
 use super::*;
 struct FormalLookup<'a>{inner:&'a BTreeMap<String,Macro>,reads:std::cell::Cell<usize>}
 impl MacroLookup for FormalLookup<'_>{fn initial_environment(&self)->crate::InitialEnvironment{crate::InitialEnvironment::OriginalChecker0290}fn get_key_value(&self,name:&str)->Option<(&str,&Macro)>{self.inner.get_key_value(name).map(|(name,value)|(name.as_str(),value))}fn location_read(&self,_file:bool){self.reads.set(self.reads.get()+1)}}
 #[test]fn original_dynamic_formals_substitute_before_real_token_location_expansion(){
  let macros=BTreeMap::from([("FORMALS".into(),Macro{parameters:Some(vec!["__FILE__".into(),"__LINE__".into()]),variadic:false,replacement:"__FILE__ + __LINE__".into()})]);
  let original=FormalLookup{inner:&macros,reads:std::cell::Cell::new(0)};
  assert_eq!(expand("FORMALS(7,8)",&original,0,ExpandLocation{file_name:r"E:\actual.dm",line:23}).unwrap(),"7 + 8");assert_eq!(original.reads.get(),0);
 }
}

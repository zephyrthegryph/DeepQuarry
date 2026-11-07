use super::*;

pub(super) fn split_top_level_keyword<'a>(
    source: &'a str,
    keyword: &str,
) -> Option<(&'a str, &'a str)> {
    let mut depth = 0;
    for token in crate::lex_spans(source).tokens {
        match token.text(source) {
            "(" | "[" | "{" => depth += 1,
            ")" | "]" | "}" => depth -= 1,
            text if depth == 0 && token.kind == crate::TokenKind::Ident && text == keyword => {
                return Some((&source[..token.span.start], &source[token.span.end..]));
            }
            _ => {}
        }
    }
    None
}

pub(super) fn split_case_alternatives(source: &str) -> Vec<&str> {
    split_case_alternatives_with_tokens(source).0
}
pub(super) fn split_case_alternatives_with_tokens(
    source: &str,
) -> (Vec<&str>, crate::SpannedLexed) {
    let mut parts = Vec::new();
    let mut start = 0;
    let mut depth = 0;
    let lexical = crate::lex_spans(source);
    for token in &lexical.tokens {
        match token.text(source) {
            "(" | "[" => depth += 1,
            ")" | "]" => depth -= 1,
            "," if depth == 0 => {
                parts.push(&source[start..token.span.start]);
                start = token.span.end;
            }
            _ => {}
        }
    }
    parts.push(&source[start..]);
    (parts, lexical)
}

pub(super) fn parse_for(
    item: &Item,
    diagnostics: &mut BodyDiagnostics<'_>,
    origins: &mut BodyOrigins<'_>,
) -> Option<ForControl> {
    let (clause, _, lexical, clause_base) = control_clause_origin_tokens(item, "for", diagnostics)?;
    let base = item.header_span.start + item.header.find(clause).unwrap_or(0);
    if (clause.starts_with("var/") || starts_keyword(clause, "var"))
        && !clause.contains(['=', ',', ';'])
        && !clause.contains(" in ")
        && !clause.contains(" to ")
    {
        origins.local_binding(
            clause,
            &lexical,
            clause_base,
            clause,
            crate::LocalSourceKind::ForBinding,
        );
        return Some(ForControl::All {
            source_binding:origins.for_list_binding(clause,&lexical,clause_base,clause.trim()),
            declaration: clause.trim().into(),
        });
    }
    if let Some((binding_source, iterable_source)) = split_top_level_keyword(clause, "in") {
        let at = binding_source.len();
        let binding = binding_source.trim();
        let iterable = iterable_source.trim();
        if binding.is_empty() {
            diagnostics.push(Diagnostic {
                span: item.header_span,
                kind: DiagnosticKind::Statement,
                message: "missing for binding".into(),
            });
            return None;
        }
        let pair = split_case_alternatives(binding);
        if binding.starts_with("var/") || starts_keyword(binding, "var") {
            origins.local_parts(
                clause,
                &lexical,
                clause_base,
                &pair,
                crate::LocalSourceKind::ForBinding,
            );
        }
        if pair.len() > 2 || pair.iter().any(|part| part.trim().is_empty()) {
            diagnostics.push(Diagnostic {
                span: item.header_span,
                kind: DiagnosticKind::Statement,
                message: "pair for requires two bindings".into(),
            });
            return None;
        }
        if pair.len() == 2 {
            // Pinned checker ForKeyValue requires a var/key declaration with
            // no initializer, and a bare value name. Keep compiler syntax
            // acceptance unchanged, but do not issue checker-local authority
            // for a broader native pair-loop shape.
            let value = pair[1].trim();
            let mut chars = value.chars();
            let bare_value = chars.next().is_some_and(|c| c == '_' || c.is_alphabetic())
                && chars.all(|c| c == '_' || c.is_alphanumeric());
            if !(binding.starts_with("var/") || starts_keyword(binding, "var"))
                || crate::local_variable_syntax::top_level_local_assignment(pair[0]).is_some()
                || split_top_level_keyword(pair[0], "as").is_some()
                || !bare_value
            {
                origins
                    .locals
                    .decline("pair-loop shape has no original checker declaration receipt");
            }
            return parse_expr(
                iterable,
                base + clause.find(iterable).unwrap_or(at + 4),
                diagnostics,
            )
            .map(|iterable| ForControl::Pair {
                key_binding: pair[0].trim().into(),
                value_binding: pair[1].trim().into(),
                iterable,
            });
        }
        if let Some((start_source, remainder)) = split_top_level_keyword(iterable, "to") {
            return parse_range_control(
                binding,
                start_source,
                remainder,
                clause,
                base,
                diagnostics,
            );
        }
        return parse_expr(
            iterable,
            base + clause.find(iterable).unwrap_or(at + 4),
            diagnostics,
        )
        .map(|iterable| ForControl::Each {
            source_binding:origins.for_list_binding(clause,&lexical,clause_base,binding),
            binding: binding.into(),
            iterable,
        });
    }
    if let Some((begin, remainder)) = split_top_level_keyword(clause, "to") {
        if crate::local_variable_syntax::top_level_local_assignment(begin).is_none()
            && (begin.starts_with("var/") || starts_keyword(begin, "var"))
        {
            origins.local_binding(
                clause,
                &lexical,
                clause_base,
                begin.trim(),
                crate::LocalSourceKind::ForInitializer,
            );
            let array = origins
                .locals
                .entries()
                .ok()
                .and_then(|entries| entries.last())
                .and_then(|fact| fact.implicit_list_initializer());
            if array.is_none() {
                diagnostics.push(Diagnostic {
                    span: item.header_span,
                    kind: DiagnosticKind::Unsupported,
                    message: "range start has no primary implicit array constructor".into(),
                });
                return None;
            }
            let (end, step) = parse_range_tail(remainder, clause, base, diagnostics)?;
            return Some(ForControl::RangeImplicitArray {
                binding: begin.trim().into(),
                end,
                step,
            });
        }
        let Some((binding, start_source)) =
            crate::local_variable_syntax::top_level_local_assignment(begin)
                .map(|at| (&begin[..at], &begin[at + 1..]))
        else {
            diagnostics.push(Diagnostic {
                span: item.header_span,
                kind: DiagnosticKind::Statement,
                message: "range for requires an initialized binding".into(),
            });
            return None;
        };
        let binding = binding.trim();
        if binding.is_empty() {
            diagnostics.push(Diagnostic {
                span: item.header_span,
                kind: DiagnosticKind::Statement,
                message: "missing range for binding".into(),
            });
            return None;
        }
        origins.local_binding(
            clause,
            &lexical,
            clause_base,
            begin,
            crate::LocalSourceKind::ForBinding,
        );
        return parse_range_control(binding, start_source, remainder, clause, base, diagnostics);
    }
    let mut parts = split_for_clauses(clause);
    if parts.len() == 2 {
        parts.push("");
    }
    if parts.len() == 1 && parts[0].is_empty() {
        parts.extend(["", ""]);
    }
    if parts.len() == 3 {
        let initial = parts[0];
        let initializer = if initial.is_empty() {
            None
        } else if initial.starts_with("var/") || starts_keyword(initial, "var") {
            let (declaration, value) =
                crate::local_variable_syntax::top_level_local_assignment(initial)
                    .map_or((initial, None), |at| {
                        (initial[..at].trim(), Some(initial[at + 1..].trim()))
                    });
            let value = if let Some(value) = value {
                Some(parse_expr(
                    value,
                    clause_base + (value.as_ptr() as usize - clause.as_ptr() as usize),
                    diagnostics,
                )?)
            } else {
                None
            };
            origins.local_binding(
                clause,
                &lexical,
                clause_base,
                initial,
                crate::LocalSourceKind::ForInitializer,
            );
            Some(ForInitializer::Declare {
                declaration: declaration.into(),
                value,
            })
        } else {
            Some(ForInitializer::Expr(parse_expr(
                initial,
                base + clause.find(initial).unwrap_or(0),
                diagnostics,
            )?))
        };
        let condition = if parts[1].is_empty() {
            None
        } else {
            Some(parse_expr(
                parts[1],
                base + clause.find(parts[1]).unwrap_or(0),
                diagnostics,
            )?)
        };
        let step = if parts[2].is_empty() {
            None
        } else {
            Some(parse_expr(
                parts[2],
                base + clause.find(parts[2]).unwrap_or(0),
                diagnostics,
            )?)
        };
        return Some(ForControl::CStyle {
            initializer,
            condition,
            step,
        });
    }
    diagnostics.push(Diagnostic {
        span: item.header_span,
        kind: DiagnosticKind::Unsupported,
        message: "unsupported for control".into(),
    });
    None
}

fn parse_range_control(
    binding: &str,
    start_source: &str,
    remainder: &str,
    clause: &str,
    base: usize,
    diagnostics: &mut BodyDiagnostics<'_>,
) -> Option<ForControl> {
    let start_source = start_source.trim();
    let start = parse_expr(
        start_source,
        base + (start_source.as_ptr() as usize - clause.as_ptr() as usize),
        diagnostics,
    )?;
    let (end, step) = parse_range_tail(remainder, clause, base, diagnostics)?;
    Some(ForControl::Range {
        binding: binding.into(),
        start,
        end,
        step,
    })
}

fn parse_range_tail(
    remainder: &str,
    clause: &str,
    base: usize,
    diagnostics: &mut BodyDiagnostics<'_>,
) -> Option<(Expr, Option<Expr>)> {
    let (end_source, step_source) = remainder
        .split_once(" step ")
        .map_or((remainder, None), |(end, step)| (end, Some(step)));
    let end_source = end_source.trim();
    let end = parse_expr(
        end_source,
        base + (end_source.as_ptr() as usize - clause.as_ptr() as usize),
        diagnostics,
    )?;
    let step = if let Some(source) = step_source {
        let source = source.trim();
        Some(parse_expr(
            source,
            base + (source.as_ptr() as usize - clause.as_ptr() as usize),
            diagnostics,
        )?)
    } else {
        None
    };
    Some((end, step))
}

fn control_close(rest: &str) -> Option<usize> {
    if !rest.starts_with('(') {
        return None;
    }
    let lexical = crate::lex_spans(rest);
    control_close_tokens(rest, &lexical.tokens)
}
fn control_close_tokens(rest: &str, tokens: &[crate::SpanToken]) -> Option<usize> {
    if !rest.starts_with('(') {
        return None;
    }
    let mut depth = 0;
    for token in tokens {
        match token.text(rest) {
            "(" => depth += 1,
            ")" => {
                depth -= 1;
                if depth == 0 {
                    return Some(token.span.start);
                }
            }
            _ => {}
        }
    }
    None
}

/// Borrow the same inline tail used by the unique control-body parser.
pub(super) fn control_inline<'a>(item:&'a Item,keyword:&str)->Option<&'a str>{let rest=item.header.trim().strip_prefix(keyword)?.trim_start();let close=control_close(rest)?;let inline=rest[close+1..].trim().trim_end_matches(';').trim();(!inline.is_empty()).then_some(inline)}
pub(super) fn control_body(
    item: &Item,
    keyword: &str,
    diagnostics: &mut BodyDiagnostics<'_>,
    origins: &mut BodyOrigins<'_>,
) -> Vec<Statement> {
    control_body_from_inline(item,control_inline(item,keyword),diagnostics,origins)
}
pub(super) fn control_body_from_inline(item:&Item,inline:Option<&str>,diagnostics:&mut BodyDiagnostics<'_>,origins:&mut BodyOrigins<'_>)->Vec<Statement>{
    let Some(inline)=inline else{return parse_sequence(&item.children,diagnostics,origins)};
    let mut nested = item.clone();
    nested.header = inline.into();
    nested.header_span.start += inline.as_ptr() as usize-item.header.as_ptr() as usize;
    nested.span.start=nested.header_span.start;
    parse_sequence(&[nested], diagnostics, origins)
}

fn split_for_clauses(clause: &str) -> Vec<&str> {
    let mut parts = Vec::new();
    let mut depth = 0;
    let mut start = 0;
    for token in crate::lex_spans(clause).tokens {
        match token.text(clause) {
            "(" | "[" => depth += 1,
            ")" | "]" => depth -= 1,
            ";" | "," if depth == 0 => {
                parts.push(clause[start..token.span.start].trim());
                start = token.span.end;
            }
            _ => {}
        }
    }
    parts.push(clause[start..].trim());
    parts
}

pub(super) fn parse_control_condition_observed(
    item: &Item,
    keyword: &str,
    diagnostics: &mut BodyDiagnostics<'_>,
    observe: &mut dyn FnMut(&crate::ParsedExpr),
) -> Option<Expr> {
    let clause = control_clause(item, keyword, diagnostics)?;
    parse_expr_observed(
        clause,
        item.header_span.start + (clause.as_ptr() as usize - item.header.as_ptr() as usize),
        diagnostics,
        observe,
    )
}

pub(super) fn parse_control_condition_origin(
    item: &Item,
    keyword: &str,
    diagnostics: &mut BodyDiagnostics<'_>,
    origins: &mut BodyOrigins<'_>,
) -> Option<Expr> {
    let (clause, opening) = control_clause_origin(item, keyword, diagnostics)?;
    let condition = parse_expr_observed(
        clause,
        item.header_span.start + item.header.find(clause).unwrap_or(0),
        diagnostics,
        &mut|parsed|{origins.original_compound_complete&=parsed.original_simple_expression.is_some_and(|value|value.kind()==crate::expression_parser::OriginalSimpleKind::Complete);},
    )?;
    origins.push(ControlOrigin {
        condition: condition.span,
        opening,
    });
    Some(condition)
}

pub(super) fn control_clause<'a>(
    item: &'a Item,
    keyword: &str,
    diagnostics: &mut BodyDiagnostics<'_>,
) -> Option<&'a str> {
    control_clause_origin(item, keyword, diagnostics).map(|(clause, _)| clause)
}

fn control_clause_origin<'a>(
    item: &'a Item,
    keyword: &str,
    diagnostics: &mut BodyDiagnostics<'_>,
) -> Option<(&'a str, Span)> {
    control_clause_origin_tokens(item, keyword, diagnostics)
        .map(|(clause, opening, _, _)| (clause, opening))
}
fn control_clause_origin_tokens<'a>(
    item: &'a Item,
    keyword: &str,
    diagnostics: &mut BodyDiagnostics<'_>,
) -> Option<(&'a str, Span, crate::SpannedLexed, usize)> {
    let header = item.header.trim();
    let after_keyword = header.strip_prefix(keyword)?;
    let rest = after_keyword.trim_start();
    let mut lexical = crate::lex_spans(rest);
    let Some(close) = control_close_tokens(rest, &lexical.tokens) else {
        diagnostics.push(Diagnostic {
            span: item.header_span,
            kind: DiagnosticKind::Statement,
            message: format!("expected parenthesized {keyword} control"),
        });
        return None;
    };
    let clause = &rest[1..close];
    let offset = item.header_span.start
        + (item.header.len() - item.header.trim_start().len())
        + keyword.len()
        + (after_keyword.len() - rest.len());
    let clause = clause.trim();
    let start = clause.as_ptr() as usize - rest.as_ptr() as usize;
    let end = start + clause.len();
    lexical
        .tokens
        .retain(|token| token.span.start >= start && token.span.end <= end);
    for token in &mut lexical.tokens {
        token.span.start -= start;
        token.span.end -= start;
    }
    Some((
        clause,
        Span::new(offset, offset + 1),
        lexical,
        offset + start,
    ))
}

pub(super) fn parse_expr(
    source: &str,
    offset: usize,
    diagnostics: &mut BodyDiagnostics<'_>,
) -> Option<Expr> {
    parse_expr_observed(source,offset,diagnostics,&mut |_|{})
}
pub(super) fn parse_expr_observed(source:&str,offset:usize,diagnostics:&mut BodyDiagnostics<'_>,observe:&mut dyn FnMut(&crate::ParsedExpr))->Option<Expr>{
    if source.trim().is_empty() {
        diagnostics.push(Diagnostic {
            span: Span::new(offset, offset),
            kind: DiagnosticKind::Statement,
            message: "missing expression".into(),
        });
        return None;
    }
    let original=match diagnostics.settings{
      Some(provider)=>match provider.original_expression(source,offset){Ok(value)=>value,Err(actual)=>{if let Some(a)=diagnostics.admission{a.record_operational_error(actual);}return None}},None=>None,
    };
    let using_original=original.is_some();
    let mut parsed = match original{Some(parsed)=>parsed,None=>parse_expression(source)};
    observe(&parsed);
    for diagnostic in &mut parsed.diagnostics {
        diagnostic.span.start += offset;
        diagnostic.span.end += offset;
    }
    let clean = parsed.diagnostics.is_empty();
    diagnostics.extend(parsed.diagnostics);
    if !clean {
        return None;
    }
    let mut expr=parsed.expr?;
    if using_original {
        let Some(a)=diagnostics.admission else {
            diagnostics.push(Diagnostic{span:expr.span,kind:DiagnosticKind::Statement,message:"Original expression requires its native operation admission".into()});
            return None;
        };
        if let Err(actual)=crate::literal::shift_unpublished_expression_using(&mut expr,offset,a) {
            a.record_operational_error(actual);
            return None;
        }
    } else { shift_expr(&mut expr, offset); }
    Some(expr)
}

fn shift_expr(expr: &mut Expr, offset: usize) {
    crate::shift_expression(expr, offset);
}

pub(super) fn starts_keyword(source: &str, keyword: &str) -> bool {
    source == keyword
        || source
            .strip_prefix(keyword)
            .is_some_and(|tail| tail.starts_with([' ', '\t', '(']))
}

pub(super) fn is_assignment(op: &str) -> bool {
    matches!(
        op,
        "=" | "+=" | "-=" | "*=" | "/=" | "%=" | "|=" | "&=" | "^=" | "<<=" | ">>="
            | ":=" | "%%="
    )
}

pub(super) fn unsupported(item: &Item) -> Statement {
    Statement {
        kind: StatementKind::Unsupported,
        span: item.span,
        header_span: item.header_span,
        raw_header: item.header.clone(),
    }
}

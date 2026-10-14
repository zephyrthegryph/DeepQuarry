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
    let mut parts = Vec::new();
    let mut start = 0;
    let mut depth = 0;
    for token in crate::lex_spans(source).tokens {
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
    parts
}

pub(super) fn parse_for(item: &Item, diagnostics: &mut Vec<Diagnostic>) -> Option<ForControl> {
    let clause = control_clause(item, "for", diagnostics)?;
    let base = item.header_span.start + item.header.find(clause).unwrap_or(0);
    if (clause.starts_with("var/") || starts_keyword(clause, "var"))
        && !clause.contains(['=', ',', ';'])
        && !clause.contains(" in ")
        && !clause.contains(" to ")
    {
        return Some(ForControl::All {
            declaration: clause.trim().into(),
        });
    }
    if let Some(at) = clause.find(" in ") {
        let binding = clause[..at].trim();
        let iterable = clause[at + 4..].trim();
        if binding.is_empty() {
            diagnostics.push(Diagnostic {
                span: item.header_span,
                kind: DiagnosticKind::Statement,
                message: "missing for binding".into(),
            });
            return None;
        }
        let pair = split_case_alternatives(binding);
        if pair.len() > 2 || pair.iter().any(|part| part.trim().is_empty()) {
            diagnostics.push(Diagnostic {
                span: item.header_span,
                kind: DiagnosticKind::Statement,
                message: "pair for requires two bindings".into(),
            });
            return None;
        }
        if pair.len() == 2 {
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
            binding: binding.into(),
            iterable,
        });
    }
    if let Some((begin, remainder)) = split_top_level_keyword(clause, "to") {
        let Some((binding, start_source)) = begin.split_once('=') else {
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
            let (declaration, value) = initial
                .split_once('=')
                .map_or((initial, None), |(name, value)| {
                    (name.trim(), Some(value.trim()))
                });
            let value = if let Some(value) = value {
                Some(parse_expr(
                    value,
                    base + clause.find(value).unwrap_or(0),
                    diagnostics,
                )?)
            } else {
                None
            };
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
    diagnostics: &mut Vec<Diagnostic>,
) -> Option<ForControl> {
    let (end_source, step_source) = remainder
        .split_once(" step ")
        .map_or((remainder, None), |(end, step)| (end, Some(step)));
    let start_source = start_source.trim();
    let end_source = end_source.trim();
    let start = parse_expr(
        start_source,
        base + clause.find(start_source).unwrap_or(0),
        diagnostics,
    )?;
    let end = parse_expr(
        end_source,
        base + clause.find(end_source).unwrap_or(0),
        diagnostics,
    )?;
    let step = if let Some(source) = step_source {
        let source = source.trim();
        Some(parse_expr(
            source,
            base + clause.rfind(source).unwrap_or(0),
            diagnostics,
        )?)
    } else {
        None
    };
    Some(ForControl::Range {
        binding: binding.into(),
        start,
        end,
        step,
    })
}

fn control_close(rest: &str) -> Option<usize> {
    if !rest.starts_with('(') {
        return None;
    }
    let mut depth = 0;
    for token in crate::lex_spans(rest).tokens {
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

pub(super) fn control_body(
    item: &Item,
    keyword: &str,
    diagnostics: &mut Vec<Diagnostic>,
) -> Vec<Statement> {
    let rest = item
        .header
        .trim()
        .strip_prefix(keyword)
        .unwrap_or("")
        .trim_start();
    let Some(close) = control_close(rest) else {
        return parse_sequence(&item.children, diagnostics);
    };
    let inline = rest[close + 1..].trim().trim_end_matches(';').trim();
    if inline.is_empty() {
        return parse_sequence(&item.children, diagnostics);
    }
    let mut nested = item.clone();
    nested.header = inline.into();
    nested.header_span.start += item.header.find(inline).unwrap_or(0);
    parse_sequence(&[nested], diagnostics)
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

pub(super) fn parse_control_condition(
    item: &Item,
    keyword: &str,
    diagnostics: &mut Vec<Diagnostic>,
) -> Option<Expr> {
    let clause = control_clause(item, keyword, diagnostics)?;
    parse_expr(
        clause,
        item.header_span.start + item.header.find(clause).unwrap_or(0),
        diagnostics,
    )
}

pub(super) fn control_clause<'a>(
    item: &'a Item,
    keyword: &str,
    diagnostics: &mut Vec<Diagnostic>,
) -> Option<&'a str> {
    let header = item.header.trim();
    let rest = header.strip_prefix(keyword)?.trim_start();
    let Some(close) = control_close(rest) else {
        diagnostics.push(Diagnostic {
            span: item.header_span,
            kind: DiagnosticKind::Statement,
            message: format!("expected parenthesized {keyword} control"),
        });
        return None;
    };
    let clause = &rest[1..close];
    Some(clause.trim())
}

pub(super) fn parse_expr(
    source: &str,
    offset: usize,
    diagnostics: &mut Vec<Diagnostic>,
) -> Option<Expr> {
    if source.trim().is_empty() {
        diagnostics.push(Diagnostic {
            span: Span::new(offset, offset),
            kind: DiagnosticKind::Statement,
            message: "missing expression".into(),
        });
        return None;
    }
    let mut parsed = parse_expression(source);
    for diagnostic in &mut parsed.diagnostics {
        diagnostic.span.start += offset;
        diagnostic.span.end += offset;
    }
    let clean = parsed.diagnostics.is_empty();
    diagnostics.extend(parsed.diagnostics);
    if !clean {
        return None;
    }
    parsed.expr.map(|mut expr| {
        shift_expr(&mut expr, offset);
        expr
    })
}

fn shift_expr(expr: &mut Expr, offset: usize) {
    expr.span.start += offset;
    expr.span.end += offset;
    match &mut expr.kind {
        ExprKind::Unary { value, .. }
        | ExprKind::Group(value)
        | ExprKind::TypeFilter { value, .. } => shift_expr(value, offset),
        ExprKind::Binary { lhs, rhs, .. } => {
            shift_expr(lhs, offset);
            shift_expr(rhs, offset);
        }
        ExprKind::Conditional {
            condition,
            then_value,
            else_value,
        } => {
            shift_expr(condition, offset);
            shift_expr(then_value, offset);
            shift_expr(else_value, offset);
        }
        ExprKind::Call { callee, args } => {
            shift_expr(callee, offset);
            for arg in args {
                shift_expr(arg, offset);
            }
        }
        ExprKind::ObjectInitializer { object, fields } => {
            shift_expr(object, offset);
            for (_, value) in fields {
                shift_expr(value, offset);
            }
        }
        ExprKind::Member { object, .. }
        | ExprKind::SafeMember { object, .. }
        | ExprKind::StaticMember { object, .. } => shift_expr(object, offset),
        ExprKind::Index { object, index } | ExprKind::SafeIndex { object, index } => {
            shift_expr(object, offset);
            shift_expr(index, offset);
        }
        ExprKind::Ident(_) | ExprKind::Literal(_) | ExprKind::TypePath(_) => {}
    }
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

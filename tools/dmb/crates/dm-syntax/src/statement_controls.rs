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

// Exact lexical subset of the existing ForList arm. The selected split
// tells us which token is the actual top-level separator.
fn original_for_each_clause(
    clause: &str, lexical: &crate::SpannedLexed, separator: usize,
    dotted: bool, grouped_index: bool, call_member: bool, direct_call: bool, subtraction: bool,
    bare_string_index: bool, composed_iterable:bool,
) -> bool {
    use crate::TokenKind;
    if !lexical.diagnostics.is_empty() { return false; }
    let mut tokens = lexical.tokens.iter()
        .filter(|token| !matches!(token.kind, TokenKind::Whitespace | TokenKind::Newline));
    let identifier = |token: &crate::SpanToken| token.kind == TokenKind::Ident
        && token.text(clause).bytes().all(|byte| byte.is_ascii_alphanumeric() || byte == b'_');
    let Some(first) = tokens.next() else { return false; };
    if first.text(clause) == "var" {
        loop {
            if !tokens.next().is_some_and(|token| token.text(clause) == "/")
                || !tokens.next().is_some_and(identifier) { return false; }
            let Some(next) = tokens.clone().next() else { return false; };
            if next.text(clause) != "/" { break; }
        }
    } else if first.kind != TokenKind::Ident
        || !crate::expression_parser::original_ordinary_call_name(first.text(clause))
        || matches!(first.text(clause), "null" | "__PROC__" | "__TYPE__" | "__IMPLIED_TYPE__") {
        return false;
    }
    // A bare name is the pinned var_type=None form, not a declaration.
    // Exclude pinned no-argument special terms; global is a genuine Ident.
    // Existence/resolution belongs to the semantic consumer. The same next
    // token must still be the exact selected top-level In separator.
    if !tokens.next().is_some_and(|token| token.span.start == separator && token.text(clause) == "in") {
        return false;
    }
    if composed_iterable { return true; } // complete actual child covers this entire tail
    // For this route the exact entire tail is already covered by the
    // actual Original expression proof below, including both delimiters.
    if grouped_index { return tokens.next().is_some_and(|token| token.text(clause) == "("); }
    if !tokens.next().is_some_and(identifier) { return false; }
    if call_member || direct_call {
        return tokens.next().is_some_and(|token| token.kind == TokenKind::Punctuation
            && token.text(clause) == "(");
    }
    if subtraction { return true; } // exact remainder consumed by the Original expression witness
    if bare_string_index {
        return tokens.next().is_some_and(|token| token.text(clause) == "[")
            && tokens.next().is_some_and(|token| token.kind == TokenKind::String)
            && tokens.next().is_some_and(|token| token.text(clause) == "]")
            && tokens.next().is_none();
    }
    while let Some(dot) = tokens.next() {
        if !dotted || dot.text(clause) != "." || !tokens.next().is_some_and(identifier) {
            return false;
        }
    }
    true
}

// Called only after the iterable's independent Original expression receipt.
// list/alist have a dedicated complete argument production, not an ordinary
// call name; they still use the same pinned ForList control and exact In.
fn original_direct_for_iterable(expression:&Expr)->bool{
 matches!(&expression.kind,ExprKind::Call{callee,..}
  if matches!(&callee.kind,ExprKind::Ident(name)
   if crate::expression_parser::original_ordinary_call_name(name)
    || matches!(name.as_str(),"list"|"alist")))
}

fn original_call_member_iterable(expression: &Expr) -> bool {
    let ExprKind::Member { object, via_colon: false, .. } = &expression.kind else { return false };
    let mut receiver = object.as_ref();
    while let ExprKind::Member { object, via_colon: false, .. } = &receiver.kind {
        receiver = object;
    }
    matches!(&receiver.kind, ExprKind::Call { callee, args }
        if args.is_empty() && matches!(&callee.kind, ExprKind::Ident(_)))
}

fn original_for_each_bare_string_index(expression: &Expr) -> bool {
    let ExprKind::Index { object, index } = &expression.kind else { return false; };
    let ExprKind::Literal(literal) = &index.kind else { return false; };
    let Some(raw) = literal.as_str().strip_prefix('"').and_then(|raw| raw.strip_suffix('"'))
        else { return false; };
    matches!(&object.kind, ExprKind::Ident(name) if crate::expression_parser::original_ascii_identifier(name))
        && crate::expression_parser::original_ascii_identifier(raw)
        && matches!(literal.original_value(), Some(crate::OriginalTokenValue::String(cooked)) if cooked == raw)
}

fn original_for_each_subtraction(expression: &Expr) -> bool {
    let ExprKind::Binary { op, lhs, rhs } = &expression.kind else { return false; };
    let ExprKind::Member { object: left, selector: left_name, via_colon: false } = &lhs.kind
        else { return false; };
    let ExprKind::Index { object, index } = &rhs.kind else { return false; };
    let ExprKind::Member { object: right, selector: right_name, via_colon: false } = &object.kind
        else { return false; };
    op == "-" && left_name == right_name
        && matches!((&left.kind, &right.kind), (ExprKind::Ident(a), ExprKind::Ident(b)) if a == b)
        && matches!(&index.kind, ExprKind::Literal(value)
            if crate::expression_parser::original_decimal(value.as_str()))
}

pub(super) fn parse_for(
    item: &Item,
    diagnostics: &mut BodyDiagnostics<'_>,
    origins: &mut BodyOrigins<'_>,
    original_control: &mut bool,
) -> Option<ForControl> {
    let (clause, _, lexical, clause_base) = control_clause_origin_tokens(item, "for", diagnostics)?;
    let offset_of = |part: &str| clause_base + (part.as_ptr() as usize - clause.as_ptr() as usize);
    let list_clause = split_top_level_keyword(clause, "in");
    if (clause.starts_with("var/") || starts_keyword(clause, "var"))
        && !clause.contains(['=', ',', ';'])
        && list_clause.is_none()
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
    if let Some((binding_source, iterable_source)) = list_clause {
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
                offset_of(iterable),
                diagnostics,
            )
            .map(|iterable| ForControl::Pair {
                key_binding: pair[0].trim().into(),
                value_binding: pair[1].trim().into(),
                iterable,
            });
        }
        if let Some((start_source, remainder)) = split_top_level_keyword(iterable, "to") {
            let mut bounds_witnessed = false;
            let control = parse_range_control(
                binding, start_source, remainder, clause, clause_base, diagnostics,
                Some(&mut bounds_witnessed),
            )?;
            if bounds_witnessed {
                let name = origins.for_list_binding(clause, &lexical, clause_base, binding);
                *original_control = original_declared_range_header(
                    &control, offset_of(binding), name, false, origins,
                );
            }
            return Some(control);
        }
        let offset = offset_of(iterable);
        let mut expression_complete = false;
        let mut dotted_original = false;
        let mut grouped_index = false;
        let mut call_member = false;
        let mut direct_call = false;
        let mut subtraction = false;
        let mut anything_iterable = false;
        let mut bare_string_index = false;
        let mut composed_iterable = false;
        let iterable = parse_expr_observed(iterable, offset, diagnostics, &mut |parsed| {
            expression_complete = parsed.original_simple_expression.is_some_and(|value| {
                value.kind() == crate::expression_parser::OriginalSimpleKind::Complete
            });
            let actual_original = parsed.original_simple_expression.is_some_and(|value| value.is_original());
            let kind = parsed.expr.as_ref().map(|value| &value.kind);
            // The pinned `as anything` clause consumes an expression; its
            // type/name/as/in head remains separately authenticated below.
            anything_iterable = actual_original && expression_complete;
            composed_iterable = actual_original && expression_complete && (matches!(kind,Some(ExprKind::Member{via_colon:false,..}|ExprKind::SafeMember{via_colon:false,..}
                    |ExprKind::Index{..}|ExprKind::SafeIndex{..}))
                || matches!(kind,Some(ExprKind::Call{callee,..})if matches!(&callee.kind,ExprKind::Member{via_colon:false,..})));
            dotted_original = actual_original && matches!(kind, Some(ExprKind::Member { via_colon: false, .. }));
            grouped_index = actual_original && matches!(kind,
                Some(ExprKind::Group(value)) if matches!(&value.kind, ExprKind::Index { .. }));
            call_member = actual_original && parsed.expr.as_ref().is_some_and(original_call_member_iterable);
            // Pinned for_list takes an entire expression as its iterable.
            // Reuse a completed Original direct call or list/alist constructor
            // proof. Member calls, other primitives, assignments and dynamic
            // follows keep their independent gates.
            direct_call = actual_original && parsed.expr.as_ref().is_some_and(original_direct_for_iterable);
            subtraction = actual_original && parsed.expr.as_ref().is_some_and(original_for_each_subtraction);
            bare_string_index = actual_original && parsed.expr.as_ref().is_some_and(original_for_each_bare_string_index);
        })?;
        let source_binding = origins.for_list_binding(clause, &lexical, clause_base, binding);
        *original_control = expression_complete && source_binding.is_some()
            && original_for_each_clause(
                clause, &lexical, at, dotted_original, grouped_index, call_member, direct_call, subtraction, bare_string_index, composed_iterable,
            );
        let mut declaration = binding;
        if let Some((before_hint, _)) = split_top_level_keyword(binding, "as")
            .filter(|(_, hint)| hint.trim() == "anything")
            .filter(|_| !*original_control && expression_complete && anything_iterable)
        {
            if let Some(name) = source_binding {
                let prefix = Span::new(offset_of(binding), iterable.span.start);
                let typed = origins.locals.entries().ok().and_then(|rows| rows.iter().find(|row| {
                    row.source_kind == crate::LocalSourceKind::ForBinding
                        && row.name == name.name() && row.source_modifiers == 0
                        && !row.array_suffix && !row.type_components.is_empty()
                }));
                match typed.and_then(|row| origins.settings.map(|provider| {
                    provider.original_for_each_anything_prefix(prefix, row.name, &row.type_components)
                })).transpose() {
                    Ok(Some(true)) => {
                        *original_control = true;
                        // The source hint governs iteration, not the local's name.
                        declaration = before_hint.trim_end();
                    }
                    Ok(_) => {}
                    Err(actual) => {
                        if let Some(admission) = origins.admission {
                            admission.record_operational_error(actual);
                        }
                    }
                }
            }
        }
        return Some(ForControl::Each { source_binding, binding: declaration.into(), iterable });
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
            let (end, step) = parse_range_tail(remainder, clause, clause_base, diagnostics, None)?;
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
        let mut bounds_witnessed = false;
        let control = parse_range_control(
            binding, start_source, remainder, clause, clause_base, diagnostics,
            Some(&mut bounds_witnessed),
        )?;
        if bounds_witnessed {
            let name = origins.for_list_binding(clause, &lexical, clause_base, binding);
            *original_control = original_declared_range_header(
                &control, offset_of(binding), name, true, origins,
            );
        }
        return Some(control);
    }
    let mut parts = split_for_clauses(clause);
    let two_clause=parts.len()==2;
    if two_clause {
        parts.push("");
    }
    if parts.len() == 1 && parts[0].is_empty() {
        parts.extend(["", ""]);
    }
    if parts.len() == 3 {
        use crate::expression_parser::OriginalSimpleKind;
        let mut initial_witnessed = false;
        let mut test_witnessed = false;
        let mut step_witnessed = false;
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
                Some(parse_expr_observed(
                    value,
                    offset_of(value),
                    diagnostics,
                    &mut |parsed| {
                        initial_witnessed = parsed.original_simple_expression.is_some_and(|proof| {
                            proof.is_original() && proof.kind() == OriginalSimpleKind::Complete
                        });
                    },
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
            Some(ForInitializer::Expr(parse_expr_observed(
                initial,
                offset_of(initial),
                diagnostics,
                &mut |parsed| {
                    initial_witnessed = parsed.original_simple_expression.is_some_and(|proof| {
                        proof.is_original() && (proof.kind() == OriginalSimpleKind::PlainAssignment
                            || (proof.kind()==OriginalSimpleKind::Complete&&parsed.expr.as_ref().is_some_and(|value|
                                matches!(&value.kind,ExprKind::Ident(name)
                                    if crate::expression_parser::original_ordinary_call_name(name)
                                        &&!matches!(name.as_str(),"null"|"__PROC__"|"__TYPE__"|"__IMPLIED_TYPE__")))))
                    });
                },
            )?))
        };
        let condition = if parts[1].is_empty() {
            None
        } else {
            Some(parse_expr_observed(
                parts[1],
                offset_of(parts[1]),
                diagnostics,
                &mut |parsed| {
                    test_witnessed = parsed.original_simple_expression.is_some_and(|proof| {
                        proof.is_original() && matches!(proof.kind(),OriginalSimpleKind::Complete|OriginalSimpleKind::PrefixCondition)
                    });
                },
            )?)
        };
        let step = if parts[2].is_empty() {
            None
        } else {
            Some(parse_expr_observed(
                parts[2],
                offset_of(parts[2]),
                diagnostics,
                &mut |parsed| {
                    step_witnessed = original_classic_step_witness(parsed);
                },
            )?)
        };
        if (initial_witnessed || initial.is_empty()) && test_witnessed {
            if let Some(test) = &condition {
                let initial_end = match &initializer {
                    // Absence is DATA only until the SAME token provider proves
                    // the entire for/open/first-separator prefix below.
                    None => Some(item.header_span.start),
                    Some(ForInitializer::Expr(initial)) => Some(initial.span.end),
                    Some(ForInitializer::Declare { value: Some(value), .. }) => {
                        let start = offset_of(parts[0]);
                        origins.locals.entries().ok().and_then(|rows| rows.last()).filter(|row|
                            row.source_kind == crate::LocalSourceKind::ForInitializer
                                && start <= row.name.start && row.name.end <= value.span.start
                        ).and_then(|row| {
                            original_classic_tokens(origins, Span::new(start, value.span.start), row.name, true)
                                .then_some(value.span.end)
                        })
                    }
                    Some(ForInitializer::Declare { value: None, .. }) => None,
                };
                if let Some(initial_end) = initial_end {
                    if two_clause&&step.is_none(){
                        *original_control=original_two_clause_separator_question(origins.settings,
                            Span::new(initial_end,test.span.start),Span::new(test.span.end,item.header_span.end),
                            initializer.is_none(),origins.admission);
                    }else if let Some(step)=&step{
                    if !step_witnessed {
                        if let ExprKind::Unary { op, value } = &step.kind {
                            step_witnessed = op == "pre++"
                                && matches!(&value.kind, ExprKind::Ident(name)
                                    if crate::expression_parser::original_ascii_identifier(name))
                                && original_classic_tokens(origins, step.span, value.span, false);
                        }
                    }
                    if step_witnessed {
                        let first = Span::new(initial_end, test.span.start);
                        let second = Span::new(test.span.end, step.span.start);
                        *original_control = original_classic_separator_question(
                            origins.settings, first, second, initializer.is_none(), origins.admission,
                        );
                    }
                    }
                }
            }
        }
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

fn original_two_clause_separator_question(provider:Option<&dyn SettingSyntaxProvider>,first:Span,tail:Span,empty:bool,a:Option<&crate::SettingAdmission<'_>>)->bool{
 match provider.map(|p|p.original_two_clause_for_header(first,tail,empty)).transpose(){Ok(value)=>value==Some(true),Err(actual)=>{if let Some(a)=a{a.record_operational_error(actual)}false}}
}

// Route only the existing same-body separator question. A false/default/missing
// provider never creates grammar authority; actual operational errors stay sticky.
fn original_classic_separator_question(
    provider: Option<&dyn SettingSyntaxProvider>, first: Span, second: Span,
    empty_initializer: bool, admission: Option<&crate::SettingAdmission<'_>>,
) -> bool {
    match provider.map(|provider| provider.original_classic_for_separators(first, second, empty_initializer)).transpose() {
        Ok(value) => value == Some(true),
        Err(actual) => {
            if let Some(admission) = admission { admission.record_operational_error(actual); }
            false
        }
    }
}

fn original_classic_tokens(origins: &BodyOrigins<'_>, span: Span, name: Span, declaration: bool) -> bool {
    match origins.settings.map(|provider| provider.original_classic_for_tokens(span, name, declaration)).transpose() {
        Ok(value) => value == Some(true),
        Err(actual) => {
            if let Some(admission) = origins.admission {
                admission.record_operational_error(actual);
            }
            false
        }
    }
}

fn original_declared_range_header(
    control: &ForControl, binding_start: usize, name: Option<ForListBinding>,
    initialized: bool, origins: &BodyOrigins<'_>,
) -> bool {
    let (ForControl::Range { start, end, step: None, .. }, Some(name)) = (control, name)
        else { return false; };
    let prefix = Span::new(binding_start, start.span.start);
    let between = Span::new(start.span.end, end.span.start);
    match origins.settings.map(|provider| {
        provider.original_for_range_header(prefix, name.name(), between, initialized)
    }).transpose() {
        Ok(value) => value == Some(true),
        Err(actual) => {
            if let Some(admission) = origins.admission {
                admission.record_operational_error(actual);
            }
            false
        }
    }
}

fn parse_range_control(
    binding: &str,
    start_source: &str,
    remainder: &str,
    clause: &str,
    base: usize,
    diagnostics: &mut BodyDiagnostics<'_>,
    witness: Option<&mut bool>,
) -> Option<ForControl> {
    let start_source = start_source.trim();
    let mut start_witnessed = false;
    let start = parse_expr_observed(
        start_source,
        base + (start_source.as_ptr() as usize - clause.as_ptr() as usize),
        diagnostics,
        &mut |parsed| {
            start_witnessed = witness.is_some() && original_complete_range_bound(parsed);
        },
    )?;
    let mut end_witnessed = false;
    let (end, step) = parse_range_tail(
        remainder, clause, base, diagnostics, witness.as_ref().map(|_| &mut end_witnessed),
    )?;
    if let Some(witness) = witness {
        *witness = start_witnessed && end_witnessed && step.is_none();
    }
    Some(ForControl::Range {
        binding: binding.into(),
        start,
        end,
        step,
    })
}

fn original_complete_range_bound(parsed: &crate::ParsedExpr) -> bool {
    parsed.original_simple_expression.is_some_and(|value| {
        value.is_original() && value.kind() == crate::expression_parser::OriginalSimpleKind::Complete
    })
}

fn parse_range_tail(
    remainder: &str,
    clause: &str,
    base: usize,
    diagnostics: &mut BodyDiagnostics<'_>,
    end_witnessed: Option<&mut bool>,
) -> Option<(Expr, Option<Expr>)> {
    let (end_source, step_source) = remainder
        .split_once(" step ")
        .map_or((remainder, None), |(end, step)| (end, Some(step)));
    let end_source = end_source.trim();
    let mut end_witnessed = end_witnessed;
    let end = parse_expr_observed(
        end_source,
        base + (end_source.as_ptr() as usize - clause.as_ptr() as usize),
        diagnostics,
        &mut |parsed| {
            if let Some(witness) = end_witnessed.as_deref_mut() {
                *witness = original_complete_range_bound(parsed);
            }
        },
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
pub(super) fn control_inline<'a>(item: &'a Item, keyword: &str) -> Option<&'a str> {
    control_inline_header(&item.header, keyword)
}

pub(super) fn control_inline_header<'a>(header: &'a str, keyword: &str) -> Option<&'a str> {
    let rest = header.trim().strip_prefix(keyword)?.trim_start();
    let close = control_close(rest)?;
    let inline = rest[close + 1..].trim().trim_end_matches(';').trim();
    (!inline.is_empty()).then_some(inline)
}
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
    let (clause, opening, _, start) = control_clause_origin_tokens(item, keyword, diagnostics)?;
    let condition = parse_expr_observed(
        clause,
        start,
        diagnostics,
        &mut |parsed| {
            let issued = parsed.original_simple_expression.is_some_and(|value| value.kind() == crate::expression_parser::OriginalSimpleKind::Complete || (value.is_original()&&value.kind()==crate::expression_parser::OriginalSimpleKind::PrefixCondition));
            origins.require_original(issued, Span::new(start, start + clause.len()), "control_condition");
        },
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
    parse_expr_observed_with_native(source,offset,diagnostics,observe).0
}
pub(super) fn parse_expr_observed_with_native(source:&str,offset:usize,diagnostics:&mut BodyDiagnostics<'_>,observe:&mut dyn FnMut(&crate::ParsedExpr))->(Option<Expr>,Option<crate::NativeExpressionParserFacts>){
    if source.trim().is_empty() {
        diagnostics.push(Diagnostic {
            span: Span::new(offset, offset),
            kind: DiagnosticKind::Statement,
            message: "missing expression".into(),
        });
        return (None,None);
    }
    let original=match diagnostics.settings{
      Some(provider)=>match provider.original_expression_with_native_facts(source,offset){Ok(value)=>value,Err(actual)=>{if let Some(a)=diagnostics.admission{a.record_operational_error(actual);}return (None,None)}},None=>None,
    };
    let using_original=original.is_some();
    let (mut parsed,native) = match original{Some(pair)=>pair,None=>(parse_expression(source),None)};
    if let Some(progress)=diagnostics.native_progress{
        progress.expression(native,parsed.expr.as_ref().map(|expr|expr.span));
    }
    observe(&parsed);
    for diagnostic in &mut parsed.diagnostics {
        diagnostic.span.start += offset;
        diagnostic.span.end += offset;
    }
    let clean = parsed.diagnostics.is_empty();
    diagnostics.extend(parsed.diagnostics);
    if !clean {
        return (None,None);
    }
    let Some(mut expr)=parsed.expr else{return (None,None)};
    if using_original {
        let Some(a)=diagnostics.admission else {
            diagnostics.push(Diagnostic{span:expr.span,kind:DiagnosticKind::Statement,message:"Original expression requires its native operation admission".into()});
            return (None,None);
        };
        if let Err(actual)=crate::literal::shift_unpublished_expression_using(&mut expr,offset,a) {
            a.record_operational_error(actual);
            return (None,None);
        }
    } else { shift_expr(&mut expr, offset); }
    (Some(expr),native)
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

#[cfg(test)]
mod original_existing_for_each_controls {
    use super::*;
    #[test]
    fn original_existing_for_each_header_keeps_one_name_and_the_same_separator() {
        for (clause, expected) in [
            ("current_sort_text in incoming", true),
            ("not_declared_here in incoming", true),
            ("global in incoming", true),
            ("null in incoming", false),
            ("__PROC__ in incoming", false),
            ("__TYPE__ in incoming", false),
            ("__IMPLIED_TYPE__ in incoming", false),
            ("var/current_sort_text in incoming", true),
            ("var/datum/current_sort_text in incoming", true),
            ("current_sort_text.name in incoming", false),
            ("current_sort_text[key] in incoming", false),
            ("(current_sort_text) in incoming", false),
            ("current_sort_text = other in incoming", false),
            ("current_sort_text, other in incoming", false),
            ("current_sort_text as anything in incoming", false),
            ("current_sort_text in incoming to other", false),
            ("current_sort_text in incoming tail", false),
        ] {
            let lexical = crate::lex_spans(clause);
            let separator = lexical.tokens.iter().find(|token| token.text(clause) == "in").unwrap().span.start;
            assert_eq!(original_for_each_clause(clause, &lexical, separator,
                false, false, false, false, false, false, false), expected, "{clause}");
            assert!(!original_for_each_clause(clause, &lexical, separator + 1,
                false, false, false, false, false, false, false), "wrong separator: {clause}");
        }
    }
    #[test]
    fn original_existing_for_each_never_adds_a_shadow_declaration_to_the_primary_ledger() {
        for (outer, binding, expected_statements, expected_bindings) in [
            ("    var/current_sort_text\n", "current_sort_text", 1, 0),
            ("", "current_sort_text", 0, 0),
            ("    var/current_sort_text\n", "var/current_sort_text", 1, 1),
        ] {
            let source = format!("/proc/probe(incoming)\n{outer}    for({binding} in incoming)\n        return current_sort_text\n    return current_sort_text\n");
            let syntax = crate::parse(&source);
            let body = crate::parse_proc_body(&syntax.items[0]);
            assert!(body.diagnostics.is_empty(), "{:?}", body.diagnostics);
            let locals = body.local_variables.entries().unwrap();
            assert_eq!(locals.iter().filter(|row| row.source_kind == crate::LocalSourceKind::Statement).count(), expected_statements);
            assert_eq!(locals.iter().filter(|row| row.source_kind == crate::LocalSourceKind::ForBinding).count(), expected_bindings);
            let statement = &body.statements[expected_statements];
            let StatementKind::For { control: ForControl::Each { source_binding, binding: actual, .. }, .. } = &statement.kind
                else { panic!("same for-list production"); };
            assert_eq!(actual, binding);
            let name = source_binding.expect("one genuine consumed header name").name();
            assert_eq!(&source[name.range()], "current_sort_text");
        }
    }
}

#[cfg(test)]
#[test]
fn original_empty_classic_separator_question_defaults_closed_and_preserves_actual_error() {
    struct Deny;
    impl SettingSyntaxProvider for Deny {
        fn setting(&self, _: &Item) -> Result<SettingStatement, Diagnostic> { unreachable!() }
    }
    struct Fail(std::cell::Cell<usize>);
    impl SettingSyntaxProvider for Fail {
        fn setting(&self, _: &Item) -> Result<SettingStatement, Diagnostic> { unreachable!() }
        fn original_classic_for_separators(&self, first: Span, second: Span, empty_initializer: bool) -> std::io::Result<bool> {
            assert_eq!(first, Span::new(10, 20));
            assert_eq!(second, Span::new(30, 32));
            assert!(empty_initializer);
            self.0.set(self.0.get() + 1);
            Err(std::io::Error::from_raw_os_error(1450))
        }
    }
    let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
    let admission = crate::SettingAdmission::new(&used, 1 << 20, &|| Ok(()));
    let first = Span::new(10, 20);
    let second = Span::new(30, 32);
    for empty in [false, true] {
        assert!(!original_classic_separator_question(None, first, second, empty, Some(&admission)));
        assert!(!original_classic_separator_question(Some(&Deny), first, second, empty, Some(&admission)));
    }
    assert!(!admission.is_stopped());
    let fail = Fail(std::cell::Cell::new(0));
    assert!(!original_classic_separator_question(Some(&fail), first, second, true, Some(&admission)));
    assert_eq!(fail.0.get(), 1);
    assert!(admission.is_stopped());
    assert_eq!(admission.take_operational_error().unwrap().raw_os_error(), Some(1450));
    // No fake positive source/header/expression proof is supplied by this test.
}

// A role check on an already-issued complete expression receipt; it cannot
// produce an expression witness or authenticate a for header by itself.
fn original_classic_step_witness(parsed: &crate::ParsedExpr) -> bool {
    use crate::expression_parser::OriginalSimpleKind;
    let Some(proof)=parsed.original_simple_expression else { return false; };
    if !proof.is_original() { return false; }
    match proof.kind() {
        OriginalSimpleKind::PostIncrementStatement
            | OriginalSimpleKind::PostDecrementStatement
            | OriginalSimpleKind::PlainAssignment => true,
        OriginalSimpleKind::SimpleAssignmentStatement => parsed.expr.as_ref().is_some_and(|expr|
            matches!(&expr.kind, ExprKind::Binary { op, lhs, .. }
                if matches!(op.as_str(), "+=" | "-=")
                    && matches!(&lhs.kind, ExprKind::Ident(name)
                        if crate::expression_parser::original_ordinary_call_name(name)
                            && !matches!(name.as_str(), "null" | "__PROC__" | "__TYPE__" | "__IMPLIED_TYPE__")))),
        _ => false,
    }
}

#[cfg(test)]
#[test]
fn original_classic_step_never_upgrades_compatibility_expression_provenance() {
    for text in ["i += length(char)", "i -= 1", "i++", "i = i + 1", "i.field += 1", "i[1] += 1"] {
        let parsed=crate::parse_expression(text);
        assert!(parsed.expr.is_some(), "{text}");
        assert!(!original_classic_step_witness(&parsed), "a compatibility AST is not an Original receipt: {text}");
    }
}

#[cfg(test)]
mod original_classic_step_typed_demand_controls {
    use super::*;
    struct FinalTokens { rows: Vec<crate::Token>, next: usize, fail_at: Option<usize>, faulted: bool }
    impl FinalTokens {
        // These are already-FINAL punctuation occurrences, exactly as the
        // occurrence-aware primary producer lends them. Raw lex() deliberately
        // emits separate + and = bytes and must not be mislabeled final +=.
        fn fixture(text: &str, fail_at: Option<usize>) -> Self {
            let mut cursor=0;
            let rows=text.split_whitespace().map(|spelling| {
                let start=cursor+text[cursor..].find(spelling).unwrap();
                cursor=start+spelling.len();
                let kind=if crate::expression_parser::original_ascii_identifier(spelling) {
                    crate::TokenKind::Ident
                } else if spelling.bytes().all(|b|b.is_ascii_digit()) {
                    crate::TokenKind::Number
                } else {
                    assert!(crate::original_scalar_transport::original_punctuation_storage_index(spelling).is_some(),
                        "fixture punctuation must be an actual final primary spelling: {spelling}");
                    crate::original_scalar_transport::original_punctuation_native_kind(spelling)
                };
                crate::Token {kind,span:Span::new(start,cursor),text:spelling.into()}
            }).collect();
            Self {rows,next:0,fail_at,faulted:false}
        }
    }
    impl crate::NativeExpressionTokenDemand for FinalTokens {
        fn next_token(&mut self) -> std::io::Result<Option<crate::Token>> {
            assert!(!self.faulted,"first actual demand fault must stop later source pulls");
            if self.fail_at == Some(self.next) {
                self.faulted=true;
                return Err(std::io::Error::from_raw_os_error(1450));
            }
            let row=self.rows.get(self.next).cloned(); self.next+=1; Ok(row)
        }
        fn requires_original_values(&self)->bool { true }
        fn original_value(&self, at: crate::NativeExpressionTokenOccurrence)
            -> std::io::Result<Option<crate::OriginalTokenValue<&str>>> {
            let token=self.rows.get(at.ordinal()).ok_or(std::io::ErrorKind::InvalidInput)?;
            if token.span != at.span() { return Err(std::io::ErrorKind::InvalidInput.into()); }
            Ok(Some(match token.kind {
                crate::TokenKind::Ident => crate::OriginalTokenValue::Ident { spelling: &token.text, whitespace: false },
                crate::TokenKind::Number => crate::OriginalTokenValue::Int(token.text.parse().map_err(|_|std::io::ErrorKind::InvalidData)?),
                _ => {
                    let index=crate::original_scalar_transport::original_punctuation_storage_index(&token.text)
                        .ok_or(std::io::ErrorKind::InvalidInput)?;
                    crate::OriginalTokenValue::Punct(crate::original_scalar_transport::original_punctuation_storage_value(index)
                        .ok_or(std::io::ErrorKind::InvalidInput)?)
                }
            }))
        }
    }
    #[test]
    fn actual_original_classic_step_role_uses_issued_expression_and_exact_bare_target() {
        let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let admission=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
        for (text,expected) in [
            ("i += length ( char )",true),("i -= 1",true),
            ("i ++",true),("i --",true),("i = i + 1",true),
            ("i . field += 1",false),("i [ 1 ] += 1",false),
            ("( i ) += 1",false),("i *= 1",false),("i += ( char += 1 )",false),
            ("null += 1",false),("__PROC__ += 1",false),
        ] {
            // A typed final-token fixture supplies only expression occurrences;
            // it never certifies a body, loop, source header or separator.
            let mut source=FinalTokens::fixture(text,None);
            let root=crate::parse_original_expression_demanded(&mut source,&admission).unwrap();
            if expected { assert!(root.parsed().diagnostics.is_empty(),"actual final-token syntax: {text}: {:?}",root.parsed().diagnostics); }
            assert_eq!(original_classic_step_witness(root.parsed()),expected,
                "{text}; receipt={:?}; AST={:?}; diagnostics={:?}",root.parsed().original_simple_expression,
                root.parsed().expr,root.parsed().diagnostics);
            drop(root);
            assert_eq!(used.load(std::sync::atomic::Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
        }
    }
    #[test]
    fn raw_split_assignment_bytes_mislabeled_as_final_are_not_repaired_into_a_step_receipt() {
        let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let admission=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
        let rows=crate::lex("i += length(char)").tokens;
        assert!(!rows.iter().any(|token|token.text=="+="));
        assert!(rows.iter().any(|token|token.text=="+"));
        assert!(rows.iter().any(|token|token.text=="="));
        let mut source=FinalTokens{rows,next:0,fail_at:None,faulted:false};
        let root=crate::parse_original_expression_demanded(&mut source,&admission).unwrap();
        assert!(!original_classic_step_witness(root.parsed()),"typed final-value contract forbids silently merging raw bytes");
        drop(root);
        assert_eq!(used.load(std::sync::atomic::Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
    }
    #[test]
    fn actual_original_classic_step_first_demand_io_never_becomes_a_role_witness() {
        let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let admission=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
        for fail_at in [0,1,2] {
            let mut source=FinalTokens::fixture("i += length ( char )",Some(fail_at));
            let error=crate::parse_original_expression_demanded(&mut source,&admission).err()
                .expect("actual demand failure cannot become a compatibility result or step receipt");
            assert_eq!(error.raw_os_error(),Some(1450));
            assert_eq!(source.next,fail_at);
            assert_eq!(used.load(std::sync::atomic::Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
        }
    }
}

#[cfg(test)]mod original_for_constructor_controls{
 use super::*;use std::sync::atomic::Ordering;
 #[test]fn for_constructor_requires_its_complete_child_and_exact_separator(){
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
  let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  for (source,wanted) in [("list(1,2,3)",true),("alist(key=value)",true),("list(list(1),2)",true),("choose()",true),("list(key=)",false),("owner.list()",false),("call(target)()",false)]{
   let tokens=crate::lex_spans(source).tokens;
   let child=crate::expression_parser::parse_expression_original_token_view(source,&tokens,0,&a,None);
   let issued=child.original_simple_expression.is_some_and(|proof|proof.is_original()&&proof.kind()==crate::expression_parser::OriginalSimpleKind::Complete)
    &&child.expr.as_ref().is_some_and(original_direct_for_iterable);
   assert_eq!(issued,wanted,"{source}: {:?}",child.diagnostics);
   if issued{
    let clause=format!("var/bad_name in {source}");let lexical=crate::lex_spans(&clause);
    let at=lexical.tokens.iter().find(|token|token.text(&clause)=="in").unwrap().span.start;
    assert!(original_for_each_clause(&clause,&lexical,at,false,false,false,true,false,false,false));
    assert!(!original_for_each_clause(&clause,&lexical,at+1,false,false,false,true,false,false,false));
   }
   drop(child);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
  }
 }
}

#[cfg(test)]
#[test]
fn composed_iterable_data_route_preserves_the_selected_binding_and_in_separator(){
 for clause in ["var/item in owner.items[key]","item in owner?.items","var/item in owner.items()"]{
  let lexical=crate::lex_spans(clause);let at=lexical.tokens.iter().find(|token|token.text(clause)=="in").unwrap().span.start;
  assert!(original_for_each_clause(clause,&lexical,at,false,false,false,false,false,false,true));
  assert!(!original_for_each_clause(clause,&lexical,at+1,false,false,false,false,false,false,true));
 }
 for clause in ["owner.item in owner.items[key]","var/item = other in owner.items[key]","var/item as anything in owner.items[key]"]{
  let lexical=crate::lex_spans(clause);let at=lexical.tokens.iter().find(|token|token.text(clause)=="in").unwrap().span.start;
  assert!(!original_for_each_clause(clause,&lexical,at,false,false,false,false,false,false,true),"{clause}");
 }
 // These are routing DATA only: a compatibility tree is not issued Original.
 for leaf in ["for(var/item in owner.items[key]) return item","for(var/item as anything in owner.items()) return item","for(item,item,item=item.loc); return item"]{
  let syntax=crate::parse(&format!("/proc/probe(owner,key,item)\n    {leaf}\n"));
  assert!(crate::parse_proc_body(&syntax.items[0]).original_grammar.is_none());
 }
}

#[cfg(test)]
#[test]
fn two_clause_for_question_defaults_closed_and_preserves_first_actual_io(){
 struct Deny;impl SettingSyntaxProvider for Deny{fn setting(&self,_:&Item)->Result<SettingStatement,Diagnostic>{unreachable!()}}
 struct Fail(std::cell::Cell<usize>);impl SettingSyntaxProvider for Fail{
  fn setting(&self,_:&Item)->Result<SettingStatement,Diagnostic>{unreachable!()}
  fn original_two_clause_for_header(&self,first:Span,tail:Span,empty:bool)->std::io::Result<bool>{assert_eq!(first,Span::new(10,20));assert_eq!(tail,Span::new(30,31));assert!(!empty);self.0.set(self.0.get()+1);Err(std::io::Error::from_raw_os_error(1450))}
 }
 let root=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(root).unwrap();let a=crate::SettingAdmission::new(&used,1<<20,&||Ok(()));
 assert!(!original_two_clause_separator_question(None,Span::new(10,20),Span::new(30,31),false,Some(&a)));
 assert!(!original_two_clause_separator_question(Some(&Deny),Span::new(10,20),Span::new(30,31),false,Some(&a)));
 let fail=Fail(0.into());assert!(!original_two_clause_separator_question(Some(&fail),Span::new(10,20),Span::new(30,31),false,Some(&a)));assert_eq!(fail.0.get(),1);assert_eq!(a.take_operational_error().unwrap().raw_os_error(),Some(1450));assert_eq!(used.load(std::sync::atomic::Ordering::Acquire),root);
}

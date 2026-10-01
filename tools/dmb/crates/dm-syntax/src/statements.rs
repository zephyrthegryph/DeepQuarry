//! A typed, recovering procedure body layer over the lossless indentation tree.
//! Every statement retains its original header and absolute source byte spans.

use crate::{parse_expression, Diagnostic, DiagnosticKind, Expr, ExprKind, Item, ItemKind, Span};

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Statement {
    pub kind: StatementKind,
    pub span: Span,
    pub header_span: Span,
    pub raw_header: String,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ForControl {
    All {
        declaration: String,
    },
    Each {
        binding: String,
        iterable: Expr,
    },
    Pair {
        key_binding: String,
        value_binding: String,
        iterable: Expr,
    },
    Range {
        binding: String,
        start: Expr,
        end: Expr,
        step: Option<Expr>,
    },
    CStyle {
        initializer: Option<ForInitializer>,
        condition: Option<Expr>,
        step: Option<Expr>,
    },
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ForInitializer {
    Declare {
        declaration: String,
        value: Option<Expr>,
    },
    Expr(Expr),
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum SwitchAlternative {
    Exact(Expr),
    Range(Expr, Expr),
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SwitchCase {
    pub alternatives: Vec<SwitchAlternative>,
    pub body: Vec<Statement>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum StatementKind {
    If {
        condition: Expr,
        then_branch: Vec<Statement>,
        else_branch: Vec<Statement>,
    },
    While {
        condition: Expr,
        body: Vec<Statement>,
    },
    DoWhile {
        body: Vec<Statement>,
        condition: Expr,
    },
    Spawn {
        delay: Option<Expr>,
        body: Vec<Statement>,
    },
    Set {
        attribute: String,
        relation: String,
        value: Expr,
    },
    For {
        control: ForControl,
        body: Vec<Statement>,
    },
    Switch {
        selector: Expr,
        cases: Vec<SwitchCase>,
        else_branch: Vec<Statement>,
    },
    Try {
        body: Vec<Statement>,
        catch_binding: Option<String>,
        catch_body: Vec<Statement>,
    },
    Throw(Expr),
    Label {
        name: String,
        body: Vec<Statement>,
    },
    Goto(String),
    Return(Option<Expr>),
    Var {
        declaration: String,
        value: Option<Expr>,
    },
    Assign {
        target: Expr,
        op: String,
        value: Expr,
    },
    Call(Expr),
    Expression(Expr),
    Break,
    BreakLabel(String),
    Continue,
    ContinueLabel(String),
    /// Keeps syntax available to diagnostics and future grammar extensions.
    Unsupported,
}

#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct ParsedBody {
    pub statements: Vec<Statement>,
    pub diagnostics: Vec<Diagnostic>,
}

/// Parse the body of a structural `Proc` or `Verb` item. Unsupported forms are retained as
/// `StatementKind::Unsupported` and always carry a diagnostic; callers must reject such bodies.
pub fn parse_proc_body(proc: &Item) -> ParsedBody {
    let mut result = ParsedBody::default();
    if !matches!(proc.kind, ItemKind::Proc | ItemKind::Verb) {
        result.diagnostics.push(Diagnostic {
            span: proc.header_span,
            kind: DiagnosticKind::Statement,
            message: "expected a procedure or verb item".into(),
        });
        return result;
    }
    parse_body_items(&proc.children)
}

/// Parse a procedure body when its owning declaration is already known.
pub fn parse_body_items(items: &[Item]) -> ParsedBody {
    let mut result = ParsedBody::default();
    result.statements = parse_sequence(items, &mut result.diagnostics);
    result
}

fn parse_sequence(items: &[Item], diagnostics: &mut Vec<Diagnostic>) -> Vec<Statement> {
    let mut statements = Vec::new();
    let mut index = 0;
    while index < items.len() {
        let item = &items[index];
        let header = item.header.trim();
        if (header.starts_with("var/") || starts_keyword(header, "var")) && item.children.is_empty()
        {
            let parts = split_case_alternatives(header);
            if parts.len() > 1 {
                let first_decl = parts[0].split('=').next().unwrap().trim();
                let prefix = first_decl
                    .rsplit_once('/')
                    .map(|(base, _)| format!("{base}/"))
                    .unwrap_or_else(|| "var ".into());
                for (part_index, part) in parts.into_iter().enumerate() {
                    let part = part.trim();
                    let mut nested = item.clone();
                    nested.header = if part_index == 0 {
                        part.into()
                    } else {
                        format!("{prefix}{part}")
                    };
                    let at = item.header.find(part).unwrap_or(0);
                    nested.header_span.start +=
                        at.saturating_sub(if part_index == 0 { 0 } else { prefix.len() });
                    let actual_span = Span::new(
                        item.header_span.start + at,
                        item.header_span.start + at + part.len(),
                    );
                    let mut statement = parse_one(&nested, diagnostics);
                    statement.span = actual_span;
                    statement.header_span = actual_span;
                    statement.raw_header = part.into();
                    statements.push(statement);
                }
                index += 1;
                continue;
            }
        }
        if starts_keyword(header, "if") {
            let mut end = index + 1;
            while items
                .get(end)
                .is_some_and(|next| starts_keyword(next.header.trim(), "else"))
            {
                end += 1;
            }
            statements.push(parse_if(item, &items[index + 1..end], diagnostics));
            index = end;
            continue;
        }
        if header == "do" {
            if let Some(next) = items.get(index + 1).filter(|next| {
                starts_keyword(next.header.trim(), "while") && next.children.is_empty()
            }) {
                if let Some(condition) = parse_control_condition(next, "while", diagnostics) {
                    statements.push(Statement {
                        kind: StatementKind::DoWhile {
                            body: parse_sequence(&item.children, diagnostics),
                            condition,
                        },
                        span: Span::new(item.span.start, next.span.end),
                        header_span: item.header_span,
                        raw_header: item.header.clone(),
                    });
                } else {
                    statements.push(unsupported(item));
                }
                index += 2;
                continue;
            }
            diagnostics.push(Diagnostic {
                span: item.header_span,
                kind: DiagnosticKind::Statement,
                message: "do requires a following while condition".into(),
            });
            statements.push(unsupported(item));
            index += 1;
            continue;
        }
        if header == "try" {
            let Some(catch) = items.get(index + 1) else {
                diagnostics.push(Diagnostic {
                    span: item.header_span,
                    kind: DiagnosticKind::Statement,
                    message: "try requires catch".into(),
                });
                statements.push(unsupported(item));
                index += 1;
                continue;
            };
            let catch_header = catch.header.trim();
            let catch_binding = if catch_header == "catch" {
                Some(None)
            } else if catch_header.starts_with("catch(") && catch_header.ends_with(')') {
                Some(Some(
                    catch_header[6..catch_header.len() - 1].trim().to_owned(),
                ))
            } else {
                None
            };
            if let Some(catch_binding) = catch_binding {
                statements.push(Statement {
                    kind: StatementKind::Try {
                        body: parse_sequence(&item.children, diagnostics),
                        catch_binding,
                        catch_body: parse_sequence(&catch.children, diagnostics),
                    },
                    span: Span::new(item.span.start, catch.span.end),
                    header_span: item.header_span,
                    raw_header: item.header.clone(),
                });
                index += 2;
                continue;
            }
            diagnostics.push(Diagnostic {
                span: catch.header_span,
                kind: DiagnosticKind::Statement,
                message: "try requires catch".into(),
            });
            statements.push(unsupported(item));
            index += 1;
            continue;
        }
        if starts_keyword(header, "catch") {
            diagnostics.push(Diagnostic {
                span: item.header_span,
                kind: DiagnosticKind::Statement,
                message: "catch without try".into(),
            });
            statements.push(unsupported(item));
            index += 1;
            continue;
        }
        if starts_keyword(header, "else") {
            diagnostics.push(Diagnostic {
                span: item.header_span,
                kind: DiagnosticKind::Statement,
                message: "else without preceding if".into(),
            });
            statements.push(unsupported(item));
            index += 1;
            continue;
        }
        statements.push(parse_one(item, diagnostics));
        index += 1;
    }
    statements
}

fn parse_if(item: &Item, else_items: &[Item], diagnostics: &mut Vec<Diagnostic>) -> Statement {
    let condition = parse_control_condition(item, "if", diagnostics);
    let then_branch = control_body(item, "if", diagnostics);
    let mut span = item.span;
    let else_branch = if let Some((other, remaining)) = else_items.split_first() {
        span.end = else_items.last().unwrap().span.end;
        let header = other.header.trim();
        if header == "else" {
            for extra in remaining {
                diagnostics.push(Diagnostic {
                    span: extra.header_span,
                    kind: DiagnosticKind::Statement,
                    message: "duplicate else clause".into(),
                });
            }
            parse_sequence(&other.children, diagnostics)
        } else if let Some(rest) = header.strip_prefix("else").map(str::trim_start) {
            if !starts_keyword(rest, "if") {
                let mut inline = other.clone();
                inline.header = rest.trim_end_matches(';').into();
                inline.header_span.start += other.header.find(rest).unwrap_or(0);
                parse_sequence(&[inline], diagnostics)
            } else {
                let mut nested = other.clone();
                nested.header = rest.into();
                nested.header_span.start += other.header.find(rest).unwrap_or(0);
                vec![parse_if(&nested, remaining, diagnostics)]
            }
        } else {
            diagnostics.push(Diagnostic {
                span: other.header_span,
                kind: DiagnosticKind::Unsupported,
                message: "unsupported else clause".into(),
            });
            vec![unsupported(other)]
        }
    } else {
        Vec::new()
    };
    match condition {
        Some(condition) => Statement {
            kind: StatementKind::If {
                condition,
                then_branch,
                else_branch,
            },
            span,
            header_span: item.header_span,
            raw_header: item.header.clone(),
        },
        None => unsupported(item),
    }
}

fn parse_one(item: &Item, diagnostics: &mut Vec<Diagnostic>) -> Statement {
    let header = item.header.trim();
    let kind = if starts_keyword(header, "while") {
        parse_control_condition(item, "while", diagnostics).map(|condition| StatementKind::While {
            condition,
            body: control_body(item, "while", diagnostics),
        })
    } else if starts_keyword(header, "for") {
        parse_for(item, diagnostics).map(|control| StatementKind::For {
            control,
            body: control_body(item, "for", diagnostics),
        })
    } else if starts_keyword(header, "switch") {
        parse_switch(item, diagnostics)
    } else if starts_keyword(header, "spawn") {
        parse_spawn(item, diagnostics)
    } else if starts_keyword(header, "set") {
        parse_set(item, diagnostics)
    } else if header == "return" {
        Some(StatementKind::Return(None))
    } else if starts_keyword(header, "return") || header.starts_with("return..(") {
        let rest = header.strip_prefix("return").unwrap().trim_start();
        parse_expr(
            rest,
            item.header_span.start + item.header.find(rest).unwrap_or(0),
            diagnostics,
        )
        .map(|expr| StatementKind::Return(Some(expr)))
    } else if starts_keyword(header, "throw") {
        let rest = header.strip_prefix("throw").unwrap().trim_start();
        parse_expr(
            rest,
            item.header_span.start + item.header.find(rest).unwrap_or(0),
            diagnostics,
        )
        .map(StatementKind::Throw)
    } else if let Some(label) = header.strip_prefix("goto ") {
        Some(StatementKind::Goto(label.trim().into()))
    } else if let Some(label) = header.strip_suffix(':') {
        Some(StatementKind::Label {
            name: label.trim().into(),
            body: parse_sequence(&item.children, diagnostics),
        })
    } else if header == "break" {
        Some(StatementKind::Break)
    } else if let Some(label) = header.strip_prefix("break ") {
        Some(StatementKind::BreakLabel(label.trim().into()))
    } else if header == "continue" {
        Some(StatementKind::Continue)
    } else if let Some(label) = header.strip_prefix("continue ") {
        Some(StatementKind::ContinueLabel(label.trim().into()))
    } else if header.starts_with("var/") || starts_keyword(header, "var") {
        parse_var(item, diagnostics)
    } else if !item.children.is_empty() {
        diagnostics.push(Diagnostic {
            span: item.header_span,
            kind: DiagnosticKind::Unsupported,
            message: "unsupported statement block".into(),
        });
        None
    } else {
        parse_expr(header, item.header_span.start, diagnostics).map(|expr| match expr.kind {
            ExprKind::Binary { op, lhs, rhs } if is_assignment(&op) => StatementKind::Assign {
                target: *lhs,
                op,
                value: *rhs,
            },
            ExprKind::Call { .. } => StatementKind::Call(expr),
            _ => StatementKind::Expression(expr),
        })
    };
    match kind {
        Some(kind) => Statement {
            kind,
            span: item.span,
            header_span: item.header_span,
            raw_header: item.header.clone(),
        },
        None => unsupported(item),
    }
}

fn parse_set(item: &Item, diagnostics: &mut Vec<Diagnostic>) -> Option<StatementKind> {
    let header = item.header.trim();
    let rest = header.strip_prefix("set")?.trim_start();
    let equals = rest.find('=');
    let inside = rest.find(" in ");
    let (attribute, relation, value) =
        if equals.is_some_and(|at| inside.is_none_or(|other| at < other)) {
            let at = equals.unwrap();
            (rest[..at].trim(), "=", rest[at + 1..].trim())
        } else if let Some(at) = inside {
            (rest[..at].trim(), "in", rest[at + " in ".len()..].trim())
        } else {
            diagnostics.push(Diagnostic {
                span: item.header_span,
                kind: DiagnosticKind::Statement,
                message: "expected set attribute = value or set attribute in value".into(),
            });
            return None;
        };
    if attribute.is_empty() || value.is_empty() {
        diagnostics.push(Diagnostic {
            span: item.header_span,
            kind: DiagnosticKind::Statement,
            message: "missing set attribute or value".into(),
        });
        return None;
    }
    let value = parse_expr(
        value,
        item.header_span.start + item.header.find(value).unwrap_or(0),
        diagnostics,
    )?;
    Some(StatementKind::Set {
        attribute: attribute.into(),
        relation: relation.into(),
        value,
    })
}

fn parse_spawn(item: &Item, diagnostics: &mut Vec<Diagnostic>) -> Option<StatementKind> {
    let header = item.header.trim();
    let rest = header.strip_prefix("spawn")?.trim_start();
    let (delay, inline) = if rest.is_empty() {
        (None, "")
    } else if let Some(open) = rest.strip_prefix('(') {
        let mut depth = 1usize;
        let mut quote = None;
        let mut escaped = false;
        let mut close = None;
        for (at, ch) in open.char_indices() {
            if escaped {
                escaped = false;
                continue;
            }
            if ch == '\\' {
                escaped = true;
                continue;
            }
            if let Some(delimiter) = quote {
                if ch == delimiter {
                    quote = None;
                }
                continue;
            }
            match ch {
                '\'' | '"' => quote = Some(ch),
                '(' => depth += 1,
                ')' => {
                    depth -= 1;
                    if depth == 0 {
                        close = Some(at);
                        break;
                    }
                }
                _ => {}
            }
        }
        let Some(close) = close else {
            diagnostics.push(Diagnostic {
                span: item.header_span,
                kind: DiagnosticKind::Statement,
                message: "unclosed spawn delay".into(),
            });
            return None;
        };
        (Some(open[..close].trim()), open[close + 1..].trim())
    } else {
        (None, rest)
    };
    let delay = match delay.filter(|delay| !delay.is_empty()) {
        Some(delay) => Some(parse_expr(
            delay,
            item.header_span.start + item.header.find(delay).unwrap_or(0),
            diagnostics,
        )?),
        None => None,
    };
    let body = if inline.is_empty() {
        parse_sequence(&item.children, diagnostics)
    } else {
        let mut inline_item = item.clone();
        inline_item.header = inline.into();
        inline_item.header_span.start += item.header.find(inline).unwrap_or(0);
        parse_sequence(&[inline_item], diagnostics)
    };
    Some(StatementKind::Spawn { delay, body })
}

fn parse_var(item: &Item, diagnostics: &mut Vec<Diagnostic>) -> Option<StatementKind> {
    let header = item.header.trim();
    let assignment = header
        .find('=')
        .filter(|&at| !header[at + 1..].starts_with('='));
    let declaration = header[..assignment.unwrap_or(header.len())]
        .trim()
        .to_owned();
    let name = declaration
        .strip_prefix("var/")
        .or_else(|| declaration.strip_prefix("var "))
        .or_else(|| declaration.strip_prefix("var\t"))
        .map(str::trim);
    if name.is_none_or(str::is_empty) {
        diagnostics.push(Diagnostic {
            span: item.header_span,
            kind: DiagnosticKind::Statement,
            message: "missing local variable name".into(),
        });
        return None;
    }
    let value = if let Some(at) = assignment {
        let source = header[at + 1..].trim();
        let offset = item.header_span.start + item.header.find(source).unwrap_or(at + 1);
        Some(parse_expr(source, offset, diagnostics)?)
    } else {
        None
    };
    Some(StatementKind::Var { declaration, value })
}

fn parse_switch(item: &Item, diagnostics: &mut Vec<Diagnostic>) -> Option<StatementKind> {
    let selector = parse_control_condition(item, "switch", diagnostics)?;
    let mut cases = Vec::new();
    let mut else_branch = Vec::new();
    for (index, case) in item.children.iter().enumerate() {
        let header = case.header.trim();
        if starts_keyword(header, "else") {
            if index + 1 != item.children.len() {
                diagnostics.push(Diagnostic {
                    span: case.header_span,
                    kind: DiagnosticKind::Statement,
                    message: "switch else must be final".into(),
                });
            }
            let inline = header
                .strip_prefix("else")
                .unwrap()
                .trim()
                .trim_end_matches(';')
                .trim();
            else_branch = if inline.is_empty() {
                parse_sequence(&case.children, diagnostics)
            } else {
                let mut nested = case.clone();
                nested.header = inline.into();
                nested.header_span.start += case.header.find(inline).unwrap_or(0);
                parse_sequence(&[nested], diagnostics)
            };
            continue;
        }
        let clause = control_clause(case, "if", diagnostics)?;
        let base = case.header_span.start + case.header.find(clause).unwrap_or(0);
        let mut alternatives = Vec::new();
        for alternative in
            split_case_alternatives(clause.trim_end().strip_suffix(',').unwrap_or(clause))
        {
            let alternative = alternative.trim();
            let offset = base + clause.find(alternative).unwrap_or(0);
            if let Some((lower, upper)) = split_top_level_keyword(alternative, "to") {
                let lower = parse_expr(lower.trim(), offset, diagnostics)?;
                let upper = parse_expr(
                    upper.trim(),
                    offset + alternative.find(upper).unwrap_or(0),
                    diagnostics,
                )?;
                alternatives.push(SwitchAlternative::Range(lower, upper));
            } else {
                alternatives.push(SwitchAlternative::Exact(parse_expr(
                    alternative,
                    offset,
                    diagnostics,
                )?));
            }
        }
        if alternatives.is_empty() {
            diagnostics.push(Diagnostic {
                span: case.header_span,
                kind: DiagnosticKind::Statement,
                message: "empty switch case".into(),
            });
            return None;
        }
        cases.push(SwitchCase {
            alternatives,
            body: control_body(case, "if", diagnostics),
        });
    }
    Some(StatementKind::Switch {
        selector,
        cases,
        else_branch,
    })
}

fn split_top_level_keyword<'a>(source: &'a str, keyword: &str) -> Option<(&'a str, &'a str)> {
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

fn split_case_alternatives(source: &str) -> Vec<&str> {
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

fn parse_for(item: &Item, diagnostics: &mut Vec<Diagnostic>) -> Option<ForControl> {
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

fn control_body(item: &Item, keyword: &str, diagnostics: &mut Vec<Diagnostic>) -> Vec<Statement> {
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

fn parse_control_condition(
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

fn control_clause<'a>(
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

fn parse_expr(source: &str, offset: usize, diagnostics: &mut Vec<Diagnostic>) -> Option<Expr> {
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

fn starts_keyword(source: &str, keyword: &str) -> bool {
    source == keyword
        || source
            .strip_prefix(keyword)
            .is_some_and(|tail| tail.starts_with([' ', '\t', '(']))
}

fn is_assignment(op: &str) -> bool {
    matches!(
        op,
        "=" | "+=" | "-=" | "*=" | "/=" | "%=" | "|=" | "&=" | "^=" | "<<=" | ">>="
    )
}

fn unsupported(item: &Item) -> Statement {
    Statement {
        kind: StatementKind::Unsupported,
        span: item.span,
        header_span: item.header_span,
        raw_header: item.header.clone(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::parse;

    #[test]
    fn scoped_label_preserves_nested_body_and_targeted_control() {
        let source = "/proc/test(L)\n    if(L)\n        outer_loop:\n            for(var/x in L)\n                break outer_loop\n    if(L)\n        outer_loop:\n            for(var/x in L)\n                continue outer_loop\n";
        let ast = parse(source);
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let parsed = parse_proc_body(&ast.items[0]);
        assert!(parsed.diagnostics.is_empty(), "{:?}", parsed.diagnostics);
        assert_eq!(parsed.statements.len(), 2);
        for (index, control) in parsed.statements.iter().enumerate() {
            let StatementKind::If { then_branch, .. } = &control.kind else {
                panic!("expected if");
            };
            let StatementKind::Label {
                name,
                body: label_body,
            } = &then_branch[0].kind
            else {
                panic!("expected scoped label");
            };
            assert_eq!(name, "outer_loop");
            let StatementKind::For {
                body: loop_body, ..
            } = &label_body[0].kind
            else {
                panic!("expected nested for");
            };
            if index == 0 {
                assert!(
                    matches!(&loop_body[0].kind, StatementKind::BreakLabel(label) if label == "outer_loop")
                );
            } else {
                assert!(
                    matches!(&loop_body[0].kind, StatementKind::ContinueLabel(label) if label == "outer_loop")
                );
            }
        }
    }

    #[test]
    fn nested_control_and_absolute_spans() {
        let source = "/proc/test(L)\n    var/x = 0\n    for(var/i in L)\n        if(i)\n            x += i\n        else\n            helper()\n    while(x)\n        x = x - 1\n    return x\n";
        let ast = parse(source);
        let body = parse_proc_body(&ast.items[0]);
        assert!(body.diagnostics.is_empty(), "{:?}", body.diagnostics);
        assert_eq!(body.statements.len(), 4);
        let StatementKind::For {
            control: ForControl::Each { binding, iterable },
            body: loop_body,
        } = &body.statements[1].kind
        else {
            panic!("expected foreach")
        };
        assert_eq!(binding, "var/i");
        assert_eq!(&source[iterable.span.range()], "L");
        let StatementKind::If {
            then_branch,
            else_branch,
            ..
        } = &loop_body[0].kind
        else {
            panic!("expected if")
        };
        assert!(matches!(then_branch[0].kind, StatementKind::Assign { .. }));
        assert!(matches!(else_branch[0].kind, StatementKind::Call(_)));
        assert!(matches!(
            body.statements[2].kind,
            StatementKind::While { .. }
        ));
    }

    #[test]
    fn switch_string_labels_do_not_become_numeric_ranges() {
        let ast = parse("/proc/test(choice)\n    switch(choice)\n        if(\"Ready to Hatch\") return 1\n        if(\"Switch to STANDARD\", \"Switch to BROAD\") return 2\n        if(1 to 3) return 3\n");
        let body = parse_proc_body(&ast.items[0]);
        assert!(body.diagnostics.is_empty(), "{:?}", body.diagnostics);
        let StatementKind::Switch { cases, .. } = &body.statements[0].kind else {
            panic!("switch");
        };
        assert!(matches!(
            cases[0].alternatives[0],
            SwitchAlternative::Exact(_)
        ));
        assert_eq!(cases[1].alternatives.len(), 2);
        assert!(matches!(
            cases[2].alternatives[0],
            SwitchAlternative::Range(_, _)
        ));
    }

    #[test]
    fn parenthesized_return_and_throw_are_control_statements() {
        let ast = parse("/proc/test()\n    return(1 + 2)\n    throw(7)\n");
        let body = parse_proc_body(&ast.items[0]);
        assert!(body.diagnostics.is_empty(), "{:?}", body.diagnostics);
        assert!(matches!(
            body.statements[0].kind,
            StatementKind::Return(Some(_))
        ));
        assert!(matches!(body.statements[1].kind, StatementKind::Throw(_)));
    }

    #[test]
    fn inline_controls_and_native_comma_for() {
        let ast = parse("/proc/test(A)\n    if(!istype(A)) return\n    else return 1\n    for(A, A && !istype(A), A=A.loc);\n    while(A) A = A.loc\n");
        let body = parse_proc_body(&ast.items[0]);
        assert!(body.diagnostics.is_empty(), "{:?}", body.diagnostics);
        let StatementKind::If {
            then_branch,
            else_branch,
            ..
        } = &body.statements[0].kind
        else {
            panic!("if");
        };
        assert!(matches!(then_branch[0].kind, StatementKind::Return(None)));
        assert!(matches!(
            else_branch[0].kind,
            StatementKind::Return(Some(_))
        ));
        let StatementKind::For {
            control,
            body: loop_body,
        } = &body.statements[1].kind
        else {
            panic!("for");
        };
        assert!(matches!(control, ForControl::CStyle { .. }));
        assert!(loop_body.is_empty());
        let StatementKind::While {
            body: loop_body, ..
        } = &body.statements[2].kind
        else {
            panic!("while");
        };
        assert!(matches!(loop_body[0].kind, StatementKind::Assign { .. }));
    }

    #[test]
    fn pair_iteration_preserves_both_bindings_and_iterable() {
        let ast = parse("/proc/test(L)\n    for(var/I, V in L)\n        output(I, V)\n    for(var/key, value in alist(\"x\" = L))\n        output(key, value)\n    for(var/I, V in L) qdel(V)\n");
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let body = parse_proc_body(&ast.items[0]);
        assert!(body.diagnostics.is_empty(), "{:?}", body.diagnostics);
        assert!(
            matches!(&body.statements[0].kind, StatementKind::For { control: ForControl::Pair { key_binding, value_binding, .. }, .. } if key_binding == "var/I" && value_binding == "V")
        );
        assert!(
            matches!(&body.statements[1].kind, StatementKind::For { control: ForControl::Pair { key_binding, value_binding, .. }, .. } if key_binding == "var/key" && value_binding == "value")
        );
        assert!(
            matches!(&body.statements[2].kind, StatementKind::For { control: ForControl::Pair { .. }, body } if body.len() == 1)
        );
    }

    #[test]
    fn inline_return_if_conditions_from_game_parse_cleanly() {
        let ast = parse("/proc/test(user)\n    if (GLOB.prison_shuttle_moving_to_station || GLOB.prison_shuttle_moving_to_prison) return\n    if (istype(user, /mob/observer)) return\n    if(user.stat || !Adjacent(user)) return\n");
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let body = parse_proc_body(&ast.items[0]);
        assert!(body.diagnostics.is_empty(), "{:?}", body.diagnostics);
        assert!(body.statements.iter().all(|statement| matches!(&statement.kind, StatementKind::If { then_branch, .. } if matches!(&then_branch[0].kind, StatementKind::Return(None)))));
    }

    #[test]
    fn bare_var_declarations_retain_spelling_and_values() {
        let ast = parse("/proc/test()\n    var amount = 1\n    var\tname = \"Ada\"\n    var/typed/item = null\n");
        let body = parse_proc_body(&ast.items[0]);
        assert!(body.diagnostics.is_empty(), "{:?}", body.diagnostics);
        let declarations = body
            .statements
            .iter()
            .map(|statement| match &statement.kind {
                StatementKind::Var { declaration, value } => {
                    assert!(value.is_some());
                    declaration.as_str()
                }
                other => panic!("expected var declaration, got {other:?}"),
            })
            .collect::<Vec<_>>();
        assert_eq!(declarations, ["var amount", "var\tname", "var/typed/item"]);
    }

    #[test]
    fn spawn_blocks_and_inline_body_are_structured() {
        let source = "/proc/test()\n    spawn(5)\n        tick()\n    spawn() tick()\n    spawn\n        tick()\n";
        let ast = parse(source);
        let body = parse_proc_body(&ast.items[0]);
        assert!(body.diagnostics.is_empty(), "{:?}", body.diagnostics);
        assert_eq!(body.statements.len(), 3);
        let StatementKind::Spawn {
            delay: Some(delay),
            body: first_body,
        } = &body.statements[0].kind
        else {
            panic!("expected timed spawn")
        };
        assert_eq!(&source[delay.span.range()], "5");
        assert!(matches!(first_body[0].kind, StatementKind::Call(_)));
        for statement in &body.statements[1..] {
            let StatementKind::Spawn { delay, body } = &statement.kind else {
                panic!("expected spawn")
            };
            assert!(delay.is_none());
            assert_eq!(body.len(), 1);
            assert!(matches!(body[0].kind, StatementKind::Call(_)));
        }
    }

    #[test]
    fn do_while_pairs_following_condition() {
        let source = "/proc/test()\n    do\n        tick()\n    while(ready())\n    return 1\n";
        let ast = parse(source);
        let body = parse_proc_body(&ast.items[0]);
        assert!(body.diagnostics.is_empty(), "{:?}", body.diagnostics);
        assert_eq!(body.statements.len(), 2);
        let StatementKind::DoWhile {
            body: loop_body,
            condition,
        } = &body.statements[0].kind
        else {
            panic!("expected do-while")
        };
        assert!(matches!(loop_body[0].kind, StatementKind::Call(_)));
        assert_eq!(&source[condition.span.range()], "ready()");
    }

    #[test]
    fn proc_set_attributes_and_src_in_are_typed() {
        let source = "/obj/proc/test()\n    set waitfor = FALSE\n    set name = \"Look in bag\"\n    set src in view(1)\n    return\n";
        let ast = parse(source);
        let body = parse_proc_body(&ast.items[0]);
        assert!(body.diagnostics.is_empty(), "{:?}", body.diagnostics);
        assert_eq!(body.statements.len(), 4);
        let attributes = body.statements[..3]
            .iter()
            .map(|statement| match &statement.kind {
                StatementKind::Set {
                    attribute,
                    relation,
                    value,
                } => {
                    assert!(!source[value.span.range()].is_empty());
                    (attribute.as_str(), relation.as_str())
                }
                other => panic!("expected set declaration, got {other:?}"),
            })
            .collect::<Vec<_>>();
        assert_eq!(attributes, [("waitfor", "="), ("name", "="), ("src", "in")]);
    }

    #[test]
    fn switch_and_ternary_return_are_structured() {
        let ast = parse("/proc/test()\n    switch(x)\n        if(1)\n            return 1\n    return x ? 1 : 2\n");
        let body = parse_proc_body(&ast.items[0]);
        assert_eq!(body.statements.len(), 2);
        assert!(matches!(
            body.statements[0].kind,
            StatementKind::Switch { .. }
        ));
        assert!(matches!(
            body.statements[1].kind,
            StatementKind::Return(Some(_))
        ));
        assert!(body.diagnostics.is_empty());
    }

    #[test]
    fn else_if_chain_is_nested_without_orphans() {
        let ast = parse("/proc/test(x)\n    if(x == 1)\n        return 1\n    else if(x == 2)\n        return 2\n    else\n        return 3\n");
        let body = parse_proc_body(&ast.items[0]);
        assert!(body.diagnostics.is_empty(), "{:?}", body.diagnostics);
        assert_eq!(body.statements.len(), 1);
        let StatementKind::If { else_branch, .. } = &body.statements[0].kind else {
            panic!("expected if")
        };
        let StatementKind::If { else_branch, .. } = &else_branch[0].kind else {
            panic!("expected else if")
        };
        assert!(matches!(else_branch[0].kind, StatementKind::Return(_)));
    }

    #[test]
    fn native_common_operations_fixture_has_structured_bodies() {
        let source = include_str!("../../../fixtures/lowering/common_ops.dm");
        let ast = parse(source);
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        assert_eq!(ast.items.len(), 5);
        for proc in &ast.items {
            let body = parse_proc_body(proc);
            assert!(
                body.diagnostics.is_empty(),
                "{}: {:?}",
                proc.header,
                body.diagnostics
            );
            assert_eq!(body.statements.len(), 1);
            assert!(!matches!(
                body.statements[0].kind,
                StatementKind::Unsupported
            ));
        }
    }

    #[test]
    fn range_for_with_step_is_structured() {
        let source = "/proc/count()\n    for(var/i = 1 to 10 step 2)\n        output(i)\n";
        let ast = parse(source);
        let body = parse_proc_body(&ast.items[0]);
        assert!(body.diagnostics.is_empty(), "{:?}", body.diagnostics);
        let StatementKind::For {
            control:
                ForControl::Range {
                    binding,
                    start,
                    end,
                    step,
                },
            body: loop_body,
        } = &body.statements[0].kind
        else {
            panic!("expected range for")
        };
        assert_eq!(binding, "var/i");
        assert_eq!(&source[start.span.range()], "1");
        assert_eq!(&source[end.span.range()], "10");
        assert_eq!(&source[step.as_ref().unwrap().span.range()], "2");
        assert!(matches!(loop_body[0].kind, StatementKind::Call(_)));
    }

    #[test]
    fn c_style_for_is_structured() {
        let ast = parse("/proc/count(n)\n    for(var/i = 0; i < n; i = i + 1)\n        return i\n");
        let body = parse_proc_body(&ast.items[0]);
        assert!(body.diagnostics.is_empty(), "{:?}", body.diagnostics);
        assert!(matches!(
            body.statements[0].kind,
            StatementKind::For {
                control: ForControl::CStyle { .. },
                ..
            }
        ));
    }

    #[test]
    fn in_range_for_used_by_game_code_is_structured() {
        let ast = parse("/proc/count(n)\n    for(var/i in 1 to n)\n        return i\n");
        let body = parse_proc_body(&ast.items[0]);
        assert!(body.diagnostics.is_empty(), "{:?}", body.diagnostics);
        assert!(matches!(
            body.statements[0].kind,
            StatementKind::For {
                control: ForControl::Range { .. },
                ..
            }
        ));
    }

    #[test]
    fn try_catch_and_throw_are_structured() {
        let ast = parse("/proc/guard()\n    try\n        throw \"bad\"\n    catch(var/exception/E)\n        return E\n");
        let body = parse_proc_body(&ast.items[0]);
        assert!(body.diagnostics.is_empty());
        let StatementKind::Try {
            body: protected,
            catch_binding,
            catch_body,
        } = &body.statements[0].kind
        else {
            panic!("expected try")
        };
        assert_eq!(catch_binding.as_deref(), Some("var/exception/E"));
        assert!(matches!(protected[0].kind, StatementKind::Throw(_)));
        assert!(matches!(catch_body[0].kind, StatementKind::Return(Some(_))));
    }
}

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
    if crate::return_has_block(header, !item.children.is_empty()) {
        diagnostics.push(Diagnostic {
            span: item.header_span,
            kind: DiagnosticKind::Unsupported,
            message: crate::RETURN_BLOCK_UNSUPPORTED.into(),
        });
        return unsupported(item);
    }
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

#[path = "statement_controls.rs"]
mod statement_controls;
use statement_controls::*;

#[cfg(test)]
mod tests {
    include!("statements_tests_1.rs");
}

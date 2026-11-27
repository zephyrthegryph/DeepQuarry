//! Typed bodies kept from the previous model of the process (the daemon's last request, a `gen`'s previous round), so a model of the
//! next revision parses only the bodies whose text changed.
//!
//! A body's statements are a function of its expanded text (`dm_syntax::parse_proc_at_span` over the item): its spans are that text's
//! offsets plus where it starts. A body is kept under a digest of its text from the start of its first line (the indentation the
//! parser reads included) to its end; the next model takes the kept statements as they are when the body starts at the same offset,
//! and a copy with every span moved by the difference when it does not. `DQ_MODEL_BODY_VERIFY=1` parses every reused body again
//! and reports any that differ (a proof the reuse is exact; off in normal runs). `DQ_MODEL_BODY_REUSE=0` turns the reuse off.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use dm_syntax::{Expr, ExprKind, ForControl, ForInitializer, Span, Statement, StatementKind, SwitchAlternative};

/// A body's statements, shared between the models that read the same text: as the front end parsed them, or a moved copy.
#[derive(Clone)]
pub(crate) enum Body {
    Parsed(Arc<dm_tree::frontend::StatementBody>),
    Moved(Arc<Vec<Statement>>),
}

impl Body {
    pub(crate) fn statements(&self) -> &[Statement] {
        match self {
            Body::Parsed(b) => &b.parsed().statements,
            Body::Moved(v) => v,
        }
    }
}

/// The kept bodies: digest -> (statements, the offset the body started at).
static KEPT: Mutex<Option<HashMap<u128, (Body, usize)>>> = Mutex::new(None);

pub(crate) fn enabled() -> bool {
    !matches!(dq_hostio::var("DQ_MODEL_BODY_REUSE").as_deref(), Ok("0") | Ok("off"))
}

pub(crate) fn verify() -> bool {
    matches!(dq_hostio::var("DQ_MODEL_BODY_VERIFY").as_deref(), Ok("1"))
}

/// The digest a body is kept under: its text from the start of its first line to its end (`start..end` in `text`).
pub(crate) fn key(text: &str, start: usize, end: usize) -> Option<(u128, usize)> {
    let line = text.get(..start)?.rfind('\n').map_or(0, |i| i + 1);
    let body = text.get(line..end)?;
    let mut h = blake3::Hasher::new();
    h.update(&((start - line) as u64).to_le_bytes());
    h.update(body.as_bytes());
    Some((u128::from_le_bytes(h.finalize().as_bytes()[..16].try_into().unwrap()), start))
}

/// The kept statements for `key`, moved to `start` when the body moved.
pub(crate) fn take(kept: &HashMap<u128, (Body, usize)>, key: u128, start: usize) -> Option<Body> {
    let (body, was) = kept.get(&key)?;
    if *was == start {
        return Some(body.clone());
    }
    let delta = start as isize - *was as isize;
    let mut moved: Vec<Statement> = body.statements().to_vec();
    shift_statements(&mut moved, delta);
    Some(Body::Moved(Arc::new(moved)))
}

/// The previous model's bodies (empty when none was kept or the reuse is off).
pub(crate) fn kept() -> HashMap<u128, (Body, usize)> {
    if !enabled() {
        return HashMap::new();
    }
    KEPT.lock().unwrap_or_else(|e| e.into_inner()).take().unwrap_or_default()
}

/// Keeps this model's bodies for the next one (only the latest model's: the store never grows past one revision).
pub(crate) fn keep(bodies: HashMap<u128, (Body, usize)>) {
    if enabled() {
        *KEPT.lock().unwrap_or_else(|e| e.into_inner()) = Some(bodies);
    }
}

fn shift_span(span: &mut Span, delta: isize) {
    span.start = (span.start as isize + delta) as usize;
    span.end = (span.end as isize + delta) as usize;
}

pub(crate) fn shift_statements(stmts: &mut [Statement], delta: isize) {
    for s in stmts {
        shift_statement(s, delta);
    }
}

fn shift_statement(s: &mut Statement, delta: isize) {
    shift_span(&mut s.span, delta);
    shift_span(&mut s.header_span, delta);
    match &mut s.kind {
        StatementKind::If { condition, then_branch, else_branch, has_else: _ } => {
            shift_expr(condition, delta);
            shift_statements(then_branch, delta);
            shift_statements(else_branch, delta);
        }
        StatementKind::While { condition, body } | StatementKind::DoWhile { body, condition } => {
            shift_expr(condition, delta);
            shift_statements(body, delta);
        }
        StatementKind::Spawn { delay, body } => {
            if let Some(d) = delay {
                shift_expr(d, delta);
            }
            shift_statements(body, delta);
        }
        StatementKind::Set { attribute: _, relation: _, value } => shift_expr(value, delta),
        StatementKind::For { control, body } => {
            match control {
                ForControl::All { declaration: _ } => {}
                ForControl::Each { binding: _, iterable } => shift_expr(iterable, delta),
                ForControl::Pair { key_binding: _, value_binding: _, iterable } => shift_expr(iterable, delta),
                ForControl::Range { binding: _, start, end, step } => {
                    shift_expr(start, delta);
                    shift_expr(end, delta);
                    if let Some(s) = step {
                        shift_expr(s, delta);
                    }
                }
                ForControl::CStyle { initializer, condition, step } => {
                    match initializer {
                        Some(ForInitializer::Declare { declaration: _, value }) => {
                            if let Some(v) = value {
                                shift_expr(v, delta);
                            }
                        }
                        Some(ForInitializer::Expr(e)) => shift_expr(e, delta),
                        None => {}
                    }
                    if let Some(c) = condition {
                        shift_expr(c, delta);
                    }
                    if let Some(s) = step {
                        shift_expr(s, delta);
                    }
                }
            }
            shift_statements(body, delta);
        }
        StatementKind::Switch { selector, cases, else_branch } => {
            shift_expr(selector, delta);
            for case in cases {
                for alt in &mut case.alternatives {
                    match alt {
                        SwitchAlternative::Exact(e) => shift_expr(e, delta),
                        SwitchAlternative::Range(a, b) => {
                            shift_expr(a, delta);
                            shift_expr(b, delta);
                        }
                    }
                }
                shift_statements(&mut case.body, delta);
            }
            shift_statements(else_branch, delta);
        }
        StatementKind::Try { body, catch_binding: _, catch_header_span, catch_body } => {
            shift_statements(body, delta);
            shift_span(catch_header_span, delta);
            shift_statements(catch_body, delta);
        }
        StatementKind::Throw(e) | StatementKind::Call(e) | StatementKind::Expression(e) => shift_expr(e, delta),
        StatementKind::Label { name: _, body } => shift_statements(body, delta),
        StatementKind::Return(e) => {
            if let Some(e) = e {
                shift_expr(e, delta);
            }
        }
        StatementKind::Var { declaration: _, value } => {
            if let Some(v) = value {
                shift_expr(v, delta);
            }
        }
        StatementKind::Assign { target, op: _, value } => {
            shift_expr(target, delta);
            shift_expr(value, delta);
        }
        StatementKind::Goto(_)
        | StatementKind::Break
        | StatementKind::BreakLabel(_)
        | StatementKind::Continue
        | StatementKind::ContinueLabel(_)
        | StatementKind::Unsupported => {}
    }
}

fn shift_expr(e: &mut Expr, delta: isize) {
    shift_span(&mut e.span, delta);
    match &mut e.kind {
        ExprKind::Ident(_) | ExprKind::Literal(_) | ExprKind::TypePath(_) => {}
        ExprKind::Unary { op: _, value } | ExprKind::Group(value) | ExprKind::TypeFilter { value, types: _ } => shift_expr(value, delta),
        ExprKind::Binary { op: _, lhs, rhs } => {
            shift_expr(lhs, delta);
            shift_expr(rhs, delta);
        }
        ExprKind::Conditional { condition, then_value, else_value } => {
            shift_expr(condition, delta);
            shift_expr(then_value, delta);
            shift_expr(else_value, delta);
        }
        ExprKind::Call { callee, args } => {
            shift_expr(callee, delta);
            for a in args {
                shift_expr(a, delta);
            }
        }
        ExprKind::Member { object, selector: _, via_colon: _ }
        | ExprKind::SafeMember { object, selector: _, via_colon: _ }
        | ExprKind::StaticMember { object, selector: _ } => shift_expr(object, delta),
        ExprKind::ObjectInitializer { object, fields } => {
            shift_expr(object, delta);
            for (_, v) in fields {
                shift_expr(v, delta);
            }
        }
        ExprKind::Index { object, index } | ExprKind::SafeIndex { object, index } => {
            shift_expr(object, delta);
            shift_expr(index, delta);
        }
    }
}

/// Var initializers kept from the previous model: digest of the declaration item's text -> (the parsed value, where it starts in the
/// item). The value is parsed from the item's own text, so it needs no moving.
static KEPT_VALUES: Mutex<Option<HashMap<u128, (Arc<Expr>, usize)>>> = Mutex::new(None);

pub(crate) fn text_key(text: &str) -> u128 {
    u128::from_le_bytes(blake3::hash(text.as_bytes()).as_bytes()[..16].try_into().unwrap())
}

pub(crate) fn kept_values() -> HashMap<u128, (Arc<Expr>, usize)> {
    if !enabled() {
        return HashMap::new();
    }
    KEPT_VALUES.lock().unwrap_or_else(|e| e.into_inner()).take().unwrap_or_default()
}

pub(crate) fn keep_values(values: HashMap<u128, (Arc<Expr>, usize)>) {
    if enabled() {
        *KEPT_VALUES.lock().unwrap_or_else(|e| e.into_inner()) = Some(values);
    }
}

//! `switch(rand(L, H))` whose cases miss the range or leave part of it uncovered (SpacemanDMM DreamChecker's
//! `switch_rand_range.rs`). A case value is evaluated as SpacemanDMM's `simple_evaluate` does for the numbers such cases use:
//! number literals, parentheses, unary minus and arithmetic.
use dm::{DMError, Location, Severity};
use dm_syntax::{Expr, ExprKind, SwitchAlternative, SwitchCase};

use super::view::{literal, Term};
use super::walk::Walk;

/// The number `e` evaluates to, without any type tree.
fn number(e: &Expr) -> Option<f32> {
    match &e.kind {
        ExprKind::Literal(text) => match literal(text) {
            Term::Int(n) => Some(n as f32),
            Term::Float(n) => Some(n),
            _ => None,
        },
        ExprKind::Group(inner) => number(inner),
        ExprKind::Unary { op, value } if op == "-" => number(value).map(|v| -v),
        ExprKind::Binary { op, lhs, rhs } => {
            let (a, b) = (number(lhs)?, number(rhs)?);
            Some(match op.as_str() {
                "+" => a + b,
                "-" => a - b,
                "*" => a * b,
                "/" => a / b,
                "%" => (a as i32 % b as i32) as f32,
                _ => return None,
            })
        }
        _ => None,
    }
}

fn rand_range(walk: &mut Walk<'_, '_>, input: &Expr) -> Option<(i32, i32)> {
    let Term::Call { name: "rand", args } = (match walk.reader.shape(input) {
        super::view::Shape::Base(b) if b.follows.is_empty() => b.term,
        _ => return None,
    }) else {
        return None;
    };
    let (min, max) = match args.as_slice() {
        [min, max] => (number(min)?, number(max)?),
        [max] => (0., number(max)?),
        _ => return None,
    };
    Some((min.ceil() as i32, max.floor() as i32))
}

pub fn check(walk: &mut Walk<'_, '_>, input: &Expr, cases: &[SwitchCase], case_locs: &[Location], has_default: bool, location: Location) {
    let Some((rand_start, rand_end)) = rand_range(walk, input) else { return };
    let mut ranges = Vec::with_capacity(cases.len());
    for (case, &case_loc) in cases.iter().zip(case_locs) {
        for alt in &case.alternatives {
            let range = match alt {
                SwitchAlternative::Exact(v) => number(v).map(|v| (v, v)),
                SwitchAlternative::Range(a, b) => number(a).zip(number(b)),
            };
            if let Some((start, end)) = range {
                let (start, end) = (start.ceil() as i32, end.floor() as i32);
                if start <= rand_end && end >= rand_start {
                    ranges.push((start, end));
                } else {
                    walk.facts.diagnostics.push(
                        DMError::new(case_loc, format!("Case range '{start} to {end}' will never trigger as it is outside the rand() range {rand_start} to {rand_end}"))
                            .with_component(dm::Component::DreamChecker)
                            .set_severity(Severity::Warning),
                    );
                }
            }
        }
    }
    if has_default {
        return;
    }
    ranges.sort_by(|a, b| a.0.cmp(&b.0));
    let mut first_uncovered = rand_start;
    for (start, end) in ranges.iter() {
        if *start > first_uncovered {
            break;
        }
        first_uncovered = std::cmp::max(first_uncovered, end + 1);
    }
    if first_uncovered <= rand_end {
        walk.facts.diagnostics.push(
            DMError::new(location, format!("Switch branches on rand() with range {rand_start} to {rand_end} but no case branch triggers for {first_uncovered}"))
                .with_component(dm::Component::DreamChecker)
                .set_severity(Severity::Warning),
        );
    }
}

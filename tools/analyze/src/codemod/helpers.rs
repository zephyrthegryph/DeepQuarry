//! Pieces the codemods share.

use super::scan::{Arg, Span};
use super::{Ctx, Edit, Outcome};

/// An argument written `name = value`.
pub fn any_named(args: &[Arg]) -> bool {
    args.iter().any(|a| a.named.is_some())
}

/// An argument that spreads a list into the argument list (`arglist(...)`).
pub fn is_arglist(cx: &Ctx, i: usize) -> bool {
    cx.arg_clean(i).trim_start().starts_with("arglist(")
}

/// The text between two spans of the call, comments included.
pub fn gap<'a>(cx: &'a Ctx, a: Span, b: Span) -> &'a str {
    &cx.text[a.end..b.start]
}

pub fn has_comment(s: &str) -> bool {
    s.contains("//") || s.contains("/*")
}

/// A call that only changes its name: `old(a, b, c)` -> `new(a, b, c)`, valid when it has exactly `arity`
/// positional arguments. Fewer is malformed (`too_few_args`); more, or any named argument, is a form the
/// new proc does not take (`extra_args`), left for a human.
pub fn rename_exact(cx: &Ctx, new: &str, arity: usize) -> Outcome {
    let n = cx.node.args.len();
    if n < arity {
        return Outcome::Residue("too_few_args", format!("{} takes {} arguments, the call has {}", cx.callee, arity, n));
    }
    if n > arity || any_named(&cx.node.args) {
        return Outcome::Residue("extra_args", format!("{} is called with arguments {} does not take", cx.callee, new));
    }
    Outcome::edits(vec![Edit::replace(cx.node.name, new)])
}

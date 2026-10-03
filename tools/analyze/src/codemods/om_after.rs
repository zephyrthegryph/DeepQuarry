//! `om_after(E, delay, proc, args...)` and `after_slot(E, "slot", delay, proc, args...)` to `after()`
//! (doc/rewrite/api_mapping.tsv, row om_after and step A1).
//!
//! `after(owner, delay, handler, key = null, clock = CLOCK_OWN, list/with = null)` is on master
//! (code/datums/capabilities/timed.dm) and both old procs are one-line wrappers over the same `rx_after()`
//! with the same defaults, so the conversion changes the spelling and nothing else:
//!
//! ```text
//! om_after(E, 5 SECONDS, PROC_REF(x), a, b)        ->  after(E, 5 SECONDS, PROC_REF(x), with = list(a, b))
//! after_slot(E, "slot", 5 SECONDS, PROC_REF(x), a) ->  after(E, 5 SECONDS, PROC_REF(x), key = "slot", with = list(a))
//! ```
//!
//! `om_after` returns the timer id and so does `after`. `after_slot` returns `!!id`; the call is converted
//! only as a statement (its value unused), else it is `value_used` residue.
//!
//! The doc's later form, `after(owner, delay, then(PROC_REF(x)))` with an `x(datum/act/A)` handler, is not on
//! master; this converts to the form that is. The "choose" note (hold(lasts =), every(), COOLDOWN_*) is a
//! per-site judgement the rewrite does not make: the site becomes an `after()` and keeps its behaviour.

use crate::codemod::helpers::{any_named, gap, has_comment, is_arglist};
use crate::codemod::scan::Span;
use crate::codemod::{Codemod, Ctx, Edit, KeyUse, Outcome, Rewrite};

pub struct OmAfter;

impl Codemod for OmAfter {
    fn name(&self) -> &'static str {
        "om_after"
    }
    fn about(&self) -> &'static str {
        "om_after(E, d, proc, args...), after_slot(E, slot, d, proc, args...) -> after(E, d, proc, [key = slot,] [with = list(args...)])"
    }
    fn callees(&self) -> &'static [&'static str] {
        &["om_after", "after_slot"]
    }
    fn reasons(&self) -> &'static [(&'static str, &'static str)] {
        &[
            ("too_few_args", "fewer arguments than (E, delay, proc): malformed, fix the call"),
            ("named_arg", "a named argument among the call's arguments: the legacy varargs took them positionally, write the with = list(...) by hand"),
            ("arglist", "an arglist(...) spread as the handler's arguments: pass the list as with = L by hand"),
            ("value_used", "after_slot's result is used (it returned !!id, after() returns the id): convert by hand"),
            ("comment_in_moved_span", "a comment sits between the arguments being reordered: convert by hand"),
        ]
    }

    fn rewrite(&self, cx: &Ctx) -> Outcome {
        let args = &cx.node.args;
        let slot = cx.callee == "after_slot";
        let fixed = if slot { 4 } else { 3 };
        if args.len() < fixed {
            return Outcome::Residue("too_few_args", format!("{} needs {} arguments", cx.callee, fixed));
        }
        if any_named(args) {
            return Outcome::Residue("named_arg", String::new());
        }
        if (fixed..args.len()).any(|i| is_arglist(cx, i)) {
            return Outcome::Residue("arglist", String::new());
        }
        if slot && !cx.stmt_level {
            return Outcome::Residue("value_used", String::new());
        }
        let rest = &args[fixed..];
        let mut edits = vec![Edit::replace(cx.node.name, "after")];
        let mut keys = Vec::new();
        if slot {
            // The slot argument moves to `key =` after the handler.
            if has_comment(gap(cx, args[1].span, args[2].span)) {
                return Outcome::Residue("comment_in_moved_span", String::new());
            }
            let key_text = cx.arg_text(1).to_string();
            edits.push(Edit::delete(Span { start: args[1].span.start, end: args[2].span.start }));
            edits.push(Edit::insert(args[3].span.end, format!(", key = {}", key_text)));
            let owner = if cx.arg_clean(0) == "src" { cx.owner.to_string() } else { cx.arg_text(0).to_string() };
            keys.push(KeyUse { owner, key: key_text, origin: cx.origin(), handler: cx.arg_text(3).to_string(), synthesized: false });
        }
        if let (Some(first), Some(last)) = (rest.first(), rest.last()) {
            edits.push(Edit::insert(first.span.start, "with = list("));
            edits.push(Edit::insert(last.span.end, ")"));
        }
        Outcome::Rewrite(Rewrite { edits, keys, needs: Vec::new() })
    }
}

pub fn register(reg: &mut Vec<Box<dyn Codemod>>) {
    reg.push(Box::new(OmAfter));
}

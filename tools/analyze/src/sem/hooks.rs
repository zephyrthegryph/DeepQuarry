//! Handler discovery: the procs a declaration names.
//!
//! "Every proc the engine calls to run a part or a trigger is `x(datum/act/A)`: effects,
//! requirements, conditions, hook handlers, every() and sequence work, outputs, then(),
//! because = PROC_REF, CAP_PROC" (doc/rewrite/final_api.html section 7). A declaration is a marker
//! (`CAPABILITIES(T, ...)`, `CAPABILITY_DEF/TYPE`, `STAT`, and the entry procs a block names); a hook form inside it
//! (`needs(...)`, `when(...)`, `contributes(...)`, `every(...)`, `then(...)`, ...) takes handlers as
//! `PROC_REF(x)`, `TYPE_PROC_REF(/type, x)` or `CAP_PROC(x)`. The hook form decides which context
//! type the handler is called with, and so which fields it may read (section 8, "Contexts").

use super::decls::{matching_paren, split_args, Decls, Marker};

/// The five context types of section 8.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum Ctx {
    /// The context of a world action's own hooks (instead, adjusts): its typed act, which carries the action's fields.
    Action,
    Eval,
    Op,
    Timer,
    Notice,
    Request,
}

impl Ctx {
    pub fn type_path(&self) -> &'static str {
        match self {
            Ctx::Eval => "/datum/act/eval",
            Ctx::Op => "/datum/act/op",
            Ctx::Timer => "/datum/act/timer",
            Ctx::Notice => "/datum/act/notice",
            Ctx::Action => "/datum/act/action",
            Ctx::Request => "/datum/act/request",
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum Role {
    Condition,
    Requirement,
    Effect,
    Output,
    Contribution,
    Reason,
    Work,
    Reaction,
}

impl Role {
    /// Pure roles: evaluated with the no-write, no-publish, no-message guard.
    pub fn pure(&self) -> bool {
        matches!(self, Role::Condition | Role::Requirement | Role::Output | Role::Contribution | Role::Reason)
    }

    /// Roles that answer TRUE/FALSE (a requirement's reason lives beside it).
    pub fn boolean(&self) -> bool {
        matches!(self, Role::Condition | Role::Requirement)
    }

    /// Roles whose result feeds the dependency graph (what they read subscribes).
    pub fn reads_covered(&self) -> bool {
        matches!(self, Role::Condition | Role::Requirement | Role::Output | Role::Contribution)
    }
}

pub struct HookForm {
    pub kw: &'static str,
    pub ctx: Ctx,
    pub role: Role,
}

/// Hook forms the analysis knows. A requirement runs in the op's context (it has an actor, no dt);
/// a condition or contribution runs in the eval context (a dt for outputs, no actor).
pub const HOOK_FORMS: &[HookForm] = &[
    HookForm { kw: "needs", ctx: Ctx::Op, role: Role::Requirement },
    HookForm { kw: "req", ctx: Ctx::Op, role: Role::Requirement },
    HookForm { kw: "when", ctx: Ctx::Eval, role: Role::Condition },
    HookForm { kw: "contributes", ctx: Ctx::Eval, role: Role::Contribution },
    HookForm { kw: "contributes_to", ctx: Ctx::Eval, role: Role::Contribution },
    HookForm { kw: "outputs", ctx: Ctx::Eval, role: Role::Output },
    HookForm { kw: "look_layer", ctx: Ctx::Eval, role: Role::Condition },
    HookForm { kw: "then", ctx: Ctx::Op, role: Role::Effect },
    HookForm { kw: "because", ctx: Ctx::Op, role: Role::Reason },
    // `asks(..., repeats = PROC_REF(x))`: asked with the op's context after each answer (pending_op request_done)
    HookForm { kw: "repeats", ctx: Ctx::Op, role: Role::Condition },
    // `asks(..., answerer = PROC_REF(x))`: the mob the question goes to, asked with the op's context when the question opens
    HookForm { kw: "answerer", ctx: Ctx::Op, role: Role::Work },
    HookForm { kw: "every", ctx: Ctx::Timer, role: Role::Work },
    HookForm { kw: "after_init", ctx: Ctx::Timer, role: Role::Work },
    HookForm { kw: "after", ctx: Ctx::Timer, role: Role::Work },
    HookForm { kw: "delayed", ctx: Ctx::Timer, role: Role::Work },
    HookForm { kw: "instead", ctx: Ctx::Action, role: Role::Effect },
    HookForm { kw: "adjusts", ctx: Ctx::Action, role: Role::Contribution },
    HookForm { kw: "on_notice", ctx: Ctx::Notice, role: Role::Reaction },
    HookForm { kw: "on_op", ctx: Ctx::Notice, role: Role::Reaction },
    HookForm { kw: "on_change", ctx: Ctx::Notice, role: Role::Reaction },
    // a computed() field of an asks() is called with the op's context when the question opens (op_request_fields())
    HookForm { kw: "computed", ctx: Ctx::Op, role: Role::Work },
    HookForm { kw: "asks", ctx: Ctx::Request, role: Role::Work },
    HookForm { kw: "request", ctx: Ctx::Request, role: Role::Work },
];

/// A proc a declaration names as a handler.
#[derive(Clone, Debug)]
pub struct HandlerRef {
    /// The type the handler runs on (the declaring type of `CAPABILITIES(T, ...)`); "" when the
    /// holder is not known from the declaration.
    pub owner: String,
    /// `CAP_PROC(x)`: the proc is on the capability datum, not the holder.
    pub cap_proc: bool,
    /// The capability datum type for `CAP_PROC` (`CAPABILITY_TYPE(name, CAP_X, /datum/capability/x)`).
    pub cap_type: String,
    pub proc: String,
    pub form: &'static str,
    pub ctx: Ctx,
    pub role: Role,
    pub rel: String,
    pub line: u32,
    /// The notice type of the enclosing `on_notice(/datum/notice/x, ...)` (`/datum/notice/op_done` for `on_op`), whose typed fields the handler may read.
    pub notice: String,
    /// For a `then(...)` inside an `op(...)` that has a `ui_act(...)` or `topic(...)` binding: the names of its `arg(...)`s, in order. The
    /// handler of such an op is x(datum/act/A, args...): the declared args arrive as typed parameters after A (section 9, "The one signature").
    pub ui_args: Option<Vec<String>>,
}

fn is_word(b: u8) -> bool {
    b.is_ascii_alphanumeric() || b == b'_'
}

/// `(kw index, start of args, end of args)` for each hook-form call in `body`.
fn hook_ranges(body: &str) -> Vec<(usize, usize, usize)> {
    let b = body.as_bytes();
    let mut out = Vec::new();
    let mut i = 0;
    let mut in_str = false;
    while i < b.len() {
        let c = b[i];
        if c == b'"' {
            in_str = !in_str;
            i += 1;
            continue;
        }
        if in_str || !(c.is_ascii_alphabetic() || c == b'_') {
            i += 1;
            continue;
        }
        let start = i;
        while i < b.len() && is_word(b[i]) {
            i += 1;
        }
        let word = &body[start..i];
        let prev_ok = start == 0 || !(is_word(b[start - 1]) || b[start - 1] == b'.');
        if prev_ok {
            // `because = PROC_REF(x)` is a named argument, not a call.
            if word == "because" || word == "when" || word == "repeats" || word == "answerer" {
                let rest = body[i..].trim_start();
                if rest.starts_with('=') && !rest.starts_with("==") {
                    out.push((HOOK_FORMS.iter().position(|f| f.kw == word).unwrap(), i, i));
                    continue;
                }
            }
            if let Some(idx) = HOOK_FORMS.iter().position(|f| f.kw == word) {
                let rest = &body[i..];
                let skip = rest.len() - rest.trim_start().len();
                if rest.trim_start().starts_with('(') {
                    let open = i + skip;
                    if let Some(close) = matching_paren(body, open) {
                        out.push((idx, open + 1, close));
                    }
                }
            }
        }
    }
    out
}

/// Every handler a declaration marker names.
pub fn discover(decls: &Decls) -> Vec<HandlerRef> {
    let mut out = Vec::new();
    for m in &decls.markers {
        if !matches!(m.name.as_str(), "CAPABILITIES" | "CAPABILITY_DEF" | "CAPABILITY_TYPE" | "STAT" | crate::sem::decls::ENTRY_PROC) {
            continue;
        }
        marker_handlers(m, &mut out);
    }
    out
}

fn marker_handlers(m: &Marker, out: &mut Vec<HandlerRef>) {
    let (owner, cap_type) = match m.name.as_str() {
        "CAPABILITIES" => (m.args.first().cloned().unwrap_or_default(), String::new()),
        "STAT" => (m.args.first().cloned().unwrap_or_default(), String::new()),
        "CAPABILITY_TYPE" => (holder_arg(m), m.args.get(2).cloned().unwrap_or_default()),
        "CAPABILITY_DEF" => (holder_arg(m), String::new()),
        _ => (String::new(), String::new()),
    };
    let body = &m.body;
    let ranges = hook_ranges(body);
    let b = body.as_bytes();
    let mut i = 0;
    while i < b.len() {
        if !(b[i].is_ascii_alphabetic() || b[i] == b'_') {
            i += 1;
            continue;
        }
        let start = i;
        while i < b.len() && is_word(b[i]) {
            i += 1;
        }
        let word = &body[start..i];
        if start > 0 && (is_word(b[start - 1]) || b[start - 1] == b'.') {
            continue;
        }
        let (cap_proc, typed) = match word {
            "PROC_REF" => (false, false),
            "TYPE_PROC_REF" => (false, true),
            "CAP_PROC" => (true, false),
            _ => continue,
        };
        let rest = &body[i..];
        let skip = rest.len() - rest.trim_start().len();
        if !rest.trim_start().starts_with('(') {
            continue;
        }
        let open = i + skip;
        let Some(close) = matching_paren(body, open) else { continue };
        let args = super::decls::split_args(&body[open + 1..close]);
        let (ty, proc) = if typed {
            (args.first().cloned().unwrap_or_default(), args.get(1).cloned().unwrap_or_default())
        } else {
            (owner.clone(), args.first().cloned().unwrap_or_default())
        };
        if proc.is_empty() || !proc.chars().all(|c| c.is_alphanumeric() || c == '_') {
            continue;
        }
        // The innermost hook form around this reference.
        let mut best: Option<&(usize, usize, usize)> = None;
        for r in &ranges {
            let (idx, s, e) = *r;
            let kw = HOOK_FORMS[idx].kw;
            // A named `when = PROC_REF(x)` / `because = PROC_REF(x)` covers only the reference written right after its `=`, not the next named
            // argument of the same entry (`adjacency(..., when = nameof(v), changed = PROC_REF(y))`).
            let covers = if (kw == "because" || kw == "when" || kw == "repeats" || kw == "answerer") && s == e { start >= s && start <= s + 64 && body.get(s..start).is_some_and(|t| t.trim() == "=") } else { start >= s && start < e };
            if covers && best.map(|b| s >= b.1).unwrap_or(true) {
                best = Some(r);
            }
        }
        let Some(&(idx, bs, be)) = best else { continue };
        let f = &HOOK_FORMS[idx];
        // `asks(..., when = PROC_REF(x))`: the step's own condition, asked with the op's context when the step is reached (pending_op).
        let in_asks_when = f.kw == "when"
            && bs == be
            && ranges.iter().any(|&(oidx, s, e)| HOOK_FORMS[oidx].kw == "asks" && s != e && start >= s && start < e);
        // A then() or when() inside a hook that carries its own context (instead, adjusts, on_notice, on_op, on_change, after_init) runs in that context.
        let in_op_when = f.kw == "when" && enclosing_op_start(body, start).is_some_and(|op_start| {
            !ranges.iter().any(|&(oidx, s, e)| s > op_start && s != e && start >= s && start < e
                && matches!(HOOK_FORMS[oidx].kw, "every" | "after" | "delayed" | "contributes" | "contributes_to" | "outputs" | "look_layer"))
        });
        let mut ctx = if in_asks_when || in_op_when { Ctx::Op } else { f.ctx };
        let mut notice = String::new();
        let mut role = f.role;
        if matches!(f.kw, "then" | "when") {
            let mut outer: Option<&(usize, usize, usize)> = None;
            for r in &ranges {
                let (oidx, s, e) = *r;
                let kw = HOOK_FORMS[oidx].kw;
                let carries_context = matches!(kw, "instead" | "adjusts" | "on_notice" | "on_op" | "on_change" | "after_init")
                    || (f.kw == "then" && matches!(kw, "every" | "after" | "delayed"));
                if carries_context && s != e && start >= s && start < e && outer.map(|o| s >= o.1).unwrap_or(true) {
                    outer = Some(r);
                }
            }
            if let Some(&(oidx, s, e)) = outer {
                ctx = HOOK_FORMS[oidx].ctx;
                if f.kw == "then" && HOOK_FORMS[oidx].role == Role::Reaction {
                    role = Role::Reaction;
                }
                match HOOK_FORMS[oidx].kw {
                    "on_notice" => notice = split_args(&body[s..e]).first().cloned().unwrap_or_default(),
                    "on_op" => notice = "/datum/notice/op_done".to_string(),
                    _ => {}
                }
            }
        }
        let condition_value = f.kw == "on_change" && split_args(&body[bs..be]).first().is_some_and(|argument| {
            body[bs..be].find(argument).is_some_and(|offset| start >= bs + offset && start < bs + offset + argument.len())
        });
        if condition_value { ctx = Ctx::Eval; }
        if condition_value { role = Role::Output; }
        let ui_args = if f.kw == "then" && ctx == Ctx::Op { op_ui_args(body, start) } else { None };
        out.push(HandlerRef { owner: ty, cap_proc, cap_type: cap_type.clone(), proc, form: f.kw, ctx, role, rel: m.rel.clone(), line: m.line_at(start), notice, ui_args });
    }
}

/// The innermost operation containing this reference; ordinary op when() is evaluated by op_cond with the full operation context.
fn enclosing_op_start(body: &str, pos: usize) -> Option<usize> {
    let bytes = body.as_bytes();
    let mut found = None;
    let mut i = 0;
    while i < pos {
        if bytes[i].is_ascii_alphabetic() || bytes[i] == b'_' {
            let begin = i;
            while i < bytes.len() && (bytes[i].is_ascii_alphanumeric() || bytes[i] == b'_') { i += 1; }
            if &body[begin..i] == "op" {
                let mut open = i;
                while open < bytes.len() && bytes[open].is_ascii_whitespace() { open += 1; }
                if bytes.get(open) == Some(&b'(') && matching_paren(body, open).is_some_and(|close| pos > open && pos < close) { found = Some(open); }
            }
        } else { i += 1; }
    }
    found
}

/// The `arg("name", ...)` names of the `ui_act(...)` / `topic(...)` bindings of the innermost `op(...)` call around `pos` of `body`; `None` when
/// that op has neither binding (or no op surrounds `pos`).
fn op_ui_args(body: &str, pos: usize) -> Option<Vec<String>> {
    let b = body.as_bytes();
    let mut innermost: Option<(usize, usize)> = None;
    let mut i = 0;
    while i < b.len() {
        if !(b[i].is_ascii_alphabetic() || b[i] == b'_') {
            i += 1;
            continue;
        }
        let start = i;
        while i < b.len() && is_word(b[i]) {
            i += 1;
        }
        if &body[start..i] != "op" || (start > 0 && (is_word(b[start - 1]) || b[start - 1] == b'.')) {
            continue;
        }
        let rest = &body[i..];
        let skip = rest.len() - rest.trim_start().len();
        if !rest.trim_start().starts_with('(') {
            continue;
        }
        let open = i + skip;
        if let Some(close) = matching_paren(body, open) {
            if open < pos && pos < close && innermost.map(|(o, _)| open > o).unwrap_or(true) {
                innermost = Some((open, close));
            }
        }
    }
    let (open, close) = innermost?;
    let text = &body[open + 1..close];
    let tb = text.as_bytes();
    let mut names = Vec::new();
    let mut bound = false;
    let mut j = 0;
    while j < tb.len() {
        if !(tb[j].is_ascii_alphabetic() || tb[j] == b'_') {
            j += 1;
            continue;
        }
        let start = j;
        while j < tb.len() && is_word(tb[j]) {
            j += 1;
        }
        let word = &text[start..j];
        if start > 0 && (is_word(tb[start - 1]) || tb[start - 1] == b'.') {
            continue;
        }
        let rest = &text[j..];
        let skip = rest.len() - rest.trim_start().len();
        if !rest.trim_start().starts_with('(') {
            continue;
        }
        match word {
            "ui_act" | "topic" | "topic_in" => bound = true,
            "arg" => {
                let open_arg = j + skip;
                if let Some(close_arg) = matching_paren(text, open_arg) {
                    let args = super::decls::split_args(&text[open_arg + 1..close_arg]);
                    if let Some(name) = args.first() {
                        names.push(name.trim().trim_matches('"').to_string());
                    }
                }
            }
            _ => {}
        }
    }
    if bound {
        Some(names)
    } else {
        None
    }
}

/// The `holder = /type` / `of = /type` parameter of a capability marker, if given.
fn holder_arg(m: &Marker) -> String {
    for a in &m.args {
        let c = a.replace(' ', "");
        for p in ["holder=", "of="] {
            if let Some(v) = c.strip_prefix(p) {
                if v.starts_with('/') {
                    return v.to_string();
                }
            }
        }
    }
    String::new()
}

#[cfg(test)]
mod context_tests {
    use super::*;
    use crate::tree::{SourceFile, Tree};

    fn handlers(source: &str) -> Vec<HandlerRef> {
        let file = SourceFile::from_text("code/content/probe.dm", source);
        let tree = Tree::from_files(vec![file]);
        let decls = Decls::get(&tree);
        let mut found = Vec::new();
        for marker in &decls.markers {
            marker_handlers(marker, &mut found);
        }
        assert!(!found.is_empty(), "the fixture must discover its declarations");
        found
    }

    #[test]
    fn change_value_getter_is_an_output_but_handler_is_a_reaction() {
        let found = handlers("CAPABILITIES(/datum/probe)\n\ton_change(cond_all(PROC_REF(value), PROC_REF(other)), ANY, then(PROC_REF(deliver)))\n");
        let value = found.iter().find(|h| h.proc == "value").unwrap();
        assert_eq!(value.ctx, Ctx::Eval);
        assert_eq!(value.role, Role::Output);
        assert!(value.role.reads_covered());
        assert_eq!(found.iter().find(|h| h.proc == "other").unwrap().role, Role::Output);
        let deliver = found.iter().find(|h| h.proc == "deliver").unwrap();
        assert_eq!(deliver.ctx, Ctx::Notice);
        assert_eq!(deliver.role, Role::Reaction);
    }

    #[test]
    fn only_notice_carried_then_handlers_gain_reaction_role() {
        let found = handlers("CAPABILITIES(/datum/probe)
	on_notice(/datum/notice/probe, then(PROC_REF(noticed)))
	on_op(\"use\", then(PROC_REF(completed)))
	every(10, then(PROC_REF(tick)))
	op(\"ordinary\", then(PROC_REF(effect)))
");
        for name in ["noticed", "completed"] {
            let handler = found.iter().find(|h| h.proc == name).unwrap();
            assert_eq!(handler.role, Role::Reaction);
            assert_eq!(handler.ctx, Ctx::Notice);
        }
        assert_eq!(found.iter().find(|h| h.proc == "tick").unwrap().role, Role::Effect);
        assert_eq!(found.iter().find(|h| h.proc == "effect").unwrap().role, Role::Effect);
    }

    #[test]
    fn operation_when_receives_full_op_but_periodic_when_does_not() {
        let found = handlers("CAPABILITIES(/datum/probe)\n\top(\"use\", item(/obj), when(PROC_REF(offered)), then(PROC_REF(use)))\n\top(\"nested\", every(10, when = PROC_REF(ready), then(PROC_REF(tick))))\n\tevery(10, when = PROC_REF(standalone_ready), then(PROC_REF(standalone_tick)))\n");
        assert_eq!(found.iter().find(|h| h.proc == "offered").unwrap().ctx, Ctx::Op);
        assert_eq!(found.iter().find(|h| h.proc == "ready").unwrap().ctx, Ctx::Eval);
        assert_eq!(found.iter().find(|h| h.proc == "standalone_ready").unwrap().ctx, Ctx::Eval);
        assert_eq!(found.iter().find(|h| h.proc == "tick").unwrap().ctx, Ctx::Timer);
    }

    #[test]
    fn nested_every_members_effect_uses_timer_context() {
        let found = handlers("CAPABILITIES(/datum/system/probe)\n\tevery(10, then(PROC_REF(visit)), members = /datum/member, when = PROC_REF(ready))\n\top(\"ordinary\", then(PROC_REF(ordinary)))\n");
        let visit = found.iter().find(|h| h.proc == "visit").unwrap();
        assert_eq!(visit.ctx, Ctx::Timer);
        assert_eq!(visit.form, "then");
        assert_eq!(found.iter().find(|h| h.proc == "ready").unwrap().ctx, Ctx::Eval, "every admission conditions remain evaluation contexts");
        assert_eq!(found.iter().find(|h| h.proc == "ordinary").unwrap().ctx, Ctx::Op, "ordinary effects retain operation contexts");
    }

    #[test]
    fn nearest_timer_carrier_wins_and_does_not_take_ui_args() {
        let found = handlers("CAPABILITIES(/datum/probe)\n\top(\"press\", ui_act(\"press\", arg(\"value\")), on_notice(/datum/notice/probe, delayed(10, then(PROC_REF(later)))))\n");
        let later = found.iter().find(|h| h.proc == "later").unwrap();
        assert_eq!(later.ctx, Ctx::Timer, "a delayed effect receives a timer rather than its enclosing notice");
        assert!(later.ui_args.is_none(), "timer callbacks do not inherit UI invocation parameters");
    }
}

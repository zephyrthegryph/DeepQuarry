//! Handler discovery: the procs a declaration names.
//!
//! "Every proc the engine calls to run a part or a trigger is `x(datum/act/A)`: effects,
//! requirements, conditions, hook handlers, every() and sequence work, outputs, then(),
//! because = PROC_REF, CAP_PROC" (doc/rewrite/final_api.html section 7). A declaration is a marker
//! (`CAPABILITIES(T, ...)`, `CAPABILITY_DEF/TYPE`, `STAT`, `BUNDLE`); a hook form inside it
//! (`needs(...)`, `when(...)`, `contributes(...)`, `every(...)`, `then(...)`, ...) takes handlers as
//! `PROC_REF(x)`, `TYPE_PROC_REF(/type, x)` or `CAP_PROC(x)`. The hook form decides which context
//! type the handler is called with, and so which fields it may read (section 8, "Contexts").

use super::decls::{matching_paren, Decls, Marker};

/// The five context types of section 8.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum Ctx {
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
    HookForm { kw: "outputs", ctx: Ctx::Eval, role: Role::Output },
    HookForm { kw: "look_layer", ctx: Ctx::Eval, role: Role::Condition },
    HookForm { kw: "then", ctx: Ctx::Op, role: Role::Effect },
    HookForm { kw: "because", ctx: Ctx::Op, role: Role::Reason },
    HookForm { kw: "every", ctx: Ctx::Timer, role: Role::Work },
    HookForm { kw: "after", ctx: Ctx::Timer, role: Role::Work },
    HookForm { kw: "delayed", ctx: Ctx::Timer, role: Role::Work },
    HookForm { kw: "on_notice", ctx: Ctx::Notice, role: Role::Reaction },
    HookForm { kw: "on_op", ctx: Ctx::Notice, role: Role::Reaction },
    HookForm { kw: "on_change", ctx: Ctx::Notice, role: Role::Reaction },
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
            if word == "because" || word == "when" {
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
        if !matches!(m.name.as_str(), "CAPABILITIES" | "CAPABILITY_DEF" | "CAPABILITY_TYPE" | "STAT" | "BUNDLE") {
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
            let covers = if (kw == "because" || kw == "when") && s == e { start >= s && start <= s + 64 } else { start >= s && start < e };
            if covers && best.map(|b| s >= b.1).unwrap_or(true) {
                best = Some(r);
            }
        }
        let Some(&(idx, _, _)) = best else { continue };
        let f = &HOOK_FORMS[idx];
        out.push(HandlerRef { owner: ty, cap_proc, cap_type: cap_type.clone(), proc, form: f.kw, ctx: f.ctx, role: f.role, rel: m.rel.clone(), line: m.line_at(start) });
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

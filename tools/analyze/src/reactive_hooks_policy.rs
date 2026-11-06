//! Handler discovery: the procs a declaration names.
//!
//! "Every proc the engine calls to run a part or a trigger is `x(datum/act/A)`: effects,
//! requirements, conditions, hook handlers, every() and sequence work, outputs, then(),
//! because = PROC_REF, CAP_PROC" (doc/rewrite/final_api.html section 7). A declaration is a marker
//! (`CAPABILITIES(T, ...)`, `CAPABILITY_DEF/TYPE`, `STAT`, and the entry procs a block names); a hook form inside it
//! (`needs(...)`, `when(...)`, `contributes(...)`, `every(...)`, `then(...)`, ...) takes handlers as
//! `PROC_REF(x)`, `TYPE_PROC_REF(/type, x)` or `CAP_PROC(x)`. The hook form decides which context
//! type the handler is called with, and so which fields it may read (section 8, "Contexts").

use crate::{raw_marker_policy::{matching_paren,argument_slices},declare_policy::Marker,key_policy_control as kc};
pub const OPAQUE_DIRS: &[&str] = &["code/library/sys/", "code/datums/om/", "code/library/ui/tgui/", "code/library/capabilities/", "code/library/reactions/", "code/library/ownership/", "code/engine/", "code/__defines/verdigris/"];
const RUNTIME_OBSERVE:&str="RUNTIME_OBSERVE";

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
    /// A pure boolean evaluated only during lifecycle setup, never subscribed reactively.
    InitCondition,
    Requirement,
    BooleanRequirement,
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
        matches!(self, Role::Condition | Role::InitCondition | Role::Requirement | Role::BooleanRequirement | Role::Output | Role::Contribution | Role::Reason)
    }

    /// Conditions and explicit transitional requirements answer TRUE/FALSE.
    pub fn boolean(&self) -> bool {
        matches!(self, Role::Condition | Role::InitCondition | Role::BooleanRequirement)
    }

    /// Roles whose result feeds the dependency graph (what they read subscribes).
    pub fn reads_covered(&self) -> bool {
        matches!(self, Role::Condition | Role::Requirement | Role::BooleanRequirement | Role::Output | Role::Contribution)
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
    HookForm { kw: "req_bool", ctx: Ctx::Op, role: Role::BooleanRequirement },
    HookForm { kw: "when", ctx: Ctx::Eval, role: Role::Condition },
    HookForm { kw: "contributes", ctx: Ctx::Eval, role: Role::Contribution },
    HookForm { kw: "contributes_to", ctx: Ctx::Eval, role: Role::Contribution },
    // `factors(PROC_REF(table), scale = PROC_REF(x))`: the table and the scale are read at the holder, pure, like a contribution's value
    HookForm { kw: "factors", ctx: Ctx::Eval, role: Role::Contribution },
    HookForm { kw: "outputs", ctx: Ctx::Eval, role: Role::Output },
    HookForm { kw: "look_layer", ctx: Ctx::Eval, role: Role::Condition },
    // `look_glow(PROC_REF(x), when = ...)`: the light's value (a GLOW()), read when the look is drawn; pure, and it reads declared state only
    HookForm { kw: "look_glow", ctx: Ctx::Eval, role: Role::Contribution },
    HookForm { kw: "then", ctx: Ctx::Op, role: Role::Effect },
    HookForm { kw: "because", ctx: Ctx::Op, role: Role::Reason },
    // req_window_usable(remote = ...): the optional remote admission predicate remains boolean.
    HookForm { kw: "remote", ctx: Ctx::Op, role: Role::Condition },
    HookForm { kw: "remote_because", ctx: Ctx::Op, role: Role::Reason },
    // `asks(..., repeats = PROC_REF(x))`: asked with the op's context after each answer (pending_op request_done)
    HookForm { kw: "repeats", ctx: Ctx::Op, role: Role::Condition },
    // `wait_until(until = PROC_REF(x))`: the hold's end condition, asked with the op's context whenever something it reads is published
    HookForm { kw: "until", ctx: Ctx::Op, role: Role::Condition },
    // `wait(t, repeats = PROC_REF(x), after_step = PROC_REF(y))`: x is asked after each lap (a condition), y runs each finished lap's effect (pending_op step_done)
    HookForm { kw: "after_step", ctx: Ctx::Op, role: Role::Effect },
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
fn hook_ranges<C:kc::Control>(body: &str,c:&mut C) -> Result<Vec<(usize, usize, usize)>,C::Error> {
    let b = body.as_bytes();
    let mut out = Vec::new();
    let mut i = 0;
    let mut in_str = false;
    while i < b.len() {
        if i%256==0{c.checkpoint()?;}
        let byte = b[i];
        if byte == b'"' {
            in_str = !in_str;
            i += 1;
            continue;
        }
        if in_str || !(byte.is_ascii_alphabetic() || byte == b'_') {
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
            if matches!(word, "because" | "when" | "repeats" | "answerer" | "remote" | "remote_because" | "until" | "after_step") {
                let rest = body[i..].trim_start();
                if rest.starts_with('=') && !rest.starts_with("==") {
                    crate::reactive_dependency_fold::row(c,&mut out)?;out.push((HOOK_FORMS.iter().position(|f| f.kw == word).unwrap(), i, i));
                    continue;
                }
            }
            if let Some(idx) = HOOK_FORMS.iter().position(|f| f.kw == word) {
                let rest = &body[i..];
                let skip = rest.len() - rest.trim_start().len();
                if rest.trim_start().starts_with('(') {
                    let open = i + skip;
                    if let Some(close) = matching_paren(body, open) {
                        crate::reactive_dependency_fold::row(c,&mut out)?;out.push((idx, open + 1, close));
                    }
                }
            }
        }
    }
    Ok(out)
}

/// Every handler a declaration marker names.
pub fn discover(markers:&[Marker<'_>])->Vec<HandlerRef>{match discover_admitted(markers,&mut kc::Compatibility){Ok(v)=>v,Err(e)=>match e{}}}
pub fn discover_in(markers:&[Marker<'_>],names:&[&str])->Vec<HandlerRef>{match discover_in_admitted(markers,names,&mut kc::Compatibility){Ok(v)=>v,Err(e)=>match e{}}}
pub fn discover_admitted<C:kc::Control>(markers:&[Marker<'_>],c:&mut C)->Result<Vec<HandlerRef>,C::Error>{let mut out=Vec::new();for m in markers{c.checkpoint()?;if matches!(m.name,"CAPABILITIES"|"CAPABILITY_DEF"|"CAPABILITY_TYPE"|"STAT"|crate::raw_entry_proc_policy::ENTRY_PROC|RUNTIME_OBSERVE){marker_handlers(m,&mut out,c)?;}}c.checkpoint()?;Ok(out)}
pub fn discover_in_admitted<C:kc::Control>(markers:&[Marker<'_>],names:&[&str],c:&mut C)->Result<Vec<HandlerRef>,C::Error>{let mut out=Vec::new();for m in markers{c.checkpoint()?;if names.contains(&m.name){marker_handlers(m,&mut out,c)?;}}c.checkpoint()?;Ok(out)}
fn arg_owned<C:kc::Control>(arg:Option<&String>,c:&mut C)->Result<String,C::Error>{match arg{Some(s)=>kc::own(c,s),None=>Ok(String::new())}}

fn marker_handlers<C:kc::Control>(m: &Marker, out: &mut Vec<HandlerRef>,c:&mut C)->Result<(),C::Error> {
    // The non-path observe overload is a legacy key subscription, not an act handler.
    // Its callback receives a key list; only path triggers use native action parts.
    let runtime_trigger = if m.name == RUNTIME_OBSERVE {
        let Some(trigger) = m.args.get(1).filter(|arg| arg.starts_with("/datum/")) else { return Ok(()) };
        Some(trigger.as_str())
    } else { None };
    let mut runtime_parts_start = 0;
    if runtime_trigger.is_some() {
        // Only arguments four onward are parts. Source/trigger/listener expressions
        // may themselves contain forms, but are not this observer's callbacks.
        for arg in m.args.iter().take(3) {
            let Some(offset) = m.body[runtime_parts_start..].find(arg) else { return Ok(()) };
            runtime_parts_start += offset + arg.len();
        }
    }
    let (owner, cap_type) = match m.name {
        "CAPABILITIES" => (arg_owned(m.args.first(),c)?, String::new()),
        "STAT" => (arg_owned(m.args.first(),c)?, String::new()),
        "CAPABILITY_TYPE" => (holder_arg(m,c)?, arg_owned(m.args.get(2),c)?),
        "CAPABILITY_DEF" => (holder_arg(m,c)?, String::new()),
        _ => (String::new(), String::new()),
    };
    let body = &m.body;
    let ranges = hook_ranges(body,c)?;
    let b = body.as_bytes();
    let mut i = 0;
    while i < b.len() {
        if i%256==0{c.checkpoint()?;}
        if !(b[i].is_ascii_alphabetic() || b[i] == b'_') {
            i += 1;
            continue;
        }
        let start = i;
        while i < b.len() && is_word(b[i]) {
            i += 1;
        }
        let word = &body[start..i];
        if start < runtime_parts_start { continue; }
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
        let mut args = argument_slices(&body[open + 1..close]);
        let first=args.next().unwrap_or_default();let second=args.next().unwrap_or_default();
        let (ty, proc) = if typed {
            (kc::own(c,first)?,kc::own(c,second)?)
        } else {
            (kc::own(c,&owner)?,kc::own(c,first)?)
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
            let covers = if matches!(kw, "because" | "when" | "repeats" | "answerer" | "remote" | "remote_because" | "until" | "after_step") && s == e { start >= s && start <= s + 64 && body.get(s..start).is_some_and(|t| t.trim() == "=") } else { start >= s && start < e };
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
                && matches!(HOOK_FORMS[oidx].kw, "every" | "after" | "delayed" | "contributes" | "contributes_to" | "factors" | "outputs" | "look_layer" | "look_glow"))
        });
        let mut ctx = if in_asks_when || in_op_when { Ctx::Op } else { f.ctx };
        let mut notice = String::new();
        let mut role = f.role;
        // registry(when =) decides initial membership once. Rekey/movement only watches
        // its key; treating this predicate as a persistent input invents a subscription.
        if f.kw == "when" && bs == be && enclosing_call_start(body, start, "registry").is_some() {
            role = Role::InitCondition;
        }
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
                    "on_notice" => notice = kc::own(c,argument_slices(&body[s..e]).next().unwrap_or_default())?,
                    "on_op" => notice = kc::own(c,"/datum/notice/op_done")?,
                    _ => {}
                }
            }
        }
        // Runtime observe is extend(action, parts...) or on_notice(notice, parts...),
        // selected by its trigger. Requirements still receive the operation query.
        if let Some(trigger) = runtime_trigger {
            if matches!(f.kw, "then" | "when" | "instead" | "adjusts" | "adjusts_with") {
                ctx = if trigger.starts_with("/datum/act/") { Ctx::Action } else { Ctx::Notice };
                notice = kc::own(c,trigger)?;
                if f.kw == "then" { role = Role::Reaction; }
            }
        }
        let condition_value = f.kw == "on_change" && argument_slices(&body[bs..be]).next().is_some_and(|argument| {
            body[bs..be].find(argument).is_some_and(|offset| start >= bs + offset && start < bs + offset + argument.len())
        });
        if condition_value { ctx = Ctx::Eval; }
        if condition_value { role = Role::Output; }
        let ui_args = if f.kw == "then" && ctx == Ctx::Op { op_ui_args(body, start,c)? } else { None };
        crate::reactive_dependency_fold::row(c,out)?;
        out.push(HandlerRef { owner: ty, cap_proc, cap_type: kc::own(c,&cap_type)?, proc, form: f.kw, ctx, role, rel: kc::own(c,m.rel)?, line: m.line_at(start), notice, ui_args });
    }
    c.checkpoint()?;Ok(())
}

/// The innermost operation containing this reference; ordinary op when() is evaluated by op_cond with the full operation context.
fn enclosing_op_start(body: &str, pos: usize) -> Option<usize> {
    enclosing_call_start(body, pos, "op")
}

fn enclosing_call_start(body: &str, pos: usize, name: &str) -> Option<usize> {
    let bytes = body.as_bytes();
    let mut found = None;
    let mut i = 0;
    while i < pos {
        if bytes[i] == b'"' || bytes[i] == b'\'' {
            let quote = bytes[i];
            i += 1;
            while i < pos {
                if bytes[i] == b'\\' { i += 2; continue; }
                if bytes[i] == quote { i += 1; break; }
                i += 1;
            }
            continue;
        }
        if bytes[i].is_ascii_alphabetic() || bytes[i] == b'_' {
            let begin = i;
            while i < bytes.len() && (bytes[i].is_ascii_alphanumeric() || bytes[i] == b'_') { i += 1; }
            if &body[begin..i] == name {
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
fn op_ui_args<C:kc::Control>(body: &str, pos: usize,c:&mut C) -> Result<Option<Vec<String>>,C::Error> {
    let b = body.as_bytes();
    let mut innermost: Option<(usize, usize)> = None;
    let mut i = 0;
    while i < b.len() {
        if i%256==0{c.checkpoint()?;}
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
    let Some((open, close)) = innermost else{return Ok(None)};
    let text = &body[open + 1..close];
    let tb = text.as_bytes();
    let mut names = Vec::new();
    let mut bound = false;
    let mut j = 0;
    while j < tb.len() {
        if j%256==0{c.checkpoint()?;}
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
                    let mut args = argument_slices(&text[open_arg + 1..close_arg]);
                    if let Some(name) = args.next() {
                        crate::reactive_dependency_fold::row(c,&mut names)?;names.push(kc::own(c,name.trim().trim_matches('"'))?);
                    }
                }
            }
            _ => {}
        }
    }
    if bound {
        Ok(Some(names))
    } else {
        Ok(None)
    }
}

/// The `holder = /type` / `of = /type` parameter of a capability marker, if given.
fn holder_arg<C:kc::Control>(m: &Marker,c:&mut C) -> Result<String,C::Error> {
    for a in m.args {
        kc::reserve(c,||a.len().checked_add(64))?;let compact = a.replace(' ', "");
        for p in ["holder=", "of="] {
            if let Some(v) = compact.strip_prefix(p) {
                if v.starts_with('/') {
                    return kc::own(c,v);
                }
            }
        }
    }
    Ok(String::new())
}

#[cfg(test)]
#[path="reactive_hooks_frozen_original.rs"]mod hooks_original_reference;
#[cfg(test)]mod growth_tests{
 use super::*;use std::io;
 use super::hooks_original_reference as original;
 struct Probe{left:usize,polls:usize,fail:usize}
 impl kc::Control for Probe{type Error=io::Error;const CHECKED:bool=true;fn checkpoint(&mut self)->io::Result<()>{self.polls+=1;if self.polls==self.fail{Err(io::Error::from_raw_os_error(1450))}else{Ok(())}}fn reserve(&mut self,n:usize)->io::Result<()>{self.left=self.left.checked_sub(n).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;Ok(())}fn overflow(&mut self)->io::Error{io::ErrorKind::OutOfMemory.into()}fn allocation_failed(&mut self)->io::Error{io::ErrorKind::OutOfMemory.into()}}
 fn run(body:&str,args:&[String],name:&str,c:&mut Probe)->io::Result<Vec<HandlerRef>>{discover_admitted(&[Marker{name,rel:"code/probe.dm",line:1,body,args,body_offset:0,line_starts:&[0]}],c)}
 #[test]fn admitted_hook_discovery_matches_entire_original_rows_and_actual_growth(){let args=vec!["/datum/probe".into()];for body in ["op(x,ui_act(x,arg(\"value\")),needs(PROC_REF(ready)),then(PROC_REF(run)))","on_notice(/datum/notice/x,then(TYPE_PROC_REF(/datum/other,changed)))","registry(when = PROC_REF(once)), on_change(nameof(value),PROC_REF(changed))","every(1,then(CAP_PROC(tick))), outputs(PROC_REF(draw))"]{let marker=Marker{name:"CAPABILITIES",rel:"code/probe.dm",line:1,body,args:&args,body_offset:0,line_starts:&[0]};let old=original::discover(&[marker]);let got=run(body,&args,"CAPABILITIES",&mut Probe{left:65536,polls:0,fail:usize::MAX}).unwrap();assert_eq!(format!("{got:?}"),format!("{old:?}"));}let padded=format!("{}outputs(PROC_REF(draw))"," ".repeat(100_000));let mut c=Probe{left:65536,polls:0,fail:usize::MAX};assert_eq!(run(&padded,&args,"CAPABILITIES",&mut c).unwrap().len(),1);assert!(c.left>32768);}
 #[test]fn admitted_hook_discovery_quota_and_actual_io_never_return_partial_rows_and_retry(){let args=vec!["/datum/probe".into()];let body="outputs(PROC_REF(draw)), outputs(PROC_REF(other))";let error=run(body,&args,"CAPABILITIES",&mut Probe{left:1,polls:0,fail:usize::MAX}).unwrap_err();assert_eq!(error.kind(),io::ErrorKind::OutOfMemory);let error=run(body,&args,"CAPABILITIES",&mut Probe{left:65536,polls:0,fail:3}).unwrap_err();assert_eq!(error.raw_os_error(),Some(1450));assert_eq!(run(body,&args,"CAPABILITIES",&mut Probe{left:65536,polls:0,fail:usize::MAX}).unwrap().len(),2);}
}

//! `om_ask` to `open_request`, for the four generic prompt kinds, without changing what the player or the answer proc sees.
//!
//! ```text
//! om_ask(M, /datum/om/prompt/text, PROC_REF(named), title = "T", message = "Name?", default = d)
//!   -> open_request(src, /datum/prompt/text, PROC_REF(named), answerer = M, title = "T", question = "Name?", default = d, timeout = 0)
//! /type/proc/named(datum/om/prompt/text/ask)               /type/proc/named(datum/act/request/A)
//!     ... ask.text ... ask.answerer ...                ->      if(!A.answer) return
//!                                                              ... A.answer.answer_value ... A.request.answerer ...
//! ```
//!
//! The old kind runs the answer proc on an answer only, so the converted handler starts with the matching guard (a confirm: on yes,
//! unless `answer_on_no`). The old `timeout` default is 0 (wait while the window is open) and the new kinds' own defaults differ, so the
//! timeout is always written. `encode` is passed through (the new text prompt has it, default TRUE as its window always had it), and a
//! text prompt with `max_length = MAX_NAME_LEN` says `name_text = TRUE`, the old unset-`name_text` rule. A site converts only with a
//! literal kind of confirm, text, number or choice, a `message`, parameters from the lists below, and a handler on `src` that reads
//! the answer (and `answerer`) and nothing else of the prompt; roles, `requires`, `ask_flags` and cancel options are residue.

use std::any::Any;
use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};
use std::path::Path;
use std::sync::Arc;

use super::om_hook::{collect_refs, is_ident_byte, related, starts_line, words, OccKind};
use super::scan::{self, Span};
use super::{Ctx, Edit, Outcome, Rewrite};
use crate::dm::ownership_index::proc_scopes;
use crate::sem::decls::{matching_paren, split_args};
use crate::sem::Sem;
use crate::tree::{SourceFile, Tree, CODE_DM};

/// The roles, checks and options of the old prompt that the new request has no field for.
const ROLES_OR_CHECKS: &[&str] = &[
    "asker", "subject", "receiver", "optional", "cancel_answer", "cancel_text", "cancel_choice", "hold_strong", "ui_refresh", "ui_refresh_if_true",
    "key", "yes_text", "no_text", "no_first", "round_entry", "answer_proc",
];

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
enum Kind {
    Confirm,
    Text,
    Number,
    Choice,
    Color,
    Radial,
}

impl Kind {
    fn of(path: &str) -> Option<Kind> {
        match path.trim() {
            "/datum/om/prompt/confirm" => Some(Kind::Confirm),
            "/datum/om/prompt/text" => Some(Kind::Text),
            "/datum/om/prompt/number" => Some(Kind::Number),
            "/datum/om/prompt/choice" => Some(Kind::Choice),
            "/datum/om/prompt/color" => Some(Kind::Color),
            "/datum/om/prompt/choice/radial" => Some(Kind::Radial),
            _ => None,
        }
    }
    fn new_type(self) -> &'static str {
        match self {
            Kind::Confirm => "/datum/prompt/yes_no",
            Kind::Text => "/datum/prompt/text",
            Kind::Number => "/datum/prompt/number",
            Kind::Choice | Kind::Radial => "/datum/prompt/choice",
            Kind::Color => "/datum/prompt/color",
        }
    }
    /// The var the old kind keeps its answer in.
    fn answer_var(self) -> &'static str {
        match self {
            Kind::Confirm => "yes",
            Kind::Text => "text",
            Kind::Number => "number",
            Kind::Choice | Kind::Radial => "choice",
            Kind::Color => "picked_color",
        }
    }
    /// The old parameters the kind takes (besides title, message, timeout) and the new field each becomes.
    fn params(self) -> &'static [(&'static str, &'static str)] {
        match self {
            Kind::Confirm => &[],
            Kind::Text => &[("default", "default"), ("max_length", "max_len"), ("multiline", "multiline"), ("encode", "encode"), ("name_text", "name_text")],
            Kind::Number => &[("default", "default"), ("min", "min_value"), ("max", "max_value")],
            Kind::Choice => &[("choices", "choices"), ("default", "default"), ("buttons", "buttons")],
            Kind::Color => &[("default", "default")],
            Kind::Radial => &[
                ("choices", "choices"),
                ("anchor", "anchor"),
                ("radius", "radius"),
                ("tooltips", "tooltips"),
                ("radial_slice_icon", "radial_slice_icon"),
                ("autopick_single_option", "autopick_single_option"),
                ("entry_animation", "entry_animation"),
                ("click_on_hover", "click_on_hover"),
                ("user_space", "user_space"),
                ("require_near", "require_near"),
                ("uniqueid", "uniqueid"),
            ],
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
enum Guard {
    /// A confirm: the handler ran on yes only.
    Yes,
    /// Everything else, and a confirm with answer_on_no: it ran on any answer.
    Answered,
}

#[derive(Clone, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
struct HKey {
    ty: String,
    name: String,
}

impl HKey {
    fn text(&self) -> String {
        format!("{}|{}", self.ty, self.name)
    }
    fn parse(s: &str) -> Option<HKey> {
        let (ty, name) = s.split_once('|')?;
        Some(HKey { ty: ty.to_string(), name: name.to_string() })
    }
}

#[derive(Clone, Debug)]
struct DefInfo {
    ty: String,
    rel: String,
    line: u32,
}

#[derive(Clone, Debug)]
struct Site {
    rel: String,
    pos: (u32, usize),
    hline: u32,
    excluded: bool,
    kind: Option<Kind>,
    guard: Guard,
    handler: Option<HKey>,
    base: Option<&'static str>,
}

#[derive(Debug, Default)]
struct HandlerPlan {
    kind: Option<Kind>,
    guard: Option<Guard>,
    defs: Vec<DefInfo>,
    blocked: bool,
}

pub struct Prep {
    decisions: HashMap<(String, u32, usize), Result<(), &'static str>>,
    handlers: HashMap<HKey, HandlerPlan>,
    /// (type, proc) of every converted handler -> (its prompt parameter, its kind): an om_ask inside one reads the old answer in its own arguments.
    enclosing: HashMap<(String, String), (String, Kind)>,
}

fn handler_of(arg: &str, owner: &str) -> Result<HKey, &'static str> {
    let a = arg.trim();
    if let Some(name) = a.strip_prefix("PROC_REF(").and_then(|r| r.strip_suffix(')')) {
        let name = name.trim();
        if !name.is_empty() && name.chars().all(|c| c.is_alphanumeric() || c == '_') && !owner.is_empty() && owner != "/" {
            return Ok(HKey { ty: owner.to_string(), name: name.to_string() });
        }
    }
    if let Some(inner) = a.strip_prefix("TYPE_PROC_REF(").and_then(|r| r.strip_suffix(')')) {
        let parts = split_args(inner);
        if parts.len() == 2 && parts[0].starts_with('/') && parts[1].chars().all(|c| c.is_alphanumeric() || c == '_') {
            return Ok(HKey { ty: parts[0].clone(), name: parts[1].clone() });
        }
    }
    Err("handler_expr")
}

/// The named parameters of an om_ask call (those after the third argument), or why the call is not plain.
fn named_params<'a>(text: &'a str, node: &scan::CallNode) -> Result<Vec<(String, &'a str)>, &'static str> {
    let mut out = Vec::new();
    for a in node.args.iter().skip(3) {
        let Some((name, v)) = &a.named else { return Err("argc") };
        out.push((name.clone(), v.text(text)));
    }
    Ok(out)
}

/// `ASK_A | ASK_B`: the old flags, spelled the same on the request.
fn is_ask_flags(value: &str) -> bool {
    let v = value.trim();
    !v.is_empty() && v.split('|').all(|p| {
        let p = p.trim();
        p.starts_with("ASK_") && p.chars().all(|c| c.is_ascii_uppercase() || c == '_')
    })
}

/// What an old `requires` list becomes on the request: more ask flags, admin rights, a tgui state.
#[derive(Default, Debug, PartialEq)]
struct RequiresFields {
    flags: Vec<&'static str>,
    rights: Option<String>,
    usable: Option<String>,
}

fn requires_fields(value: &str) -> Option<RequiresFields> {
    let v = value.trim();
    let mut out = RequiresFields::default();
    if let Some(inner) = v.strip_prefix("PROMPT_ADMIN(").and_then(|r| r.strip_suffix(')')) {
        out.rights = Some(inner.trim().to_string());
        return Some(out);
    }
    if let Some(inner) = v.strip_prefix("PROMPT_USABLE_BY(").and_then(|r| r.strip_suffix(')')) {
        let name = inner.trim();
        if name.len() > 2 && name.starts_with('"') && name.ends_with('"') && name[1..name.len() - 1].chars().all(|c| c.is_ascii_lowercase() || c == '_') {
            out.usable = Some(name.to_string());
            return Some(out);
        }
        return None;
    }
    if let Some(inner) = v.strip_prefix("list(").and_then(|r| r.strip_suffix(')')) {
        for item in split_args(inner) {
            match item.trim() {
                "/datum/om/check/inside_target" => out.flags.push("ASK_INSIDE"),
                "/datum/om/check/not_incapacitated" => out.flags.push("ASK_CAPABLE"),
                _ => return None,
            }
        }
        return if out.flags.is_empty() { None } else { Some(out) };
    }
    None
}

/// The shape of one site, independent of its handler.
fn judge(text: &str, node: &scan::CallNode, owner: &str) -> (Option<Kind>, Guard, Option<&'static str>) {
    let mut guard = Guard::Answered;
    if node.args.len() < 3 || node.args.iter().take(3).any(|a| a.named.is_some()) {
        return (None, guard, Some("argc"));
    }
    let Some(kind) = Kind::of(node.args[1].span.text(text)) else { return (None, guard, Some("kind_unsupported")) };
    if owner.is_empty() || owner == "/" {
        return (Some(kind), guard, Some("handler_expr"));
    }
    // A flow's prompt is parked with the flow and stops it on a cancel: the request has none of that.
    if owner == "/datum/om/flow" || owner.starts_with("/datum/om/flow/") {
        return (Some(kind), guard, Some("flow_receiver"));
    }
    let params = match named_params(text, node) {
        Ok(p) => p,
        Err(why) => return (Some(kind), guard, Some(why)),
    };
    let atom_owner = ["/atom", "/obj", "/mob", "/turf", "/area"].iter().any(|r| owner == *r || owner.starts_with(&format!("{}/", r)));
    if kind == Kind::Radial && !atom_owner {
        // the old ring's default anchor is the receiver when that is an atom: the new one has to be told
        return (Some(kind), guard, Some("radial_anchor_unknown"));
    }
    let allowed: BTreeSet<&str> = ["title", "message", "timeout", "ask_flags", "requires"].into_iter().chain(kind.params().iter().map(|(o, _)| *o)).chain(if kind == Kind::Confirm { Some("answer_on_no") } else { None }).collect();
    let mut message = false;
    for (name, value) in &params {
        if ROLES_OR_CHECKS.contains(&name.as_str()) {
            return (Some(kind), guard, Some("roles_or_checks"));
        }
        if !allowed.contains(name.as_str()) {
            return (Some(kind), guard, Some("unsupported_param"));
        }
        if name == "ask_flags" && !is_ask_flags(value) {
            return (Some(kind), guard, Some("unsupported_param"));
        }
        if name == "requires" {
            match requires_fields(value) {
                None => return (Some(kind), guard, Some("requires_unknown")),
                Some(r) if r.usable.is_some() && !atom_owner => return (Some(kind), guard, Some("requires_unknown")),
                Some(_) => {}
            }
        }
        if name == "message" {
            message = true;
        }
        if name == "answer_on_no" {
            if !matches!(value.trim(), "TRUE" | "1") {
                return (Some(kind), guard, Some("unsupported_param"));
            }
            guard = Guard::Answered;
        }
    }
    if kind == Kind::Confirm && !params.iter().any(|(n, _)| n == "answer_on_no") {
        guard = Guard::Yes;
    }
    if !message && kind != Kind::Radial {
        return (Some(kind), guard, Some("no_message"));
    }
    if kind == Kind::Text {
        let has = |n: &str| params.iter().find(|(k, _)| k == n).map(|(_, v)| v.trim().to_string());
        if let Some(ml) = has("max_length") {
            if has("name_text").is_none() && ml != "MAX_NAME_LEN" {
                return (Some(kind), guard, Some("name_text_unknown"));
            }
        }
    }
    (Some(kind), guard, None)
}

pub fn prepare(tree: &Tree, sem: &Sem, excluded: &dyn Fn(&str) -> bool) -> Arc<dyn Any + Send + Sync> {
    let files = tree.select(&CODE_DM);
    let mut sites: Vec<Site> = Vec::new();
    for f in &files {
        let text = f.text();
        if !text.contains("om_ask(") {
            continue;
        }
        let clean = crate::strip::sanitize(text);
        let mut owner_of_line: HashMap<u32, String> = HashMap::new();
        proc_scopes(f.code(), |no, _line, owner, _proc, _locals| {
            owner_of_line.insert(no as u32, owner.to_string());
        });
        for off in scan::call_offsets(&clean, "om_ask") {
            let Ok(node) = scan::scan_call(text, &clean, off, "om_ask") else { continue };
            let line = text[..off].bytes().filter(|b| *b == 10u8).count() as u32 + 1;
            let col = off - text[..off].rfind('\n').map(|p| p + 1).unwrap_or(0);
            let owner = owner_of_line.get(&line).cloned().unwrap_or_default();
            let (kind, guard, mut base) = judge(text, &node, &owner);
            let hline = node.args.get(2).map(|a| text[..a.span.start].bytes().filter(|b| *b == 10u8).count() as u32 + 1).unwrap_or(line);
            let handler = if node.args.len() >= 3 {
                match handler_of(node.args[2].span.text(text), &owner) {
                    Ok(h) => Some(h),
                    Err(why) => {
                        base.get_or_insert(why);
                        None
                    }
                }
            } else {
                None
            };
            let gaps_have_comment = {
                let mut gaps: Vec<&str> = Vec::new();
                if let Some(first) = node.args.first() {
                    gaps.push(&text[node.open + 1..first.span.start]);
                }
                for w in node.args.windows(2) {
                    gaps.push(&text[w[0].span.end..w[1].span.start]);
                }
                if let Some(last) = node.args.last() {
                    gaps.push(&text[last.span.end..node.close]);
                }
                gaps.iter().any(|g| super::helpers::has_comment(g))
            };
            if gaps_have_comment {
                base.get_or_insert("comment_in_call");
            }
            if !starts_line(text, off) {
                base.get_or_insert("value_used");
            }
            sites.push(Site { rel: f.rel.clone(), pos: (line, col), hline, excluded: excluded(&f.rel), kind, guard, handler, base });
        }
    }
    // ---- handlers
    let mut by_key: BTreeMap<HKey, Vec<usize>> = BTreeMap::new();
    for (i, s) in sites.iter().enumerate() {
        if let Some(h) = &s.handler {
            by_key.entry(h.clone()).or_default().push(i);
        }
    }
    let names: HashSet<String> = by_key.keys().map(|k| k.name.clone()).collect();
    let occs = collect_refs(&files, &names);
    let mut defs_by_name: HashMap<String, Vec<DefInfo>> = HashMap::new();
    for ty in sem.objtree.iter_types() {
        let t = ty.get();
        for (pname, p) in &t.procs {
            if !names.contains(pname.as_str()) {
                continue;
            }
            let path = if t.path.is_empty() { "/".to_string() } else { t.path.clone() };
            for v in &p.value {
                if let Some(rel) = sem.file_of(v.location) {
                    defs_by_name.entry(pname.clone()).or_default().push(DefInfo { ty: path.clone(), rel: rel.to_string(), line: v.location.line });
                }
            }
        }
    }
    let texts: HashMap<&str, &SourceFile> = files.iter().map(|f| (f.rel.as_str(), *f)).collect();
    let mut hook_lines: HashSet<(String, u32, String)> = HashSet::new();
    for s in &sites {
        if let Some(h) = &s.handler {
            hook_lines.insert((s.rel.clone(), s.hline, h.name.clone()));
        }
    }
    let mut handlers: HashMap<HKey, HandlerPlan> = HashMap::new();
    for (key, idxs) in &by_key {
        let mut plan = HandlerPlan::default();
        let all_defs = defs_by_name.get(&key.name).cloned().unwrap_or_default();
        plan.defs = all_defs.iter().filter(|d| related(&d.ty, &key.ty)).cloned().collect();
        for &i in idxs {
            let s = &sites[i];
            if s.excluded || s.base.is_some() {
                plan.blocked = true;
                continue;
            }
            match (plan.kind, plan.guard) {
                (None, _) => {
                    plan.kind = s.kind;
                    plan.guard = Some(s.guard);
                }
                (Some(k), Some(g)) if Some(k) == s.kind && g == s.guard => {}
                _ => plan.blocked = true,
            }
        }
        let def_lines: HashSet<(String, u32)> = all_defs.iter().map(|d| (d.rel.clone(), d.line)).collect();
        for o in occs.get(&key.name).map(|v| v.as_slice()).unwrap_or(&[]) {
            if def_lines.contains(&(o.rel.clone(), o.line)) || hook_lines.contains(&(o.rel.clone(), o.line, key.name.clone())) {
                continue;
            }
            let relevant = match &o.kind {
                OccKind::Bare | OccKind::ProcRef(None) => related(&o.owner, &key.ty),
                OccKind::ProcRef(Some(t)) => related(t, &key.ty),
                OccKind::Dot(recv) => recv == "src" && related(&o.owner, &key.ty),
            };
            if relevant {
                plan.blocked = true;
            }
        }
        if plan.defs.is_empty() || plan.kind.is_none() {
            plan.blocked = true;
        }
        if !plan.blocked {
            for d in &plan.defs {
                let ok = !excluded(&d.rel) && texts.get(d.rel.as_str()).map(|f| analyze_def(f.text(), d.line, &key.name, plan.kind.unwrap(), plan.guard.unwrap()).is_ok()).unwrap_or(false);
                if !ok {
                    plan.blocked = true;
                    break;
                }
            }
        }
        handlers.insert(key.clone(), plan);
    }
    let mut decisions: HashMap<(String, u32, usize), Result<(), &'static str>> = HashMap::new();
    for s in &sites {
        let d = if let Some(why) = s.base {
            Err(why)
        } else if let Some(h) = &s.handler {
            if handlers.get(h).map(|p| p.blocked).unwrap_or(true) {
                Err("handler_blocked")
            } else {
                Ok(())
            }
        } else {
            Err("handler_expr")
        };
        decisions.insert((s.rel.clone(), s.pos.0, s.pos.1), d);
    }
    let mut enclosing: HashMap<(String, String), (String, Kind)> = HashMap::new();
    for (key, plan) in &handlers {
        if plan.blocked {
            continue;
        }
        for d in &plan.defs {
            if let Some(f) = texts.get(d.rel.as_str()) {
                if let Ok((_, pname)) = analyze_def(f.text(), d.line, &key.name, plan.kind.unwrap(), plan.guard.unwrap()) {
                    enclosing.insert((d.ty.clone(), key.name.clone()), (pname, plan.kind.unwrap()));
                }
            }
        }
    }
    Arc::new(Prep { decisions, handlers, enclosing })
}

/// The edits that give the handler on line `line` the `(datum/act/request/A)` shape and its guard, or why it cannot.
fn analyze_def(text: &str, line: u32, name: &str, kind: Kind, guard: Guard) -> Result<(Vec<Edit>, String), &'static str> {
    let clean = crate::strip::sanitize(text);
    let nl = if text.contains("\r\n") { "\r\n" } else { "\n" };
    let mut starts: Vec<usize> = vec![0];
    for (i, b) in text.bytes().enumerate() {
        if b == b'\n' {
            starts.push(i + 1);
        }
    }
    let li = (line as usize).checked_sub(1).ok_or("shape")?;
    if li >= starts.len() {
        return Err("shape");
    }
    let line_end = |idx: usize| -> usize {
        let e = if idx + 1 < starts.len() { starts[idx + 1] - 1 } else { text.len() };
        if e > starts[idx] && text.as_bytes()[e - 1] == b'\r' {
            e - 1
        } else {
            e
        }
    };
    let sig_start = starts[li];
    let sig_end = line_end(li);
    let sig = &clean[sig_start..sig_end];
    let p = sig.find(&format!("{}(", name)).ok_or("shape")?;
    let open = sig_start + p + name.len();
    let close = matching_paren(&clean, open).ok_or("shape")?;
    if close >= sig_end {
        return Err("shape");
    }
    let params = split_args(&clean[open + 1..close]);
    if params.len() != 1 || params[0].contains('=') {
        return Err("shape");
    }
    let pname = params[0].trim().trim_start_matches("var/").rsplit('/').next().unwrap_or("").to_string();
    if pname.is_empty() {
        return Err("shape");
    }
    let sig_indent = sig.len() - sig.trim_start().len();
    let mut last = li;
    let mut j = li + 1;
    while j < starts.len() {
        let l = &clean[starts[j]..line_end(j)];
        if l.trim().is_empty() {
            j += 1;
            continue;
        }
        if l.len() - l.trim_start().len() <= sig_indent {
            break;
        }
        last = j;
        j += 1;
    }
    let body_start = starts.get(li + 1).copied().unwrap_or(text.len());
    let body_end = line_end(last);
    let body = if body_end > body_start { &clean[body_start..body_end] } else { "" };
    if !words(body, "A").is_empty() {
        return Err("name_clash");
    }
    let mut edits: Vec<Edit> = Vec::new();
    let bb = body.as_bytes();
    for at in words(body, &pname) {
        let mut k = at + pname.len();
        if k < bb.len() && bb[k] == b'?' {
            k += 1;
        }
        if k >= bb.len() || bb[k] != b'.' {
            return Err("prompt_whole");
        }
        let fs = k + 1;
        let mut fe = fs;
        while fe < bb.len() && is_ident_byte(bb[fe]) {
            fe += 1;
        }
        let field = &body[fs..fe];
        let new = if field == kind.answer_var() {
            "A.answer.answer_value"
        } else if field == "answerer" {
            "A.request.answerer"
        } else {
            return Err("prompt_field");
        };
        edits.push(Edit::replace(Span { start: body_start + at, end: body_start + fe }, new));
    }
    edits.push(Edit::replace(Span { start: open + 1, end: close }, "datum/act/request/A"));
    // The guard goes after the proc's leading settings, indented like the body.
    let is_setting = |t: &str| -> bool {
        let head = t.split('(').next().unwrap_or("");
        ["EVENT_HANDLER", "SHOULD_", "PRIVATE_PROC", "PROTECTED_PROC", "RETURN_TYPE", "CAN_BE_REDEFINED"].iter().any(|p| head.starts_with(p)) && (!t.contains('(') || t.ends_with(')'))
    };
    let mut after = li;
    let mut k = li + 1;
    while k <= last && k < starts.len() {
        let t = clean[starts[k]..line_end(k)].trim();
        if t.is_empty() {
            k += 1;
            continue;
        }
        if is_setting(t) {
            after = k;
            k += 1;
            continue;
        }
        break;
    }
    let first_body = (li + 1..=last.min(starts.len() - 1)).find(|&k| !clean[starts[k]..line_end(k)].trim().is_empty());
    let indent: String = match first_body {
        Some(k) => text[starts[k]..line_end(k)].chars().take_while(|c| *c == ' ' || *c == '\t').collect(),
        None => format!("{}\t", &text[sig_start..sig_start + sig_indent]),
    };
    let cond = match guard {
        Guard::Yes => "!A.answer || !A.answer.answer_value",
        Guard::Answered => "!A.answer",
    };
    let ins = format!("{nl}{indent}if({cond}){nl}{indent}\treturn");
    edits.push(Edit::insert(line_end(after), ins));
    Ok((edits, pname))
}

/// `p.answer` / `p.answerer` of the old prompt parameter `p`, as the new handler reads them (an om_ask written inside a converted handler).
fn translate(text: &str, pname: &str, kind: Kind) -> String {
    let b = text.as_bytes();
    let mut out = String::new();
    let mut at = 0;
    for w in words(text, pname) {
        if w < at {
            continue;
        }
        let mut k = w + pname.len();
        if k < b.len() && b[k] == b'?' {
            k += 1;
        }
        if k >= b.len() || b[k] != b'.' {
            continue;
        }
        let fs = k + 1;
        let mut fe = fs;
        while fe < b.len() && is_ident_byte(b[fe]) {
            fe += 1;
        }
        let field = &text[fs..fe];
        let new = if field == kind.answer_var() {
            "A.answer.answer_value"
        } else if field == "answerer" {
            "A.request.answerer"
        } else {
            continue;
        };
        out.push_str(&text[at..w]);
        out.push_str(new);
        at = fe;
    }
    out.push_str(&text[at..]);
    out
}

fn new_field_value(kind: Kind, name: &str, value: &str) -> (String, String) {
    let new = kind.params().iter().find(|(o, _)| *o == name).map(|(_, n)| *n).unwrap_or(match name {
        "message" => "question",
        other => other,
    });
    (new.to_string(), value.trim().to_string())
}

pub fn rewrite(cx: &Ctx) -> Outcome {
    let Some(prep) = cx.prep.downcast_ref::<Prep>() else { return Outcome::Residue("scan_failed", "no plan".into()) };
    let col = cx.node.name.start - cx.text[..cx.node.name.start].rfind('\n').map(|p| p + 1).unwrap_or(0);
    let Some(decision) = prep.decisions.get(&(cx.rel.to_string(), cx.line, col)) else {
        return Outcome::Residue("scan_failed", "the site was not planned".into());
    };
    if let Err(why) = decision {
        return Outcome::Residue(why, format!("om_ask cannot convert: {}", why));
    }
    let Some(kind) = Kind::of(cx.arg_text(1)) else { return Outcome::Residue("kind_unsupported", String::new()) };
    let Ok(params) = named_params(cx.text, cx.node) else { return Outcome::Residue("argc", String::new()) };
    let outer = prep.enclosing.get(&(cx.owner.to_string(), cx.proc_name.to_string()));
    let tr = |t: &str| -> String {
        match outer {
            Some((p, k)) => translate(t, p, *k),
            None => t.to_string(),
        }
    };
    let translated: Vec<(String, String)> = params.iter().map(|(n, v)| (n.clone(), tr(v))).collect();
    let params: Vec<(String, &str)> = translated.iter().map(|(n, v)| (n.clone(), v.as_str())).collect();
    let mut fields: Vec<(String, String)> = vec![("answerer".into(), tr(cx.arg_text(0).trim()))];
    let get = |n: &str| params.iter().find(|(k, _)| k == n).map(|(_, v)| v.trim().to_string());
    if let Some(t) = get("title") {
        fields.push(("title".into(), t));
    }
    if kind != Kind::Radial || get("message").is_some() {
        fields.push(("question".into(), get("message").unwrap_or_default()));
    }
    let mut flags: Vec<String> = Vec::new();
    for (name, value) in &params {
        match name.as_str() {
            "title" | "message" | "timeout" | "answer_on_no" => continue,
            "ask_flags" => {
                flags.push(value.trim().to_string());
                continue;
            }
            "requires" => {
                if let Some(r) = requires_fields(value) {
                    flags.extend(r.flags.iter().map(|f| f.to_string()));
                    if let Some(x) = r.rights {
                        fields.push(("rights".into(), x));
                    }
                    if let Some(x) = r.usable {
                        fields.push(("usable_state".into(), x));
                    }
                }
                continue;
            }
            _ => {}
        }
        fields.push(new_field_value(kind, name, value));
    }
    if !flags.is_empty() {
        fields.push(("ask_flags".into(), flags.join(" | ")));
    }
    if kind == Kind::Radial {
        fields.push(("radial".into(), "TRUE".into()));
        // the old ring is anchored on the receiver (an atom here) unless told otherwise, and answers a lone choice itself unless told not to
        if get("anchor").is_none() {
            fields.push(("anchor".into(), "src".into()));
        }
        if get("autopick_single_option").is_none() {
            fields.push(("autopick_single_option".into(), "TRUE".into()));
        }
    }
    if kind == Kind::Text && get("name_text").is_none() && get("max_length").as_deref() == Some("MAX_NAME_LEN") {
        fields.push(("name_text".into(), "TRUE".into()));
    }
    fields.push(("timeout".into(), get("timeout").unwrap_or_else(|| "0".into())));
    let args: Vec<String> = fields.iter().map(|(n, v)| format!("{} = {}", n, v)).collect();
    let new = format!("open_request(src, {}, {}, {})", kind.new_type(), cx.arg_text(2).trim(), args.join(", "));
    let follows = match handler_of(cx.arg_text(2), cx.owner) {
        Ok(h) => vec![h.text()],
        Err(_) => Vec::new(),
    };
    Outcome::Rewrite(Rewrite { edits: vec![Edit::replace(cx.node.whole(), new)], follows, ..Default::default() })
}

pub fn follow_edits(root: &Path, prep: &(dyn Any + Send + Sync), follows: &[String]) -> Vec<(String, Vec<Edit>)> {
    let Some(prep) = prep.downcast_ref::<Prep>() else { return Vec::new() };
    let mut by_def: BTreeMap<(String, u32), (String, Kind, Guard)> = BTreeMap::new();
    for k in follows {
        let Some(key) = HKey::parse(k) else { continue };
        let Some(plan) = prep.handlers.get(&key) else { continue };
        let (Some(kind), Some(guard)) = (plan.kind, plan.guard) else { continue };
        for d in &plan.defs {
            by_def.entry((d.rel.clone(), d.line)).or_insert_with(|| (key.name.clone(), kind, guard));
        }
    }
    let mut out: BTreeMap<String, Vec<Edit>> = BTreeMap::new();
    for ((rel, line), (name, kind, guard)) in by_def {
        let Ok(text) = std::fs::read_to_string(root.join(&rel)) else { continue };
        if let Ok((edits, _)) = analyze_def(&text, line, &name, kind, guard) {
            out.entry(rel).or_default().extend(edits);
        }
    }
    out.into_iter().collect()
}

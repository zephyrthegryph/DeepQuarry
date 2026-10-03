//! `om_hook` / `om_unhook` to `observe` / `unobserve`, and the handlers they name to the `then()` shape.
//!
//! ```text
//! om_hook(source, /datum/om/event/x, listener, PROC_REF(h))
//!   -> observe(source, /datum/notice/x, listener, then(PROC_REF(h)))
//! om_unhook(source, /datum/om/event/x, listener)
//!   -> unobserve(source, /datum/notice/x, listener)
//! /type/proc/h(datum/source, datum/om/event/x/event)        /type/proc/h(datum/act/notice/A)
//!     ... source ... event.field ...                    ->      var/datum/source = A.target
//!                                                               var/datum/notice/x/event = A
//!                                                               ... source ... event.field_ ...
//! ```
//!
//! `observe` is the runtime form (`om_hook` hooks at runtime too), so a hook is never turned into a static `on_notice`. The twin notice of
//! each event comes from `tools/dx/codemods/om_event_map.json`: only a map row whose target is a `/datum/notice/` and that does not read
//! `event.result` converts (a `before/` event is a guard, `review` / `delete` / `op` are decisions). An event list is one `observe` per
//! event, which needs a statement. A handler changes signature for ALL its hooks or for none: every site that hooks it must convert, it
//! must have the two-parameter shape, its body may use the event only as `event.field` of the one notice, nothing else may call or
//! reference it, and each override of it (a related type that defines the name) changes the same way. An `om_unhook` converts when every
//! `om_hook` of the same event on a related type does; otherwise the hook it undoes would stay a legacy one.

use std::any::Any;
use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};
use std::path::Path;
use std::sync::Arc;

use super::scan::{self, CallNode};
use super::{Ctx, Edit, Outcome, Rewrite};
use crate::dm::ownership_index::proc_scopes;
use crate::gens::event_twins::{parse as parse_map, Row};
use crate::sem::decls::{matching_paren, split_args};
use crate::sem::Sem;
use crate::tree::{SourceFile, Tree, CODE_DM};

const MAP_TEXT: &str = include_str!("../../../dx/codemods/om_event_map.json");

fn event_map() -> &'static BTreeMap<String, Row> {
    static MAP: std::sync::OnceLock<BTreeMap<String, Row>> = std::sync::OnceLock::new();
    MAP.get_or_init(|| parse_map(MAP_TEXT))
}

/// The row of an event that converts: a notice twin that does not read `event.result`.
fn convertible(event: &str) -> Option<&'static Row> {
    let row = event_map().get(event)?;
    (row.target.starts_with("/datum/notice/") && !row.reads_result).then_some(row)
}

pub(crate) fn related(a: &str, b: &str) -> bool {
    if a.is_empty() || b.is_empty() {
        return true; // an unknown type may be anything
    }
    a == b || a.starts_with(&format!("{}/", b)) || b.starts_with(&format!("{}/", a))
}

/// A hook site as the scan saw it, before the handler is known to be convertible.
#[derive(Clone, Debug)]
struct Site {
    rel: String,
    /// Where the callee starts, as (line, column): offsets differ between the LF text the tree holds and a CRLF file.
    pos: (u32, usize),
    /// The line the handler argument starts on (a call can span lines).
    hline: u32,
    callee: String,
    owner: String,
    excluded: bool,
    /// The om events the call names (a literal path or a `list()` of them), or why it cannot convert.
    events: Result<Vec<String>, &'static str>,
    handler: Option<HKey>,
    /// A reason that holds without looking at the handler.
    base: Option<&'static str>,
}

/// A handler: the type its name resolves on and the proc name.
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

#[derive(Debug, Default)]
struct HandlerPlan {
    notices: BTreeSet<String>,
    defs: Vec<DefInfo>,
    blocked: Option<&'static str>,
}

pub struct Prep {
    /// Final decision per (file, offset of the callee).
    decisions: HashMap<(String, u32, usize), Result<Vec<String>, &'static str>>,
    handlers: HashMap<HKey, HandlerPlan>,
}

fn is_path(s: &str) -> bool {
    s.starts_with("/datum/om/event/") && s.chars().all(|c| c.is_alphanumeric() || c == '_' || c == '/')
}

/// The events an argument names: one path or `list(path, path)`.
fn parse_events(arg: &str) -> Result<Vec<String>, &'static str> {
    let a = arg.trim();
    if is_path(a) {
        return Ok(vec![a.to_string()]);
    }
    if let Some(inner) = a.strip_prefix("list(").and_then(|r| r.strip_suffix(')')) {
        let items = split_args(inner);
        if !items.is_empty() && items.iter().all(|i| is_path(i)) {
            return Ok(items);
        }
    }
    Err("event_not_literal")
}

fn handler_of(arg: &str, owner: &str, listener: &str) -> Result<HKey, &'static str> {
    let a = arg.trim();
    if let Some(name) = a.strip_prefix("PROC_REF(").and_then(|r| r.strip_suffix(')')) {
        let name = name.trim();
        if name.chars().all(|c| c.is_alphanumeric() || c == '_') && !name.is_empty() {
            return if listener.trim() == "src" && !owner.is_empty() { Ok(HKey { ty: owner.to_string(), name: name.to_string() }) } else { Err("listener_not_src") };
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

/// True when the call starts its line (only blanks before it): the form an event list can expand in.
pub(crate) fn starts_line(text: &str, off: usize) -> bool {
    let ls = text[..off].rfind('\n').map(|p| p + 1).unwrap_or(0);
    text[ls..off].chars().all(|c| c == ' ' || c == '\t')
}

/// One mention of a handler name that is not its definition: how it is written and where.
#[derive(Clone, Debug)]
pub(crate) struct Occ {
    pub rel: String,
    pub line: u32,
    pub owner: String,
    pub kind: OccKind,
}

#[derive(Clone, Debug)]
pub(crate) enum OccKind {
    /// `name(...)` with no receiver.
    Bare,
    /// `recv.name(...)`.
    Dot(String),
    /// `PROC_REF(name)` (None) or `TYPE_PROC_REF(/type, name)` (Some).
    ProcRef(Option<String>),
}

pub(crate) fn collect_refs(files: &[&SourceFile], names: &HashSet<String>) -> HashMap<String, Vec<Occ>> {
    let mut alt: Vec<&str> = names.iter().map(|s| s.as_str()).collect();
    alt.sort();
    let alt = alt.join("|");
    let bare = crate::pat::Pat::new(&format!(r"(?<![\w./:])({})\s*\(", alt));
    let dot = crate::pat::Pat::new(&format!(r"([\w.]+)\.({})\s*\(", alt));
    let pref = crate::pat::Pat::new(&format!(r"(?<![\w])PROC_REF\(\s*({})\s*\)", alt));
    let tref = crate::pat::Pat::new(&format!(r"TYPE_PROC_REF\(\s*([\w/]+)\s*,\s*({})\s*\)", alt));
    let mut out: HashMap<String, Vec<Occ>> = HashMap::new();
    for f in files {
        let text = f.text();
        let clean = crate::strip::sanitize(text);
        let mut found: Vec<(usize, String, OccKind)> = Vec::new();
        for m in bare.captures_iter(&clean) {
            found.push((m.start(1), m.s(1).to_string(), OccKind::Bare));
        }
        for m in dot.captures_iter(&clean) {
            found.push((m.start(2), m.s(2).to_string(), OccKind::Dot(m.s(1).to_string())));
        }
        for m in pref.captures_iter(&clean) {
            found.push((m.start(1), m.s(1).to_string(), OccKind::ProcRef(None)));
        }
        for m in tref.captures_iter(&clean) {
            found.push((m.start(2), m.s(2).to_string(), OccKind::ProcRef(Some(m.s(1).to_string()))));
        }
        if found.is_empty() {
            continue;
        }
        let mut owner_of_line: HashMap<u32, String> = HashMap::new();
        proc_scopes(f.code(), |no, _line, owner, _proc, _locals| {
            owner_of_line.insert(no as u32, owner.to_string());
        });
        for (off, name, kind) in found {
            let line = text[..off].bytes().filter(|b| *b == b'\n').count() as u32 + 1;
            let owner = owner_of_line.get(&line).cloned().unwrap_or_default();
            out.entry(name).or_default().push(Occ { rel: f.rel.clone(), line, owner, kind });
        }
    }
    out
}

pub fn prepare(tree: &Tree, sem: &Sem, excluded: &dyn Fn(&str) -> bool) -> Arc<dyn Any + Send + Sync> {
    let files = tree.select(&CODE_DM);
    // ---- every om_hook / om_unhook call, with the type of the proc it sits in
    let mut sites: Vec<Site> = Vec::new();
    for f in &files {
        let text = f.text();
        if !text.contains("om_hook(") && !text.contains("om_unhook(") && !text.contains("om_unhook_all(") {
            continue;
        }
        let clean = crate::strip::sanitize(text);
        let mut owner_of_line: HashMap<u32, String> = HashMap::new();
        proc_scopes(f.code(), |no, _line, owner, _proc, _locals| {
            owner_of_line.insert(no as u32, owner.to_string());
        });
        for callee in ["om_hook", "om_unhook"] {
            for off in scan::call_offsets(&clean, callee) {
                let Ok(node) = scan::scan_call(text, &clean, off, callee) else { continue };
                let line = text[..off].bytes().filter(|b| *b == b'\n').count() as u32 + 1;
                let owner = owner_of_line.get(&line).cloned().unwrap_or_default();
                sites.push(site_of(f.rel.as_str(), text, off, callee, &owner, &node, excluded(&f.rel)));
            }
        }
    }

    // ---- handlers: the definitions, the references, the body shape
    let mut by_key: BTreeMap<HKey, Vec<usize>> = BTreeMap::new();
    for (i, s) in sites.iter().enumerate() {
        if s.callee == "om_hook" {
            if let Some(h) = &s.handler {
                by_key.entry(h.clone()).or_default().push(i);
            }
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
        if s.callee == "om_hook" {
            if let Some(h) = &s.handler {
                hook_lines.insert((s.rel.clone(), s.hline, h.name.clone()));
            }
        }
    }
    let mut handlers: HashMap<HKey, HandlerPlan> = HashMap::new();
    for (key, idxs) in &by_key {
        let mut plan = HandlerPlan::default();
        let all_defs = defs_by_name.get(&key.name).cloned().unwrap_or_default();
        plan.defs = all_defs.iter().filter(|d| related(&d.ty, &key.ty)).cloned().collect();
        for &i in idxs {
            let s = &sites[i];
            if s.excluded {
                plan.blocked.get_or_insert("handler_blocked");
            }
            if let Some(why) = s.base {
                plan.blocked.get_or_insert(why);
                continue;
            }
            if let Ok(evs) = &s.events {
                for e in evs {
                    if let Some(r) = convertible(e) {
                        plan.notices.insert(r.target.clone());
                    }
                }
            }
        }
        // Nothing else may call or reference the handler on a related type: a definition and the hooks we convert are the only mentions.
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
                if std::env::var("DQ_CODEMOD_TRACE").is_ok() {
                    eprintln!("om_hook: handler {} {}: shared ({}:{} {:?})", key.ty, key.name, o.rel, o.line, o.kind);
                }
                plan.blocked.get_or_insert("handler_blocked");
            }
        }
        if plan.defs.is_empty() {
            plan.blocked.get_or_insert("handler_blocked");
        }
        if plan.blocked.is_none() {
            for d in &plan.defs {
                if excluded(&d.rel) {
                    plan.blocked = Some("handler_blocked");
                    break;
                }
                let Some(f) = texts.get(d.rel.as_str()) else {
                    plan.blocked = Some("handler_blocked");
                    break;
                };
                if let Err(why) = analyze_def(f.text(), d.line, &key.name, &plan.notices) {
                    if std::env::var("DQ_CODEMOD_TRACE").is_ok() {
                        eprintln!("om_hook: handler {} {}: {} ({}:{})", key.ty, key.name, why, d.rel, d.line);
                    }
                    plan.blocked = Some("handler_blocked");
                    break;
                }
            }
        }
        handlers.insert(key.clone(), plan);
    }

    // ---- the decision per site
    let mut decisions: HashMap<(String, u32, usize), Result<Vec<String>, &'static str>> = HashMap::new();
    for s in &sites {
        if s.callee != "om_hook" {
            continue;
        }
        let d = if let Some(why) = s.base {
            Err(why)
        } else if let Some(h) = &s.handler {
            match handlers.get(h).and_then(|p| p.blocked) {
                Some(why) => Err(why),
                None => s.events.clone(),
            }
        } else {
            Err("handler_expr")
        };
        decisions.insert((s.rel.clone(), s.pos.0, s.pos.1), d);
    }
    // An unhook converts when each of its events has hooks on related types and all of them convert.
    for s in &sites {
        if s.callee != "om_unhook" {
            continue;
        }
        let d = match &s.events {
            Err(why) => Err(*why),
            Ok(evs) if s.base.is_some() => {
                let _ = evs;
                Err(s.base.unwrap())
            }
            Ok(evs) => {
                let mut verdict: Result<Vec<String>, &'static str> = Ok(evs.clone());
                for e in evs {
                    let hooks: Vec<&Site> = sites.iter().filter(|h| h.callee == "om_hook" && related(&h.owner, &s.owner) && h.events.as_ref().map(|x| x.contains(e)).unwrap_or(false)).collect();
                    if hooks.is_empty() {
                        verdict = Err("unhook_unpaired");
                        break;
                    }
                    if hooks.iter().any(|h| decisions.get(&(h.rel.clone(), h.pos.0, h.pos.1)).map(|d| d.is_err()).unwrap_or(true)) {
                        verdict = Err("unhook_unpaired");
                        break;
                    }
                }
                verdict
            }
        };
        decisions.insert((s.rel.clone(), s.pos.0, s.pos.1), d);
    }
    Arc::new(Prep { decisions, handlers })
}

fn site_of(rel: &str, text: &str, off: usize, callee: &str, owner: &str, node: &CallNode, excluded: bool) -> Site {
    let arg = |i: usize| node.args.get(i).map(|a| a.span.text(text)).unwrap_or("");
    let want = if callee == "om_hook" { 4 } else { 3 };
    let line = text[..off].bytes().filter(|b| *b == b'\n').count() as u32 + 1;
    let hline = node.args.get(3).map(|a| text[..a.span.start].bytes().filter(|b| *b == 10u8).count() as u32 + 1).unwrap_or(line);
    let col = off - text[..off].rfind('\n').map(|p| p + 1).unwrap_or(0);
    let mut site = Site { rel: rel.to_string(), pos: (line, col), hline, callee: callee.to_string(), owner: owner.to_string(), excluded, events: Err("argc"), handler: None, base: None };
    if node.args.len() != want || super::helpers::any_named(&node.args) {
        site.base = Some("argc");
        return site;
    }
    site.events = parse_events(arg(1));
    match &site.events {
        Err(why) => site.base = Some(why),
        Ok(evs) => {
            if !evs.iter().all(|e| convertible(e).is_some()) {
                site.base = Some("event_unmapped");
            } else if evs.len() > 1 && !starts_line(text, off) {
                site.base = Some("list_value_used");
            }
        }
    }
    if callee == "om_hook" {
        match handler_of(arg(3), owner, arg(2)) {
            Ok(h) => site.handler = Some(h),
            Err(why) => {
                site.base.get_or_insert(why);
            }
        }
    }
    site
}

// ---------------------------------------------------------------------------------------------------------
// the handler definition

pub(crate) fn is_ident_byte(b: u8) -> bool {
    b.is_ascii_alphanumeric() || b == b'_'
}

/// The `(offset, len)` of every whole-word `name` in `s`.
pub(crate) fn words(s: &str, name: &str) -> Vec<usize> {
    let b = s.as_bytes();
    let mut out = Vec::new();
    let mut from = 0;
    while let Some(p) = s[from..].find(name) {
        let at = from + p;
        let end = at + name.len();
        let before_ok = at == 0 || !(is_ident_byte(b[at - 1]) || b[at - 1] == b'.' || b[at - 1] == b'/');
        let after_ok = end >= b.len() || !is_ident_byte(b[end]);
        if before_ok && after_ok {
            out.push(at);
        }
        from = end;
    }
    out
}

/// The edits that give the handler defined on line `line` of `text` the `(datum/act/A)` shape for `notices`, or why it cannot.
fn analyze_def(text: &str, line: u32, name: &str, notices: &BTreeSet<String>) -> Result<Vec<Edit>, &'static str> {
    let clean = crate::strip::sanitize(text);
    let crlf = text.contains("\r\n");
    let nl = if crlf { "\r\n" } else { "\n" };
    // Line table.
    let mut starts: Vec<usize> = vec![0];
    for (i, b) in text.bytes().enumerate() {
        if b == b'\n' {
            starts.push(i + 1);
        }
    }
    let li = (line as usize).checked_sub(1).ok_or("handler_blocked")?;
    if li >= starts.len() {
        return Err("handler_blocked");
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
    let needle = format!("{}(", name);
    let p = sig.find(&needle).ok_or("handler_blocked")?;
    let open = sig_start + p + name.len();
    let close = matching_paren(&clean, open).ok_or("handler_blocked")?;
    if close >= sig_end {
        return Err("handler_blocked");
    }
    let params = split_args(&clean[open + 1..close]);
    if params.len() != 2 || params.iter().any(|p| p.contains('=') || p.contains(" as ") || p.contains(" in ")) {
        return Err("shape");
    }
    let split = |p: &str| -> (String, String) {
        let p = p.trim().trim_start_matches("var/");
        match p.rfind('/') {
            Some(i) => (p[..i].to_string(), p[i + 1..].to_string()),
            None => ("datum".to_string(), p.to_string()),
        }
    };
    let (src_type, src_name) = split(&params[0]);
    let (_ev_type, ev_name) = split(&params[1]);
    // Body: the following lines indented deeper than the signature (blank lines included).
    let sig_indent = sig.len() - sig.trim_start().len();
    let mut last = li;
    let mut j = li + 1;
    while j < starts.len() {
        let l = &clean[starts[j]..line_end(j)];
        if l.trim().is_empty() {
            j += 1;
            continue;
        }
        let indent = l.len() - l.trim_start().len();
        if indent <= sig_indent {
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
    // The event: only `event.field` of the one notice.
    let ev_uses = words(body, &ev_name);
    let mut ev_local = String::new();
    if !ev_uses.is_empty() {
        if notices.len() != 1 {
            return Err("multi_notice");
        }
        let target = notices.iter().next().unwrap();
        let row = event_map().values().find(|r| &r.target == target).ok_or("handler_blocked")?;
        let bb = body.as_bytes();
        for at in ev_uses {
            let mut k = at + ev_name.len();
            if k < bb.len() && bb[k] == b'?' {
                k += 1;
            }
            if k >= bb.len() || bb[k] != b'.' {
                return Err("event_whole");
            }
            let fs = k + 1;
            let mut fe = fs;
            while fe < bb.len() && is_ident_byte(bb[fe]) {
                fe += 1;
            }
            let field = &body[fs..fe];
            let Some(idx) = row.fields.iter().position(|f| f == field) else { return Err("field_unknown") };
            let new = row.notice_fields.get(idx).ok_or("handler_blocked")?;
            if new != field {
                edits.push(Edit::replace(scan::Span { start: body_start + fs, end: body_start + fe }, new.clone()));
            }
        }
        ev_local = format!("var/{}/{} = A", target.trim_start_matches('/'), ev_name);
    }
    let mut locals: Vec<String> = Vec::new();
    if !words(body, &src_name).is_empty() {
        locals.push(format!("var/{}/{} = A.target", src_type, src_name));
    }
    if !ev_local.is_empty() {
        locals.push(ev_local);
    }
    edits.push(Edit::replace(scan::Span { start: open + 1, end: close }, "datum/act/notice/A"));
    if !locals.is_empty() {
        // After the proc's leading settings (EVENT_HANDLER, SHOULD_NOT_OVERRIDE(TRUE), PRIVATE_PROC(TRUE) ...: a macro line), which must stay first.
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
        let first_body = (li + 1..=last).find(|&k| !clean[starts[k.min(starts.len() - 1)]..line_end(k.min(starts.len() - 1))].trim().is_empty());
        let indent: String = match first_body {
            Some(k) if k <= last => text[starts[k]..line_end(k)].chars().take_while(|c| *c == ' ' || *c == '\t').collect(),
            _ => format!("{}\t", &text[sig_start..sig_start + sig_indent]),
        };
        let mut ins = String::new();
        for l in &locals {
            ins.push_str(nl);
            ins.push_str(&indent);
            ins.push_str(l);
        }
        edits.push(Edit::insert(line_end(after), ins));
    }
    Ok(edits)
}

// ---------------------------------------------------------------------------------------------------------
// the codemod hooks

pub fn rewrite(cx: &Ctx) -> Outcome {
    if cx.callee == "om_unhook_all" {
        return Outcome::Residue("unhook_all", "om_unhook_all(listener) has no one-call form: unobserve each source".into());
    }
    let Some(prep) = cx.prep.downcast_ref::<Prep>() else { return Outcome::Residue("scan_failed", "no plan".into()) };
    let col = cx.node.name.start - cx.text[..cx.node.name.start].rfind('\n').map(|p| p + 1).unwrap_or(0);
    let Some(decision) = prep.decisions.get(&(cx.rel.to_string(), cx.line, col)) else {
        return Outcome::Residue("scan_failed", "the site was not planned".into());
    };
    let events = match decision {
        Ok(e) => e,
        Err(why) => return Outcome::Residue(why, format!("{} cannot convert: {}", cx.callee, why)),
    };
    let hook = cx.callee == "om_hook";
    let nl = if cx.text.contains("\r\n") { "\r\n" } else { "\n" };
    // A type with a proc of the same name (a mob has the observe verb) would answer instead of the global one.
    let base = if hook { "observe" } else { "unobserve" };
    let new_name_owned = if cx.owner != "/" && cx.sem.proc_ref(cx.owner, base).map(|p| !p.ty().get().path.is_empty()).unwrap_or(false) { format!("global.{}", base) } else { base.to_string() };
    let new_name = new_name_owned.as_str();
    let a = &cx.node.args;
    let handler_text = if hook { cx.arg_text(3).to_string() } else { String::new() };
    let call = |notice: &str| -> String {
        if hook {
            format!("{}({}, {}, {}, then({}))", new_name, cx.arg_text(0), notice, cx.arg_text(2), handler_text)
        } else {
            format!("{}({}, {}, {})", new_name, cx.arg_text(0), notice, cx.arg_text(2))
        }
    };
    let notice_of = |e: &String| convertible(e).map(|r| r.target.clone()).unwrap_or_default();
    let mut edits: Vec<Edit> = Vec::new();
    if events.len() == 1 {
        edits.push(Edit::replace(cx.node.name, new_name));
        edits.push(Edit::replace(a[1].span, notice_of(&events[0])));
        if hook {
            edits.push(Edit::insert(a[3].span.start, "then("));
            edits.push(Edit::insert(a[3].span.end, ")"));
        }
    } else {
        let ls = cx.text[..cx.node.name.start].rfind('\n').map(|p| p + 1).unwrap_or(0);
        let indent = &cx.text[ls..cx.node.name.start];
        let lines: Vec<String> = events.iter().map(|e| call(&notice_of(e))).collect();
        edits.push(Edit::replace(cx.node.whole(), lines.join(&format!("{}{}", nl, indent))));
    }
    let follows = if hook { prep_follow_key(cx) } else { Vec::new() };
    Outcome::Rewrite(Rewrite { edits, follows, ..Default::default() })
}

fn prep_follow_key(cx: &Ctx) -> Vec<String> {
    match handler_of(cx.arg_text(3), cx.owner, cx.arg_text(2)) {
        Ok(h) => vec![h.text()],
        Err(_) => Vec::new(),
    }
}

pub fn follow_edits(root: &Path, prep: &(dyn Any + Send + Sync), follows: &[String]) -> Vec<(String, Vec<Edit>)> {
    let Some(prep) = prep.downcast_ref::<Prep>() else { return Vec::new() };
    // One edit set per definition, over the union of the notices of every key that reaches it.
    let mut by_def: BTreeMap<(String, u32), (String, BTreeSet<String>)> = BTreeMap::new();
    for k in follows {
        let Some(key) = HKey::parse(k) else { continue };
        let Some(plan) = prep.handlers.get(&key) else { continue };
        for d in &plan.defs {
            let e = by_def.entry((d.rel.clone(), d.line)).or_insert_with(|| (key.name.clone(), BTreeSet::new()));
            e.1.extend(plan.notices.iter().cloned());
        }
    }
    let mut out: BTreeMap<String, Vec<Edit>> = BTreeMap::new();
    for ((rel, line), (name, notices)) in by_def {
        let Ok(text) = std::fs::read_to_string(root.join(&rel)) else { continue };
        if let Ok(edits) = analyze_def(&text, line, &name, &notices) {
            out.entry(rel).or_default().extend(edits);
        }
    }
    out.into_iter().collect()
}

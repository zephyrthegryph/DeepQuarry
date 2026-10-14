//! Port of `tools/ci/sys_rules/appearance.py` (doc/rewrite/systems.md section 1): appearance keyed on
//! declared state.
//!
//! A declared field's setter refreshes the appearance by itself, so a manual `update_icon()` next to
//! a field write is the old pattern (`update_icon_call`), an `update_icon()` override must be
//! declared instead (`update_icon_override`, kept by `// ALLOW(sys_update_icon): reason`), and an
//! `appearance_overlays()` provider returns overlays and changes no state (`appearance_proc_*`).
//!
//! Quirks kept from the Python (do not fix here):
//!   * proc bodies come from the CODE view, where string contents are blanked, so the `OM_SET`
//!     pattern (`om_set(E, "field", v)`) can never match its quoted field name;
//!   * `APPEARANCE_NONE(/type)` with no trailing comma does not match `DECL` (its `$` needs the line
//!     to end after the type), so it never clears inherited watches;
//!   * `ALLOW(sys_update_icon)` keeps only `update_icon_override` sites (not the other rules);
//!   * when two declarations canonicalize to one type the later one wins (`_canon_decls`).

use std::collections::{BTreeSet, HashMap, HashSet};

use crate::dm::field_write::{canon, char_window, local_or_member, norm, proc_def, typed_names, FwlIndex, Locals};
use crate::dm::sys::{register_module, SysModule};
use crate::incr;
use crate::lint::{Registry, RuleMeta};
use crate::pat::Pat;
use crate::pat;
use crate::tree::{SourceFile, Tree};
use crate::util::{is_py_space, py_rstrip, py_strip};

const RULES: &[RuleMeta] = &[
    RuleMeta {
        name: "update_icon_call",
        hint: "delete it: a declared field's setter refreshes the appearance (APPEARANCE_WATCH the field for a procedural update_icon(); systems.md section 1)",
    },
    RuleMeta {
        name: "appearance_proc_overlays",
        hint: "return the overlays from appearance_overlays(); the runtime owns cut/add (systems.md section 1)",
    },
    RuleMeta {
        name: "appearance_proc_state",
        hint: "a provider draws, it changes no state: move the setter to where the state changes (systems.md section 1)",
    },
    RuleMeta {
        name: "update_icon_override",
        hint: "declare the appearance (APPEARANCE_TEMPLATE/LEVEL/EMISSIVE/SLOT, DECLARE_APPEARANCE); genuinely procedural drawing keeps `// ALLOW(sys_update_icon): <reason>` (systems.md section 1)",
    },
];

const RUNTIME: &[&str] = &["code/datums/sys/appearance.dm", "code/__defines/sys_appearance.dm"];
const LIFECYCLE: &[&str] = &["Initialize", "New", "LateInitialize", "Destroy", "on_materialize", "on_dematerialize"];
const HARMLESS_CALLS: &[&str] = &[
    "to_chat", "visible_message", "audible_message", "balloon_alert", "balloon_alert_to_viewers",
    "playsound", "play_sfx", "log_game", "log_admin", "log_and_message_admins", "message_admins",
    "investigate_log", "add_fingerprint", "use_power", "use_power_oneoff", "MACHINE_WAKE",
    "changed", "SStgui.update_uis", "update_uis", "say", "atom_say", "flick", "add_hiddenprint",
];

/// `split_args`: top-level comma split of a macro argument list, stopping at the closing paren.
fn split_args(text: &str) -> Vec<String> {
    let mut args = Vec::new();
    let mut depth: i32 = 0;
    let mut cur = String::new();
    for ch in text.chars() {
        if "([{".contains(ch) {
            depth += 1;
        } else if ")]}".contains(ch) {
            if depth == 0 {
                args.push(py_strip(&cur).to_string());
                return args;
            }
            depth -= 1;
        }
        if ch == ',' && depth == 0 {
            args.push(py_strip(&cur).to_string());
            cur.clear();
            continue;
        }
        cur.push(ch);
    }
    args.push(py_strip(&cur).to_string());
    args
}

struct Reg {
    owner: String,
    field: String,
    raises: bool,
}

/// `(field arg index, channel arg index, has setters, flag setters)` of a registration macro.
fn shape(macro_name: &str) -> (usize, usize, bool, bool) {
    match macro_name {
        "OM_FIELD" => (1, 3, true, false),
        "OM_FIELD_TYPED" => (2, 4, true, false),
        "OM_FLAG_FIELD" | "OM_FLAG_FIELD_BITS" => (1, 3, true, true),
        "OM_FIELD_SETTER" => (1, 2, true, false),
        _ => (1, 2, false, false), // OM_DERIVE_FIELD
    }
}

#[derive(Default)]
struct Setters {
    /// setter proc name -> registrations, plus names in first-seen order.
    map: HashMap<String, Vec<Reg>>,
    order: Vec<String>,
}

/// One setter registration: `(setter name, owner, field, raises)`.
type RegFact = (String, String, String, bool);

/// The setter registrations of one file, in line order (one entry per generated setter name).
fn registrations_of(f: &SourceFile) -> Vec<RegFact> {
    let mut out = Vec::new();
    if f.rel == "code/__defines/om.dm" {
        return out;
    }
    for line in f.raw().lines() {
        if !line.contains("OM_") {
            continue;
        }
        let Some(m) = pat!(r"\A(?:\s*(OM_FIELD|OM_FIELD_TYPED|OM_FLAG_FIELD|OM_FLAG_FIELD_BITS|OM_FIELD_SETTER|OM_DERIVE_FIELD)\((.*)$)").captures(line) else {
            continue;
        };
        let (fi, ci, has_setter, flag) = shape(m.s(1));
        let args = split_args(m.s(2));
        if args.len() <= fi.max(ci) || !has_setter {
            continue;
        }
        let (owner, field, channel) = (&args[0], &args[fi], &args[ci]);
        let raises = !(channel == "0" || channel.is_empty());
        let mut names = vec![format!("set_{}", field)];
        if flag {
            names.push(format!("{}_add", field));
            names.push(format!("{}_remove", field));
        }
        for name in names {
            out.push((name, owner.clone(), field.clone(), raises));
        }
    }
    out
}

fn registrations(per_file: &[&Vec<RegFact>]) -> Setters {
    let mut s = Setters::default();
    for regs in per_file {
        for (name, owner, field, raises) in regs.iter() {
            if !s.map.contains_key(name) {
                s.order.push(name.clone());
            }
            s.map.entry(name.clone()).or_default().push(Reg { owner: owner.clone(), field: field.clone(), raises: *raises });
        }
    }
    s
}

/// type -> (clears inherited, names its appearance declarations read or watch), in first-seen order.
struct Decls {
    entries: Vec<(String, bool, HashSet<String>)>,
    /// canonical type path -> entry index (later declarations overwrite).
    canon: HashMap<String, usize>,
}

/// One appearance declaration line: `(kind, owner, text after the owner's comma)`.
type WatchEvent = (String, String, String);

fn watch_events_of(f: &SourceFile) -> Vec<WatchEvent> {
    let mut out = Vec::new();
    for line in f.raw().lines() {
        if !line.contains("APPEARANCE") {
            continue;
        }
        let Some(m) = pat!(r"\A(?:\s*(APPEARANCE_WATCH|APPEARANCE_TEMPLATE|APPEARANCE_LEVEL|APPEARANCE_EMISSIVE|DECLARE_APPEARANCE|APPEARANCE_NONE)\(\s*(/[\w/]+)\s*(?:,(.*))?$)").captures(line) else {
            continue;
        };
        out.push((m.s(1).to_string(), m.s(2).to_string(), m.s(3).to_string()));
    }
    out
}

fn watches(per_file: &[&Vec<WatchEvent>]) -> Decls {
    let mut entries: Vec<(String, bool, HashSet<String>)> = Vec::new();
    let mut at: HashMap<String, usize> = HashMap::new();
    for events in per_file {
        for (kind, owner, rest) in events.iter() {
            let (kind, owner, rest) = (kind.as_str(), owner.as_str(), rest.as_str());
            let idx = *at.entry(owner.to_string()).or_insert_with(|| {
                entries.push((owner.to_string(), false, HashSet::new()));
                entries.len() - 1
            });
            if kind == "APPEARANCE_NONE" {
                entries[idx].1 = true;
                entries[idx].2 = HashSet::new();
                continue;
            }
            let args = split_args(rest);
            let first = args.first().map(|s| s.as_str()).unwrap_or("");
            if kind == "APPEARANCE_WATCH" {
                for c in pat!(r#""(\w+)""#).captures_iter(first) {
                    entries[idx].2.insert(c.s(1).to_string());
                }
            } else if kind == "APPEARANCE_TEMPLATE" {
                for c in pat!(r"\{\s*(\w+)\s*(?:\?[^}]*)?\}").captures_iter(first) {
                    if c.s(1) != "initial" {
                        entries[idx].2.insert(c.s(1).to_string());
                    }
                }
            } else if !args.is_empty() {
                let name = py_strip(&args[0]).trim_matches('"');
                if pat!(r"\A(?:\w+$)").is_match(name) && name != "null" {
                    entries[idx].2.insert(name.to_string());
                }
                if kind == "APPEARANCE_LEVEL" && args.len() > 2 {
                    for c in pat!(r"\{\s*(\w+)\s*(?:\?[^}]*)?\}").captures_iter(&args[2]) {
                        if c.s(1) != "initial" {
                            entries[idx].2.insert(c.s(1).to_string());
                        }
                    }
                }
            }
        }
    }
    let mut canon_map = HashMap::new();
    for (i, (t, _, _)) in entries.iter().enumerate() {
        canon_map.insert(canon(t), i);
    }
    Decls { entries, canon: canon_map }
}

impl Decls {
    /// True when `field` is read or watched by the appearance of `recv_type` (None: any type).
    fn watched(&self, recv_type: Option<&str>, field: &str) -> bool {
        let Some(recv) = recv_type else {
            return self.entries.iter().any(|(_, _, names)| names.contains(field));
        };
        let mut path = canon(recv);
        let mut chain = Vec::new();
        loop {
            chain.push(path.clone());
            if path.matches('/').count() <= 1 {
                break;
            }
            path = path.rsplit_once('/').unwrap().0.to_string();
        }
        for p in chain {
            let Some(&i) = self.canon.get(&p) else { continue };
            let entry = &self.entries[i];
            if entry.2.contains(field) {
                return true;
            }
            if entry.1 {
                return false;
            }
        }
        false
    }
}

fn descends(child: &str, parent: &str) -> bool {
    let (c, p) = (canon(child), canon(parent));
    c == p || c.starts_with(&format!("{}/", p))
}

/// True when setter `name` on a receiver of `recv_type` (None: unknown) raises a channel and the
/// receiver's appearance reads or watches the field, so the setter refreshes it.
fn capable(setters: &Setters, decls: &Decls, name: &str, recv_type: Option<&str>) -> bool {
    let Some(regs) = setters.map.get(name) else { return false };
    if regs.is_empty() {
        return false;
    }
    regs.iter()
        .filter(|r| recv_type.map(|t| descends(t, &r.owner)).unwrap_or(true))
        .any(|r| r.raises && decls.watched(recv_type, &r.field))
}

fn norm_recv(recv: Option<&str>) -> String {
    match recv {
        None | Some("") | Some("src") => "src".to_string(),
        Some(r) => r.strip_prefix("src.").unwrap_or(r).to_string(),
    }
}

fn receiver_type(index: &FwlIndex, owner: &str, locals: &Locals, recv: &str) -> Option<String> {
    if recv == "src" {
        return Some(owner.to_string());
    }
    let head = recv.split('.').next().unwrap().trim_end_matches('?');
    if recv.contains('.') {
        let (init, last) = recv.rsplit_once('.').unwrap();
        return index.chain_type(owner, locals, &format!("{}.", init), last);
    }
    local_or_member(index, locals, owner, head)
}

/// A proc found in a file's code view.
struct Proc<'a> {
    owner: String,
    name: String,
    args: &'a str,
    start: usize,
    body: Vec<(usize, &'a str)>,
}

fn procs<'a>(f: &'a SourceFile) -> Vec<Proc<'a>> {
    let mut out = Vec::new();
    let mut cur: Option<Proc<'a>> = None;
    for (no, line) in f.code().numbered() {
        if let Some(ch) = line.chars().next() {
            if !is_py_space(ch) {
                if let Some(p) = cur.take() {
                    out.push(p);
                }
                if let Some(m) = proc_def(line) {
                    // `m.params` borrows from `line` (a slice of the code view): re-slice for the lifetime.
                    let args: &'a str = &line[line.len() - m.params.len()..];
                    let mut p = Proc { owner: norm(&m.owner), name: m.name, args, start: no, body: Vec::new() };
                    let rest = match args.split_once(')') {
                        Some((_, r)) => r,
                        None => "",
                    };
                    if !py_strip(rest).is_empty() {
                        p.body.push((no, rest));
                    }
                    cur = Some(p);
                }
                continue;
            }
        }
        if let Some(p) = cur.as_mut() {
            p.body.push((no, line));
        }
    }
    if let Some(p) = cur.take() {
        out.push(p);
    }
    out
}

struct Parsed<'a> {
    rel: &'a str,
    proc: Proc<'a>,
    setter_lines: HashMap<usize, HashSet<String>>,
    is_setter: bool,
}

struct Pats {
    setter: Option<Pat>,
    harmless: Pat,
}

fn indent_of(line: &str) -> usize {
    line.chars().take_while(|c| *c == '\t' || *c == ' ').count()
}

const CALL_DOTTED: &str = r"((?:\w+\??\.)*\w+)\??\.(?:update_icon|queue_icon_update)\s*\(";
const CALL_BARE: &str = r"(?<![\w.?])(?:update_icon|queue_icon_update)\s*\(";

fn is_call_line(line: &str) -> bool {
    pat!(CALL_BARE).is_match(line) || pat!(CALL_DOTTED).is_match(line)
}

/// TRUE when the refresh at `body[index]` follows a watched-field setter on `recv` and nothing on
/// the way could change what is drawn (see the Python docstring).
fn after_setter(pats: &Pats, body: &[(usize, &str)], index: usize, recv: &str, setter_lines: &HashMap<usize, HashSet<String>>) -> bool {
    let scope = indent_of(body[index].1);
    let mut seen_nested = false;
    let mut i = index as isize - 1;
    while i >= 0 {
        let (no, line) = body[i as usize];
        i -= 1;
        if py_strip(line).is_empty() {
            continue;
        }
        let depth = indent_of(line);
        if depth < scope {
            break;
        }
        if let Some(receivers) = setter_lines.get(&no) {
            if receivers.contains(recv) {
                if depth == scope {
                    return true;
                }
                seen_nested = true;
            }
            continue;
        }
        if is_call_line(line) {
            continue; // another receiver's refresh
        }
        if pat!(r"\A(?:\s*(?:if\s*\(.*\)|else(?:\s+if\s*\(.*\))?|for\s*\(.*\)|while\s*\(.*\)|switch\s*\(.*\)|do|spawn\s*\(.*\))\s*$)").is_match(line)
            || pat!(r"\A(?:\s*var/)").is_match(line)
            || pat!(r"\A(?:\s*\.\s*=)").is_match(line)
            || pats.harmless.is_match(line)
        {
            continue;
        }
        if depth > scope && pat!(r"\A(?:\s*return\b)").is_match(line) {
            continue; // that branch never reaches the refresh
        }
        return false;
    }
    seen_nested
}

/// Everything pass 1 reads besides the file: the shared index and the merged registrations.
struct Ctx<'a> {
    index: &'a FwlIndex,
    setters: Setters,
    decls: Decls,
    pats: Pats,
}

/// Pass 1 for one file: the watched-field writes per line, per proc.
fn parse_file<'a>(cx: &Ctx, f: &'a SourceFile) -> Vec<Parsed<'a>> {
    let (index, setters, decls, pats) = (cx.index, &cx.setters, &cx.decls, &cx.pats);
    let mut out = Vec::new();
    for p in procs(f) {
        let mut locals = Locals::new();
        for tm in typed_names(p.args) {
            locals.insert(tm.name, Some(norm(&tm.ty)));
        }
        let mut setter_lines: HashMap<usize, HashSet<String>> = HashMap::new();
        for &(no, line) in &p.body {
            for tm in typed_names(line) {
                if char_window(line, tm.start, 4, 4).contains("var/") {
                    locals.insert(tm.name, Some(norm(&tm.ty)));
                }
            }
            if let Some(sp) = &pats.setter {
                if line.contains("set_") || line.contains("_add") || line.contains("_remove") {
                    for c in setter_matches(sp, line) {
                        if py_rstrip(&line[..c.start(2)]).ends_with("proc/") {
                            continue;
                        }
                        let recv = norm_recv(c.get(1));
                        let rt = receiver_type(index, &p.owner, &locals, &recv);
                        if capable(setters, decls, c.s(2), rt.as_deref()) {
                            setter_lines.entry(no).or_default().insert(recv);
                        }
                    }
                }
            }
            if line.contains("om_set") {
                for c in pat!(r#"\bom_set\(\s*([\w.]+)\s*,\s*"(\w+)""#).captures_iter(line) {
                    let recv = norm_recv(c.get(1));
                    let rt = receiver_type(index, &p.owner, &locals, &recv);
                    if capable(setters, decls, &format!("set_{}", c.s(2)), rt.as_deref()) {
                        setter_lines.entry(no).or_default().insert(recv);
                    }
                }
            }
        }
        let is_setter = setters.map.contains_key(&p.name) && capable(setters, decls, &p.name, Some(&p.owner));
        out.push(Parsed { rel: f.rel.as_str(), proc: p, setter_lines, is_setter });
    }
    out
}

/// The `(canonical owner, proc)` pairs a file's procs contribute to the owning set.
fn owning_of(parsed_file: &[Parsed]) -> Vec<(String, String)> {
    let mut out = Vec::new();
    for parsed in parsed_file {
        let writes_src = parsed.setter_lines.values().any(|r| r.contains("src"));
        if (writes_src || parsed.is_setter) && !LIFECYCLE.contains(&parsed.proc.name.as_str()) {
            out.push((canon(&parsed.proc.owner), parsed.proc.name.clone()));
        }
    }
    out
}

fn judge_parsed(pats: &Pats, owning: &HashSet<(String, String)>, parsed_file: &[Parsed]) -> Vec<(&'static str, String, usize)> {
    let inherits = |owner: &str, name: &str| -> bool {
        let mut path = canon(owner);
        while path.matches('/').count() > 1 {
            path = path.rsplit_once('/').unwrap().0.to_string();
            if owning.contains(&(path.clone(), name.to_string())) {
                return true;
            }
        }
        false
    };
    let mut out: Vec<(&'static str, String, usize)> = Vec::new();
    for parsed in parsed_file {
        let rel = parsed.rel;
        let (owner, name) = (parsed.proc.owner.as_str(), parsed.proc.name.as_str());
        if name == "update_icon" && !RUNTIME.contains(&rel) && owner != "/atom" {
            // The sys_update_icon alias is applied by the module wrapper (allow_extra).
            out.push(("update_icon_override", rel.to_string(), parsed.proc.start));
        }
        if name == "appearance_overlays" && !RUNTIME.contains(&rel) {
            for &(no, line) in &parsed.proc.body {
                if pat!(r"(?<![\w.])(?:src\.)?(?:add_overlay|cut_overlays?|copy_overlays)\s*\(|(?<![\w.])(?:src\.)?overlays\s*(?:[-+]?=(?!=)|\.Cut\()").is_match(line) {
                    out.push(("appearance_proc_overlays", rel.to_string(), no));
                }
                if parsed.setter_lines.contains_key(&no) || pat!(r#"\bom_set\(\s*([\w.]+)\s*,\s*"(\w+)""#).is_match(line) {
                    out.push(("appearance_proc_state", rel.to_string(), no));
                }
            }
        }
        if RUNTIME.contains(&rel) || LIFECYCLE.contains(&name) {
            continue;
        }
        // A setter-owning proc: a watched field's own setter, or an override that calls ..()
        // into an ancestor's proc of the same name that writes one.
        let inherited = inherits(owner, name);
        let mut owns = parsed.is_setter;
        for (index, &(no, line)) in parsed.proc.body.iter().enumerate() {
            if inherited && pat!(r"\A(?:\s*(?:\.\s*=\s*\.\.\(|\.\.\(|if\s*\(\s*\(?\s*(?:\.\s*=\s*)?\.\.\())").is_match(line) {
                owns = true;
            }
            if !line.contains("update_icon") && !line.contains("queue_icon_update") {
                continue; // no call shape can match
            }
            let mut hits: Vec<String> = Vec::new();
            for cm in pat!(r"(?:CALLBACK|INVOKE_ASYNC|om_after\w*|addtimer)\s*\(\s*(?:CALLBACK\s*\(\s*)?([\w.]+)\s*,[^\n]*?PROC_REF\s*\((?:[\w/]+\s*,\s*)?(?:update_icon|queue_icon_update)\s*\)").captures_iter(line) {
                hits.push(norm_recv(cm.get(1)));
            }
            if hits.is_empty() {
                for cm in pat!(CALL_DOTTED).captures_iter(line) {
                    hits.push(norm_recv(cm.get(1)));
                }
                for cm in pat!(CALL_BARE).captures_iter(line) {
                    if py_rstrip(&line[..cm.start(0)]).ends_with("proc/") {
                        continue;
                    }
                    hits.push("src".to_string());
                }
            }
            for recv in hits {
                let in_line = parsed.setter_lines.get(&no).map(|s| s.contains(&recv)).unwrap_or(false);
                if (recv == "src" && owns) || in_line || after_setter(pats, &parsed.proc.body, index, &recv, &parsed.setter_lines) {
                    out.push(("update_icon_call", rel.to_string(), no));
                    break;
                }
            }
        }
    }
    out
}

fn files_scan(tree: &Tree, files: &[&SourceFile]) -> Vec<(&'static str, String, usize)> {
    let index = FwlIndex::get(tree);
    let regs = incr::facts("sys-appearance-regs", files, registrations_of);
    let events = incr::facts("sys-appearance-watches", files, watch_events_of);
    let setters = registrations(&regs.iter().collect::<Vec<_>>());
    let decls = watches(&events.iter().collect::<Vec<_>>());
    let names: Vec<&String> = {
        let mut v: Vec<&String> = setters.order.iter().collect();
        v.sort_by(|a, b| b.chars().count().cmp(&a.chars().count()));
        v
    };
    let pats = Pats {
        setter: if names.is_empty() {
            None
        } else {
            // The Python's `(?<![\w])` before the name is checked by hand in `setter_matches`.
            Some(Pat::new(&format!(
                r"(?:((?:\w+\??\.)*\w+)\??\.)?({})\s*\(",
                names.iter().map(|s| s.as_str()).collect::<Vec<_>>().join("|")
            )))
        },
        harmless: Pat::new(&format!(
            r"\A(?:\s*(?:(?:src|user|usr|\w+)\.)?(?:{})\s*\(.*\)\s*$)",
            HARMLESS_CALLS.iter().map(|c| regex::escape(c)).collect::<Vec<_>>().join("|")
        )),
    };
    // What pass 1 can read: every registration and declaration, the typed members and globals.
    let key1 = incr::mix(&[incr::ctx_key(&(&regs, &events)), index.ctx_key(Some(&[]))]);
    let cx = Ctx { index: &index, setters, decls, pats };

    // Pass 1 per file, reduced to the owning pairs each file contributes.
    let owning_per: Vec<Vec<(String, String)>> = incr::keyed("sys-appearance-owning", key1, files, |f| owning_of(&parse_file(&cx, f)));
    let owning: HashSet<(String, String)> = owning_per.into_iter().flatten().collect();
    let key2 = incr::mix(&[key1, incr::ctx_key(&owning.iter().collect::<BTreeSet<_>>())]);
    let results = incr::keyed("sys-appearance-judge", key2, files, |f| {
        judge_parsed(&cx.pats, &owning, &parse_file(&cx, f))
            .into_iter()
            .map(|(rule, _, line)| (RULES.iter().position(|r| r.name == rule).unwrap_or(0) as u8, line as u32))
            .collect::<Vec<(u8, u32)>>()
    });
    let mut out = Vec::new();
    for (f, v) in files.iter().zip(results) {
        for (rule, line) in v {
            out.push((RULES[rule as usize].name, f.rel.clone(), line as usize));
        }
    }
    out
}

/// `setter_re.finditer(line)` with its `(?<![\w])` before the name: a match with no receiver whose
/// name follows a word character is rejected and the scan resumes one character on.
fn setter_matches<'h>(pat: &Pat, line: &'h str) -> Vec<crate::pat::Caps<'h>> {
    let mut out = Vec::new();
    let mut pos = 0;
    while pos <= line.len() {
        let Some(c) = pat.captures_at(line, pos) else { break };
        let (s, e) = c.groups[0].unwrap();
        if !c.matched(1) {
            if let Some(prev) = line[..c.start(2)].chars().next_back() {
                if prev.is_alphanumeric() || prev == '_' {
                    pos = s + line[s..].chars().next().map(|ch| ch.len_utf8()).unwrap_or(1);
                    continue;
                }
            }
        }
        pos = if e == s { e + line[e..].chars().next().map(|ch| ch.len_utf8()).unwrap_or(1) } else { e };
        out.push(c);
    }
    out
}

pub fn register(reg: &mut Registry) {
    register_module(
        reg,
        SysModule {
            name: "appearance",
            rules: RULES,
            allow_extra: &["update_icon"],
            allow_extra_rules: &["update_icon_override"],
            files_scan: Some(files_scan),
            ..SysModule::DEFAULT
        },
    );
}

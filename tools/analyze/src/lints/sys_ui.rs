//! Port of `tools/ci/sys_rules/ui.py` (doc/rewrite/systems.md section 3): the declared UI model.
//!
//! `tgui_interact()` / `tgui_act()` / `tgui_data()` / `tgui_state()` overrides, hand-opened tgui
//! windows, and every shape of raw `params` parsing in the tgui message path.

use std::collections::{BTreeMap, BTreeSet};

use serde::{Deserialize, Serialize};

use crate::dm::sys::{register_module, SysModule};
use crate::incr;
use crate::lint::{Registry, RuleMeta};
use crate::pat::Pat;
use crate::tree::{SourceFile, Tree};
use crate::util::{is_py_space, py_strip};
use crate::{pat, pat_match};

const RULES: &[RuleMeta] = &[
    RuleMeta {
        name: "tgui_interact_boilerplate",
        hint: "declare the window with DECLARE_UI(type, interface, opts...) and the ui_prepare/ui_redirect/ui_opening/ui_title/ui_interface hooks instead of a tgui_interact() override or a hand-opened /datum/tgui (doc/rewrite/systems.md section 3)",
    },
    RuleMeta {
        name: "ui_act_dispatch",
        hint: "one UI_ACT(type, action, handler, args...) row per action (UI_ACT_FORWARD to hand unknown actions to another datum, UI_ACT_NESTED / UI_SUBACT for nested ones) instead of a tgui_act() override",
    },
    RuleMeta {
        name: "tgui_data_override",
        hint: "declare the window's data with UI_DATA(type, \"var\", \"key=var\", \"proc:getter\", \"merge:getter{key:type,...}\") instead of a tgui_data() override",
    },
    RuleMeta {
        name: "tgui_state_override",
        hint: "declare a state every instance shares with DECLARE_UI_STATE(type, state) instead of a tgui_state() override that returns it",
    },
    RuleMeta {
        name: "text2num_params",
        hint: "declare the arg on the UI_ACT row (UI_ARG_NUM/INT/TEXT/BOOL/CHOICE/REF/PATH/LIST/VALUE) and read the typed params[name] in the handler; never parse raw params",
    },
];

/// Where windows are legitimately built by hand: the tgui core and the declared-UI runtime.
const OPEN_EXEMPT: &[&str] =
    &["code/modules/tgui/", "code/modules/tgui_input/", "code/controllers/subsystems/tgui.dm", "code/datums/sys/ui.dm"];

/// The vendored TGS DMAPI: its `params` are world.Topic query strings, never a tgui message.
const NOT_TGUI: &[&str] = &["code/modules/tgs/"];

fn starts_any(rel: &str, prefixes: &[&str]) -> bool {
    prefixes.iter().any(|p| rel.starts_with(p))
}

/// (callee, top-level argument text with nested calls blanked) for every call in `code`, nested
/// calls included. A nested call's `(` and contents drop out, its closing `)` stays (quirk).
fn calls_of(code: &str) -> Vec<(String, String)> {
    let b = code.as_bytes();
    let mut out = Vec::new();
    for c in pat!(r"\b(\w+)\s*\(").captures_iter(code) {
        let callee = c.s(1).to_string();
        let mut depth = 1i32;
        let mut i = c.end(0);
        let mut buf: Vec<u8> = Vec::new();
        while i < b.len() && depth != 0 {
            let ch = b[i];
            if ch == b'(' {
                depth += 1;
            } else if ch == b')' {
                depth -= 1;
                if depth == 0 {
                    break;
                }
            }
            if depth == 1 {
                buf.push(ch);
            }
            i += 1;
        }
        out.push((callee, String::from_utf8_lossy(&buf).into_owned()));
    }
    out
}

/// The line without its `//` comment and with string literal contents blanked.
fn code_of(line: &str) -> String {
    let b = line.as_bytes();
    let mut out: Vec<u8> = Vec::new();
    let mut quote = false;
    let mut i = 0;
    while i < b.len() {
        let c = b[i];
        if quote {
            if c == b'\\' {
                i += 2;
                continue;
            }
            if c == b'"' {
                quote = false;
                out.push(c);
            }
        } else {
            if b[i..].starts_with(b"//") {
                break;
            }
            out.push(c);
            if c == b'"' {
                quote = true;
            }
        }
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

/// The line without its `//` comment (strings kept).
fn strip_comment(line: &str) -> &str {
    let b = line.as_bytes();
    let mut quote = false;
    let mut i = 0;
    while i < b.len() {
        let c = b[i];
        if quote {
            if c == b'\\' {
                i += 2;
                continue;
            }
            if c == b'"' {
                quote = false;
            }
        } else if c == b'"' {
            quote = true;
        } else if b[i..].starts_with(b"//") {
            return &line[..i];
        }
        i += 1;
    }
    line
}

#[derive(PartialEq)]
enum Kind {
    Handler,
    Proc,
}

struct Body<'a> {
    kind: Kind,
    owner: String,
    name: String,
    args: String,
    start: usize,
    body: Vec<(usize, &'a str)>,
}

fn bodies<'a>(lines: &[&'a str]) -> Vec<Body<'a>> {
    let mut out = Vec::new();
    let n = lines.len();
    let mut i = 0;
    while i < n {
        let line = lines[i];
        let kind;
        let (owner, name, args);
        if let Some(c) = pat_match!(r"UI_(?:ACT|SUBACT)_(?:PROC|OVERRIDE|PREF_PROC)\(\s*(/[\w/]+)\s*,\s*(\w+)\s*\)").captures(line) {
            kind = Kind::Handler;
            owner = c.s(1).to_string();
            name = c.s(2).to_string();
            args = String::new();
        } else if let Some(c) = pat_match!(r"(/[\w/]+?)/(?:proc/)?(\w+)\s*\(([^)]*)\)").captures(line) {
            kind = Kind::Proc;
            owner = c.s(1).to_string();
            name = c.s(2).to_string();
            args = c.s(3).to_string();
        } else {
            i += 1;
            continue;
        }
        let mut j = i + 1;
        let mut body = Vec::new();
        while j < n && (py_strip(lines[j]).is_empty() || matches!(lines[j].as_bytes()[0], b'\t' | b' ')) {
            body.push((j + 1, lines[j]));
            j += 1;
        }
        out.push(Body { kind, owner, name, args, start: i + 1, body });
        i = j;
    }
    out
}

fn arg_names(text: &str) -> Vec<String> {
    pat!(r#"UI_ARG_\w+\(\s*"([^"]+)""#).captures_iter(text).iter().map(|c| c.s(1).to_string()).collect()
}

/// One file's UI_ACT rows: `(type, handler, declared arg names)`, sorted by `(type, handler)`.
fn declared_rows_of(f: &SourceFile) -> Vec<(String, String, BTreeSet<String>)> {
    let mut rows: BTreeMap<(String, String), BTreeSet<String>> = BTreeMap::new();
    for line in f.raw().lines() {
        let m = pat_match!(r#"UI_SUBACT\(\s*(/[\w/]+)\s*,\s*"[^"]*"\s*,\s*[^,]+,\s*(\w+)\s*(.*)\)\s*$"#)
            .captures(line)
            .or_else(|| {
                pat_match!(r#"UI_(?:ACT|SUBACT)\(\s*(/[\w/]+)\s*,(?:\s*"[^"]*"\s*,(?=\s*"))?\s*[^,]+,\s*(\w+)\s*(.*)\)\s*$"#).captures(line)
            });
        if let Some(m) = m {
            rows.entry((m.s(1).to_string(), m.s(2).to_string())).or_default().extend(arg_names(m.s(3)));
        } else if line.starts_with("#define") && line.contains("TYPE_PROC_REF(/datum,") {
            // Row-generating macros (DECLARE_UI_MODAL): their handlers live on /datum.
            for part in line.split("TYPE_PROC_REF(/datum,").skip(1) {
                let handler = py_strip(part.split(')').next().unwrap_or(""));
                rows.entry(("/datum".to_string(), handler.to_string())).or_default().extend(arg_names(part));
            }
        }
    }
    rows.into_iter().map(|((t, h), k)| (t, h, k)).collect()
}

type ByHandler = BTreeMap<String, Vec<(String, BTreeSet<String>)>>;

/// `(type, handler) -> declared arg names`, from every UI_ACT row; indexed by handler here.
fn declared_keys(per_file: &[&Vec<DeclRow>]) -> ByHandler {
    let mut rows: BTreeMap<(String, String), BTreeSet<String>> = BTreeMap::new();
    for rs in per_file {
        for (t, h, k) in rs.iter() {
            rows.entry((t.clone(), h.clone())).or_default().extend(k.iter().cloned());
        }
    }
    let mut by_handler: ByHandler = BTreeMap::new();
    for ((ty, handler), keys) in rows {
        by_handler.entry(handler).or_default().push((ty, keys));
    }
    by_handler
}

fn keys_for(rows: &ByHandler, owner: &str, handler: &str) -> BTreeSet<String> {
    let mut out = BTreeSet::new();
    if let Some(list) = rows.get(handler) {
        for (row_type, keys) in list {
            if row_type == owner || owner.starts_with(&format!("{}/", row_type)) || row_type.starts_with(&format!("{}/", owner)) {
                out.extend(keys.iter().cloned());
            }
        }
    }
    out
}

fn count(p: &Pat, text: &str) -> usize {
    p.find_iter(text).len()
}

/// Procs taking `list/params` that may receive a handler's typed params: name -> keys it reads
/// (itself and the helpers it calls).
fn helper_cands_of(f: &SourceFile) -> Vec<Cand> {
    let passthrough = ["act_ask", "om_act_ask", "rerun_ask", "list"];
    let mut out: Vec<Cand> = Vec::new();
    {
        let lines = f.raw().lines_vec();
        for b in bodies(&lines) {
            if b.kind != Kind::Proc || !pat!(r"(?:^|,)\s*(?:list/)?params\s*(?:,|$)").is_match(&b.args) {
                continue;
            }
            let mut keys = BTreeSet::new();
            let mut callees = BTreeSet::new();
            let mut ok = true;
            for (_n, line) in &b.body {
                let text = strip_comment(line);
                if !pat!(r"\bparams\b").is_match(text) {
                    continue;
                }
                if raw_re().is_match(text) || dynamic_re().is_match(text) {
                    ok = false;
                    break;
                }
                for c in keyread_re().captures_iter(text) {
                    keys.insert(c.s(1).to_string());
                }
                let rest = code_of(&keyread_re().replace_all(text, ""));
                let total = count(pat!(r"\bparams\b"), &rest);
                let mut covered = 0;
                for (callee, argtext) in calls_of(&rest) {
                    let hits = count(pat!(r"(?:^|,)\s*params\s*(?=,|$)"), &argtext);
                    if hits == 0 {
                        continue;
                    }
                    covered += hits;
                    if !passthrough.contains(&callee.as_str()) {
                        callees.insert(callee);
                    }
                }
                if covered != total {
                    ok = false;
                    break;
                }
            }
            if ok {
                out.push((b.name.clone(), keys, callees));
            }
        }
    }
    out
}

/// One proc taking `params`: name, keys it reads, helpers it forwards to.
type Cand = (String, BTreeSet<String>, BTreeSet<String>);
type DeclRow = (String, String, BTreeSet<String>);

fn typed_param_helpers(per_file: &[&Vec<Cand>]) -> BTreeMap<String, BTreeSet<String>> {
    let mut cands: BTreeMap<String, (BTreeSet<String>, BTreeSet<String>)> = BTreeMap::new();
    for cs in per_file {
        for (name, keys, callees) in cs.iter() {
            cands.insert(name.clone(), (keys.clone(), callees.clone()));
        }
    }
    let mut changed = true;
    while changed {
        changed = false;
        let names: Vec<String> = cands.keys().cloned().collect();
        for name in names {
            let drop = cands.get(&name).map(|(_, callees)| callees.iter().any(|c| !cands.contains_key(c))).unwrap_or(false);
            if drop {
                cands.remove(&name);
                changed = true;
            }
        }
    }
    let mut out = BTreeMap::new();
    for name in cands.keys() {
        let mut seen: BTreeSet<String> = BTreeSet::new();
        let mut todo = vec![name.clone()];
        let mut keys = BTreeSet::new();
        while let Some(n) = todo.pop() {
            if !seen.insert(n.clone()) {
                continue;
            }
            let (k, callees) = &cands[&n];
            keys.extend(k.iter().cloned());
            todo.extend(callees.iter().cloned());
        }
        out.insert(name.clone(), keys);
    }
    out
}

fn raw_re() -> &'static Pat {
    pat!(
        r"\b(?:text2num|locate|text2path|json_decode|params2list)\s*\(\s*params\s*\??\[|\blocate_in_list\s*\([^;]*,\s*params\s*\??\[|\blocate_within\s*\([^;]*,\s*params\s*\??\["
    )
}

fn dynamic_re() -> &'static Pat {
    pat!(r#"\bparams\s*\??\[\s*(?!")"#)
}

fn keyread_re() -> &'static Pat {
    pat!(r#"\bparams\s*\??\[\s*"([^"]+)"\s*\]"#)
}

fn judge(f: &SourceFile, rows: &ByHandler, helpers: &BTreeMap<String, BTreeSet<String>>) -> Vec<(&'static str, String, usize)> {
    let mut out: Vec<(&'static str, String, usize)> = Vec::new();
    {
        let rel = f.rel.as_str();
        if starts_any(rel, NOT_TGUI) {
            return out;
        }
        let exempt_open = starts_any(rel, OPEN_EXEMPT);
        let lines = f.raw().lines_vec();
        for (idx, line) in lines.iter().enumerate() {
            let number = idx + 1;
            let code = code_of(line);
            if pat_match!(r"/[\w/]+?/(?:proc/)?tgui_data\s*\(").is_match(line) && !line.starts_with("/datum/proc/tgui_data(") {
                out.push(("tgui_data_override", rel.to_string(), number));
            }
            if pat_match!(r"(/[\w/]+?)/(?:proc/)?tgui_state\s*\(").is_match(line) && !line.starts_with("/datum/proc/tgui_state(") {
                let mut body: Vec<String> = Vec::new();
                for follow in &lines[number..] {
                    if !py_strip(follow).is_empty() && !follow.chars().next().map(is_py_space).unwrap_or(false) {
                        break;
                    }
                    let c = code_of(follow);
                    if !py_strip(&c).is_empty() {
                        body.push(c.trim_end_matches(is_py_space).to_string());
                    }
                }
                if body.len() == 1 && pat_match!(r"\treturn\s+(GLOB\.\w+|ADMIN_STATE\([^)]*\))\s*$").is_match(&body[0]) {
                    out.push(("tgui_state_override", rel.to_string(), number));
                }
            }
            if pat_match!(r"/[\w/]+?/(?:proc/)?tgui_interact\s*\(").is_match(line) && !line.starts_with("/datum/proc/tgui_interact(") {
                out.push(("tgui_interact_boilerplate", rel.to_string(), number));
            } else if !exempt_open
                && pat!(r"\bSStgui\.try_update_ui\s*\(|\bnew\s*/datum/tgui\s*\(|\bui\s*=\s*new\s*\(|var/datum/tgui/\w+\s*=\s*new\s*\(").is_match(&code)
            {
                out.push(("tgui_interact_boilerplate", rel.to_string(), number));
            }
            if raw_re().is_match(strip_comment(line)) {
                out.push(("text2num_params", rel.to_string(), number));
            }
        }
        for b in bodies(&lines) {
            if b.kind == Kind::Proc && b.name == "tgui_act" && b.owner != "/datum" {
                out.push(("ui_act_dispatch", rel.to_string(), b.start));
                for (number, line) in &b.body {
                    let text = strip_comment(line);
                    if pat!(r"\bparams\s*\??\[").is_match(text) && !raw_re().is_match(text) {
                        out.push(("text2num_params", rel.to_string(), *number));
                    }
                }
                continue;
            }
            if b.kind != Kind::Handler {
                continue;
            }
            let allowed_keys = keys_for(&rows, &b.owner, &b.name);
            let mut aliases: Vec<String> = Vec::new();
            for (number, line) in &b.body {
                let text = strip_comment(line);
                if raw_re().is_match(text) {
                    continue; // already counted
                }
                let mut flagged = false;
                for c in keyread_re().captures_iter(text) {
                    if !allowed_keys.contains(c.s(1)) {
                        flagged = true;
                    }
                }
                if dynamic_re().is_match(text) {
                    flagged = true;
                }
                if let Some(m) = pat!(r#"var/(?:[\w/]+/)?(\w+)\s*=\s*params\s*\??\[\s*"([^"]+)"\s*\]\s*$"#).captures(py_strip(text)) {
                    let alias = m.s(1).to_string();
                    if !aliases.contains(&alias) {
                        aliases.push(alias);
                    }
                }
                for alias in &aliases {
                    if Pat::cached(&format!(r"\b(?:text2num|locate|text2path|json_decode)\s*\(\s*{}\s*\)", alias)).is_match(text) {
                        flagged = true;
                    }
                }
                let blank = code_of(line);
                for (callee, argtext) in calls_of(&blank) {
                    if matches!(callee.as_str(), "tgui_act" | "act_ask" | "om_act_ask" | "rerun_ask" | "list") {
                        continue;
                    }
                    if let Some(h) = helpers.get(&callee) {
                        if h.is_subset(&allowed_keys) {
                            continue;
                        }
                    }
                    if pat!(r"(?:^|,)\s*params\s*(?:,|$)").is_match(&argtext) {
                        flagged = true;
                    }
                }
                if flagged {
                    out.push(("text2num_params", rel.to_string(), *number));
                }
            }
        }
    }
    out
}

#[derive(Serialize, Deserialize, Default, PartialEq)]
struct Facts {
    rows: Vec<DeclRow>,
    cands: Vec<Cand>,
}

#[derive(Serialize)]
struct Merged {
    rows: ByHandler,
    helpers: BTreeMap<String, BTreeSet<String>>,
}

fn scan(_tree: &Tree, files: &[&SourceFile]) -> Vec<(&'static str, String, usize)> {
    let fs = incr::facts("sys-ui-facts", files, |f| Facts { rows: declared_rows_of(f), cands: helper_cands_of(f) });
    let rows_of: Vec<&Vec<DeclRow>> = fs.iter().map(|x| &x.rows).collect();
    let cands_of: Vec<&Vec<Cand>> = fs.iter().map(|x| &x.cands).collect();
    let merged = Merged { rows: declared_keys(&rows_of), helpers: typed_param_helpers(&cands_of) };
    let key = incr::ctx_key(&merged);
    let results = incr::keyed("sys-ui-judge", key, files, |f| {
        judge(f, &merged.rows, &merged.helpers)
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

pub fn register(reg: &mut Registry) {
    register_module(reg, SysModule { name: "ui", rules: RULES, files_scan: Some(scan), ..SysModule::DEFAULT });
}

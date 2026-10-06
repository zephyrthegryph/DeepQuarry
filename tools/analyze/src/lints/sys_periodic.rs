//! Port of `tools/ci/sys_rules/periodic.py` (doc/rewrite/systems.md section 5): periodic work
//! declared by state. Hand guards, self-re-arming timers, hand start/stop beside state writes, and
//! hand `changed(src, ...)` raises of derived fields.

use std::collections::{BTreeMap, BTreeSet};
use std::sync::LazyLock;

use crate::dm::sys::{register_module, SysModule};
use crate::incr;
use crate::lint::{Registry, RuleMeta};
use crate::pat::Pat;
use crate::tree::{SourceFile, Tree};
use crate::util::{is_py_space, py_rstrip, py_strip};
use crate::{pat, pat_match};

const RULES: &[RuleMeta] = &[
    RuleMeta {
        name: "periodic_guard",
        hint: "DECLARE_PERIODIC_WHILE(type, cadence, \"field\") and drop the guard (doc/rewrite/systems.md section 5)",
    },
    RuleMeta {
        name: "om_after_rearm",
        hint: "DECLARE_REPEAT(type, delay, proc, \"field\") instead of a self-re-arming om_after() (doc/rewrite/systems.md section 5)",
    },
    RuleMeta {
        name: "derived_hand_raise",
        hint: "declare the derived field's inputs (OM_DERIVE_FIELD(T, F, list(\"input\", ...))) as fields; their setters raise it (doc/rewrite/systems.md section 5)",
    },
    RuleMeta {
        name: "periodic_toggle",
        hint: "declare the state (DECLARE_PERIODIC_WHILE / DECLARE_REPEAT) and let its setter start/stop the work (doc/rewrite/systems.md section 5)",
    },
];

/// The runtime and the scheduler core start/stop work on purpose.
const SKIP: &[&str] = &["code/datums/sys/periodic.dm", "code/datums/om/"];

const STEP_PROCS: &[&str] = &["periodic_step", "machine_step"];
const STOP_OK: &[&str] = &["periodic_step", "machine_step", "on_dematerialize", "lifecycle_dematerialize", "on_destroy", "lifecycle_prerelease"];
const NOT_VARS: &[&str] = &["TRUE", "FALSE", "null", "src", "usr", "world"];

const TERM: &str = r"!?\s*(?:src\.)?(?:[A-Za-z_]\w*(?!\s*[\(\.\[])|operable\(\s*\)|has_stat\(\s*[\w|\s]*\))";

static STATE_COND: LazyLock<Pat> =
    LazyLock::new(|| Pat::new_match(&format!(r"^\(*\s*{t}\s*\)*(?:\s*(?:\|\||&&)\s*\(*\s*{t}\s*\)*)*$", t = TERM)));

fn head_re() -> &'static Pat {
    pat_match!(r"^(/[\w/]+?)/(?:proc/|verb/)?(\w+)\s*\(([^)]*)\)")
}

fn if_head() -> &'static Pat {
    pat_match!(r"^(?:else\s+)?if\s*\((.*)\)\s*(.*)$")
}

fn write_re() -> &'static Pat {
    pat_match!(
        r"^(?:src\.)?([A-Za-z_]\w*)\s*(?:=(?!=)|\+=|-=|\|=|&=|\^=|\+\+|--)|^(?:src\.)?set_(\w+)\s*\(|^(?:src\.)?(\w+)_(?:add|remove)\s*\("
    )
}

/// Python `str.isupper()`: at least one cased character and no lowercase one.
fn py_isupper(s: &str) -> bool {
    s.chars().any(|c| c.is_uppercase()) && !s.chars().any(|c| c.is_lowercase())
}

fn cond_is_state(cond: &str) -> bool {
    let cond = py_strip(cond);
    if cond.is_empty() || !STATE_COND.is_match(cond) {
        return false;
    }
    let words: Vec<&str> = pat!(r"[A-Za-z_]\w*").find_iter(cond).iter().map(|m| m.as_str()).collect();
    words.iter().any(|w| !NOT_VARS.contains(w) && *w != "operable" && *w != "has_stat" && !py_isupper(w))
        || cond.contains("operable")
        || cond.contains("has_stat")
}

/// Top-level comma split of the text after `om_after(src,` up to its closing paren.
fn split_args(text: &str) -> Vec<String> {
    let mut depth = 0i32;
    let mut out: Vec<String> = Vec::new();
    let mut cur = String::new();
    for ch in text.chars() {
        if ch == '(' || ch == '[' {
            depth += 1;
        } else if ch == ')' || ch == ']' {
            if depth == 0 {
                out.push(cur);
                return out.iter().map(|a| py_strip(a).to_string()).collect();
            }
            depth -= 1;
        }
        if ch == ',' && depth == 0 {
            out.push(std::mem::take(&mut cur));
            continue;
        }
        cur.push(ch);
    }
    out.push(cur);
    out.iter().map(|a| py_strip(a).to_string()).collect()
}

fn params_of(sig: &str) -> Vec<String> {
    let mut names = Vec::new();
    for part in sig.split(',') {
        let part = py_strip(part.split('=').next().unwrap_or(""));
        if part.is_empty() {
            continue;
        }
        let last = part.rsplit('/').next().unwrap_or("");
        let name = py_strip(last.split(" as ").next().unwrap_or(""));
        names.push(name.to_string());
    }
    names
}

struct Proc<'a> {
    name: String,
    params: Vec<String>,
    body: Vec<(usize, &'a str)>,
}

fn procs<'a>(lines: &[&'a str]) -> Vec<Proc<'a>> {
    let mut out = Vec::new();
    let mut cur: Option<Proc> = None;
    for (idx, line) in lines.iter().enumerate() {
        let number = idx + 1;
        if !line.is_empty() && !line.chars().next().map(is_py_space).unwrap_or(false) {
            if let Some(c) = cur.take() {
                out.push(c);
            }
            if let Some(m) = head_re().captures(line) {
                if !line.trim_start_matches(is_py_space).starts_with('#') {
                    cur = Some(Proc { name: m.s(2).to_string(), params: params_of(m.s(3)), body: Vec::new() });
                }
            }
            continue;
        }
        if let Some(c) = cur.as_mut() {
            c.body.push((number, line));
        }
    }
    if let Some(c) = cur {
        out.push(c);
    }
    out
}

/// Non-blank, non-comment statement lines: (number, indent, code).
fn stmts_of(body: &[(usize, &str)]) -> Vec<(usize, usize, String)> {
    let mut out = Vec::new();
    for (number, raw) in body {
        let code = py_rstrip(raw.split("//").next().unwrap_or(""));
        if py_strip(code).is_empty() {
            continue;
        }
        let indent = raw.chars().take_while(|c| *c == '\t').count();
        out.push((*number, indent, py_strip(code).to_string()));
    }
    out
}

fn ret_kill(s: &str) -> bool {
    pat_match!(r"^return\s+PROCESS_KILL\b").is_match(s)
}

fn scan_guard(name: &str, stmts: &[(usize, usize, String)], hits: &mut Vec<usize>) {
    if !STEP_PROCS.contains(&name) {
        return;
    }
    let mut local_names: BTreeSet<String> = BTreeSet::new();
    for (_n, _i, c) in stmts {
        for m in pat!(r"(?<![\w/])var/(?:[\w/]+/)?(\w+)").captures_iter(c) {
            local_names.insert(m.s(1).to_string());
        }
    }
    for (idx, (number, indent, code)) in stmts.iter().enumerate() {
        if *indent != 1 {
            continue;
        }
        let Some(m) = if_head().captures(code) else { continue };
        if code.starts_with("else") {
            continue;
        }
        let cond = m.s(1);
        let tail = py_strip(m.s(2));
        let kill = if !tail.is_empty() {
            ret_kill(tail)
        } else {
            let nxt = stmts.get(idx + 1);
            let after = stmts.get(idx + 2);
            match nxt {
                Some(n) => n.1 == 2 && ret_kill(&n.2) && after.map(|a| a.1 <= 1).unwrap_or(true),
                None => false,
            }
        };
        if kill && cond_is_state(cond) {
            let idents: BTreeSet<String> = pat!(r"[A-Za-z_]\w*").find_iter(cond).iter().map(|m| m.as_str().to_string()).collect();
            if idents.is_disjoint(&local_names) {
                hits.push(*number);
            }
        }
    }
}

/// An argument a loop passes on as is: a non-numeric constant, or the same parameter.
fn unchanged(arg: &str, k: usize, params: &[String]) -> bool {
    if arg.is_empty() {
        return true;
    }
    if k < params.len() && arg == params[k] {
        return true;
    }
    pat_match!(r#"^(?:[A-Z_][A-Z0-9_]*|-?\d+(?:\.\d+)?|TRUE|FALSE|null|"[^"]*")$"#).is_match(arg) && !pat_match!(r"^-?\d").is_match(arg)
}

fn scan_rearm(name: &str, params: &[String], stmts: &[(usize, usize, String)], hits: &mut Vec<usize>) {
    for (number, _indent, code) in stmts {
        let Some(m) = pat!(r"\b(?:om_after|after)(?:_slot)?\s*\(\s*src\s*,(.*)$").captures(code) else { continue };
        let args = split_args(m.s(1));
        let mut target: Option<String> = None;
        let mut rest: &[String] = &[];
        for (i, arg) in args.iter().enumerate() {
            if let Some(p) = pat!(r"(?:PROC_REF|TYPE_PROC_REF)\s*\(\s*(?:[\w/]+\s*,\s*)?(\w+)\s*\)").captures(arg) {
                target = Some(p.s(1).to_string());
                rest = &args[i + 1..];
                break;
            }
        }
        if target.as_deref() != Some(name) {
            continue;
        }
        // after(): the extra arguments ride in `with = list(...)`; `key = ...` is not one.
        let mut flat: Vec<String> = Vec::new();
        for a in rest {
            if let Some(w) = pat!(r"^with\s*=\s*list\s*\((.*)\)\s*$").captures(a) {
                flat.extend(split_args(w.s(1)));
            } else if !pat_match!(r"^key\s*=").is_match(a) {
                flat.push(a.clone());
            }
        }
        if flat.iter().enumerate().all(|(k, a)| unchanged(a, k, params)) {
            hits.push(*number);
        }
    }
}

/// TRUE when stmts[idx] is the first statement of an if/else branch over fields.
fn branch_is_state(stmts: &[(usize, usize, String)], idx: usize) -> bool {
    let indent = stmts[idx].1;
    if idx == 0 {
        return false;
    }
    let (_pn, pindent, pcode) = &stmts[idx - 1];
    if *pindent + 1 != indent {
        return false;
    }
    if let Some(m) = if_head().captures(pcode) {
        if py_strip(m.s(2)).is_empty() {
            return cond_is_state(m.s(1));
        }
    }
    if pcode == "else" {
        // Find the matching if at pindent.
        let mut j = idx as i64 - 2;
        while j >= 0 {
            let (_jn, jindent, jcode) = &stmts[j as usize];
            if *jindent < *pindent {
                return false;
            }
            if *jindent == *pindent {
                if let Some(mm) = if_head().captures(jcode) {
                    if !jcode.starts_with("else") {
                        return cond_is_state(mm.s(1));
                    }
                }
            }
            j -= 1;
        }
    }
    false
}

fn is_write(code: &str) -> bool {
    let Some(m) = write_re().captures(code) else { return false };
    let word = if m.matched(1) { m.s(1) } else if m.matched(2) { m.s(2) } else { m.s(3) };
    word != "var" && word != "." && !code.starts_with("var/")
}

fn scan_toggle(name: &str, stmts: &[(usize, usize, String)], hits: &mut Vec<usize>) {
    for (idx, (number, indent, code)) in stmts.iter().enumerate() {
        if !pat!(r"\b(?:om_task_periodic(?:_stop)?\s*\(\s*src\b|MACHINE_WAKE\s*\(\s*src\s*\)|MACHINE_SLEEP\s*\(\s*src\s*\))").is_match(code) {
            continue;
        }
        if pat!(r"\b(?:om_task_periodic_stop\s*\(\s*src\s*\)|MACHINE_SLEEP\s*\(\s*src\s*\))").is_match(code) && !STOP_OK.contains(&name) {
            // A hand stop outside the body and the lifecycle's own teardown.
            hits.push(*number);
            continue;
        }
        let mut near: Vec<&str> = Vec::new();
        if idx > 0 && stmts[idx - 1].1 == *indent {
            near.push(&stmts[idx - 1].2);
        }
        if idx + 1 < stmts.len() && stmts[idx + 1].1 == *indent {
            near.push(&stmts[idx + 1].2);
        }
        if near.iter().any(|c| is_write(c)) || branch_is_state(stmts, idx) {
            hits.push(*number);
        }
    }
}

/// One file's derived-field declarations: `(type path, input names)`; the input set holds `""`
/// for a hand-raisable type.
fn derived_of(f: &SourceFile) -> Vec<(String, Vec<String>)> {
    let mut out: Vec<(String, Vec<String>)> = Vec::new();
    for line in f.raw().lines() {
        if let Some(m) = pat_match!(r"^OM_DERIVE_FIELD\(\s*(/[\w/]+)\s*,\s*(\w+)\s*,\s*(.*)\)\s*(?://.*)?$").captures(py_strip(line)) {
            let mut names: BTreeSet<String> = pat!(r#""(\w+)""#).captures_iter(m.s(3)).iter().map(|c| c.s(1).to_string()).collect();
            if !names.is_empty() || m.s(3).contains("CHANGE_EXPLICIT") {
                names.insert(String::new());
            }
            out.push((m.s(1).to_string(), names.into_iter().collect()));
        }
    }
    out
}

fn inputs_for(path: &str, derived: &BTreeMap<String, BTreeSet<String>>) -> BTreeSet<String> {
    let mut names = BTreeSet::new();
    for (root, inputs) in derived {
        if path == root || path.starts_with(&format!("{}/", root)) {
            names.extend(inputs.iter().cloned());
        }
    }
    names
}

/// `changed(src, ...)` in a proc of a type with derived fields, when it is a hand refresh.
fn scan_hand_raise(f: &SourceFile, derived: &BTreeMap<String, BTreeSet<String>>, hits: &mut Vec<usize>) {
    let raw = f.raw();
    let nlines = raw.num_lines();
    let mut path: Option<String> = None;
    for (number, line) in raw.numbered() {
        if !line.is_empty() && !line.chars().next().map(is_py_space).unwrap_or(false) {
            path = head_re().captures(line).map(|m| m.s(1).to_string()).map(|p| if p.contains("/proc") { p.split("/proc").next().unwrap_or("").to_string() } else { p });
            continue;
        }
        let Some(p) = &path else { continue };
        if p.is_empty() {
            continue;
        }
        let code = line.split("//").next().unwrap_or("");
        if !pat!(r"changed\(\s*src\s*,").is_match(code) {
            continue;
        }
        let inputs = inputs_for(p, derived);
        if inputs.is_empty() {
            continue;
        }
        if code.contains("CHANGE_EXPLICIT") {
            hits.push(number);
            continue;
        }
        let names: BTreeSet<String> = inputs.iter().filter(|n| !n.is_empty()).cloned().collect();
        let lo = number.saturating_sub(3);
        let hi = nlines.min(number + 2);
        for i in lo..hi {
            if i == number - 1 {
                continue;
            }
            let c = py_strip(raw.line(i + 1).split("//").next().unwrap_or(""));
            let Some(m) = write_re().captures(c) else { continue };
            let word = if m.matched(1) && !m.s(1).is_empty() {
                m.s(1)
            } else if m.matched(2) && !m.s(2).is_empty() {
                m.s(2)
            } else {
                m.s(3)
            };
            if !word.is_empty() && names.contains(word) {
                hits.push(number);
                break;
            }
        }
    }
}

const R_GUARD: u8 = 0;
const R_REARM: u8 = 1;
const R_TOGGLE: u8 = 2;

/// The sites that read only the file: guards, re-arms and hand start/stop, in rule order.
fn pure_sites(f: &SourceFile) -> Vec<(u8, u32)> {
    let mut out = Vec::new();
    if SKIP.iter().any(|p| f.rel.starts_with(p)) {
        return out;
    }
    let text = f.raw().text.as_str();
    if !["PROCESS_KILL", "after(", "om_after", "om_task_periodic", "MACHINE_WAKE", "MACHINE_SLEEP"].iter().any(|k| text.contains(k)) {
        return out;
    }
    let lines = f.raw().lines_vec();
    let mut guard = Vec::new();
    let mut rearm = Vec::new();
    let mut toggle = Vec::new();
    for p in procs(&lines) {
        let stmts = stmts_of(&p.body);
        let (mut g, mut r, mut t) = (Vec::new(), Vec::new(), Vec::new());
        scan_guard(&p.name, &stmts, &mut g);
        scan_rearm(&p.name, &p.params, &stmts, &mut r);
        scan_toggle(&p.name, &stmts, &mut t);
        guard.extend(g);
        rearm.extend(r);
        toggle.extend(t);
    }
    out.extend(guard.into_iter().map(|n| (R_GUARD, n as u32)));
    out.extend(rearm.into_iter().map(|n| (R_REARM, n as u32)));
    out.extend(toggle.into_iter().map(|n| (R_TOGGLE, n as u32)));
    out
}

fn scan(_tree: &Tree, files: &[&SourceFile]) -> Vec<(&'static str, String, usize)> {
    let fd = incr::facts("sys-periodic-derived", files, derived_of);
    let mut derived: BTreeMap<String, BTreeSet<String>> = BTreeMap::new();
    for (root, names) in fd.iter().flatten() {
        derived.entry(root.clone()).or_default().extend(names.iter().cloned());
    }
    let raised: Vec<Vec<u32>> = incr::keyed("sys-periodic-raise", incr::ctx_key(&derived), files, |f| {
        let mut hits = Vec::new();
        if SKIP.iter().any(|p| f.rel.starts_with(p)) {
            return Vec::new();
        }
        if f.raw().text.contains("changed") && !derived.is_empty() {
            scan_hand_raise(f, &derived, &mut hits);
        }
        hits.into_iter().map(|n| n as u32).collect()
    });
    let pure: Vec<Vec<(u8, u32)>> = incr::facts("sys-periodic-pure", files, pure_sites);
    let mut out: Vec<(&'static str, String, usize)> = Vec::new();
    for ((f, r), p) in files.iter().zip(&raised).zip(&pure) {
        for n in r {
            out.push(("derived_hand_raise", f.rel.clone(), *n as usize));
        }
        for (rule, n) in p {
            let name = match *rule {
                R_GUARD => "periodic_guard",
                R_REARM => "om_after_rearm",
                _ => "periodic_toggle",
            };
            out.push((name, f.rel.clone(), *n as usize));
        }
    }
    out
}

pub fn register(reg: &mut Registry) {
    register_module(reg, SysModule { name: "periodic", rules: RULES, files_scan: Some(scan), ..SysModule::DEFAULT });
}

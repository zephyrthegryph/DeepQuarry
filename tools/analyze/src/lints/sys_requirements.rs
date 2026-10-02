//! Port of `tools/ci/sys_rules/requirements.py` (doc/rewrite/systems.md section 6): inline
//! refusals lifted into requirements. A refusal written at the head of an interaction effect proc
//! (instead of a REQ_* clause), and any `REFUSE_IF(...)`.

use std::collections::{BTreeSet, HashMap};

use crate::dm::sys::{register_module, SysModule};
use crate::lint::{Registry, RuleMeta};
use crate::pat::Pat;
use crate::tree::{SourceFile, Tree};
use crate::util::{is_py_space, py_rstrip, py_strip};
use crate::{pat, pat_match};

const RULES: &[RuleMeta] = &[RuleMeta {
    name: "inline_refusal",
    hint: "declare the guard as a requirement clause (REQ_FIELD/REQ_FIELD_NOT/REQ_FIELD_EQ/REQ_ACCESS/REQ_NOT_EMAGGED/REQ_ANCHORED/REQ_PANEL/REQ_ON) on the interaction (systems.md section 6)",
}];

fn decl_re() -> &'static Pat {
    pat!(r"\b(?:DECLARE_INTERACTIONS|EXTEND_INTERACTIONS)\(\s*(/[\w/]+)")
}

fn message_re() -> &'static Pat {
    pat!(r"\b(?:to_chat|balloon_alert|visible_message|audible_message|show_message|balloon_alert_to_viewers)\s*\(")
}

fn quiet_re() -> &'static Pat {
    pat_match!(r"^(?:playsound|SEND_SOUND)\s*\(")
}

fn return_re() -> &'static Pat {
    pat_match!(r"^return\b")
}

fn acting_re() -> &'static Pat {
    pat!(
        r"\b(?:drop_from_inventory|unEquip|drop_item|drop_held_item|put_in_\w+|remove_from_mob|use|use_charge|checked_use|use_tool|do_after|do_mob|tgui_\w+|input|alert|forceMove|try_\w+|attempt_\w+|consume\w*|transfer\w*|insert_item|user_unbuckle_mob|buckle_mob|Move|rerun_ask|om_ask|prob|rand|CLUMSY_FAIL_CHANCE|remove_fuel|use_resource|spend\w*|pay\w*|charge|om_task_timed)\s*\("
    )
}

/// Code part of a line: comments and string contents dropped (single quotes too), right-stripped.
fn strip(line: &str) -> String {
    let b = line.as_bytes();
    let mut out: Vec<u8> = Vec::new();
    let mut i = 0;
    let mut quote: Option<u8> = None;
    while i < b.len() {
        let c = b[i];
        if let Some(q) = quote {
            if c == b'\\' {
                i += 2;
                continue;
            }
            if c == q {
                quote = None;
                out.push(c);
            }
            i += 1;
            continue;
        }
        if c == b'"' || c == b'\'' {
            quote = Some(c);
            out.push(c);
        } else if b[i..].starts_with(b"//") {
            break;
        } else {
            out.push(c);
        }
        i += 1;
    }
    let s = String::from_utf8_lossy(&out).into_owned();
    py_rstrip(&s).to_string()
}

fn related(a: &str, b: &str) -> bool {
    a == b || a.starts_with(&format!("{}/", b)) || b.starts_with(&format!("{}/", a))
}

/// proc name -> set of declaring types.
fn effect_procs(files: &[&SourceFile]) -> HashMap<String, BTreeSet<String>> {
    let mut found: HashMap<String, BTreeSet<String>> = HashMap::new();
    for f in files {
        let mut decl: Option<String> = None;
        let mut datum = false;
        for line in f.raw().lines() {
            if let Some(m) = decl_re().captures(line) {
                decl = Some(m.s(1).to_string());
            }
            if let Some(d) = &decl {
                if pat!(r"\bINTERACT_[A-Z_]+\(").is_match(line) || decl_re().is_match(line) {
                    for r in pat!(r"\b(?:PROC_REF|TYPE_PROC_REF\([^,]*,)\s*\(?\s*(\w+)\s*\)|\.proc/(\w+)").captures_iter(line) {
                        let name = if r.matched(1) && !r.s(1).is_empty() { r.s(1) } else { r.s(2) };
                        found.entry(name.to_string()).or_default().insert(d.clone());
                    }
                }
            }
            if decl.is_some() && !py_rstrip(line).ends_with('\\') {
                decl = None;
            }
            if !line.is_empty() && !line.chars().next().map(is_py_space).unwrap_or(false) {
                datum = pat_match!(r"^(/datum/interaction[\w/]*)\s*$").is_match(line);
            }
            if datum {
                if let Some(m) = pat_match!(r"^\s+effect\s*=\s*(/[\w/]+?)/(?:proc/)?(\w+)\s*(?://.*)?$").captures(line) {
                    found.entry(m.s(2).to_string()).or_default().insert(m.s(1).to_string());
                }
            }
        }
    }
    found
}

type Stmt = Vec<(usize, String, usize)>;

/// Top-level statements of a proc body: lists of (line_no, code, depth).
fn statements(body: &[(usize, &str)]) -> Vec<Stmt> {
    let mut stmts: Vec<Stmt> = Vec::new();
    for (no, raw) in body {
        let code = strip(raw);
        if py_strip(&code).is_empty() {
            continue;
        }
        let depth = code.chars().take_while(|c| *c == '\t').count();
        let item = (*no, py_strip(&code).to_string(), depth);
        if depth <= 1 || stmts.is_empty() {
            stmts.push(vec![item]);
        } else {
            stmts.last_mut().unwrap().push(item);
        }
    }
    stmts
}

/// TRUE when the statements only say no (a message, maybe a sound) and end in return.
fn only_refusal(parts: &[String]) -> bool {
    if parts.is_empty() || !return_re().is_match(&parts[parts.len() - 1]) {
        return false;
    }
    let mut told = false;
    for part in parts {
        if message_re().is_match(part) {
            told = true;
            if !pat_match!(
                r"^[\w.?\[\]]*\s*(?:to_chat|balloon_alert|visible_message|audible_message|show_message|balloon_alert_to_viewers)\s*\("
            )
            .is_match(part)
                && !return_re().is_match(part)
            {
                return false;
            }
        } else if return_re().is_match(part) {
            continue;
        } else if !quiet_re().is_match(part) {
            return false;
        }
    }
    told
}

fn split_parts(text: &str, parts: &mut Vec<String>) {
    for p in text.split(';') {
        let p = py_strip(p);
        if !p.is_empty() {
            parts.push(p.to_string());
        }
    }
}

/// The body of an `if` statement as simple statements, or None if it isn't a plain guard.
fn guard_parts(stmt: &Stmt) -> Option<(String, Vec<String>)> {
    let first = &stmt[0].1;
    let mut depth = 0i32;
    let mut found: Option<(String, String)> = None;
    for (i, c) in first.bytes().enumerate() {
        if c == b'(' {
            depth += 1;
        } else if c == b')' {
            depth -= 1;
            if depth == 0 {
                found = Some((first[..i + 1].to_string(), py_strip(&first[i + 1..]).to_string()));
                break;
            }
        }
    }
    let (cond, rest) = found?;
    let mut parts: Vec<String> = Vec::new();
    if !rest.is_empty() {
        let rest = rest.trim_matches(|c| c == '{' || c == '}' || c == ' ');
        split_parts(rest, &mut parts);
    }
    for (_, code, _) in &stmt[1..] {
        let code = code.trim_matches(|c| c == '{' || c == '}' || c == ' ');
        split_parts(code, &mut parts);
    }
    Some((cond, parts))
}

fn scan(_tree: &Tree, files: &[&SourceFile]) -> Vec<(&'static str, String, usize)> {
    let mut out: Vec<(&'static str, String, usize)> = Vec::new();
    let effects = effect_procs(files);
    for f in files {
        let rel = f.rel.as_str();
        let lines = f.raw().lines_vec();
        for (idx, line) in lines.iter().enumerate() {
            if pat!(r"\bREFUSE_IF\s*\(").is_match(&strip(line)) && !line.contains("#define") {
                out.push(("inline_refusal", rel.to_string(), idx + 1));
            }
        }
        let n = lines.len();
        let mut i = 0;
        while i < n {
            let line = lines[i];
            let Some(m) = pat_match!(r"^(/[\w/]+?)/(?:proc/|verb/)?(\w+)\s*\(").captures(line) else {
                i += 1;
                continue;
            };
            let Some(types) = effects.get(m.s(2)) else {
                i += 1;
                continue;
            };
            if !types.iter().any(|t| related(m.s(1), t)) {
                i += 1;
                continue;
            }
            let mut body: Vec<(usize, &str)> = Vec::new();
            let mut j = i + 1;
            while j < n && (lines[j].is_empty() || lines[j].chars().next().map(is_py_space).unwrap_or(false)) {
                body.push((j + 1, lines[j]));
                j += 1;
            }
            let stmts = statements(&body);
            for (k, stmt) in stmts.iter().enumerate() {
                let code = stmt[0].1.as_str();
                if code.starts_with("var/") && acting_re().is_match(code) {
                    break; // a local that asks the player or acts: what follows validates the outcome
                }
                if code.starts_with("var/") || code.starts_with("set ") || code.starts_with("SHOULD_") || code.starts_with("SIGNAL_HANDLER") {
                    continue;
                }
                if !pat_match!(r"^if\s*\(").is_match(code) {
                    break;
                }
                if k + 1 < stmts.len() && pat_match!(r"^else\b").is_match(&stmts[k + 1][0].1) {
                    break;
                }
                let Some((cond, parts)) = guard_parts(stmt) else { break };
                if acting_re().is_match(&cond) {
                    continue;
                }
                if parts.is_empty() || (!return_re().is_match(&parts[parts.len() - 1]) && !return_re().is_match(&parts[0])) {
                    break;
                }
                if only_refusal(&parts) || (parts.len() == 1 && return_re().is_match(&parts[0]) && message_re().is_match(&parts[0])) {
                    out.push(("inline_refusal", rel.to_string(), stmt[0].0));
                } else if !parts.iter().all(|p| return_re().is_match(p) || quiet_re().is_match(p)) {
                    // A branch that does work (another action of a multi-purpose effect) ends the head.
                    break;
                }
            }
            i = j;
        }
    }
    out
}

pub fn register(reg: &mut Registry) {
    register_module(reg, SysModule { name: "requirements", rules: RULES, files_scan: Some(scan), ..SysModule::DEFAULT });
}

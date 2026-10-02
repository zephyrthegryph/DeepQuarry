//! Port of `tools/ci/sys_rules/damage_reactions.py` (doc/rewrite/systems.md section 12): declared
//! damage reactions. An override of a damage entry point that does a fixed thing (not procedural:
//! reads the hit, returns a hit-flow value, or changes the hit it passes on) is flagged.

use std::sync::LazyLock;

use crate::dm::sys::{register_module, SysModule};
use crate::lint::{Registry, RuleMeta};
use crate::pat::Pat;
use crate::tree::SourceFile;
use crate::util::py_strip;
use crate::{pat, pat_match};

const RULES: &[RuleMeta] = &[RuleMeta {
    name: "entry_override",
    hint: "declare it next to the type: DAMAGE_REACTION(type, trigger, PROC_REF(x)) / REFLECTS(type, kinds, chance) / EMP_DISABLE(type, duration, field), or a protection flag (doc/rewrite/systems.md section 12)",
}];

const ENTRIES: &[&str] = &[
    "bullet_act",
    "emp_act",
    "ex_act",
    "fire_act",
    "blob_act",
    "hitby",
    "attack_generic",
    "electrocute_act",
    // the packet adapters the entries call; overriding one to do a fixed thing is the same shape
    "receive_emp",
    "receive_ionic",
    "receive_explosion",
    "receive_blob",
    "receive_shock",
];
const ADAPTER_ROOTS: &[&str] = &["/atom", "/atom/movable", "/obj", "/turf", "/mob", "/mob/living"];
const FREE_PARAMS: &[&str] = &["severity", "recursive", "forced"];
const REFLECT_ALLOWED_MEMBERS: &[&str] = &["starting", "name", "reflected", "redirect", "obj_damage_type"];

static HEADER: LazyLock<Pat> = LazyLock::new(|| Pat::new_match(&format!(r"^(/[\w/]+?)/({})\s*\((.*)$", ENTRIES.join("|"))));

/// Names of the parameters in `signature` (the text after the header's opening paren).
fn param_names(signature: &str) -> Vec<String> {
    let mut depth = 1i32;
    let mut text = String::new();
    for c in signature.chars() {
        if c == '(' {
            depth += 1;
        } else if c == ')' {
            depth -= 1;
            if depth == 0 {
                break;
            }
        }
        text.push(c);
    }
    let mut names: Vec<String> = Vec::new();
    for part in text.split(',') {
        let part = py_strip(part.split('=').next().unwrap_or(""));
        if part.is_empty() {
            continue;
        }
        let part = py_strip(part.split(" as ").next().unwrap_or(""));
        names.push(py_strip(part.rsplit('/').next().unwrap_or("")).to_string());
    }
    names.into_iter().filter(|n| pat_match!(r"^[A-Za-z_]\w*$").is_match(n)).collect()
}

fn code_of(line: &str) -> String {
    let s = pat!(r#""(?:[^"\\\n]|\\.)*""#).replace_all(line, "\"\"");
    s.split("//").next().unwrap_or("").to_string()
}

/// The line with every parent call's argument list removed (`..(P, def_zone)` -> `..()`).
fn strip_parent_args(code: &str) -> String {
    let b = code.as_bytes();
    let mut out = String::new();
    let mut i = 0;
    while i < code.len() {
        let Some(m) = pat!(r"\.\.\(").find_at(code, i) else {
            out.push_str(&code[i..]);
            break;
        };
        out.push_str(&code[i..m.end]);
        let mut depth = 1;
        let mut j = m.end;
        while j < b.len() && depth != 0 {
            if b[j] == b'(' {
                depth += 1;
            } else if b[j] == b')' {
                depth -= 1;
            }
            j += 1;
        }
        out.push(')');
        i = j;
    }
    out
}

/// The reflect shape: a redirect back towards `name.starting`, reading nothing else of it.
fn is_reflect_boilerplate(body: &[String], name: &str) -> bool {
    let text = body.join("\n");
    let esc = regex::escape(name);
    if !Pat::new(&format!(r"\b{}\s*\.\s*redirect\s*\(", esc)).is_match(&text) {
        return false;
    }
    if !Pat::new(&format!(r"\b{}\s*\.\s*starting\b", esc)).is_match(&text) {
        return false;
    }
    for m in Pat::new(&format!(r"\b{}\b(\s*\.\s*(\w+))?", esc)).captures_iter(&text) {
        if !m.matched(2) {
            let start = m.start(0);
            // text[max(0, start - 40):start] counted in characters
            let mut from = start;
            for (n, (off, _)) in text[..start].char_indices().rev().enumerate() {
                if n >= 40 {
                    break;
                }
                from = off;
            }
            let before = &text[from..start];
            // istype(P, ...), act_message(src, P, ...) and visible_message("[P]") read no state
            if pat!(r"(istype|act_message|visible_message|span_\w+)\s*\([^()]*$").is_match(before) {
                continue;
            }
            return false;
        }
        if !REFLECT_ALLOWED_MEMBERS.contains(&m.s(2)) {
            return false;
        }
    }
    true
}

/// P3: a parameter is written, or the parent gets something other than the parameters.
fn changes_hit(raw_lines: &[String], params: &[String]) -> bool {
    for line in raw_lines {
        for name in params {
            if Pat::new(&format!(r"(?<![\w.]){}\s*(?:=(?!=)|\+\+|--|[-+*/]=)", regex::escape(name))).is_match(line) {
                return true;
            }
        }
        for m in pat!(r"\.\.\(([^()]*(?:\([^()]*\)[^()]*)*)\)").captures_iter(line) {
            for arg in m.s(1).split(',').map(py_strip) {
                if !arg.is_empty() && !params.iter().any(|p| p == arg) && !pat_match!(r"^\w+\s*=\s*\w+$").is_match(arg) {
                    return true;
                }
            }
        }
    }
    false
}

fn procedural(body: &[&str], params: &[String]) -> bool {
    let reads: Vec<&String> = params.iter().filter(|p| !FREE_PARAMS.contains(&p.as_str())).collect();
    let raw: Vec<String> = body.iter().map(|l| code_of(l)).collect();
    if changes_hit(&raw, params) {
        return true;
    }
    let lines: Vec<String> = raw.iter().map(|l| strip_parent_args(l)).collect();
    for line in &lines {
        let Some(m) = pat!(r"(?<![\w.])return\b\s*(.*)$").captures(line) else { continue };
        let mut value = py_strip(py_strip(m.s(1)).trim_end_matches(';')).to_string();
        while value.starts_with('(') && value.ends_with(')') {
            value = py_strip(&value[1..value.len() - 1]).to_string();
        }
        if matches!(value.as_str(), "" | "." | "..()" | "0" | "FALSE" | "null") {
            continue;
        }
        if !reads.is_empty() && is_reflect_boilerplate(&lines, reads[0]) {
            continue;
        }
        return true;
    }
    for name in &reads {
        let pattern = Pat::new(&format!(r"(?<![\w.]){}\b", regex::escape(name)));
        if lines.iter().any(|l| pattern.is_match(l)) {
            if is_reflect_boilerplate(&lines, name) {
                continue;
            }
            return true;
        }
    }
    false
}

fn scan(f: &SourceFile, out: &mut Vec<(&'static str, usize)>) {
    let lines = f.raw().lines_vec();
    for (index, line) in lines.iter().enumerate() {
        let Some(m) = HEADER.captures(line) else { continue };
        let path = m.s(1);
        if path.ends_with("/proc") || format!("{}/", path).contains("/proc/") || path.contains("/verb") {
            continue; // a definition, not an override
        }
        if ADAPTER_ROOTS.contains(&path) {
            continue;
        }
        let mut body: Vec<&str> = Vec::new();
        let mut j = index + 1;
        while j < lines.len() && (lines[j].starts_with(['\t', ' ']) || py_strip(lines[j]).is_empty()) {
            body.push(lines[j]);
            j += 1;
        }
        if procedural(&body, &param_names(m.s(3))) {
            continue;
        }
        out.push(("entry_override", index + 1));
    }
}

pub fn register(reg: &mut Registry) {
    register_module(reg, SysModule { name: "damage_reactions", rules: RULES, file_scan: Some(scan), ..SysModule::DEFAULT });
}

//! Port of `tools/ci/sys_rules/messages.py` (doc/rewrite/systems.md section 15): message templates.
//!
//! `visible_pair` flags a hand-written actor message: a `visible_message(` call (outside the
//! act_message runtime) that carries a self message, names the actor/user in its text, is the second
//! half of a `to_chat(X)` + `X.visible_message` pair, or the retired interaction message fields.

use crate::dm::sys::{register_module, SysModule};
use crate::lint::{Registry, RuleMeta};
use crate::pat::Pat;
use crate::tree::SourceFile;
use crate::util::{is_py_space, py_lstrip, py_strip};
use crate::{pat, pat_match};

const RULES: &[RuleMeta] = &[RuleMeta {
    name: "visible_pair",
    hint: "act_message(user, target, MSG_SELF(), MSG_OTHERS(), MSG_BLIND()) or act_message_t() (doc/rewrite/systems.md section 15)",
}];

const RUNTIME_PREFIX: &str = "code/modules/messages/";

/// Top-level args of the call whose '(' ends at `start`. Returns (args, end_index).
fn split_args(text: &str, start: usize) -> (Vec<String>, usize) {
    let b = text.as_bytes();
    let n = b.len();
    let fin = |cur: &[u8]| py_strip(&String::from_utf8_lossy(cur)).to_string();
    let mut args: Vec<String> = Vec::new();
    let mut cur: Vec<u8> = Vec::new();
    let mut depth = 0i32;
    let mut i = start;
    let mut in_str = false;
    let mut br = 0i32;
    while i < n {
        let ch = b[i];
        if in_str {
            cur.push(ch);
            if ch == b'\\' {
                if i + 1 < n {
                    cur.push(b[i + 1]);
                }
                i += 2;
                continue;
            }
            if ch == b'[' {
                br += 1;
            } else if ch == b']' && br > 0 {
                br -= 1;
            } else if ch == b'"' && br == 0 {
                in_str = false;
            }
            i += 1;
            continue;
        }
        if ch == b'"' {
            in_str = true;
        } else if matches!(ch, b'(' | b'[' | b'{') {
            depth += 1;
        } else if matches!(ch, b')' | b']' | b'}') {
            if depth == 0 {
                args.push(fin(&cur));
                return (args, i);
            }
            depth -= 1;
        } else if ch == b',' && depth == 0 {
            args.push(fin(&cur));
            cur.clear();
            i += 1;
            continue;
        }
        // (the Python had a no-op `elif ch == "\n" ...: pass` branch here)
        cur.push(ch);
        i += 1;
    }
    args.push(fin(&cur));
    (args, i)
}

/// `[R]`, and the actor's name read off it: `[R.name]`, `[R.real_name]`.
fn named(arg: &str, name: &str) -> bool {
    match name {
        "src" => pat!(r"\[\s*src(?:\.(?:name|real_name))?\s*\]").is_match(arg),
        "user" => pat!(r"\[\s*user(?:\.(?:name|real_name))?\s*\]").is_match(arg),
        "usr" => pat!(r"\[\s*usr(?:\.(?:name|real_name))?\s*\]").is_match(arg),
        _ => Pat::new(&format!(r"\[\s*{}(?:\.(?:name|real_name))?\s*\]", regex::escape(name))).is_match(arg),
    }
}

fn scan(f: &SourceFile, out: &mut Vec<(&'static str, usize)>) {
    let rel = f.rel.replace('\\', "/");
    if rel.starts_with(RUNTIME_PREFIX) || !rel.ends_with(".dm") {
        return;
    }
    let raw = f.raw();
    let lines = raw.lines_vec();
    for (idx, line) in lines.iter().enumerate() {
        let code = line.split("//").next().unwrap_or("");
        if pat!(r"(?<![\w.])(message_self|message_others|start_messages|fill_message)\b").is_match(code) && !line.contains("ALLOW(sys_visible_pair)") {
            out.push(("visible_pair", idx + 1));
        }
    }
    let text = raw.text.as_str();
    if !text.contains("visible_message") {
        return;
    }
    // Line start offsets, and the enclosing proc for each line.
    let mut starts = vec![0usize];
    for line in &lines {
        starts.push(starts[starts.len() - 1] + line.len() + 1);
    }
    let mut proc_type: Vec<Option<String>> = vec![None; lines.len() + 1];
    let mut proc_start = vec![0usize; lines.len() + 1];
    let mut cur_type: Option<String> = None;
    let mut cur_start = 0usize;
    for (idx, line) in lines.iter().enumerate() {
        if let Some(m) = pat_match!(r"^(/[\w/]+?)(?:/proc|/verb)?/(\w+)\s*\(([^)]*)\)").captures(line) {
            cur_type = Some(m.s(1).to_string());
            cur_start = idx;
        } else if !line.is_empty() && !line.chars().next().map(is_py_space).unwrap_or(false) && !line.starts_with("//") && !line.starts_with('#') {
            cur_type = None;
        }
        proc_type[idx] = cur_type.clone();
        proc_start[idx] = cur_start;
    }
    let mut line_of = 0usize;
    for m in pat!(r"(?:\b([A-Za-z_]\w*)\s*\.\s*)?\bvisible_message\s*\(").captures_iter(text) {
        let mstart = m.start(0);
        while starts[line_of + 1] <= mstart {
            line_of += 1;
        }
        let line = lines[line_of];
        let code_before = &line[..mstart - starts[line_of]];
        if code_before.contains("//") || py_lstrip(code_before).starts_with('/') {
            continue;
        }
        if line.contains("ALLOW(sys_visible_pair)") {
            continue;
        }
        let recv: Option<&str> = if m.matched(1) { Some(m.s(1)) } else { None };
        let (raw_args, _) = split_args(text, m.end(0));
        // Named arguments (`self_message = x`, `range = 1`) are not positional.
        let mut args: Vec<String> = Vec::new();
        let mut kw: Vec<(String, String)> = Vec::new();
        for a in raw_args {
            if let Some(km) = pat_match!(r"(?s)([A-Za-z_]\w*)\s*=(?!=)(.*)$").captures(&a) {
                let (k, v) = (km.s(1).to_string(), py_strip(km.s(2)).to_string());
                match kw.iter_mut().find(|e| e.0 == k) {
                    Some(e) => e.1 = v,
                    None => kw.push((k, v)),
                }
            } else {
                args.push(a);
            }
        }
        let kwget = |name: &str| kw.iter().find(|e| e.0 == name).map(|e| e.1.clone());
        if let Some(v) = kwget("message") {
            args.insert(0, v);
        }
        let second: String = kwget("self_message").unwrap_or_else(|| if args.len() > 1 { args[1].clone() } else { String::new() });
        let extra: Vec<String> = kw.iter().filter(|(k, _)| k == "self_message" || k == "blind_message").map(|(_, v)| v.clone()).collect();
        args.extend(extra);
        let ptype = proc_type[line_of].clone().unwrap_or_default();
        let in_mob = ptype.starts_with("/mob");
        let mut recv_is_mob = false;
        match recv {
            Some(r) => {
                if r == "user" || r == "usr" {
                    recv_is_mob = true;
                } else {
                    let head = lines[proc_start[line_of]..=line_of].join("\n");
                    recv_is_mob = Pat::new(&format!(r"\bmob/[\w/]*\b{}\b", regex::escape(r))).is_match(&head);
                }
            }
            None => {
                if in_mob {
                    recv_is_mob = true;
                }
            }
        }
        let mut flagged = false;
        // 1. a self message
        if recv_is_mob && !second.is_empty() && second != "null" && !second.starts_with("exclude") {
            flagged = true;
        }
        // 2. the actor names itself or its user
        let joined = args.iter().take(3).cloned().collect::<Vec<_>>().join(" ");
        if let Some(r) = recv {
            if recv_is_mob && named(&joined, r) && r != "src" {
                flagged = true;
            }
        }
        if (recv.is_none() || recv == Some("src")) && in_mob && named(&joined, "src") {
            flagged = true;
        }
        if named(&joined, "user") || named(&joined, "usr") {
            flagged = true;
        }
        // 3. to_chat(X) then X.visible_message
        if !flagged && line_of > 0 {
            let mut prev = line_of - 1;
            while prev > 0 && py_strip(lines[prev]).is_empty() {
                prev -= 1;
            }
            if let Some(tc) = pat_match!(r"^\s*to_chat\s*\(\s*([A-Za-z_]\w*)\s*,").captures(lines[prev]) {
                if tc.s(1) == recv.unwrap_or("src") {
                    flagged = true;
                }
            }
        }
        if flagged {
            out.push(("visible_pair", line_of + 1));
        }
    }
}

pub fn register(reg: &mut Registry) {
    register_module(reg, SysModule { name: "messages", rules: RULES, file_scan: Some(scan), ..SysModule::DEFAULT });
}

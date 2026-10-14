//! Port of `tools/ci/sys_rules/sfx.py` (doc/rewrite/systems.md section 16): sound and effect sets.
//!
//! `literal_playsound` (a literal sound file in a playsound call), `literal_sound_var` (a literal
//! sound file held by a var/list that is fed to playsound), `sfx_string_key` (a bare string key
//! instead of its SFX_* id) and `spark_triple` (any use of the deleted spark_spread system).

use std::collections::HashSet;

use serde::{Deserialize, Serialize};

use crate::dm::sys::{register_module, SysModule};
use crate::incr;
use crate::lint::{Registry, RuleMeta};
use crate::pat::Pat;
use crate::tree::{SourceFile, Tree};
use crate::util::{py_lstrip, py_rstrip};
use crate::{pat, pat_match};

const RULES: &[RuleMeta] = &[
    RuleMeta {
        name: "literal_playsound",
        hint: "play_sfx(atom, SFX_ID) with a SOUND_SET row (code/game/sound_sets.dm), not a literal file",
    },
    RuleMeta { name: "literal_sound_var", hint: "hold a SOUND_SET id (SFX_*) in sound vars/lists fed to playsound, not a literal file" },
    RuleMeta { name: "sfx_string_key", hint: "pass the SFX_* id, not the bare string key" },
    RuleMeta { name: "spark_triple", hint: "fx_sparks(atom, amount, cardinals), not a spark_spread new/set_up/start" },
];

const NOT_FED: &[&str] = &["src", "null", "TRUE", "FALSE", "usr", "user", "loc"];

fn code_of(line: &str) -> &str {
    line.split("//").next().unwrap_or("")
}

fn literal() -> &'static Pat {
    pat!(r"'[^'\n]+\.(?:ogg|wav|mid|mp3)'")
}

/// The text from `lines[index][start..]` up to its closing paren / end of statement, following open
/// parens and backslash continuations onto later lines. `start` doubles as a flag (quirk: a call at
/// column 0 has `start == 0`, which turns the early return off).
fn statement(lines: &[&str], index: usize, start: usize) -> String {
    let mut depth = 0i32;
    let mut out = String::new();
    let mut k = index;
    let mut col = start;
    while k < lines.len() && k < index + 40 {
        let code = code_of(lines[k]);
        let line = code.get(col..).unwrap_or("");
        col = 0;
        for c in line.chars() {
            out.push(c);
            if c == '(' || c == '[' {
                depth += 1;
            } else if c == ')' || c == ']' {
                depth -= 1;
                if depth <= 0 && start != 0 {
                    return out;
                }
            }
        }
        let stripped = py_rstrip(line);
        if depth <= 0 && !stripped.ends_with('\\') && !(start == 0 && stripped.ends_with(',')) {
            break;
        }
        out.push('\n');
        k += 1;
    }
    out
}

/// `ASSIGN.finditer(code)` as `(name, match end)`. The pattern is
/// `(?:^|[^\w.])(?:var/(?:\w+/)*)?(\w+)\s*(?<![!<>=])=(?!=)\s*(?:pick\s*\(|list\s*\()?`. The lookbehind
/// is always true (a word char or whitespace precedes the `=`), so only `(?!=)` is checked by hand.
fn assign_matches(code: &str) -> Vec<(String, usize)> {
    let mut out = Vec::new();
    let head = pat!(r"(?:^|[^\w.])(?:var/(?:\w+/)*)?(\w+)\s*=");
    let mut pos = 0;
    while pos <= code.len() {
        let Some(c) = head.captures_at(code, pos) else { break };
        let (s, e) = (c.start(0), c.end(0));
        if code.as_bytes().get(e) == Some(&b'=') {
            // `==`: the lookahead fails; the search resumes one character after this start.
            pos = s + code[s..].chars().next().map(|ch| ch.len_utf8()).unwrap_or(1);
            continue;
        }
        let rest = &code[e..];
        let ws = rest.len() - crate::util::py_lstrip(rest).len();
        let mut end = e + ws;
        if let Some(m) = pat_match!(r"(?:pick\s*\(|list\s*\()").find(&code[end..]) {
            end += m.end;
        }
        out.push((c.s(1).to_string(), end));
        pos = end;
    }
    out
}

fn py_slice(text: &str, a: isize, b: isize) -> String {
    let chars: Vec<char> = text.chars().collect();
    let len = chars.len() as isize;
    let norm = |i: isize| if i < 0 { (len + i).max(0) } else { i.min(len) };
    let (a, b) = (norm(a), norm(b));
    if a >= b {
        String::new()
    } else {
        chars[a as usize..b as usize].iter().collect()
    }
}

fn char_find(text: &str, needle: &str) -> isize {
    text.find(needle).map(|byte| text[..byte].chars().count() as isize).unwrap_or(-1)
}

fn scan_file(f: &SourceFile, fed: &HashSet<String>, named: &HashSet<String>, out: &mut Vec<(&'static str, usize)>) {
    let rel = f.rel.as_str();
    if rel == "code/game/sound_sets.dm" {
        return;
    }
    let lines = f.raw().lines_vec();
    let have_named = !named.is_empty();
    for (idx, line) in lines.iter().enumerate() {
        let number = idx + 1;
        let code = code_of(line);
        if pat!(r"\bspark_spread\b").is_match(code) {
            out.push(("spark_triple", number));
        }
        let soundy = code.contains("playsound") || code.contains("get_sfx");
        if code.contains("playsound") {
            for m in pat!(r"(?<![\w./])playsound(?:_local)?\s*\(").find_iter(code) {
                if literal().is_match(&statement(&lines, idx, m.start)) {
                    out.push(("literal_playsound", number));
                }
            }
        }
        if soundy && pat!(r#"(?<![\w./])(?:playsound(?:_local)?\s*\([^,()]+|get_sfx\s*\()\s*,?\s*"[a-z_]+""#).is_match(code) {
            out.push(("sfx_string_key", number));
        } else if have_named && code.contains('=') {
            for m in pat!(r#"(?:^|[^\w.])(\w+)\s*=\s*"(\w+)""#).captures_iter(code) {
                if fed.contains(m.s(1)) && named.contains(m.s(2)) {
                    out.push(("sfx_string_key", number));
                    break;
                }
            }
        }
        if py_lstrip(code).starts_with("#define") {
            continue;
        }
        let mut names: Vec<(String, usize)> = Vec::new();
        let gm = if code.contains("GLOBAL_LIST_INIT") { pat!(r"GLOBAL_LIST_INIT\s*\(\s*(\w+)\s*,").captures(code) } else { None };
        if let Some(gm) = gm {
            names.push((gm.s(1).to_string(), gm.end(0)));
        } else if code.contains('=') {
            names = assign_matches(code);
        }
        for (name, end) in names {
            if !fed.contains(&name) {
                continue;
            }
            if literal().is_match(statement(&lines, idx, 0).get(end..).unwrap_or("")) {
                out.push(("literal_sound_var", number));
                break;
            }
        }
    }
}

/// One file's contribution to the shared context: the names it feeds to a sound call, and (for
/// `code/__defines/sfx.dm` only) the named-set ids.
#[derive(Serialize, Deserialize, Default, PartialEq)]
struct Facts {
    fed: Vec<String>,
    named: Vec<String>,
}

fn facts_of(f: &SourceFile) -> Facts {
    let mut set: HashSet<String> = HashSet::new();
    for line in f.raw().lines() {
        let code = code_of(line);
        if !code.contains('(') || !(code.contains("playsound") || code.contains("play_sfx") || code.contains("get_sfx")) {
            continue;
        }
        for m in pat!(
            r"(?<![\w./])(?:playsound(?:_local)?|play_sfx)\s*\(\s*[^,()]+(?:\([^()]*\))?\s*,\s*(?:pick\s*\(\s*)?([A-Za-z_][\w.]*)\s*\)?\s*[,)]|(?<![\w./])get_sfx\s*\(\s*(?:pick\s*\(\s*)?([A-Za-z_][\w.]*)\s*\)?\s*\)"
        )
        .captures_iter(code)
        {
            let name = if m.matched(1) { m.s(1) } else { m.s(2) };
            set.insert(name.rsplit('.').next().unwrap_or("").to_string());
        }
    }
    let mut fed: Vec<String> = set.into_iter().collect();
    fed.sort();
    let mut named: Vec<String> = Vec::new();
    if f.rel == "code/__defines/sfx.dm" {
        let text = f.raw().text.as_str();
        let section = py_slice(text, char_find(text, "// Named sets"), char_find(text, "// File sets."));
        named = pat!(r#"#define SFX_\w+ "(\w+)""#).captures_iter(&section).iter().map(|c| c.s(1).to_string()).collect();
        named.sort();
        named.dedup();
    }
    Facts { fed, named }
}

/// What the judge reads: the fed names (minus the ones that never name a sound) and the named sets.
struct Context {
    fed: HashSet<String>,
    named: HashSet<String>,
}

fn scan(_tree: &Tree, files: &[&SourceFile]) -> Vec<(&'static str, String, usize)> {
    let (_ctx, results) = incr::two_phase(
        "sys-sfx",
        files,
        facts_of,
        |pairs| {
            let mut fed: HashSet<String> = HashSet::new();
            let mut named: HashSet<String> = HashSet::new();
            for (f, facts) in pairs {
                fed.extend(facts.fed.iter().cloned());
                if f.rel == "code/__defines/sfx.dm" {
                    named = facts.named.iter().cloned().collect();
                }
            }
            for n in NOT_FED {
                fed.remove(*n);
            }
            Context { fed, named }
        },
        |f, ctx| {
            let mut v: Vec<(&'static str, usize)> = Vec::new();
            scan_file(f, &ctx.fed, &ctx.named, &mut v);
            v.into_iter().map(|(rule, line)| (RULES.iter().position(|r| r.name == rule).unwrap_or(0) as u8, line as u32)).collect::<Vec<(u8, u32)>>()
        },
    );
    let mut out = Vec::new();
    for (f, v) in files.iter().zip(results) {
        for (rule, line) in v {
            out.push((RULES[rule as usize].name, f.rel.clone(), line as usize));
        }
    }
    out
}

pub fn register(reg: &mut Registry) {
    register_module(reg, SysModule { name: "sfx", rules: RULES, files_scan: Some(scan), ..SysModule::DEFAULT });
}

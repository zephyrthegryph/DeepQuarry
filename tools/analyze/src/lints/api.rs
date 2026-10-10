//! Port of `tools/ci/api_lints.py`: the one-way-to-do-it lints (doc/rewrite/object_model_core.md
//! sec 16). Each rule is a banned alternative to the object model's one mechanism for a job.
//!
//! Every rule but `field_write` looks at one file's code view (comments and strings blanked);
//! `field_write` needs the global declared-field index (`dm::field_write`) and runs in
//! `scan_tree`. Unit tests are skipped by every rule except `field_write`. Findings are numbered
//! in the CODE view's lines (the Python indexed the raw lines with them for ALLOW); kept as is.

use std::collections::{BTreeMap, HashMap};
use std::sync::OnceLock;

use serde::{Deserialize, Serialize};

use crate::dm::field_write::{Fields, FwlIndex};
use crate::dm::pylines::recorded_into;
use crate::incr;
use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::parity::{ParseKind, Parity};
use crate::pat::Pat;
use crate::pat_match;
use crate::tree::{SourceFile, CODE_DM};
use crate::util::{py_lstrip, py_strip};

const HINT: &str = "use the one mechanism doc/rewrite/object_model_core.md sec 16 names";

macro_rules! rules {
    ($($n:literal),* $(,)?) => { &[$(RuleMeta { name: $n, hint: HINT }),*] };
}

static META: Meta = Meta {
    name: "api",
    group: "",
    label: "api",
    legacy: "tools/ci/api_lints.py",
    select: CODE_DM,
    scan: ScanKind::Both,
    policy: Policy::Sites {
        baseline: "tools/ci/api_lints_baseline.txt",
        header: &[
            "api lint legacy sites (tools/ci/api_lints.py). rule<TAB>file<TAB>normalized line.",
            "A site not listed here fails. Shrink-only: after a sweep, `python tools/ci/api_lints.py --update`.",
        ],
        banned: &[],
    },
    rules: rules![
        "do_after_state",
        "use_tool_state",
        "vars_helpers",
        "vars_write",
        "timer_cooldown",
        "accessor_macros",
        "field_write",
        "raw_world_bind",
        "string_keys",
        "prompt_spec",
        "task_params_list",
        "reactor_api",
        "raw_relation",
    ],
    allow: &["api"],
    lists: &[],
};

/// `split_args`: top-level comma split (depth over `([{` / `)]}`, may go negative), each stripped,
/// a trailing empty piece dropped.
fn split_args(s: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut depth: i32 = 0;
    let mut cur = String::new();
    for c in s.chars() {
        if "([{".contains(c) {
            depth += 1;
        } else if ")]}".contains(c) {
            depth -= 1;
        }
        if c == ',' && depth == 0 {
            out.push(py_strip(&cur).to_string());
            cur.clear();
        } else {
            cur.push(c);
        }
    }
    if !py_strip(&cur).is_empty() {
        out.push(py_strip(&cur).to_string());
    }
    out
}

/// `calls(text, name)`: `(line number in text, argument text)` of every call of `name`.
fn calls(f: &SourceFile, name: &str, pat: &Pat) -> Vec<(usize, String)> {
    let text = &f.code().text;
    if !text.contains(name) {
        return Vec::new();
    }
    let mut out = Vec::new();
    for m in pat.find_iter(text) {
        if text[..m.start].ends_with("proc/") {
            continue;
        }
        let rest = &text[m.end..];
        let mut depth = 1;
        let mut end = None;
        for (off, ch) in rest.char_indices() {
            if ch == '(' {
                depth += 1;
            } else if ch == ')' {
                depth -= 1;
            }
            if depth == 0 {
                end = Some(off);
                break;
            }
        }
        // Unterminated call: Python slices `text[m.end():len-1]` (drops the last char).
        let args = match end {
            Some(off) => &rest[..off],
            None => match rest.char_indices().last() {
                Some((off, _)) => &rest[..off],
                None => "",
            },
        };
        out.push((f.code().line_of(m.start), args.to_string()));
    }
    out
}

/// `state_args`: how many arguments the call passes through its argument lists (99: built elsewhere).
fn state_args(argtext: &str, positional: &[usize], named: &[&str]) -> usize {
    let mut n = 0;
    for (i, arg) in split_args(argtext).iter().enumerate() {
        let m = pat_match!(r"(?s)(\w+)\s*=(?!=)\s*(.*)$").captures(arg);
        let value = match &m {
            Some(c) if named.contains(&c.s(1)) => py_strip(c.s(2)).to_string(),
            None if positional.contains(&i) => arg.clone(),
            _ => continue,
        };
        if value == "null" || value.is_empty() {
            continue;
        }
        n += match pat_match!(r"(?s)list\((.*)\)$").captures(&value) {
            Some(lm) => split_args(lm.s(1)).len(),
            None => 99,
        };
    }
    n
}

fn not_define(f: &SourceFile, line: usize) -> bool {
    !py_lstrip(f.code().line(line)).starts_with("#define")
}

/// `pattern(regex)` / `outside(prefix, regex)`: one site per match on every non-`#define` line.
fn pattern_sites(f: &SourceFile, pat: &Pat) -> Vec<usize> {
    let mut out = Vec::new();
    for (no, line) in f.code().numbered() {
        if py_lstrip(line).starts_with("#define") {
            continue;
        }
        for _ in pat.find_iter(line) {
            out.push(no);
        }
    }
    out
}

fn emit(out: &mut Sink, f: &SourceFile, rule: &str, line: usize) {
    if !out.allowed(f, line, "api") {
        out.site(rule, line);
    }
}

/// One file's part of the declared-field index (`FwlIndex::build` over that one file).
#[derive(Serialize, Deserialize, Default, PartialEq)]
struct FwFacts {
    fields: Vec<(String, Vec<String>)>,
    members: BTreeMap<String, BTreeMap<String, String>>,
    globals: BTreeMap<String, String>,
}

fn fw_facts(f: &SourceFile) -> FwFacts {
    let one = FwlIndex::build(&[f]);
    FwFacts {
        fields: one.fields,
        members: one.members.into_iter().map(|(k, v)| (k, v.into_iter().collect())).collect(),
        globals: one.globals.into_iter().collect(),
    }
}

/// The tree-wide index: what `FwlIndex::build` makes of every file, merged in file order (field
/// names in first-seen order, last writer wins for a member or a global).
fn merge_index(facts: &[FwFacts]) -> FwlIndex {
    let mut fields: Vec<(String, Vec<String>)> = Vec::new();
    let mut at: HashMap<String, usize> = HashMap::new();
    let mut members: BTreeMap<String, BTreeMap<String, String>> = BTreeMap::new();
    let mut globals: BTreeMap<String, String> = BTreeMap::new();
    for fa in facts {
        for (name, types) in &fa.fields {
            match at.get(name) {
                Some(&i) => fields[i].1.extend(types.iter().cloned()),
                None => {
                    at.insert(name.clone(), fields.len());
                    fields.push((name.clone(), types.clone()));
                }
            }
        }
        for (owner, vars) in &fa.members {
            let slot = members.entry(owner.clone()).or_default();
            for (name, ty) in vars {
                slot.insert(name.clone(), ty.clone());
            }
        }
        for (name, ty) in &fa.globals {
            globals.insert(name.clone(), ty.clone());
        }
    }
    FwlIndex { fields, members, globals }
}

fn sorted_members(index: &FwlIndex) -> BTreeMap<&String, BTreeMap<&String, &String>> {
    index.members.iter().map(|(k, v)| (k, v.iter().collect())).collect()
}

fn sorted_globals(index: &FwlIndex) -> BTreeMap<&String, &String> {
    index.globals.iter().collect()
}

struct Api {
    call_pats: Vec<(&'static str, Pat)>,
    vars_helpers: Pat,
    vars_write: Pat,
    timer_cooldown: Pat,
    accessor_macros: Pat,
    raw_world_bind: Pat,
    string_keys: Pat,
    reactor_api: Pat,
    raw_relation: Pat,
}

const PROMPT_NAMES: &[&str] = &[
    "om_prompt",
    "om_prompt_sequence",
    "om_prompt_chain",
    "topic_prompt",
    "act_prompt",
    "verb_prompt",
    "client_prompt",
    "rerun_prompt",
    "surgery_prompt",
    "cast_prompt",
];

impl Api {
    fn calls(&self, f: &SourceFile, name: &str) -> Vec<(usize, String)> {
        let (n, p) = self.call_pats.iter().find(|(n, _)| *n == name).unwrap();
        calls(f, n, p)
    }

    fn new() -> Api {
        let mut names = vec!["om_task_timed", "use_tool", "om_task_start"];
        names.extend_from_slice(PROMPT_NAMES);
        Api {
            call_pats: names.into_iter().map(|n| (n, Pat::new(&format!(r"(?<![\w/.]){}\s*\(", regex::escape(n))))).collect(),
            vars_helpers: Pat::new(r"\b(?:om_set_var(?:_then)?|om_toggle_var|cure_temporary_s?disability)\b"),
            vars_write: Pat::new(r"\bvars\[[^\]]*\]\s*=(?!=)"),
            timer_cooldown: Pat::new(r"\bS?_?TIMER_COOLDOWN_START\s*\("),
            accessor_macros: Pat::new(
                r"(?<![\w/])(?:BUCKLED|BUCKLED_MOBS|PULLING|PULLED_BY|GRABBED_BY|EYE_OWNER|EYES_OF|ACTIVE_EYE|GRAB_TARGET|ORBIT_TARGET|ORBITERS|GRAB_ASSAILANT|LEASH_PET|LEASH_MASTER|LEASH_OF|TETHERED_HANDHELD|TETHER_HOST|FOLLOWING|FOLLOWERS|BORER_HOST|BORER_OF|BS_TX_TARGET|BS_TX_RADIOS|BS_RX_SOURCE|BS_RX_RADIOS|GRIPPER_HELD|UAV_MASTERS|STASIS_SOURCE|SLOT_ITEM|SLOT_LIST|OM_REL_TARGETS?|OM_REL_SOURCES?)\s*\(",
            ),
            raw_world_bind: Pat::new(r"(?<![\w/])vg_world_(?:at|on_key|watch_\w+|rate_watch|step|clear|cancel)\s*\("),
            string_keys: Pat::new(r#"\bom_world_(?:publish|on_key)\([^)\n]*""#),
            reactor_api: Pat::new(r"\b(?:SSreactor|on_react|react_every|react_sleep_violation|reactor_id|REACT_[A-Z_]+)\b"),
            raw_relation: Pat::new(r"(?<![\w/.])om_(?:relation_of|source_of|related|related_to)\s*\("),
        }
    }
}

impl Lint for Api {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_file(&self, _cx: &Cx, f: &SourceFile, out: &mut Sink) {
        if f.rel.contains("/unit_tests/") {
            return; // only field_write scans tests
        }
        let rel = f.rel.as_str();
        // CHECKS order (sites are per rule, so only the order inside a rule matters).
        for (line, args) in self.calls(f, "om_task_timed") {
            if state_args(&args, &[5, 8, 10], &["done_args", "fail_args", "check_args"]) > 2 {
                emit(out, f, "do_after_state", line);
            }
        }
        for (line, args) in self.calls(f, "use_tool") {
            if state_args(&args, &[], &["done_args", "fail_args"]) > 2 {
                emit(out, f, "use_tool_state", line);
            }
        }
        for l in pattern_sites(f, &self.vars_helpers) {
            emit(out, f, "vars_helpers", l);
        }
        if !rel.starts_with("code/engine/state/field_tables.dm") {
            for l in pattern_sites(f, &self.vars_write) {
                emit(out, f, "vars_write", l);
            }
        }
        for l in pattern_sites(f, &self.timer_cooldown) {
            emit(out, f, "timer_cooldown", l);
        }
        for l in pattern_sites(f, &self.accessor_macros) {
            emit(out, f, "accessor_macros", l);
        }
        if rel != "code/engine/time/native_wakes.dm" && rel != "code/engine/time/world_watches.dm" && rel != "code/datums/om/world_watch.dm" {
            for l in pattern_sites(f, &self.raw_world_bind) {
                emit(out, f, "raw_world_bind", l);
            }
        }
        for l in pattern_sites(f, &self.string_keys) {
            emit(out, f, "string_keys", l);
        }
        if !rel.starts_with("code/datums/om/") {
            for name in PROMPT_NAMES {
                for (line, _) in self.calls(f, name) {
                    if not_define(f, line) {
                        emit(out, f, "prompt_spec", line);
                    }
                }
            }
        }
        for (line, args) in self.calls(f, "om_task_start") {
            let parts = split_args(&args);
            if parts.len() > 3 && !pat_match!(r"\w+\s*=(?!=)").is_match(&parts[3]) && not_define(f, line) {
                emit(out, f, "task_params_list", line);
            }
        }
        for l in pattern_sites(f, &self.reactor_api) {
            emit(out, f, "reactor_api", l);
        }
        if !rel.starts_with("code/datums/om/") {
            for l in pattern_sites(f, &self.raw_relation) {
                emit(out, f, "raw_relation", l);
            }
        }
    }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        // field_write: every file, unit tests included. The global declared-field index is the merge
        // of per-file facts (cached by content); one file's judgement is cached by (content, index).
        let all = cx.all_files();
        let facts = incr::facts("api-fw-facts", &all, fw_facts);
        let files = cx.files();
        let index = merge_index(&facts);
        let key = incr::ctx_key(&(&index.fields, sorted_members(&index), sorted_globals(&index)));
        let fields: OnceLock<Fields> = OnceLock::new();
        let found = recorded_into(out, || {
            incr::keyed("api-fw-judge", key, &files, |f| {
                let fields = fields.get_or_init(|| index.all_fields());
                let mut kept: Vec<u32> = Vec::new();
                for line in index.check(fields, &f.code().text) {
                    if !crate::dm::sys::kept_recorded(f, line, "api") {
                        kept.push(line as u32);
                    }
                }
                kept
            })
        });
        for (f, lines) in files.iter().zip(found) {
            for line in lines {
                out.site_in("field_write", &f.rel, line as usize);
            }
        }
    }

    fn parity(&self) -> Option<Parity> {
        Some(Parity {
            old: &["tools/ci/api_lints.py"],
            old_raw: &[&["tools/ci/api_lints.py", "--report"]],
            blank: &[],
            parse: ParseKind::Report,
            update: Some(&["tools/ci/api_lints.py", "--update"]),
            seed: Some(&["tools/ci/api_lints.py", "--seed"]),
            files: &["tools/ci/api_lints_baseline.txt"],
            selftest: None,
        })
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(Api::new());
}

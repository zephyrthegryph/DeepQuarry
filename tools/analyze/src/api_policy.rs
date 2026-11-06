//! Unique original API lexical rules and lexical field-index merge. DATA only.
use std::collections::{BTreeMap,HashMap};
use serde::{Serialize,Deserialize};use crate::{dm::field_write::FwlIndex,lint::{Meta,Policy,RuleMeta,ScanKind},tree::CODE_DM,pat::Pat,pat_match,util::{py_lstrip,py_strip}};
use crate::tree::SourceFile;
pub trait Reporter{fn allowed(&mut self,line:usize)->bool;fn site(&mut self,rule:&str,line:usize);}
const HINT: &str = "use the one mechanism doc/rewrite/object_model_core.md sec 16 names";

macro_rules! rules {
    ($($n:literal),* $(,)?) => { &[$(RuleMeta { name: $n, hint: HINT }),*] };
}

pub static META: Meta = Meta {
    name: crate::allow_registry_fields::api::SCOPE_META_0.name,
    group: crate::allow_registry_fields::api::SCOPE_META_0.group,
    label: "api",
    legacy: "tools/ci/api_lints.py",
    select: CODE_DM,
    scan: ScanKind::Both,
    policy: Policy::Hard,
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
    allow: crate::allow_registry_fields::api::ALLOW_0,
    lists: crate::allow_registry_fields::api::SCOPE_META_0.lists,
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

fn emit(out: &mut impl Reporter, _f: &SourceFile, rule: &str, line: usize) {
    if !out.allowed(line) {
        out.site(rule, line);
    }
}

/// One file's part of the declared-field index (`FwlIndex::build` over that one file).
#[derive(Clone,Serialize, Deserialize, Default, PartialEq)]
pub struct FwFacts {
    pub fields: Vec<(String, Vec<String>)>,
    pub members: BTreeMap<String, BTreeMap<String, String>>,
    pub globals: BTreeMap<String, String>,
}

pub fn fw_facts(f: &SourceFile) -> FwFacts {
    let p=FwlIndex::facts_from_views(f.raw(),f.code());
    let one=FwlIndex::merge_facts(std::iter::once(p));
    FwFacts {
        fields: one.fields,
        members: one.members.into_iter().map(|(k, v)| (k, v.into_iter().collect())).collect(),
        globals: one.globals.into_iter().collect(),
    }
}

/// The tree-wide index: what `FwlIndex::build` makes of every file, merged in file order (field
/// names in first-seen order, last writer wins for a member or a global).
pub fn merge_index(facts: &[FwFacts]) -> FwlIndex {
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

pub fn sorted_members(index: &FwlIndex) -> BTreeMap<&String, BTreeMap<&String, &String>> {
    index.members.iter().map(|(k, v)| (k, v.iter().collect())).collect()
}

pub fn sorted_globals(index: &FwlIndex) -> BTreeMap<&String, &String> {
    index.globals.iter().collect()
}

pub struct Api {
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

    pub fn new() -> Api {
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


impl Api{pub fn scan_file(&self,f:&SourceFile,out:&mut impl Reporter){
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
        // The by-name field owners: the declared-field table, and the weak-reference store (code/engine/refs/weak.dm: a weak var holds a handle,
        // written only by weak_set/weak_add/weak_clear, which rel_set/rel_add/rel_clear dispatch to; relations proposal D5).
        if !rel.starts_with("code/engine/state/field_tables.dm") && rel != "code/engine/refs/weak.dm" {
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
}}

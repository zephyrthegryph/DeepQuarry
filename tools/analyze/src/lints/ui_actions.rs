//! Port of `tools/ci/ui_actions_lint.py`: TSX `act()` calls against `act_<action>` procs
//! (doc/rewrite/dx_conventions.md section 5; design review C1, C2).
//!
//! Whole-tree lint over `code/**/*.dm` and the tgui interface sources. Hard failures (an act()
//! the dispatcher rejects or no host answers, a key it drops or the proc doesn't declare) are the
//! banned rule `problem`; the C1/C2 ratchets are `ui_unsent_param` / `ui_unvalidated_param` on the
//! fingerprint baseline. The dispatcher's `ui_action_key()` normalisation is read out of
//! `code/datums/capabilities/ui_actions.dm`, as in the Python.
//!
//! Quirks replicated: the problem list is not baselined and ignores ALLOW; an unsent parameter
//! yields one site per parameter (several sites on the proc head line); `$` in the dispatcher's
//! raw regex keeps Python's "also before a trailing newline" meaning.

use std::cell::{OnceCell, RefCell};
use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};
use std::rc::Rc;
use serde::{Deserialize, Serialize};

use crate::dm::dx::{enclosing_call, is_subtype, lineage, procs_in, Proc};
use crate::incr;
use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::parity::{ParseKind, Parity};
use crate::pat::{Caps, Pat};
use crate::tree::{Select, SourceFile, Tree};
use crate::util::{is_py_space, py_rstrip, py_strip};
use crate::{pat, pat_match};

const DISPATCHER: &str = "code/datums/capabilities/ui_actions.dm";
const INTERFACES: &str = "tgui/packages/tgui/interfaces";
const BASELINE: &str = "tools/ci/ui_actions_baseline.txt";
const CAP_ROOT: &str = "/datum/capability";
const CAPS_DIR: &str = "code/datums/capabilities/";
/// Framework types whose act_ procs every host inherits (the modal actions).
const BUILTIN_HOSTS: [&str; 2] = ["/datum", "/atom"];
const VALIDATORS: [&str; 5] = ["ui_number", "ui_text", "ui_choice", "ui_ref", "ui_bool"];

const R_UNSENT: &str = "ui_unsent_param";
const R_UNVALIDATED: &str = "ui_unvalidated_param";
const R_PROBLEM: &str = "problem";

static META: Meta = Meta {
    name: "ui_actions",
    group: "",
    label: "ui_actions",
    legacy: "tools/ci/ui_actions_lint.py",
    select: Select {
        roots: &[
            ("code", "dm"),
            (INTERFACES, "tsx"),
            (INTERFACES, "ts"),
            (INTERFACES, "jsx"),
            (INTERFACES, "js"),
        ],
        hidden: false,
    },
    scan: ScanKind::Tree,
    policy: Policy::Sites {
        baseline: BASELINE,
        header: &["ui_actions_lint C1/C2 baseline (design review C1, C2); shrink-only, target 0"],
        banned: &[R_PROBLEM],
    },
    rules: &[
        RuleMeta {
            name: R_UNSENT,
            hint: "every act_ parameter must be sent by some TSX act(); move internal flags to an internal proc (design review C1)",
        },
        RuleMeta {
            name: R_UNVALIDATED,
            hint: "validate the parameter first: ui_number/ui_text/ui_choice/ui_ref/ui_bool(param), or compare it to a constant (design review C2)",
        },
        RuleMeta {
            name: R_PROBLEM,
            hint: "make the act() match an act_ proc of the interface's host (dispatcher rules: code/datums/capabilities/ui_actions.dm)",
        },
    ],
    allow: &["ui_actions"],
    lists: &[],
};

// ---- the dispatcher's normalisation -----------------------------------------------------------

/// Python's `$` (no MULTILINE) also matches just before a final newline; the regex crate's does
/// not. Rewrites each unescaped `$` outside a class as `(?=\n?\z)`.
fn py_dollar(pattern: &str) -> String {
    let mut out = String::new();
    let mut in_class = false;
    let mut chars = pattern.chars().peekable();
    while let Some(c) = chars.next() {
        match c {
            '\\' => {
                out.push(c);
                if let Some(n) = chars.next() {
                    out.push(n);
                }
            }
            '[' if !in_class => {
                in_class = true;
                out.push(c);
            }
            ']' if in_class => {
                in_class = false;
                out.push(c);
            }
            '$' if !in_class => out.push_str(r"(?=\n?\z)"),
            _ => out.push(c),
        }
    }
    out
}

struct Normaliser {
    raw: Pat,
    camel: Pat,
    /// Python template (`\1_\2`).
    replacement: String,
    max_length: usize,
    reserved: HashSet<String>,
}

impl Normaliser {
    /// `ui_action_key(raw)`, or None where the dispatcher rejects it.
    fn key(&self, raw: &str) -> Option<String> {
        if raw.is_empty() || raw.chars().count() > self.max_length || !self.raw.is_match(raw) {
            return None;
        }
        let s = self.camel.replace_with(raw, |c: &Caps| expand_template(&self.replacement, c));
        Some(s.to_lowercase().replace('-', "_"))
    }
}

/// Python `re` template expansion for `\N` group references; other text is literal.
fn expand_template(template: &str, c: &Caps) -> String {
    let mut out = String::new();
    let mut it = template.chars().peekable();
    while let Some(ch) = it.next() {
        if ch == '\\' {
            if let Some(d) = it.peek().copied().filter(|d| d.is_ascii_digit()) {
                it.next();
                out.push_str(c.s(d.to_digit(10).unwrap() as usize));
                continue;
            }
        }
        out.push(ch);
    }
    out
}

/// `normaliser_from`: the Normaliser read from the dispatcher source, or the message naming what
/// is missing.
fn normaliser_from(text: &str) -> Result<Normaliser, String> {
    let missing = |name: &str| {
        format!(
            "ui_actions_lint: can't find the dispatcher's {} in {}; update PARITY (and the lint) to match ui_action_key()",
            name, DISPATCHER
        )
    };
    let patterns: [(&str, &Pat); 7] = [
        ("raw", pat!(r#"GLOBAL_DATUM_INIT\(\s*ui_action_raw_regex\s*,\s*/regex\s*,\s*regex\(\s*@?"([^"]+)""#)),
        ("camel", pat!(r#"GLOBAL_DATUM_INIT\(\s*ui_action_camel_regex\s*,\s*/regex\s*,\s*regex\(\s*@?"([^"]+)""#)),
        ("replacement", pat!(r#"ui_action_camel_regex\.Replace\(\s*\w+\s*,\s*"([^"]+)"\s*\)"#)),
        ("max_length", pat!(r"length\(raw\)\s*>\s*(\d+)")),
        ("reserved", pat!(r"GLOBAL_LIST_INIT\(\s*ui_reserved_arg_names\s*,\s*list\(([^)]*)\)")),
        ("lower", pat!(r"lowertext\(")),
        ("hyphen", pat!(r#"replacetext\([^,]+,\s*"-"\s*,\s*"_"\s*\)"#)),
    ];
    let mut found: HashMap<&str, String> = HashMap::new();
    for (name, pattern) in patterns {
        let Some(m) = pattern.captures(text) else { return Err(missing(name)) };
        found.insert(name, m.get(1).unwrap_or("").to_string());
    }
    let reserved: HashSet<String> = pat!(r#""(\w+)""#).captures_iter(&found["reserved"]).iter().map(|c| c.s(1).to_string()).collect();
    // `re.sub(r"\$(\d)", r"\\\1", replacement)`
    let replacement = pat!(r"\$(\d)").replace_with(&found["replacement"], |c| format!("\\{}", c.s(1)));
    Ok(Normaliser {
        raw: Pat::new(&py_dollar(&found["raw"])),
        camel: Pat::new(&py_dollar(&found["camel"])),
        replacement,
        max_length: found["max_length"].parse().unwrap_or(usize::MAX),
        reserved,
    })
}

// ---- TSX --------------------------------------------------------------------------------------

fn starts_at(t: &[char], s: &str, j: usize) -> bool {
    let mut k = j;
    for c in s.chars() {
        if t.get(k) != Some(&c) {
            return false;
        }
        k += 1;
    }
    true
}

fn find_str(t: &[char], s: &str, from: usize) -> Option<usize> {
    let n = s.chars().count();
    if t.len() < n {
        return None;
    }
    (from..=t.len() - n).find(|&k| starts_at(t, s, k))
}

/// Python slice `t[a:b]` (clamped).
fn slice(t: &[char], a: usize, b: usize) -> String {
    let n = t.len();
    let (a, b) = (a.min(n), b.min(n));
    if b <= a {
        String::new()
    } else {
        t[a..b].iter().collect()
    }
}

/// Index just past the JS string/template literal starting at `t[i]` (may exceed the length).
fn skip_string(t: &[char], i: usize) -> usize {
    let quote = t[i];
    let mut j = i + 1;
    while j < t.len() {
        let c = t[j];
        if c == '\\' {
            j += 2;
            continue;
        }
        if c == quote {
            return j + 1;
        }
        if quote == '`' && starts_at(t, "${", j) {
            let end = match_brace(t, j + 1);
            j = if end > 0 { end as usize + 1 } else { t.len() };
            continue;
        }
        j += 1;
    }
    j
}

/// Index of the bracket closing the one at `t[i]`, skipping strings and comments; -1 if none.
fn match_brace(t: &[char], i: usize) -> isize {
    let mut stack: Vec<char> = Vec::new();
    let mut j = i;
    while j < t.len() {
        let c = t[j];
        if c == '\'' || c == '"' || c == '`' {
            j = skip_string(t, j);
            continue;
        }
        if starts_at(t, "//", j) {
            j = find_str(t, "\n", j).unwrap_or(t.len());
            continue;
        }
        if starts_at(t, "/*", j) {
            j = match find_str(t, "*/", j + 2) {
                Some(k) => k + 2,
                None => t.len(),
            };
            continue;
        }
        match c {
            '{' => stack.push('}'),
            '[' => stack.push(']'),
            '(' => stack.push(')'),
            ')' | ']' | '}' => {
                if stack.pop() != Some(c) {
                    return -1;
                }
                if stack.is_empty() {
                    return j as isize;
                }
            }
            _ => {}
        }
        j += 1;
    }
    -1
}

fn split_top(t: &[char]) -> Vec<String> {
    let mut parts = Vec::new();
    let (mut depth, mut start, mut j) = (0i32, 0usize, 0usize);
    while j < t.len() {
        let c = t[j];
        if c == '\'' || c == '"' || c == '`' {
            j = skip_string(t, j);
            continue;
        }
        if c == '{' || c == '[' || c == '(' {
            depth += 1;
        } else if c == '}' || c == ']' || c == ')' {
            depth -= 1;
        } else if c == ',' && depth == 0 {
            parts.push(slice(t, start, j));
            start = j + 1;
        }
        j += 1;
    }
    parts.push(slice(t, start, t.len()));
    parts
}

/// The keys of a JS object literal's body, or None when a spread/computed key makes them open.
fn object_keys(body: &[char]) -> Option<Vec<String>> {
    let mut keys = Vec::new();
    for part in split_top(body) {
        let part = py_strip(&part);
        if part.is_empty() {
            continue;
        }
        if part.starts_with("...") || part.starts_with('[') {
            return None;
        }
        let m = pat_match!(r#"(?s)^\s*(?:(['"])(.*?)\1|([A-Za-z_$][\w$]*))\s*(:|\(|$)"#).captures(part)?;
        keys.push(if m.matched(1) { m.s(2).to_string() } else { m.s(3).to_string() });
    }
    Some(keys)
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
struct RawCall {
    line: usize,
    action: String,
    /// None: the params are not an object literal (a variable, a spread); empty: absent.
    keys: Option<Vec<String>>,
}

/// `tsx_calls`: every `act('literal', ...)` in a TSX source.
fn tsx_calls(text: &str) -> Vec<RawCall> {
    let t: Vec<char> = text.chars().collect();
    let mut out = Vec::new();
    for m in pat!(r"(?<![\w$])act\(\s*").find_iter(text) {
        let i = text[..m.end].chars().count();
        if i >= t.len() || !matches!(t[i], '\'' | '"' | '`') {
            continue; // act(variable): the action isn't static
        }
        let end = skip_string(&t, i);
        let action = slice(&t, i + 1, end.saturating_sub(1));
        if t[i] == '`' && action.contains("${") {
            continue;
        }
        let mut j = end;
        while j < t.len() && is_py_space(t[j]) {
            j += 1;
        }
        let mut keys = Some(Vec::new());
        if j < t.len() && t[j] == ',' {
            j += 1;
            while j < t.len() && is_py_space(t[j]) {
                j += 1;
            }
            if j < t.len() && t[j] == '{' {
                let close = match_brace(&t, j);
                keys = if close > 0 { object_keys(&t[j + 1..close as usize]) } else { None };
            } else if j < t.len() && t[j] != ')' {
                keys = None;
            }
        }
        out.push(RawCall { line: text[..m.start].matches('\n').count() + 1, action, keys });
    }
    out
}

/// One act() of a source file, with the dispatcher's normalisation of its names precomputed.
struct Call {
    rel: String,
    line: usize,
    raw_action: String,
    raw_keys: Option<Vec<String>>,
    nkey: Option<String>,
    nkeys: Option<Vec<Option<String>>>,
}

impl Call {
    fn new(rel: &str, c: &RawCall, norm: &Normaliser) -> Call {
        Call {
            rel: rel.to_string(),
            line: c.line,
            raw_action: c.action.clone(),
            raw_keys: c.keys.clone(),
            nkey: norm.key(&c.action),
            nkeys: c.keys.as_ref().map(|ks| ks.iter().map(|k| norm.key(k)).collect()),
        }
    }
}

/// `tsx_acts`: the act() calls of an interface's sources (`None`: every source under interfaces/).
struct Acts {
    /// Sorted by path.
    files: Vec<(String, Vec<Call>)>,
    /// The selftest's `{interface: calls}` table instead of files.
    fixed: bool,
    by_interface: RefCell<HashMap<Option<String>, Rc<Vec<usize>>>>,
}

impl Acts {
    fn real(files: Vec<(String, Vec<Call>)>) -> Acts {
        Acts { files, fixed: false, by_interface: RefCell::new(HashMap::new()) }
    }

    /// Selftest table: the key of each entry is the interface name.
    fn fixed(table: Vec<(String, Vec<Call>)>) -> Acts {
        Acts { files: table, fixed: true, by_interface: RefCell::new(HashMap::new()) }
    }

    fn selected(&self, interface: Option<&str>) -> Rc<Vec<usize>> {
        let key = interface.map(|s| s.to_string());
        if let Some(v) = self.by_interface.borrow().get(&key) {
            return v.clone();
        }
        let mut picked = Vec::new();
        for (n, (rel, _)) in self.files.iter().enumerate() {
            let take = if self.fixed {
                match interface {
                    None => true,
                    Some(i) => rel == i,
                }
            } else if rel.ends_with(".d.ts") {
                false
            } else {
                match interface {
                    None => rel.ends_with(".tsx") || rel.ends_with(".ts"),
                    Some(i) => {
                        let exact = ["tsx", "ts", "jsx", "js"].iter().any(|e| *rel == format!("{}/{}.{}", INTERFACES, i, e));
                        let dir = format!("{}/{}/", INTERFACES, i);
                        let under = rel.starts_with(&dir)
                            && ["tsx", "ts", "jsx", "js"].iter().any(|e| rel.ends_with(&format!(".{}", e)));
                        exact || under
                    }
                }
            };
            if take {
                picked.push(n);
            }
        }
        let v = Rc::new(picked);
        self.by_interface.borrow_mut().insert(key, v.clone());
        v
    }

    fn for_interface(&self, interface: Option<&str>) -> Vec<&Call> {
        self.selected(interface).iter().flat_map(|&n| self.files[n].1.iter()).collect()
    }
}

// ---- DM hosts ---------------------------------------------------------------------------------

/// Insertion-ordered map (a Python dict).
struct Om<V> {
    keys: Vec<String>,
    map: HashMap<String, V>,
}

impl<V> Om<V> {
    fn new() -> Om<V> {
        Om { keys: Vec::new(), map: HashMap::new() }
    }
    fn insert(&mut self, k: &str, v: V) {
        if !self.map.contains_key(k) {
            self.keys.push(k.to_string());
        }
        self.map.insert(k.to_string(), v);
    }
    fn get(&self, k: &str) -> Option<&V> {
        self.map.get(k)
    }
    fn iter(&self) -> impl Iterator<Item = (&String, &V)> {
        self.keys.iter().map(move |k| (k, &self.map[k]))
    }
    fn is_empty_at(&self, k: &str) -> bool {
        self.map.get(k).is_none()
    }
}

struct Hosts {
    /// The procs the analysis reads by index: every `act_` proc, every global `cap_*` /
    /// capabilities-directory proc and every `capabilities()` proc, in file order.
    procs: Vec<Proc>,
    /// Content hash of each of `procs`.
    hashes: Vec<u128>,
    ids: HashMap<String, String>,
    legacy: HashSet<String>,
    /// host type -> {action key: proc index}
    acts: Om<Om<usize>>,
    /// capability type -> {action key: proc index}
    cap_acts: Om<Om<usize>>,
    ctor_bodies: HashMap<String, String>,
    ctor_caps_cache: RefCell<HashMap<String, BTreeSet<String>>>,
    /// host type -> capability types its own capabilities() body adds (constructors resolved).
    type_caps: HashMap<String, BTreeSet<String>>,
    actions_cache: RefCell<HashMap<String, Rc<HashMap<String, usize>>>>,
}

/// `(tgui_id by type, DECLARE_UI types)` of one file (the head of the old `Hosts::new`).
fn host_scan(f: &SourceFile) -> (Vec<(String, String)>, Vec<String>) {
    let mut ids = Vec::new();
    let mut legacy = Vec::new();
    let clean = f.clean();
    let raw = f.raw();
    let mut current: Option<String> = None;
    for number in 1..=clean.num_lines() {
        let code = clean.line(number);
        if let Some(head) = pat!(r"^(/[\w/]+)\s*$").captures(py_rstrip(code)) {
            current = Some(head.s(1).to_string());
            continue;
        }
        if !code.is_empty() && !code.starts_with([' ', '\t']) {
            current = None;
            if let Some(l) = pat!(r"^\s*DECLARE_UI\w*\(\s*(/[\w/]+)").captures(code) {
                legacy.push(l.s(1).to_string());
            }
            if let Some(l) = pat!(r#"^(/[\w/]+?)/tgui_id\s*=\s*"([^"\n]+)""#).captures(raw.line(number)) {
                ids.push((l.s(1).to_string(), l.s(2).to_string()));
            }
            continue;
        }
        if let Some(cur) = &current {
            if code.contains("tgui_id") {
                if let Some(t) = pat!(r#"^\s+tgui_id\s*=\s*"([^"\n]+)""#).captures(raw.line(number)) {
                    ids.push((cur.clone(), t.s(1).to_string()));
                }
            }
        }
    }
    (ids, legacy)
}

/// A proc the analysis reads by index, as cached per file (`kind` 0: act_, 1: global constructor,
/// 2: capabilities()). Constructors and capabilities() carry their sanitized body.
#[derive(Serialize, Deserialize, Clone, PartialEq)]
struct PInfo {
    kind: u8,
    line: u32,
    path: String,
    name: String,
    params: Vec<String>,
    body_start: u32,
    body_len: u32,
    hash: u128,
    body: Option<String>,
}

/// One dm file's contribution: hosts, the procs read by index, the identity hash of every proc
/// (`names`: name hash and content hash, in file order), and the lines an `ALLOW(ui_actions)` keeps.
#[derive(Serialize, Deserialize, Default, PartialEq)]
struct DmFacts {
    ids: Vec<(String, String)>,
    legacy: Vec<String>,
    procs: Vec<PInfo>,
    names: Vec<(u64, u128)>,
    /// `(asked line, annotation line, reason code)`.
    kept: Vec<(u32, u32, String)>,
}

fn name_hash(name: &str) -> u64 {
    u64::from_le_bytes(blake3::hash(name.as_bytes()).as_bytes()[..8].try_into().unwrap())
}

fn dm_facts(f: &SourceFile) -> DmFacts {
    let (ids, legacy) = host_scan(f);
    let clean = f.clean();
    let mut out = DmFacts { ids, legacy, ..DmFacts::default() };
    for p in procs_in(f) {
        let body: String = (0..p.body_len).map(|k| clean.line(p.body_start + k)).collect::<Vec<_>>().join("\n");
        let mut h = blake3::Hasher::new();
        let params = p.params.join("\u{1}");
        for part in [p.path.as_str(), p.name.as_str(), params.as_str(), body.as_str()] {
            h.update(part.as_bytes());
            h.update(b"\0");
        }
        let hash = u128::from_le_bytes(h.finalize().as_bytes()[..16].try_into().unwrap());
        out.names.push((name_hash(&p.name), hash));
        let kind = if p.name.starts_with("act_") && !p.is_global() {
            Some(0u8)
        } else if p.is_global() && (p.name.starts_with("cap_") || p.rel.starts_with(CAPS_DIR)) {
            Some(1)
        } else if p.name == "capabilities" && !p.is_global() {
            Some(2)
        } else {
            None
        };
        if let Some(kind) = kind {
            out.procs.push(PInfo {
                kind,
                line: p.line as u32,
                path: p.path.clone(),
                name: p.name.clone(),
                params: p.params.clone(),
                body_start: p.body_start as u32,
                body_len: p.body_len as u32,
                hash,
                body: if kind > 0 { Some(body) } else { None },
            });
        }
    }
    if f.text().contains("ui_actions") {
        for number in 1..=f.raw().num_lines() {
            if let Some(k) = crate::allow::kept(f, number, "ui_actions") {
                out.kept.push((number as u32, k.line as u32, k.code.unwrap_or_default()));
            }
        }
    }
    out
}

impl Hosts {
    fn new(files: &[&SourceFile], facts: &[DmFacts]) -> Hosts {
        let mut ids = HashMap::new();
        let mut legacy = HashSet::new();
        let mut procs: Vec<Proc> = Vec::new();
        let mut kinds: Vec<(u8, Option<String>)> = Vec::new();
        let mut hashes: Vec<u128> = Vec::new();
        for (f, fa) in files.iter().zip(facts) {
            for (t, id) in &fa.ids {
                ids.insert(t.clone(), id.clone());
            }
            legacy.extend(fa.legacy.iter().cloned());
            for p in &fa.procs {
                procs.push(Proc {
                    rel: f.rel.clone(),
                    line: p.line as usize,
                    path: p.path.clone(),
                    name: p.name.clone(),
                    params: p.params.clone(),
                    body_start: p.body_start as usize,
                    body_len: p.body_len as usize,
                });
                kinds.push((p.kind, p.body.clone()));
                hashes.push(p.hash);
            }
        }
        let mut acts: Om<Om<usize>> = Om::new();
        let mut cap_acts: Om<Om<usize>> = Om::new();
        let mut ctor_bodies = HashMap::new();
        let mut caps_bodies: Om<Vec<String>> = Om::new();
        for (n, proc) in procs.iter().enumerate() {
            let (kind, body) = &kinds[n];
            match kind {
                0 => {
                    let table = if is_subtype(&proc.path, CAP_ROOT) { &mut cap_acts } else { &mut acts };
                    if table.is_empty_at(&proc.path) {
                        table.insert(&proc.path, Om::new());
                    }
                    table.map.get_mut(&proc.path).unwrap().insert(&proc.name[4..], n);
                }
                1 => {
                    ctor_bodies.insert(proc.name.clone(), body.clone().unwrap_or_default());
                }
                _ => {
                    if caps_bodies.is_empty_at(&proc.path) {
                        caps_bodies.insert(&proc.path, Vec::new());
                    }
                    caps_bodies.map.get_mut(&proc.path).unwrap().push(body.clone().unwrap_or_default());
                }
            }
        }
        let mut hosts = Hosts {
            procs,
            hashes,
            ids,
            legacy,
            acts,
            cap_acts,
            ctor_bodies,
            ctor_caps_cache: RefCell::new(HashMap::new()),
            type_caps: HashMap::new(),
            actions_cache: RefCell::new(HashMap::new()),
        };
        let mut type_caps = HashMap::new();
        for (path, bodies) in caps_bodies.iter() {
            let mut set = BTreeSet::new();
            for b in bodies {
                set.extend(hosts.caps_in(b, &HashSet::new()));
            }
            type_caps.insert(path.clone(), set);
        }
        hosts.type_caps = type_caps;
        hosts
    }

    /// The capability types a global cap_* constructor (or bundle) builds.
    fn ctor_caps(&self, name: &str, seen: &HashSet<String>) -> BTreeSet<String> {
        if let Some(c) = self.ctor_caps_cache.borrow().get(name) {
            return c.clone();
        }
        if seen.contains(name) || !self.ctor_bodies.contains_key(name) {
            return BTreeSet::new();
        }
        let mut seen = seen.clone();
        seen.insert(name.to_string());
        let got = self.caps_in(&self.ctor_bodies[name], &seen);
        self.ctor_caps_cache.borrow_mut().insert(name.to_string(), got.clone());
        got
    }

    fn caps_in(&self, body: &str, seen: &HashSet<String>) -> BTreeSet<String> {
        let mut out = BTreeSet::new();
        for m in pat!(r"\bnew\s+(/datum/capability[\w/]*)|\bvar/(/datum/capability[\w/]*)/\w+\s*=\s*new\b").captures_iter(body) {
            out.insert(if m.matched(1) { m.s(1).to_string() } else { m.s(2).to_string() });
        }
        for m in pat!(r"(?:[(,=]\s*)(/datum/capability/[\w/]+)").captures_iter(body) {
            out.insert(m.s(1).to_string());
        }
        for m in pat!(r"(?<![\w./:])([A-Za-z_]\w*)\s*\(").captures_iter(body) {
            out.extend(self.ctor_caps(m.s(1), seen));
        }
        out
    }

    /// Capability types a host type declares (its lineage's capabilities() bodies).
    fn caps_of(&self, path: &str) -> BTreeSet<String> {
        let mut out = BTreeSet::new();
        for anc in lineage(path) {
            if let Some(c) = self.type_caps.get(&anc) {
                out.extend(c.iter().cloned());
            }
        }
        out
    }

    fn interface_of(&self, path: &str) -> Option<String> {
        lineage(path).iter().find_map(|anc| self.ids.get(anc).cloned())
    }

    fn is_legacy(&self, path: &str) -> bool {
        lineage(path).iter().any(|a| self.legacy.contains(a))
    }

    fn cap_actions(&self, cap_type: &str) -> HashMap<String, usize> {
        let mut out = HashMap::new();
        for anc in lineage(cap_type).iter().rev() {
            if let Some(m) = self.cap_acts.get(anc) {
                for (k, v) in m.iter() {
                    out.insert(k.clone(), *v);
                }
            }
        }
        out
    }

    /// `{action: proc}` answered by `path`: its own act_ procs (nearest definition wins), else one
    /// of its capabilities' act_ procs (the dispatcher's order).
    fn actions_of(&self, path: &str) -> Rc<HashMap<String, usize>> {
        if let Some(c) = self.actions_cache.borrow().get(path) {
            return c.clone();
        }
        let mut out: HashMap<String, usize> = HashMap::new();
        for cap in self.caps_of(path) {
            for (action, proc) in self.cap_actions(&cap) {
                out.entry(action).or_insert(proc);
            }
        }
        for anc in lineage(path).iter().rev() {
            if let Some(m) = self.acts.get(anc) {
                for (k, v) in m.iter() {
                    out.insert(k.clone(), *v);
                }
            }
        }
        let rc = Rc::new(out);
        self.actions_cache.borrow_mut().insert(path.to_string(), rc.clone());
        rc
    }

    fn is_migrated(&self, path: &str) -> bool {
        if lineage(path).iter().any(|a| !BUILTIN_HOSTS.contains(&a.as_str()) && self.acts.get(a).map(|m| !m.keys.is_empty()).unwrap_or(false)) {
            return true;
        }
        self.caps_of(path).iter().any(|c| !self.cap_actions(c).is_empty())
    }

    /// `{interface: [host types]}`: the tgui_id types plus subtypes defining act_ procs or
    /// declaring capabilities.
    fn by_interface(&self) -> BTreeMap<String, Vec<String>> {
        let mut paths: BTreeSet<&String> = self.ids.keys().collect();
        paths.extend(self.acts.keys.iter());
        paths.extend(self.type_caps.keys());
        let mut out: BTreeMap<String, Vec<String>> = BTreeMap::new();
        for path in paths {
            if BUILTIN_HOSTS.contains(&path.as_str()) || is_subtype(path, CAP_ROOT) {
                continue;
            }
            if let Some(interface) = self.interface_of(path) {
                out.entry(interface).or_default().push(path.clone());
            }
        }
        out
    }

    /// Interfaces whose windows reach an act_ proc on `path`; None means every interface.
    fn served_interfaces(&self, path: &str) -> Option<BTreeSet<String>> {
        if BUILTIN_HOSTS.contains(&path) {
            return None;
        }
        let mut out = BTreeSet::new();
        if is_subtype(path, CAP_ROOT) {
            for (host, caps) in &self.type_caps {
                if caps.iter().any(|c| is_subtype(c, path)) {
                    // Python: `out |= served_interfaces(host)` (a TypeError if that is None).
                    if let Some(s) = self.served_interfaces(host) {
                        out.extend(s);
                    }
                }
            }
            return Some(out);
        }
        if let Some(top) = self.interface_of(path) {
            out.insert(top);
        }
        for (t, interface) in &self.ids {
            if is_subtype(t, path) {
                out.insert(interface.clone());
            }
        }
        Some(out)
    }
}

// ---- analysis ---------------------------------------------------------------------------------

struct Analysis<'a> {
    tree: &'a Tree,
    hosts: &'a Hosts,
    norm: &'a Normaliser,
    acts: &'a Acts,
    pats: RefCell<HashMap<String, Rc<Pat>>>,
    helpers: &'a Helpers<'a>,
    c2: Option<&'a C2Cache>,
}

/// Every proc of a given name, loaded on demand from the (few) files that define one; the names a
/// root evaluation asked for are recorded as its dependencies.
struct Helpers<'a> {
    tree: &'a Tree,
    files: &'a [&'a SourceFile],
    facts: &'a [DmFacts],
    by_name: OnceCell<HashMap<u64, Vec<usize>>>,
    loaded: RefCell<HashMap<String, Rc<Vec<Proc>>>>,
    touched: RefCell<BTreeSet<u64>>,
}

impl<'a> Helpers<'a> {
    fn new(tree: &'a Tree, files: &'a [&'a SourceFile], facts: &'a [DmFacts]) -> Helpers<'a> {
        Helpers { tree, files, facts, by_name: OnceCell::new(), loaded: RefCell::new(HashMap::new()), touched: RefCell::new(BTreeSet::new()) }
    }

    fn begin(&self) {
        self.touched.borrow_mut().clear();
    }

    fn end(&self) -> Vec<u64> {
        self.touched.borrow().iter().copied().collect()
    }

    /// `procs_named(name)`: file order, then the file's own order.
    fn named(&self, name: &str) -> Rc<Vec<Proc>> {
        let nh = name_hash(name);
        self.touched.borrow_mut().insert(nh);
        if let Some(v) = self.loaded.borrow().get(name) {
            return v.clone();
        }
        let by_name = self.by_name.get_or_init(|| {
            let mut m: HashMap<u64, Vec<usize>> = HashMap::new();
            for (i, fa) in self.facts.iter().enumerate() {
                for (h, _) in &fa.names {
                    let e = m.entry(*h).or_default();
                    if e.last() != Some(&i) {
                        e.push(i);
                    }
                }
            }
            m
        });
        let mut out: Vec<Proc> = Vec::new();
        for &i in by_name.get(&nh).map(|v| v.as_slice()).unwrap_or(&[]) {
            let rel = &self.files[i].rel;
            if let Some(f) = self.tree.get(rel) {
                out.extend(procs_in(f).into_iter().filter(|p| p.name == name));
            }
        }
        let rc = Rc::new(out);
        self.loaded.borrow_mut().insert(name.to_string(), rc.clone());
        rc
    }
}

#[derive(Serialize, Deserialize, Clone)]
struct C2Entry {
    deps: Vec<(u64, u128)>,
    off: Option<u32>,
}

/// The persistent C2 answers (`old`), the group hashes that validate them, and what this run used.
struct C2Cache {
    old: HashMap<u128, C2Entry>,
    groups: HashMap<u64, u128>,
    used: RefCell<HashMap<u128, C2Entry>>,
}

#[derive(Serialize, Deserialize, Default)]
struct C2File {
    stamp: String,
    map: HashMap<u128, C2Entry>,
}

fn c2_path() -> Option<std::path::PathBuf> {
    incr::dir().map(|d| d.join("incr-ui_actions-c2.bin"))
}

fn c2_load() -> HashMap<u128, C2Entry> {
    let (Some(path), Some(stamp)) = (c2_path(), incr::stamp()) else { return HashMap::new() };
    match std::fs::read(&path).ok().and_then(|b| bincode::deserialize::<C2File>(&b).ok()) {
        Some(f) if f.stamp == stamp => f.map,
        _ => HashMap::new(),
    }
}

fn c2_save(old_len: usize, cache: &C2Cache) {
    let (Some(path), Some(stamp)) = (c2_path(), incr::stamp()) else { return };
    let used = cache.used.borrow();
    let unchanged = used.len() == old_len && used.keys().all(|k| cache.old.contains_key(k));
    if unchanged {
        return;
    }
    if let Some(dir) = path.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    if let Ok(bytes) = bincode::serialize(&C2File { stamp, map: used.clone() }) {
        let tmp = path.with_extension(format!("tmp{}", std::process::id()));
        if std::fs::write(&tmp, &bytes).is_ok() {
            let _ = std::fs::rename(&tmp, &path);
        } else {
            let _ = std::fs::remove_file(&tmp);
        }
    }
}

/// Group hash per proc name: every proc of that name folded in file order.
fn group_hashes(facts: &[DmFacts]) -> HashMap<u64, u128> {
    let mut g: HashMap<u64, u128> = HashMap::new();
    for fa in facts {
        for (nh, ph) in &fa.names {
            g.entry(*nh).and_modify(|h| *h = (h.rotate_left(17) ^ ph).wrapping_mul(0x9E37_79B9_7F4A_7C15_F39C_C060_5CED_C835)).or_insert(*ph);
        }
    }
    g
}

impl<'a> Analysis<'a> {
    fn proc(&self, n: usize) -> &Proc {
        &self.hosts.procs[n]
    }

    /// The hard failures: `(rel, line, message)` for act() calls that don't match the act_ procs
    /// of a migrated interface.
    fn check(&self) -> Vec<(String, usize, String)> {
        let mut problems = Vec::new();
        for (interface, types) in self.hosts.by_interface() {
            if types.iter().any(|t| self.hosts.is_legacy(t)) {
                continue; // still (partly) on DECLARE_UI rows
            }
            let mut migrated: Vec<&String> = types.iter().filter(|t| self.hosts.is_migrated(t)).collect();
            migrated.sort();
            if migrated.is_empty() {
                continue;
            }
            let where_ = migrated.iter().map(|s| s.as_str()).collect::<Vec<_>>().join(", ");
            for call in self.acts.for_interface(Some(&interface)) {
                let (rel, line, raw_action) = (&call.rel, call.line, &call.raw_action);
                let Some(action) = &call.nkey else {
                    problems.push((
                        rel.clone(),
                        line,
                        format!("act('{}'): the dispatcher rejects this action name ([A-Za-z0-9_-], 64 max)", raw_action),
                    ));
                    continue;
                };
                let answering: Vec<&&String> = migrated.iter().filter(|t| self.hosts.actions_of(t).contains_key(action)).collect();
                if answering.is_empty() {
                    problems.push((rel.clone(), line, format!("act('{}') has no act_{} on {}", raw_action, action, where_)));
                    continue;
                }
                let raw_keys: &[String] = call.raw_keys.as_deref().unwrap_or(&[]);
                let nkeys: &[Option<String>] = call.nkeys.as_deref().unwrap_or(&[]);
                for (raw_key, key) in raw_keys.iter().zip(nkeys) {
                    match key {
                        None => problems.push((
                            rel.clone(),
                            line,
                            format!("act('{}') key '{}' is rejected by the dispatcher (dropped)", raw_action, raw_key),
                        )),
                        Some(k) if self.norm.reserved.contains(k) => problems.push((
                            rel.clone(),
                            line,
                            format!("act('{}') key '{}' is a reserved argument name (dropped)", raw_action, raw_key),
                        )),
                        Some(k) => {
                            let mut seen: Vec<usize> = Vec::new();
                            for t in &answering {
                                let p = self.hosts.actions_of(t)[action];
                                if !seen.contains(&p) {
                                    seen.push(p);
                                }
                            }
                            for p in seen {
                                let proc = self.proc(p);
                                if !proc.params.contains(k) {
                                    problems.push((
                                        rel.clone(),
                                        line,
                                        format!("act('{}') passes {}, which act_{} on {} doesn't declare", raw_action, k, action, proc.path),
                                    ));
                                }
                            }
                        }
                    }
                }
            }
        }
        problems
    }

    /// The act_ procs a client can reach: on a UI host's lineage or below it (not legacy), and
    /// every capability's act_ procs.
    fn ui_procs(&self) -> Vec<usize> {
        let mut out = Vec::new();
        for (path, actions) in self.hosts.acts.iter() {
            if self.hosts.is_legacy(path) {
                continue;
            }
            let served = self.hosts.served_interfaces(path);
            if matches!(&served, Some(s) if s.is_empty()) {
                continue;
            }
            out.extend(actions.iter().map(|(_, v)| *v));
        }
        for (_, actions) in self.hosts.cap_acts.iter() {
            out.extend(actions.iter().map(|(_, v)| *v));
        }
        out
    }

    /// C1: `(proc, param)` for each parameter no act() of a reaching interface sends.
    fn unsent_params(&self, procs: &[usize]) -> Vec<(usize, String)> {
        let mut out = Vec::new();
        for &n in procs {
            let proc = self.proc(n);
            let action = &proc.name[4..];
            let served = self.hosts.served_interfaces(&proc.path);
            if matches!(&served, Some(s) if s.is_empty()) {
                continue; // a capability no host declares yet: no act() to compare with (C2 still runs)
            }
            let mut sent: HashSet<Option<String>> = HashSet::new();
            let mut anything = false;
            let interfaces: Vec<Option<String>> = match &served {
                None => vec![None],
                Some(s) => s.iter().cloned().map(Some).collect(),
            };
            for interface in interfaces {
                for call in self.acts.for_interface(interface.as_deref()) {
                    if call.nkey.as_deref() != Some(action) {
                        continue;
                    }
                    match &call.nkeys {
                        None => anything = true,
                        Some(ks) => sent.extend(ks.iter().cloned()),
                    }
                }
            }
            if anything {
                continue;
            }
            for param in &proc.params {
                if !self.norm.reserved.contains(param) && !sent.contains(&Some(param.clone())) {
                    out.push((n, param.clone()));
                }
            }
        }
        out
    }

    fn use_pattern(&self, param: &str) -> Rc<Pat> {
        let mut g = self.pats.borrow_mut();
        g.entry(param.to_string()).or_insert_with(|| Rc::new(Pat::new(&format!(r"(?<![\w./:]){}\b", regex::escape(param))))).clone()
    }

    fn find_proc(&self, path: &str, name: &str) -> Option<Proc> {
        let chain = lineage(path);
        let mut best: Option<(i64, usize)> = None;
        let named = self.helpers.named(name);
        for (i, proc) in named.iter().enumerate() {
            if proc.is_global() || chain.contains(&proc.path) {
                let rank = if proc.is_global() {
                    -1
                } else {
                    chain.len() as i64 - chain.iter().position(|c| *c == proc.path).unwrap() as i64
                };
                if best.map(|b| rank > b.0).unwrap_or(true) {
                    best = Some((rank, i));
                }
            }
        }
        best.map(|b| named[b.1].clone())
    }

    /// `first_bad_use`: None when param's first real use validates it, else the offending line.
    fn first_bad_use(&self, proc: &Proc, param: &str, depth: usize) -> Option<usize> {
        let use_pat = self.use_pattern(param);
        for (number, text) in proc.lines(self.tree) {
            for m in use_pat.find_iter(text) {
                let col = m.start;
                let (before, after) = (&text[..col], &text[col + param.len()..]);
                if pat_match!(r"\s*=(?!=)").is_match(after) {
                    continue; // an assignment target or a named-argument key
                }
                if pat!(r"(?<!!)!\s*$").is_match(before) && !pat_match!(r"\s*(?:==|!=|in\b)").is_match(after) {
                    continue; // a bare truthiness test
                }
                if pat!(r"\bisnull\(\s*$").is_match(before) {
                    continue;
                }
                if pat!(r"!!\s*$").is_match(before) {
                    return None;
                }
                if pat!(r"\b(?:switch|islist)\s*\(\s*$").is_match(before) && pat_match!(r"\s*\)").is_match(after) {
                    return None;
                }
                if pat_match!(r#"\s*(?:==|!=)\s*(?:"[^"\n]*"|-?\d+(?:\.\d+)?|TRUE|FALSE|null|[A-Z][A-Z0-9_]+)\b"#).is_match(after)
                    || pat!(r#"(?:"[^"\n]*"|-?\d+(?:\.\d+)?|TRUE|FALSE|null|[A-Z][A-Z0-9_]+)\b\s*(?:==|!=)\s*$"#).is_match(before)
                {
                    return None;
                }
                if let Some(call) = enclosing_call(text, col) {
                    if pat_match!(r"\s*[,)]").is_match(after) {
                        if VALIDATORS.contains(&call.name.as_str()) && call.index == 0 && call.key.is_none() && !call.member {
                            return None;
                        }
                        let helper = if call.member { None } else { self.find_proc(&proc.path, &call.name) };
                        if let Some(helper) = helper {
                            if depth < 3 {
                                let target: Option<&String> = match &call.key {
                                    Some(k) => Some(k),
                                    None => helper.params.get(call.index),
                                };
                                if let Some(target) = target {
                                    if helper.params.contains(target) && self.first_bad_use(&helper, target, depth + 1).is_none() {
                                        return None;
                                    }
                                }
                            }
                        }
                    }
                }
                return Some(number);
            }
        }
        None
    }

    /// `first_bad_use(proc, param, 0)` through the persistent cache: an entry is the answer plus the
    /// proc-name groups the evaluation looked up (helpers), valid while the root proc and each such
    /// group (every proc of that name, in file order) hash the same.
    fn cached_bad_use(&self, n: usize, proc: &Proc, param: &str) -> Option<usize> {
        let Some(cache) = &self.c2 else { return self.first_bad_use(proc, param, 0) };
        let root = self.hosts.hashes[n];
        let key = incr::mix(&[root, incr::ctx_key(param)]);
        if let Some(e) = cache.old.get(&key) {
            if e.deps.iter().all(|(nh, gh)| cache.groups.get(nh).copied().unwrap_or(0) == *gh) {
                cache.used.borrow_mut().insert(key, e.clone());
                return e.off.map(|o| proc.body_start + o as usize);
            }
        }
        self.helpers.begin();
        let got = self.first_bad_use(proc, param, 0);
        let deps: Vec<(u64, u128)> = self.helpers.end().into_iter().map(|nh| (nh, cache.groups.get(&nh).copied().unwrap_or(0))).collect();
        let off = got.map(|l| (l - proc.body_start) as u32);
        cache.used.borrow_mut().insert(key, C2Entry { deps, off });
        got
    }

    /// C2: `(proc, param, line)`.
    fn unvalidated_params(&self, procs: &[usize]) -> Vec<(usize, String, usize)> {
        let mut out = Vec::new();
        for &n in procs {
            let proc = self.proc(n);
            for param in &proc.params {
                if self.norm.reserved.contains(param) {
                    continue;
                }
                if let Some(bad) = self.cached_bad_use(n, proc, param) {
                    out.push((n, param.clone(), bad));
                }
            }
        }
        out
    }

    /// `dx_sites`: `(C1 sites, C2 sites)`, each `(rel, line)`, ALLOW honoured through `allowed`.
    fn dx_sites(&self, allowed: &mut dyn FnMut(&str, usize) -> bool) -> (Vec<(String, usize)>, Vec<(String, usize)>) {
        let procs = self.ui_procs();
        let mut unsent = Vec::new();
        let mut unvalidated = Vec::new();
        for (n, _param) in self.unsent_params(&procs) {
            let p = self.proc(n);
            if !allowed(&p.rel, p.line) {
                unsent.push((p.rel.clone(), p.line));
            }
        }
        for (n, _param, line) in self.unvalidated_params(&procs) {
            let p = self.proc(n);
            if !allowed(&p.rel, line) {
                unvalidated.push((p.rel.clone(), line));
            }
        }
        (unsent, unvalidated)
    }
}

#[derive(Serialize, Deserialize, Default, PartialEq)]
struct TsxFacts {
    calls: Vec<RawCall>,
}

struct UiActions;

impl Lint for UiActions {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        let files = cx.files();
        let dm: Vec<&SourceFile> = files.iter().copied().filter(|f| f.ext() == "dm").collect();
        let Some(dispatcher) = cx.tree.get(DISPATCHER) else { return };
        let norm = match normaliser_from(dispatcher.text()) {
            Ok(n) => n,
            Err(msg) => {
                out.note(msg.clone());
                out.site_in_msg(R_PROBLEM, DISPATCHER, 1, msg);
                return;
            }
        };
        // TSX act() calls: per file, cached by content.
        let tsx_files: Vec<&SourceFile> =
            files.iter().copied().filter(|f| matches!(f.ext(), "tsx" | "ts" | "jsx" | "js") && !f.rel.ends_with(".d.ts")).collect();
        let tsx_facts = incr::facts("ui_actions-tsx", &tsx_files, |f| TsxFacts { calls: tsx_calls(f.text()) });
        let tsx: Vec<(String, Vec<Call>)> = tsx_files
            .iter()
            .zip(&tsx_facts)
            .map(|(f, fa)| (f.rel.clone(), fa.calls.iter().map(|c| Call::new(&f.rel, c, &norm)).collect()))
            .collect();
        let acts = Acts::real(tsx);
        // DM hosts and procs: per file, cached by content.
        let facts = incr::facts("ui_actions-dm", &dm, dm_facts);
        let hosts = Hosts::new(&dm, &facts);
        let helpers = Helpers::new(cx.tree, &dm, &facts);
        let old = c2_load();
        let old_len = old.len();
        let c2 = C2Cache { old, groups: group_hashes(&facts), used: RefCell::new(HashMap::new()) };
        let an = Analysis {
            tree: cx.tree,
            hosts: &hosts,
            norm: &norm,
            acts: &acts,
            pats: RefCell::new(HashMap::new()),
            helpers: &helpers,
            c2: Some(&c2),
        };
        let by_rel: HashMap<&str, usize> = dm.iter().enumerate().map(|(i, f)| (f.rel.as_str(), i)).collect();
        let (unsent, unvalidated) = an.dx_sites(&mut |rel, line| {
            let Some(&i) = by_rel.get(rel) else { return false };
            match facts[i].kept.iter().find(|k| k.0 as usize == line) {
                Some((_, at, code)) => {
                    let u = crate::lint::AllowUse { rel: rel.to_string(), line: *at, name: "ui_actions".to_string(), code: code.clone() };
                    if !out.allow_used.contains(&u) {
                        out.allow_used.push(u);
                    }
                    true
                }
                None => false,
            }
        });
        c2_save(old_len, &c2);
        let problems = an.check();
        for (rel, line) in unsent {
            out.site_in(R_UNSENT, &rel, line);
        }
        for (rel, line) in unvalidated {
            out.site_in(R_UNVALIDATED, &rel, line);
        }
        out.note(format!("ui_actions_lint: {} problem(s)", problems.len()));
        for (rel, line, msg) in problems {
            out.site_in_msg(R_PROBLEM, &rel, line, msg);
        }
    }

    fn selftest(&self) -> Result<String, String> {
        selftest().map(|_| "ui_actions_lint selftest ok".to_string())
    }

    fn parity(&self) -> Option<Parity> {
        Some(Parity {
            old: &["tools/ci/ui_actions_lint.py"],
            old_raw: &[],
            blank: &[BASELINE],
            parse: ParseKind::FileLine,
            update: Some(&["tools/ci/ui_actions_lint.py", "--update"]),
            seed: Some(&["tools/ci/ui_actions_lint.py", "--seed"]),
            files: &[BASELINE],
            selftest: Some(&["tools/ci/ui_actions_lint.py", "--selftest"]),
        })
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(UiActions);
}

// ---- selftest ---------------------------------------------------------------------------------

const DISPATCHER_FIXTURE: &str = r#"
/proc/ui_action_key(raw)
	if(!istext(raw) || !length(raw) || length(raw) > 64 || !GLOB.ui_action_raw_regex.Find(raw))
		return null
	var/out = GLOB.ui_action_camel_regex.Replace(raw, "$1_$2")
	out = replacetext(lowertext(out), "-", "_")
	return out
GLOBAL_DATUM_INIT(ui_action_raw_regex, /regex, regex(@"^[A-Za-z0-9_-]+$"))
GLOBAL_DATUM_INIT(ui_action_camel_regex, /regex, regex(@"([a-z0-9])([A-Z])", "g"))
GLOBAL_LIST_INIT(ui_reserved_arg_names, list("user", "src", "usr", "ui", "state", "holder"))
"#;

const DM_FIXTURE: &str = "/datum/proc/act_modal_close(mob/user, id)
\treturn TRUE
/obj/thing
\ttgui_id = \"Thing\"
/obj/thing/proc/act_go(mob/user, speed, force)
\tspeed = ui_number(speed, 0, 10)
\tif(!speed)
\t\treturn
/obj/thing/proc/act_pick(mob/user, mode, ref, flag)
\tvar/datum/D = find_ref(user, ref)
\tif(!!flag)
\t\treturn
\tswitch(mode)
\t\tif(\"a\")
\t\t\treturn
/obj/thing/proc/find_ref(mob/user, ref)
\treturn ui_ref(ref, null, /datum)
/obj/thing/proc/act_raw(mob/user, amount, name, kind, when, extra)
\tif(!amount)
\t\treturn
\tvar/x = amount + 1
\tto_chat(user, name)
\tif(kind == MODE_FAST)
\t\treturn
\thelper(when)
\tsrc.helper(extra)
/obj/thing/proc/helper(value)
\tworld << value
/obj/thing/subtype/proc/act_sub(mob/user, level, list/items)
\tvar/obj/level/marker = null
\tlevel = ui_bool(level)
\tfor(var/i in islist(items) ? items : list())
\t\treturn
/obj/thing/proc/act_bolt_toggle(mob/user, target_state)
\treturn ui_bool(target_state)
/obj/old
\ttgui_id = \"Old\"
DECLARE_UI(/obj/old, UI_TITLE(\"Old\"))
/obj/old/proc/act_whatever(mob/user, anything)
\treturn anything
/datum/capability/breakers
/proc/cap_breakers()
\treturn new /datum/capability/breakers
/obj/thing/capabilities()
\t. = ..()
\t. += thing_bundle()
/datum/capability/breakers/proc/act_breaker(mob/user, atom/holder, channel, force)
\tchannel = ui_number(channel, 1, 3)
\tif(!channel)
\t\treturn
/datum/capability/unused/proc/act_unused(mob/user, atom/holder, level)
\tworld << level
";

const BUNDLE_FIXTURE: &str = "/proc/thing_bundle()
\t. = list(cap_breakers())
";

const TSX_FIXTURE: &str = "
      <Button onClick={() => act('go', { speed: 5 })} />
      <Button onClick={() => act(\"pick\", {mode: 'a', 'ref': x.ref, flag})} />
      act('raw', { amount: 1, name: `n`, kind, when: a ? b : c, extra: { nested: 1 } });
      act('sub', {level: true, items: [1, 2]});
      act('bolt-toggle', { targetState: true });
      act(dynamicName, { a: 1 });
      act('pick', { ...params });
      act('modal_close', params);
      act('bogus');
      act('go', { speed: 1, bogus: 2 });
      act('go', { user: 'x' });
      act('go', { 'bad key': 1 });
      act('bad name!');
      act('breaker', { channel: 2 });
    ";

fn ensure(cond: bool, what: impl FnOnce() -> String) -> Result<(), String> {
    if cond {
        Ok(())
    } else {
        Err(what())
    }
}

fn selftest() -> Result<(), String> {
    let norm = normaliser_from(DISPATCHER_FIXTURE)?;
    let k = |s: &str| norm.key(s);
    ensure(k("bolt-toggle").as_deref() == Some("bolt_toggle") && k("boltToggle").as_deref() == Some("bolt_toggle"), || format!("{:?}", k("boltToggle")))?;
    ensure(k("setScreen").as_deref() == Some("set_screen") && k("targetState").as_deref() == Some("target_state"), || "camel".to_string())?;
    ensure(k("bad key").is_none() && k(&"x".repeat(65)).is_none() && k("").is_none(), || "rejects".to_string())?;
    let want: HashSet<String> = ["user", "src", "usr", "ui", "state", "holder"].iter().map(|s| s.to_string()).collect();
    ensure(norm.reserved == want, || format!("reserved {:?}", norm.reserved))?;
    ensure(normaliser_from("nothing here").is_err(), || "a dispatcher without the regexes must fail".to_string())?;
    // The live dispatcher must still parse (lint/dispatcher parity), where the source is reachable.
    let manifest = std::path::Path::new(env!("CARGO_MANIFEST_DIR"));
    for cand in [std::path::PathBuf::from(DISPATCHER), manifest.join("../..").join(DISPATCHER)] {
        if let Ok(text) = std::fs::read_to_string(&cand) {
            let live = normaliser_from(&text)?;
            ensure(live.key("bolt-toggle").as_deref() == Some("bolt_toggle"), || "the live ui_action_key() no longer matches".to_string())?;
            break;
        }
    }

    let calls = tsx_calls(TSX_FIXTURE);
    let strs = |v: &[&str]| Some(v.iter().map(|s| s.to_string()).collect::<Vec<_>>());
    let is = |c: &RawCall, a: &str, keys: Option<Vec<String>>| c.action == a && c.keys == keys;
    ensure(is(&calls[0], "go", strs(&["speed"])), || format!("{:?}", calls[0]))?;
    ensure(is(&calls[1], "pick", strs(&["mode", "ref", "flag"])), || format!("{:?}", calls[1]))?;
    ensure(is(&calls[2], "raw", strs(&["amount", "name", "kind", "when", "extra"])), || format!("{:?}", calls[2]))?;
    ensure(is(&calls[4], "bolt-toggle", strs(&["targetState"])), || format!("{:?}", calls[4]))?;
    ensure(is(&calls[5], "pick", None) && is(&calls[6], "modal_close", None), || format!("{:?}", &calls[5..7]))?;
    ensure(is(&calls[7], "bogus", strs(&[])), || format!("{:?}", calls[7]))?;

    let caps_rel = format!("{}library/fixture.dm", CAPS_DIR);
    let tree = Tree::from_files(vec![SourceFile::from_text("x.dm", DM_FIXTURE), SourceFile::from_text(&caps_rel, BUNDLE_FIXTURE)]);
    let files: Vec<&SourceFile> = tree.files.iter().collect();
    let facts: Vec<DmFacts> = files.iter().map(|f| dm_facts(f)).collect();
    let hosts = Hosts::new(&files, &facts);
    let helpers = Helpers::new(&tree, &files, &facts);
    let table = vec![
        ("Thing".to_string(), calls.iter().map(|c| Call::new("x.tsx", c, &norm)).collect::<Vec<_>>()),
        ("Old".to_string(), vec![Call::new("o.tsx", &RawCall { line: 1, action: "nope".to_string(), keys: Some(vec![]) }, &norm)]),
    ];
    let acts = Acts::fixed(table);
    let an = Analysis { tree: &tree, hosts: &hosts, norm: &norm, acts: &acts, pats: RefCell::new(HashMap::new()), helpers: &helpers, c2: None };
    let problems = an.check();
    let msgs: Vec<&str> = problems.iter().map(|p| p.2.as_str()).collect();
    ensure(problems.len() == 5, || format!("{:?}", msgs))?;
    // act('breaker') is answered by the capability the host declares through a bundle.
    ensure(
        hosts.actions_of("/obj/thing").contains_key("breaker")
            && hosts.caps_of("/obj/thing") == BTreeSet::from(["/datum/capability/breakers".to_string()]),
        || "breaker through the bundle".to_string(),
    )?;
    ensure(msgs[0].contains("act('bogus') has no act_bogus"), || format!("{:?}", msgs))?;
    ensure(msgs[1].contains("passes bogus") && msgs[2].contains("reserved") && msgs[3].contains("'bad key' is rejected"), || format!("{:?}", msgs))?;
    ensure(msgs[4].contains("rejects this action name"), || format!("{:?}", msgs))?;

    let (unsent, unvalidated) = an.dx_sites(&mut |_, _| false);
    let lines: Vec<&str> = DM_FIXTURE.split('\n').collect();
    let at = |snippet: &str| lines.iter().position(|l| l.contains(snippet)).unwrap() + 1;
    // C1: `force` on act_go is sent by no act(); act_modal_close's params arrive as a variable.
    let mut got: Vec<usize> = unsent.iter().map(|s| s.1).collect();
    got.sort();
    let mut want = vec![at("act_go("), at("act_breaker(")];
    want.sort();
    ensure(got == want, || format!("C1 {:?} want {:?}", got, want))?;
    // C2: act_raw's amount, name, when and extra; act_unused's level.
    let mut got: Vec<usize> = unvalidated.iter().map(|s| s.1).collect();
    got.sort();
    let mut want = vec![at("var/x = amount + 1"), at("to_chat(user, name)"), at("helper(when)"), at("src.helper(extra)"), at("world << level")];
    want.sort();
    ensure(got == want, || format!("C2 {:?} want {:?}", got, want))?;
    Ok(())
}

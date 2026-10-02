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

use std::cell::RefCell;
use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};
use std::rc::Rc;
use std::sync::Arc;

use crate::dm::dx::{enclosing_call, is_subtype, lineage, DxIndex, Proc};
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

#[derive(Clone, Debug, PartialEq)]
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
    idx: Arc<DxIndex>,
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

impl Hosts {
    fn new(tree: &Tree, files: &[&SourceFile], idx: Arc<DxIndex>) -> Hosts {
        let _ = tree;
        let mut ids = HashMap::new();
        let mut legacy = HashSet::new();
        for f in files {
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
                        legacy.insert(l.s(1).to_string());
                    }
                    if let Some(l) = pat!(r#"^(/[\w/]+?)/tgui_id\s*=\s*"([^"\n]+)""#).captures(raw.line(number)) {
                        ids.insert(l.s(1).to_string(), l.s(2).to_string());
                    }
                    continue;
                }
                if let Some(cur) = &current {
                    if code.contains("tgui_id") {
                        if let Some(t) = pat!(r#"^\s+tgui_id\s*=\s*"([^"\n]+)""#).captures(raw.line(number)) {
                            ids.insert(cur.clone(), t.s(1).to_string());
                        }
                    }
                }
            }
        }
        let mut acts: Om<Om<usize>> = Om::new();
        let mut cap_acts: Om<Om<usize>> = Om::new();
        let mut ctor_bodies = HashMap::new();
        let mut caps_bodies: Om<Vec<String>> = Om::new();
        // `Om<Vec<String>>` needs a Default for entry_or_new; do it by hand.
        for (n, proc) in idx.procs.iter().enumerate() {
            if proc.name.starts_with("act_") && !proc.is_global() {
                let table = if is_subtype(&proc.path, CAP_ROOT) { &mut cap_acts } else { &mut acts };
                if table.is_empty_at(&proc.path) {
                    table.insert(&proc.path, Om::new());
                }
                table.map.get_mut(&proc.path).unwrap().insert(&proc.name[4..], n);
            } else if proc.is_global() && (proc.name.starts_with("cap_") || proc.rel.starts_with(CAPS_DIR)) {
                ctor_bodies.insert(proc.name.clone(), body_text(&idx, proc, files));
            } else if proc.name == "capabilities" && !proc.is_global() {
                if caps_bodies.is_empty_at(&proc.path) {
                    caps_bodies.insert(&proc.path, Vec::new());
                }
                caps_bodies.map.get_mut(&proc.path).unwrap().push(body_text(&idx, proc, files));
            }
        }
        let mut hosts = Hosts {
            idx,
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

/// The sanitized body lines of `proc`, joined with newlines (`"\n".join(proc.body)`).
fn body_text(idx: &DxIndex, proc: &Proc, files: &[&SourceFile]) -> String {
    let _ = idx;
    match files.iter().find(|f| f.rel == proc.rel) {
        Some(f) => {
            let clean = f.clean();
            (0..proc.body_len).map(|k| clean.line(proc.body_start + k)).collect::<Vec<_>>().join("\n")
        }
        None => String::new(),
    }
}

// ---- analysis ---------------------------------------------------------------------------------

struct Analysis<'a> {
    tree: &'a Tree,
    hosts: &'a Hosts,
    norm: &'a Normaliser,
    acts: &'a Acts,
    pats: RefCell<HashMap<String, Rc<Pat>>>,
}

impl<'a> Analysis<'a> {
    fn proc(&self, n: usize) -> &Proc {
        &self.hosts.idx.procs[n]
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

    fn find_proc(&self, path: &str, name: &str) -> Option<&Proc> {
        let chain = lineage(path);
        let mut best: Option<(i64, &Proc)> = None;
        for proc in self.hosts.idx.procs_named(name) {
            if proc.is_global() || chain.contains(&proc.path) {
                let rank = if proc.is_global() {
                    -1
                } else {
                    chain.len() as i64 - chain.iter().position(|c| *c == proc.path).unwrap() as i64
                };
                if best.map(|b| rank > b.0).unwrap_or(true) {
                    best = Some((rank, proc));
                }
            }
        }
        best.map(|b| b.1)
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
                                    if helper.params.contains(target) && self.first_bad_use(helper, target, depth + 1).is_none() {
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

    /// C2: `(proc, param, line)`.
    fn unvalidated_params(&self, procs: &[usize]) -> Vec<(usize, String, usize)> {
        let mut out = Vec::new();
        for &n in procs {
            let proc = self.proc(n);
            for param in &proc.params {
                if self.norm.reserved.contains(param) {
                    continue;
                }
                if let Some(bad) = self.first_bad_use(proc, param, 0) {
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
        let mut tsx: Vec<(String, Vec<Call>)> = Vec::new();
        for f in &files {
            if matches!(f.ext(), "tsx" | "ts" | "jsx" | "js") && !f.rel.ends_with(".d.ts") {
                let calls = tsx_calls(f.text()).iter().map(|c| Call::new(&f.rel, c, &norm)).collect();
                tsx.push((f.rel.clone(), calls));
            }
        }
        let acts = Acts::real(tsx);
        let idx = DxIndex::get(cx.tree, &dm);
        let hosts = Hosts::new(cx.tree, &dm, idx);
        let an = Analysis { tree: cx.tree, hosts: &hosts, norm: &norm, acts: &acts, pats: RefCell::new(HashMap::new()) };
        let (unsent, unvalidated) = an.dx_sites(&mut |rel, line| match cx.tree.get(rel) {
            Some(f) => out.allowed(f, line, "ui_actions"),
            None => false,
        });
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
    let idx = DxIndex::get(&tree, &files);
    let hosts = Hosts::new(&tree, &files, idx);
    let table = vec![
        ("Thing".to_string(), calls.iter().map(|c| Call::new("x.tsx", c, &norm)).collect::<Vec<_>>()),
        ("Old".to_string(), vec![Call::new("o.tsx", &RawCall { line: 1, action: "nope".to_string(), keys: Some(vec![]) }, &norm)]),
    ];
    let acts = Acts::fixed(table);
    let an = Analysis { tree: &tree, hosts: &hosts, norm: &norm, acts: &acts, pats: RefCell::new(HashMap::new()) };
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

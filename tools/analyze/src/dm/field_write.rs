//! Port of `tools/ci/field_write_lint.py` (the library part): the declared-field write finder that
//! `api` (`field_write`), `sys/fields` and `sys/appearance` share.
//!
//! A declared field is declared once with `OM_FIELD(type, name, default, channel)` (and the typed,
//! flag and setter variants); the only writers allowed are its generated setter and the initial
//! value. [`violations`] finds every other write in a file's code view.
//!
//! The index ([`FwlIndex`]) is global: declared fields, typed member vars and `GLOBAL_DATUM` types
//! over EVERY `code/**/*.dm` (unit tests included), built once per tree (`FwlIndex::get`).
//!
//! The Python module also has a report CLI (`python tools/ci/field_write_lint.py`); that is not a
//! lint (no ratchet runs it), so only the library surface is ported.
//!
//! Quirks kept from the Python (do not fix here):
//!   * `locals_` maps a name to `None` for untyped locals, and `locals_.get(x) or member_type(..)`
//!     then falls through to the member lookup ([`local_or_member`]).
//!   * the last link of a `chain_type` is NOT stripped of a trailing `?`.
//!   * `member_types` and `global_types` are last-writer-wins in file order.
//!   * the `bare`/`dotted` regexes use `(?!=)` after `=`; implemented as a plain regex plus a
//!     post-check that is exactly equivalent (see [`write_matches`]).

use std::collections::{BTreeMap, HashMap};
use std::sync::Arc;

use serde::{Deserialize, Serialize};

use crate::incr;
use crate::pat::{Caps, Pat};
use crate::pat;
use crate::tree::{SourceFile, Tree, CODE_DM};
use crate::util::{is_py_space, py_rstrip};

/// Python `locals_`: local/param name -> declared type path, `None` for an untyped one.
pub type Locals = HashMap<String, Option<String>>;

/// DM's implicit parents (`IMPLICIT`).
const IMPLICIT: &[(&str, &str)] = &[
    ("/obj", "/datum/atom/movable/obj"),
    ("/mob", "/datum/atom/movable/mob"),
    ("/turf", "/datum/atom/turf"),
    ("/area", "/datum/atom/area"),
    ("/atom", "/datum/atom"),
];

const MODIFIERS: &[&str] = &["tmp", "static", "global", "const", "final"];

pub fn canon(path: &str) -> String {
    for (top, full) in IMPLICIT {
        if path == *top || (path.starts_with(top) && path.as_bytes().get(top.len()) == Some(&b'/')) {
            return format!("{}{}", full, &path[top.len()..]);
        }
    }
    path.to_string()
}

/// True when type path `a` is `b`, a subtype of `b`, or an ancestor of `b`.
pub fn related(a: &str, b: &str) -> bool {
    let (a, b) = (canon(a), canon(b));
    a == b || a.starts_with(&format!("{}/", b)) || b.starts_with(&format!("{}/", a))
}

pub fn norm(path: &str) -> String {
    if path.starts_with('/') {
        path.to_string()
    } else {
        format!("/{}", path)
    }
}

/// `"var/" in line[max(0, start-4):start+4]` is char-indexed in the Python; this is that window.
pub fn char_window(line: &str, start: usize, back: usize, fwd: usize) -> &str {
    let mut s = start;
    for _ in 0..back {
        if s == 0 {
            break;
        }
        s -= 1;
        while !line.is_char_boundary(s) {
            s -= 1;
        }
    }
    let mut e = start;
    for _ in 0..fwd {
        match line[e..].chars().next() {
            Some(c) => e += c.len_utf8(),
            None => break,
        }
    }
    &line[s..e]
}

/// `PROC_DEF_RE.match(line)`: a proc definition at column 0 (`(owner, name, text after the first "(")`).
pub struct ProcDef {
    pub owner: String,
    pub name: String,
    pub params: String,
}

pub fn proc_def(line: &str) -> Option<ProcDef> {
    let c = pat!(r"\A(?:(/[\w/]+?)/(?:(?:proc|verb)/)?(\w+)\((.*))").captures(line)?;
    Some(ProcDef { owner: c.s(1).to_string(), name: c.s(2).to_string(), params: c.s(3).to_string() })
}

/// One `TYPED_NAME_RE` match: byte start of the whole match, the type path (group 1, unnormalized)
/// and the name (group 2).
pub struct TypedName {
    pub start: usize,
    pub ty: String,
    pub name: String,
}

pub fn typed_names(text: &str) -> Vec<TypedName> {
    pat!(r"(?:var/)?((?:/?\w+)(?:/\w+)+)/(\w+)\b")
        .captures_iter(text)
        .into_iter()
        .map(|c| TypedName { start: c.start(0), ty: c.s(1).to_string(), name: c.s(2).to_string() })
        .collect()
}

/// `"var/" in line[max(0, start-4):start+4] or line[start:].startswith("var/")`.
pub fn is_var_decl(line: &str, start: usize) -> bool {
    char_window(line, start, 4, 4).contains("var/") || line[start..].starts_with("var/")
}

/// The untyped params of a proc head (`UNTYPED_PARAM_RE`).
pub fn untyped_params(params: &str) -> Vec<String> {
    pat!(r"(?:^|,)\s*(\w+)\s*(?==|,|\)|$)").captures_iter(params).into_iter().map(|c| c.s(1).to_string()).collect()
}

/// `Locals` seeded from a proc head's params (`TYPED_NAME_RE` then `UNTYPED_PARAM_RE`).
pub fn locals_from_params(params: &str) -> Locals {
    let mut locals = Locals::new();
    for tm in typed_names(params) {
        locals.insert(tm.name, Some(norm(&tm.ty)));
    }
    for name in untyped_params(params) {
        locals.entry(name).or_insert(None);
    }
    locals
}

/// `locals_.get(name) or member_type(owner, name)`.
pub fn local_or_member(index: &FwlIndex, locals: &Locals, owner: &str, name: &str) -> Option<String> {
    match locals.get(name) {
        Some(Some(t)) if !t.is_empty() => Some(t.clone()),
        _ => index.member_type(owner, name),
    }
}

/// The declared fields a lint checks: name -> declaring types, plus the compiled write patterns.
pub struct Fields {
    pub map: HashMap<String, Vec<String>>,
    bare: Option<Pat>,
    dotted: Option<Pat>,
}

impl Fields {
    pub fn new(ordered: Vec<(String, Vec<String>)>) -> Fields {
        let mut names: Vec<&String> = ordered.iter().map(|(n, _)| n).collect();
        // sorted(fields, key=len, reverse=True): stable on insertion order.
        names.sort_by(|a, b| b.chars().count().cmp(&a.chars().count()));
        let (bare, dotted) = if names.is_empty() {
            (None, None)
        } else {
            let alt = names.iter().map(|s| s.as_str()).collect::<Vec<_>>().join("|");
            // `(?!=)` after `=` is checked by hand ([`write_matches`]); the op is captured.
            let ops = r"(=|\+=|-=|\|=|&=|\^=|\*=|/=|\+\+|--)";
            (
                Some(Pat::new(&format!(r"(?<![\w./])(?:src\.)?({})\s*{}", alt, ops))),
                Some(Pat::new(&format!(r"(?<![\w])(\w+)(?:\?)?\.({})\s*{}", alt, ops))),
            )
        };
        Fields { map: ordered.into_iter().collect(), bare, dotted }
    }

    pub fn is_empty(&self) -> bool {
        self.map.is_empty()
    }
}

/// `finditer` of a write pattern whose op is the LAST capture group: a bare `=` followed by `=`
/// is `==` (Python's `=(?!=)`), so that candidate is rejected and the scan resumes one char on.
fn write_matches<'h>(pat: &Pat, line: &'h str) -> Vec<Caps<'h>> {
    let mut out = Vec::new();
    let mut pos = 0;
    while pos <= line.len() {
        let Some(c) = pat.captures_at(line, pos) else { break };
        let (s, e) = c.groups[0].unwrap();
        let last = c.groups.len() - 1;
        if c.s(last) == "=" && line[e..].starts_with('=') {
            pos = s + line[s..].chars().next().map(|ch| ch.len_utf8()).unwrap_or(1);
            continue;
        }
        pos = if e == s { e + line[e..].chars().next().map(|ch| ch.len_utf8()).unwrap_or(1) } else { e };
        out.push(c);
    }
    out
}

/// One direct write to a declared field.
pub struct Violation {
    pub line: usize,
    pub field: String,
    pub how: String,
}

/// The global index (`declared_fields`, `member_types`, `global_types`) over every `code/**/*.dm`.
pub struct FwlIndex {
    /// field name -> declaring types, names in first-seen order.
    pub fields: Vec<(String, Vec<String>)>,
    /// type path -> member var name -> declared type.
    pub members: BTreeMap<String, BTreeMap<String, String>>,
    /// `GLOB` var name -> declared type.
    pub globals: BTreeMap<String, String>,
}

#[derive(Serialize, Deserialize, Default, PartialEq)]
struct PerFile {
    fields: Vec<(String, String)>,
    members: Vec<(String, String, String)>,
    globals: Vec<(String, String)>,
}

fn scan_member_types(code: &str, out: &mut Vec<(String, String, String)>) {
    let mut add = |owner: &str, path: &str, name: &str| {
        let parts: Vec<&str> = path.split('/').filter(|p| !p.is_empty() && !MODIFIERS.contains(p)).collect();
        if !parts.is_empty() {
            out.push((owner.to_string(), name.to_string(), format!("/{}", parts.join("/"))));
        }
    };
    let mut current: Option<String> = None;
    for line in code.split('\n') {
        let first = line.chars().next();
        if let Some(ch) = first {
            if !is_py_space(ch) {
                if let Some(c) = pat!(r"\A(?:(/[\w/]+?)/var/((?:[\w]+/)*)(\w+)\b)").captures(line) {
                    add(c.s(1), c.s(2), c.s(3));
                    current = None;
                    continue;
                }
                let m = pat!(r"\A(?:(/[\w/]+)\s*(?:\{.*)?$)").captures(py_rstrip(line));
                current = match m {
                    Some(c) if !line.contains('(') => Some(c.s(1).to_string()),
                    _ => None,
                };
                continue;
            }
        }
        if let Some(cur) = &current {
            if let Some(c) = pat!(r"\A(?:\s+var/((?:[\w]+/)*)(\w+)\b)").captures(line) {
                add(cur, c.s(1), c.s(2));
            }
        }
    }
}

impl FwlIndex {
    pub fn build(files: &[&SourceFile]) -> FwlIndex {
        let per: Vec<PerFile> = incr::facts("fwl-facts", files, |f| {
            let mut p = PerFile { fields: Vec::new(), members: Vec::new(), globals: Vec::new() };
            let raw = f.raw();
            for line in raw.lines() {
                if !line.starts_with("OM_") {
                    continue;
                }
                let m = pat!(r"\A(?:OM_FIELD\(\s*(/[\w/]+)\s*,\s*(\w+)\s*,)").captures(line)
                    .or_else(|| pat!(r"\A(?:OM_FIELD_TYPED\(\s*(/[\w/]+)\s*,\s*[\w/]+\s*,\s*(\w+)\s*,)").captures(line))
                    .or_else(|| pat!(r"\A(?:OM_(?:FLAG_FIELD(?:_BITS)?|FIELD_SETTER)\(\s*(/[\w/]+)\s*,\s*(\w+)\s*,)").captures(line));
                if let Some(c) = m {
                    p.fields.push((c.s(2).to_string(), c.s(1).to_string()));
                }
            }
            scan_member_types(&f.code().text, &mut p.members);
            let text = &raw.text;
            if text.contains("GLOBAL_DATUM") {
                for c in pat!(r"GLOBAL_DATUM(?:_INIT)?\(\s*(\w+)\s*,\s*(/[\w/]+)").captures_iter(text) {
                    p.globals.push((c.s(1).to_string(), c.s(2).to_string()));
                }
            }
            p
        });
        let mut fields: Vec<(String, Vec<String>)> = Vec::new();
        let mut at: HashMap<String, usize> = HashMap::new();
        let mut members: BTreeMap<String, BTreeMap<String, String>> = BTreeMap::new();
        let mut globals = BTreeMap::new();
        for p in per {
            for (name, ty) in p.fields {
                match at.get(&name) {
                    Some(&i) => fields[i].1.push(ty),
                    None => {
                        at.insert(name.clone(), fields.len());
                        fields.push((name, vec![ty]));
                    }
                }
            }
            for (owner, name, ty) in p.members {
                members.entry(owner).or_default().insert(name, ty);
            }
            for (name, ty) in p.globals {
                globals.insert(name, ty);
            }
        }
        FwlIndex { fields, members, globals }
    }

    /// The index for this tree, built once and shared (memoized on the tree).
    pub fn get(tree: &Tree) -> Arc<FwlIndex> {
        tree.memo("field_write_index", || {
            let files = tree.select(&CODE_DM);
            FwlIndex::build(&files)
        })
    }

    /// A key of everything a judge can read from this index: the declared fields named in `only`
    /// (all when `None`), the typed members and the `GLOBAL_DATUM` types. Deterministic.
    pub fn ctx_key(&self, only: Option<&[&str]>) -> crate::tree::Hash {
        let fields: Vec<&(String, Vec<String>)> = self.fields.iter().filter(|(n, _)| only.map(|o| o.contains(&n.as_str())).unwrap_or(true)).collect();
        incr::ctx_key(&(fields, &self.members, &self.globals))
    }

    /// Every declared field (`index()`).
    pub fn all_fields(&self) -> Fields {
        Fields::new(self.fields.clone())
    }

    /// Only the named fields that are declared (`{k: v for k, v in index().items() if k in names}`).
    pub fn fields_named(&self, names: &[&str]) -> Fields {
        Fields::new(self.fields.iter().filter(|(n, _)| names.contains(&n.as_str())).cloned().collect())
    }

    /// The declared type of member var `name` of `owner`, searching up the path.
    pub fn member_type(&self, owner: &str, name: &str) -> Option<String> {
        let mut path = owner.to_string();
        while !path.is_empty() {
            if let Some(t) = self.members.get(&path).and_then(|m| m.get(name)) {
                return Some(t.clone());
            }
            if path.matches('/').count() > 1 {
                path = path.rsplit_once('/').unwrap().0.to_string();
            } else {
                break;
            }
        }
        None
    }

    /// The type of `recv` in `a.b.recv` (`before` = the text up to `recv`), walking typed members
    /// from the head; None when a link is unknown.
    pub fn chain_type(&self, owner: &str, locals: &Locals, before: &str, recv: &str) -> Option<String> {
        let c = pat!(r"((?:\w+\??\.)+)$").captures(before)?;
        let mut links: Vec<String> = c.s(1).split('.').filter(|x| !x.is_empty()).map(|x| x.trim_end_matches('?').to_string()).collect();
        links.push(recv.to_string());
        let head = links[0].clone();
        let mut t: Option<String>;
        if head == "GLOB" && links.len() > 1 {
            t = self.globals.get(&links[1]).cloned();
            links.remove(0);
        } else if head == "src" {
            t = Some(owner.to_string());
        } else {
            t = local_or_member(self, locals, owner, &head);
        }
        for link in &links[1..] {
            let cur = match &t {
                Some(x) if !x.is_empty() => x.clone(),
                _ => return None,
            };
            t = self.member_type(&cur, link);
        }
        t
    }

    /// Every write to a declared field in `text` (a file's code view) outside its setter.
    pub fn violations(&self, fields: &Fields, text: &str) -> Vec<Violation> {
        let mut out = Vec::new();
        let (Some(bare), Some(dotted)) = (&fields.bare, &fields.dotted) else { return out };
        let mut owner: Option<String> = None;
        let mut proc = String::new();
        let mut locals = Locals::new();
        for (no, line) in text.split('\n').enumerate().map(|(i, l)| (i + 1, l)) {
            if let Some(ch) = line.chars().next() {
                if !is_py_space(ch) {
                    if let Some(m) = proc_def(line) {
                        owner = Some(norm(&m.owner));
                        proc = m.name;
                        locals = locals_from_params(&m.params);
                        continue;
                    }
                    owner = None;
                    continue;
                }
            }
            let Some(owner) = owner.as_deref() else { continue };
            if line.contains("var/") {
                for c in pat!(r"\bvar/(?:(?:tmp|static|global|const)/)?(\w+)\b(?!/)").captures_iter(line) {
                    locals.entry(c.s(1).to_string()).or_insert(None);
                }
            }
            for tm in typed_names(line) {
                if is_var_decl(line, tm.start) {
                    locals.insert(tm.name, Some(norm(&tm.ty)));
                }
            }
            for m in write_matches(bare, line) {
                let field = m.s(1);
                let start = m.start(0);
                let end = m.end(0);
                let prefix = &line[..start];
                if py_rstrip(prefix).ends_with("var") || pat!(r"var/(?:[\w/]+/)?$").is_match(prefix) {
                    continue;
                }
                if locals.contains_key(field) {
                    continue; // a local of the same name shadows the field
                }
                let (before, after) = (py_rstrip(prefix), py_rstrip(&line[end..]));
                if before.ends_with('(') || before.ends_with(',') || after.ends_with(',') {
                    continue; // a named argument or a list entry
                }
                let decl = &fields.map[field];
                let setter = proc == format!("set_{}", field) || proc == format!("{}_add", field) || proc == format!("{}_remove", field);
                if setter && decl.iter().any(|t| owner == t) {
                    continue; // the generated setters (and only the declaring type's)
                }
                if decl.iter().any(|t| related(owner, t)) {
                    out.push(Violation { line: no, field: field.to_string(), how: format!("{}/{}", owner, proc) });
                }
            }
            for m in write_matches(dotted, line) {
                let (recv, field) = (m.s(1), m.s(2));
                if recv == "src" {
                    continue; // handled as a bare write
                }
                let start = m.start(0);
                let rtype = if start > 0 && line.as_bytes()[start - 1] == b'.' {
                    self.chain_type(owner, &locals, &line[..start], recv)
                } else {
                    local_or_member(self, &locals, owner, recv)
                };
                let decl = &fields.map[field];
                if let Some(t) = &rtype {
                    if !t.is_empty() && !decl.iter().any(|d| related(t, d)) {
                        continue; // a typed receiver of an unrelated type: a different var
                    }
                }
                out.push(Violation { line: no, field: field.to_string(), how: format!("{}.{} in {}/{}", recv, field, owner, proc) });
            }
        }
        out
    }

    /// `check(rel, text)`: one line number per direct write (api's `field_write`).
    pub fn check(&self, fields: &Fields, text: &str) -> Vec<usize> {
        self.violations(fields, text).into_iter().map(|v| v.line).collect()
    }
}

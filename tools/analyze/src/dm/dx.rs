//! Port of `tools/ci/sys_rules/_dx_dm.py`: the DM scanning helpers the dx_* rules, `ui_actions`
//! and `doc_snippets` share. Everything here is a static approximation of DM, good enough for
//! ratchet lints:
//!
//! * [`crate::strip::sanitize`] (via `SourceFile::clean()`): comments removed and string text
//!   blanked, code inside an embedded `[expr]` kept; same length, same newlines.
//! * [`DxIndex`]: every absolute proc definition ([`Proc`]) and `{type path: var names}`, built once
//!   per file set and shared by every rule that asks (`DxIndex::get`).
//! * [`lineage`] / [`vars_of`]: a type's ancestors (path prefixes plus DM's implicit parents).
//! * [`call_args`], [`enclosing_call`], [`pick_arg`], [`proc_ref`]: call-site parsing.
//!
//! Limits (unchanged from the Python): relative proc definitions are not seen, `parent_type`
//! overrides are ignored, macro-generated procs are invisible.

use std::collections::{HashMap, HashSet};
use std::sync::Arc;

use crate::pat;
use crate::tree::{SourceFile, Tree};
use crate::util::{py_lstrip, py_rstrip, py_strip};

/// DM's builtin vars (datum, atom, movable, mob, obj, turf, area, client-facing), never declared in code.
pub const BUILTIN_VARS: &[&str] = &[
    "type", "parent_type", "tag", "vars", "name", "desc", "suffix", "text", "icon", "icon_state",
    "icon_w", "icon_h", "dir", "layer", "plane", "alpha", "color", "blend_mode", "appearance",
    "appearance_flags", "density", "opacity", "anchored", "loc", "locs", "x", "y", "z",
    "contents", "overlays", "underlays", "vis_contents", "vis_locs", "vis_flags", "verbs",
    "luminosity", "invisibility", "infra_luminosity", "mouse_opacity", "mouse_over_pointer",
    "mouse_drag_pointer", "mouse_drop_pointer", "mouse_drop_zone", "pixel_x", "pixel_y", "pixel_w",
    "pixel_z", "step_x", "step_y", "step_size", "bound_x", "bound_y", "bound_width", "bound_height",
    "glide_size", "gender", "maptext", "maptext_width", "maptext_height", "maptext_x", "maptext_y",
    "transform", "filters", "render_source", "render_target", "screen_loc", "animate_movement",
    "override", "ckey", "key", "client", "sight", "see_in_dark", "see_invisible", "see_infrared",
    "group", "particles", "areas", "world",
];

// ---- small parsing helpers --------------------------------------------------------------------

/// `split_top`: splits `text` on `sep` outside `()`, `[]`, `{}` and quotes.
pub fn split_top(text: &str, sep: char) -> Vec<String> {
    let mut parts = Vec::new();
    let mut depth: i32 = 0;
    let mut cur = String::new();
    let mut quote: Option<char> = None;
    for c in text.chars() {
        if let Some(q) = quote {
            cur.push(c);
            if c == q {
                quote = None;
            }
            continue;
        }
        if c == '"' || c == '\'' {
            quote = Some(c);
        } else if c == '(' || c == '[' || c == '{' {
            depth += 1;
        } else if c == ')' || c == ']' || c == '}' {
            depth -= 1;
        } else if c == sep && depth == 0 {
            parts.push(std::mem::take(&mut cur));
            continue;
        }
        cur.push(c);
    }
    parts.push(cur);
    parts
}

/// `param_names`: the parameter names of a proc head's argument text.
pub fn param_names(params: &str) -> Vec<String> {
    let mut names = Vec::new();
    for part in split_top(params, ',') {
        let name = py_strip(part.split('=').next().unwrap_or(""));
        let name = pat!(r"\bas\b.*$").replace_all(name, "");
        let name = py_strip(py_strip(&name).rsplit('/').next().unwrap_or("")).to_string();
        if !name.is_empty() && name != "..." {
            names.push(name);
        }
    }
    names
}

/// A proc definition: `/T/proc/name(args)`, `/T/verb/name(args)`, `/T/name(args)` (an override)
/// or `/proc/name(args)`. Bodies are line ranges into the file's sanitized view.
#[derive(Clone, Debug, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct Proc {
    pub rel: String,
    /// 1-based line of the head.
    pub line: usize,
    /// Owning type path; "/" for a global proc.
    pub path: String,
    pub name: String,
    pub params: Vec<String>,
    /// 1-based number of the first body line, and how many lines the body has.
    pub body_start: usize,
    pub body_len: usize,
}

impl Proc {
    pub fn is_global(&self) -> bool {
        self.path == "/"
    }

    /// `(line number, sanitized text)` of each body line.
    pub fn lines<'t>(&self, tree: &'t Tree) -> Vec<(usize, &'t str)> {
        match tree.get(&self.rel) {
            Some(f) => {
                let clean = f.clean();
                (0..self.body_len).map(|k| (self.body_start + k, clean.line(self.body_start + k))).collect()
            }
            None => Vec::new(),
        }
    }

    /// The sanitized body lines.
    pub fn body<'t>(&self, tree: &'t Tree) -> Vec<&'t str> {
        self.lines(tree).into_iter().map(|(_, t)| t).collect()
    }

    /// The raw (comment-bearing) body lines.
    pub fn raw_body<'t>(&self, tree: &'t Tree) -> Vec<&'t str> {
        match tree.get(&self.rel) {
            Some(f) => (0..self.body_len).map(|k| f.line(self.body_start + k)).collect(),
            None => Vec::new(),
        }
    }

    /// The sanitized head line.
    pub fn head<'t>(&self, tree: &'t Tree) -> &'t str {
        tree.get(&self.rel).map(|f| f.clean().line(self.line)).unwrap_or("")
    }
}

/// `procs_in`: every absolute proc definition in one file.
pub fn procs_in(f: &SourceFile) -> Vec<Proc> {
    let clean = f.clean();
    let n = clean.num_lines();
    let mut out = Vec::new();
    let mut i = 0usize; // 0-based index into lines
    let line0 = |k: usize| clean.line(k + 1);
    while i < n {
        let mut head = py_rstrip(line0(i)).to_string();
        let mut last = i;
        // A head continued with `\` (discouraged, but it exists): join its lines.
        while head.ends_with('\\') && last + 1 < n && head.starts_with('/') {
            last += 1;
            head = format!("{} {}", &head[..head.len() - 1], py_strip(line0(last)));
        }
        // A parameter list spread over several lines: join until balanced.
        if head.starts_with('/') && head.contains('(') && count(&head, '(') > count(&head, ')') {
            let mut joined = head.clone();
            let mut k = last;
            while count(&joined, '(') > count(&joined, ')') && k + 1 < n && k - last < 40 {
                k += 1;
                joined = format!("{} {}", joined, py_strip(line0(k)));
            }
            if count(&joined, '(') == count(&joined, ')') {
                head = joined;
                last = k;
            }
        }
        let Some(m) = pat!(r"^(/[\w/]*?)/(?:(?:proc|verb)/)?(\w+)\((.*)\)\s*(?:as\s+[\w/|]+\s*)?$").captures(&head) else {
            i += 1;
            continue;
        };
        if format!("{}/", m.s(1)).contains("/var/") {
            i += 1;
            continue;
        }
        let mut path = if m.s(1).is_empty() { "/".to_string() } else { m.s(1).to_string() };
        if path == "/proc" || path == "/verb" {
            path = "/".to_string();
        }
        let start = last + 1;
        let mut j = start;
        while j < n {
            let l = line0(j);
            if py_strip(l).is_empty() || l.starts_with([' ', '\t']) || l.is_empty() {
                j += 1;
            } else {
                break;
            }
        }
        out.push(Proc {
            rel: f.rel.clone(),
            line: i + 1,
            path,
            name: m.s(2).to_string(),
            params: param_names(m.s(3)),
            body_start: start + 1,
            body_len: j - start,
        });
        i = j;
    }
    out
}

fn count(s: &str, c: char) -> usize {
    s.chars().filter(|&x| x == c).count()
}

/// `type_vars`: `{type path: var names}` declared in the files (both `/T/var/x` and a `var/x` line
/// inside a `/T` block, and grouped `var` blocks).
pub fn type_vars(files: &[&SourceFile]) -> HashMap<String, HashSet<String>> {
    let mut table: HashMap<String, HashSet<String>> = HashMap::new();
    for f in files {
        let clean = f.clean();
        let mut current: Option<String> = None;
        let mut group_indent: Option<usize> = None;
        for line in clean.lines() {
            if let Some(m) = pat!(r"^(/[\w/]+?)/var/(?:(?:global|static|tmp|const|final)/)*(?:[\w/]+/)?(\w+)\b").captures(line) {
                table.entry(m.s(1).to_string()).or_default().insert(m.s(2).to_string());
                current = None;
                continue;
            }
            if let Some(h) = pat!(r"^(/[\w/]+)\s*$").captures(py_rstrip(line)) {
                current = Some(h.s(1).to_string());
                group_indent = None;
                continue;
            }
            if !line.is_empty() && !line.starts_with([' ', '\t']) {
                current = None;
                continue;
            }
            let Some(cur) = &current else { continue };
            if let Some(gi) = group_indent {
                let indent = line.len() - py_lstrip(line).len();
                if !py_strip(line).is_empty() && indent > gi {
                    let t = py_strip(line);
                    let last = if !line.contains('=') {
                        t.rsplit('/').next().unwrap_or("")
                    } else {
                        py_strip(line.split('=').next().unwrap_or("")).rsplit('/').next().unwrap_or("")
                    };
                    if let Some(name) = pat!(r"\A[A-Za-z_]\w*").find(last) {
                        table.entry(cur.clone()).or_default().insert(name.as_str().to_string());
                    }
                    continue;
                }
                group_indent = None;
            }
            if let Some(g) = pat!(r"^(\s+)var\s*$").captures(line) {
                group_indent = Some(g.s(1).len());
                continue;
            }
            if let Some(v) = pat!(r"^\s+var/(?:[\w/]+/)?(\w+)\s*(?:=|$|\bas\b)").captures(line) {
                table.entry(cur.clone()).or_default().insert(v.s(1).to_string());
            }
        }
    }
    table
}

/// One file's contribution to every [`DxIndex`]: its procs and its `{type: vars}` table. A pure
/// function of the file, cached on disk by content.
#[derive(Clone, Default, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct FileDx {
    pub procs: Vec<Proc>,
    /// `(type path, var names)`, sorted.
    pub vars: Vec<(String, Vec<String>)>,
}

fn file_dx(f: &SourceFile) -> FileDx {
    let mut vars: Vec<(String, Vec<String>)> = type_vars(&[f])
        .into_iter()
        .map(|(t, set)| {
            let mut v: Vec<String> = set.into_iter().collect();
            v.sort();
            (t, v)
        })
        .collect();
    vars.sort();
    FileDx { procs: procs_in(f), vars }
}

/// The cached [`FileDx`] of every `.dm` file under `code/` and `maps/` (dot-files included), looked
/// up by path. One superset store serves every file set a lint asks about, so a lint with
/// different exemptions never evicts another's entries.
pub struct DxFacts {
    facts: Vec<FileDx>,
    index: HashMap<String, usize>,
}

impl DxFacts {
    /// The facts of the whole tree, built once per run.
    pub fn all(tree: &Tree) -> Arc<DxFacts> {
        tree.memo("dx-facts-all", || {
            let sel = crate::tree::Select { roots: &[("code", "dm"), ("maps", "dm")], hidden: true };
            let files = tree.select(&sel);
            let facts = crate::incr::facts("dx-file-facts", &files, file_dx);
            let index = files.iter().enumerate().map(|(i, f)| (f.rel.clone(), i)).collect();
            DxFacts { facts, index }
        })
    }

    /// The facts of `f`, from the store when it is in the tree's superset.
    pub fn of(&self, f: &SourceFile) -> std::borrow::Cow<'_, FileDx> {
        match self.index.get(&f.rel) {
            Some(&i) => std::borrow::Cow::Borrowed(&self.facts[i]),
            None => std::borrow::Cow::Owned(file_dx(f)),
        }
    }
}

/// One parse of a file set, shared by every rule that asks for the same set.
pub struct DxIndex {
    pub procs: Vec<Proc>,
    pub type_vars: HashMap<String, HashSet<String>>,
    by_name: HashMap<String, Vec<usize>>,
}

impl DxIndex {
    /// The index for exactly this list of files, built once per run.
    pub fn get(tree: &Tree, files: &[&SourceFile]) -> Arc<DxIndex> {
        let mut h = blake3::Hasher::new();
        h.update(b"dx-index");
        for f in files {
            h.update(&f.fkey.to_le_bytes());
        }
        let key = h.finalize().to_hex().to_string();
        let facts = DxFacts::all(tree);
        tree.memo(&key, || {
            let mut procs: Vec<Proc> = Vec::new();
            let mut table: HashMap<String, HashSet<String>> = HashMap::new();
            for f in files {
                let fd = facts.of(f);
                procs.extend(fd.procs.iter().cloned());
                for (t, vs) in &fd.vars {
                    table.entry(t.clone()).or_default().extend(vs.iter().cloned());
                }
            }
            let mut by_name: HashMap<String, Vec<usize>> = HashMap::new();
            for (i, p) in procs.iter().enumerate() {
                by_name.entry(p.name.clone()).or_default().push(i);
            }
            DxIndex { type_vars: table, procs, by_name }
        })
    }

    pub fn procs_named(&self, name: &str) -> Vec<&Proc> {
        self.by_name.get(name).map(|v| v.iter().map(|&i| &self.procs[i]).collect()).unwrap_or_default()
    }
}

// ---- types ------------------------------------------------------------------------------------

fn implicit_parent(path: &str) -> Option<&'static str> {
    match path {
        "/obj" | "/mob" => Some("/atom/movable"),
        "/atom/movable" => Some("/atom"),
        "/turf" | "/area" => Some("/atom"),
        "/atom" => Some("/datum"),
        _ => None,
    }
}

/// The path prefixes of `path`, shortest first (`path` included).
pub fn ancestors(path: &str) -> Vec<String> {
    let trimmed = path.trim_end_matches('/');
    let parts: Vec<&str> = trimmed.split('/').collect();
    (2..=parts.len()).map(|k| parts[..k].join("/")).collect()
}

/// `path` and every ancestor, nearest first, including DM's implicit parents; ends with `/datum`
/// for every datum path (not for "/", `/client`, `/list`, ...).
pub fn lineage(path: &str) -> Vec<String> {
    let mut out: Vec<String> = ancestors(path).into_iter().rev().collect();
    let mut root: Option<String> = out.last().cloned();
    while let Some(r) = root.clone() {
        match implicit_parent(&r) {
            Some(p) => {
                out.push(p.to_string());
                root = Some(p.to_string());
            }
            None => break,
        }
    }
    const NON_DATUM: &[&str] = &[
        "/client", "/world", "/list", "/savefile", "/regex", "/icon", "/image", "/sound", "/matrix", "/database",
        "/exception", "/generator", "/mutable_appearance", "/particles", "/dm_filter", "/callee",
    ];
    if let Some(last) = out.last() {
        if last != "/datum" && !NON_DATUM.contains(&last.as_str()) {
            out.push("/datum".to_string());
        }
    }
    out
}

pub fn is_subtype(path: &str, base: &str) -> bool {
    lineage(path).iter().any(|p| p == base)
}

/// `a` and `b` are the same type, or one descends from the other.
pub fn related(a: &str, b: &str) -> bool {
    is_subtype(a, b) || is_subtype(b, a)
}

/// The vars of `path` and its lineage, plus DM's builtin atom vars when `builtins`.
pub fn vars_of(table: &HashMap<String, HashSet<String>>, path: &str, builtins: bool) -> HashSet<String> {
    let mut out: HashSet<String> = if builtins { BUILTIN_VARS.iter().map(|s| s.to_string()).collect() } else { HashSet::new() };
    for anc in lineage(path) {
        if let Some(v) = table.get(&anc) {
            out.extend(v.iter().cloned());
        }
    }
    out
}

// ---- calls ------------------------------------------------------------------------------------

/// Index of the `)` closing the `(` at `text[i]` (brackets count like parens), or None.
pub fn match_paren(text: &str, i: usize) -> Option<usize> {
    let b = text.as_bytes();
    let mut depth = 0i32;
    for (j, &c) in b.iter().enumerate().skip(i) {
        if c == b'(' || c == b'[' {
            depth += 1;
        } else if c == b')' || c == b']' {
            depth -= 1;
            if depth == 0 {
                return Some(j);
            }
        }
    }
    None
}

/// The argument strings (trimmed) of the call whose `(` is at `text[i]`.
pub fn call_args(text: &str, i: usize) -> Option<Vec<String>> {
    let end = match_paren(text, i)?;
    Some(split_top(&text[i + 1..end], ',').iter().map(|a| py_strip(a).to_string()).collect())
}

/// `(start, end)` byte offsets of each argument of the call whose `(` is at `text[i]`.
pub fn call_arg_spans(text: &str, i: usize) -> Option<Vec<(usize, usize)>> {
    let end = match_paren(text, i)?;
    let b = text.as_bytes();
    let mut spans = Vec::new();
    let mut depth = 0i32;
    let mut start = i + 1;
    for k in i + 1..end {
        match b[k] {
            b'(' | b'[' | b'{' => depth += 1,
            b')' | b']' | b'}' => depth -= 1,
            b',' if depth == 0 => {
                spans.push((start, k));
                start = k + 1;
            }
            _ => {}
        }
    }
    spans.push((start, end));
    Some(spans)
}

/// The argument at positional `index` (counting only positional args before any named one) or
/// named `name`, from [`call_args`] output.
pub fn pick_arg(args: &[String], index: Option<usize>, name: &str) -> Option<String> {
    let mut positional: Vec<&String> = Vec::new();
    for arg in args {
        if let Some(m) = pat!(r"^\s*([A-Za-z_]\w*)\s*=(?!=)").captures(arg) {
            if m.s(1) == name {
                return Some(py_strip(&arg[m.end(0)..]).to_string());
            }
            continue;
        }
        positional.push(arg);
    }
    match index {
        Some(i) if i < positional.len() => Some(positional[i].clone()),
        _ => None,
    }
}

/// For the expression starting at `text[i]`: (name, positional index, named-arg key, member call?)
/// of the innermost call it is a direct argument of. `member` is only meaningful with
/// `want_member`.
#[derive(Clone, Debug, PartialEq)]
pub struct Enclosing {
    pub name: String,
    pub index: usize,
    pub key: Option<String>,
    pub member: bool,
}

pub fn enclosing_call(text: &str, i: usize) -> Option<Enclosing> {
    let b = text.as_bytes();
    let mut depth = 0i32;
    let mut commas = 0usize;
    let mut j = i as isize - 1;
    while j >= 0 {
        let ju = j as usize;
        let c = b[ju];
        if c == b')' || c == b']' {
            depth += 1;
        } else if c == b'(' || c == b'[' {
            if depth == 0 {
                if c == b'[' {
                    return None;
                }
                let before = &text[..ju];
                let m = pat!(r"([A-Za-z_]\w*)\s*$").captures(before)?;
                // the start of this argument, to spot `key = value`
                let mut seg_start = ju + 1;
                let mut d2 = 0i32;
                for k in ju + 1..i {
                    match b[k] {
                        b'(' | b'[' => d2 += 1,
                        b')' | b']' => d2 -= 1,
                        b',' if d2 == 0 => seg_start = k + 1,
                        _ => {}
                    }
                }
                let key = pat!(r"\A\s*([A-Za-z_]\w*)\s*=(?!=)").captures(&text[seg_start..i]).map(|k| k.s(1).to_string());
                let head = py_rstrip(&text[..m.start(0)]);
                return Some(Enclosing {
                    name: m.s(1).to_string(),
                    index: commas,
                    key,
                    member: head.ends_with('.') || head.ends_with(':'),
                });
            }
            depth -= 1;
        } else if c == b',' && depth == 0 {
            commas += 1;
        }
        j -= 1;
    }
    None
}

/// `proc_ref`: `(kind, type, name)` for a PROC_REF-family argument. `kind` is "src" (PROC_REF,
/// VERB_REF: the calling type), "type" (TYPE_PROC_REF/TYPE_VERB_REF) or "global".
pub fn proc_ref(arg: &str) -> Option<(&'static str, Option<String>, String)> {
    let m = pat!(
        r"^\s*(?:PROC_REF\(\s*(\w+)\s*\)|TYPE_PROC_REF\(\s*(/[\w/]+)\s*,\s*(\w+)\s*\)|GLOBAL_PROC_REF\(\s*(\w+)\s*\)|TYPE_VERB_REF\(\s*(/[\w/]+)\s*,\s*(\w+)\s*\)|VERB_REF\(\s*(\w+)\s*\))\s*$"
    )
    .captures(arg)?;
    if m.matched(1) {
        return Some(("src", None, m.s(1).to_string()));
    }
    if m.matched(3) {
        return Some(("type", Some(m.s(2).to_string()), m.s(3).to_string()));
    }
    if m.matched(4) {
        return Some(("global", None, m.s(4).to_string()));
    }
    if m.matched(6) {
        return Some(("type", Some(m.s(5).to_string()), m.s(6).to_string()));
    }
    Some(("src", None, m.s(7).to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn split_top_respects_nesting() {
        assert_eq!(split_top("a, f(b, c), [d, e], \"x,y\"", ','), vec!["a", " f(b, c)", " [d, e]", " \"x,y\""]);
    }

    #[test]
    fn procs_and_params() {
        let f = SourceFile::from_text(
            "code/a.dm",
            "/obj/thing/proc/poke(mob/user, amount = 1)\n\tif(amount)\n\t\treturn\n\n/obj/thing/other()\n\treturn 1\n",
        );
        let p = procs_in(&f);
        assert_eq!(p.len(), 2);
        assert_eq!(p[0].path, "/obj/thing");
        assert_eq!(p[0].name, "poke");
        assert_eq!(p[0].params, vec!["user", "amount"]);
        assert_eq!(p[0].body_len, 3);
        assert_eq!(p[1].name, "other");
    }

    #[test]
    fn lineage_adds_implicit_parents() {
        assert_eq!(lineage("/obj/item"), vec!["/obj/item", "/obj", "/atom/movable", "/atom", "/datum"]);
        assert_eq!(lineage("/datum/foo"), vec!["/datum/foo", "/datum"]);
        assert!(lineage("/").is_empty());
        assert_eq!(lineage("/client"), vec!["/client"]);
    }

    #[test]
    fn enclosing_call_finds_argument_position() {
        let text = "foo(a, bar(x, y = baz))";
        let at = text.find("baz").unwrap();
        let e = enclosing_call(text, at).unwrap();
        assert_eq!(e.name, "bar");
        assert_eq!(e.index, 1);
        assert_eq!(e.key.as_deref(), Some("y"));
    }

    #[test]
    fn type_vars_collects_blocks() {
        let f = SourceFile::from_text("code/a.dm", "/obj/thing\n\tvar/a = 1\n\tvar\n\t\tb\n\t\tc = 2\n/obj/thing/var/d\n");
        let t = type_vars(&[&f]);
        let v = &t["/obj/thing"];
        assert!(v.contains("a") && v.contains("b") && v.contains("c") && v.contains("d"));
    }
}

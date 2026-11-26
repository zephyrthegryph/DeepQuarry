//! The structure parser `base_vars` and `lifecycle` share: [`parse_file`] reads the declared vars of one
//! file's `code_only` view ([`crate::strip::code_only`], `SourceFile::code()`), and [`chain`] is a
//! type with its ancestors, root first.

use std::collections::{BTreeSet, HashMap};

use crate::tree::View;
use crate::util::{py_lstrip, py_rstrip, py_strip, under};
use crate::pat_match;

pub const MODIFIERS: &[&str] = &["tmp", "static", "global", "const", "final"];
pub const UNSAVED: &[&str] = &["tmp", "static", "global", "const"];
/// Object type roots. A declared type under one of these holds a reference.
pub const REF_ROOTS: &[&str] = &[
    "/datum", "/atom", "/obj", "/mob", "/turf", "/area", "/image", "/icon", "/client", "/sound", "/matrix", "/mutable_appearance", "/savefile",
    "/regex", "/database", "/exception", "/callback", "/decl",
];

/// A declared var (`class Var`).
#[derive(Clone, Debug)]
pub struct Var {
    pub owner: String,
    pub name: String,
    pub mods: BTreeSet<String>,
    pub vtype: String,
    pub is_list: bool,
    /// Repo-relative path of the declaring file.
    pub path: String,
    pub line: usize,
}

impl Var {
    /// Not `tmp`, `static`, `global` or `const`.
    pub fn saved(&self) -> bool {
        !self.mods.iter().any(|m| UNSAVED.contains(&m.as_str()))
    }

    pub fn holds_ref(&self) -> bool {
        under(&self.vtype, REF_ROOTS)
    }
}

/// `ancestors(path)`: the path's prefixes, shortest first, the path included.
pub fn ancestors(path: &str) -> Vec<String> {
    let segs: Vec<&str> = path.trim_matches('/').split('/').collect();
    (1..=segs.len()).map(|i| format!("/{}", segs[..i].join("/"))).collect()
}

/// The type and its ancestors, root first. Everything inherits /datum, except the built-in roots
/// that do not (none of ours).
pub fn chain(path: &str) -> Vec<String> {
    let mut out = ancestors(path);
    if out[0] != "/datum" {
        let first = out[0].as_str();
        if matches!(first, "/obj" | "/mob" | "/turf" | "/area") {
            let n = if matches!(first, "/obj" | "/mob") { 3 } else { 2 };
            let mut pre: Vec<String> = ["/datum", "/atom", "/atom/movable"][..n].iter().map(|s| s.to_string()).collect();
            pre.extend(out);
            out = pre;
        } else if first == "/atom" {
            out.insert(0, "/datum".to_string());
        }
    }
    out
}

/// `split_decl`: `(name, mods, vtype, is_list)` of the path segments of a declaration, or None.
fn split_decl(mut segs: Vec<&str>, block_mods: &BTreeSet<String>) -> Option<(String, BTreeSet<String>, String, bool)> {
    let mut mods = block_mods.clone();
    while !segs.is_empty() && MODIFIERS.contains(&segs[0]) {
        mods.insert(segs.remove(0).to_string());
    }
    if segs.is_empty() {
        return None;
    }
    let name = segs[segs.len() - 1].to_string();
    let mut tsegs: Vec<&str> = segs[..segs.len() - 1].to_vec();
    let mut is_list = false;
    if !tsegs.is_empty() && tsegs[0] == "list" {
        is_list = true;
        tsegs.remove(0);
    }
    let vtype = if tsegs.is_empty() { String::new() } else { format!("/{}", tsegs.join("/")) };
    Some((name, mods, vtype, is_list))
}

fn push_var(decls: &mut HashMap<String, Vec<Var>>, owner: &str, d: (String, BTreeSet<String>, String, bool), rel: &str, line: usize) {
    let (name, mods, vtype, is_list) = d;
    decls.entry(owner.to_string()).or_default().push(Var { owner: owner.to_string(), name, mods, vtype, is_list, path: rel.to_string(), line });
}

/// `parse()` for one file's `code_only` view: appends to `decls`.
pub fn parse_file(rel: &str, code: &View, decls: &mut HashMap<String, Vec<Var>>) {
    let header = pat_match!(r"^(/?[A-Za-z_][\w/]*)\s*(?:$|=|\()");
    let block_member = pat_match!(r"^((?:[A-Za-z_]\w*/)*[A-Za-z_]\w*)\s*(?:\[[^\]]*\])?\s*(?:=|$)");
    let block_head = pat_match!(r"^var(/(tmp|static|global|const))*\s*$");
    let var_decl = pat_match!(r"^var((?:/[A-Za-z_]\w*)+)\s*(?:\[[^\]]*\])?\s*(?:=|$|as\b)");
    let empty = BTreeSet::new();

    let mut cur: Option<String> = None; // current type block
    let mut in_proc = false; // inside a proc body
    let mut block_mods: Option<BTreeSet<String>> = None; // modifiers of an open `var` / `var/tmp` block
    let mut block_indent = 0usize;
    for (no, raw) in code.numbered() {
        if py_strip(raw).is_empty() {
            continue;
        }
        let stripped = raw.trim_start_matches(['\t', ' ']);
        let indent = raw.len() - stripped.len();
        let text = py_rstrip(stripped);
        if text.starts_with('#') {
            continue;
        }
        if indent == 0 {
            block_mods = None;
            in_proc = false;
            cur = None;
            let Some(m) = header.captures(text) else { continue };
            let g1 = m.s(1);
            let full = if g1.starts_with('/') { g1.to_string() } else { format!("/{}", g1) };
            let segs: Vec<&str> = full.trim_matches('/').split('/').collect();
            let has_proc = segs.contains(&"proc");
            let has_verb = segs.contains(&"verb");
            if has_proc || has_verb || py_lstrip(&text[g1.len()..]).starts_with('(') {
                let k = if has_proc {
                    segs.iter().position(|s| *s == "proc").unwrap()
                } else if has_verb {
                    segs.iter().position(|s| *s == "verb").unwrap()
                } else {
                    segs.len() - 1
                };
                let _owner = format!("/{}", segs[..k].join("/"));
                in_proc = true;
                continue;
            }
            if let Some(k) = segs.iter().position(|s| *s == "var") {
                let owner = format!("/{}", segs[..k].join("/"));
                if let Some(d) = split_decl(segs[k + 1..].to_vec(), &empty) {
                    push_var(decls, &owner, d, rel, no);
                }
                continue;
            }
            cur = Some(full.trim_end_matches('/').to_string());
            continue;
        }
        if in_proc {
            continue;
        }
        let Some(cur_t) = cur.as_deref() else { continue };
        if let Some(bm) = &block_mods {
            if indent > block_indent {
                if let Some(m) = block_member.captures(text) {
                    if let Some(d) = split_decl(m.s(1).split('/').collect(), bm) {
                        push_var(decls, cur_t, d, rel, no);
                    }
                }
                continue;
            }
        }
        block_mods = None;
        if indent != 1 && !raw.starts_with("    ") {
            continue;
        }
        if block_head.is_match(text) {
            block_mods = Some(text.split('/').skip(1).map(|s| s.to_string()).collect());
            block_indent = indent;
            continue;
        }
        if let Some(m) = var_decl.captures(text) {
            if let Some(d) = split_decl(m.s(1).trim_matches('/').split('/').collect(), &empty) {
                push_var(decls, cur_t, d, rel, no);
            }
            continue;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tree::SourceFile;

    #[test]
    fn chain_adds_implicit_roots() {
        assert_eq!(chain("/obj/item"), ["/datum", "/atom", "/atom/movable", "/obj", "/obj/item"]);
        assert_eq!(chain("/turf/x"), ["/datum", "/atom", "/turf", "/turf/x"]);
        assert_eq!(chain("/atom/movable"), ["/datum", "/atom", "/atom/movable"]);
        assert_eq!(chain("/datum/a"), ["/datum", "/datum/a"]);
        assert_eq!(chain("/client"), ["/client"]);
    }

    #[test]
    fn parse_reads_vars_blocks() {
        let f = SourceFile::from_text(
            "code/a.dm",
            "/obj/thing\n\tvar/datum/a = null\n\tvar/tmp\n\t\tobj/b\n\t\tlist/mob/c = list()\n\tvar/static/list/d\n/obj/thing/sub\n",
        );
        let mut decls = HashMap::new();
        parse_file(&f.rel, f.code(), &mut decls);
        let v = &decls["/obj/thing"];
        assert_eq!(v.len(), 4);
        assert!(v[0].saved() && v[0].holds_ref());
        assert!(!v[1].saved() && !v[2].saved() && v[2].is_list && v[2].vtype == "/mob");
        assert!(!v[3].saved());
    }
}

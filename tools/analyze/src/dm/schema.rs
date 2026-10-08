//! Port of `tools/ci/state_schema_lint.py`'s shared scanner: the structure parser other lints
//! import (`base_vars_lint`, `lifecycle_lint`, `scheduler_lints`, `derived_reads_lint`,
//! `ownership_lint`). `code_only` is [`crate::strip::code_only`] (`SourceFile::code()`).
//!
//! * [`Schema::get`]: one parse of every file, memoized per run: [`Schema::decls`] (the Python
//!   `parse()` decls), [`Schema::latent`] (`latent_safe =` per type), [`Schema::codecs`]
//!   (`parse_codec_keys`) and [`Schema::registry`] (`REGISTRY_TYPES`).
//! * [`chain`], [`ancestors`], [`Schema::effective_latent`], [`Schema::has_codec`],
//!   [`Schema::safe_types`].
//! * [`OwnershipKinds`]: `ownership_kind(owner, name)` (declared kind, or inferred from accessor
//!   writes), built on [`crate::dm::ownership_index::Index`].
//!
//! The Python walked `glob.glob` order; files are parsed here in path order. That only changes
//! which of two declarations of the same var on the same type is listed first.

use std::collections::{BTreeSet, HashMap, HashSet};
use std::sync::Arc;

use serde::{Deserialize, Serialize};

use crate::dm::ownership_index::{self as oi, Index};
use crate::tree::{SourceFile, Tree, View};
use crate::util::{py_lstrip, py_rstrip, py_strip, under};
use crate::{pat, pat_match};

pub const MODIFIERS: &[&str] = &["tmp", "static", "global", "const", "final"];
pub const UNSAVED: &[&str] = &["tmp", "static", "global", "const"];
/// Object type roots. A declared type under one of these holds a reference.
pub const REF_ROOTS: &[&str] = &[
    "/datum", "/atom", "/obj", "/mob", "/turf", "/area", "/image", "/icon", "/client", "/sound", "/matrix", "/mutable_appearance", "/savefile",
    "/regex", "/database", "/exception", "/callback", "/decl",
];
/// Frozen definition / registry types that are never deleted (implicitly SHARED).
pub const DEF_TYPES: &[&str] = &["/datum/material", "/datum/decl", "/decl", "/datum/language", "/datum/property_def", "/datum/msg"];
/// Base types whose vars are reported by `--report` (the tmp hygiene pass).
pub const BASE_TYPES: &[&str] = &["/datum", "/atom", "/atom/movable", "/obj", "/obj/item", "/obj/machinery", "/mob"];
/// Where `REGISTRY_TYPE(...)` rows live.
pub const REGISTRY_FILE: &str = "code/datums/ownership/registry_types.dm";

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

    /// `registry` needs the registry list (`Schema::registry`): the Python read a module global.
    pub fn registry(&self, registry: &[String]) -> bool {
        under(&self.vtype, registry)
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

/// `parse()` for one file's `code_only` view: appends to `decls` and `latent`.
pub fn parse_file(rel: &str, code: &View, decls: &mut HashMap<String, Vec<Var>>, latent: &mut HashMap<String, bool>) {
    let header = pat_match!(r"^(/?[A-Za-z_][\w/]*)\s*(?:$|=|\()");
    let block_member = pat_match!(r"^((?:[A-Za-z_]\w*/)*[A-Za-z_]\w*)\s*(?:\[[^\]]*\])?\s*(?:=|$)");
    let block_head = pat_match!(r"^var(/(tmp|static|global|const))*\s*$");
    let var_decl = pat_match!(r"^var((?:/[A-Za-z_]\w*)+)\s*(?:\[[^\]]*\])?\s*(?:=|$|as\b)");
    let latent_re = pat_match!(r"^latent_safe\s*=\s*(TRUE|FALSE|1|0)\b");
    let latent_registration = pat_match!(r"^register\(\s*(/[A-Za-z_][\w/]*)\s*,\s*TYPE_META_LATENT_SAFE\s*,\s*(TRUE|FALSE|1|0)\s*\)");
    let empty = BTreeSet::new();

    let mut cur: Option<String> = None; // current type block
    let mut in_proc = false; // inside a proc body
    let mut in_metadata_registration = false;
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
            in_metadata_registration = false;
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
                in_metadata_registration = matches!(full.as_str(),
                    "/datum/type_metadata_registry/register_defaults" |
                    "/datum/type_metadata_registry/register_test_defaults" |
                    "/datum/type_metadata_registry/proc/register_defaults" |
                    "/datum/type_metadata_registry/proc/register_test_defaults");
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
            if in_metadata_registration {
                if let Some(m) = latent_registration.captures(text) {
                    latent.insert(m.s(1).to_string(), matches!(m.s(2), "TRUE" | "1"));
                }
            }
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
        if let Some(m) = latent_re.captures(text) {
            latent.insert(cur_t.to_string(), matches!(m.s(1), "TRUE" | "1"));
        }
    }
}

/// `parse_codec_keys` for one file: `state_codecs()` keys are string literals, which `code_only`
/// blanks, so they are read from the raw text of each `state_codecs()` proc.
pub fn parse_codec_keys_file(text: &str, codecs: &mut HashMap<String, HashSet<String>>) {
    let head = pat!(r"(?m)^(/[\w/]+)/state_codecs\(\)");
    let first_nonspace_line = pat!(r"(?m)^\S");
    let key = pat!(r#""(\w+)"\s*=\s*/datum/state_codec"#);
    for m in head.captures_iter(text) {
        let owner = m.s(1).replace("/proc", "");
        let end = m.end(0);
        let rest = &text[end..];
        let stop = first_nonspace_line.find(rest).map(|e| e.start).unwrap_or(rest.len());
        let body = &rest[..stop];
        for k in key.captures_iter(body) {
            codecs.entry(owner.clone()).or_default().insert(k.s(1).to_string());
        }
    }
}

/// `REGISTRY_TYPES`: every `REGISTRY_TYPE(/path, ...)` row of `registry_types.dm`, then `/decl`.
pub fn registry_types(tree: &Tree) -> Vec<String> {
    let mut found = Vec::new();
    if let Some(f) = tree.get(REGISTRY_FILE) {
        for line in f.raw().lines() {
            if let Some(m) = pat_match!(r"^REGISTRY_TYPE\(\s*(/[\w/]+)\s*,").captures(line) {
                found.push(m.s(1).to_string());
            }
        }
    }
    found.push("/decl".to_string());
    found
}

/// One file's contribution to the [`Schema`] (cached per file by content).
#[derive(Serialize, Deserialize, Default, PartialEq)]
struct SchemaFacts {
    /// `(owner, name, mods, vtype, is_list, line)` in the file's declaration order per owner
    decls: Vec<(String, String, Vec<String>, String, bool, u32)>,
    latent: Vec<(String, bool)>,
    codecs: Vec<(String, Vec<String>)>,
}

/// One file's accessor usage and default-child declarations (`OwnershipKinds`).
#[derive(Serialize, Deserialize, Default, PartialEq)]
struct KindFacts {
    /// `(var name, kind index into KIND_NAMES)`, sorted and distinct
    usage: Vec<(String, u8)>,
}

const KIND_NAMES: [&str; 4] = ["OWN", "REL", "PROTO", "SHARED"];

/// The whole parse, built once per run (`Schema::get`).
#[derive(Debug, Default)]
pub struct Schema {
    /// type -> declared vars, in file order then line order
    pub decls: HashMap<String, Vec<Var>>,
    /// type -> `latent_safe` as set in that type's own block
    pub latent: HashMap<String, bool>,
    /// type -> `state_codecs()` key names
    pub codecs: HashMap<String, HashSet<String>>,
    /// `REGISTRY_TYPES`
    pub registry: Vec<String>,
}

impl Schema {
    pub fn get(tree: &Tree, files: &[&SourceFile]) -> Arc<Schema> {
        let mut h = blake3::Hasher::new();
        h.update(b"state-schema");
        for f in files {
            h.update(&f.fkey.to_le_bytes());
        }
        let key = h.finalize().to_hex().to_string();
        tree.memo(&key, || Schema::build(tree, files))
    }

    pub fn build(tree: &Tree, files: &[&SourceFile]) -> Schema {
        let facts: Vec<SchemaFacts> = oi::sharded_facts("schema-facts-type-metadata-v2", files, |f| {
            let mut decls: HashMap<String, Vec<Var>> = HashMap::new();
            let mut latent: HashMap<String, bool> = HashMap::new();
            parse_file(&f.rel, f.code(), &mut decls, &mut latent);
            let mut codecs: HashMap<String, HashSet<String>> = HashMap::new();
            parse_codec_keys_file(f.raw().text.as_str(), &mut codecs);
            let mut out = SchemaFacts::default();
            let mut owners: Vec<&String> = decls.keys().collect();
            owners.sort();
            for o in owners {
                for v in &decls[o] {
                    out.decls.push((o.clone(), v.name.clone(), v.mods.iter().cloned().collect(), v.vtype.clone(), v.is_list, v.line as u32));
                }
            }
            out.latent = latent.into_iter().collect();
            out.latent.sort();
            for (o, keys) in codecs {
                let mut ks: Vec<String> = keys.into_iter().collect();
                ks.sort();
                out.codecs.push((o, ks));
            }
            out.codecs.sort();
            out
        });
        let mut s = Schema { registry: registry_types(tree), ..Schema::default() };
        for (f, x) in files.iter().zip(facts) {
            for (owner, name, mods, vtype, is_list, line) in x.decls {
                push_var(&mut s.decls, &owner, (name, mods.into_iter().collect(), vtype, is_list), &f.rel, line as usize);
            }
            for (t, v) in x.latent {
                s.latent.insert(t, v);
            }
            for (o, keys) in x.codecs {
                s.codecs.entry(o).or_default().extend(keys);
            }
        }
        s
    }

    /// `effective_latent(path, latent)`: the last `latent_safe` set along the chain.
    pub fn effective_latent(&self, path: &str) -> bool {
        let mut val = false;
        for a in chain(path) {
            if let Some(v) = self.latent.get(&a) {
                val = *v;
            }
        }
        val
    }

    /// `has_codec(owner, name, subject)`: a `state_codecs()` key `name` on `subject` or an ancestor.
    pub fn has_codec(&self, name: &str, subject: &str) -> bool {
        chain(subject).iter().any(|a| self.codecs.get(a).map(|s| s.contains(name)).unwrap_or(false))
    }

    /// Every type that is latent-safe, sorted.
    pub fn safe_types(&self) -> Vec<String> {
        let mut all: BTreeSet<&String> = self.decls.keys().collect();
        all.extend(self.latent.keys());
        all.into_iter().filter(|t| self.effective_latent(t)).cloned().collect()
    }
}

/// `ownership_kind(owner, name)`: the declared ownership kind of a var, or the kind inferred from
/// accessor writes (`own_*` / `rel_*` / `proto_*` / `shared_set`), or None.
#[derive(Debug)]
pub struct OwnershipKinds {
    pub idx: Arc<Index>,
    /// var name -> kinds it is written through (`OWN`, `REL`, `PROTO`, `SHARED`)
    pub usage: HashMap<String, BTreeSet<&'static str>>,
    /// `(type, var)` declared in a `CAPABILITIES(/type)` block: `owns_one` / `owns_many` are `OWN`, `ref_one` / `ref_many` are `REL`.
    pub declared: HashMap<(String, String), &'static str>,
}

impl OwnershipKinds {
    pub fn get(tree: &Tree, files: &[&SourceFile]) -> Arc<OwnershipKinds> {
        let mut h = blake3::Hasher::new();
        h.update(b"ownership-kinds");
        for f in files {
            h.update(&f.fkey.to_le_bytes());
        }
        let key = h.finalize().to_hex().to_string();
        tree.memo(&key, || OwnershipKinds::build(tree, files))
    }

    pub fn build(tree: &Tree, files: &[&SourceFile]) -> OwnershipKinds {
        let idx = Index::get(tree, files);
        let facts: Vec<KindFacts> = oi::sharded_facts("schema-kinds-facts", files, |f| {
            let raw = f.raw();
            let mut usage: BTreeSet<(String, u8)> = BTreeSet::new();
            for m in oi::ACCESSOR.captures_iter(&raw.text) {
                let func = m.s(1);
                let kind = if func.starts_with("own_") {
                    0
                } else if func.starts_with("rel_") {
                    1
                } else if func.starts_with("proto_") {
                    2
                } else {
                    3
                };
                usage.insert((m.s(3).to_string(), kind));
            }
            KindFacts { usage: usage.into_iter().collect() }
        });
        let mut usage: HashMap<String, BTreeSet<&'static str>> = HashMap::new();
        for x in facts {
            for (name, kind) in x.usage {
                usage.entry(name).or_default().insert(KIND_NAMES[kind as usize]);
            }
        }
        // The declared form: the entries of CAPABILITIES(T) blocks (sem::decls reads the blocks, backslash form and block form alike).
        let entry = regex::Regex::new(r"\b(owns_one|owns_many|ref_one|ref_many)\(\s*nameof\((\w+)\)").expect("ownership entry pattern");
        let mut declared: HashMap<(String, String), &'static str> = HashMap::new();
        for m in crate::sem::decls::Decls::get(tree).markers_named("CAPABILITIES") {
            let Some(ty) = m.args.first() else { continue };
            for c in entry.captures_iter(&m.body) {
                let kind = if c[1].starts_with("owns_") { "OWN" } else { "REL" };
                declared.entry((ty.clone(), c[2].to_string())).or_insert(kind);
            }
        }
        OwnershipKinds { idx, usage, declared }
    }

    pub fn kind(&self, owner: &str, name: &str) -> Option<String> {
        for p in oi::parents(owner) {
            if let Some(kind) = self.declared.get(&(p, name.to_string())) {
                return Some(kind.to_string());
            }
        }
        if let Some((_, d)) = self.idx.decl(owner, name) {
            return Some(d.macro_name.clone());
        }
        self.usage.get(name).and_then(|k| k.iter().next()).map(|k| k.to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn chain_adds_implicit_roots() {
        assert_eq!(chain("/obj/item"), ["/datum", "/atom", "/atom/movable", "/obj", "/obj/item"]);
        assert_eq!(chain("/turf/x"), ["/datum", "/atom", "/turf", "/turf/x"]);
        assert_eq!(chain("/atom/movable"), ["/datum", "/atom", "/atom/movable"]);
        assert_eq!(chain("/datum/a"), ["/datum", "/datum/a"]);
        assert_eq!(chain("/client"), ["/client"]);
    }

    #[test]
    fn parse_reads_vars_blocks_and_latent() {
        let f = SourceFile::from_text(
            "code/a.dm",
            "/obj/thing\n\tlatent_safe = TRUE\n\tvar/datum/a = null\n\tvar/tmp\n\t\tobj/b\n\t\tlist/mob/c = list()\n\tvar/static/list/d\n/obj/thing/sub\n\tlatent_safe = FALSE\n",
        );
        let mut decls = HashMap::new();
        let mut latent = HashMap::new();
        parse_file(&f.rel, f.code(), &mut decls, &mut latent);
        let v = &decls["/obj/thing"];
        assert_eq!(v.len(), 4);
        assert!(v[0].saved() && v[0].holds_ref());
        assert!(!v[1].saved() && !v[2].saved() && v[2].is_list && v[2].vtype == "/mob");
        assert!(!v[3].saved());
        assert_eq!(latent["/obj/thing"], true);
        assert_eq!(latent["/obj/thing/sub"], false);
    }

    #[test]
    fn parse_inherited_latent_metadata_registration() {
        let f = SourceFile::from_text("code/a.dm", concat!(
            "/datum/type_metadata_registry/register_defaults()\n",
            "\tregister(/obj/thing, TYPE_META_LATENT_SAFE, TRUE)\n",
            "\tregister(/obj/thing/sub, TYPE_META_LATENT_SAFE, FALSE)\n",
            "\tregister(/obj/other, TYPE_META_SLOT_HOOKS, TRUE)\n",
            "/proc/unrelated()\n",
            "\tregister(/obj/ignored, TYPE_META_LATENT_SAFE, TRUE)\n"));
        let mut decls = HashMap::new();
        let mut latent = HashMap::new();
        parse_file(&f.rel, f.code(), &mut decls, &mut latent);
        assert_eq!(latent.len(), 2);
        assert!(latent["/obj/thing"]);
        assert!(!latent["/obj/thing/sub"]);
        let schema = Schema { latent, ..Schema::default() };
        assert!(schema.effective_latent("/obj/thing/child"));
        assert!(!schema.effective_latent("/obj/thing/sub/child"));
    }
}

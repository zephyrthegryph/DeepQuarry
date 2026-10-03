//! Reusing the semantic results across runs, so a one-file edit does not re-parse the tree.
//!
//! The full model (dreammaker over every included file) takes 7 to 8 s. What the semantic lints
//! derive from it depends on very little of it: the type, var and proc *structure* of the tree,
//! the bodies and declarations of the few procs the analysis actually walked (the **footprint**,
//! recorded by [`Sem`](super::Sem) as it answers), and which var names any body writes. So after a
//! full run this module stores, beside the lints' results:
//!
//! * per included file: its content key, a digest of the structure it contributes (the **shape**:
//!   every var declaration, proc definition and parameter list, no bodies, no line numbers), the
//!   var names its procs write, and whether it holds a preprocessor definition;
//! * the footprint, and the set of types with where each is located.
//!
//! A later run reuses the stored results when everything the model could have answered from is
//! unchanged:
//!
//! 1. the environment: `deepquarry.dme`, the declaration text ([`Decls::key`]), every
//!    `#include`d `.dm` the tree does not hold, and every file under `code/__defines/`;
//! 2. the file set; and every file whose content changed is
//! 3. outside the footprint, free of `#define`/`#undef`/`#include` (before and after), and its shape and
//!    written names, read back from a parse of just that file plus the defines, equal the stored
//!    ones, and the set of types it creates neither gains an unknown type nor loses one it was the
//!    location of.
//!
//! Any doubt is a miss, never a stale hit: a changed file the partial parse reads differently
//! (a macro from some other file, an `#ifdef`) simply fails step 3 and the full model runs.

use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::sync::{Arc, Mutex};

use serde::{Deserialize, Serialize};

use super::Sem;
use crate::lint::Sink;
use crate::tree::{Hash, Tree, CODE_DM};

const FILE: &str = "sem-cache.bin";

#[derive(Serialize, Deserialize, Default, Clone, PartialEq)]
pub struct FileFacts {
    pub fkey: Hash,
    pub shape: Hash,
    pub writes: Vec<String>,
    pub directive: bool,
    /// Digest of the file's single-token lines (`/datum/foo`, `foo`): a type header with no body defines a type
    /// and leaves no var or proc entry in the shape, so a change to these lines is treated as a structure change.
    pub bare: Hash,
}

#[derive(Serialize, Deserialize, Default, Clone)]
pub struct Record {
    pub stamp: String,
    pub env: Hash,
    pub files: BTreeMap<String, FileFacts>,
    /// type path -> the file the model located it in.
    pub type_loc: BTreeMap<String, String>,
    pub footprint: Vec<String>,
    pub sinks: BTreeMap<String, Sink>,
}

fn path() -> Option<std::path::PathBuf> {
    let _ = crate::cache::ENGINE_HASH;
    crate::incr::dir().map(|d| d.join(FILE))
}

fn load() -> Option<Record> {
    let stamp = crate::incr::stamp()?;
    let r: Record = bincode::deserialize(&std::fs::read(path()?).ok()?).ok()?;
    (r.stamp == stamp).then_some(r)
}

fn save(r: &Record) {
    let Some(p) = path() else { return };
    if let Some(dir) = p.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    if let Ok(bytes) = bincode::serialize(r) {
        let tmp = p.with_extension(format!("tmp{}", std::process::id()));
        if std::fs::write(&tmp, &bytes).is_ok() {
            let _ = std::fs::rename(&tmp, &p);
        } else {
            let _ = std::fs::remove_file(&tmp);
        }
    }
}

fn h128(bytes: &[u8]) -> Hash {
    u128::from_le_bytes(blake3::hash(bytes).as_bytes()[..16].try_into().unwrap())
}

/// A digest of the lines that may declare a type with no body (see [`FileFacts::bare`]).
fn bare_hash(f: &crate::tree::SourceFile) -> Hash {
    const STATEMENTS: &[&str] = &["return", "break", "continue", "else", "do", "sleep", "goto", "try", "catch", "finally", "spawn", "set", "new", "null"];
    let mut lines: Vec<String> = Vec::new();
    for line in f.code().lines() {
        let t = line.trim_end();
        let body = t.trim_start();
        if body.is_empty() || !body.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'/') {
            continue;
        }
        if !body.starts_with('/') && STATEMENTS.contains(&body) {
            continue;
        }
        lines.push(t.to_string());
    }
    lines.sort();
    h128(lines.join("
").as_bytes())
}

fn has_directive(text: &str) -> bool {
    crate::pat!(r"(?m)^[ \t]*#[ \t]*(?:define|undef|include)\b").is_match(text)
}

/// The `.dm` files `deepquarry.dme` includes, repo-relative.
fn included(tree: &Tree) -> Option<(Vec<String>, Hash)> {
    let text = std::fs::read_to_string(tree.root.join("deepquarry.dme")).ok()?;
    let mut out = Vec::new();
    for line in text.lines() {
        if let Some(rest) = line.strip_prefix("#include \"") {
            if let Some(p) = rest.strip_suffix('"') {
                let p = p.replace('\\', "/");
                if p.ends_with(".dm") {
                    out.push(p);
                }
            }
        }
    }
    Some((out, h128(text.as_bytes())))
}

/// The environment key and the per-file keys of every included file the tree holds.
fn environment(tree: &Tree) -> Option<(Hash, BTreeMap<String, Hash>)> {
    let (inc, dme) = included(tree)?;
    let decls = super::decls::Decls::get(tree);
    let mut files = BTreeMap::new();
    let mut ext: Vec<(String, Hash)> = Vec::new();
    for rel in inc {
        match tree.get(&rel) {
            Some(f) => {
                files.insert(rel, f.fkey);
            }
            None => ext.push((rel.clone(), h128(&std::fs::read(tree.root.join(&rel)).unwrap_or_default()))),
        }
    }
    ext.sort();
    let defines: Vec<(&str, Hash)> = tree.select(&CODE_DM).iter().filter(|f| f.rel.starts_with("code/__defines/")).map(|f| (f.rel.as_str(), f.fkey)).collect();
    let env = crate::incr::ctx_key(&(dme, decls.key, ext, defines));
    Some((env, files))
}

/// Per-file facts read off a model: shape digests, written names, and the types each file locates.
struct Collected {
    shape: HashMap<String, Vec<String>>,
    writes: HashMap<String, BTreeSet<String>>,
    types: HashMap<String, BTreeSet<String>>,
}

fn collect(sem: &Sem) -> Collected {
    let mut c = Collected { shape: HashMap::new(), writes: HashMap::new(), types: HashMap::new() };
    for ty in sem.objtree.iter_types() {
        let t = ty.get();
        let path = if t.path.is_empty() { "/".to_string() } else { t.path.clone() };
        if let Some(f) = sem.file_of(t.location) {
            c.types.entry(f.to_string()).or_default().insert(path.clone());
        }
        for (name, v) in &t.vars {
            if let Some(d) = &v.declaration {
                if let Some(f) = sem.file_of(d.location) {
                    let mut e = format!("V|{}|{}|{:?}|{}", path, name, d.var_type.flags, d.var_type.type_path.join("/"));
                    if name == "parent_type" {
                        e.push_str(&format!("|{:?}", v.value.constant));
                    }
                    c.shape.entry(f.to_string()).or_default().push(e);
                }
            } else if name == "parent_type" {
                if let Some(f) = sem.file_of(v.value.location) {
                    c.shape.entry(f.to_string()).or_default().push(format!("PT|{}|{:?}", path, v.value.constant));
                }
            }
        }
        for (name, tp) in &t.procs {
            if let Some(d) = &tp.declaration {
                if let Some(f) = sem.file_of(d.location) {
                    c.shape.entry(f.to_string()).or_default().push(format!("D|{}|{}|{:?}", path, name, d.kind));
                }
            }
            for v in &tp.value {
                if let Some(f) = sem.file_of(v.location) {
                    let params: Vec<String> = v.parameters.iter().map(|p| format!("{}:{:?}:{}", p.name, p.var_type.flags, p.var_type.type_path.join("/"))).collect();
                    c.shape.entry(f.to_string()).or_default().push(format!("P|{}|{}|{}|{}", path, name, params.join(","), v.code.is_some()));
                }
            }
        }
        for p in ty.iter_self_procs() {
            if p.is_builtin() {
                continue;
            }
            if let Some(f) = sem.file_of(p.get().location) {
                let w = super::reads::proc_writes(p);
                if !w.is_empty() {
                    c.writes.entry(f.to_string()).or_default().extend(w);
                }
            }
        }
    }
    for v in c.shape.values_mut() {
        v.sort();
    }
    c
}

fn shape_hash(entries: Option<&Vec<String>>) -> Hash {
    match entries {
        Some(v) => h128(v.join("\n").as_bytes()),
        None => 0,
    }
}

/// Is `rec` still the answer for this tree? Updates the stored content keys when it is.
fn miss(why: u32) -> Option<Record> {
    if std::env::var("DQ_ANALYZE_TRACE").is_ok() {
        eprintln!("analyze: sem record miss (reason {})", why);
    }
    None
}

fn validate(tree: &Tree) -> Option<Record> {
    let Some(mut rec) = load() else { return miss(0) };
    let (env, now) = environment(tree)?;
    if rec.env != env {
        return miss(1);
    }
    if rec.files.len() != now.len() || !rec.files.keys().eq(now.keys()) {
        return miss(2);
    }
    let changed: Vec<String> = now.iter().filter(|(rel, k)| rec.files[*rel].fkey != **k).map(|(rel, _)| rel.clone()).collect();
    if changed.is_empty() {
        return Some(rec);
    }
    let footprint: std::collections::HashSet<&str> = rec.footprint.iter().map(|s| s.as_str()).collect();
    for rel in &changed {
        if footprint.contains(rel.as_str()) || rel.starts_with("code/__defines/") || rec.files[rel].directive {
            return miss(3);
        }
        let f = tree.get(rel)?;
        if bare_hash(f) != rec.files[rel].bare {
            return miss(9);
        }
        if has_directive(f.text()) {
            return miss(4);
        }
    }
    let sem = Sem::build_partial(&tree.root, tree, &changed).ok()?;
    let got = collect(&sem);
    for rel in &changed {
        let old = &rec.files[rel];
        if shape_hash(got.shape.get(rel)) != old.shape {
            return miss(5);
        }
        let w: Vec<String> = got.writes.get(rel).map(|s| s.iter().cloned().collect()).unwrap_or_default();
        if w != old.writes {
            return miss(6);
        }
        let made = got.types.get(rel).cloned().unwrap_or_default();
        if std::env::var("DQ_ANALYZE_TRACE").is_ok() {
            eprintln!("analyze: sem partial {}: {} types made", rel, made.len());
        }
        if made.iter().any(|t| !rec.type_loc.contains_key(t)) {
            return miss(7);
        }
        if rec.type_loc.iter().any(|(t, loc)| loc == rel && !made.contains(t)) {
            return miss(8);
        }
    }
    for rel in &changed {
        rec.files.get_mut(rel)?.fkey = now[rel];
    }
    save(&rec);
    Some(rec)
}

/// The stored record when it is valid for this tree (memoized per run).
pub fn lookup(tree: &Tree) -> Option<Arc<Record>> {
    let r = tree.memo("sem/record", || validate(tree).map(Arc::new));
    r.as_ref().clone()
}

type Pending = Mutex<Option<Record>>;

fn pending(tree: &Tree) -> Arc<Pending> {
    tree.memo("sem/pending", || Mutex::new(None))
}

/// After a full analysis: the facts of every included file, to be completed by [`store`].
pub fn capture(tree: &Tree, sem: &Sem, footprint: Vec<String>) {
    let Some((env, now)) = environment(tree) else { return };
    let Some(stamp) = crate::incr::stamp() else { return };
    let col = collect(sem);
    let mut files = BTreeMap::new();
    for (rel, fkey) in now {
        let f = tree.get(&rel);
        files.insert(
            rel.clone(),
            FileFacts {
                fkey,
                shape: shape_hash(col.shape.get(&rel)),
                writes: col.writes.get(&rel).map(|s| s.iter().cloned().collect()).unwrap_or_default(),
                directive: f.map(|f| has_directive(f.text())).unwrap_or(true),
                bare: f.map(bare_hash).unwrap_or(0),
            },
        );
    }
    let type_loc: BTreeMap<String, String> = sem.type_loc.iter().map(|(k, v)| (k.clone(), v.clone())).collect();
    *pending(tree).lock().unwrap() = Some(Record { stamp, env, files, type_loc, footprint, sinks: BTreeMap::new() });
}

/// Records a lint's semantic result next to the facts captured by the run that computed it.
pub fn store(tree: &Tree, lint: &str, sink: &Sink) {
    let p = pending(tree);
    let mut g = p.lock().unwrap();
    if let Some(rec) = g.as_mut() {
        rec.sinks.insert(lint.to_string(), sink.clone());
        save(rec);
    }
}

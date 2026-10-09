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

use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};
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
    /// Digest of the comment-stripped, blank-line-free text: equal means the parse is unchanged but for line numbers.
    pub tokens: Hash,
    /// Digest of the file's single-token lines (`/datum/foo`, `foo`): a type header with no body defines a type
    /// and leaves no var or proc entry in the shape, so a change to these lines is treated as a structure change.
    pub bare: Hash,
}

#[derive(Serialize, Deserialize, Default, Clone)]
pub struct Record {
    pub stamp: String,
    pub env: Hash,
    pub files: BTreeMap<String, FileFacts>,
    /// type path -> the file the model located it in. Stored apart (`sem-types.bin`) and read only when a changed
    /// file needs a partial parse.
    #[serde(skip)]
    pub type_loc: BTreeMap<String, String>,
    pub footprint: Vec<String>,
    pub sinks: BTreeMap<String, Sink>,
    /// Generator name -> (text, diagnostics) of a generator that used the full model.
    pub gens: BTreeMap<String, GenCache>,
}

#[derive(Serialize, Deserialize, Default, Clone)]
pub struct GenCache {
    pub text: String,
    pub diags: Vec<(String, u32, String)>,
}

fn path() -> Option<std::path::PathBuf> {
    let _ = crate::cache::ENGINE_HASH;
    crate::incr::dir().map(|d| d.join(FILE))
}

fn types_path() -> Option<std::path::PathBuf> {
    crate::incr::dir().map(|d| d.join("sem-types.bin"))
}

fn load_types(stamp: &str, env: Hash) -> Option<BTreeMap<String, String>> {
    let (st, e, map): (String, Hash, Vec<(String, String)>) = crate::incr::de(&std::fs::read(types_path()?).ok()?).ok()?;
    (st == stamp && e == env).then(|| map.into_iter().collect())
}

fn save_types(stamp: &str, env: Hash, map: &BTreeMap<String, String>) {
    let Some(p) = types_path() else { return };
    let rows: Vec<(&String, &String)> = map.iter().collect();
    if let Ok(bytes) = crate::incr::ser(&(stamp, env, rows)) {
        let _ = std::fs::write(&p, bytes);
    }
}

fn load() -> Option<Record> {
    let stamp = crate::incr::stamp()?;
    let r: Record = crate::incr::de(&std::fs::read(path()?).ok()?).ok()?;
    (r.stamp == stamp).then_some(r)
}

fn save(r: &Record) {
    let Some(p) = path() else { return };
    if let Some(dir) = p.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    if let Ok(bytes) = crate::incr::ser(r) {
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
pub(crate) fn bare_hash(tree: &Tree, rel: &str) -> Hash {
    const STATEMENTS: &[&str] = &["return", "break", "continue", "else", "do", "sleep", "goto", "try", "catch", "finally", "spawn", "set", "new", "null"];
    let mut lines: Vec<String> = Vec::new();
    let code: String = match tree.get(rel) {
        Some(f) => f.code().text.clone(),
        None => crate::strip::code_only(&text_of(tree, rel)),
    };
    for line in code.lines() {
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

/// The text of an included file, from the tree or (a file no lint selected) from disk.
pub(crate) fn text_of(tree: &Tree, rel: &str) -> String {
    match tree.get(rel) {
        Some(f) => f.text().to_string(),
        None => tree.read_extra(rel).map(|t| t.as_ref().clone()).unwrap_or_default(),
    }
}

/// Digest of the text with comments removed, trailing space trimmed and blank lines dropped.
pub(crate) fn token_hash(tree: &Tree, rel: &str) -> Hash {
    let stripped = super::decls::strip_comments_keep_strings(&text_of(tree, rel));
    let mut out = String::with_capacity(stripped.len());
    for l in stripped.lines() {
        let t = l.trim_end();
        if !t.trim().is_empty() {
            out.push_str(t);
            out.push('\n');
        }
    }
    h128(out.as_bytes())
}

pub(crate) fn has_directive(text: &str) -> bool {
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

/// The environment key and the content hash of every included `.dm` (whether or not the tree holds
/// it, so the key does not depend on which lints this run selected).
pub(crate) fn environment(tree: &Tree) -> Option<(Hash, BTreeMap<String, Hash>)> {
    let (inc, dme) = included(tree)?;
    let decls = super::decls::Decls::get(tree);
    let mut files = BTreeMap::new();
    for rel in inc {
        let h = match tree.get(&rel) {
            Some(f) => f.hash,
            None => h128(&std::fs::read(tree.root.join(&rel)).unwrap_or_default()),
        };
        files.insert(rel, h);
    }
    let defines: Vec<(&str, Hash)> = tree.select(&CODE_DM).iter().filter(|f| f.rel.starts_with("code/__defines/")).map(|f| (f.rel.as_str(), f.hash)).collect();
    let env = crate::incr::ctx_key(&(dme, decls.key, defines));
    Some((env, files))
}

/// Per-file facts read off a model: shape digests, written names, and the types each file locates.
pub(crate) struct Collected {
    pub(crate) shape: HashMap<String, Vec<String>>,
    pub(crate) writes: HashMap<String, BTreeSet<String>>,
    pub(crate) types: HashMap<String, BTreeSet<String>>,
}

fn collect(sem: &Sem) -> Collected {
    collect_with(sem, true)
}

/// `with_writes` false skips the proc-body walk (the names each file's procs write), for a consumer that only needs the
/// structure (shapes and located types).
pub(crate) fn collect_with(sem: &Sem, with_writes: bool) -> Collected {
    let mut c = Collected { shape: HashMap::new(), writes: HashMap::new(), types: HashMap::new() };
    let mut procs: Vec<(dreammaker::objtree::ProcRef, &str)> = Vec::new();
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
                procs.push((p, f));
            }
        }
    }
    // The bodies of every proc, walked on plain threads (this runs under a memo init).
    if !with_writes {
        procs.clear();
    }
    let sets: Vec<HashSet<String>> = super::par_map(&procs, |(p, _)| super::reads::proc_writes(*p));
    for ((_, f), w) in procs.iter().zip(sets) {
        if !w.is_empty() {
            c.writes.entry(f.to_string()).or_default().extend(w);
        }
    }
    for v in c.shape.values_mut() {
        v.sort();
    }
    c
}

pub(crate) fn shape_hash(entries: Option<&Vec<String>>) -> Hash {
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
    }
    // A change that leaves the comment-stripped text alone (a comment, blank lines) cannot change what the
    // model derives from a file outside the footprint: no parse.
    let changed_tokens: Vec<(String, Hash)> = changed.iter().map(|rel| (rel.clone(), token_hash(tree, rel))).collect();
    let all_same = changed_tokens.iter().all(|(rel, t)| *t == rec.files[rel].tokens);
    if all_same {
        // Nothing to learn and nothing worth a 1 MB write: the next run finds the same changed files the same way
        // (a token hash each, no parse).
        for rel in &changed {
            rec.files.get_mut(rel)?.fkey = now[rel];
        }
        return Some(rec);
    }
    let changed: Vec<String> = changed_tokens.iter().filter(|(rel, t)| *t != rec.files[rel].tokens).map(|(rel, _)| rel.clone()).collect();
    let same_tokens: Vec<String> = changed_tokens.iter().filter(|(rel, t)| *t == rec.files[rel].tokens).map(|(rel, _)| rel.clone()).collect();
    for rel in &changed {
        if bare_hash(tree, rel) != rec.files[rel].bare {
            return miss(9);
        }
        if has_directive(&text_of(tree, rel)) {
            return miss(4);
        }
    }
    let Some(type_loc) = load_types(&rec.stamp, rec.env) else { return miss(10) };
    rec.type_loc = type_loc;
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
    for rel in changed.iter().chain(same_tokens.iter()) {
        let f = rec.files.get_mut(rel)?;
        f.fkey = now[rel];
        f.tokens = token_hash(tree, rel);
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

/// After a full analysis: the facts of every included file, to be completed by [`store`]. When the
/// stored record describes exactly this tree already (another consumer of the model ran first) its
/// results are kept and the footprint is widened by what this run consulted.
pub fn capture(tree: &Tree, sem: &Sem, footprint: Vec<String>) {
    let Some((env, now)) = environment(tree) else { return };
    let Some(stamp) = crate::incr::stamp() else { return };
    let same = |r: &Record| r.env == env && r.files.len() == now.len() && r.files.iter().all(|(k, f)| now.get(k) == Some(&f.fkey));
    if let Some(mut rec) = load().filter(|r| same(r)) {
        let mut fp: BTreeSet<String> = rec.footprint.iter().cloned().collect();
        fp.extend(footprint);
        rec.footprint = fp.into_iter().collect();
        *pending(tree).lock().unwrap() = Some(rec);
        return;
    }
    let col = collect(sem);
    let mut files = BTreeMap::new();
    for (rel, fkey) in now {
        files.insert(
            rel.clone(),
            FileFacts {
                fkey,
                shape: shape_hash(col.shape.get(&rel)),
                writes: col.writes.get(&rel).map(|s| s.iter().cloned().collect()).unwrap_or_default(),
                directive: has_directive(&text_of(tree, &rel)),
                bare: bare_hash(tree, &rel),
                tokens: token_hash(tree, &rel),
            },
        );
    }
    let type_loc: BTreeMap<String, String> = sem.type_loc.iter().map(|(k, v)| (k.clone(), v.clone())).collect();
    save_types(&stamp, env, &type_loc);
    *pending(tree).lock().unwrap() = Some(Record { stamp, env, files, type_loc: BTreeMap::new(), footprint, sinks: BTreeMap::new(), gens: BTreeMap::new() });
}

/// The stored output of a generator that used the full model, when the record is valid.
pub fn cached_gen(tree: &Tree, name: &str) -> Option<GenCache> {
    lookup(tree)?.gens.get(name).cloned()
}

/// Records a generator's output (after [`capture`] ran for the model it used).
pub fn store_gen(tree: &Tree, name: &str, g: GenCache) {
    let p = pending(tree);
    let mut guard = p.lock().unwrap();
    if let Some(rec) = guard.as_mut() {
        rec.gens.insert(name.to_string(), g);
        save(rec);
    }
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

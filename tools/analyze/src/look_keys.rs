//! `analyze look-keys`: the look plan.
//!
//! One TSV line per concrete type under /obj, /mob and /turf: `<type> TAB <key> TAB <probes>`.
//!
//! * `key` (16 hex chars of a blake3 digest) covers everything that can change the type's look rows: the initial values of
//!   the vars of the type and its ancestors, the CAPABILITIES/STAT declaration text of the chain, every proc in the type's
//!   draw closure, the icon sources the look can use, and a fixed engine salt (the presentation engine and the look pins).
//! * `probes` are the var names a state probe should write: the vars of the type (declared below the /obj, /mob or /turf
//!   base) whose name appears in the draw closure, or `*` ("unknown: scan every numeric var").
//!
//! The draw closure is an over-approximation by construction: it is never allowed to omit a proc that can affect the look.
//!
//! * Roots: every override up the chain of `update_icon`, `update_icon_state`, `update_overlays`, `on_update_icon`,
//!   `update_icon_overlays`, `draw`, `set_dir`, plus the procs the CAPABILITIES/STAT declarations of the chain name
//!   (`cx.handlers()`), plus every word of those declarations that names a proc (entry procs, `PROC_REF(x)`).
//! * Edges, per call `name(...)` in a closure proc: an unscoped or `src.` call resolves on the type chain (with the proc's own
//!   subtree when the proc was reached through another receiver); `x.name()` with a receiver of known declared type K
//!   resolves on K's chain and K's whole subtree (virtual dispatch); an unknown receiver reaches every proc of that name in
//!   the tree. Any identifier or string in a body that names a proc is a reference edge as well (`PROC_REF(x)`,
//!   `call(src, "x")`), so a callback is followed.
//! * Dynamic access that cannot be resolved (`vars[expr]`, `call(expr)(...)`) anywhere in the closure makes the probes `*`.
//!
//! Cost: the semantic parse (about 8 s cold) is skipped when no `.dm` file changed since the last run: the DM part of every
//! row is cached in the analyze cache directory, and only the icon sources are hashed again.
//!
//! Incremental: the cache also records, per row, its **footprint** (the procs of its closure, as a bitset over a table of the
//! procs some closure contains, each with the digest of its text; and the types of its chain, with the digest of the var values
//! each file assigns to each type) and, per included file, its structure facts (the shape digest, comment-free token digest,
//! bare type headers, directives and located types of `sem::incremental`). After an edit the plan is rebuilt from the cache
//! when every changed file left the structure alone (comment edits are ignored; a partial parse of the changed files must give
//! the same shape and the same types) and is not part of the salt, a `DECLARE_APPEARANCE` file or an `abstract_type` file.
//! A partial parse of just the changed files then says which closure procs changed their text and which types were assigned
//! different var values, and only the rows that hold one of those are recomputed (one semantic parse); the others are kept.
//! An edit to a proc no closure contains (most gameplay code) needs no parse of the whole tree at all. Any doubt (a changed
//! declaration, define, file set, structure, analyzer) is a full recompute, which is also what `--no-cache` and the tests do;
//! the tests compare the two.

use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::process::ExitCode;
use std::rc::Rc;

use dreammaker::ast::{Expression, Follow, Statement, Term};
use dreammaker::objtree::{ProcValue, TypeRef};
use serde::{Deserialize, Serialize};

use crate::sem::ast;
use crate::sem::decls::{strip_comments_keep_strings, Decls};
use crate::sem::hooks::{self, HandlerRef};
use crate::sem::incremental as inc;
use crate::sem::Sem;
use crate::tree::{Tree, CODE_DM};

/// Procs every closure starts from.
pub const ROOT_PROCS: &[&str] = &["update_icon", "update_icon_state", "update_overlays", "on_update_icon", "update_icon_overlays", "draw", "set_dir"];

/// Files whose contents are part of every key: only the code that draws (the appearance builder that applies a look and the
/// refresh path). Other engine files, the pin tests and the sweep harness do not change a drawn look, so editing them leaves
/// every key alone.
const SALT_FILES: &[&str] = &["code/datums/sys/appearance.dm", "code/engine/present/appearance_builder.dm"];
const SALT_DIRS: &[&str] = &[];
const SALT_PREFIXES: &[&str] = &[];
/// Procs whose defining files are part of the salt.
const SALT_PROCS: &[(&str, &str)] = &[("/atom", "update_icon"), ("/", "appearance_flush"), ("/obj", "update_icon"), ("/mob", "update_icon")];

/// A name with more definitions than this, called on a receiver of unknown type, reaches only the definitions on the type
/// chain and on the base types (not every definition in the tree). `--explain` lists the names this cut.
const ANY_CAP: usize = 8;
/// A call on a receiver of declared type reaches that type's chain and its subtree; a subtree with more definitions than
/// this contributes only the chain.
const SUBTREE_CAP: usize = 8;
/// The types whose procs every closure may reach through an unknown receiver.
const BASE_TYPES: &[&str] = &["/datum", "/atom", "/atom/movable", "/obj", "/mob", "/turf"];

const CACHE_VERSION: &str = "look-keys-v4";

/// A small multiplicative hasher for the model's integer-keyed tables (the closure walk does tens of millions of lookups;
/// SipHash was a third of its time). Not for anything that leaves the process.
#[derive(Default, Clone, Copy)]
struct Fx(u64);
const FX_K: u64 = 0x517c_c1b7_2722_0a95;
impl std::hash::Hasher for Fx {
    fn write(&mut self, bytes: &[u8]) {
        for b in bytes {
            self.0 = (self.0.rotate_left(5) ^ *b as u64).wrapping_mul(FX_K);
        }
    }
    fn write_u8(&mut self, i: u8) {
        self.0 = (self.0.rotate_left(5) ^ i as u64).wrapping_mul(FX_K);
    }
    fn write_u32(&mut self, i: u32) {
        self.0 = (self.0.rotate_left(5) ^ i as u64).wrapping_mul(FX_K);
    }
    fn write_u64(&mut self, i: u64) {
        self.0 = (self.0.rotate_left(5) ^ i).wrapping_mul(FX_K);
    }
    fn write_usize(&mut self, i: usize) {
        self.write_u64(i as u64);
    }
    fn finish(&self) -> u64 {
        self.0
    }
}
type FxMap<K, V> = HashMap<K, V, std::hash::BuildHasherDefault<Fx>>;
type FxSet<K> = HashSet<K, std::hash::BuildHasherDefault<Fx>>;

/// Cost accounting for `DQ_LOOK_TRACE`: nanoseconds and call counts per phase.
mod prof {
    use std::sync::atomic::{AtomicU64, Ordering};
    pub static NS: [AtomicU64; 8] = [const { AtomicU64::new(0) }; 8];
    pub static N: [AtomicU64; 8] = [const { AtomicU64::new(0) }; 8];
    pub const NAMES: [&str; 8] = ["analyze_proc", "closure: root setup", "own_vars", "declared_below+probes", "closure(incl.)", "closure: expansion loop", "closure: targets()", "closure: hashing"];
    pub fn add(slot: usize, t0: std::time::Instant) {
        NS[slot].fetch_add(t0.elapsed().as_nanos() as u64, Ordering::Relaxed);
        N[slot].fetch_add(1, Ordering::Relaxed);
    }
    pub fn report() {
        for i in 0..8 {
            eprintln!("look-keys: phase {:<24} {:>9.2?} over {} calls", NAMES[i], std::time::Duration::from_nanos(NS[i].load(Ordering::Relaxed)), N[i].load(Ordering::Relaxed));
        }
    }
}
const BASES: &[&str] = &["/obj", "/mob", "/turf"];
/// Subtrees whose look changes through something the closure cannot see: every numeric var is probed. The batons' state follows
/// `edge` and the other item flags (their look rows exist for every var written), which no draw proc of theirs reads.
const FULL_SCAN_TREES: &[&str] = &["/obj/item/melee/robotic/baton"];
const SKIP_DIRS: &[&str] = &["code/modules/unit_tests/", "code/tests/"];

/// One output line.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Row {
    pub ty: String,
    pub key: String,
    pub probes: String,
}

/// What `--explain` prints for one type.
#[derive(Clone, Debug, Default)]
pub struct Explain {
    pub closure: Vec<String>,
    pub probes: String,
    pub probe_reason: Vec<String>,
    pub icons: Vec<String>,
    pub dynamic: Option<String>,
    pub roots: Vec<String>,
    pub capped: Vec<String>,
}

pub struct Plan {
    pub rows: Vec<Row>,
    pub explain: Option<Explain>,
    /// How the DM part was obtained: "cached", "incremental: ...", "full" or "explain".
    pub mode: String,
}

#[derive(Serialize, Deserialize, Clone)]
pub struct CacheRow {
    ty: String,
    partial: Vec<u8>,
    icons: Vec<String>,
    probes: String,
}

/// The structure facts of one included file (see `sem::incremental::FileFacts`), plus the types it locates.
#[derive(Serialize, Deserialize, Default, Clone, PartialEq)]
struct FileRec {
    shape: u128,
    tokens: u128,
    bare: u128,
    directive: bool,
    made: Vec<String>,
    /// Per type, a digest of the var values this file assigns to it (see `var_digests`): an edit that changes the digest of a
    /// type moves the rows whose chain holds that type; an edit that changes none can only move rows through a proc.
    vars: BTreeMap<String, u128>,
}

/// A proc some closure contains: where it is (the file, its type, its name and its ordinal among that type's definitions of the name
/// in that file) and a digest of its text (parameters and body, locations stripped).
#[derive(Serialize, Deserialize, Clone, PartialEq, Eq, Hash, PartialOrd, Ord)]
struct ProcKey {
    file: String,
    owner: String,
    name: String,
    ord: u32,
}

#[derive(Serialize, Deserialize, Clone)]
struct ProcRec {
    key: ProcKey,
    text: u128,
}

fn bit_set(bits: &mut Vec<u8>, i: usize) {
    if bits.len() <= i / 8 {
        bits.resize(i / 8 + 1, 0);
    }
    bits[i / 8] |= 1 << (i % 8);
}

/// What the incremental path needs from the run that wrote the cache.
#[derive(Serialize, Deserialize, Default, Clone)]
struct Incr {
    /// `ENGINE_HASH` and `CACHE_VERSION` of the run that wrote it: a different engine may compute different rows.
    engine: String,
    /// `lk_env`: deepquarry.dme, the declaration markers and the defines.
    env: u128,
    /// Content hash of every `.dm` file the tree holds.
    hashes: Vec<(String, u128)>,
    /// Structure facts of the files the model includes.
    files: BTreeMap<String, FileRec>,
    /// Files whose contents are part of every key: any change recomputes everything.
    salt: Vec<String>,
    /// Files holding `DECLARE_APPEARANCE` or `abstract_type` -> `special_digest`: a change to what they declare can add or
    /// remove rows or marker text the model does not see, so it recomputes everything; an edit elsewhere in them does not.
    special: BTreeMap<String, u128>,
    /// The procs some closure contains.
    procs: Vec<ProcRec>,
    /// The closures rows use, as bitsets over `procs`.
    closures: Vec<Vec<u8>>,
    /// Parallel to `rows`: the index into `closures`.
    foot: Vec<u32>,
    /// Per type of any row's chain: its parent.
    types: BTreeMap<String, Option<String>>,
    /// The `DECLARE_APPEARANCE` declarations of the whole tree (no changed file may hold one on the incremental path, so
    /// they stay valid and the tree need not be scanned again).
    appearance: Vec<(String, String, String)>,
}

#[derive(Serialize, Deserialize)]
struct CacheFile {
    key: Vec<u8>,
    rows: Vec<CacheRow>,
    incr: Option<Incr>,
}

// ---------------------------------------------------------------------------------------------------------------------
// text helpers

/// Comment-stripped, whitespace-collapsed source text (so reflowing and commenting do not change a hash).
pub fn normalize_source(text: &str) -> String {
    let stripped = strip_comments_keep_strings(text);
    let mut out = String::with_capacity(stripped.len() / 2);
    for part in stripped.split_whitespace() {
        if !out.is_empty() {
            out.push(' ');
        }
        out.push_str(part);
    }
    out
}

/// `format!("{:?}")` of an AST node with its source locations removed (a moved definition keeps its hash).
fn strip_locations(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut rest = s;
    while let Some(i) = rest.find("Location { file:") {
        out.push_str(&rest[..i]);
        match rest[i..].find('}') {
            Some(j) => rest = &rest[i + j + 1..],
            None => {
                rest = "";
                break;
            }
        }
    }
    out.push_str(rest);
    out
}

/// Every quoted string of a Debug rendering: identifiers, field names, call names and string literals alike.
fn quoted_tokens(s: &str) -> BTreeSet<String> {
    let b = s.as_bytes();
    let mut out = BTreeSet::new();
    let mut i = 0;
    while i < b.len() {
        if b[i] == b'"' {
            let mut j = i + 1;
            let mut cur: Vec<u8> = Vec::new();
            while j < b.len() && b[j] != b'"' {
                if b[j] == b'\\' && j + 1 < b.len() {
                    j += 1;
                }
                cur.push(b[j]);
                j += 1;
            }
            if let Ok(t) = String::from_utf8(cur) {
                if !t.is_empty() {
                    out.insert(t);
                }
            }
            i = j + 1;
        } else {
            i += 1;
        }
    }
    out
}

fn is_ident(s: &str) -> bool {
    let mut c = s.chars();
    matches!(c.next(), Some(f) if f.is_ascii_alphabetic() || f == '_') && c.all(|c| c.is_ascii_alphanumeric() || c == '_')
}

fn words(text: &str) -> BTreeSet<String> {
    let mut out = BTreeSet::new();
    let mut cur = String::new();
    for c in text.chars().chain(std::iter::once(' ')) {
        if c.is_ascii_alphanumeric() || c == '_' {
            cur.push(c);
        } else if !cur.is_empty() {
            if is_ident(&cur) {
                out.insert(cur.clone());
            }
            cur.clear();
        }
    }
    out
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{:02x}", b)).collect()
}

fn digest(parts: &[&[u8]]) -> [u8; 32] {
    let mut h = blake3::Hasher::new();
    for p in parts {
        h.update(&(p.len() as u64).to_le_bytes());
        h.update(p);
    }
    *h.finalize().as_bytes()
}

// ---------------------------------------------------------------------------------------------------------------------
// the model

#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
enum Kind {
    /// An unscoped or `src.` call.
    Src,
    /// A receiver of declared type (index into `types`).
    Typed(u32),
    /// A receiver of unknown type.
    Any,
}

struct PDef<'a> {
    owner: u32,
    name: &'a str,
    idx: usize,
    val: &'a ProcValue,
}

#[derive(Default)]
struct Info {
    hash: [u8; 32],
    tokens: BTreeSet<String>,
    edges: Vec<(String, Kind, u8)>,
    /// Digest of the proc's parameters and body, locations stripped (no owner, name or ordinal).
    text_hash: u128,
    /// `edges` interned in the model's edge table, those whose name has no definition anywhere dropped (they reach nothing).
    eids: Vec<u32>,
    dynamic: Vec<String>,
    icons: Vec<String>,
    /// Defined in an engine directory: part of the closure (hashed) but never expanded, as the reads walk treats it.
    opaque: bool,
}

struct Closure {
    /// pdef ids, sorted.
    ids: Vec<u32>,
    bits: Vec<u64>,
    digest: [u8; 32],
    icons: BTreeSet<String>,
    dynamic: Option<String>,
    roots: Vec<String>,
}

impl Closure {
    fn has(&self, id: u32) -> bool {
        self.bits.get((id / 64) as usize).is_some_and(|w| w >> (id % 64) & 1 == 1)
    }
}

struct Model<'a> {
    sem: &'a Sem,
    types: Vec<TypeRef<'a>>,
    paths: Vec<String>,
    tindex: HashMap<String, u32>,
    parent: Vec<Option<u32>>,
    pdefs: Vec<PDef<'a>>,
    own: FxMap<(u32, u32), (u32, u32)>,
    own_proc_count: Vec<u32>,
    by_name: FxMap<&'a str, u32>,
    /// proc name id -> its definitions (pdef ids, ascending).
    by_nid: Vec<Vec<u32>>,
    names: Vec<&'a str>,
    /// Distinct (name, receiver, flags) call edges seen so far: (name id, receiver, flags).
    edge_ids: FxMap<(String, Kind, u8), u32>,
    edge_tab: Vec<(u32, Kind, u8)>,
    any_cache: FxMap<u32, Rc<Vec<u32>>>,
    why_on: bool,

    infos: Vec<Option<Rc<Info>>>,
    varnames: HashSet<String>,
    inv: HashMap<String, Vec<u32>>,
    dispatch_cache: FxMap<(u32, u32), Rc<Vec<u32>>>,
    // per type declarations
    handler_roots: HashMap<u32, Vec<(String, Option<String>)>>,
    marker_words: HashMap<u32, BTreeSet<String>>,
    marker_hash: HashMap<u32, Vec<[u8; 32]>>,
    closures: HashMap<u32, Rc<Closure>>,
    capped: BTreeSet<String>,
    entry_procs: HashSet<String>,
    decl_roots: HashMap<u32, BTreeSet<String>>,
    var_hash: Vec<Option<([u8; 32], BTreeSet<String>)>>,
}

impl<'a> Model<'a> {
    fn new(sem: &'a Sem, decls: &Decls, handlers: &[HandlerRef], appearance: &[(String, String, String)]) -> Model<'a> {
        let mut raw: Vec<TypeRef<'a>> = sem.objtree.iter_types().collect();
        let path_of = |t: &TypeRef<'a>| if t.get().path.is_empty() { "/".to_string() } else { t.get().path.clone() };
        raw.sort_by_key(|t| path_of(t));
        let paths: Vec<String> = raw.iter().map(path_of).collect();
        let tindex: HashMap<String, u32> = paths.iter().enumerate().map(|(i, p)| (p.clone(), i as u32)).collect();
        let mut parent = vec![None; raw.len()];
        for (i, t) in raw.iter().enumerate() {
            if let Some(p) = t.parent_type() {
                if let Some(pi) = tindex.get(&path_of(&p)) {
                    parent[i] = Some(*pi);
                }
            }
        }
        let mut pdefs: Vec<PDef<'a>> = Vec::new();
        let mut own: FxMap<(u32, u32), (u32, u32)> = FxMap::default();
        let mut own_proc_count = vec![0u32; raw.len()];
        let mut by_name: FxMap<&'a str, u32> = FxMap::default();
        let mut by_nid: Vec<Vec<u32>> = Vec::new();
        let mut proc_names: Vec<&'a str> = Vec::new();
        for (ti, t) in raw.iter().enumerate() {
            let mut names: Vec<(&'a String, &'a dreammaker::objtree::TypeProc)> = t.get().procs.iter().collect();
            names.sort_by(|a, b| a.0.cmp(b.0));
            for (name, tp) in names {
                // A builtin or a bodiless declaration draws nothing.
                if tp.value.is_empty() || tp.value.iter().all(|v| v.code.is_none()) {
                    continue;
                }
                let start = pdefs.len() as u32;
                let nid = *by_name.entry(name.as_str()).or_insert_with(|| {
                    proc_names.push(name.as_str());
                    by_nid.push(Vec::new());
                    (proc_names.len() - 1) as u32
                });
                for (idx, val) in tp.value.iter().enumerate() {
                    by_nid[nid as usize].push(pdefs.len() as u32);
                    pdefs.push(PDef { owner: ti as u32, name: name.as_str(), idx, val });
                }
                own.insert((ti as u32, nid), (start, tp.value.len() as u32));
                own_proc_count[ti] += tp.value.len() as u32;
            }
        }
        let mut varnames = HashSet::new();
        for t in &raw {
            for (n, v) in &t.get().vars {
                if v.declaration.is_some() {
                    varnames.insert(n.clone());
                }
            }
        }
        let mut handler_roots: HashMap<u32, Vec<(String, Option<String>)>> = HashMap::new();
        for h in handlers {
            // An op's effects, requirements and questions run when a player or an AI chooses; they are not part of a redraw.
            if matches!(h.ctx, hooks::Ctx::Op | hooks::Ctx::Request) {
                continue;
            }
            if h.cap_proc {
                // The proc is on the capability datum; every holder type that names it follows it there.
                if let Some(oi) = tindex.get(&h.owner) {
                    handler_roots.entry(*oi).or_default().push((h.proc.clone(), Some(h.cap_type.clone())));
                }
            } else if let Some(oi) = tindex.get(&h.owner) {
                handler_roots.entry(*oi).or_default().push((h.proc.clone(), None));
            }
        }
        let entry_procs: HashSet<String> = decls.markers_named(crate::sem::decls::ENTRY_PROC).filter_map(|m| m.args.first().cloned()).collect();
        let mut marker_words: HashMap<u32, BTreeSet<String>> = HashMap::new();
        let mut marker_hash: HashMap<u32, Vec<[u8; 32]>> = HashMap::new();
        for m in &decls.markers {
            if let Some(oi) = m.args.first().and_then(|a| tindex.get(a.trim())) {
                marker_words.entry(*oi).or_default().extend(words(&m.body));
                marker_hash.entry(*oi).or_default().push(digest(&[m.name.as_bytes(), normalize_source(&m.body).as_bytes()]));
            }
        }
        let mut decl_roots: HashMap<u32, BTreeSet<String>> = HashMap::new();
        for (path, name, body) in appearance {
            if let Some(oi) = tindex.get(path.as_str()) {
                let ws = words(body);
                marker_words.entry(*oi).or_default().extend(ws.iter().cloned());
                decl_roots.entry(*oi).or_default().extend(ws.into_iter().filter(|w| by_name.contains_key(w.as_str())));
                marker_hash.entry(*oi).or_default().push(digest(&[name.as_bytes(), normalize_source(body).as_bytes()]));
            }
        }
        for v in marker_hash.values_mut() {
            v.sort();
        }
        let n = pdefs.len();
        let nt = raw.len();
        Model {
            sem,
            types: raw,
            paths,
            tindex,
            parent,
            pdefs,
            own,
            own_proc_count,
            by_name,
            by_nid,
            names: proc_names,
            edge_ids: FxMap::default(),
            edge_tab: Vec::new(),
            any_cache: FxMap::default(),
            why_on: std::env::var("DQ_LOOK_WHY").is_ok(),

            infos: vec![None; n],
            varnames,
            inv: HashMap::new(),
            dispatch_cache: FxMap::default(),
            handler_roots,
            marker_words,
            marker_hash,
            closures: HashMap::new(),
            capped: BTreeSet::new(),
            entry_procs,
            decl_roots,
            var_hash: vec![None; nt],
        }
    }

    fn chain(&self, t: u32) -> Vec<u32> {
        let mut out = vec![t];
        let mut cur = t;
        while let Some(p) = self.parent[cur as usize] {
            out.push(p);
            cur = p;
            if out.len() > 64 {
                break;
            }
        }
        out
    }

    fn is_desc(&self, t: u32, of: u32) -> bool {
        let mut cur = Some(t);
        let mut n = 0;
        while let Some(c) = cur {
            if c == of {
                return true;
            }
            cur = self.parent[c as usize];
            n += 1;
            if n > 64 {
                break;
            }
        }
        false
    }

    fn chain_defs(&self, chain: &[u32], name: &str) -> Vec<u32> {
        match self.by_name.get(name) {
            Some(nid) => self.chain_defs_id(chain, *nid),
            None => Vec::new(),
        }
    }

    fn chain_defs_id(&self, chain: &[u32], nid: u32) -> Vec<u32> {
        let mut out = Vec::new();
        for t in chain {
            if let Some((s, n)) = self.own.get(&(*t, nid)) {
                out.extend(*s..*s + *n);
            }
        }
        out
    }

    /// The definitions of `name` a call on an object of declared type `k` may reach: k's chain and k's whole subtree.
    fn dispatch(&mut self, k: u32, name: &str) -> Rc<Vec<u32>> {
        match self.by_name.get(name).copied() {
            Some(nid) => self.dispatch_id(k, nid),
            None => Rc::new(Vec::new()),
        }
    }

    fn dispatch_id(&mut self, k: u32, nid: u32) -> Rc<Vec<u32>> {
        if let Some(v) = self.dispatch_cache.get(&(k, nid)) {
            return v.clone();
        }
        let chain = self.chain(k);
        let mut out = self.chain_defs_id(&chain, nid);
        let mut below: Vec<u32> = Vec::new();
        for id in &self.by_nid[nid as usize] {
            let o = self.pdefs[*id as usize].owner;
            if o != k && self.is_desc(o, k) {
                below.push(*id);
            }
        }
        if below.len() > SUBTREE_CAP {
            self.capped.insert(format!("{} on {} ({} definitions in its subtree; chain only)", self.names[nid as usize], self.paths[k as usize], below.len()));
        } else {
            out.extend(below);
        }
        out.sort_unstable();
        out.dedup();
        let rc = Rc::new(out);
        self.dispatch_cache.insert((k, nid), rc.clone());
        rc
    }

    /// What a call on an unknown receiver reaches besides the type chain: every definition of the name when there are few,
    /// else the base types' only. Independent of the type being closed, so computed once per name.
    fn any_defs(&mut self, nid: u32) -> Rc<Vec<u32>> {
        if let Some(v) = self.any_cache.get(&nid) {
            return v.clone();
        }
        let all = &self.by_nid[nid as usize];
        let out: Vec<u32> = if all.len() <= ANY_CAP {
            all.clone()
        } else {
            // Too common to follow everywhere: the base types only.
            self.capped.insert(format!("{} on an unknown receiver ({} definitions; type chain and base types only)", self.names[nid as usize], all.len()));
            let mut v = Vec::new();
            for b in BASE_TYPES {
                if let Some(bi) = self.tindex.get(*b) {
                    if let Some((st, n)) = self.own.get(&(*bi, nid)) {
                        v.extend(*st..*st + *n);
                    }
                }
            }
            v
        };
        let rc = Rc::new(out);
        self.any_cache.insert(nid, rc.clone());
        rc
    }

    fn known_type(&self, path: &str) -> Option<u32> {
        self.tindex.get(path).copied()
    }

    fn info(&mut self, id: u32) -> Rc<Info> {
        if let Some(i) = &self.infos[id as usize] {
            return i.clone();
        }
        let mut info = self.analyze_proc(id);
        let mut eids: Vec<u32> = Vec::with_capacity(info.edges.len());
        for (name, kind, flags) in &info.edges {
            // A name nothing defines reaches nothing, whatever the receiver.
            let Some(nid) = self.by_name.get(name.as_str()).copied() else { continue };
            let key = (name.clone(), kind.clone(), *flags);
            let eid = match self.edge_ids.get(&key) {
                Some(e) => *e,
                None => {
                    let e = self.edge_tab.len() as u32;
                    self.edge_tab.push((nid, kind.clone(), *flags));
                    self.edge_ids.insert(key, e);
                    e
                }
            };
            eids.push(eid);
        }
        info.eids = eids;
        let info = Rc::new(info);
        for t in &info.tokens {
            if self.varnames.contains(t) || (t.starts_with("set_") && self.varnames.contains(&t[4..])) {
                self.inv.entry(t.clone()).or_default().push(id);
            }
        }
        self.infos[id as usize] = Some(info.clone());
        info
    }

    fn analyze_proc(&self, id: u32) -> Info {
        let t_prof = std::time::Instant::now();
        let r = self.analyze_proc_inner(id);
        prof::add(0, t_prof);
        r
    }

    fn analyze_proc_inner(&self, id: u32) -> Info {
        let pd = &self.pdefs[id as usize];
        let owner_path = &self.paths[pd.owner as usize];
        let text = strip_locations(&format!("{:?}|{:?}", pd.val.parameters, pd.val.code));
        let hash = digest(&[owner_path.as_bytes(), pd.name.as_bytes(), &(pd.idx as u64).to_le_bytes(), text.as_bytes()]);
        let text_hash = u128::from_le_bytes(blake3::hash(text.as_bytes()).as_bytes()[..16].try_into().unwrap());
        let tokens = quoted_tokens(&text);
        let icons = tokens.iter().filter(|t| t.ends_with(".dmi")).cloned().collect();
        let mut locals: HashMap<String, Option<String>> = HashMap::new();
        for p in pd.val.parameters.iter() {
            let ty = type_string(&p.var_type.type_path);
            note_local(&mut locals, &p.name, ty);
        }
        if let Some(code) = &pd.val.code {
            collect_locals(code, &mut locals);
        }
        let mut edges: BTreeSet<(String, Kind, u8)> = BTreeSet::new();
        let mut stmt_set: HashSet<*const Expression> = HashSet::new();
        if let Some(code) = &pd.val.code {
            collect_stmt_exprs(code, &mut stmt_set);
        }
        let mut dynamic: Vec<String> = Vec::new();
        let mut visit = |e: &Expression| self.visit_expr(e, pd, owner_path, &locals, &stmt_set, &mut edges, &mut dynamic);
        if let Some(code) = &pd.val.code {
            ast::walk_block(code, &mut |e, _| visit(e));
        }
        for p in pd.val.parameters.iter() {
            if let Some(d) = &p.default {
                ast::walk_expr(d, &mut |e| visit(e));
            }
        }
        // A token that names a proc is a reference (`PROC_REF(x)`, `call(src, "x")`, a callback list).
        for t in &tokens {
            if is_ident(t) && self.by_name.contains_key(t.as_str()) {
                edges.insert((t.clone(), Kind::Src, 0));
            }
        }
        dynamic.sort();
        dynamic.dedup();
        let opaque = self.sem.file_of(pd.val.location).is_some_and(|f| crate::sem::handlers::OPAQUE_DIRS.iter().any(|d| f.starts_with(d)));
        if opaque {
            return Info { hash, text_hash, tokens: BTreeSet::new(), edges: Vec::new(), eids: Vec::new(), dynamic: Vec::new(), icons: Vec::new(), opaque };
        }
        Info { hash, text_hash, tokens, edges: edges.into_iter().collect(), eids: Vec::new(), dynamic, icons, opaque }
    }

    fn visit_expr(&self, e: &Expression, pd: &PDef<'a>, owner_path: &str, locals: &HashMap<String, Option<String>>, stmt_set: &HashSet<*const Expression>, edges: &mut BTreeSet<(String, Kind, u8)>, dynamic: &mut Vec<String>) {
        let Expression::Base { term, follow } = e else { return };
        let is_stmt = stmt_set.contains(&(e as *const Expression));
        let flags = |args: &[Expression], last: bool| -> u8 {
            let mut f = 0u8;
            if is_stmt && last {
                f |= 1;
            }
            for a in args {
                ast::walk_expr(a, &mut |x| {
                    if ast::as_ident(x) == Some("src") {
                        f |= 2;
                    }
                });
            }
            f
        };
        #[derive(Clone)]
        enum Recv {
            Src,
            Typed(u32),
            Unknown,
        }
        let typed = |decl: &str| -> Recv {
            match self.known_type(decl) {
                Some(k) => Recv::Typed(k),
                None => Recv::Unknown,
            }
        };
        let var_recv = |owner: &str, name: &str| -> Recv {
            match self.sem.var_decl(owner, name) {
                Some(sig) if sig.is_object() => typed(&sig.declared),
                _ => Recv::Unknown,
            }
        };
        let mut is_vars = false;
        let mut cur = match &term.elem {
            Term::Ident(n) => {
                if n == "vars" {
                    is_vars = true;
                }
                if n == "src" {
                    Recv::Src
                } else if let Some(l) = locals.get(n.as_str()) {
                    match l {
                        Some(t) => typed(t),
                        None => Recv::Unknown,
                    }
                } else if n == "usr" {
                    typed("/mob")
                } else {
                    var_recv(owner_path, n)
                }
            }
            Term::Call(name, args) => {
                edges.insert((name.to_string(), Kind::Src, flags(args, follow.is_empty())));
                Recv::Unknown
            }
            Term::GlobalCall(name, args) => {
                edges.insert((name.to_string(), Kind::Src, flags(args, follow.is_empty())));
                Recv::Unknown
            }
            Term::ParentCall(_) => {
                edges.insert((pd.name.to_string(), Kind::Src, 0));
                Recv::Unknown
            }
            Term::DynamicCall(a, _) => {
                let name_arg = if a.len() >= 2 { a.last() } else { a.first() };
                let literal = name_arg.is_some_and(is_literal_proc_name);
                if !literal {
                    dynamic.push("call(expr)(...)".to_string());
                }
                Recv::Unknown
            }
            Term::Locate { .. } | Term::Input { .. } => Recv::Unknown,
            _ => Recv::Unknown,
        };
        let last_idx = follow.len().wrapping_sub(1);
        for (fi, f) in follow.iter().enumerate() {
            match &f.elem {
                Follow::Field(_, name) => {
                    is_vars = { let n: &str = name; n == "vars" };
                    cur = match &cur {
                        Recv::Src => var_recv(owner_path, name),
                        Recv::Typed(k) => var_recv(&self.paths[*k as usize], name),
                        Recv::Unknown => Recv::Unknown,
                    };
                }
                Follow::Call(_, name, args) => {
                    let kind = match &cur {
                        Recv::Src => Kind::Src,
                        Recv::Typed(k) => Kind::Typed(*k),
                        Recv::Unknown => Kind::Any,
                    };
                    edges.insert((name.to_string(), kind, flags(args, fi == last_idx)));
                    cur = Recv::Unknown;
                    is_vars = false;
                }
                Follow::Index(_, ix) => {
                    if is_vars && !is_string_literal(ix) {
                        dynamic.push("vars[expr]".to_string());
                    }
                    cur = Recv::Unknown;
                    is_vars = false;
                }
                Follow::ProcReference(name) => {
                    edges.insert((name.to_string(), Kind::Any, 0));
                    cur = Recv::Unknown;
                    is_vars = false;
                }
                _ => {
                    cur = Recv::Unknown;
                    is_vars = false;
                }
            }
        }
    }

    /// The edges' targets: (definition, whether it runs with `src` = the type being closed).
    ///
    /// The look of a type is its own appearance, so what runs on `src` is followed exactly (the type chain). A call whose
    /// result is dropped, on another object, with `src` not passed to it, changes that object and not this one: it is not
    /// followed (unless the receiver may be `src` itself, which reaches the type chain only). Every other call on another
    /// object is followed to that object's type chain and, when small, its subtree.
    fn targets(&mut self, eid: u32, t_ctx: bool, from_owner: u32, chain: &[u32], out: &mut Vec<(u32, bool)>) {
        let (nid, kind, flags) = self.edge_tab[eid as usize].clone();
        let other_only = flags & 1 != 0 && flags & 2 == 0;
        match kind {
            Kind::Src if t_ctx => out.extend(self.chain_defs_id(chain, nid).into_iter().map(|d| (d, true))),
            Kind::Src => {
                if !other_only {
                    out.extend(self.dispatch_id(from_owner, nid).iter().map(|d| (*d, false)));
                }
            }
            Kind::Typed(k) => {
                if chain.contains(&k) {
                    // The receiver may be `src` itself.
                    out.extend(self.chain_defs_id(chain, nid).into_iter().map(|d| (d, true)));
                }
                if !other_only {
                    out.extend(self.dispatch_id(k, nid).iter().map(|d| (*d, false)));
                }
            }
            Kind::Any => {
                out.extend(self.chain_defs_id(chain, nid).into_iter().map(|d| (d, true)));
                if !other_only {
                    out.extend(self.any_defs(nid).iter().map(|d| (*d, false)));
                }
            }
        }
    }

    fn closure(&mut self, t: u32) -> Rc<Closure> {
        if let Some(c) = self.closures.get(&t) {
            return c.clone();
        }
        // A type that adds no procs and no declarations draws exactly as its parent does.
        if let Some(p) = self.parent[t as usize] {
            if self.own_proc_count[t as usize] == 0 && !self.handler_roots.contains_key(&t) && !self.marker_words.contains_key(&t) {
                let c = self.closure(p);
                self.closures.insert(t, c.clone());
                return c;
            }
        }
        let t_roots = std::time::Instant::now();
        let chain = self.chain(t);
        let mut root_names: BTreeSet<String> = ROOT_PROCS.iter().map(|s| s.to_string()).collect();
        let mut cap_roots: BTreeSet<(String, String)> = BTreeSet::new();
        for c in &chain {
            if let Some(hs) = self.handler_roots.get(c) {
                for (p, cap) in hs {
                    match cap {
                        None => {
                            root_names.insert(p.clone());
                        }
                        Some(ct) => {
                            cap_roots.insert((ct.clone(), p.clone()));
                        }
                    }
                }
            }
            if let Some(ws) = self.decl_roots.get(c) {
                root_names.extend(ws.iter().cloned());
            }
            if let Some(ws) = self.marker_words.get(c) {
                // A word of a declaration that names a global proc is an entry proc (`cover()`); other words are keywords.
                for w in ws {
                    if let Some(root) = self.tindex.get("/") {
                        if self.entry_procs.contains(w) && self.by_name.get(w.as_str()).is_some_and(|nid| self.own.contains_key(&(*root, *nid))) {
                            root_names.insert(w.clone());
                        }
                    }
                }
            }
        }
        let words = self.pdefs.len() / 64 + 1;
        // Visited definitions, by the context they run in: `vis_src` with `src` = the type being closed, `vis_other` not.
        let mut vis_src = vec![0u64; words];
        let mut vis_other = vec![0u64; words];
        let mut why: HashMap<u32, (Option<u32>, String)> = HashMap::new();
        let mut done_edges: FxSet<(u32, bool, u32)> = FxSet::default();
        let mut stack: Vec<(u32, bool)> = Vec::new();
        let mut roots_found: Vec<String> = Vec::new();
        let mut mark = |src_ctx: bool, d: u32| -> bool {
            let set = if src_ctx { &mut vis_src } else { &mut vis_other };
            let (w, b) = ((d / 64) as usize, d % 64);
            if set[w] >> b & 1 == 1 {
                return false;
            }
            set[w] |= 1 << b;
            true
        };
        for name in &root_names {
            let defs = self.chain_defs(&chain, name);
            if !defs.is_empty() {
                roots_found.push(name.clone());
            }
            for d in defs {
                if mark(true, d) {
                    stack.push((d, true));
                    if self.why_on {
                        why.entry(d).or_insert((None, format!("root {}", name)));
                    }
                }
            }
        }
        for (ct, p) in &cap_roots {
            if let Some(k) = self.known_type(ct) {
                for d in self.dispatch(k, p).iter() {
                    if mark(false, *d) {
                        stack.push((*d, false));
                    }
                }
                roots_found.push(format!("{}::{}", ct, p));
            }
        }
        prof::add(1, t_roots);
        let t_loop = std::time::Instant::now();
        let mut defs: Vec<(u32, bool)> = Vec::new();
        while let Some((id, t_ctx)) = stack.pop() {
            let info = self.info(id);
            if info.opaque {
                continue;
            }
            let from_owner = self.pdefs[id as usize].owner;
            // One expansion per distinct edge: every later occurrence reaches the same definitions.
            let ctx_owner = if !t_ctx { from_owner } else { u32::MAX };
            for eid in &info.eids {
                if !done_edges.insert((*eid, t_ctx, ctx_owner)) {
                    continue;
                }
                defs.clear();
                self.targets(*eid, t_ctx, from_owner, &chain, &mut defs);
                for (d, ctx) in defs.iter() {
                    if mark(*ctx, *d) {
                        stack.push((*d, *ctx));
                        if self.why_on {
                            let (nid, kind, _) = &self.edge_tab[*eid as usize];
                            why.entry(*d).or_insert((Some(id), format!("{} {:?}", self.names[*nid as usize], kind)));
                        }
                    }
                }
            }
        }
        prof::add(5, t_loop);
        let t_hash = std::time::Instant::now();
        let mut ids: Vec<u32> = Vec::new();
        for w in 0..words {
            let mut word = vis_src[w] | vis_other[w];
            while word != 0 {
                let b = word.trailing_zeros();
                ids.push((w as u32) * 64 + b);
                word &= word - 1;
            }
        }
        let mut bits = vec![0u64; words];
        let mut h = blake3::Hasher::new();
        let mut icons = BTreeSet::new();
        let mut first_dynamic: Option<(u32, String)> = None;
        for id in &ids {
            bits[(*id / 64) as usize] |= 1 << (*id % 64);
            let info = self.info(*id);
            h.update(&info.hash);
            icons.extend(info.icons.iter().cloned());
            if first_dynamic.is_none() {
                if let Some(d) = info.dynamic.first() {
                    let pd = &self.pdefs[*id as usize];
                    first_dynamic = Some((*id, format!("{}::{}: {}", self.paths[pd.owner as usize], pd.name, d)));
                }
            }
        }
        prof::add(7, t_hash);
        if let Ok(w) = std::env::var("DQ_LOOK_WHY") {
            for id in &ids {
                let pd = &self.pdefs[*id as usize];
                if pd.name == w {
                    let mut cur = Some(*id);
                    let mut lines = Vec::new();
                    while let Some(c) = cur {
                        let p = &self.pdefs[c as usize];
                        let (par, how) = why.get(&c).cloned().unwrap_or((None, String::new()));
                        lines.push(format!("{}::{} via {}", self.paths[p.owner as usize], p.name, how));
                        cur = par;
                    }
                    eprintln!("look-keys: why {} in closure of {}:
  {}", w, self.paths[t as usize], lines.join("
  "));
                    break;
                }
            }
        }
        if std::env::var("DQ_LOOK_TRACE").is_ok() {
            eprintln!("look-keys: closure of {}: {} procs, {} roots", self.paths[t as usize], ids.len(), roots_found.len());
        }
        let c = Rc::new(Closure { ids, bits, digest: *h.finalize().as_bytes(), icons, dynamic: first_dynamic.map(|d| d.1), roots: roots_found });
        self.closures.insert(t, c.clone());
        c
    }

    /// Where proc definition `id` is: its file, type, name and its ordinal among the definitions of that name on that type that
    /// sit in the same file (stable when only bodies change, and the same in a model of just that file).
    fn proc_key(&self, id: u32) -> ProcKey {
        let pd = &self.pdefs[id as usize];
        let file = self.sem.file_of(pd.val.location).unwrap_or("").to_string();
        let mut ord = 0u32;
        if let Some(nid) = self.by_name.get(pd.name) {
            if let Some((start, count)) = self.own.get(&(pd.owner, *nid)) {
                for other in *start..*start + *count {
                    if other >= id {
                        break;
                    }
                    if self.sem.file_of(self.pdefs[other as usize].val.location).unwrap_or("") == file {
                        ord += 1;
                    }
                }
            }
        }
        ProcKey { file, owner: self.paths[pd.owner as usize].clone(), name: pd.name.to_string(), ord }
    }

    /// Initial values of the type's own vars: (digest, icon paths named).
    fn own_vars(&mut self, t: u32) -> ([u8; 32], BTreeSet<String>) {
        if let Some(v) = &self.var_hash[t as usize] {
            return v.clone();
        }
        let t_prof = std::time::Instant::now();
        let _g = ProfGuard(2, t_prof);
        let ty = self.types[t as usize];
        let mut vars: Vec<(&String, &dreammaker::objtree::TypeVar)> = ty.get().vars.iter().collect();
        vars.sort_by(|a, b| a.0.cmp(b.0));
        let mut h = blake3::Hasher::new();
        let mut icons = BTreeSet::new();
        for (name, v) in vars {
            let value = match (&v.value.expression, &v.value.constant) {
                (Some(e), _) => format!("{:?}", e),
                (None, Some(c)) => format!("{:?}", c),
                _ => String::new(),
            };
            let value = strip_locations(&value);
            let decl = v.declaration.as_ref().map(|d| format!("{:?}", d.var_type)).unwrap_or_default();
            for tok in quoted_tokens(&value) {
                if tok.ends_with(".dmi") {
                    icons.insert(tok);
                }
            }
            h.update(&digest(&[name.as_bytes(), decl.as_bytes(), value.as_bytes()]));
        }
        let r = (*h.finalize().as_bytes(), icons);
        self.var_hash[t as usize] = Some(r.clone());
        r
    }

    fn is_abstract(&self, t: u32) -> bool {
        let ty = self.types[t as usize];
        match ty.get_value("abstract_type").and_then(|v| v.constant.as_ref()) {
            Some(dreammaker::constants::Constant::Prefab(p)) => format!("/{}", p.path.join("/")) == self.paths[t as usize],
            _ => false,
        }
    }

    /// The var names declared on a base type and its ancestors (a var of one of these is not a candidate probe).
    fn base_var_names(&self, base: u32) -> FxSet<&'a str> {
        let mut base_names: FxSet<&'a str> = FxSet::default();
        for c in self.chain(base) {
            for (n, v) in &self.types[c as usize].get().vars {
                if v.declaration.is_some() {
                    base_names.insert(n.as_str());
                }
            }
        }
        base_names
    }

    fn declared_below(&self, t: u32, base: u32, base_names: &FxSet<&str>) -> Vec<String> {
        let mut out = BTreeSet::new();
        for c in self.chain(t) {
            if c == base || !self.is_desc(c, base) {
                continue;
            }
            for (n, v) in &self.types[c as usize].get().vars {
                if v.declaration.is_some() && !base_names.contains(n.as_str()) {
                    out.insert(n.clone());
                }
            }
        }
        out.into_iter().collect()
    }
}

struct ProfGuard(usize, std::time::Instant);
impl Drop for ProfGuard {
    fn drop(&mut self) {
        prof::add(self.0, self.1);
    }
}

fn type_string(path: &[String]) -> Option<String> {
    if path.is_empty() {
        None
    } else {
        Some(format!("/{}", path.join("/")))
    }
}

fn note_local(m: &mut HashMap<String, Option<String>>, name: &str, ty: Option<String>) {
    match m.get(name) {
        Some(prev) if *prev != ty => {
            m.insert(name.to_string(), None);
        }
        Some(_) => {}
        None => {
            m.insert(name.to_string(), ty);
        }
    }
}

fn collect_locals(b: &dreammaker::ast::Block, m: &mut HashMap<String, Option<String>>) {
    fn stmt(s: &Statement, m: &mut HashMap<String, Option<String>>) {
        match s {
            Statement::Var(v) => note_local(m, &v.name, type_string(&v.var_type.type_path)),
            Statement::Vars(vs) => {
                for v in vs {
                    note_local(m, &v.name, type_string(&v.var_type.type_path));
                }
            }
            Statement::ForList(fl) => {
                note_local(m, &fl.name, fl.var_type.as_ref().and_then(|t| type_string(&t.type_path)));
            }
            Statement::ForKeyValue(fk) => {
                note_local(m, &fk.key, fk.var_type.as_ref().and_then(|t| type_string(&t.type_path)));
                note_local(m, &fk.value, None);
            }
            Statement::ForRange(fr) => note_local(m, &fr.name, None),
            Statement::ForLoop { init, inc, .. } => {
                for s in [init, inc].into_iter().flatten() {
                    stmt(s, m);
                }
            }
            _ => {}
        }
        for nb in ast::stmt_blocks(s) {
            collect_locals(nb, m);
        }
    }
    for s in b.iter() {
        stmt(&s.elem, m);
    }
}

/// The expressions that are whole statements (their value is dropped).
fn collect_stmt_exprs(b: &dreammaker::ast::Block, out: &mut HashSet<*const Expression>) {
    fn stmt(s: &Statement, out: &mut HashSet<*const Expression>) {
        match s {
            Statement::Expr(e) => {
                out.insert(e as *const Expression);
            }
            Statement::ForLoop { init, inc, .. } => {
                for s in [init, inc].into_iter().flatten() {
                    stmt(s, out);
                }
            }
            _ => {}
        }
        for nb in ast::stmt_blocks(s) {
            collect_stmt_exprs(nb, out);
        }
    }
    for s in b.iter() {
        stmt(&s.elem, out);
    }
}

fn is_string_literal(e: &Expression) -> bool {
    matches!(e, Expression::Base { term, follow } if follow.is_empty() && matches!(&term.elem, Term::String(_)))
}

/// The name argument of `call(...)(...)` is a literal: a string, a resource, a typepath or `nameof(...)`.
fn is_literal_proc_name(e: &Expression) -> bool {
    match e {
        Expression::Base { term, follow } if follow.is_empty() => match &term.elem {
            Term::String(_) | Term::Resource(_) | Term::Prefab(_) => true,
            Term::Call(n, _) => { let n: &str = n; n == "nameof" }
            Term::Expr(inner) => is_literal_proc_name(inner),
            _ => false,
        },
        _ => false,
    }
}

// ---------------------------------------------------------------------------------------------------------------------
// the plan

/// Extra inputs of a run.
#[derive(Default)]
pub struct PlanOpts {
    /// Explain this type (the plan is computed for it only).
    pub explain: Option<String>,
}

fn rel_of_dm(sem: &Sem, ty: TypeRef<'_>) -> String {
    sem.file_of(ty.get().location).unwrap_or("").to_string()
}

fn read_normalized(tree: &Tree, root: &Path, rel: &str) -> Option<String> {
    match tree.get(rel) {
        Some(f) => Some(normalize_source(f.text())),
        None => std::fs::read_to_string(root.join(rel)).ok().map(|t| normalize_source(&t)),
    }
}

/// The salt files, sorted and unique.
fn salt_files(tree: &Tree, sem: &Sem) -> Vec<String> {
    let mut set: BTreeSet<String> = BTreeSet::new();
    for f in tree.select(&CODE_DM) {
        let rel = f.rel.as_str();
        if SALT_FILES.contains(&rel) || SALT_DIRS.iter().any(|d| rel.starts_with(d)) || SALT_PREFIXES.iter().any(|p| rel.starts_with(p)) {
            set.insert(rel.to_string());
        }
    }
    for (ty, name) in SALT_PROCS {
        if let Some(t) = sem.ty(ty) {
            if let Some(tp) = t.get().procs.get(*name) {
                for v in &tp.value {
                    if let Some(r) = sem.file_of(v.location) {
                        set.insert(r.to_string());
                    }
                }
            }
        }
    }
    set.into_iter().collect()
}

fn salt_digest(tree: &Tree, root: &Path, sem: &Sem) -> [u8; 32] {
    let mut h = blake3::Hasher::new();
    for rel in salt_files(tree, sem) {
        if let Some(text) = read_normalized(tree, root, &rel) {
            h.update(&digest(&[rel.as_bytes(), text.as_bytes()]));
        }
    }
    *h.finalize().as_bytes()
}

/// The legacy appearance declarations, which expand to a table entry and leave no marker: `DECLARE_APPEARANCE(PATH, VAR, ROWS)`
/// and `DECLARE_APPEARANCE_PROC(PATH, PROC, FIELDS)`. (type path, macro name, argument text after the path)
fn appearance_decls(tree: &Tree, files: &mut BTreeSet<String>) -> Vec<(String, String, String)> {
    let mut out = Vec::new();
    for f in tree.select(&CODE_DM) {
        if f.text().contains("DECLARE_APPEARANCE") {
            files.insert(f.rel.clone());
            out.extend(appearance_in(f));
        }
    }
    out
}

/// The appearance declarations of one file.
fn appearance_in(f: &crate::tree::SourceFile) -> Vec<(String, String, String)> {
    let mut out = Vec::new();
    let text = f.code().text.as_str();
    let mut from = 0;
    while let Some(i) = text[from..].find("DECLARE_APPEARANCE") {
        let at = from + i;
        from = at + 1;
        let line_start = text[..at].rfind(NL).map(|p| p + 1).unwrap_or(0);
        if !text[line_start..at].trim().is_empty() {
            continue;
        }
        let rest = &text[at..];
        let name_end = rest.find(|c: char| !(c.is_ascii_alphanumeric() || c == '_')).unwrap_or(rest.len());
        let name = &rest[..name_end];
        let after = rest[name_end..].trim_start();
        if !after.starts_with('(') {
            continue;
        }
        let open = at + name_end + (rest[name_end..].len() - after.len());
        let Some(close) = crate::sem::decls::matching_paren(text, open) else { continue };
        let args = crate::sem::decls::split_args(&text[open + 1..close]);
        if let Some(path) = args.first() {
            out.push((path.trim().to_string(), name.to_string(), args[1..].join(",")));
        }
    }
    out
}

/// What a file contributes through `DECLARE_APPEARANCE` and `abstract_type`, the two things the plan reads from text rather
/// than from the model: a digest of the abstract_type lines and the appearance declarations. An edit elsewhere in the file
/// leaves it alone.
fn special_digest(f: &crate::tree::SourceFile) -> u128 {
    let mut h = blake3::Hasher::new();
    for line in f.code().text.lines() {
        if line.contains("abstract_type") {
            h.update(line.trim().as_bytes());
            h.update(b"
");
        }
    }
    for (path, name, body) in appearance_in(f) {
        h.update(&digest(&[path.as_bytes(), name.as_bytes(), body.as_bytes()]));
    }
    u128::from_le_bytes(h.finalize().as_bytes()[..16].try_into().unwrap())
}

/// The DM-derived part of the plan: per type, (partial digest, icon paths, probes).
pub fn dm_part(tree: &Tree, root: &Path, only: Option<&str>) -> Option<(Vec<CacheRow>, Option<Explain>)> {
    let c = dm_compute(tree, root, only, None, None)?;
    Some((c.rows, c.explain))
}

/// Everything one pass over the model produces.
struct Computed {
    rows: Vec<CacheRow>,
    explain: Option<Explain>,
    /// Parallel to `rows`: the index into `closures`.
    foot: Vec<u32>,
    /// The chain types of the computed rows.
    types: BTreeMap<String, Option<String>>,
    /// The procs the closures contain, and each closure as indices into them.
    procs: Vec<ProcRec>,
    closures: Vec<Vec<u32>>,
    salt: Vec<String>,
    special: Vec<String>,
    appearance: Vec<(String, String, String)>,
}

/// `only` computes (and explains) one type; `restrict` computes just those types (the incremental path); `seed` is the cache's
/// `DECLARE_APPEARANCE` list, which stays valid because no changed file holds one.
fn dm_compute(tree: &Tree, root: &Path, only: Option<&str>, restrict: Option<&HashSet<String>>, seed: Option<&Vec<(String, String, String)>>) -> Option<Computed> {
    let sem = crate::sem::sem_for(tree)?;
    let decls = Decls::get(tree);
    let handlers = hooks::discover(&decls);
    let t_model = std::time::Instant::now();
    let mut special_files: BTreeSet<String> = BTreeSet::new();
    let appearance: Vec<(String, String, String)> = match seed {
        Some(a) => a.clone(),
        None => {
            // Reads every file: load them all on the worker threads first.
            tree.prewarm();
            let a = appearance_decls(tree, &mut special_files);
            for f in tree.select(&CODE_DM) {
                if f.text().contains("abstract_type") {
                    special_files.insert(f.rel.clone());
                }
            }
            a
        }
    };
    let mut m = Model::new(&sem, &decls, &handlers, &appearance);
    let want_foot = only.is_none();
    let mut closures: Vec<Vec<u32>> = Vec::new();
    let mut local_proc: FxMap<u32, u32> = FxMap::default();
    let mut proc_ids: Vec<u32> = Vec::new();
    let mut closure_ix: FxMap<usize, u32> = FxMap::default();
    let mut foot: Vec<u32> = Vec::new();
    let mut type_foot: BTreeMap<String, Option<String>> = BTreeMap::new();
    if std::env::var("DQ_LOOK_TRACE").is_ok() {
        eprintln!("look-keys: model {:.2?}: {} types, {} procs", t_model.elapsed(), m.types.len(), m.pdefs.len());
    }
    let salt = salt_digest(tree, root, &sem);
    let mut rows = Vec::new();
    let mut explain = None;
    let order: Vec<u32> = (0..m.types.len() as u32).collect();
    let mut base_names: FxMap<u32, FxSet<&str>> = FxMap::default();
    for t in order {
        let path = m.paths[t as usize].clone();
        let Some(base_path) = BASES.iter().find(|b| path.starts_with(&format!("{}/", b))) else { continue };
        if let Some(o) = only {
            if o != path {
                continue;
            }
        }
        if let Some(r) = restrict {
            if !r.contains(&path) {
                continue;
            }
        }
        if m.is_abstract(t) {
            continue;
        }
        let file = rel_of_dm(&sem, m.types[t as usize]);
        if SKIP_DIRS.iter().any(|d| file.starts_with(d)) {
            continue;
        }
        let base = m.tindex[*base_path];
        let t_closure = std::time::Instant::now();
        let c = m.closure(t);
        prof::add(4, t_closure);
        // vars and declarations of the chain
        let chain = m.chain(t);
        let mut icons: BTreeSet<String> = c.icons.clone();
        let mut h = blake3::Hasher::new();
        h.update(b"vars");
        for ct in &chain {
            if *ct == 0 && m.paths[0] == "/" {
                continue;
            }
            let (vh, vicons) = m.own_vars(*ct);
            h.update(&digest(&[m.paths[*ct as usize].as_bytes(), &vh]));
            icons.extend(vicons);
        }
        h.update(b"markers");
        for ct in &chain {
            if let Some(mh) = m.marker_hash.get(ct) {
                for x in mh {
                    h.update(x);
                }
            }
        }
        h.update(b"closure");
        h.update(&c.digest);
        h.update(b"salt");
        h.update(&salt);
        let partial = h.finalize().as_bytes().to_vec();

        // probes
        let t_probe = std::time::Instant::now();
        let base_names = base_names.entry(base).or_insert_with(|| m.base_var_names(base));
        let cands = m.declared_below(t, base, base_names);
        let mut chain_words: BTreeSet<&String> = BTreeSet::new();
        for ct in &chain {
            if let Some(ws) = m.marker_words.get(ct) {
                chain_words.extend(ws.iter());
            }
        }
        let have_roots = !c.roots.is_empty();
        let mut reasons = Vec::new();
        let forced = FULL_SCAN_TREES.iter().any(|f| path == *f || path.starts_with(&format!("{}/", f)));
        let probes = if forced || c.dynamic.is_some() || !have_roots {
            if forced {
                reasons.push("* forced: its look follows state no draw proc reads (FULL_SCAN_TREES)".to_string());
            } else if let Some(d) = &c.dynamic {
                reasons.push(format!("* dynamic access: {}", d));
            } else {
                reasons.push("* no update_icon/appearance procs found".to_string());
            }
            "*".to_string()
        } else {
            let mut found: Vec<String> = Vec::new();
            for v in &cands {
                let set_name = format!("set_{}", v);
                let mut hit: Option<String> = None;
                for key in [v.as_str(), set_name.as_str()] {
                    if let Some(ids) = m.inv.get(key) {
                        if let Some(id) = ids.iter().find(|i| c.has(**i)) {
                            let pd = &m.pdefs[*id as usize];
                            hit = Some(format!("{}: `{}` in {}::{}", v, key, m.paths[pd.owner as usize], pd.name));
                            break;
                        }
                    }
                }
                if hit.is_none() && chain_words.contains(v) {
                    hit = Some(format!("{}: named in a CAPABILITIES/STAT declaration", v));
                }
                if let Some(r) = hit {
                    reasons.push(r);
                    found.push(v.clone());
                }
            }
            found.join(",")
        };
        prof::add(3, t_probe);
        let icon_list: Vec<String> = icons.into_iter().collect();
        if only.is_some() {
            let closure = c
                .ids
                .iter()
                .map(|i| {
                    let pd = &m.pdefs[*i as usize];
                    let line = pd.val.location.line;
                    format!("{}::{} {}:{}", m.paths[pd.owner as usize], pd.name, sem.file_of(pd.val.location).unwrap_or(""), line)
                })
                .collect();
            explain = Some(Explain { closure, probes: probes.clone(), probe_reason: reasons, icons: icon_list.clone(), dynamic: c.dynamic.clone(), roots: c.roots.clone(), capped: m.capped.iter().cloned().collect() });
        }
        if want_foot {
            for ct in &chain {
                let cp = m.paths[*ct as usize].clone();
                if !type_foot.contains_key(&cp) {
                    let parent = m.parent[*ct as usize].map(|p| m.paths[p as usize].clone());
                    type_foot.insert(cp, parent);
                }
            }
            let ix = *closure_ix.entry(Rc::as_ptr(&c) as usize).or_insert_with(|| {
                let local: Vec<u32> = c
                    .ids
                    .iter()
                    .map(|id| {
                        *local_proc.entry(*id).or_insert_with(|| {
                            proc_ids.push(*id);
                            (proc_ids.len() - 1) as u32
                        })
                    })
                    .collect();
                closures.push(local);
                (closures.len() - 1) as u32
            });
            foot.push(ix);
        }
        rows.push(CacheRow { ty: path, partial, icons: icon_list, probes });
    }
    // Rows (and their footprints) in type order.
    let mut order_ix: Vec<usize> = (0..rows.len()).collect();
    order_ix.sort_by(|a, b| rows[*a].ty.cmp(&rows[*b].ty));
    let rows: Vec<CacheRow> = order_ix.iter().map(|i| CacheRow { ty: rows[*i].ty.clone(), partial: rows[*i].partial.clone(), icons: rows[*i].icons.clone(), probes: rows[*i].probes.clone() }).collect();
    if want_foot {
        foot = order_ix.iter().map(|i| foot[*i].clone()).collect();
    }
    let procs: Vec<ProcRec> = if want_foot { proc_ids.iter().map(|id| ProcRec { key: m.proc_key(*id), text: m.info(*id).text_hash }).collect() } else { Vec::new() };
    if std::env::var("DQ_LOOK_TRACE").is_ok() {
        prof::report();
    }
    Some(Computed { rows, explain, foot, types: type_foot, procs, closures, salt: salt_files(tree, &sem), special: special_files.into_iter().collect(), appearance })
}

/// Icon sources of a `.dmi` path: its `.dmi.toml` and the `.png` beside it. A source that is not found is
/// skipped (the path alone is hashed).
fn icon_digest(root: &Path, dmi: &str, found: &mut Vec<String>) -> [u8; 32] {
    let mut h = blake3::Hasher::new();
    h.update(dmi.as_bytes());
    if dmi.starts_with("icons/gen/") || dmi.contains("..") {
        return *h.finalize().as_bytes();
    }
    let stem = dmi.strip_suffix(".dmi").unwrap_or(dmi);
    let candidates = [format!("{}.dmi.toml", stem), format!("{}.png", stem)];
    let mut any = false;
    for c in &candidates {
        if let Ok(bytes) = std::fs::read(root.join(c)) {
            h.update(&digest(&[c.as_bytes(), &bytes]));
            found.push(c.clone());
            any = true;
        }
    }
    if !any {
        // No source pair: a committed .dmi is the icon.
        if let Ok(bytes) = std::fs::read(root.join(dmi)) {
            h.update(&digest(&[dmi.as_bytes(), &bytes]));
            found.push(dmi.to_string());
        }
    }
    *h.finalize().as_bytes()
}

fn finish(root: &Path, rows: &[CacheRow]) -> (Vec<Row>, BTreeMap<String, Vec<String>>) {
    let mut paths: BTreeSet<&String> = BTreeSet::new();
    for r in rows {
        paths.extend(r.icons.iter());
    }
    let paths: Vec<&String> = paths.into_iter().collect();
    let hashed: Vec<([u8; 32], Vec<String>)> = crate::sem::par_map(&paths, |p| {
        let mut found = Vec::new();
        let d = icon_digest(root, p, &mut found);
        (d, found)
    });
    let by_path: HashMap<&String, &([u8; 32], Vec<String>)> = paths.iter().cloned().zip(hashed.iter()).collect();
    let mut sources: BTreeMap<String, Vec<String>> = BTreeMap::new();
    for (p, (_, f)) in paths.iter().zip(hashed.iter()) {
        sources.insert((*p).clone(), f.clone());
    }
    let out = rows
        .iter()
        .map(|r| {
            let mut h = blake3::Hasher::new();
            h.update(&r.partial);
            for i in &r.icons {
                h.update(&by_path[i].0);
            }
            Row { ty: r.ty.clone(), key: hex(&h.finalize().as_bytes()[..8]), probes: r.probes.clone() }
        })
        .collect();
    (out, sources)
}

fn tree_key(tree: &Tree) -> Vec<u8> {
    let mut h = blake3::Hasher::new();
    h.update(CACHE_VERSION.as_bytes());
    h.update(crate::cache::ENGINE_HASH.as_bytes());
    for f in tree.select(&CODE_DM) {
        h.update(f.rel.as_bytes());
        h.update(&f.hash.to_le_bytes());
    }
    h.finalize().as_bytes().to_vec()
}

fn load_cache(p: &Path) -> Option<CacheFile> {
    let bytes = std::fs::read(p).ok()?;
    match crate::incr::de::<CacheFile>(&bytes) {
        Ok(c) => Some(c),
        Err(e) => {
            if std::env::var("DQ_LOOK_TRACE").is_ok() {
                eprintln!("look-keys: cache {} unreadable ({}); computing", p.display(), e);
            }
            None
        }
    }
}

fn store_cache(p: &Path, file: &CacheFile) {
    if let Some(dir) = p.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    if std::env::var("DQ_LOOK_TRACE").is_ok() {
        let size = |r: Result<Vec<u8>, bincode::Error>| r.map(|b| b.len()).unwrap_or(0);
        eprintln!("look-keys: cache parts: rows {} B", size(crate::incr::ser(&file.rows)));
        if let Some(i) = &file.incr {
            eprintln!(
                "look-keys: cache parts: hashes {} B, files {} B, procs {} B ({} procs), closures {} B ({} closures), foot {} B, types {} B",
                size(crate::incr::ser(&i.hashes)),
                size(crate::incr::ser(&i.files)),
                size(crate::incr::ser(&i.procs)),
                i.procs.len(),
                size(crate::incr::ser(&i.closures)),
                i.closures.len(),
                size(crate::incr::ser(&i.foot)),
                size(crate::incr::ser(&i.types))
            );
        }
    }
    match crate::incr::ser(file) {
        Ok(bytes) => {
            let tmp = p.with_extension(format!("tmp{}", std::process::id()));
            if std::fs::write(&tmp, bytes).is_ok() {
                let _ = std::fs::rename(&tmp, p);
            }
        }
        Err(e) => eprintln!("look-keys: could not store {}: {}", p.display(), e),
    }
}

/// Per file and type, a digest of the var values the file assigns to the type: `(var, value text)` for every var whose value has an
/// expression or a constant, grouped by the file of the value. `only` limits the work to those files (a partial model).
fn var_digests(sem: &Sem, only: Option<&[String]>) -> HashMap<String, BTreeMap<String, u128>> {
    let mut rows: HashMap<String, BTreeMap<String, Vec<String>>> = HashMap::new();
    for ty in sem.objtree.iter_types() {
        let t = ty.get();
        let path = if t.path.is_empty() { "/" } else { t.path.as_str() };
        for (name, v) in &t.vars {
            let value = match (&v.value.expression, &v.value.constant) {
                (Some(e), _) => format!("{:?}", e),
                (None, Some(c)) => format!("{:?}", c),
                _ => continue,
            };
            let Some(f) = sem.file_of(v.value.location) else { continue };
            if let Some(only) = only {
                if !only.iter().any(|o| o == f) {
                    continue;
                }
            }
            rows.entry(f.to_string()).or_default().entry(path.to_string()).or_default().push(format!("{}|{}", name, strip_locations(&value)));
        }
    }
    rows.into_iter()
        .map(|(f, types)| {
            let per_type = types
                .into_iter()
                .map(|(t, mut v)| {
                    v.sort();
                    let mut h = blake3::Hasher::new();
                    for x in &v {
                        h.update(&(x.len() as u64).to_le_bytes());
                        h.update(x.as_bytes());
                    }
                    (t, u128::from_le_bytes(h.finalize().as_bytes()[..16].try_into().unwrap()))
                })
                .collect();
            (f, per_type)
        })
        .collect()
}

/// The text digest of every proc definition located in the `only` files of a (partial) model, by `ProcKey`. Mirrors the model's
/// own enumeration: a (type, name) with no body anywhere is skipped; the ordinal counts the earlier definitions of the name on
/// the type that sit in the same file.
fn proc_texts(sem: &Sem, only: &[String]) -> HashMap<ProcKey, u128> {
    let mut out = HashMap::new();
    for ty in sem.objtree.iter_types() {
        let t = ty.get();
        let owner = if t.path.is_empty() { "/".to_string() } else { t.path.clone() };
        for (name, tp) in &t.procs {
            if tp.value.is_empty() || tp.value.iter().all(|v| v.code.is_none()) {
                continue;
            }
            let mut seen: HashMap<&str, u32> = HashMap::new();
            for val in &tp.value {
                let Some(file) = sem.file_of(val.location) else { continue };
                let ord = seen.entry(file).or_insert(0);
                let this = *ord;
                *ord += 1;
                if !only.iter().any(|o| o == file) {
                    continue;
                }
                let text = strip_locations(&format!("{:?}|{:?}", val.parameters, val.code));
                let hash = u128::from_le_bytes(blake3::hash(text.as_bytes()).as_bytes()[..16].try_into().unwrap());
                out.insert(ProcKey { file: file.to_string(), owner: owner.clone(), name: name.clone(), ord: this }, hash);
            }
        }
    }
    out
}

/// What outside the files' bodies the rows read: `deepquarry.dme`, the `code/__defines` files and the declaration markers (their
/// names, arguments and normalized text, not their positions, which `Decls::key` includes: a line added above a marker would
/// otherwise look like a changed declaration).
fn lk_env(tree: &Tree) -> Option<u128> {
    let dme = std::fs::read(tree.root.join("deepquarry.dme")).ok()?;
    let decls = Decls::get(tree);
    let mut marks: Vec<(String, String, String)> = decls.markers.iter().map(|m| (m.name.clone(), m.args.join("\u{1f}"), normalize_source(&m.body))).collect();
    marks.sort();
    let defines: Vec<(&str, u128)> = tree.select(&CODE_DM).iter().filter(|f| f.rel.starts_with("code/__defines/")).map(|f| (f.rel.as_str(), f.hash)).collect();
    Some(crate::incr::ctx_key(&(blake3::hash(&dme).as_bytes().to_vec(), marks, defines)))
}

fn file_rec(tree: &Tree, rel: &str, col: &inc::Collected, vars: &HashMap<String, BTreeMap<String, u128>>) -> FileRec {
    FileRec {
        vars: vars.get(rel).cloned().unwrap_or_default(),
        shape: inc::shape_hash(col.shape.get(rel)),
        tokens: inc::token_hash(tree, rel),
        bare: inc::bare_hash(tree, rel),
        directive: inc::has_directive(&inc::text_of(tree, rel)),
        made: col.types.get(rel).map(|t| t.iter().cloned().collect()).unwrap_or_default(),
    }
}

/// The incremental state to store after a full computation (None when the tree has no `deepquarry.dme` to key it on).
fn full_state(tree: &Tree, comp: &Computed) -> Option<Incr> {
    let (_, included) = inc::environment(tree)?;
    let env = lk_env(tree)?;
    let sem = crate::sem::sem_for(tree)?;
    let col = inc::collect_with(&sem, false);
    let vars = var_digests(&sem, None);
    let rels: Vec<&String> = included.keys().collect();
    let recs: Vec<(String, FileRec)> = crate::sem::par_map(&rels, |rel| ((*rel).clone(), file_rec(tree, rel, &col, &vars)));
    Some(Incr {
        engine: format!("{}|{}", CACHE_VERSION, crate::cache::ENGINE_HASH),
        env,
        hashes: tree.select(&CODE_DM).iter().map(|f| (f.rel.clone(), f.hash)).collect(),
        files: recs.into_iter().collect(),
        salt: comp.salt.clone(),
        special: comp.special.iter().filter_map(|r| tree.get(r).map(|f| (r.clone(), special_digest(f)))).collect(),
        procs: comp.procs.clone(),
        closures: comp.closures.iter().map(|ids| ids.iter().fold(Vec::new(), |mut bits, i| {
            bit_set(&mut bits, *i as usize);
            bits
        })).collect(),
        foot: comp.foot.clone(),
        types: comp.types.clone(),
        appearance: comp.appearance.clone(),
    })
}

/// Rebuilds the rows from the cached ones after an edit that left the structure alone, recomputing only the rows whose
/// footprint holds a changed file. None = cannot tell, compute everything.
fn try_incremental(tree: &Tree, root: &Path, c: &CacheFile, old: &Incr) -> Option<(Vec<CacheRow>, Incr, String)> {
    let trace = std::env::var("DQ_LOOK_TRACE").is_ok();
    let refuse = |why: &str| -> Option<(Vec<CacheRow>, Incr, String)> {
        if trace {
            eprintln!("look-keys: incremental refused: {}", why);
        }
        None
    };
    if old.engine != format!("{}|{}", CACHE_VERSION, crate::cache::ENGINE_HASH) {
        return refuse("the analyzer changed since the cache was written");
    }
    if old.foot.len() != c.rows.len() {
        return refuse("footprints do not match the rows");
    }
    let Some((_, included)) = inc::environment(tree) else { return refuse("no deepquarry.dme") };
    let Some(env) = lk_env(tree) else { return refuse("no deepquarry.dme") };
    if env != old.env {
        return refuse("deepquarry.dme, the declarations or the defines changed");
    }
    let now: Vec<(String, u128)> = tree.select(&CODE_DM).iter().map(|f| (f.rel.clone(), f.hash)).collect();
    if now.len() != old.hashes.len() || now.iter().zip(&old.hashes).any(|(a, b)| a.0 != b.0) {
        return refuse("the set of .dm files changed");
    }
    let changed: Vec<&String> = now.iter().zip(&old.hashes).filter(|(a, b)| a.1 != b.1).map(|(a, _)| &a.0).collect();
    let mut cosmetic: Vec<String> = Vec::new();
    let mut substantive: Vec<String> = Vec::new();
    for rel in &changed {
        if old.salt.contains(*rel) {
            return refuse(&format!("{} is part of the salt", rel));
        }
        let text = inc::text_of(tree, rel);
        let special_now = tree.get(rel).filter(|f| f.text().contains("DECLARE_APPEARANCE") || f.text().contains("abstract_type")).map(special_digest);
        if special_now != old.special.get(*rel).copied() {
            return refuse(&format!("{} changed what it declares with DECLARE_APPEARANCE or abstract_type", rel));
        }
        if !included.contains_key(*rel) {
            // Not in the model, and its declarations are in the environment key: nothing the rows read.
            cosmetic.push((*rel).clone());
            continue;
        }
        let Some(rec) = old.files.get(*rel) else { return refuse(&format!("no structure record for {}", rel)) };
        if inc::token_hash(tree, rel) == rec.tokens {
            cosmetic.push((*rel).clone());
            continue;
        }
        if rec.directive || inc::has_directive(&text) {
            return refuse(&format!("{} has a #define, #undef or #include", rel));
        }
        if inc::bare_hash(tree, rel) != rec.bare {
            return refuse(&format!("{} changed a bare type header", rel));
        }
        substantive.push((*rel).clone());
    }
    // The types whose assigned var values differ in a changed file (before or after), and the closure procs whose text differs.
    let mut types_changed: HashSet<String> = HashSet::new();
    let mut new_vars: HashMap<String, BTreeMap<String, u128>> = HashMap::new();
    let mut new_texts: HashMap<ProcKey, u128> = HashMap::new();
    if !substantive.is_empty() {
        let Ok(part) = Sem::build_partial(root, tree, &substantive) else { return refuse("partial parse failed") };
        let got = inc::collect_with(&part, false);
        // A partial model locates a type in the first changed file that mentions it (an implicit parent included), so the
        // check is the one `sem::incremental` makes: every type it locates is a known one, and every type this file
        // located before is still located here.
        let known: HashSet<&str> = old.files.values().flat_map(|r| r.made.iter().map(|t| t.as_str())).collect();
        let none = BTreeSet::new();
        new_vars = var_digests(&part, Some(&substantive));
        new_texts = proc_texts(&part, &substantive);
        for rel in &substantive {
            let empty = BTreeMap::new();
            let before = &old.files[rel].vars;
            let after = new_vars.get(rel).unwrap_or(&empty);
            for (t, d) in before.iter() {
                if after.get(t) != Some(d) {
                    types_changed.insert(t.clone());
                }
            }
            for (t, d) in after.iter() {
                if before.get(t) != Some(d) {
                    types_changed.insert(t.clone());
                }
            }
            let rec = &old.files[rel];
            if inc::shape_hash(got.shape.get(rel)) != rec.shape {
                return refuse(&format!("{} changed the structure (a var or proc declaration)", rel));
            }
            let made = got.types.get(rel).unwrap_or(&none);
            if made.iter().any(|t| !known.contains(t.as_str())) {
                return refuse(&format!("{} gained a type", rel));
            }
            if rec.made.iter().any(|t| !made.contains(t)) {
                return refuse(&format!("{} lost a type", rel));
            }
        }
    }
    if trace {
        let mut names: Vec<&String> = types_changed.iter().collect();
        names.sort();
        eprintln!("look-keys: changed files {:?}; types with different var values: {:?}", changed, names);
    }
    let mut state = old.clone();
    state.hashes = now;
    for rel in cosmetic.iter().chain(substantive.iter()) {
        if let Some(rec) = state.files.get_mut(rel) {
            rec.tokens = inc::token_hash(tree, rel);
        }
    }
    for rel in &substantive {
        // Remember the digest of the values the file assigns now (the partial model computed it).
        if let Some(rec) = state.files.get_mut(rel) {
            rec.vars = new_vars.get(rel).cloned().unwrap_or_default();
        }
    }
    // The closure procs whose text changed (a proc the partial model no longer has counts as changed).
    let mut changed_procs: Vec<u8> = Vec::new();
    let mut n_changed_procs = 0usize;
    for (i, rec) in state.procs.iter_mut().enumerate() {
        if !substantive.iter().any(|f| *f == rec.key.file) {
            continue;
        }
        match new_texts.get(&rec.key) {
            Some(t) if *t == rec.text => {}
            Some(t) => {
                rec.text = *t;
                bit_set(&mut changed_procs, i);
                n_changed_procs += 1;
            }
            None => {
                bit_set(&mut changed_procs, i);
                n_changed_procs += 1;
            }
        }
    }
    // The rows a changed file can move: those whose closure holds a changed proc, and those whose chain holds a type that was
    // assigned different var values.
    let closure_hit: Vec<bool> = old.closures.iter().map(|bits| bits.iter().zip(&changed_procs).any(|(a, b)| a & b != 0)).collect();
    let mut chain_memo: FxMap<&str, bool> = FxMap::default();
    fn chain_hit<'t>(ty: &'t str, types: &'t BTreeMap<String, Option<String>>, changed: &HashSet<String>, memo: &mut FxMap<&'t str, bool>) -> bool {
        if let Some(v) = memo.get(ty) {
            return *v;
        }
        let r = changed.contains(ty)
            || match types.get(ty) {
                Some(parent) => parent.as_deref().is_some_and(|p| chain_hit(p, types, changed, memo)),
                None => true, // a chain type with no record: cannot tell
            };
        memo.insert(ty, r);
        r
    }
    let mut affected: HashSet<String> = HashSet::new();
    for (i, row) in c.rows.iter().enumerate() {
        let cl = old.foot[i];
        if closure_hit.get(cl as usize).copied().unwrap_or(true) || (!types_changed.is_empty() && chain_hit(row.ty.as_str(), &old.types, &types_changed, &mut chain_memo)) {
            affected.insert(row.ty.clone());
        }
    }
    let summary = format!("{} changed file(s) ({} cosmetic or outside the model), {} closure proc(s) and {} type(s)' var values changed", substantive.len() + cosmetic.len(), cosmetic.len(), n_changed_procs, types_changed.len());
    if affected.is_empty() {
        return Some((c.rows.clone(), state, format!("incremental: no row holds a changed proc or var ({}), no full parse", summary)));
    }
    let comp = dm_compute(tree, root, None, Some(&affected), Some(&old.appearance))?;
    if comp.rows.len() != affected.len() {
        return refuse("a recomputed type vanished");
    }
    // Join the recomputed closures: the proc table only grows, so the old bitsets keep their meaning.
    let mut index: FxMap<ProcKey, u32> = state.procs.iter().enumerate().map(|(i, r)| (r.key.clone(), i as u32)).collect();
    let mut global: Vec<u32> = Vec::with_capacity(comp.procs.len());
    for r in &comp.procs {
        let g = match index.get(&r.key) {
            Some(g) => {
                state.procs[*g as usize].text = r.text;
                *g
            }
            None => {
                state.procs.push(r.clone());
                let g = (state.procs.len() - 1) as u32;
                index.insert(r.key.clone(), g);
                g
            }
        };
        global.push(g);
    }
    let base = old.closures.len() as u32;
    let mut closures: Vec<Vec<u8>> = old.closures.clone();
    for ids in &comp.closures {
        let mut bits = Vec::new();
        for i in ids {
            bit_set(&mut bits, global[*i as usize] as usize);
        }
        closures.push(bits);
    }
    let fresh: FxMap<&str, usize> = comp.rows.iter().enumerate().map(|(i, r)| (r.ty.as_str(), i)).collect();
    let mut rows = c.rows.clone();
    let mut foot = old.foot.clone();
    for (i, row) in rows.iter_mut().enumerate() {
        if let Some(j) = fresh.get(row.ty.as_str()) {
            *row = comp.rows[*j].clone();
            foot[i] = base + comp.foot[*j];
        }
    }
    // Keep the closures some row still uses.
    let mut remap: FxMap<u32, u32> = FxMap::default();
    let mut kept: Vec<Vec<u8>> = Vec::new();
    for f in foot.iter_mut() {
        let n = *remap.entry(*f).or_insert_with(|| {
            kept.push(closures[*f as usize].clone());
            (kept.len() - 1) as u32
        });
        *f = n;
    }
    state.closures = kept;
    state.foot = foot;
    for (path, parent) in comp.types {
        state.types.insert(path, parent);
    }
    Some((rows, state, format!("incremental: {} of {} types recomputed ({})", affected.len(), c.rows.len(), summary)))
}

/// The whole plan for a loaded tree. `cache` is the file the DM part is stored in (None = never cached).
pub fn plan(tree: &Tree, root: &Path, opts: &PlanOpts, cache: Option<&Path>) -> Option<Plan> {
    let key = tree_key(tree);
    let mut explain = None;
    let mut mode = String::from("full");
    let mut rows: Option<Vec<CacheRow>> = None;
    let mut store: Option<CacheFile> = None;
    if opts.explain.is_none() {
        if let Some(c) = cache.and_then(load_cache) {
            if c.key == key {
                mode = "cached".to_string();
                rows = Some(c.rows);
            } else if let Some(old) = &c.incr {
                if let Some((r, state, how)) = try_incremental(tree, root, &c, old) {
                    mode = how;
                    store = Some(CacheFile { key: key.clone(), rows: r.clone(), incr: Some(state) });
                    rows = Some(r);
                }
            }
        }
    }
    let rows = match rows {
        Some(r) => r,
        None => {
            let comp = dm_compute(tree, root, opts.explain.as_deref(), None, None)?;
            explain = comp.explain.clone();
            if opts.explain.is_none() {
                let incr = full_state(tree, &comp);
                store = Some(CacheFile { key: key.clone(), rows: comp.rows.clone(), incr });
            } else {
                mode = "explain".to_string();
            }
            comp.rows
        }
    };
    if let (Some(file), Some(p)) = (&store, cache) {
        store_cache(p, file);
    }
    let (out, sources) = finish(root, &rows);
    let _ = sources;
    Some(Plan { rows: out, explain, mode })
}

const NL: char = 10 as char;

fn cache_dir(root: &Path) -> PathBuf {
    match std::env::var("DQ_ANALYZE_CACHE") {
        Ok(d) if !d.is_empty() => PathBuf::from(d),
        _ => root.join("data/analyze-cache"),
    }
}

/// `analyze look-keys [--out FILE] [--explain TYPE] [--no-cache]`.
pub fn run(args: &[String], root: &Path) -> ExitCode {
    let mut out: Option<PathBuf> = None;
    let mut explain: Option<String> = None;
    let mut no_cache = false;
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--out" => {
                out = args.get(i + 1).map(PathBuf::from);
                i += 1;
            }
            "--explain" => {
                explain = args.get(i + 1).cloned();
                i += 1;
            }
            "--no-cache" => no_cache = true,
            other => {
                eprintln!("analyze look-keys: unknown argument {:?}\nusage: analyze look-keys [--out FILE] [--explain TYPE] [--no-cache]", other);
                return ExitCode::from(2);
            }
        }
        i += 1;
    }
    let o = crate::run::Options { root: root.to_path_buf(), lints: vec!["sem/keys".to_string()], ..Default::default() };
    let engine = match crate::run::Engine::new(crate::run::registry(), o) {
        Ok(e) => e,
        Err(e) => {
            eprintln!("analyze: {}", e);
            return ExitCode::from(2);
        }
    };
    let cache_path = if no_cache { None } else { Some(cache_dir(root).join("look-keys.bin")) };
    let t0 = std::time::Instant::now();
    let opts = PlanOpts { explain: explain.clone() };
    let Some(p) = plan(&engine.tree, root, &opts, cache_path.as_deref()) else {
        eprintln!("analyze look-keys: the semantic model could not be built");
        return ExitCode::from(2);
    };
    if let Some(ty) = explain {
        let Some(e) = p.explain else {
            eprintln!("analyze look-keys: {} is not a concrete type under /obj, /mob or /turf", ty);
            return ExitCode::from(2);
        };
        println!("type {}", ty);
        println!("roots: {}", e.roots.join(", "));
        println!("closure ({} procs):", e.closure.len());
        for c in &e.closure {
            println!("  {}", c);
        }
        println!("probes: {}", e.probes);
        for r in &e.probe_reason {
            println!("  {}", r);
        }
        let (_, sources) = finish(root, &[CacheRow { ty: ty.clone(), partial: vec![], icons: e.icons.clone(), probes: String::new() }]);
        println!("icons ({}):", e.icons.len());
        for path in &e.icons {
            let src = sources.get(path).map(|s| s.join(", ")).unwrap_or_default();
            println!("  {} <- {}", path, if src.is_empty() { "(no source found: path only)".to_string() } else { src });
        }
        if let Some(d) = e.dynamic {
            println!("dynamic access: {}", d);
        }
        println!("cut fan-outs ({}):", e.capped.len());
        for c in &e.capped {
            println!("  {}", c);
        }
        return ExitCode::SUCCESS;
    }
    let mut text = String::new();
    for r in &p.rows {
        text.push_str(&format!("{}\t{}\t{}\n", r.ty, r.key, r.probes));
    }
    let path = out.map(|o| if o.is_absolute() { o } else { std::env::current_dir().unwrap_or_default().join(o) }).unwrap_or_else(|| root.join("data/look-plan.tsv"));
    if let Some(dir) = path.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    if let Err(e) = std::fs::write(&path, text) {
        eprintln!("analyze look-keys: write {}: {}", path.display(), e);
        return ExitCode::FAILURE;
    }
    let stars = p.rows.iter().filter(|r| r.probes == "*").count();
    eprintln!("analyze look-keys: {} types, {} with probes `*`, {:.2?} ({}); wrote {}", p.rows.len(), stars, t0.elapsed(), p.mode, path.display());
    ExitCode::SUCCESS
}

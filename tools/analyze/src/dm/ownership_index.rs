//! Port of the structure index in `tools/ci/ownership_lint.py` (lines 40-330): `class Index`,
//! `parents()`, the regexes, `proc_scopes`, `receiver_type`, `creates_entity`, `puts_object`.
//!
//! Shared by `state_schema` (its `ownership_kind` asks the index which kind a var is) and by the
//! ownership lint's checks (`lints/ownership.rs`, the port of `main()`). Only the index and its
//! helpers live here. The Python `Index` also carried the `usage` map that `main()` fills with
//! accessor writes before checking; it is not part of the shared (immutable, memoized) index here:
//! the lint builds it locally, the way `state_schema::OwnershipKinds` does.
//!
//! Python's dicts keep insertion order and some checks report in that order, so `decls` is an
//! [`OrdMap`]. Files are indexed in path order (the Python walked `glob.glob` order); the only
//! observable difference is which declaration wins when one type declares the same var twice.

use std::collections::HashMap;
use std::sync::{Arc, LazyLock};

use rayon::prelude::*;
use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};

use crate::incr;
use crate::pat::Pat;
use crate::tree::{SourceFile, Tree, View};
use crate::util::{is_py_space, py_rstrip, py_strip, under};

macro_rules! re {
    ($name:ident, $p:expr) => {
        pub static $name: LazyLock<Pat> = LazyLock::new(|| Pat::new($p));
    };
}
/// `re.match` (anchored at the start).
macro_rules! re_m {
    ($name:ident, $p:expr) => {
        pub static $name: LazyLock<Pat> = LazyLock::new(|| Pat::new_match($p));
    };
}

pub const CORE_DIRS: &[&str] = &[
    "code/datums/ownership/",
    "code/datums/om/",
    "code/engine/time/",
    "code/engine/refs/edges.dm",
    "code/engine/declare/checks.dm",
    "code/engine/declare/definition_registry.dm",
    "code/engine/kernel/cadences.dm",
    "code/engine/kernel/sequence.dm",
    "code/engine/kernel/sequence_table.dm",
    "code/datums/lifecycle/",
    "code/engine/state/",
    "code/__defines/",
    "code/controllers/",
    "code/engine/refs/containment/",
    "code/datums/containment/stock.dm",
    "code/datums/shared_cache/",
];
pub const CALLBACK_OK: &[&str] = &[
    "code/datums/om/",
    "code/engine/time/",
    "code/engine/refs/edges.dm",
    "code/engine/declare/checks.dm",
    "code/engine/declare/definition_registry.dm",
    "code/engine/kernel/cadences.dm",
    "code/engine/kernel/sequence.dm",
    "code/engine/kernel/sequence_table.dm",
    "code/controllers/",
    "code/__defines/",
    "code/datums/ownership/",
    "code/datums/callback.dm",
    "code/_helpers/",
];
pub const HANDLE_OK: &[&str] = &[
    "code/datums/om/",
    "code/engine/time/",
    "code/engine/refs/edges.dm",
    "code/engine/declare/checks.dm",
    "code/engine/declare/definition_registry.dm",
    "code/engine/kernel/cadences.dm",
    "code/engine/kernel/sequence.dm",
    "code/engine/kernel/sequence_table.dm",
    "code/datums/ownership/",
    "code/engine/state/",
    "code/datums/lifecycle/",
    "code/__defines/",
    "code/engine/refs/containment/",
    "code/datums/containment/stock.dm",
    "code/modules/unit_tests/",
];

pub const ENTITY_ROOTS: &[&str] = &["/datum", "/atom", "/obj", "/mob", "/turf"];
/// Flyweights (code/datums/ownership/flyweight.dm, GLOB.flyweight_types; keep in step).
pub const FLYWEIGHT_TYPES: &[&str] = &[
    "/datum/capability",
    "/datum/reaction",
    "/datum/stack_recipe",
    "/datum/stack_recipe_list",
    "/datum/own_entry",
    "/datum/derived_entry",
    "/datum/op_def",
];
pub const MODIFIERS: &[&str] = &["tmp", "static", "global", "const", "final"];
/// The Python defines `VALUE_TYPES` twice (`("/datum/gas_mixture/__never__",)` first, then this
/// list); the later one is the one in force.
pub const VALUE_TYPES: &[&str] =
    &["/image", "/mutable_appearance", "/icon", "/matrix", "/regex", "/list", "/sound", "/savefile", "/database", "/generator", "/particles", "/filter", "/alist"];

pub const OWN_FUNCS: &[&str] = &["own_set", "own_take", "own_add", "own_remove", "own_put", "own_take_member", "own_clear", "own_transfer"];
pub const REL_FUNCS: &[&str] = &["rel_set", "rel_add", "rel_remove", "rel_clear", "rel_link", "rel_unlink"];
/// The `rel_*` writers that replace `own_*` (the rest of `REL_FUNCS` write a true relation).
pub const REL_WRITERS: &[&str] = &["rel_set", "rel_add", "rel_remove", "rel_clear"];
pub const PROTO_FUNCS: &[&str] = &["proto_set", "proto_private"];
pub const OBJLIST_WRITES: &[&str] = &["+=", "|=", "[]=", "LAZYADD", "LAZYOR", "LAZYSET", "LAZYDISTINCTADD", "LAZYINSERT", ".Add", ".Insert"];

re_m!(PROC_DEF, r"^(/[\w/]+?)/(?:(?:proc|verb)/)?(\w+)\s*\((.*)$");
re_m!(TYPE_LINE, r"^(/[\w/]+)\s*(?:\{.*)?$");
re_m!(MEMBER, r"^\s+(?:var|VAR_PRIVATE|VAR_PROTECTED|VAR_FINAL)/((?:[\w]+/)*)(\w+)\b");
re_m!(
    OM_FIELD_DECL,
    r"^OM_FIELD(?:(?:_TYPED|_VIEW)\(\s*(/[\w/]+)\s*,\s*([\w/]+)\s*,|\(\s*(/[\w/]+)\s*,())\s*(\w+)\s*,"
);
re_m!(ABS_MEMBER, r"^(/[\w/]+?)/(?:var|VAR_PRIVATE|VAR_PROTECTED|VAR_FINAL)/((?:[\w]+/)*)(\w+)\b");
re!(TYPED_NAME, r"(?:var/)?((?:/?\w+)(?:/\w+)+)/(\w+)\b");
re_m!(DECLARE_HEAD, r"^(/[\w/]+)/(?:ownership|relations)\(\)");
re_m!(DECLARE_CALL, r"^\s+\.\s*\+=\s*(owns|shares|proto|rel_one|rel_many)\(\s*nameof\((\w+)\)\s*(?:,\s*(.*?))?\)\s*(?://.*)?$");
/// An accessor's var-name argument: a string literal (banned, `string_name`) or `nameof(v)` /
/// `nameof(x.v)` / `nameof(/type::v)`. Group: the var name.
pub const VAR_ARG: &str = r#"(?:"|nameof\((?:/[\w/]+::|\w+\.)?)(\w+)(?:"|\))"#;
re_m!(REGISTRY, r"^REGISTRY_TYPE\(\s*(/[\w/]+)\s*,");
pub static ACCESSOR: LazyLock<Pat> = LazyLock::new(|| {
    Pat::new(&format!(
        r"\b(own_set|own_take|own_add|own_remove|own_put|own_take_member|own_clear|own_transfer|rel_set|rel_add|rel_remove|rel_clear|rel_link|rel_unlink|proto_set|proto_private|shared_set)\(\s*([\w.]+)\s*,\s*{}",
        VAR_ARG
    ))
});
/// Groups: 1 = destination receiver, 2 = destination var (`VAR_ARG` with its first capture
/// turned non-capturing, exactly as the Python's `.replace`).
pub static TRANSFER_DEST: LazyLock<Pat> = LazyLock::new(|| {
    Pat::new(&format!(
        r"\bown_transfer\([^,]+,\s*{}\s*,\s*([\w.]+)\s*,\s*{}",
        VAR_ARG.replace(r"(\w+)", r"\w+"),
        VAR_ARG
    ))
});
re!(
    STRING_NAME,
    r#"\b(own_set|own_take|own_add|own_remove|own_put|own_take_member|own_take_all|own_clear|own_values|own_transfer|rel_set|rel_add|rel_remove|rel_clear|rel_link|rel_unlink|rel_targets|rel_names|proto_set|proto_private|proto_replace|proto_is_private|shared_set|keyed_set_id)\((?:[^,()"]|\([^()]*\))*,\s*"\w+"|\b(own_move)\((?:[^,()"]|\([^()]*\))*,(?:[^,()"]|\([^()]*\))*,\s*"\w+""#
);
// A name after a `/` is a path component (`/datum/capability/wires = /datum/...` is an assoc key), not a var.
re!(WRITE_ASSIGN, r"(?<![\w./])((?:\w+\??\.)*)(\w+)\s*(=(?!=)|\+=|-=|\|=|&=|\^=)");
re!(WRITE_INDEX, r"(?<![\w.])((?:\w+\??\.)*)(\w+)\[[^\]\n]*\]\s*=(?!=)");
re!(WRITE_METHOD, r"(?<![\w.])((?:\w+\??\.)*)(\w+)\??\.(Cut|Add|Remove|Insert|Swap|RemoveAll)\(");
re!(
    WRITE_MACRO,
    r"\b(QDEL_NULL|QDEL_LIST|QDEL_LIST_ASSOC|QDEL_LIST_ASSOC_VAL|QDEL_LAZYLIST|LAZYADD|LAZYREMOVE|LAZYSET|LAZYOR|LAZYINITLIST|LAZYCLEARLIST|LAZYNULL|UNSETEMPTY|LAZYADDASSOC|LAZYREMOVEASSOC|LAZYADDASSOCLIST|LAZYDISTINCTADD|LAZYINSERT)\(\s*((?:\w+\??\.)*)(\w+)\b"
);
re!(CALLBACK, r"\bCALLBACK\(");
re!(HANDLE_CALL, r"\bom_(handle|resolve|handle_of|handle_is|resolve_all)\(");
re!(HANDLE_VAR, r"^\s*var/(?:[\w]+/)*(\w+_handle)\b|^(/[\w/]+?)/var/(?:[\w]+/)*(\w+_handle)\b");
re!(
    REMOVED,
    r"\b(DECLARE_REF|OM_STATIC_TYPE|REFKIND_\w+|link_set|link_clear|link_backlist_add|link_backlist_remove|WEAK_LIST_ADD|WEAK_LIST_REMOVE|WEAK_LIST_HAS|weak_list_live|DuplicateObject|dq_lifecycle_link_table|declared_refs|declared_ownership|own_declare|keyed_target_var|declared_keep_vars|declared_pool_reset|declared_forward_vars|declare_ownership)\b|\b(?:OWN|OWN_POLICY|OWN_IF|SHARED|PROTO|REL|REL_LIST|REL_PAIR|REL_PAIR_LIST|REL_SET|REL_KEYED|REL_KEYED_LIST|KEYED_TARGET|KEEP_AFTER_DESTROY|POOL_RESET|FORWARD_STATE)(?=\()"
);
re!(LOCAL_DECL, r"\bvar/(?:[\w]+/)*(\w+)");
re!(OBJ_TOKEN, r#"(?<![\w."])(src|new|[A-Za-z_]\w*)(?![\w.\[(?:])"#);
re_m!(NEW_VALUE, r"^\s*new\s*(/[\w/]+)?");
re!(PARAM_NAME, r"(?:^|,)\s*(\w+)\s*(?:=|,|\)|$)");
re!(CALL_ARGS, r"\b(?!new\b)[A-Za-z_]\w*\s*\([^()]*\)");

pub fn related(a: &str, b: &str) -> bool {
    a == b || a.starts_with(&format!("{}/", b)) || b.starts_with(&format!("{}/", a))
}

/// `IMPLICIT_ROOTS`: DM's implicit parents of a built-in root.
fn implicit_roots(root: &str) -> &'static [&'static str] {
    match root {
        "/obj" | "/mob" => &["/atom/movable", "/atom", "/datum"],
        "/turf" | "/area" => &["/atom", "/datum"],
        "/atom" => &["/datum"],
        _ => &[],
    }
}

/// The type and its ancestors, nearest first, including DM's implicit roots (/obj -> /atom/movable
/// -> /atom -> /datum).
pub fn parents(path: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut root: Option<String> = None;
    let mut p = path.to_string();
    while !p.is_empty() && p.matches('/').count() >= 1 {
        out.push(p.clone());
        if p.matches('/').count() == 1 {
            root = Some(p);
            break;
        }
        let cut = p.rfind('/').unwrap();
        p.truncate(cut);
    }
    if let Some(r) = root {
        for imp in implicit_roots(&r) {
            out.push((*imp).to_string());
        }
    }
    out
}

/// An insertion-ordered string-keyed map (a Python dict).
#[derive(Debug)]
pub struct OrdMap<V> {
    idx: HashMap<String, usize>,
    items: Vec<(String, V)>,
}

impl<V> Default for OrdMap<V> {
    fn default() -> Self {
        OrdMap::new()
    }
}

impl<V> OrdMap<V> {
    pub fn new() -> OrdMap<V> {
        OrdMap { idx: HashMap::new(), items: Vec::new() }
    }

    pub fn get(&self, k: &str) -> Option<&V> {
        self.idx.get(k).map(|&i| &self.items[i].1)
    }

    /// `d[k] = v`: replaces in place (keeps the key's original position).
    pub fn insert(&mut self, k: &str, v: V) {
        match self.idx.get(k) {
            Some(&i) => self.items[i].1 = v,
            None => {
                self.idx.insert(k.to_string(), self.items.len());
                self.items.push((k.to_string(), v));
            }
        }
    }

    pub fn entry_or_insert_with(&mut self, k: &str, f: impl FnOnce() -> V) -> &mut V {
        let i = match self.idx.get(k) {
            Some(&i) => i,
            None => {
                self.idx.insert(k.to_string(), self.items.len());
                self.items.push((k.to_string(), f()));
                self.items.len() - 1
            }
        };
        &mut self.items[i].1
    }

    pub fn iter(&self) -> impl Iterator<Item = (&str, &V)> {
        self.items.iter().map(|(k, v)| (k.as_str(), v))
    }

    pub fn len(&self) -> usize {
        self.items.len()
    }

    pub fn is_empty(&self) -> bool {
        self.items.is_empty()
    }
}

/// One entry of a type's `ownership()` / `relations()` list: the kind under its old macro name
/// (`OWN`, `OWN_POLICY`, `OWN_IF`, `ANNOTATE`, `SHARED`, `PROTO`, `REL`, ...), the option text, and
/// where it is written.
#[derive(Clone, Debug)]
pub struct Decl {
    pub macro_name: String,
    pub opts: String,
    pub rel: String,
    pub line: usize,
}

/// `(declaring type, vtype, is_list)` for a var seen from some type.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Member {
    pub declared_on: String,
    pub vtype: String,
    pub is_list: bool,
}

#[derive(Debug, Default)]
pub struct Index {
    /// type -> var -> (vtype, is_list)
    pub members: HashMap<String, HashMap<String, (String, bool)>>,
    /// type -> var -> declaration (insertion ordered, like the Python dicts)
    pub decls: OrdMap<OrdMap<Decl>>,
    /// The registry types: the flyweights plus every `REGISTRY_TYPE(...)` seen.
    pub registry: Vec<String>,
    /// var name -> [(type, vtype, is_list)] in declaration order
    pub name_decls: HashMap<String, Vec<(String, String, bool)>>,
    /// Key of everything `members` / `name_decls` hold (what an accessor-usage scan reads).
    pub key_members: u128,
    /// Key of the whole structure minus where things are written (members, declaration kinds,
    /// registry): what a per-file judgement reads. Declaration lines, files and option text are
    /// not in it.
    pub key_struct: u128,
}

/// How many stores a sharded cache is split into.
const SHARDS: usize = 16;

fn shard_of(rel: &str) -> usize {
    let mut h: u32 = 0x811c_9dc5;
    for b in rel.bytes() {
        h = (h ^ b as u32).wrapping_mul(0x0100_0193);
    }
    h as usize % SHARDS
}

/// [`incr::keyed`] over [`SHARDS`] stores, by path hash. One edit rewrites one small store instead of
/// the whole set, and the stores load in parallel. Results are in `files` order. ALLOW uses recorded
/// through `sys::kept_recorded` are carried back to the calling thread.
pub fn sharded_keyed<R>(name: &str, ctx: u128, files: &[&SourceFile], f: impl Fn(&SourceFile) -> R + Sync) -> Vec<R>
where
    R: Serialize + DeserializeOwned + Default + PartialEq + Send,
{
    let mut groups: Vec<Vec<usize>> = vec![Vec::new(); SHARDS];
    for (i, file) in files.iter().enumerate() {
        groups[shard_of(&file.rel)].push(i);
    }
    let outs: Vec<(Vec<R>, Vec<crate::lint::AllowUse>)> = groups
        .par_iter()
        .enumerate()
        .map(|(s, idxs)| {
            let part: Vec<&SourceFile> = idxs.iter().map(|&i| files[i]).collect();
            let before = crate::dm::sys::take_recorded();
            let r = incr::keyed(&format!("{}-{}", name, s), ctx, &part, &f);
            let uses = crate::dm::sys::take_recorded();
            crate::dm::sys::restore_recorded(before);
            (r, uses)
        })
        .collect();
    let mut slots: Vec<Option<R>> = Vec::with_capacity(files.len());
    slots.resize_with(files.len(), || None);
    let mut all_uses = Vec::new();
    for (idxs, (rs, uses)) in groups.iter().zip(outs) {
        for (&i, r) in idxs.iter().zip(rs) {
            slots[i] = Some(r);
        }
        all_uses.extend(uses);
    }
    crate::dm::sys::replay_recorded(all_uses);
    slots.into_iter().map(|r| r.unwrap_or_default()).collect()
}

/// [`incr::facts`], sharded (see [`sharded_keyed`]).
pub fn sharded_facts<F>(name: &str, files: &[&SourceFile], f: impl Fn(&SourceFile) -> F + Sync) -> Vec<F>
where
    F: Serialize + DeserializeOwned + Default + PartialEq + Send,
{
    sharded_keyed(name, 0, files, f)
}

/// One file's index facts and the keys of what a judgement reads of them (0 when it has none).
#[derive(Serialize, Deserialize, Default, PartialEq)]
struct FileIdx {
    events: Vec<IdxEv>,
    h_members: u128,
    h_struct: u128,
}

fn file_idx(f: &SourceFile) -> FileIdx {
    let events = file_events(&f.rel, f.raw(), f.code());
    if events.is_empty() {
        return FileIdx::default();
    }
    // (kind, a, b, c, flag) with no lines, files or option text.
    let mut members: Vec<(&str, &str, &str, bool)> = Vec::new();
    let mut structure: Vec<(u8, &str, &str, &str, bool)> = Vec::new();
    for ev in &events {
        match ev {
            IdxEv::Member { owner, vtype, is_list, name } => {
                members.push((owner, name, vtype, *is_list));
                structure.push((0, owner, name, vtype, *is_list));
            }
            IdxEv::Decl { owner, name, macro_name, .. } => structure.push((1, owner, name, macro_name, false)),
            IdxEv::Registry(t) => structure.push((2, t, "", "", false)),
        }
    }
    let (h_members, h_struct) = (incr::ctx_key(&members), incr::ctx_key(&structure));
    FileIdx { events, h_members, h_struct }
}

/// One structural fact a file contributes to the [`Index`], in file order. Replaying every file's
/// events in path order rebuilds the index exactly as walking the files did.
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub enum IdxEv {
    Member { owner: String, vtype: String, is_list: bool, name: String },
    Decl { owner: String, name: String, macro_name: String, opts: String, rel: String, line: u32 },
    Registry(String),
}

/// `(vtype, is_list)` of a member declared with the path segments `segs`.
fn member_parts(segs: &str) -> (String, bool) {
    let mut parts: Vec<&str> = segs.split('/').filter(|p| !p.is_empty() && !MODIFIERS.contains(p)).collect();
    let is_list = !parts.is_empty() && parts[0] == "list";
    if is_list {
        parts.remove(0);
    }
    let vtype = if parts.is_empty() { String::new() } else { format!("/{}", parts.join("/")) };
    (vtype, is_list)
}

/// The kind a declaration entry is recorded under (its old macro name).
fn decl_macro(func: &str, opts: &str) -> String {
    let own_private = pat_search(r"\bpolicy\s*=\s*OWN_PRIVATE_COPY\b", opts);
    if func == "owns" && own_private {
        "PROTO".into()
    } else if func == "owns" {
        if opts.contains("policy_proc") {
            "OWN_POLICY".into()
        } else if opts.contains("if_var") {
            "OWN_IF".into()
        } else if pat_search(r"\bpolicy\s*=\s*OWN_NONE\b", opts) {
            "ANNOTATE".into()
        } else {
            "OWN".into()
        }
    } else if func == "shares" {
        "SHARED".into()
    } else if func == "rel_one" || func == "rel_many" {
        if pat_search(r"\bkind\s*=\s*RELK_OWNED\b", opts) {
            if own_private { "PROTO".into() } else { "OWN".into() }
        } else {
            "REL".into()
        }
    } else {
        func.to_uppercase()
    }
}

impl Index {
    pub fn new() -> Index {
        Index { registry: FLYWEIGHT_TYPES.iter().map(|s| s.to_string()).collect(), ..Index::default() }
    }

    /// The index over exactly `files` (path-sorted), built once per run and shared.
    pub fn get(tree: &Tree, files: &[&SourceFile]) -> Arc<Index> {
        let mut h = blake3::Hasher::new();
        h.update(b"ownership-index");
        for f in files {
            h.update(&f.fkey.to_le_bytes());
        }
        let key = h.finalize().to_hex().to_string();
        tree.memo(&key, || Index::build(files))
    }

    pub fn build(files: &[&SourceFile]) -> Index {
        let fs: Vec<FileIdx> = sharded_facts("ownership-index-facts", files, file_idx);
        let mut members: Vec<u128> = Vec::new();
        let mut structure: Vec<u128> = Vec::new();
        for x in &fs {
            if x.h_struct != 0 {
                members.push(x.h_members);
                structure.push(x.h_struct);
            }
        }
        let mut idx = Index::new();
        idx.key_members = incr::mix(&members);
        idx.key_struct = incr::mix(&structure);
        for x in fs {
            for ev in x.events {
                idx.apply_owned(ev);
            }
        }
        idx
    }

    /// Replays one recorded fact.
    pub fn apply(&mut self, ev: &IdxEv) {
        self.apply_owned(ev.clone());
    }

    fn apply_owned(&mut self, ev: IdxEv) {
        match ev {
            IdxEv::Member { owner, vtype, is_list, name } => {
                match self.members.get_mut(&owner) {
                    Some(m) => {
                        m.insert(name.clone(), (vtype.clone(), is_list));
                    }
                    None => {
                        let mut m = HashMap::new();
                        m.insert(name.clone(), (vtype.clone(), is_list));
                        self.members.insert(owner.clone(), m);
                    }
                }
                match self.name_decls.get_mut(&name) {
                    Some(v) => v.push((owner, vtype, is_list)),
                    None => {
                        self.name_decls.insert(name, vec![(owner, vtype, is_list)]);
                    }
                }
            }
            IdxEv::Decl { owner, name, macro_name, opts, rel, line } => {
                let inner = self.decls.entry_or_insert_with(&owner, OrdMap::new);
                inner.insert(&name, Decl { macro_name, opts, rel, line: line as usize });
            }
            IdxEv::Registry(t) => self.registry.push(t),
        }
    }

    pub fn add_member(&mut self, owner: &str, segs: &str, name: &str) {
        let (vtype, is_list) = member_parts(segs);
        self.apply(&IdxEv::Member { owner: owner.to_string(), vtype, is_list, name: name.to_string() });
    }

    /// One entry in `owner`'s ownership()/relations() list, recorded under the kind's old macro
    /// name. An `owns()` with no policy only annotates (`ANNOTATE`).
    pub fn add_decl(&mut self, owner: &str, func: &str, name: &str, opts: &str, rel: &str, no: usize) {
        self.apply(&decl_ev(owner, func, name, opts, rel, no));
    }

    pub fn index_file(&mut self, rel: &str, raw: &View, code: &View) {
        for ev in file_events(rel, raw, code) {
            self.apply(&ev);
        }
    }

    /// `(declaring type, vtype, is_list)` for var `name` as seen from type `owner`, or None.
    pub fn member(&self, owner: &str, name: &str) -> Option<Member> {
        for p in parents(owner) {
            if let Some((vtype, is_list)) = self.members.get(&p).and_then(|m| m.get(name)) {
                return Some(Member { declared_on: p, vtype: vtype.clone(), is_list: *is_list });
            }
        }
        None
    }

    /// `(declaring type, declaration)` of `name` as seen from type `owner`, or None.
    pub fn decl(&self, owner: &str, name: &str) -> Option<(String, &Decl)> {
        for p in parents(owner) {
            if let Some(d) = self.decls.get(&p).and_then(|m| m.get(name)) {
                return Some((p, d));
            }
        }
        None
    }

    pub fn is_registry(&self, vtype: &str) -> bool {
        under(vtype, &self.registry)
    }

    pub fn is_entity(&self, vtype: &str) -> bool {
        under(vtype, ENTITY_ROOTS) && !self.is_registry(vtype)
    }
}

/// Every structural fact `code`/`raw` (one file) contributes to the index, in order.
pub fn file_events(rel: &str, raw: &View, code: &View) -> Vec<IdxEv> {
    let mut ev: Vec<IdxEv> = Vec::new();
    let mut current: Option<String> = None;
    let mut declaring: Option<String> = None;
    for (no, line) in code.numbered() {
        let first = line.chars().next();
        if matches!(first, Some('"') | Some('\'')) {
            continue; // the tail of a multi-line string, not a new top-level line
        }
        if declaring.is_some() && first.map(is_py_space).unwrap_or(false) {
            if let Some(m) = DECLARE_CALL.captures(raw.line(no)) {
                let owner = declaring.clone().unwrap();
                ev.push(decl_ev(&owner, m.s(1), m.s(2), m.s(3), rel, no));
            }
            continue;
        }
        declaring = None;
        if first.map(|c| !is_py_space(c)).unwrap_or(false) {
            if let Some(m) = DECLARE_HEAD.captures(line) {
                declaring = Some(m.s(1).to_string());
                current = None;
                continue;
            }
            if let Some(m) = REGISTRY.captures(py_strip(raw.line(no))) {
                ev.push(IdxEv::Registry(m.s(1).to_string()));
                continue;
            }
            if let Some(m) = ABS_MEMBER.captures(line) {
                ev.push(member_ev(m.s(1), m.s(2), m.s(3)));
                current = None;
                continue;
            }
            if let Some(m) = OM_FIELD_DECL.captures(line) {
                // OM_FIELD(T, F, ...) / OM_FIELD_TYPED|_VIEW(T, VT, F, ...) declare T/var/F
                let vt = if m.matched(2) && !m.s(2).is_empty() { format!("{}/", m.s(2).trim_matches('/')) } else { String::new() };
                let owner = if !m.s(1).is_empty() { m.s(1) } else { m.s(3) };
                ev.push(member_ev(owner, &vt, m.s(5)));
                current = None;
                continue;
            }
            // SYSTEM_DEF(x) declares /datum/system/x through a macro: its indented body is that type's block.
            if let Some(m) = crate::pat!(r"^SYSTEM_DEF\((\w+)\)\s*$").captures(py_rstrip(line)) {
                current = Some(format!("/datum/system/{}", m.s(1)));
                continue;
            }
            let m = TYPE_LINE.captures(py_rstrip(line));
            current = match m {
                Some(m) if !line.contains('(') => Some(m.s(1).to_string()),
                _ => None,
            };
            continue;
        }
        if let Some(cur) = current.clone() {
            if let Some(m) = MEMBER.captures(line) {
                ev.push(member_ev(&cur, m.s(1), m.s(2)));
            }
        }
    }
    ev
}

fn member_ev(owner: &str, segs: &str, name: &str) -> IdxEv {
    let (vtype, is_list) = member_parts(segs);
    IdxEv::Member { owner: owner.to_string(), vtype, is_list, name: name.to_string() }
}

fn decl_ev(owner: &str, func: &str, name: &str, opts: &str, rel: &str, no: usize) -> IdxEv {
    IdxEv::Decl {
        owner: owner.to_string(),
        name: name.to_string(),
        macro_name: decl_macro(func, opts),
        opts: opts.to_string(),
        rel: rel.to_string(),
        line: no as u32,
    }
}

fn pat_search(p: &str, hay: &str) -> bool {
    // Compiled once per call site string; these four are tiny.
    static CACHE: LazyLock<std::sync::Mutex<HashMap<String, Arc<Pat>>>> = LazyLock::new(|| std::sync::Mutex::new(HashMap::new()));
    let pat = {
        let mut g = CACHE.lock().unwrap();
        g.entry(p.to_string()).or_insert_with(|| Arc::new(Pat::new(p))).clone()
    };
    pat.is_match(hay)
}

/// A local variable's declared type: `Some(Some(path))` typed, `Some(None)` declared without a
/// type, absent when unknown (the Python dict with `None` values).
pub type LocalTypes = HashMap<String, Option<String>>;

/// `proc_scopes(code)`: calls `f(line number, line, owner type, proc name, locals)` for every
/// proc body line (blank lines included, as the generator yielded them).
pub fn proc_scopes(code: &View, mut f: impl FnMut(usize, &str, &str, &str, &LocalTypes)) {
    let mut owner: Option<String> = None;
    let mut proc_name = String::new();
    let mut local_types: LocalTypes = HashMap::new();
    for (no, line) in code.numbered() {
        let first = line.chars().next();
        if matches!(first, Some('"') | Some('\'')) {
            continue; // the tail of a multi-line string
        }
        if first.map(|c| !is_py_space(c)).unwrap_or(false) {
            match PROC_DEF.captures(line) {
                Some(m) if !line.starts_with('#') => {
                    owner = Some(m.s(1).to_string());
                    proc_name = m.s(2).to_string();
                    local_types = HashMap::new();
                    let params = m.s(3);
                    for tm in TYPED_NAME.captures_iter(params) {
                        local_types.insert(tm.s(2).to_string(), Some(format!("/{}", tm.s(1).trim_start_matches('/'))));
                    }
                    for am in PARAM_NAME.captures_iter(params) {
                        local_types.entry(am.s(1).to_string()).or_insert(None);
                    }
                }
                _ => {
                    owner = None;
                    proc_name.clear();
                }
            }
            continue;
        }
        let Some(own) = owner.as_deref() else { continue };
        for tm in TYPED_NAME.captures_iter(line) {
            let start = tm.start(0);
            if line[..start].ends_with("var/") || line[start..].starts_with("var/") {
                local_types.insert(tm.s(2).to_string(), Some(format!("/{}", tm.s(1).trim_start_matches('/'))));
            }
        }
        for lm in LOCAL_DECL.captures_iter(line) {
            local_types.entry(lm.s(1).to_string()).or_insert(None);
        }
        f(no, line, own, &proc_name, &local_types);
    }
}

/// The static type of a `a.b.` receiver chain ("" chain = a bare write -> the owner), or None
/// when unknown.
pub fn receiver_type(idx: &Index, chain: &str, owner: &str, local_types: &LocalTypes) -> Option<String> {
    if chain.is_empty() {
        return Some(owner.to_string());
    }
    let segs: Vec<&str> = chain.trim_end_matches('.').split('.').map(|s| s.trim_end_matches('?')).collect();
    if segs == ["src"] {
        return Some(owner.to_string());
    }
    if segs.len() != 1 {
        return None;
    }
    let name = segs[0];
    if let Some(t) = local_types.get(name) {
        return t.clone();
    }
    idx.member(owner, name).map(|m| m.vtype)
}

/// True when the assigned value is `new /entity/type(...)` (not a value type such as an image).
pub fn creates_entity(rhs: &str) -> bool {
    let head = rhs.split("//").next().unwrap_or("");
    let Some(m) = NEW_VALUE.captures(head) else { return false };
    if !m.matched(1) {
        return false; // implicit type: the declared type decides (already handled)
    }
    !under(m.s(1), VALUE_TYPES)
}

/// True when the written value (or key) is recognisably an entity: `src`, a `new` expression, or a
/// local/argument declared with an entity type. `registry_roots` is `REGISTRY_ROOTS` (the index's
/// registry list, which `main()` assigns before any check).
pub fn puts_object(rhs: &str, local_types: &LocalTypes, registry_roots: &[String]) -> bool {
    let mut text = rhs.split("//").next().unwrap_or("").to_string();
    // A proc call's arguments are not the written value: EXPIRY_AT(src, ...) writes a number.
    loop {
        let next = CALL_ARGS.replace_all(&text, "0");
        if next == text {
            break;
        }
        text = next;
    }
    for m in OBJ_TOKEN.captures_iter(&text) {
        let tok = m.s(1);
        if tok == "src" || tok == "new" {
            return true;
        }
        if let Some(Some(t)) = local_types.get(tok) {
            if !t.is_empty() && under(t, ENTITY_ROOTS) && !under(t, registry_roots) {
                return true;
            }
        }
    }
    false
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parents_include_implicit_roots() {
        assert_eq!(parents("/obj/item"), ["/obj/item", "/obj", "/atom/movable", "/atom", "/datum"]);
        assert_eq!(parents("/datum/x/y"), ["/datum/x/y", "/datum/x", "/datum"]);
        assert_eq!(parents("/area"), ["/area", "/atom", "/datum"]);
        assert!(parents("nothing").is_empty());
    }

    #[test]
    fn index_reads_members_decls_and_fields() {
        let f = SourceFile::from_text(
            "code/a.dm",
            "/obj/thing\n\tvar/datum/foo/bar\n\tvar/tmp/list/obj/items\n/obj/thing/ownership()\n\t. += owns(nameof(bar))\n\n/obj/thing/var/obj/baz\nOM_FIELD(/obj/thing, on, 1)\n",
        );
        let idx = Index::build(&[&f]);
        assert_eq!(idx.member("/obj/thing", "bar").unwrap().vtype, "/datum/foo");
        let items = idx.member("/obj/thing", "items").unwrap();
        assert!(items.is_list && items.vtype == "/obj");
        assert_eq!(idx.decl("/obj/thing", "bar").unwrap().1.macro_name, "OWN");
        assert!(idx.member("/obj/thing", "baz").is_some());
        assert!(idx.member("/obj/thing", "on").is_some());
    }
}

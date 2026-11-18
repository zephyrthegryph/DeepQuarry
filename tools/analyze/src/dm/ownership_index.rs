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

use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};

use crate::raw_ownership_policy::{decl_ev, member_parts};
pub use crate::raw_ownership_policy::{
    file_events, visit_file_events, IdxEv, ABS_MEMBER, DECLARE_CALL, DECLARE_HEAD, FLYWEIGHT_TYPES,
    GLOBAL_DECL, MEMBER, MODIFIERS, REGISTRY, TYPE_LINE,
};

use crate::incr;
use crate::pat::Pat;
use crate::tree::{SourceFile, Tree, View};
use crate::util::{is_py_space, under};

macro_rules! re {
    ($name:ident,$source:ident, $p:expr) => {
        pub const $source:&str=$p;
        pub static $name: LazyLock<Pat> = LazyLock::new(|| Pat::new($p));
    };
}
/// `re.match` (anchored at the start).
macro_rules! re_m {
    ($name:ident,$source:ident, $p:expr) => {
        pub const $source:&str=$p;
        pub static $name: LazyLock<Pat> = LazyLock::new(|| Pat::new_match($p));
    };
}

pub const CORE_DIRS: &[&str] = &[
    "code/library/ownership/",
    "code/datums/om/",
    "code/engine/time/",
    "code/engine/refs/edges.dm",
    "code/engine/declare/checks.dm",
    "code/engine/declare/definition_registry.dm",
    "code/engine/kernel/cadences.dm",
    "code/engine/kernel/sequence.dm",
    "code/engine/kernel/sequence_table.dm",
    "code/library/lifecycle/",
    "code/engine/state/",
    "code/__defines/", "code/defines/engine/", "code/defines/library/", "code/defines/host/", "code/defines/base/", "code/defines/content/",
    "code/controllers/", "code/world/kernel/", "code/world/systems/", "code/world/configuration/", "code/world/controllers/",
    "code/engine/refs/containment/",
    "code/library/containers/containment/stock.dm",
    "code/library/shared_cache/",
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
    "code/controllers/", "code/world/kernel/", "code/world/systems/", "code/world/configuration/", "code/world/controllers/",
    "code/__defines/", "code/defines/engine/", "code/defines/library/", "code/defines/host/", "code/defines/base/", "code/defines/content/",
    "code/library/ownership/",
    "code/library/datum/callback.dm",
    "code/host/helpers/", "code/library/helpers/", "code/content/helpers/",
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
    "code/library/ownership/",
    "code/engine/state/",
    "code/library/lifecycle/",
    "code/__defines/", "code/defines/engine/", "code/defines/library/", "code/defines/host/", "code/defines/base/", "code/defines/content/",
    "code/engine/refs/containment/",
    "code/library/containers/containment/stock.dm",
    "code/tests/unit_tests/",
    "code/tests/unit_tests/",
];

pub const ENTITY_ROOTS: &[&str] = &["/datum", "/atom", "/obj", "/mob", "/turf"];
/// The Python defines `VALUE_TYPES` twice (`("/datum/gas_mixture/__never__",)` first, then this
/// list); the later one is the one in force.
pub const VALUE_TYPES: &[&str] = &[
    "/image",
    "/mutable_appearance",
    "/icon",
    "/matrix",
    "/regex",
    "/list",
    "/sound",
    "/savefile",
    "/database",
    "/generator",
    "/particles",
    "/filter",
    "/alist",
];

pub const OWN_FUNCS: &[&str] = &[
    "own_set",
    "own_take",
    "own_add",
    "own_remove",
    "own_put",
    "own_take_member",
    "own_clear",
    "own_transfer",
];
pub const REL_FUNCS: &[&str] = &[
    "rel_set",
    "rel_add",
    "rel_remove",
    "rel_clear",
    "rel_link",
    "rel_unlink",
];
/// The `rel_*` writers that replace `own_*` (the rest of `REL_FUNCS` write a true relation).
pub const REL_WRITERS: &[&str] = &["rel_set", "rel_add", "rel_remove", "rel_clear"];
pub const PROTO_FUNCS: &[&str] = &["proto_set", "proto_private"];
pub const OBJLIST_WRITES: &[&str] = &[
    "+=",
    "|=",
    "[]=",
    "LAZYADD",
    "LAZYOR",
    "LAZYSET",
    "LAZYDISTINCTADD",
    "LAZYINSERT",
    ".Add",
    ".Insert",
];

re_m!(PROC_DEF,PROC_DEF_SOURCE, r"^(/[\w/]+?)/(?:(?:proc|verb)/)?(\w+)\s*\((.*)$");

re!(TYPED_NAME,TYPED_NAME_SOURCE, r"(?:var/)?((?:/?\w+)(?:/\w+)+)/(\w+)\b");

/// An accessor's var-name argument: a string literal (banned, `string_name`) or `nameof(v)` /
/// `nameof(x.v)` / `nameof(/type::v)`. Group: the var name.
pub use crate::raw_ownership_policy::VAR_ARG;
// A global declared through a `GLOBAL_*` macro (code/__defines/__globals.dm): `GLOBAL_DATUM(x, /type)`, `GLOBAL_LIST_EMPTY(x)`, ... Groups: 1 = macro
// suffix, 2 = the var name, 3 = the type argument of the typed forms.

/// The type `GLOB` has; the vars of every `GLOBAL_*` macro are its globals ([`Index::globals`]).
pub const GLOB_TYPE: &str = "/datum/controller/global_vars";

pub use crate::raw_ownership_policy::{ACCESSOR,ACCESSOR_SOURCE};
/// Groups: 1 = destination receiver, 2 = destination var (`VAR_ARG` with its first capture
/// turned non-capturing, exactly as the Python's `.replace`).
macro_rules! transfer_source{($first:expr,$second:expr)=>{concat!(r"\bown_transfer\([^,]+,\s*",$first,r"\s*,\s*([\w.]+)\s*,\s*",$second)}}
pub const TRANSFER_DEST_SOURCE:&str=transfer_source!(crate::raw_ownership_policy::var_arg_source!(r"\w+"),crate::raw_ownership_policy::var_arg_source!(r"(\w+)"));
pub static TRANSFER_DEST: LazyLock<Pat> = LazyLock::new(|| {
    Pat::new(&format!(
        transfer_source!("{}","{}"),
        VAR_ARG.replace(r"(\w+)", r"\w+"),
        VAR_ARG
    ))
});
re!(STRING_NAME,STRING_NAME_SOURCE,
    r#"\b(own_set|own_take|own_add|own_remove|own_put|own_take_member|own_take_all|own_clear|own_values|own_transfer|rel_set|rel_add|rel_remove|rel_clear|rel_link|rel_unlink|rel_targets|rel_names|proto_set|proto_private|proto_replace|proto_is_private|shared_set|keyed_set_id)\((?:[^,()"]|\([^()]*\))*,\s*"\w+"|\b(own_move)\((?:[^,()"]|\([^()]*\))*,(?:[^,()"]|\([^()]*\))*,\s*"\w+""#
);
// A name after a `/` is a path component (`/datum/capability/wires = /datum/...` is an assoc key), not a var.
re!(WRITE_ASSIGN,WRITE_ASSIGN_SOURCE,
    r"(?<![\w./])((?:\w+\??\.)*)(\w+)\s*(=(?!=)|\+=|-=|\|=|&=|\^=)"
);
re!(WRITE_INDEX,WRITE_INDEX_SOURCE,
    r"(?<![\w.])((?:\w+\??\.)*)(\w+)\[[^\]\n]*\]\s*=(?!=)"
);
re!(WRITE_METHOD,WRITE_METHOD_SOURCE,
    r"(?<![\w.])((?:\w+\??\.)*)(\w+)\??\.(Cut|Add|Remove|Insert|Swap|RemoveAll)\("
);
re!(WRITE_MACRO,WRITE_MACRO_SOURCE,
    r"\b(QDEL_NULL|QDEL_LIST|QDEL_LIST_ASSOC|QDEL_LIST_ASSOC_VAL|QDEL_LAZYLIST|LAZYADD|LAZYREMOVE|LAZYSET|LAZYOR|LAZYINITLIST|LAZYCLEARLIST|LAZYNULL|UNSETEMPTY|LAZYADDASSOC|LAZYREMOVEASSOC|LAZYADDASSOCLIST|LAZYDISTINCTADD|LAZYINSERT)\(\s*((?:\w+\??\.)*)(\w+)\b"
);
re!(CALLBACK,CALLBACK_SOURCE, r"\bCALLBACK\(");
re!(HANDLE_CALL,HANDLE_CALL_SOURCE,
    r"\bom_(handle|resolve|handle_of|handle_is|resolve_all)\("
);
re!(HANDLE_VAR,HANDLE_VAR_SOURCE,
    r"^\s*var/(?:[\w]+/)*(\w+_handle)\b|^(/[\w/]+?)/var/(?:[\w]+/)*(\w+_handle)\b"
);
re!(REMOVED,REMOVED_SOURCE,
    r"\b(DECLARE_REF|OM_STATIC_TYPE|REFKIND_\w+|link_set|link_clear|link_backlist_add|link_backlist_remove|WEAK_LIST_ADD|WEAK_LIST_REMOVE|WEAK_LIST_HAS|weak_list_live|DuplicateObject|dq_lifecycle_link_table|declared_refs|declared_ownership|own_declare|keyed_target_var|declared_keep_vars|declared_pool_reset|declared_forward_vars|declare_ownership)\b|\b(?:OWN|OWN_POLICY|OWN_IF|SHARED|PROTO|REL|REL_LIST|REL_PAIR|REL_PAIR_LIST|REL_SET|REL_KEYED|REL_KEYED_LIST|KEYED_TARGET|KEEP_AFTER_DESTROY|POOL_RESET|FORWARD_STATE)(?=\()"
);
re!(LOCAL_DECL,LOCAL_DECL_SOURCE, r"\bvar/(?:[\w]+/)*(\w+)");
re!(OBJ_TOKEN,OBJ_TOKEN_SOURCE,
    r#"(?<![\w."])(src|new|[A-Za-z_]\w*)(?![\w.\[(?:])"#
);
re_m!(NEW_VALUE,NEW_VALUE_SOURCE, r"^\s*new\s*(/[\w/]+)?");
re!(PARAM_NAME,PARAM_NAME_SOURCE, r"(?:^|,)\s*(\w+)\s*(?:=|,|\)|$)");
re!(CALL_ARGS,CALL_ARGS_SOURCE, r"\b(?!new\b)[A-Za-z_]\w*\s*\([^()]*\)");

pub fn related(a: &str, b: &str) -> bool {
    a == b || a.starts_with(&format!("{}/", b)) || b.starts_with(&format!("{}/", a))
}

/// `IMPLICIT_ROOTS`: DM's implicit parents of a built-in root.
/// Same original nearest-first order; unique borrowed loop shared with native policy.
pub fn parents(path:&str)->Vec<String>{let mut rows=Vec::new();crate::raw_ownership_policy::visit_parents_using(path,&mut crate::key_policy_control::Compatibility,&mut|path,_|{rows.push(path.to_owned());Ok(())}).unwrap_or_else(|never|match never{});rows}

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
        OrdMap {
            idx: HashMap::new(),
            items: Vec::new(),
        }
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
    /// The vars of `GLOB` declared through `GLOBAL_*` macros: name -> (vtype, is_list). Kept apart from `members` on purpose: a member is
    /// something the write checks (`raw_write`) police, and the GLOB vars have their own rules (stored_refs); this map only answers "is there
    /// such a global" for an accessor that names one (`rel_set(GLOB, nameof(GLOB.x), ...)`).
    pub globals: HashMap<String, (String, bool)>,
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

// Unique cache plumbing lives outside the legacy semantic Index/model.
pub use crate::incr::{sharded_facts,sharded_keyed};

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
            IdxEv::Member {
                owner,
                vtype,
                is_list,
                name,
            } => {
                members.push((owner, name, vtype, *is_list));
                structure.push((0, owner, name, vtype, *is_list));
            }
            IdxEv::Decl {
                owner,
                name,
                macro_name,
                ..
            } => structure.push((1, owner, name, macro_name, false)),
            IdxEv::Registry(t) => structure.push((2, t, "", "", false)),
            IdxEv::Global {
                name,
                vtype,
                is_list,
            } => {
                members.push(("GLOBAL", name, vtype, *is_list));
                structure.push((3, name, vtype, "", *is_list));
            }
        }
    }
    let (h_members, h_struct) = (incr::ctx_key(&members), incr::ctx_key(&structure));
    FileIdx {
        events,
        h_members,
        h_struct,
    }
}

/// Actual collection growth envelopes; no cost is charged for an unchanged map.
/// A new hash table may double its power-of-two bucket array; the old live table
/// has already been funded. Strings moved out of an event are not cloned here.
pub(crate) fn map_room<C:crate::key_policy_control::Control,K,V>(map:&HashMap<K,V>,c:&mut C)->Result<(),C::Error>{if C::CHECKED&&map.len()==map.capacity(){crate::key_policy_control::reserve(c,||map.capacity().checked_add(1)?.checked_next_power_of_two()?.checked_mul(2)?.max(4).checked_mul(std::mem::size_of::<(K,V)>().checked_add(1)?)?.checked_add(64))?;}Ok(())}
fn vec_room<C:crate::key_policy_control::Control,T>(v:&Vec<T>,c:&mut C)->Result<(),C::Error>{if C::CHECKED&&v.len()==v.capacity(){crate::key_policy_control::reserve(c,||v.capacity().checked_mul(2)?.max(4).checked_mul(std::mem::size_of::<T>())?.checked_add(64))?;}Ok(())}
pub(crate) fn ord_room<C:crate::key_policy_control::Control,V>(m:&OrdMap<V>,key:&str,c:&mut C)->Result<(),C::Error>{if m.get(key).is_none(){map_room(&m.idx,c)?;vec_room(&m.items,c)?;crate::key_policy_control::reserve(c,||key.len().checked_mul(2)?.checked_add(64))?;}Ok(())}

impl Index {
    pub fn new() -> Index {
        Index {
            registry: FLYWEIGHT_TYPES.iter().map(|s| s.to_string()).collect(),
            ..Index::default()
        }
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

    fn apply_owned(&mut self,ev:IdxEv){self.apply_owned_using(ev,&mut crate::key_policy_control::Compatibility).unwrap_or_else(|never|match never{})}
    pub(crate) fn apply_owned_using<C:crate::key_policy_control::Control>(&mut self,ev:IdxEv,c:&mut C)->Result<(),C::Error>{
        c.checkpoint()?;
        // Fund only allocations this exact event will perform, before the original match.
        if C::CHECKED{match &ev{
         IdxEv::Member{owner,vtype,name,..}=>{
          if let Some(inner)=self.members.get(owner){if !inner.contains_key(name){map_room(inner,c)?;}}
          else{map_room(&self.members,c)?;map_room(&HashMap::<String,(String,bool)>::new(),c)?;crate::key_policy_control::reserve(c,||owner.len().checked_add(32))?;}
          crate::key_policy_control::reserve(c,||name.len().checked_add(vtype.len())?.checked_add(64))?;
          if let Some(rows)=self.name_decls.get(name){vec_room(rows,c)?;}else{map_room(&self.name_decls,c)?;crate::key_policy_control::reserve(c,||std::mem::size_of::<(String,String,bool)>().checked_add(32))?;}
         },
         IdxEv::Decl{owner,name,..}=>{ord_room(&self.decls,owner,c)?;if let Some(inner)=self.decls.get(owner){ord_room(inner,name,c)?;}else{ord_room(&OrdMap::<Decl>::new(),name,c)?;}},
         IdxEv::Registry(_)=>vec_room(&self.registry,c)?,
         IdxEv::Global{name,..}=>if !self.globals.contains_key(name){map_room(&self.globals,c)?;},
        }}
        match ev {
            IdxEv::Member {
                owner,
                vtype,
                is_list,
                name,
            } => {
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
            IdxEv::Decl {
                owner,
                name,
                macro_name,
                opts,
                rel,
                line,
            } => {
                let inner = self.decls.entry_or_insert_with(&owner, OrdMap::new);
                inner.insert(
                    &name,
                    Decl {
                        macro_name,
                        opts,
                        rel,
                        line: line as usize,
                    },
                );
            }
            IdxEv::Registry(t) => self.registry.push(t),
            IdxEv::Global {
                name,
                vtype,
                is_list,
            } => {
                self.globals.insert(name, (vtype, is_list));
            }
        }
        c.checkpoint()
    }

    pub fn add_member(&mut self, owner: &str, segs: &str, name: &str) {
        let (vtype, is_list) = member_parts(segs);
        self.apply(&IdxEv::Member {
            owner: owner.to_string(),
            vtype,
            is_list,
            name: name.to_string(),
        });
    }

    /// One entry in `owner`'s ownership()/relations() list, recorded under the kind's old macro
    /// name. An `owns()` with no policy only annotates (`ANNOTATE`).
    pub fn add_decl(
        &mut self,
        owner: &str,
        func: &str,
        name: &str,
        opts: &str,
        rel: &str,
        no: usize,
    ) {
        self.apply(&decl_ev(owner, func, name, opts, rel, no));
    }

    pub fn index_file(&mut self, rel: &str, raw: &View, code: &View) {
        for ev in file_events(rel, raw, code) {
            self.apply(&ev);
        }
    }

    /// `(declaring type, vtype, is_list)` for var `name` as seen from type `owner`, or None.
    pub fn member(&self,owner:&str,name:&str)->Option<Member>{self.member_using(owner,name,&mut crate::key_policy_control::Compatibility).unwrap_or_else(|never|match never{})}
    pub fn member_using<C:crate::key_policy_control::Control>(&self,owner:&str,name:&str,c:&mut C)->Result<Option<Member>,C::Error>{let mut found=None;crate::raw_ownership_policy::visit_parents_until_using(owner,c,&mut|parent,c|{if let Some((vtype,is_list))=self.members.get(parent).and_then(|m|m.get(name)){crate::key_policy_control::temporary(c,4,||parent.len().checked_add(vtype.len())?.checked_mul(16)?.checked_add(1024))?;found=Some(Member{declared_on:parent.to_owned(),vtype:vtype.to_owned(),is_list:*is_list});return Ok(false)}Ok(true)})?;Ok(found)}

    /// `(declaring type, declaration)` of `name` as seen from type `owner`, or None.
    pub fn decl(&self,owner:&str,name:&str)->Option<(String,&Decl)>{self.decl_using(owner,name,&mut crate::key_policy_control::Compatibility).unwrap_or_else(|never|match never{})}
    pub fn decl_using<'a,C:crate::key_policy_control::Control>(&'a self,owner:&str,name:&str,c:&mut C)->Result<Option<(String,&'a Decl)>,C::Error>{let mut found=None;crate::raw_ownership_policy::visit_parents_until_using(owner,c,&mut|parent,c|{if let Some(decl)=self.decls.get(parent).and_then(|m|m.get(name)){crate::key_policy_control::temporary(c,4,||parent.len().checked_mul(16)?.checked_add(1024))?;found=Some((parent.to_owned(),decl));return Ok(false)}Ok(true)})?;Ok(found)}

    pub fn is_registry(&self,vtype:&str)->bool{self.is_registry_using(vtype,&mut crate::key_policy_control::Compatibility).unwrap_or_else(|never|match never{})}
    pub fn is_registry_using<C:crate::key_policy_control::Control>(&self,vtype:&str,c:&mut C)->Result<bool,C::Error>{for root in &self.registry{c.checkpoint()?;if under(vtype,std::slice::from_ref(root)){return Ok(true)}}Ok(false)}
    pub fn is_entity(&self,vtype:&str)->bool{self.is_entity_using(vtype,&mut crate::key_policy_control::Compatibility).unwrap_or_else(|never|match never{})}
    pub fn is_entity_using<C:crate::key_policy_control::Control>(&self,vtype:&str,c:&mut C)->Result<bool,C::Error>{c.checkpoint()?;Ok(under(vtype,ENTITY_ROOTS)&&!self.is_registry_using(vtype,c)?)}

}

/// A local variable's declared type: `Some(Some(path))` typed, `Some(None)` declared without a
/// type, absent when unknown (the Python dict with `None` values).
pub type LocalTypes = HashMap<String, Option<String>>;

/// `proc_scopes(code)`: calls `f(line number, line, owner type, proc name, locals)` for every
/// proc body line (blank lines included, as the generator yielded them).
pub fn proc_scopes(code: &View, mut f: impl FnMut(usize, &str, &str, &str, &LocalTypes)) {
    proc_scopes_using(code,&mut crate::key_policy_control::Compatibility,&mut|no,line,owner,proc,locals,_|{f(no,line,owner,proc,locals);Ok(())}).unwrap_or_else(|never|match never{})
}
fn scope_local_room<C:crate::key_policy_control::Control>(locals:&LocalTypes,width:&mut usize,name:&str,ty:Option<&str>,replace:bool,c:&mut C)->Result<(),C::Error>{
 if !C::CHECKED{return Ok(())}
 let key=name.len().checked_add(32).ok_or_else(||c.overflow())?;
 let value=ty.map_or(Some(0),|ty|ty.trim_start_matches('/').len().checked_add(33)).ok_or_else(||c.overflow())?;
 let next=match locals.get(name){Some(old)if replace=>width.checked_sub(old.as_ref().map_or(0,|s|s.len()+32)).and_then(|n|n.checked_add(value)),Some(_)=>Some(*width),None=>width.checked_add(key).and_then(|n|n.checked_add(value))}.ok_or_else(||c.overflow())?;
 // Existing/new owner+locals, temporary duplicate entry key and replacement type,
 // plus old/new geometric hash tables coexist until this exact insertion finishes.
 crate::key_policy_control::temporary(c,1,||locals.capacity().checked_add(1)?.checked_next_power_of_two()?.checked_mul(4)?.checked_mul(std::mem::size_of::<(String,Option<String>)>())?.checked_add((*width).max(next))?.checked_add(key)?.checked_add(value)?.checked_add(1024))?;*width=next;Ok(())
}

pub fn proc_scopes_using<C:crate::key_policy_control::Control>(code:&View,c:&mut C,f:&mut impl FnMut(usize,&str,&str,&str,&LocalTypes,&mut C)->Result<(),C::Error>)->Result<(),C::Error>{
    let mut owner: Option<String> = None;
    let mut proc_name = String::new();
    let mut local_types: LocalTypes = HashMap::new();
    let mut local_bytes=0usize;
    for(no,line)in code.numbered(){c.checkpoint()?;
        let first = line.chars().next();
        if matches!(first, Some('"') | Some('\'')) {
            continue; // the tail of a multi-line string
        }
        if first.map(|c| !is_py_space(c)).unwrap_or(false) {
            match crate::key_policy_control::captures_match_static(c,PROC_DEF_SOURCE,line,||&PROC_DEF)? {
                Some(m) if !line.starts_with('#') => {
                    crate::key_policy_control::temporary(c,1,||local_bytes.checked_add(m.whole().len().checked_mul(16)?)?.checked_add(1024))?;
                    owner = Some(m.s(1).to_string());
                    proc_name = m.s(2).to_string();
                    local_types = HashMap::new();
                    if C::CHECKED{local_bytes=m.s(1).len().checked_add(m.s(2).len()).ok_or_else(||c.overflow())?;}
                    let params = m.s(3);
                    for tm in crate::key_policy_control::captures_all_static(c,TYPED_NAME_SOURCE,params,||&TYPED_NAME)? {c.checkpoint()?;scope_local_room(&local_types,&mut local_bytes,tm.s(2),Some(tm.s(1)),true,c)?;
                        local_types.insert(
                            tm.s(2).to_string(),
                            Some(format!("/{}", tm.s(1).trim_start_matches('/'))),
                        );
                    }
                    for am in crate::key_policy_control::captures_all_static(c,PARAM_NAME_SOURCE,params,||&PARAM_NAME)? {c.checkpoint()?;scope_local_room(&local_types,&mut local_bytes,am.s(1),None,false,c)?;
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
        let Some(own) = owner.as_deref() else {
            continue;
        };
        for tm in crate::key_policy_control::captures_all_static(c,TYPED_NAME_SOURCE,line,||&TYPED_NAME)? {c.checkpoint()?;
            let start = tm.start(0);
            if line[..start].ends_with("var/") || line[start..].starts_with("var/") {
                scope_local_room(&local_types,&mut local_bytes,tm.s(2),Some(tm.s(1)),true,c)?;
                local_types.insert(
                    tm.s(2).to_string(),
                    Some(format!("/{}", tm.s(1).trim_start_matches('/'))),
                );
            }
        }
        for lm in crate::key_policy_control::captures_all_static(c,LOCAL_DECL_SOURCE,line,||&LOCAL_DECL)? {c.checkpoint()?;scope_local_room(&local_types,&mut local_bytes,lm.s(1),None,false,c)?;
            local_types.entry(lm.s(1).to_string()).or_insert(None);
        }
        f(no,line,own,&proc_name,&local_types,c)?;
    }
    c.checkpoint()
}

/// The static type of a `a.b.` receiver chain ("" chain = a bare write -> the owner), or None
/// when unknown.
pub fn receiver_type(
    idx: &Index,
    chain: &str,
    owner: &str,
    local_types: &LocalTypes,
) -> Option<String> {
    receiver_type_using(idx,chain,owner,local_types,&mut crate::key_policy_control::Compatibility).unwrap_or_else(|never|match never{})
}
pub fn receiver_type_using<C:crate::key_policy_control::Control>(idx:&Index,chain:&str,owner:&str,local_types:&LocalTypes,c:&mut C)->Result<Option<String>,C::Error>{
    c.checkpoint()?;crate::key_policy_control::temporary(c,4,||chain.len().checked_mul(32)?.checked_add(owner.len().checked_mul(16)?)?.checked_add(1024))?;
    if chain.is_empty() {
        return Ok(Some(owner.to_string()));
    }
    let segs: Vec<&str> = chain
        .trim_end_matches('.')
        .split('.')
        .map(|s| s.trim_end_matches('?'))
        .collect();
    if segs == ["src"] {
        return Ok(Some(owner.to_string()));
    }
    if segs.len() != 1 {
        return Ok(None);
    }
    let name = segs[0];
    if let Some(t) = local_types.get(name) {
        return Ok(t.clone());
    }
    Ok(idx.member_using(owner,name,c)?.map(|m|m.vtype))
}

/// True when the assigned value is `new /entity/type(...)` (not a value type such as an image).
pub fn creates_entity(rhs: &str) -> bool {creates_entity_using(rhs,&mut crate::key_policy_control::Compatibility).unwrap_or_else(|never|match never{})}
pub fn creates_entity_using<C:crate::key_policy_control::Control>(rhs:&str,c:&mut C)->Result<bool,C::Error>{
    let head = rhs.split("//").next().unwrap_or("");
    let Some(m) = crate::key_policy_control::captures_match_static(c,NEW_VALUE_SOURCE,head,||&NEW_VALUE)? else {
        return Ok(false);
    };
    if !m.matched(1) {
        return Ok(false); // implicit type: the declared type decides (already handled)
    }
    Ok(!under(m.s(1), VALUE_TYPES))
}

/// True when the written value (or key) is recognisably an entity: `src`, a `new` expression, or a
/// local/argument declared with an entity type. `registry_roots` is `REGISTRY_ROOTS` (the index's
/// registry list, which `main()` assigns before any check).
pub fn puts_object(rhs: &str, local_types: &LocalTypes, registry_roots: &[String]) -> bool {
    puts_object_using(rhs,local_types,registry_roots,&mut crate::key_policy_control::Compatibility).unwrap_or_else(|never|match never{})
}
pub fn puts_object_using<C:crate::key_policy_control::Control>(rhs:&str,local_types:&LocalTypes,registry_roots:&[String],c:&mut C)->Result<bool,C::Error>{
    c.checkpoint()?;crate::key_policy_control::temporary(c,5,||rhs.len().checked_mul(16)?.checked_add(1024))?;
    let mut text = rhs.split("//").next().unwrap_or("").to_string();
    // A proc call's arguments are not the written value: TIME_NOW(src, ...) writes a number.
    loop {c.checkpoint()?;crate::key_policy_control::temporary(c,5,||text.len().checked_mul(16)?.checked_add(1024))?;
        let next = crate::key_policy_control::replace_static(c,CALL_ARGS_SOURCE,&text,"0",||&CALL_ARGS)?;
        if next == text {
            break;
        }
        text = next;
    }
    for m in crate::key_policy_control::captures_all_static(c,OBJ_TOKEN_SOURCE,&text,||&OBJ_TOKEN)? {c.checkpoint()?;
        let tok = m.s(1);
        if tok == "src" || tok == "new" {
            return Ok(true);
        }
        if let Some(Some(t)) = local_types.get(tok) {
            if !t.is_empty() && under(t, ENTITY_ROOTS) && !under(t, registry_roots) {
                return Ok(true);
            }
        }
    }
    Ok(false)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parents_include_implicit_roots() {
        assert_eq!(
            parents("/obj/item"),
            ["/obj/item", "/obj", "/atom/movable", "/atom", "/datum"]
        );
        assert_eq!(parents("/datum/x/y"), ["/datum/x/y", "/datum/x", "/datum"]);
        assert_eq!(parents("/area"), ["/area", "/atom", "/datum"]);
        assert!(parents("nothing").is_empty());
    }

    #[test]
    fn index_reads_members_and_decls() {
        let f = SourceFile::from_text(
            "code/a.dm",
            "/obj/thing\n\tvar/datum/foo/bar\n\tvar/tmp/list/obj/items\n/obj/thing/ownership()\n\t. += owns(nameof(bar))\n\n/obj/thing/var/obj/baz\n",
        );
        let idx = Index::build(&[&f]);
        assert_eq!(idx.member("/obj/thing", "bar").unwrap().vtype, "/datum/foo");
        let items = idx.member("/obj/thing", "items").unwrap();
        assert!(items.is_list && items.vtype == "/obj");
        assert_eq!(idx.decl("/obj/thing", "bar").unwrap().1.macro_name, "OWN");
        assert!(idx.member("/obj/thing", "baz").is_some());
    }

    #[test]
    fn global_macros_declare_vars_of_glob() {
        let f = SourceFile::from_text(
            "code/g.dm",
            "GLOBAL_DATUM(box, /obj/thing)
GLOBAL_DATUM_INIT(made, /datum/foo, new)
GLOBAL_LIST_EMPTY(pool)
GLOBAL_LIST_INIT_TYPED(typed, /obj/item, list())
GLOBAL_VAR(plain)
GLOBAL_ALIST_EMPTY(map)
",
        );
        let idx = Index::build(&[&f]);
        let m = |n: &str| {
            idx.globals
                .get(n)
                .cloned()
                .unwrap_or_else(|| panic!("no global {}", n))
        };
        assert_eq!(m("box"), ("/obj/thing".to_string(), false));
        assert_eq!(m("made").0, "/datum/foo");
        assert_eq!(m("pool"), (String::new(), true));
        assert_eq!(m("typed"), ("/obj/item".to_string(), true));
        assert_eq!(m("plain"), (String::new(), false));
        assert_eq!(m("map").0, "/alist");
        assert!(!idx.globals.contains_key("absent"));
        // They are globals, not members of any type: the write checks do not see them.
        assert!(idx.member(GLOB_TYPE, "box").is_none() && !idx.name_decls.contains_key("box"));
    }
}

#[cfg(test)]
mod streaming_relation_projection_tests {
    use super::*;
    #[test]
    fn event_visitor_refusal_stops_before_later_events_and_vec_compatibility_is_exact() {
        let file=SourceFile::from_text("code/stream.dm","/datum/holder\n    var/a\n    var/b\n/datum/holder/relations()\n    . += rel_one(nameof(link))\n");
        let mut visits = 0;
        let denied = visit_file_events(&file.rel, file.raw(), file.code(), |_| {
            visits += 1;
            Err("admission denied".into())
        });
        assert_eq!(visits, 1);
        assert_eq!(denied.unwrap_err(), "admission denied");
        let mut observed = Vec::new();
        visit_file_events(&file.rel, file.raw(), file.code(), |e| {
            observed.push(e);
            Ok(())
        })
        .unwrap();
        assert_eq!(observed, file_events(&file.rel, file.raw(), file.code()));
    }
}

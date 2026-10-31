//! Original reactive read result facts only: no semantic tree/parser/cache.
use std::collections::{BTreeMap,BTreeSet};
/// A supported numeric lookup argument, kept in the actual caller's coordinate system.
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord, Hash, serde::Serialize, serde::Deserialize)]
pub enum LookupArgument {
    Literal(String),
    Path { root: String, path: Vec<String> },
}
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord, Hash, serde::Serialize, serde::Deserialize)]
pub struct LookupBound {
    pub registry: String,
    pub identity_key: String,
    pub lookup: String,
    pub argument: LookupArgument,
}
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord, Hash, serde::Serialize, serde::Deserialize)]
pub struct LookupRead {
    pub binding: LookupBound,
    pub field: String,
}
impl LookupRead {
    pub fn key(&self) -> String {
        // Stable across runs; do not use a process-randomized hash or a collection position.
        let text = format!("{:?}", self);
        let hash = text.bytes().fold(14695981039346656037u64, |h, b| (h ^ u64::from(b)).wrapping_mul(1099511628211));
        format!("lookup_read_{hash:016x}")
    }
}
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord, Hash, serde::Serialize, serde::Deserialize)]
pub enum ReadKind {
    /// A var on an entity.
    Var,
    /// An accessor proc standing for a producer key (`READS_AS`).
    Accessor,
    /// `native("name")`.
    Native,
    /// A system's tracked var read through its `SYSTEM_ACCESSOR` proc.
    System,
    /// A declared numeric lookup, bound to actual producers by the engine.
    Lookup(Box<LookupRead>),
}

/// One read: a var (or key) on the entity reached from `root` through `hops`.
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord, Hash, serde::Serialize, serde::Deserialize)]
pub struct Read {
    /// `holder`, or the context hop (`actor`, `held`, `target`, ...).
    pub root: String,
    /// Relation vars crossed from the root, in order; a list relation reads `name[]`.
    pub hops: Vec<String>,
    /// The var read, or the key for an accessor.
    pub var: String,
    /// The type that declares `var` (empty for keys).
    pub owner: String,
    pub kind: ReadKind,
    /// FALSE when a hop crossed a var that is not a declared relation.
    pub hop_ok: bool,
}

impl Read {
    /// `cell.charge` on the holder, `@actor:hands[].name` through a context hop.
    pub fn key(&self) -> String {
        let mut s = String::new();
        if self.root != "holder" {
            s.push('@');
            s.push_str(&self.root);
            s.push(':');
        }
        for h in &self.hops {
            s.push_str(h);
            s.push('.');
        }
        s.push_str(&self.var);
        s
    }
}

/// Something the analysis could not resolve, or a rule violation found while walking a body.
#[derive(Clone, Debug, PartialEq, Eq, serde::Serialize)]
pub struct Diag {
    /// `unannotated_global`, `dynamic_read`, `unknown_field`, `unknown_call`, `hop_not_relation`, `ffi_call`.
    pub rule: &'static str,
    /// Found only by the closed walk: in an override a virtual call reaches, or beneath an engine-internal body the lints' walk skips.
    pub closed_only: bool,
    pub rel: String,
    pub line: u32,
    pub msg: String,
}

/// A write or an observable call in a followed body (the purity check classifies these).
#[derive(Clone, Debug, PartialEq, Eq, serde::Serialize)]
pub struct Effect {
    /// `assign` (a var write), `call`.
    pub kind: &'static str,
    pub name: String,
    /// The static type of the receiver for an `assign`; "" otherwise.
    pub owner: String,
    /// The proc the effect sits in (a setter's own write is not its caller's).
    pub proc: String,
    pub rel: String,
    pub line: u32,
}

/// Reading ordered collections back in bulk: the stored order is the sorted order, and building a tree from a sorted run is linear (one
/// insert at a time is not). Same bytes as serde's own encoding.
mod bulk {
    use serde::{Deserialize, Deserializer};
    use std::collections::{BTreeMap, BTreeSet};

    pub fn set<'de, D: Deserializer<'de>, T: Deserialize<'de> + Ord>(d: D) -> Result<BTreeSet<T>, D::Error> {
        Ok(Vec::<T>::deserialize(d)?.into_iter().collect())
    }

    pub fn map<'de, D: Deserializer<'de>, K: Deserialize<'de> + Ord, V: Deserialize<'de>>(d: D) -> Result<BTreeMap<K, V>, D::Error> {
        Ok(Vec::<(K, V)>::deserialize(d)?.into_iter().collect())
    }
}

#[derive(Default, Debug, Clone, serde::Serialize)]
#[cfg_attr(feature="legacy-sem",derive(serde::Deserialize))]
pub struct ReadSet {
    #[serde(deserialize_with = "bulk::set")]
    pub reads: BTreeSet<Read>,
    /// Context scalar/object fields read through the act (`A.dt` -> "dt"), with a line each.
    #[serde(deserialize_with = "bulk::map")]
    pub ctx_fields: BTreeMap<String, (String, u32)>,
    /// Where each read was first seen: (file, line).
    #[serde(deserialize_with = "bulk::map")]
    pub sites: BTreeMap<Read, (String, u32)>,
    pub diags: Vec<Diag>,
    /// Failures of declared numeric lookup contracts, also present in diags.
    pub lookup_diags: Vec<Diag>,
    pub effects: Vec<Effect>,
    /// `type::proc` bodies the walk followed (for the graph and for incremental invalidation).
    #[serde(deserialize_with = "bulk::set")]
    pub followed: BTreeSet<String>,
    /// Procs in an opaque (engine-internal) directory the walk reached but did not enter, with the call site: what they read is
    /// invisible to the graph, so a consumer that calls one cannot prove its inputs complete (`gen deps`, `untracked_inputs`).
    #[serde(deserialize_with = "bulk::map")]
    pub opaque: BTreeMap<String, (String, u32)>,
    /// Reads the framework makes of its own state: an engine body reading a var an engine file declares (`holder.rx`, the stat record).
    /// They stay in `reads` (the subscriptions are complete) but are not inputs a stat or a look can be stale on: `gen deps` and the lints
    /// leave them out. Closed walk only; a read also made from outside the engine is not in this set.
    #[serde(deserialize_with = "bulk::set")]
    pub internal: BTreeSet<Read>,
    /// Where a `read_once(...)` sample sits (file, line) in a body the walk entered. A draw or a stat input must not sample: the look or the
    /// value is made from it once and never follows (`untracked_inputs` rule `sampled_in_look`).
    #[serde(deserialize_with = "bulk::set")]
    pub sampled: BTreeSet<(String, u32)>,
}

impl ReadSet {
    pub fn keys(&self) -> BTreeSet<String> {
        self.reads.iter().map(|r| r.key()).collect()
    }

    /// The vars the walked bodies write, as `owner.var` (a `set_<v>` call is a write of `v`).
    pub fn writes(&self) -> BTreeSet<String> {
        let mut out = BTreeSet::new();
        for e in &self.effects {
            match e.kind {
                "assign" => {
                    out.insert(format!("{}.{}", e.owner, e.name));
                }
                "call" if e.name.starts_with("set_") => {
                    out.insert(format!("{}.{}", e.owner, &e.name[4..]));
                }
                _ => {}
            }
        }
        out
    }
}


/// Original read policy's value/object boundary. Prefix testing is equivalent
/// to the old temporary format!("{}/", value_type), without allocating it.
pub fn is_object_type(declared:&str)->bool{
 const VALUES:&[&str]=&["/list","/text","/num","/string","/icon","/sound","/mutable_appearance","/image","/matrix","/regex","/savefile","/client","/world","/exception","/path","/color","/alist"];
 !declared.is_empty()&&!VALUES.iter().any(|v|declared==*v||declared.strip_prefix(v).is_some_and(|tail|tail.starts_with('/')))
}

pub const IMPURE_CALLS: &[&str] = &[
    "hold", "hold_until", "hold_override", "release", "release_all", "grant", "revoke", "om_grant", "om_grant_for", "publish_change", "qdel", "act_done", "act_cancel", "build_all_button_icons", "build_button_icon",
];
pub const MESSAGE_CALLS: &[&str] = &["to_chat", "visible_message", "audible_message", "say", "emote", "show_message", "playsound", "play_sfx"];
pub fn effect_call(name: &str) -> bool {
    IMPURE_CALLS.contains(&name)
        || MESSAGE_CALLS.contains(&name)
        || name.starts_with("rel_")
        || name.starts_with("set_")
        || name.starts_with("log_")
        || matches!(name, "stack_trace" | "crash_with" | "WARNING" | "warning" | "notice" | "testing" | "message_admins" | "to_world" | "admin_notice" | "fx_sparks" | "after" | "every" | "world_next_tick" | "add_overlay" | "cut_overlay" | "cut_overlays")
}

pub fn framework_file(rel: &str) -> bool {
    ENGINE_DIRS.iter().any(|d| rel.starts_with(d)) || rel.starts_with("code/controllers/kernel/") || rel == "code/datums/datum.dm" || is_test_code(rel)
}

pub fn is_test_code(rel: &str) -> bool {
    rel.starts_with("code/tests/") || rel.starts_with("code/modules/unit_tests/")
}

pub fn is_builtin_name(name: &str) -> bool {
    matches!(name, "type" | "parent_type" | "vars" | "tag" | "Cross" | "Uncross" | "Entered" | "Exited" | "New" | "Del" | "Topic" | "Move" | "Crossed" | "Uncrossed" | "contents" | "loc" | "x" | "y" | "z" | "usr")
}

pub const ENGINE_DIRS: &[&str] = &["code/datums/sys/", "code/datums/om/", "code/modules/tgui/", "code/datums/capabilities/", "code/datums/reactions/", "code/datums/ownership/", "code/engine/", "code/__defines/verdigris/"];
/// SAME original narrowing iteration/first-candidate policy. The std HashMap
/// values iterator and each authored Vec order remain observable; no sorting or
/// union changes the original algorithm. Legacy None adds no admission work.
pub fn try_narrow_candidates<E>(narrow:&std::collections::HashMap<String,Vec<String>>,ty:&str,mut subtype:impl FnMut(&str,&str)->Result<bool,E>,mut admit:Option<&mut dyn FnMut(&mut Vec<String>,&str)->Result<(),E>>)->Result<Option<Vec<String>>,E>{
 let mut out=Vec::new();
 for list in narrow.values(){for candidate in list{if subtype(candidate,ty)?{if let Some(admit)=admit.as_mut(){admit(&mut out,candidate)?;}out.push(candidate.clone());}}}
 Ok((!out.is_empty()).then_some(out))
}

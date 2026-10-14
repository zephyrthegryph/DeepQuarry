//! Generated reads: what a handler reads, derived from its body on the AST.
//!
//! A handler is a proc the engine calls to evaluate a condition, requirement, output or hook
//! (`x(datum/act/A)`), or a standard output (`draw`, `tgui_data`, `push_to_rust`, `should_run`).
//! [`ReadsEngine::analyze`] walks its body and returns every read it can prove, following (per the
//! graph contract, doc/rewrite/final_api.html section 7):
//!
//! * the holder's own vars, and hops through declared relations (`REL/OWN/...`);
//! * procs of the same type and of a hop's type (followed), `..()` parents;
//! * global helpers: through `READS_FROM(arg)` in the lints' targeted walk; the closed walk walks every global proc like any proc, every
//!   parameter bound to what the call passed (`PROC_SUMMARY` only for a body that cannot be walked: `vars[]`, `call()`, a Verdigris call);
//! * accessor procs with `READS_AS(proc, key, via = ...)` (not followed: they stand for their key);
//! * context hops `A.actor`, `A.held`, `A.target` (typed hops from the act context).
//!
//! The result is a static over-approximation: every read anywhere in the body subscribes, whatever
//! branch it sits in. `A.args` and `world.time` never subscribe. In the closed walk a read of global state (`GLOB.x`, `SSx.y`, a real
//! global) is classified (`sem/globals.rs`): constant after init (written only while the world boots), a tracked var of a system (a system
//! read, which publishes), the framework's own bookkeeping (a shared cache, engine state read by engine code), or an `untracked_global`.
//! What it cannot resolve is reported as a [`Diag`]: `untracked_global`, `vars[]`, `call()`, a Verdigris call, a hop through a var that is
//! not a declared relation (and, in the targeted walk, an unannotated global call).

use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};

use dreammaker::ast::{AssignOp, Block, Expression, Follow, Statement, Term, VarType};
use dreammaker::objtree::ProcRef;

use super::ast::{as_ident, stmt_blocks, stmt_exprs, strip_parens};
use super::decls::{split_args, Decls};
use super::Sem;

/// Engine-internal directories the lints' walk does not enter (dispatchers that read `vars[]` by design, the tgui plumbing, the Verdigris
/// bindings). The closed walk ([`ReadsEngine::closed`]) enters them; what it finds there or beneath them is `closed_only`.
pub const ENGINE_DIRS: &[&str] = &["code/datums/sys/", "code/datums/om/", "code/modules/tgui/", "code/datums/capabilities/", "code/datums/reactions/", "code/datums/ownership/", "code/engine/", "code/__defines/verdigris/"];

/// Maximum depth of followed procs (a guard against pathological recursion, not a semantic limit).
const MAX_DEPTH: usize = 24;
/// Longest relation chain a read may cross.
const MAX_HOPS: usize = 4;

/// Procs whose call inside a pure body is an effect (purity check). `set_<var>` and `rel_*` are matched by prefix.
pub const IMPURE_CALLS: &[&str] = &[
    "hold", "hold_until", "hold_override", "release", "release_all", "grant", "revoke", "om_grant", "om_grant_for", "publish_change", "qdel", "act_done", "act_cancel",
];
/// Calls that talk to a player: forbidden in a pure body (the no-message guard).
pub const MESSAGE_CALLS: &[&str] = &["to_chat", "visible_message", "audible_message", "say", "emote", "show_message", "playsound", "play_sfx"];

/// Files that declare the framework's own state besides [`ENGINE_DIRS`]: the kernel (`Kernel`, its work tables) and the base datum
/// (`gc_destroyed`, `rx`). An engine body reading a var declared in one of them is the framework reading itself.
/// The file whose procs resolve entity handles (see `global_internal`).
const HANDLE_RESOLUTION_FILE: &str = "code/engine/time/handles.dm";

pub fn framework_file(rel: &str) -> bool {
    ENGINE_DIRS.iter().any(|d| rel.starts_with(d)) || rel.starts_with("code/controllers/kernel/") || rel == "code/datums/datum.dm" || is_test_code(rel)
}

/// Test-only code (the unit tests and the test driver): compiled out of production, so never an input of a stat or a look.
pub fn is_test_code(rel: &str) -> bool {
    rel.starts_with("code/tests/") || rel.starts_with("code/modules/unit_tests/")
}

/// Calls whose body is an effect or a diagnostic: the closed walk does not follow them. What they read is not an input of the value
/// being computed (a `qdel()` runs the destroy machinery, `to_chat()` the chat service, `set_x()` a setter), and the call itself is
/// recorded as an effect for the purity check.
pub fn effect_call(name: &str) -> bool {
    IMPURE_CALLS.contains(&name)
        || MESSAGE_CALLS.contains(&name)
        || name.starts_with("rel_")
        || name.starts_with("set_")
        || name.starts_with("log_")
        || matches!(name, "stack_trace" | "crash_with" | "WARNING" | "warning" | "notice" | "testing" | "message_admins" | "to_world" | "admin_notice" | "fx_sparks" | "after" | "every" | "world_next_tick")
}

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
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
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
#[derive(Clone, Debug)]
pub struct LookupDeclaration {
    pub registry: String,
    pub identity_key: String,
    pub argument: usize,
    pub result: String,
}

#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
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
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
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
#[derive(Clone, Debug, PartialEq, Eq)]
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
#[derive(Clone, Debug, PartialEq, Eq)]
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

#[derive(Default, Debug, Clone)]
pub struct ReadSet {
    pub reads: BTreeSet<Read>,
    /// Context scalar/object fields read through the act (`A.dt` -> "dt"), with a line each.
    pub ctx_fields: BTreeMap<String, (String, u32)>,
    /// Where each read was first seen: (file, line).
    pub sites: BTreeMap<Read, (String, u32)>,
    pub diags: Vec<Diag>,
    /// Failures of declared numeric lookup contracts, also present in diags.
    pub lookup_diags: Vec<Diag>,
    pub effects: Vec<Effect>,
    /// `type::proc` bodies the walk followed (for the graph and for incremental invalidation).
    pub followed: BTreeSet<String>,
    /// Procs in an opaque (engine-internal) directory the walk reached but did not enter, with the call site: what they read is
    /// invisible to the graph, so a consumer that calls one cannot prove its inputs complete (`gen deps`, `untracked_inputs`).
    pub opaque: BTreeMap<String, (String, u32)>,
    /// Reads the framework makes of its own state: an engine body reading a var an engine file declares (`holder.rx`, the stat record).
    /// They stay in `reads` (the subscriptions are complete) but are not inputs a stat or a look can be stale on: `gen deps` and the lints
    /// leave them out. Closed walk only; a read also made from outside the engine is not in this set.
    pub internal: BTreeSet<Read>,
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

/// `READS_AS` and `READS_FROM` annotations, resolved to procs.
#[derive(Default)]
pub struct Annotations {
    /// (owner type, proc) -> (key, via).
    pub reads_as: HashMap<(String, String), (String, Option<String>)>,
    /// global proc name -> the param names it reads from (empty = reads nothing).
    pub reads_from: HashMap<String, Vec<String>>,
    pub lookups: HashMap<String, LookupDeclaration>,
    /// Relations declared in `relations()` bodies (`rel_one(nameof(x), ...)` / `rel_many(...)`): type -> vars.
    pub relations: HashMap<String, HashSet<String>>,
    /// `SYSTEM_ACCESSOR(system, proc, nameof(var))`: proc -> (system, var).
    pub accessors: HashMap<String, (String, String)>,
    /// The accessor `cap_keys(CAP_X, KEY = ...)` generates for each state key (`cover_open`): proc -> the key's id name (`COVER_OPEN`).
    /// A call stands for a read of that key on its first argument; the global proc behind it is not followed.
    pub capkey_accessors: HashMap<String, String>,
    /// `PROC_SUMMARY(path, reads = list(...), writes = list(...))`: what a proc the walk cannot enter (a Verdigris FFI call, a `vars[]`
    /// dispatcher) reads and writes on its receiver, declared by hand. The walk takes the summary instead of the body.
    pub summaries: HashMap<(String, String), ProcSummary>,
}

/// A declared summary of a proc that is not walked (see [`Annotations::summaries`]): var names on the receiver.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct ProcSummary {
    pub reads: Vec<String>,
    pub writes: Vec<String>,
}

impl Annotations {
    pub fn get(sem: &Sem, decls: &Decls) -> Annotations {
        let mut a = Annotations::default();
        for m in decls.markers_named("READS_AS") {
            let Some(first) = m.args.first() else { continue };
            let key = m.args.get(1).cloned().unwrap_or_default();
            let via = m.args.iter().skip(2).find_map(|x| {
                let x = x.replace(' ', "");
                x.strip_prefix("via=nameof(").and_then(|r| r.strip_suffix(')')).map(|s| s.to_string())
            });
            let mut owners: Vec<(String, String)> = Vec::new();
            if first.starts_with('/') {
                // /type/proc/name or /type/name
                let (ty, name) = first.rsplit_once('/').unwrap();
                let ty = ty.strip_suffix("/proc").unwrap_or(ty);
                owners.push((if ty.is_empty() { "/".to_string() } else { ty.to_string() }, name.to_string()));
            } else {
                for c in sem.owner_candidates(&m.rel, m.line) {
                    owners.push((c, first.clone()));
                }
            }
            for (ty, name) in owners {
                if sem.ty(&ty).map(|t| t.get().procs.contains_key(&name)).unwrap_or(false) {
                    a.reads_as.insert((ty, name), (key.clone(), via.clone()));
                    break;
                }
            }
        }
        for m in decls.markers_named("PROC_SUMMARY") {
            let Some(first) = m.args.first() else { continue };
            let Some((ty, name)) = first.rsplit_once('/') else { continue };
            let ty = ty.strip_suffix("/proc").unwrap_or(ty);
            let ty = if ty.is_empty() { "/".to_string() } else { ty.to_string() };
            let list = |key: &str| -> Vec<String> {
                m.args
                    .iter()
                    .skip(1)
                    .find_map(|a| a.split_once('=').filter(|(k, _)| k.trim() == key).map(|(_, v)| v.trim().to_string()))
                    .and_then(|v| v.strip_prefix("list(").and_then(|r| r.strip_suffix(')')).map(|r| r.to_string()))
                    .map(|inner| {
                        split_args(&inner).into_iter().map(|x| x.trim().trim_start_matches("nameof(").trim_end_matches(')').trim().to_string()).filter(|x| !x.is_empty()).collect()
                    })
                    .unwrap_or_default()
            };
            a.summaries.insert((ty, name.to_string()), ProcSummary { reads: list("reads"), writes: list("writes") });
        }
        for m in decls.markers_named("READ_LOOKUP") {
            let Some(path) = m.args.first() else { continue };
            let Some(name) = path.strip_prefix("/proc/") else { continue };
            let named = |name: &str| m.args.iter().skip(1).find_map(|a| a.split_once('=').filter(|(k, _)| k.trim() == name).map(|(_, v)| v.trim().to_string()));
            let proc_name = |value: Option<String>| value.and_then(|v| v.strip_prefix("GLOBAL_PROC_REF(").and_then(|x| x.strip_suffix(')')).map(|x| x.trim().to_string()));
            let (Some(registry), Some(identity_key), Some(result)) = (proc_name(named("registry")), proc_name(named("key")), named("result")) else { continue };
            let argument = named("argument").and_then(|s| s.parse::<usize>().ok()).unwrap_or(1);
            if argument == 0 || !result.starts_with('/') { continue; }
            a.lookups.insert(name.to_string(), LookupDeclaration { registry, identity_key, argument: argument - 1, result });
        }
        let mut cap_names: HashMap<String, String> = HashMap::new();
        for m in decls.markers_named("CAPABILITY_TYPE").chain(decls.markers_named("CAPABILITY_DEF")) {
            if let (Some(name), Some(id)) = (m.args.first(), m.args.get(1)) {
                cap_names.insert(id.clone(), name.clone());
            }
        }
        for m in decls.markers_named("cap_keys") {
            let Some(cap_id) = m.args.first() else { continue };
            let Some(cap_name) = cap_names.get(cap_id) else { continue };
            for arg in m.args.iter().skip(1) {
                let key = arg.split('=').next().unwrap_or("").trim().to_string();
                if key.is_empty() {
                    continue;
                }
                a.capkey_accessors.insert(format!("{}_{}", cap_name, key.to_lowercase()), format!("{}_{}", cap_name.to_uppercase(), key));
            }
        }
        for m in decls.markers_named("SYSTEM_ACCESSOR") {
            if let (Some(sys), Some(name), Some(key)) = (m.args.first(), m.args.get(1), m.args.get(2)) {
                let var = key.trim().strip_prefix("nameof(").and_then(|s| s.strip_suffix(')')).unwrap_or(key).trim().to_string();
                a.accessors.insert(name.clone(), (sys.clone(), var));
            }
        }
        // relations() declares rel_one/rel_many vars; ownership() declares owns(nameof(v), ...) vars. Both are written only through the
        // ownership accessors (rel_set/rel_add/own_take/move_into), whose own_field_changed() publishes the var's name to its readers.
        for (proc_name, calls) in [("relations", &["rel_one", "rel_many"][..]), ("ownership", &["owns", "rel_one", "rel_many"][..])] {
        for ty in sem.objtree.iter_types() {
            let Some(tp) = ty.get().procs.get(proc_name) else { continue };
            let path = if ty.get().path.is_empty() { "/".to_string() } else { ty.get().path.clone() };
            for value in &tp.value {
                let Some(code) = &value.code else { continue };
                super::ast::walk_block(code, &mut |e, _| {
                    if let Some((n, args)) = super::ast::as_call(e) {
                        if calls.contains(&n) {
                            if let Some(Expression::Base { term, .. }) = args.first() {
                                if let Term::Call(f, inner) = &term.elem {
                                    if f.as_str() == "nameof" {
                                        if let Some(id) = inner.first().and_then(as_ident) {
                                            a.relations.entry(path.clone()).or_default().insert(id.to_string());
                                        }
                                    }
                                }
                            }
                        }
                    }
                });
            }
        }
        }
        for m in decls.markers_named("READS_FROM") {
            if let Some((owner, name)) = sem.def_at(&m.rel, m.line) {
                let params = m.args.iter().filter(|x| !x.is_empty()).cloned().collect();
                if owner == "/" {
                    a.reads_from.insert(name, params);
                }
            }
        }
        a
    }
}

/// How the engine decides a var is covered by the graph (see [`ReadsEngine::classify`]).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum VarClass {
    /// Tracked, a relation, a stat, or a derived value: publishes on change.
    Reactive,
    /// Never written after init: readable, not reactive.
    Constant,
    /// Anything else: an unknown read.
    Unknown,
}

/// A value during the walk: what static type it has and which entity it is.
#[derive(Clone, Debug)]
struct Val {
    ty: Option<String>,
    root: Root,
    hops: Vec<String>,
    hop_ok: bool,
    /// A list of entities (a list relation): iterating it hops `name[]`.
    list: bool,
}

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
enum Root {
    /// The entity whose handler this is.
    Holder,
    /// A context hop: `A.actor`, `A.held`, `A.target`.
    Ctx(String),
    /// The act context datum itself.
    Act,
    /// Anything untracked (a local, a new object, a global).
    Local,
    Scalar(LookupArgument),
    Lookup(Box<LookupBound>),
    /// Global state: the `GLOB` datum, a real global var, or a datum reached through one (`GLOB.x`, `SSair`). Not an entity the runtime can
    /// subscribe to; a read through it is classified by [`super::globals::GlobalIndex`] (the closed walk only).
    Global(String),
}

impl Val {
    fn local(ty: Option<String>) -> Val {
        Val { ty, root: Root::Local, hops: Vec::new(), hop_ok: true, list: false }
    }
    fn tracked(&self) -> bool {
        matches!(self.root, Root::Holder | Root::Ctx(_) | Root::Lookup(_))
    }
    fn root_name(&self) -> String {
        match &self.root {
            Root::Holder => "holder".to_string(),
            Root::Ctx(c) => c.clone(),
            Root::Lookup(b) => format!("lookup:{}", serde_json::to_string(b).expect("lookup descriptor serializes")),
            _ => String::new(),
        }
    }
}

pub struct ReadsEngine<'a> {
    pub sem: &'a Sem,
    pub decls: &'a Decls,
    pub ann: &'a Annotations,
    /// Directory prefixes whose procs are engine internals: followed by nobody (a dispatcher that
    /// reads `vars[]` by design, the tgui plumbing). Their own correctness is the engine's.
    pub opaque_dirs: Vec<String>,
    /// A call on a typed receiver also runs every override in the receiver's subtypes (the union over all of them): a virtual call reads
    /// whatever any override reads. Off for the lints, whose baselines were taken without it; on for the generated subscriptions.
    pub virtual_dispatch: bool,
    overrides_cache: std::sync::Mutex<HashMap<(String, String), std::sync::Arc<Vec<String>>>>,
    definers: std::sync::OnceLock<HashMap<String, Vec<String>>>,
    globals: std::sync::OnceLock<super::globals::GlobalIndex>,
    writes: std::sync::OnceLock<WriteIndex>,
    /// What a context-free walk of a proc found (closed walk only), by (owner, proc, receiver, argument shapes): see `Walk::run_proc`.
    memo: std::sync::RwLock<HashMap<MemoKey, std::sync::Arc<MemoNode>>>,
}

/// One memoized context-free walk: what its own body found, and the memoized walks it calls.
struct MemoNode {
    own: ReadSet,
    children: Vec<(MemoKey, bool)>,
    /// Neither it nor anything it calls found anything: a consumer that reaches it records nothing.
    trivial: bool,
}

type MemoKey = (String, String, Root, Option<String>, Vec<(Root, Option<String>)>, bool);

struct Frame<'a> {
    proc: ProcRef<'a>,
    rel: String,
    this: Val,
    locals: HashMap<String, Val>,
    /// ident -> types it was narrowed to by `istype(ident, /type)` anywhere in the body.
    narrow: HashMap<String, Vec<String>>,
}

struct Walk<'a, 'e> {
    eng: &'e ReadsEngine<'a>,
    /// The context type the hook form gives the handler's first param (overrides the declared one).
    ctx_override: Option<String>,
    out: &'e mut ReadSet,
    visited: HashSet<(String, String, Root, Vec<String>, Vec<(Root, Vec<String>)>)>,
    depth: usize,
    line: u32,
    /// Inside `read_once(...)`: reads are evaluated but neither recorded nor subscribed.
    mute: u32,
    /// The file of the body being walked (the call site of an opaque crossing).
    rel: String,
    /// Greater than zero inside the body of an override reached only through a virtual call.
    override_depth: u32,
    /// Greater than zero beneath a proc of an engine-internal directory ([`ENGINE_DIRS`]) a closed walk entered.
    engine_depth: u32,
    /// Set by the caller of the next `run_proc`: an act-typed parameter that got no context stays a plain value (a global helper walked
    /// without READS_FROM is not handed the handler's context).
    no_act: bool,
    /// The memoized nodes this consumer reached directly (while walking its own code or a node being computed), with whether the call sat
    /// beneath an engine body or an override.
    children: Vec<(MemoKey, bool)>,
    /// Memoized nodes this thread is computing now (a recursive helper reaches itself).
    computing: HashSet<MemoKey>,
    /// Nodes already merged into the set.
    merged: HashSet<MemoKey>,
    /// (rule, file, line, message) -> position in `out.diags`: a finding is recorded once however many paths reach it.
    diag_ix: HashMap<(&'static str, String, u32, String), usize>,
}

impl<'a> ReadsEngine<'a> {
    pub fn new(sem: &'a Sem, decls: &'a Decls, ann: &'a Annotations) -> ReadsEngine<'a> {
        ReadsEngine { sem, decls, ann, opaque_dirs: Vec::new(), virtual_dispatch: false, overrides_cache: Default::default(), definers: Default::default(), globals: Default::default(), writes: Default::default(), memo: Default::default() }
    }

    /// The closed walk: nothing is skipped (engine bodies are walked, or carry a `PROC_SUMMARY`) and a virtual call is the union of its
    /// overrides. This is what a handler's subscriptions are generated from.
    pub fn closed(mut self) -> Self {
        self.opaque_dirs.clear();
        self.virtual_dispatch = true;
        self
    }

    /// The subtypes of `ty` (not `ty` itself) that define their own `name`, sorted.
    pub fn overrides(&self, ty: &str, name: &str) -> std::sync::Arc<Vec<String>> {
        let key = (ty.to_string(), name.to_string());
        if let Some(v) = self.overrides_cache.lock().unwrap().get(&key) {
            return v.clone();
        }
        let definers = self.definers.get_or_init(|| {
            let mut m: HashMap<String, Vec<String>> = HashMap::new();
            for t in self.sem.objtree.iter_types() {
                let path = if t.get().path.is_empty() { "/".to_string() } else { t.get().path.clone() };
                for p in t.iter_self_procs() {
                    if !p.is_builtin() && p.get().code.is_some() {
                        m.entry(p.name().to_string()).or_default().push(path.clone());
                    }
                }
            }
            for v in m.values_mut() {
                v.sort();
                v.dedup();
            }
            m
        });
        let out: Vec<String> = definers.get(name).map(|d| d.iter().filter(|o| o.as_str() != ty && self.sem.is_subtype(o, ty)).cloned().collect()).unwrap_or_default();
        let out = std::sync::Arc::new(out);
        self.overrides_cache.lock().unwrap().insert(key, out.clone());
        out
    }

    /// Which global vars change after boot (built once; the closed walk classifies global reads with it).
    pub fn globals(&self) -> &super::globals::GlobalIndex {
        self.globals.get_or_init(|| super::globals::GlobalIndex::build(self.sem))
    }

    /// Which var names are written anywhere (built once).
    pub fn write_index(&self) -> &WriteIndex {
        self.writes.get_or_init(|| WriteIndex::build(self.sem))
    }

    pub fn with_opaque(mut self, dirs: &[&str]) -> Self {
        self.opaque_dirs = dirs.iter().map(|s| s.to_string()).collect();
        self
    }

    /// The reads of `ty`'s proc `name` as a handler on an instance of `ty`.
    pub fn analyze(&self, ty: &str, name: &str) -> ReadSet {
        let mut out = ReadSet::default();
        let Some(p) = self.sem.proc_ref(ty, name) else { return out };
        let mut w = Walk { eng: self, ctx_override: None, out: &mut out, visited: HashSet::new(), depth: 0, line: 0, mute: 0, rel: String::new(), override_depth: 0, engine_depth: 0, no_act: false, children: Vec::new(), computing: HashSet::new(), merged: HashSet::new(), diag_ix: HashMap::new() };
        let this = Val { ty: Some(ty.to_string()), root: Root::Holder, hops: Vec::new(), hop_ok: true, list: false };
        w.run_proc(p, this, &[], true);
        w.finish();
        out
    }

    /// Like [`analyze`](Self::analyze), for a handler called with a context of type `ctx_ty`
    /// (the hook form's context, section 8): `A` is bound to that type, so `A.actor` resolves
    /// against the fields that context really carries.
    pub fn analyze_handler(&self, ty: &str, name: &str, ctx_ty: &str) -> ReadSet {
        let mut out = ReadSet::default();
        let Some(p) = self.sem.proc_ref(ty, name) else { return out };
        let mut w = Walk { eng: self, ctx_override: Some(ctx_ty.to_string()), out: &mut out, visited: HashSet::new(), depth: 0, line: 0, mute: 0, rel: String::new(), override_depth: 0, engine_depth: 0, no_act: false, children: Vec::new(), computing: HashSet::new(), merged: HashSet::new(), diag_ix: HashMap::new() };
        let this = Val { ty: Some(ty.to_string()), root: Root::Holder, hops: Vec::new(), hop_ok: true, list: false };
        w.run_proc(p, this, &[], true);
        w.finish();
        out
    }

    /// Whether a var read through `owner` is reactive, constant, or unknown.
    pub fn classify(&self, owner: &str, var: &str, written: &WriteIndex) -> VarClass {
        if self.is_tracked(owner, var) || self.is_relation(owner, var) {
            return VarClass::Reactive;
        }
        if self.is_stat(owner, var) || self.is_derived(owner, var) || self.is_published_builtin(owner, var) {
            return VarClass::Reactive;
        }
        // `type` and `parent_type` are fixed for the life of the thing (BYOND does not let a running world change them)
        if matches!(var, "type" | "parent_type") {
            return VarClass::Constant;
        }
        // a `var/const` never changes, whatever other types name a var the same
        if !written.is_written(var) || self.sem.var_decl(owner, var).map(|v| v.is_const).unwrap_or(false) {
            return VarClass::Constant;
        }
        VarClass::Unknown
    }

    /// The hop kind a read of `name` crosses when it is followed to another entity, or `None` when the var is not one of the closed kinds
    /// (doc/rewrite/final_api.html section 7, "Hop kinds"). A relation is a hop; so is `loc`, the container hop: the movement choke point
    /// (`doMove()`, `Moved()`) publishes it and the container's own vars reach the contents that read them (`stat_hop_attach`, the ops'
    /// `op_query_read_pairs`, `hooks_change_hop_published`). The other kinds (area, turf neighbour, contents) arrive with their publishers.
    pub fn hop_kind(&self, ty_used: &str, owner: &str, name: &str) -> Option<&'static str> {
        if self.is_relation(ty_used, name) || self.is_relation(owner, name) {
            return Some("relation");
        }
        if name == "loc" && (self.sem.is_subtype(owner, "/atom") || self.sem.is_subtype(ty_used, "/atom")) {
            return Some("container");
        }
        None
    }

    /// A BYOND built-in var the engine publishes from its own choke point, so a read of it is reactive without being a TRACKED var:
    /// `loc` from `doMove()` / `Moved()` (the container hop's publisher).
    pub fn is_published_builtin(&self, owner: &str, var: &str) -> bool {
        var == "loc" && self.sem.is_subtype(owner, "/atom")
    }

    /// A relation declared with a macro or in a `relations()` body, on the type or an ancestor.
    pub fn is_relation(&self, ty: &str, var: &str) -> bool {
        if self.decls.is_relation_chain(self.sem, ty, var) {
            return true;
        }
        let mut cur = Some(ty.to_string());
        let mut guard = 0;
        while let Some(t) = cur {
            if self.ann.relations.get(&t).map(|s| s.contains(var)).unwrap_or(false) {
                return true;
            }
            guard += 1;
            if guard > 64 {
                break;
            }
            cur = self.sem.parent_of(&t).filter(|p| p != &t && p != "/");
        }
        false
    }

    pub fn is_tracked(&self, owner: &str, var: &str) -> bool {
        let mut cur = Some(owner.to_string());
        while let Some(t) = cur {
            if self.decls.tracked.get(&t).map(|s| s.contains(var)).unwrap_or(false) {
                return true;
            }
            if let Some(tr) = self.sem.ty(&t) {
                if tr.get().procs.contains_key(&format!("__setter_{}", var)) {
                    return true;
                }
            }
            cur = self.sem.parent_of(&t).filter(|p| p != &t && p != "/");
        }
        false
    }

    pub fn is_stat(&self, owner: &str, var: &str) -> bool {
        self.decls.markers_named("STAT").any(|m| m.args.get(1).map(|n| n == var).unwrap_or(false) && m.args.first().map(|t| self.sem.is_subtype(owner, t)).unwrap_or(false))
    }

    pub fn is_derived(&self, owner: &str, var: &str) -> bool {
        self.sem.proc_ref(owner, &format!("derive_{}", var)).is_some()
    }
}

impl Decls {
    /// A relation declared on the type or any ancestor.
    pub fn is_relation_chain(&self, sem: &Sem, ty: &str, var: &str) -> bool {
        let mut cur = Some(ty.to_string());
        let mut guard = 0;
        while let Some(t) = cur {
            if self.is_relation(&t, var) {
                return true;
            }
            guard += 1;
            if guard > 64 {
                break;
            }
            cur = sem.parent_of(&t).filter(|p| p != &t && p != "/");
        }
        false
    }
}

/// Which var names are written anywhere in a proc body (outside constructors), for the "constant"
/// class: a var nobody writes after init is readable but not reactive. Name-based and conservative.
#[derive(Default)]
pub struct WriteIndex {
    written: HashSet<String>,
}

impl WriteIndex {
    pub fn is_written(&self, var: &str) -> bool {
        self.written.contains(var)
    }

    pub fn build(sem: &Sem) -> WriteIndex {
        let procs: Vec<ProcRef> = sem.objtree.iter_types().flat_map(|t| t.iter_self_procs().collect::<Vec<_>>()).filter(|p| !p.is_builtin()).collect();
        // Plain threads, not rayon: this runs under a memo init (see `par_map`).
        let sets: Vec<HashSet<String>> = super::par_map(&procs, |p| proc_writes(*p));
        let mut w = WriteIndex::default();
        for s in sets {
            w.written.extend(s);
        }
        w
    }
}

/// The var names one proc's body writes (a constructor's writes are init and do not count).
pub fn proc_writes(p: ProcRef) -> HashSet<String> {
    let mut s = HashSet::new();
    let name = p.name();
    let ctor = matches!(name, "New" | "Initialize" | "initialize" | "Init");
    if let Some(code) = &p.get().code {
        collect_writes(code, ctor, &mut s);
    }
    s
}

fn collect_writes(code: &Block, ctor: bool, out: &mut HashSet<String>) {
    super::ast::walk_block(code, &mut |e, _| {
        if let Expression::AssignOp { lhs, .. } = e {
            if let Some(n) = lvalue_name(lhs) {
                // A constructor's writes are init; a var only assigned there stays constant.
                if !ctor {
                    out.insert(n);
                }
            }
        }
        // `x++` / `--x` and list mutators are follows/unary; approximate: a `++`/`--` is an AssignOp in DM's AST for postfix? it is a Unary follow.
        if let Expression::Base { term, follow } = e {
            if let Some(Follow::Unary(op)) = follow.last().map(|f| &f.elem) {
                if matches!(op, dreammaker::ast::UnaryOp::PreIncr | dreammaker::ast::UnaryOp::PostIncr | dreammaker::ast::UnaryOp::PreDecr | dreammaker::ast::UnaryOp::PostDecr) && !ctor {
                    if let Some(n) = lvalue_name_of(term, &follow[..follow.len() - 1]) {
                        out.insert(n);
                    }
                }
            }
        }
    });
}

/// The var name an lvalue assigns (`x`, `a.b.x` -> "x").
pub fn lvalue_name(e: &Expression) -> Option<String> {
    match e {
        Expression::Base { term, follow } => lvalue_name_of(term, follow),
        _ => None,
    }
}

pub(super) fn lvalue_name_of(term: &dreammaker::ast::Spanned<Term>, follow: &[dreammaker::ast::Spanned<Follow>]) -> Option<String> {
    match follow.last().map(|f| &f.elem) {
        Some(Follow::Field(_, n)) => Some(n.as_str().to_string()),
        Some(Follow::Index(..)) => lvalue_name_of(term, &follow[..follow.len() - 1]),
        None => match &term.elem {
            Term::Ident(n) => Some(n.clone()),
            _ => None,
        },
        _ => None,
    }
}

fn type_str(vt: &VarType) -> Option<String> {
    if vt.type_path.is_empty() {
        None
    } else {
        Some(format!("/{}", vt.type_path.join("/")))
    }
}

impl<'a, 'e> Walk<'a, 'e> {
    fn rel_of(&self, p: ProcRef<'a>) -> String {
        self.eng.sem.rel(p.get().location).to_string()
    }

    fn add_read(&mut self, mut r: Read, rel: &str, line: u32) {
        if let Some(text) = r.root.strip_prefix("lookup:") {
            let binding: LookupBound = serde_json::from_str(text).expect("internal lookup descriptor");
            if !r.hops.is_empty() {
                self.lookup_diag("dynamic_read", rel, line, "nested relations after a lookup need their own declared provider".to_string());
                return;
            }
            if r.kind == ReadKind::Var && !(self.eng.is_tracked(&r.owner, &r.var) || self.eng.is_stat(&r.owner, &r.var) || self.eng.is_relation(&r.owner, &r.var) || self.eng.is_derived(&r.owner, &r.var) || self.eng.sem.var_decl(&r.owner, &r.var).map(|v| v.is_const).unwrap_or(false)) {
                self.lookup_diag("dynamic_read", rel, line, format!("lookup result {}.{} is not tracked or a declared read producer", r.owner, r.var));
                return;
            }
            let lookup = LookupRead { binding, field: r.var };
            r.var = lookup.key();
            r.root = "holder".to_string();
            r.owner.clear();
            r.kind = ReadKind::Lookup(Box::new(lookup));
        }
        if self.mute > 0 {
            return;
        }
        if self.eng.virtual_dispatch && r.kind == ReadKind::Var {
            if self.internal_read(rel, &r) {
                if !self.out.reads.contains(&r) {
                    self.out.internal.insert(r.clone());
                }
            } else {
                self.out.internal.remove(&r);
            }
        }
        if !self.out.sites.contains_key(&r) {
            self.out.sites.insert(r.clone(), (rel.to_string(), line));
        }
        self.out.reads.insert(r);
    }

    /// Whether a var read is the framework reading its own state: the body is engine code and so is the var's declaration.
    fn internal_read(&self, rel: &str, r: &Read) -> bool {
        if !framework_file(rel) {
            return false;
        }
        match self.eng.sem.var_decl(&r.owner, &r.var) {
            Some(v) => framework_file(&v.file),
            None => false,
        }
    }

    fn diag(&mut self, rule: &'static str, rel: &str, line: u32, msg: String) {
        let closed_only = self.override_depth > 0 || self.engine_depth > 0;
        self.record_diag(Diag { rule, closed_only, rel: rel.to_string(), line, msg });
    }

    /// Records a finding once; a second sighting is closed-only only if both were.
    fn record_diag(&mut self, d: Diag) {
        // The index covers diags recorded since the walk began; a walk that starts with some (never today) would miss them.
        let key = (d.rule, d.rel.clone(), d.line, d.msg.clone());
        match self.diag_ix.get(&key) {
            Some(&i) => self.out.diags[i].closed_only &= d.closed_only,
            None => {
                self.diag_ix.insert(key, self.out.diags.len());
                self.out.diags.push(d);
            }
        }
    }

    fn lookup_diag(&mut self, rule: &'static str, rel: &str, line: u32, msg: String) {
        let diagnostic = Diag { rule, closed_only: false, rel: rel.to_string(), line, msg: msg.clone() };
        if !self.out.lookup_diags.contains(&diagnostic) {
            self.out.lookup_diags.push(diagnostic);
        }
        self.diag(rule, rel, line, msg);
    }

    /// Walks one proc body with `this` as src. `bind` are the evaluated args for its params.
    fn run_proc(&mut self, p: ProcRef<'a>, this: Val, bind: &[Val], first_is_ctx: bool) {
        if p.is_builtin() || self.depth > MAX_DEPTH {
            return;
        }
        let no_act = std::mem::take(&mut self.no_act);
        let owner = {
            let o = &p.ty().get().path;
            if o.is_empty() { "/".to_string() } else { o.clone() }
        };
        let vkey = (owner.clone(), p.name().to_string(), this.root.clone(), this.hops.clone(), bind.iter().map(|v| (v.root.clone(), v.hops.clone())).collect());
        if !self.visited.insert(vkey) {
            return;
        }
        if !self.eng.virtual_dispatch {
            self.out.followed.insert(format!("{}::{}", owner, p.name()));
        }
        // A walk that starts from no entity (a helper handed untracked values, a method of a global singleton) finds the same thing wherever
        // it is called from. It is done once per engine and kept as a node of a graph: its own findings plus the nodes it calls. A consumer
        // records the nodes it reaches and, when its walk ends, merges each node once (`finish`).
        let context_free = self.eng.virtual_dispatch
            && self.mute == 0
            && !self.eng.ann.summaries.contains_key(&(owner.clone(), p.name().to_string()))
            && matches!(this.root, Root::Local | Root::Global(_))
            && bind.iter().all(|v| matches!(v.root, Root::Local | Root::Global(_)));
        if context_free {
            let key: MemoKey = (owner.clone(), p.name().to_string(), this.root.clone(), this.ty.clone(), bind.iter().map(|v| (v.root.clone(), v.ty.clone())).collect(), no_act);
            let outer = self.override_depth > 0 || self.engine_depth > 0;
            let known = self.eng.memo.read().unwrap().get(&key).map(|n| n.trivial);
            if known == Some(true) {
                return;
            }
            if known.is_none() && !self.computing.contains(&key) {
                self.computing.insert(key.clone());
                let saved_out = std::mem::take(&mut *self.out);
                let saved_visited = std::mem::take(&mut self.visited);
                let saved_children = std::mem::take(&mut self.children);
                let saved_ix = std::mem::take(&mut self.diag_ix);
                let (saved_override, saved_engine, saved_depth) = (std::mem::take(&mut self.override_depth), std::mem::take(&mut self.engine_depth), std::mem::take(&mut self.depth));
                self.enter(p, this, bind, first_is_ctx, no_act, &owner);
                self.override_depth = saved_override;
                self.engine_depth = saved_engine;
                self.depth = saved_depth;
                self.visited = saved_visited;
                let own = std::mem::replace(&mut *self.out, saved_out);
                let children = std::mem::replace(&mut self.children, saved_children);
                self.diag_ix = saved_ix;
                self.computing.remove(&key);
                let memo = self.eng.memo.read().unwrap();
                let bare = own.reads.is_empty() && own.diags.is_empty() && own.lookup_diags.is_empty() && own.opaque.is_empty() && own.ctx_fields.is_empty();
                let trivial = bare && children.iter().all(|(c, _)| memo.get(c).map(|n| n.trivial).unwrap_or(false));
                drop(memo);
                self.eng.memo.write().unwrap().insert(key.clone(), std::sync::Arc::new(MemoNode { own, children, trivial }));
                if trivial {
                    return;
                }
            }
            self.children.push((key, outer));
            return;
        }
        self.enter(p, this, bind, first_is_ctx, no_act, &owner);
    }

    /// Merges every memoized node the walk reached (and the nodes they call, once each) into the set. `outer` carries "found beneath an
    /// engine body or an override" down the edges.
    fn finish(&mut self) {
        let mut stack: Vec<(MemoKey, bool)> = std::mem::take(&mut self.children);
        stack.reverse();
        while let Some((key, outer)) = stack.pop() {
            if !self.merged.insert(key.clone()) {
                continue;
            }
            let Some(node) = self.eng.memo.read().unwrap().get(&key).cloned() else { continue };
            self.merge(&node.own, outer);
            for (child, flag) in node.children.iter().rev() {
                if !self.merged.contains(child) {
                    stack.push((child.clone(), outer || *flag));
                }
            }
        }
    }

    /// Adds one memoized node's own findings to this walk's set.
    fn merge(&mut self, d: &ReadSet, outer: bool) {
        for r in &d.reads {
            if !d.internal.contains(r) {
                self.out.internal.remove(r);
            }
        }
        for r in &d.internal {
            if !self.out.reads.contains(r) {
                self.out.internal.insert(r.clone());
            }
        }
        for r in &d.reads {
            self.out.reads.insert(r.clone());
            if let Some(site) = d.sites.get(r) {
                self.out.sites.entry(r.clone()).or_insert_with(|| site.clone());
            }
        }
        for (k, v) in &d.ctx_fields {
            self.out.ctx_fields.entry(k.clone()).or_insert_with(|| v.clone());
        }
        for x in &d.diags {
            let mut y = x.clone();
            y.closed_only |= outer;
            self.record_diag(y);
        }
        for x in &d.lookup_diags {
            if !self.out.lookup_diags.contains(x) {
                self.out.lookup_diags.push(x.clone());
            }
        }
        for (k, v) in &d.opaque {
            self.out.opaque.entry(k.clone()).or_insert_with(|| v.clone());
        }
    }

    fn enter(&mut self, p: ProcRef<'a>, this: Val, bind: &[Val], first_is_ctx: bool, no_act: bool, owner: &str) {
        if let Some(summary) = self.eng.ann.summaries.get(&(owner.to_string(), p.name().to_string())) {
            self.apply_summary(owner, p.name(), summary, &this, bind);
            return;
        }
        let value = p.get();
        if !self.eng.opaque_dirs.is_empty() {
            let rel = self.eng.sem.rel(value.location);
            if self.eng.opaque_dirs.iter().any(|d| rel.starts_with(d.as_str())) {
                if self.depth > 0 && self.mute == 0 {
                    let key = format!("{}::{}", owner, p.name());
                    let site = (self.rel.clone(), self.line);
                    self.out.opaque.entry(key).or_insert(site);
                }
                return;
            }
        }
        let Some(code) = &value.code else { return };
        let mut fr = Frame { proc: p, rel: self.rel_of(p), this, locals: HashMap::new(), narrow: HashMap::new() };
        for (i, prm) in value.parameters.iter().enumerate() {
            let declared = type_str(&prm.var_type);
            let mut v = match bind.get(i) {
                Some(b) => b.clone(),
                None => Val::local(declared.clone()),
            };
            if let Some(d) = &declared {
                if v.ty.is_none() || v.root == Root::Local {
                    v.ty = Some(d.clone());
                }
                if self.eng.sem.is_subtype(d, "/datum/act") && (first_is_ctx || bind.get(i).is_some()) && !no_act && (v.root == Root::Local) {
                    v.root = Root::Act;
                    if let (Some(c), true) = (&self.ctx_override, i == 0 && first_is_ctx) {
                        v.ty = Some(c.clone());
                    }
                }
            }
            fr.locals.insert(prm.name.clone(), v);
        }
        collect_narrowing(code, &mut fr.narrow);
        let outer_rel = std::mem::replace(&mut self.rel, fr.rel.clone());
        let in_engine = self.eng.virtual_dispatch && ENGINE_DIRS.iter().any(|d| fr.rel.starts_with(d));
        self.engine_depth += in_engine as u32;
        self.depth += 1;
        self.block(&mut fr, code);
        self.depth -= 1;
        self.engine_depth -= in_engine as u32;
        self.rel = outer_rel;
    }

    /// A proc with a declared `PROC_SUMMARY`: its reads and writes land on the receiver (a type proc) or on the first tracked argument
    /// (a global proc), and the body is not walked.
    fn apply_summary(&mut self, owner: &str, name: &str, summary: &ProcSummary, this: &Val, bind: &[Val]) {
        let entity = if owner == "/" { bind.iter().find(|v| v.tracked()).cloned() } else { Some(this.clone()) };
        let Some(entity) = entity else { return };
        let (rel, line) = (self.rel.clone(), self.line);
        let ty = entity.ty.clone().unwrap_or_else(|| owner.to_string());
        if entity.tracked() {
            for var in &summary.reads {
                let var_owner = self.eng.sem.var_owner(&ty, var).unwrap_or_else(|| ty.clone());
                let r = Read { root: entity.root_name(), hops: entity.hops.clone(), var: var.clone(), owner: var_owner, kind: ReadKind::Var, hop_ok: entity.hop_ok };
                self.add_read(r, &rel, line);
            }
        }
        for var in &summary.writes {
            self.out.effects.push(Effect { kind: "assign", name: var.clone(), owner: ty.clone(), proc: name.to_string(), rel: rel.clone(), line });
        }
    }

    /// Follows `p` (the proc `name` resolves to on `ty`), and, for a closed walk, every override of it in `ty`'s subtypes.
    fn run_virtual(&mut self, p: ProcRef<'a>, ty: &str, name: &str, this: Val, bind: &[Val]) {
        self.run_proc(p, this.clone(), bind, false);
        if !self.eng.virtual_dispatch || !this.tracked() {
            return;
        }
        let declaring = {
            let o = &p.ty().get().path;
            if o.is_empty() { "/".to_string() } else { o.clone() }
        };
        for sub in self.eng.overrides(ty, name).iter() {
            if *sub == declaring {
                continue;
            }
            let Some(op) = self.eng.sem.proc_ref(sub, name) else { continue };
            let mut v = this.clone();
            v.ty = Some(sub.clone());
            self.override_depth += 1;
            self.run_proc(op, v, bind, false);
            self.override_depth -= 1;
        }
    }

    fn block(&mut self, fr: &mut Frame<'a>, b: &Block) {
        for st in b.iter() {
            self.line = st.location.line;
            self.stmt(fr, &st.elem);
        }
    }

    fn stmt(&mut self, fr: &mut Frame<'a>, s: &Statement) {
        match s {
            Statement::Var(vs) => {
                let declared = type_str(&vs.var_type);
                let mut v = match &vs.value {
                    Some(e) => self.eval(fr, e),
                    None => Val::local(None),
                };
                if declared.is_some() {
                    v.ty = declared;
                }
                fr.locals.insert(vs.name.clone(), v);
            }
            Statement::Vars(list) => {
                for vs in list {
                    let declared = type_str(&vs.var_type);
                    let mut v = match &vs.value {
                        Some(e) => self.eval(fr, e),
                        None => Val::local(None),
                    };
                    if declared.is_some() {
                        v.ty = declared;
                    }
                    fr.locals.insert(vs.name.clone(), v);
                }
            }
            Statement::ForList(fl) => {
                let it = match &fl.in_list {
                    Some(e) => self.eval(fr, e),
                    None => Val::local(None),
                };
                let declared = fl.var_type.as_ref().and_then(type_str);
                let mut v = if it.tracked() && it.list {
                    let mut hops = it.hops.clone();
                    if let Some(last) = hops.last_mut() {
                        if !last.ends_with("[]") {
                            last.push_str("[]");
                        }
                    }
                    Val { ty: declared.clone(), root: it.root.clone(), hops, hop_ok: it.hop_ok, list: false }
                } else {
                    Val::local(declared.clone())
                };
                if v.ty.is_none() {
                    v.ty = declared;
                }
                fr.locals.insert(fl.name.as_str().to_string(), v);
                self.block(fr, &fl.block);
            }
            Statement::ForKeyValue(fk) => {
                if let Some(e) = &fk.in_list {
                    self.eval(fr, e);
                }
                fr.locals.insert(fk.key.as_str().to_string(), Val::local(fk.var_type.as_ref().and_then(type_str)));
                fr.locals.insert(fk.value.as_str().to_string(), Val::local(None));
                self.block(fr, &fk.block);
            }
            Statement::ForRange(fr2) => {
                self.eval(fr, &fr2.start);
                self.eval(fr, &fr2.end);
                if let Some(st) = &fr2.step {
                    self.eval(fr, st);
                }
                fr.locals.insert(fr2.name.as_str().to_string(), Val::local(None));
                self.block(fr, &fr2.block);
            }
            Statement::ForLoop { init, test, inc, block } => {
                if let Some(i) = init {
                    self.stmt(fr, i);
                }
                if let Some(t) = test {
                    self.eval(fr, t);
                }
                if let Some(i) = inc {
                    self.stmt(fr, i);
                }
                self.block(fr, block);
            }
            _ => {
                for e in stmt_exprs(s) {
                    self.eval(fr, e);
                }
                for b in stmt_blocks(s) {
                    self.block(fr, b);
                }
            }
        }
    }

    fn eval(&mut self, fr: &mut Frame<'a>, e: &Expression) -> Val {
        match e {
            Expression::Base { term, follow } => {
                let line = term.location.line;
                if line != 0 {
                    self.line = line;
                }
                let mut v = self.term(fr, &term.elem, line);
                for fo in follow.iter() {
                    v = match &fo.elem {
                        Follow::Field(_, name) => self.field(fr, v, name.as_str()),
                        Follow::Call(_, name, args) => self.method(fr, v, name.as_str(), args),
                        Follow::Index(_, ix) => {
                            self.eval(fr, ix);
                            self.index(v)
                        }
                        Follow::Unary(dreammaker::ast::UnaryOp::Neg) => match &v.root {
                            Root::Scalar(LookupArgument::Literal(n)) if n != "null" => Val { ty: None, root: Root::Scalar(LookupArgument::Literal(format!("-{n}"))), hops: Vec::new(), hop_ok: true, list: false },
                            _ => Val::local(None),
                        },
                        Follow::Unary(_) => Val::local(None),
                        Follow::StaticField(_) | Follow::ProcReference(_) => Val::local(None),
                    };
                }
                v
            }
            Expression::BinaryOp { lhs, rhs, .. } => {
                self.eval(fr, lhs);
                self.eval(fr, rhs);
                Val::local(None)
            }
            Expression::AssignOp { op, lhs, rhs } => {
                let rv = self.eval(fr, rhs);
                self.assign(fr, lhs, *op, rv.clone());
                rv
            }
            Expression::TernaryOp { cond, if_, else_ } => {
                self.eval(fr, cond);
                let a = self.eval(fr, if_);
                let b = self.eval(fr, else_);
                if a.tracked() && b.tracked() && a.root == b.root && a.hops == b.hops && a.ty == b.ty {
                    a
                } else {
                    Val::local(None)
                }
            }
        }
    }

    fn assign(&mut self, fr: &mut Frame<'a>, lhs: &Expression, op: AssignOp, rv: Val) {
        let Expression::Base { term, follow } = lhs else {
            self.eval(fr, lhs);
            return;
        };
        let line = term.location.line;
        if follow.is_empty() {
            if let Term::Ident(n) = &term.elem {
                if fr.locals.contains_key(n) {
                    if !matches!(op, AssignOp::Assign) {
                        self.eval(fr, lhs);
                    }
                    let declared = fr.locals.get(n).and_then(|v| v.ty.clone());
                    let mut nv = rv;
                    if nv.ty.is_none() {
                        nv.ty = declared;
                    }
                    fr.locals.insert(n.clone(), nv);
                    return;
                }
                // A write to a var of the holder (or an untyped global).
                if !matches!(op, AssignOp::Assign) {
                    self.eval(fr, lhs);
                }
                let owner = fr.this.ty.clone().unwrap_or_default();
                if !self.eng.virtual_dispatch { self.out.effects.push(Effect { kind: "assign", name: n.clone(), owner, proc: fr.proc.name().to_string(), rel: fr.rel.clone(), line }); }
                return;
            }
        }
        // a.b.c = x: evaluate the receiver chain except the last step.
        let mut v = self.term(fr, &term.elem, line);
        let n = follow.len();
        for (i, fo) in follow.iter().enumerate() {
            let last = i + 1 == n;
            v = match &fo.elem {
                Follow::Field(_, name) if last => {
                    if !matches!(op, AssignOp::Assign) {
                        // compound: the old value is read.
                        let _ = self.field(fr, v.clone(), name.as_str());
                    }
                    if !self.eng.virtual_dispatch { self.out.effects.push(Effect { kind: "assign", name: name.as_str().to_string(), owner: v.ty.clone().unwrap_or_default(), proc: fr.proc.name().to_string(), rel: fr.rel.clone(), line }); }
                    Val::local(None)
                }
                Follow::Field(_, name) => self.field(fr, v, name.as_str()),
                Follow::Call(_, name, args) => self.method(fr, v, name.as_str(), args),
                Follow::Index(_, ix) => {
                    self.eval(fr, ix);
                    self.index(v)
                }
                _ => Val::local(None),
            };
        }
    }

    fn term(&mut self, fr: &mut Frame<'a>, t: &Term, line: u32) -> Val {
        match t {
            Term::Int(n) => Val { ty: None, root: Root::Scalar(LookupArgument::Literal(n.to_string())), hops: Vec::new(), hop_ok: true, list: false },
            Term::Float(n) => Val { ty: None, root: Root::Scalar(LookupArgument::Literal(n.to_string())), hops: Vec::new(), hop_ok: true, list: false },
            Term::Null => Val { ty: None, root: Root::Scalar(LookupArgument::Literal("null".to_string())), hops: Vec::new(), hop_ok: true, list: false },
            Term::Ident(name) => self.ident(fr, name, line),
            Term::Expr(e) => self.eval(fr, e),
            Term::Call(name, args) => self.call(fr, name.as_str(), args, line),
            Term::GlobalCall(_, args) | Term::List(args) => {
                for a in args.iter() {
                    self.eval(fr, a);
                }
                Val::local(None)
            }
            Term::SelfCall(args) => {
                for a in args.iter() {
                    self.eval(fr, a);
                }
                Val::local(None)
            }
            Term::ParentCall(args) => {
                let vals: Vec<Val> = args.iter().map(|a| self.eval(fr, a)).collect();
                if let Some(parent) = fr.proc.parent_proc() {
                    let this = fr.this.clone();
                    let bind = if vals.is_empty() { self.current_params(fr) } else { vals };
                    self.run_proc(parent, this, &bind, false);
                }
                Val::local(None)
            }
            Term::InterpString(_, parts) => {
                for (e, _) in parts.iter() {
                    if let Some(e) = e {
                        self.eval(fr, e);
                    }
                }
                Val::local(None)
            }
            Term::NewImplicit { args } | Term::NewPrefab { args, .. } | Term::NewMiniExpr { args, .. } => {
                if let Some(a) = args {
                    for x in a.iter() {
                        self.eval(fr, x);
                    }
                }
                Val::local(None)
            }
            Term::Input { args, in_list, .. } | Term::Locate { args, in_list } => {
                for a in args.iter() {
                    self.eval(fr, a);
                }
                if let Some(l) = in_list {
                    self.eval(fr, l);
                }
                Val::local(None)
            }
            Term::Pick(p) => {
                for (w, e) in p.iter() {
                    if let Some(w) = w {
                        self.eval(fr, w);
                    }
                    self.eval(fr, e);
                }
                Val::local(None)
            }
            Term::DynamicCall(a, b) => {
                for x in a.iter().chain(b.iter()) {
                    self.eval(fr, x);
                }
                let rel = fr.rel.clone();
                self.diag("dynamic_read", &rel, line, "call() cannot be followed".to_string());
                Val::local(None)
            }
            Term::ExternalCall { args, .. } => {
                for a in args.iter() {
                    self.eval(fr, a);
                }
                Val::local(None)
            }
            _ => Val::local(None),
        }
    }

    fn current_params(&self, fr: &Frame<'a>) -> Vec<Val> {
        fr.proc.get().parameters.iter().map(|p| fr.locals.get(&p.name).cloned().unwrap_or_else(|| Val::local(None))).collect()
    }

    fn ident(&mut self, fr: &mut Frame<'a>, name: &str, line: u32) -> Val {
        if name == "src" {
            return fr.this.clone();
        }
        if name == "." || name == ".." {
            return fr.locals.get(name).cloned().unwrap_or_else(|| Val::local(None));
        }
        if name == "global" {
            // `global.proc()` / `global.var`: the global scope, never a var of src.
            return Val::local(None);
        }
        if let Some(v) = fr.locals.get(name) {
            return v.clone();
        }
        if name == "vars" {
            let rel = fr.rel.clone();
            self.diag("dynamic_read", &rel, line, "vars[] reads are not allowed in a handler".to_string());
            return Val::local(None);
        }
        if let Some(v) = self.global_ident(fr, name, line) {
            return v;
        }
        // A var of src.
        let this = fr.this.clone();
        self.field(fr, this, name)
    }

    /// Global state the framework owns and keeps value-transparent: a shared cache (its store, its counter, the cache datum: a hit is the
    /// builder's value, invalidated by the cache's own policy, doc/rewrite/caching.md), or engine state (declared in an engine directory)
    /// read by an engine body. The first is structural; the second is the framework's own bookkeeping, which the staleness checker
    /// cross-checks and which is not an input of any stat or look.
    fn global_internal(&self, fr: &Frame<'a>, var: &str, ty: &str, decl_file: &str) -> bool {
        let sem = self.eng.sem;
        if sem.is_subtype(ty, "/datum/shared_cache") {
            return true;
        }
        for prefix in ["_scs_", "_sch_"] {
            if let Some(cache) = var.strip_prefix(prefix) {
                if sem.var_decl("/", &format!("_sc_{cache}")).map(|v| v.declared == "/datum/shared_cache").unwrap_or(false) {
                    return true;
                }
            }
        }
        // Handle resolution (`resolve_handle()` and its keyed fallbacks) looks a handle up in the world's registries (`GLOB.directory` for a
        // client's handle). A handle that resolves to null is the deletion signal the lifecycle already publishes, so the lookup is bookkeeping, not an input.
        if fr.rel == HANDLE_RESOLUTION_FILE {
            return true;
        }
        framework_file(&fr.rel) && framework_file(decl_file)
    }

    /// A bare identifier that names a global var (`GLOB`, `SSair`, a `var/global`): global state, not a var of src. Closed walk only.
    fn global_ident(&mut self, fr: &Frame<'a>, name: &str, line: u32) -> Option<Val> {
        if !self.eng.virtual_dispatch || matches!(name, "world" | "usr" | "src" | "args" | "vars" | "global" | "null" | "client" | "." | "..") {
            return None;
        }
        let sem = self.eng.sem;
        if let Some(ty) = &fr.this.ty {
            // A var the receiver's type declares shadows a global of the same name.
            if sem.var_owner(ty, name).map(|o| o != "/").unwrap_or(false) {
                return None;
            }
        }
        let sig = sem.var_decl("/", name)?;
        if sem.var_owner("/", name).as_deref() != Some("/") {
            return None;
        }
        let rel = fr.rel.clone();
        if name != "GLOB" && self.mute == 0 && !sig.is_const && !self.eng.globals().constant_after_init(name) && !self.global_internal(fr, name, &sig.declared, &sig.file) {
            self.diag("untracked_global", &rel, line, name.to_string());
        }
        let ty = (!sig.declared.is_empty()).then(|| sig.declared.clone());
        if sig.is_object() {
            Some(Val { ty, root: Root::Global(name.to_string()), hops: Vec::new(), hop_ok: true, list: false })
        } else {
            Some(Val::local(ty))
        }
    }

    /// `g.name` where `g` is global state: classifies the read. A var of a system that is tracked is a read of that system's state (it
    /// publishes); a var nothing writes after boot reads like a constant; anything else is an input nothing publishes.
    fn global_field(&mut self, fr: &mut Frame<'a>, v: Val, path: &str, name: &str) -> Val {
        let sem = self.eng.sem;
        let rel = fr.rel.clone();
        let line = self.line;
        let Some(ty) = v.ty.clone() else { return Val::local(None) };
        let Some(sig) = sem.var_decl(&ty, name) else { return Val::local(None) };
        let owner = sem.var_owner(&ty, name).unwrap_or_else(|| ty.clone());
        let child = if path == "GLOB" { format!("GLOB.{name}") } else { format!("{path}.{name}") };
        let is_glob = path == "GLOB";
        let mut tracked_system = None;
        if !is_glob && sem.is_subtype(&ty, "/datum/system") && self.eng.is_tracked(&owner, name) {
            let short = ty.trim_start_matches("/datum/system/").split('/').next().unwrap_or("").to_string();
            tracked_system = Some(short);
        }
        if let Some(system) = tracked_system {
            let r = Read { root: format!("system:{}", system), hops: Vec::new(), var: name.to_string(), owner: ty.clone(), kind: ReadKind::System, hop_ok: true };
            self.add_read(r, &rel, line);
        } else if self.mute == 0 {
            let constant = sig.is_const || if is_glob { self.eng.globals().constant_after_init(name) } else { !self.eng.write_index().is_written(name) || (self.eng.globals().field_constant_after_init(name) && !self.eng.is_relation(&ty, name)) };
            if !constant && !self.global_internal(fr, name, if is_glob { &sig.declared } else { &ty }, &sig.file) {
                self.diag("untracked_global", &rel, line, child.clone());
            }
        }
        if sig.is_object() && child.matches('.').count() < MAX_HOPS {
            Val { ty: (!sig.declared.is_empty()).then(|| sig.declared.clone()), root: Root::Global(child), hops: Vec::new(), hop_ok: true, list: false }
        } else {
            Val::local((!sig.declared.is_empty()).then(|| sig.declared))
        }
    }

    /// `v.name`: a var read on the entity `v` is (when it is tracked), else nothing.
    fn field(&mut self, fr: &mut Frame<'a>, v: Val, name: &str) -> Val {
        let sem = self.eng.sem;
        let rel = fr.rel.clone();
        let line = self.line;
        if let Root::Global(path) = v.root.clone() {
            return self.global_field(fr, v, &path, name);
        }
        if name == "vars" && v.tracked() {
            self.diag("dynamic_read", &rel, line, "vars[] reads are not allowed in a handler".to_string());
            return Val::local(None);
        }
        let Some(ty) = v.ty.clone() else { return Val::local(None) };
        if v.root == Root::Act {
            // Context field.
            self.out.ctx_fields.entry(name.to_string()).or_insert((rel.clone(), line));
            let sig = sem.var_decl(&ty, name);
            return match sig {
                Some(s) if name == "holder" => {
                    Val { ty: (!s.declared.is_empty()).then(|| s.declared), root: Root::Holder, hops: Vec::new(), hop_ok: true, list: false }
                }
                Some(s) if s.is_object() => Val { ty: Some(s.declared), root: Root::Ctx(name.to_string()), hops: Vec::new(), hop_ok: true, list: false },
                Some(s) => Val { ty: (!s.declared.is_empty()).then(|| s.declared), root: Root::Scalar(LookupArgument::Path { root: "context".to_string(), path: vec![name.to_string()] }), hops: Vec::new(), hop_ok: true, list: false },
                None => Val::local(None),
            };
        }
        let mut sig = sem.var_decl(&ty, name);
        let mut ty_used = ty.clone();
        if sig.is_none() {
            // istype() narrowing: a var of a subtype the receiver was tested against.
            if let Some(src_name) = fr.narrow_receiver(&v, self.eng.sem) {
                for cand in src_name {
                    if let Some(s) = sem.var_decl(&cand, name) {
                        sig = Some(s);
                        ty_used = cand;
                        break;
                    }
                }
            }
        }
        let Some(sig) = sig else {
            if v.tracked() && sem.ty(&ty).is_some() && sem.proc_ref(&ty, name).is_none() && !is_builtin_name(name) {
                if matches!(v.root, Root::Lookup(_)) {
                    self.lookup_diag("unknown_field", &rel, line, format!("{} has no var `{}`", ty, name));
                } else {
                    self.diag("unknown_field", &rel, line, format!("{} has no var `{}`", ty, name));
                }
            }
            return Val::local(None);
        };
        if !v.tracked() {
            return Val::local((!sig.declared.is_empty()).then(|| sig.declared));
        }
        let owner = sem.var_owner(&ty_used, name).unwrap_or_else(|| ty_used.clone());
        if owner == "/" {
            // A global var (`SSair`, `world`): never a read of the holder; not reactive by contract.
            return Val::local((!sig.declared.is_empty()).then(|| sig.declared));
        }
        let is_rel = self.eng.hop_kind(&ty_used, &owner, name).is_some();
        let (is_static, is_const) = (sig.is_static, sig.is_const);
        if !is_static || true {
            { let r = Read { root: v.root_name(), hops: v.hops.clone(), var: name.to_string(), owner: owner.clone(), kind: ReadKind::Var, hop_ok: v.hop_ok }; self.add_read(r, &rel, line); }
        }
        let _ = is_const;
        if !v.hop_ok || v.hops.len() >= MAX_HOPS {
            // A read beyond a non-relation hop is kept (the reads stay complete) but never extended.
            return Val::local((!sig.declared.is_empty()).then(|| sig.declared));
        }
        if sig.is_object() || sig.is_list() {
            let mut hops = v.hops.clone();
            hops.push(name.to_string());
            if !is_rel && sig.is_object() && self.mute == 0 {
                // (Inside read_once() nothing is subscribed, so a hop that does not subscribe is not a finding.)
                // Followed anyway (the reads stay complete); flagged so classification can say why a hop does not subscribe.
                let engine_hop = self.eng.virtual_dispatch && self.internal_read(&rel, &Read { root: String::new(), hops: Vec::new(), var: name.to_string(), owner: owner.clone(), kind: ReadKind::Var, hop_ok: true });
                if !engine_hop {
                    let msg = format!("hop through `{}` ({}) which is not a declared relation or another hop kind", name, owner);
                    self.diag("hop_not_relation", &rel, line, msg);
                }
            }
            return Val { ty: (!sig.declared.is_empty()).then(|| sig.declared.clone()), root: v.root.clone(), hops, hop_ok: v.hop_ok && is_rel, list: sig.is_list() };
        }
        let mut path = v.hops.clone();
        path.push(name.to_string());
        // Runtime lookup paths dereference real datum vars. Virtual stats, computed
        // aliases and accessor-only fields need a typed hop form, not raw name lookup.
        if matches!(v.root, Root::Holder | Root::Ctx(_)) && v.hop_ok && self.eng.sem.var_decl(&owner, name).is_some() && (self.eng.is_tracked(&owner, name) || sig.is_const) {
            return Val { ty: (!sig.declared.is_empty()).then(|| sig.declared), root: Root::Scalar(LookupArgument::Path { root: v.root_name(), path }), hops: Vec::new(), hop_ok: true, list: false };
        }
        Val::local((!sig.declared.is_empty()).then(|| sig.declared))
    }

    fn index(&mut self, v: Val) -> Val {
        if v.tracked() && v.list {
            let mut hops = v.hops.clone();
            if let Some(l) = hops.last_mut() {
                if !l.ends_with("[]") {
                    l.push_str("[]");
                }
            }
            return Val { ty: None, root: v.root, hops, hop_ok: v.hop_ok, list: false };
        }
        Val::local(None)
    }

    /// `v.name(args)`: follow the proc on the receiver's static type when the receiver is tracked.
    fn method(&mut self, fr: &mut Frame<'a>, v: Val, name: &str, args: &[Expression]) -> Val {
        let argv: Vec<Val> = args.iter().map(|a| self.eval(fr, a)).collect();
        let sem = self.eng.sem;
        let line = self.line;
        let rel = fr.rel.clone();
        self.note_call(fr, name, &v, line);
        if self.eng.virtual_dispatch && effect_call(name) {
            return Val::local(None);
        }
        if v.root == Root::Act {
            // A.snapshot(), A.captured(...): context API, not a read.
            return Val::local(None);
        }
        let Some(ty) = v.ty.clone() else { return Val::local(None) };
        // A look builder call that stands for a key (`READS_AS(/datum/look/proc/contents_of, KEY)`): the draw it sits in reads that key on its holder.
        if ty == "/datum/look" {
            if let Some(k) = self.reads_as_for(&ty, name) {
                // The holder is the call's first argument (`look.contents_of(src, ...)`); a call without one reads the draw's own holder.
                let holder = argv.first().filter(|a| a.tracked()).cloned().unwrap_or_else(|| fr.this.clone());
                if holder.tracked() {
                    let r = Read { root: holder.root_name(), hops: holder.hops.clone(), var: k.0.clone(), owner: String::new(), kind: ReadKind::Accessor, hop_ok: holder.hop_ok };
                    self.add_read(r, &rel, line);
                }
            }
            return Val::local(None);
        }
        let Some(p) = sem.proc_ref(&ty, name).filter(|p| !p.ty().get().path.is_empty()) else {
            if v.tracked() && sem.ty(&ty).is_some() && !is_builtin_name(name) && !self.eng.sem.is_subtype(&ty, "/datum/act") {
                self.diag("unknown_call", &rel, line, format!("{} has no proc `{}`", ty, name));
            }
            return Val::local(None);
        };
        // A call on a container of unbounded type (`loc.return_air()`, `loc?.tgui_host()`): which proc runs depends on what the thing is in, so
        // the union of every override is all of /atom. Type the container (`var/obj/x/B = loc`) and the call is followed.
        if self.eng.virtual_dispatch && v.tracked() && v.hops.last().map(|h| h == "loc").unwrap_or(false) && matches!(ty.as_str(), "/atom" | "/atom/movable" | "/datum") && !p.is_builtin() {
            // (The framework's own code asking a container what it is (the containment ledger, the latent contents) is not an input of a value.)
            if self.mute == 0 && !framework_file(&rel) {
                self.diag("hop_not_relation", &rel, line, format!("`{}()` is called on a container of unbounded type ({})", name, ty));
            }
            return Val::local(None);
        }
        if matches!(v.root, Root::Global(_)) {
            // A proc on a global singleton (`SSair.x()`, `GLOB.thing.x()`): followed, its reads classified as global reads.
            if self.eng.virtual_dispatch && !p.is_builtin() {
                self.run_proc(p, v, &argv, false);
            }
            return Val::local(None);
        }
        if p.is_builtin() || !v.tracked() || !v.hop_ok {
            return Val::local(None);
        }
        let owner = {
            let o = &p.ty().get().path;
            if o.is_empty() { "/".to_string() } else { o.clone() }
        };
        // READS_AS: an accessor stands for its key; not followed.
        if let Some(k) = self.reads_as_for(&ty, name) {
            let mut hops = v.hops.clone();
            if let Some(via) = &k.1 {
                hops.push(via.clone());
            }
            { let r = Read { root: v.root_name(), hops, var: k.0.clone(), owner: String::new(), kind: ReadKind::Accessor, hop_ok: v.hop_ok }; self.add_read(r, &rel, line); }
            return Val::local(None);
        }
        let _ = owner;
        self.run_virtual(p, &ty, name, v, &argv);
        Val::local(None)
    }

    fn reads_as_for(&self, ty: &str, name: &str) -> Option<&'e (String, Option<String>)> {
        let ann: &'e Annotations = self.eng.ann;
        // The declaring type or any ancestor.
        let mut cur = Some(ty.to_string());
        let mut guard = 0;
        while let Some(t) = cur {
            if let Some(k) = ann.reads_as.get(&(t.clone(), name.to_string())) {
                return Some(k);
            }
            guard += 1;
            if guard > 64 {
                break;
            }
            cur = self.eng.sem.parent_of(&t).filter(|p| p != &t && p != "/");
        }
        None
    }

    fn note_call(&mut self, fr: &Frame<'a>, name: &str, recv: &Val, line: u32) {
        let impure = IMPURE_CALLS.contains(&name) || name.starts_with("rel_") || MESSAGE_CALLS.contains(&name) || name.starts_with("set_");
        if impure && !self.eng.virtual_dispatch {
            self.out.effects.push(Effect { kind: "call", name: name.to_string(), owner: recv.ty.clone().unwrap_or_default(), proc: fr.proc.name().to_string(), rel: fr.rel.clone(), line });
        }
    }

    /// An unscoped call: a proc of src's type, a global with READS_FROM, or an unannotated global.
    fn call(&mut self, fr: &mut Frame<'a>, name: &str, args: &[Expression], line: u32) -> Val {
        if name == "nameof" || name == "PROC_REF" || name == "TYPE_PROC_REF" || name == "GLOBAL_PROC_REF" || name == "initial" {
            return Val::local(None);
        }
        if name == "read_once" {
            // A value read once when the question opens (code/engine/parts/cond.dm read_once()): never subscribed.
            self.mute += 1;
            for a in args {
                self.eval(fr, a);
            }
            self.mute -= 1;
            return Val::local(None);
        }
        let argv: Vec<Val> = args.iter().map(|a| self.eval(fr, a)).collect();
        let sem = self.eng.sem;
        let rel = fr.rel.clone();
        let this = fr.this.clone();
        self.note_call(fr, name, &this, line);
        if self.eng.virtual_dispatch && effect_call(name) {
            return Val::local(None);
        }
        if let Some(decl) = self.eng.ann.lookups.get(name) {
            let argument = argv.get(decl.argument).and_then(|v| match &v.root {
                Root::Scalar(a) => Some(a.clone()),
                _ => None,
            });
            let Some(argument) = argument else {
                self.lookup_diag("dynamic_read", &rel, line, format!("lookup {name} argument is not a literal or a tracked root/relation field; declare a provider for getter/index expressions"));
                return Val::local(None);
            };
            if matches!(&argument, LookupArgument::Path { root, .. } if root == "context") {
                self.lookup_diag("dynamic_read", &rel, line, format!("lookup {name} uses a scalar act-context argument with no entity binding lifetime"));
                return Val::local(None);
            }
            for provider in [decl.registry.as_str(), decl.identity_key.as_str(), name] {
                if self.eng.sem.global_proc(provider).is_none() {
                    self.lookup_diag("dynamic_read", &rel, line, format!("lookup {name} declares missing global provider {provider}"));
                    return Val::local(None);
                }
            }
            let bound = LookupBound { registry: decl.registry.clone(), identity_key: decl.identity_key.clone(), lookup: name.to_string(), argument };
            return Val { ty: Some(decl.result.clone()), root: Root::Lookup(Box::new(bound)), hops: Vec::new(), hop_ok: true, list: false };
        }
        if name == "native" {
            if let Some(Expression::Base { term, .. }) = args.first() {
                if let Term::String(s) = &term.elem {
                    { let r = Read { root: this.root_name(), hops: this.hops.clone(), var: s.clone(), owner: String::new(), kind: ReadKind::Native, hop_ok: true }; self.add_read(r, &rel, line); }
                }
            }
            return Val::local(None);
        }
        // A capability state key's accessor (cover_open(holder)): a read of the key on its first argument.
        if let Some(key) = self.eng.ann.capkey_accessors.get(name) {
            if let Some(v) = argv.first().filter(|v| v.tracked()) {
                let r = Read { root: v.root_name(), hops: v.hops.clone(), var: key.clone(), owner: String::new(), kind: ReadKind::Accessor, hop_ok: v.hop_ok };
                self.add_read(r, &rel, line);
            }
            return Val::local(None);
        }
        // A system's reactive accessor: a read of the system's tracked var (a singleton, so the hop is static).
        if let Some((system, var)) = self.eng.ann.accessors.get(name) {
            let owner = crate::sem::gen::system_types(system).into_iter().find(|t| sem.ty(t).is_some()).unwrap_or_default();
            { let r = Read { root: format!("system:{}", system), hops: Vec::new(), var: var.clone(), owner, kind: ReadKind::System, hop_ok: true }; self.add_read(r, &rel, line); }
            return Val::local(None);
        }
        // A proc of src's own type (or an ancestor's).
        if let Some(ty) = this.ty.clone() {
            // A global proc is a proc of the root type: it resolves in the global branch below.
            if let Some(p) = sem.proc_ref(&ty, name).filter(|p| !p.ty().get().path.is_empty()) {
                if p.is_builtin() {
                    return Val::local(None);
                }
                if this.tracked() {
                    if let Some(k) = self.reads_as_for(&ty, name) {
                        let mut hops = this.hops.clone();
                        if let Some(via) = &k.1 {
                            hops.push(via.clone());
                        }
                        { let r = Read { root: this.root_name(), hops, var: k.0.clone(), owner: String::new(), kind: ReadKind::Accessor, hop_ok: this.hop_ok }; self.add_read(r, &rel, line); }
                        return Val::local(None);
                    }
                    self.run_virtual(p, &ty, name, this, &argv);
                } else if matches!(this.root, Root::Global(_)) && self.eng.virtual_dispatch {
                    self.run_proc(p, this, &argv, false);
                }
                return Val::local(None);
            }
        }
        // A global proc.
        if let Some(p) = sem.global_proc(name) {
            if p.is_builtin() {
                return Val::local(None);
            }
            if self.eng.virtual_dispatch && sem.rel(p.get().location).starts_with("code/_helpers/logging/") {
                // The logging helpers write the world log; what they read is not an input of a value.
                return Val::local(None);
            }
            if let Some(summary) = self.eng.ann.summaries.get(&("/".to_string(), name.to_string())) {
                self.apply_summary("/", name, summary, &Val::local(None), &argv);
                return Val::local(None);
            }
            if self.eng.virtual_dispatch && self.eng.sem.rel(p.get().location).starts_with("code/__defines/verdigris/") {
                // A Verdigris FFI binding: Rust-owned state the walk cannot see. A PROC_SUMMARY on it declares what it touches.
                self.diag("ffi_call", &rel, line, format!("`{}` is a Verdigris FFI call: declare what it reads and writes with PROC_SUMMARY(/proc/{}, ...)", name, name));
                return Val::local(None);
            }
            if let Some(params) = self.eng.ann.reads_from.get(name) {
                if let Some((key, via)) = self.eng.ann.reads_as.get(&("/".to_string(), name.to_string())) {
                    for (i, parameter) in p.get().parameters.iter().enumerate() {
                        if !params.contains(&parameter.name) { continue; }
                        if let Some(value) = argv.get(i).filter(|value| value.tracked()) {
                            let mut hops = value.hops.clone();
                            if let Some(via) = via { hops.push(via.clone()); }
                            let read = Read { root: value.root_name(), hops, var: key.clone(), owner: String::new(), kind: ReadKind::Accessor, hop_ok: value.hop_ok };
                            self.add_read(read, &rel, line);
                        }
                    }
                    return Val::local(None);
                }
                // Follow the body with the named params bound to what the call passed.
                let value = p.get();
                let mut bind: Vec<Val> = Vec::new();
                for (i, prm) in value.parameters.iter().enumerate() {
                    let a = argv.get(i).cloned().unwrap_or_else(|| Val::local(None));
                    if params.iter().any(|n| n == &prm.name) {
                        bind.push(a);
                    } else {
                        bind.push(Val::local(type_str(&prm.var_type)));
                    }
                }
                let g = Val::local(None);
                self.run_proc(p, g, &bind, false);
            } else if self.eng.virtual_dispatch {
                // Walked like any proc, every parameter bound to what the call passed: a tracked argument keeps its root, so what the body
                // reads of it is a read of the caller's entity. Global state the body reads is classified in `global_field`.
                let value = p.get();
                // (An act context does not travel into a helper: the helper declares the context type it takes, and the handler's own
                // context fields are checked at the handler.)
                let bind: Vec<Val> = value
                    .parameters
                    .iter()
                    .enumerate()
                    .map(|(i, prm)| match argv.get(i) {
                        Some(a) if a.root != Root::Act => a.clone(),
                        _ => Val::local(type_str(&prm.var_type)),
                    })
                    .collect();
                self.no_act = true;
                self.run_proc(p, Val::local(None), &bind, false);
                self.no_act = false;
            } else {
                self.diag("unannotated_global", &rel, line, format!("global proc `{}` is called without READS_FROM", name));
            }
            return Val::local(None);
        }
        Val::local(None)
    }
}

impl<'a> Frame<'a> {
    /// The narrowed types for the local/var a value came from (by identity of root/hops: only the
    /// receiver ident is known at the call site, so this looks the type up by value type name).
    fn narrow_receiver(&self, v: &Val, sem: &Sem) -> Option<Vec<String>> {
        let ty = v.ty.as_ref()?;
        let mut out = Vec::new();
        for list in self.narrow.values() {
            for t in list {
                if sem.is_subtype(t, ty) {
                    out.push(t.clone());
                }
            }
        }
        if out.is_empty() {
            None
        } else {
            Some(out)
        }
    }
}

fn collect_narrowing(code: &Block, out: &mut HashMap<String, Vec<String>>) {
    super::ast::walk_block(code, &mut |e, _| {
        if let Expression::Base { term, .. } = e {
            if let Term::Call(n, args) = &term.elem {
                if n.as_str() == "istype" && args.len() == 2 {
                    if let (Some(id), Some(path)) = (as_ident(strip_parens(&args[0])), prefab_path(&args[1])) {
                        out.entry(id.to_string()).or_default().push(path);
                    }
                }
            }
        }
    });
}

/// `/obj/foo` as a prefab expression.
pub fn prefab_path(e: &Expression) -> Option<String> {
    if let Expression::Base { term, follow } = strip_parens(e) {
        if follow.is_empty() {
            if let Term::Prefab(p) = &term.elem {
                let mut s = String::new();
                for (op, name) in p.path.iter() {
                    let _ = op;
                    s.push('/');
                    s.push_str(name);
                }
                return Some(s);
            }
        }
    }
    None
}

/// Builtin vars/procs that an object may have without the objtree declaring them on the static type.
fn is_builtin_name(name: &str) -> bool {
    matches!(name, "type" | "parent_type" | "vars" | "tag" | "Cross" | "Uncross" | "Entered" | "Exited" | "New" | "Del" | "Topic" | "Move" | "Crossed" | "Uncrossed" | "contents" | "loc" | "x" | "y" | "z")
}

/// A one-line summary of a read set, for logs and explain output.
pub fn summarize(set: &ReadSet) -> String {
    let keys: Vec<String> = set.reads.iter().map(|r| r.key()).collect();
    format!("{} reads [{}], {} diags", keys.len(), keys.join(", "), set.diags.len())
}

#[cfg(test)]
mod global_accessor_tests {
    use super::*;
    use crate::tree::{SourceFile, Tree};
    use std::sync::atomic::{AtomicUsize, Ordering};
    static NEXT: AtomicUsize = AtomicUsize::new(0);

    #[test]
    fn annotated_global_accessors_preserve_argument_roots_through_library_wrappers() {
        let root = std::env::temp_dir().join(format!("dq-accessor-{}-{}", std::process::id(), NEXT.fetch_add(1, Ordering::Relaxed)));
        std::fs::create_dir_all(root.join("code/engine")).unwrap();
        std::fs::create_dir_all(root.join("code/content")).unwrap();
        std::fs::create_dir_all(root.join("code/library")).unwrap();
        let engine = "#define READS_AS(P, K)\n#define READS_FROM(A)\nREADS_AS(/proc/read_bits, bits)\n/proc/read_bits(datum/holder)\n\tREADS_FROM(holder)\n\treturn holder.raw\n/proc/unannotated(datum/holder)\n\treturn holder.raw\n/proc/opaque_empty(datum/holder)\n\tREADS_FROM()\n\treturn unannotated(holder)\n";
        let library = "#define CAPABILITY_TYPE(N, I, T)\n#define cap_keys(I, K)\n#define CAP_EMAG 1\nCAPABILITY_TYPE(emag, CAP_EMAG, /datum/capability/emag)\ncap_keys(CAP_EMAG, EMAGGED)\n/proc/emag_emagged(datum/holder)\n\treturn FALSE\n/proc/native_and_legacy(datum/holder)\n\tREADS_FROM(holder)\n\treturn read_bits(holder) || emag_emagged(holder)\n/proc/wrapped_bits(datum/holder)\n\tREADS_FROM(holder)\n\treturn read_bits(holder)\n";
        let content = "/datum/probe\n\tvar/raw = 0\n/datum/probe/proc/direct()\n\treturn read_bits(src)\n/datum/probe/proc/wrapped()\n\treturn wrapped_bits(src)\n/datum/probe/proc/blocked()\n\treturn unannotated(src)\n/datum/probe/proc/empty_contract()\n\treturn opaque_empty(src)\n/datum/probe/proc/native()\n\treturn native_and_legacy(src)\n";
        std::fs::write(root.join("code/engine/probe.dm"), engine).unwrap();
        std::fs::write(root.join("code/content/probe.dm"), content).unwrap();
        std::fs::write(root.join("code/library/probe.dm"), library).unwrap();
        let mut tree = Tree::from_files(vec![SourceFile::from_text("code/engine/probe.dm", engine), SourceFile::from_text("code/content/probe.dm", content), SourceFile::from_text("code/library/probe.dm", library)]);
        tree.root = root.clone();
        let sem = Sem::build(&root, &tree).unwrap();
        let decls = Decls::get(&tree);
        let annotations = Annotations::get(&sem, &decls);
        assert!(annotations.reads_as.contains_key(&("/".to_string(), "read_bits".to_string())));
        let engine = ReadsEngine::new(&sem, &decls, &annotations).with_opaque(&["code/engine/"]);
        for name in ["direct", "wrapped"] {
            let reads = engine.analyze("/datum/probe", name);
            assert!(reads.diags.is_empty(), "{name}: {:?}", reads.diags);
            assert_eq!(reads.reads.len(), 1, "{name} must have the actual accessor dependency");
            let read = reads.reads.iter().next().unwrap();
            assert_eq!(read.root, "holder");
            assert_eq!(read.var, "bits");
            assert_eq!(read.kind, ReadKind::Accessor);
        }
        let native = engine.analyze("/datum/probe", "native");
        assert!(native.diags.is_empty(), "native accessor extraction: {:?}", native.diags);
        assert_eq!(native.reads.len(), 2, "the wrapper must preserve both actual stores");
        assert!(native.reads.iter().any(|read| read.root == "holder" && read.kind == ReadKind::Accessor && read.var == "EMAG_EMAGGED"));
        assert!(native.reads.iter().any(|read| read.root == "holder" && read.kind == ReadKind::Accessor && read.var == "bits"));
        let empty = engine.analyze("/datum/probe", "empty_contract");
        assert!(empty.reads.is_empty(), "empty contracts do not track entity arguments");
        assert!(empty.diags.is_empty(), "the empty contract must preserve the opaque body cutoff");
        let blocked = engine.analyze("/datum/probe", "blocked");
        assert!(blocked.reads.is_empty());
        assert!(blocked.diags.iter().any(|diag| diag.rule == "unannotated_global"));
        std::fs::remove_dir_all(root).unwrap();
    }
    #[test]
    fn lookup_arguments_preserve_constants_roots_wrappers_and_reject_opaque_getters() {
        let root = std::env::temp_dir().join(format!("dq-lookup-{}-{}", std::process::id(), NEXT.fetch_add(1, Ordering::Relaxed)));
        std::fs::create_dir_all(root.join("code/engine")).unwrap();
        std::fs::create_dir_all(root.join("code/content")).unwrap();
        std::fs::create_dir_all(root.join("code/library")).unwrap();
        let engine = "#define READ_LOOKUP(P, A...)\n#define READS_FROM(A)\n#define TRACKED(T,V)\n#define TRACKED_DATA(T,V)\n#define CAPABILITIES(T) T/proc/__entries()\n#define ref_one(A...) return\n#define STAT(T,K,A...)\n#define READS_AS(P,K,A...)\n/datum/lookup_grid\n\tvar/load = 0\n\tvar/raw = 0\nTRACKED(/datum/lookup_grid, load)\nREAD_LOOKUP(/proc/lookup_grid, registry = GLOBAL_PROC_REF(lookup_registry), key = GLOBAL_PROC_REF(lookup_identity), argument = 1, result = /datum/lookup_grid)\n/proc/lookup_registry()\n\treturn null\n/proc/lookup_identity(id)\n\treturn id\n/proc/lookup_grid(id)\n\treturn null\n/datum/act/eval\n\tvar/datum/lookup_probe/actor\n";
        let library = "/proc/lookup_load(id)\n\tREADS_FROM(id)\n\tvar/datum/lookup_grid/G = lookup_grid(id)\n\treturn G.load\n/proc/opaque_region()\n\tREADS_FROM()\n\treturn 1\n";
        let content = "/datum/lookup_probe\n\tvar/region = 1\n\tvar/other_region = 2\nTRACKED(/datum/lookup_probe, region)\nTRACKED(/datum/lookup_probe, other_region)\n/datum/lookup_profile\n\tvar/region = 3\nTRACKED_DATA(/datum/lookup_profile, region)\n/datum/lookup_probe\n\tvar/datum/lookup_profile/profile\nTRACKED(/datum/lookup_probe, profile)\nCAPABILITIES(/datum/lookup_probe)\n\tref_one(nameof(profile))\nSTAT(/datum/lookup_probe, virtual_region, SUM)\n/datum/lookup_probe/proc/derive_alias_region()\n\treturn region\n/datum/lookup_probe/proc/profile_alias()\n\treturn profile.region\nREADS_AS(/datum/lookup_probe/proc/profile_alias, region, via = nameof(profile))\n/datum/lookup_probe/proc/direct()\n\tvar/datum/lookup_grid/G = lookup_grid(region)\n\treturn G.load\n/datum/lookup_probe/proc/wrapped()\n\treturn lookup_load(region)\n/datum/lookup_probe/proc/two()\n\treturn lookup_load(region) + lookup_load(other_region)\n/datum/lookup_probe/proc/literal()\n\treturn lookup_load(-5)\n/datum/lookup_probe/proc/contextual(datum/act/eval/A)\n\treturn lookup_load(A.actor.region)\n/datum/lookup_probe/proc/profile_leaf()\n\treturn lookup_load(profile.region)\n/datum/lookup_probe/proc/virtual_arg()\n\treturn lookup_load(virtual_region)\n/datum/lookup_probe/proc/derived_arg()\n\treturn lookup_load(alias_region)\n/datum/lookup_probe/proc/profile_alias_arg()\n\treturn lookup_load(profile_alias())\n/datum/lookup_probe/proc/opaque()\n\treturn lookup_load(opaque_region())\n/datum/lookup_probe/proc/untracked()\n\tvar/datum/lookup_grid/G = lookup_grid(region)\n\treturn G.raw\n";
        std::fs::write(root.join("code/engine/probe.dm"), engine).unwrap();
        std::fs::write(root.join("code/library/probe.dm"), library).unwrap();
        std::fs::write(root.join("code/content/probe.dm"), content).unwrap();
        let mut tree = Tree::from_files(vec![SourceFile::from_text("code/engine/probe.dm", engine), SourceFile::from_text("code/library/probe.dm", library), SourceFile::from_text("code/content/probe.dm", content)]);
        tree.root = root.clone();
        let sem = Sem::build(&root, &tree).unwrap();
        let decls = Decls::get(&tree);
        let ann = Annotations::get(&sem, &decls);
        assert!(ann.lookups.contains_key("lookup_grid"));
        let eng = ReadsEngine::new(&sem, &decls, &ann).with_opaque(&["code/engine/"]);
        for name in ["direct", "wrapped"] {
            let reads = eng.analyze("/datum/lookup_probe", name);
            assert!(reads.diags.is_empty(), "{name}: {:?}", reads.diags);
            let bound: Vec<_> = reads.reads.iter().filter_map(|r| match &r.kind { ReadKind::Lookup(b) => Some(b), _ => None }).collect();
            assert_eq!(bound.len(), 1);
            assert_eq!(bound[0].field, "load");
            assert_eq!(bound[0].binding.argument, LookupArgument::Path { root: "holder".into(), path: vec!["region".into()] });
        }
        let two = eng.analyze("/datum/lookup_probe", "two");
        assert_eq!(two.reads.iter().filter(|r| matches!(r.kind, ReadKind::Lookup(_))).count(), 2, "distinct wrapper arguments must not be collapsed by the visit cache");
        let literal = eng.analyze("/datum/lookup_probe", "literal");
        assert!(literal.reads.iter().any(|r| matches!(&r.kind, ReadKind::Lookup(b) if b.binding.argument == LookupArgument::Literal("-5".into()))));
        let contextual = eng.analyze_handler("/datum/lookup_probe", "contextual", "/datum/act/eval");
        assert!(contextual.reads.iter().any(|r| matches!(&r.kind, ReadKind::Lookup(b) if b.binding.argument == (LookupArgument::Path { root: "actor".into(), path: vec!["region".into()] }))), "actor is never substituted by holder");
        let profile = eng.analyze("/datum/lookup_probe", "profile_leaf");
        assert!(profile.diags.is_empty(), "actual tracked profile leaf: {:?}", profile.diags);
        assert!(profile.reads.iter().any(|r| matches!(&r.kind, ReadKind::Lookup(b) if b.binding.argument == (LookupArgument::Path { root: "holder".into(), path: vec!["profile".into(), "region".into()] }))));
        for name in ["opaque", "untracked", "virtual_arg", "derived_arg", "profile_alias_arg"] {
            let reads = eng.analyze("/datum/lookup_probe", name);
            assert!(reads.diags.iter().any(|d| d.rule == "dynamic_read"), "{name} must diagnose instead of promising an invalid subscription");
        }
        std::fs::remove_dir_all(root).unwrap();
    }

}

#[cfg(test)]
mod closed_walk_tests {
    use super::*;
    use crate::tree::{SourceFile, Tree};
    use std::sync::atomic::{AtomicUsize, Ordering};
    static NEXT: AtomicUsize = AtomicUsize::new(0);

    fn model(files: &[(&str, &str)]) -> (std::path::PathBuf, Tree, Sem) {
        let root = std::env::temp_dir().join(format!("dq-closed-{}-{}", std::process::id(), NEXT.fetch_add(1, Ordering::Relaxed)));
        let mut loaded = Vec::new();
        for (rel, text) in files {
            let path = root.join(rel);
            std::fs::create_dir_all(path.parent().unwrap()).unwrap();
            std::fs::write(&path, text).unwrap();
            loaded.push(SourceFile::from_text(rel, text));
        }
        let mut tree = Tree::from_files(loaded);
        tree.root = root.clone();
        let sem = Sem::build(&root, &tree).unwrap();
        (root, tree, sem)
    }

    const MACROS: &str = "#define TRACKED(T, V)\n#define READS_FROM(A)\n#define PROC_SUMMARY(P, A...)\n";

    #[test]
    fn a_virtual_call_reads_the_union_of_its_overrides() {
        let content = "/datum/shape\n\tvar/w = 1\n\tvar/h = 2\n\tvar/depth = 3\nTRACKED(/datum/shape, w)\nTRACKED(/datum/shape, h)\nTRACKED(/datum/shape, depth)\n/datum/shape/proc/area()\n\treturn w\n/datum/shape/proc/probe()\n\treturn area()\n/datum/shape/wide/proc/area()\n\treturn w + h\n/datum/shape/wide/deep/proc/area()\n\treturn ..() + depth\n/datum/shape/wide/deep/deeper\n/datum/shape/other/proc/unrelated()\n\treturn depth\n";
        let (root, tree, sem) = model(&[("code/defines.dm", MACROS), ("code/content.dm", content)]);
        let decls = Decls::get(&tree);
        let ann = Annotations::get(&sem, &decls);
        let static_walk = ReadsEngine::new(&sem, &decls, &ann).analyze("/datum/shape", "probe").keys();
        assert_eq!(static_walk, BTreeSet::from(["w".to_string()]), "the lints' walk follows the static type's proc only");
        let closed = ReadsEngine::new(&sem, &decls, &ann).closed();
        let set = closed.analyze("/datum/shape", "probe");
        assert_eq!(set.keys(), BTreeSet::from(["depth".to_string(), "h".to_string(), "w".to_string()]), "the union over every override, `..()` included");
        assert_eq!(closed.overrides("/datum/shape", "area").as_slice(), ["/datum/shape/wide".to_string(), "/datum/shape/wide/deep".to_string()]);
        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn a_recursive_virtual_call_terminates() {
        let content = "/datum/node\n\tvar/n = 0\n\tvar/datum/node/next\nTRACKED(/datum/node, n)\n/datum/node/proc/walk()\n\treturn n + walk()\n/datum/node/leaf/proc/walk()\n\treturn n + ..()\n";
        let (root, tree, sem) = model(&[("code/defines.dm", MACROS), ("code/content.dm", content)]);
        let decls = Decls::get(&tree);
        let ann = Annotations::get(&sem, &decls);
        let set = ReadsEngine::new(&sem, &decls, &ann).closed().analyze("/datum/node", "walk");
        assert_eq!(set.keys(), BTreeSet::from(["n".to_string()]));
        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn engine_bodies_are_walked_and_a_summary_replaces_a_body_that_cannot_be() {
        let engine = "/datum/probe/proc/peek()\n\treturn vars[\"hidden\"]\n/datum/probe/proc/plain()\n\treturn shown\n";
        let content = "/datum/probe\n\tvar/shown = 1\n\tvar/hidden = 2\nTRACKED(/datum/probe, shown)\nTRACKED(/datum/probe, hidden)\n/datum/probe/proc/via_peek()\n\treturn peek()\n/datum/probe/proc/via_plain()\n\treturn plain()\n";
        let summarized = format!("{}PROC_SUMMARY(/datum/probe/proc/peek, reads = list(nameof(hidden)), writes = list(nameof(shown)))\n", MACROS);
        for (with_summary, defines) in [(false, MACROS.to_string()), (true, summarized)] {
            let (root, tree, sem) = model(&[("code/defines.dm", &defines), ("code/engine/probe.dm", engine), ("code/content.dm", content)]);
            let decls = Decls::get(&tree);
            let ann = Annotations::get(&sem, &decls);
            assert_eq!(ann.summaries.contains_key(&("/datum/probe".to_string(), "peek".to_string())), with_summary);
            let skipped = ReadsEngine::new(&sem, &decls, &ann).with_opaque(&["code/engine/"]).analyze("/datum/probe", "via_plain");
            assert!(skipped.reads.is_empty() && skipped.opaque.contains_key("/datum/probe::plain"), "the lints' walk stops at the engine directory");
            let closed = ReadsEngine::new(&sem, &decls, &ann).closed();
            assert_eq!(closed.analyze("/datum/probe", "via_plain").keys(), BTreeSet::from(["shown".to_string()]), "the closed walk enters it");
            let peek = closed.analyze("/datum/probe", "via_peek");
            if with_summary {
                assert_eq!(peek.keys(), BTreeSet::from(["hidden".to_string()]), "the summary stands for the body");
                assert!(peek.diags.is_empty(), "{:?}", peek.diags);
                assert_eq!(peek.writes(), BTreeSet::from(["/datum/probe.shown".to_string()]));
            } else {
                assert!(peek.diags.iter().any(|d| d.rule == "dynamic_read" && d.closed_only), "an unsummarized vars[] body is reported: {:?}", peek.diags);
            }
            std::fs::remove_dir_all(root).unwrap();
        }
    }

    const GLOBALS: &str = "/datum/controller/global_vars
	var/boot_table = 1
	var/dyn = 0
	var/list/cache_like
var/datum/controller/global_vars/GLOB
/datum/system
/datum/system/boot
	var/state = 0
/datum/system/boot/proc/initialize()
	GLOB.boot_table = 7
	GLOB.boot_table++
	setup()
/datum/system/boot/proc/setup()
	GLOB.cache_like = list()
/proc/bump()
	GLOB.dyn++
";

    #[test]
    fn a_global_helper_is_walked_and_a_tracked_argument_keeps_its_root() {
        let content = "/datum/thing
	var/charge = 0
	var/rating = 1
TRACKED(/datum/thing, charge)
TRACKED(/datum/thing, rating)
/proc/helper(datum/thing/T, scale)
	return T.charge * scale
/datum/thing/proc/probe()
	return helper(src, rating)
";
        let (root, tree, sem) = model(&[("code/defines.dm", MACROS), ("code/content.dm", content)]);
        let decls = Decls::get(&tree);
        let ann = Annotations::get(&sem, &decls);
        let legacy = ReadsEngine::new(&sem, &decls, &ann).analyze("/datum/thing", "probe");
        assert!(legacy.diags.iter().any(|d| d.rule == "unannotated_global"), "the legacy walk reports an unannotated global");
        let closed = ReadsEngine::new(&sem, &decls, &ann).closed().analyze("/datum/thing", "probe");
        assert_eq!(closed.keys(), BTreeSet::from(["charge".to_string(), "rating".to_string()]), "the helper's read of its tracked argument is a read of the holder");
        assert!(closed.diags.is_empty(), "{:?}", closed.diags);
        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn a_global_written_only_while_booting_reads_like_a_constant() {
        let content = "/datum/thing
	var/charge = 0
TRACKED(/datum/thing, charge)
/datum/thing/proc/boot_read()
	return GLOB.boot_table + charge
/datum/thing/proc/dyn_read()
	return GLOB.dyn + charge
/datum/thing/proc/via_helper()
	return peek_dyn()
/proc/peek_dyn()
	return GLOB.dyn
";
        let (root, tree, sem) = model(&[("code/defines.dm", MACROS), ("code/globals.dm", GLOBALS), ("code/content.dm", content)]);
        let decls = Decls::get(&tree);
        let ann = Annotations::get(&sem, &decls);
        let closed = ReadsEngine::new(&sem, &decls, &ann).closed();
        let globals = closed.globals();
        assert!(globals.constant_after_init("boot_table"), "written only by a system's initialize()");
        assert!(globals.constant_after_init("cache_like"), "written only by setup(), which only initialize() calls");
        assert!(!globals.constant_after_init("dyn"), "bump() is called from nowhere that boots");
        let boot = closed.analyze("/datum/thing", "boot_read");
        assert!(boot.diags.iter().all(|d| d.rule != "untracked_global"), "{:?}", boot.diags);
        let dynamic = closed.analyze("/datum/thing", "dyn_read");
        assert!(dynamic.diags.iter().any(|d| d.rule == "untracked_global" && d.msg == "GLOB.dyn"), "{:?}", dynamic.diags);
        let helper = closed.analyze("/datum/thing", "via_helper");
        assert!(helper.diags.iter().any(|d| d.rule == "untracked_global" && d.msg == "GLOB.dyn"), "a global read inside a walked helper is found: {:?}", helper.diags);
        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn a_var_of_a_singleton_that_only_boot_code_fills_reads_like_a_constant() {
        let content = "/datum/system/fill
	var/list/boot_only
	var/list/runtime
/datum/system/fill/proc/initialize()
	load()
/datum/system/fill/proc/load()
	boot_only = list()
	boot_only[\"x\"] = 1
/datum/system/fill/proc/poke()
	runtime[\"y\"] = 1
/datum/thing
	var/charge = 0
TRACKED(/datum/thing, charge)
/datum/thing/proc/probe()
	return charge
";
        let test_code = "/datum/system/fill/proc/test_write()
	boot_only = null
";
        let (root, tree, sem) = model(&[("code/defines.dm", MACROS), ("code/globals.dm", GLOBALS), ("code/content.dm", content), ("code/tests/probe.dm", test_code)]);
        let decls = Decls::get(&tree);
        let ann = Annotations::get(&sem, &decls);
        let closed = ReadsEngine::new(&sem, &decls, &ann).closed();
        let globals = closed.globals();
        assert!(globals.field_constant_after_init("boot_only"), "written only by load(), which only initialize() calls (a unit test's write does not count)");
        assert!(!globals.field_constant_after_init("runtime"), "poke() is not boot-only");
        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn a_handle_resolution_reads_the_registries_as_bookkeeping() {
        let handles = "/proc/resolve_handle(h)
	return GLOB.dyn
";
        let content = "/datum/thing
	var/charge = 0
TRACKED(/datum/thing, charge)
/datum/thing/proc/probe(h)
	return resolve_handle(h) + charge
/datum/thing/proc/direct()
	return GLOB.dyn + charge
";
        let (root, tree, sem) = model(&[("code/defines.dm", MACROS), ("code/globals.dm", GLOBALS), ("code/engine/time/handles.dm", handles), ("code/content.dm", content)]);
        let decls = Decls::get(&tree);
        let ann = Annotations::get(&sem, &decls);
        let closed = ReadsEngine::new(&sem, &decls, &ann).closed();
        let via = closed.analyze("/datum/thing", "probe");
        assert!(via.diags.iter().all(|d| d.rule != "untracked_global"), "resolve_handle() is engine bookkeeping: {:?}", via.diags);
        let direct = closed.analyze("/datum/thing", "direct");
        assert!(direct.diags.iter().any(|d| d.rule == "untracked_global" && d.msg == "GLOB.dyn"), "a content read of the same global is still found: {:?}", direct.diags);
        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn an_effect_call_is_not_followed_and_a_proc_a_callback_names_is_not_boot_only() {
        let content = "/datum/thing
	var/charge = 0
TRACKED(/datum/thing, charge)
/datum/thing/proc/probe()
	set_charge(GLOB.dyn)
	return charge
/datum/thing/proc/set_charge(v)
	return GLOB.dyn
";
        let boot = "/datum/system/boot/proc/initialize()
	keep()
	later(PROC_REF(timed))
/proc/keep()
	GLOB.boot_table = 3
/proc/timed()
	GLOB.dyn = 2
/proc/later(x)
	return x
";
        let (root, tree, sem) = model(&[("code/defines.dm", MACROS), ("code/globals.dm", &GLOBALS.replace("/datum/system/boot/proc/initialize()
	GLOB.boot_table = 7
	GLOB.boot_table++
	setup()
/datum/system/boot/proc/setup()
	GLOB.cache_like = list()
", "")), ("code/boot.dm", boot), ("code/content.dm", content)]);
        let decls = Decls::get(&tree);
        let ann = Annotations::get(&sem, &decls);
        let closed = ReadsEngine::new(&sem, &decls, &ann).closed();
        assert!(closed.globals().constant_after_init("boot_table"), "keep() runs only from initialize()");
        assert!(!closed.globals().constant_after_init("dyn"), "timed() is named by a PROC_REF, so something else runs it");
        let set = closed.analyze("/datum/thing", "probe");
        assert!(set.diags.iter().any(|d| d.rule == "untracked_global" && d.msg == "GLOB.dyn"), "the argument is read; the setter body is not: {:?}", set.diags);
        assert_eq!(set.diags.iter().filter(|d| d.rule == "untracked_global").count(), 1, "{:?}", set.diags);
        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn the_container_is_a_hop_kind_and_a_call_on_an_unbounded_container_is_not_followed() {
        let content = "/atom/proc/glow()
	return 0
/obj/crate
	var/lit = 0
TRACKED(/obj/crate, lit)
/obj/crate/glow()
	return lit
/obj/lamp
	var/charge = 0
TRACKED(/obj/lamp, charge)
/obj/lamp/proc/typed()
	var/obj/crate/C = loc
	return C.lit + charge
/obj/lamp/proc/bare()
	return istype(loc, /obj/crate)
/obj/lamp/proc/unbounded()
	return loc.glow()
";
        let (root, tree, sem) = model(&[("code/defines.dm", MACROS), ("code/content.dm", content)]);
        let decls = Decls::get(&tree);
        let ann = Annotations::get(&sem, &decls);
        let eng = ReadsEngine::new(&sem, &decls, &ann).closed();
        let typed = eng.analyze("/obj/lamp", "typed");
        assert_eq!(typed.keys(), BTreeSet::from(["charge".to_string(), "loc".to_string(), "loc.lit".to_string()]), "a typed container is followed: its var is a hop read");
        assert!(typed.diags.iter().all(|d| d.rule != "hop_not_relation"), "{:?}", typed.diags);
        assert!(typed.reads.iter().all(|r| r.hop_ok), "the container hop is a hop kind: {:?}", typed.reads);
        let bare = eng.analyze("/obj/lamp", "bare");
        assert!(bare.diags.iter().all(|d| d.rule != "hop_not_relation"), "reading loc itself is not a hop finding: {:?}", bare.diags);
        assert_eq!(eng.classify("/atom/movable", "loc", &WriteIndex::build(&sem)), VarClass::Reactive, "loc is published by the move choke point");
        let unbounded = eng.analyze("/obj/lamp", "unbounded");
        assert!(unbounded.diags.iter().any(|d| d.rule == "hop_not_relation"), "a call on /atom could run any override: {:?}", unbounded.diags);
        assert!(!unbounded.keys().contains("loc.lit"), "and it is not followed");
        // The legacy walk still calls the container a hop that is not a relation only when it is not a kind: it is one now.
        std::fs::remove_dir_all(root).unwrap();
    }
}

//! Generated reads: what a handler reads, derived from its body on the AST.
//!
//! A handler is a proc the engine calls to evaluate a condition, requirement, output or hook
//! (`x(datum/act/A)`), or a standard output (`draw`, `tgui_data`, `push_to_rust`, `should_run`).
//! [`ReadsEngine::analyze`] walks its body and returns every read it can prove, following (per the
//! graph contract, doc/rewrite/final_api.html section 7):
//!
//! * the holder's own vars, and hops through declared relations (`REL/OWN/...`);
//! * procs of the same type and of a hop's type (followed), `..()` parents;
//! * global helpers through `READS_FROM(arg)`;
//! * accessor procs with `READS_AS(proc, key, via = ...)` (not followed: they stand for their key);
//! * context hops `A.actor`, `A.held`, `A.target` (typed hops from the act context).
//!
//! The result is a static over-approximation: every read anywhere in the body subscribes, whatever
//! branch it sits in. `A.args`, `world.time` and `GLOB` reads never subscribe (documented, not a gap).
//! What it cannot resolve is reported as a [`Diag`]: an unannotated global call, `vars[]`, `call()`.

use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};

use dreammaker::ast::{AssignOp, Block, Expression, Follow, Statement, Term, VarType};
use dreammaker::objtree::ProcRef;

use super::ast::{as_ident, stmt_blocks, stmt_exprs, strip_parens};
use super::decls::Decls;
use super::Sem;

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
    /// `unannotated_global`, `dynamic_read`, `unknown_field`, `unknown_call`, `hop_not_relation`.
    pub rule: &'static str,
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

#[derive(Default, Debug)]
pub struct ReadSet {
    pub reads: BTreeSet<Read>,
    /// Context scalar/object fields read through the act (`A.dt` -> "dt"), with a line each.
    pub ctx_fields: BTreeMap<String, (String, u32)>,
    /// Where each read was first seen: (file, line).
    pub sites: BTreeMap<Read, (String, u32)>,
    pub diags: Vec<Diag>,
    pub effects: Vec<Effect>,
    /// `type::proc` bodies the walk followed (for the graph and for incremental invalidation).
    pub followed: BTreeSet<String>,
}

impl ReadSet {
    pub fn keys(&self) -> BTreeSet<String> {
        self.reads.iter().map(|r| r.key()).collect()
    }
}

/// `READS_AS` and `READS_FROM` annotations, resolved to procs.
#[derive(Default)]
pub struct Annotations {
    /// (owner type, proc) -> (key, via).
    pub reads_as: HashMap<(String, String), (String, Option<String>)>,
    /// global proc name -> the param names it reads from (empty = reads nothing).
    pub reads_from: HashMap<String, Vec<String>>,
    /// Relations declared in `relations()` bodies (`rel_one(nameof(x), ...)` / `rel_many(...)`): type -> vars.
    pub relations: HashMap<String, HashSet<String>>,
    /// `SYSTEM_ACCESSOR(system, proc, nameof(var))`: proc -> (system, var).
    pub accessors: HashMap<String, (String, String)>,
    /// The accessor `cap_keys(CAP_X, KEY = ...)` generates for each state key (`cover_open`): proc -> the key's id name (`COVER_OPEN`).
    /// A call stands for a read of that key on its first argument; the global proc behind it is not followed.
    pub capkey_accessors: HashMap<String, String>,
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
}

impl Val {
    fn local(ty: Option<String>) -> Val {
        Val { ty, root: Root::Local, hops: Vec::new(), hop_ok: true, list: false }
    }
    fn tracked(&self) -> bool {
        matches!(self.root, Root::Holder | Root::Ctx(_))
    }
    fn root_name(&self) -> String {
        match &self.root {
            Root::Holder => "holder".to_string(),
            Root::Ctx(c) => c.clone(),
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
}

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
    visited: HashSet<(String, String, Root, Vec<String>)>,
    depth: usize,
    line: u32,
    /// Inside `read_once(...)`: reads are evaluated but neither recorded nor subscribed.
    mute: u32,
}

impl<'a> ReadsEngine<'a> {
    pub fn new(sem: &'a Sem, decls: &'a Decls, ann: &'a Annotations) -> ReadsEngine<'a> {
        ReadsEngine { sem, decls, ann, opaque_dirs: Vec::new() }
    }

    pub fn with_opaque(mut self, dirs: &[&str]) -> Self {
        self.opaque_dirs = dirs.iter().map(|s| s.to_string()).collect();
        self
    }

    /// The reads of `ty`'s proc `name` as a handler on an instance of `ty`.
    pub fn analyze(&self, ty: &str, name: &str) -> ReadSet {
        let mut out = ReadSet::default();
        let Some(p) = self.sem.proc_ref(ty, name) else { return out };
        let mut w = Walk { eng: self, ctx_override: None, out: &mut out, visited: HashSet::new(), depth: 0, line: 0, mute: 0 };
        let this = Val { ty: Some(ty.to_string()), root: Root::Holder, hops: Vec::new(), hop_ok: true, list: false };
        w.run_proc(p, this, &[], true);
        out
    }

    /// Like [`analyze`](Self::analyze), for a handler called with a context of type `ctx_ty`
    /// (the hook form's context, section 8): `A` is bound to that type, so `A.actor` resolves
    /// against the fields that context really carries.
    pub fn analyze_handler(&self, ty: &str, name: &str, ctx_ty: &str) -> ReadSet {
        let mut out = ReadSet::default();
        let Some(p) = self.sem.proc_ref(ty, name) else { return out };
        let mut w = Walk { eng: self, ctx_override: Some(ctx_ty.to_string()), out: &mut out, visited: HashSet::new(), depth: 0, line: 0, mute: 0 };
        let this = Val { ty: Some(ty.to_string()), root: Root::Holder, hops: Vec::new(), hop_ok: true, list: false };
        w.run_proc(p, this, &[], true);
        out
    }

    /// Whether a var read through `owner` is reactive, constant, or unknown.
    pub fn classify(&self, owner: &str, var: &str, written: &WriteIndex) -> VarClass {
        if self.is_tracked(owner, var) || self.is_relation(owner, var) {
            return VarClass::Reactive;
        }
        if self.is_stat(owner, var) || self.is_derived(owner, var) {
            return VarClass::Reactive;
        }
        // a `var/const` never changes, whatever other types name a var the same
        if !written.is_written(var) || self.sem.var_decl(owner, var).map(|v| v.is_const).unwrap_or(false) {
            return VarClass::Constant;
        }
        VarClass::Unknown
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

fn lvalue_name_of(term: &dreammaker::ast::Spanned<Term>, follow: &[dreammaker::ast::Spanned<Follow>]) -> Option<String> {
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

    fn add_read(&mut self, r: Read, rel: &str, line: u32) {
        if self.mute > 0 {
            return;
        }
        if !self.out.sites.contains_key(&r) {
            self.out.sites.insert(r.clone(), (rel.to_string(), line));
        }
        self.out.reads.insert(r);
    }

    fn diag(&mut self, rule: &'static str, rel: &str, line: u32, msg: String) {
        if !self.out.diags.iter().any(|d| d.rule == rule && d.rel == rel && d.line == line && d.msg == msg) {
            self.out.diags.push(Diag { rule, rel: rel.to_string(), line, msg });
        }
    }

    /// Walks one proc body with `this` as src. `bind` are the evaluated args for its params.
    fn run_proc(&mut self, p: ProcRef<'a>, this: Val, bind: &[Val], first_is_ctx: bool) {
        if p.is_builtin() || self.depth > MAX_DEPTH {
            return;
        }
        let owner = {
            let o = &p.ty().get().path;
            if o.is_empty() { "/".to_string() } else { o.clone() }
        };
        let vkey = (owner.clone(), p.name().to_string(), this.root.clone(), this.hops.clone());
        if !self.visited.insert(vkey) {
            return;
        }
        self.out.followed.insert(format!("{}::{}", owner, p.name()));
        let value = p.get();
        if !self.eng.opaque_dirs.is_empty() {
            let rel = self.eng.sem.rel(value.location);
            if self.eng.opaque_dirs.iter().any(|d| rel.starts_with(d.as_str())) {
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
                if self.eng.sem.is_subtype(d, "/datum/act") && (first_is_ctx || bind.get(i).is_some()) && (v.root == Root::Local) {
                    v.root = Root::Act;
                    if let (Some(c), true) = (&self.ctx_override, i == 0 && first_is_ctx) {
                        v.ty = Some(c.clone());
                    }
                }
            }
            fr.locals.insert(prm.name.clone(), v);
        }
        collect_narrowing(code, &mut fr.narrow);
        self.depth += 1;
        self.block(&mut fr, code);
        self.depth -= 1;
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
                self.out.effects.push(Effect { kind: "assign", name: n.clone(), owner, proc: fr.proc.name().to_string(), rel: fr.rel.clone(), line });
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
                    self.out.effects.push(Effect { kind: "assign", name: name.as_str().to_string(), owner: v.ty.clone().unwrap_or_default(), proc: fr.proc.name().to_string(), rel: fr.rel.clone(), line });
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
        if let Some(v) = fr.locals.get(name) {
            return v.clone();
        }
        if name == "vars" {
            let rel = fr.rel.clone();
            self.diag("dynamic_read", &rel, line, "vars[] reads are not allowed in a handler".to_string());
            return Val::local(None);
        }
        // A var of src.
        let this = fr.this.clone();
        self.field(fr, this, name)
    }

    /// `v.name`: a var read on the entity `v` is (when it is tracked), else nothing.
    fn field(&mut self, fr: &mut Frame<'a>, v: Val, name: &str) -> Val {
        let sem = self.eng.sem;
        let rel = fr.rel.clone();
        let line = self.line;
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
                Some(s) => Val::local((!s.declared.is_empty()).then(|| s.declared)),
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
                self.diag("unknown_field", &rel, line, format!("{} has no var `{}`", ty, name));
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
        let is_rel = self.eng.is_relation(&ty_used, name) || self.eng.is_relation(&owner, name);
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
            if !is_rel && sig.is_object() {
                // Followed anyway (the reads stay complete); flagged so classification can say why a hop does not subscribe.
                let msg = format!("hop through `{}` ({}) which is not a declared relation", name, owner);
                self.diag("hop_not_relation", &rel, line, msg);
            }
            return Val { ty: (!sig.declared.is_empty()).then(|| sig.declared.clone()), root: v.root.clone(), hops, hop_ok: v.hop_ok && is_rel, list: sig.is_list() };
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
        if v.root == Root::Act {
            // A.snapshot(), A.captured(...): context API, not a read.
            return Val::local(None);
        }
        let Some(ty) = v.ty.clone() else { return Val::local(None) };
        let Some(p) = sem.proc_ref(&ty, name).filter(|p| !p.ty().get().path.is_empty()) else {
            if v.tracked() && sem.ty(&ty).is_some() && !is_builtin_name(name) && !self.eng.sem.is_subtype(&ty, "/datum/act") {
                self.diag("unknown_call", &rel, line, format!("{} has no proc `{}`", ty, name));
            }
            return Val::local(None);
        };
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
        self.run_proc(p, v, &argv, false);
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
        if impure {
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
}

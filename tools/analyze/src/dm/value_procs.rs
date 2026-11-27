//! Which procs return only numbers or text, found from their bodies (never from their names).
//!
//! A proc definition is *value-returning* when every way it can return yields a number, text or null, or the result of another
//! value-returning proc:
//!
//! * each `return expr`,
//! * each assignment to `.` (a bare `return` and the end of the body both return `.`),
//! * a `..()` / `.()` result, which is the result of the parent or of the proc itself.
//!
//! A value expression is a number, text or type path literal, an interpolated string, arithmetic, a comparison or a unary operator (this tree
//! defines no operator overloads, so none yields an entity), `a || b` / `a && b` when both operands are values, a ternary whose
//! branches both are, a local whose every assignment in the proc is a value, or a call that resolves to value-returning procs or to a
//! DM builtin in [`BUILTIN_VALUE_CALLS`].
//!
//! Two reads are values as well. A read of a builtin `world` var that is a number or text (`world.time`, [`WORLD_VALUE_VARS`]); and a read
//! of a var that holds only values: the declaration of the var and every override of it has no type and a null, number or text initial
//! value, and every assignment to it (any operator) is a value. A var is the type that declares it and its name, so two types that
//! happen to name a var alike do not judge each other. An assignment reaches the one var its receiver's static type (or the proc's own
//! type) finds; an assignment through a receiver of unknown type counts against every var of that name. The proof does not see a write
//! through `vars[...]` or a map instance var; the lint's own rules do not either.
//!
//! A proc whose declaration says `as text` / `as num` returns a value. A parameter is a value when it has no type path (an `as text` input type is
//! allowed: DM does not enforce it for a plain call, so the call sites below still decide), takes a literal default, and every call that can reach
//! its definition passes a value in its position. A call reaches the definitions its receiver's static type (or the calling type, or the global
//! scope) finds and their overrides below that type; only a call on a receiver of unknown type reaches every definition of its name. A
//! definition is ruled out when it is a verb or overrides a DM builtin (a player or the engine supplies the arguments), when a proc reference
//! names it (`PROC_REF(x)` is the calling type's `x`, `TYPE_PROC_REF(T, x)` is `T`'s, `GLOBAL_PROC_REF(x)` the global one: the definitions
//! that type reaches, never a same-named proc on an unrelated type), when a `call(o, "x")` / `hascall(o, "x")` spells its name or the text is
//! assigned to a var that a `call()` takes (a call nothing here sees), and when any call that reaches it uses a named argument or `arglist()`.
//! A local or a var named like a proc is not a mention of the proc. The `..()` of an override hands its parameters up, so a definition's
//! parents share its answer. A method call on a receiver of unknown type is a value when every definition of that name is and no DM builtin
//! type has one.
//!
//! A call resolves by the proc's identity, never by its name: an unscoped call is the proc found on the calling type (walking its
//! parents) or else the global proc; `recv.f()` is found on the static type of `recv`, which must be known. A call may reach an
//! override, so the call is a value only when the found definition and every override on the receiver type or below it are. A proc
//! that is declared and never defined by a body returns null.
//!
//! The answer is the greatest fixpoint: every definition starts as a value-returning one and loses the title when a return path does
//! not qualify, until nothing changes. Recursion therefore terminates (the set only shrinks) and a cycle with no other way out stays
//! as it is, since it returns nothing at all.
//!
//! It is solved with a worklist: each evaluation records the facts it read (another definition's answer, the definitions of a name, a
//! var's verdict); when a fact turns false, only its readers are evaluated again, and a definition whose parameters lose a position is
//! evaluated again. An evaluation that read nothing that changed gives the same answer and the same narrowing, so this is the fixpoint
//! the round-by-round loop (`DQ_VALUE_PROCS_VERIFY=1` runs both and compares) reaches, without re-reading every body each round.
//!
//! Between runs the solution is kept (`data/analyze-cache/value-procs.bin`) with who read each fact and who would take each one out.
//! When only bodies changed (same structure, same starting candidates), the facts the changed definitions took out are put back, and
//! with them every fact only definitions affected by those took out, and just those definitions are evaluated again. Any other
//! change solves from the start.

use std::cell::RefCell;
use std::collections::{HashMap, HashSet};

use dm_syntax::{Expr, Statement};

use crate::lints::stored_refs::{collect_locals, path_of, prefab_path, ProcScope, Walker};
use crate::model::expr::{chain, form, literal, strip_groups, Args, Chain, Form, Hop, Lit, Root};
use crate::model::procs::Proc;
use crate::model::walk::{stmt_blocks, stmts, ForInit, Stmt, VarDecl, Visit};
use crate::sem::Sem;

/// DM builtins whose result is never an entity. Used only when the name is not a proc of the tree.
pub const BUILTIN_VALUE_CALLS: &[&str] = &[
    "rand", "prob", "round", "floor", "ceil", "abs", "min", "max", "sqrt", "sin", "cos", "num2text", "text2num", "list2params", "length", "lowertext", "uppertext", "copytext",
    "replacetext", "findtext", "jointext", "get_dist", "nameof", "ckey", "clamp", "isnull", "initial", "md5", "replacetextEx", "turn", "get_dir", "html_decode", "html_encode",
    "text2ascii", "ascii2text", "file2text", "rgb", "istype", "ispath", "islist", "isnum", "istext", "time2text", "addtext", "splittext", "json_encode", "text2path", "trim",
    "ref", "url_encode", "url_decode", "sha1", "findtextEx", "findlasttext", "findlasttextEx", "findtext_char", "length_char", "copytext_char", "sorttext", "sorttextEx", "log", "tan", "arcsin", "arccos", "arctan", "sign", "text",
    "roll", "cmptext", "cmptextEx", "lentext", "winget", "fexists", "file", "hascall",
];

/// Methods of the DM builtin types (`list.Find`, `list.Join`, `regex.Replace`) whose result is a number or text. Used for a method call
/// on a receiver of unknown type, and only when no proc of the tree has that name (so the call can reach nothing but the builtin).
pub const BUILTIN_VALUE_METHODS: &[&str] = &["Find", "Join", "Replace"];

/// Methods of the builtin `/regex` type that return a number (`Find`) or text (`Replace`); used when the receiver is statically a regex.
const REGEX_VALUE_METHODS: &[&str] = &["Find", "Replace"];

/// The config entry classes whose stored value is a number, flag or text (`ValidateAndSet` of the class is the only writer): a
/// `global.config.Get(/datum/config_entry/number/x)` read is then a value.
const CONFIG_VALUE_CLASSES: &[&str] = &["/datum/config_entry/number", "/datum/config_entry/flag", "/datum/config_entry/string"];
const CONFIG_TYPE: &str = "/datum/controller/configuration";

/// Builtin `world` vars that are a number, text or null.
pub const WORLD_VALUE_VARS: &[&str] = &[
    "time", "timeofday", "realtime", "tick_lag", "tick_usage", "cpu", "map_cpu", "maxx", "maxy", "maxz", "fps", "byond_version", "byond_build", "port", "address", "name", "version",
];

type DefKey = (String, String, usize);

/// What a call resolves to.
#[derive(Clone)]
enum Target {
    /// A DM builtin or a name nothing in the tree defines.
    Builtin,
    /// The definitions the call can run.
    Defs(Vec<usize>),
}

pub(crate) struct ValueProcs<'a, 'k> {
    sem: &'a Sem,
    w: &'a Walker<'a, 'k>,
    ids: HashMap<DefKey, usize>,
    /// `value[id]` after the fixpoint.
    value: Vec<bool>,
    /// The definition `..()` reaches from each definition (None: a builtin or nothing).
    parent: Vec<Option<usize>>,
    /// The final definition of each type's own proc `name`, for finding overrides.
    finals: HashMap<String, Vec<(String, usize)>>,
    targets: RefCell<HashMap<(String, String), Target>>,
    /// Var names that still hold only values (candidates start in; an assignment of a non-value takes a name out).
    vars: RefCell<HashMap<String, bool>>,
    /// Var name -> every key of `vars` with that name, for a write whose receiver cannot be typed.
    var_keys: HashMap<String, Vec<String>>,
    /// Per definition, per parameter position: still known to receive only values at every call that can reach it. A call reaches the
    /// definitions its receiver's static type finds (and their overrides); only a call whose receiver cannot be typed, a string naming the
    /// proc and a `call()` reach every definition of a name.
    params: RefCell<Vec<Vec<bool>>>,
    /// The name of each definition.
    def_names: Vec<String>,
    /// Name -> its definitions, in id order (a call on a receiver of unknown type, a name a string spells).
    by_name: HashMap<String, Vec<usize>>,
    /// Names of the procs the tree itself defines with a body or declaration (not the DM builtin types').
    tree_names: HashSet<String>,
    /// Names of the procs the DM builtin types define.
    builtin_names: HashSet<String>,
    /// The definition being evaluated, whose reads are recorded (worklist mode).
    current: std::cell::Cell<Option<usize>>,
    /// Who read a fact: the definitions to evaluate again when it turns false.
    readers: RefCell<HashMap<Fact, Vec<usize>>>,
    /// Definitions to evaluate again (a fact they read turned false, or their parameters narrowed).
    queue: RefCell<std::collections::VecDeque<usize>>,
    queued: RefCell<Vec<bool>>,
    /// Who would take a fact out (a var or a parameter position), whether or not it is still in: what may put it back after an edit.
    takers: RefCell<HashMap<Fact, Vec<usize>>>,
}

/// A fact an evaluation reads or takes out.
#[derive(Clone, PartialEq, Eq, Hash, serde::Serialize, serde::Deserialize)]
enum Fact {
    /// A definition's answer.
    Value(usize),
    /// Every definition of a name (a call on a receiver of unknown type).
    Name(String),
    /// A var's verdict (`var_key`).
    Var(String),
    /// A parameter position of a definition.
    Param(usize, usize),
    /// The bodies of one type's procs (read by `config_class_clean`).
    TypeBodies(String),
}

/// The kept solution (see the module doc).
#[derive(serde::Serialize, serde::Deserialize)]
struct Saved {
    stamp: String,
    structure: u128,
    defs: Vec<DefKey>,
    bodies: Vec<u128>,
    init_vars: Vec<(String, bool)>,
    init_params: Vec<Vec<bool>>,
    value: Vec<bool>,
    vars: Vec<(String, bool)>,
    params: Vec<Vec<bool>>,
    readers: Vec<(Fact, Vec<u32>)>,
    takers: Vec<(Fact, Vec<u32>)>,
}

fn sorted_vars(v: &HashMap<String, bool>) -> Vec<(String, bool)> {
    let mut out: Vec<(String, bool)> = v.iter().map(|(k, b)| (k.clone(), *b)).collect();
    out.sort();
    out
}

fn pack(m: &HashMap<Fact, Vec<usize>>) -> Vec<(Fact, Vec<u32>)> {
    m.iter()
        .map(|(f, v)| {
            let mut ids: Vec<u32> = v.iter().map(|i| *i as u32).collect();
            ids.sort_unstable();
            ids.dedup();
            (f.clone(), ids)
        })
        .collect()
}

fn unpack(v: Vec<(Fact, Vec<u32>)>) -> HashMap<Fact, Vec<usize>> {
    v.into_iter().map(|(f, ids)| (f, ids.into_iter().map(|i| i as usize).collect())).collect()
}

fn saved_path() -> Option<std::path::PathBuf> {
    crate::incr::dir().map(|d| d.join("value-procs.bin"))
}

struct Ctx<'c> {
    sc: &'c ProcScope<'c>,
    locals: &'c HashSet<String>,
    def: Option<usize>,
}

fn type_key(path: &str) -> String {
    if path.is_empty() { "/".to_string() } else { path.to_string() }
}

impl<'a, 'k> ValueProcs<'a, 'k> {
    pub(crate) fn build(sem: &'a Sem, w: &'a Walker<'a, 'k>) -> Self {
        let trace = dq_hostio::var_os("DQ_ANALYZE_TRACE").is_some();
        let t0 = std::time::Instant::now();
        let lap = |what: &str| {
            if trace {
                eprintln!("value_procs: {what} after {:.2?}", t0.elapsed());
            }
        };
        let mut ids: HashMap<DefKey, usize> = HashMap::new();
        let mut refs: Vec<Proc<'a>> = Vec::new();
        let mut finals: HashMap<String, Vec<(String, usize)>> = HashMap::new();
        for ty in sem.m().types() {
            let path = ty.path().to_string();
            for name in ty.proc_names() {
                let defined = ty.proc_definitions(name).len();
                if defined == 0 {
                    continue;
                }
                let Some(mut r) = ty.proc(name) else { continue };
                loop {
                    let id = refs.len();
                    ids.insert((path.clone(), name.to_string(), r.index()), id);
                    if r.index() + 1 == defined {
                        finals.entry(name.to_string()).or_default().push((path.clone(), id));
                    }
                    refs.push(r);
                    if r.index() == 0 {
                        break;
                    }
                    match r.parent_proc() {
                        Some(p) => r = p,
                        None => break,
                    }
                }
            }
        }
        let parent: Vec<Option<usize>> = refs.iter().map(|r| r.parent_proc().filter(|p| !p.is_builtin()).and_then(|p| ids.get(&(p.owner().path().to_string(), p.name().to_string(), p.index())).copied())).collect();
        lap("definitions");
        let vars = value_var_candidates(sem);
        lap("var candidates");
        let mut var_keys: HashMap<String, Vec<String>> = HashMap::new();
        for k in vars.keys() {
            if let Some((_, n)) = k.rsplit_once("::") {
                var_keys.entry(n.to_string()).or_default().push(k.clone());
            }
        }
        let def_names: Vec<String> = refs.iter().map(|r| r.name().to_string()).collect();
        let mut by_name: HashMap<String, Vec<usize>> = HashMap::new();
        for (i, n) in def_names.iter().enumerate() {
            by_name.entry(n.clone()).or_default().push(i);
        }
        let (params, names, proc_refs) = param_candidates(sem, &refs);
        lap("parameter candidates");
        let tree_names: HashSet<String> = refs.iter().filter(|r| !r.is_builtin()).map(|r| r.name().to_string()).collect();
        let mut builtin_names: HashSet<String> = HashSet::new();
        for ty in sem.m().types() {
            for name in ty.proc_names() {
                if ty.proc_definitions(name).iter().any(|v| v.is_builtin()) {
                    builtin_names.insert(name.to_string());
                }
            }
        }
        let mut me = ValueProcs { sem, w, ids, value: vec![true; refs.len()], parent, finals, targets: RefCell::new(HashMap::new()), vars: RefCell::new(vars), var_keys, params: RefCell::new(params), by_name, def_names, tree_names, builtin_names, current: std::cell::Cell::new(None), readers: RefCell::new(HashMap::new()), queue: RefCell::new(std::collections::VecDeque::new()), queued: RefCell::new(vec![false; refs.len()]), takers: RefCell::new(HashMap::new()) };
        for n in names.iter() {
            let ids: Vec<usize> = me.defs_named(n).to_vec();
            me.bar(&ids);
        }
        for (owner, name) in proc_refs.iter() {
            match me.target(owner, name) {
                Target::Defs(d) => me.bar(&d),
                // A reference to a name no definition is found for on that type: judged by name, the safe side.
                Target::Builtin => {
                    let ids: Vec<usize> = me.defs_named(name).to_vec();
                    me.bar(&ids);
                }
            }
        }
        lap("barred");
        let init_vars = me.vars.borrow().clone();
        let init_params = me.params.borrow().clone();
        let keep = sem.cacheable();
        let structure = if keep { sem.structure_digest() } else { 0 };
        let defs: Vec<DefKey> = refs.iter().map(|r| (r.owner().path().to_string(), r.name().to_string(), r.index())).collect();
        let bodies: Vec<u128> = refs.iter().map(|r| sem.site_key(r.site())).collect();
        let stamp = crate::incr::stamp().unwrap_or_default();
        let saved = if keep { Self::load(&stamp, structure, &defs, &init_vars, &init_params) } else { None };
        let incremental = saved.is_some();
        match saved {
            Some(saved) => me.solve_from(&refs, saved, &bodies),
            None => me.solve_worklist(&refs),
        }
        lap(if incremental { "fixpoint (kept, changed bodies only)" } else { "fixpoint" });
        if dq_hostio::var_os("DQ_VALUE_PROCS_VERIFY").is_some() {
            me.verify(&refs, &init_vars, &init_params, incremental);
        }
        if keep {
            me.save(stamp, structure, defs, bodies, &init_vars, init_params);
        }
        me
    }

    /// The kept solution, when it was made for this structure and these starting candidates.
    fn load(stamp: &str, structure: u128, defs: &[DefKey], init_vars: &HashMap<String, bool>, init_params: &[Vec<bool>]) -> Option<Saved> {
        let bytes = std::fs::read(saved_path()?).ok()?;
        let saved: Saved = crate::incr::de(&bytes).ok()?;
        (saved.stamp == stamp && saved.structure == structure && saved.defs == defs && saved.init_vars == sorted_vars(init_vars) && saved.init_params == init_params)
            .then_some(saved)
    }

    fn save(&self, stamp: String, structure: u128, defs: Vec<DefKey>, bodies: Vec<u128>, init_vars: &HashMap<String, bool>, init_params: Vec<Vec<bool>>) {
        let Some(path) = saved_path() else { return };
        let saved = Saved {
            stamp,
            structure,
            defs,
            bodies,
            init_vars: sorted_vars(init_vars),
            init_params,
            value: self.value.clone(),
            vars: sorted_vars(&self.vars.borrow()),
            params: self.params.borrow().clone(),
            readers: pack(&self.readers.borrow()),
            takers: pack(&self.takers.borrow()),
        };
        if let Ok(bytes) = crate::incr::ser(&saved) {
            let tmp = path.with_extension(format!("tmp{}", std::process::id()));
            if std::fs::write(&tmp, &bytes).is_ok() {
                let _ = std::fs::rename(&tmp, &path);
            }
        }
    }

    /// From the kept solution: put back what the changed definitions (and, in turn, what they affected) took out, evaluate those again.
    fn solve_from(&mut self, refs: &[Proc<'a>], saved: Saved, bodies: &[u128]) {
        self.value = saved.value;
        *self.vars.borrow_mut() = saved.vars.into_iter().collect();
        *self.params.borrow_mut() = saved.params;
        *self.readers.borrow_mut() = unpack(saved.readers);
        *self.takers.borrow_mut() = unpack(saved.takers);
        let init_vars: HashMap<String, bool> = saved.init_vars.into_iter().collect();
        let init_params = saved.init_params;
        // What each definition would take out.
        let mut takes: Vec<Vec<Fact>> = vec![Vec::new(); refs.len()];
        for (f, ids) in self.takers.borrow().iter() {
            for &d in ids {
                takes[d].push(f.clone());
            }
        }
        let changed: Vec<usize> = (0..refs.len()).filter(|&i| saved.bodies.get(i) != Some(&bodies[i])).collect();
        let mut affected = vec![false; refs.len()];
        let mut back: HashSet<Fact> = HashSet::new();
        let mut stack: Vec<usize> = changed.clone();
        // A changed body changes what `config_class_clean` reads of its type.
        for &d in &changed {
            let ty = type_key(refs[d].owner().path());
            if let Some(r) = self.readers.borrow().get(&Fact::TypeBodies(ty)) {
                stack.extend(r.iter().copied());
            }
        }
        while let Some(d) = stack.pop() {
            if affected[d] {
                continue;
            }
            affected[d] = true;
            let mut facts: Vec<Fact> = takes[d].clone();
            facts.push(Fact::Value(d));
            for f in facts {
                if back.contains(&f) {
                    continue;
                }
                let out = match &f {
                    Fact::Value(i) => !self.value[*i],
                    Fact::Var(k) => !self.vars.borrow().get(k).copied().unwrap_or(true) && init_vars.get(k).copied().unwrap_or(false),
                    Fact::Param(i, j) => {
                        !self.params.borrow()[*i].get(*j).copied().unwrap_or(true) && init_params[*i].get(*j).copied().unwrap_or(false)
                    }
                    _ => false,
                };
                if !out {
                    continue;
                }
                // Out only by affected definitions: it may come back. A taker that is not affected still takes it out.
                let all_affected = match &f {
                    Fact::Value(_) => true,
                    _ => self.takers.borrow().get(&f).is_none_or(|t| t.iter().all(|t| affected[*t])),
                };
                if !all_affected {
                    continue;
                }
                back.insert(f.clone());
                let readers = self.readers.borrow();
                if let Some(r) = readers.get(&f) {
                    stack.extend(r.iter().copied());
                }
                match &f {
                    Fact::Value(i) => {
                        if let Some(r) = readers.get(&Fact::Name(self.def_names[*i].clone())) {
                            stack.extend(r.iter().copied());
                        }
                    }
                    Fact::Param(i, _) => stack.push(*i),
                    _ => {}
                }
            }
            // A taker that joins later may free a fact an earlier one held: look at its facts' other takers again.
            for f in &takes[d] {
                if let Some(t) = self.takers.borrow().get(f) {
                    for &o in t {
                        if affected[o] && o != d {
                            stack.push(o);
                        }
                    }
                }
            }
        }
        // The facts come back as they started; the affected definitions forget what they would take out and are evaluated again.
        for f in &back {
            match f {
                Fact::Value(i) => self.value[*i] = true,
                Fact::Var(k) => {
                    self.vars.borrow_mut().insert(k.clone(), true);
                }
                Fact::Param(i, j) => self.params.borrow_mut()[*i][*j] = true,
                _ => {}
            }
        }
        {
            let mut takers = self.takers.borrow_mut();
            for ids in takers.values_mut() {
                ids.retain(|d| !affected[*d]);
            }
            takers.retain(|_, ids| !ids.is_empty());
        }
        let queue: Vec<usize> = (0..refs.len()).filter(|&d| affected[d]).collect();
        if dq_hostio::var_os("DQ_ANALYZE_TRACE").is_some() {
            eprintln!("value_procs: {} changed bodies, {} definitions affected, {} facts put back", changed.len(), queue.len(), back.len());
        }
        self.run_queue(refs, queue);
    }

    /// `DQ_VALUE_PROCS_VERIFY`: the answer must be the plain repeat-until-stable fixpoint from the same start.
    fn verify(&mut self, refs: &[Proc<'a>], init_vars: &HashMap<String, bool>, init_params: &[Vec<bool>], incremental: bool) {
        let got = (self.value.clone(), self.vars.borrow().clone(), self.params.borrow().clone());
        let tables = (self.readers.borrow().clone(), self.takers.borrow().clone());
        self.value = vec![true; refs.len()];
        *self.vars.borrow_mut() = init_vars.clone();
        *self.params.borrow_mut() = init_params.to_vec();
        self.solve_rounds(refs);
        let want = (self.value.clone(), self.vars.borrow().clone(), self.params.borrow().clone());
        let same = got == want;
        eprintln!("value_procs verify: {} and rounds {}", if incremental { "kept solution" } else { "worklist" }, if same { "agree" } else { "DIFFER" });
        if !same {
            let count = |v: &[bool]| v.iter().filter(|b| **b).count();
            eprintln!("  values true: got {} want {}", count(&got.0), count(&want.0));
            for (i, (a, b)) in got.0.iter().zip(want.0.iter()).enumerate().filter(|(_, (a, b))| a != b).take(8) {
                eprintln!("  def {} {}::{}: got {} want {}", i, refs[i].owner().path(), refs[i].name(), a, b);
            }
            for (k, b) in want.1.iter().filter(|(k, b)| got.1.get(*k) != Some(*b)).take(8) {
                eprintln!("  var {}: got {:?} want {}", k, got.1.get(k), b);
            }
            let gp: usize = got.2.iter().map(|v| count(v)).sum();
            let wp: usize = want.2.iter().map(|v| count(v)).sum();
            eprintln!("  params true: got {} want {}", gp, wp);
        }
        assert!(same, "value_procs: the solution differs from the round-by-round fixpoint");
        self.value = got.0;
        *self.vars.borrow_mut() = got.1;
        *self.params.borrow_mut() = got.2;
        *self.readers.borrow_mut() = tables.0;
        *self.takers.borrow_mut() = tables.1;
    }

    /// The fixpoint by worklist (see the module doc).
    fn solve_worklist(&mut self, refs: &[Proc<'a>]) {
        self.run_queue(refs, (0..refs.len()).collect());
    }

    /// Evaluates `start` (in order), then whatever their changes wake, until the queue is empty.
    fn run_queue(&mut self, refs: &[Proc<'a>], start: Vec<usize>) {
        {
            let mut q = self.queue.borrow_mut();
            let mut queued = self.queued.borrow_mut();
            for id in start {
                if !queued[id] {
                    q.push_back(id);
                    queued[id] = true;
                }
            }
        }
        let mut evaluations = 0usize;
        loop {
            let next = self.queue.borrow_mut().pop_front();
            let Some(id) = next else { break };
            evaluations += 1;
            self.queued.borrow_mut()[id] = false;
            // A definition that already lost the title is still evaluated: its var writes and calls narrow the vars and parameters
            // whatever it returns, and with the facts it read gone false they may narrow more.
            self.current.set(Some(id));
            let ok = self.eval_def(id, refs[id]);
            self.current.set(None);
            if !ok && self.value[id] {
                self.value[id] = false;
                self.wake(&Fact::Value(id));
                let name = self.def_names[id].clone();
                self.wake(&Fact::Name(name));
            }
        }
        if dq_hostio::var_os("DQ_ANALYZE_TRACE").is_some() {
            eprintln!("value_procs: {} evaluations of {} definitions", evaluations, refs.len());
        }
    }

    /// The reference fixpoint for `DQ_VALUE_PROCS_VERIFY`: every definition is evaluated again, round after round, until a round changes
    /// no fact. (The loop this replaced stopped evaluating a definition once it lost the title, so the narrowing its writes and calls
    /// would make under later facts was lost and the answer depended on the order of the definitions.)
    fn solve_rounds(&mut self, refs: &[Proc<'a>]) {
        loop {
            let before = (self.value.clone(), self.vars.borrow().clone(), self.params.borrow().clone());
            for id in 0..refs.len() {
                let ok = self.eval_def(id, refs[id]);
                if !ok {
                    self.value[id] = false;
                }
            }
            if before == (self.value.clone(), self.vars.borrow().clone(), self.params.borrow().clone()) {
                break;
            }
        }
    }

    /// Records that the definition being evaluated read `fact`.
    fn read(&self, fact: Fact) {
        if let Some(c) = self.current.get() {
            let mut r = self.readers.borrow_mut();
            let v = r.entry(fact).or_default();
            if v.last() != Some(&c) {
                v.push(c);
            }
        }
    }

    /// Records that the definition being evaluated would take `fact` out.
    fn take(&self, fact: Fact) {
        if let Some(c) = self.current.get() {
            let mut t = self.takers.borrow_mut();
            let v = t.entry(fact).or_default();
            if v.last() != Some(&c) {
                v.push(c);
            }
        }
    }

    /// `fact` turned false: queue its readers.
    fn wake(&self, fact: &Fact) {
        let readers = self.readers.borrow_mut().remove(fact);
        for id in readers.into_iter().flatten() {
            self.enqueue(id);
        }
    }

    fn enqueue(&self, id: usize) {
        let mut queued = self.queued.borrow_mut();
        if !queued[id] {
            queued[id] = true;
            self.queue.borrow_mut().push_back(id);
        }
    }

    fn defs_named(&self, name: &str) -> &[usize] {
        self.by_name.get(name).map(|v| v.as_slice()).unwrap_or(&[])
    }

    fn id_of(&self, r: Proc<'a>) -> Option<usize> {
        self.ids.get(&(r.owner().path().to_string(), r.name().to_string(), r.index())).copied()
    }

    /// The definitions a call of `name` on static type `ty` can run; `Builtin` when the lookup ends in a DM builtin or nothing.
    fn target(&self, ty: &str, name: &str) -> Target {
        let key = (ty.to_string(), name.to_string());
        if let Some(t) = self.targets.borrow().get(&key) {
            return t.clone();
        }
        let t = self.resolve(ty, name);
        self.targets.borrow_mut().insert(key, t.clone());
        t
    }

    fn resolve(&self, ty: &str, name: &str) -> Target {
        let found = if ty == "/" { self.sem.global_proc(name) } else { self.sem.proc_ref(ty, name) };
        let Some(r) = found else { return Target::Builtin };
        if r.is_builtin() {
            return Target::Builtin;
        }
        let Some(id) = self.id_of(r) else { return Target::Builtin };
        let mut defs = vec![id];
        if ty != "/" && r.owner().path() != "/" {
            for (d, fid) in self.finals.get(name).map(|v| v.as_slice()).unwrap_or(&[]) {
                if d != r.owner().path() && self.sem.is_subtype(d, ty) {
                    defs.push(*fid);
                }
            }
        }
        defs.sort_unstable();
        defs.dedup();
        Target::Defs(defs)
    }

    fn defs_value(&self, defs: &[usize]) -> bool {
        for d in defs {
            self.read(Fact::Value(*d));
            if !self.value[*d] {
                return false;
            }
        }
        true
    }

    fn call_value(&self, owner: &str, name: &str, builtin_ok: bool) -> bool {
        match self.target(owner, name) {
            Target::Defs(d) => self.defs_value(&d),
            Target::Builtin => builtin_ok && BUILTIN_VALUE_CALLS.contains(&name),
        }
    }

    fn value_expr(&self, ctx: &Ctx, e: &Expr) -> bool {
        let e = strip_groups(e);
        match form(e) {
            Form::Binary { op, lhs, rhs } => match op {
                "&&" | "||" => self.value_expr(ctx, lhs) && self.value_expr(ctx, rhs),
                _ => true,
            },
            Form::Assign { op, rhs, .. } => match op {
                "=" | ":=" | "&&=" | "||=" => self.value_expr(ctx, rhs),
                _ => true,
            },
            Form::Ternary { then_value, else_value, .. } => self.value_expr(ctx, then_value) && self.value_expr(ctx, else_value),
            Form::Chain(c) => {
                if let Some(last) = c.hops.last() {
                    let n = c.hops.len();
                    return match last {
                        Hop::Unary { op, .. } => !matches!(*op, "&" | "*"),
                        Hop::Field { name, .. } if n == 1 && matches!(&c.root, Root::Ident("world")) => WORLD_VALUE_VARS.contains(name),
                        Hop::Field { name, .. } => match self.w.type_of(ctx.sc, c.prefix_node(n - 1)) {
                            Some(t) if !t.is_empty() => self.var_value(&t, name),
                            _ => false,
                        },
                        Hop::Call { name, .. } if n == 1 && matches!(&c.root, Root::Ident("global")) => self.call_value("/", name, true),
                        Hop::Call { name, args, .. } if *name == "Get" && self.config_value_get(ctx, &c, *args) => true,
                        Hop::Call { name, .. } => match self.w.type_of(ctx.sc, c.prefix_node(n - 1)) {
                            Some(t) if !t.is_empty() => self.call_value(&t, name, false) || (t == "/regex" && REGEX_VALUE_METHODS.contains(name) && self.sem.proc_ref("/regex", name).is_none_or(|r| r.is_builtin())) || (BUILTIN_VALUE_METHODS.contains(name) && !self.tree_names.contains(*name)),
                            _ => self.any_receiver_value(name),
                        },
                        _ => false,
                    };
                }
                match &c.root {
                    Root::Literal(_) => true,
                    Root::Ident(n) if matches!(*n, "__PROC__" | "__TYPE__") => true,
                    // A type path literal (`/datum/msg/op/busy`) names a type, never an instance (doc/rewrite/proposals/typed_values.md section 5).
                    Root::Prefab { .. } => true,
                    // A parenthesized expression is stripped above; a group that is its own node reads as nothing.
                    Root::Group(inner) => !std::ptr::eq(*inner, e) && self.value_expr(ctx, inner),
                    Root::Ident(n) => *n == "." || ctx.locals.contains(*n) || (!ctx.sc.locals.contains_key(*n) && self.var_value(ctx.sc.owner, n)),
                    Root::Pick(choices) => choices.iter().all(|(w, v)| w.is_none_or(|w| self.value_expr(ctx, w)) && self.value_expr(ctx, v)),
                    Root::Call { name, args } if (*name == "pick" || *name == "pickweight") && matches!(self.target(ctx.sc.owner, name), Target::Builtin) => self.pick_value(ctx, *args),
                    Root::Call { name, .. } => {
                        let owner = if ctx.sc.owner == "/" { "/" } else { ctx.sc.owner };
                        self.call_value(owner, name, true)
                    }
                    // `call_ext(lib, fn)(args)` hands back the external function's text (or null), never a reference.
                    Root::ExternalCall { .. } => true,
                    Root::ParentCall(_) => match ctx.def {
                        Some(id) => self.parent_value(id),
                        None => false,
                    },
                    Root::SelfCall(_) => match ctx.def {
                        Some(id) => {
                            self.read(Fact::Value(id));
                            self.value[id]
                        }
                        None => false,
                    },
                    _ => false,
                }
            }
        }
    }

    /// `pick(a, b, c)` over value arguments, or `pick(list(...))` / `pickweight(list(...))` over a literal list of values (and value keys).
    fn pick_value(&self, ctx: &Ctx, args: Args<'_>) -> bool {
        let item = |e: &Expr| {
            let e = strip_groups(e);
            match form(e) {
                Form::Assign { op: "=", lhs, rhs } => self.value_expr(ctx, lhs) && self.value_expr(ctx, rhs),
                _ => self.value_expr(ctx, e),
            }
        };
        let all: Vec<&Expr> = args.iter().collect();
        match all.as_slice() {
            [one] => match chain(strip_groups(one)) {
                Some(c) if c.hops.is_empty() => match &c.root {
                    Root::List(items) => items.iter().all(item),
                    _ => false,
                },
                _ => false,
            },
            _ => !all.is_empty() && all.iter().all(|e| item(e)),
        }
    }

    /// `recv.Get(/datum/config_entry/number/x)` where `recv` is the configuration controller and the entry is a number, flag or string
    /// entry whose class is the only definer of `ValidateAndSet` on the path (no subtype stores anything else). `c` is the whole call
    /// chain: its last hop is the `Get`, what precedes it the receiver.
    fn config_value_get(&self, ctx: &Ctx, c: &Chain<'_>, args: Args<'_>) -> bool {
        if args.len() != 1 {
            return false;
        }
        let Some(arg) = args.first() else { return false };
        let Some(ac) = chain(strip_groups(arg)) else { return false };
        let Root::Prefab { path: p, .. } = &ac.root else { return false };
        if !ac.hops.is_empty() {
            return false;
        }
        let path = prefab_path(p);
        let before = c.hops.len() - 1;
        let recv = c.prefix_node(before);
        let global_recv = match (&c.root, before) {
            (Root::Ident("global"), 1) => match &c.hops[0] {
                Hop::Field { name: n, .. } => self.sem.var_decl("/", n).is_some_and(|d| d.declared == CONFIG_TYPE),
                _ => false,
            },
            _ => false,
        };
        if !global_recv && self.w.type_of(ctx.sc, recv).as_deref() != Some(CONFIG_TYPE) {
            return false;
        }
        let Some(class) = CONFIG_VALUE_CLASSES.iter().find(|c| path == **c || path.starts_with(&format!("{c}/"))) else { return false };
        self.config_class_clean(&path, class)
    }

    /// No type from `path` up to (not including) `class` assigns `config_entry_value`: the class's `ValidateAndSet` stays its one writer, so a
    /// subtype that only adds a side effect (`. = ..()` then a call) still holds a number, flag or text.
    fn config_class_clean(&self, path: &str, class: &str) -> bool {
        let Some(mut cur) = self.sem.ty(path) else { return false };
        loop {
            if type_key(cur.path()) == class {
                return true;
            }
            self.read(Fact::TypeBodies(type_key(cur.path())));
            for name in cur.proc_names() {
                for v in cur.proc_definitions(name) {
                    let Some(code) = v.body() else { continue };
                    let mut writes = false;
                    for_each_expr(code, &mut |vis| {
                        let Form::Assign { lhs, .. } = &vis.form else { return };
                        let Some(c) = chain(strip_groups(lhs)) else { return };
                        writes |= match c.hops.last() {
                            Some(last) => matches!(last, Hop::Field { name, .. } if *name == "config_entry_value"),
                            None => matches!(&c.root, Root::Ident("config_entry_value")),
                        };
                    });
                    if writes {
                        return false;
                    }
                }
            }
            match cur.parent() {
                Some(p) => cur = p,
                None => return false,
            }
        }
    }

    /// Whether the var `name` read on type `ty` holds only values.
    fn var_value(&self, ty: &str, name: &str) -> bool {
        let Some(sig) = self.sem.var_decl(ty, name) else { return false };
        let Some(owner) = self.sem.var_owner(ty, name) else { return false };
        if !sig.declared.is_empty() {
            return false;
        }
        let key = var_key(&owner, name);
        let v = self.vars.borrow().get(&key).copied();
        if v.is_some() {
            // Read whether in or out: a var that is put back after an edit must wake whoever saw it out.
            self.read(Fact::Var(key));
        }
        v.unwrap_or(false)
    }

    /// Takes out of `vars` every var that `code` assigns a non-value to. A write through a receiver of known type (or to the proc's own var)
    /// takes out the one var it reaches, found by the type that declares it; a write through a receiver of unknown type takes out every
    /// var of that name.
    fn scan_var_writes(&self, ctx: &Ctx, code: &[Statement]) {
        for_each_expr(code, &mut |vis| {
            let Form::Assign { lhs, rhs, .. } = &vis.form else { return };
            let Some(c) = chain(strip_groups(lhs)) else { return };
            let (name, owner): (String, Option<String>) = match c.hops.last() {
                Some(last) => match last {
                    Hop::Field { name: n, .. } => {
                        let recv = c.prefix_node(c.hops.len() - 1);
                        let owner = match self.w.type_of(ctx.sc, recv) {
                            Some(t) if !t.is_empty() && t != "/" => self.sem.var_owner(&t, n),
                            _ => None,
                        };
                        (n.to_string(), owner)
                    }
                    Hop::Static { name: n, .. } => (n.to_string(), None),
                    _ => return,
                },
                None => match &c.root {
                    Root::Ident(n) if !ctx.sc.locals.contains_key(*n) && *n != "." => {
                        let owner = if ctx.sc.owner == "/" { None } else { self.sem.var_owner(ctx.sc.owner, n) };
                        (n.to_string(), owner)
                    }
                    _ => return,
                },
            };
            let keys: Vec<String> = match owner {
                Some(o) => vec![var_key(&o, &name)],
                None => self.var_keys.get(&name).cloned().unwrap_or_default(),
            };
            let keys: Vec<String> = keys.into_iter().filter(|k| self.vars.borrow().contains_key(k)).collect();
            if keys.is_empty() {
                return;
            }
            // Judged even when every var it reaches is already out: who would take a var out is what may put it back after an edit.
            if !self.value_expr(ctx, rhs) {
                let mut killed = Vec::new();
                {
                    for k in &keys {
                        self.take(Fact::Var(k.clone()));
                    }
                    let mut vars = self.vars.borrow_mut();
                    for k in keys {
                        if let Some(b) = vars.get_mut(&k) {
                            if *b {
                                *b = false;
                                killed.push(k);
                            }
                        }
                    }
                }
                for k in killed {
                    self.wake(&Fact::Var(k));
                }
            }
        });
    }

    /// A method call `x.name()` whose receiver has no static type: it runs some definition named `name`, so it is a value when every
    /// definition of that name in the tree is and no DM builtin type has a proc of that name.
    fn any_receiver_value(&self, name: &str) -> bool {
        if self.builtin_names.contains(name) {
            return false;
        }
        if BUILTIN_VALUE_METHODS.contains(&name) && !self.tree_names.contains(name) {
            return true;
        }
        self.read(Fact::Name(name.to_string()));
        let defs = self.defs_named(name);
        !defs.is_empty() && defs.iter().all(|i| self.value[*i])
    }

    /// `id` and the definitions its `..()` reaches: a call that reaches `id` hands the same arguments up the chain.
    fn up_chain(&self, id: usize) -> Vec<usize> {
        let mut out = vec![id];
        let mut cur = id;
        while let Some(p) = self.parent[cur] {
            if out.contains(&p) {
                break;
            }
            out.push(p);
            cur = p;
        }
        out
    }

    /// Takes every parameter of the definitions out of `params` for good (something calls them with arguments nothing here can see).
    fn bar(&self, ids: &[usize]) {
        for id in ids {
            self.kill_def(*id, None);
        }
    }

    /// Takes a parameter position (all of them: None) of a definition and of the definitions above it out of `params` for good.
    fn kill_def(&self, id: usize, i: Option<usize>) {
        let mut narrowed = Vec::new();
        {
            let mut ps = self.params.borrow_mut();
            for d in self.up_chain(id) {
                let mut hit = false;
                for (j, b) in ps[d].iter_mut().enumerate() {
                    if i.is_none_or(|i| i == j) {
                        self.take(Fact::Param(d, j));
                        if *b {
                            *b = false;
                            hit = true;
                        }
                    }
                }
                if hit {
                    narrowed.push(d);
                }
            }
        }
        // A definition reads its own parameters' verdicts: evaluate it again.
        for d in narrowed {
            self.enqueue(d);
        }
    }

    /// The definitions a call of `name` on static type `ty` reaches (none for a DM builtin or a name nothing defines).
    fn call_defs(&self, ty: &str, name: &str) -> Option<Vec<usize>> {
        match self.target(ty, name) {
            Target::Defs(d) => Some(d),
            Target::Builtin => Some(Vec::new()),
        }
    }

    /// One call: a position that gets a non-value, a named argument or an `arglist()` leaves `params` of the definitions the call reaches
    /// (`defs`; None: its receiver cannot be typed, so every definition of `name`).
    fn call_site(&self, ctx: &Ctx, defs: Option<Vec<usize>>, name: &str, args: Args<'_>) {
        let ids: Vec<usize> = match defs {
            Some(d) => d,
            None => self.defs_named(name).to_vec(),
        };
        if ids.is_empty() {
            return;
        }
        let spread = args.iter().any(|a| match form(strip_groups(a)) {
            Form::Assign { .. } => true,
            Form::Chain(c) => c.hops.is_empty() && matches!(&c.root, Root::Call { name: "arglist", .. }),
            _ => false,
        });
        if spread {
            for id in ids {
                self.kill_def(id, None);
            }
            return;
        }
        for (i, a) in args.iter().enumerate() {
            if !self.value_expr(ctx, a) {
                for id in ids.iter() {
                    self.kill_def(*id, Some(i));
                }
            }
        }
    }

    /// Every call in `code` narrows the parameter positions of the definitions it can reach.
    fn scan_calls(&self, ctx: &Ctx, code: &[Statement], me: &str) {
        for_each_expr(code, &mut |vis| {
            let Form::Chain(c) = &vis.form else { return };
            match &c.root {
                Root::Call { name, args } => self.call_site(ctx, self.call_defs(ctx.sc.owner, name), name, *args),
                Root::SelfCall(args) if !args.is_empty() => self.call_site(ctx, self.call_defs(ctx.sc.owner, me), me, *args),
                Root::ParentCall(args) if !args.is_empty() => {
                    if let Some(p) = ctx.def.and_then(|id| self.parent[id]) {
                        self.call_site(ctx, Some(vec![p]), me, *args);
                    }
                }
                _ => {}
            }
            for (i, hop) in c.hops.iter().enumerate() {
                let Hop::Call { name, args, colon, .. } = hop else { continue };
                let defs = if !*colon {
                    if i == 0 && matches!(&c.root, Root::Ident("global")) {
                        self.call_defs("/", name)
                    } else {
                        let recv = c.prefix_node(i);
                        match self.w.type_of(ctx.sc, recv) {
                            Some(t) if !t.is_empty() => self.call_defs(&t, name),
                            _ => None,
                        }
                    }
                } else {
                    None
                };
                self.call_site(ctx, defs, name, *args);
            }
        });
    }

    fn parent_value(&self, id: usize) -> bool {
        match self.parent[id] {
            Some(pid) => self.defs_value(&[pid]),
            None => false,
        }
    }

    fn eval_def(&self, id: usize, r: Proc<'a>) -> bool {
        let Some(code) = r.body() else { return true };
        let path = r.owner().path().to_string();
        let mut locals: HashMap<String, (String, Option<crate::lints::stored_refs::Place>)> = HashMap::new();
        let mut bad: HashSet<String> = HashSet::new();
        let mut value_params: Vec<String> = Vec::new();
        let flags = self.params.borrow()[id].clone();
        for (i, p) in r.parameters().iter().enumerate() {
            locals.insert(p.name.to_string(), (path_of(&p.type_path), None));
            if flags.get(i).copied().unwrap_or(false) {
                value_params.push(p.name.to_string());
            } else {
                bad.insert(p.name.to_string());
                // An implicit `..()` hands this parameter up unchanged.
                if let Some(pid) = self.parent[id] {
                    self.kill_def(pid, Some(i));
                }
            }
        }
        collect_locals(code, "", &mut locals);
        let sc = ProcScope { owner: &path, locals };
        let value_locals = self.value_locals(&sc, code, &mut bad, id, &value_params);
        let ctx = Ctx { sc: &sc, locals: &value_locals, def: Some(id) };
        self.scan_var_writes(&ctx, code);
        self.scan_calls(&ctx, code, &self.def_names[id]);
        // The body is still scanned above (its calls narrow the parameters); a declared `as text` / `as num` return then settles the answer.
        declared_value_return(r) || self.returns_ok(&ctx, code)
    }

    /// The locals of a proc whose every assignment is a value.
    fn value_locals(&self, sc: &ProcScope, code: &[Statement], bad: &mut HashSet<String>, id: usize, value_params: &[String]) -> HashSet<String> {
        let mut assigns: HashMap<String, Vec<Rhs<'_>>> = HashMap::new();
        declared_locals(code, &mut assigns, bad, self.w);
        for n in value_params {
            assigns.entry(n.clone()).or_default();
        }
        for_each_expr(code, &mut |vis| {
            let Form::Assign { op, lhs, rhs } = &vis.form else { return };
            let Some(c) = chain(strip_groups(lhs)) else { return };
            let Root::Ident(n) = &c.root else { return };
            if !c.hops.is_empty() {
                return;
            }
            match *op {
                "=" | ":=" | "&&=" | "||=" => assigns.entry(n.to_string()).or_default().push(Rhs::Owned((*rhs).clone())),
                _ => {}
            }
        });
        let mut set: HashSet<String> = assigns.keys().filter(|n| !bad.contains(*n) && self.sem.var_decl(sc.owner, n).is_none() && self.sem.var_decl("/", n).is_none()).cloned().collect();
        loop {
            let mut gone: Vec<String> = Vec::new();
            {
                let ctx = Ctx { sc, locals: &set, def: Some(id) };
                for n in set.iter() {
                    if assigns[n].iter().any(|rhs| !rhs.expr().is_some_and(|e| self.value_expr(&ctx, e))) {
                        gone.push(n.clone());
                    }
                }
            }
            if gone.is_empty() {
                return set;
            }
            for n in gone {
                set.remove(&n);
            }
        }
    }

    /// Every `return expr` and every assignment to `.` is a value.
    fn returns_ok(&self, ctx: &Ctx, code: &[Statement]) -> bool {
        let mut ok = true;
        for_each_return(code, &mut |e| {
            if ok && !self.value_expr(ctx, e) {
                ok = false;
            }
        });
        if !ok {
            return false;
        }
        for_each_expr(code, &mut |vis| {
            if !ok {
                return;
            }
            let Form::Assign { op, lhs, rhs } = &vis.form else { return };
            let Some(c) = chain(strip_groups(lhs)) else { return };
            if !c.hops.is_empty() || !matches!(&c.root, Root::Ident(".")) {
                return;
            }
            if matches!(*op, "=" | ":=" | "&&=" | "||=") && !self.value_expr(ctx, rhs) {
                ok = false;
            }
        });
        ok
    }

    /// Whether the call `e`, at a site in a proc of type `owner`, can only return a number, text or null.
    pub(crate) fn is_value_call(&self, sc: &ProcScope, e: &Expr) -> bool {
        let empty = HashSet::new();
        let ctx = Ctx { sc, locals: &empty, def: None };
        self.value_expr(&ctx, e)
    }

    /// Whether the local `name` of the proc body `code` is assigned the result of a call that is not a value, directly or through other
    /// locals (`var/x = f()`, then `y = x`): a local holds what was assigned to it, so passing it on passes the call's result on.
    pub(crate) fn local_holds_call(&self, sc: &ProcScope, code: &[Statement], name: &str) -> bool {
        let mut assigns: HashMap<String, Vec<Rhs<'_>>> = HashMap::new();
        let mut bad: HashSet<String> = HashSet::new();
        declared_locals(code, &mut assigns, &mut bad, self.w);
        for_each_expr(code, &mut |vis| {
            let Form::Assign { op, lhs, rhs } = &vis.form else { return };
            let Some(c) = chain(strip_groups(lhs)) else { return };
            let Root::Ident(n) = &c.root else { return };
            if c.hops.is_empty() && matches!(*op, "=" | ":=" | "&&=" | "||=") {
                assigns.entry(n.to_string()).or_default().push(Rhs::Owned((*rhs).clone()));
            }
        });
        let mut seen: HashSet<String> = HashSet::new();
        let mut todo = vec![name.to_string()];
        while let Some(n) = todo.pop() {
            if !seen.insert(n.clone()) {
                continue;
            }
            for rhs in assigns.get(&n).map(|v| v.as_slice()).unwrap_or(&[]) {
                let Some(r) = rhs.expr() else { continue };
                let r = strip_groups(r);
                if let Some(c) = chain(r) {
                    if let (true, Root::Ident(l)) = (c.hops.is_empty(), &c.root) {
                        if sc.locals.contains_key(*l) {
                            todo.push(l.to_string());
                            continue;
                        }
                    }
                }
                if is_call(r) && !self.is_value_call(sc, r) {
                    return true;
                }
            }
        }
        false
    }

    /// How many definitions are value-returning, and how many there are.
    #[allow(dead_code)]
    pub(crate) fn counts(&self) -> (usize, usize) {
        (self.value.iter().filter(|v| **v).count(), self.value.len())
    }
}

/// The value is the result of a proc call (a plain, global, or method call at the end of the chain).
pub(crate) fn is_call(e: &Expr) -> bool {
    let e = strip_groups(e);
    let Some(c) = chain(e) else { return false };
    if let Some(last) = c.hops.last() {
        return matches!(last, Hop::Call { .. });
    }
    matches!(c.root, Root::Call { .. })
}

/// A literal: a null, number or text.
fn literal_expr(e: &Expr) -> bool {
    chain(strip_groups(e)).is_some_and(|c| c.hops.is_empty() && matches!(&c.root, Root::Literal(t) if matches!(literal(t), Lit::Null | Lit::Int(_) | Lit::Float(_) | Lit::String(_))))
}

/// A type path's segments with the separator in front of each (`.proc/x` is `('.', "proc"), ('/', "x")`): dreammaker's `(PathOp, name)`.
fn path_segments(text: &str) -> Vec<(char, String)> {
    let mut out = Vec::new();
    let mut op = '/';
    let mut cur = String::new();
    for ch in text.chars() {
        if matches!(ch, '/' | '.' | ':') {
            if !cur.is_empty() {
                out.push((op, std::mem::take(&mut cur)));
            }
            op = ch;
        } else {
            cur.push(ch);
        }
    }
    if !cur.is_empty() {
        out.push((op, cur));
    }
    out
}

/// A proc reference `.proc/x`, `T.proc/x` or `/proc/x` as the type that owns the name and the name: `.proc/x` is the type of the proc it
/// is written in, `/proc/x` the global proc (`"/"`).
fn proc_ref_of(path: &str, own: &str) -> Option<(String, String)> {
    let segs = path_segments(path);
    let i = segs.iter().position(|(_, n)| n == "proc")?;
    let name = segs.get(i + 1)?.1.to_string();
    let owner: String = segs[..i].iter().map(|(_, n)| format!("/{n}")).collect();
    let owner = if owner.is_empty() {
        if segs[i].0 == '.' { own.to_string() } else { "/".to_string() }
    } else {
        owner
    };
    Some((owner, name))
}

/// Which definitions' untyped parameters could receive only values, before any call is looked at: per definition and position, true
/// unless the parameter has a type, an input type that is not text/num/null kinds or a non-literal default, or the definition is a verb
/// (a player supplies the arguments) or overrides a DM builtin (the engine calls it). Also returned: the names a string spells (a
/// `call(o, "x")` nothing here can see: every definition of the name is out) and the `(owner type, name)` of each proc reference
/// (`PROC_REF(x)`, `TYPE_PROC_REF(T, x)`, `GLOBAL_PROC_REF(x)`: called by the engine or a handler with arguments nothing here sees; the
/// definitions that type reaches are out, definitions of the name on unrelated types are not). The call sites then narrow it (`call_site`).
/// An input type made only of number, text and null kinds (`as text`, `as num|null`): never a reference.
fn value_input(t: &[String]) -> bool {
    !t.is_empty() && t.iter().all(|n| matches!(n.as_str(), "text" | "num" | "null" | "message" | "password" | "command_text" | "color" | "key"))
}

/// The proc's declaration says it returns only numbers and text (`/proc/f() as text`). A pointer-ish declared type never counts.
fn declared_value_return(r: Proc<'_>) -> bool {
    let mut cur = Some(r);
    while let Some(p) = cur {
        if p.declares() {
            return p.member().and_then(|m| m.return_input_types()).is_some_and(|t| value_input(&t));
        }
        cur = p.parent_proc();
    }
    false
}

type ParamCandidates = (Vec<Vec<bool>>, HashSet<String>, Vec<(String, String)>);

fn param_candidates(sem: &Sem, refs: &[Proc]) -> ParamCandidates {
    use crate::model::consts::Value;
    let mut named: HashSet<String> = HashSet::new();
    // Names that reach a dynamic call (`call(o, handler)`, `hascall(o, "x")`), and the text assigned to a var of such a name.
    let mut dynamic: HashSet<String> = HashSet::new();
    let mut texts: Vec<(String, String)> = Vec::new();
    let folded = sem.m().folded();
    for ty in sem.m().types() {
        for n in ty.var_names() {
            if let Some(Some(Value::String(s))) = folded.values.get(&(ty.id, n.clone())) {
                texts.push((n, s.to_string()));
            }
        }
    }
    let mut out: Vec<Vec<bool>> = Vec::with_capacity(refs.len());
    let mut proc_refs: Vec<(String, String)> = Vec::new();
    for r in refs {
        let params = r.parameters();
        let mut slot = vec![true; params.len()];
        for (i, p) in params.iter().enumerate() {
            if !p.type_path.is_empty() || p.as_types.as_ref().is_some_and(|t| !value_input(t)) || p.in_list.is_some() || p.default().is_some_and(|d| !literal_expr(d)) {
                slot[i] = false;
            }
        }
        let verb = r.declared_verb() == Some(true);
        let mut overrides_builtin = false;
        let mut cur = Some(*r);
        while let Some(x) = cur {
            if x.is_builtin() {
                overrides_builtin = true;
                break;
            }
            cur = x.parent_proc();
        }
        if verb || overrides_builtin {
            slot.iter_mut().for_each(|b| *b = false);
        }
        out.push(slot);
        for p in params.iter() {
            if let Some(t) = p.default().and_then(literal_text) {
                texts.push((p.name.to_string(), t));
            }
        }
    }
    // What the bodies name: a function of each file's bodies, cached per file.
    for names in crate::sem::procs::per_file(sem, "value-procs-body-names", |_rel, defs| body_names(defs)) {
        texts.extend(names.texts);
        named.extend(names.named);
        dynamic.extend(names.dynamic);
        proc_refs.extend(names.proc_refs);
    }
    for (n, t) in texts {
        if dynamic.contains(&n) {
            named.insert(t);
        }
    }
    (out, named, proc_refs)
}

/// What one file's bodies name, for [`param_candidates`]: literal texts assigned to a name, names a dynamic call spells, names whose
/// value reaches a dynamic call, and the procs a type path literal refers to.
#[derive(Clone, Default, PartialEq, serde::Serialize, serde::Deserialize)]
struct BodyNames {
    texts: Vec<(String, String)>,
    named: Vec<String>,
    dynamic: Vec<String>,
    proc_refs: Vec<(String, String)>,
}

fn body_names(defs: &[(String, Proc<'_>)]) -> BodyNames {
    let mut out = BodyNames::default();
    for (own, v) in defs {
        let Some(code) = v.body() else { continue };
        for_each_var_init(code, &mut |n, e| {
            if let Some(t) = literal_text(e) {
                out.texts.push((n.to_string(), t));
            }
        });
        for_each_expr(code, &mut |vis| {
            if let Form::Assign { op: "=", lhs, rhs } = &vis.form {
                if let (Some(n), Some(t)) = (target_name(lhs), literal_text(rhs)) {
                    out.texts.push((n, t));
                }
            }
            let Form::Chain(c) = &vis.form else { return };
            match &c.root {
                Root::DynamicCall { first, .. } => {
                    for a in first.iter() {
                        if let Some(t) = literal_text(a) {
                            out.named.push(t);
                        } else if let Some(n) = target_name(a) {
                            out.dynamic.push(n);
                        }
                    }
                }
                Root::Call { name, args } if *name == "call" || *name == "hascall" => {
                    for a in args.iter() {
                        if let Some(t) = literal_text(a) {
                            out.named.push(t);
                        } else if let Some(n) = target_name(a) {
                            out.dynamic.push(n);
                        }
                    }
                }
                Root::Prefab { path, .. } | Root::NewPrefab { path, .. } => {
                    if let Some(pr) = proc_ref_of(path, own) {
                        out.proc_refs.push(pr);
                    }
                }
                _ => {}
            }
            for hop in c.hops.iter() {
                if let Hop::ProcRef { name, .. } = hop {
                    out.named.push(name.to_string());
                }
            }
        });
    }
    out
}

/// The text a literal string expression spells.
fn literal_text(e: &Expr) -> Option<String> {
    let c = chain(strip_groups(e))?;
    if !c.hops.is_empty() {
        return None;
    }
    match &c.root {
        Root::Literal(t) => match literal(t) {
            Lit::String(s) => Some(s),
            _ => None,
        },
        _ => None,
    }
}

/// The var an assignment writes or an expression reads, by name: `x`, `a.x`.
fn target_name(e: &Expr) -> Option<String> {
    let c = chain(strip_groups(e))?;
    match c.hops.last() {
        Some(Hop::Field { name, .. }) => Some(name.to_string()),
        Some(_) => None,
        None => match &c.root {
            Root::Ident(n) => Some(n.to_string()),
            _ => None,
        },
    }
}

/// Every `var/x = value` in the body with the var's name.
fn for_each_var_init<'b>(b: &'b [Statement], f: &mut dyn FnMut(&str, &'b Expr)) {
    for st in stmts(b) {
        if let Stmt::Vars(vs) = &st.stmt {
            for v in vs {
                if let Some(e) = v.value {
                    f(&v.name, e);
                }
            }
        }
        for nb in stmt_blocks(&st.stmt) {
            for_each_var_init(nb, f);
        }
    }
}

/// The key of a var in `vars`: the type that declares it and its name (a subtype's override is the same var).
fn var_key(owner: &str, name: &str) -> String {
    format!("{owner}::{name}")
}

/// The vars that could hold only values, by declaring type and name: every declaration or override of the var has no type and a null,
/// number or text initial value.
fn value_var_candidates(sem: &Sem) -> HashMap<String, bool> {
    use crate::model::consts::Value;
    let folded = sem.m().folded();
    let mut out: HashMap<String, bool> = HashMap::new();
    for ty in sem.m().types() {
        let path = type_key(ty.path());
        for name in ty.var_names() {
            let typed = ty.declares_var(&name) && ty.var_declaration(&name).is_some_and(|d| !d.declared.is_empty());
            // The type's own value of the var: its last assignment's initializer (a sized list counts as one), and what that folds to.
            let expression = ty.own_vars_named(&name).last().is_some_and(|m| m.initializer().is_some() || m.sized_list());
            let constant = folded.values.get(&(ty.id, name.clone())).cloned().flatten();
            let init_ok = match (&constant, expression) {
                (Some(Value::Null(_) | Value::Float(_) | Value::String(_) | Value::Resource(_)), _) => true,
                (None, false) => true,
                _ => false,
            };
            let owner = sem.var_owner(&path, &name).unwrap_or_else(|| path.clone());
            let slot = out.entry(var_key(&owner, &name)).or_insert(true);
            if typed || !init_ok {
                *slot = false;
            }
        }
    }
    out
}

fn for_each_expr(b: &[Statement], f: &mut dyn FnMut(&Visit<'_>)) {
    crate::model::walk::walk_block(b, &mut |v, _| f(v));
}

fn for_each_return<'b>(b: &'b [Statement], f: &mut dyn FnMut(&'b Expr)) {
    for st in stmts(b) {
        if let Stmt::Return(Some(e)) = &st.stmt {
            f(*e);
        }
        for nb in stmt_blocks(&st.stmt) {
            for_each_return(nb, f);
        }
    }
}

/// A value assigned to a local: a node of the body, a copy of one met while walking expressions (the walk lends a node for the visit
/// only), or the `new /list(...)` a sized `var/L[3]` starts as.
enum Rhs<'b> {
    Node(&'b Expr),
    Owned(Expr),
    SizedList,
}

impl Rhs<'_> {
    /// The expression; none for the sized list's `new /list(...)`, which is never a value and never a call.
    fn expr(&self) -> Option<&Expr> {
        match self {
            Rhs::Node(e) => Some(e),
            Rhs::Owned(e) => Some(e),
            Rhs::SizedList => None,
        }
    }
}

/// The locals declared in the body with their initial values; a local of an entity type, or one a loop sets, can never be a value.
fn declared_locals<'b>(b: &'b [Statement], out: &mut HashMap<String, Vec<Rhs<'b>>>, bad: &mut HashSet<String>, w: &Walker) {
    fn declare<'b>(d: &VarDecl<'b>, out: &mut HashMap<String, Vec<Rhs<'b>>>, bad: &mut HashSet<String>, w: &Walker) {
        if w.kinds.is_ref(&path_of(&d.type_path)) {
            bad.insert(d.name.clone());
        }
        let slot = out.entry(d.name.clone()).or_default();
        match d.value {
            Some(i) => slot.push(Rhs::Node(i)),
            None if !d.suffix_args.is_empty() => slot.push(Rhs::SizedList),
            None => {}
        }
    }
    for st in stmts(b) {
        match &st.stmt {
            Stmt::Vars(vs) => {
                for v in vs {
                    declare(v, out, bad, w);
                }
            }
            Stmt::ForList { binding, .. } => {
                bad.insert(binding.name.clone());
            }
            Stmt::ForKeyValue { binding, value, .. } => {
                bad.insert(binding.name.clone());
                bad.insert(value.to_string());
            }
            Stmt::ForRange { binding, .. } => {
                bad.insert(binding.name.clone());
            }
            Stmt::ForLoop { init: Some(ForInit::Var(v)), .. } => {
                declare(v, out, bad, w);
            }
            _ => {}
        }
        for nb in stmt_blocks(&st.stmt) {
            declared_locals(nb, out, bad, w);
        }
    }
}

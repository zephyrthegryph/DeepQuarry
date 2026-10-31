//! `analyze gen deps` -> `code/engine/_generated/deps.dm`: what each stat input and draw can and cannot see change.
//!
//! The reads table (`gen reads`) says what a consumer reads. This file says which of those reads the graph cannot follow, so the runtime knows
//! whether a value computed from them may be kept until an input publishes (doc/rewrite/final_api.html section 5, "Caching", and section 7,
//! "Generated reads"):
//!
//! ```text
//! GLOB.generated_untracked_reads   "<type>::<proc>" = list(<what it cannot see>, ...)   for every condition, requirement, output and
//!                                  contribution a declaration names, every STAT formula and every draw() whose reads are not all tracked
//! GLOB.generated_untracked_leaves  "<type>" = list(<var>, ...)   vars a declaration of the type names as a condition or a contribution's value
//!                                  (nameof(v) inside contributes(), contributes_to() or a when() around one) that nothing publishes
//! (What each draw() reads on the holder and up to three hops away is the change graph's plan: `gen plans`, GLOB.generated_plans.)
//! ```
//!
//! An untracked read is a var that is not tracked, a relation, a stat, a derived value or constant (`ReadsEngine::classify`, the same test as
//! `sem/reads`, but counting the `ALLOW(reads)` sites too: an allowed read is still invisible to the graph), `?<rule>` for a read the walk could
//! not resolve (an unannotated global, `vars[]`/`call()`, a hop through a var that is not a relation), or `?opaque:<type>::<proc>` for a call
//! into an engine-internal body the walk does not enter. The `untracked_inputs` lint reports the same sites against a shrink-only baseline.

use std::collections::{BTreeMap, BTreeSet};
pub use crate::reactive_facts::{DepsAnalysis, Leaf, Untracked};

use crate::sem::decls::{Decls, Marker};
use crate::sem::gen::{GenCx, GenOut, Generator};
use crate::sem::handlers;
use crate::sem::reads::{Annotations, ReadKind, ReadSet, ReadsEngine, VarClass, WriteIndex};

/// The diagnostics of a reads walk that leave a consumer's inputs incomplete.
pub use crate::reactive_dependency_policy::UNRESOLVED_RULES;

/// Engine procs a consumer may call whose reads the runtime registers itself, so the opaque crossing hides nothing: the stat and capability-key
/// readers resolve to inputs the stat layer indexes (stat_value of a literal id is a stat read; cap_key_get a capability key read).
/// A draw's `..()` into the engine's base draw reads the base look the engine itself keeps current. tracked_changed() publishes a write (a setter's
/// last line) and reads nothing. expiry_clock_now() reads a clock, as `world.time` does (a clock read never subscribes).
pub use crate::reactive_dependency_policy::OPAQUE_SEEN;

/// The `(declaring type, var)` pairs a read set reads off the holder.
fn note_reads(set:&ReadSet,reads:&mut BTreeSet<(String,String)>){match crate::reactive_dependency_fold::note_reads(crate::reactive_dependency_policy::View::Owned(set),reads,&mut crate::key_policy_control::Compatibility){Ok(())=>{},Err(never)=>match never{}}}

/// A call to the setter `analyze gen auto_tracked` writes (`<type>::set_<var>`): it writes the var and publishes it, and reads nothing the graph
/// must follow, so the walk's not entering its body (the engine's generated directory is opaque) hides no input.
fn is_generated_setter(eng: &ReadsEngine, callee: &str) -> bool {
    let Some((owner, name)) = callee.rsplit_once("::") else { return false };
    if !name.starts_with("set_") {
        return false;
    }
    eng.sem.proc_ref(owner, name).is_some_and(|p| eng.sem.file_of(p.get().location) == Some(super::auto_tracked::AUTO_REL))
}

/// The hops an output's subscriptions follow only one step from the holder: a draw (or another derived output) redraws from its own vars, from
/// the entities it declares it watches (`look.watch()`, a derived() hop over a relation), and from a var one container, turf or area hop away
/// (the plan's PLAN_DRAW_HOP keys, heard by `draw_hop_published()`). A read deeper through one of them (`hat.loc.species`, `loc.loc.x`) is an input
/// an output cannot hear change. Stat inputs, conditions and requirements hear every depth.


/// A draw hears this read through its plan's PLAN_DRAW_HOP keys: one container, turf or area hop off the holder.
pub fn draw_hop_heard(r:&crate::sem::reads::Read)->bool{crate::reactive_dependency_policy::draw_hop_heard(r)}

/// The longest hop chain a draw hears: a container, turf or area hop and then declared relations (or further container hops), each republished by
/// its own publisher. `loc.cell.charge` has two hops; `loc.loc.cell.maxcharge` has three.


/// What a consumer's reads leave the graph unable to see change. `output`: the consumer is a draw() or another derived output.
pub fn untracked_of(set:&ReadSet,eng:&ReadsEngine,written:&WriteIndex,output:bool)->Vec<Untracked>{
    struct Original<'a,'model>{engine:&'a ReadsEngine<'model>,written:&'a WriteIndex}
    impl crate::key_policy_control::Control for Original<'_,'_>{
        type Error=std::convert::Infallible;const CHECKED:bool=false;
        fn checkpoint(&mut self)->Result<(),Self::Error>{Ok(())}
        fn reserve(&mut self,_:usize)->Result<(),Self::Error>{Ok(())}
        fn overflow(&mut self)->Self::Error{unreachable!("compatibility does not compute native bounds")}
        fn allocation_failed(&mut self)->Self::Error{unreachable!("compatibility retains original allocation APIs")}
    }
    impl crate::reactive_dependency_policy::Source for Original<'_,'_>{
        fn classify(&mut self,owner:&str,name:&str)->Result<VarClass,Self::Error>{Ok(self.engine.classify(owner,name,self.written))}
        fn generated_setter(&mut self,callee:&str)->Result<bool,Self::Error>{Ok(is_generated_setter(self.engine,callee))}
    }
    match crate::reactive_dependency_policy::untracked_of(crate::reactive_dependency_policy::View::Owned(set),&mut Original{engine:eng,written},output){Ok(value)=>value,Err(never)=>match never{}}
}

/// A `nameof(v)` a declaration names as a stat input: inside contributes()/contributes_to()/factors(), or inside a when() that wraps one.


fn marker_view(m:&Marker)->crate::declare_policy::Marker<'_>{crate::declare_policy::Marker{name:&m.name,rel:&m.rel,line:m.line,body:&m.body,args:&m.args,body_offset:m.body_offset,line_starts:&m.line_starts}}
pub fn marker_leaves(m:&Marker)->Vec<Leaf>{match crate::reactive_dependency_marker_policy::marker_leaves(&marker_view(m),&mut crate::key_policy_control::Compatibility){Ok(value)=>value,Err(never)=>match never{}}}

/// The var names a CAPABILITIES block names with `nameof(v)` (a `when` condition, a stat input, an `every(when =)` gate, a toggle): the block declares
/// that it reads or drives them, so they are read by reactive code whether or not a proc body does.
pub fn marker_named_vars(m: &Marker) -> Vec<String> {
    crate::raw_marker_policy::marker_named_vars(&m.body)
}

/// The vars a CAPABILITIES block hands to the engine to WRITE (`gas_level(into = nameof(v))`, `toggles(nameof(v))`): the engine calls their setters at run
/// time, so no text write names them.
pub fn marker_driven_vars(m:&Marker)->Vec<String>{match crate::reactive_dependency_marker_policy::marker_driven_vars(&marker_view(m),&mut crate::key_policy_control::Compatibility){Ok(value)=>value,Err(never)=>match never{}}}

/// What each consumer's reads leave the graph unable to see change, over the closed walk (`ReadsEngine::closed`): engine bodies entered, virtual
/// calls the union of their overrides, global procs walked like any proc and global state classified (`sem/globals.rs`). The `untracked_inputs`
/// lint and the generated `deps.dm` read this.
pub fn analyzed(tree: &crate::tree::Tree) -> std::sync::Arc<Option<DepsAnalysis>> {
    tree.memo("gen/deps", || compute(tree, true))
}

/// The same analysis over the walk the lints used before the closed walk replaced it (engine directories opaque, a call followed on the receiver's
/// static type, a global proc followed only through `READS_FROM`). `analyze sem closure` compares the two; no lint reads it.
pub fn analyzed_legacy(tree: &crate::tree::Tree) -> std::sync::Arc<Option<DepsAnalysis>> {
    tree.memo("gen/deps-legacy", || compute(tree, false))
}

fn compute(tree: &crate::tree::Tree, closed: bool) -> Option<DepsAnalysis> {
    let started = std::time::Instant::now();
    let trace = std::env::var("DQ_ANALYZE_TRACE").is_ok();
    // The presentation reactions' reads come from the text alone: found while the model loads.
    let (reaction_pairs, sem) = std::thread::scope(|s| {
        let pairs = std::thread::Builder::new().stack_size(64 << 20).spawn_scoped(s, || crate::lints::derived_reads::reaction_read_pairs(tree, &tree.select(&crate::tree::CODE_DM))).expect("spawn");
        let sem = crate::sem::sem_for(tree);
        (pairs.join().expect("reaction reads"), sem)
    });
    let sem = sem?;
    let decls = Decls::get(tree);
    let ann = Annotations::shared(tree, &sem, &decls);
    let eng = if closed { ReadsEngine::new(&sem, &decls, &ann).closed_shared(tree) } else { ReadsEngine::new(&sem, &decls, &ann).with_opaque(handlers::OPAQUE_DIRS) };
    let t_setup = started.elapsed();
    let c_setup = crate::util::cpu_ms();
    let written: &WriteIndex = sem.write_index();
    let set_calls = super::auto_tracked::set_calls(tree);
    let outside_setters = super::auto_tracked::writes_outside_setters_of(tree, &sem);
    let t_written = started.elapsed();
    let c_written = crate::util::cpu_ms();
    let mut reads: BTreeSet<(String, String)> = BTreeSet::new();
    let mut consumers: BTreeMap<String, Vec<Untracked>> = BTreeMap::new();
    let mut sampled: BTreeMap<String, BTreeSet<(String, u32)>> = BTreeMap::new();
    let mut stat_reads: BTreeSet<String> = BTreeSet::new();
    fn note_stat_reads(set:&ReadSet,into:&mut BTreeSet<String>){match crate::reactive_dependency_fold::note_stat_reads(crate::reactive_dependency_policy::View::Owned(set),into,&mut crate::key_policy_control::Compatibility){Ok(())=>{},Err(never)=>match never{}}}
    if let Some(an) = handlers::analyzed(tree) {
        // The first handler of each consumer decides (as `entry().or_insert_with` did); judging each is independent and runs on all cores,
        // the bookkeeping in order.
        let mut firsts: Vec<&handlers::Analyzed> = Vec::new();
        let mut seen: std::collections::HashSet<String> = std::collections::HashSet::new();
        for a in &an.handlers {
            if !a.h.role.reads_covered() || a.h.cap_proc {
                continue;
            }
            let Some(handled) = &a.closed else { continue };
            if closed && a.h.role == crate::sem::hooks::Role::Contribution && !handled.sampled.is_empty() {
                sampled.entry(format!("{}::{}", a.on, a.h.proc)).or_default().extend(handled.sampled.iter().cloned());
            }
            if seen.insert(format!("{}::{}", a.on, a.h.proc)) {
                firsts.push(a);
            }
        }
        let judged: Vec<(Option<ReadSet>, Vec<Untracked>)> = crate::sem::par_map_deep(&firsts, |a| {
            let output = a.h.role == crate::sem::hooks::Role::Output;
            if closed {
                // `handlers::analyzed` keeps the closed walk's set beside the targeted one.
                let handled = a.closed.as_ref().expect("filtered above");
                (None, untracked_of(handled, &eng, written, output))
            } else {
                let set = eng.analyze_handler(&a.on, &a.h.proc, a.h.ctx.type_path());
                let u = untracked_of(&set, &eng, written, output);
                (Some(set), u)
            }
        });
        for (a, (set, untracked)) in firsts.into_iter().zip(judged) {
            let walked = match &set {
                Some(set) => set,
                None => a.closed.as_ref().expect("filtered above"),
            };
            note_reads(walked, &mut reads);
            if matches!(a.h.role, crate::sem::hooks::Role::Contribution | crate::sem::hooks::Role::Condition) {
                note_stat_reads(walked, &mut stat_reads);
            }
            consumers.insert(format!("{}::{}", a.on, a.h.proc), untracked);
        }
    }
    let t_handlers = started.elapsed();
    let c_handlers = crate::util::cpu_ms();
    // A capability's entries() (CAP_ENTRIES) names holder procs too (powered()'s TYPE_PROC_REF(/obj/machinery, power_available)): judged here only,
    // not by sem/reads, so the runtime learns what they cannot see.
    // The walks are the cost and each is independent: the distinct ones run in parallel, their bookkeeping in declaration order.
    {
        let mut work: Vec<(String, crate::sem::hooks::HandlerRef)> = Vec::new();
        let mut queued: BTreeSet<String> = BTreeSet::new();
        for h in crate::sem::hooks::discover_in(&decls, &[crate::sem::decls::CAP_ENTRIES]) {
            if !h.role.reads_covered() || h.cap_proc || h.owner.is_empty() {
                continue;
            }
            let id = format!("{}::{}", h.owner, h.proc);
            if consumers.contains_key(&id) || queued.contains(&id) || sem.proc_ref(&h.owner, &h.proc).is_none() {
                continue;
            }
            queued.insert(id.clone());
            work.push((id, h));
        }
        let walked: Vec<(std::sync::Arc<ReadSet>, Vec<Untracked>)> = crate::sem::par_map_deep(&work, |(_, h)| {
            let set = eng.analyze_handler_shared(&h.owner, &h.proc, h.ctx.type_path());
            let untracked = untracked_of(&set, &eng, &written, h.role == crate::sem::hooks::Role::Output);
            (set, untracked)
        });
        for ((id, h), (set, untracked)) in work.into_iter().zip(walked) {
            note_reads(&set, &mut reads);
            if matches!(h.role, crate::sem::hooks::Role::Contribution | crate::sem::hooks::Role::Condition) {
                note_stat_reads(&set, &mut stat_reads);
            }
            consumers.insert(id, untracked);
        }
    }
    // STAT(T, v, FORMULA, formula = PROC_REF(f)): the formula is the stat's one input.
    {
        let mut work: Vec<(String, String)> = Vec::new();
        for m in decls.markers_named("STAT") {
            let Some(owner) = m.args.first() else { continue };
            for arg in &m.args {
                let compact = arg.replace(' ', "");
                let Some(name) = compact.strip_prefix("formula=PROC_REF(").and_then(|r| r.strip_suffix(')')) else { continue };
                if sem.proc_ref(owner, name).is_none() {
                    continue;
                }
                work.push((owner.clone(), name.to_string()));
            }
        }
        let walked: Vec<(std::sync::Arc<ReadSet>, Vec<Untracked>)> = crate::sem::par_map_deep(&work, |(owner, name)| {
            let set = eng.analyze_handler_shared(owner, name, "/datum/act/eval");
            let untracked = untracked_of(&set, &eng, &written, false);
            (set, untracked)
        });
        for ((owner, name), (set, untracked)) in work.into_iter().zip(walked) {
            note_reads(&set, &mut reads);
            note_stat_reads(&set, &mut stat_reads);
            if !set.sampled.is_empty() {
                sampled.entry(format!("{}::{}", owner, name)).or_default().extend(set.sampled.iter().cloned());
            }
            consumers.entry(format!("{}::{}", owner, name)).or_insert(untracked);
        }
    }
    // The presentation reactions (Life steps, HUD, sight, canmove) read holder vars too: reactive code the handler roles do not cover.
    {
        for (owner, var) in reaction_pairs {
            if let Some(declaring) = sem.var_owner(&owner, &var) {
                reads.insert((declaring, var));
            }
        }
    }
    let t_stat = started.elapsed();
    let c_stat = crate::util::cpu_ms();
    let mut draws = BTreeSet::new();
    let mut draw_reads: BTreeMap<String, BTreeSet<String>> = BTreeMap::new();
    let mut draw_keys: BTreeMap<String, BTreeSet<String>> = BTreeMap::new();
    let mut draw_hops: BTreeMap<String, BTreeSet<String>> = BTreeMap::new();
    let mut draw_links: BTreeMap<String, BTreeSet<String>> = BTreeMap::new();
    let capability_keys: BTreeSet<String> = ann.capkey_accessors.values().cloned().collect();
    let defines: BTreeSet<String> = decls.defines.iter().cloned().collect();
    let mut draw_work: Vec<(String, String)> = Vec::new();
    for d in crate::sem::procs::proc_defs(&sem, &["draw"]) {
        if d.owner == "/" || handlers::OPAQUE_DIRS.iter().any(|p| d.rel.starts_with(p)) {
            continue;
        }
        let id = format!("{}::draw", d.owner);
        if draws.contains(&id) {
            continue;
        }
        draws.insert(id.clone());
        draw_work.push((d.owner.clone(), id));
    }
    draws.clear();
    // Each draw's closed walk is independent: run them in parallel, then fold the results in the order the definitions came.
    let draw_walked: Vec<(std::sync::Arc<ReadSet>, Vec<Untracked>)> = crate::sem::par_map_deep(&draw_work, |(owner, _)| {
        let set = eng.analyze_shared(owner, "draw");
        let untracked = untracked_of(&set, &eng, &written, true);
        (set, untracked)
    });
    for ((owner, id), (set, untracked)) in draw_work.into_iter().zip(draw_walked) {
        note_reads(&set, &mut reads);
        if !set.sampled.is_empty() {
            sampled.entry(id.clone()).or_default().extend(set.sampled.iter().cloned());
        }
        let projection=match crate::reactive_dependency_fold::draw_projection(crate::reactive_dependency_policy::View::Owned(&set),&capability_keys,&mut |_:&mut crate::key_policy_control::Compatibility,name:&str|Ok(crate::gens::reads::canonical_read_key(&ReadKind::Accessor,name,&capability_keys,&defines)),&mut crate::key_policy_control::Compatibility){Ok(value)=>value,Err(never)=>match never{}};
        draw_reads.insert(owner.clone(),projection.reads);
        draw_keys.insert(owner.clone(),projection.keys);
        draw_hops.insert(owner.clone(),projection.hops);
        draw_links.insert(owner.clone(),projection.links);
        consumers.insert(id.clone(), untracked);
        draws.insert(id);
    }
    // The verb outputs (hidden_verbs(), granted_verbs()) refresh on the draw's bit: what each override reads, for the plans.
    let mut verb_work: Vec<(String, String)> = Vec::new();
    {
        let mut seen = BTreeSet::new();
        for d in crate::sem::procs::proc_defs(&sem, &["hidden_verbs", "granted_verbs"]) {
            if d.owner == "/" || handlers::OPAQUE_DIRS.iter().any(|p| d.rel.starts_with(p)) || !seen.insert(format!("{}::{}", d.owner, d.name)) {
                continue;
            }
            verb_work.push((d.owner.clone(), d.name.clone()));
        }
    }
    let verb_walked: Vec<(std::sync::Arc<ReadSet>, Vec<Untracked>)> = crate::sem::par_map_deep(&verb_work, |(owner, name)| {
        let set = eng.analyze_shared(owner, name);
        let untracked = untracked_of(&set, &eng, &written, true);
        (set, untracked)
    });
    let mut verb_reads: BTreeMap<String, (BTreeSet<String>, bool)> = BTreeMap::new();
    for ((owner, name), (set, untracked)) in verb_work.into_iter().zip(verb_walked) {
        note_reads(&set, &mut reads);
        let mut vars = BTreeSet::new();
        for r in &set.reads {
            if r.root == "holder" && r.kind == ReadKind::Var {
                vars.insert(if r.hops.is_empty() { r.var.clone() } else { r.hops[0].trim_end_matches("[]").to_string() });
            }
        }
        let unresolved = untracked.iter().any(|u| u.what.starts_with('?'));
        verb_reads.insert(format!("{}::{}", owner, name), (vars, unresolved));
    }
    let t_draws = started.elapsed();
    let c_draws = crate::util::cpu_ms();
    // A window host's ui_data(A) is an output whether or not a CAPABILITIES block names an interface() for it (an inherited or implicit window):
    // every var it reads must publish, or the window never hears a write. The reads count here; nothing is added to the consumer table.
    {
        let mut seen_ui = BTreeSet::new();
        for d in crate::sem::procs::proc_defs(&sem, &["ui_data", "tgui_data"]) {
            if d.owner == "/" || d.owner == "/datum" || d.rel.starts_with("code/engine/") || !seen_ui.insert(format!("{}::{}", d.owner, d.name)) {
                continue;
            }
            let set = eng.analyze_handler(&d.owner, &d.name, "/datum/act/eval");
            // The base /datum's own vars (open_tguis, rx, the weakref, ...) are the framework's bookkeeping, reached from a window's data only through
            // a helper such as update_static_data_for_all_viewers(): a host's window data is its own type's vars, never these.
            for r in &set.reads {
                if r.kind == ReadKind::Var && !r.owner.is_empty() && r.owner != "/datum" {
                    reads.insert((r.owner.clone(), r.var.clone()));
                }
            }
        }
    }
    let t_ui = started.elapsed();
    let c_ui = crate::util::cpu_ms();
    let mut leaves = Vec::new();
    let mut named: BTreeSet<(String, String)> = BTreeSet::new();
    for m in decls.markers_named("CAPABILITIES") {
        if let Some(owner) = m.args.first().filter(|o| o.starts_with('/')) {
            for name in marker_named_vars(m) {
                if let Some(declaring) = sem.var_owner(owner, &name) {
                    reads.insert((declaring, name));
                }
            }
        }
        if let Some(owner) = m.args.first().filter(|o| o.starts_with('/')) {
            for name in marker_driven_vars(m) {
                if let Some(declaring) = sem.var_owner(owner, &name) {
                    named.insert((declaring, name));
                }
            }
        }
        for leaf in marker_leaves(m) {
            // A stat's input named by nameof() is read by the stat whatever its class.
            if let Some(declaring) = sem.var_owner(&leaf.owner, &leaf.var) {
                reads.insert((declaring, leaf.var.clone()));
            }
            if eng.classify(&leaf.owner, &leaf.var, &written) == VarClass::Unknown {
                leaves.push(leaf);
            }
        }
    }
    leaves.sort();
    leaves.dedup();
    if trace {
        eprintln!("analyze: gen/deps ({}) {} consumers in {:.1?}", if closed { "closed" } else { "legacy" }, consumers.len(), started.elapsed());
        eprintln!("analyze: gen/deps cpu at: setup {} written {} handlers {} stat {} draws {} ui {} end {}", c_setup, c_written, c_handlers, c_stat, c_draws, c_ui, crate::util::cpu_ms());
        eprintln!("analyze: gen/deps phases: sem+setup {:.1?}, written/set-calls {:.1?}, handler loop {:.1?}, cap entries+stat {:.1?}, draws {:.1?}, ui_data {:.1?}, markers {:.1?}", t_setup, t_written - t_setup, t_handlers - t_written, t_stat - t_handlers, t_draws - t_stat, t_ui - t_draws, started.elapsed() - t_ui);
    }
    let mut candidates: BTreeSet<(String, String)> = reads.iter().filter(|(owner, var)| super::auto_tracked::candidate(&eng, &outside_setters, &set_calls, owner, var)).cloned().collect();
    // A var written through a generated setter stays tracked after its last reader goes (the calls `analyze fix` wrote must keep compiling), and
    // so does a var whose `TRACKED()` line was dropped while nothing walked reads it: the transition set (see `auto_tracked::called_candidates`).
    // A var a CAPABILITIES block names with nameof() is driven by the engine (`gas_level(into = nameof(v))` writes it through its setter at run time, a
    // `toggles()` gate flips it): it needs the setter whether or not a text write exists.
    candidates.extend(named.iter().filter(|(o, v)| super::auto_tracked::named_candidate(&eng, o, v)).cloned());
    candidates.extend(super::auto_tracked::called_candidates(tree, &sem, &eng, &outside_setters, &set_calls));
    Some(DepsAnalysis { consumers, draws, leaves, draw_reads, draw_keys, draw_hops, draw_links, verb_reads, stat_reads, reads, candidates, sampled })
}

struct Deps;

/// Writes `GLOB.<name>` from `rows` (each tab-indented `"key" = value`) through builder procs of at most 300 rows: one GLOBAL_LIST_INIT over thousands
/// of entries is a macro argument DreamMaker cannot parse (the reads table is chunked for the same reason).
impl Generator for Deps {
    fn name(&self) -> &'static str {
        "deps"
    }

    fn stage(&self) -> u8 {
        1
    }

    fn output(&self) -> &'static str {
        "deps.dm"
    }

    fn generate(&self, cx: &GenCx, out: &mut GenOut) {
        let _ = cx.sem();
        let an = analyzed(cx.tree);
        let Some(an) = an.as_ref().as_ref() else {
            out.diag("deepquarry.dme", 1, "the semantic model could not be built; stat and draw dependencies cannot be generated");
            return;
        };
        if std::env::var("DQ_AUTO_REPORT").is_ok() {
            let mut hist: BTreeMap<&str, usize> = BTreeMap::new();
            for u in an.consumers.values().flatten() {
                *hist.entry(u.what.as_str()).or_default() += 1;
            }
            let mut rows: Vec<_> = hist.into_iter().collect();
            rows.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(b.0)));
            for (what, n) in rows {
                eprintln!("untracked-read {:5} {}", n, what);
            }
        }
        let mut generated=crate::deps_policy::Output::default();
        crate::deps_policy::generate(an,&mut generated);
        for diagnostic in generated.diags{out.diag(&diagnostic.rel,diagnostic.line,diagnostic.msg);}
        for line in generated.body.split_terminator('\n'){out.line(line);}

    }
}

pub fn register(reg: &mut Vec<Box<dyn Generator>>) {
    reg.push(Box::new(Deps));
}

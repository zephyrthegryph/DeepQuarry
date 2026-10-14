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
//! GLOB.generated_draw_reads        "<type>" = list(<var>, ...)   the holder vars the type's own draw() (and the parents it calls) reads
//! GLOB.generated_draw_hop_reads    "<type>" = list("loc.<var>", "turf.<rel>.<var>", ...)   what that draw reads up to three hops away (a container,
//!                                  turf or area hop, then relations): a publish of the var there, or of a link, redraws the thing (draw_hop_published(), refs/hops.dm)
//! ```
//!
//! An untracked read is a var that is not tracked, a relation, a stat, a derived value or constant (`ReadsEngine::classify`, the same test as
//! `sem/reads`, but counting the `ALLOW(reads)` sites too: an allowed read is still invisible to the graph), `?<rule>` for a read the walk could
//! not resolve (an unannotated global, `vars[]`/`call()`, a hop through a var that is not a relation), or `?opaque:<type>::<proc>` for a call
//! into an engine-internal body the walk does not enter. The `untracked_inputs` lint reports the same sites against a shrink-only baseline.

use std::collections::{BTreeMap, BTreeSet};

use crate::sem::decls::{matching_paren, Decls, Marker};
use crate::sem::gen::{GenCx, GenOut, Generator};
use crate::sem::handlers;
use crate::sem::reads::{Annotations, ReadKind, ReadSet, ReadsEngine, VarClass, WriteIndex};

/// The diagnostics of a reads walk that leave a consumer's inputs incomplete.
pub const UNRESOLVED_RULES: &[&str] = &["unannotated_global", "dynamic_read", "hop_not_relation", "ffi_call"];

/// Engine procs a consumer may call whose reads the runtime registers itself, so the opaque crossing hides nothing: the stat and capability-key
/// readers resolve to inputs the stat layer indexes (stat_value of a literal id is a stat read; cap_key_get a capability key read).
/// A draw's `..()` into the engine's base draw reads the base look the engine itself keeps current. tracked_changed() publishes a write (a setter's
/// last line) and reads nothing. expiry_clock_now() reads a clock, as `world.time` does (a clock read never subscribes).
pub const OPAQUE_SEEN: &[&str] = &["/::stat_value", "/::cap_key_get", "/::condition_holds", "/::condition_id_holds", "/atom::draw", "/datum::draw", "/::tracked_changed", "/::expiry_clock_now"];

/// The `(declaring type, var)` pairs a read set reads off the holder.
fn note_reads(set: &ReadSet, reads: &mut BTreeSet<(String, String)>) {
    for r in &set.reads {
        // Every var read, off the holder, a context hop (actor, held, target) or an object a hop crosses without a declared relation: reactive code
        // reads it, so it publishes (whether the reader hears it is the dependency graph's question, `hop_not_relation`).
        if r.kind == ReadKind::Var && !r.owner.is_empty() {
            reads.insert((r.owner.clone(), r.var.clone()));
        }
    }
}

/// A call to the setter `analyze gen auto_tracked` writes (`<type>::set_<var>`): it writes the var and publishes it, and reads nothing the graph
/// must follow, so the walk's not entering its body (the engine's generated directory is opaque) hides no input.
fn is_generated_setter(eng: &ReadsEngine, callee: &str) -> bool {
    let Some((owner, name)) = callee.rsplit_once("::") else { return false };
    if !name.starts_with("set_") {
        return false;
    }
    eng.sem.proc_ref(owner, name).is_some_and(|p| eng.sem.file_of(p.get().location) == Some(super::auto_tracked::AUTO_REL))
}

/// One untracked read of a consumer: what it is, and where the read sits.
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub struct Untracked {
    pub what: String,
    /// The type that declares the var read (empty when the finding is not a var read).
    pub owner: String,
    pub rel: String,
    pub line: u32,
}

/// The hops an output's subscriptions follow only one step from the holder: a draw (or another derived output) redraws from its own vars, from
/// the entities it declares it watches (`look.watch()`, a derived() hop over a relation), and from a var one container, turf or area hop away
/// (`generated_draw_hop_reads`, heard by `draw_hop_published()`). A read deeper through one of them (`hat.loc.species`, `loc.loc.x`) is an input
/// an output cannot hear change. Stat inputs, conditions and requirements hear every depth.
const DRAW_PSEUDO_HOPS: &[&str] = &["loc", "turf", "area"];

/// A draw hears this read through `generated_draw_hop_reads`: one container, turf or area hop off the holder.
pub fn draw_hop_heard(r: &crate::sem::reads::Read) -> bool {
    r.root == "holder" && r.hop_ok && !r.hops.is_empty() && r.hops.len() <= DRAW_HOP_DEPTH && DRAW_PSEUDO_HOPS.contains(&r.hops[0].as_str())
}

/// The longest hop chain a draw hears: a container, turf or area hop and then declared relations (or further container hops), each republished by
/// its own publisher. `loc.cell.charge` has two hops; `loc.loc.cell.maxcharge` has three.
const DRAW_HOP_DEPTH: usize = 3;

/// What a consumer's reads leave the graph unable to see change. `output`: the consumer is a draw() or another derived output.
pub fn untracked_of(set: &ReadSet, eng: &ReadsEngine, written: &WriteIndex, output: bool) -> Vec<Untracked> {
    let mut out = Vec::new();
    for r in &set.reads {
        if r.kind != ReadKind::Var || r.root != "holder" || set.internal.contains(r) {
            continue;
        }
        if output && r.hops.iter().any(|h| DRAW_PSEUDO_HOPS.contains(&h.as_str())) && !draw_hop_heard(r) {
            let (rel, line) = set.sites.get(r).cloned().unwrap_or_default();
            out.push(Untracked { what: r.key(), owner: r.owner.clone(), rel, line });
            continue;
        }
        if !r.hop_ok || (!eng.turf_coordinate(r) && eng.classify(&r.owner, &r.var, written) == VarClass::Unknown) {
            let (rel, line) = set.sites.get(r).cloned().unwrap_or_default();
            out.push(Untracked { what: r.key(), owner: r.owner.clone(), rel, line });
        }
    }
    for d in &set.diags {
        if d.rule == "untracked_global" {
            // Global state that changes after boot and that nothing publishes: `GLOB.x`, `SSx.y`, a real global.
            out.push(Untracked { what: d.msg.clone(), owner: String::new(), rel: d.rel.clone(), line: d.line });
        } else if UNRESOLVED_RULES.contains(&d.rule) {
            out.push(Untracked { what: format!("?{}", d.rule), owner: String::new(), rel: d.rel.clone(), line: d.line });
        }
    }
    for (callee, (rel, line)) in &set.opaque {
        if OPAQUE_SEEN.contains(&callee.as_str()) || is_generated_setter(eng, callee) {
            continue;
        }
        out.push(Untracked { what: format!("?opaque:{}", callee), owner: String::new(), rel: rel.clone(), line: *line });
    }
    out.sort();
    out.dedup();
    out
}

/// A `nameof(v)` a declaration names as a stat input: inside contributes()/contributes_to(), or inside a when() that wraps one.
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub struct Leaf {
    pub owner: String,
    pub var: String,
    pub rel: String,
    pub line: u32,
}

fn is_word(b: u8) -> bool {
    b.is_ascii_alphanumeric() || b == b'_'
}

/// `(keyword, open paren, close paren)` of each `contributes(`, `contributes_to(` and `when(` call in `body`.
fn stat_ranges(body: &str) -> Vec<(&'static str, usize, usize)> {
    let b = body.as_bytes();
    let mut out = Vec::new();
    let mut i = 0;
    let mut in_str = false;
    while i < b.len() {
        if b[i] == b'"' {
            in_str = !in_str;
            i += 1;
            continue;
        }
        if in_str || !(b[i].is_ascii_alphabetic() || b[i] == b'_') {
            i += 1;
            continue;
        }
        let start = i;
        while i < b.len() && is_word(b[i]) {
            i += 1;
        }
        if start > 0 && (is_word(b[start - 1]) || b[start - 1] == b'.') {
            continue;
        }
        let kw: &'static str = match &body[start..i] {
            "contributes" => "contributes",
            "contributes_to" => "contributes_to",
            "when" => "when",
            _ => continue,
        };
        let rest = &body[i..];
        let skip = rest.len() - rest.trim_start().len();
        if !rest.trim_start().starts_with('(') {
            continue;
        }
        let open = i + skip;
        if let Some(close) = matching_paren(body, open) {
            out.push((kw, open, close));
        }
    }
    out
}

/// The stat-input leaves of one CAPABILITIES block.
pub fn marker_leaves(m: &Marker) -> Vec<Leaf> {
    let Some(owner) = m.args.first().filter(|o| o.starts_with('/')) else { return Vec::new() };
    let body = &m.body;
    let ranges = stat_ranges(body);
    let contributes: Vec<(usize, usize)> = ranges.iter().filter(|r| r.0 != "when").map(|r| (r.1, r.2)).collect();
    let feeds_stat = |pos: usize| {
        ranges.iter().any(|&(kw, s, e)| {
            pos > s && pos < e && (kw != "when" || contributes.iter().any(|&(cs, _)| cs > s && cs < e))
        })
    };
    let mut out = Vec::new();
    let mut from = 0;
    while let Some(at) = body[from..].find("nameof(") {
        let start = from + at;
        from = start + 7;
        if start > 0 && is_word(body.as_bytes()[start - 1]) {
            continue;
        }
        let Some(close) = matching_paren(body, start + 6) else { continue };
        let name = body[start + 7..close].trim();
        if name.is_empty() || !name.bytes().all(is_word) || !feeds_stat(start) {
            continue;
        }
        out.push(Leaf { owner: owner.clone(), var: name.to_string(), rel: m.rel.clone(), line: m.line_at(start) });
    }
    out
}

/// The var names a CAPABILITIES block names with `nameof(v)` (a `when` condition, a stat input, an `every(when =)` gate, a toggle): the block declares
/// that it reads or drives them, so they are read by reactive code whether or not a proc body does.
pub fn marker_named_vars(m: &Marker) -> Vec<String> {
    let body = &m.body;
    let mut out = Vec::new();
    let mut from = 0;
    while let Some(at) = body[from..].find("nameof(") {
        let start = from + at;
        from = start + 7;
        if start > 0 && is_word(body.as_bytes()[start - 1]) {
            continue;
        }
        let Some(close) = matching_paren(body, start + 6) else { continue };
        let name = body[start + 7..close].trim();
        if !name.is_empty() && name.bytes().all(is_word) {
            out.push(name.to_string());
        }
    }
    out
}

/// The vars a CAPABILITIES block hands to the engine to WRITE (`gas_level(into = nameof(v))`, `toggles(nameof(v))`): the engine calls their setters at run
/// time, so no text write names them.
pub fn marker_driven_vars(m: &Marker) -> Vec<String> {
    let mut out = Vec::new();
    for c in crate::pat!(r"\binto\s*=\s*nameof\(\s*(\w+)\s*\)").captures_iter(&m.body) {
        out.push(c.s(1).to_string());
    }
    for c in crate::pat!(r"\btoggles\(\s*nameof\(\s*(\w+)\s*\)").captures_iter(&m.body) {
        out.push(c.s(1).to_string());
    }
    out
}

/// Every consumer of a stat or a draw and its untracked reads, computed once per tree (the generator and the lint share it).
pub struct DepsAnalysis {
    /// "<type>::<proc>" -> its untracked reads.
    pub consumers: BTreeMap<String, Vec<Untracked>>,
    /// The consumers that are draw() procs (the lint reports them as `draw_untracked`).
    pub draws: BTreeSet<String>,
    /// Untracked leaves, per declaring type.
    pub leaves: Vec<Leaf>,
    /// "<type>" -> the holder vars its own draw() reads.
    pub draw_reads: BTreeMap<String, BTreeSet<String>>,
    /// "<type>" -> the published keys its own draw() reads through a READS_AS accessor (`nutrition_of(src)` stands for MOB_KEY_NUTRITION), as the
    /// DM text of the key (a define is written `[MOB_KEY_NUTRITION]` so the compile resolves it): a PUBLISH_CHANGE of one redraws the thing.
    pub draw_keys: BTreeMap<String, BTreeSet<String>>,
    /// "<type>" -> what its own draw() reads one container, turf or area hop away, as "<hop>.<var>".
    pub draw_hops: BTreeMap<String, BTreeSet<String>>,
    /// Every `(declaring type, var)` a consumer reads off the holder (or through a declared relation hop), whatever its class: the read
    /// set `gens::auto_tracked` turns into tracked vars.
    pub reads: BTreeSet<(String, String)>,
    /// The reads of `reads` no declaration makes reactive (see `gens::auto_tracked::candidate`): the vars the inference tracks.
    pub candidates: BTreeSet<(String, String)>,
}

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
    let sem = crate::sem::sem_for(tree)?;
    let decls = Decls::get(tree);
    let ann = Annotations::get(&sem, &decls);
    let eng = if closed { ReadsEngine::new(&sem, &decls, &ann).closed() } else { ReadsEngine::new(&sem, &decls, &ann).with_opaque(handlers::OPAQUE_DIRS) };
    let written = WriteIndex::build(&sem);
    let set_calls = super::auto_tracked::set_calls(tree);
    let outside_setters = super::auto_tracked::writes_outside_setters_of(tree, &sem);
    let mut reads: BTreeSet<(String, String)> = BTreeSet::new();
    let mut consumers: BTreeMap<String, Vec<Untracked>> = BTreeMap::new();
    if let Some(an) = handlers::analyzed(tree) {
        for a in &an.handlers {
            if !a.h.role.reads_covered() || a.h.cap_proc {
                continue;
            }
            let Some(handled) = &a.closed else { continue };
            consumers.entry(format!("{}::{}", a.on, a.h.proc)).or_insert_with(|| {
                if closed {
                    // `handlers::analyzed` keeps the closed walk's set beside the targeted one.
                    note_reads(handled, &mut reads);
                    untracked_of(handled, &eng, &written, a.h.role == crate::sem::hooks::Role::Output)
                } else {
                    let set = eng.analyze_handler(&a.on, &a.h.proc, a.h.ctx.type_path());
                    note_reads(&set, &mut reads);
                    untracked_of(&set, &eng, &written, a.h.role == crate::sem::hooks::Role::Output)
                }
            });
        }
    }
    // A capability's entries() (CAP_ENTRIES) names holder procs too (powered()'s TYPE_PROC_REF(/obj/machinery, power_available)): judged here only,
    // not by sem/reads, so the runtime learns what they cannot see.
    for h in crate::sem::hooks::discover_in(&decls, &[crate::sem::decls::CAP_ENTRIES]) {
        if !h.role.reads_covered() || h.cap_proc || h.owner.is_empty() {
            continue;
        }
        let id = format!("{}::{}", h.owner, h.proc);
        if consumers.contains_key(&id) || sem.proc_ref(&h.owner, &h.proc).is_none() {
            continue;
        }
        let set = eng.analyze_handler(&h.owner, &h.proc, h.ctx.type_path());
        note_reads(&set, &mut reads);
        consumers.insert(id, untracked_of(&set, &eng, &written, h.role == crate::sem::hooks::Role::Output));
    }
    // STAT(T, v, FORMULA, formula = PROC_REF(f)): the formula is the stat's one input.
    for m in decls.markers_named("STAT") {
        let Some(owner) = m.args.first() else { continue };
        for arg in &m.args {
            let compact = arg.replace(' ', "");
            let Some(name) = compact.strip_prefix("formula=PROC_REF(").and_then(|r| r.strip_suffix(')')) else { continue };
            if sem.proc_ref(owner, name).is_none() {
                continue;
            }
            let set = eng.analyze_handler(owner, name, "/datum/act/eval");
            note_reads(&set, &mut reads);
            consumers.entry(format!("{}::{}", owner, name)).or_insert_with(|| untracked_of(&set, &eng, &written, false));
        }
    }
    // The presentation reactions (Life steps, HUD, sight, canmove) read holder vars too: reactive code the handler roles do not cover.
    {
        let files = tree.select(&crate::tree::CODE_DM);
        for (owner, var) in crate::lints::derived_reads::reaction_read_pairs(tree, &files) {
            if let Some(declaring) = sem.var_owner(&owner, &var) {
                reads.insert((declaring, var));
            }
        }
    }
    let mut draws = BTreeSet::new();
    let mut draw_reads: BTreeMap<String, BTreeSet<String>> = BTreeMap::new();
    let mut draw_keys: BTreeMap<String, BTreeSet<String>> = BTreeMap::new();
    let mut draw_hops: BTreeMap<String, BTreeSet<String>> = BTreeMap::new();
    let capability_keys: BTreeSet<String> = ann.capkey_accessors.values().cloned().collect();
    let defines: BTreeSet<String> = decls.defines.iter().cloned().collect();
    for d in crate::sem::procs::proc_defs(&sem, &["draw"]) {
        if d.owner == "/" || handlers::OPAQUE_DIRS.iter().any(|p| d.rel.starts_with(p)) {
            continue;
        }
        let id = format!("{}::draw", d.owner);
        if draws.contains(&id) {
            continue;
        }
        let set = eng.analyze(&d.owner, "draw");
        note_reads(&set, &mut reads);
        let keys = draw_reads.entry(d.owner.clone()).or_default();
        let published = draw_keys.entry(d.owner.clone()).or_default();
        let hopped = draw_hops.entry(d.owner.clone()).or_default();
        for r in &set.reads {
            if r.kind == ReadKind::Var && draw_hop_heard(r) {
                hopped.insert(format!("{}.{}", r.hops.join("."), r.var));
            }
            if r.root == "holder" && r.hops.is_empty() && r.kind == ReadKind::Var {
                keys.insert(r.var.clone());
            }
            // A capability's state key redraws its holder already (capability_key_changed -> look_key_changed); any other accessor key is a
            // producer's PUBLISH_CHANGE, which reaches the draw through this table.
            if r.root == "holder" && r.hops.is_empty() && r.kind == ReadKind::Accessor && !capability_keys.contains(&r.var) {
                published.insert(crate::gens::reads::canonical_read_key(&r.kind, &r.var, &capability_keys, &defines));
            }
        }
        consumers.insert(id.clone(), untracked_of(&set, &eng, &written, true));
        draws.insert(id);
    }
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
    }
    let mut candidates: BTreeSet<(String, String)> = reads.iter().filter(|(owner, var)| super::auto_tracked::candidate(&eng, &outside_setters, &set_calls, owner, var)).cloned().collect();
    // A var written through a generated setter stays tracked after its last reader goes (the calls `analyze fix` wrote must keep compiling), and
    // so does a var whose `TRACKED()` line was dropped while nothing walked reads it: the transition set (see `auto_tracked::called_candidates`).
    // A var a CAPABILITIES block names with nameof() is driven by the engine (`gas_level(into = nameof(v))` writes it through its setter at run time, a
    // `toggles()` gate flips it): it needs the setter whether or not a text write exists.
    candidates.extend(named.iter().filter(|(o, v)| super::auto_tracked::named_candidate(&eng, o, v)).cloned());
    candidates.extend(super::auto_tracked::called_candidates(tree, &sem, &eng, &outside_setters, &set_calls));
    Some(DepsAnalysis { consumers, draws, leaves, draw_reads, draw_keys, draw_hops, reads, candidates })
}

struct Deps;

/// Writes `GLOB.<name>` from `rows` (each tab-indented `"key" = value`) through builder procs of at most 300 rows: one GLOBAL_LIST_INIT over thousands
/// of entries is a macro argument DreamMaker cannot parse (the reads table is chunked for the same reason).
fn emit_table(out: &mut GenOut, name: &str, rows: &[String]) {
    let chunks: Vec<&[String]> = rows.chunks(300).collect();
    for (n, chunk) in chunks.iter().enumerate() {
        out.line(format!("/proc/{}_chunk_{}()", name, n));
        out.line("	. = list()");
        for r in chunk.iter() {
            let r = r.trim_start_matches('\t');
            let (key, value) = r.split_once(" = ").unwrap_or((r, "TRUE"));
            out.line(format!("	.[{}] = {}", key, value));
        }
    }
    out.line(format!("/proc/{}_build()", name));
    out.line("	. = list()");
    for n in 0..chunks.len() {
        out.line(format!("	var/list/c{} = {}_chunk_{}()", n, name, n));
        out.line(format!("	for(var/k in c{})", n));
        out.line(format!("		.[k] = c{}[k]", n));
    }
    out.line(format!("GLOBAL_LIST_INIT({}, {}_build())", name, name));
}

/// A published key as DM text: quotes and backslashes escaped, `[` left alone (a define is written `[MOB_KEY_X]` and the compile interpolates it).
fn quote_key(s: &str) -> String {
    format!("\"{}\"", s.replace('\\', "\\\\").replace('"', "\\\""))
}

fn quote(s: &str) -> String {
    // `[` opens an embedded expression in a DM string: a list hop ("parts[].x") is written `\[`.
    format!("\"{}\"", s.replace('\\', "\\\\").replace('"', "\\\"").replace('[', "\\["))
}

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
        out.doc("\"<type>::<proc>\" -> what a stat input, condition, requirement, output or draw reads that nothing publishes: an untracked var");
        out.doc("(\"power_area.x\"), ?<rule> for a read the analysis could not resolve, ?opaque:<type>::<proc> for an engine body it does not enter.");
        out.doc("A stat with such an input recomputes on every read instead of caching (stat_value(), code/engine/stats/recompute.dm).");
        let rows: Vec<String> = an
            .consumers
            .iter()
            .filter(|(_, u)| !u.is_empty())
            .map(|(id, u)| {
                let whats: BTreeSet<&str> = u.iter().map(|x| x.what.as_str()).collect();
                format!("\t{} = list({})", quote(id), whats.iter().map(|w| quote(w)).collect::<Vec<_>>().join(", "))
            })
            .collect();
        emit_table(out, "generated_untracked_reads", &rows);
        out.blank();
        out.doc("\"<type>\" -> vars its declarations name as a stat input (nameof(v) in contributes(), contributes_to() or a when() around one) that");
        out.doc("nothing publishes: a stat that reads one recomputes on every read.");
        let mut by_type: BTreeMap<&str, BTreeSet<&str>> = BTreeMap::new();
        for l in &an.leaves {
            by_type.entry(l.owner.as_str()).or_default().insert(l.var.as_str());
        }
        let rows: Vec<String> = by_type.iter().map(|(t, vs)| format!("\t{} = list({})", quote(t), vs.iter().map(|v| quote(v)).collect::<Vec<_>>().join(", "))).collect();
        emit_table(out, "generated_untracked_leaves", &rows);
        out.blank();
        out.doc("\"<type>\" -> the holder vars its own draw() (and the parent draws it calls) reads: a change of any of them redraws an exact type too");
        out.doc("(derived_compile(), code/engine/change/derived.dm), so a draw needs no hand-written drawn_from().");
        let rows: Vec<String> = an
            .draw_reads
            .iter()
            .filter(|(_, ks)| !ks.is_empty())
            .map(|(t, ks)| format!("\t{} = list({})", quote(t), ks.iter().map(|k| quote(k)).collect::<Vec<_>>().join(", ")))
            .collect();
        emit_table(out, "generated_draw_reads", &rows);
        out.blank();
        out.doc("\"<type>\" -> the published keys its own draw() (and the parent draws it calls) reads through a READS_AS accessor: a PUBLISH_CHANGE of one");
        out.doc("redraws the thing (publish_key_changed(), code/engine/stats/recompute.dm), so a draw needs no hand-written on_change() for a key it reads.");
        let rows: Vec<String> = an
            .draw_keys
            .iter()
            .filter(|(_, ks)| !ks.is_empty())
            .map(|(t, ks)| format!("	{} = list({})", quote(t), ks.iter().map(|k| quote_key(k)).collect::<Vec<_>>().join(", ")))
            .collect();
        emit_table(out, "generated_draw_keys", &rows);
        out.blank();
        out.doc("\"<type>\" -> what its own draw() (and the parent draws it calls) reads one container, turf or area hop away, as \"<hop>.<var>\": a");
        out.doc("change of the var on what the thing is in, stands on or is in redraws it (draw_hop_published(), code/engine/refs/hops.dm).");
        let rows: Vec<String> = an
            .draw_hops
            .iter()
            .filter(|(_, ks)| !ks.is_empty())
            .map(|(t, ks)| format!("\t{} = list({})", quote(t), ks.iter().map(|k| quote(k)).collect::<Vec<_>>().join(", ")))
            .collect();
        emit_table(out, "generated_draw_hop_reads", &rows);
    }
}

pub fn register(reg: &mut Vec<Box<dyn Generator>>) {
    reg.push(Box::new(Deps));
}

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
pub const UNRESOLVED_RULES: &[&str] = &["unannotated_global", "dynamic_read", "hop_not_relation"];

/// Engine procs a consumer may call whose reads the runtime registers itself, so the opaque crossing hides nothing: the stat and capability-key
/// readers resolve to inputs the stat layer indexes (stat_value of a literal id is a stat read; cap_key_get a capability key read).
/// A draw's `..()` into the engine's base draw reads the base look the engine itself keeps current.
pub const OPAQUE_SEEN: &[&str] = &["/::stat_value", "/::cap_key_get", "/::condition_holds", "/::condition_id_holds", "/atom::draw", "/datum::draw"];

/// One untracked read of a consumer: what it is, and where the read sits.
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub struct Untracked {
    pub what: String,
    pub rel: String,
    pub line: u32,
}

/// What a consumer's reads leave the graph unable to see change.
pub fn untracked_of(set: &ReadSet, eng: &ReadsEngine, written: &WriteIndex) -> Vec<Untracked> {
    let mut out = Vec::new();
    for r in &set.reads {
        if r.kind != ReadKind::Var || r.root != "holder" {
            continue;
        }
        if !r.hop_ok || eng.classify(&r.owner, &r.var, written) == VarClass::Unknown {
            let (rel, line) = set.sites.get(r).cloned().unwrap_or_default();
            out.push(Untracked { what: r.key(), rel, line });
        }
    }
    for d in &set.diags {
        if UNRESOLVED_RULES.contains(&d.rule) {
            out.push(Untracked { what: format!("?{}", d.rule), rel: d.rel.clone(), line: d.line });
        }
    }
    for (callee, (rel, line)) in &set.opaque {
        if OPAQUE_SEEN.contains(&callee.as_str()) {
            continue;
        }
        out.push(Untracked { what: format!("?opaque:{}", callee), rel: rel.clone(), line: *line });
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
}

pub fn analyzed(tree: &crate::tree::Tree) -> std::sync::Arc<Option<DepsAnalysis>> {
    tree.memo("gen/deps", || compute(tree))
}

fn compute(tree: &crate::tree::Tree) -> Option<DepsAnalysis> {
    let sem = crate::sem::sem_for(tree)?;
    let decls = Decls::get(tree);
    let ann = Annotations::get(&sem, &decls);
    let eng = ReadsEngine::new(&sem, &decls, &ann).with_opaque(handlers::OPAQUE_DIRS);
    let written = WriteIndex::build(&sem);
    let mut consumers: BTreeMap<String, Vec<Untracked>> = BTreeMap::new();
    if let Some(an) = handlers::analyzed(tree) {
        for a in &an.handlers {
            if !a.h.role.reads_covered() || a.h.cap_proc {
                continue;
            }
            let Some(set) = &a.set else { continue };
            consumers.entry(format!("{}::{}", a.on, a.h.proc)).or_insert_with(|| untracked_of(set, &eng, &written));
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
        consumers.insert(id, untracked_of(&set, &eng, &written));
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
            consumers.entry(format!("{}::{}", owner, name)).or_insert_with(|| untracked_of(&set, &eng, &written));
        }
    }
    let mut draws = BTreeSet::new();
    let mut draw_reads: BTreeMap<String, BTreeSet<String>> = BTreeMap::new();
    for d in crate::sem::procs::proc_defs(&sem, &["draw"]) {
        if d.owner == "/" || handlers::OPAQUE_DIRS.iter().any(|p| d.rel.starts_with(p)) {
            continue;
        }
        let id = format!("{}::draw", d.owner);
        if draws.contains(&id) {
            continue;
        }
        let set = eng.analyze(&d.owner, "draw");
        let keys = draw_reads.entry(d.owner.clone()).or_default();
        for r in &set.reads {
            if r.root == "holder" && r.hops.is_empty() && r.kind == ReadKind::Var {
                keys.insert(r.var.clone());
            }
        }
        consumers.insert(id.clone(), untracked_of(&set, &eng, &written));
        draws.insert(id);
    }
    let mut leaves = Vec::new();
    for m in decls.markers_named("CAPABILITIES") {
        for leaf in marker_leaves(m) {
            if eng.classify(&leaf.owner, &leaf.var, &written) == VarClass::Unknown {
                leaves.push(leaf);
            }
        }
    }
    leaves.sort();
    leaves.dedup();
    Some(DepsAnalysis { consumers, draws, leaves, draw_reads })
}

struct Deps;

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
        out.doc("\"<type>::<proc>\" -> what a stat input, condition, requirement, output or draw reads that nothing publishes: an untracked var");
        out.doc("(\"power_area.x\"), ?<rule> for a read the analysis could not resolve, ?opaque:<type>::<proc> for an engine body it does not enter.");
        out.doc("A stat with such an input recomputes on every read instead of caching (stat_value(), code/engine/stats/recompute.dm).");
        out.line("GLOBAL_LIST_INIT(generated_untracked_reads, list(");
        let rows: Vec<String> = an
            .consumers
            .iter()
            .filter(|(_, u)| !u.is_empty())
            .map(|(id, u)| {
                let whats: BTreeSet<&str> = u.iter().map(|x| x.what.as_str()).collect();
                format!("\t{} = list({})", quote(id), whats.iter().map(|w| quote(w)).collect::<Vec<_>>().join(", "))
            })
            .collect();
        for (i, r) in rows.iter().enumerate() {
            out.line(format!("{}{}", r, if i + 1 < rows.len() { "," } else { "" }));
        }
        out.line("))");
        out.blank();
        out.doc("\"<type>\" -> vars its declarations name as a stat input (nameof(v) in contributes(), contributes_to() or a when() around one) that");
        out.doc("nothing publishes: a stat that reads one recomputes on every read.");
        out.line("GLOBAL_LIST_INIT(generated_untracked_leaves, list(");
        let mut by_type: BTreeMap<&str, BTreeSet<&str>> = BTreeMap::new();
        for l in &an.leaves {
            by_type.entry(l.owner.as_str()).or_default().insert(l.var.as_str());
        }
        let rows: Vec<String> = by_type.iter().map(|(t, vs)| format!("\t{} = list({})", quote(t), vs.iter().map(|v| quote(v)).collect::<Vec<_>>().join(", "))).collect();
        for (i, r) in rows.iter().enumerate() {
            out.line(format!("{}{}", r, if i + 1 < rows.len() { "," } else { "" }));
        }
        out.line("))");
        out.blank();
        out.doc("\"<type>\" -> the holder vars its own draw() (and the parent draws it calls) reads: a change of any of them redraws an exact type too");
        out.doc("(derived_compile(), code/engine/change/derived.dm), so a draw needs no hand-written drawn_from().");
        out.line("GLOBAL_LIST_INIT(generated_draw_reads, list(");
        let rows: Vec<String> = an
            .draw_reads
            .iter()
            .filter(|(_, ks)| !ks.is_empty())
            .map(|(t, ks)| format!("\t{} = list({})", quote(t), ks.iter().map(|k| quote(k)).collect::<Vec<_>>().join(", ")))
            .collect();
        for (i, r) in rows.iter().enumerate() {
            out.line(format!("{}{}", r, if i + 1 < rows.len() { "," } else { "" }));
        }
        out.line("))");
    }
}

pub fn register(reg: &mut Vec<Box<dyn Generator>>) {
    reg.push(Box::new(Deps));
}

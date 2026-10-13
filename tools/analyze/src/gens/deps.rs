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
pub const UNRESOLVED_RULES: &[&str] = &["unannotated_global", "dynamic_read", "hop_not_relation", "ffi_call"];

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
    /// Direct holder READS_AS keys with real registered publishers.
    pub draw_native_keys: BTreeMap<String, BTreeSet<String>>,
    pub draw_native_errors: Vec<(String, u32, String)>,
}

pub fn analyzed(tree: &crate::tree::Tree) -> std::sync::Arc<Option<DepsAnalysis>> {
    tree.memo("gen/deps", || compute(tree, false))
}

/// The same analysis over the closed walk (`ReadsEngine::closed`): engine bodies entered, virtual calls the union of their overrides. What it
/// finds beyond [`analyzed`] is `doc/rewrite/reads_closure_newly_visible.md` (`analyze sem closure`); no lint reads it yet.
pub fn analyzed_closed(tree: &crate::tree::Tree) -> std::sync::Arc<Option<DepsAnalysis>> {
    tree.memo("gen/deps-closed", || compute(tree, true))
}

fn compute(tree: &crate::tree::Tree, closed: bool) -> Option<DepsAnalysis> {
    let sem = crate::sem::sem_for(tree)?;
    let decls = Decls::get(tree);
    let ann = Annotations::get(&sem, &decls);
    let eng = if closed { ReadsEngine::new(&sem, &decls, &ann).closed() } else { ReadsEngine::new(&sem, &decls, &ann).with_opaque(handlers::OPAQUE_DIRS) };
    let mut publisher_files: BTreeSet<&str> = decls.publishers.values().flatten().map(|(rel, _)| rel.as_str()).collect();
    publisher_files.extend(tree.files.iter().filter(|file| file.code().text.contains("engine_key_changed"))
        .map(|file| file.rel.as_str()));
    let mut publisher_headers = Vec::new();
    for ty in sem.objtree.iter_types() {
        for procedure in ty.iter_self_procs() {
            if procedure.is_builtin() || procedure.get().code.is_none() { continue; }
            let body = sem.proc_body(procedure);
            if !publisher_files.contains(body.file.as_str()) { continue; }
            publisher_headers.push(crate::sem::procs::ProcDef {
                header: crate::sem::procs::engine_line(&sem.root, &body.file, body.line),
                rel: body.file, owner: body.owner, name: body.name,
            });
        }
    }
    let mut trait_bases: BTreeMap<String, Vec<String>> = BTreeMap::new();
    let written = WriteIndex::build(&sem);
    let mut consumers: BTreeMap<String, Vec<Untracked>> = BTreeMap::new();
    if let Some(an) = handlers::analyzed(tree) {
        for a in &an.handlers {
            if !a.h.role.reads_covered() || a.h.cap_proc {
                continue;
            }
            let Some(status_quo) = &a.set else { continue };
            consumers.entry(format!("{}::{}", a.on, a.h.proc)).or_insert_with(|| {
                if closed {
                    untracked_of(&eng.analyze_handler(&a.on, &a.h.proc, a.h.ctx.type_path()), &eng, &written)
                } else {
                    untracked_of(status_quo, &eng, &written)
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
    let native_publishers = draw_native_publishers(&sem, &publisher_headers);
    let mut draws = BTreeSet::new();
    let mut draw_reads: BTreeMap<String, BTreeSet<String>> = BTreeMap::new();
    let mut draw_native_keys: BTreeMap<String, BTreeSet<String>> = BTreeMap::new();
    let mut draw_native_errors = Vec::new();
    for d in crate::sem::procs::proc_defs(&sem, &["draw"]) {
        if d.owner == "/" || handlers::OPAQUE_DIRS.iter().any(|p| d.rel.starts_with(p)) {
            continue;
        }
        let id = format!("{}::draw", d.owner);
        if draws.contains(&id) {
            continue;
        }
        let set = eng.analyze(&d.owner, "draw");
        for diagnostic in set.diags.iter().filter(|diagnostic| diagnostic.rule == "native_stat_read") {
            draw_native_errors.push((diagnostic.rel.clone(), diagnostic.line, diagnostic.msg.clone()));
        }
        let keys = draw_reads.entry(d.owner.clone()).or_default();
        let native_keys = draw_native_keys.entry(d.owner.clone()).or_default();
        for r in &set.reads {
            if r.root == "holder" && r.hops.is_empty() && r.kind == ReadKind::Var {
                keys.insert(r.var.clone());
            }
            if r.root == "holder" && r.hops.is_empty() && r.kind == ReadKind::Accessor {
                if let Some(id) = r.var.strip_prefix("stat:[").and_then(|rest| rest.strip_suffix(']')) {
                    if eng.stat_read_key(&d.owner, id) == Some((r.var.clone(), ReadKind::Accessor)) {
                        native_keys.insert(r.var.clone());
                        continue;
                    }
                }
            }
            // Only registered READS_AS producer keys enter this direct-holder
            // contract. Other accessor kinds retain their own native contracts.
            let declared_accessor = ann.reads_as.values().any(|(key, _)| key == &r.var);
            if r.root == "holder" && r.hops.is_empty() && r.kind == ReadKind::Accessor && declared_accessor {
                let stored_key = r.var.trim_matches('"');
                let logical_producer = eng.is_relation(&d.owner, stored_key)
                    || (eng.is_tracked(&d.owner, stored_key)
                        && sem.proc_ref(&d.owner, &format!("set_{stored_key}")).is_some());
                if logical_producer && sem.var_decl(&d.owner, stored_key).is_none() {
                    native_keys.insert(stored_key.to_string());
                } else if eng.classify(&d.owner, stored_key, &written) == VarClass::Reactive {
                    // A READS_AS alias of a real tracked/relation/stat field
                    // follows the ordinary stored-state draw path.
                    if sem.var_decl(&d.owner, stored_key).is_some() {
                        keys.insert(stored_key.to_string());
                    } else if logical_producer {
                        // Logical keys may live in a record instead of D.vars.
                        // A declared stat/relation or registered setter still
                        // owns the real publication observed by this getter.
                        native_keys.insert(stored_key.to_string());
                    } else {
                        draw_native_errors.push((d.rel.clone(), d.header,
                            format!("logical draw key {stored_key} lacks a declared native producer/setter")));
                    }
                } else if draw_key_publisher_on_receiver(tree, &sem, &decls, &publisher_headers, &d.owner, &r.var)
                    || draw_literal_key(tree, &r.var).is_some_and(|key| native_publishers.iter().any(|(base, published)|
                        published == &key && sem.is_subtype(&d.owner, base)))
                    || trait_bases.entry(r.var.clone()).or_insert_with(|| draw_key_type_trait_bases(tree, &sem, &r.var))
                        .iter().any(|base| sem.is_subtype(&d.owner, base)) {
                    native_keys.insert(r.var.clone());
                } else {
                    draw_native_errors.push((d.rel.clone(), d.header,
                        format!("draw accessor key {} has no proven PUBLISH_CHANGE(src, key) producer on this receiver", r.var)));
                }
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
    Some(DepsAnalysis { consumers, draws, leaves, draw_reads, draw_native_keys, draw_native_errors })
}

/// Publisher membership is receiver-specific. The textual producer inventory
/// is not enough: a different object's same-key publication cannot wake this one.
fn draw_key_publisher_on_receiver(tree: &crate::tree::Tree, sem: &crate::sem::Sem, decls: &Decls,
    headers: &[crate::sem::procs::ProcDef], receiver: &str, key: &str) -> bool {
    let Some(sites) = decls.publishers.get(key) else { return false };
    let publication = regex::Regex::new(r"PUBLISH_CHANGE\(\s*([A-Za-z_]\w*)\s*,\s*([\w#]+)\s*\)").expect("producer pattern");
    sites.iter().any(|(rel, line)| {
        let Some(file) = tree.files.iter().find(|file| &file.rel == rel) else { return false };
        let enclosing = headers.iter().filter(|header| &header.rel == rel && header.header <= *line).max_by_key(|header| header.header);
        let Some(header) = enclosing else { return false };
        publication.captures_iter(file.code().line(*line as usize)).any(|capture| {
            if capture[2].trim_start_matches('#') != key { return false; }
            let name = &capture[1];
            let receiver_type = if name == "src" {
                (header.owner != "/").then(|| header.owner.clone())
            } else {
                let procedure = if header.owner == "/" { sem.global_proc(&header.name) } else { sem.proc_ref(&header.owner, &header.name) };
                procedure.and_then(|procedure| procedure.get().parameters.iter().find(|parameter| parameter.name == name)
                    .map(|parameter| format!("/{}", parameter.var_type.type_path.join("/"))))
                    .filter(|ty| ty != "/")
                    .or_else(|| sem.var_decl(&header.owner, name).map(|field| field.declared).filter(|ty| !ty.is_empty()))
            };
            receiver_type.is_some_and(|ty| sem.is_subtype(receiver, &ty))
        })
    })
}

/// Validated native type-trait publisher declarations.
fn draw_key_type_trait_bases(tree: &crate::tree::Tree, sem: &crate::sem::Sem, key: &str) -> Vec<String> {
    use dreammaker::constants::Constant;
    let Some(literal_key) = draw_literal_key(tree, key) else { return Vec::new() };
    sem.objtree.iter_types().filter_map(|ty| {
        let owner = &ty.get().path;
        if !owner.starts_with("/datum/entry_engine/type_trait/") || !sem.is_subtype(owner, "/datum/entry_engine/type_trait") { return None; }
        let Some(Constant::String(published)) = ty.get_value("publish_key").and_then(|v| v.constant.as_ref()) else { return None };
        let Some(Constant::Prefab(base)) = ty.get_value("base_type").and_then(|v| v.constant.as_ref()) else { return None };
        let Some(Constant::Prefab(trait_type)) = ty.get_value("trait_type").and_then(|v| v.constant.as_ref()) else { return None };
        (published.as_ref() == literal_key
            && sem.is_subtype(&format!("/{}", trait_type.path.join("/")), "/datum/type_trait"))
            .then(|| format!("/{}", base.path.join("/")))
    }).collect()
}

fn draw_literal_key(tree: &crate::tree::Tree, key: &str) -> Option<String> {
    if key.starts_with('"') && key.ends_with('"') {
        Some(key.trim_matches('"').to_string())
    } else {
        // Literal key defines only; no guessed expression or name alias.
        let definition = regex::Regex::new(&format!(r#"^\s*#define\s+{}\s+"([^"\[\]]*)"\s*$"#, regex::escape(key))).expect("literal key pattern");
        // The code view retains directive tokens but erases string contents.
        // Recover the literal from that same raw line only after validating the
        // directive, so commented/string-embedded defines cannot prove a key.
        let directive = regex::Regex::new(&format!(r"^\s*#define\s+{}(?:\s|$)", regex::escape(key))).expect("key directive pattern");
        let values: BTreeSet<String> = tree.files.iter().flat_map(|file| file.code().numbered().filter_map(|(line_no, code)| {
            directive.is_match(code).then(|| definition.captures(file.raw().line(line_no)))
                .flatten().map(|capture| capture[1].to_string())
        }).collect::<Vec<_>>()).collect();
        (values.len() == 1).then(|| values.iter().next().unwrap().clone())
    }
}

/// Literal native engine publications and a single immutable parameter's
/// literal default are actual producer contracts. Arbitrary expressions,
/// mutable defaults and publications on unrelated receivers prove nothing.
fn draw_native_publishers(sem: &crate::sem::Sem, headers: &[crate::sem::procs::ProcDef]) -> BTreeSet<(String, String)> {
    use dreammaker::ast::{Expression, Follow, Term, UnaryOp};
    fn base(expression: &Expression) -> Option<&Term> {
        match expression { Expression::Base { term, follow } if follow.is_empty() => Some(&term.elem), _ => None }
    }
    fn literal(expression: &Expression) -> Option<String> {
        match base(expression)? {
            Term::Int(value) => Some(value.to_string()),
            Term::Float(value) if value.is_finite() => Some(value.to_string()),
            Term::String(value) => Some(value.clone()),
            _ => None,
        }
    }
    let mut publishers = BTreeSet::new();
    if sem.global_proc("engine_key_changed").is_none() { return publishers; }
    for header in headers {
        let procedure = if header.owner == "/" { sem.global_proc(&header.name) } else { sem.proc_ref(&header.owner, &header.name) };
        let Some(procedure) = procedure else { continue };
        if header.owner != "/" && sem.proc_ref(&header.owner, "engine_key_changed")
            .is_some_and(|shadow| !shadow.ty().get().path.is_empty()) { continue; }
        let Some(body) = procedure.get().code.as_ref() else { continue };
        let parameters = &procedure.get().parameters;
        let mut assigned = BTreeSet::new();
        crate::sem::ast::walk_block(body, &mut |expression, _| {
            if let Expression::AssignOp { lhs, .. } = expression {
                if let Some(Term::Ident(name)) = base(lhs) { assigned.insert(name.to_string()); }
            }
            if let Expression::Base { term, follow } = expression {
                if let Term::Ident(name) = &term.elem {
                    if follow.iter().any(|follow| matches!(&follow.elem,
                        Follow::Unary(UnaryOp::PreIncr | UnaryOp::PostIncr | UnaryOp::PreDecr | UnaryOp::PostDecr))) {
                        assigned.insert(name.to_string());
                    }
                }
            }
        });
        crate::sem::ast::walk_block(body, &mut |expression, _| {
            let Some(Term::Call(name, args)) = base(expression) else { return };
            if name != "engine_key_changed" || args.len() != 2 { return; }
            let Some(Term::Ident(receiver)) = args.first().and_then(base) else { return };
            let receiver_type = if receiver == "src" && header.owner != "/" { Some(header.owner.clone()) }
                else { parameters.iter().find(|parameter| parameter.name.as_str() == receiver.as_str())
                    .filter(|parameter| !parameter.var_type.type_path.is_empty())
                    .map(|parameter| format!("/{}", parameter.var_type.type_path.join("/"))) };
            let Some(receiver_type) = receiver_type else { return };
            let key = match base(&args[1]) {
                Some(Term::String(key)) => Some(key.clone()),
                Some(Term::InterpString(prefix, parts)) if parts.len() == 1 && parts[0].1.is_empty() => {
                    parts[0].0.as_ref().and_then(base).and_then(|term| match term {
                        Term::Ident(name) if !assigned.contains(name.as_str()) => parameters.iter()
                            .find(|parameter| parameter.name.as_str() == name.as_str()).and_then(|parameter| parameter.default.as_ref())
                            .and_then(literal).map(|value| format!("{prefix}{value}")),
                        _ => None,
                    })
                }
                _ => None,
            };
            if let Some(key) = key { publishers.insert((receiver_type, key)); }
        });
    }
    publishers
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
        for (rel, line, message) in &an.draw_native_errors {
            out.diag(rel, *line, message);
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
        let defines: BTreeSet<_> = Decls::get(cx.tree).defines.iter().cloned().collect();
        // Empty rows are intentional: a child draw that does not call its
        // parent must not inherit unrelated parent keys at runtime.
        let native_rows: Vec<String> = an.draw_native_keys.iter().map(|(ty, keys)|
            format!("\t{} = list({})", quote(ty), keys.iter().map(|key|
                if let Some(id) = key.strip_prefix("stat:[").and_then(|rest| rest.strip_suffix(']')) {
                    // Only stat_read_key-validated IDs enter this table. Keep
                    // the declared ID as DM interpolation, not a literal '['.
                    format!("\"stat:[{id}]\"")
                } else if defines.contains(key) { key.clone() } else { quote(key) }
            ).collect::<Vec<_>>().join(", "))).collect();
        emit_table(out, "generated_draw_native_keys", &native_rows);
    }
}

pub fn register(reg: &mut Vec<Box<dyn Generator>>) {
    reg.push(Box::new(Deps));
}

#[cfg(test)]
mod native_draw_tests {
    use super::*;
    use crate::tree::{SourceFile, Tree};

    #[test]
    fn registered_accessor_keys_and_stored_vars_keep_distinct_draw_contracts() {
        let root = std::env::temp_dir().join(format!("dq-native-draw-{}", std::process::id()));
        std::fs::create_dir_all(root.join("code")).unwrap();
        let source = r#"
#define TRACKED(T,V)
#define SETTER(T,V)
#define READS_AS(P,K)
#define PUBLISH_CHANGE(E,K)
#define STAT(T,N,R,A...)
#define STAT_STORED 100001
#define STAT_VIRTUAL_PROBE 8123 // a genuine explicit numeric override
#define NATIVE_STATE_KEY "native_state"
#define NATIVE_GRAPH_KEY "graph:3"
#define CAP_CONSTRUCTION 3
#define NATIVE_KEY "native_amount"
#define TRAIT_KEY "trait_amount"
/*
#define TRAIT_KEY "commented_fake_amount"
*/
/datum/probe
    var/amount = 1
    var/plain = 2
TRACKED(/datum/probe, plain)
/datum/probe/proc/get_amount()
    return amount
READS_AS(/datum/probe/proc/get_amount, NATIVE_KEY)
/datum/probe/proc/producer()
    PUBLISH_CHANGE(src, NATIVE_KEY)
/datum/probe/proc/draw()
    return get_amount() + plain
/datum/probe/proc/tracked_alias()
    return plain
READS_AS(/datum/probe/proc/tracked_alias, plain)
/datum/probe/alias/proc/draw()
    return tracked_alias()
/datum/external
    var/amount = 1
/datum/external/proc/get_amount()
    return amount
READS_AS(/datum/external/proc/get_amount, EXTERNAL_KEY)
/proc/external_producer(datum/external/receiver)
    PUBLISH_CHANGE(receiver, EXTERNAL_KEY)
/datum/external/proc/draw()
    return get_amount()
/datum/logical
/datum/logical/proc/logical_value()
    return 1
/datum/logical/proc/set_logical_key(value)
    return value
SETTER(/datum/logical, logical_key)
READS_AS(/datum/logical/proc/logical_value, logical_key)
/datum/logical/proc/draw()
    return logical_value()
/datum/type_trait/test_trait
/datum/entry_engine/type_trait
    var/publish_key
    var/base_type
    var/trait_type
/datum/entry_engine/type_trait/test_trait
    publish_key = TRAIT_KEY
    base_type = /datum/trait_holder
    trait_type = /datum/type_trait/test_trait
/datum/trait_holder
    var/amount = 1
/datum/trait_holder/proc/amount_of()
    return amount
READS_AS(/datum/trait_holder/proc/amount_of, TRAIT_KEY)
/datum/trait_holder/proc/draw()
    return amount_of()
/datum/trait_wrong_holder
    var/amount = 1
/datum/trait_wrong_holder/proc/amount_of()
    return amount
READS_AS(/datum/trait_wrong_holder/proc/amount_of, TRAIT_KEY)
/datum/trait_wrong_holder/proc/draw()
    return amount_of()
/datum/missing
    var/amount = 1
/datum/missing/proc/get_amount()
    return amount
READS_AS(/datum/missing/proc/get_amount, missing_key)
/datum/missing/proc/draw()
    return get_amount()
/datum/unrelated/proc/producer()
    PUBLISH_CHANGE(src, missing_key)
/proc/stat_value(datum/E, stat_id)
    return 0
/datum/stat_base
    var/stored = 0
STAT(/datum/stat_base, stored, SUM)
STAT(/datum/stat_base, virtual_probe, ANY, virtual = TRUE)
/datum/stat_base/virtual_child/proc/draw()
    return stat_value(src, STAT_VIRTUAL_PROBE)
/datum/stat_base/stored_child/proc/draw()
    return stat_value(src, STAT_STORED)
/datum/stat_unrelated/proc/draw()
    return stat_value(src, STAT_VIRTUAL_PROBE)
/datum/stat_base/dynamic_child
    var/selected_id = 8123
/datum/stat_base/dynamic_child/proc/draw()
    return stat_value(src, selected_id)
/datum/stat_base/unknown_child/proc/draw()
    return stat_value(src, 987654)
/datum/stat_base/alias_child/proc/virtual_of()
    return 0
READS_AS(/datum/stat_base/alias_child/proc/virtual_of, virtual_probe)
/datum/stat_base/alias_child/proc/draw()
    return virtual_of()
/proc/engine_key_changed(datum/holder, key)
    return
/proc/native_state_write(datum/native_state_holder/receiver)
    engine_key_changed(receiver, NATIVE_STATE_KEY)
/datum/native_state_holder/proc/value_of()
    return 1
READS_AS(/datum/native_state_holder/proc/value_of, NATIVE_STATE_KEY)
/datum/native_state_holder/proc/draw()
    return value_of()
/datum/native_state_wrong/proc/value_of()
    return 1
READS_AS(/datum/native_state_wrong/proc/value_of, NATIVE_STATE_KEY)
/datum/native_state_wrong/proc/draw()
    return value_of()
/proc/native_graph_write(datum/native_graph_holder/E, cap_id = CAP_CONSTRUCTION)
    engine_key_changed(E, "graph:[cap_id]")
/datum/native_graph_holder/proc/value_of()
    return 1
READS_AS(/datum/native_graph_holder/proc/value_of, NATIVE_GRAPH_KEY)
/datum/native_graph_holder/proc/draw()
    return value_of()
/proc/native_graph_wrong_default(datum/native_graph_wrong/E, cap_id = 4)
    engine_key_changed(E, "graph:[cap_id]")
/datum/native_graph_wrong/proc/value_of()
    return 1
READS_AS(/datum/native_graph_wrong/proc/value_of, NATIVE_GRAPH_KEY)
/datum/native_graph_wrong/proc/draw()
    return value_of()
/proc/native_graph_mutated(datum/native_graph_mutated/E, cap_id = CAP_CONSTRUCTION)
    cap_id = 4
    engine_key_changed(E, "graph:[cap_id]")
/datum/native_graph_mutated/proc/value_of()
    return 1
READS_AS(/datum/native_graph_mutated/proc/value_of, NATIVE_GRAPH_KEY)
/datum/native_graph_mutated/proc/draw()
    return value_of()
/proc/native_graph_unproven(datum/native_graph_unproven/E, cap_id)
    engine_key_changed(E, "graph:[cap_id]")
/datum/native_graph_unproven/proc/value_of()
    return 1
READS_AS(/datum/native_graph_unproven/proc/value_of, NATIVE_GRAPH_KEY)
/datum/native_graph_unproven/proc/draw()
    return value_of()
"#;
        std::fs::write(root.join("code/probe.dm"), source).unwrap();
        let mut tree = Tree::from_files(vec![SourceFile::from_text("code/probe.dm", source)]);
        tree.root = root.clone();
        let result = compute(&tree, false).expect("fixture semantic model");
        assert!(result.draw_reads["/datum/probe"].contains("plain"));
        assert!(result.draw_native_keys["/datum/probe"].contains("NATIVE_KEY"));
        assert!(result.draw_reads["/datum/probe/alias"].contains("plain"), "tracked READS_AS alias retains its stored-state dependency");
        assert!(result.draw_native_keys["/datum/external"].contains("EXTERNAL_KEY"), "typed global producer publishes to the actual compatible receiver");
        assert!(!result.draw_reads["/datum/probe"].contains("NATIVE_KEY"));
        assert!(result.draw_native_keys["/datum/logical"].contains("logical_key"), "registered logical getter/setter key has no D.vars slot but remains native-reactive");
        assert!(!result.draw_reads["/datum/logical"].contains("logical_key"));
        assert!(result.draw_native_keys["/datum/trait_holder"].contains("TRAIT_KEY"), "native trait declaration proves its actual key and compatible receiver");
        assert!(!result.draw_native_keys["/datum/trait_wrong_holder"].contains("TRAIT_KEY"), "a trait on another receiver does not prove this publisher");
        assert!(result.draw_native_errors.iter().any(|(_, _, text)| text.contains("missing_key") && text.contains("this receiver")), "unrelated same-key publisher must not establish this receiver's contract");
        assert!(result.draw_native_keys["/datum/stat_base/virtual_child"].contains("stat:[STAT_VIRTUAL_PROBE]"), "a preprocessed numeric ID resolves to its inherited virtual stat publication");
        assert!(result.draw_reads["/datum/stat_base/stored_child"].contains("stored"), "stored stats retain their real variable publication");
        assert!(result.draw_native_keys["/datum/stat_unrelated"].is_empty(), "same stat ID on an unrelated receiver is not a producer");
        assert!(result.draw_native_keys["/datum/stat_base/alias_child"].is_empty(), "a virtual stat display name is not its numeric native key");
        assert!(result.draw_native_errors.iter().filter(|(_, _, message)| message.contains("literal declared stat ID")).count() >= 3,
            "dynamic IDs, unknown IDs and incompatible receivers must fail native draw admission");
        assert!(result.draw_native_keys["/datum/native_state_holder"].contains("NATIVE_STATE_KEY"), "actual native key call proves its compatible typed receiver");
        assert!(result.draw_native_keys["/datum/native_graph_holder"].contains("NATIVE_GRAPH_KEY"), "actual immutable graph parameter default proves the interpolated key");
        for rejected in ["/datum/native_state_wrong", "/datum/native_graph_wrong", "/datum/native_graph_mutated", "/datum/native_graph_unproven"] {
            assert!(result.draw_native_keys[rejected].is_empty(), "wrong owner/default, mutated or unproven graph parameters cannot prove {rejected}");
        }
        let _ = std::fs::remove_dir_all(root);
    }
}

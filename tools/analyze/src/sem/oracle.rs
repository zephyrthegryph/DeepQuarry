//! The reads oracle (the E5 spike, doc/rewrite/final_api.html section 19).
//!
//! The tree today carries hand-written dependency lists in `derived()`: `runs_while`,
//! `drawn_from`, `ui_from`, `rust_push` and `derive(var, reads...)`. This module reads those lists
//! from the AST and compares each with what [`ReadsEngine`] generates from the handler body the
//! list describes. The generated reads must CONTAIN every hand-written read; a handler that
//! misses one needs a `READS_AS` / `READS_FROM` annotation (or the fallback applies: E5 ships as
//! a checker over hand-listed reads).
//!
//! Invalidation tokens are the one known difference: `rust_device_rev` is a counter that setters
//! bump so the hand-written list has something to subscribe to; the generated reads subscribe to
//! the vars the body reads, so a token is not a read. Tokens are listed in
//! `tools/analyze/oracle/spike.toml` and reported separately, never silently dropped.

use std::collections::{BTreeMap, BTreeSet};

use dreammaker::ast::{Expression, Follow, Term};

use super::ast::{as_call, as_ident, walk_block};
use super::reads::ReadsEngine;
use super::Sem;

#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum OKind {
    /// `runs_while`: `should_run()`.
    Condition,
    /// `drawn_from`: `draw()` and `hidden_verbs()`.
    Draw,
    /// `ui_from`: `tgui_data()`.
    Ui,
    /// `rust_push`: `push_to_rust()`.
    Push,
    /// `derive(var, ...)`: `derive_<var>()`.
    Derive,
}

impl OKind {
    pub fn label(&self) -> &'static str {
        match self {
            OKind::Condition => "condition",
            OKind::Draw => "draw",
            OKind::Ui => "ui",
            OKind::Push => "push",
            OKind::Derive => "derive",
        }
    }

    pub fn procs(&self, derive_var: &str) -> Vec<String> {
        match self {
            OKind::Condition => vec!["should_run".into()],
            OKind::Draw => vec!["draw".into(), "hidden_verbs".into()],
            OKind::Ui => vec!["tgui_data".into(), "ui_data".into()],
            OKind::Push => vec!["push_to_rust".into()],
            OKind::Derive => vec![format!("derive_{}", derive_var)],
        }
    }
}

/// One hand-written list on one type.
#[derive(Clone, Debug)]
pub struct OracleEntry {
    pub ty: String,
    pub kind: OKind,
    /// For `Derive`: the derived var; "" otherwise.
    pub var: String,
    pub declared: BTreeSet<String>,
    pub rel: String,
    pub line: u32,
}

#[derive(Clone, Debug)]
pub struct OracleRow {
    pub ty: String,
    pub kind: OKind,
    pub var: String,
    pub declared: BTreeSet<String>,
    pub generated: BTreeSet<String>,
    /// Declared reads the generated set lacks, tokens excluded.
    pub missing: BTreeSet<String>,
    /// Declared reads that are listed invalidation tokens.
    pub tokens: BTreeSet<String>,
    /// Unannotated globals / dynamic reads inside the handler (what would need READS_FROM).
    pub unresolved: usize,
    /// The global procs the handler calls without READS_FROM.
    pub unannotated: BTreeSet<String>,
    pub procs: Vec<String>,
}

impl OracleRow {
    pub fn needs_annotation(&self) -> bool {
        !self.missing.is_empty()
    }
}

fn nameof_var(e: &Expression) -> Option<String> {
    let (n, args) = as_call(e)?;
    if n != "nameof" {
        return None;
    }
    let a = args.first()?;
    if let Some(id) = as_ident(a) {
        return Some(id.to_string());
    }
    // nameof(/type::var)
    if let Expression::Base { follow, .. } = a {
        for f in follow.iter() {
            if let Follow::StaticField(n) = &f.elem {
                return Some(n.as_str().to_string());
            }
        }
    }
    None
}

fn read_of(e: &Expression, out: &mut BTreeSet<String>) {
    if let Some(v) = nameof_var(e) {
        out.insert(v);
        return;
    }
    if let Some((n, args)) = as_call(e) {
        if (n == "rel" || n == "rel_each") && args.len() >= 2 {
            if let (Some(l), Some(r)) = (nameof_var(&args[0]), nameof_var(&args[1])) {
                let hop = if n == "rel_each" { format!("{}[]", l) } else { l };
                out.insert(format!("{}.{}", hop, r));
            }
        }
    }
}

/// Every `derived()` list on every type.
pub fn entries(sem: &Sem) -> Vec<OracleEntry> {
    let mut out = Vec::new();
    for ty in sem.objtree.iter_types() {
        let Some(tp) = ty.get().procs.get("derived") else { continue };
        let path = ty.get().path.clone();
        if path.is_empty() {
            continue;
        }
        for value in &tp.value {
            let Some(code) = &value.code else { continue };
            let rel = sem.rel(value.location).to_string();
            walk_block(code, &mut |e, line| {
                let Some((n, args)) = as_call(e) else { return };
                let kind = match n {
                    "runs_while" => OKind::Condition,
                    "drawn_from" => OKind::Draw,
                    "ui_from" => OKind::Ui,
                    "rust_push" => OKind::Push,
                    "derive" => OKind::Derive,
                    _ => return,
                };
                let mut declared = BTreeSet::new();
                let mut var = String::new();
                let mut iter = args.iter();
                if kind == OKind::Derive {
                    var = iter.next().and_then(nameof_var).unwrap_or_default();
                }
                for a in iter {
                    read_of(a, &mut declared);
                }
                out.push(OracleEntry { ty: path.clone(), kind, var, declared, rel: rel.clone(), line });
            });
        }
    }
    out
}

/// The lists the legacy text lint generated into `code/_generated/reads.dm` (same vocabulary,
/// derived from bodies by the old scanner): a second oracle with real UI and draw handlers.
pub fn generated_entries(root: &std::path::Path) -> Vec<OracleEntry> {
    let rel = "code/_generated/reads.dm";
    let Ok(text) = std::fs::read_to_string(root.join(rel)) else { return Vec::new() };
    let mut out = Vec::new();
    let mut ty = String::new();
    for (i, line) in text.lines().enumerate() {
        let l = line.trim();
        if let Some(r) = l.strip_suffix("/generated_reads()") {
            ty = r.to_string();
            continue;
        }
        let Some(rest) = l.strip_prefix(". += ") else { continue };
        let Some((kind, args)) = rest.split_once('(') else { continue };
        let kind = match kind {
            "runs_while" => OKind::Condition,
            "drawn_from" => OKind::Draw,
            "ui_from" => OKind::Ui,
            "rust_push" => OKind::Push,
            "derive" => OKind::Derive,
            _ => continue,
        };
        let names: Vec<String> = args.split("nameof(").skip(1).filter_map(|s| s.split(')').next()).map(|s| s.to_string()).collect();
        let mut names = names.into_iter();
        let var = if kind == OKind::Derive { names.next().unwrap_or_default() } else { String::new() };
        out.push(OracleEntry { ty: ty.clone(), kind, var, declared: names.collect(), rel: rel.to_string(), line: i as u32 + 1 });
    }
    out
}

/// Evaluates every entry: declared reads (own list plus the ancestors' lists of the same kind)
/// against the generated reads of the handler on the type.
pub fn evaluate(sem: &Sem, eng: &ReadsEngine, entries: &[OracleEntry], tokens: &BTreeSet<String>) -> Vec<OracleRow> {
    // (type, kind, var) -> own declared
    let mut own: BTreeMap<(String, OKind, String), BTreeSet<String>> = BTreeMap::new();
    for e in entries {
        own.entry((e.ty.clone(), e.kind.clone(), e.var.clone())).or_default().extend(e.declared.iter().cloned());
    }
    let mut rows = Vec::new();
    for ((ty, kind, var), _) in &own {
        // Declared = this type's list plus every ancestor's (derived() chains with `. = ..()`).
        let mut declared = BTreeSet::new();
        let mut cur = Some(ty.clone());
        let mut guard = 0;
        while let Some(t) = cur {
            if let Some(d) = own.get(&(t.clone(), kind.clone(), var.clone())) {
                declared.extend(d.iter().cloned());
            }
            guard += 1;
            if guard > 64 {
                break;
            }
            cur = sem.parent_of(&t).filter(|p| p != "/" && p != &t);
        }
        let mut generated = BTreeSet::new();
        let mut unresolved = 0;
        let mut unannotated: BTreeSet<String> = BTreeSet::new();
        let mut procs = Vec::new();
        for p in kind.procs(var) {
            if sem.proc_ref(ty, &p).map(|r| !r.is_builtin()).unwrap_or(false) {
                let set = eng.analyze(ty, &p);
                generated.extend(set.keys());
                unresolved += set.diags.iter().filter(|d| matches!(d.rule, "unannotated_global" | "dynamic_read")).count();
                for d in set.diags.iter().filter(|d| d.rule == "unannotated_global") {
                    if let Some(n) = d.msg.split('`').nth(1) {
                        unannotated.insert(n.to_string());
                    }
                }
                procs.push(p);
            }
        }
        let tk: BTreeSet<String> = declared.iter().filter(|d| tokens.contains(*d)).cloned().collect();
        let missing: BTreeSet<String> = declared.iter().filter(|d| !tokens.contains(*d) && !generated.contains(*d)).cloned().collect();
        rows.push(OracleRow { ty: ty.clone(), kind: kind.clone(), var: var.clone(), declared, generated, missing, tokens: tk, unresolved, unannotated, procs });
    }
    rows
}

/// `tools/analyze/oracle/spike.toml`: the pinned handlers and the token list.
#[derive(Debug, Default)]
pub struct SpikeConfig {
    pub tokens: BTreeSet<String>,
    /// The ratchet of unannotated global procs.
    pub unannotated: BTreeSet<String>,
    /// (type, kind label, var) triples.
    pub handlers: Vec<(String, String, String)>,
}

impl SpikeConfig {
    pub fn parse(text: &str) -> SpikeConfig {
        let mut c = SpikeConfig::default();
        let mut section = String::new();
        for raw in text.lines() {
            let l = raw.split('#').next().unwrap_or("").trim();
            if l.is_empty() {
                continue;
            }
            if let Some(s) = l.strip_prefix('[').and_then(|s| s.strip_suffix(']')) {
                section = s.to_string();
                continue;
            }
            match section.as_str() {
                "unannotated" => {
                    c.unannotated.insert(l.trim_matches('"').trim_end_matches(',').trim_matches('"').to_string());
                }
                "tokens" => {
                    c.tokens.insert(l.trim_matches('"').trim_end_matches(',').trim_matches('"').to_string());
                }
                "handlers" => {
                    // "<type> <kind> [var]"
                    let l = l.trim_matches('"').trim_end_matches(',').trim_matches('"');
                    let mut p = l.split_whitespace();
                    if let (Some(t), Some(k)) = (p.next(), p.next()) {
                        c.handlers.push((t.to_string(), k.to_string(), p.next().unwrap_or("").to_string()));
                    }
                }
                _ => {}
            }
        }
        c
    }
}

#[allow(dead_code)]
fn term_name(t: &Term) -> Option<&str> {
    match t {
        Term::Ident(n) => Some(n.as_str()),
        _ => None,
    }
}

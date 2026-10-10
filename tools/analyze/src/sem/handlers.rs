//! The handlers a tree's declarations name, resolved and analyzed once per run.
//!
//! `sem/reads` and `sem/handlers` both judge the same facts (what each handler reads and what it
//! does), so the analysis is memoized on the tree: [`analyzed`]. When no declaration names a
//! handler (the tree before content converts), nothing here parses anything.

use std::sync::Arc;

use super::decls::Decls;
use super::graph::DepGraph;
use super::hooks::{self, HandlerRef};
use super::reads::{Annotations, ReadSet, ReadsEngine};
use crate::tree::Tree;

/// Engine-internal directories the reads walk does not enter (dispatchers that read `vars[]` by
/// design, the tgui plumbing). Their correctness is the engine's, not the handler's.
pub const OPAQUE_DIRS: &[&str] = &["code/datums/sys/", "code/datums/om/", "code/modules/tgui/", "code/datums/capabilities/", "code/datums/reactions/", "code/datums/ownership/", "code/engine/", "code/__defines/verdigris/"];

pub struct Analyzed {
    pub h: HandlerRef,
    /// The type the proc was looked up on (the capability datum for `CAP_PROC`).
    pub on: String,
    /// The type exists in the model (an unknown type is `handler_unresolved` too, but a type the
    /// partial model cannot see is not).
    pub proc_found: bool,
    /// Definition site of the proc: (file, line, params, has body).
    pub def: Option<(String, u32)>,
    pub params: Vec<Vec<String>>,
    pub set: Option<ReadSet>,
    /// Return-protocol violations of the top-level body (conditions and requirements).
    pub returns: Vec<super::checks::Found>,
    /// Reads of a var that is not tracked, a relation, a stat, a derived value or constant:
    /// (read key, var, owner type, file, line).
    pub unknown: Vec<(String, String, String, String, u32)>,
    /// Writes and observable calls in a pure handler's followed bodies: (what, file, line).
    pub impure: Vec<(String, String, u32)>,
    pub type_found: bool,
    /// Context fields the handler reads that its context type does not carry: (field, file, line).
    pub bad_ctx: Vec<(String, String, u32)>,
}

pub struct Analysis {
    pub handlers: Vec<Analyzed>,
    pub graph: Option<DepGraph>,
    /// Same-entity cycles of the derive graph.
    pub cycles: Vec<Vec<String>>,
    /// `READS_AS` accessors: (type, proc, key, reads that are neither tracked nor constant).
    pub accessor_gaps: Vec<AccessorGap>,
}

pub struct AccessorGap {
    pub ty: String,
    pub proc: String,
    pub key: String,
    pub vars: Vec<String>,
    pub rel: String,
    pub line: u32,
}

/// The analysis of every declared handler, or `None` when the tree declares none.
pub fn analyzed(tree: &Tree) -> Option<Arc<Analysis>> {
    let a = tree.memo("sem/handlers", || compute(tree));
    if a.handlers.is_empty() && a.accessor_gaps.is_empty() {
        None
    } else {
        Some(a)
    }
}

fn compute(tree: &Tree) -> Analysis {
    let decls = Decls::get(tree);
    let refs: Vec<HandlerRef> = hooks::discover(&decls);
    let has_reads_as = decls.markers_named("READS_AS").next().is_some();
    let mut an = Analysis { handlers: Vec::new(), graph: None, cycles: Vec::new(), accessor_gaps: Vec::new() };
    if refs.is_empty() && !has_reads_as {
        return an;
    }
    let Some(sem) = super::sem_for(tree) else { return an };
    let ann = Annotations::get(&sem, &decls);
    let eng = ReadsEngine::new(&sem, &decls, &ann).with_opaque(OPAQUE_DIRS);
    let written = super::reads::WriteIndex::build(&sem);
    let mut seen = std::collections::HashSet::new();
    // The typed fields every ACTION() declares.
    let action_fields: std::collections::HashSet<String> = decls
        .markers_named("ACTION")
        .flat_map(|m| m.args.iter().skip(1).filter(|a| a.as_str() != "FIXED" && !a.contains('=')).map(|a| a.rsplit('/').next().unwrap_or(a).trim().to_string()).collect::<Vec<_>>())
        .collect();
    for h in refs {
        let on = if h.cap_proc { h.cap_type.clone() } else { h.owner.clone() };
        if on.is_empty() {
            continue;
        }
        if !seen.insert((on.clone(), h.proc.clone(), h.form, h.rel.clone(), h.line)) {
            continue;
        }
        let pr = sem.proc_ref(&on, &h.proc);
        let (proc_found, def, params, returns) = match pr {
            Some(p) if !p.is_builtin() => {
                let b = sem.proc_body(p);
                let params = b.params.iter().map(|p| p.var_type.type_path.to_vec()).collect();
                let mut returns = Vec::new();
                if h.role.boolean() {
                    if let Some(code) = b.code {
                        super::checks::boolean_returns(code, &mut returns);
                    }
                } else if h.role == hooks::Role::Requirement {
                    if let Some(code) = b.code {
                        super::checks::requirement_returns(code, &mut returns);
                    }
                }
                (true, Some((b.file, b.line)), params, returns)
            }
            _ => (false, None, Vec::new(), Vec::new()),
        };
        let set = if proc_found && !h.cap_proc { Some(eng.analyze_handler(&on, &h.proc, h.ctx.type_path())) } else { None };
        let mut unknown = Vec::new();
        if let (Some(set), true) = (&set, h.role.reads_covered()) {
            for r in &set.reads {
                if r.kind == super::reads::ReadKind::Var && eng.classify(&r.owner, &r.var, &written) == super::reads::VarClass::Unknown {
                    let (rel, line) = set.sites.get(r).cloned().unwrap_or_default();
                    unknown.push((r.key(), r.var.clone(), r.owner.clone(), rel, line));
                }
            }
        }
        let mut impure = Vec::new();
        if let (Some(set), true) = (&set, h.role.pure()) {
            for e in &set.effects {
                // A tracked var's own setter writes it by design; the call to the setter is the finding.
                if e.kind == "assign" && e.proc.starts_with("set_") && e.proc[4..] == e.name {
                    continue;
                }
                let what = match e.kind {
                    "assign" if eng.is_tracked(&e.owner, &e.name) || eng.is_relation(&e.owner, &e.name) => Some(format!("assigns the tracked var `{}`", e.name)),
                    "call" if super::reads::MESSAGE_CALLS.contains(&e.name.as_str()) => Some(format!("calls {}(), which talks to a player", e.name)),
                    "call" if super::reads::IMPURE_CALLS.contains(&e.name.as_str()) || e.name.starts_with("rel_") => Some(format!("calls {}()", e.name)),
                    "call" if e.name.starts_with("set_") && eng.is_tracked(&e.owner, &e.name[4..]) => Some(format!("calls the setter {}()", e.name)),
                    _ => None,
                };
                if let Some(w) = what {
                    impure.push((w, e.rel.clone(), e.line));
                }
            }
        }
        let type_found = sem.ty(&on).is_some();
        let mut bad_ctx = Vec::new();
        if let Some(set) = &set {
            for (field, (rel, line)) in &set.ctx_fields {
                // A world action's hooks read the action's typed fields, a notice handler the notice's.
                let action_field = h.ctx == hooks::Ctx::Action && action_fields.contains(field);
                let notice_field = !h.notice.is_empty() && sem.var_decl(&h.notice, field).is_some();
                if !action_field && !notice_field && sem.var_decl(h.ctx.type_path(), field).is_none() && sem.proc_ref(h.ctx.type_path(), field).is_none() {
                    bad_ctx.push((field.clone(), rel.clone(), *line));
                }
            }
        }
        an.handlers.push(Analyzed { h, on, proc_found, def, params, set, returns, unknown, impure, type_found, bad_ctx });
    }
    let graph = DepGraph::from_derives(&sem, &eng);
    an.cycles = graph.cycles();
    an.graph = Some(graph);
    // READS_AS accessors whose own reads are neither tracked nor constant must have a producer for their key.
    for ((ty, name), (key, _via)) in &ann.reads_as {
        let set = eng.analyze(ty, name);
        let mut vars = Vec::new();
        for r in &set.reads {
            if r.kind != super::reads::ReadKind::Var || !r.hops.is_empty() {
                continue;
            }
            if eng.classify(&r.owner, &r.var, &written) == super::reads::VarClass::Unknown {
                vars.push(r.var.clone());
            }
        }
        let published = decls.publishers.contains_key(key) || eng.is_tracked(ty, key);
        if !vars.is_empty() && !published {
            let (rel, line) = sem.proc_ref(ty, name).map(|p| sem.proc_body(p)).map(|b| (b.file, b.line)).unwrap_or_default();
            an.accessor_gaps.push(AccessorGap { ty: ty.clone(), proc: name.clone(), key: key.clone(), vars, rel, line });
        }
    }
    an.accessor_gaps.sort_by(|a, b| (a.rel.as_str(), a.line).cmp(&(b.rel.as_str(), b.line)));
    let footprint = sem.footprint();
    if std::env::var("DQ_ANALYZE_TRACE").is_ok() {
        eprintln!("analyze: sem footprint: {} handlers, {} files consulted", an.handlers.len(), footprint.len());
    }
    super::incremental::capture(tree, &sem, footprint);
    an
}

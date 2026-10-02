//! `sem/handlers`: handler signatures, context fields and escape, ACT_TRY pairing, purity.
//!
//! "One handler signature: every proc the engine calls to run a part or a trigger is
//! `x(datum/act/A)`" and "a pooled datum/act may not be stored in a var or passed in with =; use
//! A.snapshot()" (doc/rewrite/final_api.html sections 7 and 8, the semantic-checks table).
//!
//! Over the procs a declaration names (`sem::hooks`), with the context type the hook form gives:
//!
//! * `handler_unresolved`: the named proc does not exist on the type (or the type does not).
//! * `signature`: not `x(datum/act/A)`.
//! * `context_field`: a field the context type does not carry (`A.actor` in a `when()` condition,
//!   `A.dt` in a requirement).
//! * `impure`: a requirement, condition, output or contribution (or any body it follows) that
//!   writes a tracked var, or calls a setter, hold, release, grant, revoke, `rel_*` or a message.
//! * `requirement_return`: a requirement or condition that returns text, a type, null or a number
//!   other than TRUE/FALSE (it would read as TRUE and silently allow the op).
//!
//! And over every proc that takes a context or starts an action (structural, no declaration needed):
//!
//! * `act_try_unpaired`: an `ACT_TRY` without `act_done` or `act_cancel` on every path of the proc.
//! * `context_escape`: a pooled `datum/act` stored in a var, a list, or passed in with `=`.
//! * `output_signature`: an override of a standard output base declared under `code/engine/` whose
//!   parameters differ from the base.
//!
//! Only the files that mention an action or a context are parsed for the structural checks, and the
//! full model is built only when a declaration names a handler or an engine output base exists.

use std::collections::BTreeSet;

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::pat::Pat;
use crate::sem::checks::{act_idents, act_try_pairing, context_escape, Found, DEFAULT_TRY_CALLS};
use crate::sem::handlers;
use crate::sem::Sem;
use crate::tree::CODE_DM;

const H_UNRESOLVED: &str = "name a proc the type declares, or fix the declaration";
const H_SIG: &str = "every handler is x(datum/act/A): one parameter of a datum/act type, A.holder always set";
const H_FIELD: &str = "read only the fields the context type carries (doc/rewrite/final_api.html section 8): use a requirement for A.actor, an output for A.dt";
const H_IMPURE: &str = "requirements, conditions, outputs and contributions are pure: move the write into an effect (then()) or a setter called from one";
const H_RETURN: &str = "answer TRUE or FALSE; the refusal text is the requirement's declared reason (because = ...)";
const H_PAIR: &str = "act_done(F) or act_cancel(F) on every path after ACT_TRY (a branch that tests F for null or ACT_PASS needs neither)";
const H_ESCAPE: &str = "a context is pooled and lives for one trigger: use A.snapshot() for anything that must outlive it";
const H_OUTPUT: &str = "an override takes the base's parameters exactly, or it is a silent no-op";

static META: Meta = Meta {
    name: "sem/handlers",
    group: "sem",
    label: "handlers",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::Tree,
    policy: Policy::Hard,
    rules: &[
        RuleMeta { name: "handler_unresolved", hint: H_UNRESOLVED },
        RuleMeta { name: "signature", hint: H_SIG },
        RuleMeta { name: "context_field", hint: H_FIELD },
        RuleMeta { name: "impure", hint: H_IMPURE },
        RuleMeta { name: "requirement_return", hint: H_RETURN },
        RuleMeta { name: "act_try_unpaired", hint: H_PAIR },
        RuleMeta { name: "context_escape", hint: H_ESCAPE },
        RuleMeta { name: "output_signature", hint: H_OUTPUT },
    ],
    allow: &["handlers"],
    lists: &["try_calls"],
};

/// Standard outputs: base procs the engine calls by name.
const STD_OUTPUTS: &[&str] = &["draw", "ui_data", "push_to_rust", "examine"];

struct SemHandlers;

fn candidate_re() -> &'static Pat {
    crate::pat!(r"\bACT_TRY\b|\b(?:e0_)?act_try\b|\bdatum/act\b")
}

fn engine_output_re() -> &'static Pat {
    crate::pat!(r"/proc/(?:draw|ui_data|push_to_rust|examine)\s*\(")
}

impl Lint for SemHandlers {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        let allowed = |out: &mut Sink, rel: &str, line: u32| -> bool {
            match cx.tree.get(rel) {
                Some(f) => out.allowed(f, line as usize, "handlers"),
                None => false,
            }
        };
        let mut seen: std::collections::HashSet<(String, String, u32, String)> = std::collections::HashSet::new();
        let mut put = |out: &mut Sink, rule: &'static str, rel: &str, line: u32, msg: String| {
            if rel.is_empty() || !seen.insert((rule.to_string(), rel.to_string(), line, msg.clone())) {
                return;
            }
            if allowed(out, rel, line) {
                return;
            }
            out.site_in_msg(rule, rel, line as usize, msg);
        };

        // ---- structural checks over the files that mention an action or a context ----
        let cands: Vec<String> = cx.files().iter().filter(|f| candidate_re().is_match(&f.code().text)).map(|f| f.rel.clone()).collect();
        if !cands.is_empty() {
            let extra: Vec<&str> = cx.list("try_calls").iter().map(|s| s.as_str()).collect();
            let mut try_calls: Vec<&str> = DEFAULT_TRY_CALLS.to_vec();
            try_calls.extend(extra);
            match Sem::build_partial(&cx.tree.root, cx.tree, &cands) {
                Ok(sem) => {
                    let set: BTreeSet<&str> = cands.iter().map(|s| s.as_str()).collect();
                    for ty in sem.objtree.iter_types() {
                        for (_name, tp) in ty.get().procs.iter() {
                            for v in &tp.value {
                                let rel = sem.rel(v.location);
                                let (true, Some(code)) = (set.contains(rel), &v.code) else { continue };
                                let (acts, locals) = act_idents(&v.parameters, code, &try_calls);
                                let mut found: Vec<Found> = Vec::new();
                                context_escape(code, &acts, &locals, &mut found);
                                act_try_pairing(code, &try_calls, &mut found);
                                for f in found {
                                    put(out, f.rule, rel, f.line, f.msg);
                                }
                            }
                        }
                    }
                }
                Err(e) => eprintln!("analyze: sem/handlers: {}", e),
            }
        }

        // ---- standard outputs declared under code/engine: overrides must match the base ----
        let engine_bases = cx.files().iter().any(|f| f.rel.starts_with("code/engine/") && engine_output_re().is_match(&f.code().text));
        if engine_bases {
            if let Some(sem) = cx.sem() {
                for name in STD_OUTPUTS {
                    let mut base: Option<(String, Vec<String>)> = None;
                    let mut defs: Vec<(String, String, u32, Vec<String>)> = Vec::new();
                    for ty in sem.objtree.iter_types() {
                        let Some(tp) = ty.get().procs.get(*name) else { continue };
                        let path = if ty.get().path.is_empty() { "/".to_string() } else { ty.get().path.clone() };
                        for v in &tp.value {
                            let rel = sem.rel(v.location).to_string();
                            let params: Vec<String> = v.parameters.iter().map(|p| p.name.clone()).collect();
                            if rel.starts_with("code/engine/") {
                                if base.as_ref().map(|(p, _)| path.len() < p.len()).unwrap_or(true) {
                                    base = Some((path.clone(), params));
                                }
                            } else {
                                defs.push((path.clone(), rel, v.location.line, params));
                            }
                        }
                    }
                    if let Some((bty, bparams)) = base {
                        for (ty, rel, line, params) in defs {
                            if params != bparams {
                                put(out, "output_signature", &rel, line, format!("{}::{}({}) overrides {}::{}({})", ty, name, params.join(", "), bty, name, bparams.join(", ")));
                            }
                        }
                    }
                }
            }
        }

        // ---- declared handlers ----
        let Some(an) = handlers::analyzed(cx.tree) else { return };
        for a in &an.handlers {
            let h = &a.h;
            let who = format!("{}::{} ({}())", a.on, h.proc, h.form);
            if !a.proc_found {
                let why = if a.type_found { format!("{} has no proc `{}`", a.on, h.proc) } else { format!("type {} does not exist", a.on) };
                put(out, "handler_unresolved", &h.rel, h.line, format!("{} names a handler that does not resolve: {}", h.form, why));
                continue;
            }
            let (drel, dline) = a.def.clone().unwrap_or((h.rel.clone(), h.line));
            let is_act = |p: &Vec<String>| p.len() >= 2 && p[0] == "datum" && p[1] == "act";
            if a.params.len() != 1 || !is_act(&a.params[0]) {
                put(out, "signature", &drel, dline, format!("{} takes {} parameter(s); a handler is x(datum/act/A)", who, a.params.len()));
            }
            for (field, rel, line) in &a.bad_ctx {
                put(out, "context_field", rel, *line, format!("{} reads A.{}, which a {} context does not carry", who, field, h.ctx.type_path()));
            }
            for (what, rel, line) in &a.impure {
                put(out, "impure", rel, *line, format!("{} is pure ({}) but {}", who, h.form, what));
            }
            for f in &a.returns {
                put(out, f.rule, &drel, f.line, format!("{}: {}", who, f.msg));
            }
        }
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(SemHandlers);
}

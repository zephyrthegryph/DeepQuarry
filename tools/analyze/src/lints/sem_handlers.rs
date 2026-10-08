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
        let all_files = cx.files();
        // Per-file facts (cached by content): does the file mention an action or a context, and is it an engine output base.
        let cand_flags: Vec<bool> = crate::incr::facts("sem-handlers-cand", &all_files, |f| candidate_re().is_match(&f.code().text));
        let base_flags: Vec<bool> = crate::incr::facts("sem-handlers-base", &all_files, |f| f.rel.starts_with("code/engine/") && engine_output_re().is_match(&f.code().text));
        let cands: Vec<String> = all_files.iter().zip(&cand_flags).filter(|(_, c)| **c).map(|(f, _)| f.rel.clone()).collect();
        if !cands.is_empty() {
            let extra: Vec<&str> = cx.list("try_calls").iter().map(|s| s.as_str()).collect();
            // ACT_TRY(E, name, ...) expands to act_<name>(E, ...), generated for each non-FIXED ACTION(name, ...).
            let generated: Vec<String> = crate::sem::decls::Decls::get(cx.tree)
                .markers_named("ACTION")
                .filter(|m| !m.args.iter().any(|a| a == "FIXED"))
                .filter_map(|m| m.args.first().map(|n| format!("act_{}", n.replace('/', "_"))))
                .collect();
            let mut try_calls: Vec<&str> = DEFAULT_TRY_CALLS.to_vec();
            try_calls.extend(extra);
            try_calls.extend(generated.iter().map(|s| s.as_str()));
            // The sites of the structural pass, keyed by everything the partial parse reads: the
            // candidates, the defines (macros), the call names. Unchanged inputs skip the parse.
            let cand_keys: Vec<(&str, u128)> = all_files.iter().zip(&cand_flags).filter(|(_, c)| **c).map(|(f, _)| (f.rel.as_str(), f.fkey)).collect();
            let defines: Vec<(&str, u128)> = cx.tree.select(&crate::tree::CODE_DM).iter().filter(|f| f.rel.starts_with("code/__defines/")).map(|f| (f.rel.as_str(), f.fkey)).collect();
            let key = crate::incr::ctx_key(&(&cand_keys, &defines, &try_calls));
            let found_all: Vec<(String, String, u32, String)> = crate::incr::cached("sem-handlers-structural", key, || {
                let mut found_all: Vec<(String, String, u32, String)> = Vec::new();
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
                                        found_all.push((f.rule.to_string(), rel.to_string(), f.line, f.msg));
                                    }
                                }
                            }
                        }
                    }
                    Err(e) => eprintln!("analyze: sem/handlers: {}", e),
                }
                found_all
            });
            for (rule, rel, line, msg) in found_all {
                let rule: &'static str = match rule.as_str() {
                    "act_try_unpaired" => "act_try_unpaired",
                    "context_escape" => "context_escape",
                    "requirement_return" => "requirement_return",
                    _ => "context_escape",
                };
                put(out, rule, &rel, line, msg);
            }
        }

        // ---- standard outputs declared under code/engine: overrides must match the base ----
        let engine_bases = base_flags.iter().any(|b| *b);
        if engine_bases {
            if let Some(sem) = cx.sem() {
                for (rel, line, msg) in output_signature_findings(&sem) {
                    put(out, "output_signature", &rel, line, msg);
                }
            }
        }

        // ---- declared handlers ----
        // Unless a full model was needed above (an engine output base), the stored result stands when
        // its inputs are unchanged.
        if !engine_bases {
            if let Some(rec) = crate::sem::incremental::lookup(cx.tree) {
                if let Some(st) = rec.sinks.get("sem/handlers") {
                    out.sites.extend(st.sites.iter().cloned());
                    for u in &st.allow_used {
                        if !out.allow_used.contains(u) {
                            out.allow_used.push(u.clone());
                        }
                    }
                    return;
                }
            }
        }
        let Some(an) = handlers::analyzed(cx.tree) else { return };
        let (sites_before, allow_before) = (out.sites.len(), out.allow_used.len());
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
            // A UI or topic op's handler also takes the op's declared args, typed, after A.
            let expected = 1 + h.ui_args.as_ref().map(|v| v.len()).unwrap_or(0);
            if a.params.len() != expected || a.params.is_empty() || !is_act(&a.params[0]) {
                put(out, "signature", &drel, dline, format!("{} takes {} parameter(s); a handler is x(datum/act/A){}", who, a.params.len(), if expected > 1 { " plus one parameter per declared arg()" } else { "" }));
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
        if !engine_bases {
            let mut part = Sink::new();
            part.sites = out.sites[sites_before..].to_vec();
            part.allow_used = out.allow_used[allow_before..].to_vec();
            crate::sem::incremental::store(cx.tree, "sem/handlers", &part);
        }
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(SemHandlers);
}

/// Compare an override with the nearest actual engine declaration on its parent_type chain.
/// Unrelated output protocols (atom draw versus capability draw) do not share a signature.
fn output_signature_findings(sem: &Sem) -> Vec<(String, u32, String)> {
    let mut found = Vec::new();
    for name in STD_OUTPUTS {
        let mut bases = std::collections::BTreeMap::<String, Vec<String>>::new();
        let mut defs = Vec::<(String, String, u32, Vec<String>)>::new();
        for ty in sem.objtree.iter_types() {
            let Some(tp) = ty.get().procs.get(*name) else { continue };
            let path = if ty.get().path.is_empty() { "/".to_string() } else { ty.get().path.clone() };
            for v in &tp.value {
                let rel = sem.rel(v.location).to_string();
                let params: Vec<String> = v.parameters.iter().map(|p| p.name.clone()).collect();
                if rel.starts_with("code/engine/") {
                    bases.insert(path.clone(), params);
                } else {
                    defs.push((path.clone(), rel, v.location.line, params));
                }
            }
        }
        for (ty, rel, line, params) in defs {
            let mut ancestor = Some(ty.clone());
            while let Some(path) = ancestor {
                if let Some(base_params) = bases.get(&path) {
                    if &params != base_params {
                        found.push((rel, line, format!("{}::{}({}) overrides {}::{}({})", ty, name, params.join(", "), path, name, base_params.join(", "))));
                    }
                    break;
                }
                ancestor = sem.parent_of(&path);
            }
        }
    }
    found
}

#[cfg(test)]
mod output_tests {
    use super::*;
    use crate::tree::{SourceFile, Tree};

    fn fixture() -> (tempfile::TempDir, Sem) {
        let root = tempfile::tempdir().unwrap();
        let sources = [
            ("code/engine/present/protocols.dm", "/datum/look\n/atom/proc/draw(datum/look/look)\n\treturn\n/datum/capability\n/datum/capability/proc/draw(atom/holder, datum/look/look)\n\treturn\n"),
            ("code/library/output_probe.dm", "/obj/good/draw(datum/look/look)\n\treturn\n/datum/nonlexical\n\tparent_type = /datum/capability\n/datum/nonlexical/draw(atom/holder, datum/look/look)\n\treturn\n/obj/bad/draw(atom/holder, datum/look/look)\n\treturn\n/datum/malformed_cap\n\tparent_type = /datum/capability\n/datum/malformed_cap/draw(datum/look/look)\n\treturn\n/datum/unrelated/proc/draw(value)\n\treturn\n"),
        ];
        let mut files = Vec::new();
        for (rel, text) in sources {
            let path = root.path().join(rel);
            std::fs::create_dir_all(path.parent().unwrap()).unwrap();
            std::fs::write(path, text).unwrap();
            files.push(SourceFile::from_text(rel, text));
        }
        let sem = Sem::build(root.path(), &Tree::from_files(files)).unwrap();
        assert!(sem.errors.is_empty(), "invalid semantic fixture: {:?}", sem.errors);
        (root, sem)
    }

    #[test]
    fn distinct_draw_protocols_follow_actual_ancestry() {
        let (_root, sem) = fixture();
        let found = output_signature_findings(&sem);
        assert_eq!(found.len(), 2, "valid atom/capability outputs and an unrelated draw proc are accepted: {:?}", found);
        assert!(found.iter().any(|(_, _, message)| message.contains("/obj/bad::draw") && message.contains("overrides /atom::draw")));
        assert!(found.iter().any(|(_, _, message)| message.contains("/datum/malformed_cap::draw") && message.contains("overrides /datum/capability::draw")));
    }
}

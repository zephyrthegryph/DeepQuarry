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
//! * `requirement_return`: a requirement that returns a boolean, or a condition/req_bool callback that returns a non-boolean
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
use crate::sem::checks::{act_idents, act_try_pairing, context_escape, Found, DEFAULT_TRY_CALLS};
use crate::sem::handlers;
use crate::sem::Sem;
use crate::tree::CODE_DM;

use crate::sem_handlers_policy::{metadata,STANDARD_OUTPUTS as STD_OUTPUTS};
struct SemHandlers;

impl Lint for SemHandlers {
    fn meta(&self) -> &Meta {
        metadata()
    }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        let allowed = |out: &mut Sink, rel: &str, line: u32| -> bool {
            match cx.tree.get(rel) {
                Some(f) => out.allowed(f, line as usize, crate::sem_handlers_report_policy::ALLOW_NAME),
                None => false,
            }
        };
        let mut seen = crate::sem_handlers_report_policy::Seen::default();
        let mut put = |out: &mut Sink, rule: &'static str, rel: &str, line: u32, msg: String| {
            if !seen.admit_using(rule, rel, line, &msg, &mut crate::key_policy_control::Compatibility).unwrap_or_else(|never|match never{}) {
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
        let cand_flags: Vec<bool> = crate::incr::facts("sem-handlers-cand", &all_files, |f| crate::sem_handlers_partial_recipe::candidate(&f.code().text));
        let base_flags: Vec<bool> = crate::incr::facts("sem-handlers-base", &all_files, |f| crate::sem_handlers_partial_recipe::output_base(&f.rel,&f.code().text));
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
                                    let (true, Some(code)) = (set.contains(rel), &*v.code) else { continue };
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
            let result=crate::sem_handlers_policy::declared_using(crate::sem_handlers_policy::Declared{hook:&a.h,on:&a.on,proc_found:a.proc_found,type_found:a.type_found,definition:a.def.as_ref().map(|(rel,line)|(rel.as_str(),*line)),parameters:&a.params,bad_context:&a.bad_ctx,impure:&a.impure,returns:&a.returns},&mut crate::key_policy_control::Compatibility,&mut|_,rule,rel,line,message|{put(out,rule,rel,line,message);Ok(())});
            match result{Ok(())=>{},Err(never)=>match never{}}
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
fn output_signature_findings(sem:&Sem)->Vec<(String,u32,String)>{
 let mut found=Vec::new();let mut control=crate::key_policy_control::Compatibility;
 for &name in STD_OUTPUTS{let mut output=crate::sem_handlers_output_policy::Output::default();
  for ty in sem.objtree.iter_types(){let Some(proc)=ty.get().procs.get(name)else{continue};let owner=if ty.get().path.is_empty(){"/"}else{ty.get().path.as_str()};
   for value in &proc.value{output.push_using(owner,sem.rel(value.location),value.location.line,value.parameters.iter().map(|parameter|parameter.name.as_str()),&mut control).unwrap_or_else(|never|match never{});}
  }
  output.finish_using(name,&mut|owner,_|Ok(sem.parent_of(owner)),&mut|relative,line,message,_|{found.push((relative.to_owned(),line,message));Ok(())},&mut control).unwrap_or_else(|never|match never{});
 }found
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

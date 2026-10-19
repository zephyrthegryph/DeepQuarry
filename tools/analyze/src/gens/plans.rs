//! `analyze gen plans` -> `code/engine/_generated/plans.dm`: the change graph's interned keys and per-type plans
//! (doc/rewrite/proposals/change_graph.md sections 2, 4 and 11 step 2).
//!
//! ```text
//! #define CGK_<var> <n>                 one int per observable var name any plan names, numbered by sorted name (deterministic, diff-free)
//! GLOB.generated_key_names              list: id -> name (the log table; runtime-only keys are interned above it, code/engine/change/plan.dm)
//! GLOB.generated_plans                  "<type>" = list("<var>" = PLAN_*, ...)   for each type that declares a draw(): what its draw reads, on the
//!                                       holder (PLAN_DRAW) and one container, turf or area hop away (PLAN_DRAW_HOP, keyed "<hop>.<var>")
//! GLOB.generated_plan_fallbacks         "<type>" = TRUE   a draw whose reads the walk could not resolve (D5: such a type redraws on every write)
//! ```
//!
//! Step 2 generates the plan from the same analysis `gen deps` uses (`deps::analyzed`) so that the runtime can answer "who reads this key" from one
//! table; the parity test (`dq_change_plan_parity`) proves the plan and today's tables agree for every type before step 3 deletes the tables.
//! Kept in its own module: `gen deps` and the analyzer core are being reworked elsewhere.

use std::collections::{BTreeMap, BTreeSet};

use crate::sem::gen::{GenCx, GenOut, Generator};

use super::deps;

struct Plans;

fn quote(s: &str) -> String {
    format!("\"{}\"", s.replace('\\', "\\\\").replace('"', "\\\"").replace('[', "\\["))
}

/// A var name that can be a `KEY_<name>` define.
fn key_ident(s: &str) -> bool {
    !s.is_empty() && s.chars().all(|c| c.is_ascii_alphanumeric() || c == '_') && !s.starts_with(|c: char| c.is_ascii_digit())
}

fn emit_table(out: &mut GenOut, name: &str, rows: &[(String, String)]) {
    for (n, chunk) in rows.chunks(300).enumerate() {
        out.line(format!("/proc/{}_chunk_{}()", name, n));
        out.line("\t. = list()");
        for (k, v) in chunk {
            out.line(format!("\t.[{}] = {}", k, v));
        }
    }
    out.line(format!("/proc/{}_build()", name));
    out.line("\t. = list()");
    for n in 0..rows.chunks(300).count() {
        out.line(format!("\tvar/list/c{} = {}_chunk_{}()", n, name, n));
        out.line(format!("\tfor(var/k in c{})", n));
        out.line(format!("\t\t.[k] = c{}[k]", n));
    }
    out.line(format!("GLOBAL_LIST_INIT({}, {}_build())", name, name));
}

impl Generator for Plans {
    fn name(&self) -> &'static str {
        "plans"
    }

    fn stage(&self) -> u8 {
        1
    }

    fn output(&self) -> &'static str {
        "plans.dm"
    }

    fn generate(&self, cx: &GenCx, out: &mut GenOut) {
        let _ = cx.sem();
        let an = deps::analyzed(cx.tree);
        let Some(an) = an.as_ref().as_ref() else {
            out.diag("deepquarry.dme", 1, "the semantic model could not be built; the change graph's plans cannot be generated");
            return;
        };
        // Per type: var -> PLAN bits as DM text.
        let mut plans: BTreeMap<&str, BTreeMap<String, BTreeSet<&str>>> = BTreeMap::new();
        let mut names: BTreeSet<String> = BTreeSet::new();
        for (t, vars) in &an.draw_reads {
            for v in vars {
                plans.entry(t.as_str()).or_default().entry(v.clone()).or_default().insert("PLAN_DRAW");
                names.insert(v.clone());
            }
        }
        for (t, reads) in &an.draw_hops {
            for r in reads {
                plans.entry(t.as_str()).or_default().entry(r.clone()).or_default().insert("PLAN_DRAW_HOP");
                if let Some((_, v)) = r.rsplit_once('.') {
                    names.insert(v.to_string());
                }
            }
        }
        for (t, links) in &an.draw_links {
            for v in links {
                plans.entry(t.as_str()).or_default().entry(v.clone()).or_default().insert("PLAN_DRAW");
                names.insert(v.clone());
            }
        }
        let mut verbs: BTreeMap<&str, BTreeMap<&str, &BTreeSet<String>>> = BTreeMap::new();
        for (id, (vars, _)) in &an.verb_reads {
            if let Some((t, proc_name)) = id.rsplit_once("::") {
                verbs.entry(proc_name).or_default().insert(t, vars);
                for v in vars {
                    names.insert(v.clone());
                }
            }
        }
        for (_, v) in &an.reads {
            names.insert(v.clone());
        }
        let names: Vec<String> = names.into_iter().filter(|n| key_ident(n)).collect();
        out.doc("The change graph's keys (doc/rewrite/proposals/change_graph.md section 2): one int per var name a plan or a reactive read names,");
        out.doc("numbered by sorted name. Hand code writes CGK_<name> (CGK: a KEY_ prefix is taken by other defines), never the int.");
        for (i, n) in names.iter().enumerate() {
            out.line(format!("#define CGK_{} {}", n, i + 1));
        }
        out.line(format!("#define CGK_BUILD_MAX {}", names.len()));
        out.blank();
        out.doc("id -> key name (logs and runtime interning, code/engine/change/plan.dm).");
        out.line("/proc/generated_key_names_build()");
        out.line("\t. = list()");
        for n in &names {
            out.line(format!("\t. += {}", quote(n)));
        }
        out.line("GLOBAL_LIST_INIT(generated_key_names, generated_key_names_build())");
        out.blank();
        out.doc("\"<type>\" -> list(\"<var>\" or \"<hop>.<var>\" = PLAN_* bits): what the type's own draw() (and the parent draws it calls) reads.");
        out.doc("A type with no row inherits the nearest ancestor's (plan_of(), code/engine/change/plan.dm).");
        let rows: Vec<(String, String)> = plans
            .iter()
            .map(|(t, vars)| {
                let body = vars
                    .iter()
                    .map(|(v, bits)| format!("{} = {}", quote(v), bits.iter().copied().collect::<Vec<_>>().join("|")))
                    .collect::<Vec<_>>()
                    .join(", ");
                (quote(t), format!("list({})", body))
            })
            .collect();
        emit_table(out, "generated_plans", &rows);
        out.blank();
        out.doc("\"<type>\" -> TRUE: a draw() whose reads the walk could not resolve (an untracked or unresolved read). D5: until the walk resolves it, a");
        out.doc("write to such a type marks every output (plan_fallback, counted in GLOB.plan_fallbacks).");
        for (proc_name, by_type) in &verbs {
            out.blank();
            out.doc(format!("\"<type>\" -> list(\"<var>\", ...): what the type's own {}() reads on the holder (a hop chain counts by its first link). It", proc_name));
            out.doc("refreshes on the draw's bit (DEP_DRAW), so a write may skip that bit only when neither the draw nor the verb outputs read the var.");
            let rows: Vec<(String, String)> = by_type
                .iter()
                .map(|(t, vars)| (quote(t), format!("list({})", vars.iter().map(|v| quote(v)).collect::<Vec<_>>().join(", "))))
                .collect();
            emit_table(out, &format!("generated_plan_{}", proc_name), &rows);
        }
        let mut fallbacks: BTreeSet<&str> = BTreeSet::new();
        for (id, (_, unresolved)) in &an.verb_reads {
            if *unresolved {
                if let Some((t, _)) = id.rsplit_once("::") {
                    fallbacks.insert(t);
                }
            }
        }
        for id in &an.draws {
            if an.consumers.get(id).is_some_and(|u| !u.is_empty()) {
                if let Some((t, _)) = id.rsplit_once("::") {
                    fallbacks.insert(t);
                }
            }
        }
        let rows: Vec<(String, String)> = fallbacks.iter().map(|t| (quote(t), "TRUE".to_string())).collect();
        emit_table(out, "generated_plan_fallbacks", &rows);
        out.blank();
        out.doc("\"<capability type>\" -> TRUE: a capability that overrides the legacy draw(holder, look) or hidden_verbs(holder): its reads of the holder");
        out.doc("are not in any plan, so a holder carrying one keeps redrawing on every write (plan_spares_build(), code/engine/change/plan.dm).");
        let mut legacy: BTreeSet<String> = BTreeSet::new();
        if let Some(sem) = cx.sem() {
            for d in crate::sem::procs::proc_defs(&sem, &["draw", "hidden_verbs"]) {
                if d.owner.starts_with("/datum/capability/") {
                    legacy.insert(d.owner.clone());
                }
            }
        }
        let rows: Vec<(String, String)> = legacy.iter().map(|t| (quote(t), "TRUE".to_string())).collect();
        emit_table(out, "generated_capability_legacy_outputs", &rows);
        // The stat layer's input names (step 3 of the change graph, the stats fold): over-inclusive by design. Every nameof() and every
        // `reads = list(...)` item of a declaration block can feed a contribution (entry-building procs such as heat_pump() take them as
        // arguments, which no static rule can follow), so all of them are inputs; the runtime adds the holder reads of the generated handler
        // rows (stat_input_names_build(), code/engine/change/plan.dm). dq_stat_index_oracle proves this covers every key the stat builder
        // registers.
        let decls = crate::sem::decls::Decls::get(cx.tree);
        let mut inputs: BTreeSet<String> = BTreeSet::new();
        for name in ["CAPABILITIES", crate::sem::decls::CAP_ENTRIES, "STAT"] {
            for m in decls.markers_named(name) {
                for v in deps::marker_named_vars(m) {
                    inputs.insert(quote(&v));
                }
                for c in crate::pat!(r"\breads\s*=\s*list\(([^)]*)\)").captures_iter(&m.body) {
                    for item in c.s(1).split(',') {
                        let item = item.trim();
                        if item.len() > 2 && item.starts_with('"') && item.ends_with('"') && !item[1..item.len() - 1].contains('[') {
                            inputs.insert(item.to_string());
                        } else if decls.defines.contains(item) {
                            inputs.insert(item.to_string());
                        }
                    }
                }
            }
        }
        for v in &an.stat_reads {
            if key_ident(v) {
                inputs.insert(quote(v));
            }
        }
        out.blank();
        out.doc("The stat layer's declared input names (raw: a var, \"rel.var\", \"sys:system.var\" or a define naming one), over-inclusive: every nameof()");
        out.doc("and reads = list() item of a declaration block. stat_input_names_build() splits them into GLOB.stat_input_keys.");
        out.line("/proc/generated_stat_input_reads_build()");
        out.line("	. = list()");
        for i in &inputs {
            out.line(format!("	. += {}", i));
        }
        out.line("GLOBAL_LIST_INIT(generated_stat_input_reads, generated_stat_input_reads_build())");
    }
}

pub fn register(reg: &mut Vec<Box<dyn Generator>>) {
    reg.push(Box::new(Plans));
}

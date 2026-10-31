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

use std::collections::BTreeMap;

use crate::sem::gen::{GenCx, GenOut, Generator};

use super::deps;

struct Plans;

#[cfg(test)]
use crate::plans_policy::{proc_body,reader_names,reader_owner,ReaderKeys};

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
            out.diag("deepquarry.dme",1,"the semantic model could not be built; the change graph's plans cannot be generated");
            return;
        };
        let decls=crate::sem::decls::Decls::get(cx.tree);
        let output_defs=if let Some(sem)=cx.sem(){crate::sem::procs::proc_defs(&sem,&["draw","hidden_verbs"])}else{Vec::new()};
        let output_owners:Vec<&str>=output_defs.iter().map(|d|d.owner.as_str()).collect();
        let proc_defs=if let Some(sem)=cx.sem(){crate::sem::procs::proc_defs(&sem,&["reactions","derived","generated_reads","derived_reads"])}else{Vec::new()};
        let mut texts=BTreeMap::new();
        for d in &proc_defs {texts.entry(d.rel.clone()).or_insert_with(||crate::sem::incremental::text_of(cx.tree,&d.rel));}
        let reader_procs:Vec<_>=proc_defs.iter().map(|d|crate::plans_policy::ReaderProc{owner:&d.owner,name:&d.name,source:&texts[&d.rel],header:d.header}).collect();
        let markers:Vec<_>=decls.markers.iter().map(|m|crate::plans_policy::MarkerRow{name:&m.name,args:&m.args,body:&m.body}).collect();
        let files=cx.tree.select(&crate::tree::CODE_DM);
        let input=crate::plans_policy::PlansInput{analysis:an,markers:&markers,defines:&decls.defines,tracked:&decls.tracked,output_defining_owners:&output_owners,reader_procs:&reader_procs,files:&files};
        let mut generated=crate::plans_policy::Output::default();
        crate::plans_policy::generate(&input,&mut generated);
        for diagnostic in generated.diags {out.diag(&diagnostic.rel,diagnostic.line,diagnostic.msg);}
        for line in generated.body.split_terminator('\n'){out.line(line);}

    }
}


pub fn register(reg: &mut Vec<Box<dyn Generator>>) {
    reg.push(Box::new(Plans));
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn proc_body_stops_at_the_next_top_level_line() {
        let text = "/datum/x/reactions()\n\t. = ..()\n\n\t. += on_change(\"a\")\n/datum/x/other()\n\treturn \"b\"\n";
        let body = proc_body(text, 1);
        assert!(body.contains("on_change(\"a\")"));
        assert!(!body.contains("\"b\""));
    }

    #[test]
    fn reader_names_collect_nameof_literals_segments_and_stat_ids() {
        let mut defines = std::collections::HashSet::new();
        defines.insert("STAT_OPERABLE".to_string());
        defines.insert("STAT_MACRO".to_string());
        defines.insert("MOB_KEY_CLIENT".to_string());
        let mut keys: ReaderKeys = BTreeMap::new();
        reader_names(
            "on_change(nameof(charge), then(PROC_REF(x))) seq_step(reads = list(nameof(/mob/living::phobias))) on_change(\"terminal.power\") on_change(STAT_OPERABLE) STAT_MACRO(1) every(when = PROC_REF(work_ready)) MOB_KEY_CLIENT \"has space\"",
            &defines,
            "/obj/x",
            &mut keys,
            1,
        );
        for k in ["\"phobias\"", "\"charge\"", "\"terminal\"", "STAT_OPERABLE", "\"work_ready\"", "MOB_KEY_CLIENT"] {
            assert_eq!(keys.get(&("/obj/x".to_string(), k.to_string())), Some(&1), "{k}");
        }
        assert_eq!(keys.get(&(String::new(), "\"power\"".to_string())), Some(&1), "the far end of a hop is read on every type");
        assert!(!keys.keys().any(|(_, k)| k == "STAT_MACRO"), "a function-like macro is not a stat id");
        assert!(!keys.keys().any(|(_, k)| k.contains("space")), "a literal that is not an identifier path is no key");
        assert_eq!(reader_owner("/datum/capability/powered"), "", "a capability's names fold into every holder");
        assert_eq!(reader_owner(" /obj/machinery "), "/obj/machinery");
    }
}

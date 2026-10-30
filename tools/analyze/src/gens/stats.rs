//! `analyze gen stats` -> `code/engine/_generated/stats.dm` (E3, stats).
//!
//! `STAT(T, name, RULE, id = ..., base =, reapply =, units =, formula = PROC_REF(x), reads = list(...), schema = num(...))` expands to nothing in
//! DM. This reads each one from source and writes what DM cannot: the stat's var on its type with its base as the default (when the type, or an
//! ancestor, has no var of that name; `density`, `opacity` and `invisibility` are BYOND's own and are never declared), the proc on `T` that
//! returns the stat's row, and the registration the engine reads at boot. The id is `STAT_<NAME>`, written by `analyze gen declare_ids`.
//! Declarations in files under `code/tests/` go in an `#if defined(UNIT_TESTS)` block.
//!
//! `virtual = TRUE` declares no var (an atom-wide stat, or one whose name a legacy proc holds): its value is read with `stat_value(E, STAT_X)`.
//!
//! The row's options are copied as written, so `formula = PROC_REF(compute)` resolves against `T`, which is where the proc is defined.

use crate::sem::gen::{GenCx, GenOut, Generator};
struct Stats;
impl Generator for Stats {
    fn name(&self) -> &'static str {
        "stats"
    }
    fn output(&self) -> &'static str {
        "stats.dm"
    }
    fn generate(&self, cx: &GenCx, out: &mut GenOut) {
        let mut builder = crate::stats_policy::Builder::default();
        for m in cx.markers("STAT") {
            builder.push(&m.rel, m.line, &m.args);
        }
        let files: Vec<_> = cx
            .tree
            .select(&crate::tree::CODE_DM)
            .into_iter()
            .filter(|f| !f.rel.ends_with("_generated/stats.dm"))
            .collect();
        let vars = crate::dm::dx::type_vars_in(cx.tree, &files);
        let generated = builder.finish(|ty, name| {
            crate::stats_policy::declares_var(
                |t, n| vars.get(t).is_some_and(|v| v.contains(n)),
                ty,
                name,
            )
        });
        for d in generated.diags {
            out.diag(&d.rel, d.line, d.msg);
        }
        for line in generated.body.split_terminator('\n') {
            out.line(line);
        }
    }
}
pub fn register(reg: &mut Vec<Box<dyn Generator>>) {
    reg.push(Box::new(Stats));
}
#[cfg(test)]
mod tests {
    use super::*;
    use crate::sem::gen::render;
    use crate::tree::{SourceFile, Tree};
    use std::path::Path;

    fn gen(files: Vec<(&str, &str)>) -> String {
        let tree = Tree::from_files(
            files
                .into_iter()
                .map(|(r, t)| SourceFile::from_text(r, t))
                .collect(),
        );
        let cx = GenCx::new(&tree, Path::new("."));
        render(&Stats, &cx).0
    }

    #[test]
    fn a_stat_gets_its_var_with_the_rules_base_and_a_row() {
        let text = gen(vec![(
            "code/a.dm",
            "STAT(/obj/machinery, operable, ALL)\nSTAT(/mob/living, acts_via, MASK_AND, base = ORIGIN_ALL)\nSTAT(/atom, density, TOP)\nSTAT(/mob/living, stun, MAX, units = LIFE_CYCLE, reapply = REAPPLY_MAX)\n",
        )]);
        assert!(
            text.contains("/obj/machinery/var/operable = TRUE //"),
            "{}",
            text
        );
        assert!(
            text.contains("/mob/living/var/acts_via = ORIGIN_ALL //"),
            "{}",
            text
        );
        assert!(
            !text.contains("/atom/var/density"),
            "BYOND's own vars are never declared: {}",
            text
        );
        assert!(text.contains("/mob/living/var/stun = null //"), "{}", text);
        assert!(text.contains("/obj/machinery/proc/__stat_operable()\n\treturn list(\"operable\", \"ALL\", list(id = STAT_OPERABLE))"), "{}", text);
        assert!(
            text.contains("list(id = STAT_STUN, units = LIFE_CYCLE, reapply = REAPPLY_MAX)"),
            "{}",
            text
        );
        assert!(text.contains("/datum/stat_decl/obj/machinery/__operable/spec()\n\treturn list(/obj/machinery, /obj/machinery/proc/__stat_operable)"), "{}", text);
    }

    #[test]
    fn a_virtual_stat_declares_no_var_and_hides_the_option() {
        let text = gen(vec![(
            "code/a.dm",
            "STAT(/obj/machinery, operable, ALL, virtual = TRUE)
",
        )]);
        assert!(!text.contains("/var/operable"), "{}", text);
        assert!(text.contains("list(id = STAT_OPERABLE))"), "{}", text);
    }

    #[test]
    fn a_var_the_type_already_declares_is_used_not_redeclared() {
        let text = gen(vec![
            ("code/a.dm", "/obj/machinery\n\tvar/operable = 1\n"),
            (
                "code/b.dm",
                "STAT(/obj/machinery/pump, operable, ALL)\nSTAT(/obj/other, light_range, MAX)\n",
            ),
        ]);
        assert!(
            !text.contains("/obj/machinery/pump/var/operable"),
            "an ancestor's var is the stat's var: {}",
            text
        );
        assert!(
            text.contains("/obj/other/var/light_range = null"),
            "{}",
            text
        );
    }

    #[test]
    fn test_fixture_stats_are_guarded() {
        let text = gen(vec![(
            "code/tests/x.dm",
            "STAT(/obj/lamp, lamp_range, MAX)\n",
        )]);
        assert!(text.contains("#if defined(UNIT_TESTS)"), "{}", text);
        assert!(text.contains("/obj/lamp/var/lamp_range = null"));
    }

    #[test]
    fn a_formula_option_is_copied_so_it_resolves_on_the_type() {
        let text = gen(vec![("code/a.dm", "STAT(/obj/apc, charge_percent, FORMULA, formula = PROC_REF(compute_charge_percent), reads = list(\"charge\", \"cell.charge\"))\n")]);
        assert!(text.contains("formula = PROC_REF(compute_charge_percent), reads = list(\"charge\", \"cell.charge\")"), "{}", text);
    }
}

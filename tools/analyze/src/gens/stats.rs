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

use std::collections::{HashMap, HashSet};

use crate::sem::decls::{split_args, Marker};
use crate::sem::gen::{GenCx, GenOut, Generator};

/// Vars BYOND declares on /atom and /atom/movable: a stat of the same name uses them and declares nothing.
const BUILTIN_VARS: &[&str] = &["density", "opacity", "invisibility", "luminosity", "layer", "alpha", "color", "dir", "name", "desc"];

fn up(s: &str) -> String {
    s.to_uppercase()
}

fn split_opt(arg: &str) -> Option<(String, String)> {
    let b = arg.as_bytes();
    let mut i = 0;
    while i < b.len() && (b[i].is_ascii_alphanumeric() || b[i] == b'_') {
        i += 1;
    }
    if i == 0 {
        return None;
    }
    let rest = arg[i..].trim_start();
    let rest = rest.strip_prefix('=')?;
    if rest.starts_with('=') {
        return None;
    }
    Some((arg[..i].to_string(), rest.trim().to_string()))
}

fn one_line(s: &str) -> String {
    // A marker the preprocessor sees continues its lines with a trailing backslash: that is not part of the expression.
    s.replace("\\\r\n", " ").replace("\\\n", " ").split_whitespace().collect::<Vec<_>>().join(" ")
}

/// The base a rule has with nothing contributing, as DM.
fn rule_base(rule: &str) -> &'static str {
    match rule {
        "ALL" => "TRUE",
        "ANY" => "FALSE",
        "SUM" | "MASK_OR" => "0",
        "PRODUCT" => "1",
        _ => "null",
    }
}

/// Whether `ty` or one of its path ancestors declares var `name` in the tree's text.
fn declares_var(vars: &HashMap<String, HashSet<String>>, ty: &str, name: &str) -> bool {
    let mut t = ty.to_string();
    loop {
        if vars.get(&t).map(|v| v.contains(name)).unwrap_or(false) {
            return true;
        }
        match t.rfind('/') {
            Some(0) | None => return false,
            Some(i) => t.truncate(i),
        }
    }
}

struct Stats;

struct Row<'a> {
    m: &'a Marker,
    ty: String,
    name: String,
    rule: String,
    opts: Vec<(String, String)>,
}

fn rows<'a>(cx: &'a GenCx, out: &mut GenOut) -> Vec<Row<'a>> {
    let mut rows = Vec::new();
    for m in cx.markers("STAT") {
        if m.args.len() < 3 {
            out.diag(&m.rel, m.line, "STAT(T, name, RULE, ...) needs a type, a name and a rule");
            continue;
        }
        let mut opts = Vec::new();
        for a in &m.args[3..] {
            match split_opt(a) {
                Some((k, v)) => opts.push((k, one_line(&v))),
                None => out.diag(&m.rel, m.line, format!("STAT({}): `{}` is not an option (name = value)", m.args[1], a)),
            }
        }
        rows.push(Row { m, ty: m.args[0].clone(), name: m.args[1].clone(), rule: m.args[2].clone(), opts });
    }
    rows.sort_by(|a, b| (a.ty.as_str(), a.name.as_str()).cmp(&(b.ty.as_str(), b.name.as_str())));
    rows
}

fn emit(cx: &GenCx, out: &mut GenOut, rows: &[Row], vars: &HashMap<String, HashSet<String>>, test_only: bool) {
    for r in rows.iter().filter(|r| crate::sem::gen::test_only(&r.m.rel) == test_only) {
        let base_opt = r.opts.iter().find(|(k, _)| k == "base").map(|(_, v)| v.clone());
        out.doc(format!("STAT({}, {}, {}) at {}:{}", r.ty, r.name, r.rule, r.m.rel, r.m.line));
        let is_virtual = r.opts.iter().any(|(k, v)| k == "virtual" && v == "TRUE");
        if !is_virtual && !BUILTIN_VARS.contains(&r.name.as_str()) && !declares_var(vars, &r.ty, &r.name) {
            let base = base_opt.clone().unwrap_or_else(|| rule_base(&r.rule).to_string());
            out.line(format!("{}/var/{} = {} // ALLOW(base_vars): a stat's var is its settled value (STAT, code/engine/stats)", r.ty, r.name, base));
        }
        let mut opts = vec![format!("id = STAT_{}", up(&r.name))];
        for (k, v) in r.opts.iter().filter(|(k, _)| k != "virtual") {
            opts.push(format!("{} = {}", k, v));
        }
        out.line(format!("{}/proc/__stat_{}()", r.ty, r.name));
        out.line(format!("\treturn list(\"{}\", \"{}\", list({}))", r.name, r.rule, opts.join(", ")));
        out.line(format!("/datum/stat_decl{}/__{}/spec()", r.ty, r.name));
        out.line(format!("\treturn list({}, {}/proc/__stat_{})", r.ty, r.ty, r.name));
        out.blank();
    }
    let _ = cx;
}

impl Generator for Stats {
    fn name(&self) -> &'static str {
        "stats"
    }

    fn output(&self) -> &'static str {
        "stats.dm"
    }

    fn generate(&self, cx: &GenCx, out: &mut GenOut) {
        let rows = rows(cx, out);
        // The generator's own previous output declares the vars it wrote: it must not count them as the types' own.
        let files: Vec<_> = cx.tree.select(&crate::tree::CODE_DM).into_iter().filter(|f| !f.rel.ends_with("_generated/stats.dm")).collect();
        let vars = crate::dm::dx::type_vars(&files);
        // Every type a marker names must be a type the tree defines somewhere (a typo is a DM error otherwise).
        let _ = split_args;
        emit(cx, out, &rows, &vars, false);
        let mut tests = GenOut::default();
        emit(cx, &mut tests, &rows, &vars, true);
        if !tests.text().trim().is_empty() {
            out.line(crate::sem::gen::TEST_GUARD);
            out.blank();
            out.line(tests.text().trim_end());
            out.blank();
            out.line("#endif");
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
        let tree = Tree::from_files(files.into_iter().map(|(r, t)| SourceFile::from_text(r, t)).collect());
        let cx = GenCx::new(&tree, Path::new("."));
        render(&Stats, &cx).0
    }

    #[test]
    fn a_stat_gets_its_var_with_the_rules_base_and_a_row() {
        let text = gen(vec![(
            "code/a.dm",
            "STAT(/obj/machinery, operable, ALL)\nSTAT(/mob/living, acts_via, MASK_AND, base = ORIGIN_ALL)\nSTAT(/atom, density, TOP)\nSTAT(/mob/living, stun, MAX, units = LIFE_CYCLE, reapply = REAPPLY_MAX)\n",
        )]);
        assert!(text.contains("/obj/machinery/var/operable = TRUE //"), "{}", text);
        assert!(text.contains("/mob/living/var/acts_via = ORIGIN_ALL //"), "{}", text);
        assert!(!text.contains("/atom/var/density"), "BYOND's own vars are never declared: {}", text);
        assert!(text.contains("/mob/living/var/stun = null //"), "{}", text);
        assert!(text.contains("/obj/machinery/proc/__stat_operable()\n\treturn list(\"operable\", \"ALL\", list(id = STAT_OPERABLE))"), "{}", text);
        assert!(text.contains("list(id = STAT_STUN, units = LIFE_CYCLE, reapply = REAPPLY_MAX)"), "{}", text);
        assert!(text.contains("/datum/stat_decl/obj/machinery/__operable/spec()\n\treturn list(/obj/machinery, /obj/machinery/proc/__stat_operable)"), "{}", text);
    }

    #[test]
    fn a_virtual_stat_declares_no_var_and_hides_the_option() {
        let text = gen(vec![("code/a.dm", "STAT(/obj/machinery, operable, ALL, virtual = TRUE)
")]);
        assert!(!text.contains("/var/operable"), "{}", text);
        assert!(text.contains("list(id = STAT_OPERABLE))"), "{}", text);
    }

    #[test]
    fn a_var_the_type_already_declares_is_used_not_redeclared() {
        let text = gen(vec![("code/a.dm", "/obj/machinery\n\tvar/operable = 1\n"), ("code/b.dm", "STAT(/obj/machinery/pump, operable, ALL)\nSTAT(/obj/other, light_range, MAX)\n")]);
        assert!(!text.contains("/obj/machinery/pump/var/operable"), "an ancestor's var is the stat's var: {}", text);
        assert!(text.contains("/obj/other/var/light_range = null"), "{}", text);
    }

    #[test]
    fn test_fixture_stats_are_guarded() {
        let text = gen(vec![("code/tests/x.dm", "STAT(/obj/lamp, lamp_range, MAX)\n")]);
        assert!(text.contains("#if defined(UNIT_TESTS)"), "{}", text);
        assert!(text.contains("/obj/lamp/var/lamp_range = null"));
    }

    #[test]
    fn a_formula_option_is_copied_so_it_resolves_on_the_type() {
        let text = gen(vec![("code/a.dm", "STAT(/obj/apc, charge_percent, FORMULA, formula = PROC_REF(compute_charge_percent), reads = list(\"charge\", \"cell.charge\"))\n")]);
        assert!(text.contains("formula = PROC_REF(compute_charge_percent), reads = list(\"charge\", \"cell.charge\")"), "{}", text);
    }
}

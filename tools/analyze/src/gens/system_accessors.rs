//! `analyze gen system_accessors` -> `code/engine/_generated/system_accessors.dm`.
//!
//! `SYSTEM_ACCESSOR(system, name, nameof(var))` (declared in `code/contracts/accessors/`) is the
//! only way content reads a system's private state. This emits the accessor proc:
//! `name()` returns `var` of the system's singleton, so a call is a plain typed read, and the
//! reads engine follows a call of it to that var (`ReadKind::System`), which is how a stat that
//! calls `night_shift_active()` is marked when `night` changes. A fourth argument, a type path, makes the accessor typed:
//! `SYSTEM_ACCESSOR(ticker, round_mode, nameof(mode), /datum/game_mode)` emits `/proc/round_mode() as /datum/game_mode`, so a
//! caller reads a field through it (`round_mode().name`) where the system's var held an object.

use std::collections::HashSet;

use crate::sem::gen::{system_types, system_vars, GenCx, GenOut, Generator, SYSTEM_INSTANCE};

struct SystemAccessors;

impl Generator for SystemAccessors {
    fn name(&self) -> &'static str {
        "system_accessors"
    }

    fn output(&self) -> &'static str {
        "system_accessors.dm"
    }

    fn generate(&self, cx: &GenCx, out: &mut GenOut) {
        // A system declared with SYSTEM_DEF(x) is read through its `SSx` global; a legacy world service through its GLOB var.
        let sys_def = crate::pat!(r"(?m)^\s*SYSTEM_DEF\((\w+)\)");
        let mut sys_defs: HashSet<String> = HashSet::new();
        for f in cx.tree.select(&crate::tree::CODE_DM) {
            if !f.text().contains("SYSTEM_DEF(") {
                continue;
            }
            for c in sys_def.captures_iter(f.text()) {
                sys_defs.insert(c.s(1).to_string());
            }
        }
        let instance = |system: &str| -> String {
            if sys_defs.contains(system) {
                format!("SS{}", system)
            } else {
                SYSTEM_INSTANCE.replace("{system}", system)
            }
        };
        let mut rows: Vec<(String, String, String, String, u32, Option<String>)> = Vec::new();
        for m in cx.markers("SYSTEM_ACCESSOR") {
            let (Some(system), Some(name), Some(key)) = (m.args.first(), m.args.get(1), m.args.get(2)) else {
                out.diag(&m.rel, m.line, "SYSTEM_ACCESSOR(system, name, nameof(var)) needs three arguments");
                continue;
            };
            let Some(var) = key.trim().strip_prefix("nameof(").and_then(|s| s.strip_suffix(')')).map(|s| s.trim().to_string()) else {
                out.diag(&m.rel, m.line, format!("accessor `{}`: the third argument is nameof(var), not `{}`", name, key));
                continue;
            };
            let (_, vars) = system_vars(cx.tree, system);
            if !vars.contains(&var) {
                out.diag(&m.rel, m.line, format!("accessor `{}`: system `{}` has no var `{}` (looked at {})", name, system, var, system_types(system).join(", ")));
                continue;
            }
            let typed = match m.args.get(3).map(|t| t.trim().to_string()) {
                None => None,
                Some(t) if t.starts_with('/') && t[1..].chars().all(|c| c.is_alphanumeric() || c == '_' || c == '/') => Some(t),
                Some(t) => {
                    out.diag(&m.rel, m.line, format!("accessor `{}`: the fourth argument is the var's type path, not `{}`", name, t));
                    continue;
                }
            };
            rows.push((name.clone(), system.clone(), var, m.rel.clone(), m.line, typed));
        }
        rows.sort();
        for w in rows.windows(2) {
            if w[0].0 == w[1].0 {
                out.diag(&w[1].3, w[1].4, format!("accessor `{}` is declared twice (also {}:{})", w[0].0, w[0].3, w[0].4));
            }
        }
        rows.dedup_by(|a, b| a.0 == b.0);
        // An accessor declared in a test-only file (`test_only`) exists only in a test build.
        let (tests, content): (Vec<_>, Vec<_>) = rows.into_iter().partition(|r| crate::sem::gen::test_only(&r.3));
        let emit = |out: &mut GenOut, rows: Vec<(String, String, String, String, u32, Option<String>)>| {
            for (name, system, var, rel, line, typed) in rows {
                match &typed {
                    Some(t) => {
                        out.doc(format!("SYSTEM_ACCESSOR({}, {}, nameof({}), {}) at {}:{}: the {} system's `{}`, read as a typed var.", system, name, var, t, rel, line, system, var));
                        out.line(format!("/proc/{}() as {}", name, t));
                        out.line(format!("	RETURN_TYPE({})", t));
                    }
                    None => {
                        out.doc(format!("SYSTEM_ACCESSOR({}, {}, nameof({})) at {}:{}: the {} system's `{}`, read as a plain var.", system, name, var, rel, line, system, var));
                        out.line(format!("/proc/{}()", name));
                    }
                }
                out.line(format!("	return {}?.{}", instance(&system), var));
                out.blank();
            }
        };
        emit(out, content);
        if !tests.is_empty() {
            out.line(crate::sem::gen::TEST_GUARD);
            out.blank();
            emit(out, tests);
            out.line("#endif");
        }
    }
}

pub fn register(reg: &mut Vec<Box<dyn Generator>>) {
    reg.push(Box::new(SystemAccessors));
}

//! `analyze gen system_accessors` -> `code/engine/_generated/system_accessors.dm`.
//!
//! `SYSTEM_ACCESSOR(system, name, nameof(var))` (declared in `code/contracts/accessors/`) is the
//! only way content reads a system's private state. This emits the accessor proc:
//! `name()` returns `var` of the system's singleton, so a call is a plain typed read, and the
//! reads engine follows a call of it to that var (`ReadKind::System`), which is how a stat that
//! calls `night_shift_active()` is marked when `night` changes.

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
        let mut rows: Vec<(String, String, String, String, u32)> = Vec::new();
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
            rows.push((name.clone(), system.clone(), var, m.rel.clone(), m.line));
        }
        rows.sort();
        for w in rows.windows(2) {
            if w[0].0 == w[1].0 {
                out.diag(&w[1].3, w[1].4, format!("accessor `{}` is declared twice (also {}:{})", w[0].0, w[0].3, w[0].4));
            }
        }
        rows.dedup_by(|a, b| a.0 == b.0);
        // An accessor declared in a test fixture (code/tests/) exists only in a test build.
        let (tests, content): (Vec<_>, Vec<_>) = rows.into_iter().partition(|r| r.3.starts_with("code/tests/"));
        let emit = |out: &mut GenOut, rows: Vec<(String, String, String, String, u32)>| {
            for (name, system, var, rel, line) in rows {
                out.doc(format!("SYSTEM_ACCESSOR({}, {}, nameof({})) at {}:{}: the {} system's `{}`, read as a plain var.", system, name, var, rel, line, system, var));
                out.line(format!("/proc/{}()", name));
                out.line(format!("\treturn {}.{}", instance(&system), var));
                out.blank();
            }
        };
        emit(out, content);
        if !tests.is_empty() {
            out.line("#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)");
            out.blank();
            emit(out, tests);
            out.line("#endif");
        }
    }
}

pub fn register(reg: &mut Vec<Box<dyn Generator>>) {
    reg.push(Box::new(SystemAccessors));
}

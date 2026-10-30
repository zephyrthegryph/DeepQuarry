//! `analyze gen system_accessors` -> `code/engine/_generated/system_accessors.dm`.
//!
//! `SYSTEM_ACCESSOR(system, name, nameof(var))` (declared in `code/contracts/accessors/`) is the
//! only way content reads a system's private state. This emits the accessor proc:
//! `name()` returns `var` of the system's singleton, so a call is a plain typed read, and the
//! reads engine follows a call of it to that var (`ReadKind::System`), which is how a stat that
//! calls `night_shift_active()` is marked when `night` changes. A fourth argument, a type path, makes the accessor typed:
//! `SYSTEM_ACCESSOR(ticker, ticker_mode, nameof(mode), /datum/game_mode)` emits `/proc/ticker_mode() as /datum/game_mode`, so a
//! caller reads a field through it (`ticker_mode().name`) where the system's var held an object.

use std::collections::HashSet;

use crate::sem::gen::{system_vars, GenCx, GenOut, Generator};

struct SystemAccessors;

impl Generator for SystemAccessors {
    fn name(&self) -> &'static str {
        "system_accessors"
    }

    fn output(&self) -> &'static str {
        "system_accessors.dm"
    }

    fn generate(&self, cx: &GenCx, out: &mut GenOut) {
        let files = cx.tree.select(&crate::tree::CODE_DM);
        let per: Vec<Vec<String>> = crate::incr::facts("gen-system-defs", &files, |f| {
            crate::system_accessors_policy::system_defs(f.text())
        });
        let defs: HashSet<String> = per.into_iter().flatten().collect();
        let mut builder = crate::system_accessors_policy::Builder::new(defs);
        for m in cx.markers("SYSTEM_ACCESSOR") {
            builder.push(&m.rel, m.line, &m.args, |system, var| {
                system_vars(cx.tree, system).1.contains(var)
            });
        }
        let generated = builder.finish();
        for diagnostic in generated.diags {
            out.diag(&diagnostic.rel, diagnostic.line, diagnostic.msg);
        }
        for line in generated.body.split_terminator('\n') {
            out.line(line);
        }
    }
}

pub fn register(reg: &mut Vec<Box<dyn Generator>>) {
    reg.push(Box::new(SystemAccessors));
}

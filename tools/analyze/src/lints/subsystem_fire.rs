//! Port of `tools/ci/subsystem_fire_lint.py` (K4, doc/rewrite/archive/completion_plan.md sec 3.6).
//!
//! The MC is a thin kernel; periodic gameplay work is a lane on the OM global owner or a behaviour,
//! never a new subsystem `fire()` loop. Fails on any `/datum/controller/subsystem/<name>[/...]/fire(`
//! definition whose `<name>` is not in the core list (`lint_scopes.toml`, `core`), unless the line or
//! the comment line above carries `// ALLOW(subsystem_fire): <reason>`. A `proc` name (the base proc
//! on `/datum/controller/subsystem`) is skipped. The `--report` listing of allowed fires is not
//! reproduced (it is not a finding).

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::parity::{ParseKind, Parity};
use crate::tree::{SourceFile, CODE_DM};

const HINT: &str = "move the periodic work onto an OM lane (world service or feature lane, code/datums/om/world_lanes.dm) or, for a kernel engine, add it to `core` in tools/ci/lint_scopes.toml; a temporary keep takes `// ALLOW(subsystem_fire): <reason>`";

static META: Meta = Meta {
    name: "subsystem_fire",
    group: "",
    label: "subsystem_fire",
    legacy: "tools/ci/subsystem_fire_lint.py",
    select: CODE_DM,
    scan: ScanKind::File,
    policy: Policy::Hard,
    rules: &[RuleMeta { name: "fire", hint: HINT }],
    allow: &["subsystem_fire"],
    lists: &["core"],
};

struct SubsystemFire;

impl Lint for SubsystemFire {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_file(&self, cx: &Cx, f: &SourceFile, out: &mut Sink) {
        let fire = crate::pat_match!(r"/datum/controller/subsystem/(\w+)(?:/\w+)*/fire\(");
        let core = cx.list("core");
        for (number, line) in f.raw().numbered() {
            let Some(m) = fire.captures(line) else { continue };
            let name = m.s(1);
            if name == "proc" {
                continue;
            }
            let ok = core.iter().any(|c| c == name) || out.allowed(f, number, "subsystem_fire");
            if !ok {
                out.site_msg("fire", number, format!("SS{} has a fire() outside the core allowlist", name));
            }
        }
    }

    fn parity(&self) -> Option<Parity> {
        Some(Parity {
            old: &["tools/ci/subsystem_fire_lint.py"],
            old_raw: &[],
            blank: &[],
            parse: ParseKind::FileLineAny,
            update: None,
            seed: None,
            files: &[],
            selftest: None,
        })
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(SubsystemFire);
}

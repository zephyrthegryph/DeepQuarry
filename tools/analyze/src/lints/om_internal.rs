//! Port of `tools/ci/om_internal_lint.py`: object-model internal time mechanisms
//! (doc/rewrite/time_mechanisms.md).
//!
//! The machinery under `om_after*()` / `om_deadline()` / `om_task*()` is named `_om_*` and is
//! internal to the scheduler core. Any `_om_*` name used outside `code/datums/om/` and
//! `code/__defines/om.dm` (the lint's exempt prefixes in `lint_scopes.toml`) fails unless the line
//! carries `// ALLOW(om_internal): <reason>`. No baseline.

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::parity::{ParseKind, Parity};
use crate::pat;
use crate::tree::{SourceFile, CODE_MAPS_DM};
use crate::util::before_slashes;

static META: Meta = Meta {
    name: "om_internal",
    group: "",
    label: "om_internal",
    legacy: "tools/ci/om_internal_lint.py",
    select: CODE_MAPS_DM,
    scan: ScanKind::File,
    policy: Policy::Hard,
    rules: &[RuleMeta { name: "internal", hint: "use om_after / om_deadline / om_task_*" }],
    allow: &["om_internal"],
    lists: &[],
};

struct OmInternal;

impl Lint for OmInternal {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_file(&self, _cx: &Cx, f: &SourceFile, out: &mut Sink) {
        // The Python skipped a file with no `_om_` in it before splitting lines.
        if !f.text().contains("_om_") {
            return;
        }
        for (number, line) in f.raw().numbered() {
            let code = before_slashes(line);
            if let Some(m) = pat!(r"(?<![\w])_om_\w+").find(code) {
                if !out.allowed(f, number, "om_internal") {
                    out.site_msg("internal", number, format!("{} is internal to the OM scheduler: use om_after / om_deadline / om_task_*", m.as_str()));
                }
            }
        }
    }

    fn parity(&self) -> Option<Parity> {
        Some(Parity {
            old: &["tools/ci/om_internal_lint.py"],
            old_raw: &[&["tools/ci/om_internal_lint.py"]],
            blank: &[],
            parse: ParseKind::FileLine,
            update: None,
            seed: None,
            files: &[],
            selftest: None,
        })
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(OmInternal);
}

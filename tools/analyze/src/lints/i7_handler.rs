//! Port of `tools/ci/i7_handler_lint.py` (I7, doc/rewrite/interactions.md sec 13).
//!
//! No legacy input-handler overrides anywhere: `attackby`, `attack_hand`, `attack_self`, `click_alt`
//! and `MouseDrop_T` are thin dispatchers into the resolver defined once in code/_onclick/, and a
//! type declares what it does with an input as interactions. Fails on any other definition of them.
//! The dispatchers themselves (`allowed`) and `code/modules/unit_tests/` are in `lint_scopes.toml`.
//!
//! Quirk kept from the Python: the pattern runs over the whole raw text with `re.M` (not per line),
//! on any line start; the type path may contain spaces. The comment and string content are not
//! stripped, so a definition-shaped line in a comment or string at column 0 counts.

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::parity::{ParseKind, Parity};
use crate::tree::{Select, SourceFile};

const HINT: &str = "declare interactions instead (DECLARE_INTERACTIONS / EXTEND_INTERACTIONS, code/__defines/interactions.dm)";

static META: Meta = Meta {
    name: "i7_handler",
    group: "",
    label: "i7_handler",
    legacy: "tools/ci/i7_handler_lint.py",
    // pathlib rglob: dot-files and dot-directories included.
    select: Select { roots: &[("code", "dm")], hidden: true },
    scan: ScanKind::File,
    policy: Policy::Hard,
    rules: &[RuleMeta { name: "handler_override", hint: HINT }],
    allow: &[],
    lists: &["allowed"],
};

struct I7Handler;

impl Lint for I7Handler {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_file(&self, cx: &Cx, f: &SourceFile, out: &mut Sink) {
        let handler = crate::pat!(r"(?m)^(/\w[\w/ ]*?)/(attackby|attack_hand|attack_self|click_alt|MouseDrop_T)\(");
        let allowed = cx.list("allowed");
        let text = f.text();
        for m in handler.captures_iter(text) {
            let name = format!("{}/{}", m.s(1), m.s(2));
            if allowed.iter().any(|a| *a == name) {
                continue;
            }
            let line = f.raw().line_of(m.start(0));
            out.site_msg("handler_override", line, name);
        }
    }

    fn parity(&self) -> Option<Parity> {
        Some(Parity {
            old: &["tools/ci/i7_handler_lint.py"],
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
    reg.add(I7Handler);
}

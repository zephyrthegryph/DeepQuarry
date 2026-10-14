//! Port of `tools/ci/actor_forwarding_lint.py` (I3, doc/rewrite/interactions.md section 4).
//!
//! `attack_ai` / `attack_robot` / `attack_ghost` / `attack_tk` are gone: the AI, cyborgs, ghosts and
//! telekinesis reach an atom through their capability adapter. Any definition or call fails.
//! Matched on the raw text up to the first `//` (so a string holding `//` hides the rest of the line).

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::parity::{ParseKind, Parity};
use crate::tree::{Select, SourceFile};
use crate::util::{before_slashes, py_strip};

const HINT: &str = "attack_ai/attack_robot/attack_ghost/attack_tk are gone: declare an INTERACT_SILICON / INTERACT_ROBOT / INTERACT_OBSERVER / INTERACT_TK interaction, or set silicon_use";

static META: Meta = Meta {
    name: "actor_forwarding",
    group: "",
    label: "actor_forwarding",
    legacy: "tools/ci/actor_forwarding_lint.py",
    // os.walk: dot-files and dot-directories included.
    select: Select { roots: &[("code", "dm")], hidden: true },
    scan: ScanKind::File,
    policy: Policy::Hard,
    rules: &[RuleMeta { name: "attack_proc", hint: HINT }],
    allow: &[],
    lists: &[],
};

struct ActorForwarding;

impl Lint for ActorForwarding {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_file(&self, _cx: &Cx, f: &SourceFile, out: &mut Sink) {
        let pattern = crate::pat!(r"\battack_(ai|robot|ghost|tk)\(");
        for (number, line) in f.raw().numbered() {
            if pattern.is_match(before_slashes(line)) {
                out.site_msg("attack_proc", number, py_strip(line));
            }
        }
    }

    fn parity(&self) -> Option<Parity> {
        Some(Parity {
            old: &["tools/ci/actor_forwarding_lint.py"],
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
    reg.add(ActorForwarding);
}

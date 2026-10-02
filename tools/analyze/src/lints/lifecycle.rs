//! Port of `tools/ci/lifecycle_lint.py` (roadmap L2, doc/rewrite/state.md sections 6 and 10).
//!
//! `Initialize()` sets up an object's own state; registering with the world belongs in
//! `on_materialize()`. For every latent-safe type, and every ancestor whose `Initialize()` such a
//! type runs, this rejects global list writes, processing starts, global signal registration and
//! radio joins inside `Initialize()`. (`lifecycle_counts_lint.py` is a different lint.)

use std::collections::HashSet;

use crate::dm::schema::{chain, Schema};
use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::parity::{ParseKind, Parity};
use crate::pat::Pat;
use crate::pat_match;
use crate::tree::{View, CODE_DM};
use crate::util::py_strip;

const HINT: &str = "move it to on_materialize() and undo it in on_dematerialize()";

static META: Meta = Meta {
    name: "lifecycle",
    group: "",
    label: "lifecycle",
    legacy: "tools/ci/lifecycle_lint.py",
    select: CODE_DM,
    scan: ScanKind::Tree,
    policy: Policy::Hard,
    rules: &[
        RuleMeta { name: "global_list_write", hint: HINT },
        RuleMeta { name: "processing_start", hint: HINT },
        RuleMeta { name: "global_signal_registration", hint: HINT },
        RuleMeta { name: "radio_join", hint: HINT },
    ],
    allow: &[],
    lists: &[],
};

/// Not latent-safe yet, but registering only in `on_materialize()` (L3). Keep in step with
/// `GLOB.dq_lifecycle_clean_types` in dq_lifecycle_tests.dm.
const CLEAN_TYPES: &[&str] = &[
    "/obj/item/pda",
    "/obj/item/radio",
    "/obj/item/gps",
    "/obj/item/implant/tracking",
    "/obj/item/card/id",
    "/obj/item/card/id/guest",
];

struct Lifecycle {
    /// (rule, label printed in the message, pattern)
    forbidden: Vec<(&'static str, &'static str, Pat)>,
}

impl Lifecycle {
    fn new() -> Lifecycle {
        Lifecycle {
            forbidden: vec![
                (
                    "global_list_write",
                    "global list write",
                    Pat::new(
                        r"\bGLOB\.\w+\s*(?:\+=|-=|\|=|&=|\^=)|\bGLOB\.\w+\s*\[[^\]]*\]\s*=(?!=)|\bGLOB\.\w+\.(?:Add|Remove|Insert|Cut|Swap)\(",
                    ),
                ),
                ("processing_start", "processing start", Pat::new(r"\bSTART_PROCESSING\w*\(")),
                ("global_signal_registration", "global signal registration", Pat::new(r"\bRegisterSignal\(\s*SSdcs\b")),
                ("radio_join", "radio join", Pat::new(r"\bGLOB\.radio_service\.add_object\(|\bset_frequency\(")),
            ],
        }
    }
}

/// `initialize_bodies`: `(type, head line, body lines with their numbers)` for every top-level
/// `Initialize()` definition. A body is the blank or indented lines after the head.
fn initialize_bodies<'a>(code: &'a View) -> Vec<(String, usize, Vec<(usize, &'a str)>)> {
    let head = pat_match!(r"^(/[\w/]+?)/(?:proc/)?Initialize\(");
    let n = code.num_lines();
    let mut out = Vec::new();
    let mut i = 1usize; // 1-based line number of lines[i]
    while i <= n {
        let Some(m) = head.captures(code.line(i)) else {
            i += 1;
            continue;
        };
        let start = i;
        let mut body = Vec::new();
        i += 1;
        while i <= n {
            let l = code.line(i);
            if py_strip(l).is_empty() || matches!(l.chars().next(), Some(' ') | Some('\t')) {
                body.push((i, l));
                i += 1;
            } else {
                break;
            }
        }
        out.push((m.s(1).to_string(), start, body));
    }
    out
}

impl Lint for Lifecycle {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        let all = cx.all_files();
        let schema = Schema::get(cx.tree, &all);
        // An ancestor's Initialize() runs for every latent-safe descendant.
        let mut ancestors: HashSet<String> = HashSet::new();
        for t in schema.latent.keys() {
            if schema.effective_latent(t) {
                ancestors.extend(chain(t));
            }
        }
        for t in CLEAN_TYPES {
            ancestors.extend(chain(t));
        }

        let mut checked = 0usize;
        let mut problems = 0usize;
        for f in cx.files() {
            let code = f.code();
            if !code.text.contains("Initialize(") {
                continue;
            }
            for (owner, _line, body) in initialize_bodies(code) {
                if !ancestors.contains(&owner) && !schema.effective_latent(&owner) {
                    continue;
                }
                checked += 1;
                for (number, source) in body {
                    for (rule, label, pattern) in &self.forbidden {
                        if pattern.is_match(source) {
                            problems += 1;
                            out.site_in_msg(rule, &f.rel, number, format!("{} in {}/Initialize()", label, owner));
                        }
                    }
                }
            }
        }
        out.note(format!(
            "lifecycle lint: {} Initialize() procs on latent-safe types and their ancestors, {} problems",
            checked, problems
        ));
    }

    fn parity(&self) -> Option<Parity> {
        Some(Parity {
            old: &["tools/ci/lifecycle_lint.py"],
            old_raw: &[],
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
    reg.add(Lifecycle::new());
}

//! Port of `tools/ci/interactions_lint.py`: DECLARE_INTERACTIONS shadowing
//! (doc/rewrite/interactions.md sec 5a).
//!
//! `DECLARE_INTERACTIONS(T, ...)` generates `T/get_interactions()`, which REPLACES every ancestor's
//! specs. This fails on any `DECLARE_INTERACTIONS` (or hand-written `get_interactions()` override)
//! on a type whose ancestor also declares, unless the site carries
//! `// ALLOW(interactions): <reason>`. Ancestry is by type path.
//!
//! Quirks kept: a type declared in two places keeps only the LAST one seen (files in path order);
//! the nearest declaring ancestor decides, and an annotated site still stops the walk up; the
//! annotation is read on every declaring line, whether or not that site survives the overwrite.

use std::collections::BTreeMap;

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::parity::{ParseKind, Parity};
use crate::pat;
use crate::tree::CODE_DM;

static META: Meta = Meta {
    name: "interactions",
    group: "",
    label: "interactions",
    legacy: "tools/ci/interactions_lint.py",
    select: CODE_DM,
    scan: ScanKind::Tree,
    policy: Policy::Hard,
    rules: &[RuleMeta {
        name: "shadow",
        hint: "use EXTEND_INTERACTIONS, or annotate `// ALLOW(interactions): reason`",
    }],
    allow: &["interactions"],
    lists: &[],
};

struct Interactions;

impl Lint for Interactions {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        // type path -> (rel, line, allowed)
        let mut sites: BTreeMap<String, (String, usize, bool)> = BTreeMap::new();
        for f in cx.files() {
            for (number, line) in f.raw().numbered() {
                let m = pat!(r"^\s*DECLARE_INTERACTIONS\(\s*(/[\w/]+)")
                    .captures(line)
                    .or_else(|| pat!(r"^(/[\w/]+)/get_interactions\(\)").captures(line));
                if let Some(m) = m {
                    let ok = out.allowed(f, number, "interactions");
                    sites.insert(m.s(1).to_string(), (f.rel.clone(), number, ok));
                }
            }
        }
        let mut bad = 0;
        for (path, (rel, number, ok)) in &sites {
            let parts: Vec<&str> = path.split('/').collect();
            let mut cut = parts.len() as i64 - 1;
            while cut > 1 {
                let ancestor = parts[..cut as usize].join("/");
                if let Some((arel, anum, _)) = sites.get(&ancestor) {
                    if !ok {
                        bad += 1;
                        out.site_in_msg(
                            "shadow",
                            rel,
                            *number,
                            format!(
                                "DECLARE_INTERACTIONS({}) discards {}'s specs ({}:{}): use EXTEND_INTERACTIONS, or annotate `// ALLOW(interactions): reason`",
                                path, ancestor, arel, anum
                            ),
                        );
                    }
                    break;
                }
                cut -= 1;
            }
        }
        out.note(format!("interactions_lint: {} declaring types, {} unannotated shadowing sites", sites.len(), bad));
    }

    fn parity(&self) -> Option<Parity> {
        Some(Parity {
            old: &["tools/ci/interactions_lint.py"],
            old_raw: &[&["tools/ci/interactions_lint.py"]],
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
    reg.add(Interactions);
}

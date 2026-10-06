//! Port of `tools/ci/qdel_src_lint.py`: the raw `qdel(src)` ratchet (unified plan sec 2.18,
//! doc/rewrite/lifecycle.md sec 5).
//!
//! A thing that deletes itself says why through a verb (`consume()`, `replace_with()`, `expire()`,
//! `slot_clear()`), not through the engine call. This is the `qdel(src)` slice of the `qdel(` ratchet
//! (`lifecycle_counts` counts every other `qdel(` and leaves `qdel(src)` to this lint), over the
//! `code_only` view of every `.dm` under `code/` and `maps/`. A site kept by
//! `// ALLOW(lifecycle): <reason>` does not count; the exemptions are in `lint_scopes.toml`.
//!
//! Quirks kept: one site per line however many `qdel(src)` it holds (`search`, not `finditer`); the
//! ALLOW name is `lifecycle`, shared with `lifecycle_counts`.

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::parity::{ParseKind, Parity};
use crate::pat::Pat;
use crate::tree::{SourceFile, CODE_MAPS_DM};

static META: Meta = Meta {
    name: "qdel_src",
    group: "",
    label: "qdel_src",
    legacy: "tools/ci/qdel_src_lint.py",
    select: CODE_MAPS_DM,
    scan: ScanKind::File,
    policy: Policy::Sites {
        baseline: "tools/ci/qdel_src_baseline.txt",
        header: &[
            "Raw qdel(src) sites (unified plan sec 2.18). rule<TAB>file<TAB>normalized line.",
            "tools/ci/qdel_src_lint.py fails on a site not listed here. A site with",
            "`// ALLOW(lifecycle): <reason>` doesn't count.",
            "Shrink-only: after a sweep, `python tools/ci/qdel_src_lint.py --update`.",
        ],
        banned: &["qdel_src"],
    },
    rules: &[RuleMeta {
        name: "qdel_src",
        hint: "say why the thing ends: consume() / replace_with() / expire() / slot_clear() / ledger_empty() (code/datums/lifecycle/verbs.dm); a real destroy-now keeps qdel(src) with `// ALLOW(lifecycle): <reason>`",
    }],
    allow: &["lifecycle"],
    lists: &[],
};

struct QdelSrc {
    /// `qdel(src)` and `qdel(src, force = TRUE)`, but not `qdel(src.thing)` or `foo.qdel(src)`.
    qdel_src: Pat,
}

impl Lint for QdelSrc {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_file(&self, _cx: &Cx, f: &SourceFile, out: &mut Sink) {
        for (no, line) in f.code().numbered() {
            if line.contains("qdel") && self.qdel_src.is_match(line) && !out.allowed(f, no, "lifecycle") {
                out.site("qdel_src", no);
            }
        }
    }

    fn parity(&self) -> Option<Parity> {
        Some(Parity {
            old: &["tools/ci/qdel_src_lint.py"],
            old_raw: &[],
            blank: &["tools/ci/qdel_src_baseline.txt"],
            // Some paths hold spaces (the tagged parse stops at a space).
            parse: ParseKind::FileLineAny,
            update: Some(&["tools/ci/qdel_src_lint.py", "--update"]),
            seed: Some(&["tools/ci/qdel_src_lint.py", "--seed"]),
            files: &["tools/ci/qdel_src_baseline.txt"],
            selftest: None,
        })
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(QdelSrc { qdel_src: Pat::new(r"(?<![\w.])qdel\s*\(\s*src\s*[,)]") });
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tree::Tree;

    #[test]
    fn allow_is_asked_only_for_a_qdel_src_line() {
        let tree = Tree::from_files(vec![]);
        let scope = crate::scopes::LintScope::default();
        let cx = Cx { tree: &tree, meta: &META, scope: &scope };
        let f = SourceFile::from_text(
            "code/a.dm",
            "qdel(src) qdel(src) // ALLOW(lifecycle): the grenade must vanish this instant\nqdel(src) qdel(src)\nqdel(M) // ALLOW(lifecycle): that is another lint's site, not this one\n",
        );
        let mut out = Sink::new();
        out.cur = f.rel.clone();
        let mut reg = Registry::default();
        register(&mut reg);
        reg.lints[0].scan_file(&cx, &f, &mut out);
        let lines: Vec<u32> = out.sites.iter().map(|s| s.line).collect();
        assert_eq!(lines, vec![2], "one site per line, however many qdel(src) it holds");
        assert_eq!(out.allow_used.len(), 1);
    }
}

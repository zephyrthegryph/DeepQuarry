//! Port of `tools/ci/lifecycle_counts_lint.py`: the `Destroy()` override ban and the `qdel(` ratchet
//! (roadmap L4, doc/rewrite/lifecycle.md).
//!
//! Two kinds of site, both on the `code_only` view of every `.dm` under `code/` and `maps/`:
//!   * `destroy`: a `Destroy()` override (`/type/Destroy(` at the start of a line) outside the core
//!     chain. Banned outright: no baseline, no ALLOW, and no path exemption (unit tests are checked).
//!   * `qdel`: a `qdel(` call that is not `qdel(src)` (that slice belongs to `qdel_src`), kept by
//!     `// ALLOW(lifecycle): <reason>` or by the fingerprint baseline.
//!
//! The qdel exemptions (`exempt_prefixes` / `exempt_files` in `[lint.lifecycle_counts.lists]`) are lists,
//! not `exempt_*` keys, because an exempt file is still scanned for Destroy() overrides.
//!
//! Quirks kept: the stripped line is `str.strip()`ped before either pattern runs; the ALLOW question
//! is asked once per `qdel(` match on a line and a hit ends the line (so a kept line counts nothing,
//! an unkept line counts every match); `Destroy` matching ignores comments but not preprocessor lines.

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::parity::{ParseKind, Parity};
use crate::pat::Pat;
use crate::pat_match;
use crate::tree::{SourceFile, CODE_MAPS_DM};
use crate::util::{py_strip, starts_with_any};

const DESTROY_HINT: &str = "Destroy() overrides are banned outside the core chain; use DECLARE_REF declarations, a phase hook, on_destroy(), destroy_hint or lifecycle_keep() (code/datums/lifecycle/transaction.dm)";
const QDEL_HINT: &str = "use consume()/replace_with()/expire()/slot_clear()/ledger_empty()/delete_on_death (code/datums/lifecycle/verbs.dm)";

static META: Meta = Meta {
    name: "lifecycle_counts",
    group: "",
    label: "lifecycle",
    legacy: "tools/ci/lifecycle_counts_lint.py",
    select: CODE_MAPS_DM,
    scan: ScanKind::File,
    policy: Policy::Sites {
        baseline: "tools/ci/lifecycle_counts_baseline.txt",
        header: &[
            "qdel( sites (roadmap L4, doc/rewrite/lifecycle.md sec 1, sec 8). rule<TAB>file<TAB>normalized line.",
            "tools/ci/lifecycle_counts_lint.py fails on a site not listed here (Destroy() overrides are",
            "banned outright). A site with `// ALLOW(lifecycle): <reason>` doesn't count.",
            "Shrink-only: after a sweep, `python tools/ci/lifecycle_counts_lint.py --update`.",
        ],
        banned: &["destroy"],
    },
    rules: &[RuleMeta { name: "destroy", hint: DESTROY_HINT }, RuleMeta { name: "qdel", hint: QDEL_HINT }],
    allow: &["lifecycle"],
    lists: &["exempt_prefixes", "exempt_files"],
};

/// The core `Destroy()` chain phase 7 calls after `on_destroy()`; nothing else may override it.
/// `/datum/proc` is `/datum`'s own definition.
const CORE_DESTROY_OWNERS: &[&str] = &["/datum/proc", "/datum", "/atom", "/atom/movable", "/client"];
const CORE_DESTROY_PREFIXES: &[&str] = &["/datum/controller"];

fn core_destroy_owner(owner: &str) -> bool {
    CORE_DESTROY_OWNERS.contains(&owner) || starts_with_any(owner, CORE_DESTROY_PREFIXES)
}

struct LifecycleCounts {
    /// `^/[\w/]+/Destroy\s*\(` at the start of the stripped line.
    destroy: &'static Pat,
    /// Every `qdel(` except `qdel(src)`, which `qdel_src` baselines on its own.
    qdel: Pat,
}

impl Lint for LifecycleCounts {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_file(&self, cx: &Cx, f: &SourceFile, out: &mut Sink) {
        // Unit tests, benchmarks, the vendored TGS DMAPI, the lifecycle engine and the macro
        // definitions do not count their qdel( calls (a Destroy() override is banned everywhere).
        let exempt = starts_with_any(&f.rel, cx.list("exempt_prefixes")) || cx.list("exempt_files").iter().any(|e| *e == f.rel);
        for (no, line) in f.code().numbered() {
            let text = py_strip(line);
            if text.contains("Destroy") && self.destroy.is_match(text) {
                if let Some(paren) = text.find('(') {
                    let header = &text[..paren];
                    // `/obj/item/foo/Destroy(` -> `/obj/item/foo`
                    let owner = &header[..header.rfind("/Destroy").unwrap_or(header.len())];
                    if !core_destroy_owner(owner) {
                        out.site("destroy", no);
                    }
                }
            }
            if exempt || !text.contains("qdel") {
                continue;
            }
            for _ in self.qdel.find_iter(text) {
                // Asked only about a line with a qdel( that would otherwise count.
                if out.allowed(f, no, "lifecycle") {
                    break;
                }
                out.site("qdel", no);
            }
        }
    }

    fn parity(&self) -> Option<Parity> {
        Some(Parity {
            old: &["tools/ci/lifecycle_counts_lint.py"],
            old_raw: &[],
            blank: &["tools/ci/lifecycle_counts_baseline.txt"],
            // The destroy lines carry no `[label/rule]` tag, and some paths hold spaces: compare on file and line.
            parse: ParseKind::FileLineAny,
            update: Some(&["tools/ci/lifecycle_counts_lint.py", "--update"]),
            seed: Some(&["tools/ci/lifecycle_counts_lint.py", "--seed"]),
            files: &["tools/ci/lifecycle_counts_baseline.txt"],
            selftest: None,
        })
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(LifecycleCounts {
        destroy: pat_match!(r"^/[\w/]+/Destroy\s*\("),
        qdel: Pat::new(r"(?<![\w.])qdel\s*\((?!\s*src\s*[,)])"),
    });
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::scopes::LintScope;
    use crate::tree::Tree;

    fn scan(rel: &str, text: &str) -> Sink {
        let mut scope = LintScope::default();
        scope.lists.insert("exempt_prefixes".to_string(), vec!["code/__defines/".to_string()]);
        scope.lists.insert("exempt_files".to_string(), vec!["code/datums/lifecycle/verbs.dm".to_string()]);
        let tree = Tree::from_files(vec![]);
        let cx = Cx { tree: &tree, meta: &META, scope: &scope };
        let f = SourceFile::from_text(rel, text);
        let mut out = Sink::new();
        out.cur = f.rel.clone();
        let mut reg = Registry::default();
        register(&mut reg);
        reg.lints[0].scan_file(&cx, &f, &mut out);
        out
    }

    #[test]
    fn one_allow_answer_keeps_every_qdel_on_the_line() {
        let out = scan("code/a.dm", "qdel(M) qdel(N) // ALLOW(lifecycle): the sweep deletes every mob\nqdel(M) qdel(N)\nx = 1 // ALLOW(lifecycle): nothing on this line is a qdel\n");
        let lines: Vec<u32> = out.sites.iter().map(|s| s.line).collect();
        assert_eq!(lines, vec![2, 2]);
        assert_eq!(out.allow_used.len(), 1);
        assert_eq!(out.allow_used[0].line, 1);
    }

    #[test]
    fn exempt_paths_still_check_destroy_overrides() {
        for rel in ["code/__defines/x.dm", "code/datums/lifecycle/verbs.dm"] {
            let out = scan(rel, "/obj/foo/Destroy()\n\tqdel(M)\n\tqdel(src)\n");
            let rules: Vec<&str> = out.sites.iter().map(|s| s.rule.as_str()).collect();
            assert_eq!(rules, vec!["destroy"], "{}", rel);
        }
        let out = scan("code/x.dm", "/datum/Destroy()\n/obj/foo/Destroy()\n\tqdel(M)\n\tqdel(src)\n");
        let rules: Vec<(&str, u32)> = out.sites.iter().map(|s| (s.rule.as_str(), s.line)).collect();
        assert_eq!(rules, vec![("destroy", 2), ("qdel", 3)]);
    }
}

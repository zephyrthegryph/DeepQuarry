//! Port of `tools/ci/decl_lint.py`: the declarative-lifecycle lint
//! (doc/rewrite/declarative_lifecycle.md).
//!
//! Counts `Initialize()` / `on_materialize()` / `on_destroy()` body lines doing work that a lifecycle
//! declaration (`code/__defines/lifecycle_decl.dm`) now does. Each rule is a conversion backlog,
//! a hard ban (no baseline). A line (or the comment
//! line above it) carrying `// ALLOW(decl): <reason>` is not counted; unit tests and benchmarks are
//! skipped (`[lint.decl]` in `tools/ci/lint_scopes.toml`).
//!
//! Quirks kept from the Python:
//! * the files are an `os.walk` of `code/` (dot-files and dot-directories included), not `glob`;
//! * `owned_vars()` reads EVERY file, the exempt ones too, and the raw lines, so an `own_set(...)` in a
//!   comment or in a unit test makes its var name an owned var for `destroy_qdel_owned`;
//! * a body line is cut at the first `//` even inside a string (`"http://x" + create_reagents()` hides
//!   the call), and a body is every indented or blank line after a header, ended by the next
//!   column-0 line;
//! * the ALLOW question is asked once per line that has at least one hit, and keeps all its hits.

use std::collections::BTreeSet;

use serde::{Deserialize, Serialize};

use crate::dm::pylines::recorded_into;
use crate::dm::sys::col0;
use crate::incr;
use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::parity::Parity;
use crate::pat::Pat;
use crate::pat_match;
use crate::tree::{Select, SourceFile};
use crate::util::{before_slashes, py_strip};

const HINT: &str = "declare it (doc/rewrite/declarative_lifecycle.md) instead of doing it by hand";

macro_rules! rules {
    ($($n:literal),* $(,)?) => { &[$(RuleMeta { name: $n, hint: HINT }),*] };
}

static META: Meta = Meta {
    name: crate::allow_registry_fields::decl::SCOPE_META_0.name,
    group: crate::allow_registry_fields::decl::SCOPE_META_0.group,
    label: "decl",
    legacy: "tools/ci/decl_lint.py",
    // os.walk: dot-files and dot-directories included.
    select: Select { roots: &[("code", "dm")], hidden: true },
    scan: ScanKind::Tree,
    policy: Policy::Hard,
    // The old RULES: the INIT_RULES, then the two special rules, then the DESTROY_RULES.
    rules: rules![
        "init_reagents",
        "init_gas",
        "init_registry",
        "init_service",
        "init_bind",
        "init_scheduling",
        "init_visuals",
        "init_new_child",
        "destroy_qdel_owned",
        "destroy_drop",
        "destroy_registry",
        "destroy_scheduling",
        "destroy_unbind",
        "destroy_effects",
    ],
    allow: crate::allow_registry_fields::decl::ALLOW_0,
    lists: crate::allow_registry_fields::decl::SCOPE_META_0.lists,
};

use crate::decl_policy::{Decl,owned_vars_of,text_spans,proc_kind};
#[derive(Serialize, Deserialize, Default, PartialEq)]
struct Owned {
    names: Vec<String>,
}



/// Initialize is an atom lifecycle only. Plain datum callbacks with that name are
/// called by their owners (including repeated business initialization), not InitAtom.
/// Preserve all definitions so the text fallback cannot reintroduce an excluded body.
#[cfg(feature = "legacy-sem")]
fn typed_lifecycle_defs(sem: &crate::sem::Sem) -> Vec<(String, u32, String, bool)> {
    crate::sem::procs::proc_defs(sem, &["Initialize", "on_materialize", "on_destroy"])
        .into_iter()
        .map(|d| {
            let lifecycle = d.name != "Initialize" || sem.is_subtype(&d.owner, "/atom");
            (d.rel, d.header, d.name, lifecycle)
        })
        .collect()
}

impl Lint for Decl {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        #[cfg(feature = "legacy-sem")]
        {
            let all = cx.all_files();
            let tree_key = incr::ctx_key(
                &all.iter()
                    .map(|f| (f.rel.as_str(), f.fkey))
                    .collect::<Vec<_>>(),
            );
            let typed: Option<Vec<(String, u32, String, bool)>> =
                incr::cached("decl-typed-defs-lifecycle-v2", tree_key, || {
                    cx.sem().map(|sem| typed_lifecycle_defs(&sem))
                });
            self.scan_headers(cx, out, typed.as_deref(), false);
        }
        #[cfg(not(feature = "legacy-sem"))]
        {
            let _ = (cx, out);
            panic!("decl requires explicitly injected native lifecycle facts");
        }
    }

    fn parity(&self) -> Option<Parity> {
        // `--report` also falls through to the ratchet check and prints every new site again, so raw
        // sites come from the CI run with the baseline blanked instead.
        let mut p = Parity::ratchet(&["tools/ci/decl_lint.py"], &[]);
        p.update = Some(&["tools/ci/decl_lint.py", "--update"]);
        p.seed = Some(&["tools/ci/decl_lint.py", "--seed"]);
        Some(p)
    }
}

pub(crate) fn captured_metadata() -> &'static Meta {
    &META
}
pub(crate) fn scan_captured(cx: &Cx, out: &mut Sink, headers: &[(String, u32, String, bool)]) {
    Decl::new().scan_headers(cx, out, Some(headers), true);
}
impl Decl {
    fn scan_headers(
        &self,
        cx: &Cx,
        out: &mut Sink,
        typed: Option<&[(String, u32, String, bool)]>,
        captured: bool,
    ) {
        let all = cx.all_files();
        // Captured native policy never enters the legacy on-disk cache path.
        let owned = if captured {
            all.iter()
                .map(|f| Owned {
                    names: owned_vars_of(f),
                })
                .collect()
        } else {
            incr::facts("decl-owned", &all, |f| Owned {
                names: owned_vars_of(f),
            })
        };
        let refs: BTreeSet<String> = owned.into_iter().flat_map(|o| o.names).collect();
        let files = cx.files();
        let tree_key = incr::ctx_key(
            &all.iter()
                .map(|f| (f.rel.as_str(), f.fkey))
                .collect::<Vec<_>>(),
        );
        let mut by_rel: std::collections::HashMap<&str, Vec<(u32, &'static str)>> =
            std::collections::HashMap::new();
        let mut manual_initialize: std::collections::HashMap<&str, BTreeSet<usize>> =
            std::collections::HashMap::new();
        if let Some(defs) = typed {
            for (rel, header, name, lifecycle) in defs {
                if *lifecycle {
                    by_rel
                        .entry(rel.as_str())
                        .or_default()
                        .push((*header, proc_kind(name)));
                } else {
                    manual_initialize
                        .entry(rel.as_str())
                        .or_default()
                        .insert(*header as usize + 1);
                }
            }
        }
        let judge = |f: &SourceFile| {
            if typed.is_none() {
                return self.judge(f, &refs);
            }
            let no_defs = Vec::new();
            let defs = by_rel.get(f.rel.as_str()).unwrap_or(&no_defs);
            let raw = f.raw();
            let lines: Vec<&str> = (1..=raw.num_lines()).map(|n| raw.line(n)).collect();
            let mut spans: Vec<(&'static str, std::ops::Range<usize>)> = defs
                .iter()
                .map(|(h, p)| (*p, crate::lifecycle_source::body_lines(&lines, *h)))
                .collect();
            spans.extend(text_spans(f).into_iter().filter(|(proc, range)| {
                *proc != "Initialize"
                    || !manual_initialize
                        .get(f.rel.as_str())
                        .is_some_and(|headers| headers.contains(&range.start))
            }));
            self.judge_spans(f, &refs, &spans)
        };
        let key = incr::ctx_key(&(&refs, typed.is_some().then_some(tree_key)));
        let results = recorded_into(out, || {
            if captured {
                files.iter().map(|f| judge(f)).collect()
            } else {
                incr::keyed("decl-judge", key, &files, judge)
            }
        });
        for (f, res) in files.iter().zip(results) {
            for (rule, line) in res {
                out.site_in(META.rules[rule as usize].name, &f.rel, line as usize);
            }
        }
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(Decl::new());
}

#[cfg(all(test, feature = "legacy-sem"))]
mod lifecycle_classification_tests {
    use super::*;
    use crate::tree::{SourceFile, Tree};

    #[test]
    fn manual_datum_initialize_is_not_atom_lifecycle_including_explicit_parent_types() {
        let source = "/datum/transport/proc/Initialize(list/assets)\n\tafter(src, 10, null)\n/obj/device/Initialize(mapload)\n\tafter(src, 10, null)\n/datum/atom_alias\n\tparent_type = /obj\n/datum/atom_alias/Initialize(mapload)\n\tafter(src, 10, null)\n";
        let root = tempfile::tempdir().unwrap();
        std::fs::create_dir_all(root.path().join("code")).unwrap();
        std::fs::write(root.path().join("code/probe.dm"), source).unwrap();
        let file = SourceFile::from_text("code/probe.dm", source);
        let tree = Tree::from_files(vec![SourceFile::from_text("code/probe.dm", source)]);
        let sem = crate::sem::Sem::build(root.path(), &tree).unwrap();
        let defs = typed_lifecycle_defs(&sem);
        let excluded: BTreeSet<usize> = defs
            .iter()
            .filter(|d| !d.3)
            .map(|d| d.1 as usize + 1)
            .collect();
        let spans: Vec<_> = text_spans(&file)
            .into_iter()
            .filter(|(name, span)| *name != "Initialize" || !excluded.contains(&span.start))
            .collect();
        let findings = Decl::new().judge_spans(&file, &BTreeSet::new(), &spans);
        assert_eq!(
            findings.iter().map(|site| site.1).collect::<Vec<_>>(),
            vec![4, 8]
        );
        assert!(
            defs.iter().any(|d| d.1 == 1 && !d.3),
            "the actual manual callback is classified"
        );
        assert!(
            defs.iter().any(|d| d.1 == 7 && d.3),
            "semantic atom ancestry wins over the textual datum prefix"
        );
    }
}

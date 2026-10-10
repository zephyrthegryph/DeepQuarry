//! Port of `tools/ci/decl_lint.py`: the declarative-lifecycle lint
//! (doc/rewrite/declarative_lifecycle.md).
//!
//! Counts `Initialize()` / `on_materialize()` / `on_destroy()` body lines doing work that a lifecycle
//! declaration (`code/__defines/lifecycle_decl.dm`) now does. Each rule is a conversion backlog,
//! ratcheted shrink-only by site fingerprint in `tools/ci/decl_baseline.txt`. A line (or the comment
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

const BASELINE: &str = "tools/ci/decl_baseline.txt";
const HINT: &str = "declare it (doc/rewrite/declarative_lifecycle.md) instead of doing it by hand";

macro_rules! rules {
    ($($n:literal),* $(,)?) => { &[$(RuleMeta { name: $n, hint: HINT }),*] };
}

static META: Meta = Meta {
    name: "decl",
    group: "",
    label: "decl",
    legacy: "tools/ci/decl_lint.py",
    // os.walk: dot-files and dot-directories included.
    select: Select { roots: &[("code", "dm")], hidden: true },
    scan: ScanKind::Tree,
    policy: Policy::Sites {
        baseline: BASELINE,
        header: &[
            "Declarative-lifecycle backlog (tools/ci/decl_lint.py, doc/rewrite/declarative_lifecycle.md).",
            "rule<TAB>file<TAB>normalized line. Shrink-only: convert sites, then `python tools/ci/decl_lint.py --update`.",
        ],
        // Rules whose backlog reached 0: a new site fails outright (no baseline row can cover it).
        banned: &["init_gas", "init_service", "init_bind", "destroy_qdel_owned", "destroy_registry", "destroy_scheduling", "destroy_unbind"],
    },
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
    allow: &["decl"],
    lists: &[],
};

struct Decl {
    init_rules: Vec<(&'static str, Pat)>,
    destroy_rules: Vec<(&'static str, Pat)>,
}

impl Decl {
    fn new() -> Decl {
        Decl {
            init_rules: vec![
                ("init_reagents", Pat::new(r"\bcreate_reagents\s*\(|\breagents\.add_reagent\s*\(")),
                ("init_gas", Pat::new(r"\bair_contents\s*=\s*new\b|\.adjust_gas\s*\(")),
                ("init_registry", Pat::new(r"\bregistry_join\s*\([^)]*\bsrc\b|\bGLOB\.\w+\[[^\]]*\]\s*=\s*src\b")),
                ("init_service", Pat::new(r"\bGLOB\.\w+_service\.\w+\(\s*src\b")),
                ("init_bind", Pat::new(r"\bconnect_to_network\s*\(\s*\)|\bvg_\w*bind\w*\s*\(|\bheat_body_create\s*\(")),
                ("init_scheduling", Pat::new(r"\bom_task_periodic\s*\(\s*src\s*,|\bom_attach\s*\(\s*src\s*,|\b(?:om_after|after)\s*\(\s*src\s*,")),
                ("init_visuals", Pat::new(r"\badd_overlay\s*\(|\bcut_overlays\s*\(|^\s*(?:src\.)?icon_state\s*=")),
            ],
            destroy_rules: vec![
                (
                    "destroy_drop",
                    Pat::new(
                        r"\bdump_contents\s*\(|\bfor\s*\(\s*var/[\w/]+\s+in\s+(?:src\.)?contents\b.*|\bfor\s*\(\s*var/[\w/]+\s+in\s+contents_of\(\s*src\s*\)",
                    ),
                ),
                ("destroy_registry", Pat::new(r"\bregistry_leave\s*\(|\bGLOB\.\w+\s*-=\s*src\b")),
                ("destroy_scheduling", Pat::new(r"\bom_task_periodic_stop\s*\(|\bSTOP_PROCESSING\s*\(")),
                ("destroy_unbind", Pat::new(r"\bdisconnect_from_network\s*\(|\bvg_\w*unbind\w*\s*\(")),
                (
                    "destroy_effects",
                    Pat::new(
                        r"\bvisible_message\s*\(|\bplaysound\s*\(|\bnew\s+/obj/[\w/]+\s*\(\s*(?:loc|src\.loc|get_turf\([^)]*\)|T)\s*\)",
                    ),
                ),
            ],
        }
    }
}

/// `OWN_WRITE` over every raw line of one file: the var names written through the own_* accessors
/// (sorted, unique). The tree-wide set is the union over every file, exempt ones too.
fn owned_vars_of(f: &SourceFile) -> Vec<String> {
    let own_write = crate::pat!(
        r#"\b(?:own_(?:set|add|put|transfer|move)|rel_(?:set|add))\([^,]+,\s*(?:"|nameof\((?:/[\w/]+::|\w+\.)?)(\w+)(?:"|\))"#
    );
    let mut names: BTreeSet<String> = BTreeSet::new();
    for line in f.raw().lines() {
        // `\bown_...` needs the text `own_`: a prefilter with the same result.
        if !line.contains("own_") && !line.contains("rel_") {
            continue;
        }
        for m in own_write.captures_iter(line) {
            names.insert(m.s(1).to_string());
        }
    }
    names.into_iter().collect()
}

#[derive(Serialize, Deserialize, Default, PartialEq)]
struct Owned {
    names: Vec<String>,
}

impl Decl {
    /// One file's sites as `(rule index, line)`, in emission order. ALLOW questions are recorded
    /// (the cache replays them).
    fn judge(&self, f: &SourceFile, refs: &BTreeSet<String>) -> Vec<(u8, u32)> {
        let header = pat_match!(r"^(/[\w/]+)/(Initialize|on_materialize|on_destroy)\s*\(");
        let new_into = pat_match!(r#"^\s*(?:own|rel)_(?:set|add)\(\s*src\s*,\s*(?:"|nameof\((?:/[\w/]+::|\w+\.)?)(\w+)(?:"|\))\s*,\s*new\b"#);
        let qdel_var = crate::pat!(
            r#"\b(?:own_(?:clear|take|take_all)|rel_clear)\(\s*src\s*,\s*(?:"|nameof\((?:/[\w/]+::|\w+\.)?)(\w+)(?:"|\))|\bqdel\s*\(\s*(?:src\.)?(\w+)\s*\)"#
        );
        // MATERIALIZE_RULES: the INIT_RULES that also apply to on_materialize(), in INIT_RULES order.
        let materialize = ["init_registry", "init_service", "init_scheduling"];
        let rule_index = |name: &str| META.rules.iter().position(|r| r.name == name).unwrap_or(0) as u8;

        let mut out: Vec<(u8, u32)> = Vec::new();
        let mut proc: Option<&str> = None;
        for (number, line) in f.raw().numbered() {
            if let Some(m) = header.captures(line) {
                proc = Some(match m.s(2) {
                    "Initialize" => "Initialize",
                    "on_materialize" => "on_materialize",
                    _ => "on_destroy",
                });
                continue;
            }
            if col0(line) {
                proc = None;
                continue;
            }
            let Some(proc) = proc else { continue };
            if py_strip(line).is_empty() {
                continue;
            }
            let code = before_slashes(line);
            if py_strip(code).is_empty() {
                continue;
            }
            let mut hit: Vec<&'static str> = Vec::new();
            match proc {
                "Initialize" => {
                    hit.extend(self.init_rules.iter().filter(|(_, rx)| rx.is_match(code)).map(|(r, _)| *r));
                    if new_into.is_match(code) {
                        hit.push("init_new_child");
                    }
                }
                "on_materialize" => {
                    hit.extend(self.init_rules.iter().filter(|(r, rx)| materialize.contains(r) && rx.is_match(code)).map(|(r, _)| *r));
                }
                _ => {
                    hit.extend(self.destroy_rules.iter().filter(|(_, rx)| rx.is_match(code)).map(|(r, _)| *r));
                    for qm in qdel_var.captures_iter(code) {
                        if qm.matched(1) || (qm.matched(2) && refs.contains(qm.s(2))) {
                            hit.push("destroy_qdel_owned");
                            break;
                        }
                    }
                }
            }
            // Asked only about a line that would otherwise count.
            if !hit.is_empty() && !crate::dm::sys::kept_recorded(f, number, "decl") {
                for rule in hit {
                    out.push((rule_index(rule), number as u32));
                }
            }
        }
        out
    }
}

impl Lint for Decl {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        let all = cx.all_files();
        let owned = incr::facts("decl-owned", &all, |f| Owned { names: owned_vars_of(f) });
        let refs: BTreeSet<String> = owned.into_iter().flat_map(|o| o.names).collect();
        let files = cx.files();
        let key = incr::ctx_key(&refs);
        let results = recorded_into(out, || incr::keyed("decl-judge", key, &files, |f| self.judge(f, &refs)));
        for (f, res) in files.iter().zip(results) {
            for (rule, line) in res {
                out.site_in(META.rules[rule as usize].name, &f.rel, line as usize);
            }
        }
    }

    fn parity(&self) -> Option<Parity> {
        // `--report` also falls through to the ratchet check and prints every new site again, so raw
        // sites come from the CI run with the baseline blanked instead.
        let mut p = Parity::ratchet(&["tools/ci/decl_lint.py"], &[BASELINE]);
        p.update = Some(&["tools/ci/decl_lint.py", "--update"]);
        p.seed = Some(&["tools/ci/decl_lint.py", "--seed"]);
        Some(p)
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(Decl::new());
}

//! Port of `tools/ci/init_lint.py`: the `Initialize()` ratchet (Phase 4 track 4c,
//! doc/rewrite/init_and_turfs.md sec 3.6).
//!
//! `Initialize()` should only set the instance's own state; type facts belong in the type table,
//! world registration in `on_materialize()`. Rules:
//!
//! * `initialize` / `late_initialize`: a `/type/Initialize(` / `/type/LateInitialize(` override, except
//!   one with an `// INIT: <reason>` on the header line or the comment line directly above it, or an
//!   `ALLOW(init)` keep;
//! * `world_reads`: a line in an `Initialize()` body that reaches outside the instance (`range(`,
//!   `orange(`, `view(`, `GetAbove`, `GetBelow`, `GLOB.`, `START_PROCESSING`);
//! * `turf_on_materialize`: a `/turf/.../on_materialize(` override (ceiling 0);
//! * `table_init_overrides`: an `Initialize()`/`LateInitialize()` override on a type that inherits
//!   `init_from_table = TRUE` (ceiling 0).
//!
//! Quirks kept from the Python:
//! * files are read with `read().splitlines()` (also breaking on `\v`, `\f`, `\x1c`..`\x1e`, NEL and
//!   U+2028/9, no final empty line), over an `os.walk` of `code/` then `maps/` (dot-files included);
//! * the unit-test/benchmark exemption (`[lint.init]` in `tools/ci/lint_scopes.toml`) applies to the
//!   per-file rules only: `table_init_overrides` reads every file, exempt ones too, and asks the
//!   ALLOW question about every header line it meets, whether or not it would count;
//! * the `init_from_table` flags are one global dict, so when two files flag the same type the last
//!   one in `os.walk` order wins (`dm::walk::walk_order`); a header's ancestors are searched nearest
//!   first and the search stops at the first flagged one;
//! * an `// INIT:` reason keeps a header before the ALLOW question is asked, so an `ALLOW(init)` on
//!   such a header is never recorded as used by the per-file rules (the table pass still asks).

use std::collections::HashMap;

use crate::dm::pylines::{allowed_in, py_splitlines};
use crate::dm::sys::col0;
use crate::dm::walk::walk_order;
use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::parity::Parity;
use crate::pat_match;
use crate::tree::{Select, SourceFile};
use crate::util::{before_slashes, py_lstrip};

const BASELINE: &str = "tools/ci/init_baseline.txt";

static META: Meta = Meta {
    name: "init",
    group: "",
    label: "init",
    legacy: "tools/ci/init_lint.py",
    // os.walk of code/ and maps/: dot-files and dot-directories included.
    select: Select { roots: &[("code", "dm"), ("maps", "dm")], hidden: true },
    scan: ScanKind::Both,
    policy: Policy::Sites {
        baseline: BASELINE,
        header: &[
            "Initialize() ratchet sites (tools/ci/init_lint.py, doc/rewrite/init_and_turfs.md sec 3.6).",
            "rule<TAB>file<TAB>normalized line. Shrink-only: fix sites, then `python tools/ci/init_lint.py --update`.",
        ],
        banned: &["turf_on_materialize", "table_init_overrides"],
    },
    rules: &[
        RuleMeta {
            name: "initialize",
            hint: "move type facts to the type table and registration to on_materialize(); an override that sets per-instance state says which with `// INIT: <state it sets>` on or above the header",
        },
        RuleMeta { name: "late_initialize", hint: "use on_materialize() or a first-use accessor instead of LateInitialize()" },
        RuleMeta { name: "world_reads", hint: "don't reach outside the instance in Initialize(); do it in on_materialize()" },
        RuleMeta { name: "turf_on_materialize", hint: "turf on_materialize() overrides are skipped by SSatoms; use the type table" },
        RuleMeta { name: "table_init_overrides", hint: "set init_from_table = FALSE on a type that overrides Initialize()" },
    ],
    allow: &["init"],
    lists: &[],
};

struct Init;

impl Lint for Init {
    fn meta(&self) -> &Meta {
        &META
    }

    /// `scan(lines)` for one non-exempt file.
    fn scan_file(&self, _cx: &Cx, f: &SourceFile, out: &mut Sink) {
        let init_header = pat_match!(r"^(/[\w/]+)/Initialize\s*\(");
        let late_header = pat_match!(r"^(/[\w/]+)/LateInitialize\s*\(");
        let turf_materialize = pat_match!(r"^/turf(/[\w/]*)?/on_materialize\s*\(");
        let reason = crate::pat!(r"//\s*INIT:\s*\S");
        let world_read =
            crate::pat!(r"(?<![\w.])(?:o?range|view)\s*\(|\bGetAbove\s*\(|\bGetBelow\s*\(|\bGLOB\.|\bSTART_PROCESSING\s*\(");

        let lines = py_splitlines(f.text());
        let mut in_init = false;
        for (i, line) in lines.iter().enumerate() {
            let number = i + 1;
            let line = *line;
            if turf_materialize.is_match(line) {
                out.site("turf_on_materialize", number);
            }
            let init = init_header.is_match(line);
            let late = late_header.is_match(line);
            if init || late {
                in_init = init;
                let above = if number > 1 { lines[number - 2] } else { "" };
                if reason.is_match(line) || (py_lstrip(above).starts_with("//") && reason.is_match(above)) {
                    continue; // an `// INIT:` reason keeps it (one count, not two)
                }
                if allowed_in(out, f, &lines, number, "init") {
                    continue;
                }
                out.site(if init { "initialize" } else { "late_initialize" }, number);
                continue;
            }
            if col0(line) && !line.starts_with("//") {
                in_init = false;
                continue;
            }
            if in_init {
                let code = before_slashes(line);
                if world_read.is_match(code) && !allowed_in(out, f, &lines, number, "init") {
                    out.site("world_reads", number);
                }
            }
        }
    }

    /// `table_init_violations(files)` over every file, exempt ones included.
    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        let init_header = pat_match!(r"^(/[\w/]+)/Initialize\s*\(");
        let late_header = pat_match!(r"^(/[\w/]+)/LateInitialize\s*\(");
        let type_block = pat_match!(r"^(/[\w/]+)\s*(//.*)?$");
        let table_flag = pat_match!(r"^\s+init_from_table\s*=\s*(TRUE|FALSE|1|0)\b");

        let all = cx.all_files();
        let mut flags: HashMap<String, bool> = HashMap::new();
        let mut headers: Vec<(&str, usize, String)> = Vec::new();
        for f in walk_order(&all) {
            let lines = py_splitlines(f.text());
            let mut block: Option<String> = None;
            for (i, line) in lines.iter().enumerate() {
                let number = i + 1;
                let line = *line;
                if let Some(head) = type_block.captures(line) {
                    if !line.contains('(') {
                        block = Some(head.s(1).to_string());
                        continue;
                    }
                }
                if col0(line) {
                    block = None;
                }
                if let Some(flag) = table_flag.captures(line) {
                    if let Some(b) = &block {
                        flags.insert(b.clone(), matches!(flag.s(1), "TRUE" | "1"));
                    }
                }
                let header = init_header.captures(line).or_else(|| late_header.captures(line));
                if let Some(h) = header {
                    // Asked for every header, not only one that would count.
                    if !allowed_in(out, f, &lines, number, "init") {
                        headers.push((f.rel.as_str(), number, h.s(1).to_string()));
                    }
                }
            }
        }
        for (rel, number, path) in headers {
            let parts: Vec<&str> = path.split('/').collect();
            for cut in (2..=parts.len()).rev() {
                let ancestor = parts[..cut].join("/");
                if let Some(&on) = flags.get(&ancestor) {
                    // The type that turns the flag on keeps its Initialize() as the fallback
                    // (a colour or extra New() args) and mirrors it in table_initialize().
                    if on && cut != parts.len() {
                        out.site_in("table_init_overrides", rel, number);
                    }
                    break;
                }
            }
        }
    }

    fn parity(&self) -> Option<Parity> {
        let mut p = Parity::ratchet(&["tools/ci/init_lint.py"], &[BASELINE]);
        p.update = Some(&["tools/ci/init_lint.py", "--update"]);
        p.seed = Some(&["tools/ci/init_lint.py", "--seed"]);
        Some(p)
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(Init);
}

//! The init lint (doc/rewrite/final_api.html section 15/17, the "init" row; section 6 "Lifecycle").
//!
//! One rule for what an `Initialize()` override may do: per-instance state only, and it says which with a reason code.
//! Starting contents are `starts =`, capability setup is `on_holder_init(A)`, work after init is `after_init()`. Rules:
//!
//! * `initialize`: a `/type/Initialize(` override without `// ALLOW(init/CODE): <reason>` on the header line or the comment
//!   line directly above it, CODE one of [`REASON_CODES`]. A bare `ALLOW(init)` (no code) does not keep it.
//! * `late_initialize`: a `/type/LateInitialize(` override. Banned: `after_init(0, then(PROC_REF(x)))` runs when the
//!   instance's init is complete (after the whole map load for a map-loaded one), `on_holder_init(A)` for capability setup.
//! * `init_lines` (October 2026, replaces counting whole overrides): each imperative line in an `Initialize()` override body, kept or not:
//!   every statement but the bare parent call (`. = ..()`, `..()`, `return ..()`) and a bare `return`. A type converts a line by moving its job
//!   into a form or a named `setup(PROC_REF(x))` hook; the override goes when its last line does. Switched on with a regenerated baseline
//!   (`analyze baseline --seed --lint init`), every other rule's totals unchanged; doc/rewrite/framework_gaps.md, "The init ratchet counts lines".
//! * `world_reads`: a line in an `Initialize()` body that reaches outside the instance (`range(`, `orange(`, `view(`,
//!   `GetAbove`, `GetBelow`, `GLOB.`, `START_PROCESSING`): move it to `on_holder_init(A)`, `after_init()` or `membership()`;
//! * `turf_on_materialize`: a `/turf/.../on_materialize(` override (banned);
//! * `table_init_overrides`: an `Initialize()` override on a type that inherits `init_from_table = TRUE` (banned).
//!
//! The `// INIT: <reason>` form of the old ratchet is gone: a kept override names its code in the one annotation form.
//!
//! Quirks kept from the Python port: files are read with `read().splitlines()` over an `os.walk` of `code/` then `maps/`
//! (dot-files included); the unit-test/benchmark exemption (`[lint.init]` in `tools/ci/lint_scopes.toml`) applies to the
//! per-file rules only: `table_init_overrides` reads every file and asks the ALLOW question about every header it meets;
//! the `init_from_table` flags are one global dict (last file in walk order wins; nearest flagged ancestor).

use std::collections::HashMap;

use serde::{Deserialize, Serialize};

use crate::dm::pylines::{allowed_in, allowed_in_recorded, py_splitlines, recorded_into};
use crate::dm::sys::col0;
use crate::dm::walk::walk_order;
use crate::incr;
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
    scan: ScanKind::Tree,
    policy: Policy::Sites {
        baseline: BASELINE,
        header: &[
            "Initialize() ratchet sites (the init lint, tools/analyze/src/lints/init.rs; doc/rewrite/final_api.html sections 6 and 17).",
            "rule<TAB>file<TAB>normalized line. Shrink-only: fix sites, then `analyze baseline --update --lint init`.",
        ],
        banned: &["late_initialize", "turf_on_materialize", "table_init_overrides"],
    },
    rules: &[
        RuleMeta {
            name: "initialize",
            hint: "starting contents are `starts =`, capability setup is on_holder_init(A), timed or after-load work is after_init(); an override that only sets per-instance state carries `// ALLOW(init/CODE): <state it sets>` (CODE: INSTANCE_STATE, CTOR_ARGS, FRAMEWORK) on or above the header",
        },
        RuleMeta { name: "late_initialize", hint: "LateInitialize() is banned: after_init(0, then(PROC_REF(x))) runs when the instance's init is complete (after the map load), on_holder_init(A) does capability setup" },
        RuleMeta {
            name: "init_lines",
            hint: "an imperative line in an Initialize() override: move its job into a form (starts =, keeps_if(), rolls(), param(apply =), spawns_many(), finds(), ...) or a named setup(PROC_REF(x)) hook in CAPABILITIES; the override goes when its last line does",
        },
        RuleMeta { name: "world_reads", hint: "don't reach outside the instance in Initialize(); do it in on_holder_init(A), after_init() or through membership()" },
        RuleMeta { name: "turf_on_materialize", hint: "turf on_materialize() overrides are skipped by SSatoms; use the type table" },
        RuleMeta { name: "table_init_overrides", hint: "set init_from_table = FALSE on a type that overrides Initialize()" },
    ],
    allow: &["init"],
    lists: &[],
};

/// One file's part of the table-init pass: its `init_from_table` flags `(type, on)` in file order,
/// and its `Initialize()` / `LateInitialize()` headers `(line, type)` that no ALLOW(init) kept.
#[derive(Serialize, Deserialize, Default, PartialEq)]
struct TableFacts {
    flags: Vec<(String, bool)>,
    headers: Vec<(u32, String)>,
}

fn table_facts(f: &SourceFile) -> TableFacts {
    let init_header = pat_match!(r"^(/[\w/]+)/Initialize\s*\(");
    let late_header = pat_match!(r"^(/[\w/]+)/LateInitialize\s*\(");
    let type_block = pat_match!(r"^(/[\w/]+)\s*(//.*)?$");
    let table_flag = pat_match!(r"^\s+init_from_table\s*=\s*(TRUE|FALSE|1|0)\b");
    let mut out = TableFacts::default();
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
                out.flags.push((b.clone(), matches!(flag.s(1), "TRUE" | "1")));
            }
        }
        let header = init_header.captures(line).or_else(|| late_header.captures(line));
        if let Some(h) = header {
            // Asked for every header, not only one that would count.
            if !allowed_in_recorded(f, &lines, number, "init") {
                out.headers.push((number as u32, h.s(1).to_string()));
            }
        }
    }
    out
}

/// The reason codes an `ALLOW(init/CODE)` keep may carry (also listed in `[lint.init] reason_codes`):
/// INSTANCE_STATE (a value only this instance has: a map edit, a random roll, a copy of where it is built), CTOR_ARGS (it
/// consumes extra constructor arguments), FRAMEWORK (a base of the init chain itself).
pub const REASON_CODES: &[&str] = &["INSTANCE_STATE", "CTOR_ARGS", "FRAMEWORK"];

/// The code of an `ALLOW(init/CODE): reason` on `line`, Some("") for a bare `ALLOW(init): reason`, None for no keep.
fn init_code(line: &str) -> Option<String> {
    match crate::allow::parse(line) {
        Some(a) if !a.reason.is_empty() && a.names.contains("init") => Some(a.codes.get("init").cloned().unwrap_or_default()),
        _ => None,
    }
}

struct Init;

impl Lint for Init {
    fn meta(&self) -> &Meta {
        &META
    }

    /// The per-file rules on the typed tree: the definitions come from the model (`sem::procs::proc_defs`), so a header the
    /// text rule could not see (a nested block, a macro that writes the proc) counts too; the body lines a definition owns are
    /// bounded by indentation and read as text (`world_reads` names macros the parser expands away). Without a model, the text
    /// rule (`scan_text`).
    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        let files = cx.files();
        let key = incr::ctx_key(&cx.all_files().iter().map(|f| (f.rel.as_str(), f.fkey)).collect::<Vec<_>>());
        let typed: Option<Vec<(String, u32, String, String)>> = incr::cached("init-typed-defs", key, || {
            cx.sem().map(|sem| {
                crate::sem::procs::proc_defs(&sem, &["Initialize", "LateInitialize", "on_materialize"])
                    .into_iter()
                    .map(|d| (d.rel, d.header, d.owner, d.name))
                    .collect()
            })
        });
        match typed {
            Some(defs) => {
                let mut by_rel: HashMap<&str, Vec<(u32, Def)>> = HashMap::new();
                for (rel, header, owner, name) in &defs {
                    let kind = match name.as_str() {
                        "Initialize" => Def::Init,
                        "LateInitialize" => Def::Late,
                        _ if owner == "/turf" || owner.starts_with("/turf/") => Def::TurfMaterialize,
                        _ => continue,
                    };
                    by_rel.entry(rel.as_str()).or_default().push((*header, kind));
                }
                for f in &files {
                    out.cur = f.rel.clone();
                    // The engine's lines (universal newlines), which `proc_defs` numbers its headers by.
                    let raw = f.raw();
                    let lines: Vec<&str> = (1..=raw.num_lines()).map(|n| raw.line(n).trim_end_matches('\r')).collect();
                    // The model's definitions, and the text headers too: a file the model does not compile (a map's code outside
                    // the test .dme, a branch of an #if) still counts as it did.
                    let mut defs: std::collections::BTreeMap<u32, Def> = by_rel.get(f.rel.as_str()).map(|d| d.iter().copied().collect()).unwrap_or_default();
                    for (i, line) in lines.iter().enumerate() {
                        if let Some(kind) = text_header(line) {
                            defs.entry(i as u32 + 1).or_insert(kind);
                        }
                    }
                    for (header, kind) in defs {
                        self.judge_def(f, &lines, header as usize, kind, out);
                    }
                }
            }
            None => {
                for f in &files {
                    out.cur = f.rel.clone();
                    self.scan_text(f, out);
                }
            }
        }
        self.table_init(cx, out);
    }

    // No parity: the reason codes and the LateInitialize ban have no Python counterpart (init_lint.py is gone).
    fn parity(&self) -> Option<Parity> {
        None
    }
}

impl Init {
    /// `table_init_violations(files)` over every file, exempt ones included. Per-file facts (the
    /// `init_from_table` flags and the headers the ALLOW question did not keep) are cached by content;
    /// the cross-file part (last flag in walk order wins, nearest flagged ancestor) is a cheap merge.
    fn table_init(&self, cx: &Cx, out: &mut Sink) {
        let all = cx.all_files();
        let facts = recorded_into(out, || incr::facts("init-table", &all, table_facts));
        let with: Vec<(&SourceFile, &TableFacts)> = all.iter().copied().zip(facts.iter()).filter(|(_, fa)| !fa.flags.is_empty() || !fa.headers.is_empty()).collect();
        let by_rel: HashMap<&str, &TableFacts> = with.iter().map(|(f, fa)| (f.rel.as_str(), *fa)).collect();
        let sel: Vec<&SourceFile> = with.iter().map(|(f, _)| *f).collect();

        let mut flags: HashMap<&str, bool> = HashMap::new();
        for f in walk_order(&sel) {
            for (ty, on) in &by_rel[f.rel.as_str()].flags {
                flags.insert(ty.as_str(), *on);
            }
        }
        for f in walk_order(&sel) {
            for (number, path) in &by_rel[f.rel.as_str()].headers {
                let parts: Vec<&str> = path.split('/').collect();
                for cut in (2..=parts.len()).rev() {
                    let ancestor = parts[..cut].join("/");
                    if let Some(&on) = flags.get(ancestor.as_str()) {
                        // The type that turns the flag on keeps its Initialize() as the fallback
                        // (a colour or extra New() args) and mirrors it in table_initialize().
                        if on && cut != parts.len() {
                            out.site_in("table_init_overrides", &f.rel, *number as usize);
                        }
                        break;
                    }
                }
            }
        }
    }

    /// One definition's sites: the header (its ALLOW(init/CODE) keep) and, for an Initialize(), its body's world reads.
    fn judge_def(&self, f: &SourceFile, lines: &[&str], number: usize, kind: Def, out: &mut Sink) {
        match kind {
            Def::TurfMaterialize => out.site("turf_on_materialize", number),
            Def::Late => out.site("late_initialize", number),
            Def::Init => {
                let line = lines.get(number - 1).copied().unwrap_or("");
                let above = if number > 1 { lines[number - 2] } else { "" };
                let code = init_code(line).or_else(|| if py_lstrip(above).starts_with("//") { init_code(above) } else { None });
                match code {
                    Some(c) if REASON_CODES.contains(&c.as_str()) => {
                        allowed_in(out, f, lines, number, "init"); // records the annotation as used
                    }
                    Some(c) => out.site_msg(
                        "initialize",
                        number,
                        format!("ALLOW(init{}) needs a reason code: ALLOW(init/CODE), CODE one of {}", if c.is_empty() { String::new() } else { format!("/{c}") }, REASON_CODES.join(", ")),
                    ),
                    None => {}
                }
                let world_read = crate::pat!(r"(?<![\w.])(?:o?range|view)\s*\(|\bGetAbove\s*\(|\bGetBelow\s*\(|\bGLOB\.|\bSTART_PROCESSING\s*\(");
                for n in crate::sem::procs::body_lines(lines, number as u32) {
                    let code = before_slashes(lines[n - 1]);
                    let stmt = code.trim();
                    let super_call = matches!(stmt.replace(' ', "").as_str(), ".=..()" | "..()" | "return..()" | "return" | "return.");
                    if !stmt.is_empty() && !super_call {
                        out.site("init_lines", n);
                    }
                    if world_read.is_match(code) && !allowed_in(out, f, lines, n, "init") {
                        out.site("world_reads", n);
                    }
                }
            }
        }
    }

    /// The text rule, for a tree the model cannot parse: headers found by their `/type/Initialize(` text, a body every
    /// line up to the next column-0 line.
    fn scan_text(&self, f: &SourceFile, out: &mut Sink) {
        let lines = py_splitlines(f.text());
        for (i, line) in lines.iter().enumerate() {
            if let Some(kind) = text_header(line) {
                self.judge_def(f, &lines, i + 1, kind, out);
            }
        }
    }
}

/// A definition header as the text rule reads one (`/type/Initialize(` at column 0; a commented-out line is not one).
fn text_header(line: &str) -> Option<Def> {
    let init_header = pat_match!(r"^(/[\w/]+)/Initialize\s*\(");
    let late_header = pat_match!(r"^(/[\w/]+)/LateInitialize\s*\(");
    let turf_materialize = pat_match!(r"^/turf(/[\w/]*)?/on_materialize\s*\(");
    if line.starts_with("//") {
        return None;
    }
    if turf_materialize.is_match(line) {
        Some(Def::TurfMaterialize)
    } else if late_header.is_match(line) {
        Some(Def::Late)
    } else if init_header.is_match(line) {
        Some(Def::Init)
    } else {
        None
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Def {
    Init,
    Late,
    TurfMaterialize,
}

pub fn register(reg: &mut Registry) {
    reg.add(Init);
}

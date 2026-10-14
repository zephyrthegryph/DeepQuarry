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
            "rule<TAB>file<TAB>text; an init_lines row is an identity (@owner::Initialize::target). Shrink-only: fix sites, then `analyze baseline --update --lint init`.",
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
                let mut by_rel: HashMap<&str, Vec<(u32, Def, String)>> = HashMap::new();
                for (rel, header, owner, name) in &defs {
                    let kind = match name.as_str() {
                        "Initialize" => Def::Init,
                        "LateInitialize" => Def::Late,
                        _ if owner == "/turf" || owner.starts_with("/turf/") => Def::TurfMaterialize,
                        _ => continue,
                    };
                    by_rel.entry(rel.as_str()).or_default().push((*header, kind, owner.clone()));
                }
                for f in &files {
                    out.cur = f.rel.clone();
                    // The engine's lines (universal newlines), which `proc_defs` numbers its headers by.
                    let raw = f.raw();
                    let lines: Vec<&str> = (1..=raw.num_lines()).map(|n| raw.line(n).trim_end_matches('\r')).collect();
                    // The model's definitions, and the text headers too: a file the model does not compile (a map's code outside
                    // the test .dme, a branch of an #if) still counts as it did.
                    let mut defs: std::collections::BTreeMap<u32, (Def, String)> =
                        by_rel.get(f.rel.as_str()).map(|d| d.iter().map(|(h, k, o)| (*h, (*k, o.clone()))).collect()).unwrap_or_default();
                    for (i, line) in lines.iter().enumerate() {
                        if let Some(kind) = text_header(line) {
                            defs.entry(i as u32 + 1).or_insert((kind, text_owner(line)));
                        }
                    }
                    for (header, (kind, owner)) in defs {
                        self.judge_def(f, &lines, header as usize, kind, &owner, out);
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
    fn judge_def(&self, f: &SourceFile, lines: &[&str], number: usize, kind: Def, owner: &str, out: &mut Sink) {
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
                        // Identified by the type, the proc and the target the line writes or calls, not by its text: see [`init_line_target`].
                        out.site_decl("init_lines", &f.rel, n, String::new(), format!("{}::Initialize::{}", owner, init_line_target(stmt)));
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
                self.judge_def(f, &lines, i + 1, kind, &text_owner(line), out);
            }
        }
    }
}

/// The owner a header line names (`/obj/x/Initialize(` is `/obj/x`); empty when the line writes none.
fn text_owner(line: &str) -> String {
    let init_header = pat_match!(r"^(/[\w/]+)/Initialize\s*\(");
    init_header.captures(line).map(|c| c.s(1).to_string()).unwrap_or_default()
}

/// What an `init_lines` statement is about, for its identity (`owner::Initialize::target`):
///
/// * a write `x = v`, `src.x += v`, `var/T/x = v` or the call of its setter `set_x(v)`: the var `x` (so converting a write to its setter,
///   which the `tracked` lint asks for, is the same site; `a.b = v` is `a.b`);
/// * a call `proc(args)`, `src.proc(args)`, `obj.proc(args)`, `PROC_REF` macros included: the callee;
/// * control flow (`if`, `else`, `for`, `while`, `switch`, ...): the keyword, so editing a condition keeps the site;
/// * `return v`: `return`;
/// * anything else (the argument lines of a multi-line call, a bare expression): `expr`.
///
/// Sites that share a target share an identity; the ratchet counts them per identity, so a fix still shrinks the count and a new
/// line of the same target still fails once the count is exceeded.
pub fn init_line_target(stmt: &str) -> String {
    let t = stmt.trim();
    let control = pat_match!(r"^(else\s+if|if|else|for|while|switch|do|try|catch|spawn)\b");
    if let Some(c) = control.captures(t) {
        return c.s(1).split_whitespace().collect::<Vec<_>>().join(" ");
    }
    if pat_match!(r"^return\b").is_match(t) {
        return "return".to_string();
    }
    let t = t.strip_prefix("src.").unwrap_or(t);
    // `var/list/x = ...` / `var/x`: the declared name.
    let decl = pat_match!(r"^var/(?:[\w/]*/)?(\w+)\s*(?:=|$|\[)");
    if let Some(c) = decl.captures(t) {
        return c.s(1).to_string();
    }
    let assign = pat_match!(r"^(\.|[A-Za-z_][\w.\[\]]*)\s*(?:\|\||&&|<<|>>|[-+*/%|&^])?=(?:[^=]|$)");
    if let Some(c) = assign.captures(t) {
        return c.s(1).to_string();
    }
    let call = pat_match!(r"^([A-Za-z_][\w.:]*)\s*\(");
    if let Some(c) = call.captures(t) {
        let callee = c.s(1);
        if let Some(var) = callee.strip_prefix("set_") {
            if !var.is_empty() && !var.contains('.') {
                return var.to_string();
            }
        }
        return callee.to_string();
    }
    "expr".to_string()
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::baseline::{check_sites, write_sites, Mode};
    use crate::lint::Site;
    use crate::tree::Tree;

    const BASE: &str = "/obj/machinery/mineral/console/Initialize()
	. = ..()
	linked = locate(/obj/machinery/mineral/processing_unit) in range(src, 2)
	set_power(5)
	if(!pipe_color)
		pipe_color = \"#fff\"
	ensure_pump_materials()
";

    fn scan(text: &str) -> (Tree, Vec<Site>) {
        let tree = Tree::from_files(vec![SourceFile::from_text("code/a.dm", text)]);
        let f = tree.get("code/a.dm").unwrap();
        let mut out = Sink::new();
        out.cur = f.rel.clone();
        Init.scan_text(f, &mut out);
        let sites = out.sites.into_iter().filter(|s| s.rule == "init_lines").collect();
        (tree, sites)
    }

    fn judge(base: &std::path::Path, text: &str) -> (bool, String) {
        let (tree, sites) = scan(text);
        let by_rule = vec![("init_lines", sites.iter().collect::<Vec<_>>())];
        let mut out = String::new();
        let failed = check_sites("init", &tree, &by_rule, &|_| String::new(), base, &[], &mut out);
        (failed, out)
    }

    fn seeded() -> (tempfile::TempDir, std::path::PathBuf) {
        let (tree, sites) = scan(BASE);
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("b.txt");
        let by_rule = vec![("init_lines", sites.iter().collect::<Vec<_>>())];
        let n = write_sites(&path, &["h"], &tree, &by_rule, &["init_lines"], Mode::Seed).unwrap();
        assert_eq!(n, 5);
        (dir, path)
    }

    #[test]
    fn targets_are_the_var_written_or_the_callee() {
        let t = init_line_target;
        assert_eq!(t("linked = locate(/obj/a)"), "linked");
        assert_eq!(t("src.linked = x"), "linked");
        assert_eq!(t("set_linked(x)"), "linked");
        assert_eq!(t("src.set_linked(x)"), "linked");
        assert_eq!(t("linked += 2"), "linked");
        assert_eq!(t("a.b = 1"), "a.b");
        assert_eq!(t("var/list/l = list()"), "l");
        assert_eq!(t("ensure_pump_materials()"), "ensure_pump_materials");
        assert_eq!(t("if(!pipe_color)"), "if");
        assert_eq!(t("else if(x == 2)"), "else if");
        assert_eq!(t("if(a == b) x = 1"), "if");
        assert_eq!(t("return x"), "return");
        assert_eq!(t("a == b"), "expr");
        assert_eq!(t("\"just a string\","), "expr");
    }

    #[test]
    fn the_same_sites_after_a_text_edit_a_move_and_a_reorder_stay_baselined() {
        let (_dir, path) = seeded();
        assert!(!judge(&path, BASE).0);
        // A line's text edited.
        let edited = BASE.replace("in range(src, 2)", "in range(src, 3)").replace("set_power(5)", "set_power(9)").replace("if(!pipe_color)", "if(isnull(pipe_color))");
        let (failed, out) = judge(&path, &edited);
        assert!(!failed, "{out}");
        // Two lines moved within the proc, and the whole body reordered.
        let reordered = "/obj/machinery/mineral/console/Initialize()
	. = ..()
	ensure_pump_materials()
	if(!pipe_color)
		pipe_color = \"#fff\"
	set_power(5)
	linked = locate(/obj/machinery/mineral/processing_unit) in range(src, 2)
";
        let (failed, out) = judge(&path, reordered);
        assert!(!failed, "{out}");
        // A write converted to its setter is the same site.
        let (failed, out) = judge(&path, &BASE.replace("\t\tpipe_color = \"#fff\"", "\t\tset_pipe_color(\"#fff\")"));
        assert!(!failed, "{out}");
    }

    #[test]
    fn a_new_write_or_call_fails_and_a_second_line_of_a_known_target_fails_too() {
        let (_dir, path) = seeded();
        let (failed, out) = judge(&path, &format!("{BASE}\textra = 1\n"));
        assert!(failed, "{out}");
        assert!(out.contains("code/a.dm:8:"), "{out}");
        let (failed, _) = judge(&path, &format!("{BASE}\tother_setup()\n"));
        assert!(failed);
        let (failed, _) = judge(&path, &format!("{BASE}\tlinked = null\n"));
        assert!(failed, "a second write of a baselined target is a new site");
        // The same var under another owner is another site.
        let (failed, _) = judge(&path, &BASE.replace("/obj/machinery/mineral/console/", "/obj/machinery/mineral/other/"));
        assert!(failed);
    }

    #[test]
    fn a_fixed_line_shrinks_the_count_and_update_drops_exactly_it() {
        let (_dir, path) = seeded();
        let fixed = BASE.replace("\tlinked = locate(/obj/machinery/mineral/processing_unit) in range(src, 2)\n", "");
        let (failed, out) = judge(&path, &fixed);
        assert!(!failed, "{out}");
        assert!(out.contains("1 baselined site gone"), "{out}");
        let (tree, sites) = scan(&fixed);
        let by_rule = vec![("init_lines", sites.iter().collect::<Vec<_>>())];
        assert_eq!(write_sites(&path, &["h"], &tree, &by_rule, &["init_lines"], Mode::Update).unwrap(), 4);
    }

    #[test]
    fn migrate_turns_line_text_rows_into_identity_rows_without_changing_the_count() {
        let (tree, sites) = scan(BASE);
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("b.txt");
        // The old format, including a setter spelled as its write, plus a row no site claims.
        std::fs::write(
            &path,
            "# h\ninit_lines\tcode/a.dm\tlinked = locate(/obj/machinery/mineral/processing_unit) in range(src, 2)\ninit_lines\tcode/a.dm\tpower = 5\ninit_lines\tcode/a.dm\tif(!pipe_color)\ninit_lines\tcode/a.dm\tpipe_color = \"#fff\"\ninit_lines\tcode/a.dm\tensure_pump_materials()\ninit_lines\tcode/gone.dm\tx = 1\n",
        )
        .unwrap();
        let by_rule = vec![("init_lines", sites.iter().collect::<Vec<_>>())];
        let n = write_sites(&path, &["h"], &tree, &by_rule, &["init_lines"], Mode::Migrate).unwrap();
        assert_eq!(n, 6);
        let text = std::fs::read_to_string(&path).unwrap();
        assert!(text.contains("@/obj/machinery/mineral/console::Initialize::linked"), "{text}");
        assert!(text.contains("@/obj/machinery/mineral/console::Initialize::power"), "{text}");
        assert!(text.contains("init_lines\tcode/gone.dm\tx = 1"), "{text}");
        // Re-running it changes nothing.
        assert_eq!(write_sites(&path, &["h"], &tree, &by_rule, &["init_lines"], Mode::Migrate).unwrap(), 6);
        assert_eq!(std::fs::read_to_string(&path).unwrap(), text);
        assert!(!judge(&path, BASE).0);
    }
}

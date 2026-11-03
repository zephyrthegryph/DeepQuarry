//! Port of `tools/ci/tracked_lint.py`: the tracked-var write lint (doc/rewrite/dx_conventions.md sec 1,
//! final_design.md sec 1).
//!
//! `TRACKED(T, var)` (code/__defines/capabilities.dm; two arguments, the channel argument is gone) declares that `var` on type T (and its
//! subtypes) is written only through its generated setter `T/proc/set_<var>(value)`, which compares with `TRACKED_UNCHANGED` (null differs from 0)
//! and publishes through `tracked_changed()`. `SETTER(T, var)` registers a hand-written `T/proc/set_<var>(value)` as var's setter and makes var tracked the
//! same way. A hand-written `/T/proc/set_<var>(` (or a subtype override of it) is the setter body. Reads are unrestricted. A `derive()` value
//! (`. += derive(nameof(var), ...)` in a `derived()` proc) is tracked with no setter at all: every write in DM is counted.
//!
//! This lint covers declared tracked vars only. The end state (doc/rewrite/final_api.html section 7, "Reactive closure") makes any var that reactive
//! code reads tracked, with a generated setter and a `raw_write` lint; list mutations of a read list get their own lint (`tracked_list`).
//!
//! Counted, for every tracked var V of type T, outside a setter body of V:
//! * `V = x`, `src.V = x`, `V += x` (and the other compound ops), `V++`, `V--`, `++V`, `--V` inside a
//!   proc of T or a subtype (a proc-local `var/V` shadows it and is skipped);
//! * `X.V = x` (and the same ops) anywhere, when X resolves to T or a subtype: a proc argument or a
//!   local declared `var/<type>/X` / `<type>/X` in the same proc.
//!
//! Not counted: type-level defaults and declarations, `==` compares, `#define` lines, comments and
//! strings, the `[lint.tracked]` exempt paths, and lines carrying `// ALLOW(tracked): <reason>`. The
//! baseline is empty: any site fails. `code/` and `maps/` are both read (`dm_files()`), and the
//! TRACKED / SETTER / derive() index reads the exempt files too.
//!
//! Quirks kept (the Python is the oracle):
//! * a `TRACKED(`/`SETTER(` line is matched on the RAW text, so one inside a block comment or a
//!   multi-line string still declares a var;
//! * a global `/proc/foo(` has owner `/proc` (the lazy owner group), and `derived` procs of owner `/`
//!   are skipped;
//! * the ALLOW lookup and the proc scan read the same-length `clean` view (physical line numbers, as the AST's
//!   argument positions are), so an unbalanced quote moves no line; an `[expr]` embedded in a string is code in DM and
//!   is scanned like any other;
//! * `tracked_type_of` returns the first base of the var's type set that the owner is under; the
//!   Python's set is hash-ordered, so with two matching bases the message may name either (the site
//!   is the same). Here the set is sorted, so the shortest path wins.
//!
//! Not ported: `--report` (it stays in the Python script).

use std::collections::{BTreeMap,BTreeSet};
use crate::{incr,lint::{Cx,Lint,Meta,Registry,Sink},parity::{ParseKind,Parity},tree::{SourceFile,CODE_DM},pat,pat_match};
use crate::tracked_policy::*;
pub use crate::tracked_policy::{Fix,MoreEdit};

/// What one run of the scan found: the files it judged and each file's hits.
pub struct Collected<'a> {
    pub files: Vec<&'a SourceFile>,
    pub hits: Vec<Vec<StoredHit>>,
}

/// A hit as the judge cache stores it.
#[derive(Clone, Debug, PartialEq, Eq, serde::Serialize, serde::Deserialize, Default)]
pub struct StoredHit {
    pub line: u32,
    pub msg: String,
    pub rule: u8,
    pub fix: Option<Fix>,
}

/// The tracked list vars (`TRACKED` on a `list` var): the vars whose generated procs exist, as `{var: {types}}`.
pub fn tracked_lists(cx: &Cx) -> Tracked {
    let mut lists: Tracked = BTreeMap::new();
    let Some(sem) = cx.sem() else { return lists };
    let decls = crate::gens::tracked_lists::declarations(cx.tree);
    for ((ty, var), _) in crate::gens::tracked_lists::list_vars(&sem, &decls) {
        lists.entry(var).or_default().insert(normalize_type(&ty));
    }
    lists
}

/// The scan both `check` and `fix` run: every hit of every judged file, cached while the tracked index is unchanged.
pub fn collect<'a>(cx: &Cx<'a>, tracked: &Tracked, tests: bool) -> Option<Collected<'a>> {
    let mut pats = build_pats(tracked)?;
    pats.setup = setup_hook_names(cx.all_files());
    let lists = tracked_lists(cx);
    let lpats = build_list_pats(&lists);
    let files: Vec<&SourceFile> = if tests { cx.all_files().into_iter().filter(|f| TEST_PREFIXES.iter().any(|p| f.rel.starts_with(p))).collect() } else { cx.files() };
    let semantic = cx.sem();
    let key = incr::ctx_key(&(tracked, &lists, &pats.setup));
    let hits: Vec<Vec<StoredHit>> = incr::keyed(if tests { "tracked-tests-judge-3" } else { "tracked-judge-3" }, key, &files, |f| {
        let mut sink = Sink::new();
        sink.cur = f.rel.clone();
        let named = semantic.as_ref().map(|sem| crate::sem::checks::named_argument_positions(sem, &f.rel)).unwrap_or_default();
        let (hits, _setters) = scan_one(tracked, &pats, &lists, lpats.as_ref(), f, &mut sink, &named);
        for u in sink.allow_used {
            crate::dm::sys::replay_recorded(vec![u]);
        }
        hits.into_iter().map(|h| StoredHit { line: h.line as u32, msg: h.msg, rule: h.rule, fix: h.fix }).collect()
    });
    Some(Collected { files, hits })
}

struct Tracker {
    tests: bool,
}

impl Lint for Tracker {
    fn meta(&self) -> &Meta {
        if self.tests {
            &META_TESTS
        } else {
            &META
        }
    }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        // Facts: the vars each file declares tracked (cached by content); merged into one index.
        let all = cx.all_files();
        let stats = self.tests;
        let facts: Vec<Vec<(String, String)>> = incr::facts(if stats { "tracked-tests-facts" } else { "tracked-facts" }, &all, |f| {
            let mut t: Tracked = BTreeMap::new();
            tracked_from_text_with(f, &mut t, stats);
            t.into_iter().flat_map(|(v, set)| set.into_iter().map(move |ty| (v.clone(), ty))).collect()
        });
        let mut tracked: Tracked = BTreeMap::new();
        for fs in &facts {
            for (v, ty) in fs {
                tracked.entry(v.clone()).or_default().insert(ty.clone());
            }
        }
        let mut total = 0usize;
        if let Some(c) = collect(cx, &tracked, self.tests) {
            for (f, hits) in c.files.iter().zip(c.hits) {
                for h in hits {
                    total += 1;
                    out.site_in_msg(META.rules[h.rule as usize].name, &f.rel, h.line as usize, h.msg);
                }
            }
            for u in crate::dm::sys::take_recorded() {
                if !out.allow_used.contains(&u) {
                    out.allow_used.push(u);
                }
            }
        }
        out.note(format!("tracked vars: {}, writes outside setters: {} (target 0)", tracked.len(), total));
    }

    fn selftest(&self) -> Result<String, String> {
        let files: Vec<SourceFile> = SELFTEST.iter().map(|(rel, text)| SourceFile::from_text(rel, text)).collect();
        let mut tracked: Tracked = BTreeMap::new();
        for f in &files {
            tracked_from_text(f, &mut tracked);
        }
        let pats = build_pats(&tracked).ok_or("no tracked vars in the fixtures")?;
        let mut got: Vec<(String, usize, String)> = Vec::new();
        let mut setters = 0usize;
        for f in &files {
            let mut sink = Sink::new();
            sink.cur = f.rel.clone();
            let (hits, s) = scan_one(&tracked, &pats, &Tracked::new(), None, f, &mut sink, &BTreeSet::new());
            setters += s.len();
            for h in hits {
                got.push((f.rel.clone(), h.line, h.msg.split(' ').next().unwrap_or("").to_string()));
            }
        }
        let want: Vec<(String, usize, String)> = SELFTEST_EXPECT.iter().map(|(r, n, v)| (r.to_string(), *n, v.to_string())).collect();
        if got == want && setters == 2 {
            Ok(format!("({} fixtures)", want.len()))
        } else {
            Err(format!("expected {:?}, got {:?}, setters {}", want, got, setters))
        }
    }

    fn parity(&self) -> Option<Parity> {
        if self.tests {
            return None;
        }
        Some(Parity {
            old: &["tools/ci/tracked_lint.py"],
            old_raw: &[],
            blank: &[],
            parse: ParseKind::FileLine,
            update: None,
            seed: None,
            files: &[],
            selftest: Some(&["tools/ci/tracked_lint.py", "--selftest"]),
        })
    }
}

/// The Python's `SELFTEST` fixtures (code/a.dm, code/b.dm; the texts start with a newline).
const SELFTEST: &[(&str, &str)] = &[
    (
        "code/a.dm",
        r#"
/obj/machinery/pump
	var/target_pressure = 100
	var/other = 1
TRACKED(/obj/machinery/pump, target_pressure)

/obj/machinery/pump/bigger
	target_pressure = 200

/obj/machinery/pump/proc/bad_direct()
	target_pressure = 5
	src.target_pressure += 1
	target_pressure++
	--target_pressure

/obj/machinery/pump/proc/good_read()
	if(target_pressure == 5)
		other = target_pressure
	set_target_pressure(7)

/obj/machinery/pump/proc/shadowed()
	var/target_pressure = 3
	target_pressure -= 1

/obj/machinery/pump/proc/allowed_write()
	target_pressure = 1 // ALLOW(tracked): fixture keep

/obj/machinery/pump/bigger/proc/subtype_write()
	target_pressure = 9

/obj/machinery/pump/bigger/set_target_pressure(value)
	target_pressure = value * 2
	return TRUE

/obj/other_thing/proc/unrelated()
	target_pressure = 4

/proc/external(obj/machinery/pump/P, obj/other_thing/Q)
	P.target_pressure = 3
	Q.target_pressure = 3
	var/obj/machinery/pump/bigger/B = P
	B.target_pressure -= 2
	unknown.target_pressure = 1
	// P.target_pressure = 8 in a comment
	var/s = "P.target_pressure = 8"

/obj/machinery/valve
	var/open = FALSE
SETTER(/obj/machinery/valve, open)

/obj/machinery/valve/proc/set_open(value)
	open = value
	update_pipes()

/obj/machinery/valve/proc/bad_open()
	open = TRUE

/proc/external_valve(obj/machinery/valve/V)
	V.open = FALSE
	if(V.open == TRUE)
		return
"#,
    ),
    (
        "code/b.dm",
        r#"
/obj/gadget
	var/total = 0

/obj/gadget/derived()
	. = ..()
	. += derive(nameof(total), nameof(level))

/obj/gadget/proc/oops()
	total = 5
"#,
    ),
];

const SELFTEST_EXPECT: &[(&str, usize, &str)] = &[
    ("code/a.dm", 11, "target_pressure"),
    ("code/a.dm", 12, "target_pressure"),
    ("code/a.dm", 13, "target_pressure"),
    ("code/a.dm", 14, "target_pressure"),
    ("code/a.dm", 29, "target_pressure"),
    ("code/a.dm", 39, "P.target_pressure"),
    ("code/a.dm", 42, "B.target_pressure"),
    ("code/a.dm", 56, "open"),
    ("code/a.dm", 59, "V.open"),
    ("code/b.dm", 10, "total"),
];

pub fn register(reg: &mut Registry) {
    reg.add(Tracker { tests: false });
    reg.add(Tracker { tests: true });
}

#[cfg(test)]
mod named_argument_tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};
    static NEXT: AtomicUsize = AtomicUsize::new(0);

    fn hits(body: &str) -> Vec<usize> {
        let root = std::env::temp_dir().join(format!("dq-tracked-args-{}-{}", std::process::id(), NEXT.fetch_add(1, Ordering::Relaxed)));
        std::fs::create_dir_all(root.join("code")).unwrap();
        let source = format!("/obj/machinery\n\tvar/state = 0\n\tvar/emagged = FALSE\n/obj/machinery/proc/probe()\n{body}\n");
        std::fs::write(root.join("code/fixture.dm"), &source).unwrap();
        let file = SourceFile::from_text("code/fixture.dm", &source);
        let mut tree = crate::tree::Tree::from_files(vec![SourceFile::from_text("code/fixture.dm", &source)]);
        tree.root = root.clone();
        let semantic = crate::sem::Sem::build(&root, &tree).unwrap();
        let named = crate::sem::checks::named_argument_positions(&semantic, "code/fixture.dm");
        let mut tracked = Tracked::new();
        tracked.insert("state".into(), BTreeSet::from(["/obj/machinery".into()]));
        tracked.insert("emagged".into(), BTreeSet::from(["/obj/machinery".into()]));
        let pats = build_pats(&tracked).unwrap();
        let (got, _) = scan_one(&tracked, &pats, &Tracked::new(), None, &file, &mut Sink::new(), &named);
        std::fs::remove_dir_all(root).unwrap();
        got.into_iter().map(|hit| hit.line).collect()
    }

    #[test]
    fn schema_state_option_is_a_named_argument() {
        assert!(hits("\tinterface(\"SpaceHeater\", state = 1)").is_empty());
    }
    #[test]
    fn multiline_row_constructor_key_is_not_entity_storage() {
        assert!(hits("\tvar/row = new /datum/row(\n\t\temagged = TRUE,\n\t\tstate = 1\n\t)").is_empty());
    }
    #[test]
    fn list_associative_key_is_not_entity_storage() {
        assert!(hits("\tvar/row = list(emagged = src.emagged, state = 1)").is_empty());
    }
    #[test]
    fn parenthesized_assignment_inside_list_remains_a_write() {
        assert_eq!(hits("\tvar/row = list((state = 2), emagged = TRUE)"), vec![5]);
    }
    #[test]
    fn bare_state_assignment_remains_a_violation() {
        assert_eq!(hits("\tstate = 1"), vec![5]);
    }
    #[test]
    fn named_argument_inside_a_macro_or_image_call_is_not_a_write() {
        assert_eq!(hits("	LAZYADD(images, image('x.dmi', loc = M, state = \"t\"))"), Vec::<usize>::new());
        assert_eq!(hits("	for(state = 1; state < 3; state++)"), vec![5, 5]);
    }

    #[test]
    fn named_argument_does_not_hide_real_assignment_on_same_line() {
        assert_eq!(hits("\tstate = 2; interface(\"SpaceHeater\", state = 1)"), vec![5]);
    }
}

/// `analyze fix --drop-declared [--apply]`: deletes the `TRACKED(T, v)` lines of vars reactive code reads. Read-driven tracking
/// (`gens::auto_tracked`) generates the same setter from the read set, so the declaration is redundant. A line stays when something else defines
/// `set_v` on the type's path (a subtype override that calls `..()`), which the generated setter would clash with, and when it is not a plain
/// `TRACKED(T, v)` (`TRACKED_BRIDGED`, `TRACKED_DATA`, `SETTER` and the schema forms carry more than the setter).
fn drop_declared(engine: &crate::run::Engine, root: &std::path::Path, apply: bool, prefixes: &[String]) -> std::process::ExitCode {
    use std::process::ExitCode;
    let tree = &engine.tree;
    let an = crate::gens::deps::analyzed(tree);
    let Some(an) = an.as_ref().as_ref() else {
        eprintln!("analyze fix: the dependency analysis is unavailable");
        return ExitCode::from(2);
    };
    let Some(sem) = crate::sem::sem_for(tree) else {
        eprintln!("analyze fix: the semantic model is unavailable");
        return ExitCode::from(2);
    };
    let defs = crate::gens::auto_tracked::setter_defs(tree, &sem);
    let scopes = crate::scopes::Scopes::load(&root.join("tools/ci/lint_scopes.toml")).unwrap_or_default();
    let auto = scopes.for_lint("auto_tracked", "");
    let exclude: Vec<String> = ["exclude", "exclude_fixtures", "exclude_heat", "exclude_memo"].iter().flat_map(|k| auto.list(k).iter().cloned().collect::<Vec<_>>()).collect();
    let include = auto.list("include");
    let line_pat = pat_match!(r"^(\s*)TRACKED\(\s*(/[\w/]+)\s*,\s*(\w+)\s*\)\s*(?://.*)?$");
    let calls = crate::gens::auto_tracked::set_calls(tree);
    // Pass 1: every plain TRACKED line, and the ones the generator would be asked to cover.
    let mut lines: Vec<(String, String, String)> = Vec::new();
    for f in tree.select(&CODE_DM) {
        if f.rel == crate::gens::auto_tracked::AUTO_REL || f.rel == "code/__defines/capabilities.dm" || (!prefixes.is_empty() && !prefixes.iter().any(|p| f.rel.starts_with(p.as_str()))) || !f.text().contains("TRACKED(") {
            continue;
        }
        for line in f.raw().text.split('\n') {
            if let Some(m) = line_pat.captures(line.trim_end_matches('\r')) {
                lines.push((f.rel.clone(), m.s(2).to_string(), m.s(3).to_string()));
            }
        }
    }
    let mut asked: BTreeSet<(String, String)> = BTreeSet::new();
    for (_, ty, var) in &lines {
        let read = an.reads.iter().any(|(o, v)| v == var && (o == ty || sem.is_subtype(ty, o) || sem.is_subtype(o, ty)));
        let called = crate::gens::auto_tracked::called_here(tree, &sem, &defs, &calls, ty, var);
        let included = include.iter().any(|e| e == &format!("{ty}::{var}"));
        if read || called || included {
            asked.insert((ty.clone(), var.clone()));
        }
    }
    // What the generator does with them once the lines are gone: the same decision it makes at `analyze gen`.
    let decided = crate::gens::auto_tracked::decide(tree, &sem, &asked, &exclude);
    let tracked: BTreeSet<(String, String)> = decided.tracked.iter().map(|a| (a.ty.clone(), a.var.clone())).collect();
    let covered: BTreeSet<(String, String)> = decided.blocked.iter().filter(|(_, _, why)| why == "an ancestor tracks it").map(|(t, v, _)| (t.clone(), v.clone())).collect();
    let why_blocked: std::collections::BTreeMap<(String, String), String> = decided.blocked.iter().map(|(t, v, w)| ((t.clone(), v.clone()), w.clone())).collect();
    let line_pat = pat_match!(r"^(\s*)TRACKED\(\s*(/[\w/]+)\s*,\s*(\w+)\s*\)\s*(?://.*)?$");
    let (mut dropped, mut kept) = (0usize, 0usize);
    let (mut read_n, mut called_n, mut idle_n) = (0usize, 0usize, 0usize);
    let mut files: BTreeSet<&str> = lines.iter().map(|(f, _, _)| f.as_str()).collect();
    for f in tree.select(&CODE_DM) {
        if !files.remove(f.rel.as_str()) {
            continue;
        }
        let text = f.raw().text.to_string();
        let mut out: Vec<&str> = Vec::new();
        let mut changed = false;
        for line in text.split('\n') {
            let content = line.trim_end_matches('\r');
            if let Some(m) = line_pat.captures(content) {
                let key = (m.s(2).to_string(), m.s(3).to_string());
                let (ty, var) = (&key.0, &key.1);
                let read = an.reads.iter().any(|(o, v)| v == var && (o == ty || sem.is_subtype(ty, o) || sem.is_subtype(o, ty)));
                let named = calls.contains(var.as_str()) || calls.contains(&format!("{var}[]"));
                let generated = tracked.contains(&key) || covered.contains(&key);
                // Nothing reads it and no `set_v()` call can be this var's: there is no setter to keep.
                let builtin = sem.var_decl(ty, var).is_none_or(|s| s.file.is_empty());
                let idle = !read && !builtin && (!named || !crate::gens::auto_tracked::untyped_call(tree, var)) && !asked.contains(&key);
                if generated || idle {
                    println!("{}: drop {}{}", f.rel, content.trim(), if read { "" } else if generated { "  (called, not read)" } else { "  (never written)" });
                    if read {
                        read_n += 1
                    } else if generated {
                        called_n += 1
                    } else {
                        idle_n += 1
                    }
                    dropped += 1;
                    changed = true;
                    continue;
                }
                println!("{}: KEEP {}  ({})", f.rel, content.trim(), why_blocked.get(&key).cloned().unwrap_or_else(|| "nothing asks the generator for it".to_string()));
                kept += 1;
            }
            out.push(line);
        }
        if changed && apply {
            let _ = std::fs::write(root.join(&f.rel), out.join("\n"));
        }
    }
    println!("{} TRACKED declaration(s) {} ({} read, {} called only, {} never written), {} kept", dropped, if apply { "dropped" } else { "droppable (dry run; --apply writes them)" }, read_n, called_n, idle_n, kept);
    ExitCode::SUCCESS
}

/// `analyze fix [--apply] [--tests] [--path PREFIX]...`: rewrites the in-place edits of tracked list vars (`list_mutation`) to the
/// generated procs. Prints each rewrite (or, with `--apply`, makes it) and the sites it cannot express, which stay for hand conversion.
pub fn fix_cli(args: &[String], root: &std::path::Path) -> std::process::ExitCode {
    use std::process::ExitCode;
    let apply = args.iter().any(|a| a == "--apply");
    let tests = args.iter().any(|a| a == "--tests");
    let mut prefixes: Vec<String> = Vec::new();
    let mut it = args.iter();
    while let Some(a) = it.next() {
        if a == "--path" {
            if let Some(p) = it.next() {
                prefixes.push(p.replace('\\', "/"));
            }
        }
    }
    let opts = crate::run::Options { root: root.to_path_buf(), lints: vec![LINT.to_string()], ..Default::default() };
    let engine = match crate::run::Engine::new(crate::run::registry(), opts) {
        Ok(e) => e,
        Err(e) => {
            eprintln!("analyze fix: {}", e);
            return ExitCode::from(2);
        }
    };
    if args.iter().any(|a| a == "--drop-declared") {
        return drop_declared(&engine, root, apply, &prefixes);
    }
    let meta = if tests { &META_TESTS } else { &META };
    let scope = engine.scopes.for_lint(meta.name, meta.group);
    let cx = Cx { tree: &engine.tree, meta, scope: &scope };
    let mut tracked: Tracked = BTreeMap::new();
    for f in cx.all_files() {
        tracked_from_text_with(f, &mut tracked, tests);
    }
    // A STAT var (tracked_tests also counts it) has no set_<var>(): the stat engine writes it, and a test sets it with set_var().
    let mut has_setter: Tracked = BTreeMap::new();
    for f in cx.all_files() {
        tracked_from_text_with(f, &mut has_setter, false);
    }
    let Some(c) = collect(&cx, &tracked, tests) else {
        println!("no tracked vars");
        return ExitCode::SUCCESS;
    };
    let (mut fixed, mut left) = (0usize, 0usize);
    for (f, hits) in c.files.iter().zip(&c.hits) {
        if !prefixes.is_empty() && !prefixes.iter().any(|p| f.rel.starts_with(p.as_str())) {
            continue;
        }
        let list: Vec<&StoredHit> = hits.iter().collect();
        if list.is_empty() {
            continue;
        }
        let path = root.join(&f.rel);
        let Ok(bytes) = std::fs::read(&path) else { continue };
        let Ok(text) = String::from_utf8(bytes) else { continue };
        let mut lines: Vec<String> = text.split('\n').map(|s| s.to_string()).collect();
        // Every edit of the file, checked against the original text and applied from the end so none moves another.
        let mut edits: Vec<(usize, u32, u32, String, String)> = Vec::new();
        for h in list {
            let line_at = h.line as usize;
            let ok = h.fix.as_ref().is_some_and(|fx| {
                lines.get(line_at - 1).and_then(|l| l.get(fx.start as usize..fx.end as usize)) == Some(fx.was.as_str())
                    && fx.more.iter().all(|m| lines.get(line_at - 1 + m.line_off as usize).and_then(|l| l.get(m.start as usize..m.end as usize)) == Some(m.was.as_str()))
            });
            let var = h.msg.split(' ').next().unwrap_or("").rsplit('.').next().unwrap_or("");
            match (&h.fix, ok && (h.rule == RULE_LIST || has_setter.contains_key(var))) {
                (Some(fx), true) => {
                    println!("{}:{}: {}  ->  {}{}", f.rel, h.line, fx.was, fx.text, if fx.more.is_empty() { "" } else { " ..." });
                    edits.push((line_at, fx.start, fx.end, fx.was.clone(), fx.text.clone()));
                    for m in &fx.more {
                        edits.push((line_at + m.line_off as usize, m.start, m.end, m.was.clone(), m.text.clone()));
                    }
                    fixed += 1;
                }
                _ => {
                    println!("{}:{}: residue: {}", f.rel, h.line, h.msg);
                    left += 1;
                }
            }
        }
        edits.sort_by(|a, b| (b.0, b.1, b.2).cmp(&(a.0, a.1, a.2)));
        let changed = !edits.is_empty();
        for (line, start, end, _was, text) in edits {
            lines[line - 1].replace_range(start as usize..end as usize, &text);
        }
        if changed && apply {
            let _ = std::fs::write(&path, lines.join("\n"));
        }
    }
    println!("{} rewrite(s){}, {} for hand conversion", fixed, if apply { " applied" } else { " (dry run; --apply writes them)" }, left);
    ExitCode::SUCCESS
}

#[cfg(test)]
mod list_mutation_tests {
    use super::*;

    const DECL: &str = "/obj/box\n\tvar/list/items\n\tvar/list/other\n\tvar/plain = 0\nTRACKED(/obj/box, items)\n";

    /// (line, rule, replacement) of every list hit in `body`, a proc of /obj/box.
    fn run(body: &str, args: &str) -> Vec<(usize, u8, Option<String>)> {
        let source = format!("{DECL}/obj/box/proc/probe({args})\n{body}\n");
        let f = SourceFile::from_text("code/fixture.dm", &source);
        let mut tracked = Tracked::new();
        tracked.insert("items".into(), BTreeSet::from(["/obj/box".into()]));
        let lists = tracked.clone();
        let pats = build_pats(&tracked).unwrap();
        let lpats = build_list_pats(&lists);
        let (hits, _) = scan_one(&tracked, &pats, &lists, lpats.as_ref(), &f, &mut Sink::new(), &BTreeSet::new());
        let raw: Vec<&str> = source.split('\n').collect();
        hits.into_iter()
            .filter(|h| h.rule == RULE_LIST)
            .map(|h| {
                let text = h.fix.as_ref().map(|fx| {
                    let line = raw[h.line - 1];
                    assert_eq!(&line[fx.start as usize..fx.end as usize], fx.was);
                    format!("{}{}{}", &line[..fx.start as usize], fx.text, &line[fx.end as usize..])
                });
                (h.line, h.rule, text)
            })
            .collect()
    }

    fn fixed(body: &str) -> Option<String> {
        run(body, "").into_iter().next().and_then(|h| h.2).map(|s| s.trim().to_string())
    }

    #[test]
    fn macros_become_the_generated_procs() {
        assert_eq!(fixed("\tLAZYADD(items, x)").as_deref(), Some("add_items(x)"));
        assert_eq!(fixed("\tLAZYADD(src.items, make(a, b))").as_deref(), Some("add_items(make(a, b))"));
        assert_eq!(fixed("\tLAZYREMOVE(items, x)").as_deref(), Some("remove_items(x)"));
        assert_eq!(fixed("\tLAZYOR(items, x)").as_deref(), Some("include_items(x)"));
        assert_eq!(fixed("\tLAZYDISTINCTADD(items, x)").as_deref(), Some("include_items(x)"));
        assert_eq!(fixed("\tLAZYSET(items, k, v)").as_deref(), Some("set_items_at(k, v)"));
        assert_eq!(fixed("\tLAZYCLEARLIST(items)").as_deref(), Some("clear_items()"));
    }

    #[test]
    fn methods_and_index_writes_become_the_generated_procs() {
        assert_eq!(fixed("\titems.Add(x)").as_deref(), Some("add_items(x)"));
        assert_eq!(fixed("\titems.Add(a, b)").as_deref(), Some("add_items(list(a, b))"));
        assert_eq!(fixed("\titems.Remove(x)").as_deref(), Some("remove_items(x)"));
        assert_eq!(fixed("\titems.Cut()").as_deref(), Some("clear_items()"));
        assert_eq!(fixed("\titems.Cut(1, 2)").as_deref(), Some("cut_items(1, 2)"));
        assert_eq!(fixed("\titems.Swap(1, 2)").as_deref(), Some("swap_items(1, 2)"));
        assert_eq!(fixed("\titems[k] = list(1, 2)").as_deref(), Some("set_items_at(k, list(1, 2))"));
        assert_eq!(fixed("\titems[a[1]] = v // note").as_deref(), Some("set_items_at(a[1], v) // note"));
    }

    #[test]
    fn other_holders_and_other_lists() {
        let hits = run("\tvar/obj/box/B = new\n\tLAZYADD(B.items, x)\n\tB.items.Remove(y)\n\tLAZYADD(other, x)\n\tvar/items = list()\n\titems.Add(1)", "");
        assert_eq!(hits.iter().map(|h| h.0).collect::<Vec<_>>(), vec![8, 9], "{:?}", hits);
        assert_eq!(hits[0].2.as_deref().map(str::trim), Some("B.add_items(x)"));
    }

    #[test]
    fn unfixable_forms_are_flagged_without_a_rewrite() {
        let hits = run("\tvar/n = items.Add(x)\n\titems[k] += 1\n\titems.Insert(1)\n\tif(a) items.Add(x)", "");
        assert_eq!(hits.len(), 4, "{:?}", hits);
        assert!(hits.iter().all(|h| h.2.is_none()), "{:?}", hits);
    }

    #[test]
    fn reads_and_non_tracked_are_not_hits() {
        assert!(run("\tvar/n = length(items)\n\tfor(var/i in items)\n\t\tn += i\n\treturn items[1]\n\tif(items.Find(x))\n\t\treturn 1\n\tother.Add(1)", "").is_empty());
    }
}

#[cfg(test)]
mod setter_fix_tests {
    use super::*;

    const DECL: &str = "/obj/box\n\tvar/plain = 0\n\tvar/list/items\n\tvar/other = 0\nTRACKED(/obj/box, plain)\nTRACKED(/obj/box, items)\n";

    /// The rewritten file of `body`, a proc `header` of /obj/box (None when nothing was a hit); the hits that have no rewrite are listed as `residue`.
    fn run(header: &str, body: &str) -> (Option<String>, usize) {
        let source = format!("{DECL}{header}\n{body}\n");
        let f = SourceFile::from_text("code/fixture.dm", &source);
        let mut tracked = Tracked::new();
        tracked.insert("plain".into(), BTreeSet::from(["/obj/box".into()]));
        tracked.insert("items".into(), BTreeSet::from(["/obj/box".into()]));
        let mut lists = Tracked::new();
        lists.insert("items".into(), BTreeSet::from(["/obj/box".into()]));
        let pats = build_pats(&tracked).unwrap();
        let lpats = build_list_pats(&lists);
        let (hits, _) = scan_one(&tracked, &pats, &lists, lpats.as_ref(), &f, &mut Sink::new(), &BTreeSet::new());
        if hits.is_empty() {
            return (None, 0);
        }
        let mut lines: Vec<String> = source.split('\n').map(|s| s.to_string()).collect();
        let mut edits: Vec<(usize, usize, usize, String)> = Vec::new();
        let mut residue = 0;
        for h in &hits {
            match &h.fix {
                Some(fx) => {
                    assert_eq!(&lines[h.line - 1][fx.start as usize..fx.end as usize], fx.was);
                    edits.push((h.line, fx.start as usize, fx.end as usize, fx.text.clone()));
                    for m in &fx.more {
                        edits.push((h.line + m.line_off as usize, m.start as usize, m.end as usize, m.text.clone()));
                    }
                }
                None => residue += 1,
            }
        }
        edits.sort_by(|a, b| (b.0, b.1, b.2).cmp(&(a.0, a.1, a.2)));
        for (line, start, end, text) in edits {
            lines[line - 1].replace_range(start..end, &text);
        }
        let skip = DECL.matches('\n').count() + 1;
        (Some(lines[skip..].join("\n").trim_end().to_string()), residue)
    }

    fn fixed(body: &str) -> String {
        run("/obj/box/proc/probe(obj/box/B)", body).0.unwrap_or_default()
    }

    #[test]
    fn a_plain_assignment_becomes_the_setter_call() {
        assert_eq!(fixed("\tplain = 5"), "\tset_plain(5)");
        assert_eq!(fixed("\tsrc.plain = 5 // note"), "\tset_plain(5) // note");
        assert_eq!(fixed("\tB.plain = compute(1, 2);"), "\tB.set_plain(compute(1, 2));");
        assert_eq!(fixed("\tif(other) plain = 1"), "\tif(other) set_plain(1)");
        assert_eq!(fixed("\tplain = 1; other = 2"), "\tset_plain(1); other = 2");
        assert_eq!(fixed("\tother = 2; plain = 1"), "\tother = 2; set_plain(1)");
    }

    #[test]
    fn compound_and_incrementing_writes_keep_their_arithmetic() {
        assert_eq!(fixed("\tplain += 2"), "\tset_plain(plain + 2)");
        assert_eq!(fixed("\tplain |= FLAG_A | FLAG_B"), "\tset_plain(plain | (FLAG_A | FLAG_B))");
        assert_eq!(fixed("\tB.plain -= other * 2"), "\tB.set_plain(B.plain - (other * 2))");
        assert_eq!(fixed("\tplain++"), "\tset_plain(plain + 1)");
        assert_eq!(fixed("\t--plain"), "\tset_plain(plain - 1)");
        assert_eq!(fixed("\tB.plain++ // up"), "\tB.set_plain(B.plain + 1) // up");
    }

    #[test]
    fn a_multi_line_value_closes_the_call_where_it_ends() {
        assert_eq!(fixed("\tplain = list(\n\t\t\"a\",\n\t\t\"b\"\n\t)"), "\tset_plain(list(\n\t\t\"a\",\n\t\t\"b\"\n\t))");
    }

    #[test]
    fn a_list_var_uses_its_generated_procs_for_compound_ops() {
        assert_eq!(fixed("\titems += x"), "\tadd_items(x)");
        assert_eq!(fixed("\titems -= x"), "\tremove_items(x)");
        assert_eq!(fixed("\titems |= x"), "\tinclude_items(x)");
        assert_eq!(fixed("\titems = list()"), "\tset_items(list())");
    }

    #[test]
    fn a_write_whose_value_is_used_is_left_for_hand_conversion() {
        let (text, residue) = run("/obj/box/proc/probe()", "\tvar/n = (plain = 5)\n\tfor(plain = 0; plain < 3; plain++)\n\t\tn++");
        assert!(text.is_some());
        assert_eq!(residue, 3);
    }

    #[test]
    fn setup_hook_construction_is_owner_typed() {
        let hits = |proc_owner: &str| {
            let source = format!("{DECL}CAPABILITIES(/obj/box)\n\tsetup(PROC_REF(draw_it))\n\n{proc_owner}/proc/draw_it()\n\tplain = 5\n");
            let f = SourceFile::from_text("code/fixture.dm", &source);
            let mut tracked = Tracked::new();
            tracked.insert("plain".into(), BTreeSet::from(["/obj/box".into(), "/obj/other".into()]));
            let mut pats = build_pats(&tracked).unwrap();
            pats.setup = setup_hook_names(vec![&f]);
            scan_one(&tracked, &pats, &Tracked::new(), None, &f, &mut Sink::new(), &BTreeSet::new()).0.len()
        };
        assert_eq!(hits("/obj/box"), 0);
        assert_eq!(hits("/obj/box/sub"), 0);
        assert_eq!(hits("/obj/other"), 1);
    }

    #[test]
    fn construction_writes_its_own_vars_plainly() {
        assert_eq!(run("/obj/box/Initialize(mapload)", "\t. = ..()\n\tplain = 5\n\tsrc.plain += 1\n\tLAZYADD(items, 1)").0, None);
        assert_eq!(run("/obj/box/New(loc)", "\tplain = 5").0, None);
        // another object's var, and a proc that runs once the holder is live, are judged as anywhere else
        let hooks = setup_hook_names(vec![&SourceFile::from_text("a.dm", "CAPABILITIES(/obj/box)\n\tsetup(PROC_REF(draw_it))\n")]);
        assert_eq!(hooks.iter().cloned().collect::<Vec<_>>(), vec![("/obj/box".to_string(), "draw_it".to_string())]);
        // the hook's own type and its subtypes construct; a same-named proc on an unrelated type is judged as anywhere else
        assert!(run("/obj/box/Initialize(mapload, obj/box/B)", "\tB.plain = 5").0.is_some());
        assert!(run("/obj/box/proc/after_setup()", "\tplain = 5").0.is_some());
        // a part the instance walks while it is built is construction too
        assert_eq!(run("/obj/box/Initialize(mapload)", "\t. = ..()\n\tfor(var/obj/box/P in parts)\n\t\tP.plain = 5").0, None);
        assert!(run("/obj/box/Initialize(mapload)", "\t. = ..()\n\tfor(var/obj/box/P in range(1))\n\t\tP.plain = 5").0.is_some());
    }
}

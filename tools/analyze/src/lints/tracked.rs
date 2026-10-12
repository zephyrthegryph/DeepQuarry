//! Port of `tools/ci/tracked_lint.py`: the tracked-var write lint (doc/rewrite/dx_conventions.md sec 1,
//! final_design.md sec 1).
//!
//! `TRACKED(T, var, channel)` (code/__defines/capabilities.dm) declares that `var` on type T (and its
//! subtypes) is written only through its setter `T/proc/set_<var>(value)`, which calls changed().
//! `SETTER(T, var)` registers a hand-written `T/proc/set_<var>(value)` as var's setter and makes var
//! tracked the same way. A hand-written `/T/proc/set_<var>(` (or a subtype override of it) is the
//! setter body. Reads are unrestricted. A `derive()` value (`. += derive(nameof(var), ...)` in a
//! `derived()` proc) is tracked with no setter at all: every write in DM is counted.
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
//! * the ALLOW lookup and the proc scan read the line numbers of the `code_only` view, which drift from
//!   the raw file after an unbalanced quote;
//! * `tracked_type_of` returns the first base of the var's type set that the owner is under; the
//!   Python's set is hash-ordered, so with two matching bases the message may name either (the site
//!   is the same). Here the set is sorted, so the shortest path wins.
//!
//! Not ported: `--report` (it stays in the Python script).

use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};


use crate::incr;
use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::parity::{ParseKind, Parity};
use crate::pat::Pat;
use crate::tree::{SourceFile, View, CODE_MAPS_DM};
use crate::util::{is_py_space, py_lstrip, py_rstrip, py_strip};
use crate::{pat, pat_match};

const LINT: &str = "tracked";
const HINT: &str = "write it through the setter, or `// ALLOW(tracked): <reason>`";

static META: Meta = Meta {
    name: "tracked",
    group: "",
    label: "tracked",
    legacy: "tools/ci/tracked_lint.py",
    select: CODE_MAPS_DM,
    scan: ScanKind::Tree,
    policy: Policy::Hard,
    rules: &[RuleMeta { name: "outside_setter", hint: HINT }],
    allow: &["tracked"],
    lists: &[],
};

/// The same writes in the test and benchmark trees, which `[lint.tracked]` exempts: a fixture that writes a tracked or stat var raw
/// leaves shared map state changed with no mark (a later test's refresh sweep reports REFRESH DRIFT on it). Shrink-only over
/// `tools/ci/tracked_tests_baseline.txt`; write through the setter (`A.set_equipment(...)`) or `set_var()` in a test.
static META_TESTS: Meta = Meta {
    name: "tracked_tests",
    group: "",
    label: "tracked_tests",
    legacy: "",
    select: CODE_MAPS_DM,
    scan: ScanKind::Tree,
    policy: Policy::Sites {
        baseline: "tools/ci/tracked_tests_baseline.txt",
        header: &[
            "tracked_tests: raw writes of TRACKED/SETTER/STAT/derive() vars in tests and benchmarks. rule<TAB>file<TAB>normalized line.",
            "Shrink-only: `analyze baseline --update --lint tracked_tests` drops fixed sites and never adds one.",
        ],
        banned: &[],
    },
    rules: &[RuleMeta { name: "outside_setter", hint: "a test writes state through its setter too (A.set_x(v)), or set_var() when it must restore it" }],
    allow: &["tracked"],
    lists: &[],
};

/// The test and benchmark trees `tracked_tests` reads (and `tracked` leaves to it).
const TEST_PREFIXES: &[&str] = &["code/modules/unit_tests/", "code/modules/benchmarks/", "code/tests/"];

const OPS: &str = r"(?:=(?!=)|\+=|-=|\*=|/=|\|=|&=|\^=|<<=|>>=|\+\+|--)";

/// `{var: {types}}` (the Python `tracked` dict of sets).
type Tracked = BTreeMap<String, BTreeSet<String>>;

fn is_subtype(path: &str, base: &str) -> bool {
    path == base || (path.starts_with(base) && path.as_bytes().get(base.len()) == Some(&b'/'))
}

/// `normalize_type`: strip, a leading `/`, no trailing `/`.
fn normalize_type(path: &str) -> String {
    let p = py_strip(path);
    let p = if p.starts_with('/') { p.to_string() } else { format!("/{}", p) };
    p.trim_end_matches('/').to_string()
}

/// `tracked_type_of`: the first tracked base of `var` that `owner` is under (may be "": the Python
/// treats that as falsy).
fn tracked_type_of(tracked: &Tracked, var: &str, owner: &str) -> Option<String> {
    tracked.get(var)?.iter().find(|base| is_subtype(owner, base)).cloned()
}

/// A top-level proc: `(owner, name, argument text, [(line number, line)])`.
struct Proc<'a> {
    owner: &'a str,
    name: &'a str,
    args: &'a str,
    body: Vec<(usize, &'a str)>,
}

/// `parse_procs(code)`: every top-level proc of a code view; type blocks are ignored (var defaults
/// are not writes).
fn parse_procs(code: &View) -> Vec<Proc<'_>> {
    let mut out = Vec::new();
    let mut current: Option<Proc> = None;
    for (number, line) in code.numbered() {
        if line.chars().next().map(|c| !is_py_space(c)).unwrap_or(false) {
            if let Some(cur) = current.take() {
                out.push(cur);
            }
            let stripped = py_rstrip(line);
            if stripped.starts_with('#') || pat_match!(r"/[\w/]+\s*$").is_match(stripped) {
                continue;
            }
            if let Some(m) = pat_match!(r"(/[\w/]*?)/(?:(?:proc|verb)/)?(\w+)\s*\((.*)$").captures(stripped) {
                let owner = if m.s(1).is_empty() { "/" } else { m.s(1) };
                current = Some(Proc { owner, name: m.s(2), args: m.s(3), body: Vec::new() });
            }
            continue;
        }
        if let Some(cur) = current.as_mut() {
            if !py_strip(line).is_empty() {
                cur.body.push((number, line));
            }
        }
    }
    if let Some(cur) = current {
        out.push(cur);
    }
    out
}

/// `tracked_from_text`: adds the vars this file declares tracked (TRACKED / SETTER lines, derive()
/// values) to `tracked`.
fn tracked_from_text(f: &SourceFile, tracked: &mut Tracked) {
    tracked_from_text_with(f, tracked, false)
}

/// `stats`: also the vars non-virtual STAT() declarations compose (`tracked_tests` only: in code the stat engine and the look builder
/// write them, and a few legacy sites still do).
fn tracked_from_text_with(f: &SourceFile, tracked: &mut Tracked, stats: bool) {
    let raw = f.text();
    if raw.contains("TRACKED") || raw.contains("SETTER(") {
        for line in f.raw().lines() {
            if py_lstrip(line).starts_with("#define") {
                continue;
            }
            let re = pat_match!(
                r"\s*(?:TRACKED(?:_BRIDGED)?\(\s*(/[\w/]+)\s*,\s*(\w+)\s*[,)]|SETTER\(\s*(/[\w/]+)\s*,\s*(\w+)\s*\))"
            );
            if let Some(m) = re.captures(line) {
                let var = if m.s(2).is_empty() { m.s(4) } else { m.s(2) };
                let path = if m.s(1).is_empty() { m.s(3) } else { m.s(1) };
                tracked.entry(var.to_string()).or_default().insert(normalize_type(path));
            }
        }
    }
    if raw.contains("derive(") {
        for p in parse_procs(f.code()) {
            if p.name != "derived" || p.owner == "/" {
                continue;
            }
            let text = p.body.iter().map(|(_, t)| *t).collect::<Vec<_>>().join("\n");
            for m in pat!(r"\bderive\(\s*nameof\(\s*(?:/[\w/]+::)?(\w+)\s*\)").captures_iter(&text) {
                tracked.entry(m.s(1).to_string()).or_default().insert(normalize_type(p.owner));
            }
        }
    }
    // STAT(T, name, rule, ...) declares a var the stat engine composes and writes; a virtual stat has no var.
    if stats && raw.contains("STAT(") {
        for line in f.raw().lines() {
            if py_lstrip(line).starts_with("#define") || line.contains("virtual = TRUE") {
                continue;
            }
            let re = pat_match!(r"^\s*STAT\(\s*(/[\w/]+)\s*,\s*(\w+)\s*,");
            if let Some(m) = re.captures(line) {
                tracked.entry(m.s(2).to_string()).or_default().insert(normalize_type(m.s(1)));
            }
        }
    }
}

/// The patterns built from the tracked names (`scan`).
struct Pats {
    /// does the raw text mention any tracked name at all (`any(v in raw for v in tracked)`)
    any: Pat,
    bare: Pat,
    dotted: Pat,
}

fn build_pats(tracked: &Tracked) -> Option<Pats> {
    if tracked.is_empty() {
        return None;
    }
    let mut escaped: Vec<String> = tracked.keys().map(|k| regex::escape(k)).collect();
    escaped.sort();
    let names = escaped.join("|");
    Some(Pats {
        any: Pat::new(&format!("(?:{})", names)),
        bare: Pat::new(&format!(
            r"(?<![\w.])(?:src\.)?({names})\s*{ops}|(?:\+\+|--)\s*(?<![\w.])(?:src\.)?({names})\b",
            names = names,
            ops = OPS
        )),
        dotted: Pat::new(&format!(r"(?<![\w.])(\w+)\.({names})\s*{ops}|(?:\+\+|--)\s*(\w+)\.({names})\b", names = names, ops = OPS)),
    })
}

/// One write outside a setter: the line and the message.
struct Hit {
    line: usize,
    msg: String,
}

/// `scan` for one file: its hits (in order) and the setters it defines `(owner, proc name)`.
fn scan_one(tracked: &Tracked, pats: &Pats, f: &SourceFile, sink: &mut Sink, named_args: &BTreeSet<(usize, usize)>) -> (Vec<Hit>, Vec<(String, String)>) {
    let mut hits = Vec::new();
    let mut setters = Vec::new();
    if !pats.any.is_match(f.text()) {
        return (hits, setters);
    }
    for p in parse_procs(f.clean()) {
        let owner = if p.owner != "/" { normalize_type(p.owner) } else { "/".to_string() };
        let mut is_setter_of: Option<String> = None;
        if let Some(var) = p.name.strip_prefix("set_") {
            if tracked_type_of(tracked, var, &owner).map(|b| !b.is_empty()).unwrap_or(false) {
                is_setter_of = Some(var.to_string());
                setters.push((owner.clone(), p.name.to_string()));
            }
        }
        let mut locals: HashSet<String> = HashSet::new();
        let mut typed: HashMap<String, String> = HashMap::new();
        let arg_typed = pat!(r"(?:^|[(,])\s*(?:var/)?((?:/?[\w]+/)*[\w]+)/(\w+)\s*(?==|,|\)|$|\bas\b)");
        for m in arg_typed.captures_iter(p.args) {
            typed.insert(m.s(2).to_string(), normalize_type(m.s(1)));
            locals.insert(m.s(2).to_string());
        }
        for (number, line) in &p.body {
            if py_lstrip(line).starts_with('#') {
                continue;
            }
            for m in pat!(r"\bvar/(?:[\w/]*/)?(\w+)\b").captures_iter(line) {
                locals.insert(m.s(1).to_string());
            }
            for m in pat!(r"(?:\bvar)?(/[\w/]+)/(\w+)\b").captures_iter(line) {
                typed.insert(m.s(2).to_string(), normalize_type(m.s(1)));
            }
            for m in pats.bare.captures_iter(line) {
                if named_args.contains(&(*number, m.start(0) + 1)) {
                    continue; // this exact AST expression names a call argument, not storage
                }
                let var = if m.s(1).is_empty() { m.s(2) } else { m.s(1) };
                if is_setter_of.as_deref() == Some(var) {
                    continue;
                }
                let written_via_src = m.whole().contains(&format!("src.{}", var));
                if locals.contains(var) && !written_via_src {
                    continue;
                }
                if Pat::cached(&format!(r"\bvar/(?:[\w/]*/)?{}\b", regex::escape(var))).is_match(line) {
                    continue;
                }
                let base = tracked_type_of(tracked, var, &owner).filter(|b| !b.is_empty());
                if let Some(base) = base {
                    if !sink.allowed(f, *number, LINT) {
                        hits.push(Hit { line: *number, msg: format!("{} written outside {}/proc/set_{}()", var, base, var) });
                    }
                }
            }
            for m in pats.dotted.captures_iter(line) {
                let holder = if m.s(1).is_empty() { m.s(3) } else { m.s(1) };
                let var = if m.s(2).is_empty() { m.s(4) } else { m.s(2) };
                if holder == "src" {
                    continue; // the bare pattern counts src.V
                }
                let base = typed.get(holder).and_then(|t| tracked_type_of(tracked, var, t)).filter(|b| !b.is_empty());
                if let Some(base) = base {
                    if !sink.allowed(f, *number, LINT) {
                        hits.push(Hit { line: *number, msg: format!("{}.{} written outside {}/proc/set_{}()", holder, var, base, var) });
                    }
                }
            }
        }
    }
    (hits, setters)
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
        if let Some(pats) = build_pats(&tracked) {
            let files: Vec<&SourceFile> = if self.tests {
                cx.all_files().into_iter().filter(|f| TEST_PREFIXES.iter().any(|p| f.rel.starts_with(p))).collect()
            } else {
                cx.files()
            };
            // Judge: each file's hits, cached while the merged index is unchanged.
            let semantic = cx.sem();
            let results: Vec<Vec<(u32, String)>> = incr::keyed(if self.tests { "tracked-tests-judge" } else { "tracked-judge" }, incr::ctx_key(&tracked), &files, |f| {
                let mut sink = Sink::new();
                sink.cur = f.rel.clone();
                let (hits, _setters) = scan_one(&tracked, &pats, f, &mut sink, &semantic.as_ref().map(|sem| crate::sem::checks::named_argument_positions(sem, &f.rel)).unwrap_or_default());
                for u in sink.allow_used {
                    crate::dm::sys::replay_recorded(vec![u]);
                }
                hits.into_iter().map(|h| (h.line as u32, h.msg)).collect()
            });
            for (f, hits) in files.iter().zip(results) {
                for (line, msg) in hits {
                    total += 1;
                    out.site_in_msg("outside_setter", &f.rel, line as usize, msg);
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
            let (hits, s) = scan_one(&tracked, &pats, f, &mut sink, &BTreeSet::new());
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
    reg.add(TestFaults);
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
        let (got, _) = scan_one(&tracked, &pats, &file, &mut Sink::new(), &named);
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
    fn named_argument_does_not_hide_real_assignment_on_same_line() {
        assert_eq!(hits("\tstate = 2; interface(\"SpaceHeater\", state = 1)"), vec![5]);
    }
}


// Explicit missed-publication fixtures use the tracked/type/proc indexes.
// This hard lint has no annotation escape hatch or baseline.
static META_FAULTS: Meta = Meta {
    name: "test_faults", group: "", label: "test_faults", legacy: "",
    select: CODE_MAPS_DM, scan: ScanKind::Tree, policy: Policy::Hard,
    rules: &[RuleMeta { name: "invalid_fault", hint: "an unpublished fault must target a declared allocate-owned tracked fixture field and assert actual missed-wake evidence" }],
    allow: &[], lists: &[],
};
const FAULT_DRIVER: &str = "code/tests/driver/publish_fault.dm";
// This is an executable contract, not a path exemption. The only raw write
// accepted by api belongs to this complete guarded, ownership-checked injector.
// Any operational change must update/review this contract and its rejection tests.
const FAULT_DRIVER_CONTRACT: &str = r###"#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)
#define TEST_FAULT_FIXTURE(T, FIELD) ##T/proc/__test_fault_unpublished_##FIELD() { return TYPE_PROC_REF(T, set_##FIELD) }
#define TEST_FAULT_MISSING_PUBLISH(TARGET, FIELD, VALUE) test_fault_missing_publish(TARGET, #FIELD, VALUE)
/datum/test_publish_fault
	var/field
	var/confirmed = FALSE
/datum/test_publish_fault/proc/confirm_missed_publish(actual_key)
	confirmed = istext(actual_key) && actual_key == field
	return confirmed
/proc/test_fault_missing_publish(datum/target, field, value)
	var/datum/unit_test/fixture = GLOB.current_test
	var/refusal = test_publish_fault_refusal(fixture, target, field)
	if(refusal)
		CRASH(refusal)
	var/datum/test_publish_fault/fault = fixture.allocate(/datum/test_publish_fault)
	fault.field = field
	var/restore_proc = call(target, "__test_fault_unpublished_[field]")()
	fixture.defer_cleanup(target, restore_proc, target.vars[field])
	fixture.defer_cleanup(fixture, TYPE_PROC_REF(/datum/unit_test, verify_publish_fault), fault)
	target.vars[field] = value
	return fault
/datum/unit_test/proc/verify_publish_fault(datum/test_publish_fault/fault)
	if(!fault?.confirmed)
		CRASH("unpublished test fault was not confirmed against actual missed-wake evidence")
/proc/test_publish_fault_refusal(datum/unit_test/fixture, datum/target, field)
	if(!fixture || QDELETED(fixture) || fixture != GLOB.current_test || !target || QDELETED(target) || !(target in fixture.allocated))
		return "unpublished test fault needs the current fixture's allocate-tracked target"
	if(!istext(field) || !(field in target.vars) || !hascall(target, "__setter_[field]") || !hascall(target, "__test_fault_unpublished_[field]"))
		return "unpublished test fault needs a declared tracked fixture field"
	return null
#endif
"###;

fn valid_fault_driver(f: &SourceFile) -> bool {
    if f.rel != FAULT_DRIVER { return false; }
    let expected = SourceFile::from_text(FAULT_DRIVER, FAULT_DRIVER_CONTRACT);
    let operational = |s: &SourceFile| s.code().lines().map(str::trim).filter(|line| !line.is_empty()).map(str::to_owned).collect::<Vec<_>>();
    operational(f) == operational(&expected)
}

pub(crate) fn validated_fault_driver_write(f: &SourceFile, line: usize) -> bool {
    valid_fault_driver(f) && f.code().line(line).trim() == "target.vars[field] = value"
}

fn test_path(rel: &str) -> bool {
    rel.starts_with("code/modules/unit_tests/") || rel.starts_with("code/tests/")
}

// All direct declarations of a fixture type must be in the test tree. A test
// subtype of a production type is fine; declaring a production type as a test
// fixture is not. Track only setters, not derived-only or STAT-composed fields.
fn authored_fault_source(rel: &str) -> bool {
    !rel.starts_with("code/engine/_generated/") && !rel.starts_with("code/_generated/")
}

fn fault_markers(files: &[&SourceFile], tracked: &Tracked) -> (BTreeSet<(String, String)>, Vec<(String, usize, String)>) {
    let mut declared: BTreeMap<String, BTreeSet<String>> = BTreeMap::new();
    for f in files {
        if !authored_fault_source(&f.rel) { continue; }
        for (_, line) in f.code().numbered() {
            if let Some(m) = pat_match!(r"^(/[\w/]+)\s*$").captures(line) {
                declared.entry(m.s(1).to_owned()).or_default().insert(f.rel.clone());
            }
        }
    }
    // A production proc/var override also establishes production ownership,
    // even when its file has no bare type declaration.
    for f in files {
        if test_path(&f.rel) || !authored_fault_source(&f.rel) { continue; }
        for proc in parse_procs(f.code()) {
            declared.entry(proc.owner.to_owned()).or_default().insert(f.rel.clone());
        }
        for (_, line) in f.code().numbered() {
            if let Some(m) = pat!(r"\b(?:TRACKED(?:_BRIDGED)?|SETTER)\(\s*(/[\w/]+)\s*,").captures(line) {
                declared.entry(m.s(1).to_owned()).or_default().insert(f.rel.clone());
            }
            if let Some(m) = pat_match!(r"^(/[\w/]+)/var/").captures(line) {
                declared.entry(m.s(1).to_owned()).or_default().insert(f.rel.clone());
            }
        }
    }
    let mut markers = BTreeSet::new();
    let mut invalid = Vec::new();
    for f in files {
        for (n, line) in f.code().numbered() {
            if line.trim_start().starts_with("#define") { continue; }
            if let Some(m) = pat!(r"\bTEST_FAULT_FIXTURE\(\s*(/[\w/]+)\s*,\s*(\w+)\s*\)").captures(line) {
                let ty = m.s(1); let field = m.s(2);
                let safe_type = declared.get(ty).is_some_and(|ds| !ds.is_empty() && ds.iter().all(|rel| test_path(rel)));
                if !test_path(&f.rel) || !safe_type || tracked_type_of(tracked, field, ty).is_none() {
                    invalid.push((f.rel.clone(), n, "fault fixture must be a test-defined type with a real tracked setter".to_owned()));
                } else { markers.insert((ty.to_owned(), field.to_owned())); }
            }
        }
    }
    (markers, invalid)
}

fn invalid_faults(f: &SourceFile, markers: &BTreeSet<(String, String)>) -> Vec<(usize, String)> {
    let mut invalid = Vec::new();
    if f.rel == FAULT_DRIVER && !valid_fault_driver(f) {
        invalid.push((1, "test fault driver must retain the guarded, ownership-checked injection and real setter restoration contract".to_owned()));
    }
    // The low-level injector is implementation-only. Every call site must use
    // the typed declaration form below, including in tests.
    if f.rel != FAULT_DRIVER {
        for (n, line) in f.code().numbered() {
            if pat!(r"\btest_fault_missing_publish\s*\(").is_match(line) {
                invalid.push((n, "call the fault declaration form; the injector is implementation-only".to_owned()));
            }
        }
    }
    let mut checked_lines = HashSet::new();
    for proc in parse_procs(f.code()) {
        let mut typed: HashMap<String, String> = HashMap::new();
        let mut allocated: HashSet<String> = HashSet::new();
        for (idx, (n, line)) in proc.body.iter().enumerate() {
            if let Some(m) = pat!(r"\bvar(/[^\s=]+)/([\w]+)\s*=\s*allocate\(").captures(line) {
                typed.insert(m.s(2).to_owned(), m.s(1).to_owned());
                allocated.insert(m.s(2).to_owned());
            }
            if !line.contains("TEST_FAULT_MISSING_PUBLISH") { continue; }
            checked_lines.insert(*n);
            let Some(m) = pat_match!(r"^\s*var/datum/test_publish_fault/(\w+)\s*=\s*TEST_FAULT_MISSING_PUBLISH\(\s*(\w+)\s*,\s*(\w+)\s*,").captures(line) else {
                invalid.push((*n, "bind a fault token with a typed allocate-owned local target and a literal field".to_owned())); continue;
            };
            let token = m.s(1); let target = m.s(2); let field = m.s(3);
            let valid_target = typed.get(target).is_some_and(|ty| allocated.contains(target) && markers.contains(&(ty.clone(), field.to_owned())));
            if !test_path(&f.rel) || !is_subtype(proc.owner, "/datum/unit_test") || !valid_target {
                invalid.push((*n, "faults are restricted to unit-test procs and declared allocate-owned fixture fields".to_owned())); continue;
            }
            // Evidence must come from the real audit of the injected target,
            // not an arbitrary datum with a matching .key field.
            let audit = Pat::cached(&format!(r"^\s*var/datum/seq_step/(\w+)\s*=\s*(\w+)\.missed_wake\(\s*{}\s*\)\s*$", regex::escape(target)));
            let mut actual = false;
            for (proof_idx, (_, later)) in proc.body.iter().enumerate().skip(idx + 1) {
                let Some(found) = audit.captures(later) else { continue };
                let evidence = found.s(1);
                let receiver = found.s(2);
                // A matching method name is not proof: require the engine's
                // typed definition getter before injection, with no rebinding.
                let binding = Pat::cached(&format!(r"^\s*var/datum/sequence/{}\s*=\s*sequence_def\(\s*\w+\s*\)\s*$", regex::escape(receiver)));
                let rebind = Pat::cached(&format!(r"^\s*(?:var(?:/[\w]+)*/)?{}\s*(?:=(?!=)|\+=|-=|\*=|/=|\+\+|--)", regex::escape(receiver)));
                let mut definition_bound = false;
                for (_, preceding) in proc.body.iter().take(idx) {
                    if binding.is_match(preceding) { definition_bound = true; }
                    else if rebind.is_match(preceding) { definition_bound = false; }
                }
                if !definition_bound || proc.body.iter().take(proof_idx).skip(idx + 1).any(|(_, between)| rebind.is_match(between)) { continue; }
                let proof = Pat::cached(&format!(r"^\s*TEST_ASSERT\(\s*{}\.confirm_missed_publish\(\s*{}\??\.key\s*\)", regex::escape(token), regex::escape(evidence)));
                let overwrite = Pat::cached(&format!(r"^\s*(?:{}|{})\s*=(?!=)", regex::escape(token), regex::escape(evidence)));
                for (_, following) in proc.body.iter().skip(proof_idx + 1) {
                    if overwrite.is_match(following) || rebind.is_match(following) { break; }
                    if proof.is_match(following) { actual = true; break; }
                }
                if actual { break; }
            }
            if !actual {
                invalid.push((*n, "assert the token against an actual missed_wake(target) result after injection".to_owned()));
            }
        }
    }
    for (n, line) in f.code().numbered() {
        if f.rel == FAULT_DRIVER && line.trim_start().starts_with("#define") { continue; }
        if line.contains("TEST_FAULT_MISSING_PUBLISH") && !checked_lines.contains(&n) {
            invalid.push((n, "fault declaration must be a statement in a unit-test proc".to_owned()));
        }
        if line.trim_start().starts_with("#define") && line.contains("TEST_FAULT_FIXTURE") {
            invalid.push((n, "the fixture-marker declaration form cannot be redefined".to_owned()));
        }
    }
    invalid
}

fn fault_setter_fields(f: &SourceFile, tracked: &mut Tracked) {
    // Unlike the ordinary tracked index, this deliberately excludes derive()
    // and STAT-composed values: faults need a real restoration setter.
    for line in f.code().lines() {
        if line.trim_start().starts_with("#define") { continue; }
        if let Some(m) = pat!(r"\b(?:TRACKED(?:_BRIDGED)?|SETTER)\(\s*(/[\w/]+)\s*,\s*(\w+)").captures(line) {
            tracked.entry(m.s(2).to_owned()).or_default().insert(m.s(1).to_owned());
        }
    }
}

struct TestFaults;
impl Lint for TestFaults {
    fn meta(&self) -> &Meta { &META_FAULTS }
    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        let files = cx.all_files();
        let mut tracked = Tracked::new();
        for f in &files { fault_setter_fields(f, &mut tracked); }
        let (markers, invalid) = fault_markers(&files, &tracked);
        for (file, line, message) in invalid { out.site_in_msg("invalid_fault", &file, line, message); }
        for f in files {
            for (line, message) in invalid_faults(f, &markers) {
                out.site_in_msg("invalid_fault", &f.rel, line, message);
            }
        }
    }
}


#[cfg(test)]
mod fault_contract_tests {
    use super::*;
    fn source(rel: &str, code: &str) -> SourceFile { SourceFile::from_text(rel, code) }
    fn judge(rel: &str, body: &str) -> Vec<(usize, String)> {
        let markers = BTreeSet::from([("/datum/fixture".to_owned(), "heat".to_owned())]);
        invalid_faults(&source(rel, body), &markers)
    }
    const GOOD: &str = "/datum/unit_test/probe/Run()\n\tvar/datum/fixture/E = allocate(/datum/fixture)\n\tvar/datum/sequence/def = sequence_def(SEQ_TEST)\n\tvar/datum/test_publish_fault/F = TEST_FAULT_MISSING_PUBLISH(E, heat, 7)\n\tvar/datum/seq_step/missed = def.missed_wake(E)\n\tTEST_ASSERT(F.confirm_missed_publish(missed?.key), \"observed actual fault\")\n";
    #[test] fn valid_tracked_fixture_and_actual_proof() { assert!(judge("code/modules/unit_tests/probe.dm", GOOD).is_empty()); }
    #[test] fn forged_audit_receiver_type_rejected() {
        assert!(!judge("code/modules/unit_tests/probe.dm", &GOOD.replace("var/datum/sequence/def = sequence_def(SEQ_TEST)", "var/datum/fake_same_named/def = allocate(/datum/fake_same_named)")).is_empty());
    }
    #[test] fn reassigned_definition_before_injection_rejected() {
        assert!(!judge("code/modules/unit_tests/probe.dm", &GOOD.replace("\tvar/datum/test_publish_fault/F", "\tdef = fake_same_named()\n\tvar/datum/test_publish_fault/F")).is_empty());
    }
    #[test] fn reassigned_definition_before_audit_rejected() {
        assert!(!judge("code/modules/unit_tests/probe.dm", &GOOD.replace("\tvar/datum/seq_step/missed", "\tdef = fake_same_named()\n\tvar/datum/seq_step/missed")).is_empty());
    }
    #[test] fn reassigned_definition_before_confirmation_rejected() {
        assert!(!judge("code/modules/unit_tests/probe.dm", &GOOD.replace("\tTEST_ASSERT(F", "\tdef = fake_same_named()\n\tTEST_ASSERT(F")).is_empty());
    }
    #[test] fn production_call_rejected() { assert!(!judge("code/game/machinery/probe.dm", GOOD).is_empty()); }
    #[test] fn production_owner_in_test_file_rejected() { assert!(!judge("code/modules/unit_tests/probe.dm", &GOOD.replace("/datum/unit_test/probe/Run", "/obj/machine/proc/work")).is_empty()); }
    #[test] fn unknown_field_rejected() { assert!(!judge("code/modules/unit_tests/probe.dm", &GOOD.replace("E, heat,", "E, unknown,")).is_empty()); }
    #[test] fn borrowed_target_rejected() { assert!(!judge("code/modules/unit_tests/probe.dm", &GOOD.replace("allocate(/datum/fixture)", "get_map_object()")).is_empty()); }
    #[test] fn no_confirmation_rejected() { assert!(!judge("code/modules/unit_tests/probe.dm", &GOOD.replace("TEST_ASSERT(F.confirm_missed_publish(missed?.key),", "TEST_ASSERT(TRUE,")).is_empty()); }
    #[test] fn constant_confirmation_rejected() { assert!(!judge("code/modules/unit_tests/probe.dm", &GOOD.replace("missed?.key", "\"heat\"")).is_empty()); }
    #[test] fn nonproc_macro_call_rejected() { assert!(!judge("code/modules/unit_tests/probe.dm", "#define BAD TEST_FAULT_MISSING_PUBLISH(E, heat, 7)\n").is_empty()); }
    #[test] fn redefined_fixture_marker_rejected() { assert!(!judge("code/modules/unit_tests/probe.dm", "#define TEST_FAULT_FIXTURE(T,V) 1\n").is_empty()); }
    #[test] fn injector_backdoor_rejected() { assert!(!judge("code/modules/unit_tests/probe.dm", "/datum/unit_test/probe/Run()\n\ttest_fault_missing_publish(E, \"heat\", 7)\n").is_empty()); }
    #[test] fn production_fixture_registration_rejected() {
        let production = source("code/game/object.dm", "/datum/fixture\n\tvar/heat\nTRACKED(/datum/fixture, heat)\n");
        let test = source("code/modules/unit_tests/probe.dm", "TEST_FAULT_FIXTURE(/datum/fixture, heat)\n");
        let mut tracked = Tracked::new(); tracked_from_text(&production, &mut tracked);
        let (markers, invalid) = fault_markers(&[&production, &test], &tracked);
        assert!(markers.is_empty()); assert_eq!(invalid.len(), 1);
    }
    #[test] fn test_fixture_registration_requires_setter() {
        let test = source("code/modules/unit_tests/probe.dm", "/datum/fixture\n\tvar/heat\nTEST_FAULT_FIXTURE(/datum/fixture, heat)\n");
        let (markers, invalid) = fault_markers(&[&test], &Tracked::new());
        assert!(markers.is_empty()); assert_eq!(invalid.len(), 1);
    }
    #[test] fn forged_key_object_rejected() {
        assert!(!judge("code/modules/unit_tests/probe.dm", &GOOD.replace("def.missed_wake(E)", "fake_result()")).is_empty());
    }
    #[test] fn wrong_audited_target_rejected() {
        assert!(!judge("code/modules/unit_tests/probe.dm", &GOOD.replace("def.missed_wake(E)", "def.missed_wake(other)")).is_empty());
    }
    #[test] fn overwritten_evidence_rejected() {
        assert!(!judge("code/modules/unit_tests/probe.dm", &GOOD.replace("\tTEST_ASSERT(F", "\tmissed = fake_result()\n\tTEST_ASSERT(F")).is_empty());
    }
    #[test] fn generated_fixture_override_preserves_authored_ownership() {
        let generated = source("code/engine/_generated/test_fixture.dm", "#if defined(UNIT_TESTS)\n/datum/fixture/proc/work()\n\treturn\n#endif\n");
        let test = source("code/modules/unit_tests/probe.dm", "/datum/fixture\n\tvar/heat\nTRACKED(/datum/fixture, heat)\nTEST_FAULT_FIXTURE(/datum/fixture, heat)\n");
        let mut tracked = Tracked::new(); fault_setter_fields(&test, &mut tracked);
        let (markers, invalid) = fault_markers(&[&generated, &test], &tracked);
        assert_eq!(markers.len(), 1); assert!(invalid.is_empty());
        assert!(!invalid_faults(&source("code/engine/_generated/bad.dm", GOOD), &markers).is_empty());
    }
    #[test] fn production_proc_override_registration_rejected() {
        let production = source("code/game/object.dm", "/datum/fixture/proc/work()\n\treturn\n");
        let test = source("code/modules/unit_tests/probe.dm", "/datum/fixture\n\tvar/heat\nTRACKED(/datum/fixture, heat)\nTEST_FAULT_FIXTURE(/datum/fixture, heat)\n");
        let mut tracked = Tracked::new(); fault_setter_fields(&test, &mut tracked);
        let (markers, invalid) = fault_markers(&[&production, &test], &tracked);
        assert!(markers.is_empty()); assert_eq!(invalid.len(), 1);
    }

}

#[cfg(test)]
mod fault_driver_api_tests {
    use super::*;
    fn raw_writes(f: &SourceFile) -> Vec<usize> {
        let pat = Pat::new(r"\bvars\[[^\]]*\]\s*=(?!=)");
        f.code().numbered().filter(|(line, code)| pat.is_match(code) && !validated_fault_driver_write(f, *line)).map(|(line, _)| line).collect()
    }
    #[test] fn exact_validated_driver_write_is_accepted() {
        let f = SourceFile::from_text(FAULT_DRIVER, FAULT_DRIVER_CONTRACT);
        assert!(raw_writes(&f).is_empty());
        assert!(invalid_faults(&f, &BTreeSet::new()).is_empty());
    }
    #[test] fn copied_driver_in_arbitrary_test_file_is_rejected() {
        let f = SourceFile::from_text("code/tests/driver/other.dm", FAULT_DRIVER_CONTRACT);
        assert_eq!(raw_writes(&f).len(), 1);
        assert!(!invalid_faults(&f, &BTreeSet::new()).is_empty());
    }
    #[test] fn extra_raw_write_in_driver_is_rejected() {
        let code = FAULT_DRIVER_CONTRACT.replace("target.vars[field] = value", "target.vars[field] = value\n\ttarget.vars[other] = value");
        let f = SourceFile::from_text(FAULT_DRIVER, &code);
        assert_eq!(raw_writes(&f).len(), 2);
        assert!(!invalid_faults(&f, &BTreeSet::new()).is_empty());
    }
    #[test] fn missing_guard_is_rejected() {
        let code = FAULT_DRIVER_CONTRACT.replace("#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)", "");
        let f = SourceFile::from_text(FAULT_DRIVER, &code);
        assert_eq!(raw_writes(&f).len(), 1);
        assert!(!invalid_faults(&f, &BTreeSet::new()).is_empty());
    }
    #[test] fn bypassed_ownership_preflight_is_rejected() {
        let code = FAULT_DRIVER_CONTRACT.replace("test_publish_fault_refusal(fixture, target, field)", "null");
        let f = SourceFile::from_text(FAULT_DRIVER, &code);
        assert_eq!(raw_writes(&f).len(), 1);
        assert!(!invalid_faults(&f, &BTreeSet::new()).is_empty());
    }
    #[test] fn missing_real_setter_restoration_is_rejected() {
        let code = FAULT_DRIVER_CONTRACT.replace("fixture.defer_cleanup(target, restore_proc, target.vars[field])", "return");
        let f = SourceFile::from_text(FAULT_DRIVER, &code);
        assert_eq!(raw_writes(&f).len(), 1);
        assert!(!invalid_faults(&f, &BTreeSet::new()).is_empty());
    }
}

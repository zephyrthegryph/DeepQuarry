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

struct Tracker;

impl Lint for Tracker {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        // Facts: the vars each file declares tracked (cached by content); merged into one index.
        let all = cx.all_files();
        let facts: Vec<Vec<(String, String)>> = incr::facts("tracked-facts", &all, |f| {
            let mut t: Tracked = BTreeMap::new();
            tracked_from_text(f, &mut t);
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
            let files = cx.files();
            // Judge: each file's hits, cached while the merged index is unchanged.
            let semantic = cx.sem();
            let results: Vec<Vec<(u32, String)>> = incr::keyed("tracked-judge", incr::ctx_key(&tracked), &files, |f| {
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
    reg.add(Tracker);
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
    fn bare_state_assignment_remains_a_violation() {
        assert_eq!(hits("\tstate = 1"), vec![5]);
    }
    #[test]
    fn named_argument_does_not_hide_real_assignment_on_same_line() {
        assert_eq!(hits("\tstate = 2; interface(\"SpaceHeater\", state = 1)"), vec![5]);
    }
}

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

use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};


use crate::incr;
use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::parity::{ParseKind, Parity};
use crate::pat::Pat;
use crate::tree::{SourceFile, View, CODE_DM, CODE_MAPS_DM};
use crate::util::{is_py_space, py_lstrip, py_rstrip, py_strip};
use crate::{pat, pat_match};

const LINT: &str = "tracked";
const HINT: &str = "write it through the setter, or `// ALLOW(tracked): <reason>`";
const LIST_HINT: &str = "mutate a tracked list through its generated add_<v>() / include_<v>() / remove_<v>() / set_<v>_at() / clear_<v>() (`analyze fix` rewrites most); a raw edit publishes nothing";

static META: Meta = Meta {
    name: "tracked",
    group: "",
    label: "tracked",
    legacy: "tools/ci/tracked_lint.py",
    select: CODE_MAPS_DM,
    scan: ScanKind::Tree,
    policy: Policy::Hard,
    rules: &[RuleMeta { name: "outside_setter", hint: HINT }, RuleMeta { name: "list_mutation", hint: LIST_HINT }],
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
    rules: &[RuleMeta { name: "outside_setter", hint: "a test writes state through its setter too (A.set_x(v)), or set_var() when it must restore it" }, RuleMeta { name: "list_mutation", hint: LIST_HINT }],
    allow: &["tracked"],
    lists: &[],
};

/// The test and benchmark trees `tracked_tests` reads (and `tracked` leaves to it).
const TEST_PREFIXES: &[&str] = &["code/modules/unit_tests/", "code/modules/benchmarks/", "code/tests/"];

/// The procs that construct an instance. A write of the instance's own tracked var there (`v = x`, `src.v = x`, `LAZYADD(v, x)`) is the construction of
/// the instance, not a change of a live one: nothing reads or watches an object that is still being built, so the write sets the var and publishes
/// nothing (the same as a type-level default, which is not a write either). A write to a part of the instance a loop walks (`for(var/T/P in ports)`, `P.v = x`) is the same construction. A write to ANOTHER object's tracked var (`O.v = x`) is judged as anywhere
/// else, and so is a write in `on_holder_init()`, `after_init()` and every other proc, which run once the holder is live. The init lint counts each
/// imperative line of an `Initialize()` body (`init_lines`), so rewriting these lines to setter calls would also change their fingerprints and read as
/// new init debt: the two lints agree by leaving construction alone.
const PRE_LIVE: &[&str] = &["Initialize", "New"];

const OPS: &str = r"(?:=(?!=)|\+=|-=|\*=|/=|\|=|&=|\^=|<<=|>>=|\+\+|--)";

/// `{var: {types}}` (the Python `tracked` dict of sets).
type Tracked = BTreeMap<String, BTreeSet<String>>;

fn is_subtype(path: &str, base: &str) -> bool {
    let (path, base) = (builtin_full_path(path), builtin_full_path(base));
    path == base || (path.starts_with(base.as_str()) && path.as_bytes().get(base.len()) == Some(&b'/'))
}

/// DM's implicit parents: `/obj` and `/mob` are `/atom/movable/...`, `/turf` and `/area` are `/atom/...`. A `SETTER(/atom, dir)` covers a
/// proc of `/obj/item/x` only when the path is compared in full.
fn builtin_full_path(path: &str) -> String {
    for (short, full) in [("/obj", "/atom/movable/obj"), ("/mob", "/atom/movable/mob"), ("/turf", "/atom/turf"), ("/area", "/atom/area")] {
        if path == short || (path.starts_with(short) && path.as_bytes().get(short.len()) == Some(&b'/')) {
            return format!("{}{}", full, &path[short.len()..]);
        }
    }
    path.to_string()
}

/// A bare `name = x` at `pos` that is a named argument of a call the AST did not see (inside a macro's arguments, `image(...)` or
/// `new/icon(...)`): the text before it on the line is `call(` or `..., ` at a paren depth above zero, and the innermost open paren is a
/// call's, not `for(`/`if(`/`while(`/`switch(`.
fn in_call_args(line: &str, pos: usize) -> bool {
    let before = &line[..pos];
    match before.trim_end().chars().last() {
        Some('(') | Some(',') => {}
        _ => return false,
    }
    let bytes = before.as_bytes();
    let mut depth = 0i32;
    let mut i = bytes.len();
    while i > 0 {
        i -= 1;
        match bytes[i] {
            b')' | b']' => depth += 1,
            b'(' | b'[' if depth > 0 => depth -= 1,
            b'(' => {
                let head = before[..i].trim_end();
                let word: String = head.chars().rev().take_while(|c| c.is_alphanumeric() || *c == '_' || *c == '/').collect::<Vec<_>>().into_iter().rev().collect();
                return !word.is_empty() && !matches!(word.as_str(), "for" | "if" | "while" | "switch" | "return");
            }
            b'[' => return false,
            _ => {}
        }
    }
    false
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
                r"\s*(?:TRACKED\(\s*(/[\w/]+)\s*,\s*(\w+)\s*[,)]|SETTER\(\s*(/[\w/]+)\s*,\s*(\w+)\s*\))"
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

/// One write outside a setter: the line, the message, the rule, and (for a list mutation `analyze fix` can rewrite) the edit.
struct Hit {
    line: usize,
    msg: String,
    rule: u8,
    fix: Option<Fix>,
}

/// Rule indexes (the order of `Meta::rules`).
const RULE_SETTER: u8 = 0;
const RULE_LIST: u8 = 1;

/// A single-line edit: bytes `start..end` of the line become `text`; `was` is the text it expects there.
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord, serde::Serialize, serde::Deserialize, Default)]
pub struct Fix {
    pub start: u32,
    pub end: u32,
    pub was: String,
    pub text: String,
    /// Further edits of the same rewrite on later lines (a multi-line right-hand side closes its setter call where it ends).
    pub more: Vec<MoreEdit>,
}

/// An edit of a [`Fix`] on a later line: `line_off` lines after the hit's.
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord, serde::Serialize, serde::Deserialize, Default)]
pub struct MoreEdit {
    pub line_off: u32,
    pub start: u32,
    pub end: u32,
    pub was: String,
    pub text: String,
}

/// The in-place list mutations of tracked list vars (`LAZYADD(v, x)`, `v.Add(x)`, `v[i] = x`).
struct ListPats {
    r#macro: Pat,
    method: Pat,
    index: Pat,
}

fn build_list_pats(lists: &Tracked) -> Option<ListPats> {
    if lists.is_empty() {
        return None;
    }
    let mut escaped: Vec<String> = lists.keys().map(|k| regex::escape(k)).collect();
    escaped.sort();
    let names = escaped.join("|");
    Some(ListPats {
        r#macro: Pat::new(&format!(r"\b(LAZY(?:ADD|REMOVE|OR|DISTINCTADD|SET|CLEARLIST|NULL))\(\s*(?:(\w+)\.)?({names})\s*[,)]", names = names)),
        method: Pat::new(&format!(r"(?<![\w.])(?:(\w+)\.)?({names})\.(Add|Remove|Cut|Insert|Swap)\(", names = names)),
        index: Pat::new(&format!(r"(?<![\w.])(?:(\w+)\.)?({names})\s*\[(?:[^\[\]]|\[[^\]]*\])*\]\s*{ops}", names = names, ops = OPS)),
    })
}

/// The index of the `)` closing the `(` at `open`, in `line` (strings and comments are blanked in the clean view).
fn close_paren(line: &str, open: usize) -> Option<usize> {
    let mut depth = 0i32;
    for (i, c) in line[open..].char_indices() {
        match c {
            '(' => depth += 1,
            ')' => {
                depth -= 1;
                if depth == 0 {
                    return Some(open + i);
                }
            }
            _ => {}
        }
    }
    None
}

/// Top-level argument spans (byte ranges into `line`) of the call whose `(` is at `open` and `)` at `close`.
fn arg_spans(line: &str, open: usize, close: usize) -> Vec<(usize, usize)> {
    let mut spans = Vec::new();
    let (mut depth, mut start) = (0i32, open + 1);
    for (i, c) in line[open + 1..close].char_indices() {
        let at = open + 1 + i;
        match c {
            '(' | '[' | '{' => depth += 1,
            ')' | ']' | '}' => depth -= 1,
            ',' if depth == 0 => {
                spans.push((start, at));
                start = at + 1;
            }
            _ => {}
        }
    }
    if !line[start..close].trim().is_empty() || !spans.is_empty() {
        spans.push((start, close));
    }
    spans
}

/// The call prefix a holder text gives the generated proc: `src` and none are the bare form.
fn holder_prefix(holder: &str) -> String {
    if holder.is_empty() || holder == "src" {
        String::new()
    } else {
        format!("{holder}.")
    }
}

/// The rewrite of one list mutation, or None when it is not a plain statement-level form `analyze fix` can express.
/// `clean` and `raw` are the same line; `m_start` is where the match starts.
fn list_fix(clean: &str, raw: &str, kind: &str, m_start: usize, holder: &str, var: &str, form: &str) -> Option<Fix> {
    if clean.len() != raw.len() {
        return None;
    }
    let pre = holder_prefix(holder);
    let arg = |a: (usize, usize)| raw[a.0..a.1].trim().to_string();
    match kind {
        "macro" => {
            let open = m_start + form.len();
            if clean.as_bytes().get(open) != Some(&b'(') {
                return None;
            }
            let close = close_paren(clean, open)?;
            let spans = arg_spans(clean, open, close);
            let text = match (form, spans.len()) {
                ("LAZYADD", 2) => format!("{pre}add_{var}({})", arg(spans[1])),
                ("LAZYREMOVE", 2) => format!("{pre}remove_{var}({})", arg(spans[1])),
                ("LAZYOR" | "LAZYDISTINCTADD", 2) => format!("{pre}include_{var}({})", arg(spans[1])),
                ("LAZYSET", 3) => format!("{pre}set_{var}_at({}, {})", arg(spans[1]), arg(spans[2])),
                ("LAZYCLEARLIST", 1) => format!("{pre}clear_{var}()"),
                ("LAZYNULL", 1) => format!("{pre}set_{var}(null)"),
                _ => return None,
            };
            Some(Fix { start: m_start as u32, end: close as u32 + 1, was: raw[m_start..=close].to_string(), text, more: Vec::new() })
        }
        "method" => {
            // A statement: nothing before it on the line, and the call closes the line.
            if !clean[..m_start].trim().is_empty() {
                return None;
            }
            let open = clean[m_start..].find(&format!(".{form}("))? + m_start + 1 + form.len();
            let close = close_paren(clean, open)?;
            if !clean[close + 1..].trim().trim_start_matches(';').trim().is_empty() {
                return None;
            }
            let spans = arg_spans(clean, open, close);
            let text = match (form, spans.len()) {
                ("Add", 1) => format!("{pre}add_{var}({})", arg(spans[0])),
                ("Add", n) if n > 1 => format!("{pre}add_{var}(list({}))", spans.iter().map(|s| arg(*s)).collect::<Vec<_>>().join(", ")),
                ("Remove", 1) => format!("{pre}remove_{var}({})", arg(spans[0])),
                ("Remove", n) if n > 1 => format!("{pre}remove_{var}(list({}))", spans.iter().map(|s| arg(*s)).collect::<Vec<_>>().join(", ")),
                ("Cut", 0) => format!("{pre}clear_{var}()"),
                ("Cut", 1 | 2) => format!("{pre}cut_{var}({})", spans.iter().map(|s| arg(*s)).collect::<Vec<_>>().join(", ")),
                ("Insert", 2) => format!("{pre}insert_{var}({}, {})", arg(spans[0]), arg(spans[1])),
                ("Swap", 2) => format!("{pre}swap_{var}({}, {})", arg(spans[0]), arg(spans[1])),
                _ => return None,
            };
            Some(Fix { start: m_start as u32, end: close as u32 + 1, was: raw[m_start..=close].to_string(), text, more: Vec::new() })
        }
        "index" => {
            if !clean[..m_start].trim().is_empty() {
                return None;
            }
            let name_at = clean[m_start..].find(var)? + m_start;
            let open = clean[name_at..].find('[')? + name_at;
            let mut depth = 0i32;
            let mut close = None;
            for (i, c) in clean[open..].char_indices() {
                match c {
                    '[' => depth += 1,
                    ']' => {
                        depth -= 1;
                        if depth == 0 {
                            close = Some(open + i);
                            break;
                        }
                    }
                    _ => {}
                }
            }
            let close = close?;
            let after = clean[close + 1..].trim_start();
            let rest = after.strip_prefix('=')?;
            if rest.starts_with('=') {
                return None;
            }
            let end = clean.trim_end().trim_end_matches(';').trim_end().len();
            let value_start = clean.len() - rest.len();
            let value = raw[value_start..end].trim();
            if value.is_empty() || value.matches(['(', '[', '{']).count() != value.matches([')', ']', '}']).count() {
                return None; // a value that continues on the next line
            }
            let idx = raw[open + 1..close].trim();
            Some(Fix { start: m_start as u32, end: end as u32, was: raw[m_start..end].to_string(), text: format!("{pre}set_{var}_at({idx}, {value})"), more: Vec::new() })
        }
        _ => None,
    }
}

/// Whether `prefix` (the clean text before a write) leaves the write a statement of its own: nothing, `else`, `if(...)` or `else if(...)`.
fn statement_prefix_ok(prefix: &str) -> bool {
    let p = prefix.trim();
    if p.is_empty() {
        return true;
    }
    // A statement before it on the same line (`a = 1; b = 2`): the prefix is whole statements when its brackets balance.
    if p.ends_with(';') {
        let mut depth = 0i32;
        for c in p.chars() {
            match c {
                '(' | '[' | '{' => depth += 1,
                ')' | ']' | '}' => depth -= 1,
                _ => {}
            }
        }
        return depth == 0;
    }
    let p = match p.strip_prefix("else") {
        Some(rest) if rest.is_empty() || rest.starts_with(char::is_whitespace) || rest.starts_with('(') => rest.trim_start(),
        _ => p,
    };
    if p.is_empty() {
        return true;
    }
    let Some(rest) = p.strip_prefix("if") else { return false };
    let rest = rest.trim_start();
    if !rest.starts_with('(') {
        return false;
    }
    close_paren(rest, 0) == Some(rest.len() - 1)
}

/// Where the statement whose right-hand side starts at `(line, col)` ends: the first `;` at depth 0, or the end of the line that closes every
/// bracket opened on the way. Returns `(line_off, end_col)` of the last non-blank character plus one, or None when the statement continues in a
/// way this cannot follow (a trailing `\`, a bracket closed that this statement did not open, no end within 80 lines).
fn statement_end(clean: &[&str], line: usize, col: usize) -> Option<(usize, usize)> {
    let mut depth = 0i32;
    let mut last: Option<(usize, usize)> = None;
    for off in 0..80 {
        let text = clean.get(line - 1 + off)?;
        let start = if off == 0 { col } else { 0 };
        let mut stopped = false;
        for (i, c) in text[start..].char_indices() {
            let at = start + i;
            match c {
                '(' | '[' | '{' => depth += 1,
                ')' | ']' | '}' => {
                    depth -= 1;
                    if depth < 0 {
                        return None;
                    }
                }
                ';' if depth == 0 => {
                    stopped = true;
                    break;
                }
                _ => {}
            }
            if !c.is_whitespace() {
                last = Some((off, at + c.len_utf8()));
            }
        }
        if stopped || depth == 0 {
            if text.trim_end().ends_with('\\') {
                return None;
            }
            return last;
        }
    }
    None
}

/// The rewrite of one raw write of a tracked var to its setter call, or None when the write is not a statement this can express (a write whose
/// value is used, one inside a `for(...)` header or a conditional expression, a chained assignment). `clean` and `raw` are the physical lines
/// of the file (the same indexing), `number` the 1-based line of the hit and `m_start` where the match starts on it.
fn setter_fix(clean: &[&str], raw: &[&str], number: usize, m_start: usize, holder: &str, var: &str, list: bool) -> Option<Fix> {
    let cl = *clean.get(number - 1)?;
    let rl = *raw.get(number - 1)?;
    if cl.len() != rl.len() || !statement_prefix_ok(&cl[..m_start]) {
        return None;
    }
    let pre = holder_prefix(holder);
    let read = if holder.is_empty() { var.to_string() } else { format!("{holder}.{var}") };
    let tlen = read.len();
    let s = &cl[m_start..];
    let (pre_op, after_target) = if s.starts_with("++") || s.starts_with("--") {
        let rest = s[2..].trim_start();
        let skipped = s.len() - rest.len();
        if !rest.starts_with(&read) || rest[tlen..].starts_with(|c: char| c.is_alphanumeric() || c == '_' || c == '.') {
            return None;
        }
        (Some(s[..2].to_string()), m_start + skipped + tlen)
    } else {
        if !s.starts_with(&read) {
            return None;
        }
        (None, m_start + tlen)
    };
    let tail = &cl[after_target..];
    let op_at = after_target + (tail.len() - tail.trim_start().len());
    let optext = &cl[op_at..];
    let end_of_line = cl.trim_end().trim_end_matches(';').trim_end().len();
    // `++V` / `--V` / `V++` / `V--` as a statement
    if let Some(op) = &pre_op {
        let rest = cl[after_target..].trim();
        if (!rest.is_empty() && !rest.starts_with(';')) || list {
            return None;
        }
        let delta = if op == "++" { "+" } else { "-" };
        return Some(Fix { start: m_start as u32, end: end_of_line as u32, was: rl[m_start..end_of_line].to_string(), text: format!("{pre}set_{var}({read} {delta} 1)"), more: Vec::new() });
    }
    if optext.starts_with("++") || optext.starts_with("--") {
        let rest = cl[op_at + 2..].trim();
        if (!rest.is_empty() && !rest.starts_with(';')) || list {
            return None;
        }
        let delta = if optext.starts_with("++") { "+" } else { "-" };
        return Some(Fix { start: m_start as u32, end: end_of_line as u32, was: rl[m_start..end_of_line].to_string(), text: format!("{pre}set_{var}({read} {delta} 1)"), more: Vec::new() });
    }
    // `=` or a compound assignment
    let op = ["<<=", ">>=", "+=", "-=", "*=", "/=", "|=", "&=", "^=", "="].iter().find(|o| optext.starts_with(**o))?;
    if *op == "=" && optext[1..].starts_with('=') {
        return None;
    }
    let rhs_from = op_at + op.len();
    let rhs_start = rhs_from + (cl[rhs_from..].len() - cl[rhs_from..].trim_start().len());
    if rhs_start >= cl.len() {
        return None; // the right-hand side starts on the next line
    }
    let (end_off, end_col) = statement_end(clean, number, rhs_start)?;
    if end_off > 0 && clean.get(number - 1 + end_off).map(|c| c.len()) != raw.get(number - 1 + end_off).map(|r| r.len()) {
        return None;
    }
    let simple = end_off == 0 && rl[rhs_start..end_col].chars().all(|c| c.is_alphanumeric() || c == '_' || c == '.');
    let (open_text, close_text) = if *op == "=" {
        (format!("{pre}set_{var}("), ")")
    } else if list {
        let proc = match *op {
            "+=" => "add",
            "-=" => "remove",
            "|=" => "include",
            _ => return None,
        };
        (format!("{pre}{proc}_{var}("), ")")
    } else {
        let binop = &op[..op.len() - 1];
        if simple {
            (format!("{pre}set_{var}({read} {binop} "), ")")
        } else {
            (format!("{pre}set_{var}({read} {binop} ("), "))")
        }
    };
    Some(Fix {
        start: m_start as u32,
        end: rhs_start as u32,
        was: rl[m_start..rhs_start].to_string(),
        text: open_text,
        more: vec![MoreEdit { line_off: end_off as u32, start: end_col as u32, end: end_col as u32, was: String::new(), text: close_text.to_string() }],
    })
}

/// `scan` for one file: its hits (in order) and the setters it defines `(owner, proc name)`.
fn scan_one(tracked: &Tracked, pats: &Pats, lists: &Tracked, lpats: Option<&ListPats>, f: &SourceFile, sink: &mut Sink, named_args: &BTreeSet<(usize, usize)>) -> (Vec<Hit>, Vec<(String, String)>) {
    let mut hits = Vec::new();
    let mut setters = Vec::new();
    if !pats.any.is_match(f.text()) {
        return (hits, setters);
    }
    let clean_lines: Vec<&str> = f.clean().text.split('\n').collect();
    let raw_lines: Vec<&str> = f.raw().text.split('\n').collect();
    for p in parse_procs(f.clean()) {
        let owner = if p.owner != "/" { normalize_type(p.owner) } else { "/".to_string() };
        // Construction of the instance (see PRE_LIVE): its own tracked vars are written plainly there.
        let pre_live = PRE_LIVE.contains(&p.name);
        let mut is_setter_of: Option<String> = None;
        if let Some(var) = p.name.strip_prefix("set_") {
            if tracked_type_of(tracked, var, &owner).map(|b| !b.is_empty()).unwrap_or(false) {
                is_setter_of = Some(var.to_string());
                setters.push((owner.clone(), p.name.to_string()));
            }
        }
        let mut locals: HashSet<String> = HashSet::new();
        let mut typed: HashMap<String, String> = HashMap::new();
        // Locals that walk one of the instance's own parts (`for(var/datum/omni_port/P in ports)`): parts the instance is still building.
        let mut own_parts: HashSet<String> = HashSet::new();
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
            if pre_live {
                for m in pat!(r"\bfor\s*\(\s*var/(?:[\w/]*/)?(\w+)\s+in\s+(?:src\.)?(\w+)\s*\)").captures_iter(line) {
                    own_parts.insert(m.s(1).to_string());
                }
            }
            for m in pats.bare.captures_iter(line) {
                if named_args.contains(&(*number, m.start(0) + 1)) || in_call_args(line, m.start(0)) {
                    continue; // this exact AST expression names a call argument, not storage
                }
                let var = if m.s(1).is_empty() { m.s(2) } else { m.s(1) };
                if is_setter_of.as_deref() == Some(var) {
                    continue;
                }
                let written_via_src = m.whole().contains(&format!("src.{}", var));
                if pre_live {
                    continue;
                }
                if locals.contains(var) && !written_via_src {
                    continue;
                }
                if Pat::cached(&format!(r"\bvar/(?:[\w/]*/)?{}\b", regex::escape(var))).is_match(line) {
                    continue;
                }
                let base = tracked_type_of(tracked, var, &owner).filter(|b| !b.is_empty());
                if let Some(base) = base {
                    if !sink.allowed(f, *number, LINT) {
                        let is_list = tracked_type_of(lists, var, &owner).is_some();
                        let fix = setter_fix(&clean_lines, &raw_lines, *number, m.start(0), if written_via_src { "src" } else { "" }, var, is_list);
                        hits.push(Hit { line: *number, msg: format!("{} written outside {}/proc/set_{}()", var, base, var), rule: RULE_SETTER, fix });
                    }
                }
            }
            for m in pats.dotted.captures_iter(line) {
                let holder = if m.s(1).is_empty() { m.s(3) } else { m.s(1) };
                let var = if m.s(2).is_empty() { m.s(4) } else { m.s(2) };
                if holder == "src" {
                    continue; // the bare pattern counts src.V
                }
                if own_parts.contains(holder) {
                    continue; // a part the instance is building (see PRE_LIVE)
                }
                let base = typed.get(holder).and_then(|t| tracked_type_of(tracked, var, t)).filter(|b| !b.is_empty());
                if let Some(base) = base {
                    if !sink.allowed(f, *number, LINT) {
                        let is_list = typed.get(holder).and_then(|t| tracked_type_of(lists, var, t)).is_some();
                        let fix = setter_fix(&clean_lines, &raw_lines, *number, m.start(0), holder, var, is_list);
                        hits.push(Hit { line: *number, msg: format!("{}.{} written outside {}/proc/set_{}()", holder, var, base, var), rule: RULE_SETTER, fix });
                    }
                }
            }
            if let Some(lp) = lpats {
                // In-place edits of a tracked list var: the same holder rules as a write, one pattern per form.
                let raw_line = f.raw().text.split('\n').nth(number - 1).unwrap_or("");
                let forms: [(&Pat, &str, usize, usize, usize); 3] = [(&lp.r#macro, "macro", 2, 3, 1), (&lp.method, "method", 1, 2, 3), (&lp.index, "index", 1, 2, 0)];
                for (pat, kind, holder_group, var_group, form_group) in forms {
                    for m in pat.captures_iter(line) {
                        let holder = m.s(holder_group);
                        let var = m.s(var_group);
                        let base = if holder.is_empty() || holder == "src" {
                            let written_via_src = holder == "src";
                            if pre_live {
                                continue;
                            }
                            if (locals.contains(var) && !written_via_src) || Pat::cached(&format!(r"\bvar/(?:[\w/]*/)?{}\b", regex::escape(var))).is_match(line) {
                                continue;
                            }
                            tracked_type_of(lists, var, &owner)
                        } else {
                            typed.get(holder).and_then(|t| tracked_type_of(lists, var, t))
                        };
                        let Some(base) = base.filter(|b| !b.is_empty()) else { continue };
                        if sink.allowed(f, *number, LINT) {
                            continue;
                        }
                        let form = if form_group == 0 { "" } else { m.s(form_group) };
                        let fix = list_fix(line, raw_line, kind, m.start(0), holder, var, form);
                        let who = if holder.is_empty() { var.to_string() } else { format!("{}.{}", holder, var) };
                        hits.push(Hit { line: *number, msg: format!("{} edited in place ({}) outside {}'s generated add_/remove_/set_{}_at/clear_ procs", who, if form.is_empty() { "[] =" } else { form }, base, var), rule: RULE_LIST, fix });
                    }
                }
            }
        }
    }
    (hits, setters)
}

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
    let pats = build_pats(tracked)?;
    let lists = tracked_lists(cx);
    let lpats = build_list_pats(&lists);
    let files: Vec<&SourceFile> = if tests { cx.all_files().into_iter().filter(|f| TEST_PREFIXES.iter().any(|p| f.rel.starts_with(p))).collect() } else { cx.files() };
    let semantic = cx.sem();
    let key = incr::ctx_key(&(tracked, &lists));
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
    let defs = crate::gens::auto_tracked::setter_defs(&sem);
    let outside = crate::gens::auto_tracked::writes_outside_setters(&sem);
    let scopes = crate::scopes::Scopes::load(&root.join("tools/ci/lint_scopes.toml")).unwrap_or_default();
    let exclude: Vec<String> = scopes.for_lint("auto_tracked", "").list("exclude").iter().chain(scopes.for_lint("auto_tracked", "").list("exclude_fixtures")).chain(scopes.for_lint("auto_tracked", "").list("exclude_heat")).chain(scopes.for_lint("auto_tracked", "").list("exclude_memo")).cloned().collect();
    let line_pat = pat_match!(r"^(\s*)TRACKED\(\s*(/[\w/]+)\s*,\s*(\w+)\s*\)\s*(?://.*)?$");
    let (mut dropped, mut kept) = (0usize, 0usize);
    for f in tree.select(&CODE_DM) {
        if f.rel == crate::gens::auto_tracked::AUTO_REL || f.rel == "code/__defines/capabilities.dm" || crate::sem::gen::test_only(&f.rel) || f.rel.contains("benchmarks/") || (!prefixes.is_empty() && !prefixes.iter().any(|p| f.rel.starts_with(p.as_str()))) {
            continue;
        }
        if !f.text().contains("TRACKED(") {
            continue;
        }
        let text = f.raw().text.to_string();
        let mut out: Vec<&str> = Vec::new();
        let mut changed = false;
        for line in text.split('\n') {
            let content = line.trim_end_matches('\r');
            if let Some(m) = line_pat.captures(content) {
                let (ty, var) = (m.s(2), m.s(3));
                let read = an.reads.iter().any(|(o, v)| v == var && (o == ty || sem.is_subtype(ty, o) || sem.is_subtype(o, ty)));
                let written = crate::gens::auto_tracked::set_calls(tree).contains(var) || outside.contains(var) || (crate::gens::auto_tracked::set_calls(tree).contains(&format!("{var}[]")));
                let alone = defs.get(&format!("set_{}", var)).is_none_or(|types| types.iter().all(|t| t == ty));
                let excluded = exclude.iter().any(|e| e == var || e == &format!("{ty}::{var}"));
                let builtin = sem.var_decl(ty, var).is_none_or(|s| s.file.is_empty() || s.is_static || s.is_const);
                if read && written && alone && !excluded && !builtin {
                    println!("{}: drop {}", f.rel, content.trim());
                    dropped += 1;
                    changed = true;
                    continue;
                }
                kept += 1;
            }
            out.push(line);
        }
        if changed && apply {
            let _ = std::fs::write(root.join(&f.rel), out.join("
"));
        }
    }
    println!("{} TRACKED declaration(s) {}, {} kept (no reactive reader, or another set_<v> on the path)", dropped, if apply { "dropped" } else { "droppable (dry run; --apply writes them)" }, kept);
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
    fn construction_writes_its_own_vars_plainly() {
        assert_eq!(run("/obj/box/Initialize(mapload)", "\t. = ..()\n\tplain = 5\n\tsrc.plain += 1\n\tLAZYADD(items, 1)").0, None);
        assert_eq!(run("/obj/box/New(loc)", "\tplain = 5").0, None);
        // another object's var, and a proc that runs once the holder is live, are judged as anywhere else
        assert!(run("/obj/box/Initialize(mapload, obj/box/B)", "\tB.plain = 5").0.is_some());
        assert!(run("/obj/box/proc/after_setup()", "\tplain = 5").0.is_some());
        // a part the instance walks while it is built is construction too
        assert_eq!(run("/obj/box/Initialize(mapload)", "\t. = ..()\n\tfor(var/obj/box/P in parts)\n\t\tP.plain = 5").0, None);
        assert!(run("/obj/box/Initialize(mapload)", "\t. = ..()\n\tfor(var/obj/box/P in range(1))\n\t\tP.plain = 5").0.is_some());
    }
}

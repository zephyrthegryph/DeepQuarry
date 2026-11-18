//! Port of `tools/ci/sys_rules/tables.py` (doc/rewrite/systems.md section 7): TYPE_TABLE / COW_LIST.
//!
//! `static_getter` (a proc returning a proc-local `var/static/list`, or a per-type override handing
//! out a global list), `const_list_alloc` (a constant `list(...)` rebuilt per call) and
//! `not_worth_it_annotation`.

use crate::raw_fixture_policy::{Fixture,PatternApi,PatternMode};
use std::collections::BTreeSet;

use crate::dm::sys::{register_module, SysModule};
#[cfg(feature="legacy-sem")]use crate::incr;
use crate::lint::{Registry, RuleMeta};
use crate::pat::Pat;
use crate::tree::SourceFile;
#[cfg(feature="legacy-sem")]use crate::tree::Tree;
use crate::util::{py_lstrip, py_strip};
use crate::{pat, pat_match};

pub(crate) const RULES: &[RuleMeta] = &[
    RuleMeta {
        name: "static_getter",
        hint: "declare TYPE_TABLE(type, name, value) and read TYPE_TABLE_GET(src, name), or a GLOBAL_LIST_INIT when the table is not per type (systems.md section 7)",
    },
    RuleMeta {
        name: "const_list_alloc",
        hint: "a constant list built per call: TYPE_TABLE / GLOBAL_LIST_INIT, handing out a Copy() only where callers mutate it (systems.md section 7)",
    },
    RuleMeta {
        name: "not_worth_it_annotation",
        hint: "per-subtype constant table: TYPE_TABLE + COW_LIST, then drop the instance_list ALLOW (systems.md section 7)",
    },
];

fn before_comment(s: &str) -> &str {
    s.split("//").next().unwrap_or("")
}

/// Text of the balanced `list( ... )` that starts at `lines[start][col..]`, its last line index
/// (unused by callers but kept), and whatever follows the closing paren on that line. The Python
/// kept the tail in a function attribute (`gather.tail`); it is returned here.
fn gather(lines: &[String], start: usize, col: usize) -> (Option<String>, usize, String) {
    let mut depth = 0i32;
    let mut out: Vec<String> = Vec::new();
    let end = (start + 400).min(lines.len());
    for index in start..end {
        let line: &str = if index != start { before_comment(&lines[index]) } else { before_comment(lines[index].get(col..).unwrap_or("")) };
        for (position, ch) in line.bytes().enumerate() {
            if ch == b'(' {
                depth += 1;
            } else if ch == b')' {
                depth -= 1;
                if depth == 0 {
                    out.push(line[..position + 1].to_string());
                    return (Some(out.join(" ")), index, py_strip(&line[position + 1..]).to_string());
                }
            }
        }
        out.push(line.trim_end_matches('\\').to_string());
    }
    (None, start, String::new())
}

/// A non-empty list literal of strings (no interpolation), numbers, UPPER_CASE defines and type
/// paths. Any other identifier disqualifies it.
fn constant(text: &Option<String>,fixture:&Fixture<'_>) -> bool {
    let Some(text) = text else { return false };
    let body = replace_scanned(fixture,r#""(?:[^"\\\[]|\.)*""#,text, " 0 ",||pat!(r#""(?:[^"\\\[]|\.)*""#));
    if body.contains('"') || body.contains('{') {
        return false;
    }
    let body = replace_scanned(fixture,r"(?<![\w/])/[a-z_][\w/]*",&body, " 0 ",||pat!(r"(?<![\w/])/[a-z_][\w/]*"));
    let squeezed = replace_scanned(fixture,r"\s",&body, "",||pat!(r"\s"));
    if squeezed == "list()" || squeezed == "alist()" {
        return false; // an empty list is a fresh mutable result, not a table
    }
    for m in fixture.pattern(r"(?<![\w])[A-Za-z_]\w*",PatternMode::Search,||pat!(r"(?<![\w])[A-Za-z_]\w*")).find_iter(&body) {
        let ident = m.as_str();
        if !matches!(ident, "null" | "TRUE" | "FALSE" | "list" | "alist") && !fixture.pattern(r"^[A-Z][A-Z0-9_]+$",PatternMode::Match,||pat_match!(r"^[A-Z][A-Z0-9_]+$")).is_match(ident) {
            return false;
        }
    }
    let flat = replace_scanned(fixture,r"\b(a?list)\(",&body, "(",||pat!(r"\b(a?list)\("));
    !fixture.pattern(r"\w\s*\(",PatternMode::Search,||pat!(r"\w\s*\(")).is_match(&flat)
}

const WRITE: &str = r"\s*(\+=|-=|\|=|&=|\^=|\.Add\(|\.Remove\(|\.Cut\(|\.Insert\(|\.Swap\(|\.Splice\(|\.Copy\(|\[[^\]]*\]\s*(=[^=]|\+=|-=)|\.len\s*[-+]?=|\s*=[^=])";

/// Indices of the rest of the proc body after line `index`.
fn proc_body(lines: &[String], index: usize) -> Vec<usize> {
    let mut out = Vec::new();
    for later in index + 1..lines.len() {
        let text = &lines[later];
        if !py_strip(text).is_empty() && !text.starts_with(['\t', ' ']) {
            break;
        }
        out.push(later);
    }
    out
}

/// Every value-returning `return` in the proc returns a constant list literal.
fn all_returns_constant(lines: &[String], header_index: usize,fixture:&Fixture<'_>) -> bool {
    for k in proc_body(lines, header_index) {
        let code = before_comment(&lines[k]);
        let Some(m) = fixture.pattern(r"(?:^\s+|\)\s*)return\b\s*(.*)$",PatternMode::Search,||pat!(r"(?:^\s+|\)\s*)return\b\s*(.*)$")).captures(code) else { continue };
        let value = py_strip(m.s(1));
        if matches!(value, "" | "null" | "FALSE" | "TRUE" | "0" | "1") {
            continue;
        }
        if !value.starts_with("list(") && !value.starts_with("alist(") {
            return false;
        }
        let (text, _, tail) = gather(lines, k, m.start(1));
        if !constant(&text,fixture) || !tail.is_empty() {
            return false;
        }
    }
    true
}

/// The lines with `/* ... */` spans blanked (dead code in block comments is not a site).
fn strip_block_comments(lines: &[String], text: &str) -> Vec<String> {
    if !text.contains("/*") {
        return lines.to_vec();
    }
    let t: Vec<char> = text.chars().collect();
    let n = t.len();
    let mut out = String::with_capacity(text.len());
    let mut depth = 0;
    let mut index = 0;
    let mut in_string = false;
    while index < n {
        let ch = t[index];
        let next = t.get(index + 1).copied();
        let is_pair = |a: char, b: char| ch == a && next == Some(b);
        if depth == 0 {
            if ch == '\n' {
                in_string = false;
            } else if ch == '"' && (index == 0 || t[index - 1] != '\\') {
                in_string = !in_string;
            } else if is_pair('/', '/') && !in_string {
                let end = t[index..].iter().position(|c| *c == '\n').map(|p| p + index).unwrap_or(n);
                out.extend(&t[index..end]);
                index = end;
                continue;
            }
        }
        if in_string {
            out.push(ch);
            index += 1;
            continue;
        }
        if is_pair('/', '*') {
            depth += 1;
            index += 2;
            out.push_str("  ");
            continue;
        }
        if is_pair('*', '/') && depth > 0 {
            depth -= 1;
            index += 2;
            out.push_str("  ");
            continue;
        }
        out.push(if depth == 0 || ch == '\n' { ch } else { ' ' });
        index += 1;
    }
    out.split('\n').map(|s| s.to_string()).collect()
}

/// The `GLOBAL_LIST*` names a file declares (sorted, unique).
pub(crate) fn global_lists_of(f:&SourceFile)->Vec<String>{global_lists_with_fixture(f,&Fixture::legacy())}
pub(crate) fn global_lists_with_fixture(f:&SourceFile,fixture:&Fixture<'_>)->Vec<String>{
    let mut names: BTreeSet<String> = BTreeSet::new();
    for line in f.raw().lines() {
        if line.contains("GLOBAL_LIST") {
            for c in fixture.pattern(r"\bGLOBAL_LIST(?:_INIT|_EMPTY|_INIT_TYPED|_EMPTY_TYPED)?\(\s*(\w+)",PatternMode::Search,||pat!(r"\bGLOBAL_LIST(?:_INIT|_EMPTY|_INIT_TYPED|_EMPTY_TYPED)?\(\s*(\w+)")).captures_iter(line) {
                names.insert(c.s(1).to_string());
            }
        }
    }
    names.into_iter().collect()
}

/// The build procs of the starting lists a file declares. Each runs once
/// per type, so a constant list is the shared table, rather than per-call work.
pub(crate) fn visit_cow_builds<E>(
    f: &SourceFile,
    mut visit: impl FnMut(&str) -> Result<(), E>,
) -> Result<(), E> {
    visit_cow_builds_with_fixture(f,visit,&Fixture::legacy())
}
pub(crate) fn visit_cow_builds_with_fixture<E>(f:&SourceFile,mut visit:impl FnMut(&str)->Result<(),E>,fixture:&Fixture<'_>)->Result<(),E>{
    if f.raw().text.contains("copy_on_write") {
        for line in f.raw().lines() {
            for c in fixture.pattern(r"\bper_type\([^\n]*?PROC_REF\(\s*(\w+)\s*\)[^\n]*\bcopy_on_write\s*=\s*TRUE",PatternMode::Search,||pat!(r"\bper_type\([^\n]*?PROC_REF\(\s*(\w+)\s*\)[^\n]*\bcopy_on_write\s*=\s*TRUE")).captures_iter(line) {
                visit(c.s(1))?;
            }
        }
    }
    Ok(())
}

#[cfg(feature="legacy-sem")]
fn cow_builds_of(f: &SourceFile) -> Vec<String> {
    let mut names = BTreeSet::new();
    visit_cow_builds(f, |name| {
        names.insert(name.to_owned());
        Ok::<_, std::convert::Infallible>(())
    }).unwrap_or_else(|never| match never {});
    names.into_iter().collect()
}

pub(crate) fn judge(f:&SourceFile,global_lists:&BTreeSet<String>,cow_builds:&BTreeSet<String>)->Vec<(u8,u32)>{judge_with_fixture(f,global_lists,cow_builds,&Fixture::legacy())}
pub(crate) fn judge_with_fixture(f:&SourceFile,global_lists:&BTreeSet<String>,cow_builds:&BTreeSet<String>,fixture:&Fixture<'_>)->Vec<(u8,u32)>{
    let mut out: Vec<(&'static str, String, usize)> = Vec::new();
    {
        let rel = f.rel.as_str();
        let orig: Vec<String> = f.raw().lines().map(|s| s.to_string()).collect();
        let lines = strip_block_comments(&orig, &f.raw().text);
        let mut in_proc = false;
        let mut header: Option<String> = None;
        let mut header_index = 0usize;
        for (idx, line) in lines.iter().enumerate() {
            let number = idx + 1;
            if !py_strip(line).is_empty() && !line.starts_with(['\t', ' ']) {
                in_proc = fixture.pattern(r"^/[\w/]*\w\((.*)\)",PatternMode::Match,||pat_match!(r"^/[\w/]*\w\((.*)\)")).is_match(line) && !py_lstrip(line).starts_with("//");
                header = if in_proc { Some(line.clone()) } else { None };
                header_index = number - 1;
            }
            if fixture.pattern(r"(?i)ALLOW\(instance_list\):.*not worth it",PatternMode::Search,||pat!(r"(?i)ALLOW\(instance_list\):.*not worth it")).is_match(line) {
                out.push(("not_worth_it_annotation", rel.to_string(), number));
            }
            if !in_proc {
                continue;
            }
            if header.as_deref().and_then(|h| fixture.pattern(r"/(\w+)\(",PatternMode::Search,||pat!(r"/(\w+)\(")).captures(h).map(|c| c.s(1).to_string())).is_some_and(|n| cow_builds.contains(&n)) {
                continue;
            }
            let code = before_comment(line);
            // A per-type override that hands out a global list.
            if let Some(glob) = fixture.pattern(r"^\s+return\s+(?:GLOB|global)\.(\w+)\s*$",PatternMode::Match,||pat_match!(r"^\s+return\s+(?:GLOB|global)\.(\w+)\s*$")).captures(code) {
                if global_lists.contains(glob.s(1))
                    && header.as_deref().map(|h| fixture.pattern(r"^/(?!proc/)(?![\w/]*/(?:proc|verb)/)[\w/]+/\w+\(\s*\)",PatternMode::Match,||pat_match!(r"^/(?!proc/)(?![\w/]*/(?:proc|verb)/)[\w/]+/\w+\(\s*\)")).is_match(h)).unwrap_or(false)
                    && number >= 2
                    && Some(&lines[number - 2]) == header.as_ref()
                {
                    out.push(("static_getter", rel.to_string(), number));
                    continue;
                }
            }
            if let Some(m) = fixture.pattern(r"^(\s+)var/static/list/(\w+)\b",PatternMode::Match,||pat_match!(r"^(\s+)var/static/list/(\w+)\b")).captures(code) {
                let native_ret=if fixture.has_native_patterns(){match fixture.formatted_pattern(format_args!(r"^\s+return\s+{}\s*$",m.s(2)),PatternMode::Match){Ok(value)=>{let _=value.capture_group_count();Some(value)},Err(error)=>{fixture.note_scan(Err(error));return Vec::new()}}}else{None};
                let legacy_ret=if native_ret.is_none(){Some(Pat::new_match(&format!(r"^\s+return\s+{}\s*$",m.s(2))))}else{None};
                if proc_body(&lines, number - 1).iter().any(|k| native_ret.as_ref().map_or_else(||legacy_ret.as_ref().expect("actual legacy table-return pattern").is_match(before_comment(&lines[*k])),|ret|ret.is_match(before_comment(&lines[*k])))) {
                    out.push(("static_getter", rel.to_string(), number));
                }
                continue;
            }
            if let Some(ret) = fixture.pattern(r"(?:^\s+|\)\s*)(?:return|\.\s*=)\s*list\(",PatternMode::Search,||pat!(r"(?:^\s+|\)\s*)(?:return|\.\s*=)\s*list\(")).find(code) {
                let (text, end, tail) = gather(&lines, number - 1, ret.end - "list(".len());
                if constant(&text,fixture) && tail.is_empty() && all_returns_constant(&lines, header_index,fixture) {
                    if !code[ret.start..ret.end].contains("return")
                        && proc_body(&lines, end)
                            .iter()
                            .any(|k| fixture.pattern(r"^\s*\.\s*(\[|\+=|-=|\|=|\.Add\(|\.Insert\()",PatternMode::Match,||pat_match!(r"^\s*\.\s*(\[|\+=|-=|\|=|\.Add\(|\.Insert\()")).is_match(before_comment(&lines[*k])))
                    {
                        continue; // `. = list(...)` seeding a result the proc then fills in
                    }
                    out.push(("const_list_alloc", rel.to_string(), number));
                }
                continue;
            }
            if let Some(m) = fixture.pattern(r"^(\s+)var/list/(\w+)\s*=\s*list\(",PatternMode::Match,||pat_match!(r"^(\s+)var/list/(\w+)\s*=\s*list\(")).captures(code) {
                let col = line.find("list(").unwrap_or(0);
                let (text, end, tail) = gather(&lines, number - 1, col);
                if !constant(&text,fixture) || !tail.is_empty() {
                    continue;
                }
                let name = m.s(2);
                let native_touched=if fixture.has_native_patterns(){match fixture.formatted_pattern(format_args!(r"\b{n}{w}|return\s+{n}\b|[(,]\s*{n}\s*[,)]|=\s*{n}\s*$",n=name,w=WRITE),PatternMode::Search){Ok(value)=>{let _=value.capture_group_count();Some(value)},Err(error)=>{fixture.note_scan(Err(error));return Vec::new()}}}else{None};
                let legacy_touched=if native_touched.is_none(){Some(Pat::cached(&format!(r"\b{n}{w}|return\s+{n}\b|[(,]\s*{n}\s*[,)]|=\s*{n}\s*$",n=name,w=WRITE)))}else{None};
                if !proc_body(&lines, end).iter().any(|k| native_touched.as_ref().map_or_else(||legacy_touched.expect("actual legacy table-touch pattern").is_match(before_comment(&lines[*k])),|touched|touched.is_match(before_comment(&lines[*k])))) {
                    out.push(("const_list_alloc", rel.to_string(), number));
                }
            }
        }
    }
    out.into_iter().map(|(rule, _, line)| (RULES.iter().position(|r| r.name == rule).unwrap_or(0) as u8, line as u32)).collect()
}

#[cfg(feature="legacy-sem")]
fn scan(_tree: &Tree, files: &[&SourceFile]) -> Vec<(&'static str, String, usize)> {
    let fs = incr::facts("sys-tables-facts", files, global_lists_of);
    let global_lists: BTreeSet<String> = fs.into_iter().flatten().collect();
    let cow_builds: BTreeSet<String> = incr::facts("sys-tables-cow-builds", files, cow_builds_of).into_iter().flatten().collect();
    let key = incr::ctx_key(&(&global_lists, &cow_builds));
    let results = incr::keyed("sys-tables-judge", key, files, |f| judge(f, &global_lists, &cow_builds));
    let mut out = Vec::new();
    for (f, v) in files.iter().zip(results) {
        for (rule, line) in v {
            out.push((RULES[rule as usize].name, f.rel.clone(), line as usize));
        }
    }
    out
}

#[cfg(feature="legacy-sem")]
pub fn register(reg: &mut Registry) {
    register_module(reg, SysModule { name: crate::allow_registry_fields::sys_tables::SCOPE_MODULE_NAME, rules: RULES, files_scan: Some(scan), ..SysModule::DEFAULT });
}

fn replace_scanned(fixture:&Fixture<'_>,source:&'static str,text:&str,replacement:&str,legacy:fn()->&'static Pat)->String{match fixture.replace_static(source,text,replacement,legacy){Ok(actual)=>actual,Err(error)=>{fixture.note_scan(Err(error));String::new()}}}

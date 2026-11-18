//! Unique original Sys fields lexical judgement over the existing field index.
use crate::dm::field_write::{is_var_decl,local_or_member,norm,proc_def,typed_names,FwlIndex,Locals};
use crate::raw_fixture_policy::{Fixture,PatternApi,PatternMode};
use crate::{pat,tree::SourceFile,util::{is_py_space,under}};
pub use crate::allow_registry_fields::sys_fields::RULES;
pub const CORE: &[&str] = &["on", "active", "state", "mode", "locked", "emagged", "stat", "anchored", "density", "use_power"];
const STAT_ROOTS: &[&str] = &["/obj/machinery", "/obj/vehicle"];
const RUNTIME: &[&str] = &["code/content/machinery/machinery_fields.dm", "code/defines/engine/om.dm", "code/datums/om/fields.dm"];
/// (file, proc name) of the owners allowed to write the owned bits.
const OWNED_WRITERS: &[(&str, &str)] = &[
    ("code/content/machinery/machinery_power.dm", "set_powered"),
    ("code/domains/world_model/machinery.dm", "atom_break"),
    ("code/domains/world_model/machinery.dm", "atom_fix"),
];

pub fn scan_one(index:&FwlIndex,fields:&crate::dm::field_write::Fields,f:&SourceFile)->Vec<(&'static str,usize)>{scan_one_with_fixture(index,fields,f,&Fixture::legacy())}
pub fn scan_one_with_fixture<P:PatternApi>(index:&FwlIndex,fields:&crate::dm::field_write::Fields<P>,f:&SourceFile,fixture:&Fixture<'_>)->Vec<(&'static str,usize)>{
    let mut out: Vec<(&'static str, usize)> = Vec::new();
    let rel = f.rel.as_str();
    let text = &f.code().text;
    let code_lines: Vec<&str> = text.split('\n').collect();
    let runtime = RUNTIME.contains(&rel);
    if !runtime {
        for (i, line) in code_lines.iter().enumerate() {
            if fixture.pattern(r"\b(?:inoperable|is_operational)\s*\(",PatternMode::Search,||pat!(r"\b(?:inoperable|is_operational)\s*\(")).is_match(line) {
                out.push(("stat_helper", i + 1));
            }
        }
        for v in index.violations_with_fixture(fields,text,fixture) {
            out.push(("field_write", v.line));
        }
    }
    if !rel.starts_with("code/tests/unit_tests/") {
        let mut proc_name: Option<String> = None;
        for (i, line) in code_lines.iter().enumerate() {
            let no = i + 1;
            if let Some(ch) = line.chars().next() {
                if !is_py_space(ch) {
                    proc_name = if crate::dm::field_write::proc_def_with_fixture(line,fixture).is_some() && !line.starts_with('#') {
                        fixture.pattern(r"\A(?:[\w/]*?/(\w+)\s*\()",PatternMode::Search,||pat!(r"\A(?:[\w/]*?/(\w+)\s*\()")).captures(line).map(|c| c.s(1).to_string())
                    } else {
                        None
                    };
                    continue;
                }
            }
            if fixture.pattern(r"\b(?:stat_add|stat_remove|set_stat)\s*\([^)]*\b(?:NOPOWER|BROKEN)\b",PatternMode::Search,||pat!(r"\b(?:stat_add|stat_remove|set_stat)\s*\([^)]*\b(?:NOPOWER|BROKEN)\b")).is_match(line) {
                let owned = proc_name.as_deref().map(|p| OWNED_WRITERS.contains(&(rel, p))).unwrap_or(false);
                if !owned {
                    out.push(("stat_owned", no));
                }
            }
        }
    }
    if runtime {
        return out;
    }
    let mut owner: Option<String> = None;
    let mut locals = Locals::new();
    let mut stat_local = false;
    for (i, line) in code_lines.iter().enumerate() {
        let no = i + 1;
        if let Some(ch) = line.chars().next() {
            if !is_py_space(ch) {
                if let Some(m) = crate::dm::field_write::proc_def_with_fixture(line,fixture) {
                    owner = Some(norm(&m.owner));
                    locals = Locals::new();
                    for tm in crate::dm::field_write::typed_names_with_fixture(&m.params,fixture) {
                        locals.insert(tm.name, Some(norm(&tm.ty)));
                    }
                    stat_local = fixture.pattern(r"(?<![\w/])stat\b",PatternMode::Search,||pat!(r"(?<![\w/])stat\b")).is_match(&m.params);
                } else {
                    owner = None;
                }
                continue;
            }
        }
        let Some(owner) = owner.as_deref() else { continue };
        for tm in crate::dm::field_write::typed_names_with_fixture(line,fixture) {
            if is_var_decl(line, tm.start) {
                locals.insert(tm.name, Some(norm(&tm.ty)));
            }
        }
        if fixture.pattern(r"\bvar/(?:[\w/]+/)?stat\b",PatternMode::Search,||pat!(r"\bvar/(?:[\w/]+/)?stat\b")).is_match(line) {
            stat_local = true;
            continue;
        }
        let mut hit = false;
        if under(owner, STAT_ROOTS) && !stat_local {
            for m in fixture.pattern(r"(?<![\w.])(?:src\.)?stat\b(?!\s*\()",PatternMode::Search,||pat!(r"(?<![\w.])(?:src\.)?stat\b(?!\s*\()")).find_iter(line) {
                if !crate::util::py_rstrip(&line[..m.start]).ends_with("var") {
                    hit = true;
                    break;
                }
            }
        }
        if !hit && line.contains(".stat") {
            for m in fixture.pattern(r"(?<![\w])(\w+)\??\.stat\b(?!\s*\()",PatternMode::Search,||pat!(r"(?<![\w])(\w+)\??\.stat\b(?!\s*\()")).captures_iter(line) {
                let recv = m.s(1);
                if recv == "src" {
                    if under(owner, STAT_ROOTS) {
                        hit = true;
                        break;
                    }
                    continue;
                }
                let rtype = local_or_member(index, &locals, owner, recv);
                if let Some(t) = &rtype {
                    if under(t, STAT_ROOTS) {
                        hit = true;
                        break;
                    }
                }
                if fixture.pattern(r"\A(?:\s*(?:&(?!&)|\|(?!\|)|\^))",PatternMode::Search,||pat!(r"\A(?:\s*(?:&(?!&)|\|(?!\|)|\^))")).is_match(&line[m.end(0)..])
                    || fixture.pattern(r"(?:[^&]&|[^|]\||\^)\s*\(?\s*$",PatternMode::Search,||pat!(r"(?:[^&]&|[^|]\||\^)\s*\(?\s*$")).is_match(&line[..m.start(0)])
                {
                    if let Some(t) = &rtype {
                        if !under(t, STAT_ROOTS) && !t.starts_with("/obj") {
                            continue; // a mob's (or other typed) stat: not machine bits
                        }
                    }
                    hit = true;
                    break;
                }
            }
        }
        if hit {
            out.push(("stat_bits", no));
        }
    }
    out
}

//! Port of `tools/ci/sys_rules/damage_reactions.py` (doc/rewrite/systems.md section 12): declared
//! damage reactions. An override of a damage entry point that does a fixed thing (not procedural:
//! reads the hit, returns a hit-flow value, or changes the hit it passes on) is flagged.

use crate::raw_fixture_policy::PatternApi as _;
use std::sync::LazyLock;

use crate::dm::sys::{register_module, SysModule};
use crate::lint::{Registry, RuleMeta};
use crate::pat::Pat;
use crate::tree::SourceFile;
use crate::util::py_strip;
use crate::{pat, pat_match};

use crate::allow_registry_fields::sys_damage_reactions::RULES;

const ENTRIES: &[&str] = &[
    "bullet_act",
    "emp_act",
    "ex_act",
    "fire_act",
    "blob_act",
    "hitby",
    "attack_generic",
    "electrocute_act",
    // the packet adapters the entries call; overriding one to do a fixed thing is the same shape
    "receive_emp",
    "receive_ionic",
    "receive_explosion",
    "receive_blob",
    "receive_shock",
];
const ADAPTER_ROOTS: &[&str] = &["/atom", "/atom/movable", "/obj", "/turf", "/mob", "/mob/living"];
const FREE_PARAMS: &[&str] = &["severity", "recursive", "forced"];
const REFLECT_ALLOWED_MEMBERS: &[&str] = &["starting", "name", "reflected", "redirect", "obj_damage_type"];

static HEADER: LazyLock<Pat> = LazyLock::new(|| Pat::new_match(&format!(r"^(/[\w/]+?)/({})\s*\((.*)$", ENTRIES.join("|"))));

const NATIVE_HEADER:&str=r"^(/[\w/]+?)/(bullet_act|emp_act|ex_act|fire_act|blob_act|hitby|attack_generic|electrocute_act|receive_emp|receive_ionic|receive_explosion|receive_blob|receive_shock)\s*\((.*)$";
/// Names of the parameters in `signature` (the text after the header's opening paren).
fn param_names_using(signature: &str,fixture:&crate::raw_fixture_policy::Fixture<'_>)->Result<Vec<String>,String>{fixture.check()?;
    let mut depth = 1i32;
    let mut text = String::new();
    for c in signature.chars() {
        if c == '(' {
            depth += 1;
        } else if c == ')' {
            depth -= 1;
            if depth == 0 {
                break;
            }
        }
        fixture.append(&mut text,c.encode_utf8(&mut [0;4]))?;
    }
    let mut names: Vec<String> = Vec::new();
    for part in text.split(',') {
        let part = py_strip(part.split('=').next().unwrap_or(""));
        if part.is_empty() {
            continue;
        }
        let part = py_strip(part.split(" as ").next().unwrap_or(""));
        fixture.push(&mut names,fixture.own(py_strip(part.rsplit('/').next().unwrap_or("")))?)?;
    }
    let pattern=fixture.pattern(r"^[A-Za-z_]\w*$",crate::raw_fixture_policy::PatternMode::Match,||pat_match!(r"^[A-Za-z_]\w*$"));
    let names=fixture.collect(names.into_iter().filter(|n|pattern.is_match(n)))?;fixture.check()?;Ok(names)
}

fn code_of_using(line: &str,fixture:&crate::raw_fixture_policy::Fixture<'_>) ->Result<String,String> {fixture.check()?;

    let s = fixture.replace_static(r#""(?:[^"\\\n]|\\.)*""#,line,"\"\"",||pat!(r#""(?:[^"\\\n]|\\.)*""#))?;
    fixture.own(s.split("//").next().unwrap_or(""))
}


/// The line with every parent call's argument list removed (`..(P, def_zone)` -> `..()`).
fn strip_parent_args_using(code: &str,fixture:&crate::raw_fixture_policy::Fixture<'_>) ->Result<String,String> {fixture.check()?;

    let b = code.as_bytes();
    let mut out = String::new();
    let mut i = 0;
    while i < code.len() {
        let Some(m) = fixture.pattern(r"\.\.\(",crate::raw_fixture_policy::PatternMode::Search,||pat!(r"\.\.\(")).find_at(code, i) else {
            fixture.append(&mut out,&code[i..])?;
            break;
        };
        fixture.append(&mut out,&code[i..m.end])?;
        let mut depth = 1;
        let mut j = m.end;
        while j < b.len() && depth != 0 {
            if b[j] == b'(' {
                depth += 1;
            } else if b[j] == b')' {
                depth -= 1;
            }
            j += 1;
        }
        fixture.append(&mut out,")")?;
        i = j;
    }
    Ok(out)
}


/// The reflect shape: a redirect back towards `name.starting`, reading nothing else of it.
fn is_reflect_boilerplate_using(body: &[String], name: &str,fixture:&crate::raw_fixture_policy::Fixture<'_>) ->Result<bool,String> {fixture.check()?;

    let borrowed=fixture.collect(body.iter().map(String::as_str))?;let text=fixture.join(&borrowed,"\n")?;
    let esc=fixture.escape_pattern(name)?;
    if !fixture.formatted_is_match(format_args!(r"\b{}\s*\.\s*redirect\s*\(",esc),&text,||Pat::cached(&format!(r"\b{}\s*\.\s*redirect\s*\(",esc)))? {
        return Ok(false);
    }
    if !fixture.formatted_is_match(format_args!(r"\b{}\s*\.\s*starting\b",esc),&text,||Pat::cached(&format!(r"\b{}\s*\.\s*starting\b",esc)))? {
        return Ok(false);
    }
    for m in fixture.formatted_captures_iter(format_args!(r"\b{}\b(\s*\.\s*(\w+))?",esc),&text,||Pat::cached(&format!(r"\b{}\b(\s*\.\s*(\w+))?",esc)))? {
        if !m.matched(2) {
            let start = m.start(0);
            // text[max(0, start - 40):start] counted in characters
            let mut from = start;
            for (n, (off, _)) in text[..start].char_indices().rev().enumerate() {
                if n >= 40 {
                    break;
                }
                from = off;
            }
            let before = &text[from..start];
            // istype(P, ...), act_message(src, P, ...) and visible_message("[P]") read no state
            if fixture.pattern(r"(istype|act_message|visible_message|span_\w+)\s*\([^()]*$",crate::raw_fixture_policy::PatternMode::Search,||pat!(r"(istype|act_message|visible_message|span_\w+)\s*\([^()]*$")).is_match(before) {
                continue;
            }
            return Ok(false);
        }
        if !REFLECT_ALLOWED_MEMBERS.contains(&m.s(2)) {
            return Ok(false);
        }
    }
    fixture.check()?;Ok(true)
}


/// P3: a parameter is written, or the parent gets something other than the parameters.
fn changes_hit_using(raw_lines: &[String], params: &[String],fixture:&crate::raw_fixture_policy::Fixture<'_>) ->Result<bool,String> {fixture.check()?;

    for line in raw_lines {
        for name in params {
            let escaped=fixture.escape_pattern(name)?;
            if fixture.formatted_is_match(format_args!(r"(?<![\w.]){}\s*(?:=(?!=)|\+\+|--|[-+*/]=)",escaped),line,||Pat::cached(&format!(r"(?<![\w.]){}\s*(?:=(?!=)|\+\+|--|[-+*/]=)",escaped)))? {
                return Ok(true);
            }
        }
        for m in fixture.pattern(r"\.\.\(([^()]*(?:\([^()]*\)[^()]*)*)\)",crate::raw_fixture_policy::PatternMode::Search,||pat!(r"\.\.\(([^()]*(?:\([^()]*\)[^()]*)*)\)")).captures_iter(line) {
            for arg in m.s(1).split(',').map(py_strip) {
                if !arg.is_empty() && !params.iter().any(|p| p == arg) && !fixture.pattern(r"^\w+\s*=\s*\w+$",crate::raw_fixture_policy::PatternMode::Match,||pat_match!(r"^\w+\s*=\s*\w+$")).is_match(arg) {
                    return Ok(true);
                }
            }
        }
    }
    fixture.check()?;Ok(false)
}


fn procedural_using(body: &[&str], params: &[String],fixture:&crate::raw_fixture_policy::Fixture<'_>) ->Result<bool,String> {fixture.check()?;

    let reads:Vec<&String>=fixture.collect(params.iter().filter(|p|!FREE_PARAMS.contains(&p.as_str())))?;
    let mut raw=Vec::new();for line in body{fixture.push(&mut raw,code_of_using(line,fixture)?)?;}
    if changes_hit_using(&raw,params,fixture)? {
        return Ok(true);
    }
    let mut lines=Vec::new();for line in &raw{fixture.push(&mut lines,strip_parent_args_using(line,fixture)?)?;}
    for line in &lines {
        let Some(m) = fixture.pattern(r"(?<![\w.])return\b\s*(.*)$",crate::raw_fixture_policy::PatternMode::Search,||pat!(r"(?<![\w.])return\b\s*(.*)$")).captures(line) else { continue };
        let mut value = fixture.own(py_strip(py_strip(m.s(1)).trim_end_matches(';')))?;
        while value.starts_with('(') && value.ends_with(')') {
            value = fixture.own(py_strip(&value[1..value.len() - 1]))?;
        }
        if matches!(value.as_str(), "" | "." | "..()" | "0" | "FALSE" | "null") {
            continue;
        }
        if !reads.is_empty() && is_reflect_boilerplate_using(&lines,reads[0],fixture)? {
            continue;
        }
        return Ok(true);
    }
    for name in &reads {
        let escaped=fixture.escape_pattern(name)?;
        if fixture.formatted_any_match(format_args!(r"(?<![\w.]){}\b",escaped),&lines,||Pat::cached(&format!(r"(?<![\w.]){}\b",escaped)))? {
            if is_reflect_boilerplate_using(&lines,name,fixture)? {
                continue;
            }
            return Ok(true);
        }
    }
    fixture.check()?;Ok(false)
}


fn scan_using(f: &SourceFile, out: &mut Vec<(&'static str, usize)>,fixture:&crate::raw_fixture_policy::Fixture<'_>)->Result<(),String>{fixture.check()?;
fixture.require_pattern_binding(NATIVE_HEADER.strip_prefix(r"^(/[\w/]+?)/(").and_then(|body|body.strip_suffix(r")\s*\((.*)$")).is_some_and(|body|body.split('|').eq(ENTRIES.iter().copied())))?;
    let header=fixture.pattern(NATIVE_HEADER,crate::raw_fixture_policy::PatternMode::Match,||&HEADER);

    let lines = fixture.collect(f.raw().lines())?;
    for (index, line) in lines.iter().enumerate() {
        let Some(m) = header.captures(line) else { continue };
        let path = m.s(1);
        if path.ends_with("/proc") || fixture.detail(format_args!("{}/",path))?.contains("/proc/") || path.contains("/verb") {
            continue; // a definition, not an override
        }
        if ADAPTER_ROOTS.contains(&path) {
            continue;
        }
        let mut body: Vec<&str> = Vec::new();
        let mut j = index + 1;
        while j < lines.len() && (lines[j].starts_with(['\t', ' ']) || py_strip(lines[j]).is_empty()) {
            fixture.push(&mut body,lines[j])?;
            j += 1;
        }
        if procedural_using(&body,&param_names_using(m.s(3),fixture)?,fixture)? {
            continue;
        }
        fixture.push(out,("entry_override", index + 1))?;
    }

fixture.check()?;Ok(())
}


pub fn register(reg: &mut Registry) {
    register_module(reg, SysModule { name: crate::allow_registry_fields::sys_damage_reactions::SCOPE_MODULE_NAME, rules: RULES, file_scan: Some(scan),fixture_file_scan:Some(scan_using), ..SysModule::DEFAULT });
}

fn scan(f:&SourceFile,out:&mut Vec<(&'static str,usize)>){scan_using(f,out,&crate::raw_fixture_policy::Fixture::legacy()).expect("legacy scan has no resource refusal")}

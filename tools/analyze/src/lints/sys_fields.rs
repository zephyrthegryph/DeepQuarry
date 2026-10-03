//! Port of `tools/ci/sys_rules/fields.py` (doc/rewrite/systems.md section 2): core machine state
//! as declared fields.
//!
//! Rules: `stat_bits` (raw `stat` bit use in machinery/vehicle procs, or `thing.stat` used with a bit
//! operator or typed as a machine), `stat_owned` (NOPOWER/BROKEN written outside their owner),
//! `stat_helper` (the old `inoperable()`/`is_operational()` readers) and `field_write` (a direct write
//! to a core field outside its setter, resolved by `dm::field_write`).

use crate::dm::field_write::{is_var_decl, local_or_member, norm, proc_def, typed_names, FwlIndex, Locals};
use crate::dm::sys::{register_module, SysModule};
use crate::incr;
use crate::lint::{Registry, RuleMeta};
use crate::pat;
use crate::tree::{SourceFile, Tree};
use crate::util::{is_py_space, under};

const RULES: &[RuleMeta] = &[
    RuleMeta { name: "stat_bits", hint: "operable() / has_stat(BITS) to read, stat_add()/stat_remove()/set_stat() to write (systems.md section 2)" },
    RuleMeta { name: "stat_owned", hint: "set_powered() for NOPOWER, atom_break() / atom_fix() for BROKEN (G8: they publish the state)" },
    RuleMeta { name: "stat_helper", hint: "operable() is the one reader; inoperable()/is_operational() are gone (systems.md section 2)" },
    RuleMeta { name: "field_write", hint: "set_<field>() (stat_add()/stat_remove() for bits); no direct writes to a core field (systems.md section 2)" },
];

const CORE: &[&str] = &["on", "active", "state", "mode", "locked", "emagged", "stat", "anchored", "density", "use_power"];
const STAT_ROOTS: &[&str] = &["/obj/machinery", "/obj/vehicle"];
const RUNTIME: &[&str] = &["code/game/machinery/machinery_fields.dm", "code/__defines/om.dm", "code/datums/om/fields.dm"];
/// (file, proc name) of the owners allowed to write the owned bits.
const OWNED_WRITERS: &[(&str, &str)] = &[
    ("code/game/machinery/machinery_power.dm", "set_powered"),
    ("code/game/machinery/machinery.dm", "atom_break"),
    ("code/game/machinery/machinery.dm", "atom_fix"),
];

fn scan_one(index: &FwlIndex, fields: &crate::dm::field_write::Fields, f: &SourceFile) -> Vec<(&'static str, usize)> {
    let mut out: Vec<(&'static str, usize)> = Vec::new();
    let rel = f.rel.as_str();
    let text = &f.code().text;
    let code_lines: Vec<&str> = text.split('\n').collect();
    let runtime = RUNTIME.contains(&rel);
    if !runtime {
        for (i, line) in code_lines.iter().enumerate() {
            if pat!(r"\b(?:inoperable|is_operational)\s*\(").is_match(line) {
                out.push(("stat_helper", i + 1));
            }
        }
        for v in index.violations(fields, text) {
            out.push(("field_write", v.line));
        }
    }
    if !rel.starts_with("code/modules/unit_tests/") {
        let mut proc_name: Option<String> = None;
        for (i, line) in code_lines.iter().enumerate() {
            let no = i + 1;
            if let Some(ch) = line.chars().next() {
                if !is_py_space(ch) {
                    proc_name = if proc_def(line).is_some() && !line.starts_with('#') {
                        pat!(r"\A(?:[\w/]*?/(\w+)\s*\()").captures(line).map(|c| c.s(1).to_string())
                    } else {
                        None
                    };
                    continue;
                }
            }
            if pat!(r"\b(?:stat_add|stat_remove|set_stat)\s*\([^)]*\b(?:NOPOWER|BROKEN)\b").is_match(line) {
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
                if let Some(m) = proc_def(line) {
                    owner = Some(norm(&m.owner));
                    locals = Locals::new();
                    for tm in typed_names(&m.params) {
                        locals.insert(tm.name, Some(norm(&tm.ty)));
                    }
                    stat_local = pat!(r"(?<![\w/])stat\b").is_match(&m.params);
                } else {
                    owner = None;
                }
                continue;
            }
        }
        let Some(owner) = owner.as_deref() else { continue };
        for tm in typed_names(line) {
            if is_var_decl(line, tm.start) {
                locals.insert(tm.name, Some(norm(&tm.ty)));
            }
        }
        if pat!(r"\bvar/(?:[\w/]+/)?stat\b").is_match(line) {
            stat_local = true;
            continue;
        }
        let mut hit = false;
        if under(owner, STAT_ROOTS) && !stat_local {
            for m in pat!(r"(?<![\w.])(?:src\.)?stat\b(?!\s*\()").find_iter(line) {
                if !crate::util::py_rstrip(&line[..m.start]).ends_with("var") {
                    hit = true;
                    break;
                }
            }
        }
        if !hit && line.contains(".stat") {
            for m in pat!(r"(?<![\w])(\w+)\??\.stat\b(?!\s*\()").captures_iter(line) {
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
                if pat!(r"\A(?:\s*(?:&(?!&)|\|(?!\|)|\^))").is_match(&line[m.end(0)..])
                    || pat!(r"(?:[^&]&|[^|]\||\^)\s*\(?\s*$").is_match(&line[..m.start(0)])
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

fn files_scan(tree: &Tree, files: &[&SourceFile]) -> Vec<(&'static str, String, usize)> {
    let index = FwlIndex::get(tree);
    let fields = index.fields_named(CORE);
    let key = index.ctx_key(Some(CORE));
    let per: Vec<Vec<(u8, u32)>> = incr::keyed("sys-fields-judge", key, files, |f| {
        scan_one(&index, &fields, f)
            .into_iter()
            .map(|(rule, line)| (RULES.iter().position(|r| r.name == rule).unwrap_or(0) as u8, line as u32))
            .collect()
    });
    let mut out = Vec::new();
    for (f, sites) in files.iter().zip(per) {
        for (rule, line) in sites {
            out.push((RULES[rule as usize].name, f.rel.clone(), line as usize));
        }
    }
    out
}

pub fn register(reg: &mut Registry) {
    register_module(reg, SysModule { name: "fields", rules: RULES, files_scan: Some(files_scan), ..SysModule::DEFAULT });
}

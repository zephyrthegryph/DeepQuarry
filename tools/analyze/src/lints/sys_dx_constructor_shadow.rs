//! Port of `tools/ci/sys_rules/dx_constructor_shadow.py`: type procs that shadow a capability
//! constructor or bundle (framework review 2, H7). Inside `capabilities()` a bare call binds to
//! src's own proc before the global one, so an atom proc named like a global `cap_*` constructor,
//! a presets-file global or a capability-building bundle replaces it on that type.

use std::collections::{HashMap, HashSet};

use crate::dm::dx::{lineage, DxIndex, Proc};
use crate::dm::sys::{register_module, SysModule};
use crate::lint::{Registry, RuleMeta};
use crate::pat;
use crate::tree::{SourceFile, Tree};

const RULES: &[RuleMeta] = &[
    RuleMeta {
        name: "dx_constructor_shadow",
        hint: "rename the type proc: it shadows a global capability constructor or bundle inside capabilities() (framework review 2, H7)",
    },
    RuleMeta {
        name: "part_constructor_shadow",
        hint: "rename the proc: a capability datum's entries() calls the part constructors (cooldown(), flash(), put_in(), menu(), ...) bare, and its own proc of that name would answer instead of the engine's. A CAPABILITIES list is generated as `global.name(...)` and cannot clash; a hand-written entries() cannot be qualified for you",
    },
];

const PRESET_FILES: &str = "code/datums/capabilities/library/preset";
const CAPS_DIR: &str = "code/datums/capabilities/";

/// `reserved_names`: cap_* globals, presets-file globals, and every global in
/// code/datums/capabilities/ that builds a capability (directly or by calling one that does).
fn reserved_names(tree: &Tree, procs: &[Proc]) -> HashSet<String> {
    let new_cap = pat!(r"\bnew\s+/datum/capability\b|\bvar/datum/capability[\w/]*\s*=\s*new\b");
    let call = pat!(r"(?<![\w./:])([A-Za-z_]\w*)\s*\(");
    let mut names: HashSet<String> = HashSet::new();
    let mut candidates: HashMap<String, String> = HashMap::new();
    for proc in procs {
        if !proc.is_global() {
            continue;
        }
        if proc.name.starts_with("cap_") || proc.rel.starts_with(PRESET_FILES) {
            names.insert(proc.name.clone());
        }
        if proc.name.starts_with("cap_") || proc.rel.starts_with(CAPS_DIR) {
            candidates.insert(proc.name.clone(), proc.body(tree).join("\n"));
        }
    }
    let mut builders: HashSet<String> = candidates.iter().filter(|(_, body)| new_cap.is_match(body)).map(|(n, _)| n.clone()).collect();
    let mut grew = true;
    while grew {
        grew = false;
        for (n, body) in &candidates {
            if !builders.contains(n) && call.captures_iter(body).iter().any(|m| builders.contains(m.s(1))) {
                builders.insert(n.clone());
                grew = true;
            }
        }
    }
    names.extend(builders);
    names
}

/// `scan_procs`: type procs on atoms (holders: capabilities() is an atom proc) named like a constructor.
fn scan_procs(tree: &Tree, procs: &[Proc]) -> Vec<(&'static str, String, usize)> {
    let names = reserved_names(tree, procs);
    procs
        .iter()
        .filter(|p| !p.is_global() && names.contains(&p.name) && lineage(&p.path).iter().any(|a| a == "/atom"))
        .map(|p| ("dx_constructor_shadow", p.rel.clone(), p.line))
        .collect()
}

/// The global procs of the engine (code/engine/): the part and declaration constructors a declaration is written with, generated capability
/// constructors included.
fn engine_constructors(procs: &[Proc]) -> HashSet<String> {
    procs.iter().filter(|p| p.is_global() && p.rel.starts_with("code/engine/")).map(|p| p.name.clone()).collect()
}

/// `scan_part_shadows`: a proc defined on a capability definition datum (a `/datum/capability` subtype or the type of a CAPABILITY_TYPE) named
/// like an engine constructor. The datum's `entries()` runs there and calls the constructors bare.
fn scan_part_shadows(tree: &Tree, procs: &[Proc]) -> Vec<(&'static str, String, usize)> {
    let names = engine_constructors(procs);
    let decls = crate::sem::decls::Decls::get(tree);
    // The capability definition datums of the engine: the type of each CAPABILITY_TYPE and the datum of each CAPABILITY_DEF. The legacy capability
    // datums (cap_*(), `interactions()`) call no part constructors and may keep procs of any name.
    let mut cap_types: HashSet<String> = HashSet::new();
    for m in decls.markers_named("CAPABILITY_TYPE") {
        if let Some(ty) = m.args.get(2) {
            cap_types.insert(ty.trim().to_string());
        }
    }
    for m in decls.markers_named("CAPABILITY_DEF") {
        if let Some(n) = m.args.first() {
            cap_types.insert(format!("/datum/capability/def/{}", n.trim()));
        }
    }
    let is_cap = |path: &str| -> bool { cap_types.contains(path) || lineage(path).iter().any(|a| cap_types.contains(a)) };
    procs
        .iter()
        .filter(|p| !p.is_global() && names.contains(&p.name) && is_cap(&p.path))
        .map(|p| ("part_constructor_shadow", p.rel.clone(), p.line))
        .collect()
}

fn scan(tree: &Tree, files: &[&SourceFile]) -> Vec<(&'static str, String, usize)> {
    let idx = DxIndex::get(tree, files);
    let mut found = scan_procs(tree, &idx.procs);
    found.extend(scan_part_shadows(tree, &idx.procs));
    found
}

const FIXTURE: &str = include_str!("../../fixtures/sys__dx_constructor_shadow/code/modules/x/selftest.dm");
const PRESETS_FIXTURE: &str = "
/proc/wall_console(board)
\treturn list()
";
const LIBRARY_FIXTURE: &str = "
/proc/power_channels(list/channels)
\treturn list(new /datum/capability/power_channels)
/proc/wires_of(atom/A)
\treturn cap_of(A, /datum/capability/wires)
/proc/cap_of(atom/A, key)
\treturn null
";

fn selftest() -> Result<String, String> {
    let lines: Vec<&str> = FIXTURE.split('\n').collect();
    let preset_rel = format!("{}s.dm", PRESET_FILES);
    let lib_rel = format!("{}library/apc.dm", CAPS_DIR);
    let tree = Tree::from_files(vec![
        SourceFile::from_text("x.dm", FIXTURE),
        SourceFile::from_text(&preset_rel, PRESETS_FIXTURE),
        SourceFile::from_text(&lib_rel, LIBRARY_FIXTURE),
    ]);
    let files: Vec<&SourceFile> = ["x.dm", preset_rel.as_str(), lib_rel.as_str()].iter().map(|r| tree.get(r).unwrap()).collect();
    let idx = DxIndex::get(&tree, &files);
    let mut got: Vec<usize> = scan_procs(&tree, &idx.procs).into_iter().filter(|(_, r, _)| r == "x.dm").map(|(_, _, n)| n).collect();
    got.sort();
    let at = |snippet: &str| -> usize { lines.iter().position(|l| l.contains(snippet)).map(|k| k + 1).unwrap_or(0) };
    let mut want = vec![at("airlock/proc/cap_lock()"), at("airlock/cap_has(bits)"), at("console/proc/wall_console()"), at("apc/proc/power_channels()")];
    want.sort();
    if got != want {
        return Err(format!("dx_constructor_shadow selftest: got {:?}, want {:?}", got, want));
    }
    // part_constructor_shadow: a capability datum's own `cooldown` proc captures the engine's constructor; an unrelated type's does not, nor does a
    // legacy capability datum's.
    let part_src = "CAPABILITY_TYPE(widget, CAP_WIDGET, /datum/e0_cap/widget, key = NONE)\n/datum/e0_cap/widget/proc/cooldown()\n\treturn 1\n/datum/capability/other/proc/cooldown()\n\treturn 2\n/obj/item/telecube/proc/cooldown()\n\treturn 3\n/datum/e0_cap/widget/sub/proc/cooldown()\n\treturn 4\n";
    let part_tree = Tree::from_files(vec![
        SourceFile::from_text("code/engine/parts/part.dm", "/proc/cooldown(t)\n\treturn t\n"),
        SourceFile::from_text("code/x.dm", part_src),
    ]);
    let part_files: Vec<&SourceFile> = ["code/engine/parts/part.dm", "code/x.dm"].iter().map(|r| part_tree.get(r).unwrap()).collect();
    let part_idx = DxIndex::get(&part_tree, &part_files);
    let part_got: Vec<usize> = scan_part_shadows(&part_tree, &part_idx.procs).into_iter().map(|(_, _, n)| n).collect();
    if part_got != vec![2, 8] {
        return Err(format!("part_constructor_shadow selftest: got {:?}, want [2, 8]", part_got));
    }
    Ok("dx_constructor_shadow".to_string())
}

pub fn register(reg: &mut Registry) {
    register_module(
        reg,
        SysModule { name: "dx_constructor_shadow", rules: RULES, files_scan: Some(scan), selftest: Some(selftest), py_selftest: true, ..SysModule::DEFAULT },
    );
}

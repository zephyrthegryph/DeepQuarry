//! Port of `tools/ci/sys_rules/resolvers.py`: map-time resolvers (systems.md section 9).
//!
//! An `Initialize()`/`LateInitialize()` that unconditionally ends its life (`init_qdel`) or does
//! its work then deletes itself at its top level (`init_self_delete`).

use std::collections::{BTreeSet, HashSet};

use crate::dm::sys::{col0, in_family, register_module, SysModule};
use crate::incr;
use crate::lint::{Registry, RuleMeta};
use crate::pat;
use crate::tree::{SourceFile, Tree};
use crate::util::before_slashes;

const RULES: &[RuleMeta] = &[
    RuleMeta { name: "init_qdel", hint: "an atom that only works at load then goes: map_resolver(GLOBAL_PROC_REF(x)) in its CAPABILITIES block (systems.md section 9)" },
    RuleMeta {
        name: "init_self_delete",
        hint: "an Initialize that does its work then deletes itself: map_resolver(GLOBAL_PROC_REF(x)) in its CAPABILITIES block (systems.md section 9)",
    },
];

fn roots_of(f: &SourceFile) -> Vec<String> {
    let mut roots: BTreeSet<String> = BTreeSet::new();
    let mut cur: Option<String> = None;
    for line in f.raw().lines() {
        if let Some(c) = pat!(r"^CAPABILITIES\((/[\w/]+)\)").captures(line) {
            cur = Some(c.s(1).to_string());
            continue;
        }
        if col0(line) {
            cur = None;
            continue;
        }
        if let Some(t) = &cur {
            if pat!(r"^	(configure\()?map_resolver\(").is_match(line) {
                roots.insert(t.clone());
            }
        }
    }
    roots.into_iter().collect()
}

fn judge(f: &SourceFile, roots: &HashSet<String>, out: &mut Vec<(&'static str, usize)>) {
    {
        let mut cur: Option<String> = None;
        for (number, line) in f.raw().numbered() {
            if let Some(c) = pat!(r"^(/[\w/]+?)/(Initialize|LateInitialize)\(").captures(line) {
                cur = Some(c.s(1).to_string());
                continue;
            }
            if col0(line) {
                cur = None;
                continue;
            }
            let Some(c) = &cur else { continue };
            let code = before_slashes(line);
            if pat!(r"^\t(return|\.\s*=)\s*INITIALIZE_HINT_QDEL\b").is_match(code)
                || (pat!(r"\bINITIALIZE_HINT_QDEL\b").is_match(code) && in_family(c, roots))
            {
                out.push(("init_qdel", number));
            } else if pat!(r"^\t(qdel\(src\)|expire\(0\)|replace_with\(src\b|qdel_self\(\))").is_match(code) {
                out.push(("init_self_delete", number));
            }
        }
    }
}

fn scan_files(_tree: &Tree, files: &[&SourceFile]) -> Vec<(&'static str, String, usize)> {
    let fs = incr::facts("sys-resolvers-facts", files, roots_of);
    let roots: BTreeSet<String> = fs.into_iter().flatten().collect();
    let key = incr::ctx_key(&roots);
    let roots: HashSet<String> = roots.into_iter().collect();
    let results = incr::keyed("sys-resolvers-judge", key, files, |f| {
        let mut v: Vec<(&'static str, usize)> = Vec::new();
        judge(f, &roots, &mut v);
        v.into_iter().map(|(rule, line)| (RULES.iter().position(|r| r.name == rule).unwrap_or(0) as u8, line as u32)).collect::<Vec<(u8, u32)>>()
    });
    let mut out = Vec::new();
    for (f, v) in files.iter().zip(results) {
        for (rule, line) in v {
            out.push((RULES[rule as usize].name, f.rel.clone(), line as usize));
        }
    }
    out
}

pub fn register(reg: &mut Registry) {
    register_module(reg, SysModule { name: "resolvers", rules: RULES, files_scan: Some(scan_files), ..SysModule::DEFAULT });
}

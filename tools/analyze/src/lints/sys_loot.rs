//! Port of `tools/ci/sys_rules/loot.py`: one declared loot system (systems.md section 8).
//!
//! Rejects `item_to_spawn`, the second loot system (`/datum/loot_table`, `loot_table_type`,
//! `loot_reward()`), and hand-rolled spawn logic on random spawners / map-resolved families.

use std::collections::{BTreeSet, HashSet};

use crate::dm::sys::{col0, in_family, register_module, SysModule};
use crate::incr;
use crate::lint::{Registry, RuleMeta};
use crate::pat;
use crate::tree::{SourceFile, Tree};
use crate::util::before_slashes;

const RULES: &[RuleMeta] = &[
    RuleMeta { name: "item_to_spawn", hint: "declare the table with DECLARE_LOOT(path, LOOT_TABLE(...)) (systems.md section 8)" },
    RuleMeta {
        name: "loot_table_datum",
        hint: "searchable tiers are DECLARE_LOOT(/loot/..., LOOT_UNCOMMON/RARE/...) + loot_search() (systems.md section 8)",
    },
    RuleMeta {
        name: "random_spawn_list",
        hint: "spawn lists and roll logic belong in DECLARE_LOOT (LOOT_TABLE/SET/SUB/HOOK), not procs or list vars (systems.md section 8)",
    },
];

fn roots_of(f: &SourceFile) -> Vec<String> {
    let mut roots: BTreeSet<String> = BTreeSet::new();
    for line in f.raw().lines() {
        if let Some(c) = pat!(r"^MAP_RESOLVER\((/[\w/]+),").captures(line) {
            roots.insert(c.s(1).to_string());
        }
    }
    roots.into_iter().collect()
}

fn judge(f: &SourceFile, roots: &HashSet<String>, out: &mut Vec<(&'static str, usize)>) {
    {
        let mut cur: Option<String> = None;
        for (number, line) in f.raw().numbered() {
            let code = before_slashes(line);
            if pat!(r"\bitem_to_spawn\b").is_match(code) {
                out.push(("item_to_spawn", number));
            }
            if pat!(r"/datum/loot_table\b|\bloot_table_type\b|\bloot_reward\s*\(").is_match(code) {
                out.push(("loot_table_datum", number));
            }
            if pat!(r"^/obj/random(_multi)?(/[\w/]*)?/(proc/|verb/)?\w+\(").is_match(code) {
                out.push(("random_spawn_list", number));
            }
            if let Some(c) = pat!(r"^(/[\w/]+)\s*(//.*)?$").captures(line) {
                cur = Some(c.s(1).to_string());
                continue;
            }
            if col0(line) {
                cur = None;
                continue;
            }
            if let Some(c) = &cur {
                if pat!(r"^\t(var/(list/)?)?(spawn_types|to_spawn|possible_\w+|items|\w+_loot)\s*=\s*list\(").is_match(code)
                    && in_family(c, roots)
                {
                    out.push(("random_spawn_list", number));
                }
            }
        }
    }
}

fn scan_files(_tree: &Tree, files: &[&SourceFile]) -> Vec<(&'static str, String, usize)> {
    let fs = incr::facts("sys-loot-facts", files, roots_of);
    let mut roots: BTreeSet<String> = BTreeSet::new();
    roots.insert("/obj/random".to_string());
    for r in fs.into_iter().flatten() {
        roots.insert(r);
    }
    let key = incr::ctx_key(&roots);
    let roots: HashSet<String> = roots.into_iter().collect();
    let results = incr::keyed("sys-loot-judge", key, files, |f| {
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
    register_module(reg, SysModule { name: "loot", rules: RULES, files_scan: Some(scan_files), ..SysModule::DEFAULT });
}

//! Port of `tools/ci/sys_rules/loot.py`: one declared loot system (systems.md section 8).
//!
//! Rejects `item_to_spawn`, the second loot system (`/datum/loot_table`, `loot_table_type`,
//! `loot_reward()`), and hand-rolled spawn logic on random spawners / map-resolved families.

use std::collections::HashSet;

use crate::dm::sys::{col0, in_family, register_module, SysModule};
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

fn scan_files(_tree: &Tree, files: &[&SourceFile]) -> Vec<(&'static str, String, usize)> {
    let mut out = Vec::new();
    let mut roots: HashSet<String> = HashSet::new();
    roots.insert("/obj/random".to_string());
    for f in files {
        for line in f.raw().lines() {
            if let Some(c) = pat!(r"^MAP_RESOLVER\((/[\w/]+),").captures(line) {
                roots.insert(c.s(1).to_string());
            }
        }
    }
    for f in files {
        let mut cur: Option<String> = None;
        for (number, line) in f.raw().numbered() {
            let code = before_slashes(line);
            if pat!(r"\bitem_to_spawn\b").is_match(code) {
                out.push(("item_to_spawn", f.rel.clone(), number));
            }
            if pat!(r"/datum/loot_table\b|\bloot_table_type\b|\bloot_reward\s*\(").is_match(code) {
                out.push(("loot_table_datum", f.rel.clone(), number));
            }
            if pat!(r"^/obj/random(_multi)?(/[\w/]*)?/(proc/|verb/)?\w+\(").is_match(code) {
                out.push(("random_spawn_list", f.rel.clone(), number));
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
                    && in_family(c, &roots)
                {
                    out.push(("random_spawn_list", f.rel.clone(), number));
                }
            }
        }
    }
    out
}

pub fn register(reg: &mut Registry) {
    register_module(reg, SysModule { name: "loot", rules: RULES, files_scan: Some(scan_files), ..SysModule::DEFAULT });
}

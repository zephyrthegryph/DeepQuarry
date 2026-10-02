//! Port of `tools/ci/sys_rules/resolvers.py`: map-time resolvers (systems.md section 9).
//!
//! An `Initialize()`/`LateInitialize()` that unconditionally ends its life (`init_qdel`) or does
//! its work then deletes itself at its top level (`init_self_delete`).

use std::collections::HashSet;

use crate::dm::sys::{col0, in_family, register_module, SysModule};
use crate::lint::{Registry, RuleMeta};
use crate::pat;
use crate::tree::{SourceFile, Tree};
use crate::util::before_slashes;

const RULES: &[RuleMeta] = &[
    RuleMeta { name: "init_qdel", hint: "an atom that only works at load then goes: MAP_RESOLVER(path, proc) (systems.md section 9)" },
    RuleMeta {
        name: "init_self_delete",
        hint: "an Initialize that does its work then deletes itself: MAP_RESOLVER(path, proc) (systems.md section 9)",
    },
];

fn scan_files(_tree: &Tree, files: &[&SourceFile]) -> Vec<(&'static str, String, usize)> {
    let mut out = Vec::new();
    let mut roots: HashSet<String> = HashSet::new();
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
                || (pat!(r"\bINITIALIZE_HINT_QDEL\b").is_match(code) && in_family(c, &roots))
            {
                out.push(("init_qdel", f.rel.clone(), number));
            } else if pat!(r"^\t(qdel\(src\)|expire\(0\)|replace_with\(src\b|qdel_self\(\))").is_match(code) {
                out.push(("init_self_delete", f.rel.clone(), number));
            }
        }
    }
    out
}

pub fn register(reg: &mut Registry) {
    register_module(reg, SysModule { name: "resolvers", rules: RULES, files_scan: Some(scan_files), ..SysModule::DEFAULT });
}

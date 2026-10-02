//! Port of `tools/ci/sys_rules/contents.py`: the materializing-walk lint (systems.md section 18).
//!
//! Inside a `tgui_data()` / `examine()` proc body, any walk or read that goes through the ledger
//! or materializes latent entries (including raw `in contents` / `in src` walks).

use crate::dm::sys::{col0, register_module, SysModule};
use crate::lint::{Registry, RuleMeta};
use crate::pat;
use crate::tree::SourceFile;
use crate::util::before_slashes;

const RULES: &[RuleMeta] = &[RuleMeta {
    name: "materializing_walk",
    hint: "FOR_REAL_CONTENTS() + latent_names()/latent_count() in tgui_data()/examine() (doc/rewrite/systems.md section 18)",
}];

fn scan_file(f: &SourceFile, out: &mut Vec<(&'static str, usize)>) {
    let mut inside = false;
    for (number, line) in f.raw().numbered() {
        if col0(line) {
            inside = pat!(r"^/[\w/]*/(?:tgui_data|examine)\s*\(").is_match(line);
            continue;
        }
        let code = before_slashes(line);
        if inside
            && (pat!(
                r"\b(?:FOR_CONTENTS|contents_of|slot_contents|slot_item|get_all_contents(?:_type)?|latent_materialize(?:_all)?|latent_entries)\s*\("
            )
            .is_match(code)
                || pat!(r"\bin\s+(?:\w+\.)?contents\b|\bin\s+src\s*\)").is_match(code))
        {
            out.push(("materializing_walk", number));
        }
    }
}

pub fn register(reg: &mut Registry) {
    register_module(reg, SysModule { name: "contents", rules: RULES, file_scan: Some(scan_file), ..SysModule::DEFAULT });
}

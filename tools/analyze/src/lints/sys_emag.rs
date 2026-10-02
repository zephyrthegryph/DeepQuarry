//! Port of `tools/ci/sys_rules/emag.py` (doc/rewrite/systems.md section 13).
//!
//! `emag_act` counts the old emag pattern, which is deleted: any `emag_act`; a direct call of a
//! declared emag effect (`on_emag(...)`) that bypasses `emag_target()`; `used_uses` bookkeeping
//! around an emag outside the card.

use crate::dm::sys::{register_module, SysModule};
use crate::lint::{Registry, RuleMeta};
use crate::pat;
use crate::tree::SourceFile;
use crate::util::before_slashes;

const RULES: &[RuleMeta] = &[RuleMeta {
    name: "emag_act",
    hint: "DECLARE_EMAG(type, PROC_REF(on_emag), msg) + emag_target() (code/__defines/sys_emag.dm, doc/rewrite/systems.md section 13)",
}];

const CARD: &str = "code/game/objects/items/weapons/id cards/cards.dm";

fn scan_file(f: &SourceFile, out: &mut Vec<(&'static str, usize)>) {
    for (number, line) in f.raw().numbered() {
        let code = before_slashes(line);
        if pat!(r"\bemag_act\b").is_match(code) {
            out.push(("emag_act", number));
            continue;
        }
        if code.contains("on_emag") && !pat!(r"^\s*/[\w/]+/(?:proc/)?on_emag\s*\(").is_match(code) {
            let stripped = code.replace("PROC_REF(on_emag)", "");
            if pat!(r"(?<![\w/])(?:[\w\].]+\.)?on_emag\s*\(").is_match(&stripped) {
                out.push(("emag_act", number));
                continue;
            }
        }
        if f.rel != CARD && pat!(r"\bused_uses\b").is_match(code) {
            out.push(("emag_act", number));
        }
    }
}

pub fn register(reg: &mut Registry) {
    register_module(reg, SysModule { name: "emag", rules: RULES, file_scan: Some(scan_file), ..SysModule::DEFAULT });
}

//! Port of `tools/ci/sys_rules/emag.py` (doc/rewrite/systems.md section 13).
//!
//! `emag_act` counts the old emag pattern, which is deleted: any `emag_act`; a direct call of a
//! declared emag effect (`on_emag(...)`) that bypasses `emag_target()`; `used_uses` bookkeeping
//! around an emag outside the card.

use crate::raw_fixture_policy::PatternApi as _;
use crate::dm::sys::{register_module, SysModule};
use crate::lint::{Registry, RuleMeta};
use crate::pat;
use crate::tree::SourceFile;
use crate::util::before_slashes;

use crate::allow_registry_fields::sys_emag::RULES;

const CARD: &str = "code/content/items/weapons/id_cards/cards.dm";

fn scan_file(f: &SourceFile, out: &mut Vec<(&'static str, usize)>) {scan_file_using(f,out,&crate::raw_fixture_policy::Fixture::legacy()).expect("legacy scan has no resource refusal")}
fn scan_file_using(f: &SourceFile, out: &mut Vec<(&'static str, usize)>,fixture:&crate::raw_fixture_policy::Fixture<'_>)->Result<(),String>{
    for (number, line) in f.raw().numbered() {
        let code = before_slashes(line);
        if fixture.pattern(r"\bemag_act\b",crate::raw_fixture_policy::PatternMode::Search,||pat!(r"\bemag_act\b")).is_match(code) {
            out.push(("emag_act", number));
            continue;
        }
        if code.contains("on_emag") && !fixture.pattern(r"^\s*/[\w/]+/(?:proc/)?on_emag\s*\(",crate::raw_fixture_policy::PatternMode::Search,||pat!(r"^\s*/[\w/]+/(?:proc/)?on_emag\s*\(")).is_match(code) {
            let stripped = code.replace("PROC_REF(on_emag)", "");
            if fixture.pattern(r"(?<![\w/])(?:[\w\].]+\.)?on_emag\s*\(",crate::raw_fixture_policy::PatternMode::Search,||pat!(r"(?<![\w/])(?:[\w\].]+\.)?on_emag\s*\(")).is_match(&stripped) {
                out.push(("emag_act", number));
                continue;
            }
        }
        if f.rel != CARD && fixture.pattern(r"\bused_uses\b",crate::raw_fixture_policy::PatternMode::Search,||pat!(r"\bused_uses\b")).is_match(code) {
            out.push(("emag_act", number));
        }
    }

Ok(())
}

pub fn register(reg: &mut Registry) {
    register_module(reg, SysModule { name: crate::allow_registry_fields::sys_emag::SCOPE_MODULE_NAME, rules: RULES, file_scan: Some(scan_file),fixture_file_scan:Some(scan_file_using), ..SysModule::DEFAULT });
}

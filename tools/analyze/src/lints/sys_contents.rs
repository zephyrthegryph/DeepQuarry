//! Port of `tools/ci/sys_rules/contents.py`: the materializing-walk lint (systems.md section 18).
//!
//! Inside a `tgui_data()` / `examine()` proc body, any walk or read that goes through the ledger
//! or materializes latent entries (including raw `in contents` / `in src` walks).

use crate::raw_fixture_policy::PatternApi as _;
use crate::dm::sys::{col0, register_module, SysModule};
use crate::lint::{Registry, RuleMeta};
use crate::pat;
use crate::tree::SourceFile;
use crate::util::before_slashes;

use crate::allow_registry_fields::sys_contents::RULES;

fn scan_file(f: &SourceFile, out: &mut Vec<(&'static str, usize)>) {scan_file_using(f,out,&crate::raw_fixture_policy::Fixture::legacy()).expect("legacy scan has no resource refusal")}
fn scan_file_using(f: &SourceFile, out: &mut Vec<(&'static str, usize)>,fixture:&crate::raw_fixture_policy::Fixture<'_>)->Result<(),String>{
    let mut inside = false;
    for (number, line) in f.raw().numbered() {
        if col0(line) {
            inside = fixture.pattern(r"^/[\w/]*/(?:tgui_data|examine)\s*\(",crate::raw_fixture_policy::PatternMode::Search,||pat!(r"^/[\w/]*/(?:tgui_data|examine)\s*\(")).is_match(line);
            continue;
        }
        let code = before_slashes(line);
        if inside
            && (fixture.pattern(r"\b(?:FOR_CONTENTS|contents_of|slot_contents|slot_item|get_all_contents(?:_type)?|latent_materialize(?:_all)?|latent_entries)\s*\(",crate::raw_fixture_policy::PatternMode::Search,||pat!(
                r"\b(?:FOR_CONTENTS|contents_of|slot_contents|slot_item|get_all_contents(?:_type)?|latent_materialize(?:_all)?|latent_entries)\s*\("
            ))
            .is_match(code)
                || fixture.pattern(r"\bin\s+(?:\w+\.)?contents\b|\bin\s+src\s*\)",crate::raw_fixture_policy::PatternMode::Search,||pat!(r"\bin\s+(?:\w+\.)?contents\b|\bin\s+src\s*\)")).is_match(code))
        {
            out.push(("materializing_walk", number));
        }
    }

Ok(())
}

pub fn register(reg: &mut Registry) {
    register_module(reg, SysModule { name: crate::allow_registry_fields::sys_contents::SCOPE_MODULE_NAME, rules: RULES, file_scan: Some(scan_file),fixture_file_scan:Some(scan_file_using), ..SysModule::DEFAULT });
}

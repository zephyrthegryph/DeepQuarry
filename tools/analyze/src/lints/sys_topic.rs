//! Port of `tools/ci/sys_rules/topic.py`: the TOPIC_ACTION registry lint (systems.md section 20).
//!
//! Topic() overrides, raw `href_list` dispatch chains, raw ref lookups and number parsing.

use crate::raw_fixture_policy::PatternApi as _;
use crate::dm::sys::{register_module, SysModule};
use crate::lint::{Registry, RuleMeta};
use crate::pat;
use crate::tree::SourceFile;
use crate::util::before_slashes;

use crate::allow_registry_fields::sys_topic::RULES;

fn scan_file(f: &SourceFile, out: &mut Vec<(&'static str, usize)>) {scan_file_using(f,out,&crate::raw_fixture_policy::Fixture::legacy()).expect("legacy scan has no resource refusal")}
fn scan_file_using(f: &SourceFile, out: &mut Vec<(&'static str, usize)>,fixture:&crate::raw_fixture_policy::Fixture<'_>)->Result<(),String>{
    for (number, line) in f.raw().numbered() {
        let code = before_slashes(line);
        if fixture.pattern(r"^/[\w/]*?/(?:proc/)?Topic\s*\(",crate::raw_fixture_policy::PatternMode::Search,||pat!(r"^/[\w/]*?/(?:proc/)?Topic\s*\(")).is_match(line) {
            out.push(("topic_override", number));
        }
        if fixture.pattern(r"\b(?:if|switch)\s*\(\s*!?\s*href_list\s*\[|\bIF_VV_OPTION\s*\(",crate::raw_fixture_policy::PatternMode::Search,||pat!(r"\b(?:if|switch)\s*\(\s*!?\s*href_list\s*\[|\bIF_VV_OPTION\s*\(")).is_match(code) {
            out.push(("topic_raw_dispatch", number));
        }
        if fixture.pattern(r"\blocate(?:_in_list)?\s*\([^)]*\bhref_list\s*\[",crate::raw_fixture_policy::PatternMode::Search,||pat!(r"\blocate(?:_in_list)?\s*\([^)]*\bhref_list\s*\[")).is_match(code) {
            out.push(("topic_raw_locate", number));
        }
        if fixture.pattern(r"\btext2num\s*\(\s*href_list\s*\[",crate::raw_fixture_policy::PatternMode::Search,||pat!(r"\btext2num\s*\(\s*href_list\s*\[")).is_match(code) {
            out.push(("topic_raw_num", number));
        }
    }

Ok(())
}

pub fn register(reg: &mut Registry) {
    register_module(reg, SysModule { name: crate::allow_registry_fields::sys_topic::SCOPE_MODULE_NAME, rules: RULES, file_scan: Some(scan_file),fixture_file_scan:Some(scan_file_using), ..SysModule::DEFAULT });
}

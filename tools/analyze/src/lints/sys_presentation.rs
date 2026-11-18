//! Port of `tools/ci/sys_rules/presentation.py`: mob presentation is reactive.
//!
//! A call of a HUD or sight pass (`life_hud*()`, `life_vision*()`) or of the deleted
//! `refresh_vision()` from content, outside another pass proc.

use crate::raw_fixture_policy::PatternApi as _;
use crate::dm::sys::{col0, register_module, SysModule};
use crate::lint::{Registry, RuleMeta};
use crate::pat;
use crate::tree::SourceFile;
use crate::util::before_slashes;

use crate::allow_registry_fields::sys_presentation::RULES;

const QUERIES: [&str; 3] = ["_wanted", "_idle", "_rewake_delay"];

fn scan_file(f: &SourceFile, out: &mut Vec<(&'static str, usize)>) {scan_file_using(f,out,&crate::raw_fixture_policy::Fixture::legacy()).expect("legacy scan has no resource refusal")}
fn scan_file_using(f: &SourceFile, out: &mut Vec<(&'static str, usize)>,fixture:&crate::raw_fixture_policy::Fixture<'_>)->Result<(),String>{
    if f.rel.starts_with("code/_generated/") {
        return Ok(());
    }
    let mut proc: Option<String> = None;
    for (number, line) in f.raw().numbered() {
        if col0(line) {
            proc = fixture.pattern(r"^/[\w/]*?/(?:(?:proc|verb)/)?(\w+)\s*\(",crate::raw_fixture_policy::PatternMode::Search,||pat!(r"^/[\w/]*?/(?:(?:proc|verb)/)?(\w+)\s*\(")).captures(line).map(|c| c.s(1).to_string());
            continue;
        }
        let code = before_slashes(line);
        let Some(m) = fixture.pattern(r"(?<![\w/])(?:[\w\]\)]+\.)?(life_hud\w*|life_vision\w*|refresh_vision)\s*\(",crate::raw_fixture_policy::PatternMode::Search,||pat!(r"(?<![\w/])(?:[\w\]\)]+\.)?(life_hud\w*|life_vision\w*|refresh_vision)\s*\(")).captures(code) else {
            continue;
        };
        if QUERIES.iter().any(|q| m.s(1).ends_with(q)) {
            continue;
        }
        if let Some(p) = &proc {
            if !p.is_empty() && fixture.pattern(r"^(?:life_hud|life_vision)",crate::raw_fixture_policy::PatternMode::Search,||pat!(r"^(?:life_hud|life_vision)")).is_match(p) {
                continue;
            }
        }
        out.push(("presentation_call", number));
    }

Ok(())
}

pub fn register(reg: &mut Registry) {
    register_module(reg, SysModule { name: crate::allow_registry_fields::sys_presentation::SCOPE_MODULE_NAME, rules: RULES, file_scan: Some(scan_file),fixture_file_scan:Some(scan_file_using), ..SysModule::DEFAULT });
}

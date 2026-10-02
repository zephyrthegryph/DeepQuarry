//! Port of `tools/ci/sys_rules/presentation.py`: mob presentation is reactive.
//!
//! A call of a HUD or sight pass (`life_hud*()`, `life_vision*()`) or of the deleted
//! `refresh_vision()` from content, outside another pass proc.

use crate::dm::sys::{col0, register_module, SysModule};
use crate::lint::{Registry, RuleMeta};
use crate::pat;
use crate::tree::SourceFile;
use crate::util::before_slashes;

const RULES: &[RuleMeta] = &[RuleMeta {
    name: "presentation_call",
    hint: "write the input through its setter or PUBLISH_CHANGE the key that covers it (MOB_KEY_*); the HUD / sight reactions run by themselves (living_systems.dm)",
}];

const QUERIES: [&str; 3] = ["_wanted", "_idle", "_rewake_delay"];

fn scan_file(f: &SourceFile, out: &mut Vec<(&'static str, usize)>) {
    if f.rel.starts_with("code/_generated/") {
        return;
    }
    let mut proc: Option<String> = None;
    for (number, line) in f.raw().numbered() {
        if col0(line) {
            proc = pat!(r"^/[\w/]*?/(?:(?:proc|verb)/)?(\w+)\s*\(").captures(line).map(|c| c.s(1).to_string());
            continue;
        }
        let code = before_slashes(line);
        let Some(m) = pat!(r"(?<![\w/])(?:[\w\]\)]+\.)?(life_hud\w*|life_vision\w*|refresh_vision)\s*\(").captures(code) else {
            continue;
        };
        if QUERIES.iter().any(|q| m.s(1).ends_with(q)) {
            continue;
        }
        if let Some(p) = &proc {
            if !p.is_empty() && pat!(r"^(?:life_hud|life_vision)").is_match(p) {
                continue;
            }
        }
        out.push(("presentation_call", number));
    }
}

pub fn register(reg: &mut Registry) {
    register_module(reg, SysModule { name: "presentation", rules: RULES, file_scan: Some(scan_file), ..SysModule::DEFAULT });
}

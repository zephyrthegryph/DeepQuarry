//! Port of `tools/ci/sys_rules/topic.py`: the TOPIC_ACTION registry lint (systems.md section 20).
//!
//! Topic() overrides, raw `href_list` dispatch chains, raw ref lookups and number parsing.

use crate::dm::sys::{register_module, SysModule};
use crate::lint::{Registry, RuleMeta};
use crate::pat;
use crate::tree::SourceFile;
use crate::util::before_slashes;

const RULES: &[RuleMeta] = &[
    RuleMeta {
        name: "topic_override",
        hint: "declare TOPIC_ACTION(type, href_key, PROC_REF(handler), specs...) rows instead of overriding Topic() (doc/rewrite/systems.md section 20)",
    },
    RuleMeta {
        name: "topic_raw_dispatch",
        hint: "one TOPIC_ACTION row per href key (\"key=value\" rows for value switches) instead of if/switch on href_list[...]",
    },
    RuleMeta {
        name: "topic_raw_locate",
        hint: "declare TOPIC_REF(name, type[, source]) and read args[name]; never locate() a ref straight from href_list",
    },
    RuleMeta {
        name: "topic_raw_num",
        hint: "declare TOPIC_NUM(name) and read args[name] instead of text2num(href_list[...])",
    },
];

fn scan_file(f: &SourceFile, out: &mut Vec<(&'static str, usize)>) {
    for (number, line) in f.raw().numbered() {
        let code = before_slashes(line);
        if pat!(r"^/[\w/]*?/(?:proc/)?Topic\s*\(").is_match(line) {
            out.push(("topic_override", number));
        }
        if pat!(r"\b(?:if|switch)\s*\(\s*!?\s*href_list\s*\[|\bIF_VV_OPTION\s*\(").is_match(code) {
            out.push(("topic_raw_dispatch", number));
        }
        if pat!(r"\blocate(?:_in_list)?\s*\([^)]*\bhref_list\s*\[").is_match(code) {
            out.push(("topic_raw_locate", number));
        }
        if pat!(r"\btext2num\s*\(\s*href_list\s*\[").is_match(code) {
            out.push(("topic_raw_num", number));
        }
    }
}

pub fn register(reg: &mut Registry) {
    register_module(reg, SysModule { name: "topic", rules: RULES, file_scan: Some(scan_file), ..SysModule::DEFAULT });
}

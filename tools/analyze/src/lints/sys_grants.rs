//! Port of `tools/ci/sys_rules/grants.py`: verbs through grants (systems.md section 19).
//!
//! The verb store is the only writer of a `verbs` list; any write elsewhere is a finding. No ALLOW.

use crate::dm::sys::{register_module, SysModule};
use crate::lint::{Registry, RuleMeta};
use crate::pat;
use crate::tree::SourceFile;
use crate::util::before_slashes;

const RULES: &[RuleMeta] = &[RuleMeta {
    name: "verb_write",
    hint: "om_grant(target, GRANT_VERB | GRANT_VERB_HIDE, verb, source) / om_revoke(), or DECLARE_VERB* on the type; the store is the only verbs writer (doc/rewrite/systems.md section 19)",
}];

const STORE: &str = "code/engine/present/verb_store.dm";

fn scan_file(f: &SourceFile, out: &mut Vec<(&'static str, usize)>) {
    if f.rel == STORE {
        return;
    }
    for (number, line) in f.raw().numbered() {
        let stripped = pat!(r#""(?:[^"\\]|\\.)*""#).replace_all(line, "\"\"");
        let code = before_slashes(&stripped);
        if pat!(
            r"\badd_verb\s*\(|\bremove_verb\s*\(|\bverbs\s*(\+|-|\||&|\^)=|\bverbs\s*=(?!=)|\bverbs\s*\.\s*(Add|Remove|Cut|Insert|Swap|Splice)\s*\(|\bverbs\s*\[[^\]]*\]\s*=(?!=)|\bnew\s*/[\w/]*/(proc|verb)/\w+\s*\("
        )
        .is_match(code)
        {
            out.push(("verb_write", number));
        }
    }
}

pub fn register(reg: &mut Registry) {
    register_module(
        reg,
        SysModule { name: "grants", rules: RULES, no_allow: &["verb_write"], file_scan: Some(scan_file), ..SysModule::DEFAULT },
    );
}

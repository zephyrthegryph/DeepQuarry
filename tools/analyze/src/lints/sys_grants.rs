//! Port of `tools/ci/sys_rules/grants.py`: verbs through grants (systems.md section 19).
//!
//! The verb store is the only writer of a `verbs` list; any write elsewhere is a finding. No ALLOW.

use crate::raw_fixture_policy::PatternApi as _;
use crate::dm::sys::{register_module, SysModule};
use crate::lint::{Registry, RuleMeta};
use crate::pat;
use crate::tree::SourceFile;
use crate::util::before_slashes;

use crate::allow_registry_fields::sys_grants::RULES;

const STORE: &str = "code/engine/present/verb_store.dm";

fn scan_file(f: &SourceFile, out: &mut Vec<(&'static str, usize)>) {scan_file_using(f,out,&crate::raw_fixture_policy::Fixture::legacy()).expect("legacy scan has no resource refusal")}
fn scan_file_using(f: &SourceFile, out: &mut Vec<(&'static str, usize)>,fixture:&crate::raw_fixture_policy::Fixture<'_>)->Result<(),String>{
    if f.rel == STORE {
        return Ok(());
    }
    for (number, line) in f.raw().numbered() {
        let stripped=fixture.replace_static(r#""(?:[^"\\]|\\.)*""#,line,"\"\"",||pat!(r#""(?:[^"\\]|\\.)*""#))?;
        let code = before_slashes(&stripped);
        if fixture.pattern(r"\badd_verb\s*\(|\bremove_verb\s*\(|\bverbs\s*(\+|-|\||&|\^)=|\bverbs\s*=(?!=)|\bverbs\s*\.\s*(Add|Remove|Cut|Insert|Swap|Splice)\s*\(|\bverbs\s*\[[^\]]*\]\s*=(?!=)|\bnew\s*/[\w/]*/(proc|verb)/\w+\s*\(",crate::raw_fixture_policy::PatternMode::Search,||pat!(
            r"\badd_verb\s*\(|\bremove_verb\s*\(|\bverbs\s*(\+|-|\||&|\^)=|\bverbs\s*=(?!=)|\bverbs\s*\.\s*(Add|Remove|Cut|Insert|Swap|Splice)\s*\(|\bverbs\s*\[[^\]]*\]\s*=(?!=)|\bnew\s*/[\w/]*/(proc|verb)/\w+\s*\("
        ))
        .is_match(code)
        {
            out.push(("verb_write", number));
        }
    }

Ok(())
}

pub fn register(reg: &mut Registry) {
    register_module(
        reg,
        SysModule { name: crate::allow_registry_fields::sys_grants::SCOPE_MODULE_NAME, rules: RULES, no_allow: &["verb_write"], file_scan: Some(scan_file),fixture_file_scan:Some(scan_file_using), ..SysModule::DEFAULT },
    );
}

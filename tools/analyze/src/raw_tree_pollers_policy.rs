//! Unique polling lexical policy, reused by legacy and recorded-page adapters.
use crate::raw_fixture_policy::PatternApi as _;
use std::borrow::Cow;
use crate::lint::{Meta,Policy,RuleMeta,ScanKind};
use crate::tree::{SourceFile,CODE_MAPS_DM};
use crate::{pat,pat_match};
use crate::util::{is_py_space,py_lstrip};
use crate::raw_tree_report::Reporter;
pub static META: Meta = Meta {
    name: crate::allow_registry_fields::pollers::SCOPE_META_0.name,
    group: crate::allow_registry_fields::pollers::SCOPE_META_0.group,
    label: "pollers",
    legacy: "tools/ci/pollers_lint.py",
    select: CODE_MAPS_DM,
    scan: ScanKind::Both,
    policy: Policy::Hard,
    rules: &[
        RuleMeta { name: "process", hint: "put the work on a pipeline (code/datums/om/periodic.dm)" },
        RuleMeta { name: "start", hint: "use om_task_periodic() or a machine wake" },
        RuleMeta { name: "step_coverage", hint: "" },
    ],
    allow: crate::allow_registry_fields::pollers::ALLOW_0,
    lists: crate::allow_registry_fields::pollers::SCOPE_META_0.lists,
};

/// `strip_comment`: drops a trailing `//` comment outside double quotes (a `"` after a backslash
/// does not toggle).
fn strip_comment(line: &str) -> Cow<'_, str> {
    if !line.contains("//") {
        return Cow::Borrowed(line); // nothing to cut: the loop below would copy the line
    }
    let chars: Vec<char> = line.chars().collect();
    let mut out = String::new();
    let mut in_str = false;
    let mut i = 0;
    while i < chars.len() {
        let c = chars[i];
        if c == '"' && (i == 0 || chars[i - 1] != '\\') {
            in_str = !in_str;
        }
        if !in_str && c == '/' && chars.get(i + 1) == Some(&'/') {
            break;
        }
        out.push(c);
        i += 1;
    }
    Cow::Owned(out)
}


pub fn scan_file(f:&SourceFile,out:&mut impl Reporter){scan_file_with_fixture(f,out,&crate::raw_fixture_policy::Fixture::legacy())}
pub fn scan_file_with_fixture(f:&SourceFile,out:&mut impl Reporter,fixture:&crate::raw_fixture_policy::Fixture<'_>){
        let mut in_type = false;
        let mut in_block_comment = false;
        for (number, raw) in f.raw().numbered() {if !out.checkpoint(){return}
            let line = raw.trim_end_matches('\r');
            if in_block_comment {
                if line.contains("*/") {
                    in_block_comment = false;
                }
                continue;
            }
            if py_lstrip(line).starts_with("/*") && !line.contains("*/") {
                in_block_comment = true;
                continue;
            }
            let code = strip_comment(line);
            let is_process = fixture.pattern(r"^/[\w/]+?/(?:proc/)?process\(",crate::raw_fixture_policy::PatternMode::Match,||crate::pat_match!(r"^/[\w/]+?/(?:proc/)?process\(")).is_match(&code) || (in_type && fixture.pattern(r"^\t(?:proc/)?process\(",crate::raw_fixture_policy::PatternMode::Match,||crate::pat_match!(r"^\t(?:proc/)?process\(")).is_match(&code));
            let is_start = !fixture.pattern(r"^\s*#\s*define\b",crate::raw_fixture_policy::PatternMode::Match,||crate::pat_match!(r"^\s*#\s*define\b")).is_match(&code) && fixture.pattern(r"(?<![\w])START_(?:MACHINE_)?PROCESSING\(",crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(r"(?<![\w])START_(?:MACHINE_)?PROCESSING\(")).is_match(&code);
            // Asked only about a line that would otherwise count.
            let kept = (is_process || is_start) && out.allowed(f, number, "pollers");
            if is_process && !kept {
                out.site_in_msg("process", &f.rel, number, "process() definition");
            }
            if fixture.pattern(r"^/[\w/]+\s*(?://.*)?$",crate::raw_fixture_policy::PatternMode::Match,||crate::pat_match!(r"^/[\w/]+\s*(?://.*)?$")).is_match(&code) {
                in_type = true;
            } else if code.chars().next().map(|c| !is_py_space(c)).unwrap_or(false) {
                in_type = false;
            }
            if is_start && !kept {
                out.site_in_msg("start", &f.rel, number, "START_*PROCESSING call");
            }
        }
}
pub fn steps(f:&SourceFile)->Vec<(u32,String)>{steps_using(f,&mut crate::key_policy_control::Compatibility).expect("original polling steps")}
pub fn steps_using<C:crate::key_policy_control::Control>(f:&SourceFile,c:&mut C)->Result<Vec<(u32,String)>,C::Error>{steps_using_with_fixture(f,c,&crate::raw_fixture_policy::Fixture::legacy())}
pub fn steps_using_with_fixture<C:crate::key_policy_control::Control>(f:&SourceFile,c:&mut C,fixture:&crate::raw_fixture_policy::Fixture<'_>)->Result<Vec<(u32,String)>,C::Error>{let mut steps=Vec::new();c.checkpoint()?;if f.text().contains("machine_step("){for(n,line)in f.raw().numbered(){c.checkpoint()?;if let Some(m)=fixture.pattern(r"^(/obj/machinery[\w/]*?)/machine_step\(",crate::raw_fixture_policy::PatternMode::Match,||crate::pat_match!(r"^(/obj/machinery[\w/]*?)/machine_step\(")).captures(line){crate::raw_tree_report::row(c,&mut steps)?;steps.push((n as u32,crate::raw_tree_report::own(c,m.s(1))?));}}}c.checkpoint()?;Ok(steps)}

pub fn report_steps(rel:&str,steps:&[(u32,String)],out:&mut impl Reporter){for(n,t)in steps{if !out.checkpoint(){return}out.site_in_msg("step_coverage",rel,*n as usize,format!("{} defines machine_step(): machine work is started_work()",t));}}

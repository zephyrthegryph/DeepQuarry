//! Port of `tools/ci/check_deadline_polling.py` (doc/rewrite/object_model_core.md sec 4.11, roadmap S3).
//!
//! A periodic body that compares `world.time` with a stored deadline is polling a timer; that
//! belongs in `om_after()`. The scan is shared with the sys rule `deadline_poll`
//! (`crate::dm::deadline`). A site that must stay carries `// ALLOW(sys_deadline_poll): <reason>`;
//! whole procs can still be listed in `tools/ci/deadline_polling_allowlist.txt` (`path:proc_path`
//! per line, a reason after `#`; a stale entry is an error, so the list only shrinks).
//!
//! Shape: every non-ALLOWed hit is a site keyed `path:proc_path`; `finish` reads the allowlist and
//! judges (the allowlist is a custom baseline format, so the policy is `Custom`). An allowlist entry
//! with no reason aborts the old script at once; `finish` does the same. The scan skips
//! `/unit_tests/` through `lint_scopes.toml`.

use std::collections::BTreeMap;
use std::fmt::Write as _;

use crate::baseline::Mode;
use crate::dm::deadline;
use crate::lint::{Cx, Lint, Meta, Policy, Registry, Run, RuleMeta, ScanKind, Sink};
use crate::parity::{ParseKind, Parity};
use crate::tree::{SourceFile, CODE_DM};
use crate::util::py_strip;

const ALLOWLIST: &str = "tools/ci/deadline_polling_allowlist.txt";
const HINT: &str = "Use om_after(src, deadline - world.time, PROC_REF(...)) instead (doc/rewrite/object_model_core.md sec 4.11), or allowlist with a reason.";

static META: Meta = Meta {
    name: "deadline_polling",
    group: "",
    label: "deadline_polling",
    legacy: "tools/ci/check_deadline_polling.py",
    select: CODE_DM,
    scan: ScanKind::File,
    policy: Policy::Custom,
    rules: &[RuleMeta { name: "deadline_poll", hint: HINT }],
    allow: crate::allow_registry_fields::deadline_polling::ALLOW_0,
    lists: &[],
};

struct DeadlinePolling;

/// `load_allowlist`: `{entry: line number}`, or the line that has no reason.
fn load_allowlist(path: &std::path::Path) -> Result<BTreeMap<String, usize>, (usize, String)> {
    let Ok(text) = std::fs::read_to_string(path) else { return Ok(BTreeMap::new()) };
    parse_allowlist_text(text)
}

pub(crate) fn parse_allowlist_text(text:String)->Result<BTreeMap<String,usize>,(usize,String)>{
 match parse_allowlist_using(text,&mut crate::key_policy_control::Compatibility){Ok(value)=>value,Err(never)=>match never{}}
}
fn parse_allowlist_using<C:crate::key_policy_control::Control>(text:String,control:&mut C)->Result<Result<BTreeMap<String,usize>,(usize,String)>,C::Error>{
 use crate::key_policy_control as kc;control.checkpoint()?;let text=crate::util::universal_newlines(text);let mut entries=BTreeMap::<String,usize>::new();
 // The final empty split piece is skipped below, exactly as the old collected
 // lines Vec/pop. Borrowed iteration needs no all-lines allocation.
 for(i,raw)in text.split('\n').enumerate(){control.checkpoint()?;let line=py_strip(raw.split('#').next().unwrap_or(""));if line.is_empty(){continue}
  if !raw.contains('#'){return Ok(Err((i+1,kc::own(control,line)?)))}
  if let Some(number)=entries.get_mut(line){*number=i+1;}else{kc::reserve(control,||1024usize.checked_add(std::mem::size_of::<String>())?.checked_add(std::mem::size_of::<usize>()))?;let key=kc::own(control,line)?;entries.insert(key,i+1);}
 }
 control.checkpoint()?;Ok(Ok(entries))
}

impl Lint for DeadlinePolling {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_file(&self, _cx: &Cx, f: &SourceFile, out: &mut Sink) {
        let lines = f.raw().lines_vec();
        for hit in deadline::scan_lines(&lines) {
            if out.allowed(f, hit.line, "sys_deadline_poll") {
                continue;
            }
            let key = format!("{}:{}", f.rel, hit.proc_path);
            out.site_keyed("deadline_poll", &f.rel, hit.line, format!("{} compares world.time with a stored deadline: {}", hit.proc_path, hit.text), key);
        }
    }

    fn finish(&self, cx: &Cx, run: &Run, text: &mut String) -> bool {
        let path=cx.tree.root.join(ALLOWLIST);
        judge_observed_allowlist(run,&path.to_string_lossy(),load_allowlist(&path),text)
    }

    fn update_baseline(&self, _cx: &Cx, _run: &Run, _mode: Mode) -> std::io::Result<String> {
        Ok(observed_baseline_report())
    }

    fn parity(&self) -> Option<Parity> {
        Some(Parity {
            old: &["tools/ci/check_deadline_polling.py"],
            old_raw: &[],
            blank: &[ALLOWLIST],
            parse: ParseKind::FileLineAny,
            update: None,
            seed: None,
            files: &[],
            selftest: None,
        })
    }
}

pub(crate) fn judge_observed_allowlist(run:&Run,shown:&str,observed:Result<BTreeMap<String,usize>,(usize,String)>,text:&mut String)->bool {
        let allow = match observed {
            Ok(a) => a,
            Err((number, line)) => {
                let _ = writeln!(text, "{}:{}: entry has no reason: {}", shown, number, line);
                return true;
            }
        };
        let mut findings: BTreeMap<&str, Vec<&crate::lint::Site>> = BTreeMap::new();
        for s in &run.sites {
            findings.entry(s.key.as_str()).or_default().push(s);
        }
        let mut bad: Vec<&crate::lint::Site> = Vec::new();
        for (key, hits) in &findings {
            if !allow.contains_key(*key) {
                bad.extend(hits.iter().copied());
            }
        }
        let stale: Vec<(&String, &usize)> = allow.iter().filter(|(k, _)| !findings.contains_key(k.as_str())).collect();
        for s in &bad {
            let _ = writeln!(text, "{}:{}: {}", s.rel, s.line, s.msg);
        }
        // Python iterates the allowlist dict in file order.
        let mut stale_in_order = stale.clone();
        stale_in_order.sort_by_key(|(_, n)| **n);
        for (key, number) in &stale_in_order {
            let _ = writeln!(text, "{}:{}: stale entry (nothing matches it any more): {}", shown, number, key);
        }
        let _ = writeln!(
            text,
            "Deadline polling: {} periodic bodies found, {} allowlisted, {} new finding(s), {} stale entr{}.",
            findings.len(),
            allow.len(),
            bad.len(),
            stale.len(),
            if stale.len() == 1 { "y" } else { "ies" }
        );
        if !bad.is_empty() || !stale.is_empty() {
            let _ = writeln!(text, "{}", HINT.replace("sec 4.11", "\u{a7}4.11"));
            return true;
        }
        false
    }

pub(crate) fn captured_metadata()->&'static Meta{&META}

pub fn register(reg: &mut Registry) {
    reg.add(DeadlinePolling);
}

/// As-of report data only; the caller must supply a validated native observation.
/// These variants never issue a filesystem/source receipt.
#[derive(Clone,Copy)]pub enum ReportAllowlist<'a>{CapturedUtf8(&'a str),ProvenMissing,CapturedNonUtf8}
/// Same original parser and judgement used by the ordinary CLI. No file IO.
/// Prepared policy data, never a source/EOF receipt. It is issued from a
/// caller's already-validated observation through the unique original parser.
pub struct ObservedDeadlineAllowlist{entries:Result<BTreeMap<String,usize>,(usize,String)>}
impl ObservedDeadlineAllowlist{pub fn finish(self,run:&Run,shown:&str,text:&mut String)->bool{judge_observed_allowlist(run,shown,self.entries,text)}}
pub fn prepare_observed_report<C:crate::key_policy_control::Control>(observation:ReportAllowlist<'_>,control:&mut C)->Result<ObservedDeadlineAllowlist,C::Error>{
 use crate::key_policy_control as kc;
 let entries=match observation{ReportAllowlist::CapturedUtf8(text)=>{kc::reserve(control,||text.len().checked_mul(2)?.checked_add(64))?;let input=kc::own(control,text)?;parse_allowlist_using(input,control)?},ReportAllowlist::ProvenMissing|ReportAllowlist::CapturedNonUtf8=>{control.checkpoint()?;Ok(BTreeMap::new())}};Ok(ObservedDeadlineAllowlist{entries})
}
pub fn finish_observed_report(run:&Run,shown:&str,observation:ReportAllowlist<'_>,text:&mut String)->bool{
 let parsed=match prepare_observed_report(observation,&mut crate::key_policy_control::Compatibility){Ok(value)=>value,Err(never)=>match never{}};parsed.finish(run,shown,text)
}

pub fn observed_baseline_report()->String{"deadline_polling: the allowlist is hand-maintained (no --update)".to_owned()}
#[cfg(test)]#[path="../../../dmb/shared/test_scratch.rs"]mod deadline_report_test_scratch;
#[cfg(test)]#[path="../../fixtures/original_policies/deadline_polling.rs"]mod report_original;
#[cfg(test)]mod observed_report_tests{
 use super::*;
 #[test]fn observed_deadline_report_matches_the_original_file_loader_all_reason_order_and_utf8_cases(){
  let root=deadline_report_test_scratch::dir("deadline-observed-report");let path=root.join("allowlist.txt");let run=Run{sites:vec![crate::lint::Site{rule:"deadline_poll".into(),rel:"code/a.dm".into(),line:2,msg:"actual periodic body".into(),key:"code/a.dm:/datum/a/proc/tick".into(),ident:String::new()}],notes:Vec::new()};
  for source in ["code/a.dm:/datum/a/proc/tick # actual reason\r\n", "missing # first stale reason\ncode/a.dm:/datum/a/proc/tick # actual reason\nmissing # replacement stale reason\n", "broken reasonless entry\n", "# only comment\n", ""]{std::fs::write(&path,source).unwrap();let mut old=String::new();let failed=report_original::original_finish_loaded(&run,&path,&mut old);let mut actual=String::new();let same=finish_observed_report(&run,&path.to_string_lossy(),ReportAllowlist::CapturedUtf8(source),&mut actual);assert_eq!((same,actual),(failed,old));}
  for observation in [ReportAllowlist::ProvenMissing,ReportAllowlist::CapturedNonUtf8]{match observation{ReportAllowlist::ProvenMissing=>{let _=std::fs::remove_file(&path);},ReportAllowlist::CapturedNonUtf8=>std::fs::write(&path,[0xff]).unwrap(),_=>unreachable!()}let mut expected=String::new();let failed=report_original::original_finish_loaded(&run,&path,&mut expected);let mut actual=String::new();let same=finish_observed_report(&run,&path.to_string_lossy(),observation,&mut actual);assert_eq!((same,actual),(failed,expected));}
 }
 struct Control{left:usize,polls:usize,stop:usize}
 impl crate::key_policy_control::Control for Control{type Error=std::io::Error;const CHECKED:bool=true;fn checkpoint(&mut self)->Result<(),Self::Error>{self.polls+=1;if self.polls==self.stop{Err(std::io::Error::from_raw_os_error(1450))}else{Ok(())}}fn reserve(&mut self,n:usize)->Result<(),Self::Error>{self.left=self.left.checked_sub(n).ok_or_else(||std::io::Error::from(std::io::ErrorKind::OutOfMemory))?;Ok(())}fn overflow(&mut self)->Self::Error{std::io::ErrorKind::OutOfMemory.into()}fn allocation_failed(&mut self)->Self::Error{std::io::ErrorKind::OutOfMemory.into()}}
 #[test]fn observed_deadline_parser_funds_only_unique_live_entries_and_preserves_actual_stop_and_quota(){let source="key # actual reason\n".repeat(1000);let mut control=Control{left:100_000,polls:0,stop:usize::MAX};let parsed=prepare_observed_report(ReportAllowlist::CapturedUtf8(&source),&mut control).unwrap();let entries=parsed.entries.unwrap();assert_eq!(entries.len(),1);assert_eq!(entries["key"],1000);let mut denied=Control{left:1,polls:0,stop:usize::MAX};assert_eq!(prepare_observed_report(ReportAllowlist::CapturedUtf8("key # reason"),&mut denied).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);let mut stopped=Control{left:100_000,polls:0,stop:4};assert_eq!(prepare_observed_report(ReportAllowlist::CapturedUtf8("key # reason"),&mut stopped).err().unwrap().raw_os_error(),Some(1450));}

}

#[cfg(test)]mod actual_registry_tests{
 fn exactly_one(registry:&crate::lint::Registry){assert_eq!(registry.lints.iter().filter(|lint|lint.meta().name=="deadline_polling").count(),1,"the actual generated production registry must not auto-register a test-only original policy");}
 #[test]fn generated_production_registry_registers_deadline_polling_exactly_once(){let mut registry=crate::lint::Registry::default();crate::lints::register(&mut registry);exactly_one(&registry);#[cfg(feature="legacy-sem")]exactly_one(&crate::run::registry());#[cfg(feature="native-policy")]exactly_one(crate::captured_raw_policy::registry());}
}

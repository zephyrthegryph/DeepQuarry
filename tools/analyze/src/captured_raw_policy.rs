//! Reuse unchanged, audited raw-only policy over compiler-owned source views.
//! This is explicit captured-file coverage, never a whole-workspace proof.
//! No Engine::new, filesystem discovery, legacy semantic model, generator,
//! baseline mutation or second DM parser runs at this boundary.
use crate::{
    lint::{AllowUse, Cx, Registry, Run, ScanKind, Sink},
    scopes::Scopes,
    tree::{SourceFile, Tree},
};
use dm_analysis::policy_inputs::{PolicyInputs, PolicyRole, TextView};
use std::{
    panic::{catch_unwind, AssertUnwindSafe},
    path::Path,
    sync::Arc,
};

/// Explicit migration fixture admission; not lint ceilings or CPU/RSS guarantees.
pub const MAX_FIXTURE_FILE_BYTES: usize = 256 * 1024;
pub const MAX_FIXTURE_TOTAL_BYTES: usize = 8 * 1024 * 1024;
pub const MAX_FIXTURE_SITES: usize = 10_000;
pub const RAW_FILE_LINTS: &[&str] = &crate::native_policy_roster::RAW_FILE_LINT_NAMES;
pub(crate) fn registry() -> &'static Registry {
    static REGISTRY: std::sync::OnceLock<Registry> = std::sync::OnceLock::new();
    REGISTRY.get_or_init(|| {
        let mut reg = Registry::default();
        include!(concat!(env!("OUT_DIR"), "/native_policy_registry_gen.rs"));
        reg
    })
}
/// Original policy metadata, reused for strict finding admission and later
/// host-owned ratchet judgment. No semantic model is queried.
pub fn metadata(name: &str) -> Option<&'static crate::lint::Meta> {
    registry().find(name).map(|lint| lint.meta())
}
/// Invoke the SAME native registration, including its actual inherited default.
/// This only runs fixture callbacks; it grants no producer/source completion.
pub fn registered_selftest(name:&str)->Option<Result<String,String>>{
 registry().find(name).map(|lint|lint.selftest())
}
/// Host authenticates exact bytes or absence through the native request ledger.
/// This enum does not itself prove a filesystem observation or full config closure.
#[derive(Clone, Copy)]
pub enum Configuration<'a> {
    Captured(&'a [u8]),
    ProvenMissing,
}
pub struct RawRun {
    pub name: String,
    pub run: Run,
    pub allow_used: Vec<AllowUse>,
}
pub struct CapturedRawPolicy {
    pub(crate) tree: Tree,
    pub(crate) scopes: Arc<Scopes>,
}
fn require_distinct_report_paths(files: &[SourceFile]) -> Result<(), String> {
    let mut names = std::collections::BTreeSet::new();
    for file in files {
        if !names.insert(file.rel.as_str()) {
            return Err(format!(
                "distinct captured provider keys collide in report path: {}",
                file.rel
            ));
        }
    }
    Ok(())
}
impl CapturedRawPolicy {
    /// Validate current raw-view authority without demanding unrelated variable
    /// classification or body facts. Content equality alone grants no ownership.
    pub(crate) fn validate_current_raw_roster(&self, inputs: &PolicyInputs) -> Result<(), String> {
        let expected = inputs
            .files()
            .filter(|file| file.role() == PolicyRole::DmSource)
            .count();
        if expected != self.tree.files.len() {
            return Err("current raw policy source roster is incomplete".into());
        }
        let mut seen = std::collections::BTreeSet::new();
        for file in &self.tree.files {
            if !seen.insert(file.abs.as_path()) {
                return Err("current raw policy source roster has duplicate paths".into());
            }
            let current = inputs
                .file(&file.abs)
                .ok_or("raw policy source is not in the current capture")?;
            if current.role() != PolicyRole::DmSource {
                return Err("current raw policy source role differs".into());
            }
            let raw = current
                .view(TextView::AnalyzeRaw)
                .map_err(|error| error.to_string())?;
            if !raw.same_view(&file.raw().text) {
                return Err("raw policy view belongs to another source acquisition".into());
            }
        }
        Ok(())
    }
    pub fn capture(
        root: &Path,
        inputs: &PolicyInputs,
        configuration: Configuration<'_>,
    ) -> Result<Self, String> {
        if !root.is_absolute() {
            return Err("raw policy root must be absolute".into());
        }
        let root = dm_preprocess::regions::canonical_path(root);
        let mut files = Vec::new();
        let mut total_bytes = match configuration {
            Configuration::Captured(bytes) => bytes.len(),
            Configuration::ProvenMissing => 0,
        };
        if total_bytes > MAX_FIXTURE_FILE_BYTES {
            return Err("raw-policy fixture configuration exceeds per-file admission".into());
        }
        for file in inputs
            .files()
            .filter(|file| file.role() == PolicyRole::DmSource)
        {
            let absolute = dm_preprocess::regions::canonical_path(file.path().as_ref());
            // Containment/report projection only: preserve the captured provider
            // key, including its original safe DOS-verbatim spelling.
            let relative = dm_preprocess::regions::relative_filesystem_path(&absolute, &root)
                .ok_or("captured raw source lies outside policy root")?;
            let rel = relative.to_string_lossy().replace('\\', "/");
            let raw = file
                .view(TextView::AnalyzeRaw)
                .map_err(|error| error.to_string())?
                .clone();
            if raw.len() > MAX_FIXTURE_FILE_BYTES {
                return Err("raw-policy fixture source exceeds per-file admission".into());
            }
            total_bytes = total_bytes
                .checked_add(raw.len())
                .ok_or("raw-policy fixture byte accounting overflow")?;
            if total_bytes > MAX_FIXTURE_TOTAL_BYTES {
                return Err("raw-policy fixture sources exceed total admission".into());
            }
            files.push(SourceFile::from_shared_text(&rel, absolute, raw));
        }
        let scopes = match configuration {
            Configuration::Captured(bytes) => match std::str::from_utf8(bytes) {
                Ok(text) => Scopes::parse(text)?,
                // Existing Scopes::load read_to_string treats invalid UTF8 as
                // an IO error and returns default scopes; preserve that branch.
                Err(_) => Scopes::default(),
            },
            Configuration::ProvenMissing => Scopes::default(),
        };
        require_distinct_report_paths(&files)?;
        Ok(Self {
            tree: Tree::from_captured_files(root, files),
            scopes: Arc::new(scopes),
        })
    }
    /// Assemble a bounded cross-file owner from the existing RAW_FILE nodes.
    /// Each current raw view comes from the native issued receipt; cached
    /// projections are reused after exact byte/path validation, never as proof.
    pub fn from_shared_files(
        root: &Path,
        inputs: &PolicyInputs,
        config: &crate::captured_raw_file::Config,
        shared: &[Arc<crate::captured_raw_file::File>],
    ) -> Result<Self, String> {
        if !root.is_absolute() {
            return Err("policy root must be absolute".into());
        }
        let root = dm_preprocess::regions::canonical_path(root);
        let expected = inputs
            .files()
            .filter(|file| file.role() == PolicyRole::DmSource)
            .count();
        if expected != shared.len() {
            return Err("shared source roster is incomplete".into());
        }
        let mut seen = std::collections::BTreeSet::new();
        let mut files = Vec::with_capacity(shared.len());
        let mut total = 0usize;
        for cached in shared {
            if cached.root() != root || !seen.insert(cached.path().to_path_buf()) {
                return Err("shared source root or duplicate path differs".into());
            }
            let current = inputs
                .file(cached.path())
                .ok_or("cached source absent from capture")?;
            if current.role() != PolicyRole::DmSource {
                return Err("shared source role differs".into());
            }
            let raw = current
                .view(TextView::AnalyzeRaw)
                .map_err(|error| error.to_string())?;
            if raw.len() > MAX_FIXTURE_FILE_BYTES {
                return Err("shared source exceeds fixture admission".into());
            }
            total = total
                .checked_add(raw.len())
                .ok_or("shared source accounting overflow")?;
            if total > MAX_FIXTURE_TOTAL_BYTES {
                return Err("shared sources exceed fixture admission".into());
            }
            files.push(cached.rebound_source(cached.path(), raw.clone())?);
        }
        files.sort_by(|a, b| a.rel.cmp(&b.rel));
        require_distinct_report_paths(&files)?;
        Ok(Self {
            tree: Tree::from_captured_files(root, files),
            scopes: config.shared_scopes(),
        })
    }
    /// Shared sources are reported by their allocation identities, so owners
    /// count once even when raw and typed policy nodes hold different wrappers.
    pub fn visit_policy_storage(
        &self,
        mut visit: impl FnMut(crate::tree::PolicyStorageKey, usize),
    ) {
        for file in &self.tree.files {
            file.visit_policy_storage(&mut visit);
        }
    }
    /// These are raw findings and consumed ALLOW records only. The host retains
    /// baseline/ceiling judgment, unused-ALLOW aggregation and unique generators.
    /// Every selected policy must complete; any unsupported access discards all.
    pub fn scan(
        &self,
        names: &[String],
        mut checkpoint: impl FnMut() -> Result<(), String>,
    ) -> Result<Vec<RawRun>, String> {
        if let Some(error) = self.tree.captured_violation() {
            return Err(error);
        }
        if names.is_empty() {
            return Err("explicit raw-policy lint list required".into());
        }
        for name in names {
            if !RAW_FILE_LINTS.contains(&name.as_str()) {
                return Err(format!(
                    "lint {name} has not been admitted as raw-file-only"
                ));
            }
        }
        let registry = registry();
        let mut runs = Vec::new();
        let mut completed_sites = 0usize;
        let result = catch_unwind(AssertUnwindSafe(|| -> Result<(), String> {
            for lint in registry
                .lints
                .iter()
                .filter(|lint| names.iter().any(|name| name == lint.meta().name))
            {
                checkpoint()?;
                let meta = lint.meta();
                if meta.scan != ScanKind::File {
                    return Err(format!(
                        "raw-only lint {} changed its scan contract",
                        meta.name
                    ));
                }
                let scope = self.scopes.for_lint(meta.name, meta.group);
                let cx = Cx { fixture:None,
                    tree: &self.tree,
                    meta,
                    scope: &scope,
                };
                let mut sink = Sink::new();
                for file in cx.files() {
                    checkpoint()?;
                    sink.cur = file.rel.clone();
                    lint.scan_file(&cx, file, &mut sink);
                    // A legacy per-file scan finishes before this admission
                    // check. Reject the complete batch; never truncate sites.
                    if completed_sites.saturating_add(sink.sites.len()) > MAX_FIXTURE_SITES {
                        return Err("raw-policy fixture exceeds finding admission".into());
                    }
                    if let Some(error) = self.tree.captured_violation() {
                        return Err(error);
                    }
                }
                completed_sites = completed_sites.saturating_add(sink.sites.len());
                runs.push(RawRun {
                    name: meta.name.into(),
                    run: Run {
                        sites: sink.sites,
                        notes: sink.notes,
                    },
                    allow_used: sink.allow_used,
                });
            }
            Ok(())
        }));
        match result {
            Ok(Ok(())) => Ok(runs),
            Ok(Err(error)) => Err(error),
            Err(_) => Err(self
                .tree
                .captured_violation()
                .unwrap_or_else(|| "raw policy panicked; findings discarded".into())),
        }
    }
}
#[cfg(test)]
#[path = "captured_raw_policy_tests.rs"]
mod tests;

#[cfg(test)]
mod report_collision_tests {
    use super::*;
    #[test]
    fn distinct_provider_keys_cannot_last_win_the_same_report_path() {
        let files = vec![
            SourceFile::from_shared_text(
                "code/a.dm",
                std::path::PathBuf::from("/provider-one/code/a.dm"),
                "var/a".into(),
            ),
            SourceFile::from_shared_text(
                "code/a.dm",
                std::path::PathBuf::from("/provider-two/code/a.dm"),
                "var/b".into(),
            ),
        ];
        assert!(require_distinct_report_paths(&files).is_err());
        assert!(require_distinct_report_paths(&files[..1]).is_ok());
    }
}

/// Fixture DATA only, never a completed workspace/policy frame.
pub struct RawSelftestResult{completed:usize,names:Vec<&'static str>,failures:Vec<RawSelftestFailure>,successes:Option<Vec<RawSelftestFailure>>}
struct RawSelftestFailure{ordinal:usize,message:String}
impl RawSelftestResult{
 pub fn completed(&self)->usize{self.completed}
 pub fn failed(&self)->usize{self.failures.len()}
 pub fn matches_names(&self,names:&[String])->bool{self.names.iter().copied().eq(names.iter().map(String::as_str))}
 pub fn failures(&self)->impl Iterator<Item=(&'static str,&str)>{self.failures.iter().map(|row|(self.names[row.ordinal],row.message.as_str()))}
 pub fn write_standalone(&self,out:&mut impl std::io::Write)->std::io::Result<()>{
  let successes=self.successes.as_ref().ok_or_else(||std::io::Error::new(std::io::ErrorKind::InvalidInput,"catalog did not retain actual standalone callback messages"))?;
  if self.completed!=self.names.len()||successes.len()+self.failures.len()!=self.completed{return Err(std::io::Error::new(std::io::ErrorKind::InvalidData,"standalone callback transcript is incomplete"))}
  let mut failures=self.failures.iter().peekable();let mut successes=successes.iter();
  for (ordinal,name) in self.names.iter().enumerate(){
   if failures.peek().is_some_and(|row|row.ordinal==ordinal){let row=failures.next().expect("observed actual failure");writeln!(out,"selftest FAILED: {name}: {}",row.message)?;}
   else{let row=successes.next().filter(|row|row.ordinal==ordinal).ok_or_else(||std::io::Error::new(std::io::ErrorKind::InvalidData,"standalone callback message is absent"))?;writeln!(out,"selftest ok: {name} {}",row.message)?;}
  }Ok(())
 }
 pub fn write_failures(&self,out:&mut impl std::io::Write)->std::io::Result<()>{for(name,message)in self.failures(){writeln!(out,"selftest FAILED: {name}: {message}")?;}Ok(())}
 #[cfg(test)]fn exposed_heap_bytes(&self)->usize{self.names.capacity()*std::mem::size_of::<&'static str>()+self.failures.capacity()*std::mem::size_of::<RawSelftestFailure>()+self.failures.iter().map(|row|row.message.capacity()).sum::<usize>()}
}
fn selftest_oom(message:impl Into<String>)->crate::captured_reactive_reads::Failure{crate::captured_reactive_reads::Failure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,message.into()))}
fn selftest_row<T>(rows:&mut Vec<T>,budget:&crate::captured_generator_budget::Budget)->Result<(),crate::captured_reactive_reads::Failure>{
 if rows.len()<rows.capacity(){return Ok(())}
 let needed=rows.len().checked_add(1).ok_or_else(||selftest_oom("selftest row overflow"))?;
 let upper=needed.checked_mul(4).ok_or_else(||selftest_oom("selftest capacity overflow"))?;
 let bytes=upper.checked_mul(std::mem::size_of::<T>()).ok_or_else(||selftest_oom("selftest row bytes overflow"))?;
 budget.charge(bytes).map_err(selftest_oom)?;
 rows.try_reserve_exact(1).map_err(|e|selftest_oom(e.to_string()))?;
 if rows.capacity()>upper{return Err(selftest_oom("selftest exposed row capacity exceeds its prior admission"))}Ok(())
}
/// SAME native raw Registry/callbacks as scans. No legacy Engine/parser,
/// filesystem marker or parallel success memo. Actual callback temporary heap
/// still requires independent qualification; retained result storage is charged.
pub fn run_registered_raw_selftests(names:&[String],budget:&Arc<crate::captured_generator_budget::Budget>,poll:&dyn Fn()->std::io::Result<()>)->Result<RawSelftestResult,crate::captured_reactive_reads::Failure>{
 use crate::captured_reactive_reads::Failure;
 poll()?;budget.require().map_err(selftest_oom)?;
 if names.is_empty()||names.len()>RAW_FILE_LINTS.len()||names.iter().enumerate().any(|(i,name)|!RAW_FILE_LINTS.contains(&name.as_str())||names[..i].contains(name)){return Err(Failure::Unsupported("selftests require a nonempty exact native raw-policy roster; other producers remain unported".into()))}
 let fixed=std::mem::size_of::<crate::captured_generator_budget::Budget>()+2*std::mem::size_of::<usize>();let required=MAX_FIXTURE_TOTAL_BYTES.checked_sub(fixed).ok_or_else(||selftest_oom("selftest fixed metadata exceeds existing allowance"))?;
 if budget.remaining()<required{budget.charge(required).map_err(selftest_oom)?;return Err(selftest_oom("selftest allowance changed during admission"))}
 let mut actual=Vec::new();
 for name in names{poll()?;budget.require().map_err(selftest_oom)?;let lint=registry().find(name).ok_or_else(||Failure::Unsupported("raw selftest lacks its actual native registration".into()))?;selftest_row(&mut actual,budget)?;actual.push(lint.meta());}
 run_native_selftest_catalog(&actual,budget,poll,|meta,local|registered_selftest_funded(meta.name,local,poll).expect("validated immutable native registry"))
  .map_err(|failure|match failure{crate::derived_selftest_policy::Failure::Operational(actual)=>Failure::Operational(actual),crate::derived_selftest_policy::Failure::Assertion(message)=>Failure::Unsupported(message)})
}
// Private DATA fold; production supplies only the actual native callbacks.
fn run_raw_selftest_callbacks(names:Vec<&'static str>,budget:&crate::captured_generator_budget::Budget,checkpoint:&dyn Fn()->Result<(),crate::captured_reactive_reads::Failure>,mut callback:impl FnMut(&str)->Result<String,String>)->Result<RawSelftestResult,crate::captured_reactive_reads::Failure>{
 budget.charge(names.capacity().checked_mul(std::mem::size_of::<&'static str>()).ok_or_else(||selftest_oom("selftest names overflow"))?).map_err(selftest_oom)?;
 let mut result=RawSelftestResult{completed:0,names,failures:Vec::new(),successes:None};
 for ordinal in 0..result.names.len(){
  checkpoint()?;selftest_row(&mut result.failures,budget)?;
  let actual=callback(result.names[ordinal]);checkpoint()?;result.completed+=1;
  if let Err(message)=actual{budget.charge(message.capacity()).map_err(selftest_oom)?;result.failures.push(RawSelftestFailure{ordinal,message});}
 }
 checkpoint()?;Ok(result)
}
#[cfg(test)]mod native_raw_selftest_controls{
 use super::*;
 fn names(rows:&[&str])->Vec<String>{rows.iter().map(|s|(*s).to_owned()).collect()}
 #[test]fn actual_native_raw_callbacks_run_and_unported_rosters_never_become_empty_passes(){
  let budget=crate::captured_generator_budget::Budget::new(MAX_FIXTURE_TOTAL_BYTES).unwrap();let actual=run_registered_raw_selftests(&names(&["reactions_table_proc","entry_slots"]),&budget,&||Ok(())).unwrap();assert_eq!((actual.completed(),actual.failed()),(2,0));assert!(actual.matches_names(&names(&["reactions_table_proc","entry_slots"])));assert!(budget.used()>=actual.exposed_heap_bytes());
  for rows in [&[][..],&["derived_reads"][..],&["ui_actions"][..],&["entry_slots","entry_slots"][..]]{let budget=crate::captured_generator_budget::Budget::new(MAX_FIXTURE_TOTAL_BYTES).unwrap();assert!(matches!(run_registered_raw_selftests(&names(rows),&budget,&||Ok(())),Err(crate::captured_reactive_reads::Failure::Unsupported(_))));}
 }
 #[test]fn native_raw_selftest_actual_first_io_and_fixture_quota_refuse_then_recover(){
  let budget=crate::captured_generator_budget::Budget::new(MAX_FIXTURE_TOTAL_BYTES).unwrap();let Err(crate::captured_reactive_reads::Failure::Operational(actual))=run_registered_raw_selftests(&names(&["entry_slots"]),&budget,&||Err(std::io::Error::from_raw_os_error(1450)))else{panic!("actual first IO required")};assert_eq!(actual.raw_os_error(),Some(1450));
  let tight=crate::captured_generator_budget::Budget::new(MAX_FIXTURE_TOTAL_BYTES-1).unwrap();assert!(matches!(run_registered_raw_selftests(&names(&["entry_slots"]),&tight,&||Ok(())),Err(crate::captured_reactive_reads::Failure::Operational(ref e))if e.kind()==std::io::ErrorKind::OutOfMemory));let healthy=crate::captured_generator_budget::Budget::new(MAX_FIXTURE_TOTAL_BYTES).unwrap();assert_eq!(run_registered_raw_selftests(&names(&["entry_slots"]),&healthy,&||Ok(())).unwrap().completed(),1);
 }
 #[test]fn selftest_failure_fold_preserves_typed_names_text_order_and_admits_actual_retained_capacity(){
  let budget=crate::captured_generator_budget::Budget::new(MAX_FIXTURE_TOTAL_BYTES).unwrap();let mut seen=Vec::new();let actual=run_raw_selftest_callbacks(vec!["first","second"],&budget,&||Ok(()),|name|{seen.push(name.to_owned());Err(format!("{name} detail"))}).unwrap();assert_eq!(seen,["first","second"]);assert_eq!((actual.completed(),actual.failed()),(2,2));assert_eq!(actual.failures().map(|(name,_)|name).collect::<Vec<_>>(),["first","second"]);let mut out=Vec::new();actual.write_failures(&mut out).unwrap();assert_eq!(out,b"selftest FAILED: first: first detail\nselftest FAILED: second: second detail\n");assert!(budget.used()>=actual.exposed_heap_bytes());
 }
 #[test]fn earlier_fixture_failure_never_hides_later_operational_io_or_completes_a_result(){
  let budget=crate::captured_generator_budget::Budget::new(MAX_FIXTURE_TOTAL_BYTES).unwrap();let polls=std::cell::Cell::new(0);let stopped=||{let n=polls.get()+1;polls.set(n);if n==3{Err(crate::captured_reactive_reads::Failure::Operational(std::io::Error::from_raw_os_error(1450)))}else{Ok(())}};let Err(crate::captured_reactive_reads::Failure::Operational(actual))=run_raw_selftest_callbacks(vec!["first","second"],&budget,&stopped,|_|Err("retained fixture failure".into()))else{panic!("actual later IO must prevent completed callback result")};assert_eq!(actual.raw_os_error(),Some(1450));
 }
}

/// Checked catalog fold. Each callback gets a root window in the SAME operation
/// allowance, so its own existing scoped temporary budgets remain usable.
/// The host must hold its original physical grant throughout this call. These
/// result rows are DATA, never an input/source/policy-completion certificate.
pub fn run_native_selftest_catalog(
 metas:&[&'static crate::lint::Meta],budget:&std::sync::Arc<crate::captured_generator_budget::Budget>,poll:&dyn Fn()->std::io::Result<()>,callback:impl FnMut(&'static crate::lint::Meta,&std::sync::Arc<crate::captured_generator_budget::Budget>)->Result<String,crate::derived_selftest_policy::Failure>,
)->Result<RawSelftestResult,crate::derived_selftest_policy::Failure>{run_native_selftest_catalog_mode(metas,budget,poll,false,callback)}
pub fn run_native_selftest_catalog_mode(
 metas:&[&'static crate::lint::Meta],budget:&std::sync::Arc<crate::captured_generator_budget::Budget>,
 poll:&dyn Fn()->std::io::Result<()>,retain_successes:bool,
 mut callback:impl FnMut(&'static crate::lint::Meta,&std::sync::Arc<crate::captured_generator_budget::Budget>)->Result<String,crate::derived_selftest_policy::Failure>,
)->Result<RawSelftestResult,crate::derived_selftest_policy::Failure>{
 use crate::{captured_generator_budget::Budget,derived_selftest_policy::Failure};
 let oom=|message:String|Failure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,message));
 poll()?;budget.require().map_err(oom)?;
 if metas.is_empty()||metas.iter().enumerate().any(|(i,meta)|metas[..i].iter().any(|old|old.name==meta.name)){return Err(Failure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidInput,"native selftest catalog requires exact distinct registered metadata")))}
 let upper=metas.len().checked_mul(4).ok_or_else(||oom("native selftest roster overflow".into()))?;
 budget.charge(upper.checked_mul(std::mem::size_of::<&'static str>()+std::mem::size_of::<RawSelftestFailure>()).ok_or_else(||oom("native selftest roster bytes overflow".into()))?).map_err(oom)?;
 let mut names=Vec::new();let mut failures=Vec::new();names.try_reserve_exact(metas.len()).map_err(|e|oom(e.to_string()))?;failures.try_reserve_exact(metas.len()).map_err(|e|oom(e.to_string()))?;
 if names.capacity()>upper||failures.capacity()>upper{return Err(oom("native selftest roster capacity exceeds its admitted bound".into()))}
 for meta in metas{names.push(meta.name)}
 let successes=if retain_successes{budget.charge(upper.checked_mul(std::mem::size_of::<RawSelftestFailure>()).ok_or_else(||oom("native standalone roster bytes overflow".into()))?).map_err(oom)?;let mut rows=Vec::new();rows.try_reserve_exact(metas.len()).map_err(|e|oom(e.to_string()))?;if rows.capacity()>upper{return Err(oom("native standalone roster exposed excess capacity".into()))}Some(rows)}else{None};
 let mut result=RawSelftestResult{completed:0,names,failures,successes};
 for(ordinal,meta)in metas.iter().enumerate(){
  poll()?;budget.require().map_err(oom)?;
  let window=Budget::reserve_window(budget,MAX_FIXTURE_TOTAL_BYTES).map_err(oom)?;
  let local=Budget::new(window.capacity()).map_err(oom)?;
  let actual=callback(meta,&local);
  // An actual operational failure wins before any later checkpoint. The
  // callback's owned assertion result is still under the live real window.
  let actual=match actual{Err(Failure::Operational(first))=>return Err(Failure::Operational(first)),other=>other};
  local.require().map_err(oom)?;poll()?;
  match actual{
   Ok(message)=>{if let Some(successes)=&mut result.successes{let retained=message.capacity();drop(local);window.settle(retained).map_err(oom)?;successes.push(RawSelftestFailure{ordinal,message});}else{drop(message);drop(local);window.settle(0).map_err(oom)?;}},
   Err(Failure::Assertion(message))=>{let retained=message.capacity();drop(local);window.settle(retained).map_err(oom)?;result.failures.push(RawSelftestFailure{ordinal,message});},
   Err(Failure::Operational(_))=>unreachable!("actual first IO returned above"),
  }
  result.completed+=1;
 }
 poll()?;budget.require().map_err(oom)?;Ok(result)
}

/// The actual immutable native registration, with an explicit caller-budget
/// fixture loan. Only shared fixture DATA is produced; no policy/source receipt.
pub fn registered_selftest_funded(name:&str,budget:&Arc<crate::captured_generator_budget::Budget>,poll:&dyn Fn()->std::io::Result<()>)->Option<Result<String,crate::derived_selftest_policy::Failure>>{
 let lint=registry().find(name)?;
 let fixture=crate::raw_fixture_policy::Fixture::native(budget,poll);
 let actual=lint.selftest_with_fixture(&fixture);
 Some(fixture.finish(actual))
}

/// The native host path supplies its actual same-session query/lender provider.
/// The older funded fixture helper remains container-only and explicitly does
/// not qualify legacy regex program/scratch ownership.
pub fn registered_selftest_funded_with_patterns(name:&str,budget:&Arc<crate::captured_generator_budget::Budget>,poll:&dyn Fn()->std::io::Result<()>,patterns:&dyn crate::native_pattern::Provider)->Option<Result<String,crate::derived_selftest_policy::Failure>>{
 let lint=registry().find(name)?;
 let fixture=crate::raw_fixture_policy::Fixture::native_patterns(budget,poll,patterns);
 let actual=lint.selftest_with_fixture(&fixture);Some(fixture.finish(actual))
}

#[cfg(test)]mod funded_fixture_controls{
 use super::*;
 #[test]fn actual_ten_shared_raw_callbacks_preserve_original_assertions_and_result_text(){
  for name in ["cap_bits","dcs","entry_slots","reactions_table_proc","sys/dx_manual_transfer","sys/dx_raw_delay","sys/dx_raw_overlays","sys/dx_review","sys/sync_sql","sys/usr_use"]{
   let original=registry().find(name).expect("actual native registration").selftest();
   let budget=crate::captured_generator_budget::Budget::new(MAX_FIXTURE_TOTAL_BYTES).unwrap();
   let actual=registered_selftest_funded(name,&budget,&||Ok(())).unwrap();
   match(original,actual){(Ok(a),Ok(b))=>assert_eq!(a,b,"{name}"),(Err(a),Err(crate::derived_selftest_policy::Failure::Assertion(b)))=>assert_eq!(a,b,"{name}"),other=>panic!("actual shared callback differs for {name}: {other:?}")}
  }
 }
}

#[cfg(test)]mod standalone_catalog_controls{
 use super::*;
 #[test]fn actual_catalog_standalone_keeps_actual_success_and_failure_messages_in_registered_order(){
  let a=metadata("dcs").unwrap();let b=metadata("entry_slots").unwrap();let budget=crate::captured_generator_budget::Budget::new(MAX_FIXTURE_TOTAL_BYTES).unwrap();
  let result=run_native_selftest_catalog_mode(&[a,b],&budget,&||Ok(()),true,|meta,local|{if meta.name==a.name{registered_selftest_funded(meta.name,local,&||Ok(())).unwrap()}else{Err(crate::derived_selftest_policy::Failure::Assertion("actual checked assertion failure".into()))}}).unwrap();
  assert_eq!((result.completed(),result.failed()),(2,1));let mut text=Vec::new();result.write_standalone(&mut text).unwrap();let text=String::from_utf8(text).unwrap();assert!(text.starts_with("selftest ok: dcs "));assert!(text.ends_with("selftest FAILED: entry_slots: actual checked assertion failure
"));assert!(budget.used()>=result.successes.as_ref().unwrap()[0].message.capacity());
 }
}

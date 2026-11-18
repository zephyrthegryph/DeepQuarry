//! Real captured Sys reactive fixture with genuine negative AUTO observation.
use super::{BuildHost,full_registry_check::{NativeFixtureSources,NativeSelftestWork,NativeFixtureMessage,native_fixture_macro}};
use std::{io,error::Error,path::Path};use dq_analyze::{derived_selftest_policy::{Failure,NativeAssertions},key_policy_control as kc};
impl BuildHost{pub(super) fn run_native_sys_reactive_fixture_selftest_using(&mut self,cache:&Path,work:&NativeSelftestWork<'_>)->Result<NativeFixtureMessage,Box<dyn Error>>{
 if crate::daemon::control::WorkerContext::capture_for_checkpoints().is_none(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"Sys fixture requires the original active request context").into())}
 let fixed=dq_analyze::sys_reactive_selftest_policy::FIXTURE;
 let mut control=NativeAssertions{budget:work.budget(),poll:&crate::daemon::control::checkpoint};let mut scratch=NativeFixtureSources::new_using(cache,work)?;
 let result=(||->Result<Result<String,String>,Box<dyn Error>>{
  let caps=include_str!("../../../../../code/defines/engine/capabilities.dm");let byond=include_str!("../../../../../code/__byond_version_compat.dm");
  let mut definitions=String::new();for(source,prefix)in[(caps,"#define TRACKED_UNCHANGED("),(caps,"#define TRACKED("),(caps,"#define SETTER("),(byond,"#define PROC_REF(")]{let actual=native_fixture_macro(source,prefix)?;use dq_analyze::key_policy_control::Control;control.reserve(actual.len().checked_mul(4).and_then(|n|n.checked_add(128)).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?).map_err(|failure|match failure{Failure::Operational(actual)=>actual,Failure::Assertion(message)=>io::Error::other(message)})?;definitions.push_str(actual);}
  // Definitions live outside AUTO_REL. Creating AUTO merely to install these
  // macros would change the original fixture's conditional semantic branch.
  scratch.put("code/defines/native_selftest_macros.dm",definitions.as_bytes())?;scratch.put("code/fixture.dm",fixed.as_bytes())?;scratch.put("deepquarry.dme",b"#include \"code/defines/native_selftest_macros.dm\"\n#include \"code/fixture.dm\"\n")?;scratch.put("tools/ci/lint_scopes.toml",include_bytes!("../../../../ci/lint_scopes.toml"))?;
  let request=scratch.query_request_using(cache)?;
  self.with_native_sys_reactive_fixture_request(request,|data|match dq_analyze::sys_reactive_selftest_policy::assert_rows(data.sites().iter().map(|site|(site.rule.as_str(),site.line as usize)),&mut control){Ok(actual)=>Ok(Ok(actual)),Err(Failure::Assertion(text))=>Ok(Err(text)),Err(Failure::Operational(actual))=>Err(actual)})
 })();
 self.clear_regions();let cleanup=scratch.remove();let actual=match result{Err(actual)=>return Err(actual),Ok(actual)=>{cleanup?;actual}};Ok(NativeFixtureMessage::new(actual,work)?)
}}
#[cfg(test)]mod controls{
 use super::*;
 #[test]fn actual_native_sys_reactive_callback_uses_recorded_auto_absence_and_original_assertions(){let cache=crate::test_scratch::dir("native-sys-reactive-fixture");let mut host=BuildHost::default();super::super::full_registry_check::with_full_registry_check_context(crate::request::BuildCommand::PrepareQuery,Some(120),||{let credit=host.source_arena_work().reserve(dq_analyze::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES)?;let budget=dq_analyze::captured_generator_budget::Budget::new(dq_analyze::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES).map_err(io::Error::other)?;let actual=host.run_native_sys_reactive_fixture_selftest_using(&cache,&NativeSelftestWork::new(&credit,&budget)?)?;assert_eq!(actual.outcome().unwrap(),"dx_reactive");Ok(())}).unwrap();}
}

//! Actual raw UI producer on the same host, under the original selftest loan.
use super::{BuildHost,full_registry_check::{NativeFixtureSources,NativeSelftestWork,NativeFixtureMessage}};
use std::{error::Error,io,path::Path};
use dq_analyze::{derived_selftest_policy::{Failure,NativeAssertions},ui_selftest_policy as fixture};
fn actual_io(actual:Box<dyn Error>)->io::Error{match actual.downcast::<io::Error>(){Ok(actual)=>*actual,Err(other)=>io::Error::other(other.to_string())}}
fn request(scratch:&NativeFixtureSources,cache:&Path)->Result<crate::request::BuildRequest,Box<dyn Error>>{Ok(scratch.query_request_using(cache)?)}
fn sources(scratch:&mut NativeFixtureSources)->io::Result<()>{
 scratch.put(dq_analyze::ui_actions_policy::DISPATCHER,fixture::DISPATCHER_FIXTURE.as_bytes())?;
 scratch.put("code/fixture.dm",fixture::DM_FIXTURE.as_bytes())?;
 scratch.put("code/library/capabilities/library/fixture.dm",fixture::BUNDLE_FIXTURE.as_bytes())?;
 scratch.put("tgui/packages/tgui/interfaces/Thing.tsx",fixture::TSX_FIXTURE.as_bytes())?;
 scratch.put("tgui/packages/tgui/interfaces/Old.tsx",b"act('nope');\n")?;
 scratch.put("tools/ci/lint_scopes.toml",include_bytes!("../../../../ci/lint_scopes.toml"))?;Ok(())
}
impl BuildHost{
 /// Borrowed live dispatcher DATA must come from the ordinary caller's actual
 /// positive/negative captured candidates. This fixture operation does no
 /// ambient cwd/manifest fallback, and publishes no selftest success cache.
 pub(crate) fn run_native_ui_fixture_selftest(&mut self,cache:&Path,live_dispatcher:Option<&str>)->Result<NativeFixtureMessage,Box<dyn Error>>{
  if crate::daemon::control::WorkerContext::capture_for_checkpoints().is_none(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"native UI callback requires the original active request context").into())}
  let credit=self.source_arena_work().reserve(dq_analyze::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES)?;
  let budget=dq_analyze::captured_generator_budget::Budget::new(dq_analyze::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES).map_err(|message|io::Error::new(io::ErrorKind::OutOfMemory,message))?;
  self.run_native_ui_fixture_selftest_using(cache,live_dispatcher,&NativeSelftestWork::new(&credit,&budget)?)
 }
 pub(super) fn run_native_ui_fixture_selftest_using(&mut self,cache:&Path,live_dispatcher:Option<&str>,work:&NativeSelftestWork<'_>)->Result<NativeFixtureMessage,Box<dyn Error>>{
  if crate::daemon::control::WorkerContext::capture_for_checkpoints().is_none(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"native UI callback requires the original active request context").into())}
  let mut control=NativeAssertions{budget:work.budget(),poll:&crate::daemon::control::checkpoint};
  let queries=std::sync::Arc::clone(self.query_db());
  let prelude=queries.with_native_fixture_patterns(work.budget(),|patterns|match fixture::check_inputs_with_patterns(live_dispatcher,&mut control,patterns){Err(Failure::Operational(actual))=>Err(actual),result=>Ok(result)})?;
  match prelude{Ok(())=>(),Err(Failure::Assertion(text))=>return Ok(NativeFixtureMessage::new(Err(text),work)?),Err(Failure::Operational(actual))=>return Err(actual.into())}
  // Static fixture/config payloads are borrowed writes. Their actual parsed
  // values belong to the existing request/source ledger, not 64 copies here.
  let mut scratch=NativeFixtureSources::new_using(cache,work)?;
  let result=(||->Result<Result<String,String>,Box<dyn Error>>{
   sources(&mut scratch)?;let request=request(&scratch,cache)?;let mut seen=false;let mut assertion=None;
   self.with_native_ui_fixture_request(request,&mut|actual|{
    if seen{return Err("native UI fixture collector repeated actual callback".into())}seen=true;
    match actual.check_original(&mut control){Ok(())=>(),Err(Failure::Assertion(text))=>assertion=Some(text),Err(Failure::Operational(actual))=>return Err(dq_analyze::captured_reactive_reads::Failure::Operational(actual))}Ok(())
   })?;
   if !seen{return Err(io::Error::new(io::ErrorKind::InvalidData,"native UI fixture did not deliver its real productive rows").into())}
   if let Some(text)=assertion{Ok(Err(text))}else{use dq_analyze::key_policy_control as kc;Ok(Ok(kc::own(&mut control,"ui_actions_lint selftest ok").map_err(|failure|match failure{Failure::Operational(actual)=>actual,Failure::Assertion(text)=>io::Error::other(text)})?))}
  })();
  self.clear_regions();let cleanup=scratch.remove();let actual=match result{Err(actual)=>return Err(actual),Ok(actual)=>{cleanup?;actual}};
  Ok(NativeFixtureMessage::new(actual,work)?)
 }
}
#[cfg(test)]mod controls{
 use super::*;
 #[test]fn actual_native_ui_callback_runs_original_checks_on_same_host_without_model_or_body(){
  let cache=crate::test_scratch::dir("native-ui-fixture-callback");let mut host=BuildHost::default();let db=host.query_db().clone();let before=db.db().stats(dm_query::Kind(4)).computed;
  super::super::full_registry_check::with_full_registry_check_context(crate::request::BuildCommand::PrepareQuery,Some(120),||{let message=host.run_native_ui_fixture_selftest(&cache,Some(fixture::DISPATCHER_FIXTURE))?;assert_eq!(message.outcome().unwrap(),"ui_actions_lint selftest ok");Ok(())}).unwrap();
  assert_eq!(host.query_db().db().stats(dm_query::Kind(4)).computed,before);
 }
 #[test]fn actual_native_ui_callback_keeps_live_dispatcher_assertion_then_recovers(){
  let cache=crate::test_scratch::dir("native-ui-fixture-live");let mut host=BuildHost::default();let changed=fixture::DISPATCHER_FIXTURE.replace("length(raw) > 64","length(raw) > 1");
  super::super::full_registry_check::with_full_registry_check_context(crate::request::BuildCommand::PrepareQuery,Some(120),||{let failed=host.run_native_ui_fixture_selftest(&cache,Some(&changed))?;assert_eq!(failed.outcome().unwrap_err(),"the live ui_action_key() no longer matches");assert!(host.run_native_ui_fixture_selftest(&cache,None)?.outcome().is_ok());Ok(())}).unwrap();
 }
 #[test]fn actual_native_ui_callback_preserves_producer_1450_and_next_same_host_recovers(){
  let cache=crate::test_scratch::dir("native-ui-fixture-io");let mut host=BuildHost::default();
  super::super::full_registry_check::with_full_registry_check_context(crate::request::BuildCommand::PrepareQuery,Some(120),||{let credit=host.source_arena_work().reserve(dq_analyze::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES)?;let budget=dq_analyze::captured_generator_budget::Budget::new(dq_analyze::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES).map_err(io::Error::other)?;let work=NativeSelftestWork::new(&credit,&budget)?;let mut scratch=NativeFixtureSources::new_using(&cache,&work)?;sources(&mut scratch)?;let build=request(&scratch,&cache)?;
   let failure=host.with_native_ui_fixture_request(build,&mut |_|Err(dq_analyze::captured_reactive_reads::Failure::Operational(io::Error::from_raw_os_error(1450)))).unwrap_err();assert_eq!(actual_io(failure).raw_os_error(),Some(1450));host.clear_regions();scratch.remove()?;
   assert!(host.run_native_ui_fixture_selftest(&cache,None)?.outcome().is_ok());Ok(())}).unwrap();
 }
}

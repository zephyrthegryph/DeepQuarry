//! Optional ordinary callback reads on the SAME parent recorder.
//! No source/model grant, ambient read, success cache, or second snapshot owner.
use super::*;
use dq_analyze::captured_generator_budget::Budget;
use std::sync::Arc;

pub(crate) struct NativeSelftestCandidates{dispatcher:Option<Vec<u8>>,ignore:Option<Vec<u8>>}
pub(crate) struct NativeSelftestInputs<'a>{dispatcher:Option<&'a str>,ignore:Option<&'a str>}
impl NativeSelftestInputs<'_>{pub(crate) fn dispatcher(&self)->Option<&str>{self.dispatcher}pub(crate) fn ignore(&self)->Option<&str>{self.ignore}}
impl NativeSelftestCandidates{
 fn borrowed(&self)->NativeSelftestInputs<'_>{NativeSelftestInputs{dispatcher:self.dispatcher.as_deref().and_then(|bytes|std::str::from_utf8(bytes).ok()),ignore:self.ignore.as_deref().and_then(|bytes|std::str::from_utf8(bytes).ok())}}
}
fn oom(message:impl Into<String>)->io::Error{io::Error::new(io::ErrorKind::OutOfMemory,message.into())}
impl<P:SnapshotProvider> RecordingInputs<P>{
 /// Resource-lent bounded directory plus exact physical UTF8 candidate bytes.
 /// Positive invalid-UTF8 remains a positive fact, even when the old optional
 /// read_to_string semantics proceed to the fallback/ignore no-text branch.
 fn read_native_callback_candidate(&self,path:&Path,budget:&Arc<Budget>,queries:&crate::query_db::QueryDb,lender:&mut dyn super::RecordedPolicySourceLender)->io::Result<Option<Vec<u8>>>{
  crate::daemon::control::checkpoint()?;if !path.is_absolute(){return Err(invalid("ordinary callback input must have its real absolute path"))}
  budget.charge(path.as_os_str().len().checked_mul(16).and_then(|n|n.checked_add(512)).ok_or_else(||oom("callback path metadata overflow"))?).map_err(oom)?;
  let path=canonical_path(path);
  // This is an exact optional path demand, not directory enumeration. Denied
  // parent traversal is an authentic OS NoText, never synthetic absence.
  let metadata=||self.snapshot.lock().map_err(|_|invalid("callback recorder poisoned"))?.policy_closure_charge();
  let before=metadata()?;let owner=self.policy_metadata_owner(Some(budget))?;lender.prepare_directory_metadata(&owner,before)?;
  let file_bound=path.capacity().checked_mul(4).and_then(|n|n.checked_add(256+std::mem::size_of::<FileInput>())).ok_or_else(||oom("callback metadata overflow"))?;
  let limit=dq_analyze::captured_raw_policy::MAX_FIXTURE_FILE_BYTES;let window=Budget::reserve_window(budget,limit.checked_add(file_bound).ok_or_else(||oom("callback window overflow"))?).map_err(oom)?;
  lender.directory_window_started(&owner,before.checked_add(file_bound).ok_or_else(||oom("callback recorder overflow"))?)?;
  let mut pending=None;
  let resource=lender.with_held_source_work(queries,&mut|work|{pending=Some(self.read_optional_callback_payload(&path,limit,work,&mut|size|{
   crate::daemon::control::checkpoint()?;if size.checked_add(file_bound).is_none_or(|n|n>window.capacity()){return Err(oom("callback payload exceeds actual resource window"))}Ok(())
  }));if pending.as_ref().is_some_and(Result::is_err){Err(io::ErrorKind::Other.into())}else{Ok(())}});
  let pending=match pending{Some(Err(first))=>Err(first),Some(Ok(actual))=>resource.map(|()|actual),None=>match resource{Err(first)=>Err(first),Ok(())=>Err(invalid("optional callback resource loan was not visited"))}};
  let after=match metadata(){Ok(n)=>n,Err(later)=>{window.keep();return match pending{Err(first)=>Err(first),Ok(_)=>Err(later)}}};
  if let Err(later)=lender.directory_metadata_settled(&owner,after){window.keep();return match pending{Err(first)=>Err(first),Ok(_)=>Err(later)}}
  // Read-observation spine grants are already funded by SAME held work. This
  // window retains actual payload and ordinary FileInput/map metadata only.
  let retained=after.saturating_sub(before).checked_add(pending.as_ref().ok().and_then(|v|v.as_ref()).map_or(0,Vec::capacity)).ok_or_else(||oom("callback retained capacity overflow"))?;
  let settled=window.settle(retained).map_err(oom);match pending{Err(first)=>Err(first),Ok(actual)=>{settled?;Ok(actual)}}
 }
 pub(crate) fn capture_native_selftest_candidates(&self,plan:&crate::runner_host::NativeCheckSelection,caller:Option<&Path>,workspace_root:&Path,budget:&Arc<Budget>,queries:&crate::query_db::QueryDb,lender:&mut dyn super::RecordedPolicySourceLender)->io::Result<NativeSelftestCandidates>{
  let ui=plan.names().iter().any(|name|name=="ui_actions");let grep=plan.names().iter().any(|name|name=="check_grep");
  if (ui||grep)!=caller.is_some(){return Err(invalid("ordinary callback caller directory differs from the exact selected live-input demand"))}
  let mut dispatcher=None;let mut ignore=None;
  let path_width=caller.map_or(0,|path|path.as_os_str().len()).checked_add(workspace_root.as_os_str().len()).and_then(|n|n.checked_add(dq_analyze::ui_actions_policy::DISPATCHER.len())).and_then(|n|n.checked_mul(64)).and_then(|n|n.checked_add(4096)).ok_or_else(||oom("callback namespace path overlap overflow"))?;budget.charge(path_width).map_err(oom)?;
  if !workspace_root.is_absolute(){return Err(invalid("ordinary callbacks require the actual admitted workspace namespace"))}

  if let Some(caller)=caller{
   if !caller.is_absolute(){return Err(invalid("ordinary callback caller directory must be absolute"))}
   if ui{
    let path=caller.join(dq_analyze::ui_actions_policy::DISPATCHER);dispatcher=self.read_native_callback_candidate(&path,budget,queries,lender)?;
    if dispatcher.as_deref().and_then(|bytes|std::str::from_utf8(bytes).ok()).is_none(){
     let path=dq_analyze::ui_selftest_policy::live_dispatcher_fallback();dispatcher=self.read_native_callback_candidate(&path,budget,queries,lender)?;
    }
   }
   if grep{let path=caller.join(".gitignore");ignore=self.read_native_callback_candidate(&path,budget,queries,lender)?;}
  }
  Ok(NativeSelftestCandidates{dispatcher,ignore})
 }
 /// A callback observes borrowed bytes, while both barriers inspect the SAME
 /// actual ledger in place. The post token binds the eventual single transfer;
 /// its epoch is never reused after the normal preparation adds more facts.
 pub(crate) fn with_native_selftest_inputs<T>(&self,actual:&NativeSelftestCandidates,visit:impl FnOnce(NativeSelftestInputs<'_>)->Result<T,Box<dyn std::error::Error>>)->Result<(T,Option<JoinedReportEpoch>),Box<dyn std::error::Error>>{
  let require=crate::request_runner::runner_freshness::require_native_callback_inputs_current;
  let has_facts=self.snapshot.lock().map_err(|_|invalid("callback input mutex poisoned"))?.epoch()!=0;
  if has_facts{let _=self.with_joined_report_snapshot(require)?;}
  let result=visit(actual.borrowed())?;
  let epoch=if has_facts{Some(self.with_joined_report_snapshot(require)?.1)}else{None};
  crate::daemon::control::checkpoint()?;Ok((result,epoch))
 }
}

impl JoinedReportEpoch{
 /// Issuer association only. The final actual capture still issues/validates
 /// its OWN exact epoch when the parent recorder moves; this grants no replay.
 pub(crate) fn same_recorder(&self,other:&Self)->bool{Arc::ptr_eq(&self.issuer,&other.issuer)}
}

#[cfg(test)]mod controls{
 use super::*;use dm_preprocess::source_arena_credit::SourceArenaWork;
 fn plan(db:&crate::query_db::QueryDb)->Arc<crate::runner_host::NativeCheckSelection>{crate::runner_host::prepare_native_registered_check_selection(&["check_grep".into()],crate::runner_host::FullRegistryCheckOptions::default(),db).unwrap()}
 fn context()->crate::daemon::control::Binding{crate::daemon::control::bind_with_deadline(crate::daemon::control::Cancellation::default(),std::time::Instant::now()+std::time::Duration::from_secs(60))}
 #[test]fn actual_callback_negative_to_positive_refuses_then_genuine_single_recorder_move_recovers(){
  let _context=context();let root=std::fs::canonicalize(crate::test_scratch::dir("selftest-caller-negative")).unwrap();let db=crate::query_db::QueryDb::default();let _credit=db.reserve(dq_analyze::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES).unwrap();let plan=plan(&db);
  let budget=Budget::new(dq_analyze::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES).unwrap();let inputs=RecordingInputs::new(FileSystemInputs,1);
  let actual=db.with_native_selftest_input_resources(&budget,|lender|inputs.capture_native_selftest_candidates(&plan,Some(&root),&root,&budget,&db,lender)).unwrap();
  let failed=inputs.with_native_selftest_inputs(&actual,|loan|{assert!(loan.ignore().is_none());std::fs::write(root.join(".gitignore"),b"/code/a.dm\n")?;Ok(())}).err().unwrap();assert_eq!(failed.downcast_ref::<io::Error>().unwrap().kind(),io::ErrorKind::Interrupted);drop(actual);drop(inputs);drop(budget);
  let budget=Budget::new(dq_analyze::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES).unwrap();let inputs=RecordingInputs::new(FileSystemInputs,2);let actual=db.with_native_selftest_input_resources(&budget,|lender|inputs.capture_native_selftest_candidates(&plan,Some(&root),&root,&budget,&db,lender)).unwrap();let(_,early)=inputs.with_native_selftest_inputs(&actual,|loan|{assert_eq!(loan.ignore(),Some("/code/a.dm\n"));Ok(())}).unwrap();drop(actual);
  let(_,final_epoch)=inputs.with_joined_report_snapshot(|_|Ok(())).unwrap();assert!(early.unwrap().same_recorder(&final_epoch));let moved=inputs.into_joined_report_snapshot(&final_epoch).unwrap();assert!(moved.exact_positive_contents_match(&FileSystemInputs).unwrap());assert!(moved.restat(&FileSystemInputs).unwrap().unchanged());
 }
 #[test]fn actual_callback_1450_survives_cancellation_before_any_outer_diagnostic_reset(){
  let token=crate::daemon::control::Cancellation::default();let binding=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(60));let root=std::fs::canonicalize(crate::test_scratch::dir("selftest-caller-first-io")).unwrap();std::fs::write(root.join(".gitignore"),b"").unwrap();let db=crate::query_db::QueryDb::default();let _credit=db.reserve(dq_analyze::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES).unwrap();let plan=plan(&db);let budget=Budget::new(dq_analyze::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES).unwrap();let inputs=RecordingInputs::new(FileSystemInputs,1);let actual=db.with_native_selftest_input_resources(&budget,|lender|inputs.capture_native_selftest_candidates(&plan,Some(&root),&root,&budget,&db,lender)).unwrap();
  let failed=inputs.with_native_selftest_inputs(&actual,|_|{token.cancel();Err::<(),_>(io::Error::from_raw_os_error(1450).into())}).err().unwrap();assert_eq!(failed.downcast_ref::<io::Error>().unwrap().raw_os_error(),Some(1450));drop(actual);drop(inputs);drop(budget);drop(binding);
  let _context=context();let budget=Budget::new(dq_analyze::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES).unwrap();let inputs=RecordingInputs::new(FileSystemInputs,2);let actual=db.with_native_selftest_input_resources(&budget,|lender|inputs.capture_native_selftest_candidates(&plan,Some(&root),&root,&budget,&db,lender)).unwrap();inputs.with_native_selftest_inputs(&actual,|_|Ok(())).unwrap();
 }
 #[test]fn actual_callback_quota_refuses_before_fixture_visit_and_refunds_for_a_fresh_attempt(){
  let _context=context();let root=std::fs::canonicalize(crate::test_scratch::dir("selftest-caller-quota")).unwrap();std::fs::write(root.join(".gitignore"),b"# actual caller file\n").unwrap();let db=crate::query_db::QueryDb::default();let _credit=db.reserve(dq_analyze::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES).unwrap();let plan=plan(&db);let inputs=RecordingInputs::new(FileSystemInputs,1);let budget=Budget::new(256).unwrap();let failed=db.with_native_selftest_input_resources(&budget,|lender|inputs.capture_native_selftest_candidates(&plan,Some(&root),&root,&budget,&db,lender)).err().unwrap();assert_eq!(failed.kind(),io::ErrorKind::OutOfMemory);drop(inputs);drop(budget);
  let inputs=RecordingInputs::new(FileSystemInputs,2);let budget=Budget::new(dq_analyze::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES).unwrap();let actual=db.with_native_selftest_input_resources(&budget,|lender|inputs.capture_native_selftest_candidates(&plan,Some(&root),&root,&budget,&db,lender)).unwrap();inputs.with_native_selftest_inputs(&actual,|loan|{assert_eq!(loan.ignore(),Some("# actual caller file\n"));Ok(())}).unwrap();
 }
 #[test]fn actual_optional_reader_no_text_reobserves_denied_or_read_failed_path_then_rejects_becoming_readable(){
  let _context=context();let root=std::fs::canonicalize(crate::test_scratch::dir("selftest-optional-denied")).unwrap();let path=root.join(".gitignore");
  #[cfg(windows)]let held={use std::os::windows::fs::OpenOptionsExt;std::fs::write(&path,b"# actual readable after close\n").unwrap();std::fs::File::options().read(true).share_mode(0).open(&path).unwrap()};
  #[cfg(not(windows))]std::fs::create_dir(&path).unwrap();
  let db=crate::query_db::QueryDb::default();let _credit=db.reserve(dq_analyze::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES).unwrap();let plan=plan(&db);let budget=Budget::new(dq_analyze::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES).unwrap();let inputs=RecordingInputs::new(FileSystemInputs,1);
  let actual=db.with_native_selftest_input_resources(&budget,|lender|inputs.capture_native_selftest_candidates(&plan,Some(&root),&root,&budget,&db,lender)).unwrap();
  let changed=inputs.with_native_selftest_inputs(&actual,|loan|{assert!(loan.ignore().is_none());
   #[cfg(windows)]drop(held);
   #[cfg(not(windows))]{std::fs::remove_dir(&path)?;std::fs::write(&path,b"# actual readable after directory\n")?;}
   Ok(())}).err().unwrap();assert_eq!(changed.downcast_ref::<io::Error>().unwrap().kind(),io::ErrorKind::Interrupted);drop((actual,inputs,budget));
  let budget=Budget::new(dq_analyze::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES).unwrap();let inputs=RecordingInputs::new(FileSystemInputs,2);let actual=db.with_native_selftest_input_resources(&budget,|lender|inputs.capture_native_selftest_candidates(&plan,Some(&root),&root,&budget,&db,lender)).unwrap();inputs.with_native_selftest_inputs(&actual,|loan|{assert!(loan.ignore().unwrap().starts_with("# actual readable"));Ok(())}).unwrap();
 }
 #[test]fn actual_optional_reader_admission_1450_remains_framework_error_even_with_later_cancel(){
  let root=std::fs::canonicalize(crate::test_scratch::dir("selftest-optional-admission-io")).unwrap();let path=root.join("actual.txt");std::fs::write(&path,b"actual source bytes").unwrap();let db=crate::query_db::QueryDb::default();let _credit=db.reserve(1<<20).unwrap();let budget=Budget::new(1<<20).unwrap();let inputs=RecordingInputs::new(FileSystemInputs,1);
  let token=crate::daemon::control::Cancellation::default();let binding=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(60));
  let actual=inputs.read_optional_callback_payload(&path,1024,&db,&mut |_|{token.cancel();Err(io::Error::from_raw_os_error(1450))}).err().unwrap();assert_eq!(actual.raw_os_error(),Some(1450));drop(binding);
  let _context=context();let actual=inputs.read_optional_callback_payload(&path,1024,&db,&mut |_|Ok(())).unwrap().unwrap();assert_eq!(actual,b"actual source bytes");drop(budget);
 }
 #[test]fn actual_optional_observation_never_grants_original_payload_and_old_readable_encoding_is_unchanged(){
  let original=OriginalReadOpenStatus::Readable;assert_eq!(serde_json::to_string(&original).unwrap(),"\"Readable\"");let mut input=InputSnapshot::new(1);let path=PathBuf::from(if cfg!(windows){"E:/actual-optional-only.dm"}else{"/actual-optional-only.dm"});input.optional_reads=OptionalReadFacts::from_observed_data([(path.as_path(),OptionalReadStatus::Readable)]).unwrap();assert!(input.opened_reads.is_empty());assert!(input.original_payloads.is_empty());assert!(input.check_structure().is_err(),"a decoded readable flag without actual payload cannot close the optional input set");
 }
 #[cfg(windows)]#[test]fn actual_optional_ui_primary_denial_uses_actual_captured_fallback_without_fake_absence(){
  use std::os::windows::fs::OpenOptionsExt;let _context=context();let root=std::fs::canonicalize(crate::test_scratch::dir("selftest-optional-ui-fallback")).unwrap();let path=root.join(dq_analyze::ui_actions_policy::DISPATCHER);std::fs::create_dir_all(path.parent().unwrap()).unwrap();std::fs::write(&path,b"unreadable primary").unwrap();let held=std::fs::File::options().read(true).share_mode(0).open(&path).unwrap();
  let db=crate::query_db::QueryDb::default();let _credit=db.reserve(dq_analyze::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES).unwrap();let plan=crate::runner_host::prepare_native_registered_check_selection(&["ui_actions".into()],crate::runner_host::FullRegistryCheckOptions::default(),&db).unwrap();let budget=Budget::new(dq_analyze::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES).unwrap();let inputs=RecordingInputs::new(FileSystemInputs,1);let actual=db.with_native_selftest_input_resources(&budget,|lender|inputs.capture_native_selftest_candidates(&plan,Some(&root),&root,&budget,&db,lender)).unwrap();
  let expected=std::fs::read_to_string(dq_analyze::ui_selftest_policy::live_dispatcher_fallback()).unwrap();inputs.with_native_selftest_inputs(&actual,|loan|{assert_eq!(loan.dispatcher(),Some(expected.as_str()));Ok(())}).unwrap();let snapshot=inputs.snapshot().unwrap();assert!(!snapshot.negative_files.contains(&canonical_path(&path)));drop(held);
 }
 #[test]fn actual_same_recorder_optional_and_original_ui_reads_coexist_in_both_orders_and_keep_independent_currentness(){
  use dm_preprocess::{OriginalRawOpenDecision as Decision,OriginalRawReadOutcome as Outcome,InitialEnvironment};
  for optional_first in[true,false]{
   let _context=context();let root=std::fs::canonicalize(crate::test_scratch::dir("selftest-optional-original-coexist")).unwrap();let path=root.join(dq_analyze::ui_actions_policy::DISPATCHER);std::fs::create_dir_all(path.parent().unwrap()).unwrap();std::fs::write(&path,b"/datum/native_callback_shared\n").unwrap();let db=crate::query_db::QueryDb::default();let _credit=db.reserve(dq_analyze::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES).unwrap();let budget=Budget::new(dq_analyze::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES).unwrap();let plan=crate::runner_host::prepare_native_registered_check_selection(&["ui_actions".into()],crate::runner_host::FullRegistryCheckOptions::default(),&db).unwrap();let inputs=RecordingInputs::new(FileSystemInputs,1).with_initial_environment(InitialEnvironment::OriginalChecker0290);
   let original=||{let out=dm_preprocess::source_arena_credit::read_original_source_open_using(&inputs,&path,1024,&db,&mut||Ok(Decision::Read)).unwrap();assert!(matches!(out,Outcome::Acquired(_)));};
   if !optional_first{original();}
   let actual=db.with_native_selftest_input_resources(&budget,|lender|inputs.capture_native_selftest_candidates(&plan,Some(&root),&root,&budget,&db,lender)).unwrap();
   if optional_first{original();}
   let snapshot=inputs.snapshot().unwrap();assert!(snapshot.opened_reads.get(&path).unwrap().is_readable());assert_eq!(snapshot.optional_reads.get(&path),Some(OptionalReadStatus::Readable));assert!(snapshot.original_payloads.get(&path).is_some());assert!(snapshot.recorded_canonical_file(&path).is_some());assert!(snapshot.restat(&FileSystemInputs).unwrap().unchanged());assert!(snapshot.exact_positive_contents_match(&FileSystemInputs).unwrap());
   let json=serde_json::to_vec(&snapshot).unwrap();let decoded:InputSnapshot=serde_json::from_slice(&json).unwrap();assert!(snapshot.same_recorded_facts(&decoded));let binary=dm_wire::encode(0x5350_0002,&snapshot).unwrap();let decoded:InputSnapshot=dm_wire::decode(0x5350_0002,&binary,dm_wire::MAX_BYTES).unwrap();assert!(snapshot.same_recorded_facts(&decoded));assert!(decoded.restat(&FileSystemInputs).unwrap().unchanged());drop(snapshot);
   let stamp=std::fs::metadata(&path).unwrap().modified().unwrap();let before=std::fs::read(&path).unwrap();let changed=String::from_utf8(before.clone()).unwrap().replace("shared","mutate");assert_eq!(before.len(),changed.len());
   let error=inputs.with_native_selftest_inputs(&actual,|loan|{assert!(loan.dispatcher().unwrap().contains("shared"));std::fs::write(&path,changed.as_bytes())?;std::fs::File::options().write(true).open(&path)?.set_times(std::fs::FileTimes::new().set_modified(stamp))?;Ok(())}).err().unwrap();assert_eq!(error.downcast_ref::<io::Error>().unwrap().kind(),io::ErrorKind::Interrupted);
   let conflict=dm_preprocess::source_arena_credit::read_original_source_open_using(&inputs,&path,1024,&db,&mut||Ok(Decision::Read));assert!(conflict.is_err(),"same recorder may not replace old Original payload after a later optional/body change");
  }
 }
 #[cfg(windows)]#[test]fn actual_optional_and_original_denied_ui_reads_keep_both_failure_roles_and_never_mint_original_payload(){
  use std::os::windows::fs::OpenOptionsExt;use dm_preprocess::{InitialEnvironment,OriginalRawOpenDecision as Decision,OriginalRawReadOutcome as Outcome};let _context=context();let root=std::fs::canonicalize(crate::test_scratch::dir("selftest-optional-original-denied")).unwrap();let path=root.join("shared.dm");std::fs::write(&path,b"/datum/shared\n").unwrap();let held=std::fs::File::options().read(true).share_mode(0).open(&path).unwrap();let db=crate::query_db::QueryDb::default();let inputs=RecordingInputs::new(FileSystemInputs,1).with_initial_environment(InitialEnvironment::OriginalChecker0290);
  let optional=inputs.read_optional_callback_payload(&path,1024,&db,&mut |_|panic!("denied actual OS open cannot ask for payload allocation")).unwrap();assert!(optional.is_none());let out=dm_preprocess::source_arena_credit::read_original_source_open_using(&inputs,&path,1024,&db,&mut||Ok(Decision::Read)).unwrap();assert!(matches!(out,Outcome::SourceOpenFailed(_)));let snapshot=inputs.snapshot().unwrap();assert!(!snapshot.opened_reads.get(&path).unwrap().is_readable());assert!(matches!(snapshot.optional_reads.get(&path),Some(OptionalReadStatus::NoText{phase:OptionalReadPhase::Open,raw:32|33})));assert!(snapshot.original_payloads.is_empty());assert!(snapshot.restat(&FileSystemInputs).unwrap().unchanged());drop(held);assert!(!snapshot.restat(&FileSystemInputs).unwrap().unchanged());
 }
}

impl<P:SnapshotProvider> RecordingInputs<P>{
 /// Preserve actual standalone startup configuration errors through the SAME
 /// optional read spine and existing native Config interpretation. No selected
 /// outer Tree/model/header preparation is performed for this validation.
 pub(crate) fn validate_standalone_selftest_configuration(&self,root:&Path,queries:&crate::query_db::QueryDb,budget:&Arc<Budget>,lender:&mut dyn super::RecordedPolicySourceLender)->io::Result<()>{
  crate::daemon::control::checkpoint()?;
  budget.charge(root.as_os_str().len().checked_mul(16).and_then(|n|n.checked_add(1024)).ok_or_else(||oom("standalone configuration path overflow"))?).map_err(oom)?;
  let path=root.join("tools/ci/lint_scopes.toml");
  let bytes=self.read_native_callback_candidate(&path,budget,queries,lender)?;
  // Exactly the existing native configuration parse peak admission used by
  // read_derived_configuration; this temporary dies before callbacks start.
  let peak=bytes.as_ref().map_or(0,Vec::len).checked_mul(64).and_then(|n|n.checked_add(8192)).ok_or_else(||oom("standalone configuration parse overflow"))?;
  lender.with_held_source_work(queries,&mut|work|{
   // This is a real same-ledger grant, not only a local Budget estimate. Its
   // synchronous owner covers the existing Config parser's admitted peak.
   let credit=work.reserve(peak)?;
   let config=dq_analyze::captured_raw_file::Config::capture(bytes.as_ref().map_or(dq_analyze::captured_raw_policy::Configuration::ProvenMissing,|bytes|dq_analyze::captured_raw_policy::Configuration::Captured(bytes.as_slice()))).map_err(io::Error::other)?;
   drop(config);drop(credit);Ok(())
  })?;
  drop(bytes);crate::daemon::control::checkpoint()
 }
}

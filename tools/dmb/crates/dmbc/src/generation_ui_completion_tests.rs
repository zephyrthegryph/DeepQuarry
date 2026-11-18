//! Actual UiTypes producer completion without a fabricated generated-file row.
use super::*;
fn source(entries:&str)->String{
 let define=include_str!("../../../../../code/defines/engine/declare/markers.dm").lines().find(|line|line.starts_with("#define CAPABILITIES(T)")).unwrap();
 format!("{define}\n{entries}")
}
fn fixture(entries:&str)->(BuildHost,BuildRequest,PathBuf,PathBuf){
 let(host,mut request,cache,root)=crate::generation_test_fixture::fixture();request.engine_template=None;request.bootstrap_catalog=false;request.policy_inputs.as_mut().unwrap().analysis_context=Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290);request.policy_inputs.as_mut().unwrap().workspace_generators=vec![GeneratorName::UiTypes];
 std::fs::write(root.join("deepquarry.dme"),"#include \"code/probe.dm\"\n").unwrap();std::fs::write(root.join("code/probe.dm"),source(entries)).unwrap();(host,request,cache,root)
}
const EMPTY_WINDOW:&str="/datum/ui_empty\nCAPABILITIES(/datum/ui_empty)\n    interface(\"Empty\")\n";
// Mirror the coordinator's real full-stage fallback: an all-present source-only
// probe returns NotNeeded, so it cannot be treated as a closed journal.
fn actual_closed_ui_phase(host:&mut BuildHost,request:&BuildRequest,cache:&std::path::Path)->crate::runner_host::query_snapshot::ClosedGeneration{
 prepare(host,request,&[GeneratorName::UiTypes]).unwrap();
 let snapshot={let state=host.query_state();let mut state=state.lock().unwrap_or_else(|error|error.into_inner());state.snapshot.take().expect("actual complete UI source frame")};
 snapshot.stage_generation(crate::generation_staging::temporary_output(cache).unwrap()).unwrap()
}
#[test]fn actual_ui_diagnostic_only_check_and_write_complete_without_output_or_fresh_row(){
 let(mut host,request,cache,root)=fixture(EMPTY_WINDOW);let initial=std::fs::read(root.join("code/probe.dm")).unwrap();
 for mode in [Mode::Check,Mode::Write]{let report=run(&mut host,&request,&[GeneratorName::UiTypes],mode,&cache).unwrap();assert!(report.rows.is_empty(),"no real UI target was produced");assert_eq!(report.diagnostics.len(),1);let diagnostic=&report.diagnostics[0];assert_eq!(diagnostic.name,GeneratorName::UiTypes);assert_eq!(diagnostic.relative,"code/probe.dm");assert!(diagnostic.message.contains("nothing to type"));assert!(!report.committed);assert!(report.changed.is_empty());assert!(report.cleanup.is_empty());assert_eq!(std::fs::read(root.join("code/probe.dm")).unwrap(),initial);assert!(!root.join("tgui/packages/tgui/interfaces/generated").exists());let state=host.query_state();let state=state.lock().unwrap();let snapshot=state.snapshot.as_ref().expect("final genuine native preparation remains retained");snapshot.workspace_native_read().unwrap();snapshot.workspace_generator_inputs(GeneratorName::UiTypes).unwrap();}
}
#[test]fn actual_ui_empty_without_diagnostics_and_no_selected_generator_still_refuse(){
 let(mut host,request,cache,root)=fixture("/datum/ui_empty\n");let initial=std::fs::read(root.join("code/probe.dm")).unwrap();let error=run(&mut host,&request,&[GeneratorName::UiTypes],Mode::Check,&cache).unwrap_err();assert!(error.to_string().contains("no generator named"));let failure=error.downcast_ref::<CoordinatorFailure>().unwrap();assert!(!failure.committed);let error=run(&mut host,&request,&[],Mode::Check,&cache).unwrap_err();assert_eq!(error.downcast_ref::<io::Error>().unwrap().kind(),io::ErrorKind::InvalidInput);assert_eq!(std::fs::read(root.join("code/probe.dm")).unwrap(),initial);assert!(!root.join("tgui/packages/tgui/interfaces/generated").exists());
}
#[test]fn actual_ui_no_output_then_mixed_files_reuses_host_and_preserves_actual_row_order(){
 let(mut host,request,cache,root)=fixture(EMPTY_WINDOW);let first=run(&mut host,&request,&[GeneratorName::UiTypes],Mode::Check,&cache).unwrap();assert!(first.rows.is_empty());assert_eq!(first.diagnostics.len(),1);
 let mixed=format!("{EMPTY_WINDOW}/datum/ui_z\nCAPABILITIES(/datum/ui_z)\n    interface(\"Zed\")\n    ui_shape(count = num())\n/datum/ui_a\nCAPABILITIES(/datum/ui_a)\n    interface(\"Alpha\")\n    ui_shape(count = num())\n");std::fs::write(root.join("code/probe.dm"),source(&mixed)).unwrap();let report=run(&mut host,&request,&[GeneratorName::UiTypes],Mode::Check,&cache).unwrap();assert_eq!(report.rows.len(),2);assert_eq!(report.diagnostics.len(),1);assert!(report.diagnostics[0].message.contains("nothing to type"));assert!(report.rows.iter().all(|row|row.name==GeneratorName::UiTypes&&row.state==State::Stale));assert_eq!(report.rows[0].path,root.join("tgui/packages/tgui/interfaces/generated/Alpha.d.ts"));assert_eq!(report.rows[1].path,root.join("tgui/packages/tgui/interfaces/generated/Zed.d.ts"));assert!(!report.committed);assert!(report.changed.is_empty());assert!(!root.join("tgui/packages/tgui/interfaces/generated").exists());
}
#[test]fn actual_ui_diagnostic_only_closed_phase_checks_source_after_hook_and_preserves_first_io(){
 let(mut host,request,cache,root)=fixture(EMPTY_WINDOW);let names=[GeneratorName::UiTypes];let closed=actual_closed_ui_phase(&mut host,&request,&cache);let original=std::fs::read(root.join("code/probe.dm")).unwrap();let error=transaction::commit_using(closed,&cache,Mode::Check,&mut|event|{if matches!(event,transaction::Event::BeforeFinalFreshness){return Err(io::Error::from_raw_os_error(1450))}Ok(())}).unwrap_err();assert_eq!(error.primary.downcast_ref::<io::Error>().unwrap().raw_os_error(),Some(1450));assert_eq!(std::fs::read(root.join("code/probe.dm")).unwrap(),original);assert!(!root.join("tgui/packages/tgui/interfaces/generated").exists());
 let closed=actual_closed_ui_phase(&mut host,&request,&cache);let error=transaction::commit_using(closed,&cache,Mode::Check,&mut|event|{if matches!(event,transaction::Event::BeforeFinalFreshness){std::fs::write(root.join("code/probe.dm"),source("/datum/changed_after_ui_capture\n"))?;}Ok(())}).unwrap_err();assert!(!error.to_string().is_empty());assert!(!root.join("tgui/packages/tgui/interfaces/generated").exists());std::fs::write(root.join("code/probe.dm"),original).unwrap();let recovered=run(&mut host,&request,&names,Mode::Check,&cache).unwrap();assert!(recovered.rows.is_empty());assert_eq!(recovered.diagnostics.len(),1);
}

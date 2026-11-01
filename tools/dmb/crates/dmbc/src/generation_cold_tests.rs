//! Actual resident-host bootstrap/fixed-point controls. Generated output starts
//! absent; the same BuildHost then owns the final unchanged full frame.
use super::*;
use std::sync::Arc;
fn all_names()->Vec<GeneratorName>{vec![GeneratorName::Actions,GeneratorName::AutoTracked,GeneratorName::Declare,GeneratorName::DeclareIds,GeneratorName::Deps,GeneratorName::DerivedReads,GeneratorName::Plans,GeneratorName::Reads,GeneratorName::SparseSlots,GeneratorName::Stats,GeneratorName::SystemAccessors,GeneratorName::TrackedLists,GeneratorName::UiTypes]}
fn cold_fixture()->(BuildHost,BuildRequest,PathBuf,PathBuf){
 let(host,mut request,cache,root)=crate::generation_test_fixture::fixture();
 std::fs::remove_file(root.join(GeneratorName::Deps.path())).unwrap();
 std::fs::remove_dir(root.join("code/engine/_generated")).unwrap();
 std::fs::create_dir_all(root.join("code/tests")).unwrap();
 // Use real reactive readers/writes, not an empty provider or a declaration-only
 // test standing in for Auto's actual body/read role.
 for(relative,text)in [("deepquarry.dme",include_str!("../../../../analyze/fixtures/native-cold-generation/basic/deepquarry.dme")),("code/probe.dm",include_str!("../../../../analyze/fixtures/native-cold-generation/basic/code/probe.dm")),("code/tests/only.dm",include_str!("../../../../analyze/fixtures/native-cold-generation/basic/code/tests/only.dm"))]{std::fs::write(root.join(relative),text).unwrap();}
 request.policy_inputs.as_mut().unwrap().workspace.as_mut().unwrap().recursive_roots=vec![root.join("code")];
 // Unlike the Deps-only fixture, all13 explicitly requests Auto's fixed
 // configuration observation. Absence is recorded by the real reader.
 request.policy_inputs.as_mut().unwrap().workspace.as_mut().unwrap().configuration=root.join("tools/ci/lint_scopes.toml");
 (host,request,cache,root)
}
#[test]
fn actual_cold_generation_check_refuses_postwrite_context_and_does_not_create_generated_directories(){
 let(mut host,request,cache,root)=cold_fixture();
 assert!(!root.join("code/engine/_generated").exists());
 let error=run(&mut host,&request,&all_names(),Mode::Check,&cache).err().expect("a check cannot invent installed source-seven declarations");
 assert!(!error.to_string().is_empty());assert!(!root.join("code/engine/_generated").exists());
 assert!(host.query_tree().is_none(),"no ordinary complete frame is synthesized from missing outputs");
}
#[test]
fn actual_cold_generation_source_seven_questions_all_thirteen_write_then_warm_share_final_full_frame(){
 let(mut host,request,cache,root)=cold_fixture();let names=all_names();
 let report=run(&mut host,&request,&names,Mode::Write,&cache).unwrap();
 assert!(report.committed);assert!(report.cleanup.is_empty());
 let expected:BTreeSet<_>=crate::query_db::QueryDb::generation_dm_outputs().map(|path|root.join(path)).collect();assert_eq!(report.changed,expected.into_iter().collect::<Vec<_>>(),"every actual source-seven and later phase write appears exactly once in deterministic order");
 for path in crate::query_db::QueryDb::generation_dm_outputs(){assert!(root.join(path).is_file(),"{path}");}
 assert!(std::fs::read_to_string(root.join(GeneratorName::AutoTracked.path())).unwrap().contains("TRACKED(/datum/probe, charge)"));
 let tree=Arc::clone(host.query_tree().expect("final unchanged ordinary frame on same host"));
 {let state=host.query_state();let state=state.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();let inputs=snapshot.workspace_generator_inputs(GeneratorName::AutoTracked).unwrap();let archive=inputs.policy().archive();assert!(archive.uses_body_queries(host.query_db().as_ref()),"generator bodies use the SAME resident native QueryDb");assert!(!archive.syntax_inputs().expect("actual native body input issuance").is_empty());}
 let computed=host.query_db().db().stats(dm_query::Kind(4)).computed;
 let warm=run(&mut host,&request,&names,Mode::Write,&cache).unwrap();
 assert!(!warm.committed);assert!(warm.changed.is_empty());assert!(warm.rows.iter().all(|row|row.state==State::Fresh));
 assert!(Arc::ptr_eq(&tree,host.query_tree().unwrap()));
 assert_eq!(host.query_db().db().stats(dm_query::Kind(4)).computed,computed,"warm final-frame reuse performs no new body computation");
 for name in &names{let files:Vec<_>=report.rows.iter().filter(|row|row.name==*name).map(|row|{let relative=row.path.strip_prefix(&root).unwrap().to_string_lossy().replace('\\',"/");(relative,std::fs::read_to_string(&row.path).unwrap())}).collect();let diagnostics:Vec<_>=report.diagnostics.iter().filter(|row|row.name==*name).map(|row|(&row.relative,row.line,&row.message)).collect();println!("NATIVE_COLD_GENERATION_FULL={}",serde_json::to_string(&serde_json::json!({"generator":name.name(),"files":files,"diagnostics":diagnostics})).unwrap());}
}
#[test]
fn actual_cold_generation_post_source_seven_io_failure_keeps_truthful_committed_outputs_then_recovers(){
 let(mut host,request,cache,root)=cold_fixture();
 let error=run_using(&mut host,&request,&all_names(),Mode::Write,&cache,&mut|_,_|Err(io::Error::from_raw_os_error(1450).into())).err().unwrap();
 let failure=error.downcast_ref::<CoordinatorFailure>().unwrap();assert!(failure.committed);assert_eq!(failure.primary.downcast_ref::<io::Error>().unwrap().raw_os_error(),Some(1450));
 assert!(root.join(GeneratorName::Declare.path()).is_file());assert!(!root.join(GeneratorName::AutoTracked.path()).exists());
 let report=run(&mut host,&request,&all_names(),Mode::Write,&cache).unwrap();assert!(report.cleanup.is_empty());
}
#[test]
fn actual_cold_generation_unsupported_record_replay_and_trace_refuse_before_any_output_mutation(){
 for mode in 0..3{let(mut host,mut request,cache,root)=cold_fixture();let path=cache.join("unsupported-control");match mode{0=>request.record_inputs=Some(path),1=>request.replay_inputs=Some(path),_=>request.trace_path=Some(path)}
 let error=run(&mut host,&request,&all_names(),Mode::Write,&cache).err().unwrap();assert!(error.to_string().contains("record/replay/trace"));assert!(!root.join("code/engine/_generated").exists());}
}

fn underlying_io<'a>(mut error:&'a(dyn Error+'static))->Option<&'a io::Error>{loop{if let Some(actual)=error.downcast_ref::<io::Error>(){return Some(actual)}error=error.source()?;}}
#[cfg(windows)]
#[test]
fn actual_cold_generation_physical_source_read_error_is_preserved_before_install_then_same_host_recovers(){
 let(mut host,request,cache,root)=cold_fixture();let source=root.join("code/probe.dm");
 std::fs::remove_file(&source).unwrap();std::fs::create_dir(&source).unwrap();
 let expected=crate::input_snapshot::SnapshotProvider::read_verified(&crate::input_snapshot::FileSystemInputs,&source).err().expect("actual Windows provider cannot read a directory as compiled source");
 let error=run(&mut host,&request,&all_names(),Mode::Write,&cache).err().unwrap();
 let actual=underlying_io(error.as_ref()).unwrap_or_else(||panic!("actual source IO remains in the typed cause chain; returned {error:?}; {error}"));assert_eq!(actual.kind(),expected.kind());assert_eq!(actual.raw_os_error(),expected.raw_os_error());assert!(!root.join("code/engine/_generated").exists());
 std::fs::remove_dir(&source).unwrap();std::fs::write(&source,include_str!("../../../../analyze/fixtures/native-cold-generation/basic/code/probe.dm")).unwrap();
 let report=run(&mut host,&request,&all_names(),Mode::Write,&cache).unwrap();assert!(report.cleanup.is_empty());assert!(root.join(GeneratorName::AutoTracked.path()).is_file());
}

#[test]
fn actual_cold_generation_does_not_write_unrequested_source_prerequisites_or_mint_postwrite_questions(){
 let(mut host,request,cache,root)=cold_fixture();let before=host.query_db().db().stats(dm_query::Kind(4)).computed;
 let error=run(&mut host,&request,&[GeneratorName::Deps],Mode::Write,&cache).err().expect("actual missing source-seven includes require a separately requested source phase");
 assert!(!error.to_string().is_empty());assert!(!root.join("code/engine/_generated").exists());assert_eq!(host.query_db().db().stats(dm_query::Kind(4)).computed,before,"prerequisite role refusal precedes dependent body queries");
}

#[test]
fn actual_cold_source_only_subset_refuses_unrequested_missing_include_closure_before_writing_any_output(){
 let(mut host,request,cache,root)=cold_fixture();let names:Vec<_>=all_names().into_iter().filter(|name|source_only(*name)).collect();
 let error=run(&mut host,&request,&names,Mode::Write,&cache).err().unwrap();assert!(error.to_string().contains("explicitly selected output"));assert!(!root.join("code/engine/_generated").exists());
 let failure=error.downcast_ref::<CoordinatorFailure>().unwrap();assert!(!failure.committed);assert!(failure.cleanup.is_empty());
}

#[test]
fn actual_warm_existing_phase_zero_write_is_in_final_changed_then_warm_report_is_empty(){
 let(mut host,request,cache,root)=cold_fixture();run(&mut host,&request,&all_names(),Mode::Write,&cache).unwrap();
 let path=root.join(GeneratorName::DeclareIds.path());std::fs::write(&path,"// deliberately stale existing phase-zero output\n").unwrap();
 let report=run(&mut host,&request,&[GeneratorName::DeclareIds],Mode::Write,&cache).unwrap();assert!(report.committed);assert_eq!(report.changed,vec![path.clone()]);assert_eq!(report.rows.len(),1);assert_eq!(report.rows[0].state,State::Written);
 let warm=run(&mut host,&request,&[GeneratorName::DeclareIds],Mode::Write,&cache).unwrap();assert!(!warm.committed);assert!(warm.changed.is_empty());assert_eq!(warm.rows[0].state,State::Fresh);
}
#[test]
fn actual_restricted_commit_retires_previous_published_snapshot_before_postcommit_failure_then_recovers(){
 let(mut host,request,cache,root)=crate::generation_test_fixture::fixture();run(&mut host,&request,&[GeneratorName::Deps],Mode::Write,&cache).unwrap();assert!(host.query_state().lock().unwrap().snapshot.is_some());
 let path=root.join(GeneratorName::Deps.path());std::fs::remove_file(&path).unwrap();
 let error=run_using(&mut host,&request,&[GeneratorName::Deps],Mode::Write,&cache,&mut|_,_|Err(io::Error::from_raw_os_error(1450).into())).err().unwrap();let failure=error.downcast_ref::<CoordinatorFailure>().unwrap();assert!(failure.committed);assert_eq!(underlying_io(failure.primary.as_ref()).unwrap().raw_os_error(),Some(1450));assert!(path.is_file());assert!(host.query_state().lock().unwrap().snapshot.is_none(),"no prior complete source publication survives a restricted write");
 run(&mut host,&request,&[GeneratorName::Deps],Mode::Write,&cache).unwrap();let state=host.query_state();let state=state.lock().unwrap();state.snapshot.as_ref().expect("only genuine ordinary reprepare republishes the final frame").workspace_native_read().unwrap();
}

#[test]
fn actual_notincluded_committed_write_still_appears_in_complete_changed_paths(){
 let(mut host,mut request,cache,root)=crate::generation_test_fixture::fixture();let alternate=root.join("main.dme");std::fs::rename(root.join("deepquarry.dme"),&alternate).unwrap();std::fs::write(root.join("deepquarry.dme"),"#include \"code/probe.dm\"\n").unwrap();request.project=alternate;let target=root.join(GeneratorName::Deps.path());std::fs::remove_file(&target).unwrap();
 let report=run(&mut host,&request,&[GeneratorName::Deps],Mode::Write,&cache).unwrap();assert!(report.committed);assert!(target.is_file());assert_eq!(report.rows[0].state,State::NotIncluded,"presentation flag does not erase a real write");assert_eq!(report.changed,vec![target]);
}

#[test]
fn actual_cold_generation_auto_wrong_configuration_refuses_before_source_seven_commit(){
 let(mut host,mut request,cache,root)=cold_fixture();request.policy_inputs.as_mut().unwrap().workspace.as_mut().unwrap().configuration=root.join("missing.toml");
 let before=std::fs::read(root.join("deepquarry.dme")).unwrap();let computed=host.query_db().db().stats(dm_query::Kind(4)).computed;
 let error=run(&mut host,&request,&all_names(),Mode::Write,&cache).err().expect("fixed Auto configuration intent must precede any source-only output mutation");
 assert!(error.to_string().contains("actual fixed lint_scopes configuration request"));assert!(!root.join("code/engine/_generated").exists());assert!(!root.join("code/_generated").exists());assert_eq!(std::fs::read(root.join("deepquarry.dme")).unwrap(),before);assert_eq!(host.query_db().db().stats(dm_query::Kind(4)).computed,computed);assert!(host.query_tree().is_none());
}

#[cfg(windows)]
#[test]
fn actual_cold_generation_regular_source_sharing_failure_preserves_typed_io_before_install_then_recovers(){
 use std::os::windows::fs::OpenOptionsExt;
 let(mut host,request,cache,root)=cold_fixture();let source=root.join("code/probe.dm");assert!(source.is_file());
 let locked=std::fs::OpenOptions::new().read(true).share_mode(0).open(&source).unwrap();
 let expected=crate::input_snapshot::SnapshotProvider::read_verified(&crate::input_snapshot::FileSystemInputs,&source).err().expect("real exclusive Windows share lock must refuse source acquisition");
 let error=run(&mut host,&request,&all_names(),Mode::Write,&cache).err().expect("locked actual regular source cannot become a generation input");
 let actual=underlying_io(error.as_ref()).unwrap_or_else(||panic!("actual sharing IO remains in the typed cause chain; returned {error:?}; {error}"));assert_eq!(actual.kind(),expected.kind());assert_eq!(actual.raw_os_error(),expected.raw_os_error());assert!(!root.join("code/engine/_generated").exists());assert!(!root.join("code/_generated").exists());assert!(host.query_tree().is_none());
 drop(locked);let report=run(&mut host,&request,&all_names(),Mode::Write,&cache).unwrap();assert!(report.cleanup.is_empty());assert!(root.join(GeneratorName::AutoTracked.path()).is_file());
}

#[test]
fn actual_raw_only_workspace_preparation_keeps_lazy_body_demand_without_generator_authority(){
 let(mut host,request,_,_)=crate::generation_test_fixture::fixture();
 assert!(request.policy_inputs.as_ref().unwrap().workspace_generators.is_empty());
 assert!(matches!(crate::request_runner::run_build_with_host(request,&mut host).unwrap(),BuildOutcome::QueryPrepared{..}));
 let state=host.query_state();let state=state.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();
 assert!(snapshot.workspace_generator_inputs(GeneratorName::AutoTracked).is_err(),"ordinary raw capture issues no generator subset");
 assert_eq!(host.query_db().db().stats(dm_query::Kind(4)).computed,0);
}

#[test]
fn actual_selection_only_generation_preserves_prepared_originals_and_body_inputs_for_complete_reissue(){
 let(mut host,request,cache,_root)=crate::generation_test_fixture::fixture();
 let names=[GeneratorName::Deps];
 prepare(&mut host,&request,&names).unwrap();
 let before={let state=host.query_state();let state=state.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();let inputs=snapshot.workspace_generator_inputs(GeneratorName::Deps).unwrap();inputs.policy().archive().syntax_inputs().unwrap().to_vec()};
 assert!(!before.is_empty(),"actual complete frontend issued body inputs");
 let owner=host.prepared_sources().unwrap();
 let count=|owner:&crate::input_snapshot::PreparedInputArtifacts|{let mut count=0;owner.visit_storage(|view|if matches!(view,dm_session::ArtifactStorageView::Entry{..}){count+=1});count};
 let retained=count(&owner);assert!(retained>0);
 assert!(matches!(crate::request_runner::generation_cold::stage(&mut host,&request,&names,&names,false,&cache).unwrap(),crate::request_runner::generation_cold::Preparation::NotNeeded));
 assert_eq!(count(&owner),retained,"selection-only missing-unused probes must not publish an empty prepared roster");
 prepare(&mut host,&request,&names).unwrap();
 let state=host.query_state();let state=state.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();let inputs=snapshot.workspace_generator_inputs(GeneratorName::Deps).unwrap();let after=inputs.policy().archive().syntax_inputs().unwrap();
 assert_eq!(before.len(),after.len());for(old,current)in before.iter().zip(after){assert!(Arc::ptr_eq(old,current),"same current acquisition/program proof must keep the original body input issuance");}
}

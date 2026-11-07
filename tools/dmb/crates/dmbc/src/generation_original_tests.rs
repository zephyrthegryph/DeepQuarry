//! Actual same-coordinator Original-purpose generation, never a compiler role.
use super::*;
use std::sync::Arc;
#[path="../../../fixtures/unified_original_generation/source.rs"]mod initial;
fn setup(case:&str)->(BuildHost,BuildRequest,PathBuf,PathBuf){
 let(host,mut request,cache,root)=super::cold_tests::cold_fixture();request.engine_template=None;request.bootstrap_catalog=false;request.policy_inputs.as_mut().unwrap().analysis_context=Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290);
 let probe=root.join("code/probe.dm");let text=initial::guarded_probe(&std::fs::read_to_string(&probe).unwrap());std::fs::write(probe,text).unwrap();
 let path=root.join("deepquarry.dme");let real=std::fs::read(&path).unwrap();if case!="real"{std::fs::create_dir_all(root.join("code/__defines")).unwrap();std::fs::write(root.join("code/__defines/original_generation.dm"),initial::synthetic_support(&real)).unwrap();}match initial::manifest(case,real){Some(bytes)=>std::fs::write(path,bytes).unwrap(),None=>std::fs::remove_file(path).unwrap()};(host,request,cache,root)
}
#[test]
fn actual_fixed_declare_overlay_check_leaves_absence_and_write_installs_only_verified_bytes() {
    let (mut host, mut request, cache, root) = crate::generation_test_fixture::fixture();
    request.engine_template = None;
    request.bootstrap_catalog = false;
    request.policy_inputs.as_mut().unwrap().analysis_context =
        Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290);
    let target = root.join(GeneratorName::Declare.path());
    std::fs::write(root.join("deepquarry.dme"), concat!(
        "#define CAPABILITIES(T) ##T/__capabilities()\n",
        "#include \"code/engine/overlay_forms.dm\"\n",
        "#include \"code/probe.dm\"\n",
        "#include \"code/engine/_generated/declare.dm\"\n",
    )).unwrap();
    std::fs::write(root.join("code/probe.dm"), concat!(
        "/datum/overlay_base\n    var/datum/target\n",
        "/datum/overlay_child\n    parent_type = /datum/overlay_base\n",
        "CAPABILITIES(/datum/overlay_child)\n    ref_one(nameof(target))\n",
    )).unwrap();

    std::fs::write(root.join("code/engine/overlay_forms.dm"), "/proc/ref_one(name)\n    return null\n").unwrap();

    let mut check_boundary = false;
    let check = run_declare_overlay(&mut host, &request, Mode::Check, &cache, &mut |event| {
        assert!(!target.exists());
        if matches!(event, transaction::Event::BeforeFinalFreshness) { check_boundary = true; }
        Ok(())
    }).unwrap();
    assert!(check_boundary);
    assert_eq!(check.rows[0].state, State::Stale);
    assert!(!check.committed);
    assert!(check.changed.is_empty());
    assert!(!target.exists());
    assert!(host.query_state().lock().unwrap().snapshot.is_none());

    let mut replacements = 0;
    let write = run_declare_overlay(&mut host, &request, Mode::Write, &cache, &mut |event| {
        match event {
            transaction::Event::BeforeFinalFreshness => assert!(!target.exists()),
            transaction::Event::AfterReplacement(_) => {
                replacements += 1;
                let content = std::fs::read_to_string(&target)?;
                assert!(content.contains("\t.[\"/datum/overlay_child|target\"] = /datum\n"));
            }
            _ => (),
        }
        Ok(())
    }).unwrap();
    assert_eq!(replacements, 1);
    assert_eq!(write.rows[0].state, State::Written);
    assert_eq!(write.changed, [target.clone()]);
    {
        let state = host.query_state();
        let state = state.lock().unwrap();
        let prepared = state.snapshot.as_ref()
            .expect("only the installed physical output permits Original preparation");
        assert!(prepared.prepared_query_tree().unwrap()
            .lookup_type(dm_ir::SymbolId::of("/datum/overlay_child")).is_some());
        prepared.workspace_generator_inputs(GeneratorName::Declare).unwrap();
    }
    let fresh = run(&mut host, &request, &[GeneratorName::Declare], Mode::Check, &cache).unwrap();
    assert_eq!(fresh.rows[0].state, State::Fresh);

    std::fs::remove_file(&target).unwrap();
    let refused = run_declare_overlay(&mut host, &request, Mode::Write, &cache, &mut |event| {
        if matches!(event, transaction::Event::BeforeFinalFreshness) {
            std::fs::write(&target, "// concurrent writer\n")?;
        }
        Ok(())
    }).err().expect("a changed physical negative cannot install");
    assert!(!refused.to_string().is_empty());
    assert_eq!(std::fs::read_to_string(&target).unwrap(), "// concurrent writer\n");
}

#[test]fn actual_original_generation_all_thirteen_real_and_synthetic_subjects_settle_then_reuse_same_bodies(){
 for case in initial::CASES{let(mut host,request,cache,root)=setup(case);let names=super::cold_tests::all_names();let db=Arc::clone(host.query_db());let report=run(&mut host,&request,&names,Mode::Write,&cache).unwrap();assert!(report.committed);assert!(report.cleanup.is_empty());assert!(!report.rows.is_empty());assert!(report.rows.iter().all(|row|names.contains(&row.name)));
  let first={let state=host.query_state();let current=state.lock().unwrap();let snapshot=current.snapshot.as_ref().unwrap();snapshot.require_analysis_context(Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290)).unwrap();assert!(snapshot.diagnostic_tree().is_some());let child=snapshot.workspace_generator_inputs(GeneratorName::AutoTracked).unwrap();assert!(child.policy().archive().uses_body_queries(db.as_ref()));assert!(child.original_analysis_subject().is_some());assert!(snapshot.prepared_query_tree().unwrap().lookup_type(dm_ir::SymbolId::of("/obj/original_generation_item")).is_some());Arc::clone(snapshot.prepared_query_tree().unwrap())};
  let computed=db.db().stats(dm_query::Kind(4)).computed;let warm=run(&mut host,&request,&names,Mode::Write,&cache).unwrap();assert!(!warm.committed);assert!(warm.changed.is_empty());assert!(warm.rows.iter().all(|row|row.state==State::Fresh));assert!(Arc::ptr_eq(&db,host.query_db()));{let state=host.query_state();let state=state.lock().unwrap();assert!(Arc::ptr_eq(&first,state.snapshot.as_ref().unwrap().prepared_query_tree().unwrap()));}assert_eq!(db.db().stats(dm_query::Kind(4)).computed,computed);assert!(!root.join("__dmb_original_analysis_subject__").exists());
  for name in &names{let files:Vec<_>=report.rows.iter().filter(|row|row.name==*name).map(|row|(row.path.strip_prefix(&root).unwrap().to_string_lossy().replace('\\',"/"),std::fs::read_to_string(&row.path).unwrap())).collect();let diagnostics:Vec<_>=report.diagnostics.iter().filter(|row|row.name==*name).map(|row|(&row.relative,row.line,&row.message)).collect();println!("NATIVE_ORIGINAL_GENERATION_FULL={}",serde_json::json!({"case":case,"generator":name.name(),"files":files,"diagnostics":diagnostics}));}
 }
}
#[test]fn actual_original_generation_rejects_caller_context_overrides_before_any_install(){
 for mode in 0..4{let(mut host,mut request,cache,root)=setup("real");match mode{0=>request.defines.insert("UNISSUED".into(),"1".into()),1=>{request.policy_inputs.as_mut().unwrap().analysis_context=Some(crate::policy_request::AnalysisContext::OriginalChecker0290);None},2=>{request.bootstrap_catalog=true;None},_=>{request.policy_inputs.as_mut().unwrap().analysis_context=None;None}};let failure=run(&mut host,&request,&super::cold_tests::all_names(),Mode::Write,&cache).err().expect("actual Original guards/context must refuse");assert!(!failure.to_string().is_empty());assert!(!root.join("code/engine/_generated").exists());assert!(!root.join("code/_generated").exists());assert_eq!(host.query_db().db().stats(dm_query::Kind(4)).computed,0);}
}
#[test]fn actual_original_generation_post_source_phase_first_io_keeps_commits_then_recovers(){
 let(mut host,request,cache,root)=setup("real");let failure=run_using(&mut host,&request,&super::cold_tests::all_names(),Mode::Write,&cache,&mut|_,_|Err(io::Error::from_raw_os_error(1450).into())).err().unwrap();let failure=failure.downcast_ref::<CoordinatorFailure>().unwrap();assert!(failure.committed);assert_eq!(failure.primary.downcast_ref::<io::Error>().unwrap().raw_os_error(),Some(1450));assert!(root.join(GeneratorName::Declare.path()).is_file());assert!(!root.join(GeneratorName::AutoTracked.path()).exists());assert!(host.query_state().lock().unwrap().snapshot.is_none());let completed=run(&mut host,&request,&super::cold_tests::all_names(),Mode::Write,&cache).unwrap();assert!(completed.cleanup.is_empty());assert!(root.join(GeneratorName::AutoTracked.path()).is_file());
}

#[test]fn actual_original_generation_unknown_builtin_override_refuses_without_fabricated_field_then_recovers(){
 let(mut host,request,cache,root)=setup("real");let probe=root.join("code/probe.dm");let original=std::fs::read(&probe).unwrap();let mut bad=original.clone();bad.extend_from_slice(b"\n/obj/original_generation_item\n    no_such_original_generation_field = 3\n");std::fs::write(&probe,bad).unwrap();let failure=run(&mut host,&request,&super::cold_tests::all_names(),Mode::Write,&cache).err().expect("a catalog loan cannot invent unknown builtin fields");assert!(!failure.to_string().is_empty());assert!(!root.join(GeneratorName::AutoTracked.path()).exists());std::fs::write(probe,original).unwrap();run(&mut host,&request,&super::cold_tests::all_names(),Mode::Write,&cache).unwrap();
}
#[test]fn actual_original_generation_questions_refuse_a_foreign_native_seed_before_body_computation(){
 use crate::input_snapshot::{RecordingInputs,FileSystemInputs,GenerationBootstrapFailure};
 let(mut host,request,_cache,root)=crate::generation_test_fixture::fixture();std::fs::remove_file(root.join(GeneratorName::Deps.path())).unwrap();let engine=host.engine(request.project.clone(),Default::default(),true,include_bytes!("../../../fixtures/native_template.bin").to_vec()).unwrap();let db=Arc::clone(host.query_db());let control:Arc<dyn dm_tree::frontend::SettingExpressionQueries>=db.clone();let executor=dm_exec::BuildExecutor::new(1).unwrap();let recording=RecordingInputs::new(FileSystemInputs,0).with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290).with_prepared_sources(host.prepared_sources());let result=recording.prepare_generation_question_bootstrap(&request.project,&Default::default(),dm_tree::frontend::FrontendConfig{workers:1,engine:Some(engine.frontend_seed()),observer:None},&executor,&control,&mut |_|Ok(()));assert!(matches!(result,Err(GenerationBootstrapFailure::Declarations(dm_tree::frontend::GenerationPreparationFailure::Assembly(_)))));assert_eq!(db.db().stats(dm_query::Kind(4)).computed,0);assert!(!root.join(GeneratorName::Deps.path()).exists());
}

#[cfg(windows)]
#[test]fn actual_original_generation_ordinary_workspace_root_uses_canonical_omissions_and_authored_output_namespace(){
 let(mut host,mut request,cache,canonical)=setup("real");let ordinary=dm_preprocess::regions::filesystem_comparison_key(&canonical);assert_ne!(ordinary,canonical,"the control must exercise an actual verbatim/ordinary spelling difference");assert_eq!(std::fs::canonicalize(&ordinary).unwrap(),canonical);request.project=ordinary.join("deepquarry.dme");let workspace=request.policy_inputs.as_mut().unwrap().workspace.as_mut().unwrap();workspace.root=ordinary.clone();workspace.recursive_roots=vec![ordinary.join("code")];workspace.configuration=ordinary.join("tools/ci/lint_scopes.toml");
 let names=super::cold_tests::all_names();let report=run(&mut host,&request,&names,Mode::Write,&cache).unwrap();assert!(report.committed);assert!(report.changed.iter().all(|path|path.starts_with(&ordinary)));assert!(ordinary.join(GeneratorName::AutoTracked.path()).is_file());
 {let state=host.query_state();let state=state.lock().unwrap();let child=state.snapshot.as_ref().unwrap().workspace_generator_inputs(GeneratorName::AutoTracked).unwrap();let mapping=child.policy().mapping();let(_,entry,path,lease)=mapping.original_root_acquisition_using(&mut||Ok::<(),String>(())).unwrap();let subject=child.original_analysis_subject().unwrap();assert_eq!(subject.generation_root(entry,lease).unwrap(),canonical);assert_eq!(subject.generation_workspace_root(entry,lease).unwrap(),ordinary);
 let actual=child.policy().file_exact(path).unwrap();assert!(actual.is_compiled());assert!(actual.view(dm_analysis::policy_inputs::TextView::CompilerDecoded).unwrap().same_view(lease.source_text()));assert!(actual.view(dm_analysis::policy_inputs::TextView::AnalyzeRaw).is_ok());crate::query_db::QueryDb::require_actual_generator_manifest_for_test(child,&ordinary).unwrap();
 assert!(crate::query_db::QueryDb::require_actual_generator_manifest_for_test(child,&canonical).is_err(),"an equal filesystem location does not replace the authored subject root");assert!(crate::query_db::QueryDb::require_actual_generator_manifest_for_test(child,&ordinary.join("code/..")).is_err(),"a path-only alias is not source or workspace authority");
 let foreign=dm_preprocess::AcquiredSource::from_original_bytes(lease.source_text().as_str().as_bytes().to_vec(),());assert!(subject.generation_manifest(&ordinary,entry,foreign.lease()).is_err(),"equal source bytes without the actual lease never authorize the manifest");let other_entry=entry.with_file_name("main.dme");assert!(subject.generation_manifest(&ordinary,&other_entry,lease).is_err(),"the real lease cannot authorize another root entry");}
 let computed=host.query_db().db().stats(dm_query::Kind(4)).computed;let warm=run(&mut host,&request,&names,Mode::Write,&cache).unwrap();assert!(!warm.committed);assert!(warm.changed.is_empty());assert_eq!(host.query_db().db().stats(dm_query::Kind(4)).computed,computed);
}

#[test]fn actual_original_generation_question_preparation_and_assembly_require_the_same_real_catalog_owner(){
 use crate::input_snapshot::{RecordingInputs,FileSystemInputs,GenerationBootstrapFailure,GenerationBootstrapPreparation};
 let(_host,request,_cache,root)=crate::generation_test_fixture::fixture();std::fs::remove_file(root.join(GeneratorName::Deps.path())).unwrap();let owner=dm_tree::checker_builtins::original_analysis_seed().unwrap();let cloned=owner.frontend_seed().clone();let db=Arc::new(crate::query_db::QueryDb::default());let control:Arc<dyn dm_tree::frontend::SettingExpressionQueries>=db.clone();let executor=dm_exec::BuildExecutor::new(1).unwrap();let fresh=||RecordingInputs::new(FileSystemInputs,0).with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);
 let bad=fresh();let refused=bad.prepare_generation_question_bootstrap(&request.project,&Default::default(),dm_tree::frontend::FrontendConfig{workers:1,engine:Some(&cloned),observer:None},&executor,&control,&mut |_|Ok(())).err().expect("equal cloned hierarchy has no actual Original declaration permission");assert!(matches!(refused,GenerationBootstrapFailure::Declarations(dm_tree::frontend::GenerationPreparationFailure::Assembly(_))));assert_eq!(db.db().stats(dm_query::Kind(4)).computed,0);
 let actual=fresh();let config=dm_tree::frontend::FrontendConfig{workers:1,engine:Some(owner.frontend_seed()),observer:None};let frame=match actual.prepare_generation_question_bootstrap(&request.project,&Default::default(),config,&executor,&control,&mut |_|Ok(())).unwrap(){GenerationBootstrapPreparation::MissingOutputs(frame)=>frame,_=>panic!("actual encountered Deps omission is required")};assert!(matches!(frame.into_native_questions(&actual,dm_tree::frontend::FrontendConfig{workers:1,engine:Some(&cloned),observer:None},&executor,&db),Err(GenerationBootstrapFailure::Declarations(dm_tree::frontend::GenerationPreparationFailure::Assembly(_)))));assert_eq!(db.db().stats(dm_query::Kind(4)).computed,0,"changing to a clone after real preparation still refuses before any body computation");
 let recovered=fresh();let frame=match recovered.prepare_generation_question_bootstrap(&request.project,&Default::default(),config,&executor,&control,&mut |_|Ok(())).unwrap(){GenerationBootstrapPreparation::MissingOutputs(frame)=>frame,_=>panic!("same actual missing output")};let frame=frame.into_native_questions(&recovered,config,&executor,&db).unwrap();frame.with_questions(&recovered,|questions|{assert!(questions.tree().lookup_type(dm_ir::SymbolId::of("/datum/probe")).is_some());assert!(questions.source_file_count()>0);Ok::<_,io::Error>(Ok::<_,()>(()))}).unwrap().unwrap();assert_eq!(db.db().stats(dm_query::Kind(4)).computed,0);assert!(!root.join(GeneratorName::Deps.path()).exists(),"question preparation never installs an output");
}

#[test]fn actual_original_generation_synthetic_fixed_manifest_contract_rejects_foreign_subject_and_header_as_physical(){
 use dq_analyze::captured_untyped::ManifestRead;
 let mut children=Vec::new();
 for case in ["absent","noninclude","invalid_utf8"]{
  let(mut host,request,cache,root)=setup(case);let report=run(&mut host,&request,&[GeneratorName::AutoTracked],Mode::Write,&cache).unwrap();assert!(report.committed);assert!(!root.join("__dmb_original_analysis_subject__").exists());
  let child={let state=host.query_state();let state=state.lock().unwrap();Arc::clone(state.snapshot.as_ref().unwrap().workspace_generator_inputs(GeneratorName::AutoTracked).unwrap())};
  let mapping=child.policy().mapping();let(_,entry,path,lease)=mapping.original_root_acquisition_using(&mut||Ok::<(),String>(())).unwrap();let subject=child.original_analysis_subject().unwrap();assert!(subject.synthetic());subject.require_bound_mapping(mapping).unwrap();assert_eq!(subject.generation_workspace_root(entry,lease).unwrap(),root);assert!(subject.authenticates_header(entry,lease));
  let manifest=subject.generation_manifest(&root,entry,lease).unwrap();match case{"absent"=>assert!(matches!(manifest,ManifestRead::ProvenUnavailable)),"noninclude"=>assert!(matches!(manifest,ManifestRead::OriginalBytes(bytes)if bytes==b"/datum/ignored_fixed_manifest\n")),"invalid_utf8"=>assert!(matches!(manifest,ManifestRead::OriginalBytes(bytes)if bytes==b"\xff#include ignored\n")),_=>unreachable!()}
  crate::query_db::QueryDb::require_actual_generator_manifest_for_test(&child,&root).unwrap();
  // The header's genuine CompilerDecoded view is semantic-only. It cannot
  // satisfy the physical manifest route or manufacture AnalyzeRaw bytes.
  let header=child.policy().file_exact(path).unwrap();assert!(header.view(dm_analysis::policy_inputs::TextView::CompilerDecoded).unwrap().same_view(lease.source_text()));assert!(header.view(dm_analysis::policy_inputs::TextView::AnalyzeRaw).is_err());assert!(crate::query_db::QueryDb::require_physical_generator_manifest_for_test(&child,path,lease).is_err());
  let foreign=dm_preprocess::AcquiredSource::from_original_bytes(lease.source_text().as_str().as_bytes().to_vec(),());assert!(!subject.authenticates_header(entry,foreign.lease()));assert!(subject.generation_manifest(&root,entry,foreign.lease()).is_err());assert!(subject.generation_manifest(&root,&entry.with_file_name("other.dme"),lease).is_err());assert!(crate::query_db::QueryDb::require_actual_generator_manifest_for_test(&child,&root.join("code/..")).is_err());
  children.push(child);
 }
 for(index,child)in children.iter().enumerate(){let foreign=&children[(index+1)%children.len()];let subject=child.original_analysis_subject().unwrap();assert!(subject.require_bound_mapping(foreign.policy().mapping()).is_err(),"another real complete subject cannot substitute merely because both are synthetic");let(_,entry,_,lease)=foreign.policy().mapping().original_root_acquisition_using(&mut||Ok::<(),String>(())).unwrap();assert!(!subject.authenticates_header(entry,lease));assert!(subject.generation_manifest(&root_of_child(foreign),entry,lease).is_err());}
 fn root_of_child(child:&crate::runner_host::policy_capture::CapturedPolicyInputs)->PathBuf{let subject=child.original_analysis_subject().unwrap();let(_,entry,_,lease)=child.policy().mapping().original_root_acquisition_using(&mut||Ok::<(),String>(())).unwrap();subject.generation_workspace_root(entry,lease).unwrap().to_path_buf()}
}

use super::*;
use crate::runner_host::query_snapshot::analysis_context_tests::{fixture,run,current};
#[path="../../../../analyze/fixtures/report_configuration.rs"]mod report_config;

#[test]
fn actual_original_selected_union_observes_same_completed_folds_and_real_unused_allow(){
 let (mut host,mut request,root)=fixture("/proc/scheduled_probe()\n    sleep(1) // ALLOW(scheduler): test scheduler usage across actual producer folds\n    sleep(2)\n");
 request.policy_inputs.as_mut().unwrap().analysis_context=Some(AnalysisContext::OriginalAnalyze0290);
 let config=root.join("tools/ci/lint_scopes.toml");
 std::fs::write(config,report_config::with_overlay("")).unwrap();
 // The independent raw-tree producer sees an uncompiled file in the actual
 // selected CODE roster. The stale annotation must come from selected MAPS.
 std::fs::write(root.join("code/notices.dm"),"/proc/registration()\n    on_notice(/datum/notice/covered) // ALLOW(notice_publisher): test actual subscriber annotation consumption\n    on_notice(/datum/notice/unpublished)\n").unwrap();
 std::fs::write(root.join("maps/stale.dm"),"/proc/stale()\n    return // ALLOW(scheduler): test genuinely unused annotation across roots\n").unwrap();
 run(&mut host,&request);
 let budget=Budget::new(8<<20).unwrap();let mut control=Operation{budget:&budget,poll:&||Ok(())};
 let all=full_unused::registered_full_selection(&[],&mut control).unwrap();
 let retained=["allow_annotations","notice_publisher","report_in_catch","scheduler"];
 let exclusions:Vec<_>=all.names().iter().filter(|name|!retained.contains(&name.as_str())).map(|name|format!("-{name}")).collect();
 current(&host,|snapshot|{
  let mut observed=std::collections::BTreeSet::new();
  snapshot.with_native_allow_full_run_using(&snapshot.tree,&exclusions,None,None,Some(&mut|meta,rows,_,_|{
   let name=meta.name;
   assert!(observed.insert(name.to_owned()),"actual producer must be observed once");
   match (name,rows){
    ("scheduler",UnionRows::Raw(rows))=>{let mut sites=0;let mut allows=0;for file in rows{sites+=file.run.sites.len();allows+=file.allow_used.len();for index in 0..file.run.sites.len(){assert_eq!(file.site_text(index),Some("sleep(2)"));}}assert_eq!((sites,allows),(1,1));},
    ("notice_publisher",UnionRows::Tree(data))=>{assert_eq!(data.sites().len(),1);assert!(data.sites()[0].msg.contains("/datum/notice/unpublished"));assert_eq!(data.allow_used().len(),1);},
    ("report_in_catch",UnionRows::Tree(data))=>{assert!(data.sites().is_empty()&&data.allow_used().is_empty());},
    ("allow_annotations",UnionRows::Validation(data))=>{
     // The notice scanner consumes its direct spelling, but the original
     // registered ALLOW inventory does not advertise that name.
     let [site]=data.sites.as_slice() else {panic!("expected one actual notice annotation validation finding")};
     assert_eq!((site.rel.as_str(),site.line,site.rule.as_str()),("code/notices.dm",2,"unknown_lint"));
     assert!(site.msg.starts_with("ALLOW(notice_publisher): unknown lint; known: "));
     assert_eq!(data.source_text.as_slice(),["on_notice(/datum/notice/covered) // ALLOW(notice_publisher): test actual subscriber annotation consumption"]);
    },
    _=>panic!("foreign actual producer evidence"),
   }
   Ok(())
  }),|data,_,_|{
   assert_eq!(data.selected().len(),retained.len());
   assert_eq!(data.unused().len(),1);
   assert!(data.unused()[0].starts_with("maps/stale.dm:2: ALLOW(scheduler) is unused"));
   Ok(())
  }).unwrap();
  assert_eq!(observed.len(),retained.len());
  // A non-alias subset runs the same genuine producer and unused-ALLOW fold.
  let subset=["allow_annotations","notice_publisher","scheduler"];
  let omit:Vec<_>=all.names().iter().filter(|name|!subset.contains(&name.as_str()))
   .map(|name|format!("-{name}")).collect();
  assert_eq!(selected_report::preflight_no_aux_raw_subset(&omit,&mut control).unwrap().as_ref(),subset);
  assert!(selected_report::validate_selection_v2(&omit,&budget,dq_analyze::selected_exclusions_wire::JudgmentV2::Raw).is_err());
  let mut completed=Vec::new();
  snapshot.with_native_allow_full_run_using(&snapshot.tree,&omit,None,None,Some(&mut|meta,_,_,_|{
   completed.push(meta.name);
   Ok(())
  }),|data,_,_|{
   assert!(data.selected().iter().map(String::as_str).eq(subset));
   assert_eq!(data.unused().len(),1);
   assert!(data.unused()[0].starts_with("maps/stale.dm:2: ALLOW(scheduler) is unused"));
   Ok(())
  }).unwrap();
  assert_eq!(completed,subset);
  let mut wrong=omit.clone();wrong.swap(0,1);
  assert!(selected_report::preflight_no_aux_raw_subset(&wrong,&mut control).is_err());
  let mut wrong=omit.clone();wrong.push("-not_a_registered_policy".into());
  assert!(selected_report::preflight_no_aux_raw_subset(&wrong,&mut control).is_err());
  let mut wrong=omit.clone();wrong.push(omit[0].clone());
  assert!(selected_report::preflight_no_aux_raw_subset(&wrong,&mut control).is_err());
  let empty:Vec<_>=all.names().iter().map(|name|format!("-{name}")).collect();
  assert!(selected_report::preflight_no_aux_raw_subset(&empty,&mut control).is_err());
  // Unported ImageDir cannot be inferred from its registry registration.
  let unsupported:Vec<_>=exclusions.iter().filter(|name|name.as_str()!="-image_dir_after_build").cloned().collect();
  let error=snapshot.with_native_allow_full_run_using(&snapshot.tree,&unsupported,None,None,Some(&mut|_,_,_,_|panic!("preflight cannot stage a partial selection")),|_,_,_|->io::Result<()>{panic!("unsupported producer cannot finish a union")}).unwrap_err();
  assert!(matches!(error,Failure::Unsupported(message)if message.contains("image_dir_after_build")));
 });
}

#[test]
fn selected_handler_raw_loan_uses_hidden_maps_and_preserves_a_true_missing_path(){
 let(mut host,mut request,root)=fixture("/proc/probe()\n    return\n");
 let intent=request.policy_inputs.as_mut().unwrap();
 intent.analysis_context=Some(AnalysisContext::OriginalAnalyze0290);
 intent.workspace_auxiliary=vec![Q::SiliconEntry];
 std::fs::write(root.join("tools/ci/lint_scopes.toml"),report_config::with_overlay("")).unwrap();
 std::fs::write(root.join("maps/.handler.dm"),"// actual hidden map bytes\n").unwrap();
 std::fs::write(root.join("maps/visible.dm"),"// ALLOW(handlers): recorded map output annotation witness\n").unwrap();
 run(&mut host,&request);
 current(&host,|snapshot|{
  let budget=Budget::new(1<<20).unwrap();
  let mut control=Operation{budget:&budget,poll:&||Ok(())};
  let plan=full_unused::SelectedTreePlanData::new([dq_analyze::tree::CODE_MAPS_DM],&mut control).unwrap();
  let narrow=full_unused::SelectedTreePlanData::new([dq_analyze::tree::CODE_DM],&mut control).unwrap();
  let capture=snapshot.native_workspace.as_ref().unwrap();
  let inputs=snapshot.workspace_semantic_inputs(Q::SiliconEntry).unwrap();
  let guard=snapshot.workspace_native_read().unwrap();
  let queries=snapshot.native_raw_queries.as_ref().unwrap();
  queries.with_workspace_code_pages(capture,&guard,|reader|{
   let files=reader.selected_handler_files(inputs.policy(),&plan)?;
   for(rel,expected)in [
    ("maps/.handler.dm",Some("// actual hidden map bytes\n")),
    ("maps/visible.dm",Some("// ALLOW(handlers): recorded map output annotation witness\n")),
    ("maps/missing.dm",None),("interface/other.dm",None),
   ]{
    let mut calls=0;
    files.with_file(rel,&mut|value|{
     calls+=1;
     let text=value.map(|views|views.raw().map(str::to_owned)).transpose()?;
     assert_eq!(text.as_deref(),expected);
     Ok(())
    })?;
    assert_eq!(calls,1);
   }
   assert!(reader.selected_handler_files(inputs.policy(),&narrow).is_err());
   Ok(())
  }).unwrap();
 });
}

#[test]
fn actual_clean_image_dir_private_selected_stages_same_named_section_and_refuses_foreign() {
 use crate::selected_report_spool::Stage;
 let source="/proc/image_loan_probe(image/actual)
    actual.dir = 2
";
 let (mut host,mut request,root)=fixture(source);
 let intent=request.policy_inputs.as_mut().unwrap();
 intent.analysis_context=Some(AnalysisContext::OriginalAnalyze0290);
 intent.workspace_auxiliary=vec![Q::ImageDir];
 std::fs::write(root.join("tools/ci/lint_scopes.toml"),
  report_config::with_overlay("[lint.image_dir_after_build.lists]
exempt_files=[]
")).unwrap();
 let cache=crate::test_scratch::dir("private-selected-image-report-spools");
 let prepared=crate::request_runner::run_build_with_host(request,&mut host).unwrap();
 let budget=Budget::new(8<<20).unwrap();
 let mut control=Operation{budget:&budget,poll:&||Ok(())};
 let all=full_unused::registered_full_selection(&[],&mut control).unwrap();
 let exclusions:Vec<_>=all.names().iter().filter(|name|!PRIVATE_IMAGE_DIR_ROSTER.contains(&name.as_str()))
  .map(|name|format!("-{name}")).collect();
 let mut standalone=Vec::new();
 let mut named=crate::runner_host::BuildHost::default();
 assert!(!named.write_original_image_dir_report(&root,&cache,60,&mut standalone).unwrap());
 let mut shared=Vec::new();
 current(&host,|snapshot|{
  let (clean,report)=snapshot.stage_private_image_dir_report(&prepared,&exclusions,&budget,&root,Stage::new(&cache).unwrap()).unwrap();
  assert!(!clean);
  report.publish(&mut shared).unwrap();
 });
 assert!(standalone.windows(b"code/probe.dm:2".len()).any(|part|part==b"code/probe.dm:2"));
 assert!(shared.windows(standalone.len()).any(|part|part==standalone));

 let (mut foreign,mut foreign_request,foreign_root)=fixture(source);
 let foreign_intent=foreign_request.policy_inputs.as_mut().unwrap();
 foreign_intent.analysis_context=Some(AnalysisContext::OriginalAnalyze0290);
 foreign_intent.workspace_auxiliary=vec![Q::ImageDir];
 std::fs::write(foreign_root.join("tools/ci/lint_scopes.toml"),
  report_config::with_overlay("[lint.image_dir_after_build.lists]
exempt_files=[]
")).unwrap();
 run(&mut foreign,&foreign_request);
 current(&host,|actual|current(&foreign,|other|{
  let proof=actual.image_dir_proof.as_ref().unwrap();
  assert!(proof.bind(actual.body_archive.as_ref().unwrap()).is_ok());
  assert!(proof.bind(other.body_archive.as_ref().unwrap()).is_err());
  assert!(other.stage_private_image_dir_report(&prepared,&exclusions,&budget,&foreign_root,Stage::new(&cache).unwrap()).is_err());
 }));
}

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

#[test]
fn actual_private_map_and_layering_share_complete_capture_and_warm_report() {
 use super::selected_report::PRIVATE_MAP_AND_LAYERING;
 use crate::selected_report_spool::Stage;
 let (mut host,mut request,root)=fixture(concat!(
  "/obj/base\n    var/known\n/obj/base/child\n",
  "/proc/scheduled()\n",
  "    sleep(1) // ALLOW(scheduler): actual joined report consumes this annotation\n",
 ));
 for (relative,source) in [
  ("deepquarry.dme",concat!(
   "#include \"code/probe.dm\"\n",
   "#include \"code/engine/probe.dm\"\n",
   "#include \"code/library/probe.dm\"\n",
   "#include \"code/content/probe.dm\"\n",
  )),
  ("code/engine/probe.dm","/proc/engine_probe()\n    library_probe()\n"),
  ("code/library/probe.dm","/proc/library_probe()\n    downstream_probe()\n"),
  ("code/content/probe.dm","/proc/downstream_probe()\n    return\n"),
  ("maps/.hidden/edit.dmm","/obj/base/child{known = 1; lost = 2}\n"),
  ("maps/stale.dm","/proc/stale()\n    return // ALLOW(scheduler): actual joined report sees this unused map annotation\n"),
 ] {
  let path=root.join(relative);
  std::fs::create_dir_all(path.parent().unwrap()).unwrap();
  std::fs::write(path,source).unwrap();
 }
 std::fs::write(root.join("tools/ci/lint_scopes.toml"),report_config::with_overlay("")).unwrap();
 request.no_cache=false;
 let intent=request.policy_inputs.as_mut().unwrap();
 intent.analysis_context=Some(AnalysisContext::OriginalAnalyze0290);
 intent.workspace_auxiliary=Q::SELECTED_MAP_AND_LAYERING.to_vec();
 let cache=crate::test_scratch::dir("private-map-layering-spools");
 let roster_budget=Budget::new(8<<20).unwrap();
 let mut control=Operation{budget:&roster_budget,poll:&||Ok(())};
 let all=full_unused::registered_full_selection(&[],&mut control).unwrap();
 let exclusions:Vec<_>=all.names().iter().filter(|name|!PRIVATE_MAP_AND_LAYERING.contains(&name.as_str()))
  .map(|name|format!("-{name}")).collect();

 let mut mixed=request.clone();
 mixed.policy_inputs.as_mut().unwrap().workspace_auxiliary.push(Q::Keys);
 assert!(mixed.policy_inputs.unwrap().admit().is_err());
 let mut partial=request.clone();
 partial.policy_inputs.as_mut().unwrap().workspace.as_mut().unwrap().recursive_roots.pop();
 assert!(partial.policy_inputs.unwrap().admit().is_err());

 let db=Arc::clone(host.query_db());
 let mut prior=None;
 for _ in 0..2 {
  let prepared=crate::request_runner::run_build_with_host(request.clone(),&mut host).unwrap();
  assert!(Arc::ptr_eq(&db,host.query_db()));
  current(&host,|snapshot|{
   let workspace=snapshot.native_workspace.as_ref().unwrap();
   assert!(workspace.matches_auxiliary_questions(Q::SELECTED_MAP_AND_LAYERING));
   assert!(workspace.has_map_edits_capture());
   let budget=Budget::new(8<<20).unwrap();
   let (clean,staged)=snapshot.stage_private_map_and_layering(
    &prepared,&exclusions,&budget,&root,Stage::new(&cache).unwrap()).unwrap();
   assert!(!clean);
   let mut output=Vec::new();
   staged.publish(&mut output).unwrap();
   let report=std::str::from_utf8(&output).unwrap();
   let engine=report.find("code/engine/probe.dm:2: [engine_layering/external_dependency]").unwrap_or_else(||panic!("{report}"));
   let library=report.find("code/library/probe.dm:2: [library_layering/external_dependency]").unwrap_or_else(||panic!("{report}"));
   let map=report.find("maps/.hidden/edit.dmm:1: [map_edits/unknown_var]").unwrap_or_else(||panic!("{report}"));
   assert!(engine<library&&library<map,"{report}");
   assert!(report.contains("maps/stale.dm:2: ALLOW(scheduler) is unused"),"{report}");
   if let Some(previous)=&prior{assert_eq!(&output,previous)}else{prior=Some(output)}
  });
 }

 request.policy_inputs.as_mut().unwrap().workspace_auxiliary=vec![Q::MapEdits];
 let foreign=crate::request_runner::run_build_with_host(request,&mut host).unwrap();
 current(&host,|snapshot|{
  let budget=Budget::new(8<<20).unwrap();
  assert!(snapshot.stage_private_map_and_layering(
   &foreign,&exclusions,&budget,&root,Stage::new(&cache).unwrap()).is_err());
 });
 assert!(!root.join("deepquarry.dmb").exists());
}

#[path="../../../../analyze/fixtures/native-ui-actions-workspace/fixture.rs"]
mod ui_fixture;

#[test]
fn actual_private_doc_ui_uses_one_source_capture_and_keeps_productive_roles_separate() {
 use super::selected_report::PRIVATE_DOC_UI;
 use crate::selected_report_spool::Stage;
 let (mut host,mut request,root)=fixture("/proc/known_doc()\n    return\n");
 let live_doc="\x60\x60\x60dm\nknown_doc()\nmissing_doc()\n\x60\x60\x60\n";
 let interface="act('bogus', {});";
 let dispatcher=dq_analyze::ui_actions_policy::DISPATCHER;
 for (relative,text) in [
  ("deepquarry.dme","#include \"missing-compiled-file.dm\"\n"),
  (dispatcher,ui_fixture::DISPATCHER),
  ("code/main.dm","/obj/machine\n    tgui_id = \"Machine\"\n/obj/machine/proc/act_go(mob/user, value)\n    return ui_text(value)\n"),
  ("doc/rewrite/live.md",live_doc),
  ("doc/rewrite/exempt.md","excluded Markdown must not be acquired"),
  ("tgui/packages/tgui/interfaces/Machine.tsx",interface),
  ("maps/unused.dm","/proc/stale()\n    return // ALLOW(scheduler): actual unused annotation in joined source\n"),
 ] {
  let path=root.join(relative);
  std::fs::create_dir_all(path.parent().unwrap()).unwrap();
  std::fs::write(path,text).unwrap();
 }
 std::fs::write(root.join("tools/ci/lint_scopes.toml"),report_config::with_overlay(
  "[lint.doc_snippets]\nexempt_files=['doc/rewrite/exempt.md']\n")).unwrap();
 let intent=request.policy_inputs.as_mut().unwrap();
 intent.analysis_context=Some(AnalysisContext::OriginalAnalyze0290);
 intent.workspace_auxiliary=vec![Q::DocUiFullAllow];
 intent.workspace.as_mut().unwrap().recursive_roots=vec![
  root.join("code"),root.join("doc/rewrite"),root.join("maps"),root.join("tgui/packages/tgui/interfaces"),
 ];
 let mut foreign=request.clone();
 foreign.policy_inputs.as_mut().unwrap().workspace_auxiliary.push(Q::UiActionsFullAllow);
 assert!(foreign.policy_inputs.unwrap().admit().is_err());
 let budget=Budget::new(8<<20).unwrap();
 let mut work=Operation{budget:&budget,poll:&||Ok(())};
 let all=full_unused::registered_full_selection(&[],&mut work).unwrap();
 let exclusions:Vec<_>=all.names().iter().filter(|name|!PRIVATE_DOC_UI.contains(&name.as_str()))
  .map(|name|format!("-{name}")).collect();
 let cache=crate::test_scratch::dir("private-doc-ui-spools");
 for productive in [true,false] {
  if !productive {std::fs::write(root.join(dispatcher),"not a dispatcher\n").unwrap();}
  let prepared=crate::request_runner::run_build_with_host(request.clone(),&mut host).unwrap();
  assert!(matches!(prepared,crate::request::BuildOutcome::RawQueryPrepared{retained:true,..}));
  let state=host.query_state();
  let held=state.lock().unwrap();
  assert!(held.snapshot.is_none());
  let raw=held.raw_snapshot.as_ref().unwrap();
  let count=|text:&str|raw.capture.raw_input_files().filter(|lease|lease.source_text().as_str()==text).count();
  assert_eq!(count(live_doc),1,"Docs payload remains productive for both dispatcher outcomes");
  assert_eq!(count(interface),usize::from(productive),"UI-only payload is acquired at most once");
  assert_eq!(count("excluded Markdown must not be acquired"),0);
  let budget=Budget::new(8<<20).unwrap();
  let (clean,verified)=raw.stage_private_doc_ui(&prepared,&exclusions,&budget,&root,Stage::new(&cache).unwrap()).unwrap();
  assert!(!clean);
  let mut bytes=Vec::new();
  verified.publish(&mut bytes).unwrap();
  let report=std::str::from_utf8(&bytes).unwrap();
  assert!(report.contains("doc/rewrite/live.md:3: [doc_snippets/doc_unknown_name] missing_doc()"),"{report}");
  assert_eq!(report.contains("tgui/packages/tgui/interfaces/Machine.tsx"),productive,"{report}");
  assert!(report.contains("ALLOW(scheduler): 1 annotation, but no lint run used any"),"{report}");
  assert_eq!(report.matches("allow annotations: 1 unused").count(),1,"{report}");
  assert!(raw.stage_private_doc_ui(&prepared,&[],&budget,&root,Stage::new(&cache).unwrap()).is_err());
 }
}

#[test]
fn private_authored_doc_ui_dispatcher_precedes_productive_interface_reads() {
    let (mut host, mut request, root) = fixture("/obj/base\n    var/known\n/proc/known_doc()\n    return\n");
    let dispatcher = dq_analyze::ui_actions_policy::DISPATCHER;
    let interface = "tgui/packages/tgui/interfaces/Machine.tsx";
    let markdown = "doc/rewrite/live.md";
    for (relative, content) in [
        ("deepquarry.dme", concat!(
            "#include \"code/probe.dm\"\n",
            "#include \"code/engine/probe.dm\"\n",
            "#include \"code/library/probe.dm\"\n",
            "#include \"code/content/probe.dm\"\n",
        )),
        ("code/engine/probe.dm", "/proc/engine_probe()\n    library_probe()\n"),
        ("code/library/probe.dm", "/proc/library_probe()\n    downstream_probe()\n"),
        ("code/content/probe.dm", "/proc/downstream_probe()\n    return\n"),
        ("code/main.dm", "/obj/machine\n    tgui_id = \"Machine\"\n/obj/machine/proc/act_go(mob/user, value)\n    return value\n"),
        ("maps/stale.dm", "/proc/stale()\n    return // ALLOW(scheduler): exact mixed capture unused annotation\n"),
        (dispatcher, ui_fixture::DISPATCHER),
        (interface, "act('bogus', {});"),
        (markdown, "\x60\x60\x60dm\nknown_doc()\nmissing_doc()\n\x60\x60\x60\n"),
        ("maps/edit.dmm", "/obj/base{known = 1; lost = 2}\n"),
    ] {
        let path = root.join(relative);
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(path, content).unwrap();
    }
    std::fs::write(root.join("tools/ci/lint_scopes.toml"), report_config::with_overlay("")).unwrap();
    let intent = request.policy_inputs.as_mut().unwrap();
    intent.analysis_context = Some(AnalysisContext::OriginalAnalyze0290);
    intent.workspace_auxiliary = Q::PRIVATE_AUTHORED_DOC_UI.to_vec();
    intent.workspace.as_mut().unwrap().recursive_roots = vec![
        root.join("code"), root.join("doc/rewrite"), root.join("maps"),
        root.join("tgui/packages/tgui/interfaces"),
    ];
    assert!(request.policy_inputs.clone().unwrap().admit().is_err());
    let mut foreign = request.clone();
    foreign.policy_inputs.as_mut().unwrap().workspace_auxiliary.push(Q::Keys);
    assert!(foreign.policy_inputs.unwrap().admit_private_authored_doc_ui().is_err());
    let inspect = |host: &crate::runner_host::BuildHost, productive| {
        current(host, |snapshot| {
            let owner = snapshot.native_workspace.as_ref().unwrap();
            assert!(owner.has_map_edits_capture());
            assert!(owner.matches_auxiliary_questions(Q::PRIVATE_AUTHORED_DOC_UI));
            use dq_analyze::captured_raw_tree_pages::Policy;
            assert!(owner.covers_raw_tree_policy(Policy::DocSnippets, &mut |_| Ok(())).unwrap());
            assert!(owner.covers_raw_tree_policy(Policy::UiActions, &mut |_| Ok(())).unwrap());
            assert_eq!(owner.prepared_ui_dispatcher().unwrap().needs_sources(), productive);
            let dispatcher_index = owner.ui_dispatcher_index().unwrap().unwrap();
            assert!(owner.path(dispatcher_index).unwrap().ends_with(dispatcher));
            let contains = |suffix: &str| (0..owner.file_count()).any(|i| owner.path(i).unwrap().ends_with(suffix));
            assert!(contains(markdown));
            assert_eq!(contains(interface), productive);
        });
    };
    let prepared = crate::request_runner::prepare_private_authored_doc_ui(request.clone(), &mut host).unwrap();
    inspect(&host, true);
    let budget = Budget::new(8 << 20).unwrap();
    let mut control = Operation { budget: &budget, poll: &|| Ok(()) };
    let registry = full_unused::registered_full_selection(&[], &mut control).unwrap();
    let names = super::selected_report::PRIVATE_AUTHORED_DOC_UI;
    let exclusions: Vec<_> = registry.names().iter().filter(|name| !names.contains(&name.as_str()))
        .map(|name| format!("-{name}")).collect();
    let cache = crate::test_scratch::dir("private-authored-doc-ui-report");
    let mut output = Vec::new();
    current(&host, |snapshot| {
        let (clean, verified) = snapshot.stage_private_authored_doc_ui(
            &prepared, &exclusions, &budget, &root, crate::selected_report_spool::Stage::new(&cache).unwrap(),
        ).unwrap();
        assert!(!clean);
        verified.publish(&mut output).unwrap();
        assert!(snapshot.stage_private_authored_doc_ui(
            &prepared, &[], &budget, &root, crate::selected_report_spool::Stage::new(&cache).unwrap(),
        ).is_err());
    });
    let report = std::str::from_utf8(&output).unwrap();
    let doc = report.find("[doc_snippets/doc_unknown_name]").unwrap_or_else(|| panic!("{report}"));
    let engine = report.find("[engine_layering/external_dependency]").unwrap_or_else(|| panic!("{report}"));
    let library = report.find("[library_layering/external_dependency]").unwrap_or_else(|| panic!("{report}"));
    let map = report.find("[map_edits/unknown_var]").unwrap_or_else(|| panic!("{report}"));
    let ui = report.find("tgui/packages/tgui/interfaces/Machine.tsx:").unwrap_or_else(|| panic!("{report}"));
    assert!(doc < engine && engine < library && library < map && map < ui, "{report}");
    assert!(report.contains("code/main.dm:4: [ui_actions/ui_unvalidated_param]"), "{report}");
    assert_eq!(report.matches("allow annotations: 1 unused").count(), 1, "{report}");

    // Only an independently built legacy CLI is accepted here.
    if let Some(legacy) = std::env::var_os("DQ_PRIVATE_MIXED_LEGACY_ANALYZE") {
        let legacy = std::path::PathBuf::from(legacy);
        assert!(legacy.is_absolute());
        let mut command = std::process::Command::new(legacy);
        command.args(["check", "--raw", "--no-cache", "--no-selftest", "--unused", "--root"])
            .arg(&root).arg("--lint").args(&exclusions).env_remove("DQ_ALLOW_USAGE");
        #[cfg(windows)] {
            use std::os::windows::process::CommandExt;
            command.creation_flags(0x08000000 | 0x00004000);
        }
        let expected = command.output().expect("run independent legacy mixed Analyze");
        assert_eq!(expected.status.code(), Some(1), "{}", String::from_utf8_lossy(&expected.stderr));
        assert_eq!(report, std::str::from_utf8(&expected.stdout).unwrap());
    }

    // Set the oversized length without allocating its contents in the test.
    std::fs::OpenOptions::new().write(true).open(root.join(interface)).unwrap().set_len(64 << 20).unwrap();
    std::fs::write(root.join(dispatcher), "// no dispatcher\n").unwrap();
    crate::request_runner::prepare_private_authored_doc_ui(request.clone(), &mut host).unwrap();
    inspect(&host, false);

    std::fs::write(root.join(dispatcher), ui_fixture::DISPATCHER).unwrap();
    let error = crate::request_runner::prepare_private_authored_doc_ui(request, &mut host).unwrap_err();
    assert!(error.downcast_ref::<std::io::Error>().is_some_and(|error|
        error.kind() == std::io::ErrorKind::InvalidData && error.to_string().contains("policy original exceeds remaining capture budget")
    ), "{error}");
}

#[test]
fn private_reactive_raw_union_uses_one_authored_capture_and_allow_fold() {
    let (mut host, mut request, root) = fixture(concat!(
        "#define CAPABILITIES(...)\n",
        "#define PROC_REF(P) #P\n",
        "/datum/act\n/datum/act/eval\n/obj/probe\n",
        "/obj/probe/proc/dynamic(datum/act/eval/A)\n",
        "    return vars[\"probe\"]\n",
        "CAPABILITIES(/obj/probe,when(PROC_REF(dynamic)))\n",
    ));
    std::fs::write(root.join("tools/ci/lint_scopes.toml"), report_config::with_overlay("")).unwrap();
    std::fs::write(root.join("code/internal.dm"), concat!(
        "var/raw = _om_code\n",
        "var/kept = _om_kept // ALLOW(engine_internal): this fixture consumes a real raw annotation\n",
    )).unwrap();
    std::fs::write(root.join("maps/unused.dm"),
        "var/unused // ALLOW(scheduler): this fixture has one actual unused annotation\n").unwrap();
    let intent = request.policy_inputs.as_mut().unwrap();
    intent.analysis_context = Some(AnalysisContext::OriginalAnalyze0290);
    intent.workspace_auxiliary = Q::SELECTED_REACTIVE.to_vec();
    let prepared = crate::request_runner::run_build_with_host(request.clone(), &mut host).unwrap();
    let budget = Budget::new(8 << 20).unwrap();
    let mut control = Operation { budget: &budget, poll: &|| Ok(()) };
    let registered = full_unused::registered_full_selection(&[], &mut control).unwrap();
    let selected = super::selected_report::PRIVATE_REACTIVE_RAW_UNION;
    let exclusions: Vec<_> = registered.names().iter().filter(|name| !selected.contains(&name.as_str()))
        .map(|name| format!("-{name}")).collect();
    let cache = crate::test_scratch::dir("private-reactive-raw-union");
    let render = |host: &crate::runner_host::BuildHost, prepared: &crate::request::BuildOutcome| {
        current(host, |snapshot| {
            snapshot.stage_private_reactive_raw_union(
                prepared, &exclusions, &budget, &root, crate::selected_report_spool::Stage::new(&cache).unwrap(),
            )
        })
    };
    let (clean, verified) = render(&host, &prepared).unwrap();
    assert!(!clean);
    let mut output = Vec::new();
    verified.publish(&mut output).unwrap();
    let report = std::str::from_utf8(&output).unwrap();
    let raw = report.find("code/internal.dm:1: [engine_internal/internal]").unwrap_or_else(|| panic!("{report}"));
    let semantic = report.find("[reads/dynamic_read]").unwrap_or_else(|| panic!("{report}"));
    assert!(raw < semantic, "{report}");
    assert!(!report.contains("[engine_internal/internal] _om_kept"), "{report}");
    assert_eq!(report.matches("allow annotations: 1 unused").count(), 1, "{report}");

    if let Some(path) = std::env::var_os("DQ_PRIVATE_REACTIVE_RAW_LEGACY_ANALYZE") {
        let legacy = std::path::PathBuf::from(path);
        assert!(legacy.is_absolute() && legacy.is_file(), "provide an independent legacy Analyze executable");
        let mut command = std::process::Command::new(legacy);
        command.args(["check", "--raw", "--no-cache", "--no-selftest", "--unused", "--root"])
            .arg(&root).arg("--lint").args(&exclusions)
            .env_remove("DQ_ALLOW_USAGE")
            .env("DQ_ANALYZE_SHARED_CACHE", "off")
            .env("DQ_GEN_STORE", "off");
        #[cfg(windows)] {
            use std::os::windows::process::CommandExt;
            command.creation_flags(0x08000000 | 0x00004000);
        }
        let expected = command.output().expect("run independent legacy Analyze for the same authored fixture");
        assert_eq!(expected.status.code(), Some(i32::from(!clean)), "{}", String::from_utf8_lossy(&expected.stderr));
        assert_eq!(report, std::str::from_utf8(&expected.stdout).unwrap());
    }

    request.policy_inputs.as_mut().unwrap().workspace_auxiliary = Q::SELECTED_READS.to_vec();
    let foreign = crate::request_runner::run_build_with_host(request, &mut host).unwrap();
    assert!(render(&host, &foreign).is_err());
}

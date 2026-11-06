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
  snapshot.with_native_allow_full_run_using(&snapshot.tree,&exclusions,None,Some(&mut|meta,rows,_,_|{
   let name=meta.name;
   assert!(observed.insert(name.to_owned()),"actual producer must be observed once");
   match (name,rows){
    ("scheduler",UnionRows::Raw(rows))=>{let mut sites=0;let mut allows=0;for file in rows{sites+=file.run.sites.len();allows+=file.allow_used.len();for index in 0..file.run.sites.len(){assert_eq!(file.site_text(index),Some("sleep(2)"));}}assert_eq!((sites,allows),(1,1));},
    ("notice_publisher",UnionRows::Tree(data))=>{assert_eq!(data.sites().len(),1);assert!(data.sites()[0].msg.contains("/datum/notice/unpublished"));assert_eq!(data.allow_used().len(),1);},
    ("report_in_catch",UnionRows::Tree(data))=>{assert!(data.sites().is_empty()&&data.allow_used().is_empty());},
    ("allow_annotations",UnionRows::Validation(data))=>assert!(data.sites.is_empty()),
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
  // Unported ImageDir cannot be inferred from its registry registration.
  let unsupported:Vec<_>=exclusions.iter().filter(|name|name.as_str()!="-image_dir_after_build").cloned().collect();
  let error=snapshot.with_native_allow_full_run_using(&snapshot.tree,&unsupported,None,Some(&mut|_,_,_,_|panic!("preflight cannot stage a partial selection")),|_,_,_|->io::Result<()>{panic!("unsupported producer cannot finish a union")}).unwrap_err();
  assert!(matches!(error,Failure::Unsupported(message)if message.contains("image_dir_after_build")));
 });
}

//! Actual PrepareQuery host -> producer union -> private stage -> caller output.
#[path="../../../shared/test_scratch.rs"]mod scratch;
#[path="../../../../analyze/fixtures/report_configuration.rs"]mod report_config;
use dmbc::{policy_request::{AnalysisContext,PolicyInputRequest,WorkspacePolicyRequest},request::Command,runner_host::BuildHost};
use dq_analyze::{captured_allow_annotations::{full_unused,Operation},captured_generator_budget::Budget};
use std::{io,path::Path};

fn put(root:&Path, relative:&str, text:&str) {
    let path=root.join(relative);
    std::fs::create_dir_all(path.parent().unwrap()).unwrap();
    std::fs::write(path,text).unwrap();
}

#[test]
fn selected_report_embedding_publishes_only_after_real_findings_and_unused_allow() {
    let root=scratch::dir("selected-report-embedding");
    let cache=scratch::dir("selected-report-embedding-cache");
    put(&root,"deepquarry.dme","#include \"code/probe.dm\"\n");
    put(&root,"code/probe.dm","/proc/scheduled_probe()\n    sleep(1) // ALLOW(scheduler): test scheduler usage across actual producer folds\n    sleep(2)\n");
    put(&root,"code/notices.dm","/proc/registration()\n    on_notice(/datum/notice/unpublished)\n");
    put(&root,"maps/stale.dm","/proc/stale()\n    return // ALLOW(scheduler): test genuinely unused annotation across roots\n");
    put(&root,"tools/ci/lint_scopes.toml",&report_config::with_overlay(""));
    let Command::Build(request)=dmbc::cli::parse(&["prepare-query".into(),root.join("deepquarry.dme").to_string_lossy().into_owned()]).unwrap() else { panic!("actual PrepareQuery") };
    let mut request=*request;
    request.no_cache=true;request.exact_inputs=true;request.progress_enabled=false;request.workers=1;
    request.engine_template=None;request.bootstrap_catalog=false;request.cache_root=Some(cache);
    request.policy_inputs=Some(PolicyInputRequest{
        analysis_context:Some(AnalysisContext::OriginalAnalyze0290),
        workspace:Some(WorkspacePolicyRequest{root:root.clone(),recursive_roots:vec![root.join("code"),root.join("maps")],configuration:root.join("tools/ci/lint_scopes.toml")}),
        ..Default::default()
    });
    let budget=Budget::new(1<<20).unwrap();
    let mut work=Operation{budget:&budget,poll:&||Ok(())};
    let all=full_unused::registered_full_selection(&[],&mut work).unwrap();
    let retained=["allow_annotations","notice_publisher","report_in_catch","scheduler"];
    let exclusions:Vec<_>=all.names().iter().filter(|name|!retained.contains(&name.as_str())).map(|name|format!("-{name}")).collect();
    let mut host=BuildHost::default();
    let mut diagnostics=Vec::new();let mut output=Vec::new();
    let clean=host.write_original_exclusions_report(request.clone(),&exclusions,&mut diagnostics,&mut output).unwrap();
    assert!(!clean);
    let text=String::from_utf8(output).unwrap();
    assert!(text.contains("/datum/notice/unpublished"),"{text}");
    assert!(text.contains("code/probe.dm:3") && !text.contains("code/probe.dm:2"),"{text}");
    assert!(text.contains("maps/stale.dm:2: ALLOW(scheduler) is unused"),"{text}");
    assert!(text.contains("allow annotations: 1 unused"),"{text}");
    assert!(text.ends_with("Ratchet lints failed: notice_publisher scheduler allow_annotations --unused\n"),"{text}");
    assert!(!root.join("deepquarry.dmb").exists());

    put(&root,"code/cooldown.dm",concat!(
        "/proc/cooldown_probe()\n",
        "    if(world.time > kept_tick) // ALLOW(cooldown): test genuine use in the staged report join\n",
        "        return\n",
        "    if(world.time > next_tick)\n",
        "        return\n",
    ));
    let with_cooldown:Vec<_>=exclusions.iter().filter(|name|name.as_str()!="-cooldown").cloned().collect();
    let mut cooldown_output=Vec::new();
    let clean=host.write_original_exclusions_report(request.clone(),&with_cooldown,&mut diagnostics,&mut cooldown_output).unwrap();
    assert!(!clean);
    let cooldown_text=String::from_utf8(cooldown_output).unwrap();
    let exact_cooldown=concat!(
        "cooldown: raw_compare 1 FAIL\n",
        "code/cooldown.dm:4: [cooldown/raw_compare] if(world.time > next_tick)",
        " -- use COOLDOWN_START/COOLDOWN_FINISHED (code/defines/engine/cooldowns.dm) or om_after()\n",
    );
    assert!(cooldown_text.contains(exact_cooldown),"{cooldown_text}");
    assert!(!cooldown_text.contains("code/cooldown.dm:2"),"the actual use suppresses the row and is not unused: {cooldown_text}");
    assert!(cooldown_text.contains("allow annotations: 1 unused"),"{cooldown_text}");
    assert!(cooldown_text.ends_with("Ratchet lints failed: cooldown notice_publisher scheduler allow_annotations --unused\n"),"{cooldown_text}");

    let unsupported:Vec<_>=exclusions.iter().filter(|name|name.as_str()!="-image_dir_after_build").cloned().collect();
    let mut denied=Vec::new();let mut denied_diagnostics=Vec::new();
    let error=host.write_original_exclusions_report(request.clone(),&unsupported,&mut denied_diagnostics,&mut denied).unwrap_err();
    assert_eq!(error.downcast_ref::<io::Error>().map(io::Error::kind),Some(io::ErrorKind::Unsupported));
    assert!(denied.is_empty() && denied_diagnostics.is_empty());
    std::fs::remove_file(root.join("tools/ci/lint_scopes.toml")).unwrap();
    assert!(host.write_original_exclusions_report(request,&exclusions,&mut denied_diagnostics,&mut denied).is_err());
    assert!(denied.is_empty() && denied_diagnostics.is_empty(),"missing required report configuration cannot publish a prefix");

}

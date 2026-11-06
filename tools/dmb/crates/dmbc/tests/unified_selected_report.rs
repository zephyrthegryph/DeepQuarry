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

#[test]
fn selected_silicon_matches_hidden_map_actor_domain_without_enabling_map_raw_rules() {
    use dmbc::policy_request::WorkspaceAuxiliaryQuestion as Q;
    let root = scratch::dir("selected-silicon-actors");
    let cache = scratch::dir("selected-silicon-actors-cache");
    put(&root, "deepquarry.dme", concat!(
        "#include \"code/probe.dm\"\n",
        "#include \"maps/.actor.dm\"\n",
        "#include \"maps/allowed.dm\"\n",
    ));
    put(&root, "code/probe.dm", concat!(
        "#define isAI(A) istype(A, /mob/living/silicon/ai)\n",
        "/datum/act\n",
        "    var/actor\n",
        "/datum/act/op\n",
        "/mob/living/silicon/ai\n",
        "/obj/machinery\n",
        "    var/is_ai_remote_interface = 1\n",
    ));
    put(&root, "maps/.actor.dm", concat!(
        "/obj/machinery/proc/hidden_actor(datum/act/op/A)\n",
        "    return isAI(A.actor)\n",
    ));
    put(&root, "maps/allowed.dm", concat!(
        "/obj/machinery/proc/allowed_actor(datum/act/op/A)\n",
        "    return isAI(A.actor) // ALLOW(silicon_entry): this fixture exercises real actor ALLOW consumption\n",
        "/datum/map_only\n",
        "    var/is_ai_remote_interface = 1\n",
        "    var/unused // ALLOW(scheduler): this fixture exercises the selected unused audit\n",
    ));
    put(&root, "tools/ci/lint_scopes.toml", &report_config::with_overlay(""));
    let Command::Build(request) = dmbc::cli::parse(&["prepare-query".into(), root.join("deepquarry.dme").to_string_lossy().into_owned()]).unwrap()
    else { panic!("actual PrepareQuery") };
    let mut request = *request;
    request.no_cache = true;
    request.exact_inputs = true;
    request.progress_enabled = false;
    request.workers = 1;
    request.engine_template = None;
    request.bootstrap_catalog = false;
    request.cache_root = Some(cache);
    request.policy_inputs = Some(PolicyInputRequest {
        analysis_context: Some(AnalysisContext::OriginalAnalyze0290),
        workspace: Some(WorkspacePolicyRequest {
            root: root.clone(),
            recursive_roots: vec![root.join("code"), root.join("maps")],
            configuration: root.join("tools/ci/lint_scopes.toml"),
        }),
        ..Default::default()
    });
    let budget = Budget::new(1 << 20).unwrap();
    let mut work = Operation { budget: &budget, poll: &|| Ok(()) };
    let all = full_unused::registered_full_selection(&[], &mut work).unwrap();
    let selected = ["allow_annotations", "cooldown", "notice_publisher", "report_in_catch", "scheduler", "silicon_entry"];
    let exclusions: Vec<_> = all.names().iter().filter(|name| !selected.contains(&name.as_str())).map(|name| format!("-{name}")).collect();
    let mut host = BuildHost::default();
    let mut diagnostics = Vec::new();
    let mut output = Vec::new();
    assert!(!host.write_original_exclusions_report(request.clone(), &exclusions, &mut diagnostics, &mut output).unwrap());
    let text = std::str::from_utf8(&output).unwrap();
    assert!(text.contains("maps/.actor.dm:2: [silicon_entry/handler_actor_check]"), "{text}");
    assert!(text.contains("code/probe.dm:7: [silicon_entry/shortcut]"), "{text}");
    assert!(!text.contains("maps/allowed.dm:2") && !text.contains("maps/allowed.dm:4"), "{text}");
    assert!(text.contains("ALLOW(scheduler): 1 annotation, but no lint run used any:") && text.contains("allow annotations: 1 unused"), "{text}");
    assert!(text.ends_with("Ratchet lints failed: silicon_entry allow_annotations --unused\n"), "{text}");

    let mut warm = Vec::new();
    let mut warm_diagnostics = Vec::new();
    assert!(!host.write_original_exclusions_report(request.clone(), &exclusions, &mut warm_diagnostics, &mut warm).unwrap());
    assert_eq!(warm, output);
    assert_eq!(warm_diagnostics, diagnostics);

    let mut denied = Vec::new();
    let mut denied_diagnostics = Vec::new();
    request.policy_inputs.as_mut().unwrap().workspace_auxiliary = vec![Q::SiliconEntry];
    assert!(host.write_original_exclusions_report(request, &exclusions, &mut denied_diagnostics, &mut denied).is_err());
    assert!(denied.is_empty() && denied_diagnostics.is_empty());
}

//! Small actual in-process public BuildHost coverage for the Sys semantic role.
//! This does NOT claim private guards/Kind12/foreign-Db/report-writer tests ran.
//! No daemon, game world, GUI, alternate parser or visibility widening.
#[path="../../../shared/test_scratch.rs"]mod scratch;
#[path="../../../../analyze/fixtures/report_configuration.rs"]mod report_configuration;
#[path="../../../../analyze/fixtures/native-sys-reactive/fixture.rs"]mod sys_reactive_fixture;
use dmbc::{policy_request::{AnalysisContext,PolicyInputRequest,WorkspacePolicyRequest,WorkspaceAuxiliaryQuestion as Q},request::{BuildRequest,BuildOutcome,Command},runner_host::BuildHost};
use std::path::{Path,PathBuf};
fn put(root:&Path,relative:&str,bytes:impl AsRef<[u8]>){let path=root.join(relative);std::fs::create_dir_all(path.parent().unwrap()).unwrap();std::fs::write(path,bytes).unwrap();}
fn fixture(label:&str)->PathBuf{let root=scratch::dir(label);std::fs::create_dir(root.join("maps")).unwrap();put(&root,"deepquarry.dme","#include \"code/probe.dm\"\n");put(&root,"code/probe.dm","/datum/look\n/datum/probe\n    var/power\n    var/datum/probe/cell\n/datum/probe/proc/draw(datum/look/look)\n    return cell.power\n");put(&root,"tools/ci/lint_scopes.toml",report_configuration::with_overlay(""));root}
fn request(root:&Path)->BuildRequest{let Command::Build(request)=dmbc::cli::parse(&["prepare-query".into(),root.join("deepquarry.dme").to_string_lossy().into_owned()]).unwrap()else{panic!("actual public PrepareQuery parser")};let mut request=*request;request.no_cache=true;request.exact_inputs=true;request.progress_enabled=false;request.workers=1;request.timeout_seconds=Some(60);request.engine_template=None;request.bootstrap_catalog=false;request.cache_root=Some(root.join("cache"));request.policy_inputs=Some(PolicyInputRequest{analysis_context:Some(AnalysisContext::OriginalAnalyze0290),workspace:Some(WorkspacePolicyRequest{root:root.to_owned(),recursive_roots:vec![root.join("code"),root.join("maps")],configuration:root.join("tools/ci/lint_scopes.toml")}),workspace_auxiliary:vec![Q::SysReactive],..Default::default()});request}
#[derive(Debug,Eq,PartialEq)]struct Pins{semantic:String,source:String,policy:String}
fn prepare(host:&mut BuildHost,request:&BuildRequest)->Pins{let outcome=dmbc::request_runner::run_build_with_host(request.clone(),host).unwrap();let BuildOutcome::QueryPrepared{semantic_revision,source_revision,policy_revision:Some(policy_revision),retained:true}=outcome else{panic!("actual Sys semantic model owner required; raw/empty substitute forbidden: {outcome:?}")};for value in [&semantic_revision,&source_revision,&policy_revision]{assert_eq!(value.len(),32);assert!(value.bytes().all(|byte|byte.is_ascii_hexdigit()));}assert!(host.declaration_retention_stats().is_some(),"semantic question needs genuine declaration owner");assert!(host.symbolic_retention_stats().is_none(),"PrepareQuery cannot silently lower executable code");assert!(!request.project.with_extension("dmb").exists());assert!(!request.project.with_extension("rsc").exists());Pins{semantic:semantic_revision,source:source_revision,policy:policy_revision}}
#[test]
fn selected_sys_reactive_reports_actual_map_sites_and_rechecks_scope() {
    use dq_analyze::{captured_allow_annotations::{full_unused, Operation}, captured_generator_budget::Budget, selected_exclusions_wire::Roster};

    let root = scratch::dir("public-selected-sys-reactive");
    assert!(sys_reactive_fixture::CASES.contains(&"maps"));
    for (relative, source) in sys_reactive_fixture::files("maps") {
        put(&root, &relative, source);
    }
    let mut selected = request(&root);
    selected.cache_root = Some(scratch::dir("public-selected-sys-cache"));
    selected.policy_inputs.as_mut().unwrap().workspace_auxiliary.clear();
    let budget = Budget::new(1 << 20).unwrap();
    let mut work = Operation { budget: &budget, poll: &|| Ok(()) };
    let all = full_unused::registered_full_selection(&[], &mut work).unwrap();
    let exclusions: Vec<_> = all.names().iter()
        .filter(|name| !Roster::WithSysReactive.names().contains(&name.as_str()))
        .map(|name| format!("-{name}")).collect();
    let mut host = BuildHost::default();
    let mut run = || {
        let mut output = Vec::new();
        let clean = host.write_original_exclusions_report(
            selected.clone(), &exclusions, &mut Vec::new(), &mut output,
        ).unwrap();
        (clean, String::from_utf8(output).unwrap())
    };
    let (clean, cold) = run();
    assert!(!clean);
    for rule in ["dx_untracked_read", "dx_reactive_write", "dx_caps_instance_read", "dx_timed_write"] {
        assert!(cold.contains(&format!("[sys/dx_reactive/{rule}]")), "{rule}: {cold}");
    }
    assert!(cold.contains("maps/probe.dm:"));
    assert_eq!(run(), (clean, cold));

    put(&root, "tools/ci/lint_scopes.toml", report_configuration::with_overlay(
        "[lint.\"sys/dx_reactive\"]\nexempt_files=[\"maps/probe.dm\"]\n",
    ));
    let (clean, exempt) = run();
    assert!(clean, "{exempt}");
    assert!(!exempt.contains("maps/probe.dm:"));
    assert!(exempt.contains("sys/dx_reactive: dx_untracked_read 0 OK"));
}


#[test]
fn selected_lifeforms_reports_actual_constructor_and_position_findings() {
    use dq_analyze::{captured_allow_annotations::{full_unused, Operation}, captured_generator_budget::Budget, selected_exclusions_wire::Roster};

    let root = fixture("public-selected-lifeforms");
    // Minimal existing Lifeforms oracle shapes: a dead explicit constructor
    // argument and a position override with no corresponding ancestor entry.
    put(&root, "code/probe.dm", concat!(
        "#define CAPABILITIES(...)\n#define nameof(V) #V\n",
        "/obj/no_reader\n/obj/bad_position\n    var/value\n",
        "CAPABILITIES(/obj/bad_position, param(nameof(value), pos = 3, overrides = TRUE))\n",
        "/proc/probe(loc)\n    new /obj/no_reader(loc, 2)\n",
    ));
    let mut selected = request(&root);
    selected.cache_root = Some(scratch::dir("public-selected-lifeforms-cache"));
    selected.policy_inputs.as_mut().unwrap().workspace_auxiliary.clear();
    let budget = Budget::new(1 << 20).unwrap();
    let mut work = Operation { budget: &budget, poll: &|| Ok(()) };
    let all = full_unused::registered_full_selection(&[], &mut work).unwrap();
    let exclusions: Vec<_> = all.names().iter()
        .filter(|name| !Roster::WithLifeforms.names().contains(&name.as_str()))
        .map(|name| format!("-{name}")).collect();
    let mut host = BuildHost::default();
    let mut run = || {
        let mut output = Vec::new();
        let clean = host.write_original_exclusions_report(
            selected.clone(), &exclusions, &mut Vec::new(), &mut output,
        ).unwrap();
        (clean, String::from_utf8(output).unwrap())
    };
    let (clean, cold) = run();
    assert!(!clean);
    assert!(cold.contains("[lifeforms/ctor_dead_arg]"), "{cold}");
    assert!(cold.contains("[lifeforms/param_overrides_nothing]"), "{cold}");
    assert!(cold.contains("overrides no ancestor's position"), "{cold}");
    assert!(cold.contains("code/probe.dm:"), "{cold}");
    assert!(cold.contains("allow annotations: 0 unused"), "{cold}");
    assert_eq!(run(), (clean, cold));

    put(&root, "tools/ci/lint_scopes.toml", report_configuration::with_overlay(
        "[lint.lifeforms]\nexempt_files=[\"code/probe.dm\"]\n",
    ));
    let (clean, exempt) = run();
    assert!(clean, "{exempt}");
    assert!(!exempt.contains("[lifeforms/ctor_dead_arg]"));
    assert!(!exempt.contains("[lifeforms/param_overrides_nothing]"));

    let mut diagnostics = Vec::new();
    let mut checker = Vec::new();
    let mut analyze = Vec::new();
    assert!(host.write_combined_selected_original_reports(
        selected.clone(), &exclusions, &mut diagnostics, &mut checker, &mut analyze,
    ).is_err());
    assert!(diagnostics.is_empty() && checker.is_empty() && analyze.is_empty());
    let unsupported: Vec<_> = exclusions.iter().filter(|name| name.as_str() != "-cooldown").cloned().collect();
    assert!(host.write_original_exclusions_report(selected, &unsupported, &mut diagnostics, &mut analyze).is_err());
    assert!(diagnostics.is_empty() && analyze.is_empty());
}


#[test]
fn selected_player_link_reports_actual_typed_and_map_body_writes() {
    use dq_analyze::{captured_allow_annotations::{full_unused, Operation}, captured_generator_budget::Budget, selected_exclusions_wire::Roster};

    let root = fixture("public-selected-player-link");
    put(&root, "deepquarry.dme", "#include \"code/probe.dm\"\n#include \"maps/player.dm\"\n");
    put(&root, "code/probe.dm", concat!(
        "/mob/player_child\n",
        "/proc/probe(mob/P)\n    P.key = 1\n",
    ));
    put(&root, "maps/player.dm", "/mob/player_child/proc/map_check()\n    key = 42\n");
    let mut selected = request(&root);
    selected.cache_root = Some(scratch::dir("public-selected-player-link-cache"));
    selected.policy_inputs.as_mut().unwrap().workspace_auxiliary.clear();
    let budget = Budget::new(1 << 20).unwrap();
    let mut work = Operation { budget: &budget, poll: &|| Ok(()) };
    let all = full_unused::registered_full_selection(&[], &mut work).unwrap();
    let exclusions: Vec<_> = all.names().iter()
        .filter(|name| !Roster::WithPlayerLink.names().contains(&name.as_str()))
        .map(|name| format!("-{name}")).collect();
    let mut host = BuildHost::default();
    let mut run = || {
        let mut output = Vec::new();
        let clean = host.write_original_exclusions_report(
            selected.clone(), &exclusions, &mut Vec::new(), &mut output,
        ).unwrap();
        (clean, String::from_utf8(output).unwrap())
    };
    let (clean, cold) = run();
    assert!(!clean);
    assert_eq!(cold.matches("[player_link/raw_key]").count(), 2, "{cold}");
    assert!(cold.contains("code/probe.dm:3: [player_link/raw_key]"), "{cold}");
    assert!(cold.contains("maps/player.dm:2: [player_link/raw_key]"), "{cold}");
    assert_eq!(cold.matches(dq_analyze::player_link_policy::MESSAGE).count(), 2, "{cold}");
    assert!(cold.contains("allow annotations: 0 unused"), "{cold}");
    assert_eq!(run(), (clean, cold));

    put(&root, "tools/ci/lint_scopes.toml", report_configuration::with_overlay(
        "[lint.player_link]\nexempt_prefixes=[\"code/\",\"maps/\"]\n",
    ));
    let (clean, exempt) = run();
    assert!(clean, "{exempt}");
    assert!(!exempt.contains("[player_link/raw_key]"));

    let unsupported: Vec<_> = exclusions.iter().filter(|name| name.as_str() != "-cooldown").cloned().collect();
    let mut diagnostics = Vec::new();
    let mut analyze = Vec::new();
    assert!(host.write_original_exclusions_report(selected, &unsupported, &mut diagnostics, &mut analyze).is_err());
    assert!(diagnostics.is_empty() && analyze.is_empty());
}

fn policy_or_source_changed(a:&Pins,b:&Pins){assert!(a.source!=b.source||a.policy!=b.policy,"actual raw discovery/configuration change must reissue public source/policy pins: {a:?}");}
#[test]fn actual_public_sys_role_prepares_real_model_and_refuses_missing_analysis_context(){let root=fixture("public-sys-original-model");let request=request(&root);let mut host=BuildHost::default();let first=prepare(&mut host,&request);assert_eq!(prepare(&mut host,&request),first);let mut missing=request.clone();missing.policy_inputs.as_mut().unwrap().analysis_context=None;assert!(dmbc::request_runner::run_build_with_host(missing,&mut host).is_err(),"semantic role cannot become a context-free raw-only grant");prepare(&mut host,&request);}
#[test]fn actual_public_sys_uncompiled_auto_and_config_observations_reissue_same_host(){let root=fixture("public-sys-full-source-revisions");let request=request(&root);let mut host=BuildHost::default();let first=prepare(&mut host,&request);put(&root,"code/uncompiled.dm","/datum/uncompiled_raw\n");let added=prepare(&mut host,&request);policy_or_source_changed(&first,&added);put(&root,"code/engine/_generated/auto_tracked.dm","// actual AUTO exists without explicit TRACKED entries\n");let auto=prepare(&mut host,&request);policy_or_source_changed(&added,&auto);std::fs::remove_file(root.join("code/engine/_generated/auto_tracked.dm")).unwrap();let removed=prepare(&mut host,&request);policy_or_source_changed(&auto,&removed);put(&root,"tools/ci/lint_scopes.toml",report_configuration::with_overlay("[lint.\"sys/dx_reactive\"]\nexempt_files=[\"code/probe.dm\"]\n"));let configured=prepare(&mut host,&request);assert_ne!(configured.policy,removed.policy);}
#[test]fn actual_public_sys_required_manifest_io_refuses_then_fresh_valid_input_recovers(){let root=fixture("public-sys-required-model-failure");let request=request(&root);let mut host=BuildHost::default();prepare(&mut host,&request);std::fs::remove_file(&request.project).unwrap();std::fs::create_dir(&request.project).unwrap();assert!(dmbc::request_runner::run_build_with_host(request.clone(),&mut host).is_err(),"actual required model acquisition IO cannot be treated as an authenticated absent model or clean raw result");std::fs::remove_dir(&request.project).unwrap();put(&root,"deepquarry.dme","#include \"code/probe.dm\"\n");prepare(&mut host,&request);}

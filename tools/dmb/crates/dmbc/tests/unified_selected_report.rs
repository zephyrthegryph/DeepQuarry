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

#[test]
fn selected_library_layers_share_the_capture_for_live_and_empty_scope() {
    use dq_analyze::selected_exclusions_wire::Roster;

    let root = scratch::dir("selected-library-layers");
    let cache = scratch::dir("selected-library-cache");
    std::fs::create_dir(root.join("maps")).unwrap();
    put(&root, "deepquarry.dme", concat!(
        "#include \"code/library/current.dm\"\n",
        "#include \"code/content/definition.dm\"\n",
    ));
    put(&root, "code/library/current.dm", "/proc/use_content()\n    downstream()\n");
    put(&root, "code/content/definition.dm", "/proc/downstream()\n    return\n");
    put(&root, "code/scheduler_usage.dm", concat!(
        "/proc/scheduler_use()\n",
        "    sleep(1) // ALLOW(scheduler): exercises actual selected report annotation consumption\n",
    ));

    let Command::Build(request) = dmbc::cli::parse(&[
        "prepare-query".into(), root.join("deepquarry.dme").to_string_lossy().into_owned(),
    ]).unwrap() else { panic!("actual PrepareQuery") };
    let mut request = *request;
    request.no_cache = true;
    request.exact_inputs = true;
    request.progress_enabled = false;
    request.workers = 1;
    request.engine_template = None;
    request.bootstrap_catalog = false;
    request.cache_root = Some(cache);
    request.timeout_seconds = Some(30);
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
    let wanted = Roster::WithLibraryLayering.names();
    let exclusions: Vec<_> = all.names().iter().filter(|name| !wanted.contains(&name.as_str()))
        .map(|name| format!("-{name}")).collect();
    let mut host = BuildHost::default();
    for (exempt, overlay) in [
        (false, ""),
        (true, "[lint.library_layering]\nexempt_files=[\"code/library/current.dm\"]\n"),
    ] {
        put(&root, "tools/ci/lint_scopes.toml", &report_config::with_overlay(overlay));
        let (mut diagnostics, mut output) = (Vec::new(), Vec::new());
        let clean = host.write_original_exclusions_report(request.clone(), &exclusions, &mut diagnostics, &mut output).unwrap();
        let report = String::from_utf8(output).unwrap();
        assert_eq!(clean, exempt, "{report}");
        assert_eq!(
            report.contains("code/library/current.dm:2: [library_layering/external_dependency] downstream()"),
            !exempt,
            "{report}"
        );
        assert!(report.contains("library_layering") && report.contains("allow annotations: 0 unused"), "{report}");
    }
    assert!(!root.join("deepquarry.dmb").exists());
}

#[test]
fn selected_handlers_pairs_real_partitions_and_uses_map_allows() {
    use dq_analyze::selected_exclusions_wire::Roster;
    let root = scratch::dir("selected-handlers-whole");
    let cache = scratch::dir("selected-handlers-cache");
    let manifest = concat!(
        "#warn selected_handlers_full_notice\n",
        "#include \"code/__defines/context.dm\"\n",
        "#include \"code/structural.dm\"\n",
        "#include \"code/handler.dm\"\n",
        "#include \"code/engine/present/protocols.dm\"\n",
        "#include \"maps/allowed.dm\"\n",
        "#include \"maps/.override.dm\"\n",
    );
    put(&root, "deepquarry.dme", manifest);
    put(&root, "tools/ci/lint_scopes.toml", &report_config::with_overlay(""));
    put(&root, "code/__defines/context.dm", "#define CAPABILITIES(...)\n#define PROC_REF(P) #P\n/datum/act\n/datum/act/eval\n/obj/probe\n");
    put(&root, "code/structural.dm", "/proc/leak(datum/act/A)\n    return list(A)\n/proc/allowed(datum/act/A)\n    return list(A) // ALLOW(handlers): test genuine structural annotation usage\n");
    put(&root, "code/partial_only.dm", "#warn selected_handlers_partial_notice\n/proc/partial_candidate(datum/act/A)\n    return\n");
    put(&root, "code/handler.dm", "/obj/probe/proc/handler(datum/act/eval/A)\n    return 2\nCAPABILITIES(/obj/probe,when(PROC_REF(handler)))\n");
    put(&root, "code/engine/present/protocols.dm", "/datum/look\n/atom/proc/draw(datum/look/look)\n    return\n");
    put(&root, "maps/allowed.dm", "/obj/bad/draw(extra,datum/look/look) // ALLOW(handlers): test genuine map output annotation usage\n    return\n");
    put(&root, "maps/.override.dm", "/obj/other_bad/draw(extra,datum/look/look)\n    return\n");
    put(&root, "maps/unused.dm", "/datum/unused // ALLOW(scheduler): test independent unused audit across roots\n");
    put(&root, "code/scheduler.dm", "/proc/scheduled_probe()\n    sleep(1) // ALLOW(scheduler): test scheduler usage across actual producer folds\n");
    let Command::Build(request) = dmbc::cli::parse(&["prepare-query".into(), root.join("deepquarry.dme").to_string_lossy().into_owned()]).unwrap()
    else { panic!("actual PrepareQuery") };
    let mut request = *request;
    request.no_cache = true;
    request.exact_inputs = true;
    request.progress_enabled = false;
    request.workers = 1;
    request.timeout_seconds = Some(60);
    request.engine_template = None;
    request.bootstrap_catalog = false;
    request.cache_root = Some(cache);
    request.policy_inputs = Some(PolicyInputRequest {
        analysis_context: Some(AnalysisContext::OriginalAnalyze0290),
        workspace: Some(WorkspacePolicyRequest {
            root: root.clone(), recursive_roots: vec![root.join("code"), root.join("maps")],
            configuration: root.join("tools/ci/lint_scopes.toml"),
        }), ..Default::default()
    });
    let budget = Budget::new(1 << 20).unwrap();
    let mut work = Operation { budget: &budget, poll: &|| Ok(()) };
    let all = full_unused::registered_full_selection(&[], &mut work).unwrap();
    let exclusions: Vec<_> = all.names().iter().filter(|name| !Roster::WithHandlers.names().contains(&name.as_str())).map(|name| format!("-{name}")).collect();
    let mut host = BuildHost::default();
    let mut diagnostics = Vec::new();
    let mut output = Vec::new();
    assert!(!host.write_original_exclusions_report(request.clone(), &exclusions, &mut diagnostics, &mut output).unwrap());
    let text = std::str::from_utf8(&output).unwrap();
    assert!(text.contains("code/structural.dm:2: [handlers/context_escape]"), "{text}");
    assert!(text.contains("[handlers/requirement_return]"), "{text}");
    assert!(text.contains("maps/.override.dm:1: [handlers/output_signature]"), "{text}");
    assert!(!text.contains("maps/allowed.dm:") && !text.contains("code/structural.dm:4"), "{text}");
    assert!(text.contains("maps/unused.dm:1: ALLOW(scheduler) is unused"), "{text}");
    assert!(text.ends_with("Ratchet lints failed: sem/handlers allow_annotations --unused\n"), "{text}");
    if let Some(oracle) = std::env::var_os("DQ_SELECTED_HANDLERS_ORACLE") {
        let oracle = std::path::PathBuf::from(oracle);
        assert!(oracle.is_absolute(), "oracle executable path must be absolute");
        let native = root.join("selected-handlers-verified-report.txt");
        std::fs::write(&native, &output).unwrap();
        let mut command = std::process::Command::new(oracle);
        command.arg(&root).arg(native);
        #[cfg(windows)] {
            use std::os::windows::process::CommandExt;
            const CREATE_NO_WINDOW: u32 = 0x08000000;
            const BELOW_NORMAL_PRIORITY_CLASS: u32 = 0x00004000;
            command.creation_flags(CREATE_NO_WINDOW | BELOW_NORMAL_PRIORITY_CLASS);
        }
        let checked = command.output().expect("run the frozen legacy handler/ALLOW oracle");
        assert!(checked.status.success(), "legacy comparison failed: {}\n{}",
            String::from_utf8_lossy(&checked.stdout), String::from_utf8_lossy(&checked.stderr));
    }
    let notices = std::str::from_utf8(&diagnostics).unwrap();
    let partial = "selected_handlers_partial_notice";
    let full = "selected_handlers_full_notice";
    assert_eq!(notices.matches(partial).count(), 1, "{notices}");
    assert_eq!(notices.matches(full).count(), 1, "{notices}");
    assert!(notices.find(partial).unwrap() < notices.find(full).unwrap(), "{notices}");

    let mut warm_out = Vec::new();
    let mut warm_err = Vec::new();
    assert!(!host.write_original_exclusions_report(request.clone(), &exclusions, &mut warm_err, &mut warm_out).unwrap());
    assert_eq!((warm_out, warm_err), (output, diagnostics));

    let mut denied_out = Vec::new();
    let mut denied_err = Vec::new();
    // A missing include is recoverable in Original Analyze. An unclosed
    // formal default in the authored DME prevents the full model from issuing.
    put(&root, "deepquarry.dme", &format!("{manifest}/proc/fatal(var/A=)\n"));
    let failed = host.write_original_exclusions_report(request.clone(), &exclusions, &mut denied_err, &mut denied_out).unwrap_err();
    assert_eq!(failed.downcast_ref::<io::Error>().map(io::Error::kind), Some(io::ErrorKind::InvalidInput));
    assert!(failed.to_string().contains("query role differs from actual complete/prefix native preparation"), "{failed:?}");
    assert!(denied_out.is_empty() && denied_err.is_empty());
    put(&root, "deepquarry.dme", "#include \"code/__defines/context.dm\"\n#include \"code/structural.dm\"\n");
    put(&root, "code/handler.dm", "/obj/ordinary\n");
    put(&root, "code/engine/present/protocols.dm", "/datum/look\n");
    let error = host.write_original_exclusions_report(request, &exclusions, &mut denied_err, &mut denied_out).unwrap_err();
    assert_eq!(error.downcast_ref::<io::Error>().map(io::Error::kind), Some(io::ErrorKind::Unsupported));
    assert!(denied_out.is_empty() && denied_err.is_empty());
    assert!(!root.join("deepquarry.dmb").exists());
}

#[path="../../../../analyze/fixtures/native-sem-reads/fixture.rs"]
mod semantic_read_fixture;

#[test]
fn selected_semantic_reads_use_map_allows_without_expanding_code_markers() {
    use dq_analyze::selected_exclusions_wire::Roster;
    let root = scratch::dir("selected-semantic-reads");
    let cache = scratch::dir("selected-semantic-reads-cache");
    let mut manifest = String::new();
    for (relative, bytes) in semantic_read_fixture::files("basic").unwrap() {
        let mut source = String::from_utf8(bytes).unwrap();
        match relative.as_str() {
            "deepquarry.dme" => {
                manifest = source;
                continue;
            }
            "code/modules/apc/apc.dm" => {
                let declaration = "\twhen(PROC_REF(dynamic)),";
                assert!(source.contains(declaration));
                source = source.replace(declaration, &format!("{declaration}\n\twhen(PROC_REF(dynamic_unkept)),"));
                let body = "/obj/machinery/apc/proc/dynamic(datum/act/eval/A)\n\treturn vars[\"on\"]\n";
                assert!(source.contains(body));
                source = source.replace(body, "");
            }
            _ => (),
        }
        put(&root, &relative, &source);
    }
    const KEPT: &str = "maps/.read_kept.dm";
    const UNKEPT: &str = "maps/read_unkept.dm";
    const READING: &str = "/obj/machinery/apc/proc/dynamic(datum/act/eval/A)\n    return vars[\"on\"]";
    put(&root, KEPT, &format!("{READING} // ALLOW(reads, untracked_inputs): deliberate map read retention witness\n"));
    put(&root, UNKEPT, "/obj/machinery/apc/proc/dynamic_unkept(datum/act/eval/A)\n    return vars[\"on\"]\n");
    put(&root, "maps/stale.dm", "/datum/stale // ALLOW(reads): deliberately unused selected map annotation witness\n");
    put(&root, "maps/not_compiled.dm", "PUBLISH_CHANGE(src, SECRET_KEY)
");
    manifest.push_str(&format!("#include \"{KEPT}\"\n#include \"{UNKEPT}\"\n"));
    put(&root, "deepquarry.dme", &manifest);
    put(&root, "tools/ci/lint_scopes.toml", &report_config::with_overlay(""));
    let Command::Build(request) = dmbc::cli::parse(&["prepare-query".into(), root.join("deepquarry.dme").to_string_lossy().into_owned()]).unwrap()
    else { panic!("actual PrepareQuery") };
    let mut request = *request;
    request.no_cache = true;
    request.exact_inputs = true;
    request.progress_enabled = false;
    request.workers = 1;
    request.timeout_seconds = Some(60);
    request.engine_template = None;
    request.bootstrap_catalog = false;
    request.cache_root = Some(cache);
    request.policy_inputs = Some(PolicyInputRequest {
        analysis_context: Some(AnalysisContext::OriginalAnalyze0290),
        workspace: Some(WorkspacePolicyRequest {
            root: root.clone(), recursive_roots: vec![root.join("code"), root.join("maps")],
            configuration: root.join("tools/ci/lint_scopes.toml"),
        }), ..Default::default()
    });
    let budget = Budget::new(1 << 20).unwrap();
    let mut work = Operation { budget: &budget, poll: &|| Ok(()) };
    let all = full_unused::registered_full_selection(&[], &mut work).unwrap();
    let exclusions: Vec<_> = all.names().iter().filter(|name| !Roster::WithSemanticReads.names().contains(&name.as_str()))
        .map(|name| format!("-{name}")).collect();
    let run = |host:&mut BuildHost| {
        let mut diagnostics = Vec::new();
        let mut output = Vec::new();
        assert!(!host.write_original_exclusions_report(request.clone(), &exclusions, &mut diagnostics, &mut output).unwrap());
        (output, diagnostics)
    };
    let compare = |output:&[u8], expected:&str| {
        let Some(oracle) = std::env::var_os("DQ_SELECTED_READS_ORACLE") else { return; };
        let oracle = std::path::PathBuf::from(oracle);
        assert!(oracle.is_absolute());
        let native = root.join("selected-reads-verified-report.txt");
        std::fs::write(&native, output).unwrap();
        let mut command = std::process::Command::new(oracle);
        command.arg(&root).arg(native).arg(expected);
        #[cfg(windows)] {
            use std::os::windows::process::CommandExt;
            const CREATE_NO_WINDOW: u32 = 0x08000000;
            const BELOW_NORMAL_PRIORITY_CLASS: u32 = 0x00004000;
            command.creation_flags(CREATE_NO_WINDOW | BELOW_NORMAL_PRIORITY_CLASS);
        }
        let checked = command.output().expect("run frozen legacy read policy oracle");
        assert!(checked.status.success(), "legacy comparison failed: {}\n{}",
            String::from_utf8_lossy(&checked.stdout), String::from_utf8_lossy(&checked.stderr));
    };
    let mut host = BuildHost::default();
    let initial = run(&mut host);
    let text = std::str::from_utf8(&initial.0).unwrap();
    assert!(text.contains("maps/read_unkept.dm:2: [reads/dynamic_read]"), "{text}");
    assert!(text.contains("maps/read_unkept.dm:2: [untracked_inputs/stat_input_untracked]"), "{text}");
    assert!(!text.contains("maps/.read_kept.dm:2:"), "{text}");
    assert!(text.contains("[reads/reads_as_uncovered]") && text.contains("SECRET_KEY"), "{text}");
    assert!(text.contains("maps/stale.dm:1: ALLOW(reads) is unused"), "{text}");
    compare(&initial.0, "kept");
    assert_eq!(run(&mut host), initial);

    put(&root, KEPT, &format!("{READING}\n"));
    let changed = run(&mut host);
    let text = std::str::from_utf8(&changed.0).unwrap();
    assert!(text.contains("maps/.read_kept.dm:2: [reads/dynamic_read]"), "{text}");
    assert!(text.contains("maps/.read_kept.dm:2: [untracked_inputs/stat_input_untracked]"), "{text}");
    compare(&changed.0, "unkept");
    drop(host);
    assert_eq!(run(&mut BuildHost::default()), changed);
    assert!(!root.join("deepquarry.dmb").exists());
}

#[test]
fn selected_setter_matches_old_tree_header_membership() {
    use dq_analyze::selected_exclusions_wire::Roster;
    let root = scratch::dir("selected-setter-membership");
    let cache = scratch::dir("selected-setter-cache");
    let config = concat!(
        "[lint.auto_tracked.lists]\n",
        "include=[\"/datum/probe::charge\", \"/datum/map_probe::map_charge\", ",
        "\"/datum/hidden_probe::hidden_charge\", \"/datum/outside_probe::outside_charge\"]\n",
    );
    put(&root,"tools/ci/lint_scopes.toml",&report_config::with_overlay(config));
    put(&root,"code/probe.dm",concat!(
        "#define SETTER(T,V)\n",
        "#define TRACKED_STATE(T,V) ##T/proc/set_##V(value) { V = value }\n",
        "/datum/probe\n    var/charge\n",
        "SETTER(/datum/probe, charge)\n",
        "/datum/probe/proc/set_charge(value)\n    charge = value\n",
        "/datum/map_probe\n    var/map_charge\n",
        "/datum/hidden_probe\n    var/hidden_charge\n",
        "/datum/outside_probe\n    var/outside_charge\n",
    ));
    put(&root,"maps/legacy_macro.dm","TRACKED_STATE(/datum/map_probe, map_charge)\n");
    put(&root,"maps/.legacy_macro.dm","TRACKED_STATE(/datum/hidden_probe, hidden_charge)\n");
    const OUTSIDE: &str = "interface/legacy_macro.dm";
    const ADMITTED: &str = "maps/moved_macro.dm";
    const BODY: &str = "TRACKED_STATE(/datum/outside_probe, outside_charge)\n";
    put(&root,OUTSIDE,BODY);
    let manifest = concat!(
        "#include \"code/probe.dm\"\n",
        "#include \"maps/legacy_macro.dm\"\n",
        "#include \"maps/.legacy_macro.dm\"\n",
    );
    put(&root,"deepquarry.dme",&format!("{manifest}#include \"{OUTSIDE}\"\n"));
    let Command::Build(request) = dmbc::cli::parse(&["prepare-query".into(), root.join("deepquarry.dme").to_string_lossy().into_owned()]).unwrap()
    else { panic!("actual PrepareQuery") };
    let mut request = *request;
    request.no_cache = true;
    request.exact_inputs = true;
    request.progress_enabled = false;
    request.workers = 1;
    request.timeout_seconds = Some(60);
    request.engine_template = None;
    request.bootstrap_catalog = false;
    request.cache_root = Some(cache);
    request.policy_inputs = Some(PolicyInputRequest {
        analysis_context: Some(AnalysisContext::OriginalAnalyze0290),
        workspace: Some(WorkspacePolicyRequest {
            root: root.clone(), recursive_roots: vec![root.join("code"), root.join("maps")],
            configuration: root.join("tools/ci/lint_scopes.toml"),
        }), ..Default::default()
    });
    let budget=Budget::new(1<<20).unwrap();
    let mut work=Operation{budget:&budget,poll:&||Ok(())};
    let all=full_unused::registered_full_selection(&[],&mut work).unwrap();
    let exclusions:Vec<_>=all.names().iter().filter(|name|!Roster::WithSetterPublishes.names().contains(&name.as_str()))
        .map(|name|format!("-{name}")).collect();
    let run=|host:&mut BuildHost|{
        let mut diagnostics=Vec::new();
        let mut output=Vec::new();
        assert!(!host.write_original_exclusions_report(request.clone(),&exclusions,&mut diagnostics,&mut output).unwrap());
        (output,diagnostics)
    };
    let compare=|output:&[u8],expected:&str|{
        let Some(oracle)=std::env::var_os("DQ_SELECTED_SETTER_ORACLE") else {return;};
        let oracle=std::path::PathBuf::from(oracle);
        assert!(oracle.is_absolute());
        let native=root.join("selected-setter-verified-report.txt");
        std::fs::write(&native,output).unwrap();
        let mut command=std::process::Command::new(oracle);
        command.arg(&root).arg(native).arg(expected);
        #[cfg(windows)] {
            use std::os::windows::process::CommandExt;
            command.creation_flags(0x08000000 | 0x00004000);
        }
        let checked=command.output().expect("run frozen legacy setter oracle");
        assert!(checked.status.success(),"legacy comparison failed: {}\n{}",
            String::from_utf8_lossy(&checked.stdout),String::from_utf8_lossy(&checked.stderr));
    };
    let mut host=BuildHost::default();
    let initial=run(&mut host);
    let text=std::str::from_utf8(&initial.0).unwrap();
    assert_eq!(text.matches("code/probe.dm:6: [setter_publishes/no_publish]").count(),2,"{text}");
    assert!(text.contains("interface/legacy_macro.dm:1: [setter_publishes/no_publish]"),"{text}");
    assert!(!text.contains("maps/legacy_macro.dm:") && !text.contains("maps/.legacy_macro.dm:"),"{text}");
    compare(&initial.0,"outside");
    assert_eq!(run(&mut host),initial);

    put(&root,ADMITTED,BODY);
    put(&root,"deepquarry.dme",&format!("{manifest}#include \"{ADMITTED}\"\n"));
    let changed=run(&mut host);
    let text=std::str::from_utf8(&changed.0).unwrap();
    assert_eq!(text.matches("code/probe.dm:6: [setter_publishes/no_publish]").count(),2,"{text}");
    assert!(!text.contains("legacy_macro.dm:") && !text.contains("maps/moved_macro.dm:"),"{text}");
    compare(&changed.0,"admitted");
    drop(host);
    assert_eq!(run(&mut BuildHost::default()),changed);
    assert!(!root.join("deepquarry.dmb").exists());
}

#[test]
fn combined_selected_original_reports_share_the_admitted_source() {
    use dq_analyze::selected_exclusions_wire::Roster;
    let root = scratch::dir("combined-selected-original");
    let cache = scratch::dir("combined-selected-cache");
    let manifest = "#warn combined_original_preparation\n#include \"code/probe.dm\"\n";
    put(&root, "deepquarry.dme", manifest);
    put(&root, "tools/ci/lint_scopes.toml", &report_config::with_overlay(""));
    put(&root, "code/probe.dm", concat!(
        "#define CAPABILITIES(...)\n",
        "#define PROC_REF(P) #P\n",
        "/datum/act\n/datum/act/eval\n",
        "/datum/receiver\n",
        "/proc/check_field(datum/receiver/argument)\n    return argument.field\n",
        "/obj/probe\n",
        "/obj/probe/proc/dynamic(datum/act/eval/A)\n    return vars[\"probe\"]\n",
        "CAPABILITIES(/obj/probe,when(PROC_REF(dynamic)))\n",
    ));
    let Command::Build(request) = dmbc::cli::parse(&["prepare-query".into(), root.join("deepquarry.dme").to_string_lossy().into_owned()]).unwrap()
    else { panic!("actual PrepareQuery") };
    let mut request = *request;
    request.no_cache = true;
    request.exact_inputs = true;
    request.progress_enabled = false;
    request.workers = 1;
    request.timeout_seconds = Some(60);
    request.engine_template = None;
    request.bootstrap_catalog = false;
    request.cache_root = Some(cache);
    request.policy_inputs = Some(PolicyInputRequest {
        analysis_context: Some(AnalysisContext::OriginalAnalyze0290),
        workspace: Some(WorkspacePolicyRequest {
            root: root.clone(), recursive_roots: vec![root.join("code"), root.join("maps")],
            configuration: root.join("tools/ci/lint_scopes.toml"),
        }), ..Default::default()
    });
    let budget = Budget::new(1 << 20).unwrap();
    let mut work = Operation { budget: &budget, poll: &|| Ok(()) };
    let all = full_unused::registered_full_selection(&[], &mut work).unwrap();
    let exclusions: Vec<_> = all.names().iter().filter(|name| !Roster::WithSemanticReads.names().contains(&name.as_str()))
        .map(|name| format!("-{name}")).collect();
    let mut host = BuildHost::default();
    let mut diagnostics = Vec::new();
    let mut checker = Vec::new();
    let mut analyze = Vec::new();
    assert!(!host.write_combined_selected_original_reports(request.clone(), &exclusions, &mut diagnostics, &mut checker, &mut analyze).unwrap());
    let checker_row: serde_json::Value = serde_json::from_slice(&checker).unwrap();
    assert_eq!(checker_row["coverage"], "selected_original_checker_phases");
    assert_eq!(checker_row["full_checker_parity"], false);
    assert_eq!(checker_row["configuration_present"], false);
    assert!(checker_row["diagnostics"].as_array().unwrap().iter().any(|row| {
        row["family"] == "undefined_variable" && row["message"].as_str().is_some_and(|msg| msg.contains("field"))
    }), "{checker_row}");
    let report = std::str::from_utf8(&analyze).unwrap();
    assert!(report.contains("[reads/dynamic_read]"), "{report}");
    assert!(report.contains("[untracked_inputs/stat_input_untracked]"), "{report}");
    let notices = std::str::from_utf8(&diagnostics).unwrap();
    assert_eq!(notices.matches("combined_original_preparation").count(), 1, "{notices}");

    let mut ordinary_diagnostics = Vec::new();
    let mut ordinary_analyze = Vec::new();
    let mut ordinary = BuildHost::default();
    assert!(!ordinary.write_original_exclusions_report(request.clone(), &exclusions, &mut ordinary_diagnostics, &mut ordinary_analyze).unwrap());
    assert_eq!((ordinary_diagnostics,ordinary_analyze),(diagnostics,analyze));

    put(&root, "deepquarry.dme", &format!("{manifest}/proc/fatal(var/A=)\n"));
    let mut no_diagnostics = Vec::new();
    let mut no_checker = Vec::new();
    let mut no_analyze = Vec::new();
    assert!(host.write_combined_selected_original_reports(request, &exclusions, &mut no_diagnostics, &mut no_checker, &mut no_analyze).is_err());
    assert!(no_diagnostics.is_empty() && no_checker.is_empty() && no_analyze.is_empty());
    assert!(!root.join("deepquarry.dmb").exists());
}

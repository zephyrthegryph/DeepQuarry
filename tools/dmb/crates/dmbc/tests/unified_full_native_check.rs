//! Real retained native report-only demand, never a compile/output pair.
#[path="../../../shared/test_scratch.rs"]mod scratch;
#[path="../../../../analyze/fixtures/report_configuration.rs"]mod report_configuration;
use dmbc::{policy_request::{AnalysisContext,PolicyInputRequest,WorkspacePolicyRequest},request::{BuildRequest,Command},runner_host::{BuildHost,FullRegistryCheckOptions}};
use std::{fs,path::{Path,PathBuf}};
#[global_allocator]static ALLOC:mimalloc::MiMalloc=mimalloc::MiMalloc;
const ROOTS:[&str;6]=["code","doc/rewrite","interface","maps","modular_chomp","tgui"];
fn put(root:&Path,relative:&str,bytes:impl AsRef<[u8]>){let p=root.join(relative);fs::create_dir_all(p.parent().unwrap()).unwrap();fs::write(p,bytes).unwrap();}
fn fixture(label:&str,source:&str)->(PathBuf,PathBuf,BuildRequest){let root=scratch::dir(label);let cache=scratch::dir(&format!("{label}-cache"));for dir in ROOTS{fs::create_dir_all(root.join(dir)).unwrap();}fs::create_dir_all(root.join(dq_analyze::ui_actions_policy::INTERFACES)).unwrap();put(&root,"deepquarry.dme","#include \"code/probe.dm\"\n");put(&root,"code/probe.dm",source);put(&root,"tools/ci/lint_scopes.toml",report_configuration::with_overlay(""));
 let Command::Build(request)=dmbc::cli::parse(&["prepare-query".into(),root.join("deepquarry.dme").to_string_lossy().into_owned()]).unwrap()else{panic!("actual public request parser")};let mut request=*request;request.no_cache=true;request.exact_inputs=true;request.progress_enabled=false;request.workers=1;request.timeout_seconds=Some(60);request.engine_template=None;request.bootstrap_catalog=false;request.cache_root=Some(cache.clone());request.policy_inputs=Some(PolicyInputRequest{analysis_context:Some(AnalysisContext::OriginalAnalyze0290),workspace:Some(WorkspacePolicyRequest{root:root.clone(),recursive_roots:ROOTS.map(|p|root.join(p)).to_vec(),configuration:root.join("tools/ci/lint_scopes.toml")}),..Default::default()});(root,cache,request)
}
fn no_runtime_products(root:&Path){for entry in fs::read_dir(root).unwrap(){let entry=entry.unwrap();let p=entry.path();if entry.file_type().unwrap().is_dir(){no_runtime_products(&p);}else{assert!(!matches!(p.extension().and_then(|e|e.to_str()),Some("dmb"|"rsc")),"ordinary check created unwanted executable product: {}",p.display());}}}
// Full production configuration deliberately exposes real findings in this tiny
// checkout. Formatting flags never convert that complete failing report to clean.
#[test]fn actual_full_native_check_separates_raw_judgment_from_ci_grouping_without_compiling(){
 for(raw,ci)in[(false,false),(false,true),(true,false),(true,true)]{let(root,cache,request)=fixture("native-full-check-matrix","/proc/probe()\n    return 0\n");let mut host=BuildHost::default();let(mut diagnostics,mut report)=(Vec::new(),Vec::new());let clean=host.write_full_registry_check(request,FullRegistryCheckOptions{raw,ci,unused:true},&mut diagnostics,&mut report).unwrap();let text=String::from_utf8(report).unwrap();assert!(!clean,"production configuration has genuine stale hot-home and fixture input findings: {text}");
   assert_eq!(text.contains("::group::"),ci);assert!(text.contains("allow annotations: 0 unused"));
   assert!(text.contains("Ratchet lints failed:"),"{text}");
   assert!(text.contains("base_vars")&&text.contains("check_grep"),"actual full-registry findings remain visible in every formatting mode: {text}");no_runtime_products(&root);no_runtime_products(&cache);}
}
#[test]fn actual_full_native_check_no_unused_preserves_no_footer_and_real_failure_verdict(){
 let(root,cache,request)=fixture("native-full-check-finding","/proc/probe()\n    sleep(1)\n    return 0\n");let mut host=BuildHost::default();let(mut diagnostics,mut report)=(Vec::new(),Vec::new());let clean=host.write_full_registry_check(request,FullRegistryCheckOptions{raw:true,ci:false,unused:false},&mut diagnostics,&mut report).unwrap();let text=String::from_utf8(report).unwrap();assert!(!clean,"real scheduler finding must refuse: {text}");assert!(text.contains("scheduler"));assert!(!text.contains("allow annotations: "));assert!(!text.contains("::group::"));no_runtime_products(&root);no_runtime_products(&cache);
}
#[test]fn actual_full_native_check_unissued_body_delivers_no_success_or_partial_report(){
 // A lone unused global proc need not be queried by targeted Analyze policies.
 // SETTER makes the actual tracked schema nonempty. Its named-position
 // producer needs a real same-archive complete literal BODY; recovered syntax
 // cannot be treated as an empty set of positions or a successful scan.
 let setter=include_str!("../../../../../code/defines/engine/capabilities.dm").lines().find(|line|line.starts_with("#define SETTER(")).expect("actual authored setter marker");
 let source=format!("{setter}\n/obj/box\n    var/plain\nSETTER(/obj/box, plain)\n/obj/box/proc/probe()\n    plain = (1 + )\n");
 let(root,cache,request)=fixture("native-full-check-unissued",&source);let mut host=BuildHost::default();let(mut diagnostics,mut report)=(Vec::new(),Vec::new());let error=host.write_full_registry_check(request,FullRegistryCheckOptions::default(),&mut diagnostics,&mut report).unwrap_err();assert!(error.to_string().contains("incomplete"),"the demanded literal BODY producer must refuse actual recovered syntax: {error}");assert!(report.is_empty());no_runtime_products(&root);no_runtime_products(&cache);
}

#[test]fn actual_full_native_check_valid_goto_body_still_supplies_real_tracked_write_positions(){
 // General Original code-disposition coverage and the targeted typed position
 // visitor are distinct roles. This valid control pins the latter's real row.
 let setter=include_str!("../../../../../code/defines/engine/capabilities.dm").lines().find(|line|line.starts_with("#define SETTER(")).unwrap();let source=format!("{setter}\n/obj/box\n    var/plain\nSETTER(/obj/box, plain)\n/obj/box/proc/probe()\n    goto finish\n    finish:\n        plain = 1\n        return 0\n");let(root,cache,request)=fixture("native-full-check-tracked-goto-row",&source);let mut host=BuildHost::default();let(mut diagnostics,mut report)=(Vec::new(),Vec::new());let clean=host.write_full_registry_check(request,FullRegistryCheckOptions{raw:true,ci:false,unused:false},&mut diagnostics,&mut report).unwrap();let text=String::from_utf8(report).unwrap();assert!(!clean);assert!(text.contains("plain written outside /obj/box/proc/set_plain()"),"the actual tracked producer must contribute its member-body write, not an empty schema/demand omission: {text}");no_runtime_products(&root);no_runtime_products(&cache);
}

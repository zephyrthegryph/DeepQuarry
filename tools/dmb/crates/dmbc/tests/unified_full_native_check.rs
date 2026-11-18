//! Real retained native report-only demand, never a compile/output pair.
#[path="../../../shared/test_scratch.rs"]mod scratch;
#[path="../../../../analyze/fixtures/report_configuration.rs"]mod report_configuration;
use dmbc::{policy_request::{AnalysisContext,PolicyInputRequest,WorkspacePolicyRequest},request::{BuildRequest,Command},runner_host::{BuildHost,FullRegistryCheckOptions}};
use std::{fs,path::{Path,PathBuf}};
#[global_allocator]static ALLOC:mimalloc::MiMalloc=mimalloc::MiMalloc;
const ROOTS:[&str;6]=["code","doc/rewrite","interface","maps","modular_chomp","tgui"];
fn put(root:&Path,relative:&str,bytes:impl AsRef<[u8]>){let p=root.join(relative);fs::create_dir_all(p.parent().unwrap()).unwrap();fs::write(p,bytes).unwrap();}
fn fixture(label:&str,source:&str)->(PathBuf,PathBuf,BuildRequest){let root=fs::canonicalize(scratch::dir(label)).unwrap();let cache=scratch::dir(&format!("{label}-cache"));for dir in ROOTS{fs::create_dir_all(root.join(dir)).unwrap();}fs::create_dir_all(root.join(dq_analyze::ui_actions_policy::INTERFACES)).unwrap();put(&root,"deepquarry.dme","#include \"code/probe.dm\"\n");put(&root,"code/probe.dm",source);put(&root,"tools/ci/lint_scopes.toml",report_configuration::with_overlay(""));
 let Command::Build(request)=dmbc::cli::parse(&["prepare-query".into(),root.join("deepquarry.dme").to_string_lossy().into_owned()]).unwrap()else{panic!("actual public request parser")};let mut request=*request;request.no_cache=true;request.exact_inputs=true;request.progress_enabled=false;request.workers=1;request.timeout_seconds=Some(60);request.engine_template=None;request.bootstrap_catalog=false;request.cache_root=Some(cache.clone());request.policy_inputs=Some(PolicyInputRequest{analysis_context:Some(AnalysisContext::OriginalAnalyze0290),workspace:Some(WorkspacePolicyRequest{root:root.clone(),recursive_roots:ROOTS.map(|p|root.join(p)).to_vec(),configuration:root.join("tools/ci/lint_scopes.toml")}),..Default::default()});(root,cache,request)
}
fn no_runtime_products(root:&Path){for entry in fs::read_dir(root).unwrap(){let entry=entry.unwrap();let p=entry.path();if entry.file_type().unwrap().is_dir(){no_runtime_products(&p);}else{assert!(!matches!(p.extension().and_then(|e|e.to_str()),Some("dmb"|"rsc")),"ordinary check created unwanted executable product: {}",p.display());}}}
// Full production configuration deliberately exposes real findings in this tiny
// checkout. Formatting flags never convert that complete failing report to clean.
#[test]fn actual_full_native_check_separates_raw_judgment_from_ci_grouping_without_compiling(){
 for(raw,ci)in[(false,false),(false,true),(true,false),(true,true)]{let(root,cache,request)=fixture("native-full-check-matrix","/proc/probe()\n    return 0\n");let mut host=BuildHost::default();let(mut diagnostics,mut report)=(Vec::new(),Vec::new());let clean=host.write_full_registry_check(request,FullRegistryCheckOptions{raw,ci,unused:true,..Default::default()},&mut diagnostics,&mut report).unwrap();let text=String::from_utf8(report).unwrap();assert!(!clean,"production configuration has genuine stale hot-home and fixture input findings: {text}");
   assert_eq!(text.contains("::group::"),ci);assert!(text.contains("allow annotations: 0 unused"));
   assert!(text.contains("Ratchet lints failed:"),"{text}");
   assert!(text.contains("base_vars")&&text.contains("check_grep"),"actual full-registry findings remain visible in every formatting mode: {text}");no_runtime_products(&root);no_runtime_products(&cache);}
}
#[test]fn actual_full_native_check_no_unused_preserves_no_footer_and_real_failure_verdict(){
 let(root,cache,request)=fixture("native-full-check-finding","/proc/probe()\n    sleep(1)\n    return 0\n");let mut host=BuildHost::default();let(mut diagnostics,mut report)=(Vec::new(),Vec::new());let clean=host.write_full_registry_check(request,FullRegistryCheckOptions{raw:true,ci:false,unused:false,..Default::default()},&mut diagnostics,&mut report).unwrap();let text=String::from_utf8(report).unwrap();assert!(!clean,"real scheduler finding must refuse: {text}");assert!(text.contains("scheduler"));assert!(!text.contains("allow annotations: "));assert!(!text.contains("::group::"));no_runtime_products(&root);no_runtime_products(&cache);
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
 let setter=include_str!("../../../../../code/defines/engine/capabilities.dm").lines().find(|line|line.starts_with("#define SETTER(")).unwrap();let source=format!("{setter}\n/obj/box\n    var/plain\nSETTER(/obj/box, plain)\n/obj/box/proc/probe()\n    goto finish\n    finish:\n        plain = 1\n        return 0\n");let(root,cache,request)=fixture("native-full-check-tracked-goto-row",&source);let mut host=BuildHost::default();let(mut diagnostics,mut report)=(Vec::new(),Vec::new());let clean=host.write_full_registry_check(request,FullRegistryCheckOptions{raw:true,ci:false,unused:false,..Default::default()},&mut diagnostics,&mut report).unwrap();let text=String::from_utf8(report).unwrap();assert!(!clean);assert!(text.contains("plain written outside /obj/box/proc/set_plain()"),"the actual tracked producer must contribute its member-body write, not an empty schema/demand omission: {text}");no_runtime_products(&root);no_runtime_products(&cache);
}

#[test]fn actual_report_only_observation_exports_one_complete_actual_ledger_and_binds_both_report_frames(){
 for(raw,ci)in[(true,false),(false,true)]{
  let(root,cache,request)=fixture("native-full-check-observed-ledger","/proc/probe()\n    return 0\n");let mut host=BuildHost::default();let(mut diagnostics,mut report)=(Vec::new(),Vec::new());let mut exported=None;let before=std::time::Instant::now();
  let clean=host.write_full_registry_check_with_input_observation(request,FullRegistryCheckOptions{raw,ci,unused:true,..Default::default()},|observation|{assert!(observation.deadline>before);assert!(observation.deadline<=std::time::Instant::now()+std::time::Duration::from_secs(60));let(mut header,mut inputs,mut checker)=(Vec::new(),Vec::new(),Vec::new());observation.write_inputs(&mut header,&mut inputs,&mut checker)?;exported=Some((header,inputs,checker));Ok(())},&mut diagnostics,&mut report).unwrap();
  let(header,inputs,checker)=exported.expect("actual observation ran exactly once");let header:serde_json::Value=serde_json::from_slice(&header).unwrap();assert_eq!(header["schema"],"joined-report-input-observation-v1");assert_eq!(header["kind"],"observed_combined_preparation_inputs_only");assert!(header.get("native_pair").is_none());assert!(header.get("native_inputs").is_none());assert_eq!(header["full_checker_parity"],false);assert_eq!(header["full_policy_parity"],false);assert_eq!(header["binding"]["clean"],clean);assert_eq!(header["binding"]["options"]["raw"],raw);assert_eq!(header["binding"]["options"]["ci"],ci);assert_eq!(header["binding"]["original_archive_bodies"],1,"the actual fixture has one original callable input before any Checker traversal");
  assert_eq!(header["binding"]["frame"]["semantic_revision"],header["binding"]["checker_frame"]["semantic_revision"]);assert_eq!(header["binding"]["frame"]["source_revision"],header["binding"]["checker_frame"]["source_revision"]);
  assert_eq!(header["combined_preparation_inputs"]["length"].as_u64(),Some(inputs.len()as u64));assert_eq!(header["binding"]["report"]["length"].as_u64(),Some(report.len()as u64));assert_eq!(header["combined_preparation_inputs"]["hash"],format!("{:032x}",xxhash_rust::xxh3::xxh3_128(&inputs)));assert_eq!(header["binding"]["report"]["hash"],format!("{:032x}",xxhash_rust::xxh3::xxh3_128(&report)));
  assert_eq!(header["binding"]["checker"]["length"].as_u64(),Some(checker.len()as u64));assert_eq!(header["binding"]["checker"]["hash"],format!("{:032x}",xxhash_rust::xxh3::xxh3_128(&checker)));let actual_checker:serde_json::Value=serde_json::from_slice(&checker).unwrap();assert_eq!(actual_checker["scope_completion"]["scope"],"whole_input_current_ordered_producers");assert_eq!(actual_checker["semantic_revision"],header["binding"]["checker_frame"]["semantic_revision"]);assert_eq!(actual_checker["source_revision"],header["binding"]["checker_frame"]["source_revision"]);assert_eq!(String::from_utf8_lossy(&report).contains("::group::"),ci);
  let actual:dmbc::input_snapshot::InputSnapshot=serde_json::from_slice(&inputs).unwrap();assert!(actual.files().any(|f|f.path.ends_with("tools/ci/lint_scopes.toml")));let json=String::from_utf8(inputs).unwrap();assert!(json.contains("policy_directories"));assert!(json.contains("probe.dm"));assert!(json.contains("negative_files"));assert!(json.contains("opened_reads"));assert!(json.contains("original_payloads"));
  no_runtime_products(&root);no_runtime_products(&cache);
 }
}
#[test]fn actual_report_only_observation_first_callback_io_stops_delivery_and_same_host_recovers(){
 let(root,cache,request)=fixture("native-full-check-observe-first-io","/proc/probe()\n    return 0\n");let mut host=BuildHost::default();let(mut diagnostics,mut report)=(Vec::new(),Vec::new());let mut calls=0;
 let error=host.write_full_registry_check_with_input_observation(request.clone(),FullRegistryCheckOptions::default(),|_|{calls+=1;Err(std::io::Error::from_raw_os_error(1450))},&mut diagnostics,&mut report).unwrap_err();assert_eq!(error.downcast_ref::<std::io::Error>().unwrap().raw_os_error(),Some(1450));assert_eq!(calls,1);assert!(diagnostics.is_empty());assert!(report.is_empty());
 host.write_full_registry_check_with_input_observation(request,FullRegistryCheckOptions::default(),|_|Ok(()),&mut diagnostics,&mut report).unwrap();assert!(!report.is_empty());no_runtime_products(&root);no_runtime_products(&cache);
}
#[test]fn actual_report_only_observation_same_stamp_content_change_refuses_completion_and_recovers(){
 let(root,cache,request)=fixture("native-full-check-observe-stale","/proc/probe()\n    return 0\n");let path=root.join("code/probe.dm");let old=fs::read(&path).unwrap();let modified=fs::metadata(&path).unwrap().modified().unwrap();let mut host=BuildHost::default();let(mut diagnostics,mut report)=(Vec::new(),Vec::new());
 let error=host.write_full_registry_check_with_input_observation(request.clone(),FullRegistryCheckOptions::default(),|_|{let mut changed=old.clone();let at=changed.iter().position(|b|*b==b'0').unwrap();changed[at]=b'1';fs::write(&path,changed)?;let file=fs::OpenOptions::new().write(true).open(&path)?;file.set_times(fs::FileTimes::new().set_modified(modified))?;drop(file);Ok(())},&mut diagnostics,&mut report).unwrap_err();fs::write(&path,&old).unwrap();assert!(error.to_string().contains("changed"),"{error}");assert!(diagnostics.is_empty());assert!(report.is_empty());
 host.write_full_registry_check_with_input_observation(request,FullRegistryCheckOptions::default(),|_|Ok(()),&mut diagnostics,&mut report).unwrap();assert!(!report.is_empty());no_runtime_products(&root);no_runtime_products(&cache);
}

#[test]fn actual_report_only_observation_caught_first_export_io_refuses_completion_and_same_host_recovers(){
 struct Stop;impl std::io::Write for Stop{fn write(&mut self,_:&[u8])->std::io::Result<usize>{Err(std::io::Error::from_raw_os_error(1450))}fn flush(&mut self)->std::io::Result<()>{panic!("no flush after first export IO")}}
 struct Later;impl std::io::Write for Later{fn write(&mut self,_:&[u8])->std::io::Result<usize>{panic!("no later stream after first export IO")}fn flush(&mut self)->std::io::Result<()>{panic!("no later flush after first export IO")}}
 let(root,cache,request)=fixture("native-full-check-caught-export-first-io","/proc/probe()\n    return 0\n");let mut host=BuildHost::default();let(mut diagnostics,mut report)=(Vec::new(),Vec::new());let mut calls=0;
 let error=host.write_full_registry_check_with_input_observation(request.clone(),FullRegistryCheckOptions::default(),|observation|{calls+=1;assert!(observation.write_inputs(&mut Stop,&mut Later,&mut Later).is_err());Ok(())},&mut diagnostics,&mut report).unwrap_err();assert_eq!(error.downcast_ref::<std::io::Error>().unwrap().raw_os_error(),Some(1450));assert_eq!(calls,1);assert!(diagnostics.is_empty());assert!(report.is_empty());
 host.write_full_registry_check_with_input_observation(request,FullRegistryCheckOptions::default(),|_|Ok(()),&mut diagnostics,&mut report).unwrap();assert!(!report.is_empty());no_runtime_products(&root);no_runtime_products(&cache);
}

#[test]fn actual_selected_raw_and_doc_checks_need_no_dme_or_semantic_body(){
 for selector in ["scheduler","doc_snippets"]{let(root,cache,request)=fixture("native-selected-no-dme","/proc/probe()\n    goto finish\n    finish:\n        return 0\n");fs::remove_file(root.join("deepquarry.dme")).unwrap();fs::create_dir_all(root.join("SpacemanDMM.toml")).unwrap();put(&root,"doc/rewrite/probe.md","Documentation only.\n");put(&root,"doc/rewrite/archive/unrelated.md","\x60\x60\x60dm\nnot_a_real_proc()\n\x60\x60\x60\n");
 let mut host=BuildHost::default();let(mut diagnostics,mut report)=(Vec::new(),Vec::new());let clean=host.write_selected_registry_check(request,FullRegistryCheckOptions::default(),&[selector.into()],&mut diagnostics,&mut report).unwrap();let text=String::from_utf8(report).unwrap();assert!(clean,"{selector}: {text}");assert!(text.contains(selector));assert!(!text.contains("allow annotations: "));assert!(diagnostics.is_empty());no_runtime_products(&root);no_runtime_products(&cache);}
}
#[test]fn actual_selected_semantic_check_does_not_demand_checker_handler_or_unselected_config(){
 let(root,cache,request)=fixture("native-selected-semantic-no-dme","/datum/semantic_probe\n    var/value = 1\n/datum/semantic_probe/proc/not_selected()\n    return no_such_global_proc()\n");fs::remove_file(root.join("deepquarry.dme")).unwrap();fs::create_dir_all(root.join("SpacemanDMM.toml")).unwrap();
 // This is the real unrelated Sites policy baseline, not a guessed filename.
 let meta=dq_analyze::engine_layering_policy::Layer::Library.metadata();let baseline=match meta.policy{dq_analyze::lint::Policy::Sites{baseline,..}|dq_analyze::lint::Policy::Ceilings{baseline,..}=>baseline,_=>panic!("library policy must retain its actual registered baseline for this control")};fs::create_dir_all(root.join(baseline)).unwrap();
 let mut host=BuildHost::default();let(mut diagnostics,mut report)=(Vec::new(),Vec::new());let clean=host.write_selected_registry_check(request,FullRegistryCheckOptions::default(),&["sem/reads".into()],&mut diagnostics,&mut report).unwrap();let text=String::from_utf8(report).unwrap();assert!(clean,"{text}");assert!(text.contains("reads:"));assert!(!text.contains("no_such_global_proc"),"unselected Checker must not inspect unrelated body calls");assert!(!text.contains("allow annotations: "));no_runtime_products(&root);no_runtime_products(&cache);
}

#[test]fn actual_selected_raw_keys_and_sys_checks_use_no_model_checker_or_manifest(){
 for(selector,label)in[("sem/keys","keys:"),("sys/hygiene","sys/hygiene:"),("sys/resolvers","sys/resolvers:"),("sys/tables","sys/tables:"),("system_boundary","system_boundary:")]{
  let(root,cache,request)=fixture("native-selected-raw-kernel","/proc/probe()\n    goto absent_label\n");fs::remove_file(root.join("deepquarry.dme")).unwrap();fs::create_dir_all(root.join("SpacemanDMM.toml")).unwrap();
  let mut host=BuildHost::default();let(mut diagnostics,mut report)=(Vec::new(),Vec::new());host.write_selected_registry_check(request,FullRegistryCheckOptions::default(),&[selector.into()],&mut diagnostics,&mut report).unwrap();let text=String::from_utf8(report).unwrap();assert!(text.contains(label),"{selector}: {text}");assert!(diagnostics.is_empty(),"unselected native Checker must not inspect the genuinely unsupported goto body");assert!(!text.contains("allow annotations: "));no_runtime_products(&root);no_runtime_products(&cache);
 }
}


fn selected_engine_fixture(label:&str)->(PathBuf,PathBuf,BuildRequest){
 let(root,cache,mut request)=fixture(label,"/proc/unselected_bad(\n");put(&root,"code/engine/probe.dm","/proc/also_unselected_bad(\n");put(&root,"tools/ci/lint_scopes.toml",report_configuration::with_overlay("[lint.engine_layering]\nexempt_files = [\"code/engine/probe.dm\"]\n"));put(&root,"SpacemanDMM.toml","not valid checker configuration {{{\n");let root=fs::canonicalize(root).unwrap();let cache=fs::canonicalize(cache).unwrap();request.project=root.join("deepquarry.dme");request.cache_root=Some(cache.clone());let workspace=request.policy_inputs.as_mut().unwrap().workspace.as_mut().unwrap();workspace.root=root.clone();workspace.configuration=root.join("tools/ci/lint_scopes.toml");workspace.recursive_roots=ROOTS.map(|p|root.join(p)).to_vec();(root,cache,request)
}
#[test]fn actual_selected_engine_empty_keeps_bad_missing_nonfile_dme_outside_model_and_checker(){
 for case in 0..3{let(root,_cache,request)=selected_engine_fixture("selected-engine-empty-real");let dme=root.join("deepquarry.dme");match case{0=>fs::write(&dme,"#include \"missing_compile_dependency.dm\"\n").unwrap(),1=>fs::remove_file(&dme).unwrap(),_=>{fs::remove_file(&dme).unwrap();fs::create_dir(&dme).unwrap();}}
  let mut host=BuildHost::default();let(mut diagnostics,mut report)=(Vec::new(),Vec::new());let clean=host.write_selected_registry_check(request,FullRegistryCheckOptions::default(),&["engine_layering".into()],&mut diagnostics,&mut report).unwrap();assert!(clean);assert!(diagnostics.is_empty());let text=String::from_utf8(report).unwrap();assert!(text.ends_with("All ratchet lints passed.\n"));assert!(!text.contains("allow annotations:"));no_runtime_products(&root);
 }
}
#[test]fn actual_selected_engine_nonempty_uses_real_model_without_extra_checker(){
 let(root,_cache,request)=selected_engine_fixture("selected-engine-model-real");put(&root,"tools/ci/lint_scopes.toml",report_configuration::with_overlay(""));put(&root,"code/probe.dm","/proc/unselected()\n    return 0\n");put(&root,"code/engine/probe.dm","/proc/engine_entry()\n    ordinary_helper()\n");put(&root,"code/library/downstream.dm","/proc/ordinary_helper()\n    return 0\n");put(&root,"deepquarry.dme","#include \"code/engine/probe.dm\"\n#include \"code/library/downstream.dm\"\n");put(&root,"SpacemanDMM.toml","not valid checker configuration {{{\n");
 let mut host=BuildHost::default();let(mut diagnostics,mut report)=(Vec::new(),Vec::new());let clean=host.write_selected_registry_check(request,FullRegistryCheckOptions{raw:true,ci:false,..Default::default()},&["engine_layering".into()],&mut diagnostics,&mut report).unwrap();assert!(!clean);let text=String::from_utf8(report).unwrap();assert!(text.contains("ordinary_helper")&&text.contains("external_dependency"),"real downstream definition must be visited: {text}");assert!(text.ends_with("Ratchet lints failed: engine_layering\n"));assert!(!text.contains("allow annotations:"));
}
#[test]fn actual_selected_engine_unjoined_source_mixture_is_explicitly_unsupported(){
 let(_root,_cache,request)=selected_engine_fixture("selected-engine-mixture-refuse");let mut host=BuildHost::default();let(mut diagnostics,mut report)=(Vec::new(),Vec::new());let error=host.write_selected_registry_check(request,FullRegistryCheckOptions::default(),&["engine_layering".into(),"scheduler".into()],&mut diagnostics,&mut report).unwrap_err();let actual=error.downcast_ref::<std::io::Error>().unwrap();assert_eq!(actual.kind(),std::io::ErrorKind::Unsupported);assert!(report.is_empty()&&diagnostics.is_empty());
}
#[test]fn actual_selected_engine_first_output_io_keeps_actual_error_and_same_host_recovers(){
 struct Stop;impl std::io::Write for Stop{fn write(&mut self,_:&[u8])->std::io::Result<usize>{Err(std::io::Error::from_raw_os_error(1450))}fn flush(&mut self)->std::io::Result<()>{panic!("no flush after actual first IO")}}
 let(_root,_cache,request)=selected_engine_fixture("selected-engine-first-io-real");let mut host=BuildHost::default();let mut diagnostics=Vec::new();let error=host.write_selected_registry_check(request.clone(),FullRegistryCheckOptions::default(),&["engine_layering".into()],&mut diagnostics,&mut Stop).unwrap_err();assert_eq!(error.downcast_ref::<std::io::Error>().unwrap().raw_os_error(),Some(1450));let mut report=Vec::new();assert!(host.write_selected_registry_check(request,FullRegistryCheckOptions::default(),&["engine_layering".into()],&mut diagnostics,&mut report).unwrap());
}
#[test]fn actual_selected_engine_same_stamp_configuration_mutation_refuses_and_recovers(){
 struct Change{path:PathBuf,stamp:std::time::SystemTime,changed:bool}impl std::io::Write for Change{fn write(&mut self,bytes:&[u8])->std::io::Result<usize>{if !self.changed{self.changed=true;let source=fs::read_to_string(&self.path)?;let changed=source.replace("code/engine/probe.dm","code/engine/other.dm");assert_ne!(source,changed);assert_eq!(source.len(),changed.len());fs::write(&self.path,changed)?;let file=fs::OpenOptions::new().write(true).open(&self.path)?;file.set_times(fs::FileTimes::new().set_modified(self.stamp))?;}Ok(bytes.len())}fn flush(&mut self)->std::io::Result<()>{Ok(())}}
 let(root,_cache,request)=selected_engine_fixture("selected-engine-stale-real");let path=root.join("tools/ci/lint_scopes.toml");let before=fs::read(&path).unwrap();let stamp=fs::metadata(&path).unwrap().modified().unwrap();let mut writer=Change{path:path.clone(),stamp,changed:false};let mut host=BuildHost::default();let mut diagnostics=Vec::new();assert!(host.write_selected_registry_check(request.clone(),FullRegistryCheckOptions::default(),&["engine_layering".into()],&mut diagnostics,&mut writer).is_err());assert!(writer.changed);fs::write(&path,before).unwrap();let mut report=Vec::new();assert!(host.write_selected_registry_check(request,FullRegistryCheckOptions::default(),&["engine_layering".into()],&mut diagnostics,&mut report).unwrap());
}
#[test]fn actual_selected_engine_real_source_arena_denial_refuses_then_releases_and_recovers(){
 let(_root,_cache,request)=selected_engine_fixture("selected-engine-quota-real");let mut host=BuildHost::default();let limit=host.source_arena_work().transformed_source_address_limit().unwrap();let pressure=host.source_arena_work().reserve(limit-512*1024).unwrap();let(mut diagnostics,mut report)=(Vec::new(),Vec::new());let error=host.write_selected_registry_check(request.clone(),FullRegistryCheckOptions::default(),&["engine_layering".into()],&mut diagnostics,&mut report).unwrap_err();assert_eq!(error.downcast_ref::<std::io::Error>().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert!(report.is_empty());drop(pressure);assert!(host.write_selected_registry_check(request,FullRegistryCheckOptions::default(),&["engine_layering".into()],&mut diagnostics,&mut report).unwrap());
}

#[test]fn actual_positive_all_registry_names_keep_requested_options_without_unrequested_unused_audit(){
 let budget=dq_analyze::captured_generator_budget::Budget::new(1<<20).unwrap();let data=dq_analyze::captured_registry_check_selection::select(&[],&budget,&||Ok(())).unwrap();let selectors=data.names().to_vec();assert!(selectors.len()>3);
 let(root,cache,request)=fixture("native-selected-all-positive","/proc/probe()\n    return 0\n");let options=FullRegistryCheckOptions::default();assert!(options.unused);let mut host=BuildHost::default();let(mut diagnostics,mut named)=(Vec::new(),Vec::new());
 let named_clean=host.write_selected_registry_check(request.clone(),options,&selectors,&mut diagnostics,&mut named).unwrap();let named=String::from_utf8(named).unwrap();assert!(!named.contains("allow annotations: "),"positive-all is the same producer roster but does not request the independent unused audit: {named}");
 let(mut whole_diagnostics,mut whole)=(Vec::new(),Vec::new());let whole_clean=host.write_full_registry_check(request,options,&mut whole_diagnostics,&mut whole).unwrap();let whole=String::from_utf8(whole).unwrap();assert!(whole.contains("allow annotations: 0 unused"),"ordinary whole request keeps its real audit: {whole}");assert_eq!(named_clean,whole_clean);assert_eq!(diagnostics,whole_diagnostics);no_runtime_products(&root);no_runtime_products(&cache);
}

#[test]fn actual_selected_source_handler_mixture_completes_real_sources_without_unrequested_model(){
 let(root,cache,request)=fixture("native-selected-source-handler-union","/proc/probe(\n");fs::remove_file(root.join("deepquarry.dme")).unwrap();fs::create_dir_all(root.join("SpacemanDMM.toml")).unwrap();let mut host=BuildHost::default();let(mut diagnostics,mut report)=(Vec::new(),Vec::new());
 assert!(host.write_selected_registry_check(request,FullRegistryCheckOptions::default(),&["scheduler".into(),"sem/handlers".into()],&mut diagnostics,&mut report).unwrap(),"genuine empty Handler selection plus clean raw producer is complete: {}",String::from_utf8_lossy(&report));assert!(diagnostics.is_empty()&&!report.is_empty());assert!(!String::from_utf8_lossy(&report).contains("allow annotations:"));assert!(host.symbolic_retention_stats().is_none_or(|stats|stats.records==0&&stats.successful_admissions==0));no_runtime_products(&root);no_runtime_products(&cache);
}

#[path="../../../shared/test_native_transport.rs"]mod selected_native_transport;
#[test]
#[ignore="private native IPC; run exact outside Cargo under dm_compile machine slot"]
fn actual_resident_positive_all_registry_selection_seals_requested_unused_and_omits_unrequested_audit(){
 use std::{ffi::OsString,time::Duration};
 let budget=dq_analyze::captured_generator_budget::Budget::new(1<<20).unwrap();let data=dq_analyze::captured_registry_check_selection::select(&[],&budget,&||Ok(())).unwrap();let selectors=data.names().to_vec();let expected=dq_analyze::full_registry_check_selection_wire::SelectionBinding::for_selectors(&selectors).unwrap();
 let(root,cache,_)=fixture("resident-selected-all-positive","#warn SELECTED_BINDING_NOTICE\n/proc/probe()\n    return 0\n");let transport_root=scratch::dir("resident-selected-all-transport");let transport=selected_native_transport::LibraryTransport{root:&transport_root,namespace:format!("resident-selected-all-{}",std::process::id())};
 let mut arguments=vec![OsString::from("analyze-full-check"),OsString::from("--workspace"),root.as_os_str().to_owned(),OsString::from("--no-selftest")];for name in &selectors{arguments.push("--lint".into());arguments.push(OsString::from(name.as_str()));}let arguments=arguments.iter().map(OsString::as_os_str).collect::<Vec<_>>();
 let actual=transport.run_program_with_trace(Path::new(env!("CARGO_BIN_EXE_dmbc")),&arguments,Duration::from_secs(90),true).unwrap();assert!(matches!(actual.status.code(),Some(0|1)),"{}",String::from_utf8_lossy(&actual.stderr));
 let end=actual.stdout.iter().take(dq_analyze::selected_exclusions_wire::MAX_HEADER).position(|byte|*byte==b'\n').expect("actual bounded terminal");let terminal:dq_analyze::full_registry_check_wire::Terminal=serde_json::from_slice(&actual.stdout[..end]).unwrap();let options=FullRegistryCheckOptions::default();assert!(options.unused);terminal.require(options,expected).unwrap();assert!(terminal.options.unused);assert!(matches!(terminal.scope,dq_analyze::full_registry_check_wire::Scope::FullRegistry));assert_eq!(terminal.selected,selectors.len()as u64);assert_eq!(terminal.selected,terminal.registered);assert_eq!(terminal.clean,actual.status.code()==Some(0));
 assert!(actual.stderr.is_empty(),"operational trace must stay in lifecycle log: {}",String::from_utf8_lossy(&actual.stderr));assert!(terminal.diagnostics.is_some(),"the authored preprocessor notice must be present in the actual semantic envelope");let payload=&actual.stdout[end+1..];let diagnostic_len=usize::try_from(terminal.diagnostics.as_ref().map_or(0,|seal|seal.length)).unwrap();let report_len=usize::try_from(terminal.report.length).unwrap();assert_eq!(diagnostic_len.checked_add(report_len).unwrap(),payload.len());let(diagnostics,report)=payload.split_at(diagnostic_len);match terminal.diagnostics{Some(seal)=>assert_eq!(seal.hash.0,xxhash_rust::xxh3::xxh3_128(diagnostics)),None=>assert!(diagnostics.is_empty())};assert!(String::from_utf8_lossy(diagnostics).contains("SELECTED_BINDING_NOTICE"));assert_eq!(terminal.report.hash.0,xxhash_rust::xxh3::xxh3_128(report));assert!(!String::from_utf8_lossy(report).contains("allow annotations: "));no_runtime_products(&root);no_runtime_products(&cache);
}

#[test]fn actual_handler_only_negative_full_selection_completes_genuine_unused_union_then_honors_no_unused(){
 let budget=dq_analyze::captured_generator_budget::Budget::new(1<<20).unwrap();let all=dq_analyze::captured_registry_check_selection::select(&[],&budget,&||Ok(())).unwrap();let selectors=all.names().iter().filter(|name|name.as_str()!="sem/handlers").map(|name|format!("-{name}")).collect::<Vec<_>>();let(root,cache,request)=fixture("selected-handler-full-unused-union","/proc/probe()\n    return 0\n");fs::remove_file(root.join("deepquarry.dme")).unwrap();fs::create_dir_all(root.join("SpacemanDMM.toml")).unwrap();let mut host=BuildHost::default();let(mut diagnostics,mut report)=(Vec::new(),Vec::new());assert!(host.write_selected_registry_check(request.clone(),FullRegistryCheckOptions::default(),&selectors,&mut diagnostics,&mut report).unwrap());assert!(diagnostics.is_empty());assert!(String::from_utf8_lossy(&report).contains("allow annotations: 0 unused"),"the same actual full-run context must consume its independent EOF audit: {}",String::from_utf8_lossy(&report));report.clear();let clean=host.write_selected_registry_check(request,FullRegistryCheckOptions{unused:false,..Default::default()},&selectors,&mut diagnostics,&mut report).unwrap();assert!(clean,"{}",String::from_utf8_lossy(&report));assert!(!report.is_empty()&&!String::from_utf8_lossy(&report).contains("allow annotations:"));no_runtime_products(&root);no_runtime_products(&cache);
}

#[test]fn actual_registered_untracked_and_setter_reports_keep_individual_roles(){
 for selector in ["untracked_inputs","setter_publishes"]{
  let(root,cache,request)=fixture("registered-individual-semantic-role","/datum/semantic_probe\n    var/value = 1\n/datum/semantic_probe/proc/not_selected()\n    return no_such_global_proc()\n");fs::remove_file(root.join("deepquarry.dme")).unwrap();fs::create_dir_all(root.join("SpacemanDMM.toml")).unwrap();
  let meta=dq_analyze::engine_layering_policy::Layer::Library.metadata();let baseline=match meta.policy{dq_analyze::lint::Policy::Sites{baseline,..}|dq_analyze::lint::Policy::Ceilings{baseline,..}=>baseline,_=>panic!("actual unrelated baseline")};fs::create_dir_all(root.join(baseline)).unwrap();
  let mut host=BuildHost::default();let(mut diagnostics,mut report)=(Vec::new(),Vec::new());let clean=host.write_selected_registry_check(request,FullRegistryCheckOptions::default(),&[selector.into()],&mut diagnostics,&mut report).unwrap();let text=String::from_utf8(report).unwrap();assert!(clean,"{selector}: {text}");assert!(text.contains(selector),"{selector}: {text}");assert!(!text.contains("no_such_global_proc"));assert!(!text.contains("allow annotations: "));assert!(diagnostics.is_empty());no_runtime_products(&root);no_runtime_products(&cache);
 }
}

#[test]fn actual_native_report_effective_raw_ci_options_keep_real_failure_and_no_unused_footer(){
 let(root,cache,request)=fixture("native-report-raw-ci","/proc/probe()\n    sleep(1)\n    return 0\n");let mut host=BuildHost::default();let(mut diagnostics,mut report)=(Vec::new(),Vec::new());
 let clean=host.write_selected_registry_check(request,FullRegistryCheckOptions{raw:true,ci:true,unused:false,..Default::default()},&["scheduler".into()],&mut diagnostics,&mut report).unwrap();let text=String::from_utf8(report).unwrap();assert!(!clean,"actual report failure must remain failure: {text}");assert!(text.contains("scheduler")&&text.contains("::group::")&&text.contains("::endgroup::"),"{text}");assert!(text.contains("Ratchet lints failed:"));assert!(!text.contains("allow annotations:"));assert!(diagnostics.is_empty());no_runtime_products(&root);no_runtime_products(&cache);
}

#[test]fn actual_native_raw_selftests_precede_same_selected_policy_operation_without_legacy_engine(){
 let(root,cache,request)=fixture("native-raw-selftests","/datum/probe\n");let mut host=BuildHost::default();let(mut diagnostics,mut report)=(Vec::new(),Vec::new());let selectors=vec!["reactions_table_proc".into(),"entry_slots".into()];
 let actual=host.write_selected_registry_check_with_selftests(request,FullRegistryCheckOptions{raw:true,unused:false,..Default::default()},&selectors,&mut diagnostics,&mut report).unwrap();assert!(matches!(actual,dmbc::runner_host::SelftestedRegistryCheck::Checked{clean:true,selftests_failed:0}),"{actual:?}");no_runtime_products(&root);no_runtime_products(&cache);
}
#[test]fn actual_unported_selftest_roster_refuses_without_claiming_policy_completion_or_output(){
 let(root,cache,request)=fixture("native-unported-selftests","/proc/p()\n    return ([)]\n");let mut host=BuildHost::default();let(mut diagnostics,mut report)=(Vec::new(),Vec::new());let error=host.write_selected_registry_check_with_selftests(request,FullRegistryCheckOptions{raw:true,unused:false,..Default::default()},&[],&mut diagnostics,&mut report).unwrap_err();let actual=error.downcast_ref::<std::io::Error>().unwrap();assert_eq!(actual.kind(),std::io::ErrorKind::Unsupported);assert!(actual.to_string().contains("not yet ported for every selected producer"));assert!(diagnostics.is_empty()&&report.is_empty());no_runtime_products(&root);no_runtime_products(&cache);
}

#[test]fn actual_full_selftests_keep_typed_ui_failure_then_run_parent_policies_and_unused_footer(){
 let(root,cache,mut request)=fixture("native-all-selftest-semantic-failure","/proc/probe()\n    sleep(1)\n    return 0\n");request.timeout_seconds=Some(300);
 let changed=dq_analyze::ui_selftest_policy::DISPATCHER_FIXTURE.replace("length(raw) > 64","length(raw) > 1");assert_ne!(changed,dq_analyze::ui_selftest_policy::DISPATCHER_FIXTURE);put(&root,dq_analyze::ui_actions_policy::DISPATCHER,changed);put(&root,".gitignore","");
 let mut host=BuildHost::default();let(mut diagnostics,mut report)=(Vec::new(),Vec::new());let result=host.write_selected_registry_check_with_selftests_from_caller(request,FullRegistryCheckOptions{raw:true,..Default::default()},&[],Some(root.clone()),&mut diagnostics,&mut report).unwrap();
 assert_eq!(result,dmbc::runner_host::SelftestedRegistryCheck::Checked{clean:false,selftests_failed:1});let text=String::from_utf8(report).unwrap();let failure=text.find("selftest FAILED: ui_actions: the live ui_action_key() no longer matches").unwrap();let policy=text.find("scheduler").unwrap();assert!(failure<policy,"callback failure precedes actual policy output: {text}");assert!(text.contains("ui_actions --selftest"),"typed final failed names must survive: {text}");assert!(text.contains("allow annotations: 0 unused"),"semantic callback failure must not skip the real unused producer: {text}");assert!(!String::from_utf8_lossy(&diagnostics).contains("native-selftest-"),"nested fixture semantic diagnostics must not join the parent stream");no_runtime_products(&root);no_runtime_products(&cache);
}
#[test]fn actual_selected_derived_selftest_restores_parent_engine_and_diagnostics_on_the_same_host(){
 let(root,cache,mut request)=fixture("native-selftest-parent-resume","#warn OUTER_NATIVE_SELFTEST_NOTICE\n/obj/probe\n    var/value = 0\n/obj/probe/proc/read_value()\n    return value\n");request.timeout_seconds=Some(300);let mut host=BuildHost::default();let(mut diagnostics,mut report)=(Vec::new(),Vec::new());
 let result=host.write_selected_registry_check_with_selftests_from_caller(request.clone(),FullRegistryCheckOptions{raw:true,unused:false,..Default::default()},&["derived_reads".into()],None,&mut diagnostics,&mut report).unwrap();assert!(matches!(result,dmbc::runner_host::SelftestedRegistryCheck::Checked{selftests_failed:0,..}));let text=String::from_utf8(report).unwrap();assert!(text.contains("derived_reads"));assert!(!text.contains("selftest FAILED:"));let diagnostics=String::from_utf8(diagnostics).unwrap();assert_eq!(diagnostics.matches("OUTER_NATIVE_SELFTEST_NOTICE").count(),1,"parent actual diagnostic chronology: {diagnostics}");assert!(!diagnostics.contains("native-selftest-"));
 let(mut later_diagnostics,mut later_report)=(Vec::new(),Vec::new());host.write_selected_registry_check(request,FullRegistryCheckOptions{raw:true,unused:false,..Default::default()},&["derived_reads".into()],&mut later_diagnostics,&mut later_report).unwrap();assert_eq!(later_report,text.as_bytes());assert_eq!(later_diagnostics,diagnostics.as_bytes());no_runtime_products(&root);no_runtime_products(&cache);
}

#[test]
#[ignore="private native IPC; run exact outside Cargo under dm_compile machine slot"]
fn actual_resident_selftest_mode_binds_caller_failure_and_does_not_coalesce_no_selftest(){
 use std::{ffi::OsString,time::Duration};
 let(root,cache,_)=fixture("native-resident-selftest-mode","/proc/probe()\n    return 0\n");let changed=dq_analyze::ui_selftest_policy::DISPATCHER_FIXTURE.replace("length(raw) > 64","length(raw) > 1");put(&root,dq_analyze::ui_actions_policy::DISPATCHER,changed);
 let transport_root=scratch::dir("native-resident-selftest-transport");let transport=selected_native_transport::LibraryTransport{root:&transport_root,namespace:format!("native-resident-selftests-{}",std::process::id())};
 let options=FullRegistryCheckOptions{raw:true,unused:false,..Default::default()};let selection=dq_analyze::full_registry_check_selection_wire::SelectionBinding::for_selectors(&["ui_actions".into()]).unwrap();
 for selftests in[true,false]{
  let mut args=vec![OsString::from("analyze-full-check"),OsString::from("--workspace"),root.as_os_str().to_owned(),OsString::from("--raw"),OsString::from("--no-unused"),OsString::from("--lint"),OsString::from("ui_actions")];if !selftests{args.push("--no-selftest".into());}let args=args.iter().map(OsString::as_os_str).collect::<Vec<_>>();
  let actual=transport.run_program_in(Path::new(env!("CARGO_BIN_EXE_dmbc")),&args,Duration::from_secs(330),&root).unwrap();assert!(matches!(actual.status.code(),Some(0|1)),"{}",String::from_utf8_lossy(&actual.stderr));assert!(actual.stderr.is_empty(),"{}",String::from_utf8_lossy(&actual.stderr));
  let end=actual.stdout.iter().take(dq_analyze::selected_exclusions_wire::MAX_HEADER).position(|byte|*byte==b'\n').unwrap();let terminal:dq_analyze::full_registry_check_wire::Terminal=serde_json::from_slice(&actual.stdout[..end]).unwrap();terminal.require_selftests(options,selection,selftests).unwrap();assert_eq!(terminal.clean,actual.status.code()==Some(0));
  let payload=&actual.stdout[end+1..];let diagnostic_len=usize::try_from(terminal.diagnostics.as_ref().map_or(0,|seal|seal.length)).unwrap();let report_len=usize::try_from(terminal.report.length).unwrap();assert_eq!(diagnostic_len.checked_add(report_len).unwrap(),payload.len());let(diagnostics,report)=payload.split_at(diagnostic_len);if let Some(seal)=terminal.diagnostics{assert_eq!(seal.hash.0,xxhash_rust::xxh3::xxh3_128(diagnostics));}else{assert!(diagnostics.is_empty());}assert_eq!(terminal.report.hash.0,xxhash_rust::xxh3::xxh3_128(report));let report=String::from_utf8_lossy(report);
  if selftests{let receipt=terminal.selftests.unwrap();assert_eq!((receipt.completed,receipt.failed),(1,1));assert!(!terminal.clean);assert!(report.contains("selftest FAILED: ui_actions: the live ui_action_key() no longer matches"));assert!(report.contains("ui_actions --selftest"));}else{assert!(terminal.selftests.is_none());assert!(!report.contains("selftest FAILED:"));assert!(!report.contains("ui_actions --selftest"));}
 }
 no_runtime_products(&root);no_runtime_products(&cache);
}

#[path="../../../shared/test_native_transport.rs"]mod baseline_native_transport;
#[test]#[ignore="actual resident baseline IPC; parent runs bounded focused target"]
fn actual_resident_baseline_update_uses_same_daemon_and_seals_real_committed_report(){
 use std::{ffi::OsStr,time::Duration};use dq_analyze::{native_baseline_update_wire::Terminal,selected_exclusions_wire::MAX_HEADER};
 let(root,_,build)=fixture("native-baseline-resident","/proc/probe()\n    return 0\n");let request=dmbc::runner_host::BaselineUpdateRequest{build,mode:dq_analyze::native_baseline_update_wire::Mode::Update,no_gen:true,selectors:Vec::new()};
 let mut initial=BuildHost::default();initial.update_native_baselines(request,&mut Vec::new(),&mut Vec::new()).unwrap();drop(initial);
 let transport_root=fs::canonicalize(scratch::dir("native-baseline-resident-transport")).unwrap();let transport=baseline_native_transport::LibraryTransport{root:&transport_root,namespace:format!("baseline-resident-{}",std::process::id())};let program=Path::new(env!("CARGO_BIN_EXE_dmbc"));let args=[OsStr::new("analyze-baseline-update"),OsStr::new("--workspace"),root.as_os_str(),OsStr::new("--no-gen")];
 let decode=|bytes:&[u8]|{let end=bytes.iter().take(MAX_HEADER).position(|b|*b==b'\n').expect("bounded actual terminal");let t:Terminal=serde_json::from_slice(&bytes[..end]).unwrap();t.require(&root,dq_analyze::native_baseline_update_wire::Mode::Update,true,dq_analyze::full_registry_check_selection_wire::SelectionBinding::for_selectors(&[]).unwrap()).unwrap();let payload=&bytes[end+1..];let dn=usize::try_from(t.diagnostics.as_ref().map_or(0,|s|s.length)).unwrap();let rn=usize::try_from(t.report.length).unwrap();assert_eq!(dn.checked_add(rn),Some(payload.len()));let(d,r)=payload.split_at(dn);if let Some(s)=t.diagnostics{assert_eq!(s.hash.0,xxhash_rust::xxh3::xxh3_128(d));}assert_eq!(t.report.hash.0,xxhash_rust::xxh3::xxh3_128(r));assert!(r.ends_with(b"\n"));t};
 let pid=||{let mut ids=Vec::new();for entry in fs::read_dir(transport_root.join("daemon/live")).unwrap(){let p=entry.unwrap().path();if p.extension()==Some(OsStr::new("json")){let row:serde_json::Value=serde_json::from_slice(&fs::read(p).unwrap()).unwrap();ids.push(row["pid"].as_u64().unwrap());}}assert_eq!(ids.len(),1);ids[0]};
 let first=transport.run_program_with_trace(program,&args,Duration::from_secs(300),true).unwrap();assert_eq!(first.status.code(),Some(0),"{}",String::from_utf8_lossy(&first.stderr));assert!(first.stderr.is_empty(),"operational logs remain in lifecycle output");let a=decode(&first.stdout);assert_eq!(a.committed_files,0);let first_pid=pid();
 let meta=dq_analyze::engine_layering_policy::Layer::Library.metadata();let dq_analyze::lint::Policy::Sites{baseline,..}=meta.policy else{panic!("actual library baseline metadata")};let path=root.join(baseline);let before=fs::read(&path).unwrap();let mut old=before.clone();old.extend_from_slice(b"library_layering\tcode/gone.dm\tremoved fixture source\n");fs::write(&path,old).unwrap();
 let second=transport.run_program(program,&args,Duration::from_secs(300)).unwrap();assert_eq!(second.status.code(),Some(0),"{}",String::from_utf8_lossy(&second.stderr));assert!(second.stderr.is_empty());let b=decode(&second.stdout);assert_eq!(b.committed_files,1);assert_eq!(pid(),first_pid,"same resident native daemon handles actual baseline changes");assert_eq!(fs::read(path).unwrap(),before);no_runtime_products(&root);
}

#[test]fn actual_selected_cli_changed_filter_judges_the_same_raw_findings_and_timing_keeps_typed_result_order(){
 let(root,cache,request)=fixture("native-check-cli-changed","/proc/probe()\n    spawn(0)\n        return 0\n");let mut host=BuildHost::default();let options=FullRegistryCheckOptions{unused:false,..Default::default()};let selectors=vec!["scheduler".into()];let mut requested=dq_analyze::native_check_cli_wire::Request{changed:Some(vec![]),timing:true,timing_only:false,allow_usage:false};let(mut diagnostics,mut report,mut usage)=(Vec::new(),Vec::new(),Vec::new());
 let absent=host.write_selected_registry_check_with_cli_observations(request.clone(),options,&selectors,false,None,&requested,&mut diagnostics,&mut report,&mut usage).unwrap();assert!(absent.clean);let text=String::from_utf8(std::mem::take(&mut report)).unwrap();assert!(text.contains("-- native CHECK timing")&&text.contains("raw scans"));assert!(text.find("-- native CHECK timing").unwrap()<text.find("Ratchet lints passed").unwrap());assert!(usage.is_empty());
 requested.changed=Some(vec!["code/probe.dm".into()]);let present=host.write_selected_registry_check_with_cli_observations(request.clone(),options,&selectors,false,None,&requested,&mut diagnostics,&mut report,&mut usage).unwrap();assert!(!present.clean);let text=String::from_utf8(std::mem::take(&mut report)).unwrap();assert!(text.contains("scheduler"));assert!(text.find("-- native CHECK timing").unwrap()<text.find("Ratchet lints failed").unwrap());
 requested.timing_only=true;let measured=host.write_selected_registry_check_with_cli_observations(request,options,&selectors,false,None,&requested,&mut diagnostics,&mut report,&mut usage).unwrap();assert!(!measured.clean,"timing command output must not falsify the actual policy verdict");let text=String::from_utf8(report).unwrap();assert!(text.contains("-- native CHECK timing"));assert!(!text.contains("Ratchet lints")&&!text.contains("spawn(0)"));no_runtime_products(&root);no_runtime_products(&cache);
}
#[test]fn actual_selected_cli_allow_usage_keeps_original_digest_rows_first_output_io_and_same_host_recovery(){
 use std::io::{self,Write};struct Stop;impl Write for Stop{fn write(&mut self,_:&[u8])->io::Result<usize>{Err(io::Error::from_raw_os_error(1450))}fn flush(&mut self)->io::Result<()>{panic!("no later flush after first usage output IO")}}
 let source="/proc/probe()\n    spawn(0) // ALLOW(scheduler): world.Export() is a blocking external call\n        return 0\n";let(root,cache,request)=fixture("native-check-cli-usage",source);let mut host=BuildHost::default();let options=FullRegistryCheckOptions{unused:false,..Default::default()};let selectors=vec!["scheduler".into()];let requested=dq_analyze::native_check_cli_wire::Request{changed:None,timing:false,timing_only:false,allow_usage:true};let(mut diagnostics,mut report,mut usage)=(Vec::new(),Vec::new(),Vec::new());
 let error=host.write_selected_registry_check_with_cli_observations(request.clone(),options,&selectors,false,None,&requested,&mut diagnostics,&mut report,&mut Stop).unwrap_err();assert_eq!(error.downcast_ref::<io::Error>().unwrap().raw_os_error(),Some(1450));assert!(report.is_empty(),"usage IO occurs before completed report delivery");
 let completed=host.write_selected_registry_check_with_cli_observations(request,options,&selectors,false,None,&requested,&mut diagnostics,&mut report,&mut usage).unwrap();assert!(completed.clean);assert_eq!(String::from_utf8(usage).unwrap(),"scheduler\ta9727e5f29d27253f5bda6cfb220b948931ceef9\t2\n");assert!(!report.is_empty());no_runtime_products(&root);no_runtime_products(&cache);
}
#[test]fn actual_selected_cli_empty_usage_is_completed_and_stale_same_stamp_source_still_reprepares(){
 let(root,cache,mut request)=fixture("native-check-cli-empty-usage","/proc/probe()\n    return 0\n");request.no_cache=false;let mut host=BuildHost::default();let options=FullRegistryCheckOptions{unused:false,..Default::default()};let selectors=vec!["scheduler".into()];let requested=dq_analyze::native_check_cli_wire::Request{changed:None,timing:true,timing_only:false,allow_usage:true};let(mut diagnostics,mut report,mut usage)=(Vec::new(),Vec::new(),Vec::new());
 assert!(host.write_selected_registry_check_with_cli_observations(request.clone(),options,&selectors,false,None,&requested,&mut diagnostics,&mut report,&mut usage).unwrap().clean);assert!(usage.is_empty());assert!(!report.is_empty());report.clear();let path=root.join("code/probe.dm");let stamp=fs::metadata(&path).unwrap().modified().unwrap();let changed="/proc/probe()\n    spawn(0)\n";assert_eq!(fs::metadata(&path).unwrap().len(),changed.len()as u64);fs::write(&path,changed).unwrap();let file=fs::OpenOptions::new().write(true).open(&path).unwrap();file.set_times(fs::FileTimes::new().set_modified(stamp)).unwrap();drop(file);
 assert!(!host.write_selected_registry_check_with_cli_observations(request,options,&selectors,false,None,&requested,&mut diagnostics,&mut report,&mut usage).unwrap().clean);assert!(usage.is_empty());assert!(String::from_utf8(report).unwrap().contains("Ratchet lints failed"));no_runtime_products(&root);no_runtime_products(&cache);
}

#[test]
#[ignore="private native framed IPC; run exact outside Cargo under dm_compile machine slot"]
fn actual_resident_cli_filters_usage_and_same_stamp_change_bind_all_three_payloads(){
 use std::{ffi::OsString,io,time::Duration};
 struct Metadata;impl dq_analyze::policy_finish::admitted::Work for Metadata{fn checkpoint(&self)->io::Result<()>{Ok(())}fn reserve(&self,bytes:usize)->io::Result<()>{if bytes>20*1024*1024{Err(self.overflow())}else{Ok(())}}fn overflow(&self)->io::Error{io::ErrorKind::OutOfMemory.into()}}
 let source="/proc/probe()\n    spawn(0) // ALLOW(scheduler): world.Export() is a blocking external call\n        return 0\n";
 let(root,cache,_)=fixture("native-resident-cli-observations",source);let transport_root=scratch::dir("native-resident-cli-observations-transport");let transport=selected_native_transport::LibraryTransport{root:&transport_root,namespace:format!("native-resident-cli-observations-{}",std::process::id())};
 let selectors=vec!["scheduler".into()];let selected=dq_analyze::full_registry_check_selection_wire::SelectionBinding::for_selectors(&selectors).unwrap();let options=FullRegistryCheckOptions{unused:false,..Default::default()};
 let arguments=vec![OsString::from("analyze-full-check"),OsString::from("--workspace"),root.as_os_str().to_owned(),OsString::from("--no-selftest"),OsString::from("--no-unused"),OsString::from("--lint"),OsString::from("scheduler"),OsString::from("--cli-stdin")];let arguments=arguments.iter().map(OsString::as_os_str).collect::<Vec<_>>();
 let run=|requested:&dq_analyze::native_check_cli_wire::Request|{
  let frame=dq_analyze::native_check_cli_wire::encode_request(requested,&Metadata).unwrap();let actual=transport.run_program_with_input(Path::new(env!("CARGO_BIN_EXE_dmbc")),&arguments,Duration::from_secs(120),&frame).unwrap();assert!(matches!(actual.status.code(),Some(0|1)),"{}",String::from_utf8_lossy(&actual.stderr));assert!(actual.stderr.is_empty(),"{}",String::from_utf8_lossy(&actual.stderr));
  let end=actual.stdout.iter().take(dq_analyze::selected_exclusions_wire::MAX_HEADER).position(|byte|*byte==b'\n').expect("actual bounded CLI terminal");let terminal:dq_analyze::native_check_cli_wire::Terminal=serde_json::from_slice(&actual.stdout[..end]).unwrap();terminal.require(options,selected,false,requested).unwrap();assert_eq!(terminal.terminal.clean,actual.status.code()==Some(0));
  let diagnostics=usize::try_from(terminal.terminal.diagnostics.as_ref().map_or(0,|seal|seal.length)).unwrap();let report=usize::try_from(terminal.terminal.report.length).unwrap();let usage=usize::try_from(terminal.usage.as_ref().map_or(0,|seal|seal.length)).unwrap();let payload=&actual.stdout[end+1..];assert_eq!(diagnostics.checked_add(report).and_then(|n|n.checked_add(usage)).unwrap(),payload.len(),"no trailing or omitted payload");let(diagnostic_bytes,rest)=payload.split_at(diagnostics);let(report_bytes,usage_bytes)=rest.split_at(report);
  if let Some(seal)=&terminal.terminal.diagnostics{assert_eq!(seal.hash.0,xxhash_rust::xxh3::xxh3_128(diagnostic_bytes));}else{assert!(diagnostic_bytes.is_empty())}assert_eq!(terminal.terminal.report.hash.0,xxhash_rust::xxh3::xxh3_128(report_bytes));if let Some(seal)=&terminal.usage{assert_eq!(seal.hash.0,xxhash_rust::xxh3::xxh3_128(usage_bytes));}else{assert!(usage_bytes.is_empty())}
  (terminal,report_bytes.to_vec(),usage_bytes.to_vec())
 };
 let usage_request=dq_analyze::native_check_cli_wire::Request{changed:None,timing:false,timing_only:false,allow_usage:true};let(terminal,_,usage)=run(&usage_request);assert!(terminal.terminal.clean);assert_eq!(usage,b"scheduler\ta9727e5f29d27253f5bda6cfb220b948931ceef9\t2\n");
 let source_path=root.join("code/probe.dm");fs::write(&source_path,"/proc/probe()\n    spawn(0)\n").unwrap();let requested=dq_analyze::native_check_cli_wire::Request{changed:Some(vec![]),timing:true,timing_only:false,allow_usage:false};let(absent,report,usage)=run(&requested);assert!(absent.terminal.clean);assert!(usage.is_empty());assert!(String::from_utf8_lossy(&report).contains("-- native CHECK timing"));
 let mut present=requested.clone();present.changed=Some(vec!["code/probe.dm".into()]);assert!(absent.require(options,selected,false,&present).is_err(),"an actual empty-filter terminal cannot satisfy a different requested filter");let(failing,report,_)=run(&present);assert!(!failing.terminal.clean);assert!(String::from_utf8_lossy(&report).contains("Ratchet lints failed"));
 let stamp=fs::metadata(&source_path).unwrap().modified().unwrap();let clean="/proc/probe()\n    return 0\n";assert_eq!(fs::metadata(&source_path).unwrap().len(),clean.len()as u64);fs::write(&source_path,clean).unwrap();let file=fs::OpenOptions::new().write(true).open(&source_path).unwrap();file.set_times(fs::FileTimes::new().set_modified(stamp)).unwrap();drop(file);let(recovered,_,_)=run(&present);assert!(recovered.terminal.clean,"same stamp/length must still consume actual changed source bytes");no_runtime_products(&root);no_runtime_products(&cache);
}

#[test]
#[ignore="actual thin client plus native resident IPC; Root must bind DQ_NATIVE_CHECK_TEST_CLIENT and its XXH3 to the actual client artifact receipt"]
fn actual_thin_check_appends_verified_usage_then_preserves_real_output_failure_and_recovers(){
 use std::{ffi::OsString,time::Duration};
 let client=PathBuf::from(std::env::var_os("DQ_NATIVE_CHECK_TEST_CLIENT").expect("Root must supply actual built analyze-native artifact"));assert!(client.is_absolute()&&client.is_file());let expected=std::env::var("DQ_NATIVE_CHECK_TEST_CLIENT_XXH3").expect("Root must bind actual client image bytes");let image=||format!("{:032x}",xxhash_rust::xxh3::xxh3_128(&fs::read(&client).unwrap()));assert_eq!(image(),expected);
 let source="/proc/probe()\n    spawn(0) // ALLOW(scheduler): world.Export() is a blocking external call\n        return 0\n";let(root,cache,_)=fixture("native-real-thin-usage",source);let transport_root=scratch::dir("native-real-thin-usage-transport");let transport=selected_native_transport::LibraryTransport{root:&transport_root,namespace:format!("native-real-thin-usage-{}",std::process::id())};let usage=transport_root.join("allow-usage.tsv");fs::write(&usage,b"existing actual output\n").unwrap();
 let arguments=vec![OsString::from("check"),OsString::from("--native-full-registry"),OsString::from("--native-dmbc"),OsString::from(env!("CARGO_BIN_EXE_dmbc")),OsString::from("--root"),root.as_os_str().to_owned(),OsString::from("--no-selftest"),OsString::from("--lint"),OsString::from("scheduler")];let arguments=arguments.iter().map(OsString::as_os_str).collect::<Vec<_>>();
 let row=b"scheduler\ta9727e5f29d27253f5bda6cfb220b948931ceef9\t2\n";let mut expected_output=b"existing actual output\n".to_vec();
 for _ in 0..2{let actual=transport.run_program_with_usage(&client,&arguments,Duration::from_secs(120),&usage).unwrap();assert_eq!(actual.status.code(),Some(0),"{}",String::from_utf8_lossy(&actual.stderr));assert!(actual.stderr.is_empty());assert!(String::from_utf8_lossy(&actual.stdout).contains("Ratchet lints passed"));expected_output.extend_from_slice(row);assert_eq!(fs::read(&usage).unwrap(),expected_output);assert_eq!(image(),expected);}
 let denied=transport_root.join("usage-is-an-actual-directory");fs::create_dir(&denied).unwrap();let failure=transport.run_program_with_usage(&client,&arguments,Duration::from_secs(120),&denied).unwrap();assert_eq!(failure.status.code(),Some(2));assert!(failure.stdout.is_empty(),"actual usage open failure must precede completed report output");assert!(!failure.stderr.is_empty(),"actual output error must be visible");assert_eq!(fs::read(&usage).unwrap(),expected_output,"failed output target must not append elsewhere");
 let recovered=transport.run_program_with_usage(&client,&arguments,Duration::from_secs(120),&usage).unwrap();assert_eq!(recovered.status.code(),Some(0),"{}",String::from_utf8_lossy(&recovered.stderr));assert!(recovered.stderr.is_empty());expected_output.extend_from_slice(row);assert_eq!(fs::read(&usage).unwrap(),expected_output);assert_eq!(image(),expected);no_runtime_products(&root);no_runtime_products(&cache);
}

#[test]fn actual_selected_model_cli_timing_records_the_real_selected_producer_without_checker_demand(){
 let(root,cache,request)=fixture("native-selected-model-cli-timing","/datum/semantic_probe\n    var/value = 1\n/datum/semantic_probe/proc/not_selected()\n    return no_such_global_proc()\n");fs::remove_file(root.join("deepquarry.dme")).unwrap();fs::create_dir_all(root.join("SpacemanDMM.toml")).unwrap();let meta=dq_analyze::engine_layering_policy::Layer::Library.metadata();let baseline=match meta.policy{dq_analyze::lint::Policy::Sites{baseline,..}|dq_analyze::lint::Policy::Ceilings{baseline,..}=>baseline,_=>panic!("actual unrelated baseline role")};fs::create_dir_all(root.join(baseline)).unwrap();
 let mut host=BuildHost::default();let(mut diagnostics,mut report,mut usage)=(Vec::new(),Vec::new(),Vec::new());let requested=dq_analyze::native_check_cli_wire::Request{changed:None,timing:true,timing_only:false,allow_usage:false};let actual=host.write_selected_registry_check_with_cli_observations(request,FullRegistryCheckOptions{unused:false,..Default::default()},&["sem/reads".into()],false,None,&requested,&mut diagnostics,&mut report,&mut usage).unwrap();assert!(actual.clean);let text=String::from_utf8(report).unwrap();assert!(text.contains("reads:")&&text.contains("sem/reads")&&text.contains("-- native CHECK timing"),"actual selected model callback must produce its timing row: {text}");assert!(text.find("-- native CHECK timing").unwrap()<text.find("Ratchet lints passed").unwrap());assert!(!text.contains("no_such_global_proc"),"unselected Checker must remain undemanded");assert!(diagnostics.is_empty()&&usage.is_empty());no_runtime_products(&root);no_runtime_products(&cache);
}

#[test]fn actual_standalone_native_selftest_validates_scopes_without_parsing_the_outer_project_or_running_policies(){
 let(root,cache,request)=fixture("native-standalone-selftest","/proc/outer()
    sleep(1)
");put(&root,"deepquarry.dme","#error ACTUAL_OUTER_MUST_NOT_BE_PARSED
");let mut host=BuildHost::default();let mut out=Vec::new();
 assert!(host.write_standalone_selftests(request.clone(),&["dcs".into()],None,&mut out).unwrap());let text=String::from_utf8(out).unwrap();assert!(text.starts_with("selftest ok: dcs "),"{text}");assert!(!text.contains("ACTUAL_OUTER")&&!text.contains("Ratchet lints")&&!text.contains("allow annotations:"));no_runtime_products(&root);no_runtime_products(&cache);
 put(&root,"tools/ci/lint_scopes.toml","[actual malformed TOML");let mut withheld=Vec::new();assert!(host.write_standalone_selftests(request.clone(),&["dcs".into()],None,&mut withheld).is_err());assert!(withheld.is_empty(),"startup config refusal precedes actual callback transcript");
 put(&root,"tools/ci/lint_scopes.toml",report_configuration::with_overlay(""));let mut recovered=Vec::new();assert!(host.write_standalone_selftests(request,&["dcs".into()],None,&mut recovered).unwrap());assert_eq!(recovered.as_slice(),text.as_bytes());
}
#[test]fn actual_standalone_selftest_output_1450_wins_before_later_config_change_and_same_host_recovers(){
 struct Stop(PathBuf);impl std::io::Write for Stop{fn write(&mut self,_:&[u8])->std::io::Result<usize>{fs::write(&self.0,"changed after actual output entry")?;Err(std::io::Error::from_raw_os_error(1450))}fn flush(&mut self)->std::io::Result<()>{panic!("first writer IO must stop before later flush")}}
 let(root,_,request)=fixture("native-standalone-first-output","/proc/unused()
    return 1
");let mut host=BuildHost::default();let error=host.write_standalone_selftests(request.clone(),&["dcs".into()],None,&mut Stop(root.join("tools/ci/lint_scopes.toml"))).unwrap_err();assert_eq!(error.downcast_ref::<std::io::Error>().unwrap().raw_os_error(),Some(1450));put(&root,"tools/ci/lint_scopes.toml",report_configuration::with_overlay(""));assert!(host.write_standalone_selftests(request,&["dcs".into()],None,&mut Vec::new()).unwrap());
}

#[test]
#[ignore="private native IPC; run exact outside Cargo under dm_compile machine slot"]
fn actual_resident_standalone_selftest_seals_callback_only_output_and_recovers_config_errors(){
 use std::{ffi::{OsString,OsStr},time::Duration};
 let(root,cache,_)=fixture("resident-standalone-callbacks","/proc/unused()
    return 0
");put(&root,"deepquarry.dme","#error OUTER_PROJECT_MUST_NOT_PARSE
");let transport_root=scratch::dir("resident-standalone-transport");let transport=selected_native_transport::LibraryTransport{root:&transport_root,namespace:format!("resident-standalone-{}",std::process::id())};
 let args=[OsString::from("analyze-selftest"),OsString::from("--workspace"),root.as_os_str().to_owned(),OsString::from("--lint"),OsString::from("dcs")];let borrowed=args.iter().map(OsString::as_os_str).collect::<Vec<&OsStr>>();
 let actual=transport.run_program(Path::new(env!("CARGO_BIN_EXE_dmbc")),&borrowed,Duration::from_secs(90)).unwrap();assert_eq!(actual.status.code(),Some(0),"{}",String::from_utf8_lossy(&actual.stderr));assert!(actual.stderr.is_empty());
 let end=actual.stdout.iter().take(dq_analyze::selected_exclusions_wire::MAX_HEADER).position(|b|*b==b'\n').unwrap();let terminal:dq_analyze::native_selftest_wire::Terminal=serde_json::from_slice(&actual.stdout[..end]).unwrap();let binding=dq_analyze::full_registry_check_selection_wire::SelectionBinding::for_selectors(&["dcs".into()]).unwrap();terminal.require(binding).unwrap();assert_eq!((terminal.selected,terminal.completed,terminal.failed),(1,1,0));let payload=&actual.stdout[end+1..];assert_eq!(terminal.report.length,payload.len()as u64);assert_eq!(terminal.report.hash.0,xxhash_rust::xxh3::xxh3_128(payload));assert!(payload.starts_with(b"selftest ok: dcs "));assert!(!String::from_utf8_lossy(payload).contains("Ratchet lints"));
 put(&root,"tools/ci/lint_scopes.toml","[actual invalid");let failed=transport.run_program(Path::new(env!("CARGO_BIN_EXE_dmbc")),&borrowed,Duration::from_secs(90)).unwrap();assert_eq!(failed.status.code(),Some(2));assert!(failed.stdout.is_empty(),"no completed terminal on actual malformed scopes");put(&root,"tools/ci/lint_scopes.toml",report_configuration::with_overlay(""));let healthy=transport.run_program(Path::new(env!("CARGO_BIN_EXE_dmbc")),&borrowed,Duration::from_secs(90)).unwrap();assert_eq!(healthy.status.code(),Some(0));assert_eq!(healthy.stdout,actual.stdout);no_runtime_products(&root);no_runtime_products(&cache);
}

// Actual selected native policy producers, not a legacy scanner-only scope test.
// Atom lifecycle and the existing radio CLEAN_TYPES entry deliberately select these bodies.
// Plain datum Initialize is a manual callback; arbitrary non-latent types are not judged.
// Each cold finding requires the repaired per-page native-pattern branch;
// the edit and second request use the SAME retained native host.
#[test]fn actual_selected_decl_sibling_page_scratch_keeps_findings_and_same_host_edit_current(){
 let source="/obj/item/radio\n    var/icon_state\n/obj/item/radio/Initialize()\n    icon_state = \"ready\"\n    return\n";
 let(root,cache,request)=fixture("selected-decl-sibling-pages",source);let mut host=BuildHost::default();let(mut diagnostics,mut report)=(Vec::new(),Vec::new());let options=FullRegistryCheckOptions{raw:true,unused:false,..Default::default()};
 let clean=host.write_selected_registry_check(request.clone(),options,&["decl".into()],&mut diagnostics,&mut report).unwrap();let text=String::from_utf8_lossy(&report);assert!(!clean,"real declaration visual assignment must be a finding: {text}");assert!(text.contains("init_visuals"),"{text}");assert!(diagnostics.is_empty());
 put(&root,"code/probe.dm","/obj/item/radio\n    var/icon_state\n/obj/item/radio/Initialize()\n    return\n");diagnostics.clear();report.clear();assert!(host.write_selected_registry_check(request,options,&["decl".into()],&mut diagnostics,&mut report).unwrap(),"same host must invalidate original declaration source after edit: {}",String::from_utf8_lossy(&report));assert!(diagnostics.is_empty());no_runtime_products(&root);no_runtime_products(&cache);
}
#[test]fn actual_selected_lifecycle_sibling_page_scratch_keeps_findings_and_same_host_edit_current(){
 let source="/obj/item/radio\n/obj/item/radio/Initialize()\n    START_PROCESSING(src)\n    return\n";
 let(root,cache,request)=fixture("selected-lifecycle-sibling-pages",source);let mut host=BuildHost::default();let(mut diagnostics,mut report)=(Vec::new(),Vec::new());let options=FullRegistryCheckOptions{raw:true,unused:false,..Default::default()};
 let clean=host.write_selected_registry_check(request.clone(),options,&["lifecycle".into()],&mut diagnostics,&mut report).unwrap();let text=String::from_utf8_lossy(&report);assert!(!clean,"real processing-start initializer must be a finding: {text}");assert!(text.contains("processing_start"),"{text}");assert!(diagnostics.is_empty());
 put(&root,"code/probe.dm","/obj/item/radio\n/obj/item/radio/Initialize()\n    return\n");diagnostics.clear();report.clear();assert!(host.write_selected_registry_check(request,options,&["lifecycle".into()],&mut diagnostics,&mut report).unwrap(),"same host must invalidate lifecycle source after edit: {}",String::from_utf8_lossy(&report));assert!(diagnostics.is_empty());no_runtime_products(&root);no_runtime_products(&cache);
}

#[test]fn actual_native_unicode_singleton_range_emission_preserves_captures_and_first_refusal(){
 use dq_analyze::native_pattern::{self,Spec,Mode,admission::{Admission,Hook,Refused}};
 use std::sync::{Arc,Mutex,atomic::{AtomicBool,AtomicUsize,Ordering}};
 struct Work{used:AtomicUsize,fail:AtomicBool,first:Mutex<Option<std::io::Error>>}
 impl Admission for Work{
  fn checkpoint(&self)->Result<(),Refused>{if self.fail.load(Ordering::Acquire){self.first.lock().unwrap().get_or_insert_with(||std::io::Error::from_raw_os_error(1450));Err(Refused)}else{Ok(())}}
  fn reserve(&self,bytes:usize)->Result<(),Refused>{self.checkpoint()?;self.used.fetch_update(Ordering::AcqRel,Ordering::Acquire,|n|n.checked_add(bytes).filter(|n|*n<=8<<20)).map(|_|()).map_err(|_|{self.first.lock().unwrap().get_or_insert_with(||std::io::ErrorKind::OutOfMemory.into());Refused})}
  fn overflow(&self)->Refused{self.first.lock().unwrap().get_or_insert_with(||std::io::ErrorKind::OutOfMemory.into());Refused}
  fn allocation_failed(&self)->Refused{self.overflow()}
 }
 let work=Arc::new(Work{used:AtomicUsize::new(0),fail:AtomicBool::new(false),first:Mutex::new(None)});let hook=Hook(Some(work.clone()));
 let pattern=r"(?m)^(/\w[\w/ ]*?)/(attackby|attack_hand|attack_self|click_alt)\(";let original=dq_analyze::pat::Pat::new(pattern);let actual=native_pattern::compile(Spec{pattern,mode:Mode::Search},&hook).unwrap();
 for text in["/obj/attackby(","/datum/\u{394}/attack_hand(","prefix /obj/attackby(","/\u{e9}/attack_self(","/obj/other(","/obj/other(\n/datum/attack_hand("]{
  let expected=original.find(text).map(|m|(m.start,m.end));assert_eq!(actual.find_at(text,0,&hook).unwrap(),expected,"same Unicode forward UTF8 graph on {text:?}");
  let expected=original.captures(text).map(|caps|(0..actual.capture_len()).map(|i|caps.get(i).map(|_|(caps.start(i),caps.end(i)))).collect::<Vec<_>>());assert_eq!(actual.captures_at(text,0,&hook).unwrap(),expected,"all same original capture ranges");
 }
 work.fail.store(true,Ordering::Release);assert!(actual.find_at("/obj/attackby(",0,&hook).is_err(),"operational refusal never becomes semantic no-match");assert_eq!(work.first.lock().unwrap().take().unwrap().raw_os_error(),Some(1450));
}

#[test]fn actual_full_report_retains_prior_patterns_and_unicode_handler_under_same_parent_arena(){
 let(root,cache,request)=fixture("full-report-builder-owned-utf8-keys","/obj/probe/attack_hand(mob/user)\n    return 0\n");let mut host=BuildHost::default();let(mut diagnostics,mut report)=(Vec::new(),Vec::new());let mut observed=0;
 let clean=host.write_full_registry_check_with_input_observation(request,FullRegistryCheckOptions{raw:true,ci:false,unused:false,..Default::default()},|_|{observed+=1;Ok(())},&mut diagnostics,&mut report).unwrap();
 assert_eq!(observed,1);assert!(!clean);let text=String::from_utf8(report).unwrap();assert!(text.contains("/obj/probe/attack_hand"),"actual Unicode-enabled handler producer runs after prior retained patterns: {text}");no_runtime_products(&root);no_runtime_products(&cache);
}

#[test]fn actual_original_mutating_control_callbacks_keep_authentic_enclosing_header_effect_origins(){
 for(label,header,column)in[
  ("for-step","for(var/i=0; i<2; global_sink=1)",5),
  ("while-condition","while(global_sink=1)",5),
  // Original IfArm is located at the consumed opening parenthesis, column7.
  ("if-condition","if(global_sink=1)",7),
  ("for-iterable","for(var/value in global_sink=list())",5),
  ("for-initializer","for(global_sink=1; global_sink<2; global_sink++)",5),
 ]{
  let source=format!("var/global_sink=0\n/proc/probe()\n    set SpacemanDMM_should_be_pure=1\n    {header}\n        return 0\n");
  let(root,cache,_request)=fixture(&format!("native-original-control-anchor-{label}"),&source);
  // The real standalone checker uses the same Original source/effect producer;
  // this regression does not require unrelated full-registry policy producers.
  let request=dmbc::native_checker::Request{project:root.join("deepquarry.dme"),configuration:None,cache_root:cache.clone(),workers:1,timeout_seconds:60};
  let mut host=BuildHost::default();let(mut output,mut diagnostics)=(Vec::new(),Vec::new());
  let outcome=dmbc::native_checker::run(request,&mut host,&mut output,&mut diagnostics).unwrap_or_else(|actual|panic!("actual Original control {label} ({header}) failed: {actual:?}"));
  assert_eq!(outcome.visited_bodies,1,"actual Original BODY evaluated once, {label}");assert_eq!(outcome.exit_code,1,"actual purity refusal, {label}");
  let checker=String::from_utf8(diagnostics).unwrap();assert!(checker.contains("does impure operations"),"actual purity report, {label}: {checker}");
  let effects=checker.lines().filter(|note|note.contains("happens here")).collect::<Vec<_>>();
  assert!(!effects.is_empty(),"the real control mutation must contribute a purity effect, {label}: {checker}");
  // Pinned Base follows carry their own operator locations: ++ is not an
  // assignment and must retain its actual consumed token at column50.
  let mut expected=vec![format!("- 4:{column}: Assignment on purity breaking expression happens here")];
  if label=="for-initializer"{expected.push("- 4:50: operator++ done on non-local var happens here".to_owned());}
  assert_eq!(effects,expected.iter().map(String::as_str).collect::<Vec<_>>(),"actual ordered assignment/header and unary/operator effects, {label}");
  no_runtime_products(&root);no_runtime_products(&cache);
 }
}

#[test]fn actual_original_grouped_assignment_values_keep_nonlocal_write_purity_effects(){
 for(label,statement)in[
  ("global-index-or","return global_sink[key] || (global_sink[key]=value)"),
  ("global-name-or","return global_sink || (global_sink=value)"),
  ("global-name-statement","(global_sink=value)"),
  ("global-call-key-statement","global_sink[length(\"key\")]=value"),
  ("global-nested-index-statement","global_sink[key][key]=value"),
  ("global-index-initializer","var/result=global_sink[key] || (global_sink[key]=value)\n    return result"),
 ]{
  // An untyped global deliberately preserves the pinned Index impurity. A
  // declared /list Index has its own different original policy and is not
  // used as a synthetic expectation of an effect here.
  let source=format!("var/global_sink\n/proc/probe(key,value)\n    set SpacemanDMM_should_be_pure=1\n    {statement}\n");
  let(root,cache,_request)=fixture(&format!("native-original-grouped-write-{label}"),&source);
  let request=dmbc::native_checker::Request{project:root.join("deepquarry.dme"),configuration:None,cache_root:cache.clone(),workers:1,timeout_seconds:60};let mut host=BuildHost::default();let(mut output,mut diagnostics)=(Vec::new(),Vec::new());
  let outcome=dmbc::native_checker::run(request,&mut host,&mut output,&mut diagnostics).unwrap_or_else(|error|panic!("actual grouped assignment {label} failed: {error:?}"));assert_eq!(outcome.visited_bodies,1);assert_eq!(outcome.exit_code,1,"a syntax value receipt cannot grant purity");
  let checker=String::from_utf8(diagnostics).unwrap();assert!(checker.contains("does impure operations"),"actual purity refusal {label}: {checker}");let effects=checker.lines().filter(|line|line.contains("Assignment on purity breaking expression happens here")).collect::<Vec<_>>();assert_eq!(effects.len(),1,"one actual nonlocal LHS write must survive Group/Binary evaluation {label}: {checker}");no_runtime_products(&root);no_runtime_products(&cache);
 }
}


#[test]
fn actual_original_safe_index_value_keys_preserve_ordinary_index_purity_effects() {
    // Pinned Follow::Index(_, expr) visits the key for both Normal and Safe.
    // The syntax receipt grants a value shape, never a purity exemption.
    for (label, key, expected_exit) in [
        ("impure-call", "impure_key()", 1),
        ("nonlocal-postupdate", "global_counter++", 1),
        ("pure-nameof", "nameof(key)", 0),
    ] {
        let mut parity = None;
        for (mode, bracket) in [("ordinary", "["), ("safe", "?[")] {
            let source = format!("var/global_counter=0\n/proc/impure_key()\n    global_counter=1\n    return 0\n/proc/probe(list/values,key)\n    set SpacemanDMM_should_be_pure=1\n    return values{bracket}{key}]\n");
            let (root, cache, _) = fixture(&format!("native-original-index-key-{label}-{mode}"), &source);
            let request = dmbc::native_checker::Request { project: root.join("deepquarry.dme"), configuration: None, cache_root: cache.clone(), workers: 1, timeout_seconds: 60 };
            let mut host = BuildHost::default();
            let (mut output, mut diagnostics) = (Vec::new(), Vec::new());
            let outcome = dmbc::native_checker::run(request, &mut host, &mut output, &mut diagnostics)
                .unwrap_or_else(|error| panic!("actual {mode} key {label}: {error:?}"));
            assert_eq!(outcome.visited_bodies, 2, "both genuine source procedures, {label}/{mode}");
            assert_eq!(outcome.exit_code, expected_exit, "legacy key-effect status, {label}/{mode}");
            let checker = String::from_utf8(diagnostics).unwrap();
            assert!(!checker.contains("undefined") && !checker.contains("unknown"), "no unsupported symbol may substitute for purity, {label}/{mode}: {checker}");
            let effects = checker.lines().filter(|line| line.contains("impure operations") || line.contains("happens here"))
                .map(|line| {
                    // Only the extra '?' shifts a consumed key's source column.
                    // Keep complete diagnostic text and ordering after its location.
                    let start = line.find("/proc/probe").or_else(|| line.find("- "));
                    if let Some(start) = start {
                        let text = &line[start..];
                        if text.starts_with("- ") {
                            return text.splitn(3, ':').nth(2).unwrap_or(text).trim_start().to_owned();
                        }
                        text.to_owned()
                    } else { line.to_owned() }
                }).collect::<Vec<_>>();
            if expected_exit == 0 { assert!(effects.is_empty(), "nameof stays pure: {checker}"); }
            else { assert!(!effects.is_empty(), "actual key impurity survives: {checker}"); }
            if let Some(expected) = &parity { assert_eq!(&effects, expected, "ordered legacy effects, {label}: {checker}"); }
            else { parity = Some(effects); }
            no_runtime_products(&root);
            no_runtime_products(&cache);
        }
    }
}


#[test]
fn actual_original_template_prefix_global_update_keeps_legacy_purity_effect() {
    let mut prior_effect = None;
    for (label, expression) in [("postfix-control", "global_counter++"), ("prefix-value", "++global_counter")] {
        let source = format!("var/global_counter=0\n/proc/probe()\n    set SpacemanDMM_should_be_pure=1\n    return \"#[{expression}]\"\n");
        let (root, cache, _) = fixture(&format!("native-original-template-update-{label}"), &source);
        let request = dmbc::native_checker::Request { project: root.join("deepquarry.dme"), configuration: None, cache_root: cache.clone(), workers: 1, timeout_seconds: 60 };
        let mut host = BuildHost::default();
        let (mut output, mut diagnostics) = (Vec::new(), Vec::new());
        let outcome = dmbc::native_checker::run(request, &mut host, &mut output, &mut diagnostics)
            .unwrap_or_else(|error| panic!("actual template update {label}: {error:?}"));
        assert_eq!(outcome.visited_bodies, 1, "one genuine template body, {label}");
        assert_eq!(outcome.exit_code, 1, "an actual update value cannot grant purity, {label}");
        let checker = String::from_utf8(diagnostics).unwrap();
        assert!(checker.contains("does impure operations"), "actual native purity refusal, {label}: {checker}");
        assert!(!checker.contains("undefined") && !checker.contains("unknown"), "no unsupported-symbol substitute, {label}: {checker}");
        let effects = checker.lines().filter(|line| line.contains("happens here")).collect::<Vec<_>>();
        assert_eq!(effects.len(), 1, "exactly one consumed increment effect, {label}: {checker}");
        let message = effects[0].splitn(3, ':').nth(2).unwrap().trim_start();
        assert_eq!(message, "operator++ done on non-local var happens here", "actual template effect kind, {label}: {checker}");
        if let Some(prior) = &prior_effect { assert_eq!(message, prior, "same legacy postfix/prefix impurity policy"); }
        else { prior_effect = Some(message.to_owned()); }
        no_runtime_products(&root);
        no_runtime_products(&cache);
    }
}


#[test]
fn actual_original_ordinary_omitted_call_slots_keep_checker_values_and_effects() {
    // Pinned ordinary calls preserve positional holes. Checker arguments judge
    // keyword ordering; they do not invent a minimum/maximum arity diagnostic.
    for (label, call, expected_exit, update, keyword) in [
        ("omitted", "slot_sink(1,,3)", 0, false, false),
        ("authored-null", "slot_sink(1,null,3)", 0, false, false),
        ("third-slot-effect", "slot_sink(1,,global_counter++)", 1, true, false),
        ("hole-after-keyword", "slot_sink(first=1,,3)", 1, false, true),
    ] {
        let source = format!("var/global_counter=0\n/proc/slot_sink(first,second,third)\n    set SpacemanDMM_should_be_pure=1\n    return third\n/proc/probe()\n    set SpacemanDMM_should_be_pure=1\n    return {call}\n");
        let (root, cache, _) = fixture(&format!("native-original-omitted-slots-{label}"), &source);
        let request = dmbc::native_checker::Request { project: root.join("deepquarry.dme"), configuration: None, cache_root: cache.clone(), workers: 1, timeout_seconds: 60 };
        let mut host = BuildHost::default();
        let (mut output, mut diagnostics) = (Vec::new(), Vec::new());
        let result = dmbc::native_checker::run(request, &mut host, &mut output, &mut diagnostics)
            .unwrap_or_else(|error| panic!("actual ordinary slots {label}: {error:?}"));
        assert_eq!(result.visited_bodies, 2, "both real declared procedures, {label}");
        assert_eq!(result.exit_code, expected_exit, "actual ordinary slot policy, {label}");
        let checker = String::from_utf8(diagnostics).unwrap();
        assert!(!checker.contains("undefined") && !checker.contains("unknown"), "no missing symbol substitutes for slot behavior, {label}: {checker}");
        assert_eq!(checker.contains("operator++ done on non-local var"), update, "third actual positional argument retains its effect, {label}: {checker}");
        assert_eq!(checker.contains("non-kwargs after kwargs"), keyword, "omission does not erase positional ordering, {label}: {checker}");
        if update { assert_eq!(checker.lines().filter(|line| line.contains("operator++ done on non-local var")).count(), 1, "one real update, {checker}"); }
        if expected_exit == 0 { assert!(checker.trim().is_empty(), "clean ordinary slots: {checker}"); }
        no_runtime_products(&root); no_runtime_products(&cache);
    }
}


#[test]
fn actual_original_member_prefix_value_preserves_existing_nonlocal_update_purity_effect() {
    // Keep this case identity for the recorded failed assumption. Pinned Field
    // lookup returns fresh static_type analysis with no inherited impurity;
    // both pre/post updates of this untyped field therefore have no diagnostic.
    // Existing bare-global update tests retain the separate non-local warning.
    let mut observations = Vec::new();
    for (label, body) in [("legacy-postfix", "global_holder.seq++"), ("prefix-value", "return ++global_holder.seq")] {
        let source = format!("/datum/prefix_holder\n    var/seq=0\nvar/datum/prefix_holder/global_holder\n/proc/probe()\n    set SpacemanDMM_should_be_pure=1\n    {body}\n");
        let (root, cache, _) = fixture(&format!("native-original-member-prefix-{label}"), &source);
        let request = dmbc::native_checker::Request { project: root.join("deepquarry.dme"), configuration: None, cache_root: cache.clone(), workers: 1, timeout_seconds: 60 };
        let mut host = BuildHost::default();let (mut output, mut diagnostics) = (Vec::new(), Vec::new());
        let result = dmbc::native_checker::run(request, &mut host, &mut output, &mut diagnostics)
            .unwrap_or_else(|error| panic!("actual member mutation {label}: {error:?}"));
        assert_eq!(result.visited_bodies, 1);
        let checker = String::from_utf8(diagnostics).unwrap();assert!(!checker.contains("undefined") && !checker.contains("unknown"), "actual defined field, {label}: {checker}");
        observations.push((label, result.exit_code, checker));
        no_runtime_products(&root);no_runtime_products(&cache);
    }
    // Gather both real native observations before checking the legacy policy.
    let mismatches: Vec<_> = observations.iter()
        .filter(|(_, exit, checker)| *exit != 0 || !checker.trim().is_empty())
        .collect();
    assert!(mismatches.is_empty(), "pinned member-field pre/post policy: {mismatches:?}");
    assert_eq!(observations[0].1, observations[1].1, "same pre/post status");
    assert_eq!(observations[0].2, observations[1].2, "same exact diagnostics");
}

#[test]
fn actual_original_unlint_real_setupgenetics_warning_macro_fragment_finishes_checker_traversal(){
 // Focused exact production WARNING invocation plus the real warning proc
 // and macro definitions. The whole physical setupgenetics syntax is tested
 // separately; no invented world declarations grant receiver typing.
 let source=r########"/**
* SpacemanDMM dreamchecker extensions for suite 1.7
* <https://github.com/SpaceManiac/SpacemanDMM/tree/suite-1.7/src/dreamchecker>
*/

#ifdef SPACEMAN_DMM
	#define RETURN_TYPE(X) set SpacemanDMM_return_type = X
	#define SHOULD_CALL_PARENT(X) set SpacemanDMM_should_call_parent = X
	#define UNLINT(X) SpacemanDMM_unlint(X)
	#define SHOULD_NOT_OVERRIDE(X) set SpacemanDMM_should_not_override = X
	#define SHOULD_NOT_SLEEP(X) set SpacemanDMM_should_not_sleep = X
	#define SHOULD_BE_PURE(X) set SpacemanDMM_should_be_pure = X
	#define PRIVATE_PROC(X) set SpacemanDMM_private_proc = X
	#define PROTECTED_PROC(X) set SpacemanDMM_protected_proc = X
	#define CAN_BE_REDEFINED(X) set SpacemanDMM_can_be_redefined = X
	#define VAR_FINAL var/SpacemanDMM_final
	#define VAR_PRIVATE var/SpacemanDMM_private
	#define VAR_PROTECTED var/SpacemanDMM_protected
#else
	#define RETURN_TYPE(X)
	#define SHOULD_CALL_PARENT(X)
	#define UNLINT(X) X
	#define SHOULD_NOT_OVERRIDE(X)
	#define SHOULD_NOT_SLEEP(X)
	#define SHOULD_BE_PURE(X)
	#define PRIVATE_PROC(X)
	#define PROTECTED_PROC(X)
	#define CAN_BE_REDEFINED(X)
	#define VAR_FINAL var
	#define VAR_PRIVATE var
	#define VAR_PROTECTED var
#endif

#define WARNING(MSG) warning("[MSG] in [__FILE__] at line [__LINE__] src: [UNLINT(src)] usr: [usr].")
#define LAZYLEN(L) length(L)
#define DNA_SE_LENGTH 93 // Traitgenes (Expanded from 49 to 84, there have been a considerable expansion of genes. // Upped to 93. NOTE: Ensure it's increased when there is a conflict here! Thanks!
/proc/warning(msg)
	msg = "## WARNING: [msg]"
	boot_noise_note(msg)
	log_world(msg)

/proc/setupgenetics(list/trait_list)
	WARNING("DNA2: Blocks remaining is less than 10. The DNA_SE_LENGTH should be raised in dna.dm.")
"########;
 let(root,cache,_)=fixture("native-original-unlint-setupgenetics",source);
 let request=dmbc::native_checker::Request{project:root.join("deepquarry.dme"),configuration:None,cache_root:cache.clone(),workers:1,timeout_seconds:60};
 let mut host=BuildHost::default();let(mut output,mut diagnostics)=(Vec::new(),Vec::new());
 let outcome=dmbc::native_checker::run(request,&mut host,&mut output,&mut diagnostics).unwrap_or_else(|error|panic!("real setupgenetics WARNING fragment/UNLINT checker traversal: {error:?}"));
 assert_eq!(outcome.visited_bodies,2,"actual warning procedure and focused setupgenetics macro fragment");
 let checker=String::from_utf8(diagnostics).unwrap();assert!(!checker.contains("undefined proc: \"SpacemanDMM_unlint\""),"escape is not an unresolved ordinary proc: {checker}");
 no_runtime_products(&root);no_runtime_products(&cache);
}

#[test]
fn actual_original_unlint_skips_macro_arguments_but_declared_proc_keeps_write_effects(){
 for declared in[false,true]{
  let declaration=if declared{"/proc/SpacemanDMM_unlint(value)\n    set SpacemanDMM_should_be_pure=1\n    return value\n"}else{""};
  let source=format!("var/global_counter=0\n{declaration}/proc/probe()\n    set SpacemanDMM_should_be_pure=1\n    return \"[SpacemanDMM_unlint(global_counter++)]\"\n");
  let(root,cache,_)=fixture(&format!("native-original-unlint-effect-{declared}"),&source);
  let request=dmbc::native_checker::Request{project:root.join("deepquarry.dme"),configuration:None,cache_root:cache.clone(),workers:1,timeout_seconds:60};
  let mut host=BuildHost::default();let(mut output,mut diagnostics)=(Vec::new(),Vec::new());
  let outcome=dmbc::native_checker::run(request,&mut host,&mut output,&mut diagnostics).unwrap_or_else(|error|panic!("actual unlint declaration={declared}: {error:?}"));
  assert_eq!(outcome.visited_bodies,if declared{2}else{1});
  let checker=String::from_utf8(diagnostics).unwrap();
  assert_eq!(checker.contains("does impure operations"),declared,"only genuine declared procedure evaluation visits its argument write: {checker}");
  assert_eq!(checker.lines().filter(|line|line.contains("operator++ done on non-local var happens here")).count(),usize::from(declared),"exactly the pinned argument effect: {checker}");
  assert_eq!(outcome.exit_code,if declared{1}else{0});no_runtime_products(&root);no_runtime_products(&cache);
 }
}

// Exact production declarations/annotations and source bodies; no invented receiver types.
const ACTUAL_REFRESH_LOGICAL_SUPPORT:&str=r########"/**
* SpacemanDMM dreamchecker extensions for suite 1.7
* <https://github.com/SpaceManiac/SpacemanDMM/tree/suite-1.7/src/dreamchecker>
*/

#ifdef SPACEMAN_DMM
	#define RETURN_TYPE(X) set SpacemanDMM_return_type = X
	#define SHOULD_CALL_PARENT(X) set SpacemanDMM_should_call_parent = X
	#define UNLINT(X) SpacemanDMM_unlint(X)
	#define SHOULD_NOT_OVERRIDE(X) set SpacemanDMM_should_not_override = X
	#define SHOULD_NOT_SLEEP(X) set SpacemanDMM_should_not_sleep = X
	#define SHOULD_BE_PURE(X) set SpacemanDMM_should_be_pure = X
	#define PRIVATE_PROC(X) set SpacemanDMM_private_proc = X
	#define PROTECTED_PROC(X) set SpacemanDMM_protected_proc = X
	#define CAN_BE_REDEFINED(X) set SpacemanDMM_can_be_redefined = X
	#define VAR_FINAL var/SpacemanDMM_final
	#define VAR_PRIVATE var/SpacemanDMM_private
	#define VAR_PROTECTED var/SpacemanDMM_protected
#else
	#define RETURN_TYPE(X)
	#define SHOULD_CALL_PARENT(X)
	#define UNLINT(X) X
	#define SHOULD_NOT_OVERRIDE(X)
	#define SHOULD_NOT_SLEEP(X)
	#define SHOULD_BE_PURE(X)
	#define PRIVATE_PROC(X)
	#define PROTECTED_PROC(X)
	#define CAN_BE_REDEFINED(X)
	#define VAR_FINAL var
	#define VAR_PRIVATE var
	#define VAR_PROTECTED var
#endif

/datum/time_scheduler
	var/datum/tick_meter/meter
/datum/tick_meter
	var/datum/km_attr/attr
/datum/km_holder
	var/datum/tick_meter/meter
/datum/km_attr
/proc/km_holder()
	RETURN_TYPE(/datum/km_holder)
	var/static/datum/km_holder/holder
	if(!holder)
		holder = new
	return holder

/proc/km_meter()
	RETURN_TYPE(/datum/tick_meter)
	var/datum/km_holder/holder = km_holder()
	if(!holder.meter)
		rel_set(holder, nameof(holder.meter), new /datum/tick_meter)
	return holder.meter

"########;
const ACTUAL_REFRESH_LOGICAL_WHOLE:&str=r########"#define CHURN_COUNT(kind, key) GLOB.churn_census.kind[key] += 1
#define LAZYADD(L, I) do { if(!L) { L = list(); } L += I; } while(0)
#define QDELING(X) (X.gc_destroyed)
#define QDELETED(X) (isnull(X) || QDELING(X))
#define TICK_DELTA_TO_MS(percent_of_tick_used) ((percent_of_tick_used) * world.tick_lag)
#define TICK_USAGE_TO_MS(starting_tickusage) (TICK_DELTA_TO_MS(world.tick_usage - starting_tickusage))
#define TICK_USAGE world.tick_usage
#define KM_SYS_APPEARANCE 5
#define KA_KIND_DRAW 3
#define DEP_CREATED (1<<17)
#define DEP_PARKED (1<<18)
/proc/refresh_drain(datum/time_scheduler/sched)
	rx_drain() // change reactions (on_change / on_cross / observe) run before the outputs
	var/list/Q = GLOB.refresh_queue
	var/datum/km_attr/attr = (sched?.meter || km_meter()).attr
	// review 2 M4: each entity refreshes at most once per drain; one re-queued by its own refresh (or
	// by a chain that comes back to it) waits for the next frame instead of spinning here. The pass stamp (refresh_pass) replaces a per-drain
	// list of the entities already run: a nested drain takes its own pass number, as it had its own list.
	var/pass = ++GLOB.refresh_drain_pass
	var/list/deferred
	var/i = 0
	while(i < length(Q))
		i++
		var/datum/D = Q[i]
		if(isnull(D))
			continue // a hard-deleted queued entity leaves a null entry
		var/queued_slot = slot_known(D)
		if(queued_slot && GLOB.refresh_queue_at[queued_slot] == GLOB.refresh_queue_base + i)
			GLOB.refresh_queue_at -= queued_slot // this entry is consumed (an older duplicate of it leaves the newer one's place alone)
		if(D.refresh_pass == pass)
			LAZYADD(deferred, D)
			continue
		var/pending = D.refresh_queued
		if(pending == DEP_PARKED)
			continue // a stale entry of an atom parked since (refresh_park_backlog()): it keeps owing its first draw
		D.refresh_queued = 0
		if(QDELETED(D))
			D.refresh_bits = 0
			continue
		if(!pending)
			continue // a stale duplicate: an earlier entry already ran its outputs
		var/fresh = pending & DEP_CREATED
		pending &= ~DEP_CREATED
		if(fresh && type_look_stamped(D))
			// Queued at creation before its type's verdict was in, and the type's default look is empty: nothing to draw (look_stamp.dm).
			D.refresh_bits = 0
			GLOB.type_look_stamp_skipped++
			continue
		if(!refresh_wanted_queued(D))
			// Every atom's first refresh is queued at init (caps_init()) before its type's verdict is in: the first
			// instance probes the type, and the rest, queued behind it, skip here once it is known to derive nothing.
			D.refresh_bits = 0
			continue
		D.refresh_pass = pass
		CHURN_COUNT(draws, D.type)
		var/bits = D.refresh_bits
		D.refresh_bits = 0
		GLOB.refresh_bench_drained++
		var/attr_start = TICK_USAGE
		try
			refresh_one(D, bits, pending)
			if(fresh)
				type_look_stamp_record(D)
		catch(var/exception/e)
			if(sched)
				sched.report_caught(e, "refresh of [D.type]: [e] ([e.file]:[e.line])")
			else
				dq_report_caught(e, "refresh of [D.type]")
		attr.note(KA_KIND_DRAW, KM_SYS_APPEARANCE, D.type, km_attr_reason(pending | fresh), TICK_USAGE_TO_MS(attr_start))
		if(sched?.out_of_budget() && i < length(Q))
			Q.Cut(1, i + 1)
			GLOB.refresh_queue_base += i
			for(var/datum/later as anything in deferred)
				refresh_queue_push(later)
			return FALSE
	Q.Cut()
	GLOB.refresh_queue_base = 0 // every place was given back as its entry was consumed
	for(var/datum/later as anything in deferred)
		refresh_queue_push(later)
	if(deferred)
		return FALSE
	return TRUE
"########;
const ACTUAL_REFRESH_LOGICAL_FRAGMENT:&str=r########"/proc/refresh_drain(datum/time_scheduler/sched)
	var/datum/km_attr/attr = (sched?.meter || km_meter()).attr
"########;
fn check_actual_refresh_logical_empty(label:&str,body:&str,check_no_hint:bool){
 let source=format!("{ACTUAL_REFRESH_LOGICAL_SUPPORT}\n{body}");let(root,cache,_)=fixture(label,&source);
 let request=dmbc::native_checker::Request{project:root.join("deepquarry.dme"),configuration:None,cache_root:cache.clone(),workers:1,timeout_seconds:60};let mut host=BuildHost::default();let(mut output,mut diagnostics)=(Vec::new(),Vec::new());
 let outcome=dmbc::native_checker::run(request,&mut host,&mut output,&mut diagnostics).unwrap_or_else(|error|panic!("actual refresh logical empty-analysis traversal {label}: {error:?}"));assert_eq!(outcome.visited_bodies,3,"actual km_holder, km_meter and refresh body only");
 let checker=String::from_utf8(diagnostics).unwrap();assert!(checker.contains("field access requires static type: \"attr\""),"pinned || returns empty analysis rather than a coalesced meter receiver: {checker}");if check_no_hint{assert!(!checker.contains("add additional type info here")&&!checker.contains("return type evaluated to None"),"empty logical result has no inherited variable/return fix hint: {checker}");}no_runtime_products(&root);no_runtime_products(&cache);
}
#[test]
fn actual_original_refresh_drain_logical_group_whole_reports_unhinted_attr_warning(){check_actual_refresh_logical_empty("native-refresh-logical-whole",ACTUAL_REFRESH_LOGICAL_WHOLE,false);}
#[test]
fn actual_original_refresh_drain_logical_group_real_fragment_has_no_inherited_fix_hint(){check_actual_refresh_logical_empty("native-refresh-logical-fragment",ACTUAL_REFRESH_LOGICAL_FRAGMENT,true);}

// Genuine minimal DM regression programs; no fake TypeFact/AST/source authority.
// The fourth is a STATIC undefined-return countercontrol, not runtime DiagnosedNone coverage.
fn check_original_diagnosed_empty_native(label:&str,source:&str,first_finding:&str,argument:&str,evaluated_none:bool,expected_bodies:usize){
 let(root,cache,_)=fixture(label,source);let request=dmbc::native_checker::Request{project:root.join("deepquarry.dme"),configuration:None,cache_root:cache.clone(),workers:1,timeout_seconds:60};let mut host=BuildHost::default();let(mut output,mut diagnostics)=(Vec::new(),Vec::new());
 let outcome=dmbc::native_checker::run(request,&mut host,&mut output,&mut diagnostics).unwrap_or_else(|error|panic!("genuine diagnosed empty checker {label}: {error:?}"));assert_eq!(outcome.visited_bodies,expected_bodies);let checker=String::from_utf8(diagnostics).unwrap();assert!(checker.contains(first_finding),"original diagnosed branch must report its finding: {checker}");assert!(checker.contains("field access requires static type: \"field\""),"actual follow must report a missing static type, not an operational refusal: {checker}");
 let argument_finding=format!("undefined proc: {argument:?}");assert_eq!(checker.contains(&argument_finding),evaluated_none,"the three diagnosed-empty branches skip arguments; staticreturn guard visits its argument: {checker}");assert_eq!(checker.contains("return type evaluated to None"),evaluated_none,"only successful static-None return binding inherits the evaluated-None note: {checker}");assert!(!checker.contains("add additional type info here"),"diagnosed-empty follow cannot inherit parameter/local declaration hint: {checker}");no_runtime_products(&root);no_runtime_products(&cache);
}
#[test]
fn actual_original_private_denial_empty_follow_skips_arguments_and_fix_hint(){check_original_diagnosed_empty_native("actual_original_private_denial_empty_follow_skips_arguments_and_fix_hint",r########"/datum/empty_guard/proc/hidden(value)
    set SpacemanDMM_private_proc = TRUE
    return value
/datum/empty_guard/child/proc/probe()
    return src.hidden(skipped_private_argument()).field
"########,"attempting to call private proc","skipped_private_argument",false,2);}
#[test]
fn actual_original_missing_parent_empty_follow_skips_arguments_and_fix_hint(){check_original_diagnosed_empty_native("actual_original_missing_parent_empty_follow_skips_arguments_and_fix_hint",r########"/proc/probe()
    return ..(skipped_parent_argument()).field
"########,"proc has no parent:","skipped_parent_argument",false,1);}
#[test]
fn actual_original_implicit_new_empty_follow_skips_arguments_and_fix_hint(){check_original_diagnosed_empty_native("actual_original_implicit_new_empty_follow_skips_arguments_and_fix_hint",r########"/proc/probe()
    return new(skipped_new_argument()).field
"########,"no type hint available on implicit new()","skipped_new_argument",false,1);}
#[test]
fn actual_original_static_undefined_return_keeps_evaluated_none_fix_hint_guard(){check_original_diagnosed_empty_native("actual_original_static_undefined_return_keeps_evaluated_none_fix_hint_guard",r########"/proc/declared_empty(value)
    set SpacemanDMM_return_type = /datum/undefined_return_fixture
    return null
/proc/probe()
    return declared_empty(visited_return_argument()).field
"########,"undefined type: /datum/undefined_return_fixture","visited_return_argument",true,2);}

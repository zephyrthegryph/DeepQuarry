//! Whole independently frozen original Plans versus actual source-loaned producer.
use super::*;
mod deps {
    pub use crate::gens::deps::analyzed;
    use crate::sem::decls::{Marker,matching_paren};
    fn is_word(b:u8)->bool {b.is_ascii_alphanumeric()||b==b'_'}
pub fn marker_named_vars(m: &Marker) -> Vec<String> {
    let body = &m.body;
    let mut out = Vec::new();
    let mut from = 0;
    while let Some(at) = body[from..].find("nameof(") {
        let start = from + at;
        from = start + 7;
        if start > 0 && is_word(body.as_bytes()[start - 1]) {
            continue;
        }
        let Some(close) = matching_paren(body, start + 6) else { continue };
        let name = body[start + 7..close].trim();
        if !name.is_empty() && name.bytes().all(is_word) {
            out.push(name.to_string());
        }
    }
    out
}
}

#[path="../examples/support/plans_original/producer.rs"]mod whole_original;
#[test]fn original_plans_generator_matches_whole_frozen_producer_and_keeps_reader_text_loaned(){
 let root=test_scratch::dir("native-plans-generator");std::fs::create_dir_all(root.join("code/engine/_generated")).unwrap();std::fs::create_dir(root.join("maps")).unwrap();let code=format!("{}\n#if 0\nSTATE_GRAPH(/obj/probe, on_change(nameof(plans_state_graph_only)))\n#endif\n",include_str!("../fixtures/plans-whole/code/probe.dm"));std::fs::write(root.join("code/probe.dm"),code).unwrap();std::fs::write(root.join("maps/reader.dm"),"/obj/map_reader\n    var/map_key\n/obj/map_reader/proc/reactions()\n    return on_change(nameof(map_key))\n").unwrap();std::fs::write(root.join("code/engine/_generated/auto_tracked.dm"),"").unwrap();std::fs::write(root.join("deepquarry.dme"),"#include \"code/probe.dm\"\n#include \"maps/reader.dm\"\n#include \"code/engine/_generated/auto_tracked.dm\"\n").unwrap();
 let mut original_source=Source::capture(&root);let map=root.join("maps/reader.dm");original_source.rows.insert(dm_preprocess::regions::canonical_path(&map),dm_preprocess::AcquiredSource::from_original_bytes(std::fs::read(&map).unwrap(),()));let executor=dm_exec::BuildExecutor::new(1).unwrap();let queries=Arc::new(Queries::default());let settings=queries.clone()as Arc<dyn SettingExpressionQueries>;let seed=profile::seed();let front=dm_tree::frontend::build_with_executor_and_semantic_state_for_policy_checked(&root.join("deepquarry.dme"),&original_source,&Default::default(),dm_tree::frontend::FrontendConfig{workers:1,engine:Some(&seed),observer:None},None,&executor,None,true,&settings).unwrap().with_body_queries(queries.clone()as Arc<dyn BodySyntaxQueries>);let extra=front.files.iter().filter(|file|file.captured).map(|file|dm_analysis::policy_inputs::HostCapture::analyze_raw(file.path.clone(),dm_analysis::policy_inputs::PolicyRole::DmSource,file.text.clone()));let inputs=dm_analysis::policy_inputs::PolicyInputs::capture(&front,extra).unwrap();let raw=crate::captured_raw_policy::CapturedRawPolicy::capture(&root,&inputs,crate::captured_raw_policy::Configuration::ProvenMissing).unwrap();let poll=||Ok(());let borrower=|input:&Arc<BodySyntaxInput>|queries.syntax_checked(input);let global_budget=crate::captured_generator_budget::Budget::new(128*1024*1024).unwrap();let globals=crate::captured_reactive_reads::globals_native(&inputs,&root,&global_budget,&poll,&borrower).unwrap();let global_provider=|consume:&mut dyn FnMut(&crate::captured_reactive_reads::GlobalResult)->Result<bool,Failure>|consume(&globals);
 let provider=|owner:&str,name:&str,context:Option<&str>,flavor:crate::captured_reactive_reads::Flavor,consume:&mut dyn FnMut(&crate::captured_reactive_reads::ReadResult)->Result<(),Failure>|{let budget=crate::captured_generator_budget::Budget::new(128*1024*1024).unwrap();let value=crate::captured_reactive_reads::reads(&raw,&inputs,&budget,&global_provider,owner,name,context,flavor,&poll,&borrower)?;consume(&value)};let aggregate_budget=crate::captured_generator_budget::Budget::new(128*1024*1024).unwrap();let analysis=crate::captured_reactive_reads::dependencies(&raw,&inputs,&aggregate_budget,&global_provider,&provider,&poll,&borrower).unwrap();
 let old_engine=crate::run::Engine::new(crate::run::registry(),crate::run::Options{root:root.clone(),lints:vec![crate::generator_test_scope::cli_source_lint().to_owned()],raw:true,no_cache:true,..Default::default()}).unwrap();let cx=crate::sem::gen::GenCx::new(&old_engine.tree,&root);assert!(cx.sem().unwrap().errors.is_empty());let mut generators=Vec::new();whole_original::register(&mut generators);let mut expected=crate::sem::gen::GenOut::default();generators[0].generate(&cx,&mut expected);let bodies=queries.bodies.load(Ordering::Relaxed);let budget=crate::captured_generator_budget::Budget::new(128*1024*1024).unwrap();let actual=analysis.render_plans(&raw,&inputs,&budget,&poll).unwrap();assert_original_output(&actual,&expected);assert!(actual.body.contains("plans_state_graph_only"),"STATE_GRAPH-only original reader key must reach native metadata");assert!(actual.body.contains("map_key"),"original compiled reader outside CODE_DM must retain its exact raw source loan");for needle in include_str!("../fixtures/plans-whole/expected_plans_fragments.txt").lines().filter(|s|!s.is_empty()&&!s.starts_with('#')){assert!(actual.body.contains(needle),"{needle}");}assert_eq!(queries.bodies.load(Ordering::Relaxed),bodies,"Plans metadata never demands even a warm body");assert_eq!(queries.compatibility.load(Ordering::Relaxed),0);
 let tiny=crate::captured_generator_budget::Budget::new(1024).unwrap();let error=analysis.render_plans(&raw,&inputs,&tiny,&poll).unwrap_err();assert!(matches!(error,Failure::Operational(ref actual)if actual.kind()==io::ErrorKind::OutOfMemory));let healthy=crate::captured_generator_budget::Budget::new(128*1024*1024).unwrap();let error=analysis.render_plans(&raw,&inputs,&healthy,&||Err(io::Error::from_raw_os_error(1450))).unwrap_err();assert!(matches!(error,Failure::Operational(ref actual)if actual.raw_os_error()==Some(1450)));let recovered=crate::captured_generator_budget::Budget::new(128*1024*1024).unwrap();assert_original_output(&analysis.render_plans(&raw,&inputs,&recovered,&poll).unwrap(),&expected);
 let pages=ActualPages{raw:&raw,busy:std::cell::Cell::new(false)};let order_budget=crate::captured_generator_budget::Budget::new(4*1024*1024).unwrap();let order=crate::captured_reactive_reads::original_include_order(&inputs,&root,&order_budget).unwrap();let budget=crate::captured_generator_budget::Budget::new(128*1024*1024).unwrap();let code_only=crate::reactive_original_source::ReadSource::native(&inputs,&root,&budget).unwrap().with_raw_policy_pages(&pages,&order).with_checkpoint(&poll);let error=crate::reactive_plans_generator_native::collect(&code_only).err().expect("CODE-only data cannot omit original outside-CODE reader metadata");assert!(matches!(error,Failure::Operational(ref actual)if actual.kind()==io::ErrorKind::InvalidInput));assert!(!pages.busy.get());
}

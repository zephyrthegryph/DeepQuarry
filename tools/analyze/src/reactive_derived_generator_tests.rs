//! Whole independent old raw-derived generator against original callback loans.
use std::{io,path::Path,sync::{Arc,atomic::{AtomicUsize,AtomicBool,Ordering}}};
use dm_tree::frontend::{BodySyntaxQueries,BodySyntaxInput,BodySyntax,BodySyntaxFailure,SettingExpressionQueries,SettingExpressionInput};
use crate::captured_reactive_reads::Failure;
#[path="../../dmb/shared/test_scratch.rs"]mod test_scratch;
#[path="../../dmb/crates/dm-analysis/examples/support/reference_hierarchy.rs"]mod profile;
#[path="../examples/support/deps_original/reaction_producer.rs"]mod original;
#[derive(Debug)]
struct Queries{counter:Arc<dm_syntax::SettingChargeCounter>,bodies:AtomicUsize,compatibility:AtomicUsize,fail:AtomicBool}
impl Default for Queries {
    fn default() -> Self {
        Self {
            counter: dm_syntax::SettingChargeCounter::try_new(64 * 1024 * 1024).unwrap(),
            bodies: AtomicUsize::default(),
            compatibility: AtomicUsize::default(),
            fail: AtomicBool::default(),
        }
    }
}
impl Queries{fn admitted<T>(&self,run:impl FnOnce(&dm_syntax::SettingAdmission<'_>)->Result<T,BodySyntaxFailure>)->Result<T,BodySyntaxFailure>{let poll=||Ok(());let a=dm_syntax::SettingAdmission::new(&self.counter,64*1024*1024,&poll);let result=run(&a);if matches!(&result,Err(BodySyntaxFailure::Operational(_))){return result}if let Some(actual)=a.take_operational_error(){return Err(BodySyntaxFailure::Operational(actual))}result}}
impl SettingExpressionQueries for Queries{
 fn with_declaration_admission(&self,operation:&mut dyn FnMut(&dm_syntax::SettingAdmission<'_>)->Result<(),BodySyntaxFailure>)->Result<(),BodySyntaxFailure>{self.admitted(|a|operation(a))}
 fn expression(&self,input:&SettingExpressionInput<'_>)->Result<dm_syntax::SettingExpression,BodySyntaxFailure>{self.admitted(|a|input.prepare(a))}
 fn statements(&self,input:&mut dm_tree::frontend::SettingStatementsInput<'_,'_>)->Result<Arc<dm_tree::frontend::StatementBody>,BodySyntaxFailure>{self.admitted(|a|input.prepare(a))}
}
impl BodySyntaxQueries for Queries{
 fn syntax(&self,input:&Arc<BodySyntaxInput>)->Result<Arc<BodySyntax>,dm_tree::frontend::Diagnostic>{self.compatibility.fetch_add(1,Ordering::Relaxed);input.parse().map(Arc::new)}
 fn syntax_checked(&self,input:&Arc<BodySyntaxInput>)->Result<Arc<BodySyntax>,BodySyntaxFailure>{self.bodies.fetch_add(1,Ordering::Relaxed);if self.fail.load(Ordering::Acquire){return Err(BodySyntaxFailure::Operational(io::Error::from_raw_os_error(1450)))}self.admitted(|a|input.parse_with_setting_admission(a).map(Arc::new))}
}
struct Source{rows:std::collections::BTreeMap<std::path::PathBuf,dm_preprocess::AcquiredSource>}
impl Source{
 fn capture(root:&Path)->Self{let rows=["deepquarry.dme","code/probe.dm","code/engine/_generated/auto_tracked.dm"].into_iter().map(|relative|{let path=root.join(relative);let bytes=std::fs::read(&path).unwrap();(dm_preprocess::regions::canonical_path(&path),dm_preprocess::AcquiredSource::from_original_bytes(bytes,()))}).collect();Self{rows}}
}
impl dm_preprocess::SourceProvider for Source{
 fn read(&self,_:&Path)->Result<String,String>{panic!("native fixture must use its original acquired bytes")}
 fn acquired_source(&self,path:&Path)->Result<Option<dm_preprocess::AcquiredSource>,String>{Ok(self.rows.get(&dm_preprocess::regions::canonical_path(path)).cloned())}
 fn source_acquisition(&self,path:&Path,text:&dm_preprocess::SourceText)->Option<dm_preprocess::AcquiredSource>{self.rows.get(&dm_preprocess::regions::canonical_path(path)).filter(|source|source.lease().source_text().same_view(text)).cloned()}
}

#[test]fn original_derived_generator_matches_whole_frozen_helper_reaction_boot_policy_without_body_demand(){
 let root=test_scratch::dir("native-derived-generator");std::fs::create_dir_all(root.join("code/engine/_generated")).unwrap();let code="#define PUBLISHED_BY(T,V,K)\n/datum/probe\n    var/value\n    var/derived\n/datum/probe/draw()\n    return helper()\n/datum/probe/helper()\n    return value\n/datum/probe/child/helper()\n    return derived\n/datum/probe/derive_derived()\n    return value\n/mob/probe\n    var/health\n/mob/probe/life_hud()\n    return health\n/mob/probe/reactions()\n    . += every(1, members=/datum/probe)\n    . += on_cross()\n    . += on_notice()\nPUBLISHED_BY(/mob/probe,health,HEALTH_KEY)\n";std::fs::write(root.join("code/probe.dm"),code).unwrap();std::fs::write(root.join("code/engine/_generated/auto_tracked.dm"),"").unwrap();std::fs::write(root.join("deepquarry.dme"),"#include \"code/probe.dm\"\n#include \"code/engine/_generated/auto_tracked.dm\"\n").unwrap();
 let original_source=Source::capture(&root);let executor=dm_exec::BuildExecutor::new(1).unwrap();let queries=Arc::new(Queries::default());let settings=queries.clone()as Arc<dyn SettingExpressionQueries>;let seed=profile::seed();let front=dm_tree::frontend::build_with_executor_and_semantic_state_for_policy_checked(&root.join("deepquarry.dme"),&original_source,&Default::default(),dm_tree::frontend::FrontendConfig{workers:1,engine:Some(&seed),observer:None},None,&executor,None,true,&settings).unwrap().with_body_queries(queries.clone()as Arc<dyn BodySyntaxQueries>);let extra=front.files.iter().filter(|file|file.captured).map(|file|dm_analysis::policy_inputs::HostCapture::analyze_raw(file.path.clone(),dm_analysis::policy_inputs::PolicyRole::DmSource,file.text.clone()));let inputs=dm_analysis::policy_inputs::PolicyInputs::capture(&front,extra).unwrap();let raw=crate::captured_raw_policy::CapturedRawPolicy::capture(&root,&inputs,crate::captured_raw_policy::Configuration::ProvenMissing).unwrap();let poll=||Ok(());let borrower=|input:&Arc<BodySyntaxInput>|queries.syntax_checked(input);
 let old_engine=crate::run::Engine::new(crate::run::registry(),crate::run::Options{root:root.clone(),lints:vec!["sem/keys".to_owned()],..Default::default()}).unwrap();let files=old_engine.tree.select(&crate::tree::CODE_DM);let expected=original::generated_for(&old_engine.tree,&files);let budget=crate::captured_generator_budget::Budget::new(128*1024*1024).unwrap();let actual=crate::captured_reactive_reads::render_derived_reads(&raw,&inputs,&budget,&poll,&borrower).unwrap();assert_eq!(actual,expected,"entire independent original output including helper subtype union/published reaction key/every-cross-notice boot declarations");assert!(actual.contains("RXB_CROSS | RXB_EVERY | RXB_NOTICE"));assert!(actual.contains("HEALTH_KEY"));assert!(actual.contains("/datum/probe/child/generated_reads()"));assert_eq!(queries.bodies.load(Ordering::Relaxed),0);assert_eq!(queries.compatibility.load(Ordering::Relaxed),0);
 let tiny=crate::captured_generator_budget::Budget::new(1024).unwrap();assert!(matches!(crate::captured_reactive_reads::render_derived_reads(&raw,&inputs,&tiny,&poll,&borrower),Err(Failure::Operational(ref actual))if actual.kind()==io::ErrorKind::OutOfMemory));let fresh=crate::captured_generator_budget::Budget::new(128*1024*1024).unwrap();assert!(matches!(crate::captured_reactive_reads::render_derived_reads(&raw,&inputs,&fresh,&||Err(io::Error::from_raw_os_error(1450)),&borrower),Err(Failure::Operational(ref actual))if actual.raw_os_error()==Some(1450)));let fresh=crate::captured_generator_budget::Budget::new(128*1024*1024).unwrap();assert_eq!(crate::captured_reactive_reads::render_derived_reads(&raw,&inputs,&fresh,&poll,&borrower).unwrap(),expected);
 let pages=ActualPages{raw:&raw,busy:std::cell::Cell::new(false)};let ordering_budget=crate::captured_generator_budget::Budget::new(4*1024*1024).unwrap();let order=crate::captured_reactive_reads::original_include_order(&inputs,&root,&ordering_budget).unwrap();let types=crate::sem::gen::test_only_types(&old_engine.tree);let page_budget=crate::captured_generator_budget::Budget::new(128*1024*1024).unwrap();assert_eq!(crate::captured_reactive_reads::render_derived_data_from_pages(&inputs,&root,&pages,&order,&types,&page_budget,&poll,&borrower).unwrap(),expected,"neutral page-data path uses SAME full old helper/reaction/boot policy");assert!(!pages.busy.get());assert_eq!(queries.bodies.load(Ordering::Relaxed),0);

}

struct ActualPages<'a>{raw:&'a crate::captured_raw_policy::CapturedRawPolicy,busy:std::cell::Cell<bool>}
impl crate::reactive_raw_policy_pages::RawPolicyPages for ActualPages<'_>{fn for_each(&self,visit:&mut dyn FnMut(&str,crate::captured_raw_file::RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{if self.busy.replace(true){return Err(Failure::Operational(io::Error::new(io::ErrorKind::InvalidInput,"nested original page loan")))}struct Reset<'a>(&'a std::cell::Cell<bool>);impl Drop for Reset<'_>{fn drop(&mut self){self.0.set(false)}}let _reset=Reset(&self.busy);for file in self.raw.tree.files.iter().filter(|file|crate::tree::CODE_DM.matches(file)){if !visit(&file.rel,crate::captured_raw_file::RawPolicyViews::from_source(file))?{return Ok(false)}}Ok(true)}}

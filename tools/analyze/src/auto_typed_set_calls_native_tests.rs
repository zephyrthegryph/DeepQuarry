//! Actual native source/body adapter versus the independent original visitor.
use super::*;use std::{path::Path,sync::{Arc,atomic::{AtomicUsize,AtomicBool,Ordering}}};
use dm_tree::frontend::{BodySyntaxQueries,BodySyntaxInput,BodySyntax,BodySyntaxFailure,SettingExpressionQueries,SettingExpressionInput};
#[path="../../dmb/shared/test_scratch.rs"]mod test_scratch;
#[path="../../dmb/crates/dm-analysis/examples/support/reference_hierarchy.rs"]mod profile;
#[path="typed_set_calls_reference.rs"]mod reference;
#[path="native_candidates_reference.rs"]mod candidates_reference;
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
const CODE:&str="/datum/typed\n    var/datum/typed/next\n/datum/other\n/datum/owner\n    var/datum/typed/field\n    proc/probe(datum/typed/p)\n        p.set_formal(1)\n        var/p\n        p.set_shadow_kept(1)\n        var/datum/other/q\n        q.set_typed(1)\n        var/q\n        q.set_untyped_kept(1)\n        src.set_src(1)\n        field.next.set_hop(1)\n        usr.set_usr(1)\n        (field).set_group(1)\n        field[1].set_index(1)\n        field.make().set_call(1)\n        set_bare(1)\n        field.set_first(1).set_after(1)\n        ::set_global(1)\n        global.set_explicit_global(1)\n        new set_constructor(set_argument(1))\n        for(var/datum/typed/i in list())\n            i.set_each(1)\n        for(var/datum/typed/j=1 to 2)\n            j.set_range_ignored(1)\n        for(var/datum/typed/k=1,k<2,k++)\n            k.set_cstyle_ignored(1)\n/datum/owner/child\n    probe(datum/other/p)\n        p.set_override(1)\n/datum/typed/proc/set_order(v)\n    return v\n/datum/other/proc/set_order(v)\n    return v\n/datum/owner/child/set_order(v)\n    return v\n\n#define TRACKED(T,V)\nTRACKED(/datum/owner,explicit)\n/datum/owner\n    var/charge\n    var/quiet\n    var/raw_write\n    var/explicit\n    var/const/frozen=3\n    var/list/items\n    proc/candidate_calls()\n        src.set_charge(1)\n        src.add_items(1)\n        raw_write=2\n";
#[test]fn original_typed_setter_calls_match_frozen_whole_receiver_policy_and_checked_io_retry(){
 let root=test_scratch::dir("native-typed-setters");std::fs::create_dir_all(root.join("code/engine/_generated")).unwrap();std::fs::write(root.join("code/probe.dm"),CODE).unwrap();let generated="/datum/generated/proc/probe()\n    src.set_generated_skip(1)\n";std::fs::write(root.join("code/engine/_generated/auto_tracked.dm"),generated).unwrap();std::fs::write(root.join("deepquarry.dme"),"#include \"code/probe.dm\"\n#include \"code/engine/_generated/auto_tracked.dm\"\n").unwrap();
 let mut old_tree=crate::tree::Tree::from_files(vec![crate::tree::SourceFile::from_text("code/probe.dm",CODE),crate::tree::SourceFile::from_text("code/engine/_generated/auto_tracked.dm",generated)]);old_tree.root=root.clone();let old_sem=crate::sem::Sem::build(&root,&old_tree).unwrap();assert!(old_sem.errors.is_empty(),"actual frozen parser source must be valid: {:?}",old_sem.errors);let expected=reference::collect(&old_sem);
 let original_source=Source::capture(&root);
 let executor=dm_exec::BuildExecutor::new(1).unwrap();let queries=Arc::new(Queries::default());let settings=Arc::clone(&queries)as Arc<dyn SettingExpressionQueries>;let seed=profile::seed();let front=dm_tree::frontend::build_with_executor_and_semantic_state_for_policy_checked(&root.join("deepquarry.dme"),&original_source,&Default::default(),dm_tree::frontend::FrontendConfig{workers:1,engine:Some(&seed),observer:None},None,&executor,None,true,&settings).unwrap().with_body_queries(Arc::clone(&queries)as Arc<dyn BodySyntaxQueries>);// These fixture files are known UTF-8/LF without BOM; the real captured
 // compiler SourceText therefore is also the exact Analyze raw byte contract.
 let extra=front.files.iter().filter(|file|file.captured).map(|file|dm_analysis::policy_inputs::HostCapture::analyze_raw(Arc::clone(&file.path),dm_analysis::policy_inputs::PolicyRole::DmSource,file.text.clone()));
 let inputs=dm_analysis::policy_inputs::PolicyInputs::capture(&front,extra).unwrap();let budget=crate::captured_generator_budget::Budget::new(32*1024*1024).unwrap();let poll=||Ok(());let borrower=|input:&Arc<BodySyntaxInput>|queries.syntax_checked(input);let source=ReadSource::native(&inputs,&root,&budget).unwrap().with_checkpoint(&poll).with_body_borrower(&borrower);
 let definitions=crate::auto_tracking_native::setter_defs(&source).unwrap();assert_eq!(definitions,reference::setter_defs(&old_tree,&old_sem),"complete original setter name/type groups and owner-vector order");assert_eq!(definitions.get("set_order"),Some(&vec!["/datum/typed".to_owned(),"/datum/other".to_owned()]));
 let mut variables=std::collections::BTreeSet::new();source.visit_own_declared_variables(|owner,name|{variables.insert((owner.to_owned(),name.to_owned()));Ok(())}).unwrap();assert_eq!(variables,reference::own_variables(&old_sem),"complete original own declarations including real builtin vars; no inherited/engine-only guesses");
 let result=collect(&source).unwrap();assert_eq!(result.entries(),expected.as_slice(),"complete old receiver set, including all versions and expression-shape quirks");assert!(result.contains("set_shadow_kept","/datum/typed"));assert!(result.contains("set_untyped_kept","/datum/other"));for name in["set_group","set_index","set_call","set_after","set_range_ignored","set_cstyle_ignored"]{assert!(result.contains(name,policy::UNTYPED),"{name}");}assert!(!result.entries().iter().any(|(name,_)|matches!(name.as_str(),"set_generated_skip"|"set_global"|"set_constructor")));assert!(result.contains("set_argument","/datum/owner"));assert_eq!(queries.compatibility.load(Ordering::Relaxed),0,"native route cannot take legacy body syntax hook");

 // Whole candidate decisions use the real original raw policy, facts and global
 // producer. The provider lends its actual result; it never fabricates rows.
 let raw=crate::captured_raw_policy::CapturedRawPolicy::capture(&root,&inputs,crate::captured_raw_policy::Configuration::ProvenMissing).unwrap();
 let candidate_source=ReadSource::capture(&raw,&inputs,&budget).unwrap().with_checkpoint(&poll).with_body_borrower(&borrower);
 let facts=crate::reactive_policy_facts_native::PolicyFacts::capture(&candidate_source,&mut||Ok(())).unwrap();
 let global_budget=crate::captured_generator_budget::Budget::new(32*1024*1024).unwrap();
 let globals=crate::captured_reactive_reads::globals_native(&inputs,&root,&global_budget,&poll,&borrower).unwrap();
 let questions=AtomicUsize::new(0);
 let provider=|consume:&mut dyn FnMut(&crate::captured_reactive_reads::GlobalResult)->Result<bool,Failure>|{questions.fetch_add(1,Ordering::Relaxed);consume(&globals)};
 let native=crate::auto_tracking_native::NativeCandidates::capture(&candidate_source,&facts,&provider).unwrap();
 let decls=crate::sem::decls::Decls::get(&old_tree);let annotations=crate::sem::reads::Annotations::get(&old_sem,&decls);let engine=crate::sem::reads::ReadsEngine::new(&old_sem,&decls,&annotations);
 let outside=crate::gens::auto_tracked::writes_outside_setters(&old_sem);let lexical=crate::gens::auto_tracked::set_calls(&old_tree);
 assert_eq!(crate::auto_tracking_native::set_calls(&candidate_source).unwrap(),*lexical,"complete actual lexical call set");
 let mut expected_called=std::collections::BTreeSet::new();
 for(owner,name)in &variables{
  let candidate=candidates_reference::candidate(&engine,&outside,&lexical,owner,name);
  assert_eq!(native.candidate(owner,name).unwrap(),candidate,"candidate {owner}.{name}");
  assert_eq!(native.named_candidate(owner,name).unwrap(),candidates_reference::named_candidate(&engine,owner,name),"named {owner}.{name}");
  if candidates_reference::called_here(&old_tree,&old_sem,&definitions,&lexical,owner,name)&&candidate{expected_called.insert((owner.clone(),name.clone()));}
 }
 assert_eq!(native.called_candidates(),&expected_called,"whole actual called-candidate set against independent old boolean functions, typed collector and outside-write index");
 for name in["charge","raw_write","items"]{assert!(native.candidate("/datum/owner",name).unwrap(),"actual positive {name}");}
 assert!(!native.candidate("/datum/owner","quiet").unwrap());assert!(!native.named_candidate("/datum/owner","explicit").unwrap());
 let prior=questions.load(Ordering::Relaxed);assert!(!native.candidate("/datum/owner","frozen").unwrap());assert!(!native.candidate("/datum/owner","explicit").unwrap());assert_eq!(questions.load(Ordering::Relaxed),prior,"const and explicit-reactive short circuits do not demand globals");
 let stopped=|_:&mut dyn FnMut(&crate::captured_reactive_reads::GlobalResult)->Result<bool,Failure>|->Result<bool,Failure>{Err(Failure::Operational(io::Error::from_raw_os_error(1450)))};
 let failure=crate::auto_tracking_native::candidate(&candidate_source,&facts,&stopped,&lexical,"/datum/owner","quiet").unwrap_err();assert!(matches!(failure,Failure::Operational(ref actual)if actual.raw_os_error()==Some(1450)));
 assert!(!native.candidate("/datum/owner","quiet").unwrap(),"same original provider recovers after actual provider IO");
 let wrong_front=dm_tree::frontend::build_with_executor_and_semantic_state_for_policy_checked(&root.join("deepquarry.dme"),&original_source,&Default::default(),dm_tree::frontend::FrontendConfig{workers:1,engine:Some(&seed),observer:None},None,&executor,None,true,&settings).unwrap().with_body_queries(Arc::clone(&queries)as Arc<dyn BodySyntaxQueries>);
 let wrong_inputs=dm_analysis::policy_inputs::PolicyInputs::capture(&wrong_front,[]).unwrap();
 let wrong_budget=crate::captured_generator_budget::Budget::new(32*1024*1024).unwrap();let wrong_globals=crate::captured_reactive_reads::globals_native(&wrong_inputs,&root,&wrong_budget,&poll,&borrower).unwrap();assert!(!wrong_globals.matches(&inputs));
 let foreign=|consume:&mut dyn FnMut(&crate::captured_reactive_reads::GlobalResult)->Result<bool,Failure>|consume(&wrong_globals);
 let failure=crate::auto_tracking_native::candidate(&candidate_source,&facts,&foreign,&lexical,"/datum/owner","quiet").unwrap_err();assert!(matches!(failure,Failure::Operational(ref actual)if actual.kind()==io::ErrorKind::InvalidInput));
 assert!(!native.candidate("/datum/owner","quiet").unwrap(),"foreign original result cannot poison same-source recovery");
 queries.fail.store(true,Ordering::Release);let failed=collect(&source).err().expect("actual original body IO prevents a completed typed-call result");assert!(matches!(failed,Failure::Operational(ref actual)if actual.raw_os_error()==Some(1450)));queries.fail.store(false,Ordering::Release);assert_eq!(collect(&source).unwrap().entries(),result.entries());
 let tiny=crate::captured_generator_budget::Budget::new(size_of::<crate::captured_generator_budget::Budget>()+2*size_of::<usize>()).unwrap();let limited=ReadSource::native(&inputs,&root,&tiny).unwrap().with_checkpoint(&poll).with_body_borrower(&borrower);let failed=collect(&limited).err().expect("actual output/scratch admission refuses before successful result");assert!(matches!(failed,Failure::Operational(ref actual)if actual.kind()==io::ErrorKind::OutOfMemory));assert!(tiny.denied());assert_eq!(collect(&source).unwrap().entries(),result.entries());
}

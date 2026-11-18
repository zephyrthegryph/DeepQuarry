use super::*;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};

struct Source(dm_preprocess::AcquiredSource);
impl SourceProvider for Source {
    fn read(&self,_:&Path)->Result<String,String>{Err("original acquired bytes required".into())}
    fn acquired_source(&self,_:&Path)->Result<Option<dm_preprocess::AcquiredSource>,String>{Ok(Some(self.0.clone()))}
    fn source_acquisition(&self,_:&Path,text:&dm_preprocess::SourceText)->Option<dm_preprocess::AcquiredSource>{self.0.lease().source_text().same_view(text).then(||self.0.clone())}
}
#[path="../../../shared/original_analysis_test_host.rs"]mod original_host;
use original_host::Host;

const TEXT:&str="/datum/probe\n    var/const/value=1+2\n/proc/probe()\n    return 1\n";
fn source(text:&str)->Source{Source(dm_preprocess::AcquiredSource::from_original_bytes(text.as_bytes().to_vec(),()))}
fn checked(src:&Source,state:&mut RetainedSemanticTree,host:&Arc<dyn SettingExpressionQueries>)->Result<ColdFrontend,FrontendBuildFailure>{
    let executor=dm_exec::BuildExecutor::new(2).unwrap();
    build_with_executor_and_semantic_state_for_policy_checked(Path::new("early-initializer.dme"),src,&Default::default(),FrontendConfig{workers:2,engine:None,observer:None},None,&executor,Some(state),true,host)
}
fn compatibility(src:&Source,state:&mut RetainedSemanticTree)->ColdFrontend{
    let executor=dm_exec::BuildExecutor::new(2).unwrap();
    build_with_executor_and_semantic_state_for_policy(Path::new("early-initializer.dme"),src,&Default::default(),FrontendConfig{workers:2,engine:None,observer:None},None,&executor,Some(state),true).unwrap()
}

#[test]
fn checked_frontend_compatibility_then_checked_then_warm_keeps_genuine_early_root_and_foreign_counter_declines(){
    let src=source(TEXT);
    let mut state=RetainedSemanticTree::default();
    let legacy=compatibility(&src,&mut state);
    let raw=Host::new();let host=raw.clone() as Arc<dyn SettingExpressionQueries>;
    let first=checked(&src,&mut state,&host).unwrap();
    let plan=crate::initializers::capture_declaration_plan(&first.snapshot,&first.emission_order).unwrap();
    let root=first.original_initializer_input(&plan,0).unwrap().expression().unwrap();
    let warm=checked(&src,&mut state,&host).unwrap();
    let plan2=crate::initializers::capture_declaration_plan(&warm.snapshot,&warm.emission_order).unwrap();
    let again=warm.original_initializer_input(&plan2,0).unwrap().expression().unwrap();
    assert!(root.same_root(&again),"genuine completed header must survive authored adoption and warm lookup");
    assert_eq!(legacy.snapshot.tree.declarations().len(),first.snapshot.tree.declarations().len());
    assert_eq!(first.snapshot.tree.declarations().len(),warm.snapshot.tree.declarations().len());
    assert!(warm.timings.declaration_reuse.facts_hits>0);
    let foreign=Host::new();let foreign_host=foreign.clone() as Arc<dyn SettingExpressionQueries>;
    let changed=checked(&src,&mut state,&foreign_host).unwrap();
    let plan3=crate::initializers::capture_declaration_plan(&changed.snapshot,&changed.emission_order).unwrap();
    let other=changed.original_initializer_input(&plan3,0).unwrap().expression().unwrap();
    assert!(!root.same_root(&other),"foreign budget cannot adopt equal-source old roots");
    assert!(root.same_root(&first.original_initializer_input(&plan,0).unwrap().expression().unwrap()));
}

#[test]
fn checked_frontend_actual_quota_and_os_failure_are_operational_and_same_source_recovers(){
    let src=source(TEXT);let mut state=RetainedSemanticTree::default();
    let raw=Host::new();let host=raw.clone() as Arc<dyn SettingExpressionQueries>;
    raw.limit.store(dm_syntax::SettingChargeCounter::root_allocation_bytes(),Ordering::Release);
    let error=checked(&src,&mut state,&host).err().expect("actual zero-headroom root admission");
    assert!(matches!(error,FrontendBuildFailure::Operational(ref actual)if actual.kind()==std::io::ErrorKind::OutOfMemory));
    raw.limit.store(128*1024*1024,Ordering::Release);
    let first=checked(&src,&mut state,&host).unwrap();
    raw.fail.store(true,Ordering::Release);
    let error=checked(&src,&mut state,&host).err().expect("warm path must check actual worker control");
    assert!(matches!(error,FrontendBuildFailure::Operational(ref actual)if actual.raw_os_error()==Some(1450)));
    raw.fail.store(false,Ordering::Release);
    let again=checked(&src,&mut state,&host).unwrap();
    assert_eq!(first.snapshot.tree.declarations().len(),again.snapshot.tree.declarations().len());
    assert!(raw.entries.load(Ordering::Acquire)>2);
}

#[test]
fn checked_frontend_invalid_rhs_keeps_original_eager_fold_source_policy_and_empty_build_checks_control(){
    let src=source("/datum/probe\n    var/const/value=1+\n");
    let mut old_state=RetainedSemanticTree::default();let old=compatibility(&src,&mut old_state);
    let raw=Host::new();let host=raw.clone() as Arc<dyn SettingExpressionQueries>;
    let mut state=RetainedSemanticTree::default();let current=checked(&src,&mut state,&host).unwrap();
    let old_plan=crate::initializers::capture_declaration_plan(&old.snapshot,&old.emission_order).unwrap();
    let new_plan=crate::initializers::capture_declaration_plan(&current.snapshot,&current.emission_order).unwrap();
    assert_eq!(format!("{:?}",old_plan.plan().writes),format!("{:?}",new_plan.plan().writes));
    assert!(matches!(current.original_initializer_input(&new_plan,0).unwrap().expression(),Err(BodySyntaxFailure::Syntax(_))));
    raw.fail.store(true,Ordering::Release);
    let error=checked(&source(""),&mut RetainedSemanticTree::default(),&host).err().expect("empty checked source must still enter control");
    assert!(matches!(error,FrontendBuildFailure::Operational(ref actual)if actual.raw_os_error()==Some(1450)));
}

/// Reuse the existing checked native fixture host; never manufacture a successful model.
pub(super) fn original_test_host()->Arc<dyn SettingExpressionQueries>{Host::new()}

pub(super) fn with_original_test_host_controls<T>(f:impl FnOnce(Arc<dyn SettingExpressionQueries>,&AtomicUsize,&AtomicBool,&dm_syntax::SettingChargeCounter)->T)->T{let raw=Host::new();f(raw.clone()as Arc<dyn SettingExpressionQueries>,&raw.limit,&raw.fail,&raw.counter)}

/// SAME existing resource fixture, with its actual Arc for a caller checkpoint probe.
pub(super) fn with_original_test_host_shared_counter_controls<T>(f:impl FnOnce(Arc<dyn SettingExpressionQueries>,&AtomicUsize,&Arc<dm_syntax::SettingChargeCounter>)->T)->T{let raw=Host::new();f(raw.clone()as Arc<dyn SettingExpressionQueries>,&raw.limit,&raw.counter)}

//! Entire immutable old raw+semantic rule, never the new candidate judges.
pub use dq_analyze::{dm,gens,lint,sem,tree,pat,pat_match,util,key_policy_control,incr};
#[path="../src/raw_tree_report.rs"]mod raw_tree_report;
#[path="../src/reactive_writer_policy.rs"]mod reactive_writer_policy;
#[path="../fixtures/original_policies/dx_reactive.rs"]mod original;
#[path="../fixtures/native-sys-reactive/fixture.rs"]mod fixture;
#[path="../fixtures/report_configuration.rs"]mod report_configuration;
#[path="../../dmb/shared/test_scratch.rs"]mod scratch;
fn main()->Result<(),Box<dyn std::error::Error>>{
 for case in fixture::CASES{let root=scratch::dir(&format!("sys-reactive-original-{case}"));for(path,text)in fixture::files(case){let p=root.join(path);std::fs::create_dir_all(p.parent().unwrap())?;std::fs::write(p,text)?;}
  let mut reg=lint::Registry::default();dq_analyze::dm::sys::register_module(&mut reg,dq_analyze::dm::sys::SysModule{name:dq_analyze::original_policy_descriptors::sys_dx_reactive::SCOPE_MODULE_NAME,rules:dq_analyze::original_policy_descriptors::sys_dx_reactive::RULES,files_scan:Some(original::analyse),..dq_analyze::dm::sys::SysModule::DEFAULT});
  let engine=dq_analyze::run::Engine::new(reg,dq_analyze::run::Options{root:root.clone(),lints:vec!["sys/dx_reactive".into()],no_cache:true,raw:true,..Default::default()})?;let model=sem::sem_for(&engine.tree).expect("these independent valid-input fixtures require genuine old Some");assert!(model.errors.is_empty(),"actual old fixture: {:?}",model.errors);let result=engine.run_one(engine.reg.lints[0].as_ref());println!("SYS_REACTIVE_WHOLE_ORIGINAL={}",serde_json::json!({"case":case,"sites":result.run.sites,"allow_used":result.allow_used,"notes":result.run.notes,"text":result.text,"failed":result.failed,"internal_error":result.internal_error}));
 }Ok(())
}

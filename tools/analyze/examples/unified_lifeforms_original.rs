//! Entire independent immutable pre-port Lifeforms rule and helper source.
pub use dq_analyze::{incr,lint,sem,tree,dm,pat,pat_match,util,allow,key_policy_control};
pub use dq_analyze::original_policy_descriptors as allow_registry_fields;
#[path="../fixtures/original_policies/lifeforms.rs"]mod original;
#[path="../fixtures/original_policies/lifeform_source_policy.rs"]mod lifeform_source_policy;
#[path="../fixtures/native-lifeforms/fixture.rs"]mod fixture;
#[path="../fixtures/report_configuration.rs"]mod report_configuration;
#[path="../../dmb/shared/test_scratch.rs"]mod scratch;
fn main()->Result<(),Box<dyn std::error::Error>>{
 assert_eq!(include_bytes!("../src/sem/ctor_args.rs"),include_bytes!("../fixtures/original_policies/ctor_args.rs"),"reference ctor kernel must retain its exact frozen source");
 for(case,body)in fixture::CASES{let root=scratch::dir(&format!("lifeforms-original-{case}"));for(path,text)in fixture::files(case,body){let p=root.join(path);std::fs::create_dir_all(p.parent().unwrap())?;std::fs::write(p,text)?;}
  let mut reg=lint::Registry::default();original::register(&mut reg);let engine=dq_analyze::run::Engine::new(reg,dq_analyze::run::Options{root:root.clone(),lints:vec!["lifeforms".into()],no_cache:true,raw:true,..Default::default()})?;let model=sem::sem_for(&engine.tree).expect("valid whole-input controls require actual original Some");assert!(model.errors.is_empty(),"actual old fixture errors: {:?}",model.errors);let result=engine.run_one(engine.reg.lints[0].as_ref());println!("LIFEFORMS_WHOLE_ORIGINAL={}",serde_json::json!({"case":case,"sites":result.run.sites,"allow_used":result.allow_used,"notes":result.run.notes,"text":result.text,"failed":result.failed,"internal_error":result.internal_error}));
 }Ok(())
}

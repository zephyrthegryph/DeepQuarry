 use super::*;
 use dm_tree::frontend::{SettingExpressionQueries,SettingExpressionInput,OriginalInitializerExpressionInput,OriginalInitializerExpression,BodySyntaxFailure,OriginalSignatureAliasCensus,OriginalSignatureAliasGroup,BodySyntaxQueries,BodySyntaxInput,BodySyntax};
 #[path="../../dmb/shared/test_scratch.rs"]mod scratch;
 #[path="../../dmb/shared/original_analysis_test_host.rs"]mod original_host;
 #[path="../fixtures/original_policy_source.rs"]mod policy_source;
 impl BodySyntaxQueries for original_host::Host{
  fn syntax(&self,_:&Arc<BodySyntaxInput>)->Result<Arc<BodySyntax>,dm_tree::frontend::Diagnostic>{panic!("lineage fixture uses actual admitted Original bodies")}
  fn syntax_checked(&self,input:&Arc<BodySyntaxInput>)->Result<Arc<BodySyntax>,BodySyntaxFailure>{let mut answer=None;self.with_declaration_admission(&mut|a|{answer=Some(Arc::new(input.parse_with_setting_admission(a)?));Ok(())})?;Ok(answer.unwrap())}
 }
 #[test]
 fn actual_original_read_source_views_preserve_operation_root_and_fund_sibling_payload_until_drop(){
  use crate::reactive_global_source::Source;
  let root=scratch::dir("read-source-real-operation-root");std::fs::create_dir_all(root.join("code")).unwrap();
  std::fs::write(root.join("deepquarry.dme"),"#include \"code/probe.dm\"\n").unwrap();std::fs::write(root.join("code/probe.dm"),"/datum/lineage/proc/read()\n    return 0\n").unwrap();
  let provider=policy_source::Provider::new();let host=original_host::Host::new();let settings=host.clone()as Arc<dyn SettingExpressionQueries>;let seed=dm_tree::checker_builtins::original_analysis_seed().unwrap();let executor=dm_exec::BuildExecutor::new(1).unwrap();
  let frontend=dm_tree::frontend::build_for_original_analysis_with_state_checked(&root.join("deepquarry.dme"),&provider,&Default::default(),dm_tree::frontend::FrontendConfig{workers:1,engine:Some(seed.frontend_seed()),observer:None},None,&executor,None,&settings).unwrap().with_body_queries(host.clone()as Arc<dyn BodySyntaxQueries>).unwrap();
  let view=frontend.source_view().unwrap();assert!(view.receipt().errors().is_empty());
  let extra=view.files().iter().filter(|file|file.captured).map(|file|dm_analysis::policy_inputs::HostCapture::analyze_raw(Arc::clone(&file.path),dm_analysis::policy_inputs::PolicyRole::DmSource,provider.analyze_raw(&file.path,&file.text)));
  let inputs=PolicyInputs::capture_diagnostic(&view,extra).unwrap();
  let raw=CapturedRawPolicy::capture(&root,&inputs,crate::captured_raw_policy::Configuration::ProvenMissing).unwrap();
  let budget=Budget::new(8<<20).unwrap();let profile=inputs.archive().tree().checker_builtin_profile().unwrap();let proof=inputs.archive().tree().validated_checker_profile(profile).unwrap();
  for source in[ReadSource::native(&inputs,&root,&budget).unwrap(),ReadSource::native_validated(&inputs,&root,&budget,&proof,profile).unwrap(),ReadSource::capture(&raw,&inputs,&budget).unwrap()]{
   let baseline=budget.used();let fixed=std::mem::size_of::<Budget>()+2*std::mem::size_of::<usize>();
   let phase=Budget::scoped_temporaries(&budget).unwrap();phase.charge(4096).unwrap();let phase_payload=vec![3u8;4096];let live=budget.used();
   source.with_budget(&phase,|page|{
    assert!(Arc::ptr_eq(page.budget(),&phase));assert!(Arc::ptr_eq(Source::operation_budget(page),&budget));
    assert!(Budget::scoped_temporaries(page.budget()).is_err(),"retained work remains a real child, never silently flattened");
    let sibling=Budget::scoped_temporaries(Source::operation_budget(page)).unwrap();sibling.charge(8192).unwrap();let sibling_payload=vec![7u8;8192];assert_eq!(budget.used(),live+fixed+8192);
    page.with_budget(&sibling,|next|{assert!(Arc::ptr_eq(next.budget(),&sibling));assert!(Arc::ptr_eq(Source::operation_budget(next),&budget));phase.require().unwrap();assert_eq!(phase_payload[0],3);assert_eq!(sibling_payload[0],7);});
    drop(sibling_payload);drop(sibling);assert_eq!(budget.used(),live+fixed,"physical sibling payload ends before its actual lease refunds");
   });
   drop(phase_payload);drop(phase);assert_eq!(budget.used(),baseline+2*fixed,"same operation retains only its existing conservative scratch metadata");
  }
 }

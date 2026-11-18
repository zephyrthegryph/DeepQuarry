//! Ordinary argv becomes the existing native generation request, not an Engine.
use super::{GenerationRequest,client};
use crate::{GeneratorName,request::{BuildCommand,Command},policy_request::{AnalysisContext,PolicyInputRequest,WorkspacePolicyRequest}};
use std::{error::Error,io,path::PathBuf};
pub(super) const NAMES:[GeneratorName;12]=crate::generation_coordinator::OBSERVED_NAMES;
fn invalid(message:&str)->io::Error{io::Error::new(io::ErrorKind::InvalidInput,message)}
fn request(args:&[String])->Result<GenerationRequest,Box<dyn Error>>{
 let(mut root,mut cache,mut check)=(None,None,false);let mut selected=Vec::new();let mut at=0;
 while at<args.len(){let arg=&args[at];at+=1;match arg.as_str(){
  "--workspace"|"--cache-root"=>{let value=PathBuf::from(args.get(at).filter(|value|!value.is_empty()&&!value.starts_with("--")).ok_or_else(||invalid("generation path option needs a value"))?);at+=1;let slot=if arg=="--workspace"{&mut root}else{&mut cache};if slot.replace(value).is_some(){return Err(invalid("duplicate generation path option").into())}},
  "--check"=>check=true,
  value if value.starts_with("--")=>return Err(io::Error::new(io::ErrorKind::Unsupported,format!("ordinary native generation has no qualified implementation for {value}")).into()),
  value=>selected.push(value.to_owned()),
 }}
 let root=root.ok_or_else(||invalid("ordinary native generation needs --workspace"))?;if !root.is_absolute(){return Err(invalid("generation workspace must be absolute").into())}
 let names:Vec<_>=NAMES.into_iter().filter(|name|selected.is_empty()||selected.iter().any(|candidate|candidate==name.name())).collect();
 if names.is_empty(){return Err(invalid(&format!("analyze gen: no generator named {selected:?}")).into())}
 let Command::Build(build)=crate::cli::parse(&["prepare-query".into(),root.join("deepquarry.dme").to_string_lossy().into_owned()])?else{return Err(invalid("actual PrepareQuery request absent").into())};let mut build=*build;
 build.command=BuildCommand::PrepareQuery;build.engine_template=None;build.bootstrap_catalog=false;build.progress_enabled=false;build.exact_inputs=true;build.no_cache=false;build.workers=1;build.timeout_seconds=Some(300);
 if let Some(cache)=cache{if !cache.is_absolute(){return Err(invalid("generation cache must be absolute").into())}build.cache_root=Some(cache)}
 build.policy_inputs=Some(PolicyInputRequest{analysis_context:Some(AnalysisContext::OriginalAnalyze0290),workspace:Some(WorkspacePolicyRequest{root:root.clone(),recursive_roots:vec![root.join("code")],configuration:root.join("tools/ci/lint_scopes.toml")}),workspace_generators:names,..Default::default()});
 let request=GenerationRequest{build,check,bootstrap:None};request.validate()?;Ok(request)
}
pub fn run_arguments(args:&[String])->Result<bool,Box<dyn Error>>{let request=request(args)?;client::run_request(request,&mut io::stdout().lock(),true)}
#[cfg(test)]mod tests{
 use super::*;
 fn args(names:&[&str])->Vec<String>{let root=if cfg!(windows){"E:/source"}else{"/source"};let mut args=vec!["--workspace".into(),root.into()];args.extend(names.iter().map(|name|name.to_string()));args}
 #[test]fn ordinary_generation_argv_selects_canonical_order_and_keeps_check_as_no_write(){let r=request(&args(&["reads","--check","deps","reads","unknown"])).unwrap();assert!(r.check);let p=r.build.policy_inputs.unwrap();assert_eq!(p.workspace_generators,[GeneratorName::Deps,GeneratorName::Reads]);assert_eq!(p.analysis_context,Some(AnalysisContext::OriginalAnalyze0290));assert!(r.build.exact_inputs);assert_eq!(r.build.engine_template,None);assert!(!r.build.bootstrap_catalog);assert_eq!(r.build.timeout_seconds,Some(300));}
 #[test]fn ordinary_generation_argv_all_and_unknown_are_not_fake_empty_completion(){assert_eq!(request(&args(&[])).unwrap().build.policy_inputs.unwrap().workspace_generators,NAMES);assert!(request(&args(&["unknown"])).is_err());for unsupported in ["--timing","--selftest","--drop-declared"]{let error=request(&args(&[unsupported])).unwrap_err();assert_eq!(error.downcast_ref::<io::Error>().unwrap().kind(),io::ErrorKind::Unsupported)}}
 #[test]fn ordinary_generation_request_drives_real_original_coordinator_check_write_and_warm_state(){let(mut host,old,cache,root)=crate::generation_test_fixture::fixture();let mut args=args(&["deps"]);args[1]=root.to_string_lossy().into_owned();args.extend(["--cache-root".into(),cache.to_string_lossy().into_owned()]);let mut actual=request(&args).unwrap();actual.build.no_cache=true;let target=root.join("code/engine/_generated/deps.dm");let before=std::fs::read(&target).unwrap();let checked=crate::generation_coordinator::run(&mut host,&actual.build,&[GeneratorName::Deps],crate::generation_transaction::Mode::Check,&cache).unwrap();assert_eq!(checked.rows[0].state,crate::generation_transaction::State::Stale);assert_eq!(std::fs::read(&target).unwrap(),before);assert!(!checked.committed);let written=crate::generation_coordinator::run(&mut host,&actual.build,&[GeneratorName::Deps],crate::generation_transaction::Mode::Write,&cache).unwrap();assert!(written.committed);assert_eq!(written.rows[0].state,crate::generation_transaction::State::Written);let after=std::fs::read(&target).unwrap();assert_ne!(after,before);let warm=crate::generation_coordinator::run(&mut host,&actual.build,&[GeneratorName::Deps],crate::generation_transaction::Mode::Check,&cache).unwrap();assert_eq!(warm.rows[0].state,crate::generation_transaction::State::Fresh);assert_eq!(std::fs::read(&target).unwrap(),after);drop(old);}
}

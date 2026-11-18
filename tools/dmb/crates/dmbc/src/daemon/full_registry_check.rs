//! Selected report-only Analyze CHECK using the existing resident daemon.
use super::{protocol,transport,selected_report_wire as wire};
use crate::{request::{BuildRequest,Command},runner_host::{BuildHost,FullRegistryCheckOptions}};
use serde::{Deserialize,Serialize};use std::{error::Error,io,path::PathBuf};
#[derive(Debug,Deserialize,Serialize)]#[serde(deny_unknown_fields)]
pub(super)struct Request{pub(super)build:BuildRequest,pub(super)options:FullRegistryCheckOptions,#[serde(default)]pub(super)selectors:Vec<String>,#[serde(default,skip_serializing_if="is_false")]pub(super)selftests:bool,#[serde(default,skip_serializing_if="Option::is_none")]pub(super)caller_directory:Option<PathBuf>,#[serde(default,skip_serializing_if="Option::is_none")]pub(super)cli:Option<dq_analyze::native_check_cli_wire::Request>}
fn is_false(value:&bool)->bool{!*value}
fn invalid(message:&str)->io::Error{io::Error::new(io::ErrorKind::InvalidInput,message)}
impl Request{pub(super)fn qualify(&self)->io::Result<()>{
 let metadata=self.selectors.capacity().checked_mul(std::mem::size_of::<String>()).and_then(|n|self.selectors.iter().try_fold(n,|n,selector|n.checked_add(selector.capacity()))).and_then(|n|n.checked_add(self.caller_directory.as_ref().map_or(0,|path|path.as_os_str().len().saturating_mul(4)))).and_then(|n|n.checked_add(256)).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;
 let metadata=metadata.checked_add(self.cli.as_ref().map_or(Ok(0),|cli|cli.metadata_charge())?).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;
 if let Some(cli)=&self.cli{cli.qualify(self.options,self.selftests)?;}
 if metadata>protocol::MAX_FRAME{return Err(io::Error::new(io::ErrorKind::OutOfMemory,"CHECK selector control exceeds the existing protocol metadata envelope"))}
 if self.build.timeout_seconds.is_none()||!self.build.defines.is_empty()||self.build.warnings!=crate::diagnostics::WarningPolicy::default()||(self.options.no_cache&&!self.build.no_cache){return Err(invalid("native CHECK requires its explicit original preparation deadline/default settings and requested cache mode"))}
 if (!self.selftests&&self.caller_directory.is_some())||self.caller_directory.as_ref().is_some_and(|path|!path.is_absolute()){return Err(invalid("native callback caller directory differs from request mode"))}
 BuildHost::native_registry_check_paths(&self.build)?;Ok(())
}}
pub(super) fn invocation(args:&[String])->Result<Request,Box<dyn Error>>{invocation_with_cli(args,None)}
fn invocation_with_cli(args:&[String],cli:Option<dq_analyze::native_check_cli_wire::Request>)->Result<Request,Box<dyn Error>>{invocation_mode(args,cli,false)}
pub(super)fn invocation_selftests(args:&[String])->Result<Request,Box<dyn Error>>{invocation_mode(args,None,true)}
fn invocation_mode(args:&[String],cli:Option<dq_analyze::native_check_cli_wire::Request>,standalone:bool)->Result<Request,Box<dyn Error>>{
 let mut ordinary=vec!["dmbc".to_owned(),"check".to_owned()];ordinary.extend(args.iter().map(|arg|if arg=="--workspace"{"--root".into()}else{arg.clone()}));
 let parsed=dq_analyze::cli_arguments::parse(ordinary);
 for flag in &parsed.flags{if !standalone&&!matches!(flag.as_str(),"--raw"|"--ci"|"--unused"|"--no-unused"|"--no-selftest"|"--no-cache"|"--rehash"){return Err(io::Error::new(io::ErrorKind::Unsupported,format!("unimplemented native CHECK option {flag}; no fallback")).into())}}
 let has=|name:&str|parsed.flags.iter().any(|flag|flag==name);
 let selftests=standalone||!has("--no-selftest");
 if !standalone&&cli.is_none()&&std::env::var("DQ_ALLOW_USAGE").is_ok(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"CHECK ALLOW usage presence needs its explicit bounded observation request").into())}
 let options=if standalone{FullRegistryCheckOptions{unused:false,..Default::default()}}else{FullRegistryCheckOptions{raw:has("--raw"),ci:has("--ci"),unused:!has("--no-unused"),no_cache:has("--no-cache"),rehash:has("--rehash")}};
 if let Some(cli)=&cli{cli.qualify(options,selftests)?;}
 let root=parsed.root.filter(|root|root.is_absolute()).ok_or_else(||invalid("native CHECK requires an absolute workspace root"))?;let root=std::fs::canonicalize(root)?;let cache=std::fs::canonicalize(crate::request::client_cache_root()?)?;
 let Command::Build(build)=crate::cli::parse(&["prepare-query".into(),root.join("deepquarry.dme").to_string_lossy().into_owned()])?else{return Err(invalid("expected actual preparation request").into())};
 let mut build=*build;build.no_cache=options.no_cache;build.exact_inputs=true;build.progress_enabled=false;build.workers=2;build.timeout_seconds=Some(300);build.engine_template=None;build.bootstrap_catalog=false;build.cache_root=Some(cache);
 use crate::policy_request::{PolicyInputRequest,WorkspacePolicyRequest,AnalysisContext,WorkspaceAuxiliaryQuestion as Q};let roots=Q::authored_doc_ui_roots(Q::PRIVATE_FULL_REGISTRY).ok_or_else(||invalid("actual full registry has no authored roots"))?;
 build.policy_inputs=Some(PolicyInputRequest{analysis_context:Some(AnalysisContext::OriginalAnalyze0290),workspace:Some(WorkspacePolicyRequest{root:root.clone(),recursive_roots:roots.iter().map(|path|root.join(path)).collect(),configuration:root.join("tools/ci/lint_scopes.toml")}),..Default::default()});
 let caller_directory=if selftests{
  let budget=dq_analyze::captured_generator_budget::Budget::new(dq_analyze::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES).map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))?;
  let selected=dq_analyze::captured_registry_check_selection::select(&parsed.lints,&budget,&||super::control::checkpoint()).map_err(|failure|match failure{dq_analyze::captured_reactive_reads::Failure::Operational(actual)=>actual,dq_analyze::captured_reactive_reads::Failure::Unsupported(message)=>io::Error::new(io::ErrorKind::Unsupported,message)})?;
  if selected.names().iter().any(|name|matches!(name.as_str(),"ui_actions"|"check_grep")){Some(std::env::current_dir()?)}else{None}
 }else{None};
 let request=Request{build,options,selectors:parsed.lints,selftests,caller_directory,cli};request.qualify()?;Ok(request)
}
pub fn run_cli(args:&[String])->Result<bool,Box<dyn Error>>{
 let stdin_mode=args.iter().filter(|arg|arg.as_str()=="--cli-stdin").count();if stdin_mode>1{return Err(invalid("CHECK observation input mode was repeated").into())}
 let cli=if stdin_mode==1{Some(protocol::receive::<dq_analyze::native_check_cli_wire::Request>(&mut io::stdin().lock())?)}else{None};
 let request=if stdin_mode==0{invocation(args)?}else{let ordinary:Vec<_>=args.iter().filter(|arg|arg.as_str()!="--cli-stdin").cloned().collect();invocation_with_cli(&ordinary,cli)?};let(_,cache)=BuildHost::native_registry_check_paths(&request.build)?;let expected=request.options;let selftests=request.selftests;
 let selection=dq_analyze::full_registry_check_selection_wire::SelectionBinding::for_selectors_using(&request.selectors,&||super::control::checkpoint())?;
 super::build_admission::validate(&request.build)?;let mut stream=super::connect_generation()?;transport::set_timeout(&mut stream,transport::BUILD_DEADLINE)?;let request=protocol::Request::FullRegistryCheck(request);protocol::send(&mut stream,&request)?;
 let protocol::Request::FullRegistryCheck(ref actual)=request else{unreachable!("same CHECK request variant")};
 wire::receive_full_check_cli(&mut stream,&cache,expected,selection,selftests,actual.cli.as_ref())?.publish(&mut io::stdout().lock()).map_err(Into::into)
}
#[cfg(test)]mod tests{use super::*;
 #[test]fn request_options_cannot_smuggle_compile_or_unknown_flags(){let(_,build,_,_)=crate::generation_test_fixture::fixture();let request=Request{build,options:FullRegistryCheckOptions::default(),selectors:vec!["sem".into(),"-sem/reads".into()],selftests:false,caller_directory:None,cli:None};let mut data=serde_json::to_value(&request).unwrap();data["compile"]=serde_json::json!(true);assert!(serde_json::from_value::<Request>(data).is_err());for args in[vec!["--changed-only".into()],vec!["--timing".into()]]{assert!(invocation(&args).unwrap_err().to_string().contains("unimplemented"));}}
}

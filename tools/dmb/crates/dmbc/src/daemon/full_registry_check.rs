//! Read-only full Analyze CHECK over the existing resident daemon. No native
//! compilation, output pair, .dmb/.rsc or legacy engine fallback is requested.
use super::{protocol,transport,selected_report_wire as wire};
use crate::{request::{BuildRequest,Command},runner_host::{BuildHost,FullRegistryCheckOptions}};
use serde::{Deserialize,Serialize};
use std::{error::Error,io,path::PathBuf};
#[derive(Debug,Deserialize,Serialize)]
#[serde(deny_unknown_fields)]
pub(super)struct Request{pub(super)build:BuildRequest,pub(super)options:FullRegistryCheckOptions}
impl Request{pub(super)fn qualify(&self)->io::Result<()>{
 if self.build.timeout_seconds.is_none()||!self.build.no_cache||!self.build.defines.is_empty()
  ||self.build.warnings!=crate::diagnostics::WarningPolicy::default(){return Err(invalid("full registry check requires its explicit exact original preparation deadline/default settings"))}
 BuildHost::compound_report_paths(&self.build,wire::CompoundRoster::FullRegistry)?;Ok(())
}}
fn invalid(message:&str)->io::Error{io::Error::new(io::ErrorKind::InvalidInput,message)}
fn invocation(args:&[String])->Result<Request,Box<dyn Error>>{
 let(mut root,mut no_selftest)=(None,false);let mut options=FullRegistryCheckOptions::default();let mut at=0;
 while at<args.len(){let arg=&args[at];at+=1;match arg.as_str(){
  "--workspace"=>{let value=args.get(at).ok_or_else(||invalid("--workspace needs one absolute actual source root"))?;at+=1;if root.replace(PathBuf::from(value)).is_some(){return Err(invalid("only one workspace root is accepted").into())}},
  "--raw"=>options.raw=true,"--ci"=>options.ci=true,"--unused"=>{},"--no-unused"=>options.unused=false,"--no-selftest"=>no_selftest=true,
  _=>return Err(io::Error::new(io::ErrorKind::Unsupported,format!("unimplemented full native check option {arg}; no fallback")).into()),
 }}
 if !no_selftest{return Err(io::Error::new(io::ErrorKind::Unsupported,"full native check requires explicit --no-selftest until native fixtures are qualified").into())}
 if std::env::var_os("DQ_ALLOW_USAGE").is_some(){return Err(io::Error::new(io::ErrorKind::Unsupported,"full native check DQ_ALLOW_USAGE export is not yet qualified").into())}
 let root=root.filter(|root|root.is_absolute()).ok_or_else(||invalid("full native check requires an absolute workspace root"))?;
 let root=std::fs::canonicalize(root)?;let cache=std::fs::canonicalize(crate::request::client_cache_root()?)?;
 let Command::Build(build)=crate::cli::parse(&["prepare-query".into(),root.join("deepquarry.dme").to_string_lossy().into_owned()])?else{return Err(invalid("expected actual preparation request").into())};
 let mut build=*build;build.no_cache=true;build.exact_inputs=true;build.progress_enabled=false;build.workers=2;build.timeout_seconds=Some(300);build.engine_template=None;build.bootstrap_catalog=false;build.cache_root=Some(cache);
 use crate::policy_request::{PolicyInputRequest,WorkspacePolicyRequest,AnalysisContext,WorkspaceAuxiliaryQuestion as Q};
 let roots=Q::authored_doc_ui_roots(Q::PRIVATE_FULL_REGISTRY).ok_or_else(||invalid("actual full registry has no authored roots"))?;
 build.policy_inputs=Some(PolicyInputRequest{analysis_context:Some(AnalysisContext::OriginalAnalyze0290),workspace:Some(WorkspacePolicyRequest{root:root.clone(),recursive_roots:roots.iter().map(|path|root.join(path)).collect(),configuration:root.join("tools/ci/lint_scopes.toml")}),..Default::default()});
 let request=Request{build,options};request.qualify()?;Ok(request)
}
pub fn run_cli(args:&[String])->Result<bool,Box<dyn Error>>{
 let request=invocation(args)?;let(_,cache)=BuildHost::compound_report_paths(&request.build,wire::CompoundRoster::FullRegistry)?;let expected=request.options;
 super::build_admission::validate(&request.build)?;let mut stream=super::connect_generation()?;transport::set_timeout(&mut stream,transport::BUILD_DEADLINE)?;
 protocol::send(&mut stream,&protocol::Request::FullRegistryCheck(request))?;
 let completed=wire::receive_full_check(&mut stream,&cache,expected)?;
 completed.publish(&mut io::stderr().lock(),&mut io::stdout().lock()).map_err(Into::into)
}
#[cfg(test)]mod tests{
 use super::*;
 #[test]fn request_options_cannot_smuggle_compile_or_unknown_selection_mode(){
  let(_,build,_,_)=crate::generation_test_fixture::fixture();let request=Request{build,options:FullRegistryCheckOptions::default()};let mut data=serde_json::to_value(&request).unwrap();
  data["compile"]=serde_json::json!(true);assert!(serde_json::from_value::<Request>(data).is_err());
  for args in[vec!["--changed-only".into()],vec!["--lint".into(),"scheduler".into()]]{assert!(invocation(&args).unwrap_err().to_string().contains("unimplemented"));}
 }
}

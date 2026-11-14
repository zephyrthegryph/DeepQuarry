//! Selected report-only Analyze CHECK using the existing resident daemon.
use super::{protocol,transport,selected_report_wire as wire};
use crate::{request::{BuildRequest,Command},runner_host::{BuildHost,FullRegistryCheckOptions}};
use serde::{Deserialize,Serialize};use std::{error::Error,io,path::PathBuf};
#[derive(Debug,Deserialize,Serialize)]#[serde(deny_unknown_fields)]
pub(super)struct Request{pub(super)build:BuildRequest,pub(super)options:FullRegistryCheckOptions,#[serde(default)]pub(super)selectors:Vec<String>}
fn invalid(message:&str)->io::Error{io::Error::new(io::ErrorKind::InvalidInput,message)}
impl Request{pub(super)fn qualify(&self)->io::Result<()>{
 let metadata=self.selectors.capacity().checked_mul(std::mem::size_of::<String>()).and_then(|n|self.selectors.iter().try_fold(n,|n,selector|n.checked_add(selector.capacity()))).and_then(|n|n.checked_add(256)).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;
 if metadata>protocol::MAX_FRAME{return Err(io::Error::new(io::ErrorKind::OutOfMemory,"CHECK selector control exceeds the existing protocol metadata envelope"))}
 if self.build.timeout_seconds.is_none()||!self.build.defines.is_empty()||self.build.warnings!=crate::diagnostics::WarningPolicy::default()||(self.options.no_cache&&!self.build.no_cache){return Err(invalid("native CHECK requires its explicit original preparation deadline/default settings and requested cache mode"))}
 BuildHost::native_registry_check_paths(&self.build)?;Ok(())
}}
fn invocation(args:&[String])->Result<Request,Box<dyn Error>>{
 let mut ordinary=vec!["dmbc".to_owned(),"check".to_owned()];ordinary.extend(args.iter().map(|arg|if arg=="--workspace"{"--root".into()}else{arg.clone()}));
 let parsed=dq_analyze::cli_arguments::parse(ordinary);
 for flag in &parsed.flags{if !matches!(flag.as_str(),"--raw"|"--ci"|"--unused"|"--no-unused"|"--no-selftest"|"--no-cache"|"--rehash"){return Err(io::Error::new(io::ErrorKind::Unsupported,format!("unimplemented native CHECK option {flag}; no fallback")).into())}}
 let has=|name:&str|parsed.flags.iter().any(|flag|flag==name);
 if !has("--no-selftest"){return Err(io::Error::new(io::ErrorKind::Unsupported,"native CHECK requires explicit --no-selftest until native fixtures are qualified").into())}
 if std::env::var_os("DQ_ALLOW_USAGE").is_some(){return Err(io::Error::new(io::ErrorKind::Unsupported,"native CHECK DQ_ALLOW_USAGE export is not yet qualified").into())}
 let options=FullRegistryCheckOptions{raw:has("--raw"),ci:has("--ci"),unused:!has("--no-unused"),no_cache:has("--no-cache"),rehash:has("--rehash")};
 let root=parsed.root.filter(|root|root.is_absolute()).ok_or_else(||invalid("native CHECK requires an absolute workspace root"))?;let root=std::fs::canonicalize(root)?;let cache=std::fs::canonicalize(crate::request::client_cache_root()?)?;
 let Command::Build(build)=crate::cli::parse(&["prepare-query".into(),root.join("deepquarry.dme").to_string_lossy().into_owned()])?else{return Err(invalid("expected actual preparation request").into())};
 let mut build=*build;build.no_cache=options.no_cache;build.exact_inputs=true;build.progress_enabled=false;build.workers=2;build.timeout_seconds=Some(300);build.engine_template=None;build.bootstrap_catalog=false;build.cache_root=Some(cache);
 use crate::policy_request::{PolicyInputRequest,WorkspacePolicyRequest,AnalysisContext,WorkspaceAuxiliaryQuestion as Q};let roots=Q::authored_doc_ui_roots(Q::PRIVATE_FULL_REGISTRY).ok_or_else(||invalid("actual full registry has no authored roots"))?;
 build.policy_inputs=Some(PolicyInputRequest{analysis_context:Some(AnalysisContext::OriginalAnalyze0290),workspace:Some(WorkspacePolicyRequest{root:root.clone(),recursive_roots:roots.iter().map(|path|root.join(path)).collect(),configuration:root.join("tools/ci/lint_scopes.toml")}),..Default::default()});
 let request=Request{build,options,selectors:parsed.lints};request.qualify()?;Ok(request)
}
pub fn run_cli(args:&[String])->Result<bool,Box<dyn Error>>{
 let request=invocation(args)?;let(_,cache)=BuildHost::native_registry_check_paths(&request.build)?;let expected=request.options;
 let selection=dq_analyze::full_registry_check_selection_wire::SelectionBinding::for_selectors_using(&request.selectors,&||super::control::checkpoint())?;
 super::build_admission::validate(&request.build)?;let mut stream=super::connect_generation()?;transport::set_timeout(&mut stream,transport::BUILD_DEADLINE)?;protocol::send(&mut stream,&protocol::Request::FullRegistryCheck(request))?;
 wire::receive_full_check(&mut stream,&cache,expected,selection)?.publish(&mut io::stdout().lock()).map_err(Into::into)
}
#[cfg(test)]mod tests{use super::*;
 #[test]fn request_options_cannot_smuggle_compile_or_unknown_flags(){let(_,build,_,_)=crate::generation_test_fixture::fixture();let request=Request{build,options:FullRegistryCheckOptions::default(),selectors:vec!["sem".into(),"-sem/reads".into()]};let mut data=serde_json::to_value(&request).unwrap();data["compile"]=serde_json::json!(true);assert!(serde_json::from_value::<Request>(data).is_err());for args in[vec!["--changed-only".into()],vec!["--timing".into()]]{assert!(invocation(&args).unwrap_err().to_string().contains("unimplemented"));}}
}

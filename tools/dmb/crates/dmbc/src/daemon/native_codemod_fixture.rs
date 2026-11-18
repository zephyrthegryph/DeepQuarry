//! Typed ordinary codemod/fixture utility on the existing retained native host.
//! No model/parser acquisition occurs in this request DATA adapter.
use serde::{Serialize,Deserialize};
use std::io;
use crate::request::{BuildRequest,BuildCommand};
use dq_analyze::native_codemod_fixture_wire::Binding;
#[derive(Debug,Serialize,Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) struct Request{pub(super) build:BuildRequest,pub(super) binding:Binding}
impl Request{
 pub(super) fn qualify(&self)->io::Result<()>{
  use crate::policy_request::{AnalysisContext,WorkspaceAuxiliaryQuestion as Q};
  self.binding.validate()?;let b=&self.build;let invalid=||io::Error::new(io::ErrorKind::InvalidInput,"ordinary codemod/fixture utility requires its exact live Original model intent");
  if b.command!=BuildCommand::PrepareQuery||b.timeout_seconds.is_none()||!b.no_cache||!b.exact_inputs||b.no_daemon||!b.defines.is_empty()||b.engine_template.is_some()||b.bootstrap_catalog||b.record_inputs.is_some()||b.replay_inputs.is_some()||b.artifact_directory.is_some()||b.output_store.is_some()||b.trace_path.is_some()||b.source_questions.is_some()||b.diagnostic_declarations||b.warnings!=crate::diagnostics::WarningPolicy::default(){return Err(invalid())}
  let p=b.policy_inputs.as_ref().ok_or_else(invalid)?;let w=p.workspace.as_ref().ok_or_else(invalid)?;
  let expected:&[Q]=&[Q::SemReads];
  if p.analysis_context!=Some(AnalysisContext::OriginalAnalyze0290)||p.workspace_auxiliary!=expected||!p.workspace_generators.is_empty()||!p.files.is_empty()||!p.search_folders.is_empty()||w.root!=self.binding.root||w.recursive_roots!=[w.root.join("code"),w.root.join("maps")]||w.configuration!=w.root.join("tools/ci/lint_scopes.toml")||b.project!=w.root.join("deepquarry.dme"){return Err(invalid())}
  super::build_admission::validate(b).map_err(io::Error::other)?;super::generation::validate_cache(b)
 }
}

pub fn run_cli(args:&[String])->Result<u8,Box<dyn std::error::Error>>{
 let mut root=None;let mut stdin=false;let mut at=0;while let Some(arg)=args.get(at){at+=1;match arg.as_str(){"--root"=>{let path=std::path::PathBuf::from(args.get(at).ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"utility root value missing"))?);at+=1;if root.replace(path).is_some(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"utility root repeated").into())}},"--binding-stdin" if !stdin=>stdin=true,_=>return Err(io::Error::new(io::ErrorKind::InvalidInput,"native utility accepts only its sealed root/binding channel").into())}}
 let root=root.filter(|root|root.is_absolute()).ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"native utility requires an absolute root"))?;if !stdin{return Err(io::Error::new(io::ErrorKind::InvalidInput,"native utility binding channel absent").into())}
 let binding:Binding=super::protocol::receive(&mut io::stdin().lock())?;binding.validate()?;if binding.root!=root{return Err(io::Error::new(io::ErrorKind::InvalidInput,"native utility root differs from typed binding").into())}
 let root=std::fs::canonicalize(root)?;if binding.root!=root{return Err(io::Error::new(io::ErrorKind::InvalidInput,"native utility root must use its actual canonical spelling").into())}let cache=std::fs::canonicalize(crate::request::client_cache_root()?)?;
 let build=build_for_binding(&binding,&cache)?;
 let request=Request{build,binding};request.qualify()?;super::build_admission::validate(&request.build)?;let mut stream=super::connect_generation()?;super::transport::set_timeout(&mut stream,super::transport::BUILD_DEADLINE)?;let command=super::protocol::Request::NativeUtility(super::native_utility::Request::CodemodFixture(request));
 let expected=match &command{super::protocol::Request::NativeUtility(super::native_utility::Request::CodemodFixture(request))=>&request.binding,_=>unreachable!("closed utility command constructor")};super::protocol::send(&mut stream,&command)?;
 let delivered=super::selected_report_wire::receive_native_codemod_fixture(&mut stream,&cache,expected)?;let terminal=delivered.publish_wire(&mut io::stdout().lock())?;Ok(u8::try_from(terminal.exit).map_err(|_|io::Error::new(io::ErrorKind::InvalidData,"utility terminal status exceeds CLI exit range"))?)
}

fn build_for_binding(binding:&Binding,cache:&std::path::Path)->Result<BuildRequest,Box<dyn std::error::Error>>{let root=&binding.root;
 let crate::request::Command::Build(build)=crate::cli::parse(&["prepare-query".into(),root.join("deepquarry.dme").to_string_lossy().into_owned()])?else{return Err(io::Error::other("utility preparation request factory differs").into())};let mut build=*build;build.no_cache=true;build.exact_inputs=true;build.progress_enabled=false;build.workers=2;build.timeout_seconds=Some(300);build.engine_template=None;build.bootstrap_catalog=false;build.cache_root=Some(cache.to_path_buf());
 use crate::policy_request::{PolicyInputRequest,WorkspacePolicyRequest,AnalysisContext,WorkspaceAuxiliaryQuestion as Q};let questions=vec![Q::SemReads];
 build.policy_inputs=Some(PolicyInputRequest{analysis_context:Some(AnalysisContext::OriginalAnalyze0290),workspace:Some(WorkspacePolicyRequest{root:root.to_path_buf(),recursive_roots:vec![root.join("code"),root.join("maps")],configuration:root.join("tools/ci/lint_scopes.toml")}),workspace_auxiliary:questions,..Default::default()});

 Ok(build)
}


#[cfg(test)]
#[path="native_utility_delivery_controls.rs"]
mod delivery_controls;

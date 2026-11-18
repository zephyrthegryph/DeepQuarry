//! Optional native Checker-compatible text core on a caller's existing BuildHost.
//! No daemon or parser is created here, and no compile/output-pair is requested.
//! Initial scope: explicit absolute -e and optional absolute -c, text mode.
use crate::{request::{BuildRequest,BuildOutcome,BuildCommand},runner_host::BuildHost};
use std::{error::Error,io::{self,Write},path::PathBuf};
#[derive(Clone,Debug,serde::Serialize,serde::Deserialize)]#[serde(deny_unknown_fields)]pub struct Request{pub project:PathBuf,pub configuration:Option<PathBuf>,pub cache_root:PathBuf,pub workers:usize,pub timeout_seconds:u16}
#[derive(Clone,Debug,serde::Serialize)]pub struct Outcome{pub json:bool,pub parser:Option<dq_analyze::native_checker_wire::ParserCounts>,pub emitted:usize,pub visited_bodies:usize,pub exit_code:i32,pub semantic_revision:u128,pub source_revision:u128,pub policy_revision:u128,pub full_checker_parity:bool}
impl Request{
 pub fn from_arguments(arguments:&[String],cache_root:PathBuf)->io::Result<Self>{
  let(mut project,mut configuration)=(None,None);let mut args=arguments.iter();
  while let Some(arg)=args.next(){match arg.as_str(){
   "-e"=>{if project.is_some(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"duplicate -e"))}project=Some(PathBuf::from(args.next().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"-e needs an environment"))?));},
   "-c"=>{if configuration.is_some(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"duplicate -c"))}configuration=Some(PathBuf::from(args.next().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"-c needs a configuration"))?));},
   "--json"|"--parse-only"|"--version"|"-V"=>return Err(io::Error::new(io::ErrorKind::Unsupported,"this optional native Checker core has not issued that reference CLI mode")),
   _=>return Err(io::Error::new(io::ErrorKind::InvalidInput,format!("unknown native Checker argument: {arg}"))),
  }}
  let request=Self{project:project.ok_or_else(||io::Error::new(io::ErrorKind::Unsupported,"native Checker initial scope requires explicit -e; environment autodetection is unissued"))?,configuration,cache_root,workers:2,timeout_seconds:300};request.validate()?;Ok(request)
 }
 fn validate(&self)->io::Result<()>{
  if self.project.as_os_str().len()>65536||self.cache_root.as_os_str().len()>65536||self.configuration.as_ref().is_some_and(|p|p.as_os_str().len()>65536)||!self.project.is_absolute()||!self.cache_root.is_absolute()||self.configuration.as_ref().is_some_and(|p|!p.is_absolute())||self.workers==0||self.workers>2{return Err(io::Error::new(io::ErrorKind::InvalidInput,"native Checker initial scope requires caller-absolute paths and one or two workers"))}
  crate::request::validate_timeout_seconds(Some(self.timeout_seconds))
 }
 pub(crate) fn build(&self)->Result<BuildRequest,Box<dyn Error>>{
  use crate::policy_request::{AnalysisContext,PolicyInputFile,PolicyInputRole,PolicyInputRequest};
  self.validate()?;
  let project=crate::policy_request::canonical_analysis_project(&self.project,Some(AnalysisContext::OriginalChecker0290))?;
  let configuration=self.configuration.clone().unwrap_or_else(||project.with_file_name("SpacemanDMM.toml"));
  Ok(BuildRequest{command:BuildCommand::PrepareQuery,source_questions:None,diagnostic_declarations:false,timeout_seconds:Some(self.timeout_seconds),
   policy_inputs:Some(PolicyInputRequest{analysis_context:Some(AnalysisContext::OriginalChecker0290),files:vec![
    PolicyInputFile{path:project.clone(),role:PolicyInputRole::DmSource,required:true},PolicyInputFile{path:configuration,role:PolicyInputRole::Configuration,required:false},
   ],..Default::default()}),project,defines:Default::default(),workers:self.workers,engine_template:None,bootstrap_catalog:false,progress_enabled:false,
   output_store:None,exact_inputs:true,no_cache:true,cache_root:Some(self.cache_root.clone()),record_inputs:None,replay_inputs:None,artifact_directory:None,no_daemon:false,trace_path:None,warnings:Default::default()})
 }
}
/// Result1 is an actual complete visible diagnostic result; Err is operational,
/// unissued source/grammar/configuration/chronology, or output failure—not clean.
/// No default CLI or daemon dispatch is activated by this in-process function.
pub fn run(request:Request,host:&mut BuildHost,stdout:&mut impl Write,stderr:&mut impl Write)->Result<Outcome,Box<dyn Error>>{
 run_with_json(request,false,host,stdout,stderr)
}
/// Explicit pinned JSON-count mode over the same actual complete native run.
pub fn run_with_json(request:Request,json:bool,host:&mut BuildHost,stdout:&mut impl Write,stderr:&mut impl Write)->Result<Outcome,Box<dyn Error>>{
 run_with_mode(request,json,false,host,stdout,stderr)
}
/// Explicit syntax-only operation, including a typed formal-fatal prefix.
pub fn run_parse_only(request:Request,json:bool,host:&mut BuildHost,stdout:&mut impl Write,stderr:&mut impl Write)->Result<Outcome,Box<dyn Error>>{run_with_mode(request,json,true,host,stdout,stderr)}
fn run_with_mode(request:Request,json:bool,parse_only:bool,host:&mut BuildHost,stdout:&mut impl Write,stderr:&mut impl Write)->Result<Outcome,Box<dyn Error>>{
 use crate::daemon::{control,prepare_deadline};
 if !host.retains_artifacts(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"native Checker needs the existing retained host").into())}
 request.validate()?;
 let deadline=prepare_deadline::capture(BuildCommand::PrepareQuery,Some(request.timeout_seconds),std::time::Instant::now())?.ok_or_else(||io::Error::other("Checker deadline absent"))?;
 let _binding=if control::WorkerContext::capture_for_checkpoints().is_none(){
  if control::current_deadline().is_some(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"native Checker cannot start under publication masking").into())}Some(control::bind_with_deadline(control::Cancellation::default(),deadline))
 }else{if control::current_deadline().is_none_or(|old|old>deadline){return Err(io::Error::new(io::ErrorKind::InvalidInput,"native Checker cannot extend inherited request deadline").into())}None};
 control::checkpoint()?;
 let width=request.project.as_os_str().len().checked_add(request.cache_root.as_os_str().len()).and_then(|n|n.checked_add(request.configuration.as_ref().map_or(0,|p|p.as_os_str().len()))).and_then(|n|n.checked_mul(16)).and_then(|n|n.checked_add(65536)).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;
 let _request_credit=host.source_arena_work().reserve(width)?;
 let build=request.build()?;let(outcome,_inputs)=run_prepared_with_mode(build,&request.project,None,request.configuration.as_deref(),json,parse_only,host,stdout,stderr)?;Ok(outcome)
}

/// SAME Checker execution after the existing daemon admitted its actual request.
/// The moved source ledger survives staging and is revalidated during transport.
pub(crate) fn run_prepared(build:BuildRequest,display_environment:&std::path::Path,explicit_configuration:Option<&std::path::Path>,host:&mut BuildHost,stdout:&mut impl Write,stderr:&mut impl Write)->Result<(Outcome,crate::request_runner::checker_capture::Inputs),Box<dyn Error>>{
 run_prepared_with_json(build,display_environment,explicit_configuration,false,host,stdout,stderr)
}
pub(crate) fn run_prepared_with_json(build:BuildRequest,display_environment:&std::path::Path,explicit_configuration:Option<&std::path::Path>,json:bool,host:&mut BuildHost,stdout:&mut impl Write,stderr:&mut impl Write)->Result<(Outcome,crate::request_runner::checker_capture::Inputs),Box<dyn Error>>{
 run_prepared_with_caller(build,display_environment,None,explicit_configuration,json,host,stdout,stderr)
}
pub(crate) fn run_prepared_with_caller(build:BuildRequest,display_environment:&std::path::Path,caller_directory:Option<&std::path::Path>,explicit_configuration:Option<&std::path::Path>,json:bool,host:&mut BuildHost,stdout:&mut impl Write,stderr:&mut impl Write)->Result<(Outcome,crate::request_runner::checker_capture::Inputs),Box<dyn Error>>{
 run_prepared_with_mode(build,display_environment,caller_directory,explicit_configuration,json,false,host,stdout,stderr)
}
pub(crate) fn run_prepared_with_mode(build:BuildRequest,display_environment:&std::path::Path,caller_directory:Option<&std::path::Path>,explicit_configuration:Option<&std::path::Path>,json:bool,parse_only:bool,host:&mut BuildHost,stdout:&mut impl Write,stderr:&mut impl Write)->Result<(Outcome,crate::request_runner::checker_capture::Inputs),Box<dyn Error>>{
 use crate::daemon::control;
 if crate::daemon::control::WorkerContext::capture_for_checkpoints().is_none()||crate::daemon::control::current_deadline().is_none(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"Checker staging requires its existing original request binding").into())}
 require_prepared_shape_with_caller(&build,display_environment,caller_directory,explicit_configuration)?;control::checkpoint()?;
 if let Some(caller)=caller_directory{
  // The existing physical source role and its actual moved ledger remain the
  // only source authority. This initial relative spelling must name that SAME
  // canonical key lexically; unresolved symlink aliases need a separate proof.
  if display_environment.is_absolute()||dm_preprocess::regions::canonical_path(&caller.join(display_environment))!=build.project{return Err(io::Error::new(io::ErrorKind::Unsupported,"relative Checker spelling requires a separately authenticated alias").into())}
 }else if std::fs::canonicalize(display_environment)?!=build.project{return Err(io::Error::new(io::ErrorKind::InvalidInput,"Checker display environment differs from actual canonical project").into())}
 control::checkpoint()?;
 let project=build.project.clone();let cache_root=build.cache_root.clone().ok_or_else(||io::Error::other("Checker actual cache root absent"))?;

 let mut stdout=CheckedOutput(stdout);let mut stderr=CheckedOutput(stderr);
 writeln!(stdout,"============================================================\nParsing {}...\n",display_environment.display())?;
 // Preparation text is private: success re-renders typed notices from the
 // SAME retained owner. Fatal preparation remains a distinct Err, never a
 // synthetic full Checker report assembled from compiler diagnostic text.

 if parse_only{
  let prepared=crate::request_runner::prepare_parse_only_syntax(build,host).map_err(|first|parse_only_invariant_context("actual parse-only syntax preparation rejected its source invariant",first))?;prepared.inputs.require_current(&project)?;
  let transcript=host.stage_parse_only_cli(&prepared,&project,explicit_configuration,&cache_root).map_err(|first|parse_only_invariant_context("actual parse-only transcript rejected its source invariant",Box::new(first)))?;prepared.inputs.require_current(&project)?;
  let counts=transcript.counts;let parser=dq_analyze::native_checker_wire::ParserCounts{good:u64::try_from(transcript.good).map_err(|_|io::Error::from(io::ErrorKind::OutOfMemory))?,bad:u64::try_from(transcript.bad).map_err(|_|io::Error::from(io::ErrorKind::OutOfMemory))?,fatal:transcript.fatal};
  let outcome=Outcome{json,parser:Some(parser),emitted:transcript.emitted,visited_bodies:0,exit_code:if transcript.emitted==0{0}else{1},semantic_revision:transcript.semantic,source_revision:transcript.source,policy_revision:transcript.policy,full_checker_parity:false};transcript.publish(&mut stderr)?;
  prepared.inputs.require_current(&project)?;writeln!(stdout,"============================================================\nFound {} diagnostics",outcome.emitted)?;if json{counts.write_json(&mut stdout)?;}stdout.flush()?;stderr.flush()?;prepared.inputs.require_current(&project)?;control::checkpoint()?;return Ok((outcome,prepared.inputs));
 }
 let(prepared,inputs)=crate::request_runner::prepare_standalone_checker(build,host)?;
 if !matches!(prepared,BuildOutcome::QueryPrepared{retained:true,..}){return Err(io::Error::other("native Checker did not obtain its actual retained Original source").into())}
 inputs.require_current(&project)?;
 let transcript={let state=host.query_state();let state=state.try_lock().map_err(|_|io::Error::new(io::ErrorKind::WouldBlock,"native Checker current source is borrowed"))?;
  let snapshot=state.snapshot.as_ref().ok_or_else(||io::Error::other("native Checker actual source absent"))?;
  snapshot.stage_original_checker_cli(&project,explicit_configuration,&cache_root,&inputs)?
 };
 inputs.require_current(&project)?;
 let outcome=Outcome{json,parser:None,emitted:transcript.emitted,visited_bodies:transcript.visited_bodies,exit_code:if transcript.emitted==0{0}else{1},semantic_revision:transcript.semantic,source_revision:transcript.source,policy_revision:transcript.policy,full_checker_parity:false};
 let counts=transcript.counts;transcript.publish(&mut stderr)?;
 // Emit the exact reference phase labels ONLY after every actual producer and
 // completion token succeeded. Separate stdout/stderr streams retain their own
 // reference order; this makes no claim about wall-clock interleaving.
 for phase in ["Analyzing variables...","Gathering proc settings...","Analyzing proc bodies...","Analyzing proc override validity...","Analyzing proc call tree..."]{writeln!(stdout,"============================================================\n{phase}\n")?;}
 inputs.require_current(&project)?;writeln!(stdout,"============================================================\nFound {} diagnostics",outcome.emitted)?;if json{counts.write_json(&mut stdout)?;}stdout.flush()?;stderr.flush()?;
 inputs.require_current(&project)?;control::checkpoint()?;Ok((outcome,inputs))
}
pub(crate) fn require_prepared_shape_with_caller(build:&BuildRequest,display:&std::path::Path,caller:Option<&std::path::Path>,explicit:Option<&std::path::Path>)->io::Result<()>{
 let Some(caller)=caller else{return require_prepared_shape(build,display,explicit)};
 if display.is_absolute()||display.as_os_str().len()>65536||!caller.is_absolute()||caller.as_os_str().len()>65536{return Err(io::Error::new(io::ErrorKind::InvalidInput,"Checker display requires bounded caller-resolved DATA"))}
 require_prepared_shape(build,&build.project,explicit)
}
pub(crate) fn require_prepared_shape(build:&BuildRequest,display:&std::path::Path,explicit:Option<&std::path::Path>)->io::Result<()>{
 use crate::policy_request::{AnalysisContext,PolicyInputRole};
 let invalid=||io::Error::new(io::ErrorKind::InvalidInput,"resident Checker needs the exact nonpublishing Original checker request");
 if build.command!=BuildCommand::PrepareQuery||!build.project.is_absolute()||!display.is_absolute()||!build.exact_inputs||!build.no_cache||build.no_daemon||build.workers==0||build.workers>2||build.timeout_seconds.is_none()||!build.defines.is_empty()||build.engine_template.is_some()||build.bootstrap_catalog||build.output_store.is_some()||build.artifact_directory.is_some()||build.source_questions.is_some()||build.diagnostic_declarations||build.record_inputs.is_some()||build.replay_inputs.is_some()||build.trace_path.is_some()||build.warnings!=crate::diagnostics::WarningPolicy::default()||build.cache_root.as_ref().is_none_or(|p|!p.is_absolute()){return Err(invalid())}
 let intent=build.policy_inputs.as_ref().ok_or_else(invalid)?;
 if intent.analysis_context!=Some(AnalysisContext::OriginalChecker0290)||intent.workspace.is_some()||!intent.workspace_auxiliary.is_empty()||!intent.workspace_generators.is_empty()||!intent.search_folders.is_empty(){return Err(invalid())}
 let[source,configuration]=intent.files.as_slice()else{return Err(invalid())};
 if source.path!=build.project||source.role!=PolicyInputRole::DmSource||!source.required||configuration.role!=PolicyInputRole::Configuration||configuration.required||!configuration.path.is_absolute(){return Err(invalid())}
 if let Some(explicit)=explicit{if explicit!=configuration.path.as_path(){return Err(invalid())}}else if configuration.path.parent()!=build.project.parent()||configuration.path.file_name()!=Some(std::ffi::OsStr::new("SpacemanDMM.toml")){return Err(invalid())}
 crate::request::validate_timeout_seconds(build.timeout_seconds)
}

struct CheckedOutput<'a,W:Write>(&'a mut W);
impl<W:Write>Write for CheckedOutput<'_,W>{
 fn write(&mut self,b:&[u8])->io::Result<usize>{crate::daemon::control::checkpoint()?;let count=self.0.write(b)?;crate::daemon::control::checkpoint()?;Ok(count)}
 fn flush(&mut self)->io::Result<()>{crate::daemon::control::checkpoint()?;self.0.flush()?;crate::daemon::control::checkpoint()}
}
#[cfg(test)]mod argument_controls{
 use super::*;
 #[test]fn native_checker_initial_flags_refuse_unissued_modes_and_paths(){
  let cache=PathBuf::from(if cfg!(windows){"E:/dq-cache/native-checker"}else{"/tmp/native-checker"});
  for args in [vec!["--json".into()],vec!["--parse-only".into()],vec!["-e".into(),"relative.dme".into()],vec![]]{assert!(Request::from_arguments(&args,cache.clone()).is_err());}
 }
}

#[cfg(test)]mod caller_display_binding_controls{
 use super::*;
 fn actual(label:&str)->(Request,PathBuf){let root=std::fs::canonicalize(crate::test_scratch::dir(label)).unwrap();let cache=std::fs::canonicalize(crate::test_scratch::dir(&format!("{label}-cache"))).unwrap();std::fs::write(root.join("project.dme"),"/proc/probe()\n    return 1\n").unwrap();std::fs::write(root.join("SpacemanDMM.toml"),"").unwrap();(Request{project:root.join("project.dme"),configuration:None,cache_root:cache,workers:1,timeout_seconds:60},root)}
 #[test]fn actual_checker_relative_display_denies_foreign_caller_without_issuing_output(){
  let(request,root)=actual("checker-relative-foreign");let foreign=std::fs::canonicalize(crate::test_scratch::dir("checker-relative-foreign-owner")).unwrap();let mut host=BuildHost::default();let(mut out,mut err)=(Vec::new(),Vec::new());let _bound=crate::daemon::control::bind_with_deadline(crate::daemon::control::Cancellation::default(),std::time::Instant::now()+std::time::Duration::from_secs(60));
  let failure=run_prepared_with_caller(request.build().unwrap(),std::path::Path::new("project.dme"),Some(&foreign),None,false,&mut host,&mut out,&mut err).err().unwrap();assert_eq!(failure.downcast_ref::<io::Error>().unwrap().kind(),io::ErrorKind::Unsupported);assert!(out.is_empty()&&err.is_empty());
  let(outcome,inputs)=run_prepared_with_caller(request.build().unwrap(),std::path::Path::new("./project.dme"),Some(&root),None,false,&mut host,&mut out,&mut err).unwrap();assert_eq!(outcome.exit_code,0);assert!(!outcome.full_checker_parity);inputs.require_current(&request.project).unwrap();assert!(String::from_utf8(out).unwrap().contains("Parsing ./project.dme..."));
 }
 #[test]fn actual_checker_relative_display_keeps_first_output_1450_and_same_host_recovers(){
  struct Stop;impl Write for Stop{fn write(&mut self,_:&[u8])->io::Result<usize>{Err(io::Error::from_raw_os_error(1450))}fn flush(&mut self)->io::Result<()>{Ok(())}}
  let(request,root)=actual("checker-relative-first-io");let mut host=BuildHost::default();let _bound=crate::daemon::control::bind_with_deadline(crate::daemon::control::Cancellation::default(),std::time::Instant::now()+std::time::Duration::from_secs(60));let mut err=Vec::new();
  let failure=run_prepared_with_caller(request.build().unwrap(),std::path::Path::new("project.dme"),Some(&root),None,false,&mut host,&mut Stop,&mut err).err().unwrap();assert_eq!(failure.downcast_ref::<io::Error>().unwrap().raw_os_error(),Some(1450));assert!(err.is_empty());
  let mut out=Vec::new();let(outcome,_)=run_prepared_with_caller(request.build().unwrap(),std::path::Path::new("project.dme"),Some(&root),None,false,&mut host,&mut out,&mut err).unwrap();assert_eq!(outcome.exit_code,0);assert!(err.is_empty());
 }
}

/// Explicit nondefault report-only syntax observation over the SAME producer.
/// Includes actual formal-fatal prefixes; it never publishes a Checker frame.
/// The callback borrows the actual retained source and runs under the original
/// request context. Its first error is preserved before any final freshness IO.
pub fn observe_parse_only_syntax<T>(request:Request,host:&mut BuildHost,consume:impl FnOnce(&dm_tree::frontend::DiagnosticFrontend)->io::Result<T>)->Result<T,Box<dyn Error>>{
 use crate::daemon::{control,prepare_deadline};
 if !host.retains_artifacts(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"parse-only needs the existing retained host").into())}request.validate()?;
 let deadline=prepare_deadline::capture(BuildCommand::PrepareQuery,Some(request.timeout_seconds),std::time::Instant::now())?.ok_or_else(||io::Error::other("parse-only deadline absent"))?;
 let _binding=if control::WorkerContext::capture_for_checkpoints().is_none(){if control::current_deadline().is_some(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"parse-only cannot start under publication masking").into())}Some(control::bind_with_deadline(control::Cancellation::default(),deadline))}else{if control::current_deadline().is_none_or(|old|old>deadline){return Err(io::Error::new(io::ErrorKind::InvalidInput,"parse-only cannot extend inherited request deadline").into())}None};
 control::checkpoint()?;
 let width=request.project.as_os_str().len().checked_add(request.cache_root.as_os_str().len()).and_then(|n|n.checked_add(request.configuration.as_ref().map_or(0,|p|p.as_os_str().len()))).and_then(|n|n.checked_mul(16)).and_then(|n|n.checked_add(65536)).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;
 let _request_credit=host.source_arena_work().reserve(width)?;let build=request.build()?;let project=build.project.clone();
 let prepared=crate::request_runner::prepare_parse_only_syntax(build,host)?;
 prepared.inputs.require_parse_only_binding(&project,&prepared.frontend)?;prepared.inputs.require_current(&project)?;control::checkpoint()?;
 let value=consume(&prepared.frontend)?;
 prepared.inputs.require_parse_only_binding(&project,&prepared.frontend)?;prepared.inputs.require_current(&project)?;control::checkpoint()?;Ok(value)
}

// Give an otherwise unlabelled pure invariant failure its actual phase name.
// A real OS error or existing producer diagnostic remains byte-for-byte first.
fn parse_only_invariant_context(stage:&'static str,first:Box<dyn std::error::Error>)->Box<dyn std::error::Error>{
 if std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_none(){return first}
 match first.downcast::<std::io::Error>(){
  Ok(first)if first.kind()==std::io::ErrorKind::InvalidInput&&first.raw_os_error().is_none()&&first.get_ref().is_none()=>Box::new(std::io::Error::new(first.kind(),stage)),
  Ok(first)=>first,Err(first)=>first,
 }
}

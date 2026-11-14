//! Narrow genuine public BuildHost integration. No daemon, GUI, copied TLS,
//! private test-hook access, alternate parser, fake receipt or parity claim.
#[path="../../../shared/test_scratch.rs"] mod scratch;
#[path="../../../../analyze/fixtures/report_configuration.rs"] mod report_configuration;
use dmbc::{with_compiled_full_registry_input_observation, JoinedInputObservation,
    input_snapshot::InputSnapshot, policy_request::{AnalysisContext,PolicyInputRequest,WorkspacePolicyRequest},
    publish::OutputPair, request::{BuildRequest,BuildOutcome,Command}, runner_host::BuildHost};
use dq_analyze::selected_exclusions_wire::{Frame,Hex128,Seal};
use serde::Deserialize;
use std::{fs,io,path::{Path,PathBuf},sync::{Arc,Mutex,atomic::{AtomicUsize,Ordering}},time::{Duration,SystemTime}};
#[global_allocator] static ALLOC:mimalloc::MiMalloc=mimalloc::MiMalloc;
const SOURCE:&str="/proc/completion_zero()\n    return 0\n/proc/completion_empty()\n    return 0\n";
const ROOTS:[&str;6]=["code","doc/rewrite","interface","maps","modular_chomp","tgui"];
const PHASES:[&str;7]=["reader_declarations","variable_declarations","settings_prelude","body","keyword_overrides","sleep_graph","purity_graph"];
fn invalid(message:impl Into<String>)->io::Error{io::Error::new(io::ErrorKind::InvalidData,message.into())}
fn put(root:&Path,path:&str,bytes:impl AsRef<[u8]>)->io::Result<()>{let path=root.join(path);fs::create_dir_all(path.parent().unwrap())?;fs::write(path,bytes)}
struct Fixture{root:PathBuf,prepare:BuildRequest,compile:BuildRequest}
fn fixture(label:&str,source:&str,timeout:u16)->Fixture{
 // Capture the actual canonical project namespace before preparation/observation.
 // On Windows the real producer uses the verbatim prefix; no post-bracket lookup.
 let root=fs::canonicalize(scratch::dir(label)).unwrap();let cache=scratch::dir(&format!("{label}-cache"));
 for path in ROOTS{fs::create_dir_all(root.join(path)).unwrap();}
 // FullRegistry authenticates the broad tgui root AND its actual UI subdomain.
 // Empty parent tgui alone never records an interfaces-directory observation.
 fs::create_dir_all(root.join(dq_analyze::ui_actions_policy::INTERFACES)).unwrap();
 put(&root,"deepquarry.dme","#include \"code/probe.dm\"\n").unwrap();put(&root,"code/probe.dm",source).unwrap();
 put(&root,"tools/ci/lint_scopes.toml",report_configuration::with_overlay("")).unwrap();
 fn request(command:&str,root:&Path,cache:&Path,timeout:u16)->BuildRequest{
  let Command::Build(request)=dmbc::cli::parse(&[command.into(),root.join("deepquarry.dme").to_string_lossy().into_owned()]).unwrap()else{panic!("real public request parser")};
  let mut request=*request;request.no_cache=true;request.exact_inputs=true;request.progress_enabled=false;
  request.workers=1;request.timeout_seconds=Some(timeout);request.engine_template=None;request.bootstrap_catalog=false;request.cache_root=Some(cache.to_owned());request
 }
 let mut prepare=request("prepare-query",&root,&cache,timeout);
 prepare.policy_inputs=Some(PolicyInputRequest{analysis_context:Some(AnalysisContext::OriginalAnalyze0290),workspace:Some(WorkspacePolicyRequest{root:root.clone(),recursive_roots:ROOTS.map(|p|root.join(p)).to_vec(),configuration:root.join("tools/ci/lint_scopes.toml")}),..Default::default()});
 let mut compile=request("compile",&root,&cache,timeout);compile.artifact_directory=Some(cache.join("installed"));
 Fixture{root,prepare,compile}
}
// Exact typed decoding: InputSnapshot and OutputPair carry real numeric u128
// values and must never pass through lossy serde_json::Value roundtripping.
#[derive(Deserialize)]struct Binding{frame:Frame,checker_policy_revision:Hex128,roster:String,analysis_context:Option<AnalysisContext>,checker:Seal,report:Seal}
#[derive(Deserialize)]struct Header{schema:String,kind:String,full_checker_parity:bool,native_pair:OutputPair,project:PathBuf,defines:std::collections::BTreeMap<String,String>,native_engine_identity:Hex128,native_bootstrap_catalog:bool,original_initial_environment:String,native_inputs:Seal,report_inputs:Seal,binding:Binding}
struct Export{header:Vec<u8>,native:Vec<u8>,report:Vec<u8>,pair:OutputPair}
#[derive(Clone,Copy)]enum After{None,Io1450,ConsumerInterrupted,SourceSameStamp,Configuration,Deadline}
struct Restore{path:PathBuf,bytes:Vec<u8>,modified:SystemTime,done:bool}
impl Restore{
 fn capture(path:PathBuf)->io::Result<Self>{let modified=fs::metadata(&path)?.modified()?;let bytes=fs::read(&path)?;Ok(Self{path,bytes,modified,done:false})}
 fn restore(&mut self)->io::Result<()>{fs::write(&self.path,&self.bytes)?;fs::OpenOptions::new().write(true).open(&self.path)?.set_modified(self.modified)?;self.done=true;Ok(())}
}
impl Drop for Restore{fn drop(&mut self){if !self.done{if let Err(error)=self.restore(){eprintln!("fixture restoration failed for {}: {error}",self.path.display());}}}}
type Restoration=Arc<Mutex<Option<Restore>>>;
fn restore_now(slot:&Restoration)->io::Result<()>{if let Some(restore)=slot.lock().map_err(|_|invalid("restore lock poisoned"))?.as_mut(){restore.restore()?;}Ok(())}
fn edit(slot:&Restoration,path:PathBuf,same_stamp:bool)->io::Result<()>{
 let mut slot=slot.lock().map_err(|_|invalid("restore lock poisoned"))?;
 if slot.is_some(){return Err(invalid("fixture may be edited once"))}
 *slot=Some(Restore::capture(path)?); // install RAII BEFORE any write can fail
 let saved=slot.as_ref().unwrap();let mut next=saved.bytes.clone();
 if same_stamp{let at=next.windows(b"return 0".len()).position(|b|b==b"return 0").ok_or_else(||invalid("actual fixture source marker absent"))?;next[at+b"return ".len()]=b'1';}
 else{next.extend_from_slice(b"\n# actual post-callback report configuration edit\n");}
 fs::write(&saved.path,&next)?;
 if same_stamp{
  fs::OpenOptions::new().write(true).open(&saved.path)?.set_modified(saved.modified)?;
  let after=fs::metadata(&saved.path)?;
  if after.len()!=saved.bytes.len()as u64||after.modified()?!=saved.modified{return Err(invalid("fixture failed to restore exact original size/mtime"))}
 }
 Ok(())
}
fn run(host:&mut BuildHost,fixture:&Fixture,compact:bool,after:After,called:Arc<AtomicUsize>,export:Arc<Mutex<Option<Export>>>,restoration:Restoration,checker:&mut Vec<u8>,analyze:&mut Vec<u8>)->Result<(BuildOutcome,bool),Box<dyn std::error::Error>>{
 let root=fixture.root.clone();
 with_compiled_full_registry_input_observation(host,fixture.prepare.clone(),fixture.compile.clone(),false,false,compact,
  move |observation:JoinedInputObservation<'_>|{
   called.fetch_add(1,Ordering::AcqRel);let pair=observation.pair.clone();let deadline=observation.deadline;
   let mut header=Vec::new();let mut native=Vec::new();let mut report=Vec::new();observation.write_inputs(&mut header,&mut native,&mut report)?;
   *export.lock().map_err(|_|invalid("export lock poisoned"))?=Some(Export{header,native,report,pair});
   match after{
    After::None=>Ok(()),After::Io1450=>Err(io::Error::from_raw_os_error(1450)),
    After::ConsumerInterrupted=>Err(io::Error::new(io::ErrorKind::Interrupted,"actual caller stopped qualification")),
    After::SourceSameStamp=>edit(&restoration,root.join("code/probe.dm"),true),
    After::Configuration=>edit(&restoration,root.join("tools/ci/lint_scopes.toml"),false),
    After::Deadline=>{eprintln!("observed deadline control: waiting {:?} for the SAME inherited deadline",deadline.saturating_duration_since(std::time::Instant::now()));while let Some(wait)=deadline.checked_duration_since(std::time::Instant::now()){std::thread::sleep(wait.min(Duration::from_secs(1)));}Ok(())},
   }
  },&mut Vec::new(),checker,analyze)
}
fn inputs()->(Arc<AtomicUsize>,Arc<Mutex<Option<Export>>>,Restoration){(Arc::new(AtomicUsize::new(0)),Arc::new(Mutex::new(None)),Arc::new(Mutex::new(None)))}
fn require_seal(seal:Seal,bytes:&[u8]){assert_eq!(seal.length,bytes.len()as u64);assert_eq!(seal.hash.0,xxhash_rust::xxh3::xxh3_128(bytes));}
fn require_completed(outcome:BuildOutcome,export:Export,checker:&[u8],analyze:&[u8],root:&Path){
 let BuildOutcome::Published{pair,..}=outcome else{panic!("real native compilation did not publish its pair")};
 let header:Header=serde_json::from_slice(&export.header).unwrap();assert_eq!(header.schema,"joined-publication-input-observation-v1");assert_eq!(header.kind,"observed_inputs_only");assert!(!header.full_checker_parity);assert_eq!(header.native_pair,pair);assert_eq!(export.pair,pair);
 assert_eq!(dm_preprocess::regions::canonical_path(&header.project),dm_preprocess::regions::canonical_path(&root.join("deepquarry.dme")));
 let mut expected_defines=std::collections::BTreeMap::new();dmbc::pinned_target::admit_defines(&mut expected_defines).unwrap();assert_eq!(header.defines,expected_defines);
 // request_runner normalizes embedded executable engine_template=None to bootstrap_catalog=true.
 // This is the actual native publication configuration, separate from the Original report environment.
 assert!(header.native_bootstrap_catalog);assert_eq!(header.native_engine_identity.0,xxhash_rust::xxh3::xxh3_128(include_bytes!("../../../fixtures/native_template.bin")));
 assert_eq!(header.original_initial_environment,"OriginalChecker0290");assert_eq!(header.binding.analysis_context,Some(AnalysisContext::OriginalAnalyze0290));assert_eq!(header.binding.roster,"full_registry");
 require_seal(header.native_inputs,&export.native);require_seal(header.report_inputs,&export.report);require_seal(header.binding.checker,checker);require_seal(header.binding.report,analyze);
 let native:InputSnapshot=serde_json::from_slice(&export.native).unwrap();let report:InputSnapshot=serde_json::from_slice(&export.report).unwrap();
 assert!(native.files().any(|file|file.path.ends_with("code/probe.dm")));assert!(report.files().any(|file|dm_preprocess::regions::canonical_path(&file.path)==dm_preprocess::regions::canonical_path(&root.join("tools/ci/lint_scopes.toml"))));
 let body:serde_json::Value=serde_json::from_slice(checker).unwrap();assert_eq!(body["row"],"source_native_original_ordered_checker");assert_eq!(body["full_checker_parity"],false);
 assert_eq!(body["semantic_revision"],format!("{:032x}",header.binding.frame.semantic_revision.0));assert_eq!(body["source_revision"],format!("{:032x}",header.binding.frame.source_revision.0));assert_eq!(body["policy_revision"],format!("{:032x}",header.binding.checker_policy_revision.0));
 assert_eq!(body["scope_completion"]["scope"],"whole_input_current_ordered_producers");assert_eq!(body["scope_completion"]["visited_bodies"],2);
 assert_eq!(body["scope_completion"]["completed_phase_order"],serde_json::json!(PHASES));assert_eq!(body["diagnostics"].as_array().unwrap().len(),0,"both actual zero-finding bodies must count, not vanish");assert!(!analyze.is_empty());
}
#[test]fn actual_public_joined_observation_and_whole_scope_zero_finding_normal_and_compact(){
 for compact in[false,true]{let f=fixture(if compact{"whole-observed-compact"}else{"whole-observed-normal"},SOURCE,60);let mut host=BuildHost::default();let(called,export,restore)=inputs();let(mut checker,mut analyze)=(Vec::new(),Vec::new());
  assert!(!f.root.join(".dmbc").exists(),"fresh fixture must exercise real first-use namespace initialization");
  let(outcome,_clean)=run(&mut host,&f,compact,After::None,called.clone(),export.clone(),restore,&mut checker,&mut analyze).unwrap();assert_eq!(called.load(Ordering::Acquire),1);
  assert!(f.root.join(".dmbc").is_dir());
  require_completed(outcome,export.lock().unwrap().take().unwrap(),&checker,&analyze,&f.root);
 }
}
#[test]fn actual_public_observation_consumer_io_and_interrupted_never_deliver_reports(){
 for after in[After::Io1450,After::ConsumerInterrupted]{let f=fixture("whole-observed-consumer-stop",SOURCE,60);let mut host=BuildHost::default();let(called,export,restore)=inputs();let(mut checker,mut analyze)=(Vec::new(),Vec::new());
  let error=run(&mut host,&f,true,after,called.clone(),export.clone(),restore,&mut checker,&mut analyze).unwrap_err();let actual=error.downcast_ref::<io::Error>().expect("same typed consumer IO survives actual publication");
  match after{After::Io1450=>assert_eq!(actual.raw_os_error(),Some(1450)),After::ConsumerInterrupted=>assert_eq!(actual.kind(),io::ErrorKind::Interrupted),_=>unreachable!()}
  assert_eq!(called.load(Ordering::Acquire),1);assert!(export.lock().unwrap().is_some());assert!(checker.is_empty()&&analyze.is_empty(),"installed pair may remain, qualification reports may not be delivered");
 }
}
#[test]fn actual_public_observation_rechecks_same_stamp_source_and_report_configuration_then_recovers(){
 for after in[After::SourceSameStamp,After::Configuration]{let f=fixture("whole-observed-freshness",SOURCE,60);let mut host=BuildHost::default();let(called,export,restoration)=inputs();let(mut checker,mut analyze)=(Vec::new(),Vec::new());
  let error=run(&mut host,&f,true,after,called.clone(),export.clone(),restoration.clone(),&mut checker,&mut analyze).unwrap_err();
  assert_eq!(called.load(Ordering::Acquire),1);let actual=error.downcast_ref::<io::Error>().expect("real final freshness error remains typed");assert_eq!(actual.kind(),io::ErrorKind::Interrupted);assert!(actual.to_string().contains("prepare both phases"),"{actual}");assert!(checker.is_empty()&&analyze.is_empty());
  restore_now(&restoration).unwrap();assert_eq!(fs::read(f.root.join("code/probe.dm")).unwrap(),SOURCE.as_bytes());
  let(called,export,restore)=inputs();let(outcome,_)=run(&mut host,&f,true,After::None,called.clone(),export.clone(),restore,&mut checker,&mut analyze).unwrap();assert_eq!(called.load(Ordering::Acquire),1);require_completed(outcome,export.lock().unwrap().take().unwrap(),&checker,&analyze,&f.root);
 }
}
#[test]fn actual_public_observed_source_arena_quota_releases_real_credit_and_recovers(){
 let f=fixture("whole-observed-quota",SOURCE,60);let mut host=BuildHost::default();let(called,export,restore)=inputs();let(mut checker,mut analyze)=(Vec::new(),Vec::new());
 let limit=host.source_arena_work().transformed_source_address_limit().expect("actual native host publishes its existing arena extent");assert!(limit>2*1024*1024);
 let pressure=host.source_arena_work().reserve(limit-512*1024).expect("genuine fresh-host resource-only credit, no physical giant buffer or source role");
 let error=run(&mut host,&f,true,After::None,called.clone(),export.clone(),restore,&mut checker,&mut analyze).unwrap_err();assert_eq!(error.downcast_ref::<io::Error>().unwrap().kind(),io::ErrorKind::OutOfMemory);assert_eq!(called.load(Ordering::Acquire),0);assert!(checker.is_empty()&&analyze.is_empty());drop(pressure);
 let(called,export,restore)=inputs();let(outcome,_)=run(&mut host,&f,true,After::None,called.clone(),export.clone(),restore,&mut checker,&mut analyze).unwrap();assert_eq!(called.load(Ordering::Acquire),1);require_completed(outcome,export.lock().unwrap().take().unwrap(),&checker,&analyze,&f.root);
}
#[test]fn actual_public_observed_unissued_body_cannot_deliver_scope_or_callback(){
 let f=fixture("whole-observed-unissued","/proc/probe()\n    goto finish\n    finish:\n        return 0\n",60);let mut host=BuildHost::default();let(called,export,restore)=inputs();let(mut checker,mut analyze)=(Vec::new(),Vec::new());
 let error=run(&mut host,&f,true,After::None,called.clone(),export,restore,&mut checker,&mut analyze).unwrap_err();assert!(error.to_string().contains("genuine original per-body grammar outcome is not issued"),"{error}");assert_eq!(called.load(Ordering::Acquire),0);assert!(checker.is_empty()&&analyze.is_empty());
}
#[test]fn actual_public_observation_keeps_original_deadline_even_after_pair_install(){
 let f=fixture("whole-observed-deadline",SOURCE,30);let mut host=BuildHost::default();let(called,export,restore)=inputs();let(mut checker,mut analyze)=(Vec::new(),Vec::new());
 let error=run(&mut host,&f,true,After::Deadline,called.clone(),export,restore,&mut checker,&mut analyze).unwrap_err();assert_eq!(called.load(Ordering::Acquire),1,"control must reach the genuine post-install callback; an earlier timeout is not branch coverage");let actual=error.downcast_ref::<io::Error>().unwrap();assert_eq!(actual.kind(),io::ErrorKind::Interrupted);assert!(actual.to_string().contains("deadline expired"),"{actual}");assert!(checker.is_empty()&&analyze.is_empty());
}

#[test]fn actual_public_observation_requires_the_actual_ui_interface_directory(){
 let f=fixture("whole-observed-missing-ui-domain",SOURCE,60);
 let directory=f.root.join(dq_analyze::ui_actions_policy::INTERFACES);
 fs::remove_dir(&directory).unwrap(); // This fixture owns the empty leaf directory.
 let mut host=BuildHost::default();let(called,export,restore)=inputs();let(mut checker,mut analyze)=(Vec::new(),Vec::new());
 let error=run(&mut host,&f,true,After::None,called.clone(),export,restore,&mut checker,&mut analyze).unwrap_err();
 let actual=error.downcast_ref::<io::Error>().expect("actual discovery guard must remain typed");
 assert_eq!(actual.kind(),io::ErrorKind::InvalidInput);
 assert_eq!(actual.to_string(),"authored UI joined domains were not completely observed");
 assert_eq!(called.load(Ordering::Acquire),0);assert!(checker.is_empty()&&analyze.is_empty());
}

#[test]fn actual_public_observation_refuses_a_non_directory_compiler_namespace_before_capture(){
 let f=fixture("whole-observed-bad-build-namespace",SOURCE,60);
 let path=f.root.join(".dmbc");let bytes=b"existing authored obstruction";fs::write(&path,bytes).unwrap();
 let mut host=BuildHost::default();let(called,export,restore)=inputs();let(mut checker,mut analyze)=(Vec::new(),Vec::new());
 let error=run(&mut host,&f,true,After::None,called.clone(),export,restore,&mut checker,&mut analyze).unwrap_err();
 let actual=error.downcast_ref::<io::Error>().expect("same actual namespace initialization IO must survive");assert!(actual.raw_os_error().is_some(),"{actual}");
 assert_eq!(fs::read(&path).unwrap(),bytes);assert_eq!(called.load(Ordering::Acquire),0);assert!(checker.is_empty()&&analyze.is_empty());
}

//! A closed sem-fixture operation on the ordinary registered producer.
//! Owns output/expected DATA only; authentic source authority stays in the
//! selected raw/model/handler snapshot and its SAME moved recorder.
use std::{io::{self,Write},path::{Path,PathBuf},sync::Mutex};
use dm_preprocess::source_arena_credit::{SourceArenaCredit,SourceArenaWork};
use crate::{input_snapshot::{SnapshotProvider,RecordingInputs,utility_capture::{UtilityBytes,UtilityPhysicalInputs}},selected_report_spool::{Stage,Verified}};
fn invalid(s:&'static str)->io::Error{io::Error::new(io::ErrorKind::InvalidInput,s)}
fn poisoned()->io::Error{invalid("fixture operation state is poisoned")}
pub(crate) struct CapturedFixtureTarget{root:PathBuf,original:Option<UtilityBytes>,_credit:SourceArenaCredit}
impl CapturedFixtureTarget{
 pub(crate) fn root(&self)->&Path{&self.root}
 pub(crate) fn original(&self)->Option<&UtilityBytes>{self.original.as_ref()}
 pub(crate) fn relative(&self)->&str{"expected.txt"}
}
#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub(crate) enum FixtureConfigMode{Repository,FixtureIfPresent}
struct State{captured:bool,observed:bool,target:Option<CapturedFixtureTarget>,expected:Option<Stage>}
pub(crate) struct FixtureScope{lint:String,root:PathBuf,configuration:PathBuf,cache:PathBuf,bless:bool,mode:FixtureConfigMode,own_configuration:PathBuf,own_present:bool,preview:bool,state:Mutex<State>,_credit:SourceArenaCredit}
impl FixtureScope{
 /// Caller must first resolve the single canonical registry name. A slash in
 /// that name is DATA, transformed by the exact original fixture directory rule.
 pub(crate) fn issue(real_root:&Path,lint:&str,bless:bool,cache:&Path,work:&dyn SourceArenaWork)->io::Result<Self>{
  Self::issue_mode(real_root,lint,bless,FixtureConfigMode::Repository,cache,work)
 }
 pub(crate) fn issue_mode(real_root:&Path,lint:&str,bless:bool,mode:FixtureConfigMode,cache:&Path,work:&dyn SourceArenaWork)->io::Result<Self>{
  if !real_root.is_absolute()||!cache.is_absolute()||lint.is_empty()||lint.bytes().any(|b|b==0||b<32)||lint.contains(['\\',':'])||lint.split('/').any(|p|p.is_empty()||p=="."||p==".."){return Err(invalid("invalid fixture registry name/root"))}
  let width=real_root.as_os_str().len().checked_mul(4).and_then(|n|n.checked_add(cache.as_os_str().len())).and_then(|n|n.checked_add(lint.len().checked_mul(2)?)).ok_or(io::ErrorKind::OutOfMemory)?;
  let credit=work.reserve(width.checked_mul(16).and_then(|n|n.checked_add(std::mem::size_of::<Self>()+4096)).ok_or(io::ErrorKind::OutOfMemory)?)?;
  let root=real_root.join("tools/analyze/fixtures").join(lint.replace('/',"__"));
  // Namespace verification, not source acquisition. Actual files/config are
  // read and recorded by the existing native preparation after this DATA step.
  if std::fs::canonicalize(&root)?!=root||!root.is_dir(){return Err(invalid("fixture directory must already exist with its actual canonical spelling"))}
  // Tentative namespace choice is DATA only. SAME source recorder below
  // independently captures its presence before any selected proof is sealed.
  let own_configuration=root.join("tools/ci/lint_scopes.toml");
  let own_present=if mode==FixtureConfigMode::FixtureIfPresent{own_configuration.try_exists()?}else{false};
  let configuration=if own_present{own_configuration.clone()}else{real_root.join("tools/ci/lint_scopes.toml")};let cache=cache.to_path_buf();let preview=bless||mode==FixtureConfigMode::FixtureIfPresent;
  let expected=if preview{Some(Stage::new(&cache)?)}else{None};
  Ok(Self{lint:lint.to_owned(),root,configuration,cache,bless,mode,own_configuration,own_present,preview,state:Mutex::new(State{captured:false,observed:false,target:None,expected}),_credit:credit})
 }
 pub(crate) fn lint(&self)->&str{&self.lint}
 pub(crate) fn root(&self)->&Path{&self.root}
 pub(crate) fn configuration(&self)->&Path{&self.configuration}
 pub(crate) fn require_configuration(&self,root:&Path,path:&Path)->bool{root==self.root&&path==self.configuration}
 pub(crate) fn visit_storage(&self,visit:&mut impl FnMut(usize,usize,usize)){visit(self as *const Self as usize,std::mem::size_of::<Self>(),std::mem::size_of::<Self>());visit(self.lint.as_ptr()as usize,self.lint.len(),self.lint.capacity());for p in [&self.root,&self.configuration,&self.cache,&self.own_configuration]{visit(p.as_os_str().as_encoded_bytes().as_ptr()as usize,p.as_os_str().len(),p.capacity())}self._credit.visit_storage(&mut|p,n|visit(p,n,n));}
 pub(crate) fn begin_attempt(&self)->io::Result<()>{let mut s=self.state.lock().map_err(|_|poisoned())?;s.captured=false;s.observed=false;s.target=None;if let Some(stage)=&mut s.expected{stage.restart_attempt()?;}else if self.preview{s.expected=Some(Stage::new(&self.cache)?);}Ok(())}
 /// Typed fixture-only physical hook. It does not arm ordinary utility/model
 /// capture and does not borrow or manufacture a semantic completeness receipt.
 pub(crate) fn capture_physical<P:SnapshotProvider>(&self,recording:&RecordingInputs<P>,queries:&crate::query_db::QueryDb)->io::Result<()>{
  if self.mode==FixtureConfigMode::FixtureIfPresent{
   let present=dm_preprocess::SourceProvider::path_presence_admitted(recording,&self.own_configuration,queries)?;
   if present!=self.own_present{return Err(io::Error::new(io::ErrorKind::Interrupted,"fixture own configuration appeared/disappeared during actual capture"))}
  }
  if !self.preview{return Ok(())}
  let mut state=self.state.lock().map_err(|_|poisoned())?;if state.captured{return Err(invalid("fixture target captured twice in one actual attempt"))}
  struct Capture<'a>{root:&'a Path,target:Option<CapturedFixtureTarget>}
  impl crate::request_runner::utility_capture::Capture for Capture<'_>{
   fn begin_attempt(&mut self){self.target=None;}
   fn workspace_roster(&mut self,_:&crate::runner_host::workspace_discovery::DiscoveryReceipt,_:&dyn SourceArenaWork)->io::Result<()>{Ok(())}
   fn prepare_current(&mut self,_:&dm_tree::frontend::DiagnosticSourceView<'_>,_:&crate::runner_host::query_snapshot::SourceSnapshot,_:&dyn SourceArenaWork)->Result<(),Box<dyn std::error::Error>>{Ok(())}
   fn capture(&mut self,physical:&mut dyn UtilityPhysicalInputs)->io::Result<()>{
    let mut held=None;physical.with_work(&mut|work|{held=Some(work.reserve(self.root.as_os_str().len().checked_mul(16).and_then(|n|n.checked_add(2048)).ok_or(io::ErrorKind::OutOfMemory)?)?);Ok(())})?;
    let original=physical.read(&self.root.join("expected.txt"),dq_analyze::selected_exclusions_wire::MAX_STREAM as usize)?;
    self.target=Some(CapturedFixtureTarget{root:self.root.to_path_buf(),original,_credit:held.ok_or_else(||invalid("fixture target metadata admission absent"))?});Ok(())
   }
  }
  let mut capture=Capture{root:&self.root,target:None};crate::request_runner::utility_capture::run(&mut capture,recording,queries)?;
  state.target=Some(capture.target.take().ok_or_else(||invalid("fixture target actual capture omitted"))?);state.captured=true;Ok(())
 }
 pub(crate) fn observe<C:dq_analyze::key_policy_control::Control<Error=dq_analyze::captured_reactive_reads::Failure>>(&self,sites:&[dq_analyze::lint::Site],control:&mut C,out:&mut impl Write,expected:impl FnOnce(&mut C,&mut Stage)->Result<(),dq_analyze::captured_reactive_reads::Failure>)->io::Result<()>{
  let mut state=self.state.lock().map_err(|_|poisoned())?;if state.observed{return Err(invalid("fixture producer observed more than once"))}
  dq_analyze::fixture_report_policy::write_sites(sites,control,out).map_err(actual)?;
  if self.preview{if !state.captured{return Err(invalid("fixture bless lacks SAME recorder target observation"))}expected(control,state.expected.as_mut().ok_or_else(||invalid("fixture expected output stage absent"))?).map_err(actual)?;}
  state.observed=true;Ok(())
 }
 /// Preview comes from the SAME already-observed selected producer; callers
 /// may compare it before invoking any physical writer. No second scan.
 pub(crate) fn finish_outputs(&self)->io::Result<(Option<CapturedFixtureTarget>,Option<Verified>)>{
  let mut s=self.state.lock().map_err(|_|poisoned())?;if !s.observed{return Err(invalid("fixture report did not observe its selected producer"))}
  if !self.preview{return Ok((None,None))}
  let target=Some(s.target.take().ok_or_else(||invalid("fixture target already consumed"))?);
  let stage=s.expected.take().ok_or_else(||invalid("fixture expected output already consumed"))?;let length=stage.length();
  let(verified,copied)=stage.seal_allow_empty()?.validate(|r|io::copy(r,&mut io::sink()))?;
  if copied!=length||verified.length()!=length{return Err(invalid("fixture expected output sealed extent differs"))}Ok((target,Some(verified)))
 }
 pub(crate) fn finish_expected(&self)->io::Result<Option<(CapturedFixtureTarget,Verified)>>{
  let(target,expected)=self.finish_outputs()?;match(target,expected){(Some(target),Some(expected))=>Ok(Some((target,expected))),(None,_)=>Ok(None),_=>Err(invalid("fixture expected output missing"))}
 }

}
fn actual(e:dq_analyze::captured_reactive_reads::Failure)->io::Error{match e{dq_analyze::captured_reactive_reads::Failure::Operational(e)=>e,dq_analyze::captured_reactive_reads::Failure::Unsupported(message)=>io::Error::new(io::ErrorKind::Unsupported,message)}}
impl FixtureScope{
 pub(crate) fn request_paths(&self,request:&crate::request::BuildRequest)->io::Result<(PathBuf,PathBuf)>{
  use crate::{request::BuildCommand,policy_request::AnalysisContext};
  let p=request.policy_inputs.as_ref().ok_or_else(||invalid("fixture lacks actual workspace intent"))?;let w=p.workspace.as_ref().ok_or_else(||invalid("fixture actual workspace absent"))?;
  if request.command!=BuildCommand::PrepareQuery||request.no_daemon||!request.defines.is_empty()||request.engine_template.is_some()||request.bootstrap_catalog||request.record_inputs.is_some()||request.replay_inputs.is_some()||request.artifact_directory.is_some()||request.output_store.is_some()||request.trace_path.is_some()||request.source_questions.is_some()||request.diagnostic_declarations||p.analysis_context!=Some(AnalysisContext::OriginalAnalyze0290)||!p.workspace_generators.is_empty()||!p.files.is_empty()||!p.search_folders.is_empty()||!self.require_configuration(&w.root,&w.configuration)||request.project!=self.root.join("deepquarry.dme")||request.cache_root.as_deref()!=Some(self.cache.as_path()){return Err(invalid("fixture request differs from its closed actual scope"))}
  if w.recursive_roots.iter().any(|p|!p.starts_with(&self.root)){return Err(invalid("fixture source roots escape actual fixture"))}
  if std::fs::canonicalize(&self.root)?!=self.root||std::fs::canonicalize(&self.cache)?!=self.cache||!self.cache.is_dir()||self.cache.starts_with(&self.root){return Err(invalid("fixture cache/root namespace changed"))}
  Ok((self.root.clone(),self.cache.clone()))
 }
}
#[cfg(test)]mod fixture_scope_controls{
 use super::*;
 #[test]fn actual_scope_is_bound_to_exact_registry_name_and_real_config_path(){
  let root=std::fs::canonicalize(crate::test_scratch::dir("fixture-scope-closed-config")).unwrap();let cache=std::fs::canonicalize(crate::test_scratch::dir("fixture-scope-closed-config-cache")).unwrap();std::fs::create_dir_all(root.join("tools/analyze/fixtures/decl")).unwrap();
  let host=crate::runner_host::BuildHost::default();let scope=FixtureScope::issue(&root,"decl",false,&cache,host.source_arena_work()).unwrap();let fixture=scope.root().to_path_buf();assert!(scope.require_configuration(&fixture,&root.join("tools/ci/lint_scopes.toml")));assert!(!scope.require_configuration(&fixture,&fixture.join("tools/ci/lint_scopes.toml")));
  let options=crate::runner_host::FullRegistryCheckOptions{raw:true,unused:false,..Default::default()};let mut scheduler=crate::runner_host::prepare_native_registered_check_selection(&["scheduler".into()],options,host.source_arena_work()).unwrap();assert!(std::sync::Arc::get_mut(&mut scheduler).unwrap().install_fixture(scope).is_err(),"a fixture directory cannot impersonate another selected lint");assert!(!scheduler.configuration_matches(&fixture,&root.join("tools/ci/lint_scopes.toml")),"ordinary CHECK keeps its root-only config restriction");
 }
}

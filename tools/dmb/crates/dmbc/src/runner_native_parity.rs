//! Read-only real-tree parity against the explicitly frozen legacy Analyze
//! executable. Both native questions use the existing selected query producer.
use std::{io::{self,Write},path::PathBuf};
use dm_preprocess::source_arena_credit::{SourceArenaCredit,SourceArenaWork};
use super::{BuildHost,FullRegistryCheckOptions,full_registry_check::FullRegistryCheckInputs};
use crate::request::BuildRequest;
use super::legacy_analyze_oracle::{Oracle,Binding};
type BoxError=Box<dyn std::error::Error>;
/// Borrow the exact shared utility envelope, without cloning/canonicalizing a
/// second unowned path set. Genuine producers revalidate their physical source.
fn utility_paths(request:&BuildRequest)->io::Result<(&std::path::Path,&std::path::Path)>{
 use crate::{request::BuildCommand,policy_request::{AnalysisContext,WorkspaceAuxiliaryQuestion as Q}};
 let p=request.policy_inputs.as_ref().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"parity utility policy absent"))?;let w=p.workspace.as_ref().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"parity utility workspace absent"))?;let cache=request.cache_root.as_deref().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"parity utility cache absent"))?;
 if request.command!=BuildCommand::PrepareQuery||!request.exact_inputs||!request.no_cache||request.no_daemon||request.timeout_seconds.is_none()||!request.defines.is_empty()||request.engine_template.is_some()||request.bootstrap_catalog||request.record_inputs.is_some()||request.replay_inputs.is_some()||request.artifact_directory.is_some()||request.output_store.is_some()||request.trace_path.is_some()||request.source_questions.is_some()||request.diagnostic_declarations||request.warnings!=crate::diagnostics::WarningPolicy::default()||p.analysis_context!=Some(AnalysisContext::OriginalAnalyze0290)||p.workspace_auxiliary!=[Q::SemReads]||!p.files.is_empty()||!p.search_folders.is_empty()||!p.workspace_generators.is_empty()||!w.root.is_absolute()||!cache.is_absolute()||cache.starts_with(&w.root)||request.project.strip_prefix(&w.root).ok()!=Some(std::path::Path::new("deepquarry.dme"))||w.configuration.strip_prefix(&w.root).ok()!=Some(std::path::Path::new("tools/ci/lint_scopes.toml"))||w.recursive_roots.len()!=2||w.recursive_roots.iter().zip(["code","maps"]).any(|(actual,relative)|actual.strip_prefix(&w.root).ok()!=Some(std::path::Path::new(relative))){return Err(io::Error::new(io::ErrorKind::InvalidInput,"parity requires its exact authenticated SemReads utility entry envelope"))}Ok((&w.root,cache))
}
fn neutral_request_copy(request:&BuildRequest,work:&dyn SourceArenaWork)->io::Result<(BuildRequest,SourceArenaCredit)>{
 utility_paths(request)?;let(mut copied,mut credit)=super::native_codemod::request_copy(request,work)?;
 let policy=copied.policy_inputs.as_mut().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"neutral registry copy lost policy"))?;policy.workspace_auxiliary.clear();let workspace=policy.workspace.as_mut().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"neutral registry copy lost workspace"))?;
 let old=std::mem::take(&mut workspace.recursive_roots);let retired=old.iter().try_fold(old.capacity().checked_mul(std::mem::size_of::<PathBuf>()).ok_or(io::ErrorKind::OutOfMemory)?,|n,path|n.checked_add(path.capacity()).ok_or(io::ErrorKind::OutOfMemory))?;drop(old);work.shrink(&mut credit,retired)?;
 let roots=crate::policy_request::WorkspaceAuxiliaryQuestion::authored_doc_ui_roots(crate::policy_request::WorkspaceAuxiliaryQuestion::PRIVATE_FULL_REGISTRY).ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"actual neutral registry roots absent"))?;
 workspace.recursive_roots=super::native_utility_binding::vector(roots.len(),work,&mut credit)?;for relative in roots{workspace.recursive_roots.push(dm_preprocess::regions::joined_path_into_credit(&workspace.root,relative,work,&mut credit)?);}Ok((copied,credit))
}

struct Proof{project:PathBuf,inputs:FullRegistryCheckInputs,pub(super)frame:dq_analyze::full_registry_check_wire::CheckFrame}
pub(crate)struct ChecksCompleted{pub(crate)clean:bool,default:Proof,raw:Proof,oracle:Oracle,_credit:SourceArenaCredit}
impl ChecksCompleted{pub(crate)fn require_current(&self,work:&dyn SourceArenaWork)->Result<(),BoxError>{self.oracle.require_current(work)?;self.default.inputs.require_report_current(&self.default.project)?;self.raw.inputs.require_report_current(&self.raw.project)?;Ok(())}}
/// This is a real complete default+raw comparison suboperation, not a whole
/// parity terminal: fixtures/baseline/selftest assembly stays with its caller.
pub(crate)fn run_real_checks(request:&BuildRequest,selectors:&[String],binding:&Binding,host:&mut BuildHost,mut report:&mut dyn Write,mut diagnostics:&mut dyn Write)->Result<ChecksCompleted,BoxError>{
 let(root,cache)=utility_paths(request)?;
 let credit=host.source_arena_work().reserve(std::mem::size_of::<ChecksCompleted>())?;
 let oracle=Oracle::open(binding,host.source_arena_work())?;
 // Registry order and actual resolved names are shared with normal CHECK.
 let plan=super::prepare_native_registered_check_selection(selectors,FullRegistryCheckOptions{unused:false,no_cache:true,..Default::default()},host.source_arena_work())?;
 let mut names_credit=host.source_arena_work().reserve(0)?;let mut canonical=super::native_utility_binding::vector(plan.names().len(),host.source_arena_work(),&mut names_credit)?;
 for name in plan.names(){canonical.push(dm_preprocess::regions::copy_string_into_credit(name,host.source_arena_work(),&mut names_credit)?);}drop(plan);
 let mut clean=true;let mut one=|raw:bool,host:&mut BuildHost|->Result<Proof,BoxError>{
  let options=FullRegistryCheckOptions{raw,unused:false,no_cache:true,..Default::default()};
  let(copy,copy_credit)=neutral_request_copy(request,host.source_arena_work())?;
  let actual=host.stage_selected_registry_check_report(copy,options,&canonical)?;drop(copy_credit);
  actual.inputs.require_report_current(&actual.project)?;
  let old=oracle.run_many(&root,&cache,&canonical,raw,host.source_arena_work(),&mut||actual.inputs.require_report_current(&actual.project))?;
  let old_code=old.code;let actual_code=if actual.clean{0}else{1};let old_bytes=old.stdout.length();let new_bytes=actual.report.length();
  let identical=actual.report.same_bytes(old.stdout,host.source_arena_work())?;let passed=identical&&old_code==actual_code;clean&=passed;
  actual.inputs.require_report_current(&actual.project)?;oracle.require_current(host.source_arena_work())?;
  writeln!(report,"  [{}] {} run: legacy exit {}, native {}; {} (legacy {} bytes, native {} bytes)",if passed{"ok"}else{"DIFF"},if raw{"raw"}else{"default"},old_code,actual_code,if identical{"byte-identical report"}else{"reports differ"},old_bytes,new_bytes)?;
  if old.stderr.length()>0{writeln!(diagnostics,"legacy Analyze diagnostic stream:")?;old.stderr.publish(&mut diagnostics)?;}
  if let Some(native)=actual.diagnostics{native.publish(&mut diagnostics)?;}drop(actual._credit);
  Ok(Proof{project:actual.project,inputs:actual.inputs,frame:actual.frame})
 };
 let default=one(false,host)?;let raw=one(true,host)?;drop(one);drop(canonical);drop(names_credit);
 let completed=ChecksCompleted{clean,default,raw,oracle,_credit:credit};completed.require_current(host.source_arena_work())?;Ok(completed)
}

pub(crate)struct SelftestsCompleted{pub(crate)clean:bool,actual:super::StandaloneSelftestReport,oracle:Oracle,_credit:SourceArenaCredit}
impl SelftestsCompleted{
 pub(crate)fn require_current(&self,work:&dyn SourceArenaWork)->Result<(),BoxError>{self.oracle.require_current(work)?;self.actual.require_current()?;Ok(())}
 pub(crate)fn selection(&self)->dq_analyze::full_registry_check_selection_wire::SelectionBinding{self.actual.plan.binding()}
}
/// Execute the real native registered callback catalog, not a CHECK report with
/// discarded policies. The independent reference runs only explicit selftests.
pub(crate)fn run_selftests(request:&BuildRequest,selectors:&[String],binding:&Binding,host:&mut BuildHost,mut report:&mut dyn Write,mut diagnostics:&mut dyn Write)->Result<SelftestsCompleted,BoxError>{
 let(root,cache)=utility_paths(request)?;
 let credit=host.source_arena_work().reserve(std::mem::size_of::<SelftestsCompleted>())?;let oracle=Oracle::open(binding,host.source_arena_work())?;
 let(copy,copy_credit)=neutral_request_copy(request,host.source_arena_work())?;
 let mut actual=host.stage_standalone_native_selftests(copy,selectors,None)?;drop(copy_credit);actual.require_current()?;
 let native=actual.plan.native_selftest_result()?.ok_or_else(||io::Error::new(io::ErrorKind::InvalidData,"parity callback catalog did not finish"))?;let native_pass=native.failed()==0;let mut clean=native_pass;
 for lint in actual.plan.names(){
  let old=oracle.run(&root,&cache,super::legacy_analyze_oracle::Question::Selftest{lint},host.source_arena_work(),&mut||actual.require_current())?;
  let passed=old.code==0&&native_pass;clean&=passed;writeln!(report,"  [{}] selftest {}: legacy exit {}, native callback catalog {}",if passed{"ok"}else{"DIFF"},lint,old.code,if native_pass{"passed"}else{"failed"})?;
  if old.stderr.length()>0{old.stderr.publish(&mut diagnostics)?;}old.stdout.publish(&mut diagnostics)?;
 }
 actual.report=actual.report.into_replayable(host.source_arena_work()).map_err(|(_,error)|error)?;
 actual.report.replay_alias().ok_or_else(||io::Error::new(io::ErrorKind::InvalidData,"callback report replay absent"))?.publish(&mut diagnostics)?;
 // Keep native report and input proof intact for completion/currentness.
 let actual=actual;let result=SelftestsCompleted{clean,actual,oracle,_credit:credit};result.require_current(host.source_arena_work())?;Ok(result)
}

// Complete parity utility assembly. Native cases run on the SAME retained
// host; the explicitly versioned independent oracle may mutate ONLY owned
// scratch sources. Authored expected outputs require equality first.
use std::{sync::Arc,path::Path};
use dq_analyze::native_codemod_fixture_wire::{Binding as UtilityBinding,Question,SourceFrame};
use super::full_registry_check::parity_scratch::{Sandbox,OutputId};
#[path="runner_parity_inventory.rs"]mod inventory;

pub(crate)struct Completed{
 pub(crate)exit:i32,pub(crate)committed:usize,frame:SourceFrame,
 inventory:inventory::Inventory,fixtures:Vec<super::native_fixture::Completed>,checks:Option<ChecksCompleted>,baselines:Vec<Proof>,callbacks:Option<SelftestsCompleted>,oracle:Oracle,queries:Arc<crate::query_db::QueryDb>,_credit:SourceArenaCredit,
}
impl Completed{
 pub(crate)fn frame_ref(&self)->&SourceFrame{&self.frame}
 pub(crate)fn require_current(&self)->Result<(),BoxError>{
  self.oracle.require_current(self.queries.as_ref())?;self.inventory.require_current()?;
  for fixture in &self.fixtures{fixture.require_current()?;}if let Some(checks)=&self.checks{checks.require_current(self.queries.as_ref())?;}for baseline in &self.baselines{baseline.inputs.require_report_current(&baseline.project)?;}if let Some(callbacks)=&self.callbacks{callbacks.require_current(self.queries.as_ref())?;}Ok(())
 }
}
fn invalid(message:&'static str)->io::Error{io::Error::new(io::ErrorKind::InvalidInput,message)}
/// Stream canonical actual-case observation DATA into the existing Seal shape.
/// No source authority or completeness is inferred from this digest.
fn case_seal<T:serde::Serialize>(values:&[T],work:&dyn SourceArenaWork)->io::Result<dq_analyze::selected_exclusions_wire::Seal>{
 struct SealWriter<'a>{work:&'a dyn SourceArenaWork,length:u64,hash:xxhash_rust::xxh3::Xxh3,first:Option<io::Error>}
 impl Write for SealWriter<'_>{fn write(&mut self,bytes:&[u8])->io::Result<usize>{if let Some(first)=&self.first{return Err(first.kind().into())}if let Err(first)=self.work.checkpoint(){let proxy=first.kind().into();self.first=Some(first);return Err(proxy)}self.length=self.length.checked_add(bytes.len()as u64).filter(|length|*length<=dq_analyze::selected_exclusions_wire::MAX_STREAM).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;self.hash.update(bytes);Ok(bytes.len())}fn flush(&mut self)->io::Result<()>{Ok(())}}
 let mut writer=SealWriter{work,length:0,hash:xxhash_rust::xxh3::Xxh3::new(),first:None};let encoded=serde_json::to_writer(&mut writer,values);if let Some(first)=writer.first.take(){return Err(first)}encoded.map_err(|error|io::Error::new(error.io_error_kind().unwrap_or(io::ErrorKind::InvalidData),error))?;Ok(dq_analyze::selected_exclusions_wire::Seal{length:writer.length,hash:dq_analyze::selected_exclusions_wire::Hex128(writer.hash.digest128())})
}
fn preview_same_bytes(preview:&crate::selected_report_spool::Verified,bytes:&[u8])->io::Result<bool>{
 struct Compare<'a>{bytes:&'a[u8],offset:usize,equal:bool}
 impl Write for Compare<'_>{fn write(&mut self,part:&[u8])->io::Result<usize>{let end=self.offset.checked_add(part.len()).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;self.equal&=self.bytes.get(self.offset..end)==Some(part);self.offset=end;Ok(part.len())}fn flush(&mut self)->io::Result<()>{Ok(())}}
 let mut compare=Compare{bytes,offset:0,equal:true};preview.replay_alias().ok_or_else(||invalid("parity preview is not genuinely replayable"))?.publish(&mut compare)?;Ok(compare.equal&&compare.offset==bytes.len())
}
fn fixture_compare(oracle:&Oracle,real_root:&Path,cache:&Path,lint:&str,raw:&crate::selected_report_spool::Verified,expected:&crate::selected_report_spool::Verified,target:&super::fixture_scope::CapturedFixtureTarget,inputs:&FullRegistryCheckInputs,project:&Path,configuration:&Path,work:&dyn SourceArenaWork,report:&mut dyn Write,mut diagnostics:&mut dyn Write)->Result<bool,BoxError>{
 let mut scratch=Sandbox::new(cache,work)?;
 let actual=(||->Result<bool,BoxError>{
  scratch.copy_captured(inputs,project,real_root,Some(configuration),work)?;
  let output=scratch.ensure_fixture_output(target,real_root,work)?;
  let old=oracle.run(scratch.root(),cache,super::legacy_analyze_oracle::Question::Fixture{lint},work,&mut||{inputs.require_report_current(project)?;scratch.current(work)?;Ok(())})?;
  let same_raw=raw.replay_alias().ok_or_else(||invalid("fixture raw preview replay absent"))?.same_bytes(old.stdout,work)?;let raw_pass=same_raw&&old.code==0;
  old.stderr.publish(&mut diagnostics)?;
  let old_normalized=oracle.run_owned(&mut scratch,cache,super::legacy_analyze_oracle::OwnedQuestion::FixtureBless{lint},work,&mut||inputs.require_report_current(project))?;
  old_normalized.stderr.publish(&mut diagnostics)?;
  let same_expected=scratch.with_output_bytes(output,work,&mut|bytes|preview_same_bytes(expected,bytes))?;let passed=raw_pass&&same_expected&&old_normalized.code==0;
  writeln!(report,"  [{}] fixture {}: raw {}, normalized {}, legacy exits {}/{}",if passed{"ok"}else{"DIFF"},lint,if same_raw{"same"}else{"different"},if same_expected{"same"}else{"different"},old.code,old_normalized.code)?;
  inputs.require_report_current(project)?;scratch.current(work)?;Ok(passed)
 })();let cleanup=scratch.remove();match actual{Err(first)=>Err(first),Ok(value)=>{cleanup?;Ok(value)}}
}
fn baseline_compare(request:&BuildRequest,selectors:&[String],mode:dq_analyze::native_baseline_update_wire::Mode,oracle:&Oracle,host:&mut BuildHost,mut report:&mut dyn Write,mut diagnostics:&mut dyn Write)->Result<(bool,Proof),BoxError>{
 let(root,cache)=utility_paths(request)?;
 let(copy,copy_credit)=neutral_request_copy(request,host.source_arena_work())?;
 let preview=super::baseline_update::parity_preview(copy,selectors,mode,host)?;drop(copy_credit);preview.require_current()?;
 let mut scratch=Sandbox::new(&cache,host.source_arena_work())?;
 let actual=(||->Result<bool,BoxError>{
  scratch.copy_captured(&preview.inputs,&preview.project,&root,None,host.source_arena_work())?;
  let mut count=0usize;preview.visit_targets(&mut|_,_|{count=count.checked_add(1).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;Ok(())})?;
  let mut credit=host.source_arena_work().reserve(0)?;let mut outputs:Vec<OutputId>=super::native_utility_binding::vector(count,host.source_arena_work(),&mut credit)?;
  preview.visit_targets(&mut|target,_|{outputs.push(scratch.ensure_baseline_output(target,&root,host.source_arena_work())?);Ok(())})?;
  let old=oracle.run_owned(&mut scratch,&cache,super::legacy_analyze_oracle::OwnedQuestion::Baseline{names:selectors,mode},host.source_arena_work(),&mut||preview.require_current())?;
  old.stderr.publish(&mut diagnostics)?;old.stdout.publish(&mut diagnostics)?;
  let mut same=true;let mut index=0;preview.visit_targets(&mut|_,desired|{let output=*outputs.get(index).ok_or_else(||invalid("baseline output token count differs from SAME planner"))?;index+=1;same&=scratch.with_output_bytes(output,host.source_arena_work(),&mut|bytes|Ok(bytes==desired))?;Ok(())})?;
  if index!=outputs.len(){return Err(invalid("baseline output comparison omitted a genuine target").into())}
  let passed=same&&old.code==0;writeln!(report,"  [{}] baseline {:?}: {} target bytes, legacy exit {}",if passed{"ok"}else{"DIFF"},mode,if same{"same"}else{"different"},old.code)?;
  preview.require_current()?;scratch.current(host.source_arena_work())?;drop(outputs);drop(credit);Ok(passed)
 })();let cleanup=scratch.remove();let passed=match actual{Err(first)=>return Err(first),Ok(value)=>{cleanup?;value}};
 let(project,inputs,frame)=preview.into_inputs();Ok((passed,Proof{project,inputs,frame}))
}
/// Same completed utility shape as codemod and fixture. No terminal is emitted
/// until every actually requested case and its retained currentness proof exists.
pub(crate)fn run(request:&BuildRequest,binding:&UtilityBinding,host:&mut BuildHost,stdout:&mut dyn Write,stderr:&mut dyn Write)->Result<Completed,BoxError>{
 let mut committed=0;let result=run_bound(request,binding,host,stdout,stderr,&mut committed);result.map_err(|first|crate::native_fix::BatchFailure::from_operation(committed,first))
}
fn run_bound(request:&BuildRequest,binding:&UtilityBinding,host:&mut BuildHost,mut stdout:&mut dyn Write,mut stderr:&mut dyn Write,committed:&mut usize)->Result<Completed,BoxError>{
 binding.validate()?;let Question::Parity{selectors,fixtures_only,bless,oracle:oracle_binding}=&binding.question else{return Err(invalid("parity coordinator received another utility question").into())};
 let(root,cache)=utility_paths(request)?;if root!=binding.root.as_path(){return Err(invalid("parity utility root differs from authenticated request").into())}
 let queries=Arc::clone(host.query_db());let mut credit=queries.reserve(std::mem::size_of::<Completed>())?;
 let plan=super::prepare_native_registered_check_selection(selectors,FullRegistryCheckOptions{unused:false,no_cache:true,..Default::default()},queries.as_ref())?;
 let mut names_credit=queries.reserve(0)?;let mut names=super::native_utility_binding::vector(plan.names().len(),queries.as_ref(),&mut names_credit)?;
 for name in plan.names(){names.push(dm_preprocess::regions::copy_string_into_credit(name,queries.as_ref(),&mut names_credit)?);}drop(plan);
 let inventory=inventory::Inventory::capture(&root,&names,queries.as_ref())?;
 let oracle=Oracle::open(oracle_binding,queries.as_ref())?;
 let present=inventory.rows().iter().filter(|row|row.present).count();let real=if *fixtures_only{0}else{4};
 let mut frames_credit=queries.reserve(0)?;let mut frames=super::native_utility_binding::vector(present.checked_add(real).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?,queries.as_ref(),&mut frames_credit)?;
 let mut fixtures=super::native_utility_binding::vector(present,queries.as_ref(),&mut credit)?;
 let mut callback_frames=super::native_utility_binding::vector(if *fixtures_only{0}else{1},queries.as_ref(),&mut frames_credit)?;
 let mut baselines=super::native_utility_binding::vector(if *fixtures_only{0}else{2},queries.as_ref(),&mut credit)?;
 let mut clean=true;
 // Authoring precedes the real-tree questions, so expected-only commits cannot
 // invalidate an earlier whole-tree proof. Every fixture retains its final
 // post-write native input closure; inventory stores presence, not row bytes.
 for row in inventory.rows(){
  inventory.require_current()?;if !row.present{writeln!(stdout,"  [skip] fixture {}: no captured directory",row.name)?;continue}
  let(copy,copy_credit)=super::native_codemod::request_copy(request,queries.as_ref())?;
  let actual=host.stage_native_parity_fixture(copy,&root,&row.name,*bless,&mut|raw,expected,target,inputs,project,configuration,work|fixture_compare(&oracle,&root,&cache,&row.name,raw,expected,target,inputs,project,configuration,work,&mut stdout,&mut stderr))?;drop(copy_credit);
  clean&=actual.comparison_accepted;*committed=committed.checked_add(actual.committed).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;frames.push(actual.frame);
  fixtures.push(super::native_fixture::finish_report(actual,&mut stdout,&mut stderr)?);
 }
 let(checks,callbacks)=if *fixtures_only{(None,None)}else{
  let checks=run_real_checks(request,&names,oracle_binding,host,&mut stdout,&mut stderr)?;clean&=checks.clean;frames.push(checks.default.frame);frames.push(checks.raw.frame);
  for mode in[dq_analyze::native_baseline_update_wire::Mode::Update,dq_analyze::native_baseline_update_wire::Mode::Seed]{let(passed,proof)=baseline_compare(request,&names,mode,&oracle,host,&mut stdout,&mut stderr)?;clean&=passed;frames.push(proof.frame);baselines.push(proof);}
  let callbacks=run_selftests(request,&names,oracle_binding,host,&mut stdout,&mut stderr)?;clean&=callbacks.clean;callback_frames.push(callbacks.selection());(Some(checks),Some(callbacks))
 };
 drop(names);drop(names_credit);
 let frame=SourceFrame::Parity{checks:u64::try_from(frames.len()).map_err(|_|io::Error::from(io::ErrorKind::OutOfMemory))?,check_frames:case_seal(&frames,queries.as_ref())?,callbacks:u64::try_from(callback_frames.len()).map_err(|_|io::Error::from(io::ErrorKind::OutOfMemory))?,callback_frames:case_seal(&callback_frames,queries.as_ref())?};drop(frames);drop(callback_frames);drop(frames_credit);
 let completed=Completed{exit:if clean{0}else{1},committed:*committed,frame,inventory,fixtures,checks,baselines,callbacks,oracle,queries,_credit:credit};completed.require_current()?;Ok(completed)
}
#[cfg(test)]mod parity_byte_controls{
 use super::*;
 #[test]fn genuine_preview_equality_checks_empty_prefix_suffix_and_interior_bytes(){let cache=std::fs::canonicalize(crate::test_scratch::dir("parity-preview-byte-equality")).unwrap();let host=BuildHost::default();for bytes in[&b""[..],&b"exact\n"[..]]{let mut stage=crate::selected_report_spool::Stage::new(&cache).unwrap();stage.write_all(bytes).unwrap();let preview=stage.seal_allow_empty().unwrap().validate(|r|io::copy(r,&mut io::sink())).unwrap().0.into_replayable(host.source_arena_work()).map_err(|(_,error)|error).unwrap();assert!(preview_same_bytes(&preview,bytes).unwrap());assert!(!preview_same_bytes(&preview,b"wrong").unwrap());}}
}

#[cfg(test)]
#[path="../../../../analyze/fixtures/report_configuration.rs"]
mod parity_report_configuration;

#[cfg(test)]mod actual_frozen_parity_controls{
 use super::*;
 // Keep actual collected reference diagnostics when a preceding operation
 // fails before the full parity report can be published. Test-only/external
 // owned cache: no source edit, reference retry or success expectation change.
 fn completed_with_failure_evidence(actual:Result<Completed,BoxError>,out:&[u8],err:&[u8],cache:&std::path::Path)->Completed{
  match actual{Ok(value)=>value,Err(first)=>{
   let mut copies=Vec::new();for(name,bytes)in[("parity-failure-report.stdout",out),("parity-failure-diagnostics.stderr",err)]{let path=cache.join(name);let copied=std::fs::OpenOptions::new().create_new(true).write(true).open(&path).and_then(|mut file|std::io::Write::write_all(&mut file,bytes));copies.push((path,copied.map_err(|error|error.to_string())));}
   panic!("actual parity error={first:?}; preserved evidence={copies:?}; report prefix={}; reference diagnostics prefix={}",String::from_utf8_lossy(&out[..out.len().min(2048)]),String::from_utf8_lossy(&err[..err.len().min(4096)]));
  }}
 }
 fn configured(label:&str)->(BuildHost,BuildRequest,UtilityBinding,std::path::PathBuf){
  let root=std::fs::canonicalize(crate::test_scratch::dir(label)).unwrap();let cache=std::fs::canonicalize(crate::test_scratch::dir(&format!("{label}-cache"))).unwrap();std::fs::create_dir_all(root.join("code")).unwrap();std::fs::create_dir_all(root.join("tools/ci")).unwrap();std::fs::create_dir_all(root.join("tools/analyze/fixtures/scheduler/code")).unwrap();
  super::parity_report_configuration::complete(&root.join("tools/ci/lint_scopes.toml"));std::fs::write(root.join("code/probe.dm"),b"/proc/native_parity_probe()\n    sleep(1)\n").unwrap();std::fs::write(root.join("tools/analyze/fixtures/scheduler/code/probe.dm"),b"/proc/native_parity_fixture()\n    sleep(1)\n").unwrap();
  let crate::request::Command::Build(build)=crate::cli::parse(&["prepare-query".into(),root.join("deepquarry.dme").to_string_lossy().into_owned()]).unwrap()else{panic!("actual native PrepareQuery contract changed")};let mut request=*build;request.cache_root=Some(cache);request.no_cache=true;request.exact_inputs=true;request.progress_enabled=false;request.timeout_seconds=Some(300);request.workers=1;
  use crate::policy_request::{PolicyInputRequest,WorkspacePolicyRequest,AnalysisContext,WorkspaceAuxiliaryQuestion as Q};request.policy_inputs=Some(PolicyInputRequest{analysis_context:Some(AnalysisContext::OriginalAnalyze0290),workspace:Some(WorkspacePolicyRequest{root:root.clone(),recursive_roots:vec![root.join("code"),root.join("maps")],configuration:root.join("tools/ci/lint_scopes.toml")}),workspace_auxiliary:vec![Q::SemReads],..Default::default()});
  let image=std::path::PathBuf::from(std::env::var_os("DQ_TEST_FROZEN_ANALYZE_ORACLE").expect("explicit frozen independent reference executable"));let sha256=std::env::var("DQ_TEST_FROZEN_ANALYZE_ORACLE_SHA256").expect("explicit exact frozen image SHA-256");let binding=UtilityBinding{schema:dq_analyze::native_codemod_fixture_wire::Schema::V2,root:root.clone(),question:Question::Parity{selectors:vec!["scheduler".into()],fixtures_only:false,bless:false,oracle:dq_analyze::native_codemod_fixture_wire::FrozenOracleBinding{image,sha256}}};(BuildHost::default(),request,binding,root)
 }
 #[test]#[ignore="requires explicit frozen independent Analyze image; no reference build or fallback"]fn actual_frozen_reference_and_native_full_cases_use_one_native_host_and_do_not_write_the_project(){
  let(mut host,request,binding,root)=configured("native-parity-actual-full");let source=std::fs::read(root.join("code/probe.dm")).unwrap();let config=std::fs::read(root.join("tools/ci/lint_scopes.toml")).unwrap();
  let mut out=Vec::new();let mut err=Vec::new();let actual=super::super::full_registry_check::with_full_registry_check_context(request.command,request.timeout_seconds,||run(&request,&binding,&mut host,&mut out,&mut err));let actual=completed_with_failure_evidence(actual,&out,&err,request.cache_root.as_deref().unwrap());assert_eq!(actual.exit,0,"actual native/reference mismatch: {} / {}",String::from_utf8_lossy(&out),String::from_utf8_lossy(&err));assert_eq!(actual.committed,0);actual.require_current().unwrap();
  assert!(matches!(actual.frame_ref(),SourceFrame::Parity{checks:5,callbacks:1,..}));assert_eq!(std::fs::read(root.join("code/probe.dm")).unwrap(),source);assert_eq!(std::fs::read(root.join("tools/ci/lint_scopes.toml")).unwrap(),config);assert!(!root.join("deepquarry.dme").exists());assert!(!root.join("tools/analyze/fixtures/scheduler/expected.txt").exists());
 }
 #[test]#[ignore="requires explicit frozen independent Analyze image; no reference build or fallback"]fn actual_fixture_bless_is_guarded_by_raw_and_normalized_reference_equality(){
  let(mut host,request,mut binding,root)=configured("native-parity-actual-bless");let Question::Parity{fixtures_only,bless,..}=&mut binding.question else{unreachable!()};*fixtures_only=true;*bless=true;
  let mut out=Vec::new();let mut err=Vec::new();let actual=super::super::full_registry_check::with_full_registry_check_context(request.command,request.timeout_seconds,||run(&request,&binding,&mut host,&mut out,&mut err));let actual=completed_with_failure_evidence(actual,&out,&err,request.cache_root.as_deref().unwrap());assert_eq!(actual.exit,0,"{} / {}",String::from_utf8_lossy(&out),String::from_utf8_lossy(&err));assert_eq!(actual.committed,1);actual.require_current().unwrap();let expected=std::fs::read(root.join("tools/analyze/fixtures/scheduler/expected.txt")).unwrap();assert!(!expected.is_empty());assert!(std::str::from_utf8(&expected).unwrap().lines().all(|line|line.split('\t').count()==3));assert!(matches!(actual.frame_ref(),SourceFrame::Parity{checks:1,callbacks:0,..}));
 }
 #[test]fn canonical_case_seals_are_order_sensitive_and_preserve_first_work_error(){
  let work=crate::query_db::QueryDb::default();let a=case_seal(&[1u64,2],&work).unwrap();let b=case_seal(&[2u64,1],&work).unwrap();assert_ne!(a,b);
  struct Denied;impl SourceArenaWork for Denied{fn checkpoint(&self)->io::Result<()>{Err(io::Error::from_raw_os_error(1450))}fn reserve(&self,_:usize)->io::Result<SourceArenaCredit>{panic!("case observation needs no separate allocation")}fn grow(&self,_:&mut SourceArenaCredit,_:usize)->io::Result<()>{panic!("no new budget")}fn shrink(&self,_:&mut SourceArenaCredit,_:usize)->io::Result<()>{panic!("no new budget")}}
  assert_eq!(case_seal(&[1u64],&Denied).unwrap_err().raw_os_error(),Some(1450));
 }
}

#[cfg(test)]mod actual_utility_projection_controls{
 use super::*;
 #[test]fn authenticated_sem_entry_projects_to_actual_neutral_registry_without_mutating_original(){
  let root=std::fs::canonicalize(crate::test_scratch::dir("parity-neutral-root")).unwrap();let cache=std::fs::canonicalize(crate::test_scratch::dir("parity-neutral-cache")).unwrap();let crate::request::Command::Build(build)=crate::cli::parse(&["prepare-query".into(),root.join("deepquarry.dme").to_string_lossy().into_owned()]).unwrap()else{panic!("actual prepare request factory changed")};let mut request=*build;request.cache_root=Some(cache);request.exact_inputs=true;request.no_cache=true;request.timeout_seconds=Some(120);request.engine_template=None;request.bootstrap_catalog=false;
  use crate::policy_request::{PolicyInputRequest,WorkspacePolicyRequest,AnalysisContext,WorkspaceAuxiliaryQuestion as Q};request.policy_inputs=Some(PolicyInputRequest{analysis_context:Some(AnalysisContext::OriginalAnalyze0290),workspace:Some(WorkspacePolicyRequest{root:root.clone(),recursive_roots:vec![root.join("code"),root.join("maps")],configuration:root.join("tools/ci/lint_scopes.toml")}),workspace_auxiliary:vec![Q::SemReads],..Default::default()});
  let work=crate::query_db::QueryDb::default();utility_paths(&request).unwrap();let(neutral,credit)=neutral_request_copy(&request,&work).unwrap();let original=request.policy_inputs.as_ref().unwrap();assert_eq!(original.workspace_auxiliary,[Q::SemReads]);assert_eq!(original.workspace.as_ref().unwrap().recursive_roots,[root.join("code"),root.join("maps")]);let policy=neutral.policy_inputs.as_ref().unwrap();assert!(policy.workspace_auxiliary.is_empty());let expected=Q::authored_doc_ui_roots(Q::PRIVATE_FULL_REGISTRY).unwrap();assert_eq!(policy.workspace.as_ref().unwrap().recursive_roots.len(),expected.len());BuildHost::native_registry_check_paths(&neutral).unwrap();drop(neutral);drop(credit);
 }
}

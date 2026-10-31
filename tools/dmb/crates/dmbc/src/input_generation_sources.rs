//! Actual generation-only raw source loans. No ColdFrontend, PolicyInputs,
//! SourceExportMapping, semantic/body/read completeness or cached result exists.
use super::*;
use dq_analyze::{captured_generator_budget::Budget,captured_raw_file::RawPolicyViews,captured_reactive_reads::Failure};
use crate::runner_host::{workspace_discovery::DiscoveryReceipt,workspace_capture::WorkspaceAliasIndex};
use std::sync::Arc;
fn oom(budget:&Budget,message:impl Into<String>)->Failure{budget.deny();Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message.into()))}
fn charge(budget:&Budget,bytes:Option<usize>)->Result<(),Failure>{let bytes=bytes.ok_or_else(||oom(budget,"generation raw allocation overflow"))?;budget.charge(bytes).map_err(|message|oom(budget,message))}

#[derive(Clone,Copy)]pub(crate) enum GenerationSourceFrame<'a>{Declarations(&'a GenerationBootstrap),Questions(&'a GenerationQuestionBootstrap)}
impl<'a> GenerationSourceFrame<'a>{
 pub(crate) fn originals(self)->dm_preprocess::regions::GenerationOriginalSources<'a>{match self{Self::Declarations(frame)=>frame.declarations.original_sources(),Self::Questions(frame)=>frame.questions.original_sources()}}
 pub(crate) fn root_source(self)->Option<&'a Path>{match self{Self::Declarations(frame)=>frame.declarations.root_source(),Self::Questions(frame)=>frame.questions.root_source()}}
 pub(crate) fn require_recording<P:SnapshotProvider>(self,inputs:&RecordingInputs<P>)->io::Result<()>{match self{Self::Declarations(frame)=>frame.require_recording(inputs),Self::Questions(frame)=>frame.require_recording(inputs)}}
 pub(crate) fn questions(self)->Option<&'a dm_tree::frontend::GenerationNativeQuestions>{match self{Self::Questions(frame)=>Some(&frame.questions),_=>None}}
}
#[derive(Clone,Copy)]enum ActiveFileKind{Discovered(usize),Callable}
struct ActiveFile<'a>{slot:&'a std::cell::Cell<Option<ActiveFileKind>>,before:Option<ActiveFileKind>}impl Drop for ActiveFile<'_>{fn drop(&mut self){self.slot.set(self.before)}}

enum Original<'a>{Native{primary:&'a Path,lease:&'a dm_preprocess::SourceAcquisitionLease},Owned(dm_resources::SharedBytes)}
struct File<'a>{path:&'a Path,relative:String,original:Original<'a>}
pub(crate) struct GenerationSourceReader<'a,P:SnapshotProvider>{
 frame:GenerationSourceFrame<'a>,inputs:&'a RecordingInputs<P>,discovery:&'a Arc<DiscoveryReceipt>,
 files:Vec<File<'a>>,native:Vec<(&'a Path,&'a dm_preprocess::SourceAcquisitionLease)>,active_file:std::cell::Cell<Option<ActiveFileKind>>,budget:&'a Arc<Budget>,code_completed:std::cell::Cell<bool>,tests_completed:std::cell::Cell<bool>,
}
impl<P:SnapshotProvider> RecordingInputs<P>{
 fn require_generation_capture_current(&self)->io::Result<()>{
  // Read the SAME actual recorder ledger. This operation is serialized by the
  // existing host/query gate; no cloned InputSnapshot or secondary fact store.
  let actual=self.snapshot.lock().map_err(|_|io::Error::other("generation input mutex poisoned"))?;
  if !actual.restat(&self.provider)?.unchanged(){return Err(io::Error::new(io::ErrorKind::InvalidData,"generation raw closure changed; reissue generation frame"))}Ok(())
 }
 fn generation_owned_original(&self,path:&Path,budget:&Budget)->Result<dm_resources::SharedBytes,Failure>{
  crate::daemon::control::checkpoint()?;
  // This stamp is a size preflight, not source authority. The SAME bounded
  // original read below verifies/records its own actual stamp and digest.
  let stamp=self.provider.stamp(path)?;
  let size=usize::try_from(stamp.size).map_err(|_|oom(budget,"generation raw size exceeds address space"))?;
  let envelope=size.checked_mul(4).and_then(|n|n.checked_add(8192)).ok_or_else(||oom(budget,"generation raw read envelope overflow"))?;
  charge(budget,Some(envelope))?;
  self.read_policy_candidate(path,envelope)?.ok_or_else(||Failure::Operational(io::Error::new(io::ErrorKind::Interrupted,"discovered generation source disappeared")))
 }
}
impl<'a,P:SnapshotProvider> GenerationSourceReader<'a,P>{
 pub(crate) fn capture(frame:&'a GenerationBootstrap,inputs:&'a RecordingInputs<P>,discovery:&'a Arc<DiscoveryReceipt>,budget:&'a Arc<Budget>)->Result<Self,Failure>{Self::capture_frame(GenerationSourceFrame::Declarations(frame),inputs,discovery,budget)}
 pub(crate) fn capture_questions(frame:&'a GenerationQuestionBootstrap,inputs:&'a RecordingInputs<P>,discovery:&'a Arc<DiscoveryReceipt>,budget:&'a Arc<Budget>)->Result<Self,Failure>{Self::capture_frame(GenerationSourceFrame::Questions(frame),inputs,discovery,budget)}
 pub(crate) fn capture_frame(frame:GenerationSourceFrame<'a>,inputs:&'a RecordingInputs<P>,discovery:&'a Arc<DiscoveryReceipt>,budget:&'a Arc<Budget>)->Result<Self,Failure>{
  frame.require_recording(inputs)?;discovery.validate_recording(inputs)?;
  let root=frame.root_source().and_then(Path::parent).ok_or_else(||Failure::Operational(io::Error::new(io::ErrorKind::InvalidData,"generation manifest root is absent")))?;
  if canonical_path(root)!=discovery.contract().root{return Err("generation source discovery belongs to another root".into())}
  let mut admit=|bytes|budget.charge(bytes).map_err(|message|io::Error::new(io::ErrorKind::OutOfMemory,message));
  if !discovery.covers_code_dm(&mut admit)?||!discovery.covers_generator_cli_tests(&mut admit)?{return Err("generation requires actual full CODE and generator-CLI discovery".into())}
  let count=frame.originals().count();charge(budget,count.checked_mul(std::mem::size_of::<(&Path,&dm_preprocess::SourceAcquisitionLease)>()).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(1024)))?;
  let native_capacity=count.checked_mul(4).ok_or_else(||oom(budget,"generation native source directory capacity overflow"))?;
  let mut native=Vec::new();native.try_reserve_exact(count).map_err(|_|oom(budget,"generation native source directory allocation refused"))?;if native.capacity()>native_capacity{return Err(oom(budget,"generation native source directory capacity exceeds admission"))}
  for(path,lease)in frame.originals(){let lease=lease.ok_or("generation original lease absent")?;native.push((path,lease));}
  native.sort_unstable_by(|a,b|a.0.cmp(b.0));
  for pair in native.windows(2){if pair[0].0==pair[1].0&&!pair[0].1.same_binding(pair[1].1){return Err("generation repeated source has different original acquisitions".into())}}
  native.dedup_by(|a,b|a.0==b.0);
  let aliases_charge=WorkspaceAliasIndex::reserve_charge(native.iter().map(|row|row.0))?;charge(budget,Some(aliases_charge))?;let aliases=WorkspaceAliasIndex::new(native.iter().map(|row|row.0),aliases_charge)?;
  let count=discovery.files().len();let widths=discovery.files().iter().try_fold(0usize,|n,path|n.checked_add(path.as_os_str().len().checked_mul(8)?));
  charge(budget,widths.and_then(|n|count.checked_mul(std::mem::size_of::<File<'_>>())?.checked_mul(4)?.checked_add(n)?.checked_add(4096)))?;
  let file_capacity=count.checked_mul(4).ok_or_else(||oom(budget,"generation file directory capacity overflow"))?;
  let mut files=Vec::new();files.try_reserve_exact(count).map_err(|_|oom(budget,"generation file directory allocation refused"))?;if files.capacity()>file_capacity{return Err(oom(budget,"generation file directory capacity exceeds admission"))}
  for path in discovery.files(){
   budget.require().map_err(|message|oom(budget,message))?;crate::daemon::control::checkpoint()?;
   let relative=dm_preprocess::regions::relative_filesystem_path(path,&discovery.contract().root).ok_or("generation source escapes root")?.to_string_lossy().replace('\\',"/");
   let primary=match native.binary_search_by(|row|row.0.cmp(path.as_path())){Ok(index)=>Some(native[index]),Err(_)=>match aliases.candidate(path)?{Some(primary)=>{
    let index=native.binary_search_by(|row|row.0.cmp(primary)).map_err(|_|Failure::from("generation native alias candidate absent"))?;let lease=native[index].1;
    let proof=inputs.acquire_source_alias(path,primary,lease.source_text())?.ok_or("generation source alias proof unavailable")?;
    if proof.primary_path()!=primary{return Err("generation source alias has foreign primary".into())}Some((primary,lease))
   },None=>None}};
   let original=match primary{Some((primary,lease))=>{if !inputs.validate_source_lease(primary,lease){return Err("generation native lease changed during capture".into())}crate::input_snapshot::recorded_source_original(lease)?;Original::Native{primary,lease}},None=>Original::Owned(inputs.generation_owned_original(path,budget)?)};
   files.push(File{path,relative,original});
  }
  drop(aliases);
  let reader=Self{frame,inputs,discovery,files,native,active_file:std::cell::Cell::new(None),budget,code_completed:std::cell::Cell::new(false),tests_completed:std::cell::Cell::new(false)};reader.require_current()?;Ok(reader)
 }
 pub(crate) fn root(&self)->&Path{&self.discovery.contract().root}
 pub(crate) fn budget(&self)->&Arc<Budget>{self.budget}
 pub(crate) fn checkpoint(&self)->Result<(),Failure>{self.budget.require().map_err(|message|oom(self.budget,message))?;crate::daemon::control::checkpoint()?;self.budget.require().map_err(|message|oom(self.budget,message))}
 pub(crate) fn require_current(&self)->Result<(),Failure>{
  self.checkpoint()?;self.frame.require_recording(self.inputs)?;self.discovery.validate_recording(self.inputs)?;
  self.inputs.require_generation_capture_current()?;self.checkpoint()
 }
 fn with_original(&self,path:&Path,original:&crate::input_snapshot::RecordedSourceOriginal<'_>,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{
  dq_analyze::captured_raw_file::with_original_policy_file_prepared(self.root(),path,0,self.budget,|scratch|{
    self.checkpoint()?;
    let mut backing=Some(0usize);let raw=match &original{crate::input_snapshot::RecordedSourceOriginal::Utf8(text)=>{dq_analyze::captured_raw_file::visit_source_storage(text,|_,bytes|backing=backing.and_then(|n|n.checked_add(bytes)));text.as_bytes()},crate::input_snapshot::RecordedSourceOriginal::Bytes(bytes)=>{backing=bytes.capacity().checked_add(128);bytes.as_slice()}};
    let transform=if matches!(&original,crate::input_snapshot::RecordedSourceOriginal::Utf8(text)if !text.as_bytes().contains(&b'\r')){Some(0)}else{dq_analyze::captured_raw_file::analyze_raw_len(raw)?.checked_mul(4).and_then(|n|n.checked_add(8192))};
    charge(scratch,backing.and_then(|n|n.checked_add(transform?)))?;Ok(crate::input_snapshot::normalize_recorded_policy_original(&original))
   },visit)
 }
 fn for_each_domain(&self,tests:bool,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{
  self.checkpoint()?;
  for(index,file)in self.files.iter().enumerate(){
   let selected=if tests{dq_analyze::captured_raw_file::is_generator_cli_test_source(&file.relative)}else{dq_analyze::captured_raw_file::is_code_dm(&file.relative)};if !selected{continue}
   self.checkpoint()?;
   let original=match &file.original{Original::Native{primary,lease}=>{if !self.inputs.validate_source_lease(primary,lease){return Err("generation source acquisition became foreign".into())}crate::input_snapshot::recorded_source_original(lease)?},Original::Owned(bytes)=>crate::input_snapshot::RecordedSourceOriginal::Bytes(bytes)};
   if self.active_file.get().is_some(){return Err("generation original file loans cannot reenter".into())}
   let before=self.active_file.replace(Some(ActiveFileKind::Discovered(index)));let active=ActiveFile{slot:&self.active_file,before};
   let pending=self.with_original(file.path,&original,visit);
   drop(active);
   if matches!(&pending,Err(Failure::Operational(_))){return pending}self.checkpoint()?;if !pending?{return Ok(false)}
  }
  self.checkpoint()?;if tests{self.tests_completed.set(true)}else{self.code_completed.set(true)}Ok(true)
 }
 pub(crate) fn with_auto_configuration<T>(&self,path:&Path,consume:impl FnOnce(&dq_analyze::captured_raw_file::Config)->Result<T,Failure>)->Result<T,Failure>{
  self.checkpoint()?;charge(self.budget,self.root().as_os_str().len().checked_mul(32).and_then(|n|n.checked_add(4096)))?;let expected=dm_preprocess::regions::canonical_path(&self.root().join("tools/ci/lint_scopes.toml"));if path!=expected{return Err("generation Auto requires the actual fixed lint_scopes configuration request".into())}
  let scratch=Budget::scoped_temporaries(self.budget).map_err(|m|oom(self.budget,m))?;struct Held<'a>{budget:&'a Budget,complete:bool}impl Drop for Held<'_>{fn drop(&mut self){if !self.complete{self.budget.keep_failed_scratch()}}}let mut held=Held{budget:&scratch,complete:false};
  let produced=(||{let read_limit=match self.inputs.provider.stamp(path){Ok(stamp)=>{let size=usize::try_from(stamp.size).map_err(|_|oom(&scratch,"generation Auto configuration size overflow"))?;if size>dq_analyze::captured_raw_policy::MAX_FIXTURE_FILE_BYTES{return Err("generation Auto configuration exceeds existing configuration admission".into())}size.checked_mul(4).and_then(|n|n.checked_add(8192)).ok_or_else(||oom(&scratch,"generation Auto configuration read bound overflow"))?},Err(actual)if actual.kind()==io::ErrorKind::NotFound=>0,Err(actual)=>return Err(Failure::Operational(actual))};
   charge(&scratch,Some(read_limit))?;let original=self.inputs.read_policy_candidate(path,read_limit)?;let parse=original.as_ref().map_or(Some(1024),|bytes|bytes.len().checked_mul(64).and_then(|n|n.checked_add(1024)));charge(&scratch,parse)?;let config=dq_analyze::captured_raw_file::Config::capture(match original.as_ref(){Some(bytes)=>dq_analyze::captured_raw_policy::Configuration::Captured(bytes.as_slice()),None=>dq_analyze::captured_raw_policy::Configuration::ProvenMissing})?;let value=consume(&config);drop(config);drop(original);value})();
  if matches!(&produced,Err(Failure::Operational(_))){return produced}self.checkpoint()?;scratch.require().map_err(|m|oom(&scratch,m))?;if produced.is_ok(){held.complete=true}drop(held);drop(scratch);produced
 }
 pub(crate) fn for_each_tests(&self,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{self.for_each_domain(true,visit)}
 pub(crate) fn require_completed(&self)->Result<(),Failure>{self.require_current()?;if !self.code_completed.get()||!self.tests_completed.get(){return Err("generation source domains have not completed".into())}Ok(())}
}
impl<P:SnapshotProvider> dq_analyze::reactive_raw_policy_pages::RawPolicyPages for GenerationSourceReader<'_,P>{
 fn generation_questions(&self)->Option<&dm_tree::frontend::GenerationNativeQuestions>{self.frame.questions()}
 fn generation_compiled_file(&self,relative:&str)->Result<Option<dm_ir::FileId>,Failure>{
  self.checkpoint()?;let Some(ActiveFileKind::Discovered(index))=self.active_file.get()else{return Err("generation compiled identity requires the active discovered original file loan".into())};let file=self.files.get(index).ok_or("generation active original file absent")?;if file.relative!=relative{return Err("generation compiled identity belongs to another current file".into())}
  let q=self.frame.questions().ok_or("generation declaration questions were not selected")?;match &file.original{Original::Native{primary,lease}=>{if !self.inputs.validate_source_lease(primary,lease){return Err("generation compiled identity acquisition is foreign".into())}Ok(Some(q.file_id_for_path(primary).ok_or("generation native acquisition file id absent")?))},Original::Owned(_)=>Ok(None)}
 }
 fn with_callable_file(&self,ordinal:usize,name:&str,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<(),Failure>)->Result<(),Failure>{
  self.checkpoint()?;let questions=self.frame.questions().ok_or("generation callable source role was not selected")?;let body=questions.bodies().get(ordinal).ok_or("generation callable original ordinal unavailable")?;let node=questions.tree().member(body.member).ok_or("generation callable original member unavailable")?;if questions.tree().symbols().text(node.name)!=Some(name){return Err("generation callable file request differs from issued original name".into())}let(issued,point)=questions.callable_original_header(body.member)?;if issued!=ordinal{return Err("generation callable original ordinal differs".into())}
  let index=self.native.binary_search_by(|row|row.0.cmp(point.path)).map_err(|_|Failure::from("generation callable original acquisition absent"))?;let(primary,lease)=self.native[index];if !self.inputs.validate_source_lease(primary,lease){return Err("generation callable acquisition belongs to another current recorder".into())}let original=crate::input_snapshot::recorded_source_original(lease)?;if self.active_file.get().is_some(){return Err("generation callable raw loan cannot reenter a live file".into())}let before=self.active_file.replace(Some(ActiveFileKind::Callable));let active=ActiveFile{slot:&self.active_file,before};
  let mut called=false;let pending=self.with_original(primary,&original,&mut|relative,views|{if called{return Err("generation callable raw loan repeated".into())}called=true;visit(relative,views)?;Ok(true)});drop(active);if matches!(&pending,Err(Failure::Operational(_))){return pending.map(|_|())}self.checkpoint()?;if !pending?||!called{return Err("generation callable original file loan incomplete".into())}Ok(())
 }
 fn for_each(&self,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{self.for_each_domain(false,visit)}
}

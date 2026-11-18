//! Closed Sys reactive compound EOF under the SAME reader/current guard.
use super::*;
use dq_analyze::{captured_reactive_reads::GlobalProvider,captured_sys_reactive};
pub(crate) struct WorkspaceSysReactiveWitness{capture:Weak<WorkspaceCapture>}
impl WorkspaceSysReactiveWitness{
 pub(crate) fn matches(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,inputs:&dm_analysis::policy_inputs::PolicyInputs)->Result<bool,Failure>{
  if !capture.has_semantic_question(crate::policy_request::WorkspaceAuxiliaryQuestion::SysReactive){return Ok(false)}
  matches_capture_witness(&self.capture,capture,scope,inputs)
 }
 pub(crate) fn visit_storage(&self,mut visit:impl FnMut(usize,usize)){if !self.capture.as_ptr().is_null(){visit(self.capture.as_ptr()as usize,std::mem::size_of::<WorkspaceCapture>()+2*std::mem::size_of::<usize>())}}
}
impl WorkspaceCodeReader<'_,'_>{
 fn with_sys_reactive_auto(&self,visit:&mut dyn FnMut(Option<RawPolicyViews<'_>>)->Result<(),Failure>)->Result<bool,Failure>{
  self.checkpoint()?;let index=self.capture.sys_reactive_auto_index(self.scope,&mut|bytes|self.budget.charge(bytes).map_err(|message|io::Error::new(io::ErrorKind::OutOfMemory,message)))?;
  let Some(index)=index else{visit(None)?;self.checkpoint()?;return Ok(false)};
  let fixed=self.fixed.checked_add(self.budget.used()).ok_or_else(||Failure::Operational(io::ErrorKind::OutOfMemory.into()))?;
  let available=self.db.workspace_input_headroom_locked(fixed)?;
  let(files,end)=self.capture.sys_reactive_auto_page(self.scope,index,available)?;
  if end!=index+1||files.len()!=1{return Err("Sys reactive fixed source page lost actual acquisition".into())}
  let file=&files[0];let text=file.text.as_ref().ok_or("Sys reactive positive AUTO page has no original text")?;
  let live=files.capacity().checked_mul(std::mem::size_of::<CurrentFile>()).and_then(|n|n.checked_add(file.charge)).and_then(|n|n.checked_add(file.path.capacity())).ok_or_else(||Failure::Operational(io::ErrorKind::OutOfMemory.into()))?;
  let mut calls=0usize;
  let pending=dq_analyze::captured_raw_file::with_original_policy_file(self.capture.root(),&file.path,text.clone(),live,&self.budget,&mut|relative,views|{if relative!=dq_analyze::auto_setter_calls_policy::AUTO_REL||calls!=0{return Err("Sys reactive AUTO callback changed role or repeated".into())}calls+=1;visit(Some(views))?;Ok(true)});
  if matches!(&pending,Err(Failure::Operational(_))){return pending.map(|_|false)}
  if !pending?||calls!=1{return Err("Sys reactive AUTO callback did not complete".into())}self.checkpoint()?;Ok(true)
 }
 pub(crate) fn sys_reactive_data(&self,inputs:&dm_analysis::policy_inputs::PolicyInputs,config:&Config,globals:&dyn GlobalProvider,poll:&dyn Fn()->io::Result<()>)->Result<(captured_sys_reactive::Data,WorkspaceSysReactiveWitness),Failure>{
  self.require_policy_inputs(inputs)?;self.require_sys_discovery()?;
  if !self.capture.has_semantic_question(crate::policy_request::WorkspaceAuxiliaryQuestion::SysReactive){return Err("Sys reactive semantic question was not selected".into())}
  let actual=dq_analyze::sys_reactive_policy::metadata().select;let required=dq_analyze::dm::sys::policy_selection();
  if actual.roots!=required.roots||actual.hidden!=required.hidden{return Err("Sys reactive Meta.Select differs from CODE_MAPS_DM".into())}
  struct Pages<'r,'c,'s>{reader:&'r WorkspaceCodeReader<'c,'s>,inputs:&'r dm_analysis::policy_inputs::PolicyInputs,config:&'r Config,passes:std::cell::Cell<usize>,auto:std::cell::Cell<Option<bool>>}
  impl dq_analyze::reactive_raw_policy_pages::RawPolicyPages for Pages<'_,'_,'_>{
   fn for_each(&self,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{
    let pass=self.passes.get();let selected=match(pass,self.auto.get()){(0,None)=>true,(1,Some(true))=>false,(1,Some(false))|(2,Some(true))=>true,_=>return Err("Sys reactive source phase order differs".into())};
    if selected{let Some(completion)=self.reader.for_each_sys_selection(self.config,"sys/dx_reactive","sys",visit)?else{return Ok(false)};completion.require()?;}
    else{let completion=self.reader.for_each_code_file_completed(self.inputs,visit)?;let Some(witness)=completion.into_witness()?else{return Ok(false)};if !witness.matches(self.reader.capture,self.reader.scope,self.inputs)?{return Err("Sys reactive conditional CODE EOF belongs to another owner".into())}}
    self.reader.checkpoint()?;self.passes.set(pass+1);Ok(true)
   }
  }
  impl captured_sys_reactive::Pages for Pages<'_,'_,'_>{fn with_auto_tracked(&self,visit:&mut dyn FnMut(Option<RawPolicyViews<'_>>)->Result<(),Failure>)->Result<(),Failure>{if self.passes.get()!=1||self.auto.get().is_some(){return Err("Sys reactive fixed observation order differs".into())}let present=self.reader.with_sys_reactive_auto(visit)?;self.auto.set(Some(present));Ok(())}}
  let pages=Pages{reader:self,inputs,config,passes:std::cell::Cell::new(0),auto:std::cell::Cell::new(None)};
  let slot=self.new_pattern_slot().map_err(Failure::Operational)?;let patterns=ReaderPatternProvider{reader:self,slot:&slot};let data=captured_sys_reactive::collect_available_with_patterns(inputs,self.root(),&pages,config,self.budget(),globals,poll,&patterns)?;
  let expected=match pages.auto.get(){Some(true)=>3,Some(false)=>2,None=>return Err("Sys reactive fixed observation missing".into())};
  if pages.passes.get()!=expected{return Err("Sys reactive actual compound EOF incomplete".into())}
  self.require_policy_inputs(inputs)?;self.require_sys_discovery()?;self.checkpoint()?;
  self.budget.charge(std::mem::size_of::<WorkspaceSysReactiveWitness>()+std::mem::size_of::<WorkspaceCapture>()+2*std::mem::size_of::<usize>()).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;
  let witness=WorkspaceSysReactiveWitness{capture:Arc::downgrade(self.capture)};self.checkpoint()?;Ok((data,witness))
 }
}

//! Genuine top traversal adapters over ONE raw driver, notice owner and plan.
//! Local Rc loans never leave the producer worker or become source authority.
use super::{original_driver::{RawSourceDriver,DefinitionInstallation,NamedConditionResult,ConditionResult},original_plan_owner::OriginalPlanOwner,original_raw_inputs::OriginalRawNoticeSink,original_macro_source::OriginalMacroHost,original_ordinary_output::OriginalOrdinaryOutput,original_output_queue::OriginalOutputQueue,original_primary_controller::OriginalStreamControl,original_rich_notices::{OriginalRichNotices,OriginalNoticeSeverity as Severity},original_current_location::OriginalCurrentLocation as Location,original_define_history::{HistoryPurpose,OriginalDefineHistory},origin_raw_rows::OriginalRawOrigins,original_prepared_output::{OriginalProducedSpan,OriginalDeliveryFrontier},original_directive_dispatch::{DirectiveRequest,FailurePoint},original_conditional::{Action,Instruction,Outcome}};
use crate::{SourceProvider,SourceAcquisitionLease,InitialEnvironment,source_arena_credit::{SourceArenaWork,read_original_source_open_using},macro_expansion::{OriginalMacroRows as Rows,OriginalPagedMacroRows as PagedRows,OriginalMacroText as Text,OriginalMacroTextValue as TextValue,OriginalMacroToken as Token,OriginalMacroValue as Value,OriginalMacroOrigin as Origin,OriginalMacroNotice as MacroNotice,OriginalMacroDoc as Doc,original_format_using}};
use dm_syntax::{SettingAdmission,SettingRootLease,Span,SpanToken,NativeIndentNotice};
use std::{io,rc::Rc,cell::RefCell,path::{Path,PathBuf},sync::Arc,collections::BTreeMap};
fn poll(a:&SettingAdmission<'_>)->io::Result<()>{a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))}
struct Included{registered:super::original_file_path::OriginalFilePath,first:Option<Origin>,multiple:bool}
pub(super) struct State{
 // One exact acquisition loan for the most recently emitted occurrence.
 // The append-only plan remains its authority and funds the source backing.
 emission_lease:Option<(usize,SourceAcquisitionLease)>,
 pub(super) plan:OriginalPlanOwner,pub(super) notices:OriginalRichNotices,pub(super) history:OriginalDefineHistory,pub(super) conditionals:super::original_conditional_history::OriginalConditionalHistory,pub(super) origins:OriginalRawOrigins,pub(super) scripts:Rows<super::original_diagnostic_plan::OriginalScriptInclude>,ordinary:OriginalOrdinaryOutput,includes:PagedRows<Included>,include_ordinals:Rows<usize>,last_line:Option<(usize,usize)>,_control:SettingRootLease}
pub(super) type Shared=Rc<RefCell<State>>;
impl State{
 pub(super) fn new(project:&Path,provider:&dyn SourceProvider,defines:&BTreeMap<String,String>,a:&SettingAdmission<'_>,work:&dyn SourceArenaWork,history:HistoryPurpose)->io::Result<Shared>{poll(a)?;let control=a.reserve(std::mem::size_of::<RefCell<State>>()+2*std::mem::size_of::<usize>()).map_err(|e|a.take_operational_error().unwrap_or(e))?;Ok(Rc::new(RefCell::new(State{emission_lease:None,plan:OriginalPlanOwner::new(project,provider.initial_environment(),defines,provider.revision(),a)?,notices:OriginalRichNotices::new(a)?,history:OriginalDefineHistory::with_purpose(history,a)?,conditionals:super::original_conditional_history::OriginalConditionalHistory::new(a)?,origins:OriginalRawOrigins::new(a,work)?,scripts:Rows::new(a)?,ordinary:OriginalOrdinaryOutput::new(a)?,includes:PagedRows::new(a)?,include_ordinals:Rows::new(a)?,last_line:None,_control:control})))}
 /// Seed only after the real root acquisition was registered in this plan.
 /// A registered root is not yet an entry in old include_locations.
 pub(super) fn register_actual_root_semantic_file_using(&mut self,a:&SettingAdmission<'_>)->io::Result<()>{
  poll(a)?;
  if self.includes.len()!=0{return Err(io::ErrorKind::InvalidData.into())}
  let root=self.plan.occurrence(0)?;
  if root.parent.is_some(){return Err(io::ErrorKind::InvalidData.into())}
  let semantic=Arc::clone(&root.semantic_path);
  self.insert_include_using(0,Path::new(semantic.as_ref()),None,a)
 }
 // Path::cmp has the same component equality as the previous scan.
 // Sorted ordinal rows hold no second path, and never define semantic IDs.
 fn find_include_using(&self,path:&Path,a:&SettingAdmission<'_>)->io::Result<Result<usize,usize>>{
  poll(a)?;
  let found=self.include_ordinals.as_slice().binary_search_by(|&ordinal|{
   self.includes.get(ordinal).expect("indexed include ordinal").registered.path().cmp(path)
  });
  poll(a)?;
  Ok(found.map(|at|self.include_ordinals.as_slice()[at]))
 }
 fn insert_include_using(&mut self,sorted_at:usize,path:&Path,first:Option<Origin>,a:&SettingAdmission<'_>)->io::Result<()>{
  let ordinal=self.includes.len();
  let registered=super::original_file_path::OriginalFilePath::new(path,a)?;
  self.includes.push(Included{registered,first,multiple:false},a)?;
  if let Err(actual)=self.include_ordinals.insert(sorted_at,ordinal,a){
   // The failing append never leaves an unindexed registration.
   drop(self.includes.pop());
   return Err(actual)
  }
  Ok(())
 }
 fn semantic_file_id_using(&self,occurrence:usize,a:&SettingAdmission<'_>)->io::Result<u32>{
  poll(a)?;
  let semantic=self.plan.occurrence(occurrence)?.semantic_path.as_ref();
  let ordinal=self.find_include_using(Path::new(semantic),a)?
   .map_err(|_|io::Error::new(io::ErrorKind::Unsupported,"actual semantic file was not registered by a genuine source open"))?;
  u32::try_from(ordinal.checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?).map_err(|_|io::ErrorKind::OutOfMemory.into())
 }
 fn line(&mut self,origin:Origin){let key=(origin.occurrence,origin.line);if self.last_line!=Some(key){self.ordinary.clear_danger_for_actual_new_line();self.last_line=Some(key)}}
 fn message(&mut self,location:Location,severity:Severity,error_type:Option<&'static str>,a:&SettingAdmission<'_>,format:impl FnOnce(&mut Text,&SettingAdmission<'_>)->io::Result<()>)->io::Result<usize>{let mut text=Text::new(a)?;format(&mut text,a)?;self.notices.message_using(location,None,severity,error_type,text,a)}
 fn static_message(&mut self,location:Location,severity:Severity,error_type:Option<&'static str>,message:&str,a:&SettingAdmission<'_>)->io::Result<usize>{self.message(location,severity,error_type,a,|text,a|text.push_str(message,a))}
 pub(super) fn bind(&mut self,initial:&OriginalDeliveryFrontier,a:&SettingAdmission<'_>)->io::Result<()>{self.origins.bind_output_using(initial,a)}
}
pub(super) struct NoticeSink(pub(super) Shared);
impl OriginalRawNoticeSink for NoticeSink{
 fn before_logical_pull(&mut self,registration:super::original_prepared_output::OriginalNoticeRegistration,a:&SettingAdmission<'_>)->io::Result<()>{self.0.borrow_mut().notices.before_logical_pull(registration,a)}
 fn condition_identifier_recovery(&mut self,at:Origin,value:Option<dm_syntax::OriginalTokenValue<&str>>,a:&SettingAdmission<'_>)->io::Result<()>{self.0.borrow_mut().notices.condition_identifier_recovery(at,value,a)}

 fn condition_primitive(&mut self,at:Origin,kind:dm_syntax::OriginalInputNoticeKind,value:dm_syntax::OriginalTokenValue<&str>,a:&SettingAdmission<'_>)->io::Result<()>{self.0.borrow_mut().notices.condition_primitive(at,kind,value,a)}

 fn lexical(&mut self,frame:&super::OriginalLexicalFrameIdentity,occurrence:usize,point:super::original_raw_points::OriginalRawPoint,notice:super::original_raw_frame::OriginalRawNotice,a:&SettingAdmission<'_>)->io::Result<()>{self.0.borrow_mut().notices.lexical(frame,occurrence,point,notice,a)}
 fn numeric(&mut self,frame:&super::OriginalLexicalFrameIdentity,occurrence:usize,point:super::original_raw_points::OriginalRawPoint,at:dm_syntax::OriginalLexicalNoticePoint,notice:dm_syntax::numeric_form::OriginalNumberNotice<'_>,a:&SettingAdmission<'_>)->io::Result<()>{self.0.borrow_mut().notices.numeric(frame,occurrence,point,at,notice,a)}
}
pub(super) struct Host<'work>(pub(super) Shared,pub(super) &'work dyn SourceArenaWork);
impl OriginalMacroHost for Host<'_>{
 fn condition_debug_file_id_using(&mut self,occurrence:usize,a:&SettingAdmission<'_>)->io::Result<u32>{self.0.borrow().semantic_file_id_using(occurrence,a)}

 fn condition_file_exists_using(&mut self,at:Origin,passed:&str,provider:&dyn SourceProvider,a:&SettingAdmission<'_>)->io::Result<super::original_condition_value::FileExistsResult>{let candidate={let state=self.0.borrow();let file=&state.plan.occurrence(at.occurrence)?.path;let Some(parent)=file.parent()else{let mut message=Text::new(a)?;original_format_using(&mut message,a,|out|{use std::fmt::Write;write!(out,"fexists() file has no parent: {file:?}")})?;return Ok(super::original_condition_value::FileExistsResult::SourceFailure(message))};super::original_file_path::OriginalFilePath::joined(parent,passed,a)?};let exists=provider.path_presence_admitted(candidate.path(),self.1)?;Ok(super::original_condition_value::FileExistsResult::Value(exists))}

 fn take_docs_for_define(&mut self,a:&SettingAdmission<'_>)->io::Result<Rows<Doc<'static>>>{self.0.borrow_mut().ordinary.take_docs_for_define(a)}
 fn before_identifier(&mut self,name:&str,origin:Origin,queue:&mut OriginalOutputQueue<'static>,a:&SettingAdmission<'_>)->io::Result<()>{let mut state=self.0.borrow_mut();state.line(origin);state.ordinary.before_identifier(name,origin,queue,a)}
 fn ordinary_token(&mut self,token:Token<'static>,queue:&mut OriginalOutputQueue<'static>,a:&SettingAdmission<'_>)->io::Result<()>{let mut state=self.0.borrow_mut();state.line(token.origin);state.ordinary.ordinary_token(token,queue,a)}
 fn ordinary_token_or_direct(&mut self,token:Token<'static>,queue:&mut OriginalOutputQueue<'static>,a:&SettingAdmission<'_>)->io::Result<Option<(Token<'static>,super::original_output_trace::OriginalOutputTrace)>>{
  let mut state=self.0.borrow_mut();state.line(token.origin);state.ordinary.ordinary_direct_using(token,queue,a)
 }
 fn direct_noncall_output(&mut self,token:&Token<'static>,a:&SettingAdmission<'_>)->io::Result<()>{self.0.borrow_mut().ordinary.direct_noncall_output(token,a)}
 fn invocation(&mut self,_:&str,_:Origin,a:&SettingAdmission<'_>)->io::Result<()>{poll(a)}
 fn dynamic(&mut self,file:bool,invocation:Origin,current:Option<usize>,last:Option<Origin>,a:&SettingAdmission<'_>)->io::Result<Token<'static>>{
  poll(a)?;let value=if file{let state=self.0.borrow();let occurrence=current.ok_or_else(||io::Error::new(io::ErrorKind::Unsupported,"__FILE__ has no actual physical source frame"))?;let path=state.plan.occurrence(occurrence)?.path.as_path();let mut text=Text::new(a)?;original_format_using(&mut text,a,|out|{use std::fmt::Write;write!(out,"{}",path.display())})?;Value::String(TextValue::Owned(text))}else{Value::Int(last.ok_or_else(||io::Error::new(io::ErrorKind::Unsupported,"__LINE__ has no actual raw input location"))?.line as i32)};
  Ok(Token{value,origin:invocation,string_mode:dm_syntax::OriginalStringMode::Unknown,punctuation_close:false,lexical_frame:None,lexical_span:None,raw_spelling:None})
 }
}
pub(super) struct Control<'a>{pub(super) shared:Shared,pub(super) project:&'a Path,pub(super) work:&'a dyn SourceArenaWork,pub(super) max_raw_bytes:usize,pub(super) omissions:&'a super::GenerationOmissions}
impl Control<'_>{
 fn point(&self,point:FailurePoint,driver:&mut RawSourceDriver,provider:&dyn SourceProvider,notices:&mut dyn OriginalRawNoticeSink,host:&mut dyn OriginalMacroHost,a:&SettingAdmission<'_>)->io::Result<Location>{match point{FailurePoint::LastOuter=>driver.last_outer_using(a).map(Location::Expansion),FailurePoint::CurrentReader=>driver.current_location_using(provider,notices,host,a)}}
 fn macro_error(&self,notice:MacroNotice,driver:&mut RawSourceDriver,provider:&dyn SourceProvider,notices:&mut dyn OriginalRawNoticeSink,host:&mut dyn OriginalMacroHost,a:&SettingAdmission<'_>)->io::Result<()>{let location=driver.current_location_using(provider,notices,host,a)?;self.shared.borrow_mut().notices.macro_using(location,&notice.kind,a)?;Ok(())}
 fn include(&mut self,path:Token<'static>,driver:&mut RawSourceDriver,provider:&dyn SourceProvider,notices:&mut dyn OriginalRawNoticeSink,host:&mut dyn OriginalMacroHost,a:&SettingAdmission<'_>)->io::Result<()>{
  let Value::String(spelling)=&path.value else{return Err(io::ErrorKind::InvalidData.into())};
  // Borrow SAME actually active source path before allocating candidate paths.
  let parent=driver.current_physical_path_using(a)?.and_then(Path::parent).ok_or_else(||io::Error::new(io::ErrorKind::Unsupported,"active #include has no actual physical source parent"))?;
  let root=self.project.parent().ok_or(io::ErrorKind::InvalidInput)?;let spelling=spelling.get();let bytes=parent.as_os_str().len().checked_add(root.as_os_str().len()).and_then(|n|n.checked_add(spelling.len().checked_mul(3)?)).and_then(|n|n.checked_mul(4)).ok_or(io::ErrorKind::OutOfMemory)?;
  // These candidate paths are temporary even when an include succeeds.
  // Declare their funding first so all physical buffers drop before refund.
  let _candidate_credit=a.reserve(bytes).map_err(|error|a.take_operational_error().unwrap_or(error))?;
  let requested=PathBuf::from(spelling.replace('\\',"/"));let candidates=[parent.join(&requested),root.join(&requested)];
  for candidate in candidates{
   // Exact metadata-only exists semantics precedes extension classification.
   if !provider.path_presence_admitted(&candidate,self.work)?{if self.omissions.paths().any(|path|path==super::canonical_path(&candidate)){self.shared.borrow_mut().plan.add_omitted_using(&candidate,path.origin.occurrence,path.origin.physical,path.origin.line,a)?;return Ok(())}continue}
   let last=driver.last_outer_using(a)?;
   match candidate.extension().and_then(|s|s.to_str()){
    Some("dmm")=>{self.shared.borrow_mut().plan.add_non_text_using(&candidate,path.origin.occurrence,path.origin.physical,path.origin.line,super::NonTextKind::Map,a)?;return Ok(())},
    Some("dmf")=>{self.shared.borrow_mut().plan.add_non_text_using(&candidate,path.origin.occurrence,path.origin.physical,path.origin.line,super::NonTextKind::Skin,a)?;return Ok(())},
    Some("dms")=>{let selected=super::original_file_path::OriginalFilePath::new(&candidate,a)?;let mut state=self.shared.borrow_mut();state.plan.add_dependency_using(&candidate,a)?;state.scripts.push(super::original_diagnostic_plan::OriginalScriptInclude{path:selected,at:path.origin},a)?;return Ok(())},
    Some("dm"|"dme")=>(),
    extension=>{let mut state=self.shared.borrow_mut();state.message(Location::Expansion(last),Severity::Error,None,a,|text,a|match extension{Some(ext)=>original_format_using(text,a,|out|{use std::fmt::Write;write!(out,"unknown extension {ext:?}")}),None=>text.push_str("filename has no extension",a)})?;return Ok(())}
   }
   let registered=candidate.strip_prefix(root).unwrap_or(&candidate);let mut duplicate=None;
   let outcome=read_original_source_open_using(provider,&candidate,self.max_raw_bytes,self.work,&mut||{
    let mut state=self.shared.borrow_mut();
    match state.find_include_using(registered,a)?{
     Ok(index)=>{
      let previous=state.includes.get_mut(index).expect("issued include ordinal");
      if let Some(first)=previous.first{
       if !previous.multiple{duplicate=Some(first);return Ok(crate::OriginalRawOpenDecision::Suppress)}
      }else{previous.first=Some(last)}
     }
     Err(sorted_at)=>state.insert_include_using(sorted_at,registered,Some(last),a)?,
    }
    Ok(crate::OriginalRawOpenDecision::Read)
   })?;
   match outcome{
    crate::OriginalRawReadOutcome::Suppressed=>{let mut state=self.shared.borrow_mut();let at=state.message(Location::Expansion(last),Severity::Warning,Some("duplicate_include"),a,|text,a|original_format_using(text,a,|out|{use std::fmt::Write;write!(out,"duplicate #include {candidate:?}")}))?;let mut message=Text::new(a)?;message.push_str("previously included here",a)?;state.notices.note_using(at,Location::Expansion(duplicate.ok_or(io::ErrorKind::InvalidData)?),message,a)?;},
    crate::OriginalRawReadOutcome::SourceOpenFailed(error)=>{let mut state=self.shared.borrow_mut();let at=state.message(Location::Expansion(last),Severity::Error,None,a,|text,a|original_format_using(text,a,|out|{use std::fmt::Write;write!(out,"failed to open file: #include {candidate:?}")}))?;let mut cause=Text::new(a)?;original_format_using(&mut cause,a,|out|{use std::fmt::Write;write!(out,"{error}")})?;state.notices.note_using(at,Location::Expansion(last),cause,a)?;},
    crate::OriginalRawReadOutcome::Acquired(lease)=>{let occurrence=self.shared.borrow_mut().plan.register_opened_using(&candidate,registered,lease.clone(),Some(path.origin.occurrence),path.origin.physical,path.origin.line,a)?;driver.include_phantom_newline_using(a)?;driver.push_opened_at(provider,lease,occurrence,&candidate,a)?;},
    crate::OriginalRawReadOutcome::Absent=>return Err(io::Error::new(io::ErrorKind::InvalidData,"actual opened-reader route returned unauthenticated absence"))
   }return Ok(())
  }
  let last=driver.last_outer_using(a)?;self.shared.borrow_mut().message(Location::Expansion(last),Severity::Error,None,a,|text,a|original_format_using(text,a,|out|{use std::fmt::Write;write!(out,"failed to find #include {requested:?}")}))?;Ok(())
 }
}
impl OriginalStreamControl for Control<'_>{
 fn batch_token_pages(&self,owner:&super::original_prepared_output::OriginalOutputIdentity,
  end:usize,count:usize,a:&SettingAdmission<'_>)
  ->io::Result<[Option<super::original_prepared_output::OriginalBatchTokenPage>;2]>{
   self.shared.borrow_mut().origins.batch_token_pages(owner,end,count,a,self.work)
 }
 fn default_semicolon(&mut self,produced:OriginalProducedSpan<'_>,driver:&mut RawSourceDriver,a:&SettingAdmission<'_>)->io::Result<()>{let trace=driver.take_delivery_trace_using(a)?;if trace.depth()!=0{return Err(io::ErrorKind::InvalidData.into())}self.shared.borrow_mut().origins.append_default_semicolon_using(produced,a)}

 fn directive(&mut self,hash:Origin,driver:&mut RawSourceDriver,provider:&dyn SourceProvider,notices:&mut dyn OriginalRawNoticeSink,host:&mut dyn OriginalMacroHost,a:&SettingAdmission<'_>)->io::Result<()>{
  let _stack=a.evaluation_frame()?;
  let request=driver.directive_request_using(provider,notices,host,a,&mut|_,origin,message|{self.shared.borrow_mut().static_message(Location::Expansion(origin),Severity::Hint,None,message,a)?;Ok(())})?;let mut success=true;
  match request{
   DirectiveRequest::Ignored=>(),DirectiveRequest::Include{path}=>self.include(path,driver,provider,notices,host,a)?,
   DirectiveRequest::SourceFailure{message,point}=>{let location=self.point(point,driver,provider,notices,host,a)?;self.shared.borrow_mut().notices.message_using(location,None,Severity::Error,None,message,a)?;success=false;},
   DirectiveRequest::Message{warning,text}=>{let Value::String(message)=&text.value else{return Err(io::ErrorKind::InvalidData.into())};let last=driver.last_outer_using(a)?;self.shared.borrow_mut().message(Location::Expansion(last),if warning{Severity::Warning}else{Severity::Error},None,a,|out,a|{out.push_str(if warning{"#warn "}else{"#error "},a)?;out.push_str(message.get().trim_end_matches(['\r','\n']),a)})?;},
   DirectiveRequest::Pragma{name}=>{if matches!(&name.value,Value::Ident{spelling,..}if spelling.get()=="multiple"){let mut state=self.shared.borrow_mut();let semantic=Arc::clone(&state.plan.occurrence(name.origin.occurrence)?.semantic_path);let index=state.find_include_using(Path::new(semantic.as_ref()),a)?.map_err(|_|io::Error::new(io::ErrorKind::InvalidData,"actual pragma file was not registered by its source open"))?;state.includes.get_mut(index).expect("issued include ordinal").multiple=true;}},
   DirectiveRequest::Undef{name}=>{let Value::Ident{spelling,..}=&name.value else{return Err(io::ErrorKind::InvalidData.into())};let name_text=spelling.get();let removed=driver.undefine_using(name_text,a)?;let last=driver.last_outer_using(a)?;if let Some(actual)=removed.removed{self.shared.borrow_mut().history.record_undef_using(name_text,actual,last,a)?;}else{self.shared.borrow_mut().message(Location::Expansion(name.origin),Severity::Warning,Some("macro_undefined_no_definition"),a,|text,a|{text.push_str("macro undefined while not defined: ",a)?;text.push_str(name_text,a)})?;}},
   DirectiveRequest::Define(defined)=>{let name=match &defined.name.value{Value::Ident{spelling,..}=>{let mut text=Text::new(a)?;text.push_str(spelling.get(),a)?;text},_=>return Err(io::ErrorKind::InvalidData.into())};let origin=self.shared.borrow().plan.definition_using(defined.name.origin,driver,provider,a)?;let install=driver.install_defined_using(defined,provider,Some(origin),a)?;if let DefinitionInstallation::Installed{origin,replaced:true,previous_name,warn_redefinition:true}=install{let mut state=self.shared.borrow_mut();let at=state.message(Location::Expansion(origin),Severity::Warning,Some("macro_redefined"),a,|text,a|{text.push_str("macro redefined: ",a)?;text.push_str(name.as_str(),a)})?;let mut message=Text::new(a)?;message.push_str("previous definition of ",a)?;message.push_str(name.as_str(),a)?;state.notices.note_using(at,previous_name.map(Location::Expansion).unwrap_or(Location::Builtins),message,a)?;}},
   DirectiveRequest::Conditional(directive)=>{match driver.begin_conditional_using(directive,hash,a)?{
    Action::Done{history}=>{if let Some(actual)=history{self.shared.borrow_mut().conditionals.record_using(actual,a)?}},Action::SourceFailure{origin,message}=>{self.shared.borrow_mut().static_message(Location::Expansion(origin),Severity::Error,None,message,a)?;success=false;},
    Action::Evaluate{history,pending}=>{if let Some(actual)=history{self.shared.borrow_mut().conditionals.record_using(actual,a)?}match pending.instruction(){Instruction::DefinedName{..}=>if let NamedConditionResult::SourceFailure(message)=driver.finish_named_condition_using(pending,provider,notices,host,a)?{let location=driver.current_location_using(provider,notices,host,a)?;self.shared.borrow_mut().notices.message_using(location,None,Severity::Error,None,message,a)?;success=false},Instruction::Expression=>{let evaluated=driver.evaluate_condition_with_directives_using(hash,provider,notices,host,a,&mut|driver,notice|{let mut local_sink=NoticeSink(Rc::clone(&self.shared));let mut local_host=Host(Rc::clone(&self.shared),self.work);self.macro_error(notice,driver,provider,&mut local_sink,&mut local_host,a)},&mut|driver,nested_hash|{let mut local_sink=NoticeSink(Rc::clone(&self.shared));let mut local_host=Host(Rc::clone(&self.shared),self.work);let mut nested=Control{shared:Rc::clone(&self.shared),project:self.project,work:self.work,max_raw_bytes:self.max_raw_bytes,omissions:self.omissions};nested.directive(nested_hash,driver,provider,&mut local_sink,&mut local_host,a)})?;let outcome=match evaluated.outcome{ConditionResult::Value(value)=>Outcome::Value(value),ConditionResult::DisabledAfterExpansion=>Outcome::DisabledAfterExpansion,ConditionResult::SourceFailure(message)=>{self.shared.borrow_mut().notices.message_using(Location::Expansion(evaluated.failure_at.unwrap_or(evaluated.last_input)),None,Severity::Error,None,message,a)?;Outcome::ExpressionSourceFailure},ConditionResult::SourceWarning(message)=>{self.shared.borrow_mut().notices.message_using(Location::Expansion(evaluated.failure_at.unwrap_or(evaluated.last_input)),None,Severity::Warning,None,message,a)?;Outcome::ExpressionSourceFailure}};driver.finish_conditional_using(pending,outcome,evaluated.last_input,a)?;}}}
   }},
  }driver.finish_directive_using(success,provider,notices,host,a)
 }
 fn macro_notice(&mut self,notice:MacroNotice,driver:&mut RawSourceDriver,provider:&dyn SourceProvider,notices:&mut dyn OriginalRawNoticeSink,host:&mut dyn OriginalMacroHost,a:&SettingAdmission<'_>)->io::Result<()>{self.macro_error(notice,driver,provider,notices,host,a)}
 fn conditional_eof(&mut self,actual:super::original_conditional::Unterminated,a:&SettingAdmission<'_>)->io::Result<()>{self.shared.borrow_mut().conditionals.record_using(actual.history,a)?;self.shared.borrow_mut().static_message(Location::Expansion(actual.origin),Severity::Error,None,actual.message,a)?;Ok(())}
 fn indent_notice(&mut self,kind:NativeIndentNotice,location:Option<Origin>,a:&SettingAdmission<'_>)->io::Result<()>{self.shared.borrow_mut().message(location.map(Location::Expansion).unwrap_or(Location::Default),Severity::Error,None,a,|text,a|original_format_using(text,a,|out|kind.write_message(out)))?;Ok(())}
 fn emitted(&mut self,actual:&Token<'static>,token:SpanToken,cover:Span,produced:OriginalProducedSpan<'_>,driver:&mut RawSourceDriver,provider:&dyn SourceProvider,a:&SettingAdmission<'_>)->io::Result<()>{if token!=produced.token()||cover!=produced.cover(){return Err(io::ErrorKind::InvalidInput.into())}let saved=driver.take_delivery_trace_using(a)?;
 #[cfg(feature="original-fill-sample")]
 let _sample=super::original_fill_sample::scope(super::original_fill_sample::Bucket::Emit);
 let mut state=self.shared.borrow_mut();
 let State{plan,origins,emission_lease,..}=&mut *state;
 let occurrence=actual.origin.occurrence;
 if emission_lease.as_ref().is_none_or(|(previous,_)|*previous!=occurrence) {
  *emission_lease=Some((occurrence,plan.lease(occurrence)?));
 }
 let lease=&emission_lease.as_ref().expect("actual emitted occurrence has a lease").1;
 let row=driver.observe_physical_row_using(actual.origin,lease,provider,None,a)?;
 let region=plan.region_for_emission_using(occurrence,row.row().decoded,a)?;
 let (path,trace)=original_fill_bucket!(Macro,plan.emission_owners_using(occurrence,&saved,driver,provider,Some(&row),a))?;
 origins.append_produced_using(actual,produced,region,path,trace,lease,provider,driver,Some(&row),a,self.work)}
}

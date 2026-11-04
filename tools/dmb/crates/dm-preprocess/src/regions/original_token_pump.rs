//! Actual outer raw-token cadence over the SAME macro cursor/output queue.
//! Directive execution remains with DirectivePass; no source/model/EOF grant.
use super::{original_macro_source::OriginalBorrowedMacroSource,original_conditional::{self,Frame}};
use crate::macro_expansion::{OriginalMacroCursor as Cursor,OriginalMacroRawStep as RawStep,OriginalMacroStep as Step,OriginalMacroOuterStep as OuterStep,OriginalMacroToken as Token,OriginalMacroOrigin as Origin,OriginalMacroNotice as Notice,OriginalMacroValue as Value};
use dm_syntax::SettingAdmission;use std::io;
pub(super) enum PumpEvent{Token(Token<'static>),Directive{hash:Origin},Notice(Notice),NeedInput,ActualInputEnd,Stopped}
pub(super) struct OriginalTokenPump{cursor:Cursor<'static>,outer:bool,directive:bool,nested_directives:usize,failed:bool,stopped:bool,last_outer:Option<Origin>,delivery:Option<super::original_output_trace::OriginalOutputTrace>}
impl OriginalTokenPump{
 pub(super) fn new(a:&SettingAdmission<'_>)->io::Result<Self>{Ok(Self{cursor:Cursor::new(a)?,outer:false,directive:false,nested_directives:0,failed:false,stopped:false,last_outer:None,delivery:None})}
 pub(super) fn expansion_depth(&self)->usize{self.cursor.expansion_depth()}
 pub(super) fn stop(&mut self){self.stopped=true;self.cursor.stop()}
 pub(super) fn take_delivery_trace(&mut self)->io::Result<super::original_output_trace::OriginalOutputTrace>{self.delivery.take().ok_or_else(||io::ErrorKind::InvalidInput.into())}
 pub(super) fn last_outer(&self)->Option<Origin>{self.last_outer}
 /// During conditional pumping, the actual outer raw reader updates this SAME
 /// location. Ordinary raw arguments do not update old last_input_loc.
 pub(super) fn record_conditional_outer(&mut self,actual:Origin){self.last_outer=Some(actual)}
 /// Location query only: SAME paused cursor without granting directive entry.
 /// Raw driver immediately loans it solely to HasLocation and returns it.
 pub(super) fn cursor_for_location(&mut self)->io::Result<&mut Cursor<'static>>{if self.failed||self.stopped{return Err(io::ErrorKind::InvalidInput.into())}Ok(&mut self.cursor)}
 pub(super) fn cursor_for_directive(&mut self)->io::Result<&mut Cursor<'static>>{if self.failed||self.stopped||!self.directive{return Err(io::ErrorKind::InvalidInput.into())}Ok(&mut self.cursor)}
 /// Only a completed actual directive records success. An error recovery emits
 /// no synthetic newline, matching real_next's early error return. A successful
 /// branch's newline is generated DATA, not physical source EOF/authority.
 /// Enter only from the SAME condition pump's actual Hash event. Finishing
 /// that directive releases one nested continuation, not its enclosing #if.
 pub(super) fn begin_nested_directive_using(&mut self,a:&SettingAdmission<'_>)->io::Result<()>{a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;if self.failed||self.stopped||!self.directive{return Err(io::ErrorKind::InvalidInput.into())}self.nested_directives=self.nested_directives.checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?;Ok(())}
 pub(super) fn finish_directive(&mut self,success:bool,source:&mut OriginalBorrowedMacroSource<'_>,a:&SettingAdmission<'_>)->io::Result<()>{
  if self.failed||self.stopped||!self.directive{return Err(io::ErrorKind::InvalidInput.into())}
  let result=(||{if success{let origin=self.last_outer.ok_or(io::ErrorKind::InvalidData)?;source.queue.push(Token{string_mode:dm_syntax::OriginalStringMode::Unknown,punctuation_close:false,lexical_frame:None,lexical_span:None,raw_spelling:None,value:Value::Punct("\n"),origin},a)?;}Ok(())})();if result.is_err(){self.failed=true}else if self.nested_directives!=0{self.nested_directives-=1}else{self.directive=false}result
 }
 pub(super) fn next_using(&mut self,source:&mut OriginalBorrowedMacroSource<'_>,conditionals:&[Frame],a:&SettingAdmission<'_>)->io::Result<PumpEvent>{
  if self.failed||self.directive{return Err(io::Error::new(io::ErrorKind::InvalidInput,"token pump is failed or awaiting its actual directive completion"))}if self.stopped{return Ok(PumpEvent::Stopped)}let result=self.next_inner(source,conditionals,a);if result.is_err(){self.failed=true}result
 }
 fn next_inner(&mut self,source:&mut OriginalBorrowedMacroSource<'_>,conditionals:&[Frame],a:&SettingAdmission<'_>)->io::Result<PumpEvent>{
  loop{
   a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;
   if let Some((token,trace))=source.queue.pop_with_trace()?{self.delivery=Some(trace);return Ok(PumpEvent::Token(token))}
   if self.outer{
    match self.cursor.next_outer_using(source,a)?{
     OuterStep::Boundary=>{self.outer=false;continue},
     OuterStep::Output(Step::Token(token))=>{source.queue.push(token,a)?;continue},
     OuterStep::Output(Step::Notice(notice))=>return Ok(PumpEvent::Notice(notice)),
     OuterStep::Output(Step::NeedInput)=>return Ok(PumpEvent::NeedInput),
     OuterStep::Output(Step::Stopped)=>return Ok(PumpEvent::Stopped),
     OuterStep::Output(Step::End|Step::Boundary)=>return Err(io::Error::new(io::ErrorKind::InvalidData,"outer macro operation returned an unissued completion")),
    }
   }
   let token=match self.cursor.next_undispatched_using(source,a)?{RawStep::Token(token)=>token,RawStep::NeedInput=>return Ok(PumpEvent::NeedInput),RawStep::End=>return Ok(PumpEvent::ActualInputEnd)};
   self.last_outer=Some(token.origin);
   // Hash dispatch precedes disabled filtering, as in the unique old real_next.
   // Direct noncall '#' output is drained above and never redispatched here.
   if matches!(token.value,Value::Punct("#")){self.directive=true;return Ok(PumpEvent::Directive{hash:token.origin})}
   if original_conditional::is_disabled_using(conditionals,a)?{continue}
   if !matches!(token.value,Value::Ident{..}){source.host.ordinary_token(token,source.queue,a)?;continue}
   self.cursor.begin_outer_using(token,a)?;self.outer=true;
  }
 }
}

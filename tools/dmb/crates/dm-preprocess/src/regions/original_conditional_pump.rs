//! Exact old evaluate_inner input cadence over the SAME macro/source cursor.
//! This only fills the ACTUAL undrained output queue. Parse/evaluate happens
//! after a genuine outer raw newline/End and the subsequent disabled check.
use super::original_macro_source::OriginalBorrowedMacroSource;
use crate::macro_expansion::{OriginalMacroCursor as Cursor,OriginalMacroRawStep as RawStep,OriginalMacroOuterStep as OuterStep,OriginalMacroStep as Step,OriginalMacroValue as Value,OriginalMacroOrigin as Origin,OriginalMacroNotice as Notice};
use dm_syntax::SettingAdmission;use std::io;
pub(super) enum ConditionPumpProgress{Complete,NeedInput,Directive{hash:Origin},Notice(Notice)}
/// Issued only by the SAME pump after its actual outer LF/raw End branch.
/// It closes an expression queue, never a physical source or model.
pub(super) struct OriginalCompletedCondition{last_input:Origin}
impl OriginalCompletedCondition{pub(super) fn last_input(&self)->Origin{self.last_input}}
pub(super) struct OriginalConditionPump{outer:bool,complete:bool,failed:bool,last_input:Origin}
impl OriginalConditionPump{
 pub(super) fn new(actual_hash:Origin)->Self{Self{outer:false,complete:false,failed:false,last_input:actual_hash}}
 pub(super) fn last_input(&self)->Origin{self.last_input}
 pub(super) fn into_completed(self)->io::Result<OriginalCompletedCondition>{if self.failed||!self.complete{return Err(io::Error::new(io::ErrorKind::InvalidInput,"condition pump has no genuine completed outer boundary"))}Ok(OriginalCompletedCondition{last_input:self.last_input})}

 pub(super) fn advance(&mut self,cursor:&mut Cursor<'static>,source:&mut OriginalBorrowedMacroSource<'_>,a:&SettingAdmission<'_>)->io::Result<ConditionPumpProgress>{
  if self.failed||self.complete{return Err(io::ErrorKind::InvalidInput.into())}let result=self.advance_inner(cursor,source,a);if result.is_err(){self.failed=true}result
 }
 fn advance_inner(&mut self,cursor:&mut Cursor<'static>,source:&mut OriginalBorrowedMacroSource<'_>,a:&SettingAdmission<'_>)->io::Result<ConditionPumpProgress>{
  loop{a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;
   if self.outer{match cursor.next_outer_using(source,a)?{
    OuterStep::Boundary=>{self.outer=false;continue},
    OuterStep::Output(Step::Token(token))=>{source.queue.push(token,a)?;continue},
    OuterStep::Output(Step::Notice(notice))=>return Ok(ConditionPumpProgress::Notice(notice)),
    OuterStep::Output(Step::NeedInput)=>return Ok(ConditionPumpProgress::NeedInput),
    OuterStep::Output(Step::End|Step::Stopped|Step::Boundary)=>return Err(io::Error::new(io::ErrorKind::InvalidData,"conditional outer macro step did not issue a real boundary")),
   }}
   let token=match cursor.next_undispatched_using(source,a)?{RawStep::NeedInput=>return Ok(ConditionPumpProgress::NeedInput),RawStep::End=>{self.complete=true;return Ok(ConditionPumpProgress::Complete)},RawStep::Token(token)=>token};
   self.last_input=token.origin;
   // ONLY this outer raw read ends the pump. A noncall's direct queued LF
   // does not; a replacement LF is left to this next outer raw iteration.
   if matches!(token.value,Value::Punct("\n")){self.complete=true;return Ok(ConditionPumpProgress::Complete)}
   if matches!(token.value,Value::Punct("#")){return Ok(ConditionPumpProgress::Directive{hash:token.origin})}
   // inside_condition=true deliberately bypasses disabled filtering. Actual
   // macro errors therefore still occur under an inactive parent conditional.
   if matches!(token.value,Value::Ident{..}){cursor.begin_outer_using(token,a)?;self.outer=true;}
   else{source.host.ordinary_token(token,source.queue,a)?;}
  }
 }
}

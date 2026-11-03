//! The actual completed preprocessor queue lent to the SAME native Pratt.
//! Owned token/value/credit moves once; there is no arena relex or display feed.
use super::{original_output_queue::OriginalOutputQueue,original_conditional_pump::OriginalCompletedCondition,original_native_projection::project_native_token_using};
use crate::{SourceProvider,macro_expansion::{OriginalMacroRows as Rows,OriginalMacroToken as ActualToken}};
use dm_syntax::{SettingAdmission,SettingRootLease,Span,Token,NativeExpressionTokenDemand,NativeExpressionTokenOccurrence,OriginalLiteralData,OriginalTokenValue};
use std::{io,cell::Cell};
struct Occurrence{actual:ActualToken<'static>,span:Span,literal:Option<OriginalLiteralData>,credit:Option<SettingRootLease>}
pub(super) struct OriginalConditionTokens<'a,'budget>{queue:&'a mut OriginalOutputQueue<'static>,provider:&'a dyn SourceProvider,a:&'a SettingAdmission<'budget>,rows:Rows<Occurrence>,next_offset:usize,begun:bool,failed:Cell<bool>,completion:OriginalCompletedCondition}
impl<'a,'budget> OriginalConditionTokens<'a,'budget>{
 pub(super) fn new(queue:&'a mut OriginalOutputQueue<'static>,provider:&'a dyn SourceProvider,a:&'a SettingAdmission<'budget>,completion:OriginalCompletedCondition)->io::Result<Self>{Ok(Self{queue,provider,a,rows:Rows::new(a)?,next_offset:0,begun:false,failed:Cell::new(false),completion})}
 pub(super) fn last_input(&self)->crate::macro_expansion::OriginalMacroOrigin{self.completion.last_input()}
 fn check(&self)->io::Result<()>{if self.failed.get(){return Err(io::ErrorKind::InvalidInput.into())}let result=self.a.checkpoint().map_err(|e|self.a.take_operational_error().unwrap_or(e));if result.is_err(){self.failed.set(true)}result}
 fn row(&self,occurrence:NativeExpressionTokenOccurrence)->io::Result<&Occurrence>{self.check()?;let row=self.rows.as_slice().get(occurrence.ordinal()).ok_or(io::ErrorKind::InvalidInput)?;if row.span!=occurrence.span(){return Err(io::ErrorKind::InvalidInput.into())}Ok(row)}
 fn next_inner(&mut self)->io::Result<Option<Token>>{
  self.check()?;if !self.begun{return Err(io::ErrorKind::InvalidInput.into())}let Some(actual)=self.queue.pop()?else{return Ok(None)};
  if actual.punctuation_close{return Err(io::Error::new(io::ErrorKind::Unsupported,"Original conditional CloseColon native grammar transport is unissued"))}
  let projection=project_native_token_using(&actual,self.provider,self.a)?;let span=Span::new(self.next_offset,self.next_offset.checked_add(projection.spelling.as_str().len()).ok_or(io::ErrorKind::OutOfMemory)?);
  // Gaps preserve distinct actual token boundaries; a genuine multi-character
  // punctuation already remains ONE token. No following input is requested.
  self.next_offset=span.end.checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?;
  // Keep the physical spelling inside its allocation-owning Text until every
  // fallible roster operation is complete. A failed push must not refund its
  // credit while a separately constructed Token still owns the String.
  let slot=self.rows.len();self.rows.push(Occurrence{actual,span,literal:projection.literal,credit:None},self.a)?;
  let(text,credit)=projection.spelling.into_parts();self.rows.as_mut_slice()[slot].credit=Some(credit);Ok(Some(Token{kind:projection.kind,span,text}))
 }
}
impl NativeExpressionTokenDemand for OriginalConditionTokens<'_,'_>{
 fn begin_expression(&mut self)->io::Result<()>{self.check()?;if self.begun{self.failed.set(true);return Err(io::ErrorKind::InvalidInput.into())}self.begun=true;Ok(())}
 fn next_token(&mut self)->io::Result<Option<Token>>{let result=self.next_inner();if result.is_err(){self.failed.set(true)}result}
 fn take_token_credit(&mut self,occurrence:NativeExpressionTokenOccurrence)->io::Result<Option<SettingRootLease>>{self.row(occurrence)?;self.rows.as_mut_slice()[occurrence.ordinal()].credit.take().ok_or_else(||io::ErrorKind::InvalidInput.into()).map(Some)}
 fn original_value(&self,occurrence:NativeExpressionTokenOccurrence)->io::Result<Option<OriginalTokenValue<&str>>>{Ok(Some(self.row(occurrence)?.actual.value.map_text(|text|text.get())))}
 fn original_literal_data(&self,occurrence:NativeExpressionTokenOccurrence)->io::Result<Option<&OriginalLiteralData>>{Ok(self.row(occurrence)?.literal.as_ref())}
 fn requires_original_values(&self)->bool{true}
}

// The old condition parser takes output.drain(..): tokens it did not request
// after a syntax error still retire here, while each real buffer stays funded.
impl Drop for OriginalConditionTokens<'_,'_>{fn drop(&mut self){self.queue.discard_values();}}

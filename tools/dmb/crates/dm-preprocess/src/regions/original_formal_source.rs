//! A scoped formal loan over the SAME actual driver/primary owner. No source
//! copies, parser replay, external occurrence grants or independent token store.
use super::{original_final_output::OriginalEmittedToken,OriginalFormalTokenStream};
use crate::macro_expansion::OriginalMacroRows as Rows;
use dm_syntax::{OriginalPrimaryDemand,OriginalPrimaryLiveHeader,NativeExpressionTokenDemand,NativeExpressionTokenOccurrence,OriginalLiteralData,SettingRootLease,SettingAdmission,Span,Token};use std::io;
/// Implemented by the real directive/macro/output owner. A pull runs that SAME
/// owner once, appends its genuine token to primary, and moves only scratch.
pub(super) trait OriginalFormalProducer{
 fn pull_formal_token(&mut self,primary:&mut OriginalPrimaryDemand<'_,'_,'_>)->io::Result<Option<OriginalEmittedToken>>;
 fn current_source(&self)->&str;
}
struct Pull{kind:dm_syntax::TokenKind,span:Span,credit:Option<SettingRootLease>,original:crate::macro_expansion::OriginalMacroToken<'static>}
pub(super) struct OriginalLiveFormalSource<'a,'primary,'observer,'budget,P:OriginalFormalProducer>{
 pulls:Rows<Pull>,expression_start:usize,failed:std::cell::Cell<bool>,live:OriginalPrimaryLiveHeader,
 producer:&'a mut P,primary:&'a mut OriginalPrimaryDemand<'primary,'observer,'budget>,a:&'a SettingAdmission<'budget>,
}
impl<'a,'primary,'observer,'budget,P:OriginalFormalProducer> OriginalLiveFormalSource<'a,'primary,'observer,'budget,P>{
 pub(super) fn new(producer:&'a mut P,primary:&'a mut OriginalPrimaryDemand<'primary,'observer,'budget>,live:OriginalPrimaryLiveHeader,a:&'a SettingAdmission<'budget>)->io::Result<Self>{primary.validate_live_header(&live)?;Ok(Self{pulls:Rows::new(a)?,expression_start:0,failed:std::cell::Cell::new(false),live,producer,primary,a})}
 fn check(&self)->io::Result<()>{if self.failed.get(){return Err(io::ErrorKind::InvalidInput.into())}let result=(||{self.a.checkpoint().map_err(|e|self.a.take_operational_error().unwrap_or(e))?;self.primary.validate_live_header(&self.live)})();if result.is_err(){self.failed.set(true)}result}
 fn pull(&mut self)->io::Result<Option<Token>>{
  self.check()?;let result=(||{let Some(emitted)=self.producer.pull_formal_token(self.primary)?else{return Ok(None)};
   let span=emitted.token.span;if span.start<self.live.argument_start()||span.end>self.primary.consumed_frontier().max(self.producer.current_source().len())||self.primary.span_tokens().last().is_none_or(|actual|actual.span!=span){return Err(io::ErrorKind::InvalidInput.into())}
   self.pulls.push(Pull{kind:emitted.token.kind,span,credit:Some(emitted.credit),original:emitted.original.ok_or_else(||io::Error::new(io::ErrorKind::InvalidData,"genuine formal token lost its actual typed value owner"))?},self.a)?;Ok(Some(emitted.token))})();if result.is_err(){self.failed.set(true)}result
 }
 fn row(&self,occurrence:NativeExpressionTokenOccurrence)->io::Result<&Pull>{self.check()?;let at=self.expression_start.checked_add(occurrence.ordinal()).ok_or(io::ErrorKind::InvalidInput)?;let row=self.pulls.as_slice().get(at).ok_or(io::ErrorKind::InvalidInput)?;if row.span!=occurrence.span(){return Err(io::ErrorKind::InvalidInput.into())}Ok(row)}
}
impl<P:OriginalFormalProducer> NativeExpressionTokenDemand for OriginalLiveFormalSource<'_,'_,'_,'_,P>{
 fn begin_expression(&mut self)->io::Result<()>{self.check()?;self.expression_start=self.pulls.len();Ok(())}
 fn next_token(&mut self)->io::Result<Option<Token>>{self.pull()}
 fn take_token_credit(&mut self,occurrence:NativeExpressionTokenOccurrence)->io::Result<Option<SettingRootLease>>{self.row(occurrence)?;let at=self.expression_start.checked_add(occurrence.ordinal()).ok_or(io::ErrorKind::InvalidInput)?;let credit=self.pulls.as_mut_slice()[at].credit.take().ok_or(io::ErrorKind::InvalidInput)?;Ok(Some(credit))}
 fn original_close_colon(&self,occurrence:NativeExpressionTokenOccurrence)->io::Result<Option<bool>>{let row=self.row(occurrence)?;Ok(matches!(row.original.value,dm_syntax::OriginalTokenValue::Punct(":" )).then_some(row.original.punctuation_close))}
 fn original_template_source(&self,span:Span)->io::Result<Option<&str>>{self.check()?;if span.start<span.end&&self.pulls.as_slice().iter().any(|row|row.span.start==span.start)&&self.pulls.as_slice().last().is_some_and(|row|row.span.end>=span.end){return self.producer.current_source().get(span.range()).map(Some).ok_or_else(||io::ErrorKind::InvalidInput.into())}Err(io::ErrorKind::InvalidInput.into())}
 fn original_value(&self,occurrence:NativeExpressionTokenOccurrence)->io::Result<Option<dm_syntax::OriginalTokenValue<&str>>>{Ok(Some(self.row(occurrence)?.original.value.map_text(|text|text.get())))}
 fn original_literal_data(&self,occurrence:NativeExpressionTokenOccurrence)->io::Result<Option<&OriginalLiteralData>>{let span=self.row(occurrence)?.span;self.primary.original_literal_for_span(span)}
 fn requires_original_values(&self)->bool{true}
}
impl<P:OriginalFormalProducer> OriginalFormalTokenStream for OriginalLiveFormalSource<'_,'_,'_,'_,P>{
 fn next_header_token(&mut self)->io::Result<Option<Token>>{self.pull()}
 fn current_header_value(&self,token:dm_syntax::SpanToken)->io::Result<dm_syntax::OriginalTokenValue<&str>>{
  self.check()?;let current=self.pulls.as_slice().last().ok_or(io::ErrorKind::InvalidInput)?;if current.kind!=token.kind||current.span!=token.span||self.primary.span_tokens().last()!=Some(&token){return Err(io::ErrorKind::InvalidInput.into())}Ok(current.original.value.map_text(|text|text.get()))
 }
 fn current_header_literal(&self,token:dm_syntax::SpanToken)->io::Result<Option<&OriginalLiteralData>>{
  self.check()?;let current=self.pulls.as_slice().last().ok_or(io::ErrorKind::InvalidInput)?;if current.kind!=token.kind||current.span!=token.span||self.primary.span_tokens().last()!=Some(&token){return Err(io::ErrorKind::InvalidInput.into())}self.primary.original_literal_for_span(token.span)
 }

 fn with_current_source(&self,read:&mut dyn FnMut(&str,&[dm_syntax::SpanToken])->io::Result<()>)->io::Result<()>{self.check()?;let result=read(self.producer.current_source(),self.primary.span_tokens());if result.is_err(){self.failed.set(true)}result}
}

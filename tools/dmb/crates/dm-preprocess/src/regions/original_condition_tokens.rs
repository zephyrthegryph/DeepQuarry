//! The actual completed preprocessor queue lent to the SAME native Pratt.
//! Owned token/value/credit moves once; canonical chunks accompany the SAME projection without relex or replay.
use super::{original_output_queue::OriginalOutputQueue,original_conditional_pump::OriginalCompletedCondition,original_native_projection::{project_native_token_using,Adjacency,needs_separator}};
use crate::{SourceProvider,macro_expansion::{OriginalMacroRows as Rows,OriginalMacroToken as ActualToken}};
use dm_syntax::{SettingAdmission,SettingRootLease,Span,Token,NativeExpressionTokenDemand,NativeExpressionTokenOccurrence,OriginalLiteralData,OriginalTokenValue};
use std::{io,cell::Cell};
struct Occurrence{actual:ActualToken<'static>,span:Span,literal:Option<OriginalLiteralData>,credit:Option<SettingRootLease>}
enum ParserEvent{Primitive{at:NativeExpressionTokenOccurrence,kind:dm_syntax::OriginalInputNoticeKind},MissingMember{separator:NativeExpressionTokenOccurrence,following:Option<NativeExpressionTokenOccurrence>}}
pub(super) struct OriginalConditionTokens<'a,'budget>{queue:&'a mut OriginalOutputQueue<'static>,provider:&'a dyn SourceProvider,a:&'a SettingAdmission<'budget>,rows:Rows<Occurrence>,events:Rows<ParserEvent>,source:crate::macro_expansion::OriginalMacroText,next_offset:usize,last:Option<Adjacency>,begun:bool,failed:Cell<bool>,completion:OriginalCompletedCondition}
impl<'a,'budget> OriginalConditionTokens<'a,'budget>{
 pub(super) fn new(queue:&'a mut OriginalOutputQueue<'static>,provider:&'a dyn SourceProvider,a:&'a SettingAdmission<'budget>,completion:OriginalCompletedCondition)->io::Result<Self>{Ok(Self{queue,provider,a,rows:Rows::new(a)?,events:Rows::new(a)?,source:crate::macro_expansion::OriginalMacroText::new(a)?,next_offset:0,last:None,begun:false,failed:Cell::new(false),completion})}
 pub(super) fn last_input(&self)->crate::macro_expansion::OriginalMacroOrigin{self.completion.last_input()}
 fn check(&self)->io::Result<()>{if self.failed.get(){return Err(io::ErrorKind::InvalidInput.into())}let result=self.a.checkpoint().map_err(|e|self.a.take_operational_error().unwrap_or(e));if result.is_err(){self.failed.set(true)}result}
 fn row(&self,occurrence:NativeExpressionTokenOccurrence)->io::Result<&Occurrence>{self.check()?;let row=self.rows.as_slice().get(occurrence.ordinal()).ok_or(io::ErrorKind::InvalidInput)?;if row.span!=occurrence.span(){return Err(io::ErrorKind::InvalidInput.into())}Ok(row)}
 /// Keep the SAME Pratt result alive while formatting its typed failure:
 /// that result owns the moved spelling credit; this row loans actual VALUE.
 pub(super) fn failure_using(&self,span:Option<Span>,input:Option<dm_syntax::OriginalInputExpected>,initial:crate::macro_expansion::OriginalMacroOrigin)->io::Result<(crate::macro_expansion::OriginalMacroText,crate::macro_expansion::OriginalMacroOrigin)>{self.check()?;let row=match span{Some(span)=>Some(self.rows.as_slice().iter().find(|row|row.span==span).ok_or(io::ErrorKind::InvalidInput)?),None=>None};let value=row.map(|row|row.actual.value.map_text(|text|text.get()));let place=row.or_else(||self.rows.as_slice().last()).map_or(initial,|row|row.actual.origin);let mut text=crate::macro_expansion::OriginalMacroText::new(self.a)?;crate::macro_expansion::original_format_using(&mut text,self.a,|out|match input{Some(expected)=>dm_syntax::write_original_input_failure(out,value,expected),None=>dm_syntax::write_original_term_failure(out,value)})?;Ok((text,place))}
 pub(super) fn observe_notices_using(&self,notices:&dm_syntax::OriginalInputNotices,sink:&mut dyn super::original_raw_inputs::OriginalRawNoticeSink)->io::Result<()>{self.check()?;if !notices.is_admitted_by(self.a){return Err(io::ErrorKind::InvalidInput.into())}let mut primitive=notices.as_slice().iter();for event in self.events.as_slice(){self.check()?;match event{ParserEvent::Primitive{at,kind}=>{let row=self.row(*at)?;let actual=primitive.next().ok_or(io::ErrorKind::InvalidData)?;if actual.span()!=at.span()||actual.kind()!=*kind{return Err(io::ErrorKind::InvalidData.into())}sink.condition_primitive(row.actual.origin,*kind,row.actual.value.map_text(|text|text.get()),self.a)?},ParserEvent::MissingMember{separator,following}=>{let separator=self.row(*separator)?;let following=following.map(|row|self.row(row)).transpose()?;let place=following.map_or(separator.actual.origin,|row|row.actual.origin);let value=following.map(|row|row.actual.value.map_text(|text|text.get()));sink.condition_identifier_recovery(place,value,self.a)?}}}if primitive.next().is_some(){return Err(io::ErrorKind::InvalidData.into())}Ok(())}
 pub(super) fn delimiter_failure_using(&self,expected:dm_syntax::NativeDelimiterExpectation,initial:crate::macro_expansion::OriginalMacroOrigin)->io::Result<(crate::macro_expansion::OriginalMacroText,crate::macro_expansion::OriginalMacroOrigin)>{self.check()?;let row=match expected.token_span(){Some(span)=>Some(self.rows.as_slice().iter().find(|row|row.span==span).ok_or(io::ErrorKind::InvalidInput)?),None=>None};let value=row.map(|row|row.actual.value.map_text(|text|text.get()));let place=row.or_else(||self.rows.as_slice().last()).map_or(initial,|row|row.actual.origin);let mut text=crate::macro_expansion::OriginalMacroText::new(self.a)?;crate::macro_expansion::original_format_using(&mut text,self.a,|out|dm_syntax::write_original_delimiter_failure(out,value,expected.expected()))?;Ok((text,place))}
 fn next_inner(&mut self)->io::Result<Option<Token>>{
  self.check()?;if !self.begun{return Err(io::ErrorKind::InvalidInput.into())}let Some(actual)=self.queue.pop()?else{return Ok(None)};
  let projection=project_native_token_using(&actual,self.provider,self.a)?;let start=self.next_offset.checked_add(usize::from(needs_separator(self.last,projection.adjacency))).ok_or(io::ErrorKind::OutOfMemory)?;let span=Span::new(start,start.checked_add(projection.spelling.as_str().len()).ok_or(io::ErrorKind::OutOfMemory)?);
  // SAME canonical adjacency as final output; unconditional gaps would
  // destroy actual /type path adjacency while preserving no extra identity.
  // Only actually pulled typed projected chunks enter this funded source.
  if self.source.as_str().len()!=self.next_offset{return Err(io::ErrorKind::InvalidData.into())}if start>self.next_offset{self.source.push(' ',self.a)?;}self.source.push_str(projection.spelling.as_str(),self.a)?;if self.source.as_str().len()!=span.end{return Err(io::ErrorKind::InvalidData.into())}
  self.next_offset=span.end;self.last=Some(projection.adjacency);
  // Keep the physical spelling inside its allocation-owning Text until every
  // fallible roster operation is complete. A failed push must not refund its
  // credit while a separately constructed Token still owns the String.
  let slot=self.rows.len();self.rows.push(Occurrence{actual,span,literal:projection.literal,credit:None},self.a)?;
  let(text,credit)=projection.spelling.into_parts();self.rows.as_mut_slice()[slot].credit=Some(credit);Ok(Some(Token{kind:projection.kind,span,text}))
 }
}
impl NativeExpressionTokenDemand for OriginalConditionTokens<'_,'_>{
 fn original_trivia_is_significant(&self)->bool{true}
 fn original_primitive_notice(&mut self,at:NativeExpressionTokenOccurrence,kind:dm_syntax::OriginalInputNoticeKind)->io::Result<()>{self.row(at)?;self.events.push(ParserEvent::Primitive{at,kind},self.a)}
 fn original_missing_member(&mut self,separator:NativeExpressionTokenOccurrence,following:Option<NativeExpressionTokenOccurrence>)->io::Result<bool>{let row=self.row(separator)?;if !matches!(row.actual.value,OriginalTokenValue::Punct("."|":"|"::"|"?."|"?:")){return Err(io::ErrorKind::InvalidData.into())}if let Some(next)=following{self.row(next)?;if next.ordinal()<=separator.ordinal(){return Err(io::ErrorKind::InvalidData.into())}}else if !self.queue.is_empty(){return Err(io::ErrorKind::InvalidData.into())}self.events.push(ParserEvent::MissingMember{separator,following},self.a)?;Ok(true)}

 fn requires_expression_end(&self)->bool{false}
 fn original_template_source(&self,span:Span)->io::Result<Option<&str>>{self.check()?;if self.source.as_str().len()!=self.next_offset||span.start>=span.end{return Err(io::ErrorKind::InvalidData.into())}let(mut begin,mut end)=(None,None);for row in self.rows.as_slice(){self.check()?;if row.span.start==span.start{begin=Some(row)}if row.span.end==span.end{end=Some(row)}}let(begin,end)=(begin.ok_or(io::ErrorKind::InvalidInput)?,end.ok_or(io::ErrorKind::InvalidInput)?);if !matches!(begin.literal.as_ref().map(OriginalLiteralData::value),Some(OriginalTokenValue::InterpBegin(_)))||!matches!(end.literal.as_ref().map(OriginalLiteralData::value),Some(OriginalTokenValue::InterpEnd(_))){return Err(io::ErrorKind::InvalidInput.into())}self.source.as_str().get(span.range()).map(Some).ok_or_else(||io::ErrorKind::InvalidData.into())}

 fn original_close_colon(&self,occurrence:NativeExpressionTokenOccurrence)->io::Result<Option<bool>>{let row=self.row(occurrence)?;Ok(matches!(row.actual.value,OriginalTokenValue::Punct(":" )).then_some(row.actual.punctuation_close))}

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

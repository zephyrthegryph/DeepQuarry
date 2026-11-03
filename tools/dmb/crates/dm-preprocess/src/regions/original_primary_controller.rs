//! Actual logical producer and receiver-owned SAME primary continuation.
//! The grammar never knows whether complete batches or lazy tokens fed it.
use super::{OriginalPrimaryStreamConsumer,original_driver::{RawSourceDriver,DriverEvent,LogicalToken},original_macro_source::OriginalMacroHost,original_raw_inputs::OriginalRawNoticeSink,original_final_output::{OriginalFinalOutput,OriginalEmittedToken},original_formal_source::{OriginalFormalProducer,OriginalLiveFormalSource},original_prepared_output::{OriginalOutputCursor,OriginalPreparedOutputToken,OriginalDeliveryFrontier,OriginalProducedSpan}};
use crate::{SourceProvider,source_arena_credit::SourceArenaWork,macro_expansion::{OriginalMacroToken as Token,OriginalMacroValue as Value,OriginalMacroOrigin as Origin,OriginalMacroNotice as MacroNotice}};
use dm_syntax::{OriginalPrimaryDemand,OriginalPrimaryLiveHeader,OriginalDeclarationSkeleton,OriginalHeaderFlow,SettingAdmission,NativeIndentNotice,Span,SpanToken};use std::io;
pub(super) trait OriginalStreamControl{
 fn directive(&mut self,hash:Origin,driver:&mut RawSourceDriver,provider:&dyn SourceProvider,notices:&mut dyn OriginalRawNoticeSink,host:&mut dyn OriginalMacroHost,a:&SettingAdmission<'_>)->io::Result<()>;
 fn macro_notice(&mut self,notice:MacroNotice,driver:&mut RawSourceDriver,provider:&dyn SourceProvider,notices:&mut dyn OriginalRawNoticeSink,host:&mut dyn OriginalMacroHost,a:&SettingAdmission<'_>)->io::Result<()>;
 fn conditional_eof(&mut self,actual:super::original_conditional::Unterminated,a:&SettingAdmission<'_>)->io::Result<()>;
 fn indent_notice(&mut self,kind:NativeIndentNotice,location:Option<Origin>,a:&SettingAdmission<'_>)->io::Result<()>;
 fn emitted(&mut self,actual:&Token<'static>,token:SpanToken,cover:Span,produced:OriginalProducedSpan<'_>,driver:&mut RawSourceDriver,provider:&dyn SourceProvider,a:&SettingAdmission<'_>)->io::Result<()>;
}
pub(super) struct OriginalPrimaryOutput{pub(super) source:crate::SourceText,pub(super) primary:OriginalDeclarationSkeleton,pub(super) consumed_eof:bool,pub(super) delivery:OriginalDeliveryFrontier}
impl OriginalPrimaryOutput{
 pub(super) fn into_bound_parts_using(mut self,a:&SettingAdmission<'_>)->io::Result<(crate::SourceText,OriginalDeclarationSkeleton,dm_syntax::SharedSpanTokens,super::original_literal_source::OriginalLiteralSourceBinding,bool)>{
  let facts=self.primary.take_original_literal_fact_owner_using(a)?.ok_or_else(||io::Error::new(io::ErrorKind::Unsupported,"actual logical primary has no issued neutral literal roster"))?;
  let binding=super::original_literal_source::OriginalLiteralSourceBinding::issue_actual(&self.source,facts,a)?;let(primary,tokens)=self.primary.into_shared_tokens_using(a)?;Ok((self.source,primary,tokens,binding,self.consumed_eof))
 }
}
/// Private pull side. Its real implementation owns raw traversal, directive
/// effects, output cursor and actual end; adapters cannot turn a pause into EOF.
pub(super) trait OriginalPreparedTokenSource{
 fn initial_delivery(&self)->OriginalDeliveryFrontier;
 fn next_prepared(&mut self)->io::Result<Option<OriginalPreparedOutputToken>>;
 fn reached_eof(&self)->bool;
 fn stop(&mut self);
}
pub(super) struct OriginalLogicalProducer<'source,'loan,'budget>{driver:&'loan mut RawSourceDriver,provider:&'source dyn SourceProvider,notices:&'loan mut dyn OriginalRawNoticeSink,host:&'loan mut dyn OriginalMacroHost,control:&'loan mut dyn OriginalStreamControl,a:&'loan SettingAdmission<'budget>,cursor:OriginalOutputCursor,initial:OriginalDeliveryFrontier,ended:bool,failed:bool,stopped:bool}
impl<'source,'loan,'budget> OriginalLogicalProducer<'source,'loan,'budget>{
 pub(super) fn new(driver:&'loan mut RawSourceDriver,provider:&'source dyn SourceProvider,notices:&'loan mut dyn OriginalRawNoticeSink,host:&'loan mut dyn OriginalMacroHost,control:&'loan mut dyn OriginalStreamControl,a:&'loan SettingAdmission<'budget>)->io::Result<Self>{let cursor=OriginalOutputCursor::new(a)?;let initial=cursor.initial_delivery()?;Ok(Self{driver,provider,notices,host,control,a,cursor,initial,ended:false,failed:false,stopped:false})}
 fn pull_inner(&mut self)->io::Result<Option<OriginalPreparedOutputToken>>{
  loop{self.a.checkpoint().map_err(|e|self.a.take_operational_error().unwrap_or(e))?;
   let actual=match self.driver.next_logical_using(self.provider,self.notices,self.host,self.a)?{
    DriverEvent::Token(LogicalToken::Actual(token))=>token,
    DriverEvent::Token(LogicalToken::Delimiter{spelling,location})=>{let origin=location.ok_or_else(||io::Error::new(io::ErrorKind::Unsupported,"logical default location has no actual source occurrence"))?;Token{string_mode:dm_syntax::OriginalStringMode::Unknown,punctuation_close:false,lexical_frame:None,lexical_span:None,raw_spelling:None,value:Value::Punct(spelling),origin}},
    DriverEvent::Directive{hash}=>{self.control.directive(hash,self.driver,self.provider,self.notices,self.host,self.a)?;continue},
    DriverEvent::MacroNotice(notice)=>{self.control.macro_notice(notice,self.driver,self.provider,self.notices,self.host,self.a)?;continue},
    DriverEvent::IndentNotice{kind,location}=>{self.control.indent_notice(kind,location,self.a)?;continue},
    DriverEvent::ConditionalEof(actual)=>{self.control.conditional_eof(actual,self.a)?;continue},
    DriverEvent::NeedInput=>return Err(io::Error::new(io::ErrorKind::WouldBlock,"synchronous actual logical source has not issued another token")),
    DriverEvent::ActualEnd=>{self.ended=true;return Ok(None)},
    DriverEvent::Stopped=>return Err(io::Error::new(io::ErrorKind::InvalidInput,"source stopped without its actual receiver stop handoff")),
   };
   let prepared=self.cursor.prepare(actual,self.provider,self.a)?;
   self.control.emitted(prepared.actual()?,prepared.token(),prepared.cover(),prepared.produced(),self.driver,self.provider,self.a)?;return Ok(Some(prepared))
  }
 }
}
impl OriginalPreparedTokenSource for OriginalLogicalProducer<'_,'_,'_>{
 fn initial_delivery(&self)->OriginalDeliveryFrontier{self.initial.clone()}
 fn next_prepared(&mut self)->io::Result<Option<OriginalPreparedOutputToken>>{if self.failed||self.stopped{return Err(io::ErrorKind::InvalidInput.into())}if self.ended{return Ok(None)}let result=self.pull_inner();if result.is_err(){self.failed=true;}result}
 fn reached_eof(&self)->bool{self.ended}
 fn stop(&mut self){self.stopped=true;self.driver.stop();}
}
struct PrimaryReceiver<'source,'arena,'loan,'budget>{source:&'source mut dyn OriginalPreparedTokenSource,output:OriginalFinalOutput<'arena>,a:&'loan SettingAdmission<'budget>}
impl PrimaryReceiver<'_,'_,'_,'_>{fn pull(&mut self,primary:&mut OriginalPrimaryDemand<'_,'_,'_>)->io::Result<Option<OriginalEmittedToken>>{match self.source.next_prepared()?{Some(prepared)=>self.output.adopt(prepared,primary,self.a).map(Some),None if self.source.reached_eof()=>Ok(None),None=>Err(io::Error::new(io::ErrorKind::InvalidData,"batch/source pause cannot become actual primary EOF"))}}}
impl OriginalFormalProducer for PrimaryReceiver<'_,'_,'_,'_>{fn pull_formal_token(&mut self,primary:&mut OriginalPrimaryDemand<'_,'_,'_>)->io::Result<Option<OriginalEmittedToken>>{self.pull(primary)}fn current_source(&self)->&str{self.output.source()}}
/// ONE grammar loop for both authentic delivery profiles. The source already
/// enforces either lazy driver demand or the genuine complete-batch protocol.
pub(super) fn consume_prepared_primary_using(source:&mut dyn OriginalPreparedTokenSource,work:&dyn SourceArenaWork,a:&SettingAdmission<'_>,consumer:&mut dyn OriginalPrimaryStreamConsumer)->io::Result<OriginalPrimaryOutput>{
 let initial=source.initial_delivery();if initial.end()!=0||!initial.owner().admitted_by(a){return Err(io::ErrorKind::InvalidInput.into())}let mut primary=OriginalPrimaryDemand::new(a,None)?;let mut receiver=PrimaryReceiver{source,output:OriginalFinalOutput::receiver(work,initial)?,a};let mut entered:Option<OriginalPrimaryLiveHeader>=None;
 loop{
  if receiver.pull(&mut primary)?.is_none(){primary.advance_with_observer(receiver.output.source(),true,consumer)?;break}
  if !primary.advance_with_observer(receiver.output.source(),false,consumer)?{receiver.source.stop();break}
  if let Some(live)=primary.live_callable_header(receiver.output.source())?{
   if entered.as_ref().is_some_and(|old|old.start()==live.start()){primary.validate_live_header(entered.as_ref().unwrap())?;continue}
   let result={let mut source=OriginalLiveFormalSource::new(&mut receiver,&mut primary,live.clone(),a)?;consumer.callable(live.clone(),&mut source)?};entered=Some(live.clone());
   if result==OriginalHeaderFlow::Stop{primary.observer_stop_live_header_at(&live,receiver.output.source())?;receiver.source.stop();break}
   if !primary.advance_with_observer(receiver.output.source(),false,consumer)?{receiver.source.stop();break}
  }
 }
 let consumed_eof=receiver.source.reached_eof();let actual=primary.finish(receiver.output.source(),consumed_eof)?;let delivery=receiver.output.delivery()?;let source=receiver.output.finish()?;Ok(OriginalPrimaryOutput{source,primary:actual,consumed_eof,delivery})
}
pub(super) fn consume_lazy_primary_using(driver:&mut RawSourceDriver,provider:&dyn SourceProvider,work:&dyn SourceArenaWork,notices:&mut dyn OriginalRawNoticeSink,host:&mut dyn OriginalMacroHost,control:&mut dyn OriginalStreamControl,a:&SettingAdmission<'_>,consumer:&mut dyn OriginalPrimaryStreamConsumer)->io::Result<OriginalPrimaryOutput>{let mut source=OriginalLogicalProducer::new(driver,provider,notices,host,control,a)?;consume_prepared_primary_using(&mut source,work,a,consumer)}
#[cfg(test)]#[path="original_primary_controller_tests.rs"]mod tests;

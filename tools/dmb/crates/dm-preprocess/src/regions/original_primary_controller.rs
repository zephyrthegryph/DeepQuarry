//! Actual logical producer and receiver-owned SAME primary continuation.
//! The grammar never knows whether complete batches or lazy tokens fed it.
use super::{OriginalPrimaryStreamConsumer,original_driver::{RawSourceDriver,DriverEvent,LogicalToken},original_macro_source::OriginalMacroHost,original_raw_inputs::OriginalRawNoticeSink,original_final_output::{OriginalFinalOutput,OriginalEmittedToken},original_formal_source::{OriginalFormalProducer,OriginalLiveFormalSource},original_prepared_output::{OriginalOutputCursor,OriginalOutputIdentity,OriginalPreparedDeliveryToken,OriginalDeliveryFrontier,OriginalProducedSpan,OriginalProducedEnd,OriginalBatchTokenPage}};
use crate::{SourceProvider,source_arena_credit::SourceArenaWork,macro_expansion::{OriginalMacroToken as Token,OriginalMacroValue as Value,OriginalMacroOrigin as Origin,OriginalMacroNotice as MacroNotice}};
use dm_syntax::{OriginalPrimaryDemand,OriginalPrimaryLiveHeader,OriginalCommittedPrimary,OriginalDeclarationSkeleton,OriginalHeaderFlow,SettingAdmission,NativeIndentNotice,Span,SpanToken};use std::io;
pub(super) trait OriginalStreamControl{
 fn batch_token_pages(&self,_owner:&OriginalOutputIdentity,_end:usize,_count:usize,_a:&SettingAdmission<'_>)
  ->io::Result<[Option<OriginalBatchTokenPage>;2]>{Ok([None,None])}
 /// Genuine nonphysical default delimiter; no physical mapping may be forged.
 fn default_semicolon(&mut self,_produced:OriginalProducedSpan<'_>,_driver:&mut RawSourceDriver,_a:&SettingAdmission<'_>)->io::Result<()>{Err(io::Error::new(io::ErrorKind::Unsupported,"actual nonphysical default delimiter metadata consumer is unissued"))}

 fn directive(&mut self,hash:Origin,driver:&mut RawSourceDriver,provider:&dyn SourceProvider,notices:&mut dyn OriginalRawNoticeSink,host:&mut dyn OriginalMacroHost,a:&SettingAdmission<'_>)->io::Result<()>;
 fn macro_notice(&mut self,notice:MacroNotice,driver:&mut RawSourceDriver,provider:&dyn SourceProvider,notices:&mut dyn OriginalRawNoticeSink,host:&mut dyn OriginalMacroHost,a:&SettingAdmission<'_>)->io::Result<()>;
 fn conditional_eof(&mut self,actual:super::original_conditional::Unterminated,a:&SettingAdmission<'_>)->io::Result<()>;
 fn indent_notice(&mut self,kind:NativeIndentNotice,location:Option<Origin>,a:&SettingAdmission<'_>)->io::Result<()>;
 fn emitted(&mut self,actual:&Token<'static>,token:SpanToken,cover:Span,produced:OriginalProducedSpan<'_>,driver:&mut RawSourceDriver,provider:&dyn SourceProvider,a:&SettingAdmission<'_>)->io::Result<()>;
}
/// Both variants are issued by the same token receiver and declaration parser.
pub enum OriginalStreamPrimary {
    Dense(OriginalDeclarationSkeleton),
    Committed(OriginalCommittedPrimary),
}

impl From<OriginalDeclarationSkeleton> for OriginalStreamPrimary {
    fn from(primary: OriginalDeclarationSkeleton) -> Self { Self::Dense(primary) }
}

impl OriginalStreamPrimary {
    pub fn observer_stop(&self) -> Option<Span> {
        match self {
            Self::Dense(primary) => primary.observer_stop(),
            Self::Committed(primary) => primary.observer_stop(),
        }
    }

    pub fn same_primary_header(&self, header: &OriginalPrimaryLiveHeader) -> bool {
        match self {
            Self::Dense(primary) => primary.same_primary_header(header),
            Self::Committed(primary) => primary.same_primary_header(header),
        }
    }

    pub fn same_primary_producer(&self, producer: &dm_syntax::OriginalPrimaryProducerIdentity) -> bool {
        match self {
            Self::Dense(primary) => primary.same_primary_producer(producer),
            Self::Committed(primary) => primary.same_primary_producer(producer),
        }
    }
}

pub(super) struct OriginalPrimaryOutput{pub(super) source:crate::SourceText,pub(super) primary:OriginalStreamPrimary,pub(super) consumed_eof:bool,pub(super) delivery:OriginalDeliveryFrontier}
impl OriginalPrimaryOutput{
 pub(super) fn into_bound_parts_using(mut self,a:&SettingAdmission<'_>)->io::Result<(crate::SourceText,OriginalStreamPrimary,dm_syntax::SharedSpanTokens,super::original_literal_source::OriginalLiteralSourceBinding,bool)>{
  let facts=match &mut self.primary {
      OriginalStreamPrimary::Dense(primary) => primary.take_original_literal_fact_owner_using(a)?,
      OriginalStreamPrimary::Committed(primary) => primary.take_original_literal_fact_owner_using(a)?,
  }.ok_or_else(||io::Error::new(io::ErrorKind::Unsupported,"actual logical primary has no issued neutral literal roster"))?;
  let binding=super::original_literal_source::OriginalLiteralSourceBinding::issue_actual(&self.source,facts,a)?;
  let (primary, tokens) = match self.primary {
      OriginalStreamPrimary::Dense(primary) => {
          let (primary, tokens) = primary.into_shared_tokens_using(a)?;
          (OriginalStreamPrimary::Dense(primary), tokens)
      }
      OriginalStreamPrimary::Committed(primary) => {
          let tokens = primary.tokens().clone();
          (OriginalStreamPrimary::Committed(primary), tokens)
      }
  };
  Ok((self.source,primary,tokens,binding,self.consumed_eof))
 }
}
/// Private pull side. Its real implementation owns raw traversal, directive
/// effects, output cursor and actual end; adapters cannot turn a pause into EOF.
pub(super) trait OriginalPreparedTokenSource{
 fn batch_token_pages(&self,_owner:&OriginalOutputIdentity,_end:usize,_count:usize,_a:&SettingAdmission<'_>)
  ->io::Result<[Option<OriginalBatchTokenPage>;2]>{Ok([None,None])}
 fn initial_delivery(&self)->OriginalDeliveryFrontier;
 fn next_prepared(&mut self)->io::Result<Option<OriginalPreparedDeliveryToken>>;
 fn reached_eof(&self)->bool;
 fn actual_end(&self)->Option<OriginalProducedEnd>{None}
 fn stop(&mut self);
}
pub(super) struct OriginalLogicalProducer<'source,'loan,'budget>{driver:&'loan mut RawSourceDriver,provider:&'source dyn SourceProvider,notices:&'loan mut dyn OriginalRawNoticeSink,host:&'loan mut dyn OriginalMacroHost,control:&'loan mut dyn OriginalStreamControl,a:&'loan SettingAdmission<'budget>,cursor:OriginalOutputCursor,initial:OriginalDeliveryFrontier,actual_end:Option<OriginalProducedEnd>,ended:bool,failed:bool,stopped:bool,loan_batch_geometry:bool}
impl<'source,'loan,'budget> OriginalLogicalProducer<'source,'loan,'budget>{
 pub(super) fn new(driver:&'loan mut RawSourceDriver,provider:&'source dyn SourceProvider,notices:&'loan mut dyn OriginalRawNoticeSink,host:&'loan mut dyn OriginalMacroHost,control:&'loan mut dyn OriginalStreamControl,a:&'loan SettingAdmission<'budget>)->io::Result<Self>{let cursor=OriginalOutputCursor::new(a)?;let initial=cursor.initial_delivery()?;Ok(Self{driver,provider,notices,host,control,a,cursor,initial,actual_end:None,ended:false,failed:false,stopped:false,loan_batch_geometry:false})}
 pub(super) fn enable_batch_geometry(&mut self){self.loan_batch_geometry=true;}
 fn pull_inner(&mut self)->io::Result<Option<OriginalPreparedDeliveryToken>>{
  loop{self.a.checkpoint().map_err(|e|self.a.take_operational_error().unwrap_or(e))?;
   let actual=match self.driver.next_logical_using(self.provider,self.notices,self.host,self.a)?{
    DriverEvent::Token(LogicalToken::Actual(token))=>token,
    DriverEvent::Token(LogicalToken::Delimiter{spelling,location:None})=>{if spelling!=";"{return Err(io::Error::new(io::ErrorKind::InvalidData,"default logical state issued unexpected nonphysical punctuation"))}let prepared=self.cursor.prepare_default_semicolon(self.a)?;self.control.default_semicolon(prepared.produced(),self.driver,self.a)?;return Ok(Some(prepared.into_delivery()))},
    DriverEvent::Token(LogicalToken::Delimiter{spelling,location:Some(origin)})=>{Token{string_mode:dm_syntax::OriginalStringMode::Unknown,punctuation_close:false,lexical_frame:None,lexical_span:None,raw_spelling:None,value:Value::Punct(spelling),origin}},
    DriverEvent::Directive{hash}=>{self.control.directive(hash,self.driver,self.provider,self.notices,self.host,self.a)?;continue},
    DriverEvent::MacroNotice(notice)=>{self.control.macro_notice(notice,self.driver,self.provider,self.notices,self.host,self.a)?;continue},
    DriverEvent::IndentNotice{kind,location}=>{self.control.indent_notice(kind,location,self.a)?;continue},
    DriverEvent::ConditionalEof(actual)=>{self.control.conditional_eof(actual,self.a)?;continue},
    DriverEvent::NeedInput=>return Err(io::Error::new(io::ErrorKind::WouldBlock,"synchronous actual logical source has not issued another token")),
    DriverEvent::ActualEnd=>{self.actual_end=Some(self.cursor.seal_actual_end(self.a)?);self.ended=true;return Ok(None)},
    DriverEvent::Stopped=>return Err(io::Error::new(io::ErrorKind::InvalidInput,"source stopped without its actual receiver stop handoff")),
   };
   let prepared=self.cursor.prepare(actual,self.provider,self.a)?;
   self.control.emitted(prepared.actual()?,prepared.token(),prepared.cover(),prepared.produced(),self.driver,self.provider,self.a)?;return Ok(Some(prepared.into_delivery()))
  }
 }
}
impl OriginalPreparedTokenSource for OriginalLogicalProducer<'_,'_,'_>{
 fn batch_token_pages(&self,owner:&OriginalOutputIdentity,end:usize,count:usize,a:&SettingAdmission<'_>)
  ->io::Result<[Option<OriginalBatchTokenPage>;2]>{
   if self.loan_batch_geometry {self.control.batch_token_pages(owner,end,count,a)}
   else{Ok([None,None])}
 }
 fn initial_delivery(&self)->OriginalDeliveryFrontier{self.initial.clone()}
 fn next_prepared(&mut self)->io::Result<Option<OriginalPreparedDeliveryToken>>{if self.failed||self.stopped{return Err(io::ErrorKind::InvalidInput.into())}if self.ended{return Ok(None)}let result=self.pull_inner();if result.is_err(){self.failed=true;}result}
 fn reached_eof(&self)->bool{self.ended}
 fn actual_end(&self)->Option<OriginalProducedEnd>{if self.ended&&!self.stopped{self.actual_end.clone()}else{None}}
 fn stop(&mut self){self.stopped=true;self.driver.stop();}
}
struct PrimaryReceiver<'source,'arena,'loan,'budget>{source:&'source mut dyn OriginalPreparedTokenSource,output:OriginalFinalOutput<'arena>,a:&'loan SettingAdmission<'budget>,actual_end:Option<OriginalProducedEnd>}
impl PrimaryReceiver<'_,'_,'_,'_>{fn pull(&mut self,primary:&mut OriginalPrimaryDemand<'_,'_,'_>)->io::Result<Option<OriginalEmittedToken>>{match self.source.next_prepared()?{Some(prepared)=>self.output.adopt(prepared,primary,self.a).map(Some),None if self.source.reached_eof()=>{let actual=self.source.actual_end();if let Some(end)=&actual{end.validate(&self.output.delivery()?,self.a)?;}self.actual_end=actual;Ok(None)},None=>Err(io::Error::new(io::ErrorKind::InvalidData,"batch/source pause cannot become actual primary EOF"))}}}
impl OriginalFormalProducer for PrimaryReceiver<'_,'_,'_,'_>{fn pull_formal_token(&mut self,primary:&mut OriginalPrimaryDemand<'_,'_,'_>)->io::Result<Option<OriginalEmittedToken>>{self.pull(primary)}fn current_source(&self)->&str{self.output.source()}fn actual_end(&self)->Option<&OriginalProducedEnd>{self.actual_end.as_ref()}}
/// ONE grammar loop for both authentic delivery profiles. The source already
/// enforces either lazy driver demand or the genuine complete-batch protocol.
pub(super) fn consume_prepared_primary_using(source:&mut dyn OriginalPreparedTokenSource,work:&dyn SourceArenaWork,a:&SettingAdmission<'_>,consumer:&mut dyn OriginalPrimaryStreamConsumer)->io::Result<OriginalPrimaryOutput>{
 let initial=source.initial_delivery();if initial.end()!=0||!initial.owner().admitted_by(a){return Err(io::ErrorKind::InvalidInput.into())}
 let committed=consumer.retains_committed_items();
 let mut primary=if committed{OriginalPrimaryDemand::new_committed(a,None)?}else{OriginalPrimaryDemand::new(a,None)?};let mut receiver=PrimaryReceiver{source,output:OriginalFinalOutput::receiver(work,initial)?,a,actual_end:None};let mut stopped_after_formals=false;let mut entered:Option<OriginalPrimaryLiveHeader>=None;
 let progress=(||->io::Result<()>{loop{
  if receiver.pull(&mut primary).inspect_err(|error|{#[cfg(debug_assertions)]if std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some(){eprintln!("ORIGINAL_FATAL_STAGE=receiver_pull {error:?}");}})?.is_none(){primary.advance_with_observer(receiver.output.source(),true,consumer).inspect_err(|error|{#[cfg(debug_assertions)]if std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some(){eprintln!("ORIGINAL_FATAL_STAGE=advance_eof {error:?}");}})?;break}
  if !primary.advance_with_observer(receiver.output.source(),false,consumer).inspect_err(|error|{#[cfg(debug_assertions)]if std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some(){eprintln!("ORIGINAL_FATAL_STAGE=advance_current {error:?}");}})?{receiver.source.stop();break}
  if let Some(live)=primary.resume_live_callable_header(receiver.output.source()).inspect_err(|error|{#[cfg(debug_assertions)]if std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some(){eprintln!("ORIGINAL_FATAL_STAGE=live_header {error:?}");}})?{
   if entered.as_ref().is_some_and(|old|old.start()==live.start()){primary.validate_live_header(entered.as_ref().unwrap())?;continue}
   let result={let mut source=OriginalLiveFormalSource::new(&mut receiver,&mut primary,live.clone(),a)?;consumer.callable(live.clone(),&mut source).inspect_err(|error|{#[cfg(debug_assertions)]if std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some(){eprintln!("ORIGINAL_FATAL_STAGE=callable {error:?}");}})?};entered=Some(live.clone());
   if result==OriginalHeaderFlow::Stop{stopped_after_formals=true;primary.observer_stop_live_header_at(&live,receiver.output.source()).inspect_err(|error|{#[cfg(debug_assertions)]if std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some(){eprintln!("ORIGINAL_FATAL_STAGE=stop_live {error:?}");}})?;receiver.source.stop();break}
   if !primary.advance_with_observer(receiver.output.source(),false,consumer).inspect_err(|error|{#[cfg(debug_assertions)]if std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some(){eprintln!("ORIGINAL_FATAL_STAGE=advance_current {error:?}");}})?{receiver.source.stop();break}
  }
 }Ok(())})();
 progress.inspect_err(|_error|{
  #[cfg(debug_assertions)]
  if std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some(){
   use std::io::Write;
   let counter_before_primary_drop=a.retained_bytes_for_trace();
   let literals=primary.trace_literal_retention();
   let tokens=primary.trace_token_retention();
   let items=primary.trace_item_retention(receiver.output.source());
   let _=writeln!(io::stderr().lock(),"ORIGINAL_LITERAL_CENSUS stage=receiver_before_finish counter_before_primary_drop={counter_before_primary_drop} literals={literals:?} tokens={tokens:?} items={items:?}");
  }
 })?;
 // A real physical EOF inside a failed formal still leaves primary at its
 // authored Stop frontier, without the ordinary declaration EOF assembly.
 let consumed_eof=receiver.source.reached_eof()&&!stopped_after_formals;
 let actual=if committed{
     primary.finish_committed(receiver.output.source(),consumed_eof).map(OriginalStreamPrimary::Committed)
 }else{
     primary.finish(receiver.output.source(),consumed_eof).map(OriginalStreamPrimary::Dense)
 }.inspect_err(|error|{#[cfg(debug_assertions)]if std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some(){eprintln!("ORIGINAL_FATAL_STAGE=primary_finish {error:?}");}})?;
 let delivery=receiver.output.delivery().inspect_err(|error|{#[cfg(debug_assertions)]if std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some(){eprintln!("ORIGINAL_FATAL_STAGE=receiver_delivery {error:?}");}})?;let source=receiver.output.finish().inspect_err(|error|{#[cfg(debug_assertions)]if std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some(){eprintln!("ORIGINAL_FATAL_STAGE=receiver_finish {error:?}");}})?;Ok(OriginalPrimaryOutput{source,primary:actual,consumed_eof,delivery})
}
pub(super) fn consume_lazy_primary_using(driver:&mut RawSourceDriver,provider:&dyn SourceProvider,work:&dyn SourceArenaWork,notices:&mut dyn OriginalRawNoticeSink,host:&mut dyn OriginalMacroHost,control:&mut dyn OriginalStreamControl,a:&SettingAdmission<'_>,consumer:&mut dyn OriginalPrimaryStreamConsumer)->io::Result<OriginalPrimaryOutput>{let mut source=OriginalLogicalProducer::new(driver,provider,notices,host,control,a)?;consume_prepared_primary_using(&mut source,work,a,consumer)}
#[cfg(test)]#[path="original_primary_controller_tests.rs"]mod tests;

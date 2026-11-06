//! Actual Analyze complete-batch delivery, with one bounded executor producer
//! and a caller-thread primary receiver. No private threads or parser clones.
use super::{original_batch_execution::OriginalBatchExecution,original_primary_controller::{OriginalPreparedTokenSource,OriginalPrimaryOutput,consume_prepared_primary_using},original_prepared_output::{OriginalPreparedDeliveryToken,OriginalDeliveryFrontier,OriginalProducedEnd},OriginalPrimaryStreamConsumer};
use crate::{source_arena_credit::SourceArenaWork,macro_expansion::OriginalMacroRows as Rows};
use dm_syntax::{SettingAdmission,SettingRootLease};use std::{io,sync::{Mutex,atomic::{AtomicBool,Ordering},mpsc::{sync_channel,SyncSender,Receiver}}};
const UNITS:usize=8192;const QUEUED:usize=64;
/// Actual traversal owner creates raw/notice/macro/control state INSIDE the
/// supplied fresh host admission, then finalizes its own metadata after run.
/// No callback-supplied usage vector, source hash or fabricated EOF exists.
pub(super) trait OriginalBatchRunner:Sync{
 type Metadata:Send;
 fn with_source(&self,a:&SettingAdmission<'_>,run:&mut dyn FnMut(&mut dyn OriginalPreparedTokenSource)->io::Result<()>)->io::Result<Self::Metadata>;
}
struct Batch{rows:Rows<OriginalPreparedDeliveryToken>}
struct Cursor{tokens:std::vec::IntoIter<OriginalPreparedDeliveryToken>,_credit:SettingRootLease}
impl Batch{fn cursor(self)->Cursor{let(rows,credit)=self.rows.into_parts();Cursor{tokens:rows.into_iter(),_credit:credit}}}
struct Signals{cancelled:AtomicBool,first:Mutex<Option<io::Error>>}
impl Signals{
 fn new()->Self{Self{cancelled:AtomicBool::new(false),first:Mutex::new(None)}}
 fn claim(&self,error:io::Error){let mut first=self.first.lock().unwrap_or_else(std::sync::PoisonError::into_inner);if first.is_none(){*first=Some(error)}}
 fn take(&self)->Option<io::Error>{self.first.lock().unwrap_or_else(std::sync::PoisonError::into_inner).take()}
}
enum Message{Start(OriginalDeliveryFrontier),Batch(Batch),End(Option<OriginalProducedEnd>)}
fn fill(source:&mut dyn OriginalPreparedTokenSource,a:&SettingAdmission<'_>,cancel:Option<&Signals>)->io::Result<Option<Batch>>{
 let mut rows=Rows::new(a)?;
 while rows.len()<UNITS{
  if cancel.is_some_and(|s|s.cancelled.load(Ordering::Acquire)){source.stop();return Ok(None)}
  a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;
  match source.next_prepared()?{Some(token)=>rows.push(token,a)?,None if source.reached_eof()=>break,None=>return Err(io::Error::new(io::ErrorKind::InvalidData,"batch producer pause is not actual EOF"))}
 }
 if rows.len()==0{Ok(None)}else{Ok(Some(Batch{rows}))}
}
fn send_batches(source:&mut dyn OriginalPreparedTokenSource,a:&SettingAdmission<'_>,tx:&SyncSender<Message>,signals:&Signals)->io::Result<()>{
 if tx.send(Message::Start(source.initial_delivery())).is_err(){source.stop();return Ok(())}
 loop{let next=fill(source,a,Some(signals))?;if signals.cancelled.load(Ordering::Acquire){source.stop();return Ok(())}match next{Some(batch)=>if tx.send(Message::Batch(batch)).is_err(){source.stop();return Ok(())},None if source.reached_eof()=>{let _=tx.send(Message::End(source.actual_end()));return Ok(())},None=>{source.stop();return Ok(())}}}
}
struct AsyncSource<'a>{rx:Option<Receiver<Message>>,current:Option<Cursor>,initial:OriginalDeliveryFrontier,signals:&'a Signals,actual_end:Option<OriginalProducedEnd>,ended:bool,stopped:bool}
impl<'a> AsyncSource<'a>{
 fn new(rx:Receiver<Message>,signals:&'a Signals,a:&SettingAdmission<'_>)->io::Result<Self>{let initial=match rx.recv(){Ok(Message::Start(start))if start.end()==0&&start.owner().admitted_by(a)=>start,Ok(_)=>return Err(io::ErrorKind::InvalidData.into()),Err(_)=>return Err(io::Error::new(io::ErrorKind::UnexpectedEof,"actual producer ended before its batch start"))};Ok(Self{rx:Some(rx),current:None,initial,signals,actual_end:None,ended:false,stopped:false})}
}
impl Drop for AsyncSource<'_>{fn drop(&mut self){self.signals.cancelled.store(true,Ordering::Release);self.rx.take();}}
impl OriginalPreparedTokenSource for AsyncSource<'_>{
 fn initial_delivery(&self)->OriginalDeliveryFrontier{self.initial.clone()}
 fn next_prepared(&mut self)->io::Result<Option<OriginalPreparedDeliveryToken>>{
  if self.stopped{return Err(io::ErrorKind::InvalidInput.into())}if self.ended{return Ok(None)}
  loop{if let Some(token)=self.current.as_mut().and_then(|c|c.tokens.next()){return Ok(Some(token))}self.current.take();match self.rx.as_ref().ok_or(io::ErrorKind::InvalidInput)?.recv(){Ok(Message::Batch(batch))=>{if batch.rows.len()==0||batch.rows.len()>UNITS{return Err(io::ErrorKind::InvalidData.into())}self.current=Some(batch.cursor())},Ok(Message::End(actual))=>{self.actual_end=actual;self.ended=true;return Ok(None)},Ok(Message::Start(_))=>return Err(io::ErrorKind::InvalidData.into()),Err(_)=>return Err(io::Error::new(io::ErrorKind::UnexpectedEof,"actual batch producer disconnected before EOF"))}}
 }
 fn reached_eof(&self)->bool{self.ended}
 fn actual_end(&self)->Option<OriginalProducedEnd>{if self.ended&&!self.stopped{self.actual_end.clone()}else{None}}
 fn stop(&mut self){self.stopped=true;self.signals.cancelled.store(true,Ordering::Release);self.rx.take();self.current.take();}
}
/// Fixed capacity64 queue plus the producer's one in-progress blocked-send
/// batch. This is a valid forced-fastest schedule of the SAME old protocol,
/// not a per-token lazy substitute or an unbounded materialized token list.
struct Cooperative<'source,'admission,'budget>{source:&'source mut dyn OriginalPreparedTokenSource,a:&'admission SettingAdmission<'budget>,queue:[Option<Batch>;QUEUED],head:usize,len:usize,pending:Option<Batch>,current:Option<Cursor>,initial:OriginalDeliveryFrontier,eof:bool,ended:bool,stopped:bool}
impl<'source,'admission,'budget> Cooperative<'source,'admission,'budget>{
 fn new(source:&'source mut dyn OriginalPreparedTokenSource,a:&'admission SettingAdmission<'budget>)->io::Result<Self>{let initial=source.initial_delivery();if initial.end()!=0||!initial.owner().admitted_by(a){return Err(io::ErrorKind::InvalidInput.into())}let mut this=Self{source,a,queue:std::array::from_fn(|_|None),head:0,len:0,pending:None,current:None,initial,eof:false,ended:false,stopped:false};
  while this.len<QUEUED&&!this.eof{match fill(this.source,this.a,None)?{Some(batch)=>{this.push(batch)?;this.eof=this.source.reached_eof()},None=>this.eof=true}}
  if !this.eof{this.pending=fill(this.source,this.a,None)?;this.eof=this.source.reached_eof();}Ok(this)
 }
 fn push(&mut self,batch:Batch)->io::Result<()>{if self.len==QUEUED{return Err(io::ErrorKind::InvalidData.into())}let at=(self.head+self.len)%QUEUED;if self.queue[at].is_some(){return Err(io::ErrorKind::InvalidData.into())}self.queue[at]=Some(batch);self.len+=1;Ok(())}
 fn pop(&mut self)->Option<Batch>{if self.len==0{return None}let batch=self.queue[self.head].take();self.head=(self.head+1)%QUEUED;self.len-=1;batch}
 fn receive(&mut self)->io::Result<Option<Batch>>{
  let batch=self.pop();if let Some(pending)=self.pending.take(){self.push(pending)?;}
  // The blocked sender resumes as soon as this receiver removes a batch.
  // Complete its next real batch BEFORE returning under this forced schedule.
  if !self.eof{self.pending=fill(self.source,self.a,None)?;self.eof=self.source.reached_eof();}
  Ok(batch)
 }
}
impl Drop for Cooperative<'_,'_,'_>{fn drop(&mut self){if !self.ended{self.source.stop()}}}
impl OriginalPreparedTokenSource for Cooperative<'_,'_,'_>{
 fn initial_delivery(&self)->OriginalDeliveryFrontier{self.initial.clone()}
 fn next_prepared(&mut self)->io::Result<Option<OriginalPreparedDeliveryToken>>{if self.stopped{return Err(io::ErrorKind::InvalidInput.into())}if self.ended{return Ok(None)}loop{if let Some(token)=self.current.as_mut().and_then(|c|c.tokens.next()){return Ok(Some(token))}self.current.take();match self.receive()?{Some(batch)=>self.current=Some(batch.cursor()),None if self.eof&&self.pending.is_none()&&self.len==0=>{self.ended=true;return Ok(None)},None=>return Err(io::ErrorKind::InvalidData.into())}}}
 fn reached_eof(&self)->bool{self.ended}
 fn actual_end(&self)->Option<OriginalProducedEnd>{if self.ended&&!self.stopped{self.source.actual_end()}else{None}}
 fn stop(&mut self){self.stopped=true;self.source.stop();self.current.take();self.pending.take();for row in &mut self.queue{row.take();}self.len=0;}
}
/// Caller/receiver need not be Send. Only the actual raw producer closure runs
/// on the existing build executor and obtains its own host-issued admission.
pub(super) fn consume_batch_primary_using<R:OriginalBatchRunner>(execution:&OriginalBatchExecution<'_>,work:&dyn SourceArenaWork,a:&SettingAdmission<'_>,consumer:&mut dyn OriginalPrimaryStreamConsumer,runner:&R)->io::Result<(OriginalPrimaryOutput,R::Metadata)>{
 if execution.executor().is_current_worker(){return cooperative(execution,work,a,consumer,runner)}
 // Conservative queue-coordinate envelope, not a claim about allocator/RSS.
 // Real token/text/batch buffers retain their own actual admitted credits.
 let _queue_credit=a.reserve(QUEUED.checked_mul(std::mem::size_of::<Message>()+8*std::mem::size_of::<usize>()).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(4096)).ok_or(io::ErrorKind::OutOfMemory)?)?;
 let signals=Signals::new();let metadata=Mutex::new(None);let(tx,rx)=sync_channel(QUEUED);
 let parsed=execution.executor().scope(|scope|{
  scope.spawn(|_|{let mut issued=0usize;let mut product=None;let result=std::panic::catch_unwind(std::panic::AssertUnwindSafe(||execution.host().with_producer_admission(&mut|pa|{issued+=1;if issued!=1{return Err(io::ErrorKind::InvalidData.into())}let mut borrowed=0;product=Some(runner.with_source(pa,&mut|source|{borrowed+=1;if borrowed!=1{return Err(io::ErrorKind::InvalidData.into())}send_batches(source,pa,&tx,&signals)})?);if borrowed!=1{return Err(io::ErrorKind::InvalidData.into())}Ok(())})));match result{Ok(Ok(()))if issued==1=>(),Ok(Ok(()))=>signals.claim(io::Error::new(io::ErrorKind::InvalidData,"batch host did not issue actual admission")),Ok(Err(error))=>{#[cfg(debug_assertions)]if std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some(){eprintln!("ORIGINAL_FATAL_STAGE=producer_admission {error:?}");}signals.claim(error)},Err(_)=>signals.claim(io::Error::new(io::ErrorKind::Other,"actual batch producer panicked"))};*metadata.lock().unwrap_or_else(std::sync::PoisonError::into_inner)=product;drop(tx);});
  let result:io::Result<OriginalPrimaryOutput>=match AsyncSource::new(rx,&signals,a){Ok(mut source)=>{match consume_prepared_primary_using(&mut source,work,a,consumer){Ok(output)=>Ok(output),Err(error)=>{#[cfg(debug_assertions)]if std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some(){eprintln!("ORIGINAL_FATAL_STAGE=receiver_consume {error:?}");}let kind=error.kind();signals.claim(error);source.stop();Err(kind.into())}}},Err(error)=>{#[cfg(debug_assertions)]if std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some(){eprintln!("ORIGINAL_FATAL_STAGE=receiver_start {error:?}");}let kind=error.kind();signals.claim(error);Err(kind.into())}};signals.cancelled.store(true,Ordering::Release);result
 });
 if let Some(error)=signals.take(){#[cfg(debug_assertions)]if std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some(){eprintln!("ORIGINAL_FATAL_STAGE=batch_first_error parsed_ok={} {error:?}",parsed.is_ok());}return Err(error)}let output=parsed?;let metadata=metadata.into_inner().map_err(|_|io::ErrorKind::Other)?.ok_or(io::ErrorKind::InvalidData)?;Ok((output,metadata))
}
fn cooperative<R:OriginalBatchRunner>(execution:&OriginalBatchExecution<'_>,work:&dyn SourceArenaWork,a:&SettingAdmission<'_>,consumer:&mut dyn OriginalPrimaryStreamConsumer,runner:&R)->io::Result<(OriginalPrimaryOutput,R::Metadata)>{
 let mut called=0;let mut parsed=None;let mut metadata=None;let mut first=None;
 let result=execution.host().with_producer_admission(&mut|pa|{called+=1;if called!=1{return Err(io::ErrorKind::InvalidData.into())}let mut borrowed=0;let product=runner.with_source(pa,&mut|source|{borrowed+=1;if borrowed!=1{return Err(io::ErrorKind::InvalidData.into())}let result=match Cooperative::new(source,pa){Ok(mut source)=>consume_prepared_primary_using(&mut source,work,a,consumer),Err(error)=>Err(error)};match result{Ok(output)=>parsed=Some(output),Err(error)=>first=Some(error)}Ok(())});metadata=Some(product?);if borrowed!=1{return Err(io::ErrorKind::InvalidData.into())}Ok(())});
 if let Some(error)=first{return Err(error)}result?;if called!=1{return Err(io::ErrorKind::InvalidData.into())}Ok((parsed.ok_or(io::ErrorKind::InvalidData)?,metadata.ok_or(io::ErrorKind::InvalidData)?))
}
#[cfg(test)]#[path="original_batch_primary_tests.rs"]mod tests;

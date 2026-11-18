//! Actual Analyze complete-batch delivery, with one bounded executor producer
//! and a caller-thread primary receiver. No private threads or parser clones.
use super::{original_batch_execution::OriginalBatchExecution,original_primary_controller::{OriginalPreparedTokenSource,OriginalPrimaryOutput,consume_prepared_primary_using},original_prepared_output::{OriginalPreparedDeliveryToken,OriginalDeliveryBatch as Batch,OriginalDeliveryBatchCursor as Cursor,OriginalOutputIdentity,OriginalDeliveryFrontier,OriginalProducedEnd},OriginalPrimaryStreamConsumer};
use crate::source_arena_credit::SourceArenaWork;
use dm_syntax::SettingAdmission;use std::{io,sync::{Mutex,atomic::{AtomicBool,Ordering},mpsc::{sync_channel,SyncSender,Receiver}}};
const UNITS:usize=8192;const QUEUED:usize=64;

#[derive(Default)]
struct BatchTrace {
    elapsed: std::time::Duration,
    calls: usize,
    cpu_ns: u128,
    cpu_samples: usize,
}

impl BatchTrace {
    fn measure<T>(&mut self, enabled: bool, work: impl FnOnce() -> T) -> T {
        if !enabled {
            return work();
        }
        let start = std::time::Instant::now();
        let cpu_start = dm_profile::sample_thread_cpu_ns();
        let result = work();
        let cpu_end = dm_profile::sample_thread_cpu_ns();
        self.record(start.elapsed(), cpu_start, cpu_end);
        result
    }

    fn record(&mut self, elapsed: std::time::Duration, cpu_start: Option<u64>, cpu_end: Option<u64>) {
        self.elapsed += elapsed;
        self.calls += 1;
        if let Some(cpu) = cpu_end.zip(cpu_start).and_then(|(end, start)| end.checked_sub(start)) {
            self.cpu_ns += u128::from(cpu);
            self.cpu_samples += 1;
        }
    }

    // Missing or non-monotonic samples must not masquerade as zero CPU work.
    fn complete_cpu_ns(&self) -> Option<u128> {
        (self.calls != 0 && self.cpu_samples == self.calls).then_some(self.cpu_ns)
    }
}

struct ProducerTrace {
    enabled: bool,
    fill: BatchTrace,
    send: BatchTrace,
}

impl Drop for ProducerTrace {
    fn drop(&mut self) {
        if self.enabled {
            eprintln!(
                "ORIGINAL_BATCH_TIMING fill_calls={} fill_s={:.3} send_calls={} send_s={:.3} fill_cpu_ns={:?} fill_cpu_samples={} send_cpu_ns={:?} send_cpu_samples={}",
                self.fill.calls, self.fill.elapsed.as_secs_f64(),
                self.send.calls, self.send.elapsed.as_secs_f64(),
                self.fill.complete_cpu_ns(), self.fill.cpu_samples,
                self.send.complete_cpu_ns(), self.send.cpu_samples,
            );
        }
    }
}
/// Actual traversal owner creates raw/notice/macro/control state INSIDE the
/// supplied fresh host admission, then finalizes its own metadata after run.
/// No callback-supplied usage vector, source hash or fabricated EOF exists.
pub(super) trait OriginalBatchRunner:Sync{
 type Metadata:Send;
 fn with_source(&self,a:&SettingAdmission<'_>,run:&mut dyn FnMut(&mut dyn OriginalPreparedTokenSource)->io::Result<()>)->io::Result<Self::Metadata>;
}

struct Signals{cancelled:AtomicBool,first:Mutex<Option<io::Error>>}
impl Signals{
 fn new()->Self{Self{cancelled:AtomicBool::new(false),first:Mutex::new(None)}}
 fn claim(&self,error:io::Error){let mut first=self.first.lock().unwrap_or_else(std::sync::PoisonError::into_inner);if first.is_none(){*first=Some(error)}}
 fn failure_kind(&self)->Option<io::ErrorKind>{self.first.lock().unwrap_or_else(std::sync::PoisonError::into_inner).as_ref().map(io::Error::kind)}
 fn take(&self)->Option<io::Error>{self.first.lock().unwrap_or_else(std::sync::PoisonError::into_inner).take()}
}
enum Message{Start(OriginalDeliveryFrontier,bool),Batch(Batch),End(Option<OriginalProducedEnd>)}
fn fill(source:&mut dyn OriginalPreparedTokenSource,owner:&OriginalOutputIdentity,a:&SettingAdmission<'_>,cancel:Option<&Signals>)->io::Result<Option<Batch>>{
 let mut batch=Batch::new(owner,a)?;
 while batch.len()<UNITS{
  if cancel.is_some_and(|s|s.cancelled.load(Ordering::Acquire)){source.stop();return Ok(None)}
  #[cfg(feature="original-fill-sample")]
  let _row_sample=super::original_fill_sample::row(batch.len());
  a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;
  match source.next_prepared()?{Some(token)=>original_fill_bucket!(BatchPush,batch.push(token,a))?,None if source.reached_eof()=>break,None=>return Err(io::Error::new(io::ErrorKind::InvalidData,"batch producer pause is not actual EOF"))}
 }
 if batch.len()==0{return Ok(None)}
 let mut batch=batch.seal_using(a)?;
 let geometry=source.batch_token_pages(owner,batch.end(),batch.len(),a)?;
 batch.install_geometry(geometry);
 Ok(Some(batch))
}
fn send_batches(source:&mut dyn OriginalPreparedTokenSource,a:&SettingAdmission<'_>,tx:&SyncSender<Message>,signals:&Signals,trace_enabled:bool)->io::Result<()>{
 let mut trace=ProducerTrace{enabled:trace_enabled,fill:BatchTrace::default(),send:BatchTrace::default()};
 let initial=source.initial_delivery();
 if tx.send(Message::Start(initial.clone(),source.projects_body_spelling())).is_err(){source.stop();return Ok(())}
 #[cfg(feature="original-fill-sample")]
 let mut batch_sampler=super::original_fill_sample::Sampler::from_environment();
 loop{let next=trace.fill.measure(trace_enabled,||{
  #[cfg(feature="original-fill-sample")]
  let mut batch_sample=batch_sampler.next();
  let result=fill(source,initial.owner(),a,Some(signals));
  #[cfg(feature="original-fill-sample")]
  if let Some(sample)=&mut batch_sample{
   sample.finished_rows(result.as_ref().ok().map(|batch|batch.as_ref().map_or(0,Batch::len)));
  }
  result
 })?;if signals.cancelled.load(Ordering::Acquire){source.stop();return Ok(())}match next{Some(batch)=>if trace.send.measure(trace_enabled,||tx.send(Message::Batch(batch))).is_err(){source.stop();return Ok(())},None if source.reached_eof()=>{let _=tx.send(Message::End(source.actual_end()));return Ok(())},None=>{source.stop();return Ok(())}}}
}
struct AsyncSource<'a,'budget>{rx:Option<Receiver<Message>>,current:Option<Cursor>,initial:OriginalDeliveryFrontier,signals:&'a Signals,a:&'a SettingAdmission<'budget>,trace_enabled:bool,receive:BatchTrace,actual_end:Option<OriginalProducedEnd>,ended:bool,stopped:bool,project_body_spelling:bool}
impl<'a,'budget> AsyncSource<'a,'budget>{
 fn new(rx:Receiver<Message>,signals:&'a Signals,a:&'a SettingAdmission<'budget>,trace_enabled:bool)->io::Result<Self>{let(initial,project_body_spelling)=match rx.recv(){Ok(Message::Start(start,project))if start.end()==0&&start.owner().admitted_by(a)=>(start,project),Ok(_)=>return Err(io::ErrorKind::InvalidData.into()),Err(_)=>return Err(io::Error::new(io::ErrorKind::UnexpectedEof,"actual producer ended before its batch start"))};Ok(Self{rx:Some(rx),current:None,initial,signals,a,trace_enabled,receive:BatchTrace::default(),actual_end:None,ended:false,stopped:false,project_body_spelling})}
}
impl Drop for AsyncSource<'_,'_>{fn drop(&mut self){self.signals.cancelled.store(true,Ordering::Release);self.rx.take();
 if self.trace_enabled {
    eprintln!("ORIGINAL_BATCH_TIMING recv_calls={} recv_s={:.3} recv_cpu_ns={:?} recv_cpu_samples={}",self.receive.calls,self.receive.elapsed.as_secs_f64(),self.receive.complete_cpu_ns(),self.receive.cpu_samples);
 }
}}
impl OriginalPreparedTokenSource for AsyncSource<'_,'_>{
 fn projects_body_spelling(&self)->bool{self.project_body_spelling}
 fn initial_delivery(&self)->OriginalDeliveryFrontier{self.initial.clone()}
 fn next_prepared(&mut self)->io::Result<Option<OriginalPreparedDeliveryToken>>{
  if self.stopped{return Err(io::ErrorKind::InvalidInput.into())}if self.ended{return Ok(None)}
  loop{if let Some(cursor)=&mut self.current{if let Some(token)=cursor.next(self.a)?{return Ok(Some(token))}}self.current.take();let rx=self.rx.as_ref().ok_or(io::ErrorKind::InvalidInput)?;match self.receive.measure(self.trace_enabled,||rx.recv()){Ok(Message::Batch(batch))=>{if batch.len()==0||batch.len()>UNITS{return Err(io::ErrorKind::InvalidData.into())}self.current=Some(batch.cursor())},Ok(Message::End(actual))=>{self.actual_end=actual;self.ended=true;return Ok(None)},Ok(Message::Start(..))=>return Err(io::ErrorKind::InvalidData.into()),Err(_)=>return Err(io::Error::new(io::ErrorKind::UnexpectedEof,"actual batch producer disconnected before EOF"))}}
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
  while this.len<QUEUED&&!this.eof{match fill(this.source,this.initial.owner(),this.a,None)?{Some(batch)=>{this.push(batch)?;this.eof=this.source.reached_eof()},None=>this.eof=true}}
  if !this.eof{this.pending=fill(this.source,this.initial.owner(),this.a,None)?;this.eof=this.source.reached_eof();}Ok(this)
 }
 fn push(&mut self,batch:Batch)->io::Result<()>{if self.len==QUEUED{return Err(io::ErrorKind::InvalidData.into())}let at=(self.head+self.len)%QUEUED;if self.queue[at].is_some(){return Err(io::ErrorKind::InvalidData.into())}self.queue[at]=Some(batch);self.len+=1;Ok(())}
 fn pop(&mut self)->Option<Batch>{if self.len==0{return None}let batch=self.queue[self.head].take();self.head=(self.head+1)%QUEUED;self.len-=1;batch}
 fn receive(&mut self)->io::Result<Option<Batch>>{
  let batch=self.pop();if let Some(pending)=self.pending.take(){self.push(pending)?;}
  // The blocked sender resumes as soon as this receiver removes a batch.
  // Complete its next real batch BEFORE returning under this forced schedule.
  if !self.eof{self.pending=fill(self.source,self.initial.owner(),self.a,None)?;self.eof=self.source.reached_eof();}
  Ok(batch)
 }
}
impl Drop for Cooperative<'_,'_,'_>{fn drop(&mut self){if !self.ended{self.source.stop()}}}
impl OriginalPreparedTokenSource for Cooperative<'_,'_,'_>{
 fn projects_body_spelling(&self)->bool{self.source.projects_body_spelling()}
 fn initial_delivery(&self)->OriginalDeliveryFrontier{self.initial.clone()}
 fn next_prepared(&mut self)->io::Result<Option<OriginalPreparedDeliveryToken>>{if self.stopped{return Err(io::ErrorKind::InvalidInput.into())}if self.ended{return Ok(None)}loop{if let Some(cursor)=&mut self.current{if let Some(token)=cursor.next(self.a)?{return Ok(Some(token))}}self.current.take();match self.receive()?{Some(batch)=>self.current=Some(batch.cursor()),None if self.eof&&self.pending.is_none()&&self.len==0=>{self.ended=true;return Ok(None)},None=>return Err(io::ErrorKind::InvalidData.into())}}}
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
 let trace_enabled=dm_profile::detail_enabled()||(cfg!(debug_assertions)&&std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some());
 let parsed=execution.executor().scope(|scope|{
  scope.spawn(|_|{let start=trace_enabled.then(std::time::Instant::now);let mut issued=0usize;let mut product=None;let result=std::panic::catch_unwind(std::panic::AssertUnwindSafe(||execution.host().with_producer_admission(&mut|pa|{issued+=1;if issued!=1{return Err(io::ErrorKind::InvalidData.into())}let mut borrowed=0;product=Some(runner.with_source(pa,&mut|source|{borrowed+=1;if borrowed!=1{return Err(io::ErrorKind::InvalidData.into())}send_batches(source,pa,&tx,&signals,trace_enabled)?;
   // An intentional header stop still needs its real prefix metadata. A
   // receiver error has no product to finalize, and the signal owns the
   // exact original error while the producer releases its staged state.
   if let Some(kind)=signals.failure_kind(){return Err(kind.into())}
   Ok(())
  })?);if borrowed!=1{return Err(io::ErrorKind::InvalidData.into())}Ok(())})));match result{Ok(Ok(()))if issued==1=>(),Ok(Ok(()))=>signals.claim(io::Error::new(io::ErrorKind::InvalidData,"batch host did not issue actual admission")),Ok(Err(error))=>{#[cfg(debug_assertions)]if std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some(){eprintln!("ORIGINAL_FATAL_STAGE=producer_admission {error:?}");}signals.claim(error)},Err(_)=>signals.claim(io::Error::new(io::ErrorKind::Other,"actual batch producer panicked"))};if let Some(start)=start {
    eprintln!("ORIGINAL_BATCH_TIMING producer_total_s={:.3}",start.elapsed().as_secs_f64());
   }
   *metadata.lock().unwrap_or_else(std::sync::PoisonError::into_inner)=product;drop(tx);});
  let result:io::Result<OriginalPrimaryOutput>=match AsyncSource::new(rx,&signals,a,trace_enabled){Ok(mut source)=>{match consume_prepared_primary_using(&mut source,work,a,consumer){Ok(output)=>Ok(output),Err(error)=>{#[cfg(debug_assertions)]if std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some(){eprintln!("ORIGINAL_FATAL_STAGE=receiver_consume {error:?}");}let kind=error.kind();signals.claim(error);source.stop();Err(kind.into())}}},Err(error)=>{#[cfg(debug_assertions)]if std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some(){eprintln!("ORIGINAL_FATAL_STAGE=receiver_start {error:?}");}let kind=error.kind();signals.claim(error);Err(kind.into())}};signals.cancelled.store(true,Ordering::Release);result
 });
 if let Some(error)=signals.take(){#[cfg(debug_assertions)]if std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some(){eprintln!("ORIGINAL_FATAL_STAGE=batch_first_error parsed_ok={} {error:?}",parsed.is_ok());}return Err(error)}let output=parsed?;let metadata=metadata.into_inner().map_err(|_|io::ErrorKind::Other)?.ok_or(io::ErrorKind::InvalidData)?;Ok((output,metadata))
}
fn cooperative<R:OriginalBatchRunner>(execution:&OriginalBatchExecution<'_>,work:&dyn SourceArenaWork,a:&SettingAdmission<'_>,consumer:&mut dyn OriginalPrimaryStreamConsumer,runner:&R)->io::Result<(OriginalPrimaryOutput,R::Metadata)>{
 let mut called=0;let mut parsed=None;let mut metadata=None;let mut first=None;
 let result=execution.host().with_producer_admission(&mut|pa|{called+=1;if called!=1{return Err(io::ErrorKind::InvalidData.into())}let mut borrowed=0;let product=runner.with_source(pa,&mut|source|{borrowed+=1;if borrowed!=1{return Err(io::ErrorKind::InvalidData.into())}let result=match Cooperative::new(source,pa){Ok(mut source)=>consume_prepared_primary_using(&mut source,work,a,consumer),Err(error)=>Err(error)};match result{Ok(output)=>{parsed=Some(output);Ok(())},Err(error)=>{let kind=error.kind();first=Some(error);Err(kind.into())}}});metadata=Some(product?);if borrowed!=1{return Err(io::ErrorKind::InvalidData.into())}Ok(())});
 if let Some(error)=first{return Err(error)}result?;if called!=1{return Err(io::ErrorKind::InvalidData.into())}Ok((parsed.ok_or(io::ErrorKind::InvalidData)?,metadata.ok_or(io::ErrorKind::InvalidData)?))
}
#[cfg(test)]#[path="original_batch_primary_tests.rs"]mod tests;

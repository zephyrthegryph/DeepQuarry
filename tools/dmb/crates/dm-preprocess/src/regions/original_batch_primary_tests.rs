use super::*;
use super::super::{original_prepared_output::OriginalOutputCursor,original_primary_controller::OriginalPreparedTokenSource};
use crate::{SourceProvider,macro_expansion::{OriginalMacroToken as Token,OriginalMacroValue as Value,OriginalMacroTextValue as Text,OriginalMacroOrigin as Origin}};
use std::{path::Path,sync::{Arc,atomic::AtomicUsize}};
struct Provider;impl SourceProvider for Provider{fn read(&self,_:&Path)->Result<String,String>{panic!("actual generated-token control must not acquire files")}}
struct Host{used:Arc<dm_syntax::SettingChargeCounter>,limit:usize}
impl super::super::original_batch_execution::OriginalBatchSyntaxHost for Host{fn with_producer_admission(&self,run:&mut dyn FnMut(&SettingAdmission<'_>)->io::Result<()>)->io::Result<()>{let poll=||Ok(());let a=SettingAdmission::new(&self.used,self.limit,&poll);run(&a).map_err(|e|a.take_operational_error().unwrap_or(e))}}
struct Seed<'a,'budget>{cursor:OriginalOutputCursor,initial:OriginalDeliveryFrontier,a:&'a SettingAdmission<'budget>,count:usize,at:usize,fail:Option<usize>,ended:bool,stopped:bool,visits:Arc<AtomicUsize>}
impl<'a,'budget> Seed<'a,'budget>{fn new(a:&'a SettingAdmission<'budget>,count:usize,fail:Option<usize>,visits:Arc<AtomicUsize>)->io::Result<Self>{let cursor=OriginalOutputCursor::new(a)?;let initial=cursor.initial_delivery()?;Ok(Self{cursor,initial,a,count,at:0,fail,ended:false,stopped:false,visits})}}
impl OriginalPreparedTokenSource for Seed<'_,'_>{
 fn initial_delivery(&self)->OriginalDeliveryFrontier{self.initial.clone()}
 fn next_prepared(&mut self)->io::Result<Option<OriginalPreparedDeliveryToken>>{if self.stopped{return Err(io::ErrorKind::InvalidInput.into())}if self.fail==Some(self.at){return Err(io::Error::from_raw_os_error(1450))}if self.at==self.count{self.ended=true;return Ok(None)}let value=match self.at{0=>Value::Punct("/"),1=>Value::Ident{spelling:Text::Borrowed("proc"),whitespace:false},2=>Value::Punct("/"),3=>Value::Ident{spelling:Text::Borrowed("probe"),whitespace:false},4=>Value::Punct("("),5=>Value::Punct(")"),_=>Value::Punct("\n")};let actual=Token{string_mode:dm_syntax::OriginalStringMode::Unknown,punctuation_close:false,lexical_frame:None,lexical_span:None,raw_spelling:None,value,origin:Origin{physical:dm_syntax::Span::new(self.at,self.at+1),line:self.at+1,byte_column:Some(0),occurrence:0,invocation:false}};let token=self.cursor.prepare(actual,&Provider,self.a)?;self.at+=1;self.visits.store(self.at,Ordering::Release);Ok(Some(token.into_delivery()))}
 fn reached_eof(&self)->bool{self.ended}
 fn stop(&mut self){self.stopped=true;}
}
struct Runner{count:usize,fail:Option<usize>,visits:Arc<AtomicUsize>}
impl OriginalBatchRunner for Runner{type Metadata=(usize,bool);fn with_source(&self,a:&SettingAdmission<'_>,run:&mut dyn FnMut(&mut dyn OriginalPreparedTokenSource)->io::Result<()>)->io::Result<Self::Metadata>{let mut source=Seed::new(a,self.count,self.fail,self.visits.clone())?;run(&mut source)?;Ok((source.at,source.ended))}}
struct Consumer{headers:usize,stop:bool}
impl dm_syntax::OriginalDeclarationHeaderObserver for Consumer{fn header(&mut self,_:dm_syntax::OriginalPrimaryHeader<'_>)->io::Result<dm_syntax::OriginalHeaderFlow>{self.headers+=1;Ok(if self.stop{dm_syntax::OriginalHeaderFlow::Stop}else{dm_syntax::OriginalHeaderFlow::Continue})}}
impl OriginalPrimaryStreamConsumer for Consumer{fn callable(&mut self,_:dm_syntax::OriginalPrimaryLiveHeader,source:&mut dyn super::super::OriginalFormalTokenStream)->io::Result<dm_syntax::OriginalHeaderFlow>{
 // A live callable header is the actual observable entry. This fixed empty
 // signature consumes its genuine closing token; no second formal parser.
 self.headers+=1;let close=source.next_header_token()?.ok_or(io::ErrorKind::UnexpectedEof)?;assert_eq!(close.text,")");assert!(matches!(source.current_header_value(dm_syntax::SpanToken{kind:close.kind,span:close.span})?,dm_syntax::OriginalTokenValue::Punct(")")));Ok(if self.stop{dm_syntax::OriginalHeaderFlow::Stop}else{dm_syntax::OriginalHeaderFlow::Continue})
}}
#[derive(Default)]struct SourceCreditState(AtomicUsize);struct Credit{bytes:AtomicUsize,state:Arc<SourceCreditState>}
impl Drop for Credit{fn drop(&mut self){self.state.0.fetch_sub(self.bytes.load(Ordering::Acquire),Ordering::AcqRel);}}
impl crate::source_arena_credit::SourceArenaCreditOwner for Credit{fn as_any(&self)->&dyn std::any::Any{self}fn reserved_bytes(&self)->usize{self.bytes.load(Ordering::Acquire)}fn visit_storage(&self,_:&mut dyn FnMut(usize,usize)){}}
struct Work(Arc<SourceCreditState>);
impl Work{fn actual<'a>(&self,c:&'a crate::source_arena_credit::SourceArenaCredit)->io::Result<&'a Credit>{let c=c.owner().as_any().downcast_ref::<Credit>().ok_or(io::ErrorKind::InvalidInput)?;if !Arc::ptr_eq(&c.state,&self.0){return Err(io::ErrorKind::InvalidInput.into())}Ok(c)}}
impl SourceArenaWork for Work{
 fn checkpoint(&self)->io::Result<()>{Ok(())}
 fn reserve(&self,n:usize)->io::Result<crate::source_arena_credit::SourceArenaCredit>{self.0.0.fetch_add(n,Ordering::AcqRel);Ok(crate::source_arena_credit::SourceArenaCredit::from_resource_owner(Arc::new(Credit{bytes:AtomicUsize::new(n),state:self.0.clone()})))}
 fn grow(&self,c:&mut crate::source_arena_credit::SourceArenaCredit,n:usize)->io::Result<()>{let c=self.actual(c)?;c.bytes.fetch_add(n,Ordering::AcqRel);self.0.0.fetch_add(n,Ordering::AcqRel);Ok(())}
 fn shrink(&self,c:&mut crate::source_arena_credit::SourceArenaCredit,n:usize)->io::Result<()>{let c=self.actual(c)?;c.bytes.fetch_update(Ordering::AcqRel,Ordering::Acquire,|v|v.checked_sub(n)).map_err(|_|io::ErrorKind::InvalidInput)?;self.0.0.fetch_sub(n,Ordering::AcqRel);Ok(())}
}
fn check_small(executor:&dm_exec::BuildExecutor,stop:bool){let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let host=Host{used:used.clone(),limit:64<<20};let poll=||Ok(());let a=SettingAdmission::new(&used,host.limit,&poll);let work=Work(Arc::new(SourceCreditState::default()));let execution=OriginalBatchExecution::new(&Provider,&host,executor);let runner=Runner{count:8,fail:None,visits:Arc::new(AtomicUsize::new(0))};let mut consumer=Consumer{headers:0,stop};let(output,metadata)=consume_batch_primary_using(&execution,&work,&a,&mut consumer,&runner).unwrap();assert_eq!(metadata,(8,true));assert_eq!(output.consumed_eof,!stop,"producer read-ahead EOF cannot become receiver EOF after parser stop");assert!(consumer.headers>0);drop(output);assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert_eq!(work.0.0.load(Ordering::Acquire),0);}
#[test]fn genuine_bounded_batch_external_one_worker_handles_short_eof_and_early_parser_stop(){let executor=dm_exec::BuildExecutor::new(1).unwrap();assert!(!executor.is_current_worker());check_small(&executor,false);check_small(&executor,true);}
#[test]fn genuine_bounded_batch_nested_one_worker_and_saturated_two_workers_never_wait_for_their_own_pool(){for workers in[1,2]{let executor=dm_exec::BuildExecutor::new(workers).unwrap();let barrier=std::sync::Barrier::new(workers);let passes=AtomicUsize::new(0);executor.scope(|scope|{for _ in 0..workers{let executor=&executor;let barrier=&barrier;let passes=&passes;scope.spawn(move|_|{assert!(executor.is_current_worker());barrier.wait();check_small(executor,false);check_small(executor,true);passes.fetch_add(1,Ordering::AcqRel);});}});assert_eq!(passes.load(Ordering::Acquire),workers);}}
#[test]fn genuine_first_batch_error_discards_partial_tokens_before_any_parser_callback(){let executor=dm_exec::BuildExecutor::new(1).unwrap();let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let host=Host{used:used.clone(),limit:64<<20};let a=SettingAdmission::new(&used,host.limit,&||Ok(()));let work=Work(Arc::new(SourceCreditState::default()));let execution=OriginalBatchExecution::new(&Provider,&host,&executor);let runner=Runner{count:UNITS+20,fail:Some(100),visits:Arc::new(AtomicUsize::new(0))};let mut consumer=Consumer{headers:0,stop:true};assert_eq!(consume_batch_primary_using(&execution,&work,&a,&mut consumer,&runner).err().unwrap().raw_os_error(),Some(1450));assert_eq!(consumer.headers,0);assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert_eq!(work.0.0.load(Ordering::Acquire),0);}
#[test]fn cooperative_prefetch_is_the_valid_forced_old64_plus_blocked_sender_schedule_not_whole_stream(){
 // Literal old8192/64 send loop, forced to let the sender run before parser work.
 let executor=dm_exec::BuildExecutor::new(1).unwrap();let(tx,rx)=sync_channel(QUEUED);let(progress,ready)=sync_channel(1);let old_count=AtomicUsize::new(0);
 executor.scope(|scope|{scope.spawn(|_|{let mut batch=Vec::with_capacity(UNITS);for token in 0..UNITS*67{batch.push(token);old_count.fetch_add(1,Ordering::AcqRel);if batch.len()==UNITS{let blocks=old_count.load(Ordering::Acquire)/UNITS;if blocks==65||blocks==66{progress.send(blocks).unwrap();}if tx.send(std::mem::replace(&mut batch,Vec::with_capacity(UNITS))).is_err(){break;}}}});assert_eq!(ready.recv().unwrap(),65);let first=rx.recv().unwrap();assert_eq!(first.len(),UNITS);assert_eq!(ready.recv().unwrap(),66);drop(first);drop(rx);});assert_eq!(old_count.load(Ordering::Acquire),UNITS*66);
 // Admit the actual compact buffers, including one half-full old buffer
 // during a real Vec growth. This bound excludes the old raw-token rows.
 let row = Batch::row_bytes();
 let old_row = std::mem::size_of::<OriginalPreparedDeliveryToken>();
 #[cfg(target_pointer_width = "64")]
 assert!(row <= old_row - 24, "batch owns one actual cursor and aggregate text credit");
 let batch_units = UNITS * (QUEUED + 1);
 let limit = (batch_units + UNITS) * (row + 4) + UNITS / 2 * row + (1 << 20);
 assert!(limit < batch_units * old_row, "the old producer payload cannot fit under this same bound");
 let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,dm_syntax::SettingChargeCounter::root_allocation_bytes() + (limit),&||Ok(()));let visits=Arc::new(AtomicUsize::new(0));let mut source=Seed::new(&a,UNITS*67,None,visits.clone()).unwrap();let mut cooperative=Cooperative::new(&mut source,&a).unwrap();assert_eq!(visits.load(Ordering::Acquire),UNITS*65);drop(cooperative.next_prepared().unwrap().unwrap());assert_eq!(visits.load(Ordering::Acquire),old_count.load(Ordering::Acquire));assert!(!cooperative.reached_eof());cooperative.stop();drop(cooperative);drop(source);assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
}
#[test]fn equal_spelling_and_same_budget_never_substitute_another_actual_output_owner(){let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,64<<20,&||Ok(()));let work=Work(Arc::new(SourceCreditState::default()));let mut one=Seed::new(&a,8,None,Arc::new(AtomicUsize::new(0))).unwrap();let two=Seed::new(&a,8,None,Arc::new(AtomicUsize::new(0))).unwrap();one.initial=two.initial_delivery();let mut consumer=Consumer{headers:0,stop:false};assert_eq!(consume_prepared_primary_using(&mut one,&work,&a,&mut consumer).err().unwrap().kind(),io::ErrorKind::InvalidInput);drop((one,two));assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert_eq!(work.0.0.load(Ordering::Acquire),0);}
#[test]
fn queue_rejects_foreign_actual_cursor_and_preserves_first_transfer_error() {
 let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
 let a=SettingAdmission::new(&used,64<<20,&||Ok(()));
 let mut one=Seed::new(&a,8,None,Arc::new(AtomicUsize::new(0))).unwrap();
 let two=Seed::new(&a,8,None,Arc::new(AtomicUsize::new(0))).unwrap();
 assert_eq!(fill(&mut one,two.initial.owner(),&a,None).err().unwrap().kind(),io::ErrorKind::InvalidInput);
 assert_eq!(one.at,1,"rejection follows that actual pull and prevents later producer reads");
 let mut current=Seed::new(&a,8,None,Arc::new(AtomicUsize::new(0))).unwrap();
 let initial=current.initial_delivery();
 let batch=fill(&mut current,initial.owner(),&a,None).unwrap().unwrap();
 let mut cursor=batch.cursor();
 let failed=SettingAdmission::new(&used,64<<20,&||Err(io::Error::from_raw_os_error(1450)));
 assert_eq!(cursor.next(&failed).err().unwrap().raw_os_error(),Some(1450));
 drop((cursor,current,initial,one,two));
 assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
}
#[test]fn cooperative_later_batch_fault_precedes_parser_under_its_forced_fastest_old_schedule(){let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,64<<20,&||Ok(()));let mut source=Seed::new(&a,UNITS*3,Some(UNITS+10),Arc::new(AtomicUsize::new(0))).unwrap();assert_eq!(Cooperative::new(&mut source,&a).err().unwrap().raw_os_error(),Some(1450));drop(source);assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());}
#[test]fn queued_later_batch_io_survives_receiver_stop_and_later_cancellation(){let executor=dm_exec::BuildExecutor::new(1).unwrap();let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let poll=||Ok(());let a=SettingAdmission::new(&used,64<<20,&poll);let(tx,rx)=sync_channel(QUEUED);let signals=Signals::new();let(done,completed)=sync_channel(0);executor.scope(|scope|{let used=&used;let signals=&signals;scope.spawn(move|_|{let pa=SettingAdmission::new(used,64<<20,&||Ok(()));let mut source=Seed::new(&pa,UNITS*3,Some(UNITS+10),Arc::new(AtomicUsize::new(0))).unwrap();let error=send_batches(&mut source,&pa,&tx,signals,true).unwrap_err();signals.claim(error);done.send(()).unwrap();});completed.recv().unwrap();let mut source=AsyncSource::new(rx,&signals,&a,true).unwrap();drop(source.next_prepared().unwrap().unwrap());source.stop();drop(source);});signals.claim(io::Error::new(io::ErrorKind::Interrupted,"later cancellation"));assert_eq!(signals.take().unwrap().raw_os_error(),Some(1450));assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());}

#[test]
fn receiver_io_failure_skips_unusable_metadata_in_both_batch_schedules() {
    struct Finalizer<'a> {
        tokens: usize,
        finalized: &'a AtomicUsize,
    }
    impl OriginalBatchRunner for Finalizer<'_> {
        type Metadata = ();

        fn with_source(
            &self,
            admission: &SettingAdmission<'_>,
            run: &mut dyn FnMut(&mut dyn OriginalPreparedTokenSource) -> io::Result<()>,
        ) -> io::Result<()> {
            let mut source = Seed::new(admission, self.tokens, None, Arc::new(AtomicUsize::new(0)))?;
            run(&mut source)?;
            self.finalized.fetch_add(1, Ordering::Relaxed);
            Ok(())
        }
    }

    struct FailingConsumer;
    impl dm_syntax::OriginalDeclarationHeaderObserver for FailingConsumer {
        fn header(
            &mut self,
            _: dm_syntax::OriginalPrimaryHeader<'_>,
        ) -> io::Result<dm_syntax::OriginalHeaderFlow> {
            Err(io::Error::from_raw_os_error(1450))
        }
    }
    impl OriginalPrimaryStreamConsumer for FailingConsumer {
        fn callable(
            &mut self,
            _: dm_syntax::OriginalPrimaryLiveHeader,
            _: &mut dyn super::super::OriginalFormalTokenStream,
        ) -> io::Result<dm_syntax::OriginalHeaderFlow> {
            Err(io::Error::from_raw_os_error(1450))
        }
    }

    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let run = |tokens| {
        let used = dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let host = Host { used: Arc::clone(&used), limit: 64 << 20 };
        let admission = SettingAdmission::new(&used, host.limit, &|| Ok(()));
        let work = Work(Arc::new(SourceCreditState::default()));
        let execution = OriginalBatchExecution::new(&Provider, &host, &executor);
        let finalized = AtomicUsize::new(0);
        let runner = Finalizer { tokens, finalized: &finalized };
        let error = consume_batch_primary_using(&execution, &work, &admission, &mut FailingConsumer, &runner)
            .err()
            .expect("actual receiver I/O failure");
        assert_eq!(error.raw_os_error(), Some(1450));
        assert_eq!(finalized.load(Ordering::Relaxed), 0);
        assert_eq!(used.load(Ordering::Acquire), dm_syntax::SettingChargeCounter::root_allocation_bytes());
        assert_eq!(work.0.0.load(Ordering::Acquire), 0);
    };

    // An external producer cannot reach EOF before the receiver stops it.
    run(UNITS * (QUEUED + 2));
    executor.scope(|scope| scope.spawn(|_| run(8)));
}

#[test]
fn batch_trace_cpu_totals_require_complete_monotonic_samples_and_preserve_work_results() {
    let mut trace = BatchTrace::default();
    assert_eq!(trace.complete_cpu_ns(), None);
    trace.record(std::time::Duration::from_millis(4), Some(10), Some(13));
    trace.record(std::time::Duration::from_millis(6), Some(20), Some(27));
    assert_eq!(trace.calls, 2);
    assert_eq!(trace.elapsed, std::time::Duration::from_millis(10));
    assert_eq!(trace.cpu_samples, 2);
    assert_eq!(trace.complete_cpu_ns(), Some(10));
    for (start, end) in [(None, Some(40)), (Some(30), None), (Some(50), Some(49))] {
        let mut partial = BatchTrace::default();
        partial.record(std::time::Duration::from_millis(1), Some(1), Some(2));
        partial.record(std::time::Duration::from_millis(2), start, end);
        assert_eq!(partial.calls, 2);
        assert_eq!(partial.elapsed, std::time::Duration::from_millis(3));
        assert_eq!(partial.cpu_samples, 1);
        assert_eq!(partial.cpu_ns, 1);
        assert_eq!(partial.complete_cpu_ns(), None);
    }
    let mut disabled = BatchTrace::default();
    let error = disabled.measure(false, || Err::<(), _>(io::Error::from_raw_os_error(1450))).unwrap_err();
    assert_eq!(error.raw_os_error(), Some(1450));
    assert_eq!(disabled.calls, 0);
    let error = disabled.measure(true, || Err::<(), _>(io::Error::from_raw_os_error(1450))).unwrap_err();
    assert_eq!(error.raw_os_error(), Some(1450));
    assert_eq!(disabled.calls, 1);
}

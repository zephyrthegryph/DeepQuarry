//! Operation-local requested CHECK observations on the actual selected owner.
//! No source/cache/parser/currentness authority is created by this object.
use std::{collections::{HashSet,BTreeSet,BTreeMap},io::{self,Write},path::Path,sync::{Arc,Mutex},time::{Duration,Instant}};
use dm_preprocess::source_arena_credit::{SourceArenaWork,SourceArenaCredit};
pub(crate) struct TimingRow{pub(crate) name:&'static str,pub(crate) total:Duration,pub(crate) files:usize,pub(crate) rescanned:usize,pub(crate) memo:bool}
pub(crate) struct Allocation{_credit:Mutex<SourceArenaCredit>}
pub(crate) struct Delivery{pub(crate) binding:dq_analyze::selected_exclusions_wire::Hex128,pub(crate) usage:Option<crate::selected_report_spool::Verified>,pub(crate) usage_requested:bool,_allocation:Arc<Allocation>}
pub(crate) struct Observations{request:dq_analyze::native_check_cli_wire::Request,changed:Option<HashSet<String>>,started:Instant,preparation:std::sync::OnceLock<Duration>,rows:Mutex<Vec<TimingRow>>,selected:usize,timing:Mutex<Option<crate::selected_report_spool::Stage>>,timing_written:std::sync::atomic::AtomicBool,usage:Mutex<Option<crate::selected_report_spool::Stage>>,usage_completed:std::sync::atomic::AtomicBool,_allocation:Arc<Allocation>}
fn oom()->io::Error{io::ErrorKind::OutOfMemory.into()}
impl Observations{
 pub(crate)fn issue(request:&dq_analyze::native_check_cli_wire::Request,selected:usize,cache:&Path,work:&dyn SourceArenaWork)->io::Result<Box<Self>>{
  work.checkpoint()?;let paths=request.changed.as_ref().map_or(0,Vec::len);let text=request.changed.as_ref().map_or(Ok(0),|paths|paths.iter().try_fold(0usize,|n,p|n.checked_add(p.len()).ok_or_else(oom)))?;
  let(layout,_)=std::alloc::Layout::new::<[std::sync::atomic::AtomicUsize;2]>().extend(std::alloc::Layout::new::<Allocation>()).map_err(|_|oom())?;
  let width=std::mem::size_of::<Self>().checked_add(layout.pad_to_align().size()).and_then(|n|n.checked_add(request.metadata_charge().ok()?)).and_then(|n|n.checked_add(paths.checked_mul(1024)?)).and_then(|n|n.checked_add(text.checked_mul(4)?)).and_then(|n|n.checked_add(selected.checked_mul(4*std::mem::size_of::<TimingRow>())?)).and_then(|n|n.checked_add(cache.as_os_str().len().checked_mul(8)?)).and_then(|n|n.checked_add(8192)).ok_or_else(oom)?;
  let credit=work.reserve(width)?;let request=request.clone();let mut changed=None;if let Some(paths)=&request.changed{let mut set=HashSet::new();set.try_reserve(paths.len()).map_err(|_|oom())?;if set.capacity()>paths.len().saturating_mul(8).saturating_add(16){return Err(oom())}for p in paths{work.checkpoint()?;set.insert(p.clone());}changed=Some(set)}
  let mut rows=Vec::new();if request.timing{rows.try_reserve_exact(selected).map_err(|_|oom())?;if rows.capacity()>selected.saturating_mul(4){return Err(oom())}}
  let timing=if request.timing{Some(crate::selected_report_spool::Stage::new(cache)?)}else{None};
  let usage=if request.allow_usage{Some(crate::selected_report_spool::Stage::new(cache)?)}else{None};work.checkpoint()?;
  Ok(Box::new(Self{request,changed,started:Instant::now(),preparation:std::sync::OnceLock::new(),rows:Mutex::new(rows),selected,timing:Mutex::new(timing),timing_written:false.into(),usage:Mutex::new(usage),usage_completed:false.into(),_allocation:Arc::new(Allocation{_credit:Mutex::new(credit)})}))
 }
 pub(crate)fn finish_report(&self,report:crate::selected_report_spool::Verified)->io::Result<crate::selected_report_spool::Verified>{
  if !self.request.timing{return Ok(report)}if !self.timing_written.load(std::sync::atomic::Ordering::Acquire){return Err(io::Error::new(io::ErrorKind::InvalidData,"actual CHECK producer did not reach its typed timing/result boundary"))}
  if !self.request.timing_only{return Ok(report)}drop(report);let stage=self.timing.lock().map_err(|_|io::Error::other("CHECK timing staging poisoned"))?.take().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"CHECK timing output was already consumed"))?;crate::request_runner::native_check_handlers::check_diagnostic_stage(stage)
 }
 pub(crate)fn before_result(&self,output:&mut impl Write)->io::Result<()>{
  if !self.request.timing{return Ok(())}if self.timing_written.swap(true,std::sync::atomic::Ordering::AcqRel){return Err(io::Error::new(io::ErrorKind::InvalidData,"CHECK timing/result boundary completed twice"))}
  if self.request.timing_only{let mut stage=self.timing.lock().map_err(|_|io::Error::other("CHECK timing staging poisoned"))?;self.write_timing(stage.as_mut().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"CHECK timing staging disappeared"))?)?;}else{self.write_timing(output)?;}Ok(())
 }
 fn write_timing(&self,output:&mut impl Write)->io::Result<()>{
  let preparation=*self.preparation.get().ok_or_else(||io::Error::new(io::ErrorKind::InvalidData,"timing request lacks actual preparation observation"))?;
  let mut rows=self.rows.lock().map_err(|_|io::Error::other("CHECK timing observation poisoned"))?;if rows.len()!=self.selected{return Err(io::Error::new(io::ErrorKind::InvalidData,"timing request lacks an actual completed observation for every selected producer"))}
  // Measured native phases: raw columns count actual raw visits/scans only;
  // query reuse comes from actual graph statistics. No legacy cache estimate.
  rows.sort_unstable_by(|a,b|b.total.cmp(&a.total).then_with(||a.name.cmp(b.name)));
  writeln!(output,"\n-- native CHECK timing (actual preparation {:.0?}; raw-file columns cover raw producers only) --",preparation)?;
  writeln!(output,"{:<30} {:>9} {:>9} {:>9} {:>10}","lint","time","raw files","raw scans","query reuse")?;
  for row in rows.iter(){crate::daemon::control::checkpoint()?;writeln!(output,"{:<30} {:>9.1?} {:>9} {:>9} {:>10}",row.name,row.total,row.files,row.rescanned,if row.memo{"hit"}else{"-"})?;}
  writeln!(output,"actual preparation/selected wall time: {:.2?}",self.started.elapsed())?;Ok(())
 }
 pub(crate)fn finish(&self)->io::Result<Delivery>{Ok(Delivery{binding:self.request.binding()?,usage:self.take_usage()?,usage_requested:self.request.allow_usage,_allocation:Arc::clone(&self._allocation)})}
 pub(crate)fn prepared(&self,elapsed:Duration)->io::Result<()>{self.preparation.set(elapsed).map_err(|_|io::Error::new(io::ErrorKind::InvalidInput,"actual CHECK preparation observation completed twice"))}
 pub(crate)fn request(&self)->&dq_analyze::native_check_cli_wire::Request{&self.request}
 pub(crate)fn changed(&self)->&Option<HashSet<String>>{&self.changed}
 pub(crate)fn has_timing(&self,name:&str)->io::Result<bool>{Ok(self.rows.lock().map_err(|_|io::Error::other("CHECK timing observation poisoned"))?.iter().any(|row|row.name==name))}
 pub(crate)fn record_timing(&self,row:TimingRow)->io::Result<()>{if !self.request.timing{return Ok(())}let mut rows=self.rows.lock().map_err(|_|io::Error::other("CHECK timing observation poisoned"))?;if rows.iter().any(|old|old.name==row.name)||rows.len()==rows.capacity(){return Err(io::Error::new(io::ErrorKind::InvalidData,"actual CHECK timing observation is duplicate or exceeds selected producer roster"))}rows.push(row);Ok(())}
 pub(crate)fn write_usage(&self,used:&[dq_analyze::lint::AllowUse],digests:&BTreeMap<String,[u8;20]>,child:&Arc<dq_analyze::captured_generator_budget::Budget>)->io::Result<()>{
  let scratch=dq_analyze::captured_generator_budget::Budget::scoped_temporaries(child).map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))?;let mut rows=BTreeSet::new();for row in used{crate::daemon::control::checkpoint()?;scratch.charge(row.name.len().checked_mul(4).and_then(|n|n.checked_add(4096)).ok_or_else(oom)?).map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))?;let digest=*digests.get(&row.rel).ok_or_else(||io::Error::new(io::ErrorKind::InvalidData,"actual ALLOW usage lacks its captured whole-file digest"))?;rows.insert((row.name.clone(),digest,row.line));}
  struct Hex([u8;20]);impl std::fmt::Display for Hex{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{for byte in &self.0{write!(f,"{byte:02x}")?;}Ok(())}}
  self.with_usage(|output|{for(name,digest,line)in &rows{crate::daemon::control::checkpoint()?;writeln!(output,"{}\t{}\t{}",name,Hex(*digest),line)?;}Ok(())})
 }
 pub(crate)fn with_usage<T>(&self,run:impl FnOnce(&mut crate::selected_report_spool::Stage)->io::Result<T>)->io::Result<T>{let mut output=self.usage.lock().map_err(|_|io::Error::other("CHECK usage observation poisoned"))?;if self.usage_completed.load(std::sync::atomic::Ordering::Acquire){return Err(io::Error::new(io::ErrorKind::InvalidInput,"ALLOW usage producer union completed twice"))}let result=run(output.as_mut().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"ALLOW usage was not actually requested"))?);if result.is_ok(){self.usage_completed.store(true,std::sync::atomic::Ordering::Release)}result}
 fn take_usage(&self)->io::Result<Option<crate::selected_report_spool::Verified>>{if self.request.allow_usage&&!self.usage_completed.load(std::sync::atomic::Ordering::Acquire){return Err(io::Error::new(io::ErrorKind::InvalidInput,"actual selected producer usage union did not complete"))}let output=self.usage.lock().map_err(|_|io::Error::other("CHECK usage observation poisoned"))?.take();output.filter(|stage|stage.length()!=0).map(crate::request_runner::native_check_handlers::check_diagnostic_stage).transpose()}
}

#[cfg(test)]mod actual_observation_resource_controls{
 use super::*;use std::sync::atomic::Ordering;
 fn request()->dq_analyze::native_check_cli_wire::Request{dq_analyze::native_check_cli_wire::Request{changed:Some(vec!["code/actual.dm".into()]),timing:false,timing_only:false,allow_usage:false}}
 #[test]fn actual_cli_observation_admission_denial_then_delivery_alias_retains_real_source_credit_until_last_drop(){
  let host=crate::runner_host::BuildHost::default();let cache=crate::test_scratch::dir("check-cli-observation-credit");let counter=Arc::clone(crate::query_db::body_syntax_counter_for_test(&host.query_db));let limit=128*1024*1024;let poll=||Ok(());let admission=dm_syntax::SettingAdmission::new(&counter,limit,&poll);let base=counter.load(Ordering::Acquire);let pressure=admission.reserve(limit.checked_sub(base).and_then(|n|n.checked_sub(1)).unwrap()).unwrap();
  let held=counter.load(Ordering::Acquire);let denied=Observations::issue(&request(),1,&cache,host.source_arena_work()).err().expect("actual parent headroom denies requested metadata before allocation");assert_eq!(denied.kind(),io::ErrorKind::OutOfMemory);assert_eq!(counter.load(Ordering::Acquire),held);drop(pressure);
  // Warm only the existing resource-ledger bookkeeping; no source/producer or
  // input frame is fabricated. This is not a policy completion witness.
  drop(Observations::issue(&request(),1,&cache,host.source_arena_work()).unwrap());let _=host.query_db.source_input_admission_bytes().unwrap();
  let owner=Observations::issue(&request(),1,&cache,host.source_arena_work()).unwrap();let paid=owner._allocation._credit.lock().unwrap().reserved_bytes();assert!(paid>0);let delivery=owner.finish().unwrap();let live=host.query_db.source_input_admission_bytes().unwrap();drop(owner);assert_eq!(host.query_db.source_input_admission_bytes().unwrap(),live,"the actual escaped delivery retains the SAME source-credit allocation");drop(delivery);let after=host.query_db.source_input_admission_bytes().unwrap();assert!(live.checked_sub(after).is_some_and(|released|released>=paid),"last delivery drop refunds the genuine reserved extent, not only a syntax estimate: live={live} after={after} paid={paid}");assert_eq!(counter.load(Ordering::Acquire),base);
 }
 #[test]fn actual_cli_observation_cancelled_context_refuses_before_resource_owner_and_fresh_same_host_recovers(){
  let host=crate::runner_host::BuildHost::default();let cache=crate::test_scratch::dir("check-cli-observation-cancel");let before=host.query_db.source_input_admission_bytes().unwrap();let cancellation=crate::daemon::control::Cancellation::default();let binding=crate::daemon::control::bind_with_deadline(cancellation.clone(),Instant::now()+Duration::from_secs(30));cancellation.cancel();let error=Observations::issue(&request(),1,&cache,host.source_arena_work()).err().expect("actual cancelled context cannot issue metadata owner");assert_eq!(error.kind(),io::ErrorKind::Interrupted);drop(binding);assert_eq!(host.query_db.source_input_admission_bytes().unwrap(),before);drop(Observations::issue(&request(),1,&cache,host.source_arena_work()).unwrap());
 }
}

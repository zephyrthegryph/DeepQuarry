//! Operation-local no-disk execution mode. This grants NO source authority.
use super::SourceFile;
use crate::lint::AllowUse;
use std::{cell::Cell,marker::PhantomData,rc::Rc};
#[derive(Clone,Copy,Default)]struct State{depth:usize,denied:bool}
thread_local!{static STATE:Cell<State>=const{Cell::new(State{depth:0,denied:false})};}
/// Must stay on this thread. The actual captured cohort owns an outer guard
/// across its catch boundary, so swallowed nested refusals still fail closed.
pub(crate) struct CapturedComputeScope{_same_thread:PhantomData<Rc<()>>}
pub(crate) fn captured_compute_scope()->CapturedComputeScope{
 STATE.with(|cell|{
  let mut state=cell.get();if state.depth==0{state.denied=false;}
  state.depth=state.depth.checked_add(1).unwrap_or_else(||{state.denied=true;cell.set(state);panic!("captured compute nesting overflow")});cell.set(state);
 });CapturedComputeScope{_same_thread:PhantomData}
}
pub(super) fn active()->bool{STATE.with(|s|s.get().depth!=0)}
fn deny(){STATE.with(|s|{let mut state=s.get();if state.depth!=0{state.denied=true;s.set(state);}})}
pub(super) fn reject(reason:&str)->!{deny();panic!("{reason}")}
impl CapturedComputeScope{
 pub(crate) fn require(&self)->Result<(),String>{
  if STATE.with(|s|s.get().denied){Err("captured incremental computation refused mixed input or an aborted nested callback".into())}else{Ok(())}
 }
}
impl Drop for CapturedComputeScope{
 fn drop(&mut self){STATE.with(|cell|{let mut state=cell.get();
  if std::thread::panicking(){state.denied=true;}
  state.depth=state.depth.saturating_sub(1);if state.depth==0{state.denied=false;}cell.set(state);
 });}
}
pub(super) fn require_or_panic(){
 if STATE.with(|s|s.get().denied){panic!("captured incremental computation already refused");}
}
/// Atomically inspect constructor tags before callbacks/config/cache. Explicit
/// outer mode handles empty selections; a nonempty captured roster auto-enters.
pub(super) fn inputs(files:&[&SourceFile])->Option<CapturedComputeScope>{
 let captured=files.iter().filter(|f|f.is_captured_input()).count();
 if active()||captured!=0{
  if captured!=files.len(){deny();panic!("captured incremental computation cannot mix ordinary inputs");}
  require_or_panic();Some(captured_compute_scope())
 }else{None}
}
/// Exact caller trace restoration even when a parser/policy panics. Successful
/// callbacks return their local records; failed callbacks publish none.
pub(super) struct RecordedGuard{before:Option<Vec<AllowUse>>}
impl RecordedGuard{
 pub(super) fn new()->Self{Self{before:Some(crate::dm::sys::take_recorded())}}
 pub(super) fn finish(mut self)->Vec<AllowUse>{
  let uses=crate::dm::sys::take_recorded();crate::dm::sys::restore_recorded(self.before.take().unwrap());uses
 }
}
impl Drop for RecordedGuard{
 fn drop(&mut self){if let Some(before)=self.before.take(){let _=crate::dm::sys::take_recorded();crate::dm::sys::restore_recorded(before);}}
}
pub(super) fn single<R>(compute:impl FnOnce()->R)->R{
 let scope=captured_compute_scope();require_or_panic();let trace=RecordedGuard::new();let value=compute();
 let uses=trace.finish();scope.require().unwrap_or_else(|error|panic!("{error}"));crate::dm::sys::replay_recorded(uses);value
}
pub(super) fn direct<R>(files:&[&SourceFile],f:impl Fn(&SourceFile)->R)->Vec<R>{
 let mut result=Vec::with_capacity(files.len());let mut all_uses=Vec::new();
 for file in files{
  require_or_panic();let trace=RecordedGuard::new();let value=f(file);let uses=trace.finish();require_or_panic();
  result.push(value);all_uses.extend(uses);
 }
 require_or_panic();crate::dm::sys::replay_recorded(all_uses);result
}
#[cfg(test)]thread_local!{static CONFIG_READS:Cell<usize>=const{Cell::new(0)};}
#[cfg(test)]pub(super) fn observe_config(){CONFIG_READS.with(|n|n.set(n.get()+1));}
#[cfg(test)]pub(super) fn config_reads()->usize{CONFIG_READS.with(Cell::get)}

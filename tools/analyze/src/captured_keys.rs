//! Whole unique key policy over issued captured source. No semantic model.
//! Explicit fixture admission remains unchanged; not whole-workspace coverage.
use crate::{captured_generator_budget::Budget, captured_raw_policy::{CapturedRawPolicy,RawRun,MAX_FIXTURE_SITES},
    captured_keys_source, declare_policy::Marker, key_policy_control::Control,
    keys_policy::{self,Input,ScanInput},lint::{Cx,Run,Sink}};
use dm_analysis::{policy_inputs::PolicyInputs,policy_body_demand::PolicyFailure};
use std::{io,sync::Arc};
fn operational(message:impl Into<String>)->PolicyFailure{PolicyFailure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message.into()))}
struct Checked<'a,F>{budget:&'a Budget,poll:&'a mut F}
impl<F:FnMut()->io::Result<()>> Control for Checked<'_,F>{
 type Error=PolicyFailure; const CHECKED:bool=true;
 fn checkpoint(&mut self)->Result<(),Self::Error>{(self.poll)().map_err(PolicyFailure::Operational)?;self.budget.require().map_err(operational)}
 fn reserve(&mut self,bytes:usize)->Result<(),Self::Error>{self.budget.charge(bytes).map_err(operational)}
 fn overflow(&mut self)->Self::Error{self.budget.deny();operational("keys policy accounting overflow")}
 fn allocation_failed(&mut self)->Self::Error{self.budget.deny();operational("keys policy allocation refused")}
}
pub struct BorrowedKeys<'a>{raw:&'a CapturedRawPolicy,inputs:&'a PolicyInputs}
impl<'a> BorrowedKeys<'a>{
 pub fn capture(raw:&'a CapturedRawPolicy,inputs:&'a PolicyInputs)->Self{Self{raw,inputs}}
 pub fn scan(&self,budget:Arc<Budget>,remaining_bytes:usize,remaining_sites:usize,
     mut poll:impl FnMut()->io::Result<()>)->Result<RawRun,PolicyFailure>{
  poll().map_err(PolicyFailure::Operational)?;
  let no_io=crate::incr::captured_compute_scope();
  let pending=(||{
   let rows=captured_keys_source::collect(self.raw,self.inputs,&budget,&mut poll)?;
   let systems=captured_keys_source::systems(self.raw,&rows,&budget,&mut poll)?;
   budget.charge(rows.markers.len().checked_mul(std::mem::size_of::<Marker>()).and_then(|n|n.checked_add(128)).ok_or_else(||operational("keys borrowed marker roster overflow"))?).map_err(operational)?;
   let mut markers=Vec::new();markers.try_reserve_exact(rows.markers.len()).map_err(|_|operational("keys borrowed marker roster allocation refused"))?;
   for row in &rows.markers{markers.push(Marker{name:&row.name,rel:&row.rel,line:row.line,body:&row.body,args:&row.args,body_offset:row.body_offset,line_starts:&row.line_starts});}
   let input=ScanInput{keys:Input{markers:&markers,entry_ops:&rows.entry_ops},defines:&rows.defines,key_refs:&rows.key_refs,bad_sources:&rows.bad_sources};
   let scope=self.raw.scopes.for_lint("sem/keys","sem");
   let cx=Cx{tree:&self.raw.tree,meta:crate::keys_policy::metadata(),scope:&scope};
   let headroom=remaining_bytes.saturating_sub(budget.used());
   if headroom<1024{return Err(operational("keys result metadata admission refused"))}
   // Partition remaining admission before either family allocates. The sink
   // cannot spend bytes still available to policy temporaries, or vice versa.
   let result_bytes=headroom/2;
   budget.charge(result_bytes).map_err(operational)?;
   let mut sink=Sink::bounded(remaining_sites.min(MAX_FIXTURE_SITES),result_bytes);
   let mut control=Checked{budget:&budget,poll:&mut poll};
   keys_policy::scan_keys_controlled(&cx,&input,&mut sink,&mut control,
    |system,var,control|{control.checkpoint()?;Ok(systems.get(system).map_or((false,false),|row|(row.known,row.requested.get(var).copied().unwrap_or(false))))},
    |system,control|{control.checkpoint()?;let mut types=Vec::new();for prefix in ["/datum/world_service/","/datum/system/"]{crate::key_policy_control::row(control,&mut types)?;types.push(crate::key_policy_control::format(control,format_args!("{prefix}{system}"))?)}Ok(types)})?;
   if let Some(error)=sink.admission_error(){return Err(operational(error))}
   poll().map_err(PolicyFailure::Operational)?;
   Ok(RawRun{name:"sem/keys".into(),run:Run{sites:sink.sites,notes:sink.notes},allow_used:sink.allow_used})
  })();
  // Actual operational errors win over compatibility latches. Never cache a
  // partial/empty success or convert a resource failure to a semantic finding.
  if matches!(&pending,Err(PolicyFailure::Operational(_))){return pending}
  no_io.require().map_err(PolicyFailure::from)?;
  if let Some(error)=self.raw.tree.captured_violation(){return Err(error.into())}
  budget.require().map_err(operational)?;
  pending
 }
}

#[cfg(test)]
#[path="captured_keys_tests.rs"]
mod tests;

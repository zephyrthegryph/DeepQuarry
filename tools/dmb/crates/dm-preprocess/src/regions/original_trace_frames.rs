//! Current actual macro replacement ancestry, owned beside the real source
//! controller. No lookup dictionary, parser, source/EOF/model grant or Arc API.
use crate::macro_expansion::{OriginalMacroRows as Rows,OriginalMacroText as Text,OriginalMacroOrigin as Origin};
use dm_syntax::{SettingAdmission,SettingRootLease};use std::io;
struct Frame{name:Text,origin:Origin,definition:Option<Origin>}
pub(super) struct OriginalTraceFrames{frames:Rows<Frame>,failed:bool,domain:SettingRootLease}
pub(super) struct OriginalTraceFrame<'a>{pub(super) name:&'a str,pub(super) origin:Origin,pub(super) definition:Option<Origin>}
impl OriginalTraceFrames{
 pub(super) fn new(a:&SettingAdmission<'_>)->io::Result<Self>{Ok(Self{frames:Rows::new(a)?,failed:false,domain:a.reserve(0).map_err(|e|a.take_operational_error().unwrap_or(e))?})}
 fn check(&mut self,a:&SettingAdmission<'_>)->io::Result<()>{if self.failed{return Err(io::ErrorKind::InvalidInput.into())}let result=(||{a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;if !a.matches_lease_domain(&self.domain){return Err(io::ErrorKind::InvalidInput.into())}Ok(())})();if result.is_err(){self.failed=true}result}
 pub(super) fn pushed_using(&mut self,name:&str,origin:Origin,depth:usize,definition:Option<Origin>,a:&SettingAdmission<'_>)->io::Result<()>{
  self.check(a)?;let result=(||{if depth!=self.frames.len().checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?||!origin.invocation{return Err(io::ErrorKind::InvalidInput.into())}let mut actual=Text::new(a)?;actual.push_str(name,a)?;self.frames.push(Frame{name:actual,origin,definition},a)})();if result.is_err(){self.failed=true}result
 }
 pub(super) fn popped_using(&mut self,depth:usize,a:&SettingAdmission<'_>)->io::Result<()>{
  self.check(a)?;if self.frames.len()!=depth.checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?{self.failed=true;return Err(io::ErrorKind::InvalidInput.into())}self.frames.pop().ok_or(io::ErrorKind::InvalidData)?;Ok(())
 }
 /// Borrow each genuine current replacement once, outermost first. The actual
 /// plan owner funds any retained output snapshot before allocating it.
 pub(super) fn visit_current_using(&mut self,a:&SettingAdmission<'_>,mut visit:impl FnMut(OriginalTraceFrame<'_>)->io::Result<()>)->io::Result<()>{
  self.check(a)?;let result=(||{for frame in self.frames.as_slice(){a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;visit(OriginalTraceFrame{name:frame.name.as_str(),origin:frame.origin,definition:frame.definition})?;}Ok(())})();if result.is_err(){self.failed=true}result
 }
 pub(super) fn len(&self)->usize{self.frames.len()}
}

#[cfg(test)]mod tests{
 use super::*;use std::sync::{atomic::{Ordering}};
 fn origin(at:usize)->Origin{Origin{physical:dm_syntax::Span::new(at,at+1),line:1,byte_column:Some(at+1),occurrence:0,invocation:true}}
 #[test]fn same_trace_owner_lends_ordered_current_frames_and_frees_each_owned_name_only_after_real_pop(){
  let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let mut trace=OriginalTraceFrames::new(&a).unwrap();trace.pushed_using("OUTER",origin(0),1,Some(origin(11)),&a).unwrap();trace.pushed_using("INNER",origin(2),2,None,&a).unwrap();let mut observed=Vec::new();trace.visit_current_using(&a,|row|{observed.push((row.name.to_owned(),row.origin,row.definition));Ok(())}).unwrap();assert_eq!(observed,[("OUTER".into(),origin(0),Some(origin(11))),("INNER".into(),origin(2),None)]);trace.popped_using(1,&a).unwrap();assert_eq!(trace.len(),1);trace.popped_using(0,&a).unwrap();assert_eq!(trace.len(),0);drop(trace);assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]fn trace_source_writer_first_io_and_foreign_depth_cannot_become_an_empty_successful_snapshot(){
  let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let mut trace=OriginalTraceFrames::new(&a).unwrap();trace.pushed_using("LIVE",origin(0),1,None,&a).unwrap();assert_eq!(trace.visit_current_using(&a,|_|Err(io::Error::from_raw_os_error(1450))).unwrap_err().raw_os_error(),Some(1450));assert_eq!(trace.visit_current_using(&a,|_|Ok(())).unwrap_err().kind(),io::ErrorKind::InvalidInput);drop(trace);let mut fresh=OriginalTraceFrames::new(&a).unwrap();assert_eq!(fresh.pushed_using("WRONG_DEPTH",origin(0),2,None,&a).unwrap_err().kind(),io::ErrorKind::InvalidInput);assert_eq!(fresh.len(),0);drop(fresh);assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
 }
}

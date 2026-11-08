//! Operation-local policy-only file loans. Completion/source proof stays in host.
use crate::{captured_generator_budget::Budget,captured_raw_file::RawPolicyViews,reactive_reads_native::Failure};
use std::{collections::HashMap,sync::Arc};
/// A provider may stop a requested search. This bool is DATA and cannot seal a
/// complete dependency answer; only the actual host traversal receipt can.
pub trait RawPolicyPages{
 /// Exact fixed original manifest DATA for op_order only, authenticated by the
 /// current concrete raw owner. This is not a semantic/Keys/CODE grant.
 fn with_op_order_manifest(&self,_:&mut dyn FnMut(Option<&[u8]>)->Result<(),Failure>)->Result<(),Failure>{Err(Failure::Operational(std::io::Error::new(std::io::ErrorKind::NotConnected,"actual op_order fixed manifest observation unavailable")))}

 /// Purpose-specific native generation owner DATA, never a complete source role.
 #[cfg(feature="native-policy")]
 fn generation_questions(&self)->Option<&dm_tree::frontend::GenerationNativeQuestions>{None}
 /// Existing file id after the concrete reader's actual native acquisition
 /// join. Generic providers cannot silently treat missing support as uncompiled.
 #[cfg(feature="native-policy")]
 fn generation_compiled_file(&self,_relative:&str)->Result<Option<dm_ir::FileId>,Failure>{Err(Failure::Operational(std::io::Error::new(std::io::ErrorKind::NotConnected,"generation compiled-file identity is unavailable")))}

 /// Requested original callable file DATA only. Ordinary page providers do not
 /// implicitly grant an arbitrary-path or compiled-source loan.
 /// One setter header DATA loan authenticated by its actual current member.
 /// This cannot grant whole-file CODE coverage or a generic raw-file view.
 fn with_setter_header(&self,_member:dm_tree::MemberId,_name:&str,_visit:&mut dyn FnMut(&str,usize,&str)->Result<(),Failure>)->Result<(),Failure>{Err(Failure::Operational(std::io::Error::new(std::io::ErrorKind::NotConnected,"actual setter header original source loan unavailable")))}
 fn with_callable_file(&self,_ordinal:usize,_name:&str,_visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<(),Failure>)->Result<(),Failure>{Err(Failure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidInput,"Plans requires the genuine original raw file of every issued reader definition")))}

 /// Optional CODE DATA for the active, already validated file callback only.
 fn handler_code_facts(&self)->Option<crate::sem_handlers_partial_recipe::HandlerCodeFacts>{None}

 fn for_each(&self,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>;
}
/// Unique declaration-policy rows, not a DM declaration/procedure model.
/// This owner has no coverage receipt and no compiled-source authority.
pub struct RawDependencyMarkers{pub(crate) rows:Vec<crate::captured_marker_rows::OwnedMarker>,count:usize}
impl RawDependencyMarkers{
 pub(crate) fn from_rows(rows:Vec<crate::captured_marker_rows::OwnedMarker>,count:usize)->Self{Self{rows,count}}
 pub fn new()->Self{Self{rows:Vec::new(),count:0}}
 pub fn push(&mut self,relative:&str,views:RawPolicyViews<'_>,budget:&Arc<Budget>,checkpoint:&mut dyn FnMut()->std::io::Result<()>)->Result<(),Failure>{
  checkpoint()?;budget.require()?;
  crate::captured_marker_rows::collect_file_admitted(relative,views.marker()?,budget,&["READS_AS","PROC_SUMMARY","READ_LOOKUP","CAPABILITY_TYPE","CAPABILITY_DEF","cap_keys","SYSTEM_ACCESSOR","READS_FROM","CAPABILITIES","STAT"],true,true,true,&mut self.rows,&mut self.count,&mut||{checkpoint()?;budget.require()?;Ok::<_,Failure>(())})?;
  checkpoint()?;budget.require()?;Ok(())
 }
 /// SAME stable final order as original Decls. The include map is original
 /// lexical DME policy, not compiler inclusion order or authority from a hash.
 pub(crate) fn finish(mut self,order:&HashMap<String,usize>,budget:&Arc<Budget>,checkpoint:&mut dyn FnMut()->std::io::Result<()>)->Result<crate::captured_marker_rows::Rows<'static>,Failure>{
  checkpoint()?;let bytes=self.rows.len().checked_mul(std::mem::size_of::<crate::captured_marker_rows::OwnedMarker>()).and_then(|n|n.checked_mul(2)).and_then(|n|n.checked_add(128)).ok_or_else(||{budget.deny();Failure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,"raw marker final-sort capacity overflow"))})?;budget.charge(bytes)?;
  self.rows.sort_by(|a,b|(order.get(&a.rel).copied().unwrap_or(usize::MAX),a.rel.as_str(),a.line).cmp(&(order.get(&b.rel).copied().unwrap_or(usize::MAX),b.rel.as_str(),b.line)));
  checkpoint()?;budget.require()?;Ok(crate::captured_marker_rows::Rows{markers:self.rows,engine_sources:Vec::new()})
 }
}

#[cfg(test)]mod tests{
 use super::*;
 #[test]fn page_markers_restore_original_include_file_line_order_after_runtime_scan(){
  let budget=Budget::new(4*1024*1024).unwrap();let mut fold=RawDependencyMarkers::new();
  for(relative,text)in[("code/a.dm","observe(src,/datum/notice/x,src,then(PROC_REF(first)))\nSTAT(/datum/a,value)\n"),("code/z.dm","STAT(/datum/z,value)\n")]{crate::captured_marker_rows::collect_file_admitted(relative,text,&budget,&["STAT"],true,true,true,&mut fold.rows,&mut fold.count,&mut||Ok::<_,Failure>(())).unwrap();}
  assert_eq!(fold.rows.iter().map(|m|m.name.as_str()).collect::<Vec<_>>(),["STAT","RUNTIME_OBSERVE","STAT"],"unique scanner retains original normal-pass then runtime-pass order before final Decls ordering");
  let order=HashMap::from([("code/z.dm".to_owned(),0)]);let rows=fold.finish(&order,&budget,&mut||Ok(())).unwrap();assert_eq!(rows.markers.iter().map(|m|(m.rel.as_str(),m.name.as_str(),m.line)).collect::<Vec<_>>(),[("code/z.dm","STAT",1),("code/a.dm","RUNTIME_OBSERVE",1),("code/a.dm","STAT",2)]);assert!(rows.engine_sources.is_empty(),"page text never escapes as a borrowed engine source");
 }
 #[test]fn page_scanner_preserves_actual_io_and_next_fresh_fold_recovers(){
  let budget=Budget::new(4*1024*1024).unwrap();let mut rows=Vec::new();let mut count=0;
  let error=crate::captured_marker_rows::collect_file_admitted("code/a.dm","STAT(/datum/a,value)\n",&budget,&["STAT"],true,true,true,&mut rows,&mut count,&mut||Err::<(),_>(Failure::Operational(std::io::Error::from_raw_os_error(1450)))).unwrap_err();assert!(matches!(error,Failure::Operational(ref error)if error.raw_os_error()==Some(1450)));assert!(rows.is_empty());
  crate::captured_marker_rows::collect_file_admitted("code/a.dm","STAT(/datum/a,value)\n",&budget,&["STAT"],true,true,true,&mut rows,&mut count,&mut||Ok::<_,Failure>(())).unwrap();assert_eq!(rows.len(),1);
 }
}

/// One source-neutral completed data fold. The provider bool is not a source
/// receipt; actual selected hosts must still consume their own exhausted proof.
pub(crate) fn collect_marker_rows(walk:impl FnOnce(&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>,order:&HashMap<String,usize>,budget:&Arc<Budget>,names:&[&str],entries:bool,capabilities:bool,runtime:bool,checkpoint:&mut dyn FnMut()->std::io::Result<()>,check:&dyn Fn()->Result<(),Failure>)->Result<crate::captured_marker_rows::Rows<'static>,Failure>{
 let mut rows=Vec::new();let mut count=0;let completed=walk(&mut|relative,views|{let pending=(||{checkpoint()?;check()?;crate::captured_marker_rows::collect_file_admitted(relative,views.marker()?,budget,names,entries,capabilities,runtime,&mut rows,&mut count,&mut||{checkpoint()?;check()?;Ok::<_,Failure>(())})?;Ok(true)})();if matches!(&pending,Err(Failure::Operational(_))){return pending}if budget.denied(){let message=match pending{Err(Failure::Unsupported(message))=>message,Ok(_)=>"raw marker quota was denied".to_owned(),Err(Failure::Operational(_))=>unreachable!()};return Err(Failure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,message)))}pending})?;if !completed{return Err("original marker traversal incomplete".into())}check()?;RawDependencyMarkers::from_rows(rows,count).finish(order,budget,checkpoint)
}

impl RawDependencyMarkers{
 /// Actual-growth variant over one authenticated file loan; no fixture ceiling
 /// or provider bool becomes source completion. All ephemeral scanner storage
 /// belongs to the existing FileScope and retained rows stay parent funded.
 pub(crate) fn push_full(&mut self,relative:&str,views:RawPolicyViews<'_>,budget:&Arc<Budget>,poll:&dyn Fn()->std::io::Result<()>)->Result<(),Failure>{
  let local=views.allocation_budget(budget);let pending=(||{budget.require()?;poll()?;crate::captured_marker_rows::collect_file_funded(relative,views.marker()?,budget,local,&["READS_AS","PROC_SUMMARY","READ_LOOKUP","CAPABILITY_TYPE","CAPABILITY_DEF","cap_keys","SYSTEM_ACCESSOR","READS_FROM","CAPABILITIES","STAT"],true,true,true,&mut self.rows,&mut self.count,&mut||{budget.require().map_err(|m|Failure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,m)))?;poll()?;Ok::<_,Failure>(())})?;Ok(())})();if matches!(&pending,Err(Failure::Operational(_))){return pending}if local.denied()||budget.denied(){return Err(Failure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,"semantic-read original marker admission denied")))}pending
 }
}

#[cfg(test)]mod full_semantic_marker_controls{
 use super::*;use crate::captured_raw_file::File;use std::io;
 #[test]fn full_semantic_marker_entry_preserves_real_io_known_quota_and_fresh_recovery(){
  let root=std::env::current_dir().unwrap().join("semantic-marker-data-only");let file=File::capture(&root,&root.join("code/probe.dm"),"CAPABILITIES(/datum/probe, when(PROC_REF(check)))\n".into()).unwrap();let budget=Budget::new(4*1024*1024).unwrap();let mut fold=RawDependencyMarkers::new();let error=file.with_policy_views(&mut|relative,views|{fold.push_full(relative,views,&budget,&||Err(io::Error::from_raw_os_error(1450)))?;Ok(true)}).unwrap_err();assert!(matches!(error,Failure::Operational(error)if error.raw_os_error()==Some(1450)));assert!(fold.rows.is_empty());
  let denied=Budget::new(256).unwrap();assert!(denied.charge(256).is_err());let polled=std::cell::Cell::new(false);let error=file.with_policy_views(&mut|relative,views|{fold.push_full(relative,views,&denied,&||{polled.set(true);Err(io::ErrorKind::Interrupted.into())})?;Ok(true)}).unwrap_err();assert!(matches!(error,Failure::Operational(error)if error.kind()==io::ErrorKind::OutOfMemory));assert!(!polled.get());let budget=Budget::new(4*1024*1024).unwrap();let mut recovered=RawDependencyMarkers::new();file.with_policy_views(&mut|relative,views|{recovered.push_full(relative,views,&budget,&||Ok(()))?;Ok(true)}).unwrap();let rows=recovered.finish(&HashMap::new(),&budget,&mut||Ok(())).unwrap();assert_eq!(rows.markers.len(),1);assert_eq!(rows.markers[0].name,"CAPABILITIES");
 }
 #[test]fn full_semantic_marker_rows_use_actual_growth_without_finite_count_promotion(){
  let root=std::env::current_dir().unwrap().join("semantic-marker-growth-data");let text="CAPABILITIES(/d)\n".repeat(10_001);let budget=Budget::new(64*1024*1024).unwrap();let file=File::capture(&root,&root.join("code/probe.dm"),text.into()).unwrap();let mut fold=RawDependencyMarkers::new();file.with_policy_views(&mut|relative,views|{fold.push_full(relative,views,&budget,&||Ok(()))?;Ok(true)}).unwrap();assert_eq!(fold.count,10_001);let rows=fold.finish(&HashMap::new(),&budget,&mut||Ok(())).unwrap();assert_eq!(rows.markers.len(),10_001);assert!(rows.engine_sources.is_empty(),"unsealed marker DATA never retains source views or issues CODE completion");
 }
}

/// Actual-growth variant of the SAME marker projection. Source-family budgets,
/// not finite fixture row ceilings, fund the operation before every allocation.
pub(crate) fn collect_marker_rows_funded(walk:impl FnOnce(&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>,order:&HashMap<String,usize>,budget:&Arc<Budget>,names:&[&str],entries:bool,capabilities:bool,runtime:bool,poll:&dyn Fn()->std::io::Result<()>)->Result<crate::captured_marker_rows::Rows<'static>,Failure>{
 let mut rows=Vec::new();let mut count=0;let completed=walk(&mut|relative,views|{poll()?;budget.require()?;let local=views.allocation_budget(budget);let pending=crate::captured_marker_rows::collect_file_funded(relative,views.marker()?,budget,local,names,entries,capabilities,runtime,&mut rows,&mut count,&mut||{poll()?;budget.require()?;local.require()?;Ok::<_,Failure>(())});if matches!(&pending,Err(Failure::Operational(_))){return pending.map(|_|true)}local.require()?;budget.require()?;pending?;Ok(true)})?;
 if !completed{return Err("actual funded marker traversal stopped before source exhaustion".into())}poll()?;budget.require()?;RawDependencyMarkers::from_rows(rows,count).finish(order,budget,&mut||poll())
}

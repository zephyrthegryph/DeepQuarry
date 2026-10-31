//! Unsealed UI file data over actual local raw-policy loans. This function
//! cannot mint a frontend/source/workspace receipt or install generated files.
use crate::{captured_generator_budget::Budget,captured_reactive_reads::Failure,reactive_raw_policy_pages::RawPolicyPages,ui_types_policy::{self,Input,Files},declare_policy::Marker};
use std::{collections::HashMap,io,sync::Arc};
struct Scratch{budget:Arc<Budget>,success:bool}
impl Scratch{fn new(root:&Arc<Budget>)->Result<Self,Failure>{Ok(Self{budget:Budget::scoped_temporaries(root).map_err(|message|oom(root,message))?,success:false})}}
impl Drop for Scratch{fn drop(&mut self){if !self.success{self.budget.keep_failed_scratch()}}}
fn oom(budget:&Budget,message:impl Into<String>)->Failure{budget.deny();Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message.into()))}
fn checkpoint(budget:&Budget,poll:&dyn Fn()->io::Result<()>)->io::Result<()>{budget.require().map_err(|message|io::Error::new(io::ErrorKind::OutOfMemory,message))?;poll()?;budget.require().map_err(|message|io::Error::new(io::ErrorKind::OutOfMemory,message))}
fn finish<T>(result:Result<T,Failure>,budget:&Budget,poll:&dyn Fn()->io::Result<()>)->Result<T,Failure>{if matches!(&result,Err(Failure::Operational(_))){return result}if budget.denied(){let message=match result{Err(Failure::Unsupported(message))=>message,Ok(value)=>{drop(value);"UI operation admission denied".into()},Err(Failure::Operational(_))=>unreachable!()};return Err(oom(budget,message))}checkpoint(budget,poll)?;result}
fn retained(files:&Files)->Option<usize>{let bytes=std::mem::size_of::<Files>().checked_add(files.files.capacity().checked_mul(std::mem::size_of::<(String,String)>())?)?.checked_add(files.diags.capacity().checked_mul(std::mem::size_of::<crate::sparse_slots_policy::Diagnostic>())?)?;let bytes=files.files.iter().try_fold(bytes,|sum,(path,body)|sum.checked_add(path.capacity())?.checked_add(body.capacity()))?;files.diags.iter().try_fold(bytes,|sum,row|sum.checked_add(row.rel.capacity())?.checked_add(row.msg.capacity()))}
/// Local page data only. The selecting host must independently prove original
/// include order, completed CODE/current-config scope and safe output paths.
pub fn generate_from_pages(pages:&dyn RawPolicyPages,order:&HashMap<String,usize>,root:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<Files,Failure>{
 checkpoint(root,poll)?;let mut scratch=Scratch::new(root)?;
 let produced=(||{
  let rows=crate::reactive_raw_policy_pages::collect_marker_rows(|visit|pages.for_each(visit),order,&scratch.budget,ui_types_policy::MARKERS,true,false,false,&mut||checkpoint(&scratch.budget,poll),&||scratch.budget.require().map_err(|message|oom(&scratch.budget,message)))?;
  let cap=rows.markers.len().checked_mul(4).and_then(|n|n.checked_add(4)).ok_or_else(||oom(&scratch.budget,"UI borrowed marker directory overflow"))?;
  scratch.budget.charge(cap.checked_mul(std::mem::size_of::<Marker<'_>>()).ok_or_else(||oom(&scratch.budget,"UI borrowed marker backing overflow"))?).map_err(|message|oom(&scratch.budget,message))?;
  let mut views=Vec::new();views.try_reserve_exact(rows.markers.len()).map_err(|actual|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,actual)))?;if views.capacity()>cap{return Err(oom(&scratch.budget,"UI marker allocator exceeds reservation"))}
  for marker in &rows.markers{checkpoint(&scratch.budget,poll)?;views.push(Marker{name:&marker.name,rel:&marker.rel,line:marker.line,body:&marker.body,args:&marker.args,body_offset:marker.body_offset,line_starts:&marker.line_starts});}
  let input=Input{markers:&views,budget:Some(Arc::clone(&scratch.budget)),poll:None};ui_types_policy::generate_with(&input,&mut||checkpoint(&scratch.budget,poll).map_err(Failure::Operational))
 })();
 let produced=finish(produced,&scratch.budget,poll);
 let funded=match produced{Ok(files)=>match retained(&files).ok_or_else(||oom(root,"UI retained file capacity overflow")).and_then(|bytes|root.charge(bytes).map_err(|message|oom(root,message))){Ok(())=>Ok(files),Err(actual)=>{drop(files);Err(actual)}},Err(actual)=>Err(actual)};
 scratch.success=funded.is_ok();drop(scratch);finish(funded,root,poll)
}
#[cfg(test)]mod tests{
 use super::*;use crate::captured_raw_file::File;use std::cell::Cell;
 struct Pages{file:File,stop:Cell<bool>,fail:Cell<bool>}
 impl RawPolicyPages for Pages{fn for_each(&self,visit:&mut dyn FnMut(&str,crate::captured_raw_file::RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{let result=self.file.with_policy_views(visit)?;if self.fail.get(){return Err(Failure::Operational(io::Error::from_raw_os_error(1450)))}Ok(result&&!self.stop.get())}}
 fn fixture()->Pages{let root=std::env::current_dir().unwrap().join("ui-page-data");let text="SCHEMA(/datum/probe, value, bool())\nCAPABILITIES(/datum/probe, interface(\"Probe\"), ui_shape(value), op(\"set\", ui_act(\"set\", arg(\"value\", from = nameof(value)))))\n";Pages{file:File::capture(&root,&root.join("code/ui.dm"),text.to_owned().into()).unwrap(),stop:Cell::new(false),fail:Cell::new(false)}}
 #[test]fn ui_page_data_returns_owned_files_without_granting_a_source_receipt(){let pages=fixture();let budget=Budget::new(8*1024*1024).unwrap();let files=generate_from_pages(&pages,&HashMap::new(),&budget,&||Ok(())).unwrap();assert_eq!(files.files.len(),1);assert_eq!(files.files[0].0,"tgui/packages/tgui/interfaces/generated/Probe.d.ts");assert!(files.files[0].1.contains("export type ProbeData"));assert!(files.files[0].1.contains("value: boolean"));assert!(files.diags.is_empty());drop(pages);assert!(files.files[0].1.contains("ProbeActions"));}
 #[test]fn ui_page_data_refuses_stopped_and_actual_io_then_recovers_without_partial_files(){let pages=fixture();pages.stop.set(true);assert!(matches!(generate_from_pages(&pages,&HashMap::new(),&Budget::new(8*1024*1024).unwrap(),&||Ok(())),Err(Failure::Unsupported(_))));pages.stop.set(false);pages.fail.set(true);assert!(matches!(generate_from_pages(&pages,&HashMap::new(),&Budget::new(8*1024*1024).unwrap(),&||Ok(())),Err(Failure::Operational(ref actual))if actual.raw_os_error()==Some(1450)));pages.fail.set(false);let files=generate_from_pages(&pages,&HashMap::new(),&Budget::new(8*1024*1024).unwrap(),&||Ok(())).unwrap();assert_eq!(files.files.len(),1);}
 #[test]fn ui_page_quota_is_operational_before_a_later_cancel_poll(){let pages=fixture();let budget=Budget::new(4096).unwrap();let result=generate_from_pages(&pages,&HashMap::new(),&budget,&||if budget.denied(){Err(io::ErrorKind::Interrupted.into())}else{Ok(())});assert!(matches!(result,Err(Failure::Operational(ref actual))if actual.kind()==io::ErrorKind::OutOfMemory));}
}

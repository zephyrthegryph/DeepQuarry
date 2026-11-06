//! Returned diagnostic rows retain their actual native output admission.
//! The funded form lends only a slice; it cannot export an uncharged Vec/String.
use super::{Diagnostic};
use dm_syntax::{SettingAdmission,SettingRootLease};
use std::{io,ops::Deref};
pub struct FrontendDiagnostics{rows:Vec<Diagnostic>,original_plan:Option<dm_preprocess::regions::OriginalDiagnosticPlan>,credit:Option<SettingRootLease>}
impl std::fmt::Debug for FrontendDiagnostics{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.debug_struct("FrontendDiagnostics").field("rows",&self.rows).field("retained",&self.is_retained()).finish()}}
impl From<Vec<Diagnostic>> for FrontendDiagnostics{fn from(rows:Vec<Diagnostic>)->Self{Self{rows,original_plan:None,credit:None}}}
impl Deref for FrontendDiagnostics{type Target=[Diagnostic];fn deref(&self)->&Self::Target{&self.rows}}
impl<'a> IntoIterator for &'a FrontendDiagnostics{type Item=&'a Diagnostic;type IntoIter=std::slice::Iter<'a,Diagnostic>;fn into_iter(self)->Self::IntoIter{self.rows.iter()}}
impl FrontendDiagnostics{
 /// Borrow the raw prefix from this SAME actual failed preparation. It is
 /// neither a SourceSnapshot nor a compiler/checker/completeness witness.
 pub fn original_preprocess_notices(&self)->Option<super::OriginalPreprocessNotices<'_>>{self.original_plan.as_ref().map(super::original_notices::failed_original_notices)}
 pub(super) fn retain_original_plan(mut self,plan:&super::FrontendDirectivePlan)->io::Result<Self>{
  if let super::FrontendDirectivePlan::OriginalDiagnostic(plan)=plan{if self.credit.is_none(){return Err(io::Error::new(io::ErrorKind::InvalidData,"Original fatal prefix requires actual admitted diagnostic output"))}self.original_plan=Some(plan.clone());}Ok(self)
 }

 pub fn legacy_mut(&mut self)->Option<&mut[Diagnostic]>{self.credit.is_none().then_some(self.rows.as_mut_slice())}
 pub fn is_retained(&self)->bool{self.credit.is_some()}
 pub fn into_legacy(self)->Result<Vec<Diagnostic>,Self>{if self.credit.is_some(){Err(self)}else{Ok(self.rows)}}
 pub fn is_admitted_by(&self,a:&SettingAdmission<'_>)->bool{self.credit.as_ref().is_some_and(|credit|a.matches_lease_domain(credit))}
 pub(crate) fn admitted(rows:Vec<Diagnostic>,credit:SettingRootLease,a:&SettingAdmission<'_>)->io::Result<Self>{if !a.matches_lease_domain(&credit){return Err(io::ErrorKind::InvalidInput.into())}let mut bytes=rows.capacity().checked_mul(std::mem::size_of::<Diagnostic>()).ok_or(io::ErrorKind::OutOfMemory)?;for row in &rows{a.checkpoint().map_err(|error|a.take_operational_error().unwrap_or(error))?;bytes=bytes.checked_add(row.message.capacity()).ok_or(io::ErrorKind::OutOfMemory)?;if let Some(point)=&row.location{bytes=bytes.checked_add(location_bytes(point,a)?).ok_or(io::ErrorKind::OutOfMemory)?;}}if bytes>credit.bytes(){return Err(io::Error::new(io::ErrorKind::OutOfMemory,"returned diagnostic rows exceed their actual retained output credit"))}Ok(Self{rows,original_plan:None,credit:Some(credit)})}
}

/// Actual reachable source metadata, including shared backing retained by the
/// returned row after its producer's temporary source map has gone away.
/// This is a conservative row exposure bound, not a source/model reservation.
pub(super) fn location_bytes(point:&super::SourceLocation,a:&SettingAdmission<'_>)->io::Result<usize>{
 let add=|a:usize,b:usize|a.checked_add(b).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory));let arc=2*std::mem::size_of::<usize>();
 let mut bytes=add(point.path.capacity(),std::mem::size_of::<std::path::PathBuf>()+arc)?;
 bytes=add(bytes,add(point.semantic_path.len(),arc)?)?;bytes=add(bytes,point.include_chain.len().checked_mul(std::mem::size_of::<usize>()).and_then(|n|n.checked_add(arc)).ok_or(io::ErrorKind::OutOfMemory)?)?;
 for (_, size) in point.macro_expansions.view().buffers(){bytes=add(bytes,size)?;}bytes=add(bytes,arc)?;
 for (at,frame) in point.macro_expansions.iter().enumerate(){poll(a)?;if let Some(buffers)=point.macro_expansions.view().author_buffers(at){for(_,size)in buffers{bytes=add(bytes,size)?;}}else{bytes=add(bytes,add(frame.name.len(),arc)?)?;}if let Some(chain)=frame.replacement_chain.native_owner(){bytes=add(bytes,add(std::mem::size_of_val(chain.as_ref()),arc)?)?;for name in chain.iter(){poll(a)?;bytes=add(bytes,add(name.len(),arc)?)?;}}if let Some(definition)=frame.definition{bytes=add(bytes,add(definition.path.capacity(),std::mem::size_of::<std::path::PathBuf>()+arc)?)?;}}
 Ok(bytes)
}

fn poll(a:&SettingAdmission<'_>)->io::Result<()>{let result=a.checkpoint();if let Some(error)=a.take_operational_error(){return Err(error)}result}
pub(super) fn message_using(a:&SettingAdmission<'_>,credit:&mut SettingRootLease,render:impl FnOnce(&mut dyn std::fmt::Write)->std::fmt::Result)->io::Result<String>{dm_syntax::admitted_message_using(a,credit,render)}
pub(super) fn push(rows:&mut Vec<Diagnostic>,credit:&mut SettingRootLease,row:Diagnostic,a:&SettingAdmission<'_>)->io::Result<()>{poll(a)?;if let Some(point)=&row.location{a.grow(credit,location_bytes(point,a)?).map_err(|error|a.take_operational_error().unwrap_or(error))?;}if rows.len()==rows.capacity(){let count=rows.capacity().max(2).checked_mul(2).ok_or(io::ErrorKind::OutOfMemory)?;let peak=count.checked_mul(4).and_then(|n|n.checked_mul(std::mem::size_of::<Diagnostic>())).ok_or(io::ErrorKind::OutOfMemory)?;let old=rows.capacity().checked_mul(std::mem::size_of::<Diagnostic>()).ok_or(io::ErrorKind::OutOfMemory)?;a.grow(credit,peak).map_err(|error|a.take_operational_error().unwrap_or(error))?;rows.try_reserve_exact(count-rows.len()).map_err(|error|io::Error::new(io::ErrorKind::OutOfMemory,error))?;let actual=rows.capacity().checked_mul(std::mem::size_of::<Diagnostic>()).ok_or(io::ErrorKind::OutOfMemory)?;if actual>peak{return Err(io::ErrorKind::OutOfMemory.into())}let free=old.checked_add(peak).and_then(|n|n.checked_sub(actual)).ok_or(io::ErrorKind::InvalidData)?;a.shrink(credit,free).map_err(|error|a.take_operational_error().unwrap_or(error))?;}rows.push(row);poll(a)}

#[cfg(test)]mod tests{
 use super::*;use std::sync::{Arc,atomic::{AtomicUsize,Ordering}};
 #[test]fn returned_diagnostic_rows_and_strings_keep_actual_credit_until_the_last_report_drop(){let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let mut credit=a.reserve(0).unwrap();let mut rows=Vec::new();let text=message_using(&a,&mut credit,|out|out.write_str("actual resource-only diagnostic DATA")).unwrap();push(&mut rows,&mut credit,Diagnostic{kind:super::super::DiagnosticKind::SourceError,stage:super::super::DiagnosticStage::Declaration,message:text,location:None},&a).unwrap();let mut report=FrontendDiagnostics::admitted(rows,credit,&a).unwrap();assert!(report.is_retained());assert!(report.legacy_mut().is_none());assert!(report.is_admitted_by(&a));assert!(used.load(Ordering::Acquire)>0);let report=report.into_legacy().unwrap_err();assert_eq!(report[0].message,"actual resource-only diagnostic DATA");drop(report);assert_eq!(used.load(Ordering::Acquire),0);}
 #[test]fn diagnostic_writer_real_quota_and_io_fail_before_message_growth_without_reclassification(){let used=Arc::new(AtomicUsize::new(0));let tiny=SettingAdmission::new(&used,1,&||Ok(()));let mut credit=tiny.reserve(0).unwrap();let error=message_using(&tiny,&mut credit,|out|out.write_str("too much output")).unwrap_err();assert_eq!(error.kind(),io::ErrorKind::OutOfMemory);drop(credit);assert_eq!(used.load(Ordering::Acquire),0);let fault=||Err(io::Error::from_raw_os_error(1450));let a=SettingAdmission::new(&used,1<<20,&fault);let mut credit=SettingRootLease::reserve(&used,1<<20,0).unwrap();let error=message_using(&a,&mut credit,|out|out.write_str("not allocated")).unwrap_err();assert_eq!(error.raw_os_error(),Some(1450));drop(credit);assert_eq!(used.load(Ordering::Acquire),0);}
}

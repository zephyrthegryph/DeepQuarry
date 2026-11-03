//! Producer-owned formal parser records on the existing actual Header owner.
//! Coordinates/registrations are DATA; only the current source view maps them.
use dm_syntax::{Span,SettingAdmission,SettingRootLease};
use std::{io,mem::size_of};
#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub enum OriginalFormalNoticeLevel{Error,Warning,Hint}
#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub(super) enum Kind{Var,Static,InBeforeAs,Semicolon,BadInput,LocateInArgument,LocateTupleIn}
#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub struct OriginalFormalNotice{at:Span,kind:Kind}
impl OriginalFormalNotice{
 pub(super) fn new(at:Span,kind:Kind)->Self{Self{at,kind}}
 pub(super) fn from_primitive(notice:dm_syntax::OriginalInputNotice)->Self{use dm_syntax::OriginalInputNoticeKind as N;Self{at:notice.span(),kind:match notice.kind(){N::BadInputType=>Kind::BadInput,N::InPrecedesAs=>Kind::InBeforeAs,N::LocateInArgument=>Kind::LocateInArgument,N::LocateTupleIn=>Kind::LocateTupleIn}}}
 pub fn span(self)->Span{self.at}
 pub fn registration(self)->(Option<&'static str>,OriginalFormalNoticeLevel){use OriginalFormalNoticeLevel as L;match self.kind{Kind::Var=>(Some("var_in_proc_parameter"),L::Hint),Kind::Static=>(Some("static_in_proc_parameter"),L::Warning),Kind::InBeforeAs=>(Some("in_precedes_as"),L::Warning),Kind::Semicolon=>(Some("semicolon_in_proc_parameter"),L::Warning),Kind::BadInput=>(None,L::Error),Kind::LocateInArgument|Kind::LocateTupleIn=>(None,L::Warning)}}
 pub fn family(self)->&'static str{match self.kind{Kind::Var=>"var_in_proc_parameter",Kind::Static=>"static_in_proc_parameter",Kind::InBeforeAs=>"in_precedes_as",Kind::Semicolon=>"semicolon_in_proc_parameter",Kind::BadInput=>"bad_input_type",Kind::LocateInArgument=>"locate_in_argument",Kind::LocateTupleIn=>"locate_tuple_in"}}
 pub fn static_message(self)->Option<&'static str>{Some(match self.kind{Kind::Var=>"'var/' is unnecessary here",Kind::Static=>"'static/' has no effect here",Kind::InBeforeAs=>"'as' clause should precede 'in' clause, and is being ignored",Kind::Semicolon=>"Extraneous ';' in proc parameter",Kind::LocateInArgument=>"bad `locate(X in Y)`, should be `locate(X) in Y`",Kind::LocateTupleIn=>"bad 'locate(x, y, z) in'",Kind::BadInput=>return None})}
 pub(super) fn is_semicolon(self)->bool{self.kind==Kind::Semicolon}
 pub fn value_span(self)->Option<Span>{matches!(self.kind,Kind::BadInput).then_some(self.at)}
 pub(crate) fn checked_shift(self,offset:usize)->io::Result<Self>{Ok(Self{at:Span::new(self.at.start.checked_add(offset).ok_or(io::ErrorKind::InvalidInput)?,self.at.end.checked_add(offset).ok_or(io::ErrorKind::InvalidInput)?),kind:self.kind})}
}
#[derive(Clone,Copy)]pub(super) struct Entry{pub header:usize,pub notice:OriginalFormalNotice}
pub(super) struct FormalNotices{rows:Vec<Entry>,credit:SettingRootLease}
impl std::fmt::Debug for FormalNotices{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.debug_struct("FormalNotices").field("count",&self.rows.len()).finish()}}
fn checkpoint(a:&SettingAdmission<'_>)->io::Result<()>{a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))}
impl FormalNotices{
 pub fn new(a:&SettingAdmission<'_>)->io::Result<Self>{let credit=a.reserve(0).map_err(|e|a.take_operational_error().unwrap_or(e))?;Ok(Self{rows:Vec::new(),credit})}
 pub fn is_admitted_by(&self,a:&SettingAdmission<'_>)->bool{a.matches_lease_domain(&self.credit)}
 pub fn push(&mut self,header:usize,notice:OriginalFormalNotice,a:&SettingAdmission<'_>)->io::Result<()>{checkpoint(a)?;if !self.is_admitted_by(a)||self.rows.last().is_some_and(|row|row.header>header){return Err(io::ErrorKind::InvalidInput.into())}
  if self.rows.len()==self.rows.capacity(){let capacity=self.rows.capacity().max(2).checked_mul(2).ok_or(io::ErrorKind::OutOfMemory)?;let peak=capacity.checked_mul(4).and_then(|n|n.checked_mul(size_of::<Entry>())).ok_or(io::ErrorKind::OutOfMemory)?;let previous=self.rows.capacity().checked_mul(size_of::<Entry>()).ok_or(io::ErrorKind::OutOfMemory)?;a.grow(&mut self.credit,peak).map_err(|e|a.take_operational_error().unwrap_or(e))?;self.rows.try_reserve_exact(capacity-self.rows.len()).map_err(|error|io::Error::new(io::ErrorKind::OutOfMemory,error))?;let current=self.rows.capacity().checked_mul(size_of::<Entry>()).ok_or(io::ErrorKind::OutOfMemory)?;if current>peak{return Err(io::ErrorKind::OutOfMemory.into())}let free=previous.checked_add(peak).and_then(|n|n.checked_sub(current)).ok_or(io::ErrorKind::InvalidData)?;a.shrink(&mut self.credit,free).map_err(|e|a.take_operational_error().unwrap_or(e))?;
  }self.rows.push(Entry{header,notice});checkpoint(a)
 }
 pub fn for_header(&self,header:usize)->&[Entry]{let start=self.rows.partition_point(|row|row.header<header);let end=self.rows.partition_point(|row|row.header<=header);&self.rows[start..end]}
 pub fn all(&self)->&[Entry]{&self.rows}
 pub fn visit_storage(&self,mut visit:impl FnMut(usize,usize,usize)){if self.rows.capacity()!=0{visit(self.rows.as_ptr()as usize,self.rows.len()*size_of::<Entry>(),self.rows.capacity()*size_of::<Entry>())}self.credit.visit_counter_storage(|address,bytes|visit(address,bytes,bytes));}
}
/// Pinned actual InputType::from_str table (0290 ast.rs507..531), used only on
/// an identifier just consumed by the SAME native annotation producer.
pub(super) fn original_input_name(text:&str)->bool{matches!(text,"mob"|"obj"|"text"|"num"|"file"|"turf"|"key"|"null"|"area"|"icon"|"sound"|"message"|"anything"|"password"|"command_text"|"color"|"movable"|"atom"|"list")}

#[cfg(test)]mod tests{
 use super::*;use std::sync::{Arc,atomic::{AtomicUsize,Ordering}};
 #[test]fn actual_formal_notice_directory_is_funded_before_growth_and_drops_only_after_rows(){
  let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let mut ledger=FormalNotices::new(&a).unwrap();let notice=OriginalFormalNotice::new(Span::new(3,4),Kind::Var);ledger.push(1,notice,&a).unwrap();ledger.push(1,OriginalFormalNotice::new(Span::new(3,4),Kind::Static),&a).unwrap();ledger.push(9,notice,&a).unwrap();assert_eq!(ledger.for_header(1).len(),2);assert_eq!(ledger.for_header(9).len(),1);let funded=used.load(Ordering::Relaxed);assert!(funded>=ledger.rows.capacity()*size_of::<Entry>());assert!(ledger.push(0,notice,&a).is_err());let foreign=Arc::new(AtomicUsize::new(0));let other=SettingAdmission::new(&foreign,1<<20,&||Ok(()));assert!(ledger.push(10,notice,&other).is_err());drop(ledger);assert_eq!(used.load(Ordering::Relaxed),0);
  let tiny=SettingAdmission::new(&used,1,&||Ok(()));let mut ledger=FormalNotices::new(&tiny).unwrap();assert_eq!(ledger.push(1,notice,&tiny).unwrap_err().kind(),io::ErrorKind::OutOfMemory);assert_eq!(ledger.rows.capacity(),0);drop(ledger);assert_eq!(used.load(Ordering::Relaxed),0);
 }
 #[test]fn actual_formal_notice_checkpoint_preserves_typed_io_before_output_growth(){let used=Arc::new(AtomicUsize::new(0));let ok=SettingAdmission::new(&used,1<<20,&||Ok(()));let mut ledger=FormalNotices::new(&ok).unwrap();let bad=||Err(io::Error::from_raw_os_error(1450));let a=SettingAdmission::new(&used,1<<20,&bad);let error=ledger.push(1,OriginalFormalNotice::new(Span::new(0,1),Kind::Var),&a).unwrap_err();assert_eq!(error.raw_os_error(),Some(1450));assert_eq!(ledger.rows.capacity(),0);drop(ledger);assert_eq!(used.load(Ordering::Relaxed),0);}
}

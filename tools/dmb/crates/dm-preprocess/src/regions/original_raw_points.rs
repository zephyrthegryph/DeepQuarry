//! Physical ORIGINAL byte coordinates over the actual current raw loan. This
//! resource-only index is not source/EOF/model authority; no decoded text used.
use crate::macro_expansion::OriginalMacroRows;use dm_syntax::{SettingAdmission,OriginalLexicalNoticePoint,OriginalLexicalPointKind};use std::io;
pub(super) struct OriginalRawPointIndex{starts:OriginalMacroRows<usize>,indexed:usize,bom:usize}
#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub(super) struct OriginalRawPoint{pub(super) line:usize,pub(super) column:usize}
impl OriginalRawPointIndex{
 pub(super) fn new(bytes:&[u8],a:&SettingAdmission<'_>)->io::Result<Self>{let bom=if bytes.starts_with(&[0xef,0xbb,0xbf]){3}else{0};let mut starts=OriginalMacroRows::new(a)?;starts.push(bom,a)?;Ok(Self{starts,indexed:bom,bom})}
 /// Index only actual demanded byte frontier; later earlier token spans use
 /// this SAME line roster without rescanning or a separate source store.
 pub(super) fn at(&mut self,bytes:&[u8],offset:usize,a:&SettingAdmission<'_>)->io::Result<OriginalRawPoint>{
  if offset<self.bom||offset>bytes.len()||self.indexed>bytes.len(){return Err(io::ErrorKind::InvalidInput.into())}
  while self.indexed<offset{a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;if bytes[self.indexed]==b'\n'{self.starts.push(self.indexed+1,a)?;}self.indexed+=1;}
  let count=self.starts.as_slice().partition_point(|start|*start<=offset);let start=*self.starts.as_slice().get(count.saturating_sub(1)).ok_or(io::ErrorKind::InvalidData)?;Ok(OriginalRawPoint{line:count,column:offset-start+1})
 }
 pub(super) fn line_start(&self,line:usize)->Option<usize>{self.starts.as_slice().get(line.checked_sub(1)?).copied()}
 pub(super) fn notice(&mut self,bytes:&[u8],notice:OriginalLexicalNoticePoint,a:&SettingAdmission<'_>)->io::Result<OriginalRawPoint>{
  match notice.kind(){OriginalLexicalPointKind::ConsumedByte=>{if notice.offset()>=bytes.len(){return Err(io::ErrorKind::InvalidInput.into())}self.at(bytes,notice.offset(),a)},OriginalLexicalPointKind::TrackerAtEof=>{if notice.offset()!=bytes.len(){return Err(io::ErrorKind::InvalidInput.into())}let mut point=self.at(bytes,bytes.len(),a)?;point.column=point.column.checked_sub(1).ok_or(io::ErrorKind::InvalidData)?;Ok(point)}}
 }
}
#[cfg(test)]mod tests{
 use super::*;use std::sync::{Arc,atomic::{AtomicUsize,Ordering}};
 #[test]fn actual_raw_point_roster_preserves_byte_columns_bom_crlf_backward_spans_and_eof_zero_column(){
  let bytes=b"\xef\xbb\xbf\xc3\xa9\r\nx\n";let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let mut index=OriginalRawPointIndex::new(bytes,&a).unwrap();assert_eq!(index.at(bytes,3,&a).unwrap(),OriginalRawPoint{line:1,column:1});assert_eq!(index.at(bytes,4,&a).unwrap(),OriginalRawPoint{line:1,column:2});assert_eq!(index.at(bytes,7,&a).unwrap(),OriginalRawPoint{line:2,column:1});assert_eq!(index.at(bytes,5,&a).unwrap(),OriginalRawPoint{line:1,column:3});assert_eq!(index.notice(bytes,OriginalLexicalNoticePoint::eof(bytes.len()),&a).unwrap(),OriginalRawPoint{line:3,column:0});drop(index);assert_eq!(used.load(Ordering::Acquire),0);
 }
}

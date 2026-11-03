//! Comment facts from the SAME native byte-consumption state. Values/notice
//! points are DATA; current source/acquisition binding remains the frame owner.
use crate::Span;use std::io;
pub use crate::original_token_value::OriginalCommentKind;
pub struct OriginalCommentFacts{span:Span,content:Span,kind:OriginalCommentKind,notice:Option<crate::OriginalLexicalNoticePoint>,warnings:Vec<Span>,_credit:Option<crate::SettingRootLease>}
impl OriginalCommentFacts{
 pub fn span(&self)->Span{self.span}pub fn kind(&self)->OriginalCommentKind{self.kind}
 pub fn notice_point(&self)->Option<crate::OriginalLexicalNoticePoint>{self.notice}
 pub fn warning_spans(&self)->&[Span]{&self.warnings}
 pub fn warning_message()->&'static str{"backslash in line comment may be commenting out the following line"}
 pub fn visit_value_bytes<E>(&self,input:&[u8],mut emit:impl FnMut(&[u8])->Result<(),E>)->Result<Result<(),io::Error>,E>{
  let Some(content)=input.get(self.content.range())else{return Ok(Err(io::ErrorKind::InvalidInput.into()))};if matches!(self.kind,OriginalCommentKind::None){return Ok(Ok(()))}
  if matches!(self.kind,OriginalCommentKind::LineFollowing|OriginalCommentKind::LineEnclosing){for byte in content{if !matches!(byte,b'\r'|b'\n'){emit(std::slice::from_ref(byte))?}}}else{emit(content)?}Ok(Ok(()))
 }
 pub(super) fn block(input:&[u8],start:usize,end:usize,unterminated:bool)->Self{
  let kind=match input.get(start+2){Some(b'*')=>OriginalCommentKind::BlockFollowing,Some(b'!')=>OriginalCommentKind::BlockEnclosing,_=>OriginalCommentKind::None};let begin=start+if kind==OriginalCommentKind::BlockEnclosing{3}else{2};let finish=if unterminated{end.saturating_sub(1)}else{end.saturating_sub(2)}.max(begin);let kind=if finish==begin{OriginalCommentKind::None}else{kind};Self{span:Span::new(start,end),content:Span::new(begin,finish),kind,notice:unterminated.then(||crate::OriginalLexicalNoticePoint::eof(end)),warnings:Vec::new(),_credit:None}
 }
}
pub(super) struct OriginalLineCommentCursor{start:usize,at:usize,initialized:bool,backslash:bool,kind:OriginalCommentKind,content:usize,warnings:Vec<Span>,credit:Option<crate::SettingRootLease>}
pub(super) enum LineProgress{NeedInput,Complete(OriginalCommentFacts)}
impl OriginalLineCommentCursor{
 pub(super) fn new(start:usize)->Self{Self{start,at:start+2,initialized:false,backslash:false,kind:OriginalCommentKind::None,content:start+2,warnings:Vec::new(),credit:None}}
 fn warning(&mut self,at:usize,a:Option<&crate::SettingAdmission<'_>>)->io::Result<()>{
  let a=a.ok_or_else(||io::Error::new(io::ErrorKind::NotConnected,"Original comment warning needs actual native resource admission"))?;
  if self.credit.is_none(){self.credit=Some(a.reserve(0).map_err(|e|a.take_operational_error().unwrap_or(e))?)}let root=self.credit.as_mut().unwrap();if !a.matches_lease_domain(root){return Err(io::ErrorKind::InvalidInput.into())}
  if self.warnings.len()==self.warnings.capacity(){let capacity=self.warnings.capacity().max(2).checked_mul(2).ok_or(io::ErrorKind::OutOfMemory)?;let peak=capacity.checked_mul(std::mem::size_of::<Span>()).and_then(|n|n.checked_mul(4)).ok_or(io::ErrorKind::OutOfMemory)?;a.grow(root,peak).map_err(|e|a.take_operational_error().unwrap_or(e))?;let mut next=Vec::new();next.try_reserve_exact(capacity).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;let growth=next.capacity().checked_sub(self.warnings.capacity()).and_then(|n|n.checked_mul(std::mem::size_of::<Span>())).ok_or(io::ErrorKind::OutOfMemory)?;let release=peak.checked_sub(growth).ok_or(io::ErrorKind::OutOfMemory)?;next.append(&mut self.warnings);self.warnings=next;a.shrink(root,release).map_err(|e|a.take_operational_error().unwrap_or(e))?;}self.warnings.push(Span::new(at,at+1));Ok(())
 }
 fn complete(&mut self)->LineProgress{LineProgress::Complete(OriginalCommentFacts{span:Span::new(self.start,self.at),content:Span::new(self.content,self.at.max(self.content)),kind:self.kind,notice:None,warnings:std::mem::take(&mut self.warnings),_credit:self.credit.take()})}
 pub(super) fn advance(&mut self,input:&[u8],final_input:bool,a:Option<&crate::SettingAdmission<'_>>)->io::Result<LineProgress>{
  if self.at>input.len(){return Err(io::ErrorKind::InvalidInput.into())}if !self.initialized{let Some(&first)=input.get(self.at)else{return Ok(if final_input{self.complete()}else{LineProgress::NeedInput})};if first==b'\n'{self.initialized=true;return Ok(self.complete())}self.kind=match first{b'/'=>OriginalCommentKind::LineFollowing,b'!'=>OriginalCommentKind::LineEnclosing,_=>OriginalCommentKind::None};self.backslash=first==b'\\';self.at+=1;self.content=self.at;self.initialized=true;}
  while let Some(&ch)=input.get(self.at){if let Some(a)=a{a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;}if ch==b'\r'{self.at+=1;continue}if self.backslash{if ch==b'\n'{self.warning(self.at,a)?}self.backslash=false;self.at+=1;continue}if ch==b'\n'{return Ok(self.complete())}if ch==b'\\'{self.backslash=true}self.at+=1;}
  Ok(if final_input{self.complete()}else{LineProgress::NeedInput})
 }
}
#[cfg(test)]mod tests{
 use super::*;use std::sync::{Arc,atomic::{AtomicUsize,Ordering}};
 fn value(facts:&OriginalCommentFacts,input:&[u8])->Vec<u8>{let mut bytes=Vec::new();facts.visit_value_bytes(input,|part|{bytes.extend_from_slice(part);Ok::<_,()>(())}).unwrap().unwrap();bytes}
 #[test]fn actual_line_comment_state_retains_original_backslash_continuation_warning_and_value_bytes(){
  let input=b"///a\\\r\nb\nnext";let counter=Arc::new(AtomicUsize::new(0));let a=crate::SettingAdmission::new(&counter,1<<20,&||Ok(()));let mut cursor=OriginalLineCommentCursor::new(0);assert!(matches!(cursor.advance(&input[..7],false,Some(&a)).unwrap(),LineProgress::NeedInput));let LineProgress::Complete(facts)=cursor.advance(input,true,Some(&a)).unwrap()else{panic!("actual comment end")};assert_eq!(facts.kind(),OriginalCommentKind::LineFollowing);assert_eq!(facts.span(),Span::new(0,8));assert_eq!(facts.warning_spans(),&[Span::new(6,7)]);assert_eq!(value(&facts,input),b"a\\b");drop(cursor);assert!(counter.load(Ordering::Acquire)>0,"actual warnings outlive cursor under same root");drop(facts);assert_eq!(counter.load(Ordering::Acquire),0);
 }
 #[test]fn actual_block_comment_doc_ranges_keep_leading_star_empty_filter_and_unpushed_eof_lookbehind(){
  for(input,end,bad,kind,text)in[(b"/**/" as &[u8],4,false,OriginalCommentKind::None,b"" as &[u8]),(b"/**abc*/",8,false,OriginalCommentKind::BlockFollowing,b"*abc"),(b"/*!abc*/",8,false,OriginalCommentKind::BlockEnclosing,b"abc"),(b"/**abc",6,true,OriginalCommentKind::BlockFollowing,b"*ab")]{let facts=OriginalCommentFacts::block(input,0,end,bad);assert_eq!(facts.kind(),kind);assert_eq!(value(&facts,input),text);}
 }
 #[test]fn actual_line_comment_warning_quota_and_first_io_are_not_source_notices_or_unavailable(){
  let input=b"//\\\nx";let counter=Arc::new(AtomicUsize::new(0));let a=crate::SettingAdmission::new(&counter,1,&||Ok(()));let mut cursor=OriginalLineCommentCursor::new(0);assert_eq!(cursor.advance(input,true,Some(&a)).err().unwrap().kind(),io::ErrorKind::OutOfMemory);drop(cursor);assert_eq!(counter.load(Ordering::Acquire),0);let fail=||Err(io::Error::from_raw_os_error(1450));let a=crate::SettingAdmission::new(&counter,1<<20,&fail);let mut cursor=OriginalLineCommentCursor::new(0);assert_eq!(cursor.advance(input,true,Some(&a)).err().unwrap().raw_os_error(),Some(1450));drop(cursor);assert_eq!(counter.load(Ordering::Acquire),0);
 }
}

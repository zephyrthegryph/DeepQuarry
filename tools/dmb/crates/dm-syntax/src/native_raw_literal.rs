//! Raw delimiter state in the SAME native lexical producer. Original mode
//! follows the actual pinned byte reader, never its misleading LF comments.
use crate::{Span,OriginalLexicalNoticePoint as Point};
use std::io;

#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub enum NativeLexicalPurpose{Native5161687,Original0290Macro}
#[derive(Clone,Copy)]enum Terminator{Byte(u8),Block,Source(Span)}
#[derive(Clone,Copy)]enum Stage{Open,Terminator{start:usize,at:usize},Body{term:Terminator,start:usize,at:usize},NativeFailed{start:usize},Finished}
pub(super) struct RawCursor{start:usize,stage:Stage,purpose:NativeLexicalPurpose,native_single_line:bool,notice:Option<Point>,read:Option<Point>}
#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub(super) enum RawProgress{NeedInput,NotRaw,Complete{token:Span,content:Span},Failure{message:&'static str,token:Span,content:Span,notice:Point}}
impl RawCursor{
 pub(super) fn purpose(&self)->NativeLexicalPurpose{self.purpose}
 pub(super) fn new(start:usize,purpose:NativeLexicalPurpose)->Self{Self{start,stage:Stage::Open,purpose,native_single_line:false,notice:None,read:None}}
 pub(super) fn read_point(&self)->Option<Point>{self.read}
 fn read_at(&mut self,source:&[u8],at:usize,final_input:bool)->Option<u8>{let byte=source.get(at).copied();if byte.is_some(){self.read=Some(Point::consumed(at));}else if final_input{self.read=Some(Point::eof(source.len()));}byte}
 fn term<'a>(term:Terminator,source:&'a[u8])->io::Result<&'a[u8]>{Ok(match term{Terminator::Byte(_)=>return Err(io::ErrorKind::InvalidInput.into()),Terminator::Block=>b"\"}",Terminator::Source(span)=>source.get(span.range()).ok_or(io::ErrorKind::InvalidInput)?})}
 pub(super) fn advance(&mut self,source:&[u8],final_input:bool,a:Option<&crate::SettingAdmission<'_>>)->io::Result<RawProgress>{
  if self.start>source.len(){return Err(io::ErrorKind::InvalidInput.into())}
  loop{if let Some(a)=a{a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;}
   match self.stage{
    Stage::NativeFailed{start}=>{if final_input{self.stage=Stage::Finished;return Ok(RawProgress::Failure{notice:self.notice.unwrap_or_else(||Point::eof(source.len())),message:"unterminated raw string",token:Span::new(self.start,source.len()),content:Span::new(start,source.len())})}return Ok(RawProgress::NeedInput)},
    Stage::Finished=>return Err(io::Error::new(io::ErrorKind::InvalidInput,"raw lexical frame already consumed")),
    Stage::Open=>{
     if self.read_at(source,self.start,final_input)!=Some(b'@'){return Ok(RawProgress::NotRaw)}let Some(next)=self.read_at(source,self.start+1,final_input)else{if !final_input{return Ok(RawProgress::NeedInput)}self.stage=Stage::Finished;return Ok(RawProgress::Failure{notice:self.notice.unwrap_or_else(||Point::eof(source.len())),message:"unterminated raw string",token:Span::new(self.start,source.len()),content:Span::new(source.len(),source.len())})};
     if self.purpose==NativeLexicalPurpose::Native5161687{
      if next==b'"'{self.notice=Some(Point::consumed(self.start+1));self.native_single_line=true;self.stage=Stage::Body{term:Terminator::Byte(b'"'),start:self.start+2,at:self.start+2};continue}
      if next==b'\''{self.notice=Some(Point::consumed(self.start+1));self.stage=Stage::Body{term:Terminator::Byte(b'\''),start:self.start+2,at:self.start+2};continue}
      if next==b'{'{match self.read_at(source,self.start+2,final_input){Some(b'"')=>{self.notice=Some(Point::consumed(self.start+2));self.stage=Stage::Body{term:Terminator::Block,start:self.start+3,at:self.start+3};continue},None if !final_input=>return Ok(RawProgress::NeedInput),_=>return Ok(RawProgress::NotRaw)}}return Ok(RawProgress::NotRaw)
     }
     match next{
      b'\n'=>{self.notice=Some(Point::consumed(self.start+1));self.stage=Stage::Finished;return Ok(RawProgress::Failure{notice:self.notice.unwrap_or_else(||Point::eof(source.len())),message:"unterminated raw string",token:Span::new(self.start,self.start+2),content:Span::new(self.start+2,self.start+2)})},
      b'('=>self.stage=Stage::Terminator{start:self.start+2,at:self.start+2},
      b'{'=>match self.read_at(source,self.start+2,final_input){Some(b'"')=>{self.notice=Some(Point::consumed(self.start+2));self.stage=Stage::Body{term:Terminator::Block,start:self.start+3,at:self.start+3}},None if !final_input=>return Ok(RawProgress::NeedInput),_=>{self.notice=Some(if self.read.is_some_and(|point|point.offset()==self.start+2&&source.get(self.start+2).is_some()){Point::consumed(self.start+2)}else{Point::eof(source.len())});self.stage=Stage::Body{term:Terminator::Byte(b'{'),start:self.start+2,at:self.start+2}}},
      byte=>{self.notice=Some(Point::consumed(self.start+1));self.stage=Stage::Body{term:Terminator::Byte(byte),start:self.start+2,at:self.start+2}},
     }
    },
    Stage::Terminator{start,mut at}=>{
     while at<source.len(){if let Some(a)=a{a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;}self.read=Some(Point::consumed(at));if source[at]==b')'{if at==start{self.notice=Some(Point::consumed(at));self.stage=Stage::Finished;return Ok(RawProgress::Failure{notice:self.notice.unwrap_or_else(||Point::eof(source.len())),message:"empty raw string terminator",token:Span::new(self.start,at+1),content:Span::new(at+1,at+1)})}self.notice=Some(Point::consumed(at));self.stage=Stage::Body{term:Terminator::Source(Span::new(start,at)),start:at+1,at:at+1};break}at+=1;}
     if matches!(self.stage,Stage::Body{..}){continue}self.stage=Stage::Terminator{start,at};if final_input{self.read=Some(Point::eof(source.len()));self.stage=Stage::Finished;return Ok(RawProgress::Failure{notice:self.notice.unwrap_or_else(||Point::eof(source.len())),message:"unterminated raw string terminator",token:Span::new(self.start,source.len()),content:Span::new(source.len(),source.len())})}return Ok(RawProgress::NeedInput)
    },
    Stage::Body{term,start,mut at}=>{
     while at<source.len(){if let Some(a)=a{a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;}let byte=source[at];self.read=Some(Point::consumed(at));at+=1;
      if self.native_single_line&&byte==b'\n'{self.stage=Stage::NativeFailed{start};if final_input{self.stage=Stage::Finished;return Ok(RawProgress::Failure{notice:self.notice.unwrap_or_else(||Point::eof(source.len())),message:"unterminated raw string",token:Span::new(self.start,source.len()),content:Span::new(start,source.len())})}return Ok(RawProgress::NeedInput)}
      let length=match term{Terminator::Byte(expected)if byte==expected=>1,Terminator::Byte(_)=>0,_=>{let ending=Self::term(term,source)?;if at-start>=ending.len()&&source[start..at].ends_with(ending){ending.len()}else{0}}};
      if length>0{self.stage=Stage::Finished;return Ok(RawProgress::Complete{token:Span::new(self.start,at),content:Span::new(start,at-length)})}
     }
     self.stage=Stage::Body{term,start,at};if final_input{self.read=Some(Point::eof(source.len()));self.stage=Stage::Finished;return Ok(RawProgress::Failure{notice:self.notice.unwrap_or_else(||Point::eof(source.len())),message:"unterminated raw string",token:Span::new(self.start,source.len()),content:Span::new(start,source.len())})}return Ok(RawProgress::NeedInput)
    }
   }
  }
 }
}

#[cfg(test)]mod tests{
 use super::*;
 #[test]fn same_raw_byte_state_recognizes_every_real_original_delimiter_and_lf_without_prefix_replay(){for(source,content)in[("@@a\"}b@","a\"}b"),("@(END)a\n#include \"not a directive\"\nEND","a\n#include \"not a directive\"\n"),("@{plain{","plain"),("@\"line\ntext\"","line\ntext"),("@'raw\\'","raw\\")]{let mut cursor=RawCursor::new(0,NativeLexicalPurpose::Original0290Macro);let mut result=RawProgress::NeedInput;for end in 1..=source.len(){result=cursor.advance(&source.as_bytes()[..end],end==source.len(),None).unwrap();if matches!(result,RawProgress::Complete{..}){assert_eq!(end,source.len());break}}let RawProgress::Complete{token,content:span}=result else{panic!("actual raw completion {result:?}")};assert_eq!(token,Span::new(0,source.len()));assert_eq!(&source.as_bytes()[span.range()],content.as_bytes());}}
 #[test]fn native_raw_policy_keeps_existing_single_line_rejection_while_original_allows_lf(){let source=b"@\"line\ntext\"";let mut native=RawCursor::new(0,NativeLexicalPurpose::Native5161687);assert!(matches!(native.advance(source,true,None).unwrap(),RawProgress::Failure{..}));let mut original=RawCursor::new(0,NativeLexicalPurpose::Original0290Macro);assert!(matches!(original.advance(source,true,None).unwrap(),RawProgress::Complete{..}));}
 #[test]fn actual_original_raw_byte_delimiter_can_end_inside_utf8_and_does_not_invent_a_decoded_span(){let source="@αbodyα".as_bytes();let mut cursor=RawCursor::new(0,NativeLexicalPurpose::Original0290Macro);let RawProgress::Complete{token,content}=cursor.advance(source,true,None).unwrap()else{panic!("real first-byte delimiter")};assert_eq!(source[token.end-1],0xce);assert!(std::str::from_utf8(&source[content.range()]).is_err());assert_eq!(token.end,source.len()-1);}
}

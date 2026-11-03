//! Original numeric consumption state inside the SAME native token cursor.
//! Facts are DATA, not a source owner or permission to parse another input.
use crate::Span;
use std::io;
#[derive(Clone,Copy,Debug,Eq,PartialEq)]enum Normalized{Ordinary,Infinity,NaN}
#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub struct OriginalNumberFacts{span:Span,integer:bool,radix:u32,skip_x:bool,hash:Option<usize>,normalized:Normalized,notice:crate::OriginalLexicalNoticePoint}
impl OriginalNumberFacts{
 pub fn span(&self)->Span{self.span}pub fn integer(&self)->bool{self.integer}pub fn radix(&self)->u32{self.radix}pub fn notice_point(&self)->crate::OriginalLexicalNoticePoint{self.notice}
 /// Exact pinned buf.push(byte as char), including hash-tail bytes; never a
 /// whole UTF8 decode and never a new lexical boundary scan.
 pub fn visit_normalized<E>(&self,input:&[u8],mut emit:impl FnMut(&[u8])->Result<(),E>)->Result<Result<(),io::Error>,E>{
  if self.span.start>self.span.end||self.span.end>input.len(){return Ok(Err(io::ErrorKind::InvalidInput.into()))}
  match self.normalized{Normalized::Infinity=>{emit(b"inf")?;return Ok(Ok(()))},Normalized::NaN=>{emit(b"NaN")?;return Ok(Ok(()))},Normalized::Ordinary=>{}}
  for at in self.span.range(){let byte=input[at];if self.skip_x&&at==self.span.start+1{continue}if byte==b'_'&&self.hash.is_none_or(|hash|at<hash){continue}let mut encoded=[0u8;4];emit((byte as char).encode_utf8(&mut encoded).as_bytes())?;}Ok(Ok(()))
 }
}
pub(super) enum NumberProgress{NeedInput,Complete(OriginalNumberFacts)}
pub(super) struct OriginalNumberCursor{start:usize,at:usize,integer:bool,exponent:bool,radix:u32,initial:bool,skip_x:bool,hash:Option<usize>,hash_count:usize,normalized:Normalized,finished:bool,read_point:crate::OriginalLexicalNoticePoint}
impl OriginalNumberCursor{
 pub(super) fn new(start:usize)->Self{Self{start,at:start,integer:true,exponent:false,radix:10,initial:false,skip_x:false,hash:None,hash_count:0,normalized:Normalized::Ordinary,finished:false,read_point:crate::OriginalLexicalNoticePoint::consumed(start)}}
 fn complete(&mut self)->NumberProgress{self.finished=true;NumberProgress::Complete(OriginalNumberFacts{span:Span::new(self.start,self.at),integer:self.integer,radix:self.radix,skip_x:self.skip_x,hash:self.hash,normalized:self.normalized,notice:self.read_point})}
 pub(super) fn advance(&mut self,input:&[u8],final_input:bool,a:Option<&crate::SettingAdmission<'_>>)->io::Result<NumberProgress>{
  if self.start>=input.len()||self.at>input.len(){return Err(io::ErrorKind::InvalidInput.into())}if self.finished{return Ok(self.complete())}
  if !self.initial{let first=input[self.start];if first==b'0'&&self.start+1==input.len()&&!final_input{return Ok(NumberProgress::NeedInput)}self.integer=first!=b'.';self.radix=if first==b'0'{8}else{10};self.at=self.start+1;if first==b'0'&&input.get(self.at)==Some(&b'x'){self.radix=16;self.skip_x=true;self.at+=1}self.initial=true;}
  loop{if let Some(a)=a{a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;}let Some(&ch)=input.get(self.at)else{if final_input{self.read_point=crate::OriginalLexicalNoticePoint::eof(input.len());return Ok(self.complete())}return Ok(NumberProgress::NeedInput)};self.read_point=crate::OriginalLexicalNoticePoint::consumed(self.at);
   if let Some(hash)=self.hash{self.at+=1;self.hash_count+=1;let suffix=&input[hash+1..self.at];if !matches!(suffix,b"I"|b"IN"|b"INF"|b"IND"){return Ok(self.complete())}if self.hash_count==3{self.normalized=if suffix==b"INF"{Normalized::Infinity}else{Normalized::NaN};return Ok(self.complete())}continue}
   match ch{b'_'=>self.at+=1,b'.'|b'e'|b'E'=>{if self.radix!=16{self.integer=false;self.exponent|=matches!(ch,b'e'|b'E');}self.at+=1},b'+'|b'-' if self.exponent=>self.at+=1,b'#'=>{self.hash=Some(self.at);self.at+=1;self.integer=false;self.radix=10;},ch if (ch as char).is_digit(self.radix.max(10))=>{self.exponent=false;self.at+=1},_=>return Ok(self.complete())}
  }
 }
}
#[cfg(test)]mod tests{
 use super::*;
 fn actual(bytes:&[u8])->(OriginalNumberFacts,String){let mut cursor=OriginalNumberCursor::new(0);let NumberProgress::Complete(facts)=cursor.advance(bytes,true,None).unwrap()else{panic!("complete actual numeric")};let mut text=Vec::new();facts.visit_normalized(bytes,|part|{text.extend_from_slice(part);Ok::<_,()>(())}).unwrap().unwrap();(facts,String::from_utf8(text).unwrap())}
 #[test]fn actual_number_boundaries_and_normalized_buffer_preserve_original_radix_exponent_and_hash_consumption(){for (input,end,integer,radix,text)in[(b"0129z" as &[u8],4,true,8,"0129"),(b"0xff+1",4,true,16,"0ff"),(b"1e+-2+3",5,false,10,"1e+-2"),(b"1_2.#INF",8,false,10,"inf"),(b"1.#I_zz",5,false,10,"1.#I_")]{let(facts,normalized)=actual(input);assert_eq!((facts.span.end,facts.integer,facts.radix),(end,integer,radix));assert_eq!(normalized,text);}let(facts,text)=actual(&[b'1',b'.',b'#',0xc3,0xa9]);assert_eq!(facts.span.end,4);assert_eq!(text,"1.#Ã");}
 #[test]fn actual_number_cursor_pauses_without_consuming_a_future_byte_or_lexical_diagnostic(){let input=b"0x1e+foo";let mut cursor=OriginalNumberCursor::new(0);assert!(matches!(cursor.advance(&input[..1],false,None).unwrap(),NumberProgress::NeedInput));assert!(matches!(cursor.advance(&input[..3],false,None).unwrap(),NumberProgress::NeedInput));let NumberProgress::Complete(facts)=cursor.advance(input,true,None).unwrap()else{panic!("actual end")};assert_eq!(facts.span,Span::new(0,4));}
}

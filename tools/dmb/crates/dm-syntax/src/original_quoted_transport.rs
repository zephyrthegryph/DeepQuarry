//! Original token values over the SAME native quote/raw state, never a second
//! string parser or expression parser. These are byte lexical DATA; actual IO,
//! current acquisition and macro definition/frame owners stay with the host.
use super::*;
use super::demand::{NativeQuoteCursor,QuoteProgress,QuoteBoundary};
use super::raw_literal::{RawCursor,RawProgress,NativeLexicalPurpose};
use std::io;

#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub enum OriginalQuotedPartKind{String,Begin,Part,End}
pub struct OriginalQuotedPart<'a>{input:&'a[u8],content:Span,token:Span,kind:OriginalQuotedPartKind,raw:bool,notice:Option<crate::OriginalLexicalNoticePoint>,read:crate::OriginalLexicalNoticePoint}
impl OriginalQuotedPart<'_>{
 pub fn kind(&self)->OriginalQuotedPartKind{self.kind}
 /// Actual retained lexical branch, never reconstructed from value/spelling.
 pub fn is_raw(&self)->bool{self.raw}
 /// Actual last raw-reader operation, distinct from saved diagnostic origin.
 pub fn read_point(&self)->crate::OriginalLexicalNoticePoint{self.read}
 pub fn notice_point(&self)->Option<crate::OriginalLexicalNoticePoint>{self.notice}
 pub fn token_span(&self)->Span{self.token}
 pub fn content_span(&self)->Span{self.content}
 pub fn raw_spelling(&self)->&[u8]{&self.input[self.token.range()]}
 /// SAME pinned lexical splice projection, BEFORE UTF8-or-Latin1 value
 /// decoding. The native value factory must decode the concatenated bytes as
 /// a whole, not decode chunks independently or parse interpolation children.
 pub fn visit_value_bytes<E>(&self,mut emit:impl FnMut(&[u8])->Result<(),E>)->Result<Result<(),crate::literal::LiteralLexicalError>,E>{
  let bytes=&self.input[self.content.range()];if self.raw{emit(bytes)?;return Ok(Ok(()))}
  let mut shape=crate::literal::LiteralLexicalShape{interpolated:false,pinned_segment_nonempty:false};let mut error=None;crate::literal::visit_pinned_segment(bytes,&mut shape,&mut error,emit)?;Ok(error.map_or(Ok(()),Err))
 }
}
pub enum OriginalQuotedStep<'a>{Part(OriginalQuotedPart<'a>),Expression,NeedInput,Complete,LexicalFailure{message:&'static str,recovery:OriginalQuotedPart<'a>}}
enum FrameKind{Quote(NativeQuoteCursor),Raw(RawCursor)}
pub struct OriginalQuotedFrame{start:usize,kind:FrameKind,segment_token_start:usize,waiting:bool,depth:usize,last_expression_end:usize,finished:bool,line_head_after:bool,notice_start:crate::OriginalLexicalNoticePoint,domain:crate::SettingRootLease}
impl OriginalQuotedFrame{
 /// Start only at the actual source frame's current lexical boundary. This
 /// recognizes original bytes; it cannot claim a decoded UTF8 alias or EOF.
 pub fn start_using(input:&[u8],at:usize,a:&crate::SettingAdmission<'_>)->io::Result<Option<Self>>{
  a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;let Some(&first)=input.get(at)else{return Ok(None)};
  let kind=if first==b'@'{FrameKind::Raw(RawCursor::new(at,NativeLexicalPurpose::Original0290Macro))}else if first==b'"'{FrameKind::Quote(NativeQuoteCursor::new(false,false))}else if first==b'{'&&input.get(at+1)==Some(&b'"'){FrameKind::Quote(NativeQuoteCursor::new(true,false))}else{return Ok(None)};
  let domain=a.reserve(0).map_err(|e|a.take_operational_error().unwrap_or(e))?;Ok(Some(Self{start:at,kind,segment_token_start:at,waiting:false,depth:0,last_expression_end:at,finished:false,line_head_after:false,notice_start:crate::OriginalLexicalNoticePoint::consumed(at+usize::from(first==b'{')),domain}))
 }
 /// Actual physical lexer enters this only after its #warn/#error state and
 /// SAME whitespace/read cursor select the next real byte (never EOF/newline).
 pub fn start_directive_using(input:&[u8],at:usize,a:&crate::SettingAdmission<'_>)->io::Result<Self>{
  a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;if input.get(at).is_none_or(|b|*b==b'\n'){return Err(io::ErrorKind::InvalidInput.into())}let domain=a.reserve(0).map_err(|e|a.take_operational_error().unwrap_or(e))?;Ok(Self{start:at,kind:FrameKind::Quote(NativeQuoteCursor::directive_line()),segment_token_start:at,waiting:false,depth:0,last_expression_end:at,finished:false,line_head_after:false,notice_start:crate::OriginalLexicalNoticePoint::consumed(at),domain})
 }
 fn check(&self,a:&crate::SettingAdmission<'_>)->io::Result<()>{if !a.matches_lease_domain(&self.domain){return Err(io::Error::new(io::ErrorKind::InvalidInput,"Original quote frame has another actual native resource owner"))}a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))}
 pub fn continue_cursor(&mut self,cursor:&mut NativeTokenCursor)->io::Result<()>{let at=if self.finished||self.waiting{self.last_expression_end}else{return Err(io::ErrorKind::InvalidInput.into())};let effect=match &mut self.kind{FrameKind::Quote(quote)=>quote.take_close_effect(),FrameKind::Raw(_)=>None};cursor.resume_original_quoted_at(at,effect,self.line_head_after)}
 pub fn completed_cursor(&self)->io::Result<NativeTokenCursor>{if !self.finished{return Err(io::ErrorKind::InvalidInput.into())}Ok(NativeTokenCursor::at_interpolation_boundary(self.last_expression_end))}
 pub fn expression_start(&self)->Option<usize>{self.waiting.then_some(self.last_expression_end)}
 pub fn expression_cursor(&self)->io::Result<NativeTokenCursor>{let at=self.expression_start().ok_or(io::ErrorKind::InvalidInput)?;Ok(NativeTokenCursor::at_interpolation_boundary(at))}
 /// The actual token factory supplies each token from its SAME current scalar
 /// cursor. Nested strings have their own SAME quote state and are opaque to
 /// this frame's bracket counter; no bracket scan/reparse is performed here.
 pub fn observe_expression_token_using(&mut self,token:SpanToken,input:&[u8],a:&crate::SettingAdmission<'_>)->io::Result<bool>{
  self.check(a)?;if !self.waiting||token.span.start<self.last_expression_end||token.span.end<token.span.start||token.span.end>input.len(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"Original interpolation token is outside the actual current expression frontier"))}
  let text=&input[token.span.range()];if matches!(token.kind,TokenKind::Punctuation|TokenKind::Operator){if text==b"["||text==b"?["{self.depth=self.depth.checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?;}else if text==b"]"{self.depth=self.depth.checked_sub(1).ok_or(io::ErrorKind::InvalidInput)?;}}
  self.last_expression_end=token.span.end;if self.depth==0{let FrameKind::Quote(cursor)=&mut self.kind else{return Err(io::ErrorKind::InvalidInput.into())};cursor.resume_after_interpolation(token.span.end.checked_sub(self.start).ok_or(io::ErrorKind::InvalidInput)?)?;self.segment_token_start=token.span.start;self.notice_start=crate::OriginalLexicalNoticePoint::consumed(token.span.start);self.waiting=false;return Ok(true)}Ok(false)
 }
 pub fn next_using<'s>(&mut self,input:&'s[u8],final_input:bool,a:&crate::SettingAdmission<'_>)->io::Result<OriginalQuotedStep<'s>>{
  self.check(a)?;if self.finished{return Ok(OriginalQuotedStep::Complete)}if self.waiting{return Ok(OriginalQuotedStep::Expression)}if self.start>input.len(){return Err(io::ErrorKind::InvalidInput.into())}
  match &mut self.kind{
   FrameKind::Raw(cursor)=>match cursor.advance(input,final_input,Some(a))?{
    RawProgress::NeedInput=>Ok(OriginalQuotedStep::NeedInput),RawProgress::NotRaw=>Err(io::Error::new(io::ErrorKind::InvalidInput,"actual original raw opener was replaced")),
    RawProgress::Complete{token,content}=>{self.finished=true;self.last_expression_end=token.end;self.line_head_after=token.end>0&&input.get(token.end-1)==Some(&b'\n');Ok(OriginalQuotedStep::Part(OriginalQuotedPart{input,content,token,kind:OriginalQuotedPartKind::String,raw:true,read:cursor.read_point().ok_or(io::ErrorKind::InvalidData)?,notice:None}))},
    RawProgress::Failure{message,token,content,notice}=>{self.finished=true;self.last_expression_end=token.end;self.line_head_after=token.end>0&&input.get(token.end-1)==Some(&b'\n');Ok(OriginalQuotedStep::LexicalFailure{message,recovery:OriginalQuotedPart{input,content,token,kind:OriginalQuotedPartKind::String,raw:true,read:cursor.read_point().ok_or(io::ErrorKind::InvalidData)?,notice:Some(notice)}})},
   },
   FrameKind::Quote(cursor)=>match cursor.advance_boundary_bytes(&input[self.start..],final_input,a)?{
    QuoteProgress::NeedInput=>Ok(OriginalQuotedStep::NeedInput),QuoteProgress::Closed(end)=>{self.finished=true;self.last_expression_end=self.start+end;self.line_head_after=end>0&&input.get(self.start+end-1)==Some(&b'\n');Ok(OriginalQuotedStep::Complete)},
    QuoteProgress::Boundary(QuoteBoundary::Open{content,bracket,part})=>{let content=Span::new(self.start+content.start,self.start+content.end);let end=self.start+bracket.end;self.waiting=true;self.depth=1;self.last_expression_end=end;Ok(OriginalQuotedStep::Part(OriginalQuotedPart{input,content,token:Span::new(self.segment_token_start,end),kind:if part{OriginalQuotedPartKind::Part}else{OriginalQuotedPartKind::Begin},raw:false,read:crate::OriginalLexicalNoticePoint::consumed(end-1),notice:None}))},
    QuoteProgress::Boundary(QuoteBoundary::End{content,delimiter,interpolated})=>{self.finished=true;self.last_expression_end=self.start+delimiter.end;self.line_head_after=delimiter.end>0&&input.get(self.start+delimiter.end-1)==Some(&b'\n');Ok(OriginalQuotedStep::Part(OriginalQuotedPart{input,content:Span::new(self.start+content.start,self.start+content.end),token:Span::new(self.segment_token_start,self.start+delimiter.end),kind:if interpolated{OriginalQuotedPartKind::End}else{OriginalQuotedPartKind::String},raw:false,read:crate::OriginalLexicalNoticePoint::consumed(self.start+delimiter.end-1),notice:None}))},
    QuoteProgress::Unterminated=>{self.finished=true;self.last_expression_end=input.len();self.line_head_after=input.last()==Some(&b'\n');let content=Span::new(self.start+cursor.current_segment_start(),self.start+cursor.recovery_end(input.len()-self.start));Ok(OriginalQuotedStep::LexicalFailure{message:"unterminated string literal",recovery:OriginalQuotedPart{input,content,token:Span::new(self.segment_token_start,input.len()),kind:if cursor.had_interpolation(){OriginalQuotedPartKind::End}else{OriginalQuotedPartKind::String},raw:false,read:crate::OriginalLexicalNoticePoint::eof(input.len()),notice:Some(self.notice_start)}})},
   }
  }
 }
}

#[cfg(test)]mod tests{
 use super::*;use std::sync::{Arc,atomic::{AtomicUsize,Ordering}};
 fn bytes(part:OriginalQuotedPart<'_>)->Vec<u8>{let mut out=Vec::new();part.visit_value_bytes(|bytes|{out.extend_from_slice(bytes);Ok::<_,()>(())}).unwrap().unwrap();out}
 #[test]fn actual_same_quote_state_yields_begin_expression_part_end_without_parsing_a_child_or_touching_later_tokens(){
  let counter=Arc::new(AtomicUsize::new(0));let a=crate::SettingAdmission::new(&counter,1<<20,&||Ok(()));let source=br#""a[value]b[other]tail" TOO_FEW(1)"#;let mut frame=OriginalQuotedFrame::start_using(source,0,&a).unwrap().unwrap();let OriginalQuotedStep::Part(part)=frame.next_using(source,true,&a).unwrap()else{panic!("actual begin")};assert_eq!(part.kind(),OriginalQuotedPartKind::Begin);assert_eq!(bytes(part),b"a");let mut cursor=frame.expression_cursor().unwrap();loop{let step=cursor.next_available_using(std::str::from_utf8(source).unwrap(),true,&a,|_,_,_|panic!("no later token requested")).unwrap();let NativeTokenStep::Token(token)=step else{panic!("real expression token")};if frame.observe_expression_token_using(token,source,&a).unwrap(){break}}
  let OriginalQuotedStep::Part(part)=frame.next_using(source,true,&a).unwrap()else{panic!("actual middle")};assert_eq!(part.kind(),OriginalQuotedPartKind::Part);assert_eq!(bytes(part),b"b");let mut cursor=frame.expression_cursor().unwrap();loop{let NativeTokenStep::Token(token)=cursor.next_available_using(std::str::from_utf8(source).unwrap(),true,&a,|_,_,_|panic!("no later token requested")).unwrap()else{panic!("real expression")};if frame.observe_expression_token_using(token,source,&a).unwrap(){break}}
  let OriginalQuotedStep::Part(part)=frame.next_using(source,true,&a).unwrap()else{panic!("actual end")};assert_eq!(part.kind(),OriginalQuotedPartKind::End);assert_eq!(bytes(part),b"tail");assert!(matches!(frame.next_using(source,true,&a).unwrap(),OriginalQuotedStep::Complete));drop(frame);assert_eq!(counter.load(Ordering::Acquire),0);
 }
 #[test]fn actual_raw_delimiter_preserves_original_bytes_even_when_the_delimiter_splits_utf8(){let counter=Arc::new(AtomicUsize::new(0));let a=crate::SettingAdmission::new(&counter,1<<20,&||Ok(()));let source="@αbodyα".as_bytes();let mut frame=OriginalQuotedFrame::start_using(source,0,&a).unwrap().unwrap();let OriginalQuotedStep::Part(part)=frame.next_using(source,true,&a).unwrap()else{panic!("actual raw byte part")};assert_eq!(part.token_span().end,source.len()-1);assert_eq!(bytes(part),[&[0xb1][..],b"body"].concat());drop(frame);assert_eq!(counter.load(Ordering::Acquire),0);}
 #[test]fn actual_string_splice_writer_preserves_lexical_bytes_and_never_parses_interpolation(){let counter=Arc::new(AtomicUsize::new(0));let a=crate::SettingAdmission::new(&counter,1<<20,&||Ok(()));let source=b"\"a\\\n  b\\[c\"";let mut frame=OriginalQuotedFrame::start_using(source,0,&a).unwrap().unwrap();let OriginalQuotedStep::Part(part)=frame.next_using(source,true,&a).unwrap()else{panic!("actual static")};assert_eq!(part.kind(),OriginalQuotedPartKind::String);assert_eq!(bytes(part),br"ab\[c");}
}

#[cfg(test)]mod directive_line_tests{
 use super::*;use std::sync::{Arc,atomic::{AtomicUsize,Ordering}};
 #[test]fn actual_same_string_cursor_directive_terminator_is_lf_not_quote_and_future_tail_is_undemanded(){
  let bytes=b"hello \"quoted\"\nBAD(";let used=Arc::new(AtomicUsize::new(0));let a=crate::SettingAdmission::new(&used,1<<20,&||Ok(()));let mut frame=OriginalQuotedFrame::start_directive_using(bytes,0,&a).unwrap();let OriginalQuotedStep::Part(part)=frame.next_using(bytes,true,&a).unwrap()else{panic!("actual LF terminates directive String")};assert_eq!(part.kind(),OriginalQuotedPartKind::String);let mut value=Vec::new();part.visit_value_bytes(|p|{value.extend_from_slice(p);Ok::<_,()>(())}).unwrap().unwrap();assert_eq!(value,b"hello \"quoted\"");assert_eq!(part.token_span().end,bytes.iter().position(|b|*b==b'\n').unwrap()+1);assert!(matches!(frame.next_using(bytes,true,&a).unwrap(),OriginalQuotedStep::Complete));drop(frame);assert_eq!(used.load(Ordering::Acquire),0);
 }
}

#[cfg(test)]mod actual_read_point_tests{
 use super::*;use std::sync::{Arc,atomic::{AtomicUsize,Ordering}};
 #[test]fn actual_raw_reader_frontier_differs_from_saved_quote_notice_and_never_reads_a_future_tail(){
  let used=Arc::new(AtomicUsize::new(0));let a=crate::SettingAdmission::new(&used,1<<20,&||Ok(()));
  for(bytes,read,notice)in[(b"\"x".as_slice(),crate::OriginalLexicalNoticePoint::eof(2),crate::OriginalLexicalNoticePoint::consumed(0)),(b"@() FUTURE".as_slice(),crate::OriginalLexicalNoticePoint::consumed(2),crate::OriginalLexicalNoticePoint::consumed(2)),(b"@\nFUTURE".as_slice(),crate::OriginalLexicalNoticePoint::consumed(1),crate::OriginalLexicalNoticePoint::consumed(1))]{
   let mut frame=OriginalQuotedFrame::start_using(bytes,0,&a).unwrap().unwrap();let OriginalQuotedStep::LexicalFailure{recovery,..}=frame.next_using(bytes,true,&a).unwrap()else{panic!("genuine same raw failure branch")};assert_eq!(recovery.read_point(),read);assert_eq!(recovery.notice_point(),Some(notice));
  }assert_eq!(used.load(Ordering::Acquire),0);
 }
}

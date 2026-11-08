//! SAME native lexical state, retained across actual expansion input demand.
//! Token/diagnostic DATA only; neither a cursor nor End certifies CODE/model IO.
use super::*;
use std::io;
use super::raw_literal::{RawCursor,RawProgress,NativeLexicalPurpose};
#[path="original_number_demand.rs"]mod original_number;
pub use original_number::OriginalNumberFacts;
use original_number::{OriginalNumberCursor,NumberProgress};
#[path="original_comment_demand.rs"]mod original_comment;
pub use original_comment::{OriginalCommentFacts,OriginalCommentKind};
use original_comment::{OriginalLineCommentCursor,LineProgress};
#[path="original_resource_demand.rs"]mod original_resource;
pub use original_resource::OriginalResourceFacts;
#[path="original_scalar_facts.rs"]mod original_scalar;
pub use original_scalar::{OriginalPunctuationFacts,OriginalIdentFacts,OriginalWhitespaceFacts};
use original_scalar::{OriginalPunctuationCursor,PunctuationProgress};

#[derive(Clone,Copy)]enum QuoteFrame{Text{block:bool,raw:bool,line:bool,interpolation:usize,escaped:bool},Resource{raw:bool,escaped:bool}}
pub(super) struct NativeQuoteCursor{position:usize,current:QuoteFrame,parents:Vec<QuoteFrame>,failed:bool,closed:Option<usize>,segment_start:usize,saw_interpolation:bool,partial_delimiter:Option<usize>,splice_skip:u8,close_effect:Option<bool>,credit:Option<crate::SettingRootLease>}
pub(super) enum QuoteProgress{NeedInput,Closed(usize),Unterminated,Boundary(QuoteBoundary)}
#[derive(Clone,Copy)]pub(super) enum QuoteBoundary{Open{content:Span,bracket:Span,part:bool},End{content:Span,delimiter:Span,interpolated:bool}}
impl NativeQuoteCursor{
 pub(super) fn new(block:bool,raw:bool)->Self{Self{position:if block{2}else{1},current:QuoteFrame::Text{block,raw,line:false,interpolation:0,escaped:false},parents:Vec::new(),failed:false,closed:None,segment_start:if block{2}else{1},saw_interpolation:false,partial_delimiter:None,splice_skip:0,close_effect:None,credit:None}}
 /// SAME read_string state with actual directive LF terminator. No quote
 /// opener or second value scanner is fabricated; its first byte was put back.
 pub(super) fn directive_line()->Self{let mut out=Self::new(false,false);out.position=0;out.segment_start=0;out.current=QuoteFrame::Text{block:false,raw:false,line:true,interpolation:0,escaped:false};out}
 fn budget(&mut self,a:Option<&crate::SettingAdmission<'_>>)->io::Result<()>{match(a,&self.credit){(Some(a),Some(root))if !a.matches_lease_domain(root)=>return Err(io::Error::new(io::ErrorKind::InvalidInput,"native quote continuation has foreign resource owner")),(None,Some(_))=>return Err(io::Error::new(io::ErrorKind::InvalidInput,"admitted quote continuation cannot lose its actual resource host")),(Some(a),None)=>{if self.parents.capacity()!=0{return Err(io::Error::new(io::ErrorKind::InvalidInput,"unadmitted quote storage cannot be retrospectively funded"))}self.credit=Some(a.reserve(0).map_err(|e|a.take_operational_error().unwrap_or(e))?);},_=>{}}Ok(())}
 fn push(&mut self,next:QuoteFrame,a:Option<&crate::SettingAdmission<'_>>)->io::Result<()>{
  if self.parents.len()==self.parents.capacity(){let capacity=self.parents.capacity().max(2).checked_mul(2).ok_or(io::ErrorKind::OutOfMemory)?;let peak=capacity.checked_mul(std::mem::size_of::<QuoteFrame>()).and_then(|n|n.checked_mul(4)).ok_or(io::ErrorKind::OutOfMemory)?;if let(Some(a),Some(root))=(a,self.credit.as_mut()){a.grow(root,peak).map_err(|e|a.take_operational_error().unwrap_or(e))?;}
   let mut rows=Vec::new();rows.try_reserve_exact(capacity).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;let growth=rows.capacity().checked_sub(self.parents.capacity()).and_then(|n|n.checked_mul(std::mem::size_of::<QuoteFrame>())).ok_or(io::ErrorKind::OutOfMemory)?;let release=peak.checked_sub(growth).ok_or(io::ErrorKind::OutOfMemory)?;rows.append(&mut self.parents);self.parents=rows;if let(Some(a),Some(root))=(a,self.credit.as_mut()){a.shrink(root,release).map_err(|e|a.take_operational_error().unwrap_or(e))?;}
  }self.parents.push(self.current);self.current=next;Ok(())
 }
 fn close(&mut self,end:usize)->Option<usize>{if let Some(parent)=self.parents.pop(){self.current=parent;None}else{self.closed=Some(end);Some(end)}}
 pub(super) fn advance(&mut self,source:&str,final_input:bool,a:Option<&crate::SettingAdmission<'_>>)->io::Result<QuoteProgress>{self.advance_bytes_inner(source.as_bytes(),final_input,a,false)}
 pub(super) fn advance_boundary(&mut self,source:&str,final_input:bool,a:&crate::SettingAdmission<'_>)->io::Result<QuoteProgress>{self.advance_bytes_inner(source.as_bytes(),final_input,Some(a),true)}
 pub(super) fn advance_boundary_bytes(&mut self,source:&[u8],final_input:bool,a:&crate::SettingAdmission<'_>)->io::Result<QuoteProgress>{self.advance_bytes_inner(source,final_input,Some(a),true)}
 pub(super) fn take_close_effect(&mut self)->Option<bool>{self.close_effect.take()}
 pub(super) fn current_segment_start(&self)->usize{self.segment_start}
 pub(super) fn had_interpolation(&self)->bool{self.saw_interpolation}
 pub(super) fn recovery_end(&self,end:usize)->usize{if self.parents.is_empty()&&matches!(self.current,QuoteFrame::Text{escaped:true,..}){end.saturating_sub(1)}else{self.partial_delimiter.unwrap_or(end)}}
 pub(super) fn resume_after_interpolation(&mut self,end:usize)->io::Result<()>{if !self.parents.is_empty(){return Err(io::ErrorKind::InvalidInput.into())}let QuoteFrame::Text{block,raw,line,interpolation:1,escaped:false}=self.current else{return Err(io::ErrorKind::InvalidInput.into())};self.current=QuoteFrame::Text{block,raw,line,interpolation:0,escaped:false};self.position=end;self.segment_start=end;Ok(())}
 fn advance_bytes_inner(&mut self,source:&[u8],final_input:bool,a:Option<&crate::SettingAdmission<'_>>,boundaries:bool)->io::Result<QuoteProgress>{
  self.budget(a)?;if let Some(end)=self.closed{return Ok(QuoteProgress::Closed(end))}if self.failed{return Ok(if final_input{QuoteProgress::Unterminated}else{QuoteProgress::NeedInput})}
  if let Some(a)=a{a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;}
  if self.position>source.len(){return Err(io::ErrorKind::InvalidInput.into())}
  while self.position<source.len(){if let Some(a)=a{a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;}let at=self.position;let ch=source[at]as char;let end=at+1;if self.splice_skip!=0{if ch=='\r'{self.position=end;continue}if matches!(ch,' '|'\t'){self.close_effect=Some(false);self.position=end;continue}if ch=='\n'&&self.splice_skip==2{self.splice_skip=1;self.close_effect=Some(true);self.position=end;continue}self.splice_skip=0;}
   match self.current{
    QuoteFrame::Resource{raw,escaped}=>{if escaped{self.current=QuoteFrame::Resource{raw,escaped:false};self.position=end;continue}if ch=='\\'&&!raw{self.current=QuoteFrame::Resource{raw,escaped:true};self.position=end;continue}self.position=end;if ch=='\''{if let Some(end)=self.close(end){return Ok(QuoteProgress::Closed(end))}}},
    QuoteFrame::Text{block,raw,line,mut interpolation,escaped}=>{
     if escaped{if !raw&&interpolation==0&&matches!(ch,'\r'|'\n'){self.splice_skip=2;}self.current=QuoteFrame::Text{block,raw,line,interpolation,escaped:false};self.position=end;continue}
     if raw&&!block&&ch=='\n'{self.failed=true;return Ok(if final_input{QuoteProgress::Unterminated}else{QuoteProgress::NeedInput})}
     if ch=='\\'&&(!raw||interpolation>0){self.current=QuoteFrame::Text{block,raw,line,interpolation,escaped:true};self.position=end;continue}
     if interpolation>0{match ch{
      '"'=>{let nested_raw=at>0&&source[at-1]==b'@';self.push(QuoteFrame::Text{block:false,raw:nested_raw,line:false,interpolation:0,escaped:false},a)?;self.position=end;continue},
      '\''=>{let nested_raw=at>0&&source[at-1]==b'@';self.push(QuoteFrame::Resource{raw:nested_raw,escaped:false},a)?;self.position=end;continue},
      '['=>interpolation=interpolation.checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?,']'=>interpolation=interpolation.saturating_sub(1),_=>{}}
      if interpolation==0&&self.parents.is_empty(){self.segment_start=end;}self.current=QuoteFrame::Text{block,raw,line,interpolation,escaped:false};self.position=end;continue
     }
     if line&&ch=='\n'{self.position=end;if let Some(end)=self.close(end){if boundaries{return Ok(QuoteProgress::Boundary(QuoteBoundary::End{content:Span::new(self.segment_start,at),delimiter:Span::new(at,end),interpolated:self.saw_interpolation}))}return Ok(QuoteProgress::Closed(end))}continue}
     if ch=='['&&!raw{self.current=QuoteFrame::Text{block,raw,line,interpolation:1,escaped:false};self.position=end;if self.parents.is_empty(){let part=self.saw_interpolation;self.saw_interpolation=true;if boundaries{return Ok(QuoteProgress::Boundary(QuoteBoundary::Open{content:Span::new(self.segment_start,at),bracket:Span::new(at,end),part}))}}continue}
     if !line&&ch=='"'{if !block{self.position=end;if let Some(end)=self.close(end){if boundaries{return Ok(QuoteProgress::Boundary(QuoteBoundary::End{content:Span::new(self.segment_start,at),delimiter:Span::new(at,end),interpolated:self.saw_interpolation}))}return Ok(QuoteProgress::Closed(end))}continue}
      if end==source.len(){if !final_input{return Ok(QuoteProgress::NeedInput)}if self.parents.is_empty(){self.partial_delimiter=Some(at);}}
      if source.get(end)==Some(&b'}'){let end=end+1;self.position=end;if let Some(end)=self.close(end){if boundaries{return Ok(QuoteProgress::Boundary(QuoteBoundary::End{content:Span::new(self.segment_start,at),delimiter:Span::new(at,end),interpolated:self.saw_interpolation}))}return Ok(QuoteProgress::Closed(end))}continue}}
     self.position=end;
    }
   }
  }Ok(if final_input{QuoteProgress::Unterminated}else{QuoteProgress::NeedInput})
 }
}

pub(super) fn quoted_start(source:&str,at:usize,final_input:bool)->io::Result<Option<(NativeQuoteCursor,usize)>>{quoted_start_bytes(source.as_bytes(),at,final_input)}
fn quoted_start_bytes(source:&[u8],at:usize,final_input:bool)->io::Result<Option<(NativeQuoteCursor,usize)>>{let rest=source.get(at..).ok_or(io::ErrorKind::InvalidInput)?;if !final_input&&matches!(rest,b"@"|b"{"|b"@{"){return Err(io::Error::new(io::ErrorKind::WouldBlock,"native literal opener awaits actual input"))}Ok(if rest.starts_with(b"@{\""){Some((NativeQuoteCursor::new(true,true),1))}else if rest.starts_with(b"{\""){Some((NativeQuoteCursor::new(true,false),0))}else if rest.starts_with(b"@\""){Some((NativeQuoteCursor::new(false,true),1))}else if rest.starts_with(b"\""){Some((NativeQuoteCursor::new(false,false),0))}else{None})}
// SAME cursor/state operates on the actual byte owner. Native role decodes one
// real UTF8 scalar; Original role consumes one actual input byte, as its lexer
// does. No decoded facade or reconstructed raw byte array is accepted.
fn lexical_char(source:&[u8],at:usize,purpose:NativeLexicalPurpose)->io::Result<(char,usize)>{let first=*source.get(at).ok_or(io::ErrorKind::InvalidInput)?;if purpose==NativeLexicalPurpose::Original0290Macro{return Ok((first as char,1))}let width=if first<128{1}else if first&0xe0==0xc0{2}else if first&0xf0==0xe0{3}else if first&0xf8==0xf0{4}else{return Err(io::ErrorKind::InvalidData.into())};let bytes=source.get(at..at.checked_add(width).ok_or(io::ErrorKind::InvalidInput)?).ok_or(io::ErrorKind::InvalidData)?;let actual=std::str::from_utf8(bytes).map_err(|_|io::Error::from(io::ErrorKind::InvalidData))?;Ok((actual.chars().next().ok_or(io::ErrorKind::InvalidData)?,width))}
fn lexical_ident_start(ch:char,purpose:NativeLexicalPurpose)->bool{if purpose==NativeLexicalPurpose::Original0290Macro{ch.is_ascii_alphabetic()||ch=='_'}else{ident_start(ch)}}
fn lexical_ident_continue(ch:char,purpose:NativeLexicalPurpose)->bool{if purpose==NativeLexicalPurpose::Original0290Macro{ch.is_ascii_alphanumeric()||ch=='_'}else{ident_continue(ch)}}

enum Mode{Raw(RawCursor),Quote{cursor:NativeQuoteCursor,prefix:usize},Resource{at:usize,raw:bool,escaped:bool,kind:TokenKind},BlockComment{at:usize,depth:usize},LineComment{at:usize,original:Option<OriginalLineCommentCursor>},Whitespace{at:usize},Ident{at:usize},Number{at:usize,original:Option<OriginalNumberCursor>},Cr,Single{end:usize,original:Option<OriginalPunctuationCursor>}}
enum ModeProgress{NeedInput,Done{kind:TokenKind,end:usize,unterminated:bool},OriginalNumber{facts:OriginalNumberFacts},OriginalComment{facts:OriginalCommentFacts,unterminated:bool},OriginalResource{facts:OriginalResourceFacts},OriginalPunctuation{span:Span,spelling:&'static str,read:crate::OriginalLexicalNoticePoint},OriginalFailure{end:usize,message:&'static str}}
impl Mode{
 fn advance(&mut self,source:&[u8],start:usize,final_input:bool,purpose:NativeLexicalPurpose,a:Option<&crate::SettingAdmission<'_>>)->io::Result<ModeProgress>{
  macro_rules! done{($kind:expr,$end:expr,$bad:expr)=>{return Ok(if purpose==NativeLexicalPurpose::Original0290Macro&&$kind==TokenKind::Comment{ModeProgress::OriginalComment{facts:OriginalCommentFacts::block(source,start,$end,$bad),unterminated:$bad}}else{if purpose==NativeLexicalPurpose::Original0290Macro&&$kind==TokenKind::Resource{ModeProgress::OriginalResource{facts:OriginalResourceFacts::issued(Span::new(start,$end),$bad)}}else{ModeProgress::Done{kind:$kind,end:$end,unterminated:$bad}}})}}
  match self{
   Self::Raw(cursor)=>{match cursor.advance(source,final_input,a)?{RawProgress::NeedInput=>Ok(ModeProgress::NeedInput),RawProgress::Complete{token,..}=>Ok(ModeProgress::Done{kind:TokenKind::String,end:token.end,unterminated:false}),RawProgress::Failure{message,token,..}=>if cursor.purpose()==NativeLexicalPurpose::Original0290Macro{Ok(ModeProgress::OriginalFailure{end:token.end,message})}else{Ok(ModeProgress::Done{kind:TokenKind::String,end:token.end,unterminated:true})},RawProgress::NotRaw=>Ok(ModeProgress::Done{kind:TokenKind::Unknown,end:start+1,unterminated:false})}},
   Self::Single{end,original}=>{if purpose==NativeLexicalPurpose::Original0290Macro{let a=a.ok_or_else(||io::Error::new(io::ErrorKind::NotConnected,"actual Original punctuation needs native admission"))?;if original.is_none(){*original=Some(OriginalPunctuationCursor::new(source,start,a)?)}match original.as_mut().unwrap().advance(source,final_input,a)?{PunctuationProgress::NeedInput=>return Ok(ModeProgress::NeedInput),PunctuationProgress::Complete(Some((spelling,span)))=>return Ok(ModeProgress::OriginalPunctuation{span,spelling,read:original.as_ref().unwrap().read_point()}),PunctuationProgress::Complete(None)=>{}}}let(ch,_)=lexical_char(source,start,purpose)?;let kind=if "/()[]{}.,:;#?".contains(ch){TokenKind::Punctuation}else if "+-*%=!<>|&^~".contains(ch){TokenKind::Operator}else if ch=='\n'{TokenKind::Newline}else{TokenKind::Unknown};done!(kind,*end,false)},
   Self::Cr=>{if purpose==NativeLexicalPurpose::Original0290Macro{done!(TokenKind::Whitespace,start+1,false)}if start+1==source.len()&&!final_input{return Ok(ModeProgress::NeedInput)}done!(TokenKind::Newline,start+if source[start..].starts_with(b"\r\n"){2}else{1},false)},
   Self::Quote{cursor,prefix}=>{match cursor.advance_bytes_inner(&source[start+*prefix..],final_input,a,false)?{QuoteProgress::NeedInput=>Ok(ModeProgress::NeedInput),QuoteProgress::Closed(end)=>Ok(ModeProgress::Done{kind:TokenKind::String,end:start+*prefix+end,unterminated:false}),QuoteProgress::Unterminated=>Ok(ModeProgress::Done{kind:TokenKind::String,end:source.len(),unterminated:true}),QuoteProgress::Boundary(_)=>Err(io::Error::new(io::ErrorKind::InvalidData,"ordinary whole native quote cursor unexpectedly yielded a demand boundary"))}},
   Self::Resource{at,raw,escaped,kind}=>{while *at<source.len(){if let Some(a)=a{a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;}let(ch,width)=lexical_char(source,*at,purpose)?;*at+=width;if *escaped{*escaped=false;continue}if ch=='\\'&&!*raw{*escaped=true;continue}if ch=='\''{done!(*kind,*at,false)}}if final_input{done!(*kind,source.len(),true)}Ok(ModeProgress::NeedInput)},
   Self::BlockComment{at,depth}=>{while *at+1<source.len(){if let Some(a)=a{a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;}if source[*at..].starts_with(b"/*"){*depth=depth.checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?;*at+=2}else if source[*at..].starts_with(b"*/"){*depth-=1;*at+=2;if *depth==0{done!(TokenKind::Comment,*at,false)}}else{*at+=lexical_char(source,*at,purpose)?.1}}if final_input{done!(TokenKind::Comment,source.len(),true)}Ok(ModeProgress::NeedInput)},
   Self::LineComment{at,original}=>{if let Some(cursor)=original{return Ok(match cursor.advance(source,final_input,a)?{LineProgress::NeedInput=>ModeProgress::NeedInput,LineProgress::Complete(facts)=>ModeProgress::OriginalComment{facts,unterminated:false}})}while *at<source.len(){let(ch,width)=lexical_char(source,*at,purpose)?;if matches!(ch,'\r'|'\n'){done!(TokenKind::Comment,*at,false)}*at+=width;}if final_input{done!(TokenKind::Comment,*at,false)}Ok(ModeProgress::NeedInput)},
   Self::Whitespace{at}|Self::Ident{at}=>{if purpose==NativeLexicalPurpose::Original0290Macro{
    if matches!(source.get(start),Some(b' '|b'\t')){done!(TokenKind::Whitespace,start+1,false)}
    // The Original lexical role consumes one physical byte at a time and its
    // identifier alphabet is ASCII. Start at the same resumable frontier.
    if *at<source.len(){
     let tail=&source[*at..];
     if let Some(stop)=tail.iter().position(|byte|!byte.is_ascii_alphanumeric()&&*byte!=b'_'){
      *at+=stop;done!(TokenKind::Ident,*at,false)
     }
     *at=source.len();
    }
    if final_input{done!(TokenKind::Ident,*at,false)}
    return Ok(ModeProgress::NeedInput);
   }
   let whitespace=source.get(start).is_some_and(|b|matches!(b,b' '|b'\t'));while *at<source.len(){let(ch,width)=lexical_char(source,*at,purpose)?;if if whitespace{matches!(ch,' '| '\t')}else{lexical_ident_continue(ch,purpose)}{*at+=width}else{done!(if whitespace{TokenKind::Whitespace}else{TokenKind::Ident},*at,false)}}if final_input{done!(if whitespace{TokenKind::Whitespace}else{TokenKind::Ident},*at,false)}Ok(ModeProgress::NeedInput)},
   Self::Number{at,original}=>{if let Some(cursor)=original{ return Ok(match cursor.advance(source,final_input,a)?{NumberProgress::NeedInput=>ModeProgress::NeedInput,NumberProgress::Complete(facts)=>ModeProgress::OriginalNumber{facts}})}while *at<source.len(){let(ch,width)=lexical_char(source,*at,purpose)?;let offset=*at-start;let exponent=matches!(ch,'+'|'-')&&offset>0&&matches!(source[*at-1],b'e'|b'E')&&!source[start..].starts_with(b"0x")&&!source[start..].starts_with(b"0X");if exponent&&*at+1==source.len()&&!final_input{return Ok(ModeProgress::NeedInput)}let sign=exponent&&source.get(*at+1).is_some_and(u8::is_ascii_digit);if ch.is_ascii_alphanumeric()||matches!(ch,'.'|'_')||sign{*at+=width}else{break}}
    if source[start..*at].ends_with(b".") {let tail=&source[*at..];if tail.starts_with(b"#INF")||tail.starts_with(b"#IND"){done!(TokenKind::Number,*at+4,false)}if !final_input&&!tail.is_empty()&&(b"#INF".starts_with(tail)||b"#IND".starts_with(tail)){return Ok(ModeProgress::NeedInput)}}if *at==source.len()&&!final_input{return Ok(ModeProgress::NeedInput)}done!(TokenKind::Number,*at,false)
   }
  }
 }
}

#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub enum NativeTokenStep{Token(SpanToken),NeedInput,Stopped,End}
#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub enum OriginalPreparedBoundary{Productive(usize),NeedInput,End,Stopped}
#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub enum NativeTokenProgress{NeedInput,Stopped,Complete}
#[derive(Clone,Copy)]struct OriginalControlAfter{line_head:bool,close_allowed:bool,join:u8}
pub struct NativeTokenCursor{purpose:NativeLexicalPurpose,position:usize,finished:bool,mode:Option<Mode>,peek:Option<(SpanToken,Option<&'static str>,bool)>,number:Option<OriginalNumberFacts>,comment:Option<OriginalCommentFacts>,resource:Option<OriginalResourceFacts>,punctuation:Option<OriginalPunctuationFacts>,ident:Option<OriginalIdentFacts>,whitespace:Option<OriginalWhitespaceFacts>,original:OriginalControlAfter,pending_original:Option<OriginalControlAfter>}
impl Default for NativeTokenCursor{fn default()->Self{Self::for_purpose(NativeLexicalPurpose::Native5161687)}}
impl std::fmt::Debug for NativeTokenCursor{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.debug_struct("NativeTokenCursor").field("position",&self.position).field("finished",&self.finished).finish_non_exhaustive()}}
impl NativeTokenCursor{
 pub fn for_purpose(purpose:NativeLexicalPurpose)->Self{Self{purpose,position:0,finished:false,mode:None,peek:None,number:None,comment:None,resource:None,punctuation:None,ident:None,whitespace:None,original:OriginalControlAfter{line_head:true,close_allowed:true,join:0},pending_original:None}}
 pub fn for_original_initial_definition()->Self{let mut cursor=Self::for_purpose(NativeLexicalPurpose::Original0290Macro);cursor.original.line_head=false;cursor}
 pub fn for_original_source_bytes(input:&[u8])->Self{let mut cursor=Self::for_purpose(NativeLexicalPurpose::Original0290Macro);if input.starts_with(&[0xef,0xbb,0xbf]){cursor.position=3;}cursor}
 pub fn position(&self)->usize{self.position}
 pub(super) fn at_interpolation_boundary(position:usize)->Self{Self{position,..Self::for_purpose(NativeLexicalPurpose::Original0290Macro)}}
 fn peek_inner_once(&mut self,source:&[u8],final_input:bool,a:Option<&crate::SettingAdmission<'_>>,diagnostic:&mut dyn FnMut(Span,DiagnosticKind,&str)->bool)->io::Result<NativeTokenStep>{
  if self.position>source.len(){return Err(io::ErrorKind::InvalidInput.into())}if self.finished{return Ok(NativeTokenStep::End)}
  if self.peek.is_none(){if self.position==source.len(){if final_input{self.finished=true;return Ok(NativeTokenStep::End)}return Ok(NativeTokenStep::NeedInput)}
   if self.mode.is_none(){let rest=&source[self.position..];let(ch,width)=lexical_char(source,self.position,self.purpose)?;if !final_input&&(matches!(rest,b"/"|b"@"|b"{"|b"@{")){return Ok(NativeTokenStep::NeedInput)}let mode=if ch=='@'{Mode::Raw(RawCursor::new(self.position,self.purpose))}else if rest.starts_with(b"//"){Mode::LineComment{at:self.position+2,original:(self.purpose==NativeLexicalPurpose::Original0290Macro).then(||OriginalLineCommentCursor::new(self.position))}}else if rest.starts_with(b"/*"){Mode::BlockComment{at:self.position+2,depth:1}}else if rest.starts_with(b"@'"){Mode::Resource{at:self.position+2,raw:true,escaped:false,kind:TokenKind::String}}else if let Some((cursor,prefix))=quoted_start_bytes(source,self.position,final_input)?{Mode::Quote{cursor,prefix}}else if ch=='\''{Mode::Resource{at:self.position+1,raw:false,escaped:false,kind:TokenKind::Resource}}else if ch=='\r'{Mode::Cr}else if matches!(ch,' '| '\t'){Mode::Whitespace{at:self.position}}else if lexical_ident_start(ch,self.purpose){Mode::Ident{at:self.position}}else if ch.is_ascii_digit(){Mode::Number{at:self.position,original:(self.purpose==NativeLexicalPurpose::Original0290Macro).then(||OriginalNumberCursor::new(self.position))}}else{Mode::Single{end:self.position+width,original:None}};self.mode=Some(mode);}
   match self.mode.as_mut().unwrap().advance(source,self.position,final_input,self.purpose,a)?{ModeProgress::NeedInput=>return Ok(NativeTokenStep::NeedInput),ModeProgress::Done{kind,end,unterminated}=>{self.mode=None;let message=unterminated.then(||if self.purpose==NativeLexicalPurpose::Original0290Macro{if kind==TokenKind::Resource{"unterminated resource literal"}else if kind==TokenKind::String{"unterminated string literal"}else{"still skipping comments at end of file"}}else{unterminated_message(std::str::from_utf8(&source[self.position..]).unwrap_or(""))});self.peek=Some((SpanToken{kind,span:Span::new(self.position,end)},message,false));},ModeProgress::OriginalPunctuation{span,spelling,read}=>{self.mode=None;let closed=spelling==":"&&self.original.close_allowed&&!matches!(source.get(span.end),Some(b'\r'|b' '|b'\t'|b'\n'));self.punctuation=Some(OriginalPunctuationFacts::issued(span,spelling,closed,read));self.peek=Some((SpanToken{kind:crate::original_scalar_transport::original_punctuation_native_kind(spelling),span},None,false));},ModeProgress::OriginalResource{facts}=>{self.mode=None;self.resource=Some(facts);self.peek=Some((SpanToken{kind:TokenKind::Resource,span:facts.span()},facts.recovering().then_some("unterminated resource literal"),false));},ModeProgress::OriginalComment{facts,unterminated}=>{self.mode=None;let span=facts.span();self.comment=Some(facts);self.peek=Some((SpanToken{kind:TokenKind::Comment,span},unterminated.then_some("still skipping comments at end of file"),false));},ModeProgress::OriginalNumber{facts}=>{self.mode=None;self.number=Some(facts);self.peek=Some((SpanToken{kind:TokenKind::Number,span:facts.span()},None,false));},ModeProgress::OriginalFailure{end,message}=>{self.mode=None;self.peek=Some((SpanToken{kind:TokenKind::String,span:Span::new(self.position,end)},Some(message),false));}}
  }
  let(token,message,reported)=self.peek.as_mut().unwrap();if let Some(message)=message.filter(|_|!*reported){*reported=true;if !diagnostic(token.span,DiagnosticKind::Lexical,message){return Ok(NativeTokenStep::Stopped)}}Ok(NativeTokenStep::Token(*token))
 }
 fn original_control(&self,token:SpanToken,source:&[u8])->io::Result<(bool,OriginalControlAfter)>{
  let mut next=self.original;let text=source.get(token.span.range()).ok_or(io::ErrorKind::InvalidInput)?;
  if text==b"\r"{return Ok((true,next))}
  if token.kind==TokenKind::Whitespace{if !next.line_head||next.join!=0{next.close_allowed=false;return Ok((true,next))}return Ok((false,next))}
  if token.kind==TokenKind::Newline{next.line_head=true;if next.join==2{next.join=1;next.close_allowed=true;return Ok((true,next))}next.join=0;return Ok((false,next))}
  if text==b"\\"{next.line_head=false;next.join=2;return Ok((true,next))}
  next.join=0;next.line_head=false;if token.kind==TokenKind::Ident&&text!=b"in"||matches!(text,b")"|b"]"){next.close_allowed=true;}Ok((false,next))
 }
 pub fn prepare_original_boundary_using(&mut self,source:&[u8],final_input:bool,a:&crate::SettingAdmission<'_>,diagnostic:impl FnMut(Span,DiagnosticKind,&str)->bool)->io::Result<OriginalPreparedBoundary>{self.prepare_original_boundary_mode_using(source,final_input,a,diagnostic,false)}
 /// Same actual whitespace skipper, but pause before constructing the first
 /// directive Stringy payload token. This never clears an existing peek.
 pub fn prepare_original_directive_boundary_using(&mut self,source:&[u8],final_input:bool,a:&crate::SettingAdmission<'_>,diagnostic:impl FnMut(Span,DiagnosticKind,&str)->bool)->io::Result<OriginalPreparedBoundary>{if self.peek.is_some()||self.mode.is_some(){return Err(io::ErrorKind::InvalidInput.into())}self.prepare_original_boundary_mode_using(source,final_input,a,diagnostic,true)}
 fn prepare_original_boundary_mode_using(&mut self,source:&[u8],final_input:bool,a:&crate::SettingAdmission<'_>,mut diagnostic:impl FnMut(Span,DiagnosticKind,&str)->bool,directive_line:bool)->io::Result<OriginalPreparedBoundary>{
  if self.purpose!=NativeLexicalPurpose::Original0290Macro{return Err(io::ErrorKind::InvalidInput.into())}
  loop{a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;
   // SAME opener judge, before constructing any whole-literal mode. Skip
   // decisions and all ordinary token work remain the SAME cursor below.
   if self.peek.is_none()&&self.mode.is_none()&&self.position<source.len()&&((directive_line&&!matches!(source[self.position],b'\r'|b' '|b'\t'))||source[self.position]==b'@'||quoted_start_bytes(source,self.position,final_input)?.is_some()){return Ok(OriginalPreparedBoundary::Productive(self.position))}
   match self.peek_inner_once(source,final_input,Some(a),&mut diagnostic)?{NativeTokenStep::Token(token)=>{if self.pending_original.is_none(){let(skip,after)=self.original_control(token,source)?;self.pending_original=Some(after);if skip{self.commit_peek()?;continue}}self.finish_original_visible(token,source);return Ok(OriginalPreparedBoundary::Productive(self.position))},NativeTokenStep::NeedInput=>return Ok(OriginalPreparedBoundary::NeedInput),NativeTokenStep::End=>return Ok(OriginalPreparedBoundary::End),NativeTokenStep::Stopped=>return Ok(OriginalPreparedBoundary::Stopped)}
  }
 }
 fn finish_original_visible(&mut self,token:SpanToken,source:&[u8]){if token.kind==TokenKind::Ident&&self.ident.is_none(){self.ident=Some(OriginalIdentFacts::issued(token.span,source));}if token.kind==TokenKind::Whitespace&&self.whitespace.is_none(){self.whitespace=Some(OriginalWhitespaceFacts::issued(token.span,source.get(token.span.start)==Some(&b'\t')));}}
 fn peek_inner(&mut self,source:&[u8],final_input:bool,a:Option<&crate::SettingAdmission<'_>>,diagnostic:&mut dyn FnMut(Span,DiagnosticKind,&str)->bool)->io::Result<NativeTokenStep>{loop{
  let step=self.peek_inner_once(source,final_input,a,diagnostic)?;if self.purpose!=NativeLexicalPurpose::Original0290Macro{return Ok(step)}
  let NativeTokenStep::Token(token)=step else{return Ok(step)};if self.pending_original.is_none(){let(skip,after)=self.original_control(token,source)?;self.pending_original=Some(after);if skip{self.commit_peek()?;continue}}
  self.finish_original_visible(token,source);
  return Ok(step)
 }}
 pub(super) fn resume_original_quoted_at(&mut self,position:usize,close_effect:Option<bool>,line_head:bool)->io::Result<()>{if self.purpose!=NativeLexicalPurpose::Original0290Macro||position<self.position||self.peek.is_some()||self.mode.is_some(){return Err(io::ErrorKind::InvalidInput.into())}self.position=position;self.original.line_head=line_head;self.original.join=0;if let Some(close)=close_effect{self.original.close_allowed=close;}Ok(())}
 pub fn commit_original_interpolation_close(&mut self)->io::Result<()>{let close=self.original.close_allowed;self.commit_peek()?;self.original.close_allowed=close;Ok(())}
 pub fn peek_bytes_available_using(&mut self,source:&[u8],final_input:bool,a:&crate::SettingAdmission<'_>,mut diagnostic:impl FnMut(Span,DiagnosticKind,&str)->bool)->io::Result<NativeTokenStep>{self.peek_inner(source,final_input,Some(a),&mut diagnostic)}
 pub fn next_bytes_available_using(&mut self,source:&[u8],final_input:bool,a:&crate::SettingAdmission<'_>,mut diagnostic:impl FnMut(Span,DiagnosticKind,&str)->bool)->io::Result<NativeTokenStep>{let step=self.peek_inner(source,final_input,Some(a),&mut diagnostic)?;if matches!(step,NativeTokenStep::Token(_)){self.commit_peek()?}Ok(step)}
 pub fn original_pending_lexical_notice(&self)->Option<(&'static str,Span,crate::OriginalLexicalNoticePoint)>{let(token,message,_)=self.peek.as_ref()?;let message=(*message)?;let point=self.resource.as_ref().and_then(OriginalResourceFacts::notice_point).or_else(||self.comment.as_ref().and_then(OriginalCommentFacts::notice_point)).unwrap_or_else(||crate::OriginalLexicalNoticePoint::consumed(token.span.start));Some((message,token.span,point))}
 pub fn original_punctuation_facts(&self)->Option<&OriginalPunctuationFacts>{self.punctuation.as_ref()}
 pub fn original_ident_facts(&self)->Option<&OriginalIdentFacts>{self.ident.as_ref()}
 pub fn original_whitespace_facts(&self)->Option<&OriginalWhitespaceFacts>{self.whitespace.as_ref()}
 pub fn original_resource_facts(&self)->Option<&OriginalResourceFacts>{self.peek.as_ref().filter(|(token,_,_)|token.kind==TokenKind::Resource).and(self.resource.as_ref())}
 pub fn original_comment_facts(&self)->Option<&OriginalCommentFacts>{self.peek.as_ref().filter(|(token,_,_)|token.kind==TokenKind::Comment).and(self.comment.as_ref())}
 pub fn original_number_facts(&self)->Option<&OriginalNumberFacts>{self.peek.as_ref().filter(|(token,_,_)|token.kind==TokenKind::Number).and(self.number.as_ref())}
 pub fn commit_peek(&mut self)->io::Result<()>{let Some((token,_,_))=self.peek.take()else{return Err(io::Error::new(io::ErrorKind::InvalidInput,"native token commit has no actual peek"))};self.position=token.span.end;if let Some(after)=self.pending_original.take(){self.original=after;}self.number=None;self.comment=None;self.resource=None;self.punctuation=None;self.ident=None;self.whitespace=None;Ok(())}
 pub fn peek_available_using(&mut self,source:&str,final_input:bool,a:&crate::SettingAdmission<'_>,mut diagnostic:impl FnMut(Span,DiagnosticKind,&str)->bool)->io::Result<NativeTokenStep>{self.peek_inner(source.as_bytes(),final_input,Some(a),&mut diagnostic)}
 pub fn next_available(&mut self,source:&str,final_input:bool,mut diagnostic:impl FnMut(Span,DiagnosticKind,&str)->bool)->io::Result<NativeTokenStep>{let step=self.peek_inner(source.as_bytes(),final_input,None,&mut diagnostic)?;if matches!(step,NativeTokenStep::Token(_)){self.commit_peek()?}Ok(step)}
 pub fn next_available_using(&mut self,source:&str,final_input:bool,a:&crate::SettingAdmission<'_>,mut diagnostic:impl FnMut(Span,DiagnosticKind,&str)->bool)->io::Result<NativeTokenStep>{let step=self.peek_inner(source.as_bytes(),final_input,Some(a),&mut diagnostic)?;if matches!(step,NativeTokenStep::Token(_)){self.commit_peek()?}Ok(step)}
 fn visit_inner(&mut self,source:&str,final_input:bool,a:Option<&crate::SettingAdmission<'_>>,mut visitor:impl FnMut(SpanToken)->bool,mut diagnostic:impl FnMut(Span,DiagnosticKind,&str)->bool)->io::Result<NativeTokenProgress>{loop{match self.peek_inner(source.as_bytes(),final_input,a,&mut diagnostic)?{NativeTokenStep::Token(token)=>{if !visitor(token){return Ok(NativeTokenProgress::Stopped)}self.commit_peek()?},NativeTokenStep::NeedInput=>return Ok(NativeTokenProgress::NeedInput),NativeTokenStep::Stopped=>return Ok(NativeTokenProgress::Stopped),NativeTokenStep::End=>return Ok(NativeTokenProgress::Complete)}}}
 pub fn visit_available(&mut self,source:&str,final_input:bool,visitor:impl FnMut(SpanToken)->bool,diagnostic:impl FnMut(Span,DiagnosticKind,&str)->bool)->io::Result<NativeTokenProgress>{self.visit_inner(source,final_input,None,visitor,diagnostic)}
 pub fn visit_available_using(&mut self,source:&str,final_input:bool,a:&crate::SettingAdmission<'_>,visitor:impl FnMut(SpanToken)->bool,diagnostic:impl FnMut(Span,DiagnosticKind,&str)->bool)->io::Result<NativeTokenProgress>{self.visit_inner(source,final_input,Some(a),visitor,diagnostic)}
}

#[cfg(test)]mod actual_byte_transport_tests{
 use super::*;use std::sync::{atomic::{Ordering}};
 #[test]fn actual_original_byte_cursor_keeps_raw_delimiter_split_and_never_reconstructs_decoded_utf8(){
  let bytes="@αbodyα".as_bytes();let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&counter,1<<20,&||Ok(()));let mut cursor=NativeTokenCursor::for_purpose(NativeLexicalPurpose::Original0290Macro);
  let NativeTokenStep::Token(first)=cursor.next_bytes_available_using(bytes,true,&a,|_,_,_|true).unwrap()else{panic!("actual raw token")};assert_eq!(first.kind,TokenKind::String);assert_eq!(first.span,Span::new(0,bytes.len()-1));assert!(std::str::from_utf8(&bytes[first.span.range()]).is_err(),"real byte delimiter ends inside UTF8; decoded facade is invalid");
  let NativeTokenStep::Token(tail)=cursor.next_bytes_available_using(bytes,true,&a,|_,_,_|true).unwrap()else{panic!("actual remaining byte")};assert_eq!(tail.kind,TokenKind::Unknown);assert_eq!(tail.span,Span::new(bytes.len()-1,bytes.len()));assert_eq!(cursor.next_bytes_available_using(bytes,true,&a,|_,_,_|true).unwrap(),NativeTokenStep::End);drop(cursor);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]fn same_native_kernel_preserves_native_utf8_scalar_and_original_actual_byte_boundaries(){
  let bytes="α".as_bytes();let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&counter,1<<20,&||Ok(()));let mut native=NativeTokenCursor::default();let mut original=NativeTokenCursor::for_purpose(NativeLexicalPurpose::Original0290Macro);
  let NativeTokenStep::Token(n)=native.next_bytes_available_using(bytes,true,&a,|_,_,_|true).unwrap()else{panic!("native scalar")};assert_eq!(n.span,Span::new(0,2));let NativeTokenStep::Token(o)=original.next_bytes_available_using(bytes,true,&a,|_,_,_|true).unwrap()else{panic!("actual original byte")};assert_eq!(o.span,Span::new(0,1));assert_eq!(o.kind,TokenKind::Unknown);
  let mut invalid=NativeTokenCursor::default();assert_eq!(invalid.next_bytes_available_using(&[0xff],true,&a,|_,_,_|true).err().unwrap().kind(),io::ErrorKind::InvalidData);
 }
}

#[cfg(test)]
mod original_ascii_identifier_controls {
 use super::*;

 #[test]
 fn original_byte_identifier_resumes_and_preserves_real_lookahead() {
  let raw=b"_name09\xffsuffix";
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
  let admission=crate::SettingAdmission::new(&used,1<<20,&||Ok(()));
  let mut cursor=NativeTokenCursor::for_original_source_bytes(raw);
  for prefix in 1..=7 {
   assert_eq!(cursor.peek_bytes_available_using(&raw[..prefix],false,&admission,|_,_,_|panic!("valid identifier prefix")).unwrap(),NativeTokenStep::NeedInput);
  }
  let NativeTokenStep::Token(token)=cursor.peek_bytes_available_using(raw,true,&admission,|_,_,_|panic!("identifier has no notice")).unwrap()else{panic!("actual identifier")};
  assert_eq!(token.span,Span::new(0,7));
  assert_eq!(token.kind,TokenKind::Ident);
  let facts=cursor.original_ident_facts().unwrap();
  assert_eq!(facts.span(),token.span);
  assert!(!facts.whitespace());
  assert_eq!(facts.read_point(),crate::OriginalLexicalNoticePoint::consumed(7));
  cursor.commit_peek().unwrap();
  assert_eq!(cursor.position(),7);
 }
}

#[cfg(test)]mod actual_directive_stringy_boundary_controls{use super::*;use std::sync::{atomic::{Ordering}};#[test]fn actual_directive_boundary_stops_before_payload_ident_peek_and_quote_resumes_same_cursor(){let raw=b"#error causal failure\nAFTER";let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&used,1<<20,&||Ok(()));let mut cursor=NativeTokenCursor::for_original_source_bytes(raw);for wanted in [b"#".as_slice(),b"error".as_slice()]{let NativeTokenStep::Token(token)=cursor.next_bytes_available_using(raw,true,&a,|_,_,_|panic!("valid scalar")).unwrap()else{panic!("actual directive prefix")};assert_eq!(&raw[token.span.range()],wanted);}let OriginalPreparedBoundary::Productive(at)=cursor.prepare_original_directive_boundary_using(raw,true,&a,|_,_,_|panic!("valid boundary")).unwrap()else{panic!("actual payload boundary")};assert_eq!(at,7);assert!(cursor.peek.is_none());let mut quote=crate::OriginalQuotedFrame::start_directive_using(raw,at,&a).unwrap();let crate::OriginalQuotedStep::Part(part)=quote.next_using(raw,true,&a).unwrap()else{panic!("genuine line String")};let mut value=Vec::new();part.visit_value_bytes(|bytes|{value.extend_from_slice(bytes);Ok::<_,()>(())}).unwrap().unwrap();assert_eq!(value,b"causal failure");quote.continue_cursor(&mut cursor).unwrap();assert_eq!(&raw[cursor.position()..],b"AFTER");drop(quote);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());}}

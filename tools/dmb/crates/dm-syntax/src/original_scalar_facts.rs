use crate::{Span,SettingAdmission,original_scalar_transport::OriginalPunctuationCandidates};use std::io;
#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub struct OriginalPunctuationFacts{span:Span,spelling:&'static str,closed:bool,read:crate::OriginalLexicalNoticePoint}
impl OriginalPunctuationFacts{pub(super) fn issued(span:Span,spelling:&'static str,closed:bool,read:crate::OriginalLexicalNoticePoint)->Self{Self{span,spelling,closed,read}}pub fn read_point(&self)->crate::OriginalLexicalNoticePoint{self.read}pub fn span(&self)->Span{self.span}pub fn spelling(&self)->&'static str{self.spelling}pub fn closed(&self)->bool{self.closed}}
#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub struct OriginalIdentFacts{span:Span,whitespace:bool,read:crate::OriginalLexicalNoticePoint}
impl OriginalIdentFacts{pub(super) fn issued(span:Span,input:&[u8])->Self{Self{span,whitespace:matches!(input.get(span.end),Some(b' '|b'\t')),read:if span.end<input.len(){crate::OriginalLexicalNoticePoint::consumed(span.end)}else{crate::OriginalLexicalNoticePoint::eof(span.end)}}}pub fn span(&self)->Span{self.span}pub fn whitespace(&self)->bool{self.whitespace}pub fn read_point(&self)->crate::OriginalLexicalNoticePoint{self.read}}
#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub struct OriginalWhitespaceFacts{span:Span,tab:bool}
impl OriginalWhitespaceFacts{pub(super) fn issued(span:Span,tab:bool)->Self{Self{span,tab}}pub fn span(&self)->Span{self.span}pub fn tab(&self)->bool{self.tab}}
pub(super) struct OriginalPunctuationCursor{start:usize,at:usize,prefix:[u8;8],length:usize,candidates:OriginalPunctuationCandidates,best:Option<&'static str>,finished:bool,read:crate::OriginalLexicalNoticePoint}
pub(super) enum PunctuationProgress{NeedInput,Complete(Option<(&'static str,Span)>)}
impl OriginalPunctuationCursor{
 pub(super) fn new(input:&[u8],start:usize,a:&SettingAdmission<'_>)->io::Result<Self>{let first=*input.get(start).ok_or(io::ErrorKind::InvalidInput)?;let mut prefix=[0;8];prefix[0]=first;Ok(Self{start,at:start+1,prefix,length:1,candidates:OriginalPunctuationCandidates::for_first_using(first,a)?,best:None,finished:false,read:crate::OriginalLexicalNoticePoint::consumed(start)})}
 pub(super) fn read_point(&self)->crate::OriginalLexicalNoticePoint{self.read}
 fn complete(&mut self)->PunctuationProgress{self.finished=true;PunctuationProgress::Complete(self.best.map(|spelling|(spelling,Span::new(self.start,self.start+spelling.len()))))}
 pub(super) fn advance(&mut self,input:&[u8],final_input:bool,a:&SettingAdmission<'_>)->io::Result<PunctuationProgress>{
  if self.finished{return Err(io::ErrorKind::InvalidInput.into())}loop{if self.candidates.is_empty(){return Ok(self.complete())}if let Some(exact)=self.candidates.exact(&self.prefix[..self.length]){self.best=Some(exact)}if self.candidates.len()==1{return Ok(self.complete())}
   let Some(&next)=input.get(self.at)else{if final_input{self.read=crate::OriginalLexicalNoticePoint::eof(self.at);}return Ok(if final_input{self.complete()}else{PunctuationProgress::NeedInput})};self.read=crate::OriginalLexicalNoticePoint::consumed(self.at);if self.length==self.prefix.len(){return Err(io::Error::new(io::ErrorKind::InvalidData,"actual pinned punctuation exceeds its real bounded native table"))}self.prefix[self.length]=next;self.length+=1;self.at+=1;self.candidates=self.candidates.narrowed_using(&self.prefix[..self.length],a)?;
  }
 }
}

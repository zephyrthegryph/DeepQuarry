//! Actual raw-acquisition frame for the Original demand owner. No PreparedSource
//! or decoded facade is requested; bytes are loaned by the existing provider
//! against this SAME lease on every demand. This is not a frontend/EOF grant.
use super::original_lexical_frame::OriginalLexicalFrameIdentity;
use crate::{SourceProvider,SourceAcquisitionLease};
use dm_syntax::{NativeTokenCursor,SettingAdmission};
use std::{io,path::Path};

#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub(crate) enum OriginalRawNoticeSeverity{Error,Warning}
#[derive(Clone,Copy,Debug)]enum NoticeMessage{Static(&'static str),Illegal(u8)}
#[derive(Clone,Copy,Debug)]pub(crate) struct OriginalRawNotice{pub(crate) point:dm_syntax::OriginalLexicalNoticePoint,pub(crate) span:dm_syntax::Span,pub(crate) severity:OriginalRawNoticeSeverity,pub(crate) error_type:Option<&'static str>,message:NoticeMessage}
impl OriginalRawNotice{
 fn error(point:dm_syntax::OriginalLexicalNoticePoint,span:dm_syntax::Span,message:&'static str)->Self{Self{point,span,severity:OriginalRawNoticeSeverity::Error,error_type:None,message:NoticeMessage::Static(message)}}
 pub(crate) fn write_message(&self,out:&mut impl std::fmt::Write)->std::fmt::Result{match self.message{NoticeMessage::Static(text)=>out.write_str(text),NoticeMessage::Illegal(byte)=>{write!(out,"illegal byte 0x{byte:x}")?;if (b' '..=b'~').contains(&byte){write!(out," ({:?})",byte as char)?;}Ok(())}}}
}
pub(crate) enum OriginalPhysicalLexeme<'s>{FinalNewline{at:usize},Scalar{token:dm_syntax::SpanToken,number:Option<&'s dm_syntax::OriginalNumberFacts>,comment:Option<&'s dm_syntax::OriginalCommentFacts>,resource:Option<&'s dm_syntax::OriginalResourceFacts>,punctuation:Option<&'s dm_syntax::OriginalPunctuationFacts>,ident:Option<&'s dm_syntax::OriginalIdentFacts>,whitespace:Option<&'s dm_syntax::OriginalWhitespaceFacts>},Quote(dm_syntax::OriginalQuotedPart<'s>),QuoteFailure{message:&'static str,recovery:dm_syntax::OriginalQuotedPart<'s>}}
pub(super) struct OriginalRawFrame{identity:OriginalLexicalFrameIdentity,lexer:OriginalRawLexer,failed:bool,ended:bool}
impl OriginalRawFrame{
 pub(super) fn open(provider:&dyn SourceProvider,path:&Path,max_bytes:usize,before_decode:&mut dyn FnMut(usize,bool,bool)->io::Result<()>,a:&SettingAdmission<'_>)->io::Result<Option<Self>>{
  a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;
  // None is the provider's actual recorded bounded negative read. An unissued
  // raw provider is NotConnected; no String inspection or fake empty source.
  let Some(acquisition)=provider.original_raw_source_checked(path,max_bytes,before_decode)?else{return Ok(None)};
  Self::from_opened(provider,acquisition,a).map(Some)
 }
 pub(super) fn from_opened(provider:&dyn SourceProvider,acquisition:SourceAcquisitionLease,a:&SettingAdmission<'_>)->io::Result<Self>{
  // Receipt/currentness is checked by the real provider before a frame tag is
  // minted. Equality of path/text/span cannot replace that private issuer.
  let cursor={let bytes=provider.original_source_bytes(&acquisition)?.ok_or_else(||io::Error::new(io::ErrorKind::NotConnected,"actual Original raw-byte issuer is unavailable"))?;NativeTokenCursor::for_original_source_bytes(bytes)};
  Ok(Self{identity:OriginalLexicalFrameIdentity::issue(acquisition,a)?,lexer:OriginalRawLexer::new(cursor,true,a)?,failed:false,ended:false})
 }
 pub(super) fn read_point(&self)->Option<dm_syntax::OriginalLexicalNoticePoint>{self.lexer.read_point}
 pub(super) fn identity(&self)->&OriginalLexicalFrameIdentity{&self.identity}
 pub(super) fn acquisition(&self)->&SourceAcquisitionLease{self.identity.acquisition()}
 /// Borrow actual current bytes and mutate ONLY the SAME scalar cursor. The
 /// final-token/macro owner must observe quote brackets here, before rescan;
 /// replacement token identity does not authorize a fresh physical read.
 pub(super) fn with_current_cursor<T>(&mut self,provider:&dyn SourceProvider,a:&SettingAdmission<'_>,run:impl FnOnce(&[u8],&mut NativeTokenCursor,&OriginalLexicalFrameIdentity)->io::Result<T>)->io::Result<T>{
  if self.failed||self.ended||!self.identity.admitted_by(a){return Err(io::Error::new(io::ErrorKind::InvalidInput,"raw frame is failed, ended or belongs to another actual host"))}
  let result=(||{a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;let bytes=provider.original_source_bytes(self.identity.acquisition())?.ok_or_else(||io::Error::new(io::ErrorKind::NotConnected,"actual Original raw-byte issuer was withdrawn"))?;run(bytes,&mut self.lexer.cursor,&self.identity)})();
  if result.is_err(){self.failed=true}result
 }
 /// Loan SAME current bytes then drive the SAME physical/initial lexer core.
 pub(super) fn next_physical_using<T>(&mut self,provider:&dyn SourceProvider,a:&SettingAdmission<'_>,mut lexical_error:impl FnMut(OriginalRawNotice,&[u8],&OriginalLexicalFrameIdentity)->io::Result<()>,mut consume:impl FnMut(OriginalPhysicalLexeme<'_>,&[u8],&OriginalLexicalFrameIdentity)->io::Result<T>)->io::Result<Option<T>>{
  if self.failed||self.ended||!self.identity.admitted_by(a){return Err(io::ErrorKind::InvalidInput.into())}
  // Both callbacks are synchronous and can borrow the same exact frame
  // identity while the disjoint cursor advances. Only escaped tokens need
  // to retain that identity.
  let identity=&self.identity;
  let lexer=&mut self.lexer;
  let result=(||{
   let bytes=original_fill_bucket!(Provider,provider.original_source_bytes(identity.acquisition()))?.ok_or_else(||io::Error::new(io::ErrorKind::NotConnected,"actual current raw byte view is unavailable"))?;
   original_fill_bucket!(Lex,lexer.next_using(bytes,a,|notice|lexical_error(notice,bytes,identity),|event,bytes|consume(event,bytes,identity)))
  })();
  if result.is_err(){self.failed=true}
  result
 }
 /// Only the raw lexer owner calls this after its actual End event. A macro
 /// Stop or temporary input pause must never retire an open source as EOF.
 pub(super) fn finish_actual_end(&mut self,provider:&dyn SourceProvider,a:&SettingAdmission<'_>)->io::Result<()>{
  if !self.lexer.physical_end{self.failed=true;return Err(io::Error::new(io::ErrorKind::InvalidInput,"raw frame did not produce its genuine final newline and End"))}
  let actual=self.with_current_cursor(provider,a,|bytes,cursor,_|{match cursor.peek_bytes_available_using(bytes,true,a,|_,_,_|false)?{dm_syntax::NativeTokenStep::End=>Ok(()),_=>Err(io::Error::new(io::ErrorKind::InvalidInput,"raw frame has not consumed genuine lexer EOF"))}});if actual.is_ok(){self.ended=true}actual
 }
}
/// One shared lexical DATA state for actual physical files and explicitly
/// nonphysical initial definitions. It owns no acquisition or model grant.
#[derive(Clone,Copy,Eq,PartialEq)]enum OriginalDirectiveLexicalState{Disabled,None,Hash,Ordinary,Stringy}
fn crossed_directive_line(state:&mut OriginalDirectiveLexicalState,bytes:&[u8]){if *state!=OriginalDirectiveLexicalState::Disabled&&bytes.contains(&b'\n'){*state=OriginalDirectiveLexicalState::None;}}
fn observe_directive_scalar(state:&mut OriginalDirectiveLexicalState,token:dm_syntax::SpanToken,bytes:&[u8],number:Option<&dm_syntax::OriginalNumberFacts>){
 if *state==OriginalDirectiveLexicalState::Disabled{return}crossed_directive_line(state,&bytes[token.span.range()]);
 // read_ident actually consumes+puts back the next nonident byte. A newline
 // resets directive mode BEFORE the ident branch tests the prior Hash state.
 if token.kind==dm_syntax::TokenKind::Ident&&bytes.get(token.span.end)==Some(&b'\n'){*state=OriginalDirectiveLexicalState::None;}
 if let Some(number)=number{let point=number.notice_point();if point.offset()<bytes.len()&&bytes[point.offset()]==b'\n'{*state=OriginalDirectiveLexicalState::None;}}
 let text=&bytes[token.span.range()];if text==b"#"&&*state==OriginalDirectiveLexicalState::None{*state=OriginalDirectiveLexicalState::Hash;}
 else if token.kind==dm_syntax::TokenKind::Ident&&*state==OriginalDirectiveLexicalState::Hash{*state=if matches!(text,b"warn"|b"error"){OriginalDirectiveLexicalState::Stringy}else{OriginalDirectiveLexicalState::Ordinary};}
}
pub(crate) struct OriginalRawLexer{read_point:Option<dm_syntax::OriginalLexicalNoticePoint>,directive:OriginalDirectiveLexicalState,quotes:Vec<dm_syntax::OriginalQuotedFrame>,cursor:NativeTokenCursor,failed:bool,final_newline:bool,physical_end:bool,append_final_newline:bool,found_illegal:bool,quote_credit:dm_syntax::SettingRootLease}
impl OriginalRawLexer{
 fn new(cursor:NativeTokenCursor,append_final_newline:bool,a:&SettingAdmission<'_>)->io::Result<Self>{Ok(Self{read_point:None,directive:if append_final_newline{OriginalDirectiveLexicalState::None}else{OriginalDirectiveLexicalState::Disabled},quotes:Vec::new(),cursor,failed:false,final_newline:false,physical_end:false,append_final_newline,found_illegal:false,quote_credit:a.reserve(0).map_err(|e|a.take_operational_error().unwrap_or(e))?})}
 pub(crate) fn for_initial_definition(a:&SettingAdmission<'_>)->io::Result<Self>{Self::new(NativeTokenCursor::for_original_initial_definition(),false,a)}
 fn push_quote(&mut self,quote:dm_syntax::OriginalQuotedFrame,a:&SettingAdmission<'_>)->io::Result<()>{
  if self.quotes.len()==self.quotes.capacity(){let capacity=self.quotes.capacity().max(2).checked_mul(2).ok_or(io::ErrorKind::OutOfMemory)?;let peak=capacity.checked_mul(std::mem::size_of::<dm_syntax::OriginalQuotedFrame>()).and_then(|n|n.checked_mul(4)).ok_or(io::ErrorKind::OutOfMemory)?;a.grow(&mut self.quote_credit,peak).map_err(|e|a.take_operational_error().unwrap_or(e))?;let mut next=Vec::new();next.try_reserve_exact(capacity).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;let growth=next.capacity().checked_sub(self.quotes.capacity()).and_then(|n|n.checked_mul(std::mem::size_of::<dm_syntax::OriginalQuotedFrame>())).ok_or(io::ErrorKind::OutOfMemory)?;let release=peak.checked_sub(growth).ok_or(io::ErrorKind::OutOfMemory)?;next.append(&mut self.quotes);self.quotes=next;a.shrink(&mut self.quote_credit,release).map_err(|e|a.take_operational_error().unwrap_or(e))?;}self.quotes.push(quote);Ok(())
 }
 /// Exactly one actual physical token, before any macro rescan. A substituted
 /// token cannot call this observation path or close this file's live quote.
 /// The callback must produce owned DATA before the raw byte/fact loan ends.
 pub(crate) fn next_using<T>(&mut self,bytes:&[u8],a:&SettingAdmission<'_>,mut lexical_error:impl FnMut(OriginalRawNotice)->io::Result<()>,mut consume:impl FnMut(OriginalPhysicalLexeme<'_>,&[u8])->io::Result<T>)->io::Result<Option<T>>{
  if self.failed||!a.matches_lease_domain(&self.quote_credit){return Err(io::ErrorKind::InvalidInput.into())}
  let result=(||{loop{
   a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;
   if self.quotes.last().is_some_and(|quote|quote.expression_start().is_none()){
    let quote=self.quotes.last_mut().unwrap();match quote.next_using(bytes,true,a)?{
     dm_syntax::OriginalQuotedStep::Part(part)=>{self.read_point=Some(part.read_point());let final_part=matches!(part.kind(),dm_syntax::OriginalQuotedPartKind::String|dm_syntax::OriginalQuotedPartKind::End);crossed_directive_line(&mut self.directive,part.raw_spelling());self.found_illegal=false;let value=consume(OriginalPhysicalLexeme::Quote(part),bytes)?;if final_part{quote.continue_cursor(&mut self.cursor)?;self.quotes.pop();}else{quote.continue_cursor(&mut self.cursor)?}return Ok(Some(value))},
     dm_syntax::OriginalQuotedStep::LexicalFailure{message,recovery}=>{self.read_point=Some(recovery.read_point());let point=recovery.notice_point().ok_or_else(||io::Error::new(io::ErrorKind::InvalidData,"actual quote failure has no saved native read location"))?;lexical_error(OriginalRawNotice::error(point,recovery.token_span(),message))?;crossed_directive_line(&mut self.directive,recovery.raw_spelling());self.found_illegal=false;let value=consume(OriginalPhysicalLexeme::QuoteFailure{message,recovery},bytes)?;quote.continue_cursor(&mut self.cursor)?;self.quotes.pop();return Ok(Some(value))},
     dm_syntax::OriginalQuotedStep::Complete=>{quote.continue_cursor(&mut self.cursor)?;self.quotes.pop();continue},dm_syntax::OriginalQuotedStep::Expression=>{},dm_syntax::OriginalQuotedStep::NeedInput=>return Err(io::Error::new(io::ErrorKind::InvalidData,"complete current raw acquisition has an unfinished lexical demand")),
    }
   }
   let prior_position=self.cursor.position();
   let boundary=if self.directive==OriginalDirectiveLexicalState::Stringy{self.cursor.prepare_original_directive_boundary_using(bytes,true,a,|_,_,_|true)?}else{self.cursor.prepare_original_boundary_using(bytes,true,a,|_,_,_|true)?};
   match boundary{dm_syntax::OriginalPreparedBoundary::Productive(_)|dm_syntax::OriginalPreparedBoundary::End=>{},dm_syntax::OriginalPreparedBoundary::Stopped=>return Err(io::Error::new(io::ErrorKind::Interrupted,"actual raw lexical sink stopped")),dm_syntax::OriginalPreparedBoundary::NeedInput=>return Err(io::ErrorKind::InvalidData.into())}
   let productive=self.cursor.position();crossed_directive_line(&mut self.directive,&bytes[prior_position..productive]);
   if bytes.get(productive)==Some(&b'\n'){crossed_directive_line(&mut self.directive,b"\n");}
   if self.directive==OriginalDirectiveLexicalState::Stringy&&productive<bytes.len(){self.directive=OriginalDirectiveLexicalState::None;let quote=dm_syntax::OriginalQuotedFrame::start_directive_using(bytes,productive,a)?;self.push_quote(quote,a)?;continue}
   if let Some(quote)=dm_syntax::OriginalQuotedFrame::start_using(bytes,self.cursor.position(),a)?{self.push_quote(quote,a)?;continue}
   match self.cursor.peek_bytes_available_using(bytes,true,a,|_,_,_|true)?{
    dm_syntax::NativeTokenStep::Token(token)=>{
     self.read_point=Some(if let Some(facts)=self.cursor.original_number_facts(){facts.notice_point()}
      else if let Some(facts)=self.cursor.original_ident_facts(){facts.read_point()}
      else if let Some(facts)=self.cursor.original_punctuation_facts(){facts.read_point()}
      else if let Some(facts)=self.cursor.original_resource_facts(){if facts.recovering(){dm_syntax::OriginalLexicalNoticePoint::eof(bytes.len())}else{dm_syntax::OriginalLexicalNoticePoint::consumed(token.span.end.checked_sub(1).ok_or(io::ErrorKind::InvalidData)?)}}
      else if let Some(facts)=self.cursor.original_comment_facts(){if bytes.get(token.span.start..token.span.start+2)==Some(b"//"){if bytes.get(token.span.end).is_some(){dm_syntax::OriginalLexicalNoticePoint::consumed(token.span.end)}else{dm_syntax::OriginalLexicalNoticePoint::eof(bytes.len())}}else if facts.notice_point().is_some(){dm_syntax::OriginalLexicalNoticePoint::eof(bytes.len())}else{dm_syntax::OriginalLexicalNoticePoint::consumed(token.span.end.checked_sub(1).ok_or(io::ErrorKind::InvalidData)?)}}
      else{dm_syntax::OriginalLexicalNoticePoint::consumed(token.span.end.checked_sub(1).ok_or(io::ErrorKind::InvalidData)?)});

     observe_directive_scalar(&mut self.directive,token,bytes,self.cursor.original_number_facts());
     if let Some((message,span,point))=self.cursor.original_pending_lexical_notice(){lexical_error(OriginalRawNotice::error(point,span,message))?;}
     if let Some(comment)=self.cursor.original_comment_facts(){for span in comment.warning_spans(){lexical_error(OriginalRawNotice{point:dm_syntax::OriginalLexicalNoticePoint::consumed(span.start),span:*span,severity:OriginalRawNoticeSeverity::Warning,error_type:None,message:NoticeMessage::Static(dm_syntax::OriginalCommentFacts::warning_message())})?;}if comment.kind()==dm_syntax::OriginalCommentKind::None{self.cursor.commit_peek()?;continue}}
     if token.kind==dm_syntax::TokenKind::Unknown{if !self.found_illegal{let byte=*bytes.get(token.span.start).ok_or(io::ErrorKind::InvalidInput)?;lexical_error(OriginalRawNotice{point:dm_syntax::OriginalLexicalNoticePoint::consumed(token.span.start),span:token.span,severity:OriginalRawNoticeSeverity::Error,error_type:None,message:NoticeMessage::Illegal(byte)})?;self.found_illegal=true;}self.cursor.commit_peek()?;continue}

     // Only this freshly consumed raw event may advance an active quote.
     // Closing interpolation bracket becomes the next Part/End, not RBracket.
     if let Some(quote)=self.quotes.last_mut().filter(|quote|quote.expression_start().is_some()){if quote.observe_expression_token_using(token,bytes,a)?{self.cursor.commit_original_interpolation_close()?;continue}}
     self.found_illegal=false;let value=consume(OriginalPhysicalLexeme::Scalar{token,number:self.cursor.original_number_facts(),comment:self.cursor.original_comment_facts(),resource:self.cursor.original_resource_facts(),punctuation:self.cursor.original_punctuation_facts(),ident:self.cursor.original_ident_facts(),whitespace:self.cursor.original_whitespace_facts()},bytes)?;self.cursor.commit_peek()?;return Ok(Some(value))
    },dm_syntax::NativeTokenStep::End=>{self.read_point=Some(dm_syntax::OriginalLexicalNoticePoint::eof(bytes.len()));if self.append_final_newline&&!self.final_newline{self.final_newline=true;self.found_illegal=false;let value=consume(OriginalPhysicalLexeme::FinalNewline{at:bytes.len()},bytes)?;return Ok(Some(value))}self.physical_end=true;return Ok(None)},dm_syntax::NativeTokenStep::Stopped=>return Err(io::Error::new(io::ErrorKind::Interrupted,"actual raw lexical diagnostic consumer stopped")),dm_syntax::NativeTokenStep::NeedInput=>return Err(io::Error::new(io::ErrorKind::InvalidData,"complete raw acquisition cannot fabricate a partial scalar")),
   }
  }})();if result.is_err(){self.failed=true}result
 }
}

#[cfg(test)]mod tests{
 use super::*;use std::sync::{atomic::{AtomicBool, Ordering}};
 struct Provider{source:SourceAcquisitionLease,fail:AtomicBool,negative:bool}
 impl Provider{fn actual_utf8()->Self{Self{source:SourceAcquisitionLease::from_raw_original_bytes(b"actual".to_vec(),()),fail:AtomicBool::new(false),negative:false}}}
 impl SourceProvider for Provider{
  fn read(&self,_:&Path)->Result<String,String>{panic!("raw frame must never request prepared/decoded read")}
  fn original_raw_source_checked(&self,_:&Path,max:usize,before:&mut dyn FnMut(usize,bool,bool)->io::Result<()>)->io::Result<Option<SourceAcquisitionLease>>{if self.negative{return Ok(None)}if self.source.source_text().len()>max{return Err(io::ErrorKind::OutOfMemory.into())}before(self.source.source_text().len(),false,false)?;Ok(Some(self.source.clone()))}
  fn original_source_bytes<'a>(&'a self,lease:&'a SourceAcquisitionLease)->io::Result<Option<&'a[u8]>>{if self.fail.swap(false,Ordering::AcqRel){return Err(io::Error::from_raw_os_error(1450))}if !self.source.same_binding(lease){return Err(io::ErrorKind::InvalidInput.into())}Ok(Some(lease.source_text().as_bytes()))}
 }
 #[test]fn raw_frame_contract_keeps_same_acquisition_and_last_frame_alias_resource_owner_without_preparation(){
  let provider=Provider::actual_utf8();let counter=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&counter,1<<20,&||Ok(()));let mut before_calls=0;let mut before=|_,_,_|{before_calls+=1;Ok(())};let frame=OriginalRawFrame::open(&provider,Path::new("actual.dm"),64,&mut before,&a).unwrap().unwrap();assert_eq!(before_calls,1);assert!(frame.acquisition().same_binding(&provider.source));let alias=frame.identity().clone();let next=OriginalRawFrame::open(&provider,Path::new("actual.dm"),64,&mut|_,_,_|Ok(()),&a).unwrap().unwrap();assert!(!frame.identity().same_frame(next.identity()),"new open is another real lexical frame despite same acquisition");drop(frame);drop(next);assert!(counter.load(Ordering::Acquire)>dm_syntax::SettingChargeCounter::root_allocation_bytes());drop(alias);assert_eq!(counter.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]fn raw_frame_contract_preserves_first_provider_error_and_poison_forbids_retry_or_false_eof(){
  let provider=Provider::actual_utf8();let counter=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&counter,1<<20,&||Ok(()));let mut frame=OriginalRawFrame::open(&provider,Path::new("actual.dm"),64,&mut|_,_,_|Ok(()),&a).unwrap().unwrap();provider.fail.store(true,Ordering::Release);assert_eq!(frame.with_current_cursor(&provider,&a,|_,_,_|Ok(())).err().unwrap().raw_os_error(),Some(1450));assert_eq!(frame.with_current_cursor(&provider,&a,|_,_,_|Ok(())).err().unwrap().kind(),io::ErrorKind::InvalidInput);assert_eq!(frame.finish_actual_end(&provider,&a).err().unwrap().kind(),io::ErrorKind::InvalidInput);drop(frame);
  let mut fresh=OriginalRawFrame::open(&provider,Path::new("actual.dm"),64,&mut|_,_,_|Ok(()),&a).unwrap().unwrap();while fresh.next_physical_using(&provider,&a,|_,_,_|Ok(()),|_,_,_|Ok(())).unwrap().is_some(){}fresh.finish_actual_end(&provider,&a).unwrap();assert_eq!(fresh.with_current_cursor(&provider,&a,|_,_,_|Ok(())).err().unwrap().kind(),io::ErrorKind::InvalidInput);drop(fresh);assert_eq!(counter.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]fn actual_raw_quote_observation_precedes_rescan_and_nested_string_bracket_never_closes_parent(){
  let provider=Provider{source:SourceAcquisitionLease::from_raw_original_bytes(br#""a[ "]" ]tail""#.to_vec(),()),fail:AtomicBool::new(false),negative:false};let counter=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&counter,1<<20,&||Ok(()));let mut frame=OriginalRawFrame::open(&provider,Path::new("quote.dm"),256,&mut|_,_,_|Ok(()),&a).unwrap().unwrap();let mut kinds=Vec::new();
  while let Some(kind)=frame.next_physical_using(&provider,&a,|_,_,_|panic!("no speculative or actual lexical errors"),|event,bytes,tag|{assert!(tag.acquisition().same_binding(&provider.source));Ok(match event{OriginalPhysicalLexeme::Quote(part)=>match part.kind(){dm_syntax::OriginalQuotedPartKind::Begin=>"begin",dm_syntax::OriginalQuotedPartKind::String=>"string",dm_syntax::OriginalQuotedPartKind::Part=>"part",dm_syntax::OriginalQuotedPartKind::End=>"end"},OriginalPhysicalLexeme::FinalNewline{..}=>"final-newline",OriginalPhysicalLexeme::Scalar{token,..}=>{assert_ne!(&bytes[token.span.range()],b"]","closing interpolation is an actual End/Part event");"scalar"},OriginalPhysicalLexeme::QuoteFailure{..}=>panic!("no recovery expected")})}).unwrap(){kinds.push(kind);}
  assert_eq!(kinds,["begin","string","end","final-newline"]);frame.finish_actual_end(&provider,&a).unwrap();drop(frame);assert_eq!(counter.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]
 fn lexical_notice_and_recovery_borrow_the_live_frame_identity_in_order() {
  let provider = Provider {
   source: SourceAcquisitionLease::from_raw_original_bytes(b"\"unterminated".to_vec(), ()),
   fail: AtomicBool::new(false),
   negative: false,
  };
  let counter = dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
  let a = SettingAdmission::new(&counter, 1<<20, &|| Ok(()));
  let mut frame = OriginalRawFrame::open(&provider, Path::new("quote.dm"), 256, &mut |_,_,_| Ok(()), &a).unwrap().unwrap();
  let expected = std::ptr::from_ref(frame.identity());
  let saw_notice = std::cell::Cell::new(false);
  let recovered = frame.next_physical_using(
   &provider, &a,
   |notice, bytes, identity| {
    assert_eq!(std::ptr::from_ref(identity), expected);
    assert!(identity.acquisition().same_binding(&provider.source));
    assert_eq!(bytes, b"\"unterminated");
    assert_eq!(notice.severity, OriginalRawNoticeSeverity::Error);
    assert!(!saw_notice.replace(true));
    Ok(())
   },
   |event, bytes, identity| {
    assert_eq!(std::ptr::from_ref(identity), expected);
    assert_eq!(bytes, b"\"unterminated");
    assert!(saw_notice.get());
    Ok(matches!(event, OriginalPhysicalLexeme::QuoteFailure { .. }))
   },
  ).unwrap();
  assert_eq!(recovered, Some(true));
  provider.fail.store(true, Ordering::Release);
  assert_eq!(
   frame.next_physical_using(&provider, &a, |_,_,_| panic!("failed loan sent notice"), |_,_,_| Ok(())).unwrap_err().raw_os_error(),
   Some(1450),
  );
  assert_eq!(
   frame.next_physical_using(&provider, &a, |_,_,_| panic!("failed frame sent notice"), |_,_,_| Ok(())).unwrap_err().kind(),
   io::ErrorKind::InvalidInput,
  );
  drop(frame);
  assert_eq!(counter.load(Ordering::Acquire), dm_syntax::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]fn actual_raw_first_quote_part_does_not_lex_or_diagnose_the_later_source_tail(){
  let provider=Provider{source:SourceAcquisitionLease::from_raw_original_bytes(br#""head[1]tail" @"unterminated"#.to_vec(),()),fail:AtomicBool::new(false),negative:false};let counter=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&counter,1<<20,&||Ok(()));let mut frame=OriginalRawFrame::open(&provider,Path::new("quote.dm"),256,&mut|_,_,_|Ok(()),&a).unwrap().unwrap();let token=frame.next_physical_using(&provider,&a,|_,_,_|panic!("future lexical diagnostic demanded before actual first token"),|event,_,_|{let OriginalPhysicalLexeme::Quote(part)=event else{panic!("first actual quoted part")};assert_eq!(part.kind(),dm_syntax::OriginalQuotedPartKind::Begin);Ok(part.token_span())}).unwrap().unwrap();assert_eq!(token,dm_syntax::Span::new(0,6));drop(frame);assert_eq!(counter.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
 }

}

#[cfg(test)]mod directive_lexical_tests{
 use super::*;use std::sync::{atomic::{Ordering}};
 fn step(lexer:&mut OriginalRawLexer,bytes:&[u8],a:&dm_syntax::SettingAdmission<'_>)->Option<(String,String)>{lexer.next_using(bytes,a,|_|Ok(()),|event,bytes|{match event{
  OriginalPhysicalLexeme::Scalar{token,..}=>Ok((format!("{:?}",token.kind),std::str::from_utf8(&bytes[token.span.range()]).unwrap().to_owned())),
  OriginalPhysicalLexeme::Quote(part)=>{let mut text=Vec::new();part.visit_value_bytes(|p|{text.extend_from_slice(p);Ok::<_,io::Error>(())})?.map_err(|_|io::ErrorKind::InvalidData)?;Ok((format!("{:?}",part.kind()),String::from_utf8(text).unwrap()))},
  OriginalPhysicalLexeme::FinalNewline{..}=>Ok(("final".into(),"\n".into())),_=>Err(io::ErrorKind::InvalidData.into()),
 }}).unwrap()}
 #[test]fn actual_physical_warn_consumes_line_as_same_string_and_resets_before_next_physical_file_tokens(){
  let bytes=b"#warn hello \"text\"\n/proc/p()\n";let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=dm_syntax::SettingAdmission::new(&used,1<<20,&||Ok(()));let mut lexer=OriginalRawLexer::new(NativeTokenCursor::for_original_source_bytes(bytes),true,&a).unwrap();assert_eq!(step(&mut lexer,bytes,&a).unwrap().1,"#");assert_eq!(step(&mut lexer,bytes,&a).unwrap().1,"warn");assert_eq!(step(&mut lexer,bytes,&a).unwrap(),("String".into(),"hello \"text\"".into()));assert_eq!(step(&mut lexer,bytes,&a).unwrap().1,"/");drop(lexer);assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]fn actual_ident_lookahead_newline_cancels_stringy_and_initial_definition_has_no_file_directive_state(){
  let bytes=b"#warn\nword\n";let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=dm_syntax::SettingAdmission::new(&used,1<<20,&||Ok(()));let mut physical=OriginalRawLexer::new(NativeTokenCursor::for_original_source_bytes(bytes),true,&a).unwrap();step(&mut physical,bytes,&a);step(&mut physical,bytes,&a);assert_eq!(step(&mut physical,bytes,&a).unwrap().1,"\n");assert_eq!(step(&mut physical,bytes,&a).unwrap().0,"Ident");let mut initial=OriginalRawLexer::for_initial_definition(&a).unwrap();step(&mut initial,b"#warn word",&a);step(&mut initial,b"#warn word",&a);assert_eq!(step(&mut initial,b"#warn word",&a).unwrap(),("Ident".into(),"word".into()));drop((physical,initial));assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
 }
}

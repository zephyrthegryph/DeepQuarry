//! Directive acquisition over the SAME pending raw/macro/include cursor.
//! Requests move actual tokens to DirectivePass; they grant neither source EOF
//! nor a semantic model. No raw line scanner, string relex or second dictionary.
use super::{original_driver::RawSourceDriver,original_macro_source::OriginalMacroHost,original_raw_inputs::OriginalRawNoticeSink,original_directive_arguments::{Expected,ExpectProgress},original_define_demand::{OriginalDefineDemand,DefineDemandProgress},original_conditional::Directive};
use crate::{SourceProvider,macro_expansion::{OriginalMacroToken as Token,OriginalMacroValue as Value,OriginalMacroText as Text,OriginalDefinedMacro as Defined,OriginalMacroOrigin as Origin}};
use dm_syntax::SettingAdmission;use std::io;
/// Actual failure sites differ: expect/definition errors use the currently
/// consumed physical reader, while unknown directives use last_input_loc.
#[derive(Clone,Copy)]pub(super) enum FailurePoint{CurrentReader,LastOuter}
pub(super) enum DirectiveRequest{
 Ignored,Include{path:Token<'static>},Define(Defined<'static>),Undef{name:Token<'static>},
 Message{warning:bool,text:Token<'static>},Pragma{name:Token<'static>},Conditional(Directive),
 SourceFailure{message:Text,point:FailurePoint},
}
fn expect(driver:&mut RawSourceDriver,provider:&dyn SourceProvider,notices:&mut dyn OriginalRawNoticeSink,host:&mut dyn OriginalMacroHost,kind:Expected,pattern:&'static str,a:&SettingAdmission<'_>)->io::Result<ExpectProgress>{
 driver.with_directive_source_using(provider,notices,host,a,|cursor,source|super::original_directive_arguments::expect_using(cursor,source,kind,Some(pattern),a))
}
fn no_pause(progress:ExpectProgress)->io::Result<Result<Token<'static>,Text>>{match progress{ExpectProgress::Token(token)=>Ok(Ok(token)),ExpectProgress::SourceFailure(message)=>Ok(Err(message)),ExpectProgress::NeedInput=>Err(io::Error::new(io::ErrorKind::WouldBlock,"synchronous actual directive raw input is not available"))}}
/// No callback/source loan survives another raw token request. Hint callback
/// must register from the SAME current reader before this loop continues.
pub(super) fn read_using(driver:&mut RawSourceDriver,provider:&dyn SourceProvider,notices:&mut dyn OriginalRawNoticeSink,host:&mut dyn OriginalMacroHost,a:&SettingAdmission<'_>,hint:&mut dyn FnMut(&mut RawSourceDriver,Origin,&'static str)->io::Result<()>)->io::Result<DirectiveRequest>{
 macro_rules! required{($kind:expr,$pattern:expr)=>{match no_pause(expect(driver,provider,notices,host,$kind,$pattern,a)?)?{Ok(token)=>token,Err(message)=>return Ok(DirectiveRequest::SourceFailure{message,point:FailurePoint::CurrentReader})}}}
 let command=required!(Expected::Identifier,"Token::Ident(ident, _)");
 let Value::Ident{spelling,..}=&command.value else{return Err(io::ErrorKind::InvalidData.into())};
 let conditional=match spelling.get(){"if"=>Some(Directive::If),"ifdef"=>Some(Directive::Ifdef),"ifndef"=>Some(Directive::Ifndef),"elif"=>Some(Directive::Elif),"else"=>Some(Directive::Else),"endif"=>Some(Directive::Endif),_=>None};
 if let Some(directive)=conditional{return Ok(DirectiveRequest::Conditional(directive))}
 let disabled=driver.directive_disabled_using(a)?;
 match spelling.get(){
  // Inactive definitions alone drain the SAME raw cursor through LF. In
  // particular a stringify # must not re-enter top-level directive dispatch.
  "define" if disabled=>loop{match driver.next_directive_raw_using(provider,notices,host,a)?{
   crate::macro_expansion::OriginalMacroRawStep::Token(token)=>if matches!(&token.value,Value::Punct("\n")){break Ok(DirectiveRequest::Ignored)},
   crate::macro_expansion::OriginalMacroRawStep::NeedInput=>break Err(io::Error::new(io::ErrorKind::WouldBlock,"synchronous inactive definition raw input is not available")),
   crate::macro_expansion::OriginalMacroRawStep::End=>{let mut message=Text::new(a)?;message.push_str("unexpected EOF",a)?;break Ok(DirectiveRequest::SourceFailure{message,point:FailurePoint::CurrentReader})},
  }},
  // The other inactive branches consume NO rest-of-line tokens. Success LF
  // is emitted only by the owner calling finish_directive(true).
  "include"|"undef"|"warn"|"error"|"pragma" if disabled=>Ok(DirectiveRequest::Ignored),
  "include"=>{let path=required!(Expected::String,"Token::String(path_str)");drop(required!(Expected::Newline,"Token::Punct(Punctuation::Newline)"));Ok(DirectiveRequest::Include{path})},
  "define"=>{
   let name=required!(Expected::Identifier,"Token::Ident(define_name, _)");let docs=host.take_docs_for_define(a)?;let mut definition=OriginalDefineDemand::new(name,docs,a)?;
   loop{match driver.advance_define_using(&mut definition,provider,notices,host,a)?{
    DefineDemandProgress::Complete(definition)=>return Ok(DirectiveRequest::Define(definition)),
    DefineDemandProgress::Hint{origin,message}=>hint(driver,origin,message)?,
    DefineDemandProgress::SourceFailure{message,..}=>{let mut text=Text::new(a)?;text.push_str(message,a)?;return Ok(DirectiveRequest::SourceFailure{message:text,point:FailurePoint::CurrentReader})},
    DefineDemandProgress::NeedInput=>return Err(io::Error::new(io::ErrorKind::WouldBlock,"synchronous actual definition raw input is not available")),
   }}
  },
  "undef"=>{let name=required!(Expected::Identifier,"Token::Ident(define_name, _)");drop(required!(Expected::Newline,"Token::Punct(Punctuation::Newline)"));Ok(DirectiveRequest::Undef{name})},
  "warn"|"error"=>{let text=required!(Expected::String,"Token::String(text)");Ok(DirectiveRequest::Message{warning:spelling.get()=="warn",text})},
  "pragma"=>{let name=required!(Expected::Identifier,"Token::Ident(text, _)");Ok(DirectiveRequest::Pragma{name})},
  other=>{
   let mut meant="";for candidate in ["include","define","undef","if","ifdef","ifndef","elif","else","endif","warn","error","pragma"]{a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;if other.starts_with(candidate)&&candidate.len()>meant.len(){meant=candidate}}
   let mut message=Text::new(a)?;message.push_str("unknown directive: #",a)?;message.push_str(other,a)?;if !meant.is_empty(){message.push_str(", did you mean #",a)?;message.push_str(meant,a)?;}
   Ok(DirectiveRequest::SourceFailure{message,point:FailurePoint::LastOuter})
  },
 }
}

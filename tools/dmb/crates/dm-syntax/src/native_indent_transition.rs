//! Native logical indentation transition over SAME already-issued token facts.
//! No input reads, lexing, parser/model, source/EOF authority or hidden buffer.
//! Original0290 cadence is the pinned indents.rs real_next/next producer: blank
//! whitespace yields no units; synthetic braces/semicolon each yield one unit.
use crate::{OriginalTokenValue,SettingAdmission};use std::{fmt,io};
#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub enum NativeIndentNotice{Inconsistent{spaces:usize,unit:usize},Multiple{levels:usize},UnmatchedRightBrace}
impl NativeIndentNotice{pub fn write_message(self,out:&mut impl fmt::Write)->fmt::Result{match self{Self::Inconsistent{spaces,unit}=>write!(out,"inconsistent indentation: {spaces} % {unit} != 0"),Self::Multiple{levels}=>write!(out,"inconsistent multiple indentation: {levels} > 1"),Self::UnmatchedRightBrace=>out.write_str("unmatched right brace")}}}
#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub enum NativeIndentEmission<L>{Notice{kind:NativeIndentNotice,location:L},Punctuation{spelling:&'static str,location:L},Keep{location:L}}
struct Pending<L>{notice:Option<NativeIndentNotice>,second_notice:Option<NativeIndentNotice>,notice_location:L,first:Option<(&'static str,L)>,repeat:Option<(&'static str,usize,L)>,keep:bool,keep_location:L}
/// Scalar continuation; its physical enclosing producer funds its actual fixed
/// storage. No Vec/deque or retained borrower/admission crosses a worker step.
pub struct NativeIndentTransition<L:Clone>{current:Option<(usize,usize)>,spaces:Option<usize>,parentheses:usize,eol:Option<L>,last:L,pending:Option<Pending<L>>,ended:bool,failed:bool}
impl<L:Clone>NativeIndentTransition<L>{
 pub fn original_0290(actual_default_location:L)->Self{Self{current:None,spaces:None,parentheses:0,eol:None,last:actual_default_location,pending:None,ended:false,failed:false}}
 fn poll(&mut self,a:&SettingAdmission<'_>)->io::Result<()>{if self.failed{return Err(io::ErrorKind::InvalidInput.into())}if let Err(e)=a.checkpoint(){self.failed=true;return Err(a.take_operational_error().unwrap_or(e))}Ok(())}
 pub fn has_pending(&self)->bool{self.pending.is_some()}
 pub fn is_ended(&self)->bool{self.ended}
 /// Caller holds its SAME owned input token until Keep, then transfers it;
 /// skipped whitespace is discarded once this call returns with no pending.
 pub fn begin_using<T>(&mut self,value:&OriginalTokenValue<T>,actual_location:L,a:&SettingAdmission<'_>)->io::Result<()>{
  self.poll(a)?;if self.ended||self.pending.is_some(){self.failed=true;return Err(io::Error::new(io::ErrorKind::InvalidInput,"logical indent transition needs its real prior output drained"))}
  let result=self.begin(value,actual_location);if result.is_err(){self.failed=true}result
 }
 fn begin<T>(&mut self,value:&OriginalTokenValue<T>,location:L)->io::Result<()>{
  self.last=location.clone();let punct=match value{OriginalTokenValue::Punct(p)=>Some(*p),_=>None};
  match punct{Some("\n")=>{if self.parentheses==0{self.spaces=Some(0)}if self.eol.is_none(){self.eol=Some(location)}return Ok(())},Some(" "|"\t")=>{if let Some(spaces)=&mut self.spaces{*spaces=spaces.checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?}return Ok(())},_=>()}
  if matches!(punct,Some("{"|"}")){self.spaces=None}
  let mut pending=Pending{notice:None,second_notice:None,notice_location:location.clone(),first:None,repeat:None,keep:true,keep_location:location.clone()};
  if let Some(spaces)=self.spaces.take(){
   let(old,new)=match self.current{None=>{let new=usize::from(spaces!=0);self.current=(spaces!=0).then_some((spaces,new));(0,new)},Some((unit,old))=>{if spaces==0{self.current=None;(old,0)}else{if unit==0{return Err(io::ErrorKind::InvalidData.into())}if spaces%unit!=0{pending.notice=Some(NativeIndentNotice::Inconsistent{spaces,unit})}let new=spaces/unit;self.current=Some((unit,new));(old,new)}}};
   let origin=self.eol.clone().unwrap_or(location);
   if old<new{let levels=new-old;if levels>1{let notice=NativeIndentNotice::Multiple{levels};if pending.notice.is_some(){pending.second_notice=Some(notice)}else{pending.notice=Some(notice)}}pending.repeat=Some(("{",levels,origin));}
   else if old>new{pending.repeat=Some(("}",old-new,origin));}
   else{pending.first=Some((";",origin));}
  }
  match punct{Some("{")=>{self.current=Some(match self.current{None=>(1,1),Some((unit,n))=>(unit,n.checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?)});},Some("}")=>{self.current=match self.current{None=>{pending.notice=Some(NativeIndentNotice::UnmatchedRightBrace);None},Some((_,1))=>None,Some((unit,n))=>Some((unit,n.checked_sub(1).ok_or(io::ErrorKind::InvalidData)?))};},Some("(")=>self.parentheses=self.parentheses.checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?,Some(")")=>self.parentheses=self.parentheses.saturating_sub(1),_=>()}
  self.eol=None;self.pending=Some(pending);Ok(())
 }
 /// One real logical output or typed notice at a time. A batch boundary may
 /// pause in a long brace run without requesting another physical/macro token.
 pub fn next_using(&mut self,a:&SettingAdmission<'_>)->io::Result<Option<NativeIndentEmission<L>>>{
  self.poll(a)?;let Some(pending)=self.pending.as_mut()else{return Ok(None)};
  if let Some(kind)=pending.notice.take(){return Ok(Some(NativeIndentEmission::Notice{kind,location:pending.notice_location.clone()}))}
  if let Some(kind)=pending.second_notice.take(){return Ok(Some(NativeIndentEmission::Notice{kind,location:pending.notice_location.clone()}))}
  if let Some((spelling,location))=pending.first.take(){return Ok(Some(NativeIndentEmission::Punctuation{spelling,location}))}
  if let Some((spelling,count,location))=pending.repeat.as_mut(){if *count>0{*count-=1;return Ok(Some(NativeIndentEmission::Punctuation{spelling:*spelling,location:location.clone()}))}}
  if pending.keep{pending.keep=false;return Ok(Some(NativeIndentEmission::Keep{location:pending.keep_location.clone()}))}
  self.pending=None;Ok(None)
 }
 /// Control only. The actual source owner must call this on genuine producer
 /// End; public syntax DATA alone cannot certify any acquisition or CODE EOF.
 pub fn end_input_using(&mut self,a:&SettingAdmission<'_>)->io::Result<()>{
  self.poll(a)?;if self.ended||self.pending.is_some(){self.failed=true;return Err(io::ErrorKind::InvalidInput.into())}let levels=self.current.take().map_or(0,|(_,n)|n);self.ended=true;self.pending=Some(Pending{notice:None,second_notice:None,notice_location:self.last.clone(),first:Some((";",self.last.clone())),repeat:Some(("}",levels,self.last.clone())),keep:false,keep_location:self.last.clone()});Ok(())
 }
}

#[cfg(test)]mod immutable_types{
  use std::cell::RefCell;pub type Location=usize;#[derive(Default)]pub struct Context{pub notices:RefCell<Vec<(Location,String)>>}
  pub struct DMError{location:Location,message:String}impl DMError{pub fn new(location:Location,message:impl Into<String>)->Self{Self{location,message:message.into()}}pub fn register(self,context:&Context){context.notices.borrow_mut().push((self.location,self.message));}}
  pub mod lexer{
   #[derive(Clone,Copy,Debug,Eq,PartialEq)]pub enum Punctuation{Newline,Tab,Space,LBrace,RBrace,LParen,RParen,Semicolon}
   #[derive(Clone,Copy,Debug,Eq,PartialEq)]pub enum Token{Punct(Punctuation),Other(&'static str)}
   #[derive(Clone,Copy,Debug,Eq,PartialEq)]pub struct LocatedToken{pub location:usize,pub token:Token}impl LocatedToken{pub fn new(location:usize,token:Token)->Self{Self{location,token}}}
  }
 }

#[cfg(test)]#[path="../../../fixtures/original_indent_transition.rs"]mod immutable_original;
#[cfg(test)]mod tests{
 use super::*;use std::{cell::RefCell, sync::{Arc, atomic::{Ordering}}};
 fn old_token(text:&'static str)->immutable_types::lexer::Token{use immutable_types::lexer::{Token,Punctuation as P};match text{"\n"=>Token::Punct(P::Newline),"\t"=>Token::Punct(P::Tab)," "=>Token::Punct(P::Space),"{"=>Token::Punct(P::LBrace),"}"=>Token::Punct(P::RBrace),"("=>Token::Punct(P::LParen),")"=>Token::Punct(P::RParen),";"=>Token::Punct(P::Semicolon),_=>Token::Other(text)}}
 fn old_text(token:immutable_types::lexer::Token)->&'static str{use immutable_types::lexer::{Token,Punctuation as P};match token{Token::Other(s)=>s,Token::Punct(p)=>match p{P::Newline=>"\n",P::Tab=>"\t",P::Space=>" ",P::LBrace=>"{",P::RBrace=>"}",P::LParen=>"(",P::RParen=>")",P::Semicolon=>";"}}}
 fn value(text:&'static str)->OriginalTokenValue<&'static str>{match text{"\n"|"\t"|" "|"{"|"}"|"("|")"|";"=>OriginalTokenValue::Punct(text),_=>OriginalTokenValue::Ident{spelling:text,whitespace:false}}}
 fn drain(cursor:&mut NativeIndentTransition<usize>,actual:&'static str,a:&SettingAdmission<'_>,out:&mut Vec<(usize,&'static str)>,notices:&mut Vec<(usize,String)>){while let Some(event)=cursor.next_using(a).unwrap(){match event{NativeIndentEmission::Keep{location}=>out.push((location,actual)),NativeIndentEmission::Punctuation{spelling,location}=>out.push((location,spelling)),NativeIndentEmission::Notice{kind,location}=>{let mut message=String::new();kind.write_message(&mut message).unwrap();notices.push((location,message));}}}}
 #[test]fn same_native_indent_events_match_literal_old_entire_transition_order_and_locations(){
  let mut cases=vec![vec![],vec!["x","\n","\n"," "," "," "," ","y","\n"," "," "," "," "," "," "," "," ","z","\n","tail"],vec!["x","\n","\t","y","\n"," "," "," "," ","z"],vec!["x","\n"," "," ","y","\n"," "," "," "," "," "," "," ","z"],vec!["(","\n","\t","x",")","\n","y"],vec!["{","\n","\t","x","\n","}"],vec!["]","}"]];let mut blanks=vec!["x"];blanks.extend(std::iter::repeat("\n").take(12000));blanks.push("y");cases.push(blanks);
  for input in cases{let context=immutable_types::Context::default();let original:Vec<_>=immutable_original::IndentProcessor::new(&context,input.iter().enumerate().map(|(i,s)|immutable_types::lexer::LocatedToken::new(i+1,old_token(s)))).map(|t|(t.location,old_text(t.token))).collect();let expected_notices=context.notices.into_inner();let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let mut cursor=NativeIndentTransition::original_0290(0);let mut output=Vec::new();let mut notices=Vec::new();for(i,text)in input.iter().enumerate(){cursor.begin_using(&value(text),i+1,&a).unwrap();drain(&mut cursor,text,&a,&mut output,&mut notices);}cursor.end_input_using(&a).unwrap();drain(&mut cursor,"not kept at EOF",&a,&mut output,&mut notices);assert_eq!(output,original);assert_eq!(notices,expected_notices);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());}
 }
 #[test]fn actual_pending_indent_brace_run_can_pause_without_reading_or_losing_units_and_preserves_both_notices(){
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let mut cursor=NativeIndentTransition::original_0290(0);let mut output=Vec::new();let mut notices=Vec::new();for(i,text)in ["x","\n"," "," ","y","\n"," "," "," "," "," "," "," "].iter().enumerate(){cursor.begin_using(&value(text),i+1,&a).unwrap();drain(&mut cursor,text,&a,&mut output,&mut notices);}cursor.begin_using(&value("z"),14,&a).unwrap();assert!(matches!(cursor.next_using(&a).unwrap(),Some(NativeIndentEmission::Notice{kind:NativeIndentNotice::Inconsistent{spaces:7,unit:2},..})));assert!(matches!(cursor.next_using(&a).unwrap(),Some(NativeIndentEmission::Notice{kind:NativeIndentNotice::Multiple{levels:2},..})));assert!(matches!(cursor.next_using(&a).unwrap(),Some(NativeIndentEmission::Punctuation{spelling:"{",..})));assert!(cursor.has_pending());assert!(matches!(cursor.next_using(&a).unwrap(),Some(NativeIndentEmission::Punctuation{spelling:"{",..})));assert!(matches!(cursor.next_using(&a).unwrap(),Some(NativeIndentEmission::Keep{location:14})));assert!(cursor.next_using(&a).unwrap().is_none());
 }
 #[test]fn actual_indent_first_operational_failure_poisons_continuation_and_fresh_owner_can_recover(){
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let fault=||Err(io::Error::from_raw_os_error(1450));let a=SettingAdmission::new(&used,1<<20,&fault);let mut cursor=NativeIndentTransition::original_0290(0);assert_eq!(cursor.begin_using(&value("x"),1,&a).unwrap_err().raw_os_error(),Some(1450));assert!(cursor.next_using(&a).is_err());assert!(cursor.end_input_using(&a).is_err());let fresh=SettingAdmission::new(&used,1<<20,&||Ok(()));let mut cursor=NativeIndentTransition::original_0290(0);cursor.begin_using(&value("x"),1,&fresh).unwrap();assert!(matches!(cursor.next_using(&fresh).unwrap(),Some(NativeIndentEmission::Keep{location:1})));
 }
}

#[cfg(test)]mod owned_location_tests{
 use super::*;use std::sync::{Arc};
 #[derive(Clone)]struct Location{key:usize,owner:Arc<()>}
 #[test]fn genuine_saved_eol_location_retains_noncopy_owner_until_synthetic_delimiter_is_delivered(){
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let owner=Arc::new(());let mut indent=NativeIndentTransition::original_0290(Location{key:0,owner:Arc::new(())});let word=OriginalTokenValue::Ident{spelling:"x",whitespace:false};indent.begin_using(&word,Location{key:1,owner:Arc::new(())},&a).unwrap();while indent.next_using(&a).unwrap().is_some(){}indent.begin_using(&OriginalTokenValue::<&str>::Punct("\n"),Location{key:2,owner:owner.clone()},&a).unwrap();assert!(Arc::strong_count(&owner)>1);indent.begin_using(&word,Location{key:3,owner:Arc::new(())},&a).unwrap();let Some(NativeIndentEmission::Punctuation{spelling:";",location})=indent.next_using(&a).unwrap()else{panic!("same EOL delimiter")};assert_eq!(location.key,2);assert!(Arc::ptr_eq(&location.owner,&owner));drop(location);while indent.next_using(&a).unwrap().is_some(){}drop(indent);assert_eq!(Arc::strong_count(&owner),1);
 }
}

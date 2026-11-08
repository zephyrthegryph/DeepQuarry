//! SAME old docs-in/output/interpolation bookkeeping, with actual metadata
//! funding. No parser, source/currentness/EOF/model authorization is carried.
use super::original_output_queue::OriginalOutputQueue;
use crate::macro_expansion::{OriginalMacroRows as Rows,OriginalMacroToken as Token,OriginalMacroValue as Value,OriginalMacroOrigin as Origin,OriginalMacroText as Text,OriginalMacroDoc as Doc};
use dm_syntax::{SettingAdmission,OriginalCommentKind};use std::io;
pub(super) struct OriginalOrdinaryOutput{docs:Rows<Option<Token<'static>>>,danger:Rows<(Text,Origin)>,interpolation:u32,failed:bool}
fn poll(a:&SettingAdmission<'_>)->io::Result<()>{a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))}
fn following(kind:OriginalCommentKind)->bool{matches!(kind,OriginalCommentKind::LineFollowing|OriginalCommentKind::BlockFollowing)}
fn whitespace(value:&Value<'_>)->bool{matches!(value,Value::Punct(" "|"\t"|"\n")|Value::Eof)}
impl OriginalOrdinaryOutput{
 pub(super) fn new(a:&SettingAdmission<'_>)->io::Result<Self>{Ok(Self{docs:Rows::new(a)?,danger:Rows::new(a)?,interpolation:0,failed:false})}
 fn check(&self,a:&SettingAdmission<'_>)->io::Result<()>{if self.failed{return Err(io::ErrorKind::InvalidInput.into())}poll(a)}
 /// Actual outer source owner calls this only on its observed next printable
 /// physical line/file transition. It is not inferred from replacement text.
 pub(super) fn clear_danger_for_actual_new_line(&mut self){self.danger.truncate(0)}
 pub(super) fn flush_docs(&mut self,queue:&mut OriginalOutputQueue<'static>,a:&SettingAdmission<'_>)->io::Result<()>{
  self.check(a)?;let result=(||{for doc in self.docs.as_mut_slice(){poll(a)?;if let Some(doc)=doc.take(){queue.push(doc,a)?;}}self.docs.truncate(0);Ok(())})();if result.is_err(){self.failed=true}result
 }
 pub(super) fn before_identifier(&mut self,name:&str,origin:Origin,queue:&mut OriginalOutputQueue<'static>,a:&SettingAdmission<'_>)->io::Result<()>{
  self.check(a)?;let result=(||{self.flush_docs(queue,a)?;if self.interpolation>0{
   if let Some((_,previous))=self.danger.as_mut_slice().iter_mut().find(|(actual,_)|actual.as_str()==name){*previous=origin;}
   else{let mut text=Text::new(a)?;text.push_str(name,a)?;self.danger.push((text,origin),a)?;}
  }Ok(())})();if result.is_err(){self.failed=true}result
 }
 fn interpolation_token(&mut self,value:&Value<'_>){match value{Value::InterpBegin(_)=>self.interpolation=self.interpolation.wrapping_add(1),Value::InterpEnd(_)=>self.interpolation=self.interpolation.wrapping_sub(1),_=>()}}
 pub(super) fn direct_noncall_output(&mut self,token:&Token<'static>,a:&SettingAdmission<'_>)->io::Result<()>{self.check(a)?;self.interpolation_token(&token.value);Ok(())}
 pub(super) fn ordinary_token(&mut self,token:Token<'static>,queue:&mut OriginalOutputQueue<'static>,a:&SettingAdmission<'_>)->io::Result<()>{
  self.ordinary_using(token,queue,false,a).map(|_|())
 }
 pub(super) fn ordinary_direct_using(&mut self,token:Token<'static>,queue:&mut OriginalOutputQueue<'static>,a:&SettingAdmission<'_>)->io::Result<Option<(Token<'static>,super::original_output_trace::OriginalOutputTrace)>>{
  self.ordinary_using(token,queue,true,a)
 }
 fn ordinary_using(&mut self,token:Token<'static>,queue:&mut OriginalOutputQueue<'static>,direct:bool,a:&SettingAdmission<'_>)->io::Result<Option<(Token<'static>,super::original_output_trace::OriginalOutputTrace)>>{
  self.check(a)?;let result=(||{self.interpolation_token(&token.value);
   if matches!(&token.value,Value::DocComment{kind,..}if following(*kind)){self.docs.push(Some(token),a)?;return Ok(None)}
   if !whitespace(&token.value){self.flush_docs(queue,a)?;}
   if direct&&queue.is_empty(){return queue.direct_using(token,a).map(Some)}
   queue.push(token,a)?;Ok(None)
  })();if result.is_err(){self.failed=true}result
 }
 /// #define drains the SAME pending docs once. Actual raw-frame/value/point
 /// identities move intact, never stringify/relex or duplicate a text model.
 pub(super) fn take_docs_for_define(&mut self,a:&SettingAdmission<'_>)->io::Result<Rows<Doc<'static>>>{
  self.check(a)?;let result=(||{let mut result=Rows::new(a)?;for slot in self.docs.as_mut_slice(){poll(a)?;let token=slot.take().ok_or(io::ErrorKind::InvalidData)?;let Token{value:Value::DocComment{kind,text},origin,lexical_frame,lexical_span,..}=token else{return Err(io::ErrorKind::InvalidData.into())};result.push(Doc{kind,text,origin,lexical_frame,lexical_span},a)?;}self.docs.truncate(0);Ok(result)})();if result.is_err(){self.failed=true}result
 }
}
#[cfg(test)]mod tests{
 use super::*;use crate::macro_expansion::OriginalMacroTextValue as ValueText;use std::sync::{atomic::{Ordering}};
 fn token(value:Value<'static>)->Token<'static>{Token{string_mode:dm_syntax::OriginalStringMode::Unknown,punctuation_close:false,lexical_frame:None,lexical_span:None,raw_spelling:None,value,origin:Origin{physical:dm_syntax::Span::default(),line:1,byte_column:None,occurrence:0,invocation:false}}}
 #[test]fn actual_pending_doc_waits_across_whitespace_then_moves_once_to_define_or_actual_output(){
  let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let mut state=OriginalOrdinaryOutput::new(&a).unwrap();let mut output=OriginalOutputQueue::new(&a).unwrap();state.ordinary_token(token(Value::DocComment{kind:OriginalCommentKind::LineFollowing,text:ValueText::Borrowed("pending")}),&mut output,&a).unwrap();assert!(output.is_empty());state.ordinary_token(token(Value::Punct("\n")),&mut output,&a).unwrap();assert!(matches!(output.pop().unwrap(),Some(Token{value:Value::Punct("\n"),..})));let docs=state.take_docs_for_define(&a).unwrap();assert_eq!(docs.len(),1);assert_eq!(docs.as_slice()[0].text.get(),"pending");state.flush_docs(&mut output,&a).unwrap();assert!(output.is_empty());drop((docs,state,output));assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
 }
}

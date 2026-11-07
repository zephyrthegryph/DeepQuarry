//! #define demand joins the actual macro raw stack and unique definition judge.
//! It never calls expanded next(), so argument/replacement identifiers cannot
//! trigger lookups before a real future consumer requests them.
use crate::macro_expansion::{OriginalMacroCursor as Cursor,OriginalMacroSource as Source,OriginalMacroRawStep as RawStep,OriginalMacroToken as Token,OriginalMacroRows as Rows,OriginalMacroDoc as Doc,OriginalDefineBuilder as Builder,OriginalDefineInput as Input,OriginalDefineProgress as Progress,OriginalDefinedMacro as Defined,OriginalMacroOrigin as Origin,OriginalMacroValue as Value};
use dm_syntax::SettingAdmission;use std::io;
pub(super) enum DefineDemandProgress{NeedInput,Hint{origin:Origin,message:&'static str},Complete(Defined<'static>),SourceFailure{origin:Origin,message:&'static str}}
pub(super) struct OriginalDefineDemand{builder:Builder<'static>,finished:bool,failed:bool}
impl OriginalDefineDemand{
 pub(super) fn new(actual_name:Token<'static>,drained_docs:Rows<Doc<'static>>,a:&SettingAdmission<'_>)->io::Result<Self>{Ok(Self{builder:Builder::new(actual_name,drained_docs,a)?,finished:false,failed:false})}
 pub(super) fn advance(&mut self,cursor:&mut Cursor<'static>,source:&mut impl Source<'static>,a:&SettingAdmission<'_>)->io::Result<DefineDemandProgress>{
  if self.finished||self.failed{return Err(io::Error::new(io::ErrorKind::InvalidInput,"completed or failed define demand cannot resume"))}let result=self.advance_inner(cursor,source,a);if result.is_err(){self.failed=true}result
 }
 fn advance_inner(&mut self,cursor:&mut Cursor<'static>,source:&mut impl Source<'static>,a:&SettingAdmission<'_>)->io::Result<DefineDemandProgress>{
  loop{
   let progress=match cursor.next_undispatched_using(source,a)?{
    RawStep::NeedInput=>return Ok(DefineDemandProgress::NeedInput),
    RawStep::End=>self.builder.finish_eof(a)?,
    RawStep::Token(token)=>{let input=if matches!(token.value,Value::Punct("\n")){Input::Newline(token.origin)}else{Input::Token(token)};self.builder.push(input,a)?}
   };
   match progress{
    Progress::Continue=>continue,
    Progress::Hint{origin,message}=>return Ok(DefineDemandProgress::Hint{origin,message}),
    Progress::Complete(definition)=>{self.finished=true;return Ok(DefineDemandProgress::Complete(definition))},
    Progress::SourceFailure{origin,message}=>{self.finished=true;return Ok(DefineDemandProgress::SourceFailure{origin,message})}
   }
  }
 }
}
#[cfg(test)]mod tests{
 use super::*;use crate::macro_expansion::{OriginalMacroTextValue as Text,OriginalMacroDefinition as Definition};use std::{collections::VecDeque, sync::{atomic::{Ordering}}};
 fn token(value:Value<'static>)->Token<'static>{Token{string_mode:dm_syntax::OriginalStringMode::Unknown,punctuation_close:false,lexical_frame:None,lexical_span:None,raw_spelling:None,value,origin:Origin{physical:dm_syntax::Span::default(),line:1,byte_column:None,occurrence:0,invocation:false}}}
 fn ident(name:&'static str,whitespace:bool)->Token<'static>{token(Value::Ident{spelling:Text::Borrowed(name),whitespace})}
 struct Raw{tokens:VecDeque<Token<'static>>,reads:usize}
 impl Source<'static> for Raw{
  fn next_raw(&mut self,_:&SettingAdmission<'_>)->io::Result<RawStep<'static>>{self.reads+=1;Ok(self.tokens.pop_front().map(RawStep::Token).unwrap_or(RawStep::End))}
  fn lookup(&mut self,_:&str,_:&SettingAdmission<'_>)->io::Result<Option<Definition<'static>>>{panic!("define raw token acquisition must never expand a replacement")}
  fn include_depth(&self)->usize{1}
  fn dynamic(&mut self,_:bool,_:Origin,_:&SettingAdmission<'_>)->io::Result<Token<'static>>{panic!("raw definition must not evaluate a dynamic macro")}
  fn invocation(&mut self,_:&str,_:Origin,_:&SettingAdmission<'_>)->io::Result<()>{panic!("raw definition must not record an invocation")}
 }
 #[test]fn actual_define_cursor_stops_on_consumed_empty_parameter_delimiter_before_tail_or_macro_lookup(){
  let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let mut raw=Raw{tokens:VecDeque::from([token(Value::Punct("(")),token(Value::Punct(")")),ident("UNDEMANDED",false)]),reads:0};let mut cursor=Cursor::new(&a).unwrap();let mut demand=OriginalDefineDemand::new(ident("EMPTY",false),Rows::new(&a).unwrap(),&a).unwrap();
  assert!(matches!(demand.advance(&mut cursor,&mut raw,&a).unwrap(),DefineDemandProgress::SourceFailure{..}));assert_eq!(raw.reads,2);assert!(demand.advance(&mut cursor,&mut raw,&a).is_err());assert_eq!(raw.reads,2);assert!(matches!(cursor.next_undispatched_using(&mut raw,&a).unwrap(),RawStep::Token(Token{value:Value::Ident{spelling,..},..})if spelling.get()=="UNDEMANDED"));drop((demand,cursor,raw));assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]fn actual_define_uses_same_raw_replacement_tokens_until_real_newline_and_leaves_following_input(){
  let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let mut raw=Raw{tokens:VecDeque::from([ident("TOO_FEW",false),token(Value::Punct("(")),token(Value::Int(1)),token(Value::Punct(")")),token(Value::Punct("\n")),ident("later",false)]),reads:0};let mut cursor=Cursor::new(&a).unwrap();let mut demand=OriginalDefineDemand::new(ident("RAW",true),Rows::new(&a).unwrap(),&a).unwrap();
  let DefineDemandProgress::Complete(definition)=demand.advance(&mut cursor,&mut raw,&a).unwrap()else{panic!("actual source newline completes the definition")};assert_eq!(definition.definition.replacement.len(),4);assert_eq!(raw.reads,5);assert_eq!(raw.tokens.len(),1);drop((definition,demand,cursor,raw));assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
 }
}

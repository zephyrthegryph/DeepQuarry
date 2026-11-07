//! SAME pinned #define parameter/replacement judge over actual issued raw tokens.
//! This is parser DATA, not source/conditional/definition-environment authority.
//! Driver supplies already issued physical/replacement-stack tokens one at a time;
//! a source failure consumes precisely its offending token, never the next one.
use super::funded_storage::{MacroRows,MacroText};
use super::original_demand::Definition;
use super::original_values::{Origin,Text,Token,Value};
use dm_syntax::{OriginalCommentKind,SettingAdmission};
use std::io;

pub(crate) struct Doc<'s>{pub(crate) kind:OriginalCommentKind,pub(crate) text:Text<'s>,pub(crate) origin:Origin,pub(crate) lexical_frame:Option<crate::regions::OriginalLexicalFrameIdentity>,pub(crate) lexical_span:Option<dm_syntax::Span>}
impl Doc<'_>{pub(crate) fn duplicate(&self,a:&SettingAdmission<'_>)->io::Result<Self>{poll(a)?;Ok(Self{kind:self.kind,text:self.text.duplicate(a)?,origin:self.origin,lexical_frame:self.lexical_frame.clone(),lexical_span:self.lexical_span})}}
pub(crate) enum Input<'s>{Token(Token<'s>),Doc(Doc<'s>),Newline(Origin)}
pub(crate) struct Defined<'s>{pub(crate) name:Token<'s>,pub(crate) definition:Definition<'s>,pub(crate) docs:MacroRows<Doc<'s>>}
pub(crate) enum Progress<'s>{Continue,Hint{origin:Origin,message:&'static str},Complete(Defined<'s>),SourceFailure{origin:Origin,message:&'static str}}
#[derive(Clone,Copy)]enum State{AfterName,ParameterName,ParameterDelimiter,VariadicClose,Replacement,Finished,Failed}
pub(crate) struct Builder<'s>{name:Option<Token<'s>>,parameters:Option<MacroRows<MacroText>>,variadic:bool,replacement:Option<MacroRows<Token<'s>>>,docs:Option<MacroRows<Doc<'s>>>,state:State,last:Origin,failed:bool}
fn poll(a:&SettingAdmission<'_>)->io::Result<()>{a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))}
fn punct(t:&Token<'_>,p:&str)->bool{matches!(&t.value,Value::Punct(actual)if *actual==p)}
fn input_origin(input:&Input<'_>)->Origin{match input{Input::Token(t)=>t.origin,Input::Doc(d)=>d.origin,Input::Newline(o)=>*o}}
impl<'s>Builder<'s>{
 /// The actual directive owner has just performed pinned expect_token Ident
 /// (including its exact Debug diagnostic on failure). Drain docs_in here once.
 pub(crate) fn new(name:Token<'s>,docs:MacroRows<Doc<'s>>,a:&SettingAdmission<'_>)->io::Result<Self>{
  poll(a)?;if !matches!(name.value,Value::Ident{..}){return Err(io::Error::new(io::ErrorKind::InvalidInput,"define builder requires the actual expected Ident token"))}
  let last=name.origin;Ok(Self{name:Some(name),parameters:Some(MacroRows::new(a)?),variadic:false,replacement:Some(MacroRows::new(a)?),docs:Some(docs),state:State::AfterName,last,failed:false})
 }
 pub(crate) fn push(&mut self,input:Input<'s>,a:&SettingAdmission<'_>)->io::Result<Progress<'s>>{
  if self.failed||matches!(self.state,State::Failed|State::Finished){return Err(io::Error::new(io::ErrorKind::InvalidInput,"define builder is no longer accepting raw tokens"))}
  let result=self.push_inner(input,a);if result.is_err(){self.failed=true;}result
 }
 fn failure(&mut self,message:&'static str)->Progress<'s>{self.state=State::Failed;Progress::SourceFailure{origin:self.last,message}}
 fn complete(&mut self)->io::Result<Progress<'s>>{
  let params=self.parameters.take().ok_or(io::ErrorKind::InvalidData)?;
  // Pinned Define::Constant iff params.is_empty(), not by seeing '(' alone.
  let parameters=if params.len()==0{None}else{Some(params)};
  self.state=State::Finished;Ok(Progress::Complete(Defined{name:self.name.take().ok_or(io::ErrorKind::InvalidData)?,definition:Definition{parameters,variadic:self.variadic,replacement:self.replacement.take().ok_or(io::ErrorKind::InvalidData)?},docs:self.docs.take().ok_or(io::ErrorKind::InvalidData)?}))
 }
 fn parameter(&mut self,text:&str,a:&SettingAdmission<'_>)->io::Result<()>{let mut owned=MacroText::new(a)?;owned.push_str(text,a)?;self.parameters.as_mut().ok_or(io::ErrorKind::InvalidData)?.push_definition_row(owned,a)}
 fn replacement(&mut self,input:Input<'s>,a:&SettingAdmission<'_>)->io::Result<Progress<'s>>{match input{
  Input::Newline(_)=>self.complete(),
  Input::Token(Token{value:Value::DocComment{kind,text},origin,lexical_frame,lexical_span,..})=>self.replacement(Input::Doc(Doc{kind,text,origin,lexical_frame,lexical_span}),a),
  Input::Token(token)=>{self.replacement.as_mut().ok_or(io::ErrorKind::InvalidData)?.push_definition_row(token,a)?;Ok(Progress::Continue)},
  Input::Doc(doc)=>{
   // Lexical None is not a DocComment token; do not invent an empty document.
   if matches!(doc.kind,OriginalCommentKind::None){return Err(io::Error::new(io::ErrorKind::InvalidInput,"non-doc lexical comment entered #define DocComment stream"))}
   let hint=match doc.kind{OriginalCommentKind::BlockFollowing=>Some("after a #define, should be `/*!` instead of `/**`"),OriginalCommentKind::LineFollowing=>Some("after a #define, should be `//!` instead of `///`"),_=>None};let origin=doc.origin;
   self.docs.as_mut().ok_or(io::ErrorKind::InvalidData)?.push(doc,a)?;
   Ok(match hint{Some(message)=>Progress::Hint{origin,message},None=>Progress::Continue})
  }
 }}
 fn push_inner(&mut self,input:Input<'s>,a:&SettingAdmission<'_>)->io::Result<Progress<'s>>{
  poll(a)?;self.last=input_origin(&input);match self.state{
   State::AfterName=>{
    let adjacent=matches!(&self.name.as_ref().ok_or(io::ErrorKind::InvalidData)?.value,Value::Ident{whitespace:false,..});
    if adjacent&&matches!(&input,Input::Token(token)if punct(token,"(")){self.state=State::ParameterName;return Ok(Progress::Continue)}
    self.state=State::Replacement;self.replacement(input,a)
   },
   State::ParameterName=>{
    // Variadic comma is refused by ParameterDelimiter immediately, before
    // another raw token is requested, matching the pinned loop-head check.
    if self.variadic{return Err(io::Error::new(io::ErrorKind::InvalidInput,"driver demanded a token after completed variadic parameter comma"))}
    match input{Input::Token(token)=>match token.value{Value::Ident{spelling,..}=>self.parameter(spelling.get(),a)?,Value::Punct("...")=>{self.parameter("__VA_ARGS__",a)?;self.variadic=true},_=>return Ok(self.failure("malformed macro parameters, expected name"))},_=>return Ok(self.failure("malformed macro parameters, expected name"))};self.state=State::ParameterDelimiter;Ok(Progress::Continue)
   },
   State::ParameterDelimiter=>{
    match input{Input::Token(token)if punct(&token,",")=>{if self.variadic{return Ok(self.failure("only the last parameter of a macro may be variadic"))}self.state=State::ParameterName;},Input::Token(token)if punct(&token,")")=>self.state=State::Replacement,Input::Token(token)if punct(&token,"...")=>{self.variadic=true;self.state=State::VariadicClose;},_=>return Ok(self.failure("malformed macro parameters, expected comma"))}Ok(Progress::Continue)
   },
   State::VariadicClose=>{if matches!(&input,Input::Token(token)if punct(token,")")){self.state=State::Replacement;Ok(Progress::Continue)}else{Ok(self.failure("only the last parameter of a macro may be variadic"))}},
   State::Replacement=>self.replacement(input,a),State::Failed|State::Finished=>Err(io::ErrorKind::InvalidInput.into()),
  }
 }
 /// True physical/replacement-stack exhaustion only. NeedInput is not EOF.
 /// The owner uses the actual directive last_input_loc diagnostic binding.
 pub(crate) fn finish_eof(&mut self,a:&SettingAdmission<'_>)->io::Result<Progress<'s>>{if self.failed||matches!(self.state,State::Failed|State::Finished){return Err(io::ErrorKind::InvalidInput.into())}if let Err(error)=poll(a){self.failed=true;return Err(error)}Ok(self.failure("unexpected EOF"))}
}

#[cfg(test)]mod tests{
 use super::*;use std::sync::{atomic::{Ordering}};
 fn origin(at:usize)->Origin{Origin{physical:dm_syntax::Span::new(at,at+1),line:2,byte_column:None,occurrence:9,invocation:false}}
 fn token(value:Value<'static>,at:usize)->Token<'static>{Token{string_mode:dm_syntax::OriginalStringMode::Unknown,punctuation_close:false,lexical_frame:None,lexical_span:None,value,raw_spelling:None,origin:origin(at)}}
 fn id(s:&'static str,ws:bool,at:usize)->Token<'static>{token(Value::Ident{spelling:Text::Borrowed(s),whitespace:ws},at)}
 fn p(s:&'static str,at:usize)->Input<'static>{Input::Token(token(Value::Punct(s),at))}
 fn builder(a:&SettingAdmission<'_>,ws:bool)->Builder<'static>{Builder::new(id("ACTUAL",ws,0),MacroRows::new(a).unwrap(),a).unwrap()}
 #[test]
 fn actual_small_macro_body_publishes_under_one_token_of_credit() {
  let used = dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
  let bytes = std::mem::size_of::<Token<'static>>();
  let a = SettingAdmission::new(&used, dm_syntax::SettingChargeCounter::root_allocation_bytes() + (bytes), &|| Ok(()));
  let mut b = builder(&a, true);
  let replacement = token(Value::Int(42), 1);
  let span = replacement.origin.physical;
  assert!(matches!(b.push(Input::Token(replacement), &a).unwrap(), Progress::Continue));
  let Progress::Complete(done) = b.push(Input::Newline(origin(2)), &a).unwrap() else {
   panic!("actual one-token definition");
  };
  assert_eq!(done.definition.replacement.capacity(), 1);
  assert_eq!(done.definition.replacement.as_slice()[0].origin.physical, span);
  assert!(matches!(done.definition.replacement.as_slice()[0].value, Value::Int(42)));
  assert_eq!(used.load(Ordering::Acquire), dm_syntax::SettingChargeCounter::root_allocation_bytes() + (bytes));
  drop((b, done));
  assert_eq!(used.load(Ordering::Acquire), dm_syntax::SettingChargeCounter::root_allocation_bytes());
 }

 #[test]fn empty_function_parameters_stop_exactly_at_close_without_eating_following_replacement(){let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let mut b=builder(&a,false);assert!(matches!(b.push(p("(",1),&a).unwrap(),Progress::Continue));assert!(matches!(b.push(p(")",2),&a).unwrap(),Progress::SourceFailure{origin,message:"malformed macro parameters, expected name"}if origin.physical.start==2));assert!(b.push(Input::Token(token(Value::Int(1),3)),&a).is_err());drop(b);assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());}
 #[test]fn actual_name_whitespace_distinguishes_constant_parenthesis_and_raw_replacement_is_never_expanded(){let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let mut b=builder(&a,true);for t in [p("(",1),Input::Token(id("TOO_FEW",false,2)),p(")",3)]{assert!(matches!(b.push(t,&a).unwrap(),Progress::Continue));}let Progress::Complete(done)=b.push(Input::Newline(origin(4)),&a).unwrap()else{panic!("actual constant")};assert!(done.definition.parameters.is_none());assert_eq!(done.definition.replacement.len(),3);assert!(matches!(&done.definition.replacement.as_slice()[1].value,Value::Ident{spelling,..}if spelling.get()=="TOO_FEW"));drop((done,b));assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());}
 #[test]fn named_and_anonymous_variadic_chronology_preserves_first_failure_and_next_token_frontier(){let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,1<<20,&||Ok(()));for anonymous in [false,true]{let mut b=builder(&a,false);b.push(p("(",1),&a).unwrap();if anonymous{b.push(p("...",2),&a).unwrap();}else{b.push(Input::Token(id("args",false,2)),&a).unwrap();b.push(p("...",3),&a).unwrap();}b.push(p(")",4),&a).unwrap();let Progress::Complete(done)=b.push(Input::Newline(origin(5)),&a).unwrap()else{panic!("actual variadic")};assert!(done.definition.variadic);assert_eq!(done.definition.parameters.as_ref().unwrap().as_slice()[0].as_str(),if anonymous{"__VA_ARGS__"}else{"args"});}let mut b=builder(&a,false);b.push(p("(",1),&a).unwrap();b.push(p("...",2),&a).unwrap();assert!(matches!(b.push(p(",",3),&a).unwrap(),Progress::SourceFailure{message:"only the last parameter of a macro may be variadic",..}));drop(b);assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());}
 #[test]fn actual_doc_hints_keep_order_text_and_origin_in_same_definition_output(){let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let mut prior=MacroRows::new(&a).unwrap();prior.push(Doc{kind:OriginalCommentKind::LineFollowing,text:Text::Borrowed("before"),origin:origin(1),lexical_frame:None,lexical_span:None},&a).unwrap();let mut b=Builder::new(id("A",true,0),prior,&a).unwrap();for(kind,at,message)in[(OriginalCommentKind::LineFollowing,2,"after a #define, should be `//!` instead of `///`"),(OriginalCommentKind::BlockFollowing,3,"after a #define, should be `/*!` instead of `/**`")]{assert!(matches!(b.push(Input::Doc(Doc{kind,text:Text::Borrowed("actual"),origin:origin(at),lexical_frame:None,lexical_span:None}),&a).unwrap(),Progress::Hint{origin:actual,message:m}if actual.physical.start==at&&m==message));}let Progress::Complete(done)=b.push(Input::Newline(origin(4)),&a).unwrap()else{panic!("actual docs")};assert_eq!(done.docs.len(),3);assert_eq!(done.docs.as_slice()[0].text.get(),"before");assert_eq!(done.docs.as_slice()[2].origin.occurrence,9);drop((b,done));assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());}
 #[test]fn first_typed_io_poison_never_turns_into_source_error_and_new_builder_recovers(){let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let good=SettingAdmission::new(&used,1<<20,&||Ok(()));let mut b=builder(&good,false);b.push(p("(",1),&good).unwrap();let fail=||Err(io::Error::from_raw_os_error(1450));let bad=SettingAdmission::new(&used,1<<20,&fail);assert_eq!(b.push(Input::Token(id("x",false,2)),&bad).err().unwrap().raw_os_error(),Some(1450));assert_eq!(b.push(p(")",3),&good).err().unwrap().kind(),io::ErrorKind::InvalidInput);drop(b);let mut fresh=builder(&good,true);assert!(matches!(fresh.push(Input::Newline(origin(1)),&good).unwrap(),Progress::Complete(_)));drop(fresh);assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());}
 #[test]fn actual_doc_tokens_from_raw_replacement_stack_are_collected_not_inserted_as_substitution_text(){let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let mut b=builder(&a,true);let doc=token(Value::DocComment{kind:OriginalCommentKind::LineEnclosing,text:Text::Borrowed("actual expansion doc")},2);assert!(matches!(b.push(Input::Token(doc),&a).unwrap(),Progress::Continue));let Progress::Complete(done)=b.push(Input::Newline(origin(3)),&a).unwrap()else{panic!("actual result")};assert_eq!(done.docs.as_slice()[0].text.get(),"actual expansion doc");assert_eq!(done.definition.replacement.len(),0);drop((done,b));assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());}
}

//! Exact Original final-token demand state. This is transient native parser
//! DATA only. The actual DirectivePass owns input/definition issuance and EOF.
//! No eager environment prepass, argument expansion, replacement-string rescanner,
//! second parser/cache, or source/model receipt is created here.
use super::funded_storage::{MacroRows,MacroRowsCursor,MacroText};
use super::original_values::{Factory,Origin,Text,Token,Value};
use super::original_substitution::{arguments_using,substitute_using,SubstitutionFailure};
use dm_syntax::SettingAdmission;
use std::io;

pub(crate) struct Definition<'s>{pub(crate) parameters:Option<MacroRows<MacroText>>,pub(crate) variadic:bool,pub(crate) replacement:MacroRows<Token<'s>>}
pub(crate) enum RawStep<'s>{Token(Token<'s>),NeedInput,End}
/// Must be implemented by the SAME actual source/definition owner. A definition
/// is cloned at lookup BEFORE argument demand, as pinned defines.get().cloned().
/// Actual definition-time lexical products must live on the SAME current
/// MacroDefinition/environment entry, not a parallel dictionary or String rescan.
/// Actual input frames retain SAME RecordingInputs acquisition/decoder leases;
/// ordinary Native PreparedSource cache is never an Original source fallback.
/// Returned token values/spacing come from native Original lexical transport;
/// arbitrary SpanToken/whole String relabelling does not meet this contract.
pub(crate) trait Source<'s>{
 /// The SAME actual file push records the current expansion depth. Its file
 /// precedes old frames at/below that floor; newer replacements precede it.
 fn physical_input_precedes(&self,_expansion_depth:usize)->bool{false}
 /// Actual EOF pop yields a control pause, so input rechecks interleaved stack
 /// order BEFORE it could read the parent file. This never certifies EOF.
 fn take_physical_stack_change(&mut self)->bool{false}

 /// Exact real_next Ident entry: SAME owner flushes pending docs and records
 /// interpolation danger identifiers before dynamic/defined/ordinary lookup.
 /// Raw argument tokens and direct noncall bypass tokens do not call this hook.
 fn before_identifier(&mut self,_name:&str,_origin:Origin,_a:&SettingAdmission<'_>)->io::Result<()>{Ok(())}
 /// Noncall second token bypasses real_next; ONLY actual interpolation depth
 /// is updated by the old branch before it directly pushes that token.
 fn direct_noncall_output(&mut self,_token:&Token<'s>,_a:&SettingAdmission<'_>)->io::Result<()>{Ok(())}
 fn next_raw(&mut self,a:&SettingAdmission<'_>)->io::Result<RawStep<'s>>;
 fn lookup(&mut self,name:&str,a:&SettingAdmission<'_>)->io::Result<Option<Definition<'s>>>;
 /// SAME actual owner reports its undrained output queue shape only. Normal
 /// body iteration drains each output and therefore returns false; conditional
 /// evaluation buffers output. This is not inferred token history in Cursor.
 fn preserves_defined_operand(&self)->bool{false}
 fn include_depth(&self)->usize;
 fn dynamic(&mut self,file:bool,origin:Origin,a:&SettingAdmission<'_>)->io::Result<Token<'s>>;
 fn invocation(&mut self,name:&str,origin:Origin,a:&SettingAdmission<'_>)->io::Result<()>;
 /// Actual replacement frame publication/retirement on this SAME cursor.
 /// Callbacks carry DATA only and may not advance a source/parser frontier.
 fn expansion_pushed(&mut self,_name:&str,_origin:Origin,_depth:usize,_a:&SettingAdmission<'_>)->io::Result<()>{Ok(())}
 fn expansion_popped(&mut self,_depth:usize,_a:&SettingAdmission<'_>)->io::Result<()>{Ok(())}

}
pub(crate) enum NoticeKind{WrongArity,UnexpectedEof,DepthLimit(MacroText),StringifyNonArgument(MacroText),StringifyNonIdent(MacroText),StringifyEof}
pub(crate) struct Notice{pub(crate) origin:Origin,pub(crate) kind:NoticeKind}
pub(crate) enum Step<'s>{Token(Token<'s>),Notice(Notice),NeedInput,End,Stopped,Boundary}
pub(crate) enum OuterStep<'s>{Output(Step<'s>),Boundary}
struct Frame<'s>{tokens:MacroRowsCursor<Token<'s>>,origin:Origin}
struct Call<'s>{name:Token<'s>,definition:Definition<'s>,arguments:MacroRows<MacroRows<Token<'s>>>,current:MacroRows<Token<'s>>,parens:usize}
enum State<'s>{Ready,Open{token:Token<'s>,definition:Definition<'s>},Arguments(Call<'s>)}
pub(crate) struct Cursor<'s>{frames:MacroRows<Frame<'s>>,pending:MacroRows<Token<'s>>,state:State<'s>,stopped:bool,failed:bool,outer_active:bool,outer_seed:Option<Token<'s>>}
fn poll(a:&SettingAdmission<'_>)->io::Result<()>{a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))}
fn is_punct(token:&Token<'_>,value:&str)->bool{matches!(&token.value,Value::Punct(p)if *p==value)}
fn name<'a>(token:&'a Token<'_>)->Option<&'a str>{match &token.value{Value::Ident{spelling,..}=>Some(spelling.get()),_=>None}}
fn owned(text:&str,a:&SettingAdmission<'_>)->io::Result<MacroText>{let mut out=MacroText::new(a)?;out.push_str(text,a)?;Ok(out)}
impl<'s>Cursor<'s>{
 pub(crate) fn new(a:&SettingAdmission<'_>)->io::Result<Self>{Ok(Self{frames:MacroRows::new(a)?,pending:MacroRows::new(a)?,state:State::Ready,stopped:false,failed:false,outer_active:false,outer_seed:None})}
 /// A real primary consumer stops by declining further demand. This state is
 /// permanent and DISTINCT from actual EOF; no future source/macro call occurs.
 pub(crate) fn stop(&mut self){self.stopped=true;}
 fn input(&mut self,source:&mut impl Source<'s>,a:&SettingAdmission<'_>)->io::Result<RawStep<'s>>{loop{poll(a)?;
  if !source.physical_input_precedes(self.frames.len()){if let Some(frame)=self.frames.last_mut(){if let Some(token)=frame.tokens.next(){return Ok(RawStep::Token(token))}self.frames.pop();source.expansion_popped(self.frames.len(),a)?;continue}}
  let read=source.next_raw(a)?;if source.take_physical_stack_change(){if !matches!(read,RawStep::NeedInput){return Err(io::Error::new(io::ErrorKind::InvalidInput,"physical stack changed without its actual control pause"))}continue}return Ok(read)
 }}
 pub(crate) fn expansion_depth(&self)->usize{self.frames.len()}
 pub(crate) fn current_expansion_origin(&self,source:&impl Source<'s>)->Option<Origin>{if source.physical_input_precedes(self.frames.len()){None}else{self.frames.as_slice().last().map(|frame|frame.origin)}}
 fn push(&mut self,tokens:MacroRows<Token<'s>>,origin:Origin,name:&str,source:&mut impl Source<'s>,a:&SettingAdmission<'_>)->io::Result<()>{self.frames.ensure(1,a)?;let depth=self.frames.len().checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?;source.expansion_pushed(name,origin,depth,a)?;self.frames.push(Frame{tokens:tokens.into_cursor(),origin},a)}
 /// Any typed failure permanently poisons this transient cursor. A partially
 /// consumed raw argument/state may never be retried as a different stream.
 pub(crate) fn next(&mut self,source:&mut impl Source<'s>,a:&SettingAdmission<'_>)->io::Result<Step<'s>>{
  if self.failed{return Err(io::Error::new(io::ErrorKind::InvalidInput,"original macro cursor is poisoned after an operational failure"))}
  if self.outer_active{return Err(io::Error::new(io::ErrorKind::InvalidInput,"whole macro iteration cannot interrupt an actual outer operation"))}
  let result=self.next_inner(source,a);if result.is_err(){self.failed=true;}result
 }
 /// One actual outer inner_next token is processed exactly once. It is not
 /// a fake expansion frame and therefore contributes no recursion depth.
 pub(crate) fn begin_outer_using(&mut self,token:Token<'s>,a:&SettingAdmission<'_>)->io::Result<()>{
  if self.failed||self.stopped||self.outer_active||!matches!(self.state,State::Ready)||self.pending.len()!=0{return Err(io::Error::new(io::ErrorKind::InvalidInput,"outer operation is not at the actual raw boundary"))}poll(a)?;self.outer_seed=Some(token);self.outer_active=true;Ok(())
 }
 /// Match one old real_next call: raw args may be demanded, direct output is
 /// drained, but newly pushed replacement frames are NOT interpreted here.
 /// They remain for the next OUTER raw read (whose newline test runs first).
 pub(crate) fn next_outer_using(&mut self,source:&mut impl Source<'s>,a:&SettingAdmission<'_>)->io::Result<OuterStep<'s>>{
  if self.failed||!self.outer_active{return Err(io::Error::new(io::ErrorKind::InvalidInput,"outer macro operation is failed or absent"))}
  let result=self.next_inner(source,a);if result.is_err(){self.failed=true}
  match result?{Step::Boundary=>Ok(OuterStep::Boundary),output=>Ok(OuterStep::Output(output))}
 }
 /// Actual directive owner only: pinned inner_next sees raw replacement frames
 /// as well as physical frames. No macro lookup/directive dispatch occurs here.
 /// Only Ready with no queued direct output is a valid directive boundary.
 pub(crate) fn next_undispatched_using(&mut self,source:&mut impl Source<'s>,a:&SettingAdmission<'_>)->io::Result<RawStep<'s>>{
  if self.failed{return Err(io::Error::new(io::ErrorKind::InvalidInput,"original macro cursor is poisoned after an operational failure"))}
  if self.stopped{return Err(io::Error::new(io::ErrorKind::InvalidInput,"original macro cursor was stopped before raw directive demand"))}
  if self.outer_active||!matches!(self.state,State::Ready)||self.pending.len()!=0{return Err(io::Error::new(io::ErrorKind::InvalidInput,"raw directive demand is not at an actual macro boundary"))}
  let result=self.input(source,a);if result.is_err(){self.failed=true;}result
 }
 fn next_inner(&mut self,source:&mut impl Source<'s>,a:&SettingAdmission<'_>)->io::Result<Step<'s>>{
  if self.stopped{return Ok(Step::Stopped)}let _stack=a.evaluation_frame()?;
  // At most two queued direct-output tokens, in pinned push_output order.
  if let Some(token)=self.pending.pop(){return Ok(Step::Token(token))}
  loop{poll(a)?;let state=std::mem::replace(&mut self.state,State::Ready);match state{
   State::Ready=>{
    if self.outer_active&&self.outer_seed.is_none(){self.outer_active=false;return Ok(Step::Boundary)}
    let token=match self.outer_seed.take(){Some(token)=>token,None=>match self.input(source,a)?{RawStep::Token(t)=>t,RawStep::NeedInput=>return Ok(Step::NeedInput),RawStep::End=>return Ok(Step::End)}};
    let Some(spelling)=name(&token)else{return Ok(Step::Token(token))};
    source.before_identifier(spelling,token.origin,a)?;
    // Pinned dynamic tokens precede ANY ordinary definition lookup.
    if spelling=="__FILE__"||spelling=="__LINE__"{return Ok(Step::Token(source.dynamic(spelling=="__FILE__",Origin{invocation:true,..token.origin},a)?))}
    if source.preserves_defined_operand(){return Ok(Step::Token(token))}
    let Some(mut definition)=source.lookup(spelling,a)?else{return Ok(Step::Token(token))};
    let depth=source.include_depth().checked_add(self.frames.len()).ok_or(io::ErrorKind::OutOfMemory)?;
    if depth>32{let notice=Notice{origin:token.origin,kind:NoticeKind::DepthLimit(owned(spelling,a)?)};self.pending.push(token,a)?;return Ok(Step::Notice(notice))}
    if definition.parameters.is_some(){self.state=State::Open{token,definition};continue}
    source.invocation(spelling,token.origin,a)?;for output in definition.replacement.as_mut_slice(){poll(a)?;output.origin=Origin{invocation:true,..token.origin};}self.push(definition.replacement,Origin{invocation:true,..token.origin},spelling,source,a)?;
   },
   State::Open{mut token,definition}=>{
    match self.input(source,a)?{
     RawStep::NeedInput=>{self.state=State::Open{token,definition};return Ok(Step::NeedInput)},
     RawStep::End=>return Ok(Step::Notice(Notice{origin:token.origin,kind:NoticeKind::UnexpectedEof})),
     RawStep::Token(next)=>{
      if !is_punct(&next,"("){if let Value::Ident{whitespace,..}=&mut token.value{*whitespace=false;}source.direct_noncall_output(&next,a)?;self.pending.push(next,a)?;return Ok(Step::Token(token))}
      source.invocation(name(&token).ok_or(io::ErrorKind::InvalidData)?,token.origin,a)?;
      self.state=State::Arguments(Call{name:token,definition,arguments:MacroRows::new(a)?,current:MacroRows::new(a)?,parens:0});
     }
    }
   },
   State::Arguments(mut call)=>{
    let token=match self.input(source,a)?{RawStep::NeedInput=>{self.state=State::Arguments(call);return Ok(Step::NeedInput)},RawStep::End=>return Ok(Step::Notice(Notice{origin:call.name.origin,kind:NoticeKind::UnexpectedEof})),RawStep::Token(t)=>t};
    if is_punct(&token,"("){call.parens=call.parens.checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?;call.current.push(token,a)?;self.state=State::Arguments(call);continue}
    if is_punct(&token,")")&&call.parens==0{
     call.arguments.push(call.current,a)?;let params=call.definition.parameters.as_ref().ok_or(io::ErrorKind::InvalidData)?;
     let mut factory=Factory{invocation:Origin{invocation:true,..call.name.origin},source:std::marker::PhantomData};
     let normalized=match arguments_using(params.as_slice(),call.arguments.as_slice(),call.definition.variadic,&mut factory,a)?{Ok(args)=>args,Err(())=>return Ok(Step::Notice(Notice{origin:call.name.origin,kind:NoticeKind::WrongArity}))};
     let expanded=match substitute_using(params.as_slice(),normalized.as_slice(),call.definition.replacement.as_slice(),&mut factory,a)?{Ok(tokens)=>tokens,Err(error)=>{let kind=match error{SubstitutionFailure::Eof=>NoticeKind::StringifyEof,SubstitutionFailure::NonArgument(n)=>NoticeKind::StringifyNonArgument(owned(n,a)?),SubstitutionFailure::NonIdent(token)=>{let mut text=MacroText::new(a)?;token.write_display(&mut text,a)?;NoticeKind::StringifyNonIdent(text)}};return Ok(Step::Notice(Notice{origin:call.name.origin,kind}))}};
     self.push(expanded,Origin{invocation:true,..call.name.origin},name(&call.name).ok_or(io::ErrorKind::InvalidData)?,source,a)?;continue
    }
    if is_punct(&token,")"){call.parens-=1;}
    if is_punct(&token,",")&&call.parens==0{call.arguments.push(call.current,a)?;call.current=MacroRows::new(a)?;}else{call.current.push(token,a)?;}
    self.state=State::Arguments(call);
   }
  }}
 }
}

#[cfg(test)]mod tests{
 use super::*;use std::collections::VecDeque;use std::sync::{Arc,atomic::{AtomicUsize,Ordering}};
 fn at()->Origin{Origin{physical:dm_syntax::Span::new(0,1),line:3,byte_column:None,occurrence:0,invocation:false}}
 fn id(s:&'static str)->Token<'static>{Token{string_mode:dm_syntax::OriginalStringMode::Unknown,punctuation_close:false,lexical_frame:None,lexical_span:None,value:Value::Ident{spelling:Text::Borrowed(s),whitespace:false},raw_spelling:Some(Text::Borrowed(s)),origin:at()}}
 fn punct(p:&'static str)->Token<'static>{Token{string_mode:dm_syntax::OriginalStringMode::Unknown,punctuation_close:false,lexical_frame:None,lexical_span:None,value:Value::Punct(p),raw_spelling:Some(Text::Borrowed(p)),origin:at()}}
 fn number()->Token<'static>{Token{string_mode:dm_syntax::OriginalStringMode::Unknown,punctuation_close:false,lexical_frame:None,lexical_span:None,value:Value::Int(1),raw_spelling:Some(Text::Borrowed("1")),origin:at()}}
 fn rows(tokens:impl IntoIterator<Item=Token<'static>>,a:&SettingAdmission<'_>)->MacroRows<Token<'static>>{let mut out=MacroRows::new(a).unwrap();for t in tokens{out.push(t,a).unwrap();}out}
 struct Input{raw:VecDeque<RawStep<'static>>,lookups:Vec<String>,invocations:usize}
 impl Source<'static> for Input{
  fn next_raw(&mut self,a:&SettingAdmission<'_>)->io::Result<RawStep<'static>>{poll(a)?;Ok(self.raw.pop_front().unwrap_or(RawStep::End))}
  fn lookup(&mut self,n:&str,a:&SettingAdmission<'_>)->io::Result<Option<Definition<'static>>>{poll(a)?;self.lookups.push(n.into());if n=="OBJECT"{return Ok(Some(Definition{parameters:None,variadic:false,replacement:rows([Token{string_mode:dm_syntax::OriginalStringMode::Unknown,punctuation_close:false,lexical_frame:None,lexical_span:None,value:Value::Int(1),raw_spelling:Some(Text::Borrowed("1")),origin:Origin{physical:dm_syntax::Span::new(900,901),line:77,byte_column:None,occurrence:0,invocation:false}}],a)}))}let(parameters,replacement)=match n{"MAKE"=>(vec!["x"],vec![punct(","),id("x")]),"TOO_FEW"=>(vec!["a","b"],vec![id("a")]),"FN"=>(vec!["x"],vec![id("x")]),"F"=>(vec!["x"],vec![id("F"),punct("("),id("x"),punct(")")]),_=>return Ok(None)};let mut names=MacroRows::new(a)?;for name in parameters{names.push(owned(name,a)?,a)?;}Ok(Some(Definition{parameters:Some(names),variadic:false,replacement:rows(replacement,a)}))}
  fn include_depth(&self)->usize{1}
  fn dynamic(&mut self,_:bool,origin:Origin,a:&SettingAdmission<'_>)->io::Result<Token<'static>>{poll(a)?;Ok(Token{string_mode:dm_syntax::OriginalStringMode::Unknown,punctuation_close:false,lexical_frame:None,lexical_span:None,value:Value::Int(origin.line as i32),raw_spelling:None,origin})}
  fn invocation(&mut self,_:&str,_:Origin,a:&SettingAdmission<'_>)->io::Result<()>{poll(a)?;self.invocations+=1;Ok(())}
 }
 fn input(tokens:impl IntoIterator<Item=Token<'static>>)->Input{Input{raw:tokens.into_iter().map(RawStep::Token).collect(),lookups:Vec::new(),invocations:0}}
 #[test]fn actual_raw_substitution_yields_fatal_comma_before_future_argument_macro_lookup_and_stop_is_permanent(){let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let mut source=input([id("MAKE"),punct("("),id("TOO_FEW"),punct("("),number(),punct(")"),punct(")")]);let mut cursor=Cursor::new(&a).unwrap();assert!(matches!(cursor.next(&mut source,&a).unwrap(),Step::Token(t)if is_punct(&t,",")));assert_eq!(source.lookups,["MAKE"]);cursor.stop();for _ in 0..3{assert!(matches!(cursor.next(&mut source,&a).unwrap(),Step::Stopped));}assert_eq!(source.lookups,["MAKE"]);drop(cursor);assert_eq!(used.load(Ordering::Acquire),0);}
 #[test]fn without_primary_stop_the_same_later_raw_argument_lookup_and_real_arity_notice_are_demanded(){let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let mut source=input([id("MAKE"),punct("("),id("TOO_FEW"),punct("("),number(),punct(")"),punct(")")]);let mut cursor=Cursor::new(&a).unwrap();assert!(matches!(cursor.next(&mut source,&a).unwrap(),Step::Token(t)if is_punct(&t,",")));assert!(matches!(cursor.next(&mut source,&a).unwrap(),Step::Notice(Notice{kind:NoticeKind::WrongArity,..})));assert_eq!(source.lookups,["MAKE","TOO_FEW"]);assert!(matches!(cursor.next(&mut source,&a).unwrap(),Step::End));drop(cursor);assert_eq!(used.load(Ordering::Acquire),0);}
 #[test]fn exact_pinned_noncall_consumes_and_directly_outputs_next_identifier_without_its_lookup(){let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let mut source=input([id("FN"),id("TOO_FEW"),punct("("),number(),punct(")")]);let mut cursor=Cursor::new(&a).unwrap();assert!(matches!(cursor.next(&mut source,&a).unwrap(),Step::Token(t)if name(&t)==Some("FN")));assert!(matches!(cursor.next(&mut source,&a).unwrap(),Step::Token(t)if name(&t)==Some("TOO_FEW")));assert_eq!(source.lookups,["FN"]);drop(cursor);assert_eq!(used.load(Ordering::Acquire),0);}
 #[test]fn pending_actual_raw_input_keeps_same_definition_and_argument_frame_without_relookup_or_fake_eof(){let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let mut source=input([]);source.raw=VecDeque::from([RawStep::Token(id("FN")),RawStep::NeedInput,RawStep::Token(punct("(")),RawStep::Token(number()),RawStep::NeedInput,RawStep::Token(punct(")"))]);let mut cursor=Cursor::new(&a).unwrap();assert!(matches!(cursor.next(&mut source,&a).unwrap(),Step::NeedInput));assert_eq!(source.lookups,["FN"]);assert!(matches!(cursor.next(&mut source,&a).unwrap(),Step::NeedInput));assert_eq!(source.lookups,["FN"]);assert!(matches!(cursor.next(&mut source,&a).unwrap(),Step::Token(Token{string_mode:dm_syntax::OriginalStringMode::Unknown,punctuation_close:false,lexical_frame:None,lexical_span:None,value:Value::Int(1),..})));assert!(matches!(cursor.next(&mut source,&a).unwrap(),Step::End));drop(cursor);assert_eq!(used.load(Ordering::Acquire),0);}
 #[test]fn exact_frame_depth_notice_keeps_original_ident_for_following_body_diagnostic(){let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,2<<20,&||Ok(()));let mut source=input([id("F"),punct("("),number(),punct(")")]);let mut cursor=Cursor::new(&a).unwrap();assert!(matches!(cursor.next(&mut source,&a).unwrap(),Step::Notice(Notice{kind:NoticeKind::DepthLimit(n),..})if n.as_str()=="F"));assert_eq!(source.lookups.len(),33);assert_eq!(source.invocations,32);assert!(matches!(cursor.next(&mut source,&a).unwrap(),Step::Token(t)if name(&t)==Some("F")));assert_eq!(source.lookups.len(),33);drop(cursor);assert_eq!(used.load(Ordering::Acquire),0);}
 #[test]fn actual_object_replacement_rebinds_definition_coordinates_to_invocation_before_final_delivery(){let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let mut source=input([id("OBJECT")]);let mut cursor=Cursor::new(&a).unwrap();let Step::Token(token)=cursor.next(&mut source,&a).unwrap()else{panic!("actual object output token")};assert!(matches!(token.value,Value::Int(1)));assert_eq!(token.origin,Origin{invocation:true,..at()});assert_eq!(token.raw_spelling(),Some("1"));assert_eq!(source.lookups,["OBJECT"]);assert_eq!(source.invocations,1);drop((token,cursor));assert_eq!(used.load(Ordering::Acquire),0);}

 #[test]fn actual_argument_io_poison_prevents_all_retry_reads_and_fresh_cursor_recovers(){
  struct Fault{inner:Input,reads:usize,fail_at:usize}
  impl Source<'static>for Fault{
   fn next_raw(&mut self,a:&SettingAdmission<'_>)->io::Result<RawStep<'static>>{self.reads+=1;if self.reads==self.fail_at{return Err(io::Error::from_raw_os_error(1450))}self.inner.next_raw(a)}
   fn lookup(&mut self,n:&str,a:&SettingAdmission<'_>)->io::Result<Option<Definition<'static>>>{self.inner.lookup(n,a)}
   fn include_depth(&self)->usize{1}
   fn dynamic(&mut self,b:bool,o:Origin,a:&SettingAdmission<'_>)->io::Result<Token<'static>>{self.inner.dynamic(b,o,a)}
   fn invocation(&mut self,n:&str,o:Origin,a:&SettingAdmission<'_>)->io::Result<()>{self.inner.invocation(n,o,a)}
  }
  let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,1<<20,&||Ok(()));
  let mut source=Fault{inner:input([id("FN"),punct("("),number(),punct(")")]),reads:0,fail_at:3};
  let mut cursor=Cursor::new(&a).unwrap();assert_eq!(cursor.next(&mut source,&a).err().unwrap().raw_os_error(),Some(1450));let reads=source.reads;
  for _ in 0..3{assert_eq!(cursor.next(&mut source,&a).err().unwrap().kind(),io::ErrorKind::InvalidInput);assert_eq!(cursor.next_undispatched_using(&mut source,&a).err().unwrap().kind(),io::ErrorKind::InvalidInput);}assert_eq!(source.reads,reads);
  drop(cursor);let mut source=input([id("FN"),punct("("),number(),punct(")")]);let mut fresh=Cursor::new(&a).unwrap();assert!(matches!(fresh.next(&mut source,&a).unwrap(),Step::Token(t)if matches!(t.value,Value::Int(1))));drop((fresh,source));assert_eq!(used.load(Ordering::Acquire),0);
 }
 #[test]fn actual_undrained_defined_queue_suppresses_only_ordinary_lookup_and_dynamic_still_precedes_guard(){
  struct Conditional{input:Input,output:VecDeque<Token<'static>>}
  impl Source<'static>for Conditional{
   fn next_raw(&mut self,a:&SettingAdmission<'_>)->io::Result<RawStep<'static>>{self.input.next_raw(a)}
   fn lookup(&mut self,n:&str,a:&SettingAdmission<'_>)->io::Result<Option<Definition<'static>>>{self.input.lookup(n,a)}
   fn preserves_defined_operand(&self)->bool{self.output.len()>=2&&self.output.back().is_some_and(|t|is_punct(t,"("))&&self.output.get(self.output.len()-2).is_some_and(|t|name(t)==Some("defined"))}
   fn include_depth(&self)->usize{1}
   fn dynamic(&mut self,b:bool,o:Origin,a:&SettingAdmission<'_>)->io::Result<Token<'static>>{self.input.dynamic(b,o,a)}
   fn invocation(&mut self,n:&str,o:Origin,a:&SettingAdmission<'_>)->io::Result<()>{self.input.invocation(n,o,a)}
  }
  let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,1<<20,&||Ok(()));
  for operand in ["OBJECT","__LINE__"]{let mut source=Conditional{input:input([id("defined"),punct("("),id(operand),punct(")")]),output:VecDeque::new()};let mut cursor=Cursor::new(&a).unwrap();for _ in 0..4{let Step::Token(token)=cursor.next(&mut source,&a).unwrap()else{panic!("actual buffered output")};source.output.push_back(token);}assert_eq!(source.input.lookups,["defined"]);if operand=="OBJECT"{assert_eq!(name(&source.output[2]),Some("OBJECT"));}else{assert!(matches!(source.output[2].value,Value::Int(3)));}
   source.output.clear();source.input.raw.push_back(RawStep::Token(id("OBJECT")));assert!(matches!(cursor.next(&mut source,&a).unwrap(),Step::Token(t)if matches!(t.value,Value::Int(1))));assert_eq!(source.input.lookups,["defined","OBJECT"]);
  }
  let mut body=input([id("defined"),punct("("),id("OBJECT"),punct(")")]);let mut cursor=Cursor::new(&a).unwrap();for _ in 0..2{assert!(matches!(cursor.next(&mut body,&a).unwrap(),Step::Token(_)));}assert!(matches!(cursor.next(&mut body,&a).unwrap(),Step::Token(t)if matches!(t.value,Value::Int(1))));assert_eq!(body.lookups,["defined","OBJECT"]);drop(cursor);assert_eq!(used.load(Ordering::Acquire),0);
 }
 #[test]fn actual_identifier_owner_hook_precedes_dynamic_and_lookup_but_not_raw_arguments_or_noncall_bypass(){
  struct Observed{input:Input,events:Vec<String>}
  impl Source<'static>for Observed{
   fn before_identifier(&mut self,n:&str,_:Origin,_:&SettingAdmission<'_>)->io::Result<()>{self.events.push(format!("before:{n}"));Ok(())}
   fn next_raw(&mut self,a:&SettingAdmission<'_>)->io::Result<RawStep<'static>>{self.input.next_raw(a)}
   fn lookup(&mut self,n:&str,a:&SettingAdmission<'_>)->io::Result<Option<Definition<'static>>>{self.events.push(format!("lookup:{n}"));self.input.lookup(n,a)}
   fn include_depth(&self)->usize{1}
   fn dynamic(&mut self,b:bool,o:Origin,a:&SettingAdmission<'_>)->io::Result<Token<'static>>{self.events.push("dynamic".into());self.input.dynamic(b,o,a)}
   fn invocation(&mut self,n:&str,o:Origin,a:&SettingAdmission<'_>)->io::Result<()>{self.events.push(format!("invoke:{n}"));self.input.invocation(n,o,a)}
  }
  let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let mut source=Observed{input:input([id("__LINE__"),id("FN"),id("TOO_FEW")]),events:Vec::new()};let mut cursor=Cursor::new(&a).unwrap();for _ in 0..3{assert!(matches!(cursor.next(&mut source,&a).unwrap(),Step::Token(_)));}assert_eq!(source.events,["before:__LINE__","dynamic","before:FN","lookup:FN"]);drop(cursor);
  let mut source=Observed{input:input([id("MAKE"),punct("("),id("TOO_FEW"),punct("("),number(),punct(")"),punct(")")]),events:Vec::new()};let mut cursor=Cursor::new(&a).unwrap();assert!(matches!(cursor.next(&mut source,&a).unwrap(),Step::Token(t)if is_punct(&t,",")));assert_eq!(source.events,["before:MAKE","lookup:MAKE","invoke:MAKE"]);cursor.stop();drop(cursor);assert_eq!(used.load(Ordering::Acquire),0);
 }
 struct TraceInput{inner:Input,events:Vec<(String,usize)>,fail_push:bool}
 impl Source<'static> for TraceInput{
  fn next_raw(&mut self,a:&SettingAdmission<'_>)->io::Result<RawStep<'static>>{self.inner.next_raw(a)}
  fn lookup(&mut self,name:&str,a:&SettingAdmission<'_>)->io::Result<Option<Definition<'static>>>{self.inner.lookup(name,a)}
  fn include_depth(&self)->usize{1}
  fn dynamic(&mut self,file:bool,origin:Origin,a:&SettingAdmission<'_>)->io::Result<Token<'static>>{self.inner.dynamic(file,origin,a)}
  fn invocation(&mut self,name:&str,origin:Origin,a:&SettingAdmission<'_>)->io::Result<()>{self.inner.invocation(name,origin,a)}
  fn expansion_pushed(&mut self,name:&str,origin:Origin,depth:usize,_:&SettingAdmission<'_>)->io::Result<()>{if self.fail_push{return Err(io::Error::from_raw_os_error(1450))}assert!(origin.invocation);self.events.push((name.into(),depth));Ok(())}
  fn expansion_popped(&mut self,depth:usize,_:&SettingAdmission<'_>)->io::Result<()>{self.events.push(("pop".into(),depth));Ok(())}
 }
 #[test]fn actual_nested_replacement_callbacks_preserve_live_ancestry_until_each_frame_is_really_retired(){
  let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,4<<20,&||Ok(()));let mut source=TraceInput{inner:input([id("FN"),punct("("),id("OBJECT"),punct(")")]),events:Vec::new(),fail_push:false};let mut cursor=Cursor::new(&a).unwrap();assert!(matches!(cursor.next(&mut source,&a).unwrap(),Step::Token(Token{value:Value::Int(1),..})));assert_eq!(source.events,[("FN".into(),1),("OBJECT".into(),2)]);assert_eq!(cursor.expansion_depth(),2);assert!(matches!(cursor.next(&mut source,&a).unwrap(),Step::End));assert_eq!(source.events,[("FN".into(),1),("OBJECT".into(),2),("pop".into(),1),("pop".into(),0)]);drop((cursor,source));assert_eq!(used.load(Ordering::Acquire),0);
 }
 #[test]fn actual_trace_callback_first_io_poison_does_not_publish_a_replacement_or_pull_future_raw_input(){
  let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,4<<20,&||Ok(()));let mut source=TraceInput{inner:input([id("OBJECT"),id("LATER")]),events:Vec::new(),fail_push:true};let mut cursor=Cursor::new(&a).unwrap();assert_eq!(cursor.next(&mut source,&a).err().unwrap().raw_os_error(),Some(1450));assert_eq!(cursor.expansion_depth(),0);assert!(source.events.is_empty());let remaining=source.inner.raw.len();source.fail_push=false;assert_eq!(cursor.next(&mut source,&a).err().unwrap().kind(),io::ErrorKind::InvalidInput);assert_eq!(source.inner.raw.len(),remaining);drop((cursor,source));let mut fresh=TraceInput{inner:input([id("OBJECT")]),events:Vec::new(),fail_push:false};let mut cursor=Cursor::new(&a).unwrap();assert!(matches!(cursor.next(&mut fresh,&a).unwrap(),Step::Token(_)));drop((cursor,fresh));assert_eq!(used.load(Ordering::Acquire),0);
 }

}

#[cfg(test)]mod outer_boundary_tests{
 use super::*;use std::{collections::VecDeque,sync::{Arc,atomic::{AtomicUsize,Ordering}}};
 fn token(value:Value<'static>)->Token<'static>{Token{string_mode:dm_syntax::OriginalStringMode::Unknown,punctuation_close:false,lexical_frame:None,lexical_span:None,raw_spelling:None,value,origin:Origin{physical:dm_syntax::Span::default(),line:1,byte_column:None,occurrence:0,invocation:false}}}
 fn ident(name:&'static str)->Token<'static>{token(Value::Ident{spelling:Text::Borrowed(name),whitespace:false})}
 struct Input{raw:VecDeque<Token<'static>>,reads:usize,lookups:usize}
 impl Source<'static> for Input{
  fn next_raw(&mut self,_:&SettingAdmission<'_>)->io::Result<RawStep<'static>>{self.reads+=1;Ok(self.raw.pop_front().map(RawStep::Token).unwrap_or(RawStep::End))}
  fn lookup(&mut self,name:&str,a:&SettingAdmission<'_>)->io::Result<Option<Definition<'static>>>{self.lookups+=1;let mut replacement=MacroRows::new(a)?;if name=="NEWLINE"{replacement.push(token(Value::Punct("\n")),a)?;return Ok(Some(Definition{parameters:None,variadic:false,replacement}))}if name=="FN"{let mut parameters=MacroRows::new(a)?;parameters.push(owned("x",a)?,a)?;return Ok(Some(Definition{parameters:Some(parameters),variadic:false,replacement}))}Ok(None)}
  fn include_depth(&self)->usize{1}
  fn dynamic(&mut self,_:bool,_:Origin,_:&SettingAdmission<'_>)->io::Result<Token<'static>>{panic!("not a dynamic probe")}
  fn invocation(&mut self,_:&str,_:Origin,_:&SettingAdmission<'_>)->io::Result<()>{Ok(())}
 }
 #[test]fn actual_one_outer_noncall_direct_newline_is_output_before_boundary_and_never_a_raw_pump_terminator(){
  let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let mut input=Input{raw:VecDeque::from([token(Value::Punct("\n")),ident("AFTER")]),reads:0,lookups:0};let mut cursor=Cursor::new(&a).unwrap();cursor.begin_outer_using(ident("FN"),&a).unwrap();
  assert!(matches!(cursor.next_outer_using(&mut input,&a).unwrap(),OuterStep::Output(Step::Token(Token{value:Value::Ident{spelling,..},..}))if spelling.get()=="FN"));assert!(matches!(cursor.next_outer_using(&mut input,&a).unwrap(),OuterStep::Output(Step::Token(Token{value:Value::Punct("\n"),..}))));assert!(matches!(cursor.next_outer_using(&mut input,&a).unwrap(),OuterStep::Boundary));assert_eq!((input.reads,input.lookups),(1,1));assert!(matches!(cursor.next_undispatched_using(&mut input,&a).unwrap(),RawStep::Token(Token{value:Value::Ident{spelling,..},..})if spelling.get()=="AFTER"));drop((input,cursor));assert_eq!(used.load(Ordering::Acquire),0);
 }
 #[test]fn actual_one_outer_object_replacement_newline_remains_on_same_stack_until_next_outer_raw_read(){
  let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let mut input=Input{raw:VecDeque::from([ident("AFTER")]),reads:0,lookups:0};let mut cursor=Cursor::new(&a).unwrap();cursor.begin_outer_using(ident("NEWLINE"),&a).unwrap();assert!(matches!(cursor.next_outer_using(&mut input,&a).unwrap(),OuterStep::Boundary));assert_eq!((input.reads,input.lookups),(0,1));assert!(matches!(cursor.next_undispatched_using(&mut input,&a).unwrap(),RawStep::Token(Token{value:Value::Punct("\n"),..})));assert_eq!(input.reads,0);assert!(matches!(cursor.next_undispatched_using(&mut input,&a).unwrap(),RawStep::Token(Token{value:Value::Ident{spelling,..},..})if spelling.get()=="AFTER"));drop((input,cursor));assert_eq!(used.load(Ordering::Acquire),0);
 }
}

#[cfg(test)]mod interleaved_stack_control_tests{
 use super::*;use std::{collections::VecDeque,sync::{Arc,atomic::{AtomicUsize,Ordering}}};
 struct File{floor:usize,tokens:VecDeque<Token<'static>>}struct ActualOrder{files:Vec<File>,changed:bool}
 fn origin()->Origin{Origin{physical:dm_syntax::Span::new(0,1),line:1,byte_column:None,occurrence:0,invocation:false}}
 fn token(value:Value<'static>)->Token<'static>{Token{string_mode:dm_syntax::OriginalStringMode::Unknown,punctuation_close:false,lexical_frame:None,lexical_span:None,raw_spelling:None,value,origin:origin()}}
 fn ident(name:&'static str)->Token<'static>{token(Value::Ident{spelling:Text::Borrowed(name),whitespace:false})}
 impl Source<'static> for ActualOrder{
  fn physical_input_precedes(&self,depth:usize)->bool{self.files.last().is_some_and(|file|depth<=file.floor)}
  fn take_physical_stack_change(&mut self)->bool{std::mem::take(&mut self.changed)}
  fn next_raw(&mut self,_a:&SettingAdmission<'_>)->io::Result<RawStep<'static>>{let Some(file)=self.files.last_mut()else{return Ok(RawStep::End)};if let Some(token)=file.tokens.pop_front(){return Ok(RawStep::Token(token))}self.files.pop();self.changed=true;Ok(RawStep::NeedInput)}
  fn lookup(&mut self,name:&str,a:&SettingAdmission<'_>)->io::Result<Option<Definition<'static>>>{if name!="OBJECT"{return Ok(None)}let mut replacement=MacroRows::new(a)?;replacement.push(token(Value::Punct("#")),a)?;replacement.push(ident("AFTER"),a)?;Ok(Some(Definition{parameters:None,variadic:false,replacement}))}
  fn include_depth(&self)->usize{self.files.len()}
  fn dynamic(&mut self,_:bool,_:Origin,_:&SettingAdmission<'_>)->io::Result<Token<'static>>{Err(io::ErrorKind::Unsupported.into())}
  fn invocation(&mut self,_:&str,_:Origin,_:&SettingAdmission<'_>)->io::Result<()>{Ok(())}
 }
 #[test]fn actual_control_file_push_precedes_old_replacement_but_newer_frames_and_return_order_stay_exact(){
  let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let mut source=ActualOrder{files:vec![File{floor:0,tokens:VecDeque::from([ident("OBJECT"),ident("PARENT")])}],changed:false};let mut cursor=Cursor::new(&a).unwrap();assert!(matches!(cursor.next(&mut source,&a).unwrap(),Step::Token(Token{value:Value::Punct("#"),..})));assert!(cursor.current_expansion_origin(&source).is_some());
  source.files.push(File{floor:cursor.expansion_depth(),tokens:VecDeque::from([ident("OBJECT"),ident("CHILD")])});assert!(cursor.current_expansion_origin(&source).is_none());
  assert!(matches!(cursor.next(&mut source,&a).unwrap(),Step::Token(Token{value:Value::Punct("#"),..})));assert!(cursor.current_expansion_origin(&source).is_some());
  for expected in ["AFTER","CHILD","AFTER","PARENT"]{let Step::Token(token)=cursor.next(&mut source,&a).unwrap()else{panic!("same stack must not expose its internal EOF-pop pause")};assert!(matches!(&token.value,Value::Ident{spelling,..}if spelling.get()==expected));}
  assert!(matches!(cursor.next(&mut source,&a).unwrap(),Step::End));drop((cursor,source));assert_eq!(used.load(Ordering::Acquire),0);
 }

}

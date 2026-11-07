//! Original macro-token DATA and allocation owner. Only the SAME native token
//! and retained quote-frame producer may bind these values to current source.
//! This transient value is not another lexer/model or a source authority grant.
use super::funded_storage::{MacroText,MacroTokenRows,formatted};
use super::original_substitution::{self,JoinTail,TokenView};
use dm_syntax::{SettingAdmission,Span};
use std::io;
#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub(crate) struct Origin{pub(crate) physical:Span,pub(crate) line:usize,pub(crate) byte_column:Option<usize>,pub(crate) occurrence:usize,pub(crate) invocation:bool}
pub(crate) enum Text<'s>{Borrowed(&'s str),Source(crate::SourceText),Owned(MacroText)}
impl Text<'_>{pub(crate) fn get(&self)->&str{match self{Self::Borrowed(s)=>s,Self::Source(s)=>s.as_str(),Self::Owned(s)=>s.as_str()}}pub(crate) fn duplicate(&self,a:&SettingAdmission<'_>)->io::Result<Self>{Ok(match self{Self::Borrowed(s)=>Self::Borrowed(s),Self::Source(s)=>Self::Source(s.clone()),Self::Owned(s)=>{let mut text=MacroText::new(a)?;text.push_str(s.as_str(),a)?;Self::Owned(text)}})}}
pub(crate) type Value<'s>=dm_syntax::OriginalTokenValue<Text<'s>>;
/// The lexical frame is DATA provenance only, NEVER proof of a fresh raw event.
/// Only Source::next_raw may advance a physical quote frame, before macro rescan.
/// Diagnostic Origin is independently rebound to invocation; this identity stays
/// the real definition/input lexer identity, or None for generated facts.
/// punctuation_close preserves the actual pinned CloseColon variant; spelling
/// alone is insufficient. Only the SAME actual lexical fact producer sets it.
/// lexical_span is independent DATA for that event, preserved when diagnostic
/// Origin rebinds; only the actual same-frame owner may lend its original bytes.
pub(crate) struct Token<'s>{pub(crate) string_mode:dm_syntax::OriginalStringMode,pub(crate) punctuation_close:bool,pub(crate) lexical_frame:Option<crate::regions::OriginalLexicalFrameIdentity>,pub(crate) lexical_span:Option<Span>,pub(crate) value:Value<'s>,pub(crate) raw_spelling:Option<Text<'s>>,pub(crate) origin:Origin}
fn poll(a:&SettingAdmission<'_>)->io::Result<()>{a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))}

impl Token<'_>{
 /// Authored spelling and typed value are separate DATA. Old Display is NOT
 /// lossless transport (six-digit float formatting; String-vs-interpolation).
 pub(crate) fn raw_spelling(&self)->Option<&str>{self.raw_spelling.as_ref().map(Text::get)}
 pub(crate) fn write_display(&self,out:&mut MacroText,a:&SettingAdmission<'_>)->io::Result<()>{poll(a)?;if matches!(&self.value,Value::DocComment{kind:dm_syntax::OriginalCommentKind::None,..}){return Err(io::Error::new(io::ErrorKind::InvalidInput,"non-doc comment is not an Original DocComment token"))}let value=self.value.map_text(Text::get);formatted(out,a,|out|value.write_display(out))}
 /// Exact pinned Token Debug, distinct from lossy/display serialization.
 /// Formatting is paid by the SAME MacroText writer; first actual IO survives.
 pub(crate) fn write_debug(&self,out:&mut MacroText,a:&SettingAdmission<'_>)->io::Result<()>{
  poll(a)?;
  if self.punctuation_close&&!matches!(&self.value,Value::Punct(":")){return Err(io::Error::new(io::ErrorKind::InvalidInput,"CloseColon fact without actual colon token"))}
  match &self.value{
   Value::Eof=>out.push_str("Eof",a),
   Value::Punct(p)=>{let name=dm_syntax::original_scalar_transport::original_punctuation_debug_name(p,self.punctuation_close).ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"unissued Original punctuation Debug variant"))?;formatted(out,a,|out|{use std::fmt::Write;write!(out,"Punct({name})")})},
   Value::Ident{spelling,whitespace}=>formatted(out,a,|out|{use std::fmt::Write;write!(out,"Ident({:?}, {:?})",spelling.get(),whitespace)}),
   Value::Int(n)=>formatted(out,a,|out|{use std::fmt::Write;write!(out,"Int({n:?})")}),
   Value::Float(n)=>formatted(out,a,|out|{use std::fmt::Write;write!(out,"Float({n:?})")}),
   Value::String(text)|Value::Resource(text)|Value::InterpBegin(text)|Value::InterpPart(text)|Value::InterpEnd(text)=>{let name=match &self.value{Value::String(_)=>"String",Value::Resource(_)=>"Resource",Value::InterpBegin(_)=>"InterpStringBegin",Value::InterpPart(_)=>"InterpStringPart",Value::InterpEnd(_)=>"InterpStringEnd",_=>unreachable!()};formatted(out,a,|out|{use std::fmt::Write;write!(out,"{name}({:?})",text.get())})},
   Value::DocComment{kind,text}=>{let(kind,target)=match kind{dm_syntax::OriginalCommentKind::BlockFollowing=>("Block","FollowingItem"),dm_syntax::OriginalCommentKind::BlockEnclosing=>("Block","EnclosingItem"),dm_syntax::OriginalCommentKind::LineFollowing=>("Line","FollowingItem"),dm_syntax::OriginalCommentKind::LineEnclosing=>("Line","EnclosingItem"),dm_syntax::OriginalCommentKind::None=>return Err(io::Error::new(io::ErrorKind::InvalidInput,"non-doc comment is not an Original DocComment token"))};formatted(out,a,|out|{use std::fmt::Write;write!(out,"DocComment(DocComment {{ kind: {kind}, target: {target}, text: {:?} }})",text.get())})}
  }
 }
 pub(crate) fn duplicate(&self,a:&SettingAdmission<'_>)->io::Result<Self>{poll(a)?;let value=match &self.value{Value::DocComment{kind,text}=>Value::DocComment{kind:*kind,text:text.duplicate(a)?},Value::Eof=>Value::Eof,Value::Punct(p)=>Value::Punct(p),Value::Ident{spelling,whitespace}=>Value::Ident{spelling:spelling.duplicate(a)?,whitespace:*whitespace},Value::Int(n)=>Value::Int(*n),Value::Float(n)=>Value::Float(*n),Value::String(s)=>Value::String(s.duplicate(a)?),Value::Resource(s)=>Value::Resource(s.duplicate(a)?),Value::InterpBegin(s)=>Value::InterpBegin(s.duplicate(a)?),Value::InterpPart(s)=>Value::InterpPart(s.duplicate(a)?),Value::InterpEnd(s)=>Value::InterpEnd(s.duplicate(a)?)};let raw_spelling=match &self.raw_spelling{Some(text)=>Some(text.duplicate(a)?),None=>None};Ok(Self{string_mode:self.string_mode,punctuation_close:self.punctuation_close,lexical_frame:self.lexical_frame.clone(),lexical_span:self.lexical_span,value,raw_spelling,origin:self.origin})}
}
/// Actual invocation frame supplies its authentic current physical point. Macro
/// replacement DATA shares that invocation origin; no source read occurs here.
pub(crate) struct Factory<'s>{pub(crate) invocation:Origin,pub(crate) source:std::marker::PhantomData<&'s str>}
impl<'s> Factory<'s> {
 fn stringify_tokens<'t>(&self, raw: impl Iterator<Item = &'t Token<'s>>, a: &SettingAdmission<'_>) -> io::Result<Token<'s>> where 's: 't {
  let mut text=MacroText::new(a)?;
  for (index,token) in raw.enumerate() {
   if index>0 {text.push(' ',a)?;}
   token.write_display(&mut text,a)?;
  }
  Ok(Token{string_mode:dm_syntax::OriginalStringMode::Generated,punctuation_close:false,lexical_frame:None,lexical_span:None,value:Value::String(Text::Owned(text)),raw_spelling:None,origin:self.invocation})
 }
}
impl<'s>original_substitution::Tokens for Factory<'s>{
 type Token=Token<'s>;
 fn view<'a>(&self,t:&'a Self::Token)->TokenView<'a>{match &t.value{Value::Ident{spelling,whitespace}=>TokenView::Ident(spelling.get(),*whitespace),Value::Int(n)=>TokenView::Int(*n),Value::Punct("#")=>TokenView::Hash,Value::Punct("##")=>TokenView::Paste,_=>TokenView::Other}}
 fn duplicate(&mut self,t:&Self::Token,a:&SettingAdmission<'_>)->io::Result<Self::Token>{let mut out=t.duplicate(a)?;out.origin=self.invocation;Ok(out)}
 fn join_ident(&mut self,first:&str,last:JoinTail<'_>,whitespace:bool,a:&SettingAdmission<'_>)->io::Result<Self::Token>{let mut spelling=MacroText::new(a)?;spelling.push_str(first,a)?;match last{JoinTail::Ident(last)=>spelling.push_str(last,a)?,JoinTail::Int(n)=>formatted(&mut spelling,a,|out|{use std::fmt::Write;write!(out,"{n}")})?};Ok(Token{string_mode:dm_syntax::OriginalStringMode::Unknown,punctuation_close:false,lexical_frame:None,lexical_span:None,value:Value::Ident{spelling:Text::Owned(spelling),whitespace},raw_spelling:None,origin:self.invocation})}
 fn stringify(&mut self,raw:&MacroTokenRows<Self::Token>,a:&SettingAdmission<'_>)->io::Result<Self::Token>{self.stringify_tokens(raw.iter(),a)}
 fn comma(&mut self,a:&SettingAdmission<'_>)->io::Result<Self::Token>{poll(a)?;Ok(Token{string_mode:dm_syntax::OriginalStringMode::Unknown,punctuation_close:false,lexical_frame:None,lexical_span:None,value:Value::Punct(","),raw_spelling:None,origin:self.invocation})}
}
#[cfg(test)]mod tests{
 use super::*;use super::original_substitution::Tokens;use std::sync::{atomic::{Ordering}};
 fn origin()->Origin{Origin{physical:Span::new(17,21),line:4,byte_column:None,occurrence:0,invocation:true}}
 #[test]fn original_int_token_display_and_paste_use_distinct_actual_old_rules(){let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let mut f=Factory{invocation:origin(),source:std::marker::PhantomData};let raw=[Token{string_mode:dm_syntax::OriginalStringMode::Unknown,punctuation_close:false,lexical_frame:None,lexical_span:None,value:Value::Int(i32::MAX),raw_spelling:None,origin:origin()}];let string=f.stringify_tokens(raw.iter(),&a).unwrap();let Value::String(text)=&string.value else{panic!("actual original String result")};assert_eq!(text.get(),"2.14748e+009");let pasted=f.join_ident("pre",JoinTail::Int(i32::MAX),false,&a).unwrap();let Value::Ident{spelling,..}=&pasted.value else{panic!("actual paste Ident result")};assert_eq!(spelling.get(),"pre2147483647");drop((string,pasted));assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());}
 #[test]fn exact_string_resource_interpolation_display_reuses_unparsed_text_and_boundaries(){let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,1<<20,&||Ok(()));for(value,wanted)in[(Value::String(Text::Borrowed(r"a\n")),"\"a\\n\""),(Value::String(Text::Borrowed("a\"b")),"{\"a\"b\"}"),(Value::String(Text::Borrowed("a\"}b")),"@@a\"}b@"),(Value::Resource(Text::Borrowed("path/file.dmi")),"'path/file.dmi'"),(Value::InterpBegin(Text::Borrowed("a")),"\"a["),(Value::InterpPart(Text::Borrowed("b")),"]b["),(Value::InterpEnd(Text::Borrowed("c")),"]c\"")]{let token=Token{string_mode:dm_syntax::OriginalStringMode::Unknown,punctuation_close:false,lexical_frame:None,lexical_span:None,value,raw_spelling:None,origin:origin()};let mut out=MacroText::new(&a).unwrap();token.write_display(&mut out,&a).unwrap();assert_eq!(out.as_str(),wanted);}assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());}
 #[test]fn original_raw_numeric_spelling_and_float_kind_are_not_replaced_by_rounded_display(){let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let token=Token{string_mode:dm_syntax::OriginalStringMode::Unknown,punctuation_close:false,lexical_frame:None,lexical_span:None,value:Value::Float(1.2345678),raw_spelling:Some(Text::Borrowed("1.2345678")),origin:origin()};let mut display=MacroText::new(&a).unwrap();token.write_display(&mut display,&a).unwrap();assert_eq!(display.as_str(),"1.23457");assert_eq!(token.raw_spelling(),Some("1.2345678"));let duplicate=token.duplicate(&a).unwrap();assert_eq!(duplicate.raw_spelling(),Some("1.2345678"));assert!(matches!(duplicate.value,Value::Float(n)if n.to_bits()==1.2345678f32.to_bits()));drop((duplicate,display));assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());}

 #[test]fn actual_current_source_views_share_backing_and_survive_definition_aliases_without_text_copy(){let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let source:crate::SourceText="αmacro".to_owned().into();let weak=source.downgrade();let view=source.checked_view(2..7).unwrap();let mut owner=0;source.visit_storage(|p,_,_|owner=p);let token:Token<'static>=Token{string_mode:dm_syntax::OriginalStringMode::Unknown,punctuation_close:false,lexical_frame:None,lexical_span:None,value:Value::Ident{spelling:Text::Source(view.clone()),whitespace:false},raw_spelling:Some(Text::Source(view)),origin:origin()};drop(source);let copy=token.duplicate(&a).unwrap();let Value::Ident{spelling:Text::Source(actual),..}=&copy.value else{panic!("same actual current view, not copied text")};actual.visit_storage(|p,_,_|assert_eq!(p,owner));assert_eq!(copy.raw_spelling(),Some("macro"));drop(token);assert!(weak.upgrade().is_some());drop(copy);assert!(weak.upgrade().is_none());assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());}

 #[test]fn actual_doc_token_display_and_duplicate_are_preserved_inside_raw_macro_arguments(){let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,1<<20,&||Ok(()));for(kind,wanted)in[(dm_syntax::OriginalCommentKind::LineFollowing,"///actual"),(dm_syntax::OriginalCommentKind::LineEnclosing,"//!actual"),(dm_syntax::OriginalCommentKind::BlockFollowing,"/**actual*/"),(dm_syntax::OriginalCommentKind::BlockEnclosing,"/*!actual*/")]{let token=Token{string_mode:dm_syntax::OriginalStringMode::Unknown,punctuation_close:false,lexical_frame:None,lexical_span:None,value:Value::DocComment{kind,text:Text::Borrowed("actual")},raw_spelling:None,origin:origin()};let copy=token.duplicate(&a).unwrap();let mut display=MacroText::new(&a).unwrap();copy.write_display(&mut display,&a).unwrap();assert_eq!(display.as_str(),wanted);let mut factory=Factory{invocation:origin(),source:std::marker::PhantomData};let string=factory.stringify_tokens([copy].iter(),&a).unwrap();assert!(matches!(&string.value,Value::String(text)if text.get()==wanted));}assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());}
 #[test]fn lexical_extent_data_survives_diagnostic_invocation_rebinding_but_generated_tokens_have_none(){let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let raw=Token{string_mode:dm_syntax::OriginalStringMode::Unknown,punctuation_close:false,lexical_frame:None,lexical_span:Some(Span::new(100,109)),value:Value::Float(1.2345678),raw_spelling:None,origin:origin()};let invocation=Origin{physical:Span::new(800,804),line:90,byte_column:None,occurrence:12,invocation:true};let mut factory=Factory{invocation,source:std::marker::PhantomData};let copy=factory.duplicate(&raw,&a).unwrap();assert_eq!(copy.origin,invocation);assert_eq!(copy.lexical_span,Some(Span::new(100,109)));let generated=factory.stringify_tokens([copy].iter(),&a).unwrap();assert!(generated.lexical_span.is_none());assert!(generated.lexical_frame.is_none());drop(generated);assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());}
 #[test]fn pinned_close_colon_fact_survives_clone_and_invocation_rebind_without_display_inference(){let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let raw=Token{string_mode:dm_syntax::OriginalStringMode::Unknown,punctuation_close:true,lexical_frame:None,lexical_span:Some(Span::new(4,5)),value:Value::Punct(":"),raw_spelling:None,origin:origin()};let mut factory=Factory{invocation:origin(),source:std::marker::PhantomData};let copy=factory.duplicate(&raw,&a).unwrap();assert!(copy.punctuation_close);let mut text=MacroText::new(&a).unwrap();copy.write_display(&mut text,&a).unwrap();assert_eq!(text.as_str(),":");let generated=factory.comma(&a).unwrap();assert!(!generated.punctuation_close);drop((copy,generated,text));assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());}
}

#[cfg(test)]mod original_token_debug_tests{
 use super::*; use std::sync::{atomic::{Ordering}};
 use super::original_token_debug_frozen as frozen;
 fn token(value:Value<'static>,close:bool)->Token<'static>{Token{string_mode:dm_syntax::OriginalStringMode::Unknown,value,punctuation_close:close,lexical_frame:None,lexical_span:None,raw_spelling:None,origin:Origin{physical:Span::new(0,1),line:1,byte_column:None,occurrence:0,invocation:false}}}
 fn compare(value:Value<'static>,old:frozen::Token,close:bool){let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,1<<20,&||Ok(()));{let mut text=MacroText::new(&a).unwrap();token(value,close).write_debug(&mut text,&a).unwrap();assert_eq!(text.as_str(),format!("{old:?}"));}assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());}
 #[test]fn exact_frozen_original_punctuation_names_including_actual_closecolon(){
 compare(Value::Punct("in"),frozen::Token::Punct(frozen::Punctuation::In),false);
 compare(Value::Punct("\t"),frozen::Token::Punct(frozen::Punctuation::Tab),false);
 compare(Value::Punct("\n"),frozen::Token::Punct(frozen::Punctuation::Newline),false);
 compare(Value::Punct(" "),frozen::Token::Punct(frozen::Punctuation::Space),false);
 compare(Value::Punct("!"),frozen::Token::Punct(frozen::Punctuation::Not),false);
 compare(Value::Punct("!="),frozen::Token::Punct(frozen::Punctuation::NotEq),false);
 compare(Value::Punct("\""),frozen::Token::Punct(frozen::Punctuation::DoubleQuote),false);
 compare(Value::Punct("#"),frozen::Token::Punct(frozen::Punctuation::Hash),false);
 compare(Value::Punct("##"),frozen::Token::Punct(frozen::Punctuation::TokenPaste),false);
 compare(Value::Punct("%"),frozen::Token::Punct(frozen::Punctuation::Mod),false);
 compare(Value::Punct("%%"),frozen::Token::Punct(frozen::Punctuation::FloatMod),false);
 compare(Value::Punct("%%="),frozen::Token::Punct(frozen::Punctuation::FloatModAssign),false);
 compare(Value::Punct("%="),frozen::Token::Punct(frozen::Punctuation::ModAssign),false);
 compare(Value::Punct("&"),frozen::Token::Punct(frozen::Punctuation::BitAnd),false);
 compare(Value::Punct("&&"),frozen::Token::Punct(frozen::Punctuation::And),false);
 compare(Value::Punct("&&="),frozen::Token::Punct(frozen::Punctuation::AndAssign),false);
 compare(Value::Punct("&="),frozen::Token::Punct(frozen::Punctuation::BitAndAssign),false);
 compare(Value::Punct("'"),frozen::Token::Punct(frozen::Punctuation::SingleQuote),false);
 compare(Value::Punct("("),frozen::Token::Punct(frozen::Punctuation::LParen),false);
 compare(Value::Punct(")"),frozen::Token::Punct(frozen::Punctuation::RParen),false);
 compare(Value::Punct("*"),frozen::Token::Punct(frozen::Punctuation::Mul),false);
 compare(Value::Punct("**"),frozen::Token::Punct(frozen::Punctuation::Pow),false);
 compare(Value::Punct("*="),frozen::Token::Punct(frozen::Punctuation::MulAssign),false);
 compare(Value::Punct("+"),frozen::Token::Punct(frozen::Punctuation::Add),false);
 compare(Value::Punct("++"),frozen::Token::Punct(frozen::Punctuation::PlusPlus),false);
 compare(Value::Punct("+="),frozen::Token::Punct(frozen::Punctuation::AddAssign),false);
 compare(Value::Punct(","),frozen::Token::Punct(frozen::Punctuation::Comma),false);
 compare(Value::Punct("-"),frozen::Token::Punct(frozen::Punctuation::Sub),false);
 compare(Value::Punct("--"),frozen::Token::Punct(frozen::Punctuation::MinusMinus),false);
 compare(Value::Punct("-="),frozen::Token::Punct(frozen::Punctuation::SubAssign),false);
 compare(Value::Punct("."),frozen::Token::Punct(frozen::Punctuation::Dot),false);
 compare(Value::Punct(".."),frozen::Token::Punct(frozen::Punctuation::Super),false);
 compare(Value::Punct("..."),frozen::Token::Punct(frozen::Punctuation::Ellipsis),false);
 compare(Value::Punct("/"),frozen::Token::Punct(frozen::Punctuation::Slash),false);
 compare(Value::Punct("/*"),frozen::Token::Punct(frozen::Punctuation::BlockComment),false);
 compare(Value::Punct("//"),frozen::Token::Punct(frozen::Punctuation::LineComment),false);
 compare(Value::Punct("/="),frozen::Token::Punct(frozen::Punctuation::DivAssign),false);
 compare(Value::Punct(":"),frozen::Token::Punct(frozen::Punctuation::Colon),false);
 compare(Value::Punct(":"),frozen::Token::Punct(frozen::Punctuation::CloseColon),true);
 compare(Value::Punct("::"),frozen::Token::Punct(frozen::Punctuation::Scope),false);
 compare(Value::Punct(":="),frozen::Token::Punct(frozen::Punctuation::AssignInto),false);
 compare(Value::Punct(";"),frozen::Token::Punct(frozen::Punctuation::Semicolon),false);
 compare(Value::Punct("<"),frozen::Token::Punct(frozen::Punctuation::Less),false);
 compare(Value::Punct("<<"),frozen::Token::Punct(frozen::Punctuation::LShift),false);
 compare(Value::Punct("<<="),frozen::Token::Punct(frozen::Punctuation::LShiftAssign),false);
 compare(Value::Punct("<="),frozen::Token::Punct(frozen::Punctuation::LessEq),false);
 compare(Value::Punct("<=>"),frozen::Token::Punct(frozen::Punctuation::LessOrGreater),false);
 compare(Value::Punct("<>"),frozen::Token::Punct(frozen::Punctuation::LessGreater),false);
 compare(Value::Punct("="),frozen::Token::Punct(frozen::Punctuation::Assign),false);
 compare(Value::Punct("=="),frozen::Token::Punct(frozen::Punctuation::Eq),false);
 compare(Value::Punct(">"),frozen::Token::Punct(frozen::Punctuation::Greater),false);
 compare(Value::Punct(">="),frozen::Token::Punct(frozen::Punctuation::GreaterEq),false);
 compare(Value::Punct(">>"),frozen::Token::Punct(frozen::Punctuation::RShift),false);
 compare(Value::Punct(">>="),frozen::Token::Punct(frozen::Punctuation::RShiftAssign),false);
 compare(Value::Punct("?"),frozen::Token::Punct(frozen::Punctuation::QuestionMark),false);
 compare(Value::Punct("?."),frozen::Token::Punct(frozen::Punctuation::SafeDot),false);
 compare(Value::Punct("?:"),frozen::Token::Punct(frozen::Punctuation::SafeColon),false);
 compare(Value::Punct("?["),frozen::Token::Punct(frozen::Punctuation::SafeLBracket),false);
 compare(Value::Punct("["),frozen::Token::Punct(frozen::Punctuation::LBracket),false);
 compare(Value::Punct("]"),frozen::Token::Punct(frozen::Punctuation::RBracket),false);
 compare(Value::Punct("^"),frozen::Token::Punct(frozen::Punctuation::BitXor),false);
 compare(Value::Punct("^="),frozen::Token::Punct(frozen::Punctuation::BitXorAssign),false);
 compare(Value::Punct("{"),frozen::Token::Punct(frozen::Punctuation::LBrace),false);
 compare(Value::Punct("{\""),frozen::Token::Punct(frozen::Punctuation::BlockString),false);
 compare(Value::Punct("|"),frozen::Token::Punct(frozen::Punctuation::BitOr),false);
 compare(Value::Punct("|="),frozen::Token::Punct(frozen::Punctuation::BitOrAssign),false);
 compare(Value::Punct("||"),frozen::Token::Punct(frozen::Punctuation::Or),false);
 compare(Value::Punct("||="),frozen::Token::Punct(frozen::Punctuation::OrAssign),false);
 compare(Value::Punct("}"),frozen::Token::Punct(frozen::Punctuation::RBrace),false);
 compare(Value::Punct("~"),frozen::Token::Punct(frozen::Punctuation::BitNot),false);
 compare(Value::Punct("~!"),frozen::Token::Punct(frozen::Punctuation::NotEquiv),false);
 compare(Value::Punct("~="),frozen::Token::Punct(frozen::Punctuation::Equiv),false);
 }
 #[test]fn exact_frozen_original_scalar_static_interpolation_and_doc_debug(){
 compare(Value::Eof,frozen::Token::Eof,false);
 for n in [i32::MIN,0,i32::MAX]{compare(Value::Int(n),frozen::Token::Int(n),false);}
 for n in [-0.0f32,1.0,1.2345678,f32::INFINITY,f32::NEG_INFINITY,f32::NAN]{compare(Value::Float(n),frozen::Token::Float(n),false);}
 for text in ["", "a\n\t\0\"\\α漢", "[static]"]{
 compare(Value::String(Text::Borrowed(text)),frozen::Token::String(text.into()),false);
 compare(Value::Resource(Text::Borrowed(text)),frozen::Token::Resource(text.into()),false);
 compare(Value::InterpBegin(Text::Borrowed(text)),frozen::Token::InterpStringBegin(text.into()),false);
 compare(Value::InterpPart(Text::Borrowed(text)),frozen::Token::InterpStringPart(text.into()),false);
 compare(Value::InterpEnd(Text::Borrowed(text)),frozen::Token::InterpStringEnd(text.into()),false);
 for whitespace in [false,true]{compare(Value::Ident{spelling:Text::Borrowed(text),whitespace},frozen::Token::Ident(text.into(),whitespace),false);}
 for kind in [dm_syntax::OriginalCommentKind::BlockFollowing,dm_syntax::OriginalCommentKind::BlockEnclosing,dm_syntax::OriginalCommentKind::LineFollowing,dm_syntax::OriginalCommentKind::LineEnclosing]{let(k,t)=match kind{dm_syntax::OriginalCommentKind::BlockFollowing=>(frozen::CommentKind::Block,frozen::DocTarget::FollowingItem),dm_syntax::OriginalCommentKind::BlockEnclosing=>(frozen::CommentKind::Block,frozen::DocTarget::EnclosingItem),dm_syntax::OriginalCommentKind::LineFollowing=>(frozen::CommentKind::Line,frozen::DocTarget::FollowingItem),_=>(frozen::CommentKind::Line,frozen::DocTarget::EnclosingItem)};compare(Value::DocComment{kind,text:Text::Borrowed(text)},frozen::Token::DocComment(frozen::DocComment{kind:k,target:t,text:text.into()}),false);}
 }
 }
 #[test]fn first_io_quota_invalid_close_are_typed_and_fresh_writer_recovers(){let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let good=SettingAdmission::new(&used,1<<20,&||Ok(()));let fault=||Err(io::Error::from_raw_os_error(1450));let bad=SettingAdmission::new(&used,1<<20,&fault);{let mut text=MacroText::new(&good).unwrap();assert_eq!(token(Value::Int(4),false).write_debug(&mut text,&bad).unwrap_err().raw_os_error(),Some(1450));assert!(text.as_str().is_empty());assert_eq!(token(Value::Punct(";"),true).write_debug(&mut text,&good).unwrap_err().kind(),io::ErrorKind::InvalidInput);token(Value::Int(4),false).write_debug(&mut text,&good).unwrap();assert_eq!(text.as_str(),"Int(4)");}assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());let tiny=SettingAdmission::new(&used,dm_syntax::SettingChargeCounter::root_allocation_bytes(),&||Ok(()));{let mut out=MacroText::new(&tiny).unwrap();assert!(token(Value::Int(4),false).write_debug(&mut out,&tiny).is_err());assert!(out.as_str().is_empty());}assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());}
}

#[cfg(test)]#[path="original_token_debug_frozen.rs"]mod original_token_debug_frozen;

#[cfg(test)]mod actual_string_mode_token_tests{
 use super::*;use super::original_substitution::Tokens;use std::sync::{atomic::{Ordering}};
 #[test]fn actual_clone_substitution_rebind_and_stringify_preserve_distinct_issued_modes(){let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let origin=Origin{physical:Span::new(1,5),line:1,byte_column:None,occurrence:1,invocation:false};let mut f=Factory{invocation:origin,source:std::marker::PhantomData};for mode in [dm_syntax::OriginalStringMode::Normal,dm_syntax::OriginalStringMode::Raw,dm_syntax::OriginalStringMode::Generated]{let token=Token{string_mode:mode,punctuation_close:false,lexical_frame:None,lexical_span:None,value:Value::String(Text::Borrowed("same")),raw_spelling:None,origin};let copy=f.duplicate(&token,&a).unwrap();assert_eq!(copy.string_mode,mode);let generated=f.stringify_tokens([copy].iter(),&a).unwrap();assert_eq!(generated.string_mode,dm_syntax::OriginalStringMode::Generated);}assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());}
}

#[cfg(test)]mod byte_column_data_tests{
 use super::*;use super::original_substitution::Tokens;use std::sync::{atomic::{Ordering}};
 #[test]fn original_point_data_survives_clone_and_rebind_while_nonphysical_initial_is_explicitly_absent(){
  let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,1<<20,&||Ok(()));
  let original=Origin{physical:Span::new(17,21),line:4,byte_column:Some(13),occurrence:2,invocation:false};let raw=Token{string_mode:dm_syntax::OriginalStringMode::Unknown,punctuation_close:false,lexical_frame:None,lexical_span:None,raw_spelling:None,value:Value::Ident{spelling:Text::Borrowed("name"),whitespace:false},origin:original};
  assert_eq!(raw.duplicate(&a).unwrap().origin.byte_column,Some(13));let invocation=Origin{physical:Span::new(99,103),line:9,byte_column:Some(35),occurrence:7,invocation:true};let mut f=Factory{invocation,source:std::marker::PhantomData};let rebound=f.duplicate(&raw,&a).unwrap();assert_eq!(rebound.origin.byte_column,Some(35));assert_eq!(rebound.origin.occurrence,7);
  let initial=Origin{physical:Span::default(),line:0,byte_column:None,occurrence:0,invocation:false};assert!(initial.byte_column.is_none());drop((raw,rebound));assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
 }
}

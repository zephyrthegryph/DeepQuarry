//! SAME raw macro/include stack expectations for actual directive execution.
//! Failure message DATA is returned to the owner, which resolves the genuine
//! current lexer tracker; invocation Origin is not diagnostic location authority.
use crate::macro_expansion::{OriginalMacroCursor as Cursor,OriginalMacroSource as Source,OriginalMacroRawStep as RawStep,OriginalMacroToken as Token,OriginalMacroValue as Value,OriginalMacroText as Text};
use dm_syntax::SettingAdmission;use std::io;
#[derive(Clone,Copy)]pub(super) enum Expected{Identifier,String,Newline}
impl Expected{fn pattern(self)->&'static str{match self{Self::Identifier=>"Token::Ident(ident, _)",Self::String=>"Token::String(path_str)",Self::Newline=>"Token::Punct(Punctuation::Newline)"}}}
pub(super) enum ExpectProgress{Token(Token<'static>),NeedInput,SourceFailure(Text)}
/// The actual old stringify! pattern includes local binding names. The owner
/// supplies the exact source branch's static pattern, never token text guesses.
pub(super) fn expect_using(cursor:&mut Cursor<'static>,source:&mut impl Source<'static>,expected:Expected,actual_pattern:Option<&'static str>,a:&SettingAdmission<'_>)->io::Result<ExpectProgress>{
 a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;let actual=match cursor.next_undispatched_using(source,a)?{RawStep::NeedInput=>return Ok(ExpectProgress::NeedInput),RawStep::End=>{let mut message=Text::new(a)?;message.push_str("unexpected EOF",a)?;return Ok(ExpectProgress::SourceFailure(message))},RawStep::Token(token)=>token};
 let accepts=matches!((expected,&actual.value),(Expected::Identifier,Value::Ident{..})|(Expected::String,Value::String(_))|(Expected::Newline,Value::Punct("\n")));
 if accepts{return Ok(ExpectProgress::Token(actual))}let mut message=Text::new(a)?;message.push_str("unexpected token ",a)?;actual.write_debug(&mut message,a)?;message.push_str(", expecting ",a)?;message.push_str(actual_pattern.unwrap_or_else(||expected.pattern()),a)?;Ok(ExpectProgress::SourceFailure(message))
}

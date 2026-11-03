//! One native grammar DATA projection of actual produced macro token values.
//! Shared by the genuine condition lender and later final-output owner.
use super::original_literal_owner::static_literal_using;
use crate::{SourceProvider,macro_expansion::{OriginalMacroToken as Token,OriginalMacroValue as Value,OriginalMacroText as Text}};
use dm_syntax::{OriginalLiteralData,SettingAdmission,TokenKind};use std::io;
#[derive(Clone,Copy)]pub(super) enum Adjacency{Word,Punct,Other,Whitespace}
pub(super) struct OriginalNativeProjection{pub(super) kind:TokenKind,pub(super) spelling:Text,pub(super) literal:Option<dm_syntax::OriginalLiteralData>,pub(super) adjacency:Adjacency}
pub(super) fn project_native_token_using(actual:&Token<'_>,provider:&dyn SourceProvider,a:&SettingAdmission<'_>)->io::Result<OriginalNativeProjection>{
  let literal=static_literal_using(actual,provider,a)?;let mut spelling=Text::new(a)?;
  let(kind,adjacency)=match &actual.value{
   Value::Ident{spelling:name,..}=>{spelling.push_str(name.get(),a)?;(TokenKind::Ident,Adjacency::Word)},
   Value::Punct(text)=>{spelling.push_str(text,a)?;match *text{"in"=>(TokenKind::Ident,Adjacency::Word),"\n"=>(TokenKind::Newline,Adjacency::Whitespace)," "|"\t"=>(TokenKind::Whitespace,Adjacency::Whitespace),_=>(dm_syntax::original_scalar_transport::original_punctuation_native_kind(text),Adjacency::Punct)}},
   Value::Int(_)|Value::Float(_)=>{spelling.push_str(literal.as_ref().ok_or(io::ErrorKind::InvalidData)?.raw(),a)?;(TokenKind::Number,Adjacency::Word)},
   Value::String(_)=>{spelling.push_str(literal.as_ref().ok_or(io::ErrorKind::InvalidData)?.raw(),a)?;(TokenKind::String,Adjacency::Other)},
   Value::Resource(_)=>{spelling.push_str(literal.as_ref().ok_or(io::ErrorKind::InvalidData)?.raw(),a)?;(TokenKind::Resource,Adjacency::Other)},
   // Display is the unique exact docs judge only. Ordinary scalar/static
   // literal meaning NEVER goes through that lossy formatting operation.
   Value::DocComment{..}=>{actual.write_display(&mut spelling,a)?;(TokenKind::Comment,Adjacency::Other)},
   Value::InterpBegin(_)|Value::InterpPart(_)|Value::InterpEnd(_)=>{spelling.push_str(literal.as_ref().ok_or(io::ErrorKind::InvalidData)?.raw(),a)?;(TokenKind::Interpolation,Adjacency::Other)},
   Value::Eof=>return Err(io::Error::new(io::ErrorKind::InvalidInput,"actual source End is not an emitted grammar token")),
  };
 Ok(OriginalNativeProjection{kind,spelling,literal,adjacency})
}

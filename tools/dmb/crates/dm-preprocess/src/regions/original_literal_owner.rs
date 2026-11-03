//! Actual final-token→immutable scalar/static DATA handoff. Physical spelling
//! is lent from SAME raw acquisition+lexical extent, never Token Display or a
//! normalized SourceText offset. Typed value/kind/float bits stay unchanged.
use crate::{SourceProvider,macro_expansion::{OriginalMacroToken as Token,OriginalMacroValue as Value,OriginalMacroText as Text,original_format_using,original_quote_delimiters}};
use dm_syntax::{OriginalLiteralData,SettingAdmission};use std::io;
fn poll(a:&SettingAdmission<'_>)->io::Result<()>{a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))}
pub(super) fn static_literal_using(token:&Token<'_>,provider:&dyn SourceProvider,a:&SettingAdmission<'_>)->io::Result<Option<OriginalLiteralData>>{
 poll(a)?;match &token.value{
  Value::Int(_)|Value::Float(_)|Value::String(_)|Value::Resource(_)|Value::InterpBegin(_)|Value::InterpPart(_)|Value::InterpEnd(_)=>(),
  _=>return Ok(None),
 }
 let raw=actual_grammar_spelling_using(token,provider,a)?;
 let(raw,credit)=raw.into_parts();
 // This moves the SAME String and existing allocation credit. Fixed metadata
 // and actual value-copy allocations are then funded by that SAME root, not a
 // second capacity reservation for bytes already live in the raw spelling.
 OriginalLiteralData::from_admitted_raw_with_mode_using(raw,credit,token.value.map_text(|text|text.get()),token.string_mode,a).map(Some)
}

/// Lossless authored/genuinely generated grammar DATA. Macro metadata mirrors
/// borrow this SAME producer; Original macro lookup always consumes the typed
/// definition product, never this String. No literal owner/parser is created.
pub(super) fn actual_grammar_spelling_using(token:&Token<'_>,provider:&dyn SourceProvider,a:&SettingAdmission<'_>)->io::Result<Text>{
 poll(a)?;
 let mut raw=Text::new(a)?;
 match(&token.lexical_frame,token.lexical_span){
  (Some(frame),Some(span))=>{
   if !frame.admitted_by(a){return Err(io::ErrorKind::InvalidInput.into())}
   let bytes=provider.original_source_bytes(frame.acquisition())?.ok_or_else(||io::Error::new(io::ErrorKind::NotConnected,"actual lexical spelling issuer is unavailable"))?;let spelling=bytes.get(span.range()).ok_or(io::ErrorKind::InvalidInput)?;
   // Whole original token spelling is converted ONCE with the shared codec;
   // all physical coordinates remain in the original raw frame, not this UTF8
   // grammar DATA. Any invalid byte makes the WHOLE spelling Latin1.
   dm_syntax::original_token_value::visit_original_token_value_using(spelling,&mut||poll(a),&mut|part|raw.push_str(part,a))?;
  },
  (None,None)=>{
   if let Some(spelling)=token.raw_spelling(){raw.push_str(spelling,a)?;}else{match &token.value{
    Value::Ident{spelling,..}=>raw.push_str(spelling.get(),a)?,
    Value::Punct(spelling)=>raw.push_str(spelling,a)?,
    // Genuine generated LINE has exact decimal Int spelling. Stringify/FILE
    // are generated static String values and use the SAME original quote rule;
    // brackets remain static via retained typed DATA, never relexed templates.
    Value::Int(value)=>original_format_using(&mut raw,a,|out|{use std::fmt::Write;write!(out,"{value}")})?,
    Value::String(value)=>{let(open,close)=original_quote_delimiters(value.get());raw.push_str(open,a)?;raw.push_str(value.get(),a)?;raw.push_str(close,a)?;},
    Value::InterpBegin(value)=>{raw.push_str("\"",a)?;raw.push_str(value.get(),a)?;raw.push_str("[",a)?;},
    Value::InterpPart(value)=>{raw.push_str("]",a)?;raw.push_str(value.get(),a)?;raw.push_str("[",a)?;},
    Value::InterpEnd(value)=>{raw.push_str("]",a)?;raw.push_str(value.get(),a)?;raw.push_str("\"",a)?;},
    _=>return Err(io::Error::new(io::ErrorKind::Unsupported,"actual generated literal lacks lossless grammar spelling")),
   }}
  },
  _=>return Err(io::Error::new(io::ErrorKind::InvalidInput,"actual lexical frame and spelling extent must travel together")),
 }
 Ok(raw)
}

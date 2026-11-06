//! Actual final-token→immutable scalar/static DATA handoff. Physical spelling
//! is lent from SAME raw acquisition+lexical extent, never Token Display or a
//! normalized SourceText offset. Typed value/kind/float bits stay unchanged.
use crate::{SourceProvider,macro_expansion::{OriginalMacroToken as Token,OriginalMacroValue as Value,OriginalMacroText as Text,original_format_using,original_quote_delimiters}};
use dm_syntax::{OriginalLiteralData,OriginalLiteralPool,SettingAdmission};use std::io;
fn poll(a:&SettingAdmission<'_>)->io::Result<()>{a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))}
pub(super) fn static_literal_using(token:&Token<'_>,provider:&dyn SourceProvider,a:&SettingAdmission<'_>,pool:Option<&mut OriginalLiteralPool>)->io::Result<Option<OriginalLiteralData>>{
 poll(a)?;match &token.value{
  Value::Int(_)|Value::Float(_)|Value::String(_)|Value::Resource(_)|Value::InterpBegin(_)|Value::InterpPart(_)|Value::InterpEnd(_)=>(),
  _=>return Ok(None),
 }
 let raw=actual_grammar_spelling_using(token,provider,a)?;
 let(raw,credit)=raw.into_parts();
 // This moves the SAME String and existing allocation credit. Fixed metadata
 // and actual value-copy allocations are then funded by that SAME root, not a
 // second capacity reservation for bytes already live in the raw spelling.
 let value=token.value.map_text(|text|text.get());
 if matches!(&value,dm_syntax::OriginalTokenValue::Int(_)|dm_syntax::OriginalTokenValue::Float(_)|dm_syntax::OriginalTokenValue::String(_)|dm_syntax::OriginalTokenValue::Resource(_)){
  if let Some(pool)=pool{return pool.issue_using(raw,credit,value,token.string_mode,a).map(Some)}
 }
 OriginalLiteralData::from_admitted_raw_with_mode_using(raw,credit,value,token.string_mode,a).map(Some)
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

#[cfg(test)]
mod static_pool_io_tests {
    use super::*;
    use crate::{SourceAcquisitionLease, macro_expansion::{OriginalMacroOrigin as Origin, OriginalMacroTextValue}};
    use dm_syntax::{OriginalStringMode, Span};
    use std::{cell::Cell, path::Path, sync::{Arc, atomic::{AtomicUsize, Ordering}}};

    struct Source {
        lease: SourceAcquisitionLease,
        reads: Cell<usize>,
        fail: Cell<bool>,
    }
    impl SourceProvider for Source {
        fn read(&self, _: &Path) -> Result<String, String> { panic!("raw source only") }
        fn original_source_bytes<'a>(&'a self, lease: &'a SourceAcquisitionLease) -> io::Result<Option<&'a [u8]>> {
            assert!(lease.same_original_acquisition(&self.lease));
            self.reads.set(self.reads.get() + 1);
            if self.fail.get() { return Err(io::Error::from_raw_os_error(1450)); }
            Ok(Some(lease.source_text().as_bytes()))
        }
    }

    #[test]
    fn warm_static_pool_still_requires_the_next_actual_raw_provider_loan() {
        let used = Arc::new(AtomicUsize::new(0));
        let a = SettingAdmission::new(&used, 1 << 20, &|| Ok(()));
        let source = Source {
            lease: SourceAcquisitionLease::from_raw_original_bytes(b"\"same\" \"same\" \"same\"".to_vec(), 17u64),
            reads: Cell::new(0), fail: Cell::new(false),
        };
        let frame = crate::regions::original_raw_frame::OriginalRawFrame::from_opened(&source, source.lease.clone(), &a).unwrap();
        let token = |start| Token {
            string_mode: OriginalStringMode::Normal, punctuation_close: false,
            lexical_frame: Some(frame.identity().clone()), lexical_span: Some(Span::new(start, start + 6)),
            value: Value::String(OriginalMacroTextValue::Borrowed("same")), raw_spelling: None,
            origin: Origin { physical: Span::new(start, start + 6), line: 1, byte_column: Some(start + 1), occurrence: 0, invocation: false },
        };
        let mut pool = OriginalLiteralPool::new(&a).unwrap();
        let one = static_literal_using(&token(0), &source, &a, Some(&mut pool)).unwrap().unwrap();
        let two = static_literal_using(&token(7), &source, &a, Some(&mut pool)).unwrap().unwrap();
        assert_eq!(one.raw().as_ptr(), two.raw().as_ptr());
        assert_eq!(source.reads.get(), 3, "frame currentness plus two real spelling loans");
        let paid = used.load(Ordering::Acquire);
        source.fail.set(true);
        let failure = static_literal_using(&token(14), &source, &a, Some(&mut pool)).unwrap_err();
        assert_eq!(failure.raw_os_error(), Some(1450));
        assert_eq!(source.reads.get(), 4);
        assert_eq!(used.load(Ordering::Acquire), paid);
        drop((one, two, pool, frame));
        assert_eq!(used.load(Ordering::Acquire), 0);
    }
}

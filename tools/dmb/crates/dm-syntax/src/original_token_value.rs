//! Original token VALUE conversion, distinct from physical-source decoding.
//! Pinned lexer::from_utf8_or_latin1 at0290db5c752fa292f9824521515b603a2afd11dc.
//! Concatenate the actual lexical value bytes BEFORE this call. Valid UTF8 is
//! retained whole; ONE invalid byte selects Latin1 for EVERY byte. No BOM strip,
//! mixed-prefix fallback, CP1252 mapping, unescape, lexer, or source authority.
#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub enum OriginalTokenEncoding{Utf8,Latin1}
/// One shared value operation. Output sink owns/funds actual allocation; this
/// function retains no decoded text/cache/model and never swallows first errors.
pub fn visit_original_token_value_using<E>(bytes:&[u8],checkpoint:&mut dyn FnMut()->Result<(),E>,emit:&mut dyn FnMut(&str)->Result<(),E>)->Result<OriginalTokenEncoding,E>{
 checkpoint()?;let utf8=std::str::from_utf8(bytes);checkpoint()?;
 match utf8{
  Ok(text)=>{let mut at=0;while at<text.len(){checkpoint()?;let mut end=at.saturating_add(1024).min(text.len());while !text.is_char_boundary(end){end-=1;}emit(&text[at..end])?;at=end;}Ok(OriginalTokenEncoding::Utf8)},
  Err(_)=>{for &byte in bytes{checkpoint()?;let mut encoded=[0;4];emit((byte as char).encode_utf8(&mut encoded))?;}Ok(OriginalTokenEncoding::Latin1)},
 }
}
/// Ordinary no-control facade delegates SAME whole-token operation. Native
/// admitted producers use the borrowed/funded sink API above, not this String.
pub fn original_token_value(bytes:&[u8])->String{let mut output=String::new();let result=visit_original_token_value_using::<std::convert::Infallible>(bytes,&mut||Ok(()),&mut|part|{output.push_str(part);Ok(())});match result{Ok(_)=>output,Err(never)=>match never{}}}
#[cfg(test)]#[path="../../../fixtures/original_token_value.rs"]mod immutable_original;
#[cfg(test)]mod tests{
 use super::*;
 #[test]fn actual_whole_token_codec_matches_literal_old_conversion_including_split_utf8_invalid_tail_bom_and_c1(){
  let cases:Vec<Vec<&[u8]>>=vec![vec![b"\xce",b"\xb1"],vec![b"\xce\xb1",b"\xff"],vec![b"\x80",b"\x91"],vec![b"\xef\xbb\xbf",b"a"],vec![b"plain\\n\0"],vec![b"\xc3\xa9"]];for pieces in cases{let bytes:Vec<u8>=pieces.into_iter().flatten().copied().collect();let old=immutable_original::from_utf8_or_latin1(bytes.clone());let actual=original_token_value(&bytes);assert_eq!(actual,old,"{bytes:?}");}
  assert_eq!(original_token_value(&[0xce,0xb1,0xff]),"Î±ÿ","invalid tail makes the WHOLE token Latin1, not only its suffix");assert_eq!(original_token_value(&[0x80,0x91]),"\u{80}\u{91}");assert_eq!(original_token_value(&[0xef,0xbb,0xbf,b'a']),"\u{feff}a");
 }
 #[test]fn actual_first_checkpoint_or_sink_failure_stops_without_emitting_future_value_or_masking_io(){use std::{io,cell::Cell};for denial in [1,2,4]{let calls=Cell::new(0);let emitted=Cell::new(0);let mut checkpoint=||{calls.set(calls.get()+1);if calls.get()==denial{Err(io::Error::from_raw_os_error(1450))}else{Ok(())}};let mut output=|part:&str|{emitted.set(emitted.get()+part.len());Ok(())};let error=visit_original_token_value_using(&[0xff,b'a',b'b'],&mut checkpoint,&mut output).unwrap_err();assert_eq!(error.raw_os_error(),Some(1450));assert!(emitted.get()<=2);}let calls=Cell::new(0);let mut checkpoint=||Ok(());let mut sink=|_:&str|{calls.set(calls.get()+1);Err(io::Error::from_raw_os_error(1450))};assert_eq!(visit_original_token_value_using(b"first second",&mut checkpoint,&mut sink).unwrap_err().raw_os_error(),Some(1450));assert_eq!(calls.get(),1);}
}

// Shared typed VALUE follows the existing whole-token byte codec.
// SAME native Original lexer/macro VALUE transport, shared downward so syntax
// and preprocessing do not recreate or relex values at a parser boundary.
// Text ownership remains with T (borrowed, current SourceText view or admitted
// MacroText). Origin, lexical frame, raw spelling and resource roots remain in
// the actual token owner. This DATA grants no source/model/literal authority.
pub enum OriginalTokenValue<T>{DocComment{kind:crate::OriginalCommentKind,text:T},Ident{spelling:T,whitespace:bool},Int(i32),Float(f32),String(T),Resource(T),InterpBegin(T),InterpPart(T),InterpEnd(T),Punct(&'static str),Eof}

impl<T> OriginalTokenValue<T>{
 /// Allocation-free loan over the SAME value variants, including exact float
 /// bits, static String identity and interpolation pieces. The caller's text
 /// owner remains live for the returned borrow; nothing is Display/relexed.
 pub fn map_text<'a,U>(&'a self,mut map:impl FnMut(&'a T)->U)->OriginalTokenValue<U>{match self{
  Self::DocComment{kind,text}=>OriginalTokenValue::DocComment{kind:*kind,text:map(text)},
  Self::Ident{spelling,whitespace}=>OriginalTokenValue::Ident{spelling:map(spelling),whitespace:*whitespace},
  Self::Int(n)=>OriginalTokenValue::Int(*n),Self::Float(n)=>OriginalTokenValue::Float(*n),
  Self::String(s)=>OriginalTokenValue::String(map(s)),Self::Resource(s)=>OriginalTokenValue::Resource(map(s)),
  Self::InterpBegin(s)=>OriginalTokenValue::InterpBegin(map(s)),Self::InterpPart(s)=>OriginalTokenValue::InterpPart(map(s)),Self::InterpEnd(s)=>OriginalTokenValue::InterpEnd(map(s)),
  Self::Punct(s)=>OriginalTokenValue::Punct(s),Self::Eof=>OriginalTokenValue::Eof,
 }}
}

#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub enum OriginalCommentKind{None,LineFollowing,LineEnclosing,BlockFollowing,BlockEnclosing}

/// SAME original quote delimiter decision used by native macro Display and
/// diagnostics. Value bytes are never unescaped/relexed or inferred from raw.
pub fn original_quote_delimiters(text:&str)->(&'static str,&'static str){if text.contains("\"}"){("@@","@")}else if text.contains('"')||text.contains('\n'){("{\"","\"}")}else{("\"","\"")}}
impl<T:AsRef<str>> OriginalTokenValue<T>{
 /// Allocation-free SAME native Token Display. The actual owner/output sink
 /// admits storage and preserves first operational failure; this is DATA only.
 pub fn write_display(&self,mut out:&mut dyn std::fmt::Write)->std::fmt::Result{use std::fmt::Write;
  match self{
   Self::Eof=>out.write_str("__EOF__"),Self::Punct(p)=>out.write_str(p),Self::Ident{spelling,..}=>out.write_str(spelling.as_ref()),
   Self::Int(n)=>crate::numeric_form::write_original_float(*n as f32,&mut out),Self::Float(n)=>crate::numeric_form::write_original_float(*n,&mut out),
   Self::String(s)=>{let(open,close)=original_quote_delimiters(s.as_ref());out.write_str(open)?;out.write_str(s.as_ref())?;out.write_str(close)},
   Self::Resource(s)=>{out.write_char('\'')?;out.write_str(s.as_ref())?;out.write_char('\'')},
   Self::InterpBegin(s)=>{out.write_char('"')?;out.write_str(s.as_ref())?;out.write_char('[')},Self::InterpPart(s)=>{out.write_char(']')?;out.write_str(s.as_ref())?;out.write_char('[')},Self::InterpEnd(s)=>{out.write_char(']')?;out.write_str(s.as_ref())?;out.write_char('"')},
   Self::DocComment{kind,text}=>{let(open,close)=match kind{OriginalCommentKind::BlockFollowing=>("/**","*/"),OriginalCommentKind::BlockEnclosing=>("/*!","*/"),OriginalCommentKind::LineFollowing=>("///",""),OriginalCommentKind::LineEnclosing=>("//!",""),OriginalCommentKind::None=>return Err(std::fmt::Error)};out.write_str(open)?;out.write_str(text.as_ref())?;out.write_str(close)}
  }
 }
}
#[cfg(test)]mod original_display_controls{
 use super::*;
 #[test]fn same_typed_display_preserves_numeric_value_and_static_string_boundaries(){for(value,wanted)in[(OriginalTokenValue::Int(i32::MAX),"2.14748e+009"),(OriginalTokenValue::Float(1.2345678),"1.23457"),(OriginalTokenValue::String("a[b"),"\"a[b\""),(OriginalTokenValue::String("a\"b"),"{\"a\"b\"}"),(OriginalTokenValue::String("a\"}b"),"@@a\"}b@"),(OriginalTokenValue::Resource("a.dmi"),"'a.dmi'"),(OriginalTokenValue::InterpBegin("a"),"\"a["),(OriginalTokenValue::InterpPart("b"),"]b["),(OriginalTokenValue::InterpEnd("c"),"]c\"")]{let mut output=String::new();value.write_display(&mut output).unwrap();assert_eq!(output,wanted);}}
 #[test]fn same_display_stops_at_first_sink_failure_without_an_intermediate_string(){struct Stop{calls:usize}impl std::fmt::Write for Stop{fn write_str(&mut self,_:&str)->std::fmt::Result{self.calls+=1;Err(std::fmt::Error)}}let mut output=Stop{calls:0};assert!(OriginalTokenValue::String("large actual value").write_display(&mut output).is_err());assert_eq!(output.calls,1);}
}

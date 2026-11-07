//! Value projection from actual SAME native lexical facts. No source scanner,
//! quote parser, model, frame/EOF grant or second macro dictionary exists here.
//! The current physical source owner supplies facts+bytes and authenticates its
//! actual acquisition/frame; range geometry or a decoded value cannot do that.
use super::funded_storage::{MacroRows,MacroText};
use dm_syntax::{OriginalCommentFacts,OriginalCommentKind,OriginalQuotedPart,OriginalQuotedPartKind,SettingAdmission};
use std::io;
fn poll(a:&SettingAdmission<'_>)->io::Result<()>{a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))}
fn decode(bytes:&[u8],a:&SettingAdmission<'_>)->io::Result<MacroText>{
 let mut text=MacroText::new(a)?;
 // ONE validity decision over the concatenated token. Never decode each splice
 // independently, strip BOM, apply CP1252, or reuse physical-source mixed decode.
 dm_syntax::original_token_value::visit_original_token_value_using(bytes,&mut||poll(a),&mut|part|text.push_str(part,a))?;Ok(text)
}
pub(crate) struct QuotedValue{pub(crate) kind:OriginalQuotedPartKind,pub(crate) text:MacroText,pub(crate) lexical:Result<(),dm_syntax::literal::LiteralLexicalError>}
/// Preserve lexical recovery flag as DATA. The actual Source has already issued
/// a genuine unterminated-string notice on recovery; this inner splice error is
/// not a new source diagnostic, model None, or permission to ignore unissued text.
pub(crate) fn quoted_value_using(part:&OriginalQuotedPart<'_>,a:&SettingAdmission<'_>)->io::Result<QuotedValue>{
 poll(a)?;let mut bytes=MacroRows::new(a)?;let lexical=part.visit_value_bytes(|chunk|bytes.extend_from_slice(chunk,a))?;
 let text=decode(bytes.as_slice(),a)?;Ok(QuotedValue{kind:part.kind(),text,lexical})
}
/// None is a real non-doc comment and produces no definition DocComment token.
/// Warnings remain actual Source events emitted from the fact's warning spans,
/// before cursor commit, never reconstructed by rescanning value text here.
pub(crate) fn comment_value_using(facts:&OriginalCommentFacts,actual_input:&[u8],a:&SettingAdmission<'_>)->io::Result<Option<MacroText>>{
 poll(a)?;if matches!(facts.kind(),OriginalCommentKind::None){return Ok(None)}let mut bytes=MacroRows::new(a)?;facts.visit_value_bytes(actual_input,|chunk|bytes.extend_from_slice(chunk,a))??;Ok(Some(decode(bytes.as_slice(),a)?))
}
/// SAME resource-byte projection (slash quotes one following byte), then the
/// SAME whole-token UTF8/else-Latin1 conversion. Genuine unterminated resource
/// notice/recovery was issued by actual raw cursor, not inferred from its text.
pub(crate) fn resource_value_using(facts:&dm_syntax::OriginalResourceFacts,actual_input:&[u8],a:&SettingAdmission<'_>)->io::Result<MacroText>{poll(a)?;let mut bytes=MacroRows::new(a)?;facts.visit_value_bytes(actual_input,|chunk|bytes.extend_from_slice(chunk,a))??;decode(bytes.as_slice(),a)}
#[cfg(test)]mod tests{
 use super::*;use dm_syntax::{OriginalQuotedFrame,OriginalQuotedStep,NativeLexicalPurpose,NativeTokenCursor,NativeTokenStep};use std::sync::{atomic::{Ordering}};
 #[test]fn actual_quote_facts_keep_whole_token_utf8_or_latin1_bom_and_exceptional_raw_delimiter(){
  let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,1<<20,&||Ok(()));
  let cases:Vec<(&[u8],&str)>=vec![(b"\"\xce\xb1\"","α"),(b"\"\xce\xb1\xff\"","Î±ÿ"),(b"\"\x80\x91\"","\u{80}\u{91}"),(b"\"\xef\xbb\xbftext\"","\u{feff}text"),("@αbodyα".as_bytes(),"±body")];for(input,wanted)in cases{let mut frame=OriginalQuotedFrame::start_using(input,0,&a).unwrap().unwrap();let OriginalQuotedStep::Part(part)=frame.next_using(input,true,&a).unwrap()else{panic!("actual issued part")};let value=quoted_value_using(&part,&a).unwrap();assert_eq!(value.text.as_str(),wanted);assert!(value.lexical.is_ok());}
  assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]fn actual_unterminated_recovery_preserves_exact_old_value_without_inventing_inner_splice_error(){let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let input=b"\"text\\";let mut frame=OriginalQuotedFrame::start_using(input,0,&a).unwrap().unwrap();let OriginalQuotedStep::LexicalFailure{message,recovery}=frame.next_using(input,true,&a).unwrap()else{panic!("actual raw lexical failure")};assert_eq!(message,"unterminated string literal");let value=quoted_value_using(&recovery,&a).unwrap();assert_eq!(value.text.as_str(),"text");assert!(value.lexical.is_ok(),"actual quote issuer excludes terminal unpushed backslash from recovered value");drop((value,frame));assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());}
 #[test]fn actual_doc_comment_fact_is_decoded_once_with_original_kind_and_no_future_token_demand(){let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let cases:Vec<(&[u8],Option<&str>)>=vec![(b"///\xce\xb1\xff\nTOO_FEW(1)",Some("Î±ÿ")),(b"/*ordinary*/ TOO_FEW(1)",None)];for(input,wanted)in cases{let mut cursor=NativeTokenCursor::for_purpose(NativeLexicalPurpose::Original0290Macro);let NativeTokenStep::Token(_)=cursor.peek_bytes_available_using(input,true,&a,|_,_,_|panic!("no future lexical demand")).unwrap()else{panic!("actual comment token")};let facts=cursor.original_comment_facts().unwrap();let value=comment_value_using(facts,input,&a).unwrap();assert_eq!(value.as_ref().map(MacroText::as_str),wanted);cursor.commit_peek().unwrap();}assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());}
 #[test]fn first_io_or_quota_before_value_growth_remains_typed_and_same_resource_domain_recovers(){let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let good=SettingAdmission::new(&used,1<<20,&||Ok(()));let input=b"\"\xffdata\"";let mut frame=OriginalQuotedFrame::start_using(input,0,&good).unwrap().unwrap();let OriginalQuotedStep::Part(part)=frame.next_using(input,true,&good).unwrap()else{panic!("actual part")};let fail=||Err(io::Error::from_raw_os_error(1450));let bad=SettingAdmission::new(&used,1<<20,&fail);assert_eq!(quoted_value_using(&part,&bad).err().unwrap().raw_os_error(),Some(1450));let tiny=SettingAdmission::new(&used,dm_syntax::SettingChargeCounter::root_allocation_bytes() + (1),&||Ok(()));assert_eq!(quoted_value_using(&part,&tiny).err().unwrap().kind(),io::ErrorKind::OutOfMemory);let value=quoted_value_using(&part,&good).unwrap();assert_eq!(value.text.as_str(),"ÿdata");drop((value,frame));assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());}
 #[test]fn actual_resource_facts_preserve_single_byte_escape_and_whole_token_latin1_recovery(){let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let cases:Vec<(&[u8],&str,bool)>=vec![(b"'a\\nb'","anb",false),(b"'\xce\xb1\xff'","Î±ÿ",false),(b"'\xef\xbb\xbftext'","\u{feff}text",false),(b"'a\\","a",true)];for(input,wanted,recovery)in cases{let mut cursor=NativeTokenCursor::for_purpose(NativeLexicalPurpose::Original0290Macro);let mut notices=0;let NativeTokenStep::Token(_)=cursor.peek_bytes_available_using(input,true,&a,|_,_,_|{notices+=1;true}).unwrap()else{panic!("actual resource event")};let facts=cursor.original_resource_facts().unwrap();assert_eq!(facts.recovering(),recovery);let value=resource_value_using(facts,input,&a).unwrap();assert_eq!(value.as_str(),wanted);assert_eq!(notices,usize::from(recovery));cursor.commit_peek().unwrap();}assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());}
 #[test]fn actual_unterminated_block_quote_recovery_excludes_held_partial_terminator_exactly_as_old_buf(){let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let input=b"{\"text\"";let mut frame=OriginalQuotedFrame::start_using(input,0,&a).unwrap().unwrap();let OriginalQuotedStep::LexicalFailure{message,recovery}=frame.next_using(input,true,&a).unwrap()else{panic!("actual unclosed block quote")};assert_eq!(message,"unterminated string literal");let value=quoted_value_using(&recovery,&a).unwrap();assert_eq!(value.text.as_str(),"text");assert!(value.lexical.is_ok());drop((value,frame));assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());}
}

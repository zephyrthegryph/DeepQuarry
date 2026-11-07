//! Scalar DATA transport over tokens already issued by the SAME native lexer.
//! Pinned punctuation DATA from SpacemanDMM0290db5c752fa292f9824521515b603a2afd11dc,
//! GPL-3.0, Tad Hardesty and SpacemanDMM contributors; same canonical native table.
//! Does not read files, create source/model receipts, or parse another token stream.
use crate::{Span,SpanToken,TokenKind,SettingAdmission};
use std::io;
/// Exact pinned PUNCT_TABLE scalar spellings, preserving maximal-munch grammar.
/// This is the ONE full non-keyword pinned table. Quote/comment/whitespace
/// alternatives also matter for actual lookahead/read-point issuance even when
/// their values are handled by the SAME retained quote/comment state. Keyword
/// `in` is classified by the actual identifier branch, never read_punct.
struct PunctuationRow{spelling:&'static str,debug:&'static str,closed:Option<&'static str>}
const ORIGINAL_PUNCTUATION:&[PunctuationRow]=&[
 PunctuationRow{spelling:"\t",debug:"Tab",closed:None},
 PunctuationRow{spelling:"\n",debug:"Newline",closed:None},
 PunctuationRow{spelling:" ",debug:"Space",closed:None},
 PunctuationRow{spelling:"!",debug:"Not",closed:None},
 PunctuationRow{spelling:"!=",debug:"NotEq",closed:None},
 PunctuationRow{spelling:"\"",debug:"DoubleQuote",closed:None},
 PunctuationRow{spelling:"#",debug:"Hash",closed:None},
 PunctuationRow{spelling:"##",debug:"TokenPaste",closed:None},
 PunctuationRow{spelling:"%",debug:"Mod",closed:None},
 PunctuationRow{spelling:"%%",debug:"FloatMod",closed:None},
 PunctuationRow{spelling:"%%=",debug:"FloatModAssign",closed:None},
 PunctuationRow{spelling:"%=",debug:"ModAssign",closed:None},
 PunctuationRow{spelling:"&",debug:"BitAnd",closed:None},
 PunctuationRow{spelling:"&&",debug:"And",closed:None},
 PunctuationRow{spelling:"&&=",debug:"AndAssign",closed:None},
 PunctuationRow{spelling:"&=",debug:"BitAndAssign",closed:None},
 PunctuationRow{spelling:"'",debug:"SingleQuote",closed:None},
 PunctuationRow{spelling:"(",debug:"LParen",closed:None},
 PunctuationRow{spelling:")",debug:"RParen",closed:None},
 PunctuationRow{spelling:"*",debug:"Mul",closed:None},
 PunctuationRow{spelling:"**",debug:"Pow",closed:None},
 PunctuationRow{spelling:"*=",debug:"MulAssign",closed:None},
 PunctuationRow{spelling:"+",debug:"Add",closed:None},
 PunctuationRow{spelling:"++",debug:"PlusPlus",closed:None},
 PunctuationRow{spelling:"+=",debug:"AddAssign",closed:None},
 PunctuationRow{spelling:",",debug:"Comma",closed:None},
 PunctuationRow{spelling:"-",debug:"Sub",closed:None},
 PunctuationRow{spelling:"--",debug:"MinusMinus",closed:None},
 PunctuationRow{spelling:"-=",debug:"SubAssign",closed:None},
 PunctuationRow{spelling:".",debug:"Dot",closed:None},
 PunctuationRow{spelling:"..",debug:"Super",closed:None},
 PunctuationRow{spelling:"...",debug:"Ellipsis",closed:None},
 PunctuationRow{spelling:"/",debug:"Slash",closed:None},
 PunctuationRow{spelling:"/*",debug:"BlockComment",closed:None},
 PunctuationRow{spelling:"//",debug:"LineComment",closed:None},
 PunctuationRow{spelling:"/=",debug:"DivAssign",closed:None},
 PunctuationRow{spelling:":",debug:"Colon",closed:Some("CloseColon")},
 PunctuationRow{spelling:"::",debug:"Scope",closed:None},
 PunctuationRow{spelling:":=",debug:"AssignInto",closed:None},
 PunctuationRow{spelling:";",debug:"Semicolon",closed:None},
 PunctuationRow{spelling:"<",debug:"Less",closed:None},
 PunctuationRow{spelling:"<<",debug:"LShift",closed:None},
 PunctuationRow{spelling:"<<=",debug:"LShiftAssign",closed:None},
 PunctuationRow{spelling:"<=",debug:"LessEq",closed:None},
 PunctuationRow{spelling:"<=>",debug:"LessOrGreater",closed:None},
 PunctuationRow{spelling:"<>",debug:"LessGreater",closed:None},
 PunctuationRow{spelling:"=",debug:"Assign",closed:None},
 PunctuationRow{spelling:"==",debug:"Eq",closed:None},
 PunctuationRow{spelling:">",debug:"Greater",closed:None},
 PunctuationRow{spelling:">=",debug:"GreaterEq",closed:None},
 PunctuationRow{spelling:">>",debug:"RShift",closed:None},
 PunctuationRow{spelling:">>=",debug:"RShiftAssign",closed:None},
 PunctuationRow{spelling:"?",debug:"QuestionMark",closed:None},
 PunctuationRow{spelling:"?.",debug:"SafeDot",closed:None},
 PunctuationRow{spelling:"?:",debug:"SafeColon",closed:None},
 PunctuationRow{spelling:"?[",debug:"SafeLBracket",closed:None},
 PunctuationRow{spelling:"[",debug:"LBracket",closed:None},
 PunctuationRow{spelling:"]",debug:"RBracket",closed:None},
 PunctuationRow{spelling:"^",debug:"BitXor",closed:None},
 PunctuationRow{spelling:"^=",debug:"BitXorAssign",closed:None},
 PunctuationRow{spelling:"{",debug:"LBrace",closed:None},
 PunctuationRow{spelling:"{\"",debug:"BlockString",closed:None},
 PunctuationRow{spelling:"|",debug:"BitOr",closed:None},
 PunctuationRow{spelling:"|=",debug:"BitOrAssign",closed:None},
 PunctuationRow{spelling:"||",debug:"Or",closed:None},
 PunctuationRow{spelling:"||=",debug:"OrAssign",closed:None},
 PunctuationRow{spelling:"}",debug:"RBrace",closed:None},
 PunctuationRow{spelling:"~",debug:"BitNot",closed:None},
 PunctuationRow{spelling:"~!",debug:"NotEquiv",closed:None},
 PunctuationRow{spelling:"~=",debug:"Equiv",closed:None},
 // Genuine identifier producer maps this keyword; never read_punct.
 PunctuationRow{spelling:"in",debug:"In",closed:None},
];
const ORIGINAL_LEXICAL_PUNCTUATION_LEN:usize=ORIGINAL_PUNCTUATION.len()-1;

/// In-memory storage index for the exact spelling of an already issued
/// punctuation value. No source read, token classification or grant.
pub fn original_punctuation_storage_index(spelling: &str) -> Option<u8> {
    let ordinal = if spelling == "in" {
        ORIGINAL_LEXICAL_PUNCTUATION_LEN
    } else {
        ORIGINAL_PUNCTUATION[..ORIGINAL_LEXICAL_PUNCTUATION_LEN]
            .binary_search_by(|row| row.spelling.cmp(spelling)).ok()?
    };
    u8::try_from(ordinal).ok()
}

/// Exact inverse over the same static punctuation roster. Storage indices
/// are process-local DATA and are never serialized or inferred from raw bytes.
pub fn original_punctuation_storage_value(index: u8) -> Option<&'static str> {
    ORIGINAL_PUNCTUATION.get(usize::from(index)).map(|row| row.spelling)
}

#[cfg(test)]
#[test]
fn original_punctuation_storage_round_trips_the_entire_canonical_roster() {
    for (ordinal, row) in ORIGINAL_PUNCTUATION.iter().enumerate() {
        let index = original_punctuation_storage_index(row.spelling).unwrap();
        assert_eq!(usize::from(index), ordinal);
        assert_eq!(original_punctuation_storage_value(index), Some(row.spelling));
    }
    for spelling in ["", "unknown", "??", "IN", ":::", " in"] {
        assert_eq!(original_punctuation_storage_index(spelling), None);
    }
    assert_eq!(original_punctuation_storage_value(u8::MAX), None);
}

/// Exact derived-Debug variant name from the SAME canonical punctuation row.
/// No token recognition or source/provenance grant; close is actual lexer DATA.
pub fn original_punctuation_debug_name(spelling:&str,closed:bool)->Option<&'static str>{
 let row=ORIGINAL_PUNCTUATION.iter().find(|row|row.spelling==spelling)?;
 if closed{row.closed}else{Some(row.debug)}
}
/// Read-only candidate DATA over the SAME table, not another scanner. Actual
/// native cursor owns each read/putback and chooses when to ask for a prefix;
/// this helper never reads input, advances a cursor, allocates, or issues facts.
#[derive(Clone,Copy,Debug)]pub(crate) struct OriginalPunctuationCandidates{first:usize,end:usize}
impl OriginalPunctuationCandidates{
 pub(crate) fn for_first_using(byte:u8,a:&SettingAdmission<'_>)->io::Result<Self>{Self{first:0,end:ORIGINAL_LEXICAL_PUNCTUATION_LEN}.narrowed_using(&[byte],a)}
 pub(crate) fn len(self)->usize{self.end-self.first}
 pub(crate) fn is_empty(self)->bool{self.first==self.end}
 /// Pinned read_punct tests the FIRST candidate for exact equality before it
 /// decides whether more than one alternative requires another actual byte.
 pub(crate) fn exact(self,prefix:&[u8])->Option<&'static str>{ORIGINAL_PUNCTUATION.get(self.first).filter(|_|!self.is_empty()).map(|row|row.spelling).filter(|s|s.as_bytes()==prefix)}
 pub(crate) fn narrowed_using(self,prefix:&[u8],a:&SettingAdmission<'_>)->io::Result<Self>{
  a.checkpoint().map_err(|e|actual(a,e))?;let mut first=None;let mut end=self.first;
  for index in self.first..self.end{a.checkpoint().map_err(|e|actual(a,e))?;if ORIGINAL_PUNCTUATION[index].spelling.as_bytes().starts_with(prefix){first.get_or_insert(index);end=index+1;}else if first.is_some(){break}}
  Ok(first.map_or(Self{first:self.end,end:self.end},|first|Self{first,end}))
 }
}

/// Kind of an ALREADY issued Original punctuation spelling. This is the
/// same producer decision used by the native cursor; it reads no source.
pub fn original_punctuation_native_kind(spelling:&str)->TokenKind{if spelling=="\n"{return TokenKind::Newline}if matches!(spelling," "|"\t"){return TokenKind::Whitespace}if !spelling.is_empty()&&spelling.bytes().all(|b|b"+-*%=!<>|&^~".contains(&b)){TokenKind::Operator}else{TokenKind::Punctuation}}

fn actual(a:&SettingAdmission<'_>,error:io::Error)->io::Error{a.take_operational_error().unwrap_or(error)}
/// Expected group boundary only: the actual native cursor must commit each
/// contiguous already-issued member before returning this grouped token. This
/// helper never consumes/recognizes the following token or fabricates a cursor.
pub fn original_punctuation_boundary_using(source:&str,first:SpanToken,a:&SettingAdmission<'_>)->io::Result<Option<(&'static str,Span)>>{
 a.checkpoint().map_err(|e|actual(a,e))?;
 if !matches!(first.kind,TokenKind::Punctuation|TokenKind::Operator){return Ok(None)}
 let Some(raw)=source.get(first.span.start..)else{return Err(io::ErrorKind::InvalidInput.into())};
 let Some(first_text)=source.get(first.span.range())else{return Err(io::ErrorKind::InvalidInput.into())};
 if first_text.chars().count()!=1{return Err(io::ErrorKind::InvalidInput.into())}
 let mut best=None;for row in &ORIGINAL_PUNCTUATION[..ORIGINAL_LEXICAL_PUNCTUATION_LEN]{let punct=row.spelling;a.checkpoint().map_err(|e|actual(a,e))?;if raw.starts_with(punct)&&best.is_none_or(|old:&str|punct.len()>old.len()){best=Some(punct)}}
 Ok(best.map(|punct|(punct,Span::new(first.span.start,first.span.start+punct.len()))))
}
#[derive(Clone,Copy,Debug,PartialEq)]pub enum OriginalScalarNumber{Integer(i32),Float(f32)}
/// Original valid-scalar DATA only. Genuine invalid-number diagnostic/recovery
/// tokens are separately unissued; this MUST NOT become model/body None.
#[derive(Clone,Copy,Debug,PartialEq,Eq)]pub enum OriginalScalarUnavailable{NotOneNativeNumericToken,OriginalNumericRecoveryNotIssued,OriginalNumericNoticeNotIssued}
pub fn original_scalar_number_using(source:&str,token:SpanToken,a:&SettingAdmission<'_>)->io::Result<Result<OriginalScalarNumber,OriginalScalarUnavailable>>{
 a.checkpoint().map_err(|e|actual(a,e))?;
 if token.kind!=TokenKind::Number{return Ok(Err(OriginalScalarUnavailable::NotOneNativeNumericToken))}
 let raw=source.get(token.span.range()).ok_or(io::ErrorKind::InvalidInput)?;
 // SAME numeric_form normalization+diagnostic scratch, funded before its
 // existing allocations. Its temporary strings die before this root credit.
 // raw debug escaping <=6x plus normalized and radix-prefix copies; 8x+512
 // covers their true overlap, never changes any host cap.
 let bytes=raw.len().checked_mul(8).and_then(|n|n.checked_add(512)).ok_or(io::ErrorKind::OutOfMemory)?;
 let _scratch=a.reserve(bytes).map_err(|e|actual(a,e))?;
 let form=match crate::numeric_form::numeric_form(raw){Ok(form)=>form,Err(_)=>return Ok(Err(OriginalScalarUnavailable::OriginalNumericRecoveryNotIssued))};
 let value=match form{crate::numeric_form::NumericForm::Integer(n)=>OriginalScalarNumber::Integer(n),crate::numeric_form::NumericForm::Float=>{let normalized:String=raw.chars().filter(|ch|*ch!='_').collect();let n=if normalized.ends_with("#INF"){f32::INFINITY}else if normalized.ends_with("#IND"){f32::NAN}else{match normalized.parse::<f32>(){Ok(n)=>n,Err(_)=>return Ok(Err(OriginalScalarUnavailable::OriginalNumericRecoveryNotIssued))}};if normalized.bytes().all(|b|b.is_ascii_digit())&&n.to_string()!=normalized{return Ok(Err(OriginalScalarUnavailable::OriginalNumericNoticeNotIssued))}OriginalScalarNumber::Float(n)}};
 a.checkpoint().map_err(|e|actual(a,e))?;Ok(Ok(value))
}
/// SAME old Token Display rule: even Int tokens display through FormatFloat.
/// Paste separately consumes Integer(i32), NOT this rounded display spelling.
pub fn write_original_scalar_number(value:OriginalScalarNumber,out:&mut impl std::fmt::Write)->std::fmt::Result{crate::numeric_form::write_original_float(match value{OriginalScalarNumber::Integer(n)=>n as f32,OriginalScalarNumber::Float(n)=>n},out)}
#[cfg(test)]mod tests{
 use super::*;use std::sync::{atomic::{Ordering}};
 #[test]fn exact_old_punctuation_transport_groups_only_adjoining_native_tokens_and_does_not_look_past_group(){let c=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&c,4096,&||Ok(()));for(raw,wanted)in[("&&= later","&&="),("...bad","..."),("<=>x","<=>"),("##x","##"),("? .","?"),("~=x","~="),("[bad","["),("+ \"bad","+")]{let first=crate::lex_spans(&raw[..raw.chars().next().unwrap().len_utf8()]).tokens[0];let(punct,span)=original_punctuation_boundary_using(raw,first,&a).unwrap().unwrap();assert_eq!(punct,wanted);assert_eq!(&raw[span.range()],wanted);}assert_eq!(c.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());}
 #[test]fn actual_scalar_values_preserve_int_float_paste_distinction_and_failure_credit(){let c=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&c,4096,&||Ok(()));for(raw,wanted)in[("0144",OriginalScalarNumber::Integer(100)),("0x64",OriginalScalarNumber::Integer(100)),("2147483647",OriginalScalarNumber::Integer(i32::MAX)),("1.0",OriginalScalarNumber::Float(1.0))]{let token=crate::lex_spans(raw).tokens[0];assert_eq!(original_scalar_number_using(raw,token,&a).unwrap(),Ok(wanted));assert_eq!(c.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());}let overflow="2147483648";assert_eq!(original_scalar_number_using(overflow,crate::lex_spans(overflow).tokens[0],&a).unwrap(),Err(OriginalScalarUnavailable::OriginalNumericNoticeNotIssued));let bad="08";assert_eq!(original_scalar_number_using(bad,crate::lex_spans(bad).tokens[0],&a).unwrap(),Err(OriginalScalarUnavailable::OriginalNumericRecoveryNotIssued));assert_eq!(c.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());let fault=||Err(io::Error::from_raw_os_error(1450));let a=SettingAdmission::new(&c,4096,&fault);assert_eq!(original_scalar_number_using("1",crate::lex_spans("1").tokens[0],&a).unwrap_err().raw_os_error(),Some(1450));assert_eq!(c.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());}
}

#[cfg(test)]mod actual_original_punctuation_candidates_tests{
 use super::*;use std::sync::{atomic::{Ordering}};
 fn driven(input:&[u8],a:&SettingAdmission<'_>)->(Option<&'static str>,usize,Option<u8>,bool){let first=input[0];let mut at=1;let mut candidates=OriginalPunctuationCandidates::for_first_using(first,a).unwrap();let mut needle=[0u8;8];needle[0]=first;let mut len=1;let mut matched=None;let mut putback=None;let mut eof=false;while !candidates.is_empty(){if let Some(value)=candidates.exact(&needle[..len]){matched=Some(value)}if candidates.len()==1{return(matched,at,putback,eof)}match input.get(at){Some(&byte)=>{at+=1;needle[len]=byte;len+=1;},None=>{eof=true;return(matched,at,putback,eof)}}candidates=candidates.narrowed_using(&needle[..len],a).unwrap();}if len>1{putback=Some(needle[len-1]);}(matched,at,putback,eof)}
 #[test]fn one_table_preserves_actual_lookahead_only_quote_comment_candidates_and_putback_frontier(){let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,4096,&||Ok(()));let cases:Vec<(&[u8],Option<&str>,usize,Option<u8>,bool)>=vec![(b"{X",Some("{"),2,Some(b'X'),false),(b"{",Some("{"),1,None,true),(b"{\"X",Some("{\""),2,None,false),(b"/X",Some("/"),2,Some(b'X'),false),(b"/*X",Some("/*"),2,None,false),(b"//X",Some("//"),2,None,false),(b"<=>X",Some("<=>"),3,None,false),(b"\tX",Some("\t"),1,None,false),(b"iX",None,1,None,false)];for(input,matched,read,putback,eof)in cases{assert_eq!(driven(input,&a),(matched,read,putback,eof));}assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());}
 #[test]fn candidate_filter_first_io_is_typed_and_same_operation_recovers_without_allocation(){let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let fail=||Err(io::Error::from_raw_os_error(1450));let bad=SettingAdmission::new(&used,4096,&fail);assert_eq!(OriginalPunctuationCandidates::for_first_using(b'/',&bad).unwrap_err().raw_os_error(),Some(1450));let good=SettingAdmission::new(&used,4096,&||Ok(()));assert_eq!(OriginalPunctuationCandidates::for_first_using(b'/',&good).unwrap().exact(b"/"),Some("/"));assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());}
}

#[cfg(test)]mod native_punctuation_kind_controls{
 use super::*;use std::sync::{atomic::{Ordering}};
 #[test]fn already_issued_punctuation_projection_reuses_actual_original_cursor_operator_kind(){
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,1<<20,&||Ok(()));for spelling in ["!","~","-","+","*","&","&&","||","%","%%","**",">>=","!=","(",")","[","]","/","::","?",",",";"]{let mut cursor=crate::NativeTokenCursor::for_original_source_bytes(spelling.as_bytes());let crate::NativeTokenStep::Token(token)=cursor.next_bytes_available_using(spelling.as_bytes(),true,&a,|_,_,_|panic!("valid punctuation")).unwrap()else{panic!("one real token")};assert_eq!(token.span,Span::new(0,spelling.len()),"{spelling}");assert_eq!(original_punctuation_native_kind(spelling),token.kind,"{spelling}");}assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
}

#[cfg(test)]mod original_physical_line_head_control{
 use super::*;use std::sync::{atomic::{Ordering}};
 #[test]fn actual_original_newline_restores_line_head_and_preserves_each_indentation_token(){let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let raw=b"p()\n    return A\n";let mut cursor=crate::NativeTokenCursor::for_original_source_bytes(raw);let mut indent=Vec::new();loop{match cursor.next_bytes_available_using(raw,true,&a,|_,_,_|panic!("valid physical source")).unwrap(){crate::NativeTokenStep::Token(token)=>{if token.kind==TokenKind::Whitespace{indent.push(token.span)}if &raw[token.span.range()]==b"\n"{assert_eq!(token.kind,TokenKind::Newline)}},crate::NativeTokenStep::End=>break,_=>panic!("complete physical source")}}assert_eq!(indent,[Span::new(4,5),Span::new(5,6),Span::new(6,7),Span::new(7,8)]);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());}
}

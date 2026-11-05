//! Pure shared formatting over ALREADY authenticated parser failure DATA.
//! These functions issue no token/source/parser/EOF grant and allocate nothing;
//! the caller keeps its real input/root loan and funded output writer alive.
use crate::{OriginalInputExpected,OriginalTokenValue};use std::fmt;
fn head(out:&mut dyn fmt::Write,actual:Option<OriginalTokenValue<&str>>)->fmt::Result{match actual{Some(value)=>{out.write_str("got '")?;value.write_display(out)?;out.write_str("', expected one of: ")},None=>out.write_str("got EOF, expected one of: ")}}
pub fn write_original_input_failure(out:&mut dyn fmt::Write,actual:Option<OriginalTokenValue<&str>>,expected:OriginalInputExpected)->fmt::Result{head(out,actual)?;out.write_str(match expected{OriginalInputExpected::ParenOrIdentifier=>"'(', identifier",OriginalInputExpected::Identifier=>"identifier",OriginalInputExpected::RightParen=>"')'",OriginalInputExpected::EmptyPickArm=>""})}
/// Pinned parser group() records operator before term() records these three
/// categories. Caller must authenticate the actual expected-term branch; this
/// is never a fallback classifier for arbitrary native syntax diagnostic text.
pub fn write_original_term_failure(out:&mut dyn fmt::Write,actual:Option<OriginalTokenValue<&str>>)->fmt::Result{head(out,actual)?;out.write_str("operator, literal, variable, proc call")}
#[cfg(test)]mod tests{use super::*;#[test]fn actual_typed_expected_messages_share_value_display_and_distinguish_real_eof(){let mut text=String::new();write_original_input_failure(&mut text,Some(OriginalTokenValue::Int(9)),OriginalInputExpected::Identifier).unwrap();assert_eq!(text,"got '9', expected one of: identifier");text.clear();write_original_term_failure(&mut text,None).unwrap();assert_eq!(text,"got EOF, expected one of: operator, literal, variable, proc call");}}

/// Pinned group()/arguments()/ternary expected sequence, issued only by the
/// corresponding actual Original Pratt consuming branch.
pub fn write_original_delimiter_failure(out:&mut dyn fmt::Write,actual:Option<OriginalTokenValue<&str>>,expected:crate::NativeDelimiterExpected)->fmt::Result{head(out,actual)?;out.write_str(match expected{crate::NativeDelimiterExpected::GroupRightParen=>"operator, field access, ')'",crate::NativeDelimiterExpected::ConditionalColon=>"operator, field access, ':'",crate::NativeDelimiterExpected::EmptyCall=>"')', ',', operator, literal, variable, proc call",crate::NativeDelimiterExpected::CallArgumentEnd=>"operator, field access, ')', ','",crate::NativeDelimiterExpected::IndexRightBracket=>"operator, field access, ']'",crate::NativeDelimiterExpected::Identifier=>"identifier"})}

//! Lexical number shape, distinct from the runtime floating-point value.
//!
//! Int-vs-Float rules follow SpacemanDMM dreammaker lexer.rs at
//! 0290db5c752fa292f9824521515b603a2afd11dc (GPL-3.0). Invalid spellings fail;
//! the reference lexer's error-recovery Int(0) is not an authoritative fact.

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NumericForm {
    Integer(i32),
    Float,
}

/// Classify one compiler-issued numeric literal token, without evaluating an
/// expression or rounding a floating-point value into an integer.
pub fn numeric_form(raw: &str) -> Result<NumericForm, String> {
    let text: String = raw.chars().filter(|c| *c != '_').collect();
    let invalid = || format!("unsupported or invalid numeric literal {raw:?}");
    if text.is_empty() || !matches!(text.as_bytes()[0], b'0'..=b'9' | b'.') {
        return Err(invalid());
    }
    if let Some(digits) = text.strip_prefix("0x") {
        if digits.is_empty() || !digits.bytes().all(|c| c.is_ascii_hexdigit()) {
            return Err(invalid());
        }
        let buffer=format!("0{digits}");
        return match original_number_value_core(&buffer,true,16){OriginalNumberOutcome{value:OriginalNumber::Integer(n),notice:None}=>Ok(NumericForm::Integer(n)),_=>Err(invalid())};
    }
    if text.contains('#') {
        let (prefix, suffix) = text.split_once('#').ok_or_else(invalid)?;
        return if matches!(suffix, "INF" | "IND")
            && !prefix.is_empty()
            && numeric_form(prefix.trim_end_matches('.')).is_ok()
        {
            Ok(NumericForm::Float)
        } else {
            Err(invalid())
        };
    }
    if text.bytes().any(|c| matches!(c, b'.' | b'e' | b'E')) {
        // Parsing validates spelling only; no policy receives the rounded value.
        return match original_number_value_core(&text,false,10){OriginalNumberOutcome{notice:None,..}=>Ok(NumericForm::Float),_=>Err(invalid())};
    }
    if !text.bytes().all(|c| c.is_ascii_digit()) {
        return Err(invalid());
    }
    let radix = if text.starts_with('0') { 8 } else { 10 };
    match original_number_value_core(&text,true,radix){
        OriginalNumberOutcome{value:OriginalNumber::Integer(n),notice:None}=>Ok(NumericForm::Integer(n)),
        OriginalNumberOutcome{value:OriginalNumber::Float(_),notice:None|Some(OriginalNumberNotice::PrecisionLoss{..})}=>Ok(NumericForm::Float),
        _=>Err(invalid()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn integer_shape_is_lexical_not_rounded() {
        for (raw, expected) in [
            ("0", 0),
            ("1", 1),
            ("01", 1),
            ("0144", 100),
            ("0x64", 100),
            ("1_00", 100),
            ("2147483647", i32::MAX),
        ] {
            assert_eq!(
                numeric_form(raw),
                Ok(NumericForm::Integer(expected)),
                "{raw}"
            );
        }
        for raw in [
            "1.0",
            "1e0",
            ".1",
            "2147483648",
            "1.#INF",
            "1.#IND",
            "2.#INF",
        ] {
            assert_eq!(numeric_form(raw), Ok(NumericForm::Float), "{raw}");
        }
    }

    #[test]
    fn malformed_or_expression_spellings_are_not_recovery_facts() {
        for raw in [
            "",
            "-1",
            "+1",
            "08",
            "0x",
            "0x80000000",
            "1+1",
            "1e",
            "nan",
            "0X1",
        ] {
            assert!(numeric_form(raw).is_err(), "{raw}");
        }
    }
}

/// SAME pinned lexer::FormatFloat body formerly owned by the checker Debug
/// consumer. Formatting DATA only, never numeric-token or source authority.
pub fn write_original_float(n:f32,out:&mut impl std::fmt::Write)->std::fmt::Result{if n.is_nan(){out.write_str(if n.is_sign_negative(){"-1.#IND"}else{"1.#IND"})}else if n.is_infinite(){out.write_str(if n.is_sign_negative(){"-1.#INF"}else{"1.#INF"})}else if n==0.0{out.write_str("0")}else{let exp=n.abs().log10().floor();let factor=10.0f32.powf(5.0-exp);if exp>=6.0||exp<=-5.0{let n2=(n*factor).round()*1.0e-5;let mut precision=0;while precision<5&&(n2*10.0f32.powi(precision))!=(n2*10.0f32.powi(precision)).round(){precision+=1;}write!(out,"{:.*}e{:+04}",precision as usize,n2,exp)}else{let n2=(n*factor).round()/factor;write!(out,"{n2}")}}}

#[cfg(test)]mod original_float_display_tests{
 use super::*;
 #[test]fn pinned_float_display_preserves_signed_zero_specials_and_six_digit_thresholds(){
  for(value,wanted)in[(0.0,"0"),(-0.0,"0"),(1.0,"1"),(-1.0,"-1"),(1_000_000.0,"1e+006"),(0.00001,"1e-005"),(f32::INFINITY,"1.#INF"),(f32::NEG_INFINITY,"-1.#INF"),(f32::from_bits(0x7fc00000),"1.#IND"),(f32::from_bits(0xffc00000),"-1.#IND")]{let mut out=String::new();write_original_float(value,&mut out).unwrap();assert_eq!(out,wanted,"bits {:08x}",value.to_bits());}
 }
 #[test]fn actual_output_refusal_stops_same_formatter_without_a_second_write(){struct Deny(usize);impl std::fmt::Write for Deny{fn write_str(&mut self,_:&str)->std::fmt::Result{self.0+=1;Err(std::fmt::Error)}}for n in [0.0,1.23456,1e20,f32::INFINITY,f32::NAN]{let mut out=Deny(0);assert!(write_original_float(n,&mut out).is_err());assert_eq!(out.0,1);}}
}

/// SAME pinned lexer read_number value/recovery judge over its actual issued
/// normalized buffer. Does NOT scan token boundaries or certify source identity.
#[derive(Clone,Copy,Debug,PartialEq)]pub enum OriginalNumber{Integer(i32),Float(f32)}
#[derive(Debug)]pub enum OriginalNumberNotice<'a>{
 PrecisionLoss{buffer:&'a str,value:f32},
 BadInteger{buffer:&'a str,radix:u32,error:std::num::ParseIntError},
 BadFloat{buffer:&'a str,error:std::num::ParseFloatError},
}
impl OriginalNumberNotice<'_>{
 pub fn is_warning(&self)->bool{matches!(self,Self::PrecisionLoss{..})}
 pub fn error_type(&self)->Option<&'static str>{matches!(self,Self::PrecisionLoss{..}).then_some("integer_precision_loss")}
 /// SAME original diagnostic text, written to actual caller-owned/funded sink.
 /// No untracked message String and no replacement of source diagnostic location.
 pub fn write_message(&self,out:&mut impl std::fmt::Write)->std::fmt::Result{match self{
  Self::PrecisionLoss{buffer,value}=>write!(out,"precision loss of integer constant: \"{buffer}\" to {value}"),
  Self::BadInteger{buffer,radix,error}=>write!(out,"bad base-{radix} integer \"{buffer}\": {error}"),
  Self::BadFloat{buffer,error}=>write!(out,"bad float \"{buffer}\": {error}"),
 }}
}
#[derive(Debug)]pub struct OriginalNumberOutcome<'a>{pub value:OriginalNumber,pub notice:Option<OriginalNumberNotice<'a>>}
/// Stream the SAME standard f32 Display comparison as old val.to_string()!=buf,
/// without allocating a second hidden String merely to compare its bytes.
fn original_number_display_equals(value:f32,buffer:&str)->bool{
 struct Compare<'a>{bytes:&'a[u8],at:usize,equal:bool}
 impl std::fmt::Write for Compare<'_>{fn write_str(&mut self,text:&str)->std::fmt::Result{let end=self.at.checked_add(text.len());self.equal&=end.is_some_and(|end|self.bytes.get(self.at..end)==Some(text.as_bytes()));self.at=end.unwrap_or(usize::MAX);Ok(())}}
 let mut out=Compare{bytes:buffer.as_bytes(),at:0,equal:true};let result=std::fmt::write(&mut out,format_args!("{value}"));debug_assert!(result.is_ok(),"the bounded comparison writer never refuses");result.is_ok()&&out.equal&&out.at==buffer.len()
}
fn original_number_value_core(buffer:&str,integer:bool,radix:u32)->OriginalNumberOutcome<'_>{
 if integer{
  let original_error=match i32::from_str_radix(buffer,radix){Ok(n)=>return OriginalNumberOutcome{value:OriginalNumber::Integer(n),notice:None},Err(error)=>error};
  if radix==10{if let Ok(value)=buffer.parse::<f32>(){let notice=(!original_number_display_equals(value,buffer)).then_some(OriginalNumberNotice::PrecisionLoss{buffer,value});return OriginalNumberOutcome{value:OriginalNumber::Float(value),notice}}}
  OriginalNumberOutcome{value:OriginalNumber::Integer(0),notice:Some(OriginalNumberNotice::BadInteger{buffer,radix,error:original_error})}
 }else{match buffer.parse::<f32>(){Ok(value)=>OriginalNumberOutcome{value:OriginalNumber::Float(value),notice:None},Err(error)=>OriginalNumberOutcome{value:OriginalNumber::Float(0.0),notice:Some(OriginalNumberNotice::BadFloat{buffer,error})}}}
}
/// Caller lends the actual canonical lexer's funded normalized buffer and its
/// issued integer/radix facts under SAME current byte/frame owner. A raw span or
/// arbitrary string is NOT that owner. Recovery/notice stays DATA until actual
/// source owner attaches authentic source location and ordered diagnostics.
pub fn original_number_value_using<'a>(buffer:&'a str,integer:bool,radix:u32,a:&crate::SettingAdmission<'_>)->std::io::Result<OriginalNumberOutcome<'a>>{
 let poll=||a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e));poll()?;
 if !matches!(radix,8|10|16){return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"original number facts have unissued radix"))}
 let value=original_number_value_core(buffer,integer,radix);poll()?;Ok(value)
}
#[cfg(test)]#[path="../../../fixtures/original_number_value.rs"]mod immutable_original_number_value;
#[cfg(test)]mod actual_original_number_value_tests{
 use super::*;use std::sync::{atomic::{Ordering}};
 #[test]fn shared_value_judge_matches_literal_pinned_old_body_for_valid_recovery_and_precision_notices(){let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&used,4096,&||Ok(()));for(integer,radix,buffer)in[(true,8,"0129"),(true,16,"0ff"),(true,16,"0"),(true,16,"0ffffffff"),(true,10,"2147483647"),(true,10,"2147483648"),(true,10,"999999999999999999999999999999999999999999999"),(true,10,"invalid"),(false,10,"1e+-2"),(false,10,"1.#I_"),(false,10,"1.#Ã"),(false,10,"1.0"),(false,10,"1e-2"),(false,10,"inf"),(false,10,"NaN")]{let old=immutable_original_number_value::observe(integer,radix,buffer);let actual=original_number_value_using(buffer,integer,radix,&a).unwrap();let bits=match actual.value{OriginalNumber::Integer(n)=>(true,n as u32),OriginalNumber::Float(n)=>(false,n.to_bits())};assert_eq!(bits,old.value,"{buffer}");let notice=actual.notice.as_ref().map(|notice|{let mut message=String::new();notice.write_message(&mut message).unwrap();(message,notice.is_warning(),notice.error_type().map(str::to_owned))});assert_eq!(notice,old.notice,"{buffer}");assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());}}
 #[test]fn first_actual_io_before_or_after_numeric_work_never_becomes_recovery_zero_or_silent_notice(){use std::cell::Cell;let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();for denial in [1,2]{let calls=Cell::new(0);let fault=||{calls.set(calls.get()+1);if calls.get()==denial{Err(std::io::Error::from_raw_os_error(1450))}else{Ok(())}};let a=crate::SettingAdmission::new(&used,4096,&fault);assert_eq!(original_number_value_using("08",true,8,&a).unwrap_err().raw_os_error(),Some(1450));assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());}let a=crate::SettingAdmission::new(&used,4096,&||Ok(()));let actual=original_number_value_using("08",true,8,&a).unwrap();assert_eq!(actual.value,OriginalNumber::Integer(0));assert!(matches!(actual.notice,Some(OriginalNumberNotice::BadInteger{..})));assert!(original_number_value_using("1",true,0,&a).is_err());}
}

//! Borrowed validation of the exclusive Derived report document. JSON remains
//! DATA: no model, hash, revision string or preparation tag admits a source.
use serde::{Deserialize,de::{DeserializeSeed,Visitor,SeqAccess}};
use serde_json::value::RawValue;
use std::{fmt,io::{self,Write}};
use super::admitted::Work;
fn invalid()->io::Error{io::Error::new(io::ErrorKind::InvalidData,"native Derived report is not complete/matching")}
fn hex(value:&str,width:usize)->bool{value.len()==width&&value.bytes().all(|b|b.is_ascii_digit()||(b'a'..=b'f').contains(&b))}
#[derive(Deserialize)]#[serde(deny_unknown_fields)]struct Failure<'a>{kind:FailureKind,#[serde(borrow)]message:&'a RawValue}
#[derive(Deserialize)]enum FailureKind{InvalidRequest,Source,Internal,Infrastructure,Cancelled}
#[derive(Deserialize)]#[serde(deny_unknown_fields)]struct Preparation<'a>{
 kind:&'a str,
 #[serde(default,borrow)]semantic_revision:Option<&'a str>,#[serde(default,borrow)]source_revision:Option<&'a str>,#[serde(default,borrow)]policy_revision:Option<&'a str>,
 #[serde(default,borrow)]failure:Option<Failure<'a>>,#[serde(default,borrow)]io_kind:Option<&'a str>,#[serde(default)]os_code:Option<i32>,
}
#[derive(Deserialize)]#[serde(deny_unknown_fields)]struct Document<'a>{schema:&'a str,complete:bool,full_policy_parity:bool,baseline:bool,clean:bool,#[serde(borrow)]preparation:Preparation<'a>,#[serde(borrow)]lints:[&'a str;1],#[serde(borrow)]text:&'a RawValue,#[serde(borrow)]allow_usage:&'a RawValue}
/// All fields borrow the SAME completed admitted document. Text/error messages
/// are serde-issued raw JSON loans, never decoded into another owned String.
pub struct Validated<'a>{document:Document<'a>}
impl Validated<'_>{pub fn clean(&self)->bool{self.document.clean}pub fn is_current(&self)->bool{self.document.preparation.kind=="current"}}
struct Allows<'output,'error>{output:Option<&'output mut dyn Write>,first:&'error mut Option<io::Error>}
impl<'de>DeserializeSeed<'de> for Allows<'_,'_>{type Value=();fn deserialize<D:serde::Deserializer<'de>>(self,d:D)->Result<(),D::Error>{d.deserialize_seq(self)}}
impl<'de>Visitor<'de> for Allows<'_,'_>{type Value=();fn expecting(&self,f:&mut fmt::Formatter<'_>)->fmt::Result{f.write_str("ordered exact Derived ALLOW tuples")}
 fn visit_seq<A:SeqAccess<'de>>(mut self,mut seq:A)->Result<(),A::Error>{let mut last:Option<(&'de str,&'de str,u32)>=None;while let Some(row)=seq.next_element::<(&'de str,&'de str,u32)>()?{if row.0!="derived_reads"||!hex(row.1,40)||row.2==0||last.is_some_and(|previous|previous>=row){return Err(serde::de::Error::custom("invalid or unordered Derived ALLOW row"))}if let Some(output)=self.output.as_deref_mut(){if self.first.is_none(){if let Err(first)=writeln!(output,"{}\t{}\t{}",row.0,row.1,row.2){*self.first=Some(first);return Err(serde::de::Error::custom("actual ALLOW output IO failed"))}}}last=Some(row)}Ok(())}
}
fn allows(raw:&RawValue,output:Option<&mut dyn Write>)->io::Result<()>{let mut first=None;let mut decoder=serde_json::Deserializer::from_str(raw.get());let result=Allows{output,first:&mut first}.deserialize(&mut decoder).and_then(|_|decoder.end());if let Some(first)=first{return Err(first)}result.map_err(io::Error::other)}
pub fn validate<'a>(bytes:&'a[u8],clean:bool,work:&dyn Work)->io::Result<Validated<'a>>{
 work.checkpoint()?;let bound=bytes.len().checked_mul(4).and_then(|n|n.checked_add(65_536)).ok_or_else(||work.overflow())?;work.temporary(0,bound)?;
 let document:Document<'a>=serde_json::from_slice(bytes).map_err(|_|invalid())?;
 if document.schema!="native-analyze-derived-report-v1"||!document.complete||document.full_policy_parity||document.baseline||document.clean!=clean||document.lints!=["derived_reads"]||!document.text.get().trim_start().starts_with('"'){return Err(invalid())}
 let p=&document.preparation;match p.kind{
  "current"=>{if !p.semantic_revision.is_some_and(|v|hex(v,32))||!p.source_revision.is_some_and(|v|hex(v,32))||!p.policy_revision.is_some_and(|v|hex(v,32))||p.failure.is_some()||p.io_kind.is_some()||p.os_code.is_some(){return Err(invalid())}},
  "failed_root_one_shot"=>{if p.semantic_revision.is_some()||p.source_revision.is_some()||p.policy_revision.is_some()||p.failure.as_ref().is_none_or(|f|!f.message.get().trim_start().starts_with('"')){return Err(invalid())}},
  _=>return Err(invalid()),
 }
 allows(document.allow_usage,None)?;Ok(Validated{document})
}
impl Validated<'_>{pub fn write_allow_usage(&self,output:&mut dyn Write)->io::Result<()>{allows(self.document.allow_usage,Some(output))}}

/// Same serde codec, borrowed schema probe only. It cannot admit source or a
/// family by itself; callers must run the complete exclusive validator next.
pub fn has_derived_schema(bytes:&[u8],work:&dyn Work)->io::Result<bool>{work.temporary(0,bytes.len().checked_mul(4).and_then(|n|n.checked_add(65_536)).ok_or_else(||work.overflow())?)?;#[derive(Deserialize)]struct Schema<'a>{schema:&'a str}let schema:Schema<'_>=serde_json::from_slice(bytes).map_err(|_|invalid())?;Ok(schema.schema=="native-analyze-derived-report-v1")}

#[cfg(test)]mod tests{
 use super::*;use std::cell::Cell;
 struct W{remaining:Cell<usize>,denied:Cell<bool>}impl Work for W{fn checkpoint(&self)->io::Result<()>{if self.denied.get(){Err(io::ErrorKind::OutOfMemory.into())}else{Ok(())}}fn reserve(&self,n:usize)->io::Result<()>{let Some(next)=self.remaining.get().checked_sub(n)else{return Err(self.overflow())};self.remaining.set(next);Ok(())}fn overflow(&self)->io::Error{self.denied.set(true);io::ErrorKind::OutOfMemory.into()}}
 fn work()->W{W{remaining:Cell::new(8*1024*1024),denied:Cell::new(false)}}
 fn wire(failed:bool)->Vec<u8>{let p=if failed{serde_json::json!({"kind":"failed_root_one_shot","failure":{"kind":"Infrastructure","message":"actual root failure\n"},"io_kind":"NotFound","os_code":2})}else{serde_json::json!({"kind":"current","semantic_revision":"a".repeat(32),"source_revision":"b".repeat(32),"policy_revision":"c".repeat(32)})};serde_json::to_vec(&serde_json::json!({"schema":"native-analyze-derived-report-v1","complete":true,"full_policy_parity":false,"baseline":false,"clean":false,"preparation":p,"lints":["derived_reads"],"text":"exact UTF8 α report\n","allow_usage":[["derived_reads","0123456789012345678901234567890123456789",2]]})).unwrap()}
 #[test]fn text_and_failed_message_are_same_borrowed_raw_value_not_a_decoded_report(){for failed in [false,true]{let bytes=wire(failed);let report=validate(&bytes,false,&work()).unwrap();let base=bytes.as_ptr()as usize;let text=report.document.text.get();assert!((base..base+bytes.len()).contains(&(text.as_ptr()as usize)));assert!(text.contains("\\n"));assert_eq!(report.is_current(),!failed);let mut rows=Vec::new();report.write_allow_usage(&mut rows).unwrap();assert_eq!(rows,b"derived_reads\t0123456789012345678901234567890123456789\t2\n");}}
 #[test]fn unknown_tags_fake_failed_revisions_and_foreign_allow_usage_refuse(){let bytes=wire(true);let original:serde_json::Value=serde_json::from_slice(&bytes).unwrap();for change in 0..6{let mut row=original.clone();match change{0=>row["preparation"]["semantic_revision"]="a".repeat(32).into(),1=>row["preparation"]["kind"]="foreign".into(),2=>row["lints"]=serde_json::json!(["scheduler"]),3=>row["allow_usage"]=serde_json::json!([["scheduler","0123456789012345678901234567890123456789",2]]),4=>row["allow_usage"]=serde_json::json!([["derived_reads","",2]]),_=>row["text"]=serde_json::json!([])}assert!(validate(&serde_json::to_vec(&row).unwrap(),false,&work()).is_err(),"change {change}");}}
 #[test]fn quota_is_before_decode_and_first_allow_sink_io_is_not_wrapped_or_retried(){let bytes=wire(false);let denied=W{remaining:Cell::new(0),denied:Cell::new(false)};assert_eq!(validate(&bytes,false,&denied).err().unwrap().kind(),io::ErrorKind::OutOfMemory);let report=validate(&bytes,false,&work()).unwrap();struct Failed(usize);impl Write for Failed{fn write(&mut self,_:&[u8])->io::Result<usize>{self.0+=1;Err(io::Error::from_raw_os_error(1450))}fn flush(&mut self)->io::Result<()>{Ok(())}}let mut failed=Failed(0);assert_eq!(report.write_allow_usage(&mut failed).unwrap_err().raw_os_error(),Some(1450));assert_eq!(failed.0,1);}
}

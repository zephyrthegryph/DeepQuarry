//! Admission of the shared utility child framing; no child or allowance owner.
//! Included privately below native_cli_client. Endpoints validate their own typed
//! request/terminal and keep the captured buffer and SAME work alive through use.
use super::NativeReportWork;
use crate::{report_work::Work,selected_exclusions_wire::{Seal,MAX_HEADER,MAX_STREAM}};
use serde::de::DeserializeOwned;
use std::io::{self,Write};
fn invalid(why:&'static str)->io::Error{io::Error::new(io::ErrorKind::InvalidData,why)}
pub(super) struct Admitted<'a,T>{pub(super) terminal:T,stderr:&'a[u8],stdout:&'a[u8],_work:&'a NativeReportWork}
impl<T>Admitted<'_,T>{
 pub(super) fn publish(self,stdout:&mut impl Write,stderr:&mut impl Write)->io::Result<T>{
  stderr.write_all(self.stderr)?;stdout.write_all(self.stdout)?;Ok(self.terminal)
 }
}
/// stderr is the backend process's operational channel, separate from the
/// terminal's sealed semantic stderr. An endpoint must handle incomplete exits
/// before admission (and emit its own unknown-commit diagnostic where needed).
pub(super) fn admit<'a,T:DeserializeOwned>(
 bytes:&'a[u8],operational_stderr:&[u8],work:&'a NativeReportWork,
 require:&dyn Fn(&T)->io::Result<()>,seals:fn(&T)->(Seal,Seal),
)->io::Result<Admitted<'a,T>>{
 work.checkpoint()?;
 let line=bytes.iter().take(MAX_HEADER).position(|b|*b==b'\n')
  .ok_or_else(||invalid("native utility lacks a bounded typed terminal"))?;
 // Same existing bounded terminal decode window used by baseline admission.
 work.temporary(0,MAX_HEADER.checked_mul(8).and_then(|n|n.checked_add(65_536)).ok_or_else(||work.overflow())?)?;
 let terminal:T=serde_json::from_slice(&bytes[..line]).map_err(io::Error::other)?;
 require(&terminal)?;
 let(err,out)=seals(&terminal);
 let total=err.length.checked_add(out.length).filter(|n|*n<=MAX_STREAM)
  .ok_or_else(||invalid("native utility stream aggregate exceeds its bound"))?;
 let payload=&bytes[line+1..];
 if usize::try_from(total).ok()!=Some(payload.len()){return Err(invalid("native utility payload differs from terminal extents"))}
 let split=usize::try_from(err.length).map_err(|_|invalid("native utility stderr extent overflow"))?;
 let(stderr,stdout)=payload.split_at(split);
 if err.hash.0!=xxhash_rust::xxh3::xxh3_128(stderr)||out.hash.0!=xxhash_rust::xxh3::xxh3_128(stdout){return Err(invalid("native utility stream differs from its actual seal"))}
 if !operational_stderr.is_empty(){return Err(io::Error::new(io::ErrorKind::Unsupported,"operational stderr has no separately qualified log sink; no completed utility output delivered"))}
 work.checkpoint()?;
 Ok(Admitted{terminal,stderr,stdout,_work:work})
}

#[cfg(test)]mod tests{
 use super::*;
 #[derive(serde::Serialize,serde::Deserialize)]#[serde(deny_unknown_fields)]struct Terminal{binding:u8,stderr:Seal,stdout:Seal}
 fn seals(t:&Terminal)->(Seal,Seal){(t.stderr,t.stdout)}
 fn bytes(binding:u8,err:&[u8],out:&[u8])->Vec<u8>{let seal=|bytes:&[u8]|Seal{length:bytes.len()as u64,hash:crate::selected_exclusions_wire::Hex128(xxhash_rust::xxh3::xxh3_128(bytes))};let mut result=serde_json::to_vec(&Terminal{binding,stderr:seal(err),stdout:seal(out)}).unwrap();result.push(b'\n');result.extend_from_slice(err);result.extend_from_slice(out);result}
 fn require(t:&Terminal)->io::Result<()>{if t.binding==7{Ok(())}else{Err(invalid("foreign utility request"))}}
 #[test]fn actual_empty_and_nonempty_utility_streams_require_both_seals_before_delivery(){
  for(err,out)in[(&b""[..],&b""[..]),(&b"diagnostic\n"[..],&b"answer\n"[..])]{let input=bytes(7,err,out);let work=NativeReportWork::for_buffer(input.len()).unwrap();let admitted=admit::<Terminal>(&input,&[],&work,&require,seals).unwrap();let(mut stdout,mut stderr)=(Vec::new(),Vec::new());admitted.publish(&mut stdout,&mut stderr).unwrap();assert_eq!(stderr,err);assert_eq!(stdout,out);}
  let input=bytes(8,b"",b"answer");let work=NativeReportWork::for_buffer(input.len()).unwrap();assert!(admit::<Terminal>(&input,&[],&work,&require,seals).is_err());
  let mut input=bytes(7,b"diagnostic",b"answer");*input.last_mut().unwrap()^=1;let work=NativeReportWork::for_buffer(input.len()).unwrap();assert!(admit::<Terminal>(&input,&[],&work,&require,seals).is_err());
 }
 #[test]fn utility_semantic_stderr_first_actual_io_stops_stdout(){
  struct Fail;impl Write for Fail{fn write(&mut self,_:&[u8])->io::Result<usize>{Err(io::Error::from_raw_os_error(1450))}fn flush(&mut self)->io::Result<()>{Ok(())}}
  let input=bytes(7,b"diagnostic",b"answer");let work=NativeReportWork::for_buffer(input.len()).unwrap();let admitted=admit::<Terminal>(&input,&[],&work,&require,seals).unwrap();let mut out=Vec::new();assert_eq!(admitted.publish(&mut out,&mut Fail).err().unwrap().raw_os_error(),Some(1450));assert!(out.is_empty());
 }
}

pub(super) fn input<T:serde::Serialize>(request:&T,work:&NativeReportWork)->io::Result<super::FundedInput>{
 use std::io::Write;struct Count<'a>{bytes:usize,work:&'a dyn crate::report_work::Work,first:Option<io::Error>}
 impl Write for Count<'_>{fn write(&mut self,bytes:&[u8])->io::Result<usize>{if let Some(first)=&self.first{return Err(first.kind().into())}if let Err(actual)=self.work.checkpoint(){let proxy=actual.kind().into();self.first=Some(actual);return Err(proxy)}self.bytes=self.bytes.checked_add(bytes.len()).filter(|n|*n<=crate::native_check_cli_wire::MAX_REQUEST).ok_or_else(||self.work.overflow())?;Ok(bytes.len())}fn flush(&mut self)->io::Result<()>{Ok(())}}
 let mut count=Count{bytes:0,work,first:None};let encoded=serde_json::to_writer(&mut count,request);if let Some(first)=count.first.take(){return Err(first)}encoded.map_err(|e|io::Error::new(e.io_error_kind().unwrap_or(io::ErrorKind::InvalidData),e))?;
 let size=count.bytes.checked_add(4).ok_or_else(||work.overflow())?;work.reserve(size.checked_mul(4).and_then(|n|n.checked_add(65536)).ok_or_else(||work.overflow())?)?;
 let mut bytes=Vec::new();bytes.try_reserve_exact(size).map_err(|_|work.overflow())?;if bytes.capacity()>size.saturating_mul(4){return Err(work.overflow())}bytes.extend_from_slice(&u32::try_from(count.bytes).map_err(|_|work.overflow())?.to_le_bytes());serde_json::to_writer(&mut bytes,request).map_err(io::Error::other)?;if bytes.len()!=size{return Err(io::Error::new(io::ErrorKind::InvalidData,"utility metadata count/encoding changed"))}work.checkpoint()?;Ok(super::FundedInput{bytes,_work:work.clone()})
}

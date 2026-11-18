//! Requested CHECK output/filter DATA; never source, filesystem or completion authority.
use serde::{Deserialize,Serialize};use std::io;use crate::selected_exclusions_wire::Hex128;
#[derive(Clone,Debug,Deserialize,Serialize,Eq,PartialEq,Ord,PartialOrd)]#[serde(deny_unknown_fields)]pub struct Request{#[serde(default,skip_serializing_if="Option::is_none")]pub changed:Option<Vec<String>>,#[serde(default,skip_serializing_if="is_false")]pub timing:bool,#[serde(default,skip_serializing_if="is_false")]pub timing_only:bool,#[serde(default,skip_serializing_if="is_false")]pub allow_usage:bool}
/// Same four-MiB metadata envelope as the existing daemon protocol.
pub const MAX_REQUEST:usize=4*1024*1024;
fn is_false(value:&bool)->bool{!*value}
impl Request{
 pub fn qualify(&self,options:crate::full_registry_check_wire::Options,selftests:bool)->io::Result<()>{
  if self.metadata_charge()?>MAX_REQUEST{return Err(io::Error::new(io::ErrorKind::OutOfMemory,"CHECK observation metadata exceeds the existing protocol bound"))}
  if self.allow_usage&&options.unused||self.timing_only&&(!self.timing||self.allow_usage||selftests||options.unused){return Err(io::Error::new(io::ErrorKind::InvalidInput,"CHECK observation mode differs from actual callback/ALLOW audit settings"))}Ok(())
 }
 pub fn binding(&self)->io::Result<Hex128>{let mut hash=xxhash_rust::xxh3::Xxh3::new();hash.update(b"native-check-cli-observations-v1\0");hash.update(&[self.timing as u8,self.timing_only as u8,self.allow_usage as u8,self.changed.is_some()as u8]);if let Some(paths)=&self.changed{let b=crate::full_registry_check_selection_wire::SelectionBinding::for_selectors(paths)?;hash.update(&b.selectors.to_le_bytes());hash.update(&b.hash.0.to_le_bytes());}Ok(Hex128(hash.digest128()))}
 pub fn metadata_charge(&self)->io::Result<usize>{self.changed.as_ref().map_or(Ok(0),|paths|paths.iter().try_fold(paths.capacity().checked_mul(std::mem::size_of::<String>()).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?,|n,path|n.checked_add(path.capacity()).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))))}
}
#[cfg(test)]mod controls{use super::*;#[test]fn actual_cli_binding_distinguishes_filter_absence_empty_paths_order_and_each_requested_output(){let make=|changed,timing,allow_usage|Request{changed,timing,timing_only:false,allow_usage}.binding().unwrap();assert_ne!(make(None,false,false),make(Some(vec![]),false,false));let paths=Some(vec!["code/a.dm".into()]);assert_ne!(make(paths.clone(),false,false),make(paths.clone(),true,false));assert_ne!(make(paths.clone(),false,false),make(paths,true,true));assert_ne!(make(Some(vec!["a".into(),"bc".into()]),false,false),make(Some(vec!["ab".into(),"c".into()]),false,false));}}

#[derive(Clone,Copy,Debug,Deserialize,Serialize,Eq,PartialEq)]pub enum Schema{#[serde(rename="native-check-cli-observations-v1")]V1}
fn presence<'de,D:serde::Deserializer<'de>>(d:D)->Result<Option<crate::selected_exclusions_wire::Seal>,D::Error>{Option::<crate::selected_exclusions_wire::Seal>::deserialize(d)}
/// Wrapper leaves the original V2/V3 terminal unchanged for ordinary requests.
/// The additional payload is a sealed ALLOW usage log, not a source/write grant.
#[derive(Clone,Debug,Deserialize,Serialize)]#[serde(deny_unknown_fields)]pub struct Terminal{pub schema:Schema,pub requested:Hex128,pub terminal:crate::full_registry_check_wire::Terminal,#[serde(deserialize_with="presence")]pub usage:Option<crate::selected_exclusions_wire::Seal>}
impl Terminal{pub fn require(&self,options:crate::full_registry_check_wire::Options,selection:crate::full_registry_check_selection_wire::SelectionBinding,selftests:bool,expected:&Request)->io::Result<()>{
 self.terminal.require_selftests(options,selection,selftests)?;let invalid=||io::Error::new(io::ErrorKind::InvalidData,"native CHECK CLI terminal differs from exact requested filters/output payloads");
 if self.requested!=expected.binding()?||self.usage.is_some()!=expected.allow_usage||expected.timing_only&&(!expected.timing||expected.allow_usage||selftests)||self.usage.as_ref().is_some_and(|seal|seal.length>crate::selected_exclusions_wire::MAX_STREAM)||self.terminal.report.length.checked_add(self.terminal.diagnostics.as_ref().map_or(0,|seal|seal.length)).and_then(|n|n.checked_add(self.usage.as_ref().map_or(0,|seal|seal.length))).is_none_or(|n|n>crate::selected_exclusions_wire::MAX_STREAM){return Err(invalid())}Ok(())
}}

/// Existing four-byte length + JSON frame, bounded before allocating the frame.
/// The native backend consumes this with its SAME protocol::receive kernel.
pub fn encode_request(request:&Request,work:&dyn crate::report_work::Work)->io::Result<Vec<u8>>{
 use std::io::Write;struct Count<'a>{bytes:usize,work:&'a dyn crate::report_work::Work,first:Option<io::Error>}
 impl Write for Count<'_>{fn write(&mut self,bytes:&[u8])->io::Result<usize>{if let Some(first)=&self.first{return Err(first.kind().into())}if let Err(actual)=self.work.checkpoint(){let proxy=actual.kind().into();self.first=Some(actual);return Err(proxy)}self.bytes=self.bytes.checked_add(bytes.len()).filter(|n|*n<=MAX_REQUEST).ok_or_else(||self.work.overflow())?;Ok(bytes.len())}fn flush(&mut self)->io::Result<()>{Ok(())}}
 let mut count=Count{bytes:0,work,first:None};let encoded=serde_json::to_writer(&mut count,request);if let Some(first)=count.first.take(){return Err(first)}encoded.map_err(|e|io::Error::new(e.io_error_kind().unwrap_or(io::ErrorKind::InvalidData),e))?;
 let size=count.bytes.checked_add(4).ok_or_else(||work.overflow())?;work.reserve(size.checked_mul(4).and_then(|n|n.checked_add(65536)).ok_or_else(||work.overflow())?)?;
 let mut bytes=Vec::new();bytes.try_reserve_exact(size).map_err(|_|work.overflow())?;if bytes.capacity()>size.saturating_mul(4){return Err(work.overflow())}bytes.extend_from_slice(&u32::try_from(count.bytes).map_err(|_|work.overflow())?.to_le_bytes());serde_json::to_writer(&mut bytes,request).map_err(io::Error::other)?;if bytes.len()!=size{return Err(io::Error::new(io::ErrorKind::InvalidData,"CHECK metadata count/encoding changed"))}work.checkpoint()?;Ok(bytes)
}

#[cfg(test)]mod first_metadata_io_control{use super::*;struct Stop;impl crate::report_work::Work for Stop{fn checkpoint(&self)->io::Result<()>{Err(io::Error::from_raw_os_error(1450))}fn reserve(&self,_:usize)->io::Result<()>{panic!("no allocation after actual counting IO")}fn overflow(&self)->io::Error{io::ErrorKind::OutOfMemory.into()}}
 #[test]fn actual_request_encoder_preserves_first_framework_os_error_before_frame_allocation(){let request=Request{changed:Some(vec!["code/a.dm".into()]),timing:false,timing_only:false,allow_usage:false};assert_eq!(encode_request(&request,&Stop).unwrap_err().raw_os_error(),Some(1450));}
}

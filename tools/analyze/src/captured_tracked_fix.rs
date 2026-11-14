//! Source-bound edit DATA produced only by the checked tracked collection.
//! Spans/preimage describe the exact normalized Analyze view, NOT physical CRLF offsets.
//! Apply must authenticate physical source and map per-line columns separately.
//! This module grants no filesystem, source or publication authority.
use crate::{captured_generator_budget::Budget,captured_reactive_reads::Failure,
 key_policy_control::{self as kc,Control},captured_allow_annotations::Operation,tracked_policy::Hit,tree::SourceFile};
use std::{io,sync::Arc};
#[derive(Debug,serde::Serialize)]
pub struct Edit {pub start:usize,pub end:usize,pub was:String,pub text:String,pub line:u32}
#[derive(Debug,serde::Serialize)]
pub struct Residue {pub line:u32,pub message:String}
#[derive(Debug,serde::Serialize)]
pub struct ListMacroFixData {relative:String,#[serde(skip_serializing)]preimage:String,edits:Vec<Edit>,residue:Vec<Residue>,#[serde(skip_serializing)]seen:bool,schema_count:usize}
fn oom(b:&Budget,message:&'static str)->Failure{b.deny();Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message))}
impl ListMacroFixData {
 pub(crate) fn new(relative:&str,b:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<Self,Failure>{
  let mut w=Operation{budget:b,poll};Ok(Self{relative:kc::own(&mut w,relative)?,preimage:String::new(),edits:Vec::new(),residue:Vec::new(),seen:false,schema_count:0})
 }
 pub(crate) fn set_schema_count(&mut self,count:usize){self.schema_count=count;}
 pub fn relative(&self)->&str{&self.relative}pub fn preimage(&self)->&str{&self.preimage}
 pub fn edits(&self)->&[Edit]{&self.edits}pub fn residue(&self)->&[Residue]{&self.residue}
 pub(crate) fn source(&mut self,file:&SourceFile,b:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<(),Failure>{
  if file.rel!=self.relative{return Ok(())}if self.seen{return Err("native fix source file was issued twice".into())}
  let mut w=Operation{budget:b,poll};self.preimage=kc::own(&mut w,&file.raw().text)?;self.seen=true;Ok(())
 }
 pub(crate) fn hit(&mut self,file:&SourceFile,hit:&mut Hit,b:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<(),Failure>{
  if !self.seen||file.rel!=self.relative||file.raw().text.as_str()!=self.preimage.as_str(){return Err("native fix hit is not the exact captured preimage".into())}
  if !hit.list_macro{return Err("native tracked-list_macro fix refuses other tracked write forms; no partial apply".into())}
  let mut w=Operation{budget:b,poll};w.checkpoint()?;
  let line=u32::try_from(hit.line).map_err(|_|oom(b,"native fix line overflow"))?;
  let Some(fix)=hit.fix.take()else{kc::row(&mut w,&mut self.residue)?;self.residue.push(Residue{line,message:kc::own(&mut w,&hit.msg)?});return Ok(())};
  if !fix.more.is_empty(){return Err("list macro fix unexpectedly requests multiline companion edits".into())}
  let raw=file.raw();if hit.line==0||hit.line>raw.num_lines(){return Err("fix line absent from actual preimage".into())}let offset=raw.line_start(hit.line);
  let start=offset.checked_add(fix.start as usize).ok_or_else(||oom(b,"fix start overflow"))?;
  let end=offset.checked_add(fix.end as usize).ok_or_else(||oom(b,"fix end overflow"))?;
  if start>end||self.preimage.get(start..end)!=Some(fix.was.as_str()){return Err("native fix byte span does not match actual source".into())}
  // The checked scanner funded temporary rewrite buffers before constructing
  // them. Fund their retained ownership before moving them out of that phase.
  b.charge(fix.was.capacity().checked_add(fix.text.capacity()).ok_or_else(||oom(b,"fix text charge overflow"))?).map_err(|_|oom(b,"fix text retention refused"))?;
  kc::row(&mut w,&mut self.edits)?;self.edits.push(Edit{start,end,was:fix.was,text:fix.text,line});Ok(())
 }
 pub(crate) fn finish(&mut self,b:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<(),Failure>{
  poll()?;if !self.seen{return Err("native fix target is absent from actual complete source discovery".into())}
  self.edits.sort_unstable_by_key(|edit|(edit.start,edit.end));
  let mut previous=0;for edit in &self.edits{if edit.start<previous{return Err("native fix edits overlap; no partial apply".into())}previous=edit.end;}
  b.require().map_err(|_|oom(b,"native fix final admission refused"))
 }
 pub fn retained_charge(&self)->Option<usize>{let mut n=std::mem::size_of::<Self>().checked_add(self.relative.capacity())?.checked_add(self.preimage.capacity())?.checked_add(self.edits.capacity().checked_mul(std::mem::size_of::<Edit>())?)?.checked_add(self.residue.capacity().checked_mul(std::mem::size_of::<Residue>())?)?;for edit in &self.edits{n=n.checked_add(edit.was.capacity())?.checked_add(edit.text.capacity())?;}for item in &self.residue{n=n.checked_add(item.message.capacity())?;}Some(n)}
 pub fn text(&self,applied:bool,b:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<String,Failure>{
  use std::fmt::Write;
  if self.schema_count==0{return kc::own(&mut Operation{budget:b,poll},"no tracked vars\n")}
  let mut size=128usize;
  for edit in &self.edits{size=size.checked_add(self.relative.len()).and_then(|n|n.checked_add(edit.was.len())).and_then(|n|n.checked_add(edit.text.len())).and_then(|n|n.checked_add(32)).ok_or_else(||oom(b,"fix report length overflow"))?;}
  for item in &self.residue{size=size.checked_add(self.relative.len()).and_then(|n|n.checked_add(item.message.len())).and_then(|n|n.checked_add(32)).ok_or_else(||oom(b,"fix residue report overflow"))?;}
  poll()?;b.charge(size.checked_mul(4).and_then(|n|n.checked_add(64)).ok_or_else(||oom(b,"fix report capacity overflow"))?).map_err(|_|oom(b,"fix report admission refused"))?;
  let mut output=String::new();output.try_reserve_exact(size).map_err(|_|oom(b,"fix report allocation failed"))?;
  if output.capacity()>size.saturating_mul(4){return Err(oom(b,"fix report allocation exceeds grant"))}
  for edit in &self.edits{poll()?;writeln!(&mut output,"{}:{}: {}  ->  {}",self.relative,edit.line,edit.was,edit.text).map_err(|_|oom(b,"fix report formatting failed"))?;}
  for item in &self.residue{poll()?;writeln!(&mut output,"{}:{}: residue: {}",self.relative,item.line,item.message).map_err(|_|oom(b,"fix residue formatting failed"))?;}
  writeln!(&mut output,"{} rewrite(s){}, {} for hand conversion",self.edits.len(),if applied{" applied"}else{" (dry run; --apply writes them)"},self.residue.len()).map_err(|_|oom(b,"fix summary formatting failed"))?;
  if output.len()>size{return Err(oom(b,"fix report exceeded its admitted bound"))}Ok(output)
 }
}

#[cfg(test)]mod data_controls {
 use super::*;
 #[test]fn fix_data_transport_omits_full_preimage_and_private_collection_marker(){
  let budget=Budget::new(1<<20).unwrap();let poll=||Ok(());
  let file=SourceFile::from_text("code/probe.dm","/obj/probe\n    var/list/items\n");
  let mut data=ListMacroFixData::new("code/probe.dm",&budget,&poll).unwrap();data.source(&file,&budget,&poll).unwrap();data.finish(&budget,&poll).unwrap();
  let wire=serde_json::to_value(&data).unwrap();
  assert!(wire.get("preimage").is_none());assert!(wire.get("seen").is_none());assert_eq!(wire["relative"],"code/probe.dm");
  assert_eq!(data.text(false,&budget,&poll).unwrap(),"no tracked vars\n");
 }
}

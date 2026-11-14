//! Source-bound edit DATA produced only by the checked tracked collection.
//! Spans/preimage describe the exact normalized Analyze view, NOT physical CRLF offsets.
//! Apply must authenticate physical source and map per-line columns separately.
//! This module grants no filesystem, source or publication authority.
use crate::{captured_generator_budget::Budget,captured_reactive_reads::Failure,
 key_policy_control::{self as kc,Control},captured_allow_annotations::Operation,tracked_policy::Hit,tree::SourceFile};
use std::{io,sync::Arc};
#[derive(Debug,serde::Serialize)]
pub struct Edit {pub start:usize,pub end:usize,pub was:String,pub text:String,pub line:u32,pub drop_line:bool}
#[derive(Debug,serde::Serialize)]
pub struct Residue {pub line:u32,pub message:String}
#[derive(Debug,serde::Serialize)]
pub struct ListMacroFixData {#[serde(skip_serializing)]rewrites:Vec<Rewrite>,#[serde(skip_serializing)]declarations:Option<Declarations>,#[serde(skip_serializing)]rewrite_count:usize,relative:String,#[serde(skip_serializing)]preimage:String,edits:Vec<Edit>,residue:Vec<Residue>,#[serde(skip_serializing)]seen:bool,schema_count:usize}
fn oom(b:&Budget,message:&'static str)->Failure{b.deny();Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message))}
impl ListMacroFixData {
 pub(crate) fn new(relative:&str,b:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<Self,Failure>{
  let mut w=Operation{budget:b,poll};Ok(Self{rewrites:Vec::new(),declarations:None,rewrite_count:0,relative:kc::own(&mut w,relative)?,preimage:String::new(),edits:Vec::new(),residue:Vec::new(),seen:false,schema_count:0})
 }
 pub(crate) fn set_schema_count(&mut self,count:usize){self.schema_count=count;}
 pub fn relative(&self)->&str{&self.relative}pub fn preimage(&self)->&str{&self.preimage}
 pub fn edits(&self)->&[Edit]{&self.edits}pub fn rewrite_count(&self)->usize{self.rewrite_count}pub fn has_schema(&self)->bool{self.schema_count!=0}pub fn declaration_counts(&self)->(usize,usize,usize,usize,usize){self.declarations.as_ref().map_or((0,0,0,0,0),|data|data.counts)}pub fn residue(&self)->&[Residue]{&self.residue}
 pub(crate) fn source(&mut self,file:&SourceFile,b:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<(),Failure>{
  if file.rel!=self.relative{return Ok(())}if self.seen{return Err("native fix source file was issued twice".into())}
  let mut w=Operation{budget:b,poll};self.preimage=kc::own(&mut w,&file.raw().text)?;self.seen=true;Ok(())
 }
 pub(crate) fn hit(&mut self,file:&SourceFile,hit:&mut Hit,b:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<(),Failure>{
  if !self.seen||file.rel!=self.relative||file.raw().text.as_str()!=self.preimage.as_str(){return Err("native fix hit is not the exact captured preimage".into())}
  self.hit_using(file,hit,b,poll,false)
 }
 pub(crate) fn tracked_hit(&mut self,file:&SourceFile,hit:&mut Hit,b:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<(),Failure>{
  if !self.seen||file.rel!=self.relative||file.raw().text.as_str()!=self.preimage.as_str(){return Err("native fix hit is not the exact captured preimage".into())}self.hit_using(file,hit,b,poll,true)
 }
 fn push_piece(&mut self,file:&SourceFile,line:usize,start:u32,end:u32,was:String,text:String,b:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<(),Failure>{
  let mut w=Operation{budget:b,poll};w.checkpoint()?;let raw=file.raw();if line==0||line>raw.num_lines(){return Err("fix line absent from actual preimage".into())}
  let offset=raw.line_start(line);let start=offset.checked_add(start as usize).ok_or_else(||oom(b,"fix start overflow"))?;let end=offset.checked_add(end as usize).ok_or_else(||oom(b,"fix end overflow"))?;
  let last=offset.checked_add(raw.line(line).len()).ok_or_else(||oom(b,"fix line end overflow"))?;
  if start>end||end>last||self.preimage.get(start..end)!=Some(was.as_str())||text.contains(['\r','\n']){return Err("native fix byte span does not match actual source single-line piece".into())}
  b.charge(was.capacity().checked_add(text.capacity()).ok_or_else(||oom(b,"fix text charge overflow"))?).map_err(|_|oom(b,"fix text retention refused"))?;
  let line=u32::try_from(line).map_err(|_|oom(b,"native fix line overflow"))?;kc::row(&mut w,&mut self.edits)?;self.edits.push(Edit{start,end,was,text,line,drop_line:false});Ok(())
 }
 fn hit_using(&mut self,file:&SourceFile,hit:&mut Hit,b:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>,all:bool)->Result<(),Failure>{
  if !all&&!hit.list_macro{return Err("native tracked-list_macro fix refuses other tracked write forms; no partial apply".into())}
  let mut w=Operation{budget:b,poll};w.checkpoint()?;let line=u32::try_from(hit.line).map_err(|_|oom(b,"native fix line overflow"))?;
  let Some(fix)=hit.fix.take()else{kc::row(&mut w,&mut self.residue)?;self.residue.push(Residue{line,message:kc::own(&mut w,&hit.msg)?});return Ok(())};
  if !all&&!fix.more.is_empty(){return Err("list macro fix unexpectedly requests multiline companion edits".into())}
  self.rewrite_count=self.rewrite_count.checked_add(1).ok_or_else(||oom(b,"fix rewrite count overflow"))?;
  let more=!fix.more.is_empty();self.push_piece(file,hit.line,fix.start,fix.end,fix.was,fix.text,b,poll)?;let main=self.edits.last().ok_or("actual main rewrite absent")?;let row=Rewrite{start:main.start,end:main.end,more};kc::row(&mut w,&mut self.rewrites)?;self.rewrites.push(row);
  for piece in fix.more{poll()?;let next=hit.line.checked_add(piece.line_off as usize).ok_or_else(||oom(b,"companion fix line overflow"))?;self.push_piece(file,next,piece.start,piece.end,piece.was,piece.text,b,poll)?;}Ok(())
 }
 pub(crate) fn drop_line(&mut self,file:&SourceFile,line:usize,b:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<(),Failure>{
  if !self.seen||file.rel!=self.relative||file.raw().text.as_str()!=self.preimage.as_str(){return Err("drop declaration is not the exact captured preimage".into())}let raw=file.raw();if line==0||line>raw.num_lines(){return Err("drop declaration line absent".into())}self.rewrite_count=self.rewrite_count.checked_add(1).ok_or_else(||oom(b,"fix rewrite count overflow"))?;let mut w=Operation{budget:b,poll};let was=kc::own(&mut w,raw.line(line))?;let start=raw.line_start(line);let end=start.checked_add(was.len()).ok_or_else(||oom(b,"drop declaration span overflow"))?;let line=u32::try_from(line).map_err(|_|oom(b,"drop declaration line overflow"))?;kc::row(&mut w,&mut self.edits)?;self.edits.push(Edit{start,end,was,text:String::new(),line,drop_line:true});Ok(())
 }
 pub(crate) fn begin_declarations(&mut self){self.declarations=Some(Declarations{rows:Vec::new(),counts:(0,0,0,0,0)});}
 pub(crate) fn declaration(&mut self,file:&SourceFile,line:usize,read:bool,generated:bool,dropped:bool,reason:&str,b:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<(),Failure>{let mut w=Operation{budget:b,poll};w.checkpoint()?;let data=self.declarations.as_mut().ok_or("declared report mode absent")?;let raw=file.raw();if line==0||line>raw.num_lines(){return Err("declared report line absent".into())}kc::row(&mut w,&mut data.rows)?;data.rows.push(Declaration{source:kc::own(&mut w,raw.line(line).trim())?,reason:kc::own(&mut w,reason)?,read,generated,dropped});if dropped{data.counts.0+=1;if read{data.counts.2+=1}else if generated{data.counts.3+=1}else{data.counts.4+=1}}else{data.counts.1+=1}Ok(())}
 pub(crate) fn finish(&mut self,b:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<(),Failure>{
  poll()?;if !self.seen{return Err("native fix target is absent from actual complete source discovery".into())}
  self.edits.sort_unstable_by_key(|edit|(edit.start,edit.end));
  let mut previous=0;for edit in &self.edits{if edit.start<previous{return Err("native fix edits overlap; no partial apply".into())}previous=edit.end;}
  b.require().map_err(|_|oom(b,"native fix final admission refused"))
 }
 pub fn retained_charge(&self)->Option<usize>{let mut n=std::mem::size_of::<Self>().checked_add(self.rewrites.capacity().checked_mul(std::mem::size_of::<Rewrite>())?)?.checked_add(self.relative.capacity())?.checked_add(self.preimage.capacity())?.checked_add(self.edits.capacity().checked_mul(std::mem::size_of::<Edit>())?)?.checked_add(self.residue.capacity().checked_mul(std::mem::size_of::<Residue>())?)?;for edit in &self.edits{n=n.checked_add(edit.was.capacity())?.checked_add(edit.text.capacity())?;}for item in &self.residue{n=n.checked_add(item.message.capacity())?;}if let Some(data)=&self.declarations{n=n.checked_add(data.retained_charge()?)?;}Some(n)}
 pub fn text(&self,applied:bool,b:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<String,Failure>{self.text_using(applied,b,poll,true)}
 pub fn body_text(&self,applied:bool,b:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<String,Failure>{self.text_using(applied,b,poll,false)}
 fn text_using(&self,applied:bool,b:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>,summary:bool)->Result<String,Failure>{
  use std::fmt::Write;
  if let Some(data)=&self.declarations{return data.text(&self.relative,applied,b,poll,summary)}
  if self.schema_count==0{return kc::own(&mut Operation{budget:b,poll},if summary{"no tracked vars\n"}else{""})}
  let mut size=128usize;
  for edit in &self.edits{size=size.checked_add(self.relative.len()).and_then(|n|n.checked_add(edit.was.len())).and_then(|n|n.checked_add(edit.text.len())).and_then(|n|n.checked_add(32)).ok_or_else(||oom(b,"fix report length overflow"))?;}
  for item in &self.residue{size=size.checked_add(self.relative.len()).and_then(|n|n.checked_add(item.message.len())).and_then(|n|n.checked_add(32)).ok_or_else(||oom(b,"fix residue report overflow"))?;}
  poll()?;b.charge(size.checked_mul(4).and_then(|n|n.checked_add(64)).ok_or_else(||oom(b,"fix report capacity overflow"))?).map_err(|_|oom(b,"fix report admission refused"))?;
  let mut output=String::new();output.try_reserve_exact(size).map_err(|_|oom(b,"fix report allocation failed"))?;
  if output.capacity()>size.saturating_mul(4){return Err(oom(b,"fix report allocation exceeds grant"))}
  for row in &self.rewrites{poll()?;let at=self.edits.binary_search_by_key(&(row.start,row.end),|edit|(edit.start,edit.end)).map_err(|_|Failure::from("logical rewrite lost its actual main edit"))?;let edit=&self.edits[at];writeln!(&mut output,"{}:{}: {}  ->  {}{}",self.relative,edit.line,edit.was,edit.text,if row.more{" ..."}else{""}).map_err(|_|oom(b,"fix report formatting failed"))?;}
  for item in &self.residue{poll()?;writeln!(&mut output,"{}:{}: residue: {}",self.relative,item.line,item.message).map_err(|_|oom(b,"fix residue formatting failed"))?;}
  if summary{writeln!(&mut output,"{} rewrite(s){}, {} for hand conversion",self.rewrite_count,if applied{" applied"}else{" (dry run; --apply writes them)"},self.residue.len()).map_err(|_|oom(b,"fix summary formatting failed"))?;}
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

#[derive(Debug)]struct Declaration{source:String,reason:String,read:bool,generated:bool,dropped:bool}
#[derive(Debug)]struct Declarations{rows:Vec<Declaration>,counts:(usize,usize,usize,usize,usize)}
impl Declarations{
 fn retained_charge(&self)->Option<usize>{self.rows.iter().try_fold(std::mem::size_of::<Self>().checked_add(self.rows.capacity().checked_mul(std::mem::size_of::<Declaration>())?)?,|n,row|n.checked_add(row.source.capacity())?.checked_add(row.reason.capacity()))}
 fn text(&self,relative:&str,applied:bool,b:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>,summary:bool)->Result<String,Failure>{
  use std::fmt::Write;let mut size=256usize;for row in &self.rows{size=size.checked_add(relative.len()).and_then(|n|n.checked_add(row.source.len())).and_then(|n|n.checked_add(row.reason.len())).and_then(|n|n.checked_add(128)).ok_or_else(||oom(b,"declared report bound overflow"))?;}
  let mut work=Operation{budget:b,poll};kc::reserve(&mut work,||size.checked_mul(4)?.checked_add(64))?;let mut output=String::new();output.try_reserve_exact(size).map_err(|_|oom(b,"declared report allocation failed"))?;if output.capacity()>size.saturating_mul(4){return Err(oom(b,"declared report allocation exceeds grant"))}let(mut dropped,mut kept,mut read,mut called,mut idle)=(0,0,0,0,0);
  for row in &self.rows{poll()?;if row.dropped{dropped+=1;if row.read{read+=1}else if row.generated{called+=1}else{idle+=1}writeln!(&mut output,"{}: drop {}{}",relative,row.source,if row.read{""}else if row.generated{"  (called, not read)"}else{"  (never written)"}).map_err(|_|oom(b,"declared report format failed"))?;}else{kept+=1;writeln!(&mut output,"{}: KEEP {}  ({})",relative,row.source,row.reason).map_err(|_|oom(b,"declared report format failed"))?;}}
  if summary{writeln!(&mut output,"{} TRACKED declaration(s) {} ({} read, {} called only, {} never written), {} kept",dropped,if applied{"dropped"}else{"droppable (dry run; --apply writes them)"},read,called,idle,kept).map_err(|_|oom(b,"declared report format failed"))?;}if output.len()>size{return Err(oom(b,"declared report exceeds bound"))}Ok(output)
 }
}

#[derive(Debug)]struct Rewrite{start:usize,end:usize,more:bool}

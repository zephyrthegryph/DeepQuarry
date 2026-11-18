//! Exact ordinary semantic utility text over shared readonly facts.
//! No parser/model/source or completion authority is issued by this renderer.
use std::io::{self,Write};
use crate::reactive_read_facts::{Read,Diag};
#[cfg(feature="native-policy")]use crate::captured_reactive_reads::FrozenReadSet;
pub struct Procedure<'a>{pub owner:&'a str,pub name:&'a str,pub file:&'a str,pub line:usize,pub builtin:bool,pub code:Option<usize>}
pub fn debug_proc(out:&mut impl Write,owner:&str,name:&str,type_known:bool,actual:Option<Procedure<'_>>)->io::Result<()>{match actual{None=>writeln!(out,"no proc {} {} (type known: {})",owner,name,type_known),Some(p)=>writeln!(out,"proc {}::{} at {}:{} builtin={} code={}",p.owner,p.name,p.file,p.line,p.builtin,p.code.map(|n|n as i64).unwrap_or(-1))}}
pub fn reads<'a>(out:&mut impl Write,reads:impl IntoIterator<Item=&'a Read>,diags:impl IntoIterator<Item=&'a Diag>,checkpoint:&dyn Fn()->io::Result<()>)->io::Result<()>{for r in reads{checkpoint()?;writeln!(out,"{}\t{:?}\t{}",r.key_display(),r.kind,r.owner)?}for d in diags{checkpoint()?;writeln!(out,"DIAG {} {}:{} {}",d.rule,d.rel,d.line,d.msg)?}Ok(())}
#[cfg(feature="native-policy")]
pub fn frozen_reads(out:&mut impl Write,value:&FrozenReadSet,checkpoint:&dyn Fn()->io::Result<()>)->io::Result<()>{reads(out,value.reads(),value.diagnostics(),checkpoint)}

pub const CLOTHING_ROOTS:[&str;3]=["/obj/item/clothing","/obj/item/storage/belt","/obj/item/storage/backpack"];
pub const CLOTHING_VARS:[&str;8]=["icon","icon_state","item_state","worn_state","icon_override","item_icons","sprite_sheets","item_state_slots"];
pub fn clothing_type(path:&str)->bool{CLOTHING_ROOTS.iter().any(|root|path==*root||path.strip_prefix(root).is_some_and(|tail|tail.starts_with('/')))}
/// The ordinary JSON schema/order, with borrowed caller-owned actual values.
/// The first actual output error is restored outside serde's proxy boundary.
pub fn clothing_row(out:&mut impl Write,path:&str,vars:&serde_json::Map<String,serde_json::Value>)->io::Result<()>{
 #[derive(serde::Serialize)]struct Row<'a>{path:&'a str,vars:&'a serde_json::Map<String,serde_json::Value>}
 struct Sink<'a,W:Write>{out:&'a mut W,first:Option<io::Error>}
 impl<W:Write>Write for Sink<'_,W>{fn write(&mut self,bytes:&[u8])->io::Result<usize>{if self.first.is_some(){return Err(io::ErrorKind::Other.into())}match self.out.write(bytes){Ok(n)=>Ok(n),Err(actual)=>{self.first=Some(actual);Err(io::ErrorKind::Other.into())}}}fn flush(&mut self)->io::Result<()>{if self.first.is_some(){return Err(io::ErrorKind::Other.into())}match self.out.flush(){Ok(())=>Ok(()),Err(actual)=>{self.first=Some(actual);Err(io::ErrorKind::Other.into())}}}}
 let mut sink=Sink{out,first:None};let pending=serde_json::to_writer(&mut sink,&Row{path,vars});if let Some(actual)=sink.first.take(){return Err(actual)}pending.map_err(io::Error::other)?;sink.out.write_all(b"\n")
}


/// Same serde_json map ordering as the original Map, without allocating a
/// second set of owned strings for already paid Debug values.
pub fn clothing_borrowed_row(out:&mut impl Write,path:&str,values:&[Option<&str>;8])->io::Result<()>{
 struct Vars<'a>(&'a[Option<&'a str>;8]);impl serde::Serialize for Vars<'_>{fn serialize<S:serde::Serializer>(&self,s:S)->Result<S::Ok,S::Error>{use serde::ser::SerializeMap;let mut map=s.serialize_map(Some(self.0.iter().filter(|value|value.is_some()).count()))?;for index in[0usize,4,1,5,2,7,6,3]{if let Some(value)=self.0[index]{map.serialize_entry(CLOTHING_VARS[index],value)?;}}map.end()}}
 #[derive(serde::Serialize)]struct Row<'a>{path:&'a str,vars:Vars<'a>}
 struct Sink<'a,W:Write>{out:&'a mut W,first:Option<io::Error>}impl<W:Write>Write for Sink<'_,W>{fn write(&mut self,bytes:&[u8])->io::Result<usize>{if self.first.is_some(){return Err(io::ErrorKind::Other.into())}match self.out.write(bytes){Ok(n)=>Ok(n),Err(first)=>{self.first=Some(first);Err(io::ErrorKind::Other.into())}}}fn flush(&mut self)->io::Result<()>{if self.first.is_some(){return Err(io::ErrorKind::Other.into())}match self.out.flush(){Ok(())=>Ok(()),Err(first)=>{self.first=Some(first);Err(io::ErrorKind::Other.into())}}}}
 let mut sink=Sink{out,first:None};let pending=serde_json::to_writer(&mut sink,&Row{path,vars:Vars(values)});if let Some(first)=sink.first.take(){return Err(first)}pending.map_err(io::Error::other)?;sink.out.write_all(b"\n")
}

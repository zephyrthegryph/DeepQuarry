//! Explicit final-generator bytes over the actual admitted workspace frame.
//! No output installation, second parser, or semantic/output cache.
use super::*;
use std::io;
use crate::daemon::query::encoded_bytes::{Buffer,ByteCursor,Collector,Fragment,MAX_FRAGMENT};
use dq_analyze::captured_generator_budget::Budget;
struct Hex(u128);
impl serde::Serialize for Hex{
 fn serialize<S:serde::Serializer>(&self,serializer:S)->Result<S::Ok,S::Error>{let mut bytes=[b'0';32];for(index,byte)in bytes.iter_mut().enumerate(){*byte=b"0123456789abcdef"[((self.0>>((31-index)*4))&15)as usize];}serializer.serialize_str(std::str::from_utf8(&bytes).expect("hexadecimal ASCII"))}
}

struct FragmentBuffer { bytes:Vec<u8>, limit:usize }
impl FragmentBuffer {
 fn new(budget:&Budget,limit:usize)->io::Result<Self>{
  if limit==0||limit>MAX_FRAGMENT{return Err(io::Error::new(io::ErrorKind::InvalidInput,"generator fragment limit invalid"))}
  let charge=limit.checked_mul(4).and_then(|n|n.checked_add(std::mem::size_of::<Self>())).ok_or_else(||io::Error::new(io::ErrorKind::OutOfMemory,"generator fragment admission overflow"))?;
  budget.charge(charge).map_err(|reason|io::Error::new(io::ErrorKind::OutOfMemory,reason))?;
  let mut bytes=Vec::new();bytes.try_reserve_exact(limit).map_err(|actual|io::Error::new(io::ErrorKind::OutOfMemory,actual))?;
  if bytes.capacity()>limit.saturating_mul(4){budget.deny();return Err(io::Error::new(io::ErrorKind::OutOfMemory,"generator fragment allocation exceeded admission"))}
  Ok(Self{bytes,limit})
 }
}
impl Buffer for FragmentBuffer {
 fn append(&mut self,value:&[u8])->io::Result<()>{if self.bytes.len().checked_add(value.len()).is_none_or(|n|n>self.limit){return Err(io::Error::new(io::ErrorKind::OutOfMemory,"generator fragment exceeded admission"))}self.bytes.extend_from_slice(value);Ok(())}
 fn bytes(&self)->&[u8]{&self.bytes}
}

impl SourceSnapshot {
 pub(crate) fn write_native_generator_bytes(&self,name:crate::GeneratorName,cursor:Option<ByteCursor>,limit:usize,tree:&dm_tree::SemanticTree,output:&mut impl io::Write)->io::Result<()>{
  if !self.matches_tree(tree){return Err(io::Error::new(io::ErrorKind::InvalidInput,"generator semantic tree belongs to another snapshot"))}
  let guard=self.workspace_native_read()?;
  let workspace=self.native_workspace.as_ref().ok_or_else(||io::Error::other("generator workspace unavailable"))?;
  let child=self.workspace_generator_inputs(name)?;
  let db=self.native_raw_queries.as_ref().ok_or_else(||io::Error::other("generator query graph unavailable"))?;
  db.with_workspace_generator_guard_budget(workspace,&guard,child,name,|artifact,budget|{
   let mut bytes=FragmentBuffer::new(budget,limit)?;
   let mut collector=Collector::new(&mut bytes,cursor,limit,64*1024*1024)?;
   serde_json::to_writer(&mut collector,&artifact.output_wire()).map_err(io::Error::from)?;
   let fragment=collector.finish()?;
   budget.require().map_err(|reason|io::Error::new(io::ErrorKind::OutOfMemory,reason))?;
   crate::daemon::control::checkpoint()?;workspace.require_scope(&guard)?;
   #[derive(serde::Serialize)]struct Page<'a>{row:&'static str,schema:&'static str,semantic_revision:Hex,source_revision:Hex,policy_revision:Hex,generator:&'static str,full_generator_output:bool,byte_fragment_only:bool,output_format:&'static str,requested_cursor:Option<ByteCursor>,limit:usize,fragment:Fragment,bytes:&'a[u8]}
   let page=Page{row:"source_native_generator_bytes",schema:"dm-session-source-query-v1",semantic_revision:Hex(tree.identity().into()),source_revision:Hex(self.source_revision),policy_revision:Hex(self.policy_revision.ok_or_else(||io::Error::other("generator workspace revision unavailable"))?),generator:name.name(),full_generator_output:true,byte_fragment_only:true,output_format:"native_generator_artifact_json",requested_cursor:cursor,limit,fragment,bytes:bytes.bytes()};
   serde_json::to_writer(&mut *output,&page).map_err(io::Error::from)?;output.write_all(b"\n")?;
   budget.require().map_err(|reason|io::Error::new(io::ErrorKind::OutOfMemory,reason))?;crate::daemon::control::checkpoint()?;workspace.require_scope(&guard)
  })
 }
}

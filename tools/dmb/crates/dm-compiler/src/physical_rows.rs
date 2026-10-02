//! Optional exact physical row directory. Symbol/debug witnesses remain the replay gate.
use std::{collections::BTreeMap,io};
use byond_dmb::dmb::{Proc,Variable};
use dm_output::{assembly::AssemblyImage,typed_table::TypedTable,wire_image::WireImageBuilder};
use sha2::{Digest,Sha256};
#[derive(Clone)]
struct Location {proc_index:usize,variable_start:usize,variables:usize,digest:[u8;32]}
#[derive(Default)]
pub(crate) struct PhysicalRowsDirectory {procs:Option<TypedTable<Proc>>,variables:Option<TypedTable<Variable>>,entries:BTreeMap<crate::ProcKey,Location>,pending:BTreeMap<crate::ProcKey,(usize,usize,usize)>,pub hits:usize}
fn fingerprint(proc:&Proc,variables:&[Variable])->io::Result<[u8;32]> {let bytes=rmp_serde::to_vec(&(proc,variables)).map_err(io::Error::other)?;Ok(Sha256::digest(bytes).into())}
impl PhysicalRowsDirectory {
 pub fn clear(&mut self) {*self=Self::default();}
 pub fn begin(&mut self) {self.pending.clear();self.hits=0;}
 pub fn observe(&mut self,key:&crate::ProcKey,proc_index:usize,start:usize,count:usize) {if self.pending.len()<100_000 {self.pending.insert(key.clone(),(proc_index,start,count));}}
 pub fn reuse<I:AssemblyImage>(&mut self,key:&crate::ProcKey,image:&mut I,proc:&Proc,variables:&[Variable])->io::Result<bool> {
  if !image.supports_typed_segments() {return Ok(false);}
  let Some(location)=self.entries.get(key) else {return Ok(false);};
  if location.variables!=variables.len()||location.digest!=fingerprint(proc,variables)? {return Ok(false);}
  let (Some(procs),Some(vars))=(&self.procs,&self.variables) else {return Ok(false);};
  let Ok(proc_rows)=procs.slice_segments(location.proc_index,location.proc_index+1) else {return Ok(false);};
  let Ok(variable_rows)=vars.slice_segments(location.variable_start,location.variable_start+location.variables) else {return Ok(false);};
  image.append_variable_source_segments(variable_rows)?;image.append_proc_source_segments(proc_rows)?;self.hits+=1;Ok(true)
 }
 pub fn capture(&mut self,image:&mut WireImageBuilder)->io::Result<()> {
  let procs=image.capture_proc_table()?;let variables=image.capture_variable_table()?;let mut entries=BTreeMap::new();
  // Walk physical order so bounded page caches decode each page once, rather
  // than thrashing them in the unrelated lexical declaration-key order.
  let mut ordered:Vec<_>=self.pending.iter().collect();ordered.sort_unstable_by_key(|(_,location)|location.0);
  for (key,(proc_index,start,count)) in ordered {if *count>1024 {continue;}
   let digest=fingerprint(&procs.get(*proc_index)?,&variables.range(*start,start+count)?)?;
   entries.insert(key.clone(),Location {proc_index:*proc_index,variable_start:*start,variables:*count,digest});
  }
  self.procs=Some(procs);self.variables=Some(variables);self.entries=entries;self.pending.clear();
  if self.resident_bytes()>64*1024*1024 {self.clear();}Ok(())
 }
 pub fn resident_bytes(&self)->usize {self.procs.as_ref().map_or(0,TypedTable::resident_bytes)+self.variables.as_ref().map_or(0,TypedTable::resident_bytes)+self.entries.iter().map(|(key,_)|key.path.capacity()+std::mem::size_of::<Location>()+96).sum::<usize>()+self.pending.keys().map(|key|key.path.capacity()+120).sum::<usize>()}
}

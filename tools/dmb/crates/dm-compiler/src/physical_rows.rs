//! Optional exact physical row directory. Symbol/debug witnesses remain the replay gate.
use std::{collections::BTreeMap,io,path::Path,sync::{Arc,Mutex}};
use byond_dmb::dmb::{Proc,Variable};
use dm_output::{assembly::AssemblyImage,typed_table::{TypedTable,PageSliceRef},typed_pages::TypedPages,wire_image::WireImageBuilder};
use serde::{Serialize,Deserialize};
use sha2::{Digest,Sha256};
#[derive(Clone)]
struct Location {proc_index:usize,variable_start:usize,variables:usize,digest:[u8;32]}
#[derive(Clone,Serialize,Deserialize)]
struct Durable {version:u32,digest:[u8;32],procs:Vec<PageSliceRef>,variables:Vec<PageSliceRef>}
struct Disk {records:dm_store::PackedRecords,store:dm_store::Store,base_namespace:String,selected_namespace:String,procs:Arc<Mutex<TypedPages<Proc>>>,variables:Arc<Mutex<TypedPages<Variable>>>}
#[derive(Default)]
struct Misses {unsupported:usize,noentry:usize,variables:usize,digest:usize,slices:usize}
#[derive(Default)]
pub(crate) struct PhysicalRowsDirectory {procs:Option<TypedTable<Proc>>,variables:Option<TypedTable<Variable>>,entries:BTreeMap<crate::ProcKey,Location>,pending:BTreeMap<crate::ProcKey,(usize,usize,usize)>,pub hits:usize,disk:Option<Disk>,restored:BTreeMap<crate::ProcKey,Durable>,known:BTreeMap<crate::ProcKey,[u8;32]>,misses:Misses}
fn fingerprint(proc:&Proc,variables:&[Variable])->io::Result<[u8;32]> {crate::content_hash::compact(b"",&(proc,variables)).ok_or_else(||io::Error::other("physical row fingerprint encoding failed"))}
impl PhysicalRowsDirectory {
 pub fn open(root:&Path,identity:&str)->Self {
  let disk=(||->io::Result<Disk> {let namespace=format!("physical-rows-v1-{:x}",Sha256::digest(format!("{}\0{}",identity,env!("DM_EMISSION_FINGERPRINT"))));
   let store=dm_store::Store::open(root.join("physical-row-directory.redb"))?;
   Ok(Disk {records:dm_store::PackedRecords::new(store.clone(),namespace.clone())?,store,base_namespace:namespace.clone(),selected_namespace:namespace,
    procs:Arc::new(Mutex::new(TypedPages::open(root,"wire-proc-v1",1024*1024,|_|0)?)),variables:Arc::new(Mutex::new(TypedPages::open(root,"wire-variable-v1",1024*1024,|_|0)?))})})();
  Self {disk:disk.ok(),..Default::default()}
 }
 /// Retain directories for prior declaration layouts instead of overwriting
 /// their row locations on every structural edit. This selects candidates;
 /// the exact current physical-row fingerprint still authorizes every reuse.
 pub fn select_context(&mut self,proof:Option<&crate::project_graph::BindingContextProof>)->io::Result<()> {
  let Some(disk)=&self.disk else {return Ok(());};
  let namespace=match proof {
   Some(proof)=>format!("{}-{}",disk.base_namespace,crate::content_hash::text(crate::content_hash::compact(b"physical-layout-context-v1\0",proof).ok_or_else(||io::Error::other("physical layout context encoding failed"))?)),
   None=>disk.base_namespace.clone(),
  };
  if namespace==disk.selected_namespace {return Ok(());}
  let records=dm_store::PackedRecords::new(disk.store.clone(),namespace.clone())?;
  self.clear();
  if let Some(disk)=&mut self.disk {disk.records=records;disk.selected_namespace=namespace;}
  Ok(())
 }
 pub fn clear(&mut self) {if std::env::var_os("DM_BUILD_TRACE").is_some() {eprintln!("DM_BUILD_TRACE physical rows pressure/reset clear: entries={} bytes={}",self.entries.len(),self.resident_bytes());}let disk=self.disk.take();if let Some(disk)=&disk {disk.records.clear_index_cache();disk.procs.lock().unwrap_or_else(|e|e.into_inner()).clear_decoded();disk.variables.lock().unwrap_or_else(|e|e.into_inner()).clear_decoded();}*self=Self {disk,..Default::default()};}
 fn name(key:&crate::ProcKey)->String {format!("{:x}",Sha256::digest(format!("{}\0{}",key.path,key.occurrence)))}
 pub fn prefetch(&mut self,keys:&[crate::ProcKey]) {
  self.restored.clear();let Some(disk)=&self.disk else {return;};
  if keys.len()>1024 {return;}
  let requested:Vec<_>=keys.iter().filter(|key|!self.entries.contains_key(*key)).collect();if requested.is_empty() {return;}
  let names:Vec<_>=requested.iter().map(|key|Self::name(key)).collect();
  let Ok(rows)=disk.records.read_many(&names,1024*1024,8*1024*1024,None) else {return;};
  for (key,bytes) in requested.into_iter().zip(rows) {let Some(bytes)=bytes else {continue;};
   let Ok(row)=rmp_serde::from_slice::<Durable>(&bytes) else {continue;};
   if row.procs.iter().chain(&row.variables).any(|slice|slice.start>slice.end||slice.end>slice.page.rows||slice.page.rows>256) {continue;}
   if row.version!=1||row.procs.len()>2||row.variables.len()>8||row.procs.iter().map(|slice|slice.end.saturating_sub(slice.start)).sum::<usize>()!=1 {continue;}
   self.known.insert(key.clone(),row.digest);self.restored.insert(key.clone(),row);
  }
 }
 pub fn begin(&mut self) {self.pending.clear();self.hits=0;self.misses=Misses::default();}
 pub fn observe(&mut self,key:&crate::ProcKey,proc_index:usize,start:usize,count:usize) {if self.pending.len()<100_000 {self.pending.insert(key.clone(),(proc_index,start,count));}}
 pub fn reuse<I:AssemblyImage>(&mut self,key:&crate::ProcKey,image:&mut I,proc:&Proc,variables:&[Variable])->io::Result<bool> {
  if !image.supports_typed_segments() {self.misses.unsupported+=1;return Ok(false);}
  let digest=fingerprint(proc,variables)?;
  if !self.entries.contains_key(key) {if let (Some(disk),Some(saved))=(&self.disk,self.restored.get(key)) {
   if saved.digest!=digest {self.misses.digest+=1;return Ok(false);}
   let mut procs=TypedTable::default();let mut vars=TypedTable::default();
   if procs.append_page_slices(disk.procs.clone(),saved.procs.clone()).is_err()||vars.append_page_slices(disk.variables.clone(),saved.variables.clone()).is_err()||vars.len()!=variables.len() {return Ok(false);}
   let Ok(actual)=procs.get(0).and_then(|row|vars.range(0,vars.len()).and_then(|values|fingerprint(&row,&values))) else {self.known.remove(key);return Ok(false);};
   if actual!=digest {self.known.remove(key);return Ok(false);}
   image.append_variable_source_segments(vars.slice_segments(0,vars.len())?)?;image.append_proc_source_segments(procs.slice_segments(0,1)?)?;self.hits+=1;return Ok(true);
  }self.misses.noentry+=1;return Ok(false);}
  let Some(location)=self.entries.get(key) else {return Ok(false);};
  if location.variables!=variables.len() {self.misses.variables+=1;return Ok(false);}
  if location.digest!=digest {self.misses.digest+=1;return Ok(false);}
  let (Some(procs),Some(vars))=(&self.procs,&self.variables) else {return Ok(false);};
  let Ok(proc_rows)=procs.slice_segments(location.proc_index,location.proc_index+1) else {self.misses.slices+=1;return Ok(false);};
  let Ok(variable_rows)=vars.slice_segments(location.variable_start,location.variable_start+location.variables) else {self.misses.slices+=1;return Ok(false);};
  image.append_variable_source_segments(variable_rows)?;image.append_proc_source_segments(proc_rows)?;self.hits+=1;Ok(true)
 }
 pub fn capture(&mut self,image:&mut WireImageBuilder)->io::Result<()> {
  let started=std::time::Instant::now();let mut procs=image.capture_proc_table()?;let mut variables=image.capture_variable_table()?;
  if self.disk.is_some() {procs.address_resident_segments()?;variables.address_resident_segments()?;}
  let mut changed=Vec::new();let mut changed_bytes=0usize;let mut published=0usize;let mut entries=BTreeMap::new();
  // Walk physical order so bounded page caches decode each page once, rather
  // than thrashing them in the unrelated lexical declaration-key order.
  let mut ordered:Vec<_>=self.pending.iter().collect();ordered.sort_unstable_by_key(|(_,location)|location.0);
  for (key,(proc_index,start,count)) in ordered {if *count>1024 {continue;}
   let digest=fingerprint(&procs.get(*proc_index)?,&variables.range(*start,start+count)?)?;
   if self.disk.is_some()&&self.known.get(key)!=Some(&digest) {
    let saved=Durable {version:1,digest,procs:procs.export_page_slices(*proc_index,*proc_index+1)?,variables:variables.export_page_slices(*start,start+count)?};
    let bytes=rmp_serde::to_vec(&saved).map_err(io::Error::other)?;
    if !changed.is_empty()&&(changed.len()>=16_384||changed_bytes.saturating_add(bytes.len()+80)>8*1024*1024) {
        if let Some(disk)=&self.disk {if !matches!(disk.records.write_many(&changed,None)?,dm_store::Commit::Applied) {return Err(io::Error::new(io::ErrorKind::WouldBlock,"physical directory publication conflict"));}}
        published+=changed.len();changed.clear();changed_bytes=0;
    }
    changed_bytes+=bytes.len()+80;changed.push((Self::name(key),bytes));self.known.insert(key.clone(),digest);
   }
   entries.insert(key.clone(),Location {proc_index:*proc_index,variable_start:*start,variables:*count,digest});
  }
  if !changed.is_empty() {if let Some(disk)=&self.disk {if !matches!(disk.records.write_many(&changed,None)?,dm_store::Commit::Applied) {return Err(io::Error::new(io::ErrorKind::WouldBlock,"physical directory publication conflict"));}}published+=changed.len();}
  if std::env::var_os("DM_BUILD_TRACE").is_some() {eprintln!("DM_BUILD_TRACE physical row directory: rows={} published={} capture_seconds={:.3} hits={} unsupported={} noentry={} variable_count={} digest={} slices={}",entries.len(),published,started.elapsed().as_secs_f64(),self.hits,self.misses.unsupported,self.misses.noentry,self.misses.variables,self.misses.digest,self.misses.slices);}
  self.procs=Some(procs);self.variables=Some(variables);self.entries=entries;self.pending.clear();
  if self.resident_bytes()>64*1024*1024 {self.clear();}Ok(())
 }
 pub fn resident_bytes(&self)->usize {self.procs.as_ref().map_or(0,TypedTable::resident_bytes)+self.variables.as_ref().map_or(0,TypedTable::resident_bytes)+self.entries.iter().map(|(key,_)|key.path.capacity()+std::mem::size_of::<Location>()+96).sum::<usize>()+self.pending.keys().map(|key|key.path.capacity()+120).sum::<usize>()+self.known.keys().map(|key|key.path.capacity()+128).sum::<usize>()+self.restored.iter().map(|(key,row)|key.path.capacity()+256+(row.procs.len()+row.variables.len())*192).sum::<usize>()+self.disk.as_ref().map_or(0,|disk|disk.records.retained_index_bytes()+disk.procs.lock().unwrap_or_else(|e|e.into_inner()).resident_bytes()+disk.variables.lock().unwrap_or_else(|e|e.into_inner()).resident_bytes())}
}

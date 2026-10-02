//! Owner-local symbolic binding roots. Physical table IDs are never cache inputs.
//! Current allocation aliases compose separately from the immutable semantic roots.
use super::*;
use serde::{Serialize,Deserialize};
use dm_codegen_byond::{AllocationCensus,CompactMap,CompactSet};
use sha2::{Digest,Sha256};
#[derive(Clone,Default,Serialize,Deserialize)]
struct Root {
 types:CompactMap<String,String>,globals:CompactMap<String,String>,fields:CompactSet<String>,
 procs:CompactMap<String,String>,known_procs:CompactSet<String>,returns:CompactMap<String,String>,
 static_types:CompactMap<String,String>,parent:Option<String>,
}
#[derive(Default)]
pub(crate) struct OwnerBindingQueries {
 roots:im::OrdMap<String,(String,Root)>,snapshot:SharedLowerBindings,store:Option<Store>,bytes:usize,
 snapshot_ready:bool,recency:HashMap<String,u64>,clock:u64,
 overlap_cache:std::sync::Mutex<Option<(std::sync::Weak<SharedLowerBindings>,usize)>>,
}
impl OwnerBindingQueries {
 const LIMIT:usize=32*1024*1024;
 fn namespace()->String {format!("owner-binding-roots-v3-{}",env!("DM_EMISSION_FINGERPRINT"))}
 pub(super) fn bind(&mut self,root:&Path){*self=Self {store:Store::open(root.join("declaration-fragments.redb")).ok(),..Default::default()};}
 pub(super) fn resident_bytes(&self)->usize{self.bytes}
 pub(super) fn resident_bytes_excluding(&self,shared:&Arc<SharedLowerBindings>)->usize {
  let mut cached=self.overlap_cache.lock().unwrap_or_else(|error|error.into_inner());
  if let Some((weak,bytes))=&*cached {if weak.upgrade().is_some_and(|old|Arc::ptr_eq(&old,shared)){return *bytes;}}
  let bytes=resident_charge_excluding(&self.roots,&self.snapshot,Some(shared))+recency_charge(&self.recency);
  if std::env::var_os("DM_BUILD_TRACE").is_some(){eprintln!("DM_BUILD_TRACE owner binding allocation census: standalone_bytes={} unique_after_frozen_bytes={} shared_bytes={}",self.bytes,bytes,self.bytes.saturating_sub(bytes));}
  *cached=Some((Arc::downgrade(shared),bytes));bytes
 }
 pub(super) fn clear(&mut self){self.roots.clear();self.snapshot=SharedLowerBindings::default();self.bytes=0;self.snapshot_ready=false;self.recency.clear();*self.overlap_cache.lock().unwrap_or_else(|error|error.into_inner())=None;}
 pub(crate) fn build(&mut self,dmb:&impl AssemblyImage,mut types:HashMap<String,HashMap<String,String>>,pending:&[PendingProc<'_>],shared:&mut SharedLowerBindings,source_debug:Option<&crate::source_debug::SourceDebugIndex<'_>>)->Result<HashMap<String,u32>,String> {
  let started=std::time::Instant::now();let mut restore_seconds=0.0;
  shared.member_types=self.snapshot.member_types.clone();shared.member_globals=self.snapshot.member_globals.clone();
  shared.known_member_fields=self.snapshot.known_member_fields.clone();shared.member_procs=self.snapshot.member_procs.clone();
  shared.known_member_procs=self.snapshot.known_member_procs.clone();shared.member_proc_return_types=self.snapshot.member_proc_return_types.clone();shared.parent_types=self.snapshot.parent_types.clone();
  let mut authored:HashMap<&str,Vec<&PendingProc<'_>>>=HashMap::new();
  for procedure in pending {if !procedure.owner_path.is_empty(){authored.entry(&procedure.owner_path).or_default().push(procedure);}}
  let mut inputs=Vec::with_capacity(dmb.classes().len());
  for (class_id,class) in dmb.classes().iter().enumerate(){
   let Some(owner)=dmb.string(class.path_string_id()).and_then(|bytes|std::str::from_utf8(bytes).ok())else{continue;};
   let mut hash=Sha256::new();
   fn text(hash:&mut Sha256,value:&[u8]){hash.update((value.len() as u64).to_le_bytes());hash.update(value);}
   text(&mut hash,owner.as_bytes());
   text(&mut hash,dmb.classes().get(class.parent_class_id() as usize).and_then(|parent|dmb.string(parent.path_string_id())).unwrap_or(&[]));
   hash.update(b"fields");
   for (variable,flags) in dmb.class_variable_declarations(class_id).map_err(|error|error.to_string())?.unwrap_or_default(){text(&mut hash,owner_variable_name(dmb,variable)?.unwrap_or(&[]));hash.update(flags.to_le_bytes());}
   hash.update(b"types");
   if let Some(fields)=types.get(owner){let mut fields:Vec<_>=fields.iter().collect();fields.sort();for(name,ty)in fields{text(&mut hash,name.as_bytes());text(&mut hash,ty.as_bytes());}}
   hash.update(b"native-procs");
   for slot in 0..2 {hash.update([slot as u8]);let list=class.lists_and_procs[slot];if list!=0xffff {let ids=dmb.list_words(list).map_err(|error|error.to_string())?;for id in &ids {let proc=dmb.proc(*id as usize).map_err(|error|error.to_string())?;text(&mut hash,dmb.string(proc.strings[0]).unwrap_or(&[]));text(&mut hash,dmb.string(proc.strings[1]).unwrap_or(&[]));}}}
   hash.update(b"authored-procs");
   if let Some(procedures)=authored.get(owner){for procedure in procedures {text(&mut hash,procedure.item.header.as_bytes());hash.update([procedure.verb as u8,has_proc_name_setting(&procedure.item.children) as u8]);}}
   inputs.push((Some(class_id),owner,format!("{:x}",hash.finalize())));
  }
  // Pseudo owners such as /world have authored member procedures but no
  // physical class row. Their semantic namespace still needs an owner root.
  let physical:HashSet<_>=inputs.iter().map(|(_,owner,_)|*owner).collect();
  let synthetic:BTreeSet<_>=authored.keys().copied().filter(|owner|!physical.contains(owner)).collect();
  for owner in synthetic {
   let mut hash=Sha256::new();hash.update(b"synthetic-owner-binding-v1");hash.update((owner.len() as u64).to_le_bytes());hash.update(owner.as_bytes());
   if let Some(fields)=types.get(owner){let mut fields:Vec<_>=fields.iter().collect();fields.sort();for(name,ty)in fields{hash.update((name.len() as u64).to_le_bytes());hash.update(name.as_bytes());hash.update((ty.len() as u64).to_le_bytes());hash.update(ty.as_bytes());}}
   for procedure in &authored[owner] {hash.update((procedure.item.header.len() as u64).to_le_bytes());hash.update(procedure.item.header.as_bytes());hash.update([procedure.verb as u8,has_proc_name_setting(&procedure.item.children) as u8]);}
   inputs.push((None,owner,format!("{:x}",hash.finalize())));
  }
  let input_seconds=started.elapsed().as_secs_f64();
  let mut next=self.roots.clone();let present:HashSet<_>=inputs.iter().map(|(_,owner,_)|*owner).collect();
  let removed:BTreeSet<_>=self.snapshot.member_types.keys().chain(next.keys()).filter(|owner|!present.contains(owner.as_str())).cloned().collect();for owner in removed{next.remove(&owner);shared.member_types.remove(&owner);shared.member_globals.remove(&owner);shared.known_member_fields.remove(&owner);shared.member_procs.remove(&owner);shared.known_member_procs.remove(&owner);shared.member_proc_return_types.remove(&owner);shared.parent_types.remove(&owner);}
  let mut aliases=HashMap::new();let mut writes=Vec::new();let mut write_bytes=0;let mut hits=0;let mut misses=0;
  let mut input_iter=inputs.into_iter();
  loop {
   let window:Vec<_>=input_iter.by_ref().take(1024).collect();if window.is_empty(){break;}
  let restore_started=std::time::Instant::now();let mut restored=HashMap::new();let mut restored_bytes=0usize;
  if let Some(store)=self.store.clone(){
   let keys:Vec<_>=window.iter().filter(|(_,owner,key)|self.roots.get(*owner).is_none_or(|(old,_)|old!=key)).map(|(_,_,key)|Key::new(Self::namespace(),key)).collect();
   default_plans::read_stage_batch(&store,&keys,1024*1024,8*1024*1024,&mut |key,bytes|{if let Some(bytes)=bytes {let charge=bytes.len().saturating_mul(3);if restored_bytes.saturating_add(charge)<=16*1024*1024 {if let Ok(root)=rmp_serde::from_slice::<Root>(&bytes){restored_bytes+=charge;restored.insert(key.name.clone(),root);}}}});
  }
  restore_seconds+=restore_started.elapsed().as_secs_f64();
  for (class_id,owner,key) in window {

   self.clock=self.clock.wrapping_add(1);
   if let Some(recency)=self.recency.get_mut(owner){*recency=self.clock;}else{self.recency.insert(owner.to_owned(),self.clock);}
   let unchanged=self.snapshot_ready&&self.roots.get(owner).is_some_and(|(old,_)|old==&key);
   let root=if let Some((old,root))=self.roots.get(owner).filter(|(old,_)|old==&key){let _=old;hits+=1;root.clone()}
    else if let Some(root)=restored.remove(&key){hits+=1;next.insert(owner.to_owned(),(key.clone(),root.clone()));root}
    else {misses+=1;let root=derive(dmb,class_id,owner,types.remove(owner),authored.get(owner).map(Vec::as_slice).unwrap_or(&[]),source_debug)?;
     if let Ok(bytes)=rmp_serde::to_vec_named(&root){write_bytes+=bytes.len();writes.push(Change::Put(Key::new(Self::namespace(),&key),bytes));if write_bytes>=1024*1024 {if let Some(store)=&self.store{let _=store.commit(&[],&writes,None);}writes.clear();write_bytes=0;}}
     next.insert(owner.to_owned(),(key.clone(),root.clone()));root};
   if !unchanged {
    shared.member_types.insert(owner.to_owned(),root.types);shared.member_globals.insert(owner.to_owned(),root.globals);
    shared.known_member_fields.insert(owner.to_owned(),root.fields);shared.member_procs.insert(owner.to_owned(),root.procs);
    shared.known_member_procs.insert(owner.to_owned(),root.known_procs);shared.member_proc_return_types.insert(owner.to_owned(),root.returns);
    if let Some(parent)=root.parent{shared.parent_types.insert(owner.to_owned(),parent);}else{shared.parent_types.remove(owner);}
   }
   shared.global_types.extend(root.static_types);
   for (variable,flags) in if let Some(class_id)=class_id {dmb.class_variable_declarations(class_id).map_err(|error|error.to_string())?.unwrap_or_default()}else{Vec::new()}{if flags&1!=0 {if let Some(name)=owner_variable_name(dmb,variable)?.and_then(|bytes|std::str::from_utf8(bytes).ok()){let symbol=static_symbol("__dm_class_static_",owner,name);shared.globals.insert(symbol.clone());aliases.insert(symbol,variable);}}}
  }
  }
  if !writes.is_empty(){if let Some(store)=&self.store{let _=store.commit(&[],&writes,None);}}
  // Optional owner recipes use bounded LRU admission, rather than discarding
  // the complete inventory when one owner pushes it over budget.
  let mut charges:Vec<_>=next.iter().map(|(owner,(key,root))|(self.recency.get(owner).copied().unwrap_or(0),owner.clone(),root_charge(owner,key,root))).collect();
  let mut recipe_bytes=charges.iter().map(|(_,_,bytes)|*bytes).sum::<usize>();
  if recipe_bytes>Self::LIMIT {
   charges.sort_by_key(|(recency,_,_)|*recency);
   for (_,owner,charge) in charges {if recipe_bytes<=Self::LIMIT{break;}next.remove(&owner);self.recency.remove(&owner);recipe_bytes=recipe_bytes.saturating_sub(charge);}
  }
  self.recency.retain(|owner,_|next.contains_key(owner));
  self.roots=next;
  self.snapshot=SharedLowerBindings {member_types:shared.member_types.clone(),member_globals:shared.member_globals.clone(),known_member_fields:shared.known_member_fields.clone(),member_procs:shared.member_procs.clone(),known_member_procs:shared.known_member_procs.clone(),member_proc_return_types:shared.member_proc_return_types.clone(),parent_types:shared.parent_types.clone(),..Default::default()};
  // The aggregate is a shared semantic model, separately bounded from decoded
  // recipe admission. Container allocation identities prevent double charging
  // the same Arc through both recipe rows and the aggregate indexes.
  self.snapshot_ready=true;
  if snapshot_charge(&self.snapshot)>64*1024*1024 {self.snapshot=SharedLowerBindings::default();self.snapshot_ready=false;}
  self.bytes=resident_charge(&self.roots,&self.snapshot)+recency_charge(&self.recency);
  *self.overlap_cache.lock().unwrap_or_else(|error|error.into_inner())=None;
  if std::env::var_os("DM_BUILD_TRACE").is_some(){eprintln!("DM_BUILD_TRACE owner binding roots: reused={hits} derived={misses} retained_bytes={} inputs_seconds={input_seconds:.3} restore_seconds={restore_seconds:.3} total_seconds={:.3}",self.bytes,started.elapsed().as_secs_f64());}
  Ok(aliases)
 }
}
fn owner_variable_name(dmb:&impl AssemblyImage,id:u32)->Result<Option<&[u8]>,String> {
 let row=dmb.variable(id as usize).map_err(|error|error.to_string())?;Ok(dmb.string(row.name))
}

fn derive(dmb:&impl AssemblyImage,class_id:Option<usize>,owner:&str,types:Option<HashMap<String,String>>,authored:&[&PendingProc<'_>],source_debug:Option<&crate::source_debug::SourceDebugIndex<'_>>)->Result<Root,String>{
 let mut root=Root::default();if let Some(types)=types{root.types=types.into_iter().collect();}
 let declared_types=root.types.clone();
 let mut builtin=LowerBindings::default();seed_builtin_fields(owner,&mut builtin);
 root.fields.extend(builtin.fields);for(name,ty)in builtin.field_types{root.types.entry(name).or_insert(ty);}
 let class=class_id.and_then(|id|dmb.classes().get(id));root.parent=class.and_then(|class|dmb.classes().get(class.parent_class_id() as usize)).and_then(|parent|dmb.string(parent.path_string_id())).and_then(|bytes|std::str::from_utf8(bytes).ok()).filter(|parent|*parent!=owner).map(str::to_owned);
 for (variable,flags) in if let Some(class_id)=class_id {dmb.class_variable_declarations(class_id).map_err(|error|error.to_string())?.unwrap_or_default()}else{Vec::new()}{if let Some(name)=owner_variable_name(dmb,variable)?.and_then(|bytes|std::str::from_utf8(bytes).ok()){
  root.fields.insert(name.to_owned());if flags&1!=0 {let symbol=static_symbol("__dm_class_static_",owner,name);root.globals.insert(name.to_owned(),symbol.clone());if let Some(ty)=declared_types.get(name){root.static_types.insert(symbol,ty.clone());}}
 }}
 for slot in 0..2 {if let Some(list)=class.map(|class|class.lists_and_procs[slot]).filter(|list|*list!=0xffff){let ids=dmb.list_words(list).map_err(|error|error.to_string())?;for id in &ids{let proc=dmb.proc(*id as usize).map_err(|error|error.to_string())?;if let Some(path)=dmb.string(proc.strings[0]).and_then(|bytes|std::str::from_utf8(bytes).ok()){if let Some(name)=path.rsplit('/').next(){root.known_procs.insert(name.to_owned());if dmb.string(proc.strings[1])!=Some(name.replace('_'," ").as_bytes()){root.procs.insert(name.to_owned(),path.to_owned());}}}}}}
 for procedure in authored {let path=InvocationFragments::declaration_path(procedure.item,owner,procedure.verb)?;let name=path.rsplit('/').next().unwrap_or("").to_owned();root.known_procs.insert(name.clone());if let Some(Some(ty))=declared_proc_return_type(&procedure.item.header).map_err(|reason|source_error(source_debug,procedure.span().start,&procedure.item.header,&reason))?{root.returns.insert(name.clone(),ty);}if has_proc_name_setting(&procedure.item.children){root.procs.insert(name,path);}}
 Ok(root)
}

fn map_charge(rows:&CompactMap<String,String>)->usize {
 rows.storage_bytes()+rows.iter().map(|(key,value)|key.capacity()+value.capacity()).sum::<usize>()
}
fn set_charge(rows:&CompactSet<String>)->usize {
 rows.storage_bytes()+rows.iter().map(String::capacity).sum::<usize>()
}
fn root_charge(owner:&str,key:&str,root:&Root)->usize {
 owner.len()+key.len()+256
 +[&root.types,&root.globals,&root.procs,&root.returns,&root.static_types].iter().map(|rows|map_charge(rows)).sum::<usize>()
 +[&root.fields,&root.known_procs].iter().map(|rows|set_charge(rows)).sum::<usize>()
 +root.parent.as_ref().map_or(0,String::capacity)
}
fn snapshot_charge(snapshot:&SharedLowerBindings)->usize {
 let mut seen=HashSet::new();aggregate_charge(snapshot,&mut seen)
}
fn aggregate_charge(snapshot:&SharedLowerBindings,seen:&mut HashSet<usize>)->usize {
 let mut bytes=std::mem::size_of::<SharedLowerBindings>();
 for map in [&snapshot.member_types,&snapshot.member_globals,&snapshot.member_procs,&snapshot.member_proc_return_types] {
  for (owner,rows) in map {bytes+=owner.capacity()+96;if seen.insert(rows.allocation_id()){bytes+=map_charge(rows);}}
 }
 for map in [&snapshot.known_member_fields,&snapshot.known_member_procs] {
  for (owner,rows) in map {bytes+=owner.capacity()+96;if seen.insert(rows.allocation_id()){bytes+=set_charge(rows);}}
 }
 bytes+snapshot.parent_types.iter().map(|(key,value)|key.capacity()+value.capacity()+96).sum::<usize>()
}
fn resident_charge(roots:&im::OrdMap<String,(String,Root)>,snapshot:&SharedLowerBindings)->usize {
 let mut seen=HashSet::new();let mut bytes=aggregate_charge(snapshot,&mut seen);
 for (owner,(key,root)) in roots {
  bytes+=owner.capacity()+key.capacity()+256+root.parent.as_ref().map_or(0,String::capacity);
  for rows in [&root.types,&root.globals,&root.procs,&root.returns,&root.static_types] {if seen.insert(rows.allocation_id()){bytes+=map_charge(rows);}}
  for rows in [&root.fields,&root.known_procs] {if seen.insert(rows.allocation_id()){bytes+=set_charge(rows);}}
 }
 bytes
}

fn recency_charge(recency:&HashMap<String,u64>)->usize {
 recency.capacity()*(std::mem::size_of::<(String,u64)>()+16)+recency.keys().map(String::capacity).sum::<usize>()
}
fn resident_charge_excluding(roots:&im::OrdMap<String,(String,Root)>,snapshot:&SharedLowerBindings,other:Option<&SharedLowerBindings>)->usize {
 let mut census=AllocationCensus::default();
 if let Some(other)=other {
  for map in [&other.member_types,&other.member_globals,&other.member_procs,&other.member_proc_return_types] {for (_,rows) in map {census.observe(rows.allocation_id());}}
  for map in [&other.known_member_fields,&other.known_member_procs] {for (_,rows) in map {census.observe(rows.allocation_id());}}
 }
 let mut bytes=std::mem::size_of::<SharedLowerBindings>();
 for (index,map) in [&snapshot.member_types,&snapshot.member_globals,&snapshot.member_procs,&snapshot.member_proc_return_types].into_iter().enumerate() {
  let shared_root=other.is_some_and(|other|map.ptr_eq([&other.member_types,&other.member_globals,&other.member_procs,&other.member_proc_return_types][index]));
  for (owner,rows) in map {if !shared_root{bytes+=owner.capacity()+96;}bytes+=census.claim(rows.allocation_id(),map_charge(rows));}
 }
 for (index,map) in [&snapshot.known_member_fields,&snapshot.known_member_procs].into_iter().enumerate() {
  let shared_root=other.is_some_and(|other|map.ptr_eq([&other.known_member_fields,&other.known_member_procs][index]));
  for (owner,rows) in map {if !shared_root{bytes+=owner.capacity()+96;}bytes+=census.claim(rows.allocation_id(),set_charge(rows));}
 }
 if !other.is_some_and(|other|snapshot.parent_types.ptr_eq(&other.parent_types)) {bytes+=snapshot.parent_types.iter().map(|(key,value)|key.capacity()+value.capacity()+96).sum::<usize>();}
 for (owner,(key,root)) in roots {
  bytes+=owner.capacity()+key.capacity()+256+root.parent.as_ref().map_or(0,String::capacity);
  for rows in [&root.types,&root.globals,&root.procs,&root.returns,&root.static_types] {bytes+=census.claim(rows.allocation_id(),map_charge(rows));}
  for rows in [&root.fields,&root.known_procs] {bytes+=census.claim(rows.allocation_id(),set_charge(rows));}
 }
 bytes
}

//! Reusable physical declaration prefix, independent of procedure overlays.
//! Portable compressed artifacts are primary; one bounded encoded record is
//! retained per session. Current procedure syntax is replayed from source handles.
use super::*;
const MAX_ENCODED:usize=32*1024*1024;
const MAX_DECODED:usize=256*1024*1024;
const NAMESPACE:&str="declaration-allocation-base-v2";
pub(crate) struct DeclarationBase {
 pub image:dm_output::wire_image::WireImageBuilder,pub strings:StringIndexRecipe,
 pub proc_paths:HashSet<Vec<u8>>,pub class_paths:HashMap<String,u32>,
 pub metadata:TypeMetadataState,pub dynamic:Vec<PendingDynamic>,
 pub globals:HashMap<String,u32>,pub global_types:HashMap<String,String>,
 pub field_types:HashMap<String,HashMap<String,String>>,pub type_order:Vec<usize>,
}
#[derive(Serialize,Deserialize)]
struct BaseWire {image:dm_output::wire_image::PhysicalSnapshot,strings:StringIndexRecipe,
 proc_paths:HashSet<Vec<u8>>,class_paths:HashMap<String,u32>,
 metadata:TypeMetadataState,dynamic:Vec<PendingDynamic>,
 globals:HashMap<String,u32>,global_types:HashMap<String,String>,
 field_types:HashMap<String,HashMap<String,String>>,type_order:Vec<usize>,
}
pub(super) fn encode(base:&mut DeclarationBase)->Option<Vec<u8>> {
 let wire=BaseWire {image:base.image.export_snapshot().ok()?,strings:base.strings.clone(),proc_paths:base.proc_paths.clone(),class_paths:base.class_paths.clone(),metadata:base.metadata.clone(),dynamic:base.dynamic.clone(),globals:base.globals.clone(),global_types:base.global_types.clone(),field_types:base.field_types.clone(),type_order:base.type_order.clone()};
 let raw=rmp_serde::to_vec_named(&wire).ok()?;if raw.len()>MAX_DECODED{return None;}
 let encoded=lz4_flex::compress_prepend_size(&raw);(encoded.len()<=MAX_ENCODED).then_some(encoded)
}
pub(super) fn decode(bytes:&[u8],store:Arc<dm_output::wire_image::CodeObjectStore>)->Option<DeclarationBase> {
 if bytes.len()>MAX_ENCODED||bytes.len()<4{return None;}let length=u32::from_le_bytes(bytes[..4].try_into().ok()?) as usize;if length>MAX_DECODED{return None;}
 let raw=lz4_flex::decompress_size_prepended(bytes).ok()?;let wire:BaseWire=rmp_serde::from_slice(&raw).ok()?;
 Some(DeclarationBase {image:dm_output::wire_image::WireImageBuilder::restore_snapshot(wire.image,store).ok()?,strings:wire.strings,proc_paths:wire.proc_paths,class_paths:wire.class_paths,metadata:wire.metadata,dynamic:wire.dynamic,globals:wire.globals,global_types:wire.global_types,field_types:wire.field_types,type_order:wire.type_order})
}
pub(super) fn load(root:&Path,key:&str)->Option<Vec<u8>> {
 let store=Store::open(root.join("declaration-base.redb")).ok()?;
 store.read_many_bounded(&[Key::new(NAMESPACE,key)],MAX_ENCODED,MAX_ENCODED,None).ok()?.values.into_iter().next().flatten()
}
pub(super) fn store(root:&Path,key:&str,bytes:&[u8]) {
 if let Ok(store)=Store::open(root.join("declaration-base.redb")) {let _=store.commit(&[],&[Change::Put(Key::new(NAMESPACE,key),bytes.to_vec())],None);}
}
pub(crate) fn declaration_base_key(items:&[Item],modified:&ModifiedTypes,builtins:&[u8],world:&str,resources:&HashMap<String,u32>,debug:bool)->String {
 declaration_base_key_roots(&[items],modified,builtins,world,resources,debug)
}
pub(crate) fn declaration_base_key_fragments(fragments:&[(usize,Arc<dm_syntax::AstFile>)],modified:&ModifiedTypes,builtins:&[u8],world:&str,resources:&HashMap<String,u32>,debug:bool)->String {
 let roots:Vec<_>=fragments.iter().map(|(_,ast)|ast.items.as_slice()).collect();
 declaration_base_key_roots(&roots,modified,builtins,world,resources,debug)
}
fn declaration_base_key_roots(roots:&[&[Item]],modified:&ModifiedTypes,builtins:&[u8],world:&str,resources:&HashMap<String,u32>,debug:bool)->String {
 fn field(hash:&mut Sha256,value:&str){hash.update((value.len() as u64).to_le_bytes());hash.update(value.as_bytes());}
 fn rows(hash:&mut Sha256,items:&[Item],references:&mut Vec<String>){
  for item in items {
   if matches!(item.kind,ItemKind::Proc|ItemKind::Verb){continue;}
   hash.update([item.kind as u8]);field(hash,&item.header);
   if let Some((_,value))=item.header.split_once('=') {
    // Both explicit proc values and qualified statics depend on the overlay.
    // Ambiguous absolute values can denote overridden proc paths as well.
    if value.contains("/proc")||value.contains("/verb")||value.contains("::")||value.trim_start().starts_with('/') {references.push(value.to_owned());}
   }
   rows(hash,&item.children,references);hash.update([255]);
  }
 }
 let mut hash=Sha256::new();hash.update(NAMESPACE);hash.update(env!("DM_EMISSION_FINGERPRINT"));hash.update(Sha256::digest(builtins));field(&mut hash,world);hash.update([u8::from(debug)]);
 let mut references=Vec::new();for items in roots {rows(&mut hash,items,&mut references);}rows(&mut hash,&modified.declarations,&mut references);
 // Implicit classes are allocated in first-observed top-level owner order.
 // Repeated procedures on an existing owner do not change this allocation.
 let mut seen=HashSet::new();
 for item in roots.iter().flat_map(|items|items.iter()).filter(|item|matches!(item.kind,ItemKind::Proc|ItemKind::Verb)) {
  let raw=item.header.split('(').next().unwrap_or("").trim().trim_end_matches('/');
  let owner=raw.rsplit_once("/proc/").or_else(||raw.rsplit_once("/verb/")).or_else(||raw.rsplit_once('/')).map(|(owner,_)|owner).unwrap_or("");
  if !owner.is_empty()&&!matches!(owner,"/proc"|"/verb"|"/world")&&seen.insert(owner){field(&mut hash,owner);}
 }
 // Extract exact absolute names read by declaration expressions. Current
 // provisional proc recipes do not embed final IDs; their targets are resolved
 // by the procedure overlay. Changes to the referenced target are conservative
 // invalidations, unrelated new procedures are not.
 let mut referenced=HashSet::<String>::new();
 for value in &references {
  let bytes=value.as_bytes();let mut i=0;
  while i<bytes.len(){if bytes[i]!=b'/'{i+=1;continue;}let start=i;i+=1;
   while i<bytes.len()&&(bytes[i].is_ascii_alphanumeric()||matches!(bytes[i],b'/'|b'_')){i+=1;}
   referenced.insert(value[start..i].to_owned());
  }
 }
 if !referenced.is_empty() {
  fn observed(items:&[Item],owner:&str,referenced:&HashSet<String>,hash:&mut Sha256){
   for item in items {
    if matches!(item.kind,ItemKind::Proc|ItemKind::Verb){
     let raw=item.header.split('(').next().unwrap_or("").trim();
     let path=if raw.starts_with('/') {raw.to_owned()} else {format!("{owner}/{}",raw.trim_start_matches('/'))};
     let explicit=if raw.starts_with('/') {path.clone()} else {format!("{owner}/{}/{}",if item.kind==ItemKind::Verb{"verb"}else{"proc"},raw.trim_start_matches("proc/").trim_start_matches("verb/"))};
     if referenced.contains(&path)||referenced.contains(&explicit){field(hash,&item.header);let mut ignored=Vec::new();rows(hash,&item.children,&mut ignored);}
    }else{observed(&item.children,if item.kind==ItemKind::Type{item.header.trim()}else{owner},referenced,hash);}
   }
  }
  for items in roots {observed(items,"",&referenced,&mut hash);}
 }
 let mut resources:Vec<_>=resources.iter().collect();resources.sort_by(|a,b|a.0.cmp(b.0));
 for(name,id)in resources{field(&mut hash,name);hash.update(id.to_le_bytes());}
 format!("{:x}",hash.finalize())
}

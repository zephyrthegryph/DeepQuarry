//! Typed declaration operation plans with exact replay witnesses. Unsupported
//! mutation families continue deriving normally; no unobserved table patch is
//! accepted. The same immutable plan can back declaration pages and analysis.
use super::*;
use std::sync::{Mutex,OnceLock};
use sha2::{Digest,Sha256};
use serde::{Serialize,Deserialize};
use dm_store::{Store,Key,Change};
const NAMESPACE:&str="typed-declaration-operations-v1";
const LIMIT:usize=4*1024*1024;
#[derive(Serialize,Deserialize)]
struct Witness {allocation:bool,class:byond_dmb::dmb::Class,strings:usize,variables:usize,lists:usize,footer:u32,list_lengths:Vec<(u32,usize)>,resource:Option<(String,u32)>}
pub(super) struct Snapshot {witness:Witness}
#[derive(Serialize,Deserialize)]
enum Operation {Intern {bytes:Vec<u8>,id:u32},WriteClass(byond_dmb::dmb::Class),AppendVariable(byond_dmb::dmb::Variable),AppendList(Vec<u32>),ExtendList {id:u32,words:Vec<u32>},SetFooter(u32)}
#[derive(Serialize,Deserialize)]
struct Plan {witness:Witness,operations:Vec<Operation>}
#[derive(Default)]
struct Cache {root:Option<std::path::PathBuf>,store:Option<Store>,rows:HashMap<String,(Arc<Plan>,usize)>,missing:HashSet<String>,bytes:usize,pending:Vec<Change>,pending_bytes:usize,hits:usize,misses:usize}
fn cache()->&'static Mutex<Cache>{static CACHE:OnceLock<Mutex<Cache>>=OnceLock::new();CACHE.get_or_init(||Mutex::new(Cache::default()))}
fn key(owner:&str,source:&str)->String {let mut hash=Sha256::new();hash.update(env!("DM_EMISSION_FINGERPRINT"));hash.update((owner.len() as u64).to_le_bytes());hash.update(owner);hash.update(source);format!("{:x}",hash.finalize())}
fn owner(dmb:&Dmb,id:u32)->Option<&str>{std::str::from_utf8(dmb.string(dmb.classes.get(id as usize)?.path_string_id())?).ok()}
fn resource(source:&str,resources:&HashMap<String,u32>)->Option<(String,u32)>{let(name,value)=source.split_once('=')?;if name.trim()!="icon"&&!name.trim().starts_with("var/"){return None;}let path=value.trim().strip_prefix('\'')?.strip_suffix('\'')?.replace('\\',"/");Some((path.clone(),*resources.get(&path)?))}
fn numeric(value:&str)->bool {value.bytes().any(|byte|byte.is_ascii_digit())&&value.bytes().all(|byte|byte.is_ascii_digit()||matches!(byte,b'.'|b'+'|b'-'|b'e'|b'E'))&&value.parse::<f32>().is_ok()}
fn literal(value:&str)->bool {value=="null"||numeric(value)||(value.len()>=2&&value.starts_with('"')&&value.ends_with('"')&&!value[1..value.len()-1].contains(['[',']','\\','"']))||(value.len()>=2&&value.starts_with('\'')&&value.ends_with('\''))}
pub(super) fn eligible_variable(source:&str)->bool {let (name,value)=source.split_once('=').unwrap_or((source,"null"));name.trim().starts_with("var/")&&!name.contains(['[',']'])&&!name.split('/').any(|part|matches!(part.trim(),"static"|"const"))&&literal(value.trim())}
pub(super) fn eligible(source:&str)->bool {
 if eligible_variable(source){return true;}
 let Some((name,value))=source.split_once('=')else{return false;};let name=name.trim();let value=value.trim();
 match name {
  "name"|"desc"|"icon_state"|"maptext"|"text"|"suffix"=>value=="null"||(value.len()>=2&&value.starts_with('"')&&value.ends_with('"')&&!value[1..value.len()-1].contains(['[',']','\\','"'])),
  "icon"=>value=="null"||(value.len()>=2&&value.starts_with('\'')&&value.ends_with('\'')),
  "density"|"opacity"|"layer"|"dir"|"maptext_width"|"maptext_height"|"maptext_x"|"maptext_y"|"mouse_opacity"|"animate_movement"=>numeric(value),
  _=>false,
 }
}
fn flush_locked(cache:&mut Cache){if cache.pending.is_empty(){return;}if let Some(store)=&cache.store {if store.commit(&[],&cache.pending,None).is_err(){return;}}cache.pending.clear();cache.pending_bytes=0;}
pub(super) fn flush(){flush_locked(&mut cache().lock().unwrap_or_else(|error|error.into_inner()));}
pub(super) fn bind(root:&Path){let mut cache=cache().lock().unwrap_or_else(|error|error.into_inner());if cache.root.as_deref()==Some(root){return;}flush_locked(&mut cache);*cache=Cache {root:Some(root.to_owned()),store:Store::open(root.join("declaration-operations.redb")).ok(),..Default::default()};}
fn retain(cache:&mut Cache,key:String,plan:Arc<Plan>,size:usize){if size>LIMIT{return;}if let Some((_,old))=cache.rows.remove(&key){cache.bytes=cache.bytes.saturating_sub(old);}while cache.bytes.saturating_add(size)>LIMIT{let Some(key)=cache.rows.keys().next().cloned()else{break;};if let Some((_,old))=cache.rows.remove(&key){cache.bytes=cache.bytes.saturating_sub(old);}}cache.bytes+=size;cache.missing.remove(&key);cache.rows.insert(key,(plan,size));}
pub(super) fn prefetch(items:&[&Item]) {
 let mut cache=cache().lock().unwrap_or_else(|error|error.into_inner());let Some(store)=cache.store.clone()else{return;};
 let keys:Vec<_>=items.iter().flat_map(|item|item.children.iter().filter(|child|eligible(&child.header)).map(move|child|Key::new(NAMESPACE,key(item.header.trim(),&child.header)))).filter(|key|!cache.rows.contains_key(&key.name)&&!cache.missing.contains(&key.name)).collect();
 for batch in keys.chunks(4096){default_plans::read_stage_batch(&store,batch,64*1024,4*1024*1024,&mut |key,bytes|{if let Some(bytes)=bytes {if let Ok(plan)=rmp_serde::from_slice::<Plan>(&bytes){retain(&mut cache,key.name.clone(),Arc::new(plan),bytes.len()*2+key.name.len()+128);return;}}if cache.missing.len()<16_384 {cache.missing.insert(key.name.clone());}});}
}
pub(super) fn replay(source:&str,class:u32,dmb:&mut Dmb,strings:&mut StringIndex,resources:&HashMap<String,u32>)->bool {
 let Some(owner)=owner(dmb,class)else{return false;};let key=key(owner,source);
 let plan={let mut cache=cache().lock().unwrap_or_else(|error|error.into_inner());cache.misses+=1;cache.rows.get(&key).map(|(plan,_)|Arc::clone(plan))};let Some(plan)=plan else{return false;};
 if dmb.classes[class as usize]!=plan.witness.class||resource(source,resources)!=plan.witness.resource||(plan.witness.allocation&&(dmb.variables.len()!=plan.witness.variables||dmb.lists.len()!=plan.witness.lists||dmb.variable_footer!=plan.witness.footer||plan.witness.list_lengths.iter().any(|(id,length)|dmb.lists.get(*id as usize).is_none_or(|words|words.len()!=*length)))){return false;}
 let mut next=dmb.strings.len() as u32;let mut new=HashMap::<&[u8],u32>::new();
 for operation in &plan.operations {if let Operation::Intern {bytes,id}=operation {
  let observed=strings.0.get(bytes.as_slice()).copied().or_else(||new.get(bytes.as_slice()).copied()).unwrap_or_else(||{while crate::native_reserved_string_id(next){next+=1;}let assigned=next;next+=1;new.insert(bytes,assigned);assigned});
  if observed!=*id{return false;}
 }}
 for operation in &plan.operations {match operation {Operation::Intern {bytes,..}=>{strings.intern_bytes(dmb,bytes);},Operation::WriteClass(row)=>dmb.classes[class as usize]=row.clone(),Operation::AppendVariable(row)=>dmb.variables.push(row.clone()),Operation::AppendList(words)=>{dmb.lists.push(words.clone());},Operation::ExtendList {id,words}=>dmb.lists[*id as usize].extend(words.iter().copied()),Operation::SetFooter(id)=>dmb.variable_footer=*id}}
 {let mut cache=cache().lock().unwrap_or_else(|error|error.into_inner());cache.misses=cache.misses.saturating_sub(1);cache.hits+=1;}
 true
}
pub(super) fn begin(source:&str,class:u32,dmb:&Dmb,resources:&HashMap<String,u32>)->Snapshot {
 let row=dmb.classes[class as usize].clone();let mut list_lengths=Vec::new();
 for id in [row.lists_and_procs[4],dmb.variable_footer] {if id!=0xffff&&!list_lengths.iter().any(|(other,_)|*other==id) {if let Some(words)=dmb.lists.get(id as usize){list_lengths.push((id,words.len()));}}}
 Snapshot {witness:Witness {allocation:eligible_variable(source),class:row,strings:dmb.strings.len(),variables:dmb.variables.len(),lists:dmb.lists.len(),footer:dmb.variable_footer,list_lengths,resource:resource(source,resources)}}
}
pub(super) fn record(source:&str,class:u32,snapshot:Snapshot,dmb:&Dmb,strings:Vec<procedure_fragments::StringRecipe>){
 let Some(owner)=owner(dmb,class)else{return;};let key=key(owner,source);
 let mut operations=Vec::new();for operation in strings {match operation {procedure_fragments::StringRecipe::Bytes {old_id,bytes}=>operations.push(Operation::Intern {bytes:bytes.to_vec(),id:old_id}),procedure_fragments::StringRecipe::Debug {..}=>return,}}
 for (id,length) in &snapshot.witness.list_lengths {let words=&dmb.lists[*id as usize];if words.len()<*length{return;}if words.len()>*length {operations.push(Operation::ExtendList {id:*id,words:words[*length..].to_vec()});}}
 for row in &dmb.variables[snapshot.witness.variables..] {operations.push(Operation::AppendVariable(row.clone()));}
 for words in dmb.lists.iter().skip(snapshot.witness.lists) {operations.push(Operation::AppendList(words.to_vec()));}
 if dmb.variable_footer!=snapshot.witness.footer {operations.push(Operation::SetFooter(dmb.variable_footer));}
 operations.push(Operation::WriteClass(dmb.classes[class as usize].clone()));
 let plan=Arc::new(Plan {witness:snapshot.witness,operations});let Ok(bytes)=rmp_serde::to_vec_named(plan.as_ref())else{return;};if bytes.len()>64*1024{return;}
 let mut cache=cache().lock().unwrap_or_else(|error|error.into_inner());retain(&mut cache,key.clone(),plan,bytes.len()*2+key.len()+128);
 if cache.store.is_some(){if cache.pending_bytes.saturating_add(bytes.len())>1024*1024{flush_locked(&mut cache);}if cache.pending_bytes.saturating_add(bytes.len())>1024*1024 {cache.pending.clear();cache.pending_bytes=0;}cache.pending_bytes+=bytes.len();cache.pending.push(Change::Put(Key::new(NAMESPACE,key),bytes));}
}
pub(super) fn resident_bytes()->usize{let cache=cache().lock().unwrap_or_else(|error|error.into_inner());cache.bytes+cache.pending_bytes+cache.missing.iter().map(|key|key.len()+40).sum::<usize>()}
pub(super) fn trim(){let mut cache=cache().lock().unwrap_or_else(|error|error.into_inner());flush_locked(&mut cache);cache.rows.clear();cache.missing.clear();cache.bytes=0;}

pub(super) fn stats()->(usize,usize){let cache=cache().lock().unwrap_or_else(|error|error.into_inner());(cache.hits,cache.misses)}

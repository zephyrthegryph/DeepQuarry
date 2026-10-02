//! Typed declaration operation plans with exact replay witnesses. Unsupported
//! mutation families continue deriving normally; no unobserved table patch is
//! accepted. The same immutable plan can back declaration pages and analysis.
use super::*;
use dm_output::assembly::AssemblyImage;
use std::sync::{Mutex,OnceLock};
use std::collections::VecDeque;
use sha2::{Digest,Sha256};
use serde::{Serialize,Deserialize};
use dm_store::{Store,Key,Change};
use dm_output::object_directory::{AllocationCounts,AllocationMask,ObjectWitness,WitnessObservation,OwnedReference,OwnedTable};
const NAMESPACE:&str="typed-declaration-operations-v6";
const LIMIT:usize=4*1024*1024;
#[derive(Serialize,Deserialize)]
struct Witness {allocation:bool,defining_list:u32,variables:usize,lists:usize,footer:u32,list_lengths:Vec<(u32,usize)>,resource:Option<(String,u32)>}
pub(super) struct Snapshot {witness:Witness,start:AllocationCounts}
#[derive(Clone,Serialize,Deserialize)]
enum ClassProperty {Initial(u8),Text,Maptext,Suffix,Direction,Layer,Geometry(u8),Flags(u64),DefiningList}
impl ClassProperty {
 fn assign(&self,row:&mut byond_dmb::dmb::Class,value:u64){match self {Self::Initial(slot)=>row.initial_ids[*slot as usize]=value as u32,Self::Text=>row.text=value as u32,Self::Maptext=>row.maptext=value as u32,Self::Suffix=>row.suffix=value as u32,Self::Direction=>row.direction=value as u8,Self::Layer=>row.layer_bits=value as u32,Self::Geometry(slot)=>row.maptext_geometry[*slot as usize]=value as u16,Self::Flags(mask)=>row.flags=(row.flags&!mask)|(value&mask),Self::DefiningList=>row.lists_and_procs[4]=value as u32}}
}
#[derive(Serialize,Deserialize)]
enum Operation {Intern {bytes:Vec<u8>,id:u32},WriteProperty {property:ClassProperty,value:u64},AppendVariable(byond_dmb::dmb::Variable),AppendList(Vec<u32>),ExtendList {id:u32,words:Vec<u32>},SetFooter(u32),StaticId {name:String,id:u32}}
#[derive(Serialize,Deserialize)]
pub(super) struct Plan {witness:Witness,object:ObjectWitness,operations:Vec<Operation>,variable:Option<VariableRecipe>,property:Option<PropertyRecipe>}
/// Closed property writes preserve interning order but bind string/resource IDs
/// in the current image. They never inherit historical allocation prefixes.
#[derive(Serialize,Deserialize)]
struct PropertyRecipe {property:ClassProperty,value:PropertyValue,intern:Vec<Vec<u8>>}
#[derive(Serialize,Deserialize)]
enum PropertyValue {Scalar(u64),Text(Vec<u8>),Resource(String)}
fn property_recipe(property:&ClassProperty,value:u64,operations:&[Operation],snapshot:&Snapshot,dmb:&impl AssemblyImage)->Option<PropertyRecipe> {
 if snapshot.witness.allocation||operations.iter().any(|operation|!matches!(operation,Operation::Intern {..}|Operation::WriteProperty {..})){return None;}
 let intern=operations.iter().filter_map(|operation|match operation {Operation::Intern {bytes,..}=>Some(bytes.clone()),_=>None}).collect();
 let value=match property {
  ClassProperty::Initial(2|3|5)|ClassProperty::Text|ClassProperty::Maptext|ClassProperty::Suffix if value!=0xffff=>PropertyValue::Text(dmb.string(u32::try_from(value).ok()?)?.to_vec()),
  ClassProperty::Initial(4) if value!=0xffff=>PropertyValue::Resource(snapshot.witness.resource.as_ref()?.0.clone()),
  ClassProperty::Initial(2|3|4|5)|ClassProperty::Text|ClassProperty::Maptext|ClassProperty::Suffix|ClassProperty::Direction|ClassProperty::Layer|ClassProperty::Geometry(_)|ClassProperty::Flags(_)=>PropertyValue::Scalar(value),
  _=>return None,
 };
 Some(PropertyRecipe {property:property.clone(),value,intern})
}
fn replay_property(recipe:&PropertyRecipe,class:u32,dmb:&mut impl AssemblyImage,strings:&mut StringIndex,resources:&HashMap<String,u32>)->bool {
 // Resolve fallible resource reads before applying any interning writes.
 let resource=match &recipe.value {PropertyValue::Resource(path)=>match resources.get(path){Some(id)=>Some(*id),None=>return false},_=>None};
 for bytes in &recipe.intern {strings.intern_bytes(dmb,bytes);}
 let value=match &recipe.value {PropertyValue::Scalar(value)=>*value,PropertyValue::Text(bytes)=>strings.intern_bytes(dmb,bytes) as u64,PropertyValue::Resource(_)=>resource.unwrap() as u64};
 recipe.property.assign(&mut dmb.classes_mut()[class as usize],value);true
}
/// Allocation-independent writes for closed literal declarations. Destinations
/// are current owner/footer lists, never historical absolute row addresses.
#[derive(Serialize,Deserialize)]
struct VariableRecipe {name:Vec<u8>,kind:u8,value:u32,text:Option<Vec<u8>>,resource:Option<String>,flags:u32,static_name:Option<String>,dynamic:Option<String>,intern:Vec<Vec<u8>>}
fn variable_recipe(source:&str,class:u32,snapshot:&Snapshot,dmb:&impl AssemblyImage,metadata:Option<&TypeMetadataState>)->Option<VariableRecipe>{
 if !snapshot.witness.allocation||dmb.variable_count()!=snapshot.witness.variables+1{return None;}
 let row=dmb.variable(snapshot.witness.variables).ok()?;
 if !matches!(row.kind,0|6|12|42){return None;}
 let declaration=default_plans::declaration(source).ok()?;
 // Failed nonconst evaluation can emit a null placeholder plus dynamic work.
 // A closed recipe must never hide those side effects.
 let dynamic=if row.kind==0&&declaration.initial.as_deref().is_some_and(|value|value.trim()!="null") {
  if !declaration.initial.as_deref().is_some_and(closed_list){return None;}Some(declaration.dynamic.clone().ok()?)
 }else{None};
 let static_name=if declaration.is_static||declaration.is_const {
  let name=class_static_symbol(dmb,class,&declaration.name);if *metadata?.static_ids.get(&name)?!=snapshot.witness.variables as u32{return None;}Some(name)
 }else{None};
 Some(VariableRecipe {name:dmb.string(row.name)?.to_vec(),kind:row.kind,value:row.value,
 text:if row.kind==6 {Some(dmb.string(row.value)?.to_vec())}else{None},
 resource:if row.kind==12 {Some(snapshot.witness.resource.as_ref()?.0.clone())}else{None},
 flags:(if declaration.is_const {3}else if declaration.is_static {1}else{0})|if declaration.is_tmp {4}else{0},static_name,dynamic,intern:Vec::new()})
}
fn replay_variable(recipe:&VariableRecipe,class:u32,dmb:&mut impl AssemblyImage,strings:&mut StringIndex,resources:&HashMap<String,u32>,mut metadata:Option<&mut TypeMetadataState>,pending:&mut Vec<PendingDynamic>)->Result<bool,String>{
 if recipe.static_name.is_some()&&metadata.is_none(){return Ok(false);}
 let defining=dmb.classes()[class as usize].lists_and_procs[4];let footer=*dmb.variable_footer();
 if defining!=0xffff&&dmb.list_words(defining).is_err(){return Ok(false);}
 if recipe.static_name.is_some()&&footer!=0xffff&&dmb.list_words(footer).is_err(){return Ok(false);}
 let base=counts(dmb);let Some(variable)=(OwnedReference {table:OwnedTable::Variable,ordinal:0}).resolve(&base)else{return Ok(false);};
 if recipe.kind==6&&recipe.text.is_none(){return Ok(false);}
 let resource=if recipe.kind==12 {let Some(id)=recipe.resource.as_ref().and_then(|path|resources.get(path))else{return Ok(false);};Some(*id)}else{None};
 if recipe.dynamic.is_some()&&recipe.static_name.is_none()&&std::str::from_utf8(&recipe.name).is_err(){return Ok(false);}
 // Preserve every original intern, including intermediates produced before a
 // dynamic initializer was selected. Physical writes are otherwise redundant.
 for bytes in &recipe.intern {strings.intern_bytes(dmb,bytes);}
 let value=match recipe.kind {6=>strings.intern_bytes(dmb,recipe.text.as_ref().unwrap()),12=>resource.unwrap(),_=>recipe.value};
 if let Some(expression)=&recipe.dynamic {
  let name=if let Some(name)=&recipe.static_name {name.clone()}else{let Some(name)=std::str::from_utf8(&recipe.name).ok()else{return Ok(false);};name.to_owned()};
  pending.push(PendingDynamic {owner:if recipe.static_name.is_some(){None}else{Some(class)},name:name.clone(),expression:expression.clone(),sized_array:false});
  if recipe.static_name.is_some(){metadata.as_deref_mut().unwrap().dynamic_static_scopes.insert(name,class);}
 }
 let name=strings.intern_bytes(dmb,&recipe.name);
 dmb.append_variable(Variable {kind:recipe.kind,value,name}).map_err(|error|error.to_string())?;
 let mut list_ordinal=0;
 if let Some(name)=&recipe.static_name {
  metadata.as_deref_mut().unwrap().static_ids.insert(name.clone(),variable);
  if footer==0xffff {let expected=(OwnedReference {table:OwnedTable::List,ordinal:list_ordinal}).resolve(&base);let actual=dmb.append_list(vec![variable,recipe.flags].into()).map_err(|error|error.to_string())?;debug_assert_eq!(expected,Some(actual));*dmb.variable_footer_mut()=actual;list_ordinal+=1;}
  else {let words=dmb.list_mut(footer).map_err(|error|error.to_string())?;words.extend([variable,recipe.flags]);}
 }
 if defining==0xffff {let expected=(OwnedReference {table:OwnedTable::List,ordinal:list_ordinal}).resolve(&base);let actual=dmb.append_list(vec![variable,recipe.flags].into()).map_err(|error|error.to_string())?;debug_assert_eq!(expected,Some(actual));dmb.classes_mut()[class as usize].lists_and_procs[4]=actual;}
 else {let words=dmb.list_mut(defining).map_err(|error|error.to_string())?;words.extend([variable,recipe.flags]);}
 Ok(true)
}
#[derive(Default)]
struct Cache {root:Option<std::path::PathBuf>,store:Option<Store>,rows:HashMap<String,(Arc<Plan>,usize)>,order:VecDeque<String>,missing:HashSet<String>,bytes:usize,pending:Vec<Change>,pending_bytes:usize,hits:usize,misses:usize}
fn cache()->&'static Mutex<Cache>{static CACHE:OnceLock<Mutex<Cache>>=OnceLock::new();CACHE.get_or_init(||Mutex::new(Cache::default()))}
pub(super) fn key(owner:&str,source:&str)->String {let mut hash=Sha256::new();hash.update(env!("DM_EMISSION_FINGERPRINT"));hash.update((owner.len() as u64).to_le_bytes());hash.update(owner);hash.update(source);format!("{:x}",hash.finalize())}
fn owner(dmb:&impl AssemblyImage,id:u32)->Option<&str>{std::str::from_utf8(dmb.string(dmb.classes().get(id as usize)?.path_string_id())?).ok()}
fn resource(source:&str,resources:&HashMap<String,u32>)->Option<(String,u32)>{let(name,value)=source.split_once('=')?;if name.trim()!="icon"&&!name.trim().starts_with("var/"){return None;}let path=value.trim().strip_prefix('\'')?.strip_suffix('\'')?.replace('\\',"/");Some((path.clone(),*resources.get(&path)?))}
fn numeric(value:&str)->bool {value.bytes().any(|byte|byte.is_ascii_digit())&&value.bytes().all(|byte|byte.is_ascii_digit()||matches!(byte,b'.'|b'+'|b'-'|b'e'|b'E'))&&value.parse::<f32>().is_ok()}
/// Purity is syntactic: no symbol lookup, calls, mutation, or type binding.
/// Normal semantic evaluation still determines the value on the first build.
fn closed_arithmetic(value:&str)->bool {
 if !value.bytes().any(|byte|byte.is_ascii_digit()){return false;}
 // Cheap rejection prevents parsing ordinary named defaults during prefetch.
 if !value.bytes().all(|byte|byte.is_ascii_digit()||byte.is_ascii_whitespace()||matches!(byte,b'.'|b'e'|b'E'|b'+'|b'-'|b'*'|b'/'|b'%'|b'&'|b'|'|b'^'|b'~'|b'!'|b'<'|b'>'|b'='|b'('|b')'|b'?'|b':')){return false;}
 fn closed(expr:&dm_syntax::Expr)->bool {use dm_syntax::ExprKind;match &expr.kind {
  ExprKind::Literal(text)=>numeric(text),ExprKind::Group(value)=>closed(value),
  ExprKind::Unary {op,value}=>matches!(op.as_str(),"+"|"-"|"~"|"!")&&closed(value),
  ExprKind::Binary {op,lhs,rhs}=>matches!(op.as_str(),"+"|"-"|"*"|"/"|"%"|"**"|"&"|"|"|"^"|"<<"|">>"|"=="|"!="|"<"|">"|"<="|">="|"&&"|"||")&&closed(lhs)&&closed(rhs),
  ExprKind::Conditional {condition,then_value,else_value}=>closed(condition)&&closed(then_value)&&closed(else_value),_=>false,
 }}
 const_eval::parsed_expression(value).is_some_and(|expr|closed(&expr))
}
fn closed_list(source:&str)->bool {
 fn closed(expr:&dm_syntax::Expr,depth:usize)->bool {
  if depth>64{return false;}use dm_syntax::ExprKind;
  match &expr.kind {
   ExprKind::Literal(value)=>literal_scalar(value),ExprKind::Ident(name)=>name=="null",
   ExprKind::Group(value)=>closed(value,depth+1),
   ExprKind::Unary {op,value}=>matches!(op.as_str(),"+"|"-"|"~"|"!")&&closed(value,depth+1),
   ExprKind::Binary {op,lhs,rhs}=>matches!(op.as_str(),"="|"+"|"-"|"*"|"/"|"%"|"**"|"&"|"|"|"^"|"<<"|">>"|"=="|"!="|"<"|">"|"<="|">="|"&&"|"||")&&closed(lhs,depth+1)&&closed(rhs,depth+1),
   ExprKind::Call {callee,args}=>matches!(&callee.kind,ExprKind::Ident(name) if name=="list")&&args.iter().all(|arg|closed(arg,depth+1)),_=>false,
  }
 }
 if !source.trim_start().starts_with("list("){return false;}
 const_eval::parsed_expression(source).is_some_and(|expr|closed(&expr,0))
}
fn literal_scalar(value:&str)->bool {value=="null"||numeric(value)||(value.len()>=2&&value.starts_with('"')&&value.ends_with('"')&&!value[1..value.len()-1].contains(['[',']','\\','"']))||(value.len()>=2&&value.starts_with('\'')&&value.ends_with('\''))}
fn literal(value:&str)->bool {value=="null"||numeric(value)||closed_arithmetic(value)||(value.len()>=2&&value.starts_with('"')&&value.ends_with('"')&&!value[1..value.len()-1].contains(['[',']','\\','"']))||(value.len()>=2&&value.starts_with('\'')&&value.ends_with('\''))}
pub(super) fn eligible_variable(source:&str)->bool {let (name,value)=source.split_once('=').unwrap_or((source,"null"));name.trim().starts_with("var/")&&!name.contains(['[',']'])&&(literal(value.trim())||closed_list(value.trim()))}
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
fn retain(cache:&mut Cache,key:String,plan:Arc<Plan>,size:usize){
 if size>LIMIT{return;}let existing=cache.rows.remove(&key);let mut queued=existing.is_some();if let Some((_,old))=&existing {cache.bytes=cache.bytes.saturating_sub(*old);}
 while cache.bytes.saturating_add(size)>LIMIT {let Some(old)=cache.order.pop_front()else{break;};if old==key {queued=false;}if let Some((_,charge))=cache.rows.remove(&old){cache.bytes=cache.bytes.saturating_sub(charge);}}
 if !queued{cache.order.push_back(key.clone());}cache.bytes+=size;cache.missing.remove(&key);cache.rows.insert(key,(plan,size));
}
pub(super) fn prefetch(items:&[&Item]) {
 let mut cache=cache().lock().unwrap_or_else(|error|error.into_inner());let Some(store)=cache.store.clone()else{return;};
 let keys:Vec<_>=items.iter().flat_map(|item|item.children.iter().filter(|child|eligible(&child.header)).map(move|child|Key::new(NAMESPACE,key(item.header.trim(),&child.header)))).filter(|key|!cache.rows.contains_key(&key.name)&&!cache.missing.contains(&key.name)).collect();
 for batch in keys.chunks(4096){default_plans::read_stage_batch(&store,batch,64*1024,4*1024*1024,&mut |key,bytes|{if let Some(bytes)=bytes {if let Some(plan)=decode_plan(&bytes){retain(&mut cache,key.name.clone(),Arc::new(plan),bytes.len()*2+key.name.len()+128);return;}}if cache.missing.len()<16_384 {cache.missing.insert(key.name.clone());}});}
}
pub(super) fn closed_owner_plan(plan:&Plan,resources:&HashMap<String,u32>)->bool {
 if let Some(variable)=&plan.variable {return variable.resource.as_ref().is_none_or(|name|resources.contains_key(name));}
 if let Some(property)=&plan.property {return match &property.value {PropertyValue::Resource(name)=>resources.contains_key(name),_=>true};}
 false
}
pub(super) fn owner_plans(owner:&str,sources:impl Iterator<Item=String>)->HashMap<String,Arc<Plan>> {let cache=cache().lock().unwrap_or_else(|error|error.into_inner());sources.filter_map(|source|{let key=key(owner,&source);cache.rows.get(&key).map(|(plan,_)|(key,plan.clone()))}).collect()}
fn counts(dmb:&impl AssemblyImage)->AllocationCounts {AllocationCounts {strings:dmb.strings().len() as u32,variables:dmb.variable_count() as u32,lists:dmb.list_count() as u32,procedures:dmb.proc_count() as u32,references:dmb.proc_references().len() as u32,instances:dmb.instances().len() as u32}}
fn scalars(witness:&Witness,dmb:Option<&dyn AssemblyImage>,class:u32,resource:Option<&(String,u32)>)->Vec<u64> {
 let mut reads=Vec::new();
 if witness.allocation {reads.push(dmb.map_or(witness.defining_list,|dmb|dmb.classes()[class as usize].lists_and_procs[4]) as u64);reads.push(dmb.map_or(witness.footer,|dmb|*dmb.variable_footer()) as u64);for(id,length)in &witness.list_lengths {reads.push(*id as u64);reads.push(dmb.and_then(|dmb|dmb.list_words(*id).ok()).map_or(*length,|words|words.len()) as u64);}}
 reads.push(resource.map_or(u64::MAX,|(_,id)|*id as u64));reads
}
fn recipe_identity(operations:&[Operation],variable:Option<&VariableRecipe>,property:Option<&PropertyRecipe>)->Option<String>{Some(crate::content_hash::text(crate::content_hash::named(b"",&(operations,variable,property))?))}
fn decode_plan(bytes:&[u8])->Option<Plan>{let plan:Plan=rmp_serde::from_slice(bytes).ok()?;if !plan.object.valid()||(plan.variable.is_some()&&plan.property.is_some())||recipe_identity(&plan.operations,plan.variable.as_ref(),plan.property.as_ref())?!=plan.object.recipe_identity {return None;}Some(plan)}
pub(super) fn replay(source:&str,class:u32,dmb:&mut impl AssemblyImage,strings:&mut StringIndex,resources:&HashMap<String,u32>,mut metadata:Option<&mut TypeMetadataState>,pending:&mut Vec<PendingDynamic>)->Result<bool,String> {
 let Some(owner)=owner(dmb,class)else{return Ok(false);};let key=key(owner,source);
 let plan=super::declaration_objects::current_plan(&key).or_else(||{let mut cache=cache().lock().unwrap_or_else(|error|error.into_inner());cache.misses+=1;cache.rows.get(&key).map(|(plan,_)|Arc::clone(plan))});let Some(plan)=plan else{return Ok(false);};
 if plan.object.semantic_identity!=key{return Ok(false);}
 if let Some(recipe)=&plan.variable {
  if !replay_variable(recipe,class,dmb,strings,resources,metadata,pending)?{return Ok(false);}
  let mut cache=cache().lock().unwrap_or_else(|error|error.into_inner());cache.misses=cache.misses.saturating_sub(1);cache.hits+=1;return Ok(true);
 }
 if let Some(recipe)=&plan.property {
  if !replay_property(recipe,class,dmb,strings,resources){return Ok(false);}
  let mut cache=cache().lock().unwrap_or_else(|error|error.into_inner());cache.misses=cache.misses.saturating_sub(1);cache.hits+=1;return Ok(true);
 }
 if resource(source,resources)!=plan.witness.resource||plan.witness.list_lengths.iter().any(|(id,_)|dmb.list_words(*id).is_err()){return Ok(false);}
 let scalar_reads=scalars(&plan.witness,Some(dmb),class,resource(source,resources).as_ref());
 let observation=WitnessObservation {semantic_identity:&key,recipe_identity:&plan.object.recipe_identity,start:counts(dmb),read_identities:&plan.object.read_identities,scalar_reads:&scalar_reads,unresolved_debug:&[]};
 if metadata.is_none()&&plan.operations.iter().any(|operation|matches!(operation,Operation::StaticId {..})){return Ok(false);}
 let mut next=dmb.strings().len() as u32;let mut new=HashMap::<&[u8],u32>::new();let mut observed_strings=Vec::new();
 for operation in &plan.operations {if let Operation::Intern {bytes,id}=operation {
  let observed=strings.0.get(bytes.as_slice()).copied().or_else(||new.get(bytes.as_slice()).copied()).unwrap_or_else(||{while crate::native_reserved_string_id(next){next+=1;}let assigned=next;next+=1;new.insert(bytes,assigned);assigned});
  let _=id;observed_strings.push(observed);
 }}
 if !plan.object.matches(&observation,std::iter::once(class),observed_strings,std::iter::empty()){return Ok(false);}
 for operation in &plan.operations {match operation {Operation::Intern {bytes,..}=>{strings.intern_bytes(dmb,bytes);},Operation::WriteProperty {property,value}=>property.assign(&mut dmb.classes_mut()[class as usize],*value),Operation::AppendVariable(row)=>{dmb.append_variable(row.clone()).map_err(|error|error.to_string())?;},Operation::AppendList(words)=>{dmb.append_list(words.clone().into()).map_err(|error|error.to_string())?;},Operation::ExtendList {id,words}=>{let list=dmb.list_mut(*id).map_err(|error|error.to_string())?;list.extend(words.iter().copied());},Operation::SetFooter(id)=>*dmb.variable_footer_mut()=*id,Operation::StaticId {name,id}=>{metadata.as_deref_mut().unwrap().static_ids.insert(name.clone(),*id);}}}
 {let mut cache=cache().lock().unwrap_or_else(|error|error.into_inner());cache.misses=cache.misses.saturating_sub(1);cache.hits+=1;}
 Ok(true)
}
pub(super) fn begin(source:&str,class:u32,dmb:&impl AssemblyImage,resources:&HashMap<String,u32>)->Snapshot {
 let defining_list=dmb.classes()[class as usize].lists_and_procs[4];let mut list_lengths=Vec::new();
 for id in [defining_list,*dmb.variable_footer()] {if id!=0xffff&&!list_lengths.iter().any(|(other,_)|*other==id) {if let Ok(words)=dmb.list_words(id){list_lengths.push((id,words.len()));}}}
 Snapshot {start:counts(dmb),witness:Witness {allocation:eligible_variable(source),defining_list,variables:dmb.variable_count(),lists:dmb.list_count(),footer:*dmb.variable_footer(),list_lengths,resource:resource(source,resources)}}
}
pub(super) fn record(source:&str,class:u32,snapshot:Snapshot,dmb:&impl AssemblyImage,strings:Vec<procedure_fragments::StringRecipe>,metadata:Option<&TypeMetadataState>){
 let Some(owner)=owner(dmb,class)else{return;};let key=key(owner,source);
 let mut operations=Vec::new();for operation in strings {match operation {procedure_fragments::StringRecipe::Bytes {old_id,bytes}=>operations.push(Operation::Intern {bytes:bytes.to_vec(),id:old_id}),procedure_fragments::StringRecipe::Debug {..}=>return,}}
 for (id,length) in &snapshot.witness.list_lengths {let Ok(words)=dmb.list_words(*id)else{return;};if words.len()<*length{return;}if words.len()>*length {operations.push(Operation::ExtendList {id:*id,words:words[*length..].to_vec()});}}
 for id in snapshot.witness.variables..dmb.variable_count() {let Ok(row)=dmb.variable(id)else{return;};operations.push(Operation::AppendVariable(row));}
 for id in snapshot.witness.lists..dmb.list_count() {let Ok(words)=dmb.list_words(id as u32)else{return;};operations.push(Operation::AppendList(words.to_vec()));}
 if *dmb.variable_footer()!=snapshot.witness.footer {operations.push(Operation::SetFooter(*dmb.variable_footer()));}
 if let Some(metadata)=metadata {
  if let Ok(plan)=default_plans::declaration(source) {if plan.is_static||plan.is_const {
   let name=class_static_symbol(dmb,class,&plan.name);let Some(id)=metadata.static_ids.get(&name)else{return;};
   operations.push(Operation::StaticId {name,id:*id});
  }}
 }
 let row=&dmb.classes()[class as usize];
 let name=source.split('=').next().unwrap_or(source).trim();
 let (property,value)=match name {
  "name"=>(ClassProperty::Initial(2),row.initial_ids[2] as u64),"desc"=>(ClassProperty::Initial(3),row.initial_ids[3] as u64),"icon"=>(ClassProperty::Initial(4),row.initial_ids[4] as u64),"icon_state"=>(ClassProperty::Initial(5),row.initial_ids[5] as u64),
  "text"=>(ClassProperty::Text,row.text as u64),"maptext"=>(ClassProperty::Maptext,row.maptext as u64),"suffix"=>(ClassProperty::Suffix,row.suffix as u64),"dir"=>(ClassProperty::Direction,row.direction as u64),"layer"=>(ClassProperty::Layer,row.layer_bits as u64),
  "maptext_width"=>(ClassProperty::Geometry(0),row.maptext_geometry[0] as u64),"maptext_height"=>(ClassProperty::Geometry(1),row.maptext_geometry[1] as u64),"maptext_x"=>(ClassProperty::Geometry(2),row.maptext_geometry[2] as u64),"maptext_y"=>(ClassProperty::Geometry(3),row.maptext_geometry[3] as u64),
  "density"=>(ClassProperty::Flags(2),row.flags&2),"opacity"=>(ClassProperty::Flags(1),row.flags&1),"mouse_opacity"=>(ClassProperty::Flags(0x3000),row.flags&0x3000),"animate_movement"=>(ClassProperty::Flags(0xc400),row.flags&0xc400),
  _ if snapshot.witness.allocation=>(ClassProperty::DefiningList,row.lists_and_procs[4] as u64),_=>return,
 };
 let symbolic_property=property_recipe(&property,value,&operations,&snapshot,dmb);
 operations.push(Operation::WriteProperty {property,value});
 let property=symbolic_property;
 let mut variable=variable_recipe(source,class,&snapshot,dmb,metadata);
 if let Some(recipe)=&mut variable {recipe.intern=operations.iter().filter_map(|operation|match operation {Operation::Intern {bytes,..}=>Some(bytes.clone()),_=>None}).collect();}
 if snapshot.witness.allocation&&variable.is_none(){return;}
 // Symbolic plans do not need duplicate physical writes and old string IDs.
 if variable.is_some()||property.is_some(){operations.clear();}
 let Some(recipe)=recipe_identity(&operations,variable.as_ref(),property.as_ref())else{return;};
 let scalar_reads=scalars(&snapshot.witness,None,class,snapshot.witness.resource.as_ref());
 let string_ids=operations.iter().filter_map(|operation|if let Operation::Intern {id,..}=operation{Some(*id)}else{None}).collect();
 let object=ObjectWitness {semantic_identity:key.clone(),recipe_identity:recipe,start:snapshot.start,allocation_mask:if snapshot.witness.allocation {AllocationMask::VARIABLES.union(AllocationMask::LISTS)}else{AllocationMask::NONE},symbol_ids:vec![class],string_ids,debug_ids:Vec::new(),read_identities:Vec::new(),scalar_reads,unresolved_debug:Vec::new()};
 let plan=Arc::new(Plan {witness:snapshot.witness,object,operations,variable,property});let Ok(bytes)=rmp_serde::to_vec_named(plan.as_ref())else{return;};if bytes.len()>64*1024{return;}
 let mut cache=cache().lock().unwrap_or_else(|error|error.into_inner());retain(&mut cache,key.clone(),plan,bytes.len()*2+key.len()+128);
 if cache.store.is_some(){if cache.pending_bytes.saturating_add(bytes.len())>1024*1024{flush_locked(&mut cache);}if cache.pending_bytes.saturating_add(bytes.len())>1024*1024 {cache.pending.clear();cache.pending_bytes=0;}cache.pending_bytes+=bytes.len();cache.pending.push(Change::Put(Key::new(NAMESPACE,key),bytes));}
}
pub(super) fn resident_bytes()->usize{let cache=cache().lock().unwrap_or_else(|error|error.into_inner());cache.bytes+cache.pending_bytes+cache.order.iter().map(|key|key.capacity()+32).sum::<usize>()+cache.missing.iter().map(|key|key.len()+40).sum::<usize>()}
pub(super) fn trim(){let mut cache=cache().lock().unwrap_or_else(|error|error.into_inner());flush_locked(&mut cache);cache.rows.clear();cache.order.clear();cache.missing.clear();cache.bytes=0;}

pub(super) fn stats()->(usize,usize){let cache=cache().lock().unwrap_or_else(|error|error.into_inner());(cache.hits,cache.misses)}

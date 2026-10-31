//! Unique reactive policy facts over authenticated original inputs, not a DM model.
//! WORKING DATA; no native result registration until complete producer parity.
use crate::{reactive_original_source::{ReadSource,SelectedCallable},reactive_annotations_policy::Annotations,reactive_reads_native::Failure};
use std::{collections::{BTreeMap,BTreeSet},io};
use crate::reactive_policy_storage::{Map,Set,Storage};
pub(crate) struct PolicyFacts{pub annotations:PolicyAnnotations,tracked:Map<String,Map<String,bool>>,relations:Map<String,Set<String>>,stats:Vec<(String,String)>}
struct Builder{annotations:Annotations,tracked:BTreeMap<String,BTreeMap<String,bool>>,relations:BTreeMap<String,BTreeSet<String>>,stats:Vec<(String,String)>}
pub(crate) struct PolicyAnnotations{pub reads_as:Map<(String,String),(String,Option<String>)>,pub reads_from:Map<String,Vec<String>>,pub lookups:Map<String,crate::reactive_annotations_policy::LookupDeclaration>,pub relations:Map<String,Set<String>>,pub accessors:Map<String,(String,String)>,pub capkey_accessors:Map<String,String>,pub summaries:Map<(String,String),crate::reactive_annotations_policy::ProcSummary>}
impl PolicyFacts{
 pub(crate) fn capture(source:&ReadSource<'_>,checkpoint:&mut dyn FnMut()->io::Result<()>)->Result<Self,Failure>{
  // Reuse the one captured raw-marker producer. This is policy-only output,
  // never another declaration/parser roster or a source acquisition.
  let rows=source.marker_rows_checked(checkpoint)?;
  let annotations=crate::reactive_annotations_native::original_annotations_from_rows(source,&rows,checkpoint)?;
  let mut out=Builder{annotations,tracked:BTreeMap::new(),relations:BTreeMap::new(),stats:Vec::new()};
  source.raw_metadata_checked(checkpoint,&mut|relative,event|{
   use crate::raw_reactive_metadata_policy::Event;
   let(owner,name,relation)=match event{Event::Tracked{owner,name}=>(owner,name,false),Event::Relation{owner,name}=>(owner,name,true)};
   source.reserve(owner.len().checked_add(name.len()).and_then(|n|n.checked_mul(8)).and_then(|n|n.checked_add(2048)))?;
   if relation{out.relations.entry(owner.to_owned()).or_default().insert(name.to_owned());}
   else{let explicit=relative!=crate::auto_setter_calls_policy::AUTO_REL;let named=out.tracked.entry(owner.to_owned()).or_default().entry(name.to_owned()).or_default();*named|=explicit;}
   Ok::<_,Failure>(())
  })?;
  for m in rows.markers.iter().filter(|m|m.name=="STAT"){
   checkpoint()?;
   if let(Some(owner),Some(name))=(m.args.first(),m.args.get(1)){
    source.reserve(owner.len().checked_add(name.len()).and_then(|n|n.checked_mul(8)).and_then(|n|n.checked_add(1024)))?;
    out.stats.try_reserve(1).map_err(|e|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,e)))?;
    out.stats.push((owner.clone(),name.clone()));
   }
  }
  checkpoint()?;source.require()?;let frozen=Self::freeze(out,source.budget(),checkpoint);if matches!(&frozen,Err(Failure::Operational(_))){return frozen}checkpoint()?;source.require().map_err(|message|if source.budget().denied(){Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message))}else{Failure::Unsupported(message)})?;frozen
 }
 fn chain(&self,source:&ReadSource<'_>,owner:&str,name:&str,contains:impl Fn(&str)->bool,limit:Option<usize>,setter:bool)->Result<bool,Failure>{
  // Borrow SAME parent graph, no copied type table/ancestor strings/cache.
  let mut current=Some(owner);let mut guard=0usize;let total=source.inputs().archive().tree().types().len();
  while let Some(t)=current{
   source.require()?;
   if contains(t){return Ok(true)}
   if setter{
    source.reserve(name.len().checked_add(64).and_then(|n|n.checked_mul(4)))?;
    if source.own_callable_exists(t,&format!("__setter_{name}"))?{return Ok(true)}
   }
   guard+=1;if limit.is_some_and(|n|guard>n){break}
   if guard>total.saturating_add(1){return Err("reactive original parent graph cycle".into())}
   current=source.parent_type(t)?.filter(|p|*p!=t&&*p!="/");
  }
  Ok(false)
 }
 pub(crate) fn reads_as<'f>(&'f self,source:&ReadSource<'_>,owner:&str,name:&str)->Result<Option<&'f (String,Option<String>)>,Failure>{
  let mut current=Some(owner);let mut guard=0;
  while let Some(t)=current{
   source.require()?;
   if let Some((_,value))=self.annotations.reads_as.iter().find(|((ty,proc),_)|ty==t&&proc==name){return Ok(Some(value))}
   guard+=1;if guard>64{break}current=source.parent_type(t)?.filter(|p|*p!=t&&*p!="/");
  }
  Ok(None)
 }
 pub(crate) fn is_relation(&self,source:&ReadSource<'_>,owner:&str,name:&str)->Result<bool,Failure>{
  if self.chain(source,owner,name,|t|self.relations.get(t).is_some_and(|names|names.contains(name)),Some(64),false)?{return Ok(true)}
  self.chain(source,owner,name,|t|self.annotations.relations.get(t).is_some_and(|names|names.contains(name)),Some(64),false)
 }
 /// Auto inference ignores its own generated declarations. The explicit bit
 /// is a union at the existing name, not a second copied tracked-name table.
 pub(crate) fn auto_declared_reactive(&self,source:&ReadSource<'_>,owner:&str,name:&str)->Result<bool,Failure>{
  Ok(self.chain(source,owner,name,|t|self.tracked.get(t).and_then(|names|names.get(name)).copied().unwrap_or(false),Some(64),false)?||self.is_relation(source,owner,name)?||self.is_stat(source,owner,name)?||self.is_derived(source,owner,name)?)
 }
 pub(crate) fn is_tracked(&self,source:&ReadSource<'_>,owner:&str,name:&str)->Result<bool,Failure>{self.chain(source,owner,name,|t|self.tracked.get(t).is_some_and(|names|names.contains_key(name)),None,true)}
 pub(crate) fn is_stat(&self,source:&ReadSource<'_>,owner:&str,name:&str)->Result<bool,Failure>{for(t,v)in &self.stats{if v==name&&source.is_subtype(owner,t)?{return Ok(true)}}Ok(false)}
 pub(crate) fn is_derived(&self,source:&ReadSource<'_>,owner:&str,name:&str)->Result<bool,Failure>{
  source.reserve(name.len().checked_add(64).and_then(|n|n.checked_mul(4)))?;
  Ok(!matches!(source.callable(owner,&format!("derive_{name}"))?,SelectedCallable::Missing))
 }
}

impl PolicyFacts{fn freeze(input:Builder,budget:&std::sync::Arc<crate::captured_generator_budget::Budget>,poll:&mut dyn FnMut()->io::Result<()>)->Result<Self,Failure>{
 let Builder{annotations,tracked,relations,stats}=input;let Annotations{reads_as,reads_from,lookups,relations:annotation_relations,accessors,capkey_accessors,summaries}=annotations;
 let annotations=PolicyAnnotations{reads_as:Map::freeze(reads_as.into_iter(),budget,poll)?,reads_from:Map::freeze(reads_from.into_iter(),budget,poll)?,lookups:Map::freeze(lookups.into_iter(),budget,poll)?,relations:Map::freeze_values(annotation_relations.into_iter(),budget,poll,|set,budget,poll|Set::freeze(set.into_iter(),budget,poll))?,accessors:Map::freeze(accessors.into_iter(),budget,poll)?,capkey_accessors:Map::freeze(capkey_accessors.into_iter(),budget,poll)?,summaries:Map::freeze(summaries.into_iter(),budget,poll)?};
 Ok(Self{annotations,tracked:Map::freeze_values(tracked.into_iter(),budget,poll,|map,budget,poll|Map::freeze(map.into_iter(),budget,poll))?,relations:Map::freeze_values(relations.into_iter(),budget,poll,|set,budget,poll|Set::freeze(set.into_iter(),budget,poll))?,stats})
}
 pub(crate) fn visit_storage(&self,mut visit:impl FnMut(usize,usize)){let visit=&mut visit;self.annotations.reads_as.storage(visit);self.annotations.reads_from.storage(visit);self.annotations.lookups.storage(visit);self.annotations.relations.storage(visit);self.annotations.accessors.storage(visit);self.annotations.capkey_accessors.storage(visit);self.annotations.summaries.storage(visit);self.tracked.storage(visit);self.relations.storage(visit);self.stats.storage(visit);}
 pub(crate) fn retained_charge(&self)->Option<usize>{let mut sum=Some(std::mem::size_of::<Self>());self.visit_storage(|_,capacity|sum=sum.and_then(|n|n.checked_add(capacity)));sum}
}
impl Storage for crate::reactive_annotations_policy::LookupDeclaration{fn storage(&self,visit:&mut dyn FnMut(usize,usize)){self.registry.storage(visit);self.identity_key.storage(visit);self.result.storage(visit)}}
impl Storage for crate::reactive_annotations_policy::ProcSummary{fn storage(&self,visit:&mut dyn FnMut(usize,usize)){self.reads.storage(visit);self.writes.storage(visit)}}

impl PolicyFacts{pub(crate) fn fingerprint(&self,poll:&dyn Fn()->io::Result<()>)->Result<u128,Failure>{
 struct Encode<'a>{hash:blake3::Hasher,poll:&'a dyn Fn()->io::Result<()>}impl Encode<'_>{fn number(&mut self,n:usize)->Result<(),Failure>{(self.poll)()?;self.hash.update(&(n as u128).to_le_bytes());Ok(())}fn text(&mut self,text:&str)->Result<(),Failure>{self.number(text.len())?;self.hash.update(text.as_bytes());Ok(())}fn strings(&mut self,rows:&[String])->Result<(),Failure>{self.number(rows.len())?;for row in rows{self.text(row)?;}Ok(())}}
 let mut e=Encode{hash:blake3::Hasher::new(),poll};e.hash.update(b"unique-policy-facts-ordered-v1\0");e.number(self.annotations.reads_as.len())?;for((owner,proc),(key,via))in self.annotations.reads_as.iter(){e.text(owner)?;e.text(proc)?;e.text(key)?;e.number(usize::from(via.is_some()))?;if let Some(via)=via{e.text(via)?;}}
 e.number(self.annotations.reads_from.len())?;for(name,params)in self.annotations.reads_from.iter(){e.text(name)?;e.strings(params)?;}e.number(self.annotations.lookups.len())?;for(name,value)in self.annotations.lookups.iter(){e.text(name)?;e.text(&value.registry)?;e.text(&value.identity_key)?;e.number(value.argument)?;e.text(&value.result)?;}
 e.number(self.annotations.relations.len())?;for(owner,names)in self.annotations.relations.iter(){e.text(owner)?;e.number(names.len())?;for name in names.iter(){e.text(name)?;}}e.number(self.annotations.accessors.len())?;for(name,(system,var))in self.annotations.accessors.iter(){e.text(name)?;e.text(system)?;e.text(var)?;}e.number(self.annotations.capkey_accessors.len())?;for(name,key)in self.annotations.capkey_accessors.iter(){e.text(name)?;e.text(key)?;}
 e.number(self.annotations.summaries.len())?;for((owner,proc),summary)in self.annotations.summaries.iter(){e.text(owner)?;e.text(proc)?;e.strings(&summary.reads)?;e.strings(&summary.writes)?;}e.number(self.tracked.len())?;for(owner,names)in self.tracked.iter(){e.text(owner)?;e.number(names.len())?;for(name,explicit)in names.iter(){e.text(name)?;e.number(usize::from(*explicit))?;}}e.number(self.relations.len())?;for(owner,names)in self.relations.iter(){e.text(owner)?;e.number(names.len())?;for name in names.iter(){e.text(name)?;}}e.number(self.stats.len())?;for(owner,name)in &self.stats{e.text(owner)?;e.text(name)?;}poll()?;let digest=e.hash.finalize();Ok(u128::from_le_bytes(digest.as_bytes()[..16].try_into().unwrap()))
}}

impl PolicyFacts{pub(crate) fn tracked_names(&self)->impl Iterator<Item=&str>{self.tracked.values().flat_map(|names|names.keys().map(String::as_str))}}

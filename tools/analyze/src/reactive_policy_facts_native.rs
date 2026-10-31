//! Unique reactive policy facts over authenticated original inputs, not a DM model.
//! WORKING DATA; no native result registration until complete producer parity.
use crate::{reactive_original_source::{ReadSource,SelectedCallable},reactive_annotations_policy::Annotations,reactive_reads_native::Failure};
use std::{collections::{BTreeMap,BTreeSet},io};
pub(crate) struct PolicyFacts{
 pub annotations:Annotations,
 tracked:BTreeMap<String,BTreeMap<String,bool>>,
 relations:BTreeMap<String,BTreeSet<String>>,
 stats:Vec<(String,String)>,
}
impl PolicyFacts{
 pub(crate) fn capture(source:&ReadSource<'_>,checkpoint:&mut dyn FnMut()->io::Result<()>)->Result<Self,Failure>{
  // Reuse the one captured raw-marker producer. This is policy-only output,
  // never another declaration/parser roster or a source acquisition.
  let rows=source.marker_rows_checked(checkpoint)?;
  let annotations=crate::reactive_annotations_native::original_annotations_from_rows(source,&rows,checkpoint)?;
  let mut out=Self{annotations,tracked:BTreeMap::new(),relations:BTreeMap::new(),stats:Vec::new()};
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
  checkpoint()?;source.require()?;Ok(out)
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

//! Ephemeral original source rows for whole keys. Not a Sem/Decls/type model.
use crate::{captured_raw_policy::CapturedRawPolicy,captured_generator_budget::Budget,captured_marker_rows::OwnedMarker,raw_key_calls_policy::KeyRef};
use dm_analysis::{policy_inputs::PolicyInputs,policy_body_demand::PolicyFailure};
use std::{collections::{BTreeMap,HashSet},io,sync::Arc};
pub(crate) struct Sources{pub markers:Vec<OwnedMarker>,pub entry_ops:Vec<(String,String)>,pub defines:HashSet<String>,pub key_refs:Vec<KeyRef>,pub bad_sources:Vec<(String,u32,String)>}
pub(crate) struct System{pub known:bool,pub requested:BTreeMap<String,bool>,types:Vec<String>}
pub(crate) type Systems=BTreeMap<String,System>;
fn oom(text:impl Into<String>)->PolicyFailure{PolicyFailure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,text.into()))}
fn overflow()->PolicyFailure{oom("keys source projection accounting overflow")}
fn charge(b:&Budget,n:usize)->Result<(),PolicyFailure>{b.charge(n).map_err(oom)}
fn intact(raw:&CapturedRawPolicy)->Result<(),PolicyFailure>{raw.tree.captured_violation().map_or(Ok(()),|e|Err(e.into()))}
fn own(b:&Budget,s:&str)->Result<String,PolicyFailure>{let mut text=String::new();if !b.string(&mut text,s){return Err(oom("keys source string admission denied"))}Ok(text)}
fn source_rows(raw:&CapturedRawPolicy,inputs:&PolicyInputs,b:&Arc<Budget>,poll:&mut impl FnMut()->io::Result<()>)->Result<Sources,PolicyFailure>{
 poll().map_err(PolicyFailure::Operational)?;
 charge(b,raw.tree.files.len().checked_mul(256).and_then(|n|n.checked_add(4096)).ok_or_else(overflow)?)?;
 raw.validate_current_raw_roster(inputs)?;intact(raw)?;
 // Original Decls sorts ONLY markers by manifest order; all other rows retain
 // Tree.CODE_DM file order. Never use the sorted marker roster for call facts.
 let order=crate::captured_sparse_slots::captured_order(raw,inputs,b)?;
 let collected=crate::captured_marker_rows::collect_admitted(raw,&order,b,crate::keys_policy::MARKERS,true,&mut||poll().map_err(PolicyFailure::Operational))?;
 let mut out=Sources{markers:collected.markers,entry_ops:Vec::new(),defines:HashSet::new(),key_refs:Vec::new(),bad_sources:Vec::new()};
 drop(collected.engine_sources);
 let files=raw.tree.select(&crate::tree::CODE_DM);
 for f in files{
  poll().map_err(PolicyFailure::Operational)?;intact(raw)?;
  let marker=f.marker();intact(raw)?;if let Some(e)=f.captured_budget_error(){return Err(oom(e))}
  let lines=marker.as_str().bytes().filter(|b|*b==b'\n').count().checked_add(1).ok_or_else(overflow)?;
  charge(b,lines.checked_mul(4).and_then(|n|n.checked_add(128)).ok_or_else(overflow)?)?;
  let mut starts=Vec::new();starts.try_reserve_exact(lines).map_err(|_|{b.deny();oom("keys line projection allocation denied")})?;starts.push(0);
  for(i,byte)in marker.as_str().bytes().enumerate(){if byte==b'\n'{starts.push(u32::try_from(i+1).map_err(|_|overflow())?);}}
  crate::raw_key_calls_policy::visit_headers_admitted(marker.as_str(),|owner,name|{
   if b.row(&mut out.entry_ops){match(own(b,owner),own(b,name)){(Ok(owner),Ok(name))=>out.entry_ops.push((owner,name)),_=>b.deny()}}
  },|name|{
   if b.charge(256).is_ok(){if let Ok(name)=own(b,name){out.defines.insert(name);}}
  },|bytes|{poll().map_err(PolicyFailure::Operational)?;charge(b,bytes)},overflow)?;
  crate::raw_key_calls_policy::visit_calls_admitted(&f.rel,marker.as_str(),&starts,|key|{
   if b.row(&mut out.key_refs){out.key_refs.push(key);}
  },|bad|{if b.row(&mut out.bad_sources){out.bad_sources.push(bad);}},|bytes|{poll().map_err(PolicyFailure::Operational)?;charge(b,bytes)},overflow)?;
  b.require().map_err(oom)?;intact(raw)?;
 }
 poll().map_err(PolicyFailure::Operational)?;b.require().map_err(oom)?;Ok(out)
}
pub(crate) fn collect(raw:&CapturedRawPolicy,inputs:&PolicyInputs,b:&Arc<Budget>,poll:&mut impl FnMut()->io::Result<()>)->Result<Sources,PolicyFailure>{
 let pending=source_rows(raw,inputs,b,poll);
 if matches!(&pending,Err(PolicyFailure::Operational(_))){return pending}
 if b.denied(){return Err(oom("keys source projection admission denied"))}pending
}
/// Only requested accessor membership is retained. Existing raw own-var matcher
/// remains unique; no inherited fields or normalized compiler symbol table.
pub(crate) fn systems(raw:&CapturedRawPolicy,rows:&Sources,b:&Arc<Budget>,poll:&mut impl FnMut()->io::Result<()>)->Result<Systems,PolicyFailure>{
 let mut requested:Systems=BTreeMap::new();
 for marker in rows.markers.iter().filter(|m|m.name=="SYSTEM_ACCESSOR"){
  poll().map_err(PolicyFailure::Operational)?;
  let(Some(system),Some(key))=(marker.args.first(),marker.args.get(2))else{continue};
  let Some(var)=key.trim().strip_prefix("nameof(").and_then(|s|s.strip_suffix(')')).map(str::trim)else{continue};
  if !requested.contains_key(system.as_str()){
   charge(b,system.len().checked_mul(8).and_then(|n|n.checked_add(1024)).ok_or_else(overflow)?)?;
   let name=own(b,system)?;let types=crate::system_accessors_policy::system_types(system);
   requested.insert(name,System{known:false,requested:BTreeMap::new(),types});
  }
  let row=requested.get_mut(system.as_str()).unwrap();
  if !row.requested.contains_key(var){charge(b,256)?;row.requested.insert(own(b,var)?,false);}
 }
 charge(b,raw.tree.files.len().checked_mul(32).and_then(|n|n.checked_add(4096)).ok_or_else(overflow)?)?;
 for file in raw.tree.select(&crate::tree::CODE_DM){
  poll().map_err(PolicyFailure::Operational)?;intact(raw)?;
  if requested.is_empty(){continue}
  let code=file.code();intact(raw)?;if let Some(e)=file.captured_budget_error(){return Err(oom(e))}
  // Do not retain a file×system matrix or all own fields. The old candidate
  // substring/run-prefix policy is applied independently for each request.
  for(name,system)in &mut requested{
   poll().map_err(PolicyFailure::Operational)?;
   if !crate::system_accessors_policy::file_mentions_system_with_types(&code.text,name,&system.types){continue}
   if code.text.lines().any(|line|system.types.iter().any(|ty|line.trim_end()==ty)){system.known=true;}
   let clean=file.clean();intact(raw)?;if let Some(e)=file.captured_budget_error(){return Err(oom(e))}
   crate::raw_type_vars_policy::visit(&clean.text,|owner,var|{
    if system.types.iter().any(|ty|ty==owner){system.known=true;if let Some(found)=system.requested.get_mut(var){*found=true;}}
   });
   intact(raw)?;
  }
 }
 poll().map_err(PolicyFailure::Operational)?;b.require().map_err(oom)?;Ok(requested)
}

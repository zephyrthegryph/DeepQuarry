//! Dependency aggregation over the SAME ordered read rows. Source discovery and
//! current-source authority remain with the caller; no missing provider defaults.
use std::collections::{BTreeMap,BTreeSet};
use crate::{reactive_dependency_policy::{View,draw_hop_heard},reactive_read_facts::ReadKind,reactive_facts::{DepsAnalysis,Untracked},key_policy_control as kc};

pub(crate) fn row<C:kc::Control,T>(c:&mut C,rows:&mut Vec<T>)->Result<(),C::Error>{if !C::CHECKED||rows.len()<rows.capacity(){return Ok(())}let requested=rows.capacity().checked_mul(2).map(|n|n.max(4)).ok_or_else(||c.overflow())?;kc::reserve(c,||requested.checked_mul(std::mem::size_of::<T>())?.checked_mul(4)?.checked_add(64))?;rows.try_reserve_exact(requested-rows.len()).map_err(|_|c.allocation_failed())?;if rows.capacity()>requested.saturating_mul(4){return Err(c.allocation_failed())}Ok(())}
fn node<C:kc::Control>(c:&mut C)->Result<(),C::Error>{kc::reserve(c,||Some(256))}
fn own<C:kc::Control>(c:&mut C,s:&str)->Result<String,C::Error>{kc::own(c,s)}
fn insert<C:kc::Control>(c:&mut C,set:&mut BTreeSet<String>,s:&str)->Result<(),C::Error>{if !set.contains(s){node(c)?;set.insert(own(c,s)?);}Ok(())}
fn pair<C:kc::Control>(c:&mut C,set:&mut BTreeSet<(String,String)>,a:&str,b:&str)->Result<(),C::Error>{c.checkpoint()?;node(c)?;set.insert((own(c,a)?,own(c,b)?));Ok(())}
pub fn note_reads<C:kc::Control>(view:View<'_>,into:&mut BTreeSet<(String,String)>,c:&mut C)->Result<(),C::Error>{for read in view.reads(){c.checkpoint()?;if read.kind==ReadKind::Var&&!read.owner.is_empty(){pair(c,into,&read.owner,&read.var)?;}}Ok(())}
pub fn note_stat_reads<C:kc::Control>(view:View<'_>,into:&mut BTreeSet<String>,c:&mut C)->Result<(),C::Error>{for read in view.reads(){c.checkpoint()?;match read.kind{ReadKind::System=>insert(c,into,&read.var)?,ReadKind::Var|ReadKind::Accessor if read.root=="holder"=>{insert(c,into,&read.var)?;for hop in &read.hops{insert(c,into,hop.trim_end_matches("[]"))?;}},_=>{}}}Ok(())}
/// The complete old result schema. BTree row order and each untracked Vec order
/// remain unchanged; this is aggregation, never an ordering normalizer.
pub struct Fold{pub analysis:DepsAnalysis}
impl Default for Fold{fn default()->Self{Self{analysis:DepsAnalysis{consumers:BTreeMap::new(),draws:BTreeSet::new(),leaves:Vec::new(),draw_reads:BTreeMap::new(),draw_keys:BTreeMap::new(),draw_hops:BTreeMap::new(),draw_links:BTreeMap::new(),verb_reads:BTreeMap::new(),stat_reads:BTreeSet::new(),reads:BTreeSet::new(),candidates:BTreeSet::new(),sampled:BTreeMap::new()}}}}
impl Fold{
 pub fn sample<C:kc::Control>(&mut self,id:&str,view:View<'_>,c:&mut C)->Result<(),C::Error>{
  for (rel,line) in view.sampled(){c.checkpoint()?;if !self.analysis.sampled.contains_key(id){node(c)?;self.analysis.sampled.insert(own(c,id)?,BTreeSet::new());}let rows=self.analysis.sampled.get_mut(id).unwrap();if !rows.iter().any(|(r,l)|r==rel&&l==line){node(c)?;rows.insert((own(c,rel)?,*line));}}
  Ok(())
 }
 pub fn consumer<C:kc::Control>(&mut self,id:&str,view:View<'_>,untracked:Vec<Untracked>,stat:bool,first:bool,c:&mut C)->Result<(),C::Error>{
  note_reads(view,&mut self.analysis.reads,c)?;if stat{note_stat_reads(view,&mut self.analysis.stat_reads,c)?;}
  if !first||!self.analysis.consumers.contains_key(id){if !self.analysis.consumers.contains_key(id){node(c)?;}let key=own(c,id)?;self.analysis.consumers.insert(key,untracked);}Ok(())
 }
 pub fn draw<C:kc::Control>(&mut self,owner:&str,id:&str,view:View<'_>,untracked:Vec<Untracked>,capability_keys:&BTreeSet<String>,canonical:&mut impl FnMut(&mut C,&str)->Result<String,C::Error>,c:&mut C)->Result<(),C::Error>{
 note_reads(view,&mut self.analysis.reads,c)?;self.sample(id,view,c)?;let rows=draw_projection(view,capability_keys,canonical,c)?;
 for map in [&mut self.analysis.draw_reads,&mut self.analysis.draw_keys,&mut self.analysis.draw_hops,&mut self.analysis.draw_links]{if !map.contains_key(owner){node(c)?;}}
 self.analysis.draw_reads.insert(own(c,owner)?,rows.reads);self.analysis.draw_keys.insert(own(c,owner)?,rows.keys);self.analysis.draw_hops.insert(own(c,owner)?,rows.hops);self.analysis.draw_links.insert(own(c,owner)?,rows.links);
 if !self.analysis.consumers.contains_key(id){node(c)?;}self.analysis.consumers.insert(own(c,id)?,untracked);insert(c,&mut self.analysis.draws,id)?;Ok(())}
 pub fn verbs<C:kc::Control>(&mut self,id:&str,view:View<'_>,untracked:&[Untracked],c:&mut C)->Result<(),C::Error>{
  note_reads(view,&mut self.analysis.reads,c)?;let mut vars=BTreeSet::new();for read in view.reads(){c.checkpoint()?;if read.root=="holder"&&read.kind==ReadKind::Var{insert(c,&mut vars,if read.hops.is_empty(){&read.var}else{read.hops[0].trim_end_matches("[]")})?;}}
  let unresolved=untracked.iter().any(|row|row.what.starts_with('?'));if !self.analysis.verb_reads.contains_key(id){node(c)?;}self.analysis.verb_reads.insert(own(c,id)?,(vars,unresolved));Ok(())
 }
 pub fn ui<C:kc::Control>(&mut self,view:View<'_>,c:&mut C)->Result<(),C::Error>{for read in view.reads(){c.checkpoint()?;if read.kind==ReadKind::Var&&!read.owner.is_empty()&&read.owner!="/datum"{pair(c,&mut self.analysis.reads,&read.owner,&read.var)?;}}Ok(())}
}

#[derive(Default)]pub struct DrawProjection{pub reads:BTreeSet<String>,pub keys:BTreeSet<String>,pub hops:BTreeSet<String>,pub links:BTreeSet<String>}
pub fn draw_projection<C:kc::Control>(view:View<'_>,capability_keys:&BTreeSet<String>,canonical:&mut impl FnMut(&mut C,&str)->Result<String,C::Error>,c:&mut C)->Result<DrawProjection,C::Error>{let mut out=DrawProjection::default();
  for read in view.reads(){c.checkpoint()?;
   if read.root=="holder"&&read.kind==ReadKind::Var&&!read.hops.is_empty(){insert(c,&mut out.links,read.hops[0].trim_end_matches("[]"))?;}
   if read.kind==ReadKind::Var&&draw_hop_heard(read){kc::reserve(c,||read.hops.iter().try_fold(read.var.len().checked_add(1)?,|n,h|n.checked_add(h.len())?.checked_add(1))?.checked_mul(4)?.checked_add(256))?;let key=format!("{}.{}",read.hops.join("."),read.var);insert(c,&mut out.hops,&key)?;}
   if read.root=="holder"&&read.hops.is_empty()&&read.kind==ReadKind::Var{insert(c,&mut out.reads,&read.var)?;}
   if read.root=="holder"&&read.hops.is_empty()&&read.kind==ReadKind::Accessor&&!capability_keys.contains(&read.var){let key=canonical(c,&read.var)?;insert(c,&mut out.keys,&key)?;}
  }
Ok(out)}

#[cfg(test)]mod tests{
 use super::*;use crate::reactive_read_facts::{Read,ReadSet};
 fn key(kind:&ReadKind,name:&str,capability_keys:&BTreeSet<String>,defines:&BTreeSet<String>)->String{if *kind==ReadKind::Accessor&&capability_keys.contains(name){format!("capkey:[{name}]")}else if *kind==ReadKind::Accessor&&defines.contains(name){format!("[{name}]")}else{name.to_owned()}}
 fn old_draw(set:&ReadSet,capability_keys:&BTreeSet<String>,defines:&BTreeSet<String>)->DrawProjection{
  fn draw_hop_heard(r:&Read)->bool{r.root=="holder"&&r.hop_ok&&!r.hops.is_empty()&&r.hops.len()<=3&&["loc","turf","area"].contains(&r.hops[0].as_str())}
  let mut out=DrawProjection::default();let keys=&mut out.reads;let published=&mut out.keys;let hopped=&mut out.hops;let linked=&mut out.links;
        for r in &set.reads {
            if r.root == "holder" && r.kind == ReadKind::Var && !r.hops.is_empty() {
                linked.insert(r.hops[0].trim_end_matches("[]").to_string());
            }
            if r.kind == ReadKind::Var && draw_hop_heard(r) {
                hopped.insert(format!("{}.{}", r.hops.join("."), r.var));
            }
            if r.root == "holder" && r.hops.is_empty() && r.kind == ReadKind::Var {
                keys.insert(r.var.clone());
            }
            // A capability's state key redraws its holder already (capability_key_changed -> look_key_changed); any other accessor key is a
            // producer's PUBLISH_CHANGE, which reaches the draw through this table.
            if r.root == "holder" && r.hops.is_empty() && r.kind == ReadKind::Accessor && !capability_keys.contains(&r.var) {
                published.insert(key(&r.kind, &r.var, &capability_keys, &defines));
            }
        }

  out
 }
 fn read(root:&str,hops:&[&str],var:&str,kind:ReadKind)->Read{Read{root:root.into(),hops:hops.iter().map(|s|s.to_string()).collect(),var:var.into(),owner:"/datum/probe".into(),kind,hop_ok:true}}
 fn fixture()->ReadSet{let mut set=ReadSet::default();for r in [read("holder",&[],"own",ReadKind::Var),read("holder",&["parts[]"],"charge",ReadKind::Var),read("holder",&["loc","cell"],"energy",ReadKind::Var),read("holder",&["loc","loc","cell","deep"],"deep_value",ReadKind::Var),read("actor",&["target"],"other",ReadKind::Var),read("holder",&[],"CAP_KEY",ReadKind::Accessor),read("holder",&[],"DEFINED_KEY",ReadKind::Accessor),read("holder",&[],"literal_key",ReadKind::Accessor),read("system",&[],"load",ReadKind::System)]{set.reads.insert(r);}set}
 #[test]fn complete_original_draw_projection_and_stat_read_rows_match_shared_policy(){let set=fixture();let capabilities=BTreeSet::from(["CAP_KEY".into()]);let defines=BTreeSet::from(["DEFINED_KEY".into()]);let expected=old_draw(&set,&capabilities,&defines);let mut control=kc::Compatibility;let got=draw_projection(View::Owned(&set),&capabilities,&mut|c,name|crate::reactive_read_key_policy::canonical(c,&ReadKind::Accessor,name,&capabilities,&defines),&mut control).unwrap();assert_eq!(got.reads,expected.reads);assert_eq!(got.keys,expected.keys);assert_eq!(got.hops,expected.hops);assert_eq!(got.links,expected.links);let mut reads=BTreeSet::new();note_reads(View::Owned(&set),&mut reads,&mut control).unwrap();let expected:BTreeSet<_>=set.reads.iter().filter(|r|r.kind==ReadKind::Var&&!r.owner.is_empty()).map(|r|(r.owner.clone(),r.var.clone())).collect();assert_eq!(reads,expected);let mut stat=BTreeSet::new();note_stat_reads(View::Owned(&set),&mut stat,&mut control).unwrap();assert!(stat.contains("load")&&stat.contains("parts")&&stat.contains("deep_value"));assert!(!stat.contains("target"));}
 #[cfg(feature="native-policy")]
 #[test]fn actual_frozen_read_rows_share_projection_without_reordering_or_copying_nodes(){let set=fixture();let budget=crate::captured_generator_budget::Budget::new(1024*1024).unwrap();let frozen=crate::reactive_read_result::FrozenReadSet::freeze(set.clone(),&budget,&mut||Ok(())).unwrap();let expected=old_draw(&set,&BTreeSet::new(),&BTreeSet::new());let got=draw_projection(View::Frozen(&frozen),&BTreeSet::new(),&mut|c,name|kc::own(c,name),&mut kc::Compatibility).unwrap();assert_eq!(got.reads,expected.reads);assert_eq!(got.keys,expected.keys);assert_eq!(got.hops,expected.hops);assert_eq!(got.links,expected.links);}
}

/// Required completed auto-inference facts. No empty/default implementation:
/// caller validates its original-source owner before lending these data rows.
pub enum CalledCandidates<'a>{Tree(&'a BTreeSet<(String,String)>),Rows(&'a[(String,String)])}
enum CalledIter<'a>{Tree(std::collections::btree_set::Iter<'a,(String,String)>),Rows(std::slice::Iter<'a,(String,String)>)}
impl<'a> Iterator for CalledIter<'a>{type Item=&'a(String,String);fn next(&mut self)->Option<Self::Item>{match self{Self::Tree(rows)=>rows.next(),Self::Rows(rows)=>rows.next()}}}
pub trait Candidates{
 type Error;
 fn candidate(&self,owner:&str,name:&str)->Result<bool,Self::Error>;
 fn named_candidate(&self,owner:&str,name:&str)->Result<bool,Self::Error>;
 fn called_candidates(&self)->Result<CalledCandidates<'_>,Self::Error>;
}
impl Fold{
 pub fn finish<C:kc::Control,A:Candidates<Error=C::Error>>(mut self,named:&BTreeSet<(String,String)>,auto:&A,control:&mut C)->Result<DepsAnalysis,C::Error>{
  for(owner,name)in &self.analysis.reads{control.checkpoint()?;if auto.candidate(owner,name)?{pair(control,&mut self.analysis.candidates,owner,name)?;}}
  for(owner,name)in named{control.checkpoint()?;if auto.named_candidate(owner,name)?{pair(control,&mut self.analysis.candidates,owner,name)?;}}
  let called=match auto.called_candidates()?{CalledCandidates::Tree(rows)=>CalledIter::Tree(rows.iter()),CalledCandidates::Rows(rows)=>CalledIter::Rows(rows.iter())};
  for(owner,name)in called{control.checkpoint()?;pair(control,&mut self.analysis.candidates,owner,name)?;}
  control.checkpoint()?;Ok(self.analysis)
 }
}

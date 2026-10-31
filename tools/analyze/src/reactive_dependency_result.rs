//! Ordered dependency RESULT data, moved from the unique completed fold.
//! No syntax/model/source handles; the enclosing factory owns source authority.
use crate::{reactive_facts::{DepsAnalysis,Untracked,Leaf},captured_generator_budget::Budget};
use std::{io,sync::Arc};
#[derive(Debug,serde::Serialize)]
pub struct FrozenDeps{
 pub(crate) consumers:Vec<(String,Vec<Untracked>)>,pub(crate) draws:Vec<String>,pub(crate) leaves:Vec<Leaf>,
 pub(crate) draw_reads:Vec<(String,Vec<String>)>,pub(crate) draw_keys:Vec<(String,Vec<String>)>,pub(crate) draw_hops:Vec<(String,Vec<String>)>,pub(crate) draw_links:Vec<(String,Vec<String>)>,
 pub(crate) verb_reads:Vec<(String,(Vec<String>,bool))>,pub(crate) stat_reads:Vec<String>,
 pub(crate) reads:Vec<(String,String)>,pub(crate) candidates:Vec<(String,String)>,pub(crate) sampled:Vec<(String,Vec<(String,u32)>)>,
}
fn denied(budget:&Budget,message:&'static str)->io::Error{budget.deny();io::Error::new(io::ErrorKind::OutOfMemory,message)}
fn moved<T>(rows:impl ExactSizeIterator<Item=T>,budget:&Budget,poll:&dyn Fn()->io::Result<()>)->io::Result<Vec<T>>{
 poll()?;let count=rows.len();if count==0{return Ok(Vec::new())}
 let reservation=count.checked_mul(std::mem::size_of::<T>()).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(64)).ok_or_else(||denied(budget,"dependency result capacity overflow"))?;
 budget.charge(reservation).map_err(|message|io::Error::new(io::ErrorKind::OutOfMemory,message))?;
 let mut out=Vec::new();out.try_reserve_exact(count).map_err(|error|{budget.deny();io::Error::new(io::ErrorKind::OutOfMemory,error)})?;
 if out.capacity().checked_mul(std::mem::size_of::<T>()).is_none_or(|bytes|bytes>reservation){return Err(denied(budget,"dependency result allocator exceeds admitted capacity"))}
 for row in rows{poll()?;out.push(row)}poll()?;Ok(out)
}
fn strings(rows:std::collections::BTreeSet<String>,budget:&Budget,poll:&dyn Fn()->io::Result<()>)->io::Result<Vec<String>>{moved(rows.into_iter(),budget,poll)}
impl FrozenDeps{
 pub(crate) fn freeze(input:DepsAnalysis,budget:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->io::Result<Self>{
  poll()?;let DepsAnalysis{consumers,draws,leaves,draw_reads,draw_keys,draw_hops,draw_links,verb_reads,stat_reads,reads,candidates,sampled}=input;
  let consumers=moved(consumers.into_iter(),budget,poll)?;let draws=strings(draws,budget,poll)?;
  let draw_reads=maps(draw_reads,budget,poll)?;let draw_keys=maps(draw_keys,budget,poll)?;let draw_hops=maps(draw_hops,budget,poll)?;let draw_links=maps(draw_links,budget,poll)?;
  let verb_reads=nested(verb_reads.into_iter(),budget,poll,|(names,unresolved)|Ok((strings(names,budget,poll)?,unresolved)))?;
  let stat_reads=strings(stat_reads,budget,poll)?;let reads=moved(reads.into_iter(),budget,poll)?;let candidates=moved(candidates.into_iter(),budget,poll)?;
  let sampled=nested(sampled.into_iter(),budget,poll,|rows|moved(rows.into_iter(),budget,poll))?;
  poll()?;if budget.denied(){return Err(denied(budget,"dependency result operation denied"))}
  Ok(Self{consumers,draws,leaves,draw_reads,draw_keys,draw_hops,draw_links,verb_reads,stat_reads,reads,candidates,sampled})
 }
 pub fn visit_storage(&self,mut visit:impl FnMut(&'static str,usize,usize,usize)){
  fn vec<T>(name:&'static str,rows:&Vec<T>,visit:&mut impl FnMut(&'static str,usize,usize,usize)){visit(name,rows.as_ptr()as usize,rows.len()*std::mem::size_of::<T>(),rows.capacity()*std::mem::size_of::<T>())}
  fn text(s:&String,visit:&mut impl FnMut(&'static str,usize,usize,usize)){visit("dependency_text",s.as_ptr()as usize,s.len(),s.capacity())}
  for(name,rows)in [("dependency_draws",&self.draws),("dependency_stat_reads",&self.stat_reads)]{vec(name,rows,&mut visit);for s in rows{text(s,&mut visit)}}
  vec("dependency_consumers",&self.consumers,&mut visit);for(id,rows)in &self.consumers{text(id,&mut visit);vec("dependency_untracked",rows,&mut visit);for row in rows{for s in [&row.what,&row.owner,&row.rel]{text(s,&mut visit)}}}
  vec("dependency_leaves",&self.leaves,&mut visit);for row in &self.leaves{for s in [&row.owner,&row.var,&row.rel]{text(s,&mut visit)}}
  for rows in [&self.draw_reads,&self.draw_keys,&self.draw_hops,&self.draw_links]{vec("dependency_draw_rows",rows,&mut visit);for(owner,names)in rows{text(owner,&mut visit);vec("dependency_names",names,&mut visit);for s in names{text(s,&mut visit)}}}
  vec("dependency_verb_rows",&self.verb_reads,&mut visit);for(id,(names,_))in &self.verb_reads{text(id,&mut visit);vec("dependency_verb_names",names,&mut visit);for s in names{text(s,&mut visit)}}
  for rows in [&self.reads,&self.candidates]{vec("dependency_pairs",rows,&mut visit);for(a,b)in rows{text(a,&mut visit);text(b,&mut visit)}}
  vec("dependency_sampled",&self.sampled,&mut visit);for(id,rows)in &self.sampled{text(id,&mut visit);vec("dependency_sample_rows",rows,&mut visit);for(rel,_)in rows{text(rel,&mut visit)}}
 }
 pub fn retained_charge(&self)->Option<usize>{let mut sum=Some(std::mem::size_of::<Self>()+2*std::mem::size_of::<usize>());self.visit_storage(|_,_,_,bytes|sum=sum.and_then(|n|n.checked_add(bytes)));sum}
}
fn nested<T,U>(rows:impl ExactSizeIterator<Item=(String,T)>,budget:&Budget,poll:&dyn Fn()->io::Result<()>,mut convert:impl FnMut(T)->io::Result<U>)->io::Result<Vec<(String,U)>>{
 poll()?;let count=rows.len();if count==0{return Ok(Vec::new())}let reserve=count.checked_mul(std::mem::size_of::<(String,U)>()).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(64)).ok_or_else(||denied(budget,"dependency nested result capacity overflow"))?;
 budget.charge(reserve).map_err(|message|io::Error::new(io::ErrorKind::OutOfMemory,message))?;let mut out=Vec::new();out.try_reserve_exact(count).map_err(|error|{budget.deny();io::Error::new(io::ErrorKind::OutOfMemory,error)})?;
 if out.capacity().checked_mul(std::mem::size_of::<(String,U)>()).is_none_or(|n|n>reserve){return Err(denied(budget,"dependency nested allocator exceeds admission"))}
 for(name,value)in rows{poll()?;out.push((name,convert(value)?))}poll()?;Ok(out)
}
fn maps(rows:std::collections::BTreeMap<String,std::collections::BTreeSet<String>>,budget:&Budget,poll:&dyn Fn()->io::Result<()>)->io::Result<Vec<(String,Vec<String>)>>{nested(rows.into_iter(),budget,poll,|rows|strings(rows,budget,poll))}

#[cfg(test)]mod tests{
 use super::*;use std::collections::{BTreeMap,BTreeSet};
 fn fixture()->DepsAnalysis{
 let mut data=DepsAnalysis{consumers:BTreeMap::new(),draws:BTreeSet::new(),leaves:Vec::new(),draw_reads:BTreeMap::new(),draw_keys:BTreeMap::new(),draw_hops:BTreeMap::new(),draw_links:BTreeMap::new(),verb_reads:BTreeMap::new(),stat_reads:BTreeSet::new(),reads:BTreeSet::new(),candidates:BTreeSet::new(),sampled:BTreeMap::new()};
 data.consumers.insert("/datum/probe::draw".into(),vec![Untracked{what:"charge".into(),owner:"/datum/probe".into(),rel:"code/probe.dm".into(),line:3}]);data.draws.insert("/datum/probe::draw".into());data.leaves.push(Leaf{owner:"/datum/probe".into(),var:"charge".into(),rel:"code/probe.dm".into(),line:2});
 for map in [&mut data.draw_reads,&mut data.draw_keys,&mut data.draw_hops,&mut data.draw_links]{map.insert("/datum/probe".into(),BTreeSet::from(["charge".into(),"loc.energy".into()]));}
 data.verb_reads.insert("/datum/probe::hidden_verbs".into(),(BTreeSet::from(["charge".into()]),true));data.stat_reads.insert("charge".into());data.reads.insert(("/datum/probe".into(),"charge".into()));data.candidates.insert(("/datum/probe".into(),"charge".into()));data.sampled.insert("/datum/probe::draw".into(),BTreeSet::from([("code/probe.dm".into(),4)]));data
 }
 #[test]fn frozen_move_preserves_all_ordered_fields_and_original_buffers_without_tree_retention(){
 let data=fixture();let read_owner=data.reads.first().unwrap().0.as_ptr();let consumer_rows=data.consumers.values().next().unwrap().as_ptr();let leaf_rows=data.leaves.as_ptr();let mut old=crate::deps_policy::Output::default();crate::deps_policy::generate(&data,&mut old);
 let defines=std::collections::HashSet::new();let tracked=std::collections::HashMap::from([("/datum/probe".into(),std::collections::HashSet::from(["charge".into()]))]);let metadata=crate::plans_policy::MetadataInput{markers:&[],defines:&defines,tracked:&tracked,output_defining_owners:&[],reader_procs:&[],files:&[]};let mut old_plans=crate::plans_policy::Output::default();crate::plans_policy::generate(&crate::plans_policy::PlansInput{analysis:&data,markers:&[],defines:&defines,tracked:&tracked,output_defining_owners:&[],reader_procs:&[],files:&[]},&mut old_plans);
 let budget=Budget::new(1024*1024).unwrap();let value=FrozenDeps::freeze(data,&budget,&||Ok(())).unwrap();let mut frozen_plans=crate::plans_policy::Output::default();crate::plans_policy::generate_with_analysis(&metadata,crate::reactive_dependency_view::Analysis::Frozen(&value),&mut frozen_plans);assert_eq!(frozen_plans,old_plans,"full plans output borrows SAME frozen dependency fields without rebuilding trees");assert_eq!(value.reads[0].0.as_ptr(),read_owner);assert_eq!(value.consumers[0].1.as_ptr(),consumer_rows);assert_eq!(value.leaves.as_ptr(),leaf_rows);
 assert_eq!(value.draws,["/datum/probe::draw"]);assert_eq!(value.leaves[0].line,2);assert_eq!(value.draw_reads[0].1,["charge","loc.energy"]);assert_eq!(value.draw_keys,value.draw_reads);assert_eq!(value.draw_hops,value.draw_reads);assert_eq!(value.draw_links,value.draw_reads);assert_eq!(value.verb_reads[0].1.0,["charge"]);assert!(value.verb_reads[0].1.1);assert_eq!(value.stat_reads,["charge"]);assert_eq!(value.candidates,value.reads);assert_eq!(value.sampled[0].1,[("code/probe.dm".into(),4)]);
 let mut new=crate::deps_policy::Output::default();crate::deps_policy::generate_view(crate::reactive_dependency_view::Analysis::Frozen(&value),&mut new);assert_eq!(new,old);
 let mut actual=std::mem::size_of::<FrozenDeps>()+2*std::mem::size_of::<usize>();value.visit_storage(|_,_,_,capacity|actual+=capacity);assert_eq!(value.retained_charge(),Some(actual));
 }
 #[test]fn freeze_refuses_before_new_coordination_and_does_not_turn_actual_io_into_semantic_data(){
 let fixed=std::mem::size_of::<Budget>()+2*std::mem::size_of::<usize>();let tiny=Budget::new(fixed).unwrap();assert_eq!(FrozenDeps::freeze(fixture(),&tiny,&||Ok(())).unwrap_err().kind(),io::ErrorKind::OutOfMemory);assert!(tiny.denied());
 let fresh=Budget::new(1024*1024).unwrap();assert_eq!(FrozenDeps::freeze(fixture(),&fresh,&||Err(io::Error::from_raw_os_error(1450))).unwrap_err().raw_os_error(),Some(1450));assert!(!fresh.denied());assert!(FrozenDeps::freeze(fixture(),&fresh,&||Ok(())).is_ok());
 }
}

//! SAME unique dependency-gap judgement over original owned/borrowed read rows.
//! Views hold no copied AST/source/model; classification callbacks retain source proof.
use crate::{reactive_read_facts::{ReadSet,Read,ReadKind,Diag},reactive_facts::Untracked,key_policy_control as kc,reactive_variable_policy::VarClass};
pub const UNRESOLVED_RULES:&[&str]=&["unannotated_global","dynamic_read","hop_not_relation","ffi_call"];
pub const OPAQUE_SEEN:&[&str]=&["/::stat_value","/::cap_key_get","/::condition_holds","/::condition_id_holds","/atom::draw","/datum::draw","/::tracked_changed","/::expiry_clock_now"];
const DRAW_PSEUDO_HOPS:&[&str]=&["loc","turf","area"];
const DRAW_HOP_DEPTH:usize=3;
pub fn draw_hop_heard(read:&Read)->bool{read.root=="holder"&&read.hop_ok&&!read.hops.is_empty()&&read.hops.len()<=DRAW_HOP_DEPTH&&DRAW_PSEUDO_HOPS.contains(&read.hops[0].as_str())}
pub fn turf_coordinate(read:&Read)->bool{matches!(read.var.as_str(),"x"|"y"|"z")&&read.hops.last().is_some_and(|hop|hop=="turf")}
#[cfg(feature="native-policy")]use crate::reactive_read_result::FrozenReadSet;
#[derive(Clone,Copy)]
pub enum View<'a>{Owned(&'a ReadSet),#[cfg(feature="native-policy")]Frozen(&'a FrozenReadSet)}
pub(crate) enum Reads<'a>{Owned(std::collections::btree_set::Iter<'a,Read>),#[cfg(feature="native-policy")]Frozen(std::slice::Iter<'a,Read>)}
impl<'a> Iterator for Reads<'a>{type Item=&'a Read;fn next(&mut self)->Option<Self::Item>{match self{Self::Owned(rows)=>rows.next(),#[cfg(feature="native-policy")]Self::Frozen(rows)=>rows.next()}}}
enum Opaque<'a>{Owned(std::collections::btree_map::Iter<'a,String,(String,u32)>),#[cfg(feature="native-policy")]Frozen(std::slice::Iter<'a,(String,(String,u32))>)}
impl<'a> Iterator for Opaque<'a>{type Item=(&'a str,&'a(String,u32));fn next(&mut self)->Option<Self::Item>{match self{Self::Owned(rows)=>rows.next().map(|(key,value)|(key.as_str(),value)),#[cfg(feature="native-policy")]Self::Frozen(rows)=>rows.next().map(|(key,value)|(key.as_str(),value))}}}

enum Samples<'a>{Owned(std::collections::btree_set::Iter<'a,(String,u32)>),#[cfg(feature="native-policy")]Frozen(std::slice::Iter<'a,(String,u32)>)}
impl<'a> Iterator for Samples<'a>{type Item=&'a(String,u32);fn next(&mut self)->Option<Self::Item>{match self{Self::Owned(rows)=>rows.next(),#[cfg(feature="native-policy")]Self::Frozen(rows)=>rows.next()}}}
impl<'a> View<'a>{
 pub(crate) fn sampled(self)->impl Iterator<Item=&'a(String,u32)>{match self{Self::Owned(value)=>Samples::Owned(value.sampled.iter()),#[cfg(feature="native-policy")]Self::Frozen(value)=>Samples::Frozen(value.sampled().iter())}}

 pub(crate) fn reads(self)->Reads<'a>{match self{Self::Owned(value)=>Reads::Owned(value.reads.iter()),#[cfg(feature="native-policy")]Self::Frozen(value)=>Reads::Frozen(value.reads().iter())}}
 fn site(self,read:&Read)->Option<&'a(String,u32)>{match self{Self::Owned(value)=>value.sites.get(read),#[cfg(feature="native-policy")]Self::Frozen(value)=>value.site(read)}}
 fn internal(self,read:&Read)->bool{match self{Self::Owned(value)=>value.internal.contains(read),#[cfg(feature="native-policy")]Self::Frozen(value)=>value.is_internal(read)}}
 fn diags(self)->&'a[Diag]{match self{Self::Owned(value)=>&value.diags,#[cfg(feature="native-policy")]Self::Frozen(value)=>value.diagnostics()}}
 fn opaque(self)->Opaque<'a>{match self{Self::Owned(value)=>Opaque::Owned(value.opaque.iter()),#[cfg(feature="native-policy")]Self::Frozen(value)=>Opaque::Frozen(value.opaque().iter())}}
}
pub trait Source:kc::Control{
 fn classify(&mut self,owner:&str,name:&str)->Result<VarClass,Self::Error>;
 fn generated_setter(&mut self,callee:&str)->Result<bool,Self::Error>;
}
fn push<C:kc::Control>(out:&mut Vec<Untracked>,control:&mut C,what:String,owner:&str,site:Option<(&str,u32)>)->Result<(),C::Error>{
 if C::CHECKED&&out.len()==out.capacity(){let count=out.capacity().checked_mul(2).map(|n|n.max(4)).ok_or_else(||control.overflow())?;kc::reserve(control,||count.checked_mul(std::mem::size_of::<Untracked>())?.checked_mul(4)?.checked_add(64))?;out.try_reserve_exact(count-out.len()).map_err(|_|control.allocation_failed())?;if out.capacity()>count.saturating_mul(4){return Err(control.allocation_failed())}}
 let(rel,line)=site.unwrap_or(("",0));out.push(Untracked{what,owner:kc::own(control,owner)?,rel:kc::own(control,rel)?,line});Ok(())
}
fn read_key<C:kc::Control>(control:&mut C,read:&Read)->Result<String,C::Error>{kc::reserve(control,||read.hops.iter().try_fold(read.root.len().checked_add(read.var.len())?.checked_add(2)?,|n,hop|n.checked_add(hop.len())?.checked_add(1))?.checked_mul(4)?.checked_add(256))?;Ok(read.key())}
/// Preserve original read/diagnostic/opaque iteration, short circuit, sort and
/// dedup. No internal array/diagnostic order is normalized by a comparison here.
pub fn untracked_of<S:Source>(set:View<'_>,source:&mut S,output:bool)->Result<Vec<Untracked>,S::Error>{
 source.checkpoint()?;let mut out=Vec::new();
 for read in set.reads(){source.checkpoint()?;
  if read.kind!=ReadKind::Var||read.root!="holder"||set.internal(read){continue}
  if matches!(read.var.as_str(),"type"|"parent_type"){continue}
  if output&&read.hops.iter().any(|hop|DRAW_PSEUDO_HOPS.contains(&hop.as_str()))&&!draw_hop_heard(read){let key=read_key(source,read)?;push(&mut out,source,key,&read.owner,set.site(read).map(|(rel,line)|(rel.as_str(),*line)))?;continue}
  if !read.hop_ok||(!turf_coordinate(read)&&source.classify(&read.owner,&read.var)?==VarClass::Unknown){let key=read_key(source,read)?;push(&mut out,source,key,&read.owner,set.site(read).map(|(rel,line)|(rel.as_str(),*line)))?;}
 }
 for diagnostic in set.diags(){source.checkpoint()?;
  if diagnostic.rule=="untracked_global"{let what=kc::own(source,&diagnostic.msg)?;let site=(diagnostic.rel.as_str(),diagnostic.line);push(&mut out,source,what,"",Some(site))?;}
  else if UNRESOLVED_RULES.contains(&diagnostic.rule){let what=kc::format(source,format_args!("?{}",diagnostic.rule))?;let site=(diagnostic.rel.as_str(),diagnostic.line);push(&mut out,source,what,"",Some(site))?;}
 }
 for(callee,site)in set.opaque(){source.checkpoint()?;if OPAQUE_SEEN.contains(&callee)||source.generated_setter(callee)?{continue}let what=kc::format(source,format_args!("?opaque:{}",callee))?;push(&mut out,source,what,"",Some((site.0.as_str(),site.1)))?;}
 out.sort();out.dedup();source.checkpoint()?;Ok(out)
}

/// Exposed capture coordination is admitted before each SAME Pat matcher call;
/// private regex engine scratch is outside this accounting contract.
pub(crate) fn captures<'h,C:kc::Control>(pattern:&crate::pat::Pat,text:&'h str,control:&mut C,mut emit:impl FnMut(&mut C,crate::pat::Caps<'h>)->Result<(),C::Error>)->Result<(),C::Error>{
 pattern.try_for_each_capture(text,control,|c,groups|kc::reserve(c,||groups.checked_mul(4)?.checked_mul(std::mem::size_of::<Option<(usize,usize)>>())?.checked_add(std::mem::size_of::<crate::pat::Caps<'_>>()+64)),|c,row|emit(c,row))
}

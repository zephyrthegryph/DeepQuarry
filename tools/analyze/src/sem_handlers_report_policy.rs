//! The original handler put() dedup scope, shared by all three partitions.
//! No source, ALLOW lookup, reporting or model authority is issued here.
use crate::key_policy_control::{self as kc,Control};
pub const ALLOW_NAME:&str="handlers";
#[derive(Default)]pub struct Seen{keys:std::collections::HashSet<(String,String,u32,String)>}
impl Seen{
 /// Exactly old put(): blank relative first; tuple insertion before ALLOW.
 /// Caller must look up the actual original raw file only when this is true.
 pub fn admit_using<C:Control>(&mut self,rule:&str,relative:&str,line:u32,message:&str,c:&mut C)->Result<bool,C::Error>{
  if relative.is_empty(){return Ok(false)}c.checkpoint()?;kc::set_room(c,&mut self.keys)?;
  let key=(kc::own(c,rule)?,kc::own(c,relative)?,line,kc::own(c,message)?);Ok(self.keys.insert(key))
 }
}
#[cfg(test)]mod controls{
 use super::*;
 #[test]fn all_partitions_keep_one_shared_old_tuple_scope_and_dedup_before_allow(){
  let rows=[("context_escape","",1,"blank"),("context_escape","code/a.dm",2,"same"),("context_escape","code/a.dm",2,"same"),("act_try_unpaired","code/a.dm",2,"same"),("context_escape","code/a.dm",3,"same"),("context_escape","code/a.dm",2,"different"),("output_signature","code/b.dm",4,"bad"),("output_signature","code/b.dm",4,"bad")];
  let mut old=std::collections::HashSet::new();let mut actual=Seen::default();let mut old_visits=Vec::new();let mut actual_visits=Vec::new();for(rule,rel,line,msg)in rows{if !rel.is_empty()&&old.insert((rule.to_owned(),rel.to_owned(),line,msg.to_owned())){old_visits.push((rule,rel,line,msg))}if actual.admit_using(rule,rel,line,msg,&mut kc::Compatibility).unwrap(){actual_visits.push((rule,rel,line,msg))}}assert_eq!(actual_visits,old_visits);assert_eq!(actual_visits.len(),5);assert_eq!(ALLOW_NAME,"handlers");
 }
 struct Fault;impl Control for Fault{type Error=std::io::Error;const CHECKED:bool=true;fn checkpoint(&mut self)->Result<(),Self::Error>{Err(std::io::Error::from_raw_os_error(1450))}fn reserve(&mut self,_:usize)->Result<(),Self::Error>{panic!("first checkpoint must win")}fn overflow(&mut self)->Self::Error{std::io::ErrorKind::OutOfMemory.into()}fn allocation_failed(&mut self)->Self::Error{std::io::ErrorKind::OutOfMemory.into()}}
 #[test]fn first_io_prevents_seen_insertion_and_blank_relative_needs_no_native_work(){let mut seen=Seen::default();assert!(!seen.admit_using("rule","",1,"message",&mut Fault).unwrap());assert_eq!(seen.admit_using("rule","code/a.dm",1,"message",&mut Fault).unwrap_err().raw_os_error(),Some(1450));assert!(seen.admit_using("rule","code/a.dm",1,"message",&mut kc::Compatibility).unwrap());}
}

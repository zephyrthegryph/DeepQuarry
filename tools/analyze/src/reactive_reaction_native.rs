//! Source-bound historical raw reaction policy, NOT a second semantic model.
use crate::{reactive_original_source::ReadSource,reactive_reaction_policy::{self as policy,Source,Procedure,ProcedureKey,Lines,Membership},reactive_reads_native::Failure,key_policy_control::{self as kc,Control}};
use std::io;
struct RawControl<'a,'s>{source:&'a ReadSource<'s>}
fn denial()->Failure{Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"reaction lexical policy admission refused"))}
impl Control for RawControl<'_,'_>{type Error=Failure;const CHECKED:bool=true;fn checkpoint(&mut self)->Result<(),Failure>{self.source.checkpoint()?;if self.source.budget().denied(){return Err(denial())}self.source.require().map_err(Failure::from)}fn reserve(&mut self,n:usize)->Result<(),Failure>{self.source.reserve(Some(n)).map_err(|_|denial())}fn overflow(&mut self)->Failure{self.source.budget().deny();denial()}fn allocation_failed(&mut self)->Failure{self.source.budget().deny();denial()}}
struct Original<'a,'s>{source:&'a ReadSource<'s>}
struct Known<'a,'s>{source:&'a ReadSource<'s>,owner:&'a str}
fn known_in_file<C:Control>(relative:&str,view:&crate::tree::View,owner:&str,name:&str,control:&mut C)->Result<bool,C::Error>{
 if relative==policy::GENERATED_REL{return Ok(false)}let mut found=false;
 policy::visit_variable_names(view,control,|control,row|{control.checkpoint()?;if row.name==name&&policy::owner_in_chain(row.owner_without_leading_slash,owner){found=true;Ok(false)}else{Ok(true)}})?;Ok(found)
}
impl Membership for Known<'_,'_>{type Error=Failure;fn contains(&self,name:&str)->Result<bool,Failure>{let mut found=false;let mut control=RawControl{source:self.source};self.source.with_reaction_code(name,|relative,view|{found=known_in_file(relative,view,self.owner,name,&mut control)?;Ok(!found)})?;control.checkpoint()?;Ok(found)}}
impl<'source> Source for Original<'_,'source>{
 type Error=Failure;type Known<'a>=Known<'a,'source> where Self:'a;
 fn for_each_named(&self,name:&str,visit:&mut dyn FnMut(ProcedureKey<'_>,Procedure<'_>)->Result<bool,Failure>)->Result<(),Failure>{visit_procedures(self.source,ProcedureSelector::Names(&[name]),visit)}
 fn known<'a>(&'a self,owner:&'a str)->Result<Known<'a,'source>,Failure>{self.source.checkpoint()?;Ok(Known{source:self.source,owner})}
}
/// A lexical policy selector, never a compiled declaration/body receipt.
pub(crate) enum ProcedureSelector<'a>{Names(&'a[&'a str]),Prefix(&'a str)}
impl ProcedureSelector<'_>{fn accepts(&self,name:&str)->bool{match self{Self::Names(names)=>names.contains(&name),Self::Prefix(prefix)=>name.starts_with(prefix)}}fn might_match(&self,line:&str)->bool{match self{Self::Names(names)=>names.iter().any(|name|line.contains(name)),Self::Prefix(prefix)=>line.contains(prefix)}}}
/// Every procedure/body borrow ends before the current original file loan ends.
pub(crate) fn visit_procedures(source:&ReadSource<'_>,selector:ProcedureSelector<'_>,visit:&mut dyn FnMut(ProcedureKey<'_>,Procedure<'_>)->Result<bool,Failure>)->Result<(),Failure>{
 let mut control=RawControl{source};source.with_reaction_code("",|relative,code|{
  for(number,line)in code.numbered(){control.checkpoint()?;if !selector.might_match(line){continue}
   let Some(header)=policy::header_admitted(line,|groups|kc::reserve(&mut control,||groups.checked_mul(4)?.checked_mul(std::mem::size_of::<Option<(usize,usize)>>())?.checked_add(std::mem::size_of::<crate::pat::Caps<'_>>()+64)))?else{continue};if !selector.accepts(header.name){continue}
   let owner=header.owner.trim_end_matches('/');let owner=if owner.is_empty(){"/"}else{owner};let first=number.checked_add(1).ok_or_else(||control.overflow())?;
   if !visit(ProcedureKey::Raw{relative,header:number},Procedure{owner,name:header.name,relative,args:header.args,lines:Lines::IndentedCode{view:code,first}})?{return Ok(false)}
  }Ok(true)
 })?;control.checkpoint()
}
pub(crate) fn reaction_pairs(source:&ReadSource<'_>)->Result<std::collections::BTreeSet<(String,String)>,Failure>{let original=Original{source};policy::reaction_pairs(&original,&mut RawControl{source})}

pub(crate) fn raw_has_variable(source:&ReadSource<'_>,owner:&str,name:&str)->Result<bool,Failure>{Known{source,owner}.contains(name)}
pub(crate) fn reaction_reads(source:&ReadSource<'_>)->Result<Vec<policy::ReactionRead>,Failure>{policy::reaction_reads(&Original{source},&mut RawControl{source})}

#[cfg(test)]mod membership_tests{use super::*;#[test]fn generated_read_file_cannot_supply_original_model_variable_membership(){let view=crate::tree::View::new("/mob/unit/var/only_generated\n".into());assert!(!known_in_file(policy::GENERATED_REL,&view,"/mob/unit","only_generated",&mut kc::Compatibility).unwrap());assert!(known_in_file("code/unit.dm",&view,"/mob/unit","only_generated",&mut kc::Compatibility).unwrap());}}

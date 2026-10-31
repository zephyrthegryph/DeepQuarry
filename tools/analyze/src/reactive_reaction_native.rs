//! Source-bound historical raw reaction policy, NOT a second semantic model.
use crate::{reactive_original_source::ReadSource,reactive_reaction_policy::{self as policy,Source,Procedure,ProcedureKey,Lines,Membership},reactive_reads_native::Failure,key_policy_control::{self as kc,Control}};
use std::io;
struct RawControl<'a,'s>{source:&'a ReadSource<'s>}
fn denial()->Failure{Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"reaction lexical policy admission refused"))}
impl Control for RawControl<'_,'_>{type Error=Failure;const CHECKED:bool=true;fn checkpoint(&mut self)->Result<(),Failure>{self.source.checkpoint()?;if self.source.budget().denied(){return Err(denial())}self.source.require().map_err(Failure::from)}fn reserve(&mut self,n:usize)->Result<(),Failure>{self.source.reserve(Some(n)).map_err(|_|denial())}fn overflow(&mut self)->Failure{self.source.budget().deny();denial()}fn allocation_failed(&mut self)->Failure{self.source.budget().deny();denial()}}
struct Original<'a,'s>{source:&'a ReadSource<'s>}
struct Known<'a,'s>{source:&'a ReadSource<'s>,owner:&'a str}
impl Membership for Known<'_,'_>{type Error=Failure;fn contains(&self,name:&str)->Result<bool,Failure>{let mut found=false;let mut control=RawControl{source:self.source};self.source.with_reaction_code(name,|_,view|{
 policy::visit_variable_names(view,&mut control,|control,row|{control.checkpoint()?;if row.name==name&&policy::owner_in_chain(row.owner_without_leading_slash,self.owner){found=true;Ok(false)}else{Ok(true)}})?;Ok(!found)
 })?;control.checkpoint()?;Ok(found)}}
impl<'source> Source for Original<'_,'source>{
 type Error=Failure;type Known<'a>=Known<'a,'source> where Self:'a;
 fn for_each_named<'a>(&'a self,name:&str,visit:&mut dyn FnMut(ProcedureKey<'a>,Procedure<'a>)->Result<bool,Failure>)->Result<(),Failure>{
  let mut control=RawControl{source:self.source};self.source.with_reaction_code(name,|relative,code|{
   for(number,line)in code.numbered(){control.checkpoint()?;if !line.contains(name){continue}
    let Some(header)=policy::header_admitted(line,|groups|kc::reserve(&mut control,||groups.checked_mul(4)?.checked_mul(std::mem::size_of::<Option<(usize,usize)>>())?.checked_add(std::mem::size_of::<crate::pat::Caps<'_>>()+64)))?else{continue};if header.name!=name{continue}
    let owner=header.owner.trim_end_matches('/');let owner=if owner.is_empty(){"/"}else{owner};let first=number.checked_add(1).ok_or_else(||control.overflow())?;
    if !visit(ProcedureKey::Raw{relative,header:number},Procedure{owner,name:header.name,relative,args:header.args,lines:Lines::IndentedCode{view:code,first}})?{return Ok(false)}
   }Ok(true)
  })?;control.checkpoint()
 }
 fn known<'a>(&'a self,owner:&'a str)->Result<Known<'a,'source>,Failure>{self.source.checkpoint()?;Ok(Known{source:self.source,owner})}
}
pub(crate) fn reaction_pairs(source:&ReadSource<'_>)->Result<std::collections::BTreeSet<(String,String)>,Failure>{let original=Original{source};policy::reaction_pairs(&original,&mut RawControl{source})}

//! Unique original standard-output signature judgement; no parser/model/cache.
use crate::key_policy_control::{self as kc,Control};
struct Definition{owner:String,relative:String,line:u32,parameters:Vec<String>}
#[derive(Default)]pub struct Output{bases:Vec<(String,Vec<String>)>,definitions:Vec<Definition>}
impl Output{
 /// Feed original type/own-proc value order for ONE standard output name.
 /// Every source value participates, including bodyless declarations.
 pub fn push_using<'a,C:Control>(&mut self,owner:&str,relative:&str,line:u32,names:impl IntoIterator<Item=&'a str>,c:&mut C)->Result<(),C::Error>{
  c.checkpoint()?;let mut parameters=Vec::new();for name in names{kc::row(c,&mut parameters)?;parameters.push(kc::own(c,name)?)}
  let owner=kc::own(c,owner)?;if relative.starts_with("code/engine/"){if let Some((_,old))=self.bases.iter_mut().find(|(key,_)|key==&owner){*old=parameters}else{kc::row(c,&mut self.bases)?;self.bases.push((owner,parameters));}}else{kc::row(c,&mut self.definitions)?;self.definitions.push(Definition{owner,relative:kc::own(c,relative)?,line,parameters});}Ok(())
 }
 pub fn finish_using<C:Control>(self,name:&str,parent:&mut impl FnMut(&str,&mut C)->Result<Option<String>,C::Error>,emit:&mut impl FnMut(&str,u32,String,&mut C)->Result<(),C::Error>,c:&mut C)->Result<(),C::Error>{
  for row in self.definitions{c.checkpoint()?;let mut ancestor=Some(kc::own(c,&row.owner)?);while let Some(path)=ancestor{
   c.checkpoint()?;if let Some(base)=self.bases.iter().find_map(|(key,value)|(key==&path).then_some(value)){if &row.parameters!=base{
    kc::reserve(c,||row.parameters.iter().try_fold(row.parameters.len().checked_mul(2)?,|n,p|n.checked_add(p.len()))?.checked_add(base.iter().try_fold(base.len().checked_mul(2)?,|n,p|n.checked_add(p.len()))?)?.checked_add(128))?;
    let params=row.parameters.join(", ");let base_params=base.join(", ");let message=kc::format(c,format_args!("{}::{}({}) overrides {}::{}({})",row.owner,name,params,path,name,base_params))?;emit(&row.relative,row.line,message,c)?;
   }break}ancestor=parent(&path,c)?;
  }}c.checkpoint()
 }
}
#[cfg(test)]mod tests{
 use super::*;use crate::key_policy_control::Compatibility;
 #[test]fn old_last_base_self_match_actual_parent_and_source_order(){let mut output=Output::default();let mut c=Compatibility;
  output.push_using("/atom","code/engine/a.dm",1,["old"],&mut c).unwrap();output.push_using("/atom","code/engine/b.dm",2,["look"],&mut c).unwrap();
  output.push_using("/obj/bad","code/b.dm",3,["holder","look"],&mut c).unwrap();output.push_using("/datum/other","code/a.dm",4,["other"],&mut c).unwrap();output.push_using("/atom","code/a.dm",5,["wrong"],&mut c).unwrap();
  let mut found=Vec::new();output.finish_using("draw",&mut|owner,_|Ok(match owner{"/obj/bad"=>Some("/atom".to_owned()),_=>None}),&mut|rel,line,msg,_|{found.push((rel.to_owned(),line,msg));Ok(())},&mut c).unwrap();assert_eq!(found,[("code/b.dm".to_owned(),3,"/obj/bad::draw(holder, look) overrides /atom::draw(look)".to_owned()),("code/a.dm".to_owned(),5,"/atom::draw(wrong) overrides /atom::draw(look)".to_owned())]);
 }
}

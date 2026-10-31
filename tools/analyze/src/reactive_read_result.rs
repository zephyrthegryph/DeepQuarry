//! Read-only retained form of the SAME completed unique read result.
//! BTree collectors are consumed, never cloned into a second retained model.
use crate::{reactive_read_facts::{ReadSet,Read,ReadKind,Diag,Effect,LookupArgument},reactive_reads_native::Failure,captured_generator_budget::Budget};
use std::{io,mem::size_of};
#[derive(Debug,serde::Serialize)]
pub struct FrozenReadSet{
 reads:Vec<Read>,ctx_fields:Vec<(String,(String,u32))>,sites:Vec<(Read,(String,u32))>,
 diags:Vec<Diag>,lookup_diags:Vec<Diag>,effects:Vec<Effect>,followed:Vec<String>,
 opaque:Vec<(String,(String,u32))>,internal:Vec<Read>,sampled:Vec<(String,u32)>,
}
fn oom(b:&Budget,error:impl Into<Box<dyn std::error::Error+Send+Sync>>)->Failure{b.deny();Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,error))}
fn rows<T>(iter:impl ExactSizeIterator<Item=T>,b:&Budget)->Result<Vec<T>,Failure>{
 let requested=iter.len();let reserve=requested.checked_mul(4).and_then(|n|n.checked_mul(size_of::<T>())).and_then(|n|n.checked_add(size_of::<Vec<T>>()));
 let reserve=reserve.ok_or_else(||oom(b,"reactive frozen row capacity overflow"))?;b.charge(reserve).map_err(|e|oom(b,e))?;
 let mut out=Vec::new();out.try_reserve_exact(requested).map_err(|e|oom(b,e))?;
 if out.capacity().checked_mul(size_of::<T>()).and_then(|n|n.checked_add(size_of::<Vec<T>>())).is_none_or(|n|n>reserve){return Err(oom(b,"reactive exposed row capacity exceeds admitted overlap"))}
 out.extend(iter);Ok(out)
}
impl FrozenReadSet{
 pub(crate) fn freeze(value:ReadSet,b:&Budget,checkpoint:&mut dyn FnMut()->io::Result<()>)->Result<Self,Failure>{
  checkpoint()?;
  // Each destination reservation is additional to every currently live old
  // collector allocation. Moving rows preserves their owned string buffers.
  let ReadSet{reads,ctx_fields,sites,diags,lookup_diags,effects,followed,opaque,internal,sampled}=value;
  let reads=rows(reads.into_iter(),b)?;checkpoint()?;
  let ctx_fields=rows(ctx_fields.into_iter(),b)?;checkpoint()?;
  let sites=rows(sites.into_iter(),b)?;checkpoint()?;
  let followed=rows(followed.into_iter(),b)?;checkpoint()?;
  let opaque=rows(opaque.into_iter(),b)?;checkpoint()?;
  let internal=rows(internal.into_iter(),b)?;checkpoint()?;
  let sampled=rows(sampled.into_iter(),b)?;checkpoint()?;
  Ok(Self{reads,ctx_fields,sites,diags,lookup_diags,effects,followed,opaque,internal,sampled})
 }
 pub fn reads(&self)->&[Read]{&self.reads}
 pub fn ctx_fields(&self)->&[(String,(String,u32))]{&self.ctx_fields}
 pub fn sites(&self)->&[(Read,(String,u32))]{&self.sites}
 pub fn diagnostics(&self)->&[Diag]{&self.diags}
 pub fn lookup_diagnostics(&self)->&[Diag]{&self.lookup_diags}
 pub fn effects(&self)->&[Effect]{&self.effects}
 pub fn followed(&self)->&[String]{&self.followed}
 pub fn opaque(&self)->&[(String,(String,u32))]{&self.opaque}
 pub fn internal(&self)->&[Read]{&self.internal}
 pub fn sampled(&self)->&[(String,u32)]{&self.sampled}
 pub fn site(&self,read:&Read)->Option<&(String,u32)>{self.sites.binary_search_by(|(key,_)|key.cmp(read)).ok().map(|i|&self.sites[i].1)}
 pub fn is_internal(&self,read:&Read)->bool{self.internal.binary_search(read).is_ok()}
 /// Actual exposed capacities. Standard allocator/header overhead is not RSS.
 /// No raw source/AST/model is owned by this immutable result.
 pub fn retained_charge(&self)->Option<usize>{let mut total=Some(size_of::<Self>());self.visit_storage(|_,_,_,capacity|total=total.and_then(|n|n.checked_add(capacity)));total}
 pub fn visit_storage(&self,mut visit:impl FnMut(&'static str,usize,usize,usize)){
  fn vector<T>(name:&'static str,value:&Vec<T>,visit:&mut impl FnMut(&'static str,usize,usize,usize)){visit(name,value.as_ptr() as usize,value.len()*size_of::<T>(),value.capacity()*size_of::<T>());}
  fn text(value:&String,visit:&mut impl FnMut(&'static str,usize,usize,usize)){visit("text",value.as_ptr() as usize,value.len(),value.capacity());}
  fn read(value:&Read,visit:&mut impl FnMut(&'static str,usize,usize,usize)){
   text(&value.root,visit);text(&value.var,visit);text(&value.owner,visit);vector("hops",&value.hops,visit);for hop in &value.hops{text(hop,visit);}
   if let ReadKind::Lookup(lookup)=&value.kind{
    visit("lookup",lookup.as_ref() as *const _ as usize,size_of::<crate::reactive_read_facts::LookupRead>(),size_of::<crate::reactive_read_facts::LookupRead>());
    text(&lookup.field,visit);let binding=&lookup.binding;text(&binding.registry,visit);text(&binding.identity_key,visit);text(&binding.lookup,visit);
    match &binding.argument{LookupArgument::Literal(value)=>text(value,visit),LookupArgument::Path{root,path}=>{text(root,visit);vector("lookup_path",path,visit);for part in path{text(part,visit);}}}
   }
  }
  vector("reads",&self.reads,&mut visit);for value in &self.reads{read(value,&mut visit);}
  vector("context_fields",&self.ctx_fields,&mut visit);for(key,(file,_))in &self.ctx_fields{text(key,&mut visit);text(file,&mut visit);}
  vector("sites",&self.sites,&mut visit);for(key,(file,_))in &self.sites{read(key,&mut visit);text(file,&mut visit);}
  for values in [&self.diags,&self.lookup_diags]{vector("diagnostics",values,&mut visit);for value in values{text(&value.rel,&mut visit);text(&value.msg,&mut visit);}}
  vector("effects",&self.effects,&mut visit);for value in &self.effects{text(&value.name,&mut visit);text(&value.owner,&mut visit);text(&value.proc,&mut visit);text(&value.rel,&mut visit);}
  vector("followed",&self.followed,&mut visit);for value in &self.followed{text(value,&mut visit);}
  vector("opaque",&self.opaque,&mut visit);for(key,(file,_))in &self.opaque{text(key,&mut visit);text(file,&mut visit);}
  vector("internal",&self.internal,&mut visit);for value in &self.internal{read(value,&mut visit);}
  vector("sampled",&self.sampled,&mut visit);for(file,_)in &self.sampled{text(file,&mut visit);}
 }
}
#[cfg(test)]mod tests{
 use super::*;
 fn value()->ReadSet{
  let mut value=ReadSet::default();let r=Read{root:"holder".into(),hops:vec!["link".into()],var:"value".into(),owner:"/datum/probe".into(),kind:ReadKind::Var,hop_ok:true};value.reads.insert(r.clone());value.internal.insert(r.clone());value.sites.insert(r,("code/probe.dm".into(),4));value.ctx_fields.insert("actor".into(),("code/probe.dm".into(),3));value.followed.insert("/datum/probe::p".into());value.opaque.insert("/datum/probe::q".into(),("code/probe.dm".into(),5));value.sampled.insert(("code/probe.dm".into(),6));
  value.diags.push(Diag{rule:"unknown_field",closed_only:false,rel:"z.dm".into(),line:9,msg:"first ordered diagnostic".into()});value.diags.push(Diag{rule:"dynamic_read",closed_only:true,rel:"a.dm".into(),line:1,msg:"second ordered diagnostic".into()});value.lookup_diags.push(value.diags[1].clone());value.effects.push(Effect{kind:"assign",name:"value".into(),owner:"/datum/probe".into(),proc:"p".into(),rel:"code/probe.dm".into(),line:4});value
 }
 #[test]fn frozen_rows_move_same_buffers_and_preserve_all_field_order(){
  let input=value();let string=input.reads.iter().next().unwrap().var.as_ptr();let budget=Budget::new(1024*1024).unwrap();let out=FrozenReadSet::freeze(input,&budget,&mut||Ok(())).unwrap();assert_eq!(out.reads()[0].var.as_ptr(),string,"owned result buffer moved, not cloned");assert_eq!(out.diagnostics()[0].rel,"z.dm");assert_eq!(out.diagnostics()[1].rel,"a.dm");assert_eq!(out.lookup_diagnostics().len(),1);assert_eq!(out.effects().len(),1);assert_eq!(out.followed().len(),1);assert_eq!(out.opaque().len(),1);assert_eq!(out.sampled().len(),1);assert!(out.is_internal(&out.reads()[0]));assert_eq!(out.site(&out.reads()[0]).unwrap().1,4);
  let mut capacity=0;out.visit_storage(|_,_,_,n|capacity+=n);assert_eq!(out.retained_charge(),Some(size_of::<FrozenReadSet>()+capacity));assert!(serde_json::to_string(&out).unwrap().contains("first ordered diagnostic"));
 }
 #[test]fn frozen_overlap_denial_is_operational_and_fresh_same_input_recovers(){
  let fixed=size_of::<Budget>()+2*size_of::<usize>();let budget=Budget::new(fixed).unwrap();assert_eq!(budget.used(),fixed,"actual budget exists but has no payload headroom");assert!(matches!(FrozenReadSet::freeze(value(),&budget,&mut||Ok(())),Err(Failure::Operational(ref e))if e.kind()==io::ErrorKind::OutOfMemory));assert!(budget.denied());let fresh=Budget::new(1024*1024).unwrap();assert!(FrozenReadSet::freeze(value(),&fresh,&mut||Ok(())).is_ok());
 }
}

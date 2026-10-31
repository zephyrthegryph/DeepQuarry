//! Shared auto-tracking collision and inheritance policy. No parser/cache/model.
use std::collections::{BTreeMap,BTreeSet,HashMap};
use crate::key_policy_control::{self as kc,Control};
#[derive(Clone,Debug,PartialEq,Eq,PartialOrd,Ord)]pub struct Auto{pub ty:String,pub var:String,pub list:bool}
#[derive(Default)]pub struct AutoSet{pub tracked:Vec<Auto>,pub blocked:Vec<(String,String,String)>}
pub struct Variable{pub file:String,pub is_static:bool,pub is_const:bool,pub is_list:bool}
pub trait Source:Control{
 fn variable(&mut self,owner:&str,var:&str)->Result<Option<Variable>,Self::Error>;
 fn subtype(&mut self,child:&str,parent:&str)->Result<bool,Self::Error>;
 fn var_owner(&mut self,owner:&str,var:&str)->Result<Option<String>,Self::Error>;
}
const RESERVED:&[&str]=&["value","src","usr","null","world"];
fn reason<S:Source>(s:&mut S,text:&str)->Result<Option<String>,S::Error>{Ok(Some(kc::own(s,text)?))}
fn related<S:Source>(s:&mut S,owner:&str,ty:&str)->Result<bool,S::Error>{Ok(s.subtype(owner,ty)?||s.subtype(ty,owner)?)}
fn blocked<S:Source>(s:&mut S,defs:&HashMap<String,Vec<String>>,exclude:&[String],owner:&str,var:&str)->Result<Option<String>,S::Error>{
 s.checkpoint()?;
 if RESERVED.contains(&var){return reason(s,"a reserved name")}
 if exclude.iter().any(|e|e==var||e.strip_prefix(owner).and_then(|r|r.strip_prefix("::"))==Some(var)){return reason(s,"excluded in tools/ci/lint_scopes.toml [lint.auto_tracked.lists] exclude")}
 let Some(sig)=s.variable(owner,var)?else{return reason(s,"no declaration")};
 if sig.file.is_empty(){return reason(s,"a built-in var")}
 if sig.file==crate::auto_setter_calls_policy::AUTO_REL{return reason(s,"declared in the generated file")}
 if crate::reactive_read_facts::ENGINE_DIRS.iter().any(|d|sig.file.starts_with(d))&&!sig.file.starts_with("code/modules/tgui/modules/"){return reason(s,"engine-internal state: the framework's own bookkeeping publishes itself")}
 if sig.file.contains("benchmarks/"){return reason(s,"declared in a benchmark file, which only the bench build compiles")}
 if sig.is_static||sig.is_const{return reason(s,"static or const")}
 if !s.subtype(owner,"/datum")?{return reason(s,"not a /datum type")}
 if s.subtype(owner,"/datum/record")?{return reason(s,"a profile record: its fields are TRACKED_DATA, and a record holds data only")}
 if s.var_owner(owner,var)?.as_deref()!=Some(owner){return reason(s,"declared on another type")}
 let name=kc::format(s,format_args!("set_{}",var))?;
 if let Some(types)=defs.get(&name){for ty in types{s.checkpoint()?;if related(s,owner,ty)?{return Ok(Some(kc::format(s,format_args!("{} already defines {}()",ty,name))?))}}}
 if sig.is_list{
  for (prefix,suffix)in [("add_",""),("include_",""),("remove_",""),("set_","_at"),("clear_",""),("insert_",""),("swap_",""),("cut_","")]{
   let name=kc::format(s,format_args!("{}{}{}",prefix,var,suffix))?;
   if let Some(types)=defs.get(&name){for ty in types{s.checkpoint()?;if related(s,owner,ty)?{return Ok(Some(kc::format(s,format_args!("{} already defines {}(), a list mutator the generator would write",ty,name))?))}}}
  }
 }
 if sig.is_list{let version=kc::format(s,format_args!("{}_version",var))?;if s.variable(owner,&version)?.is_some_and(|v|v.file!="code/engine/_generated/tracked_lists.dm"){return reason(s,"the list's _version var is taken")}}
 Ok(None)
}
pub fn decide<S:Source>(source:&mut S,defs:&HashMap<String,Vec<String>>,candidates:&BTreeSet<(String,String)>,exclude:&[String])->Result<AutoSet,S::Error>{
 let mut out=AutoSet::default();let mut kept=Vec::new();
 for(owner,var)in candidates{
  let why=blocked(source,defs,exclude,owner,var)?;
  match why{Some(why)=>{let owner=kc::own(source,owner)?;let var=kc::own(source,var)?;kc::row(source,&mut out.blocked)?;out.blocked.push((owner,var,why));},None=>{let list=source.variable(owner,var)?.is_some_and(|v|v.is_list);let ty=kc::own(source,owner)?;let var=kc::own(source,var)?;kc::row(source,&mut kept)?;kept.push(Auto{ty,var,list});}}
 }
 let mut by_var:BTreeMap<&str,Vec<&Auto>>=BTreeMap::new();
 for a in &kept{source.checkpoint()?;if !by_var.contains_key(a.var.as_str()){kc::reserve(source,||Some(256))?;}let entries=by_var.entry(a.var.as_str()).or_default();kc::row(source,entries)?;entries.push(a);}
 for a in &kept{
  source.checkpoint()?;let mut shadowed=false;
  for b in &by_var[a.var.as_str()]{source.checkpoint()?;if b.ty!=a.ty&&source.subtype(&a.ty,&b.ty)?{shadowed=true;break}}
  if shadowed{let ty=kc::own(source,&a.ty)?;let var=kc::own(source,&a.var)?;let why=kc::own(source,"an ancestor tracks it")?;kc::row(source,&mut out.blocked)?;out.blocked.push((ty,var,why));}
  else{let ty=kc::own(source,&a.ty)?;let var=kc::own(source,&a.var)?;kc::row(source,&mut out.tracked)?;out.tracked.push(Auto{ty,var,list:a.list});}
 }
 source.checkpoint()?;out.tracked.sort();out.blocked.sort();source.checkpoint()?;Ok(out)
}

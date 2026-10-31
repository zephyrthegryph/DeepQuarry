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

/// Borrowed adapters over the SAME typed-call result; never a converted map.
pub enum TypedReceivers<'a>{Tree(std::collections::btree_set::Iter<'a,String>),Rows(std::slice::Iter<'a,(String,String)>)}
impl<'a> Iterator for TypedReceivers<'a>{type Item=&'a str;fn next(&mut self)->Option<Self::Item>{match self{Self::Tree(values)=>values.next().map(String::as_str),Self::Rows(values)=>values.next().map(|row|row.1.as_str())}}}
pub trait TypedCalls{fn receivers(&self,name:&str)->Option<TypedReceivers<'_>>;}
impl TypedCalls for HashMap<String,BTreeSet<String>>{fn receivers(&self,name:&str)->Option<TypedReceivers<'_>>{self.get(name).map(|values|TypedReceivers::Tree(values.iter()))}}
impl<T:TypedCalls+?Sized> TypedCalls for &T{fn receivers(&self,name:&str)->Option<TypedReceivers<'_>>{T::receivers(*self,name)}}
impl<T:TypedCalls+?Sized> TypedCalls for std::sync::Arc<T>{fn receivers(&self,name:&str)->Option<TypedReceivers<'_>>{T::receivers(self.as_ref(),name)}}
pub fn called_here<S:Source,T:TypedCalls>(source:&mut S,defs:&HashMap<String,Vec<String>>,typed:impl FnOnce()->Result<T,S::Error>,calls:&BTreeSet<String>,owner:&str,var:&str)->Result<bool,S::Error>{
 source.checkpoint()?;let plain=calls.contains(var);let list=kc::format(source,format_args!("{}{}",var,crate::auto_setter_calls_policy::LIST_CALL))?;
 if !plain&&!calls.contains(&list){return Ok(false)}
 let mut names=Vec::new();
 for(prefix,suffix)in[("set_",""),("add_",""),("include_",""),("remove_",""),("set_","_at"),("clear_",""),("insert_",""),("swap_",""),("cut_","")]{let name=kc::format(source,format_args!("{}{}{}",prefix,var,suffix))?;kc::row(source,&mut names)?;names.push(name);}
 let typed=typed()?;
 let mut has_typed=false;
 for name in &names{source.checkpoint()?;if let Some(types)=typed.receivers(name){has_typed=true;for ty in types{source.checkpoint()?;if (source.subtype(ty,owner)?||source.subtype(owner,ty)?){return Ok(true)}}}}
 if has_typed{return Ok(false)}
 for name in &names{source.checkpoint()?;if let Some(types)=defs.get(name){for ty in types{source.checkpoint()?;if !(source.subtype(ty,owner)?||source.subtype(owner,ty)?){return Ok(false)}}}}
 source.checkpoint()?;Ok(true)
}

/// The write predicate is the old OUTSIDE-setters index, never all writes.
pub trait ReactiveSource:Source{fn declared_reactive(&mut self,owner:&str,var:&str)->Result<bool,Self::Error>;}
pub trait CandidateSource:ReactiveSource{
 fn outside_written_on(&mut self,owner:&str,var:&str)->Result<bool,Self::Error>;
}
pub fn named_candidate<S:ReactiveSource>(source:&mut S,owner:&str,var:&str)->Result<bool,S::Error>{
 source.checkpoint()?;if source.declared_reactive(owner,var)?{return Ok(false)}
 let result=!source.variable(owner,var)?.is_some_and(|v|v.is_const);source.checkpoint()?;Ok(result)
}
pub fn candidate<S:CandidateSource>(source:&mut S,calls:&BTreeSet<String>,owner:&str,var:&str)->Result<bool,S::Error>{
 source.checkpoint()?;if source.declared_reactive(owner,var)?{return Ok(false)}
 if source.variable(owner,var)?.is_some_and(|v|v.is_const){return Ok(false)}
 if source.outside_written_on(owner,var)?||calls.contains(var){return Ok(true)}
 let list=kc::format(source,format_args!("{}{}",var,crate::auto_setter_calls_policy::LIST_CALL))?;
 let result=calls.contains(&list)&&source.variable(owner,var)?.is_some_and(|v|v.is_list);source.checkpoint()?;Ok(result)
}

#[cfg(test)]mod candidate_tests{
 use super::*;
 struct Probe{reactive:bool,constant:bool,list:bool,written:bool,queries:usize,relations:Vec<(String,String)>}
 impl Control for Probe{type Error=std::io::Error;const CHECKED:bool=true;fn checkpoint(&mut self)->Result<(),Self::Error>{Ok(())}fn reserve(&mut self,_:usize)->Result<(),Self::Error>{Ok(())}fn overflow(&mut self)->Self::Error{std::io::ErrorKind::OutOfMemory.into()}fn allocation_failed(&mut self)->Self::Error{std::io::ErrorKind::OutOfMemory.into()}}
 impl Source for Probe{
  fn variable(&mut self,_:&str,_:&str)->Result<Option<Variable>,Self::Error>{Ok(Some(Variable{file:"code/probe.dm".into(),is_static:false,is_const:self.constant,is_list:self.list}))}
  fn subtype(&mut self,a:&str,b:&str)->Result<bool,Self::Error>{self.relations.push((a.into(),b.into()));Ok(a==b)}
  fn var_owner(&mut self,o:&str,_:&str)->Result<Option<String>,Self::Error>{Ok(Some(o.into()))}
 }
 impl ReactiveSource for Probe{fn declared_reactive(&mut self,_:&str,_:&str)->Result<bool,Self::Error>{Ok(self.reactive)}}
 impl CandidateSource for Probe{fn outside_written_on(&mut self,_:&str,_:&str)->Result<bool,Self::Error>{self.queries+=1;Ok(self.written)}}
 fn probe()->Probe{Probe{reactive:false,constant:false,list:false,written:false,queries:0,relations:Vec::new()}}
 #[test]fn candidate_short_circuit_and_list_policy_match_original_boolean_expression(){
  for reactive in [false,true]{for constant in [false,true]{for list in [false,true]{for written in [false,true]{for call in ["","charge","charge[]"]{
   let mut s=Probe{reactive,constant,list,written,..probe()};let calls=BTreeSet::from([call.into()]);
   let expected=!reactive&&!constant&&(written||calls.contains("charge")||(calls.contains("charge[]")&&list));
   assert_eq!(candidate(&mut s,&calls,"/datum/probe","charge").unwrap(),expected);
   assert_eq!(s.queries,usize::from(!reactive&&!constant),"outside-setter graph is demanded only after old short circuits");
   assert_eq!(named_candidate(&mut s,"/datum/probe","charge").unwrap(),!reactive&&!constant);
  }}}}}
 }
 #[test]fn called_here_keeps_lazy_typed_precedence_and_old_relation_query_order(){
  let mut s=probe();assert!(!called_here(&mut s,&HashMap::new(),||->Result<HashMap<String,BTreeSet<String>>,std::io::Error>{panic!("no setter name, no body scan")},&BTreeSet::new(),"/datum/probe","charge").unwrap());
  let calls=BTreeSet::from(["charge".into()]);let typed=HashMap::from([("set_charge".into(),BTreeSet::from(["?".into()]))]);
  assert!(!called_here(&mut s,&HashMap::new(),||Ok(&typed),&calls,"/datum/probe","charge").unwrap());
  assert_eq!(s.relations,vec![("?".into(),"/datum/probe".into()),("/datum/probe".into(),"?".into())]);
  let empty=HashMap::new();let defs=HashMap::from([("set_charge".into(),vec!["/datum/other".into()])]);
  assert!(!called_here(&mut s,&defs,||Ok(&empty),&calls,"/datum/probe","charge").unwrap());
  let typed=HashMap::from([("set_charge".into(),BTreeSet::from(["/datum/probe".into()]))]);
  assert!(called_here(&mut s,&defs,||Ok(&typed),&calls,"/datum/probe","charge").unwrap(),"typed related receiver wins before unrelated definition fallback");
 }
}

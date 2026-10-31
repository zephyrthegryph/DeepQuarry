//! Exact legacy typed setter receiver transitions. No body/type model or cache.
use crate::key_policy_control::{self as kc,Control};
use std::collections::HashMap;
pub const UNTYPED:&str="?";
pub const SETTER_PREFIXES:&[&str]=&["set_","add_","include_","remove_","clear_","insert_","swap_","cut_"];
pub fn is_setter(name:&str)->bool{SETTER_PREFIXES.iter().any(|prefix|name.starts_with(prefix))}
pub trait Source:Control{
 fn variable_type(&mut self,owner:&str,name:&str)->Result<Option<String>,Self::Error>;
 fn record(&mut self,name:&str,receiver:&str)->Result<(),Self::Error>;
}
pub enum Base<'a>{Ident(&'a str),Call(&'a str),Unknown}
pub fn begin<S:Source>(source:&mut S,owner:&str,locals:&HashMap<String,String>,base:Base<'_>)->Result<Option<String>,S::Error>{
 source.checkpoint()?;match base{
  Base::Ident("src")=>Ok(Some(kc::own(source,owner)?)),
  Base::Ident(name)=>match locals.get(name){Some(ty)=>Ok(Some(kc::own(source,ty)?)),None=>Ok(source.variable_type(owner,name)?.filter(|ty|!ty.is_empty()))},
  Base::Call(name)=>{call(source,&None,name,Some(owner))?;Ok(None)},
  Base::Unknown=>Ok(None),
 }
}
pub fn field<S:Source>(source:&mut S,current:Option<String>,name:&str)->Result<Option<String>,S::Error>{source.checkpoint()?;match current{Some(owner)=>Ok(source.variable_type(&owner,name)?.filter(|ty|!ty.is_empty())),None=>Ok(None)}}
pub fn call<S:Source>(source:&mut S,current:&Option<String>,name:&str,bare_owner:Option<&str>)->Result<(),S::Error>{source.checkpoint()?;if is_setter(name){source.record(name,bare_owner.or(current.as_deref()).unwrap_or(UNTYPED))?;}Ok(())}

#[cfg(test)]mod tests{
 use super::*;use std::{collections::BTreeSet,convert::Infallible,sync::Arc};
 #[derive(Default)]struct Probe{hits:Vec<(String,String)>}
 impl Control for Probe{type Error=Infallible;const CHECKED:bool=false;fn checkpoint(&mut self)->Result<(),Self::Error>{Ok(())}fn reserve(&mut self,_:usize)->Result<(),Self::Error>{Ok(())}fn overflow(&mut self)->Self::Error{unreachable!()}fn allocation_failed(&mut self)->Self::Error{unreachable!()}}
 impl Source for Probe{fn variable_type(&mut self,owner:&str,name:&str)->Result<Option<String>,Infallible>{Ok(match(owner,name){("/holder","usr")=>Some("/mob".into()),("/datum/a","next")=>Some("/datum/b".into()),_=>None})}fn record(&mut self,name:&str,receiver:&str)->Result<(),Infallible>{self.hits.push((name.into(),receiver.into()));Ok(())}}
 impl crate::auto_tracking_policy::Source for Probe{fn variable(&mut self,_:&str,_:&str)->Result<Option<crate::auto_tracking_policy::Variable>,Infallible>{Ok(None)}fn subtype(&mut self,a:&str,b:&str)->Result<bool,Infallible>{Ok(a==b)}fn var_owner(&mut self,_:&str,_:&str)->Result<Option<String>,Infallible>{Ok(None)}}
 #[test]fn exact_receiver_transitions_keep_usr_ordinary_and_reset_after_calls(){let mut source=Probe::default();let locals=HashMap::from([("x".into(),"/datum/a".into())]);assert_eq!(begin(&mut source,"/holder",&locals,Base::Ident("usr")).unwrap().as_deref(),Some("/mob"));let current=begin(&mut source,"/holder",&locals,Base::Ident("x")).unwrap();let current=field(&mut source,current,"next").unwrap();call(&mut source,&current,"set_charge",None).unwrap();let after=begin(&mut source,"/holder",&locals,Base::Call("set_one")).unwrap();assert!(after.is_none());let after=field(&mut source,after,"field").unwrap();call(&mut source,&after,"add_items",None).unwrap();assert_eq!(source.hits,vec![("set_charge".into(),"/datum/b".into()),("set_one".into(),"/holder".into()),("add_items".into(),"?".into())]);}
 #[test]fn typed_receiver_adapters_preserve_empty_set_presence_and_lazy_called_here(){use crate::auto_tracking_policy::{TypedCalls,called_here};let map=HashMap::from([("set_charge".to_owned(),BTreeSet::<String>::new())]);assert!(map.receivers("set_charge").unwrap().next().is_none());assert!(map.receivers("absent").is_none());let arc=Arc::new(map);assert!((&arc).receivers("set_charge").is_some());let mut source=Probe::default();assert!(!called_here(&mut source,&HashMap::new(),||->Result<&HashMap<String,BTreeSet<String>>,Infallible>{panic!("typed facts must stay lazy when lexical call names are absent")},&BTreeSet::new(),"/holder","charge").unwrap());let calls=BTreeSet::from(["charge".to_owned()]);assert!(!called_here(&mut source,&HashMap::new(),||Ok(Arc::clone(&arc)),&calls,"/holder","charge").unwrap(),"present empty typed set must suppress definition-only fallback");}
}

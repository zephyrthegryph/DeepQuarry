//! Unique sem/handlers pooled-context policy over borrowed expression facts.
//! Syntax adapters supply canonical names/arguments; no parser/model lives here.
use crate::key_policy_control::{self as kc,Control};use std::collections::BTreeSet;
pub trait Expression{fn bare_name(&self)->Option<&str>;fn named_rhs(&self)->Option<&Self>;}
#[derive(Clone,Copy)]pub enum CallKind<'a>{Ordinary(&'a str),New,List,Follow(&'a str)}
pub struct Call<'a,E>{pub kind:CallKind<'a>,pub args:&'a[E]}
fn act<'a,E:Expression>(e:&'a E,acts:&BTreeSet<String>)->Option<&'a str>{e.bare_name().filter(|name|acts.contains(*name))}
pub fn store_using<C:Control>(lhs:Option<&str>,rhs:Option<&str>,is_named:bool,acts:&BTreeSet<String>,locals:&BTreeSet<String>,c:&mut C,emit:&mut impl FnMut(String)->Result<(),C::Error>)->Result<(),C::Error>{c.checkpoint()?;if !is_named&&rhs.is_some_and(|name|acts.contains(name))&&!lhs.is_some_and(|name|locals.contains(name)){let name=rhs.expect("checked bare context");emit(kc::format(c,format_args!("`{name}` is a pooled context and is stored where it can outlive the trigger; use {name}.snapshot()"))?)?;}Ok(())}
pub fn base_using<'a,C:Control,E:Expression>(calls:&[Call<'a,E>],acts:&BTreeSet<String>,c:&mut C,mark_named:&mut impl FnMut(&'a E)->Result<(),C::Error>,emit:&mut impl FnMut(String)->Result<(),C::Error>)->Result<(),C::Error>{
 // Original Base marks ALL term/follow named args before emitting any report
 // or descending, including names which occur in later follow calls.
 for call in calls{c.checkpoint()?;if matches!(call.kind,CallKind::List){continue}for arg in call.args{c.checkpoint()?;if arg.named_rhs().is_some(){mark_named(arg)?;}}}
 for call in calls{c.checkpoint()?;if matches!(call.kind,CallKind::List){for arg in call.args{c.checkpoint()?;if let Some(name)=act(arg,acts){emit(kc::format(c,format_args!("`{name}` is put in a list; use {name}.snapshot()"))?)?;}}continue}
  let what=match call.kind{CallKind::Ordinary(name)|CallKind::Follow(name)=>name,CallKind::New=>"new",CallKind::List=>unreachable!()};
  for arg in call.args{c.checkpoint()?;if let Some(name)=arg.named_rhs().and_then(|rhs|act(rhs,acts)){emit(kc::format(c,format_args!("`{name}` is passed in with = to {what}; use {name}.snapshot()"))?)?;}}
  if matches!(call.kind,CallKind::Follow("Add"|"Insert")){for arg in call.args{c.checkpoint()?;if let Some(name)=act(arg,acts){emit(kc::format(c,format_args!("`{name}` is added to a list; use {name}.snapshot()"))?)?;}}}
 }c.checkpoint()?;Ok(())
}
#[cfg(test)]mod tests{
 use super::*;#[derive(Clone)]enum E{Name(&'static str),Named(Box<E>)}impl Expression for E{fn bare_name(&self)->Option<&str>{match self{Self::Name(n)=>Some(n),_=>None}}fn named_rhs(&self)->Option<&Self>{match self{Self::Named(e)=>Some(e),_=>None}}}
 #[test]fn same_named_store_list_and_follow_contracts_preserve_message_text_and_mark_before_emit(){let acts=BTreeSet::from(["A".to_owned()]);let locals=BTreeSet::from(["alias".to_owned()]);let term=[E::Named(Box::new(E::Name("A")))];let list=[E::Name("A")];let follow=[E::Name("A"),E::Named(Box::new(E::Name("A")))];let mut marks=Vec::new();let mut rows=Vec::new();base_using(&[Call{kind:CallKind::Ordinary("f"),args:&term},Call{kind:CallKind::List,args:&list},Call{kind:CallKind::Follow("Insert"),args:&follow}],&acts,&mut kc::Compatibility,&mut|e|{marks.push(e as*const E as usize);Ok(())},&mut|message|{rows.push(message);Ok(())}).unwrap();assert_eq!(marks.len(),2);assert_eq!(rows,["`A` is passed in with = to f; use A.snapshot()","`A` is put in a list; use A.snapshot()","`A` is passed in with = to Insert; use A.snapshot()","`A` is added to a list; use A.snapshot()"]);let mut out=Vec::new();for(lhs,named)in[(Some("alias"),false),(None,true),(None,false)]{store_using(lhs,Some("A"),named,&acts,&locals,&mut kc::Compatibility,&mut|m|{out.push(m);Ok(())}).unwrap()}assert_eq!(out,["`A` is a pooled context and is stored where it can outlive the trigger; use A.snapshot()"]);}
}

#[cfg(all(test,feature="legacy-sem"))]#[path="../fixtures/native-sem-handlers/oracle.rs"]mod immutable;
#[cfg(all(test,feature="legacy-sem"))]mod old_projection_controls{
 use super::*;
 #[test]fn actual_old_body_projection_keeps_frozen_context_escape_order_and_list_named_assignment_trap(){
  for written in ["saved = A", "var/local\n    local = A", "f(with = A)", "list(A)", "list(with = A)", "items.Insert(A, with = A)", "new /datum(with = A)", "f(with = A).Insert(A, with = A)"]{
   let text=format!("/datum/act\n/datum/probe\n    var/saved\n    var/list/items\n    proc/p(datum/act/A)\n        {}\n",written.replace("\n    ","\n        "));let tree=crate::tree::Tree::from_files(vec![crate::tree::SourceFile::from_text("code/escape-control.dm",&text)]);let sem=crate::sem::sem_for(&tree).expect("actual old source model");let proc=sem.proc_ref("/datum/probe","p").unwrap();let body=sem.proc_body(proc);let code=body.code.unwrap();let(acts,locals)=immutable::checks::act_idents(body.params,code,crate::sem_handlers_partial_recipe::DEFAULT_TRY_CALLS);let mut old=Vec::new();let mut actual=Vec::new();immutable::checks::context_escape(code,&acts,&locals,&mut old);crate::sem::checks::context_escape(code,&acts,&locals,&mut actual);assert_eq!(old.iter().map(|f|(f.rule,f.line,f.msg.as_str())).collect::<Vec<_>>(),actual.iter().map(|f|(f.rule,f.line,f.msg.as_str())).collect::<Vec<_>>(),"frozen independent context policy and projection: {written}");
  }
 }
}

#[cfg(test)]mod denied_controls{use super::*;struct Denied;impl Control for Denied{type Error=std::io::Error;const CHECKED:bool=true;fn checkpoint(&mut self)->Result<(),Self::Error>{Ok(())}fn reserve(&mut self,_:usize)->Result<(),Self::Error>{Err(std::io::Error::from_raw_os_error(1450))}fn overflow(&mut self)->Self::Error{std::io::ErrorKind::OutOfMemory.into()}fn allocation_failed(&mut self)->Self::Error{std::io::ErrorKind::OutOfMemory.into()}}#[test]fn failed_message_admission_preserves_real_io_and_emits_no_unfunded_message(){let acts=BTreeSet::from(["A".to_owned()]);let mut emitted=false;let actual=store_using(None,Some("A"),false,&acts,&BTreeSet::new(),&mut Denied,&mut|_|{emitted=true;Ok(())}).unwrap_err();assert_eq!(actual.raw_os_error(),Some(1450));assert!(!emitted);}}

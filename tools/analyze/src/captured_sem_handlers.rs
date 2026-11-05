//! Whole-handler aggregation DATA. Host source/preparation/child witnesses
//! remain separate; this cannot issue full/partial/raw or compiler authority.
use crate::{captured_generator_budget::Budget,captured_reactive_reads::Failure,captured_allow_annotations::Operation,key_policy_control::{self as kc,Control},lint::{Site,AllowUse},tree::SourceFile};
use std::{sync::Arc,io,collections::BTreeMap};
fn quota(b:&Budget,message:String)->Failure{b.deny();Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message))}
pub struct Data{sites:Vec<Site>,source_text:Vec<String>,allows:Vec<AllowUse>,digests:BTreeMap<String,[u8;20]>}
impl Data{
 pub fn metadata(&self)->&'static crate::lint::Meta{crate::sem_handlers_policy::metadata()}
 pub fn sites(&self)->&[Site]{&self.sites}pub fn allow_used(&self)->&[AllowUse]{&self.allows}
 pub fn source_text(&self)->&[String]{&self.source_text}
 pub fn allow_digests(&self)->&BTreeMap<String,[u8;20]>{&self.digests}
 pub fn retained_charge(&self)->Option<usize>{let mut n=std::mem::size_of::<Self>().checked_add(self.sites.capacity().checked_mul(std::mem::size_of::<Site>())?)?.checked_add(self.source_text.capacity().checked_mul(std::mem::size_of::<String>())?)?.checked_add(self.allows.capacity().checked_mul(std::mem::size_of::<AllowUse>())?)?;for row in &self.sites{n=n.checked_add(row.rule.capacity())?.checked_add(row.rel.capacity())?.checked_add(row.msg.capacity())?.checked_add(row.key.capacity())?.checked_add(row.ident.capacity())?;}for text in &self.source_text{n=n.checked_add(text.capacity())?;}for row in &self.allows{n=n.checked_add(row.rel.capacity())?.checked_add(row.name.capacity())?.checked_add(row.code.capacity())?;}for key in self.digests.keys(){n=n.checked_add(key.capacity())?.checked_add(256)?;}Some(n)}
 pub fn serialize_data<S:serde::Serializer>(&self,s:S)->Result<S::Ok,S::Error>{serde::Serialize::serialize(&(&self.sites,&self.source_text,&self.allows,&self.digests),s)}
}
/// Single old put() scope across partial structural, independently demanded
/// full declared handlers, and standard outputs, before actual raw ALLOW lookup.
/// Raw view closure None is DATA: the host must prove genuine old-tree absence.
pub struct Builder<'a>{seen:crate::sem_handlers_report_policy::Seen,data:Data,budget:&'a Arc<Budget>,poll:&'a dyn Fn()->io::Result<()>}
impl<'a> Builder<'a>{
 pub fn new(budget:&'a Arc<Budget>,poll:&'a dyn Fn()->io::Result<()>)->Result<Self,Failure>{poll()?;budget.require().map_err(|m|quota(budget,m))?;Ok(Self{seen:Default::default(),data:Data{sites:Vec::new(),source_text:Vec::new(),allows:Vec::new(),digests:BTreeMap::new()},budget,poll})}
 pub fn push(&mut self,rule:&str,relative:&str,line:u32,message:&str,loan:&mut dyn FnMut(&str,&mut dyn FnMut(Option<crate::captured_raw_file::RawPolicyViews<'_>>)->Result<(),Failure>)->Result<(),Failure>)->Result<(),Failure>{
  let mut c=Operation{budget:self.budget,poll:self.poll};if !self.seen.admit_using(rule,relative,line,message,&mut c)?{return Ok(())}
  let mut calls=0usize;let mut allowed=false;let mut source_text=String::new();loan(relative,&mut|file|{calls+=1;if calls!=1{return Err("handler report raw ALLOW callback repeated".into())}let Some(views)=file else{return Ok(())};let file=views.source_file()?;if file.rel!=relative{return Err("handler report raw ALLOW file differs".into())}
   let Some(kept)=crate::allow::kept_using(file,line as usize,crate::sem_handlers_report_policy::ALLOW_NAME,&mut c)?else{let actual=file.raw().line(line as usize);kc::reserve(&mut c,||actual.len().checked_mul(4)?.checked_add(128))?;source_text=crate::util::normalize_ws(actual);return Ok(())};allowed=true;let code=kept.code.unwrap_or_default();let name=crate::sem_handlers_report_policy::ALLOW_NAME;
   if !self.data.allows.iter().any(|row|row.rel==relative&&row.line as usize==kept.line&&row.name==name&&row.code==code){kc::row(&mut c,&mut self.data.allows)?;self.budget.charge(code.capacity()).map_err(|m|quota(self.budget,m))?;self.data.allows.push(AllowUse{rel:kc::own(&mut c,relative)?,line:u32::try_from(kept.line).map_err(|_|Failure::from("actual handler ALLOW line overflows wire coordinate"))?,name:kc::own(&mut c,name)?,code});}
   if !self.data.digests.contains_key(relative){kc::reserve(&mut c,||Some(2048))?;self.data.digests.insert(kc::own(&mut c,relative)?,crate::captured_raw_file::source_allow_digest(file));}Ok(())
  })?;if calls!=1{return Err("handler report raw ALLOW callback omitted".into())}if allowed{return Ok(())}
  kc::row(&mut c,&mut self.data.source_text)?;self.data.source_text.push(source_text);kc::row(&mut c,&mut self.data.sites)?;self.data.sites.push(Site{rule:kc::own(&mut c,rule)?,rel:kc::own(&mut c,relative)?,line,msg:kc::own(&mut c,message)?,key:String::new(),ident:String::new()});c.checkpoint()?;Ok(())
 }
 pub fn finish(self)->Result<Data,Failure>{(self.poll)()?;self.budget.require().map_err(|m|quota(self.budget,m))?;Ok(self.data)}
}
#[cfg(test)]mod controls{
 use super::*;
 #[test]fn all_three_handler_partitions_share_old_dedup_before_actual_allow_trace(){
  let file=SourceFile::from_text("code/a.dm","/proc/p()\n    return 2 // ALLOW(handlers): retained old annotation behavior for actual callback\n");let b=Budget::new(4<<20).unwrap();let mut builder=Builder::new(&b,&||Ok(())).unwrap();let mut old=crate::lint::Sink::new();let mut seen=std::collections::HashSet::new();let mut loans=0;for(rule,relative,line,message)in[("signature","",1,"blank"),("signature","code/a.dm",1,"same"),("signature","code/a.dm",1,"same"),("context_escape","code/a.dm",1,"same"),("impure","code/a.dm",2,"veto"),("impure","code/a.dm",2,"veto"),("output_signature","code/a.dm",2,"veto")]{if !relative.is_empty()&&seen.insert((rule.to_owned(),relative.to_owned(),line,message.to_owned())){if !old.allowed(&file,line as usize,"handlers"){old.site_in_msg(rule,relative,line as usize,message)}}builder.push(rule,relative,line,message,&mut|_,consume|{loans+=1;consume(Some(crate::captured_raw_file::RawPolicyViews::from_source(&file)))}).unwrap();}let data=builder.finish().unwrap();assert_eq!(data.sites,old.sites);assert_eq!(data.allows,old.allow_used);assert_eq!(data.source_text.len(),data.sites.len());assert_eq!(crate::baseline::SiteText::site_text(&data,"code/a.dm",1),"/proc/p()");assert_eq!(loans,4,"duplicate rows never look up ALLOW; different rule tuples still do");assert!(data.retained_charge().unwrap()>0);
 }
 #[test]fn actual_handler_report_raw_loan_error_is_first_and_omission_is_not_clean(){let budget=Budget::new(4<<20).unwrap();let mut data=Builder::new(&budget,&||Ok(())).unwrap();let error=data.push("signature","code/a.dm",2,"bad",&mut|_,_|Err(Failure::Operational(io::Error::from_raw_os_error(1450)))).unwrap_err();assert!(matches!(error,Failure::Operational(error)if error.raw_os_error()==Some(1450)));let mut data=Builder::new(&budget,&||Ok(())).unwrap();assert!(matches!(data.push("signature","code/a.dm",2,"bad",&mut|_,_|Ok(())),Err(Failure::Unsupported(_))));}
}

impl crate::baseline::SiteText for Data{fn site_text(&self,relative:&str,line:usize)->String{self.sites.iter().zip(&self.source_text).find(|(site,_)|site.rel==relative&&site.line as usize==line).map(|(_,text)|text.clone()).unwrap_or_default()}}

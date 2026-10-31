//! Explicit native read factory over the SAME captured raw and native owners.
//! No producer installation or source acquisition. Returned data has no AST.
use crate::{captured_generator_budget::Budget,captured_raw_policy::CapturedRawPolicy,reactive_original_source::ReadSource,reactive_policy_facts_native::PolicyFacts,reactive_reads_native::{self,Directives},reactive_global_facts_native::NativeGlobals};
use dm_analysis::policy_inputs::PolicyInputs;
use dm_tree::frontend::{BodySyntax,BodySyntaxInput,BodySyntaxFailure,OriginalArchiveOwner};
use std::{io,sync::Arc};
pub use crate::{reactive_read_result::FrozenReadSet,reactive_reads_native::Failure};
#[derive(Clone,Copy,Debug,PartialEq,Eq,serde::Serialize)]pub enum Flavor{Closed,Targeted}
/// Opaque original-source-bound global result; fact equality is not authority.
pub struct GlobalResult{owner:OriginalArchiveOwner,value:NativeGlobals}
impl GlobalResult{
 pub fn matches(&self,inputs:&PolicyInputs)->bool{self.owner.matches(inputs.archive())}
 pub fn visit_storage(&self,mut visit:impl FnMut(&'static str,usize,usize,usize)){
  self.owner.visit_storage(&mut visit);self.value.visit_storage(|pointer,capacity|visit("global_rows",pointer,capacity,capacity));
 }
 pub fn retained_charge(&self)->Option<usize>{let mut sum=Some(std::mem::size_of::<Self>()+2*std::mem::size_of::<usize>());self.visit_storage(|_,_,_,capacity|sum=sum.and_then(|n|n.checked_add(capacity)));sum}
 /// Readonly data serialization for admitted output/oracle callers. It grants
 /// no source authority; callers must budget the destination and cancellation.
 pub fn serialize_facts<S:serde::Serializer>(&self,serializer:S)->Result<S::Ok,S::Error>{serde::Serialize::serialize(&self.value,serializer)}
}
type BodyBorrower<'a>=dyn Fn(&Arc<BodySyntaxInput>)->Result<Arc<BodySyntax>,BodySyntaxFailure>+'a;
/// All lifetimes end with this operation. Every demanded body enters the real
/// active query context callback before the archive's private issuance check.
fn source<'a>(raw:&'a CapturedRawPolicy,inputs:&'a PolicyInputs,budget:&'a Arc<Budget>,checkpoint:&'a dyn Fn()->io::Result<()>,body:&'a BodyBorrower<'a>)->Result<ReadSource<'a>,Failure>{
 checkpoint()?;Ok(ReadSource::capture(raw,inputs,budget)?.with_checkpoint(checkpoint).with_body_borrower(body))
}
pub fn globals(raw:&CapturedRawPolicy,inputs:&PolicyInputs,budget:&Arc<Budget>,checkpoint:&dyn Fn()->io::Result<()>,body:&BodyBorrower<'_>)->Result<GlobalResult,Failure>{
 let source=source(raw,inputs,budget,checkpoint,body)?;let value=NativeGlobals::build(&source,checkpoint)?;checkpoint()?;source.require()?;
 Ok(GlobalResult{owner:inputs.archive().original_owner_witness(),value})
}
/// A stack-only lazy loan from the SAME query graph. The factory checks the
/// returned value's original-source witness before any policy question.
pub trait GlobalProvider{fn with_globals(&self,consume:&mut dyn FnMut(&GlobalResult)->Result<bool,Failure>)->Result<bool,Failure>;}
impl<F> GlobalProvider for F where F:Fn(&mut dyn FnMut(&GlobalResult)->Result<bool,Failure>)->Result<bool,Failure>{fn with_globals(&self,consume:&mut dyn FnMut(&GlobalResult)->Result<bool,Failure>)->Result<bool,Failure>{self(consume)}}
struct GlobalAdapter<'a,'s>{source:&'a ReadSource<'s>,provider:&'a dyn GlobalProvider}
impl reactive_reads_native::GlobalFacts for GlobalAdapter<'_,'_>{
 fn constant_after_init(&self,name:&str)->Result<bool,Failure>{self.question(&mut|result|{self.check(result)?;reactive_reads_native::GlobalFacts::constant_after_init(&result.value,name)})}
 fn field_constant_after_init(&self,name:&str)->Result<bool,Failure>{self.question(&mut|result|{self.check(result)?;reactive_reads_native::GlobalFacts::field_constant_after_init(&result.value,name)})}
 fn is_written_on(&self,source:&ReadSource<'_>,owner:&str,name:&str)->Result<bool,Failure>{self.question(&mut|result|{self.check(result)?;reactive_reads_native::GlobalFacts::is_written_on(&result.value,source,owner,name)})}
}
/// First actual callback error is retained locally; a malicious provider cannot
/// swallow IO, omit/repeat the real loan, or replace the checked answer.
fn checked_question(provider:&dyn GlobalProvider,action:&mut dyn FnMut(&GlobalResult)->Result<bool,Failure>)->Result<bool,Failure>{
 let mut answer=None;let mut first=None;let mut called=false;
 let returned=provider.with_globals(&mut|value|{
  if called{if first.is_none(){first=Some(Failure::Operational(io::Error::new(io::ErrorKind::InvalidInput,"global provider repeated original result callback")));}return Err(Failure::Operational(io::Error::other("global callback stopped")))}called=true;
  match action(value){Ok(actual)=>{answer=Some(actual);Ok(actual)},Err(actual)=>{first=Some(actual);Err(Failure::Operational(io::Error::other("global callback stopped")))}}
 });
 if let Some(actual)=first{return Err(actual)}let returned=returned?;
 match answer{Some(actual)if actual==returned=>Ok(actual),_=>Err(Failure::Operational(io::Error::new(io::ErrorKind::InvalidInput,"global provider omitted or replaced original checked answer")))}
}
impl GlobalAdapter<'_,'_>{
 fn question(&self,action:&mut dyn FnMut(&GlobalResult)->Result<bool,Failure>)->Result<bool,Failure>{checked_question(self.provider,action)}
 fn check(&self,result:&GlobalResult)->Result<(),Failure>{if !result.matches(self.source.inputs()){return Err(Failure::Operational(io::Error::new(io::ErrorKind::InvalidInput,"reactive globals belong to another original source owner tuple")))}self.source.checkpoint()?;Ok(())}}
pub struct ReadResult{owner:OriginalArchiveOwner,facts:FrozenReadSet}
impl ReadResult{
 pub fn matches(&self,inputs:&PolicyInputs)->bool{self.owner.matches(inputs.archive())}
 pub fn facts(&self)->&FrozenReadSet{&self.facts}
 pub fn visit_storage(&self,mut visit:impl FnMut(&'static str,usize,usize,usize)){self.owner.visit_storage(&mut visit);self.facts.visit_storage(visit);}
 pub fn retained_charge(&self)->Option<usize>{self.facts.retained_charge()?.checked_add(self.owner.fixed_retention_capacity()?)?.checked_add(std::mem::size_of::<OriginalArchiveOwner>())}
}
pub fn reads(raw:&CapturedRawPolicy,inputs:&PolicyInputs,budget:&Arc<Budget>,provider:&dyn GlobalProvider,receiver:&str,procedure:&str,context:Option<&str>,flavor:Flavor,checkpoint:&dyn Fn()->io::Result<()>,body:&BodyBorrower<'_>)->Result<ReadResult,Failure>{
 checkpoint()?;let source=source(raw,inputs,budget,checkpoint,body)?;let mut poll=||checkpoint();let facts=PolicyFacts::capture(&source,&mut poll)?;
 let globals=GlobalAdapter{source:&source,provider};
 let result=reactive_reads_native::original_request(&source,Directives{facts:&facts,globals:Some(&globals)},receiver,procedure,context,matches!(flavor,Flavor::Closed),&mut poll)?;
 let frozen=FrozenReadSet::freeze(result,budget,&mut poll)?;checkpoint()?;source.require()?;Ok(ReadResult{owner:inputs.archive().original_owner_witness(),facts:frozen})
}

#[cfg(test)]mod provider_contract_tests{use super::*;
 #[test]fn omitted_actual_global_result_cannot_mint_a_boolean_answer(){for value in [true,false]{let called=std::cell::Cell::new(false);let provider=|_:&mut dyn FnMut(&GlobalResult)->Result<bool,Failure>|Ok(value);let error=checked_question(&provider,&mut|_|{called.set(true);Ok(!value)}).unwrap_err();assert!(!called.get());assert!(matches!(error,Failure::Operational(ref e)if e.kind()==io::ErrorKind::InvalidInput));}}
}

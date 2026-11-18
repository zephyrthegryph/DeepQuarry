//! Explicit native read factory over the SAME captured raw and native owners.
//! No producer installation or source acquisition. Returned data has no AST.
use crate::{captured_generator_budget::Budget,captured_raw_policy::CapturedRawPolicy,reactive_original_source::ReadSource,reactive_policy_facts_native::PolicyFacts,reactive_reads_native::{self,Directives},reactive_global_facts_native::NativeGlobals};
use dm_analysis::policy_inputs::PolicyInputs;
use dm_tree::frontend::{BodySyntax,BodySyntaxInput,BodySyntaxFailure,OriginalArchiveOwner};
use std::{io,sync::Arc};
pub use crate::{reactive_read_result::FrozenReadSet,reactive_reads_native::Failure};
#[derive(Clone,Copy,Debug,PartialEq,Eq,serde::Serialize)]pub enum Flavor{Closed,Targeted,UtilityClosed,UtilityTargeted}
impl Flavor{pub(crate) fn is_utility(self)->bool{matches!(self,Self::UtilityClosed|Self::UtilityTargeted)}pub(crate) fn is_closed(self)->bool{matches!(self,Self::Closed|Self::UtilityClosed)}pub(crate) fn utility(self)->Self{if self.is_closed(){Self::UtilityClosed}else{Self::UtilityTargeted}}}
/// Opaque original-source-bound global result; fact equality is not authority.
pub struct GlobalResult{owner:OriginalArchiveOwner,value:NativeGlobals,utility:bool}
impl GlobalResult{
 pub fn matches(&self,inputs:&PolicyInputs)->bool{!self.utility&&self.owner.matches(inputs.archive())}
 pub fn matches_utility(&self,inputs:&PolicyInputs)->bool{self.utility&&self.owner.matches(inputs.archive())}
 pub fn utility_contract(&self)->bool{self.utility}
 fn matches_source(&self,source:&dyn crate::reactive_global_source::Source)->bool{self.utility==source.utility_body_contract()&&source.complete_inputs().is_some_and(|inputs|self.owner.matches(inputs.archive()))}
 pub fn visit_storage(&self,mut visit:impl FnMut(&'static str,usize,usize,usize)){
  self.owner.visit_storage(&mut visit);self.value.visit_storage(|pointer,capacity|visit("global_rows",pointer,capacity,capacity));
 }
 pub fn retained_charge(&self)->Option<usize>{let mut sum=Some(std::mem::size_of::<Self>()+2*std::mem::size_of::<usize>());self.visit_storage(|_,_,_,capacity|sum=sum.and_then(|n|n.checked_add(capacity)));sum}
 /// Readonly data serialization for admitted output/oracle callers. It grants
 /// no source authority; callers must budget the destination and cancellation.
 pub fn serialize_facts<S:serde::Serializer>(&self,serializer:S)->Result<S::Ok,S::Error>{serde::Serialize::serialize(&self.value,serializer)}
 /// Internal query cutoff stream includes all policy facts, not just the old
 /// public oracle schema. This is data only; source witness checks still apply.
 pub fn serialize_dependency_facts<S:serde::Serializer>(&self,serializer:S)->Result<S::Ok,S::Error>{self.value.serialize_dependencies(serializer)}
 pub(crate) fn outside_setters(&self)->&crate::write_policy::WriteRows{self.value.outside_setters()}
 pub(crate) fn outside_written_on(&self,source:&dyn crate::reactive_global_source::Source,owner:&str,name:&str)->Result<bool,Failure>{let _inputs=source.complete_inputs().ok_or("derived Globals require actual complete original source")?;if !self.matches_source(source){return Err("derived Globals original owner/utility contract differs".into())}reactive_reads_native::GlobalFacts::outside_written_on(&self.value,source,owner,name)}


}
type BodyBorrower<'a>=dyn Fn(&Arc<BodySyntaxInput>)->Result<Arc<BodySyntax>,BodySyntaxFailure>+'a;
#[derive(Clone,Copy)]enum BodyDemand<'a>{Strict(&'a BodyBorrower<'a>),Utility(&'a crate::reactive_original_source::UtilityBodyBorrower<'a>)}
impl<'a>BodyDemand<'a>{fn bind<'b>(self,source:ReadSource<'b>)->ReadSource<'b>where 'a:'b{match self{Self::Strict(body)=>source.with_body_borrower(body),Self::Utility(body)=>source.with_utility_body_borrower(body)}}}

/// All lifetimes end with this operation. Every demanded body enters the real
/// active query context callback before the archive's private issuance check.
fn source<'a>(raw:&'a CapturedRawPolicy,inputs:&'a PolicyInputs,budget:&'a Arc<Budget>,checkpoint:&'a dyn Fn()->io::Result<()>,body:&'a BodyBorrower<'a>)->Result<ReadSource<'a>,Failure>{
 checkpoint()?;Ok(ReadSource::capture(raw,inputs,budget)?.with_checkpoint(checkpoint).with_body_borrower(body))
}
pub fn globals(raw:&CapturedRawPolicy,inputs:&PolicyInputs,budget:&Arc<Budget>,checkpoint:&dyn Fn()->io::Result<()>,body:&BodyBorrower<'_>)->Result<GlobalResult,Failure>{
 let source=source(raw,inputs,budget,checkpoint,body)?;let value=NativeGlobals::build(&source,checkpoint)?;checkpoint()?;source.require()?;
 Ok(GlobalResult{owner:inputs.archive().original_owner_witness(),value,utility:false})
}
/// Native semantic-only Globals producer. The caller must authenticate current
/// evidence/config/mapping before cache access and lend the SAME active query
/// context body borrower. No raw marker coverage or producer selection follows.
pub fn globals_native(inputs:&PolicyInputs,root:&std::path::Path,budget:&Arc<Budget>,checkpoint:&dyn Fn()->io::Result<()>,body:&BodyBorrower<'_>)->Result<GlobalResult,Failure>{
 checkpoint()?;let source=ReadSource::native(inputs,root,budget)?.with_checkpoint(checkpoint).with_body_borrower(body);
 let value=NativeGlobals::build(&source,checkpoint)?;checkpoint()?;source.require()?;
 Ok(GlobalResult{owner:inputs.archive().original_owner_witness(),value,utility:false})
}
/// A stack-only lazy loan from the SAME query graph. The factory checks the
/// returned value's original-source witness before any policy question.
pub trait GlobalProvider{fn with_globals(&self,consume:&mut dyn FnMut(&GlobalResult)->Result<bool,Failure>)->Result<bool,Failure>;}
impl<F> GlobalProvider for F where F:Fn(&mut dyn FnMut(&GlobalResult)->Result<bool,Failure>)->Result<bool,Failure>{fn with_globals(&self,consume:&mut dyn FnMut(&GlobalResult)->Result<bool,Failure>)->Result<bool,Failure>{self(consume)}}
struct GlobalAdapter<'a,'s>{source:&'a ReadSource<'s>,provider:&'a dyn GlobalProvider}
impl reactive_reads_native::GlobalFacts for GlobalAdapter<'_,'_>{
 fn outside_written_on(&self,source:&dyn crate::reactive_global_source::Source,owner:&str,name:&str)->Result<bool,Failure>{let _inputs=source.complete_inputs().ok_or_else(||Failure::Operational(io::Error::new(io::ErrorKind::InvalidInput,"ordinary global provider requires complete original source")))?;self.question(&mut|result|{self.check(result)?;if !result.matches_source(source){return Err(Failure::Operational(io::Error::new(io::ErrorKind::InvalidInput,"global provider differs from actual question source/utility contract")))}reactive_reads_native::GlobalFacts::outside_written_on(&result.value,source,owner,name)})}

 fn constant_after_init(&self,name:&str)->Result<bool,Failure>{self.question(&mut|result|{self.check(result)?;reactive_reads_native::GlobalFacts::constant_after_init(&result.value,name)})}
 fn field_constant_after_init(&self,name:&str)->Result<bool,Failure>{self.question(&mut|result|{self.check(result)?;reactive_reads_native::GlobalFacts::field_constant_after_init(&result.value,name)})}
 fn is_written_on(&self,source:&dyn crate::reactive_global_source::Source,owner:&str,name:&str)->Result<bool,Failure>{let _inputs=source.complete_inputs().ok_or_else(||Failure::Operational(io::Error::new(io::ErrorKind::InvalidInput,"ordinary global provider requires its actual complete original source")))?;self.question(&mut|result|{self.check(result)?;if !result.matches_source(source){return Err(Failure::Operational(io::Error::new(io::ErrorKind::InvalidInput,"global provider differs from actual question source/utility contract")))}reactive_reads_native::GlobalFacts::is_written_on(&result.value,source,owner,name)})}
}
/// One lazy current-source question from the existing query graph. A provider
/// cannot mint an answer without exactly one authenticated borrowed result.
/// Actual callback/provider IO stays operational even after a semantic refusal.
pub fn with_global_question(provider:&dyn GlobalProvider,inputs:&PolicyInputs,checkpoint:&dyn Fn()->io::Result<()>,action:&mut dyn FnMut(&GlobalResult)->Result<bool,Failure>)->Result<bool,Failure>{with_global_question_contract(provider,inputs,false,checkpoint,action)}
fn with_global_question_contract(provider:&dyn GlobalProvider,inputs:&PolicyInputs,utility:bool,checkpoint:&dyn Fn()->io::Result<()>,action:&mut dyn FnMut(&GlobalResult)->Result<bool,Failure>)->Result<bool,Failure>{
 checkpoint()?;let mut answer=None;let mut first=None;let mut called=false;
 let returned=provider.with_globals(&mut|value|{
  let attempt=(||{checkpoint()?;if called{return Err(Failure::Operational(io::Error::new(io::ErrorKind::InvalidInput,"global provider repeated original result callback")))}called=true;
   if !(if utility{value.matches_utility(inputs)}else{value.matches(inputs)}){return Err(Failure::Operational(io::Error::new(io::ErrorKind::InvalidInput,"global provider supplied another original source owner/utility contract tuple")))}
   let actual=action(value)?;answer=Some(actual);checkpoint()?;Ok(actual)})();
  match attempt{Ok(actual)=>Ok(actual),Err(actual)=>{if first.is_none()||(!matches!(&first,Some(Failure::Operational(_)))&&matches!(&actual,Failure::Operational(_))){first=Some(actual)}Err(Failure::Operational(io::Error::other(ReadCallbackStopped)))}}
 });
 if matches!(&first,Some(Failure::Operational(_))){return Err(first.take().unwrap())}
 let returned=match returned{Err(Failure::Operational(actual))if !read_callback_proxy(&actual)=>return Err(Failure::Operational(actual)),result=>result};
 checkpoint()?;if let Some(actual)=first{return Err(actual)}let returned=returned?;
 match answer{Some(actual)if actual==returned=>Ok(actual),_=>Err(Failure::Operational(io::Error::new(io::ErrorKind::InvalidInput,"global provider omitted or replaced original checked answer")))}
}
impl GlobalAdapter<'_,'_>{
 fn question(&self,action:&mut dyn FnMut(&GlobalResult)->Result<bool,Failure>)->Result<bool,Failure>{budgeted_action(self.source.budget(),||with_global_question_contract(self.provider,self.source.inputs(),self.source.utility_body_borrower().is_some(),&||self.source.checkpoint(),&mut|result|budgeted_action(self.source.budget(),||action(result))))}
 fn check(&self,result:&GlobalResult)->Result<(),Failure>{if !result.matches_source(self.source){return Err(Failure::Operational(io::Error::new(io::ErrorKind::InvalidInput,"reactive globals belong to another original source owner tuple")))}self.source.checkpoint()?;Ok(())}}


// Classify SAME-budget denial inside the child callback, before a provider can
// perform its final cancellation poll. A returned actual IO remains first.
fn budgeted_action<T>(budget:&Budget,action:impl FnOnce()->Result<T,Failure>)->Result<T,Failure>{let require=||budget.require().map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)));require()?;let pending=action();if matches!(&pending,Err(Failure::Operational(_))){return pending}require()?;pending}
/// Exact query subject, privately minted by the successful original factory.
/// Fact/source equality never substitutes a different requested root.
struct ReadIdentity{receiver:String,procedure:String,context:Option<String>,flavor:Flavor}
impl ReadIdentity{
 fn capture(budget:&Budget,receiver:&str,procedure:&str,context:Option<&str>,flavor:Flavor)->Result<Self,Failure>{
  let bytes=receiver.len().checked_add(procedure.len()).and_then(|n|n.checked_add(context.map_or(0,str::len))).and_then(|n|n.checked_add(3*64)).ok_or_else(||{budget.deny();Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"reactive exact request overflow"))})?;budget.charge(bytes).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;
  Ok(Self{receiver:receiver.to_owned(),procedure:procedure.to_owned(),context:context.map(str::to_owned),flavor})
 }
 fn matches(&self,receiver:&str,procedure:&str,context:Option<&str>,flavor:Flavor)->bool{self.receiver==receiver&&self.procedure==procedure&&self.context.as_deref()==context&&self.flavor==flavor}
 fn visit_storage(&self,mut visit:impl FnMut(&'static str,usize,usize,usize)){for text in [&self.receiver,&self.procedure].into_iter().chain(self.context.iter()){visit("read_request",text.as_ptr() as usize,text.len(),text.capacity());}}
}
pub struct ReadResult{owner:OriginalArchiveOwner,request:ReadIdentity,facts:FrozenReadSet}
impl ReadResult{
 pub fn matches(&self,inputs:&PolicyInputs)->bool{self.owner.matches(inputs.archive())}
 pub fn matches_request(&self,receiver:&str,procedure:&str,context:Option<&str>,flavor:Flavor)->bool{self.request.matches(receiver,procedure,context,flavor)}
 pub fn facts(&self)->&FrozenReadSet{&self.facts}
 pub fn visit_storage(&self,mut visit:impl FnMut(&'static str,usize,usize,usize)){self.owner.visit_storage(&mut visit);self.request.visit_storage(&mut visit);self.facts.visit_storage(visit);}
 pub fn retained_charge(&self)->Option<usize>{let mut sum=Some(std::mem::size_of::<Self>()+2*std::mem::size_of::<usize>());self.visit_storage(|_,_,_,capacity|sum=sum.and_then(|n|n.checked_add(capacity)));sum}
}
pub fn reads(raw:&CapturedRawPolicy,inputs:&PolicyInputs,budget:&Arc<Budget>,provider:&dyn GlobalProvider,receiver:&str,procedure:&str,context:Option<&str>,flavor:Flavor,checkpoint:&dyn Fn()->io::Result<()>,body:&BodyBorrower<'_>)->Result<ReadResult,Failure>{
 checkpoint()?;let source=source(raw,inputs,budget,checkpoint,body)?;let request=ReadIdentity::capture(budget,receiver,procedure,context,flavor)?;let mut poll=||checkpoint();let facts=PolicyFacts::capture(&source,&mut poll)?;
 let frozen=freeze_original_read(&source,&facts,provider,receiver,procedure,context,flavor,budget,checkpoint)?;checkpoint()?;source.require()?;Ok(ReadResult{owner:inputs.archive().original_owner_witness(),request,facts:frozen})
}


/// A borrowed child from the SAME active query graph. Current evidence/config
/// admission belongs to the endpoint, and the result must prove this exact root.
pub trait ReadProvider{fn with_read(&self,receiver:&str,procedure:&str,context:Option<&str>,flavor:Flavor,consume:&mut dyn FnMut(&ReadResult)->Result<(),Failure>)->Result<(),Failure>;}
impl<F> ReadProvider for F where F:Fn(&str,&str,Option<&str>,Flavor,&mut dyn FnMut(&ReadResult)->Result<(),Failure>)->Result<(),Failure>{fn with_read(&self,receiver:&str,procedure:&str,context:Option<&str>,flavor:Flavor,consume:&mut dyn FnMut(&ReadResult)->Result<(),Failure>)->Result<(),Failure>{self(receiver,procedure,context,flavor,consume)}}

#[derive(Debug)]struct ReadCallbackStopped;
impl std::fmt::Display for ReadCallbackStopped{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.write_str("read callback stopped")}}
impl std::error::Error for ReadCallbackStopped{}
fn read_callback_proxy(error:&io::Error)->bool{let mut cause=error.get_ref().map(|e|e as &(dyn std::error::Error+'static));while let Some(error)=cause{if error.is::<ReadCallbackStopped>(){return true}cause=error.downcast_ref::<io::Error>().and_then(io::Error::get_ref).map(|payload|payload as &(dyn std::error::Error+'static)).or_else(||error.source());}false}
/// Neutral page data is never exposed as a verified finite ReadResult.
/// Host full-result wrappers must additionally check completed workspace proof.
pub struct UnsealedReadData{owner:OriginalArchiveOwner,request:ReadIdentity,facts:FrozenReadSet,utility_procedure:Option<Box<UtilityProcedure>>}
impl UnsealedReadData{
 pub fn matches_compiled(&self,inputs:&PolicyInputs)->bool{self.owner.matches(inputs.archive())}
 pub fn matches_request(&self,receiver:&str,procedure:&str,context:Option<&str>,flavor:Flavor)->bool{self.request.matches(receiver,procedure,context,flavor)}
 pub fn facts(&self)->&FrozenReadSet{&self.facts}
 pub fn utility_procedure(&self)->Option<&UtilityProcedure>{self.utility_procedure.as_deref()}
 pub fn serialize_data<S:serde::Serializer>(&self,serializer:S)->Result<S::Ok,S::Error>{use serde::Serialize as _;match &self.utility_procedure{None=>self.facts.serialize(serializer),Some(actual)=>(&self.facts,actual).serialize(serializer)}}
 pub fn retained_charge(&self)->Option<usize>{let mut bytes=Some(std::mem::size_of::<Self>()+2*std::mem::size_of::<usize>());self.visit_storage(|_,_,_,capacity|bytes=bytes.and_then(|n|n.checked_add(capacity)));bytes}
 pub fn visit_storage(&self,mut visit:impl FnMut(&'static str,usize,usize,usize)){self.owner.visit_storage(&mut visit);self.request.visit_storage(&mut visit);self.facts.visit_storage(&mut visit);if let Some(actual)=&self.utility_procedure{visit("utility_procedure_owner",actual.as_ref() as *const _ as usize,std::mem::size_of::<UtilityProcedure>(),std::mem::size_of::<UtilityProcedure>());actual.visit_storage(&mut visit);}}
}
pub trait RawPolicyReadProvider{fn with_read_data(&self,receiver:&str,procedure:&str,context:Option<&str>,flavor:Flavor,consume:&mut dyn FnMut(&UnsealedReadData)->Result<(),Failure>)->Result<(),Failure>;}
impl<F> RawPolicyReadProvider for F where F:Fn(&str,&str,Option<&str>,Flavor,&mut dyn FnMut(&UnsealedReadData)->Result<(),Failure>)->Result<(),Failure>{fn with_read_data(&self,receiver:&str,procedure:&str,context:Option<&str>,flavor:Flavor,consume:&mut dyn FnMut(&UnsealedReadData)->Result<(),Failure>)->Result<(),Failure>{self(receiver,procedure,context,flavor,consume)}}
trait QuestionValue{type Facts;fn question_matches(&self,inputs:&PolicyInputs,receiver:&str,procedure:&str,context:Option<&str>,flavor:Flavor)->bool;fn question_facts(&self)->&Self::Facts;}
impl QuestionValue for ReadResult{type Facts=FrozenReadSet;fn question_matches(&self,inputs:&PolicyInputs,r:&str,p:&str,c:Option<&str>,f:Flavor)->bool{self.matches(inputs)&&self.matches_request(r,p,c,f)}fn question_facts(&self)->&FrozenReadSet{self.facts()}}
impl QuestionValue for UnsealedReadData{type Facts=FrozenReadSet;fn question_matches(&self,inputs:&PolicyInputs,r:&str,p:&str,c:Option<&str>,f:Flavor)->bool{self.matches_compiled(inputs)&&self.matches_request(r,p,c,f)}fn question_facts(&self)->&FrozenReadSet{self.facts()}}
pub fn with_read_facts<T>(provider:&dyn ReadProvider,inputs:&PolicyInputs,receiver:&str,procedure:&str,context:Option<&str>,flavor:Flavor,checkpoint:&dyn Fn()->io::Result<()>,consume:impl FnOnce(&FrozenReadSet)->Result<T,Failure>)->Result<T,Failure>{with_read_question(|visit|provider.with_read(receiver,procedure,context,flavor,visit),inputs,receiver,procedure,context,flavor,checkpoint,consume)}
pub fn with_raw_read_facts<T>(provider:&dyn RawPolicyReadProvider,inputs:&PolicyInputs,receiver:&str,procedure:&str,context:Option<&str>,flavor:Flavor,checkpoint:&dyn Fn()->io::Result<()>,consume:impl FnOnce(&FrozenReadSet)->Result<T,Failure>)->Result<T,Failure>{with_read_question(|visit|provider.with_read_data(receiver,procedure,context,flavor,visit),inputs,receiver,procedure,context,flavor,checkpoint,consume)}
fn with_read_question<T,V:QuestionValue>(obtain:impl FnOnce(&mut dyn FnMut(&V)->Result<(),Failure>)->Result<(),Failure>,inputs:&PolicyInputs,receiver:&str,procedure:&str,context:Option<&str>,flavor:Flavor,checkpoint:&dyn Fn()->io::Result<()>,consume:impl FnOnce(&V::Facts)->Result<T,Failure>)->Result<T,Failure>{
 checkpoint()?;let mut action=Some(consume);let mut answer=None;let mut first=None;
 let returned=obtain(&mut|value|{
  let attempt=(||{checkpoint()?;let Some(consume)=action.take()else{return Err(Failure::Operational(io::Error::new(io::ErrorKind::InvalidInput,"read provider repeated actual result callback")))};
   if !value.question_matches(inputs,receiver,procedure,context,flavor){return Err(Failure::Operational(io::Error::new(io::ErrorKind::InvalidInput,"read provider supplied a foreign source or requested root")))}
   answer=Some(consume(value.question_facts())?);checkpoint()?;Ok(())})();
  if let Err(actual)=attempt{if first.is_none()||(!matches!(&first,Some(Failure::Operational(_)))&&matches!(&actual,Failure::Operational(_))){first=Some(actual)}return Err(Failure::Operational(io::Error::other(ReadCallbackStopped)))}Ok(())
 });
 if matches!(&first,Some(Failure::Operational(_))){return Err(first.take().unwrap())}
 // Preserve genuine provider IO ahead of later checkpoint proxies. Our own
 // typed stop marker carries no operational fact and is unwrapped below.
 let returned=match returned{Err(Failure::Operational(actual))if !read_callback_proxy(&actual)=>return Err(Failure::Operational(actual)),result=>result};
 checkpoint()?;
 if let Some(actual)=first{return Err(actual)}returned?;
 answer.ok_or_else(||Failure::Operational(io::Error::new(io::ErrorKind::InvalidInput,"read provider omitted actual result callback")))
}

/// Unique dependency-gap judgement over an actual completed original read
/// result. Source owner equality alone is not a current-frame permission: the
/// endpoint must keep its existing evidence/config/gate checks around this loan.
pub fn untracked(raw:&CapturedRawPolicy,inputs:&PolicyInputs,budget:&Arc<Budget>,provider:&dyn GlobalProvider,read:&ReadResult,output:bool,checkpoint:&dyn Fn()->io::Result<()>,body:&BodyBorrower<'_>)->Result<Vec<crate::reactive_facts::Untracked>,Failure>{
 checkpoint()?;if !read.matches(inputs){return Err(Failure::Operational(io::Error::new(io::ErrorKind::InvalidInput,"dependency read belongs to another original source tuple")))}
 let source=source(raw,inputs,budget,checkpoint,body)?;let mut poll=||checkpoint();let facts=PolicyFacts::capture(&source,&mut poll)?;
 let globals=GlobalAdapter{source:&source,provider};let result=crate::reactive_dependency_native::untracked(&source,&facts,&globals,read.facts(),output,checkpoint)?;
 checkpoint()?;source.require()?;Ok(result)
}

/// Completed dependency data bound to the actual original source-owner tuple.
/// The retained payload contains ordered result rows only, never syntax/source.
/// Endpoint evidence/config/complete raw-roster admission remains mandatory.
pub struct DependencyResult{owner:OriginalArchiveOwner,facts:crate::reactive_dependency_result::FrozenDeps}
impl DependencyResult{
 /// Admitted unique deps emitter over the completed original result. No file
 /// writing or default producer selection is granted by this returned data.
 pub fn render_deps(&self,inputs:&PolicyInputs,budget:&Arc<Budget>,checkpoint:&dyn Fn()->io::Result<()>)->Result<crate::sparse_slots_policy::Output,Failure>{
  checkpoint()?;if !self.matches(inputs){return Err(Failure::Operational(io::Error::new(io::ErrorKind::InvalidInput,"dependency emitter source owner differs")))}
  crate::deps_policy::generate_view_admitted(crate::reactive_dependency_view::Analysis::Frozen(&self.facts),budget,checkpoint).map_err(Failure::Operational)
 }
 pub fn matches(&self,inputs:&PolicyInputs)->bool{self.owner.matches(inputs.archive())}
 pub fn serialize_facts<S:serde::Serializer>(&self,serializer:S)->Result<S::Ok,S::Error>{serde::Serialize::serialize(&self.facts,serializer)}
 pub fn visit_storage(&self,mut visit:impl FnMut(&'static str,usize,usize,usize)){self.owner.visit_storage(&mut visit);self.facts.visit_storage(visit)}
 pub fn retained_charge(&self)->Option<usize>{let mut sum=Some(std::mem::size_of::<Self>()+2*std::mem::size_of::<usize>());self.visit_storage(|_,_,_,capacity|sum=sum.and_then(|n|n.checked_add(capacity)));sum}
}
// Called only by the unique successful aggregate fold inside the same source
// operation. The enclosing scratch guard must remain live until parent-retained
// capacity is charged, and release no escaping buffers on failure.
fn finish_dependencies(source:&ReadSource<'_>,input:crate::reactive_facts::DepsAnalysis,budget:&Arc<Budget>,checkpoint:&dyn Fn()->io::Result<()>)->Result<DependencyResult,Failure>{
 checkpoint()?;let facts=crate::reactive_dependency_result::FrozenDeps::freeze(input,budget,checkpoint)?;checkpoint()?;source.require()?;
 Ok(DependencyResult{owner:source.inputs().archive().original_owner_witness(),facts})
}

/// Explicit finite-capture aggregate factory. All facts/providers use this SAME
/// original tuple; this is not whole-workspace/default generator activation.
pub fn dependencies(raw:&CapturedRawPolicy,inputs:&PolicyInputs,budget:&Arc<Budget>,globals_provider:&dyn GlobalProvider,read_provider:&dyn ReadProvider,checkpoint:&dyn Fn()->io::Result<()>,body:&BodyBorrower<'_>)->Result<DependencyResult,Failure>{
 checkpoint()?;let source=source(raw,inputs,budget,checkpoint,body)?;
 let scratch=Budget::scoped_temporaries(budget).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;
 let produced:Result<DependencyResult,Failure>=source.with_budget(&scratch,|work|{
  aggregate_from_source(&source,work,&scratch,globals_provider,&crate::reactive_dependency_native::ReadQuestions::Captured(read_provider),checkpoint,None)
 });
 let funded=match produced{Ok(value)=>match value.retained_charge().ok_or_else(||{budget.deny();io::Error::new(io::ErrorKind::OutOfMemory,"dependency retained capacity overflow")}).and_then(|bytes|budget.charge(bytes).map_err(|message|io::Error::new(io::ErrorKind::OutOfMemory,message))){Ok(())=>Ok(value),Err(actual)=>{drop(value);Err(Failure::Operational(actual))}},Err(actual)=>Err(actual)};
 // Moved buffers now have parent retention funding BEFORE the temporary
 // reservation can be credited. All other fold/metadata/source loans have
 // physically dropped when with_budget returned.
 if funded.is_err(){scratch.keep_failed_scratch()}drop(scratch);
 if matches!(&funded,Err(Failure::Operational(_))){return funded}checkpoint()?;
 if budget.denied(){return Err(Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"dependency aggregate admission refused")))}source.require()?;funded
}

impl DependencyResult{
 /// Finite original-source AutoTracked data. The caller must authenticate the
 /// fixed old lint_scopes configuration before selecting any artifact role.
 pub fn render_auto_tracked(&self,raw:&crate::captured_raw_policy::CapturedRawPolicy,inputs:&PolicyInputs,configuration_path:&std::path::Path,budget:&Arc<Budget>,checkpoint:&dyn Fn()->io::Result<()>)->Result<crate::sparse_slots_policy::Output,Failure>{
  checkpoint()?;if !self.matches(inputs){return Err(Failure::Operational(io::Error::new(io::ErrorKind::InvalidInput,"AutoTracked dependency source owner differs")))}raw.validate_current_raw_roster(inputs)?;
  let expected=raw.tree.root.join("tools/ci/lint_scopes.toml");if dm_preprocess::regions::canonical_path(configuration_path)!=dm_preprocess::regions::canonical_path(&expected){return Err("AutoTracked requires the original fixed lint_scopes configuration".into())}
  let scratch=Budget::scoped_temporaries(budget).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;
  let produced=(||{
   let source=ReadSource::capture(raw,inputs,&scratch)?.with_checkpoint(checkpoint);let scope=raw.scopes.borrowed_for_lint("auto_tracked","");let list=|name:&str|scope.map_or(&[][..],|scope|scope.list(name));
   let excludes=[list("exclude"),list("exclude_fixtures"),list("exclude_heat"),list("exclude_memo")];let includes=list("include");
   let set=auto_decisions(&source,&self.facts,includes,&excludes,checkpoint)?;
   struct TestControl<'a>{budget:&'a Budget,poll:&'a dyn Fn()->io::Result<()>}
   impl crate::key_policy_control::Control for TestControl<'_>{type Error=Failure;const CHECKED:bool=true;fn checkpoint(&mut self)->Result<(),Failure>{(self.poll)()?;self.budget.require().map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))}fn reserve(&mut self,bytes:usize)->Result<(),Failure>{self.budget.charge(bytes).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))}fn overflow(&mut self)->Failure{self.budget.deny();Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"AutoTracked test scope capacity overflow"))}fn allocation_failed(&mut self)->Failure{self.overflow()}}
   let mut tests=crate::generator_test_scope::TestTypeCollector::default();let mut control=TestControl{budget:&scratch,poll:checkpoint};for file in &raw.tree.files{tests.observe(&file.rel,file.text(),&mut control)?;}let tests=tests.finish();
   crate::auto_tracking_emitter::generate_admitted(&set,&tests,budget,checkpoint).map_err(Failure::Operational)
  })();if produced.is_err(){scratch.keep_failed_scratch()}drop(scratch);if matches!(&produced,Err(Failure::Operational(_))){return produced}checkpoint()?;budget.require().map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;produced
 }
}

fn freeze_original_read(source:&ReadSource<'_>,facts:&PolicyFacts,provider:&dyn GlobalProvider,receiver:&str,procedure:&str,context:Option<&str>,flavor:Flavor,budget:&Arc<Budget>,checkpoint:&dyn Fn()->io::Result<()>)->Result<FrozenReadSet,Failure>{
 let mut poll=||checkpoint();let globals=GlobalAdapter{source,provider};let result=reactive_reads_native::original_request(source,Directives{facts,globals:Some(&globals)},receiver,procedure,context,flavor.is_closed(),&mut poll)?;let frozen=FrozenReadSet::freeze(result,budget,&mut poll)?;checkpoint()?;source.require()?;Ok(frozen)
}
/// Unsealed full-page data production. The provider's bool is not coverage
/// authority. Actual host exhaustion/WorkspaceCodeWitness must be checked
/// before a full-role query may deliver this data, including every warm loan.
pub fn read_data_from_pages(inputs:&PolicyInputs,root:&std::path::Path,pages:&dyn crate::reactive_raw_policy_pages::RawPolicyPages,order:&std::collections::HashMap<String,usize>,budget:&Arc<Budget>,provider:&dyn GlobalProvider,receiver:&str,procedure:&str,context:Option<&str>,flavor:Flavor,checkpoint:&dyn Fn()->io::Result<()>,body:&BodyBorrower<'_>)->Result<UnsealedReadData,Failure>{read_data_from_pages_inner(inputs,root,pages,order,budget,provider,receiver,procedure,context,flavor,checkpoint,BodyDemand::Strict(body),None)}
fn read_data_from_pages_inner(inputs:&PolicyInputs,root:&std::path::Path,pages:&dyn crate::reactive_raw_policy_pages::RawPolicyPages,order:&std::collections::HashMap<String,usize>,budget:&Arc<Budget>,provider:&dyn GlobalProvider,receiver:&str,procedure:&str,context:Option<&str>,flavor:Flavor,checkpoint:&dyn Fn()->io::Result<()>,body:BodyDemand<'_>,policy:Option<&PolicyFacts>)->Result<UnsealedReadData,Failure>{
 checkpoint()?;let produced=(||{
  let scratch=Budget::scoped_temporaries(budget).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;
  let value=(||{let source=body.bind(ReadSource::native(inputs,root,&scratch)?.with_raw_policy_pages(pages,order).with_checkpoint(checkpoint));let request=ReadIdentity::capture(&scratch,receiver,procedure,context,flavor)?;let mut poll=||checkpoint();let captured=if policy.is_none(){Some(PolicyFacts::capture(&source,&mut poll)?)}else{None};let facts=policy.or(captured.as_ref()).expect("actual captured or supplied policy facts");let frozen=freeze_original_read(&source,facts,provider,receiver,procedure,context,flavor,&scratch,checkpoint)?;let utility_procedure=match body{BodyDemand::Strict(_)=>None,BodyDemand::Utility(body)=>{scratch.charge(std::mem::size_of::<UtilityProcedure>()).map_err(|m|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,m)))?;Some(Box::new(UtilityProcedure::capture(inputs,root,&scratch,checkpoint,body,receiver,procedure)?))}};Ok::<_,Failure>(UnsealedReadData{owner:inputs.archive().original_owner_witness(),request,facts:frozen,utility_procedure})})();
  // Source/facts/interpreter containers above are physically gone. The moved
  // immutable payload remains funded while the conservative scratch credit is
  // still live; only then may the scratch Arc retire. No root-by-root facts
  // reservation accumulates for discarded policy/interpreter containers.
  let funded=match value{Ok(value)=>match value.retained_charge().ok_or_else(||{budget.deny();io::Error::new(io::ErrorKind::OutOfMemory,"raw read retained capacity overflow")}).and_then(|bytes|budget.charge(bytes).map_err(|message|io::Error::new(io::ErrorKind::OutOfMemory,message))){Ok(())=>Ok(value),Err(actual)=>{drop(value);Err(Failure::Operational(actual))}},Err(actual)=>Err(actual)};
  if funded.is_err(){scratch.keep_failed_scratch()}drop(scratch);funded
 })();finish_page_data(produced,budget,checkpoint)
}

fn aggregate_from_source(source:&ReadSource<'_>,work:&ReadSource<'_>,budget:&Arc<Budget>,globals_provider:&dyn GlobalProvider,questions:&crate::reactive_dependency_native::ReadQuestions<'_>,checkpoint:&dyn Fn()->io::Result<()>,policy:Option<&UnsealedPolicyFacts>)->Result<DependencyResult,Failure>{
  let mut poll=||checkpoint();let captured=if policy.is_none(){Some(PolicyFacts::capture(work,&mut poll)?)}else{None};let facts=policy.map(|data|&data.facts).or(captured.as_ref()).expect("actual captured or supplied aggregate policy facts");
  // Auto's typed collector owns its real per-body scratch scopes. It borrows
  // the SAME root-budget source (not this temporary child budget), so no nested
  // scratch scope or alternate source/control domain is invented.
  let auto=crate::auto_tracking_native::NativeCandidates::capture(source,facts,globals_provider)?;
  let owned=work.dependency_marker_rows()?;let count=owned.markers.len();
  let reservation=count.checked_mul(std::mem::size_of::<crate::declare_policy::Marker<'_>>()).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(64)).ok_or_else(||{budget.deny();Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"dependency marker projection overflow"))})?;
  budget.charge(reservation).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;
  let mut markers=Vec::new();markers.try_reserve_exact(count).map_err(|actual|{budget.deny();Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,actual))})?;
  if markers.capacity().checked_mul(std::mem::size_of::<crate::declare_policy::Marker<'_>>()).is_none_or(|n|n>reservation){budget.deny();return Err(Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"dependency marker allocator exceeds admitted projection")))}
  for row in &owned.markers{checkpoint()?;markers.push(crate::declare_policy::Marker{name:&row.name,rel:&row.rel,line:row.line,body:&row.body,args:&row.args,body_offset:row.body_offset,line_starts:row.line_starts.as_slice()});}
  let defines=match policy{Some(data)=>{let mut names=std::collections::BTreeSet::new();for name in data.defines(){checkpoint()?;work.reserve(name.len().checked_mul(4).and_then(|n|n.checked_add(320)))?;names.insert(name.clone());}names},None=>work.dependency_defines()?};let globals=GlobalAdapter{source:work,provider:globals_provider};
  let folded=crate::reactive_dependency_native::analyze_questions(work,facts,&globals,questions,&markers,&defines,&auto,checkpoint)?;
  finish_dependencies(work,folded,budget,checkpoint)
}

/// Data only. There is intentionally no conversion/getter to DependencyResult;
/// generic callbacks cannot mint its finite-capture or any full-source role.
pub struct UnsealedDependencyData{value:DependencyResult}
impl UnsealedDependencyData{
 pub fn matches_compiled(&self,inputs:&PolicyInputs)->bool{self.value.matches(inputs)}
 pub fn retained_charge(&self)->Option<usize>{self.value.retained_charge()}
 pub fn visit_storage(&self,visit:impl FnMut(&'static str,usize,usize,usize)){self.value.visit_storage(visit)}
 pub fn serialize_facts<S:serde::Serializer>(&self,serializer:S)->Result<S::Ok,S::Error>{self.value.serialize_facts(serializer)}
 pub fn render_deps_data(&self,inputs:&PolicyInputs,budget:&Arc<Budget>,checkpoint:&dyn Fn()->io::Result<()>)->Result<crate::sparse_slots_policy::Output,Failure>{self.value.render_deps(inputs,budget,checkpoint)}
}
/// Actual full-page fold, unsealed until the host consumes exhausted traversal
/// proof and binds the current workspace/discovery/config owner. The concrete
/// provider must use its ROOT reader budget for per-file scratch; policy fold
/// scratch is a sibling under that same root, never a nested source budget.
pub fn dependency_data_from_pages(inputs:&PolicyInputs,root:&std::path::Path,pages:&dyn crate::reactive_raw_policy_pages::RawPolicyPages,order:&std::collections::HashMap<String,usize>,budget:&Arc<Budget>,globals_provider:&dyn GlobalProvider,read_provider:&dyn RawPolicyReadProvider,checkpoint:&dyn Fn()->io::Result<()>,body:&BodyBorrower<'_>)->Result<UnsealedDependencyData,Failure>{dependency_data_from_pages_inner(inputs,root,pages,order,budget,globals_provider,read_provider,checkpoint,body,None,None)}
fn dependency_data_from_pages_inner(inputs:&PolicyInputs,root:&std::path::Path,pages:&dyn crate::reactive_raw_policy_pages::RawPolicyPages,order:&std::collections::HashMap<String,usize>,budget:&Arc<Budget>,globals_provider:&dyn GlobalProvider,read_provider:&dyn RawPolicyReadProvider,checkpoint:&dyn Fn()->io::Result<()>,body:&BodyBorrower<'_>,policy:Option<&UnsealedPolicyFacts>,selected_setter_files:Option<&dyn crate::captured_raw_file::SelectedTreeFiles>)->Result<UnsealedDependencyData,Failure>{
 checkpoint()?;
 let produced=(||{
  let source=ReadSource::native(inputs,root,budget)?.with_raw_policy_pages(pages,order) .with_checkpoint(checkpoint).with_body_borrower(body).with_selected_setter_files(selected_setter_files);
  let scratch=Budget::scoped_temporaries(budget).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;
  let value=source.with_budget(&scratch,|work|aggregate_from_source(&source,work,&scratch,globals_provider,&crate::reactive_dependency_native::ReadQuestions::RawData(read_provider),checkpoint,policy));
  let funded=match value{Ok(value)=>match value.retained_charge().ok_or_else(||{budget.deny();io::Error::new(io::ErrorKind::OutOfMemory,"raw dependency retained capacity overflow")}).and_then(|bytes|budget.charge(bytes).map_err(|message|io::Error::new(io::ErrorKind::OutOfMemory,message))){Ok(())=>Ok(UnsealedDependencyData{value}),Err(actual)=>{drop(value);Err(Failure::Operational(actual))}},Err(actual)=>Err(actual)};
  if funded.is_err(){scratch.keep_failed_scratch()}drop(scratch);funded
 })();
 finish_page_data(produced,budget,checkpoint)
}
fn finish_page_data<T>(produced:Result<T,Failure>,budget:&Budget,checkpoint:&dyn Fn()->io::Result<()>)->Result<T,Failure>{
 if matches!(&produced,Err(Failure::Operational(_))){return produced}checkpoint()?;budget.require().map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;produced
}

/// Original DME include ordering only; completion/source roles remain host-owned.
pub fn original_include_order(inputs:&PolicyInputs,root:&std::path::Path,budget:&Budget)->Result<std::collections::HashMap<String,usize>,Failure>{crate::captured_sparse_slots::original_order(root,inputs,budget).map_err(|message|if budget.denied(){Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message))}else{Failure::Unsupported(message)})}

/// Exact finite original read-table generation. Whole CLI source coverage is
/// a separate host receipt; this unchanged finite wrapper selects captured reads.
pub fn render_reads(raw:&CapturedRawPolicy,inputs:&PolicyInputs,budget:&Arc<Budget>,provider:&dyn ReadProvider,checkpoint:&dyn Fn()->io::Result<()>,body:&BodyBorrower<'_>)->Result<crate::sparse_slots_policy::Output,Failure>{
 checkpoint()?;let source=match source(raw,inputs,budget,checkpoint,body){Ok(source)=>source,Err(Failure::Operational(actual))=>return Err(Failure::Operational(actual)),Err(Failure::Unsupported(message))if budget.denied()=>return Err(Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message))),Err(actual)=>return Err(actual)};
 render_reads_scoped(&source,&crate::reactive_dependency_native::ReadQuestions::Captured(provider),|work|crate::reactive_reads_generator_native::test_types(work,raw),checkpoint)
}
fn render_reads_collect<T:std::borrow::Borrow<std::collections::BTreeSet<String>>>(work:&ReadSource<'_>,questions:&crate::reactive_dependency_native::ReadQuestions<'_>,make_tests:impl FnOnce(&ReadSource<'_>)->Result<T,Failure>,checkpoint:&dyn Fn()->io::Result<()>,policy:Option<&UnsealedPolicyFacts>)->Result<crate::sparse_slots_policy::Output,Failure>{let scratch=work.budget();

  let mut poll=||checkpoint();let captured=if policy.is_none(){Some(PolicyFacts::capture(work,&mut poll)?)}else{None};let facts=policy.map(|value|&value.facts).or(captured.as_ref()).expect("actual generator policy facts");let owned=work.dependency_marker_rows()?;let count=owned.markers.len();let reserve=count.checked_mul(std::mem::size_of::<crate::declare_policy::Marker<'_>>()).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(64)).ok_or_else(||{scratch.deny();Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"read generator marker projection overflow"))})?;scratch.charge(reserve).map_err(|actual|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,actual)))?;
  let mut markers=Vec::new();markers.try_reserve_exact(count).map_err(|actual|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,actual)))?;if markers.capacity().checked_mul(std::mem::size_of::<crate::declare_policy::Marker<'_>>()).is_none_or(|n|n>reserve){scratch.deny();return Err(Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"read generator marker capacity exceeds admission")))}for row in &owned.markers{checkpoint()?;markers.push(crate::declare_policy::Marker{name:&row.name,rel:&row.rel,line:row.line,body:&row.body,args:&row.args,body_offset:row.body_offset,line_starts:&row.line_starts});}
  let tests=make_tests(work)?;let tests:&std::collections::BTreeSet<String>=std::borrow::Borrow::borrow(&tests);
  let defines=match policy{Some(data)=>{let mut names=std::collections::BTreeSet::new();for name in data.defines(){checkpoint()?;work.reserve(name.len().checked_mul(4).and_then(|n|n.checked_add(320)))?;names.insert(name.clone());}names},None=>work.dependency_defines()?};let mut rendered=crate::reactive_reads_generator_native::generate_with_questions(work,facts,questions,&markers,&defines,tests)?;let mut output=crate::sparse_slots_policy::Output::default();output.body=std::mem::take(&mut rendered.body);output.diags=std::mem::take(&mut rendered.diags);Ok(output)
}
fn render_reads_scoped<T:std::borrow::Borrow<std::collections::BTreeSet<String>>>(source:&ReadSource<'_>,questions:&crate::reactive_dependency_native::ReadQuestions<'_>,make_tests:impl FnOnce(&ReadSource<'_>)->Result<T,Failure>,checkpoint:&dyn Fn()->io::Result<()>)->Result<crate::sparse_slots_policy::Output,Failure>{let budget=source.budget();let scratch=Budget::scoped_temporaries(budget).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;let result=source.with_budget(&scratch,|work|render_reads_collect(work,questions,make_tests,checkpoint,None));
let funded=fund_read_output(result,budget,scratch,checkpoint);if matches!(&funded,Err(Failure::Operational(_))){return funded}source.require()?;funded
}

/// Neutral owned renderer data from original raw-page loans. The supplied
/// test-type set is data; only the actual host's completed CODE and distinct
/// GeneratorCliTest witnesses may authorize a full-role Artifact/publication.
pub fn render_reads_data_from_pages(inputs:&PolicyInputs,root:&std::path::Path,pages:&dyn crate::reactive_raw_policy_pages::RawPolicyPages,order:&std::collections::HashMap<String,usize>,test_types:&std::collections::BTreeSet<String>,budget:&Arc<Budget>,provider:&dyn RawPolicyReadProvider,checkpoint:&dyn Fn()->io::Result<()>,body:&BodyBorrower<'_>)->Result<crate::sparse_slots_policy::Output,Failure>{checkpoint()?;let produced=(||{let source=ReadSource::native(inputs,root,budget)?.with_raw_policy_pages(pages,order).with_checkpoint(checkpoint).with_body_borrower(body);render_reads_scoped(&source,&crate::reactive_dependency_native::ReadQuestions::RawData(provider),|_|Ok(test_types),checkpoint)})();finish_page_data(produced,budget,checkpoint)}

/// Explicit finite original raw-derived rendering; source-free owned output
/// does not certify full-workspace or compiled parser/source roles.
pub fn render_derived_reads(raw:&CapturedRawPolicy,inputs:&PolicyInputs,budget:&Arc<Budget>,checkpoint:&dyn Fn()->io::Result<()>,body:&BodyBorrower<'_>)->Result<String,Failure>{checkpoint()?;let source=match source(raw,inputs,budget,checkpoint,body){Ok(source)=>source,Err(Failure::Operational(actual))=>return Err(Failure::Operational(actual)),Err(Failure::Unsupported(message))if budget.denied()=>return Err(Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message))),Err(actual)=>return Err(actual)};let result=(||{let tests=crate::reactive_reads_generator_native::test_types(&source,raw)?;crate::reactive_derived_generator_native::generate(&source,&tests)})();if matches!(&result,Err(Failure::Operational(_))){return result}checkpoint()?;if budget.denied(){return Err(Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"derived read aggregate admission refused")))}source.require()?;result}

/// Neutral raw-derived renderer data, sharing the exact finite collector. The
/// caller's test-type rows and provider do not themselves grant source coverage.
pub fn render_derived_data_from_pages(inputs:&PolicyInputs,root:&std::path::Path,pages:&dyn crate::reactive_raw_policy_pages::RawPolicyPages,order:&std::collections::HashMap<String,usize>,test_types:&std::collections::BTreeSet<String>,budget:&Arc<Budget>,checkpoint:&dyn Fn()->io::Result<()>,body:&BodyBorrower<'_>)->Result<String,Failure>{checkpoint()?;let produced=(||{let source=ReadSource::native(inputs,root,budget)?.with_raw_policy_pages(pages,order).with_checkpoint(checkpoint).with_body_borrower(body);crate::reactive_derived_generator_native::generate(&source,test_types)})();finish_page_data(produced,budget,checkpoint)}

impl GlobalResult{
 /// Only the fixed original-owner backing extended by this result. Canonical
 /// graph buffers are already funded by their actual producer allocations.
 pub fn owner_coordination_charge(&self)->Option<usize>{let mut bytes=Some(0usize);self.owner.visit_storage(|_,_,_,capacity|bytes=bytes.and_then(|n|n.checked_add(capacity)));bytes}
}

/// One temporary original-DME policy map. Buffers physically drop before the
/// SAME existing scratch reservation can retire; no source/result authority.
pub struct ScopedOriginalIncludeOrder{order:Option<std::collections::HashMap<String,usize>>,_scratch:Arc<Budget>}
impl std::ops::Deref for ScopedOriginalIncludeOrder{type Target=std::collections::HashMap<String,usize>;fn deref(&self)->&Self::Target{self.order.as_ref().expect("original include order owner")}}
impl Drop for ScopedOriginalIncludeOrder{fn drop(&mut self){drop(self.order.take());}}
pub fn scoped_original_include_order(inputs:&PolicyInputs,root:&std::path::Path,budget:&Arc<Budget>)->Result<ScopedOriginalIncludeOrder,Failure>{
 let scratch=Budget::scoped_temporaries(budget).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;let produced=original_include_order(inputs,root,&scratch);match produced{Ok(order)=>Ok(ScopedOriginalIncludeOrder{order:Some(order),_scratch:scratch}),Err(actual)=>{scratch.keep_failed_scratch();Err(actual)}}
}

/// Source-neutral unique policy dataset. Full-role reuse requires the host's
/// actual current input and completed raw-discovery witness, never this value alone.
pub struct UnsealedPolicyFacts{owner:OriginalArchiveOwner,facts:PolicyFacts,defines:Vec<String>}
impl UnsealedPolicyFacts{
 pub fn matches_compiled(&self,inputs:&PolicyInputs)->bool{self.owner.matches(inputs.archive())}
 pub fn tracked_names(&self)->impl Iterator<Item=&str>{self.facts.tracked_names()}
 pub fn defines(&self)->&[String]{&self.defines}
 pub fn visit_storage(&self,mut visit:impl FnMut(&'static str,usize,usize,usize)){self.owner.visit_storage(&mut visit);self.facts.visit_storage(|address,bytes|visit("reactive.policy_facts",address,bytes,bytes));if self.defines.capacity()!=0{visit("reactive.policy_defines",self.defines.as_ptr()as usize,self.defines.len()*std::mem::size_of::<String>(),self.defines.capacity()*std::mem::size_of::<String>());}for name in &self.defines{if name.capacity()!=0{visit("reactive.policy_define",name.as_ptr()as usize,name.len(),name.capacity())}}}
 pub fn retained_charge(&self)->Option<usize>{let mut bytes=Some(std::mem::size_of::<Self>());self.visit_storage(|_,_,_,capacity|bytes=bytes.and_then(|n|n.checked_add(capacity)));bytes}
 pub fn fingerprint(&self,poll:&dyn Fn()->io::Result<()>)->Result<u128,Failure>{let facts=self.facts.fingerprint(poll)?;let mut hash=blake3::Hasher::new();hash.update(b"source-policy-data-v1\0");hash.update(&facts.to_le_bytes());hash.update(&(self.defines.len()as u128).to_le_bytes());for name in &self.defines{poll()?;hash.update(&(name.len()as u128).to_le_bytes());hash.update(name.as_bytes());}poll()?;Ok(u128::from_le_bytes(hash.finalize().as_bytes()[..16].try_into().unwrap()))}
}
pub trait PolicyFactsProvider{fn with_policy_facts(&self,consume:&mut dyn FnMut(&UnsealedPolicyFacts)->Result<(),Failure>)->Result<(),Failure>;}
impl<F> PolicyFactsProvider for F where F:Fn(&mut dyn FnMut(&UnsealedPolicyFacts)->Result<(),Failure>)->Result<(),Failure>{fn with_policy_facts(&self,consume:&mut dyn FnMut(&UnsealedPolicyFacts)->Result<(),Failure>)->Result<(),Failure>{self(consume)}}
impl QuestionValue for UnsealedPolicyFacts{type Facts=Self;fn question_matches(&self,inputs:&PolicyInputs,receiver:&str,procedure:&str,context:Option<&str>,flavor:Flavor)->bool{receiver=="<policy>"&&procedure=="<all>"&&context.is_none()&&flavor==Flavor::Closed&&self.matches_compiled(inputs)}fn question_facts(&self)->&Self{self}}
pub fn with_policy_data<T>(provider:&dyn PolicyFactsProvider,inputs:&PolicyInputs,poll:&dyn Fn()->io::Result<()>,consume:impl FnOnce(&UnsealedPolicyFacts)->Result<T,Failure>)->Result<T,Failure>{with_read_question(|visit|provider.with_policy_facts(visit),inputs,"<policy>","<all>",None,Flavor::Closed,poll,consume)}
pub fn policy_data_from_pages(inputs:&PolicyInputs,root:&std::path::Path,pages:&dyn crate::reactive_raw_policy_pages::RawPolicyPages,order:&std::collections::HashMap<String,usize>,budget:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<UnsealedPolicyFacts,Failure>{
 poll()?;let produced=(||{let scratch=Budget::scoped_temporaries(budget).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;let value=(||{let source=ReadSource::native(inputs,root,&scratch)?.with_raw_policy_pages(pages,order).with_checkpoint(poll);let facts=PolicyFacts::capture(&source,&mut||poll())?;let names=source.dependency_defines()?;let count=names.len();let bytes=count.checked_mul(4*std::mem::size_of::<String>()).and_then(|n|n.checked_add(64)).ok_or_else(||{scratch.deny();Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"policy defines capacity overflow"))})?;scratch.charge(bytes)?;let mut defines=Vec::new();defines.try_reserve_exact(count).map_err(|actual|{scratch.deny();Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,actual))})?;if defines.capacity().checked_mul(std::mem::size_of::<String>()).is_none_or(|n|n>bytes){scratch.deny();return Err(Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"policy defines allocator exceeds admission")))}for name in names{poll()?;defines.push(name)}Ok::<_,Failure>(UnsealedPolicyFacts{owner:inputs.archive().original_owner_witness(),facts,defines})})();let funded=match value{Ok(value)=>match value.retained_charge().ok_or_else(||{budget.deny();io::Error::new(io::ErrorKind::OutOfMemory,"policy data retained capacity overflow")}).and_then(|bytes|budget.charge(bytes).map_err(|message|io::Error::new(io::ErrorKind::OutOfMemory,message))){Ok(())=>Ok(value),Err(actual)=>{drop(value);Err(Failure::Operational(actual))}},Err(actual)=>Err(actual)};if funded.is_err(){scratch.keep_failed_scratch()}drop(scratch);funded})();finish_page_data(produced,budget,poll)
}

pub fn read_data_from_pages_with_policy(inputs:&PolicyInputs,root:&std::path::Path,pages:&dyn crate::reactive_raw_policy_pages::RawPolicyPages,order:&std::collections::HashMap<String,usize>,budget:&Arc<Budget>,globals:&dyn GlobalProvider,policy:&dyn PolicyFactsProvider,receiver:&str,procedure:&str,context:Option<&str>,flavor:Flavor,poll:&dyn Fn()->io::Result<()>,body:&BodyBorrower<'_>)->Result<UnsealedReadData,Failure>{let produced=with_policy_data(policy,inputs,poll,|data|read_data_from_pages_inner(inputs,root,pages,order,budget,globals,receiver,procedure,context,flavor,poll,BodyDemand::Strict(body),Some(&data.facts)));finish_page_data(produced,budget,poll)}

pub fn dependency_data_from_pages_with_policy(inputs:&PolicyInputs,root:&std::path::Path,pages:&dyn crate::reactive_raw_policy_pages::RawPolicyPages,order:&std::collections::HashMap<String,usize>,budget:&Arc<Budget>,globals:&dyn GlobalProvider,reads:&dyn RawPolicyReadProvider,policy:&dyn PolicyFactsProvider,poll:&dyn Fn()->io::Result<()>,body:&BodyBorrower<'_>)->Result<UnsealedDependencyData,Failure>{dependency_data_from_pages_with_policy_using(inputs,root,pages,order,budget,globals,reads,policy,poll,body,None)}

/// Selected setter's dependency candidates use its actual mixed Tree headers.
pub fn dependency_data_from_pages_with_selected_setter_files(inputs:&PolicyInputs,root:&std::path::Path,pages:&dyn crate::reactive_raw_policy_pages::RawPolicyPages,order:&std::collections::HashMap<String,usize>,budget:&Arc<Budget>,globals:&dyn GlobalProvider,reads:&dyn RawPolicyReadProvider,policy:&dyn PolicyFactsProvider,poll:&dyn Fn()->io::Result<()>,body:&BodyBorrower<'_>,selected_setter_files:&dyn crate::captured_raw_file::SelectedTreeFiles)->Result<UnsealedDependencyData,Failure>{
 dependency_data_from_pages_with_policy_using(inputs,root,pages,order,budget,globals,reads,policy,poll,body,Some(selected_setter_files))
}

fn dependency_data_from_pages_with_policy_using(inputs:&PolicyInputs,root:&std::path::Path,pages:&dyn crate::reactive_raw_policy_pages::RawPolicyPages,order:&std::collections::HashMap<String,usize>,budget:&Arc<Budget>,globals:&dyn GlobalProvider,reads:&dyn RawPolicyReadProvider,policy:&dyn PolicyFactsProvider,poll:&dyn Fn()->io::Result<()>,body:&BodyBorrower<'_>,selected_setter_files:Option<&dyn crate::captured_raw_file::SelectedTreeFiles>)->Result<UnsealedDependencyData,Failure>{let produced=with_policy_data(policy,inputs,poll,|data|dependency_data_from_pages_inner(inputs,root,pages,order,budget,globals,reads,poll,body,Some(data),selected_setter_files));finish_page_data(produced,budget,poll)}

/// Same renderer and collector, borrowing canonical policy rows from an actual
/// checked source loan. Coverage/test-domain roles remain the host's witnesses.
pub fn render_reads_data_from_pages_with_policy(inputs:&PolicyInputs,root:&std::path::Path,pages:&dyn crate::reactive_raw_policy_pages::RawPolicyPages,order:&std::collections::HashMap<String,usize>,test_types:&std::collections::BTreeSet<String>,budget:&Arc<Budget>,provider:&dyn RawPolicyReadProvider,policy:&dyn PolicyFactsProvider,poll:&dyn Fn()->io::Result<()>,body:&BodyBorrower<'_>)->Result<crate::sparse_slots_policy::Output,Failure>{
 let produced=with_policy_data(policy,inputs,poll,|data|{let source=ReadSource::native(inputs,root,budget)?.with_raw_policy_pages(pages,order).with_checkpoint(poll).with_body_borrower(body);let scratch=Budget::scoped_temporaries(budget).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;let rendered=source.with_budget(&scratch,|work|render_reads_collect(work,&crate::reactive_dependency_native::ReadQuestions::RawData(provider),|_|Ok(test_types),poll,Some(data)));let funded=fund_read_output(rendered,budget,scratch,poll);if matches!(&funded,Err(Failure::Operational(_))){return funded}source.require()?;funded});finish_page_data(produced,budget,poll)
}

fn fund_read_output(result:Result<crate::sparse_slots_policy::Output,Failure>,budget:&Arc<Budget>,scratch:Arc<Budget>,checkpoint:&dyn Fn()->io::Result<()>)->Result<crate::sparse_slots_policy::Output,Failure>{let funded=match result{Ok(output)=>{let bytes=output.diags.capacity().checked_mul(std::mem::size_of::<crate::sparse_slots_policy::Diagnostic>()).and_then(|rows|output.body.capacity().checked_add(rows)).and_then(|n|n.checked_add(std::mem::size_of::<crate::sparse_slots_policy::Output>())).and_then(|initial|output.diags.iter().try_fold(initial,|n,d|n.checked_add(d.rel.capacity())?.checked_add(d.msg.capacity())));match bytes.ok_or_else(||{budget.deny();Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"read generator retained output overflow"))}).and_then(|bytes|budget.charge(bytes).map_err(|actual|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,actual)))){Ok(())=>Ok(output),Err(actual)=>{drop(output);Err(actual)}}},Err(actual)=>Err(actual)};if funded.is_err(){scratch.keep_failed_scratch()}drop(scratch);if matches!(&funded,Err(Failure::Operational(_))){return funded}checkpoint()?;if budget.denied(){return Err(Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"read generator aggregate admission refused")))}funded
}
fn auto_decisions(source:&ReadSource<'_>,facts:&crate::reactive_dependency_result::FrozenDeps,includes:&[String],excludes:&[&[String]],checkpoint:&dyn Fn()->io::Result<()>)->Result<crate::auto_tracking_policy::AutoSet,Failure>{auto_decisions_rows(source,facts.candidates.iter().map(|(owner,name)|(owner.as_str(),name.as_str())),includes,excludes,checkpoint)}
pub(crate) fn auto_decisions_rows<'a>(source:&dyn crate::reactive_global_source::Source,rows:impl ExactSizeIterator<Item=(&'a str,&'a str)>,includes:&'a[String],excludes:&[&[String]],checkpoint:&dyn Fn()->io::Result<()>)->Result<crate::auto_tracking_policy::AutoSet,Failure>{
   let count=rows.len().checked_add(includes.len()).ok_or_else(||{source.budget().deny();Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"AutoTracked candidate count overflow"))})?;
   let bytes=count.checked_mul(4*std::mem::size_of::<(&str,&str)>()).and_then(|n|n.checked_add(64)).ok_or_else(||{source.budget().deny();Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"AutoTracked candidate capacity overflow"))})?;source.budget().charge(bytes)?;let mut candidates=Vec::new();candidates.try_reserve_exact(count).map_err(|actual|{source.budget().deny();Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,actual))})?;if candidates.capacity().checked_mul(std::mem::size_of::<(&str,&str)>()).is_none_or(|n|n>bytes){source.budget().deny();return Err(Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"AutoTracked candidate allocator exceeds admission")))}
   for pair in rows{checkpoint()?;candidates.push(pair);}for entry in includes{checkpoint()?;if let Some(pair)=entry.split_once("::"){candidates.push(pair)}}candidates.sort_unstable();candidates.dedup();
   let defs=crate::auto_tracking_native::setter_defs(source)?;let set=crate::auto_tracking_native::decide_rows(source,&defs,candidates.into_iter(),&excludes)?;

Ok(set)
}

impl UnsealedDependencyData{
 /// Owned data only. Actual CODE and generator-CLI test completion must be
 /// authenticated by the full host before this output can be an Artifact.
 pub fn render_auto_data_from_pages(&self,inputs:&PolicyInputs,root:&std::path::Path,pages:&dyn crate::reactive_raw_policy_pages::RawPolicyPages,order:&std::collections::HashMap<String,usize>,configuration:&crate::captured_raw_file::Config,configuration_path:&std::path::Path,test_types:&std::collections::BTreeSet<String>,budget:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<crate::sparse_slots_policy::Output,Failure>{
  poll()?;if !self.matches_compiled(inputs){return Err(Failure::Operational(io::Error::new(io::ErrorKind::InvalidInput,"Auto data belongs to another compiled original")))}budget.charge(root.as_os_str().len().checked_mul(8).and_then(|n|n.checked_add(1024)).ok_or_else(||{budget.deny();Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"Auto fixed config path capacity overflow"))})?)?;let expected=root.join("tools/ci/lint_scopes.toml");if dm_preprocess::regions::canonical_path(configuration_path)!=dm_preprocess::regions::canonical_path(&expected){return Err("AutoTracked requires the original fixed lint_scopes configuration".into())}
  let scratch=Budget::scoped_temporaries(budget).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;let produced=(||{let source=ReadSource::native(inputs,root,&scratch)?.with_raw_policy_pages(pages,order).with_checkpoint(poll);let set=configuration.with_auto_tracked_lists(|includes,excludes|auto_decisions(&source,&self.value.facts,includes,excludes,poll))?;source.require()?;crate::auto_tracking_emitter::generate_admitted(&set,test_types,budget,poll).map_err(Failure::Operational)})();if produced.is_err(){scratch.keep_failed_scratch()}drop(scratch);finish_page_data(produced,budget,poll)
 }
}

fn render_plans_pages_using(facts:&crate::reactive_dependency_result::FrozenDeps,inputs:&PolicyInputs,root:&std::path::Path,pages:&dyn crate::reactive_raw_policy_pages::RawPolicyPages,order:&std::collections::HashMap<String,usize>,budget:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<crate::sparse_slots_policy::Output,Failure>{
  let scratch=Budget::scoped_temporaries(budget).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;
  let produced=(||{let source=ReadSource::native(inputs,root,&scratch)?.with_raw_policy_pages(pages,order).with_checkpoint(poll);let mut rendered=crate::reactive_plans_generator_native::generate(&source,crate::reactive_dependency_view::Analysis::Frozen(facts))?;let mut out=crate::sparse_slots_policy::Output::default();out.body=std::mem::take(&mut rendered.body);out.diags=std::mem::take(&mut rendered.diags);drop(rendered);let bytes=out.diags.capacity().checked_mul(std::mem::size_of::<crate::sparse_slots_policy::Diagnostic>()).and_then(|n|n.checked_add(out.body.capacity())).and_then(|n|out.diags.iter().try_fold(n,|n,d|n.checked_add(d.rel.capacity())?.checked_add(d.msg.capacity()))).ok_or_else(||Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"Plans retained output overflow")))?;budget.charge(bytes).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;Ok(out)})();if produced.is_err(){scratch.keep_failed_scratch()}drop(scratch);finish_page_data(produced,budget,poll)
}
impl UnsealedDependencyData{
 /// Output DATA only; the real host separately validates current full scopes.
 pub fn render_plans_data_from_pages(&self,inputs:&PolicyInputs,root:&std::path::Path,pages:&dyn crate::reactive_raw_policy_pages::RawPolicyPages,order:&std::collections::HashMap<String,usize>,budget:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<crate::sparse_slots_policy::Output,Failure>{poll()?;if !self.matches_compiled(inputs){return Err(Failure::Operational(io::Error::new(io::ErrorKind::InvalidInput,"Plans data belongs to another compiled source")))}render_plans_pages_using(&self.value.facts,inputs,root,pages,order,budget,poll)}
}
impl DependencyResult{
 /// Finite dependency DATA may exercise the same renderer without receiving
 /// any full-scope Artifact or completion authority.
 pub fn render_plans_data_from_pages(&self,inputs:&PolicyInputs,root:&std::path::Path,pages:&dyn crate::reactive_raw_policy_pages::RawPolicyPages,order:&std::collections::HashMap<String,usize>,budget:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<crate::sparse_slots_policy::Output,Failure>{poll()?;if !self.matches(inputs){return Err(Failure::Operational(io::Error::new(io::ErrorKind::InvalidInput,"Plans dependency source differs")))}render_plans_pages_using(&self.facts,inputs,root,pages,order,budget,poll)}
}

impl DependencyResult{
 /// Finite original Plans generation over the SAME completed dependency rows.
 /// Raw metadata loans grant no whole-workspace or default CLI coverage.
 pub fn render_plans(&self,raw:&crate::captured_raw_policy::CapturedRawPolicy,inputs:&PolicyInputs,budget:&Arc<Budget>,checkpoint:&dyn Fn()->io::Result<()>)->Result<crate::sparse_slots_policy::Output,Failure>{checkpoint()?;if !self.matches(inputs){return Err(Failure::Operational(io::Error::new(io::ErrorKind::InvalidInput,"Plans dependency source owner differs")))}raw.validate_current_raw_roster(inputs)?;
 let scratch=Budget::scoped_temporaries(budget).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;
 let produced:Result<crate::sparse_slots_policy::Output,Failure>=(||{let source=ReadSource::capture(raw,inputs,&scratch)?.with_checkpoint(checkpoint);let mut rendered=crate::reactive_plans_generator_native::generate(&source,crate::reactive_dependency_view::Analysis::Frozen(&self.facts))?;let mut output=crate::sparse_slots_policy::Output::default();output.body=std::mem::take(&mut rendered.body);output.diags=std::mem::take(&mut rendered.diags);Ok(output)})();
 let funded=match produced{Ok(output)=>{let bytes=output.diags.capacity().checked_mul(std::mem::size_of::<crate::sparse_slots_policy::Diagnostic>()).and_then(|rows|output.body.capacity().checked_add(rows)).and_then(|n|n.checked_add(std::mem::size_of::<crate::sparse_slots_policy::Output>())).and_then(|initial|output.diags.iter().try_fold(initial,|n,d|n.checked_add(d.rel.capacity())?.checked_add(d.msg.capacity())));match bytes.ok_or_else(||{budget.deny();Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"Plans retained output overflow"))}).and_then(|bytes|budget.charge(bytes).map_err(|actual|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,actual)))){Ok(())=>Ok(output),Err(actual)=>{drop(output);Err(actual)}}},Err(actual)=>Err(actual)};if funded.is_err(){scratch.keep_failed_scratch()}drop(scratch);if matches!(&funded,Err(Failure::Operational(_))){return funded}checkpoint()?;if budget.denied(){return Err(Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"Plans aggregate admission refused")))}if !self.matches(inputs){return Err(Failure::Operational(io::Error::new(io::ErrorKind::InvalidInput,"Plans dependency source owner changed")))}raw.validate_current_raw_roster(inputs)?;funded
 }
}

/// Unsealed semantic-read policy data over actual current canonical policy/read
/// child loans. The host, not these callbacks, owns full CODE source completion
/// and the selected original analysis context. No model/facts clone is retained.
pub fn sem_reads_data_from_pages(inputs:&PolicyInputs,root:&std::path::Path,pages:&dyn crate::reactive_raw_policy_pages::RawPolicyPages,order:&std::collections::HashMap<String,usize>,budget:&Arc<Budget>,globals:&dyn GlobalProvider,reads:&dyn RawPolicyReadProvider,policy:&dyn PolicyFactsProvider,poll:&dyn Fn()->io::Result<()>,body:&BodyBorrower<'_>)->Result<crate::captured_sem_reads::SemReadData,Failure>{
 sem_reads_data_from_pages_using(inputs,root,pages,order,budget,globals,reads,policy,poll,body,None)
}

/// Explicit combined Tree loan applies only to finding-path ALLOW lookup.
pub fn sem_reads_data_from_pages_with_selected_allows(inputs:&PolicyInputs,root:&std::path::Path,pages:&dyn crate::reactive_raw_policy_pages::RawPolicyPages,order:&std::collections::HashMap<String,usize>,budget:&Arc<Budget>,globals:&dyn GlobalProvider,reads:&dyn RawPolicyReadProvider,policy:&dyn PolicyFactsProvider,poll:&dyn Fn()->io::Result<()>,body:&BodyBorrower<'_>,selected_allows:&dyn crate::captured_sem_reads::SelectedReadAllowFiles)->Result<crate::captured_sem_reads::SemReadData,Failure>{
 sem_reads_data_from_pages_using(inputs,root,pages,order,budget,globals,reads,policy,poll,body,Some(selected_allows))
}

fn sem_reads_data_from_pages_using(inputs:&PolicyInputs,root:&std::path::Path,pages:&dyn crate::reactive_raw_policy_pages::RawPolicyPages,order:&std::collections::HashMap<String,usize>,budget:&Arc<Budget>,globals:&dyn GlobalProvider,reads:&dyn RawPolicyReadProvider,policy:&dyn PolicyFactsProvider,poll:&dyn Fn()->io::Result<()>,body:&BodyBorrower<'_>,selected_allows:Option<&dyn crate::captured_sem_reads::SelectedReadAllowFiles>)->Result<crate::captured_sem_reads::SemReadData,Failure>{
 budget.require().map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;let produced=with_policy_data(policy,inputs,poll,|data|{budget.require().map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;let source=ReadSource::native(inputs,root,budget)?.with_raw_policy_pages(pages,order).with_checkpoint(poll).with_body_borrower(body);let globals=GlobalAdapter{source:&source,provider:globals};crate::captured_sem_reads::collect_source(&source,&data.facts,&globals,&crate::reactive_dependency_native::ReadQuestions::RawData(reads),order,poll,selected_allows)});finish_page_data(produced,budget,poll)
}

/// Lazy SAME-Db dependency result DATA. Arbitrary callback success does not
/// issue a result or whole-source completion; actual original-owner checks are mandatory.
pub trait DependencyDataProvider{fn with_dependency_data(&self,consume:&mut dyn FnMut(&UnsealedDependencyData)->Result<(),Failure>)->Result<(),Failure>;}
impl<F> DependencyDataProvider for F where F:Fn(&mut dyn FnMut(&UnsealedDependencyData)->Result<(),Failure>)->Result<(),Failure>{fn with_dependency_data(&self,consume:&mut dyn FnMut(&UnsealedDependencyData)->Result<(),Failure>)->Result<(),Failure>{self(consume)}}
impl QuestionValue for UnsealedDependencyData{type Facts=Self;fn question_matches(&self,inputs:&PolicyInputs,receiver:&str,procedure:&str,context:Option<&str>,flavor:Flavor)->bool{receiver=="<dependencies>"&&procedure=="<all>"&&context.is_none()&&flavor==Flavor::Closed&&self.matches_compiled(inputs)}fn question_facts(&self)->&Self{self}}
pub fn with_dependency_data<T>(provider:&dyn DependencyDataProvider,inputs:&PolicyInputs,poll:&dyn Fn()->io::Result<()>,consume:impl FnOnce(&UnsealedDependencyData)->Result<T,Failure>)->Result<T,Failure>{with_read_question(|visit|provider.with_dependency_data(visit),inputs,"<dependencies>","<all>",None,Flavor::Closed,poll,consume)}
/// No body demand is introduced by this consumer: existing complete dependency
/// rows carry its facts; original header identifiers/ALLOW borrow current files.
pub fn untracked_inputs_data_from_pages(inputs:&PolicyInputs,root:&std::path::Path,pages:&dyn crate::reactive_raw_policy_pages::RawPolicyPages,order:&std::collections::HashMap<String,usize>,configuration:&crate::captured_raw_file::Config,budget:&Arc<Budget>,dependencies:&dyn DependencyDataProvider,poll:&dyn Fn()->io::Result<()>)->Result<crate::captured_sem_reads::SemanticPolicyData,Failure>{
 untracked_inputs_data_from_pages_using(inputs,root,pages,order,configuration,budget,dependencies,poll,None)
}

/// Explicit combined Tree loan applies only to finding-path ALLOW lookup.
pub fn untracked_inputs_data_from_pages_with_selected_allows(inputs:&PolicyInputs,root:&std::path::Path,pages:&dyn crate::reactive_raw_policy_pages::RawPolicyPages,order:&std::collections::HashMap<String,usize>,configuration:&crate::captured_raw_file::Config,budget:&Arc<Budget>,dependencies:&dyn DependencyDataProvider,poll:&dyn Fn()->io::Result<()>,selected_allows:&dyn crate::captured_sem_reads::SelectedReadAllowFiles)->Result<crate::captured_sem_reads::SemanticPolicyData,Failure>{
 untracked_inputs_data_from_pages_using(inputs,root,pages,order,configuration,budget,dependencies,poll,Some(selected_allows))
}

fn untracked_inputs_data_from_pages_using(inputs:&PolicyInputs,root:&std::path::Path,pages:&dyn crate::reactive_raw_policy_pages::RawPolicyPages,order:&std::collections::HashMap<String,usize>,configuration:&crate::captured_raw_file::Config,budget:&Arc<Budget>,dependencies:&dyn DependencyDataProvider,poll:&dyn Fn()->io::Result<()>,selected_allows:Option<&dyn crate::captured_sem_reads::SelectedReadAllowFiles>)->Result<crate::captured_sem_reads::SemanticPolicyData,Failure>{
 budget.require().map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;let produced=with_dependency_data(dependencies,inputs,poll,|data|{budget.require().map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;let source=ReadSource::native(inputs,root,budget)?.with_raw_policy_pages(pages,order).with_checkpoint(poll);crate::captured_untracked_inputs::collect_source(&source,crate::reactive_dependency_view::Analysis::Frozen(&data.value.facts),configuration,poll,selected_allows)});finish_page_data(produced,budget,poll)
}

#[cfg(test)]mod semantic_callback_budget_tests{use super::*;
 #[test]fn denial_is_typed_before_provider_final_cancel_and_actual_io_stays_first(){
 let budget=Budget::new(1024).unwrap();let mut final_poll=false;let pending:Result<(),Failure>=budgeted_action(&budget,||{assert!(budget.charge(2048).is_err());Err(Failure::Unsupported("semantic child refusal".into()))});let result:Result<(),io::Error>=match pending{Err(Failure::Operational(actual))=>Err(actual),other=>{final_poll=true;drop(other);Err(io::Error::new(io::ErrorKind::Interrupted,"late provider cancellation"))}};assert_eq!(result.unwrap_err().kind(),io::ErrorKind::OutOfMemory);assert!(!final_poll);let mut called=false;let denied:Result<(),Failure>=budgeted_action(&budget,||{called=true;Ok(())});assert!(matches!(denied,Err(Failure::Operational(ref actual))if actual.kind()==io::ErrorKind::OutOfMemory));assert!(!called);
 let budget=Budget::new(1024).unwrap();let pending:Result<(),Failure>=budgeted_action(&budget,||{assert!(budget.charge(2048).is_err());Err(Failure::Operational(io::Error::from_raw_os_error(1450)))});assert!(matches!(pending,Err(Failure::Operational(ref actual))if actual.raw_os_error()==Some(1450)));
 let fresh=Budget::new(1024).unwrap();assert_eq!(budgeted_action(&fresh,||Ok(7)).unwrap(),7);
 }
}

/// Owned include-order DATA from an authenticated caller's fixed-original loan.
/// Option::None means the host proved this requested fixed file absent; this
/// helper itself grants no source/completion role. Exact old read_to_string
/// policy yields empty order for observed invalid UTF8, while preserving a BOM.
pub fn scoped_original_include_order_bytes(original:Option<&[u8]>,budget:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<ScopedOriginalIncludeOrder,Failure>{
 budget.require().map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;poll()?;let scratch=Budget::scoped_temporaries(budget).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;
 let produced=(||{let text=original.and_then(|bytes|std::str::from_utf8(bytes).ok()).unwrap_or("");let mut control=crate::captured_allow_annotations::Operation{budget:&scratch,poll};let order=crate::raw_marker_policy::dme_include_order_controlled(text,false,&mut control)?;scratch.require().map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;poll()?;scratch.require().map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;Ok(order)})();
 match produced{Ok(order)=>Ok(ScopedOriginalIncludeOrder{order:Some(order),_scratch:scratch}),Err(actual)=>{scratch.keep_failed_scratch();Err(actual)}}
}
#[cfg(test)]mod fixed_manifest_order_data_tests{
 use super::*;
 #[test]fn fixed_manifest_bytes_preserve_original_bom_invalid_negative_duplicates_and_slash_policy(){for bytes in [None,Some(b"#include \"code\\z.dm\"\n#include \"code/a.dm\"\n#include \"code\\z.dm\"\n".as_slice()),Some(b"\xef\xbb\xbf#include \"code/first.dm\"\n#include \"code/second.dm\"\n".as_slice()),Some(b"#include \"code/valid.dm\"\n// invalid \xff\n".as_slice())]{let budget=Budget::new(1<<20).unwrap();let expected=bytes.and_then(|bytes|std::str::from_utf8(bytes).ok()).map(crate::raw_marker_policy::dme_include_order).unwrap_or_default();let actual=scoped_original_include_order_bytes(bytes,&budget,&||Ok(())).unwrap();assert_eq!(&*actual,&expected);}}
 #[test]fn fixed_manifest_data_keeps_first_io_and_real_denial_before_later_interrupted_poll_then_fresh_retry(){let budget=Budget::new(1<<20).unwrap();let actual=scoped_original_include_order_bytes(None,&budget,&||Err(io::Error::from_raw_os_error(1450)));assert!(matches!(actual,Err(Failure::Operational(ref actual))if actual.raw_os_error()==Some(1450)));let tiny=Budget::new(256).unwrap();let poll=||if tiny.denied(){Err(io::Error::new(io::ErrorKind::Interrupted,"later cancellation after real manifest denial"))}else{Ok(())};let actual=scoped_original_include_order_bytes(Some(b"#include \"code/actual.dm\"\n"),&tiny,&poll);assert!(matches!(actual,Err(Failure::Operational(ref actual))if actual.kind()==io::ErrorKind::OutOfMemory));let fresh=Budget::new(1<<20).unwrap();let actual=scoped_original_include_order_bytes(Some(b"#include \"code/actual.dm\"\n"),&fresh,&||Ok(())).unwrap();assert_eq!(actual.get("code/actual.dm"),Some(&0));}
}

/// Exact SetterPublishes route shares the existing globals/read/dependency graph.
/// No second globals/reads walk, parser/model or cache is created by this fold.
pub fn setter_publishes_data_from_pages(inputs:&PolicyInputs,root:&std::path::Path,pages:&dyn crate::reactive_raw_policy_pages::RawPolicyPages,order:&std::collections::HashMap<String,usize>,configuration:&crate::captured_raw_file::Config,budget:&Arc<Budget>,dependencies:&dyn DependencyDataProvider,policy:&dyn PolicyFactsProvider,poll:&dyn Fn()->io::Result<()>,body:&BodyBorrower<'_>)->Result<crate::captured_sem_reads::SemanticPolicyData,Failure>{
 setter_publishes_data_from_pages_using(inputs,root,pages,order,configuration,budget,dependencies,policy,poll,body,None)
}

/// Selected setter uses the same Tree qualification as its dependency child.
pub fn setter_publishes_data_from_pages_with_selected_setter_files(inputs:&PolicyInputs,root:&std::path::Path,pages:&dyn crate::reactive_raw_policy_pages::RawPolicyPages,order:&std::collections::HashMap<String,usize>,configuration:&crate::captured_raw_file::Config,budget:&Arc<Budget>,dependencies:&dyn DependencyDataProvider,policy:&dyn PolicyFactsProvider,poll:&dyn Fn()->io::Result<()>,body:&BodyBorrower<'_>,selected_setter_files:&dyn crate::captured_raw_file::SelectedTreeFiles)->Result<crate::captured_sem_reads::SemanticPolicyData,Failure>{
 setter_publishes_data_from_pages_using(inputs,root,pages,order,configuration,budget,dependencies,policy,poll,body,Some(selected_setter_files))
}

fn setter_publishes_data_from_pages_using(inputs:&PolicyInputs,root:&std::path::Path,pages:&dyn crate::reactive_raw_policy_pages::RawPolicyPages,order:&std::collections::HashMap<String,usize>,configuration:&crate::captured_raw_file::Config,budget:&Arc<Budget>,dependencies:&dyn DependencyDataProvider,policy:&dyn PolicyFactsProvider,poll:&dyn Fn()->io::Result<()>,body:&BodyBorrower<'_>,selected_setter_files:Option<&dyn crate::captured_raw_file::SelectedTreeFiles>)->Result<crate::captured_sem_reads::SemanticPolicyData,Failure>{
 let produced=with_dependency_data(dependencies,inputs,poll,|data|with_policy_data(policy,inputs,poll,|facts|{let source=ReadSource::native(inputs,root,budget)?.with_raw_policy_pages(pages,order).with_checkpoint(poll).with_body_borrower(body).with_selected_setter_files(selected_setter_files);let set=configuration.with_auto_tracked_lists(|includes,excludes|auto_decisions(&source,&data.value.facts,includes,excludes,poll))?;crate::captured_setter_publishes::collect_source(&source,&set,&facts.facts,poll)}));finish_page_data(produced,budget,poll)
}

/// Whole derived-read DATA fold over the SAME complete source, eager Globals,
/// authentic raw CODE loans and shared native generator. No report role is
/// issued here; the host must exhaust/join its actual selected source purpose.
pub fn derived_reads_data_from_pages(inputs:&PolicyInputs,root:&std::path::Path,selected_pages:&dyn crate::reactive_raw_policy_pages::RawPolicyPages,pages:&dyn crate::reactive_raw_policy_pages::RawPolicyPages,order:&std::collections::HashMap<String,usize>,test_types:&std::collections::BTreeSet<String>,budget:&Arc<Budget>,globals:&dyn GlobalProvider,poll:&dyn Fn()->io::Result<()>,body:&BodyBorrower<'_>)->Result<crate::captured_derived_reads::DerivedReadData,Failure>{
 derived_reads_data_from_pages_using(inputs,root,selected_pages,pages,order,test_types,budget,globals,poll,body,None)
}

/// Actual fixture inspection on the SAME native collector; no report role.
pub fn derived_reads_fixture_from_pages(inputs:&PolicyInputs,root:&std::path::Path,selected_pages:&dyn crate::reactive_raw_policy_pages::RawPolicyPages,pages:&dyn crate::reactive_raw_policy_pages::RawPolicyPages,order:&std::collections::HashMap<String,usize>,test_types:&std::collections::BTreeSet<String>,budget:&Arc<Budget>,globals:&dyn GlobalProvider,poll:&dyn Fn()->io::Result<()>,body:&BodyBorrower<'_>,fixture:&mut crate::captured_derived_reads::FixtureVisitor<'_>)->Result<crate::captured_derived_reads::DerivedReadData,Failure>{
 derived_reads_data_from_pages_using(inputs,root,selected_pages,pages,order,test_types,budget,globals,poll,body,Some(fixture))
}

fn derived_reads_data_from_pages_using(inputs:&PolicyInputs,root:&std::path::Path,selected_pages:&dyn crate::reactive_raw_policy_pages::RawPolicyPages,pages:&dyn crate::reactive_raw_policy_pages::RawPolicyPages,order:&std::collections::HashMap<String,usize>,test_types:&std::collections::BTreeSet<String>,budget:&Arc<Budget>,globals:&dyn GlobalProvider,poll:&dyn Fn()->io::Result<()>,body:&BodyBorrower<'_>,mut fixture:Option<&mut crate::captured_derived_reads::FixtureVisitor<'_>>)->Result<crate::captured_derived_reads::DerivedReadData,Failure>{
 budget.require().map_err(|m|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,m)))?;poll()?;
 let phase=Budget::scoped_temporaries(budget).map_err(|m|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,m)))?;
 let pending=(||{let source=ReadSource::native(inputs,root,&phase)?.with_raw_policy_pages(selected_pages,order).with_checkpoint(poll).with_body_borrower(body);let all_source=ReadSource::native(inputs,root,&phase)?.with_raw_policy_pages(pages,order).with_checkpoint(poll).with_body_borrower(body);let mut index=Some(crate::captured_derived_reads::prepare(&source,poll)?);let mut out=None;with_global_question(globals,inputs,poll,&mut|value|{let index=index.take().ok_or("derived schema consumed by a repeated Globals question")?;out=Some(match fixture.as_deref_mut(){Some(visit)=>crate::captured_derived_reads::collect_with_fixture(&source,&all_source,index,value,test_types,poll,visit)?,None=>crate::captured_derived_reads::collect(&source,&all_source,index,value,test_types,poll)?});Ok(true)})?;out.ok_or_else(||Failure::Unsupported("derived whole question omitted its actual Globals result".into()))})();
 let pending=finish_page_data(pending,&phase,poll);let pending=match pending{Ok(data)=>{let bytes=data.retained_charge().ok_or_else(||Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"derived retained report size overflow")))?;match budget.charge(bytes){Ok(())=>Ok(data),Err(message)=>{drop(data);Err(Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))}}},Err(actual)=>Err(actual)};
 if pending.is_err(){phase.keep_failed_scratch()}drop(phase);finish_page_data(pending,budget,poll)
}

/// Consume only unsealed preflight DATA AFTER the actual host has bound its
/// recorder/current source closure. This returns DATA, never a source grant.
pub fn derived_reads_data_from_preflight_pages(preflight:crate::captured_derived_reads::UnsealedDerivedIndexData,inputs:&PolicyInputs,root:&std::path::Path,selected_pages:&dyn crate::reactive_raw_policy_pages::RawPolicyPages,pages:&dyn crate::reactive_raw_policy_pages::RawPolicyPages,order:&std::collections::HashMap<String,usize>,test_types:&std::collections::BTreeSet<String>,budget:&Arc<Budget>,globals:&dyn GlobalProvider,poll:&dyn Fn()->io::Result<()>,body:&BodyBorrower<'_>)->Result<crate::captured_derived_reads::DerivedReadData,Failure>{
 budget.require().map_err(|m|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,m)))?;poll()?;let phase=Budget::scoped_temporaries(budget).map_err(|m|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,m)))?;let mut preflight=Some(preflight);
 let pending=(||{let source=ReadSource::native(inputs,root,&phase)?.with_raw_policy_pages(selected_pages,order).with_checkpoint(poll).with_body_borrower(body);let all_source=ReadSource::native(inputs,root,&phase)?.with_raw_policy_pages(pages,order).with_checkpoint(poll).with_body_borrower(body);let mut out=None;with_global_question(globals,inputs,poll,&mut|value|{let original=preflight.take().ok_or("Derived preflight consumed by repeated Globals callback")?;out=Some(original.collect_held(&source,&all_source,value,test_types,poll)?);Ok(true)})?;out.ok_or_else(||Failure::Unsupported("Derived preflight question omitted actual Globals".into()))})();
 let pending=finish_page_data(pending,&phase,poll);let pending=match pending{Ok(data)=>{let bytes=data.retained_charge().ok_or_else(||Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"Derived preflight result retention overflow")))?;match budget.charge(bytes){Ok(())=>Ok(data),Err(message)=>{drop(data);Err(Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))}}},Err(actual)=>Err(actual)};
 // Any unconsumed old index drops with its OWN actual funding after failure.
 drop(preflight);if pending.is_err(){phase.keep_failed_scratch()}drop(phase);finish_page_data(pending,budget,poll)
}

/// Unsealed declared+output handler partition over actual current full inputs.
/// Structural partial preparation/report/ALLOW completion remains a separate
/// typed host obligation. No ReadResult conversion or whole-policy witness.
pub fn handlers_declared_data_from_pages(inputs:&PolicyInputs,scope:Option<&crate::scopes::LintScope>,root:&std::path::Path,pages:&dyn crate::reactive_raw_policy_pages::RawPolicyPages,order:&std::collections::HashMap<String,usize>,budget:&Arc<Budget>,reads:&dyn RawPolicyReadProvider,poll:&dyn Fn()->io::Result<()>,body:&BodyBorrower<'_>,mut emit:impl FnMut(&'static str,&str,u32,String)->Result<(),Failure>)->Result<(),Failure>{
 poll()?;let source=ReadSource::native(inputs,root,budget)?.with_raw_policy_pages(pages,order).with_checkpoint(poll).with_body_borrower(body);
 crate::sem_handlers_native::full_from_current_raw_source(&source,reads,scope,&mut emit)?;
 poll()?;source.require()?;Ok(())
}

/// Declared/output finding DATA only: no full-handler report/ALLOW witness.
pub struct UnsealedHandlerDeclarations{sites:Vec<crate::lint::Site>}
impl UnsealedHandlerDeclarations{
 pub fn sites(&self)->&[crate::lint::Site]{&self.sites}
 pub fn serialize_data<S:serde::Serializer>(&self,s:S)->Result<S::Ok,S::Error>{serde::Serialize::serialize(&self.sites,s)}
 pub fn retained_charge(&self)->Option<usize>{self.sites.iter().try_fold(self.sites.capacity().checked_mul(std::mem::size_of::<crate::lint::Site>())?.checked_add(std::mem::size_of::<Self>())?,|n,row|n.checked_add(row.rule.capacity())?.checked_add(row.rel.capacity())?.checked_add(row.msg.capacity())?.checked_add(row.key.capacity())?.checked_add(row.ident.capacity()))}
}
pub fn handler_declarations_data_from_pages(inputs:&PolicyInputs,scope:Option<&crate::scopes::LintScope>,root:&std::path::Path,pages:&dyn crate::reactive_raw_policy_pages::RawPolicyPages,order:&std::collections::HashMap<String,usize>,budget:&Arc<Budget>,reads:&dyn RawPolicyReadProvider,poll:&dyn Fn()->io::Result<()>,body:&BodyBorrower<'_>)->Result<UnsealedHandlerDeclarations,Failure>{
 let mut data=UnsealedHandlerDeclarations{sites:Vec::new()};handlers_declared_data_from_pages(inputs,scope,root,pages,order,budget,reads,poll,body,|rule,relative,line,message|{let mut c=crate::captured_allow_annotations::Operation{budget,poll};crate::key_policy_control::row(&mut c,&mut data.sites)?;data.sites.push(crate::lint::Site{rule:crate::key_policy_control::own(&mut c,rule)?,rel:crate::key_policy_control::own(&mut c,relative)?,line,msg:message,key:String::new(),ident:String::new()});Ok(())})?;Ok(data)
}

/// Exact declared-removal consumer of already-issued SAME-owner dependencies.
pub fn drop_declared_fix_from_pages(inputs:&PolicyInputs,root:&std::path::Path,pages:&dyn crate::reactive_raw_policy_pages::RawPolicyPages,order:&std::collections::HashMap<String,usize>,configuration:&crate::captured_raw_file::Config,relative:&str,budget:&Arc<Budget>,dependencies:&dyn DependencyDataProvider,poll:&dyn Fn()->io::Result<()>,body:&BodyBorrower<'_>)->Result<crate::captured_tracked_fix::ListMacroFixData,Failure>{
 let result=with_dependency_data(dependencies,inputs,poll,|data|{let source=ReadSource::native(inputs,root,budget)?.with_raw_policy_pages(pages,order).with_checkpoint(poll).with_body_borrower(body);crate::captured_tracked_drop::collect_source(&source,crate::reactive_dependency_view::Analysis::Frozen(&data.value.facts),configuration,relative,poll)});finish_page_data(result,budget,poll)
}

/// Utility Globals share the existing native global classifier and completed
/// original source witness. The private result tag prevents strict CHECK/GEN
/// callers from adopting NoCode-derived utility facts.
pub fn globals_native_utility(inputs:&PolicyInputs,root:&std::path::Path,budget:&Arc<Budget>,checkpoint:&dyn Fn()->io::Result<()>,body:&crate::reactive_original_source::UtilityBodyBorrower<'_>)->Result<GlobalResult,Failure>{
 checkpoint()?;let source=ReadSource::native(inputs,root,budget)?.with_checkpoint(checkpoint).with_utility_body_borrower(body);
 let value=NativeGlobals::build(&source,checkpoint)?;checkpoint()?;source.require()?;
 Ok(GlobalResult{owner:inputs.archive().original_owner_witness(),value,utility:true})
}
/// SAME read scratch/freeze/retained-charge kernel with an explicit utility
/// request identity and canonical Kind4 body borrower. No direct body parse.
pub fn utility_read_data_from_pages_with_policy(inputs:&PolicyInputs,root:&std::path::Path,pages:&dyn crate::reactive_raw_policy_pages::RawPolicyPages,order:&std::collections::HashMap<String,usize>,budget:&Arc<Budget>,globals:&dyn GlobalProvider,policy:&dyn PolicyFactsProvider,receiver:&str,procedure:&str,context:Option<&str>,flavor:Flavor,poll:&dyn Fn()->io::Result<()>,body:&crate::reactive_original_source::UtilityBodyBorrower<'_>)->Result<UnsealedReadData,Failure>{
 let flavor=flavor.utility();let produced=with_policy_data(policy,inputs,poll,|data|read_data_from_pages_inner(inputs,root,pages,order,budget,globals,receiver,procedure,context,flavor,poll,BodyDemand::Utility(body),Some(&data.facts)));finish_page_data(produced,budget,poll)
}


/// Ordinary debug text uses actual Original callable selection and SAME current
/// canonical body loan. A rejected body prints -1 only after its private bound
/// Rejected product has been authenticated by that loan.
fn with_utility_procedure(inputs:&PolicyInputs,root:&std::path::Path,budget:&Arc<Budget>,checkpoint:&dyn Fn()->io::Result<()>,body:&crate::reactive_original_source::UtilityBodyBorrower<'_>,requested_owner:&str,name:&str,mut consume:impl FnMut(bool,Option<crate::native_sem_utility_render::Procedure<'_>>)->Result<(),Failure>)->Result<(),Failure>{
 use dm_ir::{ResolvedMeaning,SymbolId};
 use crate::native_sem_utility_render::Procedure;
 checkpoint()?;let source=ReadSource::native(inputs,root,budget)?.with_checkpoint(checkpoint).with_utility_body_borrower(body);source.require()?;
 let receiver=if requested_owner.is_empty(){"/"}else{requested_owner};let tree=inputs.archive().tree();let profile=tree.checker_builtin_profile().ok_or("utility callable profile absent")?;
 let type_known=if requested_owner.is_empty()||requested_owner=="/"{true}else{tree.checker_source_type_presence(profile,receiver).map_err(|e|format!("utility type presence: {e:?}"))?};
 match source.callable_checked(receiver,name)?{
  crate::reactive_original_source::SelectedCallable::Missing=>consume(type_known,None)?,
  crate::reactive_original_source::SelectedCallable::Source(call)=>{
   let mut code=None;crate::reactive_global_source::Source::with_body(&source,call.ordinal,&mut|loan|{code=Some(loan.statement_body().parsed().statements.len());Ok(())})?;
   // ProcBody reports the actual model location, not the distinct raw/engine-line projection used by lint sites.
   let point=inputs.archive().callable_header_source().reported_policy_line(call.member)?;let file=source.utility_report_file(&point.path)?;
   let owner=if call.owner.is_empty(){"/"}else{call.owner};
   consume(type_known,Some(Procedure{owner,name:call.name,file:&file,line:point.line,builtin:false,code}))?;
  },
  crate::reactive_original_source::SelectedCallable::Builtin=>{
   // Re-enter the SAME checked fact selector solely to borrow the selected
   // fixed catalog spelling; never infer declaring owner from the receiver.
   let rows=inputs.archive().callables().members().len();let reserve=std::mem::size_of::<ResolvedMeaning>().checked_mul(16).and_then(|n|n.checked_mul(rows)).and_then(|n|n.checked_add(tree.types().len().checked_mul(std::mem::size_of::<SymbolId>()*16)?)).and_then(|n|n.checked_add(8192)).ok_or_else(||Failure::Operational(io::ErrorKind::OutOfMemory.into()))?;
   budget.charge(reserve).map_err(|m|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,m)))?;
   let fact=dm_analysis::checker_call_facts::callable_any_using(tree,tree,profile,SymbolId::of(receiver),SymbolId::of(name),&mut||{checkpoint().map_err(Failure::Operational)})?;
   let dm_analysis::checker_call_facts::CallableFact::CheckerBuiltin{declaring_owner,name:actual_name,..}=fact else{return Err("utility builtin selector changed role".into())};
   let owner=tree.checker_builtin_spelling(profile,declaring_owner).ok_or("utility builtin owner spelling absent")?;let actual_name=tree.checker_builtin_spelling(profile,actual_name).ok_or("utility builtin name spelling absent")?;
   consume(type_known,Some(Procedure{owner:if owner.is_empty(){"/"}else{owner},name:actual_name,file:"",line:1,builtin:true,code:None}))?;
  }
 }
 checkpoint()?;source.require()?;Ok(())
}

#[derive(serde::Serialize)]pub struct UtilityProcedure{type_known:bool,selected:Option<UtilityProcedureRow>}
#[derive(serde::Serialize)]struct UtilityProcedureRow{owner:String,name:String,file:String,line:usize,builtin:bool,code:Option<usize>}
impl UtilityProcedure{
 fn capture(inputs:&PolicyInputs,root:&std::path::Path,budget:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>,body:&crate::reactive_original_source::UtilityBodyBorrower<'_>,owner:&str,name:&str)->Result<Self,Failure>{
  fn copied(text:&str,b:&Budget)->Result<String,Failure>{let bound=text.len().checked_mul(4).and_then(|n|n.checked_add(std::mem::size_of::<String>())).ok_or_else(||Failure::Operational(io::ErrorKind::OutOfMemory.into()))?;b.charge(bound).map_err(|m|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,m)))?;let mut out=String::new();out.try_reserve_exact(text.len()).map_err(|e|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,e)))?;if out.capacity().checked_add(std::mem::size_of::<String>()).is_none_or(|n|n>bound){return Err(Failure::Operational(io::ErrorKind::OutOfMemory.into()))}out.push_str(text);Ok(out)}
  let mut result=None;with_utility_procedure(inputs,root,budget,poll,body,owner,name,|type_known,selected|{if result.is_some(){return Err("utility procedure descriptor repeated".into())}let selected=selected.map(|p|Ok::<_,Failure>(UtilityProcedureRow{owner:copied(p.owner,budget)?,name:copied(p.name,budget)?,file:copied(p.file,budget)?,line:p.line,builtin:p.builtin,code:p.code})).transpose()?;result=Some(Self{type_known,selected});Ok(())})?;result.ok_or_else(||"actual utility procedure descriptor absent".into())
 }
 pub fn write(&self,owner:&str,name:&str,out:&mut impl io::Write)->io::Result<()>{let selected=self.selected.as_ref().map(|p|crate::native_sem_utility_render::Procedure{owner:&p.owner,name:&p.name,file:&p.file,line:p.line,builtin:p.builtin,code:p.code});crate::native_sem_utility_render::debug_proc(out,owner,name,self.type_known,selected)}
 fn visit_storage(&self,visit:&mut dyn FnMut(&'static str,usize,usize,usize)){if let Some(p)=&self.selected{for value in [&p.owner,&p.name,&p.file]{if value.capacity()!=0{visit("utility_procedure_text",value.as_ptr() as usize,value.len(),value.capacity());}}}}
}

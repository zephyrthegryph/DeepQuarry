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
 /// Internal query cutoff stream includes all policy facts, not just the old
 /// public oracle schema. This is data only; source witness checks still apply.
 pub fn serialize_dependency_facts<S:serde::Serializer>(&self,serializer:S)->Result<S::Ok,S::Error>{self.value.serialize_dependencies(serializer)}
 pub(crate) fn outside_setters(&self)->&crate::write_policy::WriteRows{self.value.outside_setters()}

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
/// Native semantic-only Globals producer. The caller must authenticate current
/// evidence/config/mapping before cache access and lend the SAME active query
/// context body borrower. No raw marker coverage or producer selection follows.
pub fn globals_native(inputs:&PolicyInputs,root:&std::path::Path,budget:&Arc<Budget>,checkpoint:&dyn Fn()->io::Result<()>,body:&BodyBorrower<'_>)->Result<GlobalResult,Failure>{
 checkpoint()?;let source=ReadSource::native(inputs,root,budget)?.with_checkpoint(checkpoint).with_body_borrower(body);
 let value=NativeGlobals::build(&source,checkpoint)?;checkpoint()?;source.require()?;
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
/// One lazy current-source question from the existing query graph. A provider
/// cannot mint an answer without exactly one authenticated borrowed result.
/// Actual callback/provider IO stays operational even after a semantic refusal.
pub fn with_global_question(provider:&dyn GlobalProvider,inputs:&PolicyInputs,checkpoint:&dyn Fn()->io::Result<()>,action:&mut dyn FnMut(&GlobalResult)->Result<bool,Failure>)->Result<bool,Failure>{
 checkpoint()?;let mut answer=None;let mut first=None;let mut called=false;
 let returned=provider.with_globals(&mut|value|{
  let attempt=(||{checkpoint()?;if called{return Err(Failure::Operational(io::Error::new(io::ErrorKind::InvalidInput,"global provider repeated original result callback")))}called=true;
   if !value.matches(inputs){return Err(Failure::Operational(io::Error::new(io::ErrorKind::InvalidInput,"global provider supplied another original source owner tuple")))}
   let actual=action(value)?;answer=Some(actual);checkpoint()?;Ok(actual)})();
  match attempt{Ok(actual)=>Ok(actual),Err(actual)=>{if first.is_none()||(!matches!(&first,Some(Failure::Operational(_)))&&matches!(&actual,Failure::Operational(_))){first=Some(actual)}Err(Failure::Operational(io::Error::other(ReadCallbackStopped)))}}
 });
 if matches!(&first,Some(Failure::Operational(_))){return Err(first.take().unwrap())}
 let returned=match returned{Err(Failure::Operational(actual))if !read_callback_proxy(&actual)=>return Err(Failure::Operational(actual)),result=>result};
 checkpoint()?;if let Some(actual)=first{return Err(actual)}let returned=returned?;
 match answer{Some(actual)if actual==returned=>Ok(actual),_=>Err(Failure::Operational(io::Error::new(io::ErrorKind::InvalidInput,"global provider omitted or replaced original checked answer")))}
}
impl GlobalAdapter<'_,'_>{
 fn question(&self,action:&mut dyn FnMut(&GlobalResult)->Result<bool,Failure>)->Result<bool,Failure>{with_global_question(self.provider,self.source.inputs(),&||self.source.checkpoint(),action)}
 fn check(&self,result:&GlobalResult)->Result<(),Failure>{if !result.matches(self.source.inputs()){return Err(Failure::Operational(io::Error::new(io::ErrorKind::InvalidInput,"reactive globals belong to another original source owner tuple")))}self.source.checkpoint()?;Ok(())}}

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
 let globals=GlobalAdapter{source:&source,provider};
 let result=reactive_reads_native::original_request(&source,Directives{facts:&facts,globals:Some(&globals)},receiver,procedure,context,matches!(flavor,Flavor::Closed),&mut poll)?;
 let frozen=FrozenReadSet::freeze(result,budget,&mut poll)?;checkpoint()?;source.require()?;Ok(ReadResult{owner:inputs.archive().original_owner_witness(),request,facts:frozen})
}


/// A borrowed child from the SAME active query graph. Current evidence/config
/// admission belongs to the endpoint, and the result must prove this exact root.
pub trait ReadProvider{fn with_read(&self,receiver:&str,procedure:&str,context:Option<&str>,flavor:Flavor,consume:&mut dyn FnMut(&ReadResult)->Result<(),Failure>)->Result<(),Failure>;}
impl<F> ReadProvider for F where F:Fn(&str,&str,Option<&str>,Flavor,&mut dyn FnMut(&ReadResult)->Result<(),Failure>)->Result<(),Failure>{fn with_read(&self,receiver:&str,procedure:&str,context:Option<&str>,flavor:Flavor,consume:&mut dyn FnMut(&ReadResult)->Result<(),Failure>)->Result<(),Failure>{self(receiver,procedure,context,flavor,consume)}}

#[derive(Debug)]struct ReadCallbackStopped;
impl std::fmt::Display for ReadCallbackStopped{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.write_str("read callback stopped")}}
impl std::error::Error for ReadCallbackStopped{}
fn read_callback_proxy(error:&io::Error)->bool{let mut cause=error.get_ref().map(|e|e as &(dyn std::error::Error+'static));while let Some(error)=cause{if error.is::<ReadCallbackStopped>(){return true}cause=error.downcast_ref::<io::Error>().and_then(io::Error::get_ref).map(|payload|payload as &(dyn std::error::Error+'static)).or_else(||error.source());}false}
pub fn with_read_facts<T>(provider:&dyn ReadProvider,inputs:&PolicyInputs,receiver:&str,procedure:&str,context:Option<&str>,flavor:Flavor,checkpoint:&dyn Fn()->io::Result<()>,consume:impl FnOnce(&FrozenReadSet)->Result<T,Failure>)->Result<T,Failure>{
 checkpoint()?;let mut action=Some(consume);let mut answer=None;let mut first=None;
 let returned=provider.with_read(receiver,procedure,context,flavor,&mut|value|{
  let attempt=(||{checkpoint()?;let Some(consume)=action.take()else{return Err(Failure::Operational(io::Error::new(io::ErrorKind::InvalidInput,"read provider repeated actual result callback")))};
   if !value.matches(inputs)||!value.matches_request(receiver,procedure,context,flavor){return Err(Failure::Operational(io::Error::new(io::ErrorKind::InvalidInput,"read provider supplied a foreign source or requested root")))}
   answer=Some(consume(value.facts())?);checkpoint()?;Ok(())})();
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
  let mut poll=||checkpoint();let facts=PolicyFacts::capture(work,&mut poll)?;
  // Auto's typed collector owns its real per-body scratch scopes. It borrows
  // the SAME root-budget source (not this temporary child budget), so no nested
  // scratch scope or alternate source/control domain is invented.
  let auto=crate::auto_tracking_native::NativeCandidates::capture(&source,&facts,globals_provider)?;
  let owned=work.dependency_marker_rows()?;let count=owned.markers.len();
  let reservation=count.checked_mul(std::mem::size_of::<crate::declare_policy::Marker<'_>>()).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(64)).ok_or_else(||{scratch.deny();Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"dependency marker projection overflow"))})?;
  scratch.charge(reservation).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;
  let mut markers=Vec::new();markers.try_reserve_exact(count).map_err(|actual|{scratch.deny();Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,actual))})?;
  if markers.capacity().checked_mul(std::mem::size_of::<crate::declare_policy::Marker<'_>>()).is_none_or(|n|n>reservation){scratch.deny();return Err(Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"dependency marker allocator exceeds admitted projection")))}
  for row in &owned.markers{checkpoint()?;markers.push(crate::declare_policy::Marker{name:&row.name,rel:&row.rel,line:row.line,body:&row.body,args:&row.args,body_offset:row.body_offset,line_starts:row.line_starts.as_slice()});}
  let defines=work.dependency_defines()?;let globals=GlobalAdapter{source:work,provider:globals_provider};
  let folded=crate::reactive_dependency_native::analyze(work,&facts,&globals,read_provider,&markers,&defines,&auto,checkpoint)?;
  finish_dependencies(work,folded,&scratch,checkpoint)
 });
 let funded=match produced{Ok(value)=>match value.retained_charge().ok_or_else(||{budget.deny();io::Error::new(io::ErrorKind::OutOfMemory,"dependency retained capacity overflow")}).and_then(|bytes|budget.charge(bytes).map_err(|message|io::Error::new(io::ErrorKind::OutOfMemory,message))){Ok(())=>Ok(value),Err(actual)=>{drop(value);Err(Failure::Operational(actual))}},Err(actual)=>Err(actual)};
 // Moved buffers now have parent retention funding BEFORE the temporary
 // reservation can be credited. All other fold/metadata/source loans have
 // physically dropped when with_budget returned.
 if funded.is_err(){scratch.keep_failed_scratch()}drop(scratch);
 if matches!(&funded,Err(Failure::Operational(_))){return funded}checkpoint()?;
 if budget.denied(){return Err(Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"dependency aggregate admission refused")))}source.require()?;funded
}

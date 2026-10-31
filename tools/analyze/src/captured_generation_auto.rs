//! Auto generation from purpose-specific native owners, not a complete source.
//! The host must authenticate its requested names, native Q/Db/current recorder,
//! actual fixed configuration read and exhausted CODE/CLI-test original scopes.
//! This returns only staged output DATA; no receipt, cache or installer exists.
use crate::{captured_generator_budget::Budget,captured_reactive_reads::Failure,reactive_global_source::Source};use std::{io,path::Path,sync::Arc,collections::{BTreeSet,HashMap}};
fn oom(b:&Budget,message:impl Into<String>)->Failure{b.deny();Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message.into()))}
struct Scratch{budget:Arc<Budget>,complete:bool}impl Drop for Scratch{fn drop(&mut self){if !self.complete{self.budget.keep_failed_scratch()}}}
pub fn generate_from_questions(questions:&dm_tree::frontend::GenerationNativeQuestions,root:&Path,pages:&dyn crate::reactive_raw_policy_pages::RawPolicyPages,order:&HashMap<String,usize>,configuration:&crate::captured_raw_file::Config,tests:&BTreeSet<String>,budget:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<crate::sparse_slots_policy::Output,Failure>{
 let mut scratch=Scratch{budget:Budget::scoped_temporaries(budget).map_err(|m|oom(budget,m))?,complete:false};
 let produced=(||{
  let source=crate::generation_reactive_source::GenerationSource::new(questions,pages,root,order,&scratch.budget,budget,poll)?;let mut checkpoint=||poll();
  let facts=crate::reactive_policy_facts_native::PolicyFacts::capture_from(&source,&mut checkpoint)?;let globals=crate::reactive_global_facts_native::NativeGlobals::build_from(&source,||poll())?;
  let auto=crate::auto_tracking_native::NativeCandidates::capture_original(&source,&facts,&globals)?;
  let owned=source.dependency_marker_rows(&mut checkpoint)?;let count=owned.markers.len();let bytes=count.checked_mul(std::mem::size_of::<crate::declare_policy::Marker<'_>>()).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(64)).ok_or_else(||oom(&scratch.budget,"generation Auto marker projection overflow"))?;source.reserve(Some(bytes))?;let mut markers=Vec::new();markers.try_reserve_exact(count).map_err(|e|oom(&scratch.budget,e.to_string()))?;if markers.capacity().checked_mul(std::mem::size_of::<crate::declare_policy::Marker<'_>>()).is_none_or(|n|n>bytes){return Err(oom(&scratch.budget,"generation Auto marker capacity exceeds admission"))}for row in &owned.markers{source.require()?;markers.push(crate::declare_policy::Marker{name:&row.name,rel:&row.rel,line:row.line,body:&row.body,args:&row.args,body_offset:row.body_offset,line_starts:&row.line_starts});}
  let defines=source.dependency_defines()?;let reads=crate::reactive_dependency_native::ReadQuestions::Generation{source:&source,facts:&facts,globals:&globals};let dependencies=crate::reactive_dependency_native::analyze_questions(&source,&facts,&globals,&reads,&markers,&defines,&auto,poll)?;
  let set=configuration.with_auto_tracked_lists(|includes,excludes|crate::captured_reactive_reads::auto_decisions_rows(&source,dependencies.candidates.iter().map(|(owner,name)|(owner.as_str(),name.as_str())),includes,excludes,poll))?;source.require()?;
  // Same existing renderer/templates. All temporary originals/facts/flow work
  // are still live while output is parent funded. None can escape this scope.
  crate::auto_tracking_emitter::generate_admitted(&set,tests,budget,poll).map_err(Failure::Operational)
 })();
 if matches!(&produced,Err(Failure::Operational(_))){return produced}if scratch.budget.denied(){return Err(oom(&scratch.budget,"generation Auto policy admission refused"))}poll()?;scratch.budget.require().map_err(|m|oom(&scratch.budget,m))?;if produced.is_ok(){scratch.complete=true}drop(scratch);produced
}

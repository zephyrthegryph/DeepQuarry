//! Purpose-specific generation from the SAME native parsed/question owners.
//! Only staged DATA escapes; the private host separately owns actual source,
//! current recorder, CODE/CLI EOF, requested names and retirement/freshness.
use crate::{captured_generator_budget::Budget,captured_reactive_reads::Failure,reactive_global_source::Source};
use std::{collections::{BTreeSet,HashMap},io,path::Path,sync::Arc};
#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub enum Generator{Deps,AutoTracked,Reads,DerivedReads,Plans}
pub enum Generated{Single(crate::sparse_slots_policy::Output),Derived(String)}
struct Scratch{budget:Arc<Budget>,complete:bool}impl Drop for Scratch{fn drop(&mut self){if !self.complete{self.budget.keep_failed_scratch()}}}
fn oom(b:&Budget,message:impl Into<String>)->Failure{b.deny();Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message.into()))}
fn fund_output(mut captured:crate::sparse_slots_policy::Output,budget:&Arc<Budget>)->Result<crate::sparse_slots_policy::Output,Failure>{let mut output=crate::sparse_slots_policy::Output::default();output.body=std::mem::take(&mut captured.body);output.diags=std::mem::take(&mut captured.diags);drop(captured);let bytes=output.body.capacity().checked_add(output.diags.capacity().checked_mul(std::mem::size_of::<crate::sparse_slots_policy::Diagnostic>()).ok_or_else(||oom(budget,"generation diagnostic capacity overflow"))?).and_then(|n|output.diags.iter().try_fold(n,|n,d|n.checked_add(d.rel.capacity())?.checked_add(d.msg.capacity()))).ok_or_else(||oom(budget,"generation retained output capacity overflow"))?;budget.charge(bytes).map_err(|m|oom(budget,m))?;Ok(output)}
/// ONE original reader/context for the selected phase. Every policy/fact value
/// drops before successful scratch release. The caller must stage output under
/// the loan; neither source references nor an operation Budget may be cached.
pub fn with_generators(questions:&dm_tree::frontend::GenerationNativeQuestions,root:&Path,pages:&dyn crate::reactive_raw_policy_pages::RawPolicyPages,order:&HashMap<String,usize>,configuration:Option<&crate::captured_raw_file::Config>,tests:&BTreeSet<String>,generators:&[Generator],budget:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>,consume:&mut dyn FnMut(Generator,Generated)->Result<(),Failure>)->Result<(),Failure>{
 if generators.is_empty()||generators.len()>5{return Err("generation question role set is empty or oversized".into())}for(i,name)in generators.iter().enumerate(){if generators[..i].contains(name){return Err("generation question role repeats".into())}}if generators.contains(&Generator::AutoTracked)&&configuration.is_none(){return Err("Auto requires its genuine current recorded configuration".into())}
 let mut scratch=Scratch{budget:Budget::scoped_temporaries(budget).map_err(|m|oom(budget,m))?,complete:false};
 let produced=(||{
  let source=crate::generation_reactive_source::GenerationSource::new(questions,pages,root,order,&scratch.budget,budget,poll)?;
  let needs_policy=generators.iter().any(|name|*name!=Generator::DerivedReads);let needs_dependencies=generators.iter().any(|name|matches!(name,Generator::Deps|Generator::AutoTracked|Generator::Plans));let mut checkpoint=||poll();
  // Unique canonical producer once per actual selected operation. Derived's
  // historical raw policy needs neither these facts nor any body demand.
  let facts=if needs_policy{Some(crate::reactive_policy_facts_native::PolicyFacts::capture_from(&source,&mut checkpoint)?)}else{None};
  let globals=if needs_policy{Some(crate::reactive_global_facts_native::NativeGlobals::build_from(&source,||poll())?)}else{None};
  let auto=if needs_dependencies{Some(crate::auto_tracking_native::NativeCandidates::capture_original(&source,facts.as_ref().ok_or("generation facts omitted")?,globals.as_ref().ok_or("generation globals omitted")?)?)}else{None};
  let owned=if needs_policy{Some(source.dependency_marker_rows(&mut checkpoint)?)}else{None};let mut markers=Vec::new();if let Some(owned)=&owned{let count=owned.markers.len();let bytes=count.checked_mul(std::mem::size_of::<crate::declare_policy::Marker<'_>>()).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(64)).ok_or_else(||oom(&scratch.budget,"generation marker projection overflow"))?;source.reserve(Some(bytes))?;markers.try_reserve_exact(count).map_err(|e|oom(&scratch.budget,e.to_string()))?;if markers.capacity().checked_mul(std::mem::size_of::<crate::declare_policy::Marker<'_>>()).is_none_or(|n|n>bytes){return Err(oom(&scratch.budget,"generation marker capacity exceeds admission"))}for row in &owned.markers{source.require()?;markers.push(crate::declare_policy::Marker{name:&row.name,rel:&row.rel,line:row.line,body:&row.body,args:&row.args,body_offset:row.body_offset,line_starts:&row.line_starts});}}
  let defines=if needs_policy{Some(source.dependency_defines()?)}else{None};
  let reads=if needs_policy{Some(crate::reactive_dependency_native::ReadQuestions::Generation{source:&source,facts:facts.as_ref().ok_or("generation facts omitted")?,globals:globals.as_ref().ok_or("generation globals omitted")?})}else{None};
  let dependencies=if needs_dependencies{Some(crate::reactive_dependency_native::analyze_questions(&source,facts.as_ref().ok_or("generation facts omitted")?,globals.as_ref().ok_or("generation globals omitted")?,reads.as_ref().ok_or("generation read questions omitted")?,&markers,defines.as_ref().ok_or("generation defines omitted")?,auto.as_ref().ok_or("generation candidates omitted")?,poll)?)}else{None};
  for name in generators{source.require()?;let generated=match name{
   Generator::Deps=>Generated::Single(crate::deps_policy::generate_view_admitted(crate::reactive_dependency_view::Analysis::Owned(dependencies.as_ref().ok_or("generation dependencies omitted")?),budget,poll).map_err(Failure::Operational)?),
   Generator::AutoTracked=>{let configuration=configuration.ok_or("generation Auto configuration omitted")?;let dependencies=dependencies.as_ref().ok_or("generation dependencies omitted")?;let set=configuration.with_auto_tracked_lists(|includes,excludes|crate::captured_reactive_reads::auto_decisions_rows(&source,dependencies.candidates.iter().map(|(owner,name)|(owner.as_str(),name.as_str())),includes,excludes,poll))?;Generated::Single(crate::auto_tracking_emitter::generate_admitted(&set,tests,budget,poll).map_err(Failure::Operational)?)},
   Generator::Reads=>{let captured=crate::reactive_reads_generator_native::generate_with_questions(&source,facts.as_ref().ok_or("generation facts omitted")?,reads.as_ref().ok_or("generation read questions omitted")?,&markers,defines.as_ref().ok_or("generation defines omitted")?,tests)?;Generated::Single(fund_output(captured,budget)?)},
   Generator::DerivedReads=>{let text=crate::reactive_derived_generator_native::generate(&source,tests)?;budget.charge(text.capacity()).map_err(|m|oom(budget,m))?;Generated::Derived(text)},
   Generator::Plans=>{let captured=crate::reactive_plans_generator_native::generate(&source,crate::reactive_dependency_view::Analysis::Owned(dependencies.as_ref().ok_or("generation dependencies omitted")?))?;Generated::Single(fund_output(captured,budget)?)},
  };source.require()?;consume(*name,generated)?;source.require()?;
  }Ok(())
 })();
 if matches!(&produced,Err(Failure::Operational(_))){return produced}if scratch.budget.denied(){return Err(oom(&scratch.budget,"generation question admission refused"))}poll()?;scratch.budget.require().map_err(|m|oom(&scratch.budget,m))?;if produced.is_ok(){scratch.complete=true}drop(scratch);produced
}

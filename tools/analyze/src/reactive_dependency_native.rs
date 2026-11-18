//! Native adapters for SAME shared variable/gap judgement. No parser/model.
use crate::{reactive_original_source::ReadSource,reactive_global_source::{Source as OriginalSource,SelectedCallable},reactive_policy_facts_native::PolicyFacts,reactive_reads_native::{Failure,GlobalFacts},reactive_variable_policy::{self,VarClass},reactive_dependency_policy::{self,View},key_policy_control as kc,reactive_read_result::FrozenReadSet,reactive_facts::Untracked};
use std::io;
struct Native<'a>{source:&'a dyn OriginalSource,facts:&'a PolicyFacts,globals:&'a dyn GlobalFacts,poll:&'a dyn Fn()->io::Result<()>}
impl kc::Control for Native<'_>{
 type Error=Failure;const CHECKED:bool=true;
 fn checkpoint(&mut self)->Result<(),Failure>{(self.poll)()?;self.source.require()?;Ok(())}
 fn reserve(&mut self,bytes:usize)->Result<(),Failure>{self.source.budget().charge(bytes).map_err(|actual|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,actual)))}
 fn overflow(&mut self)->Failure{self.source.budget().deny();Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"native dependency policy capacity overflow"))}
 fn allocation_failed(&mut self)->Failure{self.source.budget().deny();Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"native dependency policy capacity refused"))}
}
impl reactive_variable_policy::Source for Native<'_>{
 type Error=Failure;
 fn checkpoint(&mut self)->Result<(),Failure>{kc::Control::checkpoint(self)}
 fn tracked(&mut self,o:&str,n:&str)->Result<bool,Failure>{self.facts.is_tracked(self.source,o,n)}
 fn relation(&mut self,o:&str,n:&str)->Result<bool,Failure>{self.facts.is_relation(self.source,o,n)}
 fn stat(&mut self,o:&str,n:&str)->Result<bool,Failure>{self.facts.is_stat(self.source,o,n)}
 fn derived(&mut self,o:&str,n:&str)->Result<bool,Failure>{self.facts.is_derived(self.source,o,n)}
 fn published_builtin(&mut self,o:&str,n:&str)->Result<bool,Failure>{
  Ok((matches!(n,"loc"|"turf"|"area")&&self.source.is_subtype(o,"/atom")?)||(matches!(n,"ckey"|"client"|"key")&&self.source.is_subtype(o,"/mob")?))
 }
 fn flyweight(&mut self,o:&str)->Result<bool,Failure>{for ty in crate::raw_ownership_policy::FLYWEIGHT_TYPES{if self.source.is_subtype(o,ty)?{return Ok(true)}}Ok(false)}
 fn written(&mut self,o:&str,n:&str)->Result<bool,Failure>{self.globals.is_written_on(self.source,o,n)}
 fn constant(&mut self,o:&str,n:&str)->Result<bool,Failure>{Ok(self.source.variable(o,n)?.is_some_and(|value|value.is_const))}
}
impl reactive_dependency_policy::Source for Native<'_>{
 fn classify(&mut self,o:&str,n:&str)->Result<VarClass,Failure>{reactive_variable_policy::classify(self,o,n)}
 fn generated_setter(&mut self,callee:&str)->Result<bool,Failure>{
  let Some((owner,name))=callee.rsplit_once("::")else{return Ok(false)};if !name.starts_with("set_"){return Ok(false)}
  match self.source.callable(owner,name)?{SelectedCallable::Source(call)=>Ok(self.source.site_line(call.ordinal,1)?.0=="code/engine/_generated/auto_tracked.dm"),SelectedCallable::Builtin|SelectedCallable::Missing=>Ok(false)}
 }
}
pub(crate) fn untracked(source:&dyn OriginalSource,facts:&PolicyFacts,globals:&dyn GlobalFacts,reads:&FrozenReadSet,output:bool,poll:&dyn Fn()->io::Result<()>)->Result<Vec<Untracked>,Failure>{
 let mut control=Native{source,facts,globals,poll};reactive_dependency_policy::untracked_of(View::Frozen(reads),&mut control,output)
}

/// Separate data-only full-page reads from existing finite verified results.
/// A host full-result wrapper supplies current raw proof before either loan.
pub(crate) enum ReadQuestions<'a>{Captured(&'a dyn crate::captured_reactive_reads::ReadProvider),RawData(&'a dyn crate::captured_reactive_reads::RawPolicyReadProvider),Generation{source:&'a dyn OriginalSource,facts:&'a PolicyFacts,globals:&'a dyn GlobalFacts},Utility{source:&'a dyn OriginalSource,facts:&'a PolicyFacts,globals:&'a dyn GlobalFacts,closed:bool}}
impl ReadQuestions<'_>{pub(crate) fn with_facts<T>(&self,inputs:&dm_analysis::policy_inputs::PolicyInputs,receiver:&str,procedure:&str,context:Option<&str>,flavor:crate::captured_reactive_reads::Flavor,poll:&dyn Fn()->io::Result<()>,consume:impl FnOnce(&FrozenReadSet)->Result<T,Failure>)->Result<T,Failure>{match self{Self::Captured(provider)=>crate::captured_reactive_reads::with_read_facts(*provider,inputs,receiver,procedure,context,flavor,poll,consume),Self::RawData(provider)=>crate::captured_reactive_reads::with_raw_read_facts(*provider,inputs,receiver,procedure,context,flavor,poll,consume),Self::Generation{..}|Self::Utility{..}=>Err(Failure::Operational(io::Error::new(io::ErrorKind::InvalidInput,"generation read data requires its actual purpose source loan")))}}}

impl ReadQuestions<'_>{
 pub(crate) fn with_source_facts<T>(&self,current:&dyn OriginalSource,receiver:&str,procedure:&str,context:Option<&str>,flavor:crate::captured_reactive_reads::Flavor,poll:&dyn Fn()->io::Result<()>,consume:impl FnOnce(&FrozenReadSet)->Result<T,Failure>)->Result<T,Failure>{
  if let Self::Generation{source,facts,globals}|Self::Utility{source,facts,globals,..}=self{
   let closed=match self{Self::Utility{closed,..}=>{if !current.utility_body_contract(){return Err(Failure::Operational(io::Error::new(io::ErrorKind::InvalidInput,"closure utility requires its actual optional BODY contract")))}*closed},_=>flavor==crate::captured_reactive_reads::Flavor::Closed};
   current.require()?;if !std::ptr::eq((*source as *const dyn OriginalSource).cast::<()>(),(current as *const dyn OriginalSource).cast::<()>()){return Err(Failure::Operational(io::Error::new(io::ErrorKind::InvalidInput,"generation read source differs from actual operation owner")))}
   let scratch=crate::captured_generator_budget::Budget::scoped_temporaries(current.operation_budget()).map_err(|m|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,m)))?;let mut action=Some(consume);let mut completed=None;
   let pending=current.with_budget(&scratch,&mut|page|{let mut checkpoint=||poll();let reads=crate::reactive_reads_native::original_request(page,crate::reactive_reads_native::Directives{facts,globals:Some(*globals)},receiver,procedure,context,closed,&mut checkpoint)?;let frozen=FrozenReadSet::freeze(reads,&scratch,&mut checkpoint)?;let consume=action.take().ok_or_else(||Failure::Operational(io::Error::new(io::ErrorKind::InvalidData,"generation read callback repeated")))?;completed=Some(consume(&frozen)?);drop(frozen);Ok(())});
   if pending.is_err(){scratch.keep_failed_scratch()}drop(scratch);let pending=match pending{Err(Failure::Operational(actual))=>return Err(Failure::Operational(actual)),other=>other};current.require()?;pending?;return completed.ok_or_else(||Failure::Operational(io::Error::new(io::ErrorKind::InvalidData,"generation read callback omitted")))
  }
  let inputs=current.complete_inputs().ok_or_else(||Failure::Operational(io::Error::new(io::ErrorKind::InvalidInput,"ordinary read provider cannot serve generation-only source questions")))?;self.with_facts(inputs,receiver,procedure,context,flavor,poll,consume)
 }
}

/// Ordered closed-root dependency aggregation. Marker discovery and every child
/// result remain source-bound; auto inference/reaction additions are mandatory
/// later inputs to completion, not empty fallback implementations here.
pub(crate) fn fold_read_roots(source:&dyn OriginalSource,facts:&PolicyFacts,globals:&dyn GlobalFacts,provider:&ReadQuestions<'_>,markers:&[crate::declare_policy::Marker<'_>],defines:&std::collections::BTreeSet<String>,poll:&dyn Fn()->io::Result<()>)->Result<crate::reactive_dependency_fold::Fold,Failure>{
 use crate::{reactive_dependency_fold::Fold,reactive_hooks_policy::{self as hooks,Role},captured_reactive_reads::{with_read_facts,Flavor},reactive_read_facts::ReadKind};use std::collections::BTreeSet;
 let closed=!matches!(provider,ReadQuestions::Utility{closed:false,..});
 let utility=matches!(provider,ReadQuestions::Utility{..});
 let mut control=Native{source,facts,globals,poll};kc::Control::checkpoint(&mut control)?;
 let handlers=hooks::discover_admitted(markers,&mut control)?;let extra=hooks::discover_in_admitted(markers,&["CAP_ENTRIES"],&mut control)?;let mut out=Fold::default();
 for h in handlers{kc::Control::checkpoint(&mut control)?;if !h.role.reads_covered()||h.cap_proc||h.owner.is_empty(){continue}let SelectedCallable::Source(call)=source.callable(&h.owner,&h.proc)? else{continue};
  if utility{
   // The pinned handler catalog first requires an actual code-bearing closed
   // handler even for the legacy comparison. Genuine Rejected yields no body
   // callback; unissued/operational input still fails through the same borrower.
   let mut code=false;source.with_body(call.ordinal,&mut|_|{code=true;Ok(())})?;
   if !code{continue}
  }
  let id=kc::format(&mut control,format_args!("{}::{}",h.owner,h.proc))?;let first=!out.analysis.consumers.contains_key(&id);if !first&&(!closed||h.role!=Role::Contribution){continue}
  provider.with_source_facts(source,&h.owner,&h.proc,Some(h.ctx.type_path()),Flavor::Closed,poll,|read|{
   if closed&&h.role==Role::Contribution{out.sample(&id,View::Frozen(read),&mut control)?;}if first{let gaps=untracked(source,facts,globals,read,h.role==Role::Output,poll)?;out.consumer(&id,View::Frozen(read),gaps,matches!(h.role,Role::Contribution|Role::Condition),false,&mut control)?;}Ok(())
  })?;
 }
 for h in extra{kc::Control::checkpoint(&mut control)?;if !h.role.reads_covered()||h.cap_proc||h.owner.is_empty(){continue}let id=kc::format(&mut control,format_args!("{}::{}",h.owner,h.proc))?;if out.analysis.consumers.contains_key(&id)||matches!(source.callable(&h.owner,&h.proc)?,SelectedCallable::Missing){continue}
  provider.with_source_facts(source,&h.owner,&h.proc,Some(h.ctx.type_path()),Flavor::Closed,poll,|read|{let gaps=untracked(source,facts,globals,read,h.role==Role::Output,poll)?;out.consumer(&id,View::Frozen(read),gaps,matches!(h.role,Role::Contribution|Role::Condition),false,&mut control)})?;
 }
 for marker in markers.iter().filter(|m|m.name=="STAT"){let Some(owner)=marker.args.first()else{continue};for arg in marker.args{kc::Control::checkpoint(&mut control)?;source.reserve(arg.len().checked_add(64))?;let compact=arg.replace(' ',"");let Some(name)=compact.strip_prefix("formula=PROC_REF(").and_then(|r|r.strip_suffix(')'))else{continue};if matches!(source.callable(owner,name)?,SelectedCallable::Missing){continue}let id=kc::format(&mut control,format_args!("{}::{}",owner,name))?;
  provider.with_source_facts(source,owner,name,Some("/datum/act/eval"),Flavor::Closed,poll,|read|{let gaps=untracked(source,facts,globals,read,false,poll)?;out.sample(&id,View::Frozen(read),&mut control)?;out.consumer(&id,View::Frozen(read),gaps,true,true,&mut control)})?;
 }}
 // The old proc_defs order is (relative file, display header, owner, name), not
 // declaration iteration order. Keep every genuine version until this sort.
 struct Definition<'a>{relative:String,line:usize,owner:&'a str,name:&'a str}
 let mut definitions=Vec::new();source.visit_callables(Some(&["draw","hidden_verbs","granted_verbs","ui_data","tgui_data"]),&mut||poll().map_err(Failure::from),&mut|call|{
  crate::reactive_dependency_fold::row(&mut control,&mut definitions)?;let(relative,_)=source.site_line(call.ordinal,1)?;definitions.push(Definition{relative,line:call.header,owner:call.owner,name:call.name});Ok::<(),Failure>(())
 })?;
 definitions.sort_by(|a,b|(&a.relative,a.line,a.owner,a.name).cmp(&(&b.relative,b.line,b.owner,b.name)));definitions.dedup_by(|a,b|a.relative==b.relative&&a.line==b.line&&a.owner==b.owner&&a.name==b.name);
 let mut capability_keys=BTreeSet::new();for key in facts.annotations.capkey_accessors.values(){kc::Control::checkpoint(&mut control)?;kc::reserve(&mut control,||key.len().checked_add(320))?;capability_keys.insert(key.clone());}
 let mut seen=BTreeSet::new();
 for phase in 0..3{for definition in &definitions{kc::Control::checkpoint(&mut control)?;let(owner,name)=(definition.owner,definition.name);
  if (phase==0&&name!="draw")||(phase==1&&!matches!(name,"hidden_verbs"|"granted_verbs"))||(phase==2&&!matches!(name,"ui_data"|"tgui_data")){continue}if owner=="/"{continue}
  let output=matches!(name,"draw"|"hidden_verbs"|"granted_verbs");if output&&hooks::OPAQUE_DIRS.iter().any(|prefix|definition.relative.starts_with(prefix)){continue}
  if !output&&(owner=="/datum"||definition.relative.starts_with("code/engine/")){continue}
  let id=kc::format(&mut control,format_args!("{owner}::{name}"))?;kc::reserve(&mut control,||id.len().checked_add(320))?;if !seen.insert(id.clone()){continue}
  provider.with_source_facts(source,owner,name,if output{None}else{Some("/datum/act/eval")},Flavor::Closed,poll,|read|{
   if name=="draw"{let gaps=untracked(source,facts,globals,read,true,poll)?;out.draw(owner,&id,View::Frozen(read),gaps,&capability_keys,&mut|c,name|crate::reactive_read_key_policy::canonical(c,&ReadKind::Accessor,name,&capability_keys,defines),&mut control)}
   else if output{let gaps=untracked(source,facts,globals,read,true,poll)?;out.verbs(&id,View::Frozen(read),&gaps,&mut control)}else{out.ui(View::Frozen(read),&mut control)}
  })?;
 }
 }
 kc::Control::checkpoint(&mut control)?;Ok(out)
}

pub(crate) fn fold_marker_leaves(source:&dyn OriginalSource,facts:&PolicyFacts,globals:&dyn GlobalFacts,markers:&[crate::declare_policy::Marker<'_>],fold:&mut crate::reactive_dependency_fold::Fold,poll:&dyn Fn()->io::Result<()>)->Result<std::collections::BTreeSet<(String,String)>,Failure>{
 use std::collections::BTreeSet;let mut named=BTreeSet::new();let mut control=Native{source,facts,globals,poll};
 for marker in markers.iter().filter(|m|m.name=="CAPABILITIES"){
  kc::Control::checkpoint(&mut control)?;
  if let Some(owner)=marker.args.first().filter(|owner|owner.starts_with('/')){
   for name in crate::raw_marker_policy::marker_named_vars_admitted(marker.body,&mut control)?{if let Some(declaring)=source.declaring_owner(owner,&name)?{kc::reserve(&mut control,||Some(256))?;fold.analysis.reads.insert((kc::own(&mut control,declaring)?,name));}}
   for name in crate::reactive_dependency_marker_policy::marker_driven_vars(marker,&mut control)?{if let Some(declaring)=source.declaring_owner(owner,&name)?{kc::reserve(&mut control,||Some(256))?;named.insert((kc::own(&mut control,declaring)?,name));}}
  }
  for leaf in crate::reactive_dependency_marker_policy::marker_leaves(marker,&mut control)?{
   if let Some(declaring)=source.declaring_owner(&leaf.owner,&leaf.var)?{kc::reserve(&mut control,||Some(256))?;fold.analysis.reads.insert((kc::own(&mut control,declaring)?,kc::own(&mut control,&leaf.var)?));}
   if reactive_variable_policy::classify(&mut control,&leaf.owner,&leaf.var)?==VarClass::Unknown{crate::reactive_dependency_fold::row(&mut control,&mut fold.analysis.leaves)?;fold.analysis.leaves.push(leaf);}
  }
 }
 fold.analysis.leaves.sort();fold.analysis.leaves.dedup();kc::Control::checkpoint(&mut control)?;Ok(named)
}

/// Complete dependency data fold over original read answers and narrow raw
/// reaction policy. Auto inference is required and supplied by the same caller;
/// absence is never interpreted as an empty candidate set.
pub(crate) fn analyze<A:crate::reactive_dependency_fold::Candidates<Error=Failure>>(source:&dyn OriginalSource,facts:&PolicyFacts,globals:&dyn GlobalFacts,provider:&dyn crate::captured_reactive_reads::ReadProvider,markers:&[crate::declare_policy::Marker<'_>],defines:&std::collections::BTreeSet<String>,auto:&A,poll:&dyn Fn()->io::Result<()>)->Result<crate::reactive_facts::DepsAnalysis,Failure>{
 analyze_questions(source,facts,globals,&ReadQuestions::Captured(provider),markers,defines,auto,poll)
}

pub(crate) fn analyze_questions<A:crate::reactive_dependency_fold::Candidates<Error=Failure>>(source:&dyn OriginalSource,facts:&PolicyFacts,globals:&dyn GlobalFacts,provider:&ReadQuestions<'_>,markers:&[crate::declare_policy::Marker<'_>],defines:&std::collections::BTreeSet<String>,auto:&A,poll:&dyn Fn()->io::Result<()>)->Result<crate::reactive_facts::DepsAnalysis,Failure>{
 let reactions=crate::reactive_reaction_native::reaction_pairs(source)?;
 let mut fold=fold_read_roots(source,facts,globals,provider,markers,defines,poll)?;
 let mut control=Native{source,facts,globals,poll};
 for(owner,name)in reactions{kc::Control::checkpoint(&mut control)?;if let Some(declaring)=source.declaring_owner(&owner,&name)?{kc::reserve(&mut control,||Some(256))?;fold.analysis.reads.insert((kc::own(&mut control,declaring)?,name));}}
 let named=fold_marker_leaves(source,facts,globals,markers,&mut fold,poll)?;
 fold.finish(&named,auto,&mut control)
}

impl crate::reactive_dependency_fold::Candidates for crate::auto_tracking_native::NativeCandidates<'_,'_>{
 type Error=Failure;
 fn candidate(&self,owner:&str,name:&str)->Result<bool,Failure>{crate::auto_tracking_native::NativeCandidates::candidate(self,owner,name)}
 fn named_candidate(&self,owner:&str,name:&str)->Result<bool,Failure>{crate::auto_tracking_native::NativeCandidates::named_candidate(self,owner,name)}
 fn called_candidates(&self)->Result<crate::reactive_dependency_fold::CalledCandidates<'_>,Failure>{Ok(crate::reactive_dependency_fold::CalledCandidates::Tree(crate::auto_tracking_native::NativeCandidates::called_candidates(self)))}
}

/// SAME original variable classification for the semantic-read consumer.
pub(crate) fn classify_original(source:&dyn OriginalSource,facts:&PolicyFacts,globals:&dyn GlobalFacts,owner:&str,name:&str,poll:&dyn Fn()->io::Result<()>)->Result<VarClass,Failure>{source.budget().require().map_err(|m|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,m)))?;let pending=reactive_variable_policy::classify(&mut Native{source,facts,globals,poll},owner,name);if matches!(&pending,Err(Failure::Operational(_))){return pending}if source.budget().denied(){return Err(Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"semantic-read classification admission denied")))}pending}

/// Both closure answers are operation-owned DATA over the SAME current model,
/// facts, globals and actual utility BODY borrower. This path never publishes a
/// targeted answer into the ordinary closed dependency memo.
pub(crate) fn analyze_utility_pair<A:crate::reactive_dependency_fold::Candidates<Error=Failure>>(
 source:&dyn OriginalSource,facts:&PolicyFacts,globals:&dyn GlobalFacts,
 markers:&[crate::declare_policy::Marker<'_>],defines:&std::collections::BTreeSet<String>,auto:&A,
 poll:&dyn Fn()->io::Result<()>,consume:impl FnOnce(&crate::reactive_facts::DepsAnalysis,&crate::reactive_facts::DepsAnalysis)->Result<(),Failure>
)->Result<(),Failure>{
 source.require()?;poll()?;
 if !source.utility_body_contract()||source.complete_inputs().is_none(){return Err(Failure::Operational(io::Error::new(io::ErrorKind::InvalidInput,"closure utility lacks its actual complete model/BODY owner")))}
 let targeted=analyze_questions(source,facts,globals,&ReadQuestions::Utility{source,facts,globals,closed:false},markers,defines,auto,poll)?;
 source.require()?;poll()?;
 let closed=analyze_questions(source,facts,globals,&ReadQuestions::Utility{source,facts,globals,closed:true},markers,defines,auto,poll)?;
 source.require()?;poll()?;
 let pending=consume(&targeted,&closed);
 // Preserve actual operational IO before later currentness/cancellation checks.
 if matches!(&pending,Err(Failure::Operational(_))){return pending}
 source.require()?;poll()?;pending
}

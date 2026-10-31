//! Native adapters for SAME shared variable/gap judgement. No parser/model.
use crate::{reactive_original_source::{ReadSource,SelectedCallable},reactive_policy_facts_native::PolicyFacts,reactive_reads_native::{Failure,GlobalFacts},reactive_variable_policy::{self,VarClass},reactive_dependency_policy::{self,View},key_policy_control as kc,reactive_read_result::FrozenReadSet,reactive_facts::Untracked};
use std::io;
struct Native<'a,'source>{source:&'a ReadSource<'source>,facts:&'a PolicyFacts,globals:&'a dyn GlobalFacts,poll:&'a dyn Fn()->io::Result<()>}
impl kc::Control for Native<'_,'_>{
 type Error=Failure;const CHECKED:bool=true;
 fn checkpoint(&mut self)->Result<(),Failure>{(self.poll)()?;self.source.require()?;Ok(())}
 fn reserve(&mut self,bytes:usize)->Result<(),Failure>{self.source.budget().charge(bytes).map_err(|actual|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,actual)))}
 fn overflow(&mut self)->Failure{self.source.budget().deny();Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"native dependency policy capacity overflow"))}
 fn allocation_failed(&mut self)->Failure{self.source.budget().deny();Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"native dependency policy capacity refused"))}
}
impl reactive_variable_policy::Source for Native<'_,'_>{
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
impl reactive_dependency_policy::Source for Native<'_,'_>{
 fn classify(&mut self,o:&str,n:&str)->Result<VarClass,Failure>{reactive_variable_policy::classify(self,o,n)}
 fn generated_setter(&mut self,callee:&str)->Result<bool,Failure>{
  let Some((owner,name))=callee.rsplit_once("::")else{return Ok(false)};if !name.starts_with("set_"){return Ok(false)}
  match self.source.callable(owner,name)?{SelectedCallable::Source(call)=>Ok(self.source.site_line(call.ordinal,1)?.0=="code/engine/_generated/auto_tracked.dm"),SelectedCallable::Builtin|SelectedCallable::Missing=>Ok(false)}
 }
}
pub(crate) fn untracked(source:&ReadSource<'_>,facts:&PolicyFacts,globals:&dyn GlobalFacts,reads:&FrozenReadSet,output:bool,poll:&dyn Fn()->io::Result<()>)->Result<Vec<Untracked>,Failure>{
 let mut control=Native{source,facts,globals,poll};reactive_dependency_policy::untracked_of(View::Frozen(reads),&mut control,output)
}

/// Separate data-only full-page reads from existing finite verified results.
/// A host full-result wrapper supplies current raw proof before either loan.
pub(crate) enum ReadQuestions<'a>{Captured(&'a dyn crate::captured_reactive_reads::ReadProvider),RawData(&'a dyn crate::captured_reactive_reads::RawPolicyReadProvider)}
impl ReadQuestions<'_>{pub(crate) fn with_facts<T>(&self,inputs:&dm_analysis::policy_inputs::PolicyInputs,receiver:&str,procedure:&str,context:Option<&str>,flavor:crate::captured_reactive_reads::Flavor,poll:&dyn Fn()->io::Result<()>,consume:impl FnOnce(&FrozenReadSet)->Result<T,Failure>)->Result<T,Failure>{match self{Self::Captured(provider)=>crate::captured_reactive_reads::with_read_facts(*provider,inputs,receiver,procedure,context,flavor,poll,consume),Self::RawData(provider)=>crate::captured_reactive_reads::with_raw_read_facts(*provider,inputs,receiver,procedure,context,flavor,poll,consume)}}}

/// Ordered closed-root dependency aggregation. Marker discovery and every child
/// result remain source-bound; auto inference/reaction additions are mandatory
/// later inputs to completion, not empty fallback implementations here.
pub(crate) fn fold_read_roots(source:&ReadSource<'_>,facts:&PolicyFacts,globals:&dyn GlobalFacts,provider:&ReadQuestions<'_>,markers:&[crate::declare_policy::Marker<'_>],defines:&std::collections::BTreeSet<String>,poll:&dyn Fn()->io::Result<()>)->Result<crate::reactive_dependency_fold::Fold,Failure>{
 use crate::{reactive_dependency_fold::Fold,reactive_hooks_policy::{self as hooks,Role},captured_reactive_reads::{with_read_facts,Flavor},reactive_read_facts::ReadKind};use std::collections::BTreeSet;
 let mut control=Native{source,facts,globals,poll};kc::Control::checkpoint(&mut control)?;
 let handlers=hooks::discover_admitted(markers,&mut control)?;let extra=hooks::discover_in_admitted(markers,&["CAP_ENTRIES"],&mut control)?;let mut out=Fold::default();
 for h in handlers{kc::Control::checkpoint(&mut control)?;if !h.role.reads_covered()||h.cap_proc||h.owner.is_empty(){continue}if !matches!(source.callable(&h.owner,&h.proc)?,SelectedCallable::Source(_)){continue}
  let id=kc::format(&mut control,format_args!("{}::{}",h.owner,h.proc))?;let first=!out.analysis.consumers.contains_key(&id);if !first&&h.role!=Role::Contribution{continue}
  provider.with_facts(source.inputs(),&h.owner,&h.proc,Some(h.ctx.type_path()),Flavor::Closed,poll,|read|{
   if h.role==Role::Contribution{out.sample(&id,View::Frozen(read),&mut control)?;}if first{let gaps=untracked(source,facts,globals,read,h.role==Role::Output,poll)?;out.consumer(&id,View::Frozen(read),gaps,matches!(h.role,Role::Contribution|Role::Condition),false,&mut control)?;}Ok(())
  })?;
 }
 for h in extra{kc::Control::checkpoint(&mut control)?;if !h.role.reads_covered()||h.cap_proc||h.owner.is_empty(){continue}let id=kc::format(&mut control,format_args!("{}::{}",h.owner,h.proc))?;if out.analysis.consumers.contains_key(&id)||matches!(source.callable(&h.owner,&h.proc)?,SelectedCallable::Missing){continue}
  provider.with_facts(source.inputs(),&h.owner,&h.proc,Some(h.ctx.type_path()),Flavor::Closed,poll,|read|{let gaps=untracked(source,facts,globals,read,h.role==Role::Output,poll)?;out.consumer(&id,View::Frozen(read),gaps,matches!(h.role,Role::Contribution|Role::Condition),false,&mut control)})?;
 }
 for marker in markers.iter().filter(|m|m.name=="STAT"){let Some(owner)=marker.args.first()else{continue};for arg in marker.args{kc::Control::checkpoint(&mut control)?;source.reserve(arg.len().checked_add(64))?;let compact=arg.replace(' ',"");let Some(name)=compact.strip_prefix("formula=PROC_REF(").and_then(|r|r.strip_suffix(')'))else{continue};if matches!(source.callable(owner,name)?,SelectedCallable::Missing){continue}let id=kc::format(&mut control,format_args!("{}::{}",owner,name))?;
  provider.with_facts(source.inputs(),owner,name,Some("/datum/act/eval"),Flavor::Closed,poll,|read|{let gaps=untracked(source,facts,globals,read,false,poll)?;out.sample(&id,View::Frozen(read),&mut control)?;out.consumer(&id,View::Frozen(read),gaps,true,true,&mut control)})?;
 }}
 // The old proc_defs order is (relative file, display header, owner, name), not
 // declaration iteration order. Keep every genuine version until this sort.
 struct Definition<'a>{relative:String,line:usize,owner:&'a str,name:&'a str}
 let mut definitions=Vec::new();source.visit_callables(&["draw","hidden_verbs","granted_verbs","ui_data","tgui_data"],||poll().map_err(Failure::from),|call|{
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
  provider.with_facts(source.inputs(),owner,name,if output{None}else{Some("/datum/act/eval")},Flavor::Closed,poll,|read|{
   if name=="draw"{let gaps=untracked(source,facts,globals,read,true,poll)?;out.draw(owner,&id,View::Frozen(read),gaps,&capability_keys,&mut|c,name|crate::reactive_read_key_policy::canonical(c,&ReadKind::Accessor,name,&capability_keys,defines),&mut control)}
   else if output{let gaps=untracked(source,facts,globals,read,true,poll)?;out.verbs(&id,View::Frozen(read),&gaps,&mut control)}else{out.ui(View::Frozen(read),&mut control)}
  })?;
 }
 }
 kc::Control::checkpoint(&mut control)?;Ok(out)
}

pub(crate) fn fold_marker_leaves(source:&ReadSource<'_>,facts:&PolicyFacts,globals:&dyn GlobalFacts,markers:&[crate::declare_policy::Marker<'_>],fold:&mut crate::reactive_dependency_fold::Fold,poll:&dyn Fn()->io::Result<()>)->Result<std::collections::BTreeSet<(String,String)>,Failure>{
 use std::collections::BTreeSet;let mut named=BTreeSet::new();let mut control=Native{source,facts,globals,poll};
 for marker in markers.iter().filter(|m|m.name=="CAPABILITIES"){
  kc::Control::checkpoint(&mut control)?;
  if let Some(owner)=marker.args.first().filter(|owner|owner.starts_with('/')){
   for name in crate::raw_marker_policy::marker_named_vars_admitted(marker.body,&mut control)?{if let Some(declaring)=source.variable_declaring_owner(owner,&name)?{kc::reserve(&mut control,||Some(256))?;fold.analysis.reads.insert((kc::own(&mut control,declaring)?,name));}}
   for name in crate::reactive_dependency_marker_policy::marker_driven_vars(marker,&mut control)?{if let Some(declaring)=source.variable_declaring_owner(owner,&name)?{kc::reserve(&mut control,||Some(256))?;named.insert((kc::own(&mut control,declaring)?,name));}}
  }
  for leaf in crate::reactive_dependency_marker_policy::marker_leaves(marker,&mut control)?{
   if let Some(declaring)=source.variable_declaring_owner(&leaf.owner,&leaf.var)?{kc::reserve(&mut control,||Some(256))?;fold.analysis.reads.insert((kc::own(&mut control,declaring)?,kc::own(&mut control,&leaf.var)?));}
   if reactive_variable_policy::classify(&mut control,&leaf.owner,&leaf.var)?==VarClass::Unknown{crate::reactive_dependency_fold::row(&mut control,&mut fold.analysis.leaves)?;fold.analysis.leaves.push(leaf);}
  }
 }
 fold.analysis.leaves.sort();fold.analysis.leaves.dedup();kc::Control::checkpoint(&mut control)?;Ok(named)
}

/// Complete dependency data fold over original read answers and narrow raw
/// reaction policy. Auto inference is required and supplied by the same caller;
/// absence is never interpreted as an empty candidate set.
pub(crate) fn analyze<A:crate::reactive_dependency_fold::Candidates<Error=Failure>>(source:&ReadSource<'_>,facts:&PolicyFacts,globals:&dyn GlobalFacts,provider:&dyn crate::captured_reactive_reads::ReadProvider,markers:&[crate::declare_policy::Marker<'_>],defines:&std::collections::BTreeSet<String>,auto:&A,poll:&dyn Fn()->io::Result<()>)->Result<crate::reactive_facts::DepsAnalysis,Failure>{
 analyze_questions(source,facts,globals,&ReadQuestions::Captured(provider),markers,defines,auto,poll)
}

pub(crate) fn analyze_questions<A:crate::reactive_dependency_fold::Candidates<Error=Failure>>(source:&ReadSource<'_>,facts:&PolicyFacts,globals:&dyn GlobalFacts,provider:&ReadQuestions<'_>,markers:&[crate::declare_policy::Marker<'_>],defines:&std::collections::BTreeSet<String>,auto:&A,poll:&dyn Fn()->io::Result<()>)->Result<crate::reactive_facts::DepsAnalysis,Failure>{
 let reactions=crate::reactive_reaction_native::reaction_pairs(source)?;
 let mut fold=fold_read_roots(source,facts,globals,provider,markers,defines,poll)?;
 let mut control=Native{source,facts,globals,poll};
 for(owner,name)in reactions{kc::Control::checkpoint(&mut control)?;if let Some(declaring)=source.variable_declaring_owner(&owner,&name)?{kc::reserve(&mut control,||Some(256))?;fold.analysis.reads.insert((kc::own(&mut control,declaring)?,name));}}
 let named=fold_marker_leaves(source,facts,globals,markers,&mut fold,poll)?;
 fold.finish(&named,auto,&mut control)
}

impl crate::reactive_dependency_fold::Candidates for crate::auto_tracking_native::NativeCandidates<'_,'_>{
 type Error=Failure;
 fn candidate(&self,owner:&str,name:&str)->Result<bool,Failure>{crate::auto_tracking_native::NativeCandidates::candidate(self,owner,name)}
 fn named_candidate(&self,owner:&str,name:&str)->Result<bool,Failure>{crate::auto_tracking_native::NativeCandidates::named_candidate(self,owner,name)}
 fn called_candidates(&self)->Result<crate::reactive_dependency_fold::CalledCandidates<'_>,Failure>{Ok(crate::reactive_dependency_fold::CalledCandidates::Tree(crate::auto_tracking_native::NativeCandidates::called_candidates(self)))}
}

//! Full-run usage/annotation DATA fold. No source/run completion issuer lives
//! here. Native host must lend actual producer outputs under its one full-run
//! owner and consume genuine unexempt CODE_MAPS_DM EOF before publication.
use super::ConfigurationNames;
use crate::{allow_annotation_policy as policy,captured_raw_file::Config,key_policy_control::{self as kc,Control},lint::AllowUse,captured_reactive_reads::Failure,reactive_raw_policy_pages::RawPolicyPages,captured_generator_budget::Budget};
use std::io;
fn invalid(message:&str)->Failure{Failure::Operational(io::Error::new(io::ErrorKind::InvalidInput,message))}
/// Selection metadata only, NEVER evidence that these producers executed.
#[derive(Debug)]pub struct FullSelectionData{names:Vec<String>}
impl FullSelectionData{pub fn names(&self)->&[String]{&self.names}}
/// SAME actual full-registration discovery/name/group selection. Full means
/// exclusions-only (or empty), matching original main; excluded policies do not
/// mysteriously become mandatory, and zero-usage policies still must complete.
#[cfg(feature="native-policy")]
pub fn registered_full_selection(exclusions:&[String],c:&mut impl Control<Error=Failure>)->Result<FullSelectionData,Failure>{
 if exclusions.iter().any(|name|!name.starts_with('-')){return Err(invalid("unused ALLOW requires original full/exclusions-only selection metadata"))}
 let mut names=Vec::new();
 crate::allow_registry_fields::visit_all_scopes(c,&mut |meta,c|{
  if !exclusions.iter().any(|name|{let name=&name[1..];meta.name==name||(!meta.group.is_empty()&&meta.group==name)}){
   if names.iter().any(|old|old==meta.name){return Err(invalid("registered full policy metadata contains duplicate names"))}
   kc::row(c,&mut names)?;names.push(kc::own(c,meta.name)?);
  }Ok(())
 })?;c.checkpoint()?;Ok(FullSelectionData{names})
}
/// Cross-fold run coordinates DATA. Equality is only a consistency check: hashes
/// never issue authority. The actual native full-run owner must bind all three.
#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub enum FrameOwner{Semantic(u128),RawQuery(u128)}
#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub struct FrameData{pub owner:FrameOwner,pub source:u128,pub configuration:u128}
/// Operation-local aggregation of the actual policy folds' ALLOW outputs.
/// No manager/cache/source text/model is retained. This DATA cannot authorize
/// a partial/exclusive snapshot to masquerade as an all-selected-policy run.
pub struct UsageJoinData<'a>{selection:&'a FullSelectionData,frame:FrameData,completed:Vec<bool>,used:Vec<AllowUse>,poisoned:bool}
#[derive(Debug)]pub struct UsageData<'a>{used:&'a[AllowUse]}
impl UsageData<'_>{/// Borrowed completed fold DATA; source/currentness still belongs to the actual host.
 pub fn used(&self)->&[AllowUse]{self.used}}

impl<'a>UsageJoinData<'a>{
 pub fn new(selection:&'a FullSelectionData,frame:FrameData)->Self{Self{selection,frame,completed:Vec::new(),used:Vec::new(),poisoned:false}}
 /// Native caller must pass the concrete completed producer's own metadata
 /// name, even when its usage slice is empty. ALLOW alias names are NOT policy
 /// completion names. Mark completion only after all actual rows are copied.
 pub fn record_fold(&mut self,producer:&str,frame:FrameData,used:&[AllowUse],c:&mut impl Control<Error=Failure>)->Result<(),Failure>{self.record_fold_iter(producer,frame,used.iter(),c)}
 pub fn record_fold_iter<'row>(&mut self,producer:&str,frame:FrameData,used:impl IntoIterator<Item=&'row AllowUse>,c:&mut impl Control<Error=Failure>)->Result<(),Failure>{
  if self.poisoned{return Err(invalid("failed full ALLOW usage fold cannot resume"))}
  let pending=(||{
   c.checkpoint()?;
   let index=self.selection.names.iter().position(|name|name==producer);if frame!=self.frame||index.is_none()||index.is_some_and(|index|self.completed.get(index)==Some(&true)){return Err(invalid("ALLOW usage fold is foreign, duplicate or outside actual full selection"))}let index=index.expect("actual selected producer index");
   for row in used{c.checkpoint()?;kc::row(c,&mut self.used)?;self.used.push(AllowUse{rel:kc::own(c,&row.rel)?,line:row.line,name:kc::own(c,&row.name)?,code:kc::own(c,&row.code)?});}
   // Selection already owns every exact producer name. Only completion
   // flags are new storage; fund each real Vec growth before allocation.
   // Keep used-row copying above before completion admission as before.
   while self.completed.len()<self.selection.names.len(){kc::row(c,&mut self.completed)?;self.completed.push(false);}
   self.completed[index]=true;c.checkpoint()
  })();if pending.is_err(){self.poisoned=true}pending
 }
 /// This seals only the DATA fold. No completion bool from a page provider or
 /// caller, registry-known name set, or number of ALLOW uses licenses execution.
 pub fn finish_data(&mut self,c:&mut impl Control<Error=Failure>)->Result<UsageData<'_>,Failure>{
  if let Err(error)=c.checkpoint(){self.poisoned=true;return Err(error)}if self.poisoned||self.completed.len()!=self.selection.names.len()||self.completed.iter().any(|complete|!*complete){return Err(invalid("actual selected producer usage union is incomplete"))}Ok(UsageData{used:&self.used})
 }
}
struct FileFacts{relative:String,has_marker:bool,annotations:Vec<(u32,Vec<String>)>}
/// SAME original unused judge over actual raw-file loans and the accumulated
/// producer DATA. A true provider bool is only DATA; host's actual EOF receipt
/// and full-run scope MUST be consumed outside this fold before delivery.
/// Exemptions deliberately do not filter this phase: original unused() selects
/// all visible CODE_MAPS_DM, independently of per-lint annotation exemptions.
pub fn collect_unused_data(known:&ConfigurationNames<'_>,usage:&UsageData<'_>,pages:&dyn RawPolicyPages,extra_used:&[(String,String,u32)],digest:&dyn Fn(&str)->String,budget:&Budget,poll:&dyn Fn()->io::Result<()>)->Result<Vec<String>,Failure>{collect_unused_using(known,usage,pages,extra_used,digest,budget,poll,None)}
pub fn collect_unused_data_with_patterns(known:&ConfigurationNames<'_>,usage:&UsageData<'_>,pages:&dyn RawPolicyPages,extra_used:&[(String,String,u32)],digest:&dyn Fn(&str)->String,budget:&Budget,poll:&dyn Fn()->io::Result<()>,patterns:&dyn crate::native_pattern::Provider)->Result<Vec<String>,Failure>{collect_unused_using(known,usage,pages,extra_used,digest,budget,poll,Some(patterns))}
fn collect_unused_using(known:&ConfigurationNames<'_>,usage:&UsageData<'_>,pages:&dyn RawPolicyPages,extra_used:&[(String,String,u32)],digest:&dyn Fn(&str)->String,budget:&Budget,poll:&dyn Fn()->io::Result<()>,patterns:Option<&dyn crate::native_pattern::Provider>)->Result<Vec<String>,Failure>{
 let mut files:Vec<FileFacts>=Vec::new();let mut c=super::PatternOperation{budget,poll,patterns};
 let complete=pages.for_each(&mut|relative,views|{
  c.checkpoint()?;if !crate::tree::CODE_MAPS_DM.matches_path(relative){return Err(invalid("unused ALLOW source escaped actual CODE_MAPS_DM selection"))}
  let raw=views.raw()?;if !raw.contains("ALLOW("){return Ok(true)}
  // The SAME parser's retained names/rows are parent-funded while all source
  // loans remain nonescaping. No raw/code view, SourceFile or tree is copied.
  let annotations=policy::annotations(raw.split('\n').enumerate().map(|(n,line)|(n+1,line)),&mut c)?;
  kc::row(&mut c,&mut files)?;files.push(FileFacts{relative:kc::own(&mut c,relative)?,has_marker:true,annotations});Ok(true)
 })?;
 if !complete{return Err(Failure::Unsupported("unused ALLOW actual annotation traversal stopped before EOF".into()))}
 kc::sort_data(&mut files,&mut|a,b|->Result<std::cmp::Ordering,Failure>{c.checkpoint()?;Ok(a.relative.cmp(&b.relative))})?;
 if files.windows(2).any(|pair|pair[0].relative==pair[1].relative){return Err(invalid("unused ALLOW actual annotation source appeared twice"))}
 let mut rows=Vec::new();for file in &files{kc::row(&mut c,&mut rows)?;rows.push(policy::AnnotationFile{relative:&file.relative,has_marker:file.has_marker,annotations:&file.annotations});}
 let output=policy::unused(known.names,usage.used,extra_used,&rows,digest,&mut c)?;c.checkpoint()?;Ok(output)
}

#[cfg(test)]#[path="captured_allow_unused_tests.rs"]mod tests;

/// Neutral selected-tree Plan DATA, built by the native owner from concrete
/// producers' actual Meta::select values. Not a source/EOF/run receipt.
pub struct SelectedTreePlanData{plan:crate::tree::Plan,roots:Vec<&'static str>}
impl SelectedTreePlanData{
 pub fn new<C:Control<Error=Failure>>(selects:impl IntoIterator<Item=crate::tree::Select>,c:&mut C)->Result<Self,Failure>{
  let mut plan=crate::tree::Plan::default();let mut roots=Vec::new();
  for select in selects{for &(dir,extension)in select.roots{c.checkpoint()?;
   // Plan::add normalizes before allocating two Strings and attempting its
   // BTreeSet insertion. Avoid BOTH dead duplicate Strings and their admission;
   // the existing new-node envelope is unchanged. Borrowed comparison matches
   // that exact normalization and is DATA only, never discovery/completion.
   let normalized_dir=dir.trim_end_matches('/');let normalized_extension=extension.trim_start_matches('.');
   if plan.entries.iter().any(|(old_dir,old_extension)|old_dir==normalized_dir&&old_extension==normalized_extension){
    // Preserve the checked preallocation checkpoint even with no allocation.
    if C::CHECKED{c.checkpoint()?;}
   }else{kc::reserve(c,||dir.len().checked_add(extension.len())?.checked_mul(4)?.checked_add(2048))?;plan.add(dir,extension);}
   if extension.trim_start_matches('.')!="dm"{continue}let dir=dir.trim_end_matches('/');for domain in ["code","maps"]{let needed=if dir.is_empty()||dir==domain{Some(domain)}else if dir.starts_with(domain)&&dir.as_bytes().get(domain.len())==Some(&b'/'){Some(dir)}else{None};if let Some(needed)=needed{if !roots.contains(&needed){kc::row(c,&mut roots)?;roots.push(needed)}}}
  }}c.checkpoint()?;Ok(Self{plan,roots})
 }
 pub fn roots(&self)->&[&'static str]{&self.roots}
 /// Exact physical DM roots in the legacy loaded tree, including hidden files.
 pub fn loaded_dm_roots(&self) -> impl Iterator<Item = &str> {
  self.plan.entries.iter().filter(|(_, ext)| ext == "dm").map(|(dir, _)| dir.as_str())
 }
 /// The global loader retains hidden files regardless of each lint's scan filter.
 pub fn matches_loaded_dm(&self, relative: &str) -> bool {
  std::path::Path::new(relative).extension().and_then(|ext| ext.to_str()) == Some("dm")
   && self.loaded_dm_roots().any(|dir|
   dir.is_empty() || relative.strip_prefix(dir).is_some_and(|suffix| suffix.starts_with('/')))
 }
 pub fn matches_path(&self,relative:&str)->bool{if !crate::tree::CODE_MAPS_DM.matches_path(relative){return false}let extension=relative.rsplit_once('.').map_or("",|(_,extension)|extension);self.plan.entries.iter().any(|(dir,ext)|ext==extension&&(dir.is_empty()||(relative.starts_with(dir)&&relative.as_bytes().get(dir.len())==Some(&b'/'))))}
}

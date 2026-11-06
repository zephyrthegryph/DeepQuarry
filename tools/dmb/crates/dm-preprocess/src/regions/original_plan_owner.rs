//! Actual directive traversal metadata in the EXISTING DirectivePlan.
//! Original output has no PreparedLine/environment snapshots; the raw driver
//! supplies its one source/token/parser product. This owner funds metadata
//! before allocation and moves its SAME root to final product/Mapping owners.
use super::{DirectivePlan,IncludeOccurrence,IncludeRegion,OrderedItem,MacroEffect,ExpansionSegment};
use crate::{SourceAcquisitionLease,InitialEnvironment,macro_expansion::{OriginalMacroRows as Rows, empty_exact as exact_rows}};
use super::{original_output_trace::OriginalTraceProjectionKey, original_plan_paths::OriginalPlanPaths};
use dm_syntax::{SettingAdmission,SettingRootLease,SharedSettingRetention,Span};
use std::{io,mem,path::{Path,PathBuf},sync::Arc,collections::BTreeMap};
fn poll(a:&SettingAdmission<'_>)->io::Result<()>{a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))}
fn add(left:usize,right:usize)->io::Result<usize>{left.checked_add(right).ok_or_else(||io::ErrorKind::OutOfMemory.into())}
fn scaled(n:usize,scale:usize)->io::Result<usize>{n.checked_mul(scale).ok_or_else(||io::ErrorKind::OutOfMemory.into())}
fn grow(root:&mut SettingRootLease,bytes:usize,a:&SettingAdmission<'_>)->io::Result<()>{a.grow(root,bytes).map_err(|e|a.take_operational_error().unwrap_or(e))}
// SAME pinned std B-tree conservative <=16-slot/node allowance reviewed by the
// existing environment wrapper. This is a reservation, NEVER a heap census row.
fn node<K,V>()->io::Result<usize>{add(scaled(mem::size_of::<(K,V)>(),16)?,256)}
fn path_bound(path:&Path)->io::Result<usize>{add(scaled(path.as_os_str().len(),4)?,mem::size_of::<PathBuf>()+4*mem::size_of::<usize>())}
fn owned_path(path:&Path)->io::Result<PathBuf>{let mut result=PathBuf::new();result.try_reserve_exact(path.as_os_str().len()).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;result.push(path);if result.capacity()>path.as_os_str().len().saturating_mul(4){return Err(io::ErrorKind::OutOfMemory.into())}Ok(result)}
/// Reconcile only the variable byte allowance after constructing this exact
/// retained PathBuf. Its inline/Arc and map-node grants stay separate.
fn opened_path_unused(path:&PathBuf)->io::Result<usize>{
 scaled(path.as_os_str().len(),4)?.checked_sub(path.capacity()).ok_or(io::ErrorKind::InvalidData.into())
}
fn owned_text(text:&str)->io::Result<String>{let mut out=String::new();out.try_reserve_exact(text.len()).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;if out.capacity()>text.len().saturating_mul(4){return Err(io::ErrorKind::OutOfMemory.into())}out.push_str(text);Ok(out)}
fn push<T>(rows:&mut Vec<T>,value:T,root:&mut SettingRootLease,a:&SettingAdmission<'_>)->io::Result<()>{
 poll(a)?;
 if rows.len()==rows.capacity(){
  let target=rows.len().checked_add(1).and_then(usize::checked_next_power_of_two).ok_or(io::ErrorKind::OutOfMemory)?;
  let unit=mem::size_of::<T>();
  let old=scaled(rows.capacity(),unit)?;
  // Both actual buffers remain funded until the old one is freed.
  grow(root,scaled(target,unit)?,a)?;
  let mut next=exact_rows(target,a)?;
  next.append(rows);
  drop(mem::replace(rows,next));
  a.shrink(root,old).map_err(|e|a.take_operational_error().unwrap_or(e))?;
 }
 rows.push(value);
 Ok(())
}
// Bounded producer-local spelling reuse only. A name is never source or
// occurrence authority, and a collision only evicts the optional alias.
const TRACE_NAME_SLOTS:usize=256;
const TRACE_NAME_MAX_BYTES:usize=64;
const TRACE_ARC_HEADER:usize=2*mem::size_of::<usize>();
const TRACE_BOX_WRAPPER:usize=mem::size_of::<Box<[super::MacroExpansion]>>()+TRACE_ARC_HEADER;
fn trace_name_slot(name:&str)->usize{
 let mut hash=0xcbf29ce484222325u64;
 for byte in name.bytes(){hash=(hash^u64::from(byte)).wrapping_mul(0x100000001b3);}
 (hash as usize)&(TRACE_NAME_SLOTS-1)
}
// The Original stream never installs PreparedLine segments or native
// MacroEffects. Its region rows only retain encounter geometry.
struct EmptyOriginalRegion {
    segments: Arc<Vec<ExpansionSegment>>,
    effects: Arc<Vec<MacroEffect>>,
}
impl EmptyOriginalRegion {
    const BYTES: usize = mem::size_of::<Vec<ExpansionSegment>>()
        + mem::size_of::<Vec<MacroEffect>>() + 2 * TRACE_ARC_HEADER;
}

struct LastTraceProjection {
    key: OriginalTraceProjectionKey,
    rows: Arc<Box<[super::MacroExpansion]>>,
}
// Debug-only, opt-in measurement. No second dictionary or owner scan over
// tokens. Live trace projections are already retained by the original arena.
#[cfg(debug_assertions)]
#[derive(Debug,Default)]
struct TraceProjectionReservations {
 projections:usize,
 exact_hits:usize,
 rows:usize,
 row_bytes:usize,
 name_grants:usize,
 name_hits:usize,
 parent_slice_grants:usize,
 total_plan_grants:usize,
}
pub(super) struct OriginalPlanOwner{
 plan:DirectivePlan,paths:OriginalPlanPaths,current_region:Option<usize>,failed:bool,
 empty_region:Option<EmptyOriginalRegion>,
 empty_trace:Option<Arc<Box<[super::MacroExpansion]>>>,
 empty_replacement_chain:Option<Arc<[Arc<str>]>>,
 last_trace:Option<LastTraceProjection>,
 // Inline slots are already included in the owner's admitted size. Their
 // Arcs alias the same separately funded projection payloads.
 trace_names:[Option<Arc<str>>;TRACE_NAME_SLOTS],
 #[cfg(debug_assertions)]
 trace_projection:Option<TraceProjectionReservations>,
 credit:SettingRootLease,
}
impl OriginalPlanOwner{
 pub(super) fn new(project:&Path,initial:InitialEnvironment,defines:&BTreeMap<String,String>,revision:Option<u64>,a:&SettingAdmission<'_>)->io::Result<Self>{
  poll(a)?;if initial!=InitialEnvironment::OriginalChecker0290{return Err(io::ErrorKind::InvalidInput.into())}
  let mut credit=a.reserve(add(mem::size_of::<Self>(),path_bound(project.parent().unwrap_or_else(||Path::new("")))?)?).map_err(|e|a.take_operational_error().unwrap_or(e))?;
  let mut plan=DirectivePlan::default();plan.initial_environment=initial;plan.input_revision=revision;plan.source_acquisitions=super::SourceAcquisitions::original(a)?;plan.project_dir=owned_path(project.parent().unwrap_or_else(||Path::new("")))?;
  for(name,replacement)in defines{poll(a)?;let bytes=add(node::<String,String>()?,scaled(add(name.len(),replacement.len())?,4)?)?;grow(&mut credit,bytes,a)?;plan.defines.insert(owned_text(name)?,owned_text(replacement)?);}
  Ok(Self{plan,paths:OriginalPlanPaths::new(a)?,current_region:None,failed:false,empty_region:None,empty_trace:None,empty_replacement_chain:None,last_trace:None,trace_names:std::array::from_fn(|_|None),
   #[cfg(debug_assertions)]
   trace_projection:std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some().then(TraceProjectionReservations::default),
   credit})
 }
 fn check(&mut self,a:&SettingAdmission<'_>)->io::Result<()>{if self.failed{return Err(io::ErrorKind::InvalidInput.into())}let result=if !a.matches_lease_domain(&self.credit){Err(io::ErrorKind::InvalidInput.into())}else{poll(a)};if result.is_err(){self.failed=true}result}
 #[cfg(debug_assertions)]
 pub(super) fn trace_reservations(&self) -> (usize, usize, usize) {
  (self.plan.occurrences.len(), self.plan.regions.len(), self.credit.bytes().saturating_add(self.paths.row_capacity_bytes()))
 }
 /// Failed-stage telemetry. Role counts use existing borrowed indexes; no
 /// new path owner, duplicate census or successful-request traversal.
 #[cfg(debug_assertions)]
 pub(super) fn log_failure_reservations(&self){
  let Some(projection)=self.trace_projection.as_ref() else{return};
  let plan=&self.plan;
  let occurrence_path_payload_capacity=plan.occurrences.iter().map(|row|row.path.capacity()).fold(0usize,usize::saturating_add);
  let semantic_path_bytes=plan.occurrences.iter().map(|row|row.semantic_path.len()).fold(0usize,usize::saturating_add);
  fn capacity<T>(rows:&Vec<T>)->usize{rows.capacity().saturating_mul(mem::size_of::<T>())}
  let plan_vector_capacity=capacity(&plan.occurrences).saturating_add(capacity(&plan.regions))
   .saturating_add(capacity(&plan.items)).saturating_add(capacity(&plan.file_dirs));
  let empty_region_arc_grants=self.empty_region.as_ref().map_or(0,|_|EmptyOriginalRegion::BYTES);
  eprintln!("ORIGINAL_PLAN_RESERVATIONS opened_paths={} dependency_paths={} path_index_row_capacity={} occurrence_path_payload_capacity={occurrence_path_payload_capacity} semantic_path_bytes={semantic_path_bytes} plan_vector_capacity={plan_vector_capacity} empty_region_arc_grants={empty_region_arc_grants} projection={projection:?}",self.paths.sources().iter().count(),self.paths.dependencies().count(),self.paths.row_capacity_bytes());
 }
 pub(super) fn plan(&self)->&DirectivePlan{&self.plan}
 /// Only the actual admitted read/recorded acquisition path supplies a lease.
 /// No normalization/preparation/reopen occurs; decoded line metadata is DATA
 /// over that SAME facade, while all Original token points stay raw-issued.
 pub(super) fn register_opened_using(&mut self,path:&Path,semantic_path:&Path,lease:SourceAcquisitionLease,parent:Option<usize>,directive_span:Span,directive_line:usize,a:&SettingAdmission<'_>)->io::Result<usize>{
  self.check(a)?;let result=self.register_inner(path,semantic_path,lease,parent,directive_span,directive_line,a);if result.is_err(){self.failed=true}result
 }
 fn register_inner(&mut self,path:&Path,semantic_path:&Path,lease:SourceAcquisitionLease,parent:Option<usize>,directive_span:Span,directive_line:usize,a:&SettingAdmission<'_>)->io::Result<usize>{
  if parent.is_some_and(|p|p>=self.plan.occurrences.len()){return Err(io::ErrorKind::InvalidInput.into())}
  let occurrence=self.plan.occurrences.len();let text=lease.source_text();
  let previous=self.paths.sources().get(path);
  let needs_source=previous.is_none();
  if previous.is_some_and(|previous|previous.as_str()!=text.as_str()){return Err(io::Error::new(io::ErrorKind::InvalidInput,"same captured source path changed during actual traversal"))}
  let mut metadata=add(path_bound(path)?,scaled(mem::size_of::<usize>(),8)?)?;
  path.to_str().ok_or_else(||io::Error::new(io::ErrorKind::Unsupported,"actual semantic source path is not UTF8"))?;
  let semantic=semantic_path.to_str().ok_or(io::ErrorKind::InvalidInput)?;
  // The real include branch has already registered this semantic name. Own
  // its exact Arc payload once; the fixed grant covers control and alignment.
  metadata=add(metadata,add(semantic.len(),4*mem::size_of::<usize>())?)?;grow(&mut self.credit,metadata,a)?;
  let path=Arc::new(owned_path(path)?);let unused=opened_path_unused(&path)?;
  let semantic_path:Arc<str>=Arc::from(semantic);
  let row=IncludeOccurrence{path:Arc::clone(&path),semantic_path,original_entry:if parent.is_none(){Some(Arc::clone(&path))}else{None},parent,directive_span,directive_line,suppressed:false,non_text_kind:None,return_cursor:None,eof_cursor_line:None,eof_cursor_encounter:None};
  push(&mut self.plan.occurrences,row,&mut self.credit,a)?;
  // The map roles share the first matching actual path allocation. Do not
  // canonicalize the occurrence path itself or replace its separate receipt.
  if needs_source{self.paths.note(Arc::clone(&path),Some(text.clone()),a)?;}
  self.plan.source_acquisitions.append_original(occurrence,lease,a)?;
  // All real path allocations and index updates happened in traversal
  // order; retire only unused allowance after those owners are settled.
  if unused!=0{a.shrink(&mut self.credit,unused).map_err(|e|a.take_operational_error().unwrap_or(e))?;}
  self.current_region=None;Ok(occurrence)
 }
 /// Actual emitted token chooses a region from its current registered physical
 /// occurrence. A return from a real child starts another encounter segment;
 /// no environment snapshot or PreparedLine is fabricated for raw output.
 pub(super) fn region_for_emission_using(&mut self,occurrence:usize,decoded_row:Span,a:&SettingAdmission<'_>)->io::Result<usize>{
  self.check(a)?;let result=(||{let lease=self.plan.source_acquisitions.get(&occurrence).ok_or(io::ErrorKind::InvalidInput)?;if decoded_row.start>decoded_row.end||decoded_row.end>lease.source_text().as_str().len(){return Err(io::ErrorKind::InvalidInput.into())}
   if let Some(index)=self.current_region{let row=&mut self.plan.regions[index];if row.occurrence==occurrence{row.source_span.start=row.source_span.start.min(decoded_row.start);row.source_span.end=row.source_span.end.max(decoded_row.end);return Ok(index)}}
   if self.empty_region.is_none() {
    grow(&mut self.credit,EmptyOriginalRegion::BYTES,a)?;
    self.empty_region=Some(EmptyOriginalRegion{segments:Arc::new(Vec::new()),effects:Arc::new(Vec::new())});
   } else {
    // Keep the checked transition before allocating or publishing a new row.
    poll(a)?;
   }
   let empty=self.empty_region.as_ref().expect("admitted Original empty region storage");
   let index=self.plan.regions.len();
   let region=IncludeRegion{occurrence,source_span:decoded_row,encounter_ordinal:self.plan.items.len(),manifest_source:self.plan.occurrences[occurrence].path.extension().is_some_and(|e|e=="dme"),segments:Arc::clone(&empty.segments),effects:Arc::clone(&empty.effects)};
   push(&mut self.plan.regions,region,&mut self.credit,a)?;push(&mut self.plan.items,OrderedItem::Text(index),&mut self.credit,a)?;self.current_region=Some(index);Ok(index)
  })();if result.is_err(){self.failed=true}result
 }

 pub(super) fn occurrence(&self,index:usize)->io::Result<&IncludeOccurrence>{self.plan.occurrences.get(index).ok_or_else(||io::ErrorKind::InvalidInput.into())}
 pub(super) fn lease(&self,index:usize)->io::Result<SourceAcquisitionLease>{self.plan.source_acquisitions.get(&index).cloned().ok_or_else(||io::ErrorKind::InvalidInput.into())}
 pub(super) fn charge_using(&mut self,bytes:usize,a:&SettingAdmission<'_>)->io::Result<()>{self.check(a)?;grow(&mut self.credit,bytes,a)}
 pub(super) fn definition_using(&self,origin:crate::macro_expansion::OriginalMacroOrigin,driver:&mut super::original_driver::RawSourceDriver,provider:&dyn crate::SourceProvider,a:&SettingAdmission<'_>)->io::Result<super::DefinitionOrigin>{let occurrence=self.occurrence(origin.occurrence)?;let lease=self.lease(origin.occurrence)?;let row=driver.physical_row_using(origin,&lease,provider,a)?;let end=driver.decoded_offset_using(origin.occurrence,&lease,origin.physical.end,a)?;Ok(super::DefinitionOrigin{path:Arc::clone(&occurrence.path),source_span:Span::new(row.point.source_offset,end),source_line:row.point.line})}
 pub(super) fn add_dependency_using(&mut self,path:&Path,a:&SettingAdmission<'_>)->io::Result<()>{
  self.check(a)?;
  if !self.paths.contains_dependency(path){
   grow(&mut self.credit,path_bound(path)?,a)?;
   let path=Arc::new(owned_path(path)?);let unused=opened_path_unused(&path)?;
   self.paths.note(path,None,a)?;
   if unused!=0{a.shrink(&mut self.credit,unused).map_err(|e|a.take_operational_error().unwrap_or(e))?;}
  }
  Ok(())
 }
 pub(super) fn add_non_text_using(&mut self,path:&Path,parent:usize,span:Span,line:usize,kind:super::NonTextKind,a:&SettingAdmission<'_>)->io::Result<usize>{self.check(a)?;self.add_dependency_using(path,a)?;grow(&mut self.credit,add(path_bound(path)?,scaled(path.as_os_str().len(),4)?)?,a)?;let path=Arc::new(owned_path(path)?);let semantic_path:Arc<str>=Arc::from(path.to_str().ok_or(io::ErrorKind::InvalidInput)?);let occurrence=self.plan.occurrences.len();push(&mut self.plan.occurrences,IncludeOccurrence{path,semantic_path,original_entry:None,parent:Some(parent),directive_span:span,directive_line:line,suppressed:false,non_text_kind:Some(kind),return_cursor:None,eof_cursor_line:None,eof_cursor_encounter:None},&mut self.credit,a)?;push(&mut self.plan.items,OrderedItem::NonText{occurrence,kind},&mut self.credit,a)?;self.current_region=None;Ok(occurrence)}
 pub(super) fn add_omitted_using(&mut self,path:&Path,parent:usize,span:Span,line:usize,a:&SettingAdmission<'_>)->io::Result<usize>{self.check(a)?;self.add_dependency_using(path,a)?;grow(&mut self.credit,add(path_bound(path)?,scaled(path.as_os_str().len(),4)?)?,a)?;let path=Arc::new(owned_path(path)?);let semantic_path:Arc<str>=Arc::from(path.to_str().ok_or(io::ErrorKind::InvalidInput)?);let occurrence=self.plan.occurrences.len();push(&mut self.plan.occurrences,IncludeOccurrence{path,semantic_path,original_entry:None,parent:Some(parent),directive_span:span,directive_line:line,suppressed:false,non_text_kind:None,return_cursor:None,eof_cursor_line:None,eof_cursor_encounter:None},&mut self.credit,a)?;self.current_region=None;Ok(occurrence)}
 pub(super) fn add_file_dir_using(&mut self,path:&Path,a:&SettingAdmission<'_>)->io::Result<()>{self.check(a)?;grow(&mut self.credit,path_bound(path)?,a)?;push(&mut self.plan.file_dirs,owned_path(path)?,&mut self.credit,a)}

 fn project_trace_name(&mut self,name:&str,a:&SettingAdmission<'_>)->io::Result<(Arc<str>,usize)>{
  let slot=(name.len()<=TRACE_NAME_MAX_BYTES).then(||&mut self.trace_names[trace_name_slot(name)]);
  if let Some(existing)=slot.as_deref().and_then(Option::as_ref).filter(|old|old.as_ref()==name){
   return Ok((Arc::clone(existing),0))
  }
  // One immutable spelling. Keep the existing conservative byte/alignment
  // grant on misses, and no second name storage or lookup allocation.
  let grant=add(name.len(),4*mem::size_of::<usize>())?;
  grow(&mut self.credit,grant,a)?;
  let projected:Arc<str>=Arc::from(name);
  if let Some(slot)=slot{*slot=Some(Arc::clone(&projected));}
  Ok((projected,grant))
 }

 pub(super) fn trace_using(&mut self,actual:&super::original_output_trace::OriginalOutputTrace,driver:&mut super::original_driver::RawSourceDriver,provider:&dyn crate::SourceProvider,a:&SettingAdmission<'_>)->io::Result<Arc<Box<[super::MacroExpansion]>>>{
  self.check(a)?;
  if actual.depth()==0{
   // An empty trace carries no locations or authority. Reuse one funded
   // allocation in this plan so adjacent authenticated ordinary origins can
   // share their physical-row group, and do not reserve it per token.
   if self.empty_trace.is_none(){
    grow(&mut self.credit,TRACE_BOX_WRAPPER,a)?;
    self.empty_trace=Some(Arc::new(Vec::new().into_boxed_slice()));
   }
   return Ok(Arc::clone(self.empty_trace.as_ref().expect("actual empty trace allocated")));
  }
  if let Some(last) = self.last_trace.as_ref().filter(|last| last.key.matches(actual, a)) {
   let mut matches = true;
   actual.visit_inner_to_outer_using(a, |entry| {
    // Geometry still borrows real provider bytes, in exactly the old order.
    // Never skip or replay that call on a hit, including its first IO error.
    let definition = entry.definition.map(|origin| self.definition_using(origin, driver, provider, a)).transpose()?;
    let prior = &last.rows[entry.depth - 1].definition;
    matches &= match (&definition, prior) {
     (None, None) => true,
     (Some(current), Some(previous)) => Arc::ptr_eq(&current.path, &previous.path)
      && current.source_span == previous.source_span && current.source_line == previous.source_line,
     _ => false,
    };
    Ok(())
   })?;
   if !matches {
    return Err(io::Error::new(io::ErrorKind::InvalidData, "actual macro trace definition changed within its source acquisition"));
   }
   #[cfg(debug_assertions)]
   if let Some(trace)=&mut self.trace_projection {trace.exact_hits=trace.exact_hits.saturating_add(1);}
   return Ok(Arc::clone(&last.rows));
  }
  // Retire the previous weak backing before funding any new key.
  self.last_trace = None;
  #[cfg(debug_assertions)]
  let before=self.credit.bytes();
  let depth = actual.depth();
  #[cfg(debug_assertions)]
  let mut name_usage=self.trace_projection.as_ref().map(|_|(0usize,0usize));
  // The immutable box keeps a thin Arc handle in every provenance group.
  // Only this wrapper and one exact row array are retained.
  let mut rows = Vec::new();
  grow(&mut self.credit, TRACE_BOX_WRAPPER, a)?;
  actual.visit_inner_to_outer_using(a, |entry| {
   let (name,_grant)=self.project_trace_name(entry.name,a)?;
   #[cfg(debug_assertions)]
   if let Some((grants,hits))=&mut name_usage{
    *grants=grants.saturating_add(_grant);
    *hits=hits.saturating_add(usize::from(_grant==0));
   }
   let definition = entry.definition.map(|origin| self.definition_using(origin, driver, provider, a)).transpose()?;
   if self.empty_replacement_chain.is_none() {
    grow(&mut self.credit, TRACE_ARC_HEADER, a)?;
    self.empty_replacement_chain = Some(Arc::from([]));
   }
   if rows.is_empty() {
    // Fund the exact original trace depth once, after the first definition
    // loan (where the former row allocation ran). No transient geometric
    // copies or unfunded Vec capacity growth are possible.
    grow(&mut self.credit, scaled(depth, mem::size_of::<super::MacroExpansion>())?, a)?;
    rows = exact_rows(depth, a)?;
   }
   if rows.len() >= depth {
    return Err(io::ErrorKind::InvalidData.into());
   }
   let replacement_chain = Arc::clone(self.empty_replacement_chain.as_ref().expect("original empty replacement chain funded"));
   rows.push(super::MacroExpansion { name, invocation_span: entry.origin.physical, replacement_chain, definition });
   Ok(())
  })?;
  if rows.len() != depth {
   return Err(io::ErrorKind::InvalidData.into());
  }
  rows.reverse();
  // The outer row keeps the shared empty chain. Every other row aliases
  // the same earlier projected names. Keep the exact Arc payload funded,
  // and release the scratch Vec only after Arc::from has consumed it.
  for at in 1..rows.len() {
   let bytes = scaled(at, mem::size_of::<Arc<str>>())?;
   grow(&mut self.credit, add(bytes, TRACE_ARC_HEADER)?, a)?;
   let scratch = a.reserve(bytes).map_err(|error| a.take_operational_error().unwrap_or(error))?;
   let mut parents = exact_rows(at, a)?;
   parents.extend(rows[..at].iter().map(|row| Arc::clone(&row.name)));
   rows[at].replacement_chain = Arc::from(parents);
   drop(scratch);
  }
  // The vector was issued at exact depth and is full. Converting it
  // transfers the original row allocation without a shrink or second array.
  debug_assert_eq!(rows.capacity(), rows.len());
  let row_pointer=rows.as_ptr();
  let rows = Arc::new(rows.into_boxed_slice());
  debug_assert_eq!(rows.as_ptr(),row_pointer);
  self.last_trace = Some(LastTraceProjection { key: actual.projection_key_using(a)?, rows: Arc::clone(&rows) });
  #[cfg(debug_assertions)]
  if let Some(trace)=&mut self.trace_projection {
   trace.projections=trace.projections.saturating_add(1);
   trace.rows=trace.rows.saturating_add(rows.len());
   trace.row_bytes=trace.row_bytes.saturating_add(rows.len().saturating_mul(mem::size_of::<super::MacroExpansion>()));
   trace.total_plan_grants=trace.total_plan_grants.saturating_add(self.credit.bytes().saturating_sub(before));
   let (grants,hits)=name_usage.expect("trace counters enabled for this projection");
   trace.name_grants=trace.name_grants.saturating_add(grants);
   trace.name_hits=trace.name_hits.saturating_add(hits);
   for row in rows.iter().skip(1){
    trace.parent_slice_grants=trace.parent_slice_grants.saturating_add(row.replacement_chain.len().saturating_mul(mem::size_of::<Arc<str>>()).saturating_add(TRACE_ARC_HEADER));
   }
  }
  Ok(rows)
 }
 pub(super) fn finish_using(mut self,a:&SettingAdmission<'_>)->io::Result<(DirectivePlan,OriginalPlanPaths,SharedSettingRetention)>{
  self.check(a)?;
  grow(&mut self.credit,mem::size_of::<SettingRootLease>()+4*mem::size_of::<usize>(),a)?;
  let Self{plan,paths,credit,..}=self;
  Ok((plan,paths,SharedSettingRetention::new(credit)))
 }
}

#[cfg(test)]
mod trace_storage_tests {
    use super::*;
    use crate::macro_expansion::OriginalMacroOrigin;
    use std::sync::atomic::{AtomicUsize, Ordering};

    struct NoSource;
    impl crate::SourceProvider for NoSource {
        fn read(&self, _: &Path) -> Result<String, String> {
            panic!("this trace fixture has no raw source to acquire")
        }
    }

    #[test]
    fn ordinary_tokens_share_one_funded_empty_projection_across_an_actual_macro_trace() {
        let used = Arc::new(AtomicUsize::new(0));
        let a = SettingAdmission::new(&used, 8 << 20, &|| Ok(()));
        let defines = BTreeMap::new();
        let mut plan = OriginalPlanOwner::new(
            Path::new("empty-trace.dme"), InitialEnvironment::OriginalChecker0290,
            &defines, None, &a,
        ).unwrap();
        let mut driver = super::super::original_driver::RawSourceDriver::new(
            InitialEnvironment::OriginalChecker0290, &defines, &a,
            &mut |input, a| super::super::original_token_factory::initial_definition_using(
                input, a, &mut |_| panic!("fixed defaults have no lexical notice"),
                &mut |_, _| panic!("fixed defaults have no numeric notice"),
            ),
        ).unwrap();
        let empty = super::super::original_output_trace::OriginalOutputTrace::default();
        let first = plan.trace_using(&empty, &mut driver, &NoSource, &a).unwrap();
        let origin = OriginalMacroOrigin {
            physical: Span::new(5, 11), line: 2, byte_column: Some(3),
            occurrence: 0, invocation: true,
        };
        let actual = empty.pushed_using("TRACE", origin, 1, None, &a).unwrap();
        let nonempty = plan.trace_using(&actual, &mut driver, &NoSource, &a).unwrap();
        assert_eq!(nonempty.len(), 1);
        assert_eq!(nonempty[0].name.as_ref(), "TRACE");
        assert_eq!(nonempty[0].invocation_span, origin.physical);
        let before = used.load(Ordering::Acquire);
        for _ in 0..32 {
            let next = plan.trace_using(&empty, &mut driver, &NoSource, &a).unwrap();
            assert!(next.is_empty());
            assert!(Arc::ptr_eq(&first, &next));
            assert_eq!(used.load(Ordering::Acquire), before);
        }
        drop((first, nonempty, actual, empty, driver, plan));
        assert_eq!(used.load(Ordering::Acquire), 0);
    }

    #[test]
    fn projected_trace_charges_exact_depth_and_releases_parent_scratch() {
        let used = Arc::new(AtomicUsize::new(0));
        let a = SettingAdmission::new(&used, 8 << 20, &|| Ok(()));
        let defines = BTreeMap::new();
        let mut plan = OriginalPlanOwner::new(
            Path::new("exact-trace.dme"), InitialEnvironment::OriginalChecker0290,
            &defines, None, &a,
        ).unwrap();
        let mut driver = super::super::original_driver::RawSourceDriver::new(
            InitialEnvironment::OriginalChecker0290, &defines, &a,
            &mut |input, a| super::super::original_token_factory::initial_definition_using(
                input, a, &mut |_| panic!("fixed defaults have no lexical notice"),
                &mut |_, _| panic!("fixed defaults have no numeric notice"),
            ),
        ).unwrap();
        let origin = OriginalMacroOrigin {
            physical: Span::new(2, 7), line: 1, byte_column: Some(3),
            occurrence: 0, invocation: true,
        };
        let mut actual = super::super::original_output_trace::OriginalOutputTrace::default();
        let names = ["OUTER", "MIDDLE", "INNER"];
        for (at, name) in names.into_iter().enumerate() {
            actual = actual.pushed_using(name, origin, at + 1, None, &a).unwrap();
        }
        let before = plan.credit.bytes();
        let rows = plan.trace_using(&actual, &mut driver, &NoSource, &a).unwrap();
        assert_eq!(rows.len(), names.len(), "exact frozen row array");
        assert_eq!(mem::size_of_val(&rows), mem::size_of::<Arc<Vec<super::super::MacroExpansion>>>(), "the coordinate group must keep its thin trace handle");
        assert_eq!(TRACE_BOX_WRAPPER + mem::size_of::<usize>(), mem::size_of::<Vec<super::super::MacroExpansion>>() + TRACE_ARC_HEADER);
        for (at, row) in rows.iter().enumerate() {
            assert_eq!(row.name.as_ref(), names[at]);
            assert_eq!(row.replacement_chain.len(), at);
            for (alias, parent) in row.replacement_chain.iter().zip(&rows[..at]) {
                assert!(Arc::ptr_eq(alias, &parent.name));
            }
        }
        let control = 4 * mem::size_of::<usize>();
        let expected = TRACE_BOX_WRAPPER
            + names.len() * mem::size_of::<super::super::MacroExpansion>()
            + names.iter().map(|name| name.len() + control).sum::<usize>()
            + TRACE_ARC_HEADER + (mem::size_of::<Arc<str>>() + TRACE_ARC_HEADER)
            + (2 * mem::size_of::<Arc<str>>() + TRACE_ARC_HEADER);
        assert_eq!(plan.credit.bytes() - before, expected);
        let other = super::super::original_output_trace::OriginalOutputTrace::default()
            .pushed_using("OTHER", origin, 1, None, &a).unwrap();
        let previous = plan.credit.bytes();
        let next = plan.trace_using(&other, &mut driver, &NoSource, &a).unwrap();
        assert!(Arc::ptr_eq(&rows[0].replacement_chain, &next[0].replacement_chain));
        assert_eq!(plan.credit.bytes() - previous,
            TRACE_BOX_WRAPPER + mem::size_of::<super::super::MacroExpansion>() + "OTHER".len() + control);
        drop((rows, next, other, actual, driver, plan));
        assert_eq!(used.load(Ordering::Acquire), 0);
    }


    #[test]
    fn projected_name_reuse_funds_spelling_once_and_collisions_keep_distinct_occurrences() {
        let used=Arc::new(AtomicUsize::new(0));
        let a=SettingAdmission::new(&used,8<<20,&||Ok(()));
        let defines=BTreeMap::new();
        let mut plan=OriginalPlanOwner::new(Path::new("trace-names.dme"),InitialEnvironment::OriginalChecker0290,&defines,None,&a).unwrap();
        let mut driver=super::super::original_driver::RawSourceDriver::new(
            InitialEnvironment::OriginalChecker0290,&defines,&a,
            &mut|input,a|super::super::original_token_factory::initial_definition_using(
                input,a,&mut |_|panic!("fixed default lexical notice"),&mut|_,_|panic!("fixed default numeric notice"),
            ),
        ).unwrap();
        let make=|name,at|super::super::original_output_trace::OriginalOutputTrace::default().pushed_using(
            name,OriginalMacroOrigin{physical:Span::new(at,at+1),line:at+1,byte_column:Some(1),occurrence:0,invocation:true},
            1,None,&a,
        ).unwrap();
        assert_eq!(trace_name_slot("SAME"),trace_name_slot("DIFFERENT_187"));
        let first=make("SAME",0);let repeated=make("SAME",2);let collision=make("DIFFERENT_187",4);
        let first_rows=plan.trace_using(&first,&mut driver,&NoSource,&a).unwrap();
        let before=plan.credit.bytes();
        let repeated_rows=plan.trace_using(&repeated,&mut driver,&NoSource,&a).unwrap();
        assert_eq!(plan.credit.bytes()-before,TRACE_BOX_WRAPPER+mem::size_of::<super::super::MacroExpansion>());
        assert!(Arc::ptr_eq(&first_rows[0].name,&repeated_rows[0].name));
        assert!(!Arc::ptr_eq(&first_rows,&repeated_rows));
        assert_eq!(first_rows[0].invocation_span,Span::new(0,1));
        assert_eq!(repeated_rows[0].invocation_span,Span::new(2,3));
        let collided_rows=plan.trace_using(&collision,&mut driver,&NoSource,&a).unwrap();
        assert_eq!(collided_rows[0].name.as_ref(),"DIFFERENT_187");
        let replayed=plan.trace_using(&first,&mut driver,&NoSource,&a).unwrap();
        assert_eq!(replayed,first_rows);
        assert!(!Arc::ptr_eq(&replayed[0].name,&first_rows[0].name),"collision only evicts the pool alias");
        drop((first_rows,repeated_rows,collided_rows,replayed,first,repeated,collision,driver,plan));
        assert_eq!(used.load(Ordering::Acquire),0);
    }

    #[test]
    fn exact_trace_hit_lends_both_actual_definition_sources_and_keeps_first_io_error() {
        use std::cell::{Cell, RefCell};
        use super::super::{original_driver::RawSourceDriver, original_output_trace::OriginalOutputTrace};

        struct Sources {
            definitions: [SourceAcquisitionLease; 2],
            calls: RefCell<Vec<usize>>,
            fail_at: Cell<Option<usize>>,
        }
        impl crate::SourceProvider for Sources {
            fn read(&self, _: &Path) -> Result<String, String> {
                panic!("a definition lookup must lend its original acquisition")
            }
            fn original_source_bytes<'a>(&'a self, lease: &'a SourceAcquisitionLease) -> io::Result<Option<&'a [u8]>> {
                let source = self.definitions.iter().position(|actual| actual.same_original_acquisition(lease))
                    .ok_or(io::ErrorKind::InvalidInput)?;
                let mut calls = self.calls.borrow_mut();
                calls.push(source);
                if self.fail_at.get() == Some(calls.len()) {
                    return Err(io::Error::from_raw_os_error(1450));
                }
                Ok(Some(lease.source_text().as_bytes()))
            }
        }

        let used = Arc::new(AtomicUsize::new(0));
        let a = SettingAdmission::new(&used, 8 << 20, &|| Ok(()));
        let defines = BTreeMap::new();
        let mut plan = OriginalPlanOwner::new(
            Path::new("outer.dme"), InitialEnvironment::OriginalChecker0290,
            &defines, None, &a,
        ).unwrap();
        let mut driver = RawSourceDriver::new(
            InitialEnvironment::OriginalChecker0290, &defines, &a,
            &mut |input, a| super::super::original_token_factory::initial_definition_using(
                input, a, &mut |_| panic!("fixed defaults have no lexical notice"),
                &mut |_, _| panic!("fixed defaults have no numeric notice"),
            ),
        ).unwrap();
        let sources = Sources {
            definitions: [
                SourceAcquisitionLease::from_raw_original_bytes(b"outer\n".to_vec(), 10u64),
                SourceAcquisitionLease::from_raw_original_bytes(b"inner\n".to_vec(), 20u64),
            ],
            calls: RefCell::new(Vec::new()),
            fail_at: Cell::new(None),
        };
        for (ordinal, (name, lease)) in ["outer.dme", "inner.dm"].iter().zip(&sources.definitions).enumerate() {
            let path = Path::new(name);
            let parent = ordinal.checked_sub(1);
            assert_eq!(plan.register_opened_using(path, path, lease.clone(), parent, Span::default(), 0, &a).unwrap(), ordinal);
            driver.push_opened_at(&sources, lease.clone(), ordinal, path, &a).unwrap();
        }
        let invocation = OriginalMacroOrigin {
            physical: Span::new(0, 5), line: 1, byte_column: Some(1), occurrence: 0, invocation: true,
        };
        let outer_definition = OriginalMacroOrigin { invocation: false, ..invocation };
        let inner_definition = OriginalMacroOrigin { occurrence: 1, ..outer_definition };
        let outer = OriginalOutputTrace::default().pushed_using("OUTER", invocation, 1, Some(outer_definition), &a).unwrap();
        let trace = outer.pushed_using("INNER", invocation, 2, Some(inner_definition), &a).unwrap();

        sources.calls.borrow_mut().clear();
        let first = plan.trace_using(&trace, &mut driver, &sources, &a).unwrap();
        assert_eq!(*sources.calls.borrow(), [1, 0]);
        assert_eq!(first[0].definition.as_ref().unwrap().path.as_path(), Path::new("outer.dme"));
        assert_eq!(first[1].definition.as_ref().unwrap().path.as_path(), Path::new("inner.dm"));
        assert_eq!(first[1].replacement_chain[0].as_ref(), "OUTER");

        sources.calls.borrow_mut().clear();
        let before = used.load(Ordering::Acquire);
        let repeat = plan.trace_using(&trace, &mut driver, &sources, &a).unwrap();
        assert_eq!(*sources.calls.borrow(), [1, 0]);
        assert!(Arc::ptr_eq(&repeat, &first));
        assert_eq!(used.load(Ordering::Acquire), before);

        let equal_but_distinct = outer.pushed_using("INNER", invocation, 2, Some(inner_definition), &a).unwrap();
        sources.calls.borrow_mut().clear();
        let other = plan.trace_using(&equal_but_distinct, &mut driver, &sources, &a).unwrap();
        assert_eq!(*sources.calls.borrow(), [1, 0]);
        assert_eq!(other, first);
        assert!(!Arc::ptr_eq(&other, &first));
        assert!(Arc::ptr_eq(&other[0].name,&first[0].name));
        assert!(Arc::ptr_eq(&other[1].name,&first[1].name));

        sources.calls.borrow_mut().clear();
        sources.fail_at.set(Some(2));
        let error = plan.trace_using(&equal_but_distinct, &mut driver, &sources, &a).unwrap_err();
        assert_eq!(error.raw_os_error(), Some(1450));
        assert_eq!(*sources.calls.borrow(), [1, 0], "hit must neither skip nor replay real IO");
        drop((trace, equal_but_distinct, outer, driver, plan, first, repeat, other));
        assert_eq!(used.load(Ordering::Acquire), 0);
    }
}

#[cfg(test)]
mod opened_path_storage_tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};

    #[test]
    fn actual_open_registration_charges_each_retained_path_capacity_once() {
        let used=Arc::new(AtomicUsize::new(0));
        let a=SettingAdmission::new(&used,8<<20,&||Ok(()));
        let root=Path::new("root.dme");
        let semantic=Path::new("child.dm");
        let measure=|physical:&Path|{
            let mut plan=OriginalPlanOwner::new(root,InitialEnvironment::OriginalChecker0290,&BTreeMap::new(),None,&a).unwrap();
            let lease=SourceAcquisitionLease::from_raw_original_bytes(b"/datum/x\n".to_vec(),17u64);
            plan.register_opened_using(root,root,lease.clone(),None,Span::default(),0,&a).unwrap();
            let prior=plan.credit.bytes();
            let child=plan.register_opened_using(physical,semantic,lease.clone(),Some(0),Span::new(2,7),1,&a).unwrap();
            let row=plan.occurrence(child).unwrap();
            assert_eq!(row.path.as_path(),physical);
            assert_eq!(row.semantic_path.as_ref(),"child.dm");
            assert!(plan.lease(child).unwrap().same_binding(&lease));
            let text_key=plan.paths.sources().iter().find(|(path,_)|path.as_path()==physical).unwrap().0;
            let dep_key=plan.paths.dependencies().find(|path|path.as_path()==physical).unwrap();
            assert!(std::ptr::eq(text_key,row.path.as_ref()));
            assert!(std::ptr::eq(dep_key,row.path.as_ref()));
            let path_bytes=row.path.capacity();
            let charge=plan.credit.bytes()-prior;
            drop(plan);
            assert_eq!(used.load(Ordering::Acquire),0);
            (charge,path_bytes)
        };
        let(short,short_path)=measure(Path::new("E:/root/child.dm"));
        let(long,long_path)=measure(Path::new("E:/root/a-much-longer-physical-prefix/child.dm"));
        assert!(long_path>short_path);
        assert_eq!(long-short,long_path-short_path,"one physical PathBuf is shared by the two actual indexes and its occurrence");
    }

    #[test]
    fn actual_empty_region_rows_share_one_funded_pair_without_merging_geometry() {
        let used=Arc::new(AtomicUsize::new(0));
        let a=SettingAdmission::new(&used,1<<20,&||Ok(()));
        let root=Path::new("root.dme");
        let child=Path::new("child.dm");
        let lease=SourceAcquisitionLease::from_raw_original_bytes(b"/datum/x\n".to_vec(),17u64);
        let mut owner=OriginalPlanOwner::new(root,InitialEnvironment::OriginalChecker0290,&BTreeMap::new(),None,&a).unwrap();
        let first=owner.register_opened_using(root,root,lease.clone(),None,Span::default(),0,&a).unwrap();
        let second=owner.register_opened_using(child,child,lease,Some(first),Span::new(2,5),1,&a).unwrap();
        assert!(owner.empty_region.is_none());
        let row_bytes=mem::size_of::<IncludeRegion>()+mem::size_of::<OrderedItem>();
        let baseline=owner.credit.bytes();
        assert_eq!(owner.region_for_emission_using(first,Span::new(0,1),&a).unwrap(),0);
        assert_eq!(owner.credit.bytes()-baseline,row_bytes+EmptyOriginalRegion::BYTES);
        assert_eq!(owner.region_for_emission_using(second,Span::new(2,4),&a).unwrap(),1);
        assert_eq!(owner.credit.bytes()-baseline,2*row_bytes+EmptyOriginalRegion::BYTES);

        let (plan,paths,retention)=owner.finish_using(&a).unwrap();
        assert_eq!(plan.regions[0].source_span,Span::new(0,1));
        assert_eq!(plan.regions[1].source_span,Span::new(2,4));
        assert_eq!(plan.regions[0].occurrence,first);
        assert_eq!(plan.regions[1].occurrence,second);
        assert_eq!(plan.regions[1].encounter_ordinal,1);
        assert!(plan.regions[0].manifest_source);
        assert!(!plan.regions[1].manifest_source);
        assert!(Arc::ptr_eq(&plan.regions[0].segments,&plan.regions[1].segments));
        assert!(Arc::ptr_eq(&plan.regions[0].effects,&plan.regions[1].effects));
        assert_eq!(plan.regions[0].segments.capacity(),0);
        assert_eq!(plan.regions[0].effects.capacity(),0);
        assert!(used.load(Ordering::Acquire)>0);
        drop((plan,paths,retention));
        assert_eq!(used.load(Ordering::Acquire),0);
    }

    #[test]
    fn actual_path_index_fits_a_small_admission_with_distinct_occurrence_receipts() {
        let used=Arc::new(AtomicUsize::new(0));
        let a=SettingAdmission::new(&used,768<<10,&||Ok(()));
        let root=Path::new("root.dme");
        let mut plan=OriginalPlanOwner::new(root,InitialEnvironment::OriginalChecker0290,&BTreeMap::new(),None,&a).unwrap();
        let text=b"/datum/x\n";
        let first=SourceAcquisitionLease::from_raw_original_bytes(text.to_vec(),17u64);
        plan.register_opened_using(root,root,first.clone(),None,Span::default(),0,&a).unwrap();
        for ordinal in (0..512).rev() {
            let path=PathBuf::from(format!("child-{ordinal:04}.dm"));
            plan.register_opened_using(&path,&path,first.clone(),Some(0),Span::default(),1,&a).unwrap();
        }
        let repeat=SourceAcquisitionLease::from_raw_original_bytes(text.to_vec(),18u64);
        let child=Path::new("child-0000.dm");
        let duplicate=plan.register_opened_using(child,child,repeat.clone(),Some(0),Span::default(),1,&a).unwrap();
        let original=duplicate-1;
        assert!(plan.lease(original).unwrap().same_binding(&first));
        assert!(plan.lease(duplicate).unwrap().same_binding(&repeat));
        assert!(!plan.lease(original).unwrap().same_binding(&plan.lease(duplicate).unwrap()));
        assert!(!Arc::ptr_eq(&plan.occurrence(original).unwrap().path,&plan.occurrence(duplicate).unwrap().path));
        let (key,value)=plan.paths.sources().iter().next().unwrap();
        assert!(std::ptr::eq(key,plan.occurrence(original).unwrap().path.as_ref()));
        assert!(value.same_view(first.source_text()));
        assert_eq!(plan.paths.dependencies().count(),513);
        drop(plan);
        assert_eq!(used.load(Ordering::Acquire),0);
    }
}

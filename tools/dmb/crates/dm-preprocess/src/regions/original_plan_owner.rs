//! Actual directive traversal metadata in the EXISTING DirectivePlan.
//! Original output has no PreparedLine/environment snapshots; the raw driver
//! supplies its one source/token/parser product. This owner funds metadata
//! before allocation and moves its SAME root to final product/Mapping owners.
use super::{DirectivePlan,IncludeOccurrence,IncludeRegion,OrderedItem,MacroEffect,ExpansionSegment};
use crate::{SourceAcquisitionLease,InitialEnvironment,Macro,macro_expansion::OriginalMacroRows as Rows};
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
fn owned_text(text:&str)->io::Result<String>{let mut out=String::new();out.try_reserve_exact(text.len()).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;if out.capacity()>text.len().saturating_mul(4){return Err(io::ErrorKind::OutOfMemory.into())}out.push_str(text);Ok(out)}
fn push<T>(rows:&mut Vec<T>,value:T,root:&mut SettingRootLease,a:&SettingAdmission<'_>)->io::Result<()>{
 poll(a)?;if rows.len()==rows.capacity(){let target=rows.len().checked_add(1).and_then(usize::checked_next_power_of_two).ok_or(io::ErrorKind::OutOfMemory)?;let bound=scaled(target,4)?;let old=scaled(rows.capacity(),mem::size_of::<T>())?;let peak=scaled(bound,mem::size_of::<T>())?;grow(root,peak,a)?;rows.try_reserve_exact(target-rows.len()).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;if rows.capacity()>bound{return Err(io::ErrorKind::OutOfMemory.into())}let actual=scaled(rows.capacity(),mem::size_of::<T>())?;let release=add(old,peak-actual)?;a.shrink(root,release).map_err(|e|a.take_operational_error().unwrap_or(e))?;}rows.push(value);Ok(())
}
/// Move-only actual final map and its existing wrapper's output allocation
/// lease. No Clone/public raw-map escape can duplicate metadata under one lease.
pub(super) struct OriginalFinalMacroMap{map:BTreeMap<String,Macro>,credit:SettingRootLease}
impl OriginalFinalMacroMap{pub(super) fn from_environment(environment:super::environment::OriginalEnvironment,a:&SettingAdmission<'_>)->io::Result<Self>{let(map,credit)=environment.into_final_macros_using(a)?;Ok(Self{map,credit})}}
pub(super) struct OriginalPlanOwner{plan:DirectivePlan,current_region:Option<usize>,failed:bool,final_macro_credit:Option<SettingRootLease>,credit:SettingRootLease}
impl OriginalPlanOwner{
 pub(super) fn new(project:&Path,initial:InitialEnvironment,defines:&BTreeMap<String,String>,revision:Option<u64>,a:&SettingAdmission<'_>)->io::Result<Self>{
  poll(a)?;if initial!=InitialEnvironment::OriginalChecker0290{return Err(io::ErrorKind::InvalidInput.into())}
  let mut credit=a.reserve(add(mem::size_of::<Self>(),path_bound(project.parent().unwrap_or_else(||Path::new("")))?)?).map_err(|e|a.take_operational_error().unwrap_or(e))?;
  let mut plan=DirectivePlan::default();plan.initial_environment=initial;plan.input_revision=revision;plan.project_dir=owned_path(project.parent().unwrap_or_else(||Path::new("")))?;
  for(name,replacement)in defines{poll(a)?;let bytes=add(node::<String,String>()?,scaled(add(name.len(),replacement.len())?,4)?)?;grow(&mut credit,bytes,a)?;plan.defines.insert(owned_text(name)?,owned_text(replacement)?);}
  Ok(Self{plan,current_region:None,failed:false,final_macro_credit:None,credit})
 }
 fn check(&mut self,a:&SettingAdmission<'_>)->io::Result<()>{if self.failed{return Err(io::ErrorKind::InvalidInput.into())}let result=if !a.matches_lease_domain(&self.credit){Err(io::ErrorKind::InvalidInput.into())}else{poll(a)};if result.is_err(){self.failed=true}result}
 pub(super) fn plan(&self)->&DirectivePlan{&self.plan}
 /// Only the actual admitted read/recorded acquisition path supplies a lease.
 /// No normalization/preparation/reopen occurs; decoded line metadata is DATA
 /// over that SAME facade, while all Original token points stay raw-issued.
 pub(super) fn register_opened_using(&mut self,path:&Path,lease:SourceAcquisitionLease,parent:Option<usize>,directive_span:Span,directive_line:usize,a:&SettingAdmission<'_>)->io::Result<usize>{
  self.check(a)?;let result=self.register_inner(path,lease,parent,directive_span,directive_line,a);if result.is_err(){self.failed=true}result
 }
 fn register_inner(&mut self,path:&Path,lease:SourceAcquisitionLease,parent:Option<usize>,directive_span:Span,directive_line:usize,a:&SettingAdmission<'_>)->io::Result<usize>{
  if parent.is_some_and(|p|p>=self.plan.occurrences.len()){return Err(io::ErrorKind::InvalidInput.into())}
  let occurrence=self.plan.occurrences.len();let text=lease.source_text();let key_exists=self.plan.source_texts.contains_key(path);
  if self.plan.source_texts.get(path).is_some_and(|previous|previous.as_str()!=text.as_str()){return Err(io::Error::new(io::ErrorKind::InvalidInput,"same captured source path changed during actual traversal"))}
  let mut metadata=add(path_bound(path)?,scaled(mem::size_of::<usize>(),8)?)?;
  metadata=add(metadata,node::<usize,SourceAcquisitionLease>()?)?;
  if !self.plan.dependencies.contains(path){metadata=add(metadata,add(node::<PathBuf,()>()?,path_bound(path)?)?)?;}
  if !key_exists{metadata=add(metadata,add(node::<PathBuf,crate::SourceText>()?,path_bound(path)?)?)?;}
  let semantic=path.to_str().ok_or_else(||io::Error::new(io::ErrorKind::Unsupported,"actual semantic source path is not UTF8"))?;metadata=add(metadata,add(scaled(semantic.len(),4)?,4*mem::size_of::<usize>())?)?;grow(&mut self.credit,metadata,a)?;
  let path=Arc::new(owned_path(path)?);let semantic_path:Arc<str>=Arc::from(semantic);
  let row=IncludeOccurrence{path:Arc::clone(&path),semantic_path,original_entry:if parent.is_none(){Some(Arc::clone(&path))}else{None},parent,directive_span,directive_line,suppressed:false,non_text_kind:None,return_cursor:None,eof_cursor_line:None,eof_cursor_encounter:None};
  push(&mut self.plan.occurrences,row,&mut self.credit,a)?;
  if !key_exists{
   // No eager full-file line scan: raw geometry is issued by the SAME
   // demanded lexical frames. Generic decoded line tables are deliberately
   // absent; raw OriginArena rows own the authenticated line/span mapping.
   self.plan.source_texts.insert(owned_path(&path)?,text.clone());
  }
  if !self.plan.dependencies.contains(path.as_path()){self.plan.dependencies.insert(owned_path(&path)?);}
  self.plan.source_acquisitions.insert(occurrence,lease);self.current_region=None;Ok(occurrence)
 }
 /// Actual emitted token chooses a region from its current registered physical
 /// occurrence. A return from a real child starts another encounter segment;
 /// no environment snapshot or PreparedLine is fabricated for raw output.
 pub(super) fn region_for_emission_using(&mut self,occurrence:usize,decoded_row:Span,a:&SettingAdmission<'_>)->io::Result<usize>{
  self.check(a)?;let result=(||{let lease=self.plan.source_acquisitions.get(&occurrence).ok_or(io::ErrorKind::InvalidInput)?;if decoded_row.start>decoded_row.end||decoded_row.end>lease.source_text().as_str().len(){return Err(io::ErrorKind::InvalidInput.into())}
   if let Some(index)=self.current_region{let row=&mut self.plan.regions[index];if row.occurrence==occurrence{row.source_span.start=row.source_span.start.min(decoded_row.start);row.source_span.end=row.source_span.end.max(decoded_row.end);return Ok(index)}}
   grow(&mut self.credit,2*(mem::size_of::<Vec<ExpansionSegment>>()+4*mem::size_of::<usize>()),a)?;let index=self.plan.regions.len();let region=IncludeRegion{occurrence,source_span:decoded_row,encounter_ordinal:self.plan.items.len(),manifest_source:self.plan.occurrences[occurrence].path.extension().is_some_and(|e|e=="dme"),segments:Arc::new(Vec::new()),effects:Arc::<Vec<MacroEffect>>::new(Vec::new())};push(&mut self.plan.regions,region,&mut self.credit,a)?;push(&mut self.plan.items,OrderedItem::Text(index),&mut self.credit,a)?;self.current_region=Some(index);Ok(index)
  })();if result.is_err(){self.failed=true}result
 }

 pub(super) fn occurrence(&self,index:usize)->io::Result<&IncludeOccurrence>{self.plan.occurrences.get(index).ok_or_else(||io::ErrorKind::InvalidInput.into())}
 pub(super) fn lease(&self,index:usize)->io::Result<SourceAcquisitionLease>{self.plan.source_acquisitions.get(&index).cloned().ok_or_else(||io::ErrorKind::InvalidInput.into())}
 pub(super) fn semantic_path_using(&mut self,index:usize,semantic:&Path,a:&SettingAdmission<'_>)->io::Result<()>{self.check(a)?;let spelling=semantic.to_str().ok_or(io::ErrorKind::InvalidInput)?;grow(&mut self.credit,add(scaled(spelling.len(),4)?,4*mem::size_of::<usize>())?,a)?;self.plan.occurrences.get_mut(index).ok_or(io::ErrorKind::InvalidInput)?.semantic_path=Arc::from(spelling);Ok(())}
 pub(super) fn charge_using(&mut self,bytes:usize,a:&SettingAdmission<'_>)->io::Result<()>{self.check(a)?;grow(&mut self.credit,bytes,a)}
 pub(super) fn definition_using(&self,origin:crate::macro_expansion::OriginalMacroOrigin,driver:&mut super::original_driver::RawSourceDriver,provider:&dyn crate::SourceProvider,a:&SettingAdmission<'_>)->io::Result<super::DefinitionOrigin>{let occurrence=self.occurrence(origin.occurrence)?;let lease=self.lease(origin.occurrence)?;let row=driver.physical_row_using(origin,&lease,provider,a)?;let end=driver.decoded_offset_using(origin.occurrence,&lease,origin.physical.end,a)?;Ok(super::DefinitionOrigin{path:Arc::clone(&occurrence.path),source_span:Span::new(row.point.source_offset,end),source_line:row.point.line})}
 pub(super) fn add_dependency_using(&mut self,path:&Path,a:&SettingAdmission<'_>)->io::Result<()>{self.check(a)?;if !self.plan.dependencies.contains(path){grow(&mut self.credit,add(node::<PathBuf,()>()?,path_bound(path)?)?,a)?;self.plan.dependencies.insert(owned_path(path)?);}Ok(())}
 pub(super) fn add_non_text_using(&mut self,path:&Path,parent:usize,span:Span,line:usize,kind:super::NonTextKind,a:&SettingAdmission<'_>)->io::Result<usize>{self.check(a)?;self.add_dependency_using(path,a)?;grow(&mut self.credit,add(path_bound(path)?,scaled(path.as_os_str().len(),4)?)?,a)?;let path=Arc::new(owned_path(path)?);let semantic_path:Arc<str>=Arc::from(path.to_str().ok_or(io::ErrorKind::InvalidInput)?);let occurrence=self.plan.occurrences.len();push(&mut self.plan.occurrences,IncludeOccurrence{path,semantic_path,original_entry:None,parent:Some(parent),directive_span:span,directive_line:line,suppressed:false,non_text_kind:Some(kind),return_cursor:None,eof_cursor_line:None,eof_cursor_encounter:None},&mut self.credit,a)?;push(&mut self.plan.items,OrderedItem::NonText{occurrence,kind},&mut self.credit,a)?;self.current_region=None;Ok(occurrence)}
 pub(super) fn add_omitted_using(&mut self,path:&Path,parent:usize,span:Span,line:usize,a:&SettingAdmission<'_>)->io::Result<usize>{self.check(a)?;self.add_dependency_using(path,a)?;grow(&mut self.credit,add(path_bound(path)?,scaled(path.as_os_str().len(),4)?)?,a)?;let path=Arc::new(owned_path(path)?);let semantic_path:Arc<str>=Arc::from(path.to_str().ok_or(io::ErrorKind::InvalidInput)?);let occurrence=self.plan.occurrences.len();push(&mut self.plan.occurrences,IncludeOccurrence{path,semantic_path,original_entry:None,parent:Some(parent),directive_span:span,directive_line:line,suppressed:false,non_text_kind:None,return_cursor:None,eof_cursor_line:None,eof_cursor_encounter:None},&mut self.credit,a)?;self.current_region=None;Ok(occurrence)}
 pub(super) fn add_file_dir_using(&mut self,path:&Path,a:&SettingAdmission<'_>)->io::Result<()>{self.check(a)?;grow(&mut self.credit,path_bound(path)?,a)?;push(&mut self.plan.file_dirs,owned_path(path)?,&mut self.credit,a)}

 pub(super) fn absorb_using(&mut self,other:&mut SettingRootLease,a:&SettingAdmission<'_>)->io::Result<()>{self.check(a)?;a.absorb(&mut self.credit,other).map_err(|e|a.take_operational_error().unwrap_or(e))}
 pub(super) fn trace_using(&mut self,actual:&super::original_output_trace::OriginalOutputTrace,driver:&mut super::original_driver::RawSourceDriver,provider:&dyn crate::SourceProvider,a:&SettingAdmission<'_>)->io::Result<Arc<Vec<super::MacroExpansion>>>{
  self.check(a)?;let mut rows=Vec::new();grow(&mut self.credit,4*mem::size_of::<usize>(),a)?;
  actual.visit_inner_to_outer_using(a,|entry|{let name_bytes=add(scaled(entry.name.len(),4)?,4*mem::size_of::<usize>())?;grow(&mut self.credit,name_bytes,a)?;let name:Arc<str>=Arc::from(entry.name);let definition=entry.definition.map(|origin|self.definition_using(origin,driver,provider,a)).transpose()?;grow(&mut self.credit,4*mem::size_of::<usize>(),a)?;let expansion=super::MacroExpansion{name,invocation_span:entry.origin.physical,replacement_chain:Arc::from([]),definition};push(&mut rows,expansion,&mut self.credit,a)})?;
  rows.reverse();
  // Replacement-chain ancestry is taken only from this SAME saved emission
  // trace; no current-after-pop stack or second macro lookup is consulted.
  for at in 0..rows.len(){grow(&mut self.credit,add(scaled(at,8*mem::size_of::<Arc<str>>())?,4*mem::size_of::<usize>())?,a)?;let mut parents=Vec::new();parents.try_reserve_exact(at).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;if parents.capacity()>at.saturating_mul(4){return Err(io::ErrorKind::OutOfMemory.into())}for parent in &rows[..at]{parents.push(Arc::clone(&parent.name));}rows[at].replacement_chain=Arc::from(parents);}
  Ok(Arc::new(rows))
 }
 pub(super) fn finish_using(mut self,final_macros:OriginalFinalMacroMap,a:&SettingAdmission<'_>)->io::Result<(DirectivePlan,SharedSettingRetention,SettingRootLease)>{
  // Keep the incoming map before its credit until all fallible preconditions
  // pass; after adoption plan still drops before either retained root.
  self.check(a)?;if !a.matches_lease_domain(&final_macros.credit){return Err(io::ErrorKind::InvalidInput.into())}
  grow(&mut self.credit,mem::size_of::<SettingRootLease>()+4*mem::size_of::<usize>(),a)?;
  let OriginalFinalMacroMap{map,credit}=final_macros;self.plan.final_macros=map;self.final_macro_credit=Some(credit);
  let macro_credit=self.final_macro_credit.take().ok_or(io::ErrorKind::InvalidData)?;let Self{plan,credit,..}=self;Ok((plan,SharedSettingRetention::new(credit),macro_credit))
 }
}

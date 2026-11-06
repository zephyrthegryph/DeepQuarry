//! Restricted actual Original diagnostic metadata. There is deliberately no
//! Deref, generic plan getter, compiler conversion or physical/model EOF grant.
use super::{DirectivePlan,GenerationOmissions,SourcePlanGeometry,IncludeOccurrence,IncludeRegion,OrderedItem,original_rich_notices::OriginalRichNotices,original_define_history::OriginalDefineHistory};
use crate::{SourceText,SourceAcquisitionLease,Macro,Diagnostic};use dm_syntax::{SettingAdmission,SettingRootLease,SharedSettingRetention};
use std::{io,sync::Arc,path::PathBuf,collections::{BTreeMap,BTreeSet}};
/// Physical rows precede every matching retained resource counter.
pub(super) struct OriginalScriptInclude{pub(super) path:super::original_file_path::OriginalFilePath,pub(super) at:crate::macro_expansion::OriginalMacroOrigin}
pub(super) struct OriginalPlanRetention{pub(super) scripts:crate::macro_expansion::OriginalMacroRows<OriginalScriptInclude>,pub(super) notices:OriginalRichNotices,pub(super) history:OriginalDefineHistory,pub(super) conditionals:super::original_conditional_history::OriginalConditionalHistory,pub(super) metadata:SharedSettingRetention,pub(super) final_macros:super::environment::OriginalFinalMacros}
struct Inner{plan:DirectivePlan,retention:OriginalPlanRetention,control:SettingRootLease}
pub struct OriginalDiagnosticPlan(Option<Arc<Inner>>);
impl Clone for OriginalDiagnosticPlan{fn clone(&self)->Self{Self(Some(Arc::clone(self.0.as_ref().expect("actual diagnostic owner"))))}}
impl Drop for OriginalDiagnosticPlan{fn drop(&mut self){if let Some(owner)=self.0.take(){if let Some(inner)=Arc::into_inner(owner){drop(inner)}}}}
impl std::fmt::Debug for OriginalDiagnosticPlan{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.debug_struct("OriginalDiagnosticPlan").field("occurrences",&self.occurrences().len()).field("regions",&self.regions().len()).finish_non_exhaustive()}}
/// Actual objects/buffers and explicit existing opaque allocations. A quota
/// estimate is NEVER supplied as a measured heap row. Paths/maps remain borrowed
/// through the neutral getters so the caller's existing census can visit them.
pub enum OriginalDiagnosticStorage{Owner{address:usize,bytes:usize},Buffer{address:usize,logical:usize,capacity:usize},Opaque(&'static str)}
impl OriginalDiagnosticPlan{
 pub(super) fn from_actual_using(plan:DirectivePlan,omissions:&GenerationOmissions,retention:OriginalPlanRetention,a:&SettingAdmission<'_>)->io::Result<Self>{
  a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;if plan.initial_environment!=crate::InitialEnvironment::OriginalChecker0290||omissions.paths().next().is_some()||!retention.metadata.is_admitted_by(a)||!retention.notices.is_admitted_by(a)||!retention.history.is_finalized_by(a)||!retention.conditionals.is_admitted_by(a)||!retention.final_macros.is_admitted_by(a){return Err(io::Error::new(io::ErrorKind::InvalidInput,"diagnostic handoff requires SAME actual Original no-omission product"))}
  let bytes=std::mem::size_of::<Inner>().checked_add(2*std::mem::size_of::<usize>()).ok_or(io::ErrorKind::OutOfMemory)?;let control=a.reserve(bytes).map_err(|e|a.take_operational_error().unwrap_or(e))?;Ok(Self(Some(Arc::new(Inner{plan,retention,control}))))
 }
 fn inner(&self)->&Inner{self.0.as_deref().expect("actual diagnostic owner")}
 pub fn same_owner(&self,other:&Self)->bool{Arc::ptr_eq(self.0.as_ref().unwrap(),other.0.as_ref().unwrap())}
 pub fn initial_environment(&self)->crate::InitialEnvironment{self.inner().plan.initial_environment}
 pub fn root_source(&self)->Option<&std::path::Path>{self.occurrences().first().map(|row|row.path.as_path())}
 pub fn source_geometry(&self)->SourcePlanGeometry<'_>{self.inner().plan.source_geometry()}
 pub fn occurrences(&self)->&Vec<IncludeOccurrence>{&self.inner().plan.occurrences}
 pub fn regions(&self)->&Vec<IncludeRegion>{&self.inner().plan.regions}
 pub fn items(&self)->&Vec<OrderedItem>{&self.inner().plan.items}
 pub fn file_dirs(&self)->&Vec<PathBuf>{&self.inner().plan.file_dirs}
 pub fn source_acquisitions(&self)->&super::SourceAcquisitions{&self.inner().plan.source_acquisitions}
 pub fn source_texts(&self)->&BTreeMap<PathBuf,SourceText>{&self.inner().plan.source_texts}
 pub fn source_line_starts(&self)->&BTreeMap<PathBuf,Arc<[usize]>>{&self.inner().plan.source_line_starts}
 pub fn project_dir(&self)->&PathBuf{&self.inner().plan.project_dir}
 pub fn final_macro(&self,name:&str)->Option<&Macro>{self.inner().retention.final_macros.get(name)}
 pub fn final_macros(&self)->impl ExactSizeIterator<Item=(&str,&Macro)>{self.inner().retention.final_macros.iter()}
 pub fn dependencies(&self)->&BTreeSet<PathBuf>{&self.inner().plan.dependencies}
 pub fn defines(&self)->&BTreeMap<String,String>{&self.inner().plan.defines}
 pub fn diagnostics(&self)->&Vec<Diagnostic>{&self.inner().plan.diagnostics}
 pub fn warnings(&self)->&Vec<Diagnostic>{&self.inner().plan.warnings}
 pub fn diagnostic_ordinals(&self)->&Vec<usize>{&self.inner().plan.diagnostic_ordinals}
 pub fn input_revision(&self)->Option<u64>{self.inner().plan.input_revision}
 pub fn original_notices(&self)->&OriginalRichNotices{&self.inner().retention.notices}
 pub fn conditional_ranges(&self)->impl Iterator<Item=super::OriginalConditionalRange>+'_ {self.inner().retention.conditionals.iter()}
 /// Actual .dms selections in encounter order, duplicates preserved. No
 /// script payload/acquisition/physical EOF is granted by metadata existence.
 pub fn script_includes(&self)->impl Iterator<Item=(&std::path::Path,super::OriginalNoticePlace)>+'_ {self.inner().retention.scripts.as_slice().iter().map(|row|(row.path.path(),super::OriginalNoticePlace::Actual{occurrence:row.at.occurrence,line:row.at.line,column:row.at.byte_column.expect("actual include source point"),raw_span:Some(row.at.physical)}))}
 pub fn original_sources(&self)->impl Iterator<Item=(&std::path::Path,Option<&SourceAcquisitionLease>)>{self.occurrences().iter().enumerate().filter_map(|(at,row)|row.non_text_kind().is_none().then(||(row.path.as_path(),self.source_acquisitions().get(&at))))}
 pub fn visit_storage(&self,mut visit:impl FnMut(OriginalDiagnosticStorage)){
  let owner=self.0.as_ref().unwrap();owner.retention.notices.visit_storage(|address,logical,capacity|visit(OriginalDiagnosticStorage::Buffer{address,logical,capacity}));owner.retention.scripts.visit_allocation(|address,capacity|visit(OriginalDiagnosticStorage::Buffer{address,logical:owner.retention.scripts.len()*std::mem::size_of::<OriginalScriptInclude>(),capacity}));for row in owner.retention.scripts.as_slice(){row.path.visit_storage(|address,logical,capacity|visit(OriginalDiagnosticStorage::Buffer{address,logical,capacity}));}owner.retention.conditionals.visit_storage(|address,logical,capacity|visit(OriginalDiagnosticStorage::Buffer{address,logical,capacity}));visit(OriginalDiagnosticStorage::Owner{address:Arc::as_ptr(owner)as usize,bytes:std::mem::size_of::<Inner>()+2*std::mem::size_of::<usize>()});owner.control.visit_counter_storage(|address,bytes|visit(OriginalDiagnosticStorage::Owner{address,bytes:bytes+2*std::mem::size_of::<usize>()}));owner.retention.final_macros.visit_storage(|address,logical,capacity|visit(OriginalDiagnosticStorage::Buffer{address,logical,capacity}));owner.retention.metadata.visit_storage(|address,bytes|visit(OriginalDiagnosticStorage::Owner{address,bytes:bytes+2*std::mem::size_of::<usize>()}));
  owner.plan.source_acquisitions.visit_original_storage(|address,logical,capacity|visit(OriginalDiagnosticStorage::Buffer{address,logical,capacity}));
  macro_rules! rows{($field:ident,$t:ty)=>{{let rows=&owner.plan.$field;if rows.capacity()!=0{visit(OriginalDiagnosticStorage::Buffer{address:rows.as_ptr()as usize,logical:rows.len()*std::mem::size_of::<$t>(),capacity:rows.capacity()*std::mem::size_of::<$t>()});}}}}
  rows!(occurrences,IncludeOccurrence);rows!(regions,IncludeRegion);rows!(items,OrderedItem);rows!(diagnostic_ordinals,usize);rows!(diagnostics,Diagnostic);rows!(warnings,Diagnostic);rows!(file_dirs,PathBuf);
  // Existing persistent map/B-tree allocation geometry is not public. The
  // caller must mark this closure opaque and use neutral getters for payloads;
  // retaining a conservative resource allowance does not make it measured.
  visit(OriginalDiagnosticStorage::Opaque("diagnostic plan maps/sets, nested region Arc arrays and rich notice/history rows require their actual payload visitors; no reservation is a heap measurement"));
 }
}

#[cfg(test)]mod tests{
 use super::*;use std::sync::atomic::{AtomicUsize,Ordering};
 fn retention(a:&SettingAdmission<'_>)->OriginalPlanRetention{let mut history=OriginalDefineHistory::new(a).unwrap();history.capture_current_using(&super::super::environment::MacroEnvironment::default(),a).unwrap();OriginalPlanRetention{scripts:crate::macro_expansion::OriginalMacroRows::new(a).unwrap(),notices:OriginalRichNotices::new(a).unwrap(),history,conditionals:super::super::original_conditional_history::OriginalConditionalHistory::new(a).unwrap(),metadata:SharedSettingRetention::new(a.reserve(1024).unwrap()),final_macros:super::super::environment::OriginalFinalMacros::empty(a).unwrap()}}
 fn empty()->GenerationOmissions{GenerationOmissions::probe(std::iter::empty(),&mut |_|panic!("no path is probed"),&mut |_|Ok(())).unwrap()}
 #[test]fn metadata_only_clone_shares_restricted_owner_and_keeps_actual_credit_until_last_alias(){
  // This constructor test grants no source, primary, parser or model role.
  let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,8<<20,&||Ok(()));let mut plan=DirectivePlan::default();plan.initial_environment=crate::InitialEnvironment::OriginalChecker0290;let owner=OriginalDiagnosticPlan::from_actual_using(plan,&empty(),retention(&a),&a).unwrap();let alias=owner.clone();assert!(owner.same_owner(&alias));assert!(owner.original_sources().next().is_none());assert!(owner.root_source().is_none());assert!(owner.occurrences().is_empty());let mut opaque=false;owner.visit_storage(|view|if matches!(view,OriginalDiagnosticStorage::Opaque(_)){opaque=true});assert!(opaque,"opaque maps must not become fabricated exact heap totals");drop(owner);assert!(used.load(Ordering::Acquire)>0);drop(alias);assert_eq!(used.load(Ordering::Acquire),0);
 }
 #[test]fn diagnostic_handoff_rejects_any_omission_and_foreign_retained_resource_domain(){
  let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,8<<20,&||Ok(()));let omissions=GenerationOmissions::probe([PathBuf::from("E:/no-role/generated.dm")],&mut |_|Ok(true),&mut |_|Ok(())).unwrap();let mut plan=DirectivePlan::default();plan.initial_environment=crate::InitialEnvironment::OriginalChecker0290;assert_eq!(OriginalDiagnosticPlan::from_actual_using(plan,&omissions,retention(&a),&a).unwrap_err().kind(),io::ErrorKind::InvalidInput);assert_eq!(used.load(Ordering::Acquire),0);let other=Arc::new(AtomicUsize::new(0));let b=SettingAdmission::new(&other,8<<20,&||Ok(()));let mut plan=DirectivePlan::default();plan.initial_environment=crate::InitialEnvironment::OriginalChecker0290;assert_eq!(OriginalDiagnosticPlan::from_actual_using(plan,&empty(),retention(&a),&b).unwrap_err().kind(),io::ErrorKind::InvalidInput);assert_eq!(used.load(Ordering::Acquire),0);assert_eq!(other.load(Ordering::Acquire),0);
 }
}

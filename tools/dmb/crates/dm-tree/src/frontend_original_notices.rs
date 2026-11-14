//! Borrowed actual Original preprocessor diagnostics. Raw byte coordinates are
//! never converted to expanded syntax spans or used as source-role authority.
use super::{DiagnosticSourceView,FrontendDirectivePlan,SourceExportMapping};
use dm_preprocess::{SourceAcquisitionLease,regions::{OriginalDiagnosticPlan,OriginalNoticePlace,OriginalNoticeSeverity,OriginalNoticeNotes}};
use std::path::Path;
#[derive(Clone,Copy,Debug)]
pub enum OriginalDiagnosticPoint<'a>{
 Default,Builtins,
 Acquired{occurrence:usize,source_path:&'a Path,reported_path:&'a Path,
  acquisition:&'a SourceAcquisitionLease,line:usize,byte_column:usize,
  raw_span:Option<dm_syntax::Span>},
}
pub struct OriginalPreprocessNotice<'a>{pub point:OriginalDiagnosticPoint<'a>,pub severity:OriginalNoticeSeverity,pub error_type:Option<&'static str>,pub message:&'a str,pub notes:OriginalPreprocessNotes<'a>,pub registration:Option<&'a dm_preprocess::regions::OriginalNoticeRegistration>}
pub struct OriginalPreprocessNotices<'a>{plan:&'a OriginalDiagnosticPlan,mapping:Option<&'a SourceExportMapping>}
pub struct OriginalPreprocessNotes<'a>{plan:&'a OriginalDiagnosticPlan,mapping:Option<&'a SourceExportMapping>,notes:OriginalNoticeNotes<'a>}
fn point<'a>(plan:&'a OriginalDiagnosticPlan,mapping:Option<&'a SourceExportMapping>,place:OriginalNoticePlace)->Result<OriginalDiagnosticPoint<'a>,&'static str>{
 Ok(match place{
  OriginalNoticePlace::Default=>OriginalDiagnosticPoint::Default,
  OriginalNoticePlace::Builtins=>OriginalDiagnosticPoint::Builtins,
  OriginalNoticePlace::Actual{occurrence,line,column,raw_span}=>{
   let row=plan.occurrences().get(occurrence).ok_or("Original diagnostic occurrence absent")?;
   let acquisition=plan.source_acquisitions().get(&occurrence).ok_or("Original diagnostic acquisition absent")?;
   let reported_path=if let Some(mapping)=mapping{
    let mapped=mapping.source_acquisition(occurrence).ok_or("Original diagnostic mapped acquisition absent")?;
    if !mapped.same_binding(acquisition){return Err("Original diagnostic belongs to another acquisition")}
    mapping.registered_checker_path(occurrence)?
   }else{
    // A strict parser fatal legitimately has no completed SourceExportMapping.
    // Borrow only the actual no-omission plan's private retained occurrence.
    super::source_export_mapping::registered_original_checker_path(row.parent.is_none(),row.original_entry_path().map(|path|path.as_path()),plan.occurrences().first().and_then(|row|row.original_entry_path()).map(|path|path.as_path()),row.semantic_path.as_ref())?
   };
   OriginalDiagnosticPoint::Acquired{occurrence,source_path:row.path.as_path(),reported_path,acquisition,line,byte_column:column,raw_span}
  }
 })
}
impl DiagnosticSourceView<'_>{
 /// This view already authenticates the exact graph/archive/mapping owner.
 /// Borrow only the actual retained diagnostic plan; ordinary plans have no
 /// Original notices, and no full/compiler/EOF grant follows from this DATA.
 pub fn original_preprocess_notices(&self)->Option<OriginalPreprocessNotices<'_>>{
  match self.original_plan(){FrontendDirectivePlan::OriginalDiagnostic(plan)=>Some(OriginalPreprocessNotices{plan,mapping:Some(self.mapping())}),FrontendDirectivePlan::Ordinary(_)=>None}
 }
}
impl<'a> OriginalPreprocessNotices<'a>{
 pub fn len(&self)->usize{self.plan.original_notices().len()}
 pub fn is_empty(&self)->bool{self.plan.original_notices().is_empty()}
 pub fn iter(&self)->impl Iterator<Item=Result<OriginalPreprocessNotice<'a>,&'static str>>+'_ {
  let plan=self.plan;let mapping=self.mapping;
  plan.original_notices().iter().map(move|row|Ok(OriginalPreprocessNotice{point:point(plan,mapping,row.place)?,severity:row.severity,error_type:row.error_type,message:row.message,notes:OriginalPreprocessNotes{plan,mapping,notes:row.notes},registration:row.registration}))
 }
}
impl<'a> Iterator for OriginalPreprocessNotes<'a>{
 type Item=Result<(OriginalDiagnosticPoint<'a>,&'a str),&'static str>;
 fn next(&mut self)->Option<Self::Item>{self.notes.next().map(|(at,text)|point(self.plan,self.mapping,at).map(|at|(at,text)))}
}

/// Only the concrete returned fatal report's actual restricted owner calls this.
pub(super) fn failed_original_notices(plan:&OriginalDiagnosticPlan)->OriginalPreprocessNotices<'_>{OriginalPreprocessNotices{plan,mapping:None}}

/// Inline source-epoch replay owner. Its existing plan/mapping Arc allocations
/// stay funded by their genuine producers. No new control/counter is created.
pub struct OriginalPreprocessNoticeOwner{plan:OriginalDiagnosticPlan,mapping:std::sync::Arc<SourceExportMapping>}
pub enum OriginalPreprocessNoticeStorage<'a>{
 Metadata(dm_preprocess::regions::OriginalDiagnosticStorage),
 Mapping(&'a std::sync::Arc<SourceExportMapping>),
 Acquisition(&'a SourceAcquisitionLease),
 Path(&'a std::sync::Arc<std::path::PathBuf>),
}
impl DiagnosticSourceView<'_>{
 /// Only this genuine current view can issue the replay owner. Empty actual
 /// notices remain retained, distinct from ordinary and pressure-released.
 pub fn retain_original_preprocess_notices(&self)->Option<OriginalPreprocessNoticeOwner>{match self.original_plan(){FrontendDirectivePlan::OriginalDiagnostic(plan)=>Some(OriginalPreprocessNoticeOwner{plan:plan.clone(),mapping:std::sync::Arc::clone(self.mapping())}),FrontendDirectivePlan::Ordinary(_)=>None}}
}
impl OriginalPreprocessNoticeOwner{
 pub fn borrow(&self)->OriginalPreprocessNotices<'_>{OriginalPreprocessNotices{plan:&self.plan,mapping:Some(&self.mapping)}}
 pub fn matches_mapping(&self,mapping:&SourceExportMapping)->bool{std::ptr::eq(self.mapping.as_ref(),mapping)}
 pub fn visit_storage(&self,mut visit:impl FnMut(OriginalPreprocessNoticeStorage<'_>)){
  self.plan.visit_storage(|v|visit(OriginalPreprocessNoticeStorage::Metadata(v)));visit(OriginalPreprocessNoticeStorage::Mapping(&self.mapping));
  for acquisition in self.plan.source_acquisitions().values(){visit(OriginalPreprocessNoticeStorage::Acquisition(acquisition));}
  for row in self.plan.occurrences(){visit(OriginalPreprocessNoticeStorage::Path(&row.path));}
 }
}

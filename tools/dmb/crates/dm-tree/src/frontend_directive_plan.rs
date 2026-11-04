//! Typed ownership of compiler directive data vs genuine Original diagnostics.
//! Diagnostic source geometry is borrowed DATA; no generic plan unwrap exists.
use super::*;
#[derive(Clone,Debug)]pub enum FrontendDirectivePlan{Ordinary(DirectivePlan),OriginalDiagnostic(dm_preprocess::regions::OriginalDiagnosticPlan)}
impl From<DirectivePlan> for FrontendDirectivePlan{fn from(plan:DirectivePlan)->Self{Self::Ordinary(plan)}}
impl FrontendDirectivePlan{
 pub fn ordinary(&self)->Option<&DirectivePlan>{match self{Self::Ordinary(plan)=>Some(plan),Self::OriginalDiagnostic(_)=>None}}
 pub fn ordinary_mut(&mut self)->Option<&mut DirectivePlan>{match self{Self::Ordinary(plan)=>Some(plan),Self::OriginalDiagnostic(_)=>None}}
 pub fn is_original_diagnostic(&self)->bool{matches!(self,Self::OriginalDiagnostic(_))}
 pub fn initial_environment(&self)->dm_preprocess::InitialEnvironment{match self{Self::Ordinary(plan)=>plan.initial_environment,Self::OriginalDiagnostic(plan)=>plan.initial_environment()}}
 pub fn source_geometry(&self)->dm_preprocess::regions::SourcePlanGeometry<'_>{match self{Self::Ordinary(plan)=>plan.source_geometry(),Self::OriginalDiagnostic(plan)=>plan.source_geometry()}}
 pub fn source_acquisitions(&self)->&BTreeMap<usize,dm_preprocess::SourceAcquisitionLease>{match self{Self::Ordinary(plan)=>&plan.source_acquisitions,Self::OriginalDiagnostic(plan)=>plan.source_acquisitions()}}
 pub fn source_texts(&self)->&BTreeMap<PathBuf,dm_preprocess::SourceText>{match self{Self::Ordinary(plan)=>&plan.source_texts,Self::OriginalDiagnostic(plan)=>plan.source_texts()}}
 pub fn source_line_starts(&self)->&BTreeMap<PathBuf,Arc<[usize]>>{match self{Self::Ordinary(plan)=>&plan.source_line_starts,Self::OriginalDiagnostic(plan)=>plan.source_line_starts()}}
 pub fn occurrences(&self)->&Vec<dm_preprocess::regions::IncludeOccurrence>{match self{Self::Ordinary(plan)=>&plan.occurrences,Self::OriginalDiagnostic(plan)=>plan.occurrences()}}
 pub fn regions(&self)->&Vec<dm_preprocess::regions::IncludeRegion>{match self{Self::Ordinary(plan)=>&plan.regions,Self::OriginalDiagnostic(plan)=>plan.regions()}}
 pub fn items(&self)->&Vec<dm_preprocess::regions::OrderedItem>{match self{Self::Ordinary(plan)=>&plan.items,Self::OriginalDiagnostic(plan)=>plan.items()}}
 pub fn dependencies(&self)->&std::collections::BTreeSet<PathBuf>{match self{Self::Ordinary(plan)=>&plan.dependencies,Self::OriginalDiagnostic(plan)=>plan.dependencies()}}
 pub fn diagnostics(&self)->&Vec<dm_preprocess::Diagnostic>{match self{Self::Ordinary(plan)=>&plan.diagnostics,Self::OriginalDiagnostic(plan)=>plan.diagnostics()}}
 pub fn warnings(&self)->&Vec<dm_preprocess::Diagnostic>{match self{Self::Ordinary(plan)=>&plan.warnings,Self::OriginalDiagnostic(plan)=>plan.warnings()}}
 pub fn diagnostic_ordinals(&self)->&Vec<usize>{match self{Self::Ordinary(plan)=>&plan.diagnostic_ordinals,Self::OriginalDiagnostic(plan)=>plan.diagnostic_ordinals()}}
 pub fn final_macros(&self)->&BTreeMap<String,dm_preprocess::Macro>{match self{Self::Ordinary(plan)=>&plan.final_macros,Self::OriginalDiagnostic(plan)=>plan.final_macros()}}
 pub fn file_dirs(&self)->&Vec<PathBuf>{match self{Self::Ordinary(plan)=>&plan.file_dirs,Self::OriginalDiagnostic(plan)=>plan.file_dirs()}}
 pub fn project_dir(&self)->&PathBuf{match self{Self::Ordinary(plan)=>&plan.project_dir,Self::OriginalDiagnostic(plan)=>plan.project_dir()}}
 pub fn defines(&self)->&BTreeMap<String,String>{match self{Self::Ordinary(plan)=>&plan.defines,Self::OriginalDiagnostic(plan)=>plan.defines()}}
 pub fn input_revision(&self)->Option<u64>{match self{Self::Ordinary(plan)=>plan.input_revision,Self::OriginalDiagnostic(plan)=>plan.input_revision()}}
 pub fn non_text(&self,kind:NonTextKind)->impl Iterator<Item=&Path>{self.items().iter().filter_map(move|item|match item{dm_preprocess::regions::OrderedItem::NonText{occurrence,kind:item_kind}if *item_kind==kind=>Some(self.occurrences()[*occurrence].path.as_path()),_=>None})}
 pub fn original_owner_storage(&self,visit:&mut dyn FnMut(dm_preprocess::regions::OriginalDiagnosticStorage)){if let Self::OriginalDiagnostic(plan)=self{plan.visit_storage(visit)}}
}

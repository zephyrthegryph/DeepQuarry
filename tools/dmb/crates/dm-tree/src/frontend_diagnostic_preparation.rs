//! Diagnostic-only preparation over ONE original native frontend pass.
//! No alternate parser, model, normalized member table or runtime ABI receipt.
use super::*;
use crate::diagnostic_declarations::DiagnosticDeclarationReceipt;
use crate::SemanticTree;
pub struct DiagnosticFrontend {
    inner: ColdFrontend,
    receipt: Arc<DiagnosticDeclarationReceipt>,
    archive: Arc<BodyArchive>,
    retained_records: Option<Arc<super::DiagnosticRetainedRecords>>,
}
/// Sealed borrowed projection of existing handles, never an alternate Sem model.
/// Only the original diagnostic preparation can issue this view.
pub struct DiagnosticSourceView<'a> {
    owner: &'a DiagnosticFrontend,
}
impl DiagnosticFrontend {
    pub(super) fn visit_retention_storage(&self,mut visit:impl FnMut(super::AnalysisRetentionStorage<'_>)){
        use super::AnalysisRetentionStorage as V;
        visit(V::Source(DiagnosticSourceView{owner:self}));visit(V::Receipt(&self.receipt));
        if let Some(records)=&self.retained_records{visit(V::Allocation{address:Arc::as_ptr(records)as usize,bytes:std::mem::size_of_val(records.as_ref())});records.visit_storage(&mut visit);}
    }

    pub(super) fn preparation_frontend(&self)->&ColdFrontend { &self.inner }
    pub(super) fn preparation_engine_matches(&self,engine:Option<&EngineSeed>)->bool {
        self.receipt.errors().is_empty() && self.receipt.settings_compilable()
            && self.retained_records.as_ref().is_some_and(|records|records.engine_matches(engine))
            && self.source_view().is_ok()
    }
    pub(super) fn preparation_records(&self)->Option<Arc<super::DiagnosticRetainedRecords>> { self.retained_records.clone() }

    pub(super) fn bind(
        inner: ColdFrontend,
        mut receipt: DiagnosticDeclarationReceipt,
    ) -> Result<Self, Vec<Diagnostic>> {
        if !receipt.authenticates(&inner.snapshot.tree) {
            return Err(vec![internal(
                "diagnostic declaration receipt belongs to another native graph",
            )]);
        }
        let archive = inner
            .body_archive()
            .ok_or_else(|| vec![internal("diagnostic original archive unavailable")])?;
        receipt.settings_compilable=inner.issued_settings.iter().flatten().all(|owner|crate::procedure::settings_compilable(&owner.settings,inner.snapshot.tree.symbols()));
        if !receipt.settings_compilable{receipt.retained_records=None;}
        let retained_records = receipt.retained_records.take();
        Ok(Self {
            retained_records,
            inner,
            receipt: Arc::new(receipt),
            archive,
        })
    }
    pub fn with_body_queries(self, host: Arc<dyn BodySyntaxQueries>) -> Result<Self, String> {
        let Self {
            inner,
            receipt,
            retained_records,
            ..
        } = self;
        let inner = inner.with_body_queries(host);
        let archive = inner
            .body_archive()
            .ok_or("diagnostic current body-query archive unavailable")?;
        Ok(Self {
            inner,
            receipt,
            archive,
            retained_records,
        })
    }
    pub fn source_view(&self) -> Result<DiagnosticSourceView<'_>, String> {
        if !self.receipt.authenticates(&self.inner.snapshot.tree)
            || !self.archive.matches_tree(&self.inner.snapshot.tree)
            || !self
                .inner
                .source_export_mapping()
                .is_some_and(|mapping| Arc::ptr_eq(mapping, self.archive.source_mapping()))
        {
            return Err("diagnostic original source handles no longer agree".into());
        }
        Ok(DiagnosticSourceView { owner: self })
    }
    /// The ordinary compiler can consume this exact original frontend only when
    /// its declaration builder recorded NO compile errors. No second parse/build.
    pub fn try_into_compilable_retained(
        mut self,
        state: &mut RetainedSemanticTree,
    ) -> Result<ColdFrontend, Self> {
        if self.archive.source_mapping().initial_environment()==dm_preprocess::InitialEnvironment::OriginalChecker0290{return Err(self)}
        if self.receipt.settings_compilable() && self.receipt.errors().is_empty()
            && state
                .snapshot_tree()
                .is_some_and(|tree| Arc::ptr_eq(tree, &self.inner.snapshot.tree))
        {
            // Existing complete native entry already owns this exact graph.
            return Ok(self.inner);
        }
        if !self.receipt.settings_compilable() || !self.receipt.errors().is_empty() || self.retained_records.is_none() {
            return Err(self);
        }
        let records = self
            .retained_records
            .take()
            .expect("complete original records checked");
        let records=match Arc::try_unwrap(records){Ok(records)=>records,Err(records)=>{self.retained_records=Some(records);return Err(self)}};
        state
            .adopt_valid_diagnostic_records(records, &self.inner.snapshot)
            .expect("private original diagnostic record owner cannot change");
        Ok(self.inner)
    }
    pub fn try_into_compilable(self) -> Result<ColdFrontend, Self> {
        if self.archive.source_mapping().initial_environment()==dm_preprocess::InitialEnvironment::OriginalChecker0290{return Err(self)}
        if self.receipt.settings_compilable() && self.receipt.errors().is_empty() {
            Ok(self.inner)
        } else {
            Err(self)
        }
    }
}
impl DiagnosticSourceView<'_> {
    pub fn storage_view(&self)->super::FrontendStorageView<'_>{self.owner.inner.storage_view()}
    /// Borrowed preparation DATA only; callers still need their actual current source guard.
    pub fn expanded_text(&self)->&str { self.owner.inner.expanded.text.as_str() }
    /// Borrow the SAME directive plan for actual original-source acquisition joins.
    pub fn original_plan(&self)->&dm_preprocess::regions::DirectivePlan { &self.owner.inner.plan }
    pub fn tree(&self) -> &Arc<SemanticTree> {
        &self.owner.inner.snapshot.tree
    }
    pub fn occurrences(&self) -> &Arc<crate::OccurrenceTable> {
        &self.owner.inner.snapshot.occurrences
    }
    pub fn archive(&self) -> &Arc<BodyArchive> {
        &self.owner.archive
    }
    pub fn mapping(&self) -> &Arc<SourceExportMapping> {
        self.owner.archive.source_mapping()
    }
    pub fn files(&self) -> &Arc<[SourceFile]> {
        &self.owner.inner.files
    }
    pub fn bodies(&self) -> &Arc<[BodyOccurrence]> {
        &self.owner.inner.bodies
    }
    pub fn source_revision(&self) -> u128 {
        self.owner.inner.source_export_revision()
    }
    pub fn receipt(&self) -> &Arc<DiagnosticDeclarationReceipt> {
        &self.owner.receipt
    }
    /// Only actual text occurrences need original semantic-decoding admission.
    /// NonText items remain in includes()/dependency metadata, with their exact
    /// original indices; absence of a text lease never classifies an item.
    pub fn semantic_includes(&self)->impl Iterator<Item=(usize,&Arc<PathBuf>)>{
        self.owner.inner.plan.occurrences.iter().enumerate()
            .filter(|(_,row)|row.non_text_kind().is_none())
            .map(|(index,row)|(index,&row.path))
    }
    pub fn includes(&self) -> impl Iterator<Item = (usize, &Arc<PathBuf>)> {
        self.owner
            .inner
            .plan
            .occurrences
            .iter()
            .enumerate()
            .map(|(index, row)| (index, &row.path))
    }
}

#[cfg(test)]
#[path = "frontend_diagnostic_preparation_tests.rs"]
mod tests;

#[cfg(test)]mod original_analysis_promotion_tests{
 use super::*;
 struct Source(dm_preprocess::AcquiredSource);
 impl dm_preprocess::SourceProvider for Source{
  fn initial_environment(&self)->dm_preprocess::InitialEnvironment{dm_preprocess::InitialEnvironment::OriginalChecker0290}
  fn read(&self,_:&std::path::Path)->Result<String,String>{Err("actual original source acquisition required".into())}
  fn acquired_source(&self,_:&std::path::Path)->Result<Option<dm_preprocess::AcquiredSource>,String>{Ok(Some(self.0.clone()))}
  fn source_acquisition(&self,_:&std::path::Path,text:&dm_preprocess::SourceText)->Option<dm_preprocess::AcquiredSource>{self.0.lease().source_text().same_view(text).then(||self.0.clone())}
 }
 #[test]fn original_analysis_zero_error_diagnostic_owner_cannot_promote_through_either_compiler_api(){
  let source=Source(dm_preprocess::AcquiredSource::from_original_bytes(b"/datum/analysis_zero\n".to_vec(),()));let seed=crate::checker_builtins::original_analysis_seed().unwrap();let executor=dm_exec::BuildExecutor::new(1).unwrap();
  let build=||super::super::build_for_checker_diagnostics_with_state(std::path::Path::new("analysis-zero.dme"),&source,&Default::default(),FrontendConfig{workers:1,engine:Some(seed.frontend_seed()),observer:None},None,&executor,None).unwrap();
  let first=build();assert!(first.source_view().unwrap().receipt().errors().is_empty());assert!(first.try_into_compilable().is_err());
  let second=build();assert!(second.source_view().unwrap().receipt().errors().is_empty());let mut state=RetainedSemanticTree::new();assert!(second.try_into_compilable_retained(&mut state).is_err());assert!(state.snapshot_tree().is_none());
 }
 #[test]fn original_analysis_previous_storage_retains_actual_records_until_the_only_owner_drops(){
  let source=Source(dm_preprocess::AcquiredSource::from_original_bytes(b"/datum/analysis_owned\n".to_vec(),()));let seed=crate::checker_builtins::original_analysis_seed().unwrap();let executor=dm_exec::BuildExecutor::new(1).unwrap();let mut preparation_state=RetainedSemanticTree::new();let diagnostic=Arc::new(super::super::build_for_checker_diagnostics_with_state(std::path::Path::new("analysis-owned.dme"),&source,&Default::default(),FrontendConfig{workers:1,engine:Some(seed.frontend_seed()),observer:None},None,&executor,Some(&mut preparation_state)).unwrap());drop(preparation_state);
  let weak=Arc::downgrade(&diagnostic);let records=diagnostic.retained_records.as_ref().unwrap();let records_address=Arc::as_ptr(records)as usize;let weak_records=Arc::downgrade(records);let mut state=RetainedSemanticTree::new();state.remember_analysis_frontend(std::path::Path::new("analysis-owned.dme"),&Default::default(),Arc::clone(&diagnostic)).unwrap();drop(diagnostic);assert!(weak.upgrade().is_some());assert!(weak_records.upgrade().is_some());
  let mut allocations=std::collections::BTreeSet::new();let mut index=false;let mut source_owner=false;state.visit_previous_analysis_storage(|view|match view{super::super::AnalysisRetentionStorage::Allocation{address,..}=>{allocations.insert(address);},super::super::AnalysisRetentionStorage::Declarations(_)=>index=true,super::super::AnalysisRetentionStorage::Source(_)=>source_owner=true,_=>{}});assert!(allocations.contains(&records_address));assert!(index&&source_owner);drop(state);assert!(weak.upgrade().is_none());assert!(weak_records.upgrade().is_none());
 }
}

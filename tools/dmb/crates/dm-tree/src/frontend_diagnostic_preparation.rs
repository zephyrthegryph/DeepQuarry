//! Diagnostic-only preparation over ONE original native frontend pass.
//! No alternate parser, model, normalized member table or runtime ABI receipt.
use super::*;
use crate::diagnostic_declarations::DiagnosticDeclarationReceipt;
use crate::SemanticTree;
pub struct DiagnosticFrontend {
    purpose: DiagnosticPreparationPurpose,
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
    pub fn preparation_purpose(&self)->DiagnosticPreparationPurpose{self.purpose}
    pub fn original_analysis_completeness(&self)->Option<OriginalAnalysisCompleteness>{match self.purpose{DiagnosticPreparationPurpose::OriginalSharedComplete=>Some(OriginalAnalysisCompleteness::Complete),DiagnosticPreparationPurpose::OriginalAnalyzePrefix=>Some(OriginalAnalysisCompleteness::PrimaryPrefix),_=>None}}
    pub fn checker_source_view(&self)->Result<DiagnosticSourceView<'_>,String>{if !matches!(self.purpose,DiagnosticPreparationPurpose::Checker|DiagnosticPreparationPurpose::OriginalSharedComplete){return Err("partial original purpose cannot certify the checker purpose".into())}self.source_view()}
    pub fn handlers_structural_source(&self)->Result<HandlersStructuralSource<'_>,String>{let completeness=match self.purpose{DiagnosticPreparationPurpose::OriginalHandlersStructuralComplete=>OriginalAnalysisCompleteness::Complete,DiagnosticPreparationPurpose::OriginalHandlersStructuralPrefix=>OriginalAnalysisCompleteness::PrimaryPrefix,_=>return Err("actual original handlers structural purpose was not issued".into())};Ok(HandlersStructuralSource{view:self.source_view()?,completeness})}
    pub(super) fn bind_original_primary(mut self,primary:Arc<super::original_declaration_input::OriginalPrimaryRetention>)->Result<Self,Vec<Diagnostic>>{
      let view=self.source_view().map_err(|message|vec![internal(&message)])?;view.require_original_analysis_seed().map_err(|message|vec![internal(&message)])?;
      if view.original_plan().initial_environment!=dm_preprocess::InitialEnvironment::OriginalChecker0290||!self.inner.original_primary.as_ref().is_some_and(|issued|Arc::ptr_eq(issued,&primary)){return Err(vec![internal("actual original primary outcome does not belong to the native graph recipe")])}
      if primary.frontier().is_some(){self.retained_records=None;}Ok(self)
    }

    pub(super) fn visit_retention_storage(&self,mut visit:impl FnMut(super::AnalysisRetentionStorage<'_>)){
        use super::AnalysisRetentionStorage as V;
        if let Some(primary)=&self.inner.original_primary{visit(V::Allocation{address:Arc::as_ptr(primary)as usize,bytes:std::mem::size_of_val(primary.as_ref())});primary.visit_retained_storage(|address,bytes,_|visit(V::Allocation{address,bytes}));}
        visit(V::Source(DiagnosticSourceView{owner:self}));visit(V::Receipt(&self.receipt));
        if let Some(records)=&self.retained_records{visit(V::Allocation{address:Arc::as_ptr(records)as usize,bytes:std::mem::size_of_val(records.as_ref())});records.visit_storage(&mut visit);}
    }

    pub(super) fn preparation_frontend(&self)->&ColdFrontend { &self.inner }
    pub(super) fn preparation_original_primary(&self)->Option<Arc<super::original_declaration_input::OriginalPrimaryRetention>>{self.inner.original_primary.clone()}
    pub(super) fn preparation_engine_matches(&self,engine:Option<&EngineSeed>)->bool {
        if self.purpose.is_structural(){return false}
        let original=self.inner.plan.initial_environment==dm_preprocess::InitialEnvironment::OriginalChecker0290
            && self.receipt.authenticates(self.inner.snapshot.tree.as_ref())
            && self.receipt.has_original_variable_declarations()
            && crate::checker_builtins::OriginalVariableDeclarations::for_seed(engine).is_some();
        self.source_view().is_ok() && (original || (self.receipt.errors().is_empty() && self.receipt.settings_compilable()
            && self.retained_records.as_ref().is_some_and(|records|records.engine_matches(engine))
            ))
    }
    pub(super) fn preparation_receipt(&self,tree:&Arc<SemanticTree>)->Option<crate::diagnostic_declarations::DiagnosticDeclarationReceipt>{
        if self.purpose.is_structural()||!Arc::ptr_eq(tree,&self.inner.snapshot.tree){return None}
        crate::diagnostic_declarations::DiagnosticDeclarationReceipt::reused_diagnostic_tree(tree,&self.receipt)
    }
    pub(super) fn preparation_records(&self)->Option<Arc<super::DiagnosticRetainedRecords>> { self.retained_records.clone() }
    pub(super) fn preparation_original_variables(&self)->Option<crate::checker_builtins::OriginalVariableDeclarations>{if self.receipt.authenticates(self.inner.snapshot.tree.as_ref())&&self.inner.plan.initial_environment==dm_preprocess::InitialEnvironment::OriginalChecker0290{self.receipt.original_variables}else{None}}

    pub(super) fn bind(
        inner: ColdFrontend,
        mut receipt: DiagnosticDeclarationReceipt,
    ) -> Result<Self, Vec<Diagnostic>> {Self::bind_subject(inner,receipt,false)}
    pub(super) fn bind_handlers_structural(inner:ColdFrontend,receipt:DiagnosticDeclarationReceipt)->Result<Self,Vec<Diagnostic>>{Self::bind_subject(inner,receipt,true)}
    fn bind_subject(inner:ColdFrontend,mut receipt:DiagnosticDeclarationReceipt,structural:bool)->Result<Self,Vec<Diagnostic>>{
        let purpose=match (structural,inner.original_primary.as_ref().map(|primary|primary.frontier().is_some())){
          (false,None)=>DiagnosticPreparationPurpose::Checker,
          (false,Some(false))=>DiagnosticPreparationPurpose::OriginalSharedComplete,
          (false,Some(true))=>DiagnosticPreparationPurpose::OriginalAnalyzePrefix,
          (true,Some(false))=>DiagnosticPreparationPurpose::OriginalHandlersStructuralComplete,
          (true,Some(true))=>DiagnosticPreparationPurpose::OriginalHandlersStructuralPrefix,
          (true,None)=>return Err(vec![internal("structural purpose lacks its actual original primary owner")]),
        };
        if structural{receipt.retained_records=None;}
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
            purpose,
            retained_records,
            inner,
            receipt: Arc::new(receipt),
            archive,
        })
    }
    pub fn with_body_queries(self, host: Arc<dyn BodySyntaxQueries>) -> Result<Self, String> {
        let Self {
            purpose,
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
            purpose,
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
        if self.inner.original_primary.is_some()||self.receipt.has_original_variable_declarations()||self.archive.source_mapping().initial_environment()==dm_preprocess::InitialEnvironment::OriginalChecker0290{return Err(self)}
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
        if self.inner.original_primary.is_some()||self.receipt.has_original_variable_declarations()||self.archive.source_mapping().initial_environment()==dm_preprocess::InitialEnvironment::OriginalChecker0290{return Err(self)}
        if self.receipt.settings_compilable() && self.receipt.errors().is_empty() {
            Ok(self.inner)
        } else {
            Err(self)
        }
    }
}
impl DiagnosticSourceView<'_> {
    pub fn preparation_purpose(&self)->DiagnosticPreparationPurpose{self.owner.preparation_purpose()}
    pub fn original_analysis_completeness(&self)->Option<OriginalAnalysisCompleteness>{self.owner.original_analysis_completeness()}
    /// Validate the actual declaration-only catalog seed used by this builder.
    /// This proves no runtime inventory, source coverage, or operation completion.
    pub fn require_original_analysis_seed(&self)->Result<(),String>{if !self.owner.receipt.has_original_variable_declarations()||!self.owner.receipt.authenticates(self.owner.inner.snapshot.tree.as_ref()){return Err("original analysis declaration seed was not actually issued".into())}Ok(())}
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
 let test_original_host=crate::frontend::declaration_checked_tests::original_test_host();

  let source=Source(dm_preprocess::AcquiredSource::from_original_bytes(b"/datum/analysis_zero\n".to_vec(),()));let seed=crate::checker_builtins::original_analysis_seed().unwrap();let executor=dm_exec::BuildExecutor::new(1).unwrap();
  let build=||super::super::build_for_checker_diagnostics_with_state_checked(std::path::Path::new("analysis-zero.dme"),&source,&Default::default(),FrontendConfig{workers:1,engine:Some(seed.frontend_seed()),observer:None},None,&executor,None,&test_original_host).unwrap();
  let first=build();assert!(first.source_view().unwrap().receipt().errors().is_empty());assert!(first.try_into_compilable().is_err());
  let second=build();assert!(second.source_view().unwrap().receipt().errors().is_empty());let mut state=RetainedSemanticTree::new();assert!(second.try_into_compilable_retained(&mut state).is_err());assert!(state.snapshot_tree().is_none());
 }
 #[test]fn original_analysis_previous_storage_retains_actual_records_until_the_only_owner_drops(){
 let test_original_host=crate::frontend::declaration_checked_tests::original_test_host();

  let source=Source(dm_preprocess::AcquiredSource::from_original_bytes(b"/datum/analysis_owned\n".to_vec(),()));let seed=crate::checker_builtins::original_analysis_seed().unwrap();let executor=dm_exec::BuildExecutor::new(1).unwrap();let mut preparation_state=RetainedSemanticTree::new();let diagnostic=Arc::new(super::super::build_for_checker_diagnostics_with_state_checked(std::path::Path::new("analysis-owned.dme"),&source,&Default::default(),FrontendConfig{workers:1,engine:Some(seed.frontend_seed()),observer:None},None,&executor,Some(&mut preparation_state),&test_original_host).unwrap());drop(preparation_state);
  let weak=Arc::downgrade(&diagnostic);let records=diagnostic.retained_records.as_ref().unwrap();let records_address=Arc::as_ptr(records)as usize;let weak_records=Arc::downgrade(records);let mut state=RetainedSemanticTree::new();state.remember_analysis_frontend(std::path::Path::new("analysis-owned.dme"),&Default::default(),Arc::clone(&diagnostic)).unwrap();drop(diagnostic);assert!(weak.upgrade().is_some());assert!(weak_records.upgrade().is_some());
  let mut allocations=std::collections::BTreeSet::new();let mut index=false;let mut source_owner=false;state.visit_previous_analysis_storage(|view|match view{super::super::AnalysisRetentionStorage::Allocation{address,..}=>{allocations.insert(address);},super::super::AnalysisRetentionStorage::Declarations(_)=>index=true,super::super::AnalysisRetentionStorage::Source(_)=>source_owner=true,_=>{}});assert!(allocations.contains(&records_address));assert!(index&&source_owner);drop(state);assert!(weak.upgrade().is_none());assert!(weak_records.upgrade().is_none());
 }
}

#[cfg(test)]
#[path="frontend_original_builtin_variables_tests.rs"]mod original_builtin_variables_tests;

#[cfg(test)]mod original_missing_parent_outcome_tests{
 use super::*;
 struct Source(dm_preprocess::AcquiredSource);
 impl dm_preprocess::SourceProvider for Source{fn initial_environment(&self)->dm_preprocess::InitialEnvironment{dm_preprocess::InitialEnvironment::OriginalChecker0290}fn read(&self,_:&std::path::Path)->Result<String,String>{Err("actual Original source lease required".into())}fn acquired_source(&self,_:&std::path::Path)->Result<Option<dm_preprocess::AcquiredSource>,String>{Ok(Some(self.0.clone()))}fn source_acquisition(&self,_:&std::path::Path,text:&dm_preprocess::SourceText)->Option<dm_preprocess::AcquiredSource>{self.0.lease().source_text().same_view(text).then(||self.0.clone())}}
 #[test]fn missing_parent_recovers_root_only_for_original_diagnostics_never_for_compiler(){
 let test_original_host=crate::frontend::declaration_checked_tests::original_test_host();

  let source=Source(dm_preprocess::AcquiredSource::from_original_bytes(b"/datum/bad\n    parent_type=/datum/missing\n/proc/probe()\n    return\n".to_vec(),()));let seed=crate::checker_builtins::original_analysis_seed().unwrap();let executor=dm_exec::BuildExecutor::new(1).unwrap();let path=std::path::Path::new("missing-parent.dme");let config=FrontendConfig{workers:1,engine:Some(seed.frontend_seed()),observer:None};
  let build=||super::super::build_for_checker_diagnostics_with_state_checked(path,&source,&Default::default(),config,None,&executor,None,&test_original_host).unwrap();let diagnostic=build();let view=diagnostic.source_view().unwrap();let id=view.tree().lookup_type(dm_ir::SymbolId::of("/datum/bad")).unwrap();assert_eq!(view.tree().type_node(view.tree().parent(id).unwrap()).unwrap().path,dm_ir::SymbolId::of("/"));assert!(view.receipt().errors().iter().any(|error|matches!(error,crate::TreeError::OriginalMissingParent{owner,parent}if *owner==dm_ir::SymbolId::of("/datum/bad")&&*parent==dm_ir::SymbolId::of("/datum/missing"))));let span=view.archive().original_parent_assignment_span(dm_ir::SymbolId::of("/datum/bad"),dm_ir::SymbolId::of("/datum/missing"),&||Ok(())).unwrap();let point=view.mapping().borrowed_source_note_point(span.start).unwrap();assert_eq!((point.reported_coordinates().1,point.reported_coordinates().2),(2,16));assert!(diagnostic.try_into_compilable().is_err());let second=build();let mut state=RetainedSemanticTree::new();assert!(second.try_into_compilable_retained(&mut state).is_err());assert!(state.snapshot_tree().is_none());
  let strict=super::super::build_with_config(path,&source,&Default::default(),config);assert!(strict.is_err(),"ordinary native compile must still reject the unresolved parent");
 }
 #[test]fn many_missing_parent_primary_cursors_are_observed_in_one_native_declaration_walk(){
 let test_original_host=crate::frontend::declaration_checked_tests::original_test_host();

  let source=Source(dm_preprocess::AcquiredSource::from_original_bytes(include_bytes!("../../../fixtures/unified_checks/missing_parent_outcome_many_missing_parents/project.dme").to_vec(),()));let seed=crate::checker_builtins::original_analysis_seed().unwrap();let executor=dm_exec::BuildExecutor::new(1).unwrap();let diagnostic=super::super::build_for_checker_diagnostics_with_state_checked(std::path::Path::new("many-parent.dme"),&source,&Default::default(),FrontendConfig{workers:1,engine:Some(seed.frontend_seed()),observer:None},None,&executor,None,&test_original_host).unwrap();let view=diagnostic.source_view().unwrap();let parents=view.receipt().errors().iter().filter_map(|error|if let crate::TreeError::OriginalMissingParent{owner,parent}=error{Some((*owner,*parent))}else{None}).collect::<std::collections::BTreeMap<_,_>>();assert_eq!(parents.len(),16);let mut selected=0;let mut observed=0;view.archive().visit_original_parent_assignment_spans(&||Ok(()),|owner|{selected+=1;Ok(parents.get(&owner).copied())},|owner,parent,at|{assert_eq!(parents.get(&owner),Some(&parent));assert_eq!(&view.expanded_text()[at.range()],"=");let point=view.mapping().borrowed_source_note_point(at.start).unwrap();assert_eq!(point.reported_coordinates().2,16);observed+=1;Ok(())}).unwrap();assert_eq!(selected,16,"one visit to each existing type AST, not one whole-tree scan per error");assert_eq!(observed,16);
 }

}

#[cfg(test)]mod original_fatal_parameter_outcome_tests{
 use super::*;
 struct Source(dm_preprocess::AcquiredSource);impl SourceProvider for Source{fn initial_environment(&self)->dm_preprocess::InitialEnvironment{dm_preprocess::InitialEnvironment::OriginalChecker0290}fn read(&self,_:&Path)->Result<String,String>{Err("actual Original acquisition required".into())}fn acquired_source(&self,_:&Path)->Result<Option<dm_preprocess::AcquiredSource>,String>{Ok(Some(self.0.clone()))}fn source_acquisition(&self,_:&Path,text:&dm_preprocess::SourceText)->Option<dm_preprocess::AcquiredSource>{self.0.lease().source_text().same_view(text).then(||self.0.clone())}}
 #[test]fn original_fatal_parameter_failure_preserves_actual_primary_tokens_and_stops_before_tree(){
 let test_original_host=crate::frontend::declaration_checked_tests::original_test_host();

  for(name,bytes)in[("exact_bad_parameter",include_bytes!("../../../fixtures/unified_checks/fatal_parameter_outcome_exact_bad_parameter/project.dme").as_slice()),("comma_operand",include_bytes!("../../../fixtures/unified_checks/fatal_parameter_outcome_comma_operand/project.dme").as_slice()),("utf8_prefix_byte_column",include_bytes!("../../../fixtures/unified_checks/fatal_parameter_outcome_utf8_prefix_byte_column/project.dme").as_slice())]{
   let source=Source(dm_preprocess::AcquiredSource::from_original_bytes(bytes.to_vec(),()));let seed=crate::checker_builtins::original_analysis_seed().unwrap();let executor=dm_exec::BuildExecutor::new(1).unwrap();let mut state=RetainedSemanticTree::new();let result=super::super::build_for_checker_diagnostics_with_state_checked(Path::new("project.dme"),&source,&Default::default(),FrontendConfig{workers:1,engine:Some(seed.frontend_seed()),observer:None},None,&executor,Some(&mut state),&test_original_host);let errors=match result{Err(FrontendBuildFailure::Diagnostics(errors))=>errors,Err(FrontendBuildFailure::Operational(actual))=>panic!("actual original fixture hit operational failure: {actual}"),Ok(_)=>panic!("malformed signature cannot prepare an admitted graph")};assert!(state.snapshot_tree().is_none(),"fatal must not publish a partial semantic tree");let outcome=super::super::original_fatal_preparation_outcome(&errors).expect("actual first-header native grammar receipt");assert!(!outcome.continues_analysis());assert!(!outcome.compiler_admissible());let(_,line,column)=outcome.location();assert_eq!(line,1);assert_eq!(column,if name=="utf8_prefix_byte_column"{32}else{13});
   use sha2::Digest;println!("ORIGINAL_FATAL_PARAMETER_NATIVE {}",serde_json::json!({"case":name,"source_sha256":format!("{:x}",sha2::Sha256::digest(bytes)),"diagnostics":[{"message":outcome.message(),"level":outcome.severity(),"line":line,"column":column,"notes":outcome.notes()}]}));
  }
 }
 #[test]fn original_fatal_parameter_outcome_binds_genuine_earlier_statement_terminator_state(){
 let test_original_host=crate::frontend::declaration_checked_tests::original_test_host();

  let bytes=include_bytes!("../../../fixtures/unified_checks/fatal_parameter_outcome_earlier_and_later_procs_stop/project.dme");let source=Source(dm_preprocess::AcquiredSource::from_original_bytes(bytes.to_vec(),()));let seed=crate::checker_builtins::original_analysis_seed().unwrap();let executor=dm_exec::BuildExecutor::new(1).unwrap();let mut state=RetainedSemanticTree::new();let result=super::super::build_for_checker_diagnostics_with_state_checked(Path::new("project.dme"),&source,&Default::default(),FrontendConfig{workers:1,engine:Some(seed.frontend_seed()),observer:None},None,&executor,Some(&mut state),&test_original_host);let errors=match result{Err(FrontendBuildFailure::Diagnostics(errors))=>errors,Err(FrontendBuildFailure::Operational(actual))=>panic!("actual original fixture hit operational failure: {actual}"),Ok(_)=>panic!("malformed prefix cannot admit a graph")};assert!(!errors.is_empty());assert!(state.snapshot_tree().is_none());let outcome=super::super::original_fatal_preparation_outcome(&errors).expect("actual primary outer block probe must bind earlier parser state");assert_eq!(outcome.notes().len(),3);assert!(outcome.notes()[0].contains("check for extra indentation"));
 }
 #[test]fn ordinary_compiler_keeps_its_rejection_without_original_fatal_report_role(){
  let source=Source(dm_preprocess::AcquiredSource::from_original_bytes(include_bytes!("../../../fixtures/unified_checks/fatal_parameter_outcome_exact_bad_parameter/project.dme").to_vec(),()));let seed=crate::checker_builtins::original_analysis_seed().unwrap();let result=super::super::build_with_config(Path::new("project.dme"),&source,&Default::default(),FrontendConfig{workers:1,engine:Some(seed.frontend_seed()),observer:None});let errors=match result{Err(errors)=>errors,Ok(_)=>panic!("ordinary native compiler must still reject this authored invalid-setting fixture")};println!("STRICT_FATAL_REJECTION {errors:#?}");assert!(super::super::original_fatal_preparation_outcome(&errors).is_none());assert_eq!(errors.iter().map(|row|row.message.as_str()).collect::<Vec<_>>(),["unknown procedure setting: mystery_bad","unknown procedure setting: mystery_good"],"ordinary Native adapter retains its actual setting-first refusal precedence");assert!(errors.iter().all(|row|row.kind==DiagnosticKind::UnsupportedModel&&!row.kind.is_source_error()));
 }
}

#[cfg(test)]mod original_outer_terminator_tests{
 use super::*;
 struct Source(dm_preprocess::AcquiredSource);impl SourceProvider for Source{fn initial_environment(&self)->dm_preprocess::InitialEnvironment{dm_preprocess::InitialEnvironment::OriginalChecker0290}fn read(&self,_:&Path)->Result<String,String>{Err("actual Original acquisition required".into())}fn acquired_source(&self,_:&Path)->Result<Option<dm_preprocess::AcquiredSource>,String>{Ok(Some(self.0.clone()))}fn source_acquisition(&self,_:&Path,text:&dm_preprocess::SourceText)->Option<dm_preprocess::AcquiredSource>{self.0.lease().source_text().same_view(text).then(||self.0.clone())}}
 #[test]fn original_outer_header_terminator_events_preserve_full_fatal_notes_and_stop(){
 let test_original_host=crate::frontend::declaration_checked_tests::original_test_host();

  for(name,bytes)in[("prior_block_in_same_failed_type_chunk",include_bytes!("../../../fixtures/unified_checks/outer_terminator_prior_block_in_same_failed_type_chunk/project.dme").as_slice()),("earlier_and_later_procs_stop",include_bytes!("../../../fixtures/unified_checks/fatal_parameter_outcome_earlier_and_later_procs_stop/project.dme").as_slice()),("prior_return_block",include_bytes!("../../../fixtures/unified_checks/outer_terminator_prior_return_block/project.dme").as_slice()),("prior_bare_block",include_bytes!("../../../fixtures/unified_checks/outer_terminator_prior_bare_block/project.dme").as_slice()),("prior_bodyless",include_bytes!("../../../fixtures/unified_checks/outer_terminator_prior_bodyless/project.dme").as_slice()),("prior_empty_explicit_block",include_bytes!("../../../fixtures/unified_checks/outer_terminator_prior_empty_explicit_block/project.dme").as_slice()),("prior_same_line_body",include_bytes!("../../../fixtures/unified_checks/outer_terminator_prior_same_line_body/project.dme").as_slice()),("prior_type_block_no_proc_body",include_bytes!("../../../fixtures/unified_checks/outer_terminator_prior_type_block_no_proc_body/project.dme").as_slice()),("prior_nested_proc_block",include_bytes!("../../../fixtures/unified_checks/outer_terminator_prior_nested_proc_block/project.dme").as_slice())]{
   let source=Source(dm_preprocess::AcquiredSource::from_original_bytes(bytes.to_vec(),()));let seed=crate::checker_builtins::original_analysis_seed().unwrap();let executor=dm_exec::BuildExecutor::new(1).unwrap();let mut state=RetainedSemanticTree::new();let result=super::super::build_for_checker_diagnostics_with_state_checked(Path::new("project.dme"),&source,&Default::default(),FrontendConfig{workers:1,engine:Some(seed.frontend_seed()),observer:None},None,&executor,Some(&mut state),&test_original_host);let errors=match result{Err(FrontendBuildFailure::Diagnostics(errors))=>errors,Err(FrontendBuildFailure::Operational(actual))=>panic!("actual original fixture hit operational failure: {actual}"),Ok(_)=>panic!("a fatal parameter must not publish a graph")};assert!(state.snapshot_tree().is_none());let outcome=super::super::original_fatal_preparation_outcome(&errors).expect("real current primary header event and real fatal token must be bound");assert!(!outcome.continues_analysis());assert!(!outcome.compiler_admissible());let(_,line,column)=outcome.location();let notes=outcome.notes();let indentation=matches!(name,"prior_return_block"|"prior_bare_block"|"prior_empty_explicit_block"|"prior_nested_proc_block"|"earlier_and_later_procs_stop"|"prior_block_in_same_failed_type_chunk");assert_eq!(notes.len(),if indentation{3}else{2},"{name}");if indentation{assert_eq!(notes[0],format!("{}:1: check for extra indentation at the start of the next line",line+1));}
   use sha2::Digest;println!("ORIGINAL_OUTER_TERMINATOR_NATIVE {}",serde_json::json!({"case":name,"source_sha256":format!("{:x}",sha2::Sha256::digest(bytes)),"diagnostics":[{"message":outcome.message(),"level":outcome.severity(),"line":line,"column":column,"notes":notes}]}));
   let strict=super::super::build_with_config(Path::new("project.dme"),&source,&Default::default(),FrontendConfig{workers:1,engine:Some(seed.frontend_seed()),observer:None});let Err(strict)=strict else{panic!("ordinary native compiler cannot admit malformed parameter")};assert!(super::super::original_fatal_preparation_outcome(&strict).is_none());assert!(strict.iter().any(|error|error.kind==DiagnosticKind::SourceError));
  }
 }
}

/// Purpose is selected before the SAME native frontend pass. A source-complete
/// capture is not a semantic-completeness or checker/compile admission token.
#[derive(Clone,Copy,Debug,PartialEq,Eq)]pub enum OriginalAnalysisCompleteness{Complete,PrimaryPrefix}
#[derive(Clone,Copy,Debug,PartialEq,Eq)]pub enum DiagnosticPreparationPurpose{Checker,OriginalSharedComplete,OriginalAnalyzePrefix,OriginalHandlersStructuralComplete,OriginalHandlersStructuralPrefix}
impl DiagnosticPreparationPurpose{pub fn is_structural(self)->bool{matches!(self,Self::OriginalHandlersStructuralComplete|Self::OriginalHandlersStructuralPrefix)}}
/// Private-constructor witness for an actual partial translation unit. It is
/// neither the checker witness nor original full-workspace completeness.
pub struct HandlersStructuralSource<'a>{view:DiagnosticSourceView<'a>,completeness:OriginalAnalysisCompleteness}
impl<'a> HandlersStructuralSource<'a>{pub fn view(&self)->&DiagnosticSourceView<'a>{&self.view}pub fn completeness(&self)->OriginalAnalysisCompleteness{self.completeness}}
/// Retained recipe discrimination only; never source/current-owner authority.
pub const ORIGINAL_ANALYZE_PREPARATION_VERSION:u32=1;
#[cfg(test)]mod original_analyze_prefix_tests{
 use super::*;use std::sync::atomic::{AtomicUsize,Ordering};
 struct Source(dm_preprocess::AcquiredSource);
 impl SourceProvider for Source{
  fn initial_environment(&self)->dm_preprocess::InitialEnvironment{dm_preprocess::InitialEnvironment::OriginalChecker0290}
  fn read(&self,_:&Path)->Result<String,String>{Err("actual Original acquisition required".into())}
  fn acquired_source(&self,_:&Path)->Result<Option<dm_preprocess::AcquiredSource>,String>{Ok(Some(self.0.clone()))}
  fn source_acquisition(&self,_:&Path,text:&dm_preprocess::SourceText)->Option<dm_preprocess::AcquiredSource>{self.0.lease().source_text().same_view(text).then(||self.0.clone())}
 }
 #[derive(Debug)]struct Host{counter:Arc<AtomicUsize>,fault:bool,aliases:std::sync::Mutex<OriginalSignatureAliasCensus>}
 impl SettingExpressionQueries for Host{
  fn retain_original_signature_aliases(&self,row:Arc<OriginalSignatureAliasGroup>,a:&dm_syntax::SettingAdmission<'_>)->Result<(),BodySyntaxFailure>{self.aliases.lock().unwrap().retain(row,a).map_err(BodySyntaxFailure::Operational)}
  fn with_declaration_admission(&self,operation:&mut dyn FnMut(&dm_syntax::SettingAdmission<'_>)->Result<(),BodySyntaxFailure>)->Result<(),BodySyntaxFailure>{let poll=||if self.fault{Err(std::io::Error::from_raw_os_error(1450))}else{Ok(())};let a=dm_syntax::SettingAdmission::new(&self.counter,64*1024*1024,&poll);self.aliases.lock().unwrap().prune(&a).map_err(BodySyntaxFailure::Operational)?;let result=operation(&a);if matches!(&result,Err(BodySyntaxFailure::Operational(_))){return result}if let Some(actual)=a.take_operational_error(){return Err(BodySyntaxFailure::Operational(actual))}result}
  fn expression(&self,_:&SettingExpressionInput<'_>)->Result<dm_syntax::SettingExpression,BodySyntaxFailure>{panic!("declaration-only preparation does not demand a settings expression")}
 }
 fn original(text:&str)->Source{Source(dm_preprocess::AcquiredSource::from_original_bytes(text.as_bytes().to_vec(),()))}
 #[test]fn actual_analyze_prefix_model_keeps_real_first_field_prior_body_and_cannot_promote(){
  let text="/datum/parent\n    var/before\n/proc/kept()\n    return 1\n/datum/child\n    parent_type=/datum/parent\n    var/const/value=1+2\n    var/datum/first, second\n/proc/after()\n    return 2\n";let source=original(text);let seed=crate::checker_builtins::original_analysis_seed().unwrap();let executor=dm_exec::BuildExecutor::new(1).unwrap();let config=FrontendConfig{workers:1,engine:Some(seed.frontend_seed()),observer:None};let counter=Arc::new(AtomicUsize::new(0));let host=Arc::new(Host{counter:counter.clone(),fault:false,aliases:Default::default()})as Arc<dyn SettingExpressionQueries>;let mut state=RetainedSemanticTree::new();
  let analysis=super::super::build_for_original_analysis_with_state_checked(Path::new("actual-prefix.dme"),&source,&Default::default(),config,None,&executor,Some(&mut state),&host).unwrap();assert_eq!(analysis.original_analysis_completeness(),Some(OriginalAnalysisCompleteness::PrimaryPrefix));let view=analysis.source_view().unwrap();assert_eq!(view.expanded_text(),text);let owner=view.tree().lookup_type(dm_ir::SymbolId::of("/datum/child")).unwrap();let parent=view.tree().parent(owner).unwrap();assert_eq!(view.tree().type_node(parent).unwrap().path,dm_ir::SymbolId::of("/datum/parent"));assert!(view.tree().symbols().text(dm_ir::SymbolId::of("first")).is_some());assert!(view.tree().symbols().text(dm_ir::SymbolId::of("second")).is_none());assert!(view.tree().symbols().text(dm_ir::SymbolId::of("after")).is_none());assert!(view.bodies().iter().all(|body|body.expanded_span.start<text.find("var/datum/first").unwrap()));assert!(state.snapshot_tree().is_none(),"partial Analyze preparation never publishes a compiler-complete semantic state");
  assert!(analysis.checker_source_view().is_err(),"Analyze purpose cannot stand for a checker view");assert!(analysis.try_into_compilable().is_err(),"actual partial role cannot promote through existing compiler API");drop(state);host.with_declaration_admission(&mut |_|Ok(())).unwrap();assert_eq!(counter.load(Ordering::Acquire),0);
 }
 #[test]fn actual_analyze_parameter_fatal_has_a_real_prefix_not_semantic_none_and_no_later_parent(){
  let text="/datum/kept\n    var/value=1\n/proc/good(obj/value)\n    return value\n/proc/bad(value=)\n    return 7\n/datum/later\n    parent_type=/datum/missing\n";let source=original(text);let seed=crate::checker_builtins::original_analysis_seed().unwrap();let executor=dm_exec::BuildExecutor::new(1).unwrap();let counter=Arc::new(AtomicUsize::new(0));let host=Arc::new(Host{counter:counter.clone(),fault:false,aliases:Default::default()})as Arc<dyn SettingExpressionQueries>;
  let analysis=super::super::build_for_original_analysis_with_state_checked(Path::new("parameter-prefix.dme"),&source,&Default::default(),FrontendConfig{workers:1,engine:Some(seed.frontend_seed()),observer:None},None,&executor,None,&host).unwrap();assert_eq!(analysis.original_analysis_completeness(),Some(OriginalAnalysisCompleteness::PrimaryPrefix));let view=analysis.source_view().unwrap();assert!(view.tree().symbols().text(dm_ir::SymbolId::of("good")).is_some());assert!(view.tree().symbols().text(dm_ir::SymbolId::of("bad")).is_none());assert!(view.tree().symbols().text(dm_ir::SymbolId::of("/datum/later")).is_none());assert_eq!(view.bodies().len(),1);let config=FrontendConfig{workers:1,engine:Some(seed.frontend_seed()),observer:None};assert!(super::super::build_for_checker_diagnostics_with_state_checked(Path::new("parameter-prefix.dme"),&source,&Default::default(),config,None,&executor,None,&host).is_err());assert!(super::super::build_with_config(Path::new("parameter-prefix.dme"),&source,&Default::default(),config).is_err());drop(analysis);host.with_declaration_admission(&mut |_|Ok(())).unwrap();assert_eq!(counter.load(Ordering::Acquire),0);
 }
 #[test]fn original_analyze_operational_failure_stays_typed_and_unsupported_primary_state_never_becomes_empty_available_model(){
  let seed=crate::checker_builtins::original_analysis_seed().unwrap();let executor=dm_exec::BuildExecutor::new(1).unwrap();let counter=Arc::new(AtomicUsize::new(0));let host=Arc::new(Host{counter:counter.clone(),fault:true,aliases:Default::default()})as Arc<dyn SettingExpressionQueries>;let source=original("/datum/prefix\n");let result=super::super::build_for_original_analysis_with_state_checked(Path::new("failure.dme"),&source,&Default::default(),FrontendConfig{workers:1,engine:Some(seed.frontend_seed()),observer:None},None,&executor,None,&host);assert!(matches!(result,Err(FrontendBuildFailure::Operational(actual))if actual.raw_os_error()==Some(1450)));assert_eq!(counter.load(Ordering::Acquire),0);
  let host=Arc::new(Host{counter:counter.clone(),fault:false,aliases:Default::default()})as Arc<dyn SettingExpressionQueries>;let source=original("/datum/prefix\n    var/first = 1, second = 2\n");let result=super::super::build_for_original_analysis_with_state_checked(Path::new("unissued.dme"),&source,&Default::default(),FrontendConfig{workers:1,engine:Some(seed.frontend_seed()),observer:None},None,&executor,None,&host);assert!(matches!(result,Err(FrontendBuildFailure::Operational(actual))if actual.kind()==std::io::ErrorKind::Unsupported));assert_eq!(counter.load(Ordering::Acquire),0);
 }
}

#[cfg(test)]mod original_shared_complete_owner_tests{
 use super::*;use std::sync::atomic::{AtomicUsize,Ordering};
 struct Source(dm_preprocess::AcquiredSource);impl SourceProvider for Source{fn initial_environment(&self)->dm_preprocess::InitialEnvironment{dm_preprocess::InitialEnvironment::OriginalChecker0290}fn read(&self,_:&Path)->Result<String,String>{Err("actual original lease required".into())}fn acquired_source(&self,_:&Path)->Result<Option<dm_preprocess::AcquiredSource>,String>{Ok(Some(self.0.clone()))}fn source_acquisition(&self,_:&Path,text:&dm_preprocess::SourceText)->Option<dm_preprocess::AcquiredSource>{self.0.lease().source_text().same_view(text).then(||self.0.clone())}}
 #[derive(Debug)]struct Host(Arc<AtomicUsize>,std::sync::Mutex<OriginalSignatureAliasCensus>);impl SettingExpressionQueries for Host{fn retain_original_signature_aliases(&self,row:Arc<OriginalSignatureAliasGroup>,a:&dm_syntax::SettingAdmission<'_>)->Result<(),BodySyntaxFailure>{self.1.lock().unwrap().retain(row,a).map_err(BodySyntaxFailure::Operational)}fn with_declaration_admission(&self,operation:&mut dyn FnMut(&dm_syntax::SettingAdmission<'_>)->Result<(),BodySyntaxFailure>)->Result<(),BodySyntaxFailure>{let poll=||Ok(());let a=dm_syntax::SettingAdmission::new(&self.0,64*1024*1024,&poll);self.1.lock().unwrap().prune(&a).map_err(BodySyntaxFailure::Operational)?;let result=operation(&a);if matches!(&result,Err(BodySyntaxFailure::Operational(_))){return result}if let Some(actual)=a.take_operational_error(){return Err(BodySyntaxFailure::Operational(actual))}result}fn expression(&self,_:&SettingExpressionInput<'_>)->Result<dm_syntax::SettingExpression,BodySyntaxFailure>{panic!("shared declaration preparation does not demand settings")}}
 #[test]fn complete_original_roles_share_native_tree_syntax_and_signature_work_and_aliases_keep_real_roots(){
  let text="/datum/shared\n    var/value=1\n/proc/shared(argument=1)\n    return argument\n";let source=Source(dm_preprocess::AcquiredSource::from_original_bytes(text.as_bytes().to_vec(),()));let seed=crate::checker_builtins::original_analysis_seed().unwrap();let executor=dm_exec::BuildExecutor::new(1).unwrap();let config=FrontendConfig{workers:1,engine:Some(seed.frontend_seed()),observer:None};let counter=Arc::new(AtomicUsize::new(0));let host=Arc::new(Host(counter.clone(),Default::default()))as Arc<dyn SettingExpressionQueries>;let mut state=RetainedSemanticTree::new();let project=Path::new("shared-complete.dme");let defines=Default::default();
  let first=Arc::new(super::super::build_for_checker_diagnostics_with_state_checked(project,&source,&defines,config,None,&executor,Some(&mut state),&host).unwrap());assert_eq!(first.preparation_purpose(),DiagnosticPreparationPurpose::OriginalSharedComplete);first.checker_source_view().unwrap();state.remember_analysis_frontend(project,&defines,Arc::clone(&first)).unwrap();let before=crate::procedure::signature_interpretations();
  let second=super::super::build_for_original_analysis_with_state_checked(project,&source,&defines,config,None,&executor,Some(&mut state),&host).unwrap();assert_eq!(crate::procedure::signature_interpretations(),before);assert!(Arc::ptr_eq(first.source_view().unwrap().tree(),second.source_view().unwrap().tree()));assert!(Arc::ptr_eq(&first.inner.syntax,&second.inner.syntax));assert_eq!(second.original_analysis_completeness(),Some(OriginalAnalysisCompleteness::Complete));second.checker_source_view().unwrap();
  let tree=Arc::clone(second.source_view().unwrap().tree());let mapping=Arc::clone(second.source_view().unwrap().mapping());drop(second);drop(first);drop(state);assert!(counter.load(Ordering::Acquire)>0);drop(tree);assert!(counter.load(Ordering::Acquire)>0,"source/archive alias retains actual original roots independently of remembered frontend");drop(mapping);host.with_declaration_admission(&mut |_|Ok(())).unwrap();assert_eq!(counter.load(Ordering::Acquire),0);
 }
}

#[cfg(test)]mod handlers_structural_purpose_tests{
 use super::*;
 struct Source{root:dm_preprocess::AcquiredSource}
 impl SourceProvider for Source{
  fn initial_environment(&self)->dm_preprocess::InitialEnvironment{dm_preprocess::InitialEnvironment::OriginalChecker0290}
  fn read(&self,_:&Path)->Result<String,String>{panic!("partial original purpose cannot reopen/relex through legacy read")}
  fn original_raw_source_admitted(&self,_:&Path,_:usize,_:&mut dyn FnMut(usize)->std::io::Result<()>,before:&mut dyn FnMut(dm_preprocess::OriginalRawAllocationPlan<'_>)->std::io::Result<()>,acquired:&mut dyn FnMut(&dm_preprocess::SourceAcquisitionLease)->std::io::Result<()>)->std::io::Result<Option<dm_preprocess::SourceAcquisitionLease>>{before(dm_preprocess::OriginalRawAllocationPlan::new(&[],0,0,0,false,false))?;acquired(self.root.lease())?;Ok(Some(self.root.lease().clone()))}
  fn original_source_bytes<'a>(&'a self,lease:&'a dm_preprocess::SourceAcquisitionLease)->std::io::Result<Option<&'a[u8]>>{if !lease.same_binding(self.root.lease()){return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"foreign test subject lease"))}Ok(Some(self.root.prepared().original().as_bytes()))}
  fn acquired_source(&self,_:&Path)->Result<Option<dm_preprocess::AcquiredSource>,String>{Ok(Some(self.root.clone()))}
  fn source_acquisition(&self,_:&Path,text:&dm_preprocess::SourceText)->Option<dm_preprocess::AcquiredSource>{self.root.prepared().original().same_view(text).then(||self.root.clone())}
 }
 #[test]fn identical_native_graph_never_promotes_partial_purpose_to_full_or_checker(){
  let provider=Source{root:dm_preprocess::AcquiredSource::synthetic_utf8(dm_preprocess::SourceText::from("/datum/probe\n/proc/test(datum/act/A)\n    return\n".to_owned()),())};let path=Path::new("synth.dme");let seed=crate::checker_builtins::original_analysis_seed().unwrap();let executor=dm_exec::BuildExecutor::new(1).unwrap();let host=crate::frontend::declaration_checked_tests::original_test_host();
  let build=||super::super::build_for_original_handlers_structural_checked(path,&provider,FrontendConfig{workers:1,engine:Some(seed.frontend_seed()),observer:None},None,&executor,&host).unwrap();
  let partial=build();assert_eq!(partial.preparation_purpose(),DiagnosticPreparationPurpose::OriginalHandlersStructuralComplete);assert_eq!(partial.original_analysis_completeness(),None);assert!(partial.checker_source_view().is_err());let structural=partial.handlers_structural_source().unwrap();assert_eq!(structural.completeness(),OriginalAnalysisCompleteness::Complete);assert!(structural.view().tree().lookup_type(dm_ir::SymbolId::of("/datum/probe")).is_some());assert!(structural.view().original_analysis_completeness().is_none());assert!(partial.try_into_compilable().is_err());
  let mut retained=RetainedSemanticTree::new();let partial=Arc::new(build());assert!(retained.remember_analysis_frontend(path,&Default::default(),partial).is_err());assert!(retained.with_remembered_analysis_source(|_|()).unwrap().is_none());
  let full=super::super::build_for_original_analysis_with_state_checked(path,&provider,&Default::default(),FrontendConfig{workers:1,engine:Some(seed.frontend_seed()),observer:None},None,&executor,None,&host).unwrap();assert_eq!(full.original_analysis_completeness(),Some(OriginalAnalysisCompleteness::Complete));assert!(full.handlers_structural_source().is_err());full.checker_source_view().unwrap();
 }
}

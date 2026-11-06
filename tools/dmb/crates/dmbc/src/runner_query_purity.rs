//! Internal prepared-snapshot authority for the incremental purity producer.
//! There is intentionally no CLI/public cutover until all effect categories
//! have independent old-checker coverage. Never reconstruct a policy from disk.
use super::SourceSnapshot;
#[cfg(test)]thread_local!{static ORIGINAL_SCOPE_LOADS:std::cell::Cell<usize>=const{std::cell::Cell::new(0)};}
#[cfg(test)]pub(super) fn original_scope_loads_on_current_thread()->usize{ORIGINAL_SCOPE_LOADS.with(|count|count.get())}
use dm_analysis::{
    check_policy::{CheckerPolicy, WarningLevel},
    checker_effects::{EffectInput, Produced},
};
use std::{path::Path, sync::Arc};
pub(crate) struct PurityScope<'a> {
    snapshot: &'a SourceSnapshot,
    tree: &'a dm_tree::SemanticTree,
    policy: &'a CheckerPolicy,
    policy_key: u128,
    configuration: &'a dm_analysis::check_configuration::Loaded,
}
impl PurityScope<'_> {
    pub(crate) fn validate(
        &self,
        db: &crate::query_db::QueryDb,
        input: &Arc<EffectInput>,
    ) -> Result<(), String> {
        let capture = self
            .snapshot
            .named_policy_capture(self.tree)
            .map_err(|e| e.to_string())?;
        if !Arc::ptr_eq(capture.policy().archive(), input.archive())
            || !self.snapshot.matches_tree(self.tree)
            || !self
                .snapshot
                .native_raw_queries
                .as_ref()
                .is_some_and(|q| std::ptr::eq(q.as_ref(), db))
        {
            return Err(
                "purity scope is not the exact current published archive/Db/policy frame".into(),
            );
        }
        input.validate_current(capture.policy().archive(), db)?;
        // A None config is still a captured, revision-qualified selection. Never
        // skip the frame/owner checks on that path or on a cached report.
        if self.snapshot.policy_revision.is_none() {
            return Err("purity policy frame unissued".into());
        }
        Ok(())
    }
    pub(crate) fn policy(&self) -> &CheckerPolicy {
        self.policy
    }
    pub(crate) fn configuration(&self)->&dm_analysis::check_configuration::Loaded{self.configuration}
    pub(crate) fn policy_key(&self) -> u128 {
        self.policy_key
    }
}
fn hash_policy(policy: &CheckerPolicy, frame: u128, configuration: &Path) -> u128 {
    fn level(x: WarningLevel) -> u8 {
        match x {
            WarningLevel::Error => 0,
            WarningLevel::Warning => 1,
            WarningLevel::Info => 2,
            WarningLevel::Hint => 3,
            WarningLevel::Disabled => 4,
            WarningLevel::Unset => 5,
        }
    }
    let mut h = xxhash_rust::xxh3::Xxh3::new();
    h.update(b"native-purity-config-v1\0");
    h.update(&frame.to_le_bytes());
    h.update(configuration.as_os_str().as_encoded_bytes());
    h.update(&[level(policy.display_error_level)]);
    for (name, value) in &policy.diagnostics {
        h.update(&(name.len() as u64).to_le_bytes());
        h.update(name.as_bytes());
        h.update(&[level(*value)]);
    }
    h.digest128()
}
impl SourceSnapshot {
    /// Caller may retain the immutable input between queries; all subsequent
    /// accesses must supply this exact current snapshot again, never a cached
    /// owner token alone. Strong source ownership remains the original archive.
    pub(crate) fn native_purity_input(
        &self,
        tree: &dm_tree::SemanticTree,
    ) -> Result<Arc<EffectInput>, String> {
        let c = self.named_policy_capture(tree).map_err(|e| e.to_string())?;
        EffectInput::new(
            Arc::clone(c.policy().archive()),
            tree.checker_builtin_profile()
                .ok_or("purity builtin profile unavailable")?,
        )
    }
    pub(crate) fn native_purity_report(
        &self,
        input: &Arc<EffectInput>,
        environment: &Path,
        explicit: Option<&Path>,
        tree: &dm_tree::SemanticTree,
    ) -> std::io::Result<Arc<Vec<Produced>>> {
        self.native_effect_report(input, environment, explicit, tree, false)
    }
    pub(crate) fn native_sleep_report(
        &self,
        input: &Arc<EffectInput>,
        environment: &Path,
        explicit: Option<&Path>,
        tree: &dm_tree::SemanticTree,
    ) -> std::io::Result<Arc<Vec<Produced>>> {
        self.native_effect_report(input, environment, explicit, tree, true)
    }
    fn native_effect_report(&self,input:&Arc<EffectInput>,environment:&Path,explicit:Option<&Path>,tree:&dm_tree::SemanticTree,sleeping:bool)->std::io::Result<Arc<Vec<Produced>>>{
        self.with_effect_scope(input,environment,explicit,tree,|db,scope|if sleeping{db.native_sleep_report(input,scope)}else{db.native_purity_report(input,scope)})
    }
    /// Additive original page input; ordinary bounded whole-report input stays.
    pub(crate) fn native_effect_source_input(&self,tree:&dm_tree::SemanticTree)->Result<Arc<EffectInput>,String>{let capture=self.named_policy_capture(tree).map_err(|e|e.to_string())?;EffectInput::source_pages(Arc::clone(capture.policy().archive()),tree.checker_builtin_profile().ok_or("effect source builtin profile unavailable")?)}
    pub(crate) fn native_effect_source_page(&self,input:&Arc<EffectInput>,start:usize,width:usize,environment:&Path,explicit:Option<&Path>,tree:&dm_tree::SemanticTree)->std::io::Result<Arc<crate::query_db::NativeEffectPage>>{
        self.with_effect_scope(input,environment,explicit,tree,|db,scope|db.native_effect_source_page(input,scope,start,width))
    }
    pub(crate) fn native_effect_source_graph(&self,input:&Arc<EffectInput>,width:usize,environment:&Path,explicit:Option<&Path>,tree:&dm_tree::SemanticTree)->std::io::Result<Arc<crate::query_db::NativeEffectGraph>>{self.with_effect_scope(input,environment,explicit,tree,|db,scope|db.native_effect_source_graph(input,scope,width))}
    pub(crate) fn native_effect_source_summary(&self,input:&Arc<EffectInput>,width:usize,environment:&Path,explicit:Option<&Path>,tree:&dm_tree::SemanticTree)->std::io::Result<Arc<crate::query_db::NativeEffectSummary>>{self.with_effect_scope(input,environment,explicit,tree,|db,scope|db.native_effect_source_summary(input,scope,width))}
    pub(crate) fn native_effect_source_report(&self,input:&Arc<EffectInput>,width:usize,phase:dm_analysis::checker_effects::EffectReportPhase,environment:&Path,explicit:Option<&Path>,tree:&dm_tree::SemanticTree)->std::io::Result<Arc<crate::query_db::NativeEffectReport>>{self.with_effect_scope(input,environment,explicit,tree,|db,scope|db.native_effect_source_report(input,scope,width,phase))}
    /// Exact bounded target-order window over the SAME complete global summary.
    pub(crate) fn native_effect_source_report_window(&self,input:&Arc<EffectInput>,width:usize,phase:dm_analysis::checker_effects::EffectReportPhase,start:usize,count:usize,environment:&Path,explicit:Option<&Path>,tree:&dm_tree::SemanticTree)->std::io::Result<Arc<crate::query_db::NativeEffectReport>>{self.with_effect_scope(input,environment,explicit,tree,|db,scope|db.native_effect_source_report_window(input,scope,width,phase,start,count))}
    fn with_effect_scope<T>(
        &self,
        input: &Arc<EffectInput>,
        environment: &Path,
        explicit: Option<&Path>,
        tree: &dm_tree::SemanticTree,
        operation: impl FnOnce(&crate::query_db::QueryDb,&PurityScope<'_>)->std::io::Result<T>,
    ) -> std::io::Result<T> {
        crate::daemon::control::checkpoint()?;
        let capture = self.named_policy_capture(tree)?;
        if !environment.is_absolute()
            || capture
                .compiled_source_file(environment)
                .is_none_or(|file| file.role() != dm_analysis::policy_inputs::PolicyRole::DmSource)
        {
            return Err(std::io::Error::other(
                "purity environment is not an original compiled source",
            ));
        }
        let loaded = super::named_policy::configuration(capture, environment, explicit)?;
        #[cfg(test)]ORIGINAL_SCOPE_LOADS.with(|count|count.set(count.get()+1));
        let frame = self
            .policy_revision
            .ok_or_else(|| std::io::Error::other("purity frame unissued"))?;
        let scope = PurityScope {
            snapshot: self,
            tree,
            policy: &loaded.policy,
            configuration: &loaded,
            policy_key: hash_policy(&loaded.policy, frame, &loaded.selected.path),
        };
        let db = self.native_raw_queries.as_ref().ok_or_else(|| {
            std::io::Error::other("purity current compiler query database unavailable")
        })?;
        scope.validate(db, input).map_err(std::io::Error::other)?;
        operation(db,&scope)
    }
}

#[cfg(test)]
#[path = "runner_query_purity_tests.rs"]
mod tests;

#[path="runner_query_effect_wire.rs"]mod effect_wire;

/// One private request-only issued input. No raw Arc escapes this retained slot.
/// EffectInput owns the existing archive; its body provider points weakly to Db.
pub(super) struct EffectRequestInput{input:Option<Arc<EffectInput>>,_lease:crate::query_db::EffectRequestInputLease}
impl Drop for EffectRequestInput{fn drop(&mut self){drop(self.input.take());}}
impl EffectRequestInput{pub(super) fn input(&self)->&Arc<EffectInput>{self.input.as_ref().expect("sealed actual request input")}pub(super) fn census(&self,census:&mut crate::heap_census::HeapCensus){if let Some(input)=&self.input{if census.arc_object("query_snapshot.effect_request_input",input){input.visit_storage(&mut|view|match view{dm_analysis::checker_effects::Storage::Buffer{owner,address,logical,capacity}=>{census.exposed_buffer(owner,address,logical,capacity);},dm_analysis::checker_effects::Storage::Unknown{owner,items}=>{census.observe_items(owner,items);census.unknown(owner,"effect input storage capacity unexposed");}});}}}}
impl SourceSnapshot{
 fn effect_request_input(&self,tree:&dm_tree::SemanticTree)->std::io::Result<&EffectRequestInput>{self.issued_effect_request_input(tree,false)}
 /// Must be selected before any mixed full-checker/effect question executes.
 /// This uses the SAME existing retained input slot, never a parallel BODY owner.
 pub(super) fn original_checker_request_input(&self,tree:&dm_tree::SemanticTree)->std::io::Result<&EffectRequestInput>{self.issued_effect_request_input(tree,true)}
 fn issued_effect_request_input(&self,tree:&dm_tree::SemanticTree,original:bool)->std::io::Result<&EffectRequestInput>{
  crate::daemon::control::checkpoint()?;let capture=self.named_policy_capture(tree)?;let db=self.native_raw_queries.as_ref().ok_or_else(||std::io::Error::new(std::io::ErrorKind::NotConnected,"effect request current query database unavailable"))?;let profile=tree.checker_builtin_profile().ok_or_else(||std::io::Error::other("effect request builtin profile unavailable"))?;
  if self.native_effect_request_input.get().is_none(){let bytes=std::mem::size_of::<std::sync::OnceLock<EffectRequestInput>>().checked_add(std::mem::size_of::<EffectInput>()).and_then(|n|n.checked_add(2*std::mem::size_of::<usize>()+128)).and_then(|n|n.checked_add(if original{std::mem::size_of::<dm_tree::diagnostic_declarations::DiagnosticDeclarationReceipt>()+2*std::mem::size_of::<usize>()}else{0})).ok_or_else(||std::io::Error::new(std::io::ErrorKind::OutOfMemory,"effect request fixed input capacity overflow"))?;let lease=db.reserve_effect_request_input(bytes)?;let input=if original{let receipt=self.diagnostic_declarations.as_ref().ok_or_else(||std::io::Error::other("whole checker input requires authentic diagnostic declaration receipt"))?;EffectInput::original_checker_source(Arc::clone(capture.policy().archive()),profile,receipt,db.as_ref())}else{EffectInput::source_pages(Arc::clone(capture.policy().archive()),profile)}.map_err(std::io::Error::other)?;input.validate_current(capture.policy().archive(),db.as_ref()).map_err(std::io::Error::other)?;let owner=EffectRequestInput{input:Some(input),_lease:lease};let _=self.native_effect_request_input.set(owner);}
  let owner=self.native_effect_request_input.get().expect("actual retained request input initialized");let input=owner.input.as_ref().expect("sealed request input remains owned");if input.profile()!=profile{return Err(std::io::Error::other("effect request cached profile differs"))}if original&&!input.is_original_checker_source(){return Err(std::io::Error::other("whole checker purpose must be bound before ordinary effect contribution evaluation"))}if input.is_original_checker_source(){input.require_original_checker_source().map_err(std::io::Error::other)?;}input.validate_current(capture.policy().archive(),db.as_ref()).map_err(std::io::Error::other)?;
  Ok(owner)
 }
 pub(crate) fn write_native_effect_request(&self,width:usize,target_window:usize,environment:&Path,explicit:Option<&Path>,tree:&dm_tree::SemanticTree,output:&mut impl std::io::Write)->std::io::Result<()>{let owner=self.effect_request_input(tree)?;let input=owner.input.as_ref().expect("sealed actual input");
  self.write_native_effect_reports_exhausted(input,width,target_window,environment,explicit,tree,output)
 }
}

impl SourceSnapshot{
 /// The checker observes the exact BODY outcome also consumed by PAGE/effects.
 /// Callers cannot supply another input or promote an ordinary selected frame.
 pub(super) fn with_original_checker_body<T>(&self,ordinal:usize,environment:&Path,explicit:Option<&Path>,tree:&dm_tree::SemanticTree,consume:impl FnOnce(&dm_analysis::checker_effects::BodyEffects)->std::io::Result<T>)->std::io::Result<T>{
  let owner=self.original_checker_request_input(tree)?;let input=owner.input();
  let source=dm_analysis::checker_effects::EffectSource::new(input.archive(),input.profile()).map_err(|failure|match failure{dm_analysis::policy_body_demand::PolicyFailure::Operational(actual)=>actual,dm_analysis::policy_body_demand::PolicyFailure::Unsupported(message)=>std::io::Error::other(message.0)})?;
  let mut rank=None;for index in 0..source.len(){crate::daemon::control::checkpoint()?;if source.original_ordinal(index)==Some(ordinal){rank=Some(index);break}}
  let rank=rank.ok_or_else(||std::io::Error::other("checker ordinal is not an actual original source body"))?;
  let page=self.native_effect_source_page(input,rank,1,environment,explicit,tree)?;
  let pending=page.with_original_body(0,input,consume);match pending{Ok(Err(actual))|Err(dm_analysis::policy_body_demand::PolicyFailure::Operational(actual))=>Err(actual),other=>{crate::daemon::control::checkpoint()?;input.validate_current(input.archive(),self.native_raw_queries.as_ref().ok_or_else(||std::io::Error::other("checker Db absent"))?.as_ref()).map_err(std::io::Error::other)?;match other{Ok(Ok(value))=>Ok(value),Err(dm_analysis::policy_body_demand::PolicyFailure::Operational(actual))=>Err(actual),Err(dm_analysis::policy_body_demand::PolicyFailure::Unsupported(message))=>Err(std::io::Error::other(message.0)),_=>unreachable!()}}}
 }
 /// Ordered BODY prelude/body phases over the SAME actual cached contributions.
 /// Global declaration/frontend and final graph/keyword phases remain separate.
 pub(super) fn visit_original_body_diagnostics(&self,environment:&Path,explicit:Option<&Path>,tree:&dm_tree::SemanticTree,consume:impl FnMut(usize,&dm_analysis::checker_effects::OriginalBodyDiagnostic)->std::io::Result<()>)->std::io::Result<()>{let owner=self.original_checker_request_input(tree)?;let input=owner.input();self.with_effect_scope(input,environment,explicit,tree,|db,scope|db.visit_cached_original_diagnostics(input,||scope.validate(db,input).map_err(std::io::Error::other),consume))}

}

/// Real phases borrow ONE actual current configuration/scope. Public private
/// wrappers preserve their existing API; no scope, model or BODY cache is added.
pub(super) enum OriginalDeclarationAndBody<'a>{Declaration(&'a dm_analysis::checks_variable_visibility::Produced),Body{ordinal:usize,row:&'a dm_analysis::checker_effects::OriginalBodyDiagnostic}}
pub(super) enum OriginalThroughKeywords<'a>{Source(OriginalDeclarationAndBody<'a>),Keyword{findings:&'a dm_analysis::checks_keyword_overrides::Findings<'a>,row:&'a dm_analysis::checks_keyword_overrides::Finding}}
pub(super) enum OriginalThroughGraph<'a>{Source(OriginalThroughKeywords<'a>),Graph(&'a dm_analysis::checker_effects::Produced)}
pub(super) enum OriginalThroughReaderDeclarations<'a>{Declaration(dm_analysis::checks_proc_visibility::Finding<'a>),Semantic(OriginalThroughGraph<'a>)}
impl SourceSnapshot{
 fn visit_original_declarations_and_bodies_in_scope(&self,input:&Arc<EffectInput>,tree:&dm_tree::SemanticTree,db:&crate::query_db::QueryDb,scope:&PurityScope<'_>,mut consume:impl FnMut(OriginalDeclarationAndBody<'_>)->std::io::Result<()>)->std::io::Result<()>{
  db.with_original_declarations(input,tree,||scope.validate(db,input).map_err(std::io::Error::other),|findings|{for row in findings.rows(){crate::daemon::control::checkpoint()?;consume(OriginalDeclarationAndBody::Declaration(row))?;}Ok(())})?;
  db.visit_cached_original_diagnostics(input,||scope.validate(db,input).map_err(std::io::Error::other),|ordinal,row|consume(OriginalDeclarationAndBody::Body{ordinal,row}))
 }
 fn visit_original_through_keywords_in_scope(&self,input:&Arc<EffectInput>,tree:&dm_tree::SemanticTree,db:&crate::query_db::QueryDb,scope:&PurityScope<'_>,mut consume:impl FnMut(OriginalThroughKeywords<'_>)->std::io::Result<()>)->std::io::Result<()>{
  self.visit_original_declarations_and_bodies_in_scope(input,tree,db,scope,|row|consume(OriginalThroughKeywords::Source(row)))?;
  db.with_cached_original_keyword_overrides(input,tree,||scope.validate(db,input).map_err(std::io::Error::other),|findings|{if !findings.belongs_to(input.archive()){return Err(std::io::Error::other("keyword finalization result belongs to another archive"))}for row in findings.rows(){crate::daemon::control::checkpoint()?;consume(OriginalThroughKeywords::Keyword{findings,row})?;}Ok(())})
 }
 fn visit_original_through_graph_in_scope(&self,input:&Arc<EffectInput>,tree:&dm_tree::SemanticTree,db:&crate::query_db::QueryDb,scope:&PurityScope<'_>,mut consume:impl FnMut(OriginalThroughGraph<'_>)->std::io::Result<()>)->std::io::Result<()>{
  self.visit_original_through_keywords_in_scope(input,tree,db,scope,|row|consume(OriginalThroughGraph::Source(row)))?;
  use dm_analysis::checker_effects::{EffectReportPhase,ProducedPhase};let total=input.archive().callables().source_order().len();
  for(phase,issued)in[(EffectReportPhase::Sleep,ProducedPhase::SleepGraph),(EffectReportPhase::Purity,ProducedPhase::PurityGraph)]{
   let mut start=0;while start<total{crate::daemon::control::checkpoint()?;let count=256usize.min(total-start);let rows=db.native_effect_source_report_window(input,scope,32,phase,start,count)?;for row in rows.iter(){crate::daemon::control::checkpoint()?;if row.phase()==issued{consume(OriginalThroughGraph::Graph(row))?;}}drop(rows);scope.validate(db,input).map_err(std::io::Error::other)?;start=start.checked_add(count).ok_or_else(||std::io::Error::new(std::io::ErrorKind::OutOfMemory,"original graph delivery progress overflow"))?;}
  }
  scope.validate(db,input).map_err(std::io::Error::other)
 }
 fn visit_original_through_reader_declarations_in_scope(&self,input:&Arc<EffectInput>,tree:&dm_tree::SemanticTree,db:&crate::query_db::QueryDb,scope:&PurityScope<'_>,mut consume:impl FnMut(OriginalThroughReaderDeclarations<'_>)->std::io::Result<()>)->std::io::Result<()>{
  db.visit_original_reader_declarations(input,||scope.validate(db,input).map_err(std::io::Error::other),|row|consume(OriginalThroughReaderDeclarations::Declaration(row)))?;
  self.visit_original_through_graph_in_scope(input,tree,db,scope,|row|consume(OriginalThroughReaderDeclarations::Semantic(row)))
 }
 pub(super) fn visit_original_declarations_and_bodies(&self,environment:&Path,explicit:Option<&Path>,tree:&dm_tree::SemanticTree,consume:impl FnMut(OriginalDeclarationAndBody<'_>)->std::io::Result<()>)->std::io::Result<()>{let owner=self.original_checker_request_input(tree)?;let input=owner.input();self.with_effect_scope(input,environment,explicit,tree,|db,scope|self.visit_original_declarations_and_bodies_in_scope(input,tree,db,scope,consume))}
 pub(super) fn visit_original_through_keywords(&self,environment:&Path,explicit:Option<&Path>,tree:&dm_tree::SemanticTree,consume:impl FnMut(OriginalThroughKeywords<'_>)->std::io::Result<()>)->std::io::Result<()>{let owner=self.original_checker_request_input(tree)?;let input=owner.input();self.with_effect_scope(input,environment,explicit,tree,|db,scope|self.visit_original_through_keywords_in_scope(input,tree,db,scope,consume))}
 pub(super) fn visit_original_through_graph(&self,environment:&Path,explicit:Option<&Path>,tree:&dm_tree::SemanticTree,consume:impl FnMut(OriginalThroughGraph<'_>)->std::io::Result<()>)->std::io::Result<()>{let owner=self.original_checker_request_input(tree)?;let input=owner.input();self.with_effect_scope(input,environment,explicit,tree,|db,scope|self.visit_original_through_graph_in_scope(input,tree,db,scope,consume))}
 pub(super) fn visit_original_through_reader_declarations(&self,environment:&Path,explicit:Option<&Path>,tree:&dm_tree::SemanticTree,consume:impl FnMut(OriginalThroughReaderDeclarations<'_>)->std::io::Result<()>)->std::io::Result<()>{let owner=self.original_checker_request_input(tree)?;let input=owner.input();self.with_effect_scope(input,environment,explicit,tree,|db,scope|self.visit_original_through_reader_declarations_in_scope(input,tree,db,scope,consume))}
 /// Old CLI visibility follows each real producer's registration. Graph rows
 /// already registered their levels; raw context still retains all real Hints.
 pub(super) fn visit_original_cli_diagnostics(&self,environment:&Path,explicit:Option<&Path>,tree:&dm_tree::SemanticTree,consume:impl FnMut(OriginalThroughReaderDeclarations<'_>,dm_analysis::check_policy::DiagnosticSeverity)->std::io::Result<()>)->std::io::Result<()>{
  let owner=self.original_checker_request_input(tree)?;let input=owner.input();self.with_effect_scope(input,environment,explicit,tree,|db,scope|{
   self.visit_original_cli_diagnostics_in_scope(input,tree,db,scope,consume)
  })
 }
 fn visit_original_cli_diagnostics_in_scope(&self,input:&Arc<EffectInput>,tree:&dm_tree::SemanticTree,db:&crate::query_db::QueryDb,scope:&PurityScope<'_>,mut consume:impl FnMut(OriginalThroughReaderDeclarations<'_>,dm_analysis::check_policy::DiagnosticSeverity)->std::io::Result<()>)->std::io::Result<()> {
   self.visit_original_through_reader_declarations_in_scope(input,tree,db,scope,|row|{use dm_analysis::check_policy::DiagnosticSeverity as S;let level=match &row{
    OriginalThroughReaderDeclarations::Declaration(finding)=>scope.policy().register(finding.registration_tag(),finding.original_fixed_level().ok_or_else(||std::io::Error::other("original reader diagnostic lacks genuine default severity"))?),
    OriginalThroughReaderDeclarations::Semantic(OriginalThroughGraph::Source(OriginalThroughKeywords::Source(OriginalDeclarationAndBody::Declaration(finding))))=>scope.policy().register(finding.registration_tag(),finding.default_severity()),
    OriginalThroughReaderDeclarations::Semantic(OriginalThroughGraph::Source(OriginalThroughKeywords::Source(OriginalDeclarationAndBody::Body{row,..})))=>scope.policy().register(row.registration_tag(),row.default_level()),
    OriginalThroughReaderDeclarations::Semantic(OriginalThroughGraph::Source(OriginalThroughKeywords::Keyword{..}))=>{
     use dm_analysis::checks_keyword_overrides::{DEFAULT_SEVERITY,REGISTRATION_TAG};
     scope.policy().register(Some(REGISTRATION_TAG),DEFAULT_SEVERITY)
    },
    OriginalThroughReaderDeclarations::Semantic(OriginalThroughGraph::Graph(row))=>Some(row.severity),
   };if let Some(level)=level.filter(|level|*level<=S::Info){consume(row,level)?;}Ok(())})?;scope.validate(db,input).map_err(std::io::Error::other)
 }
}

#[path = "runner_query_original_ordered_wire.rs"]
mod original_ordered_wire;

// Selected authentic current semantic producer, not a default checker cutover.
impl SourceSnapshot{
 pub(crate) fn write_current_undefined_variable(
    &self,
    ordinal: u32,
    environment: &Path,
    explicit: Option<&Path>,
    tree: &dm_tree::SemanticTree,
    output: &mut impl std::io::Write,
 ) -> std::io::Result<()> {
    use dm_analysis::{check_policy::DiagnosticSeverity, checks_undefined_variable::CurrentUndefinedDisposition};
    use std::io;

    let owner = self.original_checker_request_input(tree)?;
    let input = owner.input();
    self.with_effect_scope(input, environment, explicit, tree, |db, scope| {
        let loaded = scope.configuration();
        let policy_revision = self.policy_revision.ok_or_else(|| io::Error::other("Original checker policy revision unavailable"))?;
        let metadata = serde_json::json!({
            "row": "source_native_configured_checker",
            "schema": "dm-session-source-query-v1",
            "semantic_revision": format!("{:032x}", tree.identity()),
            "source_revision": format!("{:032x}", self.source_revision),
            "policy_revision": format!("{:032x}", policy_revision),
            "ordinal": ordinal,
            "family": "current_undefined_variable",
            "environment": environment,
            "configuration": loaded.selected.path,
            "configuration_explicit": loaded.selected.explicit,
            "configuration_present": loaded.present,
            "configuration_schema": "complete_pinned_checker_schema",
            "full_checker_parity": false,
        });
        let header = serde_json::to_vec(&metadata).map_err(io::Error::other)?;
        output.write_all(header.strip_suffix(b"}").ok_or_else(|| io::Error::other("invalid current checker metadata object"))?)?;
        output.write_all(b",\"diagnostics\":[")?;

        // The caller owns a bounded reply buffer and publishes it only after
        // the complete graph visit succeeds. Borrow one diagnostic at a time.
        let severity = scope.policy().register(None, DiagnosticSeverity::Error);
        let mut first = true;
        let disposition = db.visit_current_variable_diagnostics(input, scope, ordinal as usize, |row| {
            let Some(severity) = severity else { return Ok(()) };
            let origin = input.archive().borrowed_source_note_point(row.span.start).map_err(io::Error::other)?;
            let (file, line, column) = origin.reported_coordinates();
            if !first { output.write_all(b",")?; }
            first = false;
            serde_json::to_writer(&mut *output, &serde_json::json!({
                "family": row.diagnostic.family,
                "severity": super::named_policy::severity(severity),
                "file": file,
                "line": line,
                "column": column,
                "expanded_span": [row.span.start, row.span.end],
                "expression_span": [row.expression_span.start, row.expression_span.end],
                "message": row.diagnostic.message,
                "notes": row.diagnostic.notes.iter().map(|note| note.legacy_text()).collect::<Vec<_>>(),
            })).map_err(io::Error::other)
        })?;
        let disposition = match disposition {
            CurrentUndefinedDisposition::Evaluated => "evaluated",
            CurrentUndefinedDisposition::SkippedOriginal => "skipped_original",
        };
        output.write_all(b"],\"disposition\":")?;
        serde_json::to_writer(&mut *output, disposition).map_err(io::Error::other)?;
        output.write_all(b"}\n")
    })
 }
 pub(super) fn visit_current_variable_diagnostics(&self,ordinal:usize,environment:&Path,explicit:Option<&Path>,tree:&dm_tree::SemanticTree,consume:impl FnMut(dm_analysis::checks_undefined_variable::CurrentUndefinedRow<'_>)->std::io::Result<()>)->std::io::Result<dm_analysis::checks_undefined_variable::CurrentUndefinedDisposition>{
  let owner=self.original_checker_request_input(tree)?;let input=owner.input();self.with_effect_scope(input,environment,explicit,tree,|db,scope|db.visit_current_variable_diagnostics(input,scope,ordinal,consume))
 }
}
#[cfg(test)]#[path="runner_query_current_variables_tests.rs"]mod current_variables_tests;

#[cfg(test)]#[path="runner_query_current_prefix_tests.rs"]mod current_prefix_tests;

#[cfg(test)]#[path="runner_query_current_callable_tests.rs"]mod current_callable_tests;


impl SourceSnapshot{
 pub(super) fn visit_current_selected_diagnostics(&self,ordinal:usize,environment:&Path,explicit:Option<&Path>,tree:&dm_tree::SemanticTree,consume:impl FnMut(crate::query_db::CurrentSelectedDiagnostic<'_>)->std::io::Result<()>)->std::io::Result<dm_analysis::checks_undefined_variable::CurrentUndefinedDisposition>{
  let owner=self.original_checker_request_input(tree)?;let input=owner.input();self.with_effect_scope(input,environment,explicit,tree,|db,scope|db.visit_current_selected_diagnostics(input,scope,ordinal,consume))
 }
}
